param(
    [Parameter(Mandatory)][ValidateSet('Android', 'Windows', 'VerifyApk')][string]$Platform,
    [string]$Device,
    [string]$Aapt,
    [string]$Apk,
    [ValidateSet('integration_test/lan_pairing_test.dart', 'integration_test/reminders_test.dart')][string]$Target = 'integration_test/lan_pairing_test.dart',
    [Parameter(Mandatory)][string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
$allowedRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot '.local')) + [IO.Path]::DirectorySeparatorChar
if (-not $outputRoot.StartsWith($allowedRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Native test artifacts must be in this checkout .local directory.'
}
$expectedPackage = 'dev.echootaku.echo_subs.integration'
function Assert-IsolatedApk([string]$File) {
    if (-not $Aapt -or -not (Test-Path -LiteralPath $Aapt) -or -not (Test-Path -LiteralPath $File)) {
        throw 'Pass existing SDK aapt and APK paths; this helper installs no tools.'
    }
    $badging = & $Aapt dump badging $File
    if ($LASTEXITCODE -ne 0) { throw 'APK metadata verification failed.' }
    $line = $badging | Where-Object { $_ -match '^package: name=' } | Select-Object -First 1
    if ($line -notmatch "^package: name='([^']+)'" -or $Matches[1] -ne $expectedPackage) {
        throw 'Refusing to run: APK is not the isolated integration package.'
    }
    Write-Output "Verified isolated APK package: $expectedPackage"
}
if ($Platform -eq 'VerifyApk') { Assert-IsolatedApk $Apk; exit 0 }

$flutter = (Get-Command flutter -ErrorAction Stop).Source
New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
function Invoke-Native([string]$Name, [string[]]$CommandArguments) {
    $stdout = Join-Path $outputRoot "$Name.stdout.log"
    $stderr = Join-Path $outputRoot "$Name.stderr.log"
    $process = Start-Process -FilePath $flutter -ArgumentList $CommandArguments -WorkingDirectory $repoRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $started = Get-Date
    $progress = $started
    Write-Output "$Name owned PID=$($process.Id), hard deadline=$($started.AddMinutes(15).ToString('o'))"
    while (-not $process.WaitForExit(1000)) {
        if (((Get-Date) - $started).TotalSeconds -ge 900) {
            & taskkill.exe /PID $process.Id /T /F
            throw "$Name exceeded its 15-minute hard limit."
        }
        if (((Get-Date) - $progress).TotalSeconds -ge 20) {
            Write-Output "$Name elapsed=$([int]((Get-Date) - $started).TotalSeconds)s"
            Get-Content -LiteralPath $stdout -Tail 6 -ErrorAction SilentlyContinue
            Get-Content -LiteralPath $stderr -Tail 3 -ErrorAction SilentlyContinue
            $progress = Get-Date
        }
    }
    $process.WaitForExit()
    Get-Content -LiteralPath $stdout -Tail 30
    Get-Content -LiteralPath $stderr -Tail 12
    if ($process.ExitCode -ne 0) { throw "$Name failed: exit $($process.ExitCode). Diagnose before retrying." }
}
$previousIsolation = $env:ECHOSUBS_INTEGRATION_TEST
$previousOutput = $env:ECHOSUBS_LAN_TEST_DIR
try {
    $env:ECHOSUBS_LAN_TEST_DIR = $outputRoot
    if ($Platform -eq 'Android') {
        if (-not $Device) { throw 'Specify the existing Android device serial.' }
        $env:ECHOSUBS_INTEGRATION_TEST = '1'
        Invoke-Native 'android-build' @('build', 'apk', '--debug', '--target', $Target)
        $apkPath = Join-Path $repoRoot 'build/app/outputs/flutter-apk/app-debug.apk'
        Assert-IsolatedApk $apkPath
        # flutter test rebuilds the same target with the same process opt-in.
        # --no-uninstall is mandatory even for this separate fictional-data app.
        Invoke-Native 'android-test' @('test', $Target, '-d', $Device, '--no-uninstall', '--reporter', 'expanded')
        Assert-IsolatedApk $apkPath
    } else {
        Invoke-Native 'windows-test' @('test', $Target, '-d', 'windows', '--no-uninstall', '--reporter', 'expanded')
    }
} finally {
    $env:ECHOSUBS_INTEGRATION_TEST = $previousIsolation
    $env:ECHOSUBS_LAN_TEST_DIR = $previousOutput
}
