extends BattleRole
## 苍炎魔女（roleID 30）—— 移植自服务端 role/MoNv.cpp
## 形态：tap（【烈焰形态】）；指示物：【重生】(tokens[0]，上限 4)
## 技能：苍炎法典（3001，法术：弃 1 张火系牌，对目标角色和自己各造成 2 点法术伤害）、
##       天火断空（3002，法术：弃 2 张火系牌，非烈焰形态再移除 1 点【重生】，
##                 对目标角色和自己各造成 3（敌方士气更高时为 4）点法术伤害）、
##       魔女之怒（3003，启动：手牌 ≤ 3 时进入【烈焰形态】、摸 0~3 张牌并调整手牌上限；30031 为该形态下
##                 弃 1 张攻击牌、以虚拟【火焰斩】(87) 发起一次攻击）、
##       替身玩偶（3004，响应：受攻击伤害时弃 1 张法术牌，指定同队角色摸 1 张牌）、
##       永生银时计（3005，被动：因承受法术伤害掉士气时 +1【重生】）、
##       痛苦链接（3006，法术：耗 1 点能量，对目标对手和自己各 1 点法术伤害，然后弃到 3 张牌）、
##       魔能翻转（3007，响应：受法术伤害且能量 ≥ 1 时，弃 X（X>1）张法术牌对目标对手造成 X-1 点法术伤害）
## 【烈焰形态】下除水系、暗系外的攻击牌视为火系（服务端 getCardElement / IsFired）。

const CANG_YAN_FA_DIAN: int = 3001
const TIAN_HUO_DUAN_KONG: int = 3002
const MO_NV_ZHI_NU: int = 3003
const MO_NV_ZHI_NU_ATTACK: int = 30031
const MO_NV_ZHI_NU_DRAW: int = 30032
const TI_SHEN_WAN_OU: int = 3004
const YONG_SHENG_YIN_SHI_JI: int = 3005
const TONG_KU_LIAN_JIE: int = 3006
const TONG_KU_LIAN_JIE_CARD: int = 30061
const MO_NENG_FAN_ZHUAN: int = 3007

## 服务端用以代替任意攻击牌的虚拟卡：火焰斩
const VIRTUAL_FIRE_SLASH: int = 87


## 魔女之怒本回合要摸的牌数（服务端 cardNum）
var mo_nv_zhi_nu_card_num: int = 0


func setup(p: BattlePlayer, e: BattleEngine) -> void:
	super.setup(p, e)
	p.tokens[0] = {"name": "重生", "max": 4, "num": 0}


func available_skills() -> Array:
	var out: Array = []
	if _fire_like_count() >= 1:
		# 苍炎法典只能弃视为火系的牌（v_magic_skill 的 _has_fire_like 校验同一条）
		out.append({"type": GConst.ActionType.MagicSkill, "id": CANG_YAN_FA_DIAN, "need_card": 1, "need_target": 1,
			"cards": hand_ids_where(func(cid: int, _c: GCard) -> bool: return _is_fire_like(cid))})
	if _fire_like_count() >= 2 and (player.tap or int(player.tokens[0]["num"]) >= 1):
		# 天火断空只能弃视为火系的牌（v_magic_skill 的 _has_fire_like 校验同一条）
		out.append({"type": GConst.ActionType.MagicSkill, "id": TIAN_HUO_DUAN_KONG, "need_card": 2, "need_target": 1,
			"cards": hand_ids_where(func(cid: int, _c: GCard) -> bool: return _is_fire_like(cid))})
	if player.get_energy() >= 1:
		# 痛苦链接：目标须为对手（v_magic_skill：dst.color == player.color 时返回 GE_INVALID_ACTION）
		out.append({"type": GConst.ActionType.MagicSkill, "id": TONG_KU_LIAN_JIE, "need_card": 0, "need_target": 1,
			"targets": enemy_ids()})
	# 服务端 v_attack_skill 未限制形态；该技能即【烈焰形态】下把攻击牌当作火系【火焰斩】打出
	if player.tap and not player.hand_cards.is_empty():
		# 只能弃攻击牌（v_attack_skill 校验同一条）
		# 目标须为对手（v_attack_skill：dst.color == player.color 时返回 GE_INVALID_PLAYERID）
		out.append({"type": GConst.ActionType.AttackSkill, "id": MO_NV_ZHI_NU_ATTACK, "need_card": 1, "need_target": 1,
			"cards": hand_ids_where(func(_cid: int, c: GCard) -> bool: return c.is_attack()),
			"targets": enemy_ids()})
	return out


## 烈焰形态下，除水系、暗系外的攻击牌均视为火系（服务端 getCardElement）
func _is_fire_like(card_id: int) -> bool:
	var card: GCard = Data.get_card(card_id)
	if card == null:
		return false
	var element: int = card.element_enum()
	if element == GConst.CardElement.Fire:
		return true
	if player.tap and card.is_attack():
		return element != GConst.CardElement.Water and element != GConst.CardElement.Darkness
	return false


## 手牌中视为火系的牌数
func _fire_like_count() -> int:
	var n: int = 0
	for cid: int in player.hand_cards:
		if _is_fire_like(cid):
			n += 1
	return n


# ============================================================
# 回合开始：离开【烈焰形态】（服务端 p_between_weak_and_action；引擎未调用该钩子，
# 故改在 p_turn_begin 执行，执行顺序仍在 p_boot 之前）
# ============================================================
func p_between_weak_and_action(_ctx: Dictionary) -> int:
	return _get_away_from_fire()


func p_turn_begin(_ctx: Dictionary) -> int:
	if engine.current_id != player.id:
		return SUCCESS
	return _get_away_from_fire()


func _get_away_from_fire() -> int:
	if not player.tap:
		return SUCCESS
	player.tap = false
	player.hand_cards_max += 2 - int(player.tokens[0]["num"])
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 启动：魔女之怒（手牌 ≤ 3 时进入【烈焰形态】、摸牌并调整手牌上限）
# ============================================================
func p_boot(_ctx: Dictionary) -> int:
	if engine.current_id != player.id or player.hand_cards.size() > 3:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if step == 0:
		step = MO_NV_ZHI_NU
	if step == MO_NV_ZHI_NU:
		if not engine.has_reply():
			engine.ask_skill(player.id, MO_NV_ZHI_NU, 0, 0)
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		var args: Array = r.get("args", [])
		if args.is_empty() or int(args[0]) != 1:
			step = STEP_DONE
			return SUCCESS
		# 服务端 args(1) 为本回合摸牌数（>3 视为非法）
		var card_num: int = int(args[1]) if args.size() > 1 else 0
		mo_nv_zhi_nu_card_num = clampi(card_num, 0, 3)
		step = MO_NV_ZHI_NU_DRAW
	if step == MO_NV_ZHI_NU_DRAW:
		step = STEP_DONE
		notice_skill(MO_NV_ZHI_NU, [player.id])
		player.tap = true
		player.hand_cards_max += int(player.tokens[0]["num"]) - 2
		if mo_nv_zhi_nu_card_num > 0:
			engine.draw(player.id, mo_nv_zhi_nu_card_num)
			mo_nv_zhi_nu_card_num = 0
		engine._broadcast_game()
	return SUCCESS


# ============================================================
# 永生银时计：因承受法术伤害掉士气时 +1【重生】
# 服务端按 con->harm.type == TYPE_MAGIC 判定（MoNv::p_true_lose_morale）；
# 引擎 lose_morale 的 ctx 提供「type」（最近一次伤害的类型），故据此识别法术伤害。
# 注意：ctx["cause"] 恒为超限来源（CAUSE_OVERLOAD），不能用来判伤害，已改用 type。
# ============================================================
func p_true_lose_morale(ctx: Dictionary) -> int:
	if int(ctx.get("dst", -1)) != player.id:
		return SUCCESS
	if int(ctx.get("amount", 0)) < 1:
		return SUCCESS
	if int(ctx.get("type", -1)) != GConst.HarmType.Magic:
		return SUCCESS
	if int(player.tokens[0]["num"]) >= int(player.tokens[0]["max"]):
		return SUCCESS
	notice_skill(YONG_SHENG_YIN_SHI_JI, [player.id])
	player.tokens[0]["num"] = int(player.tokens[0]["num"]) + 1
	if player.tap:
		player.hand_cards_max += 1
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 承受伤害时：替身玩偶（攻击伤害）/ 魔能翻转（法术伤害）
# ============================================================
func p_timeline_3(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("dst", -1)) != player.id:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if int(harm.get("type", -1)) == GConst.HarmType.Attack:
		return _ti_shen_wan_ou(ctx)
	if int(harm.get("type", -1)) == GConst.HarmType.Magic:
		return _mo_neng_fan_zhuan(ctx)
	return SUCCESS


## 替身玩偶：弃 1 张法术牌，指定同队角色摸 1 张牌
func _ti_shen_wan_ou(ctx: Dictionary) -> int:
	if bool(ctx.get("mo_nv_tswo_done", false)):
		return SUCCESS
	if step == 0:
		step = TI_SHEN_WAN_OU
	if step != TI_SHEN_WAN_OU:
		return SUCCESS
	if not engine.has_reply():
		engine.ask_skill(player.id, TI_SHEN_WAN_OU, 1, 1)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	ctx["mo_nv_tswo_done"] = true
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		return SUCCESS
	var cards: Array = r.get("card_ids", [])
	var dsts: Array = r.get("dst_ids", [])
	if cards.is_empty():
		return SUCCESS
	var cid: int = int(cards[0])
	var card: GCard = Data.get_card(cid)
	if card == null or not card.is_magic() or not player.has_hand_card(cid):
		return SUCCESS
	var mate_id: int = int(dsts[0]) if not dsts.is_empty() else player.id
	var mate: BattlePlayer = engine.p(mate_id)
	if mate == null or mate.color != player.color:
		return SUCCESS
	notice_skill(TI_SHEN_WAN_OU, [mate_id])
	engine.draw(mate_id, 1)
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": [cid], "is_real": true,
	})
	engine.take_from_hand(player.id, [cid])
	engine.to_discard([cid])
	engine._broadcast_game()
	return SUCCESS


## 魔能翻转：弃 X（X>1）张法术牌，对目标对手造成 X-1 点法术伤害
func _mo_neng_fan_zhuan(ctx: Dictionary) -> int:
	if bool(ctx.get("mo_nv_mnfz_done", false)):
		return SUCCESS
	if player.get_energy() < 1:
		return SUCCESS
	if step == 0:
		step = MO_NENG_FAN_ZHUAN
	if step != MO_NENG_FAN_ZHUAN:
		return SUCCESS
	if not engine.has_reply():
		# 弃 X 张法术牌（X≥2）：上限放到法术牌张数，并让客户端只让法术牌可点
		var 法术牌: Array = []
		for cid: int in player.hand_cards:
			var c: GCard = Data.get_card(cid)
			if c != null and c.is_magic():
				法术牌.append(cid)
		engine.ask_skill(player.id, MO_NENG_FAN_ZHUAN, 2, 1, GConst.CardSource.Hand, [], 法术牌.size(), "", 法术牌)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	ctx["mo_nv_mnfz_done"] = true
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		return SUCCESS
	var cards: Array = r.get("card_ids", [])
	var dsts: Array = r.get("dst_ids", [])
	if cards.size() < 2 or dsts.is_empty():
		return SUCCESS
	var use: Array = []
	for c: Variant in cards:
		var cid: int = int(c)
		var card: GCard = Data.get_card(cid)
		if card == null or not card.is_magic() or not player.has_hand_card(cid):
			return SUCCESS
		use.append(cid)
	var enemy_id: int = int(dsts[0])
	var enemy: BattlePlayer = engine.p(enemy_id)
	if enemy == null or enemy.color == player.color:
		return SUCCESS
	notice_skill(MO_NENG_FAN_ZHUAN, [enemy_id])
	if player.crystal > 0:
		player.set_crystal(player.crystal - 1)
	else:
		player.set_gem(player.gem - 1)
	engine.push_harm({
		"src": player.id, "dst": enemy_id, "point": use.size() - 1,
		"cause": MO_NENG_FAN_ZHUAN, "type": GConst.HarmType.Magic,
	})
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": use, "is_real": true,
	})
	engine.take_from_hand(player.id, use)
	engine.to_discard(use)
	engine._broadcast_game()
	return URGENT


# ============================================================
# 应战校验（服务端 v_reattack）：整体替换通用实现
# 差别一：【烈焰形态】下除水系、暗系外的攻击牌视为火系（服务端 getCardElement），可应战火系攻击；
# 差别二：服务端对暗系起源牌返回 GE_INVALID_CARDID（通用实现返回 GE_INVALID_ACTION）。
# 未移植：服务端签名中的 rate != RATE_NORMAL 判定与 dstID / orignID 校验，本引擎签名无法表达。
# ============================================================
func v_reattack(card_id: int, attack_card_id: int) -> int:
	if not player.has_hand_card(card_id):
		return GConst.GE_HANDCARD_NOT_FOUND
	var card: GCard = Data.get_card(card_id)
	var atk: GCard = Data.get_card(attack_card_id)
	if card == null or atk == null or not card.is_attack():
		return GConst.GE_INVALID_CARDID
	if atk.element_enum() == GConst.CardElement.Darkness:
		return GConst.GE_INVALID_CARDID
	if card.element_enum() != GConst.CardElement.Darkness:
		# 实际系别：烈焰形态下除水系、暗系外的攻击牌视为火系（服务端 getCardElement）
		var effect_element: int = GConst.CardElement.Fire if _is_fire_like(card_id) else card.element_enum()
		if effect_element != atk.element_enum():
			return GConst.GE_INVALID_CARDID
	return GConst.GE_SUCCESS


# ============================================================
# 主动法术技能
# ============================================================
func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	var aid: int = int(action.get("action_id", 0))
	var cards: Array = action.get("card_ids", [])
	if aid == CANG_YAN_FA_DIAN:
		if cards.size() != 1 or not _has_fire_like(cards):
			return GConst.GE_INVALID_ACTION
		return GConst.GE_SUCCESS
	if aid == TIAN_HUO_DUAN_KONG:
		if cards.size() != 2 or not _has_fire_like(cards):
			return GConst.GE_INVALID_ACTION
		if not player.tap and int(player.tokens[0]["num"]) < 1:
			return GConst.GE_INVALID_ACTION
		return GConst.GE_SUCCESS
	if aid == TONG_KU_LIAN_JIE:
		if player.get_energy() < 1:
			return GConst.GE_INVALID_ACTION
		var dsts: Array = action.get("dst_ids", [])
		var dst: BattlePlayer = engine.p(int(dsts[0]) if not dsts.is_empty() else player.id)
		if dst == null or dst.color == player.color:
			return GConst.GE_INVALID_ACTION
		return GConst.GE_SUCCESS
	return GConst.GE_INVALID_ACTION


## 给定牌是否都在手牌中且被视为火系
func _has_fire_like(cards: Array) -> bool:
	for c: Variant in cards:
		var cid: int = int(c)
		if not player.has_hand_card(cid) or not _is_fire_like(cid):
			return false
	return true


func p_magic_skill(action: Dictionary) -> int:
	match int(action.get("action_id", 0)):
		CANG_YAN_FA_DIAN:
			return _cang_yan_fa_dian(action)
		TIAN_HUO_DUAN_KONG:
			return _tian_huo_duan_kong(action)
		TONG_KU_LIAN_JIE:
			return _tong_ku_lian_jie(action)
	return GConst.GE_INVALID_ACTION


## 苍炎法典：弃 1 张火系牌，对目标角色和自己各造成 2 点法术伤害
func _cang_yan_fa_dian(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	var cid: int = int(cards[0])
	var dst_id: int = int(dsts[0]) if not dsts.is_empty() else player.id
	notice_skill(CANG_YAN_FA_DIAN, [dst_id])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": [cid], "is_real": true,
	})
	engine.push_harm({
		"src": player.id, "dst": player.id, "point": 2,
		"cause": CANG_YAN_FA_DIAN, "type": GConst.HarmType.Magic,
	})
	engine.push_harm({
		"src": player.id, "dst": dst_id, "point": 2,
		"cause": CANG_YAN_FA_DIAN, "type": GConst.HarmType.Magic,
	})
	engine.take_from_hand(player.id, [cid])
	engine.to_discard([cid])
	engine._broadcast_game()
	return URGENT


## 天火断空：弃 2 张火系牌（非烈焰形态额外 -1【重生】），对目标角色和自己各造成伤害
func _tian_huo_duan_kong(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	var cid_list: Array = [int(cards[0]), int(cards[1])]
	var dst_id: int = int(dsts[0]) if not dsts.is_empty() else player.id
	notice_skill(TIAN_HUO_DUAN_KONG, [dst_id])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": cid_list, "is_real": true,
	})
	if not player.tap:
		player.tokens[0]["num"] = maxi(int(player.tokens[0]["num"]) - 1, 0)
	var harm_point: int = 3
	var dst: BattlePlayer = engine.p(dst_id)
	if dst != null and engine.team_morale[dst.color] > engine.team_morale[player.color]:
		harm_point = 4
	engine.push_harm({
		"src": player.id, "dst": player.id, "point": harm_point,
		"cause": TIAN_HUO_DUAN_KONG, "type": GConst.HarmType.Magic,
	})
	engine.push_harm({
		"src": player.id, "dst": dst_id, "point": harm_point,
		"cause": TIAN_HUO_DUAN_KONG, "type": GConst.HarmType.Magic,
	})
	engine.take_from_hand(player.id, cid_list)
	engine.to_discard(cid_list)
	engine._broadcast_game()
	return URGENT


## 痛苦链接：耗 1 点能量，对目标对手和自己各 1 点法术伤害，然后弃到 3 张牌（弃牌先结算）
func _tong_ku_lian_jie(action: Dictionary) -> int:
	var dsts: Array = action.get("dst_ids", [])
	var dst_id: int = int(dsts[0]) if not dsts.is_empty() else player.id
	if step == 0:
		step = TONG_KU_LIAN_JIE
		notice_skill(TONG_KU_LIAN_JIE, [dst_id])
		if player.crystal > 0:
			player.set_crystal(player.crystal - 1)
		else:
			player.set_gem(player.gem - 1)
		engine._broadcast_game()
		if player.hand_cards.size() >= 4:
			engine.ask_skill(player.id, TONG_KU_LIAN_JIE_CARD, 1, 0)
			return WAIT
	step = STEP_DONE
	var chosen: Array = []
	if engine.has_reply():
		var r: Dictionary = take_skill_reply_full()
		chosen = r.get("card_ids", [])
	_discard_down_to(3, chosen)
	engine.push_harm({
		"src": player.id, "dst": player.id, "point": 1,
		"cause": TONG_KU_LIAN_JIE, "type": GConst.HarmType.Magic,
	})
	engine.push_harm({
		"src": player.id, "dst": dst_id, "point": 1,
		"cause": TONG_KU_LIAN_JIE, "type": GConst.HarmType.Magic,
	})
	engine._broadcast_game()
	return URGENT


## 把手牌弃到 keep 张：优先使用客户端给出的牌，不足时自动补齐
func _discard_down_to(keep: int, chosen: Array) -> void:
	var over: int = player.hand_cards.size() - keep
	if over <= 0:
		return
	var use: Array = []
	for c: Variant in chosen:
		if use.size() < over and player.has_hand_card(int(c)) and not use.has(int(c)):
			use.append(int(c))
	for cid: int in player.hand_cards:
		if use.size() >= over:
			break
		if not use.has(cid):
			use.append(cid)
	engine.take_from_hand(player.id, use)
	engine.to_discard(use)


# ============================================================
# 攻击技能：魔女之怒（弃 1 张攻击牌，以虚拟【火焰斩】发起一次攻击）
# ============================================================
func v_attack_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != MO_NV_ZHI_NU_ATTACK:
		return GConst.GE_INVALID_ACTION
	var cards: Array = action.get("card_ids", [])
	if cards.is_empty():
		return GConst.GE_INVALID_CARDID
	var cid: int = int(cards[0])
	var card: GCard = Data.get_card(cid)
	# 服务端仅校验手牌；此处要求所弃之牌为攻击牌（本技能即把攻击牌当火系打出）
	if card == null or not player.has_hand_card(cid) or not card.is_attack():
		return GConst.GE_INVALID_CARDID
	var dsts: Array = action.get("dst_ids", [])
	var dst: BattlePlayer = engine.p(int(dsts[0]) if not dsts.is_empty() else player.id)
	if dst == null or dst.color == player.color:
		return GConst.GE_INVALID_PLAYERID
	return GConst.GE_SUCCESS


func p_attack_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != MO_NV_ZHI_NU_ATTACK:
		return GConst.GE_INVALID_ACTION
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	var cid: int = int(cards[0])
	var dst_id: int = int(dsts[0]) if not dsts.is_empty() else player.id
	notice_skill(MO_NV_ZHI_NU_ATTACK, [dst_id])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": [cid], "is_real": true,
	})
	engine.take_from_hand(player.id, [cid])
	engine.to_discard([cid])
	# 与 _do_attack 一致：以虚拟【火焰斩】(87) 进入完整攻击流程（应战 / 命中 / 各钩子）
	var harm: Dictionary = {
		"src": player.id, "dst": dst_id, "point": 2, "cause": GConst.CAUSE_ATTACK,
		"type": GConst.HarmType.Attack, "card_id": VIRTUAL_FIRE_SLASH, "is_active": true,
	}
	engine.push(BattleEngine.SAttackCard.new(player.id, dst_id, VIRTUAL_FIRE_SLASH, harm))
	engine.push_show_hand(player.id, [cid])
	engine._broadcast_game()
	return URGENT
