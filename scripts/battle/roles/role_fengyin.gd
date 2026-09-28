extends BattleRole
## 封印师（roleID 4）—— 移植自服务端 role/FengYin.cpp
## 技能：
##   风之封印（401）/ 水之封印（402）/ 火之封印（403）/ 地之封印（404）/ 雷之封印（405）
##     ——【法术】把手中带对应【X之封印】的牌放到目标对手面前；该对手此后打出或展示出同系牌时强制触发：
##        对其造成 3 点法术伤害并移除该封印牌（在 p_show_hand 中判定）
##   法术激荡（406）——【被动】你的法术行动结束时额外 +1 攻击行动（p_after_magic）
##   五系束缚（407）——【法术·星石】把【五系束缚】放到目标对手面前；在其下个行动阶段开始前可选择摸
##        （X+2）张牌取消（X = 场上封印数，最高按 2 计，即最多摸 4 张），否则跳过该行动阶段（p_boot 判定）
##   封印破碎（408）——【法术·星石】把场上任意一张基础效果牌收入自己手中
##
## 引擎限制说明：服务端用一个 StateWeaken 同时结算「虚弱 + 五系束缚」的摸牌/跳过行动阶段；
## 本引擎 SWeaken 只处理虚弱牌，故五系束缚改在 p_boot 中独立询问，并在拒绝时沿用引擎
## 自身「跳过行动阶段」的做法（移除本回合行动阶段状态 + 压入回合结束状态）。

const FENG_ZHI_FENG_YIN: int = 401
const SHUI_ZHI_FENG_YIN: int = 402
const HUO_ZHI_FENG_YIN: int = 403
const DI_ZHI_FENG_YIN: int = 404
const LEI_ZHI_FENG_YIN: int = 405
const FA_SHU_JI_DANG: int = 406
const WU_XI_SHU_FU: int = 407
const FENG_YIN_PO_SUI: int = 408

const TAG_SEAL_WIND: String = "风之封印"
const TAG_SEAL_WATER: String = "水之封印"
const TAG_SEAL_FIRE: String = "火之封印"
const TAG_SEAL_EARTH: String = "地之封印"
const TAG_SEAL_THUNDER: String = "雷之封印"

const SEAL_HARM_POINT: int = 3      # 封印触发时的法术伤害
const WU_XI_DRAW_BASE: int = 2      # 五系束缚基础摸牌数
const WU_XI_DRAW_MAX: int = 4       # 五系束缚摸牌上限（场上封印数最高按 2 计）

## 五系束缚询问状态
var _wu_xi_asking: bool = false
var _wu_xi_draw: int = 0


# ============================================================
# 行动阶段可选技能
# ============================================================
func available_skills() -> Array:
	var out: Array = []
	for sid: int in [FENG_ZHI_FENG_YIN, SHUI_ZHI_FENG_YIN, HUO_ZHI_FENG_YIN, DI_ZHI_FENG_YIN, LEI_ZHI_FENG_YIN]:
		if _hand_has_tag(_seal_tag(sid)):
			out.append({"type": GConst.ActionType.MagicSkill, "id": sid, "need_card": 1, "need_target": 1})
	if player.get_energy() > 0:
		out.append({"type": GConst.ActionType.MagicSkill, "id": WU_XI_SHU_FU, "need_card": 0, "need_target": 1})
		if _any_basic_effect_on_field():
			out.append({"type": GConst.ActionType.MagicSkill, "id": FENG_YIN_PO_SUI, "need_card": 1, "need_target": 1})
	return out


# ============================================================
# 回合开始（p_boot）：五系束缚判定
# ============================================================
func p_boot(_ctx: Dictionary) -> int:
	var cur: BattlePlayer = engine.p(engine.current_id)
	if cur == null or not cur.check_exclusive_effect(GConst.Exclusive.WuXiShuFu):
		return SUCCESS
	if not _wu_xi_asking:
		_wu_xi_asking = true
		_wu_xi_draw = mini(WU_XI_DRAW_BASE + _seal_count(), WU_XI_DRAW_MAX)
		cur.remove_exclusive_effect(GConst.Exclusive.WuXiShuFu)
		engine._broadcast_game()
		engine.ask_skill(cur.id, WU_XI_SHU_FU, 0, 0)
		return WAIT
	_wu_xi_asking = false
	notice_skill(WU_XI_SHU_FU, [cur.id])
	if take_skill_reply():
		engine.draw(cur.id, _wu_xi_draw)
		engine._broadcast_game()
		return SUCCESS
	_skip_action_phase()
	engine._broadcast_game()
	return SUCCESS


## 跳过当前玩家的行动阶段：效仿引擎 SWeaken 的做法（移除尚未执行的行动阶段状态，压入回合结束状态）
func _skip_action_phase() -> void:
	var found: bool = false
	for st: Variant in engine._states:
		if st is BattleEngine.SActionPhase:
			found = true
			break
	if not found:
		return
	engine._remove_next_state(BattleEngine.SActionPhase)
	engine.resolve_action(GConst.ActionType.None, {})


# ============================================================
# 展示手牌（p_show_hand）：封印触发
# ============================================================
func p_show_hand(ctx: Dictionary) -> int:
	# 命中封印后返回 URGENT，引擎跑完伤害结算会重新进入本钩子，从而依次触发同一玩家身上的多个封印
	var r: int = _feng_yin_effect(int(ctx.get("player", -1)), ctx.get("cards", []))
	if r == URGENT:
		return URGENT
	return SUCCESS


func _feng_yin_effect(player_id: int, cards: Array) -> int:
	var target: BattlePlayer = engine.p(player_id)
	if target == null:
		return SUCCESS
	for e: Dictionary in target.basic_effects:
		var seal: GCard = Data.get_card(int(e["card"]))
		if seal == null or not _is_seal_card(seal):
			continue
		# 只由布下封印的封印师本人触发（服务端未校验来源，两个封印师同场会重复结算）
		if int(e["src"]) != player.id:
			continue
		var seal_elem: int = seal.element_enum()
		for c: Variant in cards:
			var shown: GCard = Data.get_card(int(c))
			if shown == null or shown.element_enum() != seal_elem:
				continue
			_trigger_seal(target, int(e["card"]), seal_elem)
			return URGENT
	return SUCCESS


func _trigger_seal(target: BattlePlayer, seal_card: int, element: int) -> void:
	var cause: int = _seal_cause(element)
	notice_skill(cause, [target.id])
	engine.remove_basic_effect(target.id, seal_card, cause)
	engine.to_discard([seal_card])
	engine.push_harm({
		"src": player.id, "dst": target.id, "point": SEAL_HARM_POINT,
		"cause": cause, "type": GConst.HarmType.Magic,
	})
	engine._broadcast_game()


# ============================================================
# 法术行动结束（法术激荡）：额外 +1 攻击行动
# ============================================================
func p_after_magic(ctx: Dictionary) -> int:
	# 法术牌行动传 src，法术技能传 player
	if int(ctx.get("player", ctx.get("src", -1))) != player.id:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	step = STEP_DONE
	player.add_action(GConst.ActionType.Attack, FA_SHU_JI_DANG)
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
		FENG_ZHI_FENG_YIN, SHUI_ZHI_FENG_YIN, HUO_ZHI_FENG_YIN, DI_ZHI_FENG_YIN, LEI_ZHI_FENG_YIN:
			if cards.is_empty() or dsts.is_empty():
				return GConst.GE_INVALID_CARDID
			var cid: int = int(cards[0])
			var card: GCard = Data.get_card(cid)
			if not player.has_hand_card(cid) or card == null or not card.has_speciality_name(_seal_tag(aid)):
				return GConst.GE_INVALID_ACTION
			var dst: BattlePlayer = engine.p(int(dsts[0]))
			if dst == null or dst.color == player.color or dst.check_basic_effect_tag(_seal_tag(aid)):
				return GConst.GE_INVALID_PLAYERID
		WU_XI_SHU_FU:
			if dsts.is_empty():
				return GConst.GE_INVALID_PLAYERID
			if player.get_energy() <= 0:
				return GConst.GE_INVALID_ACTION
			var dst2: BattlePlayer = engine.p(int(dsts[0]))
			if dst2 == null or dst2.color == player.color:
				return GConst.GE_INVALID_PLAYERID
		FENG_YIN_PO_SUI:
			if cards.is_empty() or dsts.is_empty():
				return GConst.GE_INVALID_CARDID
			if player.get_energy() <= 0:
				return GConst.GE_INVALID_ACTION
			var dst3: BattlePlayer = engine.p(int(dsts[0]))
			if dst3 == null or not _has_basic_card(dst3, int(cards[0])):
				return GConst.GE_INVALID_ACTION
		_:
			return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	match int(action.get("action_id", 0)):
		FENG_ZHI_FENG_YIN, SHUI_ZHI_FENG_YIN, HUO_ZHI_FENG_YIN, DI_ZHI_FENG_YIN, LEI_ZHI_FENG_YIN:
			return _cast_seal(action)
		WU_XI_SHU_FU:
			return _cast_wu_xi_shu_fu(action)
		FENG_YIN_PO_SUI:
			return _cast_feng_yin_po_sui(action)
	return GConst.GE_INVALID_ACTION


## 封印：把封印牌从自己手中放到目标对手的基础效果区
func _cast_seal(action: Dictionary) -> int:
	var aid: int = int(action.get("action_id", 0))
	var cid: int = int(action.get("card_ids")[0])
	var dst_id: int = int(action.get("dst_ids")[0])
	notice_skill(aid, [dst_id])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": dst_id,
		"card_ids": [cid], "is_real": true,
	})
	engine.take_from_hand(player.id, [cid])
	engine.add_basic_effect(dst_id, cid, player.id, aid)
	engine._broadcast_game()
	return URGENT


## 五系束缚：消耗 1 能量（优先水晶），给目标对手挂上独有效果
func _cast_wu_xi_shu_fu(action: Dictionary) -> int:
	var dst_id: int = int(action.get("dst_ids")[0])
	var dst: BattlePlayer = engine.p(dst_id)
	notice_skill(WU_XI_SHU_FU, [dst_id])
	_consume_one_energy()
	dst.add_exclusive_effect(GConst.Exclusive.WuXiShuFu)
	engine._broadcast_game()
	return SUCCESS


## 封印破碎：消耗 1 能量（优先水晶），把场上任意一张基础效果牌收入自己手中
func _cast_feng_yin_po_sui(action: Dictionary) -> int:
	var cid: int = int(action.get("card_ids")[0])
	var dst_id: int = int(action.get("dst_ids")[0])
	notice_skill(FENG_YIN_PO_SUI, [dst_id])
	_consume_one_energy()
	engine.remove_basic_effect(dst_id, cid, FENG_YIN_PO_SUI)
	player.add_hand_cards([cid])
	engine._broadcast_game()
	return URGENT


# ============================================================
# 工具
# ============================================================
## 消耗 1 点能量（优先水晶，其次宝石，与服务端一致）
func _consume_one_energy() -> void:
	if player.crystal > 0:
		player.set_crystal(player.crystal - 1)
	else:
		player.set_gem(player.gem - 1)


## 是否是封印牌（攻击牌 + 幻命格，与服务端 TYPE_ATTACK + PROPERTY_PHANTOM 一致）
func _is_seal_card(card: GCard) -> bool:
	return card.is_attack() and card.property_enum() == GConst.CardProperty.Phantom


## 技能号 → 封印特技标签
func _seal_tag(skill_id: int) -> String:
	match skill_id:
		FENG_ZHI_FENG_YIN: return TAG_SEAL_WIND
		SHUI_ZHI_FENG_YIN: return TAG_SEAL_WATER
		HUO_ZHI_FENG_YIN: return TAG_SEAL_FIRE
		DI_ZHI_FENG_YIN: return TAG_SEAL_EARTH
		LEI_ZHI_FENG_YIN: return TAG_SEAL_THUNDER
	return ""


## 元素 → 对应的封印技能号（服务端 getMapping）
func _seal_cause(element: int) -> int:
	match element:
		GConst.CardElement.Wind: return FENG_ZHI_FENG_YIN
		GConst.CardElement.Water: return SHUI_ZHI_FENG_YIN
		GConst.CardElement.Fire: return HUO_ZHI_FENG_YIN
		GConst.CardElement.Earth: return DI_ZHI_FENG_YIN
		GConst.CardElement.Thunder: return LEI_ZHI_FENG_YIN
	return 0


func _hand_has_tag(tag: String) -> bool:
	for cid: int in player.hand_cards:
		var c: GCard = Data.get_card(cid)
		if c != null and c.has_speciality_name(tag):
			return true
	return false


## 场上封印牌数量（五系束缚的 X 来源）
func _seal_count() -> int:
	var n: int = 0
	for pid: int in engine.order:
		var p0: BattlePlayer = engine.p(pid)
		if p0 == null:
			continue
		for e: Dictionary in p0.basic_effects:
			var c: GCard = Data.get_card(int(e["card"]))
			if c != null and _is_seal_card(c):
				n += 1
	return n


## 场上是否有任意基础效果（封印破碎的前提）
func _any_basic_effect_on_field() -> bool:
	for pid: int in engine.order:
		var p0: BattlePlayer = engine.p(pid)
		if p0 != null and not p0.basic_effects.is_empty():
			return true
	return false


## 目标是否拥有指定的基础效果牌
func _has_basic_card(target: BattlePlayer, cid: int) -> bool:
	for e: Dictionary in target.basic_effects:
		if int(e["card"]) == cid:
			return true
	return false
