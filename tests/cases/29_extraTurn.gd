extends 自检用例
## F7 额外回合 / 角色替换（spike）：
## - 额外回合：当前回合正常结束后，由安排者立即开始一个完整的新回合——不推进 current_id 到下家、
##   不增加 round_id；回合开始钩子 / 中毒虚弱 / 行动计数 / 启动标记全部按普通回合重置；
##   该额外回合里安排者的普通攻击 / 应战反击伤害 +N（引擎统一加，不依赖角色对象）。
## - 角色替换：旧角色 p_before_role_replace 清理 → 解绑 → 通用状态 / 上限 / 指示物重置 →
##   按角色表重新 setup 新角色（剑之子 → 风之剑圣）；手牌 / 盖牌 / 基础效果 / 能量 / 治疗保留。
## - 组合（模拟 10803）：回合结束后先安排 +1 额外回合、再替换为风之剑圣；额外回合照常开始，
##   新角色能正常行动，且本次攻击伤害吃到 +1。

## dummy 角色：回合结束时安排额外回合，可选在同一个钩子里替换角色（10803 的顺序）。
class 额外回合角色:
	extends BattleRole

	const 技能号: int = 9902

	## 下一次 p_after_turn_end 要不要安排额外回合（安排一次后自动关掉）
	var 自动安排: bool = false
	## 安排后要不要顺手替换角色（0＝不替换；1＝风之剑圣）
	var 自动替换角色: int = 0
	## 安排结果与当时的 ctx
	var 安排记录: Array = []
	## p_after_turn_end 收到的 ctx（普通回合 / 额外回合各一条）
	var 回合结束记录: Array = []
	## p_before_turn_begin / p_turn_begin 收到的 ctx
	var 回合开始记录: Array = []

	func p_after_turn_end(ctx: Dictionary) -> int:
		回合结束记录.append(ctx.duplicate())
		if not 自动安排:
			return SUCCESS
		自动安排 = false
		var rc: int = engine.安排额外回合(player.id, 1, 技能号)
		安排记录.append({"rc": rc, "ctx": ctx.duplicate()})
		if 自动替换角色 > 0:
			var rid: int = 自动替换角色
			自动替换角色 = 0
			engine.替换角色(player.id, rid)
		return SUCCESS

	func p_before_turn_begin(ctx: Dictionary) -> int:
		回合开始记录.append({"hook": "before", "ctx": ctx.duplicate()})
		return SUCCESS

	func p_turn_begin(ctx: Dictionary) -> int:
		回合开始记录.append({"hook": "begin", "ctx": ctx.duplicate()})
		return SUCCESS


## dummy 观察角色：记录 2 号打出的攻击伤害（验证额外回合攻击 +1 真的进了 harm）
class 观察角色:
	extends BattleRole

	var 攻击伤害记录: Array = []

	func p_timeline_1(ctx: Dictionary) -> int:
		if int(ctx.get("src", -1)) == 2:
			var harm: Dictionary = ctx.get("harm", {})
			攻击伤害记录.append(int(harm.get("point", 0)))
		return SUCCESS


## dummy 旧角色：验证替换前的清理钩子与解绑
class 旧角色:
	extends BattleRole

	var 已清理: bool = false
	var 清理记录: Array = []

	func p_before_role_replace(ctx: Dictionary) -> int:
		已清理 = true
		清理记录.append(ctx.duplicate())
		return SUCCESS


var 引擎: BattleEngine = null
var 玩家1: BattlePlayer = null
var 玩家2: BattlePlayer = null
var 玩家3: BattlePlayer = null
var 玩家4: BattlePlayer = null
var 额外: 额外回合角色 = null
var 观察: 观察角色 = null
var 发送记录: Array = []


func _init() -> void:
	名称 = "额外回合与角色替换"


# ============================================================
# 工具
# ============================================================
## 卡库里第一张非暗系攻击牌（暗系无法应战，这里要能走到应战询问）
func _取攻击牌() -> GCard:
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual or not c.is_attack():
			continue
		if c.element_enum() == GConst.CardElement.Darkness:
			continue
		return c
	return null


## 连取 数量 张互不相同的非虚拟牌
func _取实体牌号(数量: int, 排除: Array = []) -> Array[int]:
	var out: Array[int] = []
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual or 排除.has(c.id) or out.has(c.id):
			continue
		out.append(c.id)
		if out.size() >= 数量:
			break
	return out


func _挂角色(p0: BattlePlayer, 角色: BattleRole) -> void:
	角色.setup(p0, 引擎)
	p0.role = 角色


## 卸下所有角色（同一个角色实例不能同时挂两个人：先全部解绑再重新挂）
func _卸下所有角色() -> void:
	for pid: int in 引擎.order:
		引擎.p(pid).role = null


func _换手牌(p0: BattlePlayer, cards: Array) -> void:
	p0.hand_cards.clear()
	for c: Variant in cards:
		p0.hand_cards.append(int(c))


## 发送记录里有没有「额外回合」的 TurnBegin
func _有额外回合广播() -> bool:
	for r: Dictionary in 发送记录:
		if int(r["msg"]) != GConst.Msg.TurnBegin:
			continue
		var data: Dictionary = r["data"]
		if bool(data.get("extra_turn", false)):
			return true
	return false


## 回合开始钩子里有没有 extra_turn = 期望值 的记录
func _有回合开始记录(期望额外: bool) -> bool:
	for rec: Dictionary in 额外.回合开始记录:
		var ctx: Dictionary = rec.get("ctx", {})
		if bool(ctx.get("extra_turn", false)) == 期望额外:
			return true
	return false


## 清空战斗状态：轮到玩家 1、普通回合、无额外回合 / 无等待
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
	引擎.测试跳过回合 = -1
	引擎.额外回合玩家 = -1
	引擎.额外回合攻击加伤 = 0
	引擎.额外回合来源 = 0
	引擎.当前额外回合玩家 = -1
	引擎.当前额外回合攻击加伤 = 0
	引擎.当前额外回合来源 = 0
	引擎.额外回合续位 = -1
	引擎.deck.discard.clear()
	引擎.last_harm_cause = 0
	引擎.last_harm_type = 0
	引擎.team_morale[GConst.BLUE] = 10
	引擎.team_morale[GConst.RED] = 10
	发送记录.clear()
	for pid: int in 引擎.order:
		var p0: BattlePlayer = 引擎.p(pid)
		p0.hand_cards.clear()
		p0.cover_cards.clear()
		p0.basic_effects.clear()
		p0.additional_actions.clear()
		p0.cross_num = 0
		p0.tap = false
		p0.boot_skill_used = false
		p0.reset_action_counts()
	额外.安排记录.clear()
	额外.回合结束记录.clear()
	额外.回合开始记录.clear()
	额外.自动安排 = false
	额外.自动替换角色 = 0
	观察.攻击伤害记录.clear()


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
	额外 = 额外回合角色.new()
	观察 = 观察角色.new()

	_测试额外回合()
	_测试额外回合跨回合边界()
	_测试安排额外回合并替换角色()
	_测试角色替换()

	# 收尾
	引擎._states.clear()
	引擎._清空等待()
	引擎.send_cb = Callable()


# ============================================================
# 额外回合：不推进 current_id / 不增加 round_id、状态重置、攻击加伤
# ============================================================
func _测试额外回合() -> void:
	_重置战斗()
	_卸下所有角色()
	_挂角色(玩家2, 额外)
	额外.自动安排 = true
	引擎.current_id = 2
	引擎.round_id = 1
	玩家2.attack_action_count = 2
	玩家2.magic_action_count = 1
	玩家2.extra_action_count = 1
	玩家2.boot_skill_used = true

	引擎.push(BattleEngine.STurnEnd.new())
	引擎.run()

	检(引擎._await_id == 2 and 引擎._await_kind == GConst.Msg.Action,
		"额外回合开始后应等待 2 号行动（等待 %s / %s）" % [str(引擎._await_id), str(引擎._await_kind)])
	检(引擎.current_id == 2, "额外回合不应推进 current_id，实际 %d" % 引擎.current_id)
	检(引擎.round_id == 1, "额外回合不应增加 round_id，实际 %d" % 引擎.round_id)
	检(引擎.是否额外回合() and 引擎.当前额外回合玩家 == 2,
		"应处于 2 号的额外回合（当前 %s）" % str(引擎.当前额外回合玩家))
	检(引擎.额外回合加伤(2) == 1, "2 号额外回合攻击加伤应为 1")
	检(引擎.额外回合加伤(3) == 0, "非额外回合玩家不应吃到加伤")
	检(引擎.攻击基础伤害(2) == 3 and 引擎.攻击基础伤害(3) == 2,
		"攻击基础伤害应分别为 3 / 2，实际 %d / %d" % [引擎.攻击基础伤害(2), 引擎.攻击基础伤害(3)])
	检(额外.安排记录.size() == 1 and int(额外.安排记录[0].get("rc", -1)) == GConst.GE_SUCCESS,
		"p_after_turn_end 里安排额外回合应成功")
	检(玩家2.action_count() == 0 and 玩家2.extra_action_count == 0,
		"额外回合开始应重置行动计数（总 %d / 额外 %d）" % [玩家2.action_count(), 玩家2.extra_action_count])
	检(not 玩家2.boot_skill_used, "额外回合开始应重置「启动技能已用」标记")
	检(_有回合开始记录(true), "额外回合的 p_before_turn_begin / p_turn_begin 上下文应带 extra_turn=true")
	检(_有额外回合广播(), "额外回合开始应广播带 extra_turn=true 的 TurnBegin")
	检(not 额外.回合结束记录.is_empty() and not bool(额外.回合结束记录[0].get("extra_turn", true)),
		"普通回合结束的 ctx.extra_turn 应为 false：%s" % str(额外.回合结束记录))

	# 结束额外回合：应正常轮转到下家 3 号（先手红队），同时 round 进 1
	引擎._states.clear()
	引擎._清空等待()
	引擎.push(BattleEngine.STurnEnd.new())
	引擎.run()
	检(引擎.current_id == 3, "额外回合结束后应轮到 3 号，实际 %d" % 引擎.current_id)
	检(not 引擎.是否额外回合() and 引擎.当前额外回合玩家 == -1, "额外回合结束后应清掉额外回合状态")
	检(引擎.额外回合加伤(2) == 0, "额外回合结束后加伤应清零")
	检(引擎.round_id == 2, "绕回先手 3 号时 round_id 应 +1，实际 %d" % 引擎.round_id)
	检(引擎._await_id == 3, "额外回合结束后应等待 3 号行动")
	检(额外.回合结束记录.size() >= 2 and bool(额外.回合结束记录[1].get("extra_turn", false)),
		"额外回合结束的 ctx.extra_turn 应为 true：%s" % str(额外.回合结束记录))


# ============================================================
# 额外回合跨回合边界：2 号额外回合结束后轮转到先手 3 号，round_id 才 +1
# ============================================================
func _测试额外回合跨回合边界() -> void:
	_重置战斗()
	_卸下所有角色()
	_挂角色(玩家2, 额外)
	额外.自动安排 = true
	引擎.current_id = 2
	引擎.round_id = 5

	引擎.push(BattleEngine.STurnEnd.new())
	引擎.run()
	检(引擎.current_id == 2 and 引擎.round_id == 5,
		"2 号额外回合开始应保持 current_id=2 / round=5，实际 %d / %d" % [引擎.current_id, 引擎.round_id])
	检(引擎.是否额外回合() and 引擎.当前额外回合玩家 == 2, "应处于 2 号的额外回合")

	引擎._states.clear()
	引擎._清空等待()
	引擎.push(BattleEngine.STurnEnd.new())
	引擎.run()
	检(引擎.current_id == 3, "2 号额外回合结束后应轮到先手 3 号，实际 %d" % 引擎.current_id)
	检(引擎.round_id == 6, "轮转到先手 3 号时 round_id 应 +1，实际 %d" % 引擎.round_id)
	检(not 引擎.是否额外回合(), "跨回合后额外回合状态应清掉")


# ============================================================
# 10803 顺序：先安排 +1 额外回合，再替换为风之剑圣；额外回合里攻击吃到 +1
# ============================================================
func _测试安排额外回合并替换角色() -> void:
	_重置战斗()
	_卸下所有角色()
	_挂角色(玩家2, 额外)
	_挂角色(玩家4, 观察)
	额外.自动安排 = true
	额外.自动替换角色 = 1
	引擎.current_id = 1
	var 攻击牌: GCard = _取攻击牌()
	检(攻击牌 != null, "找不到非暗系攻击牌")
	_换手牌(玩家2, [攻击牌.id])

	引擎.push(BattleEngine.STurnEnd.new())
	引擎.run()
	检(引擎.current_id == 2, "额外回合应切到安排者 2 号，实际 %d" % 引擎.current_id)
	检(引擎.是否额外回合() and 引擎.当前额外回合玩家 == 2, "应处于 2 号的额外回合")
	检(引擎.额外回合加伤(2) == 1, "本次额外回合攻击加伤应为 1")
	检(玩家2.role_id == 1, "角色卡应替换为风之剑圣（角色号 1），实际 %d" % 玩家2.role_id)
	检(玩家2.role != null and 玩家2.role.player == 玩家2 and 玩家2.role.engine == 引擎,
		"替换后的角色对象应重新绑定到玩家 2")
	检(玩家2.hand_cards.has(攻击牌.id), "替换角色不应丢掉手牌")
	检(_有额外回合广播(), "替换角色后的额外回合开始应广播带 extra_turn=true 的 TurnBegin")

	# 额外回合里用普通攻击：应战询问前应已把 +1 加进 harm
	引擎.on_message(2, GConst.Msg.Action, {
		"action_type": GConst.ActionType.Attack, "action_id": 0, "src_id": 2,
		"card_ids": [攻击牌.id], "dst_ids": [3], "args": [],
	})
	检(观察.攻击伤害记录 == [3],
		"额外回合的普通攻击伤害应为 3（2+1），实际 %s" % str(观察.攻击伤害记录))
	检(玩家2.attack_action_count == 1, "额外回合里的攻击应正常记行动数")
	检(引擎.current_id == 2 and 玩家2.role_id == 1, "攻击后应仍是 2 号的风之剑圣额外回合")


# ============================================================
# 角色替换：清理 / 解绑 / 上限与指示物重算 / 资源保留
# ============================================================
func _测试角色替换() -> void:
	_重置战斗()
	_卸下所有角色()
	var 旧: 旧角色 = 旧角色.new()
	_挂角色(玩家2, 旧)
	var 手牌: Array[int] = _取实体牌号(3)
	var 盖牌: Array[int] = _取实体牌号(2, 手牌)
	_换手牌(玩家2, 手牌)
	玩家2.cover_cards.assign(盖牌)
	玩家2.cover_cards_max = 2
	玩家2.basic_effects.append({"card": 手牌[0], "src": 1})
	玩家2.hand_cards_max = 8
	玩家2.energy_max = 4
	玩家2.cross_max = 5
	玩家2.tokens[0] = {"name": "旧指示物", "max": 3, "num": 2}
	玩家2.tokens[1] = {"name": "旧指示物2", "max": 2, "num": 1}
	玩家2.tap = true
	玩家2.boot_skill_used = true
	玩家2.record_action("attack", true)
	玩家2.add_action(GConst.ActionType.Attack, 1234)
	var 手牌前: Array = 玩家2.hand_cards.duplicate()
	var 盖牌前: Array = 玩家2.cover_cards.duplicate()
	var 基础效果前: int = 玩家2.basic_effects.size()

	检(引擎.替换角色(2, 1) == GConst.GE_SUCCESS, "替换为风之剑圣应成功")
	检(旧.已清理 and 旧.清理记录.size() == 1, "旧角色应收到 p_before_role_replace")
	if not 旧.清理记录.is_empty():
		检(int(旧.清理记录[0].get("new_role_id", -1)) == 1, "清理钩子应带新角色号 1")
	检(旧.player == null and 旧.engine == null, "旧角色应已解绑 player / engine")
	检(玩家2.role_id == 1 and Data.role_name(1) == "风之剑圣", "角色号应变成风之剑圣（1）")
	检(玩家2.role != null and 玩家2.role.player == 玩家2 and 玩家2.role.engine == 引擎,
		"新角色对象应绑定到玩家 2")
	检(玩家2.hand_cards_max == GConst.HAND_CARDS_MAX, "上限应恢复到基础手牌上限 6")
	检(玩家2.energy_max == GConst.ENERGY_MAX, "能量上限应恢复到基础 3")
	检(玩家2.cross_max == GConst.CROSS_MAX, "治疗上限应恢复到基础 2")
	检(玩家2.tokens[0] == null and 玩家2.token_def(0).is_empty(), "旧指示物槽 0 应被清空")
	检(玩家2.tokens[1] == null and 玩家2.token_def(1).is_empty(), "旧指示物槽 1 应被清空")
	检(玩家2.cover_cards_max == 0, "新角色没有盖牌槽时盖牌上限应为 0")
	检(not 玩家2.tap, "替换后应退出旧形态")
	检(not 玩家2.boot_skill_used, "替换后应清掉启动技能标记")
	检(玩家2.action_count() == 0 and 玩家2.extra_action_count == 0, "替换后行动计数应清零")
	检(玩家2.additional_actions.is_empty(), "替换后旧额外行动应清空")
	检((玩家2.hand_cards as Array) == 手牌前, "替换后手牌应保留")
	检((玩家2.cover_cards as Array) == 盖牌前, "替换后盖牌应保留")
	检(玩家2.basic_effects.size() == 基础效果前, "替换后基础效果应保留")
	检(玩家2.role.available_skills().is_empty(), "风之剑圣没有技能栏主动技，available_skills 应为空")
	检(玩家2.role.p_before_turn_begin({}) == BattleRole.SUCCESS, "新角色钩子应可正常调用")

	# 非法参数不改变现状
	检(引擎.替换角色(2, 0) == GConst.GE_INVALID_TABLEID, "角色号 0 应被拒绝")
	检(引擎.替换角色(99, 1) == GConst.GE_INVALID_PLAYERID, "不存在的玩家应被拒绝")
	检(玩家2.role_id == 1 and 玩家2.role != null, "非法替换后角色应保持不变")
