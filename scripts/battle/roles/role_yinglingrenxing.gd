extends BattleRole
## 英灵人形（roleID 27）—— 移植自服务端 role/YingLingRenXing.cpp
## 技能：怒火压制（响应 2702：主动攻击未命中时，翻转 1 个【战纹】为【魔纹】）、
##       魔纹融合（响应 2704：主动攻击未命中时，翻转 1 个【魔纹】，弃 X 张异系牌对目标造成 (X-1) 点法术伤害）、
##       战纹碎击（响应 2703：主动攻击命中时，翻转 1 个【战纹】，弃 X 张同系牌使本次伤害 +(X-1)）、
##       符文改造（启动 2705：宝石 ×1 转为【蓄势迸发形态】，手牌上限 +2、摸 2 张牌并重排【战纹】/【魔纹】）、
##       双重回响（响应 2706：对目标造成伤害时，能量 ×1 对另一目标造成等量（最高 3）法术伤害，且不造成士气下降）
## 【战纹】tokens[0]、【魔纹】tokens[1]，上限之和为 3；【蓄势迸发形态】用 tap 表示。

const NU_HUO_MO_WEN: int = 2701       # 怒火压制 / 魔纹融合 的询问号
const NU_HUO_YA_ZHI: int = 2702       # 怒火压制（宣告号）
const ZHAN_WEN_SUI_JI: int = 2703     # 战纹碎击（响应）
const MO_WEN_RONG_HE: int = 2704      # 魔纹融合（宣告号）
## 怒火压制／魔纹融合 询问的选项值（客户端点选项即以该值作为回复 args[0]）
const CHOICE_NU_HUO_YA_ZHI: int = 1
const CHOICE_MO_WEN_RONG_HE: int = 2
const FU_WEN_GAI_ZAO: int = 2705      # 符文改造（启动）
const FU_WEN_GAI_ZAO_TOKEN: int = 27051 # 符文改造·重排指示物
const SHUANG_CHONG_HUI_XIANG: int = 2706 # 双重回响（响应）

const TOKEN_ZHAN_WEN: int = 0         # 「战纹」指示物下标
const TOKEN_MO_WEN: int = 1           # 「魔纹」指示物下标
const TOKEN_MAX: int = 3
const FU_WEN_HAND_ADD: int = 2        # 符文改造期间手牌上限 +2

enum ElementKind { Invalid = 0, AllDifferent = 1, AllSame = 2 }

var shuangChongHuiXiangUsed: bool = false


func setup(p: BattlePlayer, e: BattleEngine) -> void:
	super.setup(p, e)
	p.tokens[TOKEN_ZHAN_WEN] = {"name": "战纹", "max": TOKEN_MAX, "num": 3}
	p.tokens[TOKEN_MO_WEN] = {"name": "魔纹", "max": TOKEN_MAX, "num": 0}


func available_skills() -> Array:
	return []


# ============================================================
# 指示物：战纹 / 魔纹
# ============================================================
func _zhan_wen() -> int:
	return int(player.tokens[TOKEN_ZHAN_WEN]["num"])


func _mo_wen() -> int:
	return int(player.tokens[TOKEN_MO_WEN]["num"])


func _set_zhan_wen(v: int) -> void:
	player.tokens[TOKEN_ZHAN_WEN]["num"] = clampi(v, 0, TOKEN_MAX)


func _set_mo_wen(v: int) -> void:
	player.tokens[TOKEN_MO_WEN]["num"] = clampi(v, 0, TOKEN_MAX)


# ============================================================
# 回合开始 / 启动：符文改造
# ============================================================
func p_turn_begin(_ctx: Dictionary) -> int:
	shuangChongHuiXiangUsed = false
	return SUCCESS


func p_boot(_ctx: Dictionary) -> int:
	if engine.current_id != player.id:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if step == 0:
		step = FU_WEN_GAI_ZAO
	if step == FU_WEN_GAI_ZAO:
		var r: int = _fu_wen_gai_zao()
		if r == WAIT:
			return WAIT
		if r == URGENT:
			step = FU_WEN_GAI_ZAO_TOKEN
			return URGENT
		step = STEP_DONE
	if step == FU_WEN_GAI_ZAO_TOKEN:
		var r2: int = _fu_wen_gai_zao_token()
		if r2 == WAIT:
			return WAIT
		step = STEP_DONE
	return SUCCESS


## 符文改造：消耗 1 宝石转为蓄势迸发形态，手牌上限 +2 并摸 2 张牌
func _fu_wen_gai_zao() -> int:
	if player.gem < 1:
		return SUCCESS
	if not engine.has_reply():
		engine.ask_skill(player.id, FU_WEN_GAI_ZAO, 0, 0)
		return WAIT
	if not take_skill_reply():
		return SUCCESS
	notice_skill(FU_WEN_GAI_ZAO, [player.id])
	player.set_gem(player.gem - 1)
	player.hand_cards_max += FU_WEN_HAND_ADD
	engine.draw(player.id, 2)
	engine.set_tap(player.id, true)
	engine._broadcast_game()
	return URGENT


## 符文改造·重排：任意调整【战纹】与【魔纹】（两者之和为 3）
func _fu_wen_gai_zao_token() -> int:
	if not engine.has_reply():
		engine.ask_skill(player.id, FU_WEN_GAI_ZAO_TOKEN, 0, 0)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	var num: int = int(args[1]) if args.size() > 1 else 1
	num = clampi(num, 0, TOKEN_MAX)
	_set_zhan_wen(num)
	_set_mo_wen(TOKEN_MAX - _zhan_wen())
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 主动攻击命中后：战纹碎击
# ============================================================
func p_timeline_2_hit(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	if _zhan_wen() == 0:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if step == 0:
		step = ZHAN_WEN_SUI_JI
	if step == ZHAN_WEN_SUI_JI:
		var r: int = _zhan_wen_sui_ji(ctx)
		if r == WAIT:
			return WAIT
		step = STEP_DONE
		if r == URGENT:
			return URGENT
	return SUCCESS


## 战纹碎击：翻转 1 个战纹，弃 X 张同系牌，本次伤害 +(X-1)（可额外翻转 Y 个战纹，再 +Y）
func _zhan_wen_sui_ji(ctx: Dictionary) -> int:
	if not engine.has_reply():
		# 弃 X 张同系牌（X≥2）：上限放到手牌数，并让客户端只让同系牌可点
		engine.ask_skill(player.id, ZHAN_WEN_SUI_JI, 2, 0, GConst.CardSource.Hand, [], player.hand_count(), "same")
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		return SUCCESS
	var cards: Array = r.get("card_ids", [])
	if _zhan_wen() < 1 or cards.size() < 2:
		return GConst.GE_INVALID_ARGUMENT
	if _element_check(cards) != ElementKind.AllSame or not _has_cards(cards):
		return GConst.GE_INVALID_CARDID
	_set_zhan_wen(_zhan_wen() - 1)
	_set_mo_wen(_mo_wen() + 1)
	var addition: int = int(args[1]) if args.size() > 1 else 0
	if addition > 0:
		if _zhan_wen() < addition:
			return GConst.GE_INVALID_ARGUMENT
		_set_zhan_wen(_zhan_wen() - addition)
		_set_mo_wen(_mo_wen() + addition)
	notice_skill(ZHAN_WEN_SUI_JI, [int(ctx.get("dst", -1))])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": cards, "is_real": true,
	})
	engine.take_from_hand(player.id, cards)
	engine.to_discard(cards)
	var harm: Dictionary = ctx.get("harm", {})
	harm["point"] = int(harm.get("point", 0)) + cards.size() - 1 + addition
	engine._broadcast_game()
	return URGENT


# ============================================================
# 主动攻击未命中后：怒火压制 / 魔纹融合
# ============================================================
func p_timeline_2_miss(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if step == 0:
		step = NU_HUO_MO_WEN
	if step == NU_HUO_MO_WEN:
		var r: int = _nu_huo_mo_wen(ctx)
		if r == WAIT:
			return WAIT
		step = STEP_DONE
		if r == URGENT:
			return URGENT
	return SUCCESS


## 怒火压制（1）/ 魔纹融合（2）
## 两个分支对牌的要求不同（分支 1 不用牌；分支 2 要 ≥2 张异系牌），所以下发选项按钮让玩家选：
## 先按需选好牌（分支 2 用），再点对应选项；点分支 1 时不用选牌。
func _nu_huo_mo_wen(ctx: Dictionary) -> int:
	var dst_id: int = int(ctx.get("dst", -1))
	if not engine.has_reply():
		# 分支 2（魔纹融合）要弃 X 张互异系牌（X≥2）：上限放到手牌数，并让客户端只让异系牌可点
		engine.ask_skill(player.id, NU_HUO_MO_WEN, 2, 0, GConst.CardSource.Hand, [
			{"value": CHOICE_NU_HUO_YA_ZHI, "label": "怒火压制"},
			{"value": CHOICE_MO_WEN_RONG_HE, "label": "魔纹融合"},
		], player.hand_count(), "diff")
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	var choice: int = int(args[0]) if not args.is_empty() else 0
	if choice == CHOICE_NU_HUO_YA_ZHI:
		# 怒火压制：翻转 1 个战纹为魔纹
		if _zhan_wen() < 1:
			return GConst.GE_INVALID_ARGUMENT
		notice_skill(NU_HUO_YA_ZHI, [dst_id])
		_set_zhan_wen(_zhan_wen() - 1)
		_set_mo_wen(_mo_wen() + 1)
		engine._broadcast_game()
		return SUCCESS
	if choice == CHOICE_MO_WEN_RONG_HE:
		# 魔纹融合：翻转 1 个魔纹，弃 X 张异系牌，对目标造成 (X-1) 点法术伤害
		var cards: Array = r.get("card_ids", [])
		if _mo_wen() < 1 or cards.size() < 2:
			return GConst.GE_INVALID_ARGUMENT
		if _element_check(cards) != ElementKind.AllDifferent or not _has_cards(cards):
			return GConst.GE_INVALID_CARDID
		_set_zhan_wen(_zhan_wen() + 1)
		_set_mo_wen(_mo_wen() - 1)
		var addition: int = int(args[1]) if args.size() > 1 else 0
		if addition > 0:
			if _mo_wen() < addition:
				return GConst.GE_INVALID_ARGUMENT
			_set_zhan_wen(_zhan_wen() + addition)
			_set_mo_wen(_mo_wen() - addition)
		notice_skill(MO_WEN_RONG_HE, [dst_id])
		engine.broadcast(GConst.Msg.Card, {
			"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
			"card_ids": cards, "is_real": true,
		})
		engine.take_from_hand(player.id, cards)
		engine.to_discard(cards)
		engine.push_harm({
			"src": player.id, "dst": dst_id, "point": cards.size() - 1 + addition,
			"cause": MO_WEN_RONG_HE, "type": GConst.HarmType.Magic,
		})
		engine._broadcast_game()
		return URGENT
	return SUCCESS


# ============================================================
# 对目标造成伤害时：双重回响
# ============================================================
func p_timeline_3(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("src", -1)) != player.id:
		return SUCCESS
	if player.get_energy() < 1 or shuangChongHuiXiangUsed:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if step == 0:
		step = SHUANG_CHONG_HUI_XIANG
	if step == SHUANG_CHONG_HUI_XIANG:
		var r: int = _shuang_chong_hui_xiang(harm)
		if r == WAIT:
			return WAIT
		step = STEP_DONE
		if r == URGENT:
			return URGENT
	return SUCCESS


func _shuang_chong_hui_xiang(harm: Dictionary) -> int:
	var from_dst: int = int(harm.get("dst", -1))
	if not engine.has_reply():
		engine.ask_skill(player.id, SHUANG_CHONG_HUI_XIANG, 0, 1)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		return SUCCESS
	var dsts: Array = r.get("dst_ids", [])
	if dsts.is_empty():
		return SUCCESS
	var dst_id: int = int(dsts[0])
	if dst_id == from_dst:
		return GConst.GE_INVALID_ARGUMENT
	notice_skill(SHUANG_CHONG_HUI_XIANG, [dst_id])
	shuangChongHuiXiangUsed = true
	if player.crystal > 0:
		player.set_crystal(player.crystal - 1)
	else:
		player.set_gem(player.gem - 1)
	engine.push_harm({
		"src": player.id, "dst": dst_id, "point": mini(int(harm.get("point", 0)), 3),
		"cause": SHUANG_CHONG_HUI_XIANG, "type": GConst.HarmType.Magic,
	})
	engine._broadcast_game()
	return URGENT


## 双重回响的伤害不造成士气下降（服务端据 con->harm.cause == 双重回响 判定）
func p_before_lose_morale(ctx: Dictionary) -> int:
	if int(ctx.get("harm_cause", 0)) == SHUANG_CHONG_HUI_XIANG:
		ctx["amount"] = 0
	return SUCCESS


# ============================================================
# 回合结束：脱离蓄势迸发形态
# ============================================================
func p_turn_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id or not player.tap:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	step = STEP_DONE
	notice_skill(FU_WEN_GAI_ZAO, [player.id])
	player.hand_cards_max -= FU_WEN_HAND_ADD
	engine.set_tap(player.id, false)
	engine._broadcast_game()
	return URGENT


# ============================================================
# 工具
# ============================================================
## 判元素：全同 / 全异 / 其它
func _element_check(cards: Array) -> int:
	var elements: Array[int] = []
	for c: Variant in cards:
		var card: GCard = Data.get_card(int(c))
		if card == null:
			return ElementKind.Invalid
		var e: int = card.element_enum()
		if not elements.has(e):
			elements.append(e)
	if elements.size() == 1:
		return ElementKind.AllSame
	if elements.size() == cards.size():
		return ElementKind.AllDifferent
	return ElementKind.Invalid


## 是否全部为手牌（且非空）
func _has_cards(cards: Array) -> bool:
	if cards.is_empty():
		return false
	for c: Variant in cards:
		if not player.has_hand_card(int(c)):
			return false
	return true
