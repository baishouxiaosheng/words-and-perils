extends RefCounted
## Apply AA to the viewport that actually renders the world, not the HUD root.
## Pattern reviewed against Godot's MIT 3D antialiasing demo; see docs/render_quality.
## Values 0/1 retain the old set_quality API used by existing capture harnesses.
enum Preset { LOW_LOAD = 0, FINE = 1, BALANCED = 2 }

const MENU_IDS := [6, 7, 26]
const LABELS := ["低负载 · 无抗锯齿", "精细 · 4× MSAA", "均衡 · 2× MSAA"]

static func default_preset(adapter: String) -> int:
	# Software rasterizers need an explicit, honestly named low-load preview.
	var device := adapter.to_lower()
	return Preset.LOW_LOAD if device.contains("llvmpipe") or device.contains("softpipe") or device.contains("software rasterizer") else Preset.FINE

static func settings(index: int) -> Dictionary:
	var preset := clampi(index, Preset.LOW_LOAD, Preset.BALANCED)
	var msaa: Viewport.MSAA = Viewport.MSAA_DISABLED
	if preset == Preset.FINE: msaa = Viewport.MSAA_4X
	elif preset == Preset.BALANCED: msaa = Viewport.MSAA_2X
	return {"index": preset, "label": LABELS[preset], "msaa": msaa,
		"samples": [0, 4, 2][preset], "software_preview": preset == Preset.LOW_LOAD,
		"legacy_shadow_size": [1024, 8192, 4096][preset],
		# Hardware 2x2 PCF has no per-pixel noise, so the thresholded two-band contour stays clean.
		"shadow_filter": [RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_HARD][preset]}

static func apply(world: SubViewport, hud: Viewport, container: SubViewportContainer, index: int) -> Dictionary:
	var profile := settings(index)
	world.msaa_3d = profile.msaa
	# Compatibility 4.6 has no built-in FXAA, SMAA, TAA or FSR2. Do not expose
	# unsupported toggles or soften the flat polygon planes with a screen blur.
	world.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	world.use_taa = false
	world.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	world.scaling_3d_scale = 1.0
	container.stretch_shrink = 1
	hud.msaa_3d = Viewport.MSAA_DISABLED
	# The styled coast uses a mipmapped baked contact field, not shadow maps.
	# This preserves the legacy PBR preview's existing shadow setting only.
	RenderingServer.directional_shadow_atlas_set_size(profile.legacy_shadow_size, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(profile.shadow_filter)
	world.set_meta(&"render_quality", profile.duplicate())
	return profile

static func status(index: int) -> String:
	match index:
		Preset.LOW_LOAD: return "低负载预览：关闭抗锯齿，轮廓会有台阶；可在「显示」切换 2× / 4× MSAA"
		Preset.BALANCED: return "均衡显示：2× MSAA、原生分辨率；保留切面，显卡负载较低"
		_: return "精细显示：4× MSAA、原生分辨率；保留切面，1660Ti 性能仍需实机验证"
