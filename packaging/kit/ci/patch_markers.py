#!/usr/bin/env python3
"""Гейт «наши патчи в собранном бинарнике»: сверяет реестр маркеров с байтами exe/dll.

Мера нужна потому, что зелёная сборка в GitHub Actions не доказывает наличие наших патчей:
 Actions может собрать чистое дерево апстрима (не тот ref, не тот worktree, потерянная ветка),
 и лог сборки выглядел бы ровно так же. Реестр `patch-markers.json` снят 12.11 по-настоящему
 меркой (`ci_binary_markers2_2026-11-12.py`) со стендовых сборок и содержит только те имена,
 которые бинарник Способен нести: строковые литералы (имена переменных среды, CLI-флаги,
 тексты ошибок) и имена `__global__`-ядер из fatbin. Локальные имена функций компилятор не
 сохраняет, поэтому покрытие коммитов меньше их числа - и это зафиксировано в реестре, а не
 прячется за «все 72 коммита проверены».

Вызов:
    python packaging/kit/ci/patch_markers.py --engine strata --bin <путь к exe> [--bin ...]
    python packaging/kit/ci/patch_markers.py --engine llama --bin <ggml-cuda.dll> --bin <llama.dll>
        --out patch-markers-proof.json
    python packaging/kit/ci/patch_markers.py --selftest

Коды возврата: 0 - все маркеры движка найдены в переданных бинарниках; 1 - хотя бы один маркер
пропал (это либо чужое дерево, либо утраченный патч - список токенов печатается); 2 - вход неверен
(нет реестра, движок не в реестре, не передан носитель маркеров, бинарник пуст или не читается) -
то есть проверка не состоялась, и её результат нельзя принимать за «патчи на месте».
"""

from __future__ import annotations

import argparse
import json
import sys
import tempfile
from pathlib import Path

# Маркер обязан быть ASCII: побайтный поиск по exe/dll не видит кириллицу (она живёт в UTF-16
# секции #US), и не-ASCII маркер вечно светился бы красным при собранном патче.
ASCII_ONLY = True


def load_registry(path: Path) -> dict:
    """Реестр маркеров; отказ - исключением с причиной, а не пустым словарём."""
    if not path.is_file():
        raise ValueError(f"реестр не найден: {path}")
    raw = path.read_bytes()
    if len(raw) < 200:
        raise ValueError(f"реестр {len(raw)} Б - обрезан или пуст, проверка не состоялась")
    try:
        reg = json.loads(raw.decode("utf-8"))
    except Exception as e:  # noqa: BLE001 - причина отказа обязана дочиться человеком
        raise ValueError(f"реестр не читается как JSON: {e}") from e
    if not isinstance(reg, dict) or not isinstance(reg.get("engines"), dict) or not reg["engines"]:
        raise ValueError("в реестре нет раздела engines - не по чему сверять")
    for name, eng in reg["engines"].items():
        if not isinstance(eng.get("list"), list) or not eng["list"]:
            raise ValueError(f"у движка '{name}' пустой список маркеров - мерка ничего не нашла")
        for m in eng["list"]:
            for key in ("token", "kind", "commit", "bins"):
                if key not in m:
                    raise ValueError(f"у маркера движка '{name}' нет поля '{key}': {m}")
            if ASCII_ONLY and not m["token"].isascii():
                raise ValueError(
                    f"маркер '{m['token'][:40]}' не ASCII: побайтный поиск по exe/dll его "
                    "не увидит даже при собранном патче (кириллица живёт в UTF-16 #US)")
    return reg


def carriers(eng: dict) -> list[str]:
    """Отсортированные имена бинарников, которые обязан передаться в гейт."""
    return sorted({b for m in eng["list"] for b in m["bins"]})


def check(eng: dict, blobs: dict[str, bytes]) -> tuple[list[dict], list[dict]]:
    """(найденные, пропавшие) маркеры относительно переданных носителей.

    Маркер сверяется только с теми бинарниками, где его нашла мерка: требовать `GGML_MOE_HIST`
    от ggml-base.dll - значит выдумывать провал. Но если нужного носителя нет в blobs, это
    не «пропал маркер», а «проверка не состоялась» - за это отвечает вызывающий.
    """
    found: list[dict] = []
    missing: list[dict] = []
    for m in eng["list"]:
        tok = m["token"].encode("utf-8")
        hit_bins = [b for b in m["bins"] if b in blobs and tok in blobs[b]]
        if len(hit_bins) == len(m["bins"]):
            found.append(m)
        else:
            missing.append({**{k: m[k] for k in ("token", "kind", "commit", "subject")},
                            "wanted": m["bins"], "hit": hit_bins})
    return found, missing


def commits_covered(eng: dict, found: list[dict]) -> int:
    return len({m["commit"] for m in found})


def main() -> int:
    ap = argparse.ArgumentParser(description=(__doc__ or "").splitlines()[0])
    ap.add_argument("--registry", help="реестр маркеров (по умолчанию рядом со скриптом)")
    ap.add_argument("--engine", help="strata или llama")
    ap.add_argument("--bin", action="append", default=[], dest="bins",
                    help="путь к собранному exe/dll (повторяется)")
    ap.add_argument("--out", help="куда записать JSON-меру (пути в неё не пишутся)")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()

    if a.selftest:
        return selftest()

    reg_path = Path(a.registry) if a.registry else Path(__file__).with_name("patch-markers.json")
    try:
        reg = load_registry(reg_path)
    except ValueError as e:
        print(f"ОТКАЗ: {e}", file=sys.stderr)
        return 2
    if not a.engine:
        print(f"ОТКАЗ: --engine обязателен (в реестре: {', '.join(sorted(reg['engines']))})",
              file=sys.stderr)
        return 2
    if a.engine not in reg["engines"]:
        print(f"ОТКАЗ: движка '{a.engine}' в реестре нет (есть {', '.join(sorted(reg['engines']))}) "
              "- проверка не состоялась", file=sys.stderr)
        return 2
    eng = reg["engines"][a.engine]

    if not a.bins:
        print("ОТКАЗ: ни одного --bin: сравнивать не с чем", file=sys.stderr)
        return 2
    blobs: dict[str, bytes] = {}
    for p in a.bins:
        f = Path(p)
        if not f.is_file():
            print(f"ОТКАЗ: бинарник не найден: {f}", file=sys.stderr)
            return 2
        data = f.read_bytes()
        if not data:
            print(f"ОТКАЗ: {f.name} 0 Б - проверка не состоялась", file=sys.stderr)
            return 2
        blobs[f.name.lower()] = data
        print(f"{f.name}: {len(data):,} Б")

    need = carriers(eng)
    absent = [c for c in need if c.lower() not in blobs]
    if absent:
        print("ОТКАЗ: не переданы носители маркеров: " + ", ".join(absent) +
              f" (движок '{a.engine}' ждёт {', '.join(need)}) - часть патчей не проверена",
              file=sys.stderr)
        return 2
    extra = sorted(set(blobs) - {c.lower() for c in need})
    if extra:
        print(f"ВНИМАНИЕ: переданы лишние бинарники, сверка по ним не определена: {', '.join(extra)}")

    found, missing = check(eng, blobs)
    total = len(eng["list"])
    cov = commits_covered(eng, found)
    print(f"{a.engine}: маркеров {len(found)}/{total}, коммитов с подтверждённым маркером "
          f"{cov} из {eng['commits_with_marker']}")
    for m in missing:
        print(f"  ПРОПАЛ [{m['kind']}] {m['token']!r} (коммит {m['commit']}): "
              f"искали в {', '.join(m['wanted'])}, "
              + (f"нашли в {', '.join(m['hit'])}" if m["hit"] else "нет ни в одном носителе"))

    if a.out:
        measure = {
            "engine": a.engine,
            "registry_version": reg.get("version"),
            "markers_total": total,
            "markers_found": len(found),
            "markers_missing": [{k: m[k] for k in ("token", "kind", "commit")} for m in missing],
            "commits_covered": cov,
            "commits_with_marker": eng["commits_with_marker"],
            "carriers": need,
            "binaries": [{"name": k, "bytes": len(v)} for k, v in sorted(blobs.items())],
            "result": "ok" if not missing else "есть пропавшие маркеры",
            "note": eng.get("carrier_note", ""),
        }
        Path(a.out).write_text(json.dumps(measure, ensure_ascii=False, indent=2) + "\n",
                              encoding="utf-8")
        print(f"мера: {Path(a.out).name}")

    return 1 if missing else 0


def selftest() -> int:
    ok, bad = 0, 0

    def chk(name: str, got, want) -> None:
        nonlocal ok, bad
        if str(got) == str(want):
            ok += 1
            print(f"  ok   {name}")
        else:
            bad += 1
            print(f"FAIL   {name}: получено '{got}', ожидалось '{want}'")

    real = Path(__file__).with_name("patch-markers.json")
    reg = load_registry(real)
    chk("реестр рядом со скриптом читается", ", ".join(sorted(reg["engines"])), "llama, strata")
    tok_all = [m["token"] for e in reg["engines"].values() for m in e["list"]]
    chk("все маркеры ASCII (иначе поиск слеп)", all(t.isascii() for t in tok_all), True)
    chk("маркеры не дублируются внутри движка",
        len({(k, t) for k, e in reg["engines"].items() for t in
             [m["token"] for m in e["list"]]}), len(tok_all))
    chk("носители Страты - два exe", carriers(reg["engines"]["strata"]),
        ["strata-q36.exe", "strata.exe"])
    chk("носители llama - три dll", carriers(reg["engines"]["llama"]),
        ["ggml-base.dll", "ggml-cuda.dll", "llama.dll"])

    # Цифры реестра обязаны следовать за списком маркеров: после синка апстрима файл иначе
    # врёт молча - гейт печатает «покрыто 12 из 72», хотя наших коммитов уже 81.
    for e_name, eng in reg["engines"].items():
        chk(f"{e_name}: markers равен длине списка", eng.get("markers"), len(eng["list"]))
        chk(f"{e_name}: commits_with_marker равен множеству commit списка",
            eng.get("commits_with_marker"), len({m["commit"] for m in eng["list"]}))
        chk(f"{e_name}: покрыто не больше, чем наших коммитов",
            eng["commits_with_marker"] <= eng["commits_ours"], True)
        chk(f"{e_name}: правило съёмки записано в реестре", bool(eng.get("marker_rule")), True)

    # Подложка: бинарник, в который вручную положены ВСЕ маркеры движка, обязан дать zero missing.
    tmp = Path(tempfile.mkdtemp(prefix="patch-markers-"))
    try:
        for e_name, eng in reg["engines"].items():
            fake = {b.lower(): b"".join(m["token"].encode() + b"\0"
                                        for m in eng["list"] if b in m["bins"])
                    for b in carriers(eng)}
            found, missing = check(eng, fake)
            chk(f"подложка {e_name}: пропавших нет", len(missing), 0)
            chk(f"подложка {e_name}: найдено ровно число маркеров", len(found), len(eng["list"]))
            chk(f"подложка {e_name}: покрытие коммитов равно реестровому",
                commits_covered(eng, found), eng["commits_with_marker"])

        # Саботаж 1: вырезали один маркер - гейт обязан назвать именно его, а не «всё пропало».
        eng = reg["engines"]["llama"]
        fake = {b.lower(): b"".join(m["token"].encode() + b"\0"
                                    for m in eng["list"] if b in m["bins"])
                for b in carriers(eng)}
        victim = eng["list"][0]
        fake[victim["bins"][0].lower()] = fake[victim["bins"][0].lower()].replace(
            victim["token"].encode(), b"")
        found, missing = check(eng, fake)
        chk("саботаж: пропал ровно один маркер", len(missing), 1)
        chk("саботаж: назван именно вырезанный токен", missing[0]["token"], victim["token"])
        chk("саботаж: осталось найдено на один меньше", len(found), len(eng["list"]) - 1)

        # Саботаж 2: маркер обязан искаться в СВОИХ носителях. Добавив токен в чужой файл,
        # нельзя заставить гейт требовать его оттуда - иначе тест не ловит перепутанные dll.
        other = {b.lower(): b"".join(m["token"].encode() + b"\0"
                                     for m in eng["list"] if b in m["bins"])
                 for b in carriers(eng)}
        only_base = {"ggml-base.dll": other["ggml-base.dll"]}
        f2, m2 = check({**eng, "list": [x for x in eng["list"] if x["bins"] == ["ggml-base.dll"]]},
                       only_base)
        chk("сверка идёт по назначенным носителям", len(m2), 0)
        chk("и такие маркеры найдены", len(f2) > 0, True)

        # Пустой бинарник не должен читаться как «маркеров нет, но мы не при чём»: 0 Б - это
        # вход, а не результат, и решает это вызывающий (main возвращает 2 до сравнения).
        f3, m3 = check(eng, {"ggml-base.dll": b"", "ggml-cuda.dll": b"x", "llama.dll": b"x"})
        chk("пустой носитель даёт пропавшие маркеры, а не ноль проверок", len(m3) > 0, True)

        # Отрезанный реестр обязан быть отказом, а не «движков нет».
        (tmp / "cut.json").write_bytes(real.read_bytes()[:120])
        try:
            load_registry(tmp / "cut.json")
            chk("обрезанный реестр - отказ", "не бросил", "бросил")
        except ValueError:
            chk("обрезанный реестр - отказ", "бросил", "бросил")
        try:
            load_registry(tmp / "missing.json")
            chk("несуществующий реестр - отказ", "не бросил", "бросил")
        except ValueError:
            chk("несуществующий реестр - отказ", "бросил", "бросил")

        # Не-ASCII маркер в реестре - отказ при загрузке: иначе гейт вечно светится красным
        # по патчу, который побайтным поиском проверить нельзя.
        bad_reg = {"version": 1, "engines": {"x": {"list": [
            {"token": "ива", "kind": "literal", "commit": "abc", "bins": ["x.dll"]}]}}}
        (tmp / "cjk.json").write_text(json.dumps(bad_reg, ensure_ascii=False), encoding="utf-8")
        try:
            load_registry(tmp / "cjk.json")
            chk("не-ASCII маркер - отказ загрузки", "не бросил", "бросил")
        except ValueError:
            chk("не-ASCII маркер - отказ загрузки", "бросил", "бросил")
    finally:
        import shutil
        shutil.rmtree(tmp, ignore_errors=True)

    print(f"patch_markers selftest: ok={ok} bad={bad}")
    # Обрезанный или изменённый блок выглядел бы как «провалов нет»: порог проверок - часть меры.
    if (ok + bad) < 24:
        print("ИТОГ: проверок меньше 24 - мера не состоялась")
        return 2
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
