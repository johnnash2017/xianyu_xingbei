extends BattleRole
## 巫女（roleID 23）—— 移植自服务端 role/WuNv.cpp
## 形态：tap（【流血形态】）叠加【同生共死】独有效果（放在目标身上，双方手牌上限联动）
## 技能：流血（2306，持续：因承受伤害导致我方士气下降时转为【流血形态】并 +1 治疗；
##             该形态下每次回合开始对自己造成 1 点法术伤害；手牌 < 3 时脱离形态）、
##       血之哀伤（2303，启动：对自己造成 2 点法术伤害，然后转移或移除【同生共死】）、
##       同生共死（2302，法术：摸 2 张牌并将【同生共死】放置于目标角色面前，
##                 普通形态双方手牌上限各 -2，流血形态各 +1）、
##       逆流（2304，法术：仅【流血形态】下，弃 2 张牌并 +1 治疗）、
##       血之悲鸣（2301，法术：对目标角色和自己各造成 1~3 点法术伤害）、
##       血之诅咒（2351，法术：耗 1 宝石，对目标角色造成 2 点法术伤害并弃最多 3 张牌）

const XUE_ZHI_BEI_MING: int = 2301
const TONG_SHENG_GONG_SI: int = 2302
const XUE_ZHI_AI_SHANG: int = 2303
const NI_LIU: int = 2304
const LIU_XUE: int = 2306
const XUE_ZHI_ZU_ZHOU: int = 2351

## 【同生共死】的目标（-1 表示未放置）
var tong_sheng_id: int = -1
## 血之哀伤：已选的分支（1=转移、2=移除）与转移目标；
## 先对自己造成 2 点法术伤害，伤害结算完由 p_after_special 落实转移 / 移除
var ai_shang_choose: int = 0
var ai_shang_dst: int = -1
## 本回合是否已在回合开始结算过流血伤害
var liu_xue_done: bool = false


func available_skills() -> Array:
	var out: Array = []
	if tong_sheng_id == -1:
		out.append({"type": GConst.ActionType.MagicSkill, "id": TONG_SHENG_GONG_SI, "need_card": 0, "need_target": 1})
	if player.tap and player.hand_cards.size() >= 2:
		# 逆流任意 2 张手牌都可弃，无牌类限制，故不下发 cards
		out.append({"type": GConst.ActionType.MagicSkill, "id": NI_LIU, "need_card": 2, "need_target": 0})
	var 悲鸣牌: Array[int] = hand_ids_with_skill(XUE_ZHI_BEI_MING)
	if not 悲鸣牌.is_empty():
		# 血之悲鸣只能弃带【血之悲鸣】特技的牌（v_magic_skill 校验同一条）；
		# v_magic_skill 允许 args[0] 取 1~3，执行体对目标与自己各造成该点数的法术伤害，
		# 故用 arg_choices 让玩家在选好牌与目标后选定伤害点数
		out.append({"type": GConst.ActionType.MagicSkill, "id": XUE_ZHI_BEI_MING, "need_card": 1, "need_target": 1,
			"cards": 悲鸣牌, "arg_choices": [
				{"text": "对目标与自身各造成 1 点法术伤害", "args": [1], "need_card": 1, "need_target": 1},
				{"text": "对目标与自身各造成 2 点法术伤害", "args": [2], "need_card": 1, "need_target": 1},
				{"text": "对目标与自身各造成 3 点法术伤害", "args": [3], "need_card": 1, "need_target": 1},
			]})
	if player.gem >= 1:
		out.append({"type": GConst.ActionType.MagicSkill, "id": XUE_ZHI_ZU_ZHOU, "need_card": 0, "need_target": 1})
	# 【血之哀伤】为「启动」：自己场上有【同生共死】时可发动（二选一：转移 / 移除）
	if tong_sheng_id != -1:
		out.append({"type": GConst.ActionType.SpecialSkill, "id": XUE_ZHI_AI_SHANG, "need_card": 0, "need_target": 1,
			"arg_choices": [
				{"text": "转移【同生共死】给选定目标", "args": [1], "need_card": 0, "need_target": 1},
				{"text": "移除【同生共死】", "args": [2], "need_card": 0, "need_target": 0},
			]})
	return out


func p_before_turn_begin(_ctx: Dictionary) -> int:
	ai_shang_choose = 0
	ai_shang_dst = -1
	liu_xue_done = false
	return SUCCESS


# ============================================================
# 回合开始：流血（流血形态下对自己造成 1 点法术伤害）
# ============================================================
func p_turn_begin(_ctx: Dictionary) -> int:
	if engine.current_id != player.id or not player.tap or liu_xue_done:
		return SUCCESS
	liu_xue_done = true
	notice_skill(LIU_XUE, [player.id])
	engine.push_harm({
		"src": player.id, "dst": player.id, "point": 1,
		"cause": LIU_XUE, "type": GConst.HarmType.Magic,
	})
	engine._broadcast_game()
	return URGENT


# ============================================================
# 启动：血之哀伤（技能栏按钮，自己场上有【同生共死】时可发动）
# 二选一（转移【同生共死】给选定目标 / 移除【同生共死】），随后对自己造成 2 点法术伤害
# ============================================================
func is_free_skill(skill_id: int) -> bool:
	return skill_id == XUE_ZHI_AI_SHANG


func v_special_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != XUE_ZHI_AI_SHANG:
		return GConst.GE_INVALID_ACTION
	if tong_sheng_id == -1:
		return GConst.GE_INVALID_ACTION
	var args: Array = action.get("args", [])
	var choice: int = int(args[0]) if not args.is_empty() else 0
	if choice != 1 and choice != 2:
		return GConst.GE_INVALID_ACTION
	if choice == 1:
		var dsts: Array = action.get("dst_ids", [])
		if dsts.is_empty():
			return GConst.GE_INVALID_ARGUMENT
		if engine.p(int(dsts[0])) == null:
			return GConst.GE_INVALID_PLAYERID
	return GConst.GE_SUCCESS


## 血之哀伤：记下所选分支与转移目标，先对自己造成 2 点法术伤害；
## 伤害结算完由 p_after_special 落实转移 / 移除（与服务端「先伤害、后动【同生共死】」顺序一致）
func p_special_skill(action: Dictionary) -> int:
	var args: Array = action.get("args", [])
	ai_shang_choose = int(args[0])
	ai_shang_dst = -1
	if ai_shang_choose == 1:
		var dsts: Array = action.get("dst_ids", [])
		ai_shang_dst = int(dsts[0])
	notice_skill(XUE_ZHI_AI_SHANG, [player.id])
	player.boot_skill_used = true
	engine.push_harm({
		"src": player.id, "dst": player.id, "point": 2,
		"cause": XUE_ZHI_AI_SHANG, "type": GConst.HarmType.Magic,
	})
	engine._broadcast_game()
	return URGENT


## 血之哀伤结算完（伤害已落地）：转移 / 移除【同生共死】
func p_after_special(ctx: Dictionary) -> int:
	if int(ctx.get("action_id", 0)) != XUE_ZHI_AI_SHANG or ai_shang_choose == 0:
		return SUCCESS
	if ai_shang_choose == 1:
		_transfer_tong_sheng(ai_shang_dst)
	else:
		_remove_tong_sheng()
	ai_shang_choose = 0
	ai_shang_dst = -1
	engine._broadcast_game()
	return SUCCESS


## 血之哀伤判定（服务端 WuNv::XueZhiAiShangJudge）：手牌为空且无宝石、或手牌全为光系时，
## 本次可用于抵御的治疗最多 1 点（服务端把 crossAvailable 压到 1）
func p_timeline_4(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("dst", -1)) != player.id:
		return SUCCESS
	if int(harm.get("cause", -1)) != XUE_ZHI_AI_SHANG:
		return SUCCESS
	if player.cross_num < 2:
		return SUCCESS
	if player.hand_cards.is_empty() and player.gem < 1:
		harm["cross_max_point"] = 1
		return SUCCESS
	var all_light: bool = true
	for cid: int in player.hand_cards:
		var c: GCard = Data.get_card(cid)
		if c == null or c.element_enum() != GConst.CardElement.Light:
			all_light = false
			break
	if all_light:
		harm["cross_max_point"] = 1
	return SUCCESS


# ============================================================
# 脱流血形态（服务端 WuNv::p_hand_change）：任何时候手牌不足 3 张就强制重置形态
# 引擎在「手牌数量变化」后统一触发 p_hand_change（见 battle_engine._check_hand_change），
# 因此被他人技能逼着弃牌也会立刻脱形态
# ============================================================
func p_hand_change(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	return _to_normal_form()


func _to_normal_form() -> int:
	if not player.tap or player.hand_cards.size() >= 3:
		return SUCCESS
	player.tap = false
	if tong_sheng_id == -1:
		engine._broadcast_game()
		return SUCCESS
	if tong_sheng_id == player.id:
		player.hand_cards_max -= 3
	else:
		var dst: BattlePlayer = engine.p(tong_sheng_id)
		if dst != null:
			dst.hand_cards_max -= 3
		player.hand_cards_max -= 3
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 流血（持续）：因承受伤害导致我方士气下降时转为【流血形态】，+1 治疗
# ============================================================
func p_true_lose_morale(ctx: Dictionary) -> int:
	if int(ctx.get("dst", -1)) != player.id or player.tap:
		return SUCCESS
	if int(ctx.get("amount", 0)) <= 0:
		return SUCCESS
	# 服务端要求本次掉士气由伤害造成（con->harm.type != HARM_NONE）
	if int(ctx.get("type", 0)) == GConst.HarmType.None:
		return SUCCESS
	engine.set_tap(player.id, true)
	施加治疗(player.id, 1)
	if tong_sheng_id != -1:
		if tong_sheng_id == player.id:
			player.hand_cards_max += 3
		else:
			var dst: BattlePlayer = engine.p(tong_sheng_id)
			if dst != null:
				dst.hand_cards_max += 3
			player.hand_cards_max += 3
	engine._broadcast_game()
	return SUCCESS


## 转移【同生共死】到新目标，并按形态联动双方手牌上限
func _transfer_tong_sheng(new_dst: int) -> void:
	var dst: BattlePlayer = engine.p(new_dst)
	if dst == null:
		return
	notice_skill(XUE_ZHI_AI_SHANG, [new_dst])
	var old: BattlePlayer = engine.p(tong_sheng_id)
	if old != null:
		old.remove_exclusive_effect(GConst.Exclusive.TongShengGongSi)
	dst.add_exclusive_effect(GConst.Exclusive.TongShengGongSi)
	if new_dst != player.id:
		if player.tap:
			dst.hand_cards_max += 1
		else:
			dst.hand_cards_max -= 2
	if tong_sheng_id != player.id:
		if old != null:
			if player.tap:
				old.hand_cards_max -= 1
			else:
				old.hand_cards_max += 2
	tong_sheng_id = new_dst


## 移除【同生共死】，并按形态联动双方手牌上限
func _remove_tong_sheng() -> void:
	notice_skill(XUE_ZHI_AI_SHANG, [player.id])
	var old: BattlePlayer = engine.p(tong_sheng_id)
	if old != null:
		old.remove_exclusive_effect(GConst.Exclusive.TongShengGongSi)
	if tong_sheng_id == player.id:
		if player.tap:
			player.hand_cards_max -= 1
		else:
			player.hand_cards_max += 2
	else:
		if old != null:
			if player.tap:
				old.hand_cards_max -= 1
			else:
				old.hand_cards_max += 2
		if player.tap:
			player.hand_cards_max -= 1
		else:
			player.hand_cards_max += 2
	tong_sheng_id = -1


# ============================================================
# 主动法术技能
# ============================================================
func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	var aid: int = int(action.get("action_id", 0))
	var cards: Array = action.get("card_ids", [])
	var args: Array = action.get("args", [])
	if aid == TONG_SHENG_GONG_SI:
		if tong_sheng_id != -1:
			return GConst.GE_INVALID_ACTION
		return GConst.GE_SUCCESS
	if aid == NI_LIU:
		if not player.tap or cards.size() != 2:
			return GConst.GE_INVALID_ACTION
		return GConst.GE_SUCCESS
	if aid == XUE_ZHI_BEI_MING:
		if cards.is_empty():
			return GConst.GE_INVALID_CARDID
		var cid: int = int(cards[0])
		var card: GCard = Data.get_card(cid)
		if not player.has_hand_card(cid) or card == null or not card.has_skill_id(XUE_ZHI_BEI_MING):
			return GConst.GE_INVALID_ACTION
		if not args.is_empty() and (int(args[0]) < 1 or int(args[0]) > 3):
			return GConst.GE_INVALID_ACTION
		return GConst.GE_SUCCESS
	if aid == XUE_ZHI_ZU_ZHOU:
		if player.gem < 1:
			return GConst.GE_INVALID_ACTION
		return GConst.GE_SUCCESS
	return GConst.GE_INVALID_ACTION


func p_magic_skill(action: Dictionary) -> int:
	match int(action.get("action_id", 0)):
		TONG_SHENG_GONG_SI:
			return _tong_sheng_gong_si(action)
		NI_LIU:
			return _ni_liu(action)
		XUE_ZHI_BEI_MING:
			return _xue_zhi_bei_ming(action)
		XUE_ZHI_ZU_ZHOU:
			return _xue_zhi_zu_zhou(action)
	return GConst.GE_INVALID_ACTION


## 同生共死：摸 2 张牌，把独有效果放到目标身上并按形态联动双方手牌上限
func _tong_sheng_gong_si(action: Dictionary) -> int:
	var dsts: Array = action.get("dst_ids", [])
	var dst_id: int = int(dsts[0]) if not dsts.is_empty() else player.id
	var dst: BattlePlayer = engine.p(dst_id)
	if dst == null:
		return GConst.GE_INVALID_PLAYERID
	notice_skill(TONG_SHENG_GONG_SI, [dst_id])
	engine.draw(player.id, 2)
	tong_sheng_id = dst_id
	dst.add_exclusive_effect(GConst.Exclusive.TongShengGongSi)
	if dst_id == player.id:
		if player.tap:
			player.hand_cards_max += 1
		else:
			player.hand_cards_max -= 2
	else:
		if player.tap:
			player.hand_cards_max += 1
			dst.hand_cards_max += 1
		else:
			player.hand_cards_max -= 2
			dst.hand_cards_max -= 2
	engine._broadcast_game()
	return SUCCESS


## 逆流：弃 2 张牌，+1 治疗
func _ni_liu(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var use: Array = []
	for c: Variant in cards:
		use.append(int(c))
	notice_skill(NI_LIU, [player.id])
	engine.take_from_hand(player.id, use)
	engine.to_discard(use)
	engine._log_discard(player.id, use)
	施加治疗(player.id, 1)
	engine._broadcast_game()
	return SUCCESS


## 血之悲鸣：对目标角色和自己各造成 1~3 点法术伤害
func _xue_zhi_bei_ming(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	var args: Array = action.get("args", [])
	var dst_id: int = int(dsts[0]) if not dsts.is_empty() else player.id
	var cid: int = int(cards[0])
	# 服务端 args(0) 为 1~3 的伤害值；客户端未提供时按最低 1 点处理
	var harm_num: int = int(args[0]) if not args.is_empty() else 1
	harm_num = clampi(harm_num, 1, 3)
	notice_skill(XUE_ZHI_BEI_MING, [dst_id])
	engine.push_harm({
		"src": player.id, "dst": player.id, "point": harm_num,
		"cause": XUE_ZHI_BEI_MING, "type": GConst.HarmType.Magic,
	})
	engine.push_harm({
		"src": player.id, "dst": dst_id, "point": harm_num,
		"cause": XUE_ZHI_BEI_MING, "type": GConst.HarmType.Magic,
	})
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": [cid], "is_real": true,
	})
	engine.take_from_hand(player.id, [cid], true)
	engine.to_discard([cid])
	engine._broadcast_game()
	return URGENT


## 血之诅咒：耗 1 宝石，对目标角色 2 点法术伤害，随后弃最多 3 张牌
## 服务端顺序：先造成 2 点法术伤害，再弃牌（弃牌排在伤害之后）
func _xue_zhi_zu_zhou(action: Dictionary) -> int:
	var dsts: Array = action.get("dst_ids", [])
	var dst_id: int = int(dsts[0]) if not dsts.is_empty() else player.id
	if step != 0:
		return SUCCESS
	step = STEP_DONE
	notice_skill(XUE_ZHI_ZU_ZHOU, [dst_id])
	player.set_gem(player.gem - 1)
	# 压栈顺序：弃牌 → 伤害，LIFO 弹出即「先伤害、后弃牌」
	engine.push(BattleEngine.SRequestDiscard.new(player.id, mini(player.hand_cards.size(), 3), -1, XUE_ZHI_ZU_ZHOU))
	engine.push_harm({
		"src": player.id, "dst": dst_id, "point": 2,
		"cause": XUE_ZHI_ZU_ZHOU, "type": GConst.HarmType.Magic,
	})
	engine._broadcast_game()
	return URGENT
