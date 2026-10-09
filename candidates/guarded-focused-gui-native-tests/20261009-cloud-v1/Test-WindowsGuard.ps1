$ErrorActionPreference='Stop'
try {
 $taskSource=Join-Path $PSScriptRoot 'WindowsGuard.FocusedGui.cs'
 $taskSourceHash=(Get-FileHash -LiteralPath $taskSource -Algorithm SHA256).Hash.ToLowerInvariant()
 # Candidate type compiled once by the fixed outer suite entry.
 $taskOut=Join-Path $PSScriptRoot ('selftest-'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,6))
 $null=New-Item -ItemType Directory -Path $taskOut
 $taskChecks=[Collections.Generic.List[object]]::new()
 function Check([bool]$Okay,[string]$Label){$taskChecks.Add([ordered]@{label=$Label;passed=$Okay});if(-not $Okay){throw ('Guard check failed: '+$Label)}}
 $taskMiB=[uint64](1024*1024)
 $taskLogic=@(
  @{label='other applications using over 8 GiB do not consume task budget';total=32768;avail=15360;profile='small';allow=$true;reason='admitted';budget=8192},
  @{label='small exact physical admission boundary';total=32768;avail=1536;profile='small';allow=$true;reason='admitted';budget=8192},
  @{label='small one byte below admission';total=32768;avail=1536;minus=1;profile='small';allow=$false;reason='physical_admission_insufficient';budget=8192},
  @{label='full exact physical admission boundary';total=32768;avail=2253;profile='full';allow=$true;reason='admitted';budget=8192},
  @{label='full one byte below admission';total=32768;avail=2253;minus=1;profile='full';allow=$false;reason='physical_admission_insufficient';budget=8192},
  @{label='total physical below 8 GiB controls budget';total=4096;avail=3000;profile='full';allow=$true;reason='admitted';budget=4096},
  @{label='total physical budget too small';total=1024;avail=1024;profile='small';allow=$false;reason='task_budget_insufficient';budget=1024},
  @{label='unreadable physical memory rejects';total=32768;avail=16000;readable=$false;profile='small';allow=$false;reason='physical_sensor_unreadable_or_invalid';budget=8192},
  @{label='invalid available greater than physical total rejects';total=4096;avail=4097;profile='small';allow=$false;reason='physical_sensor_unreadable_or_invalid';budget=4096},
  @{label='zero physical total rejects';total=0;avail=0;profile='small';allow=$false;reason='physical_sensor_unreadable_or_invalid';budget=0},
  @{label='unknown profile rejects';total=32768;avail=16000;profile='unexpected';allow=$false;reason='unknown_profile';budget=8192}
 )
 $taskLogicResults=@()
 foreach($taskCase in $taskLogic){
  $taskReadable=if($taskCase.ContainsKey('readable')){[bool]$taskCase.readable}else{$true}
  $taskAvailable=[uint64]$taskCase.avail*$taskMiB;if($taskCase.minus){$taskAvailable--}
  $taskAdmission=[WordsAndPerils.NativeGuardFocusedGuiCandidate.Guard]::Evaluate($taskReadable,([uint64]$taskCase.total*$taskMiB),$taskAvailable,$taskCase.profile)
  Check ($taskAdmission.Allowed -eq $taskCase.allow -and $taskAdmission.Reason -eq $taskCase.reason -and $taskAdmission.BudgetBytes -eq [uint64]$taskCase.budget*$taskMiB) $taskCase.label
  $taskLogicResults+=[ordered]@{label=$taskCase.label;source='synthetic_boundary_values_no_process';result=$taskAdmission}
 }
 $taskSmall=[WordsAndPerils.NativeGuardFocusedGuiCandidate.Guard]::Evaluate($true,32768*$taskMiB,16000*$taskMiB,'small')
 $taskFull=[WordsAndPerils.NativeGuardFocusedGuiCandidate.Guard]::Evaluate($true,32768*$taskMiB,16000*$taskMiB,'full')
 Check ($taskSmall.AdditionalBytes -eq 1024*$taskMiB -and $taskSmall.ReserveBytes -eq 512*$taskMiB -and $taskSmall.ProfileTimeoutSeconds -eq 120) 'small profile exact bytes and deadline'
 Check ($taskFull.AdditionalBytes -eq 1741*$taskMiB -and $taskFull.ReserveBytes -eq 512*$taskMiB -and $taskFull.ProfileTimeoutSeconds -eq 180) 'full profile exact bytes and deadline'
 $taskPreparedEnv=[WordsAndPerils.NativeGuardFocusedGuiCandidate.Guard]::ChildEnvironment((Join-Path $taskOut 'future-godot-data'))
 Check ($taskPreparedEnv['APPDATA'] -like ($taskOut+'*') -and $taskPreparedEnv['LOCALAPPDATA'] -like ($taskOut+'*') -and $taskPreparedEnv.Count -eq 8) 'minimal child-only environment prepared without host environment enumeration'
 $taskLogicResults|ConvertTo-Json -Depth 9|Set-Content -LiteralPath (Join-Path $taskOut 'logic-boundaries.json') -Encoding UTF8
 [ordered]@{phase='pure_logic_boundaries_passed';checks=$taskChecks.Count;next='serial_native_os_program_selftests'}|ConvertTo-Json -Compress
 $taskWindows=[Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)
 $taskPS=Join-Path $taskWindows 'System32\WindowsPowerShell\v1.0\powershell.exe'
 if(-not (Test-Path -LiteralPath $taskPS -PathType Leaf)){throw 'Existing Windows PowerShell unavailable'}
 $taskChildCode='$c=[Diagnostics.ProcessStartInfo]::new();$c.FileName="'+$taskPS+'";$c.Arguments=''-NoLogo -NoProfile -NonInteractive -Command "Start-Sleep -Seconds 30"'';$c.UseShellExecute=$false;$c.CreateNoWindow=$true;$p=[Diagnostics.Process]::Start($c);Write-Output ("OWNED_CHILD="+$p.Id);Start-Sleep -Seconds 30'
 $taskNativeCases=@(
  @{name='normal_exit';fault='none';code='Write-Output GUARD_NATIVE_CHILD_OK; exit 0';timeout=10;status='completed';exit=0},
  @{name='admission_unreadable_injection';fault='admission_unreadable';code='exit 0';timeout=10;status='refused';exit=2},
  @{name='admission_low_injection';fault='admission_low';code='exit 0';timeout=10;status='refused';exit=2},
  @{name='monitor_unreadable_injection';fault='monitor_unreadable';code='Start-Sleep -Seconds 30';timeout=10;status='stopped';exit=125},
  @{name='monitor_low_injection';fault='monitor_low';code='Start-Sleep -Seconds 30';timeout=10;status='stopped';exit=126},
  @{name='timeout_with_owned_descendant';fault='none';code=$taskChildCode;timeout=6;status='stopped';exit=124;descendant=$true},
  @{name='kill_on_job_close';fault='cleanup_close_job';code='Start-Sleep -Seconds 30';timeout=10;status='stopped';exit=127}
 )
 $taskActualResults=@()
 foreach($taskCase in $taskNativeCases){
  $taskOpts=[WordsAndPerils.NativeGuardFocusedGuiCandidate.Options]::new();$taskOpts.Executable=$taskPS
  $taskOpts.Arguments=[string[]]@('-NoLogo','-NoProfile','-NonInteractive','-Command',$taskCase.code)
  $taskOpts.WorkingDirectory=$taskOut;$taskOpts.IsolatedDataRoot=Join-Path $taskOut ('data-'+$taskCase.name)
  $taskOpts.Profile='small';$taskOpts.TimeoutSeconds=$taskCase.timeout;$taskOpts.SelfTest=$true;$taskOpts.FaultMode=$taskCase.fault
  $taskResult=[WordsAndPerils.NativeGuardFocusedGuiCandidate.Guard]::Run($taskOpts)
  $taskCaseLog=Join-Path $taskOut ($taskCase.name+'.json')
  $taskResult|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $taskCaseLog -Encoding UTF8
  Check ($taskResult.Status -eq $taskCase.status -and $taskResult.GuardExitCode -eq $taskCase.exit) ($taskCase.name+' expected actual status')
  Check ($taskResult.PhysicalMemoryWasActuallyRead -and $taskResult.AdmissionNativeReading.Success) ($taskCase.name+' real Win32 physical sensor read')
  Check ($taskResult.ElapsedSeconds -le 120 -and -not $taskResult.EngineStarted) ($taskCase.name+' scope and per-case deadline')
  if($taskResult.Started){
   Check ($taskResult.JobAssignedBeforeResume -and $taskResult.KillOnCloseVerified -and $taskResult.BreakawayDisabledVerified -and $taskResult.PriorityClassBeforeResume -eq 0x4000 -and $taskResult.QueriedJobCommitLimitBytes -eq 1024*$taskMiB) ($taskCase.name+' actual kernel job limit and ownership readback')
   Check ($taskResult.JobEmptyAfterRun -and $taskResult.AllRecordedHandlesExited -and @($taskResult.OwnedProcesses|Where-Object{-not $_.Exited -or -not $_.JobMembershipVerified}).Count -eq 0) ($taskCase.name+' all owned handles exited and job empty')
  }else{Check ($taskResult.OwnedProcesses.Count -eq 0 -and -not $taskResult.WorkloadResumed) ($taskCase.name+' admission refused before process creation')}
  if($taskCase.name -eq 'normal_exit'){Check ($taskResult.RootExitCode -eq 0 -and $taskResult.Stdout.Contains('GUARD_NATIVE_CHILD_OK') -and $taskResult.Stderr.Length -eq 0 -and $taskResult.PeakJobCommitBytes -gt 0) 'normal exit output and real job peak observed'}
  if($taskCase.descendant){Check ($taskResult.OwnedProcesses.Count -ge 2 -and $taskResult.Stdout.Contains('OWNED_CHILD=')) 'real descendant inherited private job and was cleaned'}
  $taskActualResults+=[ordered]@{name=$taskCase.name;fault_injection=$taskResult.SyntheticFault;status=$taskResult.Status;guard_exit_code=$taskResult.GuardExitCode;root_pid=$taskResult.RootPid;owned_pids=@($taskResult.OwnedProcesses|ForEach-Object Pid);elapsed_seconds=$taskResult.ElapsedSeconds;peak_job_commit_MiB=[math]::Round($taskResult.PeakJobCommitBytes/$taskMiB,3);minimum_actual_available_MiB=if($taskResult.LowestActualAvailPhysBytes){[math]::Round($taskResult.LowestActualAvailPhysBytes/$taskMiB,3)}else{$null};log_path=$taskCaseLog;log_sha256=(Get-FileHash -LiteralPath $taskCaseLog).Hash.ToLowerInvariant()}
  [ordered]@{case=$taskCase.name;status=$taskResult.Status;pid=$taskResult.RootPid;owned_count=$taskResult.OwnedProcesses.Count;elapsed_seconds=$taskResult.ElapsedSeconds}|ConvertTo-Json -Compress
 }
 Check ((Get-FileHash -LiteralPath $taskSource).Hash.ToLowerInvariant() -eq $taskSourceHash) 'guard source unchanged during selftests'
 $taskSummary=[ordered]@{status='passed_windows_native_guard_selftests';source_path=$taskSource;source_sha256=$taskSourceHash;logic_cases=$taskLogicResults.Count;assertion_count=$taskChecks.Count;checks=$taskChecks;native_cases=$taskActualResults;selftest_output_directory=$taskOut;real_native_mechanisms=@('GlobalMemoryStatusEx TotalPhys and AvailPhys','private Job Object commit cap/readback','create suspended and assign before resume','root and descendant job membership/creation-time handles','BelowNormal and two allowed CPU bits','timeout termination of private job','kill-on-close','owned handle cleanup');mock_scope=@('logical boundary inputs','admission unreadable/low values','runtime unreadable/low values');not_tested=@('actual memory exhaustion','Godot','actual user:// resolution','complete candidate materialization','hard memory allocation refusal stress');budget_definition='min(real TotalPhys,8192 MiB)';reserve_MiB=512;small=@{additional_MiB=1024;maximum_seconds=120};full=@{additional_MiB=1741;maximum_seconds=180};sampling_interval_ms=100;all_native_cases_serial=$true;all_observed_job_processes_exited=$true;engine_started=$false;system_settings_changed=$false;closed_utc=[DateTime]::UtcNow.ToString('o')}
 $taskSummary|ConvertTo-Json -Depth 14|Set-Content -LiteralPath (Join-Path $taskOut 'selftest-summary.json') -Encoding UTF8
 [ordered]@{status=$taskSummary.status;logic_cases=$taskSummary.logic_cases;native_cases=$taskActualResults.Count;assertion_count=$taskChecks.Count;source_sha256=$taskSourceHash;summary_path=(Join-Path $taskOut 'selftest-summary.json');summary_sha256=(Get-FileHash -LiteralPath (Join-Path $taskOut 'selftest-summary.json')).Hash.ToLowerInvariant();engine_started=$false;all_observed_job_processes_exited=$true}|ConvertTo-Json
}catch{
 $taskMessage=$_.Exception.Message -replace '(?i)C:\\Users\\[^\\\s]+','C:\Users\[REDACTED]' -replace 'https?://\S+','[REDACTED_URL]'
 $taskFailure=[ordered]@{status='guard_selftest_failed';error_class=$_.Exception.GetType().Name;message=$taskMessage;checks_completed=if($taskChecks){$taskChecks.Count}else{0};engine_started=$false}
 if($taskOut -and (Test-Path -LiteralPath $taskOut)){$taskFailure|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskOut 'selftest-failure.json') -Encoding UTF8}
 $taskFailure|ConvertTo-Json
 exit 1
}
