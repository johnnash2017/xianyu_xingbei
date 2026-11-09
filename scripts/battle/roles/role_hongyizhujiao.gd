extends BattleRole
## 红衣主教（roleID 111）
##
## 技能：
##   圣约银契 11101（被动）：【攻击行动】或【法术行动】结束时，你 +1【银制子弹】。
##   驱魔式 11102（启动）：移除 2 点【银制子弹】，我方目标角色弃 1 张牌【展示】；
##       若该弃牌为圣类命格，你 +1【治疗】并摸 1 张牌【强制】。
##   祷告式 11103（响应）：主动攻击前①，移除 1 点【银制子弹】，指定 1 名角色 +1【治疗】。
##   权能逆位 11104（法术）：移除 1 点【银制子弹】或我方合计 2【治疗】，你 +2【圣遗物】，
##       移除你的所有基础效果与【治疗】，将手牌弃到 4 张，角色卡替换为【铸律者】。
##   神宣祷言 11105（响应）：我方非因承受伤害而掉士气时，移除 1 点【圣遗物】抵御 1 点，你 +1【银制子弹】。
##   圣典 11106（启动 / 必杀技 / 水晶）：我方所有未拥有【治疗】的角色各 +1【治疗】。

const SHENG_YUE_YIN_QI: int = 11101
const QU_MO_SHI: int = 11102
const DAO_GAO_SHI: int = 11103
const QUAN_NENG_NI_WEI: int = 11104
const SHEN_XUAN_DAO_YAN: int = 11105
const SHENG_DIAN: int = 11106

## 指示物槽位（角色表 0:银制子弹:3;1:圣遗物:3）
const 银弹槽: int = 0
const 圣遗物槽: int = 1

## 权能逆位换成的角色
const 铸律者: int = 92

## 权能逆位：0＝还没结算 / 1＝已付费与清场 / 2＝正在等「弃到 4 张」/ 3＝该换角色了
var _权能阶段: int = 0
## 驱魔式：0＝还没付代价 / 1＝已付费，正在等目标弃牌
var _驱魔阶段: int = 0


# ============================================================
# 技能栏
# ============================================================
func available_skills() -> Array:
	var 我方: Array[int] = 我方角色()
	return [
		# 驱魔式：让我方一名有手牌的角色弃 1 张（目标自己点）
		{
			"type": GConst.ActionType.SpecialSkill,
			"id": QU_MO_SHI,
			"need_card": 0,
			"need_target": 1,
			"targets": 我方,
			"enabled": player.token_num(银弹槽) >= 2 and not 我方.is_empty(),
		},
		# 圣典：水晶
		{
			"type": GConst.ActionType.SpecialSkill,
			"id": SHENG_DIAN,
			"enabled": player.get_energy() >= 1,
		},
		# 权能逆位：两个付费用选项（1＝银制子弹 / 2＝我方合计 2 治疗）
		{
			"type": GConst.ActionType.MagicSkill,
			"id": QUAN_NENG_NI_WEI,
			"need_card": 0,
			"need_target": 0,
			"arg_choices": _权能费用选项(),
			"enabled": player.token_num(银弹槽) >= 1 or _我方治疗合计() >= 2,
		},
	]


func is_free_skill(skill_id: int) -> bool:
	return skill_id == QU_MO_SHI or skill_id == SHENG_DIAN


## 权能逆位的两档代价；做不了的那一档照样下发、置灰
func _权能费用选项() -> Array:
	return [
		{"value": 1, "label": GConst.按钮原文(QUAN_NENG_NI_WEI, 0),
			"text": GConst.按钮原文(QUAN_NENG_NI_WEI, 0),
			"enabled": player.token_num(银弹槽) >= 1},
		{"value": 2, "label": GConst.按钮原文(QUAN_NENG_NI_WEI, 1),
			"text": GConst.按钮原文(QUAN_NENG_NI_WEI, 1),
			"enabled": _我方治疗合计() >= 2},
	]


# ============================================================
# 圣约银契：攻击 / 法术行动结束 +1 银制子弹
# ============================================================
func p_after_attack(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	player.add_token(银弹槽, 1)
	engine._broadcast_game()
	return SUCCESS


func p_after_magic(ctx: Dictionary) -> int:
	return p_after_attack(ctx)


# ============================================================
# 祷告式：主动攻击前①，移 1 银制子弹，指定角色 +1 治疗（可选）
# ============================================================
func p_timeline_1(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id or not bool(ctx.get("is_active", false)):
		return SUCCESS
	if player.token_num(银弹槽) <= 0:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if not engine.has_reply():
		询问(player.id, DAO_GAO_SHI, 0, 1, GConst.CardSource.Hand, [], 0, "", [], true,
			0, -1, 全部角色(), -1, {}, 1, GConst.预览类型_治疗)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	var dsts: Array = r.get("dst_ids", [])
	if dsts.is_empty():
		return SUCCESS
	var dst: int = int(dsts[0])
	if engine.p(dst) == null:
		engine.报错("【祷告式】提交的目标不存在", player.id)
		return SUCCESS
	notice_skill(DAO_GAO_SHI, [dst])
	player.remove_token(银弹槽, 1)
	施加治疗(dst, 1)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 神宣祷言：我方非因承受伤害掉士气时，移 1 圣遗物抵御 1 点
# 掉士气链是同步调用（ctx.sync），这里只改 ctx、不开询问。
# ============================================================
func p_before_lose_morale(ctx: Dictionary) -> int:
	if int(ctx.get("type", GConst.HarmType.None)) != GConst.HarmType.None:
		return SUCCESS
	if int(ctx.get("amount", 0)) <= 0:
		return SUCCESS
	var dst: BattlePlayer = engine.p(int(ctx.get("dst", -1)))
	if dst == null or dst.color != player.color:
		return SUCCESS
	if player.token_num(圣遗物槽) <= 0:
		return SUCCESS
	ctx["amount"] = int(ctx.get("amount", 0)) - 1
	player.remove_token(圣遗物槽, 1)
	player.add_token(银弹槽, 1)
	return SUCCESS


# ============================================================
# 圣典：我方所有未拥有治疗的角色各 +1 治疗
# ============================================================
func v_special_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	var 技能号: int = int(action.get("action_id", 0))
	if 技能号 == SHENG_DIAN:
		if player.get_energy() < 1:
			return GConst.GE_INVALID_ACTION
		return GConst.GE_SUCCESS
	if 技能号 == QU_MO_SHI:
		if player.token_num(银弹槽) < 2:
			return GConst.GE_INVALID_ACTION
		var dsts: Array = action.get("dst_ids", [])
		if dsts.is_empty():
			return GConst.GE_INVALID_ARGUMENT
		var dp: BattlePlayer = engine.p(int(dsts[0]))
		if dp == null or dp.color != player.color or dp.hand_cards.is_empty():
			return GConst.GE_INVALID_ACTION
		return GConst.GE_SUCCESS
	return GConst.GE_INVALID_ACTION


func p_special_skill(action: Dictionary) -> int:
	var 技能号: int = int(action.get("action_id", 0))
	if 技能号 == SHENG_DIAN:
		return _圣典()
	if 技能号 == QU_MO_SHI:
		return _驱魔式(action)
	return SUCCESS


func _圣典() -> int:
	player.remove_energy(1)
	player.boot_skill_used = true
	var dsts: Array = []
	for pid: int in 我方角色全部():
		var p0: BattlePlayer = engine.p(pid)
		if p0 != null and p0.cross_num == 0:
			dsts.append(pid)
	notice_skill(SHENG_DIAN, dsts)
	for pid: int in dsts:
		施加治疗(int(pid), 1)
	engine._broadcast_game()
	return SUCCESS


## 驱魔式：付 2 点银制子弹 → 我方目标角色弃 1 张牌【展示】→ 圣类命格则 +1 治疗、摸 1 张
func _驱魔式(action: Dictionary) -> int:
	var 弃牌人: int = int((action.get("dst_ids", []) as Array)[0])
	var dp: BattlePlayer = engine.p(弃牌人)
	player.boot_skill_used = true
	if _驱魔阶段 == 0:
		player.remove_token(银弹槽, 2)
		notice_skill(QU_MO_SHI, [弃牌人])
		engine._broadcast_game()
		_驱魔阶段 = 1
	if _驱魔阶段 == 1:
		if not engine.has_reply():
			# 让对方自己选弃哪张（用标准弃牌应答，提示条会自动写成「【驱魔式】：请选择 1 张牌弃掉」）
			engine.ask_respond(弃牌人, GConst.RespondType.Discard, [弃牌人, QU_MO_SHI, 1], [弃牌人])
			engine.wait_for(弃牌人, GConst.Msg.Respond)
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		_驱魔阶段 = 0
		var cards: Array = r.get("card_ids", [])
		var 弃: int = -1
		if not cards.is_empty() and dp.has_discard_card(int(cards[0])):
			弃 = int(cards[0])
		else:
			# 强制弃牌：超时 / 空回复按手牌顺序补一张，不能白跳过
			弃 = int(dp.hand_cards[0])
		var 牌: GCard = Data.get_card(弃)
		# 「弃 1 张牌【展示】」：统一入口（亮牌 + 触发封印 + 离手 + 弃牌堆 + 日志）
		engine.展示手牌并弃(弃牌人, [弃], {"cause": QU_MO_SHI})
		if 牌 != null and 牌.fate_pattern_enum() == GConst.FatePattern.Holy:
			notice_skill(QU_MO_SHI, [弃牌人])
			施加治疗(player.id, 1)
			engine.push_强制摸牌(player.id, 1, QU_MO_SHI)
			engine._broadcast_game()
			return URGENT
		engine._broadcast_game()
	return SUCCESS


# ============================================================
# 权能逆位（法术技能）
# ============================================================
func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != QUAN_NENG_NI_WEI:
		return GConst.GE_INVALID_ACTION
	var args: Array = action.get("args", [])
	var 费用: int = int(args[0]) if not args.is_empty() else 0
	if 费用 == 1:
		if player.token_num(银弹槽) < 1:
			return GConst.GE_INVALID_ACTION
	elif 费用 == 2:
		if _我方治疗合计() < 2:
			return GConst.GE_INVALID_ACTION
	else:
		return GConst.GE_INVALID_ARGUMENT
	# 新的一次发动：清掉上一次的分步（v_* 只在技能开始时调用一次）
	_权能阶段 = 0
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	if _权能阶段 == 4:
		# 等施法者选从谁身上扣「我方合计 2 治疗」
		var r: Dictionary = take_skill_reply_full()
		_权能阶段 = 1
		_权能移除治疗(r.get("dst_ids", []))
		return _权能结算()
	if _权能阶段 == 1:
		return _权能结算()
	if _权能阶段 == 5:
		_权能阶段 = 0
		替换角色(铸律者)
		return SUCCESS
	var args: Array = action.get("args", [])
	var 费用: int = int(args[0]) if not args.is_empty() else 1
	notice_skill(QUAN_NENG_NI_WEI, [player.id])
	if 费用 == 2:
		var 有治疗: Array = player_ids_where(func(p: BattlePlayer) -> bool:
			return p.color == player.color and p.cross_num > 0, true)
		_权能阶段 = 4
		询问(player.id, QUAN_NENG_NI_WEI, 0, mini(2, 有治疗.size()), GConst.CardSource.Hand,
			[], 0, "", [], false, 0, -1, 有治疗, -1, {})
		return WAIT
	player.remove_token(银弹槽, 1)
	_权能阶段 = 1
	return _权能结算()


## 付费之后的固定结算：+2【圣遗物】、清掉自己的基础效果与治疗，手牌弃到 4 张，最后换【铸律者】
func _权能结算() -> int:
	_权能阶段 = 2
	# +2【圣遗物】：换角色时同名指示物会跟着走（见 engine.替换角色）
	player.add_token(圣遗物槽, 2)
	_移除全部基础效果与治疗()
	engine._broadcast_game()
	# 「将手牌弃到 4 张」只弃不摸：手牌不足 4 张时不能反向补牌（不能用 调整手牌到）
	if player.hand_cards.size() > 4:
		engine.push(BattleEngine.SHandAdjust.new(player.id, 4, QUAN_NENG_NI_WEI))
		return URGENT
	_权能阶段 = 0
	替换角色(铸律者)
	return SUCCESS


## 等「弃到 4 张」结算完再回来换角色（技能本体只走一次，靠这里放行）
func 技能URGENT后重入(_action: Dictionary = {}) -> bool:
	if _权能阶段 != 2:
		return false
	_权能阶段 = 5
	return true


## 移除自己的所有基础效果与治疗
func _移除全部基础效果与治疗() -> void:
	for be: Dictionary in player.basic_effects.duplicate():
		engine.remove_basic_effect(player.id, int(be["card"]), QUAN_NENG_NI_WEI, player.id)
	player.sub_cross_num(player.cross_num)


## 从玩家选中的我方角色身上各扣 1 点治疗；不够 2 点的部分继续从选中的 / 座位顺序补
func _权能移除治疗(dsts: Array) -> void:
	var 还需: int = 2
	var 已选: Array = []
	for d: Variant in dsts:
		if 还需 <= 0:
			break
		var p0: BattlePlayer = engine.p(int(d))
		if p0 == null or p0.cross_num <= 0 or 已选.has(p0.id):
			continue
		p0.sub_cross_num(1)
		还需 -= 1
		已选.append(p0.id)
	while 还需 > 0:
		var 扣到: bool = false
		for pid: int in (已选 if not 已选.is_empty() else 我方角色全部()):
			var p1: BattlePlayer = engine.p(pid)
			if p1 == null or p1.cross_num <= 0:
				continue
			p1.sub_cross_num(1)
			还需 -= 1
			扣到 = true
			break
		if not 扣到:
			break
	if 还需 > 0:
		engine.报错("【权能逆位】我方治疗不足 2 点", player.id)


func _我方治疗合计() -> int:
	var 总: int = 0
	for pid: int in 我方角色全部():
		var p0: BattlePlayer = engine.p(pid)
		if p0 != null:
			总 += p0.cross_num
	return 总


## 我方角色（含自己）
func 我方角色全部() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		var p0: BattlePlayer = engine.p(pid)
		if p0 != null and p0.color == player.color:
			out.append(pid)
	return out


## 我方有手牌的角色（驱魔式的可选目标）
func 我方角色() -> Array[int]:
	var out: Array[int] = []
	for pid: int in 我方角色全部():
		var p0: BattlePlayer = engine.p(pid)
		if p0 != null and not p0.hand_cards.is_empty():
			out.append(pid)
	return out


## 全部在场角色（含自己）：祷告式「目标角色」按术语表是可选场上任意角色
func 全部角色() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		out.append(pid)
	return out
