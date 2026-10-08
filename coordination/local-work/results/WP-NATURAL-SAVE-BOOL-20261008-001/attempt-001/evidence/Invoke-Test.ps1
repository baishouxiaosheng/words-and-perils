param([Parameter(Mandatory=$true)][string]$RunName)
$ErrorActionPreference='Stop'
$runRoot=Join-Path $PSScriptRoot $RunName
& (Join-Path $PSScriptRoot 'Gate.ps1') -Boundary ('engine_'+$RunName)
if(-not (Test-Path -LiteralPath (Join-Path $runRoot 'PREPARATION.json')) -or -not (Test-Path -LiteralPath (Join-Path $runRoot 'SPEC.json'))) {throw 'Preparation not completed; no launch'}
if(Test-Path -LiteralPath (Join-Path $runRoot 'actual_host.stdout.log')) {throw 'Preserve previous invocation'}
& (Get-Command pwsh).Source -NoProfile -NonInteractive -File (Join-Path $PSScriptRoot 'Run-Test.ps1') -RunName $RunName -Attempt actual 1> (Join-Path $runRoot 'actual_host.stdout.log') 2> (Join-Path $runRoot 'actual_host.stderr.log')
$taskExit=$LASTEXITCODE
[ordered]@{host_exit_code=$taskExit;completed_utc=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $runRoot 'actual_HOST_EXIT.json') -Encoding utf8
Get-Content -LiteralPath (Join-Path $runRoot 'actual_host.stdout.log')
Get-Content -LiteralPath (Join-Path $runRoot 'actual_host.stderr.log')
exit $taskExit
