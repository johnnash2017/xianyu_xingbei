extends BattleRole
## 异教徒（95）：异端邪说 / 审判 / 献祭 / 末日预言 / 放逐 / 贪婪
##
## 【末日预言】＝场卡（F1）：id = "末日预言"，owner = 自己，counter = 【预言】张数（上限 6），
## pile = 隐藏的【预言】牌（实例号）。翻面之后 id 变成 "天雷劫火" / "地裂波涛"（state 记 1/2）。
##
## 口径：
## 1. 【异端邪说】开局 +1 水晶；【末日预言】在场时手牌上限 -1（每次自己回合开始重算）。
## 2. 【末日预言】的「因承受伤害摸牌时第 1 张改从【预言】处获得」用 F8 同步钩子
##    伤害摸牌替换(pid)：任意角色因伤害摸牌都生效；从预言堆顶取 1 张、张数 -1。
## 3. 翻面：预言堆**取空的那一次结算完**，按【放逐】时记在场卡 front 的正面直接翻面
##    （没有 front 数据就什么都不做；不询问、不随机），移除【末日预言】、
##    换一张同名场卡入场，然后立刻结算它的「展示时」效果。
##    展示结算完把 _翻面步 归零（【放逐】放进新的【末日预言】后还能再翻一次）。
## 4. 【天雷劫火】/【地裂波涛】「展示时」：四系选项板（本被动两个系可发，另一个被动两个系置灰），
##    **系别、弃牌、目标都在同一次询问里选完**（弃 X 张该系牌 ≤4，可为 0；1 名目标对手）→
##    摸 X 张【强制】→ 目标自选弃任意张该系牌【展示】（可弃 0 张但不可取消）→
##    造成 X+1 点法术伤害③。非贪婪选一项；【贪婪】9506 花 1 点能量改成两项都发动：
##    不再问先后顺序，发完一项该项置灰、回板子继续选另一项，直到没有可发项。
##    结算后场卡**不立刻移除**，留到异教徒自己回合开始的【灾殃止息】9509 再移除。
## 5. 【审判】逐名队友问「弃 1 张牌【展示】」，然后各自摸 1 张【强制】，再由你选 1 张弃牌
##    交给目标对手；【末日预言】在场时其余弃牌洗混放到预言堆顶。
## 6. 【放逐】「无视手牌上限摸 6-8 张」＝本次结算期间进入「不爆牌」状态（引擎 进入不爆牌() /
##    解除不爆牌()），不是临时改手牌上限：状态期间手牌超上限也不结算超限，结算完才解除。
##    放置时从【天雷劫火】/【地裂波涛】里二选一作为这张【末日预言】的正面（记在场卡 "front"，
##    翻面时直接用，不再问）；随后由玩家自己选 6 张手牌洗混作为【预言】。
##    「额外 +1【攻击行动】或【法术行动】」＝一份攻击 / 法术都能用的额外行动（AttackMagic）。

const YI_DUAN_XIE_SHUO: int = 9501
const SHEN_PAN: int = 9502
const XIAN_JI: int = 9503
const MO_RI_YU_YAN: int = 9504
const FANG_ZHU: int = 9505
const TAN_LAN: int = 9506
## 专属技关键词：翻面后的两张（展示时发动）、以及回合开始移除它们的被动
const TIAN_LEI_JIE_HUO: int = 9507
const DI_LIE_BO_TAO: int = 9508
const ZAI_YANG_ZHI_XI: int = 9509

const 末日预言名: String = "末日预言"
const 天雷劫火名: String = "天雷劫火"
const 地裂波涛名: String = "地裂波涛"
const 预言上限: int = 6

## 本回合被【审判】造成过伤害的对手：既是发动条件，也是给弃牌的可选目标
## （技能条件「对目标角色造成伤害」指任意一个被你伤害过的对手，不是随便挑一个）
var _本回合伤害目标: Array[int] = []
## 本回合【审判】已经发动过：回合结束钩子会被引擎多次重入，没有它每次回来都会再问一遍
var _审判已发动: bool = false
## 审判：上一名队友弃牌结算完后，还欠他 1 张【强制】摸牌（弃 + 摸结算完再轮下一名）
var _审判待摸: int = -1
## 【放逐】回合限定：每回合只能发动一次（同圣女【圣疗】的 used_ 标记做法）
var _本回合已用放逐: bool = false
## 审判进度
var _审判步: int = 0
var _审判下标: int = 0
var _审判弃牌: Array[int] = []
var _审判对手: int = -1
## 审判：把哪一张弃牌交给对手（_审判弃牌 的下标）
var _审判给: int = 0
## 翻面 / 展示时的进度
var _翻面步: int = 0
## 伤害摸牌把最后一张【预言】抽空：等这次伤害结算完（p_harm_end）再翻面
var _待翻面检查: bool = false
var _展示系: int = 0
var _展示X: int = 0
var _展示对手: int = -1
## 展示时这一轮要依次结算的系别（贪婪＝两项都发动，顺序由玩家选）
## 贪婪时已经发动过的系别（选项板上置灰）
var _展示已用: Array[int] = []
var _展示贪婪: bool = false


func setup(p: BattlePlayer, e: BattleEngine) -> void:
	super.setup(p, e)
	# 【异端邪说】：游戏初始时你 +1【水晶】
	player.set_crystal(player.crystal + 1)


# ============================================================
# 技能栏
# ============================================================
func available_skills() -> Array:
	var 有末日: bool = engine.有场卡(末日预言名)
	var 手牌: Array[int] = player.hand_cards.duplicate()
	return [
		{
			# 献祭是「启动」：技能类型必须是 SpecialSkill（引擎按这个 + is_free_skill 判启动，
			# 才能走「每回合只能发动一个启动技」「启动技与特殊行动互斥」那套约束），
			# 不能写成 MagicSkill —— 否则它会当成法术行动去消耗放逐给的额外行动
			"type": GConst.ActionType.SpecialSkill,
			"id": XIAN_JI,
			"enabled": 有末日 and engine.取场卡(末日预言名).get("pile", []).size() > 0,
			# 和魔弓【魔眼】一样：点技能直接进二级技能栏选系别，可以按「返回」退出来；
			# 选项带系别标色（光/暗也在内）
			"arg_choices": _献祭系别选项(),
		},
		{
			"type": GConst.ActionType.MagicSkill,
			"id": FANG_ZHU,
			"enabled": player.get_energy() >= 1 and not _本回合已用放逐,
			# 和魔弓【魔眼】一样：点技能直接进二级技能栏，三个抽牌档在那里选；
			# 不选就按「返回」退出来，不扣能量也不发动
			"arg_choices": [
				{"text": GConst.按钮原文(FANG_ZHU, 0), "args": [6]},
				{"text": GConst.按钮原文(FANG_ZHU, 1), "args": [7]},
				{"text": GConst.按钮原文(FANG_ZHU, 2), "args": [8]},
			],
		},
	]


func is_free_skill(skill_id: int) -> bool:
	return skill_id == XIAN_JI


func v_special_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != XIAN_JI:
		return GConst.GE_INVALID_ACTION
	if not engine.有场卡(末日预言名):
		return GConst.GE_INVALID_ACTION
	if (engine.取场卡(末日预言名).get("pile", []) as Array).is_empty():
		return GConst.GE_INVALID_ACTION
	# 系别由二级技能栏的选项给出（args[0]），必须是 7 系之一
	var 献祭参数: Array = action.get("args", [])
	if 献祭参数.is_empty() or not _献祭系别().has(int(献祭参数[0])):
		return GConst.GE_INVALID_ARGUMENT
	return GConst.GE_SUCCESS


func p_special_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != XIAN_JI:
		return EMPTY_HANDLE
	var 参数: Array = action.get("args", [])
	if 参数.is_empty():
		return GConst.GE_INVALID_ARGUMENT
	return _p_献祭(int(参数[0]))


func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	match int(action.get("action_id", 0)):
		FANG_ZHU:
			if player.get_energy() < 1 or _本回合已用放逐:
				return GConst.GE_INVALID_ACTION
			var 参数: Array = action.get("args", [])
			if 参数.is_empty() or int(参数[0]) < 6 or int(参数[0]) > 8:
				return GConst.GE_INVALID_ARGUMENT
			return GConst.GE_SUCCESS
	return GConst.GE_INVALID_ACTION


func p_magic_skill(action: Dictionary) -> int:
	match int(action.get("action_id", 0)):
		FANG_ZHU:
			var 张: Array = action.get("args", [])
			return _p_放逐(int(张[0]) if not 张.is_empty() else 6)
	return EMPTY_HANDLE


# ============================================================
# 9501 异端邪说
# ============================================================
func p_before_turn_begin(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	_本回合伤害目标.clear()
	_审判已发动 = false
	_本回合已用放逐 = false
	# 献祭 / 审判流程残留都清掉，避免下一回合被旧步骤挡住
	_献祭步 = 0
	_献祭系 = 0
	_待翻面检查 = false
	# 审判流程残留在任何一步都清掉：否则下一步的 p_turn_end 会被「_审判步 != 0」挡住，
	# 表现为「偶尔触发不了」
	_审判步 = 0
	_审判下标 = 0
	_审判弃牌 = []
	_审判待摸 = -1
	_重算手牌上限()
	# 【灾殃止息】：回合开始时若存在【天雷劫火】/【地裂波涛】→ 移除
	if engine.有场卡(天雷劫火名) or engine.有场卡(地裂波涛名):
		notice_skill(ZAI_YANG_ZHI_XI, [player.id])
		if engine.有场卡(天雷劫火名):
			engine.移除场卡(天雷劫火名)
		if engine.有场卡(地裂波涛名):
			engine.移除场卡(地裂波涛名)
		engine._broadcast_game()
	return SUCCESS


func _重算手牌上限() -> void:
	player.设手牌上限修正("末日预言", -1 if engine.有场卡(末日预言名) else 0)


## 记录本回合被你造成过伤害的对手（【审判】条件 + 给牌目标白名单）；
## 顺带处理「预言抽空」的翻面 —— 等这次伤害全部结算完（p_harm_end）再问。
func p_harm_end(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) == player.id:
		var dst: BattlePlayer = engine.p(int(ctx.get("dst", -1)))
		if dst != null and dst.color != player.color and not _本回合伤害目标.has(dst.id):
			_本回合伤害目标.append(dst.id)
	if _待翻面检查:
		_待翻面检查 = false
		_检查预言取空()
	return SUCCESS


## 【审判】给弃牌的可选目标：本回合被你伤害过、且仍然在场的对手
func _审判可选目标() -> Array[int]:
	var 结果: Array[int] = []
	for pid: int in _本回合伤害目标:
		var 目标: BattlePlayer = engine.p(pid)
		if 目标 != null and 目标.color != player.color and not 结果.has(pid):
			结果.append(pid)
	return 结果


# ============================================================
# 9504 末日预言：F8 同步钩子 —— 因承受伤害摸牌时第 1 张从预言堆拿
# ============================================================
func 伤害摸牌替换(pid: int) -> int:
	if not engine.有场卡(末日预言名):
		return -1
	var 表: Dictionary = engine.取场卡(末日预言名)
	var 堆: Array = 表.get("pile", [])
	if 堆.is_empty():
		return -1
	var 牌: int = int(堆.pop_back())
	表["counter"] = 堆.size()
	# 有人因伤害摸牌时改从【预言】堆拿走 1 张：战斗日志写清谁从谁的预言堆摸走，并播技能发动
	_日志末日("摸走", pid, 1)
	notice_skill(MO_RI_YU_YAN, [pid])
	# 最后 1 张被拿走的这一次伤害结算完才翻面：先记标记，等 p_harm_end（伤害流水线最后一步）
	# 再压翻面钩子。原来在这里直接 push 钩子，但没把 _翻面步 置 1，钩子跑进去什么都不做，
	# 表现就是「预言抽到 0 张却不翻面」。
	if 堆.is_empty():
		_待翻面检查 = true
	return 牌


# ============================================================
# 9502 审判：自己的回合结束时
# ============================================================
func p_turn_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if _审判可选目标().is_empty() or _审判已发动:
		return SUCCESS
	# 流程已经走到「问队友弃牌 / 选牌给对手」等步骤：回合结束钩子不参与，
	# 避免把别人的回复当成「是否发动」的回复吃掉（列表中途的 WAIT 由审判自己的钩子负责）
	if _审判步 == 2 or _审判步 == 3 or _审判步 == 4:
		return SUCCESS
	if _审判步 == 1:
		# 等发动询问的回复；没有回复就说明还没轮到/已被处理
		if not engine.has_reply():
			return SUCCESS
	else:
		# _审判步 == 0：第一次进入，发起动询问
		_审判步 = 1
		if not engine.has_reply():
			询问(player.id, SHEN_PAN, 0, 0, GConst.CardSource.Hand, [], 0, "", [], true,
				0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0, "")
				# 说明交给默认的技能说明（提示条会显示技能表里【审判】的说明），
				# 不再自己写「是否发动【审判】：…」——技能名已经由询问标题显示
			return WAIT
	if not take_skill_reply():
		_审判步 = 0
		return SUCCESS
	# 定死「本回合只发动一次」：结算完钩子被重入时直接跳过（否则会循环再问）
	_审判已发动 = true
	notice_skill(SHEN_PAN, [])
	_审判弃牌 = []
	_审判下标 = 0
	_审判待摸 = -1
	_审判步 = 2
	engine.push(BattleEngine.SHook.new("p_yi_jiao_tu_ask", {"player": player.id}, []))
	return URGENT


# ============================================================
# 9503 献祭：展示预言堆顶 1 张
# ============================================================
## 【献祭】可选的 7 种系别（光 / 暗也要能选）
func _献祭系别() -> Array[int]:
	return [GConst.CardElement.Wind, GConst.CardElement.Water, GConst.CardElement.Fire,
		GConst.CardElement.Earth, GConst.CardElement.Thunder, GConst.CardElement.Light,
		GConst.CardElement.Darkness]


## 二级技能栏里的献祭选项：文案取技能表「按钮」列，按系别标色（客户端按 elements 着色）
func _献祭系别选项() -> Array:
	var out: Array = []
	var 系表: Array[int] = _献祭系别()
	for i: int in range(系表.size()):
		out.append({"text": GConst.按钮原文(XIAN_JI, i),
			"args": [系表[i]], "elements": [系表[i]]})
	return out


## 发动【献祭】：系别由二级技能栏的选项给出（args[0]），这里直接进入结算
func _p_献祭(系: int) -> int:
	# 启动技每回合只能发动一个（引擎在行动入口也会拦；这里防直接调用绕过）
	if player.boot_skill_used:
		return GConst.GE_INVALID_ACTION
	if not _献祭系别().has(系):
		return GConst.GE_INVALID_ARGUMENT
	var 表: Dictionary = engine.取场卡(末日预言名)
	var 堆: Array = 表.get("pile", [])
	if 堆.is_empty():
		return GConst.GE_INVALID_ACTION
	# 「启动」技能每回合只能发动一个：发动成功记到玩家身上（引擎统一下发/校验）
	player.boot_skill_used = true
	_献祭系 = 系
	_献祭步 = 2
	# 头像飘字带系别：献祭*火系
	notice_skill(XIAN_JI, [player.id], "献祭*%s系" % GConst.element_to_chinese(系))
	engine.push(BattleEngine.SHook.new("p_yi_jiao_tu_ask", {"player": player.id}, []))
	return URGENT

var _献祭步: int = 0
var _献祭系: int = 0


# ============================================================
# 9505 放逐：摸 6~8 → 移除旧预言 → 入场 → 6 张手牌作预言 → 额外行动
# ============================================================
func _p_放逐(张: int) -> int:
	if player.get_energy() < 1 or _本回合已用放逐:
		return GConst.GE_INVALID_ACTION
	张 = clampi(张, 6, 8)
	# 【放逐】是回合限定：本回合只能发动一次（下回合开始重置）
	_本回合已用放逐 = true
	player.remove_energy(1)
	notice_skill(FANG_ZHU, [player.id])
	# 「无视你的手牌上限摸 6-8 张」：进入「不爆牌」状态（本次结算完成前超限一律不结算），
	# 结算完（6 张手牌放成【预言】后）再解除
	engine.进入不爆牌(player.id)
	# 摸几张已在二级技能栏里选好（args[0]）：先压「继续走」的钩子、再压摸牌（栈顶是摸牌），
	# 摸完再回来走 _放逐步 == 2
	_放逐步 = 2
	engine.push(BattleEngine.SHook.new("p_yi_jiao_tu_ask", {"player": player.id}, []))
	engine.push_draw(player.id, 张, FANG_ZHU)
	return URGENT

var _放逐步: int = 0


# ============================================================
# 9504 翻面 → 9507 / 9508「展示时」效果（9506 贪婪改「两项都发动」、9509 灾殃止息移除）
# ============================================================
func p_yi_jiao_tu_ask(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	# 翻面：正面在【放逐】放置【末日预言】时已经记在场卡 front 里，直接按它翻。
	# 没有正面数据就什么都不做（不询问、不随机、也不报错）。
	if _翻面步 == 1:
		var 场: Dictionary = engine.取场卡(末日预言名)
		var 预定: String = str(场.get("front", ""))
		_翻面步 = 2
		if 预定.is_empty():
			engine.报错("【末日预言】缺少 front，无法翻面（正常只能由【放逐】放置）", player.id)
			_翻面步 = 0
			return SUCCESS
		return _翻面为(预定)
	# 展示时：是否发动【贪婪】（消耗 1 水晶 → 两项都发动）
	if _展示步 == 10:
		if player.get_energy() <= 0:
			_展示步 = 1
			return p_yi_jiao_tu_ask(ctx)
		if not engine.has_reply():
			询问(player.id, TAN_LAN, 0, 0, GConst.CardSource.Hand, [], 0, "", [], true,
				0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0, "")
				# 说明交给默认的技能说明（提示条显示技能表里【贪婪】的说明）
			return WAIT
		_展示贪婪 = take_skill_reply()
		_展示已用.clear()
		if _展示贪婪:
			player.remove_energy(1)
			notice_skill(TAN_LAN, [player.id])
		# 贪婪不再先问「先雷后火 / 先火后雷」：直接进四系选项板，
		# 本被动两个系可发、另一个被动两个系置灰；用一个灰一个，直到用完。
		_展示步 = 1
		return p_yi_jiao_tu_ask(ctx)
	# 展示时：四系选项板 + 弃牌 + 目标在同一次询问里选完（按一次「确定」）
	if _展示步 == 1:
		var 可发系: Array[int] = []
		for 系0: int in _展示主动系():
			if _展示可发动(系0):
				可发系.append(系0)
		var 候选: Array[int] = hand_ids_where(
			func(_cid: int, c: GCard) -> bool: return 可发系.has(c.element_enum()))
		if not engine.has_reply():
			# 不写 ask_text：没选系别前提示条显示技能完整说明；
			# 每个系别选项自带「该系效果」文案（option_prompts），选中后替换提示条。
			# 牌白名单只放本被动还能发的两个系，改选系别后客户端再按选项收紧。
			询问(player.id, _展示技能号(), 0, 1, GConst.CardSource.Hand,
				_展示系别选项(), 4, "", 候选, false,
				0, player.id, enemy_ids(), 4, {}, 0, 0, false, [], true, -1, 0, "")
			return WAIT
		var r2: Dictionary = take_skill_reply_full()
		var 超时: bool = bool(r2.get("is_timeout", false))
		var args2: Array = r2.get("args", [])
		var 选系: int = int(args2[0]) if not args2.is_empty() else -1
		if not _展示可发动(选系):
			if not 超时:
				# 提交了置灰 / 非法系别：驳回重问，不替玩家改选
				engine.send(player.id, GConst.Msg.ErrorInput,
					{"error_type": GConst.CmdType.Respond, "commands": []})
				return p_yi_jiao_tu_ask({"player": player.id})
			# 超时才取第一个还能发的系
			for 系2: int in 可发系:
				选系 = 系2
				break
		if not _展示可发动(选系):
			engine.报错("【%s】没有可发动的系别，展示取消" % _在展示, player.id)
			_展示步 = 0
			_展示已用.clear()
			_翻面步 = 0
			return SUCCESS
		_展示系 = 选系
		# 校验弃牌：每张都必须还在手、属于刚选的系别、最多 4 张；非法就驳回重问
		var 输入牌: Array = r2.get("card_ids", [])
		var 弃: Array = []
		var 牌非法: bool = 输入牌.size() > 4
		for c: Variant in 输入牌:
			if 牌非法:
				break
			var cid3: int = int(c)
			if not player.有手牌(cid3) or 弃.has(cid3):
				牌非法 = true
				break
			var 卡3: GCard = Data.get_card(cid3)
			if 卡3 == null or 卡3.element_enum() != _展示系:
				牌非法 = true
				break
			弃.append(cid3)
		if 牌非法:
			engine.send(player.id, GConst.Msg.ErrorInput,
				{"error_type": GConst.CmdType.Respond, "commands": []})
			return p_yi_jiao_tu_ask({"player": player.id})
		# 目标也先校验：非法就驳回重问，不静默换人
		var 敌表3: Array = enemy_ids()
		var ds3: Array = r2.get("dst_ids", [])
		_展示对手 = -1
		if 敌表3.is_empty():
			return _展示本项结束()
		if ds3.size() == 1 and 敌表3.has(int(ds3[0])):
			_展示对手 = int(ds3[0])
		elif not 超时:
			engine.send(player.id, GConst.Msg.ErrorInput,
				{"error_type": GConst.CmdType.Respond, "commands": []})
			return p_yi_jiao_tu_ask({"player": player.id})
		else:
			# 超时兜底：随机指定一名对手，别把这次展示白丢
			_展示对手 = int(敌表3[engine._rng.randi_range(0, 敌表3.size() - 1)])
		if _展示对手 < 0 or engine.p(_展示对手) == null:
			return _展示本项结束()
		if not 弃.is_empty():
			engine.broadcast(GConst.Msg.Card, {
				"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
				"card_ids": 弃, "is_real": true,
			})
			engine.take_from_hand(player.id, 弃, false)
			engine.to_discard(弃, {"owner": player.id, "source": "hand", "cause": _展示技能号()})
			engine._log_discard(player.id, 弃, false)
		_展示X = 弃.size()
		# 先压「继续走」的钩子、再压摸牌：摸完（含超限结算）回来问目标对手弃牌
		_展示步 = 7
		engine.push(BattleEngine.SHook.new("p_yi_jiao_tu_ask", {"player": player.id}, []))
		if _展示X > 0:
			engine.push_draw(player.id, _展示X, _展示技能号())
		return URGENT
	# 展示时（每一项）：目标对手自选弃任意张该系牌【展示】（可不弃）
	if _展示步 == 7:
		var 对手: BattlePlayer = engine.p(_展示对手)
		var 牌面: Array = []
		var 上限: int = 0
		if 对手 != null:
			for cid: int in 对手.hand_cards:
				var 卡2: GCard = Data.get_card(cid)
				if 卡2 == null or 卡2.element_enum() != _展示系:
					continue
				上限 += 1
				var 面2: int = GConst.牌号(int(cid))
				if not 牌面.has(面2):
					牌面.append(面2)
		if 上限 <= 0:
			return _展示本项伤害()
		if not engine.has_reply():
			# 目标弃牌这一步不可取消（can_cancel=false）：可以一张都不弃，但不能点「取消」跳过
			询问(_展示对手, _展示技能号(), 0, 0, GConst.CardSource.Hand, [], 上限, "", 牌面, false,
				0, _展示对手, [], 上限, {}, 0, 0, false, [], true, -1, 0,
				GConst.提示原文(_展示技能号(), 4)
				% [_在展示, GConst.element_to_chinese(_展示系)])
			return WAIT
		var r7: Dictionary = take_skill_reply_full()
		var 超时7: bool = bool(r7.get("is_timeout", false))
		var 已弃: Array = []
		var 对手2: BattlePlayer = engine.p(_展示对手)
		var 弃牌非法: bool = false
		if 对手2 != null:
			for c: Variant in r7.get("card_ids", []):
				if 已弃.size() >= 上限:
					弃牌非法 = true
					break
				var cid2: int = int(c)
				var 卡3: GCard = Data.get_card(cid2)
				if 对手2.有手牌(cid2) and 卡3 != null and 卡3.element_enum() == _展示系 						and not 已弃.has(cid2):
					已弃.append(cid2)
				else:
					弃牌非法 = true
					break
		if 弃牌非法:
			if not 超时7:
				# 提交了不在手 / 不是该系 / 超过上限的牌：驳回重问
				engine.send(_展示对手, GConst.Msg.ErrorInput,
					{"error_type": GConst.CmdType.Respond, "commands": []})
				return p_yi_jiao_tu_ask({"player": player.id})
			已弃.clear()
		if not 已弃.is_empty():
			engine.broadcast(GConst.Msg.Card, {
				"type": GConst.CardMsgType.Show, "src_id": _展示对手, "dst_id": _展示对手,
				"card_ids": 已弃, "is_real": true,
			})
			engine.take_from_hand(_展示对手, 已弃, false)
			engine.to_discard(已弃, {"owner": _展示对手, "source": "hand", "cause": _展示技能号()})
			engine._log_discard(_展示对手, 已弃, false)
		return _展示本项伤害()
	# 展示时（每一项）：伤害结算完 → 进入下一项（贪婪）或收尾
	if _展示步 == 9:
		return _展示本项结束()
	# 审判：逐名队友弃 1 张牌【展示】
	if _审判步 == 2:
		var 队友: Array[int] = _我方角色()
		# 上一名队友的弃牌已经结算完（含弃牌前拦截/渗蚀）：先让他摸 1 张，
		# 再轮下一名队友 —— 不要所有人先弃完再一起摸。
		# 摸牌压成状态再摸：摸完先由引擎统一结算手牌/盖牌超限，结算完才回来问下一名队友
		# 座位号从 0 开始：0 号座位是合法的人，哨兵必须是 -1（用 > 0 会吞掉 0 号的摸牌）
		if _审判待摸 >= 0:
			var 待摸: int = _审判待摸
			_审判待摸 = -1
			engine.push_强制摸牌(待摸, 1, SHEN_PAN)
			return URGENT
		if _审判下标 >= 队友.size():
			_审判步 = 3
			return p_yi_jiao_tu_ask({"player": player.id})
		var pid2: int = int(队友[_审判下标])
		var pp: BattlePlayer = engine.p(pid2)
		if pp == null or pp.hand_cards.is_empty():
			_审判下标 += 1
			return p_yi_jiao_tu_ask({"player": player.id})
		if not engine.has_reply():
			# 强制弃牌：can_cancel=false（客户端不显示可点的取消；超时由下面的空回复兜底补弃）
			询问(pid2, SHEN_PAN, 1, 0, GConst.CardSource.Hand, [], 1, "", [], false,
				0, pid2, [], 1, {}, 0, 0, false, [], true, -1, 0,
				GConst.提示原文(SHEN_PAN, 1))
			return WAIT
		var r6: Dictionary = take_skill_reply_full()
		var 超时6: bool = bool(r6.get("is_timeout", false))
		var cards6: Array = r6.get("card_ids", [])
		var cid: int = -1
		if not cards6.is_empty():
			if pp.有手牌(int(cards6[0])):
				cid = int(cards6[0])
			elif not 超时6:
				# 提交了不在手的牌：驳回重问，不替玩家随机弃
				engine.send(pid2, GConst.Msg.ErrorInput,
					{"error_type": GConst.CmdType.Respond, "commands": []})
				return p_yi_jiao_tu_ask({"player": player.id})
		if cid < 0:
			if not 超时6:
				# 强制弃牌必须选 1 张；空提交也驳回
				engine.send(pid2, GConst.Msg.ErrorInput,
					{"error_type": GConst.CmdType.Respond, "commands": []})
				return p_yi_jiao_tu_ask({"player": player.id})
			# 超时：自动弃掉一张（随机），不卡住流程
			var 手6: Array = pp.hand_cards.duplicate()
			if not 手6.is_empty():
				cid = int(手6[engine._rng.randi_range(0, 手6.size() - 1)])
		if cid >= 0 and pp.有手牌(cid):
			engine.broadcast(GConst.Msg.Card, {
				"type": GConst.CardMsgType.Show, "src_id": pid2, "dst_id": pid2,
				"card_ids": [cid], "is_real": true,
			})
			engine.take_from_hand(pid2, [cid], false)
			# 走统一的弃牌入口：F6「弃牌前拦截」会在这里触发（如噬神者【渗蚀】），
			# 牌先进弃牌堆，最后一步再按需要取回来（交给对手 / 放进【预言】堆）。
			# 注意 owner 必须是真正弃牌的那个人（渗蚀的伤害打给弃牌者）。
			engine.to_discard([cid], {"owner": pid2, "source": "hand", "cause": SHEN_PAN})
			_审判弃牌.append(cid)
			_审判下标 += 1
			_审判待摸 = pid2
			# 先让弃牌拦截结算完，回来先给这名队友摸 1 张，再继续下一名
			return URGENT
		_审判下标 += 1
		return p_yi_jiao_tu_ask({"player": player.id})
	# 审判：选 1 张弃牌给目标对手；其余进预言堆
	if _审判步 == 3:
		# 选项只能是「确实还在弃牌堆、且仍在场」的弃牌：被【渗蚀】等移除的牌
		# 既不在弃牌堆也不在场，不能作为选项；后续给牌也才有牌可取。
		var 可给: Array[int] = []
		for c0: Variant in _审判弃牌:
			var cid0: int = int(c0)
			if engine.牌在场(cid0) and engine.deck.discard.has(cid0):
				可给.append(cid0)
		_审判弃牌 = 可给
		if _审判弃牌.is_empty():
			_审判步 = 0
			return SUCCESS
		if not engine.has_reply():
			var 弃牌选项: Array = []
			for i: int in range(_审判弃牌.size()):
				var 弃卡: GCard = Data.get_card(int(_审判弃牌[i]))
				弃牌选项.append({"value": i + 1,
					"label": 弃卡.card_name if 弃卡 != null else "弃牌", "card_id": int(_审判弃牌[i])})
			询问(player.id, SHEN_PAN, 0, 1, GConst.CardSource.Hand, 弃牌选项, 0, "", [], false,
				0, -1, _审判可选目标(), -1, {}, 0, 0, false, [], true, -1, 0,
				GConst.提示原文(SHEN_PAN, 2))
			return WAIT
		var r7: Dictionary = take_skill_reply_full()
		var ds7: Array = r7.get("dst_ids", [])
		var args7: Array = r7.get("args", [])
		# 目标 / 选牌都必须合法：不合法就驳回（ErrorInput）并重新问这一步。
		# 不做换目标 / 顺延之类的兜底 —— 那会把「提交错了」掩盖成「结算错了」。
		# 超时不用管：这条询问不可取消且要 1 名目标，引擎的兜底回复已经带了合法目标 + args=[1]。
		var 目标id: int = int(ds7[0]) if ds7.size() == 1 else -1
		var 目标: BattlePlayer = engine.p(目标id)
		var 下标: int = (int(args7[0]) - 1) if not args7.is_empty() else -1
		# 下标落在可选范围内、且那张牌确实还在弃牌堆（防客户端旧列表 / 中途被取走）
		var 可交: bool = 下标 >= 0 and 下标 < _审判弃牌.size()
		if 可交:
			可交 = engine.deck.discard.has(int(_审判弃牌[下标]))
		if 目标 == null or not _审判可选目标().has(目标id) or not 可交:
			engine.send(player.id, GConst.Msg.ErrorInput,
				{"error_type": GConst.CmdType.Respond, "commands": []})
			# _审判步 仍是 3：重入本分支会重新发「选 1 张弃牌交给目标对手」
			return p_yi_jiao_tu_ask({"player": player.id})
		_审判步 = 4
		_审判对手 = 目标id
		_审判给 = 下标
		return p_yi_jiao_tu_ask({"player": player.id})
	if _审判步 == 4:
		_审判步 = 0
		var 已弃: Array = _审判弃牌.duplicate()
		_审判弃牌 = []
		# 这些牌已经在 step2 走统一弃牌入口进了弃牌堆；step3 的选项又按「仍在弃牌堆」筛过，
		# 所以这里直接按选中的下标取同一实例即可，不做换目标 / 顺延之类的兜底。
		var 下标给: int = clampi(_审判给, 0, maxi(已弃.size() - 1, 0))
		var 已给: int = -1
		var 敌: BattlePlayer = engine.p(_审判对手)
		if 敌 != null and not 已弃.is_empty():
			var cid给: int = int(已弃[下标给])
			var 取: int = engine.deck.取出实例(cid给)
			if 取 >= 0:
				敌.add_hand_cards([取])
				已给 = 取
				engine._log_give_cards(player.id, 敌.id, [取])
		# 其余弃牌：有【末日预言】才从弃牌堆取出来放进【预言】堆；
		# 没有【末日预言】就留在弃牌堆（本来就已经在里面了，不用再动）
		if engine.有场卡(末日预言名):
			var 表2: Dictionary = engine.取场卡(末日预言名)
			var 堆2: Array = 表2.get("pile", [])
			var 上限: int = int(表2.get("counter_max", 6))
			var 空位: int = maxi(上限 - 堆2.size(), 0)
			# 这批「其余弃牌」里仍然在弃牌堆的（被【渗蚀】等移除的不算）
			var 候选: Array = []
			for i: int in range(已弃.size()):
				if i == 下标给 and 已给 >= 0:
					continue
				var cid2: int = int(已弃[i])
				if engine.deck.discard.has(cid2):
					候选.append(cid2)
			# 超过【预言】上限：只从这批里随机抽「刚好填满」的几张，剩下的留在弃牌堆不动
			候选.shuffle()
			if 候选.size() > 空位:
				候选.resize(空位)
			if 空位 > 0:
				# 「将其余弃牌面朝下洗混放置到【预言】堆顶部」：只打乱这批弃牌，再压到顶部
				var 放入数: int = 0
				for c4: Variant in 候选:
					var 取2: int = engine.deck.取出实例(int(c4))
					if 取2 >= 0:
						堆2.append(取2)
						放入数 += 1
				表2["pile"] = 堆2
				表2["counter"] = 堆2.size()
				_日志末日("放入", player.id, 放入数)
				engine._broadcast_game()
		return SUCCESS
	# 献祭：系别已在二级技能栏里选好，直接结算
	if _献祭步 == 2:
		var 系: int = _献祭系
		var 表3: Dictionary = engine.取场卡(末日预言名)
		var 堆3: Array = 表3.get("pile", [])
		_献祭步 = 0
		if 堆3.is_empty():
			return SUCCESS
		var 牌: int = int(堆3.back())
		engine.broadcast(GConst.Msg.Card, {
			"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
			"card_ids": [牌], "is_real": true,
		})
		var 卡: GCard = Data.get_card(牌)
		if 卡 != null and 卡.element_enum() == 系:
			# 同系：移除该预言，我方战绩区 +1 宝石
			堆3.pop_back()
			表3["counter"] = 堆3.size()
			_日志末日("移除", player.id, 1)
			engine.set_team_gem(player.color, engine.team_gem[player.color] + 1)
			engine.to_discard([牌], {"owner": player.id, "source": "other", "cause": XIAN_JI})
		else:
			# 不同系：与牌库顶 1 张交换，然后把该预言加入你手牌
			var 顶: Array[int] = engine.移除牌库顶(1)
			if not 顶.is_empty():
				堆3.pop_back()
				堆3.append(int(顶[0]))
				表3["pile"] = 堆3
				表3["counter"] = 堆3.size()
				_日志末日("移除", player.id, 1)
				_日志末日("放入", player.id, 1)
				player.add_hand_cards([牌])
				engine._broadcast_game()
		engine._broadcast_game()
		_检查预言取空()
		return SUCCESS
	# 放逐：移除旧场卡 → 选天雷 / 地裂放 1 张【末日预言】入场
	if _放逐步 == 2:
		_放逐步 = 3
		engine.移除场卡(末日预言名)
		engine.移除场卡(天雷劫火名)
		engine.移除场卡(地裂波涛名)
		if not engine.has_reply():
			# 一次询问里同时选：放哪张正面（天雷劫火 / 地裂波涛）+ 哪 6 张手牌作为【预言】。
			# 这一步是强制的（can_cancel=false）：超时由下面的兜底随机选正面、自动放 6 张。
			询问(player.id, FANG_ZHU, 6, 0, GConst.CardSource.Hand,
				[{"value": 1, "label": GConst.按钮原文(FANG_ZHU, 3), "skill_id": TIAN_LEI_JIE_HUO,
					"no_prompt_change": true},
				 {"value": 2, "label": GConst.按钮原文(FANG_ZHU, 4), "skill_id": DI_LIE_BO_TAO,
					"no_prompt_change": true}],
				6, "", [], false,
				0, player.id, [], 6, {}, 0, 0, false, [], true, -1, 0,
				GConst.提示原文(FANG_ZHU, 1))
			return WAIT
		return p_yi_jiao_tu_ask({"player": player.id})
	# 放逐：正面 + 6 张手牌一起取回 → 放【末日预言】、洗混【预言】→ 解除不爆牌 → +1 额外行动
	if _放逐步 == 3:
		if not engine.has_reply():
			return WAIT
		var r3: Dictionary = take_skill_reply_full()
		var 超时3: bool = bool(r3.get("is_timeout", false))
		# 非超时必须恰好选 6 张、且都在手、不重复；非法就直接驳回重问
		if not 超时3:
			var 输入3: Array = r3.get("card_ids", [])
			if 输入3.size() != 6:
				engine.send(player.id, GConst.Msg.ErrorInput,
					{"error_type": GConst.CmdType.Respond, "commands": []})
				_放逐步 = 2
				return p_yi_jiao_tu_ask({"player": player.id})
			var 查重: Array = []
			for c0: Variant in 输入3:
				var cid0: int = int(c0)
				if not player.有手牌(cid0) or 查重.has(cid0):
					engine.send(player.id, GConst.Msg.ErrorInput,
						{"error_type": GConst.CmdType.Respond, "commands": []})
					_放逐步 = 2
					return p_yi_jiao_tu_ask({"player": player.id})
				查重.append(cid0)
		_放逐步 = 0
		var a3: Array = r3.get("args", [])
		# 超时 / 跳过：随机从【天雷劫火】/【地裂波涛】里选一个，不卡住流程
		var 选: int = int(a3[0]) if not a3.is_empty() else engine._rng.randi_range(1, 2)
		var 正面: String = 地裂波涛名 if 选 == 2 else 天雷劫火名
		engine.加场卡({"id": 末日预言名, "owner": player.id, "attached": -1,
			"counter": 0, "counter_max": 预言上限, "state": 0, "pile": [], "front": 正面})
		var 已选: Array = []
		for c: Variant in r3.get("card_ids", []):
			if 已选.size() >= 6:
				break
			var cid: int = int(c)
			if player.有手牌(cid) and not 已选.has(cid):
				已选.append(cid)
		# 只有超时会走到这里（非超时上面已保证 6 张合法）：随机补足，保证放逐结算完
		if 已选.size() < 6:
			var 候选: Array = player.hand_cards.duplicate()
			候选.shuffle()
			for cid3: Variant in 候选:
				if 已选.size() >= 6:
					break
				if not 已选.has(int(cid3)):
					已选.append(int(cid3))
		var 新堆: Array = []
		for cid2: Variant in 已选:
			var 取: int = player.取出实例(player.hand_cards, int(cid2))
			if 取 >= 0 and 新堆.size() < 6:
				新堆.append(取)
		if 新堆.size() != 6:
			engine.报错("【放逐】没能凑齐 6 张【预言】（实际 %d 张）" % 新堆.size(), player.id)
		var 表: Dictionary = engine.取场卡(末日预言名)
		表["pile"] = 新堆
		表["counter"] = 新堆.size()
		_日志末日("放入", player.id, 新堆.size())
		_重算手牌上限()
		_翻面步 = 0
		engine.解除不爆牌(player.id)
		# 「额外 +1【攻击行动】或【法术行动】」＝一份既能攻击也能施法的额外行动（不是二选一各一份）
		player.add_action(GConst.ActionType.AttackMagic, FANG_ZHU, true, true)
		engine._broadcast_game()
		return SUCCESS
	return SUCCESS

var _在展示: String = ""
var _展示步: int = 0


# ============================================================
# 小工具
# ============================================================
## 翻面成指定那张（天雷劫火 / 地裂波涛），并接着走「展示时」流程
func _翻面为(名: String) -> int:
	engine.移除场卡(末日预言名)
	engine.加场卡({"id": 名, "owner": player.id, "attached": -1,
		"counter": 0, "counter_max": 0, "state": 1})
	# 翻面本身不播【末日预言】；换成【天雷劫火】/【地裂波涛】后立刻发动它，补一条技能发动播报
	_在展示 = 名
	notice_skill(_展示技能号(), [player.id])
	_展示已用.clear()
	_展示贪婪 = false
	_展示对手 = -1
	# 先把「是否发动贪婪」问掉，再决定发动一项还是两项（贪婪＝两项都发动、顺序自定）
	_展示步 = 10
	return p_yi_jiao_tu_ask({"player": player.id})


## 战斗日志称呼（与引擎 _称号 同口径：[职业名]）
func _称号(pid: int) -> String:
	var pp: BattlePlayer = engine.p(pid)
	return "[%s]" % Data.role_name(pp.role_id) if pp != null else "?"


## 【末日预言】牌堆移动日志：[谁]从/在[谁]的【末日预言】摸走/移除/放入 X 张牌
## 动作 是文本表 id 的后缀（日志_末日预言_摸走 / _放入 / _移除），句子本身不写在代码里。
func _日志末日(动作: String, 操作者: int, 数: int) -> void:
	if 数 <= 0:
		return
	engine.broadcast(GConst.Msg.Gossip, {
		"type": GConst.GossipType.Discard,
		"txt": GConst.文本("日志_末日预言_" + 动作) % [
			_称号(操作者), _称号(player.id), 数],
		"id": player.id,
	})


## 翻面 / 预言取空的检查：堆空且还挂着【末日预言】就进入翻面询问
func _检查预言取空() -> void:
	if not engine.有场卡(末日预言名):
		return
	if not (engine.取场卡(末日预言名).get("pile", []) as Array).is_empty():
		return
	if _翻面步 != 0:
		return
	_翻面步 = 1
	engine.push(BattleEngine.SHook.new("p_yi_jiao_tu_ask", {"player": player.id}, []))


## 四系选项板：本被动的两个系可发（贪婪时用过的置灰），另一个被动的两个系始终置灰。
## 文案取各自技能表「按钮」列（9507 的雷/火、9508 的地/水），并带系别标色与「该系效果」提示。
func _展示系别选项() -> Array:
	var out: Array = []
	var 效果模板: String = GConst.文本("提示_展示_系别效果")
	for 系: int in [GConst.CardElement.Thunder, GConst.CardElement.Fire,
			GConst.CardElement.Earth, GConst.CardElement.Water]:
		var 系名: String = GConst.element_to_chinese(系)
		var 技能号: int = TIAN_LEI_JIE_HUO if 系 in [GConst.CardElement.Thunder, GConst.CardElement.Fire] \
			else DI_LIE_BO_TAO
		# 逐选项牌白名单：选中这一系后只让该系的手牌可点（空手牌用 -1＝全禁）
		var 牌白: Array = []
		for cid: int in player.hand_cards:
			var 卡: GCard = Data.get_card(cid)
			if 卡 == null or 卡.element_enum() != 系:
				continue
			var 面: int = GConst.牌号(cid)
			if not 牌白.has(面):
				牌白.append(面)
		if 牌白.is_empty():
			牌白.append(GConst.手牌白名单_全禁)
		out.append({
			"value": 系,
			"label": GConst.按钮原文(技能号, 0) % 系名,
			"elements": [系],
			"enabled": _展示可发动(系),
			"skill_id": 技能号,
			"cards": 牌白,
			"提示": GConst.文本("通用_技能提示") % [
				_在展示, GConst.填文本(效果模板, {"s": 系名})],
		})
	return out


## 当前展示的这张牌该用哪个技能号（天雷劫火 9507 / 地裂波涛 9508）：询问与伤害来源都用它
func _展示技能号() -> int:
	return DI_LIE_BO_TAO if _在展示 == 地裂波涛名 else TIAN_LEI_JIE_HUO


## 当前被动自己的两个系
func _展示主动系() -> Array[int]:
	return _展示系别()


## 这一系现在能不能发动：必须是本被动的两个系之一；贪婪时已经发过的不能再发
func _展示可发动(系: int) -> bool:
	if not _展示主动系().has(系):
		return false
	if _展示贪婪 and _展示已用.has(系):
		return false
	return true


## 展示流程里「每一项」的伤害：目标对手弃完牌后造成 X+1 点法术伤害③
func _展示本项伤害() -> int:
	_展示步 = 9
	# 座位号 0 是合法对手：哨兵是 -1
	if _展示对手 >= 0:
		engine.push_harm({
			"src": player.id, "dst": _展示对手, "point": _展示X + 1,
			"cause": _展示技能号(), "type": GConst.HarmType.Magic,
		})
		return URGENT
	return _展示本项结束()


## 一项结算完：下一项（贪婪）或收尾（清翻面标记，放逐放进新【末日预言】后还能再翻）
func _展示本项结束() -> int:
	_展示对手 = -1
	if _展示贪婪:
		if not _展示已用.has(_展示系):
			_展示已用.append(_展示系)
		# 还有没发的主动系 → 回四系选项板（用过的置灰）
		for 系: int in _展示主动系():
			if not _展示已用.has(系):
				_展示步 = 1
				return p_yi_jiao_tu_ask({"player": player.id})
	# 非贪婪 / 两项都发完：收尾
	_展示步 = 0
	_展示已用.clear()
	_翻面步 = 0
	return SUCCESS


## 【天雷劫火】/【地裂波涛】的两种系别
func _展示系别() -> Array[int]:
	if _在展示 == 地裂波涛名:
		return [GConst.CardElement.Earth, GConst.CardElement.Water]
	return [GConst.CardElement.Thunder, GConst.CardElement.Fire]


func _我方角色() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		var pp: BattlePlayer = engine.p(pid)
		if pp != null and pp.color == player.color:
			out.append(pid)
	return out


