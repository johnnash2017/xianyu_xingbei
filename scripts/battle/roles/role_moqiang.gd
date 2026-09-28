extends BattleRole
## 魔枪（roleID 29）—— 移植自服务端 role/MoQiang.cpp
## 形态：tap = [幻影形态]（暗之解放进入，幻影星辰解除；形态下手牌上限恒定为 5，解除后恢复 6）
## 技能：暗之解放（2901，启动：转[幻影形态]，本回合下次主动攻击伤害 +2；
##                 不能发动漆黑之枪和充盈）、
##       幻影星辰（2902，启动：仅[幻影形态]下，对自身 2 点法术伤害并脱离[幻影形态]；
##                 若没有因此造成士气下降，则对目标角色 2 点法术伤害）、
##       黑暗束缚（2903，被动：始终不能使用法术牌，由 v_missile/v_shield/v_weaken 覆写实现；
##                 圣光格挡与反魔弹由 v_block/v_remissile 覆写实现）、
##       暗之障壁（2904，响应：任何人对你造成伤害时，弃 X 张法术牌或雷系牌[展示]）、
##       充盈（2905，法术：弃 1 张法术牌或雷系牌[展示]，所有人各弃 1 张牌，
##             除你以外每有人弃法术牌或雷系牌则本回合下次主动攻击伤害 +1，额外 +1 攻击行动）、
##       漆黑之枪（2906，响应：仅[幻影形态]下，主动攻击命中手牌 1~2 的对手后，
##                 耗 X 能量，本次攻击伤害 +(X+2)）

const AN_ZHI_JIE_FANG: int = 2901
const HUAN_YING_XING_CHEN: int = 2902
const HUAN_YING_XING_CHEN_EFFECT: int = 29021
const HEI_AN_SHU_FU: int = 2903
const AN_ZHI_ZHANG_BI: int = 2904
const CHONG_YING: int = 2905
const CHONG_YING_DISCARD: int = 29051
const QI_HEI_ZHI_QIANG: int = 2906

const HAND_MAX_ILLUSION: int = 5
const HAND_MAX_NORMAL: int = 6

var card_count: int = 0
var hurt_id: int = -1
var using_an_zhi_jie_fang: bool = false
var using_huan_ying_xing_chen: bool = false
var availabel_qi_hei_zhi_qiang: bool = true
var availabel_chong_ying: bool = true
var used_chong_ying: bool = false
var used_an_zhi_jie_fang: bool = false
## 幻影星辰本次自伤是否已造成士气下降（服务端 p_true_lose_morale 置位 HuanYingXingChenEffectFlag：
## 置位则不再对目标追加 2 点法术伤害）；引擎 lose_morale 的 ctx 提供 harm_cause，故按该字段判定
var huan_ying_morale_lost: bool = false
## 充盈询问目标与游标（跨 WAIT 重入保留）
var _chong_targets: Array[int] = []
var _chong_index: int = 0


func p_before_turn_begin(_ctx: Dictionary) -> int:
	card_count = 0
	using_an_zhi_jie_fang = false
	using_huan_ying_xing_chen = false
	availabel_qi_hei_zhi_qiang = true
	availabel_chong_ying = true
	used_chong_ying = false
	used_an_zhi_jie_fang = false
	huan_ying_morale_lost = false
	hurt_id = -1
	return SUCCESS


func available_skills() -> Array:
	var out: Array = []
	# 黑暗束缚：始终不能使用法术牌（由 v_missile/v_shield/v_weaken 覆写实现）
	# 暗之解放后本回合不能发动充盈
	if availabel_chong_ying and (_hand_has_thunder() or _hand_has_magic()):
		out.append({"type": GConst.ActionType.MagicSkill, "id": CHONG_YING, "need_card": 1, "need_target": 0})
	return out


# ============================================================
# 牌类校验覆写（对照服务端 MoQiang.cpp）
# 【黑暗束缚】（2903）：始终不能使用法术牌，服务端恒返回 GE_INVALID_CARDID——
#   v_missile / v_shield / v_weaken 禁止使用魔弹/圣盾/虚弱；v_block / v_remissile 禁止圣光格挡与反魔弹。
# 充盈（2905）属法术技能（走 v_magic_skill），不受上述限制。
# 说明：服务端未覆写中毒等其他法术牌的校验路径，故本引擎同样不拦截。
# ============================================================
func v_missile(_card_id: int, _dst_id: int) -> int:
	return GConst.GE_INVALID_CARDID


func v_shield(_dst_id: int, _players: Dictionary) -> int:
	return GConst.GE_INVALID_CARDID


func v_weaken(_dst_id: int, _players: Dictionary) -> int:
	return GConst.GE_INVALID_CARDID


## 不能使用【圣光】格挡
func v_block(_card_id: int) -> int:
	return GConst.GE_INVALID_CARDID


## 不能响应【魔弹】（转弹）
func v_remissile(_card_id: int) -> int:
	return GConst.GE_INVALID_CARDID


# ============================================================
# 启动：暗之解放（2901）/ 幻影星辰（2902）
# ============================================================
func p_boot(_ctx: Dictionary) -> int:
	if engine.current_id != player.id:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if step == 0:
		step = HUAN_YING_XING_CHEN if player.tap else AN_ZHI_JIE_FANG
	if step == AN_ZHI_JIE_FANG or step == HUAN_YING_XING_CHEN:
		return _an_zhi_huan_ying()
	if step == HUAN_YING_XING_CHEN_EFFECT:
		return _huan_ying_xing_chen_effect()
	return SUCCESS


## 服务端 AnZhiHuanYing：按当前形态询问暗之解放或幻影星辰
func _an_zhi_huan_ying() -> int:
	var need_target: int = 1 if player.tap else 0
	var skill_id: int = HUAN_YING_XING_CHEN if player.tap else AN_ZHI_JIE_FANG
	if not engine.has_reply():
		engine.ask_skill(player.id, skill_id, 0, need_target)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	var choice: int = int(args[0]) if not args.is_empty() else 0
	if choice == 1:
		# 暗之解放：转[幻影形态]，手牌上限 5；本回合下次主动攻击 +2，禁用漆黑之枪与充盈
		notice_skill(AN_ZHI_JIE_FANG, [player.id])
		using_an_zhi_jie_fang = true
		availabel_qi_hei_zhi_qiang = false
		availabel_chong_ying = false
		player.tap = true
		player.hand_cards_max = HAND_MAX_ILLUSION
		step = STEP_DONE
		engine._broadcast_game()
		return SUCCESS
	if choice == 2:
		# 幻影星辰：对自身 2 点法术伤害并脱离[幻影形态]
		var dsts: Array = r.get("dst_ids", [])
		if dsts.is_empty():
			step = STEP_DONE
			return SUCCESS
		notice_skill(HUAN_YING_XING_CHEN, [int(dsts[0])])
		hurt_id = int(dsts[0])
		using_huan_ying_xing_chen = true
		huan_ying_morale_lost = false
		step = HUAN_YING_XING_CHEN_EFFECT
		engine.push_harm({
			"src": player.id, "dst": player.id, "point": 2,
			"cause": HUAN_YING_XING_CHEN, "type": GConst.HarmType.Magic,
		})
		engine._broadcast_game()
		return URGENT
	step = STEP_DONE
	return SUCCESS


## 幻影星辰：因该技能自伤造成士气下降时置位（服务端 MoQiang::p_true_lose_morale）
## 引擎 lose_morale 的 ctx 提供「harm_cause」（最近一次伤害的 cause），据此识别本次自伤
func p_true_lose_morale(ctx: Dictionary) -> int:
	if int(ctx.get("dst", -1)) != player.id:
		return SUCCESS
	if int(ctx.get("amount", 0)) < 1:
		return SUCCESS
	if not using_huan_ying_xing_chen:
		return SUCCESS
	if int(ctx.get("harm_cause", 0)) != HUAN_YING_XING_CHEN:
		return SUCCESS
	huan_ying_morale_lost = true
	return SUCCESS


## 服务端 HuanYingXingChen_Effect：脱离形态；若自伤未造成士气下降则对目标 2 点法术伤害
func _huan_ying_xing_chen_effect() -> int:
	player.tap = false
	using_huan_ying_xing_chen = false
	player.hand_cards_max = HAND_MAX_NORMAL
	var morale_lost: bool = huan_ying_morale_lost
	huan_ying_morale_lost = false
	step = STEP_DONE
	engine._broadcast_game()
	if morale_lost or hurt_id < 0:
		return SUCCESS
	var dst_id: int = hurt_id
	hurt_id = -1
	engine.push_harm({
		"src": player.id, "dst": dst_id, "point": 2,
		"cause": HUAN_YING_XING_CHEN, "type": GConst.HarmType.Magic,
	})
	engine._broadcast_game()
	return URGENT


# ============================================================
# 主动攻击命中后：暗之解放 +2 伤害（2901）→ 充盈加伤（2905）→ 漆黑之枪（2906）
# ============================================================
func p_timeline_2_hit(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("src", -1)) != player.id:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if step == 0:
		step = AN_ZHI_JIE_FANG
	if step == AN_ZHI_JIE_FANG:
		_an_zhi_jie_fang_effect(ctx)
		step = CHONG_YING
	if step == CHONG_YING:
		_chong_ying_add_harm(ctx)
		step = QI_HEI_ZHI_QIANG
	if step == QI_HEI_ZHI_QIANG:
		return _qi_hei_zhi_qiang(ctx)
	return SUCCESS


## 暗之解放：仅[幻影形态]下本回合首次主动攻击伤害 +2
func _an_zhi_jie_fang_effect(ctx: Dictionary) -> void:
	if not using_an_zhi_jie_fang or used_an_zhi_jie_fang:
		return
	if not bool(ctx.get("is_active", false)):
		return
	var harm: Dictionary = ctx["harm"]
	notice_skill(AN_ZHI_JIE_FANG, [int(harm.get("dst", -1))])
	harm["point"] = int(harm.get("point", 0)) + 2
	used_an_zhi_jie_fang = true


## 充盈加伤：本回合下次主动攻击伤害 +（其他角色弃掉的雷系/法术牌数）
func _chong_ying_add_harm(ctx: Dictionary) -> void:
	if not used_chong_ying or using_an_zhi_jie_fang:
		return
	if not bool(ctx.get("is_active", false)):
		return
	var harm: Dictionary = ctx["harm"]
	harm["point"] = int(harm.get("point", 0)) + card_count
	card_count = 0


## 漆黑之枪：仅[幻影形态]下，耗 X 能量，本次伤害 +(X+2)
func _qi_hei_zhi_qiang(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx["harm"]
	var dst_p: BattlePlayer = engine.p(int(harm.get("dst", -1)))
	if dst_p == null or not availabel_qi_hei_zhi_qiang:
		step = STEP_DONE
		return SUCCESS
	if dst_p.hand_cards.size() < 1 or dst_p.hand_cards.size() > 2:
		step = STEP_DONE
		return SUCCESS
	if not bool(ctx.get("is_active", false)) or using_an_zhi_jie_fang:
		step = STEP_DONE
		return SUCCESS
	if not player.tap or player.get_energy() == 0:
		step = STEP_DONE
		return SUCCESS
	if not engine.has_reply():
		engine.ask_skill(player.id, QI_HEI_ZHI_QIANG, 0, 0)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		return SUCCESS
	var use: int = int(args[1]) if args.size() > 1 else 0
	use = clampi(use, 0, player.get_energy())
	for _i: int in range(use):
		if player.crystal > 0:
			player.set_crystal(player.crystal - 1)
		else:
			player.set_gem(player.gem - 1)
	notice_skill(QI_HEI_ZHI_QIANG, [dst_p.id])
	harm["point"] = int(harm.get("point", 0)) + use + 2
	engine._broadcast_game()
	return SUCCESS


func p_timeline_2_miss(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id or not bool(ctx.get("is_active", false)):
		return SUCCESS
	if used_chong_ying:
		card_count = 0
	used_an_zhi_jie_fang = true
	return SUCCESS


# ============================================================
# 受到伤害时：暗之障壁（2904，弃 X 张法术牌或雷系牌）
# ============================================================
func p_timeline_3(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("dst", -1)) != player.id:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if not engine.has_reply():
		engine.ask_skill(player.id, AN_ZHI_ZHANG_BI, 1, 0)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		return SUCCESS
	var cards: Array = r.get("card_ids", [])
	var chosen: Array = []
	for c: Variant in cards:
		var cid: int = int(c)
		if not player.has_hand_card(cid):
			continue
		var card: GCard = Data.get_card(cid)
		if card != null and (card.element_enum() == GConst.CardElement.Thunder or card.is_magic()):
			chosen.append(cid)
	if chosen.is_empty():
		return SUCCESS
	notice_skill(AN_ZHI_ZHANG_BI, [player.id])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": chosen, "is_real": true,
	})
	engine.take_from_hand(player.id, chosen)
	engine.to_discard(chosen)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 幻影星辰自伤结算：手牌为 0 时，治疗最多只能使用 1 点
# （服务端 crossAvailable 为可抵御点数；本引擎用 harm["cross_max_point"] 限制本次可抵御点数）
# ============================================================
func p_timeline_4(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("dst", -1)) != player.id:
		return SUCCESS
	if int(harm.get("cause", -1)) != HUAN_YING_XING_CHEN:
		return SUCCESS
	if int(harm.get("cross_available", 1)) <= 0:
		return SUCCESS
	if not player.hand_cards.is_empty() or player.cross_num <= 1:
		return SUCCESS
	harm["cross_max_point"] = 1
	return SUCCESS


# ============================================================
# 主动法术技能：充盈（2905）
# ============================================================
func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != CHONG_YING or not availabel_chong_ying:
		return GConst.GE_INVALID_ACTION
	var cards: Array = action.get("card_ids", [])
	if cards.is_empty():
		return GConst.GE_INVALID_CARDID
	if not player.has_hand_card(int(cards[0])):
		return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != CHONG_YING:
		return GConst.GE_INVALID_ACTION
	return _chong_ying(action)


## 充盈：弃 1 张法术牌或雷系牌，所有人各弃 1 张牌（敌方强制、我方可选），
## 除你以外每有人弃雷系/法术牌则本回合下次主动攻击 +1，额外 +1 攻击行动
func _chong_ying(action: Dictionary) -> int:
	if step == 0:
		var cards: Array = action.get("card_ids", [])
		var cid: int = int(cards[0])
		var card: GCard = Data.get_card(cid)
		# 服务端：既非法术牌也非雷系牌则不发动的落空分支
		if card == null:
			return GConst.GE_INVALID_ACTION
		notice_skill(CHONG_YING, [player.id])
		engine.broadcast(GConst.Msg.Card, {
			"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
			"card_ids": [cid], "is_real": true,
		})
		engine.take_from_hand(player.id, [cid])
		engine.to_discard([cid])
		card_count = 0
		used_chong_ying = true
		_chong_targets = _all_ids_from_self()
		_chong_index = 0
		player.add_action(GConst.ActionType.Attack, CHONG_YING)
		engine._broadcast_game()
		step = 1
	if step == 1:
		while _chong_index < _chong_targets.size():
			var tid: int = _chong_targets[_chong_index]
			var tp: BattlePlayer = engine.p(tid)
			if tp == null:
				_chong_index += 1
				continue
			if not engine.has_reply():
				engine.ask_skill(tid, CHONG_YING_DISCARD, 1, 0)
				return WAIT
			var r: Dictionary = take_skill_reply_full()
			_chong_index += 1
			var cs: Array = r.get("card_ids", [])
			if cs.is_empty():
				continue
			var ccid: int = int(cs[0])
			if not tp.has_hand_card(ccid):
				continue
			var c2: GCard = Data.get_card(ccid)
			if c2 == null:
				continue
			var counted: bool = c2.is_magic() or c2.element_enum() == GConst.CardElement.Thunder
			notice_skill(CHONG_YING_DISCARD, [tid])
			engine.broadcast(GConst.Msg.Card, {
				"type": GConst.CardMsgType.Show, "src_id": tid, "dst_id": tid,
				"card_ids": [ccid], "is_real": true,
			})
			engine.take_from_hand(tid, [ccid])
			engine.to_discard([ccid])
			if counted and tid != player.id:
				card_count += 1
			engine._broadcast_game()
		step = STEP_DONE
	return SUCCESS


# ============================================================
# 工具
# ============================================================
func _hand_has_thunder() -> bool:
	for cid: int in player.hand_cards:
		var c: GCard = Data.get_card(cid)
		if c != null and c.element_enum() == GConst.CardElement.Thunder:
			return true
	return false


func _hand_has_magic() -> bool:
	for cid: int in player.hand_cards:
		var c: GCard = Data.get_card(cid)
		if c != null and c.is_magic():
			return true
	return false


## 自己以外、从下家开始按座位序的所有角色 id
func _other_ids_from_self() -> Array[int]:
	var ids: Array[int] = []
	var cur: int = player.post_id
	var guard: int = engine.order.size()
	while cur != player.id and guard > 0:
		ids.append(cur)
		cur = engine.next_id(cur)
		guard -= 1
	return ids


## 从下家开始按座位序绕回自己（充盈：所有人各弃 1 张，含自己）
func _all_ids_from_self() -> Array[int]:
	var ids: Array[int] = _other_ids_from_self()
	ids.append(player.id)
	return ids
