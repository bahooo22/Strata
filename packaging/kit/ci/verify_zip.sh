#!/bin/bash
# Формат-гейт ZIP-комплекта: код выхода архиватора не доказывает формат, поэтому меряем байты.
#
# Класс дефекта, который этот скрипт ловит: под `shell: bash` голый `tar` резолвится в GNU tar
# 1.35 из Git for Windows, который не знает `-a` для zip, пишет POSIX-tar с кодом выхода 0, а
# GitHub по расширению .zip ставит application/zip - и битый «архив» доходит до пользователя.
# Мёртвый архив без EOCD не открывает ни Проводник, ни WinRAR.
#
# Запуск:
#     bash packaging/kit/ci/verify_zip.sh dist/gpu-infer-kit-2026-11-12.zip
#     bash packaging/kit/ci/verify_zip.sh --selftest
#
# Коды возврата: 0 - формат и содержимое подтверждены; 1 - архив битый или неполный;
# 2 - проверка не состоялась (файл не прочитан, нет bsdtar, пустой вход).
set -uo pipefail

TARW="/c/Windows/System32/tar.exe"   # полный путь: голый tar под bash - это GNU tar, не bsdtar
MIN_ENTRIES=20                        # нижняя граница: живой комплект 12.11 - 25 записей
NEED_DEFAULT=(
  "START.bat"
  "bin/strata-q36.exe"
  "bin/strata.exe"
  "bin/ggml-cuda.dll"
  "bin/llama-server.exe"
  "kit/classify.py"
  "kit/detect.py"
  "kit/recommend.py"
  "build-measure.json"
  "elf-proof.json"
  "runtime-deps.json"
)

fail() { echo "::error::$*" >&2; exit 1; }
noshow() { echo "ПРОВЕРКА НЕ СОСТОЯЛАСЬ: $*" >&2; exit 2; }

ZIP=""
NEED=()
SELFTEST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --selftest) SELFTEST=1; shift ;;
    --need|--min-entries)
      [ $# -ge 2 ] || noshow "$1 без значения"
      if [ "$1" = "--need" ]; then NEED+=("$2"); else MIN_ENTRIES="$2"; fi
      shift 2 ;;
    -*) noshow "неизвестный флаг $1" ;;
    *) ZIP="$1"; shift ;;
  esac
done

# Листинг нормализуется: bsdtar пишет CRLF и обратные слеши даже под Git Bash, а ведущий ./
# появляется у архивов, собранных командой вида `tar -C dir .`.
listing_of() {
  "$TARW" -t -f "$1" | tr -d '\r' | tr '\\' '/' | sed 's#^\./##'
}

# Сигнатурная мерка по обоим концам файла: заголовок PK\3\4 и EOCD ровно за 22 байта до конца.
check_bytes() {
  local f="$1"
  [ -s "$f" ] || noshow "файл пуст или недоступен: $f"
  local h e
  h=$(head -c 4 "$f" | od -An -tx1 | tr -d ' \n')
  e=$(tail -c 22 "$f" | head -c 4 | od -An -tx1 | tr -d ' \n')
  [ "$h" = "504b0304" ] || fail "$f: нет заголовка PK\\\\3\\\\4 (получено $h) - это не zip"
  [ "$e" = "504b0506" ] || fail "$f: нет EOCD 504b0506 за 22 байта до конца (получено $e) - архив не откроется"
}

verify() {
  local f="$1"
  check_bytes "$f"
  local listing
  listing=$(listing_of "$f") || fail "$f: zip читается как архив, но bsdtar не отдал листинг"
  [ -n "$listing" ] || fail "$f: zip открывается, но записей ноль"
  local entries
  entries=$(printf '%s\n' "$listing" | grep -c .)
  if [ "$entries" -lt "$MIN_ENTRIES" ]; then
    fail "$f: всего $entries записей при нижней границе $MIN_ENTRIES - упаковка неполная"
  fi
  local need=("${NEED_DEFAULT[@]}")
  [ ${#NEED[@]} -gt 0 ] && need=("${NEED[@]}")
  local missing=() n
  for n in "${need[@]}"; do
    # case, а не grep -q: под pipefail grep -q закрывает канал, printf ловит SIGPIPE, и
    # конвейер возвращает 141 на здоровом архиве.
    case $'\n'"$listing"$'\n' in
      *$'\n'"$n"$'\n'*) ;;
      *) missing+=("$n") ;;
    esac
  done
  [ ${#missing[@]} -eq 0 ] || fail "$f: в архиве нет обязательных записей: ${missing[*]}"
  echo "verify_zip: OK $f - $entries записей, все ${#need[@]} обязательных на месте"
}

# Мерка вызывается в подоболочке: fail/noshow внутри неё обязаны ронять только прогон мерки,
# иначе самоконтроль завершился бы на первом же ожидании rc=1.
rc_of() { ( verify "$1" ) >/dev/null 2>&1; echo $?; }

if [ "$SELFTEST" -eq 1 ]; then
  [ -x "$TARW" ] || noshow "нет $TARW - формат-гейт нельзя измерить на этой машине"
  command -v od >/dev/null 2>&1 || noshow "нет od - сигнатуры не снять"
  work=$(mktemp -d "${TMPDIR:-/tmp}/verify-zip-XXXXXX") || noshow "mktemp не удался"
  ok=0; bad=0
  chk() { # chk <имя> <ждём rc> <получено>
    if [ "$2" = "$3" ]; then ok=$((ok + 1)); echo "  ok   $1"
    else bad=$((bad + 1)); echo "FAIL   $1: ждали rc=$2, получили rc=$3"; fi
  }
  mkdir -p "$work/src/kit" "$work/src/bin"
  for f in START.bat build-measure.json elf-proof.json runtime-deps.json \
           bin/strata-q36.exe bin/strata.exe bin/ggml-cuda.dll bin/llama-server.exe \
           kit/classify.py kit/detect.py kit/recommend.py; do
    printf 'x\n' > "$work/src/$f"
  done
  # Дополнение до нижней границы записей: без него неполный архив падал бы по числу записей,
  # а контроль «отклонён по содержимому» не доказывал бы именно содержимое.
  for i in $(seq 1 12); do printf 'p\n' > "$work/src/kit/pad$i.py"; done

  # Вход 1: настоящий zip, собранный bsdtar по списку имён (имена без ./ - как у .NET-упаковщика).
  ( cd "$work/src" && "$TARW" -a -c -f "$work/real.zip" START.bat bin kit \
      build-measure.json elf-proof.json runtime-deps.json ) >/dev/null 2>&1
  chk "настоящий zip принят" 0 "$(rc_of "$work/real.zip")"

  # Вход 2: битый - GNU tar под именем .zip (тот самый дефект с кодом выхода 0).
  ( cd "$work/src" && tar cf "$work/fake.zip" . ) >/dev/null 2>&1
  chk "tar-под-.zip отклонён по сигнатуре" 1 "$(rc_of "$work/fake.zip")"

  # Вход 3: частичный - настоящий zip, но без ключевых записей движков.
  mkdir -p "$work/part/bin" "$work/part/kit"
  printf 'x\n' > "$work/part/START.bat"
  printf 'x\n' > "$work/part/build-measure.json"
  printf 'x\n' > "$work/part/elf-proof.json"
  printf 'x\n' > "$work/part/runtime-deps.json"
  cp "$work/src/kit/"*.py "$work/part/kit/" 2>/dev/null
  printf 'x\n' > "$work/part/bin/readme.txt"
  for i in $(seq 1 16); do printf 'p\n' > "$work/part/kit/pad$i.py"; done
  ( cd "$work/part" && "$TARW" -a -c -f "$work/partial.zip" START.bat bin kit \
      build-measure.json elf-proof.json runtime-deps.json ) >/dev/null 2>&1
  chk "неполный архив отклонён по содержимому" 1 "$(rc_of "$work/partial.zip")"

  # Вход 4: пустой файл - «проверка не состоялась», а не «всё чисто».
  : > "$work/empty.zip"
  chk "пустой вход даёт rc=2" 2 "$(rc_of "$work/empty.zip")"

  # Вход 5: срезанный хвост - заголовок настоящий, EOCD потерян.
  head -c 200 "$work/real.zip" > "$work/trunc.zip"
  chk "обрезанный хвост отклонён" 1 "$(rc_of "$work/trunc.zip")"

  # Вход 6: несуществующий путь - тоже rc=2, опечатка в имени не должна читаться как провал формата.
  chk "нет такого файла - rc=2" 2 "$(rc_of "$work/missing.zip")"

  rm -rf "$work"
  echo "verify_zip selftest: ok=$ok bad=$bad"
  [ $((ok + bad)) -ge 6 ] || { echo "ОТКАЗ: контролей меньше 6 - мерка деградировала"; exit 2; }
  [ "$bad" -eq 0 ] || exit 1
  exit 0
fi

[ -n "$ZIP" ] || noshow "не передан путь до zip - проверка не состоялась"
[ -x "$TARW" ] || noshow "нет $TARW (bsdtar) - листинг не снять"
command -v od >/dev/null 2>&1 || noshow "нет od - сигнатуры не снять"
verify "$ZIP"
