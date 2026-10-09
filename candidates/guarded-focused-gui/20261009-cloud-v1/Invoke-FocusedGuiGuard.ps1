[CmdletBinding(DefaultParameterSetName='Headless')]
param(
 [Parameter(Mandatory=$true,ParameterSetName='Headless')][string]$SpecPath,
 [Parameter(Mandatory=$true,ParameterSetName='FocusedGui')][string]$OwnerGuiSpecPath,
 [Parameter(Mandatory=$true,ParameterSetName='FocusedGui')][switch]$FocusedGui,
 [Parameter(Mandatory=$true,ParameterSetName='FocusedGui')][ValidatePattern('^[a-f0-9]{64}$')][string]$OwnerGodotSha256,
 [Parameter(Mandatory=$true,ParameterSetName='FocusedGui')][ValidatePattern('^[A-Za-z0-9_-]{1,128}$')][string]$OwnerRunId
)
$ErrorActionPreference='Stop'
try {
 if(-not ('WordsAndPerils.NativeGuardFocusedGuiCandidate.Guard' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'WindowsGuard.FocusedGui.cs') -ErrorAction Stop}
 $gui=$PSCmdlet.ParameterSetName -eq 'FocusedGui'
 if($gui -and -not $FocusedGui){throw 'explicit_owner_focused_gui_switch_required'}
 $inputSpec=if($gui){$OwnerGuiSpecPath}else{$SpecPath}
 $taskSpec=Get-Content -LiteralPath $inputSpec -Encoding UTF8 -Raw|ConvertFrom-Json
 if($gui){
  $allowed=@('executable','arguments','working_directory','isolated_data_root','profile','timeout_seconds','log_path')
  $names=@($taskSpec.PSObject.Properties.Name)
  if($names.Count -ne $allowed.Count -or @($names|Where-Object {$_ -cnotin $allowed}).Count -ne 0){throw 'owner_gui_spec_fields_not_exact'}
  # Logging may write only this fresh run's standard result; no arbitrary output path.
  $dataFull=[IO.Path]::GetFullPath([string]$taskSpec.isolated_data_root)
  $expectedLog=Join-Path ([IO.Path]::GetDirectoryName($dataFull)) 'GUARD_RESULT.json'
  if(-not [string]::Equals([string]$taskSpec.log_path,$expectedLog,[StringComparison]::OrdinalIgnoreCase)){throw 'owner_gui_log_must_be_owned_run_result'}
  if(Test-Path -LiteralPath $expectedLog){throw 'owner_gui_result_already_exists'}
 }
 $taskOptions=[WordsAndPerils.NativeGuardFocusedGuiCandidate.Options]::new()
 $taskOptions.Executable=$taskSpec.executable
 $taskOptions.Arguments=[string[]]@($taskSpec.arguments)
 $taskOptions.WorkingDirectory=$taskSpec.working_directory
 $taskOptions.IsolatedDataRoot=$taskSpec.isolated_data_root
 $taskOptions.Profile=$taskSpec.profile
 if($taskSpec.timeout_seconds){$taskOptions.TimeoutSeconds=[int]$taskSpec.timeout_seconds}
 if($gui){
  $taskOptions.Mode=[WordsAndPerils.NativeGuardFocusedGuiCandidate.RunMode]::FocusedGui
  $taskOptions.OwnerGui=[WordsAndPerils.NativeGuardFocusedGuiCandidate.OwnerFocusedGui]::new()
  $taskOptions.OwnerGui.RunId=$OwnerRunId
  # This pin is explicit local-owner invocation input, never read from a ready/SPEC file.
  $taskOptions.OwnerGui.ExpectedGodotSha256=$OwnerGodotSha256
 }
 $taskResult=[WordsAndPerils.NativeGuardFocusedGuiCandidate.Guard]::Run($taskOptions)
 $taskResult|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $taskSpec.log_path -Encoding UTF8
 [ordered]@{status=$taskResult.Status;started=$taskResult.Started;root_pid=$taskResult.RootPid;guard_exit_code=$taskResult.GuardExitCode;root_exit_code=$taskResult.RootExitCode;stop_reason=$taskResult.StopReason;job_empty=$taskResult.JobEmptyAfterRun;all_recorded_handles_exited=$taskResult.AllRecordedHandlesExited;engine_started=$taskResult.EngineStarted;mode=$taskResult.SelectedMode;owner_run_id=$taskResult.OwnerRunId}|ConvertTo-Json
 exit $taskResult.GuardExitCode
} catch {
 $taskSafeMessage=$_.Exception.Message -replace '(?i)C:\\Users\\[^\\\s]+','C:\Users\[REDACTED]' -replace 'https?://\S+','[REDACTED_URL]'
 [ordered]@{status='guard_wrapper_failed';error_class=$_.Exception.GetType().Name;message=$taskSafeMessage}|ConvertTo-Json
 exit 3
}
