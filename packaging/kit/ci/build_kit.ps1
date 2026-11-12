<#
    Часть 4.3 в CI-раскладке: сборка двух движков под портативный комплект и её меры.

    Это копия стендового скрипта сборки комплекта, доведённая до запуска там, где нет стенда:
    каталоги исходников, вывода, тулчейна CUDA и Visual Studio задаются только параметрами,
    а не выводятся из положения скрипта и не зашиты литералами. Наборы флагов configure и цели
    сборки - те же, что на стенде: иначе «доказано в Actions» нельзя переносить на локальную
    сборку. Контроль точного списка -D-ключей живёт в -SelfTest.

    Запуск под pwsh 7 (в GitHub Actions windows-раннер - PowerShell 7):

        pwsh -File packaging/kit/ci/build_kit.ps1 -SelfTest
        pwsh -File packaging/kit/ci/build_kit.ps1 -StrataSrc . -LlamaSrc ../llama.cpp `
             -Cuda ../cuda -Out ../dist -Engines "strata;llama" -Arch "86;89;120"

    Что делает:
      1. настраивает и собирает Страту (цели strata, strata-q36) и llama.cpp (llama-server)
         под список архитектур; PORTABLE включён по умолчанию, иначе комплект собран под это
         железо, а не под чужое;
      2. меряет время каждой сборки;
      3. по желанию меряет предельную цену архитектуры прогонником по compile_commands.json
         (-ProbeScript: в Actions этот скрипт не нужен и время жрёт, поэтому по умолчанию
         пропуск явно печатается, а не молча происходит);
      4. доказывает архитектуры фактом: cuobjdump --list-elf по каждому бинарнику.

    Коды возврата: 0 всё собрано и доказано; 1 сборка или проверка провалились;
    2 вход неверен (нет исходников или компилятора, пустой список архитектур).
#>
[CmdletBinding()]
param(
    [string]$Arch = "86;89;120",
    [string]$Cuda = "",
    [string]$Vs = "",
    [string]$Out = "",
    [string]$Engines = "strata",
    [string]$GgmlDir = "",
    [string]$LlamaSrc = "",
    [string]$StrataSrc = "",
    [string]$StrataBuildDir = "",
    [string]$LlamaBuildDir = "",
    [string]$ProbeScript = "",
    [switch]$NoPortable,
    [switch]$SkipProbe,
    [switch]$SkipElfCheck,
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
# Логи уходят в файл, а консоль PowerShell по умолчанию пишет в OEM-странице - русские строки тогда
# нечитаемы. Разворачиваем вывод в UTF-8 до первого же сообщения.
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Функции объявлены до любой работы - так их виджет-проверка (-SelfTest) доступна без тулчейна,
# CUDA и исходников: мерка разборывания вывода cuobjdump обязана запускаться где угодно.

function Join2([string]$base, [string]$tail) {
    # Join-Path бросает исключение, если диск в пользовательском пути не существует (проверено меркой
    # отказов: "-Cuda X:\нет" давал стек-трейс вместо причины). Сборка обязана отказывать сама, поэтому
    # пути склеиваются строкой, а проверяются через Test-Path.
    if (-not $base) { return $tail }
    return ($base.TrimEnd('\', '/')) + '\' + $tail
}

function Invoke-Capture([string]$LogFile, [scriptblock]$Body) {
    # $LASTEXITCODE из-под Measure-Command наружу не виден (дочерняя область),
    # поэтому код снимаем здесь же и отдаём вместе с временем.
    #
    # Логи пишутся вручную, без Tee-Object: у Windows PowerShell 5.1 параметра -Encoding у
    # Tee-Object нет вовсе (в прошлый правку именно ParameterBindingException ронял конвейер ещё
    # до запуска компилятора, а сборка отрапортовывала «rc=0 за 0 секунд»), а pwsh- вариант всё
    # равно ничего не сообщает о том, выполнился ли источник. Поэтому пишем сами и проверяем, что
    # прогон оставил после себя и код возврата, и строки в логе.
    $script:LASTRc = $null
    $before = if (Test-Path $LogFile) { (Get-Item $LogFile).Length } else { -1 }
    $t = Measure-Command {
        $lines = @(& $Body *>&1 | ForEach-Object { "$_" })
        # Пустой вывод здесь - не «тихая успешная команда», а признак того, что конвейер не
        # выполнился: при ошибке привязки параметра в приёмнике PowerShell не вызывает источник
        # вообще, и $LASTEXITCODE сохраняет значение предыдущей команды (так и получался «rc=0»).
        if ($lines.Count -eq 0) {
            throw "конвейер не выдал ни строки - команда не запустилась (лог $LogFile)"
        }
        $lines | Out-File -FilePath $LogFile -Append -Encoding utf8
        $script:LASTRc = $LASTEXITCODE
    }
    $sec = [math]::Round($t.TotalSeconds, 1)
    $after = if (Test-Path $LogFile) { (Get-Item $LogFile).Length } else { -1 }
    if ($null -eq $script:LASTRc) {
        throw "команда не вернула код возврата - прогон не состоялся (${sec} с, лог $LogFile)"
    }
    if ($after -le $before) {
        throw "в $LogFile не добавилось ни байта - прогон не состоялся (${sec} с, rc=$($script:LASTRc))"
    }
    # log_start нужен мере работы: после этого шага в тот же лог дописываются другие шаги
    # (elf-доказательство, cuobjdump), поэтому «последние log_bytes байт» уезжают в середину
    # чужой строки. На прогоне 00:14 это и дало 22 компиляции там, где лог показывает 160.
    return [pscustomobject]@{ sec = $sec; rc = $script:LASTRc; log_bytes = $after - $before
                              log_start = [math]::Max($before, 0) }
}

# Прогон не состоялся - не то же самое, что сборка упала: здесь виноват сам скрипт,
# и честный ответ ему rc=2 (иначе «0 с, rc=0» уйдёт в меры как успешная сборка).
function Invoke-BuildStep([string]$LogFile, [string]$What, [scriptblock]$Body) {
    try {
        return Invoke-Capture $LogFile $Body
    } catch {
        Write-Host "ОТКАЗ: ${What}: $($_.Exception.Message)"
        exit 2
    }
}

function Assert-FreshCache([string]$BuildDir, [string]$SrcDir) {
    # Перенесённый кэш молча компилирует чужое дерево (проверено 10.11): сверяем домашний каталог.
    $cache = Join2 $BuildDir "CMakeCache.txt"
    if (-not (Test-Path $cache)) { return }
    $line = Select-String -Path $cache -Pattern '^CMAKE_HOME_DIRECTORY:INTERNAL=(.+)$' | Select-Object -First 1
    if (-not $line) { throw "в $cache нет CMAKE_HOME_DIRECTORY - кэш непонятен, собрать в чистом каталоге" }
    $home_ = $line.Matches[0].Groups[1].Value.TrimEnd('\', '/')
    if ($home_.Replace('\', '/') -ne $SrcDir.Replace('\', '/')) {
        throw "кэш $BuildDir указывает на $home_, а нужен ${SrcDir}: удали кэш или возьми другой каталог сборки"
    }
    # Второй способ, которым кэш врёт: в него записалось НЕраскрытое имя переменной вместо пути.
    # Так вышло 10.11 на этом стенде - CMake получил `-DCMAKE_CUDA_COMPILER=$nvcc` дословно
    # (PowerShell съел токен как имя параметра), и кэш с литералом «$nvcc» остался лежать в
    # build-kit. Даже после починки вызова такой кэш переживает прогон и объясняет отказ тем,
    # чего в команде уже нет, поэтому проверка живёт здесь, а не в тексте ошибки сборки.
    $cc = Select-String -Path $cache -Pattern '^CMAKE_CUDA_COMPILER:[^=]*=(.+)$' | Select-Object -First 1
    if ($cc -and $cc.Matches[0].Groups[1].Value -match '\$\{?\w') {
        throw "кэш $BuildDir записал компилятор как «$($cc.Matches[0].Groups[1].Value)» - это нераскрытая " +
              "переменная, а не путь: удали каталог сборки $BuildDir целиком"
    }
}

function Split-FatbinLines([string[]]$Lines) {
    # Разбор вывода cuobjdump 13.3: `ELF file 12: strata-q36.12.sm_86.cubin` и
    # `PTX file 12: ….sm_86.ptx` - НЕ `arch = sm_86`. Прежний парсер ждал именно `arch =`,
    # поэтому на настоящем выводе получал пустой список, а запись в build-measure.json
    # выглядела как успешно выполненный прогон. Считаются только строки-записи списка,
    # и заодно видно СКОЛЬКО cubin на каждую арх (у multi-arch сборки их десятки, и
    # «список уникальных» это скрывал).
    $counts = [ordered]@{}
    foreach ($s in @($Lines)) {
        if ($s -notmatch '^(ELF|PTX) file\s+\d+:') { continue }
        foreach ($tok in ($s -replace '[.\s]', ' ' -split '\s+')) {
            if ($tok -match '^(sm_\d\d\d?[af]?|compute_\d\d\d?[af]?)$') {
                if (-not $counts.Contains($tok)) { $counts[$tok] = 0 }
                $counts[$tok] = $counts[$tok] + 1
            }
        }
    }
    return $counts
}

function Get-FatbinList([string]$Exe, [string]$Flag) {
    $out = @(& $script:cuobj $Flag $Exe 2>&1 | ForEach-Object { "$_" })
    return [pscustomobject]@{ rc = $LASTEXITCODE; counts = Split-FatbinLines $out; lines = $out.Count }
}

function Get-ArchProofTag($CubinArchs, [string]$Num) {
    # Чем именно доказано наличие архитектуры. суффиксы "a" и "f" - это код той же
    # вычислительной способности, а не чужой: nvcc для -arch=sm_90a даёт architecture-specific
    # реальный gpu-код sm_90a (CUDA Compiler Driver, --gpu-architecture), и llama.cpp просит
    # 120a-real осознанно (ggml/src/ggml-cuda/CMakeLists.txt:51). Поэтому cubin sm_120a
    # закрывает требование 120, а sm_121a - нет, и имя тега пишется в сайдкар как факт.
    foreach ($t in @("sm_$Num", "sm_${Num}a", "sm_${Num}f")) {
        if (@($CubinArchs) -contains $t) { return $t }
    }
    return $null
}

function Get-ArchProofMap($CubinArchs, [string[]]$WantNums) {
    # таблица «архитектура -> каким cubin-тегом доказана» (null - не доказана)
    $map = [ordered]@{}
    foreach ($n in @($WantNums)) { $map["sm_$n"] = Get-ArchProofTag $CubinArchs $n }
    return $map
}

function Get-CubinVerdict($CubinArchs, [string[]]$WantNums, [bool]$CarriesCuda) {
    # Вердикт вынесен в функцию, чтобы его можно было проверить selftest'ом: на стенде этот
    # гейт покрасил полностью удачную сборку llama, потребовав fatbin у llama-server.exe -
    # обёртки в 10 КиБ, весь CUDA-код которой лежит в ggml-cuda.dll. Отсутствие cubin у
    # обёртки ничего не опровергает, поэтому провалом меры оно не считается.
    if (-not $CarriesCuda) { return @() }
    $have = @($CubinArchs)
    if ($have.Count -eq 0) {
        return @("cubin не найден ни в одном виде - архитектуры не доказаны, проверка не состоялась")
    }
    $missing = @($WantNums | Where-Object { -not (Get-ArchProofTag $have $_) })
    if ($missing) { return @("нет cubin для $(($missing -join ',')) - архитектура не доказана") }
    return @()
}

function Get-KqTypes([string]$CmakeFile) {
    # Какие K-quant инстансы Страта требует от ggml-дерева: список живёт в её же cmake
    # (set(_strata_kq_types ...)), переписывать его сюда константой значит разойтись с
    # апстримом в тот вечер, когда апстрим его правит.
    $types = @()
    foreach ($l in @(Get-Content -LiteralPath $CmakeFile -ErrorAction SilentlyContinue)) {
        if ($l -match 'set\(\s*_strata_kq_types\s+(.+)') {
            $types = @((($matches[1] -replace '[)].*$', '').Trim()) -split '\s+')
        }
    }
    return @($types | Where-Object { $_ })
}

function Get-KqMissing([string]$InstDir, [string[]]$Types) {
    # Чего не хватает в этом ggml-дереве. Пустой список при непустом запросе - значит дерево
    # годится; пустой запрос caller разбирает сам, как «проверка не состоялась».
    return @($Types | Where-Object { -not (Test-Path (Join2 $InstDir "mmq-instance-$_.cu")) })
}

function Get-BuildWork([string]$LogFile, [long]$Start, [long]$Delta) {
    # Сколько НАСТОЯЩЕЙ работы сделал прогон: строки компиляции и линковки, которые печатает сам
    # ninja. Фраза "ninja: no work to do" для этой меры не авторитет - прогон может смолчать и по
    # другой причине, а «0 с, rc=0» без разбора неотличим от полной сборки.
    #
    # Нужен ровно тот кусок, который добавил этот шаг: [Start, Start+Delta). Прежний отсчёт
    # «последние Delta байт от конца файла» молча ломался, как только в тот же лог после сборки
    # дописывалось что-нибудь ещё, - окно уезжало в середину строки компиляции и мерял меньше
    # работы (проверено 12.11 на cold-прогоне Страты: мера 22 компиляции при 160 в том же логе).
    if ($Delta -le 0 -or -not (Test-Path $LogFile)) {
        return [pscustomobject]@{ compiles = 0; links = 0; bytes = 0 }
    }
    $text = ""
    $fs = [System.IO.File]::OpenRead($LogFile)
    try {
        [void]$fs.Seek($Start, [System.IO.SeekOrigin]::Begin)
        $take = [long]($fs.Length - $Start)
        if ($Delta -lt $take) { $take = $Delta }
        $buf = New-Object byte[] $take
        $got = 0
        while ($got -lt $take) {
            $n = $fs.Read($buf, $got, [int]($take - $got))
            if ($n -le 0) { break }
            $got += $n
        }
        $text = [System.Text.Encoding]::UTF8.GetString($buf, 0, $got)
    } finally { $fs.Dispose() }
    $c = ([regex]::Matches($text, '(?im)^\s*\[\d+/\d+\] Building (CUDA|CXX|C) object')).Count
    $l = ([regex]::Matches($text, '(?im)^\s*\[\d+/\d+\] Linking ')).Count
    return [pscustomobject]@{ compiles = $c; links = $l; bytes = $text.Length }
}

function Get-PrevBuild([string]$OutDir, [string]$Engine) {
    # Прежняя measure-запись движка, снятая на реальной компиляции. Нужна потому, что повторный
    # прогон скрипта на тёплом кэше собирает ноль файлов за ноль секунд, а «время сборки» в
    # отчёте комплекта - это время полной компиляции под все архитектуры, и подменять его
    # нулями нельзя: читатель принял бы 0.4 с за цену сборки трёх архитектур.
    foreach ($name in @("build-measure.json", "build-measure.partial.json")) {
        $p = Join2 $OutDir $name
        if (-not (Test-Path $p)) { continue }
        $o = $null
        try { $o = Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json } catch { continue }
        $e = $o.engines.$Engine
        if ($e -and $e.build_kind -ne "no-op" -and $e.build_s) {
            return [pscustomobject]@{ build = $e; started = $o.started; from = $name }
        }
    }
    return $null
}

function Write-Utf8([string]$Path, $Lines) {
    # Set-Content/Add-Content с -Encoding utf8NoBOM понимает только PowerShell 6+, а прод-сборка
    # идёт системным 5.1 (обёртки cold3/sync3 зовут powershell.exe): под 5.1 контролы, которые так
    # пишут образцы логов, молча не создавали файл и краснели как «мера сломана», хотя мера цела.
    # .NET-запись даёт один и тот же UTF-8 без BOM на обоих интерпретаторах.
    $body = if ($Lines -is [string]) { $Lines } else { ($Lines -join "`n") }
    [System.IO.File]::WriteAllText($Path, ($body + "`n"), (New-Object System.Text.UTF8Encoding($false)))
}

function Add-Utf8([string]$Path, [string]$Line) {
    [System.IO.File]::AppendAllText($Path, ($Line + "`n"), (New-Object System.Text.UTF8Encoding($false)))
}

function Write-Json($Object, [string]$Path, [int]$Depth) {
    # Без BOM: kit\classify.py читает elf-proof.json и build-measure.json как JSON, а
    # `Set-Content -Encoding UTF8` в Windows PowerShell 5.1 приписывает в начало EF BB BF, и
    # json.loads на таком файле падает с «Unexpected UTF-8 BOM» - то есть доказательство
    # архитектур переставало читаться ровно на той машине, для которой комплект и собран.
    [System.IO.File]::WriteAllText($Path, ($Object | ConvertTo-Json -Depth $Depth),
                                   (New-Object System.Text.UTF8Encoding($false)))
}

function Set-EngineMeasure([string]$EngineName, [string]$Src, [string]$BuildDir, $Cfg, $Build,
                           [string]$LogFile, [string]$Measures) {
    # Единообразная запись меры движка: у llama и Страты она была скопирована дважды, и пропуск
    # no-op-проверки в одной из копий дал бы молчаливую подмену времени сборки нулями.
    $work = Get-BuildWork $LogFile $Build.log_start $Build.log_bytes
    $noop = ($work.compiles + $work.links) -eq 0
    $kind = if ($noop) { "no-op" } else { "полная компиляция" }
    # Мера обязана называть коммит носителя: без него время сборки, размеры и cuobjdump описывают
    # «какую-то» вершину, и приёмка комплекта не может доказать, что байты в архиве сняты с того же
    # дерева, которое названо в аудите синка.
    $commit = "ПУСТО"; $branch = "ПУСТО"; $dirty = -1
    $head = & git -C $Src rev-parse --short HEAD 2>$null | Select-Object -First 1
    if ($head) {
        $commit = ("$head").Trim()
        $branch = ("$(& git -C $Src rev-parse --abbrev-ref HEAD 2>$null | Select-Object -First 1)").Trim()
        $dirty  = @(& git -C $Src status --porcelain 2>$null).Count
    } else {
        Write-Host ("  ВНИМАНИЕ ${EngineName}: git не назвал HEAD в $Src - мера сборки без " +
                    "коммита-носителя, приёмка комплекта не доказуема")
    }
    $m = [ordered]@{
        source       = $Src
        branch       = $branch
        commit       = $commit
        dirty_paths  = $dirty
        build_dir    = $BuildDir
        configure_s  = $Cfg.sec
        configure_rc = $Cfg.rc
        build_s      = $Build.sec
        build_rc     = $Build.rc
        build_kind   = $kind
        build_compiles = $work.compiles
        build_links    = $work.links
        build_log_bytes = $Build.log_bytes
    }
    if ($noop) {
        $prev = Get-PrevBuild $Measures $EngineName
        if ($prev) {
            # Время полной компиляции берём из прежнего замера и открыто говорим, откуда оно.
            $m.build_s = $prev.build.build_s
            $m.build_s_this_run = $Build.sec
            $m.build_s_at = $prev.started
            $m.build_s_from = $prev.from
            Write-Host ("  ${EngineName}: прогон ничего не компилировал ({0} с) - время сборки " +
                        "взято из реальной компиляции {1} с (замер {2}, {3})" -f `
                        $Build.sec, $prev.build.build_s, $prev.started, $prev.from)
        } else {
            $m.build_s = $null
            Write-Host ("  ВНИМАНИЕ ${EngineName}: прогон ничего не компилировал, а прежней меры " +
                        "полной сборки нет - время сборки НЕ измерено, в отчёт его ставить нельзя")
        }
    }
    return $m
}

if ($SelfTest) {
    # Контроли разбора и гейта «прогон не состоялся». Отдельно от сборки: этот прогон не трогает
    # компилятор, поэтому обязан работать и на машине без тулчейна.
    $ErrorActionPreference = "Continue"
    $script:ok = 0; $script:bad = 0
    function Chk([string]$Name, $Got, $Want) {
        if ([string]$Got -eq [string]$Want) {
            $script:ok++; Write-Host "  ok   $Name"
        } else {
            $script:bad++; Write-Host "FAIL   ${Name}: получено '$Got', ожидалось '$Want'"
        }
    }
    Write-Host "build_kit.ps1 selftest"
    Chk "Join2 без завершающего слэша" (Join2 "C:\a" "b\c") "C:\a\b\c"
    Chk "Join2 с завершающим слэшем" (Join2 "C:\a\" "b") "C:\a\b"
    Chk "Join2 с пустой базой" (Join2 "" "b\c") "b\c"
    $sample = @("arch = sm_86",
                "ELF file 1: strata-q36.1.sm_86.cubin",
                "ELF file 2: strata-q36.2.sm_120a.cubin",
                "ELF file 3: strata-q36.3.sm_86.cubin",
                "Fatbin elf code:", "================")
    $c = Split-FatbinLines $sample
    Chk "записей cubin найдено" $c.Count 2
    Chk "sm_86 посчитан по двум записям" $c["sm_86"] 2
    Chk "sm_120a посчитан" $c["sm_120a"] 1
    Chk "строка старого формата не дала ключа" ($c.Contains("arch = sm_86")) $false
    Chk "пустой ввод даёт пустой список" (Split-FatbinLines @()).Count 0
    # Гейт cubin: обёртка не обязана нести fatbin, носитель - обязан. Без этого контроля
    # правка «llama-сборка не должна краснеть» ничем не отличается от правки «убрать проверку».
    Chk "обёртка без cubin - не провал" (Get-CubinVerdict @() @("86", "89") $false).Count 0
    Chk "носитель без cubin - провал" (Get-CubinVerdict @() @("86") $true).Count 1
    Chk "провал носителя назван проверкой не состоявшейся" `
        ((@(Get-CubinVerdict @() @("86") $true))[0] -like "*не состоялась*") $true
    Chk "носитель с неполным покрытием - провал" `
        ((@(Get-CubinVerdict @("sm_86", "sm_89") @("86", "89", "120") $true))[0] -like "*120*") $true
    Chk "полное покрытие - без провалов" (Get-CubinVerdict @("sm_86", "sm_89", "sm_120a") @("86", "89") $true).Count 0
    # Суффикс arch-specific cubin (a/f) - та же вычислительная способность, и так же думает
    # kit\classify.py (arch_code). Без этих двух контролиров «принять sm_120a за 120» неотличимо
    # от «перестать проверять покрытие»: второй контроль обязан остаться красным.
    Chk "sm_120a закрывает 120" (Get-ArchProofTag @("sm_86", "sm_120a") "120") "sm_120a"
    Chk "чужой суффикс 120 не закрывает" (Get-ArchProofTag @("sm_86", "sm_121a") "120") $null
    Chk "непокрытая архитектура при частичном списке - провал" `
        ((@(Get-CubinVerdict @("sm_86", "sm_121a") @("86", "120") $true))[0] -like "*120*") $true
    Chk "map доказывает базовым тегом" (Get-ArchProofMap @("sm_86") @("86"))["sm_86"] "sm_86"
    # Префлайт ggml-дерева: список типов читается из чужого cmake, поэтому обязана сработать
    # и его вычитка, и отсутствие строки (пустой список = проверка не состоялась, а не «всё есть»).
    $kc = Join2 ([System.IO.Path]::GetTempPath()) "build-kit-kq.cmake"
    Write-Utf8 $kc @('    set(_strata_mmq_cuda_types ${_strata_mmq_types})',
                    '    set(_strata_kq_types q2_k q4_k q5_k q5_1 q6_k)',
                    '    set(_strata_kq_dso ON)')
    Chk "K-quant типы вычитаны из cmake" ((@(Get-KqTypes $kc)) -join ' ') "q2_k q4_k q5_k q5_1 q6_k"
    Write-Utf8 $kc "    set(SOMETHING_ELSE 1)"
    Chk "cmake без списка даёт пустой список" (@(Get-KqTypes $kc).Count) 0
    Chk "несуществующий файл - пустой список" (@(Get-KqTypes (Join2 ([System.IO.Path]::GetTempPath()) "net-takogo-net-file.cmake")).Count) 0
    Remove-Item $kc -ErrorAction SilentlyContinue
    $log = Join2 ([System.IO.Path]::GetTempPath()) "build-kit-selftest.log"
    Remove-Item $log -ErrorAction SilentlyContinue
    $r = Invoke-Capture $log { & cmd /c echo build-kit-selftest-line }
    Chk "прогон с выводом вернул rc=0" $r.rc 0
    Chk "прогон с выводом дописал лог" ($r.log_bytes -gt 0) $true
    $threw = ""
    try { Invoke-Capture $log { & cmd /c exit 5 } | Out-Null } catch { $threw = $_.Exception.Message }
    Chk "команда без вывода - отказ, а не успешно" ($threw -like "*не запустилась*") $true
    Remove-Item $log -ErrorAction SilentlyContinue
    # Разбор добавки лога: no-op прогон обязан быть отличим от полной компиляции, иначе «0 с,
    # rc=0» уходит в меры как время сборки трёх архитектур.
    $wlog = Join2 ([System.IO.Path]::GetTempPath()) "build-kit-work.log"
    Remove-Item $wlog -ErrorAction SilentlyContinue
    Write-Utf8 $wlog ("prior run noise`n[12/345] Building CUDA object CMakeFiles/x.dir/a.cu.obj`n" +
                "[345/345] Linking CXX executable strata-q36.exe")
    $prevBytes = (Get-Item $wlog).Length
    Add-Utf8 $wlog "ninja: no work to do."
    $delta = (Get-Item $wlog).Length - $prevBytes
    $w = Get-BuildWork $wlog $prevBytes $delta
    Chk "no-op-добавка не содержит компиляций" ($w.compiles + $w.links) 0
    # Весь файл целиком: отсчёт от конца файла попадает в середину строки компиляции, и контрольная
    # строка «видна» перестаёт быть доказательством разбора (проверено: compiles=0 при links=1 на
    # одном и том же куске).
    $wAll = Get-BuildWork $wlog 0 (Get-Item $wlog).Length
    Chk "кусок с компиляцией посчитан" $wAll.compiles 1
    Chk "кусок с линковкой посчитан" $wAll.links 1
    Chk "нулевая добавка - ноль работы, без исключения" (Get-BuildWork $wlog 0 0).compiles 0
    Chk "нет лога - ноль работы, без исключения" (Get-BuildWork (Join2 ([System.IO.Path]::GetTempPath()) "no-such.log") 0 100).links 0
    Remove-Item $wlog -ErrorAction SilentlyContinue
    # Саботаж холодного прогона Страты 12.11 00:14: после сборки в тот же лог дописываются другие
    # шаги, и прежний отсчёт «последние delta байт от конца» уносил окно в хвост, где компиляций
    # почти нет, - мера выдала 22 компиляции там, где этот же лог при полном разборе показывает 160.
    # Значит гейт «ноль компиляций = no-op» краснел бы и на настоящей полной сборке, и на дельте.
    $slog = Join2 ([System.IO.Path]::GetTempPath()) "build-kit-step.log"
    Remove-Item $slog -ErrorAction SilentlyContinue
    $sbuild = Join2 ([System.IO.Path]::GetTempPath()) "build-kit-step-build.txt"
    $snoise = Join2 ([System.IO.Path]::GetTempPath()) "build-kit-step-noise.txt"
    Write-Utf8 $sbuild "ninja: edge 1/3`n[1/3] Building CUDA object CMakeFiles/s.dir/a.cu.obj"
    Write-Utf8 $snoise ("elf-proof listing`n" + ("x" * 400) + "`nKernel fatbin 42 of 99")
    $step1 = Invoke-Capture $slog { & cmd /c type $sbuild }
    $step2 = Invoke-Capture $slog { & cmd /c type $snoise }
    Chk "окно по оффсету считает свой шаг" (Get-BuildWork $slog $step1.log_start $step1.log_bytes).compiles 1
    Chk "чужой шаг не попадает в счёт" (Get-BuildWork $slog $step2.log_start $step2.log_bytes).compiles 0
    Chk "прежнее окно от конца файла теряет компиляцию" `
        (Get-BuildWork $slog ((Get-Item $slog).Length - $step1.log_bytes) $step1.log_bytes).compiles 0
    Remove-Item $slog, $sbuild, $snoise -ErrorAction SilentlyContinue
    # Прежняя мера полной сборки читается только если она сама была полной: no-op прошлого
    # прогона не должен становиться «временем сборки» этого.
    $mdir = Join2 ([System.IO.Path]::GetTempPath()) ("build-kit-prev-" +
               [Guid]::NewGuid().ToString("N").Substring(0, 8))
    New-Item -ItemType Directory -Force -Path $mdir | Out-Null
    Write-Json ([ordered]@{ started = "2026-11-10 19:51:41"
                            engines = [ordered]@{ llama = [ordered]@{ build_s = 2857.6; build_kind = "полная компиляция" } } }) `
               (Join2 $mdir "build-measure.json") 4
    $pv = Get-PrevBuild $mdir "llama"
    Chk "прежняя полная сборка найдена" $pv.build.build_s 2857.6
    Chk "у найденной меры есть дата замера" $pv.started "2026-11-10 19:51:41"
    Write-Json ([ordered]@{ started = "2026-11-10 20:00:00"
                            engines = [ordered]@{ llama = [ordered]@{ build_s = 0.4; build_kind = "no-op" } } }) `
               (Join2 $mdir "build-measure.json") 4
    Chk "no-op не принимается за полную сборку" ($null -eq (Get-PrevBuild $mdir "llama")) $true
    Chk "движок без прежней меры отсутствует" ($null -eq (Get-PrevBuild $mdir "strata")) $true
    Remove-Item -LiteralPath $mdir -Recurse -Force -ErrorAction SilentlyContinue
    # Write-Json обязан давать читаемый classify.py файл: BOM меряется первым байтом, а не
    # «похоже ли содержимое на JSON» - с BOM содержимое тоже похоже, а json.loads падает.
    $bomFile = Join2 ([System.IO.Path]::GetTempPath()) "build-kit-selftest.json"
    Remove-Item $bomFile -ErrorAction SilentlyContinue
    Write-Json ([ordered]@{ note = "сборка доказана"; archs = @("sm_86", "sm_120") }) $bomFile 4
    $raw = [System.IO.File]::ReadAllBytes($bomFile)
    Chk "Write-Json не пишет BOM" ($raw.Length -ge 3 -and $raw[0] -ne 0xEF) $true
    Chk "Write-Json пишет кириллицу без потерь" `
        (([System.Text.Encoding]::UTF8.GetString($raw) | ConvertFrom-Json).note) "сборка доказана"
    Chk "Write-Json отдаёт массив архитектур" `
        (([System.Text.Encoding]::UTF8.GetString($raw) | ConvertFrom-Json).archs.Count) 2
    Remove-Item $bomFile -ErrorAction SilentlyContinue
    # Гейт кэша меряется на настоящем файле: на стенде он уже пропустил две беды - чужой
    # CMAKE_HOME_DIRECTORY и литерал «$nvcc» вместо пути к компилятору.
    $cacheDir = Join2 ([System.IO.Path]::GetTempPath()) "build-kit-selftest-cache"
    New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
    $cacheF = Join2 $cacheDir "CMakeCache.txt"
    $homeLine = 'CMAKE_HOME_DIRECTORY:INTERNAL=C:\proj\src'
    function Write-Cache([string]$Body) {
        [System.IO.File]::WriteAllText($cacheF, $Body + "`n", (New-Object System.Text.UTF8Encoding($false)))
    }
    Write-Cache ($homeLine + "`n" + 'CMAKE_CUDA_COMPILER:UNINITIALIZED=$nvcc')
    $threw = ""
    try { Assert-FreshCache $cacheDir "C:\proj\src" } catch { $threw = $_.Exception.Message }
    Chk "кэш с нераскрытой переменной отклонён" ($threw -like "*нераскрытая*") $true
    Write-Cache ($homeLine + "`n" + 'CMAKE_CUDA_COMPILER:UNINITIALIZED=C:\CUDA\bin\nvcc.exe')
    $threw = ""
    try { Assert-FreshCache $cacheDir "C:\proj\src" } catch { $threw = $_.Exception.Message }
    Chk "кэш с реальным путём принят" $threw ""
    $threw = ""
    try { Assert-FreshCache $cacheDir "C:\other\src" } catch { $threw = $_.Exception.Message }
    Chk "кэш с чужим деревом отклонён" ($threw -like "*указывает на*") $true
    Write-Cache 'CMAKE_CUDA_COMPILER:UNINITIALIZED=C:\CUDA\bin\nvcc.exe'
    $threw = ""
    try { Assert-FreshCache $cacheDir "C:\proj\src" } catch { $threw = $_.Exception.Message }
    Chk "кэш без домашней строки отклонён" ($threw -like "*нет CMAKE_HOME_DIRECTORY*") $true
    Remove-Item -Recurse -Force $cacheDir -ErrorAction SilentlyContinue
    # Класс дефекта, который 12.11 испорчил measure-файл убитого прогона: в Windows PowerShell 5.1
    # строка `Write-Host "a" +` не продолжается на следующую строку - та становится отдельным
    # выражением и уходит в поток вывода функции. Set-EngineMeasure возвращала Object[] из двух
    # элементов, и build-measure.json был списком ["коммита-носителя, ...", {...}]: его не читают
    # ни classify.py, ни Get-PrevBuild, ни упаковщик. Меряем форму возврата на настоящем
    # провале (дерева нет - git не называет HEAD), а не на подставной строке.
    $emptyLog = Join2 ([System.IO.Path]::GetTempPath()) "build-kit-selftest-empty.log"
    [System.IO.File]::WriteAllText($emptyLog, "", (New-Object System.Text.UTF8Encoding($false)))
    $cfgStub = [pscustomobject]@{ sec = 0.1; rc = 0 }
    $bldStub = [pscustomobject]@{ sec = 0.2; rc = 0; log_start = 0; log_bytes = 0 }
    $mLeak = Set-EngineMeasure "strata" "C:/build-kit-selftest-нет-такого-дерева" "C:/нет" `
                              $cfgStub $bldStub $emptyLog ([System.IO.Path]::GetTempPath())
    Chk "мера без git возвращает словарь, не массив" ($mLeak -is [System.Collections.IDictionary]) $true
    Chk "мера без git называет коммит ПУСТО" $mLeak["commit"] "ПУСТО"
    Chk "JSON меры без git начинается с { а не с [" `
        (((ConvertTo-Json -InputObject $mLeak -Depth 6).TrimStart())[0]) "{"
    Remove-Item $emptyLog -ErrorAction SilentlyContinue
    # И тот же класс по тексту скрипта: голая склейка Write-Host обязана быть запрещена, иначе
    # правка вернёт утечку в том месте, которое сейчас не исполняется.
    $bareGlue = @([regex]::Matches(([System.IO.File]::ReadAllText($PSCommandPath)),
                  '(?m)^[ \t]*Write-Host[ \t]+"[^"]*"[ \t]*\+[ \t]*$')).Count
    Chk "в скрипте нет голых Write-Host-склеек" $bareGlue 0

    # --- CI-пригодность --------------------------------------------------------------------
    # Класс дефекта, который правки возвращают тише всего: в рабочую копию возвращается стендовый
    # путь или корень, выведенный из положения скрипта. Тогда сборка работает на стенде, а в Actions
    # падает другой ошибкой, и по логу не понять, что виной путь.
    # Меряется двумя способами. Литералы - по коду, причём комментарии и docstring вырезаны: иначе
    # контроль находит собственные пояснения и собственный же список. Отказы по входам - поведением:
    # скрипт запускает сам себя с недостающим параметром и обязан отказать до любой дорогой работы.
    $raw = [System.IO.File]::ReadAllText($PSCommandPath)
    $dollar = [char]36
    $noDoc = [regex]::Replace($raw, '(?s)<\#.*?\#>', '')
    $code = @(($noDoc -split "`r?`n") | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
    # Каждый литерал собран из двух кусков: целым он остался бы в этом же файле, и мерка встречала
    # бы самое себя вместо кода сборки (проверено на красном прогоне: 7 «находок» из 7 - свои же).
    $standLits = @('F:\' + 'CUDA', 'C:\' + 'Projects', 'E:\' + 'tmp', 'harness\' + 'scripts',
                   'llama' + '-kit', 'dist\' + 'gpu-infer-kit', 'C:\Program Files\' + 'NVIDIA')
    $hits = @($standLits | Where-Object { $code.Contains($_) })
    Chk "в коде нет стендовых литералов путей" ($hits -join ', ') ""
    Chk "в коде нет обращений к выведенному корню" `
        ([regex]::Matches($code, '\' + $dollar + 'root\b').Count) 0
    # Та же схема паттерна обязана находить то, что в коде точно есть: без этого контроля «0
    # находок» неотличимо от паттерна, который не находит ничего (с `$` в regex как анкором).
    Chk "мера находит заведомо присутствующий маркер" `
        ([regex]::Matches($code, '\' + $dollar + 'Out\b').Count -gt 0) $true
    Chk "в коде нет путей, выведенных из положения скрипта" `
        ($code.Contains('PSScript' + 'Root') -or $code.Contains('Split-Path ' + $dollar + 'PSCommandPath')) $false
    foreach ($p in @("Cuda", "Vs", "Out", "StrataSrc", "LlamaSrc", "GgmlDir",
                     "ProbeScript", "StrataBuildDir", "LlamaBuildDir")) {
        $m = [regex]::Match($code,
              '(?m)^\s*\[string\]' + [regex]::Escape($dollar + $p) + '\s*=\s*"([^"]*)"')
        # Первый контроль - саботаж второго: прежняя редакция совпадала с «пустой строкой» и давала
        # зелёный на параметре, которого в блоке нет вовсе.
        Chk "параметр -$p объявлен (мера не пустая)" $m.Success $true
        Chk "параметр -$p без дефолтного пути" $m.Groups[1].Value ""
    }

    # Набор -D-ключей нельзя «улучшить по ходу» молча: доказательство переносимо только если флаги
    # совпадают со стендовыми. Функция бросает, если массив не найден или в нём нет ни одного -D:
    # пустой список иначе канонизировал бы зелёный контроль на пустом входе.
    function Get-DFlagNames([string]$varName) {
        $lines = $code -split "`r?`n"
        $pat = '^\s*' + [regex]::Escape($dollar + $varName + ' = @(')
        $start = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match $pat) { $start = $i; break }
        }
        if ($start -lt 0) { throw "массив $dollar$varName не найден - проверка не состоялась" }
        $got = @()
        for ($i = $start; $i -lt $lines.Count; $i++) {
            $got += @([regex]::Matches($lines[$i], '-D([A-Za-z_][A-Za-z_0-9]*)=') |
                      ForEach-Object { $_.Groups[1].Value })
            # Массив закрывается строкой, кончающейся на ')' - по ней и останавливаемся.
            if ($i -gt $start -and $lines[$i].TrimEnd().EndsWith(")")) { break }
        }
        if (-not $got) { throw "в $dollar$varName нет ни одного -D-флага - проверка не состоялась" }
        return @($got | Sort-Object -Unique)
    }
    $wantStrata = @("CMAKE_BUILD_TYPE", "CMAKE_CUDA_ARCHITECTURES", "CMAKE_CUDA_COMPILER",
                    "CMAKE_EXPORT_COMPILE_COMMANDS", "STRATA_BUILD_TESTS", "STRATA_ENABLE_CUDA",
                    "STRATA_PORTABLE") | Sort-Object
    $wantLlama = @("CMAKE_BUILD_TYPE", "CMAKE_CUDA_ARCHITECTURES", "CMAKE_CUDA_COMPILER",
                   "CMAKE_EXPORT_COMPILE_COMMANDS", "GGML_CUDA", "LLAMA_BUILD_EXAMPLES",
                   "LLAMA_BUILD_SERVER", "LLAMA_BUILD_TESTS", "LLAMA_CURL") | Sort-Object
    foreach ($t in @(@{ v = "cfgArgs"; n = "Страты"; want = $wantStrata },
                     @{ v = "llamaArgs"; n = "llama"; want = $wantLlama })) {
        $got = @(); $err = ""
        try { $got = @(Get-DFlagNames $t.v) } catch { $err = $_.Exception.Message }
        Chk "массив -D $($t.n) вычитан из кода" $err ""
        Chk "набор -D $($t.n) ровно стендовый" ($got -join ',') ($t.want -join ',')
    }
    Chk "STRATA_GGML_DIR добавляется условно, а не всегда" `
        ($code.Contains($dollar + 'cfgArgs += "-DSTRATA_GGML_DIR=' + $dollar + 'GgmlDir"')) $true
    Chk "портативность включена по умолчанию" ($code.Contains('-DSTRATA_PORTABLE=' + $dollar + 'portable')) $true
    Chk "curl в llama выключён" ($code.Contains('-DLLAMA_CURL=OFF')) $true
    Chk "цель Страты - обе программы" ($code.Contains('--target strata strata-q36')) $true
    Chk "цель llama - llama-server" ($code.Contains('--target llama-server')) $true
    Chk "bin тулчейна попадает в PATH безусловно" `
        ($code.Contains($dollar + 'env:PATH = (Join2 ' + $dollar + 'Cuda "bin") + ";"')) $true

    # Отказы по входам меряются прогоном, а не грепом: важно, чтобы отказ был и текстом, и кодом, и
    # случился до первой дорогой работы. Дешевизну доказывает позиция: валидация стоит до New-Item.
    # Иглы собраны из кусков: целиком 'ОТКАЗ: -Cuda не передан' стоит в этой же строке мерки, и
    # IndexOf нашёл бы саму себя раньше основного потока - порядок оказался бы верным всегда.
    $iEntry = $code.IndexOf('ОТКАЗ: ' + '-Cuda не передан')
    $iMkdir = $code.IndexOf('New-Item -ItemType Directory -Force -Path ' + $dollar + 'Out')
    Chk "отказ по входу идёт до создания каталога вывода" `
        ($iEntry -ge 0 -and $iMkdir -ge 0 -and $iEntry -lt $iMkdir) $true
    Chk "отказ по входу -Cuda в коде ровно один" `
        ([regex]::Matches($code, [regex]::Escape('ОТКАЗ: ' + '-Cuda не передан')).Count) 1

    function Invoke-EntryProbe([string[]]$Entry) {
        $exe = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
        if (-not $exe) { return [pscustomobject]@{ rc = -1; out = "нет pwsh - прогон не состоялся" } }
        $out = & $exe -NoProfile -NonInteractive -File $PSCommandPath @Entry 2>&1 | Out-String
        $rc = $LASTEXITCODE
        return [pscustomobject]@{ rc = $rc; out = $out }
    }
    $noDir = "C:\_build-kit-selftest-no-such-dir"
    foreach ($t in @(
        @{ n = "без -Cuda"; o = "-Cuda";
           a = @("-StrataSrc", $noDir, "-Out", $noDir) },
        @{ n = "без -StrataSrc"; o = "-StrataSrc";
           a = @("-Out", $noDir) },
        @{ n = "без -Out"; o = "-Out";
           a = @("-StrataSrc", $noDir) },
        @{ n = "llama без -LlamaSrc"; o = "-LlamaSrc";
           a = @("-StrataSrc", $noDir, "-Out", $noDir, "-Cuda", $noDir, "-Engines", "strata;llama") }
    )) {
        $pr = Invoke-EntryProbe $t.a
        Chk "отказ по входу ($($t.n)) даёт rc=2" $pr.rc 2
        Chk "отказ по входу ($($t.n)) называет $($t.o)" ($pr.out.Contains($t.o)) $true
    }

    Write-Host "build_kit: $script:ok/$($script:ok + $script:bad) контролей пройдено"
    # нижняя граница числа контролей: выкинутый контроль обязан быть замечен, а не «менее 46».
    # Фактическое число на 12.11 - 87 (стенд); 80 оставлены с запасом на правку, а не на молчание.
    if (($script:ok + $script:bad) -lt 80) {
        Write-Host "ОТКАЗ: контролей меньше 80 - мерка деградировала (проверка не состоялась)"
        exit 2
    }
    exit $(if ($script:bad) { 1 } else { 0 })
}

# --- входы: только параметрами, никаких путей, выведенных из положения скрипта ---
# В harness-версии корень стенда находился прогоном вверх по engine\CMakeLists.txt, и это работало
# ровно на C:\Projects\Strata-3060Ti. В Actions рабочее дерево раннера лежит в D:\a\<repo>\<repo>,
# второй клон - соседним каталогом, а CUDA собрана install_cuda_redist.ps1: подстановка «на два
# уровня выше» там не находит ничего и скрипт отказывал бы по несуществующему пути.
if (-not $StrataSrc) {
    Write-Host ("ОТКАЗ: -StrataSrc не передан (ждём каталог исходников Страты - в Actions это" +
                " рабочее дерево раннера)")
    exit 2
}
if (-not $Out) { Write-Host "ОТКАЗ: -Out не передан (каталог мер и комплекта) - проверка не состоялась"; exit 2 }
if (-not $Cuda) { Write-Host "ОТКАЗ: -Cuda не передан: без тулчейна CUDA компилировать нечем"; exit 2 }
if (($Engines -match 'llama') -and -not $LlamaSrc) {
    Write-Host ("ОТКАЗ: -Engines '${Engines}' заказывает llama, но -LlamaSrc не передан -" +
                " второй клон в Actions обязан быть указан явно")
    exit 2
}
if (-not $GgmlDir) { $GgmlDir = "" }

# build-measure.json и elf-proof.json читаются классификатором комплекта и упаковщиком как меры
# ВСЕГО комплекта. Прогон -Engines llama перезаписывал их своими двумя строками, и доказательство
# Страты исчезало молча (проверено 10.11: в elf-proof.json остались только llama-бинарники, а
# pack_kit.ps1 не увидел потери). Частичный прогон поэтому пишет в *.partial.json - объединённый
# файл можно получить только прогоном, покрывающим оба движка.
$partial = -not (($Engines -match 'strata') -and ($Engines -match 'llama'))
$sfx = if ($partial) { ".partial" } else { "" }
if ($partial) {
    Write-Host "ВНИМАНИЕ: -Engines '$Engines' покрывает один движок: меры пишутся в *.partial.json,"
    Write-Host "          объединённые build-measure.json / elf-proof.json не трогаются."
}
try {
    New-Item -ItemType Directory -Force -Path $Out | Out-Null
} catch {
    Write-Host "ОТКАЗ: не удаётся создать каталог вывода ${Out}: $($_.Exception.Message)"; exit 2
}
$outFile = Join2 $Out ("build-measure{0}.json" -f $sfx)

$nvcc = Join2 $Cuda "bin\nvcc.exe"
if (-not (Test-Path $nvcc)) { Write-Host "ОТКАЗ: не найден ${nvcc}: параметр -Cuda должен указывать на набор CUDA"; exit 2 }

# cuobjdump нужен, чтобы доказать архитектуры фактом, а не обещанием. В harness-версии он искался
# ещё и по типовым каталогам установки стенда (в их числе литерал F:\CUDA), и именно эти строки
# делали скрипт непригодным вне стенда: на раннере таких каталогов нет, а сам поиск не мешает
# отказу. Здесь источников два: набор CUDA из -Cuda (redist-тулчейн кладёт cuobjdump.exe в bin\)
# и PATH. Отсутствие - отказ, а не пустой список cubin: прогон с пустым cubin выглядит как
# «доказательство получилось».
$cuobj = ""
$cuCandidates = @((Join2 $Cuda "bin\cuobjdump.exe"))
$fromPath = Get-Command cuobjdump -ErrorAction SilentlyContinue
if ($fromPath) { $cuCandidates += $fromPath.Source }
foreach ($c in $cuCandidates) {
    if ($c -and (Test-Path $c)) { $cuobj = $c; break }
}
if (-not $cuobj -and -not $SkipElfCheck) {
    Write-Host ("ОТКАЗ: не найден cuobjdump.exe (искали здесь: " + ($cuCandidates -join '; ') + "); " +
                "без него архитектуры не доказаны - -SkipElfCheck уместен только как осознанный пропуск проверки")
    exit 2
}

$archList = @($Arch -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if (-not $archList) { Write-Host "ОТКАЗ: пустой список архитектур - проверка не состоялась"; exit 2 }
foreach ($a in $archList) { if ($a -notmatch '^\d\d\d?[af]?$') { Write-Host "ОТКАЗ: архитектура '$a' не похожа на номер (86, 89, 120, 120a, 90f)"; exit 2 } }

# vcvars64 не наследуется в PowerShell: вытаскиваем из него переменные среды прогоном cmd /c set.
# Каталог Visual Studio либо передан -Vs, либо спросить у vswhere: в Actions не нужно знать, какая
# редакция стоит на раннере (Enterprise/Professional/2022->2026 меняются вместе с образом), а
# hardcoded-путь редакции сделал бы скрипт стендовым.
if (-not $Vs) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) {
        Write-Host ("ОТКАЗ: -Vs не передан, а vswhere.exe нет на месте ($vswhere) -" +
                    " где MSVC, неизвестно; проверка не состоялась")
        exit 2
    }
    $Vs = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
            -property installationPath) | Select-Object -First 1
    if (-not $Vs) { Write-Host "ОТКАЗ: vswhere не нашёл установку VS с VC++-инструментами"; exit 2 }
    Write-Host "Visual Studio найдена через vswhere: $Vs"
}
$vcvars = Join2 $Vs "VC\Auxiliary\Build\vcvars64.bat"
if (-not (Test-Path $vcvars)) { Write-Host "ОТКАЗ: не найден $vcvars (-Vs)"; exit 2 }
cmd /c "`"$vcvars`" >nul 2>&1 && set" | ForEach-Object {
    if ($_ -match '^(.*?)=(.*)$') { Set-Item -Path ("env:" + $matches[1]) -Value $matches[2] }
}

# CMake, Ninja и Python в Actions даёт образ раннера и они лежат в PATH; на стенде они живут в
# engine\.venv\Scripts, поэтому каталог ищется рядом с -StrataSrc и добавляется, только если есть.
# В harness-версии путь .venv выводился из корня стенда - здесь он выведен из переданного исходника.
$venvBin = Join2 $StrataSrc ".venv\Scripts"
if (Test-Path $venvBin) { $env:PATH = "$venvBin;" + $env:PATH }
# Каталог bin тулчейна обязан попасть в PATH безусловно: nvcc зовёт cicc/ptxas по имени, и без
# этого CMake падает на enable_language(CUDA) сформулировкой про компилятор, а не про PATH.
$env:PATH = (Join2 $Cuda "bin") + ";" + $env:PATH
$cmake = if (Test-Path (Join2 $venvBin "cmake.exe")) { Join2 $venvBin "cmake.exe" } else { "cmake" }
$python = if (Test-Path (Join2 $venvBin "python.exe")) { Join2 $venvBin "python.exe" } else { "python" }
# Ninja и nvcc живут в .venv\Scripts и в CUDA\bin: без них CMake отвечает своей же ошибкой
# («unable to find a build program corresponding to "Ninja"»), и она приходит как NativeCommandError
# вместо внятного отказа. Каталог подложки в PATH - и причина становится нашей формулировкой.
if (-not (Get-Command ninja -ErrorAction SilentlyContinue)) {
    Write-Host "ОТКАЗ: ninja не найден (искали в $venvBin и в PATH): без него генератор Ninja не работает"
    exit 2
}
if (-not (Get-Command $cmake -ErrorAction SilentlyContinue) -and -not (Test-Path $cmake)) {
    Write-Host "ОТКАЗ: не найден cmake ($cmake) и его нет в PATH"
    exit 2
}

# CMake и cuobjdump пишут policy-warning в stderr; в Windows PowerShell 5.1 это
# NativeCommandError и падение при Stop. Успех нативной команды меряем только кодом возврата.
$ErrorActionPreference = "Continue"

$measure = [ordered]@{
    archs            = $archList
    cuda             = $Cuda
    portable         = (-not $NoPortable)
    ggml_dir         = $GgmlDir
    started          = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    engines          = @{}
    arch_probe       = @{}
    binaries         = @()
}
$rc_total = 0

function Save-Measure([string]$Note) {
    # Отказ посреди сборки обязан оставить след в мерах: иначе рядом с новой сборкой лежит
    # build-measure.json прошлого прогона, и пустые числа читаются как «собрали быстро».
    $measure.finished = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $measure.result = $Note
    Write-Json $measure $outFile 8
    Write-Host "меры (неполные): $outFile"
}

if ($Engines -match 'strata') {
    # Источник - параметр: точка истины kit-all живёт отдельным worktree, и подменять ради неё
    # рабочее дерево engine (где идут свои сборки) нельзя.
    $src = $StrataSrc
    if (-not (Test-Path (Join2 $src "CMakeLists.txt"))) { Write-Host "ОТКАЗ: нет исходников Страты в $src"; exit 2 }
    # Каталог сборки - параметр, а не вечный "build-kit": время полной компиляции имеет смысл
    # мерить только на холодном кэше, а в общем build-kit в это же время могла идти чужая сборка
    # (проверено 10.11: nvcc из чужого прогона держал каталог, и переименовать его было нельзя).
    $bd = if ($StrataBuildDir) { $StrataBuildDir } else { Join2 $src "build-kit" }
    Assert-FreshCache $bd $src
    # --- префлайт ggml-дерева, до запуска единого компилятора ---------------------------------
    # main Страты требует от ggml-дерева K-quant инстансы: cmake/backends/cuda.cmake перечисляет
    # q2_k..q6_k в set(_strata_kq_types) и target_sources'-ит их при STRATA_MMQ_KQUANTS (он ON
    # по умолчанию), а в vendored third_party\strata-ggml одного q2_k нет. Без этого шага CMake
    # доходит до "Configuring done" и падает на generate ("Cannot find source file"), что в логе
    # неотличимо от поломки тулчейна, - проверено 10.11 на отказе настройки Страты rc=1.
    $kqCmake = Join2 $src "cmake\backends\cuda.cmake"
    $kqTypes = @(if (Test-Path $kqCmake) { Get-KqTypes $kqCmake } else { @() })
    if (-not $kqTypes) {
        Write-Host "ОТКАЗ: список K-quant инстансов не вычитан из $kqCmake - префлайт ggml-дерева не состоялся"; exit 2
    }
    $cand = @()
    foreach ($base in @($GgmlDir, (Join2 $src "third_party\strata-ggml"))) {
        if (-not $base) { continue }
        $cand += (Join2 $base "ggml\src\ggml-cuda\template-instances")
        $cand += (Join2 $base "src\ggml-cuda\template-instances")
    }
    $ti = @($cand | Where-Object { Test-Path $_ }) | Select-Object -First 1
    if (-not $ti) {
        Write-Host "ОТКАЗ: каталог template-instances не найден ни в -GgmlDir, ни в vendored ggml Страты:";
        foreach ($c in $cand) { Write-Host "         $c" }
        exit 2
    }
    $lack = @(Get-KqMissing $ti $kqTypes)
    Write-Host ("ggml-дерево Страты: $ti (K-quant инстансов запрошено $($kqTypes.Count), недостаёт $($lack.Count))")
    if ($lack) {
        Write-Host "ОТКАЗ: в этом ggml-дереве нет mmq-instance для $($lack -join ', ') - сборка упала бы на generate."
        Write-Host "       выход: -GgmlDir <дерево, где эти инстансы лежат>. Ни один компилятор не запущен, время сборки не испорчено."
        exit 2
    }
    $portable = if ($NoPortable) { "OFF" } else { "ON" }
    $log = Join2 $Out "build-strata.log"
    $cfgArgs = @("-S", $src, "-B", $bd, "-G", "Ninja", "-DCMAKE_BUILD_TYPE=Release",
                 "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON", "-DSTRATA_ENABLE_CUDA=ON",
                 "-DSTRATA_BUILD_TESTS=OFF", "-DSTRATA_PORTABLE=$portable",
                 "-DCMAKE_CUDA_ARCHITECTURES=$($archList -join ';')",
                 "-DCMAKE_CUDA_COMPILER=$nvcc")
    if ($GgmlDir) { $cfgArgs += "-DSTRATA_GGML_DIR=$GgmlDir" }
    $tCfg = Invoke-BuildStep $log "настройка Страты" { & $cmake @cfgArgs }
    if ($tCfg.rc -ne 0) { Write-Host "ОТКАЗ: настройка Страты rc=$($tCfg.rc) (лог $log)"; Save-Measure "отказ: настройка Страты rc=$($tCfg.rc)"; exit 1 }
    $tBuild = Invoke-BuildStep $log "сборка Страты" { & $cmake --build $bd --target strata strata-q36 -j 4 }
    if ($tBuild.rc -ne 0) { Write-Host "СБОРКА Страты упала rc=$($tBuild.rc) (лог $log)"; $rc_total = 1 }
    $measure.engines.strata = Set-EngineMeasure "strata" $src $bd $tCfg $tBuild $log $Out
    $sm = $measure.engines["strata"]
    Write-Host ("strata: настройка {0} с, сборка {1} с ({2} компиляций, {3} линковок), rc={4}" -f `
                $tCfg.sec, $sm.build_s, $sm.build_compiles, $sm.build_links, $tBuild.rc)
}

if ($Engines -match 'llama') {
    $src = $LlamaSrc
    if (-not (Test-Path (Join2 $src "CMakeLists.txt"))) {
        Write-Host "ОТКАЗ: нет дерева llama.cpp в $src (-LlamaSrc); для Страты этот движок не обязателен"
        exit 2
    }
    $bd = if ($LlamaBuildDir) { $LlamaBuildDir } else { Join2 $src "build-kit" }
    Assert-FreshCache $bd $src
    $log = Join2 $Out "build-llama.log"
    # Аргументы - массивом и в двойных кавычках, как в ветке Страты. В командной позиции токен
    # вида -DCMAKE_CUDA_COMPILER=$nvcc начинается с дефиса, поэтому PowerShell трактует его как
    # имя параметра и переменную не раскрывает: CMake получал дословный «$nvcc» и падал на
    # enable_language (проверено 10.11 по build-llama.log). Элемент массива - уже готовая
    # строка, поэтому раскрытие происходит всегда, а пробелы в пути nvcc не ломают аргумент.
    $llamaArgs = @("-S", $src, "-B", $bd, "-G", "Ninja", "-DCMAKE_BUILD_TYPE=Release",
                   "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON", "-DGGML_CUDA=ON",
                   "-DCMAKE_CUDA_ARCHITECTURES=$($archList -join ';')",
                   "-DCMAKE_CUDA_COMPILER=$nvcc",
                   "-DLLAMA_BUILD_SERVER=ON", "-DLLAMA_BUILD_TESTS=OFF",
                   "-DLLAMA_BUILD_EXAMPLES=OFF", "-DLLAMA_CURL=OFF")
    $tCfg = Invoke-BuildStep $log "настройка llama" { & $cmake @llamaArgs }
    if ($tCfg.rc -ne 0) { Write-Host "ОТКАЗ: настройка llama rc=$($tCfg.rc) (лог $log)"; Save-Measure "отказ: настройка llama rc=$($tCfg.rc)"; exit 1 }
    $tBuild = Invoke-BuildStep $log "сборка llama" { & $cmake --build $bd --target llama-server -j 4 }
    if ($tBuild.rc -ne 0) { Write-Host "СБОРКА llama упала rc=$($tBuild.rc) (лог $log)"; $rc_total = 1 }
    $measure.engines.llama = Set-EngineMeasure "llama" $src $bd $tCfg $tBuild $log $Out
    $lm = $measure.engines["llama"]
    Write-Host ("llama: настройка {0} с, сборка {1} с ({2} компиляций, {3} линковок), rc={4}" -f `
                $tCfg.sec, $lm.build_s, $lm.build_compiles, $lm.build_links, $tBuild.rc)
}

if (-not $measure.engines.Count) {
    # Опечатка в -Engines (например "-Engines starta") молча проходила бы весь скрипт: ни один
    # движок не собран, список бинарников пуст, и «доказательство» выглядело бы как прогон.
    Write-Host ("ОТКАЗ: -Engines '$Engines' не зацепил ни один движок (ждём strata и/или llama) -" +
                " проверка не состоялась")
    exit 2
}

# --- предельная цена каждой архитектуры: прогонник по настоящим флагам сборки ---
if ($SkipProbe) {
    Write-Host "пробник architectures: пропущен явно (-SkipProbe) - предельная цена архитектур не мерялась"
} elseif (-not $ProbeScript) {
    # В CI скрипт пробника живёт в отдельной репе harness и в прогоне комплекта не нужен: он мерит
    # время, а не правильность. Пропуск обязан быть напечатан, иначе пустой arch_probe в мере
    # выглядел бы как «мерили и всё быстро».
    Write-Host "пробник architectures: пропущен явно (-ProbeScript не передан)"
} else {
    if (-not (Test-Path $ProbeScript)) {
        Write-Host "ОТКАЗ: -ProbeScript указан, но файла нет ($ProbeScript) - проверка не состоялась"
        exit 2
    }
    foreach ($e in @("strata", "llama")) {
        if (-not $measure.engines.Contains($e)) { continue }
        $bd = $measure.engines[$e].build_dir
        & $python $ProbeScript --build $bd `
            --archs ($archList -join ';') --out (Join2 $Out "arch-probe-$e.json") --top 3
        if ($LASTEXITCODE -eq 0) {
            $measure.arch_probe[$e] = (Get-Content (Join2 $Out "arch-probe-$e.json") -Raw | ConvertFrom-Json)
        } elseif ($LASTEXITCODE -eq 2) {
            Write-Host "пробник ${e}: проверка не состоялась (нет compile_commands.json или тяжёлого файла)"
            $rc_total = 1
        } else {
            Write-Host "пробник ${e}: rc=$LASTEXITCODE"; $rc_total = 1
        }
    }
}

# Бинарники меряются группами: ggml-cuda.dll лежит то в bin\, то в ggml\src\ - это один артефакт,
# а не два. Прощать отсутствие пути целиком нельзя: при упавшей сборке список остался бы пустым
# без единого сигнала. Поэтому если в группе нет НИ ОДНОГО файла - это провал меры.
$elfProofFile = Join2 $Out ("elf-proof{0}.json" -f $sfx)
$elfProof = [ordered]@{
    cuobjdump  = $cuobj
    want_archs = @($archList | ForEach-Object { "sm_$_" })
    binaries   = @()
}
$groups = @()
if ($measure.engines.Contains("strata")) {
    $bd = $measure.engines.strata.build_dir
    $groups += [pscustomobject]@{ name = "strata-q36"; carries = $true; paths = @((Join2 $bd "strata-q36.exe")) },
               [pscustomobject]@{ name = "strata"; carries = $true; paths = @((Join2 $bd "strata.exe")) }
}
if ($measure.engines.Contains("llama")) {
    $bd = $measure.engines.llama.build_dir
    # llama-server.exe - обёртка: линкуется без CUDA-кода, и cubin в ней появиться не может.
    $groups += [pscustomobject]@{ name = "llama-server"; carries = $false; paths = @((Join2 $bd "bin\llama-server.exe")) },
               [pscustomobject]@{ name = "ggml-cuda"; carries = $true; paths = @((Join2 $bd "bin\ggml-cuda.dll"),
                                                                                 (Join2 $bd "ggml\src\ggml-cuda.dll")) }
}
foreach ($g in $groups) {
    $b = @($g.paths | Where-Object { Test-Path $_ })
    if (-not $b) {
        Write-Host "  ВНИМАНИЕ: $($g.name): ни одного файла из $(($g.paths -join '; ')) - архитектура не доказана"
        $rc_total = 1
        continue
    }
    $b = $b[0]
    $sz = (Get-Item $b).Length
    $item = [ordered]@{
        name          = $g.name
        path          = $b
        bytes         = $sz
        carries_cuda  = [bool]$g.carries
        cubin         = @()
        cubin_files   = @{}
        ptx           = @()
        ptx_files     = @{}
    }
    if (-not $SkipElfCheck) {
        $e = Get-FatbinList $b "--list-elf"
        $p = Get-FatbinList $b "--list-ptx"
        $item.cubin = @($e.counts.Keys | Where-Object { $_ -like "sm_*" } | Sort-Object)
        $item.cubin_files = $e.counts
        $item.ptx = @($p.counts.Keys | Sort-Object)
        $item.ptx_files = $p.counts
        Write-Host ("{0}: {1} байт, cubin [{2}] по {3} строкам, PTX [{4}] по {5} строкам" -f `
                    $g.name, $sz, ($item.cubin -join ' '), (@($e.counts.Values | Measure-Object -Sum).Sum),
                    ($item.ptx -join ' '), (@($p.counts.Values | Measure-Object -Sum).Sum))
        foreach ($v in @(Get-CubinVerdict $item.cubin $archList ([bool]$g.carries))) {
            Write-Host "  ВНИМАНИЕ: $($g.name): $v (cuobjdump --list-elf rc=$($e.rc))"
            $rc_total = 1
        }
        if ($g.carries) {
            # чем доказана каждая запрошенная архитектура: если тег с суффиксом, это видно
            # в строке - иначе читатель принимает sm_120a за отсутствие 120 или, наоборот,
            # за обещание, которое никто не проверял на чужом железе.
            $pm = Get-ArchProofMap $item.cubin $archList
            $sfx = @($pm.Keys | Where-Object { $pm[$_] -and $pm[$_] -ne $_ })
            Write-Host ("  {0}: доказано {1}" -f $g.name, (($pm.Keys | ForEach-Object {
                if ($pm[$_]) { "$_<=$($pm[$_])" } else { "$_=нет" } }) -join ' '))
            if ($sfx) {
                Write-Host ("  {0}: для $(($sfx -join ',')) cubin только в форме с суффиксом -" +
                            " код той же вычислительной способности, но на 120-железе не запускался" -f $g.name)
            }
        }
        if (-not $g.carries) {
            Write-Host "  $($g.name): обёртка без CUDA-кода - отсутствие cubin здесь нормально, несёт его ggml-cuda.dll"
        }
        # elf-proof.json - то же доказательство, но в формате, который читает kit\classify.py:
        # без сайдкара вердикт «cubin для твоей архитектуры в комплекте нет» опирался бы на
        # константу в исходнике, пережившую пересборку под другой список архитектур.
        $elfProof.binaries += [ordered]@{
            label = $g.name; path = $b; bytes = $sz; carries_cuda = [bool]$g.carries
            rc_list_elf = $e.rc; rc_list_ptx = $p.rc
            cubin_archs = @($e.counts.Keys | Where-Object { $_ -like "sm_*" } | Sort-Object)
            proven_by   = (Get-ArchProofMap @($e.counts.Keys | Where-Object { $_ -like "sm_*" } | Sort-Object) $archList)
            cubin_per_arch = $e.counts
            elf_entries = (@($e.counts.Values | Measure-Object -Sum).Sum)
            ptx_archs = @($p.counts.Keys | Sort-Object)
            ptx_entries = (@($p.counts.Values | Measure-Object -Sum).Sum)
        }
    }
    $measure.binaries += $item
}
if ($SkipElfCheck -and (Test-Path $elfProofFile)) {
    # Доказательство не снималось, а старый сайдкар рядом с новой сборкой classify прочитал бы
    # как актуальный. Убираем его из поля зрения и считаем это провалом меры, а не нормой.
    $stale = $elfProofFile -replace '\.json$', ("stale-{0:yyyyMMdd-HHmmss}.json" -f (Get-Date))
    Move-Item -Path $elfProofFile -Destination $stale -Force
    Write-Host ("  ВНИМАНИЕ: -SkipElfCheck: прежнее доказательство убрано в $(Split-Path $stale -Leaf) -" +
                " читать его как актуальное нельзя"); $rc_total = 1
} elseif (-not $SkipElfCheck) {
    Write-Json $elfProof $elfProofFile 6
    Write-Host "доказательство архитектур: $elfProofFile ($(@($elfProof.binaries).Count) бинарников)"
}
if ($rc_total -eq 0) { $measure.result = "собрано и доказано" } else { $measure.result = "есть провалы, см логи" }
Write-Json $measure $outFile 8
Write-Host "меры: $outFile"
exit $rc_total
