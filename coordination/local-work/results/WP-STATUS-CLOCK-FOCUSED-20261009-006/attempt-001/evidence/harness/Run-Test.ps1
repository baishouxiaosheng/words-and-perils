param([Parameter(Mandatory=$true)][string]$RunName,[string]$Attempt='actual')
$ErrorActionPreference='Stop'
$taskRoot='E:\WordsAndPerils-Tasks\candidate-20261008-ea04d75a'
$runRoot=Join-Path $PSScriptRoot $RunName
if(Test-Path -LiteralPath (Join-Path $runRoot 'GUARD_RESULT.json')) {throw 'Existing result must not be overwritten'}
if(Get-Process | Where-Object ProcessName -match 'Godot') {throw 'Unknown Godot found; preserved, no launch'}
$guardRoot=Join-Path $taskRoot 'windows-guard-v3'
$pins=@(Get-Content -LiteralPath (Join-Path $guardRoot 'source-hashes.json') -Raw | ConvertFrom-Json)
$rows=@($pins | ForEach-Object { $actual=(Get-FileHash -LiteralPath (Join-Path $guardRoot $_.name)).Hash.ToLowerInvariant(); [ordered]@{name=$_.name;expected=$_.sha256;actual=$actual;matches=$actual -eq $_.sha256} })
$exe='E:\WordsAndPerils-Test\Godot\4.6.3\Godot_v4.6.3-stable_win64.exe'
$exeHash=(Get-FileHash -LiteralPath $exe).Hash.ToLowerInvariant()
if(@($rows | Where-Object {-not $_.matches}).Count -or $exeHash -ne 'ef90e929ba1a6a4322860285d97f40f4aa349c90329a91b0e8b55b8df0f4cb00') {throw 'Guard or engine source changed; no launch'}
$rows | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runRoot ($Attempt+'_GUARD_SOURCE_PRELAUNCH.json')) -Encoding utf8
$hostProcess=Get-Process -Id $PID
[ordered]@{host_pid=$PID;host_created_utc=$hostProcess.StartTime.ToUniversalTime().ToString('o');utc=[DateTime]::UtcNow.ToString('o');fresh_powershell=$true;guard_compiled_per_run=$true;guard_source_sha256=$rows[0].actual;engine_sha256=$exeHash;injections=$false;profile='small';unknown_processes_killed=$false} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $runRoot ($Attempt+'_HOST_IDENTITY.json')) -Encoding utf8
& (Join-Path $guardRoot 'Invoke-WindowsGuard.ps1') -SpecPath (Join-Path $runRoot 'SPEC.json')
exit $LASTEXITCODE
