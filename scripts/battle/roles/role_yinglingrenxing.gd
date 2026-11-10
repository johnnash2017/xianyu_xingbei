extends BattleRole
## 英灵人形（roleID 27）—— 移植自服务端 role/YingLingRenXing.cpp
## 技能：怒火压制（响应 2704：主动攻击未命中时翻转 1 个【战纹】为【魔纹】）、
##       魔纹融合（响应 2701：主动攻击未命中时翻转 1 个【魔纹】，弃 X 张异系牌对目标造成 (X-1) 点法术伤害；
##         两者在同一次未命中里二选一，不能同时发动）、
##       战纹碎击（响应 2703：主动攻击命中时，翻转 1 个【战纹】，弃 X 张同系牌使本次伤害 +(X-1)）、
##       符文改造（启动 2705：宝石 ×1 转为【蓄势迸发形态】，手牌上限 +1、摸 1 张牌并重排【战纹】/【魔纹】）、
##       双重回响（响应 2706：对目标造成伤害时，能量 ×1 对另一目标造成等量（最高 3）法术伤害，且不造成士气下降）
## 【战纹】tokens[0]、【魔纹】tokens[1】，上限见角色表；【蓄势迸发形态】用 tap 表示。

const NU_HUO_YA_ZHI: int = 2704       # 怒火压制（响应）
const MO_WEN_RONG_HE: int = 2701      # 魔纹融合（响应）
const ZHAN_WEN_SUI_JI: int = 2703     # 战纹碎击（响应）
## 怒火压制／魔纹融合 的开局二选一
const CHOICE_NU_HUO_YA_ZHI: int = 1
const CHOICE_MO_WEN_RONG_HE: int = 2
const FU_WEN_GAI_ZAO: int = 2705      # 符文改造（启动）
const SHUANG_CHONG_HUI_XIANG: int = 2706 # 双重回响（响应）

const TOKEN_ZHAN_WEN: int = 0         # 「战纹」指示物下标
const TOKEN_MO_WEN: int = 1           # 「魔纹」指示物下标
const FU_WEN_HAND_ADD: int = 1        # 符文改造期间手牌上限 +1

enum ElementKind { Invalid = 0, AllDifferent = 1, AllSame = 2 }

var shuangChongHuiXiangUsed: bool = false


func setup(p: BattlePlayer, e: BattleEngine) -> void:
	super.setup(p, e)
	# 【战纹】开局就带 3 点（表里只记上限，初始数量在这里补）
	p.tokens[TOKEN_ZHAN_WEN]["num"] = 3


## 行动阶段可发动的技能：【符文改造】为「启动」，不消耗行动
## （is_free_skill 认可，发动后引擎重新进入行动阶段让玩家继续本回合行动）
func available_skills() -> Array:
	var out: Array = []
	# 符文改造：有宝石时才能发动（耗 1 宝石并横置进入蓄势迸发形态、手牌上限 +1、摸 1 张）；
	# 重排【战纹】/【魔纹】的取值做成参数按钮，点哪个即以该值作为 args[0] 提交
	out.append({"type": GConst.ActionType.SpecialSkill, "id": FU_WEN_GAI_ZAO,
		"need_card": 0, "need_target": 0, "arg_choices": _fu_wen_gai_zao_choices(),
		"enabled": player.gem > 0})
	return out


## 【符文改造】为「启动」：不消耗本回合行动，发动后行动阶段照旧继续
func is_free_skill(skill_id: int) -> bool:
	return skill_id == FU_WEN_GAI_ZAO


# ============================================================
# 指示物：战纹 / 魔纹
# ============================================================
func _zhan_wen() -> int:
	return int(player.tokens[TOKEN_ZHAN_WEN]["num"])


func _mo_wen() -> int:
	return int(player.tokens[TOKEN_MO_WEN]["num"])


func _wen_max() -> int:
	return int(player.tokens[TOKEN_ZHAN_WEN]["max"])


func _set_zhan_wen(v: int) -> void:
	player.tokens[TOKEN_ZHAN_WEN]["num"] = clampi(v, 0, _wen_max())


func _set_mo_wen(v: int) -> void:
	player.tokens[TOKEN_MO_WEN]["num"] = clampi(v, 0, _wen_max())


# ============================================================
# 回合开始
# ============================================================
func p_turn_begin(_ctx: Dictionary) -> int:
	shuangChongHuiXiangUsed = false
	return SUCCESS


## 符文改造的重排【战纹】/【魔纹】选项（两者之和为 3）：每项一个按钮，
## 点哪个即以该项 args[0]（要保留的【战纹】数）作为技能参数提交
func _fu_wen_gai_zao_choices() -> Array:
	var out: Array = []
	for n: int in range(0, _wen_max() + 1):
		out.append({"text": GConst.按钮文本(FU_WEN_GAI_ZAO, 0, {"n": n, "n2": _wen_max() - n}), "args": [n]})
	return out


# ============================================================
# 启动技能（行动阶段按钮）：符文改造
# （「每回合只能发动一个启动技能」由引擎统一把关，这里只校验本技能自己的条件）
# ============================================================
func v_special_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != FU_WEN_GAI_ZAO:
		return GConst.GE_INVALID_ACTION
	# 宝石不足 1 点：不能发动
	if player.gem < 1:
		return GConst.GE_INVALID_ACTION
	var args: Array = action.get("args", [])
	# 对照原版 FuWenGaiZaoToken 的超时分支：没给重排值（超时）按 1 处理，发动照旧成立
	if not args.is_empty() and (int(args[0]) < 0 or int(args[0]) > _wen_max()):
		return GConst.GE_INVALID_ARGUMENT
	return GConst.GE_SUCCESS


func p_special_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != FU_WEN_GAI_ZAO:
		return GConst.GE_INVALID_ACTION
	return _apply_fu_wen_gai_zao(action)


## 符文改造：消耗 1 宝石转为蓄势迸发形态，手牌上限 +1 并摸 1 张牌，再按所选值重排【战纹】/【魔纹】
## 摸 1 张走 push_draw（延迟结算），压了就必须返回 URGENT：先摸完再压行动结束响应。
func _apply_fu_wen_gai_zao(action: Dictionary) -> int:
	var args: Array = action.get("args", [])
	# 对照原版：重排值缺省（超时）时按 1 处理
	var num: int = int(args[0]) if not args.is_empty() else 1
	notice_skill(FU_WEN_GAI_ZAO, [player.id])
	player.boot_skill_used = true
	player.set_gem(player.gem - 1)
	player.设手牌上限修正("符文改造", FU_WEN_HAND_ADD)
	engine.push_draw(player.id, 1)
	engine.set_tap(player.id, true)
	_set_zhan_wen(num)
	_set_mo_wen(_wen_max() - _zhan_wen())
	engine._broadcast_game()
	return URGENT


# ============================================================
# 主动攻击命中后：战纹碎击
# ============================================================


func p_timeline_2_hit(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	# 只要还有【战纹】、且手上凑得出 2 张牌就问（同系牌至少要 2 张，手牌不足 2 张根本选不出来）
	if _zhan_wen() == 0 or player.hand_count() < 2:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	var dst: int = int(ctx.get("dst", -1))
	return 多步询问(ZHAN_WEN_SUI_JI, [
		{"选项": _战纹碎击选项(), "需牌": 2, "牌规则": "same", "牌上限": player.hand_count(),
		 "目标白": [dst] if dst >= 0 else [],
		 "预览基准": int((ctx.get("harm", {}) as Dictionary).get("point", 0))},
	], func(答案: Array) -> int: return _战纹碎击结算(ctx, 答案))


## 战纹碎击的选项：额外翻转 Y 个【战纹】，value = 1 + Y（Y=0 表示不额外翻转）
func _战纹碎击选项() -> Array:
	var 选项: Array = []
	for y: int in range(0, 3):
		var 可用: bool = y == 0 or (player.tap and _zhan_wen() >= y + 1)
		var 名: String = 提示(ZHAN_WEN_SUI_JI, 1) if y == 0 else 提示(ZHAN_WEN_SUI_JI, 2, y)
		选项.append({"value": y + 1, "label": 名, "enabled": 可用})
	return 选项


## 战纹碎击：翻转 1 个战纹，弃 X 张同系牌，本次伤害 +(X-1)（可额外翻转 Y 个战纹，再 +Y）
func _战纹碎击结算(ctx: Dictionary, 答案: Array) -> int:
	var 回: Dictionary = 答案[0] if not 答案.is_empty() else {}
	var args: Array = 回.get("args", [])
	if args.is_empty() or int(args[0]) < 1:
		return SUCCESS
	var addition: int = int(args[0]) - 1
	var cards: Array = 回.get("cards", [])
	if _zhan_wen() < 1 or cards.size() < 2:
		return GConst.GE_INVALID_ARGUMENT
	if _element_check(cards) != ElementKind.AllSame or not _has_cards(cards):
		return GConst.GE_INVALID_CARDID
	_set_zhan_wen(_zhan_wen() - 1)
	_set_mo_wen(_mo_wen() + 1)
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
	engine.take_from_hand(player.id, cards, true)
	engine.to_discard(cards, {"owner": player.id, "source": "hand"})
	var harm: Dictionary = ctx.get("harm", {})
	harm["point"] = int(harm.get("point", 0)) + cards.size() - 1 + addition
	# 结算里压了伤害推进并返回 URGENT：引擎会重入本钩子，用 step 挡住（框架不接管重入）
	step = STEP_DONE
	engine._broadcast_game()
	return URGENT




# ============================================================
# 主动攻击未命中后：怒火压制 / 魔纹融合（两段式：先二选一，再选魔纹融合的翻转档）
#   用 BattleRole.多步询问 声明两段：第 1 段二选一，第 2 段翻转档（可「返回」=重问第 1 段）；
#   第 1 段选了怒火压制时第 2 段自动跳过（条件段）。
#   结算返回 URGENT（压了法术伤害）后引擎会重入本钩子：结算里把 step 置 STEP_DONE 挡住重入。
# ============================================================


func p_timeline_2_miss(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	var dst_id: int = int(ctx.get("dst", -1))
	return 多步询问(MO_WEN_RONG_HE, [
		{"选项": _nu_huo_选项(dst_id), "牌规则": "diff",
		 "目标白": [dst_id] if dst_id >= 0 else []},
		{"选项": _mo_wen_档选项(dst_id), "牌规则": "diff", "牌上限": player.hand_count(),
		 "目标白": [dst_id] if dst_id >= 0 else [],
		 "可返回": true,
		 "跳过": func(答案: Array) -> bool: return _nu_huo_选择(答案) != CHOICE_MO_WEN_RONG_HE},
	], func(答案: Array) -> int: return _nu_huo_结算(dst_id, 答案))


## 第 1 段选了什么（1＝怒火压制，2＝魔纹融合；没答就是 0）
func _nu_huo_选择(答案: Array) -> int:
	if 答案.is_empty():
		return 0
	var a: Array = (答案[0] as Dictionary).get("args", [])
	return int(a[0]) if not a.is_empty() else 0


## 第 1 段选项：怒火压制 2704 / 魔纹融合 2701 二选一（选魔纹融合只是进第二段，不结算）
func _nu_huo_选项(dst_id: int) -> Array:
	var 魔纹可用: bool = _mo_wen() >= 1 and player.hand_count() >= 2
	return [
		{"value": CHOICE_NU_HUO_YA_ZHI, "label": GConst.skill_desc_name(NU_HUO_YA_ZHI),
		 "skill_id": NU_HUO_YA_ZHI, "need_card": 0, "enabled": _zhan_wen() >= 1},
		{"value": CHOICE_MO_WEN_RONG_HE, "label": GConst.按钮原文(MO_WEN_RONG_HE, 0),
		 "skill_id": MO_WEN_RONG_HE, "need_card": 0, "enabled": 魔纹可用},
	]


## 第 2 段选项：魔纹融合的三个翻转档（客户端会在这三颗左边摆出技能本体，共四个按钮）
func _mo_wen_档选项(_dst_id: int) -> Array:
	var 有牌可弃: bool = player.hand_count() >= 2
	var 魔纹基础可用: bool = _mo_wen() >= 1 and 有牌可弃
	var 魔纹额外1可用: bool = player.tap and _mo_wen() >= 2 and 有牌可弃 \
		and (_wen_max() - _zhan_wen() - 1) >= 1
	var 魔纹额外2可用: bool = player.tap and _mo_wen() >= 3 and 有牌可弃 \
		and (_wen_max() - _zhan_wen() - 1) >= 2
	return [
		{"value": CHOICE_MO_WEN_RONG_HE, "label": GConst.按钮原文(MO_WEN_RONG_HE, 1),
		 "skill_id": MO_WEN_RONG_HE, "need_card": 2, "enabled": 魔纹基础可用},
		{"value": CHOICE_MO_WEN_RONG_HE + 1, "label": GConst.按钮原文(MO_WEN_RONG_HE, 2),
		 "skill_id": MO_WEN_RONG_HE, "need_card": 2, "enabled": 魔纹额外1可用},
		{"value": CHOICE_MO_WEN_RONG_HE + 2, "label": GConst.按钮原文(MO_WEN_RONG_HE, 3),
		 "skill_id": MO_WEN_RONG_HE, "need_card": 2, "enabled": 魔纹额外2可用},
	]


## 整条链走完：怒火压制当场结算；魔纹融合交给 _nu_huo_rong_he
func _nu_huo_结算(dst_id: int, 答案: Array) -> int:
	step = STEP_DONE
	var 选择: int = _nu_huo_选择(答案)
	if 选择 == CHOICE_NU_HUO_YA_ZHI:
		return _nu_huo_ya_zhi(dst_id)
	if 选择 < CHOICE_MO_WEN_RONG_HE or 答案.size() < 2:
		return SUCCESS
	var a1: Array = (答案[1] as Dictionary).get("args", [])
	var 档: int = int(a1[0]) if not a1.is_empty() else 0
	if 档 < CHOICE_MO_WEN_RONG_HE:
		return SUCCESS
	return _nu_huo_rong_he(dst_id, 档 - CHOICE_MO_WEN_RONG_HE, (答案[1] as Dictionary).get("cards", []))


## 【怒火压制】结算：翻转 1 个【战纹】为【魔纹】
func _nu_huo_ya_zhi(dst_id: int) -> int:
	if _zhan_wen() < 1:
		return SUCCESS
	notice_skill(NU_HUO_YA_ZHI, [dst_id])
	_set_zhan_wen(_zhan_wen() - 1)
	_set_mo_wen(_mo_wen() + 1)
	engine._broadcast_game()
	return SUCCESS


## 魔纹融合结算：弃 ≥2 张互异系牌【展示】，对目标造成 (张数 - 1 + 额外翻转数) 点法术伤害
func _nu_huo_rong_he(dst_id: int, addition: int, cards: Array) -> int:
	# 取消 / 没选够（客户端按 "diff" 规则拦着，正常提交到不了这）：当作放弃
	if cards.size() < 2:
		return SUCCESS
	if _mo_wen() < 1:
		return GConst.GE_INVALID_ARGUMENT
	if _element_check(cards) != ElementKind.AllDifferent or not _has_cards(cards):
		return GConst.GE_INVALID_CARDID
	# 额外翻转要本来的 1 个 + addition 个魔纹都够；先验再改，避免先扣资源后报错
	if _mo_wen() < 1 + addition:
		return GConst.GE_INVALID_ARGUMENT
	_set_zhan_wen(_zhan_wen() + 1)
	_set_mo_wen(_mo_wen() - 1)
	if addition > 0:
		_set_zhan_wen(_zhan_wen() + addition)
		_set_mo_wen(_mo_wen() - addition)
	notice_skill(MO_WEN_RONG_HE, [dst_id])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": cards, "is_real": true,
	})
	engine.push_harm({
		"src": player.id, "dst": dst_id, "point": cards.size() - 1 + addition,
		"cause": MO_WEN_RONG_HE, "type": GConst.HarmType.Magic,
	})
	engine.take_from_hand(player.id, cards, true)
	engine.to_discard(cards, {"owner": player.id, "source": "hand"})
	engine._broadcast_game()
	return URGENT


# ============================================================
# 对目标造成伤害时：双重回响
# ============================================================




func p_timeline_3(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("src", -1)) != player.id:
		return SUCCESS
	if player.get_energy() < 1 or shuangChongHuiXiangUsed:
		return SUCCESS
	return _shuang_chong_hui_xiang(harm)


func _shuang_chong_hui_xiang(harm: Dictionary) -> int:
	var from_dst: int = int(harm.get("dst", -1))
	# 不能选「当前正被这次伤害打中的人」：把合法目标（除他以外的所有人）一并下发，
	# 让那名角色的头像点不动；服务端这层校验也再挡一次（选了他就重问本段）
	var 合法目标: Array = []
	for pid: int in engine.order:
		if pid != from_dst:
			合法目标.append(pid)
	return 多步询问(SHUANG_CHONG_HUI_XIANG, [
		{"需目标": 1, "目标白": 合法目标,
		 "预览基准": mini(int(harm.get("point", 0)), 3),
		 "校验": func(回: Dictionary) -> bool:
			var ds: Array = 回.get("dsts", [])
			return not ds.is_empty() and int(ds[0]) != from_dst},
	], func(答案: Array) -> int: return _双重回响结算(harm, from_dst, 答案))


## 双重回响结算：扣 1 能量（水晶优先），对选中的目标复制本次伤害（与 3 取小）
func _双重回响结算(harm: Dictionary, from_dst: int, 答案: Array) -> int:
	var 回: Dictionary = 答案[0] if not 答案.is_empty() else {}
	var args: Array = 回.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		return SUCCESS
	var dsts: Array = 回.get("dsts", [])
	if dsts.is_empty():
		return SUCCESS
	var dst_id: int = int(dsts[0])
	if dst_id == from_dst:
		return SUCCESS
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
	player.设手牌上限修正("符文改造", 0)
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
