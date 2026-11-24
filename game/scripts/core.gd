class_name MJCore
extends RefCounted
## 麻将·转运胡 规则内核（不依赖界面，可无头测试）。
## 每次操作返回事件列表，界面只负责按事件演出：动画不是判定器。

const COLS := 6
const ROWS := 4
const SAVE_VERSION := 3
const RULE_PACK := "国标灵感包"

const GRADE_NAMES := ["普通", "蓝", "紫", "金", "钻"]
const GRADE_PTS := [0, 1, 2, 4, 8]
## 整手品级系数（公开配置表）：按整手品级点数之和查表，不逐张相乘。
const GRADE_TABLE := [[16, 3.0], [8, 2.0], [4, 1.5], [1, 1.2], [0, 1.0]]
## 转轴牌品级出现概率（固定，不随进度变化）。
const GRADE_ODDS := [[4, 0.0015], [3, 0.008], [2, 0.02], [1, 0.05]]
## ---- 经济系统：全部是虚拟积分，赔率 = 投注的倍数（公开配置） ----
## 数值由 tests/rtp.gd 测算得出（目标 RTP≈96%），改动任何一项后都要重新跑测算。
## 投注档都是 100 的整数倍，赔率精确到 0.01 倍，所以所有派彩都是整数、没有舍入偏差。
const BETS := [100, 200, 500, 1000, 2000, 5000]
const START_BALANCE := 20000
const SUPPLY_PTS := 5000          # 余额不够最低投注时的免费补给
const CLEAR_X := 0.01             # 消除：每张牌 × 连消数
const FREE_CLEAR_MULT := 2        # 免费转期间消除赔率翻倍
const FLOWER_DUP_X := 0.01
## 集齐奖按速度分三档：从该组第一张上架到集齐用了几转（含首尾两转）。
## 档位 2 = 极快（≤ SPINS[0] 转）、1 = 快（≤ SPINS[1] 转）、0 = 普通。越快赔率越高、名字越雅、动画越大。
const FLOWER_TIER_SPINS := [3, 9]
const FLOWER_TIER_X := [0.1, 0.25, 1.5]
const WIND_TIER_SPINS := [8, 22]
const WIND_TIER_X := [0.3, 0.7, 4.0]
const BONUS_NAMES := {
	"flower0": ["四季平安", "四季如花", "岁岁繁花"],   # 春夏秋冬
	"flower1": ["四君子", "兰亭雅集", "香满乾坤"],     # 梅兰竹菊
	"wind": ["四风齐", "东南西北风", "风生水起"],
}
## 短剧情二选一的奖励（公开）：黄金牌自带品级加成，所以不再另给积分；「斩」给积分补偿，两者期望接近。
const STORY_GOLD_X := 0.0
const STORY_ZHAN_X := 1.45
const HU_X := 1.8                 # 胡牌 = 本局平均投注 × HU_X × 任务系数 × 整手品级系数
const BIG_WIN_X := 10.0           # 胡牌赔率达到此倍数 = 大奖
const SUPER_WIN_X := 14.0         # = 超级大奖
const FREE_BIG_WIN := 3           # 大奖送免费转
const FREE_SUPER_WIN := 8
const FREE_BIG_HAND := 8          # 大牌亮相送免费转
const FREE_DIAMOND_TOP := 20      # 钻石局命中最高档送免费转
const AID_DRY_SPINS := 8
const BIG_MIN_CELLS := 4          # 四连及以上的消除才攒进大牌副线
## 钻石局抽取奖档（公开）：[投注倍数, 概率]
const DIAMOND_TIERS := [[200.0, 0.01], [50.0, 0.09], [10.0, 0.30], [2.0, 0.60]]

## 固定符号池权重（每局开局按模板锁定，局内不变）。
const W_BASE := 1.0      # 全部 34 种普通牌的底权重
const W_TARGET := 3.2
const W_BIG := 1.5
const W_WIND := 1.4
const W_FLOWER := 0.55
const W_HU := 5.0
const W_WILD := 2.2
const CLUSTER := 0.30

const LEVELS := [[0, "入门学徒"], [300, "茶馆好手"], [1000, "流派达人"], [2500, "百番宗师"], [6000, "万象雀神"]]

const TEMPLATES := [
	{"id": "qys_pph", "name": "清一色碰碰和", "fan_name": "碰碰和", "fan": 6, "coef": 3.0,
		"melds": [["m1", "m1", "m1"], ["m3", "m3", "m3"], ["m5", "m5", "m5"], ["m7", "m7", "m7"], ["m9", "m9"]]},
	{"id": "duanyao", "name": "断幺", "fan_name": "断幺", "fan": 2, "coef": 1.5,
		"melds": [["m2", "m3", "m4"], ["p4", "p5", "p6"], ["s6", "s7", "s8"], ["p3", "p4", "p5"], ["s5", "s5"]]},
	{"id": "qidui", "name": "七对", "fan_name": "七对", "fan": 24, "coef": 4.0,
		"melds": [["m2", "m2"], ["m5", "m5"], ["p2", "p2"], ["p8", "p8"], ["s5", "s5"], ["z1", "z1"], ["z5", "z5"]]},
	{"id": "hunyise", "name": "混一色", "fan_name": "混一色", "fan": 6, "coef": 2.5,
		"melds": [["s1", "s2", "s3"], ["s4", "s5", "s6"], ["s7", "s8", "s9"], ["z1", "z1", "z1"], ["z6", "z6"]]},
	{"id": "sansetong", "name": "三色三同顺", "fan_name": "三色三同顺", "fan": 8, "coef": 2.0,
		"melds": [["m1", "m2", "m3"], ["p1", "p2", "p3"], ["s1", "s2", "s3"], ["m7", "m8", "m9"], ["p5", "p5"]]},
]

const BIG_HANDS := [
	{"id": "ssy", "name": "十三幺", "fan": 88, "x": 25.0,
		"tiles": ["m1", "m1", "m9", "p1", "p9", "s1", "s9", "z1", "z2", "z3", "z4", "z5", "z6", "z7"]},
	{"id": "qd", "name": "七对", "fan": 24, "x": 10.0,
		"tiles": ["m2", "m2", "m5", "m5", "p2", "p2", "p8", "p8", "s5", "s5", "z1", "z1", "z5", "z5"]},
	{"id": "qys", "name": "清一色", "fan": 24, "x": 10.0,
		"tiles": ["m1", "m1", "m1", "m2", "m3", "m4", "m5", "m6", "m7", "m8", "m8", "m8", "m9", "m9"]},
	{"id": "dsy", "name": "大三元", "fan": 88, "x": 25.0,
		"tiles": ["z5", "z5", "z5", "z6", "z6", "z6", "z7", "z7", "z7", "m1", "m2", "m3", "p9", "p9"]},
	{"id": "zys", "name": "字一色", "fan": 64, "x": 15.0,
		"tiles": ["z1", "z1", "z1", "z2", "z2", "z2", "z3", "z3", "z3", "z5", "z5", "z5", "z4", "z4"]},
]

## 国标 81 番种目录（1998 试行规则公开资料整理，图鉴用）。
const FAN_CATALOG := [
	[88, ["大四喜", "大三元", "绿一色", "九莲宝灯", "四杠", "连七对", "十三幺"]],
	[64, ["清幺九", "小四喜", "小三元", "字一色", "四暗刻", "一色双龙会"]],
	[48, ["一色四同顺", "一色四节高"]],
	[32, ["一色四步高", "三杠", "混幺九"]],
	[24, ["七对", "七星不靠", "全双刻", "清一色", "一色三同顺", "一色三节高", "全大", "全中", "全小"]],
	[16, ["清龙", "三色双龙会", "一色三步高", "全带五", "三同刻", "三暗刻"]],
	[12, ["全不靠", "组合龙", "大于五", "小于五", "三风刻"]],
	[8, ["花龙", "推不倒", "三色三同顺", "三色三节高", "无番和", "妙手回春", "海底捞月", "杠上开花", "抢杠和"]],
	[6, ["碰碰和", "混一色", "三色三步高", "五门齐", "全求人", "双暗杠", "双箭刻"]],
	[4, ["全带幺", "不求人", "双明杠", "和绝张"]],
	[2, ["箭刻", "圈风刻", "门风刻", "门前清", "平和", "四归一", "双同刻", "双暗刻", "暗杠", "断幺"]],
	[1, ["一般高", "喜相逢", "连六", "老少副", "幺九刻", "明杠", "缺一门", "无字", "边张", "坎张", "单钓将", "自摸", "花牌"]],
]

const NUM_CN := ["一", "二", "三", "四", "五", "六", "七", "八", "九"]
const HONOR_CN := ["东", "南", "西", "北", "红中", "发财", "白板"]
const FLOWER_CN := ["春", "夏", "秋", "冬", "梅", "兰", "竹", "菊"]

var rng := RandomNumberGenerator.new()
var scripted: Array = []  # 测试用：非空时按序取符号（"m1" 或 "m1:3" 带品级）

var state := "pending"  # pending / collect / ting / ready
var tpl_idx := -1
var need: Array = []
var slots: Array = []   # -1 空；否则为品级 0..4
var meld_ranges: Array = []
var groups_done: Array = []
var pool: Dictionary = {}
var grid: Array = []
var hand := {}
var big := {"idx": 0, "slots": [], "staked": 0, "spins": 0}
var flowers: Array = []
var winds: Array = []
var flower_start: Array = [-1, -1]  # 每组花第一张上架时的 spin_no；-1 = 该组还没开始
var wind_start := -1
var total_points := START_BALANCE  # 余额
var bet_idx := 0
var free_spins := 0
var free_bet := 0
var xp := 0
var hand_no := 0
var spin_no := 0
var records := {"small": {}, "big": {}, "fans": {}}
var recent: Array = []
var collection: Dictionary = {}
var last_result: Dictionary = {}
var story_offer: Dictionary = {}
var settings := {"music": true, "sfx": true, "voice": true, "reduce": false}


func _init() -> void:
	rng.randomize()
	flowers.resize(8); flowers.fill(false)
	winds.resize(4); winds.fill(false)
	big.slots = []
	big.slots.resize(14); big.slots.fill(false)
	_new_hand_blank()


func _new_hand_blank() -> void:
	hand = {"clear_pts": 0, "set_pts": 0, "story_pts": 0, "spins": 0, "story_done": false,
		"aid_done": false, "skill": 0, "dry": 0, "staked": 0, "paid": 0, "last_bet": 0, "free_n": 0}


# ---------- 名称与查询 ----------

static func tile_name(id: String) -> String:
	if id == "hu": return "胡"
	if id == "wild": return "百搭"
	var n := int(id.substr(1)) - 1
	match id[0]:
		"m": return NUM_CN[n] + "万"
		"p": return NUM_CN[n] + "筒"
		"s": return NUM_CN[n] + "条"
		"z": return HONOR_CN[n]
		"f": return FLOWER_CN[n]
	return id

static func is_flower(id: String) -> bool:
	return id.begins_with("f")

static func is_tile(id: String) -> bool:
	return id != "hu" and id != "wild" and not id.begins_with("f")

func tpl() -> Dictionary:
	return TEMPLATES[tpl_idx] if tpl_idx >= 0 else {}

func big_tpl() -> Dictionary:
	return BIG_HANDS[big.idx]

func filled() -> int:
	var n := 0
	for s in slots:
		if s >= 0: n += 1
	return n

func big_filled() -> int:
	var n := 0
	for s in big.slots:
		if s: n += 1
	return n

func missing() -> Dictionary:
	var d := {}
	for i in need.size():
		if slots[i] < 0:
			d[need[i]] = d.get(need[i], 0) + 1
	return d

func grade_sum() -> int:
	var n := 0
	for s in slots:
		if s > 0: n += GRADE_PTS[s]
	return n

func grade_coef() -> float:
	var g := grade_sum()
	for row in GRADE_TABLE:
		if g >= row[0]: return row[1]
	return 1.0

func level() -> int:
	var lv := 0
	for i in LEVELS.size():
		if xp >= LEVELS[i][0]: lv = i
	return lv

func level_name() -> String:
	return LEVELS[level()][1]

func bet() -> int:
	return BETS[bet_idx]

## 本局平均投注（含免费转的名义投注）；胡牌按它结算，所以中途改投注也公平
func avg_bet() -> int:
	if hand.spins <= 0 or hand.staked <= 0:
		return bet()
	return int(round(float(hand.staked) / hand.spins))

func big_avg_bet() -> int:
	if int(big.spins) <= 0:
		return bet()
	return int(round(float(big.staked) / int(big.spins)))

## 调整投注档位；免费转期间按触发时的投注进行，不能改
func change_bet(delta: int) -> bool:
	if free_spins > 0:
		return false
	var n := clampi(bet_idx + delta, 0, BETS.size() - 1)
	if n == bet_idx:
		return false
	bet_idx = n
	return true

func _award_free(n: int, b: int) -> void:
	if free_spins <= 0:
		free_bet = b
	free_spins += n


## 集齐速度档位：用了 used 转 → 2 极快 / 1 快 / 0 普通
static func speed_tier(used: int, limits: Array) -> int:
	if used <= int(limits[0]): return 2
	if used <= int(limits[1]): return 1
	return 0


func can_zhan() -> bool:
	return state == "ting" and hand.skill > 0


# ---------- 开局 ----------

func _start_hand(events: Array) -> void:
	var idx := tpl_idx
	if scripted.is_empty() or tpl_idx < 0:
		while idx == tpl_idx:
			idx = rng.randi_range(0, TEMPLATES.size() - 1)
	_setup_template(idx)
	hand_no += 1
	_new_hand_blank()
	last_result = {}
	story_offer = {}
	state = "collect"
	events.append({"t": "new_hand", "id": tpl().id, "name": tpl().name, "fan_name": tpl().fan_name, "fan": tpl().fan, "coef": tpl().coef})

func _setup_template(idx: int) -> void:
	tpl_idx = idx
	need = []
	meld_ranges = []
	for m in TEMPLATES[idx].melds:
		meld_ranges.append([need.size(), m.size()])
		need.append_array(m)
	slots = []
	slots.resize(need.size()); slots.fill(-1)
	groups_done = []
	_build_pool()

func _build_pool() -> void:
	pool = {}
	for suit in ["m", "p", "s"]:
		for i in 9: pool["%s%d" % [suit, i + 1]] = W_BASE
	for i in 7: pool["z%d" % (i + 1)] = W_BASE
	for i in 4: pool["z%d" % (i + 1)] = W_WIND
	for id in big_tpl().tiles:
		pool[id] = max(pool[id], W_BIG)
	for id in need:
		pool[id] = W_TARGET
	for i in 8:
		pool["f%d" % (i + 1)] = W_FLOWER
	pool["hu"] = W_HU
	pool["wild"] = W_WILD

func force_template(idx: int) -> void:  # 测试 / 调试
	_setup_template(idx)
	_new_hand_blank()
	state = "collect"
	last_result = {}
	story_offer = {}


# ---------- 符号生成 ----------

func _cell(c: int, r: int) -> Variant:
	if c < 0 or c >= COLS or r < 0 or r >= ROWS: return null
	return grid[r * COLS + c]

func _gen(c: int, r: int) -> Dictionary:
	if not scripted.is_empty():
		var s: String = scripted.pop_front()
		var parts := s.split(":")
		return {"id": parts[0], "g": int(parts[1]) if parts.size() > 1 else 0}
	var id := ""
	if rng.randf() < CLUSTER:
		var cand := []
		for d in [[-1, 0], [1, 0], [0, 1], [0, -1]]:
			var n = _cell(c + d[0], r + d[1])
			if n != null and n.id != "wild" and not is_flower(n.id):
				cand.append(n.id)
		if not cand.is_empty():
			id = cand[rng.randi_range(0, cand.size() - 1)]
	if id == "":
		var total := 0.0
		for k in pool: total += pool[k]
		var x := rng.randf() * total
		for k in pool:
			x -= pool[k]
			if x <= 0.0:
				id = k
				break
		if id == "": id = pool.keys()[0]
	var g := 0
	if is_tile(id):
		var x2 := rng.randf()
		for row in GRADE_ODDS:
			if x2 < row[1]:
				g = row[0]
				break
			x2 -= row[1]
	return {"id": id, "g": g}

func _fill_grid() -> void:
	grid = []
	grid.resize(COLS * ROWS)
	for r in range(ROWS - 1, -1, -1):
		for c in COLS:
			grid[r * COLS + c] = _gen(c, r)

func _snapshot() -> Array:
	var out := []
	for cell in grid:
		out.append({"id": cell.id, "g": cell.g})
	return out


# ---------- 成组检测 ----------

func _find_groups() -> Array:
	var out := []
	var seen := {}
	for i in grid.size():
		var id: String = grid[i].id
		if id == "wild" or is_flower(id) or seen.has(i): continue
		var comp := []
		var local := {i: true}
		var stack := [i]
		var real := 0
		while not stack.is_empty():
			var cur: int = stack.pop_back()
			comp.append(cur)
			if grid[cur].id == id:
				seen[cur] = true
				real += 1
			var c := cur % COLS
			var r := cur / COLS
			for d in [[-1, 0], [1, 0], [0, 1], [0, -1]]:
				var nc: int = c + d[0]
				var nr: int = r + d[1]
				if nc < 0 or nc >= COLS or nr < 0 or nr >= ROWS: continue
				var ni := nr * COLS + nc
				if local.has(ni): continue
				var nid: String = grid[ni].id
				# 百搭只帮普通牌成组，不替代「胡」字
				if nid == id or (nid == "wild" and id != "hu"):
					local[ni] = true
					stack.append(ni)
		if comp.size() >= 3 and real >= 1:
			comp.sort()
			var g := 0
			for ci in comp:
				if grid[ci].id == id: g = max(g, grid[ci].g)
			out.append({"kind": id, "cells": comp, "g": g})
	out.sort_custom(func(a, b): return a.cells[0] < b.cells[0])
	return out


# ---------- 入槽 ----------

func _put_main(kind: String, g: int, events_meld: Array) -> int:
	for i in need.size():
		if need[i] == kind and slots[i] < 0:
			slots[i] = g
			_check_melds(events_meld)
			return i
	return -1

func _check_melds(out: Array) -> void:
	for mi in meld_ranges.size():
		if groups_done.has(mi): continue
		var start: int = meld_ranges[mi][0]
		var n: int = meld_ranges[mi][1]
		var ok := true
		for j in n:
			if slots[start + j] < 0: ok = false
		if ok:
			groups_done.append(mi)
			var kind := "对子成组"
			if n == 3:
				kind = "刻子成组" if need[start] == need[start + 1] else "顺子成组"
			out.append({"meld": mi, "start": start, "n": n, "label": kind})

func _put_big(kind: String) -> int:
	var tiles: Array = big_tpl().tiles
	for i in tiles.size():
		if tiles[i] == kind and not big.slots[i]:
			big.slots[i] = true
			return i
	return -1


# ---------- 转动 ----------

func spin() -> Array:
	var events: Array = []
	if not story_offer.is_empty():
		return events  # 剧情选择未完成，不能转
	if state == "pending":
		_start_hand(events)
	spin_no += 1
	hand.spins += 1
	# 投注：免费转不扣余额；余额不够就自动降档，连最低档都不够则免费补给
	var free := free_spins > 0
	var b := 0
	if free:
		free_spins -= 1
		b = free_bet if free_bet > 0 else bet()
		hand.free_n += 1
	else:
		if total_points < bet():
			while bet_idx > 0 and total_points < bet():
				bet_idx -= 1
			if total_points < bet():
				total_points += SUPPLY_PTS
				events.append({"t": "supply", "pts": SUPPLY_PTS})
			else:
				events.append({"t": "bet_down", "bet": bet()})
		b = bet()
		total_points -= b
		hand.paid += b
	hand.staked += b
	hand.last_bet = b
	big.staked = int(big.staked) + b
	big.spins = int(big.spins) + 1
	events.append({"t": "stake", "bet": b, "free": free, "free_left": free_spins, "balance": total_points})
	var bal0 := total_points
	var clear_mult := FREE_CLEAR_MULT if free else 1
	var filled_before := filled()
	var big_before := big_filled()
	_fill_grid()
	events.append({"t": "grid", "grid": _snapshot()})

	var hu_events := 0
	var chain := 0
	for _guard in 40:
		var groups := _find_groups()
		var fl := []
		for i in grid.size():
			if is_flower(grid[i].id): fl.append(i)
		if groups.is_empty() and fl.is_empty(): break
		if not groups.is_empty(): chain += 1
		var ev := {"t": "step", "chain": chain, "flowers": [], "groups": [], "bonus": [], "melds": [], "pts": 0}
		var removed := {}
		for i in fl:
			var fi := int(grid[i].id.substr(1)) - 1
			var is_new: bool = not flowers[fi]
			flowers[fi] = true
			if is_new and int(flower_start[fi >> 2]) < 0:
				flower_start[fi >> 2] = spin_no
			var p := 0 if is_new else int(round(FLOWER_DUP_X * b))
			ev.pts += p
			ev.flowers.append({"cell": i, "id": grid[i].id, "idx": fi, "new": is_new, "pts": p})
			removed[i] = true
		for set_i in 2:
			var all := true
			for k in 4:
				if not flowers[set_i * 4 + k]: all = false
			if all:
				for k in 4: flowers[set_i * 4 + k] = false
				var f_used: int = spin_no - int(flower_start[set_i]) + 1
				var ft := speed_tier(f_used, FLOWER_TIER_SPINS)
				flower_start[set_i] = -1
				var fp := int(round(FLOWER_TIER_X[ft] * b))
				hand.set_pts += fp
				ev.bonus.append({"kind": "flower", "set": set_i, "tier": ft, "spins": f_used, "x": FLOWER_TIER_X[ft],
					"name": BONUS_NAMES["flower%d" % set_i][ft], "pts": fp})
		for g in groups:
			var ge := {"kind": g.kind, "cells": g.cells, "g": g.g, "dest": "none", "slot": -1, "pts": 0, "wind": -1}
			for ci in g.cells: removed[ci] = true
			if g.kind == "hu":
				hu_events += 1
				ge.dest = "hu"
			else:
				ge.pts = int(round(CLEAR_X * b * g.cells.size() * chain * clear_mult))
				ev.pts += ge.pts
				var si := _put_main(g.kind, g.g, ev.melds)
				if si >= 0:
					ge.dest = "main"; ge.slot = si
				else:
					var bi := _put_big(g.kind) if g.cells.size() >= BIG_MIN_CELLS else -1
					if bi >= 0:
						ge.dest = "big"; ge.slot = bi
				if g.kind.begins_with("z") and int(g.kind.substr(1)) <= 4:
					var wi := int(g.kind.substr(1)) - 1
					if not winds[wi]:
						winds[wi] = true
						ge.wind = wi
						if wind_start < 0:
							wind_start = spin_no
			ev.groups.append(ge)
		var wall := true
		for w in winds:
			if not w: wall = false
		if wall:
			winds.fill(false)
			var w_used: int = spin_no - wind_start + 1
			var wt := speed_tier(w_used, WIND_TIER_SPINS)
			wind_start = -1
			var wp := int(round(WIND_TIER_X[wt] * b))
			hand.set_pts += wp
			ev.bonus.append({"kind": "wind", "tier": wt, "spins": w_used, "x": WIND_TIER_X[wt],
				"name": BONUS_NAMES["wind"][wt], "pts": wp})
		hand.clear_pts += ev.pts
		total_points += ev.pts
		for bn in ev.bonus: total_points += bn.pts
		ev.removed = removed.keys()
		ev.removed.sort()
		_collapse(removed)
		ev.grid = _snapshot()
		ev.filled = filled()
		ev.big_filled = big_filled()
		events.append(ev)

	# 公开援助：连续 N 转无新增有效槽位且仍缺牌，每局一次
	if filled() > filled_before: hand.dry = 0
	else: hand.dry += 1
	if hand.dry >= AID_DRY_SPINS and not hand.aid_done and filled() < need.size():
		hand.aid_done = true
		hand.dry = 0
		var melds := []
		for i in need.size():
			if slots[i] < 0:
				slots[i] = 0
				_check_melds(melds)
				events.append({"t": "aid", "slot": i, "id": need[i], "melds": melds, "filled": filled()})
				break

	# 大牌副线里程碑
	var bf := big_filled()
	for ms in [[7, "过半"], [13, "听牌"], [14, "成牌"]]:
		if big_before < ms[0] and bf >= ms[0]:
			events.append({"t": "big_ms", "label": ms[1], "n": bf, "name": big_tpl().name})

	_state_events(events, hu_events > 0)

	# 本转「胡」字：先处理完补牌、重算手牌，再判定
	if hu_events > 0:
		if filled() == need.size():
			_settle(events)
		elif bf == 14:
			_big_hu(events)
		else:
			events.append({"t": "hu_void", "filled": filled(), "total": need.size()})

	events.append({"t": "win", "win": total_points - bal0, "bet": b, "free": free, "balance": total_points})

	# 短剧情：每局最多一次，仅未成牌时
	if state != "pending" and not hand.story_done and filled() >= 6 and filled() <= need.size() - 2:
		_make_story_offer()
		events.append({"t": "story", "offer": story_offer})
	return events

func _state_events(events: Array, hu_this_spin: bool) -> void:
	var f := filled()
	var t := need.size()
	if f == t and state != "ready":
		state = "ready"
		events.append({"t": "ready", "merged": hu_this_spin})
	elif f == t - 1 and state != "ting":
		state = "ting"
		events.append({"t": "ting", "id": missing().keys()[0], "can_zhan": hand.skill > 0})
	elif f < t - 1:
		state = "collect"

func _collapse(removed: Dictionary) -> void:
	for c in COLS:
		var keep := []
		for r in range(ROWS - 1, -1, -1):
			var i := r * COLS + c
			if not removed.has(i): keep.append(grid[i])
		for r in range(ROWS - 1, -1, -1):
			var k := ROWS - 1 - r
			grid[r * COLS + c] = keep[k] if k < keep.size() else null
		for r in range(ROWS - 1, -1, -1):
			if grid[r * COLS + c] == null:
				grid[r * COLS + c] = _gen(c, r)


# ---------- 剧情 / 技能 ----------

func _make_story_offer() -> void:
	var miss := missing().keys()
	var gold_id: String = miss[rng.randi_range(0, miss.size() - 1)] if scripted.is_empty() else miss[0]
	story_offer = {"name": ["茶馆送错桌", "牌铺盘点"][hand_no % 2], "gold": gold_id,
		"pts_gold": int(round(STORY_GOLD_X * max(int(hand.last_bet), BETS[0]))),
		"pts_zhan": int(round(STORY_ZHAN_X * max(int(hand.last_bet), BETS[0])))}

## choice: 0 = 拿黄金牌（填槽并入收藏）；1 = 拿斩杀牌（技能）；-1 = 跳过
func choose_story(choice: int) -> Array:
	var events: Array = []
	if story_offer.is_empty() or hand.story_done: return events
	var offer := story_offer
	story_offer = {}
	hand.story_done = true
	if choice == 0:
		var melds := []
		var si := _put_main(offer.gold, 3, melds)
		collection[offer.gold] = collection.get(offer.gold, 0) + 1
		hand.story_pts += int(offer.pts_gold)
		events.append({"t": "story_gold", "id": offer.gold, "slot": si, "melds": melds, "filled": filled()})
		_state_events(events, false)
	elif choice == 1:
		hand.skill += 1
		hand.story_pts += int(offer.pts_zhan)
		events.append({"t": "story_skill", "can_zhan": can_zhan()})
	else:
		events.append({"t": "story_skip"})
	return events

## 尾张斩杀：仅 T-1 槽且确有技能时生效；补一张普通品级目标牌，不替代「胡」字。
func use_zhan() -> Array:
	var events: Array = []
	if not can_zhan(): return events
	hand.skill -= 1
	var melds := []
	for i in need.size():
		if slots[i] < 0:
			slots[i] = 0
			_check_melds(melds)
			events.append({"t": "zhan", "slot": i, "id": need[i], "melds": melds, "filled": filled()})
			break
	_state_events(events, false)
	return events


# ---------- 结算 ----------

func _settle(events: Array) -> void:
	var t := tpl()
	var gc := grade_coef()
	var ab := avg_bet()
	var hu_x: float = HU_X * t.coef * gc
	var hu_pts := int(round(ab * hu_x))
	var diamond := false
	for s in slots:
		if s == 4: diamond = true
	var total: int = hand.clear_pts + hu_pts + hand.set_pts + hand.story_pts
	total_points += hu_pts + hand.story_pts
	xp += int(100 * t.coef)
	# 大奖分级按胡牌赔率（投注的倍数）；大奖送免费转
	var tier := 2 if hu_x >= SUPER_WIN_X else (1 if hu_x >= BIG_WIN_X else 0)
	var free_n: int = [0, FREE_BIG_WIN, FREE_SUPER_WIN][tier]
	if free_n > 0:
		_award_free(free_n, ab)
	var rec: Dictionary = records.small.get(t.id, {"count": 0, "best": 0, "first": ""})
	rec.count += 1
	if rec.best == 0 or hand.spins < rec.best: rec.best = hand.spins
	if rec.first == "": rec.first = Time.get_date_string_from_system()
	records.small[t.id] = rec
	records.fans[t.fan_name] = true
	recent.push_front({"name": t.name, "spins": hand.spins, "pts": total})
	if recent.size() > 8: recent.resize(8)
	last_result = {"hand_no": hand_no, "id": t.id, "name": t.name, "fan_name": t.fan_name, "fan": t.fan,
		"bet": ab, "hu_x": hu_x, "coef": t.coef, "grade_coef": gc, "grade_sum": grade_sum(), "hu_pts": hu_pts,
		"clear_pts": hand.clear_pts, "set_pts": hand.set_pts, "story_pts": hand.story_pts, "total": total,
		"spins": hand.spins, "paid": hand.paid, "free_n": hand.free_n, "tier": tier, "free_award": free_n,
		"diamond": diamond, "drawn": false, "draw_pts": 0, "draw_top": false,
		"need": need.duplicate(), "slots": slots.duplicate(), "level": level_name()}
	state = "pending"
	events.append({"t": "settle", "result": last_result})
	if free_n > 0:
		events.append({"t": "free_award", "n": free_n, "left": free_spins, "reason": "超级大奖" if tier == 2 else "大奖"})

func _big_hu(events: Array) -> void:
	var b := big_tpl()
	var ab := big_avg_bet()
	var pts := int(round(b.x * ab))
	total_points += pts
	hand.set_pts += pts
	xp += 200
	_award_free(FREE_BIG_HAND, ab)
	var rec: Dictionary = records.big.get(b.id, {"count": 0, "best": 0, "first": ""})
	rec.count += 1
	rec.first = Time.get_date_string_from_system() if rec.first == "" else rec.first
	records.big[b.id] = rec
	records.fans[b.name] = true
	events.append({"t": "big_hu", "id": b.id, "name": b.name, "fan": b.fan, "pts": pts, "x": b.x, "bet": ab,
		"free": FREE_BIG_HAND, "tiles": b.tiles.duplicate()})
	events.append({"t": "free_award", "n": FREE_BIG_HAND, "left": free_spins, "reason": "大牌 " + String(b.name)})
	big.idx = (big.idx + 1) % BIG_HANDS.size()
	big.slots.fill(false)
	big.staked = 0
	big.spins = 0

## 钻石局抽取：资格与结果分开；每局只抽一次（幂等）。
func draw_diamond() -> Dictionary:
	if last_result.is_empty() or not last_result.diamond or last_result.drawn:
		return {}
	var x := rng.randf()
	var mult: float = DIAMOND_TIERS[-1][0]
	for i in DIAMOND_TIERS.size():
		if x < DIAMOND_TIERS[i][1]:
			mult = DIAMOND_TIERS[i][0]
			break
		x -= DIAMOND_TIERS[i][1]
	var b := int(last_result.bet)
	var pts := int(round(mult * b))
	var top: bool = mult == DIAMOND_TIERS[0][0]
	last_result.drawn = true
	last_result.draw_pts = pts
	last_result.draw_top = top
	total_points += pts
	var free_n := 0
	if top:
		free_n = FREE_DIAMOND_TOP
		_award_free(free_n, b)
	return {"pts": pts, "top": top, "x": mult, "free": free_n}


# ---------- 存档 ----------

func to_dict() -> Dictionary:
	return {"v": SAVE_VERSION, "pack": RULE_PACK, "state": state, "tpl_idx": tpl_idx, "slots": slots,
		"groups_done": groups_done, "grid": grid, "hand": hand, "big": big, "flowers": flowers, "winds": winds,
		"flower_start": flower_start, "wind_start": wind_start,
		"total_points": total_points, "xp": xp, "hand_no": hand_no, "spin_no": spin_no, "records": records,
		"recent": recent, "collection": collection, "last_result": last_result, "story_offer": story_offer,
		"settings": settings, "bet_idx": bet_idx, "free_spins": free_spins, "free_bet": free_bet}

func from_dict(d: Dictionary) -> bool:
	if int(d.get("v", 0)) != SAVE_VERSION: return false
	var idx := int(d.get("tpl_idx", -1))
	if idx >= TEMPLATES.size(): return false
	big = {"idx": int(d.big.idx) % BIG_HANDS.size(), "slots": _bools(d.big.slots, 14),
		"staked": int(d.big.get("staked", 0)), "spins": int(d.big.get("spins", 0))}
	if idx >= 0:
		_setup_template(idx)
		var s: Array = d.get("slots", [])
		if s.size() == need.size():
			for i in s.size(): slots[i] = int(s[i])
		groups_done = []
		for g in d.get("groups_done", []): groups_done.append(int(g))
	state = String(d.get("state", "pending"))
	grid = []
	for cell in d.get("grid", []):
		grid.append({"id": String(cell.id), "g": int(cell.g)})
	if grid.size() != COLS * ROWS: grid = []
	var h: Dictionary = d.get("hand", {})
	_new_hand_blank()
	for k in hand:
		if h.has(k):
			hand[k] = bool(h[k]) if hand[k] is bool else int(h[k])
	flowers = _bools(d.get("flowers", []), 8)
	winds = _bools(d.get("winds", []), 4)
	var fs: Array = d.get("flower_start", [-1, -1])
	flower_start = [int(fs[0]) if fs.size() > 0 else -1, int(fs[1]) if fs.size() > 1 else -1]
	wind_start = int(d.get("wind_start", -1))
	total_points = int(d.get("total_points", START_BALANCE))
	bet_idx = clampi(int(d.get("bet_idx", 0)), 0, BETS.size() - 1)
	free_spins = int(d.get("free_spins", 0))
	free_bet = int(d.get("free_bet", 0))
	xp = int(d.get("xp", 0))
	hand_no = int(d.get("hand_no", 0))
	spin_no = int(d.get("spin_no", 0))
	var r: Dictionary = d.get("records", {})
	records = {"small": r.get("small", {}), "big": r.get("big", {}), "fans": r.get("fans", {})}
	recent = d.get("recent", [])
	collection = d.get("collection", {})
	last_result = d.get("last_result", {})
	story_offer = d.get("story_offer", {})
	var st: Dictionary = d.get("settings", {})
	for k in settings:
		if st.has(k): settings[k] = bool(st[k])
	return true

func _bools(a: Array, n: int) -> Array:
	var out := []
	for i in n:
		out.append(bool(a[i]) if i < a.size() else false)
	return out

func save(path := "user://save.json") -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(to_dict()))

func load_save(path := "user://save.json") -> bool:
	if not FileAccess.file_exists(path): return false
	var txt := FileAccess.get_file_as_string(path)
	var d = JSON.parse_string(txt)
	if not (d is Dictionary): return false
	return from_dict(d)
