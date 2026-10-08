import sys
from queue_io import *
name=sys.argv[1];out=R/'runs'/name;prep=load(out/'PREPARATION.json');g=load(out/'GUARD_RESULT.json');host=load(out/'actual_HOST_IDENTITY.json');he=load(out/'actual_HOST_EXIT.json')
# Check only the recorded owned host identity, never unknown argv/environment.
info=subprocess.run(['pwsh','-NoProfile','-NonInteractive','-Command',f"$p=Get-Process -Id {int(host['host_pid'])} -ErrorAction SilentlyContinue; if($p){{$p.StartTime.ToUniversalTime().ToString('o')}}; exit 0"],capture_output=True,check=True).stdout.decode().strip()
host_exited=info!=host['host_created_utc']
(out/'stdout.log').write_text(g['Stdout'],'utf-8');(out/'stderr.log').write_text(g['Stderr'],'utf-8')
lines=g['Stdout'].splitlines();iso=[strict(x[len('LOCAL_SUITE_ISOLATION '):].encode()) for x in lines if x.startswith('LOCAL_SUITE_ISOLATION ')];assert len(iso)==1
prefix={'mkdir':'NATURAL_STAGING_MKDIR_PROBE ','parse':'CANDIDATE_PARSE ','focused':'NATURAL_WRITE_RESULT ','owned':'NATURAL_OWNED_STAGING ','diagnostic':'NATURAL_OWNED_STAGING ','compile':'NATURAL_COAST_BASIC ','adapter':'NATURAL_COAST_BASIC '}[prep['kind']]
sr=[strict(x[len(prefix):].encode()) for x in lines if x.startswith(prefix)]
suite=sr[0] if len(sr)==1 else {'ok':False,'failures':['Missing or duplicate completion receipt']};put(out/'SUITE_RESULT.json',suite)
before=load(out/'SOURCE_MAP.json');post=[]
authority_map={x['path']:x['sha256'] for x in load(R/'CANDIDATE_SOURCE_MAP.json')} if prep['kind']!='mkdir' else {'tests/t03_natural_owned_staging/test_mkdir_semantics_probe.gd':'76a2c1d21771992fa40e8fbe339ca74396414b51eb625a577fc7c1609ca88dbb'}
recorded_map={x['path']:x['sha256'] for x in before}
assert all(recorded_map.get(p)==h for p,h in authority_map.items()),'Recorded run source differs from pinned candidate'
for x in before:
 h=sha((Path(prep['project'])/x['path']).read_bytes());post.append({'path':x['path'],'before_sha256':x['sha256'],'after_sha256':h,'matches':h==x['sha256']})
put(out/'SOURCE_POSTRUN.json',post)
diag=[x for x in (g['Stdout']+'\n'+g['Stderr']).splitlines() if re.search(r'(?i)(?:\bERROR:|\bWARNING:|\bSCRIPT ERROR|^\s*FAIL[: ])',x)]
clean=g['Status']=='completed' and g['RootExitCode']==0 and g['GuardExitCode']==0 and he['host_exit_code']==0 and g['JobEmptyAfterRun'] and g['OutputReadersFinished'] and g['AllRecordedHandlesExited'] and host_exited and iso[0]['isolated'] and not g['SyntheticFault'] and not g['OutputLimitExceeded'] and all(x['matches'] for x in post)
bound=suite.get('ok',False) and suite.get('owned_pid',suite.get('pid'))==g['RootPid'] and suite.get('script_sha256')==prep['entry_sha256']
t03=[strict(x[len('T03_EXECUTED '):].encode()) for x in lines if x.startswith('T03_EXECUTED ')];put(out/'T03_EXECUTED.json',t03)
strict_pass=bool(clean and bound and not diag)
if prep['kind']=='mkdir':strict_pass=strict_pass and suite.get('checks')==11 and suite.get('mkdir_results',{}).get('existing_directory')!=0 and suite.get('mkdir_results',{}).get('existing_file')!=0
if prep['kind']=='focused':strict_pass=strict_pass and len(suite.get('cases',[]))==5 and all(x.get('passed',False) for x in suite.get('cases',[]))
if prep['kind']=='compile':strict_pass=strict_pass and suite.get('checks')==4
if prep['kind']=='adapter':strict_pass=strict_pass and suite.get('checks')==170 and len(t03)==13 and all(x['passed'] for x in t03)
expected=prep['kind']=='diagnostic' and clean and bound and suite.get('diagnostic_only') and suite.get('strict_guard_pass_expected') is False and len(diag)==1 and 'cleanup' in diag[0].lower() and not suite.get('failures')
if prep['kind']=='diagnostic':strict_pass=False
result={'run':name,'kind':prep['kind'],'recipe':prep['recipe'],'strict_pass':bool(strict_pass),'expected_diagnostic_observed':bool(expected),'accepted_stage':bool(strict_pass or expected),'checks':suite.get('checks'),'assertions':suite.get('assertions'),'cases':suite.get('cases',[]),'t03_executed':len(t03),'suite_failures':suite.get('failures',[]),'godot_pid':g['RootPid'],'guard_host_pid':host['host_pid'],'host_exit_code':he['host_exit_code'],'guard_exit_code':g['GuardExitCode'],'godot_exit_code':g['RootExitCode'],'diagnostics':diag,'stderr_empty':not g['Stderr'],'job_empty':g['JobEmptyAfterRun'],'readers_finished':g['OutputReadersFinished'],'recorded_handles_exited':g['AllRecordedHandlesExited'],'host_exited':host_exited,'isolation':iso[0],'source_files_rehashed':len(post),'source_mismatches':[x for x in post if not x['matches']],'source_commit':prep['source_commit'],'suite_sha256':prep['suite_sha256'],'entry_sha256':prep['entry_sha256'],'guard_result_sha256':sha((out/'GUARD_RESULT.json').read_bytes()),'source_map_sha256':sha((out/'SOURCE_MAP.json').read_bytes()),'started_utc':g['StartedUtc'],'ended_utc':g['EndedUtc'],'elapsed_seconds':g['ElapsedSeconds'],'job_peak_commit_bytes':g['PeakJobCommitBytes'],'physical_peak_rss_measured':False,'output_bytes':g['OutputObservedBytes'],'admission':g['Admission'],'policy_restore':[x for x in post if x['path']=='core/ai_gm_rebuilt/traversal_policy.gd'],'version_observed_in_test':suite.get('version'),'bound':bound,'prohibited_scope_run':False}
put(out/'VERIFIED_RESULT.json',result)
print(json.dumps({k:v for k,v in result.items() if k in ('run','strict_pass','accepted_stage','expected_diagnostic_observed','checks','assertions','t03_executed','diagnostics','godot_pid','bound')}))
if not result['accepted_stage']:sys.exit(1)
