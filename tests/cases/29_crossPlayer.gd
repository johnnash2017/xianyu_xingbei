extends 自检用例
## F9 跨玩家操作：
## - 右手边最近队友：nearest_teammate_id（沿 post 方向，不含自己）。
## - 随机弃手牌：从真实手牌随机抽 n 张离手进弃牌堆，不需要玩家选牌。
## - 跳过行动阶段：请求跳过 → SActionPhase 直接收尾，并记录「本回合跳过 / 来源」供后续技能读取。
## - 提炼前 / 后钩子：p_before_extract（全体同步，可 forbidden 取消）、p_after_extract（星石已移动，可等待）；
##   p_after_special 的 ctx 增加 action_id。
## - 手牌补 / 弃到 N：不足时强制摸牌补齐，超出时由牌主自己选弃（或随机弃）；支持其他玩家。
## - 跨玩家询问：由当前角色向队友发起询问，回复仍回到发起询问的钩子（10601 由队友指定目标）。
## - 组合：10601 式「找右手边队友 → 队友选目标 → 随机弃自己 1 张 → 目标强制摸 1 张」。

## dummy 观察角色：记录回合结束时的「跳过行动阶段」标记
class 跳过观察角色:
	extends BattleRole

	var 记录: Array = []

	func p_turn_end(ctx: Dictionary) -> int:
		if int(ctx.get("player", -1)) == player.id:
			记录.append({
				"跳过": engine.本回合跳过行动阶段,
				"来源": engine.本回合跳过行动阶段来源,
			})
		return SUCCESS


## dummy 观察角色：记录提炼前 / 后（以及 p_after_special 的 action_id）
class 提炼观察角色:
	extends BattleRole

	## 是否在 p_before_extract 里把 forbidden 置 true（模拟 10604「你不能提炼」之类）
	var 禁止: bool = false
	var 前记录: Array = []
	var 后记录: Array = []
	var 特殊行动记录: Array = []

	func p_before_extract(ctx: Dictionary) -> int:
		前记录.append({
			"ctx": ctx.duplicate(),
			"team_gem": engine.team_gem[player.color],
			"team_crystal": engine.team_crystal[player.color],
		})
		if 禁止:
			ctx["forbidden"] = true
		return SUCCESS

	func p_after_extract(ctx: Dictionary) -> int:
		var 提炼者: BattlePlayer = engine.p(int(ctx.get("player", -1)))
		后记录.append({
			"ctx": ctx.duplicate(),
			"team_gem": engine.team_gem[player.color],
			"team_crystal": engine.team_crystal[player.color],
			"提炼者_gem": 提炼者.gem if 提炼者 != null else -1,
			"提炼者_crystal": 提炼者.crystal if 提炼者 != null else -1,
		})
		return SUCCESS

	func p_after_special(ctx: Dictionary) -> int:
		if bool(ctx.get("special_action", false)):
			特殊行动记录.append(ctx.duplicate())
		return SUCCESS


## dummy 角色：10601 式跨玩家组合（队友选目标 → 随机弃自己 → 目标强制摸牌）
class 组合角色:
	extends BattleRole

	const 技能号: int = 9905

	var 已问: bool = false
	var 队友id: int = -1
	var 记录: Array = []

	func p_turn_begin(_ctx: Dictionary) -> int:
		if not 已问:
			已问 = true
			队友id = nearest_teammate_id(player.id, true)
			if 队友id < 0:
				return SUCCESS
			# 由队友（不是当前行动者）指定目标对手：回复仍回到本钩子
			engine.ask_skill(队友id, 技能号, 0, 1)
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		var dst: int = -1
		var 选定: Array = r.get("dst_ids", [])
		if not 选定.is_empty():
			dst = int(选定[0])
		var 弃牌: Array = engine.随机弃手牌(player.id, 1, 技能号)
		if dst >= 0:
			engine.强制摸牌(dst, 1, 技能号)
		记录.append({"队友": 队友id, "dst": dst, "弃牌": 弃牌})
		return SUCCESS


var 引擎: BattleEngine = null
var 玩家1: BattlePlayer = null
var 玩家2: BattlePlayer = null
var 玩家3: BattlePlayer = null
var 玩家4: BattlePlayer = null
var 跳过观察: 跳过观察角色 = null
var 提炼观察: 提炼观察角色 = null
var 组合: 组合角色 = null
var 发送记录: Array = []


func _init() -> void:
	名称 = "跨玩家操作"


# ============================================================
# 工具
# ============================================================
func _取实体牌号(数量: int, 排除: Array = []) -> Array[int]:
	var out: Array[int] = []
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual or 排除.has(c.id) or out.has(c.id):
			continue
		out.append(c.id)
		if out.size() >= 数量:
			break
	return out


func _换手牌(p0: BattlePlayer, cards: Array) -> void:
	p0.hand_cards.clear()
	for c: Variant in cards:
		p0.hand_cards.append(int(c))


func _有错误输入(pid: int) -> bool:
	for r: Dictionary in 发送记录:
		if int(r["pid"]) == pid and int(r["msg"]) == GConst.Msg.ErrorInput:
			return true
	return false


func _卸下所有角色() -> void:
	for pid: int in 引擎.order:
		引擎.p(pid).role = null


func _挂角色(p0: BattlePlayer, 角色: BattleRole) -> void:
	角色.setup(p0, 引擎)
	p0.role = 角色


func _重置战斗() -> void:
	引擎._states.clear()
	引擎._清空等待()
	引擎._最后询问.clear()
	引擎._最后行动命令.clear()
	引擎.phase = BattleEngine.Phase.Playing
	引擎.current_id = 1
	引擎.round_id = 1
	引擎.行动允许 = GConst.ActionType.Any
	引擎.行动可放弃 = false
	引擎.行动额外 = false
	引擎.行动额外来源 = 0
	引擎.行动禁特殊 = false
	引擎.skip_action_phase = false
	引擎.跳过行动阶段来源 = 0
	引擎.本回合跳过行动阶段 = false
	引擎.本回合跳过行动阶段来源 = 0
	引擎.测试跳过回合 = -1
	引擎.deck.discard.clear()
	引擎.last_harm_cause = 0
	引擎.last_harm_type = 0
	引擎.team_morale[GConst.BLUE] = 10
	引擎.team_morale[GConst.RED] = 10
	引擎.team_gem[GConst.BLUE] = 0
	引擎.team_crystal[GConst.BLUE] = 0
	引擎.team_gem[GConst.RED] = 0
	引擎.team_crystal[GConst.RED] = 0
	发送记录.clear()
	for pid: int in 引擎.order:
		var p0: BattlePlayer = 引擎.p(pid)
		p0.hand_cards.clear()
		p0.cover_cards.clear()
		p0.basic_effects.clear()
		p0.additional_actions.clear()
		p0.cross_num = 0
		p0.reset_action_counts()
		p0.boot_skill_used = false
		p0.set_gem(0)
		p0.set_crystal(0)
	跳过观察.记录.clear()
	提炼观察.前记录.clear()
	提炼观察.后记录.clear()
	提炼观察.特殊行动记录.clear()
	提炼观察.禁止 = false
	组合.已问 = false
	组合.队友id = -1
	组合.记录.clear()


# ============================================================
# 用例主体
# ============================================================
func 跑() -> void:
	await 等帧(1)

	引擎 = BattleEngine.new()
	引擎.send_cb = func(pid: int, msg: int, data: Dictionary) -> void:
		发送记录.append({"pid": pid, "msg": msg, "data": data})
	引擎.add_player(1, GConst.BLUE, "蓝一")
	引擎.add_player(2, GConst.BLUE, "蓝二")
	引擎.add_player(3, GConst.RED, "红三")
	引擎.add_player(4, GConst.RED, "红四")
	引擎.start_with_roles({})
	玩家1 = 引擎.p(1)
	玩家2 = 引擎.p(2)
	玩家3 = 引擎.p(3)
	玩家4 = 引擎.p(4)
	跳过观察 = 跳过观察角色.new()
	提炼观察 = 提炼观察角色.new()
	组合 = 组合角色.new()

	_测试最近队友()
	_测试随机弃手牌()
	_测试调整手牌()
	_测试跳过行动阶段()
	_测试提炼钩子()
	_测试跨玩家询问与组合()

	# 收尾
	引擎._states.clear()
	引擎._清空等待()
	引擎.send_cb = Callable()


# ============================================================
# 右手边最近队友
# ============================================================
func _测试最近队友() -> void:
	_重置战斗()
	# 座次 1(蓝) 2(蓝) 3(红) 4(红)：1 的右手边最近队友是 2；2 绕一圈回到 1
	检(引擎.nearest_teammate_id(1, true) == 2, "1 号右手边最近队友应为 2")
	检(引擎.nearest_teammate_id(2, true) == 1, "2 号右手边绕一圈最近队友应为 1")
	检(引擎.nearest_teammate_id(3, true) == 4, "3 号右手边最近队友应为 4")
	检(引擎.nearest_teammate_id(4, true) == 3, "4 号右手边最近队友应为 3")
	检(引擎.nearest_teammate_id(1, false) == 2, "1 号左手边最近队友也应是 2")
	检(引擎.nearest_teammate_id(99, true) == -1, "不存在的玩家应返回 -1")


# ============================================================
# 随机弃手牌
# ============================================================
func _测试随机弃手牌() -> void:
	_重置战斗()
	var 手牌: Array[int] = _取实体牌号(3)
	_换手牌(玩家2, 手牌)
	var 弃: Array = 引擎.随机弃手牌(2, 1, 9901)
	检(弃.size() == 1, "随机弃 1 张应返回 1 张，实际 %d" % 弃.size())
	检(手牌.has(int(弃[0])), "随机弃的牌应来自原手牌")
	检(玩家2.hand_cards.size() == 2, "随机弃后手牌应剩 2，实际 %d" % 玩家2.hand_cards.size())
	检(引擎.deck.discard.has(int(弃[0])), "随机弃的牌应进弃牌堆")
	检(int(引擎.随机弃手牌(99, 1).size()) == 0, "不存在玩家应返回空")
	检(int(引擎.随机弃手牌(2, 0).size()) == 0, "0 张应返回空")

	# 手牌不足：弃现有的全部
	_重置战斗()
	_换手牌(玩家2, _取实体牌号(1))
	var 全弃: Array = 引擎.随机弃手牌(2, 5)
	检(全弃.size() == 1 and 玩家2.hand_cards.is_empty(), "手牌不足时应把现有手牌弃光")
	检(引擎.deck.discard.size() == 1, "弃掉的牌应进弃牌堆")


# ============================================================
# 手牌补 / 弃到 N
# ============================================================
func _测试调整手牌() -> void:
	# 不足：压标准摸牌状态补到 4（摸完由状态边界结算，再断言）
	_重置战斗()
	_换手牌(玩家2, _取实体牌号(2))
	检(引擎.调整手牌到(2, 4) == true, "补牌应压入摸牌状态，调用方需要挂起")
	引擎.run()
	检(玩家2.hand_cards.size() == 4, "补牌后手牌应为 4，实际 %d" % 玩家2.hand_cards.size())

	# 超出：由牌主自己选弃 2 张
	_重置战斗()
	_换手牌(玩家2, _取实体牌号(6))
	检(引擎.调整手牌到(2, 4) == true, "超出手牌应压入等待状态")
	引擎.run()
	检(引擎._await_id == 2, "调整手牌应询问 2 号选弃，实际等待 %s" % str(引擎._await_id))
	var 交: Array = []
	for i: int in range(2):
		交.append(玩家2.hand_cards[i])
	引擎.on_message(2, GConst.Msg.Respond, {
		"respond_id": GConst.RespondType.Discard, "src_id": 2,
		"args": [2, 9701, 2], "card_ids": 交, "dst_ids": [2],
	})
	检(玩家2.hand_cards.size() == 4, "选弃后手牌应为 4，实际 %d" % 玩家2.hand_cards.size())
	检(引擎.deck.discard.size() == 2, "选弃的 2 张应进弃牌堆")

	# 超出 + 随机弃：不问玩家，直接随机弃到目标
	_重置战斗()
	_换手牌(玩家2, _取实体牌号(6))
	检(引擎.调整手牌到(2, 4, 0, true) == false, "随机弃牌应当场完成")
	检(玩家2.hand_cards.size() == 4, "随机弃后手牌应为 4，实际 %d" % 玩家2.hand_cards.size())
	检(引擎.deck.discard.size() == 2, "随机弃的 2 张应进弃牌堆")

	# 调整其他角色的手牌（7804 的目标为其他角色）
	_重置战斗()
	_换手牌(玩家1, _取实体牌号(1))
	检(引擎.调整手牌到(1, 4) == true, "调整其他角色手牌也应压入摸牌状态")
	引擎.run()
	检(玩家1.hand_cards.size() == 4, "其他角色补牌后手牌应为 4")

	# 相同 / 非法目标：不改动
	_重置战斗()
	_换手牌(玩家2, _取实体牌号(4))
	检(引擎.调整手牌到(2, 4) == false and 玩家2.hand_cards.size() == 4, "张数相同不应改动")
	检(引擎.调整手牌到(99, 4) == false and 引擎.调整手牌到(2, -1) == false, "非法参数不应压状态")


# ============================================================
# 跳过行动阶段
# ============================================================
func _测试跳过行动阶段() -> void:
	_重置战斗()
	_卸下所有角色()
	_挂角色(玩家2, 跳过观察)
	引擎.current_id = 2
	引擎.请求跳过行动阶段(9906)
	检(引擎.skip_action_phase, "请求跳过后标记应置位")
	检(引擎.跳过行动阶段来源 == 9906, "跳过来源应为 9906")
	引擎.push(BattleEngine.SActionPhase.new())
	引擎.run()
	检(跳过观察.记录.size() == 1, "回合结束钩子应看到一次跳过记录")
	if not 跳过观察.记录.is_empty():
		检(bool(跳过观察.记录[0].get("跳过", false)), "本回合应被记录为跳过行动阶段")
		检(int(跳过观察.记录[0].get("来源", -1)) == 9906, "跳过来源应为 9906")
	检(not 引擎.skip_action_phase, "跳过标记应已被消费")
	检(引擎.current_id == 3, "跳过后应正常轮到 3 号，实际 %d" % 引擎.current_id)
	检(not 引擎.本回合跳过行动阶段 and int(引擎.本回合跳过行动阶段来源) == 0,
		"下个回合开始时应清掉本回合跳过记录")


# ============================================================
# 提炼前 / 后钩子
# ============================================================
func _测试提炼钩子() -> void:
	# 正常提炼：蓝队战绩区 2 宝石 / 1 水晶，1 号提炼 1 宝石 1 水晶
	_重置战斗()
	_卸下所有角色()
	_挂角色(玩家2, 提炼观察)
	引擎.team_gem[GConst.BLUE] = 2
	引擎.team_crystal[GConst.BLUE] = 1
	引擎.current_id = 1
	引擎.resolve_action(GConst.ActionType.Special, {
		"action_id": GConst.SpecialAction.Extract, "args": [1, 1], "dst_ids": [],
	})
	引擎.run()
	检(提炼观察.前记录.size() == 1, "提炼前钩子应对队友角色触发一次")
	if not 提炼观察.前记录.is_empty():
		var 前: Dictionary = 提炼观察.前记录[0]
		var 前ctx: Dictionary = 前.get("ctx", {})
		检(int(前ctx.get("player", -1)) == 1, "提炼前钩子应带提炼者 1")
		检((前ctx.get("args", []) as Array) == [1, 1], "提炼前钩子应带原始参数")
		检(int(前.get("team_gem", -1)) == 2 and int(前.get("team_crystal", -1)) == 1,
			"提炼前战绩区应仍是 2/1，实际 %s" % str(前))
	检(提炼观察.后记录.size() == 1, "提炼后钩子应触发一次")
	if not 提炼观察.后记录.is_empty():
		var 后: Dictionary = 提炼观察.后记录[0]
		var 后ctx: Dictionary = 后.get("ctx", {})
		检(int(后ctx.get("player", -1)) == 1, "提炼后钩子应带提炼者 1")
		检(int(后ctx.get("gem", -1)) == 1 and int(后ctx.get("crystal", -1)) == 1,
			"提炼后钩子应带本次提炼的 1 宝石 / 1 水晶")
		检(int(后.get("team_gem", -1)) == 1 and int(后.get("team_crystal", -1)) == 0,
			"提炼后战绩区应已扣到 1/0，实际 %s" % str(后))
		检(int(后.get("提炼者_gem", -1)) == 1 and int(后.get("提炼者_crystal", -1)) == 1,
			"提炼后提炼者个人能量应为 1/1，实际 %s" % str(后))
	检(引擎.team_gem[GConst.BLUE] == 1 and 引擎.team_crystal[GConst.BLUE] == 0,
		"提炼结算后战绩区应为 1/0")
	检(玩家1.gem == 1 and 玩家1.crystal == 1, "提炼者个人能量应为 1/1")
	检(提炼观察.特殊行动记录.size() == 1, "p_after_special 应收到提炼")
	if not 提炼观察.特殊行动记录.is_empty():
		检(int(提炼观察.特殊行动记录[0].get("action_id", -1)) == GConst.SpecialAction.Extract,
			"p_after_special 的 action_id 应为提炼")

	# 提炼前 forbidden：整个提炼被驳回，不移动星石
	_重置战斗()
	_卸下所有角色()
	_挂角色(玩家2, 提炼观察)
	提炼观察.禁止 = true
	引擎.team_gem[GConst.BLUE] = 2
	引擎.team_crystal[GConst.BLUE] = 1
	引擎.current_id = 1
	引擎.resolve_action(GConst.ActionType.Special, {
		"action_id": GConst.SpecialAction.Extract, "args": [1, 1], "dst_ids": [],
	})
	引擎.run()
	检(_有错误输入(1), "提炼前 forbidden 应驳回提炼")
	检(引擎.team_gem[GConst.BLUE] == 2 and 引擎.team_crystal[GConst.BLUE] == 1,
		"被驳回的提炼不应移动战绩区星石")
	检(玩家1.gem == 0 and 玩家1.crystal == 0, "被驳回的提炼不应给个人能量")
	检(提炼观察.后记录.is_empty(), "被驳回的提炼不应触发提炼后钩子")


# ============================================================
# 跨玩家询问 + 10601 式组合
# ============================================================
func _测试跨玩家询问与组合() -> void:
	_重置战斗()
	_卸下所有角色()
	_挂角色(玩家1, 组合)
	_换手牌(玩家1, _取实体牌号(3))
	_换手牌(玩家3, [])
	# 由 1 号在回合开始钩子里问队友 2 号「选目标对手」，再把目标摸牌 + 自己随机弃
	引擎.push(BattleEngine.SHook.new("p_turn_begin", {"player": 1}, []))
	引擎.run()
	检(组合.队友id == 2, "1 号右手边最近队友应为 2，实际 %d" % 组合.队友id)
	检(引擎._await_id == 2, "应由队友 2 号应答，实际等待 %s" % str(引擎._await_id))
	引擎.on_message(2, GConst.Msg.Respond, {
		"respond_id": 组合角色.技能号, "src_id": 2, "args": [1],
		"card_ids": [], "dst_ids": [3],
	})
	检(组合.记录.size() == 1, "跨玩家组合应完成一次结算")
	if not 组合.记录.is_empty():
		检(int(组合.记录[0].get("dst", -1)) == 3, "队友选择的目标应为 3")
		检((组合.记录[0].get("弃牌", []) as Array).size() == 1, "应随机弃掉 1 号 1 张手牌")
	检(玩家1.hand_cards.size() == 2, "随机弃后 1 号手牌应为 2，实际 %d" % 玩家1.hand_cards.size())
	检(玩家3.hand_cards.size() == 1, "被指定目标 3 号应强制摸 1 张")
	检(引擎.deck.discard.size() == 1, "随机弃的牌应进弃牌堆")
	检(not _有错误输入(2), "队友应答不应产生操作无效")
