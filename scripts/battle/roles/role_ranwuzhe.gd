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

## 扭曲之爱的两次询问：1＝选形态与弃/摸，2＝选戾气数（见 p_special_skill）
var _扭曲阶段: int = 0
## 第一次询问选中的形态（0＝普通、1＝狂戾）、以及是不是「弃 2 张」
var _扭曲形态: int = 0
var _扭曲弃牌: bool = false
var _戾如泉涌已用: bool = false


func setup(p: BattlePlayer, e: BattleEngine) -> void:
	super.setup(p, e)
	# 【神弃之裔】：游戏初始 +1【水晶】；治疗上限恒定 0（cross_max=0 时施加治疗一律加不进去）
	player.set_crystal(player.crystal + 1)
	player.cross_max = 0


# ============================================================
# 技能栏：扭曲之爱（启动，消耗 1【宝石】）
# ============================================================
func available_skills() -> Array:
	return [{
		"type": GConst.ActionType.SpecialSkill,
		"id": NIU_QU_ZHI_AI,
		"need_card": 0,
		"need_target": 0,
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
	return GConst.GE_SUCCESS


# ============================================================
# 扭曲之爱：两次询问（形态+弃/摸 → 戾气数）。
# 第一种选择的空间是「形态 2 × 弃/摸 2 × 戾气 0..上限」＝十几个组合，摆成一条询问的
# 选项会糊成一片；这里按「一次只问一件事、且上一问的代价当场结算」拆成两问：
# 第一问选形态与弃/摸并把要弃的牌一起选掉，第二问只选戾气数（不可取消）。
# ============================================================
func p_special_skill(_action: Dictionary) -> int:
	if _扭曲阶段 == 0:
		_扭曲阶段 = 1
		询问(player.id, NIU_QU_ZHI_AI, 0, 0, GConst.CardSource.Hand, _扭曲首问选项(),
			0, "", [], true, 0, -1, [], -1, {}, 0, 0, false)
		return WAIT
	if _扭曲阶段 == 1:
		var r: Dictionary = take_skill_reply_full()
		var args: Array = r.get("args", [])
		if args.is_empty():
			# 第一问取消＝不发动：不扣宝石、什么都不做
			_扭曲阶段 = 0
			return SUCCESS
		var 选择: int = int(args[0])
		if 选择 < 0 or 选择 > 3:
			_扭曲阶段 = 0
			return SUCCESS
		_扭曲形态 = 选择 % 2
		_扭曲弃牌 = 选择 < 2
		if _扭曲弃牌:
			var cards: Array = r.get("card_ids", [])
			if cards.size() != 2 or int(cards[0]) == int(cards[1]) \
					or not player.has_hand_card(int(cards[0])) \
					or not player.has_hand_card(int(cards[1])):
				engine.报错("【扭曲之爱】提交的弃牌不合法", player.id)
				_扭曲阶段 = 0
				return SUCCESS
			# 代价先结（技能维护约定：先选的那一档代价要先结算完，再问下一档）
			engine.to_discard(cards, {"owner": player.id, "source": "hand", "cause": NIU_QU_ZHI_AI})
		_扭曲阶段 = 2
		询问(player.id, NIU_QU_ZHI_AI, 0, 0, GConst.CardSource.Hand, _扭曲戾气选项(),
			0, "", [], false, 0, -1, [], -1, {}, 0, 0, false)
		return WAIT
	# 第二问：戾气数
	var r2: Dictionary = take_skill_reply_full()
	_扭曲阶段 = 0
	var args2: Array = r2.get("args", [])
	var 值: int = int(args2[0]) if not args2.is_empty() else 0
	notice_skill(NIU_QU_ZHI_AI, [player.id])
	player.boot_skill_used = true
	player.set_gem(player.gem - 1)
	player.set_token_num(戾气槽, 值)
	# 形态最后落：改形态会压入一轮 p_tap 钩子，放在两次询问都收完之后（约定 §19）
	player.tap = _扭曲形态 == 1
	engine._broadcast_game()
	if _扭曲弃牌:
		return SUCCESS
	engine.push_强制摸牌(player.id, 2, NIU_QU_ZHI_AI)
	return URGENT


## 第一问的 4 个选项：形态 × 弃 2 张 / 摸 2 张。弃牌的档位自带 need_card=2。
func _扭曲首问选项() -> Array:
	var 能弃: bool = player.hand_cards.size() >= 2
	var out: Array = []
	for i: int in range(4):
		out.append({
			"value": i,
			"label": GConst.按钮原文(NIU_QU_ZHI_AI, i),
			"text": GConst.按钮原文(NIU_QU_ZHI_AI, i),
			"need_card": 2 if i < 2 else 0,
			"enabled": 能弃 if i < 2 else true,
		})
	return out


## 第二问：戾气 0..上限，按角色表「戾气」槽的上限枚举（上限 2 → 3 个按钮）。
func _扭曲戾气选项() -> Array:
	var 上限: int = player.token_max(戾气槽)
	var out: Array = []
	for n: int in range(上限 + 1):
		out.append({
			"value": n,
			"label": GConst.按钮原文(NIU_QU_ZHI_AI, 4 + n),
			"text": GConst.按钮原文(NIU_QU_ZHI_AI, 4 + n),
		})
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
func _尝试狂戾变身() -> int:
	if player.tap or player.token_num(戾气槽) < player.token_max(戾气槽):
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if not engine.has_reply():
		询问(player.id, KUANG_LI_ZHI_XIN, 1, 1, GConst.CardSource.Hand, [],
			0, "", [], true, 0, -1, 全部角色(), -1, {})
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	var cards: Array = r.get("card_ids", [])
	var dsts: Array = r.get("dst_ids", [])
	if cards.is_empty() or dsts.is_empty():
		return SUCCESS
	var card: int = int(cards[0])
	if not player.has_hand_card(card):
		engine.报错("【狂戾之心】提交的弃牌不在手牌里", player.id)
		return SUCCESS
	var dst: BattlePlayer = engine.p(int(dsts[0]))
	if dst == null:
		engine.报错("【狂戾之心】提交的目标不存在", player.id)
		return SUCCESS
	notice_skill(KUANG_LI_ZHI_XIN, [dst.id])
	engine.to_discard([card], {"owner": player.id, "source": "hand", "cause": KUANG_LI_ZHI_XIN})
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
# 狂戾形态：无法使用【圣光】格挡（攻击 / 魔弹都走 v_block）
# ============================================================
func v_block(_card_id: int) -> int:
	if not player.tap:
		return V_NOT_OVERRIDE
	return GConst.GE_INVALID_CARDID


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
			harm["point"] = int(harm.get("point", 0)) + 1
		if player.tap:
			harm["point"] = int(harm.get("point", 0)) + 1
	if dst_id == player.id and src != player.id and player.tap and player.token_num(戾气槽) > 0:
		if int(harm.get("point", 0)) > 0:
			player.remove_token(戾气槽, 1)
			harm["point"] = mini(int(harm.get("point", 0)) + 1, 4)
			notice_skill(KUANG_LI_ZHI_TI, [player.id])
			engine._broadcast_game()


## 神智污染：狂戾形态下你对目标造成伤害时可选发动（移 1 戾气换 +1 且禁治疗抵御）
func _神智污染(harm: Dictionary) -> int:
	if not player.tap or player.token_num(戾气槽) <= 0:
		return SUCCESS
	if int(harm.get("src", -1)) != player.id or int(harm.get("dst", -1)) == player.id:
		return SUCCESS
	if int(harm.get("point", 0)) <= 0:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if not engine.has_reply():
		var dst: int = int(harm.get("dst", -1))
		询问(player.id, SHEN_ZHI_WU_RAN, 0, 0, GConst.CardSource.Hand, [], 0, "", [], true,
			0, -1, [dst] if dst >= 0 else [], -1, {},
			int(harm.get("point", 0)), int(harm.get("type", GConst.HarmType.None)))
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
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
