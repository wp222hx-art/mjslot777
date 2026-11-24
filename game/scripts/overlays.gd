class_name Overlays
extends Control
## 弹层：短剧情、结算、大牌亮相、牌型记录、规则、设置。
## 奖励在选择前明示，选后不再抽取；全部可跳过，跳过不影响结果。

signal done(value)

var main: Control
var auto := false  # 自动演示用：弹层自动关闭
var _open_count := 0
var _stack: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func is_open() -> bool:
	return _open_count > 0


func _modal(alpha: float = 0.82) -> Control:
	var root := Control.new()
	Engine.time_scale = 1.0
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.04, 0.03, alpha)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.modulate.a = 0.0
	create_tween().tween_property(root, "modulate:a", 1.0, 0.2)
	_open_count += 1
	_stack.append(root)
	return root


func close_top() -> void:
	if not _stack.is_empty():
		_close(_stack[-1])


func _close(root: Control) -> void:
	if not _stack.has(root):
		return
	_stack.erase(root)
	_open_count -= 1
	var tw := create_tween()
	tw.tween_property(root, "modulate:a", 0.0, 0.15)
	tw.tween_callback(root.queue_free)


## 自动关闭：auto = 自动演示（快）；main.auto_on = 玩家开了「自动」（留出看清的时间）
func _auto_delay(fast: float, slow: float) -> float:
	if auto:
		return fast
	if main.auto_on:
		return slow
	return -1.0


func _auto_after(root: Control, delay: float, v) -> void:
	if delay > 0.0:
		get_tree().create_timer(delay).timeout.connect(_auto_emit.bind(root.get_instance_id(), v))


func _auto_emit(root_id: int, v) -> void:
	var root := instance_from_id(root_id) as Control
	if root != null and is_instance_valid(root) and not _stack.is_empty() and _stack[-1] == root:
		done.emit(v)


func _click() -> void:
	main.audio.sfx("click")


func _media(parent: Control, video_path: String, still_path: String, rect: Rect2, loop: bool = true) -> Control:
	if ResourceLoader.exists(video_path) and not main.fx.reduce:
		var stream = load(video_path)
		if stream is VideoStream:
			var vp := VideoStreamPlayer.new()
			vp.stream = stream
			vp.expand = true
			vp.loop = loop
			vp.volume_db = -80.0
			vp.position = rect.position
			vp.size = rect.size
			vp.mouse_filter = Control.MOUSE_FILTER_IGNORE
			parent.add_child(vp)
			vp.play()
			return vp
	var tr := TextureRect.new()
	tr.texture = TileView.tex(still_path)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.position = rect.position
	tr.size = rect.size
	tr.clip_contents = true
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(tr)
	return tr


func _title(root: Control, text: String, y: float, size: int = 76) -> Label:
	var l := UI.outline(UI.label(text, size, UI.GOLD, "kai"), Color(0.1, 0.05, 0.0, 0.95), 10)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(UI.place(l, 0, y, 1080, size + 24))
	return l


# ================= 短剧情 =================

func show_story(offer: Dictionary) -> int:
	var root := _modal(0.985)
	main.audio.sfx("story")
	main.audio.duck(true)
	main.audio.voice("story" if offer.name == "茶馆送错桌" else "story2", 3)
	_media(root, "res://assets/video/story.ogv", "res://assets/video/story_still.png", Rect2(0, 96, 1080, 716))
	# 用本局真实的两样东西盖住画面里的示意牌
	var gold_id: String = offer.gold
	var gt := TileView.make(gold_id, 3, Vector2(150, 188))
	gt.position = Vector2(360 - 75, 96 + 494 - 104)
	root.add_child(gt)
	var zt := TextureRect.new()
	zt.texture = TileView.tex("res://assets/ui/zhan.png")
	zt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	zt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	zt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(UI.place(zt, 810 - 60, 96 + 494 - 120, 120, 210))
	UI.wood_panel(root, Rect2(200, 14, 680, 96))
	_title(root, offer.name, 18, 62)
	var once := UI.label("每局一次", 24, UI.GOLD, "bold")
	UI.panel(root, Rect2(900, 36, 150, 48), UI.box(Color(0.05, 0.16, 0.12, 0.9), UI.GOLD_DEEP, 24, 2))
	once.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(UI.place(once, 900, 42, 150, 36))
	var line := "茶能续，牌只能挑一张。" if offer.name == "茶馆送错桌" else "这张适合收藏，那张现在就能用。"
	var bub := UI.panel(root, Rect2(30, 126, 560, 80), UI.box(Color("f1e3c0"), UI.GOLD_DEEP, 18, 3, 6))
	var bl := UI.label(line, 30, UI.INK, "bold")
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bub.add_child(UI.place(bl, 0, 0, 560, 80))

	var nm := MJCore.tile_name(gold_id)
	var cards := [
		{"x": 40.0, "title": "拿黄金" + nm, "l1": "去向：填入%s空槽" % nm, "l2": "并记入收藏 · 品级：金", "choice": 0},
		{"x": 550.0, "title": "拿「斩」技能", "l1": "去向：技能栏（本局一次）", "l2": "听牌时主动补最后一张\n不替代「胡」字", "choice": 1},
	]
	for cd in cards:
		var x: float = cd.x
		UI.green_panel(root, Rect2(x, 830, 490, 760))
		if cd.choice == 0:
			main.fx.rays(root, Vector2(x + 245, 1010), 230.0, Color(1.0, 0.82, 0.4, 0.9))
			var t := TileView.make(gold_id, 3, Vector2(176, 220))
			t.position = Vector2(x + 245 - 88, 900)
			root.add_child(t)
		else:
			main.fx.rays(root, Vector2(x + 245, 1010), 230.0, Color(0.9, 0.9, 0.95, 0.6))
			var z := TextureRect.new()
			z.texture = TileView.tex("res://assets/ui/zhan.png")
			z.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			z.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			z.mouse_filter = Control.MOUSE_FILTER_IGNORE
			root.add_child(UI.place(z, x + 245 - 70, 880, 140, 260))
		var tl := UI.label(cd.title, 60, UI.GOLD, "kai")
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		root.add_child(UI.place(tl, x, 1160, 490, 80))
		var d1 := UI.label(cd.l1, 30, UI.CREAM, "bold")
		d1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		root.add_child(UI.place(d1, x, 1262, 490, 44))
		var d2 := UI.label(cd.l2, 28, UI.CREAM)
		d2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		root.add_child(UI.place(d2, x, 1310, 490, 90))
		var d3 := UI.label("金品级提高整手品级系数" if cd.choice == 0 else "另得剧情奖励 +%s" % UI.fmt(int(offer.pts_zhan)), 28, UI.GOLD, "bold")
		d3.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		root.add_child(UI.place(d3, x, 1404, 490, 40))
		var b := UI.button(root, "选这张", Rect2(x + 45, 1462, 400, 100), 46, true)
		b.pressed.connect(_emit_done.bind(cd.choice))
	var note := UI.label("—  奖励已明示，选后不再抽取  —", 30, UI.GOLD, "kai")
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(UI.place(note, 0, 1614, 1080, 44))
	var hl := UI.label("目标手牌 %d / %d   还缺：%s" % [main.core.filled(), main.core.need.size(), _missing_text()], 28, UI.CREAM, "bold")
	hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(UI.place(hl, 0, 1680, 1080, 40))
	var skip := UI.button(root, "跳过", Rect2(820, 1780, 220, 90), 38)
	skip.pressed.connect(_emit_done.bind(-1))
	_auto_after(root, _auto_delay(1.2, 3.2), 0)
	var v = await done
	_click()
	main.audio.duck(false)
	_close(root)
	return int(v)


func _emit_done(v) -> void:
	done.emit(v)


func _missing_text() -> String:
	var parts := []
	var miss: Dictionary = main.core.missing()
	for id in miss:
		parts.append("%s×%d" % [MJCore.tile_name(id), miss[id]])
	return "  ".join(parts)


# ================= 结算 =================

func show_settlement(r: Dictionary) -> void:
	var root := _modal(0.96)
	# 视频下半部分画的是固定示例手牌，只取上半部分；手牌按本局真实结果另行绘制
	var clip := Control.new()
	clip.name = "clip"
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(UI.place(clip, 0, 0, 1080, 632))
	_media(clip, "res://assets/video/hu.ogv", "res://assets/video/hu_still.png", Rect2(-240, 0, 1560, 1170))
	main.fx.rise(Vector2(540, 660), 900.0, UI.FIRE, 40, 2.0, 500.0, 1.6)
	UI.wood_panel(root, Rect2(300, 640, 480, 84))
	_title(root, r.name, 646, 54)
	UI.wood_panel(root, Rect2(40, 736, 1000, 318))
	UI.panel(root, Rect2(54, 750, 972, 290), UI.box(Color(0.05, 0.22, 0.16, 0.95), Color(0, 0, 0, 0.4), 12, 2))
	var need: Array = r.need
	var slots: Array = r.slots
	for i in need.size():
		var t := TileView.make(need[i], int(slots[i]), Vector2(106, 132))
		t.position = Vector2(92 + (i % 7) * 130, 758 + (i / 7) * 140)
		t.scale = Vector2.ZERO
		root.add_child(t)
		var tw := create_tween()
		tw.tween_interval(0.15 + i * 0.04)
		tw.tween_property(t, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	UI.wood_panel(root, Rect2(40, 1066, 1000, 430))
	var hd := UI.label("本局结算  RESULT", 40, UI.GOLD, "kai")
	hd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(UI.place(hd, 40, 1074, 1000, 54))
	var rows := [
		["消除分  CLEAR", "+" + UI.fmt(r.clear_pts)],
		["胡牌 = 投注 %s × %s × 任务 %s × 品级 %s" % [UI.fmt(int(r.bet)), _num(MJCore.HU_X), _num(r.coef), _num(r.grade_coef)], "+" + UI.fmt(r.hu_pts)],
		["集齐奖  SETS", "+" + UI.fmt(r.set_pts)],
		["剧情奖励  STORY", "+" + UI.fmt(r.story_pts)],
	]
	var y := 1134.0
	for row in rows:
		root.add_child(UI.place(UI.label(row[0], 30, UI.CREAM, "bold"), 86, y))
		var v := UI.label(row[1], 38, UI.CREAM, "bold")
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		root.add_child(UI.place(v, 700, y - 6, 300, 50))
		y += 58
		var sep := ColorRect.new()
		sep.color = Color(0.72, 0.54, 0.24, 0.35)
		sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(UI.place(sep, 86, y - 8, 914, 2))
	root.add_child(UI.place(UI.label("本局赢分  TOTAL WIN", 40, UI.GOLD, "kai"), 86, 1390))
	var total := UI.gold(UI.label("0", 84, UI.GOLD, "bold"), 84)
	total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(UI.place(total, 500, 1356, 500, 116))
	total.pivot_offset = Vector2(500, 58)
	var tw2 := create_tween()
	tw2.tween_interval(0.5)
	tw2.tween_method(_count_step.bind(total), 0, int(r.total), 1.1).set_ease(Tween.EASE_OUT)
	tw2.tween_callback(main.audio.sfx.bind("count_end"))
	tw2.tween_property(total, "scale", Vector2(1.22, 1.22), 0.1)
	tw2.tween_property(total, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 大奖分级由内核按胡牌赔率判定（公开阈值）；金币量随档位增加
	var tier := int(r.tier)
	for k in 4 + tier * 4:
		get_tree().create_timer(0.55 + k * 0.2).timeout.connect(_coins.bind(root.get_instance_id(), Vector2(540, 1930), 8 + tier * 5))
	if tier > 0:
		var bw := UI.impact("超级大奖" if tier == 2 else "大奖", 200, "fire" if tier == 2 else "gold")
		bw.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		root.add_child(UI.place(bw, 0, 190, 1080, 230))
		bw.pivot_offset = Vector2(540, 115)
		bw.scale = Vector2(3.0, 3.0)
		bw.modulate.a = 0.0
		var tb := bw.create_tween()
		tb.tween_interval(1.7)
		tb.tween_property(bw, "modulate:a", 1.0, 0.08)
		tb.parallel().tween_property(bw, "scale", Vector2.ONE, 0.2).set_ease(Tween.EASE_IN)
		tb.tween_callback(_big_win_hit.bind(root.get_instance_id(), tier))
	var net := int(r.total) - int(r.paid)
	var ref := UI.label("本局投注 -%s（%d 转，免费 %d）  ·  净输赢 %s%s  ·  胡牌赔率 ×%s" % [UI.fmt(int(r.paid)), r.spins, r.free_n, "+" if net > 0 else "", UI.fmt(net), _num(snappedf(float(r.hu_x), 0.01))], 28, UI.CREAM, "bold")
	ref.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(UI.place(ref, 0, 1506, 1080, 38))

	var draw_btn: Button = null
	if r.diamond:
		var dp := UI.panel(root, Rect2(40, 1556, 1000, 150), UI.box(Color(0.10, 0.16, 0.22, 0.96), Color(0.85, 0.92, 1.0), 18, 3, 8))
		main.fx.rays(root, Vector2(140, 1631), 110.0, Color(1, 1, 1, 0.8), 1.0)
		var dt := TileView.make("m7", 4, Vector2(84, 105))
		for i in need.size():
			if int(slots[i]) == 4:
				dt.set_symbol(need[i], 4)
		dt.position = Vector2(98, 1578)
		root.add_child(dt)
		root.add_child(UI.place(UI.label("钻石局资格", 42, UI.GOLD, "kai"), 230, 1568))
		var ds := UI.label("已获得抽取资格 · 资格不等于最高奖", 28, UI.CREAM, "bold")
		ds.name = "ds"
		root.add_child(UI.place(ds, 230, 1626, 560, 40))
		var ot := "奖档："
		for tr in MJCore.DIAMOND_TIERS:
			ot += "%s(%d%%)  " % [UI.fmt(int(round(tr[0] * int(r.bet)))), int(round(tr[1] * 100.0))]
		var odds := UI.label(ot, 22, Color(1, 1, 1, 0.6))
		root.add_child(UI.place(odds, 230, 1666))
		draw_btn = UI.button(root, "抽取", Rect2(820, 1586, 190, 90), 46, true)
		draw_btn.pressed.connect(_do_draw.bind(root, draw_btn, ds, dp))
		main.audio.voice("draw", 2)

	var face := TextureRect.new()
	face.texture = TileView.tex("res://assets/host/f_win.png")
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(UI.place(face, 50, 1730, 160, 160))
	var lv := UI.label("Lv.%d %s" % [main.core.level() + 1, main.core.level_name()], 28, UI.CREAM, "bold")
	root.add_child(UI.place(lv, 230, 1750))
	root.add_child(UI.place(UI.label("虚拟积分 · 不可兑换", 22, Color(1, 1, 1, 0.5)), 230, 1800))
	var next := UI.button(root, "下一手", Rect2(520, 1744, 330, 120), 54, true)
	next.pressed.connect(_emit_done.bind(0))
	var rec := UI.button(root, "记录", Rect2(870, 1754, 170, 100), 38)
	rec.pressed.connect(show_record)
	var ad := _auto_delay(2.4, 5.0)
	if ad > 0.0 and draw_btn != null:
		get_tree().create_timer(ad * 0.45).timeout.connect(_auto_draw.bind(root.get_instance_id(), draw_btn.get_instance_id()))
		ad += 1.6
	_auto_after(root, ad, 0)
	await done
	_click()
	_close(root)


func _coins(root_id: int, pos: Vector2, n: int) -> void:
	var root := instance_from_id(root_id) as Control
	if root != null and is_instance_valid(root) and _stack.has(root):
		# 喷高控制在结算面板以下，不挡分项数字
		main.fx.coin_fountain(pos + Vector2(randf_range(-420, 420), 0), n, 1450.0, 0.3, root)
		main.audio.sfx("coin", -6.0, randf_range(0.9, 1.2))


func _big_win_hit(root_id: int, tier: int) -> void:
	var root := instance_from_id(root_id) as Control
	if root == null or not is_instance_valid(root) or not _stack.has(root):
		return
	main.audio.sfx("big_win")
	main.audio.voice("superwin" if tier == 2 else "bigwin", 5)
	var clip := root.get_node_or_null("clip") as Control
	if clip != null:
		clip.create_tween().tween_property(clip, "modulate", Color(0.16, 0.13, 0.1, 1.0), 0.12)
	main.fx.shake(root, 18.0, 0.4)
	var ry: ColorRect = main.fx.rays(root, Vector2(540, 305), 560.0, Color(1.0, 0.82, 0.4, 0.85), 1.0 if tier == 2 else 0.0)
	root.move_child(ry, 2)
	main.fx.coin_fountain(Vector2(540, 560), 20 + tier * 10, 1100.0, 1.3, root)


func _count_step(v: int, l: Label) -> void:
	if l.text != UI.fmt(v):
		l.text = UI.fmt(v)
		if Engine.get_process_frames() % 4 == 0:
			main.audio.sfx("tick", -8.0)


func _do_draw(root: Control, btn: Button, ds: Label, dp: Panel) -> void:
	var res: Dictionary = main.core.draw_diamond()
	if res.is_empty():
		return
	main.spin_win += int(res.pts)  # 钻石局抽到的也算进本转赢分
	main.core.save(main.save_path)
	btn.disabled = true
	btn.text = "已抽"
	main.audio.sfx("diamond")
	if res.top:
		# 命中最高档：与「仅获得资格」使用不同文案与演出
		ds.text = "命中最高档！ +%s · 送免费转 %d 次" % [UI.fmt(res.pts), int(res.free)]
		main.fx.flash(Color.WHITE, 0.8, 0.8)
		main.audio.sfx("big_win")
		main.audio.voice("draw_top", 5)
		main.fx.coin_fountain(Vector2(540, 1631), 70, 2200.0, 1.1, root)
		var ry: ColorRect = main.fx.rays(root, Vector2(540, 960), 900.0, Color(1, 1, 1, 0.9), 1.0)
		root.move_child(ry, 1)
		main.fx.banner("命中最高档", Color.WHITE, "+" + UI.fmt(res.pts), "light", 2.2, 960.0, 120)
	else:
		ds.text = "抽取结果 +%s（未命中最高档）" % UI.fmt(res.pts)
		main.fx.burst(Vector2(540, 1631), Color(0.9, 0.95, 1.0), 40, 420.0, 0.8, 100.0, 0.8)
		main.fx.coin_fountain(Vector2(540, 1631), 18, 1500.0, 0.8, root)
		main.fx.float_text(Vector2(540, 1560), "+" + UI.fmt(res.pts), Color(0.9, 0.95, 1.0), 72, 1.4, true)


func _num(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, round(v)) else str(v)


# ================= 大牌亮相 =================

func show_big_hand(ev: Dictionary) -> void:
	var root := _modal(1.0)
	main.audio.sfx("big_win")
	main.audio.sfx("fire", -8.0)
	main.audio.duck(true)
	main.audio.voice("big_" + String(ev.id), 5)
	for k in 8:
		get_tree().create_timer(0.4 + k * 0.22).timeout.connect(_coins.bind(root.get_instance_id(), Vector2(540, 1700), 22))
	main.fx.flash(UI.FIRE, 0.7, 0.7)
	if ev.name == "十三幺":
		# Seedance 生成的亮相片段：牌型名与本次一致，底部的示例分数另行盖住
		_media(root, "res://assets/video/bighand.ogv", "res://assets/video/bighand_still.png", Rect2(0, 0, 1080, 1920), false)
		# 片段底部画着固定的示例分数，用本次真实派彩的面板盖住
		var vbox := UI.panel(root, Rect2(70, 1684, 940, 142), UI.box(Color(0.13, 0.07, 0.03, 1.0), UI.GOLD, 16, 3, 8))
		vbox.z_index = 3  # 压在金币之上，派彩数字始终看得清
		var vt := UI.label("大牌分  BIG HAND", 38, UI.GOLD, "kai")
		vt.z_index = 3
		root.add_child(UI.place(vt, 106, 1696))
		var vp := UI.impact("+" + UI.fmt(ev.pts), 76, "gold")
		vp.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		vp.z_index = 3
		root.add_child(UI.place(vp, 520, 1680, 460, 96))
		var vr := UI.label("投注 %s × %s 倍 · 送免费转 %d 次 · 番种参考 %s %d番" % [UI.fmt(int(ev.bet)), _num(ev.x), int(ev.free), ev.name, ev.fan], 27, UI.CREAM, "bold")
		vr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vr.z_index = 3
		root.add_child(UI.place(vr, 70, 1776, 940, 40))
	else:
		var bg := ColorRect.new()
		bg.color = Color(0.10, 0.04, 0.02, 1.0)
		bg.size = Vector2(1080, 1920)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(bg)
		main.fx.rays(root, Vector2(540, 820), 900.0, Color(1.0, 0.7, 0.3, 0.75))
		var hu := TextureRect.new()
		hu.texture = TileView.tex("res://assets/ui/hu.png")
		hu.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		hu.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(UI.place(hu, 470, 60, 140, 140))
		_title(root, ev.name, 220, 190)
		var sub := UI.label("—  大牌  BIG HAND  —", 34, UI.GOLD, "bold")
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		root.add_child(UI.place(sub, 0, 450, 1080, 50))
		var tiles: Array = ev.tiles
		for i in tiles.size():
			var t := TileView.make(tiles[i], 0, Vector2(82, 102))
			var k := (i - 6.5) / 6.5
			t.position = Vector2(540 + k * 480 - 41, 600 + k * k * 110)
			t.rotation = k * 0.32
			t.scale = Vector2.ZERO
			root.add_child(t)
			var tw := create_tween()
			tw.tween_interval(0.2 + i * 0.05)
			tw.tween_property(t, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_callback(main.audio.sfx.bind("clack", -8.0, 0.9 + i * 0.02))
		var face := TextureRect.new()
		face.texture = TileView.tex("res://assets/host/f_win.png")
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(UI.place(face, 340, 900, 400, 400))
		var bub := UI.panel(root, Rect2(250, 1330, 580, 110), UI.box(Color("f1e3c0"), UI.GOLD_DEEP, 22, 3, 6))
		var bl := UI.label("%s耶！你也太厉害了吧！" % ev.name, 38, UI.INK, "bold")
		bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		bub.add_child(UI.place(bl, 0, 0, 580, 110))
		UI.wood_panel(root, Rect2(90, 1500, 900, 190))
		root.add_child(UI.place(UI.label("大牌分  BIG HAND", 40, UI.GOLD, "kai"), 130, 1520))
		var pts := UI.gold(UI.label("+" + UI.fmt(ev.pts), 90, UI.GOLD, "bold"), 90)
		pts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		root.add_child(UI.place(pts, 480, 1500, 470, 110))
		var rf := UI.label("投注 %s × %s 倍 · 送免费转 %d 次 · 番种参考 %s %d番" % [UI.fmt(int(ev.bet)), _num(ev.x), int(ev.free), ev.name, ev.fan], 30, UI.CREAM)
		rf.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		root.add_child(UI.place(rf, 90, 1626, 900, 44))
		main.fx.rise(Vector2(540, 1930), 1080.0, UI.FIRE, 70, 3.0, 800.0, 2.0)
	# 盖住视频底部自带的示意按钮与文字，换成真实可用的操作
	var bar := ColorRect.new()
	bar.color = Color(0.07, 0.04, 0.02, 1.0)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(UI.place(bar, 0, 1822, 1080, 98))
	var bar_ln := ColorRect.new()
	bar_ln.color = UI.GOLD_DEEP
	bar_ln.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(UI.place(bar_ln, 0, 1822, 1080, 3))
	var note := UI.label("已记入牌型记录 · 副线换下一个目标：%s" % main.core.big_tpl().name, 28, UI.CREAM, "bold")
	root.add_child(UI.place(note, 40, 1836))
	root.add_child(UI.place(UI.label("虚拟积分 · 不可兑换", 22, Color(1, 1, 1, 0.5)), 40, 1878))
	var skip := UI.button(root, "继续", Rect2(850, 1834, 200, 76), 38)
	skip.pressed.connect(_emit_done.bind(0))
	_auto_after(root, 1.6 if auto else (4.5 if main.auto_on else 6.5), 0)
	await done
	main.audio.duck(false)
	_close(root)


func _auto_draw(root_id: int, btn_id: int) -> void:
	var root := instance_from_id(root_id) as Control
	var btn := instance_from_id(btn_id) as Button
	if root != null and btn != null and is_instance_valid(root) and _stack.has(root) and is_instance_valid(btn) and not btn.disabled:
		btn.pressed.emit()


# ================= 牌型记录 =================

func show_record(tab: int = 0) -> void:
	var root := _modal(0.97)
	_click()
	_title(root, "牌型记录", 26, 84)
	var back := UI.button(root, "返回", Rect2(30, 40, 150, 80), 36)
	back.pressed.connect(_close_simple.bind(root))
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(holder)
	var names := ["小胡", "大牌", "81番图鉴"]
	var tabs: Array = []
	for i in 3:
		var b := UI.button(root, names[i], Rect2(60 + i * 325, 150, 310, 84), 38, i == tab)
		tabs.append(b)
		b.pressed.connect(_record_tab.bind(root, holder, tabs, i))
	_record_fill(holder, tab)
	var note := UI.label("—  记录只记账，不影响出牌  ·  虚拟积分不可兑换  —", 26, UI.GOLD, "kai")
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(UI.place(note, 0, 1860, 1080, 40))


func _close_simple(root: Control) -> void:
	_click()
	_close(root)


func _record_tab(root: Control, holder: Control, tabs: Array, idx: int) -> void:
	_click()
	for i in tabs.size():
		var primary: bool = i == idx
		var bg := Color("c79a45") if primary else Color(0.16, 0.10, 0.06, 0.96)
		tabs[i].add_theme_stylebox_override("normal", UI.box(bg, UI.GOLD if primary else UI.GOLD_DEEP, 26, 3, 6))
		tabs[i].add_theme_color_override("font_color", UI.INK if primary else UI.GOLD)
	_record_fill(holder, idx)


func _record_fill(holder: Control, tab: int) -> void:
	for c in holder.get_children():
		c.queue_free()
	var sc := ScrollContainer.new()
	sc.position = Vector2(30, 256)
	sc.size = Vector2(1020, 1590)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	holder.add_child(sc)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(1000, 0)
	vb.add_theme_constant_override("separation", 14)
	sc.add_child(vb)
	var core: MJCore = main.core
	if tab == 0:
		for t in MJCore.TEMPLATES:
			var tiles := []
			for m in t.melds:
				tiles.append_array(m)
			var rec: Dictionary = core.records.small.get(t.id, {})
			var status := "已胡" if not rec.is_empty() else ("攒进" if core.tpl_idx >= 0 and core.tpl().id == t.id and core.state != "pending" else "未见过")
			var line := "尚无记录"
			if not rec.is_empty():
				line = "胡出 %d 次 · 最少 %d 转 · 首胡 %s" % [rec.count, rec.best, rec.first]
			elif status == "攒进":
				line = "本局进度 %d / %d" % [core.filled(), core.need.size()]
			vb.add_child(_record_card(t.name, "番种参考 %d番 · 任务系数 ×%s" % [t.fan, _num(t.coef)], line, tiles, status, {}))
		vb.add_child(_recent_card(core.recent))
	elif tab == 1:
		for i in MJCore.BIG_HANDS.size():
			var b: Dictionary = MJCore.BIG_HANDS[i]
			var rec2: Dictionary = core.records.big.get(b.id, {})
			var cur: bool = i == core.big.idx
			var status2 := "已胡" if not rec2.is_empty() else ("攒进" if cur and core.big_filled() > 0 else "未见过")
			var line2 := "尚无记录"
			if not rec2.is_empty():
				line2 = "胡出 %d 次 · 首胡 %s" % [rec2.count, rec2.first]
			if cur:
				line2 += "   当前副线 %d / 14" % core.big_filled()
			var have := {}
			if cur:
				for k in 14:
					have[k] = core.big.slots[k]
			vb.add_child(_record_card(b.name, "番种参考 %d番 · 大牌赔率 ×%s" % [b.fan, _num(b.x)], line2, b.tiles, status2, have if cur else {}))
	else:
		var seen := 0
		for row in MJCore.FAN_CATALOG:
			for nm in row[1]:
				if core.records.fans.has(nm): seen += 1
		var head := UI.label("国标 81 番种目录（1998 试行规则公开资料整理）· 已完成 %d / 81\n金色 = 已完成  ·  亮色 = 改编挑战可玩  ·  灰色 = 仅收录说明" % seen, 26, UI.CREAM)
		head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		head.custom_minimum_size = Vector2(1000, 0)
		vb.add_child(head)
		var playable := {}
		for t in MJCore.TEMPLATES: playable[t.fan_name] = true
		for b in MJCore.BIG_HANDS: playable[b.name] = true
		for row in MJCore.FAN_CATALOG:
			var pc := PanelContainer.new()
			pc.add_theme_stylebox_override("panel", UI.box(Color(0.06, 0.20, 0.15, 0.92), UI.GOLD_DEEP, 14, 2))
			var mg := MarginContainer.new()
			for side in ["left", "right", "top", "bottom"]:
				mg.add_theme_constant_override("margin_" + side, 16)
			var inner := VBoxContainer.new()
			inner.add_child(UI.label("%d 番  ·  %d 种" % [row[0], row[1].size()], 32, UI.GOLD, "kai"))
			var flow := HFlowContainer.new()
			flow.add_theme_constant_override("h_separation", 12)
			flow.add_theme_constant_override("v_separation", 10)
			for nm in row[1]:
				var done_it: bool = core.records.fans.has(nm)
				var can: bool = playable.has(nm)
				var chip := PanelContainer.new()
				var col := UI.GOLD if done_it else (UI.CREAM if can else Color(0.62, 0.64, 0.6))
				chip.add_theme_stylebox_override("panel", UI.box(Color("5a4320") if done_it else Color(0, 0, 0, 0.35), col if (done_it or can) else Color(0.35, 0.36, 0.34), 10, 2))
				var cm := MarginContainer.new()
				for side in ["left", "right"]:
					cm.add_theme_constant_override("margin_" + side, 14)
				for side in ["top", "bottom"]:
					cm.add_theme_constant_override("margin_" + side, 6)
				cm.add_child(UI.label(("✓ " if done_it else "") + nm, 28, col, "bold"))
				chip.add_child(cm)
				flow.add_child(chip)
			inner.add_child(flow)
			mg.add_child(inner)
			pc.add_child(mg)
			vb.add_child(pc)


func _record_card(title: String, sub: String, line: String, tiles: Array, status: String, have: Dictionary) -> Control:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(1000, 232)
	p.add_theme_stylebox_override("panel", UI.box(Color("e9d8b0") if status != "未见过" else Color("b9ad92"), UI.GOLD_DEEP, 16, 3))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in tiles.size():
		var t := TileView.make(tiles[i], 0, Vector2(56, 70))
		t.position = Vector2(22 + i * 58, 16)
		p.add_child(t)
		if status == "未见过" or (not have.is_empty() and not have.get(i, false)):
			t.set_dim(1.0)
	p.add_child(UI.place(UI.label(title, 46, UI.INK, "kai"), 26, 96))
	p.add_child(UI.place(UI.label(sub, 26, UI.INK), 26, 152))
	p.add_child(UI.place(UI.label(line, 26, Color("5a4630"), "bold"), 26, 188))
	var col := {"已胡": UI.RED, "攒进": Color("8a6a2a"), "未见过": Color("6b665c")}
	var c: Color = col[status]
	var stamp := Panel.new()
	stamp.add_theme_stylebox_override("panel", UI.box(Color(c.r, c.g, c.b, 0.08), c, 14, 5))
	stamp.rotation = -0.14
	stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(UI.place(stamp, 850, 120, 128, 72))
	var sl := UI.label(status, 34, c, "kai")
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stamp.add_child(UI.place(sl, 0, 0, 128, 72))
	return p


func _recent_card(recent: Array) -> Control:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(1000, 80 + max(1, recent.size()) * 50)
	p.add_theme_stylebox_override("panel", UI.box(Color(0.06, 0.20, 0.15, 0.95), UI.GOLD_DEEP, 16, 3))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := UI.label("最近  RECENT", 34, UI.GOLD, "kai")
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(UI.place(h, 0, 12, 1000, 46))
	if recent.is_empty():
		var e := UI.label("还没有胡过，先完成一手吧", 28, UI.CREAM)
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		p.add_child(UI.place(e, 0, 70, 1000, 40))
	for i in recent.size():
		var r: Dictionary = recent[i]
		var y := 68.0 + i * 50
		p.add_child(UI.place(UI.label(String(r.name), 30, UI.CREAM, "bold"), 120, y))
		p.add_child(UI.place(UI.label("%d 转" % int(r.spins), 30, UI.CREAM), 520, y))
		var v := UI.label(UI.fmt(int(r.pts)), 30, UI.GOLD, "bold")
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		p.add_child(UI.place(v, 680, y, 220, 40))
	return p


# ================= 规则 =================

## 规则文案里的数值全部取自内核常量，改了赔率表这里自动跟着变
static func rules() -> Array:
	var bets := ""
	for b in MJCore.BETS:
		bets += ("" if bets == "" else " / ") + UI.fmt(b)
	var dia := ""
	for t in MJCore.DIAMOND_TIERS:
		dia += ("" if dia == "" else " / ") + "×%s(%d%%)" % [_n(t[0]), int(round(t[1] * 100.0))]
	var big := ""
	for b in MJCore.BIG_HANDS:
		big += ("" if big == "" else "、") + "%s ×%s" % [b.name, _n(b.x)]
	return [
		["一句话", "转动消除攒牌 → 听牌 → 补齐 14 张 → 消出「胡」字结算。每转消耗一次投注，所有赔率都是投注的倍数。"],
		["投注与赔率", "投注档：%s，每转扣一次，可随时调整（免费转期间除外）。\n消除：每张 ×%s × 连消数。\n胡牌 = 本局平均投注 × %s × 任务系数 × 整手品级系数。\n胡牌赔率 ≥%s 倍为大奖，≥%s 倍为超级大奖。\n番值只是国标参考，不换算成倍率。" % [bets, _n(MJCore.CLEAR_X), _n(MJCore.HU_X), _n(MJCore.BIG_WIN_X), _n(MJCore.SUPER_WIN_X)]],
		["免费转", "大奖送 %d 次、超级大奖送 %d 次、大牌亮相送 %d 次、钻石局最高档送 %d 次。\n免费转不扣余额，按触发时的投注进行，消除赔率 ×%d，期间不能改投注。" % [MJCore.FREE_BIG_WIN, MJCore.FREE_SUPER_WIN, MJCore.FREE_BIG_HAND, MJCore.FREE_DIAMOND_TOP, MJCore.FREE_CLEAR_MULT]],
		["消除", "三个或以上相同图标上下左右相邻即消除，空位补落可连锁。「百搭」只帮普通牌成组，不进手牌，也不替代「胡」字。"],
		["入槽", "一次消除事件最多收一张还缺的同名牌（消掉一组 ≠ 收进一组）。不需要的牌不占槽；%d 连及以上时去攒大牌副线。" % MJCore.BIG_MIN_CELLS],
		["听牌 / 成牌 / 胡", "13/14 叫听牌；14/14 叫成牌待胡；成牌后消出「胡」字才结算。\n· 0–12 槽消出「胡」：只是普通消除。\n· 13 槽消出「胡」：不胡、不吞牌、不储存。\n· 同一转先补齐第 14 张、又消出「胡」：可以胡。"],
		["品级", "普通 / 蓝 / 紫 / 金 / 钻，只换材质，牌还是那张牌。入槽时品级固定。\n品级点数：蓝1 紫2 金4 钻8；整手合计 ≥1 ×1.2，≥4 ×1.5，≥8 ×2，≥16 ×3。\n转轴牌品级概率固定：蓝5% 紫2% 金0.8% 钻0.15%。"],
		["钻石局", "胡牌时手牌里至少有一张钻石牌 → 获得一次抽取资格。资格不等于最高奖。\n奖档（投注倍数）：%s。" % dia],
		["花架与风位", "花牌出现即上花架，不占手牌槽；重复花牌 ×%s。消除风牌点亮风位。\n集齐奖按速度分三档：从该组第一张到集齐用了几转，越快奖越高、演出越大。\n花架（四季 / 四君子）：≤%d 转 ×%s，≤%d 转 ×%s，更慢 ×%s。\n风位（东南西北）：≤%d 转 ×%s，≤%d 转 ×%s，更慢 ×%s。\n集齐后该组重置、重新计转。" % [_n(MJCore.FLOWER_DUP_X),
			MJCore.FLOWER_TIER_SPINS[0], _n(MJCore.FLOWER_TIER_X[2]), MJCore.FLOWER_TIER_SPINS[1], _n(MJCore.FLOWER_TIER_X[1]), _n(MJCore.FLOWER_TIER_X[0]),
			MJCore.WIND_TIER_SPINS[0], _n(MJCore.WIND_TIER_X[2]), MJCore.WIND_TIER_SPINS[1], _n(MJCore.WIND_TIER_X[1]), _n(MJCore.WIND_TIER_X[0])]],
		["大牌副线", "主线不要的牌（%d 连及以上）攒大牌。副线 14/14 时消出「胡」字即大牌亮相，按副线期间平均投注发大牌赔率并送免费转，然后换下一个目标。\n赔率：%s。" % [MJCore.BIG_MIN_CELLS, big]],
		["短剧情", "每局最多一次，两个选项的内容在选择前写明，选后不再抽取。\n· 黄金牌：填入一张缺牌并收藏，金品级会提高整手品级系数。\n· 「斩」技能：另得剧情奖励（投注 ×%s）。" % _n(MJCore.STORY_ZHAN_X)],
		["斩", "只在听牌（差最后一张）时可用：主动补入那张牌（普通品级）。不替代「胡」字，每次只补一张。"],
		["关键牌援助", "连续 %d 转没有新增有效槽位且仍缺牌时，公开赠送一张关键牌，每局一次。不会偷偷调整符号概率。" % MJCore.AID_DRY_SPINS],
		["说明", "本作为「国标番种灵感模式」，不是赛事规则还原。全部为虚拟积分，无充值、无提现，不可交易或兑换；余额不够最低投注时免费补给 %s。符号权重开局锁定，不随进度、时长、投注大小或接近奖励的程度变化。" % UI.fmt(MJCore.SUPPLY_PTS)],
	]


static func _n(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, round(v)) else str(v)


func show_rules() -> void:
	var root := _modal(0.97)
	_title(root, "规则", 26, 84)
	var back := UI.button(root, "返回", Rect2(30, 40, 150, 80), 36)
	back.pressed.connect(_close_simple.bind(root))
	var sc := ScrollContainer.new()
	sc.position = Vector2(40, 160)
	sc.size = Vector2(1000, 1720)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(sc)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(980, 0)
	vb.add_theme_constant_override("separation", 14)
	sc.add_child(vb)
	for r in rules():
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", UI.box(Color(0.06, 0.20, 0.15, 0.92), UI.GOLD_DEEP, 14, 2))
		var mg := MarginContainer.new()
		for side in ["left", "right", "top", "bottom"]:
			mg.add_theme_constant_override("margin_" + side, 18)
		var inner := VBoxContainer.new()
		inner.add_child(UI.label(r[0], 38, UI.GOLD, "kai"))
		var body := UI.label(r[1], 28, UI.CREAM)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(930, 0)
		inner.add_child(body)
		mg.add_child(inner)
		pc.add_child(mg)
		vb.add_child(pc)


# ================= 设置 =================

func show_settings() -> void:
	var root := _modal(0.9)
	UI.wood_panel(root, Rect2(140, 480, 800, 900))
	_title(root, "设置", 506, 76)
	var items := [["music", "背景音乐"], ["sfx", "音效"], ["voice", "主持人语音"], ["reduce", "减少动态效果"]]
	for i in items.size():
		var key: String = items[i][0]
		root.add_child(UI.place(UI.label(items[i][1], 40, UI.CREAM, "bold"), 200, 640 + i * 110))
		var b := UI.button(root, "", Rect2(680, 628 + i * 110, 200, 84), 38)
		_toggle_text(b, key)
		b.pressed.connect(_toggle.bind(b, key))
	var hint := UI.label("关闭语音、音效或动态效果都不影响结果、奖励和操作。", 26, Color(1, 1, 1, 0.6))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(UI.place(hint, 140, 1080, 800, 40))
	var reset := UI.button(root, "重置全部进度", Rect2(200, 1150, 320, 96), 36)
	reset.pressed.connect(_reset.bind(root, reset))
	var ok := UI.button(root, "完成", Rect2(580, 1150, 300, 96), 42, true)
	ok.pressed.connect(_close_simple.bind(root))
	var warn := UI.label("重置会清空积分、等级、记录、收藏与当前手牌，不可恢复。", 24, Color(1, 0.75, 0.6))
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(UI.place(warn, 140, 1270, 800, 40))


func _toggle_text(b: Button, key: String) -> void:
	var on: bool = main.core.settings[key]
	b.text = "开" if on else "关"
	b.add_theme_color_override("font_color", UI.GOLD if on else Color(0.6, 0.6, 0.55))


func _toggle(b: Button, key: String) -> void:
	main.core.settings[key] = not main.core.settings[key]
	_toggle_text(b, key)
	main._apply_settings()
	main.core.save(main.save_path)
	_click()


func _reset(root: Control, b: Button) -> void:
	if b.text != "确认重置？":
		b.text = "确认重置？"
		_click()
		return
	if main.busy:
		return
	var st: Dictionary = main.core.settings
	main.core = MJCore.new()
	main.core.settings = st
	main.core.save(main.save_path)
	main.shown_points = 0
	main._show_idle_grid()
	main.refresh_all()
	_close_simple(root)
	main.fx.toast("进度已重置")
