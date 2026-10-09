extends RefCounted
## Original deterministic miniature geometry profiles, in world-space meters.
## These shape existing surfaces only; they define no routes or game rules.
static func bank_height(distance:float,width:float,bed:float,water:float,ground:float,shoulder:float)->float:
	# Submerged toe -> gently rounded wet ledge -> dry shoulder -> meadow.
	# Explicit broad intervals read at game zoom; texture is only micro-detail.
	var toe=width*0.66
	var wet=width+shoulder*0.29
	var ledge=width+shoulder*0.48
	var crest=width+shoulder*0.85
	var outer=width+shoulder
	var wet_y=minf(ground,water+0.040)
	if distance<=toe:return bed
	if distance<width:return lerpf(bed,water,smoothstep(toe,width,distance))
	if distance<wet:return lerpf(water,wet_y,smoothstep(width,wet,distance))
	if distance<ledge:return wet_y+0.006*smoothstep(wet,ledge,distance)
	if distance<crest:return lerpf(wet_y+0.006,ground+0.012,smoothstep(ledge,crest,distance))
	if distance<outer:return lerpf(ground+0.012,ground,smoothstep(crest,outer,distance))
	return ground

