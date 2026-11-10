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

## 【扭曲之爱】三段式（形态 → 弃/摸 → 戾气），写法同魔弓【魔眼】：
## 第一段在二级技能栏里选（可「返回」退出、不扣宝石），后两段是服务端询问，
## 空应答＝退回上一段重问（指示器 选项可返回，客户端会摆「返回」）。
const 扭曲_弃张数: int = 2
const 扭曲_摸张数: int = 2
## 0＝未开始 / 1＝重问形态（第二段返回时）/ 2＝等选弃或摸 / 3＝等选戾气
var _扭曲段: int = 0
var _扭曲形态: int = 0
## 第二段选的是「弃」还是「摸」；弃哪几张先记下来，等三段都选完再一起结算
var _扭曲弃牌: bool = true
var _扭曲弃: Array = []
var _戾如泉涌已用: bool = false
## 狂戾之心：0＝未问 / 1＝等选弃牌 + 目标
var _狂戾阶段: int = 0


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
		# 第一段（调整形态）在二级技能栏里选：点技能才进、可「返回」退出，不扣宝石（同魔弓【魔眼】）
		"arg_choices": _扭曲形态选项(),
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
# 【扭曲之爱】8306：三段式（形态 → 弃/摸 → 戾气）
#   第一段：点技能进二级技能栏选形态（可「返回」退出，不发动、不扣宝石）
#   第二段：选「你弃 2 张牌」（当场选好 2 张一起确认）或「你摸 2 张牌」
#   第三段：选「调整【戾气】为 X」
#   第二/三段都是服务端询问，空应答＝退回上一段重问（指示器 选项可返回）；
#   弃的牌先记下来，三段选完才和费用一起结算 —— 中途返回不会白弃牌。
# ============================================================
func p_special_skill(action: Dictionary) -> int:
	while true:
		match _扭曲段:
			0:
				var a0: Array = action.get("args", [])
				_扭曲形态 = 1 if (not a0.is_empty() and int(a0[0]) == 1) else 0
				_扭曲段 = 2
			2:
				if not engine.has_reply():
					询问(player.id, NIU_QU_ZHI_AI, 0, 0, GConst.CardSource.Hand, _扭曲弃摸选项(),
						0, "", [], true, 0, -1, [], -1, {}, 0, 0, false)
					return WAIT
				var r: Dictionary = take_skill_reply_full()
				var 选: Array = r.get("args", [])
				if 选.is_empty() or int(选[0]) <= 0:
					# 返回：重问形态一段（再取消一次才是「不发动」）
					_扭曲段 = 1
					continue
				if int(选[0]) == 1:
					# 有多少弃多少：手牌不足 2 张时按实际张数收（0 张就是空弃）
					var 需弃: int = mini(扭曲_弃张数, player.hand_cards.size())
					var 弃: Array = []
					for c: Variant in r.get("card_ids", []):
						var 实例: int = player.手牌实例(int(c))
						if 实例 >= 0 and not 弃.has(实例):
							弃.append(实例)
					if 弃.size() != 需弃:
						engine.报错("【扭曲之爱】提交的弃牌不合法", player.id)
						_扭曲段 = 0
						return SUCCESS
					_扭曲弃牌 = true
					_扭曲弃 = 弃
				else:
					_扭曲弃牌 = false
					_扭曲弃 = []
				_扭曲段 = 3
			3:
				if not engine.has_reply():
					询问(player.id, NIU_QU_ZHI_AI, 0, 0, GConst.CardSource.Hand, _扭曲戾气选项(),
						0, "", [], true, 0, -1, [], -1, {}, 0, 0, false)
					return WAIT
				var r3: Dictionary = take_skill_reply_full()
				var a3: Array = r3.get("args", [])
				if a3.is_empty() or int(a3[0]) < 0:
					_扭曲段 = 2
					continue
				var 值: int = clampi(int(a3[0]), 0, player.token_max(戾气槽))
				_扭曲段 = 0
				return _扭曲结算(值)
			_:
				# 1＝重问形态（第二段返回时）：选了就接着问第二段，取消＝不发动
				if not engine.has_reply():
					询问(player.id, NIU_QU_ZHI_AI, 0, 0, GConst.CardSource.Hand, _扭曲形态选项(),
						0, "", [], true, 0, -1, [], -1, {}, 0, 0, false)
					return WAIT
				var rf: Dictionary = take_skill_reply_full()
				var af: Array = rf.get("args", [])
				if af.is_empty() or int(af[0]) < 0:
					_扭曲段 = 0
					return SUCCESS
				_扭曲形态 = 1 if int(af[0]) == 1 else 0
				_扭曲段 = 2
	return SUCCESS


## 第一段：调整形态（arg_choices 与询问共用同一份：arg_choices 读 text/args，询问读 label/value）
func _扭曲形态选项() -> Array:
	return [
		{"value": 0, "args": [0],
			"label": GConst.按钮原文(NIU_QU_ZHI_AI, 0), "text": GConst.按钮原文(NIU_QU_ZHI_AI, 0)},
		{"value": 1, "args": [1],
			"label": GConst.按钮原文(NIU_QU_ZHI_AI, 1), "text": GConst.按钮原文(NIU_QU_ZHI_AI, 1)},
	]


## 第二段：弃 2 张（当场选牌）/ 摸 2 张。
## 标题固定写 2 张，不随手牌数变化；手牌不足时照样能选 —— 实际是「有多少弃多少」（0 张＝空弃），
## 所以 need_card 给的是这一问实际要选的张数（min(2, 手牌数)），0 张时不用选牌也能确定。
func _扭曲弃摸选项() -> Array:
	var 需选: int = mini(扭曲_弃张数, player.hand_cards.size())
	return [
		{"value": 1, "label": GConst.按钮原文(NIU_QU_ZHI_AI, 2) % 扭曲_弃张数,
			"need_card": 需选},
		{"value": 2, "label": GConst.按钮原文(NIU_QU_ZHI_AI, 3) % 扭曲_摸张数},
	]


## 第三段：戾气 0..上限（按角色表「戾气」槽的上限枚举）
func _扭曲戾气选项() -> Array:
	var 上限: int = player.token_max(戾气槽)
	var out: Array = []
	for n: int in range(上限 + 1):
		out.append({"value": n, "label": GConst.按钮原文(NIU_QU_ZHI_AI, 4) % n})
	return out


## 三段都选完：扣宝石 → 调戾气 → 落形态 → 弃牌或摸牌
func _扭曲结算(戾气值: int) -> int:
	notice_skill(NIU_QU_ZHI_AI, [player.id])
	player.boot_skill_used = true
	player.set_gem(player.gem - 1)
	player.set_token_num(戾气槽, 戾气值)
	player.tap = _扭曲形态 == 1
	engine._broadcast_game()
	if _扭曲弃牌:
		var 弃: Array = _扭曲弃
		_扭曲弃 = []
		if not 弃.is_empty():
			engine.take_from_hand(player.id, 弃)
			engine.to_discard(弃, {"owner": player.id, "source": "hand", "cause": NIU_QU_ZHI_AI})
			engine._log_discard(player.id, 弃)
		return SUCCESS
	engine.push_强制摸牌(player.id, 扭曲_摸张数, NIU_QU_ZHI_AI)
	return URGENT


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
	# 「你弃 1 张牌」是代价：手里一张牌都没有时这段结算不了，等下次触发
	if player.hand_cards.is_empty():
		return SUCCESS
	if _狂戾阶段 == 0:
		_狂戾阶段 = 1
		询问(player.id, KUANG_LI_ZHI_XIN, 1, 1, GConst.CardSource.Hand, [],
			0, "", [], false, 0, -1, 全部角色(), -1, {})
		return WAIT
	_狂戾阶段 = 0
	var r: Dictionary = take_skill_reply_full()
	var cards: Array = r.get("card_ids", [])
	var dsts: Array = r.get("dst_ids", [])
	if cards.is_empty() or dsts.is_empty():
		return SUCCESS
	var card: int = player.手牌实例(int(cards[0]))
	if card < 0:
		engine.报错("【狂戾之心】提交的弃牌不在手牌里", player.id)
		return SUCCESS
	var dst: BattlePlayer = engine.p(int(dsts[0]))
	if dst == null:
		engine.报错("【狂戾之心】提交的目标不存在", player.id)
		return SUCCESS
	notice_skill(KUANG_LI_ZHI_XIN, [dst.id])
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
