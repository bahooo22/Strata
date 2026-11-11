#Requires -Version 5.1
<#
    Единственная точка входа портативного комплекта: измерить железо -> сказать класс ->
    подобрать окно и параметры -> запустить. Только Windows PowerShell 5.1: он есть на любой
    Windows, pwsh 7 - нет.

        START.bat                          спросить путь к .gguf и всё сделать
        START.bat C:\models\model.gguf     то же без вопроса
        START.bat a.gguf -DryRun           напечатать строку запуска и НЕ запускать
        START.bat a.gguf -Yes              не спрашивать разрешения на запуск
        START.bat a.gguf -Engine llama     запретить выбор движка
        START.bat a.gguf -Window 131072    проверить конкретное окно вместо максимума
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
    if ($Python) {
        if (Get-Command $Python -ErrorAction SilentlyContinue) { return $Python }
        if (Test-Path -LiteralPath $Python) { return $Python }
        Fail "python не найден: $Python" 2
    }
    foreach ($c in @("python", "py")) {
        if (Get-Command $c -ErrorAction SilentlyContinue) { return $c }
    }
    Fail "нужен Python 3.10+ (в PATH как `python`), а его нет: комплект считает окно на Python" 2
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
$common = @((Quote-Arg (Join-Path $kit "recommend.py")), "--gguf", (Quote-Arg $Gguf),
            "--config", (Quote-Arg $cfgPath), "--engine", $Engine,
            "--exe-strata", (Quote-Arg $ExeStrata), "--exe-llama", (Quote-Arg $ExeLlama))
if ($Window -gt 0) { $common += @("--window", "$Window") }
Write-Host ""
Write-Host "== подбор окна и параметров =="
$rc = Invoke-Kit $common
if ($rc -eq 2) { Fail "подбор не состоялся (см. [FAIL] выше)" 2 }

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
try { $rec = Get-Content -LiteralPath $recPath -Raw | ConvertFrom-Json }
catch { Fail "$recPath не разбирается как JSON: $_" 2 }
if (-not $rec.launch -or -not $rec.launch.args) { Fail "в подборе нет строки запуска" 2 }

$launchArgs = @($rec.launch.args)
$exe = $launchArgs[0]
$tail = @()
if ($launchArgs.Count -gt 1) { $tail = $launchArgs[1..($launchArgs.Count - 1)] }
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

if (-not (Test-Path -LiteralPath $exe)) {
    Fail "движка нет на месте: $exe (собранный бинарник должен лежать в bin\; кладите модель отдельно)" 2
}

if (-not $Yes) {
    $answer = Read-Host "Запустить сервер? (y/N)"
    if ($answer -notmatch '^(y|д|у)') { Write-Host "Отменено пользователем. Строка запуска - выше."; exit 0 }
}

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
    Write-Host ""
    Write-Host "Сервер завершился с кодом $($proc.ExitCode). Хвост журнала:"
    if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Tail 25 | ForEach-Object { Write-Host $_ } }
    if (Test-Path -LiteralPath $errLog) {
        Get-Content -LiteralPath $errLog -Tail 25 | ForEach-Object { Write-Host $_ }
    }
    Fail "сервер не поднялся (код $($proc.ExitCode)); разбор - по $log и README.ru.md рядом с START.bat" 1
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
