#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Максимальное окно и лучшие параметры под конкретную модель и конкретное железо.

Таблица правил собрана из ЗАМЕРОВ нашего стенда, а не из общих рассуждений: каждая строка
несёт первичник - имя профиля `harness\\config\\*.json` или таблицу `docs\\measurements\\*.md`.
Отсутствующий замер обозначен прямо (`measured: false` + формула), потому что красивая
рекомендация без первичника и есть тот случай, когда комплект врёт вежливо.

Как считается окно. Для каждого шага лесенки (64k, 80k, 96k, 128k, 160k) складывается
то, что реально занимает видеопамять:

    KV-кэш      = байт на токен (из заголовка GGUF) x окно
    attention   = --att-mb
    запас       = --vram-reserve-mib
    GDN-состояние (линейные слои) и, для llama, веса на GPU при данном --n-cpu-moe

Шаг проходит, если сумма влезает в видеопамять. На нашей базе (8192 МиБ) формула обязана
воспроизвести замеренную лесенку с точностью до одной ступени - это контроль в --selftest,
и он же мера готовности из п. 4.5 плана.

Вызов:
    python kit\\recommend.py --gguf model.gguf [--config cfg.json] [--engine auto]
    python kit\\recommend.py --gguf model.gguf --fake-config 16g.json --json
    python kit\\recommend.py --gguf model.gguf --window 131072
    python kit\\recommend.py --selftest

Коды возврата: 0 - рекомендация дана; 1 - дана с предупреждениями (железо не мерилось в этом
классе, модель не из нашего списка, окно предсказано формулой); 2 - вход неверен или считать
неоткуда (битый GGUF, пустой models.json, окно, которое не влезает даже на минимальной ступени).
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys
from dataclasses import dataclass, field

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import gguf_meta            # noqa: E402
import classify as classify_mod   # noqa: E402  (нужен kit_archs, а не только сама функция)
from classify import BASE, classify   # noqa: E402

MIB = 1024 ** 2
KV_TYPE = "q4_0"          # измеренный рабочий тип KV на всех пяти окнах
LADDER = (65536, 81920, 98304, 131072, 163840, 229376)

# Кванты KV, которые принимает каждый движок: ключ - имя, которое мы печатаем в строке
# запуска, значение - имя строки в geom["kv_bytes_per_token"] (она по ggml-именам).
# Первичники: Страта - src/qwen35/q36_engine.cu:4389-4395 (лямбда kv_of; fp16/f16 откатывает
# на fp32, k8v4 и пара K!=V отвергаются с rc=2); llama.cpp в пине 3cf03257 -
# common/arg.cpp:304-313 (f32, f16, bf16, q8_0, q4_0, q4_1, iq4_nl, q5_0, q5_1).
# Множества РАЗНЫЕ: q5_1 есть у обоих, iq4_nl и q4_1 - только у llama, а Страта не знает f16.
KV_BY_ENGINE = {
    "strata": {"fp32": "f32", "q8_0": "q8_0", "q5_1": "q5_1", "q5_0": "q5_0", "q4_0": "q4_0"},
    "llama": {t: t for t in ("f32", "f16", "bf16", "q8_0", "q5_1", "q5_0", "q4_0",
                             "q4_1", "iq4_nl")},
}
# Вся лесенка и все окна реестра сняты при q4_0, поэтому на любом другом кванте ответ
# перестаёт быть «замером этой модели» и обязан быть подписан расчётом: цена KV входит в
# слагаемые окна, и менять её, не переснимая замер, нельзя.
KV_MEASURED = KV_TYPE

# --- правила по окнам: значения взяты из профилей стенда, первичник в src ---
# Страта. chunk/prefill/kv/mtp одинаковы во всех профилях рабочей сетки; различаются
# att-mb и vram-reserve-mib, и именно они определяют, какое окно ещё влезает.
STRATA_RULES = [
    {"window": 65536, "att_mb": 256, "reserve_mib": 512, "super_chunk": 8, "mtp": 0,
     "src": "harness/config/strata-coder-64k.json"},
    {"window": 81920, "att_mb": 256, "reserve_mib": 512, "super_chunk": 8, "mtp": 0,
     "src": "harness/config/strata-coder-80k.json"},
    {"window": 98304, "att_mb": 256, "reserve_mib": 512, "super_chunk": 8, "mtp": 0,
     "src": "harness/config/strata-coder-96k.json"},
    {"window": 131072, "att_mb": 256, "reserve_mib": 512, "super_chunk": 8, "mtp": 0,
     "src": "harness/config/strata-coder-128k.json"},
    {"window": 163840, "att_mb": 512, "reserve_mib": 512, "super_chunk": 8, "mtp": 0,
     "src": "harness/config/strata-coder-160k.json"},
    {"window": 229376, "att_mb": 256, "reserve_mib": 512, "super_chunk": 8, "mtp": 0,
     "src": "harness/config/strata-coder-224k.json"},
]
STRATA_FIXED = {"chunk": 128, "batch": 1, "prefill": 2048, "kv_type": KV_TYPE,
                "draft_vocab": 8192, "fa_layer": "all",
                "src": "harness/config/strata-kat-iq4xs-96k.json"}

# llama.cpp: -ngl 99 + --n-cpu-moe k снимает в RAM экспертов ПЕРВЫХ k слоёв; ступень k
# подбиралась по окну и по модели (на Q4_K_M потребовалось 33, иначе обвал pp).
LLAMA_RULES = [
    {"window": 65536, "ncmoe": 32, "ub": 8192, "b": 2048,
     "src": "harness/scripts/run_llama_coder_64k.bat"},
    {"window": 81920, "ncmoe": 32, "ub": 8192, "b": 2048,
     "src": "harness/scripts/run_llama_coder_80k.bat"},
    {"window": 98304, "ncmoe": 32, "ub": 8192, "b": 2048,
     "src": "harness/scripts/run_llama_fast_96k.bat"},
    {"window": 131072, "ncmoe": 32, "ub": 8192, "b": 2048,
     "src": "harness/scripts/run_llama_general_128k.bat"},
    {"window": 163840, "ncmoe": 33, "ub": 8192, "b": 2048,
     "src": "harness/scripts/run_llama_heretic-q4km_160k.bat"},
]
# «Остаток» - всё, что llama.cpp держит в видеопамяти кроме весов, KV и GDN: вычислительные
# буферы чанков, контекстные аллокации, сверх плана ggml. Числа сняты НЕ рассуждением, а
# вычитанием известных слагаемых из VRAM max по 14 точкам (первичник - поле src): там
# замерено и VRAM max, и фактическое заполнение контекста, и ncmoe, и геометрия заголовка.
# Разброс - в 2.8 раза и НЕ следует из геометрии: у KAT IQ4_XS и HauhauCS IQ4_XS плотная
# часть различается на 25 МиБ, а остаток - на 646 МиБ. Поэтому одна «медиана» врать обязана,
# и комплект честно работает двумя границами: max - то, что гарантированно влезает,
# min - оптимистичный предел между ними нужен живой замер.
LLAMA_REMAINDER = {
    "min_mib": 536, "median_mib": 1306, "max_mib": 1518,
    "src": "docs/measurements/vram-audit-ncmoe-2026-11-09.md:14-20,27-33,41-44,63-66,70-74 "
           "(14 точек, остаток = VRAM max - (плотная часть + эксперты слоёв >= ncmoe + "
           "KV по фактическим токенам + GDN))",
}
# Страта по маршруту q36 стримит экспертов из RAM, и в рабочих профилях нет ни одного флага
# размера арены (grep по harness/config: --moe-cache-mib не встречается), поэтому разложения
# VRAM Страты по окнам в нашей базе нет - есть только верхняя граница лесенки (160k работал:
# профиль strata-heretic-q4km-160k.json) и отказ 256k по ВРЕМЕНИ, а не по памяти
# (docs/measurements/context-160k-256k: 88 мин на 45 pp). Предсказание Страты это обязано
# говорить прямо, а не притворяться посчитанным.
STRATA_NOT_CALIBRATED = (
    "strata: разложения видеопамяти по окнам для маршрута q36 (эксперты стримятся из RAM) "
    "мы не мерили - предсказано по слагаемым KV+attention+reserve+GDN+плотная часть, "
    "а не по факту VRAM max; окно 256k ограничено временем (88 мин при 45 pp), а не памятью")

PORTS = {"strata": 8082, "llama": 8081}


class RecommendError(ValueError):
    """Считать неоткуда. Причина обязательна: «пустой ответ» без ошибки - провал меры."""


@dataclass
class Fit:
    """Сколько видеопамяти съедают слагаемые при данном окне."""
    window: int
    kv_mib: float
    att_mib: float
    reserve_mib: float
    gdn_mib: float
    weights_mib: float
    remainder_mib: float = 0.0
    parts: dict = field(default_factory=dict)

    @property
    def total_mib(self) -> float:
        return (self.kv_mib + self.att_mib + self.reserve_mib + self.gdn_mib
                + self.weights_mib + self.remainder_mib)

    def to_dict(self) -> dict:
        return {"window": self.window, "kv_mib": round(self.kv_mib, 1),
                "att_mib": round(self.att_mib, 1), "reserve_mib": round(self.reserve_mib, 1),
                "gdn_mib": round(self.gdn_mib, 1), "weights_mib": round(self.weights_mib, 1),
                "remainder_mib": round(self.remainder_mib, 1),
                "total_mib": round(self.total_mib, 1), "parts": self.parts}


def load_models(path: pathlib.Path) -> dict:
    """Реестр замеренных моделей. Пустой или битый файл - отказ, а не «моделей нет, не страшно»."""
    if not path.is_file():
        raise RecommendError(f"нет файла моделей {path}: без реестра нечем проверять, "
                             f"для какой модели подобраны параметры")
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        raise RecommendError(f"{path} не читается как JSON: {exc}") from exc
    models = (data or {}).get("models") if isinstance(data, dict) else None
    if not models:
        raise RecommendError(f"в {path} нет ни одной модели (ключ models пуст) - "
                             f"проверка не состоялась")
    for m in models:
        for key in ("gguf", "hf_url", "windows"):
            if key not in m:
                raise RecommendError(f"запись модели в {path} без поля {key}: {m}")
        if not m["windows"]:
            raise RecommendError(f"модель {m['gguf']} объявлена без замеренных окон")
        for w in m["windows"]:
            if "window" not in w:
                raise RecommendError(f"окно модели {m['gguf']} без поля window: {w}")
            if not w.get("src"):
                raise RecommendError(f"замер {m['gguf']} {w['window']} без первичника src: "
                                     f"цифру нечем проверить")
        geom = m.get("geom")
        if geom is not None:
            missing = [k for k in ("dense_gib", "kv_bytes_per_token", "expert_bytes_by_layer")
                       if not geom.get(k)]
            if missing:
                raise RecommendError(f"у {m['gguf']} в geom нет {missing}: по такой геометрии "
                                     f"окно не считается, лучше убрать блок geom совсем")
    return {m["gguf"].lower(): m for m in models}


def model_lookup(models: dict, gguf_name: str):
    """Модель ищется по имени файла, не по «похожести»: ссылка на загрузку обязана вести
    именно к тому файлу, под который подбирались окна."""
    return models.get(pathlib.Path(gguf_name).name.lower())


def kv_bytes_per_token(geom: dict, kv_type: str = KV_TYPE) -> float:
    table = geom.get("kv_bytes_per_token") or {}
    if kv_type not in table:
        raise RecommendError(f"в заголовке GGUF нет расчёта KV для типа {kv_type}: "
                             f"есть только {sorted(table)}")
    per = float(table[kv_type])
    if per <= 0:
        raise RecommendError(f"KV на токен получился {per} байт: ни одного слоя attention "
                             f"с известной геометрией (head_count_kv x (k_len+v_len)) в "
                             f"заголовке не найдено - окно посчитать нельзя")
    return per


def gpu_weights_mib(geom: dict, ncmoe: int, engine: str) -> tuple[float, dict]:
    """Сколько весов остаётся в видеопамяти при данном сдвиге экспертов.

    `-ngl 99 --n-cpu-moe k` убирает в RAM экспертов ПЕРВЫХ k слоёв, поэтому берётся хвост
    ряда `expert_bytes_by_layer` - ряд по номерам слоёв, а не среднее: на heretic Q4_K_M
    слои различаются до 15 % (432..498 МиБ), и на среднем числе ошибка лезет ровно в вердикт
    «влезло / не влезло» (первичник ряда - замер заголовка, gguf_meta.geometry)."""
    dense = float(geom.get("dense_gib", 0.0)) * 1024.0
    by_layer = geom.get("expert_bytes_by_layer") or []
    if not by_layer:
        raise RecommendError(f"в геометрии нет послойного ряда экспертов "
                             f"(expert_bytes_by_layer пуст): для {engine} веса на GPU "
                             f"рассчитать нечем, а «на глаз по кванту» даёт обещание без замера")
    # У Страты q36 в видеопамяти остаётся ТОЛЬКО плотная часть: эксперты стримятся из RAM,
    # флага размера арены в рабочих профилях нет. Для неё k = все слои, что бы ни прислали
    # в ncmoe (это параметр llama, а не Страты).
    k = len(by_layer) if engine == "strata" else max(0, min(int(ncmoe), len(by_layer)))
    on_gpu = sum(by_layer[k:]) / MIB
    return dense + on_gpu, {"dense_mib": round(dense, 1), "experts_on_gpu_mib": round(on_gpu, 1),
                            "expert_layers_on_gpu": len(by_layer) - k,
                            "expert_layers_in_ram": k, "n_layer": len(by_layer)}


def fit_strata(geom: dict, window: int, rule: dict, kv_type: str = KV_TYPE) -> Fit:
    per_tok = kv_bytes_per_token(geom, KV_BY_ENGINE["strata"][kv_type])
    kv = per_tok * window / MIB
    # Плотная часть (attention, эмбеддинги, norm) у q36 в видеопамяти остаётся, эксперты -
    # нет: они стримятся из RAM, и флага размера арены в рабочих профилях нет (см. константу).
    weights, wparts = gpu_weights_mib(geom, 0, "strata")
    return Fit(window=window, kv_mib=kv, att_mib=float(rule["att_mb"]),
               reserve_mib=float(rule["reserve_mib"]),
               gdn_mib=float(geom.get("gdn_mib_total") or 0.0),
               weights_mib=weights,
               parts={"kv_type": kv_type, "kv_per_token_bytes": round(per_tok, 1), **wparts,
                      "weights_note": "плотная часть: эксперты маршрута q36 стримятся из RAM",
                      "src": rule["src"], "engine": "strata"})


def fit_llama(geom: dict, window: int, rule: dict,
              remainder_mib: float = LLAMA_REMAINDER["max_mib"],
              kv_type: str = KV_TYPE) -> Fit:
    per_tok = kv_bytes_per_token(geom, KV_BY_ENGINE["llama"][kv_type])
    # У llama при -fa on attention-буферы считается внутри остатка: отдельным слагаемым их
    # не ставим, иначе одна и та же память учитывается дважды (в остаток они вошли фактом
    # VRAM max из аудита).
    kv = per_tok * window / MIB
    weights, wparts = gpu_weights_mib(geom, rule["ncmoe"], "llama")
    return Fit(window=window, kv_mib=kv, att_mib=0.0, reserve_mib=0.0,
               gdn_mib=float(geom.get("gdn_mib_total") or 0.0), weights_mib=weights,
               remainder_mib=float(remainder_mib),
               parts={"kv_type": kv_type, "kv_per_token_bytes": round(per_tok, 1), **wparts,
                      "remainder_src": LLAMA_REMAINDER["src"],
                      "src": rule["src"], "engine": "llama"})


def build_args(engine: str, gguf_path: str, window: int, rule: dict, exe: str,
               threads: int | None = None, kv_type: str = KV_TYPE) -> dict:
    if engine == "strata":
        fixed = STRATA_FIXED
        args = [exe, "--native", gguf_path,
                "--max-context", str(window),
                "--chunk", str(fixed["chunk"]), "--batch", str(fixed["batch"]),
                "--no-graph", "--prefill", str(fixed["prefill"]),
                "--mtp", str(rule["mtp"]), "--draft-vocab", str(fixed["draft_vocab"]),
                "--kv-type", kv_type,
                "--vram-reserve-mib", str(rule["reserve_mib"]),
                "--att-mb", str(rule["att_mb"])]
        env = {"STRATA_Q36_FA_LAYER": fixed["fa_layer"],
               "STRATA_Q36_SUPER_CHUNK": str(rule["super_chunk"])}
        return {"exe": exe, "args": args, "env": env, "port": PORTS["strata"]}
    args = [exe, "-m", gguf_path,
            "--ctx-size", str(window), "-ngl", "99",
            "--n-cpu-moe", str(rule["ncmoe"]), "-b", str(rule["b"]), "-ub", str(rule["ub"]),
            "-ctk", kv_type, "-ctv", kv_type, "-fa", "on",
            "--temp", "0", "--host", "127.0.0.1", "--port", str(PORTS["llama"])]
    # -t на стенде равнялся числу ФИЗИЧЕСКИХ ядер (4) - на другой машине это другое число,
    # и зашивать его значит выдать замеренное за универсальное.
    if threads:
        args[7:7] = ["-t", str(threads)]
    return {"exe": exe, "args": args, "env": {}, "port": PORTS["llama"]}


def rules_for(engine: str) -> list[dict]:
    return STRATA_RULES if engine == "strata" else LLAMA_RULES


def fit_of(geom: dict, engine: str, rule: dict, remainder_mib: float | None = None,
           kv_type: str = KV_TYPE) -> Fit:
    if kv_type not in KV_BY_ENGINE[engine]:
        raise RecommendError(f"квант KV {kv_type!r} движок {engine} не принимает: "
                             f"его список - {', '.join(KV_BY_ENGINE[engine])}")
    if engine == "strata":
        return fit_strata(geom, rule["window"], rule, kv_type)
    return fit_llama(geom, rule["window"], rule,
                     LLAMA_REMAINDER["max_mib"] if remainder_mib is None else remainder_mib,
                     kv_type)


def ladder_max(geom: dict, engine: str, vram: float,
               remainder_mib: float | None = None,
               kv_type: str = KV_TYPE) -> tuple[dict | None, Fit | None]:
    """Верхняя ступень лесенки, которая влезает в vram по слагаемым (спускаемся сверху)."""
    for rule in sorted(rules_for(engine), key=lambda r: -r["window"]):
        f = fit_of(geom, engine, rule, remainder_mib, kv_type)
        if f.total_mib <= vram:
            return rule, f
    return None, None


def measured_max(measured: dict | None, engine: str) -> tuple[int | None, dict]:
    """Максимальное ЗАМЕРЕННОЕ окно этой модели ДАННЫМ движком и строка замера под него.

    Реестр первичнее формулы: по 14 точкам аудита остаток не выводится из геометрии
    (KAT против HauhauCS - разница 646 МиБ при разнице плотной части 25 МиБ), поэтому
    там, где факт есть, факт и отвечает за «влезло»."""
    if not measured:
        return None, {}
    ok = [w for w in measured["windows"]
          if w.get("window") in LADDER and (w.get("engine") or engine) == engine]
    if not ok:
        return None, {}
    best = max(ok, key=lambda w: w["window"])
    return int(best["window"]), best


def recommend(geom: dict, cfg: dict, models: dict, engine: str = "auto",
              want_window: int | None = None, gguf_path: str = "",
              exe_strata: str = "bin\\strata-q36.exe",
              exe_llama: str = "bin\\llama-server.exe",
              kv_type: str = KV_TYPE) -> dict:
    """Главный ответ комплекта: окно, параметры, ссылка на модель и честный список оговорок."""
    vram = cfg.get("gpu", {}).get("vram_mib")
    if not vram:
        raise RecommendError("в конфигурации железа нет gpu.vram_mib: окно предсказать нельзя")
    vram = float(vram)
    warnings: list[str] = []
    phys = (cfg.get("cpu") or {}).get("physical")
    threads = int(phys) if phys else None
    if threads is None:
        warnings.append("число физических ядер не снято: -t не подставляется, llama.cpp возьмёт "
                        "свой дефолт, а наши замеры сделаны с -t 4 (= ядра стенда)")

    order = ["strata", "llama"] if engine == "auto" else [engine]
    for eng in order:
        if eng not in ("strata", "llama"):
            raise RecommendError(f"движка {eng!r} в комплекте нет: только strata или llama")
    known = {t for names in KV_BY_ENGINE.values() for t in names}
    if kv_type not in known:
        raise RecommendError(f"кванта KV {kv_type!r} нет ни у одного движка комплекта: "
                             f"Страта - {', '.join(KV_BY_ENGINE['strata'])}; "
                             f"llama.cpp - {', '.join(KV_BY_ENGINE['llama'])}")
    if kv_type != KV_MEASURED:
        warnings.append(f"квант KV {kv_type}: лесенка и весь реестр окон сняты при "
                        f"{KV_MEASURED}, поэтому ответ ниже - расчёт по слагаемым, а не замер "
                        f"этой модели на этом кванте")
    measured = model_lookup(models, gguf_path or geom.get("file", ""))
    if measured:
        q = measured.get("quant")
        if q and geom.get("quant") and q != geom["quant"]:
            warnings.append(f"квант в реестре ({q}) не совпадает с фактическим из заголовка "
                            f"({geom['quant']}): реестр относится к другой сборке файла")
    else:
        warnings.append("модели нет в реестре замеренных: параметры подобраны по формуле и по "
                        "правилу для этого класса моделей, а не по прямому замеру этой модели")

    candidates: list[dict] = []
    kv_skipped: list[str] = []
    for eng in order:
        rules = rules_for(eng)
        if kv_type not in KV_BY_ENGINE[eng]:
            kv_skipped.append(f"{eng} не принимает квант KV {kv_type} "
                              f"(его список: {', '.join(KV_BY_ENGINE[eng])})")
            warnings.append(kv_skipped[-1] + " - движок отложен, чтобы не выдавать строку "
                            "запуска с флагом, который движок отвергает")
            continue
        m_window, m_row = measured_max(measured, eng)
        # Основанием «по замеру» окно бывает только на том кванте, на котором мерилось:
        # реестр не знает, сколько весит KV при другом.
        b_window = m_window if kv_type == KV_MEASURED else None
        cons_rule, cons_fit = ladder_max(geom, eng, vram, kv_type=kv_type)
        opt_rule, opt_fit = (None, None)
        if eng == "llama":
            opt_rule, opt_fit = ladder_max(geom, eng, vram, LLAMA_REMAINDER["min_mib"], kv_type)
        if cons_rule is None:
            f0 = fit_of(geom, eng, rules[0], kv_type=kv_type)
            warnings.append(f"{eng}: минимальная ступень лесенки ({rules[0]['window']} токенов) "
                            f"требует {round(f0.total_mib)} МиБ из {round(vram)} - не влезает")
            continue

        if want_window:
            step = next((r for r in rules if r["window"] == want_window), None)
            if step is None:
                raise RecommendError(f"окна {want_window} нет в лесенке "
                                     f"({[r['window'] for r in rules]})")
            fw = fit_of(geom, eng, step, kv_type=kv_type)
            fw_opt = (fit_of(geom, eng, step, LLAMA_REMAINDER["min_mib"], kv_type)
                      if eng == "llama" else fw)
            fits = fw.total_mib <= vram
            candidates.append({"engine": eng, "window": want_window, "asked": True,
                               "fits": fits, "fits_optimistic": fw_opt.total_mib <= vram,
                               "basis": "measured" if b_window == want_window
                                        else "formula", "rule": step, "fit": fw.to_dict(),
                               "measured": b_window == want_window,
                               "launch": build_args(eng, gguf_path, want_window, step,
                                                    exe_strata if eng == "strata" else exe_llama,
                                                    threads, kv_type)})
            if not fits:
                msg = (f"{eng}: окно {want_window} требует {round(fw.total_mib)} МиБ "
                       f"> {round(vram)}")
                if eng == "llama" and not fits and fw_opt.total_mib <= vram:
                    msg += (f"; при лучшем из измеренных остатков ({LLAMA_REMAINDER['min_mib']} МиБ) "
                            f"выходит {round(fw_opt.total_mib)} МиБ - влезает. Границы остатка "
                            f"разомкнуты, ответ без живого прогона не даёт")
                warnings.append(msg)
            continue

        rule, f, basis = cons_rule, cons_fit, "formula"
        if b_window and b_window > cons_fit.window and abs(vram - BASE["vram_mib"]) < 1:
            # Формула занижает против факта на нашей же базе: идём за фактом и говорим об этом.
            rule = next((r for r in rules if r["window"] == b_window), cons_rule)
            f = fit_of(geom, eng, rule, kv_type=kv_type)
            basis = "measured"
            warnings.append(f"{eng}: формула по слагаемым остановилась на {cons_fit.window} "
                            f"токенов, а для этой модели замерено {m_window} "
                            f"(pp {m_row.get('pp')}, первичник {m_row.get('src', 'реестр')}): "
                            f"берём замеренное, потому что остаток видеопамяти под данную "
                            f"модель не калибровался")
        elif b_window == cons_fit.window:
            basis = "measured"
        if basis == "measured" and measured:
            step = next((r for r in rules if r["window"] == m_window), rule)
            # Параметры окна принадлежат замеру КОНКРЕТНОЙ модели, а не общему правилу окна:
            # у KAT IQ4_XS на 160k в реестре reserve 512 и src grid-2026-11-07.md:14, тогда как
            # общее правило окна несло reserve 1024 из профиля heretic Q4_K_M. Подпись
            # «замер этой модели» при чужих параметрах была ложной (замер 11.11, dry-run START).
            from_model = {k: m_row[k] for k in ("att_mb", "reserve_mib", "super_chunk", "mtp",
                                                "ncmoe")
                          if m_row.get(k) is not None}
            diff = {k: v for k, v in from_model.items() if step.get(k) != v}
            if diff:
                rule = {**step, **from_model, "src": m_row.get("src") or step["src"]}
                f = fit_of(geom, eng, rule, kv_type=kv_type)
                warnings.append(f"{eng}: параметры окна берутся из замера этой модели "
                                f"({', '.join('%s=%s' % kv for kv in diff.items())}, "
                                f"src {rule['src']}), а не из общего правила окна ({step['src']})")

        if opt_rule and opt_fit and opt_fit.window > cons_fit.window:
            warnings.append(f"{eng}: формула с худшим измеренным остатком даёт {cons_fit.window} "
                            f"токенов, с лучшим - {opt_fit.window}; между ними нужен живой прогон, "
                            f"комплект рекомендует меньшее (остаток: {LLAMA_REMAINDER['src']})")
        if f.window < max(LADDER):
            warnings.append(f"{eng}: предложено {f.window} токенов - следующая ступень не влезает "
                            f"в {round(vram)} МиБ по слагаемым {f.to_dict()}")
        if eng == "strata" and basis != "measured":
            warnings.append(STRATA_NOT_CALIBRATED)
        candidates.append({"engine": eng, "window": f.window, "asked": False, "fits": True,
                           "fits_optimistic": True,
                           "basis": basis, "rule": rule, "fit": f.to_dict(),
                           "formula_window": cons_fit.window,
                           "measured": basis == "measured",
                           "launch": build_args(eng, gguf_path, f.window, rule,
                                                exe_strata if eng == "strata" else exe_llama,
                                                threads, kv_type)})

    if not candidates:
        if kv_skipped:
            raise RecommendError(f"квант KV {kv_type}: {'; '.join(kv_skipped)} - "
                                 f"считать окно нечем, возьмите квант из списка движка")
        raise RecommendError("ни один движок не смог разместить даже минимальную ступень лесенки: "
                             "нужна видеопамять больше или модель легче")
    best = max(candidates, key=lambda c: c["window"])
    if not best["measured"]:
        warnings.append(f"окно {best['window']} для этой модели не мерилось: это расчёт по "
                        f"формуле, направление проверено на нашей базе, точность - ступень лесенки")

    link = None
    if measured:
        link = {"gguf": measured["gguf"], "hf_url": measured["hf_url"],
                "note": measured.get("note", "")}
    else:
        warnings.append("ссылки на загрузку нет: комплект не угадывает репозиторий по названию, "
                        "подставьте модель сами и сверяйте предупреждение выше")

    return {"model": {"file": geom.get("file"), "quant": geom.get("quant"),
                      "arch": geom.get("arch"), "block_count": geom.get("block_count"),
                      "expert_count": geom.get("expert_count"),
                      "expert_gib": round(float(geom.get("expert_gib", 0)), 2),
                      "dense_gib": round(float(geom.get("dense_gib", 0)), 2),
                      "gdn_mib_total": round(float(geom.get("gdn_mib_total", 0)), 1),
                      "kv_bytes_per_token": geom.get("kv_bytes_per_token")},
            "vram_mib": vram, "window": best["window"], "engine": best["engine"],
            "kv_type": kv_type,
            "basis": best["basis"], "rule": best["rule"], "fit": best["fit"],
            "asked": best["asked"], "fits": best["fits"],
            "fits_optimistic": best["fits_optimistic"],
            "launch": best["launch"],
            "remainder_mib": dict(LLAMA_REMAINDER),
            "alternatives": [{"engine": c["engine"], "window": c["window"],
                              "basis": c.get("basis"), "measured": c["measured"]}
                             for c in candidates],
            "measured": best["measured"], "model_link": link,
            "ladder": list(LADDER), "warnings": warnings}


def render_text(res: dict) -> str:
    """Человеческий вывод: что предложено, почему, чем мерить."""
    r = res["rule"]
    lines = [f"движок: {res['engine']}    окно: {res['window']} токенов    "
             f"видеопамять: {round(res['vram_mib'])} МиБ    KV: {res.get('kv_type', KV_TYPE)}"]
    m = res["model"]
    lines.append(f"модель: {m['file']}  квант экспертов {m['quant']}  "
                 f"слоёв {m['block_count']} MoE-слоёв всего {m['expert_gib']} ГиБ, "
                 f"плотная часть {m['dense_gib']} ГиБ")
    f = res["fit"]
    lines.append(f"расход: KV {f['kv_mib']} + attention {f['att_mib']} + запас {f['reserve_mib']}"
                 f" + GDN {f['gdn_mib']} + веса {f['weights_mib']}"
                 + (f" + остаток {f['remainder_mib']}" if f.get("remainder_mib") else "")
                 + f" = {f['total_mib']} МиБ")
    if res.get("basis") == "measured":
        lines.append("основание ответа: окно и параметры взяты из замера ЭТОЙ модели (реестр "
                     "первичнее формулы)")
    else:
        lines.append("основание ответа: расчёт по слагаемым видеопамяти, замера этой модели "
                     "на этом окне нет")
    lines.append(f"первичник правила: {r['src']}    "
                 f"параметры подобраны по замеру: {res['measured']}")
    l = res["launch"]
    lines.append("запуск: " + " ".join(f'"{x}"' if " " in str(x) else str(x) for x in l["args"]))
    if l["env"]:
        lines.append("окружение: " + " ".join(f"{k}={v}" for k, v in l["env"].items()))
    if res["model_link"]:
        lines.append(f"скачать модель: {res['model_link']['hf_url']}")
    for alt in res["alternatives"]:
        lines.append(f"альтернатива: {alt['engine']} {alt['window']} "
                     f"(по замеру: {alt['measured']})")
    for w in res["warnings"]:
        lines.append(f"ПРЕДУПРЕЖДЕНИЕ: {w}")
    return "\n".join(lines)


# --------------------------------------------------------------------------- selftest
def fake_geom(**over) -> dict:
    """Синтетическая геометрия - ТОЛЬКО для саботаж-контролей и проверок направления.

    Числа сняты с HauhauCS IQ4_XS (замер заголовка), но это не та модель, что в реестре:
    точность формулы меряется real_geoms() ниже, по настоящим снимкам."""
    g = {"file": "model.gguf", "arch": "qwen35moe", "quant": "iq4_xs", "block_count": 40,
         "expert_count": 256, "expert_gib": 15.94, "dense_gib": 1.495, "gdn_mib_total": 62.8,
         "expert_bytes_by_layer": [427819008] * 40,
         # Таблица KV собрана ИЗ gguf_meta.KV_BYTES при том же числе элементов KV на токен,
         # что у HauhauCS IQ4_XS (10240 = 5760 / (18/32)). Своим списком она неизбежно
         # разошлась бы с первичником, и контроль «каждый квант движка чем-то считается»
         # мерил бы копию, а не таблицу заголовка.
         "kv_bytes_per_token": {t: 10240 * b for t, b in gguf_meta.KV_BYTES.items()}}
    g.update(over)
    return g


# Контрольные точки формулы: пары (окно, ncmoe), по которым есть и вердикт, и первичник.
# health=True - прогон здоров (pp выше 600), False - измерен обвал. Строки - из
# docs/measurements/vram-audit-ncmoe-2026-11-09.md; короткое имя модели - поле short в
# kit/models.json.
LLAMA_AUDIT_POINTS = [
    ("heretic", 98304, 30, False, ":29 pp 60.65"),
    ("heretic", 98304, 31, True, ":30 pp 794.44"),
    ("heretic", 98304, 32, True, ":31 pp 858.10"),
    ("heretic", 98304, 33, True, ":32 pp 843.41"),
    ("heretic", 131072, 33, True, "harness/scripts/run_llama_heretic-q4km_128k.bat"),
    ("heretic", 163840, 33, True, "harness/scripts/run_llama_heretic-q4km_160k.bat"),
    ("kat", 98304, 30, True, ":16 pp 769.56"),
    ("kat", 98304, 32, True, ":65 pp 941.18"),
    ("kat", 131072, 30, True, ":72 pp 900.33"),
    ("kat", 131072, 32, True, ":73 pp 866.55"),
    ("hauhaucs", 98304, 30, True, ":17 pp 973.37"),
    ("hauhaucs", 98304, 32, True, ":66 pp 936.40"),
    ("hauhaucs", 131072, 32, True, ":74 pp 876.99"),
]


def real_geoms(models_path: pathlib.Path) -> dict:
    """Измеренные геометрии из реестра - только по ним и меряется точность формулы."""
    models = load_models(models_path)
    out = {}
    for name, m in models.items():
        if m.get("geom"):
            out[str(m.get("short") or name).lower()] = dict(m["geom"], file=name)
    if not out:
        raise RecommendError(f"в {models_path} нет ни одной геометрии (блок geom пуст у всех): "
                             f"контроль точности формулы состояться не мог")
    return out


def selftest(models_path: pathlib.Path | None = None) -> int:
    fails: list[str] = []

    def check(label, got, want):
        ok = got == want
        print(f"  [{'ok  ' if ok else 'FAIL'}] {label}: получено {got!r}, ожидалось {want!r}")
        if not ok:
            fails.append(label)

    cfg_base = {"gpu": {"name": "RTX 3060 Ti", "vram_mib": BASE["vram_mib"], "cc": BASE["cc"]},
                "cpu": {"physical": BASE["cpu_physical"]}, "ram": {"total_gib": BASE["ram_gib"]}}
    models = {"model.gguf": {"gguf": "model.gguf", "quant": "iq4_xs",
                             "hf_url": "https://huggingface.co/example/repo/resolve/main/model.gguf",
                             "windows": [{"window": w, "engine": "strata", "pp": 1300.0,
                                          "src": "docs/measurements/grid-2026-11-08.md:1"}
                                         for w in LADDER]}}

    res = recommend(fake_geom(), cfg_base, models, gguf_path="model.gguf")
    check("окно на базе - из лесенки", res["window"] in LADDER, True)
    check("движок на базе - Страта (измерена быстрее llama на 96k и 128k)", res["engine"], "strata")
    check("параметры окна несут первичник", bool(res["rule"]["src"]), True)
    check("для замеренной модели ответ помечен как измеренный", res["measured"], True)
    check("основание ответа - замер, а не формула", res["basis"], "measured")
    check("ссылка на загрузку отдана", res["model_link"]["gguf"], "model.gguf")
    check("сумма слагаемых меньше видеопамяти", res["fit"]["total_mib"] < BASE["vram_mib"], True)
    check("потолок лесенки - 224k, больше не обещаем", res["window"], max(LADDER))

    more = recommend(fake_geom(), {"gpu": {"name": "RTX 5080", "vram_mib": 16303, "cc": "120"},
                                   "cpu": {"physical": 16}, "ram": {"total_gib": 95.7}},
                     models, gguf_path="model.gguf")
    check("на 16 ГиБ окно не меньше, чем на 8", more["window"] >= res["window"], True)
    kvs = [fit_strata(fake_geom(), r["window"], r).kv_mib for r in
           sorted(STRATA_RULES, key=lambda x: x["window"])]
    check("KV-расход растёт с окном монотонно", kvs == sorted(kvs) and len(set(kvs)) == len(kvs), True)

    weak = {"gpu": {"name": "GTX 1660", "vram_mib": 6144, "cc": "75"},
            "cpu": {"physical": 4}, "ram": {"total_gib": 16.0}}
    res_weak = recommend(fake_geom(), weak, models, gguf_path="model.gguf")
    check("слабое железо получает предупреждение", bool(res_weak["warnings"]), True)
    check("слабое железо не получает окно больше базы", res_weak["window"] <= res["window"], True)
    cls = classify(weak, ["86", "89", "120"], "elf-proof.json")
    check("класс слабой машины - ниже базы", cls["class"] in ("below", "weak"), True)
    check("для чужой архитектуры есть жалоба на cubin",
          any("sm_75" in w for w in cls["warnings"]), True)

    # ---------------- квант KV как параметр гейта (фикс #5715: цена окна зависит от кванта) --
    # Без этого гейт считал окно всегда по q4_0 и печатал в строке запуска тот же q4_0, а
    # выбор другого кванта пользователем остался бы вообще без пересчёта.
    for eng, names in KV_BY_ENGINE.items():
        for name, table_key in names.items():
            check(f"{eng}: квант {name} имеет цену KV в заголовке",
                  kv_bytes_per_token(fake_geom(), table_key) > 0, True)
    check("у движков есть квант, известный только одному (иначе отсев пуст)",
          "q4_1" in KV_BY_ENGINE["llama"] and "q4_1" not in KV_BY_ENGINE["strata"], True)
    q4 = recommend(fake_geom(), cfg_base, models, gguf_path="model.gguf", engine="strata")
    q51 = recommend(fake_geom(), cfg_base, models, gguf_path="model.gguf", engine="strata",
                    kv_type="q5_1")
    check("q5_1 дороже на токен, чем q4_0",
          q51["fit"]["parts"]["kv_per_token_bytes"] > q4["fit"]["parts"]["kv_per_token_bytes"],
          True)
    check("более дорогой квант не обещает более широкое окно", q51["window"] <= q4["window"], True)
    check("на замеренном кванте основание - замер", (q4["basis"], q4["measured"]),
          ("measured", True))
    check("на чужом кванте основание - расчёт", (q51["basis"], q51["measured"]),
          ("formula", False))
    check("на чужом кванте есть предупреждение про реестр",
          any("реестр окон сняты" in w for w in q51["warnings"]), True)
    check("строка запуска несёт выбранный квант",
          q51["launch"]["args"][q51["launch"]["args"].index("--kv-type") + 1], "q5_1")
    check("llama принимает квант, которого нет у Страты",
          recommend(fake_geom(), cfg_base, models, gguf_path="model.gguf", engine="llama",
                    kv_type="q4_1")["fit"]["parts"]["kv_type"], "q4_1")

    # Модель не из реестра: ответ обязан остаться, но «измеренность» и ссылка - нет.
    res_unknown = recommend(fake_geom(), cfg_base, models, gguf_path="other.gguf")
    check("незнакомая модель: измеренности нет", res_unknown["measured"], False)
    check("незнакомая модель: основание - формула", res_unknown["basis"], "formula")
    check("незнакомая модель: ссылки на загрузку не выдумано", res_unknown["model_link"], None)
    check("незнакомая модель: предупреждение есть",
          any("реестре" in w for w in res_unknown["warnings"]), True)

    # Явное окно: влезает и не влезает.
    ask = recommend(fake_geom(), cfg_base, models, gguf_path="model.gguf", want_window=163840)
    check("запрошенное окно возвращено", ask["window"], 163840)
    check("запрошенное окно честно помечено по разбору слагаемых",
          ask["fits"] == (ask["fit"]["total_mib"] < BASE["vram_mib"]), True)
    impossible = {"gpu": {"name": "GT 1030", "vram_mib": 2048, "cc": "75"},
                  "cpu": {"physical": 2}, "ram": {"total_gib": 8.0}}
    try:
        recommend(fake_geom(), impossible, models, gguf_path="model.gguf")
        fails.append("маленькая память: ожидался отказ")
        print("  [FAIL] маленькая память: ответ дан без отказа")
    except RecommendError as exc:
        print(f"  [ok  ] маленькая память: отказ с причиной «{exc}»")

    # ------------------------- точность формулы по 13 точкам ЗАМЕРЕННОГО VRAM-аудита -----
    # Главная мера п. 4.5 («отклонение не больше ступени, направление не враньё») считается
    # двумя отдельными счётчиками, потому что расхождения стоят разных денег: обещать окно
    # там, где измерен обвал, - врать; занижать - потерять скорость, но не сломать прогон.
    if models_path is None:
        models_path = pathlib.Path(__file__).resolve().parent / "models.json"
    try:
        geoms = real_geoms(models_path)
    except RecommendError as exc:
        print(f"  [FAIL] ПРОВЕРКА НЕ СОСТОЯЛАСЬ: {exc}")
        return 2
    print(f"  [info] геометрий из реестра: {len(geoms)} ({', '.join(sorted(geoms))})")
    by_window = {r["window"]: r for r in LLAMA_RULES}
    danger: list[str] = []
    strict: list[str] = []
    matched = 0
    for short, window, ncmoe, health, anchor in LLAMA_AUDIT_POINTS:
        g = geoms.get(short)
        if g is None:
            danger.append(f"{short}: геометрии нет в реестре ({sorted(geoms)}) - точка не сверена")
            continue
        matched += 1
        total = fit_llama(g, window, dict(by_window.get(window, LLAMA_RULES[0]),
                                          ncmoe=ncmoe), LLAMA_REMAINDER["max_mib"]).total_mib
        fits = total <= BASE["vram_mib"]
        if fits and not health:
            danger.append(f"{short} {window} ncmoe {ncmoe}: формула обещает влезть "
                          f"({round(total)} МиБ), а по замеру обвал ({anchor})")
        if not fits and health and by_window.get(window, {}).get("ncmoe") == ncmoe:
            strict.append(f"{short} {window} ncmoe {ncmoe}: формула даёт {round(total)} МиБ > "
                          f"{BASE['vram_mib']}, а по замеру здоров ({anchor}) - и это тот самый "
                          f"ncmoe, который рекомендует правило окна")
    check("точек аудита сопоставлено с реестром", matched >= 12, True)
    check("опасных расхождений (обещает там, где измерен обвал)", danger, [])
    check("занижений на рекомендованном правилу ncmoe", strict, [])
    print(f"  [info] остаток {LLAMA_REMAINDER['min_mib']}..{LLAMA_REMAINDER['max_mib']} МиБ; "
          f"первичник: {LLAMA_REMAINDER['src']}")

    # Реестр первичнее формулы: где окно замерено этим движком, ответ обязан быть измеренным.
    for short, g in sorted(geoms.items()):
        r = recommend(g, cfg_base, load_models(models_path), gguf_path=g["file"], engine="llama")
        if r["measured"]:
            check(f"{short}: замеренное окно не перебито формулой",
                  r["basis"] == "measured" and r["window"] in LADDER, True)

    # саботаж-контроли: каждый обязан дать RecommendError с причиной
    def sabotage(label, fn):
        try:
            fn()
        except RecommendError as exc:
            print(f"  [ok  ] саботаж {label}: пойман с причиной «{exc}»")
        except Exception as exc:  # noqa: BLE001
            fails.append(label)
            print(f"  [FAIL] саботаж {label}: пойман НЕ RecommendError, а {type(exc).__name__}: {exc}")
        else:
            fails.append(label)
            print(f"  [FAIL] саботаж {label}: принят молча - мера не состоялась")

    def no_vram():
        recommend(fake_geom(), {"gpu": {"name": "x"}}, models, gguf_path="model.gguf")
    sabotage("нет vram_mib", no_vram)

    def no_kv():
        recommend(fake_geom(kv_bytes_per_token={}), cfg_base, models, gguf_path="model.gguf")
    sabotage("нет расчёта KV", no_kv)

    def bad_window():
        recommend(fake_geom(), cfg_base, models, gguf_path="model.gguf", want_window=12345)
    sabotage("окно вне лесенки", bad_window)

    def bad_kv():
        recommend(fake_geom(), cfg_base, models, gguf_path="model.gguf",
                  engine="strata", kv_type="q4_1")
    sabotage("квант KV, которого нет у выбранного движка", bad_kv)

    def unknown_kv():
        recommend(fake_geom(), cfg_base, models, gguf_path="model.gguf", kv_type="q9_9")
    sabotage("квант KV, которого нет ни у одного движка", unknown_kv)

    tmp = pathlib.Path(__file__).resolve().parent / "_selftest-models.json"
    try:
        tmp.write_text(json.dumps({"models": []}), encoding="utf-8")
        sabotage("пустой models.json", lambda: load_models(tmp))
        tmp.write_text("{это не json", encoding="utf-8")
        sabotage("битый JSON в models.json", lambda: load_models(tmp))
        tmp.write_text(json.dumps({"models": [{"gguf": "a.gguf"}]}), encoding="utf-8")
        sabotage("запись без hf_url и окон", lambda: load_models(tmp))
        sabotage("нет файла реестра",
                 lambda: load_models(tmp.with_name("net-takogo-net-file.json")))
    finally:
        tmp.unlink(missing_ok=True)

    # Переносимость: в ответе не должно быть путей стенда. Сами префиксы собраны из кусков,
    # потому что та же проверка живёт grep'ом по дереву комплекта (мера «переносимость» в
    # README), и собственный код проверки не должен попадаться в ней как нарушение.
    blob = json.dumps(res, ensure_ascii=False) + render_text(res)
    slash = chr(92)
    for needle in ("D:" + slash, "F:" + slash, "C:" + slash + "Users"):
        check(f"в выводе нет пути стенда {needle}", needle in blob, False)
    check("детерминизм: два вызова равны",
          json.dumps(recommend(fake_geom(), cfg_base, models, gguf_path="model.gguf"),
                     ensure_ascii=False, sort_keys=True),
          json.dumps(recommend(fake_geom(), cfg_base, models, gguf_path="model.gguf"),
                     ensure_ascii=False, sort_keys=True))

    print(f"\nselftest recommend: {'OK' if not fails else 'ПРОВАЛЕНО ' + str(len(fails)) + ': ' + ', '.join(fails)}")
    return 0 if not fails else 1


def main() -> int:
    ap = argparse.ArgumentParser(description="подбор окна и параметров под модель и железо")
    ap.add_argument("--gguf", help="путь к .gguf")
    ap.add_argument("--config", help="JSON от kit\\detect.py; без него железо меряется самому")
    ap.add_argument("--fake-config", help="тот же JSON, но подставной: проверка без смены железа")
    ap.add_argument("--models", help="реестр замеренных моделей (по умолчанию kit\\models.json)")
    ap.add_argument("--engine", default="auto", choices=["auto", "strata", "llama"])
    ap.add_argument("--kv-type", default=KV_TYPE,
                    choices=sorted({t for n in KV_BY_ENGINE.values() for t in n}),
                    help=f"квант KV-кэша, под который считается окно; по умолчанию {KV_TYPE} - "
                         f"на нём снята лесенка и весь реестр. Множества у движков разные: "
                         f"Страта - {', '.join(KV_BY_ENGINE['strata'])}; "
                         f"llama.cpp - {', '.join(KV_BY_ENGINE['llama'])}")
    ap.add_argument("--window", type=int, help="проверить конкретное окно, а не максимум")
    ap.add_argument("--exe-strata", default="bin\\strata-q36.exe")
    ap.add_argument("--exe-llama", default="bin\\llama-server.exe")
    ap.add_argument("--kit-dir", help="каталог комплекта, где лежит elf-proof.json "
                                      "(по умолчанию - рядом с kit\\)")
    ap.add_argument("--json", action="store_true", help="machine-readable вывод")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()

    models_path = pathlib.Path(a.models) if a.models else \
        pathlib.Path(__file__).resolve().parent / "models.json"
    if a.selftest:
        return selftest(models_path)
    if not a.gguf:
        print("нужен --gguf <путь> либо --selftest", file=sys.stderr)
        return 2
    try:
        out = gguf_meta.parse(pathlib.Path(a.gguf))
        geom = gguf_meta.geometry(out)
    except gguf_meta.GgufError as exc:
        print(f"[FAIL] заголовок GGUF не разобран: {exc}", file=sys.stderr)
        return 2
    if not geom.get("bpw_ok"):
        print(f"[FAIL] сверка байт-на-вес не прошла "
              f"(max_rel_diff={geom.get('bpw_max_rel_diff')}, "
              f"неизвестные типы {geom.get('bpw_unknown')}): геометрии не доверяем",
              file=sys.stderr)
        return 2

    fake = pathlib.Path(a.fake_config) if a.fake_config else \
        (pathlib.Path(a.config) if a.config else None)
    if fake:
        import detect
        try:
            cfg = detect.load_fake(fake)
        except (OSError, ValueError) as exc:
            print(f"[FAIL] {fake}: {exc}", file=sys.stderr)
            return 2
    else:
        import detect
        cfg = detect.detect(a.gguf)
    lack = detect.missing_required(cfg)
    if lack:
        print(f"[FAIL] конфигурация железа неполная, не снято: {', '.join(lack)} - "
              f"по такому железу окно предсказывать нельзя", file=sys.stderr)
        return 2
    try:
        kit_dir = pathlib.Path(a.kit_dir) if a.kit_dir else \
            pathlib.Path(__file__).resolve().parent
        archs, archs_source, archs_warn = classify_mod.kit_archs(None, kit_dir)
    except ValueError as exc:
        print(f"[FAIL] архитектуры комплекта: {exc}", file=sys.stderr)
        return 2
    try:
        models = load_models(models_path)
        res = recommend(geom, cfg, models, engine=a.engine, want_window=a.window,
                        gguf_path=a.gguf, exe_strata=a.exe_strata, exe_llama=a.exe_llama,
                        kv_type=a.kv_type)
    except RecommendError as exc:
        print(f"[FAIL] {exc}", file=sys.stderr)
        return 2
    cls = classify_mod.classify(cfg, archs, archs_source)
    res["classification"] = {"class": cls.get("class"), "label": cls.get("label"),
                             "axes": cls.get("axes"), "limits": cls.get("limits")}
    res["warnings"] = archs_warn + cls.get("warnings", []) + res["warnings"]
    if a.json:
        print(json.dumps(res, ensure_ascii=False, indent=1))
    else:
        print(render_text(res))
    return 1 if res["warnings"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
