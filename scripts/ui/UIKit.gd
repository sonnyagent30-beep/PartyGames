extends Node
## UIKit — reusable factory functions for building styled UI in code.
## We build scenes programmatically so we don't need to author .tscn files
## by hand (faster iteration, fewer compatibility surprises).

class_name UIKit

const COLOR_BG_DARK := Color(0.094, 0.094, 0.176)         # #18182D
const COLOR_BG_PANEL := Color(0.137, 0.137, 0.235)        # #23233C
const COLOR_ACCENT := Color(0.0, 0.439, 0.957)             # #0070F4 (Dannion brand blue)
const COLOR_ACCENT_HOVER := Color(0.302, 0.639, 1.0)       # #4DA3FF
const COLOR_TEXT := Color(0.95, 0.95, 0.98)
const COLOR_TEXT_DIM := Color(0.7, 0.7, 0.78)
const COLOR_SUCCESS := Color(0.18, 0.78, 0.45)
const COLOR_WARNING := Color(0.95, 0.65, 0.18)
const COLOR_DANGER := Color(0.93, 0.30, 0.30)

const FONT_SIZE_TITLE := 48
const FONT_SIZE_HEADING := 32
const FONT_SIZE_BODY := 20
const FONT_SIZE_SMALL := 16

static func make_button(text: String, accent: bool = true, big: bool = false) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", FONT_SIZE_BODY if not big else FONT_SIZE_HEADING)
	btn.custom_minimum_size = Vector2(0, 64 if big else 52)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.focus_mode = Control.FOCUS_ALL
	var sb := StyleBoxFlat.new()
	sb.bg_color = COLOR_ACCENT if accent else COLOR_BG_PANEL
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	btn.add_theme_stylebox_override("normal", sb)
	var sb_hover := sb.duplicate()
	sb_hover.bg_color = COLOR_ACCENT_HOVER if accent else Color(0.2, 0.2, 0.32)
	btn.add_theme_stylebox_override("hover", sb_hover)
	var sb_pressed := sb.duplicate()
	sb_pressed.bg_color = COLOR_ACCENT_HOVER.darkened(0.2) if accent else Color(0.18, 0.18, 0.28)
	btn.add_theme_stylebox_override("pressed", sb_pressed)
	var sb_disabled := sb.duplicate()
	sb_disabled.bg_color = Color(0.3, 0.3, 0.4)
	btn.add_theme_stylebox_override("disabled", sb_disabled)
	btn.add_theme_color_override("font_color", COLOR_TEXT)
	btn.add_theme_color_override("font_disabled_color", COLOR_TEXT_DIM)
	return btn

static func make_panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COLOR_BG_PANEL
	sb.corner_radius_top_left = 16
	sb.corner_radius_top_right = 16
	sb.corner_radius_bottom_left = 16
	sb.corner_radius_bottom_right = 16
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 20
	sb.content_margin_bottom = 20
	p.add_theme_stylebox_override("panel", sb)
	return p

static func make_label(text: String, size: int = FONT_SIZE_BODY, color: Color = COLOR_TEXT, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	lbl.horizontal_alignment = align
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return lbl

static func make_vbox(spacing: int = 12) -> VBoxContainer:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", spacing)
	return vb

static func make_hbox(spacing: int = 12) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", spacing)
	return hb

static func make_center_container(child: Control) -> CenterContainer:
	var c := CenterContainer.new()
	c.add_child(child)
	return c

static func make_background() -> ColorRect:
	var bg := ColorRect.new()
	bg.color = COLOR_BG_DARK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bg

static func make_status_dot(color: Color) -> Control:
	var dot := ColorRect.new()
	dot.color = color
	dot.custom_minimum_size = Vector2(14, 14)
	dot.size = Vector2(14, 14)
	return dot