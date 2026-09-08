class_name MenuVisuals
extends RefCounted

const NIGHT := Color("080e15")
const PANEL := Color("101b27")
const SILVER := Color("edf5ff")
const MUTED := Color("9cafc5")
const CYAN := Color("68edff")
const VIOLET := Color("ce70ff")
const REFERENCE := "res://assets/style/character_select.png"
const BACKGROUND := "res://assets/ui/menu_neon_background_v2.png"


static func panel_style(accent: Color = CYAN, opacity: float = 0.94) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(PANEL, opacity)
	style.border_color = Color(accent, 0.64)
	style.set_border_width_all(2)
	style.set_corner_radius_all(20)
	style.shadow_color = Color(accent, 0.13)
	style.shadow_size = 12
	return style


static func button(button_node: Button, accent: Color = CYAN, font_size: int = 27) -> void:
	button_node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button_node.add_theme_font_size_override("font_size", font_size)
	button_node.add_theme_color_override("font_outline_color", NIGHT)
	button_node.add_theme_constant_override("outline_size", 3)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := panel_style(accent)
		style.content_margin_left = 18
		style.content_margin_right = 18
		if state == "hover":
			style.bg_color = Color("22384a")
			style.border_color = accent
			style.shadow_color = Color(accent, 0.35)
		elif state == "pressed":
			style.bg_color = Color(accent, 0.24)
			style.border_color = SILVER
			style.shadow_size = 4
		elif state == "disabled":
			style.bg_color = Color("0b131d")
			style.border_color = Color("354452")
			style.shadow_size = 0
		elif state == "focus":
			style.bg_color = Color.TRANSPARENT
			style.border_color = SILVER
			style.set_border_width_all(3)
			style.shadow_color = Color(accent, 0.3)
		button_node.add_theme_stylebox_override(state, style)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button_node.add_theme_color_override(state, SILVER)
	button_node.add_theme_color_override("font_disabled_color", Color("63778a"))


static func label(label_node: Label, font_size: int, tint: Color = SILVER) -> void:
	label_node.add_theme_font_size_override("font_size", font_size)
	label_node.add_theme_color_override("font_color", tint)
	label_node.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label_node.add_theme_constant_override("shadow_offset_y", 2)
	label_node.add_theme_color_override("font_outline_color", NIGHT)
	label_node.add_theme_constant_override("outline_size", 2)


static func reference_region(region: Rect2) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = load(REFERENCE) as Texture2D
	var dimensions := atlas.atlas.get_size()
	atlas.region = Rect2(region.position * dimensions, region.size * dimensions)
	atlas.filter_clip = true
	return atlas


static func logo() -> TextureRect:
	var art := TextureRect.new()
	art.texture = reference_region(Rect2(0, 0.018, 1, 0.113))
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.custom_minimum_size.y = 142
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return art


static func portraits(height: float = 355) -> TextureRect:
	var art := TextureRect.new()
	art.texture = reference_region(Rect2(0, 0.18, 1, 0.46 if height >= 400 else 0.38))
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if height >= 400 else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.custom_minimum_size.y = height
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return art


static func background(parent: Control) -> Control:
	var backdrop := Control.new()
	backdrop.name = "NeonBackdrop"
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var solid := ColorRect.new()
	solid.color = NIGHT
	solid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.add_child(solid)
	solid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var atmosphere := TextureRect.new()
	atmosphere.texture = load(BACKGROUND) as Texture2D
	atmosphere.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	atmosphere.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	atmosphere.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.add_child(atmosphere)
	atmosphere.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return backdrop


static func input(field: LineEdit) -> void:
	field.add_theme_stylebox_override("normal", panel_style(VIOLET))
	var focus := panel_style(CYAN)
	focus.border_color = SILVER
	field.add_theme_stylebox_override("focus", focus)
	field.add_theme_color_override("font_color", SILVER)
	field.add_theme_color_override("font_placeholder_color", MUTED)
	field.add_theme_color_override("caret_color", CYAN)
	field.add_theme_color_override("selection_color", Color("4f427c"))
