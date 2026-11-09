class_name UIKit
## Utilitários de interface: tema, painéis e rótulos com a identidade visual do jogo.

const ACCENT := Color(0.89, 0.04, 0.0)
const BG := Color(0.05, 0.06, 0.08, 0.82)
const BG_LIGHT := Color(0.12, 0.13, 0.16, 0.9)
const TEXT := Color(0.95, 0.96, 0.98)
const MUTED := Color(0.62, 0.65, 0.7)
const PURPLE := Color(0.66, 0.25, 1.0)
const GREEN := Color(0.15, 0.85, 0.35)
const YELLOW := Color(1.0, 0.82, 0.1)

static var _font: Font
static var _font_bold: Font
static var _theme: Theme


static func font(bold := false) -> Font:
	if _font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Segoe UI", "Roboto", "Helvetica Neue", "Arial", "Sans-Serif"])
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_font = f
		var fb := SystemFont.new()
		fb.font_names = PackedStringArray(["Segoe UI", "Roboto", "Helvetica Neue", "Arial", "Sans-Serif"])
		fb.font_weight = 750
		fb.font_italic = false
		_font_bold = fb
	return _font_bold if bold else _font


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font(false)
	t.default_font_size = 20
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color(0.12, 0.13, 0.16, 0.92)
	btn.set_corner_radius_all(4)
	btn.content_margin_left = 18
	btn.content_margin_right = 18
	btn.content_margin_top = 10
	btn.content_margin_bottom = 10
	btn.border_width_left = 4
	btn.border_color = Color(0.25, 0.27, 0.3)
	var hov := btn.duplicate() as StyleBoxFlat
	hov.bg_color = Color(0.18, 0.19, 0.23, 0.95)
	hov.border_color = ACCENT
	var prs := btn.duplicate() as StyleBoxFlat
	prs.bg_color = ACCENT
	prs.border_color = Color.WHITE
	var foc := hov.duplicate() as StyleBoxFlat
	foc.draw_center = false
	foc.border_width_left = 4
	foc.border_width_right = 1
	foc.border_width_top = 1
	foc.border_width_bottom = 1
	t.set_stylebox("normal", "Button", btn)
	t.set_stylebox("hover", "Button", hov)
	t.set_stylebox("pressed", "Button", prs)
	t.set_stylebox("focus", "Button", foc)
	t.set_stylebox("disabled", "Button", btn)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_font("font", "Button", font(true))
	t.set_font_size("font_size", "Button", 20)
	t.set_color("font_color", "Label", TEXT)
	var opt := btn.duplicate() as StyleBoxFlat
	opt.border_width_left = 0
	t.set_stylebox("normal", "OptionButton", opt)
	t.set_stylebox("hover", "OptionButton", hov)
	t.set_stylebox("pressed", "OptionButton", hov)
	t.set_stylebox("focus", "OptionButton", foc)
	var pnl := StyleBoxFlat.new()
	pnl.bg_color = Color(0.08, 0.09, 0.11, 0.97)
	pnl.set_corner_radius_all(4)
	pnl.content_margin_left = 8
	pnl.content_margin_right = 8
	pnl.content_margin_top = 8
	pnl.content_margin_bottom = 8
	t.set_stylebox("panel", "PopupMenu", pnl)
	t.set_stylebox("panel", "PanelContainer", panel_style(BG))
	var gr := StyleBoxFlat.new()
	gr.bg_color = Color(0.25, 0.27, 0.3)
	gr.content_margin_top = 4
	gr.content_margin_bottom = 4
	gr.set_corner_radius_all(3)
	var gf := gr.duplicate() as StyleBoxFlat
	gf.bg_color = ACCENT
	t.set_stylebox("slider", "HSlider", gr)
	t.set_stylebox("grabber_area", "HSlider", gf)
	t.set_stylebox("grabber_area_highlight", "HSlider", gf)
	_theme = t
	return t


static func panel_style(c: Color, radius := 4, margin := 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(radius)
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin * 0.7
	s.content_margin_bottom = margin * 0.7
	return s


static func label(text: String, size := 20, color := TEXT, bold := false, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(bold))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


static func panel(c := BG, radius := 4, margin := 12) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(c, radius, margin))
	return p


static func rect(c: Color, size: Vector2) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.custom_minimum_size = size
	return r
