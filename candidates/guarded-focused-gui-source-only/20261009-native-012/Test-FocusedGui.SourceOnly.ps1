# Compile and invoke managed validation only. Never calls Guard.Run or any engine.
$ErrorActionPreference='Stop'
Add-Type -Path (Join-Path $PSScriptRoot 'WindowsGuard.FocusedGui.cs') -ErrorAction Stop
Add-Type -Path (Join-Path $PSScriptRoot 'baseline/WindowsGuard.cs') -ErrorAction Stop
$checks=0
function Assert-Check([bool]$ok,[string]$name){if(-not $ok){throw "FAILED: $name"};$script:checks++}
function Assert-Rejected([scriptblock]$action,[string]$message){
 $rejected=$false
 try{& $action}catch{if($_.Exception.ToString().Contains($message)){$rejected=$true}else{throw}}
 Assert-Check $rejected $message
}
$candidate=[WordsAndPerils.NativeGuardFocusedGuiCandidate.Options]::new()
Assert-Check ($candidate.Mode -eq [WordsAndPerils.NativeGuardFocusedGuiCandidate.RunMode]::Headless) 'default_headless'
Assert-Check ([WordsAndPerils.NativeGuardFocusedGuiCandidate.Guard]::CreationFlags($candidate.Mode) -eq (0x4 -bor 0x08000000 -bor 0x400 -bor 0x80000 -bor 0x4000)) 'original_headless_flags'
Assert-Check ([WordsAndPerils.NativeGuardFocusedGuiCandidate.Guard]::ShowWindow($candidate.Mode) -eq 0) 'original_headless_hidden'
Assert-Check ([WordsAndPerils.NativeGuardFocusedGuiCandidate.Guard]::CreationFlags([WordsAndPerils.NativeGuardFocusedGuiCandidate.RunMode]::FocusedGui) -eq (0x4 -bor 0x400 -bor 0x80000 -bor 0x4000)) 'gui_preserves_suspended_unicode_extended_priority'
Assert-Check ([WordsAndPerils.NativeGuardFocusedGuiCandidate.Guard]::ShowWindow([WordsAndPerils.NativeGuardFocusedGuiCandidate.RunMode]::FocusedGui) -eq 1) 'gui_show_normal'
Assert-Rejected {[WordsAndPerils.NativeGuardFocusedGuiCandidate.Guard]::CreationFlags([System.Enum]::ToObject([WordsAndPerils.NativeGuardFocusedGuiCandidate.RunMode],[int]99))} 'unknown_run_mode'
Assert-Rejected {[WordsAndPerils.NativeGuardFocusedGuiCandidate.Guard]::ValidateFocusedGui($candidate)} 'explicit_owner_gui_binding_required'
foreach($profile in @('small','full','unknown')){
 foreach($reading in @(@($true,8589934592UL,8589934592UL),@($false,8589934592UL,8589934592UL),@($true,1073741824UL,1073741824UL),@($true,8589934592UL,536870911UL))){
  $old=[WordsAndPerils.NativeGuardV3.Guard]::Evaluate($reading[0],$reading[1],$reading[2],$profile)
  $new=[WordsAndPerils.NativeGuardFocusedGuiCandidate.Guard]::Evaluate($reading[0],$reading[1],$reading[2],$profile)
  Assert-Check (($old|ConvertTo-Json -Compress) -eq ($new|ConvertTo-Json -Compress)) "admission_parity_$profile"
 }
}
$root=Join-Path ([IO.Path]::GetTempPath()) ('wp-gui-source-only-'+[guid]::NewGuid().ToString('N'))
try {
 $project=Join-Path $root 'project';$data=Join-Path $root 'data';$bin=Join-Path $root 'bin'
 foreach($path in @($project,$data,$bin)){[void][IO.Directory]::CreateDirectory($path)}
 foreach($leaf in @('appdata','localappdata','temp')){[void][IO.Directory]::CreateDirectory((Join-Path $data $leaf))}
 $candidate.Executable=Join-Path $bin 'Godot_v4.6.3-stable_win64.exe'
 # No executable is created. Every test refuses before opening the executable.
 $candidate.WorkingDirectory=$project;$candidate.IsolatedDataRoot=$data
 $candidate.Profile='small';$candidate.TimeoutSeconds=120
 $candidate.Mode=[WordsAndPerils.NativeGuardFocusedGuiCandidate.RunMode]::FocusedGui
 $candidate.OwnerGui=[WordsAndPerils.NativeGuardFocusedGuiCandidate.OwnerFocusedGui]::new()
 $candidate.OwnerGui.RunId='source-only-test';$candidate.OwnerGui.ExpectedGodotSha256='a'*64
 $correct=@('--path',$project,'--script','res://tests/focused/local_gui.gd','--fixed-fps','15','--',$data)
 $candidate.Arguments=$correct+@('--editor')
 Assert-Rejected {[WordsAndPerils.NativeGuardFocusedGuiCandidate.Guard]::ValidateFocusedGui($candidate)} 'gui_arguments_not_exact_allowlist'
 $candidate.Arguments=$correct.Clone();$candidate.Arguments[3]='res://main.gd'
 Assert-Rejected {[WordsAndPerils.NativeGuardFocusedGuiCandidate.Guard]::ValidateFocusedGui($candidate)} 'gui_arguments_not_exact_allowlist'
 $candidate.Arguments=$correct.Clone();$candidate.Arguments[5]='60'
 Assert-Rejected {[WordsAndPerils.NativeGuardFocusedGuiCandidate.Guard]::ValidateFocusedGui($candidate)} 'gui_arguments_not_exact_allowlist'
 $candidate.Arguments=$correct
 foreach($field in @('Profile','TimeoutSeconds','OutputLimitBytes','SelfTest','FaultMode')){
  $old=$candidate.$field
  $candidate.$field=switch($field){'Profile'{'full'} 'TimeoutSeconds'{121} 'OutputLimitBytes'{128} 'SelfTest'{$true} 'FaultMode'{'monitor_low'}}
  Assert-Rejected {[WordsAndPerils.NativeGuardFocusedGuiCandidate.Guard]::ValidateFocusedGui($candidate)} 'gui_requires_small_production_limits'
  $candidate.$field=$old
 }
 $candidate.Executable=Join-Path $bin 'cmd.exe'
 Assert-Rejected {[WordsAndPerils.NativeGuardFocusedGuiCandidate.Guard]::ValidateFocusedGui($candidate)} 'gui_owned_roots_or_executable_invalid'
 $candidate.Executable=Join-Path $bin 'Godot_v4.6.3-stable_win64.exe'
 $occupied=Join-Path $data 'appdata/old-state.txt';[IO.File]::WriteAllText($occupied,'fixture')
 Assert-Rejected {[WordsAndPerils.NativeGuardFocusedGuiCandidate.Guard]::ValidateFocusedGui($candidate)} 'gui_fresh_isolated_data_required'
 Remove-Item -LiteralPath $occupied
 Assert-Rejected {[WordsAndPerils.NativeGuardFocusedGuiCandidate.Guard]::ValidateFocusedGui($candidate)} 'gui_source_closure_mismatch'
} finally {if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force}}
[ordered]@{status='passed';checks=$checks;engine_invocations=0;native_guard_run_calls=0;win32_equivalence='NOT_TESTED'}|ConvertTo-Json
