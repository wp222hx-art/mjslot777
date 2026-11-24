extends SceneTree
## RTP 测算：godot --headless --path . -s tests/rtp.gd -- spins=1000000 seed=1 bet=2 story=mix
##   spins  实际转数（含免费转）      seed  随机种子      bet  投注档位下标（0..5）
##   story  短剧情选择：gold / zhan / mix / skip
## 输出：总返还率、分项返还率、免费转占比、命中率、波动、单局与分段盈亏分布。
## 口径：RTP = 全部派彩 ÷ 实际扣掉的投注；免费转的派彩算返还、不算投注；免费补给不算返还。

const KEYS := ["clear", "clear_free", "flower_dup", "flower_set", "wind_set", "story", "hu", "big", "diamond"]
const NAMES := {"clear": "消除（付费转）", "clear_free": "消除（免费转）", "flower_dup": "重复花牌", "flower_set": "花架集齐",
	"wind_set": "四风齐", "story": "短剧情奖励", "hu": "胡牌", "big": "大牌亮相", "diamond": "钻石局抽取"}


func arg(name: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(name + "="):
			return a.substr(name.length() + 1)
	return def


func _init() -> void:
	var n := int(arg("spins", "200000"))
	var seed_v := int(arg("seed", "1"))
	var bet_idx := int(arg("bet", "2"))
	var story := arg("story", "mix")
	var c := MJCore.new()
	c.rng.seed = seed_v
	c.bet_idx = bet_idx
	c.total_points = 2000000000  # 足够大，测算中不会触发降档 / 补给
	var bet := float(c.bet())
	var start_bal := c.total_points

	var won := {}
	for k in KEYS:
		won[k] = 0
	var paid := 0
	var paid_spins := 0
	var free_spins := 0
	var hits := 0
	var sum_w := 0.0
	var sum_w2 := 0.0
	var max_w := 0.0
	var hands := 0
	var hand_spins := 0
	var tiers := [0, 0, 0]
	var bigs := 0
	var dia := 0
	var dia_top := 0
	var dia_ev := 0.0  # 钻石局按期望值计（去掉抽奖本身的运气）
	var free_awards := 0
	var supply := 0
	var hand_net: Array = []
	var seg_net: Array = []
	var seg := 0.0
	var seg_n := 0
	var ev_draw := 0.0
	for t in MJCore.DIAMOND_TIERS:
		ev_draw += t[0] * t[1]
	var hu_hist := {}    # 任务系数×品级系数 → 次数
	var big_hist := {}   # 大牌 id → 次数
	var size_hist := {}  # 消除组张数 → 次数
	var units := 0       # Σ 张数×连消数（消除赔率的计量单位）
	var dup_n := 0
	var fset_n := 0
	var wset_n := 0
	var bonus_spins := {"flower": [], "wind": []}
	var bonus_tier := {"flower": [0, 0, 0], "wind": [0, 0, 0]}
	var bonus_won := {"flower": [0, 0, 0], "wind": [0, 0, 0]}
	var buckets := [0, 0, 0, 0, 0, 0, 0]  # 单转赢分：0 / <1 / 1-2 / 2-5 / 5-20 / 20-100 / ≥100 倍
	var t0 := Time.get_ticks_msec()

	for i in n:
		var bal0 := c.total_points
		var ev := c.spin()
		var is_free := false
		var stake := 0
		var pend: Array = ev.duplicate()
		while not pend.is_empty():
			var e: Dictionary = pend.pop_front()
			match e.t:
				"stake":
					is_free = e.free
					stake = 0 if e.free else int(e.bet)
				"supply":
					supply += int(e.pts)
				"step":
					for g in e.groups:
						won["clear_free" if is_free else "clear"] += int(g.pts)
						if g.kind != "hu":
							units += g.cells.size() * int(e.chain)
							var sz: int = min(g.cells.size(), 6)
							size_hist[sz] = size_hist.get(sz, 0) + 1
					for f in e.flowers:
						won["flower_dup"] += int(f.pts)
						if not f.new: dup_n += 1
					for b in e.bonus:
						won["flower_set" if b.kind == "flower" else "wind_set"] += int(b.pts)
						if b.kind == "flower": fset_n += 1
						else: wset_n += 1
						bonus_spins[b.kind].append(int(b.spins))
						bonus_tier[b.kind][int(b.tier)] += 1
						bonus_won[b.kind][int(b.tier)] += int(b.pts)
				"story":
					var ch := 0
					match story:
						"zhan": ch = 1
						"skip": ch = -1
						"mix": ch = i % 2
					pend.append_array(c.choose_story(ch))
				"settle":
					var r: Dictionary = e.result
					won["hu"] += int(r.hu_pts)
					won["story"] += int(r.story_pts)
					hands += 1
					hand_spins += int(r.spins)
					tiers[int(r.tier)] += 1
					var hk := snappedf(float(r.coef) * float(r.grade_coef), 0.01)
					hu_hist[hk] = hu_hist.get(hk, 0) + 1
					hand_net.append((float(r.total) - float(r.paid)) / bet)
					if r.diamond:
						dia += 1
						dia_ev += ev_draw * float(r.bet)
						var d := c.draw_diamond()
						won["diamond"] += int(d.pts)
						if d.top:
							dia_top += 1
				"big_hu":
					won["big"] += int(e.pts)
					bigs += 1
					big_hist[e.id] = big_hist.get(e.id, 0) + 1
				"free_award":
					free_awards += int(e.n)
		if c.can_zhan():
			c.use_zhan()
		if is_free:
			free_spins += 1
		else:
			paid_spins += 1
			paid += stake
		# 本转净派彩（含同一转触发的胡牌、大牌、钻石抽取）
		var w := float(c.total_points - bal0 + stake) / bet
		# 剧情奖励在结算时入账，这里按入账时刻计
		if w > 0.0:
			hits += 1
		sum_w += w
		sum_w2 += w * w
		max_w = max(max_w, w)
		var bi := 0
		if w <= 0.0: bi = 0
		elif w < 1.0: bi = 1
		elif w < 2.0: bi = 2
		elif w < 5.0: bi = 3
		elif w < 20.0: bi = 4
		elif w < 100.0: bi = 5
		else: bi = 6
		buckets[bi] += 1
		seg += w - (0.0 if is_free else 1.0)
		seg_n += 1
		if seg_n == 200:
			seg_net.append(seg)
			seg = 0.0
			seg_n = 0

	var total_won := 0
	for k in KEYS:
		total_won += won[k]
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	print("== RTP 测算 ==  转数 %d（付费 %d + 免费 %d） 种子 %d 投注 %d 剧情策略 %s 用时 %.1fs" % [n, paid_spins, free_spins, seed_v, int(bet), story, secs])
	# 对账：余额变化必须等于 派彩 - 投注 + 补给，否则说明有漏记的入账
	var delta := c.total_points - start_bal
	var pending_story := int(c.hand.story_pts)  # 未结算的一局里尚未入账的剧情奖励不在余额里
	var expect := total_won - paid + supply
	print("对账：余额变化 %d，派彩-投注 %d  →  %s" % [delta, expect, "一致" if delta == expect else "不一致（差 %d，未结算局的剧情奖励 %d）" % [delta - expect, pending_story]])
	print("总投注 %d   总派彩 %d   RTP = %.2f%%" % [paid, total_won, 100.0 * total_won / max(paid, 1)])
	print("-- 分项返还率（占总投注） --")
	for k in KEYS:
		print("  %-10s %7.2f%%   %d" % [NAMES[k], 100.0 * won[k] / max(paid, 1), won[k]])
	var rtp_ev: float = 100.0 * (total_won - won["diamond"] + dia_ev) / max(paid, 1)
	print("钻石局按期望值计的 RTP = %.2f%%（单次抽取期望 %.1f 倍；实际抽 %d 次，命中最高档 %d 次）" % [rtp_ev, ev_draw, dia, dia_top])
	print("-- 节奏 --")
	print("  完局 %d，平均每局 %.1f 转；普通胡 %d / 大奖 %d / 超级大奖 %d；大牌亮相 %d 次" % [hands, float(hand_spins) / max(hands, 1), tiers[0], tiers[1], tiers[2], bigs])
	print("  免费转占比 %.2f%%（共送出 %d 次）；每 %.0f 转触发一次大奖以上" % [100.0 * free_spins / n, free_awards, float(n) / max(tiers[1] + tiers[2], 1)])
	print("-- 频率（调参用，与赔率数值无关） --")
	print("  每转：消除计量 %.3f（Σ张数×连消）  重复花牌 %.4f  花架集齐 %.5f  四风齐 %.5f" % [float(units) / n, float(dup_n) / n, float(fset_n) / n, float(wset_n) / n])
	print("  每转：完局 %.5f  大牌 %.5f  钻石局 %.6f" % [float(hands) / n, float(bigs) / n, float(dia) / n])
	var hk2 := hu_hist.keys()
	hk2.sort()
	var hl := "  胡牌 任务×品级 分布："
	var hsum := 0.0
	for k in hk2:
		hl += "%s: %.1f%%  " % [str(k), 100.0 * hu_hist[k] / max(hands, 1)]
		hsum += float(k) * hu_hist[k]
	print(hl)
	print("  胡牌 任务×品级 均值 %.3f；大牌分布 %s；消除组张数分布 %s" % [hsum / max(hands, 1), str(big_hist), str(size_hist)])
	for kind in ["flower", "wind"]:
		var arr: Array = bonus_spins[kind]
		arr.sort()
		var m3 := arr.size()
		if m3 < 10:
			continue
		var cum := ""
		for lim in [1, 2, 3, 4, 5, 6, 8, 10, 12, 15, 18, 22, 26, 30, 40, 60]:
			cum += "≤%d: %.1f%%  " % [lim, 100.0 * arr.bsearch(lim + 1) / m3]
		print("  %s 集齐用转数：P10=%d P25=%d P50=%d P75=%d P90=%d  累计 %s" % ["花架" if kind == "flower" else "风位", arr[m3 / 10], arr[m3 / 4], arr[m3 / 2], arr[m3 * 3 / 4], arr[m3 * 9 / 10], cum])
		var bt: Array = bonus_tier[kind]
		var bw: Array = bonus_won[kind]
		print("  %s 分档：普通 %.1f%% / 快 %.1f%% / 极快 %.1f%%；返还率 %.2f%% / %.2f%% / %.2f%%" % ["花架" if kind == "flower" else "风位", 100.0 * bt[0] / m3, 100.0 * bt[1] / m3, 100.0 * bt[2] / m3, 100.0 * bw[0] / max(paid, 1), 100.0 * bw[1] / max(paid, 1), 100.0 * bw[2] / max(paid, 1)])
	print("-- 波动 --")
	var mean := sum_w / n
	var sd := sqrt(max(sum_w2 / n - mean * mean, 0.0))
	print("  命中率 %.1f%%（有派彩的转数占比）；单转派彩标准差 %.2f 倍；单转最大 %.0f 倍" % [100.0 * hits / n, sd, max_w])
	var names := ["0", "<1", "1-2", "2-5", "5-20", "20-100", ">=100"]
	var line := "  单转派彩分布(倍)："
	for j in buckets.size():
		line += "%s: %.2f%%  " % [names[j], 100.0 * buckets[j] / n]
	print(line)
	hand_net.sort()
	seg_net.sort()
	if hand_net.size() > 10:
		var m := hand_net.size()
		var lose := 0
		for v in hand_net:
			if v < 0.0: lose += 1
		print("  单局净盈亏(倍)：P10=%.1f P50=%.1f P90=%.1f P99=%.1f；亏损局占比 %.1f%%" % [hand_net[m / 10], hand_net[m / 2], hand_net[m * 9 / 10], hand_net[m * 99 / 100], 100.0 * lose / m])
	if seg_net.size() > 10:
		var m2 := seg_net.size()
		var up := 0
		for v in seg_net:
			if v > 0.0: up += 1
		print("  每 200 转净盈亏(倍)：P5=%.0f P25=%.0f P50=%.0f P75=%.0f P95=%.0f；盈利段占比 %.1f%%" % [seg_net[m2 / 20], seg_net[m2 / 4], seg_net[m2 / 2], seg_net[m2 * 3 / 4], seg_net[m2 * 19 / 20], 100.0 * up / m2])
	print("RESULT rtp=%.4f rtp_ev=%.4f free=%.4f hands=%d" % [float(total_won) / max(paid, 1), rtp_ev / 100.0, float(free_spins) / n, hands])
	quit(0)
