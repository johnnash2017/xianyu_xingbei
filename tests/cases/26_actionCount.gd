extends 自检用例
## F2 额外行动与行动计数：
## - 每回合「攻击 / 法术 / 特殊 / 额外」行动计数：普通行动、额外行动都记，回合开始清零；
## - 行动结束通用钩子 p_action_end（与 p_after_* 同一份上下文，带本回合第几次行动 / 是否额外）；
## - 额外行动的目标 / 出牌限制接口（extra_action_card_ids / extra_action_targets）：
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
	## 本份额外攻击行动的出牌 / 目标限制（空＝不限制）
	var 额外攻击牌: Array = []
	var 额外攻击目标: Array = []
	## 旧接口 action_card_ids（只配它时，额外行动仍按它下发白名单，兼容剑圣 103 那类实现）
	var 旧接口白名单: Array = []

	func action_card_ids(_action_type: int) -> Array:
		return 旧接口白名单

	func p_action_end(ctx: Dictionary) -> int:
		if int(ctx.get("player", -1)) != player.id:
			return SUCCESS
		行动结束记录.append(ctx.duplicate())
		if 授予额外攻击 and not bool(ctx.get("is_extra", false)) \
				and str(ctx.get("kind", "")) == "attack" and int(ctx.get("action_id", 0)) == 0:
			授予额外攻击 = false
			player.add_action(GConst.ActionType.Attack, 额外攻击来源)
		return SUCCESS

	func extra_action_card_ids(cause: int, _action_type: int) -> Array:
		if cause == 额外攻击来源:
			return 额外攻击牌
		return []

	func extra_action_targets(cause: int) -> Array:
		if cause == 额外攻击来源:
			return 额外攻击目标
		return []

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
	引擎._额外确认选项.clear()
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
	角色.旧接口白名单 = []


## 最近一条行动结束记录（没有则空字典）
func _最后记录() -> Dictionary:
	return 角色.行动结束记录[-1] if not 角色.行动结束记录.is_empty() else {}


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
	# 角色只实现旧接口 action_card_ids 时，额外行动的牌白名单退回它（剑圣 103 的现状不能回归）
	角色.额外攻击牌 = []
	角色.旧接口白名单 = [攻击牌乙.id]
	var 回退命令表: Array = 引擎.action_commands(1, GConst.ActionType.Attack, true, true, false,
		计数角色.额外攻击来源)
	var 回退命令: Dictionary = 回退命令表[0] if not 回退命令表.is_empty() else {}
	检((回退命令.get("card_ids", []) as Array) == [攻击牌乙.id],
		"额外行动没配新接口时应退回 action_card_ids：%s" % str(回退命令.get("card_ids", [])))
	角色.旧接口白名单 = []
	角色.额外攻击牌 = [攻击牌甲.id]
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
	引擎.行动允许 = GConst.ActionType.Attack
	引擎.行动可放弃 = true
	引擎.行动额外 = true
	引擎.行动额外来源 = 计数角色.额外攻击来源
	角色.额外攻击牌 = [攻击牌甲.id]
	角色.额外攻击目标 = [3]
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
	引擎.行动允许 = GConst.ActionType.Attack
	引擎.行动可放弃 = true
	引擎.行动额外 = true
	引擎.行动额外来源 = 计数角色.额外攻击来源
	角色.额外攻击牌 = [攻击牌甲.id]
	角色.额外攻击目标 = [3]
	玩家1.hand_cards.append(攻击牌甲.id)
	引擎.resolve_action(GConst.ActionType.Attack, {"card_ids": [攻击牌甲.id], "dst_ids": [4], "args": []})
	引擎.run()
	检(_有错误输入(1), "额外行动攻击了受限目标应被驳回")
	检(玩家1.hand_cards.has(攻击牌甲.id), "被驳回的额外攻击不应把牌打出去")
	检(玩家1.action_count() == 0, "目标被驳回时不应计入行动计数")
	# 2c：合法牌 + 合法目标通过并记一次额外行动
	_重置战斗()
	引擎.行动允许 = GConst.ActionType.Attack
	引擎.行动可放弃 = true
	引擎.行动额外 = true
	引擎.行动额外来源 = 计数角色.额外攻击来源
	角色.额外攻击牌 = [攻击牌甲.id]
	角色.额外攻击目标 = [3]
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
	var 额外阶段: BattleEngine.SActionPhase = BattleEngine.SActionPhase.new(
		GConst.ActionType.Attack, true, true, false, 当前额外)
	额外阶段.额外数据 = {
		"allow_action": GConst.ActionType.Attack, "cause": 当前额外,
		"direct": true, "skip_notice": true,
	}
	引擎.push(额外阶段)
	引擎.run()
	检(引擎.行动额外 and 引擎.行动额外来源 == 当前额外,
		"应进入当前额外攻击阶段（额外 %s / 来源 %s）" % [str(引擎.行动额外), str(引擎.行动额外来源)])
	var 切换命令表: Array = 引擎._最后询问.get(1, {}).get("commands", [])
	var 有切换: bool = false
	for c: Dictionary in 切换命令表:
		if int(c.get("respond_id", 0)) == GConst.ActionType.ChooseExtraAction \
				and (c.get("args", []) as Array) == [另一额外]:
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

	# ---- 场景 10：风怒追击的白名单按 cause 给，不依赖当前是否已经进入 ----
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
		var 白名单: Array = 剑圣.extra_action_card_ids(103, GConst.ActionType.Attack)
		检(白名单 == [风击.id],
			"风怒追击的牌白名单应只含风系攻击牌，实际 %s" % str(白名单))
		引擎.行动额外 = true
		引擎.行动额外来源 = 103
		检(剑圣.v_attack(非风击.id, 3, {3: 引擎.p(3)}) != GConst.GE_SUCCESS,
			"风怒追击额外攻击不应允许非风系攻击牌")
		检(剑圣.v_attack(风击.id, 3, {3: 引擎.p(3)}) == GConst.GE_SUCCESS,
			"风怒追击额外攻击应允许风系攻击牌")
		# 恢复 dummy 角色，避免影响同用例后续（当前已是最后一个场景）
		玩家1.role = 角色
	else:
		检(false, "卡库里找不到一张风系攻击牌和一张非风系攻击牌")

	# ---- 场景 11：103 风怒追击 / 105 剑影在攻击结束时一起摆出来问 ----
	_重置战斗()
	var 剑圣二: BattleRole = 剑圣类.new()
	剑圣二.setup(玩家1, 引擎)
	玩家1.role = 剑圣二
	玩家1.set_gem(1)
	引擎.push(BattleEngine.SHook.new("p_after_attack", {"player": 1}, []))
	引擎.run()
	var 一问: Array = 引擎._最后询问.get(1, {}).get("commands", [])
	var 一选项: Array = (一问[0] as Dictionary).get("args", []) if not 一问.is_empty() else []
	检(一选项.size() >= 6 and 一选项.slice(4) == [103, 105],
		"攻击结束应同时摆出风怒追击和剑影：%s" % str(一选项))
	# 确认风怒追击后只入队，还应继续问剑影；不立即进入、不先消耗
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 103, "src_id": 1, "args": [103], "card_ids": [], "dst_ids": [],
	})
	var 二问: Array = 引擎._最后询问.get(1, {}).get("commands", [])
	var 二选项: Array = (二问[0] as Dictionary).get("args", []) if not 二问.is_empty() else []
	检(二选项.size() >= 5 and 二选项.slice(4) == [105],
		"选完风怒追击后还应继续问剑影：%s" % str(二选项))
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
	# 从 103 切到 105 时 using 标记可能仍是 true，v_attack 不能因此套用风系限制
	var 非风五: GCard = null
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.is_attack() \
				and c.element_enum() != GConst.CardElement.Wind:
			非风五 = c
			break
	剑圣五.using_lian_xu_ji = true
	玩家1.hand_cards.append(非风五.id)
	引擎.行动额外 = true
	引擎.行动额外来源 = 105
	检(剑圣五.v_attack(非风五.id, 3, {3: 引擎.p(3)}) == GConst.GE_SUCCESS,
		"剑影额外攻击不应继承风怒追击的风系限制")
	检(not 剑圣五.using_lian_xu_ji, "切到剑影后应清除风怒追击的 using 标记")

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
	玩家1.add_action(GConst.ActionType.Attack, 101, true, true)
	玩家1.add_action(GConst.ActionType.Attack, 103, true, true)
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

	# ---- 场景 19：疾风技 + 剑影 + 风怒追击 + 迅捷赐福 都在队列时，1601 也应作为可切换项 ----
	_重置战斗()
	var 剑圣九: BattleRole = 剑圣类.new()
	剑圣九.setup(玩家1, 引擎)
	玩家1.role = 剑圣九
	玩家1.add_action(GConst.ActionType.Attack, 101, true, true)
	玩家1.add_action(GConst.ActionType.Attack, 105, true, true)
	玩家1.add_action(GConst.ActionType.Attack, 103, true, true)
	玩家1.add_action(GConst.ActionType.Attack, GConst.技能_迅捷赐福, true)
	for a: Dictionary in 玩家1.additional_actions:
		if int(a.get("cause", 0)) == GConst.技能_迅捷赐福:
			a["可切换"] = true
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
		检(((赐福剩余问[0] as Dictionary).get("extra_attack_causes", []) as Array)\
			.has(GConst.技能_迅捷赐福),
			"确认迅捷赐福后新获得的攻击行动应作为通用快捷按钮出现在剩余响应里")
		引擎.on_message(1, GConst.Msg.Respond, {
			"respond_id": 103, "src_id": 1, "args": [], "card_ids": [], "dst_ids": [],
		})
		检(引擎.行动额外来源 == GConst.技能_迅捷赐福 and 引擎._await_kind == GConst.Msg.Action,
			"放弃剩余响应后进入 1601 额外行动（来源 %d / 等待 %s）"
			% [引擎.行动额外来源, str(引擎._await_kind)])
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
