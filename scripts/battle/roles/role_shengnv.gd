extends BattleRole
## 圣女（roleID 6）—— 移植自服务端 role/ShengNv.cpp
## 技能：冰霜祷言（使用水系攻击时可选，目标+1 治疗）、治疗术（法术，目标+2 治疗）、
##       治愈之光（法术，最多 3 名角色各+1 治疗）、怜悯（启动，1 宝石转怜悯形态，手牌上限恒为 7）、
##       圣疗（必杀技，1 能量任意分配 3 治疗，额外攻/法行动，每回合限一次）

const ZHI_LIAO_SHU: int = 601
const ZHI_YU_ZHI_GUANG: int = 602
const BING_SHUANG_DAO_YAN: int = 603
const LIAN_MIN: int = 604
const SHENG_LIAO: int = 605

var used_sheng_liao: bool = false


func available_skills() -> Array:
	var out: Array = []
	# 治疗术/治愈之光：只有手中带对应特技的牌可作发动牌，下发给界面把其余手牌置灰
	# （v_magic_skill 校验同一张牌：须在手且带该特技）
	var 治疗牌: Array[int] = hand_ids_with_skill(ZHI_LIAO_SHU)
	if not 治疗牌.is_empty():
		out.append({"type": GConst.ActionType.MagicSkill, "id": ZHI_LIAO_SHU, "need_card": 1, "need_target": 1,
			"cards": 治疗牌})
	var 治愈牌: Array[int] = hand_ids_with_skill(ZHI_YU_ZHI_GUANG)
	if not 治愈牌.is_empty():
		# v_magic_skill：dsts 至少 1 名、至多 3 名（dsts.size() > 3 直接拒），故放开目标上限
		out.append({"type": GConst.ActionType.MagicSkill, "id": ZHI_YU_ZHI_GUANG, "need_card": 1, "need_target": 1,
			"target_max": 3, "cards": 治愈牌})
	if player.get_energy() >= 1 and not used_sheng_liao:
		# v_magic_skill 只校验能量与使用标记，不校验目标数/args；
		# 执行体 _sheng_liao 把 3 点治疗按 args 逐一分配给 dsts（args[i] 为第 i 名目标的治疗量，合计 3）。
		# 分配过程由客户端做「点头像 +1 治疗」的交互，选满 3 点后把「目标 + 各自点数」一并回传，
		# 所以这里不再下发 arg_choices 让玩家点选项
		out.append({"type": GConst.ActionType.MagicSkill, "id": SHENG_LIAO, "need_card": 0, "need_target": 1,
			"target_max": 3})
	return out


## 每回合开始重置「圣疗」使用标记
func p_before_turn_begin(_ctx: Dictionary) -> int:
	used_sheng_liao = false
	return SUCCESS


# ============================================================
# 启动类：怜悯（自身回合开始、有宝石且未横置时询问）
# ============================================================
func p_boot(_ctx: Dictionary) -> int:
	if engine.current_id != player.id:
		return SUCCESS
	if player.gem == 0 or player.tap:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if not engine.has_reply():
		询问(player.id, LIAN_MIN, 0, 0)
		return WAIT
	step = STEP_DONE
	if not take_skill_reply():
		return SUCCESS
	notice_skill(LIAN_MIN, [player.id])
	player.tap = true
	player.set_gem(player.gem - 1)
	player.hand_cards_max = 7
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 攻击宣告后：冰霜祷言（水系攻击可选，指定一名角色+1 治疗）
# ============================================================
func p_timeline_1(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	var card: GCard = Data.get_card(int(ctx.get("card_id", -1)))
	if card == null or card.element_enum() != GConst.CardElement.Water:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if not engine.has_reply():
		询问(player.id, BING_SHUANG_DAO_YAN, 0, 1)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	var args: Array = r.get("args", [])
	var dsts: Array = r.get("dst_ids", [])
	var dst_id: int = int(dsts[0]) if not dsts.is_empty() else player.id
	if args.is_empty() or int(args[0]) != 1:
		# 超时/取消兜底：服务端超时分支给自己 +1 治疗
		notice_skill(BING_SHUANG_DAO_YAN, [player.id])
		施加治疗(player.id, 1)
		engine._broadcast_game()
		return SUCCESS
	var dst: BattlePlayer = engine.p(dst_id)
	if dst == null:
		return SUCCESS
	notice_skill(BING_SHUANG_DAO_YAN, [dst_id])
	施加治疗(dst_id, 1)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 主动法术技能
# ============================================================
func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	var aid: int = int(action.get("action_id", 0))
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	match aid:
		ZHI_LIAO_SHU:
			if cards.is_empty():
				return GConst.GE_INVALID_CARDID
			var cid: int = int(cards[0])
			var card: GCard = Data.get_card(cid)
			if not player.has_hand_card(cid) or card == null or not card.has_skill_id(ZHI_LIAO_SHU):
				return GConst.GE_INVALID_ACTION
		ZHI_YU_ZHI_GUANG:
			if cards.is_empty():
				return GConst.GE_INVALID_CARDID
			var cid2: int = int(cards[0])
			var card2: GCard = Data.get_card(cid2)
			if not player.has_hand_card(cid2) or card2 == null or not card2.has_skill_id(ZHI_YU_ZHI_GUANG):
				return GConst.GE_INVALID_ACTION
			if dsts.is_empty() or dsts.size() > 3:
				return GConst.GE_INVALID_ACTION
		SHENG_LIAO:
			if player.get_energy() < 1 or used_sheng_liao:
				return GConst.GE_INVALID_ACTION
		_:
			return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	match int(action.get("action_id", 0)):
		ZHI_LIAO_SHU:
			return _zhi_liao_shu(action)
		ZHI_YU_ZHI_GUANG:
			return _zhi_yu_zhi_guang(action)
		SHENG_LIAO:
			return _sheng_liao(action)
	return GConst.GE_INVALID_ACTION


## 治疗术：目标 +2 治疗
func _zhi_liao_shu(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	var cid: int = int(cards[0])
	var dst_id: int = int(dsts[0]) if not dsts.is_empty() else player.id
	var dst: BattlePlayer = engine.p(dst_id)
	if dst == null:
		return GConst.GE_INVALID_PLAYERID
	notice_skill(ZHI_LIAO_SHU, [dst_id])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": [cid], "is_real": true,
	})
	engine.take_from_hand(player.id, [cid])
	engine.to_discard([cid])
	施加治疗(dst.id, 2)
	engine._broadcast_game()
	return SUCCESS


## 治愈之光：最多 3 名角色各 +1 治疗
func _zhi_yu_zhi_guang(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	var cid: int = int(cards[0])
	notice_skill(ZHI_YU_ZHI_GUANG, dsts)
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": [cid], "is_real": true,
	})
	engine.take_from_hand(player.id, [cid])
	engine.to_discard([cid])
	for d: Variant in dsts:
		var dp: BattlePlayer = engine.p(int(d))
		if dp != null:
			施加治疗(dp.id, 1)
	engine._broadcast_game()
	return SUCCESS


## 圣疗：消耗 1 能量，任意分配 3 点治疗，额外 +1 攻击或法术行动
func _sheng_liao(action: Dictionary) -> int:
	var dsts: Array = action.get("dst_ids", [])
	var args: Array = action.get("args", [])
	notice_skill(SHENG_LIAO, dsts)
	# 消耗 1 能量：优先扣水晶
	if player.crystal > 0:
		player.set_crystal(player.crystal - 1)
	else:
		player.set_gem(player.gem - 1)
	# 分配治疗：显式给定时按其数值，否则把 3 点全给第一个目标
	var remain: int = 3
	for i: int in range(dsts.size()):
		var dp: BattlePlayer = engine.p(int(dsts[i]))
		if dp == null:
			continue
		var amount: int = int(args[i]) if i < args.size() else remain
		amount = mini(amount, remain)
		if amount <= 0:
			continue
		施加治疗(dp.id, amount)
		remain -= amount
	used_sheng_liao = true
	# direct=true：获得额外行动后不必再点一次【圣疗】按钮，直接进入额外行动阶段（里面可放弃）
	player.add_action(GConst.ActionType.AttackMagic, SHENG_LIAO, true)
	engine._broadcast_game()
	return SUCCESS
