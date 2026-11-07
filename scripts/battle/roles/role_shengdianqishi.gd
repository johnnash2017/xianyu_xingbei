extends BattleRole
## 圣殿骑士（43）：神选者 / 神威 / 圣裁 / 圣愈 / 神之子 / 神临圣启 / 圣炎祈愿
##
## 【圣印】＝0 号指示物（角色表 0:圣印:2，上限 2；【神临圣启】期间允许到 4）。
## 【圣炎形态】是独立状态（不是横置本身）：进入时横置、清空自己的治疗；形态期间
## 我方士气下限为 1（F5 morale_floor）；退出时【重置】并结算形态收尾的伤害。
##
## 口径：
## 1. 【神选者】的「治疗上限 -1」在 setup 里改 cross_max（角色表本来写 3，改完 2）。
## 2. 【神威】的「无法应战」＝把本次攻击设成 NoReattack（不弹应战询问）并关掉【圣光】；
##    「本回合你与攻击目标无法获得治疗」＝双方的 no_heal_round 记成当前回合号（F4，自动过期）。
## 3. 【圣裁】的 X 由玩家在发动时选（1~当前圣印）；伤害在攻击前先结算，攻击伤害 +(X-1)。
## 4. 【神之子】在「圣印增加」时进入形态；持续到**自己的下个回合结束**（回合号 +1，回合结束时退）。
##    形态下受伤 → 本次伤害清零，改为承受 1 点来自自身的法术伤害⑥，然后退出形态。
##    同一份伤害只处理一次（在 harm 里打标记）。

const SHEN_XUAN_ZHE: int = 4301
const SHEN_WEI: int = 4302
const SHENG_CAI: int = 4303
const SHENG_YU: int = 4304
const SHEN_ZHI_ZI: int = 4305
const SHEN_LIN_SHENG_QI: int = 4306
const SHENG_YAN_QI_YUAN: int = 4307

const YIN_SLOT: int = 0
const 圣炎形态上限: int = 4

## 是否处于【圣炎形态】
var _圣炎: bool = false
## 形态持续到哪个回合结束（自己的回合号）
var _圣炎到回合: int = 0
## 本回合不能发动【神威】（【神临圣启】的代价）
var _神威禁: bool = false
## 本回合被【神威】禁止获得治疗的目标（含多次攻击叠起来的名单）
var _神威目标们: Array[int] = []
## 攻击前①的询问状态：0＝还没问，1＝正等「神威 / 圣裁」二选一的回复
var _t1_step: int = 0


func setup(p: BattlePlayer, e: BattleEngine) -> void:
	super.setup(p, e)
	# 【神选者】：你的【治疗】上限 -1
	player.cross_max = maxi(player.cross_max - 1, 0)


# ============================================================
# 技能栏
# ============================================================
func available_skills() -> Array:
	var 圣印: int = player.token_num(YIN_SLOT)
	var 队友: Array[int] = ally_ids()
	return [
		{
			"type": GConst.ActionType.MagicSkill,
			"id": SHENG_YU,
			"need_card": mini(1, player.hand_cards.size()),
			"card_max": mini(1, player.hand_cards.size()),
			"need_target": 1,
			"targets": 队友,
			"arg_choices": _圣愈选项(),
			"enabled": 圣印 >= 1 and not 队友.is_empty(),
		},
		{
			"type": GConst.ActionType.MagicSkill,
			"id": SHEN_LIN_SHENG_QI,
			"enabled": player.get_energy() >= 1,
		},
	]


func _圣愈选项() -> Array:
	var out: Array = []
	for n: int in range(1, player.token_num(YIN_SLOT) + 1):
		out.append({"text": GConst.按钮文本(SHENG_YU, 0, {"n": n}), "args": [n]})
	return out


func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	match int(action.get("action_id", 0)):
		SHENG_YU:
			if player.token_num(YIN_SLOT) < 1:
				return GConst.GE_INVALID_ACTION
			var args: Array = action.get("args", [])
			var x: int = int(args[0]) if not args.is_empty() else 0
			if x < 1 or x > player.token_num(YIN_SLOT):
				return GConst.GE_INVALID_ACTION
			var ds: Array = action.get("dst_ids", [])
			if ds.size() != 1:
				return GConst.GE_INVALID_ACTION
			var dst: BattlePlayer = engine.p(int(ds[0]))
			if dst == null or dst.color != player.color or dst.id == player.id:
				return GConst.GE_INVALID_ACTION
			return GConst.GE_SUCCESS
		SHEN_LIN_SHENG_QI:
			if player.get_energy() < 1:
				return GConst.GE_INVALID_ACTION
			return GConst.GE_SUCCESS
	return GConst.GE_INVALID_ACTION


func p_magic_skill(action: Dictionary) -> int:
	match int(action.get("action_id", 0)):
		SHENG_YU:
			return _p_圣愈(action)
		SHEN_LIN_SHENG_QI:
			return _p_神临圣启(action)
	return EMPTY_HANDLE


## 自己的回合开始：解除【神临圣启】对【神威】的禁令
func p_before_turn_begin(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) == player.id:
		_神威禁 = false
		_神威目标们.clear()
	return SUCCESS


## 自己的回合结束：神威的「无法获得治疗」只持续到圣殿骑士的回合结束，双方一起清
# ============================================================
# 4301 神选者
# ============================================================
## 主动攻击命中后②：你 +1【治疗】
func p_timeline_2_hit(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id or not bool(ctx.get("is_active", false)):
		return SUCCESS
	施加治疗(player.id, 1)
	return SUCCESS


## 你获得【治疗】并溢出时：你 +1【圣印】
func p_heal_overflow(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	_加圣印(1, YIN_SLOT, player.token_max(YIN_SLOT))
	return SUCCESS


# ============================================================
# 4302 神威 / 4303 圣裁：主动攻击前①
# ============================================================
func p_timeline_1(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id or not bool(ctx.get("is_active", false)):
		return SUCCESS
	# 圣裁收尾会 push_harm 并返回 URGENT：引擎跑完那段伤害会重新进入本钩子，
	# 用本次攻击自己的 ctx 记「已结算」，避免神威 / 圣裁在同一次攻击里被再问一遍
	if bool(ctx.get("圣殿骑士_攻击前已结算", false)):
		return SUCCESS
	# 0 ＝还没问，1 ＝正等「神威 / 圣裁」二选一的回复。
	# 第一段二选一里圣裁的 X 由客户端本地展开，服务端只收一次最终 args
	# （args=[1] 神威 / args=[2, X] 圣裁）。
	if _t1_step == 0:
		if player.token_num(YIN_SLOT) < 1:
			return SUCCESS
		_t1_step = 1
	if not engine.has_reply():
		var 攻目标: int = int(ctx.get("dst", -1))
		var 原伤害: int = int((ctx.get("harm", {}) as Dictionary).get("point", 0))
		var 攻击卡: GCard = Data.get_card(int(ctx.get("card_id", -1)))
		var 神威加伤: int = 1 if 攻击卡 != null \
			and 攻击卡.fate_pattern_enum() == GConst.FatePattern.Holy else 0
		var 预览目标: Array = [攻目标] if 攻目标 >= 0 else []
		var 选项: Array = _神威圣裁选项()
		# 主询问始终挂在【神威】名下：圣裁只有 1 圣印时也走同一套「第一段二选一 →
		# 本地展开圣裁 X」的界面，不再因为主技能换成 4303 而走另一条流程。
		# 选项本身就是技能：no_parent=true 不再多摆一颗「本体技能」。
		engine.ask_skill(player.id, SHEN_WEI, 0, 0, GConst.CardSource.Hand, 选项, 0, "", [], true,
			"", [], 原伤害, GConst.HarmType.Attack, false, 预览目标, true,
			原伤害 + 神威加伤 if 原伤害 > 0 and _可神威() else -1,
			0, false, -1, true, "", 预览目标, [], 0)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	var 选: int = int(args[0]) if not args.is_empty() else 0
	_t1_step = 0
	if 选 == 1 and _可神威() and player.remove_token(YIN_SLOT, 2):
		_应用神威(ctx)
		return SUCCESS
	if 选 == 2 and args.size() >= 2:
		var x: int = int(args[1])
		if x > 0 and x <= player.token_num(YIN_SLOT) and player.remove_token(YIN_SLOT, x):
			return _应用圣裁(ctx, x)
	return SUCCESS


func _可神威() -> bool:
	return not _神威禁 and player.token_num(YIN_SLOT) >= 2


## 第一段二选一：两个响应都摆出来，资源不够的一项置灰
func _神威圣裁选项() -> Array:
	return [
		{
			"value": 1,
			"label": GConst.skill_desc_name(SHEN_WEI),
			"args": [1],
			"skill_id": SHEN_WEI,
			"enabled": _可神威(),
		},
		{
			"value": 2,
			"label": GConst.skill_desc_name(SHENG_CAI),
			"args": [2],
			"skill_id": SHENG_CAI,
			"enabled": player.token_num(YIN_SLOT) >= 1,
		},
	]


## 应用【圣裁】（已由调用方扣圣印）：1 点法术伤害 + 攻击伤害 +(X-1)
func _应用圣裁(ctx: Dictionary, x: int) -> int:
	notice_skill(SHENG_CAI, [int(ctx.get("dst", -1))])
	var harm2: Dictionary = ctx.get("harm", {})
	if not harm2.is_empty():
		harm2["point"] = int(harm2.get("point", 0)) + (x - 1)
	engine._broadcast_game()
	engine.push_harm({
		"src": player.id, "dst": int(ctx.get("dst", -1)),
		"point": 1, "cause": SHENG_CAI, "type": GConst.HarmType.Magic,
	})
	ctx["圣殿骑士_攻击前已结算"] = true
	return URGENT


## 应用【神威】（已由调用方扣圣印）：无法应战、圣类 +1、双方禁疗并逐人播报
func _应用神威(ctx: Dictionary) -> void:
	notice_skill(SHEN_WEI, [int(ctx.get("dst", -1))])
	ctx["hit_rate"] = GConst.HitRate.NoReattack
	ctx["can_light"] = false
	var 卡: GCard = Data.get_card(int(ctx.get("card_id", -1)))
	var harm: Dictionary = ctx.get("harm", {})
	if 卡 != null and 卡.fate_pattern_enum() == GConst.FatePattern.Holy and not harm.is_empty():
		harm["point"] = int(harm.get("point", 0)) + 1
	var 新禁疗: Array[int] = []
	if not player.无法获得治疗():
		新禁疗.append(player.id)
	var dst: BattlePlayer = engine.p(int(ctx.get("dst", -1)))
	if dst != null and not dst.无法获得治疗():
		新禁疗.append(dst.id)
	player.no_heal_round = engine.round_id
	if dst != null:
		dst.no_heal_round = engine.round_id
		if not _神威目标们.has(dst.id):
			_神威目标们.append(dst.id)
	for pid: int in 新禁疗:
		var p0: BattlePlayer = engine.p(pid)
		if p0 != null:
			engine.broadcast(GConst.Msg.Gossip, {
				"type": GConst.GossipType.Heal,
				"txt": "%s 无法获得治疗" % engine._称号(p0),
				"id": pid,
				"num": 0,
			})
	engine._broadcast_game()


# ============================================================
# 4304 圣愈：移除 X 圣印 → 目标队友 +X 治疗，你弃 1 张牌，额外 +1【攻击行动】
# ============================================================
func _p_圣愈(action: Dictionary) -> int:
	var 校验: int = v_magic_skill(action)
	if 校验 != GConst.GE_SUCCESS:
		return 校验
	var dst: int = int((action.get("dst_ids", []) as Array)[0])
	var args: Array = action.get("args", [])
	var x: int = int(args[0])
	notice_skill(SHENG_YU, [dst])
	if not player.remove_token(YIN_SLOT, x):
		return GConst.GE_INVALID_ACTION
	# 顺序：目标先加治疗 → 自己弃 1 张牌 → 获得额外攻击行动
	var 目标: BattlePlayer = engine.p(dst)
	if 目标 != null:
		施加治疗(目标.id, x)
	var 需弃: int = mini(1, player.hand_cards.size())
	var cards: Array = action.get("card_ids", [])
	if 需弃 > 0 and (cards.is_empty() or not player.有手牌(int(cards[0]))):
		if not player.hand_cards.is_empty():
			cards = [player.hand_cards[0]]
	if not cards.is_empty() and player.有手牌(int(cards[0])):
		var cid: int = int(cards[0])
		engine.take_from_hand(player.id, [cid], false)
		engine.to_discard([cid], {"owner": player.id, "source": "hand", "cause": SHENG_YU})
		engine._log_discard(player.id, [cid], false)
	player.add_action(GConst.ActionType.Attack, SHENG_YU, true, true)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 4306 神临圣启：无视圣印上限 +2 圣印（最高 4），额外 +1 攻击行动；本回合不能发动【神威】
# ============================================================
func _p_神临圣启(_action: Dictionary) -> int:
	if player.get_energy() < 1:
		return GConst.GE_INVALID_ACTION
	player.remove_energy(1)
	notice_skill(SHEN_LIN_SHENG_QI, [player.id])
	_加圣印(2, YIN_SLOT, 圣炎形态上限)
	_神威禁 = true
	player.add_action(GConst.ActionType.Attack, SHEN_LIN_SHENG_QI, true, true)
	engine._broadcast_game()
	return URGENT


# ============================================================
# 4305 神之子：圣印增加时进入【圣炎形态】
# ============================================================
func _进入圣炎() -> void:
	player.tap = true
	player.cross_num = 0
	_圣炎 = true
	_圣炎到回合 = engine.round_id + 1
	notice_skill(SHEN_ZHI_ZI, [player.id])
	engine._broadcast_game()


## 形态期间：我方士气最少为 1（F5）
func morale_floor() -> int:
	return 1 if _圣炎 else 0


## 形态下受到伤害③：抵御本次伤害，改为承受 1 点来自自身的法术伤害⑥，然后退出形态
func p_timeline_3(ctx: Dictionary) -> int:
	if not _圣炎:
		return SUCCESS
	var harm: Dictionary = ctx.get("harm", {})
	if harm.is_empty() or int(harm.get("dst", -1)) != player.id:
		return SUCCESS
	# 已经被其他效果减到 0 的伤害不算“受到伤害”，不触发圣炎抵御/退出
	if int(harm.get("point", 0)) <= 0:
		return SUCCESS
	if bool(harm.get("圣炎已抵御", false)):
		return SUCCESS
	harm["圣炎已抵御"] = true
	harm["point"] = 0
	notice_skill(SHEN_ZHI_ZI, [player.id])
	# 先记形态退出并压「圣炎祈愿」钩子，再把 1 点自伤压到它上面：
	# 栈是后进先出，自伤先结算，之后才询问祈愿。
	_退出圣炎(false)
	engine.push_harm({
		"src": player.id, "dst": player.id, "point": 1,
		"cause": SHEN_ZHI_ZI, "type": GConst.HarmType.Magic,
	})
	return URGENT


## 退出形态：重置 + 清标记；收尾伤害 / 圣炎祈愿 由 _圣炎收尾 结算
func _退出圣炎(收尾: bool) -> void:
	if not _圣炎:
		return
	_圣炎 = false
	_圣炎到回合 = 0
	if 收尾:
		_圣炎收尾 = 1
	else:
		# 受伤脱离：不再对对手造成 1 点收尾伤害，但仍触发【圣炎祈愿】
		_圣炎收尾 = 2
	engine.push(BattleEngine.SHook.new("p_sheng_dian_ask", {"player": player.id}, []))
	# 先压「圣炎收尾 / 祈愿」钩子，再重置形态：tap=false 会压 p_tap，
	# 后进先出保证先完成【重置】相关钩子，再结算收尾 / 祈愿。
	player.tap = false
	engine._broadcast_game()

var _圣炎收尾: int = 0


## 自己的下个回合结束时退出形态并结算收尾
func p_turn_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	# 神威的禁止治疗只到圣殿骑士自己的回合结束，双方一起清
	var 清过: bool = engine.清除神威禁疗(player.id)
	for pid: int in _神威目标们:
		if engine.清除神威禁疗(pid):
			清过 = true
	_神威目标们.clear()
	if 清过:
		engine._broadcast_game()
	if not _圣炎:
		return SUCCESS
	if engine.round_id < _圣炎到回合:
		return SUCCESS
	_退出圣炎(true)
	return URGENT


# ============================================================
# 统一的「小段询问」钩子：圣炎收尾 / 圣炎祈愿
# ============================================================
func p_sheng_dian_ask(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	# 圣炎收尾：对目标对手 1 点法术伤害
	if _圣炎收尾 == 1:
		if not engine.has_reply():
			询问(player.id, SHEN_ZHI_ZI, 0, 1, GConst.CardSource.Hand, [], 0, "", [], false,
				0, -1, enemy_ids(), -1, {}, 1, GConst.HarmType.Magic, false, [], true, -1, 0,
				GConst.提示原文(SHEN_ZHI_ZI, 1))
			return WAIT
		var r3: Dictionary = take_skill_reply_full()
		var ds: Array = r3.get("dst_ids", [])
		_圣炎收尾 = 3
		if ds.size() == 1:
			engine.push_harm({
				"src": player.id, "dst": int(ds[0]), "point": 1,
				"cause": SHEN_ZHI_ZI, "type": GConst.HarmType.Magic,
			})
		# 即使没有合法目标 / 超时没选到人，也不能把后续的圣炎祈愿一起吞掉
		engine.push(BattleEngine.SHook.new("p_sheng_dian_ask", {"player": player.id}, []))
		return URGENT
	# 圣炎祈愿：退出形态时目标角色 +2 治疗（消耗 1 点能量）。
	# 选目标本身就是「发动」：不再先问一次是否发动再问目标，取消即不发动。
	if _圣炎收尾 == 2:
		_圣炎收尾 = 3
	if _圣炎收尾 == 3:
		if player.get_energy() < 1:
			_圣炎收尾 = 0
			return SUCCESS
		if not engine.has_reply():
			询问(player.id, SHENG_YAN_QI_YUAN, 0, 1, GConst.CardSource.Hand, [], 0, "", [], true,
				0, -1, _全体角色(), -1, {}, 2, GConst.预览类型_治疗, false, [], true, -1, 0,
				"")
			return WAIT
		var r3: Dictionary = take_skill_reply_full()
		var ds3: Array = r3.get("dst_ids", [])
		_圣炎收尾 = 0
		if ds3.size() == 1:
			player.remove_energy(1)
			notice_skill(SHENG_YAN_QI_YUAN, [int(ds3[0])])
			施加治疗(int(ds3[0]), 2)
		return SUCCESS
	return SUCCESS



# ============================================================
# 小工具
# ============================================================
## 加【圣印】并处理【神之子】的进入时机；cap 由调用方给（普通 2，神临圣启 4）
func _加圣印(n: int, slot: int, cap: int) -> void:
	if n <= 0:
		return
	var 定义: Dictionary = player.token_def(slot)
	if 定义.is_empty():
		return
	var 前: int = int(定义.get("num", 0))
	var 新: int = mini(前 + n, maxi(cap, 前))
	if 新 <= 前:
		return
	定义["num"] = 新
	if not _圣炎:
		_进入圣炎()
	engine._broadcast_game()


func _全体角色() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		if engine.p(pid) != null:
			out.append(pid)
	return out
