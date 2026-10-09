extends SceneTree
const Adapter=preload("res://view/playable_build/adapter.gd")
const Scope=preload("res://view/runtime_ai/scoped_engine.gd")
const Content=preload("res://view/playable_build/creative_content.gd")
const C=preload("res://core/ai_gm_rebuilt/canonical.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var a:=Adapter.new(1,true);a.begin_intent(a.sample_goal("brace_bar"),Content.make_reference("passage:coast_brace:south",a.state_copy()))
	var s:=Scope.new(a.engine,func():return true);s.model_request(a.active_action);print(s.last_metrics);print(s.last_error)
	var r:Dictionary=a.request()
	for key in r.context.facts:print(key," ",C.bytes(r.context.facts[key]).length())
	print("contract ",C.bytes(r.contract).length()," focus ",C.bytes(r.context.attention_focus).length())
	quit()
