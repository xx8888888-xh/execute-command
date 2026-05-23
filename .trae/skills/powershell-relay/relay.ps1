param(
    [string]$EncodedCommand,
    [string]$CommandFile,
    [string]$OutputFile,
    [string]$CwdFile,
    [int]$TimeoutSeconds = 300,
    [switch]$Cleanup
)

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$relayDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not $CommandFile) {
    $CommandFile = Join-Path $relayDir "relay_cmd.txt"
}
if (-not $OutputFile) {
    $OutputFile = Join-Path $relayDir "relay_out.txt"
}
if (-not $CwdFile) {
    $CwdFile = Join-Path $relayDir "relay_cwd.txt"
}

$exitFile = Join-Path $relayDir "relay_exit.txt"
$errFile = Join-Path $relayDir "relay_err.txt"

if ($Cleanup) {
    $tempFiles = @($CommandFile, $CwdFile, $OutputFile, $exitFile, $errFile)
    foreach ($f in $tempFiles) {
        if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
    }
    Write-Output "Cleanup done"
    exit 0
}

if (Test-Path $OutputFile) { Remove-Item $OutputFile -Force -ErrorAction SilentlyContinue }
if (Test-Path $exitFile) { Remove-Item $exitFile -Force -ErrorAction SilentlyContinue }
if (Test-Path $errFile) { Remove-Item $errFile -Force -ErrorAction SilentlyContinue }

$command = ""

if ($EncodedCommand) {
    try {
        $bytes = [System.Convert]::FromBase64String($EncodedCommand)
        $command = [System.Text.Encoding]::UTF8.GetString($bytes)
    } catch {
        "ERROR: Failed to decode Base64 command: $($_.Exception.Message)" | Out-File -FilePath $OutputFile -Encoding utf8
        "1" | Out-File -FilePath $exitFile -Encoding utf8
        Remove-Item $CommandFile -Force -ErrorAction SilentlyContinue
        Remove-Item $CwdFile -Force -ErrorAction SilentlyContinue
        exit 1
    }
} elseif (Test-Path $CommandFile) {
    $command = (Get-Content -Path $CommandFile -Raw -Encoding utf8).Trim()
} else {
    "ERROR: No command provided. Use -EncodedCommand or create relay_cmd.txt" | Out-File -FilePath $OutputFile -Encoding utf8
    "1" | Out-File -FilePath $exitFile -Encoding utf8
    exit 1
}

if ([string]::IsNullOrWhiteSpace($command)) {
    "ERROR: Command is empty" | Out-File -FilePath $OutputFile -Encoding utf8
    "1" | Out-File -FilePath $exitFile -Encoding utf8
    Remove-Item $CommandFile -Force -ErrorAction SilentlyContinue
    Remove-Item $CwdFile -Force -ErrorAction SilentlyContinue
    exit 1
}

if (Test-Path $CwdFile) {
    $cwd = (Get-Content -Path $CwdFile -Raw -Encoding utf8).Trim()
    if (-not [string]::IsNullOrWhiteSpace($cwd) -and (Test-Path $cwd -PathType Container)) {
        Set-Location $cwd
    }
}

Remove-Item $CommandFile -Force -ErrorAction SilentlyContinue
Remove-Item $CwdFile -Force -ErrorAction SilentlyContinue

$env:PATH = "C:\Windows\System32;C:\Windows\SysWOW64;C:\Windows;C:\Windows\System32\Wbem;" + $env:PATH

try {
    $output = Invoke-Expression $command 2>&1
    $lastExit = $LASTEXITCODE

    $stdout = ""
    $stderr = ""
    foreach ($line in $output) {
        if ($line -is [System.Management.Automation.ErrorRecord]) {
            $stderr += $line.ToString() + "`n"
        } else {
            $stdout += $line.ToString() + "`n"
        }
    }

    $stdout | Out-File -FilePath $OutputFile -Encoding utf8 -NoNewline
    $stderr | Out-File -FilePath $errFile -Encoding utf8 -NoNewline

    if ($null -ne $lastExit -and $lastExit -ne 0) {
        "$lastExit" | Out-File -FilePath $exitFile -Encoding utf8
    } else {
        "0" | Out-File -FilePath $exitFile -Encoding utf8
    }
} catch {
    "ERROR: $($_.Exception.Message)" | Out-File -FilePath $errFile -Encoding utf8
    "1" | Out-File -FilePath $exitFile -Encoding utf8
}
