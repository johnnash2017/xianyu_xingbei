extends BattleRole
## 圣女（roleID 6）—— 移植自服务端 role/ShengNv.cpp
## 技能：冰霜祷言（使用水系牌或【圣光】时可选，目标+1 治疗）、治疗术（法术，目标+2 治疗）、
##       治愈之光（法术，最多 3 名角色各+1 治疗）、怜悯（启动，1 宝石转怜悯形态并 +1 水晶，手牌上限恒为 7）、
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
	# 怜悯（启动）：有宝石且未横置时可发动 —— 耗 1 宝石转怜悯形态、+1 水晶（手牌上限恒为 7）
	if player.gem > 0 and not player.tap:
		out.append({"type": GConst.ActionType.SpecialSkill, "id": LIAN_MIN, "need_card": 0, "need_target": 0})
	return out


## 每回合开始重置「圣疗」使用标记
func p_before_turn_begin(_ctx: Dictionary) -> int:
	used_sheng_liao = false
	return SUCCESS


# ============================================================
# 启动技能（行动阶段按钮）：怜悯（604）
# （「每回合只能发动一个启动技能」由引擎统一把关，这里只校验技能自身条件）
# ============================================================
## 怜悯为「启动」：不消耗本回合行动，发动后行动阶段照旧继续
func is_free_skill(skill_id: int) -> bool:
	return skill_id == LIAN_MIN


func v_special_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != LIAN_MIN:
		return GConst.GE_INVALID_ACTION
	# 无宝石或已横置：不能发动
	if player.gem <= 0 or player.tap:
		return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


## 怜悯：耗 1 宝石并横置（进入怜悯形态，手牌上限恒为 7），并 +1 水晶
func p_special_skill(_action: Dictionary) -> int:
	notice_skill(LIAN_MIN, [player.id])
	player.boot_skill_used = true
	player.tap = true
	player.set_gem(player.gem - 1)
	player.set_crystal(player.crystal + 1)
	player.hand_cards_max = 7
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 展示手牌（p_show_hand）：冰霜祷言（603）—— 每当你使用水系牌或【圣光】时
# 引擎里任何「公开打出的牌」都会经 take_from_hand(..., 已展示=true) 触发本钩子（与封印师的封印同源）。
# 触发口径（策划）：
#   · 水系牌：公开打出即触发（任意场合）；
#   · 【圣光】：仅限「用【圣光】抵挡攻击」（应战抵挡）时触发——引擎在该场合把 ctx["格挡攻击"] 置真；
#            用【圣光】抵挡魔弹、弃牌展示等其它公开打出【圣光】的场合都不算。
# ============================================================
func p_show_hand(ctx: Dictionary) -> int:
	# 钩子对每个角色都会触发一次，只处理自己打出的牌
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if not _触发冰霜祷言(ctx.get("cards", []), bool(ctx.get("格挡攻击", false))):
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


## 本次展示的牌里是否含「水系牌」，或含「用于格挡攻击的【圣光】」（冰霜祷言的触发条件）
## 格挡攻击=false 时【圣光】不计入：区别于抵挡魔弹 / 弃牌展示等其它公开打出【圣光】的场合
func _触发冰霜祷言(cards: Array, 格挡攻击: bool) -> bool:
	for c: Variant in cards:
		var card: GCard = Data.get_card(int(c))
		if card == null:
			continue
		if card.element_enum() == GConst.CardElement.Water:
			return true
		if 格挡攻击 and card.card_name_enum() == GConst.CardName.HolyLight:
			return true
	return false


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
	engine.take_from_hand(player.id, [cid], true)
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
	engine.take_from_hand(player.id, [cid], true)
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
