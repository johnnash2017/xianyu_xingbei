extends BattleRole
## 神官（roleID 15）—— 移植自服务端 role/ShenGuan.cpp
## 被动：圣使守护（治疗上限 +4；每次用治疗抵御伤害最多只能用 1 点，见 p_timeline_4）
## 启动：神圣契约（技能栏按钮发动，1 能量 + 转移 X 治疗给队友，无视其治疗上限但最高为 4）
## 法术：神圣祈福（弃 2 张法术牌，自己 +2 治疗）、
##       水之神力（弃 1 张水系牌，给目标队友 1 张手牌，双方各 +1 治疗）、
##       神圣领域（1 能量，弃 min(2, 手牌) 张牌：移除 1 治疗对目标造成 2 点法术伤害，或自己 +2 / 队友 +1 治疗）
## 响应：神圣启示（特殊行动结束时，自己 +1 治疗）

const SHEN_SHENG_QI_SHI: int = 1501   # 神圣启示（被动响应）
const SHEN_SHENG_QI_FU: int = 1502    # 神圣祈福
const SHUI_ZHI_SHEN_LI: int = 1503    # 水之神力
const SHENG_SHI_SHOU_HU: int = 1504   # 圣使守护（被动）
const SHEN_SHENG_QI_YUE: int = 1505   # 神圣契约
const SHEN_SHENG_LING_YU: int = 1506  # 神圣领域

const CROSS_MAX_BONUS: int = 4
const LING_YU_DISCARD: int = 2        # 神圣领域最多弃 2 张牌

## 水之神力的交牌子步骤（0 = 尚未弃牌 / 1 = 等待交出 1 张手牌）
var _shui_shen_phase: int = 0
## 水之神力第一步选定的队友：第二步「交哪张牌」的询问不带目标，得把它记下来，
## 否则第二步回包没有 dst_ids，牌会交给自己（等于白交）
var _shui_shen_dst: int = -1


func setup(p: BattlePlayer, e: BattleEngine) -> void:
	super.setup(p, e)
	# 圣使守护：治疗上限 +4
	p.cross_max = p.cross_max + CROSS_MAX_BONUS


func available_skills() -> Array:
	var out: Array = []
	if _count_magic_cards() >= 2:
		out.append({"type": GConst.ActionType.MagicSkill, "id": SHEN_SHENG_QI_FU, "need_card": 2, "need_target": 0,
			"cards": magic_hand_ids()})
	if _has_water_card():
		# 水之神力要弃 1 张水系牌：只让手牌里的水系牌可点（v_magic_skill 校验 card2.element_enum() == Water）
		# 目标须为同色队友（v_magic_skill：dst1.color != player.color 时返回 GE_INVALID_ACTION）；
		# 自己与自己是同色，所以也点得动（给牌＝给自己，等价于白洗一张水系牌）
		var 水牌目标: Array[int] = ally_ids()
		水牌目标.append(player.id)
		out.append({"type": GConst.ActionType.MagicSkill, "id": SHUI_ZHI_SHEN_LI, "need_card": 1, "need_target": 1,
			"cards": hand_ids_where(func(_cid: int, c: GCard) -> bool: return c.element_enum() == GConst.CardElement.Water),
			"targets": 水牌目标})
	if player.get_energy() >= 1:
		# 神圣领域要弃牌：手牌多于 2 张时恰好弃 2 张，否则把手牌弃光（v_magic_skill 同一条）
		# 用法不用按钮选，直接由目标决定（客户端按目标我方/敌方定 args）：
		#   选队友（含自己）＝ 自己 +2、目标 +1 治疗（args[0]==0）；选敌人 ＝ 移除自己 1 治疗、目标受 2 点法术伤害（args[0]==1）
		# 自己治疗不足时打不出伤害（v_magic_skill 判 cross_num < 1），所以这时敌人整片不亮
		out.append({
			"type": GConst.ActionType.MagicSkill, "id": SHEN_SHENG_LING_YU,
			"need_card": mini(LING_YU_DISCARD, player.hand_cards.size()), "need_target": 1,
			"targets": _ling_yu_targets(),
		})
	# 【神圣契约】为「启动」：有能量且有治疗时可发动，把治疗转移给队友（不消耗本回合行动）
	if player.get_energy() >= 1 and player.cross_num > 0:
		out.append({"type": GConst.ActionType.SpecialSkill, "id": SHEN_SHENG_QI_YUE,
			"need_card": 0, "need_target": 1, "targets": ally_ids()})
	return out


## 手牌中法术牌数量
func _count_magic_cards() -> int:
	var n: int = 0
	for cid: int in player.hand_cards:
		var c: GCard = Data.get_card(cid)
		if c != null and c.is_magic():
			n += 1
	return n


## 手牌中是否有水系牌
func _has_water_card() -> bool:
	for cid: int in player.hand_cards:
		var c: GCard = Data.get_card(cid)
		if c != null and c.element_enum() == GConst.CardElement.Water:
			return true
	return false


func _has_cards(cards: Array) -> bool:
	for c: Variant in cards:
		if not player.has_hand_card(int(c)):
			return false
	return not cards.is_empty()


## 神圣领域的可选目标：治疗够时全场都能点（含自己，因为「队友」这一边含自己）；
## 自己治疗不足时打不出第一用法（v_magic_skill 判 cross_num < 1），只留队友（含自己）可点
func _ling_yu_targets() -> Array[int]:
	var out: Array[int] = ally_ids()
	out.append(player.id)
	if player.cross_num >= 1:
		out.append_array(enemy_ids())
	return out


# ============================================================
# 圣使守护（被动）：用治疗抵御伤害时最多只能用 1 点治疗
# 服务端 ShenGuan::ShengShiShouHu 于 p_timeline_4 把 crossAvailable 压到 1（仅当原本可抵御）
# ============================================================
func p_timeline_4(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("dst", -1)) != player.id:
		return SUCCESS
	if int(harm.get("cross_available", 1)) <= 0 or player.cross_num <= 0:
		return SUCCESS
	harm["cross_max_point"] = 1
	notice_skill(SHENG_SHI_SHOU_HU, [player.id])
	return SUCCESS


# ============================================================
# 启动：神圣契约（技能栏按钮，有能量且有治疗时可发动）
# 交互走「技能指示器」（const.gd 里 技能_神圣契约）：客户端点头像把自身治疗分给队友，
# 回包的 dst_ids / args 平行 —— args[i] 就是第 i 名队友分到的治疗点数。
# ============================================================
func is_free_skill(skill_id: int) -> bool:
	return skill_id == SHEN_SHENG_QI_YUE


func v_special_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != SHEN_SHENG_QI_YUE:
		return GConst.GE_INVALID_ACTION
	if player.get_energy() <= 0 or player.cross_num <= 0:
		return GConst.GE_INVALID_ACTION
	var dsts: Array = action.get("dst_ids", [])
	var args: Array = action.get("args", [])
	if dsts.is_empty() or args.is_empty():
		return GConst.GE_INVALID_ARGUMENT
	var 合计: int = 0
	for i: int in range(dsts.size()):
		var dst: BattlePlayer = engine.p(int(dsts[i]))
		if dst == null:
			return GConst.GE_INVALID_PLAYERID
		# 只能把治疗转移给队友（不含自己）
		if dst.color != player.color or dst.id == player.id:
			return GConst.GE_INVALID_ACTION
		合计 += int(args[i]) if i < args.size() else 0
	if 合计 <= 0 or 合计 > player.cross_num:
		return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


## 神圣契约：消耗 1 能量，把自己的 X 治疗转移给队友（无视其治疗上限、最高到 4）
func p_special_skill(action: Dictionary) -> int:
	var dsts: Array = action.get("dst_ids", [])
	var args: Array = action.get("args", [])
	# 分配规则（每次几点 / 是否突破上限与封顶）与客户端共用「技能指示器」这一份配置
	var 配置: Dictionary = GConst.技能指示器.get(SHEN_SHENG_QI_YUE, {})
	var 每次: int = int(配置.get("每次", 1))
	var 突破: bool = bool(配置.get("突破上限", false))
	var 封顶: int = int(配置.get("突破封顶", 0))
	if 每次 <= 0:
		每次 = 1
	notice_skill(SHEN_SHENG_QI_YUE, dsts)
	player.boot_skill_used = true
	# 消耗 1 能量：优先扣水晶
	if player.crystal > 0:
		player.set_crystal(player.crystal - 1)
	else:
		player.set_gem(player.gem - 1)
	var 实转: int = 0
	for i: int in range(dsts.size()):
		var dst: BattlePlayer = engine.p(int(dsts[i]))
		var amount: int = int(args[i]) if i < args.size() else 每次
		if amount <= 0:
			continue
		实转 += amount
		# 以此法转移的治疗无视目标治疗上限（突破时按配置的封顶收尾，如最高到 4）
		if 突破:
			施加治疗_突破(dst.id, amount, 封顶)
		else:
			施加治疗(dst.id, amount)
	player.sub_cross_num(实转)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 响应：神圣启示（特殊行动结束时 +1 治疗）
# ============================================================
func p_after_special(ctx: Dictionary) -> int:
	var src_id: int = int(ctx.get("player", ctx.get("src", -1)))
	if src_id != player.id:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if not engine.has_reply():
		询问(player.id, SHEN_SHENG_QI_SHI, 0, 0)
		return WAIT
	step = STEP_DONE
	if not take_skill_reply():
		return SUCCESS
	notice_skill(SHEN_SHENG_QI_SHI, [player.id])
	施加治疗(player.id, 1)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 主动法术技能校验
# ============================================================
func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	var aid: int = int(action.get("action_id", 0))
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	match aid:
		SHEN_SHENG_QI_FU:
			if cards.size() != 2:
				return GConst.GE_INVALID_ACTION
			for c: Variant in cards:
				var card: GCard = Data.get_card(int(c))
				if card == null or not card.is_magic() or not player.has_hand_card(int(c)):
					return GConst.GE_INVALID_ACTION
		SHUI_ZHI_SHEN_LI:
			if cards.is_empty() or dsts.size() != 1:
				return GConst.GE_INVALID_ACTION
			var cid: int = int(cards[0])
			var card2: GCard = Data.get_card(cid)
			if not player.has_hand_card(cid) or card2 == null or card2.element_enum() != GConst.CardElement.Water:
				return GConst.GE_INVALID_ACTION
			var dst1: BattlePlayer = engine.p(int(dsts[0]))
			if dst1 == null or dst1.color != player.color:
				return GConst.GE_INVALID_ACTION
		SHEN_SHENG_LING_YU:
			if dsts.size() != 1:
				return GConst.GE_INVALID_ACTION
			if player.hand_cards.size() > LING_YU_DISCARD:
				if cards.size() != LING_YU_DISCARD:
					return GConst.GE_INVALID_ACTION
			elif cards.size() != player.hand_cards.size():
				return GConst.GE_INVALID_ACTION
			if not _has_cards(cards) and not cards.is_empty():
				return GConst.GE_INVALID_ACTION
			var args: Array = action.get("args", [])
			var mode: int = int(args[0]) if not args.is_empty() else 0
			if player.get_energy() < 1:
				return GConst.GE_INVALID_ACTION
			if mode == 1:
				if player.cross_num < 1:
					return GConst.GE_INVALID_ACTION
			else:
				var dst2: BattlePlayer = engine.p(int(dsts[0]))
				if dst2 == null or dst2.color != player.color:
					return GConst.GE_INVALID_ACTION
		_:
			return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	match int(action.get("action_id", 0)):
		SHEN_SHENG_QI_FU:
			return _shen_sheng_qi_fu(action)
		SHUI_ZHI_SHEN_LI:
			return _shui_zhi_shen_li(action)
		SHEN_SHENG_LING_YU:
			return _shen_sheng_ling_yu(action)
	return GConst.GE_INVALID_ACTION


## 神圣祈福：弃 2 张法术牌，自己 +2 治疗
func _shen_sheng_qi_fu(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	notice_skill(SHEN_SHENG_QI_FU, [player.id])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": cards, "is_real": true,
	})
	engine.take_from_hand(player.id, cards, true)
	engine.to_discard(cards)
	施加治疗(player.id, 2)
	engine._broadcast_game()
	return SUCCESS


## 水之神力：弃 1 张水系牌；若仍有手牌则交给目标队友 1 张，之后双方各 +1 治疗
func _shui_zhi_shen_li(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	# 第二步（交哪张牌）的回包不带目标，沿用第一步记下的队友
	var dst_id: int = int(dsts[0]) if not dsts.is_empty() else _shui_shen_dst
	if dst_id < 0:
		dst_id = player.id
	var dst: BattlePlayer = engine.p(dst_id)
	if _shui_shen_phase == 0:
		var cid: int = int(cards[0])
		notice_skill(SHUI_ZHI_SHEN_LI, [dst_id])
		engine.broadcast(GConst.Msg.Card, {
			"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
			"card_ids": [cid], "is_real": true,
		})
		engine.take_from_hand(player.id, [cid], true)
		engine.to_discard([cid])
		if player.hand_cards.is_empty():
			_shui_shen_dst = -1
			施加治疗(player.id, 1)
			施加治疗(dst.id, 1)
			engine._broadcast_game()
			return SUCCESS
		# 仍有手牌：请玩家选择交给队友的牌（强制交一张，所以不许取消）。
		# 这一步问的是「你自己」，提示取技能表 1503 那一行「提示」列的第 0 条（{dst}=收牌人）
		_shui_shen_phase = 1
		_shui_shen_dst = dst_id
		询问(player.id, SHUI_ZHI_SHEN_LI, 1, 0, GConst.CardSource.Hand, [], 0, "", [], false, 0, dst_id)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	_shui_shen_phase = 0
	_shui_shen_dst = -1
	var picked: Array = r.get("card_ids", [])
	var give: int = -1
	if not picked.is_empty() and player.has_hand_card(int(picked[0])):
		give = int(picked[0])
	else:
		give = player.hand_cards[0]
	player.remove_hand_cards([give])
	dst.add_hand_cards([give])
	# 交牌不发公共亮牌：交/接双方在日志里看到牌名，其他人只看到张数
	engine._log_give_cards(player.id, dst.id, [give])
	施加治疗(player.id, 1)
	施加治疗(dst.id, 1)
	engine._broadcast_game()
	return SUCCESS


## 神圣领域：1 能量 + 弃 min(2, 手牌) 张牌；移除 1 治疗造成 2 点法术伤害，或自己 +2 / 队友 +1 治疗
func _shen_sheng_ling_yu(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	var dst_id: int = int(dsts[0]) if not dsts.is_empty() else player.id
	var dst: BattlePlayer = engine.p(dst_id)
	var args: Array = action.get("args", [])
	var mode: int = int(args[0]) if not args.is_empty() else 0
	notice_skill(SHEN_SHENG_LING_YU, [dst_id])
	if player.crystal > 0:
		player.set_crystal(player.crystal - 1)
	else:
		player.set_gem(player.gem - 1)
	var limit: int = mini(LING_YU_DISCARD, player.hand_cards.size())
	var use_cards: Array = []
	for i: int in range(mini(limit, cards.size())):
		use_cards.append(int(cards[i]))
	if mode == 1:
		player.sub_cross_num(1)
		engine.push_harm({
			"src": player.id, "dst": dst_id, "point": 2,
			"cause": SHEN_SHENG_LING_YU, "type": GConst.HarmType.Magic,
		})
	if not use_cards.is_empty():
		engine.take_from_hand(player.id, use_cards)
		engine.to_discard(use_cards)
	if mode == 1:
		engine._broadcast_game()
		return URGENT
	施加治疗(player.id, 2)
	施加治疗(dst.id, 1)
	engine._broadcast_game()
	return SUCCESS
