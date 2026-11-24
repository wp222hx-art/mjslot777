class_name UI
extends RefCounted
## 界面小工具：配色、字体、面板与按钮样式。

const GOLD := Color("e8c77a")
const GOLD_DEEP := Color("b88a3e")
const CREAM := Color("f3ebd8")
const GREEN := Color("12382e")
const GREEN_LIGHT := Color("1f6b4c")
const WOOD := Color("3a2418")
const WOOD_DARK := Color("24160e")
const RED := Color("b8271e")
const INK := Color("2a2018")
const ICE := Color("8fd8ff")
const THUNDER := Color("b98cff")
const FIRE := Color("ff9a3c")
const WIND := Color("8fe0c0")

static var _fonts: Dictionary = {}


## 喊话字的配色：[上, 中, 下, 描边]。颜色只是氛围，含义始终由文字本身承载。
const PAL := {
	"gold": [Color(1.0, 0.98, 0.78), Color(1.0, 0.80, 0.26), Color(0.88, 0.46, 0.08), Color(0.26, 0.09, 0.0)],
	"fire": [Color(1.0, 0.97, 0.70), Color(1.0, 0.58, 0.14), Color(0.90, 0.14, 0.05), Color(0.30, 0.02, 0.0)],
	"jade": [Color(0.94, 1.0, 0.90), Color(0.42, 0.95, 0.60), Color(0.06, 0.60, 0.34), Color(0.0, 0.17, 0.10)],
	"ice": [Color(0.78, 0.95, 1.0), Color(0.30, 0.72, 1.0), Color(0.06, 0.30, 0.86), Color(0.01, 0.06, 0.24)],
	"thunder": [Color(1.0, 0.96, 1.0), Color(0.82, 0.62, 1.0), Color(0.45, 0.24, 0.95), Color(0.12, 0.03, 0.30)],
	"pink": [Color(1.0, 0.97, 0.98), Color(1.0, 0.66, 0.80), Color(0.90, 0.28, 0.54), Color(0.30, 0.03, 0.15)],
	"silver": [Color(1.0, 1.0, 1.0), Color(0.86, 0.88, 0.93), Color(0.52, 0.56, 0.66), Color(0.04, 0.04, 0.06)],
}


static func font(kind: String = "sans") -> Font:
	if kind == "impact" and not _fonts.has(kind):
		# 站酷庆科黄油体（OFL，见 assets/fonts/impact-OFL.txt）：笔画粗圆，大字远看也清楚
		var ff = load("res://assets/fonts/impact.ttf")
		if ff is FontFile:
			ff.fallbacks = [font("bold")]
			_fonts[kind] = ff
		else:
			_fonts[kind] = font("bold")
	if not _fonts.has(kind):
		var f := SystemFont.new()
		if kind == "kai":
			f.font_names = PackedStringArray(["KaiTi", "STKaiti", "Kaiti SC", "AR PL UKai CN", "Microsoft YaHei", "sans-serif"])
			f.font_weight = 700
		elif kind == "bold":
			f.font_names = PackedStringArray(["Microsoft YaHei", "PingFang SC", "Noto Sans CJK SC", "SimHei", "sans-serif"])
			f.font_weight = 700
		else:
			f.font_names = PackedStringArray(["Microsoft YaHei", "PingFang SC", "Noto Sans CJK SC", "SimHei", "sans-serif"])
		f.allow_system_fallback = true
		_fonts[kind] = f
	return _fonts[kind]


static func label(text: String, size: int, color: Color = CREAM, kind: String = "sans") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(kind))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func outline(l: Label, color: Color, size: int) -> Label:
	l.add_theme_color_override("font_outline_color", color)
	l.add_theme_constant_override("outline_size", size)
	return l


static func place(c: Control, x: float, y: float, w: float = -1.0, h: float = -1.0) -> Control:
	c.position = Vector2(x, y)
	if w >= 0.0:
		c.size = Vector2(w, h)
	return c


static func box(bg: Color, border: Color, radius: int = 14, bw: int = 2, shadow: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.anti_aliasing = true
	if shadow > 0:
		s.shadow_color = Color(0, 0, 0, 0.5)
		s.shadow_size = shadow
		s.shadow_offset = Vector2(0, shadow * 0.5)
	return s


static func panel(parent: Node, rect: Rect2, style: StyleBox) -> Panel:
	var p := Panel.new()
	p.position = rect.position
	p.size = rect.size
	p.add_theme_stylebox_override("panel", style)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	return p


static func wood_panel(parent: Node, rect: Rect2) -> Panel:
	return panel(parent, rect, box(Color(0.20, 0.12, 0.07, 0.94), GOLD_DEEP, 16, 3, 8))


static func green_panel(parent: Node, rect: Rect2) -> Panel:
	return panel(parent, rect, box(Color(0.06, 0.20, 0.15, 0.92), GOLD_DEEP, 16, 3, 8))


static func button(parent: Node, text: String, rect: Rect2, fsize: int = 34, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.position = rect.position
	b.size = rect.size
	b.pivot_offset = rect.size * 0.5
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font("kai"))
	b.add_theme_font_size_override("font_size", fsize)
	var bg := Color("c79a45") if primary else Color(0.16, 0.10, 0.06, 0.96)
	var fg := INK if primary else GOLD
	var radius := int(min(rect.size.y * 0.32, 26.0))
	b.add_theme_stylebox_override("normal", box(bg, GOLD if primary else GOLD_DEEP, radius, 3, 6))
	b.add_theme_stylebox_override("hover", box(bg.lightened(0.10), GOLD, radius, 3, 6))
	b.add_theme_stylebox_override("pressed", box(bg.darkened(0.18), GOLD, radius, 3, 2))
	b.add_theme_stylebox_override("disabled", box(Color(0.14, 0.14, 0.13, 0.9), Color(0.4, 0.38, 0.32), radius, 3, 2))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, fg)
	b.add_theme_color_override("font_disabled_color", Color(0.55, 0.52, 0.45))
	parent.add_child(b)
	return b


static func fmt(n: int) -> String:
	var s := str(abs(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## 冲击力喊话字：粗圆字体 + 渐变字面 + 厚描边 + 投影。pal 见 PAL。
static func impact(text: String, size: int, pal: String = "gold") -> Label:
	var l := label(text, size, Color.WHITE, "impact")
	var p: Array = PAL.get(pal, PAL["gold"])
	var ow: int = max(10, size / 6)
	l.add_theme_color_override("font_outline_color", p[3])
	l.add_theme_constant_override("outline_size", ow)
	l.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", max(4, size / 12))
	l.add_theme_constant_override("shadow_outline_size", ow)
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/gold_text.gdshader")
	m.set_shader_parameter("height", font("impact").get_height(size))
	m.set_shader_parameter("top", p[0])
	m.set_shader_parameter("mid", p[1])
	m.set_shader_parameter("bottom", p[2])
	l.material = m
	return l


## 鎏金渐变字：奖励数字、牌型标题。字面染金，描边与阴影保持深色。
static func gold(l: Label, size: int) -> Label:
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0.26, 0.09, 0.0, 1.0))
	l.add_theme_constant_override("outline_size", max(8, size / 7))
	l.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", max(3, size / 14))
	l.add_theme_constant_override("shadow_outline_size", max(8, size / 7))
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/gold_text.gdshader")
	m.set_shader_parameter("height", size * 1.38)
	l.material = m
	return l

