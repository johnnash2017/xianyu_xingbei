extends BattleRole
## 死灵法师（roleID 13）—— 移植自服务端 role/SiLing.cpp
## 被动：圣渎（1302，[治疗]上限 +3；[治疗]不能抵御攻击伤害）
## 技能：不朽（1301，响应：[法术行动]结束时可选，自身 +1 治疗）、
##       瘟疫（1303，法术：弃 1 张地系牌[展示]，对其他所有角色各 1 点法术伤害）、
##       死亡之触（1304，法术：移除 A 点治疗并弃 B 张同系牌（A、B≥2），
##                 对目标造成 A+B-3 点法术伤害；不能和不朽同时发动）、
##       墓碑陨落（1305，必杀技：消耗 1 宝石，对其他所有角色各 2 点法术伤害，自身 +1 治疗）
## 说明：服务端无形态与指示物（圣渎为被动、不朽为响应），故本移植不使用 tokens。

const BU_XIU: int = 1301
const SHENG_DU: int = 1302
const WEN_YI: int = 1303
const SI_WANG_ZHI_CHU: int = 1304
const MU_BEI_YUN_LUO: int = 1305

## 服务端 p_after_magic 只做一次询问；墓碑陨落的「+1 治疗」在服务端由 p_magic_skill 重入结算，
## 本引擎 SkillRun 不重入，故移到 p_after_magic 首段（见 pending_mu_bei_cross）
var used_si_wang_zhi_chu: bool = false
var pending_mu_bei_cross: bool = false


func setup(p: BattlePlayer, e: BattleEngine) -> void:
	super.setup(p, e)
	# 圣渎：你的[治疗]上限 +3
	p.cross_max = GConst.CROSS_MAX + 3


func available_skills() -> Array:
	var out: Array = []
	if _hand_has_element(GConst.CardElement.Earth):
		out.append({"type": GConst.ActionType.MagicSkill, "id": WEN_YI, "need_card": 1, "need_target": 0})
	if player.cross_num >= 2 and _has_same_element_pair():
		out.append({"type": GConst.ActionType.MagicSkill, "id": SI_WANG_ZHI_CHU, "need_card": 1, "need_target": 1})
	if player.gem >= 1:
		out.append({"type": GConst.ActionType.MagicSkill, "id": MU_BEI_YUN_LUO, "need_card": 0, "need_target": 0})
	return out


# ============================================================
# 法术行动结束后：墓碑陨落第二段（+1 治疗）→ 不朽（1301）
# ============================================================
func p_after_magic(ctx: Dictionary) -> int:
	# 法术牌走 _do_magic（ctx 用 src），法术技能走 SkillRun（ctx 用 player，含 action_id）
	var pid: int = int(ctx.get("player", ctx.get("src", -1)))
	if pid != player.id:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if step == 0:
		# 墓碑陨落：对其他角色的伤害结算完毕后自身 +1 治疗
		if pending_mu_bei_cross:
			pending_mu_bei_cross = false
			player.add_cross_num(1)
			engine._broadcast_game()
		step = BU_XIU
	if step == BU_XIU:
		return _bu_xiu()
	return SUCCESS


## 不朽：法术行动结束后可选，自身 +1 治疗；若本回合用过死亡之触则跳过并复位
func _bu_xiu() -> int:
	if used_si_wang_zhi_chu:
		used_si_wang_zhi_chu = false
		step = STEP_DONE
		return SUCCESS
	if not engine.has_reply():
		engine.ask_skill(player.id, BU_XIU, 0, 0)
		return WAIT
	step = STEP_DONE
	if not take_skill_reply():
		return SUCCESS
	notice_skill(BU_XIU, [player.id])
	player.add_cross_num(1)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 圣渎：[治疗]不能抵御攻击伤害（服务端 crossAvailable = 0）
# ============================================================
func p_timeline_4(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("dst", -1)) != player.id:
		return SUCCESS
	if int(harm.get("type", -1)) != GConst.HarmType.Attack:
		return SUCCESS
	if int(harm.get("cross_available", 1)) <= 0:
		return SUCCESS
	harm["cross_available"] = 0
	notice_skill(SHENG_DU, [player.id])
	return SUCCESS


# ============================================================
# 主动法术技能
# ============================================================
func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	var aid: int = int(action.get("action_id", 0))
	var cards: Array = action.get("card_ids", [])
	var args: Array = action.get("args", [])
	match aid:
		WEN_YI:
			if cards.is_empty():
				return GConst.GE_INVALID_CARDID
			var cid: int = int(cards[0])
			var card: GCard = Data.get_card(cid)
			if not player.has_hand_card(cid) or card == null or card.element_enum() != GConst.CardElement.Earth:
				return GConst.GE_INVALID_ACTION
		SI_WANG_ZHI_CHU:
			if cards.size() < 2 or args.is_empty() or int(args[0]) < 2:
				return GConst.GE_INVALID_ACTION
			if player.cross_num < int(args[0]):
				return GConst.GE_INVALID_ACTION
			var element: int = -1
			for c: Variant in cards:
				var cid2: int = int(c)
				var card2: GCard = Data.get_card(cid2)
				if card2 == null or not player.has_hand_card(cid2):
					return GConst.GE_INVALID_ACTION
				if element < 0:
					element = card2.element_enum()
				elif element != card2.element_enum():
					return GConst.GE_INVALID_ACTION
			var dsts: Array = action.get("dst_ids", [])
			if dsts.is_empty():
				return GConst.GE_INVALID_ACTION
		MU_BEI_YUN_LUO:
			if player.gem < 1:
				return GConst.GE_INVALID_ACTION
		_:
			return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	match int(action.get("action_id", 0)):
		WEN_YI:
			return _wen_yi(action)
		SI_WANG_ZHI_CHU:
			return _si_wang_zhi_chu(action)
		MU_BEI_YUN_LUO:
			return _mu_bei_yun_luo(action)
	return GConst.GE_INVALID_ACTION


## 瘟疫：弃 1 张地系牌，对其他所有角色各 1 点法术伤害
func _wen_yi(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var cid: int = int(cards[0])
	var dst_ids: Array = _all_other_ids_from_self()
	notice_skill(WEN_YI, dst_ids)
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": [cid], "is_real": true,
	})
	engine.take_from_hand(player.id, [cid])
	engine.to_discard([cid])
	for d: Variant in dst_ids:
		engine.push_harm({
			"src": player.id, "dst": int(d), "point": 1,
			"cause": WEN_YI, "type": GConst.HarmType.Magic,
		})
	engine._broadcast_game()
	return URGENT


## 死亡之触：移除 A 点治疗并弃 B 张同系牌，对目标造成 A+B-3 点法术伤害
func _si_wang_zhi_chu(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var args: Array = action.get("args", [])
	var dsts: Array = action.get("dst_ids", [])
	var cross_used: int = int(args[0])
	var dst_id: int = int(dsts[0])
	used_si_wang_zhi_chu = true
	notice_skill(SI_WANG_ZHI_CHU, [dst_id])
	player.sub_cross_num(cross_used)
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": cards, "is_real": true,
	})
	engine.take_from_hand(player.id, cards)
	engine.to_discard(cards)
	engine.push_harm({
		"src": player.id, "dst": dst_id, "point": cards.size() + cross_used - 3,
		"cause": SI_WANG_ZHI_CHU, "type": GConst.HarmType.Magic,
	})
	engine._broadcast_game()
	return URGENT


## 墓碑陨落：消耗 1 宝石，对其他所有角色各 2 点法术伤害，再自身 +1 治疗
func _mu_bei_yun_luo(_action: Dictionary) -> int:
	var dst_ids: Array = _all_other_ids_from_self()
	notice_skill(MU_BEI_YUN_LUO, dst_ids)
	player.set_gem(player.gem - 1)
	for d: Variant in dst_ids:
		engine.push_harm({
			"src": player.id, "dst": int(d), "point": 2,
			"cause": MU_BEI_YUN_LUO, "type": GConst.HarmType.Magic,
		})
	pending_mu_bei_cross = true
	engine._broadcast_game()
	return URGENT


# ============================================================
# 工具
# ============================================================
func _hand_has_element(elem: int) -> bool:
	for cid: int in player.hand_cards:
		var c: GCard = Data.get_card(cid)
		if c != null and c.element_enum() == elem:
			return true
	return false


## 手牌中是否存在两张同系牌（死亡之触的弃牌条件）
func _has_same_element_pair() -> bool:
	var elems: Array[int] = []
	for cid: int in player.hand_cards:
		var c: GCard = Data.get_card(cid)
		if c == null:
			continue
		var e: int = c.element_enum()
		if elems.has(e):
			return true
		elems.append(e)
	return false


## 从自己下家开始、按座位序绕回自己之前，收集其他所有角色 id
func _all_other_ids_from_self() -> Array:
	var ids: Array = []
	var cur: int = player.post_id
	var guard: int = engine.order.size()
	while cur != player.id and guard > 0:
		ids.append(cur)
		cur = engine.next_id(cur)
		guard -= 1
	return ids
