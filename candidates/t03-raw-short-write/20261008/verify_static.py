from pathlib import Path
import difflib
import hashlib
import json

ROOT = Path(__file__).resolve().parent
BASE = ROOT.parent / 'exact_v30_restore_20261008/candidate'
PREVIOUS = ROOT.parent / 't03_save_guard_candidate_20261008'
REL = 'core/ai_gm_rebuilt/engine.gd'
OLD = '\tfile.store_string(C.bytes(save_data())); file.flush(); file.close()\n'
NEW = ('\tvar stored: bool = file.store_string(C.bytes(save_data()))\n'
       '\tfile.flush()\n'
       '\tvar write_error: Error = file.get_error()\n'
       '\tfile.close()\n'
       '\tif not stored or write_error != OK: return C.fail("SAVE_FAILED", "Temporary save write failed.")\n')

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def verify():
    checks = []
    def check(label, passed):
        checks.append({'label': label, 'passed': bool(passed)})
    manifest = json.loads((ROOT / 'MANIFEST.json').read_text())
    baseline = (BASE / REL).read_text()
    candidate = (ROOT / 'overlay' / REL).read_text()
    expected = manifest['production_files'][REL]
    check('exact raw Engine base hash matches prior 168-input snapshot',
          sha(BASE / REL) == expected['base_sha256'] == json.loads((PREVIOUS / 'BASE_AUTHORITY_INPUTS.json').read_text())['files'][REL])
    check('exact raw Engine candidate hash matches manifest', sha(ROOT / 'overlay' / REL) == expected['candidate_sha256'])
    check('only the one declared old save statement is replaced', baseline.count(OLD) == 1 and candidate == baseline.replace(OLD, NEW))
    check('reversing the new five statements restores exact frozen Engine bytes', candidate.count(NEW) == 1 and candidate.replace(NEW, OLD) == baseline)
    method = candidate[candidate.index('func save_file('):candidate.index('\nfunc load_file(', candidate.index('func save_file('))]
    baseline_method = baseline[baseline.index('func save_file('):baseline.index('\nfunc load_file(', baseline.index('func save_file('))]
    check('save_file signature is identical and every non-save_file byte is identical',
          method.splitlines()[0] == baseline_method.splitlines()[0] and candidate.replace(method, baseline_method) == baseline)
    check('store_string boolean is captured instead of discarded', 'var stored: bool = file.store_string(C.bytes(save_data()))' in method)
    check('file-reported error is captured before close', method.index('file.get_error()') < method.index('file.close()'))
    check('write refusal precedes rename and checks both signals',
          method.index('if not stored or write_error != OK: return C.fail("SAVE_FAILED"') < method.index('DirAccess.rename_absolute'))
    check('close precedes both write refusal and rename',
          method.index('file.close()') < method.index('if not stored') < method.index('DirAccess.rename_absolute'))
    check('existing readiness/open/rename failures and success return stay exact',
          all(line in method for line in baseline_method.splitlines() if line.strip() and line + '\n' != OLD))
    check('no new temporary deletion, lock, revalidation, schema or load path is added', candidate.replace(NEW, OLD) == baseline)
    check('one production file and two test-only files are the entire overlay',
          sorted(str(p.relative_to(ROOT / 'overlay')) for p in (ROOT / 'overlay').rglob('*') if p.is_file()) ==
          ['core/ai_gm_rebuilt/engine.gd', 'tests/t03_raw_short_write/io_probe.gd', 'tests/t03_raw_short_write/test_save_file.gd'])
    check('all declared small read-only inputs still match their hashes', all(sha(BASE / p) == digest for p, digest in manifest['read_only_inputs'].items()))
    check('frozen project declares Godot 4.6 for the bool-returning store_string API',
          'config/features=PackedStringArray("4.6", "GL Compatibility")' in (BASE / 'project.godot').read_text())
    check('raw Engine is already an authority input; list is unchanged',
          '"res://core/ai_gm_rebuilt/engine.gd"' in (BASE / 'view/generated_natural_coast_basic/authority_inputs.gd').read_text())
    check('previous natural-coast candidate production bytes remain exact',
          all(sha(PREVIOUS / p) == digest for p, digest in manifest['previous_candidate_unchanged'].items()))
    check('previous authority snapshot remains byte-identical', sha(PREVIOUS / 'BASE_AUTHORITY_INPUTS.json') == manifest['base_authority_snapshot']['sha256'])
    test = (ROOT / 'overlay/tests/t03_raw_short_write/test_save_file.gd').read_text()
    check('prepared tests pin exact Engine and extracted-method hashes',
          'const ENGINE_SHA256 := "' + sha(ROOT / 'overlay' / REL) + '"' in test and
          'const METHOD_SHA256 := "' + hashlib.sha256(method.encode()).hexdigest() + '"' in test)
    check('prepared source fault harness changes only three backend identifier occurrences',
          method.count('FileAccess.') == 2 and method.count('DirAccess.') == 1 and
          method.replace('FileAccess.', 'ProbeIO.').replace('DirAccess.', 'ProbeIO.').replace('ProbeIO.open', 'FileAccess.open').replace('ProbeIO.WRITE', 'FileAccess.WRITE').replace('ProbeIO.rename_absolute', 'DirAccess.rename_absolute') == method)
    check('ten prepared cases contain seven in-memory and three isolated native cases',
          test.count('\n\tprobe_case(harness,') == 6 and test.count('\n\tstart_case(') == 5 and manifest['verification']['prepared_runtime_cases'] == 10)
    check('test fixtures have exact manifest hashes', all(sha(ROOT / 'overlay' / p) == item['sha256'] for p, item in manifest['new_test_files'].items()))
    patch = ''.join(difflib.unified_diff(baseline.splitlines(True), candidate.splitlines(True), fromfile='a/' + REL, tofile='b/' + REL, n=5))
    check('minimal source patch is exact, hash-bound and contains one hunk',
          (ROOT / 'T03_RAW_SHORT_WRITE.patch').read_text() == patch and patch.count('\n@@ ') == 1 and
          sha(ROOT / 'T03_RAW_SHORT_WRITE.patch') == manifest['source_patch']['sha256'])
    applied = json.loads((ROOT / 'PATCH_APPLICATION_CHECK.json').read_text())
    check('recorded zero-fuzz disposable patch output is byte-identical to candidate',
          applied['process_exit_code'] == 0 and applied['fuzz_allowed'] == 0 and
          applied['patched_sha256'] == applied['candidate_sha256'] == sha(ROOT / 'overlay' / REL))
    result = {'status': 'passed' if all(c['passed'] for c in checks) else 'failed',
              'scope': 'Python source/byte/order consistency only; no GDScript parse or Engine execution',
              'static_check_count': len(checks), 'checks': checks,
              'godot_parses': 0, 'godot_runs': 0, 'runtime_cases_prepared': 10, 'runtime_cases_executed': 0}
    (ROOT / 'STATIC_CHECKS.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))
    if result['status'] != 'passed': raise SystemExit(1)

if __name__ == '__main__':
    verify()
