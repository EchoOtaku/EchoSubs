param(
    [ValidateSet('unit', 'windows', 'android', 'all')][string]$Stage = 'unit',
    [ValidateRange(0, 86400)][int]$TimeoutSeconds = 0
)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$output = Join-Path $repo ('.local/verify/' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $output -Force | Out-Null
$pwsh = (Get-Process -Id $PID).Path
$flutter = (Get-Command flutter -ErrorAction Stop).Source
$dart = (Get-Command dart -ErrorAction Stop).Source
function Start-Stage([string]$Name, [int]$DefaultLimit) {
    $script:stageStart = Get-Date
    $limit = if ($TimeoutSeconds -gt 0) { $TimeoutSeconds } else { $DefaultLimit }
    $script:stageDeadline = $script:stageStart.AddSeconds($limit)
    Write-Output "STAGE START $Name deadline=$($script:stageDeadline.ToString('o'))"
}
function End-Stage([string]$Name) {
    Write-Output "STAGE END $Name elapsed=$([math]::Round(((Get-Date)-$script:stageStart).TotalSeconds, 1))s exit=0"
}
function Invoke-Checked([string]$Name, [string]$Tool, [string[]]$Arguments, [int]$DefaultLimit) {
    $limit = [math]::Floor(($script:stageDeadline - (Get-Date)).TotalSeconds)
    if ($limit -le 0) { throw "$Name stage deadline already exceeded before command: $Tool $($Arguments -join ' ')" }
    $out = Join-Path $output "$Name.stdout.log"
    $err = Join-Path $output "$Name.stderr.log"
    $script = Join-Path $output "$Name.ps1"
    $quoted = @($Arguments | ForEach-Object { "'" + $_.Replace("'", "''") + "'" }) -join ' '
    Set-Content -LiteralPath $script -Value ("& '" + $Tool.Replace("'", "''") + "' " + $quoted + "`nexit `$LASTEXITCODE") -Encoding utf8
    $start = Get-Date
    Write-Output "START $Name command=$Tool $($Arguments -join ' ') deadline=$($start.AddSeconds($limit).ToString('o'))"
    $p = Start-Process $pwsh -ArgumentList @('-NoProfile', '-File', ('"' + $script + '"')) -WorkingDirectory $repo -WindowStyle Hidden -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
    Write-Output "OWNED PID=$($p.Id)"
    $last = $start
    try {
        while (-not $p.WaitForExit(1000)) {
            $elapsed = ((Get-Date) - $start).TotalSeconds
            if ($elapsed -ge $limit) { throw "$Name timeout after ${limit}s" }
            if (((Get-Date) - $last).TotalSeconds -ge 15) {
                Write-Output "PROGRESS $Name elapsed=$([int]$elapsed)s"
                Get-Content $out -Tail 8 -ErrorAction SilentlyContinue
                Get-Content $err -Tail 4 -ErrorAction SilentlyContinue
                $last = Get-Date
            }
        }
        $p.WaitForExit()
        Get-Content $out
        Get-Content $err
        if ($p.ExitCode -ne 0) { throw "$Name exit=$($p.ExitCode): $Tool $($Arguments -join ' ')" }
        Write-Output "END $Name elapsed=$([math]::Round(((Get-Date)-$start).TotalSeconds, 1))s exit=0"
    } catch {
        if (-not $p.HasExited) { & taskkill.exe /PID $p.Id /T /F | Write-Output }
        Get-Content $out -Tail 12 -ErrorAction SilentlyContinue
        Get-Content $err -Tail 8 -ErrorAction SilentlyContinue
        Write-Output "FAIL $Name command=$Tool $($Arguments -join ' ') elapsed=$([math]::Round(((Get-Date)-$start).TotalSeconds, 1))s: $_"
        throw
    }
}
try {
    if ($Stage -in @('unit', 'all')) {
        Start-Stage 'unit' 300
        Invoke-Checked 'tests' $flutter @('test', '--reporter', 'expanded') 300
        Invoke-Checked 'analyze' $flutter @('analyze') 300
        Invoke-Checked 'format' $dart @('format', '--output=none', '--set-exit-if-changed', 'lib', 'test', 'integration_test') 300
        End-Stage 'unit'
    }
    if ($Stage -in @('windows', 'all')) {
        Start-Stage 'windows' 900
        Invoke-Checked 'windows-offline' $flutter @('test', 'integration_test/offline_flow_test.dart', '-d', 'windows', '--no-uninstall', '--reporter', 'expanded') 900
        Invoke-Checked 'windows-release' $flutter @('build', 'windows', '--release') 900
        End-Stage 'windows'
    }
    if ($Stage -in @('android', 'all')) {
        Start-Stage 'android' 900
        if ($env:ECHOSUBS_INTEGRATION_TEST -eq '1') { throw 'Release build requires a normal app process, not integration isolation.' }
        Invoke-Checked 'android-release' $flutter @('build', 'apk', '--release') 900
        End-Stage 'android'
    }
    Write-Output "Logs: $output"
} catch { Write-Error $_; exit 1 }
