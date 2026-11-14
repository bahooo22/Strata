#Requires -Version 5.1
<#
    Единственная точка входа портативного комплекта: измерить железо -> сказать класс ->
    подобрать окно и параметры -> запустить. Только Windows PowerShell 5.1: он есть на любой
    Windows, pwsh 7 - нет.

        START.bat                          спросить путь к .gguf и всё сделать
        START.bat .\models\model.gguf      то же без вопроса
        START.bat a.gguf -DryRun           напечатать строку запуска и НЕ запускать
        START.bat a.gguf -Yes              не спрашивать разрешения на запуск
        START.bat a.gguf -Engine llama     запретить выбор движка
        START.bat a.gguf -Window 131072    проверить конкретное окно вместо максимума
        START.bat a.gguf                   без -Engine спросит, какой сервер поднимать, если
                                           подбор дал больше одного движка
        START.bat -FakeConfig 16g.json -Gguf a.gguf -DryRun   чужое железо без смены железа

    Коды возврата: 0 - запущено (или напечатано для -DryRun); 1 - запущено с предупреждениями;
    2 - вход неверен или считать неоткуда (нет Python, нет bin\, битый GGUF, окно не влезает).
#>
[CmdletBinding()]
param(
    [string]$Gguf = "",
    [string]$Engine = "auto",
    [int]$Window = 0,
    [string]$FakeConfig = "",
    [string]$Python = "",
    [string]$ExeStrata = "",
    [string]$ExeLlama = "",
    [int]$StartTimeoutSec = 900,
    [switch]$DryRun,
    [switch]$Yes,
    [switch]$NoBrowser
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$root = Split-Path -Parent $MyInvocation.MyCommand.Path

function Fail([string]$msg, [int]$rc) {
    Write-Host "[FAIL] $msg"
    exit $rc
}

# Windows PowerShell 5.1 отдаёт код выхода процесса, заведённого через Start-Process -PassThru
# БЕЗ -Wait, только если у объекта включено уведомление о выходе: без $proc.EnableRaisingEvents
# свойство ExitCode молча пустое (не исключение!), и живой отказ печатался как «сервер не
# поднялся (код )». Замер 14.11 зондом на `cmd /c exit 7` при запуске без -Wait: ExitCode как
# есть - пусто; коснуться $proc.Handle - пусто; WaitForExit() после HasExited - пусто;
# EnableRaisingEvents=$true сразу после старта - 7; он же плюс WaitForExit() - 7. У живого
# процесса HasExited ложен и код недоступен - поэтому «недоступен» остаётся честным ответом
# для случая, когда процесс ещё жив или обход не сработал: это не «код 0» и не «кода нет».
function Get-ProcExitCode($p) {
    if (-not $p.HasExited) { return $null }
    try { $p.WaitForExit() } catch { }
    $code = $p.ExitCode
    # Сверяем наличие значения с типом, а не через -eq '': в 5.1 `0 -eq ''` истинно, и честный
    # код 0 (так уходит, например, питоновый сервер, которому не хватило файла конфигурации)
    # превращался в «код недоступен». Пустое свойство без уведомления о выходе - строка пустая.
    if ($null -eq $code) { return $null }
    if ($code -isnot [int] -and ([string]$code) -eq '') { return $null }
    return $code
}

# Раскладка комплекта и дерева стенда различаются одним уровнем (kit\ лежит рядом с bin\
# в архиве и сам является $root при запуске из исходников), поэтому каталог ищется, а не
# зашивается: зашить - значит выдать одну рабочую раскладку за единственно возможную.
function Resolve-Kit {
    foreach ($c in @((Join-Path $root "kit"), $root)) {
        if (Test-Path -LiteralPath (Join-Path $c "recommend.py")) { return $c }
    }
    Fail "recommend.py не найден; просмотрено: $(Join-Path $root 'kit') | $root" 2
}

function Resolve-Bin {
    foreach ($c in @((Join-Path $root "bin"), (Join-Path $kit "bin"), (Join-Path $root "..\bin"))) {
        if (Test-Path -LiteralPath $c) { return (Resolve-Path -LiteralPath $c).Path }
    }
    return ""
}

function Find-Python {
    # Приоритет - автономный интерпретатор комплекта: докачанный `kit\runtime\python\python.exe`
    # обязан побеждать системный Python, иначе на машине с установленным Python сервер запустился
    # бы им, а колёса в vendor\ под его ABI могли и не лечь (раскладку задаёт pack_kit.ps1:128).
    # Путь - от $kit, как у bin\ выше: раскладка архива и дерева стенда различаются одним
    # уровнем, поэтому каталог ищется, а не зашивается.
    $runtime = Join-Path $kit "runtime\python\python.exe"
    if (Test-Path -LiteralPath $runtime -PathType Leaf) { return $runtime }
    if ($Python) {
        if (Get-Command $Python -ErrorAction SilentlyContinue) { return $Python }
        if (Test-Path -LiteralPath $Python) { return $Python }
        Fail "python не найден: $Python (автономного интерпретатора $runtime тоже нет)" 2
    }
    foreach ($c in @("python", "py")) {
        if (Get-Command $c -ErrorAction SilentlyContinue) { return $c }
    }
    # Список мест - фактический, а обещанная версия - та, которую проверяет гейт колёс ниже
    # (3.11-3.15 = ряд $VENDOR_ABIS), а не «3.10+» из прежнего текста.
    $tried = @("автономный интерпретатор комплекта $runtime")
    if ($Python) { $tried += "указанный -Python «$Python»" }
    $tried += "в PATH как python и как py"
    Fail ("python не найден; искали: " + ($tried -join '; ') + ". На нём считаются окно и " +
          "параметры, им же поднимается веб-морда Страты: докачайте kit\runtime\python\ " +
          "или поставьте CPython 3.11-3.15 (под него собраны колёса vendor\)") 2
}

function Quote-Arg([string]$a) {
    if ($a -match '[\s"]') { return '"' + ($a -replace '"', '\"') + '"' }
    return $a
}

function Invoke-Kit([string[]]$kitArgs) {
    # Отдельная область с ErrorActionPreference=Continue: под Stop чужая stderr-строка
    # (ОТКАЗ detect.py, [FAIL] recommend.py) превращалась в terminating NativeCommandError,
    # прогон обрывался с rc=1 вместо обещанных в шапке 2, а причина тонула в CategoryInfo-шуме.
    $ErrorActionPreference = 'Continue'
    $lines = & $py @kitArgs 2>&1
    $code = $LASTEXITCODE
    foreach ($line in $lines) { Write-Host ([string]$line) }
    return $code
}

# ---- помощники Страта-ноги и меню выбора сервера -------------------------------
function Engine-Label([string]$e) {
    switch ($e) {
        'llama'  { return 'llama.cpp' }
        'strata' { return 'Страта' }
        default  { return $e }
    }
}

# Один базис вместо двух: сервер резолвит "exe" конфига от cfg["cwd"] (serve/server.py:10353),
# а "tokenizer" и "log" - от рабочей папки процесса (:10255, :10325). Относительные пути в
# одном конфиге разъехались бы по разным базам, поэтому в strata.json пишутся абсолютные.
function Get-AbsPath([string]$p, [string]$base) {
    if (-not $p) { return "" }
    if ([System.IO.Path]::IsPathRooted($p)) { return [System.IO.Path]::GetFullPath($p) }
    return [System.IO.Path]::GetFullPath((Join-Path $base $p))
}

# Свойства конфига может не быть: присваивание несуществующему свойству PSCustomObject в 5.1
# бросает исключение, поэтому недостающее имя добавляем через Add-Member.
function Set-CfgProp($obj, [string]$name, $value) {
    if ($obj.PSObject.Properties.Name -contains $name) { $obj.$name = $value }
    else { $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value | Out-Null }
}

# Относительный exe сервер склеивает со своим cwd, но в раскладке архива бинарники лежат не в
# kit\, а в ../bin от него, поэтому собираем сами: сначала настоящий bin\ (его уже нашёл
# Resolve-Bin), затем leaf в нём, затем базовый каталог.
function Resolve-StrataExe([string]$p, [string]$base) {
    if (-not $p) { return "" }
    if ($p.StartsWith('component:')) { return $p }   # ссылку на пакет движка разворачивает сервер
    if ([System.IO.Path]::IsPathRooted($p)) { return [System.IO.Path]::GetFullPath($p) }
    if ($binDir) {
        foreach ($cand in @((Join-Path $binDir $p), (Join-Path $binDir (Split-Path -Leaf $p)), (Join-Path $base $p))) {
            if (Test-Path -LiteralPath $cand) { return [System.IO.Path]::GetFullPath($cand) }
        }
    }
    return [System.IO.Path]::GetFullPath((Join-Path $base $p))
}

# Строка ввода, которую не ломает перенаправленный stdin: Read-Host в 5.1 с трубой на входе
# ответа не отдаёт, а отсутствие консоли вообще бросается исключением.
function Read-KitLine([string]$prompt) {
    try {
        if ([Console]::IsInputRedirected) { return [Console]::In.ReadLine() }
        return Read-Host $prompt
    } catch { return $null }
}

# Вопрос «какой сервер поднять». Варианты берутся из alternatives подбора: у одного движка там
# может быть несколько ступенек лесенки, а решаем мы именно по движку. Рекомендованное
# подбором всегда под номером 1 и берётся на пустой Enter; нечитаемый ввод (stdin закрыт,
# консоли нет) молча отдаёт рекомендованное - падать здесь не на что.
function Select-Engine($rec) {
    $best = ([string]$rec.engine).Trim()
    if (-not $best) { return "" }
    $rest = @()
    foreach ($a in @($rec.alternatives)) {
        $e = ([string]$a.engine).Trim()
        if ($e -and $e -ne $best -and -not ($rest -contains $e)) { $rest += $e }
    }
    if ($rest.Count -lt 1) { return $best }
    $opts = @($best) + $rest
    Write-Host ""
    Write-Host "Какой сервер поднять?"
    for ($i = 0; $i -lt $opts.Count; $i++) {
        $w = ''
        foreach ($a in @($rec.alternatives)) {
            if (([string]$a.engine) -eq $opts[$i] -and -not $w) { $w = $a.window }
        }
        $tag = if ($i -eq 0) { " (рекомендуется)" } else { "" }
        Write-Host ("  {0} - {1}{2}, окно {3} токенов" -f ($i + 1), (Engine-Label $opts[$i]), $tag, $w)
    }
    for ($try = 0; $try -lt 3; $try++) {
        $pick = Read-KitLine "Ваш выбор [1]"
        if ($null -eq $pick) { return $best }
        $pick = $pick.Trim()
        if (-not $pick) { return $best }
        if ($pick -match '^[0-9]+$' -and [int]$pick -ge 1 -and [int]$pick -le $opts.Count) {
            return $opts[[int]$pick - 1]
        }
        Write-Host "  Нет такого варианта: нужно число от 1 до $($opts.Count)."
    }
    Fail "выбор сервера не распознан с третьей попытки: ждали число от 1 до $($opts.Count)" 2
}

# Полный цикл подбора для одного движка: человекочитаемый разбор + машинная копия. Функция, а
# не строки в теле, потому что выбор в меню пересчитывает и окно, и строку запуска, а не только
# подписывает их повторно.
function Invoke-Recommend([string]$ForEngine) {
    $common = @((Quote-Arg (Join-Path $kit "recommend.py")), "--gguf", (Quote-Arg $Gguf),
                "--config", (Quote-Arg $cfgPath), "--engine", $ForEngine,
                "--exe-strata", (Quote-Arg $ExeStrata), "--exe-llama", (Quote-Arg $ExeLlama))
    if ($Window -gt 0) { $common += @("--window", "$Window") }
    Write-Host ""
    Write-Host "== подбор окна и параметров =="
    $script:rc = Invoke-Kit $common
    if ($script:rc -eq 2) { Fail "подбор не состоялся (см. [FAIL] выше)" 2 }

    # Машинная копия подбора пишется при Continue: та же ловушка - чужая stderr-строка под Stop
    # обрывала бы прогон после уже успешного подбора.
    $eap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    # stderr в файл, а не в $null: Out-File создаёт и обнуляет $recPath до первой строки вывода,
    # поэтому упавший Python оставлял нулевой файл, а следующий за ним отказ читался как «в подборе
    # нет строки запуска» - ложная причина при настоящей причине, утопленной в $null.
    $recErr = Join-Path $run "recommend.err.log"
    & $py @($common + @("--json")) 2> $recErr | Out-File -LiteralPath $recPath -Encoding UTF8
    $jsrc = $LASTEXITCODE
    $ErrorActionPreference = $eap
    if (-not (Test-Path -LiteralPath $recPath)) { Fail "не записан $recPath" 2 }
    if ((Get-Item -LiteralPath $recPath).Length -eq 0) {
        $why = ''
        if (Test-Path -LiteralPath $recErr) { $why = ((Get-Content -LiteralPath $recErr | Select-Object -Last 3) -join ' / ') }
        if (-not $why) { $why = "stderr пуст" }
        Fail "recommend.py --json не напечатал ничего (rc=$jsrc): $why" 2
    }
    try { $script:rec = Get-Content -LiteralPath $recPath -Raw | ConvertFrom-Json }
    catch { Fail "$recPath не разбирается как JSON: $_" 2 }
    if (-not $script:rec.launch -or -not $script:rec.launch.args) { Fail "в подборе нет строки запуска" 2 }
}

# Признак Страта-ноги: подбор отдаёт команду не бинарника, а питонового сервера (webui и режим
# --serve живут в serve/server.py, а не в strata-q36.exe), поэтому exe == python либо в выдаче
# есть тело конфига движка.
function Test-StrataLaunch($l) {
    if ($null -ne $l.PSObject.Properties['config']) { return $true }
    $n = [System.IO.Path]::GetFileNameWithoutExtension([string]$l.exe).ToLowerInvariant()
    return ($n -in @('python', 'python3', 'py'))
}

# Подготовка Страта-ноги: конфиг движка на диске, целостность комплекта, PYTHONPATH и
# экстракция токенизатора. Ничего не запускает - это право остаётся у основного тела; собранную
# строку аргументов сервера кладёт в $script:strataTail.
function Invoke-StrataSetup {
    Write-Host ""
    Write-Host "== сервер Страты: python + serve\server.py =="
    if ($null -eq $rec.launch.PSObject.Properties['config']) {
        # Временный разрыв: контракт «launch.config для Страты» договаривается с recommend.py
        # отдельно, и без него поднимать Страту нечем - выдумывать конфиг по своей мере глупо.
        Fail "подбор не вернул конфиг сервера (в выдаче нет launch.config): Страту поднимать нечем, обновите kit\recommend.py или возьмите -Engine llama" 2
    }
    $c = $rec.launch.config
    $base = Get-AbsPath ([string]$c.cwd) $kit
    if (-not $base) { $base = $kit }
    Set-CfgProp $c 'cwd' $base
    if ($c.PSObject.Properties.Name -contains 'exe') {
        Set-CfgProp $c 'exe' (Resolve-StrataExe ([string]$c.exe) $base)
    }

    # Распакованные колёса (jinja2, markupsafe, regex) - единственное, чем сервер живёт без pip:
    # без них импорт падает трассировкой, поэтому отказываем именем недостающего пути.
    $vendor = Join-Path $kit "vendor"
    # regex имеет win-колёса только под CPython 3.11-3.15 (ряд $VENDOR_ABIS в pack_kit.ps1:128):
    # вне диапазона комплект обязан честно отказать, а не тащить ImportError через полминуты
    # загрузки.
    $verLine = ''
    $eap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $verLine = ((& $py -c "import sys; print('%d.%d' % sys.version_info[:2])" 2>&1 | Select-Object -Last 1) | Out-String).Trim()
    $ErrorActionPreference = $eap
    $vendorAbi = ''
    if ($verLine -match '^(\d+)\.(\d+)$') {
        $maj = [int]$Matches[1]
        $min = [int]$Matches[2]
        if ($maj -ne 3 -or $min -lt 11 -or $min -gt 15) {
            Fail "колёса regex в комплекте собраны только под CPython 3.11-3.15, а python это $maj.$min ($py): возьмите Python из диапазона или укажите его через -Python" 2
        }
        # ABI берётся С ФАКТИЧЕСКОГО интерпретатора, а не шьётся литералом: зашитый «cp312» под
        # системным Python 3.11 указал бы PYTHONPATH в чужой каталог - тот же ImportError, только
        # с правдоподобным путём в сообщении.
        $vendorAbi = "cp$maj$min"
    } elseif (-not $DryRun) {
        Write-Host "ПРЕДУПРЕЖДЕНИЕ: версию python определить не вышло ($verLine) - продолжаем на свой риск."
    }

    # Колёса лежат НЕ в vendor\ плоско, а по ABI-каталогам: vendor\cp311..cp315 для бинарных
    # (regex, markupsafe) и vendor\py3-none-any для чисто питоновских (jinja2). Гейт собирает
    # ВСЕ недостающие уровни в один отказ с конкретными путями: по одному отказу на уровень
    # заставили бы пользователя перезапускать стартер после каждой найденной дыры.
    $pureDir = Join-Path $vendor "py3-none-any"
    $abiDir = if ($vendorAbi) { Join-Path $vendor $vendorAbi } else { "" }
    $lacking = @()
    if (-not (Test-Path -LiteralPath $vendor)) {
        $lacking += "$vendor (нужны jinja2, markupsafe, regex)"
    } else {
        if (-not $abiDir) {
            $lacking += "$vendor\<abi> - ABI фактического python ($py, ответ «$verLine») не определён"
        } elseif (-not (Test-Path -LiteralPath $abiDir)) {
            $lacking += "$abiDir - нет каталога колёс под ABI этого python (ряд в архиве: cp311..cp315)"
        } elseif (@(Get-ChildItem -LiteralPath $abiDir -Directory -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -in @('regex', 'markupsafe') }).Count -eq 0) {
            $lacking += "$abiDir - каталог есть, но ни regex, ни markupsafe в нём не распакованы"
        }
        if (-not (Test-Path -LiteralPath $pureDir)) {
            $lacking += "$pureDir - нет pure-каталога (в нём лежит jinja2)"
        } elseif (-not (Test-Path -LiteralPath (Join-Path $pureDir "jinja2"))) {
            $lacking += "$pureDir\jinja2 - колесо jinja2 не распаковано"
        }
    }
    if ($lacking.Count) {
        $why = $lacking -join '; '
        if ($DryRun) { Write-Host "ПРЕДУПРЕЖДЕНИЕ: комплект неполон: нет $why - сервер не поднимется." }
        else { Fail "комплект неполный: нет $why" 2 }
    }

    # PYTHONPATH дочернему процессу: ABI-каталог, затем pure-каталог, затем всё, что уже было в
    # окружении (пути библиотек пользователя перекрывать нельзя - тогда CUDA-библиотеки исчезнут
    # из поиска). Порядок именно такой: колёса комплекта обязаны выигрывать у чужого site-packages
    # того же пакета. Разделитель - ';' (Windows); прежнее «$pp = $vendor» не добавляло ни ABI,
    # ни py3-none-any, то есть ни один вендорный модуль так и не находился.
    $ppParts = @()
    if ($abiDir) { $ppParts += $abiDir }
    $ppParts += $pureDir
    if ($env:PYTHONPATH) { $ppParts += $env:PYTHONPATH }
    $pp = $ppParts -join ';'
    Set-Item -Path 'Env:PYTHONPATH' -Value $pp
    Write-Host ("  set PYTHONPATH={0}" -f $pp)

    # Переменная собрана - но её наличие ещё ничего не доказывает: если рядом с интерпретатором
    # лежит ._pth, sys.path сворачивается в строки файла (isolated=1, import site=0) и PYTHONPATH
    # игнорируется МОЛЧА. Измерено прогоном glm\scripts\kit415_pth_mechanism_2026-11-14.ps1: верная
    # переменная при ._pth даёт ModuleNotFoundError, а дописанная в ._pth относительная строка -
    # импорт. Поэтому дорога именно такая: проба импорта ПОСЛЕ сборки PYTHONPATH, а отказ называет
    # причину - «файл ._pth закрыл поиск»: вина упаковки (pack_kit.ps1 обязан дописать вендор), или
    # «вендора на месте нет»: вина комплекта на диске. Прежний код молчал до первой страницы
    # морды, то есть до ImportError через полминуты загрузки.
    $pthDir = ''
    if (Test-Path -LiteralPath $py -PathType Leaf) { $pthDir = Split-Path -Parent $py }
    else {
        $gc = Get-Command $py -ErrorAction SilentlyContinue
        if ($gc -and $gc.Source) { $pthDir = Split-Path -Parent $gc.Source }
    }
    $pths = @()
    if ($pthDir -and (Test-Path -LiteralPath $pthDir -PathType Container)) {
        $pths = @(Get-ChildItem -LiteralPath $pthDir -File -Force |
                  Where-Object { $_.Name -like '*._pth' })
    }
    $vOut = ''; $vRc = -1
    $eap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $vOut = ((& $py -c "import jinja2, regex" 2>&1 | Out-String).Trim())
    $vRc = $LASTEXITCODE
    $ErrorActionPreference = $eap
    if ($vRc -ne 0) {
        if ($pths.Count) {
            $why = "рядом с интерпретатором лежит $($pths[0].Name) ($pthDir): он закрывает поиск " +
                   "по PYTHONPATH, а каталог колёс в его строки не дописан - править упаковку " +
                   "(packaging\kit\ci\pack_kit.ps1, Add-VendorToPth), а не переменную"
        } else {
            # Имя дублирует константу $VENDOR_SITE_PTH из packaging\kit\ci\pack_kit.ps1: именно этот
            # сайдкар даёт собранному комплекту вендор БЕЗ переменной окружения (site читает *.pth в
            # Lib\site-packages, строки разрешаются от каталога файла; глубина проверена прогоном
            # glm\scripts\kit469_pth_depth.ps1). Здесь он нужен только для диагноза: если файл на
            # месте, а импорт всё равно краснеет с собранной переменной - дело в самом PYTHONPATH.
            $site = if ($pthDir) { Join-Path $pthDir 'Lib\site-packages\strata_kit_vendor.pth' } else { '' }
            $siteTxt = if ($site -and (Test-Path -LiteralPath $site -PathType Leaf)) {
                "сайдкар $site на месте, то есть каталоги вендора в комплекте есть"
            } else {
                "сайдкар Lib\site-packages\strata_kit_vendor.pth отсутствует - править упаковку " +
                "(packaging\kit\ci\pack_kit.ps1, Add-VendorToSitePth)"
            }
            $why = "файла ._pth рядом с $py нет, значит PYTHONPATH ($pp) собран, но модулей в нём " +
                   "не видно - колёса не под этот ABI или каталог пуст; $siteTxt"
        }
        $flat = ($vOut -replace '\s+', ' | ')
        if ($DryRun) {
            Write-Host "ПРЕДУПРЕЖДЕНИЕ: импорт jinja2/regex не удался (rc=$vRc): $why; вывод: $flat"
        } else {
            Fail "импорт jinja2/regex вернул rc=$vRc : $why; вывод: $flat" 2
        }
    }

    $serverPy = Get-AbsPath ([string]$launchArgs[0]) $kit
    if (-not (Test-Path -LiteralPath $serverPy)) {
        if ($DryRun) { Write-Host "ПРЕДУПРЕЖДЕНИЕ: комплект неполон: нет $serverPy - сервер не поднимется." }
        else { Fail "комплект неполный: нет файла сервера $serverPy (в архиве он лежит как kit\serve\server.py)" 2 }
    }
    # Команду переклеиваем под свои пути: args[0] - относительный serve\server.py, --config -
    # относительный run\strata.json, а рабочая папка процесса на них влиять не должна. Сама
    # строка аргументов остаётся целиком: первым элементом идёт файл сервера, а не интерпретатор.
    $cmd = @($launchArgs)
    $cmd[0] = $serverPy
    $i = [Array]::IndexOf($cmd, '--config')
    if ($i -ge 0 -and $i + 1 -lt $cmd.Count) { $cmd[$i + 1] = $strataJson }
    elseif ($i -lt 0) { $cmd += @('--config', $strataJson) }
    $script:strataTail = $cmd

    # Бинарник движка: каталог bin\ проверен выше (:104-112), здесь - сам файл, потому что для
    # питоновой ноги общая проверка «движка нет на месте» по exe не срабатывает.
    if ($c.PSObject.Properties.Name -contains 'exe' -and $c.exe -and -not ([string]$c.exe).StartsWith('component:')) {
        if (-not (Test-Path -LiteralPath ([string]$c.exe))) {
            if ($DryRun) { Write-Host "ПРЕДУПРЕЖДЕНИЕ: движка нет на месте: $($c.exe)" }
            else { Fail "движка нет на месте: $($c.exe) (собранный бинарник должен лежать в bin\ рядом с kit\)" 2 }
        }
    }

    # Путь токенизатора в конфиге делаем абсолютным здесь, а дорогую экстракцию оставляем
    # отдельной функции после подтверждения: без vocab.json, merges.txt и token_type.json
    # сервер отказывает уже на загрузке (serve/server.py:10256, :10264, :10265), но выкапывать
    # их из GGUF без «y» пользователь не просил.
    $tokDir = Get-AbsPath ([string]$c.tokenizer) $kit
    if (-not $tokDir) { $tokDir = Join-Path $run "tokenizer" }
    Set-CfgProp $c 'tokenizer' $tokDir
    if ($c.PSObject.Properties.Name -contains 'log') {
        Set-CfgProp $c 'log' (Get-AbsPath ([string]$c.log) $kit)
    }
    if (-not (Test-Path -LiteralPath (Join-Path $tokDir 'vocab.json'))) {
        Write-Host "  токенизатора нет ($tokDir) - будет извлечён перед запуском."
    }

    # Конфиг сервера: тело из подбора, пути абсолютные. UTF-8 с BOM PS 5.1 не мешает - сервер
    # читает конфиг через decode("utf-8-sig") (serve/server.py:10178).
    $c | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $strataJson -Encoding UTF8
    Write-Host "Конфиг движка записан: $strataJson"
}

# Экстракция токенизатора: идемпотентна по наличию vocab.json, поэтому повторный запуск
# комплекта на той же модели её больше не делает.
function Invoke-StrataTokenizer {
    $tokDir = [string]$rec.launch.config.tokenizer
    if (-not $tokDir) { return }
    if (Test-Path -LiteralPath (Join-Path $tokDir 'vocab.json')) { return }
    $tool = Get-AbsPath 'tools\strata_tokenizer.py' $kit
    if (-not (Test-Path -LiteralPath $tool)) {
        Fail "комплект неполный: нет $tool (экстракция токенизатора обязательна до запуска)" 2
    }
    Write-Host ""
    Write-Host "== токенизатор =="
    # extract() пишет <out>\tokenizer (tools/strata_tokenizer.py:487), поэтому точкой вывода
    # служит родитель папки токенизатора; имя не «tokenizer» - сверимся после по факту.
    $outDir = $tokDir
    if ((Split-Path -Leaf $tokDir) -eq 'tokenizer') { $outDir = Split-Path -Parent $tokDir }
    $trc = Invoke-Kit @((Quote-Arg $tool), "--gguf", (Quote-Arg $Gguf), "--out", (Quote-Arg $outDir))
    $vdir = Join-Path $kit "vendor"
    if ($trc -ne 0) { Fail "экстракция токенизатора не удалась (код $trc): regex ищется в PYTHONPATH - это $vdir\<abi> и $vdir\py3-none-any" 2 }
    if (-not (Test-Path -LiteralPath (Join-Path $tokDir 'vocab.json'))) {
        Fail "после экстракции нет $(Join-Path $tokDir 'vocab.json'): strata_tokenizer.py пишет в другую папку ($outDir)" 2
    }
}

$kit = Resolve-Kit
$binDir = Resolve-Bin
$py = Find-Python

if (-not $binDir) {
    # Для -DryRun бинарники не нужны: строка запуска считается по подбору параметров, а вот
    # настоящий запуск без bin\ обязан отказывать, а не падать молча на Start-Process.
    if (-not $DryRun) {
        Fail "каталога bin\ с движками нет ни рядом с $(Split-Path -Parent $kit), ни внутри комплекта" 2
    }
    Write-Host "ПРЕДУПРЕЖДЕНИЕ: каталога bin\ нет - строка запуска укажет на несуществующий файл."
    $binDir = Join-Path $root "bin"
}
if (-not $ExeStrata) { $ExeStrata = Join-Path $binDir "strata-q36.exe" }
if (-not $ExeLlama) { $ExeLlama = Join-Path $binDir "llama-server.exe" }

# ---- вопрос о модели: путь принимает перетащенный в окно ярлыка текст со скобками и кавычками
if (-not $Gguf) {
    Write-Host "Локальный путь к файлу модели (.gguf). Скачанную модель можно перетащить в это окно."
    $Gguf = Read-Host "Путь к .gguf"
}
if (-not $Gguf) { Fail "путь к модели не введен: считать неоткуда" 2 }
$Gguf = $Gguf.Trim().Trim('"')
if (-not (Test-Path -LiteralPath $Gguf)) {
    Fail "файла модели нет по пути: $Gguf (проверьте расширение .gguf и диск)" 2
}
if ((Get-Item -LiteralPath $Gguf).PSIsContainer) { Fail "указан каталог, а нужен файл .gguf: $Gguf" 2 }
if (([System.IO.Path]::GetExtension($Gguf).ToLowerInvariant()) -ne ".gguf") {
    Write-Host "ПРЕДУПРЕЖДЕНИЕ: расширение не .gguf - комплект всё равно попробует прочитать заголовок."
}
$Gguf = (Resolve-Path -LiteralPath $Gguf).Path

$run = Join-Path $root "run"
if (-not (Test-Path -LiteralPath $run)) { New-Item -ItemType Directory -Path $run | Out-Null }
$cfgPath = Join-Path $run "config.json"
$recPath = Join-Path $run "recommend.json"
$log = Join-Path $run "server.log"
$errLog = Join-Path $run "server.err.log"
# Без этого Python на русской Windows печатает кириллицу в cp866/cp1251, а PS читает поток
# как UTF-8 - вместо причин отказа получается нечитаемый шум.
$env:PYTHONIOENCODING = "utf-8"
$env:PYTHONUTF8 = "1"

# ---- 1. конфигурация железа (одна съёмка на весь прогон: и для класса, и для подбора)
$detectArgs = @((Quote-Arg (Join-Path $kit "detect.py")), "--out", (Quote-Arg $cfgPath),
                "--model", (Quote-Arg $Gguf))
if ($FakeConfig) { $detectArgs = @((Quote-Arg (Join-Path $kit "detect.py")),
                                   "--fake-config", (Quote-Arg $FakeConfig),
                                   "--out", (Quote-Arg $cfgPath)) }
Write-Host "== железо =="
$drc = Invoke-Kit $detectArgs
if ($drc -eq 2) { Fail "detect.py: конфигурация неполная (см. ОТКАЗ выше)" 2 }
if ($drc -eq 1) { Write-Host "  (detect дал предупреждения - они учтены в подборе)" }
if (-not (Test-Path -LiteralPath $cfgPath)) { Fail "detect.py не записал $cfgPath" 2 }

# ---- 2. подбор: окно, движок, параметры, ссылка на модель
Invoke-Recommend $Engine

# ---- 2a. выбор сервера голосом. Спрашиваем, только когда движок не задан извне (-Engine),
# прогон живой (не -DryRun) и тихого запуска (-Yes) не просили; иначе вопрос превращал бы
# автоматический запуск в висящее окно. Один движок в alternatives - спрашивать не о чем.
if ($Engine -eq 'auto' -and -not $DryRun -and -not $Yes) {
    $chosen = Select-Engine $rec
    if ($chosen -and $chosen -ne ([string]$rec.engine).Trim()) {
        Write-Host "  выбрали $(Engine-Label $chosen) - пересчитываю окно и параметры под него"
        Invoke-Recommend $chosen
    }
}

$launchArgs = @($rec.launch.args)
# Две ноги запуска: у llama команда указывает на бинарник движка, у Страты - на питоновый
# сервер (webui и --serve живут в serve/server.py, а не в strata-q36.exe), и для неё подготовкой
# занимается Invoke-StrataSetup.
$strata = Test-StrataLaunch $rec.launch
if ($strata) {
    $strataJson = Join-Path $run "strata.json"
    Invoke-StrataSetup
    $exe = $py
    $tail = $script:strataTail
} else {
    $exe = $launchArgs[0]
    $tail = @()
    if ($launchArgs.Count -gt 1) { $tail = $launchArgs[1..($launchArgs.Count - 1)] }
}
$line = (Quote-Arg $exe) + " " + (($tail | ForEach-Object { Quote-Arg ([string]$_) }) -join " ")

Write-Host ""
Write-Host "== готовая строка запуска =="
Write-Host $line
foreach ($k in $rec.launch.env.PSObject.Properties.Name) {
    Write-Host ("  set {0}={1}" -f $k, $rec.launch.env.$k)
}

if ($DryRun) {
    Write-Host ""
    Write-Host "-DryRun: ничего не запущено."
    exit $rc
}

if (-not $strata -and -not (Test-Path -LiteralPath $exe)) {
    # У Страта-ноги процесс другой: exe команды - python, а бинарник движка проверяется внутри
    # Invoke-StrataSetup по конфигу, поэтому здесь решает только наличие движка llama.cpp.
    Fail "движка нет на месте: $exe (собранный бинарник должен лежать в bin\; кладите модель отдельно)" 2
}

if (-not $Yes) {
    $answer = Read-Host "Запустить сервер? (y/N)"
    if ($answer -notmatch '^(y|д|у)') { Write-Host "Отменено пользователем. Строка запуска - выше."; exit 0 }
}

# Дорогая часть подготовки стоит ПОСЛЕ «y»: до него скрипт только пишет конфиг и считает строку.
if ($strata) { Invoke-StrataTokenizer }

foreach ($k in $rec.launch.env.PSObject.Properties.Name) {
    Set-Item -Path ("Env:" + $k) -Value ([string]$rec.launch.env.$k)
}
Write-Host ""
Write-Host "Запуск: $line"
Write-Host "Журнал: $log"
# -ArgumentList одной строкой, а не массивом: в 5.1 массив склеивается без кавычек, и путь
# модели с пробелом разъезжается на два аргумента.
$proc = Start-Process -FilePath $exe -ArgumentList (($tail | ForEach-Object { Quote-Arg ([string]$_) }) -join " ") `
        -NoNewWindow -PassThru -WorkingDirectory $root `
        -RedirectStandardOutput $log -RedirectStandardError $errLog
# Включить ДО цикла ожидания: позже уже нельзя - момент выхода пропущен, и ExitCode останется
# пустым, а отказ - без числа.
$proc.EnableRaisingEvents = $true

$url = "http://127.0.0.1:" + $rec.launch.port
Write-Host "Сервер поднимается, webui будет по адресу $url (модель 18-23 ГиБ грузится минутами)."
$deadline = (Get-Date).AddSeconds($StartTimeoutSec)
$ready = $false
while ((Get-Date) -lt $deadline) {
    if ($proc.HasExited) { break }
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $c.Connect("127.0.0.1", [int]$rec.launch.port)
        $c.Close()
        $ready = $true
        break
    } catch { Start-Sleep -Seconds 3 }
}
if ($proc.HasExited) {
    $code = Get-ProcExitCode $proc
    $shown = if ($null -eq $code) { "недоступен" } else { [string]$code }
    Write-Host ""
    Write-Host "Сервер завершился с кодом $shown. Хвост журнала:"
    if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Tail 25 | ForEach-Object { Write-Host $_ } }
    if (Test-Path -LiteralPath $errLog) {
        Get-Content -LiteralPath $errLog -Tail 25 | ForEach-Object { Write-Host $_ }
    }
    Fail "сервер не поднялся (код $shown); разбор - по $log и README.ru.md рядом с START.bat" 1
}
if (-not $ready) {
    Write-Host "ПРЕДУПРЕЖДЕНИЕ: порт $($rec.launch.port) не отвечает через $StartTimeoutSec с - процесс жив."
    Write-Host "Смотрите ${log}: на 8 ГиБ это может быть не ошибка, а медленная загрузка весов."
} else {
    Write-Host "Порт отвечает: $url"
    if (-not $NoBrowser) { Start-Process $url | Out-Null }
}
Write-Host "Остановить: закройте это окно или выполните Stop-Process -Id $($proc.Id)"
exit $rc
