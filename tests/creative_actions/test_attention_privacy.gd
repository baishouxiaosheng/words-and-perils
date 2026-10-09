extends "res://tests/creative_actions/test_core.gd"
const FocusContract = preload("res://core/focus_contract.gd")
func run()->void:
	base=Coast.world(true)
	var state:=base.duplicate(true);state.items[PLANK]["private_notes"]="PRIVATE_ITEM_SENTINEL";state.hexes["-1,14"]["private_notes"]="PRIVATE_CELL_SENTINEL"
	var f:=FocusContract.new();var ref:=Content.make_reference(PLANK,state)
	expect(ref.entity_revision==Content.make_reference(PLANK,base).entity_revision,"public revision ignores private extra fields")
	var resolved:Dictionary=f.resolve(ref,state)
	expect(resolved.ok and not C.bytes(resolved.focus).contains("PRIVATE_"),"frozen creative attention stores only public facts")
	for field in ["catalog_version","schema_version","entity_revision"]:
		var bad:Dictionary=resolved.focus.duplicate(true);bad[field]=true
		expect(not f.validate_historical(bad,state).is_empty(),"historical attention rejects wrong type "+field)
	for field in ["selection_is_action","scene_id","supporting_cell"]:
		var bad:Dictionary=resolved.focus.duplicate(true);bad.facts[field]="bad"
		expect(not f.validate_historical(bad,state).is_empty(),"historical facts reject wrong type "+field)
	var bad:Dictionary=ref.duplicate(true);bad.catalog_version=true;expect(not f.resolve(bad,state).ok,"live reference catalog type rejects gracefully")
	var e:=make(seed_for(true,true),state);var result:=finish(e,reply(e,PLANK,NORTH,"place_obstruction",ref))
	expect(result.ok,"private world data does not prevent real assessed placement")
	var restored:=make(1);expect(restored.load_data(e.save_data()).ok,"private fields do not corrupt public historical save focus")
	for target in [PLANK,NORTH]:
		var attention:Dictionary=e.attention(Content.make_reference(target,e.state_copy())).focus
		expect(f.validate_historical(attention,e.state_copy()).is_empty(),"current public focus historical validation "+target)
		if target==PLANK:
			for field in ["schema_version","target_id","anchor_id","posture","revision"]:
				bad=attention.duplicate(true);bad.facts.placement[field]=true;expect(not f.validate_historical(bad,e.state_copy()).is_empty(),"typed historical pose "+field)
		else:
			for field in ["schema_version","id","mechanism","source_item_id","target_id","source_deployment_revision","target_revision","active","revision"]:
				bad=attention.duplicate(true);bad.facts.state.relation[field]=[];expect(not f.validate_historical(bad,e.state_copy()).is_empty(),"typed historical relation "+field)
	var wrong_bundle:=state.duplicate(true);wrong_bundle.generated_world.bundle_id=true
	expect(not World.validate(wrong_bundle).ok,"physical world source identity must be a string")
	print("CREATIVE_ATTENTION_PRIVACY ",checks-failures.size(),"/",checks," ",failures)
	quit(0 if failures.is_empty() else 1)
