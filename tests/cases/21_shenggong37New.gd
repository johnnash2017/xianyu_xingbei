extends 自检用例
## 37 号圣弓新版技能：+2 水晶、圣屑只弃同系攻击牌、圣光爆裂改为辅助/群体、
## 圣煌辉光炮用完移除（不出余辉），以及客户端两处新分支。

func _init() -> void:
	名称 = "圣弓新版技能"


func _按号(技能表: Array) -> Dictionary:
	var out: Dictionary = {}
	for sk: Dictionary in 技能表:
		out[int(sk.get("id", 0))] = sk
	return out


func 跑() -> void:
	await 等帧(1)
	var 引擎: BattleEngine = BattleEngine.new()
	引擎.add_player(1, GConst.BLUE, "圣弓")
	引擎.add_player(2, GConst.BLUE, "队友")
	引擎.add_player(3, GConst.RED, "对手")
	引擎.start_with_roles({1: 37, 2: 0, 3: 0})
	引擎._states.clear()
	引擎._清空等待()
	引擎.phase = BattleEngine.Phase.Playing
	var 弓: BattlePlayer = 引擎.p(1)
	var 队友: BattlePlayer = 引擎.p(2)
	var 对手: BattlePlayer = 引擎.p(3)
	if 弓 == null or 弓.role == null:
		检(false, "37 号圣弓脚本没有挂上")
		return
	var 角色: BattleRole = 弓.role
	检(弓.crystal == 2, "天之弓开局应 +2 水晶，实际 %d" % 弓.crystal)
	检(弓.sheng_huang_side == 0, "开局应拥有【圣煌辉光炮】正面状态")

	var 技能: Dictionary = _按号(角色.available_skills())
	检(技能.has(3702) and 技能.has(3703) and 技能.has(3704) and 技能.has(3706),
		"新版圣弓技能栏缺少基础/法术技能：%s" % str(技能.keys()))
	检(not 技能.has(3708), "新版圣弓不应再摆出圣煌余辉")

	# 圣屑飓暴：只接受两张同系【攻击牌】
	var 同系攻击: Array[int] = []
	for a: GCard in Data.card_db:
		if not a.is_attack() or a.is_virtual:
			continue
		for b: GCard in Data.card_db:
			if b.id == a.id or not b.is_attack() or b.is_virtual:
				continue
			if b.element_enum() == a.element_enum():
				同系攻击 = [a.id, b.id]
				break
		if 同系攻击.size() == 2:
			break
	检(同系攻击.size() == 2, "卡库找不到两张同系攻击牌")
	if 同系攻击.size() == 2:
		弓.hand_cards.clear()
		弓.hand_cards.append_array(同系攻击)
		技能 = _按号(角色.available_skills())
		var 可弃: Array = (技能.get(3702, {}) as Dictionary).get("cards", [])
		检(可弃.has(同系攻击[0]) and 可弃.has(同系攻击[1]),
			"同系攻击牌应进入圣屑飓暴的合法牌：%s" % str(可弃))
		var 飓暴动作: Dictionary = {
			"src_id": 1, "action_id": 3702, "card_ids": 同系攻击, "dst_ids": [3],
		}
		检(角色.v_magic_skill(飓暴动作) == GConst.GE_SUCCESS, "两张同系攻击牌应能发动圣屑飓暴")

		var 非攻击: int = -1
		for c: GCard in Data.card_db:
			if not c.is_virtual and not c.is_attack() and c.element_enum() == Data.get_card(同系攻击[0]).element_enum():
				非攻击 = c.id
				break
		if 非攻击 >= 0:
			弓.hand_cards.clear()
			弓.hand_cards.append(同系攻击[0])
			弓.hand_cards.append(非攻击)
			var 混牌动作: Dictionary = {
				"src_id": 1, "action_id": 3702, "card_ids": [同系攻击[0], 非攻击], "dst_ids": [3],
			}
			检(角色.v_magic_skill(混牌动作) != GConst.GE_SUCCESS,
				"圣屑飓暴不能再把非攻击牌当同系牌弃掉")

	# 圣光爆裂：新辅助分支只能选同队目标
	弓.tap = true
	弓.cross_num = 2
	var 爆裂选项: Array = (技能.get(3704, {}) as Dictionary).get("arg_choices", [])
	检(爆裂选项.size() == 2, "圣光爆裂应有两个选项")
	if 爆裂选项.size() == 2:
		var 单体: Dictionary = 爆裂选项[0]
		检((单体.get("targets", []) as Array).has(队友.id), "圣光爆裂辅助分支应能选队友")
		检(not (单体.get("targets", []) as Array).has(对手.id), "圣光爆裂辅助分支不能选对手")
		var 辅助动作: Dictionary = {
			"src_id": 1, "action_id": 3704, "args": [1], "card_ids": [], "dst_ids": [队友.id],
		}
		检(角色.v_magic_skill(辅助动作) == GConst.GE_SUCCESS, "圣光爆裂应能对队友发动辅助分支")
		var 打敌动作: Dictionary = {
			"src_id": 1, "action_id": 3704, "args": [1], "card_ids": [], "dst_ids": [对手.id],
		}
		检(角色.v_magic_skill(打敌动作) != GConst.GE_SUCCESS, "圣光爆裂辅助分支不能打对手")

	# 圣屑未命中：选项文案必须写清是目标友方弃牌，不能让人误以为自己弃牌
	for 项: Dictionary in 角色.call("_sheng_xie_miss_choices"):
		检(str(项.get("label", "")).contains("目标友方"), "圣屑未命中选项应写明是目标友方弃牌：%s" % str(项.get("label", "")))

	# 圣煌辉光炮：用完直接移除，不再翻面、不给治疗、不给额外行动
	弓.tap = true
	弓.sheng_huang_side = 0
	弓.tokens[0]["num"] = 10
	弓.cross_num = 0
	队友.cross_num = 0
	弓.additional_actions.clear()
	var 四张: Array[int] = []
	for c: GCard in Data.card_db:
		if not c.is_virtual and not 四张.has(c.id):
			四张.append(c.id)
		if 四张.size() >= 4:
			break
	for p: BattlePlayer in [弓, 队友, 对手]:
		p.hand_cards.clear()
		p.hand_cards.append_array(四张)
	var 炮动作: Dictionary = {"src_id": 1, "action_id": 3706, "args": [0], "card_ids": [], "dst_ids": []}
	检(角色.v_magic_skill(炮动作) == GConst.GE_SUCCESS, "圣煌辉光炮应能发动")
	检(角色.p_magic_skill(炮动作) == BattleRole.SUCCESS, "圣煌辉光炮应能结算")
	检(弓.sheng_huang_side == 2, "37 号圣煌辉光炮用完后应直接移除状态")
	检(弓.cross_num == 0 and 队友.cross_num == 0, "37 号圣煌辉光炮不应再给我方治疗")
	检(not 弓.contains_action(), "37 号圣煌辉光炮不应再给额外行动")

	# 圣煌降临：脱离形态后由 p_after_special 询问 +1 治疗 / +1 信仰
	弓.tap = true
	弓.cross_num = 弓.cross_max
	弓.tokens[0]["num"] = 0
	角色.p_before_special({"player": 1})
	引擎._reply = {"args": [2], "card_ids": [], "dst_ids": []}
	引擎._has_reply = true
	角色.p_after_special({"player": 1})
	检(int(弓.tokens[0]["num"]) == 1, "圣煌形态脱离时选信仰应 +1 信仰")
	弓.tap = true
	弓.cross_num = 0
	弓.tokens[0]["num"] = 0
	角色.p_before_special({"player": 1})
	引擎._reply = {"args": [1], "card_ids": [], "dst_ids": []}
	引擎._has_reply = true
	角色.p_after_special({"player": 1})
	检(弓.cross_num == 1, "圣煌形态脱离时选治疗应 +1 治疗")

	# 客户端：37 的自动填充顺序、圣光爆裂辅助提示、没有攻击伤害/群体信仰
	var 窗: Control = load("res://scripts/ui/battle_mobile.gd").new()
	Logic.my_player_id = 1
	窗._skill_ask_id = 3707
	var 水晶二层: Array = 窗.call("_自动填充第二层选项", 1)
	检(水晶二层.size() == 2 and (水晶二层[0].get("args", []) as Array) == [1, 2],
		"37 号自动填充第二层应先列 +信仰")
	窗._pending_skill_id = 3704
	窗._mode = 4
	窗._已选参数 = [1]
	窗._sel_players.clear()
	窗._sel_players.append(队友.id)
	var 辅助提示: Dictionary = 窗.call("_圣光爆裂头像提示")
	检(str(辅助提示.get(队友.id, "")) == "+1 治疗", "37 号圣光爆裂辅助分支应给目标 +1 治疗")
	检(str(辅助提示.get(1, "")).contains("移除 1 治疗")
		and not str(辅助提示.get(1, "")).contains("攻击伤害"),
		"37 号圣光爆裂辅助分支自己不应再攻击")
	var 群体说明: String = 窗.call("_圣光爆裂群体说明", 2, 5)
	检(not 群体说明.contains("获得 2 点【信仰】"), "37 号群体分支不应再加信仰")
	窗._pending_skill_id = 3706
	窗._sel_players.clear()
	var 炮提示: Dictionary = 窗.call("_圣煌辉光炮头像提示")
	检(not str(炮提示.get(队友.id, "")).contains("+1 治疗"),
		"37 号圣煌辉光炮不应再给我方治疗")
