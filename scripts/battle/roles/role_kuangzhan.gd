extends BattleRole
## 狂战士（roleID 2）—— 移植自服务端 role/KuangZhan.cpp
## 技能：狂化（被动，攻击伤害+1）、血影狂刀（攻击时可选）、血腥咆哮（攻击时可选，强制命中）、撕裂（命中后消耗宝石+2 伤害）

const XUE_YING_KUANG_DAO: int = 201
const XUE_XING_PAO_XIAO: int = 202
const KUANG_HUA: int = 203
const SI_LIE: int = 205


## 行动阶段可发动的技能：【血影狂刀 / 血腥咆哮】是「主动攻击前」的响应技能，
## 改成技能栏按钮：选一张带对应特技的攻击牌 + 一名符合条件的对手，直接发起这次主动攻击，
## 攻击宣告后由 p_timeline_1 直接结算（不再弹窗询问）
func available_skills() -> Array:
	var out: Array = []
	# 血影狂刀（201）：目标手牌数为 2 或 3 时才能发动（本次伤害 +2 / +1）
	var 血影刀: Array[int] = hand_ids_where(func(_cid: int, c: GCard) -> bool: return c.is_attack() and c.has_skill_id(XUE_YING_KUANG_DAO))
	if not 血影刀.is_empty():
		var 刀目标: Array[int] = _enemy_ids_where(func(d: BattlePlayer) -> bool: return d.hand_cards.size() >= 2 and d.hand_cards.size() <= 3)
		if not 刀目标.is_empty():
			out.append({"type": GConst.ActionType.AttackSkill, "id": XUE_YING_KUANG_DAO, "need_card": 1, "need_target": 1,
				"cards": 血影刀, "targets": 刀目标})
	# 血腥咆哮（202）：目标【治疗】恰好为 2 时才能发动（本次攻击强制命中）
	var 咆哮: Array[int] = hand_ids_where(func(_cid: int, c: GCard) -> bool: return c.is_attack() and c.has_skill_id(XUE_XING_PAO_XIAO))
	if not 咆哮.is_empty():
		var 咆哮目标: Array[int] = _enemy_ids_where(func(d: BattlePlayer) -> bool: return d.cross_num == 2)
		if not 咆哮目标.is_empty():
			out.append({"type": GConst.ActionType.AttackSkill, "id": XUE_XING_PAO_XIAO, "need_card": 1, "need_target": 1,
				"cards": 咆哮, "targets": 咆哮目标})
	return out


## 场上满足条件的对手 id（available_skills 的 "targets" 用它；条件必须与 v_attack_skill 里的目标校验完全一致）
func _enemy_ids_where(条件: Callable) -> Array[int]:
	var out: Array[int] = []
	for pid: int in enemy_ids():
		var d: BattlePlayer = engine.p(pid)
		if bool(条件.call(d)):
			out.append(pid)
	return out


## 【血影狂刀 / 血腥咆哮】的推进阶段（0＝还没开始 / XUE_YING_KUANG_DAO＝处理血影狂刀 / XUE_XING_PAO_XIAO＝处理血腥咆哮）。
## 支持两种用法：技能栏按钮在发起攻击前预选（预选命中→直接结算，不再询问）；
## 普通出牌攻击（预选为 0）→ 按原版顺序弹窗询问是否发动。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零。
## 每次自己主动宣告攻击（p_timeline_1）触发一次，收尾清回 0（留 STEP_DONE 会让下一次触发不再发动）
var _timeline_1_step: int = 0

## 本次主动攻击预选的响应技能号（0＝普通出牌攻击）：由 p_attack_skill 在发起攻击前写入，
## p_timeline_1 据此直接结算血影狂刀 / 血腥咆哮，用完即清
var _预选攻击技能: int = 0


func p_timeline_1(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	if _timeline_1_step >= STEP_DONE:
		return SUCCESS
	# 本次主动攻击预选的响应技能号：只在本次宣告后处理一次，读完即清
	# （普通出牌攻击 _预选攻击技能 为 0，走原版询问流程；应战反击 is_active 为假，函数内直接跳过）
	var 预选: int = _预选攻击技能
	_预选攻击技能 = 0
	if _timeline_1_step == 0:
		_timeline_1_step = XUE_YING_KUANG_DAO
	if _timeline_1_step == XUE_YING_KUANG_DAO:
		# 预选命中血影狂刀→技能栏按钮直接结算；普通出牌攻击（预选 0）→原版弹窗询问
		if 预选 == 0 or 预选 == XUE_YING_KUANG_DAO:
			var r: int = _xue_ying_kuang_dao(ctx, 预选 == 0)
			if r == WAIT:
				return WAIT
		_timeline_1_step = XUE_XING_PAO_XIAO
	if _timeline_1_step == XUE_XING_PAO_XIAO:
		# 预选命中血腥咆哮→技能栏按钮直接结算；普通出牌攻击（预选 0）→原版弹窗询问
		if 预选 == 0 or 预选 == XUE_XING_PAO_XIAO:
			var r2: int = _xue_xing_pao_xiao(ctx, 预选 == 0)
			if r2 == WAIT:
				return WAIT
		_timeline_1_step = 0
	return SUCCESS


# ============================================================
# 攻击技能（技能栏按钮）：血影狂刀 / 血腥咆哮
# 选一张带对应特技的攻击牌 + 一名符合条件的对手，直接完成一次带效果的主动攻击
# ============================================================
func v_attack_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	var aid: int = int(action.get("action_id", 0))
	if aid != XUE_YING_KUANG_DAO and aid != XUE_XING_PAO_XIAO:
		return GConst.GE_INVALID_ACTION
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	if cards.is_empty() or dsts.is_empty():
		return GConst.GE_INVALID_ARGUMENT
	var cid: int = int(cards[0])
	# 选中的必须是带对应特技的攻击牌（与 available_skills 的 "cards" 同一条）
	var card: GCard = Data.get_card(cid)
	if card == null or not card.is_attack() or not card.has_skill_id(aid):
		return GConst.GE_INVALID_CARDID
	var dst_id: int = int(dsts[0])
	# 复用通用主动攻击校验（持有该攻击牌、目标不同队、面前【挑衅】限制等）
	if player.v_attack(cid, dst_id, engine.players) != GConst.GE_SUCCESS:
		return GConst.GE_INVALID_ACTION
	var dst: BattlePlayer = engine.p(dst_id)
	if dst == null or dst.v_attacked() != GConst.GE_SUCCESS:
		return GConst.GE_INVALID_PLAYERID
	# 各技能的目标条件（与 available_skills 的 "targets" 一致）：
	# 血影狂刀要求目标手牌 2~3 张；血腥咆哮要求目标【治疗】恰好为 2
	if aid == XUE_YING_KUANG_DAO:
		if dst.hand_cards.size() < 2 or dst.hand_cards.size() > 3:
			return GConst.GE_INVALID_PLAYERID
	elif dst.cross_num != 2:
		return GConst.GE_INVALID_PLAYERID
	return GConst.GE_SUCCESS


## 【血影狂刀 / 血腥咆哮】：打出所选攻击牌发起一次主动攻击。
## 攻击宣告后 p_timeline_1 会依据 _预选攻击技能 直接结算对应效果（不再弹窗询问）
func p_attack_skill(action: Dictionary) -> int:
	var aid: int = int(action.get("action_id", 0))
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	var cid: int = int(cards[0])
	var dst_id: int = int(dsts[0])
	_预选攻击技能 = aid
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


## 【狂化 / 撕裂】的推进阶段（0＝还没开始 / KUANG_HUA＝结算狂化 / SI_LIE＝在问撕裂）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨一次询问，
## 中途一旦被别的钩子轮次（改手牌 / 盖牌 / 基础效果 / 横置…）插进来，step 就被抹掉、流程退回第 0 步。
## 每次自己主动攻击命中（p_timeline_2_hit）触发一次，收尾清回 0（留 STEP_DONE 会让下一次触发不再发动）
var _timeline_2_hit_step: int = 0


func p_timeline_2_hit(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("src", -1)) != player.id:
		return SUCCESS
	if harm.get("type", GConst.HarmType.Attack) != GConst.HarmType.Attack:
		return SUCCESS
	if _timeline_2_hit_step >= STEP_DONE:
		return SUCCESS
	if _timeline_2_hit_step == 0:
		_timeline_2_hit_step = KUANG_HUA
	if _timeline_2_hit_step == KUANG_HUA:
		var r: int = _kuang_hua(harm)
		if r == WAIT:
			return WAIT
		_timeline_2_hit_step = SI_LIE
	if _timeline_2_hit_step == SI_LIE:
		var r2: int = _si_lie(harm)
		if r2 == WAIT:
			return WAIT
		_timeline_2_hit_step = 0
	return SUCCESS


# ============================================================
# 具体技能
# ============================================================
## 【血影狂刀】本次攻击伤害 +2（目标手牌 2 张）或 +1（目标手牌 3 张）。
## 是否询问：普通出牌攻击（true）按原版弹窗询问是否发动；技能栏按钮预选（false）直接结算
func _xue_ying_kuang_dao(ctx: Dictionary, 是否询问: bool) -> int:
	var card: GCard = Data.get_card(int(ctx.get("card_id", -1)))
	if card == null or not card.has_skill_id(XUE_YING_KUANG_DAO) or not bool(ctx.get("is_active", false)):
		return SUCCESS
	var dst: BattlePlayer = engine.p(int(ctx.get("dst", -1)))
	if dst == null:
		return SUCCESS
	var n: int = dst.hand_cards.size()
	if n < 2 or n > 3:
		return SUCCESS
	if 是否询问:
		if not engine.has_reply():
			# 目标与发动前的伤害一并下发：客户端据此在目标头像上现算「本次攻击伤害」
			询问(player.id, XUE_YING_KUANG_DAO, 0, 0, GConst.CardSource.Hand, [], 0, "", [], true,
				0, -1, [dst.id], -1, {}, int(ctx.get("harm", {}).get("point", 0)))
			return WAIT
		if not take_skill_reply():
			return SUCCESS
	notice_skill(XUE_YING_KUANG_DAO, [dst.id])
	var harm: Dictionary = ctx["harm"]
	harm["point"] = int(harm["point"]) + (2 if n == 2 else 1)
	return SUCCESS


## 【血腥咆哮】本次攻击强制命中。
## 是否询问：普通出牌攻击（true）按原版弹窗询问是否发动；技能栏按钮预选（false）直接结算
func _xue_xing_pao_xiao(ctx: Dictionary, 是否询问: bool) -> int:
	var card: GCard = Data.get_card(int(ctx.get("card_id", -1)))
	if card == null or not card.has_skill_id(XUE_XING_PAO_XIAO) or not bool(ctx.get("is_active", false)):
		return SUCCESS
	var dst: BattlePlayer = engine.p(int(ctx.get("dst", -1)))
	if dst == null or dst.cross_num != 2:
		return SUCCESS
	if 是否询问:
		if not engine.has_reply():
			询问(player.id, XUE_XING_PAO_XIAO)
			return WAIT
		if not take_skill_reply():
			return SUCCESS
	notice_skill(XUE_XING_PAO_XIAO, [dst.id])
	ctx["hit_rate"] = GConst.HitRate.NoMiss
	return SUCCESS


func _kuang_hua(harm: Dictionary) -> int:
	notice_skill(KUANG_HUA, [int(harm["dst"])])
	harm["point"] = int(harm["point"]) + 1
	return SUCCESS


func _si_lie(harm: Dictionary) -> int:
	if player.gem <= 0:
		return SUCCESS
	if not engine.has_reply():
		询问(player.id, SI_LIE)
		return WAIT
	if not take_skill_reply():
		return SUCCESS
	notice_skill(SI_LIE, [int(harm["dst"])])
	harm["point"] = int(harm["point"]) + 2
	player.set_gem(player.gem - 1)
	engine._broadcast_game()
	return SUCCESS
