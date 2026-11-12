<#
.SYNOPSIS
    Сборка CUDA-тулчейна из redist-архивов NVIDIA: без установщика, без путей стенда.
.DESCRIPTION
    В образов раннера GitHub Actions CUDA не входит (есть только MSVC, CMake, Ninja, Python),
    а тихая установка full-дистрибутива тянет несколько гигабайт и требует подтверждения
    лицензии. redist-архивы - официальный способ: каждый компонент весит от долей МиБ,
    скачивается по одному URL и раскладывается по корню тулчейна.

    Правила, снятые меркой по настоящим заголовкам архивов 13.3.1 12.11 (не по догадке):
      * индекс redistrib_<версия>.json держит компоненты ВЕРХНИМИ ключами, поля записи
        windows-x86_64 - md5, relative_path, sha256, size (size - СТРОКА);
      * у каждого архива ровно ОДНА верхняя папка `<компонент>-windows-x86_64-<версия>-archive`,
        внутри неё - каталоги относительно корня тулчейна (bin, include, lib, nvvm,
        visual_studio_integration, LICENSE);
      * DLL лежат в bin/x64/, а комплект и сборщик ищут их в bin/ - отсюда шаг «подъёма»;
      * каталоги разных архивов ПЕРЕКРЫВАЮТСЯ (листинг 9 архивов 12.11: bin у 4 из 9,
        include у 6 из 9, lib у 3 из 9), поэтому раскладка обязана СЛИВАТЬСЯ: перенос каталога
        в уже существующий каталог-приёмник PowerShell кладёт его внутрь, и первый живой прогон
        12.11 дал Root\bin\bin\x64\cublas64_13.dll при совпавших
        sha256 всех девяти архивов - неполный тулчейн, который заметил только Test-Toolchain.
    Стендовый тулчейн F:\CUDA\cuda-13.3 устроен ровно так же (в bin/ лежат cublas64_13.dll,
    cudart64_13.dll, а рядом - каталоги crt/ и x64/), поэтому собранный здесь nvcc ведёт себя
    как стендовый.

    Каждый архив сверяется по sha256 ДВАЖДЫ: с индексом NVIDIA и с закреплённым в этом файле
    значением. Закрепление обязано падать, а не молча принимать подменённый или обновлённый
    бинарник: иначе «наша сборка» собрана чужим компилятором, и ни elf-proof, ни гейт маркеров
    этого не заметят - они меряют выход, а не вход.

    Вызов:
        pwsh -File packaging/kit/ci/install_cuda_redist.ps1 -Root <каталог> [-CudaVersion 13.3.1]
        pwsh -File packaging/kit/ci/install_cuda_redist.ps1 -SelfTest

    Коды возврата: 0 - тулчейн собран и проверен; 1 - сверка байтов или обязательный файл
    не прошли; 2 - вход неверен (нет -Root, пустой список компонентов, недоступен индекс) -
    проверка не состоялась.
#>
[CmdletBinding()]
param(
    [string]$Root = "",
    [string]$CudaVersion = "13.3.1",
    [string[]]$Components = @(),
    [string]$CacheDir = "",
    [int]$Retries = 3,
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$BASE = "https://developer.download.nvidia.com/compute/cuda/redist"

# Закреплённые образы компонентов 13.3.1 (release_date 2026-06-29), сняты 12.11 индексом и
# подтверждены скачиванием: у всех мелких архивов фактический sha256 совпал с индексом.
$PINS = [ordered]@{
    "cuda_crt"                  = @{ sha = "9227ec7c80db10b7cb0d4ee71ed62ec7ae36e67890216413ab6f9afa35d577f0"; min = "cuda_crt/13.3.73" }
    "cuda_cudart"               = @{ sha = "1feb7dd266813ffe8dbc24e115183a5ac35a4795c8d34aca0df85ab616b64d9c"; min = "cuda_cudart/13.3.29" }
    "cuda_nvcc"                 = @{ sha = "270214eaee58e49f8fca52a910a46afbfab227858e70897cba8afae10826280b"; min = "cuda_nvcc/13.3.73" }
    "cuda_nvrtc"                = @{ sha = "8519f678588610bf380ccaac130729aa1a624c407183e7ad9c319c19ecc63d2f"; min = "cuda_nvrtc/13.3.33" }
    "cuda_cuobjdump"            = @{ sha = "02712a1fad9be784aa5b6e930ee22381678f1f1b96e83302bd171489b7dfbb38"; min = "cuda_cuobjdump/13.3.73" }
    "libcublas"                 = @{ sha = "62e9fa30560c8f0a28e0cdcf9d6fc1fed347bcfab8847239b9ae1fdc1d86408a"; min = "libcublas/13.6.0.2" }
    "libnvvm"                   = @{ sha = "ca8f11d5173ac16a166be8fafefbf9676542a097de1fce61b3f17696dffc1f27"; min = "libnvvm/13.3.73" }
    "cccl"                      = @{ sha = "48fab83097a636c4119da28bd3c9c9af9327e34c1efed17a14449cc2956ca6d1"; min = "cccl/13.3.3.4.1" }
    "visual_studio_integration" = @{ sha = "a83b8154fe411c3445ff0eaca5f71eaecae596185ba4129a76f2cc4dd878d47e"; min = "visual_studio_integration/13.3.31" }
    "cuda_profiler_api"         = @{ sha = "b41e9634dee36a7c31e121f636c43ba8b461de03de678bcb918060bd352fa2b8"; min = "cuda_profiler_api/13.3.27" }
    "libnvjitlink"              = @{ sha = "43bc22509507c138c86885191bb2709b5d23506ea6abdc8bc64d9960e2b63363"; min = "libnvjitlink/13.3.33" }
}

# Что нужно именно нашей сборке. Стенд F:\CUDA\cuda-13.3 доказывает достаточность: в его bin/
# нет ни nvrtc, ни nvjitlink - значит компилятору и линковке они не требуются, а 560 МиБ
# лишней загрузки в CI не оправданы. cublas обязателен: его зовёт и strata-q36.exe, и
# ggml-cuda.dll, и он же едет в комплект. cuobjdump обязателен для elf-proof.
$NEED_BUILD = @("cuda_crt", "cuda_nvcc", "libnvvm", "cccl", "cuda_cudart",
                "cuda_profiler_api", "visual_studio_integration")
$NEED_PROOF = @("cuda_cuobjdump")
$NEED_RUNTIME = @("libcublas")

function Get-CudaDefaults {
    return @($NEED_BUILD + $NEED_PROOF + $NEED_RUNTIME)
}

function Write-NoBom([string]$Path, [string]$Text) {
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-Sha256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "нет файла $Path - сверка не состоялась" }
    $h = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    return $h.ToLowerInvariant()
}

function Test-IndexJson([string]$Path, [string]$Version) {
    # Пригодность индекса меряется СТРУКТУРОЙ, а не размером. Прежний байтовый порог
    # ("-lt 50000") отбраковывал живой полный redistrib_13.3.1.json весом 47 914 Б (замер
    # 12.11), то есть шаг "Тулчейн CUDA" прерывался до первого скачивания - и это была не
    # защита, а отказ работать. Теперь три критерия, каждый из которых ловит свой способ
    # испортить проверку: метка релиза (другая версия или подмена), число компонентов
    # (обрезанный ответ) и сам разбор JSON (страница ошибки CDN вместо JSON).
    $bad = @()
    $obj = $null
    try {
        $obj = ConvertFrom-Json (Get-Content -LiteralPath $Path -Raw -Encoding UTF8)
    } catch {
        return @("разбор JSON не удался")
    }
    if ($null -eq $obj) { return @("индекс пуст") }
    $label = [string]$obj.release_label
    if ($label -ne $Version) { $bad += ("метка релиза '{0}', запрошена {1}" -f $label, $Version) }
    $comps = @(@($obj.PSObject.Properties | Where-Object { $_.Value -is [System.Management.Automation.PSCustomObject] }))
    if ($comps.Count -lt 20) { $bad += ("компонентов {0}, ждём не меньше 20" -f $comps.Count) }
    return $bad
}

function Save-Index([string]$Version, [string]$Dest) {
    $url = "$BASE/redistrib_$Version.json"
    try {
        Invoke-WebRequest -Uri $url -OutFile $Dest -UseBasicParsing -TimeoutSec 180
    } catch {
        Write-Host "ОТКАЗ: индекс не загружен ($url): $($_.Exception.Message)"
        return $null
    }
    $bytes = (Get-Item -LiteralPath $Dest).Length
    # Пустой или обрезанный ответ читался бы как «компонентов нет», и прогон выглядел бы
    # отказом по версии, хотя проверка просто не состоялась - поэтому гейт здесь, до разбора.
    $bad = @(Test-IndexJson -Path $Dest -Version $Version)
    if ($bad) {
        Write-Host ("ОТКАЗ: индекс {0} Б неприменим ({1}) - проверка не состоялась" -f `
                    $bytes, ($bad -join '; '))
        return $null
    }
    Write-Host ("индекс пригоден: {0} Б, метка релиза {1}" -f $bytes, $Version)
    return $bytes
}

function Get-Archive([string]$Url, [string]$Dest, [int]$Retries) {
    for ($i = 1; $i -le $Retries; $i++) {
        try {
            Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing -TimeoutSec 1800
            return $true
        } catch {
            Write-Host "  попытка $i/$Retries не удалась: $($_.Exception.Message)"
            Start-Sleep -Seconds (5 * $i)
        }
    }
    return $false
}

function Merge-Into([string]$Src, [string]$Dst) {
    # Рекурсивное СЛИЯНИЕ дерева Src в Dst; возвращает число перенесённых файлов.
    # Именно слияние, а не Move-Item верхним слоем: живой прогон 12.11 (9/9 sha256 совпали,
    # распаковка прошла) дал Root\bin\bin\x64\cublas64_13.dll, Root\bin\bin\cuobjdump.exe и
    # Root\include\include\cuda_runtime.h. Причина в семантике PowerShell: перенос каталога в
    # уже существующий каталог-приёмник кладёт его ВНУТРЬ, а не сливает. Первый архив создаёт
    # bin\, и все последующие с тем же каталогом (bin у 4 из 9: nvcc, cudart, cuobjdump, cublas;
    # include у 6 из 9, lib у 3 из 9 - листинг архивов 12.11) оказывались вторым слоем, поэтому
    # тулчейн собирался неполным при зелёных образах байтов.
    if (-not (Test-Path -LiteralPath $Dst)) {
        New-Item -ItemType Directory -Force -Path $Dst | Out-Null
    }
    $moved = 0
    foreach ($item in Get-ChildItem -LiteralPath $Src -Force) {
        $target = Join-Path $Dst $item.Name
        if ($item.PSIsContainer) {
            $moved += Merge-Into $item.FullName $target
        } else {
            Move-Item -LiteralPath $item.FullName -Destination $target -Force
            $moved++
        }
    }
    return $moved
}

function Expand-RedistArchive([string]$Zip, [string]$Root) {
    # Одна верхняя папка на архив - измеренный факт, а не предположение. Проверяем её наличие,
    # иначе «срез уровня» молча превратился бы в перенос пустого дерева.
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("redist-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    try {
        Expand-Archive -LiteralPath $Zip -DestinationPath $tmp -Force
        $tops = @(Get-ChildItem -LiteralPath $tmp -Directory)
        if ($tops.Count -ne 1) {
            throw ("в архиве {0} верхних каталогов {1} (ждём один) - правило переноса больше не верно" -f `
                   (Split-Path $Zip -Leaf), $tops.Count)
        }
        return Merge-Into $tops[0].FullName $Root
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Move-BinX64ToBin([string]$Root) {
    # Стендовый тулчейн держит DLL в bin\, а redist кладёт их в bin\x64\; комплект (манифест
    # pack_kit) ищет cublas64_13.dll именно в bin\. Копируем, не переносим: x64\ остаётся
    # там, где его ждёт CMake.
    $src = Join-Path $Root "bin\x64"
    if (-not (Test-Path -LiteralPath $src)) { return @() }
    $up = @()
    foreach ($dll in Get-ChildItem -LiteralPath $src -Filter *.dll -File) {
        Copy-Item -LiteralPath $dll.FullName -Destination (Join-Path $Root ("bin\" + $dll.Name)) -Force
        $up += $dll.Name
    }
    return $up
}

function Test-Toolchain([string]$Root) {
    # Обязательные файлы - не «красивое дерево», а то, без чего сборка упала бы другой ошибкой:
    # nvcc без nvvm/libdevice падает на device-link, cuobjdump без архива - на elf-proof.
    $need = @{
        "bin/nvcc.exe"                          = "компилятор CUDA"
        "bin/cuobjdump.exe"                     = "доказательство архитектур"
        "nvvm/libdevice/libdevice.10.bc"        = "библиотека устройств nvvm"
        "include/cuda_runtime.h"                = "заголовки runtime"
        "bin/cublas64_13.dll"                   = "cublas для линковки и комплекта"
        "bin/cublasLt64_13.dll"                 = "cublasLt (cublas зовёт его сам)"
    }
    $miss = @()
    foreach ($k in $need.Keys) {
        if (-not (Test-Path -LiteralPath (Join-Path $Root $k))) { $miss += "$k ($($need[$k]))" }
    }
    return $miss
}

# -----------------SelfTest: правило переноса и сверка байтов -----------------
if ($SelfTest) {
    $ok = 0
    $bad = 0
    function Chk([string]$Name, $Got, $Want) {
        if ($Got -eq $Want) { $script:ok++; Write-Host "  ok   $Name" }
        else { $script:bad++; Write-Host "  ПРОВАЛ ${Name}: получено '$Got', ждём '$Want'" }
    }
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("cuda-redist-selftest-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    # Собственный текст скрипта нужен отдельной проверке: байтовый порог пригодности индекса
    # уже не защищает ничего, и его возврат выглядел бы как «улучшение», а не как регрессия.
    $code_redist = Get-Content -LiteralPath $PSCommandPath -Raw -Encoding UTF8
    try {
        # Подложка архива ровно как у NVIDIA: одна верхняя папка, внутри bin/x64 и LICENSE.
        $stage = Join-Path $tmp "payload"
        New-Item -ItemType Directory -Force -Path (Join-Path $stage "bin\x64") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $stage "include") | Out-Null
        Write-NoBom (Join-Path $stage "LICENSE") "license"
        Write-NoBom (Join-Path $stage "bin\x64\cublas64_13.dll") "dll-bytes"
        Write-NoBom (Join-Path $stage "include\cuda_runtime.h") "header"
        $zip = Join-Path $tmp "cuda_selftest-windows-x86_64-1.0-archive.zip"
        Compress-Archive -Path $stage -DestinationPath $zip -Force
        $tc = Join-Path $tmp "cuda"
        New-Item -ItemType Directory -Force -Path $tc | Out-Null
        $moved = Expand-RedistArchive $zip $tc
        Chk "перенос срезает одну верхнюю папку и считает файлы" $moved 3
        Chk "include лёг в корень тулчейна" (Test-Path (Join-Path $tc "include\cuda_runtime.h")) $true
        Chk "LICENSE не конфликтует при повторе" (Test-Path (Join-Path $tc "LICENSE")) $true
        $up = Move-BinX64ToBin $tc
        Chk "DLL поднят из bin/x64 в bin" ($up -join ",") "cublas64_13.dll"
        Chk "копия, а не перенос: x64 остался на месте" (Test-Path (Join-Path $tc "bin\x64\cublas64_13.dll")) $true

        # Второй архив с ТЕМИ ЖЕ bin/x64 и include - ровно тот случай, который сломал живой
        # прогон 12.11: перенос каталога в уже существующий каталог-приёмник давал слой bin\bin,
        # и компоненты с общими каталогами (bin у 4 из 9, include у 6 из 9, lib у 3 из 9)
        # уходили вторым слоем мимо мест, которые проверяет Test-Toolchain.
        $stage2 = Join-Path $tmp "payload2"
        New-Item -ItemType Directory -Force -Path (Join-Path $stage2 "bin\x64") | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $stage2 "include") | Out-Null
        Write-NoBom (Join-Path $stage2 "LICENSE") "license"
        Write-NoBom (Join-Path $stage2 "bin\x64\cublasLt64_13.dll") "dll-bytes-2"
        Write-NoBom (Join-Path $stage2 "include\cublas_v2.h") "header-2"
        $zip2 = Join-Path $tmp "libcublas-windows-x86_64-13.6.0.2-archive.zip"
        Compress-Archive -Path $stage2 -DestinationPath $zip2 -Force
        $moved2 = Expand-RedistArchive $zip2 $tc
        Chk "второй архив принёс свои 3 файла" $moved2 3
        Chk "dll второго архива легла в bin/x64" (Test-Path (Join-Path $tc "bin\x64\cublasLt64_13.dll")) $true
        Chk "заголовок второго архива дописан в тот же include" `
            (Test-Path (Join-Path $tc "include\cublas_v2.h")) $true
        Chk "слоя bin\bin после слияния нет" (Test-Path (Join-Path $tc "bin\bin")) $false
        Chk "слоя include\include после слияния нет" (Test-Path (Join-Path $tc "include\include")) $false
        Chk "файл первого архива цел после слияния" (Test-Path (Join-Path $tc "bin\x64\cublas64_13.dll")) $true
        $up2 = @(Move-BinX64ToBin $tc)
        Chk "подъём находит обе dll после слияния" `
            (@($up2 | Where-Object { $_ -in @("cublas64_13.dll", "cublasLt64_13.dll") }).Count) 2

        # Список обязательных файлов обязан различать «нет файла» и «есть файл».
        $miss = @(Test-Toolchain $tc)
        Chk "полного тулчейна на подложке не хватает" ($miss.Count -ge 1) $true
        $full = Join-Path $tmp "full"
        foreach ($f in @("bin\nvcc.exe", "bin\cuobjdump.exe", "nvvm\libdevice\libdevice.10.bc",
                         "include\cuda_runtime.h", "bin\cublas64_13.dll", "bin\cublasLt64_13.dll")) {
            $p = Join-Path $full $f
            New-Item -ItemType Directory -Force -Path (Split-Path $p -Parent) | Out-Null
            Write-NoBom $p "x"
        }
        Chk "собранный тулчейн проходит проверку" (@(Test-Toolchain $full).Count) 0

        # Саботаж: закреплённый образ обязан не совпасть, и это должно быть видно как провал,
        # а не как «всё хорошо, пинов нет».
        $fake = Join-Path $tmp "fake.bin"
        Write-NoBom $fake "совсем другие байты"
        $got = Get-Sha256 $fake
        Chk "хеш считается и он не похож на пин" ($got -eq $PINS["cuda_nvcc"].sha) $false
        Chk "у закреплённых компонентов известна версия" ($PINS["libcublas"].min.StartsWith("libcublas/")) $true
        Chk "по умолчанию берём ровно 9 компонентов" @(Get-CudaDefaults).Count 9
        Chk "nvrtc и nvjitlink в набор не входят" `
            @(Get-CudaDefaults | Where-Object { $_ -in @('cuda_nvrtc', 'libnvjitlink') }).Count 0
        Chk "cuobjdump для elf-proof и cublas для комплекта в наборе" `
            @(Get-CudaDefaults | Where-Object { $_ -in @('cuda_cuobjdump', 'libcublas') }).Count 2
        Chk "в закреплённом списке все образы по 64 шестнадцатеричных цифры" `
            (@($PINS.Keys | Where-Object { $PINS[$_].sha -notmatch '^[0-9a-f]{64}$' }).Count) 0
        Chk "индекс по умолчанию не содержит путей стенда" ($BASE -match '[A-Za-z]:\\') $false
        try {
            Get-Sha256 (Join-Path $tmp "missing.bin")
            Chk "несуществующий файл - исключение, а не пустой хеш" "не бросил" "бросил"
        } catch {
            Chk "несуществующий файл - исключение, а не пустой хеш" "бросил" "бросил"
        }

        # Гейт пригодности индекса проверяется офлайн на подложках: сеть в selftest недоступна,
        # а ловить надо ровно те три способа испортить проверку, которые и описаны в функции.
        # Метка релиза и порог компонентов берутся из живого индекса 13.3.1 (49 компонентов,
        # release_label 13.3.1), поэтому подложка обязана проходить с тем же порогом.
        function New-FakeIndex([string]$Label, [int]$Count) {
            $o = [ordered]@{ release_date = "2026-06-29"; release_label = $Label; release_product = "cuda" }
            for ($i = 0; $i -lt $Count; $i++) {
                $o["comp$i"] = @{ "windows-x86_64" = @{ sha256 = ("{0:x64}" -f $i); size = "1024" } }
            }
            return ($o | ConvertTo-Json -Depth 6 -Compress)
        }
        $iGood = Join-Path $tmp "idx-good.json"
        Write-NoBom $iGood (New-FakeIndex $CudaVersion 49)
        Chk "полный индекс своей версии проходит гейт" @(Test-IndexJson -Path $iGood -Version $CudaVersion).Count 0
        $iLabel = Join-Path $tmp "idx-label.json"
        Write-NoBom $iLabel (New-FakeIndex "13.3.0" 49)
        Chk "индекс другой версии отбраковывается" `
            (@(Test-IndexJson -Path $iLabel -Version $CudaVersion).Count -ge 1) $true
        $iTiny = Join-Path $tmp "idx-tiny.json"
        Write-NoBom $iTiny (New-FakeIndex $CudaVersion 5)
        Chk "обрезанный индекс (5 компонентов) отбраковывается" `
            (@(Test-IndexJson -Path $iTiny -Version $CudaVersion).Count -ge 1) $true
        $iJunk = Join-Path $tmp "idx-junk.json"
        Write-NoBom $iJunk "<html><body>502 Bad Gateway</body></html>"
        Chk "страница ошибки вместо JSON отбраковывается" `
            (@(Test-IndexJson -Path $iJunk -Version $CudaVersion).Count -ge 1) $true
        # Байтовый порог в Save-Index больше не критерий: живой индекс проходил бы мимо него.
        # Ищем именно код (`if ($bytes -lt N)`), а не подстроку: число 50000 осознанно осталось
        # в комментариях как история, и проверка по тексту их бы заставила удалить.
        Chk "размер индекса больше не порог пригодности" `
            ($code_redist -match '\$bytes\s*-\s*lt\s*\d') $false
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host "install_cuda_redist selftest: ok=$ok bad=$bad"
    # Обрезанный или изменённый блок выглядел бы как «провалов нет»: порог проверок - часть меры.
    # 27 - число Chk, реально выполняющихся за прогон: в паре try/catch про несуществующий файл
    # срабатывает ровно один из двух вызовов, поэтому мерить надо по прогону, а не по строкам.
    if (($ok + $bad) -lt 27) { Write-Host "ИТОГ: проверок $($ok + $bad) меньше 27 - мера не состоялась"; exit 2 }
    if ($bad) { exit 1 }
    exit 0
}

# -----------------основной поток -----------------
if (-not $Root) { Write-Host "ОТКАЗ: -Root обязателен (каталог тулчейна) - проверка не состоялась"; exit 2 }
if (-not $Components) { $Components = @(Get-CudaDefaults) }
if (-not $Components.Count) { Write-Host "ОТКАЗ: список компонентов пуст - проверка не состоялась"; exit 2 }
foreach ($c in $Components) {
    if (-not $PINS.Contains($c)) {
        Write-Host ("ОТКАЗ: компонент '{0}' не закреплён - образ байтов неизвестен, брать его неоткуда" -f $c)
        Write-Host "         закрепите sha256 из redistrib_$CudaVersion.json после проверки, что это тот же релиз"
        exit 2
    }
}

$work = if ($CacheDir) { $CacheDir } else { Join-Path ([System.IO.Path]::GetTempPath()) "cuda-redist" }
New-Item -ItemType Directory -Force -Path $work | Out-Null
New-Item -ItemType Directory -Force -Path $Root | Out-Null

$idxPath = Join-Path $work ("redistrib_{0}.json" -f $CudaVersion)
if (-not (Save-Index $CudaVersion $idxPath)) { exit 2 }
$idx = ConvertFrom-Json (Get-Content -LiteralPath $idxPath -Raw -Encoding UTF8)

$report = [ordered]@{
    cuda_version = $CudaVersion
    base         = $BASE
    index_bytes  = (Get-Item -LiteralPath $idxPath).Length
    components   = @()
    raised_to_bin = @()
    result       = ""
}
$rc = 0
foreach ($name in $Components) {
    $entry = $idx.$name
    if (-not $entry) {
        Write-Host "ОТКАЗ: компонент '$name' отсутствует в индексе $CudaVersion"; $rc = 1; continue
    }
    $w = $entry."windows-x86_64"
    if (-not $w) {
        Write-Host "ОТКАЗ: у '$name' нет оконной записи - собирать нечем"; $rc = 1; continue
    }
    $rel = $w.relative_path
    $file = Split-Path $rel -Leaf
    $dest = Join-Path $work $file
    $indexSha = $w.sha256.ToLowerInvariant()
    $pinSha = $PINS[$name].sha
    Write-Host ("{0}: {1} (в индексе {2} Б)" -f $name, $file, ([long]$w.size))

    # Сначала сверяем пин с индексом: если NVIDIA обновила образ, молча качать его нельзя.
    if ($indexSha -ne $pinSha) {
        Write-Host ("ОТКАЗ: индекс предлагает {0}, а закреплено {1}" -f $indexSha, $pinSha)
        Write-Host "         это другой (или подменённый) бинарник компилятора - проверьте релиз и обновите пин"
        $rc = 1; continue
    }
    if (-not (Test-Path -LiteralPath $dest) -or (Get-Sha256 $dest) -ne $pinSha) {
        if (-not (Get-Archive "$BASE/$rel" $dest $Retries)) {
            Write-Host "ОТКАЗ: архив '$name' не скачан ($BASE/$rel) после $Retries попыток"
            $rc = 1; continue
        }
    }
    $got = Get-Sha256 $dest
    if ($got -ne $pinSha) {
        Write-Host ("ОТКАЗ: скачанный '{0}' имеет sha256 {1}, закреплено {2} - распаковку не делаем" -f `
                    $name, $got, $pinSha)
        $rc = 1; continue
    }
    $n = Expand-RedistArchive $dest $Root
    $report.components += [ordered]@{
        name = $name; version = $PINS[$name].min; archive = $file
        bytes = [long]$w.size; sha256 = $got; files_moved = $n
    }
    Write-Host ("  образ совпал, перенесено файлов {0}" -f $n)
}

$raised = @(Move-BinX64ToBin $Root)
$report.raised_to_bin = $raised
Write-Host ("поднято в bin/: {0}" -f ($raised -join ', '))

$miss = @(Test-Toolchain $Root)
if ($miss) {
    Write-Host ("ОТКАЗ: тулчейн неполный ({0}):" -f $miss.Count)
    foreach ($m in $miss) { Write-Host "         $m" }
    $rc = 1
}

if ($rc -eq 0) {
    $report.result = "тулчейн собран и проверен"
    Write-Host ("ИТОГ: CUDA {0} в $Root, компонентов {1}, образы байтов совпали" -f `
                $CudaVersion, @($report.components).Count)
} else {
    $report.result = "есть провалы, см вывод"
    Write-Host "ИТОГ: тулчейн не готов - сборку продолжать нельзя"
}
Write-NoBom (Join-Path $Root "cuda-redist-measure.json") ($report | ConvertTo-Json -Depth 5)
exit $rc
