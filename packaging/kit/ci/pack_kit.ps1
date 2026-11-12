<#
    Часть 4.4/4.6: сборка дерева портативного комплекта по манифесту и упаковка в zip - с гейтами.

    Это ЛОКАЛЬНЫЙ скрипт стенда (pwsh 7). В комплект входит только обвязка на PowerShell 5.1.

        pwsh -File packaging/kit/ci/pack_kit.ps1 -StrataBuild <dir> -LlamaBuild <dir> -Measures <dir> -Stage <dir> -Zip <file>
        pwsh -File packaging/kit/ci/pack_kit.ps1 ... -NoCudaRuntime     # тонкая версия без cublas
        pwsh -File packaging/kit/ci/pack_kit.ps1 -SelfTest              # контроли без сборки и железа

    Почему по манифесту, а не «скопировать папку»: в dist\gpu-infer-kit лежат build-логи на
    мегабайты, рядом с ними - run\ и __pycache__, созданные самим комплектом при прогонах. Копия
    «что видит глаз» принесла бы этот мусор на чужую машину, и никто бы не заметил: архив
    открывался бы нормально.

    Гейты до того, как архив считается готовым:
      1. каждый обязательный файл манифеста существует - иначе комплект доезжает до чужой машины
         с «модуль не найден» вместо предупреждения;
      2. переносимость: в текстовых файлах дерева нет абсолютных путей с литерой диска ни в
         одной форме записи (`C:\x`, `C:/x`, смешанный `C:\x/y`) - ни стенда, ни раннера;
      3. сайдкары читаются: elf-proof.json, runtime-deps.json, build-measure.json - валидный JSON
         БЕЗ BOM (классификатор комплекта читает их json.loads, BOM ломает чтение);
      4. доказательство архитектур покрывает заявленные архитектуры, а замыкание зависимостей
         закрыто (missing пусто);
      5. zip открывается, число записей совпадает с деревом, внутри нет моделей (*.gguf);
      6. вес папки и zip - замер, а не оценка; он же уходит в kit-weight.json.

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
    [switch]$NoCudaRuntime,
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
# Пути, которые делают «портативный» непригодным на чужой машине: ЛЮБАЯ литера диска и ЛЮБОЙ
# разделитель. Прежняя сигнатура ловила только обратные слеши трёх литер (D, F, E) и C:\Users,
# поэтому молчала на реальных мерах: в elf-proof.json и build-measure.json значения записаны в
# форме «литера, косая черта, дерево, затем \\ перед именем файла» - первая половина не совпадала
# вовсе. Та же причина дырявит Actions: у раннера рабочий каталог начинается на C:\, а сочетание
# литеры C с обратным слэшем в старом наборе не было.
# Lookbehind обязан быть: без него `https://` даёт совпадение на `s://`, и очистка изуродовала бы
# ссылки в models.json (мерка кандидата на живом дереве: 14 находок, ноль ложных).
$STAND_PATH_RE = '(?i)(?<![a-z])[a-z]:[\\/]'

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

function Test-NoStandPaths([string]$Dir) {
    # Читаем только текстовые файлы: в бинарниках путь сборки живёт в отладочной секции и на запуск
    # не влияет, а «найти подстроку в 300 МиБ» не является меркой переносимости.
    $hits = @()
    foreach ($f in (Get-KitFiles -Dir $Dir) | Where-Object {
                   $_.Extension -in @('.py', '.ps1', '.bat', '.json', '.md', '.txt', '.cmd') }) {
        $t = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
        if (-not $t) { continue }
        if ($t -match $STAND_PATH_RE) {
            $line = @($t -split "`r?`n" | Where-Object { $_ -match $STAND_PATH_RE })[0]
            $rel = $f.FullName.Substring($Dir.Length).TrimStart('\', '/')
            $hits += ("{0}: {1}" -f $rel, $line.Trim())
        }
    }
    return $hits
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
                      [string]$Measures, [string]$Cuda, [bool]$WithCudaRuntime) {
    $m = [ordered]@{}
    $m["bin\strata.exe"] = Join2 $StrataBuild "strata.exe"
    $m["bin\strata-q36.exe"] = Join2 $StrataBuild "strata-q36.exe"
    # llama-server.exe - тонкая обёртка (10 КиБ): вся логика в llama-server-impl.dll, и без неё
    # exe на чужой машине падает с «модуль не найден», а не с внятной причиной.
    $m["bin\llama-server.exe"] = Join2 $LlamaBuild "bin\llama-server.exe"
    $m["bin\llama-server-impl.dll"] = Join2 $LlamaBuild "bin\llama-server-impl.dll"
    foreach ($d in @("ggml.dll", "ggml-base.dll", "ggml-cpu.dll", "ggml-cuda.dll",
                     "llama.dll", "llama-common.dll", "mtmd.dll")) {
        $m["bin\$d"] = Join2 $LlamaBuild ("bin\" + $d)
    }
    if ($WithCudaRuntime) {
        # Замыкание снято соседней меркой kit_dll_deps.py: cublas64 сам зовёт
        # cublasLt - вдвоём это 488 МиБ, и «тонкий» вариант обязан быть виден отдельным флагом.
        foreach ($d in @("cublas64_13.dll", "cublasLt64_13.dll")) { $m["bin\$d"] = Join2 $Cuda $d }
    }
    foreach ($f in @("detect.py", "classify.py", "gguf_meta.py", "recommend.py", "models.json",
                     "start.ps1")) { $m["kit\$f"] = Join2 $KitSrc $f }
    $m["START.bat"] = Join2 $KitSrc "START.bat"
    foreach ($f in @("elf-proof.json", "runtime-deps.json", "build-measure.json")) {
        $m[$f] = Join2 $Measures $f
    }
    foreach ($f in @("README.ru.md", "README.en.md")) { $m[$f] = Join2 $KitSrc $f }
    return $m
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

if ($SelfTest) {
    $ErrorActionPreference = "Continue"
    $script:ok = 0; $script:bad = 0
    function Chk([string]$Name, $Got, $Want) {
        if ([string]$Got -eq [string]$Want) { $script:ok++; Write-Host "  ok   $Name" }
        else { $script:bad++; Write-Host "FAIL   ${Name}: получено '$Got', ожидалось '$Want'" }
    }
    Write-Host "pack_kit.ps1 selftest"
    Chk "Join2 без слэша" (Join2 "C:\a" "b") "C:\a\b"
    Chk "Join2 с пустой базой" (Join2 "" "b\c") "b\c"

    $tmp = Join2 ([System.IO.Path]::GetTempPath()) ("pack-kit-selftest-" +
               [Guid]::NewGuid().ToString("N").Substring(0, 8))
    New-Item -ItemType Directory -Force -Path (Join2 $tmp "kit\__pycache__") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join2 $tmp "kit\run") | Out-Null
    Set-Content -LiteralPath (Join2 $tmp "detect.py") -Value "print(1)" -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join2 $tmp "kit\__pycache__\detect.cpython-314.pyc") -Value "x" -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join2 $tmp "kit\run\config.json") -Value "{}" -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join2 $tmp "old.log") -Value "x" -Encoding utf8NoBOM
    Set-Content -LiteralPath (Join2 $tmp "models.json") -Value '{"p": "x"}' -Encoding utf8NoBOM
    $keep = Get-KitFiles -Dir $tmp
    Chk "мусор отсеян списком" $keep.Count 2
    Chk "pycache не просочился" (@($keep | Where-Object { $_.FullName -match '__pycache__' }).Count) 0
    Chk "run не просочился" (@($keep | Where-Object { $_.FullName -match '\\run\\' }).Count) 0
    Chk "*.log не просочился" (@($keep | Where-Object { $_.Extension -eq '.log' }).Count) 0

    Set-Content -LiteralPath (Join2 $tmp "models.json") -Value '{"p": "D:\models\x.gguf"}' -Encoding utf8NoBOM
    $hits = Test-NoStandPaths -Dir $tmp
    Chk "путь стенда найден" $hits.Count 1
    Chk "найден именно models.json" (@($hits | Where-Object { $_ -like 'models.json*' }).Count) 1
    # Регрессия на прежнюю сигнатуру: реальные меры пишут путь как «литера, косая черта, дерево,
    # \\ перед именем», и прежний шаблон с обратными слэшами на такой форме молчал - гейт был
    # зелёным при четырнадцати путях машины в текстовых файлах комплекта.
    Set-Content -LiteralPath (Join2 $tmp "models.json") -Value '{"p": "C:/build/x\\strata.exe"}' -Encoding utf8NoBOM
    Chk "косая черта после литеры тоже находка" (Test-NoStandPaths -Dir $tmp).Count 1
    # Обратная сторона: ссылка на CDN не является путём, и не должна красить зелёную сборку.
    Set-Content -LiteralPath (Join2 $tmp "models.json") `
        -Value '{"hf_url": "https://huggingface.co/x/y/resolve/main/model.gguf"}' -Encoding utf8NoBOM
    Chk "https-ссылка не находка" (Test-NoStandPaths -Dir $tmp).Count 0
    Set-Content -LiteralPath (Join2 $tmp "models.json") -Value '{"p": "models/x.gguf"}' -Encoding utf8NoBOM
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
    # в полной версии, и «тонкий» комплект с ними внутри был бы не тонким.
    $fat = Get-Manifest "Q:\нет\build-kit" "Q:\нет\llama" $tmp $tmp "Q:\нет\cuda" $true
    $thin = Get-Manifest "Q:\нет\build-kit" "Q:\нет\llama" $tmp $tmp "Q:\нет\cuda" $false
    Chk "полный манифест содержит cublas" (@($fat.Keys | Where-Object { $_ -like '*cublas*' }).Count) 2
    Chk "тонкий манифест без cublas" (@($thin.Keys | Where-Object { $_ -like '*cublas*' }).Count) 0

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
                     "CudaBin", "Version")) {
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

    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "selftest: ok=$script:ok bad=$script:bad"
    # нижняя граница ЧИСЛА контролей (а не числа пройденных): упавший контроль уже даёт rc=1,
    # а rc=2 означает «мерку урезали» - две разные причины отказа нельзя путать.
    # Фактическое число на 12.11 - 66 (было 26 до CI-пригодности); 60 оставлены с запасом на
    # правку, а не на молчание.
    if (($script:ok + $script:bad) -lt 60) {
        Write-Host "ОТКАЗ: контролей меньше 60 - мерка деградировала (проверка не состоялась)"
        exit 2
    }
    if ($script:bad -gt 0) { exit 1 }
    exit 0
}

# ---------------- основной поток ----------------

# Входы - только параметрами. В стендовой версии недостающие каталоги подставлялись от $root,
# выведенного из положения скрипта, и на чужом дереве это давало отказ по несуществующему пути,
# а не сообщение о том, какой параметр не передан. Путь, выведенный из расположения файла, один:
# исходники комплекта лежат соседним каталогом к ci\ внутри того же репозитория, и эта связь
# одинакова на стенде, в Actions и у любого, кто клонирует форк.
foreach ($t in @(
        @{ n = "StrataBuild"; v = $StrataBuild; d = "каталог сборки Страты - это -Out у build_kit.ps1" },
        @{ n = "LlamaBuild";  v = $LlamaBuild;  d = "каталог сборки llama.cpp" },
        @{ n = "Measures";    v = $Measures;    d = "каталог мер: build-measure.json, elf-proof.json, runtime-deps.json" },
        @{ n = "Stage";       v = $Stage;       d = "каталог, под которым раскладывается комплект перед zip" })) {
    if (-not $t.v) {
        Write-Host ("ОТКАЗ: -{0} не передан ({1}) - проверка не состоялась" -f $t.n, $t.d)
        exit 2
    }
}
if (-not $KitSrc) { $KitSrc = Split-Path -Parent $PSScriptRoot }
if (-not $CudaBin) {
    # CUDA-тулчейн берётся из мер сборки: угадывать его путь нельзя, а без него тонкая версия
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
    Write-Host "      задайте -CudaBin <путь>\bin или упакуйте тонкую версию: -NoCudaRuntime"
    exit 2
}

$manifest = Get-Manifest $StrataBuild $LlamaBuild $KitSrc $Measures $CudaBin $withRuntime
if (-not $manifest.Count) { Write-Host "ОТКАЗ: манифест пуст - проверка не состоялась"; exit 2 }

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

# Гейт 2: переносимость.
$hits = @(Test-NoStandPaths -Dir $Stage)
if ($hits) {
    Write-Host ("ВНИМАНИЕ: в комплекте остались пути стенда ({0}):" -f $hits.Count)
    foreach ($h in $hits) { Write-Host "      $h" }
    $rcGate = 1
} else {
    Write-Host "переносимость: путей стенда в текстовых файлах нет"
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

# Гейт 6: вес.
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
    gate = if ($rcGate -eq 0) { "зелёные" } else { "есть провалы" }
}
[System.IO.File]::WriteAllText((Join2 $Measures "kit-weight.json"),
    ($weight | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("вес: дерево {0} МиБ, zip {1} МиБ, CUDA-рантайм {2} МиБ, файлов {3}" -f `
            $weight.tree_mib, $weight.zip_mib, (Format-Mib ([long]$deps.cuda_runtime_to_copy_bytes)), $manifest.Count)
Write-Host "архив: $Zip"
Write-Host "меры веса: $(Join2 $Measures 'kit-weight.json')"
if ($rcGate -ne 0) { Write-Host "ИТОГ: гейты упаковки упали - архив считать готовым нельзя"; exit 1 }
Write-Host "ИТОГ: комплект упакован, гейты зелёные"
exit 0
