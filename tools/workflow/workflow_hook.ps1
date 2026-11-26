param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Pre', 'Post', 'Context', 'Selftest')]
    [string]$Mode
)

$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

function Read-Event {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return $raw | ConvertFrom-Json
}

function Get-Repo {
    $root = [Environment]::GetEnvironmentVariable('QODER_PROJECT_DIR')
    if ([string]::IsNullOrWhiteSpace($root)) { $root = (Get-Location).Path }
    return [System.IO.Path]::GetFullPath($root)
}

function Get-Participants {
    param([string]$Repo)
    $path = Join-Path $Repo 'docs/workflow/participants.json'
    if (-not (Test-Path -LiteralPath $path)) { return @{} }
    $data = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    return @{
        A = [string]$data.A
        H = [string]$data.H
        N = [string]$data.N
    }
}

function Get-Role {
    param($Event, [hashtable]$Participants)
    $session = [string]$Event.session_id
    foreach ($role in @('A', 'H', 'N')) {
        if ($session -eq $Participants[$role]) { return $role }
    }
    return 'FOREIGN'
}

function Get-Branch {
    param([string]$Repo)
    $result = & git -C $Repo branch --show-current 2>$null
    if ($LASTEXITCODE -ne 0) { return '' }
    return ([string]$result).Trim()
}

function Get-TaskId {
    param($Event, [string]$Repo)
    $explicit = [Environment]::GetEnvironmentVariable('STRATA_TASK_ID')
    if (-not [string]::IsNullOrWhiteSpace($explicit)) { return $explicit }
    $branch = Get-Branch $Repo
    if ($branch -match '^task/(.+)$') { return $Matches[1] }
    return ''
}

function Get-TaskState {
    param([string]$Repo, [string]$TaskId)
    if ([string]::IsNullOrWhiteSpace($TaskId)) { return $null }
    $path = Join-Path $Repo 'docs/workflow/state.json'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $state = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    $property = $state.tasks.PSObject.Properties[$TaskId]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Test-GitMutation {
    param([string]$Command)
    return $Command -match '(^|[\s;&])git[^\n;]*\s(commit|push|merge|reset|rebase|checkout|switch|restore|clean)(\s|$)'
}

function Test-BuildOrTest {
    param([string]$Command)
    return $Command -match 'build_strata_nommq|cmake\s+--build|(^|[\s/])ninja(\.exe)?(\s|$)|(^|[\s/])ctest(\.exe)?(\s|$)|pytest|python[^\n]*test_'
}

function Get-ToolPath {
    param($Event)
    $input = $Event.tool_input
    if ($null -eq $input) { return '' }
    $path = [string]$input.file_path
    if ([string]::IsNullOrWhiteSpace($path)) { $path = [string]$input.path }
    return $path
}

function Assert-PreToolUse {
    param($Event, [string]$Repo, [hashtable]$Participants)
    $tool = [string]$Event.tool_name
    if ($tool -eq 'Agent') { return 'Workflow v3 запрещает Agent/subagents; используйте отдельные сеансы A/H/N.' }

    $mutation = $false
    if ($tool -in @('Write', 'Edit')) { $mutation = $true }
    if ($tool -eq 'Bash') {
        $command = [string]$Event.tool_input.command
        if (Test-GitMutation $command) { $mutation = $true }
        if (Test-BuildOrTest $command) { $mutation = $true }
    }
    if (-not $mutation) { return $null }

    $role = Get-Role $Event $Participants
    if ($role -eq 'FOREIGN') { return 'Workflow v3: FOREIGN не выполняет мутации, build или GPU.' }

    if ($tool -in @('Write', 'Edit')) {
        if ($role -eq 'N') {
            $path = Get-ToolPath $Event
            $normalized = $path.Replace('\', '/')
            if ($normalized -notmatch '^docs/workflow/tasks/[^/]+/REVIEW_REPORT\.(md|json)$') {
                return 'Workflow v3: N пишет только REVIEW_REPORT.md/.json в каталог задачи.'
            }
            return $null
        }
        if ($role -eq 'H') {
            $branch = Get-Branch $Repo
            if ($branch -notmatch '^task/') { return 'Workflow v3: H редактирует только отдельную task-ветку.' }
            $path = Get-ToolPath $Event
            $full = [System.IO.Path]::GetFullPath((Join-Path $Repo $path))
            if ($full -ne $Repo -and -not $full.StartsWith($Repo + [System.IO.Path]::DirectorySeparatorChar)) {
                return 'Workflow v3: H не пишет вне репозитория.'
            }
            foreach ($reserved in @('docs/workflow/state.json', 'docs/workflow/events.jsonl', 'docs/workflow/participants.json')) {
                $reservedPath = [System.IO.Path]::GetFullPath((Join-Path $Repo $reserved))
                if ($full -eq $reservedPath) { return 'Workflow v3: глобальный state меняет только A через workflow.py.' }
            }
        }
        return $null
    }

    $command = [string]$Event.tool_input.command
    if (Test-BuildOrTest $command) {
        if ($role -ne 'A') { return 'Workflow v3: build/test выполняет A после CODE_APPROVED.' }
        return $null
    }

    if (Test-GitMutation $command) {
        if ($role -ne 'A') { return 'Workflow v3: commit/push/merge выполняет только A.' }
        $taskId = Get-TaskId $Event $Repo
        $task = Get-TaskState $Repo $taskId
        if ($null -eq $task) { return 'Workflow v3: для git-мутации нужен task state.' }
        if ($command -match 'git\s+commit') {
            if ($task.gate -ne 'UPSTREAM_PR_CHECK') { return 'Workflow v3: commit main разрешён только на UPSTREAM_PR_CHECK.' }
        }
        if ($command -match 'git\s+(push|merge)') {
            if ($task.gate -ne 'MERGED') { return 'Workflow v3: push/merge main разрешены только после MERGED.' }
        }
    }
    return $null
}

function Write-Context {
    param($Event, [string]$Repo, [hashtable]$Participants)
    $role = Get-Role $Event $Participants
    $taskId = Get-TaskId $Event $Repo
    $task = Get-TaskState $Repo $taskId
    Write-Output "WORKFLOW v3: роль=$role task=$taskId gate=$($task.gate)"
    switch ($role) {
        'A' { Write-Output 'A: TASK_IDEA, idea diagram, прогоны, INTEGRATION_REPORT, commit/push/merge после гейтов.' }
        'H' { Write-Output 'H: IMPL_PLAN, PATCH, DOC_IMPL, algorithm diagram в task-worktree; без commit/push/merge и GPU.' }
        'N' { Write-Output 'N: read-only REVIEW_REPORT C1-C10; без edit/build/GPU.' }
        default { Write-Output 'FOREIGN: только read-only.' }
    }
}

function Write-Audit {
    param($Event, [string]$Repo, [hashtable]$Participants)
    $role = Get-Role $Event $Participants
    $path = Join-Path $Repo 'docs/workflow/events.jsonl'
    $record = [ordered]@{
        time = [DateTime]::UtcNow.ToString('o')
        event = 'post-tool-use'
        actor = $role
        tool = [string]$Event.tool_name
        target = (Get-ToolPath $Event)
    }
    Add-Content -LiteralPath $path -Value ($record | ConvertTo-Json -Compress) -Encoding UTF8
}

function Invoke-Selftest {
    [Environment]::SetEnvironmentVariable('STRATA_TASK_ID', 'T1')
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('workflow-hook-' + [Guid]::NewGuid().ToString('N'))
    $repo = Join-Path $root 'repo'
    New-Item -ItemType Directory -Path (Join-Path $repo 'docs/workflow') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $repo 'docs/workflow/locks') -Force | Out-Null
    $participants = @{ A = 'A'; H = 'H'; N = 'N' }
    @{ A = 'A'; H = 'H'; N = 'N' } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $repo 'docs/workflow/participants.json') -Encoding UTF8
    $state = @{ version = 1; tasks = @{ T1 = @{ gate = 'G5'; branch = 'task/T1'; upstreamPr = @{ status = 'not-run' } } } }
    $state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $repo 'docs/workflow/state.json') -Encoding UTF8
    $passed = 0
    function Check($Condition, $Name) {
        if (-not $Condition) { throw "Assertion failed: $Name" }
        $script:passed += 1
        Write-Output "ok $script:passed`: $Name"
    }
    $agent = [pscustomobject]@{ tool_name = 'Agent'; session_id = 'A'; tool_input = @{} }
    Check ($null -ne (Assert-PreToolUse $agent $repo $participants)) 'Agent запрещён'
    $hCommit = [pscustomobject]@{ tool_name = 'Bash'; session_id = 'H'; tool_input = @{ command = 'git -C repo commit -m x' } }
    Check ($null -ne (Assert-PreToolUse $hCommit $repo $participants)) 'H commit запрещён'
    $nWrite = [pscustomobject]@{ tool_name = 'Write'; session_id = 'N'; tool_input = @{ file_path = 'x.txt' } }
    Check ($null -ne (Assert-PreToolUse $nWrite $repo $participants)) 'N edit запрещён'
    $nReview = [pscustomobject]@{ tool_name = 'Write'; session_id = 'N'; tool_input = @{ file_path = 'docs/workflow/tasks/T1/REVIEW_REPORT.md' } }
    Check ($null -eq (Assert-PreToolUse $nReview $repo $participants)) 'N REVIEW_REPORT разрешён'
    $foreign = [pscustomobject]@{ tool_name = 'Bash'; session_id = 'X'; tool_input = @{ command = 'ninja' } }
    Check ($null -ne (Assert-PreToolUse $foreign $repo $participants)) 'Foreign build запрещён'
    $aPush = [pscustomobject]@{ tool_name = 'Bash'; session_id = 'A'; tool_input = @{ command = 'git push origin main' } }
    Check ($null -ne (Assert-PreToolUse $aPush $repo $participants)) 'A push до MERGED запрещён'
    $state.tasks.T1.gate = 'MERGED'
    $state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $repo 'docs/workflow/state.json') -Encoding UTF8
    Check ($null -eq (Assert-PreToolUse $aPush $repo $participants)) 'A push после MERGED разрешён'
    Remove-Item -LiteralPath $root -Recurse -Force
    Write-Output "Selftest: $script:passed проверок пройдено."
}

try {
    $repo = Get-Repo
    $participants = Get-Participants $repo
    if ($Mode -eq 'Selftest') {
        Invoke-Selftest
        exit 0
    }
    $event = Read-Event
    if ($null -eq $event) { exit 0 }
    if ($Mode -eq 'Context') {
        Write-Context $event $repo $participants
        exit 0
    }
    if ($Mode -eq 'Post') {
        Write-Audit $event $repo $participants
        exit 0
    }
    $errorMessage = Assert-PreToolUse $event $repo $participants
    if ($null -ne $errorMessage) {
        [Console]::Error.WriteLine($errorMessage)
        exit 2
    }
    exit 0
} catch {
    [Console]::Error.WriteLine("Workflow hook: $($_.Exception.Message)")
    exit 1
}
