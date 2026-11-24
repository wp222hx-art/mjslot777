extends SceneTree
## 无头规则测试: godot --headless --path . -s tests/test_core.gd
## 追加 "-- sim" 额外跑 2000 局仿真

var fails := 0
var passed := 0

# 互不成组的填充牌（不在清一色碰碰和模板内，也不是花牌、风牌）
const A := "p2"
const B := "p3"
const C := "p4"
const D := "p6"


func ok(cond: bool, name: String) -> void:
	if cond:
		passed += 1
	else:
		fails += 1
		print("  FAIL: ", name)


func has(events: Array, t: String) -> bool:
	for e in events:
		if e.t == t:
			return true
	return false


func get_ev(events: Array, t: String) -> Dictionary:
	for e in events:
		if e.t == t:
			return e
	return {}


## rows 为自上而下的 4 行，每行 6 个符号；返回内核的取符号顺序（自底向上逐行）。
func board(rows: Array) -> Array:
	var out := []
	for r in range(3, -1, -1):
		for c in 6:
			out.append(rows[r][c])
	return out


func filler_rows() -> Array:
	return [[A, B, A, B, A, B], [C, D, C, D, C, D], [A, B, A, B, A, B], [C, D, C, D, C, D]]


## 补落用：与填充牌、彼此都不成组
func refill(n: int) -> Array:
	var out := []
	var seq := ["s2", "s4", "s6", "s8", "s3", "s7"]
	for i in n:
		out.append(seq[i % seq.size()])
	return out


func mk() -> MJCore:
	var c := MJCore.new()
	c.rng.seed = 12345
	c.force_template(0)  # 清一色碰碰和 111 333 555 777 99 万
	c.hand_no = 1
	return c


func fill_to(c: MJCore, n: int) -> void:
	for i in n:
		c.slots[i] = 0
	c.state = "collect"
	if n == 13:
		c.state = "ting"
	if n == 14:
		c.state = "ready"


func hu_rows() -> Array:
	var rows := filler_rows()
	rows[3][0] = "hu"
	rows[3][1] = "hu"
	rows[3][2] = "hu"
	return rows


func _init() -> void:
	print("== 规则测试 ==")
	t_catalog()
	t_one_per_event()
	t_irrelevant_and_cap()
	t_hu_under_13()
	t_hu_at_13_void()
	t_same_spin_complete_and_hu()
	t_ready_then_hu_once()
	t_wild()
	t_story_and_zhan()
	t_grade()
	t_diamond()
	t_flower_wind()
	t_big_track()
	t_aid()
	t_save_restore()
	t_economy()
	print("通过 %d 项, 失败 %d 项" % [passed, fails])
	if OS.get_cmdline_user_args().has("sim"):
		simulate()
	quit(1 if fails > 0 else 0)


func t_catalog() -> void:
	var n := 0
	var seen := {}
	for row in MJCore.FAN_CATALOG:
		for nm in row[1]:
			n += 1
			seen[nm] = true
	ok(n == 81, "81 番种合计")
	ok(seen.size() == 81, "81 番种无重复")
	for t in MJCore.TEMPLATES:
		var cnt := {}
		var total := 0
		for m in t.melds:
			for id in m:
				cnt[id] = cnt.get(id, 0) + 1
				total += 1
		ok(total == 14, "模板 14 张: " + t.name)
		var mx := 0
		for k in cnt:
			mx = max(mx, cnt[k])
		ok(mx <= 4, "同种牌最多四枚: " + t.name)
	for b in MJCore.BIG_HANDS:
		ok(b.tiles.size() == 14, "大牌 14 张: " + b.name)


func t_one_per_event() -> void:
	var c := mk()
	var rows := filler_rows()
	rows[3][0] = "m1"
	rows[3][1] = "m1"
	rows[3][2] = "m1"
	rows[3][3] = "m1"  # 四连一万算一次消除事件
	c.scripted = board(rows) + refill(8)
	var ev := c.spin()
	ok(c.filled() == 1, "一次消除事件最多收一张 (实际 %d)" % c.filled())
	var st := get_ev(ev, "step")
	ok(st.groups.size() == 1 and st.groups[0].dest == "main", "消除去向为主手牌")
	ok(st.groups[0].pts == 4, "消除分 = 投注100 × 0.01 × 4张 × 连消1 (实际 %d)" % st.groups[0].pts)


func t_irrelevant_and_cap() -> void:
	var c := mk()
	var rows := filler_rows()
	rows[3][0] = "s9"
	rows[3][1] = "s9"
	rows[3][2] = "s9"  # 九条不在主模板，但在十三幺副线里
	c.scripted = board(rows) + refill(6)
	c.spin()
	ok(c.filled() == 0, "无关牌不占主槽")
	ok(c.big_filled() == 0, "三连消除不攒大牌副线")
	rows[3][3] = "s9"
	c.scripted = board(rows) + refill(8)
	c.spin()
	ok(c.big_filled() == 1, "四连及以上、主线不要的牌才攒大牌副线")
	var c2 := mk()
	c2.slots[12] = 0
	c2.slots[13] = 0  # 两张九万已满
	var rows2 := filler_rows()
	rows2[3][0] = "m9"
	rows2[3][1] = "m9"
	rows2[3][2] = "m9"
	c2.scripted = board(rows2) + refill(6)
	c2.spin()
	ok(c2.filled() == 2, "同名槽已满不再入主槽")


func t_hu_under_13() -> void:
	var c := mk()
	fill_to(c, 5)
	c.scripted = board(hu_rows()) + refill(6)
	var before := c.total_points
	var ev := c.spin()
	ok(has(ev, "hu_void") and not has(ev, "settle"), "0-12 槽消胡不结算")
	ok(c.filled() == 5, "消胡不扣已有牌")
	ok(c.total_points == before - c.bet(), "无效胡字无额外奖励 (只扣本转投注)")


func t_hu_at_13_void() -> void:
	var c := mk()
	fill_to(c, 13)
	c.scripted = board(hu_rows()) + refill(6)
	var ev := c.spin()
	ok(not has(ev, "settle") and has(ev, "hu_void"), "13 槽消胡不结算")
	ok(c.filled() == 13 and c.state == "ting", "13 槽无效胡字不吞牌、仍听牌")
	var rows2 := filler_rows()
	rows2[3][0] = "m9"
	rows2[3][1] = "m9"
	rows2[3][2] = "m9"
	c.scripted = board(rows2) + refill(6)
	var ev2 := c.spin()
	ok(c.state == "ready" and not has(ev2, "settle"), "胡字不留到下一转")


func t_same_spin_complete_and_hu() -> void:
	var c := mk()
	fill_to(c, 13)
	var rows := filler_rows()
	rows[3][0] = "m9"
	rows[3][1] = "m9"
	rows[3][2] = "m9"
	rows[2][3] = "hu"
	rows[2][4] = "hu"
	rows[2][5] = "hu"
	c.scripted = board(rows) + refill(12)
	var ev := c.spin()
	ok(has(ev, "settle"), "同转补齐第 14 张并消胡必胡")
	ok(c.state == "pending", "结算后进入下一局待开启")
	var r: Dictionary = get_ev(ev, "settle").get("result", {})
	ok(r.get("hu_pts", 0) == int(round(100 * MJCore.HU_X * 3.0)), "胡牌分 = 平均投注100 × HU_X × 任务系数3 × 品级1.0 (实际 %d)" % r.get("hu_pts", 0))
	ok(r.get("total", -1) == r.get("clear_pts", 0) + r.get("hu_pts", 0) + r.get("set_pts", 0) + r.get("story_pts", 0),
		"总分 = 消除分+胡牌分+集齐奖+剧情奖励")


func t_ready_then_hu_once() -> void:
	var c := mk()
	fill_to(c, 14)
	var rows := hu_rows()
	rows[1][3] = "hu"
	rows[1][4] = "hu"
	rows[1][5] = "hu"  # 同转两组胡字
	c.scripted = board(rows) + refill(12)
	var ev := c.spin()
	var n := 0
	for e in ev:
		if e.t == "settle":
			n += 1
	ok(n == 1, "每局只结算一次")
	ok(c.records.small.get("qys_pph", {}).get("count", 0) == 1, "牌型记录记一次")
	var hn := c.hand_no
	c.scripted = board(filler_rows())
	var ev2 := c.spin()
	ok(has(ev2, "new_hand") and c.hand_no == hn + 1, "胡后主动转动才生成新目标")
	ok(c.filled() == 0, "新局从空槽开始")


func t_wild() -> void:
	var c := mk()
	var rows := filler_rows()
	rows[3][0] = "m5"
	rows[3][1] = "wild"
	rows[3][2] = "m5"
	c.scripted = board(rows) + refill(6)
	c.spin()
	ok(c.filled() == 1, "百搭助普通牌成三连")
	var c2 := mk()
	fill_to(c2, 14)
	var rows2 := filler_rows()
	rows2[3][0] = "hu"
	rows2[3][1] = "wild"
	rows2[3][2] = "hu"
	c2.scripted = board(rows2) + refill(6)
	var ev := c2.spin()
	ok(not has(ev, "settle"), "百搭不替代胡字")


func t_story_and_zhan() -> void:
	var c := mk()
	fill_to(c, 6)
	c.scripted = board(filler_rows())
	var ev := c.spin()
	ok(has(ev, "story"), "6 槽后触发短剧情")
	ok(c.spin().is_empty(), "剧情未选择时不能转动")
	var gold_id: String = c.story_offer.gold
	var se := c.choose_story(0)
	var sg := get_ev(se, "story_gold")
	ok(c.filled() == 7, "剧情只补一张")
	ok(sg.get("slot", -1) >= 0 and c.slots[sg.slot] == 3 and c.need[sg.slot] == gold_id, "黄金牌填入同名空槽且品级为金")
	ok(c.collection.size() == 1, "黄金牌记入收藏")
	ok(c.choose_story(0).is_empty(), "剧情每局一次 (重复回调不重复发放)")
	c.scripted = board(filler_rows())
	ok(not has(c.spin(), "story"), "同局不再触发剧情")

	var z := mk()
	fill_to(z, 6)
	z.scripted = board(filler_rows())
	z.spin()
	z.choose_story(1)
	ok(z.hand.skill == 1 and z.filled() == 6, "选斩杀牌得技能、不补牌")
	ok(int(z.hand.story_pts) == int(round(MJCore.STORY_ZHAN_X * 100)) and int(c.hand.story_pts) == int(round(MJCore.STORY_GOLD_X * 100)), "两个选项的剧情奖励按各自公开的倍数")
	ok(z.use_zhan().is_empty(), "非 T-1 槽不能斩杀")
	ok(z.hand.skill == 1, "条件不满足不误扣次数")
	fill_to(z, 13)
	var ze := z.use_zhan()
	ok(z.filled() == 14 and z.hand.skill == 0, "斩杀只补一张合法缺牌")
	ok(z.state == "ready" and not has(ze, "settle"), "斩杀后仍需胡字")
	ok(z.slots[13] == 0, "斩杀补入普通品级")

	var r := mk()
	fill_to(r, 14)
	r.scripted = board(filler_rows())
	ok(not has(r.spin(), "story"), "成牌后不再弹补牌剧情")


func t_grade() -> void:
	var c := mk()
	var rows := filler_rows()
	rows[3][0] = "m7:3"
	rows[3][1] = "m7"
	rows[3][2] = "m7"
	c.scripted = board(rows) + refill(6)
	c.spin()
	ok(c.slots[9] == 3, "金色牌入槽仍是七万、品级固定为金")
	ok(is_equal_approx(c.grade_coef(), 1.5), "整手品级系数查表 (金=4点 → ×1.5)")


func t_diamond() -> void:
	var c := mk()
	fill_to(c, 14)
	c.slots[10] = 4
	c.scripted = board(hu_rows()) + refill(6)
	var ev := c.spin()
	var r: Dictionary = get_ev(ev, "settle").get("result", {})
	ok(r.get("diamond", false) and not r.get("drawn", true), "含钻石牌且胡牌 → 取得抽取资格")
	var before := c.total_points
	var d := c.draw_diamond()
	ok(d.get("pts", 0) > 0 and c.total_points == before + d.get("pts", 0), "钻石局抽取落账")
	ok(c.draw_diamond().is_empty(), "钻石局只抽一次")
	var c2 := mk()
	fill_to(c2, 14)
	c2.scripted = board(hu_rows()) + refill(6)
	c2.spin()
	ok(c2.draw_diamond().is_empty(), "无钻石牌无抽取资格")


func t_flower_wind() -> void:
	var c := mk()
	var rows := filler_rows()
	rows[0][0] = "f1"
	rows[0][2] = "f2"
	rows[0][4] = "f3"
	rows[1][1] = "f4"
	c.scripted = board(rows) + refill(8)
	var ev := c.spin()
	var st := get_ev(ev, "step")
	var bonus: Array = st.get("bonus", [])
	ok(bonus.size() == 1 and bonus[0].kind == "flower" and bonus[0].tier == 2 and bonus[0].spins == 1, "同一转集齐四季 → 极快档")
	ok(bonus[0].pts == int(round(MJCore.FLOWER_TIER_X[2] * 100)) and bonus[0].name == MJCore.BONUS_NAMES["flower0"][2], "极快档按最高赔率发奖并用最高雅称")
	ok(int(c.flower_start[0]) == -1, "集齐后该组计转清零")
	# 慢慢集齐：第一张与最后一张相隔很多转 → 普通档
	var sl := mk()
	var r1 := filler_rows()
	r1[0][0] = "f5"
	sl.scripted = board(r1) + refill(4)
	sl.spin()
	ok(int(sl.flower_start[1]) == sl.spin_no, "该组第一张上架时开始计转")
	sl.flowers[5] = true
	sl.flowers[6] = true
	sl.spin_no += MJCore.FLOWER_TIER_SPINS[1] + 5
	var r2 := filler_rows()
	r2[0][0] = "f8"
	sl.scripted = board(r2) + refill(4)
	var sb: Array = get_ev(sl.spin(), "step").get("bonus", [])
	ok(sb.size() == 1 and sb[0].tier == 0 and sb[0].pts == int(round(MJCore.FLOWER_TIER_X[0] * 100)) and sb[0].name == MJCore.BONUS_NAMES["flower1"][0], "很多转才集齐 → 普通档、最低赔率")
	ok(MJCore.speed_tier(MJCore.FLOWER_TIER_SPINS[0], MJCore.FLOWER_TIER_SPINS) == 2 and MJCore.speed_tier(MJCore.FLOWER_TIER_SPINS[0] + 1, MJCore.FLOWER_TIER_SPINS) == 1 and MJCore.speed_tier(MJCore.FLOWER_TIER_SPINS[1] + 1, MJCore.FLOWER_TIER_SPINS) == 0, "速度档位边界")
	ok(not c.flowers[0], "集齐后花架该组重置")
	ok(c.filled() == 0, "花牌不占手牌槽")
	var w := mk()
	w.winds = [true, true, true, false]
	w.spin_no = 100
	w.wind_start = 100 - MJCore.WIND_TIER_SPINS[1]  # 第 23 转才集齐 → 普通档
	var rows2 := filler_rows()
	rows2[3][0] = "z4"
	rows2[3][1] = "z4"
	rows2[3][2] = "z4"
	w.scripted = board(rows2) + refill(6)
	var ev2 := w.spin()
	var bonus2: Array = get_ev(ev2, "step").get("bonus", [])
	ok(bonus2.size() == 1 and bonus2[0].kind == "wind" and bonus2[0].tier == 0 and bonus2[0].pts == int(round(MJCore.WIND_TIER_X[0] * 100)), "四风齐按速度档发奖（慢 → 普通档）")
	ok(w.wind_start == -1, "四风齐后计转清零")


func t_big_track() -> void:
	var c := mk()
	for i in 14:
		c.big.slots[i] = true
	fill_to(c, 3)
	c.scripted = board(hu_rows()) + refill(6)
	var ev := c.spin()
	ok(has(ev, "big_hu") and not has(ev, "settle"), "大牌副线 14/14 + 胡字 → 大牌亮相")
	ok(c.big_filled() == 0 and c.big.idx == 1, "大牌胡后换下一个副线目标")
	ok(c.filled() == 3 and c.state == "collect", "大牌胡不影响主手牌")


func t_aid() -> void:
	var c := mk()
	fill_to(c, 2)
	var got := false
	for i in MJCore.AID_DRY_SPINS:
		c.scripted = board(filler_rows())
		if has(c.spin(), "aid"):
			got = true
	ok(got and c.filled() == 3, "连续 N 转无进展给一次关键牌援助")
	var again := false
	for i in MJCore.AID_DRY_SPINS + 2:
		c.scripted = board(filler_rows())
		var ev := c.spin()
		if not c.story_offer.is_empty():
			c.choose_story(-1)
		if has(ev, "aid"):
			again = true
	ok(not again, "援助每局仅一次")


func t_save_restore() -> void:
	var c := mk()
	fill_to(c, 9)
	c.slots[4] = 3
	c.total_points = 4321
	c.bet_idx = 4
	c.free_spins = 3
	c.free_bet = 200
	c.winds[2] = true
	c.wind_start = 3
	c.flowers[5] = true
	c.flower_start[1] = 2
	c.big.slots[3] = true
	c.hand.skill = 1
	c.scripted = board(filler_rows())
	c.spin()
	var path := "user://test_save.json"
	c.save(path)
	var d := MJCore.new()
	ok(d.load_save(path), "读档成功")
	ok(d.tpl_idx == c.tpl_idx and d.slots == c.slots, "恢复模板与槽位")
	ok(d.total_points == c.total_points and d.winds == c.winds and d.flowers == c.flowers, "恢复积分/风位/花架")
	ok(d.bet_idx == c.bet_idx and d.free_spins == c.free_spins and d.free_bet == c.free_bet, "恢复投注档与免费转")
	ok(d.flower_start == c.flower_start and d.wind_start == c.wind_start, "恢复花架 / 风位的计转起点")
	ok(int(d.hand.staked) == int(c.hand.staked) and int(d.hand.paid) == int(c.hand.paid), "恢复本局已投注额")
	ok(d.big.slots == c.big.slots and d.hand.skill == 1, "恢复副线与技能")
	ok(d.state == c.state and d.grid.size() == 24, "恢复状态与盘面")
	ok(d.story_offer.size() == c.story_offer.size() and not d.story_offer.is_empty(), "恢复待选剧情")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func t_economy() -> void:
	# 每转扣注
	var c := mk()
	var b0 := c.total_points
	c.scripted = board(filler_rows())
	var ev := c.spin()
	var st := get_ev(ev, "stake")
	ok(c.total_points == b0 - 100 and st.get("bet", 0) == 100 and not st.get("free", true), "每转扣当前投注 100")
	ok(get_ev(ev, "win").get("win", -1) == 0, "空转赢分为 0")
	ok(int(c.hand.paid) == 100 and int(c.hand.staked) == 100, "本局已付/名义投注累计")
	# 调档
	ok(c.change_bet(1) and c.bet() == 200, "加注一档")
	ok(c.change_bet(-9) and c.bet() == MJCore.BETS[0], "减注到最低档封底")
	ok(not c.change_bet(-1), "最低档不能再减")
	# 赔率随投注等比
	var hi := mk()
	hi.bet_idx = 5
	var rows := filler_rows()
	rows[3][0] = "m1"; rows[3][1] = "m1"; rows[3][2] = "m1"
	hi.scripted = board(rows) + refill(6)
	var st2 := get_ev(hi.spin(), "step")
	ok(st2.groups[0].pts == 150, "消除赔率随投注等比 (5000 × 0.01 × 3 = 150, 实际 %d)" % st2.groups[0].pts)
	# 余额不足：自动降档
	var lo := mk()
	lo.bet_idx = 2
	lo.total_points = 250
	lo.scripted = board(filler_rows())
	var ev3 := lo.spin()
	ok(has(ev3, "bet_down") and lo.bet() == 200 and lo.total_points == 50, "余额不足自动降到付得起的档")
	# 连最低档都不够：免费补给
	lo.scripted = board(filler_rows())
	var ev4 := lo.spin()
	ok(has(ev4, "supply") and lo.total_points == 50 + MJCore.SUPPLY_PTS - MJCore.BETS[0], "最低档也不够则免费补给后照常扣注")
	# 免费转：不扣余额、消除翻倍、不能改注
	var f := mk()
	f.free_spins = 2
	f.free_bet = 200
	var fb := f.total_points
	rows = filler_rows()
	rows[3][0] = "m1"; rows[3][1] = "m1"; rows[3][2] = "m1"
	f.scripted = board(rows) + refill(6)
	var ev5 := f.spin()
	var fs := get_ev(ev5, "stake")
	var fg := get_ev(ev5, "step")
	ok(fs.get("free", false) and f.free_spins == 1, "免费转消耗一次")
	ok(fg.groups[0].pts == 12, "免费转按触发时投注 200、消除翻倍 (200×0.01×3×2 = 12, 实际 %d)" % fg.groups[0].pts)
	ok(f.total_points == fb + 12, "免费转不扣余额")
	ok(not f.change_bet(1), "免费转期间不能改投注")
	ok(int(f.hand.paid) == 0 and int(f.hand.staked) == 200, "免费转计入名义投注、不计已付")
	# 胡牌按本局平均投注；大奖送免费转
	var w := mk()
	fill_to(w, 14)
	w.slots[0] = 3; w.slots[1] = 3; w.slots[2] = 3; w.slots[3] = 3  # 16 点 → 品级系数 3.0
	w.scripted = board(hu_rows()) + refill(6)
	var r: Dictionary = get_ev(w.spin(), "settle").get("result", {})
	var hx: float = MJCore.HU_X * 3.0 * 3.0
	ok(is_equal_approx(r.get("hu_x", 0.0), hx) and r.get("hu_pts", 0) == int(round(100 * hx)), "胡牌赔率 = HU_X × 任务系数 × 品级系数")
	var want_tier := 2 if hx >= MJCore.SUPER_WIN_X else (1 if hx >= MJCore.BIG_WIN_X else 0)
	ok(r.get("tier", -1) == want_tier, "大奖分级按胡牌赔率")
	ok(w.free_spins == [0, MJCore.FREE_BIG_WIN, MJCore.FREE_SUPER_WIN][want_tier] and w.free_bet == 100, "大奖送免费转并锁定投注")
	# 大牌：按副线期间平均投注 × 倍数，并送免费转
	var g := mk()
	for i in 14:
		g.big.slots[i] = true
	fill_to(g, 3)
	g.scripted = board(hu_rows()) + refill(6)
	var be := get_ev(g.spin(), "big_hu")
	ok(be.get("pts", 0) == int(round(MJCore.BIG_HANDS[0].x * 100)), "大牌分 = 平均投注 × 大牌倍数")
	ok(g.free_spins == MJCore.FREE_BIG_HAND, "大牌亮相送免费转")
	ok(int(g.big.staked) == 0 and int(g.big.spins) == 0, "大牌胡后副线投注累计清零")
	# 钻石局概率合计
	var psum := 0.0
	for t in MJCore.DIAMOND_TIERS:
		psum += t[1]
	ok(is_equal_approx(psum, 1.0), "钻石局奖档概率合计 100%")
	# 所有投注档下派彩都是整数（赔率精确到 0.01 倍、投注是 100 的整数倍）
	var exact := true
	for bv in MJCore.BETS:
		for x in [MJCore.CLEAR_X, MJCore.FLOWER_DUP_X, MJCore.STORY_GOLD_X, MJCore.STORY_ZHAN_X] + MJCore.FLOWER_TIER_X + MJCore.WIND_TIER_X:
			if not is_equal_approx(x * bv, round(x * bv)): exact = false
		if bv % 100 != 0: exact = false
	ok(exact, "各投注档派彩无舍入偏差")


func simulate() -> void:
	print("== 仿真 (2000 局) ==")
	var c := MJCore.new()
	c.rng.seed = 2026
	var spins := []
	var pts := []
	var ready_wait := []
	var per_tpl := {}
	var big_hu := 0
	var dia := 0
	var hands := 0
	var total_spins := 0
	var wait := 0
	while hands < 2000 and total_spins < 400000:
		var ev := c.spin()
		total_spins += 1
		if c.state == "ready":
			wait += 1
		for e in ev:
			if e.t == "story":
				c.choose_story(total_spins % 2)
			elif e.t == "big_hu":
				big_hu += 1
			elif e.t == "settle":
				hands += 1
				spins.append(e.result.spins)
				pts.append(e.result.total)
				ready_wait.append(wait)
				wait = 0
				if e.result.diamond:
					dia += 1
				var k: String = e.result.name
				if not per_tpl.has(k):
					per_tpl[k] = []
				per_tpl[k].append(e.result.spins)
		if c.can_zhan():
			c.use_zhan()
	spins.sort()
	pts.sort()
	ready_wait.sort()
	var n := spins.size()
	print("完局 %d, 总转数 %d" % [n, total_spins])
	if n == 0:
		return
	print("完局转数 P50=%d P90=%d P99=%d max=%d" % [spins[n / 2], spins[n * 9 / 10], spins[n * 99 / 100], spins[-1]])
	print("成牌到胡等待 P50=%d P90=%d P99=%d" % [ready_wait[n / 2], ready_wait[n * 9 / 10], ready_wait[n * 99 / 100]])
	print("本局积分 P50=%d P90=%d max=%d" % [pts[n / 2], pts[n * 9 / 10], pts[-1]])
	print("大牌胡 %d 次, 钻石局资格 %d 次" % [big_hu, dia])
	for k in per_tpl:
		var a: Array = per_tpl[k]
		a.sort()
		print("  %s: %d 局, P50=%d P90=%d" % [k, a.size(), a[a.size() / 2], a[a.size() * 9 / 10]])
