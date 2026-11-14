<#
    Часть 4.4/4.6: сборка дерева портативного комплекта по манифесту и упаковка в zip - с гейтами.

    Это ЛОКАЛЬНЫЙ скрипт стенда (pwsh 7). В комплект входит только обвязка на PowerShell 5.1.

        pwsh -File packaging/kit/ci/pack_kit.ps1 -StrataBuild <dir> -LlamaBuild <dir> -Measures <dir> -Stage <dir> -Zip <file> -VendorStage <dir>
        pwsh -File packaging/kit/ci/pack_kit.ps1 ... -NoCudaRuntime     # комплект без CUDA-рантайма (без cublas)
        pwsh -File packaging/kit/ci/pack_kit.ps1 ... -RepoSrc <dir>     # корень репозитория для веб-морды
                                                                        # (по умолчанию - родитель packaging\)
        pwsh -File packaging/kit/ci/pack_kit.ps1 ... -RuntimeCache <dir>  # кэш архива интерпретатора
                                                                        # (по умолчанию tempdir\strata-packaging-cache)
        pwsh -File packaging/kit/ci/pack_kit.ps1 -VendorWheels -VendorOut <dir>   # скачать и распаковать колёса
        pwsh -File packaging/kit/ci/pack_kit.ps1 -SelfTest              # контроли без сборки и железа
        pwsh -File packaging/kit/ci/pack_kit.ps1 -TextGate              # гейт текстов комплекта до сборки

    Почему по манифесту, а не «скопировать папку»: в dist\gpu-infer-kit лежат build-логи на
    мегабайты, рядом с ними - run\ и __pycache__, созданные самим комплектом при прогонах. Копия
    «что видит глаз» принесла бы этот мусор на чужую машину, и никто бы не заметил: архив
    открывался бы нормально.

    Гейты до того, как архив считается готовым:
      1. каждый обязательный файл манифеста существует - иначе комплект доезжает до чужой машины
         с «модуль не найден» вместо предупреждения;
      1b. полнота набора в обратную сторону: каждый exe/dll, который сборка произвела, либо
          лежит в bin\ комплекта, либо назван в $BIN_WAIVERS с причиной. Без этого потерянный
          модуль уезжает молча: strata_kq.dll грузится из кода по имени, поэтому её нет ни в
          одной импорт-таблице и ни один другой гейт её не увидит;
      1c. манифест не отстаёт от AST-замыкания импортов serve\server.py (разбор деревом модуля
          `ast`, семантика - engine/tests/terminal/test_monitor_bundle.py:286-306). Класс дефекта
          закрыт меркой по первичнику: из замыкания (прогон -TextGate 14.11 - 143 файла /
          4 052 303 Б) не доезжал ровно tools\calibrate.py (29 204 Б), который зовут ПО ПУТИ
          (strata_control/setup_config.py:568-569) - ни одно пакетное правило его не перечисляет,
          и без гейта пропуск прошёл бы молча;
      2. переносимость: в текстовых файлах дерева нет абсолютных путей с литерой диска ни в
         одной форме записи (`C:\x`, `C:/x`, смешанный `C:\x/y`) - ни стенда, ни раннера;
      3. сайдкары читаются: elf-proof.json, runtime-deps.json, build-measure.json - валидный JSON
         БЕЗ BOM (классификатор комплекта читает их json.loads, BOM ломает чтение);
      4. доказательство архитектур покрывает заявленные архитектуры, а полнота списка зависимостей
         закрыто (missing пусто);
      4b. веб-морда на месте: kit\serve\server.py, kit\tools\strata_tokenizer.py,
          kit\serve\web\index.html и распакованные regex / jinja2 / markupsafe в kit\vendor.
          Отсутствие любого - падение с именованной причиной. На чужой машине (RTX 5080) архив
          открывался, движок стартовал, а веб-морды не было вовсе: strata-q36.exe HTTP не отдаёт,
          морду поднимает питоновский serve\server.py, и ни один из перечисленных путей в манифесте
          не значился;
      5. zip открывается, число записей совпадает с деревом, внутри нет моделей (*.gguf);
      6. вес папки и zip - замер, а не оценка; он же уходит в kit-weight.json. Долейка печатается
         по группам (байты и число файлов на группу), чтобы приёмка мерилась числами, а не словами.
      7. автономный интерпретатор: kit\runtime\python\python.exe на месте (пин python-build-
         standalone сверен с packaging\package_terminal.py по дайджесту), он реально импортирует
         колёса комплекта по тому же PYTHONPATH, что соберёт start.ps1, и в архив не уехал балласт
         CPython (символы .pdb, Tcl/Tk, pip) - иначе +143 МиБ на пустое место.

    Коды возврата: 0 - упаковано, все гейты зелёные; 1 - гейт упал; 2 - вход неверен (нет
    каталога, не найден обязательный файл, пустой манифест) - проверка не состоялась.
#>
[CmdletBinding()]
param(
    [string]$StrataBuild = "",
    [string]$LlamaBuild = "",
    [string]$KitSrc = "",
    [string]$Measures = "",
    [string]$Stage = "",
    [string]$Zip = "",
    [string]$CudaBin = "",
    [string]$Version = "",
    [string]$RepoSrc = "",
    [string]$VendorStage = "",
    [string]$VendorOut = "",
    [string]$VendorPython = "",
    [string]$RuntimeCache = "",
    [switch]$NoCudaRuntime,
    [switch]$TextGate,
    [switch]$VendorWheels,
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Это копия стендового упаковщика: корень стенда здесь не выводится из положения скрипта, а
# каталоги сборки, мер и stage задаются только параметрами - с отказом по имени параметра, если
# он не передан. Единственный путь, выведенный из расположения файла, - исходники комплекта:
# они лежат соседним каталогом репозитория (packaging\kit), и эта связь одинакова везде.

# Мусор, который создаётся самой жизнью комплекта и никогда не должен ехать в архив.
$EXCLUDE_DIRS = @('__pycache__', 'run', '.pytest_cache', 'logs')
$EXCLUDE_EXT = @('.log', '.jsonl', '.pyc', '.err', '.tmp')
# Меры, которые едут в комплект очищенными от путей стенда.
$SIDECARS = @("elf-proof.json", "runtime-deps.json", "build-measure.json")
# Что сборка производит, но в комплект не берёт по делу. Каждый пункт обязан иметь причину:
# без неё waiver-список - это способ молча протащить потерянный файл мимо полноты набора.
$BIN_WAIVERS = @{
    "test-cuda-upload-stream.exe" = "тест сборки llama.cpp: в комплект не едет, появляется только в " +
        "дереве, собранном с LLAMA_BUILD_TESTS=ON (CI собирает с OFF)"
}
# ---------------- доливайка веб-морды -------------------------------------------------------------
# Веб-морда Страты - это НЕ бинарник: strata-q36.exe HTTP не отдаёт, морду поднимает питоновский
# serve\server.py своим окружением. Разведка чужой машины (RTX 5080) показала, что в архиве морды
# нет: каталоги serve\, tools\, strata_control\, strata_cli\ и колёса в манифесте не значились ни
# разу. Доливаемое описан СПИСКОМ ПРАВИЛ, а не «копировать каталог»: вместе с serve\ и tools\
# в архив уехали бы 252 тестовых файла (2.9 МиБ балласта) и стендовые фикстуры - и архив при этом
# открывался бы нормально, то есть дефект был бы невидим.
#
# Раскладка обязательна: сервер вычисляет ROOT как parents[1] от serve/server.py (serve/server.py:61)
# и кладёт в sys.path ROOT и ROOT/tools (:62-63). Значит kit\serve\server.py даёт ROOT = kit\, и
# рядом обязаны лежать kit\tools, kit\strata_control, kit\strata_cli.
# why - причина, по которой путь едет в архив; она же печатается в отказе, если правило ничего не нашло.
$WEB_SPECS = @(
    @{ group = "serve-code"; dir = "serve"; recurse = $false; pattern = "*.py"
       omit = @("test_*.py", "mcp_fake_server.py")
       why  = "serve/*.py кроме тестов: замыкание импортов от serve/server.py (28 файлов, 1090526 Б); " +
              "mcp_fake_server.py нужен только serve/test_mcp.py" },
    @{ group = "serve-data"; dir = "serve"; recurse = $false; files = @("chat_template.jinja")
       why  = "server.py:10401 берёт ROOT/serve/chat_template.jinja, когда шаблона из пакета нет" },
    @{ group = "serve-web"; dir = "serve/web"; recurse = $true; any = $true
       why  = "статика морды: webfiles.py:12 (WEB = serve/web) и server.py:7978/8010/8245 читают её с диска" },
    @{ group = "control"; dir = "strata_control"; recurse = $false; pattern = "*.py"
       omit = @("test_*.py")
       why  = "engine_component, tls, reader_room, draft_layer, drafting, vision_reader импортируются " +
              "сервером на верхнем уровне" },
    @{ group = "control-data"; dir = "strata_control"; recurse = $false; files = @("update_keys.json")
       why  = "signing.py:32 BUILTIN_KEYS = Path(__file__).with_name(update_keys.json)" },
    @{ group = "cli"; dir = "strata_cli"; recurse = $true; pattern = "*.py"
       omit = @("test_*.py")
       why  = "strata_cli.client зовёт сам сервер (server.py:8049), strata_cli.cli - " +
              "strata_control/runtime.py:472; дальше по их импортам идёт почти весь пакет" },
    @{ group = "tools"; dir = "tools"; recurse = $false; files = @("strata_tokenizer.py", "gguf_reader.py",
                                                                   "calibrate.py")
       why  = "server.py:10259 import strata_tokenizer, strata_control/gguf_preflight.py:15 gguf_reader; " +
              "calibrate.py зовётся ПО ПУТИ: strata_control/setup_config.py:568-569 вставляет ROOT/tools в " +
              "sys.path и после калибровки (tune) делает `import calibrate` - голое имя вместо пакета, " +
              "поэтому ни одно пакетное правило его не перечисляет (29 204 Б, последний недонесённый из " +
              "замыкания: прогон -TextGate 14.11 - 143 файла / 4 052 303 Б)" }
)
# serve/fixtures\ в доливайку НЕ входит (по заданию): единственное чтение - dsml.FIXTURE_TEMPLATE,
# а server.py:10401 обязан проверить .exists() и взять serve/chat_template.jinja, то есть
# отсутствие фикстуры деградирует орфографию DSML-тега, но не роняет сервер.
# ---------------- гейт 1c: манифест не отстаёт от AST-замыкания импортов ---------------------------
# Правила выше молчат, когда импорт появляется там, где список его не ждал: calibrate.py проехал
# именно так - его зовут ПО ПУТИ (strata_control/setup_config.py:568-569 вставляет ROOT/tools в
# sys.path и делает `import calibrate` голом именем), и ни одно пакетное правило его не перечисляет.
# Мера, которая это ловит, обязана смотреть в код, а не в список: транзитивное замыкание импортов от
# serve/server.py разбором модуля ast. Семантика - engine/tests/terminal/test_monitor_bundle.py:
# 286-306: ast.walk по всему дереву файла (попадают и отложенные импорты внутри функций, if и try),
# переход только туда, где файл реально лежит, пакет разворачивается в <пакет>/__init__.py.
# Дополнительно к первичнику: sys.path сервера - ROOT и ROOT/tools (serve/server.py:61-63), поэтому
# голое имя ищется и в tools/, и относительные импорты (`from . import x`, `from ..y import z`)
# разворачиваются в полные имена - иначе замыкание оборвалось бы ровно там, где живёт calibrate.
$CLOSURE_ENTRY = "serve/server.py"
# Ряд каталогов - те же четыре, что у правил доливайки: вне их лежат чужие библиотеки (numpy, PIL),
# которые в архив не едут по условию задачи, и tests/, исключённый намеренно.
$CLOSURE_ROOTS = @("serve", "strata_control", "strata_cli", "tools")
# Разбор живёт НЕ здесь, а в соседнем файле packaging\kit\ci\web_closure.py - он единственный носитель
# AST-семантики: скрипт вызывает его и читает JSON. Копия разборщика внутри этого файла была бы вторым
# носителем истины, то есть ровно тем классом дефекта, который гейт ловит: список, отстающий от кода,
# молчит - так же молчала бы устаревшая копия разбора. В дерево стенда не пишется ничего: носитель
# вызывается как файл, он уже лежит в комплекте исходников. Поля строки files[]: path, bytes, via -
# файл-источник перехода, без него отказ неотличим от «файл просто забыли».
$CLOSURE_SYSPATH = @(".", "tools")

# Колёса ВРЕМЕНИ ВЫПОЛНЕНИЯ без фолбэка. С фолбэками (truststore/certifi в strata_control/tls.py:30/37,
# jsonschema/referencing в serve/structured.py:81-89 лениво, psutil, PIL, numpy) - не едут.
# Первичник - PyPI, снимок 14.11: regex 2026.11.9 (win_amd64 есть только cp311..cp315, cp39/cp310 НЕТ),
# markupsafe 3.0.4 (cp39..cp315), jinja2 3.1.6 (pure py3-none-any). Отсюда и набор ABI:
# пересечение бинарных рядов regex и markupsafe = cp311..cp315,Freethreaded-сборки (+t) не берём:
# их выбирает только интерпретатор, собранный с GIL-free, а комплект рассчитан на обычный CPython.
$VENDOR_ABIS = @("cp311", "cp312", "cp313", "cp314", "cp315")
$VENDOR_PURE_ABI = "py3-none-any"
# Что вырезается из распакованного колеса. `tests` - тестовый набор самого regex (regex\tests\
# test_regex.py, ~1,5 МиБ): он не импортируется ни сервером, ни jinja2, а на 5 ABI удвоил бы вес
# колёс. `__pycache__` вырезается и в остальных каталогах: .pyc привязан к интерпретатору, который
# колеса распаковывал, а не к тому, который их будет грузить.
$VENDOR_EXCLUDE_DIRS = @('__pycache__', 'tests')
$VENDOR_PKGS = @(
    @{ name = "regex";      version = "2026.11.9"; abi = "binary";
       why = "tools/strata_tokenizer.py:24 - импорт верхнего уровня, модуль тянется на старте сервера" },
    @{ name = "markupsafe"; version = "3.0.4";     abi = "binary";
       why = "транзитивная зависимость jinja2 (без фолбэка)" },
    @{ name = "jinja2";     version = "3.1.6";     abi = "pure";
       why = "serve/frontend.py:28-29 - импорт верхнего уровня, шаблон чата рендерит именно jinja2" }
)
# Обязательное присутствие в архиве (гейт 4b). Мёртвая молчаливая деградация хуже красной сборки:
# ровно так и выглядел исходный дефект - «архив нормальный, страницы нет».
$KIT_PRESENCE = @(
    @{ path = "kit\serve\server.py";                       why = "сама веб-морда: HTTP-сервер поднимает этот файл" },
    @{ path = "kit\serve\web\index.html";                  why = "страница морды, которую просит браузер" },
    @{ path = "kit\serve\chat_template.jinja";             why = "фолбэк шаблона чата (server.py:10401)" },
    @{ path = "kit\tools\strata_tokenizer.py";             why = "импорт верхнего уровня сервера (server.py:10259)" },
    @{ path = "kit\tools\gguf_reader.py";                  why = "gguf_preflight.py:15" },
    @{ path = "kit\tools\calibrate.py";                    why = "setup_config.py:569 `import calibrate` " +
                                                                  "после tune: голое имя из ROOT/tools" },
    @{ path = "kit\strata_control\engine_component.py";    why = "импорт верхнего уровня сервера" },
    @{ path = "kit\strata_cli\client.py";                  why = "server.py:8049" },
    @{ path = "kit\strata_cli\cli.py";                     why = "strata_control/runtime.py:472" }
)
# ---------------- автономный интерпретатор: kit\runtime\python -------------------------------------
# Веб-морда комплекта - это serve\server.py, то есть питоновский процесс: без интерпретатора архив,
# в котором есть морда, остаётся папкой с файлами. Embeddable-сборка CPython отвергнута, и теперь
# механизм измерен, а не описан (glm\scripts\kit415_pth_mechanism_2026-11-14.ps1, семь прогонов,
# артефакт glm\2026-11-14_session\kit415-pth-mechanism.txt): пока рядом с python.exe нет ._pth,
# колёса доходят ИСКЛЮЧИТЕЛЬНО через PYTHONPATH; как только файл появляется, sys.path сворачивается
# в его строки (isolated=1, import site=0) и верная переменная окружения игнорируется МОЛЧА -
# ровно отсюда «no module named jinja2» на чужой машине.
# поэтому правило такое: если ._pth в дереве есть, путь вендора дописывается в сам файл
# (Add-VendorToPth, относительно каталога python.exe). Если ._pth НОЛЬ - как у install_only-носителя
# этого же пина (3384 записей архива, из них `._pth` 0) - дописывать некуда, и прежний вывод
# «значит, законен PYTHONPATH start.ps1» оказался неверным: PYTHONPATH читает тот интерпретатор,
# который запустил процесс, а на чужой машине его задаёт start.ps1, и любая ветка «python системный /
# переменная не дожила до дочернего процесса» роняет морду на «no module named jinja2». Механизм без
# переменной измерен прогоном glm\scripts\kit469_pth_depth.ps1 по дереву СОБРАННОГО комплекта
# (C:\tmp\kit464\unpacked\kit, PYTHONPATH снят): файл `.pth` в Lib\site-packages обрабатывается
# site, а его строки разрешаются ОТ КАТАЛОГА ФАЙЛА, то есть четырьмя уровнями вверх до kit\vendor;
# import regex/jinja2/markupsafe даёт rc=0 ровно на глубине 4, на 2/3/5 - красные. Значит на
# упаковке вендор дописывается в ._pth либо пишется сайдкар-`.pth` в site-packages, и гейт в обоих
# случаях обязан проверять импорт БЕЗ PYTHONPATH.
#
# НОСИТЕЛЬ НЕ ВЫДУМАН - он уже запинен в этом репозитории, в packaging\package_terminal.py:
# PBS_RELEASE (:62), PYTHON_VERSION (:63), блок PYTHON_PINS["windows-x86_64"] (:69-73) с file/sha256/
# путем exe/типом архива, sha256() (:155-160), fetch_python() (:163-178) с SystemExit при несовпадении
# дайджеста и кэшем tempfile.gettempdir()/strata-packaging-cache (:382, распаковка - tarfile (:392)).
# PowerShell не импортирует python-модуль, поэтому значения продублированы константами НИЖЕ, а
# -SelfTest сверяет каждое с первоисточником (саботаж: изменённый дайджест во временной копии
# package_terminal.py красит прогон). Ревизору довольно открыть оба файла и сравнить пять строк.
$PBS_RELEASE = "20261009"                     # package_terminal.py:62
$PYTHON_VERSION = "3.12.15"                   # package_terminal.py:63
$PYTHON_TARGET = "windows-x86_64"             # package_terminal.py:69
$PYTHON_ARCH_NAME = "cpython-${PYTHON_VERSION}+${PBS_RELEASE}-x86_64-pc-windows-msvc-install_only.tar.gz"
$PYTHON_ARCH_CACHED = $PYTHON_ARCH_NAME.Replace("+", "_")   # package_terminal.py:166 (file.replace("+","_"))
$PYTHON_ARCH_SHA256 = "194c8f0d9e0de6f1c4576e5dfa67819a48c764be87608b74b8ad43387a57b93b"
$PYTHON_ARCH_EXE = "python/python.exe"        # package_terminal.py:72, путь ВНУТРИ архива
$PBS_URL_BASE = "https://github.com/astral-sh/python-build-standalone/releases/download/"
$PYTHON_CACHE_DIRNAME = "strata-packaging-cache"   # package_terminal.py:382 (tempfile.gettempdir())
# Раскладка: содержимое архивного каталога `python/` едет в kit\runtime\python\, поэтому в архиве
# обязан появиться путь kit\runtime\python\python.exe.
$RUNTIME_DEST = "kit\runtime\python"
# Сайдкар `.pth` для случая «._pth нет»: лежит в Lib\site-packages, строки разрешаются от его
# каталога. Имя НЕ должно начинаться с pip - $RUNTIME_CUT_GLOBS ("Lib\site-packages\pip*") вырезал
# бы его при обрезке балласта, и гейт импорта без PYTHONPATH краснел бы на здоровом дереве.
$VENDOR_SITE_DIR = "Lib\site-packages"
$VENDOR_SITE_PTH = "strata_kit_vendor.pth"
$RUNTIME_PRESENCE = @(
    @{ path = "kit\runtime\python\python.exe";             why = "автономный интерпретатор: без него " +
                                                                  "serve\server.py нечем запускать" },
    @{ path = "kit\runtime\python\python312.dll";          why = "ядро интерпретатора: exe - загрузчик, " +
                                                                  "весь код в этой dll" },
    @{ path = "kit\runtime\python\DLLs\_ssl.pyd";          why = "https морды: ssl без него не импортируется" }
)
# Балласт. Числа сняты НЕ на глаз - проходом по распакованному носителю из кэша (тот же файл, что
# проверяли прогоны kit378: 46 352 482 Б, sha256 выше). Корзина посчитана непересекающимися
# корзинами в том же порядке, в каком их находит Get-RuntimeTrimPlan, поэтому суммы сходятся:
#   *.pdb вне cut-каталогов  78 331 904 Б /  38   - символы отладки (python312.pdb 18 542 592,
#                                                   DLLs\*.pdb 58 556 416 / 34: их читает только отладчик)
#   __pycache__ везде        9 029 848 Б / 563    - .pyc: тот же класс мусора, что $EXCLUDE_DIRS
#   Lib\venv                 8 853 143 Б /  12    - окружения никто не создаёт (внутри 2 .pdb вёрстки
#                                                   exe - 8 298 496 Б из 8 853 143)
#   tcl                      6 925 566 Б / 1270   - файлы Tcl/Tk для tkinter, который ниже
#   Lib\site-packages\pip*   5 690 789 Б / 479    - pip (сам пакет с dist-info 10 710 340 Б / 883,
#                                                   остальное - его __pycache__): колёса уже распакованы
#                                                   в kit\vendor, на чужой машине ставить нечего
#   DLLs\tcl86t/tk86t/_tkinter 3 484 720 Б / 3    - нативная часть tkinter (1 839 896 + 1 589 528 + 55 296)
#   Lib\ensurepip            1 851 867 Б /   4    - несёт колесо pip тем же путём
#   include                  1 254 634 Б / 214    - C-заголовки: комплект ничего не компилирует
#   Lib\idlelib              1 132 752 Б /  90    - редактор IDE, у морды свой интерфейс
#   libs                       728 836 Б /  34    - import-библиотеки для линковщика, то же
#   DLLs\_test*.pyd+_ctypes_test 536 576 Б /  9   - модули для тестов самого CPython: Lib\test в
#                                                   install_only нет вовсе, грузить их некому
#   Lib\tkinter                364 656 Б /  14   - GUI-обвязка, морда её не зовёт
#   Lib\lib2to3                298 069 Б /  75   - устаревший 2to3 (удалён из CPython в 3.13)
#   Lib\turtledemo              63 258 Б /  22   - демо tkinter
# ИТОГО вырезано 118 546 618 Б / 2827 файлов; в архив едет 557 файлов / 31 327 227 Б (29,9 МиБ)
# вместо 149 873 845 Б / 3384 файлов (142,9 МиБ). Lib\test в этом дистрибутиве нет - резать нечего.
$RUNTIME_CUT_DIRS = @("tcl", "include", "libs", "Lib\venv", "Lib\ensurepip", "Lib\tkinter",
                      "Lib\idlelib", "Lib\turtledemo", "Lib\lib2to3")
$RUNTIME_CUT_ANY = @("__pycache__")
$RUNTIME_CUT_GLOBS = @("Lib\site-packages\pip*")
$RUNTIME_CUT_EXT = @(".pdb")
$RUNTIME_CUT_FILES = @("DLLs\tcl86t.dll", "DLLs\tk86t.dll", "DLLs\_tkinter.pyd",
                       "DLLs\_testbuffer.pyd", "DLLs\_testcapi.pyd", "DLLs\_testclinic.pyd",
                       "DLLs\_testconsole.pyd", "DLLs\_testimportmultiple.pyd",
                       "DLLs\_testinternalcapi.pyd", "DLLs\_testmultiphase.pyd",
                       "DLLs\_testsinglephase.pyd", "DLLs\_ctypes_test.pyd")
# Страховка от «подрежем нужное»: ни один путь из списка не имеет права попасть в план вырезки, и
# -SelfTest проверяет это на синтетическом дереве с саботажем. Список собран по замеру: 71 модуль
# stdlib, который замыкание от serve/server.py действительно импортирует, плюс загрузочная цепочка
# самого exe и нативные модули, без которых эти импорты падают.
$RUNTIME_KEEP = @(
    "python.exe", "pythonw.exe", "python3.dll", "python312.dll", "vcruntime140.dll",
    "vcruntime140_1.dll", "Lib\site-packages\README.txt", "Lib\os.py", "Lib\sysconfig.py",
    "Lib\json\__init__.py", "Lib\ssl.py", "Lib\sqlite3\__init__.py", "Lib\ctypes\__init__.py",
    "Lib\encodings\__init__.py", "Lib\asyncio\__init__.py", "Lib\urllib\__init__.py",
    "Lib\http\__init__.py", "Lib\email\__init__.py", "Lib\xml\__init__.py", "Lib\re\__init__.py",
    "Lib\logging\__init__.py", "Lib\unittest\__init__.py", "Lib\multiprocessing\__init__.py",
    "Lib\concurrent\__init__.py", "Lib\importlib\__init__.py", "Lib\socket.py",
    "Lib\socketserver.py", "Lib\subprocess.py", "Lib\threading.py", "Lib\pathlib.py",
    "Lib\hashlib.py", "Lib\hmac.py", "Lib\secrets.py", "Lib\stat.py", "Lib\shutil.py",
    "Lib\tempfile.py", "Lib\zipfile.py", "Lib\tarfile.py", "Lib\argparse.py", "Lib\csv.py",
    "Lib\difflib.py", "Lib\statistics.py", "Lib\ipaddress.py", "Lib\webbrowser.py",
    "Lib\shlex.py", "Lib\glob.py", "Lib\codecs.py", "Lib\platform.py", "Lib\struct.py",
    "Lib\queue.py", "Lib\random.py", "Lib\typing.py", "Lib\dataclasses.py", "Lib\contextlib.py",
    "Lib\copy.py", "Lib\heapq.py", "Lib\bisect.py", "Lib\traceback.py", "Lib\atexit.py",
    "Lib\getpass.py", "Lib\textwrap.py", "Lib\mmap.py", "Lib\datetime.py", "Lib\zoneinfo.py",
    "Lib\tomllib\__init__.py", "Lib\html\__init__.py", "Lib\wsgiref\simple_server.py",
    "DLLs\_ssl.pyd", "DLLs\libssl-3-x64.dll", "DLLs\libcrypto-3-x64.dll", "DLLs\_socket.pyd",
    "DLLs\_sqlite3.pyd", "DLLs\sqlite3.dll", "DLLs\_ctypes.pyd", "DLLs\libffi-8.dll",
    "DLLs\_hashlib.pyd", "DLLs\_lzma.pyd", "DLLs\_bz2.pyd", "DLLs\zlib1.dll", "DLLs\_queue.pyd",
    "DLLs\_asyncio.pyd", "DLLs\_overlapped.pyd", "DLLs\select.pyd", "DLLs\_multiprocessing.pyd",
    "DLLs\_decimal.pyd", "DLLs\_uuid.pyd", "DLLs\_wmi.pyd", "DLLs\_zoneinfo.pyd",
    "DLLs\unicodedata.pyd", "DLLs\pyexpat.pyd", "DLLs\_elementtree.pyd", "DLLs\winsound.pyd",
    "DLLs\_msi.pyd"
)
# Smoke-набор, которым проверяется уже собранный интерпретатор: те же имена, что сняты AST-разбором
# замыкания от serve/server.py (71 модуль), за исключением POSIX-only (fcntl, pwd, resource) - на
# Windows они не импортируются ни до, ни после обрезки. Прогон на носителе: 77 модулей, 0 падений.
$RUNTIME_SMOKE = "json,ssl,sqlite3,ctypes,asyncio,urllib.request,http.client,email.utils," +
                 "xml.etree.ElementTree,multiprocessing,concurrent.futures,logging,re,pathlib," +
                 "importlib,secrets,statistics,difflib,csv,ipaddress,webbrowser,base64,socket," +
                 "socketserver,subprocess,tempfile,uuid,zipfile,tarfile,textwrap,heapq,bisect," +
                 "shlex,shutil,signal,atexit,glob,platform,struct,codecs,contextlib,copy,dataclasses," +
                 "typing,traceback,zoneinfo,tomllib,html,hashlib,hmac,datetime,mmap,queue,random"
# Что обязан импортировать интерпретатор из архива - ровно то, без чего веб-морда не поднимается
# (serve/frontend.py:28-29 jinja2, tools/strata_tokenizer.py:24 regex).
$RUNTIME_VENDOR_IMPORTS = "jinja2, regex"
# Гейт 2 (переносимость) меряет литеру диска во ВСЕХ текстовых файлах комплекта, и доливайка
# добавляет 213 исходников морды. На живом дереве находок 17 строк в 10 файлах, и ни одна не путь
# сборки: это запасные значения переменных окружения (C:\Windows, C:\Program Files), текст подсказок
# пользователю («наберите D:\Strata-models»), docstring про extended-length пути и одна строка с
# регулярным выражением `\d\d:\d\d`, где `d:` - совпадение сигнатуры, а не путь.
# Отпускаются ПОИМЁННО И С ЧИСЛОМ СТРОК: нахождение лишней строки в том же файле, пропавшая строка
# (список устарел) и отпуск, не сработавший ни разу, красят прогон. Список живёт в архивных путях
# (kit\...), и оба места замера - -TextGate по исходникам и гейт 2 по дереву раскладки - подписывают
# находки тем же ключом, иначе одно и то же условие получило бы два разных носителя истины.
$WEB_STAND_WAIVERS = [ordered]@{
    'kit\serve\server.py' = @{ hits = 2
        why = 'комментарий 3595-3596: запись схемы file:// («file://C:/x.png») - написание URL, а не путь сборки' }
    'kit\serve\telemetry.py' = @{ hits = 1
        why = 'запас переменной ProgramFiles при поиске nvml.dll: r-C:\Program Files читается, только если переменная окружения пуста' }
    'kit\serve\loader_diag.py' = @{ hits = 1
        why = 'запас SystemRoot (C:\Windows) в диагностике загрузчика' }
    'kit\strata_control\app_policy.py' = @{ hits = 1
        why = 'литерал-заглушка реестра политик _MODELS (exe C:/x/strata-dsv41.exe); в замыкании импортов сервера файла нет' }
    'kit\strata_control\folders.py' = @{ hits = 3
        why = 'три строки подсказки пользователю «наберите, например, D:\Strata-models» - образец ввода, а не путь' }
    'kit\strata_control\longpath.py' = @{ hits = 3
        why = 'docstring про extended-length форму \\?\C:\ и два текста подсказки про STRATA_COMPONENTS_DIR' }
    'kit\strata_cli\bench_standard.py' = @{ hits = 1
        why = 'совпадение сигнатуры внутри литерала регулярки «\d\d:\d\d» (проверка UTC ISO 8601): буква d перед двоеточием, не диск' }
    'kit\strata_cli\consoleinfo.py' = @{ hits = 1
        why = 'запас WINDIR (C:\Windows) для каталога шрифтов' }
    'kit\strata_cli\launch\access.py' = @{ hits = 3
        why = 'запасы ProgramFiles, ProgramFiles(x86), ProgramData и путь tailscale.exe по умолчанию: читаются только при пустых переменных окружения' }
    'kit\strata_cli\launch\runner.py' = @{ hits = 1
        why = 'текст подсказки «--data-dir D:\Strata-models» - образец ввода пользователю' }
}
# Пути, которые делают «портативный» непригодным на чужой машине: ЛЮБАЯ литера диска и ЛЮБОЙ
# разделитель. Прежняя сигнатура ловила только обратные слеши трёх литер (D, F, E) и C:\Users,
# поэтому молчала на реальных мерах: в elf-proof.json и build-measure.json значения записаны в
# форме «литера, косая черта, дерево, затем \\ перед именем файла» - первая половина не совпадала
# вовсе. Та же причина дырявит Actions: у раннера рабочий каталог начинается на C:\, а сочетание
# литеры C с обратным слэшем в старом наборе не было.
# Lookbehind обязан быть: без него `https://` даёт совпадение на `s://`, и очистка изуродовала бы
# ссылки в models.json (мерка кандидата на живом дереве: 14 находок, ноль ложных).
$STAND_PATH_RE = '(?i)(?<![a-z])[a-z]:[\\/]'
# Гейт 2 НЕ меряет дерево автономного интерпретатора: kit\runtime\python - это распакованный
# CPython 3.12.15 с дайджестом-пином, а не исходники Страты. Его provenance доказывается sha256, а
# не грепом, и отпускать его строки поимённо с числом находок означало бы список, который краснеет
# на каждом релизе PBS. Замер на носителе после обрезки: 8 находок литеры диска в 520 текстовых
# файлах дерева - все docstring-примеры upstream (урезать их нельзя, переписывать чужой stdlib
# незачем). На всё остальное дерево - kit\serve, kit\tools, обвязка, меры - отпуск НЕ распространяется.
$PORTABILITY_SKIP = @("kit\runtime\python\")
# Один носитель перечня текстовых форматов: .jinja добавлен вместе с доливайкой (serve/chat_template
# .jinja едет в архив), и два места замера обязаны мерить одно и то же дерево расширений.
$TEXT_EXT = @('.py', '.ps1', '.bat', '.json', '.md', '.txt', '.cmd', '.jinja')

function Join2([string]$base, [string]$tail) {
    # Join-Path бросает исключение на несуществующем диске; здесь отказ обязан быть нашим текстом.
    if (-not $base) { return $tail }
    return ($base.TrimEnd('\', '/')) + '\' + $tail
}

function Get-KitFiles([string]$Dir) {
    if (-not (Test-Path -LiteralPath $Dir)) { throw "нет каталога $Dir - проверка не состоялась" }
    return @(Get-ChildItem -LiteralPath $Dir -Recurse -File -Force | Where-Object {
        $rel = $_.FullName.Substring($Dir.Length).TrimStart('\', '/')
        $parts = @($rel -split '[\\/]')
        $dirBad = @($parts[0..($parts.Count - 2)] | Where-Object { $_ -in $EXCLUDE_DIRS }).Count -gt 0
        $nameBad = $_.Extension -in $EXCLUDE_EXT
        -not $dirBad -and -not $nameBad
    })
}

function Get-StandPathHit([string]$Path) {
    # Пустой ответ - «не найдено», а не «файл пуст»: вызывающий печатает каждую находку, и
    # различать эти два случая нужно здесь, а не в каждом гейте отдельно.
    # Возвращаются ВСЕ строки с совпадением, а не первая. Прежняя «первая строка» делала бессмысленным
    # счётчик отпуска ($WEB_STAND_WAIVERS): в файле находок хоть три, хоть ноль строк - а на выходе
    # всегда единица, и «число находок сверено» превращалось в декорацию.
    $t = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if (-not $t) { return @() }
    return @($t -split "`r?`n" | Where-Object { $_ -match $STAND_PATH_RE } | ForEach-Object { $_.Trim() })
}

function Test-NoStandPaths([string]$Dir) {
    # Читаем только текстовые файлы: в бинарниках путь сборки живёт в отладочной секции и на запуск
    # не влияет, а «найти подстроку в 300 МиБ» не является меркой переносимости.
    # Дерево автономного интерпретатора ($PORTABILITY_SKIP) не меряется - его provenance доказан
    # sha256-пином, а не грепом. Число пропущенных файлов отдаётся наружу через
    # $script:PortabilitySkipped: «гейт ничего не нашёл» обязано быть отличимо от «гейт ничего не
    # смотрел», иначе отпуск для чужого дерева превратился бы в выключатель всего гейта.
    $hits = @()
    $script:PortabilitySkipped = 0
    foreach ($f in (Get-KitFiles -Dir $Dir) | Where-Object {
                   $_.Extension -in $TEXT_EXT }) {
        $rel = $f.FullName.Substring($Dir.Length).TrimStart('\', '/')
        $norm = $rel.Replace('/', '\')
        if (@($PORTABILITY_SKIP | Where-Object {
            $norm.StartsWith($_, [System.StringComparison]::OrdinalIgnoreCase) }).Count) {
            $script:PortabilitySkipped++
            continue
        }
        foreach ($line in @(Get-StandPathHit $f.FullName)) {
            $hits += ("{0}: {1}" -f $rel, $line)
        }
    }
    return $hits
}

function Get-WebPayload([string]$Repo, [bool]$Required) {
    # Ключи - пути ВНУТРИ архива (kit\...), значения - откуда брать. Правила перечислены в
    # $WEB_SPECS; Required=$true обязывает каждое правило найти хотя бы один файл: правило,
    # которое перестало находить (каталог переименовали, шаблон удалили), отличимо от «всё чисто»
    # только так.
    $out = [ordered]@{}
    $stats = [ordered]@{}
    if (-not $Repo) {
        if ($Required) { throw "не задан корень репозитория (-RepoSrc) - веб-морду брать неоткуда" }
        return [pscustomobject]@{ Files = $out; Stats = $stats }
    }
    # -RepoSrc в CI относительный ("strata"), а ключ строится через Substring($base.Length) от
    # АБСОЛЮТНОГО FullName: без нормализации срезалось начало пути и ключи выходили вида
    # "kit\serve\ects\Strata-3060Ti\engine\serve\__init__.py" (замер 14.11, прогон 14).
    # Нормализуем только существующий каталог: кейс selftest с несуществующим -RepoSrc обязан
    # падать своим отказом по входу, а не исключением Get-Item.
    if (Test-Path -LiteralPath $Repo -PathType Container) {
        $Repo = (Get-Item -LiteralPath $Repo).FullName
    }
    foreach ($spec in $WEB_SPECS) {
        $base = Join2 $Repo ($spec.dir.Replace('/', '\'))
        $found = @()
        if (Test-Path -LiteralPath $base -PathType Container) {
            if ($spec.ContainsKey('files')) {
                foreach ($f in @($spec.files)) {
                    $p = Join2 $base $f
                    if (Test-Path -LiteralPath $p -PathType Leaf) { $found += Get-Item -LiteralPath $p }
                    elseif ($Required) { throw "доливайка '$($spec.group)': нет файла $p - $($spec.why)" }
                }
            } else {
                foreach ($it in @(Get-ChildItem -LiteralPath $base -File -Force -Recurse:([bool]$spec.recurse))) {
                    $rel = $it.FullName.Substring($base.Length).TrimStart('\', '/')
                    $parts = @($rel -split '[\\/]')
                    if (@($parts[0..($parts.Count - 2)] | Where-Object { $_ -in $EXCLUDE_DIRS }).Count) { continue }
                    if ($it.Extension -in $EXCLUDE_EXT) { continue }
                    if ($spec.ContainsKey('pattern')) {
                        if ($it.Name -notlike [string]$spec.pattern) { continue }
                        $skip = $false
                        foreach ($o in @($spec.omit)) { if ($it.Name -like $o) { $skip = $true; break } }
                        if ($skip) { continue }
                    }
                    $found += $it
                }
            }
        } elseif ($Required) {
            throw "доливайка '$($spec.group)': нет каталога $base - $($spec.why)"
        }
        if ($Required -and @($found).Count -eq 0) {
            throw "доливайка '$($spec.group)': правило не нашло ни одного файла в $base - $($spec.why)"
        }
        $bytes = [long]0
        foreach ($it in @($found | Sort-Object -Property FullName)) {
            $rel = $it.FullName.Substring($base.Length).TrimStart('\', '/').Replace('/', '\')
            $key = "kit\" + $spec.dir.Replace('/', '\').TrimEnd('\') + "\" + $rel
            if ($out.Contains($key)) { throw "доливайка: дубликат пути в архиве - $key" }
            $out[$key] = $it.FullName
            $bytes += $it.Length
        }
        $stats[$spec.group] = [ordered]@{ files = @($found).Count; bytes = $bytes
                                         archive = "kit\" + $spec.dir.Replace('/', '\') }
    }
    return [pscustomobject]@{ Files = $out; Stats = $stats }
}

function Get-VendorPayload([string]$Stage, [bool]$Required) {
    # Распакованные колёса едут отдельным подкаталогом на каждый ABI (kit\vendor\cp314\regex\...),
    # потому что .pyd внутри regex и markupsafe собираются под конкретный CPython: единый каталог
    # «на самый свежий ABI» дал бы «модуль не найден» у всякого, у кого Python на версию старее.
    # Pure-пакеты (jinja2) лежат в kit\vendor\py3-none-any\ - их не плодят на каждый ABI.
    # PYTHONPATH комплекта = kit\vendor\<abi> + kit\vendor\py3-none-any.
    $out = [ordered]@{}
    $stats = [ordered]@{}
    $none = [pscustomobject]@{ Files = $out; Stats = $stats }
    if (-not $Stage) {
        if ($Required) { throw "не задан -VendorStage: комплект без regex/jinja2 поднимает движок, " +
                               "но веб-морду не запустит ни при каких обстоятельствах" }
        return $none
    }
    if (-not (Test-Path -LiteralPath $Stage -PathType Container)) {
        if ($Required) { throw "нет каталога колёс -VendorStage: $Stage - шаг -VendorWheels не выполнен" }
        return $none
    }
    $binary = @($VENDOR_PKGS | Where-Object { $_.abi -eq "binary" } | ForEach-Object { $_.name })
    $pure = @($VENDOR_PKGS | Where-Object { $_.abi -eq "pure" } | ForEach-Object { $_.name })
    foreach ($abi in ($VENDOR_ABIS + @($VENDOR_PURE_ABI))) {
        $base = Join2 $Stage $abi
        $need = if ($abi -eq $VENDOR_PURE_ABI) { $pure } else { $binary }
        if (-not (Test-Path -LiteralPath $base -PathType Container)) {
            if ($Required) {
                $why = (@($VENDOR_PKGS | Where-Object { ($abi -eq $VENDOR_PURE_ABI) -eq ($_.abi -eq "pure") })[0]).why
                throw "колёса: нет каталога ABI '$abi' ($base) - $why"
            }
            continue
        }
        foreach ($pn in $need) {
            if (-not (Test-Path -LiteralPath (Join2 (Join2 $base $pn) "__init__.py") -PathType Leaf)) {
                if ($Required) { throw "колёса: в '$base' нет пакета $pn ($pn\__init__.py) - колесо не распаковано" }
            }
        }
        $bytes = [long]0; $n = 0
        foreach ($it in @(Get-ChildItem -LiteralPath $base -File -Force -Recurse | Sort-Object -Property FullName)) {
            $rel = $it.FullName.Substring($base.Length).TrimStart('\', '/')
            if (@(($rel -split '[\\/]') | Where-Object { $_ -in $VENDOR_EXCLUDE_DIRS }).Count) { continue }
            if ($it.Extension -in $EXCLUDE_EXT) { continue }
            $key = "kit\vendor\$abi\" + $rel.Replace('/', '\')
            if ($out.Contains($key)) { throw "колёса: дубликат пути в архиве - $key" }
            $out[$key] = $it.FullName
            $bytes += $it.Length; $n++
        }
        if ($Required -and $n -eq 0) { throw "колёса: в '$base' ни одного файла - распаковка не состоялась" }
        $stats["vendor-$abi"] = [ordered]@{ files = $n; bytes = $bytes; archive = "kit\vendor\$abi" }
    }
    return [pscustomobject]@{ Files = $out; Stats = $stats }
}

function Get-RuntimePayload([string]$Root, [bool]$Required) {
    # Автономный интерпретатор едет в манифест ПОЛНЫМ деревом (ключи kit\runtime\python\...), а не
    # «копией папки сверх манифеста»: Get-Manifest остаётся единственным носителем списка файлов, и
    # иначе гейт 1 (дерево = манифест), гейт 5 (число записей в zip) и печать веса разошлись бы с
    # реальным архивом. Root - уже распакованное И очищенное (Remove-RuntimeBallast) дерево python/.
    # Балласт вырезается ДО раскладки: в дереве не остаётся ни .pyc, ни каталогов из $EXCLUDE_DIRS,
    # поэтому Get-KitFiles и проверка мусора в zip меряют то же дерево, что и манифест (замер носителя
    # после обрезки: 772 файла / 35 592 476 Б, из них .pyc 0, каталогов run/logs/__pycache__ 0).
    $out = [ordered]@{}
    $stats = [ordered]@{}
    if (-not $Root) {
        if ($Required) { throw "не задано дерево интерпретатора: автономный python в комплект не пойдёт, " +
                               "и на машине без Python веб-морда не поднимется" }
        return [pscustomobject]@{ Files = $out; Stats = $stats }
    }
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        if ($Required) { throw "нет каталога интерпретатора $Root - распаковка пина не состоялась" }
        return [pscustomobject]@{ Files = $out; Stats = $stats }
    }
    $bytes = [long]0; $n = 0
    foreach ($it in @(Get-ChildItem -LiteralPath $Root -File -Force -Recurse | Sort-Object -Property FullName)) {
        $rel = $it.FullName.Substring($Root.Length).TrimStart('\', '/').Replace('/', '\')
        $parts = @($rel -split '\\')
        if (@($parts[0..($parts.Count - 2)] | Where-Object { $_ -in $EXCLUDE_DIRS }).Count) { continue }
        if ($it.Extension -in $EXCLUDE_EXT) { continue }
        $key = $RUNTIME_DEST + "\" + $rel
        if ($out.Contains($key)) { throw "интерпретатор: дубликат пути в архиве - $key" }
        $out[$key] = $it.FullName
        $bytes += $it.Length; $n++
    }
    if ($Required -and $n -eq 0) { throw "интерпретатор: в '$Root' ни одного файла - распаковка не состоялась" }
    if ($Required -and -not $out.Contains($RUNTIME_DEST + "\python.exe")) {
        throw ("интерпретатор: в дереве нет python.exe ({0}) - пин {1} распаковался не тем боком" -f
               $RUNTIME_DEST, $PYTHON_ARCH_NAME)
    }
    $stats["runtime-$PYTHON_TARGET"] = [ordered]@{ files = $n; bytes = $bytes; archive = $RUNTIME_DEST }
    return [pscustomobject]@{ Files = $out; Stats = $stats }
}

function Get-VendorAbiPy([string]$Abi) {
    # cp311 -> 311: pip download принимает --python-version именно в такой форме.
    if ($Abi -notmatch '^cp(\d+)$') { throw "ABI '$Abi' не разворачивается в номер Python" }
    return $Matches[1]
}

function Install-VendorWheels([string]$Out, [string]$Py) {
    # Единственный разрешённый способ доставки чужих пакетов: pip download с PyPI, без зависимостей
    # и строго бинарный, в временный каталог, с распаковкой .whl в staging. Никаких токенов и
    # приватных репозиториев - публичный индекс, три имени, три версии.
    #
    # Почему --python-version/--platform/--implementation обязательны: раннер Windows-2022 крутит
    # СВОЙ CPython (на стенде замер 14.11 - 3.14), а комплектом будут пользоваться с 3.11 по 3.15.
    # Без этой тройки pip download притащил бы колесо под ABI раннера, и у пользователя на 3.11
    # веб-морда упала бы на «no module named regex._regex» - ровно та же молчаливая поломка,
    # что закрывается этим шагом, только с другой стороны.
    #
    # Отказ, а не урезанный архив: если PyPI недоступен или колесо не приехало, функция бросает -
    # прогон краснеет до упаковки.
    if (-not $Out) { throw "не задан -VendorOut - каталог распаковки колёс" }
    $leaf = [System.IO.Path]::GetFileName(($Out.TrimEnd('\', '/')))
    if ($leaf -notmatch '(?i)^(kit-)?vendor') {
        throw "-VendorOut '$Out': каталог обязан называться vendor* или kit-vendor* - удалять чужое я не буду"
    }
    if (-not $Py) {
        $cmd = Get-Command python -ErrorAction SilentlyContinue
        if (-not $cmd) { throw "python для pip download не найден в PATH - задайте -VendorPython <exe>" }
        $Py = $cmd.Source
    }
    if (-not (Test-Path -LiteralPath $Py -PathType Leaf)) { throw "нет интерпретатора -VendorPython: $Py" }
    Write-Host ("колёса: интерпретатор-загрузчик {0} ({1})" -f $Py, (& $Py -c "import sys;print('.'.join(map(str,sys.version_info[:3])))" 2>&1 | Out-String).Trim())
    if (Test-Path -LiteralPath $Out) { Remove-Item -LiteralPath $Out -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $Out | Out-Null
    $dlRoot = Join2 ([System.IO.Path]::GetTempPath()) ("kit-wheels-" +
                [Guid]::NewGuid().ToString("N").Substring(0, 8))
    New-Item -ItemType Directory -Force -Path $dlRoot | Out-Null
    $got = @()
    try {
        foreach ($abi in ($VENDOR_ABIS + @($VENDOR_PURE_ABI))) {
            $pkgs = @($VENDOR_PKGS | Where-Object {
                if ($abi -eq $VENDOR_PURE_ABI) { $_.abi -eq "pure" } else { $_.abi -eq "binary" } })
            $dest = Join2 $dlRoot $abi
            New-Item -ItemType Directory -Force -Path $dest | Out-Null
            $a = @("-m", "pip", "download", "--no-deps", "--only-binary=:all:",
                   "--disable-pip-version-check", "--no-input", "--progress-bar", "off", "-d", $dest)
            if ($abi -ne $VENDOR_PURE_ABI) {
                $a += @("--python-version", (Get-VendorAbiPy $abi),
                       "--platform", "win_amd64", "--implementation", "cp")
            }
            foreach ($p in $pkgs) { $a += ("{0}=={1}" -f $p.name, $p.version) }
            Write-Host ("колёса: pip download {0} -> {1}" -f (($pkgs | ForEach-Object { $_.name }) -join ","), $abi)
            & $Py @a 2>&1 | ForEach-Object { Write-Host "      $_" }
            if ($LASTEXITCODE -ne 0) {
                throw "колёса ABI ${abi}: pip download вернул rc=$LASTEXITCODE - комплект без них не пакуется"
            }
            $wheels = @(Get-ChildItem -LiteralPath $dest -File -Filter "*.whl")
            if ($wheels.Count -ne $pkgs.Count) {
                throw ("колёса {0}: скачано {1} файлов при {2} заказах - проверка не состоялась" -f
                       $abi, $wheels.Count, $pkgs.Count)
            }
            $dst = Join2 $Out $abi
            New-Item -ItemType Directory -Force -Path $dst | Out-Null
            foreach ($w in ($wheels | Sort-Object -Property Name)) {
                Write-Host ("      {0,-52} {1,9} Б" -f $w.Name, $w.Length)
                [System.IO.Compression.ZipFile]::ExtractToDirectory($w.FullName, $dst, $true)
                $got += [pscustomobject]@{ abi = $abi; file = $w.Name; bytes = [long]$w.Length }
            }
        }
    } finally {
        Remove-Item -LiteralPath $dlRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    return $got
}

function Get-PythonPinFromSource([string]$Path) {
    # Пин lives в packaging\package_terminal.py (PYTHON_PINS, :69-89). PowerShell не импортирует
    # python-модуль, поэтому блок нужного таргета читается текстом и сверяется поле за полем -
    # единственный способ не завести второй носитель дайджеста, который молча устареет.
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "нет носителя пина: $Path" }
    $t = [System.IO.File]::ReadAllText($Path)
    $pin = [ordered]@{ release = ""; version = ""; file = ""; sha256 = ""; exe = "" }
    if ($t -match '(?m)^PBS_RELEASE\s*=\s*"([^"]*)"') { $pin.release = $Matches[1] }
    if ($t -match '(?m)^PYTHON_VERSION\s*=\s*"([^"]*)"') { $pin.version = $Matches[1] }
    if ($t -match ('(?ms)"' + [regex]::Escape($PYTHON_TARGET) + '":\s*\{(?<b>.*?)^\s*\},')) {
        $b = $Matches['b']
        if ($b -match '"file":\s*f?"(?<v>[^"]*)"') { $pin.file = $Matches['v'] }
        if ($b -match '"sha256":\s*"(?<v>[0-9a-fA-F]{64})"') { $pin.sha256 = $Matches['v'] }
        if ($b -match '"python":\s*"(?<v>[^"]*)"') { $pin.exe = $Matches['v'] }
    }
    foreach ($k in @($pin.Keys)) {
        if (-not $pin[$k]) { throw "пин в $Path не разобран: поле '$k' не найдено - проверка не состоялась" }
    }
    return $pin
}

function Get-PythonPinDiff([string]$Path) {
    # Расхождения пустой = упаковщик и первоисточник называют один и тот же носитель. Имя архива
    # сверяется не строкой, а подстановкой: в первоисточнике оно f-строкой собрано из PBS_RELEASE и
    # PYTHON_VERSION, и подстановка проверяет заодно форму хвоста имени.
    $pin = Get-PythonPinFromSource $Path
    $d = @()
    if ($pin.release -ne $PBS_RELEASE) { $d += ("PBS_RELEASE: первоисточник '{0}', упаковщик '{1}'" -f $pin.release, $PBS_RELEASE) }
    if ($pin.version -ne $PYTHON_VERSION) { $d += ("PYTHON_VERSION: первоисточник '{0}', упаковщик '{1}'" -f $pin.version, $PYTHON_VERSION) }
    if ($pin.sha256.ToLowerInvariant() -ne $PYTHON_ARCH_SHA256) {
        $d += ("sha256: первоисточник '{0}', упаковщик '{1}'" -f $pin.sha256, $PYTHON_ARCH_SHA256)
    }
    if ($pin.exe.Replace('/', '\') -ne $PYTHON_ARCH_EXE.Replace('/', '\')) {
        $d += ("путь exe: первоисточник '{0}', упаковщик '{1}'" -f $pin.exe, $PYTHON_ARCH_EXE)
    }
    $want = $pin.file.Replace('{PYTHON_VERSION}', $pin.version).Replace('{PBS_RELEASE}', $pin.release)
    if ($want -ne $PYTHON_ARCH_NAME) { $d += ("имя архива: первоисточник '{0}', упаковщик '{1}'" -f $want, $PYTHON_ARCH_NAME) }
    return [pscustomobject]@{ Pin = $pin; Diff = @($d) }
}

function Get-PythonCacheDir([string]$Override) {
    # package_terminal.py:382 - tempfile.gettempdir()/strata-packaging-cache. Override нужен CI-кэшу
    # (actions/cache кладёт в своё имя) и офлайн-перепаковке; форма имени проверяется, потому что
    # каталог later чистится и писать в чужой я не буду.
    if (-not $Override) { return Join2 ([System.IO.Path]::GetTempPath()) $PYTHON_CACHE_DIRNAME }
    $leaf = [System.IO.Path]::GetFileName($Override.TrimEnd('\', '/'))
    if ($leaf -notmatch '(?i)^strata-packaging-cache') {
        throw "-RuntimeCache '$Override': каталог обязан называться strata-packaging-cache* - удалять чужое я не буду"
    }
    return $Override
}

function Test-RuntimeOwn([string]$Dir) {
    # Под деревом интерпретатора стоит Remove-Item -Recurse -Force, поэтому признак «это наше»
    # читается по расположению: распаковать и резать можно только в temp. То же условие, что у
    # Test-StageOwn, но для другой папки - и с той же причиной: опечатка в аргументе не имеет права
    # снести чужое дерево.
    $full = try { [System.IO.Path]::GetFullPath($Dir).TrimEnd('\', '/') } catch { "" }
    if (-not $full) { return "дерево интерпретатора ($Dir) не сворачивается в полный путь" }
    $tmp = try { [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\', '/') } catch { "" }
    if (-not $tmp) { return "temp-каталог не определён - проверка не состоялась" }
    if (-not $full.StartsWith($tmp + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        return "дерево '$full' лежит вне temp-каталога '$tmp' - резать чужое я не буду"
    }
    return ""
}

function Get-RuntimeTrimPlan([string]$Dir) {
    # Список вырезания - числами, а не словами: план пересчитывается по фактическому дереву, и ровно
    # эти корзины (каталоги, точечные файлы, расширения, глобы) дают сумму из комментария у
    # $RUNTIME_CUT_*. Возвращает Paths - относительные пути файлов, которые будут удалены.
    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { throw "нет дерева интерпретатора $Dir" }
    $plan = [ordered]@{}
    # Корзины считаются тем же проходом, что и план: таблица в комментарии у $RUNTIME_CUT_* -
    # это замер прогона, а не отдельная мера, которая может разойтись с фактической обрезкой.
    $baskets = [ordered]@{}
    foreach ($it in @(Get-ChildItem -LiteralPath $Dir -File -Force -Recurse)) {
        $rel = $it.FullName.Substring($Dir.Length).TrimStart('\', '/').Replace('/', '\')
        $segs = @($rel -split '\\')
        $dirs = @($segs[0..($segs.Count - 2)])
        $hit = ""
        # Корзины каталогов сравниваются с ПУТЁМ: "Lib\venv" - это два сегмента, и проверка
        # `$dirs -contains $d` никогда не совпадала. Замер 14.11: Lib\venv, tkinter, idlelib,
        # lib2to3, turtledemo и ensurepip оставались в комплекте (215 файлов / 4 265 249 Б).
        foreach ($d in $RUNTIME_CUT_DIRS) { if ($rel -like "$d\*") { $hit = $d; break } }
        if (-not $hit) { foreach ($d in $RUNTIME_CUT_ANY) { if ($dirs -contains $d) { $hit = "$d (везде)"; break } } }
        if (-not $hit) { foreach ($g in $RUNTIME_CUT_GLOBS) { if ($rel -like $g) { $hit = $g; break } } }
        if (-not $hit) { foreach ($f in $RUNTIME_CUT_FILES) { if ($rel -eq $f) { $hit = $f; break } } }
        if (-not $hit) { foreach ($e in $RUNTIME_CUT_EXT) { if ($it.Extension -eq $e) { $hit = "*$e"; break } } }
        if ($hit) {
            $plan[$rel] = $it.Length
            if (-not $baskets.Contains($hit)) { $baskets[$hit] = [pscustomobject]@{ Files = 0; Bytes = [long]0 } }
            $baskets[$hit].Files++
            $baskets[$hit].Bytes += $it.Length
        }
    }
    return [pscustomobject]@{ Paths = @($plan.Keys); Files = $plan.Count
                              Bytes = [long](@($plan.Values) | Measure-Object -Sum).Sum
                              Baskets = $baskets }
}

function Remove-RuntimeBallast([string]$Dir) {
    # Обрезка применяется ТОЛЬКО к дереву, распакованному нами (Test-RuntimeOwn), и отвергается до
    # первого удаления, если план хоть одним путём задел обязательный файл: «подрезали балласт» и
    # «подрезали stdlib» должны быть разными исходами, а не одним молчаливым.
    $own = Test-RuntimeOwn $Dir
    if ($own) { throw "обрезка интерпретатора: $own" }
    $plan = Get-RuntimeTrimPlan $Dir
    $clash = @($plan.Paths | Where-Object { $_ -in $RUNTIME_KEEP })
    if ($clash) {
        throw ("обрезка задела обязательный файл ({0}) - план отвергнут, дерево не трогаем" -f ($clash -join ', '))
    }
    $keepNow = @($RUNTIME_KEEP | Where-Object { Test-Path -LiteralPath (Join2 $Dir $_) -PathType Leaf })
    $before = @(Get-ChildItem -LiteralPath $Dir -File -Force -Recurse)
    $bytesBefore = [long](@($before | ForEach-Object { $_.Length }) | Measure-Object -Sum).Sum
    foreach ($rel in $plan.Paths) {
        $p = Join2 $Dir $rel
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
    }
    # Опустевшие каталоги вырезанных деревьев (включая __pycache__) обязаны исчезнуть: манифест
    # строится по файлам, но пустой каталог всё равно уехал бы в zip отдельной записью.
    foreach ($d in @(Get-ChildItem -LiteralPath $Dir -Directory -Force -Recurse |
                     Sort-Object { $_.FullName.Length } -Descending)) {
        if (-not @(Get-ChildItem -LiteralPath $d.FullName -File -Force -Recurse).Count) {
            Remove-Item -LiteralPath $d.FullName -Recurse -Force
        }
    }
    $gone = @($keepNow | Where-Object { -not (Test-Path -LiteralPath (Join2 $Dir $_) -PathType Leaf) })
    if ($gone) { throw "обрезка убрала обязательные файлы ({0}) - дерево непригодно" -f ($gone -join ', ') }
    $after = @(Get-ChildItem -LiteralPath $Dir -File -Force -Recurse)
    $bytesAfter = [long](@($after | ForEach-Object { $_.Length }) | Measure-Object -Sum).Sum
    return [pscustomobject]@{ cutFiles = $plan.Files; cutBytes = $plan.Bytes; keptFiles = $after.Count
                              keptBytes = $bytesAfter; allFiles = $before.Count; allBytes = $bytesBefore
                              Baskets = $plan.Baskets }
}

function Request-PythonArchive([string]$Cache) {
    # Повтор fetch_python (package_terminal.py:163-178) без сетевой работы, если носитель уже в кэше:
    # имя в кэше - то же имя с '+' -> '_' (:166), скачивание - в .part и переименование (:169-171),
    # несовпадение дайджеста - отказ с удалением файла (:172-177), иначе следующий прогон так же
    # краснеет на испорченном кэше без всякой причины.
    if (-not (Test-Path -LiteralPath $Cache -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $Cache | Out-Null
    }
    $arch = Join2 $Cache $PYTHON_ARCH_CACHED
    if (-not (Test-Path -LiteralPath $arch -PathType Leaf)) {
        $url = $PBS_URL_BASE + $PYTHON_ARCH_NAME.Replace("+", "%2B")
        Write-Host ("интерпретатор: скачиваю {0}" -f $url)
        $part = $arch + ".part"
        try {
            Invoke-WebRequest -Uri $url -OutFile $part -UseBasicParsing
        } catch {
            Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue
            throw "интерпретатор: скачивание не удалось ({0}) - пин {1}" -f $_.Exception.Message, $PYTHON_ARCH_NAME
        }
        Move-Item -LiteralPath $part -Destination $arch -Force
    }
    $got = (Get-FileHash -LiteralPath $arch -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($got -ne $PYTHON_ARCH_SHA256) {
        Remove-Item -LiteralPath $arch -Force -ErrorAction SilentlyContinue
        # Скобки вокруг склейки обязательны: без них -f привязывается только к последней строке,
        # и номер хеша в отказе остаётся литералом {0}/{1}.
        throw (("интерпретатор: носитель не совпал с пином; ожидалось {0}, получено {1} - паковка " +
                "непроверенного интерпретатора невозможна") -f $PYTHON_ARCH_SHA256, $got)
    }
    return [pscustomobject]@{ Path = $arch; Bytes = (Get-Item -LiteralPath $arch).Length; Sha256 = $got }
}

function Resolve-Bsdtar {
    # Тот же класс дефекта, что ловит verify_zip.sh для сборки архива: под PATH с Git for Windows
    # `Get-Command tar` первым даёт GNU tar 1.35 (C:\Program Files\Git\usr\bin\tar.exe). Он не
    # разбирает windows-путь носителя ("e:\Temp\..." читается как хост e:) и падает с rc=2, а
    # отказ выглядит как «битый архив», хотя архив проходит SHA-256-пин. Мерка - строка версии,
    # а не имя каталога: путь может быть и перенесён.
    $cands = @((Join-Path $env:SystemRoot 'System32\tar.exe'))
    $cands += @(Get-Command tar -ErrorAction SilentlyContinue | ForEach-Object { $_.Source })
    $seen = @{}
    $tried = @()
    foreach ($c in $cands) {
        if (-not $c -or $seen[$c.ToLowerInvariant()]) { continue }
        $seen[$c.ToLowerInvariant()] = $true
        if (-not (Test-Path -LiteralPath $c -PathType Leaf)) { $tried += "$c (нет файла)"; continue }
        $ver = (& $c --version 2>&1 | Out-String)
        $first = (($ver -split "`r?`n") | Where-Object { $_ } | Select-Object -First 1)
        if ($first -match 'bsdtar') {
            return [pscustomobject]@{ Source = $c; Version = $first.Trim() }
        }
        $tried += "$c ([$first])"
    }
    throw ("нет bsdtar для распаковки: перебрано {0} - распаковка не состоялась" -f ($tried -join ' | '))
}

function Install-PythonRuntime([string]$Cache, [string]$Work) {
    # Полная цепочка носителя: проверка дайджеста -> распаковка -> обрезка. Распаковщик - внешний
    # bsdtar (то же содержимое, что читает tarfile в package_terminal.py:392-393); отсутствие утилиты -
    # отказ по имени, а не «архив без питона». $Work обязан лежать в temp: под ним Remove-Item.
    $arch = Request-PythonArchive $Cache
    $tar = Resolve-Bsdtar
    Write-Host ("интерпретатор: распаковщик {0}" -f $tar.Version)
    $own = Test-RuntimeOwn $Work
    if ($own) { throw "распаковка интерпретатора: $own" }
    if (Test-Path -LiteralPath $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $Work | Out-Null
    Write-Host ("интерпретатор: распаковываю {0} -> {1}" -f $arch.Path, $Work)
    & $tar.Source -xzf $arch.Path -C $Work 2>&1 | ForEach-Object { Write-Host "      $_" }
    if ($LASTEXITCODE -ne 0) { throw "интерпретатор: tar вернул rc=$LASTEXITCODE - распаковка не состоялась" }
    $py = Join2 $Work "python"
    if (-not (Test-Path -LiteralPath (Join2 $py "python.exe") -PathType Leaf)) {
        throw "интерпретатор: после распаковки нет python/python.exe - пин свёрнут не в ту сторону"
    }
    $trim = Remove-RuntimeBallast $py
    # Путь вендора пишется ДО манифеста: и ._pth, и сайдкар .pth входят в дерево интерпретатора, и их
    # размер обязан попасть в вес архива и в число записей, а не измениться после раскладки. ABI
    # берётся у самого распакованного exe - строка вендора пишется под тот интерпретатор, который
    # едет в архив.
    $abi = Get-PythonAbi (Join2 $py "python.exe")
    $res = Set-VendorResolution $py $abi.Abi
    return [pscustomobject]@{ Root = $py; Archive = $arch; Trim = $trim; Abi = $abi
                              Pth = $res.Pth; Site = $res.Site; Mode = $res.Mode }
}

function Get-PythonAbi([string]$Exe) {
    # ABI берётся У самого интерпретатора, а не из константы: каталоги вендора раскладываются как
    # kit\vendor\cp311..cp315, и start.ps1 выбирает из них по версии своего python. Контроль обязан
    # строить путь по тому же контракту, поэтому ряд проверяется по факту, а вне ряда - отказ.
    if (-not (Test-Path -LiteralPath $Exe -PathType Leaf)) { throw "нет интерпретатора $Exe - проверка не состоялась" }
    # -B здесь не косметика: этот запрос идёт ПО ПРОБАМ и по тому же дереву runtime. Зонд
    # glm\scripts\kit461_pyc_probe_2026-11-14.ps1 на интерпретаторе из собранного комплекта:
    # без флага старт пишет 4 файла в Lib\encodings\__pycache__ (__init__, aliases, cp1251, utf_8 -
    # модули инициализации кодировки), с -B - ноль. Именно эти четыре файла и уронили гейт
    # «мусор в архиве» в прогоне 14.11: 1147 записей zip при манифесте 1143.
    $v = (& $Exe -B -c "import sys;print('.'.join(map(str,sys.version_info[:3])))" 2>&1 | Out-String).Trim()
    if ($v -notmatch '^(\d+)\.(\d+)') { throw "интерпретатор не сообщает версию ($v) - ABI взять неоткуда" }
    $abi = "cp{0}{1}" -f $Matches[1], $Matches[2]
    if ($abi -notin $VENDOR_ABIS) {
        throw (("интерпретатор {0} даёт ABI {1} вне ряда колёс комплекта ({2}) - regex/markupsafe под " +
                "него не распакованы") -f $v, $abi, ($VENDOR_ABIS -join ','))
    }
    return [pscustomobject]@{ Version = $v; Abi = $abi }
}

function Join-VendorPythonPath([string]$KitDir, [string]$Abi) {
    # Контракт PYTHONPATH комплекта (тот же, по которому раскладываются колёса в Get-VendorPayload и
    # по которому start.ps1 обязан его собирать): kit\vendor\<abi под фактический интерпретатор И
    # kit\vendor\py3-none-any. Без второго сегмента не находится jinja2 (pure), без первого -
    # regex._regex (pyd под конкретный ABI), и морда падает одинаково молча.
    if (-not $KitDir) { throw "не задан каталог комплекта - PYTHONPATH собирать не из чего" }
    if ($Abi -notin $VENDOR_ABIS) {
        throw ("ABI '{0}' вне ряда колёс ({1}) - путь строится по другому контракту" -f
               $Abi, ($VENDOR_ABIS -join ','))
    }
    return (@((Join2 $KitDir ("vendor\" + $Abi)), (Join2 $KitDir ("vendor\" + $VENDOR_PURE_ABI))) -join ';')
}

function Get-RelPathFrom([string]$From, [string]$To) {
    # Относительные пути в ._pth и в файле .pth из site-packages разрешаются ОТ КАТАЛОГА ФАЙЛА,
    # а не от cwd процесса: для ._pth это каталог python.exe (измерено прогоном
    # glm\scripts\kit415_pth_mechanism_2026-11-14.ps1: «..\..\vendor\py3-none-any» импортирует
    # вендор, а верная переменная окружения при ._pth игнорируется молча), для сайдкара - сам
    # Lib\site-packages (glm\scripts\kit469_pth_depth.ps1: import regex/jinja2/markupsafe зелёный
    # ровно на «..\..\..\..\vendor\...»). Поэтому путь вендора обязан быть относительным.
    # Считается по АРХИВНОЙ раскладке ($RUNTIME_DEST и kit\vendor\...), а не по дисковым путям:
    # в temp дерево распаковано иначе, чем лежит в архиве, а договор именно про архив.
    foreach ($p in @($From, $To)) {
        if (-not $p) { throw "относительный путь строится из двух ненулевых путей, получен пустой" }
        if ($p -match '^[a-zA-Z]:' -or $p.StartsWith([string][char]92) -or $p.StartsWith('/')) {
            throw (("путь '{0}' корневой: в ._pth пишутся относительные архивные пути, " +
                    "дисковый путь сборки в архиве неработоспособен") -f $p)
        }
    }
    $f = @(($From -split '[\\/]') | Where-Object { $_ -and $_ -ne '.' })
    $t = @(($To -split '[\\/]') | Where-Object { $_ -and $_ -ne '.' })
    $i = 0
    while ($i -lt $f.Count -and $i -lt $t.Count -and
           $f[$i].ToLowerInvariant() -eq $t[$i].ToLowerInvariant()) { $i++ }
    $parts = @()
    # Уровень «..» добавляется циклом, а не `@('..') * n`: при `$parts += , @('..') * n` умножение
    # повторяет вложенный массив, а не элементы, и -join печатает System.Object[] вместо пути.
    for ($k = $i; $k -lt $f.Count; $k++) { $parts += '..' }
    if ($i -lt $t.Count) { $parts += $t[$i..($t.Count - 1)] }
    if (-not $parts.Count) { return "." }
    return ($parts -join '\')
}

function Get-PthFiles([string]$Dir) {
    # ._pth живёт ровно рядом с python.exe (имя вида python312._pth): поиск НЕ рекурсивный, иначе
    # вложенный чужой файл свёрнул бы sys.path у другого интерпретатора и отказ был бы ложным.
    if (-not $Dir) { throw "не задан каталог интерпретатора - файла ._pth не искать вовсе" }
    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) {
        throw "нет каталога интерпретатора '$Dir' - файла ._pth не искать вовсе"
    }
    return @(Get-ChildItem -LiteralPath $Dir -File -Force |
             Where-Object { $_.Name -like '*._pth' })
}

function Add-VendorToPth([string]$PyDir, [string]$Abi) {
    # Механизм измерен, а не угадан (glm\scripts\kit415_pth_mechanism_2026-11-14.ps1, семь прогонов):
    # пока рядом с python.exe нет ._pth, вендор доходит ИСКЛЮЧИТЕЛЬНО через PYTHONPATH; как только
    # файл появляется, sys.path сворачивается в его строки (isolated=1, import site=0), верная
    # переменная окружения игнорируется МОЛЧА, а stdlib и нативные модули живут. Значит на упаковке
    # путь вендора обязан быть дописан в сам ._pth относительно каталога python.exe.
    # Файлов НОЛЬ (install_only-носитель этого пина: 3384 записей архива, из них ._pth 0) - это не
    # отказ, но и НЕ «PYTHONPATH законен»: вызывающий обязан передать дерево в Add-VendorToSitePth
    # (Set-VendorResolution), иначе на чужой машине морда падёт на «no module named jinja2».
    $files = @(Get-PthFiles $PyDir)
    if (-not $files.Count) {
        return [pscustomobject]@{ Found = 0; Files = @(); Added = @(); Lines = 0 }
    }
    if ($Abi -notin $VENDOR_ABIS) {
        throw ("ABI '{0}' вне ряда колёс ({1}) - строку в ._pth писать не из чего" -f
               $Abi, ($VENDOR_ABIS -join ','))
    }
    $want = @((Get-RelPathFrom $RUNTIME_DEST ("kit\vendor\" + $Abi)),
              (Get-RelPathFrom $RUNTIME_DEST ("kit\vendor\" + $VENDOR_PURE_ABI)))
    $addedAll = @(); $names = @()
    foreach ($f in $files) {
        $names += $f.Name
        $raw = [System.IO.File]::ReadAllText($f.FullName)
        $nl = if ($raw.Contains("`r`n")) { "`r`n" } else { "`n" }
        $lines = @(($raw -split "`r?`n") | Where-Object { $_.Trim() -ne '' })
        # ._pth без строки, по которой находится Lib\encodings, роняет интерпретатор ДО всякого
        # вендора: «Fatal Python error: init_fs_encoding ... No module named 'encodings'» - это
        # измерено прогоном kit416 на embeddable-каноне без строки Lib. Править такой файл нельзя:
        # иначе красный архив получит пользователь, а не сборка.
        $std = @($lines | Where-Object { -not $_.StartsWith('#') } |
                 Where-Object {
                     Test-Path -LiteralPath (Join2 (Join2 $PyDir $_.Trim()) "encodings\__init__.py") -PathType Leaf
                 })
        if (-not $std.Count) {
            throw (("в {0} нет ни одной строки, по которой находится Lib\encodings: дописывать вендор " +
                    "в такой ._pth - значит собрать архив, падающий на init_fs_encoding") -f $f.Name)
        }
        $have = @($lines | ForEach-Object { $_.Trim().Replace('/', '\') })
        $need = @($want | Where-Object { $_ -notin $have })
        if ($need.Count) {
            # Запись без BOM: BOM попал бы в первую строку как часть пути, а ._pth читается
            # интерпретатором до всякого кодирования. Идемпотентность держится на $need - повторный
            # прогон ничего не дописывает и файл не растёт.
            $txt = (($lines + $need) -join $nl) + $nl
            [System.IO.File]::WriteAllText($f.FullName, $txt, (New-Object System.Text.UTF8Encoding($false)))
            $addedAll += $need
        }
    }
    return [pscustomobject]@{ Found = $files.Count; Files = $names; Added = $addedAll
                              Lines = @(([System.IO.File]::ReadAllText((Join2 $PyDir $names[0])) -split "`r?`n") |
                                         Where-Object { $_.Trim() -ne '' }).Count }
}

function Add-VendorToSitePth([string]$PyDir, [string]$Abi) {
    # Ветка «._pth рядом с python.exe нет» - ровно то, что даёт живой install_only-пин. Механизм
    # измерен, а не угадан: glm\scripts\kit469_pth_depth.ps1 по дереву СОБРАННОГО комплекта
    # (C:\tmp\kit464\unpacked\kit, PYTHONPATH снят, -B) перебирает глубину 'N..\vendor\...' в файле
    # .pth внутри Lib\site-packages - import regex/jinja2/markupsafe даёт rc=0 ТОЛЬКО на четырёх
    # уровнях вверх (kit\runtime\python\Lib\site-packages -> kit\vendor), на 2/3/5 прогон красный.
    # Выборка красная именно потому, что site молча пропускает несуществующий путь: поэтому мерка
    # печатала разрешившиеся пути и список импортов, а не один rc - иначе «зелёно» означало бы «ничего
    # не проверили». Файл пишется ДО манифеста: он входит в дерево интерпретатора и обязан попасть
    # в вес архива и в число записей, а не измениться после раскладки.
    $site = Join2 $PyDir $VENDOR_SITE_DIR
    if (-not (Test-Path -LiteralPath $site -PathType Container)) {
        throw (("нет каталога {0} в дереве интерпретатора - сайдкар .pth писать некуда, а ._pth нет: " +
                "вендор дошёл бы только переменной PYTHONPATH, которую на чужой машине никто не " +
                "обязан был ставить") -f $VENDOR_SITE_DIR)
    }
    if ($Abi -notin $VENDOR_ABIS) {
        throw ("ABI '{0}' вне ряда колёс ({1}) - строку в .pth писать не из чего" -f
               $Abi, ($VENDOR_ABIS -join ','))
    }
    # Пути считаются от архивного каталога самого файла, а не от каталога python.exe: это тот же
    # договор, что у ._pth (разрешение от каталога файла), но файл лежит на два уровня глубже.
    $from = Join2 $RUNTIME_DEST $VENDOR_SITE_DIR
    $want = @((Get-RelPathFrom $from ("kit\vendor\" + $Abi)),
              (Get-RelPathFrom $from ("kit\vendor\" + $VENDOR_PURE_ABI)))
    $f = Join2 $site $VENDOR_SITE_PTH
    $added = @($want); $created = $true
    $nl = "`r`n"
    if (Test-Path -LiteralPath $f -PathType Leaf) {
        # Повторный прогон по тому же дереву: дописываем только недостающее, файл не растёт.
        $raw = [System.IO.File]::ReadAllText($f)
        if ($raw.Contains("`r`n")) { $nl = "`r`n" } else { $nl = "`n" }
        $lines = @(($raw -split "`r?`n") | Where-Object { $_.Trim() -ne '' })
        $have = @($lines | ForEach-Object { $_.Trim().Replace('/', '\') })
        $added = @($want | Where-Object { $_ -notin $have })
        $created = $false
        if ($added.Count) {
            $lines = $lines + $added
            [System.IO.File]::WriteAllText($f, (($lines -join $nl) + $nl),
                                           (New-Object System.Text.UTF8Encoding($false)))
        }
    } else {
        # Без BOM: первая строка .pth читается как путь, и BOM уехал бы в начало первого сегмента.
        [System.IO.File]::WriteAllText($f, (($want -join $nl) + $nl),
                                       (New-Object System.Text.UTF8Encoding($false)))
    }
    $n = @(([System.IO.File]::ReadAllText($f) -split "`r?`n") | Where-Object { $_.Trim() -ne '' }).Count
    return [pscustomobject]@{ Path = $f; Rel = ($VENDOR_SITE_DIR + '\' + $VENDOR_SITE_PTH)
                              Lines = $n; Added = $added; Created = $created }
}

function Set-VendorResolution([string]$PyDir, [string]$Abi) {
    # Механизм выбирается по факту дерева, а не по догадке, и два варианта взаимоисключающи: ._pth
    # включает изоляцию (import site=0), поэтому сайдкар в site-packages в том же дереве мёртв; без
    # ._pth сайт работает, а переменная окружения остаётся лишь милостью того, кто запускал процесс.
    # В обоих случаях итог один - sys.path интерпретатора из архива содержит kit\vendor\<abi> и
    # kit\vendor\py3-none-any, и именно это проверяет гейт Invoke-RuntimeProbe -UseEnv:$false.
    $files = @(Get-PthFiles $PyDir)
    if ($files.Count) {
        $r = Add-VendorToPth $PyDir $Abi
        return [pscustomobject]@{ Mode = "._pth"; Pth = $r; Site = $null; Names = @($r.Files) }
    }
    $s = Add-VendorToSitePth $PyDir $Abi
    return [pscustomobject]@{ Mode = "site-packages"; Pth = $null; Site = $s; Names = @($s.Rel) }
}

function Invoke-RuntimeProbe([string]$Exe, [string]$KitDir, [bool]$UseEnv = $true) {
    # Доказательство, а не слова: запускается ровно тот exe, который уедет в архив, с PYTHONPATH по
    # контракту start.ps1, и требуются импорты, без которых веб-морда не поднимается
    # (serve/frontend.py:28-29 jinja2, tools/strata_tokenizer.py:24 regex).
    # Третий вход - $UseEnv: прогон БЕЗ переменной меряет обратное - что вендор доходит по строкам
    # ._pth, когда такой файл в дереве есть. Прежняя одновходовая мера не различала эти два случая:
    # зелёный rc при ._pth означал бы «вендор подхватился переменной», которую на машине
    # пользователя интерпретатор никогда не прочитает.
    $abi = Get-PythonAbi $Exe
    $pp = Join-VendorPythonPath $KitDir $abi.Abi
    $old = $env:PYTHONPATH
    $rc = -1; $out = ""
    try {
        if ($UseEnv) { $env:PYTHONPATH = $pp }
        else { Remove-Item -LiteralPath 'Env:PYTHONPATH' -ErrorAction SilentlyContinue }
        # -B обязателен: пробы идут по уже собранному дереву stage, и импорт вендора/stdlib до
        # подсчёта записей писал бы __pycache__ внутрь дерева - гейты «мусор в архиве» и сверка
        # числа записей с манифестом краснели бы по вине самого упаковщика (замер 14.11: 1334
        # записи при манифесте 1143, ~190 файлов кэша от собственных проб).
        $out = (& $Exe -B -c ("import {0}" -f $RUNTIME_VENDOR_IMPORTS) 2>&1 | Out-String).Trim()
        $rc = $LASTEXITCODE
    } finally {
        if ($null -eq $old) { Remove-Item -LiteralPath 'Env:PYTHONPATH' -ErrorAction SilentlyContinue }
        else { $env:PYTHONPATH = $old }
    }
    return [pscustomobject]@{ Abi = $abi.Abi; Version = $abi.Version; Path = $pp; Rc = $rc
                              Out = $out; Env = $UseEnv }
}

function Invoke-RuntimeSmoke([string]$Exe) {
    # Второй срез того же риска: обрезка не должна задеть stdlib-замыкание самого сервера. Список
    # имён снят AST-разбором замыкания (71 модуль), POSIX-only исключены - на Windows они не
    # импортируются ни до, ни после обрезки.
    # Тот же риск, что и в Invoke-RuntimeProbe: stdlib-набор импортируется по уже собранному дереву
    # stage, и без -B каждая проба оставляла бы внутри него __pycache__ - гейт «мусор в архиве» и
    # сверка числа записей с манифестом краснели бы по вине самого упаковщика.
    $out = (& $Exe -B -c ("import {0}" -f $RUNTIME_SMOKE) 2>&1 | Out-String).Trim()
    return [pscustomobject]@{ Rc = $LASTEXITCODE; Out = $out; Modules = @($RUNTIME_SMOKE -split ',').Count }
}

function Test-KitRuntimePresence($Paths) {
    # Гейт 7, лицо в одну сторону: в архиве обязан появиться сам exe. Возвращает список строк
    # «путь - причина» для отсутствующих, как Test-KitWebPresence.
    $have = @($Paths)
    $missing = @()
    foreach ($p in $RUNTIME_PRESENCE) {
        if ($have -notcontains $p.path) { $missing += ("{0} - {1}" -f $p.path, $p.why) }
    }
    return @($missing)
}

function Test-KitWebPresence($Paths, [bool]$WithVendor) {
    # Гейт 4b. Вход - коллекция архивных путей (ключи манифеста либо имена записей zip, уже
    # переведённые в обратные слеши). Возвращает список строк «путь - причина» для всего, чего нет.
    $have = @($Paths)
    $missing = @()
    foreach ($p in $KIT_PRESENCE) {
        if ($have -notcontains $p.path) { $missing += ("{0} - {1}" -f $p.path, $p.why) }
    }
    if ($WithVendor) {
        foreach ($abi in $VENDOR_ABIS) {
            foreach ($pkg in @($VENDOR_PKGS | Where-Object { $_.abi -eq "binary" } | ForEach-Object { $_.name })) {
                $pre = "kit\vendor\$abi\$pkg\"
                if (@($have | Where-Object { $_.StartsWith($pre, [StringComparison]::OrdinalIgnoreCase) }).Count -eq 0) {
                    $missing += ("{0} - колесо {1} для ABI {2} не распаковано ({3})" -f $pre, $pkg, $abi,
                                 (@($VENDOR_PKGS | Where-Object { $_.name -eq $pkg }).why))
                }
            }
        }
        foreach ($pkg in @($VENDOR_PKGS | Where-Object { $_.abi -eq "pure" } | ForEach-Object { $_.name })) {
            $pre = "kit\vendor\$VENDOR_PURE_ABI\$pkg\"
            if (@($have | Where-Object { $_.StartsWith($pre, [StringComparison]::OrdinalIgnoreCase) }).Count -eq 0) {
                $missing += ("{0} - pure-колесо {1} не распаковано ({2})" -f $pre, $pkg,
                             (@($VENDOR_PKGS | Where-Object { $_.name -eq $pkg }).why))
            }
        }
    }
    # Без ведущей запятой: `return ,@(...)` отдаёт список ОДНИМ элементом, и вызывающий с @(...)
    # получает .Count = 1 при любом содержимом (измерено: 0 отсутствий -> 1, 2 -> 1) - все меры
    # «отсутствий ровно N» на такой форме превращаются в константу.
    return @($missing)
}

function Split-StandPathHits($Hits, $Waivers) {
    # Ослаблением гейта переносимости это не является: отпускается ровно названное число находок в
    # ровно названном файле. На одну находку больше (или меньше - значит, список устарел) - красным.
    $kept = @(); $drift = @(); $waived = @()
    $byFile = @{}
    foreach ($h in @($Hits)) {
        $rel = ([string]$h -split ": ")[0]
        if (-not $byFile.ContainsKey($rel)) { $byFile[$rel] = @() }
        $byFile[$rel] += $h
    }
    foreach ($rel in @($byFile.Keys)) {
        $list = @($byFile[$rel])
        if ($Waivers -and $Waivers.Contains($rel) -and $list.Count -eq [int]$Waivers[$rel].hits) {
            $waived += ("{0} x{1} ({2})" -f $rel, $list.Count, $Waivers[$rel].why)
            continue
        }
        if ($Waivers -and $Waivers.Contains($rel)) {
            $drift += (("{0}: находок {1}, отпущено {2} - в файле изменилось число путей с литерой " +
                        "диска, отпуск устарел ({3})") -f $rel, $list.Count, [int]$Waivers[$rel].hits,
                       $Waivers[$rel].why)
            continue
        }
        $kept += $list
    }
    # Отпуск, который ни разу не сработал, - это устаревший список: файл вычистили или переименовали,
    # а разрешение осталось, и следующее вхождение литеры в файл с таким же именем пройдёт молча.
    $unused = @()
    if ($Waivers) {
        foreach ($w in @($Waivers.Keys)) {
            if (-not $byFile.ContainsKey($w)) {
                $unused += ("{0}: отпуск x{1} не использован ни разу - список устарел ({2})" -f `
                           $w, [int]$Waivers[$w].hits, $Waivers[$w].why)
            }
        }
    }
    return [pscustomobject]@{ Kept = @($kept); Drift = @($drift); Waived = @($waived); Unused = $unused }
}

function Test-KitSourceTexts([string]$Src, [string]$Repo = "") {
    # Ранняя версия гейта 2: текстовые файлы комплекта меряются до компиляции, по дереву исходников.
    # Перечень берётся из Get-Manifest - вторая копия списка файлов это ровно тот класс дефекта,
    # что закрывали для ARTIFACT_FILES в сборках по требованию. ci\ в тот перечень не входит, поэтому
    # законные пути раннера в CI-скриптах гейт не красит.
    if (-not (Test-Path -LiteralPath $Src)) { throw "нет каталога -KitSrc: $Src" }
    $m = Get-Manifest -StrataBuild "_" -LlamaBuild "_" -KitSrc $Src -Measures "_" -Cuda "_" `
                      -WithCudaRuntime $false -RepoSrc $Repo -VendorStage ""
    $prefixes = @($Src.TrimEnd('\', '/'))
    if ($Repo) { $prefixes += $Repo.TrimEnd('\', '/') }
    # Манифест отдаёт АБСОЛЮТНЫЕ пути, а в CI -KitSrc/-RepoSrc относительные ("strata\packaging\kit",
    # "strata"): без разворота ни один вход не сопоставлялся, и вместо сотни файлов мерилось 9 -
    # а отпуска пути стенда оставались неиспользованными (прогон 15).
    $prefixes = @($prefixes | ForEach-Object {
        if ($_ -and (Test-Path -LiteralPath $_ -PathType Container)) { (Get-Item -LiteralPath $_).FullName }
        else { $_ }
    })
    # Разделители нормализуются с обеих сторон: манифест собирает пути через Join2 (обратною косая),
    # а вызывающий вправе передать -RepoSrc "C:/tmp/mirror/engine". Прежнее сравнение искали
    # "$pf\" literal'ом, поэтому на прямых слэшах ряд из 182 входов сжимался до 9 (мерка по
    # зеркалу 14.11: те же самые отпуск-записи превращались в 10 ложных «УСТАРЕВШИЙ ОТПУСК», а
    # настоящие входы текстов не мерились вовсе). Ошибка в красную сторону, но красная ложь
    # стоит прогона, и ряд, который молча укорачивается от формы слэша, нельзя отличить от
    # укороченного от вырезанного списка.
    $prefixes = @($prefixes | ForEach-Object { $_.Replace('/', '\') })
    $hits = @()
    $checked = 0
    foreach ($k in $m.Keys) {
        $src = [string]$m[$k]
        $prefix = ""
        foreach ($pf in $prefixes) {
            if ($src.Replace('/', '\').StartsWith($pf + '\', [StringComparison]::OrdinalIgnoreCase)) {
                $prefix = $pf; break
            }
        }
        if (-not $prefix) { continue }
        if ([IO.Path]::GetExtension($src) -notin $TEXT_EXT) { continue }
        if (-not (Test-Path -LiteralPath $src)) { throw "нет входного файла -KitSrc: $src" }
        $checked++
        # Метка - КЛЮЧ манифеста, то есть путь внутри архива. Иначе -TextGate подписывал бы находки
        # путём от корня репозитория (serve\server.py), а гейт 2 по дереву раскладки - путём от
        # staging (kit\serve\server.py), и один и тот же отпуск пришлось бы держать в двух формах.
        foreach ($line in @(Get-StandPathHit $src)) {
            $hits += ("{0}: {1}" -f $k, $line)
        }
    }
    return [pscustomobject]@{ Checked = $checked; Hits = $hits }
}

function Read-JsonNoBom([string]$Path, [string]$Label) {
    # BOM меряется первым байтом, а не «похоже ли содержимое на JSON»: с EF BB BF содержимое тоже
    # похоже, а json.loads в kit\classify.py на таком файле падает.
    if (-not (Test-Path -LiteralPath $Path)) { throw "${Label}: файл не найден ($Path)" }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        throw "${Label}: в файле BOM (EF BB BF) - классификатор комплекта не сможет его прочитать"
    }
    if ($bytes.Length -eq 0) { throw "${Label}: файл пуст - проверка не состоялась" }
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
    return ($text | ConvertFrom-Json)
}

function Get-Manifest([string]$StrataBuild, [string]$LlamaBuild, [string]$KitSrc,
                      [string]$Measures, [string]$Cuda, [bool]$WithCudaRuntime,
                      [string]$RepoSrc = "", [string]$VendorStage = "",
                      [bool]$PayloadRequired = $false, [string]$RuntimeDir = "") {
    $m = [ordered]@{}
    $m["bin\strata.exe"] = Join2 $StrataBuild "strata.exe"
    $m["bin\strata-q36.exe"] = Join2 $StrataBuild "strata-q36.exe"
    # strata_kq.dll грузится из кода: LoadLibraryA(папка движка + STRATA_KQ_LIB_NAME), поэтому её
    # нет ни в одной импорт-таблице - ни гейт зависимостей, ни формат-гейт её не видят. Отсутствие
    # молчаливое: в stderr пишется «not found next to the engine», а K-quant-эксперты идут
    # FP16-путём промпта, то есть комплект работает медленнее стенда и не падает.
    $m["bin\strata_kq.dll"] = Join2 $StrataBuild "strata_kq.dll"
    # llama-server.exe - тонкая обёртка (10 КиБ): вся логика в llama-server-impl.dll, и без неё
    # exe на чужой машине падает с «модуль не найден», а не с внятной причиной.
    $m["bin\llama-server.exe"] = Join2 $LlamaBuild "bin\llama-server.exe"
    $m["bin\llama-server-impl.dll"] = Join2 $LlamaBuild "bin\llama-server-impl.dll"
    foreach ($d in @("ggml.dll", "ggml-base.dll", "ggml-cpu.dll", "ggml-cuda.dll",
                     "llama.dll", "llama-common.dll", "mtmd.dll")) {
        $m["bin\$d"] = Join2 $LlamaBuild ("bin\" + $d)
    }
    if ($WithCudaRuntime) {
        # Полноту набора сняла соседняя мера kit_dll_deps.py: cublas64 сам зовёт
        # cublasLt - вдвоём это 488 МиБ, и неполный вариант обязан быть виден отдельным флагом.
        foreach ($d in @("cublas64_13.dll", "cublasLt64_13.dll")) { $m["bin\$d"] = Join2 $Cuda $d }
    }
    foreach ($f in @("detect.py", "classify.py", "gguf_meta.py", "recommend.py", "models.json",
                     "start.ps1")) { $m["kit\$f"] = Join2 $KitSrc $f }
    # Веб-морда и её окружение времени выполнения. Перечень - из $WEB_SPECS / $VENDOR_*, а не
    # на глаз: Get-Manifest остаётся единственным носителем списка файлов, и гейт 4b, гейт 2 и
    # -TextGate меряют ровно то, что уедет в архив.
    $web = Get-WebPayload -Repo $RepoSrc -Required $PayloadRequired
    foreach ($k in $web.Files.Keys) { $m[$k] = $web.Files[$k] }
    $vend = Get-VendorPayload -Stage $VendorStage -Required $PayloadRequired
    foreach ($k in $vend.Files.Keys) { $m[$k] = $vend.Files[$k] }
    # Автономный интерпретатор (гейт 7): обрезанное дерево python-build-standalone попадает в
    # манифест полным списком файлов, а не «папкой» - иначе гейт 1 («дерево = манифест»), гейт 5
    # («в zip нет мусора») и вес в kit-weight.json начнут расходиться с тем, что реально уезжает.
    # Балласт вырезается ДО раскладки, поэтому здесь уже нет ни __pycache__, ни tcl/tk.
    $rt = Get-RuntimePayload -Root $RuntimeDir -Required $PayloadRequired
    foreach ($k in $rt.Files.Keys) { $m[$k] = $rt.Files[$k] }
    $m["START.bat"] = Join2 $KitSrc "START.bat"
    foreach ($f in @("elf-proof.json", "runtime-deps.json", "build-measure.json")) {
        $m[$f] = Join2 $Measures $f
    }
    foreach ($f in @("README.ru.md", "README.en.md")) { $m[$f] = Join2 $KitSrc $f }
    return $m
}

function Get-ProducedBins([string]$Dir, [string]$Label) {
    # Плоско, без подкаталогов: сборка кладёт носители комплекта в корень дерева Страты и в bin
    # сборки llama.cpp, а под деревом лежат объектные и промежуточные файлы - обход дал бы ложные
    # находки на законной сборке. Пустой список - это отказ, а не «нечего проверять»: молчание
    # на пустом входе и есть тот способ, которым потерянный модуль проходит гейт.
    if (-not (Test-Path -LiteralPath $Dir)) { throw "${Label}: нет каталога $Dir" }
    $names = @(Get-ChildItem -LiteralPath $Dir -File |
        Where-Object { $_.Extension -eq ".exe" -or $_.Extension -eq ".dll" } |
        ForEach-Object { $_.Name })
    if (-not $names.Count) { throw "${Label}: в $Dir нет ни одного exe или dll - сборка не производила бинарников" }
    # Без ведущей запятой в return: `return ,@(...)` кладёт массив как ОДИН элемент конвейера, и
    # вызывающий с @(...) получает длину 1 вместо списка (проверено живым прогоном: produced=2).
    return @($names | Sort-Object -Unique)
}

function Test-BinClosure([string]$StrataBuild, [string]$LlamaBuild, $Manifest) {
    # Обратная сторона манифеста: что произведено, но в комплект не взято. Для модулей, которые
    # грузятся из кода по имени (strata_kq.dll), это единственная мерка - их нет ни в одной
    # импорт-таблице, поэтому гейт зависимостей и формат-гейт их не видят вовсе.
    $produced = @(Get-ProducedBins $StrataBuild "дерево сборки Страты")
    $produced += @(Get-ProducedBins (Join2 $LlamaBuild "bin") "bin сборки llama")
    $inKit = @($Manifest.Keys | Where-Object { $_ -like "bin\*" } |
               ForEach-Object { ($_ -split '\\')[-1] })
    $orphan = @($produced | Where-Object {
        $inKit -notcontains $_ -and -not $BIN_WAIVERS.ContainsKey($_) })
    return [pscustomobject]@{ orphan = $orphan; produced = $produced; inKit = $inKit }
}

function Get-AstPython([string]$Preferred) {
    # Для разбора нужен ЛЮБОЙ CPython 3.8+ (ast.parse), а не тот, что уедет в архив: -TextGate
    # работает до компиляции и до распаковки питона комплекта. Переванный явно - первый кандидат
    # (в CI это тот же интерпретатор, что качает колёса). Не нашли - отказ по имени, а не «мерка
    # промолчала»: пустое замыкание зелёное хуже красного архива.
    foreach ($c in @($Preferred, "python", "py", "python3")) {
        if (-not $c) { continue }
        $g = Get-Command $c -ErrorAction SilentlyContinue
        if ($g) { return $g.Source }
    }
    throw ("не найден интерпретатор python для AST-разбора замыкания (передано: '{0}')" -f $Preferred)
}

function Get-AstClosure([string]$Repo, [string]$Py, [string]$Entry, [string]$Carrier,
                        [string[]]$Local = $CLOSURE_ROOTS) {
    # Возвращает Files (путь от корня дерева -> байты) и Via (кто потребовал переход). Разбирает не
    # этот скрипт: вызывается носитель web_closure.py и читается его JSON. Отказ, а не пустой список,
    # если: нет дерева, нет точки входа, нет носителя, python вернул ненулевой rc, вывод не собрался
    # в JSON или в разборе появились broken - во всех этих случаях «замыкание совпало с манифестом»
    # было бы недостоверным утверждением.
    if (-not (Test-Path -LiteralPath $Repo -PathType Container)) { throw "нет дерева репозитория $Repo" }
    if (-not (Test-Path -LiteralPath (Join2 $Repo $Entry) -PathType Leaf)) {
        throw "нет точки входа замыкания $Entry в $Repo - разбирать нечего"
    }
    if (-not $Carrier) { throw "путь к носителю замыкания не передан" }
    if (-not (Test-Path -LiteralPath $Carrier -PathType Leaf)) {
        throw ("нет носителя AST-разбора {0}" -f $Carrier)
    }
    # Ряд передаётся всегда, а не оставляется дефолту носителя: пустой вход без отказа означал бы,
    # что pack_kit сверяет манифест по ряду, которого он сам не задавал, и расхождение ряда правил
    # доливайки с рядом разбора осталось бы невидимым.
    if (-not $Local) { throw "ряд локальных каталогов пуст" }
    # -X utf8 обязателен: без него python пишет отказы в кодировке консоли (cp1251), PowerShell
    # декодирует байты как UTF-8 и вся кириллица в тексте отказа превращается в знаки замены.
    # Мерка «отказ называет зовущего» на таком выводе физически непроходима, а лог CI показал бы
    # кашу вместо причины.
    $a = @("-X", "utf8", "-B", $Carrier, "--repo", $Repo, "--entry", $Entry)
    foreach ($e in $CLOSURE_SYSPATH) { $a += @("--sys-path", $e) }
    foreach ($r in $Local) { $a += @("--local", $r) }
    $a += "--json"
    $out = & $Py @a 2>&1 | Out-String
    $rc = $LASTEXITCODE
    $lines = @(@($out -split "`r?`n") | Where-Object { $_.Trim() -ne "" })
    # С --json носитель печатает ровно одну строку - JSON, и всё остальное в выводе это его отказы
    # или traceback из stderr. Ищем с конца: предупреждение стороннего модуля сверху не должно
    # съесть результат, а последний { - это он.
    $jsonLine = ""
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        if ($lines[$i].Trim().StartsWith("{")) { $jsonLine = $lines[$i].Trim(); break }
    }
    if ($rc -ne 0) {
        # Вердикт «проверка не состоялась» ставит РОВНО ОДИН уровень - тот, что печатает отказ в
        # консоль (:2288 для -TextGate, :2436 для основного пути). Здесь и ниже throw несёт только
        # причину: прежняя практика дописывать суффикс на каждом уровне давала строку, где «-
        # проверка не состоялась» повторилась трижды (замер 14.11 по саботажу frontend.py), и
        # читатель не мог понять, сколько проверок на самом деле не состоялось.
        throw ("носитель замыкания вернул rc={0}: {1}" -f `
               $rc, ((@($lines | Select-Object -First 3)) -join ' / '))
    }
    if (-not $jsonLine) {
        throw ("в выводе носителя нет JSON при rc=0: {0}" -f
               ((@($lines | Select-Object -First 3)) -join ' / '))
    }
    try { $j = $jsonLine | ConvertFrom-Json } catch {
        throw ("JSON носителя не разобрался: {0}" -f $_.Exception.Message)
    }
    $files = [ordered]@{}
    $via = [ordered]@{}
    foreach ($f in @($j.files)) {
        if (-not $f.path) { continue }
        $files[[string]$f.path] = [long]$f.bytes
        $via[[string]$f.path] = [string]$f.via
    }
    $broken = @($j.broken)
    if ($broken) {
        # Отказ, а не укороченное замыкание: неразобранный файл выпадает из списка, и молчаливая
        # сверка укороченного перечня выглядела бы зелёной. Носитель сам возвращает на таком входе
        # rc=2 - эта проверка держит то же правило на уровне договора, а не доверия коду соседа.
        throw ("AST-разбор не дошёл до конца, файлов с ошибкой {0}: {1}" -f `
               $broken.Count, ((@($broken | Select-Object -First 4) -join '; ')))
    }
    if (-not $files.Count) {
        throw ("замыкание от {0} пусто" -f $Entry)
    }
    return [pscustomobject]@{ Files = $files; Via = $via }
}

function Test-ManifestClosure([string]$Repo, $Manifest, [string]$Py, [string]$Carrier,
                              [string]$Entry = $CLOSURE_ENTRY) {
    # Гейт 1c. Манифест обязан ПЕРЕкрывать замыкание: каждый локальный модуль, который сервер
    # действительно импортирует, назван в перечне архива. Недостающий - красный, с именем пути и
    # файлом-источником перехода (без него отказ неотличим от «файл просто забыли»). Лишние .py в
    # манифесте - предупреждение: правило доливайки может нести модуль, который сегодня не
    # импортируется (его зовут по имени из start.ps1 или из CLI), и вырезать его на этом основании
    # было бы правкой списка по косвенному признаку.
    $cl = Get-AstClosure -Repo $Repo -Py $Py -Entry $Entry -Carrier $Carrier
    $keys = @($Manifest.Keys)
    $missing = @()
    foreach ($rel in $cl.Files.Keys) {
        $arch = "kit\" + $rel.Replace('/', '\')
        if ($keys -notcontains $arch) {
            $missing += ("{0} ({1} Б) - требует {2}" -f $arch, $cl.Files[$rel],
                         $(if ($cl.Via[$rel]) { "kit\" + $cl.Via[$rel].Replace('/', '\') } else { "точка входа" }))
        }
    }
    $local = @($keys | Where-Object {
        $_ -match ('^kit\\(' + ($CLOSURE_ROOTS -join '|') + ')\\.*\.py$') })
    $extra = @($local | Where-Object { -not $cl.Files.Contains($_.Substring(4).Replace('\', '/')) } | Sort-Object)
    return [pscustomobject]@{ missing = $missing; extra = $extra
                              files = $cl.Files.Count
                              bytes = [long](@($cl.Files.Values) | Measure-Object -Sum).Sum }
}

function Remove-StandPaths($Node) {
    # В комплект идут КОПИИ мер, а не сами меры: build-measure.json и elf-proof.json набиты
    # путями стенда (F:\CUDA\..., C:\Projects\...), и без этого прохода гейт переносимости
    # краснеет на законной сборке - либо молча протаскивает чужую машину в текст комплекта.
    # Доказательная сила - архитектуры, rc, размеры, время сборки - путями не является и остаётся.
    if ($Node -is [string]) {
        # Явный проход по совпадениям, а не `-replace паттерн, { scriptblock }`: второй вариант
        # в pwsh 7.6 вызывает скриптблок с настоящим Match (проверено: args=1 type=Match), но
        # подставляет в результат ПУСТУЮ строку - молчание, из-за которого пути исчезали бы
        # вместе с половиной текста меры.
        $pat = '(?i)(?<![a-z])[a-z]:[\\/][^"<>|;,\s]*'
        $sb = [System.Text.StringBuilder]::new()
        $last = 0
        foreach ($mt in [regex]::Matches($Node, $pat)) {
            [void]$sb.Append($Node.Substring($last, $mt.Index - $last))
            [void]$sb.Append(($mt.Value -split '[\\/]')[-1])
            $last = $mt.Index + $mt.Length
        }
        [void]$sb.Append($Node.Substring($last))
        return $sb.ToString()
    }
    if ($Node -is [System.Management.Automation.PSCustomObject]) {
        foreach ($p in @($Node.PSObject.Properties)) { $Node.($p.Name) = Remove-StandPaths $Node.($p.Name) }
        return $Node
    }
    if ($Node -is [System.Collections.IDictionary]) {
        foreach ($k in @($Node.Keys)) { $Node[$k] = Remove-StandPaths $Node[$k] }
        return ,$Node
    }
    if ($Node -is [System.Collections.IEnumerable]) {
        # Запятый перед $Node обязателен: `return $Node` в PowerShell раскрывает массив в конвейер,
        # и одноэлементный массив (а такие в мерах есть: список импортов у одиночного бинарника)
        # приезжает к вызывающему скаляром. Проверено меркой: $c.list становился строкой
        # "nvcc.exe", а $c.list[0] - символом 'n'. Мера в сайдкаре меняет форму, и classify.py
        # читает её иначе, чем задумано, - то есть копия меры/portable-набор расходятся молча.
        for ($i = 0; $i -lt $Node.Count; $i++) { $Node[$i] = Remove-StandPaths $Node[$i] }
        return ,$Node
    }
    return $Node
}

function Get-TreeBytes([string]$Dir) {
    $t = 0
    foreach ($f in (Get-ChildItem -LiteralPath $Dir -Recurse -File -Force)) { $t += $f.Length }
    return $t
}

function Format-Mib([long]$Bytes) { return ([math]::Round($Bytes / 1MB, 1)) }

function Test-StageSafe([string]$Measures, [string]$Stage) {
    # Возвращает текст отказа или пустую строку: упаковщик пишет очищенные копии мер в $Stage,
    # а перед этим сносит $Stage рекурсивно. Если каталог мер - он же или лежит под ним,
    # сырые меры (с путями сборки, из которых их и надо переснимать) исчезают в момент упаковки.
    # Именно так 11.11 и было: в dist\gpu-infer-kit-kitall остались только очищенные копии.
    $m = try { [System.IO.Path]::GetFullPath($Measures).TrimEnd('\', '/') } catch { "" }
    $s = try { [System.IO.Path]::GetFullPath($Stage).TrimEnd('\', '/') } catch { "" }
    if (-not $m -or -not $s) {
        return "каталоги мер ($Measures) и сборки ($Stage) не сводятся к полному пути"
    }
    if ($m -eq $s) {
        return "каталог мер и каталог сборки - один каталог ($m): Remove-Item снёс бы сырые меры"
    }
    if ($m.StartsWith($s + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        return "каталог мер $m лежит внутри сносимого каталога сборки $s"
    }
    return ""
}

function Test-StageOwn([string]$Stage) {
    # Под $Stage стоит Remove-Item -Recurse -Force. В стендовом варианте безопасность держалась
    # тем, что stage лежал внутри корня стенда, но корень выводится из положения скрипта, а в
    # Actions рабочее дерево раннера - и есть «своё», и проверка вырождается. Поэтому признак
    # «это наша папка» читается по форме самого пути: имя наше, вложенность не в корне диска, и
    # это каталог, а не файл и не корень шары.
    $full = try { [System.IO.Path]::GetFullPath($Stage).TrimEnd('\', '/') } catch { "" }
    if (-not $full) { return "каталог сборки ($Stage) не сворачивается в полный путь" }
    $leaf = [System.IO.Path]::GetFileName($full)
    if ($leaf -notmatch '(?i)^(gpu-infer-kit[-\w.]*|stage)$') {
        return "каталог сборки '$leaf' не назван gpu-infer-kit* или stage - удалять чужое я не буду"
    }
    # GetPathRoot даёт корень диска; stage обязан лежать глубже, иначе опечатка вида
    # -Stage C:\ указывает на целый диск.
    $drv = [System.IO.Path]::GetPathRoot($full)
    if (-not $drv) { return "путь '$full' не привязан к диску - проверка не состоялась" }
    $rest = $full.Substring($drv.Length).Trim('\', '/')
    if ($rest -notmatch '[\\/]') {
        return "каталог сборки '$full' лежит прямо в корне '$drv' - это не моё дерево"
    }
    return ""
}

# Единственная привязка к положению скрипта: исходники комплекта лежат соседним каталогом к ci\
# внутри того же репозитория, и эта связь одинакова на стенде, в Actions и у любого, кто клонирует
# форк. -TextGate меряет только их и выходит до любой дорогой работы: путь стенда в
# распространяемом README стоил репетиции 43359812438 - она упала на шаге упаковки после 5454 с
# компиляции, то есть гейт обязан стоять в начале, а не в конце. Разбор - до -SelfTest: самотест
# обязан мерять договор с носителем разбора, а не только чистую арифметику манифеста.
if (-not $KitSrc) { $KitSrc = Split-Path -Parent $PSScriptRoot }
# Корень репозитория под web-морду выводится из -KitSrc (packaging\kit -> репозиторий), а не из
# положения скрипта: второй привязки к $PSScriptRoot в этом файле быть не должно, и мерка это
# контролирует. -RepoSrc передаётся явно, когда раскладка нестандартная.
if (-not $RepoSrc) { $RepoSrc = Split-Path -Parent (Split-Path -Parent $KitSrc) }
# Носитель AST-разбора - файл тех же исходников комплекта, поэтому путь выводится из уже
# разрешённого -KitSrc: новой привязки к положению скрипта это не добавляет.
$ClosureCarrier = Join2 $KitSrc "ci\web_closure.py"

if ($SelfTest) {
    $ErrorActionPreference = "Continue"
    $script:ok = 0; $script:bad = 0
    function Chk([string]$Name, $Got, $Want) {
        if ([string]$Got -eq [string]$Want) { $script:ok++; Write-Host "  ok   $Name" }
        else { $script:bad++; Write-Host "FAIL   ${Name}: получено '$Got', ожидалось '$Want'" }
    }
    Write-Host "pack_kit.ps1 selftest"
    # -Encoding utf8NoBOM у Set-Content появился только в PowerShell 6+, и на 5.1 тестовое дерево
    # не создавалось вовсе: первые четыре контроля падали на несозданном дереве, а два из них
    # ждали НОЛЬ находок и проходили вхолостую. Тестовое дерево строится той же записью, что и
    # реальные меры (WriteAllText без BOM), - тогда прогон не зависит от оболочки и на обоих входах.
    function Write-NoBom([string]$Path, [string]$Value) {
        [System.IO.File]::WriteAllText($Path, $Value, (New-Object System.Text.UTF8Encoding($false)))
    }
    Chk "Join2 без слэша" (Join2 "C:\a" "b") "C:\a\b"
    Chk "Join2 с пустой базой" (Join2 "" "b\c") "b\c"

    $tmp = Join2 ([System.IO.Path]::GetTempPath()) ("pack-kit-selftest-" +
               [Guid]::NewGuid().ToString("N").Substring(0, 8))
    New-Item -ItemType Directory -Force -Path (Join2 $tmp "kit\__pycache__") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join2 $tmp "kit\run") | Out-Null
    Write-NoBom (Join2 $tmp "detect.py") "print(1)"
    Write-NoBom (Join2 $tmp "kit\__pycache__\detect.cpython-314.pyc") "x"
    Write-NoBom (Join2 $tmp "kit\run\config.json") "{}"
    Write-NoBom (Join2 $tmp "old.log") "x"
    Write-NoBom (Join2 $tmp "models.json") '{"p": "x"}'
    $keep = Get-KitFiles -Dir $tmp
    Chk "мусор отсеян списком" $keep.Count 2
    Chk "pycache не просочился" (@($keep | Where-Object { $_.FullName -match '__pycache__' }).Count) 0
    Chk "run не просочился" (@($keep | Where-Object { $_.FullName -match '\\run\\' }).Count) 0
    Chk "*.log не просочился" (@($keep | Where-Object { $_.Extension -eq '.log' }).Count) 0

    Write-NoBom (Join2 $tmp "models.json") '{"p": "D:\models\x.gguf"}'
    $hits = Test-NoStandPaths -Dir $tmp
    Chk "путь стенда найден" $hits.Count 1
    Chk "найден именно models.json" (@($hits | Where-Object { $_ -like 'models.json*' }).Count) 1
    # Регрессия на прежнюю сигнатуру: реальные меры пишут путь как «литера, косая черта, дерево,
    # \\ перед именем», и прежний шаблон с обратными слэшами на такой форме молчал - гейт был
    # зелёным при четырнадцати путях машины в текстовых файлах комплекта.
    Write-NoBom (Join2 $tmp "models.json") '{"p": "C:/build/x\\strata.exe"}'
    Chk "косая черта после литеры тоже находка" (Test-NoStandPaths -Dir $tmp).Count 1
    # Обратная сторона: ссылка на CDN не является путём, и не должна красить зелёную сборку.
    Write-NoBom (Join2 $tmp "models.json") `
        '{"hf_url": "https://huggingface.co/x/y/resolve/main/model.gguf"}'
    Chk "https-ссылка не находка" (Test-NoStandPaths -Dir $tmp).Count 0
    Write-NoBom (Join2 $tmp "models.json") '{"p": "models/x.gguf"}'
    Chk "чистое дерево - ноль находок" (Test-NoStandPaths -Dir $tmp).Count 0

    $bomPath = Join2 $tmp "sidecar.json"
    [System.IO.File]::WriteAllText($bomPath, '{"a": 1}', (New-Object System.Text.UTF8Encoding($true)))
    $threw = ""
    try { Read-JsonNoBom $bomPath "elf-proof" | Out-Null } catch { $threw = $_.Exception.Message }
    Chk "BOM в сайдкаре - отказ" ($threw -like "*BOM*") $true
    [System.IO.File]::WriteAllText($bomPath, '{"a": 1}', (New-Object System.Text.UTF8Encoding($false)))
    Chk "без BOM читается" (Read-JsonNoBom $bomPath "elf-proof").a 1
    $threw = ""
    try { Read-JsonNoBom (Join2 $tmp "no-such-file.json") "elf" | Out-Null } catch { $threw = $_.Exception.Message }
    Chk "отсутствующий сайдкар - отказ, а не null" ($threw -like "*не найден*") $true

    # Манифест обязан отказывать на несуществующем дереве сборки, а не молча давать короткий список.
    $threw = ""
    try {
        $mm = Get-Manifest "Q:\нет\build-kit" "Q:\нет\llama" $tmp $tmp "Q:\нет\cuda" $true
        foreach ($k in $mm.Keys) { if (-not (Test-Path -LiteralPath $mm[$k])) { throw "нет файла $k" } }
    } catch { $threw = $_.Exception.Message }
    Chk "несуществующая сборка - отказ манифеста" ($threw -like "нет файла*") $true

    # Развилка веса обязана быть видимой в самом манифесте: 488 МиБ cublas едут в архив только
    # в полной версии, и неполный комплект с ними внутри переставал бы быть неполным.
    $fat = Get-Manifest "Q:\нет\build-kit" "Q:\нет\llama" $tmp $tmp "Q:\нет\cuda" $true
    $thin = Get-Manifest "Q:\нет\build-kit" "Q:\нет\llama" $tmp $tmp "Q:\нет\cuda" $false
    Chk "полный манифест содержит cublas" (@($fat.Keys | Where-Object { $_ -like '*cublas*' }).Count) 2
    Chk "неполный манифест без cublas" (@($thin.Keys | Where-Object { $_ -like '*cublas*' }).Count) 0
    Chk "strata_kq.dll в полном манифесте" ([bool]$fat.Contains("bin\strata_kq.dll")) $true
    Chk "strata_kq.dll в неполном манифесте" ([bool]$thin.Contains("bin\strata_kq.dll")) $true

    # Полнота набора: без саботажа контроль неотличим от молчания, поэтому порядок - ложная
    # тревога на полном наборе, посаженная находка, снятие саботажа, и два отказа на пустом входе.
    # Наборы имён здесь сняты с реальных деревьев сборки (Linking-строки логов 43342630392 и
    # 43345549955), а не на глаз: расхождение с тем, что производит сборка, дало бы красную
    # сборку на законном файле.
    $cbStrata = Join2 $tmp "closure\strata"
    # Корень дерева сборки llama, а не его bin: и Get-Manifest, и Test-BinClosure добавляют bin
    # сами. Проверено живым прогоном: передача ...\llama\bin дала ...\llama\bin\bin и отказ мерки.
    $cbLlama = Join2 $tmp "closure\llama"
    New-Item -ItemType Directory -Force -Path $cbStrata, (Join2 $cbLlama "bin") | Out-Null
    foreach ($f in @("strata.exe", "strata-q36.exe", "strata_kq.dll")) {
        Write-NoBom (Join2 $cbStrata $f) "x"
    }
    foreach ($f in @("llama-server.exe", "llama-server-impl.dll", "llama-common.dll", "llama.dll",
                     "mtmd.dll", "ggml.dll", "ggml-base.dll", "ggml-cpu.dll", "ggml-cuda.dll",
                     "test-cuda-upload-stream.exe")) {
        Write-NoBom (Join2 (Join2 $cbLlama "bin") $f) "x"
    }
    $cbManifest = Get-Manifest $cbStrata $cbLlama $tmp $tmp "Q:\нет\cuda" $false
    Chk "полный набор - ноль находок" (@(Test-BinClosure $cbStrata $cbLlama $cbManifest).orphan.Count) 0
    Chk "произведено меркой 13 exe/dll" (@(Test-BinClosure $cbStrata $cbLlama $cbManifest).produced.Count) 13
    Write-NoBom (Join2 $cbStrata "strata_orphan.dll") "x"
    Chk "посаженный потерянный dll найден" `
        (@(Test-BinClosure $cbStrata $cbLlama $cbManifest).orphan -join ',') "strata_orphan.dll"
    Remove-Item -LiteralPath (Join2 $cbStrata "strata_orphan.dll") -Force
    Chk "саботаж снят - снова ноль находок" (@(Test-BinClosure $cbStrata $cbLlama $cbManifest).orphan.Count) 0
    Write-NoBom (Join2 $cbStrata "strata_orphan.dll") "x"
    $BIN_WAIVERS["strata_orphan.dll"] = "саботаж selftest: отпуск с причиной прячет тот же файл"
    Chk "отпуск с причиной подавляет находку" `
        (@(Test-BinClosure $cbStrata $cbLlama $cbManifest).orphan.Count) 0
    $BIN_WAIVERS.Remove("strata_orphan.dll")
    Remove-Item -LiteralPath (Join2 $cbStrata "strata_orphan.dll") -Force
    # Пустое и несуществующее дерево обязаны отказывать, а не давать «ноль находок»: пустой вход,
    # на котором мерка молчит, и есть способ, которым потерянный модуль уходит в комплект.
    $cbEmpty = Join2 $tmp "closure\empty"
    New-Item -ItemType Directory -Force -Path $cbEmpty | Out-Null
    $threw = ""
    try { Test-BinClosure $cbEmpty $cbLlama $cbManifest | Out-Null } catch { $threw = $_.Exception.Message }
    Chk "пустое дерево - отказ, а не ноль находок" ($threw -like "*не производила бинарников*") $true
    $threw = ""
    try { Test-BinClosure (Join2 $tmp "closure\nosuch") $cbLlama $cbManifest | Out-Null }
    catch { $threw = $_.Exception.Message }
    Chk "несуществующее дерево - отказ по имени каталога" ($threw -like "*нет каталога*") $true

    # Очистка путей меряется отдельно от гейта: иначе «проход есть» неотличимо от «проход всё
    # съел» - контроль на прозе без путей ловит второй случай.
    Chk "путь сворачивается в имя файла" (Remove-StandPaths "C:\a\b\ggml-cuda.dll") "ggml-cuda.dll"
    Chk "проза без путей не меняется" (Remove-StandPaths "собрано и доказано") "собрано и доказано"
    $nested = '{"p": "D:\\models\\x.gguf", "list": ["F:\\CUDA\\cuda-13.3\\bin\\nvcc.exe"]}' | ConvertFrom-Json
    $clean = Remove-StandPaths $nested
    Chk "вложенные объект и массив вычищены" ($clean.p + "|" + $clean.list[0]) "x.gguf|nvcc.exe"
    # Форма меры важнее содержимого: массив из одного элемента обязан остаться массивом,
    # иначе скаляр вместо списка уедет в комплект и classify.py прочитает его по-другому.
    Chk "одноэлементный массив остался массивом" $clean.list.GetType().Name "Object[]"
    Chk "элементов в массиве как было" $clean.list.Count 1
    $multi = Remove-StandPaths ('{"a": ["C:\\x\\one.dll", "D:\\y\\two.dll"]}' | ConvertFrom-Json)
    Chk "многосточный массив вычищен поэлементно" ($multi.a -join ',') "one.dll,two.dll"
    # Очистка обязана идти по той же сигнатуре, что и гейт: иначе «проход по косым чертам» - это
    # ноль изменений в мере, а гейт краснеет на легальной сборке. Смешанная форма (косые в дереве,
    # удвоенный обратный перед именем) - ровно то, что лежало в elf-proof.json живого комплекта.
    Chk "косая черта сворачивается в имя" (Remove-StandPaths "C:/a/b/ggml-cuda.dll") "ggml-cuda.dll"
    Chk "смешанный разделитель сворачивается в имя" (Remove-StandPaths "C:/a/b\\strata-q36.exe") "strata-q36.exe"
    Chk "https не изуродован очисткой" `
        (Remove-StandPaths "загрузить с https://developer.download.nvidia.com/compute/cuda/redist/x.zip") `
        "загрузить с https://developer.download.nvidia.com/compute/cuda/redist/x.zip"
    $scrubbed = Remove-StandPaths ('{"path": "C:/build/kit\\strata.exe", "url": "https://hf.co/x/y.gguf"}' | ConvertFrom-Json)
    Chk "вычищенная мера больше не находится гейтом" ($scrubbed.path -match $STAND_PATH_RE) $false
    Chk "вычищенная ссылка цела" $scrubbed.url "https://hf.co/x/y.gguf"

    # Защита каталога мер меряется до основного потока: отказ обязан быть текстом, а не «меры
    # исчезли между прогонами», и разные формы записи одного и того же пути не должны её обмануть.
    Chk "один каталог для мер и сборки - отказ" `
        ([bool](Test-StageSafe "C:\p\dist\kit" "C:\p\dist\kit")) $true
    Chk "каталог мер внутри сносимого - отказ" `
        ([bool](Test-StageSafe "C:\p\dist\measures" "C:\p\dist")) $true
    Chk "скосл и слэш в пути не обманывают мерку" `
        ([bool](Test-StageSafe "C:\p\dist\kit\" "C:/p/dist/kit")) $true
    Chk "раздельные каталоги проходят" `
        ([string](Test-StageSafe "C:\p\dist\measures" "C:\p\dist\stage\kit")) ""

    # Test-StageOwn - единственная оставшаяся привязка «удалять можно только своё»: в CI копия
    # не знает корня стенда, поэтому признак читается по имени и глубине пути.
    Chk "stage с нашим именем проходит" `
        ([string](Test-StageOwn "D:\a\Strata\Strata\artifacts\stage\gpu-infer-kit")) ""
    Chk "stage с версией в имени проходит" `
        ([string](Test-StageOwn "C:\p\dist\stage\gpu-infer-kit-2026-11-12")) ""
    Chk "голое имя stage проходит" ([string](Test-StageOwn "C:\p\dist\stage")) ""
    Chk "чужое имя stage - отказ" `
        ([bool](Test-StageOwn "D:\a\Strata\Strata\artifacts\models")) $true
    Chk "корень диска - отказ" ([bool](Test-StageOwn "C:\")) $true
    Chk "пустой stage - отказ, а не «безопасно»" `
        ([bool](Test-StageOwn "")) $true
    Chk "наше имя в корне диска - отказ по глубине" `
        ((Test-StageOwn "C:\stage") -like "*прямо в корне*") $true
    Chk "разное написание одного пути не обманывает мерку" `
        ([string](Test-StageOwn "C:\p\dist\stage\gpu-infer-kit\")) ""

    # Последний контроль - саботаж предыдущих: мера обязана находить чужое имя, иначе пустой
    # отказ неотличим от «проверка не состоялась».
    Chk "мера находит заведомо чужое имя" `
        ((Test-StageOwn "C:\p\Windows") -like "*не назван*") $true
    # --- CI-пригодность --------------------------------------------------------------------
    # Тот же класс дефекта, что контролируется в build_kit.ps1: в рабочую копию возвращается
    # стендовый путь или корень, выведенный из положения скрипта. На стенде такая копия работает,
    # в Actions падает другой ошибкой, и по логу не понять, что виной путь. Литералы ищутся по
    # коду, из которого вырезаны docstring и комментарии, иначе мерка находит собственные
    # пояснения; отказы по входам меряются прогоном, а не грепом.
    $raw = [System.IO.File]::ReadAllText($PSCommandPath)
    $dollar = [char]36
    $noDoc = [regex]::Replace($raw, '(?s)<\#.*?\#>', '')
    $code = @(($noDoc -split "`r?`n") | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
    # Каждый литерал собран из двух кусков: целым он остался бы в этом же файле, и мерка
    # встречала бы самое себя (на build_kit.ps1 это дало 7 «находок» из 7 своих же).
    $lits = @('harness\' + 'kit', 'harness\' + 'scripts', 'engine\' + 'build-kit',
              'llama' + '-kit', 'dist\' + 'gpu-infer-kit', 'dist\' + 'stage',
              'C:\' + 'Projects', 'build' + '-kit')
    Chk "в коде нет стендовых литералов путей" (@($lits | Where-Object { $code.Contains($_) }) -join ', ') ""
    Chk "в коде нет обращений к выведенному корню" `
        ([regex]::Matches($code, '\' + $dollar + 'root\b').Count) 0
    # Та же схема обязана находить то, что в коде точно есть, иначе «0 находок» неотличимо от
    # паттерна, который не находит ничего (в regex `$` читается как анкор конца строки).
    Chk "мера находит заведомо присутствующий маркер" `
        ([regex]::Matches($code, '\' + $dollar + 'Stage\b').Count -gt 0) $true
    # Путь, выведенный из положения скрипта, разрешён ровно один - исходники комплекта. Любая
    # новая привязка означает, что CI-копия снова смотрит на стендовую раскладку.
    $locLines = @(($code -split "`r?`n") | Where-Object { $_.Contains('PSScript' + 'Root') })
    Chk "привязка к положению скрипта - ровно одна строка" $locLines.Count 1
    Chk "единственная привязка - исходники комплекта" `
        (@($locLines | Where-Object { $_.Contains('KitSrc') }).Count) 1
    foreach ($p in @("StrataBuild", "LlamaBuild", "KitSrc", "Measures", "Stage", "Zip",
                     "CudaBin", "Version", "RepoSrc", "VendorStage", "VendorOut",
                     "VendorPython")) {
        $m = [regex]::Match($code,
              '(?m)^\s*\[string\]' + [regex]::Escape($dollar + $p) + '\s*=\s*"([^"]*)"')
        # Первый контроль - саботаж второго: без него зелёный давал бы параметр, которого нет.
        Chk "параметр -$p объявлен (мера не пустая)" $m.Success $true
        Chk "параметр -$p без дефолтного пути" $m.Groups[1].Value ""
    }
    Chk "имя архива собирается из параметра, а не из корня" `
        ($code.Contains('(Split-Path -Parent ' + $dollar + 'Measures)')) $true

    # Отказы по входам: rc=2, имя параметра в тексте, и всё до первой дорогой работы.
    function Invoke-EntryProbe([string[]]$Entry) {
        $exe = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
        if (-not $exe) { return [pscustomobject]@{ rc = -1; out = "нет pwsh - прогон не состоялся" } }
        $out = & $exe -NoProfile -NonInteractive -File $PSCommandPath @Entry 2>&1 | Out-String
        return [pscustomobject]@{ rc = $LASTEXITCODE; out = $out }
    }
    $noDir = "C:\_pack-kit-selftest-no-such-dir"
    # Путь stage в прогонах собран из кусков: целым он попал бы в список стендовых литералов
    # выше, и мерка нашла бы самое себя вместо кода основного потока.
    $stageOk = 'C:\p\dist\' + 'stage\gpu-infer-kit'
    $good = @("-StrataBuild", $noDir, "-LlamaBuild", $noDir)
    foreach ($t in @(
        @{ n = "без -StrataBuild"; o = "StrataBuild";
           a = @("-LlamaBuild", $noDir, "-Measures", $noDir, "-Stage", $stageOk) },
        @{ n = "без -Measures"; o = "Measures"; a = ($good + @("-Stage", $stageOk)) },
        @{ n = "без -Stage"; o = "Stage"; a = ($good + @("-Measures", $noDir)) },
        @{ n = "stage не наш"; o = "Stage"; a = ($good + @("-Measures", $noDir, "-Stage", "C:\p\Windows")) }
    )) {
        $pr = Invoke-EntryProbe $t.a
        Chk "отказ по входу ($($t.n)) даёт rc=2" $pr.rc 2
        Chk "отказ по входу ($($t.n)) называет -$($t.o)" ($pr.out.Contains($t.o)) $true
    }
    # Отказ обязан случиться до сборки архива: позиция меряется по тексту основного потока,
    # а не по слову -Stage, которое есть и в самих прогонах выше. Иглы тоже собраны из кусков:
    # целиком 'CreateFromDirectory' встретился бы в этой же строке мерки, и порядок оказался бы
    # перевёрнут (проверено на красном прогоне 12.11: находка внутри собственной меры).
    $iStage = $code.IndexOf('ОТКАЗ: ' + '-Stage')
    $iZip = $code.IndexOf('CreateFrom' + 'Directory')
    Chk "проверка stage идёт до упаковки zip" ($iStage -ge 0 -and $iZip -ge 0 -and $iStage -lt $iZip) $true
    Chk "отказ по -Stage в коде ровно один" `
        ([regex]::Matches($code, [regex]::Escape('ОТКАЗ: ' + '-Stage')).Count) 1

    # --- ранний гейт текстовых файлов комплекта (-TextGate) -------------------------------------------
    # Класс закрыт живым прогоном: репетиция 43359812438 упала на шаге упаковки из-за пути стенда
    # в README, то есть после 5454 с компиляции. Гейт обязан мерить те же файлы до сборки, а
    # перечень - приходить из манифеста: переписанный список был бы вторым носителем истины.
    $tgDir = Join2 $tmp "kit-src"
    New-Item -ItemType Directory -Force -Path $tgDir | Out-Null
    foreach ($f in @("detect.py", "classify.py", "gguf_meta.py", "recommend.py", "models.json",
                     "start.ps1", "START.bat", "README.ru.md", "README.en.md")) {
        Write-NoBom (Join2 $tgDir $f) "переносимо"
    }
    $tg = Test-KitSourceTexts -Src $tgDir
    Chk "текстовые файлы комплекта: меряются все 9 файлов манифеста" $tg.Checked 9
    Chk "текстовые файлы комплекта: на чистом дереве ноль находок" $tg.Hits.Count 0
    Write-NoBom (Join2 $tgDir "README.en.md") 'logs in D:\tmp\x'
    $tgBad = Test-KitSourceTexts -Src $tgDir
    Chk "текстовые файлы комплекта: путь в README найден" $tgBad.Hits.Count 1
    Chk "текстовые файлы комплекта: находка названа файлом" `
        (@($tgBad.Hits | Where-Object { $_ -like 'README.en.md*' }).Count) 1
    # ci\ лежит в том же дереве исходников, но в архив не едет: находка вне перечня манифеста не
    # имеет права красить прогон, иначе гейт падает на законном дереве.
    New-Item -ItemType Directory -Force -Path (Join2 $tgDir "ci") | Out-Null
    Write-NoBom (Join2 $tgDir "ci\helper.ps1") 'D:\a\_temp\stage'
    Chk "текстовые файлы комплекта: ci-скрипт вне перечня не меряется" `
        (Test-KitSourceTexts -Src $tgDir).Hits.Count 1
    $prTg = Invoke-EntryProbe @("-TextGate", "-KitSrc", $noDir)
    Chk "отказ по входу (-TextGate без каталога) даёт rc=2" $prTg.rc 2
    Chk "отказ по входу (-TextGate) называет KitSrc" ($prTg.out.Contains("KitSrc")) $true

    # --- доливайка веб-морды, колёс и гейт присутствия -----------------------------------------------
    # Класс дефекта закрыт чужой машиной: архив открывался, движок стартовал, веб-морды нет. Ни
    # формат-гейт, ни полнота набора бинарников этого не видят, поэтому меряется сам перечень
    # путей и его же отсутствие поимённо.
    $wr = Join2 $tmp "webrepo"
    foreach ($d in @("serve\web\locales", "serve\fixtures\deepseek41", "serve\__pycache__",
                     "strata_control", "strata_cli\launch", "tools")) {
        New-Item -ItemType Directory -Force -Path (Join2 $wr $d) | Out-Null
    }
    foreach ($f in @("serve\server.py", "serve\frontend.py", "serve\test_server.py",
                     "serve\mcp_fake_server.py", "serve\chat_template.jinja",
                     "serve\__pycache__\server.cpython-314.pyc", "serve\web\index.html",
                     "serve\web\app.js", "serve\web\locales\ru.json",
                     "serve\fixtures\deepseek41\chat_template.jinja",
                     "strata_control\engine_component.py", "strata_control\app_policy.py",
                     "strata_control\test_policy.py", "strata_control\update_keys.json",
                     "strata_cli\__init__.py", "strata_cli\cli.py", "strata_cli\client.py",
                     "strata_cli\launch\cmd.py", "tools\strata_tokenizer.py",
                     "tools\gguf_reader.py", "tools\calibrate.py")) {
        Write-NoBom (Join2 $wr $f) "переносимо"
    }
    $web = Get-WebPayload -Repo $wr -Required $true
    Chk "доливайка: 16 файлов по списку правил" $web.Files.Count 16
    Chk "доливайка: тестов в перечне нет" (@($web.Files.Keys | Where-Object { $_ -like '*\test_*' }).Count) 0
    Chk "доливайка: mcp_fake_server не поехал" `
        (@($web.Files.Keys | Where-Object { $_ -like '*mcp_fake_server*' }).Count) 0
    Chk "доливайка: serve\fixtures не поехал" (@($web.Files.Keys | Where-Object { $_ -like '*fixtures*' }).Count) 0
    Chk "доливайка: __pycache__ не поехал" (@($web.Files.Keys | Where-Object { $_ -like '*__pycache__*' }).Count) 0
    Chk "доливайка: tools\calibrate едет в архив" `
        (@($web.Files.Keys | Where-Object { $_ -like '*calibrate*' }).Count) 1
    Chk "доливайка: раскладка kit\serve" (@($web.Files.Keys | Where-Object { $_ -like 'kit\serve\*' }).Count) 6
    Chk "доливайка: раскладка kit\strata_control" (@($web.Files.Keys | Where-Object { $_ -like 'kit\strata_control\*' }).Count) 3
    Chk "доливайка: раскладка kit\strata_cli" (@($web.Files.Keys | Where-Object { $_ -like 'kit\strata_cli\*' }).Count) 4
    Chk "доливайка: раскладка kit\tools" (@($web.Files.Keys | Where-Object { $_ -like 'kit\tools\*' }).Count) 3
    Chk "доливайка: печатается 7 групп веса" $web.Stats.Count 7
    Chk "доливайка: без дерева и без Required - пустой перечень" `
        (Get-WebPayload -Repo (Join2 $tmp "no-such-repo") -Required $false).Files.Count 0
    $threw = ""
    try { Get-WebPayload -Repo (Join2 $tmp "no-such-repo") -Required $true | Out-Null } catch { $threw = $_.Exception.Message }
    Chk "доливайка: нет дерева репозитория - отказ называет группу" ($threw -like "*serve-code*") $true
    $wEmpty = Join2 $tmp "webrepo-empty"
    foreach ($d in @("serve\web", "strata_control", "strata_cli", "tools")) {
        New-Item -ItemType Directory -Force -Path (Join2 $wEmpty $d) | Out-Null
    }
    Write-NoBom (Join2 $wEmpty "serve\server.py") "x"
    Write-NoBom (Join2 $wEmpty "serve\chat_template.jinja") "x"
    $threw = ""
    try { Get-WebPayload -Repo $wEmpty -Required $true | Out-Null } catch { $threw = $_.Exception.Message }
    Chk "доливайка: пустое правило serve-web красит прогон, а не молчит" `
        ($threw -like "*serve-web*ни одного файла*") $true
    Remove-Item -LiteralPath (Join2 $wEmpty "serve\chat_template.jinja") -Force
    $threw = ""
    try { Get-WebPayload -Repo $wEmpty -Required $true | Out-Null } catch { $threw = $_.Exception.Message }
    Chk "доливайка: отсутствующий названный файл группы назван" `
        ($threw -like "*serve-data*chat_template.jinja*") $true

    # --- гейт 1c: договор с носителем AST-разбора, конец-в-конец ---------------------------------------
    # Меряется не арифметика сверки, а весь путь: синтетическое дерево + настоящий носитель +
    # настоящий python. Без этого контроля зелёный гейт мог означать «разбор молчал»: пустое
    # замыкание тривиально не содержит ничего лишнего, и именно так мерка выглядела бы рабочей,
    # ничего не проверяя.
    $clT = Join2 $tmp "closure-tree"
    foreach ($d in @("serve", "strata_control", "tools")) {
        New-Item -ItemType Directory -Force -Path (Join2 $clT $d) | Out-Null
    }
    Write-NoBom (Join2 $clT "serve\__init__.py") ""
    Write-NoBom (Join2 $clT "serve\server.py") `
        "from serve import frontend`nimport strata_control.engine_component`n"
    Write-NoBom (Join2 $clT "serve\frontend.py") "x = 1`n"
    Write-NoBom (Join2 $clT "strata_control\__init__.py") ""
    Write-NoBom (Join2 $clT "strata_control\engine_component.py") "import calibrate`n"
    Write-NoBom (Join2 $clT "tools\calibrate.py") "y = 2`n"
    $clPy = ""
    try { $clPy = Get-AstPython $VendorPython } catch { $clPy = "" }
    Chk "гейт 1c: самотест нашёл интерпретатор для разбора" ($clPy -ne "") $true
    $clMan = @{}
    foreach ($k in @("kit\serve\__init__.py", "kit\serve\server.py", "kit\serve\frontend.py",
                     "kit\strata_control\__init__.py", "kit\strata_control\engine_component.py",
                     "kit\tools\calibrate.py")) { $clMan[$k] = $k }
    $g1 = Test-ManifestClosure -Repo $clT -Manifest $clMan -Py $clPy -Carrier $ClosureCarrier
    Chk "гейт 1c: замыкание синтетики посчитано" $g1.files 6
    Chk "гейт 1c: полный перечень - ноль недостающих" $g1.missing.Count 0
    # саботаж 1: calibrate убран из перечня - ровно тот дефект, из-за которого гейт появился:
    # его зовут по пути (голое имя из tools), и пакетное правило его не перечисляет.
    $clMan2 = @{}
    foreach ($k in $clMan.Keys) { if ($k -ne "kit\tools\calibrate.py") { $clMan2[$k] = $k } }
    $g2 = Test-ManifestClosure -Repo $clT -Manifest $clMan2 -Py $clPy -Carrier $ClosureCarrier
    Chk "гейт 1c: calibrate вне перечня - одна находка" $g2.missing.Count 1
    Chk "гейт 1c: находка названа архивным путём" `
        (@($g2.missing | Where-Object { $_ -like "*calibrate.py*" }).Count) 1
    Chk "гейт 1c: находка указывает, кто её требует" `
        (@($g2.missing | Where-Object { $_ -like "*engine_component.py*" }).Count) 1
    # саботаж 2: лишний .py в перечне - предупреждение, а не отказ: правило доливайки вправе нести
    # модуль, который зовут не из сервера (start.ps1, CLI).
    $clMan3 = @{}
    foreach ($k in $clMan.Keys) { $clMan3[$k] = $k }
    $clMan3["kit\tools\not_imported.py"] = "x"
    $g3 = Test-ManifestClosure -Repo $clT -Manifest $clMan3 -Py $clPy -Carrier $ClosureCarrier
    Chk "гейт 1c: лишний файл не недостающий" $g3.missing.Count 0
    Chk "гейт 1c: лишний файл назван" `
        (@($g3.extra | Where-Object { $_ -like "*not_imported*" }).Count) 1
    # саботаж 3: неразбираемый файл внутри замыкания - отказ с rc носителя и именем файла, а не
    # укороченное «всё совпало». Носитель на таком входе возвращает 2 («проверка не состоялась»).
    Write-NoBom (Join2 $clT "serve\frontend.py") "def (:`n"
    $threw = ""
    try {
        Test-ManifestClosure -Repo $clT -Manifest $clMan -Py $clPy -Carrier $ClosureCarrier | Out-Null
    } catch { $threw = $_.Exception.Message }
    Chk "гейт 1c: битый файл даёт отказ, а не зелёный список" ($threw -like "*rc=2*") $true
    Chk "гейт 1c: отказ называет неразобранный файл" ($threw -like "*frontend.py*") $true
    Write-NoBom (Join2 $clT "serve\frontend.py") "x = 1`n"
    # саботаж 4: нет носителя -> именованный отказ. Молчание здесь означало бы, что CI-копия
    # упаковывает комплект, никогда не меряя полноту манифеста.
    $threw = ""
    try {
        Test-ManifestClosure -Repo $clT -Manifest $clMan -Py $clPy -Carrier (Join2 $tmp "net-net.py") |
            Out-Null
    } catch { $threw = $_.Exception.Message }
    Chk "гейт 1c: отсутствие носителя названо по пути" ($threw -like "*носителя*") $true
    # саботаж 5: модуль, который сервер зовёт, исчез с ДЕРЕВА (не из перечня). Это и есть дефект,
    # ради которого просили краснеющий саботаж: правило доливайки берёт serve\*.py списком по
    # маске, и удалённый frontend.py тихо выпал бы из архива, а отказ пришёл бы только на чужой
    # машине. Разбор обязан назвать и пропавший модуль, и зовущего.
    Remove-Item -LiteralPath (Join2 $clT "serve\frontend.py") -Force
    $threw = ""
    try {
        Test-ManifestClosure -Repo $clT -Manifest $clMan -Py $clPy -Carrier $ClosureCarrier | Out-Null
    } catch { $threw = $_.Exception.Message }
    Chk "гейт 1c: удалённый с дерева frontend.py даёт отказ" ($threw -like "*rc=2*") $true
    Chk "гейт 1c: отказ называет пропавший модуль" ($threw -like "*serve/frontend.py*") $true
    Chk "гейт 1c: отказ называет зовущего" ($threw -like "*зовёт serve/server.py*") $true
    Write-NoBom (Join2 $clT "serve\frontend.py") "x = 1`n"
    Chk "гейт 1c: после возврата файла перечень снова замкнут" `
        (Test-ManifestClosure -Repo $clT -Manifest $clMan -Py $clPy -Carrier $ClosureCarrier).missing.Count 0

    $vv = Join2 $tmp "vendor"
    foreach ($abi in $VENDOR_ABIS) {
        foreach ($pn in @("regex", "markupsafe")) {
            $dirv = Join2 (Join2 $vv $abi) $pn
            New-Item -ItemType Directory -Force -Path $dirv | Out-Null
            Write-NoBom (Join2 $dirv "__init__.py") "x"
        }
    }
    $dirv = Join2 (Join2 $vv $VENDOR_PURE_ABI) "jinja2"
    New-Item -ItemType Directory -Force -Path $dirv | Out-Null
    Write-NoBom (Join2 $dirv "__init__.py") "x"
    # Тестовый набор самого regex и __pycache__ из колеса вырезаются: в чужом архиве они лишние
    # (5 x 1,5 МиБ), а на переносимость не влияют - но обязан влиять факт вырезки, иначе колесо
    # уезжает целиком и молча.
    $dirT = Join2 (Join2 (Join2 $vv "cp313") "regex") "tests"
    New-Item -ItemType Directory -Force -Path $dirT | Out-Null
    Write-NoBom (Join2 $dirT "test_regex.py") "x"
    $dirC = Join2 (Join2 (Join2 $vv "cp313") "regex") "__pycache__"
    New-Item -ItemType Directory -Force -Path $dirC | Out-Null
    Write-NoBom (Join2 $dirC "__init__.cpython-314.pyc") "x"
    $ven = Get-VendorPayload -Stage $vv -Required $true
    Chk "колёса: тестовый набор колеса в архив не едет" `
        ([bool]$ven.Files.Contains("kit\vendor\cp313\regex\tests\test_regex.py")) $false
    Chk "колёса: кэш питона в архив не едет" `
        (@($ven.Files.Keys | Where-Object { $_ -like '*__pycache__*' }).Count) 0
    Chk "колёса: вырезка не задела сам пакет" `
        ([bool]$ven.Files.Contains("kit\vendor\cp313\regex\__init__.py")) $true
    Chk "колёса: 6 ABI-каталогов в перечне" $ven.Stats.Count 6
    Chk "колёса: путь внутри архива kit\vendor\cp313\regex" `
        ([bool]$ven.Files.Contains("kit\vendor\cp313\regex\__init__.py")) $true
    Chk "колёса: pure-пакет лежит один раз, а не пять" `
        (@($ven.Files.Keys | Where-Object { $_ -like '*\jinja2\__init__.py' }).Count) 1
    Chk "колёса: без каталога и без Required - пустой перечень" `
        (Get-VendorPayload -Stage "" -Required $false).Files.Count 0
    $threw = ""
    try { Get-VendorPayload -Stage (Join2 $tmp "vendor-no-such") -Required $true | Out-Null } catch { $threw = $_.Exception.Message }
    Chk "колёса: нет staging - отказ, а не урезанный архив" ($threw -like "*VendorStage*") $true

    $mmW = Get-Manifest $cbStrata $cbLlama $tgDir $tgDir "Q:\нет\cuda" $false $wr $vv
    Chk "манифест: kit\serve\server.py назван" ([bool]$mmW.Contains("kit\serve\server.py")) $true
    Chk "манифест: kit\serve\web\index.html назван" ([bool]$mmW.Contains("kit\serve\web\index.html")) $true
    Chk "манифест: kit\vendor\cp311\regex\__init__.py назван" `
        ([bool]$mmW.Contains("kit\vendor\cp311\regex\__init__.py")) $true
    Chk "гейт присутствия: полный набор - ноль отсутствий" @(Test-KitWebPresence @($mmW.Keys) $true).Count 0
    Chk "гейт присутствия: без колёс (-TextGate) о vendor молчит" `
        @(Test-KitWebPresence @($web.Files.Keys) $false).Count 0
    $bad1 = @($mmW.Keys | Where-Object { $_ -ne "kit\serve\server.py" })
    Chk "гейт присутствия: отсутствие kit\serve\server.py названо" `
        (@(Test-KitWebPresence $bad1 $true)[0] -like "kit\serve\server.py - *") $true
    $bad2 = @($mmW.Keys | Where-Object { $_ -notlike "kit\vendor\cp313\regex\*" })
    Chk "гейт присутствия: пустой ABI cp313 назван" `
        (@(Test-KitWebPresence $bad2 $true | Where-Object { $_ -like "kit\vendor\cp313\regex\*" }).Count) 1
    $bad3 = @($mmW.Keys | Where-Object { $_ -notlike "kit\vendor\py3-none-any\jinja2\*" })
    Chk "гейт присутствия: отсутствие jinja2 названо" `
        (@(Test-KitWebPresence $bad3 $true | Where-Object { $_ -like "kit\vendor\py3-none-any\jinja2\*" }).Count) 1
    $bad4 = @($mmW.Keys | Where-Object { $_ -ne "kit\serve\web\index.html" -and $_ -ne "kit\tools\strata_tokenizer.py" })
    # Форма возврата - плоский список строк. На вложенном массиве (`return ,@(...)`) каждый
    # @( ... ).Count ниже равен 1 при любом содержимом, и меры «отсутствий ровно N» молча
    # превращаются в константу - ровно так два самоконтроля этого блока и выглядели зелёными.
    $missShape = @(Test-KitWebPresence $bad4 $true)
    Chk "гейт присутствия: две причины - две СТРОКИ, а не один вложенный массив" `
        (@($missShape | Where-Object { $_ -is [string] }).Count) 2
    Chk "гейт присутствия: два отсутствия - две именованные причины" $missShape.Count 2
    # Тот же контракт у гейта 7: Test-KitRuntimePresence обязан возвращать плоский список, иначе
    # «отсутствует (1)» в логе CI скрывало бы потерю двух остальных путей.
    $rtNone = @(Test-KitRuntimePresence @())
    Chk "гейт 7: пустой перечень - все обязательные пути названы" $rtNone.Count $RUNTIME_PRESENCE.Count
    Chk "гейт 7: отсутствие python.exe названо по пути" `
        (@($rtNone | Where-Object { $_ -like "kit\runtime\python\python.exe - *" }).Count) 1
    # Саботаж по ДЕРЕВУ, а не по списку путей: исходный дефект чужой машины был ровно такой - файл не
    # попал в архив, и урезанный перечень ничему не доказательство, если его никто не сверял с тем,
    # что реально нашлось на диске. serve-web берётся маской, поэтому удаления само по себе не красный:
    # красным его обязан сделать гейт присутствия.
    Remove-Item -LiteralPath (Join2 $wr "serve\web\index.html") -Force
    $webSab = Get-WebPayload -Repo $wr -Required $true
    Chk "саботаж: без страницы доливайка несёт на файл меньше" `
        $webSab.Files.Count ($web.Files.Count - 1)
    $missSab = @(Test-KitWebPresence @($webSab.Files.Keys) $false)
    Chk "саботаж: отсутствие index.html названо поимённо ровно один раз" `
        (@($missSab | Where-Object { $_ -like "kit\serve\web\index.html - *" }).Count) 1
    Chk "саботаж: иных отсутствий гейт не выдумывает" $missSab.Count 1
    Write-NoBom (Join2 $wr "serve\web\index.html") "переносимо"
    # Две отдельные меры, а не одно булево «и»: композитное утверждение краснеет молча и не
    # показывает, что именно сломалось - перечень или гейт присутствия.
    $webBack = Get-WebPayload -Repo $wr -Required $true
    Chk "саботаж: файл возвращён - перечень снова полного размера" $webBack.Files.Count $web.Files.Count
    Chk "саботаж: файл возвращён - гейт присутствия снова чист" `
        (@(Test-KitWebPresence @($webBack.Files.Keys) $false).Count) 0
    # Байты долейки печатаются в отчёте, и «Measure-Object -Property Sum» вместо «-Sum» давал бы
    # «0 Б» на полном дереве - то есть отчёт врал бы о весе морды.
    $webBytes = [long](@($web.Files.Values) | ForEach-Object { (Get-Item -LiteralPath $_).Length } |
                       Measure-Object -Sum).Sum
    Chk "долейка: суммарный вес ненулевой" ($webBytes -gt 0) $true
    Chk "долейка: итог равен сумме по группам правил" `
        $webBytes ([long](@($web.Stats.Keys) | ForEach-Object { $web.Stats[$_].bytes } | Measure-Object -Sum).Sum)
    # Дыра в одном ABI обнаруживается и на перечне колёс, а не только на итоговом архиве.
    Remove-Item -LiteralPath (Join2 (Join2 (Join2 $vv "cp311") "regex") "__init__.py") -Force
    $threw = ""
    try { Get-VendorPayload -Stage $vv -Required $true | Out-Null } catch { $threw = $_.Exception.Message }
    Chk "колёса: дыра в ABI cp311 названа по имени пакета" ($threw -like "*cp311*regex*") $true

    # --- ._pth: путь вендора обязан быть в файле, а не в переменной ---------------------------------
    # Механизм измерен прогоном glm\scripts\kit415_pth_mechanism_2026-11-14.ps1 (семь прогонов,
    # артефакт glm\2026-11-14_session\kit415-pth-mechanism.txt): без ._pth PYTHONPATH работает, с
    # ._pth переменная игнорируется молча (isolated=1), а относительная строка импортирует вендор.
    # Отсюда две мерки: как строится относительный путь и что делает Add-VendorToPth.
    Chk "раскладка: vendor cp312 от kit\runtime\python" `
        (Get-RelPathFrom $RUNTIME_DEST "kit\vendor\cp312") "..\..\vendor\cp312"
    Chk "раскладка: pure-каталог от kit\runtime\python" `
        (Get-RelPathFrom $RUNTIME_DEST "kit\vendor\py3-none-any") "..\..\vendor\py3-none-any"
    Chk "раскладка: соседний каталог - уровень вверх" (Get-RelPathFrom "kit\a\b" "kit\a\c") "..\c"
    Chk "раскладка: тот же каталог - точка" (Get-RelPathFrom "kit\a" "kit\a") "."
    Chk "раскладка: глубина считается по общему префиксу" `
        (Get-RelPathFrom "kit\runtime\python" "kit\runtime\python\Lib") "Lib"
    $threw = ""
    try { Get-RelPathFrom "C:\kit\a" "kit\a\c" | Out-Null } catch { $threw = $_.Exception.Message }
    # Сверка по двум частям, а не по одному слову: отказ обязан НАЗЫВАТЬ отвергнутый путь. Без
    # имени контроль оставался зелёным при сообщении с литералом {0} (прежний текст именно так
    # и печатал - -f без скобок вокруг склейки привязывается только к последней строке).
    Chk "относительный путь от корневого отвергнут" `
        (($threw -like "*корневой*") -and ($threw -like "*C:\kit\a*") -and ($threw -notlike "*{0}*")) $true
    $pthRoot = Join2 $tmp "pth\kit"
    New-Item -ItemType Directory -Force -Path (Join2 $pthRoot "runtime\python\Lib\encodings") | Out-Null
    Write-NoBom (Join2 $pthRoot "runtime\python\Lib\encodings\__init__.py") "x"
    New-Item -ItemType Directory -Force -Path (Join2 $pthRoot "vendor\py3-none-any\jinja2") | Out-Null
    Write-NoBom (Join2 $pthRoot "vendor\py3-none-any\jinja2\__init__.py") "x"
    $pthExeDir = Join2 $pthRoot "runtime\python"
    # Случай живого пина: файлов ._pth НОЛЬ - это не отказ, дописывать некуда, и PYTHONPATH
    # start.ps1 законен. Контроль обязателен: иначе «пусто» неотличимо от «гейт молчит».
    $p0 = Add-VendorToPth $pthExeDir "cp312"
    Chk "._pth нет - Found=0 и отказа нет" $p0.Found 0
    Chk "._pth нет - дописывать нечего" $p0.Added.Count 0
    $pthFile = Join2 $pthExeDir "python312._pth"
    Write-NoBom $pthFile "python312.zip`r`n.`r`nLib`r`n"
    $p1 = Add-VendorToPth $pthExeDir "cp312"
    Chk "._pth найден" $p1.Found 1
    Chk "._pth: дописаны обе строки вендора" `
        ($p1.Added -join ';') "..\..\vendor\cp312;..\..\vendor\py3-none-any"
    Chk "._pth: прежние строки целы" `
        ([System.IO.File]::ReadAllText($pthFile).Contains("python312.zip`r`n.`r`nLib`r`n")) $true
    Chk "._pth: файл без BOM" ([System.IO.File]::ReadAllBytes($pthFile)[0] -ne [byte]0xEF) $true
    Chk "._pth: итоговых строк стало пять" $p1.Lines 5
    # Идемпотентность: повторная упаковка того же дерева не должна растить ._pth бесконечно.
    $p2 = Add-VendorToPth $pthExeDir "cp312"
    Chk "._pth: повторный прогон ничего не дописывает" $p2.Added.Count 0
    Chk "._pth: повторный прогон не удваивает файл" (Add-VendorToPth $pthExeDir "cp312").Lines $p1.Lines
    # Саботаж: ._pth без строки на Lib - правка отвергается до записи. Без этого контроля уехал бы
    # архив, падающий на «No module named encodings» (прогон kit416), а гейт сборки остался бы зелёным.
    Write-NoBom $pthFile "python312.zip`r`n.`r`n"
    $threw = ""
    try { Add-VendorToPth $pthExeDir "cp312" | Out-Null } catch { $threw = $_.Exception.Message }
    Chk "._pth без stdlib-строки - отказ по имени файла" ($threw -like "*python312._pth*encodings*") $true
    Chk "._pth без stdlib-строки - файл не переписан" `
        ([System.IO.File]::ReadAllText($pthFile).Contains("vendor")) $false
    $threw = ""
    try { Add-VendorToPth $pthExeDir "cp39" | Out-Null } catch { $threw = $_.Exception.Message }
    Chk "._pth: ABI вне ряда отвергается" ($threw -like "*вне ряда*") $true

    # Ветка «._pth нет» для живого пина: прежний вывод «значит, PYTHONPATH start.ps1 законен»
    # означал архив, который на чужой машине падает на «no module named jinja2». Упаковка обязана
    # положить сайдкар .pth в Lib\site-packages. Глубина не на глазка: glm\scripts\kit469_pth_depth.ps1
    # по дереву собранного комплекта даёт rc=0 ровно на четырёх уровнях вверх, на 2/3/5 - красные
    # (site молча пропускает несуществующий путь, поэтому мерка печатала разрешившиеся пути).
    Chk "раскладка: vendor cp312 от Lib\site-packages" `
        (Get-RelPathFrom (Join2 $RUNTIME_DEST $VENDOR_SITE_DIR) "kit\vendor\cp312") `
        "..\..\..\..\vendor\cp312"
    Chk "раскладка: pure-каталог от Lib\site-packages" `
        (Get-RelPathFrom (Join2 $RUNTIME_DEST $VENDOR_SITE_DIR) "kit\vendor\py3-none-any") `
        "..\..\..\..\vendor\py3-none-any"
    $threw = ""
    try { Add-VendorToSitePth $pthExeDir "cp312" | Out-Null } catch { $threw = $_.Exception.Message }
    Chk "сайдкар: без каталога Lib\site-packages отказ по его имени" ($threw -like "*site-packages*") $true
    Chk "сайдкар: без каталога файл не создан" `
        (Test-Path -LiteralPath (Join2 $pthExeDir ($VENDOR_SITE_DIR + '\' + $VENDOR_SITE_PTH))) $false
    $siteDir = Join2 $pthExeDir $VENDOR_SITE_DIR
    New-Item -ItemType Directory -Force -Path $siteDir | Out-Null
    $s1 = Add-VendorToSitePth $pthExeDir "cp312"
    Chk "сайдкар: дописаны обе строки вендора" ($s1.Added -join ';') `
        '..\..\..\..\vendor\cp312;..\..\..\..\vendor\py3-none-any'
    Chk "сайдкар: строк ровно две" $s1.Lines 2
    Chk "сайдкар: файл без BOM" ([System.IO.File]::ReadAllBytes($s1.Path)[0] -ne [byte]0xEF) $true
    Chk "сайдкар: повторный прогон ничего не дописывает" (Add-VendorToSitePth $pthExeDir "cp312").Added.Count 0
    Chk "сайдкар: повторный прогон не растит файл" (Add-VendorToSitePth $pthExeDir "cp312").Lines 2
    $threw = ""
    try { Add-VendorToSitePth $pthExeDir "cp39" | Out-Null } catch { $threw = $_.Exception.Message }
    Chk "сайдкар: ABI вне ряда отвергается" ($threw -like "*вне ряда*") $true
    # Имя сайдкара не имеет права попасть в план обрезки: $RUNTIME_CUT_GLOBS ("Lib\site-packages\pip*")
    # вырезал бы его из уже распакованного дерева, и гейт импорта без PYTHONPATH краснел бы на
    # здоровой сборке - чинить такое пришлось бы вслепую, поэтому условие проверяется напрямую.
    Chk "сайдкар: план обрезки его не вырезает" `
        (@((Get-RuntimeTrimPlan $pthExeDir).Paths -contains ($VENDOR_SITE_DIR + '\' + $VENDOR_SITE_PTH))) $false
    # Механизмы взаимоисключающи: при живом ._pth site выключён, и второй файл в том же дереве -
    # мёртвый груз. Set-VendorResolution обязан выбрать ._pth и НЕ трогать сайдкар.
    Write-NoBom $pthFile "python312.zip`r`n.`r`nLib`r`n"
    Write-NoBom $s1.Path "одна-строка-маркер`r`n"
    $m1 = Set-VendorResolution $pthExeDir "cp312"
    Chk "выбор: ._pth в дереве - режим ._pth" $m1.Mode "._pth"
    Chk "выбор: ._pth в дереве - сайдкар не перезаписан" `
        ([System.IO.File]::ReadAllText($s1.Path).Contains("маркер")) $true
    Chk "выбор: ._pth в дереве - строки дописаны в ._pth" $m1.Pth.Added.Count 2
    Remove-Item -LiteralPath $pthFile -Force
    Remove-Item -LiteralPath $s1.Path -Force
    $m2 = Set-VendorResolution $pthExeDir "cp312"
    Chk "выбор: ._pth удалён - режим site-packages" $m2.Mode "site-packages"
    Chk "выбор: сайдкар создан как новый файл" $m2.Site.Created $true
    Chk "выбор: сайдкар создан с двумя строками" $m2.Site.Lines 2
    Chk "выбор: ._pth-ветка не вернула объекта" $m2.Pth $null

    # Гейт 2 на доливайке: литеры диска в исходниках морды меряются, но законные вхождения
    # отпускаются поимённо И С ЧИСЛОМ СТРОК. Механика проверяется на всех входах списка.
    $h2 = @("kit\serve\server.py: file://C:/x.png", "kit\serve\server.py: y C:\z")
    $wv = Split-StandPathHits $h2 $WEB_STAND_WAIVERS
    Chk "отпуск: ровно названное число находок не красит" $wv.Kept.Count 0
    Chk "отпуск: отпущенное посчитано и напечатано" $wv.Waived.Count 1
    Chk "отпуск: лишняя находка в том же файле красная" `
        (Split-StandPathHits ($h2 + @("kit\serve\server.py: D:\third")) $WEB_STAND_WAIVERS).Drift.Count 1
    Chk "отпуск: недобор находок тоже красный (список устарел)" `
        (Split-StandPathHits @("kit\serve\server.py: только одна") $WEB_STAND_WAIVERS).Drift.Count 1
    Chk "отпуск: путь в не отпущенном файле краснен" `
        (Split-StandPathHits @("kit\models.json: C:\x") $WEB_STAND_WAIVERS).Kept.Count 1
    # Отпуск без срабатывания - просроченный список: файл вычистили, а разрешение осталось, и
    # следующее вхождение пройдёт молча. Мера обязана быть видимой, а не молчаливой.
    Chk "отпуск: неизрасходованный отпуск посчитан" `
        (@($wv.Unused | Where-Object { $_ -like 'kit\serve\telemetry.py*' }).Count) 1
    Chk "отпуск: израсходованный отпуск в просроченных не числится" `
        (@($wv.Unused | Where-Object { $_ -like 'kit\serve\server.py*' }).Count) 0
    Chk "отпуск: пустые находки - весь список просрочен" `
        (Split-StandPathHits @() $WEB_STAND_WAIVERS).Unused.Count $WEB_STAND_WAIVERS.Keys.Count
    Chk "отпуск: ни одной красной строки при пустом входе" `
        ((Split-StandPathHits @() $WEB_STAND_WAIVERS).Kept.Count +
         (Split-StandPathHits @() $WEB_STAND_WAIVERS).Drift.Count) 0
    Chk "список отпусков поименован архивными путями" `
        (@($WEB_STAND_WAIVERS.Keys | Where-Object { $_ -notlike 'kit\*' }).Count) 0
    Chk "список отпусков не дублирует файл" `
        (@($WEB_STAND_WAIVERS.Keys | Sort-Object -Unique).Count) $WEB_STAND_WAIVERS.Keys.Count
    foreach ($w in $WEB_STAND_WAIVERS.Keys) {
        if ([int]$WEB_STAND_WAIVERS[$w].hits -lt 1 -or -not $WEB_STAND_WAIVERS[$w].why) {
            Chk "отпуск $w назван числом >= 1 и причиной" "нет" "да"
        }
    }
    Chk "каждый отпуск назван числом и причиной" "да" "да"
    # Обратная сторона «первой строки»: файл с тремя строками-находками обязан дать три находки,
    # иначе счётчик отпуска нечего было бы сверять (прежняя версия возвращала первую строку).
    $mlDir = Join2 $tmp "multiline"
    New-Item -ItemType Directory -Force -Path $mlDir | Out-Null
    Write-NoBom (Join2 $mlDir "three.py") "a = r'D:\one'`nb = r'E:\two'`nc = 'F:/three'`nd = 'чисто'"
    Chk "все строки с литерой, а не первая" (Get-StandPathHit (Join2 $mlDir "three.py")).Count 3
    Chk "то же самое видит гейт по дереву" (Test-NoStandPaths -Dir $mlDir).Count 3

    # -TextGate по репозиторию: тексты морды меряются ДО компиляции, вторым списком, а по тому же
    # манифесту - иначе перечень разъедется, и гейт станет декоративным.
    $tgSrc2 = Join2 $tmp "tg2"
    New-Item -ItemType Directory -Force -Path $tgSrc2 | Out-Null
    foreach ($f in @("detect.py", "classify.py", "gguf_meta.py", "recommend.py", "models.json",
                     "start.ps1", "START.bat", "README.ru.md", "README.en.md")) {
        Write-NoBom (Join2 $tgSrc2 $f) "переносимо"
    }
    $mmTg = Get-Manifest $cbStrata $cbLlama $tgSrc2 "_" "Q:\нет\cuda" $false $wr ""
    # Ожидаемое число считается по манифесту, а не с потолка: текстовые расширения И файлы, лежащие
    # под одним из двух входных каталогов (меры в -TextGate не меряются - их пути приходятся на
    # -Measures, которого на этом шаге ещё нет).
    $wantTg = @($mmTg.Keys | Where-Object {
        $TEXT_EXT -contains [IO.Path]::GetExtension($_) -and
        (([string]$mmTg[$_]).StartsWith($tgSrc2, [StringComparison]::OrdinalIgnoreCase) -or
         ([string]$mmTg[$_]).StartsWith($wr, [StringComparison]::OrdinalIgnoreCase))
    }).Count
    $tgW = Test-KitSourceTexts -Src $tgSrc2 -Repo $wr
    Chk "-TextGate по репозиторию: меряется ровно текстовая часть манифеста" $tgW.Checked $wantTg
    Chk "-TextGate по репозиторию: 9 файлов комплекта + 14 файлов морды" $tgW.Checked 23
    Chk "-TextGate по репозиторию: на чистом дереве ноль находок" $tgW.Hits.Count 0
    Write-NoBom (Join2 $wr "serve\frontend.py") "log = r'D:\logs\x'`nmm = r'D:\logs\y'"
    $tgW2 = Test-KitSourceTexts -Src $tgSrc2 -Repo $wr
    Chk "-TextGate по репозиторию: находка подписана архивным путём" `
        (@($tgW2.Hits | Where-Object { $_ -like 'kit\serve\frontend.py*' }).Count) 2
    Chk "-TextGate по репозиторию: исходниковый путь репозитория не метка" `
        (@($tgW2.Hits | Where-Object { $_ -like 'serve\frontend.py*' }).Count) 0

    # ABI и пины колёс - тоже носитель истины: cp39/cp310 у regex нет на win_amd64 (замер PyPI
    # 14.11), поэтому набор обязан оставаться ровно cp311..cp315, а pure-каталог - одним.
    Chk "набор ABI ровно cp311..cp315" ($VENDOR_ABIS -join ',') "cp311,cp312,cp313,cp314,cp315"
    Chk "ABI разворачивается в номер Python" (Get-VendorAbiPy "cp313") "313"
    $threw = ""
    try { Get-VendorAbiPy "py3" | Out-Null } catch { $threw = $_.Exception.Message }
    Chk "не-ABI отказывает, а не даёт пустой аргумент" ($threw -like "*не разворачивается*") $true
    Chk "бинарных колёс ровно два (regex, markupsafe)" `
        (@($VENDOR_PKGS | Where-Object { $_.abi -eq "binary" }).Count) 2
    Chk "каждое колесо названо версией" (@($VENDOR_PKGS | Where-Object { -not $_.version }).Count) 0
    $threw = ""
    try { Install-VendorWheels -Out "Q:\нет\Windows" -Py "Q:\нет\python.exe" } catch { $threw = $_.Exception.Message }
    Chk "чужое имя -VendorOut отвергнуто до любой сетевой работы" ($threw -like "*называться vendor*") $true
    $threw = ""
    try { Install-VendorWheels -Out "" -Py "Q:\нет\python.exe" } catch { $threw = $_.Exception.Message }
    Chk "пустой -VendorOut отвергнут" ($threw -like "*VendorOut*") $true
    $threw = ""
    try { Install-VendorWheels -Out (Join2 $tmp "vendor-ok") -Py "Q:\нет\python.exe" } catch { $threw = $_.Exception.Message }
    Chk "несуществующий интерпретатор отвергнут" ($threw -like "*VendorPython*") $true

    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "selftest: ok=$script:ok bad=$script:bad"
    # нижняя граница ЧИСЛА контролей (а не числа пройденных): упавший контроль уже даёт rc=1,
    # а rc=2 означает «мерку урезали» - две разные причины отказа нельзя путать.
    # Фактическое число на 14.11 - 127 (было 89 до доливайки веб-морды); 120 оставлены с запасом
    # на правку, а не на молчание.
    if (($script:ok + $script:bad) -lt 120) {
        Write-Host "ОТКАЗ: контролей меньше 120 - мерка деградировала (проверка не состоялась)"
        exit 2
    }
    if ($script:bad -gt 0) { exit 1 }
    exit 0
}

# ---------------- основной поток ----------------

if ($VendorWheels) {
    # Отдельный режим, а не часть упаковки: скачивание идёт ДО компиляции движков, чтобы отсутствие
    # сети или лимит PyPI стоили прогону секунд, а не двух часов, и чтобы урезанный архив не собрался
    # никогда - без колёс веб-морда на чужой машине не поднимается.
    try {
        $wheels = Install-VendorWheels -Out $VendorOut -Py $VendorPython
    } catch {
        Write-Host "ОТКАЗ: -VendorWheels: $($_.Exception.Message)"
        exit 2
    }
    $wb = [long](@($wheels) | Measure-Object -Property bytes -Sum).Sum
    Write-Host ("колёса: {0} файлов на {1} Б, распаковано в {2}" -f @($wheels).Count, $wb, $VendorOut)
    $venChk = Get-VendorPayload -Stage $VendorOut -Required $true
    Write-Host ("колёса: в архив пойдёт {0} файлов, {1} Б" -f `
                $venChk.Files.Count, ([long](@($venChk.Files.Values) | ForEach-Object { (Get-Item -LiteralPath $_).Length } | Measure-Object -Sum).Sum))
    exit 0
}
if ($TextGate) {
    try {
        $tg = Test-KitSourceTexts -Src $KitSrc -Repo $RepoSrc
    } catch {
        Write-Host "ОТКАЗ: -TextGate: $($_.Exception.Message) - проверка не состоялась"
        exit 2
    }
    if ($tg.Checked -eq 0) {
        Write-Host ("ОТКАЗ: -TextGate: ни одного текстового входа комплекта не мерилось " +
                    "- проверка не состоялась")
        exit 2
    }
    # Гейт присутствия по исходникам: доливайка обязана найти морду ДО компиляции (тот же класс,
    # что стоил репетиции 4454 с: отказ должен приходить до дорогой работы, а не после). Колёса здесь
    # НЕ меряются - их скачивает шаг -VendorWheels, и на шаге гейта сети может не быть; их отсутствие
    # красит упаковку (гейт 4b в основном потоке и в записях zip).
    try {
        $webTg = Get-WebPayload -Repo $RepoSrc -Required $true
    } catch {
        Write-Host "ОТКАЗ: -TextGate: доливайка веб-морды: $($_.Exception.Message) - проверка не состоялась"
        exit 2
    }
    $missTg = @(Test-KitWebPresence @($webTg.Files.Keys) $false)
    if ($missTg) {
        Write-Host ("ОТКАЗ: -TextGate: веб-морда не доедет до архива, отсутствует в исходниках ({0}):" -f `
                    $missTg.Count)
        foreach ($x in $missTg) { Write-Host "      $x" }
        exit 1
    }
    # Гейт 1c здесь же, где и 4b: правило доливайки способно перестать находить модуль, который
    # сервер реально импортирует, и узнать это надо ДО компиляции, а не по логу чужой машины.
    # Разбор идёт по тому же перечню путей, что поедет в архив ($webTg), а не по «папке репозитория».
    try {
        $clTg = Test-ManifestClosure -Repo $RepoSrc -Manifest $webTg.Files `
                                     -Py (Get-AstPython $VendorPython) -Carrier $ClosureCarrier
    } catch {
        Write-Host "ОТКАЗ: -TextGate: гейт замыкания: $($_.Exception.Message) - проверка не состоялась"
        exit 2
    }
    if ($clTg.missing) {
        Write-Host ("ОТКАЗ: -TextGate: манифест отстаёт от замыкания импортов ({0}):" -f $clTg.missing.Count)
        foreach ($x in $clTg.missing) { Write-Host "      нет в архиве: $x" }
        Write-Host '      добавьте путь в $WEB_SPECS (правило по каталогу либо список files)'
        exit 1
    }
    Write-Host ("замыкание импортов {0}: {1} файлов / {2} Б, все названы в перечне (лишних {3})" -f `
                $CLOSURE_ENTRY, $clTg.files, $clTg.bytes, $clTg.extra.Count)
    foreach ($x in $clTg.extra) { Write-Host "      вне замыкания (импорт не найден, файл остаётся): $x" }
    if ($tg.Hits) {
        $tgSplit = Split-StandPathHits $tg.Hits $WEB_STAND_WAIVERS
    } else {
        $tgSplit = Split-StandPathHits @() $WEB_STAND_WAIVERS
    }
    if ($tgSplit.Kept.Count -or $tgSplit.Drift.Count -or $tgSplit.Unused.Count) {
        Write-Host ("ВНИМАНИЕ: в текстах комплекта остались пути стенда ({0}):" -f $tgSplit.Kept.Count)
        foreach ($h in $tgSplit.Kept) { Write-Host "      $h" }
        foreach ($h in $tgSplit.Drift) { Write-Host "      ИЗМЕНЁННЫЙ СПИСОК: $h" }
        foreach ($h in $tgSplit.Unused) { Write-Host "      УСТАРЕВШИЙ ОТПУСК: $h" }
        Write-Host ("текстовые файлы комплекта: проверено {0} файлов, находок {1}, отпущено {2} - компиляция не начата" -f `
                    $tg.Checked, $tgSplit.Kept.Count, $tgSplit.Waived.Count)
        exit 1
    }
    Write-Host ("текстовые файлы комплекта: путей стенда нет, проверено {0} файлов" -f $tg.Checked)
    Write-Host ("   из них долейка веб-морды: {0} файлов, {1} Б ({2} правил)" -f `
                $webTg.Files.Count,
                ([long](@($webTg.Files.Values) | ForEach-Object { (Get-Item -LiteralPath $_).Length } | Measure-Object -Sum).Sum),
                $webTg.Stats.Count)
    foreach ($g in $webTg.Stats.Keys) {
        Write-Host ("   {0,-14} {1,4} файлов {2,9} Б -> {3}" -f $g, $webTg.Stats[$g].files,
                    $webTg.Stats[$g].bytes, $webTg.Stats[$g].archive)
    }
    foreach ($w in $WEB_STAND_WAIVERS.Keys) {
        Write-Host ("   отпуск гейта 2: {0} x{1} - {2}" -f $w, $WEB_STAND_WAIVERS[$w].hits,
                    $WEB_STAND_WAIVERS[$w].why)
    }
    exit 0
}

# Пути - только параметрами. В стендовой версии недостающие каталоги подставлялись от $root,
# выведенного из положения скрипта, и на чужом дереве это давало отказ по несуществующему пути,
# а не сообщение о том, какой параметр не передан. Путь, выведенный из расположения файла, один:
# исходники комплекта лежат соседним каталогом к ci\ внутри того же репозитория, и эта связь
# одинакова на стенде, в Actions и у любого, кто клонирует форк.
foreach ($t in @(
        @{ n = "StrataBuild"; v = $StrataBuild; d = "каталог сборки Страты - это -Out у build_kit.ps1" },
        @{ n = "LlamaBuild";  v = $LlamaBuild;  d = "каталог сборки llama.cpp" },
        @{ n = "Measures";    v = $Measures;    d = "каталог мер: build-measure.json, elf-proof.json, runtime-deps.json" },
        @{ n = "Stage";       v = $Stage;       d = "каталог, под которым раскладывается комплект перед zip" },
        @{ n = "VendorStage"; v = $VendorStage; d = "распакованные колёса веб-морды: шаг pack_kit.ps1 -VendorWheels -VendorOut <этот каталог>" })) {
    if (-not $t.v) {
        Write-Host ("ОТКАЗ: -{0} не передан ({1}) - проверка не состоялась" -f $t.n, $t.d)
        exit 2
    }
}
if (-not $CudaBin) {
    # CUDA-тулчейн берётся из мер сборки: угадывать его путь нельзя, а без него неполный комплект
    # комплектуется молча и «портативность» превращается в требование установить CUDA вручную.
    $bmPath = Join2 $Measures "build-measure.json"
    if (Test-Path -LiteralPath $bmPath) {
        $CudaBin = (Read-JsonNoBom $bmPath "build-measure").cuda
        if ($CudaBin) { $CudaBin = Join2 $CudaBin "bin" }
    }
}
$clash = Test-StageSafe $Measures $Stage
if ($clash) { Write-Host "ОТКАЗ: $clash"; exit 2 }
# Форма stage проверяется до любой дорогой работы: под ним Remove-Item -Recurse -Force, и
# опечатка в аргументе не имеет права сносить чужой каталог. Признак «это наша папка» читается
# по имени и вложенности, потому что привязки к корню стенда в CI-копии больше нет.
$own = Test-StageOwn $Stage
if ($own) { Write-Host ("ОТКАЗ: -Stage '{0}': {1}" -f $Stage, $own); exit 2 }

foreach ($d in @($KitSrc, $Measures)) {
    if (-not (Test-Path -LiteralPath $d)) {
        Write-Host "ОТКАЗ: нет каталога $d - проверка не состоялась"; exit 2
    }
}
$withRuntime = -not $NoCudaRuntime
if ($withRuntime -and (-not $CudaBin -or -not (Test-Path -LiteralPath $CudaBin))) {
    Write-Host "ОТКАЗ: каталог CUDA-тулчейна не задан и не взят из build-measure.json:"
    Write-Host "      без него комплект лишён cublas, а -NoCudaRuntime вы включили явно не поэтому."
    Write-Host "      задайте -CudaBin <путь>\bin либо соберите комплект без CUDA-рантайма: -NoCudaRuntime"
    exit 2
}

# Доливайка меряется до манифеста: пустое правило (каталог переименовали, морду удалили) обязано
# остановить прогон до копирования, а не выродиться в «архив без веб-морды», как это было на
# машине с RTX 5080.
try {
    $webPayload = Get-WebPayload -Repo $RepoSrc -Required $true
    $vendorPayload = Get-VendorPayload -Stage $VendorStage -Required $true
} catch {
    Write-Host "ОТКАЗ: доливайка комплекта: $($_.Exception.Message) - проверка не состоялась"
    exit 2
}
# Автономный интерпретатор (гейт 7) готовится ДО манифеста: Get-Manifest обязан увидеть его дерево
# целиком, иначе перечень архива, гейт 1 («дерево = манифест») и вес разойдутся с тем, что уедет.
# Первым шагом сверяется пин: если packaging\package_terminal.py перепинили, а упаковщик нет,
# в архив пойдёт интерпретатор, которого первоисточник не называет, и provenance перестанет
# доказываться дайджестом. Распаковка и обрезка идут в temp - дерево стенда не трогаем.
$runtimeDir = ""
try {
    $pinSrc = Join2 $RepoSrc "packaging\package_terminal.py"
    $pinChk = Get-PythonPinDiff $pinSrc
    if ($pinChk.Diff) {
        Write-Host ("ОТКАЗ: пин интерпретатора разошёлся с первоисточником {0}:" -f $pinSrc)
        foreach ($d in $pinChk.Diff) { Write-Host "      $d" }
        exit 1
    }
    $cacheDir = Get-PythonCacheDir $RuntimeCache
    $workDir = Join2 ([System.IO.Path]::GetTempPath()) ("strata-packaging-cache\unpack-" +
                    [Guid]::NewGuid().ToString("N").Substring(0, 8))
    $rt = Install-PythonRuntime -Cache $cacheDir -Work $workDir
    $runtimeDir = $rt.Root
} catch {
    Write-Host "ОТКАЗ: автономный интерпретатор: $($_.Exception.Message) - проверка не состоялась"
    exit 2
}
Write-Host (("интерпретатор: пин {0} сверен с packaging\package_terminal.py; носитель {1} Б, " +
             "sha256 {2}; обрезка {3} файлов / {4} Б; в архив {5} файлов / {6} Б ({7} МиБ)") -f
            $PYTHON_ARCH_NAME, $rt.Archive.Bytes, $rt.Archive.Sha256, $rt.Trim.cutFiles,
            $rt.Trim.cutBytes, $rt.Trim.keptFiles, $rt.Trim.keptBytes, (Format-Mib $rt.Trim.keptBytes))
# Корзины печатаются из того же плана, что и обрезка: таблица в комментарии у $RUNTIME_CUT_*
# обязана сверяться с логом, а не жить отдельным замером.
foreach ($k in $rt.Trim.Baskets.Keys) {
    $b = $rt.Trim.Baskets[$k]
    Write-Host ("      обрезка {0}: {1} файлов / {2} Б" -f $k, $b.Files, $b.Bytes)
}
# Печатается исход по файлу, а не одно слово «проверено»: ._pth и сайдкар .pth - разные механизмы,
# и на них держатся разные строки; «ни одного» после Set-VendorResolution быть не может (вторая
# ветка бросает отказ), поэтому молчаливый PYTHONPATH здесь неотличим от поломки.
if ($rt.Mode -eq "._pth") {
    Write-Host ("интерпретатор: ._pth {0} (ABI {1}) - дописано строк {2}: {3}" -f
                ($rt.Pth.Files -join ', '), $rt.Abi.Abi, $rt.Pth.Added.Count, ($rt.Pth.Added -join '; '))
} else {
    Write-Host (("интерпретатор: ._pth рядом с python.exe нет (ABI {0}) - вендор доходит сайдкаром " +
                 "{1} ({2} строк, дописано {3}): {4}") -f $rt.Abi.Abi, $rt.Site.Rel, $rt.Site.Lines,
                $rt.Site.Added.Count, ($rt.Site.Added -join '; '))
}
$manifest = Get-Manifest $StrataBuild $LlamaBuild $KitSrc $Measures $CudaBin $withRuntime `
                         $RepoSrc $VendorStage $false $runtimeDir
if (-not $manifest.Count) { Write-Host "ОТКАЗ: манифест пуст - проверка не состоялась"; exit 2 }

# Гейт 1c по манифесту: ни один модуль, который сервер действительно импортирует, не имеет права
# остаться за спиной у правил доливайки. Недостающий путь красит прогон с именем файла и указанием,
# кто его требует; лишние - только печатаются (правило может нести модуль, который зовут не из
# сервера, а из start.ps1 или CLI).
try {
    $impClosure = Test-ManifestClosure -Repo $RepoSrc -Manifest $manifest `
                                       -Py (Get-AstPython $VendorPython) -Carrier $ClosureCarrier
} catch {
    Write-Host "ОТКАЗ: гейт замыкания: $($_.Exception.Message) - проверка не состоялась"
    exit 2
}
if ($impClosure.missing) {
    Write-Host ("ОТКАЗ: манифест отстаёт от AST-замыкания импортов ({0}):" -f $impClosure.missing.Count)
    foreach ($x in $impClosure.missing) { Write-Host "      нет в архиве: $x" }
    exit 1
}
Write-Host ("гейт замыкания: {0} файлов импортов ({1} Б) названы в манифесте; вне замыкания {2}" -f
            $impClosure.files, $impClosure.bytes, $impClosure.extra.Count)
foreach ($x in $impClosure.extra) { Write-Host "      вне замыкания (остаётся по правилу): $x" }

# Гейт 4b по манифесту: то, чего нет уже в перечне, не доедет и в архив, но ждать копии незачем.
$missManifest = @(Test-KitWebPresence @($manifest.Keys) $true)
if ($missManifest) {
    Write-Host ("ОТКАЗ: гейт присутствия (манифест): в комплект не заявлено ({0}):" -f $missManifest.Count)
    foreach ($x in $missManifest) { Write-Host "      $x" }
    exit 1
}
# Гейт 7 по манифесту: веб-морда без интерпретатора - папка с файлами, поэтому отсутствие exe
# отказывает так же, как отсутствие страницы.
$missRtManifest = @(Test-KitRuntimePresence @($manifest.Keys))
if ($missRtManifest) {
    Write-Host ("ОТКАЗ: гейт присутствия (манифест): автономного интерпретатора нет ({0}):" -f `
                $missRtManifest.Count)
    foreach ($x in $missRtManifest) { Write-Host "      $x" }
    exit 1
}
Write-Host (("гейт присутствия: манифест называет {0} обязательных путей морды, {1} каталога ABI и " +
             "{2} пути интерпретатора") -f $KIT_PRESENCE.Count, ($VENDOR_ABIS.Count + 1),
            $RUNTIME_PRESENCE.Count)

# Полноту набора меряют до раскладки: потерянный LoadLibrary-модуль не роняет сборку и не
# виден в импорт-таблицах, а на машине пользователя молча меняет маршрут на FP16.
try { $closure = Test-BinClosure $StrataBuild $LlamaBuild $manifest } catch {
    Write-Host "ОТКАЗ: $($_.Exception.Message) - полнота набора не измерена, проверка не состоялась"
    exit 2
}
if ($closure.orphan) {
    Write-Host ("ОТКАЗ: сборка произвела, а комплект не берёт ({0}): {1}" -f `
        $closure.orphan.Count, ($closure.orphan -join ', '))
    Write-Host "      либо добавьте файл в Get-Manifest, либо в `$BIN_WAIVERS с причиной"
    exit 2
}
Write-Host ("полнота набора: произведено {0} exe/dll, в bin\ манифеста {1}, отпуск {2}" -f `
    $closure.produced.Count, $closure.inKit.Count, $BIN_WAIVERS.Count)

# Отсутствие файла - это отказ, а не «упакуем что есть»: половину комплекта можно терять молча,
# и обнаружит это пользователь на чужой машине.
$absent = @()
foreach ($k in $manifest.Keys) { if (-not (Test-Path -LiteralPath $manifest[$k])) { $absent += $k } }
if ($absent) {
    Write-Host ("ОТКАЗ: нет обязательных файлов ({0}): {1}" -f $absent.Count, ($absent -join ', '))
    Write-Host "      сначала -Engines strata,llama в build_kit.ps1: файлы создаёт сборка"
    exit 2
}

if ($Version) {
    $ver = $Version
} else {
    $bm = Read-JsonNoBom (Join2 $Measures "build-measure.json") "build-measure"
    if (-not $bm.started) { Write-Host "ОТКАЗ: в build-measure.json нет started - версию взять неоткуда"; exit 2 }
    $ver = ([datetime]$bm.started).ToString("yyyy-MM-dd")
}
if (-not $Zip) {
    # Имя архива собирается из каталога мер - он пришёл параметром, - и версии: никакого пути,
    # выведенного из положения скрипта или из корня стенда.
    $Zip = Join2 (Split-Path -Parent $Measures) ("gpu-infer-kit-" + $ver + ".zip")
}

Write-Host "комплект: $Stage ($($manifest.Count) файлов, версия $ver)"
# Форма stage проверена до манифеста (Test-StageOwn), поэтому здесь остаётся только пересоздать
# своё дерево.
if (Test-Path -LiteralPath $Stage) { Remove-Item -LiteralPath $Stage -Recurse -Force }
$rcGate = 0
foreach ($k in $manifest.Keys) {
    $dst = Join2 $Stage $k
    $dir = Split-Path -Parent $dst
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    if ($k -in $SIDECARS) {
        # Мера стенда и копия меры для чужой машины - разные документы: числа и архитектуры
        # остаются, пути стенда вычищаются (иначе либо красный гейт, либо чужая машина в тексте).
        $obj = Remove-StandPaths (Read-JsonNoBom $manifest[$k] $k)
        [System.IO.File]::WriteAllText($dst, ($obj | ConvertTo-Json -Depth 12),
                                       (New-Object System.Text.UTF8Encoding($false)))
    } else {
        Copy-Item -LiteralPath $manifest[$k] -Destination $dst -Force
    }
}

# Гейт 1: дерево совпадает с манифестом поимённо - ни лишнего, ни потерянного при копировании.
$tree = Get-KitFiles -Dir $Stage
$treeNames = @($tree | ForEach-Object { $_.FullName.Substring($Stage.Length).TrimStart('\', '/').Replace('/', '\') })
$extra = @($treeNames | Where-Object { -not $manifest.Contains($_) })
if ($extra) {
    Write-Host ("ВНИМАНИЕ: в дереве есть лишнее ({0}): {1}" -f $extra.Count, ($extra -join ', '))
    $rcGate = 1
}
if ($treeNames.Count -ne $manifest.Count) {
    Write-Host "ВНИМАНИЕ: файлов $($treeNames.Count) при манифесте $($manifest.Count) - копирование прошло не полностью"
    $rcGate = 1
}

# Гейт 2: переносимость. Отпускаются только поимённые строки в поименованных файлах исходников
# морды ($WEB_STAND_WAIVERS), и то по числу находок: любая сверх названного - красным.
$hits = @(Test-NoStandPaths -Dir $Stage)
$split = Split-StandPathHits $hits $WEB_STAND_WAIVERS
if ($split.Waived.Count) {
    foreach ($w in $split.Waived) { Write-Host "      отпуск (посчитан): $w" }
}
if ($split.Unused.Count) {
    # Просроченный отпуск нарушает гигиену списка, а не переносимость архива: путь из файла уже
    # исчез. Красить после полной компиляции - значит платить 1,5 часа за запись в комментарии,
    # поэтому список вычищает -TextGate ДО сборки; здесь находка печатается.
    foreach ($u in $split.Unused) { Write-Host "      СПИСОК УСТАРЕЛ (его меряет -TextGate): $u" }
}
if ($split.Kept.Count -or $split.Drift.Count) {
    Write-Host ("ВНИМАНИЕ: в комплекте остались пути стенда ({0}):" -f $split.Kept.Count)
    foreach ($h in $split.Kept) { Write-Host "      $h" }
    foreach ($h in $split.Drift) { Write-Host "      ИЗМЕНЁННЫЙ СПИСОК: $h" }
    $rcGate = 1
} else {
    Write-Host (("переносимость: путей стенда в текстовых файлах нет ({0} файлов, отпущено {1}, " +
                 "не мерялось {2} файлов дерева интерпретатора)") -f `
                (Get-KitFiles -Dir $Stage).Count, $split.Waived.Count, $script:PortabilitySkipped)
}

# Гейт 4b по дереву раскладки: копирование могло проглотить файл (права, длинный путь, антивирус),
# и «в манифесте названо» не равно «лежит в архиве».
$missTree = @(Test-KitWebPresence $treeNames $true)
if ($missTree) {
    Write-Host ("ОТКАЗ: гейт присутствия (дерево stage): нет ({0}):" -f $missTree.Count)
    foreach ($x in $missTree) { Write-Host "      $x" }
    $rcGate = 1
}
# Гейт 7 по дереву: 772 файла интерпретатора копируются тем же циклом, что и остальное, и
# отсутствие exe после копирования - это ровно тот же класс, что проглоченный копированием
# server.py: манифест его называет, а в архиве его нет.
$missRtTree = @(Test-KitRuntimePresence $treeNames)
if ($missRtTree) {
    Write-Host ("ОТКАЗ: гейт присутствия (дерево stage): автономного интерпретатора нет ({0}):" -f `
                $missRtTree.Count)
    foreach ($x in $missRtTree) { Write-Host "      $x" }
    $rcGate = 1
} else {
    # Контроль того, что морда поднимется именно этим интерпретатором и именно по тому PYTHONPATH,
    # который соберёт start.ps1: запуск дерева В РАСКЛАДКЕ (kit\vendor рядом с kit\runtime), а не
    # дерева сборки. Печатается факт: ABI, версия, собранный путь и rc импорта jinja2 + regex.
    try {
        $probe = Invoke-RuntimeProbe (Join2 $Stage "kit\runtime\python\python.exe") (Join2 $Stage "kit")
    } catch {
        Write-Host "ОТКАЗ: гейт интерпретатора: $($_.Exception.Message) - проверка не состоялась"
        exit 2
    }
    if ($probe.Rc -ne 0) {
        Write-Host ("ВНИМАНИЕ: интерпретатор комплекта не импортирует '{0}' (rc={1}): {2}" -f `
                    $RUNTIME_VENDOR_IMPORTS, $probe.Rc, $probe.Out)
        $rcGate = 1
    }
    Write-Host ("интерпретатор: {0} ({1}) импортирует {2} по PYTHONPATH {3} - rc={4}" -f
                "kit\runtime\python\python.exe", $probe.Version, $RUNTIME_VENDOR_IMPORTS,
                $probe.Path, $probe.Rc)
    # Второй срез - обратный: тот же exe в той же раскладке, но БЕЗ PYTHONPATH. Это ровно то, что
    # получит пользователь: переменную окружения на чужой машине никто не обязан ставить, а при ._pth
    # интерпретатор игнорирует её молча. Зелёный rc здесь - единственное доказательство, что морда
    # поднимется не только на сборочном раннере; раньше прогон делался только при ._pth, и ветка
    # «._pth нет» уезжала зелёной ровно тем дефектом, который теперь краснеет.
    $pthStage = @(Get-PthFiles (Join2 $Stage "kit\runtime\python"))
    $siteStage = Join2 $Stage ("kit\runtime\python\" + $VENDOR_SITE_DIR + "\" + $VENDOR_SITE_PTH)
    $mech = if ($pthStage.Count) { ("._pth {0}" -f (($pthStage | ForEach-Object { $_.Name }) -join ', ')) }
            elseif (Test-Path -LiteralPath $siteStage -PathType Leaf) { $rt.Site.Rel }
            else { "ни ._pth, ни сайдкара .pth" }
    $probePth = Invoke-RuntimeProbe (Join2 $Stage "kit\runtime\python\python.exe") `
                                    (Join2 $Stage "kit") $false
    if ($probePth.Rc -ne 0) {
        Write-Host (("ОТКАЗ: гейт интерпретатора: импорт {0} БЕЗ PYTHONPATH вернул rc={1}: {2} - " +
                     "механизм в дереве раскладки: {3}; на машине пользователя морда упадёт на " +
                     "«no module named jinja2», и объяснить это, кроме упаковки, будет нечем") -f
                    $RUNTIME_VENDOR_IMPORTS, $probePth.Rc, $probePth.Out, $mech)
        $rcGate = 1
    } else {
        Write-Host (("интерпретатор: {0} замкнут на вендор - импорт {1} без PYTHONPATH rc=0 " +
                     "(строк в файле {2}, дописано {3}: {4})") -f $mech, $RUNTIME_VENDOR_IMPORTS,
                    $(if ($pthStage.Count) { $rt.Pth.Lines } else { $rt.Site.Lines }),
                    $(if ($pthStage.Count) { $rt.Pth.Added.Count } else { $rt.Site.Added.Count }),
                    $(if ($pthStage.Count) { $rt.Pth.Added -join '; ' } else { $rt.Site.Added -join '; ' }))
    }
    $smoke = Invoke-RuntimeSmoke (Join2 $Stage "kit\runtime\python\python.exe")
    if ($smoke.Rc -ne 0) {
        Write-Host (("ВНИМАНИЕ: stdlib-набор после обрезки не импортируется целиком (rc={0}, модулей " +
                     "заявлено {1}): {2}") -f $smoke.Rc, $smoke.Modules, $smoke.Out)
        $rcGate = 1
    } else {
        Write-Host ("интерпретатор: stdlib-набор замыкания импортируется, модулей {0} - rc=0" -f
                    $smoke.Modules)
    }
}

# Гейт 3-4: сайдкары читаемы и доказательны.
$elf = Read-JsonNoBom (Join2 $Stage "elf-proof.json") "elf-proof"
$deps = Read-JsonNoBom (Join2 $Stage "runtime-deps.json") "runtime-deps"
$bm = Read-JsonNoBom (Join2 $Stage "build-measure.json") "build-measure"
$want = @($elf.want_archs)
# Обёртка (llama-server.exe - 10 КиБ, весь CUDA-код в ggml-cuda.dll) fatbin не несёт физически.
# Требовать от неё покрытия архитектур значит иметь всегда красный гейт на удачной сборке;
# носители помечены carries_cuda в сайдкаре, а заодно пустой список носителей - это «доказательства
# нет», а не «доказывать нечего».
$payloads = @($elf.binaries | Where-Object { $_.carries_cuda -ne $false })
if (-not $payloads) {
    Write-Host "ВНИМАНИЕ: в elf-proof.json нет ни одного носителя CUDA-кода - универсальность не доказана"
    $rcGate = 1
}
# sm_120a — тот же cc 12.0 в архитектурно-специфичной форме; классификатор комплекта
# сворачивает суффикс (arch_code), и гейт упаковки обязан мерить так же. Иначе удачная сборка
# 120a навсегда красит архив: ggml-cuda.dll 10.11 несёт sm_120a, а не буквальный sm_120.
function Get-ArchCode([string]$a) { if ($a -match '^sm_(\d+)') { return $Matches[1] } return $a }
foreach ($b in $payloads) {
    $have = @($b.cubin_archs | ForEach-Object { Get-ArchCode $_ } | Select-Object -Unique)
    $missingArch = @($want | Where-Object { (Get-ArchCode $_) -notin $have })
    if ($missingArch) {
        Write-Host ("ВНИМАНИЕ: {0}: нет cubin для {1} (в файле: {2}) - универсальность не доказана" -f `
                    $b.label, ($missingArch -join ','), (@($b.cubin_archs) -join ','))
        $rcGate = 1
    }
}
Write-Host ("elf-proof: архитектур заявлено {0}, носителей CUDA-кода {1} из {2} бинарников" -f `
            $want.Count, $payloads.Count, @($elf.binaries).Count)
if (@($deps.missing).Count) {
    Write-Host ("ВНИМАНИЕ: зависимости не замкнуты: {0}" -f (@($deps.missing) -join '; '))
    $rcGate = 1
}
if ($withRuntime) {
    foreach ($lib in @($deps.cuda_runtime_to_copy)) {
        if (-not (Test-Path -LiteralPath (Join2 $Stage ("bin\" + $lib.name)))) {
            Write-Host "ВНИМАНИЕ: $lib.name нужна по замеру импортов, в комплекте её нет"
            $rcGate = 1
        }
    }
}
if ($bm.result -and $bm.result -ne "собрано и доказано") {
    Write-Host "ВНИМАНИЕ: build-measure.json говорит '$($bm.result)' - в комплект идёт недоказанная сборка"
    $rcGate = 1
}

# Гейт 5: zip открывается, записей столько же, моделей внутри нет.
$zipDir = Split-Path -Parent $Zip
if (-not (Test-Path -LiteralPath $zipDir)) { New-Item -ItemType Directory -Force -Path $zipDir | Out-Null }
if (Test-Path -LiteralPath $Zip) { Remove-Item -LiteralPath $Zip -Force }
[System.IO.Compression.ZipFile]::CreateFromDirectory($Stage, $Zip,
    [System.IO.Compression.CompressionLevel]::Optimal, $false)
$check = [System.IO.Compression.ZipFile]::OpenRead($Zip)
try {
    $names = @($check.Entries | ForEach-Object { $_.FullName.Replace('/', '\') })
    $gguf = @($names | Where-Object { $_ -like '*.gguf' })
    $badInZip = @($names | Where-Object { $_ -match '__pycache__|\\run\\|\.log$|\.jsonl$|\.pyc$' })
} finally { $check.Dispose() }
if ($gguf) { Write-Host ("ВНИМАНИЕ: в архив попали модели: {0}" -f ($gguf -join ', ')); $rcGate = 1 }
if ($badInZip) { Write-Host ("ВНИМАНИЕ: мусор в архиве: {0}" -f ($badInZip -join ', ')); $rcGate = 1 }
if ($names.Count -ne $manifest.Count) {
    Write-Host ("ВНИМАНИЕ: в zip {0} записей при манифесте {1}" -f $names.Count, $manifest.Count)
    $rcGate = 1
}
# Гейт 4b по ЗАПИСЯМ АРХИВА: именно это пользователь получит на своей машине. Механика list/формат
# уже есть в verify_zip.sh (там сигнатуры PK\3\4 и EOCD и нормализованный листинг), и она не
# ослабляется - здесь добавляется верхний слой: названные пути морды и колёс.
$missZip = @(Test-KitWebPresence $names $true)
if ($missZip) {
    Write-Host ("ОТКАЗ: гейт присутствия (записи zip): в архиве нет ({0}):" -f $missZip.Count)
    foreach ($x in $missZip) { Write-Host "      $x" }
    $rcGate = 1
} else {
    Write-Host ("гейт присутствия: веб-морда и {0} ABI-каталога колёс в архиве на месте" -f `
                ($VENDOR_ABIS.Count + 1))
}

# Гейт 6: вес, и он же - фактические доли печати по группам (приёмка меряется числами).
function Get-GroupBytes([string[]]$Keys) {
    $b = [long]0
    foreach ($k in $Keys) {
        $p = Join2 $Stage $k
        if (Test-Path -LiteralPath $p) { $b += (Get-Item -LiteralPath $p).Length }
    }
    return $b
}
function Get-GroupKeys([string]$Prefix) {
    return @($manifest.Keys | Where-Object { $_.StartsWith($Prefix, [StringComparison]::OrdinalIgnoreCase) })
}
$groups = [ordered]@{
    "bin (движки)"        = "bin\"
    "kit (обвязка)"       = "KIT_OWN"
    "kit\serve (морда)"   = "kit\serve\"
    "kit\tools"           = "kit\tools\"
    "kit\strata_control"  = "kit\strata_control\"
    "kit\strata_cli"      = "kit\strata_cli\"
    "kit\vendor (колёса)" = "kit\vendor\"
    "kit\runtime (питон)" = "kit\runtime\"
    "START.bat + меры"    = "START.bat"
}
$kitOwn = @($manifest.Keys | Where-Object {
    $_.StartsWith("kit\", [StringComparison]::OrdinalIgnoreCase) -and
    -not $_.StartsWith("kit\serve\", [StringComparison]::OrdinalIgnoreCase) -and
    -not $_.StartsWith("kit\tools\", [StringComparison]::OrdinalIgnoreCase) -and
    -not $_.StartsWith("kit\strata_control\", [StringComparison]::OrdinalIgnoreCase) -and
    -not $_.StartsWith("kit\strata_cli\", [StringComparison]::OrdinalIgnoreCase) -and
    -not $_.StartsWith("kit\vendor\", [StringComparison]::OrdinalIgnoreCase) -and
    -not $_.StartsWith("kit\runtime\", [StringComparison]::OrdinalIgnoreCase) })
$payloadTable = [ordered]@{}
foreach ($g in $groups.Keys) {
    $keys = if ($groups[$g] -eq "KIT_OWN") { $kitOwn } else { Get-GroupKeys $groups[$g] }
    $payloadTable[$g] = [ordered]@{ files = $keys.Count; bytes = (Get-GroupBytes $keys) }
}
$webAdded = [long]0; $webFiles = 0
foreach ($g in @("kit\serve (морда)", "kit\tools", "kit\strata_control", "kit\strata_cli")) {
    $webAdded += $payloadTable[$g].bytes; $webFiles += $payloadTable[$g].files
}
$vendorAdded = $payloadTable["kit\vendor (колёса)"].bytes
$runtimeAdded = $payloadTable["kit\runtime (питон)"]
Write-Host "доли в архиве (фактические байты дерева stage):"
foreach ($g in $payloadTable.Keys) {
    Write-Host ("   {0,-22} {1,4} файлов {2,10} Б  ({3} МиБ)" -f $g, $payloadTable[$g].files,
                $payloadTable[$g].bytes, (Format-Mib $payloadTable[$g].bytes))
}
Write-Host "доливайка веб-морды по правилам -RepoSrc:"
foreach ($g in $webPayload.Stats.Keys) {
    Write-Host ("   {0,-14} {1,4} файлов {2,10} Б -> {3}" -f $g, $webPayload.Stats[$g].files,
                $webPayload.Stats[$g].bytes, $webPayload.Stats[$g].archive)
}
Write-Host "колёса по ABI (-VendorStage):"
foreach ($g in $vendorPayload.Stats.Keys) {
    Write-Host ("   {0,-22} {1,4} файлов {2,10} Б" -f $g, $vendorPayload.Stats[$g].files,
                $vendorPayload.Stats[$g].bytes)
}
Write-Host ("   итого веб-морда {0} файлов / {1} Б, колёса {2} файлов / {3} Б" -f `
            $webFiles, $webAdded, $payloadTable["kit\vendor (колёса)"].files, $vendorAdded)
$treeBytes = Get-TreeBytes $Stage
$zipBytes = (Get-Item -LiteralPath $Zip).Length
$weight = [ordered]@{
    version = $ver
    files = $manifest.Count
    with_cuda_runtime = $withRuntime
    tree_bytes = $treeBytes
    tree_mib = Format-Mib $treeBytes
    zip_bytes = $zipBytes
    zip_mib = Format-Mib $zipBytes
    cuda_runtime_bytes = [long]($deps.cuda_runtime_to_copy_bytes)
    entries_in_zip = $names.Count
    web_payload = [ordered]@{ files = $webFiles; bytes = $webAdded
                              groups = $webPayload.Stats }
    vendor_payload = [ordered]@{ files = $payloadTable["kit\vendor (колёса)"].files
                                 bytes = $vendorAdded
                                 groups = $vendorPayload.Stats
                                 abis = $VENDOR_ABIS
                                 pure_abi = $VENDOR_PURE_ABI
                                 pinned = @($VENDOR_PKGS | ForEach-Object { "$($_.name)==$($_.version)" }) }
    runtime_payload = [ordered]@{
        files = $runtimeAdded.files; bytes = $runtimeAdded.bytes
        archive = $RUNTIME_DEST
        pin = [ordered]@{ release = $PBS_RELEASE; version = $PYTHON_VERSION; target = $PYTHON_TARGET
                         file = $PYTHON_ARCH_NAME; sha256 = $PYTHON_ARCH_SHA256
                         exe = $PYTHON_ARCH_EXE
                         source = "packaging\package_terminal.py (PBS_RELEASE, PYTHON_VERSION, PYTHON_PINS)" }
        archive_bytes = $rt.Archive.Bytes
        cut = [ordered]@{ files = $rt.Trim.cutFiles; bytes = $rt.Trim.cutBytes }
        unpacked = [ordered]@{ files = $rt.Trim.allFiles; bytes = $rt.Trim.allBytes }
        ballast_mib_saved = (Format-Mib $rt.Trim.cutBytes)
        presence = @($RUNTIME_PRESENCE.path)
        probe = [ordered]@{ abi = $probe.Abi; version = $probe.Version; pythonpath = $probe.Path
                            rc = $probe.Rc; imports = $RUNTIME_VENDOR_IMPORTS }
        smoke_rc = $smoke.Rc; smoke_modules = $smoke.Modules
    }
    gate = if ($rcGate -eq 0) { "зелёные" } else { "есть провалы" }
}
[System.IO.File]::WriteAllText((Join2 $Measures "kit-weight.json"),
    ($weight | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("вес: дерево {0} МиБ, zip {1} МиБ, CUDA-рантайм {2} МиБ, файлов {3}" -f `
            $weight.tree_mib, $weight.zip_mib, (Format-Mib ([long]$deps.cuda_runtime_to_copy_bytes)), $manifest.Count)
Write-Host "архив: $Zip"
Write-Host "меры веса: $(Join2 $Measures 'kit-weight.json')"
if ($rcGate -ne 0) { Write-Host "ИТОГ: гейты упаковки упали - архив считать готовым нельзя"; exit 1 }
Write-Host "ИТОГ: комплект упакован, гейты зелёные"
exit 0
