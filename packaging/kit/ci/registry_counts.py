#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Мера реестра маркеров: переснимает числа и происхождение каждого маркера из git-истории.

Реестр `patch-markers.json` утверждает три вещи, которые нельзя проверить в самом Actions:
число наших коммитов, что маркер взят из «+»-строки названного коммита, и что имени маркера
нет в дереве базы апстрима. Причина - `actions/checkout` стоит с `fetch-depth: 1`, то есть
истории в раннере нет вовсе. Поэтому эта мерка живёт локально, на стенде, и только для съёмки:
гейт в Actions меряет другое - наличие маркеров в байтах exe/dll.

Снимок привязан к названной в реестре голове, а не к живому tip: реестр лежит в той же репе,
коммит не может записать собственный хеш, и сравнение с tip вечно давало бы ложное расхождение
на коммите, который этот реестр и правит. Поэтому утверждение «на коммите X от базы Y наших
коммитов N» проверяемо с любой головы ветки и переживает следующие коммиты.

Вызов:
    python registry_counts.py                       # только Страта
    python registry_counts.py --llama <рабочая копия llama.cpp с нашей веткой>
    python registry_counts.py --selftest

Коды возврата: 0 - реестр совпал с историей; 1 - есть расхождение (список печатается);
2 - проверка не состоялась (нет репозитория, нет истории, не передан --llama при съёмке llama,
реестр не читается) - то есть результат нельзя читать как «расхождений нет».
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

# Корень репы Страты: packaging/kit/ci -> на три уровня выше.
ENGINE_ROOT = Path(__file__).resolve().parents[3]
REGISTRY = Path(__file__).with_name("patch-markers.json")
# Правило съёмки: наши коммиты = не-мержи от точки ответвления до названной в реестре головы;
# голова пишется в реестр родителем, а не собственным хешем (см. measure).
BRANCH = {"strata": ("upstream/main", "main"), "llama": ("origin/master", "kit-all-sync")}
# Что обязан нести реестр на каждый движок: снимок числа и способ его снять.
SNAPSHOT = ("commits_ours", "commits_ours_cmd", "commits_ours_base",
            "commits_ours_head", "commits_ours_at", "commits_ours_note")


def git(repo: Path, *args: str) -> tuple[str, int]:
    p = subprocess.run(["git", "-C", str(repo), *args], capture_output=True,
                       text=True, encoding="utf-8", errors="replace")
    return p.stdout, p.returncode


def repo_or_die(name: str, path: Path | None) -> Path:
    """Репа движка: Страта берёт свой корень, у llama рабочая копия обязана прийти флагом.

    Путь из аргумента для Страты игнорируется намеренно: скрипт лежит внутри репы Страты,
    и выведенный из него корень - единственный переносимый способ его найти; стендовый путь
    в коде запрещён, иначе мерка годится лишь одному стенду.
    """
    if name == "strata":
        path = ENGINE_ROOT
    elif path is None:
        raise ValueError("у движка 'llama' рабочая копия передаётся только флагом --llama: "
                         "стендовый путь в коде запрещён, иначе мерка годится лишь одному стенду")
    if not (path / ".git").exists():
        raise ValueError(f"{path} не git-репозиторий - проверка не состоялась")
    return path


def measure(name: str, eng: dict, repo: Path) -> list[str]:
    """Список расхождений; пустой список = реестр совпал с историей по этому движку."""
    bad: list[str] = []
    if not eng["list"]:
        bad.append(f"{name}/list: список маркеров пуст - сверять нечего, "
                   "проверка не состоялась")
    up, branch = BRANCH[name]
    base, rc = git(repo, "merge-base", up, branch)
    if rc != 0:
        raise ValueError(f"нет истории: merge-base {up}..{branch} в {repo} не снимается")
    base = base.strip()
    if str(eng.get("commits_ours_base")) != base[:9]:
        bad.append(f"{name}/commits_ours_base: в реестре '{eng.get('commits_ours_base')}', "
                   f"по истории '{base[:9]}'")
    # Голову сверяем с названным в реестре коммитом, а не с живым tip: реестр лежит в репе
    # Страты, а коммит не может записать собственный хеш - сравнение с tip давало бы
    # ложное расхождение на каждом коммите, который правит этот реестр.
    rec_head = str(eng.get("commits_ours_head"))
    _, rc = git(repo, "rev-parse", "--verify", "--quiet", f"{rec_head}^{{commit}}")
    if rc != 0:
        bad.append(f"{name}/commits_ours_head: коммита '{rec_head}' в репе нет - "
                   "число неоткуда взять, привязка снимка ко времени потеряна")
    else:
        if git(repo, "merge-base", "--is-ancestor", rec_head, branch)[1] != 0:
            bad.append(f"{name}/commits_ours_head: '{rec_head}' не предок {branch} - "
                       "снимок взят вне нашей ветки")
        count, rc = git(repo, "rev-list", "--count", "--no-merges", f"{base}..{rec_head}")
        if rc != 0:
            raise ValueError(f"нет истории: rev-list по {base[:9]}..{rec_head} не прошёл")
        if str(eng.get("commits_ours")) != count.strip():
            bad.append(f"{name}/commits_ours: в реестре {eng.get('commits_ours')}, "
                       f"по истории {count.strip()}")
    cmd = str(eng.get("commits_ours_cmd"))
    if not all(w in cmd for w in ("merge-base", "rev-list", "--no-merges")):
        bad.append(f"{name}/commits_ours_cmd: в команде съёмки нет merge-base и rev-list "
                   "с --no-merges - число неотделимо от способа его снять")
    if not str(eng.get("commits_ours_note")).strip():
        bad.append(f"{name}/commits_ours_note: пустая оговорка - снимок числа Readable "
                   "как гейт, а это только документация")
    for m in eng["list"]:
        tok, sha = m["token"], m["commit"]
        diff, rc = git(repo, "show", sha)
        if rc != 0:
            bad.append(f"{name}/provenance {tok[:28]}: коммит {sha} не читается")
            continue
        if not any(tok in line for line in diff.splitlines() if line.startswith("+")):
            bad.append(f"{name}/provenance {tok[:28]}: имени нет в «+»-строках {sha}")
        _, rc = git(repo, "grep", "-l", "-F", "-e", tok, base, "--")
        if rc not in (0, 1):
            # Токен обязан идти после -e: без него «--cache-type-k» читается как флаг git,
            # мерка падает с rc 129 и молча выдаёт «имени в базе нет» на любой проверке.
            raise ValueError(f"нет проверки: git grep по {tok[:24]} вернул rc={rc} - "
                             "проверка базы не состоялась")
        if rc == 0:
            bad.append(f"{name}/absent {tok[:28]}: имя есть в дереве базы {base[:9]} - "
                       "это не наш маркер")
    return bad


def selftest() -> int:
    """Мерка обязана различать причины отказа, а не молчать зелёным на пустом входе."""
    ok, bad = 0, 0

    def chk(title: str, got, want) -> None:
        nonlocal ok, bad
        if str(got) == str(want):
            ok += 1
            print(f"  ok   {title}")
        else:
            bad += 1
            print(f"FAIL   {title}: получено '{got}', ожидалось '{want}'")

    try:
        reg = json.loads(REGISTRY.read_text(encoding="utf-8"))
    except Exception as e:  # noqa: BLE001
        print(f"ИТОГ: реестр не читается ({e}) - мера не состоялась")
        return 2
    for name, eng in reg["engines"].items():
        chk(f"{name}: реестр несёт снимок числа наших коммитов",
            all(k in eng for k in SNAPSHOT), True)
        chk(f"{name}: база и голова записаны как hex 7-9 знаков",
            all(len(str(eng[k])) in (7, 8, 9) and
                all(c in "0123456789abcdef" for c in str(eng[k]))
                for k in ("commits_ours_base", "commits_ours_head")), True)
        chk(f"{name}: число не меньше покрытого маркерами",
            eng["commits_ours"] >= eng["commits_with_marker"], True)
        chk(f"{name}: команда съёмки называет merge-base и rev-list без мержей",
            all(w in eng["commits_ours_cmd"]
                for w in ("merge-base", "rev-list", "--no-merges")), True)
        if name == "strata":
            chk(f"{name}: на живом дереве расхождений нет", measure(name, eng, ENGINE_ROOT), [])
    live = reg["engines"]["strata"]
    # Саботаж 1: число наших коммитов намеренно сдвинуто - мера обязана назвать расхождение,
    # иначе зелёный прогон неотличим от меры, которая ничего не сверяет.
    wrong = dict(live, commits_ours=int(live["commits_ours"]) + 7)
    chk("саботаж: сдвинутое число наших коммитов найдено",
        len([b for b in measure("strata", wrong, ENGINE_ROOT)
             if "/commits_ours:" in b]) >= 1, True)
    # Саботаж 2: голова снята с другой точки истории - мера обязана назвать именно это поле,
    # не трогая базу: на чужой базе rev-list падает, и это отказ, а не расхождение.
    shifted = dict(live, commits_ours_head="0000000")
    chk("саботаж: чужая голова названа по своему полю",
        len([b for b in measure("strata", shifted, ENGINE_ROOT)
             if "/commits_ours_head" in b]) == 1, True)
    # Саботаж 3: оговорка о снимке пуста - число снова читается как гейт, а это документация.
    blank = {**live, "commits_ours_note": ""}
    chk("саботаж: пустая оговорка снимка числа найдена",
        len([b for b in measure("strata", blank, ENGINE_ROOT) if "_note" in b]) >= 1, True)
    # Саботаж 4: маркер из несуществующего коммита и маркер, живущий в базе апстрима: оба
    # обязаны попасть в список, иначе происхождение сверяется только на словах.
    fake = dict(live, list=[{"token": "STRATA_Q36_SUPER_CHUNK", "kind": "literal",
                                  "commit": "deadbeef", "subject": "", "bins": ["strata.exe"]},
                                 {"token": "__global__", "kind": "kernel",
                                  "commit": "cc4da32c", "subject": "", "bins": ["strata.exe"]}])
    hits = measure("strata", fake, ENGINE_ROOT)
    chk("саботаж: коммита которого нет, назван", any("deadbeef" in b for b in hits), True)
    # Имя живёт в базе апстрима и попадает в «+»-строки нашего коммита: маркер обязан быть
    # назван именно чужим, иначе правило «имени нет в базе» сверяется только на словах.
    chk("саботаж: маркер из базы апстрима назван",
        any("/absent __global__" in b for b in hits), True)
    # Пустой список маркеров - не «всё хорошо», а отсутствующая проверка: движок без списка
    # обязан дать пустоту только вместе с отказом по числу, иначе съёмка молча пройдёт.
    chk("саботаж: пустой список маркеров не даёт проверенных патчей",
        measure("strata", dict(live, list=[]), ENGINE_ROOT) != [], True)
    # Чужая репа (каталог без .git) обязана быть отказом, а не нулём расхождений.
    try:
        repo_or_die("llama", None)
        chk("движок llama без рабочей копии - отказ", "не бросил", "бросил")
    except ValueError:
        chk("движок llama без рабочей копии - отказ", "бросил", "бросил")
    try:
        repo_or_die("llama", Path(__file__).parent)
        chk("репа без .git - отказ", "не бросил", "бросил")
    except ValueError:
        chk("репа без .git - отказ", "бросил", "бросил")
    print(f"registry_counts selftest: ok={ok} bad={bad}")
    if (ok + bad) < 10:
        print("ИТОГ: проверок меньше 10 - мера не состоялась")
        return 2
    return 1 if bad else 0


def main() -> int:
    ap = argparse.ArgumentParser(description=(__doc__ or "").splitlines()[0])
    ap.add_argument("--registry", help="реестр маркеров (по умолчанию рядом со скриптом)")
    ap.add_argument("--llama", help="рабочая копия llama.cpp с нашей веткой kit-all-sync")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    reg_path = Path(a.registry) if a.registry else REGISTRY
    if not reg_path.is_file():
        print(f"ОТКАЗ: реестр не найден: {reg_path}", file=sys.stderr)
        return 2
    try:
        reg = json.loads(reg_path.read_text(encoding="utf-8"))
    except Exception as e:  # noqa: BLE001
        print(f"ОТКАЗ: реестр не читается: {e}", file=sys.stderr)
        return 2
    names = ["strata"] + (["llama"] if a.llama else [])
    bad: list[str] = []
    try:
        for name in names:
            bad += measure(name, reg["engines"][name],
                           repo_or_die(name, Path(a.llama) if a.llama else None))
    except ValueError as e:
        print(f"ОТКАЗ: {e}", file=sys.stderr)
        return 2
    print(f"registry_counts: движков {len(names)}, расхождений {len(bad)}")
    for b in bad:
        print(f"  РАСХОЖДЕНИЕ {b}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
