#!/usr/bin/env python3
"""Реестр нативных зависимостей бинарников комплекта: какие DLL реально нужны.

Мера нужна потому, что `bin\\` портативного комплекта обязан содержать не «то, что кажется
нужным», а фактический импорт PE-заголовка. Список снимается `dumpbin /imports`, поэтому он
переживает смену версии CUDA и добавление движка - если сборка начинает звать новую DLL, мера
это показывает сама.

Вызов (из корня репозитория):
    python packaging/kit/ci/kit_dll_deps.py --bin <exe> [--bin ...] --dumpbin <path>
        --cuda-bin <path> --system-root <path> --extra-dir <path> --out <json>
    python packaging/kit/ci/kit_dll_deps.py --selftest

Коды возврата: 0 - реестр снят по всем входам; 1 - хотя бы один биначник не разобран или
импортирует DLL, которой нет ни в CUDA\\bin, ни в System32; 2 - вход неверен (нет файла,
пустой список, не найден dumpbin) - то есть проверка не состоялась.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

# Категории, по которым принимается решение «класть в комплект или нет». Порядок проверки важен:
# msvc-страница Windows (vcruntime*) ищется первой, потому что cudart тоже кончается на .dll.
CUDA_RE = re.compile(r"^(cudart|cublas|cublasLt|cufft|curand|cusolver|cusparse|nvrtc|nppu|nppc"
                     r"|nppial|nppitc|nvfatbin|cupti|cuda|nvvm|libcuda|nvml)", re.I)
MSVC_RE = re.compile(r"^(vcruntime|ucrtbase|msvcp|concrt|vccorlib|api-ms-|ext-ms-)", re.I)
SYSTEM_RE = re.compile(r"^(kernel32|user32|gdi32|advapi32|shell32|ole32|oleaut32|ws2_32|winhttp"
                       r"|bcrypt|crypt32|iphlpapi|setupapi|shlwapi|dbghelp|psapi|wldap32|normaliz"
                       r"|secur32|userenv|dwmapi|comdlg32|gdiplus|srvcli|netapi32|ncrypt|wincrypt"
                       r"|imm32|ntdll|msvcrt|api-ms|powrprof|pdh|version|cfgmgr32|devobj|propsys"
                       r"|windowsapp|runtimeobject|synchronization)", re.I)

# Импорты, которые PE-заголовок объявляет, но которые не обязан нести комплект: их даёт ОС или
# драйвер. Без этого списка мера превратилась бы в бесконечный «не найдено» по системным DLL.
DRIVER_RE = re.compile(r"^(nvcuda|cuda\.dll|nvml\.dll|libcuda)", re.I)


def parse_imports(text: str) -> list[str]:
    """Имена DLL из вывода `dumpbin /imports`.

    Формат вывода - блоки: строка с отступом и именем DLL, затем строки с RVA/импортами. Имя DLL
    - это единственная строка блока, начинающаяся с 4+ пробелов и не содержащая «[».
    """
    out: list[str] = []
    seen: set[str] = set()
    for line in text.splitlines():
        if not line.startswith(("    ", "\t")):
            continue
        s = line.strip()
        if not s or s.startswith("["):
            continue
        m = re.match(r"^([A-Za-z0-9_.\-]+\.dll)\b", s, re.I)
        if not m:
            continue
        name = m.group(1).lower()
        if name not in seen:
            seen.add(name)
            out.append(name)
    return out


def classify(name: str) -> str:
    if DRIVER_RE.match(name):
        return "driver"          # даёт видеодрайвер, в комплект не кладётся
    if CUDA_RE.match(name):
        return "cuda"
    if MSVC_RE.match(name):
        return "msvc"
    if SYSTEM_RE.match(name):
        return "system"
    return "other"


def run_dumpbin(dumpbin: Path, target: Path) -> str:
    p = subprocess.run([str(dumpbin), "/imports", str(target)], capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    if p.returncode != 0:
        raise RuntimeError(f"dumpbin rc={p.returncode} для {target.name}: "
                           f"{(p.stderr or p.stdout).strip()[:200]}")
    return p.stdout


def search_dir(name: str, directory: Path) -> dict | None:
    for cand in (directory / name, directory / name.upper()):
        if cand.is_file():
            return {"name": name, "bytes": cand.stat().st_size}
    return None


def resolve(name: str, cuda_bin: Path | None, system_root: Path, extra_dirs: list[Path],
            home: Path | None = None) -> tuple[str, dict] | None:
    """Где лежит DLL и сколько весит; порядок каталогов фиксирует источник."""
    for kind, d in (("adjacent", home), ("cuda", cuda_bin), ("system", system_root / "System32")):
        if not d:
            continue
        found = search_dir(name, d)
        if found:
            return kind, found
    for d in extra_dirs:
        found = search_dir(name, d)
        if found:
            return "extra", found
    return None


def closure(seed: list[tuple[Path, list[str]]], dumpbin: Path, cuda_bin: Path | None,
            system_root: Path, extra_dirs: list[Path], max_rounds: int = 8) -> tuple[dict, list[str]]:
    """Транзитивное замыкание CUDA-зависимостей.

    Плоский список импортов врёт: cublas64_13.dll сама импортирует cublasLt64_13.dll (460 МиБ),
    и комплект, собранный по первому слою, падает на чужой машине с «модуль не найден». Поэтому
    обход идёт, пока фронт пуст; непустой фронт после max_rounds - провал меры, а не «посчитали
    сколько успели».
    """
    seen: dict[str, dict] = {}
    missing: list[str] = []
    front: list[tuple[str, str, Path | None]] = []
    for b, names in seed:
        for n in names:
            if classify(n) in ("cuda", "other"):
                front.append((n.lower(), b.name, b.parent))
    rounds = 0
    while front and rounds < max_rounds:
        rounds += 1
        nxt: list[tuple[str, str, Path | None]] = []
        for name, why, home in front:
            if name in seen:
                continue
            got = resolve(name, cuda_bin, system_root, extra_dirs, home)
            if not got:
                missing.append(f"{why} -> {name}")
                continue
            kind, info = got
            entry = {"name": name, "bytes": info["bytes"], "source": kind}
            seen[name] = entry
            target = None
            if kind == "cuda" and cuda_bin:
                target = cuda_bin / name
            elif kind == "adjacent" and home:
                target = home / name
            if target and target.is_file():
                # Лезем внутрь библиотеки: у неё свои импорты, и они тоже обязаны быть в комплекте.
                inner = [n.lower() for n in parse_imports(run_dumpbin(dumpbin, target))
                         if classify(n) in ("cuda", "other")]
                entry["imports"] = sorted(set(inner))
                for n2 in inner:
                    nxt.append((n2, name, home if kind == "adjacent" else None))
        front = nxt
    if front:
        missing.append(f"фронт не исчерпан за {max_rounds} раундов: "
                       + ", ".join(sorted({n for n, _, _ in front})))
    return seen, missing


def build(bins: list[Path], dumpbin: Path, cuda_bin: Path | None, system_root: Path,
          extra_dirs: list[Path]) -> dict:
    # Порядок поиска - не произвольный: «рядом с бинарником» отвечает на другой вопрос, чем
    # «в CUDA\\bin». Соседняя DLL (ggml-base.dll для ggml-cuda.dll) уже едет в комплекте вместе
    # с движком, а библиотеку тулчейна надо копировать явно - их раздельно и печатаем.
    records = []
    missing = []
    seeds: list[tuple[Path, list[str]]] = []
    for b in bins:
        names = parse_imports(run_dumpbin(dumpbin, b))
        seeds.append((b, names))
        groups: dict[str, list[str]] = {"cuda": [], "msvc": [], "system": [], "driver": [],
                                        "adjacent": [], "other": []}
        for n in names:
            kind = classify(n)
            if kind == "other" and search_dir(n, b.parent):
                kind = "adjacent"
            groups[kind].append(n)
        records.append({
            "binary": b.name,
            "bytes": b.stat().st_size,
            "imports_total": len(names),
            "cuda": sorted(groups["cuda"]),
            "msvc": sorted(groups["msvc"]),
            "system": sorted(groups["system"]),
            "driver": sorted(groups["driver"]),
            "adjacent": sorted(groups["adjacent"]),
            "other": sorted(groups["other"]),
        })
    lib_map, miss2 = closure(seeds, dumpbin, cuda_bin, system_root, extra_dirs)
    missing.extend(miss2)
    cuda_libs = sorted((v for v in lib_map.values() if v["source"] == "cuda"),
                       key=lambda v: v["name"])
    return {"binaries": records, "missing": missing,
            "cuda_runtime_to_copy": cuda_libs,
            "cuda_runtime_to_copy_bytes": sum(v["bytes"] for v in cuda_libs),
            "cuda_bin_scanned": bool(cuda_bin), "note":
            "пути не пишутся: комплект не должен содержать абсолютных путей стенда"}


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

    sample = "\n".join([
        "  File dump of imports",
        "    Kernel32.dll",
        "            1E2F  Import Address Table",
        "        1  Foo=00401000",
        "    cudart64_13.dll",
        "        1  cudaMalloc@600",
        "    nvcuda.dll",
        "    vcruntime140.dll",
        "    ggml-cuda.dll",
        "",
    ])
    names = parse_imports(sample)
    chk("имён найдено", len(names), 5)
    chk("cudart классифицирован как cuda", classify("cudart64_13.dll"), "cuda")
    chk("драйвер не путается с cuda", classify("nvcuda.dll"), "driver")
    chk("msvc-страница", classify("vcruntime140.dll"), "msvc")
    chk("системная", classify("kernel32.dll"), "system")
    chk("чужое имя", classify("ggml-cuda.dll"), "other")
    chk("строка RVA не имя DLL", ("Import Address Table" in [n.lower() for n in names]), False)
    chk("дубликаты схлопнуты", len(set(names)), len(names))
    # Пустой вывод dumpbin обязан давать пустой список, а не «разобрано успешно с числами».
    chk("пустой ввод", len(parse_imports("")), 0)
    # Соседняя DLL движка не должна выглядеть отсутствующей: ggml-cuda.dll зовёт ggml-base.dll,
    # и оба едут в bin\ комплекта. Мерка ищет по каталогу бинарника, поэтому проверка - на живом
    # временном дереве, а не на догадке о формате вывода dumpbin.
    tmp = Path(tempfile.mkdtemp(prefix="kit-deps-"))
    (tmp / "ggml-base.dll").write_bytes(b"\x4d\x5a" + b"0" * 2048)
    chk("соседняя DLL найдена с размером", (search_dir("ggml-base.dll", tmp) or {}).get("bytes"), 2050)
    chk("несуществующая DLL не выдумана", search_dir("ggml-cuda.dll", tmp), None)
    # Порядок поиска важен: если имя лежит и рядом с бинарником, и в CUDA\\bin, комплект обязан
    # взять соседнюю (она той же сборки), а не библиотеку тулчейна.
    (tmp / "cublas64_13.dll").write_bytes(b"\x4d\x5a" + b"0" * 10)
    fake_system = Path(tempfile.mkdtemp(prefix="kit-deps-sys-"))
    hit = resolve("cublas64_13.dll", tmp, fake_system, [], tmp)
    chk("соседний каталог важнее cuda-бина", (hit or ("", ""))[0], "adjacent")
    chk("размер взят от соседа", (hit or ({}, {}))[1].get("bytes"), 12)
    chk("несуществующая в четырёх каталогах не выдумана",
        resolve("nope.dll", tmp, fake_system, [], tmp), None)
    shutil.rmtree(tmp, ignore_errors=True)
    shutil.rmtree(fake_system, ignore_errors=True)
    print(f"selftest: ok={ok} bad={bad}")
    return 0 if bad == 0 else 1


def main() -> int:
    ap = argparse.ArgumentParser(description=(__doc__ or "").splitlines()[0])
    ap.add_argument("--bin", action="append", default=[], dest="bins",
                    help="бинарник комплекта (повторяется)")
    ap.add_argument("--dumpbin", help="полный путь к dumpbin.exe")
    ap.add_argument("--cuda-bin", help="каталог bin CUDA-тулчейна (для поиска cudart/cublas)")
    ap.add_argument("--extra-dir", action="append", default=[], dest="extra",
                    help="дополнительный каталог поиска DLL (повторяется)")
    ap.add_argument("--system-root", default=str(Path(sys.executable).drive + "\\Windows"),
                    help="корень Windows для поиска системных DLL")
    ap.add_argument("--out", help="куда записать JSON-реестр")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()

    if a.selftest:
        return selftest()

    bins = [Path(p) for p in a.bins]
    if not bins:
        print("ОТКАЗ: ни одного --bin: проверка не состоялась", file=sys.stderr)
        return 2
    for b in bins:
        if not b.is_file():
            print(f"ОТКАЗ: бинарник не найден: {b}", file=sys.stderr)
            return 2
    dumpbin = Path(a.dumpbin) if a.dumpbin else None
    if not dumpbin or not dumpbin.is_file():
        print("ОТКАЗ: --dumpbin обязателен и должен существовать: без него реестр был бы догадкой",
              file=sys.stderr)
        return 2
    cuda_bin = Path(a.cuda_bin) if a.cuda_bin else None
    if cuda_bin and not cuda_bin.is_dir():
        print(f"ОТКАЗ: каталог CUDA не найден: {cuda_bin}", file=sys.stderr)
        return 2
    system_root = Path(a.system_root)
    if not system_root.is_dir():
        print(f"ОТКАЗ: корень Windows не найден: {system_root}", file=sys.stderr)
        return 2
    extra_dirs = []
    for p in a.extra:
        d = Path(p)
        if not d.is_dir():
            print(f"ОТКАЗ: каталог поиска не найден: {d}", file=sys.stderr)
            return 2
        extra_dirs.append(d)

    data = build(bins, dumpbin, cuda_bin, system_root, extra_dirs)
    text = json.dumps(data, ensure_ascii=False, indent=2)
    if a.out:
        Path(a.out).write_text(text + "\n", encoding="utf-8")
        print(f"реестр зависимостей: {a.out}")
    else:
        print(text)
    for b in data["binaries"]:
        print(f"{b['binary']}: импортов {b['imports_total']}, cuda [{', '.join(b['cuda'])}], "
              f"other [{', '.join(b['other'])}]")
    if data["missing"]:
        print("ОТКАЗ: импортируемых DLL нет ни в CUDA\\bin, ни в System32: " + "; ".join(data["missing"]),
              file=sys.stderr)
        return 1
    if any(b["imports_total"] == 0 for b in data["binaries"]):
        print("ОТКАЗ: у бинарника ноль импортов - dumpbin разобрал не то", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
