$ErrorActionPreference='Stop'
try {
 $taskSource=Join-Path $PSScriptRoot 'WindowsGuard.cs'
 $taskHash=(Get-FileHash -LiteralPath $taskSource).Hash.ToLowerInvariant()
 Add-Type -Path $taskSource -ErrorAction Stop
 $taskOut=Join-Path $PSScriptRoot ('terminal-selftest-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,6))
 $null=New-Item -ItemType Directory -Path $taskOut
 $taskChecks=[Collections.Generic.List[object]]::new()
 function Check([bool]$Okay,[string]$Label){$taskChecks.Add([ordered]@{label=$Label;passed=$Okay});if(-not $Okay){throw ('Terminal guard check failed: '+$Label)}}
 $taskWindows=[Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)
 $taskPS=Join-Path $taskWindows 'System32\WindowsPowerShell\v1.0\powershell.exe'
 $taskCases=@(
  @{name='terminal_unreadable';fault='terminal_unreadable';code='exit 0';timeout=10;status='stopped';exit=125;reason='physical_monitor_unreadable';terminal=$true},
  @{name='terminal_low';fault='terminal_low';code='exit 0';timeout=10;status='stopped';exit=126;reason='physical_reserve_below_512_MiB';terminal=$true},
  @{name='terminal_deadline';fault='terminal_deadline';code='exit 0';timeout=10;status='stopped';exit=124;reason='wall_clock_timeout';terminal=$true},
  @{name='terminal_reader_failure';fault='terminal_reader_failure';code='exit 0';timeout=10;status='failed';exit=131;reason='output_reader_failed';terminal=$true},
  @{name='real_one_second_deadline';fault='none';code='Start-Sleep -Seconds 3';timeout=1;status='stopped';exit=124;reason='wall_clock_timeout'},
  @{name='immediate_exit_output_over';fault='none';code="[Console]::Out.Write(('O'*257));[Console]::Out.Flush();exit 0";timeout=10;status='stopped';exit=128;reason='output_limit_exceeded';output=$true}
 )
 $taskResults=@()
 foreach($taskCase in $taskCases){
  $taskOptions=[WordsAndPerils.NativeGuardV3.Options]::new();$taskOptions.Executable=$taskPS
  $taskOptions.Arguments=[string[]]@('-NoLogo','-NoProfile','-NonInteractive','-Command',$taskCase.code)
  $taskOptions.WorkingDirectory=$taskOut;$taskOptions.IsolatedDataRoot=Join-Path $taskOut ('data-'+$taskCase.name)
  $taskOptions.Profile='small';$taskOptions.TimeoutSeconds=$taskCase.timeout;$taskOptions.OutputLimitBytes=256;$taskOptions.SelfTest=$true;$taskOptions.FaultMode=$taskCase.fault
  $taskResult=[WordsAndPerils.NativeGuardV3.Guard]::Run($taskOptions)
  $taskLog=Join-Path $taskOut ($taskCase.name+'.json')
  $taskResult|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $taskLog -Encoding UTF8
  $taskLast=$taskResult.Samples[-1]
  Check ($taskResult.Started -and $taskResult.WorkloadResumed -and $taskResult.JobAssignedBeforeResume -and $taskResult.PhysicalMemoryWasActuallyRead) ($taskCase.name+' actual native child job and physical reading')
  Check ($taskResult.Status -eq $taskCase.status -and $taskResult.GuardExitCode -eq $taskCase.exit -and $taskResult.StopReason -eq $taskCase.reason) ($taskCase.name+' terminal fault never reported completed')
  Check ($taskResult.SyntheticFault -eq ($taskCase.fault -ne 'none') -and -not $taskResult.EngineStarted) ($taskCase.name+' injection accurately labelled and no Godot')
  Check ($taskResult.OutputReadersFinished -and $taskResult.JobEmptyAfterRun -and $taskResult.AllRecordedHandlesExited -and @($taskResult.OwnedProcesses|Where-Object{-not $_.Exited -or -not $_.JobMembershipVerified}).Count -eq 0) ($taskCase.name+' EOF and owned cleanup completed')
  Check ($taskResult.ElapsedSeconds -lt 2 -and $taskResult.TimeoutSeconds -eq $taskCase.timeout -and $taskResult.Admission.ProfileTimeoutSeconds -eq 120) ($taskCase.name+' short unchanged deadline')
  if($taskCase.terminal){
   Check ($taskLast.TerminalJobAndRootExited -and $taskLast.Injected -and $taskLast.NativeReadSuccess -and $taskResult.RootExitCode -eq 0) ($taskCase.name+' fault and real clean exit coincided in terminal sample')
  }
  if($taskCase.name -eq 'terminal_unreadable'){Check (-not $taskLast.EffectiveReadSuccess) 'terminal unreadable injection differs from successful actual native read'}
  if($taskCase.name -eq 'terminal_low'){Check ($taskLast.EffectiveAvailPhysBytes -eq 536870911 -and $taskLast.ActualAvailPhysBytes -gt 536870912) 'terminal low physical value is injected rather than memory exhaustion'}
  if($taskCase.name -eq 'terminal_deadline'){Check ($taskLast.DeadlineInjected -and $taskLast.DeadlineExceeded) 'terminal deadline is explicitly injected without fabricated elapsed time'}
  if($taskCase.name -eq 'real_one_second_deadline'){Check ($taskLast.DeadlineExceeded -and -not $taskLast.DeadlineInjected -and $taskResult.ElapsedSeconds -ge 1) 'actual one second deadline stopped live child'}
  if($taskCase.output){Check ($taskResult.OutputObservedBytes -eq 257 -and $taskResult.StdoutRetainedBytes -eq 256 -and $taskResult.StderrRetainedBytes -eq 0 -and $taskResult.OutputLimitTerminationRequested -and $taskResult.OutputLimitTerminationSucceeded) 'real immediate exit output overflow wins over success'}
  $taskResults+=[ordered]@{name=$taskCase.name;status=$taskResult.Status;stop_reason=$taskResult.StopReason;guard_exit_code=$taskResult.GuardExitCode;root_exit_code=$taskResult.RootExitCode;started_utc=$taskResult.StartedUtc;ended_utc=$taskResult.EndedUtc;elapsed_seconds=$taskResult.ElapsedSeconds;synthetic_fault=$taskResult.SyntheticFault;terminal_sample=$taskLast;readers_finished=$taskResult.OutputReadersFinished;owned_count=$taskResult.OwnedProcesses.Count;job_empty=$taskResult.JobEmptyAfterRun;all_owned_exited=$taskResult.AllRecordedHandlesExited;observed_output_bytes=$taskResult.OutputObservedBytes;retained_output_bytes=($taskResult.StdoutRetainedBytes+$taskResult.StderrRetainedBytes);log_sha256=(Get-FileHash -LiteralPath $taskLog).Hash.ToLowerInvariant()}
  [ordered]@{case=$taskCase.name;status=$taskResult.Status;guard_exit_code=$taskResult.GuardExitCode;root_exit_code=$taskResult.RootExitCode;terminal_sample=$taskLast.TerminalJobAndRootExited;injected=$taskResult.SyntheticFault;readers_finished=$taskResult.OutputReadersFinished;owned_count=$taskResult.OwnedProcesses.Count;elapsed_seconds=$taskResult.ElapsedSeconds}|ConvertTo-Json -Compress
 }
 Check ((Get-FileHash -LiteralPath $taskSource).Hash.ToLowerInvariant() -eq $taskHash) 'v3 source unchanged during terminal tests'
 $taskSummary=[ordered]@{status='passed_v3_terminal_boundary_selftests';source_sha256=$taskHash;assertion_count=$taskChecks.Count;checks=$taskChecks;cases=$taskResults;production_output_limit_bytes=65536;test_output_limit_bytes=256;profile_deadline_seconds=120;fault_priority=@('output limit','reader failure','physical sensor','physical reserve or budget','job commit limit','deadline','selftest close','completed');engine_started=$false;memory_stress=$false;closed_utc=[DateTime]::UtcNow.ToString('o')}
 $taskSummary|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $taskOut 'terminal-selftest-summary.json') -Encoding UTF8
 [ordered]@{status=$taskSummary.status;assertion_count=$taskChecks.Count;source_sha256=$taskHash;summary_path=(Join-Path $taskOut 'terminal-selftest-summary.json');summary_sha256=(Get-FileHash -LiteralPath (Join-Path $taskOut 'terminal-selftest-summary.json')).Hash.ToLowerInvariant();engine_started=$false}|ConvertTo-Json
}catch{
 $taskMessage=$_.Exception.Message -replace '(?i)C:\\Users\\[^\\\s]+','C:\Users\[REDACTED]' -replace 'https?://\S+','[REDACTED_URL]'
 $taskFailure=[ordered]@{status='v3_terminal_selftest_failed';error_class=$_.Exception.GetType().Name;message=$taskMessage;checks_completed=if($taskChecks){$taskChecks.Count}else{0};engine_started=$false}
 if($taskOut -and (Test-Path -LiteralPath $taskOut)){$taskFailure|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskOut 'terminal-selftest-failure.json') -Encoding UTF8}
 $taskFailure|ConvertTo-Json
 exit 1
}
