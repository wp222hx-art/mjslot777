class_name FX
extends Control
## 特效层：粒子、飘字、横幅、震屏、闪屏、时刻元素边缘辉光、墨刃。
## 只做表现，不参与任何判定；reduce=true 时降级为静态提示，信息不丢失。

const EDGE := preload("res://shaders/edge.gdshader")
const RAYS := preload("res://shaders/rays.gdshader")

var reduce := false
var _dot: Texture2D
var _edge: ColorRect
var _edge_mat: ShaderMaterial
var _flash: ColorRect
var _mood := "none"
var _mood_emitters: Array = []
var _seq_cache: Dictionary = {}
var _coins: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 32
	gt.height = 32
	_dot = gt

	_edge = ColorRect.new()
	_edge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge_mat = ShaderMaterial.new()
	_edge_mat.shader = EDGE
	_edge.material = _edge_mat
	add_child(_edge)

	_flash = ColorRect.new()
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 1, 1, 0)
	add_child(_flash)


func dot() -> Texture2D:
	return _dot


# ---------- 粒子 ----------

func _particles(pos: Vector2, color: Color, amount: int, life: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = _dot
	p.position = pos
	p.amount = max(1, amount / 3 if reduce else amount)
	p.lifetime = life
	p.color = color
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = ramp
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = mat
	add_child(p)
	return p


func burst(pos: Vector2, color: Color, amount: int = 18, speed: float = 320.0, life: float = 0.55, grav: float = 500.0, scale: float = 0.55) -> void:
	var p := _particles(pos, color, amount, life)
	p.one_shot = true
	p.explosiveness = 0.95
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.35
	p.initial_velocity_max = speed
	p.gravity = Vector2(0, grav)
	p.scale_amount_min = scale * 0.5
	p.scale_amount_max = scale * 1.3
	p.emitting = true
	get_tree().create_timer(life + 0.3).timeout.connect(p.queue_free)


## 自下而上的火焰 / 向上飘的星点
func rise(pos: Vector2, width: float, color: Color, amount: int, dur: float, speed: float = 420.0, scale: float = 1.2) -> void:
	var p := _particles(pos, color, amount, 0.9)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(width * 0.5, 8)
	p.direction = Vector2(0, -1)
	p.spread = 18.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector2(0, -160)
	p.scale_amount_min = scale * 0.5
	p.scale_amount_max = scale * 1.4
	p.emitting = true
	get_tree().create_timer(dur).timeout.connect(_stop_emitter.bind(p))


func _stop_emitter(p: CPUParticles2D) -> void:
	if not is_instance_valid(p):
		return
	p.emitting = false
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)


## 跟随节点的拖尾（风·入槽）
func trail(node: Node, color: Color) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = _dot
	p.amount = 10 if reduce else 28
	p.lifetime = 0.4
	p.local_coords = false
	p.color = color
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.9))
	ramp.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = ramp
	p.spread = 180.0
	p.initial_velocity_min = 10.0
	p.initial_velocity_max = 60.0
	p.gravity = Vector2.ZERO
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = mat
	node.add_child(p)
	return p


# ---------- 文字 ----------

## 颜色 → 喊话字配色
static func pal_of(color: Color) -> String:
	if color.is_equal_approx(UI.ICE): return "ice"
	if color.is_equal_approx(UI.THUNDER): return "thunder"
	if color.is_equal_approx(UI.FIRE): return "fire"
	if color.is_equal_approx(UI.WIND): return "jade"
	if color.is_equal_approx(UI.CREAM) or color.is_equal_approx(Color.WHITE): return "silver"
	return "gold"


## 盖章式喊话：大字从镜头前砸下来，落定瞬间光芒 + 冲击环 + 碎星，停留后上浮淡出。
## 碰 / 吃 / 对、听牌、连消、集齐、免费转都用它。减少动态效果时不砸、不闪，只显示文字。
## plate=true 时在字后垫一块深色圆角衬底（盖在长卷等花哨画面上用）。
func stamp(text: String, pos: Vector2, size: int, pal: String = "gold", hold: float = 0.7, sub: String = "", delay: float = 0.0, plate: bool = false) -> void:
	var p: Array = UI.PAL.get(pal, UI.PAL["gold"])
	var col: Color = p[1]
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.position = pos
	root.z_index = 5  # 字在金币、花瓣等粒子之上
	add_child(root)
	if size >= 200:
		var shade := ColorRect.new()
		shade.color = Color(0, 0, 0, 0.55)
		shade.size = Vector2(1080, size * 1.7 + (80.0 if sub != "" else 0.0))
		shade.position = Vector2(-pos.x, -size * 0.85)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shade.modulate.a = 0.0
		root.add_child(shade)
		var ts := shade.create_tween()
		ts.tween_interval(delay)
		ts.tween_property(shade, "modulate:a", 1.0, 0.12)
	var ry: ColorRect = null
	if not reduce:
		ry = rays(root, Vector2.ZERO, size * 2.4, Color(col.r, col.g, col.b, 0.85))
		ry.modulate.a = 0.0
	var l := UI.impact(text, size, pal)
	root.add_child(l)
	l.reset_size()
	l.position = -l.size * 0.5
	l.pivot_offset = l.size * 0.5
	if plate:
		var pl := Panel.new()
		pl.add_theme_stylebox_override("panel", UI.box(Color(0.05, 0.02, 0.01, 0.58), Color(col.r, col.g, col.b, 0.55), 46, 3))
		pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pl.size = l.size + Vector2(110.0, 24.0 + (size * 0.42 if sub != "" else 0.0))
		pl.position = Vector2(-pl.size.x * 0.5, -l.size.y * 0.5 - 12.0)
		root.add_child(pl)
		root.move_child(pl, l.get_index())
		pl.modulate.a = 0.0
		var tp := pl.create_tween()
		tp.tween_interval(delay + 0.1)
		tp.tween_property(pl, "modulate:a", 1.0, 0.12)
	var s: Control = null
	if sub != "":
		# 副标题放在深色底条里：盖在牌面或长卷上都读得清
		var sl := UI.label(sub, max(34, size / 4), UI.CREAM, "bold")
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", UI.box(Color(0.05, 0.03, 0.02, 0.86), Color(col.r, col.g, col.b, 0.9), 16, 2))
		pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mg := MarginContainer.new()
		mg.add_theme_constant_override("margin_left", 22)
		mg.add_theme_constant_override("margin_right", 22)
		mg.add_theme_constant_override("margin_top", 4)
		mg.add_theme_constant_override("margin_bottom", 6)
		mg.add_child(sl)
		pc.add_child(mg)
		root.add_child(pc)
		pc.reset_size()
		pc.position = Vector2(-pc.size.x * 0.5, l.size.y * 0.5 - size * 0.04)
		pc.modulate.a = 0.0
		s = pc
	l.modulate.a = 0.0
	l.scale = Vector2.ONE if reduce else Vector2(3.2, 3.2)
	var tw := root.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(l, "modulate:a", 1.0, 0.05)
	tw.parallel().tween_property(l, "scale", Vector2(0.9, 0.9), 0.13).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(_stamp_hit.bind(root.get_instance_id(), size, col))
	tw.tween_property(l, "scale", Vector2(1.14, 1.14), 0.07)
	tw.tween_property(l, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if s != null:
		tw.parallel().tween_property(s, "modulate:a", 1.0, 0.12)
	tw.tween_interval(max(0.1, hold))
	tw.tween_property(root, "modulate:a", 0.0, 0.22)
	tw.parallel().tween_property(root, "position:y", pos.y - size * 0.35, 0.22)
	tw.parallel().tween_property(l, "scale", Vector2(1.18, 1.18), 0.22)
	tw.tween_callback(root.queue_free)
	if ry != null:
		var tr := ry.create_tween()
		tr.tween_interval(delay + 0.16)
		tr.tween_property(ry, "modulate:a", 1.0, 0.08)
		tr.tween_interval(max(0.1, hold))
		tr.tween_property(ry, "modulate:a", 0.0, 0.25)


func _stamp_hit(root_id: int, size: int, col: Color) -> void:
	var root := instance_from_id(root_id) as Control
	if root == null or not is_instance_valid(root) or reduce:
		return
	var pos := root.position
	seq("ring", pos, size * 3.2, false, null, col.lightened(0.25), 1.2)
	seq("burst", pos, size * 2.4, false, null, col.lightened(0.4))
	burst(pos, col.lightened(0.35), 36, size * 5.0, 0.6, 420.0, 0.8)
	burst(pos, Color.WHITE, 16, size * 3.2, 0.4, 200.0, 0.5)


## 长卷横穿：一条画带从右侧滑入，画面在带内自左向右展开（春→冬 / 梅→菊 / 风过山水），再从左侧滑出。
## name: seasons / junzi / wind；height 越大演出越隆重。减少动态效果时改为静止淡入淡出。
func scroll(name: String, center_y: float, height: float, dur: float) -> void:
	var tex := TileView.tex("res://assets/fx/scroll_%s.jpg" % name)
	if tex == null:
		return
	var band := Control.new()
	band.clip_contents = true
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.size = Vector2(1080, height)
	band.position = Vector2(0.0 if reduce else 1080.0, center_y - height * 0.5)
	add_child(band)
	var th: float = max(height, 760.0)  # 窄画带只露出画面中段，保证横向有足够的行程
	var tw_px: float = th * tex.get_width() / tex.get_height()
	var pic := TextureRect.new()
	pic.texture = tex
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_SCALE
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.size = Vector2(tw_px, th)
	pic.position = Vector2(0.0, (height - th) * 0.5)
	band.add_child(pic)
	for ey in [0.0, height - 10.0]:
		var dark := ColorRect.new()
		dark.color = Color(0.16, 0.08, 0.02, 1.0)
		dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		band.add_child(UI.place(dark, 0, ey, 1080, 10))
		var edge := ColorRect.new()
		edge.color = UI.GOLD
		edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		band.add_child(UI.place(edge, 0, ey + 3.0, 1080, 4))
	var t := band.create_tween()
	if reduce:
		pic.position.x = -(tw_px - 1080.0) * 0.5
		band.modulate.a = 0.0
		t.tween_property(band, "modulate:a", 1.0, 0.2)
		t.tween_interval(max(0.2, dur - 0.5))
		t.tween_property(band, "modulate:a", 0.0, 0.3)
	else:
		t.tween_property(band, "position:x", 0.0, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		t.tween_interval(max(0.2, dur - 0.62))
		t.tween_property(band, "position:x", -1080.0, 0.32).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
		pic.create_tween().tween_property(pic, "position:x", -(tw_px - 1080.0), dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_callback(band.queue_free)


func float_text(pos: Vector2, text: String, color: Color = UI.GOLD, size: int = 44, dur: float = 0.9, gold: bool = false) -> void:
	var l: Label
	if gold:
		l = UI.impact(text, size, pal_of(color))
	else:
		l = UI.outline(UI.label(text, size, color, "impact"), Color(0.1, 0.05, 0.0, 0.95), max(10, size / 5))
	add_child(l)
	l.reset_size()
	l.position = pos - l.size * 0.5
	l.pivot_offset = l.size * 0.5
	l.scale = Vector2(0.4, 0.4)
	var tw := create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "position:y", l.position.y - 70.0, dur).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.25)
	tw.tween_callback(l.queue_free)


## 元素图里画有固定的示例牌，只裁取不含牌面的区域（火：上半的胡字与烈焰；雷：上方电光）
const EL_REGION := {"fire": Rect2(0.0, 0.0, 1.0, 0.60), "thunder": Rect2(0.0, 0.0, 1.0, 0.42)}

## 中 / 重反馈横幅，自动销毁；调用方用 timer 等待。
func banner(text: String, color: Color, sub: String = "", el: String = "", dur: float = 1.0, y: float = 900.0, size: int = 110) -> void:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.position = Vector2(540, y)
	add_child(root)
	var text_h := size * 1.25 + (64.0 if sub != "" else 0.0)
	var strip := ColorRect.new()
	strip.color = Color(0, 0, 0, 0.62)
	strip.size = Vector2(1080, text_h + 40)
	strip.position = Vector2(-540, -strip.size.y * 0.5)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(strip)
	for edge_y in [strip.position.y, strip.position.y + strip.size.y - 4]:
		var ln := ColorRect.new()
		ln.color = Color(color.r, color.g, color.b, 0.85)
		ln.size = Vector2(1080, 4)
		ln.position = Vector2(-540, edge_y)
		ln.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(ln)
	if EL_REGION.has(el):
		var tex := TileView.tex("res://assets/fx/el_%s.png" % el)
		if tex:
			var rg: Rect2 = EL_REGION[el]
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(rg.position.x * tex.get_width(), rg.position.y * tex.get_height(), rg.size.x * tex.get_width(), rg.size.y * tex.get_height())
			var tr := TextureRect.new()
			tr.texture = at
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_SCALE
			var w := 1080.0
			tr.size = Vector2(w, w * at.region.size.y / at.region.size.x)
			tr.position = Vector2(-w * 0.5, strip.position.y - tr.size.y + 6)
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			root.add_child(tr)
	var l := UI.impact(text, size, pal_of(color))
	root.add_child(l)
	l.reset_size()
	l.position = Vector2(-l.size.x * 0.5, -l.size.y * 0.5 - (30 if sub != "" else 0))
	if sub != "":
		var s := UI.outline(UI.label(sub, 40, UI.CREAM, "bold"), Color(0, 0, 0, 0.9), 8)
		root.add_child(s)
		s.reset_size()
		s.position = Vector2(-s.size.x * 0.5, strip.position.y + strip.size.y - s.size.y - 14)
	root.modulate.a = 0.0
	root.scale = Vector2.ONE if reduce else Vector2(1.35, 1.35)
	var tw := create_tween()
	tw.tween_property(root, "modulate:a", 1.0, 0.12)
	tw.parallel().tween_property(root, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(max(0.1, dur - 0.5))
	tw.tween_property(root, "modulate:a", 0.0, 0.25)
	tw.tween_callback(root.queue_free)


func toast(text: String, y: float = 1262.0, dur: float = 1.5) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.box(Color(0.05, 0.05, 0.04, 0.88), UI.GOLD_DEEP, 22, 2))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := MarginContainer.new()
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 28)
	for side in ["top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 12)
	m.add_child(UI.label(text, 32, UI.CREAM, "bold"))
	p.add_child(m)
	add_child(p)
	p.reset_size()
	p.position = Vector2(540 - p.size.x * 0.5, y)
	p.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.15)
	tw.tween_interval(dur)
	tw.tween_property(p, "modulate:a", 0.0, 0.3)
	tw.tween_callback(p.queue_free)


# ---------- 屏幕级 ----------

func flash(color: Color, dur: float = 0.35, alpha: float = 0.55) -> void:
	if reduce:
		alpha *= 0.35
	_flash.color = Color(color.r, color.g, color.b, alpha)
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", 0.0, dur)


func shake(target: Control, amp: float = 14.0, dur: float = 0.4) -> void:
	if reduce:
		return
	var base := target.position
	var tw := create_tween()
	var steps := int(dur / 0.04)
	for i in steps:
		var k := 1.0 - float(i) / steps
		tw.tween_property(target, "position", base + Vector2(randf_range(-amp, amp), randf_range(-amp, amp)) * k, 0.04)
	tw.tween_property(target, "position", base, 0.04)


## 时刻元素：none / ice（听牌）/ thunder（成牌待胡）/ fire（胡牌）
func set_mood(kind: String) -> void:
	if kind == _mood:
		return
	_mood = kind
	for e in _mood_emitters:
		_stop_emitter(e)
	_mood_emitters = []
	var tint := Color(0, 0, 0, 0)
	var strength := 0.0
	var flicker := 0.0
	var rise_v := 0.0
	match kind:
		"ice":
			tint = UI.ICE; strength = 0.85
		"thunder":
			tint = UI.THUNDER; strength = 0.95; flicker = 1.0
		"fire":
			tint = UI.FIRE; strength = 1.0; flicker = 0.5; rise_v = 1.0
	_edge_mat.set_shader_parameter("tint", tint)
	_edge_mat.set_shader_parameter("flicker", flicker)
	_edge_mat.set_shader_parameter("rise", rise_v)
	var tw := create_tween()
	var cur: float = _edge_mat.get_shader_parameter("strength") if _edge_mat.get_shader_parameter("strength") != null else 0.0
	tw.tween_method(func(v): _edge_mat.set_shader_parameter("strength", v), cur, strength, 0.4)
	if reduce or kind == "none":
		return
	if kind == "ice":
		var p := _particles(Vector2(540, -20), Color(0.8, 0.95, 1.0, 0.8), 26, 5.0)
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		p.emission_rect_extents = Vector2(540, 4)
		p.direction = Vector2(0.2, 1)
		p.spread = 12.0
		p.initial_velocity_min = 90.0
		p.initial_velocity_max = 190.0
		p.gravity = Vector2(0, 30)
		p.scale_amount_min = 0.25
		p.scale_amount_max = 0.6
		p.emitting = true
		_mood_emitters.append(p)
	elif kind == "thunder":
		var p2 := _particles(Vector2(540, 1900), Color(0.75, 0.55, 1.0, 0.9), 22, 2.2)
		p2.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		p2.emission_rect_extents = Vector2(540, 4)
		p2.direction = Vector2(0, -1)
		p2.spread = 8.0
		p2.initial_velocity_min = 300.0
		p2.initial_velocity_max = 700.0
		p2.gravity = Vector2.ZERO
		p2.scale_amount_min = 0.2
		p2.scale_amount_max = 0.5
		p2.emitting = true
		_mood_emitters.append(p2)


## 闪电：从 a 到 b 的折线，闪两下后消失
func bolt(a: Vector2, b: Vector2, color: Color = UI.THUNDER) -> void:
	if reduce:
		return
	var line := Line2D.new()
	line.width = 7.0
	line.default_color = color.lightened(0.5)
	var n := 9
	for i in n + 1:
		var t := float(i) / n
		var p := a.lerp(b, t)
		if i > 0 and i < n:
			p += Vector2(randf_range(-46, 46), randf_range(-14, 14))
		line.add_point(p)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	line.material = mat
	add_child(line)
	var tw := create_tween()
	tw.tween_property(line, "modulate:a", 0.2, 0.06)
	tw.tween_property(line, "modulate:a", 1.0, 0.04)
	tw.tween_property(line, "modulate:a", 0.0, 0.22)
	tw.tween_callback(line.queue_free)


## 墨刃·斩杀：一道由细变粗再收锋的墨痕划过
func slash(a: Vector2, b: Vector2) -> void:
	var line := Line2D.new()
	line.default_color = Color(0.04, 0.04, 0.05, 0.96)
	line.width = 90.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.05))
	curve.add_point(Vector2(0.35, 1.0))
	curve.add_point(Vector2(0.8, 0.55))
	curve.add_point(Vector2(1.0, 0.0))
	line.width_curve = curve
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	add_child(line)
	var mid := (a + b) * 0.5 + (b - a).orthogonal().normalized() * 120.0
	var pts: Array = []
	for i in 25:
		var t := i / 24.0
		pts.append(a.lerp(mid, t).lerp(mid.lerp(b, t), t))
	var dur := 0.05 if reduce else 0.22
	var tw := create_tween()
	tw.tween_method(_slash_step.bind(line, pts), 0.0, 1.0, dur).set_ease(Tween.EASE_IN)
	tw.tween_interval(0.25)
	tw.tween_property(line, "modulate:a", 0.0, 0.35)
	tw.tween_callback(line.queue_free)
	if not reduce:
		for i in 6:
			burst(pts[4 + i * 4], Color(0.05, 0.05, 0.06, 1.0), 6, 260.0, 0.5, 300.0, 0.7)


func _slash_step(k: float, line: Line2D, pts: Array) -> void:
	line.clear_points()
	for i in int(k * 24) + 1:
		line.add_point(pts[i])


## 旋转光芒（金 / 彩虹），返回节点由调用方负责销毁
func rays(parent: Node, center: Vector2, radius: float, color: Color, rainbow: float = 0.0) -> ColorRect:
	var r := ColorRect.new()
	r.size = Vector2(radius * 2.0, radius * 2.0)
	r.position = center - r.size * 0.5
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = RAYS
	m.set_shader_parameter("tint", color)
	m.set_shader_parameter("rainbow", rainbow)
	m.set_shader_parameter("speed", 0.0 if reduce else 0.35)
	r.material = m
	parent.add_child(r)
	return r


# ---------- 序列帧特效（GPT Image 2.6 生成，tools/gen_fx.py 拆帧） ----------

const SEQ_MS := {"wind": 60, "burst": 50, "ice": 60, "thunder": 60, "fire": 70, "light": 80, "goldglow": 70, "petals": 70, "ring": 50, "ink": 50, "coin": 45}
const SEQ_FRAMES := 8


func _seq_frames(name: String) -> SpriteFrames:
	if _seq_cache.has(name):
		return _seq_cache[name]
	var tex := TileView.tex("res://assets/fx/seq_%s.png" % name)
	var sf: SpriteFrames = null
	if tex != null:
		sf = SpriteFrames.new()
		var w := tex.get_width() / SEQ_FRAMES
		for anim in ["once", "loop"]:
			sf.add_animation(anim)
			sf.set_animation_loop(anim, anim == "loop")
			sf.set_animation_speed(anim, 1000.0 / SEQ_MS.get(name, 60))
			for i in SEQ_FRAMES:
				var at := AtlasTexture.new()
				at.atlas = tex
				at.region = Rect2(i * w, 0, w, tex.get_height())
				sf.add_frame(anim, at)
	_seq_cache[name] = sf
	return sf


## 播放一段序列帧。width 为显示宽度（像素）；loop=false 播完自动销毁（hold>0 则停在末帧再淡出）。
## 减少动态效果模式下，一次性特效直接跳过（信息由文字与状态面板承载）。
func seq(name: String, pos: Vector2, width: float, loop: bool = false, parent: Node = null, tint: Color = Color.WHITE, speed: float = 1.0, hold: float = 0.0) -> AnimatedSprite2D:
	if reduce and not loop:
		return null
	var sf := _seq_frames(name)
	if sf == null:
		return null
	var s := AnimatedSprite2D.new()
	s.sprite_frames = sf
	s.position = pos
	var fw := float(sf.get_frame_texture("once", 0).get_width())
	s.scale = Vector2.ONE * (width / fw)
	s.modulate = tint
	if name != "ink":
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		s.material = mat
	if parent == null:
		add_child(s)
	else:
		parent.add_child(s)
	s.speed_scale = 0.0 if (reduce and loop) else speed
	s.play("loop" if loop else "once")
	if not loop:
		s.animation_finished.connect(_seq_end.bind(s, hold))
	return s


func _seq_end(s: AnimatedSprite2D, hold: float) -> void:
	if not is_instance_valid(s):
		return
	if hold <= 0.0:
		s.queue_free()
		return
	var tw := s.create_tween()
	tw.tween_interval(hold)
	tw.tween_property(s, "modulate:a", 0.0, 0.3)
	tw.tween_callback(s.queue_free)


func seq_stop(s: AnimatedSprite2D, fade: float = 0.35) -> void:
	if s == null or not is_instance_valid(s):
		return
	var tw := s.create_tween()
	tw.tween_property(s, "modulate:a", 0.0, fade)
	tw.tween_callback(s.queue_free)


# ---------- 金币 ----------

func _process(delta: float) -> void:
	if _coins.is_empty():
		return
	var keep: Array = []
	for c in _coins:
		var raw = c.node
		if not is_instance_valid(raw):
			continue
		var n: AnimatedSprite2D = raw
		c.vel.y += 2700.0 * delta
		n.position += c.vel * delta
		c.life -= delta
		if c.life < 0.3:
			n.modulate.a = max(0.0, c.life / 0.3)
		if c.life <= 0.0 or n.position.y > 2060.0:
			n.queue_free()
		else:
			keep.append(c)
	_coins = keep


func _coin(pos: Vector2, size: float, parent: Node = null) -> AnimatedSprite2D:
	var sf := _seq_frames("coin")
	if sf == null:
		return null
	var s := AnimatedSprite2D.new()
	s.sprite_frames = sf
	s.position = pos
	s.scale = Vector2.ONE * (size / float(sf.get_frame_texture("loop", 0).get_width()))
	s.speed_scale = randf_range(0.8, 1.7)
	if parent == null:
		add_child(s)
	else:
		parent.add_child(s)
	s.play("loop")
	s.frame = randi() % SEQ_FRAMES
	return s


## 金币喷泉：从 pos 向上喷出，受重力落下
func coin_fountain(pos: Vector2, count: int, power: float = 1600.0, spread: float = 0.8, parent: Node = null) -> void:
	if parent != null and not is_instance_valid(parent):
		return
	if reduce:
		count = max(2, count / 4)
	for i in count:
		var s := _coin(pos + Vector2(randf_range(-30, 30), 0), randf_range(54, 100), parent)
		if s == null:
			return
		var ang := -PI * 0.5 + randf_range(-spread, spread)
		_coins.append({"node": s, "vel": Vector2(cos(ang), sin(ang)) * power * randf_range(0.5, 1.0), "life": 2.3})


## 金币从 a 飞向 b（消除得分飞向积分栏）
func coins_to(a: Vector2, b: Vector2, count: int) -> void:
	if reduce:
		count = min(count, 2)
	for i in count:
		var from := a + Vector2(randf_range(-60, 60), randf_range(-40, 40))
		var s := _coin(from, 58.0)
		if s == null:
			return
		s.modulate.a = 0.0
		var mid := (from + b) * 0.5 + Vector2(randf_range(-220, 220), randf_range(-60, 140))
		var tw := s.create_tween()
		tw.tween_interval(i * 0.045)
		tw.tween_property(s, "modulate:a", 1.0, 0.05)
		tw.tween_method(_coin_step.bind(s, from, mid, b), 0.0, 1.0, 0.55).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.tween_callback(s.queue_free)


func _coin_step(t: float, s: Node2D, a: Vector2, m: Vector2, b: Vector2) -> void:
	s.position = a.lerp(m, t).lerp(m.lerp(b, t), t)

