extends BattleRole
## 红莲骑士（roleID 28）—— 移植自服务端 role/HongLian.cpp
## 形态：tap（血印形态）+ 血印指示物（上限 2）；cross_max = 4
## 技能：腥红圣约（2801，攻击技能：治疗未满且本回合未用 → 选牌攻击时 +1 治疗）、
##       腥红信仰（2802，被动：被他人伤害且可治疗时，放弃治疗结算）、
##       血腥祷言（2803，启动：把治疗转移给其他角色，转移一次 +1 血印，自身承受等量法术伤害）、
##       杀戮盛宴（2806，主动攻击命中后可选：耗 1 血印，伤害 +2，自身受 4 点法术伤害）、
##       热血沸腾（2807，被动：血印形态下不损失士气；未横置时受伤进入血印形态；回合结束解除并 +2 治疗）、
##       戒骄戒躁（2808，额外行动：血印形态且能量≥1 时追加一次攻击/法术行动）、
##       腥红十字（2809，法术技能：弃 2 张法术牌 + 1 能量 + 1 血印，目标 3 点、自身 4 点法术伤害）

const XING_HONG_SHENG_YUE: int = 2801
const XING_HONG_XIN_YANG: int = 2802
const XUE_XING_DAO_YAN: int = 2803
const SHA_LU_SHENG_YAN: int = 2806
const RE_XUE_FEI_TENG: int = 2807
const JIE_JIAO_JIE_ZAO: int = 2808
const XING_HONG_SHI_ZI: int = 2809

var used_xing_hong_sheng_yue: bool = false

## 本次主动攻击预选的「攻击技能」号（0＝普通攻击）：由 p_attack_skill 在发起攻击前写入，
## p_timeline_1 据此结算腥红圣约，用完即清
var _预选攻击技能: int = 0

## 【腥红圣约（普通出牌攻击询问）】的推进阶段：0＝还没开始 / T1_ASK＝在问是否发动，收尾清回 0。
## 用自有变量推进而不是引擎 step：钩子轮次开始会把 step 清零，而这条流程要跨一次询问。
var _timeline_1_step: int = 0
const T1_ASK: int = 1


func setup(p: BattlePlayer, e: BattleEngine) -> void:
	super.setup(p, e)
	p.cross_max = 4
	p.tokens[0] = {"name": "血印", "max": 2, "num": 0}


func available_skills() -> Array:
	var out: Array = []
	if player.get_energy() >= 1 and int(player.tokens[0]["num"]) >= 1 and _magic_card_count() >= 2:
		out.append({"type": GConst.ActionType.MagicSkill, "id": XING_HONG_SHI_ZI, "need_card": 2, "need_target": 1,
			"cards": magic_hand_ids()})
	# 【血腥祷言】为「启动」：有治疗时可发动，把自身治疗分给队友（不消耗本回合行动）
	if player.cross_num > 0:
		out.append({"type": GConst.ActionType.SpecialSkill, "id": XUE_XING_DAO_YAN,
			"need_card": 0, "need_target": 1, "targets": ally_ids()})
	# 【腥红圣约】不再提供技能栏按钮：它只能在主动攻击宣告时响应发动
	return out


## 手牌中法术牌数量
func _magic_card_count() -> int:
	var n: int = 0
	for cid: int in player.hand_cards:
		var c: GCard = Data.get_card(cid)
		if c != null and c.is_magic():
			n += 1
	return n


func p_before_turn_begin(_ctx: Dictionary) -> int:
	used_xing_hong_sheng_yue = false
	return SUCCESS


# ============================================================
# 启动：血腥祷言（技能栏按钮，有治疗时可发动）
# 交互走「技能指示器」（const.gd 里 技能_血腥祷言）：客户端点头像把自身治疗分给队友，
# 回包的 dst_ids / args 平行 —— args[i] 就是第 i 名队友分到的治疗点数。
# ============================================================
func is_free_skill(skill_id: int) -> bool:
	return skill_id == XUE_XING_DAO_YAN


func v_special_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != XUE_XING_DAO_YAN:
		return GConst.GE_INVALID_ACTION
	if player.cross_num <= 0:
		return GConst.GE_INVALID_ACTION
	var dsts: Array = action.get("dst_ids", [])
	var args: Array = action.get("args", [])
	if dsts.is_empty() or args.is_empty():
		return GConst.GE_INVALID_ARGUMENT
	for i: int in range(dsts.size()):
		var dp: BattlePlayer = engine.p(int(dsts[i]))
		if dp == null:
			return GConst.GE_INVALID_PLAYERID
		# 只能分给队友（不含自己）
		if dp.color != player.color or dp.id == player.id:
			return GConst.GE_INVALID_ACTION
	var total: int = _分配点数(dsts, args)
	if total <= 0 or player.cross_num < total:
		return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


## 血腥祷言：移除自身 total 点治疗，分给各队友，自身受 total 点法术伤害并 +1【血印】
func p_special_skill(action: Dictionary) -> int:
	var dsts: Array = action.get("dst_ids", [])
	var args: Array = action.get("args", [])
	var total: int = _分配点数(dsts, args)
	notice_skill(XUE_XING_DAO_YAN, dsts)
	player.boot_skill_used = true
	player.sub_cross_num(total)
	for i: int in range(dsts.size()):
		施加治疗(int(dsts[i]), int(args[i]) if i < args.size() else 0)
	if int(player.tokens[0]["num"]) < 2:
		player.tokens[0]["num"] = int(player.tokens[0]["num"]) + 1
	engine.push_harm({
		"src": player.id, "dst": player.id, "point": total,
		"cause": XUE_XING_DAO_YAN, "type": GConst.HarmType.Magic,
	})
	engine._broadcast_game()
	return URGENT


## 各目标分到的点数之和（dst_ids 与 args 平行）
func _分配点数(dsts: Array, args: Array) -> int:
	var total: int = 0
	for i: int in range(dsts.size()):
		total += int(args[i]) if i < args.size() else 0
	return total


# ============================================================
# 攻击技能（技能栏）：腥红圣约（选一张攻击牌 + 一名对手发起攻击，攻击前 +1 治疗）
# ============================================================
func v_attack_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != XING_HONG_SHENG_YUE:
		return GConst.GE_INVALID_ACTION
	# 回合限定：治疗未达上限且本回合未发动过
	if used_xing_hong_sheng_yue or player.cross_num >= player.cross_max:
		return GConst.GE_INVALID_ACTION
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	if cards.is_empty() or dsts.is_empty():
		return GConst.GE_INVALID_ARGUMENT
	var cid: int = int(cards[0])
	var dst_id: int = int(dsts[0])
	# 复用通用主动攻击校验（持有该攻击牌、目标不同队、面前【挑衅】限制等）
	if player.v_attack(cid, dst_id, engine.players) != GConst.GE_SUCCESS:
		return GConst.GE_INVALID_ACTION
	var dst: BattlePlayer = engine.p(dst_id)
	if dst == null or dst.v_attacked() != GConst.GE_SUCCESS:
		return GConst.GE_INVALID_PLAYERID
	return GConst.GE_SUCCESS


## 腥红圣约：打出所选攻击牌发起一次主动攻击。
## 攻击宣告后 p_timeline_1 会依据 _预选攻击技能 直接结算 +1 治疗（不再弹窗询问）
func p_attack_skill(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	var cid: int = int(cards[0])
	var dst_id: int = int(dsts[0])
	_预选攻击技能 = XING_HONG_SHENG_YUE
	var harm: Dictionary = {
		"src": player.id, "dst": dst_id, "point": BattleEngine.ATTACK_BASE_POINT, "cause": GConst.CAUSE_ATTACK,
		"type": GConst.HarmType.Attack, "card_id": cid, "is_active": true,
	}
	engine.push(BattleEngine.SAttackCard.new(player.id, dst_id, cid, harm))
	engine.take_from_hand(player.id, [cid], true)
	engine.to_discard([cid])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Use, "src_id": player.id, "dst_id": dst_id, "card_ids": [cid], "is_real": true,
	})
	return URGENT


# ============================================================
# 攻击宣告后：腥红圣约（治疗未满上限且本回合未发动时 +1 治疗）
# 两条路径：
#   · 技能栏按钮（_预选攻击技能 == 2801）：直接结算，不再弹窗询问；
#   · 普通出牌攻击（_预选攻击技能 == 0）：恢复原版弹窗询问。
# ============================================================
func p_timeline_1(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	if _timeline_1_step == 0:
		var 预选: int = _预选攻击技能
		_预选攻击技能 = 0
		if 预选 == XING_HONG_SHENG_YUE:
			# 技能栏按钮：直接结算（不再弹窗询问）
			_发动腥红圣约(ctx)
			return SUCCESS
		# 普通出牌攻击：恢复原版前提前置条件（治疗未满上限且本回合未发动），满足才问
		if player.cross_num >= player.cross_max or used_xing_hong_sheng_yue:
			return SUCCESS
		_timeline_1_step = T1_ASK
	if _timeline_1_step == T1_ASK:
		if not engine.has_reply():
			询问(player.id, XING_HONG_SHENG_YUE, 0, 0)
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		_timeline_1_step = 0
		var args: Array = r.get("args", [])
		if args.is_empty() or int(args[0]) != 1:
			return SUCCESS
		_发动腥红圣约(ctx)
	return SUCCESS


## 腥红圣约：治疗未满上限且本回合未发动时，+1 治疗并把本回合标记为已发动
func _发动腥红圣约(ctx: Dictionary) -> void:
	if player.cross_num >= player.cross_max or used_xing_hong_sheng_yue:
		return
	notice_skill(XING_HONG_SHENG_YUE, [int(ctx.get("dst", -1))])
	施加治疗(player.id, 1)
	used_xing_hong_sheng_yue = true
	engine._broadcast_game()


# ============================================================
# 主动攻击命中后：杀戮盛宴（耗 1 血印，伤害 +2，自身受 4 点法术伤害）
# ============================================================
func p_timeline_2_hit(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("src", -1)) != player.id:
		return SUCCESS
	if not bool(ctx.get("is_active", false)) or int(player.tokens[0]["num"]) == 0:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if not engine.has_reply():
		# 目标与「这次攻击原本的伤害」一并下发：客户端在敌人头像上现算「原伤害 + 2」，
		# 并在自己头像上写自身要吃的 4 点法术伤害
		var dst: int = int(harm.get("dst", -1))
		# 座位号从 0 起：0 号也是合法对手，判「没取到」只能用 < 0
		询问(player.id, SHA_LU_SHENG_YAN, 0, 0, GConst.CardSource.Hand, [], 0, "", [], true,
			0, -1, [dst] if dst >= 0 else [], -1, {}, int(harm.get("point", 0)))
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		return SUCCESS
	notice_skill(SHA_LU_SHENG_YAN, [int(harm.get("dst", -1))])
	harm["point"] = int(harm.get("point", 0)) + 2
	player.tokens[0]["num"] = int(player.tokens[0]["num"]) - 1
	engine.push_harm({
		"src": player.id, "dst": player.id, "point": 4,
		"cause": SHA_LU_SHENG_YAN, "type": GConst.HarmType.Magic,
	})
	engine._broadcast_game()
	return URGENT


# ============================================================
# 腥红信仰：被他人伤害时关闭本次治疗结算（服务端 XingHongXinYang：crossAvailable = 0）
# ============================================================
func p_timeline_4(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("dst", -1)) != player.id:
		return SUCCESS
	if int(harm.get("src", -1)) == player.id:
		return SUCCESS
	if int(harm.get("cross_available", 1)) == 0:
		return SUCCESS
	harm["cross_available"] = 0
	notice_skill(XING_HONG_XIN_YANG, [player.id])
	return SUCCESS


# ============================================================
# 攻击/法术行动结束后：戒骄戒躁（血印形态 + 能量≥1 时追加一次攻击/法术行动）
# ============================================================
func p_after_attack(ctx: Dictionary) -> int:
	return _jie_jiao_jie_zao(int(ctx.get("player", -1)))


func p_after_magic(ctx: Dictionary) -> int:
	return _jie_jiao_jie_zao(int(ctx.get("player", ctx.get("src", -1))))


## 授予额外行动（服务端 JieJiaoJieZao 仅 addAction，代价改在玩家选择时结算）
func _jie_jiao_jie_zao(pid: int) -> int:
	if pid != player.id or not player.tap or player.get_energy() < 1:
		return SUCCESS
	player.add_action(GConst.ActionType.AttackMagic, JIE_JIAO_JIE_ZAO)
	return SUCCESS


# ============================================================
# 玩家选择额外行动时：戒骄戒躁扣 1 能量（优先水晶）并解除血印形态
# （引擎已在选中时广播该额外行动的技能宣告，此处不再重复）
# ============================================================
func p_additional_action(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id or int(ctx.get("cause", 0)) != JIE_JIAO_JIE_ZAO:
		return SUCCESS
	if player.crystal > 0:
		player.set_crystal(player.crystal - 1)
	else:
		player.set_gem(player.gem - 1)
	player.tap = false
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 热血沸腾：血印形态下不受士气损失；未横置时因伤害掉士气则进入血印形态；
# 回合结束解除并 +2 治疗（服务端要求 harm.type != HARM_NONE）
# ============================================================
func p_before_lose_morale(ctx: Dictionary) -> int:
	if int(ctx.get("dst", -1)) != player.id:
		return SUCCESS
	if not player.tap or int(ctx.get("amount", 0)) <= 0:
		return SUCCESS
	if int(ctx.get("type", 0)) == GConst.HarmType.None:
		return SUCCESS
	ctx["amount"] = 0
	return SUCCESS


func p_true_lose_morale(ctx: Dictionary) -> int:
	if int(ctx.get("dst", -1)) != player.id or player.tap:
		return SUCCESS
	if int(ctx.get("amount", 0)) <= 0:
		return SUCCESS
	if int(ctx.get("type", 0)) == GConst.HarmType.None:
		return SUCCESS
	notice_skill(RE_XUE_FEI_TENG, [player.id])
	player.tap = true
	engine._broadcast_game()
	return SUCCESS


func p_turn_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id or not player.tap:
		return SUCCESS
	player.tap = false
	施加治疗(player.id, 2)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 主动法术技能：腥红十字
# ============================================================
func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != XING_HONG_SHI_ZI:
		return GConst.GE_INVALID_ACTION
	var cards: Array = action.get("card_ids", [])
	if cards.size() != 2 or player.get_energy() < 1 or int(player.tokens[0]["num"]) == 0:
		return GConst.GE_INVALID_ACTION
	for c: Variant in cards:
		var cid: int = int(c)
		var card: GCard = Data.get_card(cid)
		if card == null or not card.is_magic() or not player.has_hand_card(cid):
			return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != XING_HONG_SHI_ZI:
		return GConst.GE_INVALID_ACTION
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	var dst_id: int = int(dsts[0]) if not dsts.is_empty() else player.id
	notice_skill(XING_HONG_SHI_ZI, [dst_id])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": cards, "is_real": true,
	})
	if player.crystal > 0:
		player.set_crystal(player.crystal - 1)
	else:
		player.set_gem(player.gem - 1)
	player.tokens[0]["num"] = int(player.tokens[0]["num"]) - 1
	engine.push_harm({
		"src": player.id, "dst": dst_id, "point": 3,
		"cause": XING_HONG_SHI_ZI, "type": GConst.HarmType.Magic,
	})
	engine.push_harm({
		"src": player.id, "dst": player.id, "point": 4,
		"cause": XING_HONG_SHI_ZI, "type": GConst.HarmType.Magic,
	})
	engine.take_from_hand(player.id, cards, true)
	engine.to_discard(cards)
	# 牌已在上面展示过：只写日志、不播弃牌特效
	engine._log_discard(player.id, cards, false)
	engine._broadcast_game()
	return URGENT
