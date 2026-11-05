extends 自检用例
## 异教徒（95）实际跑测：末日预言的【预言】堆、翻面、天雷劫火 / 地裂波涛的「展示时」、
## 【贪婪】两项都发动、【灾殃止息】移除、【献祭】、【放逐】（无视手牌上限）。
##
## 驱动方式与其它角色用例一致：直接调角色钩子 / 技能入口，把回复塞进引擎后 run()，
## 由状态栈自己推进（与线上同一条路径，不在用例里复制规则）。

const 角色路径: String = "res://scripts/battle/roles/role_yijiaotu.gd"

var 引擎: BattleEngine = null
var 角色: BattleRole = null
var 玩家1: BattlePlayer = null
var 玩家2: BattlePlayer = null
var 发送记录: Array = []


func _init() -> void:
	名称 = "异教徒（95）：末日预言 / 天雷劫火 / 地裂波涛 / 贪婪 / 灾殃止息"


func 跑() -> void:
	_检开局与手牌上限()
	_检状态显示资料()
	_检献祭同系()
	_检献祭异系()
	_检预言抽空翻面()
	_检翻面天雷()
	_检贪婪两项()
	_检灾殃止息()
	_检放逐()
	_检翻面用记下的正面()
	_检缺正面报错()
	_检末日日志()
	_检系别选项牌白()
	_检展示非法牌驳回()
	_检放逐非法牌驳回()
	_检放逐超时()
	_检放逐提示不切换()
	_检审判()
	_检审判超时()
	_检审判弃刃触发渗蚀()
	_检审判选项值对应()
	_检审判预言不超上限()
	_检审判摸牌先结算超限()
	_检审判零号座位摸牌()
	_检展示零号座位伤害()
	_检审判头像提示()
	_检审判同名牌两张()
	_检审判残留状态()
	引擎 = null


# ============================================================
# 建局
# ============================================================
func _建引擎() -> void:
	引擎 = BattleEngine.new()
	发送记录.clear()
	引擎.send_cb = func(pid: int, msg: int, data: Dictionary) -> void:
		发送记录.append({"pid": pid, "msg": msg, "data": data})
	引擎.add_player(1, GConst.BLUE, "甲")
	引擎.add_player(2, GConst.RED, "乙")
	引擎.add_player(3, GConst.BLUE, "丙")
	引擎.add_player(4, GConst.RED, "丁")
	引擎.start_with_roles({})
	for pid: int in 引擎.order:
		var p0: BattlePlayer = 引擎.p(pid)
		p0.role = null
		p0.hand_cards.clear()
		p0.cross_num = 0
	玩家1 = 引擎.p(1)
	玩家2 = 引擎.p(2)
	角色 = (load(角色路径) as GDScript).new()
	角色.setup(玩家1, 引擎)
	玩家1.role = 角色
	玩家1.role_id = 95
	引擎._states.clear()
	引擎._清空等待()
	引擎.phase = BattleEngine.Phase.Playing
	引擎.current_id = 1
	引擎.round_id = 1


## 设置「本回合伤害过的对手」（角色字段是 Array[int]，必须按类型赋，动态赋 Array 会报错）
func _设伤害目标(目标: Array[int]) -> void:
	角色._本回合伤害目标 = 目标


## 把一条回复塞进引擎（随后 run() 由状态栈取走）
func _应答(args: Array = [], dsts: Array = [], cards: Array = []) -> void:
	引擎._reply = {"args": args, "card_ids": cards, "dst_ids": dsts, "respond_id": 0}
	引擎._has_reply = true


## 跑到「问目标对手」的询问为止：途中的「治疗抵挡」询问一律答不用治疗
func _等到目标询问() -> bool:
	for i: int in range(10):
		引擎.run()
		if 引擎._await_id < 0:
			return false
		if 引擎._pending_respond_id == GConst.RespondType.Heal:
			_应答([0])
			continue
		return 引擎._await_id == 1 and 引擎._pending_respond_id == 9507
	return false


## 战斗日志里是否有包含片段的 Gossip
func _有日志(片段: String) -> bool:
	for r: Dictionary in 发送记录:
		if int(r["msg"]) != GConst.Msg.Gossip:
			continue
		if str((r["data"] as Dictionary).get("txt", "")).contains(片段):
			return true
	return false


## 是否播过某技能的发动通知
func _有技能通知(技能号: int) -> bool:
	for r: Dictionary in 发送记录:
		if int(r["msg"]) == GConst.Msg.Skill and int((r["data"] as Dictionary).get("skill_id", 0)) == 技能号:
			return true
	return false


## 最近一条指定技能号的技能询问命令（看 option_enabled / card_max 等）
func _最近命令(技能号: int) -> Dictionary:
	for i: int in range(发送记录.size() - 1, -1, -1):
		var r: Dictionary = 发送记录[i]
		if int(r["msg"]) != GConst.Msg.CmdReq:
			continue
		var 命令: Array = (r["data"] as Dictionary).get("commands", [])
		if 命令.is_empty():
			continue
		var c: Dictionary = 命令[0]
		if int(c.get("respond_id", 0)) == 技能号:
			return c
	return {}


## 最近一条指定技能号的技能询问文案（ask_text）
func _最近询问文案(技能号: int) -> String:
	for i: int in range(发送记录.size() - 1, -1, -1):
		var r: Dictionary = 发送记录[i]
		if int(r["msg"]) != GConst.Msg.CmdReq:
			continue
		var 命令: Array = (r["data"] as Dictionary).get("commands", [])
		if 命令.is_empty():
			continue
		var c: Dictionary = 命令[0]
		if int(c.get("respond_id", 0)) == 技能号:
			return str(c.get("ask_prompt", c.get("ask_text", "")))
	return ""


## 模拟超时兜底：引擎超时下发的就是空 args / 空 card_ids + is_timeout
func _应答超时() -> void:
	引擎._reply = {"args": [], "card_ids": [], "dst_ids": [], "is_timeout": true, "respond_id": 0}
	引擎._has_reply = true


## 最近一条「放逐」技能询问里的 option_skill_ids（选项各自挂的技能号）
func _询问选项技能号() -> Array:
	for i: int in range(发送记录.size() - 1, -1, -1):
		var r: Dictionary = 发送记录[i]
		if int(r["msg"]) != GConst.Msg.CmdReq:
			continue
		var 命令: Array = (r["data"] as Dictionary).get("commands", [])
		if 命令.is_empty():
			continue
		var c: Dictionary = 命令[0]
		if int(c.get("respond_id", 0)) == 9505:
			return (c.get("option_skill_ids", []) as Array).duplicate()
	return []


## 一项的收尾：目标对手「自选弃任意张该系牌」答不弃、治疗抵挡答不用；
## 直到出现下一项的目标询问（交给调用方）或整个展示流程结束
func _本项收尾() -> void:
	for i: int in range(8):
		引擎.run()
		if 引擎._await_id < 0:
			return
		if 引擎._pending_respond_id == GConst.RespondType.Heal:
			_应答([0])
			continue
		if 引擎._await_id == 玩家2.id and 引擎._pending_respond_id == 9507:
			_应答([], [], [])
			continue
		return


## 跑一段伤害结算：只在「治疗抵挡」询问时回答不用治疗，其它询问一律留着给用例自己答
func _收伤害() -> void:
	for i: int in range(8):
		引擎.run()
		if 引擎._await_id < 0 or 引擎._pending_respond_id != GConst.RespondType.Heal:
			return
		_应答([0])


## 给某玩家 n 张指定系别的牌（牌库牌的实例号 == 牌面），返回实例号
func _发牌(p: BattlePlayer, 元素: int, n: int) -> Array:
	var out: Array = []
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual or c.element_enum() != 元素:
			continue
		p.add_hand_cards([c.id])
		out.append(c.id)
		if out.size() >= n:
			break
	return out


func _放末日(预言: Array = []) -> void:
	# front 正常由【放逐】写入；测试造场卡也按正常状态带正面（翻面不再有兜底询问）
	引擎.加场卡({"id": "末日预言", "owner": 1, "attached": -1,
		"counter": 预言.size(), "counter_max": 6, "state": 0, "pile": 预言, "front": "天雷劫火"})


func _场卡(名: String) -> Dictionary:
	return 引擎.取场卡(名) if 引擎.有场卡(名) else {}


# ============================================================
# 1. 异端邪说：开局 +1 水晶；【末日预言】在场时手牌上限 -1
# ============================================================
func _检开局与手牌上限() -> void:
	_建引擎()
	检(玩家1.crystal == 1, "【异端邪说】开局应 +1 水晶：%d" % 玩家1.crystal)
	_放末日([101])
	角色.p_before_turn_begin({"player": 1})
	检(玩家1.hand_cards_max == GConst.HAND_CARDS_MAX - 1,
		"【末日预言】在场时手牌上限应 -1：%d" % 玩家1.hand_cards_max)
	引擎.移除场卡("末日预言")
	角色.p_before_turn_begin({"player": 1})
	检(玩家1.hand_cards_max == GConst.HAND_CARDS_MAX,
		"【末日预言】离场后手牌上限应恢复：%d" % 玩家1.hand_cards_max)


# ============================================================
# 2. 献祭：同系 → 移除该预言、+1 宝石
# ============================================================
func _检献祭同系() -> void:
	_建引擎()
	玩家1.set_crystal(0)
	var 两张: Array = _发牌(玩家1, GConst.CardElement.Wind, 2)
	_放末日(两张)
	# 【献祭】是「启动」：技能类型必须是 SpecialSkill（不是法术技能），否则会去消耗放逐给的额外行动
	var 献祭项: Dictionary = {}
	for 项: Dictionary in 角色.available_skills():
		if int(项.get("id", 0)) == 9503:
			献祭项 = 项
	检(int(献祭项.get("type", 0)) == GConst.ActionType.SpecialSkill,
		"【献祭】应作为启动技（SpecialSkill）下发：%s" % str(献祭项.get("type", 0)))
	# 和【魔眼】一样：点技能进二级技能栏选系别，选项 7 系齐全（含光/暗）并带系别标色
	var 献祭选项: Array = 献祭项.get("arg_choices", [])
	var 七系: Array[int] = [GConst.CardElement.Wind, GConst.CardElement.Water, GConst.CardElement.Fire,
		GConst.CardElement.Earth, GConst.CardElement.Thunder, GConst.CardElement.Light,
		GConst.CardElement.Darkness]
	检(献祭选项.size() == 七系.size(), "【献祭】应有 7 个系别选项：%d" % 献祭选项.size())
	var 选项正确: bool = 献祭选项.size() == 七系.size()
	for i: int in range(mini(献祭选项.size(), 七系.size())):
		var d: Dictionary = 献祭选项[i]
		var 参数: Array = d.get("args", [])
		if 参数.is_empty() or int(参数[0]) != 七系[i] \
				or (d.get("elements", []) as Array) != [七系[i]] \
				or not str(d.get("text", "")).ends_with("系"):
			选项正确 = false
	检(选项正确, "【献祭】选项应逐项带 args/elements/「X系」文案：%s" % str(献祭选项))
	var rc: int = 角色.p_special_skill({"action_id": 9503, "src_id": 1,
		"args": [GConst.CardElement.Wind]})
	检(rc == BattleRole.URGENT, "【献祭】应压入展示流程并返回 URGENT")
	检(玩家1.boot_skill_used, "发动启动技后应记 boot_skill_used（每回合只能一个）")
	引擎.run()
	检(引擎._await_id < 0, "系别已在二级栏选好，服务端不应再补问一次")
	# 头像飘字带系别：献祭*风系
	var 飘字: String = ""
	for r: Dictionary in 发送记录:
		if int(r["msg"]) != GConst.Msg.Skill:
			continue
		var 数据: Dictionary = r["data"]
		if int(数据.get("skill_id", 0)) == 9503:
			飘字 = str(数据.get("name", ""))
	检(飘字 == "献祭*风系", "【献祭】发动飘字应为「献祭*风系」，实际「%s」" % 飘字)
	var 表: Dictionary = _场卡("末日预言")
	检(int(表.get("pile", []).size()) == 1, "同系应移除 1 张【预言】：%d" % int(表.get("pile", []).size()))
	检(引擎.team_gem[GConst.BLUE] == 1, "同系应让战绩区 +1【宝石】")
	检(角色.v_magic_skill({"action_id": 9503, "src_id": 1}) == GConst.GE_INVALID_ACTION,
		"【献祭】不应再有法术技能入口（否则能被当成放逐给的额外法术行动用掉）")
	检(引擎.deck.discard.has(int(两张[1])), "被移除的【预言】应进弃牌堆")
	检(_有日志("[异教徒]从[异教徒]的【末日预言】移除 1 张牌"),
		"同系移除应写战斗日志（移除 1 张）")


# ============================================================
# 3. 献祭：异系 → 与牌库顶交换、该【预言】加入手牌
# ============================================================
func _检献祭异系() -> void:
	_建引擎()
	玩家1.set_crystal(0)
	var 风: Array = _发牌(玩家1, GConst.CardElement.Wind, 1)
	var 牌库顶前: int = int(引擎.deck.pile.back())
	_放末日([int(风[0])])
	角色.p_special_skill({"action_id": 9503, "src_id": 1, "args": [GConst.CardElement.Fire]})
	引擎.run()
	var 表: Dictionary = _场卡("末日预言")
	var 堆: Array = 表.get("pile", [])
	检(堆.size() == 1, "异系交换后【预言】堆应仍是 1 张：%d" % 堆.size())
	检(int(堆.back()) == 牌库顶前, "交换后堆顶应是原牌库顶那张：%d / %d" % [int(堆.back()), 牌库顶前])
	检(玩家1.有手牌(int(风[0])), "异系的【预言】应加入你手牌")
	检(引擎.team_gem[GConst.BLUE] == 0, "异系不应 +宝石")
	检(_有日志("[异教徒]从[异教徒]的【末日预言】移除 1 张牌")
		and _有日志("[异教徒]在[异教徒]的【末日预言】放入 1 张牌"),
		"异系交换应写「移除 1 张 + 放入 1 张」两条日志")


# ============================================================
# 3b. 伤害摸牌抽空最后一张【预言】→ 这一次伤害结算完再翻面
# ============================================================
func _检预言抽空翻面() -> void:
	_建引擎()
	玩家1.set_crystal(0)
	_放末日([101])
	检(int(角色.call("伤害摸牌替换", 1)) == 101, "伤害摸牌应从预言堆拿最后 1 张")
	# 翻面要等伤害流水线最后一步（p_harm_end）才压钩子
	检(角色.p_harm_end({"src": 2, "dst": 1,
		"harm": {"src": 2, "dst": 1, "point": 1, "type": GConst.HarmType.Magic}}) == BattleRole.SUCCESS,
		"伤害结束钩子应正常返回")
	引擎.run()
	检(引擎.有场卡("天雷劫火") and not 引擎.有场卡("末日预言"),
		"抽空后应直接按放逐记下的正面翻成【天雷劫火】（不再询问二选一）")


# ============================================================
# 4. 翻面 + 天雷劫火「展示时」（无贪婪）
# ============================================================
func _检翻面天雷() -> void:
	_建引擎()
	玩家1.set_crystal(0)
	玩家1.set_gem(0)
	var 雷: Array = _发牌(玩家1, GConst.CardElement.Thunder, 2)
	var 敌雷: Array = _发牌(玩家2, GConst.CardElement.Thunder, 1)
	var 敌手牌前: int = 玩家2.hand_cards.size()
	_放末日([])
	角色._检查预言取空()
	引擎.run()
	检(引擎.有场卡("天雷劫火") and not 引擎.有场卡("末日预言"),
		"翻面应直接按放逐记下的正面变成【天雷劫火】")
	检(not _有技能通知(9504), "翻面本身不应播【末日预言】")
	检(_有技能通知(9507), "翻面成【天雷劫火】后应播它的技能发动")
	检(引擎._await_id == 1, "能量为 0 时应跳过贪婪、直接问系别")
	# 四系选项板：本被动（天雷）的雷/火可发，另一个被动（地裂）的地/水置灰；
	# 选项带系别标色 + 「选中后本系效果」提示（完整说明在没选时显示）
	var 系别选项: Array = 角色.call("_展示系别选项")
	检(系别选项.size() == 4
		and (系别选项[0] as Dictionary).get("elements", []) == [GConst.CardElement.Thunder]
		and not str((系别选项[0] as Dictionary).get("提示", "")).is_empty()
		and str((系别选项[1] as Dictionary).get("提示", "")).contains("火系")
		and (系别选项[0] as Dictionary).get("enabled", false)
		and (系别选项[1] as Dictionary).get("enabled", false)
		and not (系别选项[2] as Dictionary).get("enabled", true)
		and not (系别选项[3] as Dictionary).get("enabled", true),
		"四系选项板应只开雷/火、置灰地/水，并带系别标色与效果提示：%s" % str(系别选项))
	# 目标头像伤害提示：伤害＝弃牌数+1，选 0 张也显示 1
	var 指示: Dictionary = GConst.技能指示器.get(9507, {})
	检(str(指示.get("文案", "")) == "%d 法术伤害"
		and int(指示.get("每牌", 0)) == 1 and int(指示.get("偏移", 0)) == 1
		and bool(指示.get("空选也算", false)),
		"天雷劫火应配「%%d 法术伤害（不写点）、每牌 1 + 偏移 1、空选也算」：%s" % str(指示))
	var 提示窗: Control = load("res://scripts/ui/battle_mobile.gd").new()
	检(int(提示窗.call("_提示数值", 指示, 0)) == 1, "没选牌时头像伤害应显示 1")
	var 两张已选: Array[int] = [1, 2]
	提示窗.set("_sel_cards", 两张已选)
	检(int(提示窗.call("_提示数值", 指示, 0)) == 3, "选 2 张牌时头像伤害应显示 3")
	提示窗.queue_free()
	# 系别选项、弃牌、目标在同一次询问里，按一次确定提交
	var 合并问: Dictionary = _最近命令(9507)
	var 选项牌白: Array = 合并问.get("option_cards", [])
	检(int(合并问.get("card_max", 0)) == 4 and (合并问.get("dst_ids", []) as Array).has(2)
		and (合并问.get("option_enabled", []) as Array) == [true, true, false, false]
		and 选项牌白.size() == 4
		and not ((选项牌白[0] as Dictionary).get("ids", []) as Array).is_empty()
		and ((选项牌白[2] as Dictionary).get("ids", []) as Array) == [-1],
		"合并询问应带四系选项、各自的牌白名单、最多 4 张牌和目标 2：%s" % str(合并问))
	_应答([GConst.CardElement.Thunder], [2], 雷)
	引擎.run()
	检(引擎._await_id == 2, "应问目标对手弃任意张该系牌（等待 %s / %s）"
		% [str(引擎._await_id), str(引擎._await_kind)])
	# 这一步不能取消（可以一张都不弃，但没有「取消」按钮）
	var 目标弃问: Dictionary = {}
	for r: Dictionary in 发送记录:
		if int(r["msg"]) != GConst.Msg.CmdReq:
			continue
		var 命令2: Array = (r["data"] as Dictionary).get("commands", [])
		if 命令2.is_empty():
			continue
		var c2: Dictionary = 命令2[0]
		if int(c2.get("respond_id", 0)) == 9507 and int(c2.get("src_id", -1)) == 2:
			目标弃问 = c2
	检(not 目标弃问.is_empty() and bool(目标弃问.get("can_cancel", true)) == false,
		"目标弃牌询问应不可取消：%s" % str(目标弃问.get("can_cancel", "缺省")))
	_应答([], [], 敌雷)
	_收伤害()
	检(引擎.deck.discard.has(int(敌雷[0])), "目标对手弃掉的牌应进弃牌堆")
	检(玩家2.hand_cards.size() == 敌手牌前 - 1 + 3,
		"目标应弃 1 张、再因 3 点法术伤害摸 3 张：%d → %d"
		% [敌手牌前, 玩家2.hand_cards.size()])
	检(玩家1.hand_cards.size() == 雷.size() - 2 + 2, "你弃 2 张再摸 2 张")
	检(引擎.有场卡("天雷劫火"), "展示结算完后【天雷劫火】应留在场上（等灾殃止息移除）")


# ============================================================
# 5. 贪婪：两项都发动、顺序由玩家选
# ============================================================
func _检贪婪两项() -> void:
	_建引擎()
	检(玩家1.get_energy() >= 1, "开局应有 1 点能量可供【贪婪】")
	var 敌手牌前: int = 玩家2.hand_cards.size()
	_放末日([])
	角色._检查预言取空()
	引擎.run()
	检(引擎.有场卡("天雷劫火"), "翻面应直接按 front 变成【天雷劫火】")
	检(引擎._await_id == 1, "有能量时应先问是否发动【贪婪】（等待 %s）" % str(引擎._await_id))
	_应答([1])          # 发动贪婪
	引擎.run()
	检(玩家1.get_energy() == 0, "【贪婪】应消耗 1 点能量")
	# 不再先问「先后顺序」：直接进四系选项板；天雷的两个系可发，地裂的两个系置灰
	var 板1: Dictionary = _最近命令(9507)
	检((板1.get("option_enabled", []) as Array) == [true, true, false, false],
		"贪婪后应直接给四系选项板（雷/火可用、地/水置灰）：%s" % str(板1.get("option_enabled", [])))
	# 第一项：雷系。系别+弃牌+目标一次提交，本次 0 张牌 → 1 点伤害
	_应答([GConst.CardElement.Thunder], [2])
	引擎.run()
	_本项收尾()   # 可能插入治疗抵挡 / 目标弃牌询问，都答掉等回到板子
	# 回到板子：雷已用，只剩火
	var 板2: Dictionary = _最近命令(9507)
	检((板2.get("option_enabled", []) as Array) == [false, true, false, false],
		"发完雷系后应只剩火系可用：%s" % str(板2.get("option_enabled", [])))
	_应答([GConst.CardElement.Fire], [2])
	引擎.run()
	_本项收尾()
	检(引擎._await_id < 0, "两项都发完后不应再问（等待 %s）" % str(引擎._await_id))
	检(玩家2.hand_cards.size() == 敌手牌前 + 2,
		"两项各 1 点伤害，目标应摸 2 张：%d → %d" % [敌手牌前, 玩家2.hand_cards.size()])
	检(引擎.有场卡("天雷劫火"), "两项结算完后场卡仍在")


# ============================================================
# 6. 灾殃止息：异教徒回合开始移除天雷 / 地裂
# ============================================================
func _检灾殃止息() -> void:
	_建引擎()
	引擎.加场卡({"id": "天雷劫火", "owner": 1, "attached": -1,
		"counter": 0, "counter_max": 0, "state": 1})
	引擎.加场卡({"id": "地裂波涛", "owner": 1, "attached": -1,
		"counter": 0, "counter_max": 0, "state": 2})
	角色.p_before_turn_begin({"player": 1})
	检(not 引擎.有场卡("天雷劫火") and not 引擎.有场卡("地裂波涛"),
		"【灾殃止息】应移除【天雷劫火】/【地裂波涛】")
	var 有通知: bool = false
	for r: Dictionary in 发送记录:
		if int(r["msg"]) == GConst.Msg.Skill and int((r["data"] as Dictionary).get("skill_id", 0)) == 9509:
			有通知 = true
	检(有通知, "【灾殃止息】移除时应播技能通知")


# ============================================================
# 7. 放逐：无视手牌上限摸 6、6 张手牌作【预言】、额外行动
# ============================================================
func _检放逐() -> void:
	_建引擎()
	# 手里 5 张、场上已有【末日预言】（手牌上限 5）：摸 6 张会超过上限，
	# 但放逐期间是「不爆牌」状态，不该弹超限弃牌。
	_发牌(玩家1, GConst.CardElement.Wind, 5)
	_放末日([101, 102])
	角色.p_before_turn_begin({"player": 1})
	检(玩家1.hand_cards_max == 5, "放逐前手牌上限应为 5：%d" % 玩家1.hand_cards_max)
	# 摸几张由二级技能栏选（同魔眼）：技能栏带三个 arg_choices，不选返回就不该通过校验
	var 放逐项: Dictionary = {}
	for 项: Dictionary in 角色.available_skills():
		if int(项.get("id", 0)) == 9505:
			放逐项 = 项
	检(not 放逐项.is_empty() and (放逐项.get("arg_choices", []) as Array).size() == 3,
		"【放逐】应给出摸 6/7/8 三个档（二级技能栏）")
	var 档: Array = 放逐项.get("arg_choices", [])
	检(int(档[0].get("args", [0])[0]) == 6 and int(档[2].get("args", [0])[0]) == 8,
		"三档应分别是 6 / 7 / 8 张")
	检(角色.v_magic_skill({"action_id": 9505, "src_id": 1, "args": []}) == GConst.GE_INVALID_ARGUMENT,
		"没选摸牌档（按「返回」）时不应通过校验")
	var rc: int = 角色.p_magic_skill({"action_id": 9505, "src_id": 1, "args": [6]})
	检(rc == BattleRole.URGENT, "【放逐】应进入摸牌流程")
	引擎.run()
	检(玩家1.hand_cards.size() == 11, "摸 6 张后应 11 张手牌：%d" % 玩家1.hand_cards.size())
	检(引擎._pending_respond_id == 9505,
		"不爆牌状态下不应弹超限弃牌（当前询问号 %s）" % str(引擎._pending_respond_id))
	检(引擎._await_id == 1, "摸完牌应问放哪张【末日预言】（等待 %s）" % str(引擎._await_id))
	检(_询问选项技能号() == [9507, 9508],
		"正面二选一的选项应挂技能号（悬停看被动说明）：%s" % str(_询问选项技能号()))
	# 同一次询问里同时选正面 + 6 张手牌，且不可取消
	var 组合问: Dictionary = {}
	for r: Dictionary in 发送记录:
		if int(r["msg"]) != GConst.Msg.CmdReq:
			continue
		var 命令: Array = (r["data"] as Dictionary).get("commands", [])
		if 命令.is_empty():
			continue
		var c: Dictionary = 命令[0]
		var 参: Array = c.get("args", [])
		if int(c.get("respond_id", 0)) == 9505 and 参.size() > 3 and int(参[3]) == 2:
			组合问 = c
	检(not 组合问.is_empty(), "放逐应只问一次（正面 + 6 张手牌合并）")
	if not 组合问.is_empty():
		检(int(组合问.get("card_max", 0)) == 6, "合并询问应要求选 6 张手牌：%s" % str(组合问.get("card_max")))
		检(not bool(组合问.get("can_cancel", true)), "放逐这一步不允许取消")
		检(组合问.get("option_no_prompt_change", []) == [true, true],
			"放逐的正面选项应标记「选中不改提示条」：%s" % str(组合问.get("option_no_prompt_change", [])))
	var 手: Array = 玩家1.hand_cards.duplicate()
	var 选六: Array = []
	for i: int in range(6):
		选六.append(int(手[i]))
	_应答([1], [], 选六)   # 天雷劫火 + 6 张
	引擎.run()
	var 表: Dictionary = _场卡("末日预言")
	检(int(表.get("counter", 0)) == 6 and int(表.get("pile", []).size()) == 6,
		"6 张手牌应成为【预言】：%d" % int(表.get("counter", 0)))
	检(str(表.get("front", "")) == "天雷劫火", "放置时应记下正面为【天雷劫火】：%s"
		% str(表.get("front", "")))
	# 正面是隐藏信息：只有拥有者自己的快照能拿到，别人拿不到
	var 自己正面: String = ""
	var 别人正面: String = ""
	for 项: Dictionary in 引擎.game_info(1).get("field_cards", []):
		if str(项.get("id", "")) == "末日预言":
			自己正面 = str(项.get("front", ""))
	for 项: Dictionary in 引擎.game_info(2).get("field_cards", []):
		if str(项.get("id", "")) == "末日预言":
			别人正面 = str(项.get("front", ""))
	检(自己正面 == "天雷劫火", "拥有者自己的快照里应带正面：%s" % 自己正面)
	检(别人正面.is_empty(), "别人的快照里不应带正面：%s" % 别人正面)
	检(玩家1.hand_cards.size() == 5, "选走 6 张后应剩 5 张：%d" % 玩家1.hand_cards.size())
	检(玩家1.get_energy() == 0, "【放逐】应消耗 1 点能量")
	# 回合限定：同一回合只能发动一次
	var 放逐项2: Dictionary = {}
	for 项2: Dictionary in 角色.available_skills():
		if int(项2.get("id", 0)) == 9505:
			放逐项2 = 项2
	检(not bool(放逐项2.get("enabled", true)), "同一回合内【放逐】应置灰")
	检(角色.v_magic_skill({"action_id": 9505, "src_id": 1, "args": [6]}) == GConst.GE_INVALID_ACTION,
		"同一回合第二次【放逐】不应通过校验")
	检(角色.p_magic_skill({"action_id": 9505, "src_id": 1, "args": [6]}) == GConst.GE_INVALID_ACTION,
		"直接调执行体也不能绕过回合限定")
	# 下回合开始重置
	玩家1.set_crystal(1)
	角色.p_before_turn_begin({"player": 1})
	var 放逐项3: Dictionary = {}
	for 项3: Dictionary in 角色.available_skills():
		if int(项3.get("id", 0)) == 9505:
			放逐项3 = 项3
	检(bool(放逐项3.get("enabled", false)), "新回合开始【放逐】应重新可发动")
	# 「额外 +1【攻击行动】或【法术行动】」= 一份攻击/法术都能用的额外行动
	var 额外: Dictionary = {}
	for a: Dictionary in 玩家1.additional_actions:
		if int(a.get("cause", 0)) == 9505:
			额外 = a
	检(not 额外.is_empty(), "【放逐】应给 1 份额外行动")
	检(int(额外.get("allow_action", 0)) == GConst.ActionType.AttackMagic,
		"这份额外行动应同时允许攻击与法术：%s" % str(额外.get("allow_action", 0)))
	检(引擎._不爆牌.is_empty(), "放逐结算完应解除不爆牌状态")


# ============================================================
# 6b. 系别选项自带牌白名单（供通用选项置灰逻辑用）
# ============================================================
func _检系别选项牌白() -> void:
	_建引擎()
	var 雷: Array = _发牌(玩家1, GConst.CardElement.Thunder, 1)
	var 火: Array = _发牌(玩家1, GConst.CardElement.Fire, 1)
	var 选项: Array = 角色.call("_展示系别选项")
	检(选项.size() == 4, "应有四个系别选项")
	var 雷白: Array = (选项[0] as Dictionary).get("cards", [])
	var 火白: Array = (选项[1] as Dictionary).get("cards", [])
	检(雷白 == [GConst.牌号(int(雷[0]))],
		"雷系选项的牌白应只有手里的雷牌：%s" % str(雷白))
	检(火白 == [GConst.牌号(int(火[0]))],
		"火系选项的牌白应只有手里的火牌：%s" % str(火白))
	检((选项[2] as Dictionary).get("cards", []) == [GConst.手牌白名单_全禁],
		"没有地系手牌时该选项应下 -1（一张都不给点）")


# ============================================================
# 6c. 服务端：合并询问里提交非本系牌 → 驳回重问
# ============================================================
func _检展示非法牌驳回() -> void:
	_建引擎()
	玩家1.set_crystal(0)
	玩家1.set_gem(0)
	_发牌(玩家1, GConst.CardElement.Thunder, 1)
	var 火: Array = _发牌(玩家1, GConst.CardElement.Fire, 1)
	_放末日([])
	角色._检查预言取空()
	引擎.run()
	检(引擎._await_id == 1 and 引擎._pending_respond_id == 9507,
		"应已进入天雷劫火合并询问")
	var 标记: int = 发送记录.size()
	# 选雷系却提交火牌：应 ErrorInput + 重新问这一步，不能静默吞掉
	_应答([GConst.CardElement.Thunder], [2], 火)
	引擎.run()
	var 有驳回: bool = false
	for i: int in range(标记, 发送记录.size()):
		if int(发送记录[i]["msg"]) == GConst.Msg.ErrorInput:
			有驳回 = true
	检(有驳回, "提交非本系牌应被驳回")
	检(玩家1.有手牌(int(火[0])), "被驳回的火牌不应被静默弃掉")
	检(引擎._await_id == 1 and 引擎._pending_respond_id == 9507,
		"驳回后应重新问合并询问")


# ============================================================
# 6d. 放逐：非超时提交重复/不在手的 6 张 → 驳回重问，不静默补齐
# ============================================================
func _检放逐非法牌驳回() -> void:
	_建引擎()
	_发牌(玩家1, GConst.CardElement.Wind, 6)
	角色._放逐步 = 2
	引擎.push(BattleEngine.SHook.new("p_yi_jiao_tu_ask", {"player": 1}, []))
	引擎.run()
	检(引擎._await_id == 1 and 引擎._pending_respond_id == 9505, "应先问放逐的正面 + 6 张手牌")
	var 手: Array = 玩家1.hand_cards.duplicate()
	var 重复: Array = [int(手[0]), int(手[0]), int(手[1]), int(手[2]), int(手[3]), int(手[4])]
	var 标记: int = 发送记录.size()
	_应答([1], [], 重复)
	引擎.run()
	var 有驳回: bool = false
	for i: int in range(标记, 发送记录.size()):
		if int(发送记录[i]["msg"]) == GConst.Msg.ErrorInput:
			有驳回 = true
	检(有驳回, "放逐提交重复牌应被驳回")
	检(玩家1.hand_cards.size() == 6, "驳回后手牌不应被取走")
	检(引擎._await_id == 1 and 引擎._pending_respond_id == 9505, "驳回后应重新问放逐这一步")


# ============================================================
# 7a. 伤害摸牌从【末日预言】摸走：写卡牌日志 + 播技能发动
# ============================================================
func _检末日日志() -> void:
	_建引擎()
	_放末日([101, 102])
	检(int(角色.伤害摸牌替换(2)) == 102, "2 号因伤害摸牌应改从【预言】堆拿最后 1 张")
	var 名2: String = "[%s]" % Data.role_name(玩家2.role_id)
	检(_有日志("%s从[异教徒]的【末日预言】摸走 1 张牌" % 名2),
		"摸走预言应写战斗日志：%s" % str(发送记录))
	检(_有技能通知(9504), "从预言堆摸牌应播【末日预言】技能发动")


# ============================================================
# 7b. 场卡缺少 front：不翻面、不询问，战斗日志输出 [报错]
# ============================================================
func _检缺正面报错() -> void:
	_建引擎()
	引擎.加场卡({"id": "末日预言", "owner": 1, "attached": -1,
		"counter": 0, "counter_max": 6, "state": 0, "pile": []})
	角色._检查预言取空()
	引擎.run()
	检(引擎.有场卡("末日预言") and not 引擎.有场卡("天雷劫火")
		and not 引擎.有场卡("地裂波涛"), "缺少 front 时不应翻面")
	检(引擎._await_id < 0, "缺少 front 时不应弹任何询问")
	var 报错: String = ""
	for r: Dictionary in 发送记录:
		if int(r["msg"]) != GConst.Msg.Gossip:
			continue
		var 数据: Dictionary = r["data"]
		if int(数据.get("type", 0)) == GConst.GossipType.Error:
			报错 = str(数据.get("txt", ""))
	检(报错.contains("front") and 报错.contains("无法翻面"),
		"缺少 front 应在战斗日志输出 [报错]：%s" % 报错)
	var 窗: Control = load("res://scripts/ui/battle_mobile.gd").new()
	检(窗.call("_日志标签", GConst.GossipType.Error) == "报错",
		"客户端应把 GossipType.Error 显示成 [报错]")
	窗.queue_free()


# ============================================================
# 8. 放逐放下的【末日预言】翻面时用记下的正面（不再问二选一）
# ============================================================
func _检翻面用记下的正面() -> void:
	_建引擎()
	引擎.加场卡({"id": "末日预言", "owner": 1, "attached": -1,
		"counter": 0, "counter_max": 6, "state": 0, "pile": [], "front": "地裂波涛"})
	角色._检查预言取空()
	引擎.run()
	检(引擎.有场卡("地裂波涛") and not 引擎.有场卡("末日预言"),
		"应按记下的正面翻成【地裂波涛】")
	检(_有技能通知(9508), "翻面成【地裂波涛】后应播它的技能发动")
	检(引擎._pending_respond_id != 9504 or 引擎._await_id < 0,
		"已记正面时不应再问翻面二选一（询问号 %s）" % str(引擎._pending_respond_id))


# ============================================================
# 9. 放逐超时兜底：正面随机、6 张手牌自动放
# ============================================================
func _检放逐超时() -> void:
	_建引擎()
	var rc: int = 角色.p_magic_skill({"action_id": 9505, "src_id": 1, "args": [6]})
	检(rc == BattleRole.URGENT, "【放逐】应进入摸牌流程")
	引擎.run()
	检(引擎._await_id == 1 and 引擎._pending_respond_id == 9505,
		"摸完牌应问正面（等待 %s / 号 %s）" % [str(引擎._await_id), str(引擎._pending_respond_id)])
	# 合并询问超时：随机选正面 + 自动放 6 张手牌，不再有第二问
	_应答超时()
	引擎.run()
	var 表: Dictionary = _场卡("末日预言")
	var 正面: String = str(表.get("front", ""))
	检(正面 == "天雷劫火" or 正面 == "地裂波涛", "超时应随机选一个正面：%s" % 正面)
	检(int(表.get("counter", 0)) == 6 and int(表.get("pile", []).size()) == 6,
		"超时应自动放 6 张作为【预言】：%d" % int(表.get("counter", 0)))
	检(玩家1.hand_cards.is_empty(), "6 张都被放成【预言】后手牌应为空：%d" % 玩家1.hand_cards.size())
	var 有额外: bool = false
	for a: Dictionary in 玩家1.additional_actions:
		if int(a.get("cause", 0)) == 9505 and int(a.get("allow_action", 0)) == GConst.ActionType.AttackMagic:
			有额外 = true
	检(有额外, "超时结算完也应给那份攻击/法术合一的额外行动")
	检(引擎._不爆牌.is_empty(), "超时结算完应解除不爆牌状态")


# ============================================================
# 10. 审判：只发动一次、队友弃牌文案、超时自动弃一张
# ============================================================
func _检审判() -> void:
	_建引擎()
	_发牌(玩家1, GConst.CardElement.Wind, 1)
	_发牌(引擎.p(3), GConst.CardElement.Fire, 1)
	_放末日([101])
	_设伤害目标([2])
	检(角色.p_turn_end({"player": 1}) == BattleRole.WAIT, "【审判】应先问是否发动")
	# 发动询问不再自带「是否发动【审判】：…」：说明交给默认的技能说明（技能名已由询问标题显示）
	检(_最近询问文案(9502).is_empty(), "发动询问应留给默认技能说明：%s" % _最近询问文案(9502))
	_应答([1])
	角色.p_turn_end({"player": 1})
	引擎.run()
	检(引擎._await_id == 1 and 引擎._pending_respond_id == 9502,
		"应先问 1 号队友弃牌（等待 %s / 号 %s）" % [str(引擎._await_id), str(引擎._pending_respond_id)])
	# 强制弃牌：询问不能带取消（can_cancel=false），客户端不该出现可点的取消按钮
	var 弃牌询问: Dictionary = {}
	for r: Dictionary in 发送记录:
		if int(r["msg"]) != GConst.Msg.CmdReq:
			continue
		var 命令: Array = (r["data"] as Dictionary).get("commands", [])
		if 命令.is_empty():
			continue
		var c: Dictionary = 命令[0]
		if int(c.get("respond_id", 0)) == 9502 and int(c.get("card_max", 0)) == 1:
			弃牌询问 = c
	检(not 弃牌询问.is_empty() and not bool(弃牌询问.get("can_cancel", true)),
		"审判的队友弃牌是强制的，询问不应可取消：%s" % str(弃牌询问))
	检(_最近询问文案(9502).find("摸 1 张牌") >= 0,
		"队友弃牌询问应写「弃 1 张牌【展示】，摸 1 张牌」：%s" % _最近询问文案(9502))
	_应答([], [], [玩家1.hand_cards[0]])
	引擎.run()
	检(玩家1.hand_cards.size() == 1, "队友弃牌后应先摸 1 张，再问下一名：%d" % 玩家1.hand_cards.size())
	检(引擎._await_id == 3 and 引擎._pending_respond_id == 9502,
		"再问 3 号队友弃牌（等待 %s / 号 %s）" % [str(引擎._await_id), str(引擎._pending_respond_id)])
	_应答([], [], [引擎.p(3).hand_cards[0]])
	引擎.run()
	检(引擎._await_id == 1 and 引擎._pending_respond_id == 9502,
		"两名队友弃完应问交给哪名对手（等待 %s）" % str(引擎._await_id))
	# 给牌目标只能从「本回合被你伤害过的对手」里选（本例只伤害过 2 号）；
	# 条件里的「对目标角色造成伤害」指任意一个，不是让玩家随便点一个对手。
	var 给牌询问: Dictionary = {}
	for r: Dictionary in 发送记录:
		if int(r["msg"]) != GConst.Msg.CmdReq:
			continue
		var 命令2: Array = (r["data"] as Dictionary).get("commands", [])
		if 命令2.is_empty():
			continue
		var c2: Dictionary = 命令2[0]
		if int(c2.get("respond_id", 0)) == 9502 and not (c2.get("dst_ids", []) as Array).is_empty():
			给牌询问 = c2
	检((给牌询问.get("dst_ids", []) as Array) == [2],
		"审判的给牌目标应只有本回合伤害过的 2 号：%s" % str(给牌询问.get("dst_ids", [])))
	# 不合法的目标（自己/队友）应被服务端驳回并重新问，不能随机换目标或静默给牌
	var 驳回前: int = 发送记录.size()
	_应答([1], [1])
	引擎.run()
	var 有驳回: bool = false
	for i: int in range(驳回前, 发送记录.size()):
		var r: Dictionary = 发送记录[i]
		if int(r["msg"]) == GConst.Msg.ErrorInput:
			有驳回 = true
	检(有驳回, "目标选成自己应被驳回（ErrorInput）")
	检(引擎._await_id == 1 and 引擎._pending_respond_id == 9502, "驳回后应重新问这一步")
	# 对手 4 号本回合没被你伤害过，也不能作为给牌目标
	var 驳回前2: int = 发送记录.size()
	_应答([1], [4])
	引擎.run()
	var 有驳回2: bool = false
	for i2: int in range(驳回前2, 发送记录.size()):
		if int(发送记录[i2]["msg"]) == GConst.Msg.ErrorInput:
			有驳回2 = true
	检(有驳回2, "未被你伤害过的对手不应能作为审判给牌目标（ErrorInput）")
	检(引擎._await_id == 1 and 引擎._pending_respond_id == 9502, "驳回后应重新问这一步")
	_应答([1], [2])
	引擎.run()
	检(玩家2.hand_cards.size() == 1, "对手应收到 1 张弃牌：%d" % 玩家2.hand_cards.size())
	检(int(_场卡("末日预言").get("counter", 0)) == 2,
		"其余 1 张弃牌应进【预言】堆：%d" % int(_场卡("末日预言").get("counter", 0)))
	检(_有日志("[异教徒]在[异教徒]的【末日预言】放入 1 张牌"),
		"审判把弃牌放进【预言】堆应写战斗日志")
	# 结算完再重入回合结束钩子：不应再问一遍（不能循环发动）
	检(角色.p_turn_end({"player": 1}) == BattleRole.SUCCESS, "本回合已发动过，不应再问")
	检(引擎._await_id < 0, "不应重新弹【审判】询问")


func _检审判超时() -> void:
	_建引擎()
	_发牌(玩家1, GConst.CardElement.Wind, 1)
	_发牌(引擎.p(3), GConst.CardElement.Fire, 1)
	_放末日([101])
	_设伤害目标([2])
	角色.p_turn_end({"player": 1})
	_应答([1])
	角色.p_turn_end({"player": 1})
	引擎.run()
	检(引擎._await_id == 1 and 引擎._pending_respond_id == 9502, "应先问 1 号队友弃牌")
	# 超时 / 跳过：自动弃掉一张
	_应答超时()
	引擎.run()
	检(玩家1.hand_cards.size() == 1, "超时自动弃 1 张后应立刻摸 1 张：%d" % 玩家1.hand_cards.size())
	检(引擎._await_id == 3 and 引擎._pending_respond_id == 9502, "应继续问 3 号队友")
	_应答([], [], [引擎.p(3).hand_cards[0]])
	引擎.run()
	_应答([1], [2])
	引擎.run()
	检(玩家2.hand_cards.size() == 1, "超时后流程应照常走完，对手收到 1 张弃牌")


# ============================================================
# 11. 状态区显示资料：图标名 / 悬停被动说明
# ============================================================
func _检状态显示资料() -> void:
	检(GConst.场卡显示.has("末日预言"), "状态区应有【末日预言】的图标配置")
	检(not GConst.skill_desc(9504).is_empty(), "悬停提示应能取到【末日预言】的被动说明")
	# 悬停像魔刃一样显示「【被动】技能名：说明」（限宽换行由客户端的提示内容负责）
	var 提示: String = 角色技能提示.单个技能(9504, 16, 95)
	检(提示.find("【被动】") >= 0, "悬停说明应带【被动】类型：%s" % 提示.substr(0, 20))
	检(提示.find("末日预言") >= 0, "悬停说明应写技能名：%s" % 提示.substr(0, 20))
	检(提示.find("[color=") >= 0, "带字号的说明也要有【被动】标色码：%s" % 提示.substr(0, 40))


# ============================================================
# 12. 审判弃掉【魔刃】要触发噬神者【渗蚀】
# ============================================================
func _检审判弃刃触发渗蚀() -> void:
	_建引擎()
	# 3 号座位挂噬神者，拿到他的【魔刃】唯一实例并塞给 1 号（任何持有者弃置都要触发渗蚀）
	var 噬: BattleRole = (load("res://scripts/battle/roles/role_shishenzhe.gd") as GDScript).new()
	噬.setup(引擎.p(3), 引擎)
	引擎.p(3).role = 噬
	引擎.p(3).role_id = 79
	引擎.确保噬神者刃(3)
	var 刃: int = 引擎.p(3).刃实例(GConst.噬神者_魔刃卡)
	检(刃 > 0, "噬神者应生成【魔刃】唯一实例")
	引擎.deck.discard.erase(刃)
	玩家1.add_hand_cards([刃])
	_发牌(引擎.p(3), GConst.CardElement.Wind, 1)
	_设伤害目标([2])
	检(角色.p_turn_end({"player": 1}) == BattleRole.WAIT, "【审判】应先问是否发动")
	_应答([1])
	角色.p_turn_end({"player": 1})
	引擎.run()
	检(引擎._await_id == 1 and 引擎._pending_respond_id == 9502, "应先问 1 号队友弃牌")
	_应答([], [], [刃])
	引擎.run()
	# 渗蚀：3 号噬神者应对弃牌者（1 号）造成法术伤害
	var 有渗蚀: bool = false
	for r: Dictionary in 发送记录:
		if int(r["msg"]) != GConst.Msg.Skill:
			continue
		var 数据: Dictionary = r["data"]
		if int(数据.get("skill_id", 0)) == 7911 and (数据.get("dst_ids", []) as Array).has(1):
			有渗蚀 = true
	检(有渗蚀, "弃置【魔刃】应触发【渗蚀】并对弃牌者造成伤害")
	检(引擎._await_id == 3 and 引擎._pending_respond_id == 9502,
		"渗蚀结算完应继续问 3 号队友（等待 %s）" % str(引擎._await_id))
	var 三号弃牌: int = int(引擎.p(3).hand_cards[0])
	_应答([], [], [三号弃牌])
	引擎.run()
	检(引擎._await_id == 1 and 引擎._pending_respond_id == 9502, "应问选哪张弃牌交给对手")
	# 被移除的刃不应再作为「选 1 张弃牌交给对手」的选项：只剩 3 号队友那张
	var 选项数: int = 0
	for r: Dictionary in 发送记录:
		if int(r["msg"]) != GConst.Msg.CmdReq:
			continue
		var 命令: Array = (r["data"] as Dictionary).get("commands", [])
		if 命令.is_empty():
			continue
		var c: Dictionary = 命令[0]
		if int(c.get("respond_id", 0)) == 9502 and c.has("option_card_ids"):
			选项数 = (c.get("option_card_ids", []) as Array).size()
	检(选项数 == 1, "被移除的【魔刃】不应作为审判的弃牌选项，实际选项数 %d" % 选项数)
	_应答([1], [2])
	引擎.run()
	检(玩家2.有手牌(三号弃牌), "对手应收到玩家交出的那张弃牌")
	检(引擎.移除牌堆.has(刃), "渗蚀后的【魔刃】应收纳在移除牌堆里")
	检(not 引擎.deck.discard.has(刃) and not 玩家1.有手牌(刃),
		"被移除的【魔刃】不应进弃牌堆 / 手牌")
	检(引擎._await_id < 0, "审判结算完不应还停在等待")


# ============================================================
# 13. 审判残留状态：新回合清掉后必须还能正常发动（修「偶尔触发不了」）
# ============================================================
func _检审判残留状态() -> void:
	_建引擎()
	_发牌(玩家1, GConst.CardElement.Wind, 1)
	角色._审判步 = 3
	var 残留弃牌: Array[int] = [int(玩家1.hand_cards[0])]
	角色._审判弃牌 = 残留弃牌
	角色.p_before_turn_begin({"player": 1})
	检(int(角色.get("_审判步")) == 0 and (角色.get("_审判弃牌") as Array).is_empty(),
		"新回合开始应清掉残留的审判流程状态")
	_设伤害目标([2])
	检(角色.p_turn_end({"player": 1}) == BattleRole.WAIT, "清掉残留后【审判】应能正常发动")


# ============================================================
# 14. 选项目标：客户端显示的第 N 项必须对应服务器列表的第 N 项
# ============================================================
func _检审判选项值对应() -> void:
	_建引擎()
	_发牌(玩家1, GConst.CardElement.Wind, 2)
	var 甲: int = int(玩家1.hand_cards[0])
	var 乙: int = int(玩家1.hand_cards[1])
	玩家1.取出实例(玩家1.hand_cards, 甲)
	玩家1.取出实例(玩家1.hand_cards, 乙)
	引擎.deck.push_discard([甲, 乙])
	# 给牌目标白名单：本回合伤害过 2 号，才能把弃牌交给 2 号
	_设伤害目标([2])
	角色._审判步 = 3
	var 候选弃牌: Array[int] = [甲, 乙]
	角色._审判弃牌 = 候选弃牌
	引擎.push(BattleEngine.SHook.new("p_yi_jiao_tu_ask", {"player": 1}, []))
	引擎.run()
	检(引擎._await_id == 1 and 引擎._pending_respond_id == 9502, "应先问选 1 张弃牌交给对手")
	# 越界的选项值（客户端旧列表 / 乱传）：驳回重问，不能交牌
	_应答([3], [2])
	引擎.run()
	检(not 玩家2.有手牌(甲) and not 玩家2.有手牌(乙), "越界选项值不应交出任何牌")
	检(引擎._await_id == 1 and 引擎._pending_respond_id == 9502, "越界选项值应被驳回并重问")
	# 客户端显示的第 2 项 → args[0] = 服务器该项的 value(2) → 交给对手的应是列表第 2 张（乙）
	_应答([2], [2])
	引擎.run()
	检(玩家2.有手牌(乙) and not 玩家2.有手牌(甲),
		"选项值 2 应对应服务器选项列表的第 2 项，实际手牌=%s" % str(玩家2.hand_cards))


# ============================================================
# 15. 审判：队友摸 1 张后必须先结算手牌超限，再问下一名队友
# ============================================================
func _检审判摸牌先结算超限() -> void:
	_建引擎()
	for i: int in range(GConst.HAND_CARDS_MAX):
		_发牌(玩家1, GConst.CardElement.Wind, 1)
	角色._审判步 = 2
	角色._审判下标 = 1
	角色._审判待摸 = 1
	引擎.push(BattleEngine.SHook.new("p_yi_jiao_tu_ask", {"player": 1}, []))
	引擎.run()
	检(引擎._await_id == 1, "摸牌超过上限时应先问超出上限的人弃牌（等待 %s）" % str(引擎._await_id))
	检(引擎._pending_respond_id != 9502, "不应跳过超限结算、直接问下一名队友弃牌")


# ============================================================
# 16. 审判：选牌给对手时，选中敌方头像要写「给予【卡名】」
# ============================================================
func _检审判头像提示() -> void:
	var 甲: GCard = Data.get_card(3)
	var 乙: GCard = Data.get_card(4)
	检(甲 != null and 乙 != null, "测试用卡面 3 / 4 应存在")
	var 窗: Control = load("res://scripts/ui/battle_mobile.gd").new()
	窗._mode = 3
	窗._skill_ask_id = GConst.技能_审判
	窗._二级选项 = [{"参数": [1], "卡牌": 3}, {"参数": [2], "卡牌": 4}]
	窗._已选参数 = [2]
	窗._sel_players.append(2)
	var 提示: Dictionary = 窗.call("_审判头像提示")
	检(str(提示.get(2, "")) == "给予【%s】" % (乙.card_name if 乙 != null else "?"),
		"审判选中第 2 项时目标头像应写「给予【第 2 张牌名】」：%s" % str(提示))
	窗._已选参数 = [1]
	提示 = 窗.call("_审判头像提示")
	检(str(提示.get(2, "")) == "给予【%s】" % (甲.card_name if 甲 != null else "?"),
		"改选第 1 项后头像提示应跟着换成第 1 张牌名：%s" % str(提示))
	窗._已选参数 = []
	检(窗.call("_审判头像提示").is_empty(), "没选牌时不应写提示")
	# 实例号 0 的牌（卡表#0 圣盾）也要能写提示（选项 card_id 走 -1＝没有牌、0＝合法牌）
	窗._二级选项 = [{"参数": [1], "卡牌": 0}]
	窗._已选参数 = [1]
	窗._sel_players.append(2)
	var 圣盾卡: GCard = Data.get_card(0)
	检(圣盾卡 != null and str(窗.call("_审判头像提示").get(2, "")) == "给予【%s】" % 圣盾卡.card_name,
		"实例号 0 的牌也应写「给予【卡名】」：%s" % str(窗.call("_审判头像提示")))
	窗._sel_players.clear()
	窗._已选参数 = [1]
	检(窗.call("_审判头像提示").is_empty(), "没选目标时不应写提示")
	窗.queue_free()


# ============================================================
# 17. 审判：两张同名不同实例的牌（其中一张实例号是 0）都要进选项
# ============================================================
func _检审判同名牌两张() -> void:
	_建引擎()
	# 卡表#0 圣盾（地/幻）实例号正好是 0；卡表#6 圣盾（风/圣）是另一张同名牌
	玩家1.add_hand_cards([0])
	引擎.p(3).add_hand_cards([6])
	_设伤害目标([2])
	_应答([1])
	角色.p_turn_end({"player": 1})
	引擎.run()
	_应答([], [], [0])
	引擎.run()
	_应答([], [], [6])
	引擎.run()
	var 选牌询问: Dictionary = {}
	for r: Dictionary in 发送记录:
		if int(r["msg"]) != GConst.Msg.CmdReq:
			continue
		var 表: Array = (r["data"] as Dictionary).get("commands", [])
		if 表.is_empty():
			continue
		var c: Dictionary = 表[0]
		if int(c.get("respond_id", 0)) == 9502 and c.has("option_card_ids"):
			选牌询问 = c
	检(not 选牌询问.is_empty(), "应进入「选 1 张弃牌交给对手」")
	var 卡面: Array = 选牌询问.get("option_card_ids", [])
	检(卡面 == [0, 6], "两张同名牌（含实例号 0 的圣盾）都应作为选项，实际 %s" % str(卡面))
	检(int((选牌询问.get("args", []) as Array)[3] if (选牌询问.get("args", []) as Array).size() > 3 else 0) == 2,
		"选项数量应为 2，实际 %s" % str(选牌询问.get("args", [])))
	# 选中实例号 0 的那张：也要能按实例取出来交给对手
	_应答([1], [2])
	引擎.run()
	检(引擎.p(2).有手牌(0), "选中实例号 0 的圣盾应能交给对手，对手手牌=%s" % str(引擎.p(2).hand_cards))


# ============================================================
# 18. 放逐：选中正面选项时提示条保持本次询问文案（不切换成选项被动说明）
# ============================================================
func _检放逐提示不切换() -> void:
	var 窗: Control = load("res://scripts/ui/battle_mobile.gd").new()
	窗._mode = 3
	窗._skill_ask_id = 9505
	窗._二级栏父技能号 = 9505
	窗._pending = {"ask_prompt": "【放逐】：选择放 1 张【末日预言】入场，并选择 6 张手牌作为【预言】"}
	var 带标记: Dictionary = {"参数": [1], "技能号": 9507, "不改提示": true}
	var 不带标记: Dictionary = {"参数": [2], "技能号": 9508}
	var 保持: String = str(窗.call("_选项保持提示", 带标记))
	检(保持.contains("选择 6 张手牌作为【预言】"),
		"带「不改提示」的正面选项应保持本次询问文案（ask_prompt）：%s" % 保持)
	检(str(窗.call("_选项保持提示", 不带标记)).is_empty(),
		"没有标记的选项不应走保持逻辑")
	# 二级栏归一化不能再把选项开关漏抄（以前白名单抄字段，不改提示到这里就丢了）
	var 归: Dictionary = 窗.call("_归一化二级选项", {"参数": [1], "技能号": 9507,
		"不改提示": true, "自定义键": 3})
	检(bool(归.get("不改提示", false)), "归一化后应保留「不改提示」标记：%s" % str(归))
	检(int(归.get("自定义键", 0)) == 3, "归一化后应原样保留其余键：%s" % str(归))
	var 归保持: String = str(窗.call("_选项保持提示", 归))
	检(归保持.contains("选择 6 张手牌作为【预言】"),
		"归一化后的选项也应走保持逻辑：%s" % 归保持)
	窗.queue_free()


# ============================================================
# 15b. 审判：0 号座位弃牌后也要摸 1 张（座位从 0 开始，不能用 > 0 判空）
# ============================================================
func _检审判零号座位摸牌() -> void:
	引擎 = BattleEngine.new()
	发送记录.clear()
	引擎.send_cb = func(pid: int, msg: int, data: Dictionary) -> void:
		发送记录.append({"pid": pid, "msg": msg, "data": data})
	引擎.add_player(0, GConst.BLUE, "零")
	引擎.add_player(1, GConst.RED, "一")
	引擎.add_player(2, GConst.BLUE, "二")
	引擎.add_player(3, GConst.RED, "三")
	引擎.start_with_roles({})
	for pid: int in 引擎.order:
		var p0: BattlePlayer = 引擎.p(pid)
		p0.role = null
		p0.hand_cards.clear()
		p0.cross_num = 0
	角色 = (load(角色路径) as GDScript).new()
	角色.setup(引擎.p(0), 引擎)
	引擎.p(0).role = 角色
	引擎.p(0).role_id = 95
	引擎._states.clear()
	引擎._清空等待()
	引擎.phase = BattleEngine.Phase.Playing
	引擎.current_id = 0
	引擎.round_id = 1
	_发牌(引擎.p(0), GConst.CardElement.Wind, 1)
	_发牌(引擎.p(2), GConst.CardElement.Fire, 1)
	_设伤害目标([1])
	检(角色.p_turn_end({"player": 0}) == BattleRole.WAIT, "【审判】应先问是否发动")
	_应答([1])
	角色.p_turn_end({"player": 0})
	引擎.run()
	检(引擎._await_id == 0 and 引擎._pending_respond_id == 9502,
		"应先问 0 号队友弃牌（等待 %s）" % str(引擎._await_id))
	_应答([], [], [引擎.p(0).hand_cards[0]])
	引擎.run()
	检(引擎.p(0).hand_cards.size() == 1,
		"0 号座位弃牌后应摸 1 张（不能被 > 0 哨兵吞掉），实际手牌=%d" % 引擎.p(0).hand_cards.size())


# ============================================================
# 15c. 展示流程：对手是 0 号座位时也要结算本项伤害
# ============================================================
func _检展示零号座位伤害() -> void:
	_建引擎()
	角色._展示步 = 9
	角色._展示对手 = 0
	角色._展示X = 1
	检(角色._展示本项伤害() == BattleRole.URGENT,
		"展示对手为 0 号座位时也应压入伤害（不能被 > 0 哨兵吞掉）")
	角色._展示对手 = -1


# ============================================================
# 14b. 审判：其余弃牌放进【预言】堆时不能超过 6 张
# ============================================================
func _检审判预言不超上限() -> void:
	_建引擎()
	var 三张: Array = _发牌(玩家1, GConst.CardElement.Wind, 3)
	# 模拟「队友已经弃牌」：三张都在弃牌堆里
	for c: Variant in 三张:
		玩家1.取出实例(玩家1.hand_cards, int(c))
	引擎.deck.push_discard(三张)
	# 预言堆已有 5 张，只剩 1 个空位
	_放末日([101, 102, 103, 104, 105])
	var 审判弃牌: Array[int] = []
	for c: Variant in 三张:
		审判弃牌.append(int(c))
	角色._审判弃牌 = 审判弃牌
	角色._审判给 = 0
	角色._审判对手 = 2
	角色._审判步 = 4
	引擎.push(BattleEngine.SHook.new("p_yi_jiao_tu_ask", {"player": 1}, []))
	引擎.run()
	var 场: Dictionary = _场卡("末日预言")
	检(int(场.get("counter", 0)) == 6,
		"预言堆不能超过 6 张：%d" % int(场.get("counter", 0)))
	var 给对手: int = 0
	var 进堆: int = 0
	var 还在弃牌: int = 0
	for c2: Variant in 三张:
		var cid: int = int(c2)
		if 玩家2.有手牌(cid):
			给对手 += 1
		elif (场.get("pile", []) as Array).has(cid):
			进堆 += 1
		elif 引擎.deck.discard.has(cid):
			还在弃牌 += 1
	检(给对手 == 1 and 进堆 == 1 and 还在弃牌 == 1,
		"应 1 张给对手、1 张进堆、1 张留在弃牌堆，实际 %d/%d/%d" % [给对手, 进堆, 还在弃牌])
