#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Съём конфигурации машины для портативного комплекта.

Входит то, что реально влияет на подбор окна и параметров: видеопамять и
архитектура GPU, ядра CPU, объём ОЗУ, тип носителя под моделью, HAGS и MSI.
Никаких путей стенда: всё определяется по месту запуска.

Вызов:
    python kit/detect.py                       # JSON в stdout
    python kit/detect.py --out config.json     # и в файл
    python kit/detect.py --model <путь к .gguf>      # добавить тип диска под моделью
    python kit/detect.py --fake-config f.json  # не мерить железо, взять из файла
    python kit/detect.py --selftest            # контроли, включая саботаж

Коды возврата: 0 - съёмка состоялась; 1 - часть зондов не сработала, причины в
"warnings"; 2 - проверка не состоялась (нет ни GPU, ни ОЗУ, битый вход).
"""

from __future__ import annotations

import argparse
import json
import os
import platform
import re
import shutil
import subprocess
import sys
from pathlib import Path

try:
    import winreg
except ImportError:
    winreg = None

# Минимальный набор, без которого вердикт о машине невозможен.
REQUIRED = ("gpu.name", "gpu.vram_mib", "ram.total_gib")


def _run_ps(script: str, timeout: int = 60) -> str | None:
    """Одна команда PowerShell с выводом в UTF-8; None - если прогон не удался."""
    cmd = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command",
           "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8;" + script]
    try:
        p = subprocess.run(cmd, capture_output=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if p.returncode != 0:
        return None
    try:
        return (p.stdout or b"").decode("utf-8", "replace").strip()
    except Exception:
        return None


def probe_gpu(w: list[str]) -> dict:
    """Имя, объём, версия драйвера и compute capability из nvidia-smi."""
    out = None
    try:
        p = subprocess.run(
            ["nvidia-smi", "--query-gpu=name,memory.total,memory.free,driver_version,compute_cap",
             "--format=csv,noheader,nounits"],
            capture_output=True, timeout=30)
        if p.returncode == 0:
            out = p.stdout.decode("utf-8", "replace").strip().splitlines()
    except (OSError, subprocess.TimeoutExpired):
        out = None
    if not out:
        w.append("nvidia-smi недоступен: GPU не измерен")
        return {}
    parts = [x.strip() for x in out[0].split(",")]
    if len(parts) < 4:
        w.append(f"nvidia-smi вернул неполную строку: {out[0]!r}")
        return {}
    gpu = {"name": parts[0], "driver": parts[3]}
    try:
        gpu["vram_mib"] = int(float(parts[1]))
        gpu["free_mib"] = int(float(parts[2]))
    except ValueError:
        w.append(f"nvidia-smi: память не читается в {out[0]!r}")
    if len(parts) >= 5 and parts[4]:
        m = re.match(r"^(\d+)\.(\d+)", parts[4])
        if m:
            gpu["cc"] = f"{m.group(1)}{m.group(2)}"
            gpu["arch"] = f"sm_{gpu['cc']}"
    if "arch" not in gpu:
        w.append("compute_cap не вернулся: архитектура не определена, cubin не подобрать")
    return gpu


def probe_cpu(w: list[str]) -> dict:
    cpu: dict = {"logical": os.cpu_count() or 0}
    out = _run_ps("(Get-CimInstance Win32_Processor | "
                  "Measure-Object -Property NumberOfCores -Sum).Sum")
    if out and out.isdigit():
        cpu["physical"] = int(out)
    else:
        w.append("физические ядра не сняты (Win32_Processor): считаем только логические")
    return cpu


def probe_ram(w: list[str]) -> dict:
    if os.name != "nt":
        w.append("объём ОЗУ меряется только на Windows")
        return {}
    import ctypes

    class MEMORYSTATUSEX(ctypes.Structure):
        _fields_ = [("dwLength", ctypes.c_ulong),
                    ("dwMemoryLoad", ctypes.c_ulong),
                    ("ullTotalPhys", ctypes.c_ulonglong),
                    ("ullAvailPhys", ctypes.c_ulonglong),
                    ("ullTotalPageFile", ctypes.c_ulonglong),
                    ("ullAvailPageFile", ctypes.c_ulonglong),
                    ("ullTotalVirtual", ctypes.c_ulonglong),
                    ("ullAvailVirtual", ctypes.c_ulonglong),
                    ("ullAvailExtendedVirtual", ctypes.c_ulonglong)]

    s = MEMORYSTATUSEX()
    s.dwLength = ctypes.sizeof(MEMORYSTATUSEX)
    if not ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(s)):
        w.append("GlobalMemoryStatusEx отказал: ОЗУ не измерено")
        return {}
    return {"total_gib": round(s.ullTotalPhys / 2**30, 2),
            "avail_gib": round(s.ullAvailPhys / 2**30, 2),
            "load_percent": int(s.dwMemoryLoad)}


def probe_hags(w: list[str]) -> dict:
    """HAGS в Windows 11 лежит в HwSchMode: 1 - выключен, 2 - включён."""
    if winreg is None:
        w.append("winreg недоступен (не Windows): HAGS не определён")
        return {}
    path = r"SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
    try:
        key = winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, path, 0,
                             winreg.KEY_READ | winreg.KEY_WOW64_64KEY)
    except OSError as e:
        w.append(f"{path} не открыт ({e.strerror}): HAGS не определён")
        return {}
    try:
        value, typ = winreg.QueryValueEx(key, "HwSchMode")
    except OSError:
        winreg.CloseKey(key)
        w.append("HwSchMode не найдено: HAGS не определён (возможно, Windows 10)")
        return {}
    winreg.CloseKey(key)
    if typ != winreg.REG_DWORD:
        w.append(f"HwSchMode имеет тип {typ}, ожидался DWORD: HAGS не определён")
        return {}
    return {"hags": int(value) == 2, "hw_sch_mode": int(value)}


def probe_msi(w: list[str], gpu_name: str) -> dict:
    """MSI у того адаптера, который назвал nvidia-smi: MSISupported в его PCI-ветке.

    Перебирать класс видеоадаптеров нельзя: Enum\\PCI хранит и давно снятые карты,
    и у них MSISupported может отличаться от текущей.
    """
    if winreg is None:
        w.append("winreg недоступен (не Windows): MSI не определён")
        return {}
    out = _run_ps("Get-CimInstance Win32_VideoController | ForEach-Object "
                  "{ $_.Name + '|' + $_.PNPDeviceID }")
    if not out:
        w.append("Win32_VideoController не ответил: MSI не определён")
        return {}
    pci = None
    for line in out.splitlines():
        name, sep, dev = line.partition("|")
        if not sep:
            continue
        if name.strip().lower() == gpu_name.strip().lower():
            pci = dev.strip()
            break
        if pci is None and "NVIDIA" in name.upper():
            pci = dev.strip()
    if not pci:
        w.append(f"видеоадаптер {gpu_name!r} не найден в Win32_VideoController: MSI не определён")
        return {}
    if not pci.upper().startswith("PCI\\"):
        w.append(f"адаптер {gpu_name!r} сидит не на PCI ({pci}): MSI не применим")
        return {}
    rel = pci[len("PCI\\"):] + r"\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
    try:
        root = winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, r"SYSTEM\CurrentControlSet\Enum\PCI",
                              0, winreg.KEY_READ | winreg.KEY_WOW64_64KEY)
    except OSError as e:
        w.append(f"Enum\\PCI не открыт ({e.strerror}): MSI не определён")
        return {}
    try:
        m = winreg.OpenKey(root, rel, 0, winreg.KEY_READ)
    except OSError as e:
        winreg.CloseKey(root)
        w.append(f"ветка MessageSignaledInterruptProperties не найдена ({e.strerror}): MSI не определён")
        return {}
    try:
        value, typ = winreg.QueryValueEx(m, "MSISupported")
    except OSError as e:
        w.append(f"MSISupported не найдено ({e.strerror}): MSI не определён")
        value, typ = None, None
    finally:
        winreg.CloseKey(m)
        winreg.CloseKey(root)
    if value is None or typ != winreg.REG_DWORD:
        return {}
    return {"msi": int(value) == 1, "pci_id": pci, "adapter": gpu_name}


def disk_of(path: str) -> dict:
    """Тип носителя под произвольным путём (SSD/HDD) и свободное место."""
    letter = re.match(r"^([A-Za-z]):", path)
    if not letter:
        return {"error": f"в пути {path!r} нет буквы диска"}
    d = letter.group(1).upper()
    free = None
    try:
        free = round(shutil.disk_usage(path if os.path.exists(path) else f"{d}:\\").free / 2**30, 1)
    except OSError:
        pass
    out = _run_ps(
        "$ErrorActionPreference='SilentlyContinue';"
        f"$p=Get-Partition -DriveLetter {d}; if(-not $p){{exit 3}};"
        "$d=Get-Disk -Number $p.DiskNumber;"
        "$pd=Get-PhysicalDisk | Where-Object DeviceId -eq $d.Number;"
        "Write-Output ($d.FriendlyName + '|' + $pd.MediaType + '|' + $d.BusType)")
    res: dict = {"drive": f"{d}:", "free_gib": free}
    if not out or "|" not in out:
        res["media"] = None
        res["note"] = "Get-Partition/Get-PhysicalDisk не ответили: тип носителя неизвестен"
        return res
    friendly, media, bus = (x.strip() for x in out.split("|", 2))
    res.update(model=friendly, media=(media or None), bus=(bus or None))
    return res


def detect(model_path: str | None) -> dict:
    w: list[str] = []
    cfg: dict = {"os": {"system": platform.system(), "release": platform.release(),
                        "machine": platform.machine(), "python": platform.python_version()}}
    cfg["gpu"] = probe_gpu(w)
    cfg["cpu"] = probe_cpu(w)
    cfg["ram"] = probe_ram(w)
    cfg.update(probe_hags(w))
    cfg.update(probe_msi(w, cfg["gpu"].get("name", "")))
    if model_path:
        cfg["model_disk"] = disk_of(model_path)
    cfg["warnings"] = w
    return cfg


def missing_required(cfg: dict) -> list[str]:
    out = []
    for dotted in REQUIRED:
        sec, field = dotted.split(".")
        val = (cfg.get(sec) or {}).get(field)
        if val in (None, "", 0):
            out.append(dotted)
    return out


def load_fake(path: Path) -> dict:
    raw = path.read_bytes()
    if not raw.strip():
        raise ValueError("файл подмены пуст: подмены не было")
    try:
        data = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as e:
        raise ValueError(f"файл подмены не читается как JSON: {e}") from e
    if not isinstance(data, dict):
        raise ValueError("файл подмены должен содержать объект JSON")
    if not data.get("gpu"):
        raise ValueError("в файле подмены нет секции gpu: измерение не состоится")
    return data


SELFTEST_FAKES = [
    ("3060ti-8g", {"gpu": {"name": "RTX 3060 Ti", "vram_mib": 8192, "cc": "86"},
                   "cpu": {"logical": 8, "physical": 4}, "ram": {"total_gib": 31.87}}),
    ("5080-16g", {"gpu": {"name": "RTX 5080", "vram_mib": 16303, "cc": "120"},
                  "cpu": {"logical": 32, "physical": 16}, "ram": {"total_gib": 95.7}}),
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

    print("detect.py selftest")
    for name, fake in SELFTEST_FAKES:
        p = Path(os.environ.get("TEMP", "/tmp")) / f"detect-fake-{name}.json"
        p.write_text(json.dumps(fake), encoding="utf-8")
        check(f"подмена {name} читается", load_fake(p), fake)
        p.unlink()
    # саботаж: пустой, не-JSON, без gpu, несуществующий путь
    tmp = Path(os.environ.get("TEMP", "/tmp"))
    empty = tmp / "detect-fake-empty.json"
    empty.write_bytes(b"")
    try:
        load_fake(empty)
        check("пустой вход -> отказ", "молча принял", "ValueError")
    except ValueError:
        check("пустой вход -> отказ", "ValueError", "ValueError")
    empty.unlink()
    notjson = tmp / "detect-fake-bad.json"
    notjson.write_text("{это не json", encoding="utf-8")
    try:
        load_fake(notjson)
        check("битый JSON -> отказ", "молча принял", "ValueError")
    except ValueError:
        check("битый JSON -> отказ", "ValueError", "ValueError")
    notjson.unlink()
    nogpu = tmp / "detect-fake-nogpu.json"
    nogpu.write_text(json.dumps({"cpu": {"logical": 4}}), encoding="utf-8")
    try:
        load_fake(nogpu)
        check("без секции gpu -> отказ", "молча принял", "ValueError")
    except ValueError:
        check("без секции gpu -> отказ", "ValueError", "ValueError")
    nogpu.unlink()
    try:
        load_fake(tmp / "detect-fake-net-net.json")
        check("несуществующий файл -> отказ", "молча принял", "OSError")
    except OSError:
        check("несуществующий файл -> отказ", "OSError", "OSError")
    check("список обязательных полей непуст", bool(REQUIRED), True)
    check("без gpu вердикт - не хватает полей",
          "gpu.name" in missing_required({"cpu": {}}), True)
    # живой прогон: если чего-то не хватает, отказ обязан быть назван причиной
    live = detect(None)
    lack = missing_required(live)
    check("живой замер: при нехватке названа причина", (not lack) or bool(live.get("warnings")), True)
    check("живой замер: HAGS или MSI сняты либо объяснены",
          ("hags" in live or "msi" in live) or any(
              "HAGS" in x or "MSI" in x for x in live.get("warnings", [])), True)
    if lack:
        print(f"  live не снято: {', '.join(lack)}")
    print(f"  live gpu={live.get('gpu', {}).get('name')!r} "
          f"vram={live.get('gpu', {}).get('vram_mib')} arch={live.get('gpu', {}).get('arch')} "
          f"ram={live.get('ram', {}).get('total_gib')} hags={live.get('hags')} msi={live.get('msi')}")
    print(f"detect: {ok}/{ok + bad} контролей пройдено")
    return 0 if bad == 0 else 1


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out", help="записать JSON в файл")
    ap.add_argument("--model", help="путь к GGUF: добавить тип носителя под моделью")
    ap.add_argument("--fake-config", help="взять конфигурацию из файла, не трогая железо")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()

    if args.selftest:
        return selftest()

    if args.fake_config:
        try:
            cfg = load_fake(Path(args.fake_config))
        except (OSError, ValueError) as e:
            print(f"ОТКАЗ: {e}", file=sys.stderr)
            return 2
    else:
        cfg = detect(args.model)

    lack = missing_required(cfg)
    text = json.dumps(cfg, ensure_ascii=False, indent=2)
    if args.out:
        Path(args.out).write_text(text + "\n", encoding="utf-8")
        print(f"конфигурация: {args.out}")
    else:
        print(text)
    if lack:
        print("ОТКАЗ: не снято обязательное: " + ", ".join(lack), file=sys.stderr)
        return 2
    if cfg.get("warnings"):
        print("ПРЕДУПРЕЖДЕНИЯ: " + "; ".join(cfg["warnings"]), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
