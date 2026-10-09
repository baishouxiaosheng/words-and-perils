"""Checks actual delivered C#/PS source and real patch application, no engines."""
from pathlib import Path
import datetime
import difflib
import hashlib
import json
import os
import shutil
import subprocess
import tempfile

P=Path(__file__).resolve().parent
CASES=[]
def check(name,ok):
    CASES.append({'case':name,'passed':bool(ok)})
    if not ok: raise AssertionError(name)
def main():
    original=(P/'baseline/WindowsGuard.cs').read_text()
    candidate=(P/'WindowsGuard.FocusedGui.cs').read_text()
    declarations,helper=(P/'FocusedGuiSupport.cs.inc').read_text().split('// INSERT_IN_GUARD\n')
    files=json.loads((P/'inputs/FIXED_SOURCE_MAP.json').read_text())
    rows='\n'.join('  new FocusedSource("%s",%d,"%s"),'%(f['path'],f['bytes'],f['sha256']) for f in files)
    helper=helper.replace('// FIXED_SOURCE_MAP',rows)
    check('actual_helper_present_once',candidate.count(helper)==1)
    check('fixed_source_count',len(files)==18)
    check('fixed_source_paths_unique',len({f['path'] for f in files})==18)
    check('fixed_project_bytes_and_sha',len((P/'inputs/fixed_project.godot').read_bytes())==240 and hashlib.sha256((P/'inputs/fixed_project.godot').read_bytes()).hexdigest()==next(f['sha256'] for f in files if f['path']=='project.godot'))
    restored=candidate
    replacements=[
      ('namespace WordsAndPerils.NativeGuardFocusedGuiCandidate {\n'+declarations,'namespace WordsAndPerils.NativeGuardV3 {'),
      (' public string FaultMode = "none";\n public RunMode Mode = RunMode.Headless;\n public OwnerFocusedGui OwnerGui;',' public string FaultMode = "none";'),
      (' public bool CreatedSuspended = true, NoWindowFlagRequested = true;\n public string SelectedMode = "Headless", OwnerRunId;\n public uint ActualCreationFlags; public ushort ActualShowWindow;',' public bool CreatedSuspended = true, NoWindowFlagRequested = true;'),
      (helper+'\n',''),
      ('  GuiInputLease guiInputs=null;\n  bool attributesReady=false;','  bool attributesReady=false;'),
      ('   if(o.Mode==RunMode.Headless) {\n    if(isGodot && !o.Arguments.Contains("--headless")) throw new ArgumentException("godot_requires_explicit_headless");\n   } else if(o.Mode==RunMode.FocusedGui) {\n    r.SelectedMode="FocusedGui"; r.OwnerRunId=o.OwnerGui==null?null:o.OwnerGui.RunId; r.Schema="wordsandperils_windows_native_guard/focused-gui-candidate-v1"; guiInputs=ValidateFocusedGui(o);\n   } else throw new ArgumentException("unknown_run_mode");','   if(isGodot && !o.Arguments.Contains("--headless")) throw new ArgumentException("godot_requires_explicit_headless");'),
      ('start.Info.ShowWindow=ShowWindow(o.Mode);\n   r.ActualShowWindow=start.Info.ShowWindow; r.ActualCreationFlags=CreationFlags(o.Mode); r.NoWindowFlagRequested=(r.ActualCreationFlags&0x08000000)!=0;','start.Info.ShowWindow=0;'),
      ('true,r.ActualCreationFlags,environment','true,0x4|0x08000000|0x400|0x80000|BELOW_NORMAL,environment'),
      ('   if(guiInputs!=null) {\n    try { guiInputs.VerifySourceSet(); } catch(Exception ex) { r.Status="failed"; r.ErrorOperation="gui_terminal_source_check: "+ex.Message; r.GuardExitCode=3; }\n    finally { try { guiInputs.Dispose(); } catch(Exception ex) { r.Status="failed"; r.ErrorOperation="gui_input_cleanup: "+ex.Message; r.GuardExitCode=3; } }\n   }\n',''),
    ]
    for i,(before,after) in enumerate(replacements):
        check(f'bounded_diff_edit_{i}',restored.count(before)==1)
        restored=restored.replace(before,after)
    check('entire_original_source_restored_exactly',restored==original)
    expected_patch=''.join(difflib.unified_diff(original.splitlines(keepends=True),candidate.splitlines(keepends=True),fromfile='baseline/WindowsGuard.cs',tofile='WindowsGuard.FocusedGui.cs'))
    check('real_unified_diff_matches_candidate',(P/'WindowsGuard.FocusedGui.patch').read_text()==expected_patch)
    check('patch_tool_available',bool(shutil.which('patch')))
    with tempfile.TemporaryDirectory(prefix='wp-gui-patch-') as d:
        temp=Path(d);(temp/'baseline').mkdir();shutil.copyfile(P/'baseline/WindowsGuard.cs',temp/'baseline/WindowsGuard.cs')
        result=subprocess.run(['patch','--batch','--strip=0','--input',str(P/'WindowsGuard.FocusedGui.patch')],cwd=temp,text=True,capture_output=True)
        check('patch_applies_to_real_baseline',result.returncode==0)
        patched=temp/'baseline/WindowsGuard.cs'
        if (temp/'WindowsGuard.FocusedGui.cs').exists(): patched=temp/'WindowsGuard.FocusedGui.cs'
        check('patched_bytes_equal_delivered_candidate',patched.read_bytes()==(P/'WindowsGuard.FocusedGui.cs').read_bytes())
    wrapper=(P/'Invoke-FocusedGuiGuard.ps1').read_text()
    for name,text in {
        'default_headless':"DefaultParameterSetName='Headless'",'ordinary_spec_headless_set':"ParameterSetName='Headless')][string]$SpecPath",
        'dedicated_gui_owner_spec':"ParameterSetName='FocusedGui')][string]$OwnerGuiSpecPath",
        'explicit_owner_switch':"ParameterSetName='FocusedGui')][switch]$FocusedGui",
        'owner_pin_not_spec':'$taskOptions.OwnerGui.ExpectedGodotSha256=$OwnerGodotSha256',
        'owner_run_id_not_spec':'$taskOptions.OwnerGui.RunId=$OwnerRunId',
        'existing_result_no_overwrite':'owner_gui_result_already_exists',
        'strict_gui_fields':'owner_gui_spec_fields_not_exact',
        'owned_log_path':'owner_gui_log_must_be_owned_run_result',
        'only_candidate_type':'NativeGuardFocusedGuiCandidate.Guard',
        'same_guard_exit':'exit $taskResult.GuardExitCode',
    }.items(): check('wrapper_'+name,text in wrapper)
    check('wrapper_no_spec_mode_selection','$taskSpec.mode' not in wrapper and '$taskSpec.gui' not in wrapper)
    check('wrapper_no_queue_or_control_update',all(x not in wrapper for x in ['CONTROL','ready.json','Set-Acl','schtasks','Register-ScheduledTask','Start-Process']))
    for name,text in {
       'fixed_gui_script':'"res://tests/focused/local_gui.gd"',
       'exact_argument_equality':'o.Arguments.SequenceEqual(expected)',
       'small_120_64k_only':'o.Profile!="small" || o.TimeoutSeconds!=120 || o.OutputLimitBytes!=MaximumOutputBytes || o.SelfTest || o.FaultMode!="none"',
       'fixed_engine_name':'"Godot_v4.6.3-stable_win64.exe"',
       'exe_hash_checked':'lease.Bind(exe,-1,o.OwnerGui.ExpectedGodotSha256)',
       'input_write_delete_denied':'FileMode.Open,FileAccess.Read,FileShare.Read',
       'fixed_closure_checked':'SetEquals(FocusedFiles.Select(f=>f.Path))',
       'reparse_rejected':'"gui_reparse_path"',
       'fresh_data_required':'"gui_fresh_isolated_data_required"',
       'fresh_cache_required':'"gui_fresh_cache_required"',
       'roots_disjoint':'Under(data,project) || Under(project,data) || Under(exe,project) || Under(exe,data)',
       'terminal_source_checked':'"gui_terminal_source_check: "',
       'lease_cleanup_failure_nonzero':'"gui_input_cleanup: "',
    }.items(): check('implemented_'+name,text in candidate)
    run=candidate[candidate.index(' public static RunResult Run(Options o) {'):]
    check('gui_validation_before_job',run.index('guiInputs=ValidateFocusedGui(o)')<run.index('job=CreateJobObject'))
    check('gui_same_createprocess_call',candidate.count('Need(CreateProcessW(')==1)
    check('gui_same_resume_call',candidate.count('uint resumed=ResumeThread(')==1)
    harness=(P/'Test-FocusedGui.SourceOnly.ps1').read_text()
    check('managed_test_compiles_actual_candidate',"'WindowsGuard.FocusedGui.cs'" in harness and 'Add-Type' in harness)
    check('managed_test_never_guard_run','::Run(' not in harness)
    check('managed_test_never_launch',all(x not in harness for x in ['Start-Process','CreateProcessW','subprocess','--headless']))
    for name,expected in {'WindowsGuard.cs':'c2add699950e8985f88dc581a76a9eda36549c9c14ff0ada2fe6f4012c53c957','Invoke-WindowsGuard.ps1':'f831a84e71f692fc851945b001cfc98092b7049fb3b48d0f5099fa49e016c5f8'}.items():
        check('original_bytes_unchanged_'+name,hashlib.sha256((P/'baseline'/name).read_bytes()).hexdigest()==expected)

if __name__=='__main__':
    status,error='passed',None
    try:main()
    except Exception as ex:status,error='failed',str(ex)
    receipt={'schema':'wp_focused_gui_actual_source_checks/v1','status':status,'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'pid':os.getpid(),'checks':len(CASES),'passed':sum(x['passed'] for x in CASES),'cases':CASES,'engine_invocations':0,'native_connections':0,'csharp_compilation':'NOT_RUN; compiler unavailable','managed_csharp_tests':'NOT_RUN; pwsh unavailable','win32_equivalence':'NOT_VERIFIED','error':error}
    (P/'SOURCE_TEST_RESULT.json').write_text(json.dumps(receipt,indent=2)+'\n')
    print(json.dumps({k:v for k,v in receipt.items() if k!='cases'}))
    raise SystemExit(0 if status=='passed' else 1)
