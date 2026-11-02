extends 自检用例
## F2 额外行动与行动计数：
## - 每回合「攻击 / 法术 / 特殊 / 额外」行动计数：普通行动、额外行动都记，回合开始清零；
## - 行动结束通用钩子 p_action_end（与 p_after_* 同一份上下文，带本回合第几次行动 / 是否额外）；
## - 额外行动的目标 / 出牌限制：写在行动自带的规格里（add_action 的 spec），引擎照单执行：
##   下发给客户端做白名单，服务端攻击 / 法术 / 技能行动落子时兜底校验；
## - 边界：「启动」技能不是行动（不计、不触发 p_action_end）；被取消的技能行动撤销计数。

## dummy 角色：记录 p_action_end，按需授予额外攻击行动、声明额外行动的牌 / 目标限制
class 计数角色:
	extends BattleRole

	## 本份额外攻击行动的来源（模拟 4501 / 101 授予的那一份）
	const 额外攻击来源: int = 9001
	## 技能行动用例：攻击技能 / 启动技能 / 会被取消的特殊技能
	const 攻击技能号: int = 9002
	const 启动技能号: int = 9003
	const 取消技能号: int = 9004

	## p_action_end 收到的上下文（按先后顺序）
	var 行动结束记录: Array = []
	## 第一次普通攻击行动结束时授予一次额外攻击行动
	var 授予额外攻击: bool = false
	## 本份额外攻击行动的出牌 / 目标限制（空＝不限制；写进行动规格，不再按 cause 回问角色）
	var 额外攻击牌: Array = []
	var 额外攻击目标: Array = []

	func p_action_end(ctx: Dictionary) -> int:
		if int(ctx.get("player", -1)) != player.id:
			return SUCCESS
		行动结束记录.append(ctx.duplicate())
		if 授予额外攻击 and not bool(ctx.get("is_extra", false)) \
				and str(ctx.get("kind", "")) == "attack" and int(ctx.get("action_id", 0)) == 0:
			授予额外攻击 = false
			player.add_action(GConst.ActionType.Attack, 额外攻击来源, false, false, {
				"cards": 额外攻击牌, "targets": 额外攻击目标,
			})
		return SUCCESS

	func v_attack_skill(action: Dictionary) -> int:
		if int(action.get("action_id", 0)) == 攻击技能号:
			return GConst.GE_SUCCESS
		return GConst.GE_EMPTY_HANDLE

	func p_attack_skill(_action: Dictionary) -> int:
		return SUCCESS

	func is_free_skill(skill_id: int) -> bool:
		return skill_id == 启动技能号

	func v_special_skill(action: Dictionary) -> int:
		var aid: int = int(action.get("action_id", 0))
		if aid == 启动技能号 or aid == 取消技能号:
			return GConst.GE_SUCCESS
		return GConst.GE_EMPTY_HANDLE

	func p_special_skill(action: Dictionary) -> int:
		# 模拟角色在技能询问里点「取消」：这次技能行动没发生，引擎应撤销 F2 计数
		if int(action.get("action_id", 0)) == 取消技能号:
			engine.取消技能行动()
		return SUCCESS


var 引擎: BattleEngine = null
var 玩家1: BattlePlayer = null
var 角色: 计数角色 = null
## send_cb 记录：{pid, msg, data}
var 发送记录: Array = []
var 攻击牌甲: GCard = null
var 攻击牌乙: GCard = null
var 圣盾牌: GCard = null


func _init() -> void:
	名称 = "额外行动与行动计数"


## 卡库里第一张非暗系攻击牌（暗系攻击无法应战，这里要能走到应战询问）
func _取攻击牌(排除: int = -1) -> GCard:
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual or not c.is_attack():
			continue
		if c.element_enum() == GConst.CardElement.Darkness:
			continue
		if c.id == 排除:
			continue
		return c
	return null


## 卡库里第一张指定卡名的牌
func _取卡名(卡名: int) -> GCard:
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.card_name_enum() == 卡名:
			return c
	return null


## 是否给某玩家发过「操作无效」错误
func _有错误输入(pid: int) -> bool:
	for r: Dictionary in 发送记录:
		if int(r["pid"]) == pid and int(r["msg"]) == GConst.Msg.ErrorInput:
			return true
	return false


## 清空战斗状态：回到「轮到玩家 1、行动阶段、无手牌」的同一起点
func _重置战斗() -> void:
	引擎._states.clear()
	引擎._清空等待()
	引擎._最后询问.clear()
	引擎._最后行动命令.clear()
	引擎.phase = BattleEngine.Phase.Playing
	引擎.current_id = 1
	引擎.行动允许 = GConst.ActionType.Any
	引擎.行动可放弃 = false
	引擎.行动额外 = false
	引擎.行动额外来源 = 0
	引擎.行动禁特殊 = false
	引擎.skip_action_phase = false
	引擎.测试跳过回合 = -1
	引擎.首选额外行动 = -1
	引擎.首选额外行动卡 = 0
	引擎.首选额外行动目标 = 0
	引擎._基础效果额外行动已确认.clear()
	引擎.当前额外行动数据 = {}
	玩家1.跳过额外攻击行动 = false
	发送记录.clear()
	for pid: int in 引擎.order:
		var p0: BattlePlayer = 引擎.p(pid)
		p0.hand_cards.clear()
		p0.cover_cards.clear()
		p0.basic_effects.clear()
		p0.cross_num = 0
		p0.additional_actions.clear()
		p0.boot_skill_used = false
		p0.reset_action_counts()
	角色.行动结束记录.clear()
	角色.授予额外攻击 = false
	角色.额外攻击牌 = []
	角色.额外攻击目标 = []


## 模拟「已经进入某份额外攻击行动」：行动按规格入队再被取走，引擎字段与这份数据一致
func _挂额外行动(牌表: Array, 目标表: Array) -> void:
	玩家1.additional_actions.clear()
	玩家1.add_action(GConst.ActionType.Attack, 计数角色.额外攻击来源, false, false, {
		"cards": 牌表, "targets": 目标表,
	})
	引擎.当前额外行动数据 = 玩家1.额外行动数据(计数角色.额外攻击来源)
	玩家1.撤回额外行动(计数角色.额外攻击来源)
	引擎.行动允许 = GConst.ActionType.Attack
	引擎.行动可放弃 = true
	引擎.行动额外 = true
	引擎.行动额外来源 = 计数角色.额外攻击来源


## 最近一条行动结束记录（没有则空字典）
func _最后记录() -> Dictionary:
	return 角色.行动结束记录[-1] if not 角色.行动结束记录.is_empty() else {}


## 额外行动队列里的来源（按队列顺序）
func _额外原因(p: BattlePlayer) -> Array:
	var 出: Array = []
	for a: Dictionary in p.additional_actions:
		出.append(int(a.get("cause", 0)))
	return 出


## 队列里的获取序号是否严格递增（数组顺序＝获取顺序）
func _额外序号递增(p: BattlePlayer) -> bool:
	var 上: int = 0
	for a: Dictionary in p.additional_actions:
		if int(a.get("order", 0)) <= 上:
			return false
		上 = int(a.get("order", 0))
	return true


func 跑() -> void:
	await 等帧(1)
	攻击牌甲 = _取攻击牌()
	if 攻击牌甲 != null:
		攻击牌乙 = _取攻击牌(攻击牌甲.id)
	圣盾牌 = _取卡名(GConst.CardName.Shield)
	检(攻击牌甲 != null and 攻击牌乙 != null, "卡库里找不到两张非暗系攻击牌")
	检(圣盾牌 != null, "卡库里找不到【圣盾】")
	if 攻击牌甲 == null or 攻击牌乙 == null or 圣盾牌 == null:
		return

	# 4 人交替座次：1 / 2 蓝，3 / 4 红；dummy 计数角色挂在玩家 1 身上
	引擎 = BattleEngine.new()
	引擎.send_cb = func(pid: int, msg: int, data: Dictionary) -> void:
		发送记录.append({"pid": pid, "msg": msg, "data": data})
	引擎.add_player(1, GConst.BLUE, "计数者")
	引擎.add_player(2, GConst.BLUE, "队友")
	引擎.add_player(3, GConst.RED, "对手甲")
	引擎.add_player(4, GConst.RED, "对手乙")
	引擎.start_with_roles({})
	玩家1 = 引擎.p(1)
	角色 = 计数角色.new()
	角色.setup(玩家1, 引擎)
	玩家1.role = 角色

	# ---- 场景 1：普通攻击计 1 次 → 行动结束钩子授予额外攻击 → 额外攻击计第 2 次 ----
	_重置战斗()
	角色.授予额外攻击 = true
	角色.额外攻击牌 = [攻击牌甲.id]
	角色.额外攻击目标 = [3]
	玩家1.hand_cards.append(攻击牌甲.id)
	引擎.resolve_action(GConst.ActionType.Attack, {"card_ids": [攻击牌甲.id], "dst_ids": [3], "args": []})
	引擎.run()
	检(引擎._await_id == 3, "攻击宣告后应等对手应战（等待 %s）" % str(引擎._await_id))
	引擎.on_message(3, GConst.Msg.Respond, {
		"respond_id": GConst.RespondType.ReplyAttack, "src_id": 3,
		"args": [GConst.Reattack.GiveUp], "card_ids": [], "dst_ids": [],
	})
	检(玩家1.action_count() == 1, "第一次普通攻击后本回合行动数应为 1，实际 %d" % 玩家1.action_count())
	检(玩家1.attack_action_count == 1 and 玩家1.extra_action_count == 0,
		"普通攻击应只记攻击、不记额外：攻击 %d / 额外 %d" % [玩家1.attack_action_count, 玩家1.extra_action_count])
	var 首次: Dictionary = _最后记录()
	检(not 首次.is_empty(), "普通行动结束没有触发通用钩子 p_action_end")
	检(str(首次.get("kind", "")) == "attack", "普通攻击的行动结束 kind 应为 attack：%s" % str(首次))
	检(not bool(首次.get("is_extra", true)) and int(首次.get("extra_cause", -1)) == 0,
		"普通攻击不应被标成额外行动：%s" % str(首次))
	检(int(首次.get("action_count", 0)) == 1 and int(首次.get("attack_action_count", 0)) == 1,
		"行动结束钩子的计数不对：%s" % str(首次))
	检(not bool(首次.get("is_skill", false)), "普通出牌不应被标成技能行动")
	# p_action_end 里授予的那份额外攻击行动现在应问是否进入
	检(引擎._await_id == 1, "攻击结束后应询问玩家 1 是否进入额外攻击行动（等待 %s）" % str(引擎._await_id))
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": GConst.RespondType.AdditionalAction, "src_id": 1,
		"args": [计数角色.额外攻击来源], "card_ids": [], "dst_ids": [],
	})
	检(引擎._await_id == 1 and 引擎.行动额外 and 引擎.行动额外来源 == 计数角色.额外攻击来源,
		"进入额外攻击行动后应处于额外行动阶段（额外 %s / 来源 %s）" % [str(引擎.行动额外), str(引擎.行动额外来源)])
	# 额外行动的目标 / 出牌限制随行动命令下发（客户端据此置灰）
	var 额外命令表: Array = 引擎._最后询问.get(1, {}).get("commands", [])
	var 额外命令: Dictionary = 额外命令表[0] if not 额外命令表.is_empty() else {}
	检((额外命令.get("card_ids", []) as Array) == [攻击牌甲.id],
		"额外行动的出牌白名单没有随行动命令下发：%s" % str(额外命令.get("card_ids", [])))
	检((额外命令.get("dst_ids", []) as Array) == [3],
		"额外行动的目标白名单没有随行动命令下发：%s" % str(额外命令.get("dst_ids", [])))
	# 规格就是唯一来源：改这份行动自己的规格，下发内容跟着变（引擎不再问角色）
	玩家1.改写额外行动(计数角色.额外攻击来源, {"cards": [攻击牌乙.id], "targets": [4]})
	var 改后命令表: Array = 引擎.action_commands(1, GConst.ActionType.Attack, true, true, false,
		计数角色.额外攻击来源)
	var 改后命令: Dictionary = 改后命令表[0] if not 改后命令表.is_empty() else {}
	检((改后命令.get("card_ids", []) as Array) == [攻击牌乙.id],
		"额外行动的牌白名单应来自行动规格：%s" % str(改后命令.get("card_ids", [])))
	检((改后命令.get("dst_ids", []) as Array) == [4],
		"额外行动的目标白名单应来自行动规格：%s" % str(改后命令.get("dst_ids", [])))
	玩家1.改写额外行动(计数角色.额外攻击来源, {"cards": [攻击牌甲.id], "targets": [3]})
	# 额外攻击用白名单里的牌打被允许的目标
	玩家1.hand_cards.append(攻击牌甲.id)
	# 先给下家预置一份计数：回合开始（SCheckTurnStart）必须清零它
	引擎.p(2).attack_action_count = 5
	引擎.p(2).extra_action_count = 2
	引擎.resolve_action(GConst.ActionType.Attack, {"card_ids": [攻击牌甲.id], "dst_ids": [3], "args": []})
	引擎.run()
	检(引擎._await_id == 3, "额外攻击宣告后应等对手应战（等待 %s）" % str(引擎._await_id))
	引擎.on_message(3, GConst.Msg.Respond, {
		"respond_id": GConst.RespondType.ReplyAttack, "src_id": 3,
		"args": [GConst.Reattack.GiveUp], "card_ids": [], "dst_ids": [],
	})
	检(玩家1.action_count() == 2 and 玩家1.attack_action_count == 2 and 玩家1.extra_action_count == 1,
		"额外攻击应记成第 2 次攻击行动 / 其中 1 次额外：总 %d 攻击 %d 额外 %d" % [
			玩家1.action_count(), 玩家1.attack_action_count, 玩家1.extra_action_count])
	var 再次: Dictionary = _最后记录()
	检(str(再次.get("kind", "")) == "attack" and bool(再次.get("is_extra", false)),
		"额外攻击的行动结束钩子应标成额外攻击：%s" % str(再次))
	检(int(再次.get("extra_cause", 0)) == 计数角色.额外攻击来源,
		"行动结束钩子的额外来源不对：%s" % str(再次))
	检(int(再次.get("action_count", 0)) == 2 and int(再次.get("extra_action_count", 0)) == 1,
		"第 2 次行动结束的计数不对：%s" % str(再次))
	# 回合已交给玩家 2：回合开始（SCheckTurnStart）把行动计数清零
	检(引擎.current_id == 2, "额外行动结束后应轮到下家，实际 %d" % 引擎.current_id)
	检(玩家1.action_count() == 2, "非自己回合不应清掉玩家 1 本回合计数")
	检(引擎.行动计数(2).get("action_count", -1) == 0,
		"新回合开始没有清零下家的行动计数：%s" % str(引擎.行动计数(2)))

	# ---- 场景 2：非法额外行动被服务端驳回（出牌 / 目标限制）----
	_重置战斗()
	_挂额外行动([攻击牌甲.id], [3])
	# 2a：白名单外的牌
	玩家1.hand_cards.append(攻击牌乙.id)
	引擎.resolve_action(GConst.ActionType.Attack, {"card_ids": [攻击牌乙.id], "dst_ids": [3], "args": []})
	引擎.run()
	检(_有错误输入(1), "额外行动用了白名单外的牌应被驳回")
	检(玩家1.hand_cards.has(攻击牌乙.id), "被驳回的额外攻击不应把牌打出去")
	检(玩家1.action_count() == 0 and 玩家1.extra_action_count == 0,
		"被驳回的行动不应计入 F2 行动计数：%s" % str(引擎.行动计数(1)))
	检(角色.行动结束记录.is_empty(), "被驳回的行动不应触发 p_action_end")
	# 2b：目标不在允许范围
	_重置战斗()
	_挂额外行动([攻击牌甲.id], [3])
	玩家1.hand_cards.append(攻击牌甲.id)
	引擎.resolve_action(GConst.ActionType.Attack, {"card_ids": [攻击牌甲.id], "dst_ids": [4], "args": []})
	引擎.run()
	检(_有错误输入(1), "额外行动攻击了受限目标应被驳回")
	检(玩家1.hand_cards.has(攻击牌甲.id), "被驳回的额外攻击不应把牌打出去")
	检(玩家1.action_count() == 0, "目标被驳回时不应计入行动计数")
	# 2c：合法牌 + 合法目标通过并记一次额外行动
	_重置战斗()
	_挂额外行动([攻击牌甲.id], [3])
	玩家1.hand_cards.append(攻击牌甲.id)
	引擎.resolve_action(GConst.ActionType.Attack, {"card_ids": [攻击牌甲.id], "dst_ids": [3], "args": []})
	检(not _有错误输入(1), "合法牌 + 合法目标的额外攻击不应被驳回")
	检(玩家1.action_count() == 1 and 玩家1.extra_action_count == 1,
		"合法的额外攻击应记 1 次行动 / 1 次额外：%s" % str(引擎.行动计数(1)))
	引擎.run()

	# ---- 场景 3：法术行动计数 ----
	_重置战斗()
	玩家1.hand_cards.append(圣盾牌.id)
	引擎.resolve_action(GConst.ActionType.Magic, {"card_ids": [圣盾牌.id], "dst_ids": [1], "args": []})
	引擎.run()
	检(玩家1.magic_action_count == 1 and 玩家1.action_count() == 1,
		"法术行动应记 1 次法术 / 1 次行动：%s" % str(引擎.行动计数(1)))
	var 法术记录: Dictionary = _最后记录()
	检(str(法术记录.get("kind", "")) == "magic" and int(法术记录.get("action_count", 0)) == 1,
		"法术行动结束钩子不对：%s" % str(法术记录))
	检(not bool(法术记录.get("is_skill", false)), "直接打法术牌不应标成技能行动")

	# ---- 场景 4：特殊行动计数 ----
	_重置战斗()
	引擎.resolve_action(GConst.ActionType.Special,
		{"action_id": GConst.SpecialAction.Buy, "args": [0, 0], "card_ids": [], "dst_ids": []})
	引擎.run()
	检(玩家1.special_action_count == 1 and 玩家1.action_count() == 1,
		"特殊行动应记 1 次特殊 / 1 次行动：%s" % str(引擎.行动计数(1)))
	var 特殊记录: Dictionary = _最后记录()
	检(str(特殊记录.get("kind", "")) == "special" and bool(特殊记录.get("special_action", false)),
		"特殊行动结束钩子不对：%s" % str(特殊记录))

	# ---- 场景 5：技能攻击算一次攻击行动（is_skill 标出来）----
	_重置战斗()
	引擎.resolve_action(GConst.ActionType.AttackSkill,
		{"action_id": 计数角色.攻击技能号, "card_ids": [], "dst_ids": [], "args": []})
	引擎.run()
	检(玩家1.attack_action_count == 1 and 玩家1.action_count() == 1,
		"技能攻击应记 1 次攻击行动：%s" % str(引擎.行动计数(1)))
	var 技能记录: Dictionary = _最后记录()
	检(str(技能记录.get("kind", "")) == "attack" and bool(技能记录.get("is_skill", false)),
		"技能攻击的 kind 应为 attack 且 is_skill=true：%s" % str(技能记录))
	检(int(技能记录.get("action_id", 0)) == 计数角色.攻击技能号,
		"技能行动结束钩子应带技能号：%s" % str(技能记录))

	# ---- 场景 6：「启动」技能不是行动：不计、不触发 p_action_end、行动阶段继续 ----
	_重置战斗()
	引擎.resolve_action(GConst.ActionType.SpecialSkill,
		{"action_id": 计数角色.启动技能号, "args": [], "card_ids": [], "dst_ids": []})
	引擎.run()
	检(玩家1.action_count() == 0 and 玩家1.special_action_count == 0,
		"「启动」技能不应计入 F2 行动计数：%s" % str(引擎.行动计数(1)))
	检(角色.行动结束记录.is_empty(), "「启动」技能不应触发通用 p_action_end")
	检(引擎.current_id == 1 and 引擎._await_id == 1,
		"「启动」技能结算完应继续让玩家 1 行动（当前 %d / 等待 %s）" % [引擎.current_id, str(引擎._await_id)])

	# ---- 场景 7：被取消的技能行动撤销计数、不触发 p_action_end、退回行动阶段 ----
	_重置战斗()
	引擎.resolve_action(GConst.ActionType.SpecialSkill,
		{"action_id": 计数角色.取消技能号, "args": [], "card_ids": [], "dst_ids": []})
	引擎.run()
	检(玩家1.action_count() == 0 and 玩家1.special_action_count == 0,
		"被取消的技能行动应撤销计数：%s" % str(引擎.行动计数(1)))
	检(角色.行动结束记录.is_empty(), "被取消的技能行动不应触发通用 p_action_end")
	# ---- 场景 8：额外攻击阶段可在「无选中代价」的额外攻击之间切换 ----
	_重置战斗()
	var 当前额外: int = 计数角色.额外攻击来源
	var 另一额外: int = GConst.技能_剑影断念
	玩家1.add_action(GConst.ActionType.Attack, 另一额外, true)
	var 排序阶段: BattleEngine.SActionPhase = BattleEngine.SActionPhase.new(
		GConst.ActionType.Attack, true, true, false, 当前额外)
	排序阶段.额外数据 = {
		"allow_action": GConst.ActionType.Attack, "cause": 当前额外,
		"direct": true, "skip_notice": true,
		"uid": 玩家1.额外行动新ID(), "order": 玩家1.额外行动新序号(),
	}
	引擎.push(排序阶段)
	引擎.run()
	检(引擎.行动额外 and 引擎.行动额外来源 == 当前额外,
		"应进入当前额外攻击阶段（额外 %s / 来源 %s）" % [str(引擎.行动额外), str(引擎.行动额外来源)])
	var 切换命令表: Array = 引擎._最后询问.get(1, {}).get("commands", [])
	var 有切换: bool = false
	for c: Dictionary in 切换命令表:
		var 切参: Array = c.get("args", [])
		if int(c.get("respond_id", 0)) == GConst.ActionType.ChooseExtraAction \
				and int(c.get("extra_cause", 0)) == 另一额外 and int(c.get("extra_uid", 0)) > 0 \
				and 切参 == [int(c.get("extra_uid", 0))]:
			有切换 = true
			break
	检(有切换, "额外攻击阶段的技能栏没有下发另一份额外攻击的切换按钮：%s" % str(切换命令表))
	引擎.on_message(1, GConst.Msg.Action, {
		"action_type": GConst.ActionType.ChooseExtraAction, "src_id": 1,
		"args": [另一额外], "card_ids": [], "dst_ids": [],
	})
	检(引擎.行动额外来源 == 另一额外,
		"切换后当前额外行动来源应变成 %d，实际 %d" % [另一额外, 引擎.行动额外来源])
	var 退回: bool = false
	for a: Dictionary in 玩家1.additional_actions:
		if int(a.get("cause", 0)) == 当前额外:
			退回 = true
			break
	检(退回, "切换后原来那份额外行动应退回队列：%s" % str(玩家1.additional_actions))
	检(引擎._await_id == 1 and 引擎._await_kind == GConst.Msg.Action,
		"切换后应重新等玩家 1 选择攻击牌（等待 %s / %s）" % [str(引擎._await_id), str(引擎._await_kind)])
	引擎._states.clear()
	引擎._清空等待()

	# ---- 场景 9：响应里已经点好手牌 + 目标，进入额外行动后直接发起攻击 ----
	_重置战斗()
	var 自动来源: int = 计数角色.额外攻击来源
	角色.额外攻击牌 = [攻击牌甲.id]
	角色.额外攻击目标 = [3]
	玩家1.hand_cards.append(攻击牌甲.id)
	玩家1.add_action(GConst.ActionType.Attack, 自动来源, true, true)
	引擎.首选额外行动 = 自动来源
	引擎.首选额外行动卡 = 攻击牌甲.id
	引擎.首选额外行动目标 = 3
	引擎.push(BattleEngine.SAdditionalAction.new())
	引擎.run()
	检(引擎.行动额外来源 == 自动来源,
		"自动进入的额外行动来源不对：%d" % 引擎.行动额外来源)
	检(引擎._await_id == 3 and 引擎._await_kind == GConst.Msg.Respond,
		"点好手牌 + 目标后应直接进入攻击应战询问（等待 %s / %s）" % [str(引擎._await_id), str(引擎._await_kind)])

	# ---- 场景 10：风怒追击授予的额外攻击行动自带「只能出风系攻击牌」的白名单 ----
	_重置战斗()
	var 剑圣类 = preload("res://scripts/battle/roles/role_jiansheng.gd")
	var 剑圣: BattleRole = 剑圣类.new()
	剑圣.setup(玩家1, 引擎)
	玩家1.role = 剑圣
	var 风击: GCard = null
	var 非风击: GCard = null
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual or not c.is_attack():
			continue
		if c.element_enum() == GConst.CardElement.Wind and 风击 == null:
			风击 = c
		elif c.element_enum() != GConst.CardElement.Wind and 非风击 == null:
			非风击 = c
	if 风击 != null and 非风击 != null:
		玩家1.hand_cards = [风击.id, 非风击.id]
		# 风怒追击现在是「攻击行动结束自动生效」，不再弹确认
		剑圣.p_after_attack({"player": 1})
		var 数据: Dictionary = 玩家1.额外行动数据(103)
		# 限定系别只写 element（规则），白名单由引擎按「该系攻击牌」现算：含风系、不含其它系
		var 首白: Array = 引擎.额外行动出牌白名单(数据)
		检(首白.has(风击.id) and not 首白.has(非风击.id),
			"风怒追击那份行动应只允许风系攻击牌，实际 %s" % str(首白))
		检(int(数据.get("element", 0)) == GConst.CardElement.Wind,
			"风怒追击那份行动的系别应标成风：%d" % int(数据.get("element", 0)))
		检(bool(数据.get("direct", false)),
			"自动生效的风怒追击应标 direct，引擎才能直接进入它的额外攻击阶段")
		# 系别要一路下发到行动询问：客户端按钮才会写成「额外【攻击行动】：风系」
		引擎.push(BattleEngine.SAdditionalAction.new())
		引擎.run()
		var 风命令: Array = 引擎.action_commands(1, GConst.ActionType.Attack, true, true, false, 103)
		var 风首: Dictionary = 风命令[0] if not 风命令.is_empty() else {}
		检(int(风首.get("extra_element", 0)) == GConst.CardElement.Wind,
			"带系别的额外攻击行动应把系别随行动询问下发：%s" % str(风首))
		引擎._states.clear()
		引擎._清空等待()
		引擎.当前额外行动数据 = {}
		玩家1.撤回额外行动(103)
		剑圣.active_lian_xu_ji = false
		玩家1.hand_cards = [非风击.id]
		剑圣.p_after_attack({"player": 1})
		数据 = 玩家1.额外行动数据(103)
		# 限定系别是**规则**不是手牌快照：手里没有风系攻击牌时，规则仍然只放行风系攻击牌
		# （之后摸到风系攻击牌也能出；以前这里会算成「全禁」，把玩家手里的风系牌全灰掉）
		var 风白: Array = 引擎.额外行动出牌白名单(数据)
		检(风白.has(风击.id) and not 风白.has(非风击.id),
			"风怒追击的白名单应始终只含风系攻击牌（与当时手牌无关）：%s" % str(风白))
		# 恢复 dummy 角色，避免影响同用例后续
		玩家1.role = 角色
	else:
		检(false, "卡库里找不到一张风系攻击牌和一张非风系攻击牌")

	# ---- 场景 11：攻击结束时风怒追击自动入队（不再询问），响应里只剩剑影要问 ----
	_重置战斗()
	var 剑圣二: BattleRole = 剑圣类.new()
	剑圣二.setup(玩家1, 引擎)
	玩家1.role = 剑圣二
	玩家1.set_gem(1)
	引擎._push_action_end_hooks("p_after_attack", {"player": 1}, false, 0)
	引擎.run()
	var 一问: Array = 引擎._最后询问.get(1, {}).get("commands", [])
	var 一选项: Array = (一问[0] as Dictionary).get("args", []) if not 一问.is_empty() else []
	检(一选项.size() >= 5 and 一选项.slice(4) == [105],
		"风怒追击不再占响应选项，攻击结束只应问剑影：%s" % str(一选项))
	var 自动有风: bool = false
	for a: Dictionary in 玩家1.additional_actions:
		if int(a.get("cause", 0)) == 103 and bool(a.get("direct", false)):
			自动有风 = true
	检(自动有风, "风怒追击应在攻击结束时自动以 direct 入队：%s" % str(玩家1.additional_actions))
	# 确认剑影：两份额外行动都应以 direct 入队、等收尾时再进入
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 105, "src_id": 1, "args": [105], "card_ids": [], "dst_ids": [],
	})
	var 有风: bool = false
	var 有影: bool = false
	for a: Dictionary in 玩家1.additional_actions:
		if int(a.get("cause", 0)) == 103 and bool(a.get("direct", false)):
			有风 = true
		elif int(a.get("cause", 0)) == 105 and bool(a.get("direct", false)):
			有影 = true
	检(有风 and 有影, "确认后两份额外行动都应以 direct 入队、等收尾时再进入：%s"
		% str(玩家1.additional_actions))

	# ---- 场景 12：响应快捷按钮已经选好风系攻击牌 + 目标，自动进入 103 应立即发起攻击 ----
	_重置战斗()
	var 剑圣三: BattleRole = 剑圣类.new()
	剑圣三.setup(玩家1, 引擎)
	玩家1.role = 剑圣三
	玩家1.set_gem(1)
	var 风击三: GCard = null
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.is_attack() \
				and c.element_enum() == GConst.CardElement.Wind:
			风击三 = c
			break
	if 风击三 != null:
		玩家1.hand_cards.append(风击三.id)
		玩家1.add_action(GConst.ActionType.Attack, 103, true, true)
		引擎.首选额外行动 = 103
		引擎.首选额外行动卡 = 风击三.id
		引擎.首选额外行动目标 = 3
		引擎.push(BattleEngine.SAdditionalAction.new())
		引擎.run()
		检(引擎.行动额外来源 == 103,
			"自动额外攻击来源应为 103：%d" % 引擎.行动额外来源)
		检(引擎._await_id == 3 and 引擎._await_kind == GConst.Msg.Respond,
			"风系攻击牌 + 目标应直接进入应战询问（等待 %s / %s）" % [str(引擎._await_id), str(引擎._await_kind)])
	else:
		检(false, "卡库里找不到风系攻击牌")

	# ---- 场景 14：额外攻击阶段点另一份行动再出手，应按选择消耗，不按队列顺序 ----
	_重置战斗()
	玩家1.role = 角色
	玩家1.hand_cards.append(攻击牌甲.id)
	玩家1.add_action(GConst.ActionType.Attack, 103, true, true)
	玩家1.add_action(GConst.ActionType.Attack, 105, true, true)
	引擎.push(BattleEngine.SAdditionalAction.new())
	引擎.run()
	检(引擎.行动额外来源 == 103 and 引擎._await_kind == GConst.Msg.Action,
		"多份 direct 额外行动应先进入第一份（来源 %d / 等待 %s）"
		% [引擎.行动额外来源, str(引擎._await_kind)])
	引擎.on_message(1, GConst.Msg.Action, {
		"action_type": GConst.ActionType.Attack, "src_id": 1,
		"card_ids": [攻击牌甲.id], "dst_ids": [3], "args": [105],
	})
	检(引擎.行动额外来源 == 105,
		"出手时应按客户端选择的 105 换队，而不是按顺序消耗 103：来源 %d"
		% 引擎.行动额外来源)
	var 剩103: bool = false
	for a: Dictionary in 玩家1.additional_actions:
		if int(a.get("cause", 0)) == 103:
			剩103 = true
			break
	检(剩103, "换队后未使用的 103 应退回队列：%s" % str(玩家1.additional_actions))

	# ---- 场景 15：剑影已在确认时付能量，即使当前能量 0 也应允许进入 / 切换，且不继承 103 的风系限制 ----
	_重置战斗()
	var 剑圣五: BattleRole = 剑圣类.new()
	剑圣五.setup(玩家1, 引擎)
	玩家1.role = 剑圣五
	玩家1.set_gem(0)
	剑圣五._jian_ying_paid = true
	玩家1.add_action(GConst.ActionType.Attack, 105, true, true)
	引擎.push(BattleEngine.SAdditionalAction.new())
	引擎.run()
	检(引擎.行动额外来源 == 105 and 引擎._await_kind == GConst.Msg.Action,
		"已付能量的剑影应能进入额外攻击阶段（来源 %d / 等待 %s）"
		% [引擎.行动额外来源, str(引擎._await_kind)])
	# 剑影那份行动不带系别限制，随便哪一系的攻击牌都该放行（限制只存在于行动自己的规格里）
	var 非风五: GCard = null
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.is_attack() \
				and c.element_enum() != GConst.CardElement.Wind:
			非风五 = c
			break
	玩家1.hand_cards.append(非风五.id)
	检((玩家1.额外行动数据(105).get("cards", []) as Array).is_empty(),
		"剑影那份行动不应带任何出牌白名单：%s" % str(玩家1.额外行动数据(105)))
	检(引擎.校验额外行动限制(玩家1, 玩家1.额外行动数据(105), GConst.ActionType.Attack,
		[非风五.id], [3]) == GConst.GE_SUCCESS,
		"剑影额外攻击不应继承风怒追击的风系限制")

	# ---- 场景 16：当前是疾风技给的额外行动时，切到风怒追击再出手应消耗风怒追击 ----
	_重置战斗()
	var 剑圣六: BattleRole = 剑圣类.new()
	剑圣六.setup(玩家1, 引擎)
	玩家1.role = 剑圣六
	var 风击六: GCard = null
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.is_attack() \
				and c.element_enum() == GConst.CardElement.Wind:
			风击六 = c
			break
	玩家1.hand_cards.append(风击六.id)
	var 非风六: GCard = null
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.is_attack() \
				and c.element_enum() != GConst.CardElement.Wind:
			非风六 = c
			break
	if 非风六 != null:
		玩家1.hand_cards.append(非风六.id)
	玩家1.add_action(GConst.ActionType.Attack, 101, true, true)
	玩家1.add_action(GConst.ActionType.Attack, 103, true, true, {
		"cards": 剑圣六.按系攻击牌(GConst.CardElement.Wind),
		"element": GConst.CardElement.Wind,
	})
	检((玩家1.额外行动数据(101).get("cards", []) as Array).is_empty(),
		"疾风技给的额外攻击不该自带任何白名单：%s" % str(玩家1.额外行动数据(101)))
	引擎.push(BattleEngine.SAdditionalAction.new())
	引擎.run()
	检(引擎.行动额外来源 == 101, "应先进入疾风技给的额外行动：%d" % 引擎.行动额外来源)
	引擎.on_message(1, GConst.Msg.Action, {
		"action_type": GConst.ActionType.Attack, "src_id": 1,
		"card_ids": [风击六.id], "dst_ids": [3], "args": [103],
	})
	检(引擎.行动额外来源 == 103,
		"从疾风技切到风怒追击后应按选择消耗 103，实际 %d" % 引擎.行动额外来源)
	var 退回101: bool = false
	for a: Dictionary in 玩家1.additional_actions:
		if int(a.get("cause", 0)) == 101:
			退回101 = true
			break
	检(退回101, "未使用的疾风技额外行动应退回队列：%s" % str(玩家1.additional_actions))

	# ---- 场景 23：风怒追击进入后切到剑影并真正用掉剑影，风怒追击还应能再进入 ----
	_重置战斗()
	var 剑圣十一: BattleRole = 剑圣类.new()
	剑圣十一.setup(玩家1, 引擎)
	玩家1.role = 剑圣十一
	var 风击十一: GCard = null
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.is_attack() \
				and c.element_enum() == GConst.CardElement.Wind:
			风击十一 = c
			break
	if 风击十一 != null:
		玩家1.hand_cards.append(风击十一.id)
		玩家1.add_action(GConst.ActionType.Attack, 103, true, true)
		玩家1.add_action(GConst.ActionType.Attack, 105, true, true)
		引擎.push(BattleEngine.SAdditionalAction.new())
		引擎.run()
		检(引擎.行动额外来源 == 103, "应先进入风怒追击：%d" % 引擎.行动额外来源)
		检(not 剑圣十一.used_lian_xu_ji, "刚进入风怒追击、还没出手时不应标记已用")
		引擎.on_message(1, GConst.Msg.Action, {
			"action_type": GConst.ActionType.Attack, "src_id": 1,
			"card_ids": [风击十一.id], "dst_ids": [3], "args": [105],
		})
		# 被攻击方放弃应战，让剑影这次攻击结算完
		引擎.on_message(引擎._await_id, GConst.Msg.Respond, {
			"respond_id": GConst.RespondType.ReplyAttack, "src_id": 3,
			"args": [], "card_ids": [], "dst_ids": [],
		})
		检(引擎.行动额外来源 == 103 and 引擎._await_kind == GConst.Msg.Action,
			"剑影用掉后应能重新进入风怒追击，不能只剩取消：来源 %d / 等待 %s / 已用103=%s / 队列=%s / 最后=%s"
			% [引擎.行动额外来源, str(引擎._await_kind), str(剑圣十一.used_lian_xu_ji),
				str(玩家1.additional_actions), str(引擎._最后询问)])
		检(剑圣十一.used_jian_ying, "剑影出手后应立即标记本回合已用")
		var 再用选项: Array = 剑圣十一.action_end_options({})
		var 再有剑影: bool = false
		for o: Dictionary in 再用选项:
			if int(o.get("value", 0)) == 105:
				再有剑影 = true
		检(not 再有剑影, "剑影本回合用过后不能再出现在攻击结束选项里：%s" % str(再用选项))

	# ---- 场景 20：没有角色攻击结束响应的玩家，也要在同一次行动结束响应里处理迅捷赐福 ----
	_重置战斗()
	var 无响应迅捷牌: GCard = null
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.has_skill_id(GConst.技能_迅捷赐福):
			无响应迅捷牌 = c
			break
	if 无响应迅捷牌 != null:
		玩家1.role = null
		var 祈祷乙 = preload("res://scripts/battle/roles/role_qidao.gd").new()
		祈祷乙.setup(引擎.p(2), 引擎)
		引擎.p(2).role = 祈祷乙
		玩家1.hand_cards.append(攻击牌甲.id)
		检(引擎.add_basic_effect(1, 无响应迅捷牌.id, 2, GConst.技能_迅捷赐福) == GConst.GE_SUCCESS,
			"无角色响应时迅捷赐福也应能贴上")
		引擎.current_id = 1
		引擎._push_action_end_hooks("p_after_attack", {"player": 1}, false, 0)
		引擎.run()
		var 无响应问: Array = 引擎._最后询问.get(1, {}).get("commands", [])
		var 无响应选项: Array = (无响应问[0] as Dictionary).get("args", []) \
			if not 无响应问.is_empty() else []
		检(无响应选项.slice(4).has(GConst.技能_迅捷赐福),
			"没有角色攻击结束响应时也应补一次迅捷赐福响应：%s" % str(无响应选项))
		# 行动结束响应整排选项：服务端应标「默认选第一项」，客户端据此预选（不用先点一下）
		检(int((无响应问[0] as Dictionary).get("default_option", -1)) == 0,
			"行动结束响应应下发 default_option=0（默认选中第一项）")
		# 聚合器的 respond_id 只是列表第一项：必须标 no_parent，否则客户端会多摆一颗
		# 「被问技能」本体，和同名选项并排成两个一模一样的按钮（如神圣追击 2501）
		检(bool((无响应问[0] as Dictionary).get("no_parent", false)),
			"行动结束响应应下发 no_parent（不摆被问技能的本体按钮）")
		引擎.on_message(1, GConst.Msg.Respond, {
			"respond_id": GConst.技能_迅捷赐福, "src_id": 1,
			"args": [GConst.技能_迅捷赐福], "card_ids": [], "dst_ids": [],
		})
		检(玩家1.basic_effects.is_empty(), "无角色响应时确认迅捷赐福也应立即移除赐福")
		var 无响应直接: bool = false
		for a: Dictionary in 玩家1.additional_actions:
			if int(a.get("cause", 0)) == GConst.技能_迅捷赐福 and bool(a.get("direct", false)):
				无响应直接 = true
		检(无响应直接, "无角色响应时得到的 1601 行动也应是 direct：%s"
			% str(玩家1.additional_actions))

	# ---- 场景 21：取消行动结束响应只结束响应，不再清空 / 跳过额外行动；
	#      迅捷赐福的牌还在时，后续行动结束仍会再问（取消不影响已获得的额外行动）----
	_重置战斗()
	var 剑圣十: BattleRole = 剑圣类.new()
	剑圣十.setup(玩家1, 引擎)
	玩家1.role = 剑圣十
	var 祈祷丙 = preload("res://scripts/battle/roles/role_qidao.gd").new()
	祈祷丙.setup(引擎.p(2), 引擎)
	引擎.p(2).role = 祈祷丙
	玩家1.hand_cards.append(攻击牌甲.id)
	var 双问牌: GCard = null
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.has_skill_id(GConst.技能_迅捷赐福):
			双问牌 = c
			break
	if 双问牌 != null:
		检(引擎.add_basic_effect(1, 双问牌.id, 2, GConst.技能_迅捷赐福) == GConst.GE_SUCCESS,
			"第二次询问测试的迅捷赐福应贴上")
		引擎.current_id = 1
		引擎._push_action_end_hooks("p_after_attack", {"player": 1}, false, 0)
		引擎.run()
		检(not 引擎.基础效果额外行动选项(1).is_empty(),
			"攻击结束响应应摆出迅捷赐福")
		# 排序：行动（额外行动 / 基础效果）排在角色响应技能之前
		var 排序问: Array = 引擎._最后询问.get(1, {}).get("commands", [])
		var 排序选项: Array = (排序问[0] as Dictionary).get("args", []) if not 排序问.is_empty() else []
		检(排序选项.slice(4) == [GConst.技能_迅捷赐福, 105],
			"额外行动应排在角色响应技能（剑影）之前：%s" % str(排序选项))
		var 取消前询问数: int = 引擎._询问计数
		引擎.on_message(1, GConst.Msg.Respond, {
			"respond_id": 103, "src_id": 1, "args": [], "card_ids": [], "dst_ids": [],
		})
		检(引擎._询问计数 == 取消前询问数,
			"取消攻击结束响应后不应马上再问一遍（询问数 %d→%d）"
			% [取消前询问数, 引擎._询问计数])
		检(not 玩家1.跳过额外攻击行动, "取消响应只结束响应，不应再标记跳过后续额外攻击")
		检(not (引擎._await_state is BattleEngine.SAdditionalAction),
			"取消攻击结束响应后不应进入额外行动询问：%s" % str(引擎._await_state))
		# 方案A：取消不再把迅捷赐福记成「本回合已拒绝」—— 牌还在，后面行动结束还能再问
		检(not 引擎.基础效果额外行动选项(1).is_empty(),
			"取消后本回合仍应保留迅捷赐福选项（不再记成本回合已拒绝）")
		# 模拟取消后本回合又有一次攻击 / 法术行动结束：仍应只问基础效果（角色额外攻击行动已跳过）
		引擎._states.clear()
		引擎._清空等待()
		引擎.current_id = 1
		引擎.push(BattleEngine.S行动聚合器.new({"player": 1}))
		引擎.run()
		var 再问: Array = 引擎._最后询问.get(1, {}).get("commands", [])
		var 再问选项: Array = (再问[0] as Dictionary).get("args", []) if not 再问.is_empty() else []
		检(再问选项.slice(4).has(GConst.技能_迅捷赐福) and 再问选项.slice(4).has(105),
			"取消响应后再有行动结束，赐福与角色额外攻击选项都应还在：%s" % str(再问选项))
		if 再问选项.slice(4).has(GConst.技能_迅捷赐福):
			引擎.on_message(1, GConst.Msg.Respond, {
				"respond_id": 0, "src_id": 1, "args": [GConst.技能_迅捷赐福],
				"card_ids": [], "dst_ids": [],
			})
			检(not 玩家1.check_basic_effect_skill(GConst.技能_迅捷赐福),
				"确认迅捷赐福后应移除赐福牌")
			检(not 玩家1.跳过额外攻击行动, "取消后的跳过标记不应被这一份基础效果解除")
			引擎._清除额外攻击行动(1)
			var 仍留: bool = false
			for a: Dictionary in 玩家1.additional_actions:
				if int(a.get("cause", 0)) == GConst.技能_迅捷赐福 and bool(a.get("direct", false)):
					仍留 = true
			检(仍留, "取消后确认的迅捷赐福额外行动应保留（direct），不能被再次清掉")
			# 进入额外行动：取消标记还在，但这份基础效果是玩家明确选的，必须能真正用出来
			引擎._states.clear()
			引擎._清空等待()
			引擎.current_id = 1
			引擎.push(BattleEngine.SAdditionalAction.new())
			引擎.run()
			检(引擎.行动额外 and 引擎.行动额外来源 == GConst.技能_迅捷赐福,
				"取消后确认的迅捷赐福应能进入额外攻击行动（来源=%d）" % 引擎.行动额外来源)

	# ---- 场景 22：祈祷师本人没有攻击结束角色响应，确认迅捷赐福后必须能直接用 1601 攻击 ----
	_重置战斗()
	var 祈祷丁 = preload("res://scripts/battle/roles/role_qidao.gd").new()
	祈祷丁.setup(玩家1, 引擎)
	玩家1.role = 祈祷丁
	玩家1.hand_cards.append(攻击牌甲.id)
	var 自贴牌: GCard = null
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.has_skill_id(GConst.技能_迅捷赐福):
			自贴牌 = c
			break
	if 自贴牌 != null:
		检(引擎.add_basic_effect(1, 自贴牌.id, 1, GConst.技能_迅捷赐福) == GConst.GE_SUCCESS,
			"祈祷师自己面前也应能贴迅捷赐福")
		引擎.current_id = 1
		引擎.push(BattleEngine.STurnEnd.new())
		引擎._push_action_end_hooks("p_after_attack", {"player": 1}, false, 0)
		引擎.run()
		var 自问: Array = 引擎._最后询问.get(1, {}).get("commands", [])
		var 自选: Array = (自问[0] as Dictionary).get("args", []) if not 自问.is_empty() else []
		检(自选.slice(4).has(GConst.技能_迅捷赐福), "祈祷师本人应收到迅捷赐福响应：%s" % str(自选))
		引擎.on_message(1, GConst.Msg.Respond, {
			"respond_id": GConst.技能_迅捷赐福, "src_id": 1,
			"args": [GConst.技能_迅捷赐福], "card_ids": [], "dst_ids": [],
		})
		检(引擎.行动额外来源 == GConst.技能_迅捷赐福 and 引擎._await_kind == GConst.Msg.Action,
			"祈祷师确认迅捷赐福后应直接进入 1601 攻击行动：来源 %d / 等待 %s"
			% [引擎.行动额外来源, str(引擎._await_kind)])

	# ---- 场景 24：修罗连斩的额外攻击走通用系别功能，限定火系 ----
	_重置战斗()
	var 魔剑类 = preload("res://scripts/battle/roles/role_mojian.gd")
	var 魔剑: BattleRole = 魔剑类.new()
	魔剑.setup(玩家1, 引擎)
	玩家1.role = 魔剑
	var 火攻: GCard = null
	var 非火攻: GCard = null
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual or not c.is_attack():
			continue
		if c.element_enum() == GConst.CardElement.Fire and 火攻 == null:
			火攻 = c
		elif c.element_enum() != GConst.CardElement.Fire and 非火攻 == null:
			非火攻 = c
	if 火攻 != null and 非火攻 != null:
		玩家1.hand_cards.append(火攻.id)
		玩家1.hand_cards.append(非火攻.id)
		# 修罗连斩现在也是「攻击行动结束自动生效」，不再弹确认
		魔剑.p_after_attack({"player": 1})
		var 火数据: Dictionary = 玩家1.额外行动数据(901)
		var 火白: Array = 引擎.额外行动出牌白名单(火数据)
		检(火白.has(火攻.id) and not 火白.has(非火攻.id),
			"修罗连斩那份行动应只允许火系攻击牌：%s" % str(火白))
		检(int(火数据.get("element", 0)) == GConst.CardElement.Fire,
			"修罗连斩的额外行动应下发火系，界面才能显示「额外【攻击行动】：火系」")
		检(bool(火数据.get("direct", false)),
			"自动生效的修罗连斩应标 direct，引擎才能直接进入它的额外攻击阶段")
		检(引擎.校验额外行动限制(玩家1, 火数据, GConst.ActionType.Attack,
			[非火攻.id], [3]) != GConst.GE_SUCCESS,
			"修罗连斩额外攻击不能用非火系攻击牌")
		检(引擎.校验额外行动限制(玩家1, 火数据, GConst.ActionType.Attack,
			[火攻.id], [3]) == GConst.GE_SUCCESS,
			"修罗连斩额外攻击应能使用火系攻击牌")

	# ---- 场景 25：修罗连斩自动生效后，攻击结束响应里只剩迅捷赐福；901 以快捷按钮出现 ----
	_重置战斗()
	var 魔剑二: BattleRole = preload("res://scripts/battle/roles/role_mojian.gd").new()
	魔剑二.setup(玩家1, 引擎)
	玩家1.role = 魔剑二
	var 聚合迅捷牌: GCard = null
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.has_skill_id(GConst.技能_迅捷赐福):
			聚合迅捷牌 = c
			break
	if 聚合迅捷牌 != null:
		玩家1.hand_cards.append(攻击牌甲.id)
		检(引擎.add_basic_effect(1, 聚合迅捷牌.id, 2, GConst.技能_迅捷赐福) == GConst.GE_SUCCESS,
			"聚合器测试的迅捷赐福应贴上")
		引擎.current_id = 1
		引擎._push_action_end_hooks("p_after_attack", {"player": 1}, false, 0)
		引擎.run()
		var 聚合问: Array = 引擎._最后询问.get(1, {}).get("commands", [])
		var 聚合选: Array = (聚合问[0] as Dictionary).get("args", []) if not 聚合问.is_empty() else []
		var 聚合快捷: Array = (聚合问[0] as Dictionary).get("extra_attack_causes", []) \
			if not 聚合问.is_empty() else []
		检(not 聚合选.slice(4).has(901),
			"修罗连斩已自动生效，不应再作为响应选项出现：%s" % str(聚合选))
		检(聚合选.slice(4).has(GConst.技能_迅捷赐福),
			"迅捷赐福仍应在攻击结束响应里：%s" % str(聚合选))
		检(聚合快捷.has(901),
			"自动生效的修罗连斩应以红色快捷按钮出现：%s" % str(聚合快捷))
		检(引擎._await_id == 1 and 引擎._await_kind == GConst.Msg.Respond,
			"聚合响应应在等玩家 1 的 Respond：id=%d kind=%s" % [引擎._await_id, str(引擎._await_kind)])
		# 取消聚合响应＝所有后续额外攻击都不再处理（含自动获得的修罗连斩）
		引擎.on_message(1, GConst.Msg.Respond, {
			"respond_id": GConst.技能_迅捷赐福, "src_id": 1,
			"args": [], "card_ids": [], "dst_ids": [],
		})
		检(not 玩家1.additional_actions.is_empty() and not 玩家1.跳过额外攻击行动,
			"取消响应只取消响应，额外行动应保留（跳过=false）：%s" % str(玩家1.additional_actions))

	# ---- 场景 26：方案 A：在聚合响应里点选有代价的额外行动，立刻扣费 ----
	_重置战斗()
	var 剑帝类 = preload("res://scripts/battle/roles/role_jiandi.gd")
	var 剑帝: BattleRole = 剑帝类.new()
	剑帝.setup(玩家1, 引擎)
	玩家1.role = 剑帝
	玩家1.set_gem(1)
	玩家1.hand_cards.append(攻击牌甲.id)
	var 付费迅捷牌: GCard = null
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.has_skill_id(GConst.技能_迅捷赐福):
			付费迅捷牌 = c
			break
	if 付费迅捷牌 != null:
		检(引擎.add_basic_effect(1, 付费迅捷牌.id, 2, GConst.技能_迅捷赐福) == GConst.GE_SUCCESS,
			"付费测试的迅捷赐福应贴上")
		引擎.current_id = 1
		引擎._push_action_end_hooks("p_after_attack", {"player": 1}, false, 0)
		引擎.run()
		var 付费问: Array = 引擎._最后询问.get(1, {}).get("commands", [])
		var 付费选: Array = (付费问[0] as Dictionary).get("args", []) if not 付费问.is_empty() else []
		检(付费选.slice(4).has(1907) and 付费选.slice(4).has(GConst.技能_迅捷赐福),
			"不屈意志和迅捷赐福应在同一列表：%s" % str(付费选))
		引擎.on_message(1, GConst.Msg.Respond, {
			"respond_id": GConst.技能_迅捷赐福, "src_id": 1,
			"args": [1907], "card_ids": [], "dst_ids": [],
		})
		检(玩家1.get_energy() == 0, "点选不屈意志时应立即扣 1 能量（方案 A），实际 %d"
			% 玩家1.get_energy())
		var 付费直接: bool = false
		for a: Dictionary in 玩家1.additional_actions:
			if int(a.get("cause", 0)) == 1907 and bool(a.get("direct", false)):
				付费直接 = true
		检(付费直接, "扣费后的不屈意志应标记 direct：%s" % str(玩家1.additional_actions))
		引擎.on_message(1, GConst.Msg.Respond, {
			"respond_id": GConst.技能_迅捷赐福, "src_id": 1,
			"args": [], "card_ids": [], "dst_ids": [],
		})
		检(not 玩家1.additional_actions.is_empty(),
			"取消响应不应清掉已获得的额外行动：%s" % str(玩家1.additional_actions))
		检(玩家1.get_energy() == 0, "取消响应不退还已付费用（方案 A）")

	# ---- 场景 27：猎巫人的偷袭也作为普通技能选项，与迅捷赐福同列表 ----
	_重置战斗()
	var 猎人类 = preload("res://scripts/battle/roles/role_liewuren.gd")
	var 猎人: BattleRole = 猎人类.new()
	猎人.setup(玩家1, 引擎)
	玩家1.role = 猎人
	玩家1.set_gem(1)
	var 猎人迅捷牌: GCard = null
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.has_skill_id(GConst.技能_迅捷赐福):
			猎人迅捷牌 = c
			break
	var 盖牌材料: Array[GCard] = []
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and not c.is_magic() and not c.is_attack():
			盖牌材料.append(c)
		if 盖牌材料.size() >= 2:
			break
	if 猎人迅捷牌 != null and 盖牌材料.size() >= 2:
		for c: GCard in 盖牌材料:
			玩家1.cover_cards.append(c.id)
		玩家1.hand_cards.append(攻击牌甲.id)
		检(引擎.add_basic_effect(1, 猎人迅捷牌.id, 2, GConst.技能_迅捷赐福) == GConst.GE_SUCCESS,
			"猎人的迅捷赐福应贴上")
		引擎.current_id = 1
		引擎._push_action_end_hooks("p_after_attack", {"player": 1}, false, 0)
		引擎.run()
		var 猎人问: Array = 引擎._最后询问.get(1, {}).get("commands", [])
		var 猎人选项: Array = (猎人问[0] as Dictionary).get("args", []) \
			if not 猎人问.is_empty() else []
		检(猎人选项.slice(4).has(4205) and 猎人选项.slice(4).has(GConst.技能_迅捷赐福),
			"偷袭和迅捷赐福应在同一响应列表：%s" % str(猎人选项))

	# ---- 场景 28：魔弓的多重射击与迅捷赐福同列表 ----
	_重置战斗()
	var 魔弓类 = preload("res://scripts/battle/roles/role_mogong.gd")
	var 魔弓: BattleRole = 魔弓类.new()
	魔弓.setup(玩家1, 引擎)
	玩家1.role = 魔弓
	魔弓._available_duo_chong = true
	魔弓._last_target = -1
	var 魔弓迅捷牌: GCard = null
	var 风充能: GCard = null
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual:
			continue
		if 魔弓迅捷牌 == null and c.has_skill_id(GConst.技能_迅捷赐福):
			魔弓迅捷牌 = c
		if 风充能 == null and c.element_enum() == GConst.CardElement.Wind:
			风充能 = c
	if 魔弓迅捷牌 != null and 风充能 != null:
		玩家1.cover_cards.append(风充能.id)
		玩家1.hand_cards.append(攻击牌甲.id)
		检(引擎.add_basic_effect(1, 魔弓迅捷牌.id, 2, GConst.技能_迅捷赐福) == GConst.GE_SUCCESS,
			"魔弓的迅捷赐福应贴上")
		引擎.current_id = 1
		引擎._push_action_end_hooks("p_after_attack", {"player": 1}, false, 0)
		引擎.run()
		var 魔弓问: Array = 引擎._最后询问.get(1, {}).get("commands", [])
		var 魔弓选项: Array = (魔弓问[0] as Dictionary).get("args", []) \
			if not 魔弓问.is_empty() else []
		检(魔弓选项.slice(4).has(2603) and 魔弓选项.slice(4).has(GConst.技能_迅捷赐福),
			"多重射击和迅捷赐福应在同一响应列表：%s" % str(魔弓选项))
		# 确认多重射击：这次暗系攻击必须先结算（等应战者），不能把迅捷赐福先问出来
		引擎.on_message(1, GConst.Msg.Respond, {
			"respond_id": 2603, "src_id": 1, "args": [2603], "card_ids": [], "dst_ids": [3],
		})
		引擎.run()
		检(int(引擎._await_id) == 3,
			"多重射击的攻击应先结算（应等应战者），实际等待 %s（询问号 %s）"
			% [str(引擎._await_id), str(引擎._pending_respond_id)])

	# ---- 场景 29：格斗家念弹必须最先结算，之后再问迅捷赐福 ----
	_重置战斗()
	var 格斗类 = preload("res://scripts/battle/roles/role_gedou.gd")
	var 格斗: BattleRole = 格斗类.new()
	格斗.setup(玩家1, 引擎)
	玩家1.role = 格斗
	玩家1.tokens[0]["num"] = 0
	玩家1.tokens[0]["max"] = 3
	var 格斗迅捷牌: GCard = null
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.has_skill_id(GConst.技能_迅捷赐福):
			格斗迅捷牌 = c
			break
	if 格斗迅捷牌 != null:
		玩家1.hand_cards.append(攻击牌甲.id)
		检(引擎.add_basic_effect(1, 格斗迅捷牌.id, 2, GConst.技能_迅捷赐福) == GConst.GE_SUCCESS,
			"格斗家的迅捷赐福应贴上")
		引擎.current_id = 1
		引擎._push_action_end_hooks("p_after_magic", {"player": 1, "kind": "magic"}, false, 0)
		引擎.run()
		var 念弹问: Array = 引擎._最后询问.get(1, {}).get("commands", [])
		var 念弹号: int = int((念弹问[0] as Dictionary).get("respond_id", 0)) \
			if not 念弹问.is_empty() else 0
		检(念弹号 == 2003, "法术结束后应先问念弹，而不是先问迅捷赐福：%s" % str(念弹问))

	# ---- 场景 30：切换额外攻击不应把退回的行动挪到队尾，整体顺序保持稳定 ----
	_重置战斗()
	var 剑圣序: BattleRole = 剑圣类.new()
	剑圣序.setup(玩家1, 引擎)
	玩家1.role = 剑圣序
	玩家1.add_action(GConst.ActionType.Attack, 101, true, true)
	玩家1.add_action(GConst.ActionType.Attack, 103, true, true)
	玩家1.add_action(GConst.ActionType.Attack, 105, true, true)
	引擎.push(BattleEngine.SAdditionalAction.new())
	引擎.run()
	检(引擎.行动额外来源 == 101, "应先进入 101：%d" % 引擎.行动额外来源)
	var 队列阶段 = 引擎._当前状态
	检(队列阶段 is BattleEngine.SActionPhase, "当前应是额外行动阶段")
	if 队列阶段 is BattleEngine.SActionPhase:
		引擎.切换额外攻击(队列阶段, 玩家1, 103)
		var 序一: Array = []
		for a: Dictionary in 玩家1.additional_actions:
			序一.append(int(a.get("cause", 0)))
		检(序一 == [101, 105], "切到 103 后队列应保持 [101,105]：%s" % str(序一))
		引擎.切换额外攻击(队列阶段, 玩家1, 105)
		var 序二: Array = []
		for a: Dictionary in 玩家1.additional_actions:
			序二.append(int(a.get("cause", 0)))
		检(序二 == [101, 103], "再切到 105 后队列应保持 [101,103]：%s" % str(序二))

	# ---- 场景 31：圣剑超时/跳过时必须把自动抽到的牌自动弃掉 ----
	_重置战斗()
	var 圣剑类 = preload("res://scripts/battle/roles/role_jiansheng.gd")
	var 圣剑: BattleRole = 圣剑类.new()
	圣剑.setup(玩家1, 引擎)
	玩家1.role = 圣剑
	玩家1.hand_cards = [攻击牌甲.id, 攻击牌乙.id, 攻击牌甲.id]
	var 圣剑原手: int = 玩家1.hand_cards.size()
	圣剑._sheng_jian_active = true
	圣剑._sheng_jian_step = 0
	引擎.current_id = 1
	引擎._push_action_end_hooks("p_after_attack", {"player": 1}, false, 0)
	引擎.run()
	# 选摸 2 张
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 104, "src_id": 1,
		"args": [2], "card_ids": [], "dst_ids": [],
	})
	引擎.run()
	# 弃牌询问直接跳过（模拟超时）：服务端应自动补弃 2 张
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 104, "src_id": 1,
		"args": [], "card_ids": [], "dst_ids": [],
	})
	引擎.run()
	检(玩家1.hand_cards.size() == 圣剑原手,
		"圣剑自动摸 2 张后跳过弃牌，应自动弃 2 张，手牌应回到 %d，实际 %d"
		% [圣剑原手, 玩家1.hand_cards.size()])
	检(玩家1.hand_cards.size() >= 2, "圣剑自动弃牌后不应把手牌弃空")

	# ---- 场景 31b：圣剑摸牌把手里摸超上限时，必须先走超限弃牌 + 掉士气，再结算「弃 X 张」----
	_重置战斗()
	var 圣剑超类 = preload("res://scripts/battle/roles/role_jiansheng.gd")
	var 圣剑超: BattleRole = 圣剑超类.new()
	圣剑超.setup(玩家1, 引擎)
	玩家1.role = 圣剑超
	var 六张: Array[int] = []
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual or 六张.has(c.id):
			continue
		六张.append(c.id)
		if 六张.size() >= 6:
			break
	玩家1.hand_cards = 六张
	玩家1.set_crystal(0)
	玩家1.set_gem(0)
	引擎.team_morale[玩家1.color] = 15
	圣剑超._sheng_jian_active = true
	圣剑超._sheng_jian_step = 0
	引擎.current_id = 1
	引擎._push_action_end_hooks("p_after_attack", {"player": 1}, false, 0)
	引擎.run()
	# 选摸 3 张：6 + 3 = 9 > 上限 6，应先走超限弃牌
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 104, "src_id": 1, "args": [3], "card_ids": [], "dst_ids": [],
	})
	引擎.run()
	检(引擎._await_id == 1 and int(引擎._pending_respond_id) == GConst.RespondType.Discard,
		"圣剑摸 3 张超过手牌上限时应先走超限弃牌（await=%s respond=%s）"
		% [str(引擎._await_id), str(引擎._pending_respond_id)])
	检(玩家1.hand_cards.size() == 9, "摸 3 张后手牌应有 9 张，实际 %d" % 玩家1.hand_cards.size())
	var 超限弃: Array = 玩家1.hand_cards.slice(0, 3)
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": GConst.RespondType.Discard, "src_id": 1,
		"args": [1, GConst.CAUSE_OVERLOAD, 3],
		"card_ids": 超限弃, "dst_ids": [1],
	})
	引擎.run()
	检(int(引擎.team_morale[玩家1.color]) == 12,
		"超限 3 张应掉 3 点士气，实际 %d" % int(引擎.team_morale[玩家1.color]))
	检(玩家1.hand_cards.size() == 6, "超限弃牌后手牌应回到上限 6，实际 %d" % 玩家1.hand_cards.size())
	检(引擎._await_id == 1 and int(引擎._pending_respond_id) == 104,
		"超限结算完应继续问【圣剑】弃 X 张（respond=%s）" % str(引擎._pending_respond_id))
	var 圣剑弃: Array = 玩家1.hand_cards.slice(0, 3)
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 104, "src_id": 1, "args": [], "card_ids": 圣剑弃, "dst_ids": [],
	})
	引擎.run()
	检(玩家1.hand_cards.size() == 3, "再弃 3 张后手牌应为 3，实际 %d" % 玩家1.hand_cards.size())
	检(not 圣剑超._sheng_jian_active, "圣剑结算完应清掉本次标记")

	# ---- 场景 31c：行动结束响应取消后，本次没确认的额外行动选项要撤回（女武神神圣追击）----
	# 神圣追击（2501）在 p_after_attack 里以 in_end_response 预先入队，只作为响应选项存在；
	# 玩家点「取消」时必须撤回，否则它会以「额外行动」身份漏到额外行动阶段，弹出红色行动按钮。
	_重置战斗()
	var 女武神类 = preload("res://scripts/battle/roles/role_nvwushen.gd")
	var 女武神: BattleRole = 女武神类.new()
	女武神.setup(玩家1, 引擎)
	玩家1.role = 女武神
	玩家1.role_id = 25
	玩家1.cross_num = 1
	引擎.current_id = 1
	引擎._push_action_end_hooks("p_after_attack", {"player": 1}, false, 0)
	引擎.run()
	检(引擎._await_id == 1 and int(引擎._pending_respond_id) == 2501,
		"神圣追击应作为行动结束响应选项摆出来（await=%s respond=%s）"
		% [str(引擎._await_id), str(引擎._pending_respond_id)])
	var 响应期间有: bool = false
	for a: Dictionary in 玩家1.additional_actions:
		if int(a.get("cause", 0)) == 2501:
			响应期间有 = true
		检(响应期间有, "响应期间队列里应有待确认的神圣追击：%s" % str(玩家1.additional_actions))
	# 取消响应：未确认的那份必须撤回
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 2501, "src_id": 1, "args": [], "card_ids": [], "dst_ids": [],
	})
	检(玩家1.additional_actions.is_empty(),
		"取消响应后不应残留未确认的额外行动：%s" % str(玩家1.additional_actions))
	检(int(玩家1.cross_num) == 1, "取消响应不应扣治疗，实际 %d" % int(玩家1.cross_num))
	检(引擎._await_id == 2, "取消后应正常轮到下家，实际等待 %s" % str(引擎._await_id))

	# 确认：照常扣 1 治疗、拿到额外攻击行动（direct，留在队列里）
	_重置战斗()
	玩家1.role = 女武神
	玩家1.cross_num = 1
	引擎.current_id = 1
	引擎._push_action_end_hooks("p_after_attack", {"player": 1}, false, 0)
	引擎.run()
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 2501, "src_id": 1, "args": [2501], "card_ids": [], "dst_ids": [],
	})
	检(int(玩家1.cross_num) == 0, "确认神圣追击应扣 1 治疗，实际 %d" % int(玩家1.cross_num))
	var 确认后有: bool = false
	for a: Dictionary in 玩家1.additional_actions:
		if int(a.get("cause", 0)) == 2501:
			确认后有 = true
		检(确认后有, "确认后应获得额外攻击行动：%s" % str(玩家1.additional_actions))

	# ---- 场景 31d：同一来源的额外行动「第二次确认」时，direct 必须落在队列里那一份 ----
	# 血色剑灵【赤色一闪】用一次之后，引擎.当前额外行动数据 还留着那份；下一次攻击结束再入队一份、
	# 玩家再确认时，旧实现按 cause 找到了「当前那份」，把新入队的那份漏在非 direct 状态，
	# 响应结束后又被当成选项问一次（连续弹两次的根因）。
	_重置战斗()
	var 血剑类 = preload("res://scripts/battle/roles/role_xuejian.gd")
	玩家1.role_id = 34
	var 血剑: BattleRole = 血剑类.new()
	血剑.setup(玩家1, 引擎)
	玩家1.role = 血剑
	玩家1.additional_actions.clear()
	if 玩家1.tokens[0] != null:
		玩家1.tokens[0]["num"] = 2
	# 模拟「上一份赤色一闪还挂在 当前额外行动数据 上」
	var 旧份: Dictionary = {"uid": 9001, "cause": 3402, "allow_action": GConst.ActionType.Attack,
		"direct": true, "in_end_response": true, "已付费": true}
	引擎.当前额外行动数据 = 旧份
	玩家1.add_action(GConst.ActionType.Attack, 3402, false, false, {"in_end_response": true})
	var 新份: Dictionary = 玩家1.额外行动队列数据(3402)
	检(not 新份.is_empty() and not bool(新份.get("direct", false)),
		"新入队的赤色一闪应先是非 direct：%s" % str(新份))
	血剑.resolve_queued_extra_action(3402)
	检(bool(新份.get("direct", false)),
		"确认要把队列里那一份标成 direct（不能被 当前额外行动数据 顶掉）：%s" % str(新份))
	检(bool(新份.get("已付费", false)), "确认后队列里那份要标「已付费」：%s" % str(新份))
	if 玩家1.tokens[0] != null:
		检(int(玩家1.tokens[0]["num"]) == 1,
			"确认应扣 1 鲜血，实际 %d" % int(玩家1.tokens[0]["num"]))
	引擎.当前额外行动数据 = {}

	# ---- 场景 31e：队列里已有「确认过、还没用」的同来源行动时，确认要落在新入队那份 ----
	# 迅捷赐福的行动先确认、赤色一闪后确认；迅捷赐福那份先用掉后，赤色一闪那份还排着。
	# 下一次攻击结束又入队一份赤色一闪，确认时必须标新的这份 ——
	# 按 cause 取第一份会标到旧的那份上，新的永远确认不了，响应会一直重复问。
	_重置战斗()
	var 血剑2: BattleRole = 血剑类.new()
	血剑2.setup(玩家1, 引擎)
	玩家1.role = 血剑2
	玩家1.additional_actions.clear()
	if 玩家1.tokens[0] != null:
		玩家1.tokens[0]["num"] = 2
	# 已确认、还没用掉的两份（迅捷赐福在前、赤色一闪在后），外加本轮新入队的一份赤色一闪
	玩家1.add_action(GConst.ActionType.Attack, GConst.技能_迅捷赐福, true, true)
	玩家1.add_action(GConst.ActionType.Attack, 3402, true, true)
	玩家1.add_action(GConst.ActionType.Attack, 3402, false, false, {"in_end_response": true})
	var 新赤色: Dictionary = 玩家1.额外行动队列数据(3402, true)
	检(not 新赤色.is_empty(), "应有一份未确认的赤色一闪：%s" % str(玩家1.additional_actions))
	血剑2.resolve_queued_extra_action(3402)
	检(bool(新赤色.get("direct", false)),
		"确认要标在新入队那份赤色一闪上（不能标到已确认的旧份）：%s" % str(新赤色))
	检(玩家1.额外行动队列数据(3402, true).is_empty(),
		"确认后不应再剩未确认的赤色一闪（否则响应会再问一次）：%s" % str(玩家1.additional_actions))
	if 玩家1.tokens[0] != null:
		检(int(玩家1.tokens[0]["num"]) == 1,
			"确认应扣 1 鲜血，实际 %d" % int(玩家1.tokens[0]["num"]))
	玩家1.additional_actions.clear()

	# ---- 场景 31f：完整响应流程 —— 队列里已有一份确认过的赤色一闪时，确认新的一份后不能再问一次 ----
	_重置战斗()
	var 血剑3: BattleRole = 血剑类.new()
	血剑3.setup(玩家1, 引擎)
	玩家1.role = 血剑3
	玩家1.additional_actions.clear()
	if 玩家1.tokens[0] != null:
		玩家1.tokens[0]["num"] = 2
	# 上一轮确认过、还没轮到的赤色一闪（已付费，所以进入时不会再扣一次）
	玩家1.add_action(GConst.ActionType.Attack, 3402, true, true,
		{"已付费": true, "in_end_response": true})
	引擎.current_id = 1
	引擎._push_action_end_hooks("p_after_attack", {"player": 1}, false, 0)
	引擎.run()
	检(引擎._await_id == 1 and int(引擎._pending_respond_id) == 3402,
		"新一份赤色一闪应作为响应选项摆出来（await=%s respond=%s）"
		% [str(引擎._await_id), str(引擎._pending_respond_id)])
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 3402, "src_id": 1, "args": [3402], "card_ids": [], "dst_ids": [],
	})
	检(玩家1.额外行动队列数据(3402, true).is_empty(),
		"确认后不应再剩未确认的赤色一闪：%s" % str(玩家1.additional_actions))
	检(int(引擎._pending_respond_id) != 3402,
		"确认后不应再弹一次赤色一闪询问，实际询问号 %s" % str(引擎._pending_respond_id))
	玩家1.additional_actions.clear()

	# ---- 场景 31g：取消响应后，基础效果（迅捷赐福）的「占位」额外行动也要撤回 ----
	# 祈祷师在攻击结束钩子里把 1601 的行动提前垫进队列；玩家没确认就取消，
	# 这份占位不能留到额外行动阶段 —— 否则会冒出一颗红色「迅捷赐福」按钮，
	# 看着像又弹了一次响应，实际是玩家从没确认过的行动。
	_重置战斗()
	玩家1.role = null
	var 赐福牌: GCard = null
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.has_skill_id(GConst.技能_迅捷赐福):
			赐福牌 = c
			break
	if 赐福牌 != null:
		检(引擎.add_basic_effect(1, 赐福牌.id, 2, GConst.技能_迅捷赐福) == GConst.GE_SUCCESS,
			"迅捷赐福应能贴上")
		玩家1.add_action(GConst.ActionType.Attack, GConst.技能_迅捷赐福)
		引擎._push_action_end_hooks("p_after_attack", {"player": 1}, false, 0)
		引擎.run()
		检(not 玩家1.additional_actions.is_empty(), "钩子应把迅捷赐福的行动垫进队列")
		var 赐福问: Array = 引擎._最后询问.get(1, {}).get("commands", [])
		检(not 赐福问.is_empty(), "攻击结束响应里应摆出迅捷赐福选项")
		引擎.on_message(1, GConst.Msg.Respond, {
			"respond_id": GConst.技能_迅捷赐福, "src_id": 1,
			"args": [], "card_ids": [], "dst_ids": [],
		})
		检(玩家1.additional_actions.is_empty(),
			"取消响应后迅捷赐福的占位行动应被撤回：%s" % str(玩家1.additional_actions))
		检(玩家1.basic_effects.size() == 1,
			"取消不应移除迅捷赐福牌本身：%s" % str(玩家1.basic_effects))

	# ---- 场景 32：聚合器仍然列出不可发动的角色技能，只是置灰 ----
	_重置战斗()
	var 剑圣灰: BattleRole = 剑圣类.new()
	剑圣灰.setup(玩家1, 引擎)
	玩家1.role = 剑圣灰
	玩家1.set_gem(0)
	玩家1.set_crystal(0)
	引擎.current_id = 1
	引擎._push_action_end_hooks("p_after_attack", {"player": 1}, false, 0)
	引擎.run()
	var 灰问: Array = 引擎._最后询问.get(1, {}).get("commands", [])
	var 灰选: Array = (灰问[0] as Dictionary).get("args", []) if not 灰问.is_empty() else []
	var 灰可用: Array = (灰问[0] as Dictionary).get("option_enabled", []) if not 灰问.is_empty() else []
	var 剑影位: int = 灰选.slice(4).find(105)
	检(剑影位 >= 0, "没有能量时剑影仍应列在聚合器里：%s" % str(灰选))
	if 剑影位 >= 0 and 剑影位 < 灰可用.size():
		检(not bool(灰可用[剑影位]), "没有能量时剑影选项应置灰不可发动")

	# ---- 场景 33：修罗连斩 + 迅捷赐福两个额外攻击行动都要出现在技能栏 ----
	_重置战斗()
	var 双刀类 = preload("res://scripts/battle/roles/role_mojian.gd")
	var 双刀: BattleRole = 双刀类.new()
	双刀.setup(玩家1, 引擎)
	玩家1.role = 双刀
	玩家1.hand_cards.append(攻击牌甲.id)
	var 双刀迅捷: GCard = null
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.has_skill_id(GConst.技能_迅捷赐福):
			双刀迅捷 = c
			break
	if 双刀迅捷 != null:
		检(引擎.add_basic_effect(1, 双刀迅捷.id, 2, GConst.技能_迅捷赐福) == GConst.GE_SUCCESS,
			"双刀测试的迅捷赐福应贴上")
		引擎.current_id = 1
		引擎._push_action_end_hooks("p_after_attack", {"player": 1}, false, 0)
		引擎.run()
		引擎.on_message(1, GConst.Msg.Respond, {
			"respond_id": 901, "src_id": 1, "args": [901], "card_ids": [], "dst_ids": [],
		})
		引擎.run()
		引擎.on_message(1, GConst.Msg.Respond, {
			"respond_id": GConst.技能_迅捷赐福, "src_id": 1,
			"args": [GConst.技能_迅捷赐福], "card_ids": [], "dst_ids": [],
		})
		引擎.run()
		var 双刀命令: Array = 引擎._最后行动命令.get(1, [])
		var 双刀额外数: int = 0
		for c: Dictionary in 双刀命令:
			if bool(c.get("is_extra", false)) \
					or int(c.get("respond_id", 0)) == GConst.ActionType.ChooseExtraAction:
				双刀额外数 += 1
		检(双刀额外数 == 2,
			"修罗连斩 + 迅捷赐福后技能栏应显示两个额外攻击行动，实际 %d：%s"
			% [双刀额外数, str(双刀命令)])

	# ---- 场景 34：封印师 406 + 迅捷赐福 两份额外攻击，提交攻击不应被驳回 ----
	_重置战斗()
	var 封印类 = preload("res://scripts/battle/roles/role_fengyin.gd")
	var 封印: BattleRole = 封印类.new()
	封印.setup(玩家1, 引擎)
	玩家1.role = 封印
	玩家1.hand_cards.append(攻击牌甲.id)
	玩家1.add_action(GConst.ActionType.Attack, 406, true, true)
	玩家1.add_action(GConst.ActionType.Attack, GConst.技能_迅捷赐福, true, true)
	引擎.current_id = 1
	引擎.push(BattleEngine.SAdditionalAction.new())
	引擎.run()
	var 封印前: int = 引擎.行动额外来源
	引擎.on_message(1, GConst.Msg.Action, {
		"action_type": GConst.ActionType.Attack,
		"card_ids": [攻击牌甲.id], "dst_ids": [3],
		"args": [封印前],
	})
	检(引擎._await_kind == GConst.Msg.Respond,
		"封印师 406/1601 的额外攻击提交后应进入应战询问，实际等待 %s/%s"
		% [str(引擎._await_id), str(引擎._await_kind)])

	# ---- 场景 35：封印师 406 当前、切到 1601 后提交攻击也不应被驳回 ----
	_重置战斗()
	var 封印二: BattleRole = 封印类.new()
	封印二.setup(玩家1, 引擎)
	玩家1.role = 封印二
	玩家1.hand_cards.append(攻击牌甲.id)
	玩家1.add_action(GConst.ActionType.Attack, 406, true, true)
	玩家1.add_action(GConst.ActionType.Attack, GConst.技能_迅捷赐福, true, true)
	引擎.current_id = 1
	引擎.push(BattleEngine.SAdditionalAction.new())
	引擎.run()
	引擎.on_message(1, GConst.Msg.Action, {
		"action_type": GConst.ActionType.Attack,
		"card_ids": [攻击牌甲.id], "dst_ids": [3],
		"args": [GConst.技能_迅捷赐福],
	})
	检(引擎._await_kind == GConst.Msg.Respond,
		"封印师从 406 切到 1601 后提交攻击应进入应战，实际等待 %s/%s"
		% [str(引擎._await_id), str(引擎._await_kind)])

	# ---- 场景 36：封印师真实法术牌结束后，406 + 1601 的攻击提交 ----
	_重置战斗()
	var 封印三: BattleRole = 封印类.new()
	封印三.setup(玩家1, 引擎)
	玩家1.role = 封印三
	玩家1.hand_cards = [攻击牌甲.id]
	var 封印法术: GCard = null
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.is_magic() and not c.is_attack():
			封印法术 = c
			break
	var 封印赐福: GCard = null
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.has_skill_id(GConst.技能_迅捷赐福):
			封印赐福 = c
			break
	if 封印法术 != null and 封印赐福 != null:
		玩家1.hand_cards.append(封印法术.id)
		检(引擎.add_basic_effect(1, 封印赐福.id, 2, GConst.技能_迅捷赐福) == GConst.GE_SUCCESS,
			"封印师测试的迅捷赐福应贴上")
		引擎.current_id = 1
		引擎.resolve_action(GConst.ActionType.Magic, {
			"card_ids": [封印法术.id], "dst_ids": [2], "args": [],
		})
		引擎.run()
		# 法术结束后应同时有 406 与 1601；选 1601 后进入额外攻击
		if not 引擎._最后询问.get(1, {}).get("commands", []).is_empty():
			引擎.on_message(1, GConst.Msg.Respond, {
				"respond_id": GConst.技能_迅捷赐福, "src_id": 1,
				"args": [GConst.技能_迅捷赐福], "card_ids": [], "dst_ids": [],
			})
			引擎.run()
		if 引擎._await_kind == GConst.Msg.Action:
			引擎.on_message(1, GConst.Msg.Action, {
				"action_type": GConst.ActionType.Attack,
				"card_ids": [攻击牌甲.id], "dst_ids": [3], "args": [406],
			})
		检(引擎._await_kind == GConst.Msg.Respond,
			"封印师真实法术后 406 的攻击应进入应战，实际等待 %s/%s"
			% [str(引擎._await_id), str(引擎._await_kind)])

	# ---- 场景 37：法术结束响应里点红色额外攻击按钮，应直接进入攻击而不是报无效 ----
	_重置战斗()
	var 封印四: BattleRole = 封印类.new()
	封印四.setup(玩家1, 引擎)
	玩家1.role = 封印四
	玩家1.hand_cards = [攻击牌甲.id]
	var 封印赐福二: GCard = null
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.has_skill_id(GConst.技能_迅捷赐福):
			封印赐福二 = c
			break
	if 封印赐福二 != null:
		检(引擎.add_basic_effect(1, 封印赐福二.id, 2, GConst.技能_迅捷赐福) == GConst.GE_SUCCESS,
			"封印师快捷额外攻击测试的迅捷赐福应贴上")
		引擎.current_id = 1
		引擎._push_action_end_hooks("p_after_magic", {"player": 1, "kind": "magic"}, false, 0)
		引擎.run()
		引擎.on_message(1, GConst.Msg.Respond, {
			"respond_id": GConst.RespondType.ChooseExtraAction, "src_id": 1,
			"args": [406, 攻击牌甲.id, 3], "card_ids": [攻击牌甲.id], "dst_ids": [3],
		})
		引擎.run()
		检(引擎._await_kind == GConst.Msg.Respond and 引擎.首选额外行动 == -1,
			"法术结束响应点红色额外攻击后应进入应战，实际等待 %s/%s，首选=%d，额外来源=%d，额外=%s"
			% [str(引擎._await_id), str(引擎._await_kind), 引擎.首选额外行动,
			引擎.行动额外来源, str(引擎.行动额外)])

	# ---- 场景 38：正在打 901 / 103 / 105 自己那一刀时，不在自己的攻击结束响应里再次出现 ----
	_重置战斗()
	var 自查魔剑类 = preload("res://scripts/battle/roles/role_mojian.gd")
	var 自查魔剑: BattleRole = 自查魔剑类.new()
	自查魔剑.setup(玩家1, 引擎)
	引擎.current_id = 1
	引擎.行动额外 = true
	引擎.行动额外来源 = 901
	自查魔剑.active_xiu_luo_lian_zhan = true
	检(自查魔剑.action_end_options({}).is_empty(),
		"修罗连斩自己的攻击结束时不应再次提供修罗连斩")
	_重置战斗()
	var 自查剑圣类 = preload("res://scripts/battle/roles/role_jiansheng.gd")
	var 自查剑圣: BattleRole = 自查剑圣类.new()
	自查剑圣.setup(玩家1, 引擎)
	引擎.current_id = 1
	引擎.行动额外 = true
	引擎.行动额外来源 = 103
	自查剑圣.active_lian_xu_ji = true
	检(自查剑圣.action_end_options({}).is_empty(),
		"风怒追击自己的攻击结束时不应再次提供风怒追击")

	# ---- 场景 39：聚合器收到不在选项表里的 cause，应回错误并继续询问 ----
	_重置战斗()
	var 非法聚合类 = preload("res://scripts/battle/roles/role_mojian.gd")
	var 非法聚合: BattleRole = 非法聚合类.new()
	非法聚合.setup(玩家1, 引擎)
	玩家1.role = 非法聚合
	玩家1.hand_cards.append(攻击牌甲.id)
	var 非法迅捷: GCard = null
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.has_skill_id(GConst.技能_迅捷赐福):
			非法迅捷 = c
			break
	if 非法迅捷 != null:
		检(引擎.add_basic_effect(1, 非法迅捷.id, 2, GConst.技能_迅捷赐福) == GConst.GE_SUCCESS,
			"非法 cause 测试的迅捷赐福应贴上")
		引擎.current_id = 1
		引擎._push_action_end_hooks("p_after_attack", {"player": 1}, false, 0)
		引擎.run()
		引擎.on_message(1, GConst.Msg.Respond, {
			"respond_id": 901, "src_id": 1, "args": [999], "card_ids": [], "dst_ids": [],
		})
		var 非法再问: Array = 引擎._最后询问.get(1, {}).get("commands", [])
		var 非法选项: Array = (非法再问[0] as Dictionary).get("args", []) \
			if not 非法再问.is_empty() else []
		检(引擎._await_kind == GConst.Msg.Respond
			and 非法选项.slice(4).has(901) and 非法选项.slice(4).has(GConst.技能_迅捷赐福),
			"非法 cause 后应继续询问原选项：等待 %s/%s，选项 %s"
			% [str(引擎._await_id), str(引擎._await_kind), str(非法选项)])

	# ---- 场景 40：101/103/105/1601 各种先后顺序下，剑影只能进入一次 ----
	var 顺序表: Array = [
		[101, 103, 105, 1601], [101, 105, 103, 1601], [103, 101, 105, 1601],
		[103, 105, 101, 1601], [105, 101, 103, 1601], [105, 103, 101, 1601],
		[1601, 101, 103, 105], [1601, 105, 103, 101], [101, 1601, 105, 103],
		[103, 1601, 105, 101], [105, 1601, 101, 103], [105, 1601, 103, 101],
	]
	var 剑影次数: int = 0
	for 顺序: Array in 顺序表:
		_重置战斗()
		var 矩阵剑圣: BattleRole = 剑圣类.new()
		矩阵剑圣.setup(玩家1, 引擎)
		玩家1.role = 矩阵剑圣
		玩家1.set_gem(1)
		玩家1.hand_cards.append(攻击牌甲.id)
		引擎.current_id = 1
		for cause: int in 顺序:
			引擎.行动额外 = true
			引擎.行动额外来源 = cause
			if cause == 105:
				矩阵剑圣.resolve_action_end_option(105, {}, {})
				剑影次数 += 1
				矩阵剑圣.v_attack(攻击牌甲.id, 3, {3: 引擎.p(3)})
				if 矩阵剑圣.action_end_options({}).any(func(o: Dictionary) -> bool:
						return int(o.get("value", 0)) == 105):
					检(false, "剑影用过后仍出现在选项里，顺序 %s" % str(顺序))
				矩阵剑圣.p_action_end({"is_extra": true, "extra_cause": 105})
			elif cause == 103:
				矩阵剑圣.v_attack(攻击牌甲.id, 3, {3: 引擎.p(3)})
			elif cause == 101:
				矩阵剑圣.v_attack(攻击牌甲.id, 3, {3: 引擎.p(3)})
			else:
				矩阵剑圣.v_attack(攻击牌甲.id, 3, {3: 引擎.p(3)})
		检(矩阵剑圣.used_jian_ying, "顺序 %s 后剑影应已标记用过" % str(顺序))
	检(剑影次数 >= 1, "矩阵至少应尝试进入一次剑影")

	# ---- 场景 19：疾风技 + 剑影 + 风怒追击 + 迅捷赐福 都在队列时，1601 也应作为可切换项 ----
	_重置战斗()
	var 剑圣九: BattleRole = 剑圣类.new()
	剑圣九.setup(玩家1, 引擎)
	玩家1.role = 剑圣九
	玩家1.add_action(GConst.ActionType.Attack, 101, true, true)
	玩家1.add_action(GConst.ActionType.Attack, 105, true, true)
	玩家1.add_action(GConst.ActionType.Attack, 103, true, true)
	玩家1.add_action(GConst.ActionType.Attack, GConst.技能_迅捷赐福, true)
	引擎.push(BattleEngine.SAdditionalAction.new())
	引擎.run()
	var 多命令表: Array = 引擎._最后询问.get(1, {}).get("commands", [])
	var 有迅捷切换: bool = false
	for c: Dictionary in 多命令表:
		if int(c.get("respond_id", 0)) == GConst.ActionType.ChooseExtraAction \
				and (c.get("args", []) as Array).has(GConst.技能_迅捷赐福):
			有迅捷切换 = true
			break
	检(有迅捷切换, "疾风技/剑影/风怒追击/迅捷赐福同队列时，迅捷赐福应作为切换项显示：%s"
		% str(多命令表))

	# ---- 场景 18：迅捷赐福由「持有者面前的赐福」在攻击结束前补授予，选中后移除赐福 ----
	_重置战斗()
	var 迅捷牌: GCard = null
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.has_skill_id(GConst.技能_迅捷赐福):
			迅捷牌 = c
			break
	if 迅捷牌 != null:
		var 剑圣八: BattleRole = 剑圣类.new()
		剑圣八.setup(玩家1, 引擎)
		玩家1.role = 剑圣八
		var 祈祷类 = preload("res://scripts/battle/roles/role_qidao.gd")
		var 祈祷: BattleRole = 祈祷类.new()
		祈祷.setup(引擎.p(2), 引擎)
		引擎.p(2).role = 祈祷
		玩家1.hand_cards.append(攻击牌甲.id)
		玩家1.add_action(GConst.ActionType.Attack, 101, true, true)
		检(引擎.add_basic_effect(1, 迅捷牌.id, 2, GConst.技能_迅捷赐福) == GConst.GE_SUCCESS,
			"迅捷赐福应能贴到风之剑圣面前")
		引擎.push(BattleEngine.STurnEnd.new())
		引擎.push(BattleEngine.SHook.new("p_action_end", {"player": 1}, []))
		引擎.push(BattleEngine.SHook.new("p_after_attack", {"player": 1}, []))
		引擎.run()
		var 赐福问: Array = 引擎._最后询问.get(1, {}).get("commands", [])
		var 赐福选项: Array = (赐福问[0] as Dictionary).get("args", []) if not 赐福问.is_empty() else []
		检(赐福选项.size() >= 6 and 赐福选项.slice(4).has(GConst.技能_迅捷赐福),
			"有迅捷赐福时攻击结束选项应包含它：%s" % str(赐福选项))
		引擎.on_message(1, GConst.Msg.Respond, {
			"respond_id": 103, "src_id": 1, "args": [GConst.技能_迅捷赐福],
			"card_ids": [], "dst_ids": [],
		})
		检(玩家1.basic_effects.is_empty(), "确认迅捷赐福后应立即移除赐福牌")
		var 赐福剩余问: Array = 引擎._最后询问.get(1, {}).get("commands", [])
		var 赐福剩余选项: Array = (赐福剩余问[0] as Dictionary).get("args", []) \
			if not 赐福剩余问.is_empty() else []
		检(赐福剩余选项.slice(4).has(103) and not 赐福剩余选项.slice(4).has(GConst.技能_迅捷赐福),
			"确认迅捷赐福后应保留剩余响应选项：%s" % str(赐福剩余选项))
		检(bool((赐福剩余问[0] as Dictionary).get("has_extra_options", false)),
			"剩余响应应被标记为可放弃的额外行动询问")
		检(((赐福剩余问[0] as Dictionary).get("extra_attack_causes", []) as Array)\
			.has(GConst.技能_迅捷赐福),
			"确认迅捷赐福后新获得的攻击行动应作为通用快捷按钮出现在剩余响应里")
		引擎.on_message(1, GConst.Msg.Respond, {
			"respond_id": 103, "src_id": 1, "args": [], "card_ids": [], "dst_ids": [],
		})
		检(玩家1.additional_actions.is_empty(), "取消后队列里的额外攻击行动应被清空：%s"
			% str(玩家1.additional_actions))
		检(引擎.行动额外来源 != GConst.技能_迅捷赐福,
			"取消后不应再进入迅捷赐福的额外攻击：%d" % 引擎.行动额外来源)
	else:
		检(false, "卡库里找不到带迅捷赐福的牌")

	# ---- 场景 13：攻击结束响应里点红色快捷按钮，跳过响应钩子后要接到额外行动 ----
	_重置战斗()
	var 剑圣四: BattleRole = 剑圣类.new()
	剑圣四.setup(玩家1, 引擎)
	玩家1.role = 剑圣四
	玩家1.set_gem(1)
	if 风击三 != null:
		玩家1.hand_cards.append(风击三.id)
		玩家1.add_action(GConst.ActionType.Attack, 103, true, true)
		var 攻击结束钩: BattleEngine.SHook = BattleEngine.SHook.new(
			"p_after_attack", {"player": 1}, [BattleEngine.STurnEnd.new()])
		攻击结束钩._started = true
		引擎.push(攻击结束钩)
		引擎._await_id = 1
		引擎._await_kind = GConst.Msg.Respond
		引擎._选择额外攻击响应(1, {
			"respond_id": GConst.RespondType.ChooseExtraAction, "src_id": 1,
			"args": [103], "card_ids": [风击三.id], "dst_ids": [3],
			})
		检(引擎.行动额外来源 == 103 and 引擎._await_id == 3,
			"响应快捷按钮应跳过响应并直接发起 103 攻击（来源 %d / 等待 %s）"
			% [引擎.行动额外来源, str(引擎._await_id)])

	# ---- 场景 41：额外行动按「获得那一刻」的先后排列，赐福贴牌时不占号 ----
	# 回归：疾风技给的行动 → 响应里确认剑影 → 确认迅捷赐福 → 用掉疾风那个行动后又打出一张疾风技。
	# 迅捷赐福可能几个回合前就贴在身上，但它授予的行动是「第三个才获得」的：
	# 不能因为赐福贴得早就排到剑影前面，也不能被客户端挪到之后获得的行动后面。
	_重置战斗()
	var 排列剑圣: BattleRole = 剑圣类.new()
	排列剑圣.setup(玩家1, 引擎)
	玩家1.role = 排列剑圣
	玩家1.set_gem(1)
	var 排列迅捷牌: GCard = null
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.has_skill_id(GConst.技能_迅捷赐福):
			排列迅捷牌 = c
			break
	检(排列迅捷牌 != null, "卡库里找不到带迅捷赐福的牌")
	if 排列迅捷牌 != null:
		玩家1.hand_cards.append(排列迅捷牌.id)
		引擎.add_basic_effect(1, 排列迅捷牌.id, 2, GConst.技能_迅捷赐福)
		引擎.run()
		玩家1.add_action(GConst.ActionType.Attack, 101, true, true)
		检(_额外原因(玩家1) == [101], "疾风技给的行动应先入队：%s" % str(_额外原因(玩家1)))
		# 风怒追击排除掉，只看剑影 + 迅捷赐福这两个响应项
		排列剑圣.used_lian_xu_ji = true
		引擎._push_action_end_hooks("p_after_attack", {"player": 1}, false, 0)
		引擎.run()
		引擎.on_message(1, GConst.Msg.Respond, {
			"respond_id": 105, "src_id": 1, "args": [105], "card_ids": [], "dst_ids": [],
			})
		检(_额外原因(玩家1) == [101, 105],
			"确认剑影后队列应为 101 / 105：%s" % str(_额外原因(玩家1)))
		引擎.on_message(1, GConst.Msg.Respond, {
			"respond_id": GConst.技能_迅捷赐福, "src_id": 1,
			"args": [GConst.技能_迅捷赐福], "card_ids": [], "dst_ids": [],
			})
		检(_额外原因(玩家1) == [101, 105, GConst.技能_迅捷赐福],
			"迅捷赐福授予的行动应排在最后（确认那一刻才获得）：%s" % str(_额外原因(玩家1)))
		检(_额外序号递增(玩家1), "队列顺序应与获取序号一致：%s" % str(玩家1.additional_actions))
		# 进入疾风技那份额外行动，再打一张疾风技 → 新行动必须排在迅捷赐福之后
		引擎._states.clear()
		引擎._清空等待()
		引擎.push(BattleEngine.SAdditionalAction.new())
		引擎.run()
		检(引擎.行动额外来源 == 101, "应先进入疾风技的额外行动：%d" % 引擎.行动额外来源)
		玩家1.add_action(GConst.ActionType.Attack, 101, true, true)
		检(_额外原因(玩家1) == [105, GConst.技能_迅捷赐福, 101],
			"新获得的疾风技行动应排在已获得的迅捷赐福之后：%s" % str(_额外原因(玩家1)))
		检(_额外序号递增(玩家1), "重新入队后获取序号仍应递增：%s" % str(玩家1.additional_actions))
		# 技能栏（额外行动阶段）与响应快捷按钮必须用同一份有序列表：
		# 服务端把这排行动按获取序号整份下发，客户端照着摆，不自己排序。
		var 栏: Array = 引擎.action_commands(1, GConst.ActionType.Attack, true, true, false, 101)
		var 栏号: Array = []
		if not 栏.is_empty():
			for c: Variant in (栏[0] as Dictionary).get("extra_attack_causes", []):
				栏号.append(int(c))
		var 队号: Array = []
		for a: Dictionary in 玩家1.additional_actions:
			队号.append(int(a.get("cause", 0)))
		# 技能栏把「当前这份」也排在列表里：当前是 101，队列里是 [105, 1601, 101新]
		队号.push_front(101)
		检(栏号 == 队号,
			"技能栏下发的顺序应与队列（含当前行动）一致：%s / %s" % [str(栏号), str(队号)])

	# ---- 场景 43：切换额外攻击时没用掉的那份退回原位，新获得的仍排在最后 ----
	# 客户端在额外行动阶段点了另一份行动再出手（args 带选中的 cause）：服务端换队，
	# 当前这份退回队列（保留原获取序号＝还在最前面），剑影被消耗；这一刀打出的疾风技再给的行动排最后。
	_重置战斗()
	var 切剑圣: BattleRole = 剑圣类.new()
	切剑圣.setup(玩家1, 引擎)
	玩家1.role = 切剑圣
	玩家1.set_gem(1)
	玩家1.hand_cards = [攻击牌甲.id, 攻击牌乙.id]
	玩家1.add_action(GConst.ActionType.Attack, 101, true, true)
	切剑圣.resolve_action_end_option(105, {}, {})
	玩家1.add_action(GConst.ActionType.Attack, GConst.技能_迅捷赐福, true, true)
	检(_额外原因(玩家1) == [101, 105, GConst.技能_迅捷赐福],
		"三份额外攻击行动应按获取顺序入队：%s" % str(_额外原因(玩家1)))
	引擎.push(BattleEngine.SAdditionalAction.new())
	引擎.run()
	检(引擎.行动额外来源 == 101, "应先进入疾风技那份：%d" % 引擎.行动额外来源)
	引擎.resolve_action(GConst.ActionType.Attack, {
		"card_ids": [攻击牌甲.id], "dst_ids": [3], "args": [105]})
	引擎.run()
	检(_额外原因(玩家1) == [101, GConst.技能_迅捷赐福],
		"切到剑影出手后：剑影被消耗，没用掉的疾风技退回原位、迅捷赐福仍在：%s"
		% str(_额外原因(玩家1)))
	检(int(玩家1.额外行动数据(101).get("order", 0)) == 1,
		"退回队列的那份应保留原获取序号（先获得的在前）")
	# 这一刀打出的疾风技再获得一份攻击行动：必须排在最后，而不是插到前面
	玩家1.add_action(GConst.ActionType.Attack, 101, true, true)
	检(_额外原因(玩家1) == [101, GConst.技能_迅捷赐福, 101],
		"新获得的疾风技行动应排最后：%s" % str(_额外原因(玩家1)))
	检(_额外序号递增(玩家1), "队列顺序应与获取序号一致：%s" % str(玩家1.additional_actions))

	# ---- 场景 42：响应里点红色快捷按钮「剑影」要真进剑影，校验不得有副作用 ----
	# 回归：v_attack 曾在「预校验」里就扣能量、把剑影标成「本回合已用」，
	# 结果这份行动被预校验判成「不可发动」—— 点了剑影却进了疾风技，
	# 剑影留在队列里，之后弹出一张置灰的「剑影」额外行动询问、只能点取消。
	_重置战斗()
	var 快捷剑圣: BattleRole = 剑圣类.new()
	快捷剑圣.setup(玩家1, 引擎)
	玩家1.role = 快捷剑圣
	玩家1.set_gem(1)
	玩家1.hand_cards = [攻击牌甲.id]
	快捷剑圣.resolve_action_end_option(105, {}, {})
	玩家1.add_action(GConst.ActionType.Attack, 101, true, true)
	检(玩家1.get_energy() == 0, "确认剑影时应已支付 1 能量，实际 %d" % 玩家1.get_energy())
	检(not 快捷剑圣.used_jian_ying, "确认剑影时还不能记成「本回合已用」")
	引擎._states.clear()
	引擎._清空等待()
	引擎._await_id = 1
	引擎._await_kind = GConst.Msg.Respond
	引擎._选择额外攻击响应(1, {
		"respond_id": GConst.RespondType.ChooseExtraAction, "src_id": 1,
		"args": [105], "card_ids": [攻击牌甲.id], "dst_ids": [3]})
	检(not 快捷剑圣.used_jian_ying,
		"快捷按钮的预校验不能把剑影标成本回合已用（否则这份行动当场不可发动）")
	检(引擎.额外行动在队列(玩家1, 105), "预校验后剑影仍应留在队列里")
	检(引擎.首选额外行动 == 105, "点剑影快捷按钮后应记下首选 105：%d" % 引擎.首选额外行动)
	引擎._states.clear()
	引擎._清空等待()
	引擎.push(BattleEngine.SAdditionalAction.new())
	引擎.run()
	检(引擎.行动额外来源 == 105 and 引擎._await_id == 3,
		"点剑影快捷按钮后应直接发起剑影的攻击（来源 %s / 等待 %s）"
		% [str(引擎.行动额外来源), str(引擎._await_id)])
	检(_额外原因(玩家1) == [101], "进入剑影后队列应只剩疾风技那份：%s" % str(_额外原因(玩家1)))
	检(玩家1.get_energy() == 0, "剑影只应付一次能量，实际剩 %d" % 玩家1.get_energy())
	引擎.on_message(3, GConst.Msg.Respond, {
		"respond_id": GConst.RespondType.ReplyAttack, "src_id": 3,
		"args": [GConst.Reattack.GiveUp], "card_ids": [], "dst_ids": [],
	})
	引擎.run()
	检(快捷剑圣.used_jian_ying, "剑影这份攻击行动结束后才应记「本回合已用」")

	# ---- 场景 44：响应快捷按钮与技能栏必须同序（获取顺序 ≠ 技能号顺序）----
	# 回归：客户端曾按 extra_order 自己排序，而该字段没进协议（永远是 0），退回按技能号排，
	# 于是「响应里 105/1601/101，进去后 101/105/1601」。现在顺序只有引擎 额外行动序列 一处，
	# 两个界面都照服务端下发的同一份列表摆。
	_重置战斗()
	var 同序剑圣: BattleRole = 剑圣类.new()
	同序剑圣.setup(玩家1, 引擎)
	玩家1.role = 同序剑圣
	玩家1.set_gem(1)
	玩家1.hand_cards = []
	引擎.current_id = 1
	# 获取顺序：剑影(2) → 迅捷赐福(3) → 新的疾风技(4)；按技能号排会是 101/105/1601
	同序剑圣.resolve_action_end_option(105, {}, {})
	玩家1.add_action(GConst.ActionType.Attack, GConst.技能_迅捷赐福, true, true)
	玩家1.add_action(GConst.ActionType.Attack, 101, true, true)
	# 迅捷赐福真实流程里是「确认后」才入队，这里手动入队，补一个已确认标记才会出现在快捷按钮里
	引擎._基础效果额外行动已确认[GConst.技能_迅捷赐福] = true
	var 同序队列: Array = []
	for a: Dictionary in 玩家1.additional_actions:
		同序队列.append(int(a.get("cause", 0)))
	检(同序队列 == [105, GConst.技能_迅捷赐福, 101],
		"队列应按获取顺序：%s" % str(同序队列))
	# ① 行动结束响应（没有当前行动）：快捷按钮列表 ＝ 队列顺序
	引擎._清空等待()
	引擎.ask_skill(1, 103, 0, 0, GConst.CardSource.Hand, [], 0, "", [], true,
		"", [], 0, 0, false, [], true, -1, 0, true)
	var 同序快捷: Array = []
	var 同序命令: Array = 引擎._最后询问.get(1, {}).get("commands", [])
	if not 同序命令.is_empty():
		for c: Variant in (同序命令[0] as Dictionary).get("extra_attack_causes", []):
			同序快捷.append(int(c))
	检(同序快捷 == 同序队列, "响应快捷按钮应等于队列顺序：%s / %s"
		% [str(同序快捷), str(同序队列)])
	# ② 额外行动阶段（当前＝中间那份迅捷赐福）：技能栏列表 ＝ 队列顺序、当前插在原位
	引擎._清空等待()
	引擎.当前额外行动数据 = {}
	for a: Dictionary in 玩家1.additional_actions:
		if int(a.get("cause", 0)) == GConst.技能_迅捷赐福:
			引擎.当前额外行动数据 = a
			玩家1.additional_actions.erase(a)
			break
	var 同序栏: Array = []
	var 同序行动: Array = 引擎.action_commands(1, GConst.ActionType.Attack, true, true, false,
		GConst.技能_迅捷赐福)
	if not 同序行动.is_empty():
		for c: Variant in (同序行动[0] as Dictionary).get("extra_attack_causes", []):
			同序栏.append(int(c))
	检(同序栏 == 同序队列, "技能栏下发的顺序应与响应一致（当前插在原位）：%s / %s"
		% [str(同序栏), str(同序队列)])

	# ---- 场景 45：同一个技能挂两份额外行动时，选项按唯一 ID 认人 ----
	# 回归：选项 / 快捷按钮以前按 cause 认，连续两张【疾风技】会一起点亮、还会进错份。
	_重置战斗()
	var 双份剑圣: BattleRole = 剑圣类.new()
	双份剑圣.setup(玩家1, 引擎)
	玩家1.role = 双份剑圣
	玩家1.set_gem(1)
	玩家1.hand_cards = [攻击牌甲.id]
	引擎.current_id = 1
	玩家1.add_action(GConst.ActionType.Attack, 101, true, true)
	玩家1.add_action(GConst.ActionType.Attack, 101, true, true)
	检(玩家1.additional_actions.size() == 2, "应有两份疾风技行动")
	var 首份ID: int = int(玩家1.additional_actions[0].get("uid", 0))
	var 次份ID: int = int(玩家1.additional_actions[1].get("uid", 0))
	检(首份ID > 0 and 次份ID > 0 and 首份ID != 次份ID,
		"两份同名行动的唯一 ID 必须不同：%d / %d" % [首份ID, 次份ID])
	# 技能栏：两份同名行动的按钮各带自己的唯一 ID，客户端只点亮点中的那个
	引擎._清空等待()
	引擎.当前额外行动数据 = {}
	var 双栏: Array = 引擎.action_commands(1, GConst.ActionType.Attack, true, true, false, 101)
	var 双栏ID: Array = (双栏[0] as Dictionary).get("extra_attack_uids", [])
	检(双栏ID.size() == 2 and int(双栏ID[0]) != int(双栏ID[1]),
		"技能栏两份同名行动的唯一 ID 应不同：%s" % str(双栏ID))
	# 响应里点第二个快捷按钮（同一技能的两份）：服务端必须按 ID 认，不能挑第一份
	引擎._清空等待()
	引擎.首选额外行动 = -1
	引擎._await_id = 1
	引擎._await_kind = GConst.Msg.Respond
	引擎._选择额外攻击响应(1, {
		"respond_id": GConst.RespondType.ChooseExtraAction, "src_id": 1,
		"args": [次份ID], "card_ids": [攻击牌甲.id], "dst_ids": [3]})
	检(引擎.首选额外行动 == 次份ID,
		"快捷按钮必须记下点中的那一份（uid %d），实际 %d" % [次份ID, 引擎.首选额外行动])
	# 点第二个选项（提交第二份的唯一 ID）：必须进入第二份，第一份留在队列里
	引擎._清空等待()
	引擎.push(BattleEngine.SAdditionalAction.new())
	引擎.run()
	检(int(引擎.当前额外行动数据.get("uid", 0)) == 次份ID,
		"应进入点中的那一份（uid %d），实际 %d" % [次份ID,
		int(引擎.当前额外行动数据.get("uid", 0))])
	检(玩家1.additional_actions.size() == 1
		and int(玩家1.additional_actions[0].get("uid", 0)) == 首份ID,
		"没点的那一份应还在队列里：%s" % str(玩家1.additional_actions))

	# ---- 场景 46：限定系别的额外行动是「规则」，不是授予那一刻的手牌快照 ----
	# 回归：修罗连斩授予时手里没有火系攻击牌 → 白名单算成「全禁」；之后摸到的火系攻击牌
	# 在界面上被灰掉、提交也被服务端驳回。现在只写 element，白名单按「该系攻击牌」规则现算。
	_重置战斗()
	var 火牌2: GCard = null
	var 非火牌2: GCard = null
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual or not c.is_attack():
			continue
		if c.element_enum() == GConst.CardElement.Fire and 火牌2 == null:
			火牌2 = c
		elif c.element_enum() != GConst.CardElement.Fire and 非火牌2 == null:
			非火牌2 = c
	if 火牌2 != null and 非火牌2 != null:
		var 规则魔剑: BattleRole = 魔剑类.new()
		规则魔剑.setup(玩家1, 引擎)
		玩家1.role = 规则魔剑
		玩家1.set_gem(1)
		玩家1.hand_cards = [非火牌2.id]
		引擎.current_id = 1
		规则魔剑.p_after_attack({"player": 1})
		var 规则数据: Dictionary = 玩家1.额外行动数据(901)
		检(not 规则数据.is_empty(), "应获得修罗连斩那份额外攻击行动")
		# 授予之后再摸到火系攻击牌：规则照样放行（这就是用户看到的「火系攻击牌被灰掉」）
		玩家1.hand_cards = [非火牌2.id, 火牌2.id]
		var 规则白: Array = 引擎.额外行动出牌白名单(规则数据)
		检(规则白.has(火牌2.id) and not 规则白.has(非火牌2.id),
			"修罗连斩的可用牌应始终只含火系攻击牌（与授予时手牌无关）：%s" % str(规则白))
		检(引擎.校验额外行动限制(玩家1, 规则数据, GConst.ActionType.Attack,
			[火牌2.id], [3]) == GConst.GE_SUCCESS,
			"授予之后才到手的火系攻击牌也要能出")
		检(引擎.校验额外行动限制(玩家1, 规则数据, GConst.ActionType.Attack,
			[非火牌2.id], [3]) != GConst.GE_SUCCESS,
			"非火系攻击牌仍应被驳回")

	# ---- 场景 47：修罗连斩「不询问」——攻击结束后自动进入额外攻击阶段 ----
	# 体验对齐封印师【法术激荡】：攻击行动一结束就自动 +1 火系攻击行动，引擎直接进入，
	# 不再弹「是否发动修罗连斩」的响应选项；不想打就在那个阶段点「放弃行动」。
	_重置战斗()
	var 静默魔剑: BattleRole = preload("res://scripts/battle/roles/role_mojian.gd").new()
	静默魔剑.setup(玩家1, 引擎)
	玩家1.role = 静默魔剑
	玩家1.hand_cards = [攻击牌甲.id]
	引擎.current_id = 1
	引擎.行动允许 = GConst.ActionType.Any
	引擎.行动额外 = false
	引擎.行动额外来源 = 0
	引擎.resolve_action(GConst.ActionType.Attack, {
		"card_ids": [攻击牌甲.id], "dst_ids": [3], "args": []})
	引擎.run()
	检(引擎._await_id == 3 and 引擎._await_kind == GConst.Msg.Respond,
		"攻击宣告后应先等对手应战（等待 %s / %s）" % [str(引擎._await_id), str(引擎._await_kind)])
	引擎.on_message(3, GConst.Msg.Respond, {
		"respond_id": GConst.RespondType.ReplyAttack, "src_id": 3,
		"args": [GConst.Reattack.GiveUp], "card_ids": [], "dst_ids": []})
	引擎.run()
	# 没有「是否发动修罗连斩」的响应询问，应直接进入修罗连斩的额外攻击阶段
	检(引擎.行动额外 and 引擎.行动额外来源 == 901,
		"攻击结束后应直接进入修罗连斩的额外攻击阶段（额外 %s / 来源 %s）"
		% [str(引擎.行动额外), str(引擎.行动额外来源)])
	var 静默问: Array = 引擎._最后询问.get(1, {}).get("commands", [])
	var 静默首: Dictionary = 静默问[0] if not 静默问.is_empty() else {}
	检(bool(静默首.get("is_extra", false)) and int(静默首.get("extra_cause", 0)) == 901,
		"下发的应是修罗连斩那份额外行动的行动询问：%s" % str(静默首))
	检(引擎._await_kind == GConst.Msg.Action,
		"这时等的是行动询问（Action），不应再出现「是否发动」的 Respond 询问：%s"
		% str(引擎._await_kind))
	var 静默火: bool = false
	for c: Variant in (静默首.get("card_ids", []) as Array):
		var 卡: GCard = Data.get_card(int(c))
		if 卡 != null and 卡.element_enum() == GConst.CardElement.Fire:
			静默火 = true
	检(静默火, "修罗连斩的行动询问应只点亮火系攻击牌：%s" % str(静默首.get("card_ids", [])))

	# ---- 场景 48：先选行动、再出手 —— 打牌 / 技能都按 extra_uid 消耗玩家选的那份 ----
	# 回归：以前只有「出攻击牌」会换队，所以额外行动阶段「先点行动、再点技能」永远消耗
	# 服务端当前那一份。现在 Action 带 extra_uid，任何行动提交都先换到玩家选中的那份再判合法性。
	_重置战斗()
	玩家1.role = 角色
	玩家1.hand_cards = [攻击牌甲.id]
	引擎.current_id = 1
	# 当前这份：攻击或法术都能做（模拟【偷天换日】）；队列里另有一份只能攻击的
	var 万能数据: Dictionary = {
		"allow_action": GConst.ActionType.AttackMagic, "cause": 9001, "direct": true,
		"skip_notice": true, "order": 玩家1.额外行动新序号(), "uid": 玩家1.额外行动新ID(),
		"cards": [], "targets": [], "element": 0, "card_fate": 0,
		"switchable": true, "in_end_response": false,
	}
	玩家1.add_action(GConst.ActionType.Attack, 9002, true, true)
	var 万能阶段: BattleEngine.SActionPhase = BattleEngine.SActionPhase.new(
		GConst.ActionType.AttackMagic, true, true, false, 9001)
	万能阶段.额外数据 = 万能数据
	引擎.push(万能阶段)
	引擎.run()
	var 攻份ID: int = int(玩家1.额外行动数据(9002).get("uid", 0))
	检(攻份ID > 0, "队列里那份额外行动应有唯一 ID")
	# ① 只能攻击的那份不能被法术消耗（换队要按这份行动自己放行的种类判）
	检(not 引擎._切换额外行动(玩家1, 攻份ID, GConst.ActionType.Magic),
		"只能攻击的额外行动不应能被法术消耗")
	检(引擎.行动额外来源 == 9001, "换队失败后当前行动不应改变：%d" % 引擎.行动额外来源)
	# ② 带 extra_uid 出攻击牌（技能行动同一条路）：消耗的是选中的那份，原当前那份退回队列
	引擎.resolve_action(GConst.ActionType.Attack, {
		"card_ids": [攻击牌甲.id], "dst_ids": [3], "args": [], "extra_uid": 攻份ID})
	引擎.run()
	检(引擎.行动额外来源 == 9002
		and int(引擎.当前额外行动数据.get("uid", 0)) == 攻份ID,
		"应换成玩家选中的那份额外行动（来源 %s / uid %s）" % [str(引擎.行动额外来源),
		str(引擎.当前额外行动数据.get("uid", 0))])
	检(_额外原因(玩家1) == [9001], "原来那份应退回队列：%s" % str(_额外原因(玩家1)))

	# ---- 场景 49：迅捷赐福的行动「确认那一刻」才取号，不沿用转发提前入队的序号 ----
	# 回归：祈祷师 / 借用角色会在行动结束钩子里先把 1601 垫进队列（发生在演员顺序里），
	# 若确认时沿用那个序号，就会排在同一回合自动获得的【修罗连斩】前面 —— 玩家看来
	# 「我确认的迅捷赐福」跑到了「自动生效的修罗连斩」前面，不像按顺序排。
	_重置战斗()
	玩家1.role = 角色
	玩家1.hand_cards = [攻击牌甲.id]
	引擎.current_id = 1
	玩家1.add_action(GConst.ActionType.Attack, GConst.技能_迅捷赐福)
	玩家1.add_action(GConst.ActionType.Attack, 901, true, true, {"element": GConst.CardElement.Fire})
	检(_额外原因(玩家1) == [GConst.技能_迅捷赐福, 901],
		"前置：转发提前入队的迅捷赐福在最前：%s" % str(_额外原因(玩家1)))
	引擎._确认基础效果额外行动(1, GConst.技能_迅捷赐福)
	检(_额外原因(玩家1) == [901, GConst.技能_迅捷赐福],
		"确认后的迅捷赐福应排在自动获得的行动之后：%s" % str(_额外原因(玩家1)))
	检(_额外序号递增(玩家1), "确认后队列仍应按获取序号递增：%s" % str(玩家1.additional_actions))

	# ---- 场景 50：攻击 / 法术两种额外行动同时挂着时，技能栏要一起下发、能互相切换 ----
	# 回归：技能栏原来只下发「放行攻击」的额外行动，元素师【元素点燃】给的额外法术行动
	# 和迅捷赐福给的额外攻击行动同时存在时，只显示法术那份（还退化成单颗兜底），无法切换。
	_重置战斗()
	玩家1.role = 角色
	玩家1.hand_cards = [攻击牌甲.id]
	引擎.current_id = 1
	# 当前：法术额外行动（模拟【元素点燃】）；队列里另有一份攻击额外行动（迅捷赐福）
	var 法术数据: Dictionary = {
		"allow_action": GConst.ActionType.Magic, "cause": 1106, "direct": true,
		"skip_notice": true, "order": 玩家1.额外行动新序号(), "uid": 玩家1.额外行动新ID(),
		"cards": [], "targets": [], "element": 0, "card_fate": 0,
		"switchable": true, "in_end_response": false,
	}
	玩家1.add_action(GConst.ActionType.Attack, GConst.技能_迅捷赐福, true, true)
	var 法阶段: BattleEngine.SActionPhase = BattleEngine.SActionPhase.new(
		GConst.ActionType.Magic, true, true, false, 1106)
	法阶段.额外数据 = 法术数据
	引擎.push(法阶段)
	引擎.run()
	var 法栏: Array = 引擎.action_commands(1, GConst.ActionType.Magic, true, true, false, 1106)
	var 法首: Dictionary = 法栏[0] if not 法栏.is_empty() else {}
	检((法首.get("extra_attack_causes", []) as Array) == [1106, GConst.技能_迅捷赐福],
		"攻击 / 法术两种额外行动应一起下发：%s" % str(法首.get("extra_attack_causes", [])))
	检((法首.get("allow_actions", []) as Array) == [GConst.ActionType.Magic, GConst.ActionType.Attack],
		"两份行动各自的放行种类要随列表下发：%s" % str(法首.get("allow_actions", [])))
	# 切到攻击那份（作为＝攻击）应成功：阶段放行种类跟着变，法术那份退回队列
	var 攻份ID3: int = int(玩家1.额外行动数据(GConst.技能_迅捷赐福).get("uid", 0))
	检(引擎._切换额外行动(玩家1, 攻份ID3, GConst.ActionType.Attack),
		"应能从法术额外行动切到攻击那份")
	检(引擎.行动允许 == GConst.ActionType.Attack,
		"切换后阶段放行种类应变成攻击：%d" % 引擎.行动允许)
	检(_额外原因(玩家1) == [1106], "法术那份应退回队列：%s" % str(_额外原因(玩家1)))

	# ---- 场景 51：秩序之印的摸 2 张必须在「法术行动结束响应」之前结算 ----
	# 回归：p_magic_skill 压入摸牌状态后返回 SUCCESS，SkillRun 会把行动结束响应
	# （神圣追击 / 迅捷赐福）压在摸牌上面，变成先弹响应、牌等响应结束才摸。
	# 压入状态后必须返回 URGENT，先结算摸牌再进行动结束响应。
	_重置战斗()
	var 女武神十一: BattleRole = preload("res://scripts/battle/roles/role_nvwushen.gd").new()
	女武神十一.setup(玩家1, 引擎)
	玩家1.role = 女武神十一
	玩家1.cross_num = 1
	玩家1.crystal = 0
	玩家1.hand_cards.clear()
	引擎.deck.pile.append(攻击牌甲.id)
	引擎.deck.pile.append(攻击牌乙.id)
	引擎.current_id = 1
	引擎.行动允许 = GConst.ActionType.Any
	引擎.phase = BattleEngine.Phase.Playing
	引擎.resolve_action(GConst.ActionType.MagicSkill, {
		"src_id": 1, "action_id": 2502, "card_ids": [], "dst_ids": [], "args": [],
	})
	引擎.run()
	检(玩家1.hand_cards.size() == 2,
		"秩序之印应先摸 2 张再弹行动结束响应（响应时手牌=%d）" % 玩家1.hand_cards.size())
	检(玩家1.cross_num == 2, "秩序之印应 +1 治疗（实际 %d）" % 玩家1.cross_num)
	检(玩家1.crystal == 1, "秩序之印应 +1 水晶（实际 %d）" % 玩家1.crystal)

	# ---- 场景 52：取消响应后，没在响应里点选的额外行动仍可用，但要在额外行动阶段付代价 ----
	# 新规则：取消只取消响应；已获得（未点选）的额外行动留到额外行动阶段，使用时再扣代价。
	_重置战斗()
	var 女武神十二: BattleRole = preload("res://scripts/battle/roles/role_nvwushen.gd").new()
	女武神十二.setup(玩家1, 引擎)
	玩家1.role = 女武神十二
	玩家1.cross_num = 2
	玩家1.hand_cards.append(攻击牌甲.id)
	玩家1.add_action(GConst.ActionType.Attack, 2501, false, false, {"in_end_response": true})
	引擎.current_id = 1
	引擎.行动允许 = GConst.ActionType.Any
	引擎.push(BattleEngine.S行动聚合器.new({"player": 1}))
	引擎.run()
	var 未点问: Array = 引擎._最后询问.get(1, {}).get("commands", [])
	var 未点选: Array = (未点问[0] as Dictionary).get("args", []) if not 未点问.is_empty() else []
	检(未点选.slice(4).has(2501), "神圣追击应出现在响应选项里：%s" % str(未点选))
	# 不点它，直接取消响应
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 0, "src_id": 1, "args": [], "card_ids": [], "dst_ids": [],
	})
	检(not 玩家1.跳过额外攻击行动, "取消响应不应标记跳过额外攻击")
	检(not 玩家1.additional_actions.is_empty(), "取消响应后额外行动应保留：%s"
		% str(玩家1.additional_actions))
	检(玩家1.cross_num == 2, "响应里没点选时不应提前扣治疗（实际 %d）" % 玩家1.cross_num)
	# 额外行动阶段：选中神圣追击 → 此时才付 -1 治疗并进入它的攻击行动
	引擎._states.clear()
	引擎._清空等待()
	引擎.current_id = 1
	引擎.push(BattleEngine.SAdditionalAction.new())
	引擎.run()
	var 额问: Array = 引擎._最后询问.get(1, {}).get("commands", [])
	var 额UID: Array = (额问[0] as Dictionary).get("option_uids", []) if not 额问.is_empty() else []
	检(引擎._await_kind == GConst.Msg.Respond and 额UID.size() == 1,
		"额外行动阶段应询问神圣追击（等待 %s / uids=%s）" % [str(引擎._await_kind), str(额UID)])
	if 额UID.size() == 1:
		引擎.on_message(1, GConst.Msg.Respond, {
			"respond_id": GConst.RespondType.AdditionalAction, "src_id": 1,
			"args": [int(额UID[0])], "card_ids": [], "dst_ids": [],
		})
		引擎.run()
		检(玩家1.cross_num == 1, "未在响应点选的额外行动应在使用（进入）时扣 1 治疗，实际 %d"
			% 玩家1.cross_num)
		检(引擎.行动额外 and 引擎.行动额外来源 == 2501,
			"付代价后应进入神圣追击的额外攻击行动（来源=%d）" % 引擎.行动额外来源)

	# ---- 场景 53：响应里点选神圣追击（扣代价）后取消响应，额外行动阶段进入时不得再扣一次 ----
	_重置战斗()
	var 女武神十三: BattleRole = preload("res://scripts/battle/roles/role_nvwushen.gd").new()
	女武神十三.setup(玩家1, 引擎)
	玩家1.role = 女武神十三
	玩家1.cross_num = 2
	玩家1.hand_cards.append(攻击牌甲.id)
	var 十三福: GCard = null
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.has_skill_id(GConst.技能_迅捷赐福):
			十三福 = c
			break
	检(引擎.add_basic_effect(1, 十三福.id, 1, GConst.技能_迅捷赐福) == GConst.GE_SUCCESS,
		"场景 53 的迅捷赐福应贴上")
	玩家1.add_action(GConst.ActionType.Attack, 2501, false, false, {"in_end_response": true})
	引擎.current_id = 1
	引擎.行动允许 = GConst.ActionType.Any
	引擎.push(BattleEngine.S行动聚合器.new({"player": 1}))
	引擎.run()
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 0, "src_id": 1, "args": [2501], "card_ids": [], "dst_ids": [],
	})
	检(玩家1.cross_num == 1, "响应里点选神圣追击应立即扣 1 治疗（实际 %d）" % 玩家1.cross_num)
	var 十三直接: bool = false
	for a: Dictionary in 玩家1.additional_actions:
		if int(a.get("cause", 0)) == 2501:
			十三直接 = bool(a.get("direct", false)) and bool(a.get("已付费", false))
	检(十三直接, "响应里点选后神圣追击应标 direct + 已付费：%s" % str(玩家1.additional_actions))
	# 还有迅捷赐福在，响应会再问一次；此时红色额外行动按钮应该已经出现（客户端置灰展示）
	var 余问: Array = 引擎._最后询问.get(1, {}).get("commands", [])
	var 余快捷: Array = (余问[0] as Dictionary).get("extra_attack_causes", []) \
		if not 余问.is_empty() else []
	检(余快捷.has(2501), "点选后神圣追击应作为（置灰的）红色额外行动按钮出现：%s" % str(余快捷))
	# 取消响应 → 额外行动阶段直接进入已付费的神圣追击，不能再扣一次治疗
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 0, "src_id": 1, "args": [], "card_ids": [], "dst_ids": [],
	})
	检(玩家1.cross_num == 1, "取消响应不应退还已付的治疗（实际 %d）" % 玩家1.cross_num)
	检(引擎.行动额外 and 引擎.行动额外来源 == 2501,
		"取消响应后应进入已获得的神圣追击额外行动（来源=%d）" % 引擎.行动额外来源)
	检(玩家1.cross_num == 1,
		"进入额外行动时不应再扣第二次治疗（实际 %d）" % 玩家1.cross_num)

	# ---- 场景 54：额外行动阶段先切到另一份再放弃，不能被驳回；剩下的那份还必须可用 ----
	# 回归：元素点燃给额外法术行动、迅捷赐福给额外攻击行动；玩家点额外攻击行动按钮再「放弃行动」时，
	# 切换要按「放弃」放行（不能因为「放弃」不是攻击/法术而判非法），否则放弃被驳回、
	# 客户端看起来就是「剩下的额外法术行动不见了」。
	_重置战斗()
	玩家1.hand_cards.append(攻击牌甲.id)
	玩家1.add_action(GConst.ActionType.Magic, 1106, true, true)
	玩家1.add_action(GConst.ActionType.Attack, 1601, true, true)
	引擎.current_id = 1
	引擎.行动允许 = GConst.ActionType.Any
	引擎.phase = BattleEngine.Phase.Playing
	引擎.push(BattleEngine.SAdditionalAction.new())
	引擎.run()
	检(引擎.行动额外 and 引擎.行动额外来源 == 1106,
		"默认应先进入先获得的额外法术行动（实际来源=%d）" % 引擎.行动额外来源)
	var 攻UID: int = int(玩家1.额外行动数据(1601).get("uid", 0))
	检(攻UID > 0, "队列里应还有额外攻击行动：%s" % str(玩家1.additional_actions))
	引擎.resolve_action(GConst.ActionType.None, {"extra_uid": 攻UID})
	检(not _有错误输入(1),
		"切到额外攻击行动后点放弃不应被驳回（否则剩下的额外法术行动会看起来消失）")
	检(引擎.行动额外 and 引擎.行动额外来源 == 1106,
		"放弃额外攻击行动后应回到剩下的额外法术行动（实际来源=%d / 等待=%s / 队列=%s）"
		% [引擎.行动额外来源, str(引擎._await_kind), str(玩家1.additional_actions)])
	检(引擎._await_kind == GConst.Msg.Action,
		"剩下的额外法术行动应重新进入可选行动阶段（等待=%s）" % str(引擎._await_kind))
