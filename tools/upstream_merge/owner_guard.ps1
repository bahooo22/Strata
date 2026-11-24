param()

$ErrorActionPreference = 'Stop'
$allowed = '443fddf1-c6a1-4de1-a762-0b61e5ca941c'

try {
    $raw = [Console]::In.ReadToEnd()
    $event = $raw | ConvertFrom-Json
} catch {
    exit 0
}

$tool = [string]$event.tool_name
if ($tool -ne 'Bash') {
    exit 0
}

$command = [string]$event.tool_input.command
$patterns = @(
    'build_strata_nommq',
    'cmake\s+--build',
    '(^|[\s/])ninja(\.exe)?\s',
    '(^|[\s/])ctest(\.exe)?\s',
    'pytest',
    'python[^\n]*test_upstream_merge',
    'upstream_merge\.py[^\n]*(check|selftest|promote)',
    'merge-gate\.py[^\n]*(check|selftest)'
)

foreach ($pattern in $patterns) {
    if ($command -match $pattern) {
        $sessionId = [string]$event.session_id
        if ($sessionId -ne $allowed) {
            [Console]::Error.WriteLine("ОТКАЗ: сборки и прогоны разрешены только сеансу $allowed; текущий сеанс: $sessionId")
            exit 2
        }
        exit 0
    }
}

exit 0
