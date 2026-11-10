extends BattleRole
## 染污者（roleID 83）
##
## 技能：
##   神弃之裔 8301（被动）：开局 +1【水晶】；【治疗】上限恒定 0（拿不到、也没得用）；
##       你对拥有【治疗】的角色造成的伤害 +1。
##   戾如泉涌 8302（响应【回合限定】）：仅【普通形态】且【戾气】<上限时，
##       攻击 / 法术行动结束后 → +1【戾气】，额外 +1【攻击行动】。
##   狂戾之心 8303（被动【持续】）：你的回合开始 / 承受伤害后⑥，且【戾气】满时 →
##       弃 1 张牌、指定 1 名角色移除 2【治疗】、【横置】转为【狂戾形态】；
##       此形态下你无法用【圣光】、造成的伤害 +1；你的回合结束时若【戾气】为 0 →
##       【转正】脱离形态，并把 1【水晶】换成 1【宝石】。
##   狂戾之体 8304（被动）：仅【狂戾形态】且【戾气】>0，别人对你造成伤害时③ →
##       移除 1【戾气】，本次伤害 +1，但最高 4。
##   神智污染 8305（响应）：仅【狂戾形态】，你对目标造成伤害时③，移除 1【戾气】→
##       本次伤害 +1，且本次伤害无法用【治疗】抵御。
##   扭曲之爱 8306（启动【宝石】）：调整形态为【普通形态】/【狂戾形态】，
##       弃 2 张牌或摸 2 张牌【强制】，并任意调整【戾气】数。

const SHEN_QI_ZHI_YI: int = 8301
const LI_RU_QUAN_YONG: int = 8302
const KUANG_LI_ZHI_XIN: int = 8303
const KUANG_LI_ZHI_TI: int = 8304
const SHEN_ZHI_WU_RAN: int = 8305
const NIU_QU_ZHI_AI: int = 8306

## 【戾气】在角色表「指示物」里的槽位（0:戾气:2）
const 戾气槽: int = 0

# 【扭曲之爱】的状态变量见下面 8306 那一段（三段式）
var _戾如泉涌已用: bool = false


func setup(p: BattlePlayer, e: BattleEngine) -> void:
	super.setup(p, e)
	# 【神弃之裔】：游戏初始 +1【水晶】；治疗上限恒定 0（cross_max=0 时施加治疗一律加不进去）
	player.set_crystal(player.crystal + 1)
	player.cross_max = 0


## 【神弃之裔】：始终无法获得【治疗】（引擎 add_cross / add_cross_pierce 都会问这里）
func 禁止获得治疗() -> bool:
	return true


# ============================================================
# 技能栏：扭曲之爱（启动，消耗 1【宝石】）
# ============================================================
func available_skills() -> Array:
	return [{
		"type": GConst.ActionType.SpecialSkill,
		"id": NIU_QU_ZHI_AI,
		"need_card": 0,
		"need_target": 0,
		# 三段都是服务端询问（写法同【军神威光】）：点技能后第一段问形态，取消＝不发动
		"enabled": player.gem > 0,
	}]


func is_free_skill(skill_id: int) -> bool:
	return skill_id == NIU_QU_ZHI_AI


func v_special_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != NIU_QU_ZHI_AI:
		return GConst.GE_INVALID_ACTION
	# 【宝石】：只能用宝石付，不能拿水晶顶
	if player.gem <= 0:
		return GConst.GE_INVALID_ACTION
	# 新的一次发动：把上一次没走完的链清掉（同一条技能行动的重入不会走到这里）
	多步询问重置(NIU_QU_ZHI_AI)
	_扭曲已结算 = false
	return GConst.GE_SUCCESS


# ============================================================
# 【扭曲之爱】8306：三段询问（形态 → 弃/摸 → 戾气）
#   用 BattleRole.多步询问 声明三段，段之间不落副作用（弃牌 / 扣宝石 / 调戾气都在结算里做），
#   所以第二、三段「返回」不用撤账；第一段取消＝不发动。
# ============================================================
const 扭曲_弃张数: int = 2
const 扭曲_摸张数: int = 2
## 结算完压了摸牌状态（返回 URGENT）：引擎会把 p_special_skill 再调一次，
## 那一调不能再开一条新链（否则会把「形态」重新问一遍），用这个标记挡住。
var _扭曲已结算: bool = false


func p_special_skill(_action: Dictionary) -> int:
	if _扭曲已结算:
		_扭曲已结算 = false
		return SUCCESS
	return 多步询问(NIU_QU_ZHI_AI, [
		{"选项": _扭曲形态选项()},
		{"选项": _扭曲弃摸选项(), "可返回": true},
		{"选项": _扭曲戾气选项(), "可返回": true},
	], _扭曲结算)


## 三段都答完：扣宝石 → 调戾气 → 落形态 → 弃牌或摸牌
func _扭曲结算(答案: Array) -> int:
	var 形态: int = 0
	var 弃牌: bool = false
	var 弃: Array = []
	var 戾气: int = 0
	var a0: Array = (答案[0] as Dictionary).get("args", []) if 答案.size() > 0 else []
	if not a0.is_empty():
		形态 = 1 if int(a0[0]) == 1 else 0
	var a1: Array = (答案[1] as Dictionary).get("args", []) if 答案.size() > 1 else []
	弃牌 = not a1.is_empty() and int(a1[0]) == 1
	if 弃牌:
		# 有多少弃多少：手牌不足 2 张时按实际张数收（0 张就是空弃）
		var 需弃: int = mini(扭曲_弃张数, player.hand_cards.size())
		for c: Variant in (答案[1] as Dictionary).get("cards", []):
			var 实例: int = player.手牌实例(int(c))
			if 实例 >= 0 and not 弃.has(实例):
				弃.append(实例)
		if 弃.size() != 需弃:
			engine.报错("【扭曲之爱】提交的弃牌不合法", player.id)
			return SUCCESS
	var a2: Array = (答案[2] as Dictionary).get("args", []) if 答案.size() > 2 else []
	if not a2.is_empty():
		戾气 = clampi(int(a2[0]), 0, player.token_max(戾气槽))
	notice_skill(NIU_QU_ZHI_AI, [player.id])
	player.boot_skill_used = true
	player.set_gem(player.gem - 1)
	player.set_token_num(戾气槽, 戾气)
	player.tap = 形态 == 1
	engine._broadcast_game()
	if 弃牌:
		if not 弃.is_empty():
			engine.take_from_hand(player.id, 弃)
			engine.to_discard(弃, {"owner": player.id, "source": "hand", "cause": NIU_QU_ZHI_AI})
			engine._log_discard(player.id, 弃)
		return SUCCESS
	_扭曲已结算 = true
	engine.push_强制摸牌(player.id, 扭曲_摸张数, NIU_QU_ZHI_AI)
	return URGENT


## 第一段选项：调整形态
func _扭曲形态选项() -> Array:
	return [
		{"value": 0, "label": GConst.按钮原文(NIU_QU_ZHI_AI, 0)},
		{"value": 1, "label": GConst.按钮原文(NIU_QU_ZHI_AI, 1)},
	]


## 第二段选项：弃 2 张（当场选牌）/ 摸 2 张。
## 标题固定写 2 张，不随手牌数变化；手牌不足时照样能选 —— 实际是「有多少弃多少」（0 张＝空弃），
## 所以 need_card 给的是这一问实际要选的张数（min(2, 手牌数)），0 张时不用选牌也能确定。
func _扭曲弃摸选项() -> Array:
	var 需选: int = mini(扭曲_弃张数, player.hand_cards.size())
	return [
		{"value": 1, "label": GConst.按钮原文(NIU_QU_ZHI_AI, 2) % 扭曲_弃张数,
			"need_card": 需选},
		{"value": 2, "label": GConst.按钮原文(NIU_QU_ZHI_AI, 3) % 扭曲_摸张数},
	]


## 第三段选项：戾气 0..上限（按角色表「戾气」槽的上限枚举）
func _扭曲戾气选项() -> Array:
	var 上限: int = player.token_max(戾气槽)
	var out: Array = []
	for n: int in range(上限 + 1):
		out.append({"value": n, "label": GConst.按钮原文(NIU_QU_ZHI_AI, 4) % n})
	return out


# ============================================================
# 【回合限定】标记：自己的回合开始时重置
# ============================================================
func p_before_turn_begin(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) == player.id:
		_戾如泉涌已用 = false
	return SUCCESS


# ============================================================
# 戾如泉涌：攻击 / 法术行动结束时的可选响应（行动聚合器）
# ============================================================
func action_end_options(_ctx: Dictionary) -> Array:
	if _戾如泉涌已用 or player.tap or player.token_num(戾气槽) >= player.token_max(戾气槽):
		return []
	return [{
		"value": LI_RU_QUAN_YONG,
		"label": GConst.按钮原文(LI_RU_QUAN_YONG, 0),
		"skill_id": LI_RU_QUAN_YONG,
		"enabled": true,
	}]


func resolve_action_end_option(cause: int, _reply: Dictionary, _ctx: Dictionary) -> int:
	if cause != LI_RU_QUAN_YONG:
		return resolve_queued_extra_action(cause)
	_戾如泉涌已用 = true
	player.add_token(戾气槽, 1)
	notice_skill(LI_RU_QUAN_YONG, [player.id])
	# 额外攻击行动：点选即得，响应结束后由引擎直接进入那一份行动
	player.add_action(GConst.ActionType.Attack, LI_RU_QUAN_YONG, true)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 狂戾之心：回合开始 / 承受伤害后⑥，戾气满时变身
# ============================================================
func p_turn_begin(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	return _尝试狂戾变身()


func p_harm_end(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("dst", -1)) != player.id:
		return SUCCESS
	return _尝试狂戾变身()


## 戾气满且还在【普通形态】时，询问「弃 1 张牌 + 指定 1 名角色移除 2 治疗」，
## 成立后横置进入【狂戾形态】。
## 手牌为空不算「不能发动」：这一步照样触发，只是没有牌可弃（need_card 给 0）。
## 用多步询问框架：只有一段（选牌 + 选目标同一问），副作用在结算里做。
func _尝试狂戾变身() -> int:
	if player.tap or player.token_num(戾气槽) < player.token_max(戾气槽):
		return SUCCESS
	var 需弃: int = 1 if not player.hand_cards.is_empty() else 0
	return 多步询问(KUANG_LI_ZHI_XIN, [
		{"需牌": 需弃, "需目标": 1, "目标白": 全部角色(), "可取消": false},
	], _狂戾变身结算)


func _狂戾变身结算(答案: Array) -> int:
	var 回: Dictionary = 答案[0] if not 答案.is_empty() else {}
	var 选牌: Array = 回.get("cards", [])
	var 选目标: Array = 回.get("dsts", [])
	if 选目标.is_empty():
		return SUCCESS
	var dst: BattlePlayer = engine.p(int(选目标[0]))
	if dst == null:
		engine.报错("【狂戾之心】提交的目标不存在", player.id)
		return SUCCESS
	var card: int = -1
	if not player.hand_cards.is_empty():
		if 选牌.is_empty():
			return SUCCESS
		card = player.手牌实例(int(选牌[0]))
		if card < 0:
			engine.报错("【狂戾之心】提交的弃牌不在手牌里", player.id)
			return SUCCESS
	notice_skill(KUANG_LI_ZHI_XIN, [dst.id])
	if card >= 0:
		engine.take_from_hand(player.id, [card])
		engine.to_discard([card], {"owner": player.id, "source": "hand", "cause": KUANG_LI_ZHI_XIN})
		engine._log_discard(player.id, [card])
	# 「移除 2 治疗」：目标有多少扣多少
	dst.sub_cross_num(mini(2, dst.cross_num))
	player.tap = true
	engine._broadcast_game()
	return SUCCESS


## 【回合结束时若戾气为 0】转正脱离狂戾形态，1【水晶】→1【宝石】
func p_turn_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if not player.tap or player.token_num(戾气槽) > 0:
		return SUCCESS
	notice_skill(KUANG_LI_ZHI_XIN, [player.id])
	player.tap = false
	if player.crystal > 0:
		player.set_crystal(player.crystal - 1)
		player.set_gem(player.gem + 1)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 狂戾形态：无法使用【圣光】
#   用引擎的通用钩子表达：攻击询问 / 魔弹询问都会把 can_light 下发成 false（客户端把圣光置灰），
#   v_block 也统一拒绝 —— 不用自己在每个入口各写一遍
# ============================================================
func 能否使用圣光() -> bool:
	return not player.tap


# ============================================================
# 攻击「预告加伤」：应战询问里告诉被打的人这一下实际要挨多少
#   神弃之裔（目标有治疗 +1）＋ 狂戾形态（造成伤害 +1）—— 两项都在③结算，预告要算进去
# ============================================================
func p_attack_preview(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id or not bool(ctx.get("is_active", false)):
		return 0
	var dst: BattlePlayer = engine.p(int(ctx.get("dst", -1)))
	var 加: int = 0
	if dst != null and dst.cross_num > 0:
		加 += 1
	if player.tap:
		加 += 1
	return 加


# ============================================================
# 伤害时间线③：被动加伤 + 神智污染的可选加伤
#   神弃之裔：对拥有治疗的角色伤害 +1
#   狂戾形态：造成的伤害 +1
#   狂戾之体：别人打你时移 1 戾气，本次伤害 +1（最高 4）
# ============================================================
func p_timeline_3(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if harm.is_empty():
		return SUCCESS
	if step == 0:
		_被动改伤(harm)
		step = 1
	return _神智污染(harm)


## 被动加伤（每笔伤害只跑一次，见 p_timeline_3 的 step 守卫）
func _被动改伤(harm: Dictionary) -> void:
	var src: int = int(harm.get("src", -1))
	var dst_id: int = int(harm.get("dst", -1))
	# 已经被挡成 0 点的伤害不再「加伤」，否则会凭空造出伤害
	if int(harm.get("point", 0)) <= 0:
		return
	if src == player.id and dst_id != player.id:
		var dst: BattlePlayer = engine.p(dst_id)
		if dst != null and dst.cross_num > 0:
			# 【神弃之裔】：对拥有【治疗】的角色伤害 +1 —— 技能名飘在**自己**头上（是我发动的）
			notice_skill(SHEN_QI_ZHI_YI, [player.id])
			harm["point"] = int(harm.get("point", 0)) + 1
		if player.tap:
			# 【狂戾之心】：狂戾形态下你造成的伤害 +1 —— 同样飘在自己头上
			notice_skill(KUANG_LI_ZHI_XIN, [player.id])
			harm["point"] = int(harm.get("point", 0)) + 1
	if dst_id == player.id and src != player.id and player.tap and player.token_num(戾气槽) > 0:
		if int(harm.get("point", 0)) > 0:
			player.remove_token(戾气槽, 1)
			harm["point"] = mini(int(harm.get("point", 0)) + 1, 4)
			# 【狂戾之体】：承受伤害 +1 —— 飘在自己头上
			notice_skill(KUANG_LI_ZHI_TI, [player.id])
			engine._broadcast_game()


## 神智污染：狂戾形态下你对目标造成伤害时可选发动（移 1 戾气换 +1 且禁治疗抵御）
## 用多步询问框架（只有一段「确认」），结算里改伤害。
func _神智污染(harm: Dictionary) -> int:
	if not player.tap or player.token_num(戾气槽) <= 0:
		return SUCCESS
	var src: int = int(harm.get("src", -1))
	var dst: int = int(harm.get("dst", -1))
	if src != player.id or dst == player.id:
		return SUCCESS
	if int(harm.get("point", 0)) <= 0:
		return SUCCESS
	if bool(harm.get("神智污染已处理", false)) and not 多步询问进行中(SHEN_ZHI_WU_RAN):
		return SUCCESS
	harm["神智污染已处理"] = true
	return 多步询问(SHEN_ZHI_WU_RAN, [
		{"目标白": [dst] if dst >= 0 else [],
		 "预览基准": int(harm.get("point", 0)),
		 "预览类型": int(harm.get("type", GConst.HarmType.None))},
	], func(答案: Array) -> int: return _神智污染结算(harm, 答案))


func _神智污染结算(harm: Dictionary, 答案: Array) -> int:
	var a: Array = (答案[0] as Dictionary).get("args", []) if 答案.size() > 0 else []
	if a.is_empty() or int(a[0]) != 1:
		return SUCCESS
	notice_skill(SHEN_ZHI_WU_RAN, [int(harm.get("dst", -1))])
	player.remove_token(戾气槽, 1)
	harm["point"] = int(harm.get("point", 0)) + 1
	# 本次伤害无法用【治疗】抵御（SAskCross 看到 cross_available=0 就不问治疗）
	harm["cross_available"] = 0
	engine._broadcast_game()
	return SUCCESS


## 全部在场角色（含自己）：狂戾之心「指定目标角色」按术语表是可选场上任意角色
func 全部角色() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		out.append(pid)
	return out
