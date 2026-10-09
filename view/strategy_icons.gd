extends RefCounted
## Original 24px line icons authored for the tabletop HUD. No third-party artwork.
static var _cache: Dictionary = {}
static func texture(kind: String, color: String = "947b50") -> Texture2D:
	var key := kind + color
	if _cache.has(key): return _cache[key]
	var marks := {
		"endturn": '<path d="M18 8a7 7 0 1 0 1 7M18 3v6h-6"/><path d="m10 9 4 3-4 3Z"/>',
		"chat": '<path d="M3 4h18v13H10l-5 4v-4H3ZM7 8h10M7 12h7"/>',
		"menu": '<path d="M4 6h16M4 12h16M4 18h16"/>',
		"radio_on": '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="4" fill="#597e6b" stroke="none"/>',
		"radio_off": '<circle cx="12" cy="12" r="8"/>',
		"check_on": '<path d="M5 3h14l2 2v14l-2 2H5l-2-2V5Z"/><path d="m7 12 3 3 7-7"/>',
		"check_off": '<path d="M5 3h14l2 2v14l-2 2H5l-2-2V5Z"/>',
		"target": '<circle cx="12" cy="12" r="5"/><path d="M12 2v5m0 10v5M2 12h5m10 0h5"/>',
		"move": '<path d="M3 18h5l4-12h8m-4-4 4 4-4 4"/>',
		"die": '<path d="m12 2 9 6v9l-9 5-9-5V8Zm-9 6 9 4 9-4M12 12v10M3 17l9-15 9 15Z"/>',
		"satchel": '<path d="M4 8h16v12H4ZM8 8V4h8v4M4 11h16M9 11v4h6v-4"/>',
		"book": '<path d="M4 3h13l3 3v15H4ZM7 7h8M7 11h10M7 15h10M17 3v4h3"/>',
		"save": '<path d="M4 3h13l3 3v15H4ZM8 3v7h8V3M8 21v-7h8v7"/>',
		"wait": '<path d="M6 3h12M6 21h12M7 3v4l10 10v4M17 3v4L7 17v4"/>',
		"clear": '<path d="m6 6 12 12M18 6 6 18"/>',
		"world": '<path d="m2 19 6-12 5 8 4-11 5 15ZM5 13h5M15 10h4"/>',
		"quill": '<path d="M4 21 9 13 18 3c3 2 3 5 1 7L10 17Zm5-8 4 2M7 17l9-10M3 22h12"/><path d="m17 4-1 5 5-2"/>',
		"focus": '<path d="M3 9V4h5m8 0h5v5M3 15v5h5m8 0h5v-5"/><circle cx="12" cy="12" r="4"/><path d="M12 6v2m0 8v2M6 12h2m8 0h2"/>',
		"crest": '<path d="m12 2 8 4v7c0 4-4 7-8 9-4-2-8-5-8-9V6Z"/><path d="M6 15h12M7 12l3-5 3 5 3-3 2 6M9 18h6"/>',
		"help": '<circle cx="12" cy="12" r="9"/><path d="M9 8c0-4 8-4 6 1l-3 3v3M12 18h.01"/>',
		"export": '<path d="M4 8v13h16V8M12 16V2m-4 4 4-4 4 4"/>',
		"import": '<path d="M4 8v13h16V8M12 2v14m-4-4 4 4 4-4"/>',
	}
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="#' + color + '" stroke-width="1.65" stroke-linecap="round" stroke-linejoin="round">' + String(marks.get(kind, marks.target)) + '</g></svg>'
	var image := Image.new()
	image.load_svg_from_string(svg, 2.0)
	var result := ImageTexture.create_from_image(image)
	_cache[key] = result
	return result

static func small_texture(kind: String, color: String, pixels: int = 16) -> Texture2D:
	var key := "small:"+kind+color+str(pixels)
	if _cache.has(key): return _cache[key]
	var image:=texture(kind,color).get_image()
	image.resize(pixels,pixels,Image.INTERPOLATE_LANCZOS)
	var result:=ImageTexture.create_from_image(image)
	_cache[key]=result
	return result

static func menu_texture(kind: String, color: String = "7d846b") -> Texture2D:
	return small_texture(kind,color,16)
