"""Разбор заголовка GGUF: метаданные, список тензоров и геометрия памяти модели.

Комплект не должен зависеть от тулчейна Страты и от хранилища скриптов, поэтому разбор
живёт здесь. За данных мы не отвечаемся: читаются только magic/счётчики, KV-ключи и список
тензоров (имя, форма, dtype, offset). Байт на тензор берётся из РАЗНОСТИ offset'ов, а не из
таблицы типов, которую можно перепутать; таблица нужна лишь чтобы показать BPW. Сумма
разностей обязана равняться `file_size - data_start` - внутренний контроль меры.

Зачем это нужно `recommend.py`: максимальное окно и `--n-cpu-moe` получаются из арифметики
«плотная часть в VRAM + KV на токен x окно + GDN-состояние + прочее», а все четыре слагаемых
берутся из заголовка, а не из рассуждений о названии кванта.

    python kit\\gguf_meta.py --gguf model.gguf     # JSON с геометрией
    python kit\\gguf_meta.py --selftest               # мини-GGUF + саботаж-контроли
"""
from __future__ import annotations

import argparse
import json
import pathlib
import struct
import sys
import tempfile

MIB = 1024 ** 2
GIB = 1024 ** 3

# Индексы и размеры - из первичника: enum ggml_type (ggml/include/ggml.h), тела struct
# block_* и их static_assert (ggml/src/ggml-common.h), таблица type_traits[].type_size /
# .blck_size (ggml/src/ggml.c). Удалённые типы сохраняют слоты, поэтому нумерация НЕ подрядная:
# q4_0 = 2, а не 3; iq4_xs = 23, а не 20.
# Формат: индекс -> (имя, элементов в блоке, байт в блоке).
# Размеры ПОДТВЕРЖЕНЫ ЭМПИРИЧЕСКИ: по разностям offset в реальных GGUF (6 моделей на стенде)
# дробь «байт/элемент» даёт ровно эти числа - q8_0 8.5 bpw, iq2_s 2.5625, iq4_xs 4.25.
GGML_TYPE = {
    0: ("f32", 1, 4), 1: ("f16", 1, 2), 2: ("q4_0", 32, 18), 3: ("q4_1", 32, 20),
    6: ("q5_0", 32, 22), 7: ("q5_1", 32, 24), 8: ("q8_0", 32, 34), 9: ("q8_1", 32, 36),
    10: ("q2_K", 256, 84), 11: ("q3_K", 256, 110), 12: ("q4_K", 256, 144),
    13: ("q5_K", 256, 176), 14: ("q6_K", 256, 210), 15: ("q8_K", 256, 292),
    16: ("iq2_xxs", 256, 66), 17: ("iq2_xs", 256, 74), 18: ("iq3_xxs", 256, 98),
    19: ("iq1_s", 256, 50), 20: ("iq4_nl", 32, 18), 21: ("iq3_s", 256, 110),
    22: ("iq2_s", 256, 82), 23: ("iq4_xs", 256, 136), 24: ("i8", 1, 1), 25: ("i16", 1, 2),
    26: ("i32", 1, 4), 27: ("i64", 1, 8), 28: ("f64", 1, 8), 29: ("iq1_m", 256, 56),
    30: ("bf16", 1, 2), 34: ("tq1_0", 256, 54), 35: ("tq2_0", 256, 66),
    39: ("mxfp4", 32, 17), 40: ("nvfp4", 64, 36), 41: ("q1_0", 128, 18), 42: ("q2_0", 64, 18),
}
# Байт на элемент KV-кэша ВЫЧИСЛЯЕТСЯ из той же таблицы: ранее те же числа были продублированы
# здесь отдельным списком и разошлись с первичником (q8_0 33/32 вместо 34/32, iq4_nl 130/256
# вместо 18/32).
KV_BYTES = {GGML_TYPE[i][0]: GGML_TYPE[i][2] / GGML_TYPE[i][1]
            for i in (0, 1, 30, 8, 9, 7, 6, 3, 2, 20)}
KV_TYPES = tuple(KV_BYTES)
_TYPE_ID = {v[0]: k for k, v in GGML_TYPE.items()}


def tid(name: str) -> int:
    """Индекс типа по имени - чтобы в тестах не было магических чисел."""
    if name not in _TYPE_ID:
        raise GgufError(f"типа {name} нет в таблице ggml-типов")
    return _TYPE_ID[name]


def row_bytes(dtype: int, elements: int):
    """Сколько байт занимает блок квантованных значений: None, если тип неизвестен."""
    if dtype not in GGML_TYPE:
        return None
    _, blck, size = GGML_TYPE[dtype]
    if elements % blck:
        return None
    return elements // blck * size

MT = {0: "u8", 1: "i8", 2: "u16", 3: "i16", 4: "u32", 5: "i32", 6: "f32", 7: "bool",
      8: "string", 9: "array", 10: "u64", 11: "i64", 12: "f64"}
HEAD_LIMIT = 512 * MIB  # дальше уже данные тензоров: ключевая область столько не весит


class GgufError(ValueError):
    """Заголовок не разобрался - причина обязательна, «пусто» без ошибки недопустимо."""


class _Reader:
    def __init__(self, fh):
        self.fh = fh
        self.buf = b""
        self.pos = 0

    def need(self, n: int) -> bytes:
        while len(self.buf) < n:
            chunk = self.fh.read(max(1 << 20, n - len(self.buf)))
            if not chunk:
                raise GgufError(f"файл кончился на смещении {self.pos}: заголовок неполный")
            self.buf += chunk
        if self.pos + n > HEAD_LIMIT and self.pos > HEAD_LIMIT:
            raise GgufError(f"ключевая область превысила {HEAD_LIMIT >> 20} МиБ - это не заголовок")
        out, self.buf = self.buf[:n], self.buf[n:]
        self.pos += n
        return out

    def u(self, fmt: str):
        return struct.unpack("<" + fmt, self.need(struct.calcsize("<" + fmt)))[0]

    def s(self) -> str:
        n = self.u("Q")
        if n > 64 * MIB:
            raise GgufError(f"неправдомерная длина строки {n}")
        return self.need(n).decode("utf-8", "replace")


def parse(path: pathlib.Path) -> dict:
    """Метаданные и список тензоров. Ничего не додумывает: отсутствующее поле остаётся None."""
    path = pathlib.Path(path)
    if not path.is_file():
        raise GgufError(f"нет файла {path}")
    with path.open("rb") as fh:
        r = _Reader(fh)
        if r.need(4) != b"GGUF":
            raise GgufError(f"{path.name}: это не GGUF (magic не совпал)")
        ver = r.u("I")
        big = ver >= 2
        n_tensors = r.u("Q" if big else "I")
        n_kv = r.u("Q" if big else "I")

        def value(t: int):
            if t not in MT:
                raise GgufError(f"неизвестный тип метаданных {t}")
            name = MT[t]
            if name == "string":
                return r.s()
            if name == "array":
                et, cnt = r.u("I"), r.u("Q")
                if et == 9:
                    raise GgufError("вложенные массивы в метаданных GGUF не ожидались")
                return [value(et) for _ in range(cnt)]
            if name == "bool":
                return r.need(1)[0] != 0
            return r.u({"u8": "B", "i8": "b", "u16": "H", "i16": "h", "u32": "I", "i32": "i",
                        "f32": "f", "u64": "Q", "i64": "q", "f64": "d"}[name])

        kv = {}
        for _ in range(n_kv):
            key = r.s()
            kv[key] = value(r.u("I"))
        align = int(kv.get("general.alignment", 32)) or 32
        tensors = []
        for _ in range(n_tensors):
            nm = r.s()
            dims = [r.u("Q" if big else "I") for _ in range(r.u("I"))]
            tensors.append({"name": nm, "dims": dims, "dtype": r.u("I"), "off": r.u("Q")})
        data_start = (r.pos + align - 1) // align * align
    out = {"version": ver, "metadata": kv, "tensors": tensors, "data_start": data_start,
           "file_size": path.stat().st_size, "path": str(path)}
    size_from_offsets(out)
    return out


def size_from_offsets(out: dict) -> bool:
    """Байты тензора = разность offset'ов; внутренний контроль суммы против data-секции."""
    ts = out["tensors"]
    if not ts:
        raise GgufError("в файле нет ни одного тензора - геометрию взять неоткуда")
    order = sorted(ts, key=lambda t: t["off"])
    total_data = out["file_size"] - out["data_start"]
    if total_data <= 0:
        raise GgufError(f"data-секция невозможна: файл {out['file_size']} Б, "
                        f"данные начинаются с {out['data_start']} Б")
    for i, t in enumerate(order):
        t["bytes"] = (order[i + 1]["off"] - t["off"]) if i + 1 < len(order) else total_data - t["off"]
        if t["bytes"] < 0:
            raise GgufError(f"смещение тензора {t['name']} ({t['off']}) вышло за data-секцию")
    if sum(t["bytes"] for t in ts) != total_data:
        raise GgufError(f"контроль не сошёлся: сумма разностей не равна data-секции "
                        f"({out['file_size']} - {out['data_start']})")
    out["data_bytes"] = total_data
    return True


def is_expert(name: str) -> bool:
    """MoE-эксперты: ffn_*_exps - единственное, что сдвигает --n-cpu-moe.

    shared MLP (`*_shexp`), router (`ffn_gate_inp`) и attention не сдвигаются: это проверялось
    прогоном, а не по названию.
    """
    return name.startswith("blk.") and "_exps." in name


def layer_of(name: str):
    p = name.split(".")
    return int(p[1]) if p[0] == "blk" and len(p) > 1 and p[1].isdigit() else None


def suffix(name: str) -> str:
    p = name.split(".")
    return ".".join(p[2:]) if len(p) > 2 else name


def bpw_audit(out: dict, min_bytes: int = 4096) -> dict:
    """Сверка табличного байт-на-вес с ЭМПИРИЧЕСКИМ (байты/элементы из разности offset'ов).

    Это защита от перепутанной нумерации ggml-типов: если индексу приписано чужое имя,
    эмпирический bpw не совпадёт с табличным, и мера это покажет, а не промолчит.
    Учитываются только достаточно крупные тензоры: выравнивание добавляет до 31 байта на
    тензор, и на маленьком весе это искажение больше самой погрешности.
    """
    agg: dict[int, list[int]] = {}
    skipped_small = skipped_dims = 0
    for t in out["tensors"]:
        if t["bytes"] < min_bytes:
            skipped_small += 1
            continue
        n = 1
        for d in t["dims"]:
            n *= d
        if n <= 0:
            skipped_dims += 1
            continue
        a = agg.setdefault(t["dtype"], [0, 0])
        a[0] += t["bytes"]
        a[1] += n
    rows, worst = [], 0.0
    for dt, (nb, ne) in sorted(agg.items()):
        emp = nb * 8.0 / ne
        name, blck, size = GGML_TYPE.get(dt, (f"type#{dt}", None, None))
        tab = size * 8.0 / blck if blck and size else None
        rel = abs(emp - tab) / tab if tab else None
        if rel is not None:
            worst = max(worst, rel)
        rows.append({"dtype": dt, "name": name, "elements": ne, "bytes": nb,
                     "bpw_empirical": round(emp, 4),
                     "bpw_table": round(tab, 4) if tab else None,
                     "rel_diff": round(rel, 5) if rel is not None else None})
    return {"rows": rows, "min_bytes": min_bytes, "skipped_small": skipped_small,
            "skipped_dims": skipped_dims, "max_rel_diff": round(worst, 5),
            "unknown_types": sorted({r["name"] for r in rows if r["name"].startswith("type#")}),
            "ok": bool(rows) and worst <= 0.02 and not any(r["bpw_table"] is None for r in rows)}


def geometry(out: dict, min_bytes: int = 4096) -> dict:
    """Всё, что нужно recommend.py:expert/dense, KV на токен по каждому типу, GDN, потолок окна."""
    md = out["metadata"]
    arch = md.get("general.architecture")
    if not arch:
        raise GgufError("в заголовке нет general.architecture - по такому метаданным не считать")
    pre = arch + "."
    tensors = out["tensors"]
    per_layer: dict[int, dict[str, int]] = {}
    expert_bytes = dense_bytes = 0
    expert_types: dict[str, int] = {}
    for t in tensors:
        if is_expert(t["name"]):
            expert_bytes += t["bytes"]
            nm = GGML_TYPE.get(t["dtype"], (f"type{t['dtype']}",))[0]
            expert_types[nm] = expert_types.get(nm, 0) + t["bytes"]
        else:
            dense_bytes += t["bytes"]
        L = layer_of(t["name"])
        if L is not None:
            d = per_layer.setdefault(L, {"exp": 0, "oth": 0})
            d["exp" if is_expert(t["name"]) else "oth"] += t["bytes"]

    def meta(key, default=None):
        return md.get(pre + key, default)

    n_layer = meta("block_count") or len(per_layer)
    kv_layers = sorted({layer_of(t["name"]) for t in tensors
                        if suffix(t["name"]) in ("attn_k.weight", "attn_v.weight",
                                                 "attn_keys.weight", "attn_values.weight")}
                       - {None})
    lin_layers = sorted({layer_of(t["name"]) for t in tensors
                         if suffix(t["name"]) == "attn_qkv.weight"} - {None} - set(kv_layers))
    head_kv = meta("attention.head_count_kv", 0)
    n_head = meta("attention.head_count") or 0
    embd = meta("embedding_length") or 0
    # Ключа key_length в заголовке может и не быть: llama.cpp в load_hparams берёт тогда
    # n_embd_head_k = n_embd / n_head (у stories260K: 64/8 = 8, ключей нет вовсе). Без этого
    # фолбэка KV выходил 0 байт на валидном заголовке, а recommend отказывался подбирать окно.
    kl = (meta("attention.key_length") or meta("attention.head_length")
          or (embd // n_head if n_head else 0))
    vl = meta("attention.value_length") or kl
    heads_by_layer = dict(enumerate(head_kv)) if isinstance(head_kv, list) else None

    per_token = {}
    for qname, bpe in KV_BYTES.items():
        tot = 0.0
        for L in kv_layers:
            h = (heads_by_layer or {}).get(L, head_kv) or 0
            tot += h * (kl + vl) * bpe
        per_token[qname] = tot

    nvh, ss, grp = meta("ssm.time_step_rank"), meta("ssm.state_size"), meta("ssm.group_count")
    inner, conv = meta("ssm.inner_size"), meta("ssm.conv_kernel")
    gdn_per_layer = 0.0
    if lin_layers and None not in (nvh, ss, grp, inner, conv):
        key_dim, val_dim = grp * ss, inner
        gdn_per_layer = nvh * ss * ss * 4.0 + (2 * key_dim + val_dim) * (conv - 1) * 4.0

    expert_per_layer = [v["exp"] for v in per_layer.values()]
    # Ряд по номерам слоёв, а не среднее: `--n-cpu-moe k` сдвигает именно ПЕРВЫЕ k слоёв, а
    # слои неравны (на heretic Q4_K_M разброс до 10 %), и на среднем числе ошибка лезет в
    # вердикт «влезло / не влезло».
    expert_by_layer = [per_layer.get(L, {}).get("exp", 0) for L in range(n_layer)]
    bpw = bpw_audit(out, min_bytes)
    return {
        "file": out["path"], "file_gib": out["file_size"] / GIB, "data_gib": out["data_bytes"] / GIB,
        "arch": arch, "name": md.get("general.name", ""),
        "block_count": n_layer, "kv_layers": len(kv_layers), "linear_layers": len(lin_layers),
        "head_count": meta("attention.head_count"), "head_kv": head_kv,
        "key_length": kl, "value_length": vl,
        "full_attention_interval": meta("full_attention_interval", 1),
        "expert_count": meta("expert_count"), "expert_used": meta("expert_used_count"),
        "context_length": meta("context_length"),
        "tensors": len(tensors),
        "expert_bytes": expert_bytes, "dense_bytes": dense_bytes,
        "expert_gib": expert_bytes / GIB, "dense_gib": dense_bytes / GIB,
        "expert_bytes_per_layer_avg": (sum(expert_per_layer) / len(expert_per_layer)) if expert_per_layer else 0,
        "expert_bytes_by_layer": expert_by_layer,
        "expert_types": expert_types,
        "bpw_ok": bpw["ok"], "bpw_max_rel_diff": bpw["max_rel_diff"],
        "bpw_unknown": bpw["unknown_types"], "bpw_skipped_small": bpw["skipped_small"],
        "bpw_types": [{k: r[k] for k in ("name", "elements", "bytes",
                                         "bpw_empirical", "bpw_table", "rel_diff")}
                      for r in bpw["rows"]],
        "kv_bytes_per_token": per_token,
        "gdn_mib_total": gdn_per_layer * len(lin_layers) / MIB,
        "quant": _quant_label(expert_types),
    }


def _quant_label(expert_types: dict) -> str:
    """Квант экспертов по фактическим типам: это подпись модели в наших таблицах."""
    if not expert_types:
        return "нет-MoE"
    total = sum(expert_types.values())
    top = max(expert_types.items(), key=lambda x: x[1])
    others = {k: v for k, v in expert_types.items() if k != top[0] and v * 20 > total}
    return top[0] + ("" if not others else "+" + ",".join(sorted(others)))


def gpu_weights_mib(out: dict, n_layer: int, k: int) -> float:
    """Стоки llama: -ngl 99 + --n-cpu-moe k = в RAM уходят эксперты ПЕРВЫХ k слоёв."""
    per = {}
    for t in out["tensors"]:
        L = layer_of(t["name"])
        if L is not None and is_expert(t["name"]):
            per[L] = per.get(L, 0) + t["bytes"]
    moved = sum(v for L, v in per.items() if L < k)
    return (out["data_bytes"] - moved) / MIB


def selftest() -> int:
    """Мини-GGUF своими руками + саботаж-контроли. Пустой вход не должен проходить как «чисто»."""
    fails = []

    def check(label, got, want):
        ok = got == want
        print(f"  [{'ok  ' if ok else 'FAIL'}] {label}: получено {got!r}, ожидалось {want!r}")
        if not ok:
            fails.append(label)

    def string(s: str) -> bytes:
        b = s.encode()
        return struct.pack("<Q", len(b)) + b

    def kv_str(k, v):
        return string(k) + struct.pack("<I", 8) + string(v)

    def kv_u32(k, v):
        return string(k) + struct.pack("<II", 4, v)

    def kv_arr_u32(k, vals):
        return string(k) + struct.pack("<IIQ", 9, 4, len(vals)) + b"".join(struct.pack("<I", x) for x in vals)

    # (имя, dims, тип) - размер вычисляется из таблицы типов, а не задаётся на глаз:
    # иначе эмпирический bpw не с чем сверять и перепутанная нумерация прошла бы незамеченной.
    specs = [("token_embd.weight", [256, 4], "f16"),
             ("blk.0.attn_k.weight", [256, 1], "f16"),
             ("blk.0.attn_v.weight", [256, 1], "f16"),
             ("blk.0.ffn_gate_exps.weight", [256, 8], "q4_K"),
             ("blk.0.ffn_up_exps.weight", [256, 8], "q4_K"),
             ("blk.0.ffn_down_exps.weight", [256, 8], "iq4_xs"),
             ("blk.0.ffn_gate_shexp.weight", [256, 2], "f16"),
             ("blk.1.attn_qkv.weight", [256, 2], "f16"),
             ("blk.1.ffn_gate_exps.weight", [256, 8], "q4_K"),
             ("blk.1.ffn_up_exps.weight", [256, 8], "q4_K"),
             ("blk.1.ffn_down_exps.weight", [256, 8], "iq4_xs")]
    sized = []
    for nm, dims, tname in specs:
        dt = tid(tname)
        nb = row_bytes(dt, dims[0] * dims[1])
        if nb is None:
            fails.append(f"размер {tname} не вычислился")
            return 1
        sized.append((nm, dims, dt, nb))
    body, off = b"", 0
    tinfo = b""
    for nm, dims, dt, nbytes in sized:
        tinfo += string(nm) + struct.pack("<I", len(dims)) + b"".join(struct.pack("<Q", d) for d in dims)
        tinfo += struct.pack("<IQ", dt, off)
        body += bytes(nbytes)
        off += nbytes
    kvs = [kv_str("general.architecture", "testarch"), kv_str("general.name", "mini"),
           kv_u32("testarch.block_count", 2), kv_u32("testarch.context_length", 32768),
           kv_u32("testarch.embedding_length", 16), kv_u32("testarch.attention.head_count", 2),
           kv_u32("testarch.attention.head_count_kv", 1),
           kv_u32("testarch.attention.key_length", 8),
           kv_u32("testarch.attention.value_length", 8),
           kv_u32("testarch.full_attention_interval", 1),
           kv_u32("testarch.expert_count", 64), kv_u32("testarch.expert_used_count", 8),
           kv_u32("testarch.ssm.time_step_rank", 4), kv_u32("testarch.ssm.state_size", 8),
           kv_u32("testarch.ssm.group_count", 2), kv_u32("testarch.ssm.inner_size", 16),
           kv_u32("testarch.ssm.conv_kernel", 4), kv_arr_u32("testarch.attention.rel_alibi", [1, 2])]
    head = (b"GGUF" + struct.pack("<IQQ", 3, len(specs), len(kvs)) + b"".join(kvs) + tinfo)
    pad = (-len(head)) % 32
    raw = head + bytes(pad) + body

    tmp = pathlib.Path(tempfile.mkdtemp()) / "mini.gguf"
    tmp.write_bytes(raw)
    out = parse(tmp)
    g = geometry(out, min_bytes=64)
    check("магия и версия", out["version"], 3)
    check("число тензоров", len(out["tensors"]), len(specs))
    check("архитектура", g["arch"], "testarch")
    exp_bytes = sum(nb for nm, dims, dt, nb in sized if is_expert(nm))
    l0_exp_bytes = sum(nb for nm, dims, dt, nb in sized
                       if is_expert(nm) and layer_of(nm) == 0)
    check("экспертных байт = сумма экспертных тензоров по таблице", g["expert_bytes"], exp_bytes)
    check("плотных байт = всего - эксперты", g["dense_bytes"],
          sum(s[3] for s in sized) - g["expert_bytes"])
    check("KV-слоёв по фактическим именам", g["kv_layers"], 1)
    check("линейных (GDN) слоёв", g["linear_layers"], 1)
    check("KV q4_0 на токен = 1*(8+8)*18/32", round(g["kv_bytes_per_token"]["q4_0"], 3), 9.0)
    check("KV q8_0 на токен = 1*(8+8)*34/32", round(g["kv_bytes_per_token"]["q8_0"], 3), 17.0)
    # Фолбэк head_length мерится мутацией: у того же заголовка отбираются явные key_length и
    # value_length - если расчёт остался 9.0/17.0 (embedding 16 / head_count 2 = 8), фолбэк
    # живой, а не «проверка проходит за счёт явно заданного ключа».
    mut = dict(out["metadata"])
    pfx = g["arch"] + "."
    for k in (pfx + "attention.key_length", pfx + "attention.value_length"):
        mut.pop(k, None)
    g_mut = geometry({**out, "metadata": mut}, min_bytes=64)
    check("KV без явного key_length - тот же q4_0", round(g_mut["kv_bytes_per_token"]["q4_0"], 3), 9.0)
    check("KV без явного key_length - тот же q8_0", round(g_mut["kv_bytes_per_token"]["q8_0"], 3), 17.0)
    check("ключей key_length в мутированном заголовке не осталось",
          sum(1 for k in mut if k.endswith("attention.key_length")), 0)
    check("GDN на слой f32 = 4*8*8*4 + (2*16+16)*3*4", round(g["gdn_mib_total"] * MIB, 1),
          round(4 * 8 * 8 * 4 + (2 * 16 + 16) * 3 * 4, 1))
    check("квант экспертов - самый тяжёлый тип", g["quant"], "q4_K+iq4_xs")
    check("потолок окна из метаданных", g["context_length"], 32768)
    check("ncmoe 0 = все веса на GPU", gpu_weights_mib(out, 2, 0), out["data_bytes"] / MIB)
    check("ncmoe 1 снимает слой 0", gpu_weights_mib(out, 2, 1),
          (out["data_bytes"] - l0_exp_bytes) / MIB)
    check("ncmoe 2 снимает оба слоя", gpu_weights_mib(out, 2, 2),
          (out["data_bytes"] - 2 * l0_exp_bytes) / MIB)
    check("эмпирический bpw сходится с табличным", g["bpw_ok"], True)
    check("расхождение bpw нулевое (без выравнивания)", g["bpw_max_rel_diff"], 0.0)
    check("типов в аудите ровно три", len(g["bpw_types"]), 3)
    # Таблица против тел struct из ggml/src/ggml-common.h: ожидаемое задано ФОРМУЛОЙ из полей,
    # а не числом - иначе перепутанный размер блока прошёл бы как «совпадает с таблицей».
    check("q8_0 = half d + i8 qs[32]", row_bytes(tid("q8_0"), 32), 2 + 32)
    check("q8_K = float d + i8 qs[256] + i16 bsums[16]", row_bytes(tid("q8_K"), 256), 4 + 256 + 32)
    check("iq4_xs = half d + u16 scales_h + u8 scales_l[4] + u8 qs[128]",
          row_bytes(tid("iq4_xs"), 256), 2 + 2 + 4 + 128)
    check("iq2_xxs = half d + u16 qs[32]", row_bytes(tid("iq2_xxs"), 256), 2 + 64)
    check("iq4_nl = half d + u8 qs[16] на блоке 32", row_bytes(tid("iq4_nl"), 32), 2 + 16)
    # саботаж самой меры: приписываем крупному тензору чужой тип - аудит обязан это увидеть,
    # иначе «зелёный bpw_ok» ничего не значит.
    tampered = {"tensors": [dict(t) for t in out["tensors"]], "file_size": out["file_size"],
                "data_start": out["data_start"], "data_bytes": out["data_bytes"]}
    for t in tampered["tensors"]:
        if t["name"] == "blk.0.ffn_gate_exps.weight":
            t["dtype"] = tid("i32")
    bad = bpw_audit(tampered, min_bytes=64)
    check("саботаж: подмена типа на i32 поймана", bad["ok"], False)
    print(f"       аудит после саботажа: max_rel_diff={bad['max_rel_diff']}, "
          f"{[(r['name'], r['bpw_empirical'], r['bpw_table']) for r in bad['rows']]}")

    # саботаж-контроли: каждый обязан дать GgufError с причиной
    def sabotage(label: str, payload: bytes):
        p = tmp.with_name("sab.gguf")
        p.write_bytes(payload)
        try:
            parse(p)
        except GgufError as e:
            print(f"  [ok  ] саботаж {label}: пойман с причиной «{e}»")
        except Exception as e:  # noqa: BLE001
            fails.append(label)
            print(f"  [FAIL] саботаж {label}: пойман НЕ GgufError, а {type(e).__name__}: {e}")
        else:
            fails.append(label)
            print(f"  [FAIL] саботаж {label}: принят молча - мера не состоялась")
        finally:
            p.unlink(missing_ok=True)

    sabotage("битая магия", b"XXXX" + raw[4:200])
    sabotage("обрезан на середине ключа", raw[:120])
    sabotage("ноль тензоров", b"GGUF" + struct.pack("<IQQ", 3, 0, 1) + kv_str("general.architecture", "a")
             + bytes((-(4 + 4 + 8 + 8 + len(kv_str("general.architecture", "a")))) % 32) + b"\x00" * 32)
    sabotage("смещение data_start за конец файла", raw[:len(head) + pad] + b"\x00" * 8)
    empty = tmp.with_name("empty.gguf")
    empty.write_bytes(b"")
    try:
        parse(empty)
    except GgufError as e:
        print(f"  [ok  ] саботаж пустой файл: пойман с причиной «{e}»")
    else:
        fails.append("пустой файл")
        print("  [FAIL] саботаж пустой файл: принят молча")
    empty.unlink()
    try:
        parse(tmp.with_name("net-suschestvuet.gguf"))
    except GgufError as e:
        print(f"  [ok  ] саботаж нет файла: пойман с причиной «{e}»")
    else:
        fails.append("нет файла")
        print("  [FAIL] саботаж нет файла: принят молча")
    tmp.unlink(missing_ok=True)
    print(f"\nselftest gguf_meta: {'OK' if not fails else 'ПРОВАЛЕНО ' + str(len(fails)) + ': ' + ', '.join(fails)}")
    return 0 if not fails else 1


def main() -> int:
    ap = argparse.ArgumentParser(description="геометрия GGUF по заголовку")
    ap.add_argument("--gguf", help="путь к .gguf; печатает JSON")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    if not a.gguf:
        print("нужен --gguf <путь> либо --selftest", file=sys.stderr)
        return 2
    try:
        out = parse(pathlib.Path(a.gguf))
    except GgufError as e:
        print(f"[FAIL] {e}", file=sys.stderr)
        return 2
    print(json.dumps(geometry(out), ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
