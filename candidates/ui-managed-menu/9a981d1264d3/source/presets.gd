extends RefCounted
## One data contract for new floating UI. Sizes are preferences, never a
## permission to exceed the current viewport or shrink its text.
const TYPES={
	&"small":{"preferred":Vector2(420,280),"minimum":Vector2(260,160),"fraction":Vector2(0.88,0.78),"margin":24.0,"duration":0.24,"travel":48.0},
	&"standard":{"preferred":Vector2(640,480),"minimum":Vector2(320,220),"fraction":Vector2(0.92,0.86),"margin":28.0,"duration":0.24,"travel":64.0},
	&"large":{"preferred":Vector2(880,680),"minimum":Vector2(360,280),"fraction":Vector2(0.94,0.90),"margin":32.0,"duration":0.24,"travel":64.0},
	&"drawer":{"preferred":Vector2(640,560),"minimum":Vector2(280,120),"fraction":Vector2(0.94,0.84),"margin":18.0,"duration":0.36,"travel":12.0}
}
static func profile(kind:StringName,options:Dictionary={})->Dictionary:
	if not TYPES.has(kind):return {}
	var rule:Dictionary=TYPES[kind].duplicate(true)
	for key in options:
		if rule.has(key):rule[key]=options[key]
	return rule
static func geometry(kind:StringName,bounds:Vector2,requested:Vector2=Vector2.ZERO,options:Dictionary={})->Rect2:
	var rule:Dictionary=profile(kind,options)
	if rule.is_empty():return Rect2()
	var margin:float=clampf(float(rule.margin),0.0,maxf(0.0,minf(bounds.x,bounds.y)*0.5-1.0))
	var available:Vector2=(bounds-Vector2.ONE*margin*2.0).max(Vector2.ONE)
	var maximum:Vector2=(bounds*Vector2(rule.fraction)).min(available).max(Vector2.ONE)
	var minimum:Vector2=Vector2(rule.minimum).min(maximum)
	var preferred:Vector2=requested if requested.x>0.0 and requested.y>0.0 else Vector2(rule.preferred)
	var extent:Vector2=preferred.max(minimum).min(maximum)
	return Rect2((bounds-extent)*0.5,extent)
static func ease(tween:Tween)->void:
	tween.set_trans(Tween.TRANS_CUBIC);tween.set_ease(Tween.EASE_IN_OUT)


static func anchored_geometry(kind:StringName,bounds:Vector2,anchor:Vector2,options:Dictionary={}) -> Rect2:
	var box:Rect2=geometry(kind,bounds,Vector2.ZERO,options)
	var rule:Dictionary=profile(kind,options)
	if rule.is_empty():return box
	var margin:float=clampf(float(rule.margin),0.0,maxf(0.0,minf(bounds.x,bounds.y)*0.5-1.0))
	box.position=anchor.clamp(Vector2.ONE*margin,(bounds-box.size-Vector2.ONE*margin).max(Vector2.ONE*margin))
	return box
