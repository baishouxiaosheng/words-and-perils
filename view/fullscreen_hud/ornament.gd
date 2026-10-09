extends RefCounted
## Original contour design: connected rails, round instruments and sea-leaf
## ornaments. Morphology is fantasy HUD; rendering uses two matte light groups.
static var cache:Dictionary={}
static func texture(kind:String,state:String="normal")->Texture2D:
	var key:=kind+state
	if cache.has(key):return cache[key]
	var light:="#fff1c9";var face:="#e8d59d";var shade:="#b7a675";var ink:="#55614e"
	if state=="hover":face="#f6e9bc";light="#fff8df"
	if state=="pressed":face="#cfbc88";light="#b4a270";shade="#f5e5b8"
	if state=="disabled":face="#bfc0a3";light="#d5d5b9";shade="#969e88"
	var svg:='<svg xmlns="http://www.w3.org/2000/svg" width="320" height="160" viewBox="0 0 320 160">'
	if kind in ["round","turn"]:
		svg='<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">'
		# Four fittings make a navigational instrument rather than a flat circle.
		svg+='<path d="M64 0l9 10h-18ZM128 64l-10 9V55ZM64 128l-9-10h18ZM0 64l10-9v18Z" fill="'+ink+'"/>'
		svg+='<circle cx="64" cy="64" r="58" fill="'+ink+'"/><circle cx="64" cy="64" r="56" fill="'+shade+'"/>'
		svg+='<path d="M8 64a56 56 0 0 1 112 0H114a50 50 0 0 0-100 0Z" fill="'+light+'"/>'
		svg+='<circle cx="64" cy="64" r="49" fill="'+face+'"/><circle cx="64" cy="64" r="44" fill="none" stroke="'+ink+'" stroke-width="1.5"/>'
		if kind=="turn":
			var core:="#4c8585" if state!="disabled" else "#8c9a8a"
			if state=="hover":core="#65a099"
			if state=="pressed":core="#386668"
			svg+='<circle cx="64" cy="64" r="41" fill="'+core+'"/><path d="M23 64a41 41 0 0 0 82 0v2a41 41 0 0 1-82 0Z" fill="#284b54"/>'
			for i in range(32):
				var a:=float(i)*TAU/32;var p:=Vector2(64,64)+Vector2(cos(a),sin(a))*47;var q:=Vector2(64,64)+Vector2(cos(a),sin(a))*51
				svg+='<path d="M%.2f %.2fL%.2f %.2f" stroke="%s" stroke-width="1.3"/>'%[p.x,p.y,q.x,q.y,ink]
			svg+='<path d="M45 14q19-9 38 0M45 114q19 9 38 0" fill="none" stroke="'+light+'" stroke-width="2"/>'
	elif kind=="dock":
		# Curved end-wings, continuous double rail, anchored leaf fittings.
		svg+='<path d="M8 36Q30 39 40 18Q51 8 66 16H254Q272 10 283 29Q293 41 312 36Q304 58 307 80Q304 113 316 130Q290 126 279 145H41Q27 127 4 132Q17 103 12 79Q17 57 8 36Z" fill="'+ink+'"/>'
		svg+='<path d="M13 40Q33 41 43 22Q52 14 67 20H253Q269 15 280 33Q292 46 306 40Q299 62 302 80Q300 112 309 126Q288 123 276 140H44Q29 122 11 127Q22 102 17 79Q21 57 13 40Z" fill="'+shade+'"/>'
		svg+='<path d="M20 44Q37 43 48 27H272Q285 46 299 44L295 113Q281 113 270 131H50Q38 113 21 117L25 82Z" fill="'+face+'"/>'
		svg+='<path d="M20 44Q37 43 48 27H272Q285 46 299 44M29 49Q41 46 52 34H269" fill="none" stroke="'+light+'" stroke-width="4"/>'
		svg+='<path d="M32 118Q42 122 49 132H272Q282 118 297 118" fill="none" stroke="#807e57" stroke-width="2"/>'
		for pair in [[30,1],[290,-1]]:
			var x:int=pair[0];var sgn:int=pair[1]
			svg+='<path d="M%d 58q%d-15 %d-20q%d 15 %d 28q%d-4 %d-8M%d 88q%d 14 %d 20q%d-16 %d-27" fill="none" stroke="%s" stroke-width="2"/>'%[x,10*sgn,24*sgn,-3*sgn,-16*sgn,7*sgn,13*sgn,x,10*sgn,22*sgn,-3*sgn,-15*sgn,ink]
		# Central clasp is authored as a folded sea-leaf, not a copied emblem.
		svg+='<path d="M145 137l15-6 15 6-15 14Z" fill="'+ink+'"/><path d="M148 137l12-4 12 4-12 10Z" fill="'+light+'"/><path d="M160 133v14l12-10Z" fill="'+shade+'"/>'
	elif kind=="speech":
		svg+='<path d="M17 23Q32 8 54 17H266Q286 8 303 23L297 130Q283 144 263 139H57Q34 144 23 130Z" fill="#eadcad" fill-opacity=".86"/>'
		svg+='<path d="M20 26Q34 13 57 21H263Q285 13 300 26M23 129Q40 141 59 135H261Q282 141 297 129" fill="none" stroke="'+shade+'" stroke-width="2"/>'
		svg+='<path d="M20 25l15 2-12 11M300 25l-15 2 12 11M24 128l13-2-11-10M296 128l-13-2 11-10" fill="none" stroke="'+ink+'" stroke-width="1.4"/>'
	elif kind=="history":
		svg+='<path d="M12 15Q30 0 49 11H271Q291 0 308 15L309 145Q288 157 271 149H49Q29 158 11 145Z" fill="#f0e4b9" fill-opacity=".55"/>'
		svg+='<path d="M12 15Q30 0 49 11H271Q291 0 308 15M309 145Q288 157 271 149H49Q29 158 11 145" fill="none" stroke="'+ink+'" stroke-width="1.3"/>'
		svg+='<path d="M16 21L14 136M304 21l2 115" stroke="'+light+'" stroke-width="2"/>'
		for pair in [[16,1],[304,-1]]:
			var x:int=pair[0];var sgn:int=pair[1]
			svg+='<path d="M%d 20q%d-8 %d 0q%d 8 %d 18M%d 139q%d 8 %d 0q%d-8 %d-18" fill="none" stroke="%s" stroke-width="2"/>'%[x,13*sgn,22*sgn,-5*sgn,-17*sgn,x,13*sgn,22*sgn,-5*sgn,-17*sgn,shade]
	elif kind=="status":
		svg+='<path d="M0 26Q18 7 43 20H286L318 40L306 59V124L278 143H43Q18 153 0 129Q15 98 9 78Z" fill="'+ink+'"/>'
		svg+='<path d="M9 30Q24 15 46 26H283L309 43L298 61V120L275 136H44Q24 143 9 126Q23 98 17 78Z" fill="'+face+'"/>'
		svg+='<path d="M9 30Q24 15 46 26H283L309 43L302 46L279 33H48Q27 21 18 33Z" fill="'+light+'"/><path d="M10 125Q23 138 46 131H275L298 115V120L275 136H44Q24 143 9 126Z" fill="'+shade+'"/>'
	else:
		# A shallow pointed tablet keeps its edges outside the glyph band even
		# at the 28px compact size. No ornament line crosses its readable face.
		svg+='<path d="M2 80Q20 38 30 10Q45 1 62 5H258Q278 1 290 10Q301 42 318 80Q301 118 290 150Q278 159 258 155H62Q43 159 30 150Q20 122 2 80Z" fill="'+ink+'"/>'
		svg+='<path d="M9 80Q27 39 36 15Q47 7 64 11H256Q274 7 284 15Q294 41 311 80Q294 117 284 145Q274 153 256 149H64Q47 154 36 145Q27 119 9 80Z" fill="'+face+'"/>'
		svg+='<path d="M13 74Q29 35 39 17Q48 10 65 14H255Q272 10 281 17" fill="none" stroke="'+light+'" stroke-width="3"/><path d="M39 143Q48 150 65 146H255Q272 150 281 143L307 85" fill="none" stroke="'+shade+'" stroke-width="3"/>'

	svg+='</svg>'
	var img:=Image.new();img.load_svg_from_string(svg,1.0)
	cache[key]=ImageTexture.create_from_image(img);return cache[key]
static func surface(kind:String,pad:float=12.0,state:String="normal")->StyleBoxTexture:
	var box:=StyleBoxTexture.new();box.texture=texture(kind,state)
	var horizontal:=55.0 if kind in ["dock","status"] else 35.0
	var vertical:=35.0 if kind=="dock" else 24.0
	for side in [SIDE_LEFT,SIDE_RIGHT]:box.set_texture_margin(side,horizontal);box.set_content_margin(side,pad)
	for side in [SIDE_TOP,SIDE_BOTTOM]:box.set_texture_margin(side,vertical);box.set_content_margin(side,pad)
	if kind in ["round","turn"]:
		for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:box.set_texture_margin(side,0);box.set_content_margin(side,0)
	return box
