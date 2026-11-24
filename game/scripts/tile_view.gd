class_name TileView
extends Control
## 一张牌 / 一个转轴符号。材质由 shader 按品级渲染，角标同时用文字标识品级（颜色不单独承载信息）。

const SHADER := preload("res://shaders/tile.gdshader")
const BADGES := ["", "badge_blue", "badge_purple", "badge_gold", "badge_diamond"]

static var _tex_cache: Dictionary = {}

var id := ""
var grade := 0
var tex_rect: TextureRect
var badge: TextureRect
var shadow: Panel
var mat: ShaderMaterial
var glow: Panel


static func tex(path: String) -> Texture2D:
	if not _tex_cache.has(path):
		_tex_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex_cache[path]


static func symbol_tex(sym: String) -> Texture2D:
	if sym == "hu" or sym == "wild":
		return tex("res://assets/ui/%s.png" % sym)
	return tex("res://assets/tiles/%s.png" % sym)


static func make(sym: String, g: int, sz: Vector2) -> TileView:
	var t := TileView.new()
	t.custom_minimum_size = sz
	t.size = sz
	t.pivot_offset = sz * 0.5
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t._build()
	t.set_symbol(sym, g)
	return t


func _build() -> void:
	shadow = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.0)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 5)
	sb.set_corner_radius_all(int(size.x * 0.14))
	shadow.add_theme_stylebox_override("panel", sb)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shadow.position = Vector2(4, 4)
	shadow.size = size - Vector2(8, 8)
	add_child(shadow)

	tex_rect = TextureRect.new()
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.size = size
	tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	tex_rect.material = mat
	add_child(tex_rect)

	badge = TextureRect.new()
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var bs := size.x * 0.36
	badge.size = Vector2(bs, bs)
	badge.position = Vector2(size.x - bs * 0.86, -bs * 0.16)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(badge)


func set_symbol(sym: String, g: int = 0) -> void:
	id = sym
	grade = g
	tex_rect.texture = symbol_tex(sym)
	var round_sym := sym == "hu" or sym == "wild"
	shadow.visible = not round_sym
	mat.set_shader_parameter("grade", 0 if round_sym else g)
	badge.visible = g > 0 and not round_sym
	if badge.visible:
		badge.texture = tex("res://assets/ui/%s.png" % BADGES[g])


func set_dim(v: float) -> void:
	mat.set_shader_parameter("dim", v)
	shadow.visible = v < 0.5 and id != "hu" and id != "wild"
	if v >= 0.5:
		badge.visible = false


func flash(dur := 0.25) -> void:
	mat.set_shader_parameter("flash", 0.85)
	var tw := create_tween()
	tw.tween_method(func(v): mat.set_shader_parameter("flash", v), 0.85, 0.0, dur)


## 发光描边：消除高亮、入槽目标、听牌缺张提示。颜色同时配合文字说明，不单独承载信息。
func set_glow(color: Color) -> void:
	var round_sym := id == "hu" or id == "wild"
	if glow == null:
		glow = Panel.new()
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(glow)
		move_child(glow, 0)
	if round_sym:
		var d: float = min(size.x, size.y)
		glow.position = Vector2((size.x - d) * 0.5 - 5, (size.y - d) * 0.5 - 5)
		glow.size = Vector2(d + 10, d + 10)
	else:
		glow.position = Vector2(-5, -5)
		glow.size = size + Vector2(10, 10)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(color.r, color.g, color.b, 0.22)
	sb.border_color = color
	sb.set_border_width_all(5)
	sb.set_corner_radius_all(int(glow.size.x * 0.5) if round_sym else int(size.x * 0.17))
	sb.shadow_color = Color(color.r, color.g, color.b, 0.85)
	sb.shadow_size = 18
	sb.anti_aliasing = true
	glow.add_theme_stylebox_override("panel", sb)
	glow.modulate.a = 1.0
	glow.visible = true


func clear_glow() -> void:
	if glow != null:
		glow.visible = false
