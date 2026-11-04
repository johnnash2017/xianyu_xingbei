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
## 3. 翻面：预言堆**取空的那一次结算完**，问玩家选【天雷劫火】/【地裂波涛】，
##    移除【末日预言】、换一张同名场卡入场，然后立刻结算它的「展示时」效果。
##    展示结算完把 _翻面步 归零（【放逐】放进新的【末日预言】后还能再翻一次）。
## 4. 【天雷劫火】/【地裂波涛】「展示时」：选 1 种系别 → 弃 X 张该系牌（≤4，可为 0）→
##    摸 X 张【强制】→ 选 1 名目标对手 → 他自选弃任意张该系牌【展示】（可不弃）→
##    造成 X+1 点法术伤害③。两项（雷/火 或 地/水）二选一发动。
##    【贪婪】9506：展示时花 1 点能量，把「选一项」改成「两项都发动、顺序由你决定」。
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

## 本回合是否对对手造成过伤害（【审判】的发动条件）
var _本回合造成伤害: bool = false
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
var _展示系: int = 0
var _展示X: int = 0
var _展示对手: int = -1
## 展示时这一轮要依次结算的系别（贪婪＝两项都发动，顺序由玩家选）
var _展示模式: Array[int] = []
var _展示序号: int = 0
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
		},
		{
			"type": GConst.ActionType.MagicSkill,
			"id": FANG_ZHU,
			"enabled": player.get_energy() >= 1 and not _本回合已用放逐,
			# 和魔弓【魔眼】一样：点技能直接进二级技能栏，三个抽牌档在那里选；
			# 不选就按「返回」退出来，不扣能量也不发动
			"arg_choices": [
				{"text": "摸 6 张牌", "args": [6]},
				{"text": "摸 7 张牌", "args": [7]},
				{"text": "摸 8 张牌", "args": [8]},
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
	return GConst.GE_SUCCESS


func p_special_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != XIAN_JI:
		return EMPTY_HANDLE
	return _p_献祭()


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
	_本回合造成伤害 = false
	_审判已发动 = false
	_本回合已用放逐 = false
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
	player.hand_cards_max = GConst.HAND_CARDS_MAX - (1 if engine.有场卡(末日预言名) else 0)


## 本回合对对手造成过伤害（【审判】条件）
func p_harm_end(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) == player.id:
		var dst: BattlePlayer = engine.p(int(ctx.get("dst", -1)))
		if dst != null and dst.color != player.color:
			_本回合造成伤害 = true
	return SUCCESS


# ============================================================
# 9504 末日预言：F8 同步钩子 —— 因承受伤害摸牌时第 1 张从预言堆拿
# ============================================================
func 伤害摸牌替换(_pid: int) -> int:
	if not engine.有场卡(末日预言名):
		return -1
	var 表: Dictionary = engine.取场卡(末日预言名)
	var 堆: Array = 表.get("pile", [])
	if 堆.is_empty():
		return -1
	var 牌: int = int(堆.pop_back())
	表["counter"] = 堆.size()
	# 最后 1 张被拿走的这一次结算完就要翻面：压一个钩子，等这次伤害摸牌流程跑完再问
	if 堆.is_empty():
		engine.push(BattleEngine.SHook.new("p_yi_jiao_tu_ask", {"player": player.id, "翻面": true}, []))
	return 牌


# ============================================================
# 9502 审判：自己的回合结束时
# ============================================================
func p_turn_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if not _本回合造成伤害 or _审判已发动:
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
func _p_献祭() -> int:
	# 启动技每回合只能发动一个（引擎在行动入口也会拦；这里防直接调用绕过）
	if player.boot_skill_used:
		return GConst.GE_INVALID_ACTION
	var 表: Dictionary = engine.取场卡(末日预言名)
	var 堆: Array = 表.get("pile", [])
	if 堆.is_empty():
		return GConst.GE_INVALID_ACTION
	# 「启动」技能每回合只能发动一个：发动成功记到玩家身上（引擎统一下发/校验）
	player.boot_skill_used = true
	_献祭牌 = int(堆.back())
	_献祭步 = 1
	engine.push(BattleEngine.SHook.new("p_yi_jiao_tu_ask", {"player": player.id}, []))
	return URGENT

var _献祭步: int = 0
var _献祭牌: int = -1


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
	# 翻面：正面在【放逐】放置【末日预言】时已经选好（front）；没有才问（旧数据 / 直接造场卡）
	if _翻面步 == 1:
		var 场: Dictionary = engine.取场卡(末日预言名)
		var 预定: String = str(场.get("front", ""))
		if 预定.is_empty():
			if not engine.has_reply():
				询问(player.id, MO_RI_YU_YAN, 0, 0, GConst.CardSource.Hand,
					[{"value": 1, "label": "天雷劫火", "skill_id": TIAN_LEI_JIE_HUO},
					 {"value": 2, "label": "地裂波涛", "skill_id": DI_LIE_BO_TAO}], 0, "", [], false,
					0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0,
					"【末日预言】的【预言】已空：翻面为【天雷劫火】或【地裂波涛】")
				return WAIT
			var r: Dictionary = take_skill_reply_full()
			var args: Array = r.get("args", [])
			# 超时 / 跳过：随机翻一面
			var 选: int = int(args[0]) if not args.is_empty() else engine._rng.randi_range(1, 2)
			预定 = 地裂波涛名 if 选 == 2 else 天雷劫火名
		_翻面步 = 2
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
		if _展示贪婪:
			player.remove_energy(1)
			notice_skill(TAN_LAN, [player.id])
			_展示步 = 11
		else:
			_展示步 = 1
		return p_yi_jiao_tu_ask(ctx)
	# 展示时（贪婪）：选两项的发动顺序
	if _展示步 == 11:
		var 序表: Array[int] = _展示系别()
		if not engine.has_reply():
			询问(player.id, TAN_LAN, 0, 0, GConst.CardSource.Hand,
				[{"value": 1, "label": "先%s后%s" % [GConst.element_to_chinese(序表[0]), GConst.element_to_chinese(序表[1])]},
				 {"value": 2, "label": "先%s后%s" % [GConst.element_to_chinese(序表[1]), GConst.element_to_chinese(序表[0])]}],
				0, "", [], false,
				0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0,
				"【贪婪】：选择发动顺序")
			return WAIT
		var rq: Dictionary = take_skill_reply_full()
		var aq: Array = rq.get("args", [])
		var 先: int = int(aq[0]) if not aq.is_empty() else 1
		# 类型化数组不能直接赋一个无类型字面量（运行时会报 Array → Array[int]），逐项 append
		_展示模式.clear()
		if 先 == 2:
			_展示模式.append(序表[1])
			_展示模式.append(序表[0])
		else:
			_展示模式.append(序表[0])
			_展示模式.append(序表[1])
		_展示序号 = 0
		_展示步 = 3
		return p_yi_jiao_tu_ask(ctx)
	# 展示时（不发动贪婪）：选 1 种系别发动
	if _展示步 == 1:
		var 系表: Array[int] = _展示系别()
		if not engine.has_reply():
			询问(player.id, _展示技能号(), 0, 0, GConst.CardSource.Hand, _系别选项(系表), 0, "", [], false,
				0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0,
				"【%s】：选择 1 种系别发动" % _在展示)
			return WAIT
		var r2: Dictionary = take_skill_reply_full()
		var args2: Array = r2.get("args", [])
		var 选系: int = int(args2[0]) if not args2.is_empty() else int(系表[0])
		if not 系表.has(选系):
			选系 = int(系表[0])
		_展示模式.clear()
		_展示模式.append(选系)
		_展示序号 = 0
		_展示步 = 3
		return p_yi_jiao_tu_ask(ctx)
	# 展示时（每一项）：选 X（弃几张该系牌，最多 4，且不能超过手里该系牌数）
	if _展示步 == 3:
		if _展示序号 >= _展示模式.size():
			# 本次展示全部结算完：清状态、清翻面标记（放逐放进新的【末日预言】后还能再翻）
			_展示步 = 0
			_展示模式.clear()
			_展示对手 = -1
			_翻面步 = 0
			return SUCCESS
		_展示系 = int(_展示模式[_展示序号])
		var 同系: Array[int] = hand_ids_where(
			func(_cid: int, c: GCard) -> bool: return c.element_enum() == _展示系)
		_展示X = mini(4, 同系.size())
		if _展示X <= 0:
			_展示步 = 5
			return p_yi_jiao_tu_ask(ctx)
		var 展示系名: String = GConst.element_to_chinese(_展示系)
		if not engine.has_reply():
			询问(player.id, _展示技能号(), _展示X, 0, GConst.CardSource.Hand, [], _展示X, "", [], false,
				0, player.id, [], _展示X, {}, 0, 0, false, [], true, -1, 0,
				"【%s】：弃最多 %d 张%s系牌【展示】" % [_在展示, _展示X, 展示系名])
			return WAIT
		var r3: Dictionary = take_skill_reply_full()
		var cards: Array = r3.get("card_ids", [])
		var 弃: Array = []
		for c: Variant in cards:
			if 弃.size() < _展示X and player.有手牌(int(c)):
				var 卡: GCard = Data.get_card(int(c))
				if 卡 != null and 卡.element_enum() == _展示系 and not 弃.has(int(c)):
					弃.append(int(c))
		if not 弃.is_empty():
			engine.broadcast(GConst.Msg.Card, {
				"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
				"card_ids": 弃, "is_real": true,
			})
			engine.take_from_hand(player.id, 弃, false)
			engine.to_discard(弃, {"owner": player.id, "source": "hand", "cause": _展示技能号()})
			engine._log_discard(player.id, 弃, false)
		_展示X = 弃.size()
		_展示步 = 5
		return p_yi_jiao_tu_ask(ctx)
	# 展示时（每一项）：摸 X 张【强制】→ 选目标对手
	if _展示步 == 5:
		if _展示X > 0:
			engine.push_draw(player.id, _展示X, _展示技能号())
		# 摸牌先压进栈；阶段推进到「等目标回复」，回来由 6 号分支取回复（避免重复摸牌）
		_展示步 = 6
		if not engine.has_reply():
			询问(player.id, _展示技能号(), 0, 1, GConst.CardSource.Hand, [], 0, "", [], false,
				0, -1, enemy_ids(), -1, {}, 0, 0, false, [], true, -1, 0,
				"【%s】：指定 1 名目标对手（他弃牌后你造成 %d 点法术伤害）" % [_在展示, _展示X + 1])
			return WAIT
	if _展示步 == 6:
		if not engine.has_reply():
			return WAIT
		var r5: Dictionary = take_skill_reply_full()
		var ds: Array = r5.get("dst_ids", [])
		var 敌表5: Array = enemy_ids()
		if ds.size() == 1:
			_展示对手 = int(ds[0])
		elif not 敌表5.is_empty():
			# 超时 / 跳过：随机指定一名对手，别把这次展示白丢
			_展示对手 = int(敌表5[engine._rng.randi_range(0, 敌表5.size() - 1)])
		else:
			_展示对手 = -1
		if _展示对手 < 0 or engine.p(_展示对手) == null:
			return _展示本项结束()
		_展示步 = 7
		return p_yi_jiao_tu_ask(ctx)
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
			询问(_展示对手, _展示技能号(), 0, 0, GConst.CardSource.Hand, [], 上限, "", 牌面, true,
				0, _展示对手, [], 上限, {}, 0, 0, false, [], true, -1, 0,
				"【%s】：请弃任意张%s系牌【展示】（可不弃）"
				% [_在展示, GConst.element_to_chinese(_展示系)])
			return WAIT
		var r7: Dictionary = take_skill_reply_full()
		var 已弃: Array = []
		var 对手2: BattlePlayer = engine.p(_展示对手)
		if 对手2 != null:
			for c: Variant in r7.get("card_ids", []):
				var cid2: int = int(c)
				var 卡3: GCard = Data.get_card(cid2)
				if 已弃.size() < 上限 and 对手2.有手牌(cid2) and 卡3 != null 						and 卡3.element_enum() == _展示系 and not 已弃.has(cid2):
					已弃.append(cid2)
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
		if _审判待摸 > 0:
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
			询问(pid2, SHEN_PAN, 1, 0, GConst.CardSource.Hand, [], 1, "", [], true,
				0, pid2, [], 1, {}, 0, 0, false, [], true, -1, 0,
				"【审判】：弃 1 张牌【展示】，摸 1 张牌")
			return WAIT
		var r6: Dictionary = take_skill_reply_full()
		var cards6: Array = r6.get("card_ids", [])
		var cid: int = -1
		if not cards6.is_empty() and pp.有手牌(int(cards6[0])):
			cid = int(cards6[0])
		if cid < 0:
			# 超时 / 跳过：自动弃掉一张（随机），不卡住流程
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
				0, -1, enemy_ids(), -1, {}, 0, 0, false, [], true, -1, 0,
				"【审判】：选 1 张弃牌交给目标对手")
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
		if 目标 == null or 目标.color == player.color or not 可交:
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
			if 取 > 0:
				敌.add_hand_cards([取])
				已给 = 取
				engine._log_give_cards(player.id, 敌.id, [取])
		# 其余弃牌：有【末日预言】才从弃牌堆取出来放进【预言】堆；
		# 没有【末日预言】就留在弃牌堆（本来就已经在里面了，不用再动）
		if engine.有场卡(末日预言名):
			var 其余: Array = []
			for i: int in range(已弃.size()):
				if i == 下标给 and 已给 > 0:
					continue
				var 取2: int = engine.deck.取出实例(int(已弃[i]))
				if 取2 > 0:
					其余.append(取2)
			var 表2: Dictionary = engine.取场卡(末日预言名)
			var 堆2: Array = 表2.get("pile", [])
			# 「将其余弃牌面朝下洗混放置到【预言】堆顶部」：只打乱这批弃牌，再压到顶部
			其余.shuffle()
			for c4: Variant in 其余:
				堆2.append(int(c4))
			表2["pile"] = 堆2
			表2["counter"] = 堆2.size()
			engine._broadcast_game()
		return SUCCESS
	# 献祭：先选系别，再结算
	if _献祭步 == 1:
		if not engine.has_reply():
			var 系表2: Array[int] = [GConst.CardElement.Wind, GConst.CardElement.Water,
				GConst.CardElement.Fire, GConst.CardElement.Earth, GConst.CardElement.Thunder]
			询问(player.id, XIAN_JI, 0, 0, GConst.CardSource.Hand, _系别选项(系表2), 0, "", [], false,
				0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0,
				"【献祭】：指定 1 种系别，展示【预言】堆顶 1 张")
			return WAIT
		# 阶段在取完回复之后再推进：重入时 _献祭步 仍是 1
		var r8: Dictionary = take_skill_reply_full()
		_献祭步 = 2
		var args8: Array = r8.get("args", [])
		var 系表8: Array[int] = [GConst.CardElement.Wind, GConst.CardElement.Water,
			GConst.CardElement.Fire, GConst.CardElement.Earth, GConst.CardElement.Thunder]
		# 超时 / 跳过：随机选一种系别（不能落到 0，否则会被当成永远「异系」）
		var 系: int = int(args8[0]) if not args8.is_empty() else int(系表8[engine._rng.randi_range(0, 系表8.size() - 1)])
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
			询问(player.id, FANG_ZHU, 0, 0, GConst.CardSource.Hand,
				[{"value": 1, "label": "天雷劫火", "skill_id": TIAN_LEI_JIE_HUO},
				 {"value": 2, "label": "地裂波涛", "skill_id": DI_LIE_BO_TAO}],
				0, "", [], true,
				0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0,
				"【放逐】：选择放 1 张【末日预言】入场（背面为【末日预言】，正面由你选择）")
			return WAIT
		return p_yi_jiao_tu_ask({"player": player.id})
	# 放逐：选正面的牌 → 放【末日预言】入场（记下正面，翻面时直接用）
	if _放逐步 == 3:
		if not engine.has_reply():
			return WAIT
		var r3: Dictionary = take_skill_reply_full()
		var a3: Array = r3.get("args", [])
		# 超时 / 跳过：随机从【天雷劫火】/【地裂波涛】里选一个，不卡住流程
		var 选: int = int(a3[0]) if not a3.is_empty() else engine._rng.randi_range(1, 2)
		var 正面: String = 地裂波涛名 if 选 == 2 else 天雷劫火名
		engine.加场卡({"id": 末日预言名, "owner": player.id, "attached": -1,
			"counter": 0, "counter_max": 预言上限, "state": 0, "pile": [], "front": 正面})
		_放逐步 = 4
		# 玩家自己选 6 张手牌作为【预言】（朝下洗混）
		询问(player.id, FANG_ZHU, 6, 0, GConst.CardSource.Hand, [], 6, "", [], false,
			0, player.id, [], 6, {}, 0, 0, false, [], true, -1, 0,
			"【放逐】：选择 6 张手牌面朝下作为【预言】")
		return WAIT
	# 放逐：6 张手牌洗混成【预言】→ 解除不爆牌 → +1 额外行动（攻击/法术二合一）
	if _放逐步 == 4:
		var r4: Dictionary = take_skill_reply_full()
		_放逐步 = 0
		var 已选: Array = []
		for c: Variant in r4.get("card_ids", []):
			var cid: int = int(c)
			if 已选.size() < 6 and player.有手牌(cid) and not 已选.has(cid):
				已选.append(cid)
		# 超时 / 没选够 6 张：从手牌里随机补足，保证放逐一定结算完
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
			if 取 > 0 and 新堆.size() < 6:
				新堆.append(取)
		# 兜底：选中里混进了已经不在手 / 0 号这类取不出来的牌时，再从当前手牌补满 6 张
		while 新堆.size() < 6 and not player.hand_cards.is_empty():
			var 补: int = player.取出实例(player.hand_cards, player.hand_cards[0])
			if 补 <= 0:
				break
			新堆.append(补)
		新堆.shuffle()
		var 表: Dictionary = engine.取场卡(末日预言名)
		表["pile"] = 新堆
		表["counter"] = 新堆.size()
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
	notice_skill(MO_RI_YU_YAN, [player.id])
	_在展示 = 名
	_展示模式.clear()
	_展示序号 = 0
	_展示贪婪 = false
	_展示对手 = -1
	# 先把「是否发动贪婪」问掉，再决定发动一项还是两项（贪婪＝两项都发动、顺序自定）
	_展示步 = 10
	return p_yi_jiao_tu_ask({"player": player.id})


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


## 系别枚举 → 询问选项（ask_skill 只收 {value,label} 字典，纯数字数组会在运行时出错）
func _系别选项(系表: Array) -> Array:
	var out: Array = []
	for 系: Variant in 系表:
		out.append({"value": int(系), "label": "%s系" % GConst.element_to_chinese(int(系))})
	return out


## 当前展示的这张牌该用哪个技能号（天雷劫火 9507 / 地裂波涛 9508）：询问与伤害来源都用它
func _展示技能号() -> int:
	return DI_LIE_BO_TAO if _在展示 == 地裂波涛名 else TIAN_LEI_JIE_HUO


## 展示流程里「每一项」的伤害：目标对手弃完牌后造成 X+1 点法术伤害③
func _展示本项伤害() -> int:
	_展示步 = 9
	if _展示对手 > 0:
		engine.push_harm({
			"src": player.id, "dst": _展示对手, "point": _展示X + 1,
			"cause": _展示技能号(), "type": GConst.HarmType.Magic,
		})
		return URGENT
	return _展示本项结束()


## 一项结算完：下一项（贪婪）或收尾（清翻面标记，放逐放进新【末日预言】后还能再翻）
func _展示本项结束() -> int:
	_展示对手 = -1
	_展示序号 += 1
	_展示步 = 3
	return p_yi_jiao_tu_ask({"player": player.id})


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


