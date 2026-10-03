extends BattleRole
## 天使（roleID 7）—— 移植自服务端 role/TianShi.cpp
## 技能：
##   天使之墙（701，法术，将带此特技的牌作为基础效果放置于目标面前，视作圣盾）
##   天使祝福（702，法术，弃 1 张水系牌：指定 1 名角色→该角色交给你 2 张手牌；
##                 指定 2 名→各交 1 张。目标可以是天使自己，但那样等于把牌转一圈回自己手里，
##                 所以选自己时跳过「交牌」这一步）
##   风之洁净（703，法术，弃 1 张风系牌，移除场上任意一个基础效果）
##   天使羁绊（704，自身移除基础效果（703/705）或以【圣盾】/【天使之墙】放置基础效果时，
##                 为指定角色 +1 治疗；由 p_basic_effect_change 实现）
##   天使之歌（705，你的回合开始前，消耗 1 能量移除场上任意一个基础效果）
##   神之庇护（706，由 p_lose_morale 实现：我方角色因法术伤害将掉士气时，可消耗能量抵消等量损失。
##                 简化：客户端只支持「抵消几点」的选择，支付优先水晶再宝石）
##
## 覆写校验：v_shield——【天使之墙】视作圣盾（服务端 PlayerEntity::v_shield）

const TIAN_SHI_ZHI_QIANG: int = 701
const TIAN_SHI_ZHU_FU: int = 702
const FENG_ZHI_JIE_JING: int = 703
const TIAN_SHI_JI_BAN: int = 704
const TIAN_SHI_ZHI_GE: int = 705
const SHEN_ZHI_BI_HU: int = 706


func available_skills() -> Array:
	var out: Array = []
	# 风之洁净：只有风系手牌可作发动牌，下发给界面把其余手牌置灰（v_magic_skill 校验同一条）。
	# 选中目标按「确定」后，客户端把该目标身上的基础效果列出来供玩家选，选中的那张 id 作为 args[0] 回传
	# （见 CardSource.HandAndBasicEffect），所以合法目标是「面前有基础效果的玩家」；
	# 场上一个基础效果都没有时不给出该技能（v_magic_skill 要求 args[0] 是目标身上的基础效果牌）
	var 风系牌: Array[int] = hand_ids_where(func(_cid: int, c: GCard) -> bool: return c.element_enum() == GConst.CardElement.Wind)
	if not 风系牌.is_empty():
		var 有基础效果的目标: Array[int] = _有基础效果的目标()
		if not 有基础效果的目标.is_empty():
			out.append({"type": GConst.ActionType.MagicSkill, "id": FENG_ZHI_JIE_JING, "need_card": 1, "need_target": 1,
				"cards": 风系牌, "card_source": GConst.CardSource.HandAndBasicEffect, "targets": 有基础效果的目标})
	# 天使之墙：只有手中带【天使之墙】的牌可作发动牌（v_magic_skill 校验同一张牌）
	# 目标已有【圣盾】或【天使之墙】基础效果时服务端拒收（v_magic_skill + v_shield）。
	# 可以贴给自己（服务端不排除自己，原客户端也可选），故白名单含自己
	var 墙牌: Array[int] = hand_ids_with_skill(TIAN_SHI_ZHI_QIANG)
	if not 墙牌.is_empty():
		out.append({"type": GConst.ActionType.MagicSkill, "id": TIAN_SHI_ZHI_QIANG, "need_card": 1, "need_target": 1,
			"cards": 墙牌,
			"targets": player_ids_where(func(p: BattlePlayer) -> bool: return not p.check_basic_effect_name(GConst.CardName.Shield) and not p.check_basic_effect_skill(TIAN_SHI_ZHI_QIANG), true)})
	# 天使祝福：只有水系手牌可作发动牌（v_magic_skill 校验同一条）
	# 服务端允许 1~2 名目标（v_magic_skill：dsts.size() > 2 时拒收）
	var 水系牌: Array[int] = hand_ids_where(func(_cid: int, c: GCard) -> bool: return c.element_enum() == GConst.CardElement.Water)
	if not 水系牌.is_empty():
		out.append({"type": GConst.ActionType.MagicSkill, "id": TIAN_SHI_ZHU_FU, "need_card": 1, "need_target": 1,
			"target_max": 2, "cards": 水系牌})
	return out


# ============================================================
# 圣盾校验：【天使之墙】视作圣盾这一条已在通用实现里
# （battle_player.base_v_shield 同时判【圣盾】与技能 701【天使之墙】，对照服务端
#  PlayerEntity::v_shield），所以本角色不再覆写 v_shield。


# ============================================================
# 回合开始前：天使之歌（移除场上任意一个基础效果）
# ============================================================
## 询问回复约定（对照服务端 TianShi::TianShiZhiGe）：args[0] = 使用的能量（1=宝石 0=水晶）、
## args[1] = 要移除的基础效果牌，dst_ids[0] = 该基础效果的拥有者；args 少于 2 项或没选目标视为放弃。
## 交互与【风之洁净】一致：先选目标按「确定」，再由客户端弹出该目标身上的基础效果 + 消耗哪种能量供选。
func p_before_turn_begin(_ctx: Dictionary) -> int:
	if engine.current_id != player.id:
		return SUCCESS
	if player.get_energy() <= 0:
		return SUCCESS
	if not _any_player_has_basic_effect():
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if not engine.has_reply():
		询问(player.id, TIAN_SHI_ZHI_GE, 0, 1, GConst.CardSource.HandAndBasicEffect,
			[], 0, "", [], true, 0, -1, _有基础效果的目标())
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	var args: Array = r.get("args", [])
	var dsts: Array = r.get("dst_ids", [])
	if args.size() < 2 or dsts.is_empty():
		return SUCCESS
	var use_gem: int = int(args[0])
	var effect_cid: int = int(args[1])
	var dst_id: int = int(dsts[0])
	if use_gem > 0 and player.gem == 0:
		return SUCCESS
	if use_gem == 0 and player.crystal == 0:
		return SUCCESS
	var dst: BattlePlayer = engine.p(dst_id)
	if dst == null or not _has_basic_card(dst, effect_cid):
		return SUCCESS
	notice_skill(TIAN_SHI_ZHI_GE, [dst_id])
	if use_gem > 0:
		player.set_gem(player.gem - 1)
	else:
		player.set_crystal(player.crystal - 1)
	engine.remove_basic_effect(dst_id, effect_cid, TIAN_SHI_ZHI_GE, player.id)
	engine.to_discard([effect_cid])
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 天使羁绊（704）：基础效果发生增/删时，由 天使 指定一名角色 +1 治疗
# 对应服务端 TianShi::p_basic_effect_change——**发动者必须是天使本人**，且为
#   风之洁净（703）/ 天使之歌（705）移除，或以【圣盾】/【天使之墙】放置基础效果（CAUSE_USE）时触发。
# 注意：doer 判定要在最前面（与服务端一致），否则别的天使移除基础效果时全场天使都会跟着触发
# ============================================================
func p_basic_effect_change(ctx: Dictionary) -> int:
	if int(ctx.get("doer", -1)) != player.id:
		return SUCCESS
	var cause: int = int(ctx.get("cause", -1))
	if cause == FENG_ZHI_JIE_JING or cause == TIAN_SHI_ZHI_GE:
		return _tian_shi_ji_ban()
	if cause != GConst.CAUSE_USE or not bool(ctx.get("add", false)):
		return SUCCESS
	var card: GCard = Data.get_card(int(ctx.get("card", -1)))
	if card == null:
		return SUCCESS
	if not card.has_skill_id(TIAN_SHI_ZHI_QIANG) and card.card_name_enum() != GConst.CardName.Shield:
		return SUCCESS
	return _tian_shi_ji_ban()


## 天使羁绊结算：询问 天使 指定的一名角色，使其 +1 治疗（未选择目标时默认自己）
func _tian_shi_ji_ban() -> int:
	if not engine.has_reply():
		询问(player.id, TIAN_SHI_JI_BAN, 0, 1)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var dsts: Array = r.get("dst_ids", [])
	var dst_id: int = int(dsts[0]) if not dsts.is_empty() else player.id
	notice_skill(TIAN_SHI_JI_BAN, [dst_id])
	var dst: BattlePlayer = engine.p(dst_id)
	if dst != null:
		施加治疗(dst.id, 1)
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
		TIAN_SHI_ZHI_QIANG:
			if cards.is_empty() or dsts.is_empty():
				return GConst.GE_INVALID_CARDID
			var cid: int = int(cards[0])
			var card: GCard = Data.get_card(cid)
			if not player.has_hand_card(cid) or card == null or not card.has_skill_id(TIAN_SHI_ZHI_QIANG):
				return GConst.GE_INVALID_ACTION
			var dst: BattlePlayer = engine.p(int(dsts[0]))
			if dst == null:
				return GConst.GE_INVALID_PLAYERID
			if dst.check_basic_effect_name(GConst.CardName.Shield) or dst.check_basic_effect_skill(TIAN_SHI_ZHI_QIANG):
				return GConst.GE_INVALID_ACTION
		FENG_ZHI_JIE_JING:
			if cards.is_empty() or dsts.is_empty():
				return GConst.GE_INVALID_CARDID
			var cid2: int = int(cards[0])
			var card2: GCard = Data.get_card(cid2)
			if not player.has_hand_card(cid2) or card2 == null or card2.element_enum() != GConst.CardElement.Wind:
				return GConst.GE_INVALID_ACTION
			var args: Array = action.get("args", [])
			if args.is_empty():
				return GConst.GE_INVALID_ARGUMENT
			var dst2: BattlePlayer = engine.p(int(dsts[0]))
			if dst2 == null or not _has_basic_card(dst2, int(args[0])):
				return GConst.GE_INVALID_ACTION
		TIAN_SHI_ZHU_FU:
			if cards.is_empty() or dsts.is_empty() or dsts.size() > 2:
				return GConst.GE_INVALID_ACTION
			var cid3: int = int(cards[0])
			var card3: GCard = Data.get_card(cid3)
			if not player.has_hand_card(cid3) or card3 == null or card3.element_enum() != GConst.CardElement.Water:
				return GConst.GE_INVALID_ACTION
		_:
			return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	match int(action.get("action_id", 0)):
		TIAN_SHI_ZHI_QIANG:
			return _tian_shi_zhi_qiang(action)
		FENG_ZHI_JIE_JING:
			return _feng_zhi_jie_jing(action)
		TIAN_SHI_ZHU_FU:
			return _tian_shi_zhu_fu(action)
	return GConst.GE_INVALID_ACTION


## 天使之墙：将手牌移到目标的基础效果区（v_shield 已按【天使之墙】判定重复；
## 引擎的自动格挡路径也把【天使之墙】视作【圣盾】挡下，见文件头说明）
func _tian_shi_zhi_qiang(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	var cid: int = int(cards[0])
	var dst_id: int = int(dsts[0])
	notice_skill(TIAN_SHI_ZHI_QIANG, [dst_id])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": [cid], "is_real": true,
	})
	engine.take_from_hand(player.id, [cid])
	# 走引擎方法以触发 p_basic_effect_change（天使羁绊 704）；cause 与服务端一致为 CAUSE_USE
	engine.add_basic_effect(dst_id, cid, player.id, GConst.CAUSE_USE)
	engine._broadcast_game()
	return SUCCESS


## 风之洁净：弃 1 张风系牌，移除场上任意一个基础效果
func _feng_zhi_jie_jing(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	var args: Array = action.get("args", [])
	var cid: int = int(cards[0])
	var effect_cid: int = int(args[0])
	var dst: BattlePlayer = engine.p(int(dsts[0]))
	notice_skill(FENG_ZHI_JIE_JING, [dst.id])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": [cid], "is_real": true,
	})
	engine.remove_basic_effect(dst.id, effect_cid, FENG_ZHI_JIE_JING, player.id)
	engine.to_discard([effect_cid])
	engine.take_from_hand(player.id, [cid])
	engine.to_discard([cid])
	engine._broadcast_game()
	return SUCCESS


## 天使祝福：弃 1 张水系牌后，向 1~2 名指定角色各索取手牌（单目标 2 张 / 双目标各 1 张），
## 索得的牌进入天使手中。对应服务端 TianShi::TianShiZhuFu + StateRequestHand（去向 DECK_HAND）
## 说明：向目标索取手牌复用「需选牌」的技能询问（与兽灵武士等角色的请求手牌约定一致）；
##   目标是天使自己时跳过（自己给自己的牌还是自己的，问一遍只会让人看不懂）
func _tian_shi_zhu_fu(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	var 每人张数: int = 1 if dsts.size() > 1 else 2
	# 第一阶段：公告并弃掉发动用的水系牌
	if step == 0:
		step = TIAN_SHI_ZHU_FU
		notice_skill(TIAN_SHI_ZHU_FU, dsts)
		var use_cid: int = int(cards[0])
		engine.broadcast(GConst.Msg.Card, {
			"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
			"card_ids": [use_cid], "is_real": true,
		})
		engine.take_from_hand(player.id, [use_cid])
		engine.to_discard([use_cid])
		engine._broadcast_game()
	var idx: int = step - TIAN_SHI_ZHU_FU
	if idx >= dsts.size():
		step = STEP_DONE
		return SUCCESS
	var t: BattlePlayer = engine.p(int(dsts[idx]))
	# 目标无手牌：跳过；目标是自己也跳过 —— 自己给自己交牌，牌还是在自己手里（数量不变），
	# 问一遍只会让玩家看到「请选择 2 张手牌交给 天使[自己]」这种费解提示
	if t == null or t.id == player.id or t.hand_cards.is_empty():
		step += 1
		return _tian_shi_zhu_fu(action)
	if not engine.has_reply():
		# 由目标自己挑选要交出的牌（单目标 2 张 / 双目标各 1 张）；提示告诉他交给谁、几张
		询问(t.id, TIAN_SHI_ZHU_FU, mini(每人张数, t.hand_cards.size()))
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var want: int = mini(每人张数, t.hand_cards.size())
	var chosen: Array = _pick_cards(t, r.get("card_ids", []), want)
	# 交牌不公开亮牌：交/接双方在日志里看到具体牌名，其他人只看到张数（与水之神力给牌同一处理）
	engine._log_give_cards(t.id, player.id, chosen)
	engine.take_from_hand(t.id, chosen)
	player.add_hand_cards(chosen)
	engine._broadcast_game()
	step += 1
	return _tian_shi_zhu_fu(action)


# ============================================================
# 神之庇护（706，服务端 TianShi::p_lose_morale）
# 我方角色因法术伤害将掉士气时（在超限掉士气的可等待钩子轮次里），
# 可消耗能量抵消等量士气损失；宝石数与水晶数由玩家自己分配
# （对照服务端 respond->args(0)=宝石数、args(1)=水晶数）
# ============================================================
func p_lose_morale(ctx: Dictionary) -> int:
	var dst: BattlePlayer = engine.p(int(ctx.get("dst", -1)))
	if dst == null or dst.color != player.color:
		return SUCCESS
	# 仅「因法术伤害」掉士气时可发动（con->harm.type == HARM_MAGIC）
	if int(ctx.get("type", 0)) != GConst.HarmType.Magic:
		return SUCCESS
	var amount: int = int(ctx.get("amount", 0))
	if amount <= 0 or player.get_energy() <= 0:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if not engine.has_reply():
		# 本引擎一次只能回一个值，故把「宝石数 × 水晶数」编码进选项值（宝石*100 + 水晶）。
		# 客户端会把它们弹成居中的选项窗（含「不抵挡」那项：编码 0 → 下面判总能量 <= 0 直接放弃）
		var 上限: int = mini(amount, player.get_energy())
		var options: Array = [{"value": 0, "label": "不抵挡（保留星石）"}]
		for g: int in range(0, player.gem + 1):
			for c: int in range(0, player.crystal + 1):
				var 总: int = g + c
				if 总 <= 0 or 总 > 上限:
					continue
				options.append({"value": g * 100 + c, "label": "宝石 %d + 水晶 %d（抵消 %d 点）" % [g, c, 总]})
		询问(player.id, SHEN_ZHI_BI_HU, 0, 0, GConst.CardSource.Hand, options)
		return WAIT
	step = STEP_DONE
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	var 编码: int = int(args[0]) if not args.is_empty() else 0
	var 用宝石: int = 编码 / 100
	var 用水晶: int = 编码 % 100
	var 总能量: int = 用宝石 + 用水晶
	if 总能量 <= 0 or 用宝石 > player.gem or 用水晶 > player.crystal or 总能量 > amount:
		return SUCCESS
	notice_skill(SHEN_ZHI_BI_HU, [dst.id])
	player.set_gem(player.gem - 用宝石)
	player.set_crystal(player.crystal - 用水晶)
	ctx["amount"] = amount - 总能量
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 工具
# ============================================================
## 从回复的卡牌中挑出最多 n 张目标手牌里真实存在的牌；不足时用手牌补齐
## （目标取消/超时/掉线时不空转，与服务端 canGiveUp=false 的「必须交出」语义一致）
func _pick_cards(target: BattlePlayer, ids: Array, n: int) -> Array:
	var out: Array = []
	for c: Variant in ids:
		if out.size() >= n:
			break
		var cid: int = int(c)
		if target.has_hand_card(cid) and not out.has(cid):
			out.append(cid)
	for cid2: int in target.hand_cards:
		if out.size() >= n:
			break
		if not out.has(cid2):
			out.append(cid2)
	return out


## 目标是否拥有指定的基础效果牌
func _has_basic_card(target: BattlePlayer, cid: int) -> bool:
	for e: Dictionary in target.basic_effects:
		if int(e["card"]) == cid:
			return true
	return false


## 场上是否有任意基础效果
func _any_player_has_basic_effect() -> bool:
	for pid: int in engine.order:
		var p0: BattlePlayer = engine.p(pid)
		if p0 != null and not p0.basic_effects.is_empty():
			return true
	return false


## 面前有基础效果的玩家（含自己）：【风之洁净】与【天使之歌】的合法目标。
## 两者都允许移除自己面前的基础效果 —— 场上只有自己有基础效果时也得能选，故白名单含自己
func _有基础效果的目标() -> Array[int]:
	return player_ids_where(func(p: BattlePlayer) -> bool: return not p.basic_effects.is_empty(), true)
