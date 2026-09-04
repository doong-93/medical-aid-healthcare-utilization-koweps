param(
    [ValidateSet('Check', 'Integration', 'Full')][string]$Mode = 'Check',
    [string]$SasExecutable = 'C:\Program Files\SASHome\SASFoundation\9.4\sas.exe',
    [ValidateRange(1, 240)][int]$MaxMinutes = 60
)
$ErrorActionPreference = 'Stop'
$codeDirectory = [IO.Path]::GetFullPath($PSScriptRoot)
if (-not (Test-Path -LiteralPath $SasExecutable -PathType Leaf)) {
    throw 'SAS was not found. Supply its location with -SasExecutable.'
}
$runIdentifier = 'run_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff')
$logDirectory = Join-Path $codeDirectory ('logs\' + $runIdentifier)
New-Item -ItemType Directory -Path $logDirectory | Out-Null
$entryName = switch ($Mode) {
    'Full' { '00_run_all.sas' }
    'Integration' { 'tests\test_pipeline.sas' }
    default { 'tests\test_core.sas' }
}
$entryPath = Join-Path $codeDirectory $entryName
$logPath = Join-Path $logDirectory 'analysis.log'
$listingPath = Join-Path $logDirectory 'analysis.lst'
$oldCode = $env:MA_DID_CODE
$oldRun = $env:MA_DID_RUN
$oldTest = $env:MA_DID_TEST_OUT
try {
    $env:MA_DID_CODE = $codeDirectory
    $env:MA_DID_RUN = $runIdentifier
    $env:MA_DID_TEST_OUT = $logDirectory
    $arguments = @('-noterminal', '-nosplash', '-encoding', 'utf-8',
        '-sysin', ('"' + $entryPath + '"'),
        '-log', ('"' + $logPath + '"'), '-print', ('"' + $listingPath + '"'))
    $process = Start-Process -FilePath $SasExecutable -ArgumentList $arguments `
        -WorkingDirectory $codeDirectory -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit($MaxMinutes * 60000)) {
        $process.Kill()
        throw 'This SAS process exceeded the requested time limit.'
    }
    $process.Refresh()
    $sasExitCode = $process.ExitCode
    if (-not (Test-Path -LiteralPath $logPath)) {
        throw "SAS exited with code $sasExitCode before producing a log. No analysis or test success is established."
    }
    $logText = Get-Content -LiteralPath $logPath -Raw
    if ($sasExitCode -notin @(0, 1) -or $logText -match '(?m)^ERROR(?:\s|:|\s+\d+)') {
        throw "SAS reported a failure (exit $sasExitCode). Review $logPath"
    }
    $marker = switch ($Mode) {
        'Check' { 'CORE_TESTS_PASSED' }
        'Integration' { 'PIPELINE_TESTS_PASSED' }
        default { 'Workflow finished.' }
    }
    if ($logText -notmatch ('(?m)^NOTE: ' + [regex]::Escape($marker))) {
        throw "Completion was not confirmed. Review $logPath"
    }
    Write-Output "Finished $Mode. Review log and diagnostic outputs: $logDirectory"
    if ($Mode -eq 'Full') { Write-Output (Join-Path $codeDirectory ('outputs\' + $runIdentifier)) }
}
finally {
    $env:MA_DID_CODE = $oldCode
    $env:MA_DID_RUN = $oldRun
    $env:MA_DID_TEST_OUT = $oldTest
}
