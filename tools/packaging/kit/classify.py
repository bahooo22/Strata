#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Класс машины против нашей базы (RTX 3060 Ti 8 ГБ + 4 ядра + 31,87 ГиБ + SSD).

Вердикт нужен затем, чтобы комплект честно сказал, что на этом железе не
получится, вместо того чтобы молча подобрать параметры от чужого стенда.

Вызов:
    python kit/classify.py                      # снять конфигурацию самому
    python kit/classify.py --config cfg.json    # взять уже снятую
    python kit/classify.py --kit-arches 86;89   # сказать, что реально собрано
    python kit/classify.py --selftest           # 5 классов железа + саботаж

Список архитектур комплекта по умолчанию берётся из elf-proof.json (доказательство по
cubin, снимается на шаге сборки), затем из build-measure.json (заказ сборки) и только
затем из константы KIT_ARCHS - источник всегда печатается, чтобы вердикт был проверяем.

Коды возврата: 0 - класс определён; 1 - определён с предупреждениями;
2 - класс определить нельзя (битый или неполный вход).
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

# Наша база. Окна и параметры подобраны именно под неё, поэтому сравнение
# идёт с этими числами, а не с абстрактным "достаточно мощно".
BASE = {
    "vram_mib": 8192,
    "ram_gib": 31.87,
    "cpu_physical": 4,
    "disk_media": "SSD",
    "cc": "86",
}

# Архитектуры, реально лежащие в собранном комплекте (доказательство -
# cuobjdump --list-elf на шаге сборки). Вне этого списка cubin не найдётся,
# и запуск уйдёт в PTX-JIT либо не состоится.
# Это ПРИМЕР, а не истина: комплект пересобирают под другой список, и тогда вердикт
# «готового cubin для этой архитектуры нет» врал бы про ту архитектуру, которая в комплекте
# как раз есть. Поэтому по-настоящему список берётся из elf-proof.json рядом с kit\
# (см. kit_archs); константа остаётся последним рубежом, когда доказательства нет вовсе.
KIT_ARCHS = ("86", "89", "120")


def arch_code(token: object) -> str:
    """`sm_120a`, `compute_86`, `8.6`, `120` -> `120`, `86`, `86`, `120`.

    Суффиксы arch-specific cubin (`a`, `f`) целевую архитектуру не меняют: sm_120a
    годится карте с compute_cap 12.0, поэтому код берётся без них."""
    s = re.sub(r"^(sm|compute)[_-]?", "", str(token).strip(), flags=re.I).replace(".", "")
    m = re.match(r"^(\d{2,3})", s)
    return m.group(1) if m else ""


def kit_archs(declared: str | None, kit_dir: Path) -> tuple[list[str], str, list[str]]:
    """Список архитектур комплекта и честное сообщение о том, откуда он взят.

    Порядок: явный --kit-arches -> elf-proof.json (доказательство по cubin) ->
    build-measure.json (что заказывали при сборке) -> константа. Возвращает
    (числовые коды, источник, предупреждения)."""
    warn: list[str] = []
    if not kit_dir.is_dir():
        raise ValueError(f"каталог комплекта {kit_dir} не найден: источник архитектур не определить")
    if declared is not None:
        codes = [arch_code(x) for x in declared.replace(",", ";").split(";") if x.strip()]
        if not codes:
            raise ValueError("--kit-arches задан, но пуст после разбора: подмены не было")
        return _ordered(codes), "флаг --kit-arches", warn
    for name, extract in (("elf-proof.json", "proof"), ("build-measure.json", "measure")):
        for base in (kit_dir.parent, kit_dir):
            path = base / name
            if not path.is_file():
                continue
            try:
                data = json.loads(path.read_text(encoding="utf-8-sig"))
            except (OSError, json.JSONDecodeError) as e:
                warn.append(f"{path.name} не читается ({e}): источник архитектур - ниже по списку")
                continue
            codes: list[str] = []
            if extract == "proof":
                for b in data.get("binaries") or []:
                    codes += [c for c in (arch_code(a) for a in (b.get("cubin_archs") or [])) if c]
                if not codes:
                    warn.append(f"в {path.name} нет ни одного cubin_archs: доказательство пустое")
                    continue
            else:
                codes = [c for c in (arch_code(x) for x in (data.get("archs") or [])) if c]
                if not codes:
                    warn.append(f"в {path.name} нет поля archs")
                    continue
                warn.append(f"архитектуры взяты из {path.name} - это заказ сборки, "
                            f"а не доказанный cubin")
            return _ordered(codes), f"{path}{' (заказ, не cubin)' if extract == 'measure' else ''}", warn
    warn.append(f"доказательства сборки нет (elf-proof.json не найден около {kit_dir}): "
                f"берётся константа KIT_ARCHS={', '.join(KIT_ARCHS)}")
    return list(KIT_ARCHS), "константа KIT_ARCHS (не доказана)", warn


def _ordered(codes: list[str]) -> list[str]:
    """Уникальные коды по возрастанию: «120» идёт после «86», а не в алфавитном порядке."""
    return sorted(set(codes), key=lambda x: int(re.match(r"\d+", x).group()))


CLASS_LABEL = {
    "above": "мощнее нашей базы",
    "equal": "не ниже нашей базы",
    "below": "ниже нашей базы",
    "weak": "сильно ниже нашей базы",
}

# Что обещает комплект и чего на слабом железе не будет.
LIMITS = {
    "vram": "длинные окна (128k+) и MoE с CPU-экспертами в такую память не влезают",
    "ram": "часть экспертов останется на диске, старт модели и прогон окна замедлятся",
    "cpu": "CPU-эксперты (--n-cpu-moe) станут узким местом",
    "disk": "загрузка модели с HDD измерялась только как ухудшение, не как профиль",
    "arch": "готового cubin для этой архитектуры в комплекте нет",
}


def relation(ours: float, yours: float) -> str:
    """Ступень относительно базы: «выше» считается от полуторного запаса."""
    if yours >= ours * 1.5:
        return "above"
    if yours >= ours * 0.95:
        return "equal"
    return "below"


def classify(cfg: dict, archs_of_kit: list[str] | None = None,
             archs_source: str = "константа KIT_ARCHS (не доказана)") -> dict:
    """Класс по пяти осям; итоговый класс - худшая из осей.

    `archs_of_kit` - архитектуры, доказанно лежащие в комплекте (см. kit_archs): без него
    вердикт «cubin для твоей архитектуры нет» опирался бы на константу, пережившую
    пересборку комплекта под другой список."""
    warnings: list[str] = []
    limits: list[str] = []
    axes: dict = {}
    archs = _ordered(archs_of_kit) if archs_of_kit else list(KIT_ARCHS)

    gpu = cfg.get("gpu") or {}
    vram = gpu.get("vram_mib")
    if vram:
        rel = relation(BASE["vram_mib"], vram)
        axes["vram_mib"] = {"ours": BASE["vram_mib"], "yours": vram, "relation": rel}
        if rel == "below":
            limits.append(LIMITS["vram"])
            if vram <= 6144:
                warnings.append(f"видеопамяти {vram} МиБ против {BASE['vram_mib']} у нас: "
                                f"это уже класс «сильно ниже»")
    else:
        warnings.append("объём видеопамяти не снят: класс по памяти определить нельзя")

    cc = arch_code(gpu.get("cc") or "")
    if cc:
        in_kit = cc in archs
        axes["compute_capability"] = {"ours": BASE["cc"], "yours": cc,
                                      "relation": "equal" if in_kit else "below"}
        if not in_kit:
            limits.append(LIMITS["arch"])
            warnings.append(f"sm_{cc} нет в списке собранных архитектур ({', '.join(archs)}; "
                            f"источник списка: {archs_source})")
    else:
        warnings.append("compute capability не снята: архитектуры комплекта не проверить")

    ram = (cfg.get("ram") or {}).get("total_gib")
    if ram:
        rel = relation(BASE["ram_gib"], ram)
        axes["ram_gib"] = {"ours": BASE["ram_gib"], "yours": ram, "relation": rel}
        if rel == "below":
            limits.append(LIMITS["ram"])
    else:
        warnings.append("объём ОЗУ не снят: класс по памяти определить нельзя")

    cpu = cfg.get("cpu") or {}
    cores = cpu.get("physical") or (cpu.get("logical") or 0)
    if cores:
        rel = relation(BASE["cpu_physical"], cores)
        axes["cpu_physical"] = {"ours": BASE["cpu_physical"], "yours": cores,
                                "relation": rel,
                                "measured": "physical" if cpu.get("physical") else "logical"}
        if rel == "below":
            limits.append(LIMITS["cpu"])
    else:
        warnings.append("число ядер не снято: класс по CPU определить нельзя")

    disk = cfg.get("model_disk") or {}
    media = (disk.get("media") or "").upper()
    if media:
        rel = "equal" if media == BASE["disk_media"] else "below"
        axes["disk_media"] = {"ours": BASE["disk_media"], "yours": media, "relation": rel}
        if rel == "below":
            limits.append(LIMITS["disk"])
            warnings.append(f"модель лежит на {media}: наши профили снимались с SSD")
    else:
        warnings.append("тип носителя под моделью не определён: сравнение по диску пропущено")

    rels = [a["relation"] for a in axes.values()]
    if "below" in rels:
        # «сильно ниже» говорим только когда не хватает видеопамяти: окна считаются по ней
        worst = "weak" if (vram or 0) <= 6144 else "below"
    elif axes.get("vram_mib", {}).get("relation") == "above":
        worst = "above"
    else:
        worst = "equal"

    return {"class": worst, "label": CLASS_LABEL[worst], "base": BASE, "axes": axes,
            "kit_archs": archs, "archs_source": archs_source,
            "limits": sorted(set(limits)), "warnings": warnings}


def read_config(path: Path) -> dict:
    raw = path.read_bytes()
    if not raw.strip():
        raise ValueError(f"{path} пуст: классификация не состоялась")
    try:
        cfg = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as e:
        raise ValueError(f"{path} не читается как JSON: {e}") from e
    if not isinstance(cfg, dict) or not cfg.get("gpu"):
        raise ValueError(f"в {path.name} нет секции gpu: классифицировать нечего")
    return cfg


def run_detect() -> dict:
    """Снять конфигурацию тем же detect.py, не дублируя зонды."""
    detect = Path(__file__).resolve().parent / "detect.py"
    p = subprocess.run([sys.executable, str(detect)], capture_output=True, timeout=180)
    if p.returncode not in (0, 1):
        raise ValueError("detect.py не отдал конфигурацию: " +
                         (p.stderr or b"").decode("utf-8", "replace").strip())
    try:
        return json.loads(p.stdout.decode("utf-8", "replace"))
    except json.JSONDecodeError as e:
        raise ValueError(f"detect.py вывел не JSON: {e}") from e


FAKES = [
    ("3060ti-8g", "equal", {"gpu": {"name": "RTX 3060 Ti", "vram_mib": 8192, "cc": "86"},
                            "cpu": {"physical": 4, "logical": 8}, "ram": {"total_gib": 31.87},
                            "model_disk": {"media": "SSD"}}),
    ("5080-16g", "above", {"gpu": {"name": "RTX 5080", "vram_mib": 16303, "cc": "120"},
                           "cpu": {"physical": 8, "logical": 16}, "ram": {"total_gib": 95.7},
                           "model_disk": {"media": "SSD"}}),
    ("4090-24g", "above", {"gpu": {"name": "RTX 4090", "vram_mib": 24564, "cc": "89"},
                           "cpu": {"physical": 16, "logical": 32}, "ram": {"total_gib": 63.9},
                           "model_disk": {"media": "SSD"}}),
    ("5090-32g", "above", {"gpu": {"name": "RTX 5090", "vram_mib": 32607, "cc": "120"},
                           "cpu": {"physical": 24, "logical": 48}, "ram": {"total_gib": 127.8},
                           "model_disk": {"media": "SSD"}}),
    ("weak-6g-16g", "weak", {"gpu": {"name": "GTX 1660 Super", "vram_mib": 6144, "cc": "75"},
                             "cpu": {"physical": 4, "logical": 8}, "ram": {"total_gib": 15.9},
                             "model_disk": {"media": "HDD"}}),
]


def selftest() -> int:
    ok = bad = 0

    def check(name: str, got, want) -> None:
        nonlocal ok, bad
        if got == want:
            ok += 1
            print(f"  ok   {name}")
        else:
            bad += 1
            print(f"FAIL   {name}: получено {got!r}, ожидалось {want!r}")

    print("classify.py selftest")
    for name, want, cfg in FAKES:
        res = classify(cfg)
        check(f"класс {name} -> {want}", res["class"], want)
    check("у слабой машины есть предупреждение",
          bool(classify(FAKES[-1][2])["warnings"]), True)
    check("у слабой машины названы ограничения",
          len(classify(FAKES[-1][2])["limits"]) >= 3, True)
    check("у базы предупреждений нет", classify(FAKES[0][2])["warnings"], [])
    # саботаж: пустой файл, не-JSON, без gpu, и конфигурация без единой снятой оси
    import tempfile
    tmp = Path(tempfile.mkdtemp())
    for label, payload in (("empty", b""), ("not-json", b"{not json at all"),
                           ("no-gpu", b'{"cpu": {"physical": 4}}')):
        f = tmp / f"{label}.json"
        f.write_bytes(payload)
        try:
            read_config(f)
            check(f"вход «{label}» -> отказ", "молча принял", "ValueError")
        except ValueError:
            check(f"вход «{label}» -> отказ", "ValueError", "ValueError")
    res = classify({"gpu": {}})
    check("пустая конфигурация не остаётся без причин", bool(res["warnings"]), True)
    # источник списка архитектур: доказательство сборки важнее константы
    kit = tmp / "kit"
    kit.mkdir()
    (kit / "elf-proof.json").write_text(json.dumps(
        {"binaries": [{"label": "strata-q36.exe", "cubin_archs": ["sm_86", "sm_120a"]}]}),
        encoding="utf-8")
    codes, src, src_w = kit_archs(None, kit)
    check("elf-proof: sm_120a сворачивается в 120", codes, ["86", "120"])
    check("elf-proof: источник назван файлом", "elf-proof.json" in src, True)
    check("elf-proof: предупреждений нет", src_w, [])
    check("доказанный список снимает жалобу на sm_89",
          [x for x in classify(FAKES[2][2], ["86", "89", "120"])["warnings"] if "sm_89" in x], [])
    res = classify(FAKES[4][2], codes, src)
    check("отсутствующая архитектура названа вместе с источником",
          any("sm_75" in x and "elf-proof.json" in x for x in res["warnings"]), True)
    # саботаж источника: пустое доказательство, заказ без доказательства, пустой флаг
    empty_kit = tmp / "kit-empty"
    empty_kit.mkdir()
    (empty_kit / "elf-proof.json").write_text(json.dumps({"binaries": [{"cubin_archs": []}]}),
                                               encoding="utf-8")
    codes2, _, warn2 = kit_archs(None, empty_kit)
    check("пустое доказательство -> константа", codes2, list(KIT_ARCHS))
    check("пустое доказательство названо причиной",
          any("доказательство пустое" in x for x in warn2), True)
    meas = tmp / "kit-measure"
    meas.mkdir()
    (meas / "build-measure.json").write_text(json.dumps({"archs": ["86", "89"]}), encoding="utf-8")
    codes3, _, warn3 = kit_archs(None, meas)
    check("без elf-proof берутся архи заказа сборки", codes3, ["86", "89"])
    check("заказ помечен как недоказанный cubin", any("заказ" in x for x in warn3), True)
    check("порядок кодов численный, не алфавитный",
          _ordered(["120", "86", "89", "86"]), ["86", "89", "120"])
    try:
        kit_archs(" ; ", kit)
        check("пустой --kit-arches -> отказ", "молча принял", "ValueError")
    except ValueError:
        check("пустой --kit-arches -> отказ", "ValueError", "ValueError")
    codes4, src4, _ = kit_archs("sm_86; 8.9, compute_120", kit)
    check("флаг перекрывает доказательство и принимает sm_/compute_/точку",
          (codes4, src4), (["86", "89", "120"], "флаг --kit-arches"))
    try:
        kit_archs(None, tmp / "no-such-kit")
        check("несуществующий каталог комплекта -> отказ", "молча принял", "ValueError")
    except ValueError:
        check("несуществующий каталог комплекта -> отказ", "ValueError", "ValueError")
    print(f"classify: {ok}/{ok + bad} контролей пройдено")
    return 0 if bad == 0 else 1


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--config", help="JSON от detect.py; по умолчанию снять самому")
    ap.add_argument("--kit-arches", help="архитектуры комплекта через ; ; по умолчанию берутся "
                                         "из elf-proof.json рядом с комплектом, затем из "
                                         "build-measure.json, затем константа KIT_ARCHS")
    ap.add_argument("--kit-dir", type=Path, help="каталог комплекта, где лежит elf-proof.json "
                                                 "(по умолчанию - рядом с kit\\)")
    ap.add_argument("--out", help="записать вердикт в файл")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()

    if args.selftest:
        return selftest()

    try:
        cfg = read_config(Path(args.config)) if args.config else run_detect()
    except (OSError, ValueError) as e:
        print(f"ОТКАЗ: {e}", file=sys.stderr)
        return 2

    try:
        kit_dir = args.kit_dir if args.kit_dir else Path(__file__).resolve().parent
        archs, archs_source, src_warn = kit_archs(args.kit_arches, kit_dir)
    except ValueError as e:
        print(f"ОТКАЗ: {e}", file=sys.stderr)
        return 2

    res = classify(cfg, archs, archs_source)
    res["warnings"] = src_warn + res["warnings"]
    text = json.dumps(res, ensure_ascii=False, indent=2)
    if args.out:
        Path(args.out).write_text(text + "\n", encoding="utf-8")
        print(f"вердикт: {args.out}")
    else:
        print(text)
    print(f"класс: {res['label']}", file=sys.stderr)
    print(f"архитектуры комплекта: {', '.join(archs)} (источник: {archs_source})", file=sys.stderr)
    for limit in res["limits"]:
        print(f"  не получится: {limit}", file=sys.stderr)
    for w in res["warnings"]:
        print(f"  предупреждение: {w}", file=sys.stderr)
    if res["warnings"]:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
