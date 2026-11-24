class_name Demo
extends Node
## 自动演示 + 截图验证（使用独立存档 user://demo_save.json，不碰玩家进度）
##   godot --path . -- shots=<输出目录>     预设牌面走完整流程，按演出阶段截图
##   godot --path . -- autoplay=<转数>      真实随机盘面自动游玩，验证不报错

const A := "p2"
const B := "p3"
const C := "p4"
const D := "p6"

var main: Control
var dir := ""
var cursor := 0
var t0 := 0


func run(m: Control, out_dir: String) -> void:
	main = m
	dir = out_dir
	DirAccess.make_dir_recursive_absolute(dir)
	main.overlays.auto = true
	var core: MJCore = main.core
	t0 = Time.get_ticks_msec()
	await pause(1.0)
	await shot("01_idle")

	# --- 积累：一万成组(含金)、百搭助五万、东风入风位与副线、花牌上架；随后触发短剧情 ---
	core.force_template(0)
	core.hand_no = 1
	for i in [0, 1, 3, 4, 9]:  # 一万已有两张：这一转补齐刻子 → 「碰」
		core.slots[i] = 0
	core.slots[6] = 2
	main.refresh_all()
	var rows := filler()
	rows[0] = ["f1", B, A, "z1", "z1", "z1"]
	rows[2] = ["m5", "wild", "m5", B, A, B]
	rows[3] = ["m1", "m1", "m1:3", D, C, D]
	core.scripted = board(rows) + ["s2", "s4", "s6", "s8", "s3", "s7", "s2", "s4", "s6", "s8"]
	main._on_spin()
	await until_phase("landed")
	await pause(0.12)
	await shot("02_landed")
	await until_phase("highlight")
	await pause(0.3)
	await shot("03_highlight")
	await until_phase("burst")
	await pause(0.1)
	await shot("04_burst")
	await until_phase("fly")
	await pause(0.16)
	await shot("05_fly")
	await pause(0.3)
	await shot("06_arrive")
	await until_phase("settled")
	await pause(0.42)
	await shot("06b_meld")
	await until_overlay()
	await pause(0.9)
	await shot("07_story")
	await until_idle()
	await shot("08_collect")

	# --- 集齐：四季平安 + 四风齐（同一转先后触发）---
	core.flowers[1] = true
	core.flowers[2] = true
	core.winds[1] = true
	core.winds[2] = true
	# 演示刚开始转数很小，直接减会得到负数（= 未开始计转）。先把转数拨后，再设两组的起点：
	core.spin_no += 60
	core.flower_start[0] = core.spin_no      # 花架：下一转集齐，共 2 转 → 极快档
	core.wind_start = core.spin_no - 40      # 风位：拖了 41 转才齐 → 普通档
	main.refresh_all()
	rows = filler()
	rows[0] = ["f4", B, A, B, A, B]
	rows[3] = ["z4", "z4", "z4", D, C, D]
	core.scripted = board(rows) + ["s2", "s4", "s6", "s8", "s3", "s7"]
	main._on_spin()
	await until_phase("bonus")
	await pause(0.22)
	await shot("08b0_scroll_in")
	await pause(0.75)
	await shot("08b_bonus_flower")
	await pause(1.2)
	await shot("08b2_scroll_late")
	await until_phase("bonus")
	await pause(0.9)
	await shot("08c_bonus_wind")
	await until_idle()

	# --- 听牌（冰）---
	for i in 12:
		if core.slots[i] < 0:
			core.slots[i] = 0
	core.slots[10] = 4
	core.slots[12] = -1  # 剧情的黄金牌是随机挑的缺牌，可能正好是九万：这里固定留出两张九万
	core.slots[13] = -1
	core.groups_done.erase(4)
	core.hand.story_done = true
	core.hand.skill = 1
	core.state = "collect"
	main.refresh_all()
	rows = filler()
	rows[3] = ["m9", "m9", "m9", D, C, D]
	core.scripted = board(rows) + ["s2", "s4", "s6"]
	main._on_spin()
	await until_phase("ting")
	await pause(0.28)
	await shot("09_ting")
	await until_idle()
	await shot("10_ting_idle")

	# --- 斩杀（墨刃）→ 成牌待胡（雷）---
	main._on_zhan()
	await until_phase("zhan")
	await pause(0.36)
	await shot("11_zhan")
	await until_phase("ready")
	await pause(0.26)
	await shot("12_ready")
	await until_idle()
	await shot("13_ready_idle")

	# --- 胡牌（火）+ 结算（含钻石局资格）---
	rows = filler()
	rows[3] = ["hu", "hu", "hu", D, C, D]
	core.scripted = board(rows) + ["s2", "s4", "s6"]
	main._on_spin()
	await until_phase("hu_hand")
	await pause(0.3)
	await shot("14a_hu_hand")
	await until_phase("hu_slam")
	await pause(0.15)
	await shot("14b_hu_slam")
	await until_phase("hu_title")
	await pause(0.45)
	await shot("14c_hu_title")
	await until_overlay()
	await pause(2.6)
	await shot("15_settlement")
	await until_phase("free")
	await pause(0.5)
	await shot("15b_free_award")
	await until_idle()
	await shot("15c_free_idle")

	# --- 大牌亮相（十三幺）---
	for i in 14:
		core.big.slots[i] = true
	rows = filler()
	rows[3] = ["hu", "hu", "hu", D, C, D]
	core.scripted = board(rows) + ["s2", "s4", "s6"]
	main._on_spin()
	await until_overlay()
	await pause(1.3)
	await shot("16_bighand")
	await until_idle()

	# --- 记录 / 规则 ---
	main.overlays.show_record(1)
	await pause(0.6)
	await shot("17_record_big")
	main.overlays.close_top()
	main.overlays.show_rules()
	await pause(0.6)
	await shot("18_rules")
	print("DEMO_DONE")
	get_tree().quit()


## 用游戏里真正的「自动」功能跑 n 转（弹层用快速自动关闭）
func autoplay(m: Control, n: int) -> void:
	main = m
	dir = "tools/shots"
	DirAccess.make_dir_recursive_absolute(dir)
	main.overlays.auto = true
	var core: MJCore = main.core
	core.rng.seed = 20261123
	t0 = Time.get_ticks_msec()
	main._toggle_auto()
	var deadline := Time.get_ticks_msec() + n * 30000
	var mid_shot := false
	var last_spin := -1
	while core.spin_no < n and Time.get_ticks_msec() < deadline:
		if not mid_shot and core.spin_no >= n / 2 and main.phase == "burst":
			mid_shot = true
			await shot("a1_midplay")
		if core.spin_no != last_spin:
			last_spin = core.spin_no
			print("SPIN ", last_spin, " t=", Time.get_ticks_msec() - t0, "ms hand=", core.hand_no, " state=", core.state, " filled=", core.filled(), " pts=", core.total_points)
		await get_tree().process_frame
	main._toggle_auto()
	await until_idle()
	await shot("a2_end")
	main.overlays.show_record(0)
	await pause(0.6)
	await shot("a3_record_small")
	main.overlays.close_top()
	main.overlays.show_settings()
	await pause(0.6)
	await shot("a4_settings")
	main.overlays.close_top()
	await pause(0.3)
	print("AUTOPLAY_DONE spins=%d hands=%d points=%d state=%s filled=%d big=%d records=%s" % [core.spin_no, core.hand_no, core.total_points, core.state, core.filled(), core.big_filled(), str(core.records.small.keys())])
	get_tree().quit()


## 宣传片录制：预设牌面走一遍精彩流程，配合 --write-movie 逐帧输出。
##   godot --path . --write-movie out.avi --fixed-fps 60 --resolution 1080x1920 -- film
## 日志里的 MARK 行是各段落的片内时间（秒），后期按它对解说。
func film(m: Control) -> void:
	main = m
	main.overlays.auto = false
	var core: MJCore = main.core
	var ov = main.overlays
	core.rng.seed = 20261124
	mark("intro")
	await pause(2.0)

	# --- 第 1 转：开局亮目标 + 三连消（金牌、百搭、风牌、花牌都出场）---
	core.tpl_idx = 0
	var rows := filler()
	rows[0] = ["f1", B, A, "z1", "z1", "z1"]
	rows[2] = ["m5", "wild", "m5", B, A, B]
	rows[3] = ["m1", "m1", "m1:3", D, C, D]
	core.scripted = board(rows) + ["s2", "m3", "s4", "m3", "s6", "m3:2", "s8", "s3", "s7", "s2", "m7", "m7", "m7", "s5", "s2", "s6"]
	mark("spin1")
	main._on_spin()
	await until_phase("landed")
	mark("spin1_landed")
	await until_idle()
	await pause(0.5)

	# --- 第 2 转：南风补齐四风齐 → 进牌后触发短剧情，二选一拿「斩」---
	core.winds[2] = true
	core.winds[3] = true
	await skip_ahead([1, 4], {})
	rows = filler()
	rows[0] = [A, B, A, "z2", "z2", "z2"]
	rows[3] = ["m5", "m5", "m5", D, C, D]
	core.scripted = board(rows) + ["s2", "s4", "s6", "s8", "s3", "s7"]
	mark("spin2")
	main._on_spin()
	await until_phase("bonus")
	mark("bonus")
	await until_overlay()
	mark("story")
	await pause(3.0)
	ov.done.emit(1)
	await until_idle()
	await pause(0.9)

	# --- 第 3 转：七万补齐刻子「碰」→ 九万进一张 → 听牌（冰）---
	await skip_ahead([2, 5, 8, 10], {10: 4})
	rows = filler()
	rows[1] = [C, D, C, "m7:3", "m7", "m7"]
	rows[3] = ["m9", "m9", "m9", D, C, D]
	core.scripted = board(rows) + ["s2", "s4", "s6", "s8", "s3", "s7"]
	mark("spin3")
	main._on_spin()
	await until_phase("ting")
	mark("ting")
	await until_idle()
	await pause(1.0)

	# --- 斩（墨刃）→ 成牌待胡（雷）---
	mark("zhan")
	main._on_zhan()
	await until_phase("ready")
	mark("ready")
	await until_idle()
	await pause(0.8)

	# --- 第 4 转：胡（火）+ 结算大奖 + 钻石局抽取 ---
	rows = filler()
	rows[3] = ["hu", "hu", "hu", D, C, D]
	core.scripted = board(rows) + ["s2", "s4", "s6"]
	mark("spin4")
	main._on_spin()
	await until_phase("hu_hand")
	mark("hu")
	await until_overlay()
	mark("settle")
	await pause(3.6)
	mark("draw")
	press("抽取")
	await pause(2.6)
	ov.done.emit(0)
	await until_idle()

	# --- 大牌副线集齐：十三幺亮相 ---
	for i in 14:
		core.big.slots[i] = true
	core.tpl_idx = 2
	main.refresh_all()
	await pause(0.5)
	rows = filler()
	rows[3] = ["hu", "hu", "hu", D, C, D]
	core.scripted = board(rows) + ["s2", "s4", "s6"]
	mark("spin5")
	main._on_spin()
	await until_overlay()
	mark("bighand")
	await pause(4.0)
	ov.done.emit(0)
	await until_idle()

	# --- 收尾：牌型记录 ---
	mark("record")
	ov.show_record(1)
	await pause(1.8)
	ov.close_top()
	await pause(0.4)
	mark("end")
	main.fx.stamp("转运胡", Vector2(540, 878), 250, "fire", 1.9, "转出好牌，胡个痛快")
	await pause(2.7)
	mark("quit")
	print("FILM_DONE")
	get_tree().quit()


## 片内时间：录制模式下每帧固定步长，用帧号换算最准
func mark(name: String) -> void:
	# drawn 落后于 frames 说明窗口被最小化、画面停止绘制，这段录像不能用
	print("MARK %s %.2f frames=%d drawn=%d" % [name, Engine.get_process_frames() / 60.0, Engine.get_process_frames(), Engine.get_frames_drawn()])


## 宣传片里的「几转之后」：直接补上若干槽位（grades: 槽位 → 品级）
func skip_ahead(idx: Array, grades: Dictionary) -> void:
	var core: MJCore = main.core
	main.fx.flash(Color(0.02, 0.06, 0.05), 0.7, 0.85)
	main.fx.toast("—— 几转之后 ——", 878.0, 1.1)
	await pause(0.3)
	for i in idx:
		core.slots[i] = int(grades.get(i, 0))
	core.groups_done = []
	var melds := []
	core._check_melds(melds)
	main.refresh_all()
	await pause(1.0)


## 按下最上层弹层里指定文字的按钮
func press(text: String) -> void:
	var st: Array = main.overlays._stack
	if st.is_empty():
		return
	for b in st[-1].find_children("*", "Button", true, false):
		if b.text == text and not b.disabled:
			b.pressed.emit()
			return
	print("PRESS_MISS ", text)


func filler() -> Array:
	return [[A, B, A, B, A, B], [C, D, C, D, C, D], [A, B, A, B, A, B], [C, D, C, D, C, D]]


func board(rows: Array) -> Array:
	var out := []
	for r in range(3, -1, -1):
		for c in 6:
			out.append(rows[r][c])
	return out


func pause(t: float) -> void:
	await get_tree().create_timer(t).timeout


## 等到某个演出阶段出现（按历史记录找，不会漏掉同一帧内被覆盖的阶段；按真实时间超时）
func until_phase(name: String) -> void:
	var deadline := Time.get_ticks_msec() + 40000
	while Time.get_ticks_msec() < deadline:
		for k in range(cursor, main.phase_hist.size()):
			if main.phase_hist[k] == name:
				cursor = k + 1
				return
		await get_tree().process_frame
	print("PHASE_TIMEOUT ", name, " hist=", main.phase_hist.slice(cursor))


func until_idle() -> void:
	for i in 400:
		if not main.busy and not main.overlays.is_open():
			break
		await pause(0.1)
	await pause(0.25)


func until_overlay() -> void:
	for i in 300:
		if main.overlays.is_open():
			break
		await pause(0.1)


func shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":  # 无窗口模式没有画面，只记录状态
		print("SHOT(skip) ", name, " state=", main.core.state, " filled=", main.core.filled())
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir.path_join(name + ".png"))
	print("SHOT ", name, " t=", Time.get_ticks_msec() - t0, "ms state=", main.core.state, " filled=", main.core.filled(), " phase=", main.phase, " fps=", Engine.get_frames_per_second())
