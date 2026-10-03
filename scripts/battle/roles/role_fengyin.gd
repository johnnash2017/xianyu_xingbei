extends BattleRole
## 封印师（roleID 4）—— 移植自服务端 role/FengYin.cpp
## 技能：
##   风之封印（401）/ 水之封印（402）/ 火之封印（403）/ 地之封印（404）/ 雷之封印（405）
##     ——【法术】把手中带对应【X之封印】的牌放到目标对手面前；该对手此后打出或展示出同系牌时强制触发：
##        对其造成 3 点法术伤害并移除该封印牌（在 p_show_hand 中判定）
##   法术激荡（406）——【被动】你的法术行动结束时额外 +1 攻击行动（p_after_magic）
##   五系束缚（407）——【法术·星石】把【五系束缚】放到目标对手面前；在其下个行动阶段开始前可选择摸
##        （X+2）张牌取消（X = 场上封印数，最高按 2 计，即最多摸 4 张），否则跳过该行动阶段
##        （与【虚弱】合并成同一次询问，见 p_check_basic_effect）
##   封印破碎（408）——【法术·星石】把场上任意一张基础效果牌收入自己手中

const FENG_ZHI_FENG_YIN: int = 401
const SHUI_ZHI_FENG_YIN: int = 402
const HUO_ZHI_FENG_YIN: int = 403
const DI_ZHI_FENG_YIN: int = 404
const LEI_ZHI_FENG_YIN: int = 405
const FA_SHU_JI_DANG: int = 406
const WU_XI_SHU_FU: int = 407
const FENG_YIN_PO_SUI: int = 408

const SEAL_HARM_POINT: int = 3      # 封印触发时的法术伤害
const WU_XI_DRAW_BASE: int = 2      # 五系束缚基础摸牌数
const WU_XI_DRAW_MAX: int = 4       # 五系束缚摸牌上限（场上封印数最高按 2 计）


# ============================================================
# 行动阶段可选技能
# ============================================================
func available_skills() -> Array:
	var out: Array = []
	for sid: int in [FENG_ZHI_FENG_YIN, SHUI_ZHI_FENG_YIN, HUO_ZHI_FENG_YIN, DI_ZHI_FENG_YIN, LEI_ZHI_FENG_YIN]:
		# 只有手里带对应【X之封印】的牌才能发动，下发给界面用来把其余手牌置灰（v_magic_skill 校验同一条）
		var 封印牌: Array[int] = hand_ids_with_skill(sid)
		if not 封印牌.is_empty():
			# 目标须非同色、且身上没有同种封印（v_magic_skill：dst.color == player.color
			# 或 dst.check_basic_effect_skill(aid) 为真时拒收）
			out.append({"type": GConst.ActionType.MagicSkill, "id": sid, "need_card": 1, "need_target": 1,
				"cards": 封印牌,
				"targets": player_ids_where(func(p: BattlePlayer) -> bool: return p.color != player.color and not p.check_basic_effect_skill(sid))})
	if player.get_energy() > 0:
		# 五系束缚：目标须为对手（v_magic_skill：dst.color == player.color 时拒收）
		out.append({"type": GConst.ActionType.MagicSkill, "id": WU_XI_SHU_FU, "need_card": 0, "need_target": 1,
			"targets": enemy_ids()})
		if _any_basic_effect_on_field():
			# 封印破碎：发动牌是目标面前的基础效果牌，不是手牌
			# （v_magic_skill 用 _has_basic_card(dst3, cards[0]) 校验目标身上的基础效果牌）
			out.append({"type": GConst.ActionType.MagicSkill, "id": FENG_YIN_PO_SUI, "need_card": 1, "need_target": 1,
				"card_source": GConst.CardSource.BasicEffect})
	return out


# ============================================================
# 回合开始的基础效果检查（服务端 FengYin::WuXiShuFu_Effect，由引擎在虚弱询问前调用）
# 当前回合玩家身上若有【五系束缚】，移除它并把应摸牌数（2 + 场上封印数，上限 4）交给引擎，
# 与【虚弱】合并成同一次询问
# ============================================================
func p_check_basic_effect(ctx: Dictionary) -> int:
	var cur: BattlePlayer = engine.p(int(ctx.get("player", -1)))
	if cur == null or not cur.check_exclusive_effect(GConst.Exclusive.WuXiShuFu):
		return SUCCESS
	cur.remove_exclusive_effect(GConst.Exclusive.WuXiShuFu)
	ctx["how_many"] = int(ctx.get("how_many", 0)) + mini(WU_XI_DRAW_BASE + _seal_count(), WU_XI_DRAW_MAX)
	return SUCCESS


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
		# 服务端不校验封印是谁布的：任一封印师都会因同系牌触发（两个封印师同场时各自结算）
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
	engine.remove_basic_effect(target.id, seal_card, cause, player.id)
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
	player.add_action(GConst.ActionType.Attack, FA_SHU_JI_DANG, true)
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
			if not player.has_hand_card(cid) or card == null or not card.has_skill_id(aid):
				return GConst.GE_INVALID_ACTION
			var dst: BattlePlayer = engine.p(int(dsts[0]))
			if dst == null or dst.color == player.color or dst.check_basic_effect_skill(aid):
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
	engine.remove_basic_effect(dst_id, cid, FENG_YIN_PO_SUI, player.id)
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


## 元素 → 对应的封印技能号（服务端 getMapping）
func _seal_cause(element: int) -> int:
	match element:
		GConst.CardElement.Wind: return FENG_ZHI_FENG_YIN
		GConst.CardElement.Water: return SHUI_ZHI_FENG_YIN
		GConst.CardElement.Fire: return HUO_ZHI_FENG_YIN
		GConst.CardElement.Earth: return DI_ZHI_FENG_YIN
		GConst.CardElement.Thunder: return LEI_ZHI_FENG_YIN
	return 0


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
