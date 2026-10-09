extends Node
## Same-size white bold world names, one genuinely blurred shadow quad each.
## Glyph rasterization occurs only when a text/style cache entry is missing.
const BASE_FONT=preload("res://assets/NotoSansCJK-Regular.ttc")
const EMBOLDEN:=1.20
const PAD:=12
const BLUR_RADIUS:=2
const BLUR_PASSES:=3
const OPACITY:=0.78
static var _bold:FontVariation
static var _cache:Dictionary={}
static var _order:Array[String]=[]
var pending:Dictionary={}
var rasterizations:=0
var _raster_jobs:Array=[]
func _ready()->void:set_process(false)
class GlyphCanvas extends Node2D:
	var face:Font
	var text:String
	var size_:int
	func _draw()->void:
		face.draw_string(get_canvas_item(),Vector2(PAD,PAD+face.get_ascent(size_)),text,HORIZONTAL_ALIGNMENT_LEFT,-1,size_,Color.WHITE)
static func bold_font()->FontVariation:
	if _bold==null:
		_bold=FontVariation.new();_bold.base_font=BASE_FONT
		_bold.variation_face_index=2;_bold.variation_embolden=EMBOLDEN
	return _bold
func attach(label:Label3D)->void:
	label.font=bold_font();label.modulate=Color.WHITE;label.outline_size=0
	var sprite:Sprite3D=label.get_node_or_null("SoftNameShadow")
	if sprite==null:
		sprite=Sprite3D.new();sprite.name="SoftNameShadow";label.add_child(sprite)
		sprite.billboard=BaseMaterial3D.BILLBOARD_ENABLED;sprite.shaded=false;sprite.no_depth_test=false
		sprite.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sprite.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS;sprite.render_priority=-1
	sprite.pixel_size=label.pixel_size
	sprite.set_meta("blur_radius",BLUR_RADIUS);sprite.set_meta("blur_passes",BLUR_PASSES);sprite.set_meta("opacity",OPACITY)
	var key_="%s:%d:SC2:bold1.2:blur2x3"%[label.text,label.font_size]
	if sprite.get_meta("text_key","")==key_:return
	sprite.set_meta("text_key",key_)
	if _cache.has(key_):_apply(sprite,_cache[key_]);return
	if DisplayServer.get_name()=="headless":return
	if not pending.has(key_):
		pending[key_]=[sprite];call_deferred("_rasterize",key_,label.text,label.font_size)
	else:pending[key_].append(sprite)
func _apply(sprite:Sprite3D,value:Dictionary)->void:
	sprite.texture=value.texture
	# Full-line metrics align the cached image with Label3D's centered line.
	# Screen-space offset is applied to the billboard quad, not world axes.
	sprite.offset=Vector2(1.4,-2.3)
	sprite.position=Vector3(0,0,0.002)
func _rasterize(key_:String,text:String,size_:int)->void:
	var font=bold_font();var line=font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,size_)
	var viewport=SubViewport.new();viewport.size=Vector2i(ceili(line.x)+PAD*2,ceili(font.get_height(size_))+PAD*2)
	viewport.transparent_bg=true;viewport.disable_3d=true;viewport.world_2d=World2D.new();viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var canvas=GlyphCanvas.new();canvas.face=font;canvas.text=text;canvas.size_=size_;viewport.add_child(canvas);canvas.queue_redraw()
	# Frame work belongs to this Node. Releasing a board cancels both _process and
	# its one signal callback; no coroutine can resume after its owner is freed.
	_raster_jobs.append({"key":key_,"viewport":viewport,"frames":2})
	set_process(true)
func _process(_delta:float)->void:
	var ready_job:=false
	for job in _raster_jobs:
		job.frames-=1
		if job.frames<=0:ready_job=true
	if ready_job and not RenderingServer.frame_post_draw.is_connected(_flush_raster_jobs):
		RenderingServer.frame_post_draw.connect(_flush_raster_jobs,CONNECT_ONE_SHOT)
func _flush_raster_jobs()->void:
	var waiting:Array=[]
	for job in _raster_jobs:
		if job.frames>0:waiting.append(job);continue
		if is_instance_valid(job.viewport):_rasterize_finish(job.key,job.viewport)
	_raster_jobs=waiting
	set_process(not _raster_jobs.is_empty())
func _rasterize_finish(key_:String,viewport:SubViewport)->void:
	if not is_inside_tree() or not is_instance_valid(viewport):return
	var source=viewport.get_texture().get_image();viewport.queue_free()
	if source==null or source.is_empty():pending.erase(key_);return
	var blurred=blur_alpha(source,BLUR_RADIUS,BLUR_PASSES,OPACITY);blurred.generate_mipmaps()
	var value={"texture":ImageTexture.create_from_image(blurred)}
	_cache[key_]=value;_order.append(key_);rasterizations+=1
	while _order.size()>128:_cache.erase(_order.pop_front())
	for sprite in pending.get(key_,[]):
		if is_instance_valid(sprite) and sprite.get_meta("text_key","")==key_:_apply(sprite,value)
	pending.erase(key_)
static func blur_alpha(source:Image,radius:int=BLUR_RADIUS,passes:int=BLUR_PASSES,opacity:float=OPACITY)->Image:
	var image_=source.duplicate();image_.convert(Image.FORMAT_RGBA8)
	var width=image_.get_width();var height=image_.get_height();var bytes=image_.get_data()
	var alpha=PackedFloat32Array();alpha.resize(width*height)
	for i in range(alpha.size()):alpha[i]=bytes[i*4+3]/255.0
	var divisor=float(radius*2+1)
	for iteration in range(passes):
		var horizontal=PackedFloat32Array();horizontal.resize(alpha.size())
		var vertical=PackedFloat32Array();vertical.resize(alpha.size())
		for y in range(height):
			var sum_=0.0
			for x in range(-radius,radius+1):
				if x>=0 and x<width:sum_+=alpha[y*width+x]
			for x in range(width):
				horizontal[y*width+x]=sum_/divisor
				if x-radius>=0:sum_-=alpha[y*width+x-radius]
				if x+radius+1<width:sum_+=alpha[y*width+x+radius+1]
		for x in range(width):
			var sum_=0.0
			for y in range(-radius,radius+1):
				if y>=0 and y<height:sum_+=horizontal[y*width+x]
			for y in range(height):
				vertical[y*width+x]=sum_/divisor
				if y-radius>=0:sum_-=horizontal[(y-radius)*width+x]
				if y+radius+1<height:sum_+=horizontal[(y+radius+1)*width+x]
		alpha=vertical
	var out=PackedByteArray();out.resize(width*height*4)
	for i in range(alpha.size()):out[i*4+3]=roundi(clampf(alpha[i]*opacity,0.0,1.0)*255.0)
	return Image.create_from_data(width,height,false,Image.FORMAT_RGBA8,out)
