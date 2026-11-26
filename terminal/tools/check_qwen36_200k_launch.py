from pathlib import Path
import argparse
import json
import re
import sys


PROFILES = {
    "kat": "D:\\Strata\\models\\katcoder\\KAT-Coder-V2.5-Dev-35B-A3B-MTP-ABLITERATED.i1-IQ4_XS.gguf",
    "huihui": "D:\\Strata\\models\\Huihui\\Huihui-Qwen3.6-35B-A3B-Claude-4.7-Opus-abliterated.i1-IQ4_XS.gguf",
}
REQUIRED = {
    "--max-context": "204800",
    "--chunk": "128",
    "--batch": "1",
    "--prefill": "2048",
    "--mtp": "0",
    "--draft-vocab": "8192",
    "--kv-type": "q4_0",
    "--vram-reserve-mib": "512",
    "--att-mb": "256",
    "--super-chunk": "8",
}
QUOTED = re.compile(r'"([^"]*)"')


def option(args, name):
    value = None
    for i, item in enumerate(args):
        if item == name:
            value = args[i + 1] if i + 1 < len(args) else None
    return value


def bat_tokens(text):
    tokens = []
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.lower().startswith(("rem ", "::", "@echo", "title ", "cd ", "if ")):
            continue
        tokens.extend(QUOTED.findall(stripped))
    return tokens


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[2]))
    a = ap.parse_args()
    root = Path(a.root).resolve()
    terminal = root / "terminal"
    errors = []
    notes = []

    def require(cond, message):
        if not cond:
            errors.append(message)

    for name, model in PROFILES.items():
        bat = terminal / f"run-qwen36-iq4_xs-{name}.bat"
        cfg = terminal / f"strata-qwen36-iq4_xs-{name}.json"
        require(bat.is_file(), f"нет BAT: {bat}")
        require(cfg.is_file(), f"нет JSON: {cfg}")
        if not bat.is_file() or not cfg.is_file():
            continue
        try:
            text = bat.read_text(encoding="utf-8-sig")
        except (OSError, UnicodeError) as e:
            errors.append(f"{bat.name}: BAT не читается: {e}")
            continue
        tokens = bat_tokens(text)
        normalized = text.replace("/", "\\")
        python_paths = [Path(value) for value in tokens if Path(value).name.lower() == "python.exe"]
        server_paths = [Path(value) for value in tokens if Path(value).name.lower() == "server.py"]
        require(len(python_paths) == 1, f"{bat.name}: ожидался один python.exe из BAT")
        require(len(server_paths) == 1, f"{bat.name}: ожидался один server.py из BAT")
        for path in python_paths:
            require(path.is_file(), f"{bat.name}: python из BAT отсутствует: {path}")
            require(str(path).replace("/", "\\").endswith("\\terminal\\.venv\\Scripts\\python.exe"),
                    f"{bat.name}: python из BAT не terminal/.venv: {path}")
        for path in server_paths:
            require(path.is_file(), f"{bat.name}: server из BAT отсутствует: {path}")
            require(str(path).replace("/", "\\").endswith("\\terminal\\serve\\server.py"),
                    f"{bat.name}: server из BAT не terminal/serve/server.py: {path}")
        require(option(tokens, "--engine") == "strata", f"{bat.name}: не штатный engine strata")
        config = option(tokens, "--config")
        require(config is not None and Path(config).name == cfg.name, f"{bat.name}: не ссылается на {cfg.name}")
        require(config is not None and Path(config).is_file(), f"{bat.name}: config из BAT отсутствует: {config}")
        require("engine\\.venv\\Scripts\\python.exe" not in normalized, f"{bat.name}: stale engine/.venv")
        require("strata-q36.exe" not in tokens and "--serve" not in tokens, f"{bat.name}: прямой engine запуск")

        try:
            data = json.loads(cfg.read_text(encoding="utf-8-sig"))
        except (OSError, UnicodeError, json.JSONDecodeError) as e:
            errors.append(f"{cfg.name}: JSON не читается: {e}")
            continue
        if not isinstance(data, dict):
            errors.append(f"{cfg.name}: JSON не объект")
            continue
        args = data.get("args")
        written = data.get("args_written")
        require("args_written" in data, f"{cfg.name}: отсутствует args_written")
        require(isinstance(args, list), f"{cfg.name}: args не список")
        require(isinstance(written, list), f"{cfg.name}: args_written не список")
        if not isinstance(args, list) or not isinstance(written, list):
            continue
        for flag, value in REQUIRED.items():
            require(option(args, flag) == value, f"{cfg.name}: args {flag} != {value}")
        require(written == args, f"{cfg.name}: args_written не совпадает с args")
        require(option(args, "--native") == model, f"{cfg.name}: неверная модель")
        require("--no-graph" not in args, f"{cfg.name}: graph выключен")

        exe = Path(data.get("exe", ""))
        cwd = Path(data.get("cwd", ""))
        tokenizer = Path(data.get("tokenizer", ""))
        lib_dirs = data.get("lib_dirs", [])
        require(exe.is_file(), f"{cfg.name}: exe отсутствует: {exe}")
        require(cwd.is_dir(), f"{cfg.name}: cwd отсутствует: {cwd}")
        require(tokenizer.is_dir(), f"{cfg.name}: tokenizer отсутствует: {tokenizer}")
        require(Path(model).is_file(), f"{cfg.name}: модель отсутствует: {model}")
        require(isinstance(lib_dirs, list), f"{cfg.name}: lib_dirs не список")
        for lib in lib_dirs if isinstance(lib_dirs, list) else []:
            require(Path(lib).is_dir(), f"{cfg.name}: lib_dirs отсутствует: {lib}")
        log = Path(data.get("log", ""))
        require(log.parent.is_dir(), f"{cfg.name}: каталог log отсутствует: {log.parent}")
        if exe.name.lower() == "strata.exe":
            notes.append(f"{cfg.name}: generic strata.exe оставлен намеренно")
        else:
            errors.append(f"{cfg.name}: ожидался generic strata.exe")

    for note in notes:
        print("[NOTE] " + note)
    for error in errors:
        print("[FAIL] " + error)
    print("[PASS] статическая проверка qwen36 200k launch" if not errors else "[FAIL] статическая проверка qwen36 200k launch")
    return 0 if not errors else 1


if __name__ == "__main__":
    sys.exit(main())
