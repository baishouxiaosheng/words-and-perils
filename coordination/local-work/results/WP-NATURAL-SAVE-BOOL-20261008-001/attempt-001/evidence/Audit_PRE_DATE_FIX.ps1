param([Parameter(Mandatory=$true)][string]$RunName)
$ErrorActionPreference='Stop'
$runRoot=Join-Path $PSScriptRoot $RunName
function Get-TaskHash($p) {(Get-FileHash -LiteralPath $p).Hash.ToLowerInvariant()}
$prep=Get-Content -LiteralPath (Join-Path $runRoot 'PREPARATION.json') -Raw | ConvertFrom-Json
$guard=Get-Content -LiteralPath (Join-Path $runRoot 'GUARD_RESULT.json') -Raw | ConvertFrom-Json
$guardHost=Get-Content -LiteralPath (Join-Path $runRoot 'actual_HOST_IDENTITY.json') -Raw | ConvertFrom-Json
$hostExit=Get-Content -LiteralPath (Join-Path $runRoot 'actual_HOST_EXIT.json') -Raw | ConvertFrom-Json
$hostProcess=Get-Process -Id $guardHost.host_pid -ErrorAction SilentlyContinue
$hostExited=-not ($hostProcess -and $hostProcess.StartTime.ToUniversalTime().ToString('o') -eq $guardHost.host_created_utc)
[IO.File]::WriteAllText((Join-Path $runRoot 'stdout.log'),$guard.Stdout,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $runRoot 'stderr.log'),$guard.Stderr,[Text.UTF8Encoding]::new($false))
$lines=@($guard.Stdout -split '\r?\n')
$isolationLine=@($lines | Where-Object {$_ -like 'LOCAL_SUITE_ISOLATION *'})
$isolation=if($isolationLine.Count) {$isolationLine[0].Substring('LOCAL_SUITE_ISOLATION '.Length) | ConvertFrom-Json} else {[pscustomobject]@{isolated=$false}}
if($prep.candidate -eq 'natural-save-identity') {
 $prefix=if($prep.suite -eq 'tests/t03_natural_write_result/test_save_file.gd') {'NATURAL_WRITE_RESULT '} else {'NATURAL_COAST_BASIC '}
 $suiteLines=@($lines | Where-Object {$_.StartsWith($prefix)})
 $suiteResult=if($suiteLines.Count) {$suiteLines[0].Substring($prefix.Length) | ConvertFrom-Json} else {[pscustomobject]@{ok=$false;checks=0;status='not_executed';failures=@('No suite completion result; see original stderr')}}
} else {
 $suiteResult=@($lines | Where-Object {$_ -like '{*"fault_scope"*'})[0] | ConvertFrom-Json
}
$suiteResult | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $runRoot 'SUITE_RESULT.json') -Encoding utf8
$t03=@($lines | Where-Object {$_ -like 'T03_EXECUTED *'} | ForEach-Object {$_.Substring('T03_EXECUTED '.Length) | ConvertFrom-Json})
$t03 | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runRoot 'T03_EXECUTED.json') -Encoding utf8
$before=Get-Content -LiteralPath (Join-Path $runRoot 'SOURCE_MAP.json') -Raw | ConvertFrom-Json
$after=@($before | ForEach-Object {$a=Get-TaskHash (Join-Path $prep.project $_.path); [ordered]@{path=$_.path;before_sha256=$_.copy_sha256;after_sha256=$a;matches=$_.copy_sha256 -eq $a}})
$after | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runRoot 'SOURCE_POSTRUN.json') -Encoding utf8
$diagnostics=@(($guard.Stdout+"`n"+$guard.Stderr) -split '\r?\n' | Where-Object {$_ -match '(?i)(?:\bERROR:|\bWARNING:|\bSCRIPT ERROR|^\s*FAIL[: ])'})
$strict=$guard.Status -eq 'completed' -and $guard.RootExitCode -eq 0 -and $guard.GuardExitCode -eq 0 -and $hostExit.host_exit_code -eq 0 -and $guard.JobEmptyAfterRun -and $guard.OutputReadersFinished -and $guard.AllRecordedHandlesExited -and $hostExited -and $isolation.isolated -and -not $guard.SyntheticFault -and -not $guard.OutputLimitExceeded -and $diagnostics.Count -eq 0 -and @($after | Where-Object {-not $_.matches}).Count -eq 0
if($prep.candidate -eq 'natural-save-identity') {$strict=$strict -and $suiteResult.ok -and $suiteResult.owned_pid -eq $guard.RootPid -and $suiteResult.script_sha256 -eq $prep.entry_sha256}
else {$strict=$strict -and $suiteResult.status -eq 'passed' -and $suiteResult.cases.Count -eq 10 -and @($suiteResult.cases | Where-Object {-not $_.passed}).Count -eq 0}
if($prep.suite -like '*test_adapter.gd') {$strict=$strict -and $t03.Count -eq 13 -and @($t03 | Where-Object {-not $_.passed}).Count -eq 0}
if($prep.suite -like '*test_compile.gd') {$strict=$strict -and $suiteResult.checks -eq 4}
if($prep.suite -like '*test_adapter.gd') {$strict=$strict -and $suiteResult.checks -eq 170}
if($prep.suite -eq 'tests/t03_natural_write_result/test_save_file.gd') {$strict=$strict -and $suiteResult.cases.Count -eq 5 -and @($suiteResult.cases | Where-Object {-not $_.passed}).Count -eq 0}
$policy=@($after | Where-Object path -eq 'core/ai_gm_rebuilt/traversal_policy.gd')[0]
$result=[ordered]@{run=$RunName;candidate=$prep.candidate;suite=$prep.suite;recipe=$prep.recipe;strict_pass=$strict;checks=$suiteResult.checks;assertions=$suiteResult.assertions;cases=$suiteResult.cases.Count;t03_executed=$t03.Count;guard_pid=$guardHost.host_pid;godot_pid=$guard.RootPid;started_utc=$guard.StartedUtc;ended_utc=$guard.EndedUtc;elapsed_seconds=$guard.ElapsedSeconds;host_exit_code=$hostExit.host_exit_code;guard_exit_code=$guard.GuardExitCode;godot_exit_code=$guard.RootExitCode;diagnostics=$diagnostics;stderr_empty=$guard.Stderr -eq '';job_empty=$guard.JobEmptyAfterRun;readers_finished=$guard.OutputReadersFinished;recorded_handles_exited=$guard.AllRecordedHandlesExited;host_exited=$hostExited;job_peak_commit_bytes=$guard.PeakJobCommitBytes;job_limit_commit_bytes=$guard.JobCommitLimitBytes;min_physical_available_bytes=$guard.LowestActualAvailPhysBytes;admission=$guard.Admission;physical_peak_rss_measured=$false;output_observed_bytes=$guard.OutputObservedBytes;source_files_rehashed=$after.Count;source_mismatches=@($after | Where-Object {-not $_.matches});policy_restore=$policy;original_suite_sha256=$prep.suite_sha256;inherited_test_entry_sha256=$prep.entry_sha256;guard_result_sha256=Get-TaskHash (Join-Path $runRoot 'GUARD_RESULT.json');source_map_sha256=Get-TaskHash (Join-Path $runRoot 'SOURCE_MAP.json');suite_result_sha256=Get-TaskHash (Join-Path $runRoot 'SUITE_RESULT.json');scope=$prep.scope;no_real_disk_short_write_or_crash_durability_claim=$true}
$result | ConvertTo-Json -Depth 25 | Set-Content -LiteralPath (Join-Path $runRoot 'VERIFIED_RESULT.json') -Encoding utf8
[pscustomobject]$result | Select-Object run,strict_pass,checks,assertions,cases,t03_executed,godot_pid,elapsed_seconds,diagnostics,source_mismatches | ConvertTo-Json -Depth 8
if(-not $strict) {exit 1}
exit 0
