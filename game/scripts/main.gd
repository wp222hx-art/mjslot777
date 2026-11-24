extends Control
## 主界面：按内核事件逐条演出。先记账、后演出；演出可加速跳过，结束后一律以内核状态刷新面板。

## 布局（1080×1920）：转轴盘面占满宽度作为主角；手牌区是一排 14 张的紧凑牌架。
const PW := 168.0
const PH := 204.0
const TS := Vector2(150, 188)
const CLIP_POS := Vector2(36, 470)
const CLIP_SIZE := Vector2(1008, 816)
const GRID_CENTER := Vector2(540, 878)
const SLOT_TS := Vector2(66, 83)
const SLOT_Y := 1352.0
const BIG_TS := Vector2(46, 58)
const RACK_TS := Vector2(52, 65)
const TOAST_Y := 1226.0

var core := MJCore.new()
var audio: GameAudio
var fx: FX
var overlays: Overlays
var stage: Control
var grid_clip: Control
var views: Array = []
var slot_views: Array = []
var slot_xy: Array = []
var big_views: Array = []
var flower_views: Array = []
var wind_views: Array = []

var busy := false
var auto_on := false
var debug_ui := false
var save_path := "user://save.json"
var shown_points := 0
var points_tween: Tween
var phase := ""  # 当前演出阶段，仅供自动演示截图对齐
var phase_hist: Array = []

var lbl_points: Label
var lbl_level: Label
var lbl_target: Label
var lbl_progress: Label
var lbl_fan: Label
var lbl_coef: Label
var lbl_big: Label
var lbl_big_n: Label
var lbl_hand: Label
var lbl_need: Label
var lbl_state: Label
var lbl_flower: Label
var lbl_wind: Label
var bar_fill: Panel
var big_root: Control
var slot_root: Control
var btn_spin: Button
var btn_zhan: Button
var btn_auto: Button
var btn_minus: Button
var btn_plus: Button
var lbl_cost: Label
var lbl_bet: Label
var lbl_win: Label
var lbl_net: Label
var lbl_fset: Label
var lbl_wset: Label
var spin_win := 0    # 本转已演出的赢分
var spin_stake := 0  # 本转实际扣掉的投注（免费转为 0）
var host_face: TextureRect
var bubble: PanelContainer
var bubble_label: Label
var bubble_tween: Tween
var ting_tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	debug_ui = OS.get_cmdline_user_args().has("debug")
	audio = GameAudio.new()
	add_child(audio)
	_build_background()
	stage = Control.new()
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)
	_build_top()
	_build_target()
	_build_big_track()
	_build_racks()
	_build_grid()
	_build_hand()
	_build_host()
	_build_bottom()
	fx = FX.new()
	add_child(fx)
	overlays = Overlays.new()
	overlays.main = self
	add_child(overlays)

	var demo := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shots="):
			demo = a.substr(6)
		elif a.begins_with("autoplay=") or a == "film":
			demo = a
	if demo != "":
		save_path = "user://demo_save.json"
	var loaded := demo == "" and core.load_save(save_path)
	_apply_settings()
	shown_points = core.total_points
	if core.grid.is_empty():
		_show_idle_grid()
	else:
		_set_grid(core.grid)
	refresh_all()
	audio.start_music()
	if demo != "":
		var d := Demo.new()
		add_child(d)
		if demo == "film":
			d.film(self)
		elif demo.begins_with("autoplay="):
			d.autoplay(self, int(demo.substr(9)))
		else:
			d.run(self, demo)
		return
	if loaded and not core.story_offer.is_empty():
		_resume_story()
	elif loaded and core.state != "pending":
		say("欢迎回来，这一手接着做。", "f_banter", "", 1)
	else:
		say("点「转」开始，先看这局要做什么牌。", "f_call", "", 1)


func _apply_settings() -> void:
	audio.sfx_on = core.settings.sfx
	audio.voice_on = core.settings.voice
	audio.set_music(core.settings.music)
	fx.reduce = core.settings.reduce


# ============ 搭建界面 ============

func _build_background() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/felt.gdshader")
	bg.material = m
	add_child(bg)


func _build_top() -> void:
	UI.panel(stage, Rect2(24, 18, 330, 62), UI.box(Color(0.05, 0.16, 0.12, 0.9), UI.GOLD_DEEP, 30, 2))
	stage.add_child(UI.place(UI.label(MJCore.RULE_PACK + " · 灵感模式", 28, UI.GOLD, "bold"), 46, 30))
	lbl_level = UI.label("", 26, UI.CREAM, "bold")
	stage.add_child(UI.place(lbl_level, 372, 32))
	stage.add_child(UI.place(UI.label("余额", 26, UI.CREAM), 650, 32))
	lbl_points = UI.label("0", 40, UI.GOLD, "bold")
	lbl_points.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stage.add_child(UI.place(lbl_points, 710, 20, 250, 56))
	lbl_points.pivot_offset = Vector2(250, 28)
	var gear := UI.button(stage, "设", Rect2(984, 14, 72, 72), 34)
	gear.pressed.connect(_open_settings)


func _build_target() -> void:
	UI.wood_panel(stage, Rect2(20, 94, 1040, 150))
	stage.add_child(UI.place(UI.label("本局目标  TARGET", 22, UI.CREAM), 44, 100))
	lbl_target = UI.outline(UI.label("点「转」生成目标", 54, UI.GOLD, "kai"), Color(0.1, 0.05, 0.0, 0.9), 8)
	stage.add_child(UI.place(lbl_target, 42, 124))
	lbl_progress = UI.label("成牌进度 0 / 14", 26, UI.CREAM, "bold")
	stage.add_child(UI.place(lbl_progress, 44, 200))
	UI.panel(stage, Rect2(290, 208, 450, 20), UI.box(Color(0, 0, 0, 0.55), UI.GOLD_DEEP, 10, 1))
	bar_fill = UI.panel(stage, Rect2(293, 211, 0, 14), UI.box(UI.GOLD, UI.GOLD, 7, 0))
	UI.panel(stage, Rect2(764, 104, 138, 130), UI.box(Color(0, 0, 0, 0.35), UI.GOLD_DEEP, 12, 2))
	var t1 := UI.label("番种参考", 22, UI.CREAM, "bold")
	t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage.add_child(UI.place(t1, 764, 110, 138, 30))
	lbl_fan = UI.label("—", 28, UI.GOLD, "kai")
	lbl_fan.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_fan.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_fan.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	stage.add_child(UI.place(lbl_fan, 770, 140, 126, 90))
	UI.panel(stage, Rect2(912, 104, 134, 130), UI.box(Color(0, 0, 0, 0.35), UI.GOLD_DEEP, 12, 2))
	var t2 := UI.label("任务系数", 22, UI.CREAM, "bold")
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage.add_child(UI.place(t2, 912, 110, 134, 30))
	lbl_coef = UI.label("—", 54, UI.GOLD, "kai")
	lbl_coef.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_coef.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stage.add_child(UI.place(lbl_coef, 912, 140, 134, 90))


func _build_big_track() -> void:
	UI.green_panel(stage, Rect2(20, 252, 1040, 78))
	stage.add_child(UI.place(UI.label("大牌副线", 22, UI.CREAM, "bold"), 40, 258))
	lbl_big = UI.label("", 30, UI.GOLD, "kai")
	stage.add_child(UI.place(lbl_big, 40, 286))
	big_root = Control.new()
	big_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(UI.place(big_root, 186, 262))
	lbl_big_n = UI.label("0/14", 30, UI.GOLD, "bold")
	lbl_big_n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stage.add_child(UI.place(lbl_big_n, 930, 270, 114, 44))


func _build_racks() -> void:
	UI.green_panel(stage, Rect2(20, 338, 560, 112))
	lbl_flower = UI.label("花架 0/8", 24, UI.CREAM, "bold")
	stage.add_child(UI.place(lbl_flower, 40, 343))
	lbl_fset = UI.label("", 22, UI.GOLD)
	lbl_fset.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stage.add_child(UI.place(lbl_fset, 200, 345, 362, 30))
	for i in 8:
		var t := TileView.make("f%d" % (i + 1), 0, RACK_TS)
		t.position = Vector2(44 + i * 62 + (18 if i >= 4 else 0), 378)
		stage.add_child(t)
		flower_views.append(t)
	UI.green_panel(stage, Rect2(590, 338, 470, 112))
	lbl_wind = UI.label("风位 0/4", 24, UI.CREAM, "bold")
	stage.add_child(UI.place(lbl_wind, 610, 343))
	lbl_wset = UI.label("", 22, UI.GOLD)
	lbl_wset.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stage.add_child(UI.place(lbl_wset, 760, 345, 282, 30))
	for i in 4:
		var w := TileView.make("z%d" % (i + 1), 0, RACK_TS)
		w.position = Vector2(672 + i * 86, 378)
		stage.add_child(w)
		wind_views.append(w)


func _build_grid() -> void:
	UI.wood_panel(stage, Rect2(20, 458, 1040, 840))
	UI.panel(stage, Rect2(28, 466, 1024, 824), UI.box(Color(0.02, 0.11, 0.085, 0.92), Color(0, 0, 0, 0.45), 14, 2))
	grid_clip = Control.new()
	grid_clip.position = CLIP_POS
	grid_clip.size = CLIP_SIZE
	grid_clip.clip_contents = true
	grid_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(grid_clip)
	views.resize(MJCore.COLS * MJCore.ROWS)


func _build_hand() -> void:
	UI.wood_panel(stage, Rect2(20, 1306, 1040, 190))
	lbl_hand = UI.label("目标手牌  HAND  0 / 14", 26, UI.CREAM, "bold")
	stage.add_child(UI.place(lbl_hand, 44, 1312))
	lbl_state = UI.label("", 28, UI.GOLD, "kai")
	lbl_state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stage.add_child(UI.place(lbl_state, 480, 1310, 556, 40))
	slot_root = Control.new()
	slot_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(slot_root)
	lbl_need = UI.label("", 26, UI.CREAM, "bold")
	lbl_need.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage.add_child(UI.place(lbl_need, 30, 1446, 1020, 40))


func _build_host() -> void:
	UI.panel(stage, Rect2(30, 1516, 164, 164), UI.box(Color(0.1, 0.07, 0.04, 1.0), UI.GOLD, 82, 4, 8))
	host_face = TextureRect.new()
	host_face.texture = TileView.tex("res://assets/host/f_call.png")
	host_face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	host_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host_face.pivot_offset = Vector2(76, 76)
	stage.add_child(UI.place(host_face, 36, 1522, 152, 152))
	bubble = PanelContainer.new()
	bubble.add_theme_stylebox_override("panel", UI.box(Color("f1e3c0"), UI.GOLD_DEEP, 18, 3, 6))
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 12)
	bubble_label = UI.label("", 24, UI.INK, "bold")
	bubble_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble_label.custom_minimum_size = Vector2(186, 0)
	m.add_child(bubble_label)
	bubble.add_child(m)
	stage.add_child(UI.place(bubble, 204, 1516, 210, 0))
	bubble.modulate.a = 0.0
	var rec := UI.button(stage, "牌型记录", Rect2(690, 1520, 360, 76), 36)
	rec.pressed.connect(_open_record)
	btn_zhan = UI.button(stage, "斩 · 补最后一张", Rect2(690, 1610, 360, 84), 40)
	btn_zhan.add_theme_stylebox_override("normal", UI.box(Color(0.05, 0.05, 0.06, 0.98), UI.GOLD, 20, 4, 8))
	btn_zhan.add_theme_stylebox_override("hover", UI.box(Color(0.12, 0.12, 0.14, 0.98), UI.CREAM, 20, 4, 8))
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		btn_zhan.add_theme_color_override(k, UI.CREAM)
	btn_zhan.visible = false
	btn_zhan.pressed.connect(_on_zhan)


func _build_bottom() -> void:
	var rules := UI.button(stage, "规则", Rect2(30, 1800, 300, 88), 42)
	rules.pressed.connect(_open_rules)
	btn_auto = UI.button(stage, "自动", Rect2(750, 1800, 300, 88), 42)
	btn_auto.pressed.connect(_toggle_auto)
	if debug_ui:  # 进度每转自动保存；「保存退出」只在调试参数下显示
		var save := UI.button(stage, "保存退出", Rect2(430, 1540, 220, 64), 30)
		save.pressed.connect(_on_save_exit)
	btn_spin = Button.new()
	btn_spin.text = "转"
	btn_spin.focus_mode = Control.FOCUS_NONE
	btn_spin.position = Vector2(425, 1648)
	btn_spin.size = Vector2(230, 230)
	btn_spin.pivot_offset = Vector2(115, 115)
	btn_spin.add_theme_font_override("font", UI.font("kai"))
	btn_spin.add_theme_font_size_override("font_size", 128)
	btn_spin.add_theme_stylebox_override("normal", UI.box(Color("c79a45"), UI.GOLD, 115, 8, 12))
	btn_spin.add_theme_stylebox_override("hover", UI.box(Color("d9ad57"), Color("fff0c0"), 115, 8, 12))
	btn_spin.add_theme_stylebox_override("pressed", UI.box(Color("9c7430"), UI.GOLD, 115, 8, 4))
	btn_spin.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		btn_spin.add_theme_color_override(k, UI.WOOD_DARK)
	stage.add_child(btn_spin)
	btn_spin.pressed.connect(_on_spin)
	# 转按钮上方：这一转要花多少（或还剩几次免费转）
	var pill := UI.panel(stage, Rect2(430, 1622, 220, 46), UI.box(Color(0.10, 0.07, 0.04, 0.97), UI.GOLD, 23, 2))
	lbl_cost = UI.label("", 26, UI.GOLD, "bold")
	lbl_cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pill.add_child(UI.place(lbl_cost, 0, 5, 220, 36))
	# 左：投注档位
	UI.wood_panel(stage, Rect2(30, 1694, 380, 96))
	stage.add_child(UI.place(UI.label("投注  BET", 22, UI.CREAM, "bold"), 48, 1698))
	btn_minus = UI.button(stage, "-", Rect2(42, 1730, 86, 54), 46)
	btn_minus.pressed.connect(_on_bet.bind(-1))
	btn_plus = UI.button(stage, "+", Rect2(312, 1730, 86, 54), 46)
	btn_plus.pressed.connect(_on_bet.bind(1))
	lbl_bet = UI.outline(UI.label("0", 46, UI.GOLD, "impact"), Color(0.1, 0.05, 0.0, 0.95), 8)
	lbl_bet.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_bet.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stage.add_child(UI.place(lbl_bet, 128, 1724, 184, 64))
	lbl_bet.pivot_offset = Vector2(92, 32)
	# 右：这一转赢了多少、净输赢多少
	UI.wood_panel(stage, Rect2(670, 1704, 380, 90))
	stage.add_child(UI.place(UI.label("本转赢分  WIN", 22, UI.CREAM, "bold"), 688, 1712))
	lbl_win = UI.outline(UI.label("0", 44, UI.GOLD, "impact"), Color(0.1, 0.05, 0.0, 0.95), 8)
	lbl_win.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stage.add_child(UI.place(lbl_win, 850, 1698, 186, 54))
	lbl_win.pivot_offset = Vector2(186, 27)
	stage.add_child(UI.place(UI.label("本转净输赢", 22, UI.CREAM, "bold"), 688, 1756))
	lbl_net = UI.label("0", 32, UI.CREAM, "bold")
	lbl_net.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stage.add_child(UI.place(lbl_net, 850, 1748, 186, 42))
	var note := UI.label("虚拟积分 · 不可兑换", 20, Color(1, 1, 1, 0.45))
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage.add_child(UI.place(note, 0, 1892, 1080, 26))
	var tw := create_tween().set_loops()
	tw.tween_property(btn_spin, "scale", Vector2(1.04, 1.04), 0.9).set_trans(Tween.TRANS_SINE)
	tw.tween_property(btn_spin, "scale", Vector2.ONE, 0.9).set_trans(Tween.TRANS_SINE)


func _on_bet(delta: int) -> void:
	if busy or overlays.is_open():
		return
	if core.free_spins > 0:
		fx.toast("免费转期间按触发时的投注进行，不能改投注", TOAST_Y, 1.4)
		return
	if core.change_bet(delta):
		audio.sfx("click")
		core.save(save_path)
		_refresh_bet()
		lbl_bet.scale = Vector2(1.3, 1.3)
		lbl_bet.create_tween().tween_property(lbl_bet, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		audio.sfx("invalid", -8.0)


## 投注栏、转按钮上的消耗提示、花架/风位的集齐奖金额（都按当前投注换算）
func _refresh_bet() -> void:
	var free := core.free_spins > 0
	var b: int = core.free_bet if free and core.free_bet > 0 else core.bet()
	lbl_bet.text = UI.fmt(b)
	lbl_cost.text = ("免费转 ×%d" % core.free_spins) if free else ("每转 -%s" % UI.fmt(b))
	lbl_cost.add_theme_color_override("font_color", UI.FIRE if free else UI.GOLD)
	btn_minus.disabled = free or core.bet_idx <= 0
	btn_plus.disabled = free or core.bet_idx >= MJCore.BETS.size() - 1
	lbl_fset.text = "越快集齐奖越高 · 最高 +%s" % UI.fmt(int(round(MJCore.FLOWER_TIER_X[2] * b)))
	lbl_wset.text = "越快越高 · 最高 +%s" % UI.fmt(int(round(MJCore.WIND_TIER_X[2] * b)))


func _show_win(pop: bool = false) -> void:
	lbl_win.text = UI.fmt(spin_win)
	var net := spin_win - spin_stake
	lbl_net.text = ("+" if net > 0 else "") + UI.fmt(net)
	lbl_net.add_theme_color_override("font_color", Color("7dffa8") if net > 0 else (Color("ff8a78") if net < 0 else UI.CREAM))
	if pop:
		lbl_win.scale = Vector2(1.35, 1.35)
		lbl_win.create_tween().tween_property(lbl_win, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _open_settings() -> void:
	audio.sfx("click")
	overlays.show_settings()

func _open_record() -> void:
	audio.sfx("click")
	overlays.show_record()

func _open_rules() -> void:
	audio.sfx("click")
	overlays.show_rules()


# ============ 坐标 ============

func cell_pos(i: int) -> Vector2:
	return Vector2((i % MJCore.COLS) * PW + (PW - TS.x) * 0.5, (i / MJCore.COLS) * PH + (PH - TS.y) * 0.5)

func cell_center(i: int) -> Vector2:
	return CLIP_POS + cell_pos(i) + TS * 0.5

func slot_pos(i: int) -> Vector2:
	return slot_xy[i] if i < slot_xy.size() else Vector2(30 + i * 72, SLOT_Y)

func slot_center(i: int) -> Vector2:
	return slot_pos(i) + SLOT_TS * 0.5

func big_center(i: int) -> Vector2:
	return big_root.position + Vector2(i * 51, 0) + BIG_TS * 0.5

func rack_center(v: Control) -> Vector2:
	return v.position + RACK_TS * 0.5

func group_center(cells: Array) -> Vector2:
	var c := Vector2.ZERO
	for i in cells:
		c += cell_center(i)
	return c / cells.size()


# ============ 刷新（一律读内核真实状态） ============

func refresh_all() -> void:
	_rebuild_hand()
	_rebuild_big()
	_refresh_progress()
	_refresh_racks()
	_refresh_bet()
	_set_points(core.total_points, false)
	lbl_level.text = "Lv.%d %s" % [core.level() + 1, core.level_name()]
	btn_zhan.visible = core.can_zhan()
	_refresh_mood()


func _refresh_mood() -> void:
	match core.state:
		"ting": fx.set_mood("ice")
		"ready": fx.set_mood("thunder")
		_: fx.set_mood("none")
	_refresh_ting_glow()


## 听牌时缺的那张空槽持续冰蓝呼吸描边，直到补齐（常驻缺牌提示接替动画）
func _refresh_ting_glow() -> void:
	if ting_tween and ting_tween.is_valid():
		ting_tween.kill()
	for i in slot_views.size():
		if core.slots[i] < 0 and core.state == "ting":
			var sv: TileView = slot_views[i]
			sv.set_glow(UI.ICE)
			if not fx.reduce:
				ting_tween = sv.glow.create_tween().set_loops()
				ting_tween.tween_property(sv.glow, "modulate:a", 0.35, 0.6).set_trans(Tween.TRANS_SINE)
				ting_tween.tween_property(sv.glow, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_SINE)
		else:
			slot_views[i].clear_glow()


func _rebuild_hand() -> void:
	for c in slot_root.get_children():
		c.queue_free()
	slot_views = []
	slot_xy = []
	if core.tpl_idx < 0:
		lbl_target.text = "点「转」生成目标"
		lbl_fan.text = "—"
		lbl_coef.text = "—"
		return
	var t := core.tpl()
	lbl_target.text = t.name
	lbl_fan.text = "%s\n%d番" % [t.fan_name, t.fan]
	lbl_coef.text = "×%s" % _num(t.coef)
	# 一排摆开，面子之间留空，直接看出刻子 / 顺子 / 对子的分组
	var n := core.need.size()
	var gaps := core.meld_ranges.size() - 1
	var step := SLOT_TS.x + 4.0
	var gap := clampf((1020.0 - n * step) / max(1, gaps), 6.0, 20.0)
	var total := n * step - 4.0 + gaps * gap
	var x := 540.0 - total * 0.5
	for mi in core.meld_ranges.size():
		var cnt: int = core.meld_ranges[mi][1]
		UI.panel(slot_root, Rect2(x - 5, SLOT_Y - 5, cnt * step - 4 + 10, SLOT_TS.y + 10), UI.box(Color(0, 0, 0, 0.34), Color(0.55, 0.42, 0.2, 0.55), 12, 2))
		for j in cnt:
			slot_xy.append(Vector2(x, SLOT_Y))
			x += step
		x += gap
	for i in n:
		var sv := TileView.make(core.need[i], 0, SLOT_TS)
		sv.position = slot_xy[i]
		slot_root.add_child(sv)
		slot_views.append(sv)
		_show_slot(i, core.slots[i])


func _show_slot(i: int, grade: int) -> void:
	if i >= slot_views.size():
		return
	var sv: TileView = slot_views[i]
	if grade < 0:
		sv.set_symbol(core.need[i], 0)
		sv.set_dim(1.0)
	else:
		sv.set_symbol(core.need[i], grade)
		sv.set_dim(0.0)


func _rebuild_big() -> void:
	for c in big_root.get_children():
		c.queue_free()
	big_views = []
	var b := core.big_tpl()
	lbl_big.text = b.name
	for i in b.tiles.size():
		var v := TileView.make(b.tiles[i], 0, BIG_TS)
		v.position = Vector2(i * 51, 0)
		big_root.add_child(v)
		big_views.append(v)
		v.set_dim(0.0 if core.big.slots[i] else 1.0)
	lbl_big_n.text = "%d/14" % core.big_filled()


func _refresh_progress() -> void:
	var total := core.need.size()
	var f := core.filled()
	if total == 0:
		lbl_progress.text = "成牌进度 0 / 14"
		lbl_hand.text = "目标手牌  HAND  0 / 14"
		lbl_need.text = "每转消耗一次投注 · 消除攒牌，成牌后消出「胡」字结算"
		lbl_state.text = ""
		bar_fill.size.x = 0
		return
	lbl_progress.text = "成牌进度 %d / %d" % [f, total]
	lbl_hand.text = "目标手牌  HAND  %d / %d" % [f, total]
	bar_fill.size.x = 444.0 * f / total
	var miss := core.missing()
	if core.state == "pending" and not core.last_result.is_empty():
		lbl_need.text = "本局已结算 · 再点「转」开启下一手"
		lbl_state.text = "下一局待开启"
	elif miss.is_empty():
		lbl_need.text = "牌已齐，等待消出「胡」字"
		lbl_state.text = "成牌待胡"
	else:
		var parts := []
		for id in miss:
			parts.append("%s×%d" % [MJCore.tile_name(id), miss[id]])
		lbl_need.text = "还缺：" + "  ".join(parts)
		lbl_state.text = ("听 " + MJCore.tile_name(miss.keys()[0])) if core.state == "ting" else "积累中"
	lbl_big_n.text = "%d/14" % core.big_filled()


func _refresh_racks() -> void:
	var fn := 0
	for i in 8:
		flower_views[i].set_dim(0.0 if core.flowers[i] else 1.0)
		if core.flowers[i]: fn += 1
	lbl_flower.text = "花架 %d/8" % fn
	var wn := 0
	for i in 4:
		wind_views[i].set_dim(0.0 if core.winds[i] else 1.0)
		if core.winds[i]: wn += 1
	lbl_wind.text = "风位 %d/4" % wn


func _num(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, round(v)) else str(v)


func _set_points(target: int, animate: bool = true) -> void:
	if points_tween and points_tween.is_valid():
		points_tween.kill()
	if not animate or target == shown_points:
		shown_points = target
		lbl_points.text = UI.fmt(target)
		return
	points_tween = create_tween()
	points_tween.tween_method(_points_step, shown_points, target, 0.5)
	lbl_points.scale = Vector2(1.25, 1.25)
	lbl_points.create_tween().tween_property(lbl_points, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _points_step(v: int) -> void:
	shown_points = v
	lbl_points.text = UI.fmt(v)


# ============ 盘面 ============

func _clear_grid() -> void:
	for i in views.size():
		if views[i] != null and is_instance_valid(views[i]):
			views[i].queue_free()
		views[i] = null


func _set_grid(g: Array) -> void:
	_clear_grid()
	for i in g.size():
		var v := TileView.make(g[i].id, g[i].g, TS)
		v.position = cell_pos(i)
		grid_clip.add_child(v)
		views[i] = v


func _show_idle_grid() -> void:
	var ids := ["m1", "m5", "p5", "s1", "z5", "z6", "z1", "hu", "m9", "wild", "p1", "z2",
		"s5", "p9", "z7", "m3", "hu", "s9", "z3", "f1", "m7", "f8", "p3", "z4"]
	var g := []
	for id in ids:
		g.append({"id": id, "g": 0})
	_set_grid(g)


func _set_phase(name: String) -> void:
	phase = name
	phase_hist.append(name)


func wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


## 转轴：旧牌整列下坠，新牌逐列落下并带回弹，每列落定有一声「咔」
func _play_grid(ev: Dictionary) -> void:
	_set_phase("spin")
	audio.sfx("spin")
	for i in views.size():
		var old = views[i]
		if old == null:
			continue
		var tw: Tween = old.create_tween()
		tw.tween_interval((i % MJCore.COLS) * 0.03)
		tw.tween_property(old, "position:y", old.position.y + 900.0, 0.24).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.tween_callback(old.queue_free)
		views[i] = null
	await wait(0.2)
	var g: Array = ev.grid
	for c in MJCore.COLS:
		for r in MJCore.ROWS:
			var i := r * MJCore.COLS + c
			var v := TileView.make(g[i].id, g[i].g, TS)
			var dst := cell_pos(i)
			v.position = Vector2(dst.x, dst.y - 900.0)
			grid_clip.add_child(v)
			views[i] = v
			var tw2 := v.create_tween()
			tw2.tween_interval(c * 0.09 + (MJCore.ROWS - 1 - r) * 0.035)
			tw2.tween_property(v, "position:y", dst.y, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		get_tree().create_timer(c * 0.09 + 0.3).timeout.connect(audio.sfx.bind("reel_stop", -6.0, 1.0 + c * 0.03))
	await wait(MJCore.COLS * 0.09 + 0.46)
	# 品级牌落定：金光 / 钻石光，提前让玩家看见稀有牌
	for i in g.size():
		if views[i] == null:
			continue
		if g[i].g == 4:
			fx.seq("light", cell_center(i), 330.0)
			audio.sfx("diamond", -10.0)
		elif g[i].g == 3:
			fx.seq("goldglow", cell_center(i) + Vector2(0, -20), 280.0)
		elif g[i].g > 0:
			fx.burst(cell_center(i), UI.ICE if g[i].g == 1 else UI.THUNDER, 12, 220.0, 0.5, 0.0)
	_set_phase("landed")


## 牌从盘面飞向目标：先原地弹起放大，再沿弧线带着风旋和拖尾飞入
func _fly(sym: String, grade: int, from: Vector2, to: Vector2, to_size: Vector2, on_arrive: Callable, color: Color = UI.WIND, vortex: String = "wind", delay: float = 0.0) -> void:
	var v := TileView.make(sym, grade, TS)
	v.position = from - TS * 0.5
	v.scale = Vector2(0.9, 0.9)
	v.modulate.a = 0.0
	fx.add_child(v)
	var end_scale := to_size / TS
	var dur := clampf(from.distance_to(to) / 1500.0, 0.42, 0.62)
	# 控制点偏向一侧并抬高，飞行路线是一道明显的弧
	var side := -1.0 if to.x < from.x else 1.0
	var mid := (from + to) * 0.5 + Vector2(side * 150.0, -180.0 if to.y > from.y else 60.0)
	var tw := v.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_callback(_fly_begin.bind(v, color, vortex))
	tw.tween_property(v, "scale", Vector2(1.22, 1.22), 0.13).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.05)
	tw.tween_method(_fly_step.bind(v, from, mid, to), 0.0, 1.0, dur).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw.parallel().tween_property(v, "scale", end_scale, dur).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(v, "rotation", side * 0.28, dur * 0.5).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(v, "rotation", 0.0, dur * 0.5).set_delay(dur * 0.5).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(_fly_done.bind(v, to, on_arrive, color))


func _fly_begin(v: TileView, color: Color, vortex: String) -> void:
	v.modulate.a = 1.0
	v.flash(0.2)
	var tr := fx.trail(v, color)
	tr.position = TS * 0.5
	if vortex != "":
		var sp := fx.seq(vortex, TS * 0.5, TS.x * 2.3, true, v)
		if sp != null:
			sp.show_behind_parent = true
	audio.sfx("wind", -9.0, randf_range(0.95, 1.15))


func _fly_step(t: float, v: Control, a: Vector2, m: Vector2, b: Vector2) -> void:
	v.position = a.lerp(m, t).lerp(m.lerp(b, t), t) - TS * 0.5


func _fly_done(v: Control, to: Vector2, on_arrive: Callable, color: Color) -> void:
	v.queue_free()
	on_arrive.call()
	fx.seq("ring", to, 190.0, false, null, color.lightened(0.3))
	fx.burst(to, color, 18, 300.0, 0.45, 260.0)
	audio.sfx("slot_in", -3.0, randf_range(0.95, 1.1))


## 落槽：先压扁再回弹，白闪，槽位描边一闪
func _fill_slot_anim(i: int, grade: int) -> void:
	_show_slot(i, grade)
	if i >= slot_views.size():
		return
	var sv: TileView = slot_views[i]
	sv.clear_glow()
	sv.flash(0.35)
	sv.scale = Vector2(1.5, 0.72)
	var tw := sv.create_tween()
	tw.tween_property(sv, "scale", Vector2(0.9, 1.14), 0.09)
	tw.tween_property(sv, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if grade == 4:
		fx.seq("light", slot_center(i), 300.0)
	elif grade == 3:
		fx.seq("goldglow", slot_center(i) + Vector2(0, -30), 240.0)


func _fill_big_anim(i: int) -> void:
	if i < big_views.size():
		var bv: TileView = big_views[i]
		bv.set_dim(0.0)
		bv.flash(0.35)
		bv.scale = Vector2(1.6, 1.6)
		bv.create_tween().tween_property(bv, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	lbl_big_n.text = "%d/14" % core.big_filled()


func _group_color(g: Dictionary) -> Color:
	if g.dest == "hu":
		return Color(1.0, 0.45, 0.3)
	if g.dest == "main":
		return UI.WIND
	if g.dest == "big":
		return UI.GOLD
	return Color(0.85, 0.88, 0.9)


## 一次消除事件的完整演出：
## 高亮描边并提示去向 → 向组心聚拢 → 爆裂消散 → 代表牌飞向手牌槽（或副线 / 风位 / 花架）→ 补落回弹
func _play_step(ev: Dictionary) -> void:
	var chain: int = ev.chain
	_set_phase("highlight")
	# 1. 高亮：成组的牌描边发光、轻轻跳动；同时点亮它要去的槽位
	for g in ev.groups:
		var col := _group_color(g)
		for k in g.cells.size():
			var v: TileView = views[g.cells[k]]
			v.set_glow(col)
			v.z_index = 2
			var tw := v.create_tween()
			tw.tween_interval(k * 0.03)
			tw.tween_property(v, "scale", Vector2(1.13, 1.13), 0.11).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(v, "scale", Vector2(1.05, 1.05), 0.12)
		if g.dest == "main" and g.slot < slot_views.size():
			slot_views[g.slot].set_glow(UI.WIND)
		elif g.dest == "big" and g.slot < big_views.size():
			big_views[g.slot].set_glow(UI.GOLD)
	for f in ev.flowers:
		var fv: TileView = views[f.cell]
		fv.set_glow(Color(1.0, 0.62, 0.78))
		fv.z_index = 2
		fx.seq("petals", cell_center(f.cell), 300.0)
	if not ev.groups.is_empty():
		audio.sfx("match", -2.0, 1.0 + 0.07 * (chain - 1))
		if chain >= 2:
			fx.stamp("连消 ×%d" % chain, GRID_CENTER + Vector2(0, -330), min(110 + chain * 12, 180), "fire", 0.35)
			fx.shake(stage, 5.0 + chain * 2.0, 0.22)
			if chain == 2:
				say("连消！", "f_win", "combo", 1)
			elif chain == 4:
				say("再连！", "f_win", "combo2", 1)
	elif not ev.flowers.is_empty():
		audio.sfx("flower", -4.0)
	await wait(0.36)

	# 2. 聚拢：同组的牌向组心收拢并白闪
	_set_phase("gather")
	for g in ev.groups:
		var gc_local := group_center(g.cells) - CLIP_POS - TS * 0.5
		for ci in g.cells:
			var v2: TileView = views[ci]
			var tw2 := v2.create_tween()
			tw2.tween_property(v2, "position", v2.position.lerp(gc_local, 0.42), 0.13).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	await wait(0.13)

	# 3. 爆裂 + 去向
	_set_phase("burst")
	var got_main := false
	var got_grade := 0
	var n_fly := 0
	for g in ev.groups:
		var gc := group_center(g.cells)
		var kind: String = g.kind
		var col2 := _group_color(g)
		fx.seq("burst", gc, 420.0, false, null, Color.WHITE if g.dest != "hu" else Color(1.0, 0.6, 0.45))
		for ci in g.cells:
			fx.burst(cell_center(ci), col2.lightened(0.3), 10, 300.0, 0.45, 520.0, 0.45)
		if g.pts > 0:
			fx.float_text(gc + Vector2(0, -96), "+%d" % g.pts, UI.GOLD, 64, 0.9, true)
			fx.coins_to(gc, Vector2(900, 48), clampi(g.cells.size() + chain, 3, 9))
			get_tree().create_timer(0.6).timeout.connect(audio.sfx.bind("coin", -8.0, randf_range(0.95, 1.2)))
		if g.dest == "main":
			got_main = true
			got_grade = max(got_grade, g.g)
			_fly(kind, g.g, gc, slot_center(g.slot), SLOT_TS, _fill_slot_anim.bind(g.slot, g.g), UI.WIND, "wind", n_fly * 0.07)
			n_fly += 1
		elif g.dest == "big":
			_fly(kind, 0, gc, big_center(g.slot), BIG_TS, _fill_big_anim.bind(g.slot), UI.GOLD, "", n_fly * 0.07)
			n_fly += 1
		elif g.dest == "hu":
			audio.sfx("hu_symbol")
			fx.seq("ring", gc, 520.0, false, null, Color(1.0, 0.5, 0.35))
			fx.burst(gc, UI.RED.lightened(0.3), 34, 460.0, 0.6, 200.0, 0.9)
		if g.wind >= 0:
			var wi: int = g.wind
			_fly(kind, 0, gc, rack_center(wind_views[wi]), RACK_TS, _wind_arrive.bind(wi), Color(0.7, 1.0, 0.9), "wind", n_fly * 0.07)
			n_fly += 1
	for f in ev.flowers:
		var fi: int = f.idx
		if f.new:
			_fly(f.id, 0, cell_center(f.cell), rack_center(flower_views[fi]), RACK_TS, _flower_arrive.bind(fi), Color(1.0, 0.7, 0.8), "petals", n_fly * 0.07)
			n_fly += 1
		else:
			fx.float_text(cell_center(f.cell) + Vector2(0, -60), "+%d" % f.pts, Color(1.0, 0.75, 0.85), 44)
	for ci in ev.removed:
		var v3: TileView = views[ci]
		views[ci] = null
		v3.clear_glow()
		var tw3 := v3.create_tween()
		tw3.tween_property(v3, "scale", Vector2(1.3, 1.3), 0.06)
		tw3.tween_property(v3, "scale", Vector2(0.05, 0.05), 0.16).set_ease(Tween.EASE_IN)
		tw3.parallel().tween_property(v3, "modulate:a", 0.0, 0.16)
		tw3.tween_callback(v3.queue_free)
	audio.sfx("pop", -5.0)
	_set_points(shown_points + ev.pts)
	if ev.pts > 0:
		spin_win += int(ev.pts)
		_show_win(true)
	await wait(0.2)
	_set_phase("fly")
	await wait(0.12)

	# 4. 补落：留下的牌下坠，新牌从上方落入，带回弹
	var g2: Array = ev.grid
	var moved := false
	for c in MJCore.COLS:
		var keep := []
		for r in range(MJCore.ROWS - 1, -1, -1):
			var i := r * MJCore.COLS + c
			if views[i] != null:
				keep.append(views[i])
		var fresh := MJCore.ROWS - keep.size()
		for r in range(MJCore.ROWS - 1, -1, -1):
			var i2 := r * MJCore.COLS + c
			var k := MJCore.ROWS - 1 - r
			var dst := cell_pos(i2)
			var v4: TileView
			if k < keep.size():
				v4 = keep[k]
			else:
				v4 = TileView.make(g2[i2].id, g2[i2].g, TS)
				v4.position = Vector2(dst.x, -PH * (fresh - (k - keep.size())))
				grid_clip.add_child(v4)
			views[i2] = v4
			if not v4.position.is_equal_approx(dst):
				moved = true
				var dist: float = dst.y - v4.position.y
				var tw4 := v4.create_tween()
				tw4.tween_interval(k * 0.025)
				tw4.tween_property(v4, "position", dst, clampf(0.16 + dist / 2600.0, 0.2, 0.42)).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	if moved:
		audio.sfx("drop", -8.0)
	await wait(0.46)
	_set_phase("settled")
	_refresh_progress_shown(ev.filled)

	if got_main:
		if got_grade == 4:
			audio.sfx("diamond")
			say("钻石牌！", "f_win", "diamond", 3)
		elif got_grade == 3:
			audio.sfx("wild", -4.0)
			say("黄金牌！", "f_win", "gold", 2)
		elif ev.melds.is_empty() and randf() < 0.3:  # 普通进牌只偶尔喊一声
			var k2 := randi_range(0, 2)
			say(["进了！", "好牌！", "漂亮！"][k2], "f_banter", "in%d" % (k2 + 1), 0)
	await _play_melds(ev.melds)
	for b in ev.bonus:
		await _play_bonus(b)


## 花架 / 风位集齐：一幅长卷横穿屏幕，雅称盖章，再派奖。
## 档位由内核按「从第一张到集齐用了几转」判定：0 普通（窄画带、短）/ 1 快（半屏）/ 2 极快（整个盘面、金币喷泉）。
func _play_bonus(b: Dictionary) -> void:
	var is_fl: bool = b.kind == "flower"
	var tier: int = int(b.tier)
	var rack: Array = []
	var art := "wind"
	var key := "wind"
	if is_fl:
		for k in 4:
			rack.append(flower_views[int(b.set) * 4 + k])
		art = "seasons" if int(b.set) == 0 else "junzi"
		key = "flower%d" % int(b.set)
	else:
		rack = wind_views.duplicate()
	var col := Color(1.0, 0.62, 0.78) if is_fl else UI.WIND
	var sq := "petals" if is_fl else "wind"
	var dur: float = [1.7, 2.4, 3.1][tier]
	var band_h: float = [300.0, 540.0, 860.0][tier]
	_set_phase("bonus")
	audio.sfx("levelup", -5.0 + tier * 2.5)
	audio.sfx("flower" if is_fl else "wind", -2.0)
	if tier == 2:
		audio.sfx("big_win", -4.0)
	fx.flash(col, 0.45, 0.2 + tier * 0.12)
	if tier > 0:
		fx.shake(stage, 5.0 + tier * 5.0, 0.3)
	for k in rack.size():
		var rv: TileView = rack[k]
		rv.set_dim(0.0)
		rv.set_glow(col)
		rv.z_index = 3
		var tr := rv.create_tween()
		tr.tween_interval(k * 0.08)
		tr.tween_property(rv, "scale", Vector2(1.7, 1.7), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tr.tween_callback(rv.flash.bind(0.3))
		tr.tween_interval(dur - 0.7)
		tr.tween_property(rv, "scale", Vector2.ONE, 0.2)
		fx.seq(sq, rack_center(rv), 260.0)
	fx.scroll(art, GRID_CENTER.y, band_h, dur)
	# 花瓣 / 风涡随画带一路飘过
	for k in 2 + tier * 3:
		var pp := Vector2(1000.0 - k * (880.0 / (1 + tier * 3)), GRID_CENTER.y + randf_range(-0.38, 0.38) * band_h)
		get_tree().create_timer(0.2 + k * 0.26).timeout.connect(fx.seq.bind(sq, pp, 360.0 + tier * 150.0))
	var nm := String(b.name)
	var sz: int = min([124, 164, 199][tier], int(880.0 / nm.length()))
	fx.stamp(nm, Vector2(540, GRID_CENTER.y - 30.0), sz, "gold" if is_fl else "jade", dur - 0.95,
		"%d 转集齐  集齐奖 ×%s  +%s" % [int(b.spins), _num(b.x), UI.fmt(b.pts)], 0.3, true)
	if tier > 0:
		fx.coin_fountain(Vector2(540, GRID_CENTER.y + band_h * 0.5), 12 + tier * 16, 1400.0 + tier * 250.0, 0.9)
	if tier == 2:
		get_tree().create_timer(1.2).timeout.connect(fx.coin_fountain.bind(Vector2(540, GRID_CENTER.y + band_h * 0.5), 30, 1900.0, 1.1))
		get_tree().create_timer(1.2).timeout.connect(fx.flash.bind(UI.GOLD, 0.4, 0.3))
	get_tree().create_timer(0.6).timeout.connect(fx.coins_to.bind(GRID_CENTER, Vector2(900, 48), 5 + tier * 2))
	_set_points(shown_points + b.pts)
	spin_win += int(b.pts)
	_show_win(true)
	say(nm + "！", "f_win", "bonus_%s_%d" % [key, tier], 2 + (1 if tier == 2 else 0))
	await wait(dur + 0.1)
	for rv2 in rack:
		rv2.clear_glow()
		rv2.z_index = 0
	_refresh_racks()


func _wind_arrive(i: int) -> void:
	wind_views[i].set_dim(0.0)
	wind_views[i].flash(0.3)
	var n := 0
	for k in 4:
		if core.winds[k] or k == i: n += 1
	lbl_wind.text = "风位 %d/4" % min(n, 4)


func _flower_arrive(i: int) -> void:
	flower_views[i].set_dim(0.0)
	flower_views[i].flash(0.3)
	audio.sfx("flower", -6.0)


func _refresh_progress_shown(f: int) -> void:
	var total := core.need.size()
	lbl_progress.text = "成牌进度 %d / %d" % [f, total]
	lbl_hand.text = "目标手牌  HAND  %d / %d" % [f, total]
	create_tween().tween_property(bar_fill, "size:x", 444.0 * f / total, 0.25)
	lbl_big_n.text = "%d/14" % core.big_filled()


## 顺子 / 刻子成组：轻反馈，只庆祝一次；不声称发生了真实吃碰
func _play_melds(melds: Array) -> void:
	var idx := 0
	for m in melds:
		var start: int = m.start
		var n: int = m.n
		for j in n:
			if start + j < slot_views.size():
				var sv: TileView = slot_views[start + j]
				var y0: float = slot_pos(start + j).y
				var tw := sv.create_tween()
				tw.tween_interval(j * 0.07)
				tw.tween_property(sv, "position:y", y0 - 20.0, 0.08)
				tw.tween_property(sv, "position:y", y0, 0.12).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
				get_tree().create_timer(j * 0.07 + 0.08).timeout.connect(audio.sfx.bind("clack", -5.0, 1.0 + j * 0.05))
		var mid := (slot_center(start) + slot_center(start + n - 1)) * 0.5
		# 短喊：刻子=碰、顺子=吃、对子=对（收集模式下的成组反馈，每组只喊一次）
		var info: Array = {"刻子成组": ["碰", "peng", "fire"], "顺子成组": ["吃", "chi", "jade"]}.get(m.label, ["对", "dui", "gold"])
		var col: Color = UI.PAL[info[2]][1]
		for j in n:
			if start + j < slot_views.size():
				var sv2: TileView = slot_views[start + j]
				sv2.set_glow(col)
				get_tree().create_timer(1.1).timeout.connect(sv2.clear_glow)
		fx.seq("ring", mid, 420.0, false, null, col)
		fx.flash(col, 0.25, 0.16)
		fx.shake(stage, 6.0, 0.18)
		fx.stamp(info[0], Vector2(clampf(mid.x, 170.0, 910.0), mid.y - 200.0), 200, info[2], 0.5, "", idx * 0.32)
		say(info[0] + "！", "f_call", info[1], 2)
		idx += 1
	# 等喊话字播完再进下一段（听牌、剧情等），避免两个大字叠在一起
	if idx > 0:
		await wait(0.85 + (idx - 1) * 0.32)


# ============ 事件演出 ============

func play(events: Array) -> void:
	for ev in events:
		match ev.t:
			"new_hand":
				_rebuild_hand()
				_refresh_progress()
				fx.set_mood("none")
				audio.sfx("story", -6.0)
				fx.seq("ring", GRID_CENTER, 900.0, false, null, UI.GOLD)
				fx.banner(ev.name, UI.GOLD, "新目标 · %s %d番 · 任务系数 ×%s" % [ev.fan_name, ev.fan, _num(ev.coef)], "", 1.2, GRID_CENTER.y, 110)
				# 目标牌架逐张亮相
				for i in slot_views.size():
					var sv: TileView = slot_views[i]
					sv.scale = Vector2.ZERO
					var tw := sv.create_tween()
					tw.tween_interval(0.25 + i * 0.03)
					tw.tween_property(sv, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				say("这局做%s！%d番！" % [ev.name, ev.fan], "f_call", "start_" + String(ev.id), 2)
				await wait(0.9)
			"supply":
				audio.sfx("coin")
				fx.toast("余额不足 · 免费补给 +%s" % UI.fmt(int(ev.pts)), TOAST_Y, 1.8)
				_set_points(shown_points + int(ev.pts))
			"bet_down":
				fx.toast("余额不足 · 投注自动降为 %s" % UI.fmt(int(ev.bet)), TOAST_Y, 1.8)
			"stake":
				spin_win = 0
				spin_stake = 0 if ev.free else int(ev.bet)
				_show_win()
				lbl_bet.text = UI.fmt(int(ev.bet))
				if ev.free:
					lbl_cost.text = "免费转中 · 剩 %d" % int(ev.free_left)
					lbl_cost.add_theme_color_override("font_color", UI.FIRE)
					fx.float_text(Vector2(540, 1590), "免费转", UI.FIRE, 64, 0.7, true)
				else:
					lbl_cost.text = "每转 -%s" % UI.fmt(int(ev.bet))
					lbl_cost.add_theme_color_override("font_color", UI.GOLD)
					fx.float_text(Vector2(835, 112), "-%s" % UI.fmt(int(ev.bet)), Color("ff8a78"), 44, 0.7)
				_set_points(int(ev.balance))
			"win":
				spin_win = int(ev.win)
				_show_win(spin_win > 0)
			"free_award":
				_set_phase("free")
				audio.sfx("levelup")
				fx.flash(UI.FIRE, 0.4, 0.3)
				fx.stamp("免费转 +%d" % int(ev.n), GRID_CENTER, 200, "fire", 1.1, "%s · 免费转期间消除赔率 ×%d" % [ev.reason, MJCore.FREE_CLEAR_MULT])
				fx.coin_fountain(Vector2(540, 1700), 30, 1900.0, 0.7)
				_refresh_bet()
				await wait(1.6)
			"grid":
				await _play_grid(ev)
			"step":
				await _play_step(ev)
			"aid":
				fx.toast("连续 %d 转未进牌 · 关键牌援助：%s" % [MJCore.AID_DRY_SPINS, MJCore.tile_name(ev.id)], TOAST_Y, 2.0)
				say("送你一张！", "f_banter", "aid", 2)
				_fly(ev.id, 0, Vector2(112, 1598), slot_center(ev.slot), SLOT_TS, _fill_slot_anim.bind(ev.slot, 0))
				await wait(0.9)
				_refresh_progress_shown(ev.filled)
				await _play_melds(ev.melds)
			"big_ms":
				audio.sfx("coin")
				fx.seq("goldglow", Vector2(540, 270), 300.0)
				fx.toast("大牌副线 · %s %s %d/14" % [ev.name, ev.label, ev.n], 340.0, 1.6)
				if ev.label == "听牌":
					say("大牌听牌了！", "f_win", "big_ting", 2)
			"ting":
				await _play_ting(ev)
			"ready":
				fx.set_mood("thunder")
				_refresh_progress()
				_refresh_ting_glow()
				btn_zhan.visible = false
				if not ev.merged:
					await _play_ready()
			"hu_void":
				if ev.filled >= ev.total - 1:
					audio.sfx("invalid", -4.0)
					fx.toast("「胡」字出现，但手牌 %d/%d 未齐 · 不结算、不扣牌、不储存" % [ev.filled, ev.total], TOAST_Y, 2.2)
					say("牌没齐，不算！", "f_banter", "hu_invalid", 2)
					await wait(0.6)
			"settle":
				# 胡牌分在结算页数完后立刻记进本转赢分，不等整转结束
				spin_win += int(ev.result.hu_pts) + int(ev.result.story_pts)
				await _play_settle(ev.result)
				_show_win(true)
			"big_hu":
				_rebuild_big()
				spin_win += int(ev.pts)
				await overlays.show_big_hand(ev)
				_set_points(core.total_points)
				_show_win(true)
			"story":
				await wait(0.3)
				var choice: int = await overlays.show_story(ev.offer)
				await play(core.choose_story(choice))
				core.save(save_path)
			"story_gold":
				audio.sfx("wild")
				fx.seq("goldglow", GRID_CENTER, 520.0)
				_fly(ev.id, 3, GRID_CENTER, slot_center(ev.slot), SLOT_TS, _fill_slot_anim.bind(ev.slot, 3), UI.GOLD, "")
				say("黄金牌！", "f_win", "gold", 2)
				await wait(0.95)
				_refresh_progress_shown(ev.filled)
				await _play_melds(ev.melds)
			"story_skill":
				fx.toast("获得「斩」· 听牌时可主动补最后一张（不替代「胡」字）", TOAST_Y, 2.2)
				btn_zhan.visible = core.can_zhan()
			"zhan":
				await _play_zhan(ev)


## 听的那张是否在对子（将牌）里 → 单钓
func _is_pair_wait() -> bool:
	for i in core.need.size():
		if core.slots[i] < 0:
			for mr in core.meld_ranges:
				if i >= mr[0] and i < mr[0] + mr[1]:
					return mr[1] == 2
	return false


## 冰 · 听牌（中反馈）：缺张空槽结冰描边，冰晶从盘面中心炸开
func _play_ting(ev: Dictionary) -> void:
	_set_phase("ting")
	fx.set_mood("ice")
	audio.sfx("ting")
	fx.flash(UI.ICE, 0.5, 0.32)
	var nm := MJCore.tile_name(ev.id)
	fx.seq("ice", GRID_CENTER + Vector2(0, -150), 760.0, false, null, Color.WHITE, 0.8)
	fx.seq("ice", GRID_CENTER + Vector2(-330, 120), 420.0, false, null, Color.WHITE, 0.9)
	fx.seq("ice", GRID_CENTER + Vector2(330, 120), 420.0, false, null, Color.WHITE, 0.9)
	fx.shake(stage, 9.0, 0.3)
	fx.stamp("听牌", GRID_CENTER + Vector2(0, -150), 250, "ice", 1.1, ("单钓" if _is_pair_wait() else "就差") + nm)
	# 亮出等的那张牌，再落到它的空槽上：一眼看出差的是哪张、要补到哪里
	var miss_i := -1
	for i in slot_views.size():
		if core.slots[i] < 0:
			miss_i = i
			fx.seq("ice", slot_center(i), 300.0)
	var want := TileView.make(String(ev.id), 0, TS)
	fx.add_child(want)
	want.position = GRID_CENTER + Vector2(-TS.x * 0.5, 130.0)
	want.scale = Vector2.ZERO
	want.set_glow(UI.ICE)
	var tw_w := want.create_tween()
	tw_w.tween_interval(0.3)
	tw_w.tween_property(want, "scale", Vector2(1.3, 1.3), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw_w.tween_interval(0.8)
	if miss_i >= 0:
		tw_w.tween_property(want, "position", slot_center(miss_i) - TS * 0.5, 0.3).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw_w.parallel().tween_property(want, "scale", Vector2.ONE * (SLOT_TS.x / TS.x), 0.3)
	tw_w.tween_property(want, "modulate:a", 0.0, 0.25)
	tw_w.tween_callback(want.queue_free)
	# 整排手牌依次顶起来一下：牌要上来了
	for i in slot_views.size():
		var sv: TileView = slot_views[i]
		var y0: float = slot_pos(i).y
		var tws := sv.create_tween()
		tws.tween_interval(0.22 + i * 0.035)
		tws.tween_property(sv, "position:y", y0 - 24.0, 0.09).set_ease(Tween.EASE_OUT)
		tws.tween_callback(sv.flash.bind(0.25))
		tws.tween_property(sv, "position:y", y0, 0.18).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	# 报出听的是哪张：缺的是将牌 / 对子 → 单钓；否则 → 就差
	var dan := _is_pair_wait()
	say(("听牌！单钓%s！" if dan else "听牌！就差%s！") % nm, "f_call", ("ting_dan_" if dan else "ting_") + String(ev.id), 3)
	_refresh_progress()
	_refresh_ting_glow()
	btn_zhan.visible = core.can_zhan()
	if btn_zhan.visible:
		btn_zhan.pivot_offset = btn_zhan.size * 0.5
		btn_zhan.scale = Vector2(1.25, 1.25)
		btn_zhan.create_tween().tween_property(btn_zhan, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await wait(1.7)


## 雷 · 成牌待胡（中反馈）：三道闪电劈下，整排手牌过电
func _play_ready() -> void:
	_set_phase("ready")
	audio.sfx("thunder")
	fx.flash(UI.THUNDER, 0.5, 0.4)
	fx.shake(stage, 10.0, 0.35)
	fx.seq("thunder", Vector2(250, 800), 520.0, false, null, Color.WHITE, 0.85)
	fx.seq("thunder", Vector2(830, 800), 520.0, false, null, Color.WHITE, 0.85)
	fx.seq("thunder", Vector2(540, 900), 640.0, false, null, Color.WHITE, 0.7)
	for i in slot_views.size():
		var sv: TileView = slot_views[i]
		var y0: float = slot_pos(i).y
		var tw := sv.create_tween()
		tw.tween_interval(0.25 + i * 0.025)
		tw.tween_callback(sv.flash.bind(0.3))
		tw.tween_property(sv, "position:y", y0 - 12.0, 0.06)
		tw.tween_property(sv, "position:y", y0, 0.1)
	fx.stamp("成牌待胡", GRID_CENTER + Vector2(0, -60), 200, "thunder", 0.9, "牌已齐，等待消出「胡」字")
	say("牌齐了！等胡！", "f_call", "ready", 3)
	await wait(1.1)


## 火 · 胡牌（重反馈）：像一段镜头，全程不叠字 ——
## 已成的面子升到台面排成一行 → 一只手抓着最后一组牌入镜，在正中悬停蓄力 → 「啪」地拍下，
## 震屏、火起、金币四溅 → 「胡」字印章盖下 → 鎏金牌型与番数亮出 → 进入结算页。
func _play_settle(r: Dictionary) -> void:
	_set_phase("hu")
	fx.set_mood("fire")
	audio.duck(true)
	var cine := Control.new()
	cine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx.add_child(cine)
	cine.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.015, 0.0, 0.0)
	dim.size = Vector2(1080, 1920)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cine.add_child(dim)
	dim.create_tween().tween_property(dim, "color:a", 0.86, 0.25)

	# 1. 已成的面子从牌架升到台面，排成一行；最后一组留给手来拍
	var row_ts := Vector2(78, 98)
	var win_ts := Vector2(128, 160)
	var row_y := 1010.0
	var last: Array = core.meld_ranges[-1]
	var first_n: int = last[0]
	var step := row_ts.x + 4.0
	var n_gaps: int = core.meld_ranges.size() - 2
	var gap := clampf((1060.0 - first_n * step) / max(1, n_gaps), 4.0, 16.0)
	var x := 540.0 - (first_n * step - 4.0 + n_gaps * gap) * 0.5
	var row: Array = []
	var k := 0
	for mi in core.meld_ranges.size() - 1:
		for j in core.meld_ranges[mi][1]:
			var t := TileView.make(r.need[k], int(r.slots[k]), row_ts)
			t.position = slot_center(k) - row_ts * 0.5
			t.scale = SLOT_TS / row_ts
			cine.add_child(t)
			row.append(t)
			var tw := t.create_tween().set_parallel(true)
			tw.tween_property(t, "position", Vector2(x, row_y), 0.32).set_delay(k * 0.014).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(t, "scale", Vector2.ONE, 0.32).set_delay(k * 0.014)
			x += step
			k += 1
		x += gap
	audio.sfx("wind", -3.0, 0.8)
	await wait(0.4)

	# 2. 手抓着最后一组牌入镜：冲到正中上方 → 再抬高一点蓄力 → 猛地拍下
	var cnt: int = last[1]
	var win_step := win_ts.x + 6.0
	var win_pos := Vector2(540.0 - (cnt * win_step - 6.0) * 0.5, 770.0)
	var grab := Control.new()
	grab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cine.add_child(grab)
	var held: Array = []
	for j in cnt:
		var ht := TileView.make(r.need[first_n + j], int(r.slots[first_n + j]), win_ts)
		ht.position = win_pos + Vector2(j * win_step, 0)
		grab.add_child(ht)
		held.append(ht)
	var hand := TextureRect.new()
	hand.texture = TileView.tex("res://assets/fx/hand.png")
	hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hand.size = Vector2(460, 690)
	hand.pivot_offset = Vector2(230, 656)  # 指尖
	hand.scale = Vector2(1.3, 1.3)
	hand.rotation = 0.22
	hand.position = Vector2(540, win_pos.y + 54) - hand.pivot_offset
	grab.add_child(hand)
	grab.position = Vector2(330, -1400)
	_set_phase("hu_hand")
	audio.sfx("wind", -2.0, 1.25)
	var gt := grab.create_tween()
	gt.tween_property(grab, "position", Vector2(46, -210), 0.24).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	gt.tween_property(grab, "position", Vector2(62, -270), 0.17).set_ease(Tween.EASE_OUT)
	gt.tween_property(grab, "position", Vector2.ZERO, 0.08).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_EXPO)
	await gt.finished

	# 3. 啪！
	_set_phase("hu_slam")
	audio.sfx("clack", 6.0, 0.62)
	audio.sfx("hu")
	audio.sfx("fire", -6.0)
	var impact := Vector2(540, win_pos.y + win_ts.y * 0.5)
	# 火放在牌和字的后面，不压住牌面与标题
	for f in [fx.seq("fire", Vector2(540, 1640), 1180.0, true, cine), fx.seq("fire", Vector2(540, 1430), 1180.0, true, cine, Color(1, 1, 1, 0.55), 1.25)]:
		if f != null:
			cine.move_child(f, 1)
	fx.seq("burst", impact, 1000.0, false, cine, Color(1.0, 0.85, 0.6), 0.8)
	fx.seq("ring", impact, 1300.0, false, cine, Color(1.0, 0.75, 0.35))
	fx.seq("ring", impact, 720.0, false, cine, Color.WHITE, 1.4)
	var fl := ColorRect.new()
	fl.color = Color(1.0, 0.96, 0.82, 0.5)
	fl.size = Vector2(1080, 1920)
	fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cine.add_child(fl)
	var ft := fl.create_tween()
	ft.tween_property(fl, "color:a", 0.0, 0.3)
	ft.tween_callback(fl.queue_free)
	fx.coin_fountain(impact, 34, 1750.0, 1.25, cine)
	cine.move_child(grab, -1)  # 手和拍下的牌始终在特效之上
	fx.shake(stage, 26.0, 0.5)
	fx.shake(cine, 20.0, 0.45)
	fx.burst(impact, Color(1.0, 0.85, 0.5), 60, 900.0, 0.8, 900.0, 0.9)
	for ht in held:
		ht.set_glow(UI.GOLD)
		ht.flash(0.3)
		ht.scale = Vector2(1.22, 0.8)
		var hs: Tween = ht.create_tween()
		hs.tween_property(ht, "scale", Vector2(0.94, 1.08), 0.08)
		hs.tween_property(ht, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	# 台面上的一行牌被震得从中间向两侧跳起
	for i in row.size():
		var tr: TileView = row[i]
		var d: float = abs(i - (row.size() - 1) * 0.5)
		var tj := tr.create_tween()
		tj.tween_interval(d * 0.02)
		tj.tween_callback(tr.flash.bind(0.25))
		tj.tween_property(tr, "position:y", row_y - 44.0 + d * 3.0, 0.09).set_ease(Tween.EASE_OUT)
		tj.tween_property(tr, "position:y", row_y, 0.22).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	say("胡了！%s！%d番！" % [r.name, r.fan], "f_win", "hu_" + String(r.id), 4)
	# 手抬走
	var lift := hand.create_tween()
	lift.tween_interval(0.24)
	lift.tween_property(hand, "position", hand.position + Vector2(380, -1500), 0.34).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	lift.tween_callback(hand.queue_free)
	await wait(0.44)

	# 4. 「胡」字印章盖下
	var seal := TextureRect.new()
	seal.texture = TileView.tex("res://assets/ui/hu.png")
	seal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seal.size = Vector2(300, 300)
	seal.position = Vector2(390, 400)
	seal.pivot_offset = Vector2(150, 150)
	seal.scale = Vector2(3.4, 3.4)
	seal.rotation = -0.5
	seal.modulate.a = 0.0
	cine.add_child(seal)
	var st := seal.create_tween().set_parallel(true)
	st.tween_property(seal, "scale", Vector2.ONE, 0.13).set_ease(Tween.EASE_IN)
	st.tween_property(seal, "rotation", -0.08, 0.13)
	st.tween_property(seal, "modulate:a", 1.0, 0.06)
	await wait(0.13)
	audio.sfx("hu_symbol", 2.0)
	fx.shake(cine, 12.0, 0.25)
	fx.seq("ring", Vector2(540, 550), 820.0, false, cine, Color(1.0, 0.5, 0.3))
	fx.burst(Vector2(540, 550), Color(1.0, 0.5, 0.3), 40, 700.0, 0.6, 300.0, 0.9)
	await wait(0.2)

	# 5. 鎏金牌型 + 番数
	_set_phase("hu_title")
	fx.coin_fountain(Vector2(540, 1260), 26, 1500.0, 1.0, cine)
	var title := UI.impact(r.name, 112, "gold")
	cine.add_child(title)
	title.reset_size()
	title.position = Vector2(540 - title.size.x * 0.5, 1140)
	title.pivot_offset = title.size * 0.5
	title.scale = Vector2(0.3, 0.3)
	title.create_tween().tween_property(title, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var sub := UI.outline(UI.label("%s %d番 · 胡牌赔率 ×%s" % [r.fan_name, r.fan, _num(snappedf(float(r.hu_x), 0.01))], 44, UI.CREAM, "bold"), Color(0, 0, 0, 0.9), 10)
	cine.add_child(sub)
	sub.reset_size()
	sub.position = Vector2(540 - sub.size.x * 0.5, 1296)
	await wait(1.3)
	Engine.time_scale = 1.0
	var out := cine.create_tween()
	out.tween_interval(0.2)
	out.tween_property(cine, "modulate:a", 0.0, 0.2)
	out.tween_callback(cine.queue_free)
	await overlays.show_settlement(r)
	audio.duck(false)
	fx.set_mood("none")
	refresh_all()


## 墨刃 · 斩杀（中反馈）：墨痕劈下，补入最后一张；明示不替代「胡」字
func _play_zhan(ev: Dictionary) -> void:
	_set_phase("zhan")
	audio.sfx("zhan")
	say("斩！", "f_call", "zhan", 3)
	var to := slot_center(ev.slot)
	fx.flash(Color(0.95, 0.93, 0.88), 0.3, 0.5)
	fx.seq("ink", GRID_CENTER, 1080.0, false, null, Color.WHITE, 1.0, 0.45)
	fx.slash(Vector2(940, 620), to + Vector2(-40, 30))
	await wait(0.26)
	fx.shake(stage, 14.0, 0.3)
	_fill_slot_anim(ev.slot, 0)
	fx.seq("ring", to, 320.0, false, null, UI.CREAM)
	fx.burst(to, Color(0.1, 0.1, 0.12), 26, 420.0, 0.6, 300.0, 0.8)
	fx.banner("斩", UI.CREAM, "补入 " + MJCore.tile_name(ev.id) + " · 不替代「胡」字", "", 1.0, GRID_CENTER.y + 250, 170)
	await wait(0.95)
	_refresh_progress_shown(ev.filled)
	await _play_melds(ev.melds)


# ============ 主持人 ============

func say(text: String, face: String, voice_name: String, prio: int) -> void:
	if voice_name != "" and not audio.voice(voice_name, prio) and audio.voice_on and prio == 0:
		return  # 低优先级台词被更重要的语音占用时，字幕也不抢
	host_face.texture = TileView.tex("res://assets/host/%s.png" % face)
	host_face.scale = Vector2(1.12, 1.12)
	host_face.create_tween().tween_property(host_face, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	bubble_label.text = text
	bubble.reset_size()
	bubble.position = Vector2(204, 1516 + max(0.0, (164.0 - bubble.size.y) * 0.5))
	if bubble_tween and bubble_tween.is_valid():
		bubble_tween.kill()
	bubble.modulate.a = 1.0
	bubble_tween = create_tween()
	bubble_tween.tween_interval(3.6)
	bubble_tween.tween_property(bubble, "modulate:a", 0.0, 0.4)


# ============ 操作 ============

func _on_spin() -> void:
	if busy:
		Engine.time_scale = 4.0  # 演出中再点 = 加速跳过，不影响结果
		return
	if overlays.is_open():
		return
	busy = true
	audio.sfx("click")
	btn_spin.modulate = Color(0.75, 0.75, 0.75)
	var events := core.spin()
	core.save(save_path)  # 先落账，再演出：中途退出也不丢结果
	await play(events)
	_finish_turn()


func _finish_turn() -> void:
	Engine.time_scale = 1.0
	_set_phase("")
	refresh_all()
	core.save(save_path)
	btn_spin.modulate = Color.WHITE
	busy = false
	if auto_on:
		get_tree().create_timer(0.5).timeout.connect(_auto_step)


## 自动：一直转下去。听牌且有「斩」就先斩；剧情、结算、钻石抽取、大牌亮相都会自动继续。
func _toggle_auto() -> void:
	auto_on = not auto_on
	audio.sfx("click")
	btn_auto.text = "停止自动" if auto_on else "自动"
	var bg := Color("c79a45") if auto_on else Color(0.16, 0.10, 0.06, 0.96)
	btn_auto.add_theme_stylebox_override("normal", UI.box(bg, UI.GOLD if auto_on else UI.GOLD_DEEP, 26, 3, 6))
	btn_auto.add_theme_stylebox_override("hover", UI.box(bg.lightened(0.1), UI.GOLD, 26, 3, 6))
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		btn_auto.add_theme_color_override(k, UI.INK if auto_on else UI.GOLD)
	fx.toast("自动转动已开启" if auto_on else "自动转动已停止", TOAST_Y, 1.0)
	if auto_on:
		_auto_step()


func _auto_step() -> void:
	if not auto_on or busy or overlays.is_open():
		return
	if core.can_zhan():
		_on_zhan()
	else:
		_on_spin()


func _on_zhan() -> void:
	if busy or not core.can_zhan():
		return
	busy = true
	btn_zhan.visible = false
	var events := core.use_zhan()
	core.save(save_path)
	await play(events)
	_finish_turn()


func _resume_story() -> void:
	busy = true
	var choice: int = await overlays.show_story(core.story_offer)
	await play(core.choose_story(choice))
	_finish_turn()


func _on_save_exit() -> void:
	if busy:
		return
	audio.sfx("click")
	core.save(save_path)
	fx.toast("进度已保存，下次从这里继续", TOAST_Y, 1.0)
	await wait(0.9)
	get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		print("WM_CLOSE_REQUEST spin=", core.spin_no)  # 窗口被关闭（区别于程序自己退出）
		core.save(save_path)
