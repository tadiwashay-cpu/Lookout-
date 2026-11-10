class_name UITheme
extends RefCounted
## One big, readable theme for tablets/phones.

static var _theme: Theme

## Your fonts (freeware, NON-COMMERCIAL licence: fine for testing with
## friends; swap or license them before a paid/ads release).
const TITLE_FONT := preload("res://assets/fonts/aq_hand_graffiti_bold.otf")   # titles, banners
const HUD_FONT := preload("res://assets/fonts/mightyspidey.ttf")              # speedo, heat, big numbers


static func get_theme() -> Theme:
	if _theme:
		return _theme
	_theme = Theme.new()
	_theme.default_font_size = 30
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.06, 0.065, 0.07, 0.94)
	panel.set_corner_radius_all(10)
	panel.set_content_margin_all(24)
	_theme.set_stylebox("panel", "PanelContainer", panel)
	_theme.set_stylebox("panel", "Panel", panel)
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var box := StyleBoxFlat.new()
		box.bg_color = {
			"normal": Color(0.16, 0.16, 0.17), "hover": Color(0.22, 0.22, 0.23),
			"pressed": Color(0.85, 0.62, 0.3), "focus": Color(0.22, 0.22, 0.23), "disabled": Color(0.1, 0.1, 0.1),
		}[state]
		box.set_corner_radius_all(8)
		box.set_content_margin_all(16)
		_theme.set_stylebox(state, "Button", box)
		_theme.set_stylebox(state, "OptionButton", box)
	_theme.set_color("font_color", "Button", Color(0.95, 0.93, 0.88))
	_theme.set_color("font_color", "Label", Color(0.95, 0.93, 0.88))
	_theme.set_constant("separation", "VBoxContainer", 14)
	_theme.set_constant("separation", "HBoxContainer", 14)
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(0.85, 0.62, 0.3)
	grabber.set_corner_radius_all(4)
	grabber.content_margin_top = 6
	grabber.content_margin_bottom = 6
	_theme.set_stylebox("grabber_area", "HSlider", grabber)
	return _theme
