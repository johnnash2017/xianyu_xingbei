extends BattleRole
## 精灵射手（roleID 32）—— 移植自服务端 role/JingLingSheShou.cpp
## 形态：tap（【精灵祝福形态】）；盖牌：【祝福】(cover_cards_max = 3)
## 技能：元素射击（3201，响应・回合限定：主动攻击时若攻击牌非暗系，弃 1 张法术牌或移除 1 张【祝福】，
##                 按攻击牌系别附加元素箭：火 +1 伤害 / 地 命中后额外 1 点法术伤害 /
##                 风 攻击行动结束后额外 1 次攻击行动 / 雷 本次攻击无法应战 / 水 命中后目标 +1 治疗）、
##       动物伙伴（3202，响应：你对他人造成伤害结算后，指定一名角色弃 1 张牌并摸 1 张牌，
##                 目标非自己时需耗 1 点能量）、
##       精灵秘仪（3203，持续：耗 1 宝石并【横置】转为【精灵祝福形态】，牌库顶 3 张作为【祝福】；
##                 回合结束时若没有【祝福】则【重置】脱离该形态，并对目标角色造成 2 点法术伤害）

const YUAN_SU_SHE_JI: int = 3201
const YUAN_SU_SHE_JI_HIT: int = 32011
const DONG_WU_HUO_BAN: int = 3202
const DONG_WU_HUO_BAN_DISCARD: int = 32021
const JING_LING_MI_YI: int = 3203
const JING_LING_MI_YI_BOOT: int = 32031


## 元素箭待结算标记（命中后生效）
var shui_zhi_shi: bool = false
var di_zhi_shi: bool = false
## 本回合是否已发动元素射击
var used_yuan_su_she_ji: bool = false
## 动物伙伴指定的弃牌角色
var _dw_target: int = -1


func setup(p: BattlePlayer, e: BattleEngine) -> void:
	super.setup(p, e)
	p.cover_cards_max = 3


func p_before_turn_begin(_ctx: Dictionary) -> int:
	used_yuan_su_she_ji = false
	return SUCCESS


# ============================================================
# 启动：精灵秘仪（耗 1 宝石横置转为【精灵祝福形态】，牌库顶 3 张作为【祝福】）
# ============================================================
func p_boot(_ctx: Dictionary) -> int:
	if engine.current_id != player.id or player.gem == 0 or player.tap:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if step == 0:
		step = JING_LING_MI_YI_BOOT
	if step != JING_LING_MI_YI_BOOT:
		return SUCCESS
	if not engine.has_reply():
		询问(player.id, JING_LING_MI_YI_BOOT, 0, 0)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		return SUCCESS
	notice_skill(JING_LING_MI_YI_BOOT, [player.id])
	engine.set_tap(player.id, true)
	player.set_gem(player.gem - 1)
	# 牌库顶 3 张面朝下放置于角色旁作为【祝福】
	var cards: Array = engine.draw(player.id, 3)
	if not cards.is_empty():
		engine.take_from_hand(player.id, cards)
		engine.add_cover(player.id, cards, player.id, JING_LING_MI_YI_BOOT)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 回合结束：精灵秘仪（无【祝福】时脱离形态并对目标角色 2 点法术伤害）
# ============================================================
## 【精灵秘仪】的推进阶段（0＝还没开始 / JING_LING_MI_YI＝已脱形态、等目标回复）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而本流程一开场就脱形态
## （player.tap = false 会压入一轮 p_tap 钩子）—— 那一轮开始把 step 抹掉后，流程退回第 0 步，
## 入口条件（要有形态）此刻已不成立 → 2 点法术伤害整条不生效。每回合结束都可能触发，收尾清回 0
var _mi_yi_step: int = 0


func p_turn_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if _mi_yi_step >= STEP_DONE:
		return SUCCESS
	# 入口条件（处于形态、没有【祝福】）只在第 0 步判：本条流程一开场就把 player.tap 置回 false，
	# 之后重入（等回复回来时会再进一次本钩子）不能再用 tap 当门槛，否则伤害整条不生效
	if _mi_yi_step == 0:
		if not player.tap or player.cover_count() > 0:
			return SUCCESS
		_mi_yi_step = JING_LING_MI_YI
	if _mi_yi_step != JING_LING_MI_YI:
		return SUCCESS
	# 服务端先【重置】再询问目标；未提供目标时以自己为目标
	player.tap = false
	engine._broadcast_game()
	if not engine.has_reply():
		询问(player.id, JING_LING_MI_YI, 0, 1)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	_mi_yi_step = 0
	var dsts: Array = r.get("dst_ids", [])
	var dst_id: int = int(dsts[0]) if not dsts.is_empty() else player.id
	notice_skill(JING_LING_MI_YI, [dst_id])
	engine.push_harm({
		"src": player.id, "dst": dst_id, "point": 2,
		"cause": JING_LING_MI_YI, "type": GConst.HarmType.Magic,
	})
	engine._broadcast_game()
	return URGENT


# ============================================================
# 主动攻击宣告时：元素射击（弃 1 张法术牌或移除 1 张【祝福】，按攻击牌系别附加元素箭）
# ============================================================
func p_timeline_1(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id or not bool(ctx.get("is_active", false)):
		return SUCCESS
	if used_yuan_su_she_ji:
		return SUCCESS
	var atk: GCard = Data.get_card(int(ctx.get("card_id", -1)))
	if atk == null or atk.element_enum() == GConst.CardElement.Darkness:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if step == 0:
		step = YUAN_SU_SHE_JI
	if step != YUAN_SU_SHE_JI:
		return SUCCESS
	if not engine.has_reply():
		# 选项 1 只能弃法术手牌、选项 2 只能移除【祝福】盖牌：两者合成白名单下发，
		# 界面就把攻击牌等其余手牌置灰（选项由玩家随后在指令条点，服务端再按选项最终校验）
		var 可弃: Array[int] = magic_hand_ids()
		可弃.append_array(player.cover_cards)
		询问(player.id, YUAN_SU_SHE_JI, 1, 0, GConst.CardSource.HandOrCover, [
			{"value": 1, "label": "弃 1 张手牌法术牌"},
			{"value": 2, "label": "移除 1 张【祝福】盖牌"},
		], 0, "", 可弃)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	var args: Array = r.get("args", [])
	# 服务端 1 = 使用手牌法术牌，2 = 移除【祝福】
	var choice: int = int(args[0]) if not args.is_empty() else 0
	if choice != 1 and choice != 2:
		return SUCCESS
	var cards: Array = r.get("card_ids", [])
	if cards.is_empty():
		return SUCCESS
	var cid: int = int(cards[0])
	if choice == 1:
		var card: GCard = Data.get_card(cid)
		if card == null or not card.is_magic() or not player.has_hand_card(cid):
			return SUCCESS
	else:
		if not player.cover_cards.has(cid):
			return SUCCESS
	notice_skill(YUAN_SU_SHE_JI, [int(ctx.get("dst", -1))])
	used_yuan_su_she_ji = true
	var harm: Dictionary = ctx.get("harm", {})
	match atk.element_enum():
		GConst.CardElement.Fire:
			harm["point"] = int(harm.get("point", 0)) + 1
		GConst.CardElement.Earth:
			di_zhi_shi = true
		GConst.CardElement.Thunder:
			ctx["hit_rate"] = GConst.HitRate.NoReattack
		GConst.CardElement.Water:
			shui_zhi_shi = true
		GConst.CardElement.Wind:
			player.add_action(GConst.ActionType.Attack, YUAN_SU_SHE_JI, true)
		_:
			# 服务端 default：技能已发动并记录，但不结算弃牌
			engine._broadcast_game()
			return SUCCESS
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": [cid], "is_real": true,
	})
	if choice == 1:
		engine.take_from_hand(player.id, [cid], true)
	else:
		engine.remove_cover(player.id, [cid], player.id, YUAN_SU_SHE_JI)
	engine.to_discard([cid])
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 主动攻击命中后：元素箭（水之矢 +1 治疗 / 地之矢 1 点法术伤害）
# ============================================================
func p_timeline_2_hit(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id or not bool(ctx.get("is_active", false)):
		return SUCCESS
	if not shui_zhi_shi and not di_zhi_shi:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if step == 0:
		step = YUAN_SU_SHE_JI_HIT
	if step != YUAN_SU_SHE_JI_HIT:
		return SUCCESS
	if not engine.has_reply():
		询问(player.id, YUAN_SU_SHE_JI_HIT, 0, 1)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	var dsts: Array = r.get("dst_ids", [])
	var dst_id: int = int(dsts[0]) if not dsts.is_empty() else player.id
	if shui_zhi_shi:
		shui_zhi_shi = false
		notice_skill(YUAN_SU_SHE_JI_HIT, [dst_id])
		var dp: BattlePlayer = engine.p(dst_id)
		if dp != null:
			施加治疗(dp.id, 1)
		engine._broadcast_game()
		return SUCCESS
	di_zhi_shi = false
	notice_skill(YUAN_SU_SHE_JI_HIT, [dst_id])
	engine.push_harm({
		"src": player.id, "dst": dst_id, "point": 1,
		"cause": YUAN_SU_SHE_JI_HIT, "type": GConst.HarmType.Magic,
	})
	engine._broadcast_game()
	return URGENT


func p_timeline_2_miss(_ctx: Dictionary) -> int:
	shui_zhi_shi = false
	di_zhi_shi = false
	return SUCCESS


# ============================================================
# 造成伤害结算后：动物伙伴（指定角色弃 1 张牌并摸 1 张牌，目标非自己时耗 1 点能量）
# 服务端顺序：先摸 1 张，再由目标自己选 1 张弃掉（StateRequestHand，canGiveUp = false）
# ============================================================
## 【动物伙伴】的推进阶段（0＝还没问 / DONG_WU_HUO_BAN＝等「选谁」/ DONG_WU_HUO_BAN_DISCARD＝等目标弃牌）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨两次询问，
## 中间还给目标摸 1 张牌（会压入一轮手牌钩子）—— 那一轮开始时 step 被抹掉，流程退回第 0 步，
## 于是把目标弃牌的回复当成「选谁」的回复解析。每次造成伤害后都可能触发，收尾清回 0
var _dw_step: int = 0


func p_timeline_6_drawn(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("src", -1)) != player.id or engine.current_id != player.id:
		return SUCCESS
	if _dw_step >= STEP_DONE:
		return SUCCESS
	if _dw_step == 0:
		_dw_step = DONG_WU_HUO_BAN
	if _dw_step == DONG_WU_HUO_BAN:
		if not engine.has_reply():
			# 序号 1：第 0 条提示是「叫别人交牌」用的，这步「选谁」读第 1 条
			询问(player.id, DONG_WU_HUO_BAN, 0, 1, GConst.CardSource.Hand, [], 0, "", [], true, 1)
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		var args: Array = r.get("args", [])
		if args.is_empty() or int(args[0]) != 1:
			_dw_step = 0
			return SUCCESS
		var dsts: Array = r.get("dst_ids", [])
		var dst_id: int = int(dsts[0]) if not dsts.is_empty() else player.id
		if dst_id != player.id:
			if player.crystal > 0:
				player.set_crystal(player.crystal - 1)
			else:
				player.set_gem(player.gem - 1)
		notice_skill(DONG_WU_HUO_BAN, [dst_id])
		engine.draw(dst_id, 1)
		engine._broadcast_game()
		_dw_target = dst_id
		_dw_step = DONG_WU_HUO_BAN_DISCARD
	if _dw_step == DONG_WU_HUO_BAN_DISCARD:
		var t: BattlePlayer = engine.p(_dw_target)
		if t == null or t.hand_cards.is_empty():
			_dw_step = 0
			return SUCCESS
		if not engine.has_reply():
			询问(t.id, DONG_WU_HUO_BAN, 1)
			return WAIT
		_dw_step = 0
		var r2: Dictionary = take_skill_reply_full()
		var cid: int = _hand_card_of(t, r2.get("card_ids", []))
		if cid < 0:
			# 取消/超时：服务端 canGiveUp = false，必须交出，故自动取首张
			cid = int(t.hand_cards[0])
		engine.take_from_hand(t.id, [cid])
		engine.to_discard([cid])
		engine._broadcast_game()
	return SUCCESS


## 取回复中第一张目标手里真实存在的手牌（无则 -1）
func _hand_card_of(t: BattlePlayer, ids: Array) -> int:
	for c: Variant in ids:
		if t.has_hand_card(int(c)):
			return int(c)
	return -1
