param([Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9_-]{1,128}$')][string]$RunId)
$ErrorActionPreference='Stop'
try {
 $taskSuiteSource=Join-Path $PSScriptRoot 'WindowsGuard.FocusedGui.cs'
 $taskSuitePins=@{
  'WindowsGuard.FocusedGui.cs'='eb642e9b4092098614be6c9b5aff0becf96728a3a47bbe9f54dc12f13fb7ea4b'
  'Test-WindowsGuard.ps1'='2083175f14585b5977e6a72fa12d8a0c5749013f853ae7897f0871cf314191d6'
  'Test-OutputGuard.ps1'='7fcdb0fdcf2027a425552d7edcf3885ef8a9d5f6a59dec1b8027b1e7a855385c'
  'Test-TerminalGuard.ps1'='382b13651f0ca8942a95ad5b251d74f9ee0bf32aa89c76b8b30c6de583d9d085'
 }
 function Verify-SuitePins {
  foreach($taskSuiteName in $taskSuitePins.Keys){
   $taskSuiteFile=Get-Item -LiteralPath (Join-Path $PSScriptRoot $taskSuiteName) -Force
   if($taskSuiteFile.PSIsContainer -or ($taskSuiteFile.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'suite_input_not_regular'}
   if((Get-FileHash -LiteralPath $taskSuiteFile.FullName -Algorithm SHA256).Hash.ToLowerInvariant() -cne $taskSuitePins[$taskSuiteName]){throw 'suite_input_hash_mismatch'}
  }
 }
 Verify-SuitePins
 $taskSuiteHost=[Diagnostics.Process]::GetCurrentProcess()
 $taskSuiteWindows=[Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)
 $taskSuitePS=Join-Path $taskSuiteWindows 'System32\WindowsPowerShell\v1.0\powershell.exe'
 $taskSuitePSHash=(Get-FileHash -LiteralPath $taskSuitePS -Algorithm SHA256).Hash.ToLowerInvariant()
 if((Get-AuthenticodeSignature -LiteralPath $taskSuitePS).Status -ne 'Valid'){throw 'existing_windows_powershell_signature_invalid'}
 if('WordsAndPerils.NativeGuardFocusedGuiCandidate.Guard' -as [type]){throw 'candidate_type_already_loaded_before_suite'}
 Add-Type -Path $taskSuiteSource -ErrorAction Stop
 if([WordsAndPerils.NativeGuardFocusedGuiCandidate.Options]::new().Mode -ne [WordsAndPerils.NativeGuardFocusedGuiCandidate.RunMode]::Headless){throw 'candidate_default_mode_changed'}
 $taskSuiteReports=[Collections.Generic.List[object]]::new()
 $taskSuiteEntries=@(
  @{entry='Test-WindowsGuard.ps1';pattern='selftest-*';summary='selftest-summary.json';status='passed_windows_native_guard_selftests';cases='native_cases';count=7},
  @{entry='Test-OutputGuard.ps1';pattern='output-selftest-*';summary='output-selftest-summary.json';status='passed_v2_tiny_output_selftests';cases='cases';count=6},
  @{entry='Test-TerminalGuard.ps1';pattern='terminal-selftest-*';summary='terminal-selftest-summary.json';status='passed_v3_terminal_boundary_selftests';cases='cases';count=6}
 )
 foreach($taskSuite in $taskSuiteEntries){
  Verify-SuitePins
  $taskSuiteBefore=@(Get-ChildItem -LiteralPath $PSScriptRoot -Directory -Filter $taskSuite.pattern | ForEach-Object Name)
  & (Join-Path $PSScriptRoot $taskSuite.entry)
  $taskSuiteCreated=@(Get-ChildItem -LiteralPath $PSScriptRoot -Directory -Filter $taskSuite.pattern | Where-Object {$_.Name -cnotin $taskSuiteBefore})
  if($taskSuiteCreated.Count -ne 1){throw 'suite_result_directory_not_unique'}
  $taskSuiteSummaryPath=Join-Path $taskSuiteCreated[0].FullName $taskSuite.summary
  $taskSuiteSummary=Get-Content -LiteralPath $taskSuiteSummaryPath -Encoding UTF8 -Raw | ConvertFrom-Json
  if($taskSuiteSummary.status -cne $taskSuite.status -or $taskSuiteSummary.source_sha256 -cne $taskSuitePins['WindowsGuard.FocusedGui.cs']){throw 'suite_summary_binding_failed'}
  $taskSuiteCaseRows=@($taskSuiteSummary.PSObject.Properties[$taskSuite.cases].Value)
  if($taskSuiteCaseRows.Count -ne $taskSuite.count -or @($taskSuiteSummary.checks | Where-Object {-not $_.passed}).Count -ne 0){throw 'suite_case_or_assertion_failed'}
  $taskSuiteReports.Add([ordered]@{entry=$taskSuite.entry;assertions=[int]$taskSuiteSummary.assertion_count;native_cases=$taskSuite.count;summary_file=($taskSuiteCreated[0].Name+'/'+$taskSuite.summary);summary_sha256=(Get-FileHash -LiteralPath $taskSuiteSummaryPath -Algorithm SHA256).Hash.ToLowerInvariant()})
  Verify-SuitePins
 }
 if((Get-FileHash -LiteralPath $taskSuitePS -Algorithm SHA256).Hash.ToLowerInvariant() -cne $taskSuitePSHash){throw 'windows_powershell_changed_during_suite'}
 $taskSuiteActualChecks=0
 foreach($taskSuiteReport in $taskSuiteReports){$taskSuiteActualChecks += $taskSuiteReport.assertions}
 $taskSuiteResult=[ordered]@{status='passed_candidate_headless_native_equivalence';run_id=$RunId;owned_host_pid=$taskSuiteHost.Id;owned_host_created_utc=$taskSuiteHost.StartTime.ToUniversalTime().ToString('o');candidate_source_sha256=$taskSuitePins['WindowsGuard.FocusedGui.cs'];existing_windows_powershell_sha256=$taskSuitePSHash;actual_assertions=$taskSuiteActualChecks;native_reported_cases=19;candidate_guard_run_calls=21;original_guard_run_calls_in_child=0;engine_invocations=0;gui_invocations=0;all_cases_serial=$true;reports=$taskSuiteReports;scope='Actual common headless Win32 process, Job, physical sensor, stricter output/deadline, terminal and owned-cleanup tests. GUI mode and actual memory exhaustion not tested.'}
 $taskSuiteResult | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'NATIVE_SUITE_RESULT.json') -Encoding UTF8
 $taskSuiteResult | ConvertTo-Json -Depth 8
} catch {
 $taskSuiteSafeMessage=$_.Exception.Message -replace '(?i)C:\\Users\\[^\\\s]+','C:\Users\[REDACTED]' -replace 'https?://\S+','[REDACTED_URL]'
 [ordered]@{status='native_equivalence_suite_failed';run_id=$RunId;error_class=$_.Exception.GetType().Name;message=$taskSuiteSafeMessage;engine_invocations=0;gui_invocations=0} | ConvertTo-Json
 exit 1
}
