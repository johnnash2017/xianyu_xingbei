extends BattleRole
## 魔剑（roleID 9）—— 移植自服务端 role/MoJian.cpp
## 形态：tap = [暗影形态]（回合开始时询问「暗影凝聚」进入，下个行动阶段开始时解除）
## 技能：修罗连斩（901，响应：[攻击行动]结束时追加 1 次火系攻击行动）、
##       暗影凝聚（902，启动：对自身 1 点法术伤害，进入[暗影形态]）、
##       暗影之力（903，被动：仅[暗影形态]下，自身发动的攻击伤害 +1）、
##       暗影抗拒（904，被动：你的行动阶段始终不能使用法术牌，由 v_missile/v_shield/v_weaken 覆写实现）、
##       暗影流星（905，法术：仅[暗影形态]下，弃 2 张法术牌[展示]，对目标 2 点法术伤害）、
##       黑暗震颤（906，响应：主动攻击前耗 1 宝石，本次攻击对方无法应战；
##                 若命中则手牌补到上限（9061，多则弃、少则摸））

const XIU_LUO_LIAN_ZHAN: int = 901
const AN_YING_NING_JU: int = 902
const AN_YING_ZHI_LI: int = 903
const AN_YING_KANG_JU: int = 904
const AN_YING_LIU_XING: int = 905
const HEI_AN_ZHEN_CHAN: int = 906
const HEI_AN_ZHEN_CHAN_BU_PAI: int = 9061

## 黑暗震颤补牌基准手牌数
const HAND_BASE: int = 4

var used_xiu_luo_lian_zhan: bool = false
var using_xiu_luo_lian_zhan: bool = false
var used_hei_an_zhen_chan: bool = false
var using_hei_an_zhen_chan: bool = false


func available_skills() -> Array:
	var out: Array = []
	# 暗影流星（905）：仅[暗影形态]（tap）下可用，需弃 2 张法术牌
	if player.tap and _magic_card_count() >= 2:
		out.append({"type": GConst.ActionType.MagicSkill, "id": AN_YING_LIU_XING, "need_card": 1, "need_target": 1})
	return out


## 手牌中法术牌数量
func _magic_card_count() -> int:
	var n: int = 0
	for cid: int in player.hand_cards:
		var c: GCard = Data.get_card(cid)
		if c != null and c.is_magic():
			n += 1
	return n


# ============================================================
# 牌类校验覆写（对照服务端 MoJian::v_missile / v_shield / v_weaken / v_attack）
# 【暗影抗拒】（904）：服务端恒返回 GE_INVALID_CARDID，即不能使用魔弹/圣盾/虚弱；
# 【修罗连斩】（901）的额外攻击行动期间，服务端限定只能用火系攻击牌。
# 暗影流星（905）属法术技能（走 v_magic_skill），不受上述限制。
# 说明：服务端未覆写中毒等其他法术牌的校验路径，故本引擎同样不拦截。
# ============================================================
func v_missile(_card_id: int, _dst_id: int) -> int:
	return GConst.GE_INVALID_CARDID


func v_shield(_dst_id: int, _players: Dictionary) -> int:
	return GConst.GE_INVALID_CARDID


func v_weaken(_dst_id: int, _players: Dictionary) -> int:
	return GConst.GE_INVALID_CARDID


## 修罗连斩额外攻击行动期间只能用火系攻击牌
func v_attack(card_id: int, dst_id: int, players: Dictionary) -> int:
	var rc: int = player.base_v_attack(card_id, dst_id, players)
	if rc != GConst.GE_SUCCESS:
		return rc
	if using_xiu_luo_lian_zhan:
		var card: GCard = Data.get_card(card_id)
		if card.element_enum() != GConst.CardElement.Fire:
			return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_before_turn_begin(_ctx: Dictionary) -> int:
	used_xiu_luo_lian_zhan = false
	using_xiu_luo_lian_zhan = false
	used_hei_an_zhen_chan = false
	using_hei_an_zhen_chan = false
	return SUCCESS


# ============================================================
# 启动：暗影凝聚（902）
# 服务端在 p_before_action 里解除[暗影形态]（MoJian::p_before_action）；
# 本实现仍并入 p_boot 首段——引擎中 p_boot 先于 p_before_action 执行，两者都在行动阶段之前，行为等价
# ============================================================
func p_boot(_ctx: Dictionary) -> int:
	if engine.current_id != player.id:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if step == 0:
		if player.tap:
			player.tap = false
			engine._broadcast_game()
		step = AN_YING_NING_JU
	if step == AN_YING_NING_JU:
		if not engine.has_reply():
			engine.ask_skill(player.id, AN_YING_NING_JU, 0, 0)
			return WAIT
		step = STEP_DONE
		if not take_skill_reply():
			return SUCCESS
		notice_skill(AN_YING_NING_JU, [player.id])
		player.tap = true
		engine.push_harm({
			"src": player.id, "dst": player.id, "point": 1,
			"cause": AN_YING_NING_JU, "type": GConst.HarmType.Magic,
		})
		engine._broadcast_game()
		return URGENT
	return SUCCESS


# ============================================================
# 主动攻击前（timeline_1）：黑暗震颤（906）
# ============================================================
func p_timeline_1(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	if player.gem <= 0 or used_hei_an_zhen_chan:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if not engine.has_reply():
		engine.ask_skill(player.id, HEI_AN_ZHEN_CHAN, 0, 0)
		return WAIT
	step = STEP_DONE
	if not take_skill_reply():
		return SUCCESS
	notice_skill(HEI_AN_ZHEN_CHAN, [int(ctx.get("dst", -1))])
	player.set_gem(player.gem - 1)
	used_hei_an_zhen_chan = true
	using_hei_an_zhen_chan = true
	ctx["hit_rate"] = GConst.HitRate.NoReattack
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 主动攻击命中后：暗影之力（903）→ 黑暗震颤补牌（9061）
# ============================================================
func p_timeline_2_hit(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("src", -1)) != player.id:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if step == 0:
		step = AN_YING_ZHI_LI
	if step == AN_YING_ZHI_LI:
		if player.tap:
			notice_skill(AN_YING_ZHI_LI, [int(harm.get("dst", -1))])
			harm["point"] = int(harm.get("point", 0)) + 1
		step = HEI_AN_ZHEN_CHAN_BU_PAI
	if step == HEI_AN_ZHEN_CHAN_BU_PAI:
		return _hei_an_zhen_chan_bu_pai()
	return SUCCESS


## 黑暗震颤补牌：手牌多于 4 则弃到 4，少于 4 则摸到 4
func _hei_an_zhen_chan_bu_pai() -> int:
	if not using_hei_an_zhen_chan:
		step = STEP_DONE
		return SUCCESS
	var num: int = player.hand_cards.size() - HAND_BASE
	if num > 0:
		if not engine.has_reply():
			engine.ask_skill(player.id, HEI_AN_ZHEN_CHAN_BU_PAI, 1, 0)
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		step = STEP_DONE
		using_hei_an_zhen_chan = false
		notice_skill(HEI_AN_ZHEN_CHAN_BU_PAI, [player.id])
		_discard_exact(num, r.get("card_ids", []))
		engine._broadcast_game()
		return SUCCESS
	step = STEP_DONE
	using_hei_an_zhen_chan = false
	if num < 0:
		notice_skill(HEI_AN_ZHEN_CHAN_BU_PAI, [player.id])
		engine.draw(player.id, -num)
		engine._broadcast_game()
	return SUCCESS


func p_timeline_2_miss(_ctx: Dictionary) -> int:
	using_hei_an_zhen_chan = false
	return SUCCESS


# ============================================================
# 攻击行动结束后：修罗连斩（901，追加 1 次火系攻击行动）
# ============================================================
func p_after_attack(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	step = STEP_DONE
	if player.hand_cards.is_empty() or used_xiu_luo_lian_zhan:
		return SUCCESS
	if _contains_action(XIU_LUO_LIAN_ZHAN):
		return SUCCESS
	notice_skill(XIU_LUO_LIAN_ZHAN, [player.id])
	player.add_action(GConst.ActionType.Attack, XIU_LUO_LIAN_ZHAN)
	# 回合限定的 used 标记在玩家选中该额外行动时置位（服务端 p_additional_action）
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 玩家选中额外行动时的二次校验（服务端 MoJian::v_additional_action）：
# 修罗连斩本回合限一次
# ============================================================
func v_additional_action(cause: int) -> int:
	if cause != XIU_LUO_LIAN_ZHAN:
		return V_NOT_OVERRIDE
	if used_xiu_luo_lian_zhan:
		return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


# ============================================================
# 玩家选中额外行动时：置「修罗连斩」标记供 v_attack 限制火系牌
# （对照服务端 p_additional_action：选中修罗连斩置位 used/using，其余额外行动清除 using）
# ============================================================
func p_additional_action(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	var cause: int = int(ctx.get("cause", 0))
	using_xiu_luo_lian_zhan = cause == XIU_LUO_LIAN_ZHAN
	if using_xiu_luo_lian_zhan:
		used_xiu_luo_lian_zhan = true
	return SUCCESS


# ============================================================
# 主动法术技能：暗影流星（905）
# ============================================================
func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != AN_YING_LIU_XING or not player.tap:
		return GConst.GE_INVALID_ACTION
	var cards: Array = action.get("card_ids", [])
	if cards.size() != 2:
		return GConst.GE_INVALID_ACTION
	for c: Variant in cards:
		var cid: int = int(c)
		var card: GCard = Data.get_card(cid)
		if card == null or not card.is_magic() or not player.has_hand_card(cid):
			return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != AN_YING_LIU_XING:
		return GConst.GE_INVALID_ACTION
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	var dst_id: int = int(dsts[0]) if not dsts.is_empty() else player.id
	notice_skill(AN_YING_LIU_XING, [dst_id])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": cards, "is_real": true,
	})
	engine.push_harm({
		"src": player.id, "dst": dst_id, "point": 2,
		"cause": AN_YING_LIU_XING, "type": GConst.HarmType.Magic,
	})
	engine.take_from_hand(player.id, cards)
	engine.to_discard(cards)
	engine._broadcast_game()
	return URGENT


# ============================================================
# 工具
# ============================================================
## 是否已存在某来源的额外行动
func _contains_action(cause: int) -> bool:
	for a: Dictionary in player.additional_actions:
		if int(a.get("cause", -1)) == cause:
			return true
	return false


## 精确弃 num 张牌（客户端优先给出要弃的牌，不足时从手牌补齐）
func _discard_exact(num: int, cards: Array) -> void:
	var chosen: Array = []
	for c: Variant in cards:
		if chosen.size() < num and player.has_hand_card(int(c)):
			chosen.append(int(c))
	if chosen.size() < num:
		for cid: int in player.hand_cards:
			if chosen.size() >= num:
				break
			if not chosen.has(cid):
				chosen.append(cid)
	engine.take_from_hand(player.id, chosen)
	engine.to_discard(chosen)
