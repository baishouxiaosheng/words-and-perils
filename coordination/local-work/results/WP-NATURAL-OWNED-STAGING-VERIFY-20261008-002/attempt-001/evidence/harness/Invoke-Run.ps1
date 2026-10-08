param([Parameter(Mandatory=$true)][string]$RunName)
$ErrorActionPreference='Stop'
$root=Join-Path $PSScriptRoot ('runs/'+$RunName)
& python (Join-Path $PSScriptRoot 'gate_entry.py') ('engine_'+$RunName)
if($LASTEXITCODE -ne 0){throw 'Gate failed; do not launch'}
if(Test-Path -LiteralPath (Join-Path $root 'actual_host.stdout.log')){throw 'Run already invoked; preserve evidence'}
& (Get-Command pwsh).Source -NoProfile -NonInteractive -File (Join-Path $PSScriptRoot 'Run-Test.ps1') -RunName ('runs/'+$RunName) -Attempt actual 1> (Join-Path $root 'actual_host.stdout.log') 2> (Join-Path $root 'actual_host.stderr.log')
$code=$LASTEXITCODE
[ordered]@{host_exit_code=$code;completed_utc=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'actual_HOST_EXIT.json') -Encoding utf8NoBOM
Get-Content -LiteralPath (Join-Path $root 'actual_host.stdout.log')
Get-Content -LiteralPath (Join-Path $root 'actual_host.stderr.log')
exit $code
