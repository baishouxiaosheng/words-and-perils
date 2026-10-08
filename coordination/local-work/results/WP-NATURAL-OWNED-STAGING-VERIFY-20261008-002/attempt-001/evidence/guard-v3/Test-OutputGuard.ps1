$ErrorActionPreference='Stop'
try {
 $taskSource=Join-Path $PSScriptRoot 'WindowsGuard.cs'
 $taskSourceHash=(Get-FileHash -LiteralPath $taskSource).Hash.ToLowerInvariant()
 Add-Type -Path $taskSource -ErrorAction Stop
 $taskOut=Join-Path $PSScriptRoot ('output-selftest-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,6))
 $null=New-Item -ItemType Directory -Path $taskOut
 $taskChecks=[Collections.Generic.List[object]]::new()
 function Check([bool]$Okay,[string]$Label){$taskChecks.Add([ordered]@{label=$Label;passed=$Okay});if(-not $Okay){throw ('Output guard check failed: '+$Label)}}
 $taskWindows=[Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)
 $taskPS=Join-Path $taskWindows 'System32\WindowsPowerShell\v1.0\powershell.exe'
 $taskDescendant='$c=[Diagnostics.ProcessStartInfo]::new();$c.FileName="'+$taskPS+'";$c.Arguments=''-NoLogo -NoProfile -NonInteractive -Command "Start-Sleep -Seconds 30"'';$c.UseShellExecute=$false;$c.CreateNoWindow=$true;$p=[Diagnostics.Process]::Start($c);Start-Sleep -Milliseconds 300;'
 $taskCases=@(
  @{name='exact_stdout';code="[Console]::Out.Write(('O'*256));[Console]::Out.Flush();exit 0";overflow=$false},
  @{name='exact_combined';code="[Console]::Out.Write(('O'*128));[Console]::Out.Flush();[Console]::Error.Write(('E'*128));[Console]::Error.Flush();exit 0";overflow=$false},
  @{name='stdout_one_byte_over';code="[Console]::Out.Write(('O'*257));[Console]::Out.Flush();Start-Sleep -Seconds 30";overflow=$true},
  @{name='stderr_one_byte_over';code="[Console]::Error.Write(('E'*257));[Console]::Error.Flush();Start-Sleep -Seconds 30";overflow=$true},
  @{name='combined_over';code="[Console]::Out.Write(('O'*200));[Console]::Out.Flush();[Console]::Error.Write(('E'*200));[Console]::Error.Flush();Start-Sleep -Seconds 30";overflow=$true},
  @{name='overflow_owned_descendant';code=($taskDescendant+"[Console]::Out.Write(('O'*257));[Console]::Out.Flush();Start-Sleep -Seconds 30");overflow=$true;descendant=$true}
 )
 Check ([WordsAndPerils.NativeGuardV3.Options]::new().OutputLimitBytes -eq 65536 -and [WordsAndPerils.NativeGuardV3.Guard]::MaximumOutputBytes -eq 65536) 'production aggregate output hard maximum is 64 KiB'
 $taskResults=@()
 foreach($taskCase in $taskCases){
  $taskOptions=[WordsAndPerils.NativeGuardV3.Options]::new()
  $taskOptions.Executable=$taskPS
  $taskOptions.Arguments=[string[]]@('-NoLogo','-NoProfile','-NonInteractive','-Command',$taskCase.code)
  $taskOptions.WorkingDirectory=$taskOut
  $taskOptions.IsolatedDataRoot=Join-Path $taskOut ('data-'+$taskCase.name)
  $taskOptions.Profile='small';$taskOptions.TimeoutSeconds=10;$taskOptions.SelfTest=$true;$taskOptions.OutputLimitBytes=256
  $taskResult=[WordsAndPerils.NativeGuardV3.Guard]::Run($taskOptions)
  $taskLog=Join-Path $taskOut ($taskCase.name+'.json')
  $taskResult|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $taskLog -Encoding UTF8
  Check ($taskResult.Started -and $taskResult.WorkloadResumed -and $taskResult.JobAssignedBeforeResume -and $taskResult.PhysicalMemoryWasActuallyRead) ($taskCase.name+' actual native process and job')
  Check (-not $taskResult.SyntheticFault -and -not $taskResult.EngineStarted) ($taskCase.name+' no injected overflow or Godot')
  Check ($taskResult.OutputLimitBytes -eq 256 -and ($taskResult.StdoutRetainedBytes+$taskResult.StderrRetainedBytes) -eq 256) ($taskCase.name+' aggregate raw retained bytes exactly bounded')
  Check ($taskResult.OutputReadersFinished -and $taskResult.JobEmptyAfterRun -and $taskResult.AllRecordedHandlesExited -and @($taskResult.OwnedProcesses|Where-Object{-not $_.Exited -or -not $_.JobMembershipVerified}).Count -eq 0) ($taskCase.name+' both readers finished and all owned processes cleaned')
  Check ($taskResult.ElapsedSeconds -lt 5 -and $taskResult.Stderr.Length+$taskResult.Stdout.Length -eq 256) ($taskCase.name+' bounded decoded output and no timeout or deadlock')
  if($taskCase.overflow){
   Check ($taskResult.Status -eq 'stopped' -and $taskResult.StopReason -eq 'output_limit_exceeded' -and $taskResult.GuardExitCode -eq 128 -and $taskResult.OutputLimitExceeded -and $taskResult.OutputObservedBytes -gt 256) ($taskCase.name+' real tiny output crossed limit')
   Check ($taskResult.OutputLimitTerminationRequested -and $taskResult.OutputLimitTerminationSucceeded -and $taskResult.OutputTerminationNativeError -eq 0) ($taskCase.name+' reader immediately terminated only private job')
  }else{
   Check ($taskResult.Status -eq 'completed' -and $taskResult.GuardExitCode -eq 0 -and $taskResult.RootExitCode -eq 0 -and -not $taskResult.OutputLimitExceeded -and $taskResult.OutputObservedBytes -eq 256) ($taskCase.name+' exact limit completes normally')
  }
  if($taskCase.descendant){Check ($taskResult.OwnedProcesses.Count -ge 3) 'tiny output overflow cleans observed owned descendant too'}
  $taskResults+=[ordered]@{name=$taskCase.name;status=$taskResult.Status;stop_reason=$taskResult.StopReason;guard_exit_code=$taskResult.GuardExitCode;started_utc=$taskResult.StartedUtc;ended_utc=$taskResult.EndedUtc;elapsed_seconds=$taskResult.ElapsedSeconds;output_limit_bytes=$taskResult.OutputLimitBytes;observed_bytes=$taskResult.OutputObservedBytes;stdout_retained_bytes=$taskResult.StdoutRetainedBytes;stderr_retained_bytes=$taskResult.StderrRetainedBytes;readers_finished=$taskResult.OutputReadersFinished;owned_count=$taskResult.OwnedProcesses.Count;all_owned_exited=$taskResult.AllRecordedHandlesExited;job_empty=$taskResult.JobEmptyAfterRun;log_sha256=(Get-FileHash -LiteralPath $taskLog).Hash.ToLowerInvariant()}
  [ordered]@{case=$taskCase.name;status=$taskResult.Status;retained=($taskResult.StdoutRetainedBytes+$taskResult.StderrRetainedBytes);observed=$taskResult.OutputObservedBytes;readers_finished=$taskResult.OutputReadersFinished;owned_count=$taskResult.OwnedProcesses.Count;elapsed_seconds=$taskResult.ElapsedSeconds}|ConvertTo-Json -Compress
 }
 foreach($taskLimit in @(0,65537)){
  $taskInvalid=[WordsAndPerils.NativeGuardV3.Options]::new();$taskInvalid.OutputLimitBytes=$taskLimit;$taskInvalid.SelfTest=$true
  $taskRejected=[WordsAndPerils.NativeGuardV3.Guard]::Run($taskInvalid)
  Check ($taskRejected.Status -eq 'failed' -and -not $taskRejected.Started -and $taskRejected.GuardExitCode -eq 3) ('invalid output limit rejected before creation: '+$taskLimit)
 }
 Check ((Get-FileHash -LiteralPath $taskSource).Hash.ToLowerInvariant() -eq $taskSourceHash) 'v2 source unchanged during tiny output selftests'
 $taskSummary=[ordered]@{status='passed_v2_tiny_output_selftests';source_sha256=$taskSourceHash;assertion_count=$taskChecks.Count;checks=$taskChecks;cases=$taskResults;test_limit_bytes=256;production_aggregate_output_limit_bytes=65536;maximum_generated_output_bytes_per_case=400;engine_started=$false;memory_stress=$false;all_cases_serial=$true;closed_utc=[DateTime]::UtcNow.ToString('o')}
 $taskSummary|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $taskOut 'output-selftest-summary.json') -Encoding UTF8
 [ordered]@{status=$taskSummary.status;assertion_count=$taskChecks.Count;summary_path=(Join-Path $taskOut 'output-selftest-summary.json');summary_sha256=(Get-FileHash -LiteralPath (Join-Path $taskOut 'output-selftest-summary.json')).Hash.ToLowerInvariant();source_sha256=$taskSourceHash;engine_started=$false}|ConvertTo-Json
}catch{
 $taskMessage=$_.Exception.Message -replace '(?i)C:\\Users\\[^\\\s]+','C:\Users\[REDACTED]' -replace 'https?://\S+','[REDACTED_URL]'
 $taskFailure=[ordered]@{status='v2_output_selftest_failed';error_class=$_.Exception.GetType().Name;message=$taskMessage;checks_completed=if($taskChecks){$taskChecks.Count}else{0};engine_started=$false}
 if($taskOut -and (Test-Path -LiteralPath $taskOut)){$taskFailure|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskOut 'output-selftest-failure.json') -Encoding UTF8}
 $taskFailure|ConvertTo-Json
 exit 1
}
