#Requires -Version 7.0
<#
.SYNOPSIS
    Живая приёмка РАСПАКОВАННОГО комплекта gpu-infer-kit: движок обязан подняться и отдать страницу.

.DESCRIPTION
    Что этот скрипт ловит и чего не ловил ни один прежний гейт:
    опубликованный llama-движок мёртв - комплектный llama-server.exe (10 752 Б, stub рядом с
    llama-server-impl.dll 7 632 896 Б) падает с 0xC0000005 (-1073741819) в первые ~50 мс, stderr
    обрывается на «srv  llama_server: initializing ...», то есть ДО загрузки модели (первичники:
      E:\tmp\kit374-watch.verdict.txt      - падение на реальной модели 15 ГиБ;
      E:\tmp\kit375-localize.verdict.txt   - master живой на той же крошечной GGUF, kit мёртв;
      E:\tmp\kit379-forensics.verdict.txt  - dll в dist побайтово равны сборке, все 9 dll kit != master;
      E:\tmp\kit380-split.verdict.txt, E:\tmp\kit390-cuda-env.verdict.txt - CUDA-бэкенд ни при чём).
    Архив при этом собирается, гейты состава зелёные, формат-гейт zip зелёный: значит missing-гейт
    обязан МЕРЯТЬ ЖИЗНЬ носителя, а не его наличие.

    Меряется распакованный бандл - ровно то, что получает пользователь, а НЕ дерево сборки:
    дефект жил именно между сборкой и носителем.

    Ноги:
      a) llama-нога: bin\llama-server.exe с -ngl 0 (на безгитарном runner'е GPU нет; -ngl 0 -
         единственный осмысленный CPU-прогон, и kit375/kit380 показывают, что мёртвый kit
         краснеет и с ним), крошечная GGUF, --host 127.0.0.1 --port <N>. Готовность - ЧЕСТНЫМ
         признаком: HTTP GET /props обязан вернуть JSON с model_path и n_ctx
         (первичник ключей - llama.cpp tools/server/server-context.cpp:5704 и :5715), затем
         GET / обязан вернуть 200 и тело, похожее на HTML.
         Файл index.html в архиве НЕ ищется: веб-морда встроена в llama-server-impl.dll
         (assets идут через scripts/ui-assets.cmake, LLAMA_UI_GZIP в tools/ui/CMakeLists.txt:4),
         а routes регистрируют "/" и "/index.html" из памяти (tools/server/server-http.cpp:563-564).
         Доказательством служит фактический ответ сервера, а не состав архива.
      b) Страта-нога: морду держит НЕ strata-q36.exe, а kit\serve\server.py - он поднимает HTTP
         сам и запускает движок подпроцессом со своим --serve
         (первичник C:\Projects\Strata-3060Ti\engine\serve\server.py:1230).
         Набор аргументов взят из первичников, а не выдуман:
           harness\scripts\run_strata_chat.bat:24  python serve\server.py --engine strata --config <cfg> --port <N>
           harness\scripts\live_strata.py:142-143  python -m serve.server --engine strata --config <tmp> --port <N>
                                                   (cwd = корень дерева), готовность ждёт /health
           E:\tmp\kit371_strata_webui_probe.ps1    - готовый зонд: раскладка копии и перечень проверок
         Routes сервера: HTML раздаётся ТОЛЬКО по "/" (server.py:8245, путь нормализуется как
         self.path.split("?")[0].rstrip('/') на server.py:7952), "/index.html" = 404;
         "/health" - готовность (server.py:8255), "/props" - под ключом (server.py:8305).
         Режим движения: real (движок из bin\ + модель + токенизатор) либо mock (тот же сервер,
         тот же web\, но движок не поднимается вовсе). mock выбирается, когда real невозможен по
         объективной причине входа (нет GPU/модели/токенизатора), и ПЕЧАТАЕТСЯ отдельным исходом -
         «морда из бандла жива» при этом всё равно меряется честно.

    Исходы каждой ноги печатаются раздельно: «готов» / «процесс умер (код)» / «таймаут» /
    «НЕ МЕРЯЛОСЬ (причина)». Молча пропущенной ноги быть не может.

.PARAMETER KitDir
    Корень РАСПАКОВАННОГО комплекта (тот, что пользователь получил из zip): bin\ и kit\ внутри.
    Для локального красного контроля допускается и комплект-подобная папка, где exe лежит прямо в
    ней (например E:\tmp\kit380-bin-all - заведомо мёртвый набор).

.PARAMETER Model
    Крошечная GGUF для llama-ноги. Тот же вход, что у приёмки стенда и у CI llama.cpp:
    https://huggingface.co/ggml-org/models/resolve/main/tinyllamas/stories260K.gguf (1 185 376 Б;
    первичник - tools/server/tests/utils.py:55-56 и E:\tmp\kit369_fetch_tiny_gguf.py).

.EXAMPLE
    pwsh -NoProfile -File smoke_kit.ps1 -KitDir C:\tmp\unpacked -Model E:\tmp\stories260K.gguf

.EXAMPLE
    pwsh -NoProfile -File smoke_kit.ps1 -SelfTest    # саботаж: битый носитель обязан дать rc=1

.NOTES
    Коды возврата: 0 - все мерявшиеся ноги зелёные; 1 - НАХОДКА (движок не поднялся / страница не
    отдаётся); 2 - прогон не состоялся (плохие входы, мерять было нечего) с явной печатью
    [NOT MEASURED] и причиной.
    Только PowerShell 7: Windows PowerShell 5.1 не читает UTF-8 без BOM, и русские строки
    превращаются в шум ещё до разбора скрипта.
    Ничего из дерева стенда не удаляется: временные файлы живут в -WorkDir (по умолчанию %TEMP%)
    и убираются за собой, кроме логов, которые нужны разбору (-KeepLogs).
#>
[CmdletBinding()]
param(
    [string]$KitDir = '',
    [string]$Model = '',
    # Диапазон портов: первый свободный берётся из [PortStart, PortStart+PortCount).
    [int]$PortStart = 18100,
    [int]$PortCount = 40,
    # Лимит ожидания готовности ОДНОЙ ноги, секунд.
    [int]$WaitSec = 120,
    [string]$Python = '',
    # Страта-нога: real | mock | auto (по умолчанию) | off.
    [ValidateSet('auto', 'real', 'mock', 'off')]
    [string]$Strata = 'auto',
    # Токенизатор для real-режима (каталог с vocab.json); без него real невозможен.
    [string]$StrataTokenizer = '',
    [string]$StrataModel = '',
    [string]$WorkDir = '',
    [switch]$KeepLogs,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$ic = [System.Globalization.CultureInfo]::InvariantCulture

# Очистка обязана существовать ДО trap: если ошибка случится в первых строках (например, на
# New-Object), trap вызовет Invoke-Cleanup, а её ещё нет - и вместо «прогон не состоялся» с rc=2
# получили бы падение самого гейта. Полная версия ниже по файлу перезаписывает этот каркас.
function Invoke-Cleanup { }

# Внутренняя ошибка самого гейта - НЕ находка в комплекте: rc=1 обязан означать «движок мёртв»,
# иначе сломанный скрипт имитировал бы красное покрытие (проверка на kit380-bin-all как раз
# ловила такой подмену: необработанный exception давал rc=1 без всякой приёмки).
trap {
    Write-Host ''
    Write-Host "[NOT MEASURED] гейт оборвался на собственной ошибке, приёмка не состоялась: $($_.Exception.Message)"
    Write-Host "  строка: $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)"
    Invoke-Cleanup
    exit 2
}
$script:llamaState = ''
$script:llamaNote = ''
$script:strataState = ''
$script:strataNote = ''
$script:workRoot = ''
$script:procs = New-Object System.Collections.Generic.List[object]

function Say([string]$t) { Write-Host $t }
function Step([string]$t) { Write-Host ''; Write-Host "== $t ==" }
function Format-Bytes([long]$b) {
    if ($b -lt 0) { return 'нет файла' }
    [string]::Format($ic, '{0:N0} Б', $b)
}
function Get-Size([string]$p) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return -1L }
    return (Get-Item -LiteralPath $p).Length
}
function Quote-Arg([string]$a) {
    if ($a -match '[\s"]') { return '"' + ($a -replace '"', '\"') + '"' }
    return $a
}

# Единственный выход «прогон не состоялся»: печатает причину и уходит с rc=2.
function Not-Measured([string]$reason) {
    Write-Host ''
    Write-Host "[NOT MEASURED] $reason"
    Write-Host 'Проверок не было: мерять было нечего, выход 2.'
    Invoke-Cleanup
    exit 2
}

function Get-Http([string]$url) {
    $r = [pscustomobject]@{ Code = $null; ContentType = ''; Body = ''; Error = '' }
    try {
        $resp = Invoke-WebRequest -Uri $url -Method Get -TimeoutSec 20 -UseBasicParsing -SkipHttpErrorCheck
        $r.Code = [int]$resp.StatusCode
        $r.ContentType = [string]$resp.Headers['Content-Type']
        $r.Body = if ($resp.Content -is [byte[]]) { [System.Text.Encoding]::UTF8.GetString($resp.Content) } else { [string]$resp.Content }
    } catch { $r.Error = $_.Exception.Message }
    return $r
}

# Пустая строка = страница отдаётся как HTML; иначе - чем именно она не является.
function Test-HtmlPage($resp) {
    if ($null -eq $resp.Code) { return "нет ответа: $($resp.Error)" }
    if ($resp.Code -ne 200) { return "код $($resp.Code)" }
    if ($resp.ContentType -notmatch 'text/html') { return "Content-Type '$($resp.ContentType)'" }
    if (($resp.Body -notmatch '(?is)<!doctype\s+html') -and ($resp.Body -notmatch '(?is)<html')) {
        return 'в теле нет ни <!doctype html>, ни <html>'
    }
    return ''
}

function Show-Tail([string]$path, [int]$lines, [string]$label) {
    $size = Get-Size $path
    if ($size -lt 0) { Write-Host "    (${label}: файла нет - $path)"; return }
    if ($size -eq 0) { Write-Host "    (${label}: пусто)"; return }
    Write-Host "    (${label}, $size Б) хвост ${lines} строк:"
    Get-Content -LiteralPath $path -Tail $lines -Encoding UTF8 -ErrorAction SilentlyContinue |
        ForEach-Object { Write-Host "      | $_" }
}

function Test-PortFree([int]$p) {
    $l = $null
    try {
        $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $p)
        $l.Start()
        return $true
    } catch { return $false }
    finally { if ($l) { try { $l.Stop() } catch { } } }
}

function Get-FreePort([string]$label) {
    for ($p = $PortStart; $p -lt ($PortStart + $PortCount); $p++) {
        if (Test-PortFree $p) { return $p }
    }
    Say "  (${label}: порты $PortStart..$($PortStart + $PortCount - 1) заняты)"
    return 0
}

function Start-Detached([string]$exe, [string[]]$args_, [string]$cwd, [string]$outFile, [string]$errFile) {
    # Перенаправление В ФАЙЛЫ, а не в события .NET: обработчики OutputDataReceived исполняются
    # вне runspace скрипта и падают с PSInvalidOperationException («Нет доступа к экземпляру
    # ScriptBlock для вызова скрипта в этом потоке») - то есть гейт умирал бы на своём коде,
    # а не на мёртвом движке. Тот же приём у зондов стенда (E:\tmp\kit363, E:\tmp\kit371).
    $line = (@($args_ | ForEach-Object { Quote-Arg $_ }) -join ' ')
    $p = Start-Process -FilePath $exe -ArgumentList $line -WorkingDirectory $cwd -NoNewWindow -PassThru `
        -RedirectStandardOutput $outFile -RedirectStandardError $errFile -ErrorAction Stop
    if ($null -eq $p -or $p.Id -le 0) { throw "процесс не запущен: $exe ($line)" }
    $p.EnableRaisingEvents = $true
    $script:procs.Add([pscustomobject]@{ Proc = $p; Exe = $exe })
    return $p
}

# Движок Страты/llama - дети HTTP-сервера: TerminateProcess родителя оставляет их висеть.
function Stop-ProcTree([int]$pid_) {
    try {
        $kids = @(Get-CimInstance -ClassName Win32_Process -Filter "ParentProcessId = $pid_" -ErrorAction SilentlyContinue)
        foreach ($k in $kids) { Stop-ProcTree ([int]$k.ProcessId) }
    } catch { }
    try { Stop-Process -Id $pid_ -Force -ErrorAction Stop } catch { }
}

function Invoke-Cleanup {
    foreach ($h in $script:procs) {
        try { if (-not $h.Proc.HasExited) { Stop-ProcTree ([int]$h.Proc.Id) } } catch { }
        try { $h.Out.Dispose(); $h.Err.Dispose(); $h.Proc.Dispose() } catch { }
    }
    $script:procs.Clear()
    Start-Sleep -Milliseconds 300
    if ($script:workRoot -and -not $KeepLogs -and (Test-Path -LiteralPath $script:workRoot)) {
        Remove-Item -LiteralPath $script:workRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --------------------------------------------------------------------------- -SelfTest
# Контроль самого гейта: на битом входе он обязан покраснеть, а на плохих входах -
# сказать «прогон не состоялся», а не «всё зелёное». Носители синтезируются в %TEMP%,
# ни дерева стенда, ни настоящего движка не касается.
if ($SelfTest) {
    $work = Join-Path $env:TEMP ('smoke-selftest-' + [System.IO.Path]::GetRandomFileName().Replace('.', ''))
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    $bad = 0
    try {
        # 1) заведомо битый носитель: exe, который умирает мгновенно, рядом с годной по magic GGUF.
        $fake = Join-Path $work 'broken'
        New-Item -ItemType Directory -Path (Join-Path $fake 'bin') -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $env:SystemRoot 'System32\ping.exe') -Destination (Join-Path $fake 'bin\llama-server.exe') -Force
        $gguf = Join-Path $work 'fake.gguf'
        $bytes = [byte[]](0x47, 0x47, 0x55, 0x46) + [byte[]](3, 0, 0, 0) + [byte[]](0, 0, 0, 0) +
                 [byte[]](0, 0, 0, 0) + (New-Object byte[] 2048)
        [System.IO.File]::WriteAllBytes($gguf, $bytes)
        $r1 = $null
        & pwsh -NoProfile -NonInteractive -File $PSCommandPath -KitDir $fake -Model $gguf -Strata off -WaitSec 25 -PortStart 18411 *>&1 |
            ForEach-Object { Write-Host "    | $_" }
        $r1 = $LASTEXITCODE
        Write-Host "rc(битый носитель)=$r1 (ожидался 1)"
        if ($r1 -ne 1) { $bad++ }

        # 2) плохой вход: каталога нет вообще - прогон обязан НЕ состояться.
        & pwsh -NoProfile -NonInteractive -File $PSCommandPath -KitDir (Join-Path $work 'no-such-dir') -Model $gguf -Strata off -WaitSec 5 -PortStart 18451 *>&1 |
            ForEach-Object { Write-Host "    | $_" }
        $r2 = $LASTEXITCODE
        Write-Host "rc(нет каталога)=$r2 (ожидался 2)"
        if ($r2 -ne 2) { $bad++ }

        # 3) плохой вход: каталог есть, модели нет - тоже «не состоялось».
        & pwsh -NoProfile -NonInteractive -File $PSCommandPath -KitDir $fake -Model '' -Strata off -WaitSec 5 -PortStart 18452 *>&1 |
            ForEach-Object { Write-Host "    | $_" }
        $r3 = $LASTEXITCODE
        Write-Host "rc(нет модели)=$r3 (ожидался 2)"
        if ($r3 -ne 2) { $bad++ }
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host ''
    Write-Host $(if ($bad) { "САМОКОНТРОЛЬ НЕ ПРОЙДЕН: расхождений $bad" } else { 'САМОКОНТРОЛЬ OK: битый носитель краснеет (1), плохие входы - не состоялось (2).' })
    exit $(if ($bad) { 1 } else { 0 })
}

# --------------------------------------------------------------------------- входы
Step 'Входы'
Say "pwsh: $($PSVersionTable.PSVersion) (требуется 7+, PowerShell 5.1 не читает UTF-8 без BOM)"

if (-not $KitDir) { Not-Measured '-KitDir не задан: распакованный комплект показывать негде' }
if (-not (Test-Path -LiteralPath $KitDir -PathType Container)) {
    Not-Measured "нет каталога распакованного комплекта: $KitDir"
}
$KitDir = (Get-Item -LiteralPath $KitDir).FullName
Say "KitDir   : $KitDir"

if (-not $Model) { Not-Measured '-Model не задана: без крошечной GGUF нечем поднимать llama-ногу' }
if (-not (Test-Path -LiteralPath $Model -PathType Leaf)) {
    Not-Measured "нет файла модели: $Model (крошечная GGUF обязана быть скачана шагом CI)"
}
$modelBytes = Get-Size $Model
$magic = New-Object byte[] 4
$fs = [System.IO.File]::OpenRead($Model)
try { $null = $fs.Read($magic, 0, 4) } finally { $fs.Dispose() }
if ([System.Text.Encoding]::ASCII.GetString($magic) -ne 'GGUF') {
    Not-Measured "$Model ($(Format-Bytes $modelBytes)) начинается с $($magic -join ',') - это не GGUF, мерить нечем"
}
Say ("Model    : {0} ({1}, magic GGUF)" -f $Model, (Format-Bytes $modelBytes))

if (-not $WorkDir) {
    $script:workRoot = Join-Path $env:TEMP ('smoke-kit-' + [System.IO.Path]::GetRandomFileName().Replace('.', ''))
} else { $script:workRoot = $WorkDir }
New-Item -ItemType Directory -Path $script:workRoot -Force | Out-Null
Say "WorkDir  : $script:workRoot"
Say "порты    : $PortStart..$($PortStart + $PortCount - 1), лимит готовности $WaitSec с на ногу"
Say "Страта   : режим -Strata $Strata"

# --------------------------------------------------------------------------- llama-нога
function Invoke-LlamaLeg {
    Step 'llama-нога: bin\llama-server.exe из распакованного комплекта'
    $cands = @((Join-Path $KitDir 'bin\llama-server.exe'), (Join-Path $KitDir 'llama-server.exe'))
    $exe = $cands | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if (-not $exe) {
        $hit = @(Get-ChildItem -LiteralPath $KitDir -Filter 'llama-server.exe' -File -Recurse -ErrorAction SilentlyContinue) |
            Select-Object -First 1
        if ($hit) { $exe = $hit.FullName }
    }
    if (-not $exe) {
        $script:llamaState = 'skip'
        $script:llamaNote = 'в распакованном комплекте нет bin\llama-server.exe (состав архива меряет гейт 4b в pack_kit.ps1)'
        Say "  [NOT MEASURED] $($script:llamaNote)"
        return
    }
    $bin = Split-Path -Parent $exe
    $impl = Join-Path $bin 'llama-server-impl.dll'
    Say ("  exe        : {0} ({1})" -f $exe, (Format-Bytes (Get-Size $exe)))
    Say ("  impl dll   : {0} ({1}) - морда встроена сюда, в архиве index.html для неё искать нельзя" -f $impl, (Format-Bytes (Get-Size $impl)))
    $port = Get-FreePort 'llama'
    if ($port -le 0) {
        $script:llamaState = 'skip'
        $script:llamaNote = "нет свободного порта в диапазоне $PortStart..$($PortStart + $PortCount - 1)"
        Say "  [NOT MEASURED] $($script:llamaNote)"
        return
    }
    $threads = [Math]::Min(8, [Environment]::ProcessorCount)
    # -ngl 0 обязателен: у windows-раннера GitHub Actions дискретного GPU нет, а мёртвый kit
    # (kit380/kit390) краснеет и на CPU, и с CUDA_VISIBLE_DEVICES="" - то есть прогон осмыслен.
    $a = @('-m', $Model, '--ctx-size', '512', '-ngl', '0', '--host', '127.0.0.1', '--port', [string]$port, '--threads', [string]$threads)
    Say "  команда    : llama-server $($a -join ' ')"
    $out = Join-Path $script:workRoot 'llama.out.log'
    $err = Join-Path $script:workRoot 'llama.err.log'
    $p = $null
    try { $p = Start-Detached $exe $a $bin $out $err } catch {
        $script:llamaState = 'found'
        $script:llamaNote = "процесс не запущен: $($_.Exception.Message)"
        Say "  НАХОДКА: $($script:llamaNote)"
        return
    }
    Say "  pid        : $($p.Id), порт $port"

    # ЧЕСТНЫЙ признак готовности: /props отвечает JSON с model_path и n_ctx.
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $deadline = [System.TimeSpan]::FromSeconds($WaitSec)   # TimeSpan, а не DateTime: у Stopwatch
                                                            # Elapsed тоже TimeSpan, сравнение одномерное
    $props = $null
    $why = ''
    $polls = 0
    while ($sw.Elapsed -lt $deadline) {
        $polls++
        if ($p.HasExited) { $why = 'умер'; break }
        $r = Get-Http "http://127.0.0.1:$port/props"
        if ($r.Code -eq 200) { $props = $r; break }
        Start-Sleep -Milliseconds 500
    }
    if ($why -eq 'умер') {
        $code = -1
        try { $code = $p.ExitCode } catch { }
        $script:llamaState = 'found'
        $script:llamaNote = "llama-server умер через $([int]$sw.Elapsed.TotalSeconds) с, код $code (0x$('{0:X8}' -f $code))"
        Say "  ИСХОД: ПРОЦЕСС УМЕР, код=$code (0x$('{0:X8}' -f $code)) через $([int]$sw.Elapsed.TotalSeconds) с, попыток HTTP: $polls"
        Show-Tail $err 10 'stderr'
        Show-Tail $out 5 'stdout'
        # Класс по фактическому хвосту, а не по коду: прежняя строка навешивала «ровно класс
        # kit374/kit375» на ЛЮБОЙ «умер», и мера не различала падение до загрузки модели
        # (initializing) от падения на модели - а это разные дефекты и разные правки.
        $tail = ''
        if ((Get-Size $err) -gt 0) {
            $tail = ((Get-Content -LiteralPath $err -Tail 40 -Encoding UTF8 -ErrorAction SilentlyContinue) -join ' ')
        }
        $cls = if ($tail -like '*initializing*') {
            'обрыв на «initializing ...» (до загрузки модели) - тот же класс, что kit374/kit375'
        } else {
            'хвост stderr НЕ содержит «initializing» - класс другой, читать хвост выше'
        }
        Say "  НАХОДКА: $($script:llamaNote); $cls"
        return
    }
    if (-not $props) {
        $script:llamaState = 'found'
        $script:llamaNote = "/props не ответил за $WaitSec с, процесс жив (pid $($p.Id))"
        Say "  ИСХОД: ТАЙМАУТ $WaitSec с, процесс жив, попыток HTTP: $polls"
        Show-Tail $err 10 'stderr'
        Show-Tail $out 5 'stdout'
        Say "  НАХОДКА: $($script:llamaNote)"
        return
    }

    $script:llamaState = 'green'
    Say "  ИСХОД: ГОТОВ через $([int]$sw.Elapsed.TotalSeconds) с (попыток HTTP: $polls)"
    $obj = $null
    try { $obj = $props.Body | ConvertFrom-Json } catch { }
    if ($null -eq $obj) {
        $script:llamaNote = "/props вернул не JSON ($(Format-Bytes $props.Body.Length), '$($props.ContentType)')"
        Say "  НАХОДКА: $($script:llamaNote)"
        $script:llamaState = 'found'
        return
    }
    $nctx = $null
    $whereNctx = 'нет'
    if ($null -ne $obj.PSObject.Properties['n_ctx']) { $nctx = $obj.n_ctx; $whereNctx = 'верхний уровень' }
    elseif ($null -ne $obj.PSObject.Properties['default_generation_settings'] -and
            $null -ne $obj.default_generation_settings.PSObject.Properties['n_ctx']) {
        $nctx = $obj.default_generation_settings.n_ctx; $whereNctx = 'default_generation_settings'
    }
    $mpProp = $obj.PSObject.Properties['model_path']
    $mp = if ($mpProp) { [string]$mpProp.Value } else { '' }
    Say ("  GET /props : 200, {0} Б; model_path='{1}', n_ctx={2} ({3})" -f $props.Body.Length, $mp, $(if ($null -eq $nctx) { 'нет' } else { $nctx }), $whereNctx)
    if (-not $mp) { $script:llamaNote = 'в /props нет поля model_path'; Say "  НАХОДКА: $($script:llamaNote)"; $script:llamaState = 'found' }
    if ($null -eq $nctx -or [long]$nctx -le 0) {
        $script:llamaNote = 'в /props нет живого n_ctx'
        Say "  НАХОДКА: $($script:llamaNote)"
        $script:llamaState = 'found'
    }
    if ($mp -and ($mp -notlike '*stories260K*') -and ([System.IO.Path]::GetFileName($mp) -ne [System.IO.Path]::GetFileName($Model))) {
        $script:llamaNote = "model_path из /props ($mp) - не наша модель ($Model): отвечает чужой сервер"
        Say "  НАХОДКА: $($script:llamaNote)"
        $script:llamaState = 'found'
    }

    $page = Get-Http "http://127.0.0.1:$port/"
    $problem = Test-HtmlPage $page
    if ($problem) {
        $script:llamaNote = "GET / не отдаёт HTML: $problem"
        Say "  GET /      : НАХОДКА - $problem"
        $script:llamaState = 'found'
    } else {
        $hasDoctype = $page.Body -match '(?is)<!doctype\s+html'
        Say ("  GET /      : 200, $($page.ContentType), тело $($page.Body.Length) Б, <!doctype html>={0} - морда отдаётся ИЗ ПАМЯТИ движка (LLAMA_UI_GZIP), файла в архиве нет" -f $hasDoctype)
    }
    $idx = Get-Http "http://127.0.0.1:$port/index.html"
    Say ("  GET /index.html : код {0} - у llama.cpp маршрут есть (server-http.cpp:563-564), в отличие от Страты" -f $(if ($null -eq $idx.Code) { 'нет ответа' } else { $idx.Code }))
    $h = Get-Http "http://127.0.0.1:$port/health"
    Say ("  GET /health     : код {0}" -f $(if ($null -eq $h.Code) { 'нет ответа' } else { $h.Code }))
    Stop-ProcTree ([int]$p.Id)
    try { $p.WaitForExit(5000) | Out-Null } catch { }
    $script:llamaNote = if ($script:llamaState -eq 'green') { "готов за $([int]$sw.Elapsed.TotalSeconds) с, HTML / = $($page.Body.Length) Б" } else { $script:llamaNote }
}

Invoke-LlamaLeg

# --------------------------------------------------------------------------- Страта-нога
function Invoke-StrataLeg {
    Step 'Страта-нога: kit\serve\server.py из распакованного комплекта'
    if ($Strata -eq 'off') {
        $script:strataState = 'skip'; $script:strataNote = 'нога выключена (-Strata off)'
        Say "  [NOT MEASURED] $($script:strataNote)"; return
    }
    $serverPy = $null; $root = $null
    foreach ($c in @((Join-Path $KitDir 'kit\serve\server.py'), (Join-Path $KitDir 'serve\server.py'))) {
        if (Test-Path -LiteralPath $c -PathType Leaf) {
            $serverPy = $c; $root = Split-Path -Parent (Split-Path -Parent $c); break
        }
    }
    if (-not $serverPy) {
        $script:strataState = 'skip'
        $script:strataNote = 'в составе нет kit\serve\server.py - морды в архиве нет вовсе (присутствие меряет гейт 4b $KIT_PRESENCE в pack_kit.ps1)'
        Say "  [NOT MEASURED] $($script:strataNote)"
        return
    }
    $indexHtml = Join-Path $root 'serve\web\index.html'
    Say ("  сервер     : {0} ({1})" -f $serverPy, (Format-Bytes (Get-Size $serverPy)))
    Say ("  ROOT копии: {0} (ROOT = parents[1] от serve\server.py, server.py:61)" -f $root)
    Say ("  index.html : {0} ({1})" -f $indexHtml, (Format-Bytes (Get-Size $indexHtml)))

    $py = $Python
    if (-not $py) {
        $rt = Join-Path $KitDir 'kit\runtime\python\python.exe'
        if (Test-Path -LiteralPath $rt -PathType Leaf) { $py = $rt }
        else {
            $onPath = Get-Command python -ErrorAction SilentlyContinue
            if ($onPath) { $py = $onPath.Source }
        }
    }
    if (-not $py -or -not (Test-Path -LiteralPath $py -PathType Leaf)) {
        $script:strataState = 'skip'
        $script:strataNote = 'python не найден (ни -Python, ни kit\runtime\python\, ни в PATH) - на этом раннере морду Страты поднять нечем'
        Say "  [NOT MEASURED] $($script:strataNote)"; return
    }
    $eap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $verLine = ((& $py -c "import sys; print('%d.%d' % sys.version_info[:2])" 2>&1 | Select-Object -Last 1) | Out-String).Trim()
    $ErrorActionPreference = $eap
    Say "  python     : $py ($verLine)"
    if ($verLine -notmatch '^3\.(1[1-5])$') {
        $script:strataState = 'skip'
        $script:strataNote = "python $verLine вне ряда колёс комплекта (cp311..cp315, pack_kit.ps1 `$VENDOR_ABIS) - сервер не импортируется по вине входа, а не бандла"
        Say "  [NOT MEASURED] $($script:strataNote)"; return
    }
    $abi = 'cp' + ($verLine -replace '\.', '')
    $vendor = Join-Path $KitDir 'kit\vendor'
    $ppParts = @()
    if (Test-Path -LiteralPath $vendor) {
        foreach ($d in @((Join-Path $vendor $abi), (Join-Path $vendor 'py3-none-any'))) {
            if (Test-Path -LiteralPath $d) { $ppParts += $d }
        }
    }
    if ($env:PYTHONPATH) { $ppParts += $env:PYTHONPATH }
    Say ("  vendor     : {0} ({1})" -f $vendor, $(if (Test-Path -LiteralPath $vendor) { 'есть' } else { 'нет' }))
    if ($ppParts.Count) { $env:PYTHONPATH = $ppParts -join ';' }
    $env:PYTHONIOENCODING = 'utf-8'
    $env:PYTHONUTF8 = '1'
    foreach ($v in @('STRATA_API_KEY', 'STRATA_TELEMETRY_KEY')) {
        if (Test-Path -LiteralPath "Env:$v") { Remove-Item -LiteralPath "Env:$v" -ErrorAction SilentlyContinue }
    }

    # Замыкание импортов проверяется ДО запуска: дешевле, чем гадать по молчаливому таймауту.
    # Меряется ровно тот набор, что доливайка кладёт в kit\vendor (первичник - pack_kit.ps1:141-158
    # и $RUNTIME_VENDOR_IMPORTS = "jinja2, regex" на :281), плюс tools\strata_tokenizer.py: его
    # сервер конструирует на первом запросе (server.py:5036 -> strata_tokenizer.py:24 `import regex`).
    # Поверхностный «import serve.server» этого не ловил: сервер поднимался и умирал уже в
    # Service.__init__ (замер 14.11 на fixture без kit\vendor: ModuleNotFoundError: regex, код 1),
    # и отсутствие vendor выглядело находкой в бандле, а не непригодным входом.
    $probe = @(
        'import sys'
        "sys.path.insert(0, r'$root')"
        "sys.path.insert(1, r'$root\tools')"
        'import serve.server'
        'import jinja2, regex'
        'from strata_tokenizer import PromptEncoder'
        "print('ok')"
    ) -join [Environment]::NewLine
    $probeFile = Join-Path $script:workRoot 'import-probe.py'
    [System.IO.File]::WriteAllText($probeFile, $probe, (New-Object System.Text.UTF8Encoding($false)))
    $eap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    # именно позиционный путь файла, а не -File: это PowerShell-флаг, python на нём печатает
    # «Try `python -h'» и выходит с кодом использования, то есть нога ложно краснела бы.
    $imp = & $py $probeFile 2>&1
    $impRc = $LASTEXITCODE
    $ErrorActionPreference = $eap
    if ($impRc -ne 0) {
        foreach ($line in @($imp | Select-Object -Last 8)) { Write-Host "      | $line" }
        if ($ppParts.Count -eq 0) {
            $script:strataState = 'skip'
            $script:strataNote = "serve.server с его vendor-замыканием (jinja2/regex) не импортируется, а kit\vendor в архиве нет (доливайку меряет гейт 4b pack_kit.ps1) - нога не мерялась"
            Say "  [NOT MEASURED] $($script:strataNote)"
            return
        }
        $script:strataState = 'found'
        $script:strataNote = "замыкание импортов serve.server не замкнулось (rc $impRc) при наличии kit\vendor - морда не поднимется"
        Say "  НАХОДКА: $($script:strataNote)"
        return
    }
    Say '  замыкание импортов serve.server + jinja2/regex/strata_tokenizer - ok'

    # Выбор режима: real требует движок из bin\, модель и токенизатор; без них - объективная
    # причина, и нога меряется на mock (тот же сервер, то же web\, движок не поднимается).
    $strataExe = Join-Path $KitDir 'bin\strata-q36.exe'
    $tok = $StrataTokenizer
    if (-not $tok) {
        foreach ($c in @((Join-Path $KitDir 'kit\run\tokenizer'), (Join-Path $root 'run\tokenizer'))) {
            if (Test-Path -LiteralPath (Join-Path $c 'vocab.json') -PathType Leaf) { $tok = $c; break }
        }
    }
    $mode = $Strata
    $why = @()
    if ($Strata -eq 'auto') {
        if (-not (Test-Path -LiteralPath $strataExe -PathType Leaf)) { $why += "нет движка $strataExe" }
        if (-not $tok) { $why += 'нет токенизатора (vocab.json): экстракция из крошечной GGUF - не предмет этого гейта' }
        if (-not $StrataModel) { $why += 'нет модели Страты (-StrataModel): крошечная GGUF не является моделью Страты' }
        $mode = if ($why.Count -eq 0) { 'real' } else { 'mock' }
    }
    if ($mode -eq 'real') {
        Say '  режим      : real (движок Страты поднимается подпроцессом сервера, server.py:1230)'
    } else {
        Say '  режим      : mock (сервер и web\ из бандла, движок не поднимается)'
        foreach ($w in $why) { Say "    объективная причина: $w" }
    }

    $port = Get-FreePort 'strata'
    if ($port -le 0) {
        $script:strataState = 'skip'
        $script:strataNote = "нет свободного порта в диапазоне $PortStart..$($PortStart + $PortCount - 1)"
        Say "  [NOT MEASURED] $($script:strataNote)"; return
    }

    $cmd = @((Quote-Arg $serverPy), '--host', '127.0.0.1', '--port', [string]$port, '--no-api-key')
    if ($mode -eq 'real') {
        $cfgOut = Join-Path $script:workRoot 'strata.json'
        $cfg = [ordered]@{
            exe       = $strataExe
            cwd       = $KitDir
            args      = @('--native', $StrataModel, '--max-context', '512')
            tokenizer = $tok
            model_name = 'smoke-kit'
            host      = '127.0.0.1'
            port      = $port
            log       = (Join-Path $script:workRoot 'strata-engine.log')
            lazy_load = $true
        }
        [System.IO.File]::WriteAllText($cfgOut, ($cfg | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
        $cmd = @((Quote-Arg $serverPy), '--engine', 'strata', '--config', (Quote-Arg $cfgOut),
                 '--host', '127.0.0.1', '--port', [string]$port, '--no-api-key', '--lazy')
    } else {
        $cmd = @((Quote-Arg $serverPy), '--engine', 'mock', '--host', '127.0.0.1', '--port', [string]$port, '--no-api-key')
    }
    $readyJson = Join-Path $script:workRoot 'ready.json'
    $cmd += @('--ready-file', (Quote-Arg $readyJson))
    Say "  команда    : $(Split-Path -Leaf $py) $($cmd -join ' ')"

    $outF = Join-Path $script:workRoot 'strata.out.log'
    $errF = Join-Path $script:workRoot 'strata.err.log'
    try { $sp = Start-Detached $py $cmd $root $outF $errF } catch {
        $script:strataState = 'found'
        $script:strataNote = "сервер морды не запущен: $($_.Exception.Message)"
        Say "  НАХОДКА: $($script:strataNote)"; return
    }
    Say "  pid        : $($sp.Id)"

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $deadline = [System.TimeSpan]::FromSeconds($WaitSec)   # TimeSpan, а не DateTime: у Stopwatch
                                                            # Elapsed тоже TimeSpan, сравнение одномерное
    $ready = $false; $polls = 0; $died = $false
    while ($sw.Elapsed -lt $deadline) {
        $polls++
        if ($sp.HasExited) { $died = $true; break }
        $r = Get-Http "http://127.0.0.1:$port/health"
        if ($r.Code -eq 200) { $ready = $true; break }
        Start-Sleep -Milliseconds 500
    }
    if ($died) {
        $code = -1
        try { $code = $sp.ExitCode } catch { }
        $script:strataState = 'found'
        $script:strataNote = "serve\server.py завершился (код $code), не подняв HTTP"
        Say "  ИСХОД: ПРОЦЕСС УМЕР, код=$code (0x$('{0:X8}' -f $code)) через $([int]$sw.Elapsed.TotalSeconds) с, попыток HTTP: $polls"
        Show-Tail $errF 20 'stderr сервера'
        Show-Tail $outF 20 'stdout сервера'
        Say "  НАХОДКА: $($script:strataNote)"
        return
    }
    if (-not $ready) {
        $script:strataState = 'found'
        $script:strataNote = "/health не ответил за $WaitSec с (процесс жив, pid $($sp.Id))"
        Say "  ИСХОД: ТАЙМАУТ $WaitSec с, процесс жив, попыток HTTP: $polls"
        Show-Tail $errF 15 'stderr сервера'
        Show-Tail $outF 25 'stdout сервера'
        Say "  НАХОДКА: $($script:strataNote)"
        return
    }
    Say "  ИСХОД: ГОТОВ через $([int]$sw.Elapsed.TotalSeconds) с (/health 200, server.py:8255), попыток HTTP: $polls"

    $rootResp = Get-Http "http://127.0.0.1:$port/"
    $problem = Test-HtmlPage $rootResp
    $script:strataState = 'green'
    if ($problem) {
        $script:strataState = 'found'
        $script:strataNote = "GET / не отдаёт HTML: $problem"
        Say "  GET /      : НАХОДКА - $problem"
    } else {
        $refs = 0
        foreach ($needle in @('web/app.js', 'web/app.css')) { if ($rootResp.Body -match [regex]::Escape($needle)) { $refs++ } }
        Say ("  GET /      : 200, $($rootResp.ContentType), тело $($rootResp.Body.Length) Б, ссылок на app.js/app.css: $refs из 2")
        if ($refs -lt 2) {
            $script:strataState = 'found'
            $script:strataNote = 'в теле / нет ссылок на web/app.js и web/app.css - это не морда'
            Say "  НАХОДКА: $($script:strataNote)"
        }
    }
    # Отдельная мера, а не догадка: путь нормализуется rstrip('/') (server.py:7952) и сравнивается
    # с пустой строкой (server.py:8245), поэтому /index.html в реестре маршрутов нет.
    $idxResp = Get-Http "http://127.0.0.1:$port/index.html"
    Say ("  GET /index.html : код {0} - так и задумано: HTML раздаётся ТОЛЬКО по / (server.py:8245, :7952)" -f $(if ($null -eq $idxResp.Code) { 'нет ответа' } else { $idxResp.Code }))
    $propsResp = Get-Http "http://127.0.0.1:$port/props"
    Say ("  GET /props      : код {0}" -f $(if ($null -eq $propsResp.Code) { 'нет ответа' } else { $propsResp.Code }))
    if ($propsResp.Code -eq 401) {
        $script:strataState = 'found'
        $script:strataNote = '/props требует ключ, хотя ключ снят (--no-api-key)'
        Say "  НАХОДКА: $($script:strataNote)"
    }
    $rs = Get-Size $readyJson
    if ($rs -lt 0) {
        Say "  ready-файл не появился ($readyJson) - при mock-движке это не находка, сервер обязан дописать его сам (server.py:10630)"
    } else {
        Say "  ready-файл: $rs Б"
    }
    $script:strataNote = if ($script:strataState -eq 'green') { "режим $mode, готов за $([int]$sw.Elapsed.TotalSeconds) с, HTML / = $($rootResp.Body.Length) Б" } else { $script:strataNote }
    Stop-ProcTree ([int]$sp.Id)
    try { $sp.WaitForExit(5000) | Out-Null } catch { }
}

Invoke-StrataLeg

# --------------------------------------------------------------------------- итог
Step 'Итог по ногам'
Say ("  llama-нога  : {0} - {1}" -f $script:llamaState, $(if ($script:llamaNote) { $script:llamaNote } else { 'без деталей' }))
Say ("  Страта-нога : {0} - {1}" -f $script:strataState, $(if ($script:strataNote) { $script:strataNote } else { 'без деталей' }))

$foundCount = @($script:llamaState, $script:strataState) | Where-Object { $_ -eq 'found' }
$measured = @($script:llamaState, $script:strataState) | Where-Object { $_ -in @('green', 'found') }
if ($script:llamaState -eq 'skip') { Write-Host "[NOT MEASURED] llama-нога: $($script:llamaNote)" }
if ($script:strataState -eq 'skip') { Write-Host "[NOT MEASURED] Страта-нога: $($script:strataNote)" }
Say ("  мерявшихся ног: {0} из 2, находок: {1}" -f $measured.Count, $foundCount.Count)
Invoke-Cleanup

if ($foundCount.Count -gt 0) {
    Write-Host ''
    Write-Host 'НАХОДКА: комплект неживой - публикация невозможна.'
    exit 1
}
if ($measured.Count -eq 0) {
    Write-Host ''
    Write-Host '[NOT MEASURED] ни одна нога не мерялась: входы непригодны, выход 2.'
    exit 2
}
Write-Host ''
Write-Host 'ВСЁ ЗЕЛЁНОЕ: мёртвый движок этим прогоном не пропущен.'
exit 0
