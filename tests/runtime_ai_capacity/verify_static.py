import hashlib,json,re
from pathlib import Path
base=Path('tests/runtime_ai_capacity/baseline')
checks={}
def method(s,start,end):return s.split(start,1)[1].split(end,1)[0]
old=(base/'scoped_engine.gd').read_text();new=Path('view/runtime_ai/scoped_engine.gd').read_text()
checks['public_projection_function_exact']=method(old,'func model_request','func narration_request')==method(new,'func model_request','func narration_request')
checks['narration_projection_exact']=method(old,'func narration_request','func _budget')==method(new,'func narration_request','func _budget')
checks['fact_reference_authority_exact']=old[old.index('static func _scene_counts'):]==new[new.index('static func _scene_counts'):]
old_controller=(base/'controller.gd').read_text();new_controller=Path('view/runtime_ai/controller.gd').read_text()
checks['trusted_instructions_exact']=old_controller.split('const CONTRACT := ',1)[1].split('\n',1)[0]==new_controller.split('const CONTRACT := ',1)[1].split('\n',1)[0]
checks['no_cap_in_payload']=not re.search(r'scoped\[.*budget|request\[.*budget',new)
old_client=(base/'client.gd').read_text();new_client=Path('core/ai_gm_http/client.gd').read_text()
checks['wire_limit_unchanged']='if body.to_utf8_buffer().size() > 4194304:' in old_client and 'if body.to_utf8_buffer().size() > 4194304:' in new_client
checks['model_reasoning_output_validation_unchanged']=method(old_client,'\tvar output_tokens: Variant','\t_config =')==method(new_client,'\tvar output_tokens: Variant','\t_config =')
for name in ['regression_test_controller.gd','regression_test_integration.gd','regression_test_core.gd','regression_test_settlement.gd']:
    old=Path('tests/runtime_ai_budget',name).read_text();new=Path('tests/runtime_ai_capacity/regressions',name).read_text()
    checks['output_only_wrapper_'+name]=old.replace('res://artifacts/runtime_ai_budget_20261004/','res://artifacts/runtime_ai_capacity_20261004/regressions/')==new
checks['legacy_budget_wrapper']=Path('tests/runtime_ai_budget/test_budget.gd').read_text().replace('res://artifacts/runtime_ai_budget_20261004/','res://artifacts/runtime_ai_capacity_20261004/regressions/')==Path('tests/runtime_ai_capacity/regressions/test_legacy_budget.gd').read_text()
report={'checks':checks,'passed':all(checks.values()),'source_sha256':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [Path('core/ai_gm_http/request_budget.gd'),Path('core/ai_gm_http/client.gd'),Path('view/runtime_ai/scoped_engine.gd'),Path('view/runtime_ai/controller.gd'),Path('view/runtime_ai/connection_panel.gd'),Path('view/ai_connection_settings/panel.gd')]}}
print(json.dumps(report,indent=2));raise SystemExit(0 if report['passed'] else 1)
