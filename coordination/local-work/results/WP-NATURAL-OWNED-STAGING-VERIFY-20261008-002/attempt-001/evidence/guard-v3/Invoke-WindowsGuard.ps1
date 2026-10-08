param([Parameter(Mandatory=$true)][string]$SpecPath)
$ErrorActionPreference='Stop'
try {
 if(-not ('WordsAndPerils.NativeGuardV3.Guard' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'WindowsGuard.cs') -ErrorAction Stop}
 $taskSpec=Get-Content -LiteralPath $SpecPath -Encoding UTF8 -Raw|ConvertFrom-Json
 $taskOptions=[WordsAndPerils.NativeGuardV3.Options]::new()
 $taskOptions.Executable=$taskSpec.executable
 $taskOptions.Arguments=[string[]]@($taskSpec.arguments)
 $taskOptions.WorkingDirectory=$taskSpec.working_directory
 $taskOptions.IsolatedDataRoot=$taskSpec.isolated_data_root
 $taskOptions.Profile=$taskSpec.profile
 if($taskSpec.timeout_seconds){$taskOptions.TimeoutSeconds=[int]$taskSpec.timeout_seconds}
 $taskResult=[WordsAndPerils.NativeGuardV3.Guard]::Run($taskOptions)
 $taskResult|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $taskSpec.log_path -Encoding UTF8
 [ordered]@{status=$taskResult.Status;started=$taskResult.Started;root_pid=$taskResult.RootPid;guard_exit_code=$taskResult.GuardExitCode;root_exit_code=$taskResult.RootExitCode;stop_reason=$taskResult.StopReason;job_empty=$taskResult.JobEmptyAfterRun;all_recorded_handles_exited=$taskResult.AllRecordedHandlesExited;engine_started=$taskResult.EngineStarted}|ConvertTo-Json
 exit $taskResult.GuardExitCode
} catch {
 $taskSafeMessage=$_.Exception.Message -replace '(?i)C:\\Users\\[^\\\s]+','C:\Users\[REDACTED]' -replace 'https?://\S+','[REDACTED_URL]'
 [ordered]@{status='guard_wrapper_failed';error_class=$_.Exception.GetType().Name;message=$taskSafeMessage}|ConvertTo-Json
 exit 3
}
