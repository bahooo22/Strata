#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Носитель AST-замыкания импортов веб-морды: какие .py обязаны доехать до архива комплекта.

Зачем это нужно: доливайка морды описана СПИСКОМ ПРАВИЛ (packaging/kit/ci/pack_kit.ps1,
$WEB_SPECS), и правило, которое отстало от кода, молчит. Так и случилось: `import calibrate`
из strata_control/setup_config.py не перечислялся ни одним правилом, файл не ехал в архив, а
архив открывался нормально. Единственный способ поймать класс - разобрать импорты и сверить
результат с перечнем манифеста; семантика разбора взята из работающего контроля этого же
репозитория (engine/tests/terminal/test_monitor_bundle.py:286-306: ast.walk, ast.Import /
ast.ImportFrom, переход только туда, где файл реально лежит).

Разрешение имён повторяет механику CPython, а не список каталогов: serve/server.py:61-63
кладёт в sys.path корень дерева и корень/tools, поэтому модуль ищется как `<имя>.py` или
`<имя>/__init__.py` в каждой записи sys.path по порядку. Отсюда три следствия, которые носитель
обязан держать правильно:
  * `import calibrate` сворачивается в tools/calibrate.py - голое имя вместо пакета;
  * пакет разворачивается в свой __init__.py, а `from pkg import mod` даёт и pkg/__init__.py,
    и pkg/mod.py (первый исполняется при импорте пакета, второй может быть единственным, кто
    реально нужен);
  * относительные импорты (`from . import x`, `from ..y import z`) разворачиваются в
    абсолютизированные имена от каталога файла;
  * импорт внутри `try`, обработчик которого гасит ModuleNotFoundError, считается мягким и в
    обязанность не входит - он уезжает в поле `optional`. Так `tools/calibrate.py:121` зовёт
    `import setup`: без корневого setup.py (739 966 Б, и тот тянет три модуля) морда работает,
    и требовать его в архиве было бы ложной находкой.

Внешние пакеты (jinja2, regex, stdlib) молча пропускаются: их полнота - предмет гейта колёс
($VENDOR_PKGS), а не этого разбора. Отличает их от потерянного локального модуля ряд LOCAL_ROOTS:
имя модуля, чья первая часть в него входит, ОБЯЗАНО быть файлом дерева, иначе это broken и rc=2 -
без этого правила удалённый serve/frontend.py выглядел бы как чужая библиотека и молча выпадал из
обязанности. Ряд применяется не ко всем точечным именам: `absolute_names` кладёт в набор и
`модуль + "." + имя` из `from модуль import имя`, а такое имя в CPython может быть и АТРИБУТОМ
(`from strata_control.engine_component import Engine`), файла под ним нет и требовать его - ложная
находка. Поэтому обязанность проверяется по трём классам, которые различает `strict_names`:
  * `import a.b` - без `a/b.py` или `a/b/__init__.py` сам импорт падает, имя обязано быть файлом;
  * `from a.b import c` - модуль `a.b` обязан существовать;
  * `from a import c` - `a/c.py` обязан существовать только если `a` разрешается в ПАКЕТ, а `c` не
    объявлено в его `__init__.py` (иначе это атрибут пакета, и файла от него не ждут).
Задержанные (ленивые) импорты внутри функций НЕ отличаются от импортов верхнего уровня - ast.walk
идёт по всему дереву, и именно так `from strata_cli.client import ...` внутри тела функции
(serve/server.py:8049) попадает в замыкание.

Вызов:
    python web_closure.py --repo <корень дерева> [--entry serve/server.py]
                          [--sys-path . --sys-path tools] [--local serve ...] [--json]
    python web_closure.py --selftest

Флаги --sys-path и --local повторяемые (action="append"), а не список через пробел: одна запись на
один флаг.

Коды выхода: 0 - замыкание посчитано; 2 - проверка не состоялась (нет дерева, нет точки входа,
файл не разобран). «Ноль файлов» отдельно от «находок нет» - пустое замыкание это тоже rc=2.
Печатная строка несёт причину, а вердикт держит код выхода: вызывающий (pack_kit.ps1) подносит
эту строку в свой отказ и дописывает вердикт сам, поэтому суффикс «проверка не состоялась» здесь
лишний - он звучит ровно один раз, на уровне, который выводит отказ в консоль.
"""
from __future__ import annotations

import argparse
import ast
import json
import os
import sys
import tempfile
from pathlib import Path

DEFAULT_ENTRY = "serve/server.py"
# serve/server.py:61-63: в sys.path идут корень дерева и корень/tools. Значение по умолчанию
# живёт здесь ровно один раз; pack_kit.ps1 передаёт тот же список, собранный из $WEB_SPECS.
DEFAULT_SYS_PATH = (".", "tools")
# Обработчики с этими типами гасят сам ImportError, то есть терпят отсутствие модуля.
SOFT_EXC = frozenset({"Exception", "BaseException", "ImportError", "ModuleNotFoundError"})
# Имена, чья первая часть попадает в этот ряд, ОБЯЗАНЫ быть файлами этого дерева. Без ряда
# разрешение имён неотличимо от их отсутствия: `from serve import frontend` и `import numpy`
# дают одинаковый пустой результат, поэтому удалённый из дерева serve/frontend.py молчал бы
# и в замыкании, и в манифесте - ровно тот класс, ради которого гейт существует. Внешние
# пакеты (stdlib, колёса) здесь не перечисляются и не нужны: их первые части в ряд не входят.
DEFAULT_LOCAL_ROOTS = ("serve", "strata_control", "strata_cli", "tools")


def _norm(rel: str) -> str:
    return rel.replace("\\", "/").lstrip("./").strip("/")


def resolve(name: str, repo: Path, sys_paths: list[Path]) -> list[str]:
    """Имя модуля - в список путей от корня дерева.

    Список, а не один путь: `import a.b` в CPython сначала исполняет `a/__init__.py`, и этот
    файл обязан доехать до архива наравне с `a/b.py`. Запись sys.path берётся первая, где
    найшёлся лист, - как в реальном поиске модулей.
    """
    parts = [p for p in name.split(".") if p]
    if not parts:
        return []
    tail = "/".join(parts)
    for base in sys_paths:
        leaf = None
        for rel in (tail + ".py", tail + "/__init__.py"):
            if (base / rel).is_file():
                leaf = rel
                break
        if leaf is None:
            continue
        out = []
        for k in range(1, len(parts)):
            init = "/".join(parts[:k]) + "/__init__.py"
            if (base / init).is_file():
                out.append(_norm(str((base / init).relative_to(repo))))
        out.append(_norm(str((base / leaf).relative_to(repo))))
        return out
    return []


def absolute_names(tree: ast.AST) -> set[str]:
    out: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for a in node.names:
                out.add(a.name)
        elif isinstance(node, ast.ImportFrom):
            if node.level:
                continue
            if node.module:
                out.add(node.module)
                for a in node.names:
                    if a.name != "*":
                        out.add(node.module + "." + a.name)
    return out


def relative_names(tree: ast.AST, rel: str) -> set[str]:
    """Относительные импорты файла rel - в абсолютизированные имена пакетов/модулей."""
    out: set[str] = set()
    pkg = _norm(rel).split("/")[:-1]
    for node in ast.walk(tree):
        if not isinstance(node, ast.ImportFrom) or not node.level:
            continue
        keep = len(pkg) - (node.level - 1)
        if keep < 0:
            continue
        stem = ".".join(pkg[:keep])
        if node.module:
            stem = (stem + "." + node.module) if stem else node.module
        if not node.names or node.names[0].name == "*":
            if stem:
                out.add(stem)
        for a in node.names:
            if a.name == "*":
                continue
            out.add((stem + "." + a.name) if stem else a.name)
    return out


def rel_base(node: ast.ImportFrom, rel: str) -> str | None:
    """Абсолютизированное имя модуля/пакета для относительного `from ... import`: '' или None.

    None - уровень выше корня пакета (`from ..` из файла верхнего уровня): имя не разбираем,
    его первая часть всё равно не попала бы в локальный ряд.
    """
    pkg = _norm(rel).split("/")[:-1]
    keep = len(pkg) - (node.level - 1)
    if keep < 0:
        return None
    stem = ".".join(pkg[:keep])
    if node.module:
        stem = (stem + "." + node.module) if stem else node.module
    return stem


def top_level_defs(tree: ast.AST) -> set[str]:
    """Имена, объявленные файлом на верхнем уровне (и в ветвлениях верхнего уровня).

    Нужны ровно для одного решения: `from pkg import ИМЯ` в CPython импортирует и атрибут,
    объявленный в `pkg/__init__.py`. Функции и классы, объявленные ВНУТРИ функции, сюда не
    попадают: такой имени на верхнем уровне пакета нет, и `from pkg import такое_имя` упало бы
    ImportError - то есть файл под него требовать можно и нужно.
    """
    out: set[str] = set()

    def add_target(t: ast.AST) -> None:
        if isinstance(t, ast.Name):
            out.add(t.id)
        elif isinstance(t, (ast.Tuple, ast.List)):
            for e in t.elts:
                add_target(e)

    def visit(node: ast.AST) -> None:
        # В FunctionDef/ClassDef не заходим: их тела создают локальные имена, которых на уровне
        # пакета нет, а значит `from pkg import такое_имя` упало бы ImportError и файл требовать можно.
        for child in ast.iter_child_nodes(node):
            if isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                out.add(child.name)
            elif isinstance(child, ast.Assign):
                for t in child.targets:
                    add_target(t)
            elif isinstance(child, ast.AnnAssign):
                add_target(child.target)
            elif isinstance(child, (ast.Import, ast.ImportFrom)):
                for al in child.names:
                    if al.name == "*":
                        continue
                    out.add(al.asname or al.name)
                    if isinstance(child, ast.Import) and al.asname is None:
                        out.add(al.name.split(".")[0])
            elif isinstance(child, (ast.If, ast.Try, ast.With, ast.AsyncWith, ast.For,
                                    ast.AsyncFor, ast.While, ast.Match)):
                visit(child)

    visit(tree)
    return out


_COMPOUND = tuple(t for t in (getattr(ast, n, None) for n in
                  ("If", "Try", "With", "AsyncWith", "For", "AsyncFor", "While", "Match")) if t)


def strict_names(node: ast.AST, rel: str) -> tuple[set[str], set[str]]:
    """Для операторов импорта: (имена, обязанные быть файлами; пары `база.алиас`, где алиас - атрибут).

    Разделение диктует сама семантика CPython: `import a.b` не выполнится без модуля a.b, тогда
    как `from a import b` требует лишь модуля a, а b может быть объявленным в нём атрибутом.
    Поэтому `from strata_control.engine_component import Engine` не имеет права требовать файл
    engine_component/Engine.py - на живом дереве такое требование дало бы 278 ложных отказов.
    """
    must: set[str] = set()
    dotted: set[str] = set()
    for n in ast.walk(node):
        if isinstance(n, ast.Import):
            for a in n.names:
                must.add(a.name)
        elif isinstance(n, ast.ImportFrom):
            if n.level:
                base = rel_base(n, rel)
                if base is None:
                    continue
            else:
                base = n.module or ""
            if base:
                must.add(base)
            for a in n.names:
                if a.name == "*":
                    continue
                if base:
                    dotted.add(base + "." + a.name)
                else:
                    must.add(a.name)
    return must, dotted


def _top_defs(rel: str, repo: Path) -> set[str]:
    """Верхние имена файла-пакета; пустое множество, если файл не читается или не разбился."""
    try:
        return top_level_defs(ast.parse((repo / rel).read_text(encoding="utf-8")))
    except (SyntaxError, UnicodeDecodeError, OSError):
        return set()


def must_be_file(name: str, kind: str, repo: Path, sys_paths: list[Path],
                 attrs: dict[str, set[str]]) -> bool:
    """Требовать ли от нерезолвленного имени локального ряда наличия файла на дереве.

    kind == "dotted" - имя пришло из `from база import алиас`. Файл от него ждут только когда база
    разрешается в ПАКЕТ (её `__init__.py` исполняется при импорте) и алиас в том файле не объявлен.
    """
    if kind == "module":
        return True
    if kind != "dotted":
        return False
    parent, _, alias = name.rpartition(".")
    pfound = resolve(parent, repo, sys_paths)
    if not pfound:
        # Родитель не найден сам - отказ по нему уже выдан, дублировать его именем атрибута нельзя.
        return False
    # Пакет - это лист вида «каталог_родителя/__init__.py»; resolve добавляет к нему и __init__.py
    # предков, поэтому по наличию любой строки, оканчивающейся на __init__.py, пакет отличить
    # нельзя (без этого различения `from strata_cli.client import normalize` требовало бы файл
    # strata_cli/client/normalize.py).
    if parent.replace(".", "/") + "/__init__.py" not in pfound:
        # База - модуль-файл: алиас обязан быть его атрибутом, файла `база/алиас.py` не существует.
        return False
    init_rel = parent.replace(".", "/") + "/__init__.py"
    if init_rel not in attrs:
        attrs[init_rel] = _top_defs(init_rel, repo)
    return alias not in attrs[init_rel]


def _handler_types(handler: ast.ExceptHandler) -> list[str]:
    if handler.type is None:
        return ["Exception"]
    node = handler.type
    items = node.elts if isinstance(node, ast.Tuple) else [node]
    out = []
    for it in items:
        if isinstance(it, ast.Name):
            out.append(it.id)
        elif isinstance(it, ast.Attribute):
            base = it
            while isinstance(base, ast.Attribute):
                base = base.value
            if isinstance(base, ast.Name):
                out.append(it.attr)
    return out


def import_names(tree: ast.AST, rel: str) -> tuple[dict[str, bool], dict[str, str]]:
    """Имена, импортируемые файлом: (имя -> мягкое оно или жёсткое, имя -> класс «обязан быть файлом»).

    Мягким считается импорт внутри `try`, обработчик которого гасит сам факт отсутствия модуля
    (ModuleNotFoundError наследуется от ImportError, та - от Exception). Так
    `tools/calibrate.py:118-130` вызывает `import setup` в `except Exception: return []`: без
    корневого setup.py морда работает, и требовать его (739 966 Б, плюс три модуля за ним) было
    бы ложной находкой. Узкий `except ValueError` импорта не гасит - тот же файл обязателен.

    Жёсткость сильнее мягкости по ИМЕНИ, а не по месту: `serve/server.py:70` импортирует
    `strata_control.engine_component` на верхнем уровне, а `:3908-3912` повторяет тот же импорт
    под широким `except` ради одной справки о классе карты. Вычитать имя из-за второго места
    значило бы выбросить 67 717 Б ядра управления и весь его подграф - мерка бы молча
    недооценила комплект втрое.
    """
    out: dict[str, bool] = {}
    kind: dict[str, str] = {}

    def add(names: set[str], must: set[str], dotted: set[str], soft: bool) -> None:
        for n in names:
            out[n] = soft if n not in out else (out[n] and soft)
        # Класс тоже сливается по имени: имя, хоть раз встретившееся в `import a.b`, обязано быть
        # файлом даже если в другом месте его зовут как атрибут, - иначе одно мягкое место
        # снимало бы обязанность со всего имени.
        for n in must:
            kind[n] = "module"
        for n in dotted:
            kind.setdefault(n, "dotted")

    def wide(node: ast.Try) -> bool:
        return any(t in SOFT_EXC for h in node.handlers for t in _handler_types(h))

    def walk(node: ast.AST, soft: bool) -> None:
        # Проверка на самом узле, а не на детях: импорт, пришедшийся прямо в тело try, - тоже узел,
        # и раньше он терялся совсем (мерка молча недосчиталась 16 файлов живого дерева).
        if isinstance(node, ast.Try):
            # Только тело try: импорт в самом обработчике (fallback-модуль) выполняется всегда,
            # когда до него дошло, и объявлять его необязательным было бы ложно.
            for stmt in node.body:
                walk(stmt, soft or wide(node))
            for other in list(node.handlers) + list(node.orelse) + list(node.finalbody):
                walk(other, soft)
            return
        if isinstance(node, (ast.Import, ast.ImportFrom)):
            must, dotted = strict_names(node, rel)
            names = absolute_names(node) | relative_names(node, rel) | must
            add(names, must, dotted, soft)
            return
        for child in ast.iter_child_nodes(node):
            walk(child, soft)

    walk(tree, False)
    return out, kind


def closure(repo: Path, entry: str, sys_paths: list[Path],
            local_roots: tuple[str, ...] = DEFAULT_LOCAL_ROOTS
            ) -> tuple[dict, list[str], list[str]]:
    """(файлы замыкания -> кто потребовал переход, список «не разобрано», мягкие файлы вне обязанности).

    Источник перехода нужен отказу: «нет kit\\tools\\calibrate.py» без него неотличимо от «файл
    просто забыли», а с ним видно, какой модуль его зовёт и по какой строке искать.
    """
    needed: dict[str, str] = {}
    optional: set[str] = set()
    broken: list[str] = []
    attrs: dict[str, set[str]] = {}
    todo = [(_norm(entry), "")]
    while todo:
        rel, src = todo.pop()
        if rel in needed:
            continue
        path = repo / rel
        if not path.is_file():
            # Одинокий путь сюда не приходит: в очередь кладётся только то, что resolve() уже
            # нашёл на диске. Если файла нет - значит развалился сам носитель, и это отказ.
            broken.append(rel + ": нет файла на дереве")
            continue
        try:
            tree = ast.parse(path.read_text(encoding="utf-8"))
        except (SyntaxError, UnicodeDecodeError, OSError) as exc:
            broken.append(rel + ": " + type(exc).__name__)
            continue
        needed[rel] = src
        names, kinds = import_names(tree, rel)
        for name in sorted(n for n, soft in names.items() if not soft):
            found = resolve(name, repo, sys_paths)
            # Жёсткое имя локального ряда, под которое на дереве нет ФАЙЛА, - отказ, а не
            # «внешний пакет». Иначе удалённый serve/frontend.py выпадал из замыкания молча,
            # манифест терял его следом, и приёмка оставалась зелёной без морды. Класс имени
            # (модуль или `база.алиас`) решает, требуется ли файл: у `from mod import Класс` файла
            # нет и быть не может. Голое имя из ROOT/tools (import calibrate) под правило не
            # подпадает - его первая часть не локальный ряд; такое ловит гейт присутствия.
            if (not found and name.split(".")[0] in local_roots
                    and must_be_file(name, kinds.get(name, "module"), repo, sys_paths, attrs)):
                broken.append("%s: локального модуля %s.py на дереве нет (зовёт %s)"
                              % (name, name.replace(".", "/"), rel))
            for r in found:
                if r not in needed:
                    todo.append((r, rel))
        for name in sorted(n for n, soft in names.items() if soft):
            for r in resolve(name, repo, sys_paths):
                if r not in needed:
                    optional.add(r)
    return needed, broken, sorted(optional)


def measure(repo: Path, entry: str, sys_paths: list[Path],
            local_roots: tuple[str, ...] = DEFAULT_LOCAL_ROOTS) -> dict:
    needed, broken, optional = closure(repo, entry, sys_paths, local_roots)
    files = sorted(needed)
    rows = [{"path": rel, "bytes": (repo / rel).stat().st_size,
             "via": needed[rel] or _norm(entry)} for rel in files]
    opt_rows = [{"path": rel, "bytes": (repo / rel).stat().st_size} for rel in optional]
    # optional перекрывает hard: тот же модуль могут звать и жёстко, и мягко из разных мест, поэтому
    # справочная цифра считается по «мягких, которых нет среди обязательных» - иначе байты
    # посчитались бы дважды и вес в отчёте не сошёлся бы с весом архива.
    soft_only = [r for r in opt_rows if r["path"] not in needed]
    return {"entry": _norm(entry), "files": rows,
            "count": len(rows), "bytes": sum(r["bytes"] for r in rows),
            "optional": opt_rows, "soft_only": len(soft_only),
            "soft_only_bytes": sum(r["bytes"] for r in soft_only),
            "optional_bytes": sum(r["bytes"] for r in opt_rows),
            "broken": broken}


def build_fake_tree(root: Path) -> None:
    """Дерево для --selftest: четыре случая разрешения имён в одном минимальном наборе."""
    for d in ("serve", "serve/web", "strata_control", "strata_control/deep", "strata_cli", "tools"):
        (root / d).mkdir(parents=True, exist_ok=True)

    def w(rel: str, text: str) -> None:
        p = root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, encoding="utf-8")

    # сервер: пакетный импорт, ленивый импорт внутри функции, голое имя из tools и внешние пакеты
    w("serve/__init__.py", "")
    w("serve/server.py",
      "import json\n"
      "import regex\n"
      "from serve import frontend\n"
      "from strata_control.engine_component import Engine\n"
      "import strata_tokenizer\n"
      "from strata_cli import run\n"
      "\n"
      "def handler():\n"
      "    from strata_cli.client import normalize\n"
      "    return normalize\n")
    w("serve/frontend.py",
      "import jinja2\nfrom strata_control.deep import tls\n"
      "def narrow():\n"
      "    try:\n"
      "        import narrow_probe\n"
      "    except ValueError:\n"
      "        pass\n"
      "    return narrow_probe\n")
    w("serve/web/index.html", "<html></html>\n")
    w("strata_control/__init__.py", "")
    w("strata_control/engine_component.py", "from . import app_policy\n")
    w("strata_control/app_policy.py",
      "import calibrate\n"
      "def extras():\n"
      "    try:\n"
      "        import soft_probe\n"
      "        return soft_probe.values\n"
      "    except Exception:\n"
      "        return []\n"
      "def again():\n"
      "    try:\n"
      "        import calibrate\n"
      "    except Exception:\n"
      "        return None\n"
      "    return calibrate\n")
    w("strata_control/deep/__init__.py", "from .. import folders\n")
    w("strata_control/deep/tls.py", "")
    w("strata_control/folders.py", "")
    w("strata_cli/__init__.py", "run = lambda: None\n")
    w("strata_cli/client.py", "from . import cli\n")
    w("strata_cli/cli.py", "import ssl\n")
    w("tools/strata_tokenizer.py", "")
    w("tools/calibrate.py", "")
    w("tools/soft_probe.py", "")
    w("tools/narrow_probe.py", "")
    # не должен попасть в замыкание: файл есть, но его никто не импортирует
    w("tools/not_imported.py", "")


def selftest() -> int:
    checks: list[tuple[str, bool, str]] = []

    def chk(name: str, got: object, want: object) -> None:
        checks.append((name, got == want, "получено %r, ожидалось %r" % (got, want)))

    with tempfile.TemporaryDirectory() as td:
        root = Path(td) / "tree"
        build_fake_tree(root)
        paths = [root, root / "tools"]
        m = measure(root, DEFAULT_ENTRY, paths)
        names = {r["path"] for r in m["files"]}
        chk("разбор состоялся: broken пусто", m["broken"], [])
        # обход транзитивный: сервер -> frontend -> strata_control.deep.tls цепочкой, а не одним шагом
        chk("цепочка дошла до strata_control/deep/tls.py",
            "strata_control/deep/tls.py" in names, True)
        chk("ленивый импорт внутри функции учтён", "strata_cli/client.py" in names, True)
        chk("голое имя из записи sys.path учтено", "tools/calibrate.py" in names, True)
        chk("__init__.py пакета учтён", "strata_control/__init__.py" in names, True)
        chk("пакет точки входа учтён через __init__.py", "serve/__init__.py" in names, True)
        chk("каждый предок трёхуровневого имени учтён",
            {"strata_control/__init__.py", "strata_control/deep/__init__.py"} <= names, True)
        chk("относительный импорт `from .` развёрнут", "strata_control/app_policy.py" in names, True)
        chk("`from ..` развёрнут в родителя", "strata_control/folders.py" in names, True)
        chk("внешние пакеты не стали файлами",
            any(n.startswith("regex") or n.startswith("jinja2") for n in names), False)
        chk("не импортируемый файл не притянулся",
            "tools/not_imported.py" in names, False)
        chk("мягкий импорт не делает файл обязательным",
            "tools/soft_probe.py" in names, False)
        chk("мягкий импорт назван отдельным полем",
            "tools/soft_probe.py" in {r["path"] for r in m["optional"]}, True)
        # Жёсткий импорт того же имени в том же файле сильнее мягкого: иначе одна конструкция try
        # вокруг повтора снимает с обязанности весь подграф модуля
        # (на живом дереве это дало 46 файлов вместо 153).
        chk("мягкий повтор жёсткого импорта обязанность не снимает",
            "tools/calibrate.py" in names, True)
        # Узкий except не гасит ModuleNotFoundError, поэтому импорт обязан остаться обязательным:
        # иначе любое имя в любом try превратилось бы в необязательное.
        chk("except ValueError не объявляет импорт мягким",
            "tools/narrow_probe.py" in names, True)
        chk("вес посчитан по файлам", m["bytes"], sum((root / n).stat().st_size for n in names))
        # Класс имени решает, ждать ли файл: `from strata_cli import run` импортирует атрибут,
        # объявленный в __init__.py, и требовать strata_cli/run.py было бы ложной находкой.
        # Тот же контроль подтверждает, что пакет-родитель всё равно обязан доехать до архива.
        chk("алиас из __init__.py пакета файла не требует, а пакет требуется",
            (m["broken"], "strata_cli/__init__.py" in names,
             "strata_cli/run.py" in names), ([], True, False))
        # Источник перехода - часть контракта: отказ «нет kit\tools\calibrate.py» без него
        # неотличим от «файл просто забыли», и чинящий идёт искать по всему дереву.
        via = {r["path"]: r["via"] for r in m["files"]}
        chk("у голого имени из tools назван источник перехода",
            via.get("tools/calibrate.py"), "strata_control/app_policy.py")
        chk("точка входа помечена источником самой себя", via.get("serve/server.py"), "serve/server.py")
        # Справка о мягких обязана быть без двойного счёта: тот же модуль могут звать и жёстко,
        # и мягко, и его байты не должны входить в «вне обязанности» дважды.
        chk("мягкий, уже обязательный по другому пути, вне обязанности не считается",
            "tools/calibrate.py" in [r["path"] for r in m["optional"]
                                     if r["path"] not in names], False)
        chk("единственный мягко-достижимый модуль синтетики назван справкой",
            [r["path"] for r in m["optional"] if r["path"] not in names],
            ["tools/soft_probe.py"])
        # саботаж 1: битый синтаксис в замыкаемом файле -> broken ненулевой, прогон отказывает
        (root / "strata_control" / "app_policy.py").write_text("def (:\n", encoding="utf-8")
        m2 = measure(root, DEFAULT_ENTRY, paths)
        chk("битый файл назван, а не промолчан", len(m2["broken"]) > 0, True)
        chk("битый файл обнуляет доверие к списку", "tools/calibrate.py" in
            {r["path"] for r in m2["files"]}, False)
        # саботаж 2: нет точки входа -> замыкание пустое, и это отказ, а не «всё чисто»
        m3 = measure(root, "serve/nope.py", paths)
        chk("несуществующая точка входа даёт broken", len(m3["broken"]) > 0, True)
        chk("пустое замыкание не выглядит успехом", m3["count"], 0)
        # саботаж 3: tools убран из sys.path -> голое имя calibrate больше не находится,
        # и гейт обязан его НЕ придумать (иначе он меряет свою догадку, а не дерево)
        m4 = measure(root, DEFAULT_ENTRY, [root])
        chk("без записи tools/calibrate.py в замыкании нет",
            "tools/calibrate.py" in {r["path"] for r in m4["files"]}, False)
        # саботаж 4: снять try у мягкого импорта - файл обязан стать обязательным. Без этого
        # контроля «мягкость» могла бы означать «импорт не разбирается вовсе».
        (root / "strata_control" / "app_policy.py").write_text(
            "import calibrate\nimport soft_probe\n", encoding="utf-8")
        m5 = measure(root, DEFAULT_ENTRY, paths)
        chk("без try-обработчика тот же импорт обязателен",
            "tools/soft_probe.py" in {r["path"] for r in m5["files"]}, True)
        # саботаж 5: файл убран с ДЕРЕВА (не из списка). Без правила о локальных рядах это
        # неотличимо от внешнего пакета: resolve() даёт пустой список, имя исчезает из замыкания,
        # манифест теряет его следом - и приёмка зелёная без веб-морды. Контроль требует отказа,
        # в котором названы и пропавший модуль, и тот, кто его зовёт.
        (root / "serve" / "frontend.py").unlink()
        m6 = measure(root, DEFAULT_ENTRY, paths)
        chk("удалённый локальный модуль даёт отказ, а не укороченное замыкание",
            len(m6["broken"]) > 0, True)
        chk("отказ называет пропавший модуль",
            any("serve/frontend.py" in b for b in m6["broken"]), True)
        chk("отказ называет, кто его звал",
            any("serve/server.py" in b for b in m6["broken"]), True)
        (root / "serve" / "frontend.py").write_text(
            "import jinja2\nfrom strata_control.deep import tls\n", encoding="utf-8")
        m7 = measure(root, DEFAULT_ENTRY, paths)
        chk("саботаж снят - broken снова пуст", m7["broken"], [])
        # саботаж 6: имя, под которое в ПАКЕТЕ нет файла и которое не объявлено в его __init__.py.
        # Это тот же класс, что и удалённый файл, но записанный через from-импорт: без разбора
        # класса имени он неотличим от атрибута, а с разбором - обязан дать отказ.
        (root / "serve" / "frontend.py").write_text(
            "from strata_control.deep import tls, ghost\n", encoding="utf-8")
        m8 = measure(root, DEFAULT_ENTRY, paths)
        chk("отсутствующий подмодуль пакета назван отказом",
            any("strata_control.deep.ghost" in b for b in m8["broken"]), True)
        chk("отказ по подмодулю называет зовущего",
            any(b.endswith("(зовёт serve/frontend.py)") for b in m8["broken"]), True)
        # Контроль флага: ряд ограничен одним `serve` - имена вне ряда (даже локального
        # strata_control) остаются молча пропущенными, иначе мерка начала бы требовать stdlib и колёса.
        m9 = measure(root, DEFAULT_ENTRY, paths, ("serve",))
        chk("ряд только из serve: чужое имя вне ряда не отказ",
            any("strata_cli" in b or "strata_control" in b for b in m9["broken"]), False)

    bad = 0
    for name, ok, detail in checks:
        if ok:
            print("  ok   " + name)
        else:
            bad += 1
            print("  FAIL " + name + ": " + detail)
    print("web_closure --selftest: ok=%d bad=%d" % (len(checks) - bad, bad))
    return 1 if bad else 0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--repo", default="", help="корень дерева репозитория")
    ap.add_argument("--entry", default=DEFAULT_ENTRY, help="точка входа замыкания")
    ap.add_argument("--sys-path", action="append", default=None, dest="sys_path",
                    help="запись sys.path относительно --repo (повторяемо; по умолчанию " +
                         ",".join(DEFAULT_SYS_PATH) + ")")
    ap.add_argument("--local", action="append", default=None, dest="local",
                    help="имя локального ряда (первая часть модуля, обязана быть файлом дерева; "
                         "повторяемо; по умолчанию " + ",".join(DEFAULT_LOCAL_ROOTS) + ")")
    ap.add_argument("--json", action="store_true", help="печатать JSON вместо текста")
    ap.add_argument("--selftest", action="store_true", help="контроли на синтетическом дереве")
    a = ap.parse_args(argv)
    if a.selftest:
        return selftest()
    if not a.repo:
        sys.stdout.write("ОТКАЗ: не задан --repo\n")
        return 2
    repo = Path(a.repo).resolve()
    if not repo.is_dir():
        sys.stdout.write("ОТКАЗ: нет дерева %s\n" % repo)
        return 2
    entries = DEFAULT_SYS_PATH if not a.sys_path else tuple(a.sys_path)
    roots = DEFAULT_LOCAL_ROOTS if not a.local else tuple(a.local)
    paths = [(repo / e).resolve() for e in entries]
    m = measure(repo, a.entry, paths, roots)
    # Здесь печатается ПРИЧИНА, а не вердикт: «проверка не состоялась» ставит ровно один уровень
    # цепочки - тот, кто выводит отказ в консоль. У носителя stdout пересказывается вызывающим
    # (pack_kit.ps1 подносит его в throw, а Write-Host дописывает вердикт), и прежний суффикс на
    # каждом уровне давал строку, где «- проверка не состоялась» повторялась трижды, - по ней
    # нельзя было понять, сколько проверок на самом деле не состоялось (замер 14.11). Код выхода
    # 2 остаётся носителем вердикта: он и есть «не состоялась».
    if m["broken"]:
        sys.stdout.write("ОТКАЗ: %d файл(ов) не разобраны: %s\n"
                         % (len(m["broken"]), "; ".join(m["broken"])))
        return 2
    if m["count"] == 0:
        sys.stdout.write("ОТКАЗ: замыкание от %s пусто\n" % m["entry"])
        return 2
    if a.json:
        sys.stdout.write(json.dumps(m, ensure_ascii=False) + "\n")
    else:
        for r in m["files"]:
            sys.stdout.write("%s\t%d\n" % (r["path"], r["bytes"]))
        sys.stdout.write("итого: %d файлов, %d Б\n" % (m["count"], m["bytes"]))
        for r in m["optional"]:
            flag = "" if r["path"] in {x["path"] for x in m["files"]} else " (вне обязанности)"
            sys.stdout.write("мягкий\t%s\t%d%s\n" % (r["path"], r["bytes"], flag))
        sys.stdout.write("мягких, которых нет среди обязательных: %d файлов, %d Б\n"
                         % (m["soft_only"], m["soft_only_bytes"]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
