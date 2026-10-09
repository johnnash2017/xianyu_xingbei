extends BattleRole
## 封印师（roleID 4）—— 移植自服务端 role/FengYin.cpp
## 技能：
##   风之封印（401）/ 水之封印（402）/ 火之封印（403）/ 地之封印（404）/ 雷之封印（405）
##     ——【法术】把手中带对应【X之封印】的牌放到目标对手面前；该对手此后打出或展示出同系牌时强制触发：
##        对其造成 3 点法术伤害并移除该封印牌（在 p_show_hand 中判定）
##   法术激荡（406）——【被动】你的法术行动结束时额外 +1 攻击行动（p_after_magic）
##   五系束缚（407）——【法术·星石】把【五系束缚】放到目标对手面前：该对手的下个行动阶段开始前，
##        可选择摸（X+2）张牌【强制】以取消该效果并照常行动（X = 场上封印数，最高按 2 计，最多摸 4 张），
##        否则跳过该行动阶段；触发后移除【五系束缚】（在行动阶段入口 p_before_action 询问、结算）
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
const WU_XI_DRAW_BASE: int = GConst.五系束缚摸牌基数   # 五系束缚基础摸牌数
const WU_XI_DRAW_MAX: int = GConst.五系束缚摸牌上限   # 五系束缚摸牌上限（场上封印数最高按 2 计）


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
		# 封印破碎：合法目标限定为「面前有基础效果牌」的玩家（对照原客户端 FengYinPoSui 的 enablePlayerItem）。
		# 交互与天使【风之洁净】一致（CardSource.HandAndBasicEffect）：先点一名目标、按「确定」，
		# 客户端再列出该目标面前的基础效果供选，选中的那张牌 id 由 args[0] 回传
		# （v_magic_skill 用 _has_basic_card(dst3, args[0]) 校验）。
		# 一个基础效果都没有时不给出该技能
		var 有基础效果的目标: Array[int] = _有基础效果的目标()
		if not 有基础效果的目标.is_empty():
			out.append({"type": GConst.ActionType.MagicSkill, "id": FENG_YIN_PO_SUI, "need_card": 0, "need_target": 1,
				"card_source": GConst.CardSource.HandAndBasicEffect, "targets": 有基础效果的目标})
	return out


# ============================================================
# 行动阶段入口（p_before_action）：五系束缚（对照服务端 FengYin::WuXiShuFu_Effect）
# 当前回合玩家身上若有我放的【五系束缚】：询问他「跳过行动阶段」还是「摸（X+2）张牌继续行动」，
# 结算后移除该标记（不论选哪一项，触发即移除）。
# ============================================================
func p_before_action(_ctx: Dictionary) -> int:
	var cur: BattlePlayer = engine.p(engine.current_id)
	if cur == null or not cur.check_exclusive_effect(GConst.Exclusive.WuXiShuFu):
		return SUCCESS
	# 场上可能有多个封印师：只由「放这枚束缚的人」处理，避免重复询问
	if cur.exclusive_owner(GConst.Exclusive.WuXiShuFu) != player.id:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	# 已因【虚弱】等原因跳过行动阶段：本回合不必再询问，直接移除这枚束缚并返回。
	# 否则玩家选了「摸牌继续行动」也照样被跳过，还会白拿牌、束缚被消耗掉。
	if engine.skip_action_phase:
		cur.remove_exclusive_effect(GConst.Exclusive.WuXiShuFu)
		engine._broadcast_game()
		return SUCCESS
	# 应摸张数只算一次，询问文案与实际摸牌复用同一结果，避免两次计算不一致
	var 摸数: int = _wu_xi_draw_count()
	if not engine.has_reply():
		var options: Array = [
			{"value": 1, "label": "跳过行动阶段"},
			{"value": 2, "label": "摸 %d 张牌，继续行动阶段" % 摸数},
		]
		# 询问文案取技能表 407 的「提示」列（序号 0），{n} 填应摸张数；两个选项按钮标签保持不变
		询问(cur.id, WU_XI_SHU_FU, 0, 0, GConst.CardSource.Hand, options, 0, "", [], true, 0, -1, [], 摸数)
		step = 1
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	var args: Array = r.get("args", [])
	# 取消 / 超时按「跳过行动阶段」兜底（＝束缚生效）
	var choose: int = int(args[0]) if not args.is_empty() else 1
	notice_skill(WU_XI_SHU_FU, [cur.id])
	cur.remove_exclusive_effect(GConst.Exclusive.WuXiShuFu)
	if choose == 2:
		# 强摸走 push_draw：先让角色响应（如暗杀者【水影】：除特殊行动外、摸牌前发动）；
		# 摸牌可能把手牌顶过上限 → 配 SHandOverflow 走「强制弃牌 + 掉士气」（对照引擎其它摸牌点）
		engine.push(BattleEngine.SHandOverflow.new())
		engine.push_draw(cur.id, 摸数)
	else:
		# 跳过行动阶段走引擎通用标记 skip_action_phase（SActionPhase 自己收尾进回合结束）
		engine.skip_action_phase = true
	engine._broadcast_game()
	return SUCCESS


## 五系束缚的应摸牌数：2 + 场上封印数（封印数最高按 2 计，故 2~4 张）
func _wu_xi_draw_count() -> int:
	return mini(WU_XI_DRAW_BASE + _seal_count(), WU_XI_DRAW_MAX)


# ============================================================
# 展示手牌（p_show_hand）：封印触发
# ============================================================
func p_show_hand(ctx: Dictionary) -> int:
	# 命中封印后返回 URGENT，引擎跑完伤害结算会重新进入本钩子，从而依次触发同一玩家身上的多个封印。
	# ctx 全程是同一个字典：用「本次已触发的封印牌」记一笔，重入时跳过已触发的，避免同一张封印被触发两次
	var r: int = _feng_yin_effect(int(ctx.get("player", -1)), ctx.get("cards", []), ctx)
	if r == URGENT:
		return URGENT
	return SUCCESS


func _feng_yin_effect(player_id: int, cards: Array, ctx: Dictionary) -> int:
	var target: BattlePlayer = engine.p(player_id)
	if target == null:
		return SUCCESS
	var 已触发: Array = ctx.get("seals_triggered", [])
	for e: Dictionary in target.basic_effects:
		var 封印牌: int = int(e["card"])
		if 已触发.has(封印牌):
			continue
		var seal: GCard = Data.get_card(封印牌)
		if seal == null or not _is_seal_card(seal):
			continue
		# 服务端不校验封印是谁布的：任一封印师都会因同系牌触发（两个封印师同场时各自结算）
		var seal_elem: int = seal.element_enum()
		for c: Variant in cards:
			var shown: GCard = Data.get_card(int(c))
			if shown == null or shown.element_enum() != seal_elem:
				continue
			_trigger_seal(target, 封印牌, seal_elem)
			已触发.append(封印牌)
			ctx["seals_triggered"] = 已触发
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
			if dsts.is_empty():
				return GConst.GE_INVALID_PLAYERID
			if player.get_energy() <= 0:
				return GConst.GE_INVALID_ACTION
			# 要拿走的基础效果牌由 args[0] 回传（与天使【风之洁净】同一套交互）
			var args: Array = action.get("args", [])
			if args.is_empty():
				return GConst.GE_INVALID_ARGUMENT
			var dst3: BattlePlayer = engine.p(int(dsts[0]))
			if dst3 == null or not _has_basic_card(dst3, int(args[0])):
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
	engine.add_basic_effect(dst_id, cid, player.id, aid)
	engine.take_from_hand(player.id, [cid], true)
	engine._broadcast_game()
	return URGENT


## 五系束缚：消耗 1 能量（优先水晶），给目标对手挂上独有效果
func _cast_wu_xi_shu_fu(action: Dictionary) -> int:
	var dst_id: int = int(action.get("dst_ids")[0])
	var dst: BattlePlayer = engine.p(dst_id)
	notice_skill(WU_XI_SHU_FU, [dst_id])
	_consume_one_energy()
	# 记下放牌者（自己）：p_before_action 据此只让放牌的那个封印师处理这枚束缚（多封印师同场时）
	dst.add_exclusive_effect(GConst.Exclusive.WuXiShuFu, player.id)
	engine._broadcast_game()
	return SUCCESS


## 封印破碎：消耗 1 能量（优先水晶），把场上任意一张基础效果牌收入自己手中
func _cast_feng_yin_po_sui(action: Dictionary) -> int:
	var cid: int = int(action.get("args")[0])
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


## 面前有基础效果的玩家（含自己）：【封印破碎】的合法目标
## （对照原客户端 FengYinPoSui 里对 hasStatus() 的 playerArea->enablePlayerItem）
func _有基础效果的目标() -> Array[int]:
	return player_ids_where(func(p: BattlePlayer) -> bool: return not p.basic_effects.is_empty(), true)


## 目标是否拥有指定的基础效果牌
func _has_basic_card(target: BattlePlayer, cid: int) -> bool:
	for e: Dictionary in target.basic_effects:
		if int(e["card"]) == cid:
			return true
	return false
