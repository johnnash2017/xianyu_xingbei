extends 自检用例
## 猎巫人（42，异端业火）：转换、魔力瓶获取与灌银毒刃的基础引擎验证。

func _init() -> void:
	名称 = "猎巫人"


func _找法术牌(排除圣光: bool) -> GCard:
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual or not c.is_magic():
			continue
		if 排除圣光:
			if c.card_name_enum() != GConst.CardName.HolyLight:
				return c
			continue
		if c.card_name_enum() == GConst.CardName.HolyLight:
			return c
	return null


func 跑() -> void:
	await 等帧(1)
	检(str(Data.role_list.get(42, "")) == "猎巫人", "42 号角色名不是「猎巫人」")
	检(Data.role_personal_name(42) == "白狼卡拉马", "42 号角色姓名不是「白狼卡拉马」")
	检(Data.role_version(42) == 2, "猎巫人应属于异端业火版本，实际 %d" % Data.role_version(42))
	检(Data.role_skills(42) == [4201, 4202, 4203, 4204, 4205],
		"猎巫人技能号不对：%s" % str(Data.role_skills(42)))
	var 瓶定义: Dictionary = Data.role_token_def(42, 2)
	检(str(瓶定义.get("name", "")) == "魔力瓶" and int(瓶定义.get("max", 0)) == 4,
		"猎巫人的魔力瓶盖牌上限配置不对：%s" % str(瓶定义))
	检(Art.role_hero(42) != null, "猎巫人缺选角立绘")
	检(ResourceLoader.exists("res://assets/textures/hero/small/42S.png"), "猎巫人缺战斗小头像")

	var 法术: GCard = _找法术牌(true)
	检(法术 != null, "卡库找不到可用于转换的非圣光法术牌")
	if 法术 == null:
		return

	var 引擎: BattleEngine = BattleEngine.new()
	引擎.add_player(1, GConst.BLUE, "猎巫人")
	引擎.add_player(2, GConst.RED, "靶子")
	引擎.start_with_roles({1: 42, 2: 0})
	引擎._states.clear()
	引擎._清空等待()
	var 猎: BattlePlayer = 引擎.p(1)
	var 靶: BattlePlayer = 引擎.p(2)
	var 角色: BattleRole = 猎.role
	猎.hand_cards.clear()
	猎.hand_cards.append(法术.id)
	var 技能表: Array = 角色.available_skills()
	var 转换技能: Dictionary = {}
	for sk: Dictionary in 技能表:
		if int(sk.get("id", 0)) == 4201:
			转换技能 = sk
	检(not 转换技能.is_empty(), "猎巫人的【转换】应作为技能栏按钮下发")
	检((转换技能.get("cards", []) as Array).has(法术.id),
		"【转换】技能的可选牌应包含非圣光法术牌：%s" % str(转换技能.get("cards", [])))
	var 转换动作: Dictionary = {
		"src_id": 1, "action_id": 4201, "card_ids": [法术.id], "dst_ids": [2],
	}
	检(角色.v_attack_skill(转换动作) == GConst.GE_SUCCESS,
		"通过【转换】技能应能把非圣光法术牌当作攻击牌使用")
	# 结算必须继续用原法术牌：转换只改变结算类型，不改变原牌的系别 / 命格。
	引擎._states.clear()
	引擎._清空等待()
	猎.hand_cards.clear()
	猎.hand_cards.append(法术.id)
	角色.p_attack_skill(转换动作)
	var 保留原牌: bool = false
	for st: Variant in 引擎._states:
		if st == null:
			continue
		var 伤害: Variant = st.get("harm")
		var 状态卡号: Variant = st.get("card")
		if 状态卡号 != null and int(状态卡号) == 法术.id and 伤害 is Dictionary \
				and int((伤害 as Dictionary).get("card_id", -1)) == 法术.id:
			保留原牌 = true
			break
	检(保留原牌, "转换攻击的结算卡仍是原法术牌（不能改成另一张攻击牌的命格/系别）")
	var 圣光: GCard = _找法术牌(false)
	if 圣光 != null:
		猎.hand_cards.clear()
		猎.hand_cards.append(圣光.id)
		var 圣光技能: Dictionary = {}
		for sk: Dictionary in 角色.available_skills():
			if int(sk.get("id", 0)) == 4201:
				圣光技能 = sk
		检(圣光技能.is_empty() or not (圣光技能.get("cards", []) as Array).has(圣光.id),
			"【圣光】不应成为【转换】的可选攻击牌")

	# 狩魔刺：目标手牌<4，目标弃 1 张后进入猎巫人的盖牌区
	引擎._states.clear()
	引擎._清空等待()
	猎.cover_cards.clear()
	猎.hand_cards.clear()
	猎.hand_cards.append(法术.id)
	靶.hand_cards.clear()
	靶.hand_cards.append(法术.id)
	靶.hand_cards.append(法术.id)
	靶.hand_cards.append(法术.id)
	var 刺: int = 角色.p_timeline_1({"src": 1, "dst": 2, "is_active": true, "harm": {}})
	检(刺 == BattleRole.WAIT, "狩魔刺应先询问发动者是否发动")
	var 发动问: Dictionary = {}
	for r: Dictionary in 引擎._最后询问.get(1, {}).get("commands", []):
		if int(r.get("respond_id", 0)) == 4202:
			发动问 = r
	检(not 发动问.is_empty(), "狩魔刺没有先询问发动者")
	引擎._reply = {"args": [1], "card_ids": [], "dst_ids": []}
	引擎._has_reply = true
	检(角色.p_timeline_1({"src": 1, "dst": 2, "is_active": true, "harm": {}}) == BattleRole.WAIT,
		"发动者确认后应继续询问目标弃牌")
	var 问: Dictionary = {}
	for r: Dictionary in 引擎._最后询问.get(2, {}).get("commands", []):
		if int(r.get("respond_id", 0)) == 4202:
			问 = r
	检(not 问.is_empty(), "狩魔刺没有向目标发出弃牌询问")
	引擎._reply = {"args": [], "card_ids": [靶.hand_cards[0]], "dst_ids": []}
	引擎._has_reply = true
	角色.p_timeline_1({"src": 1, "dst": 2, "is_active": true, "harm": {}})
	检(猎.cover_cards.size() == 1, "狩魔刺弃牌应成为 1 个【魔力瓶】")

	# 灌银毒刃：移除 1 瓶，伤害 -1，瓶入目标手牌，自己 +1 水晶
	引擎._states.clear()
	引擎._清空等待()
	猎.cover_cards = [法术.id]
	靶.hand_cards.clear()
	猎.cross_num = 0
	var 伤害: Dictionary = {
		"src": 1, "dst": 2, "point": 2, "cause": 0, "type": GConst.HarmType.Magic,
	}
	检(角色.p_timeline_6({"src": 1, "dst": 2, "harm": 伤害}) == BattleRole.WAIT,
		"灌银毒刃应在同一步让发动者选择要移除的魔力瓶")
	var 灌问: Dictionary = {}
	for r: Dictionary in 引擎._最后询问.get(1, {}).get("commands", []):
		if int(r.get("respond_id", 0)) == 4204:
			灌问 = r
	检(int(灌问.get("preview_base", 0)) == 2
		and int(灌问.get("preview_kind", 0)) == GConst.HarmType.Magic
		and (灌问.get("preview_ids", []) as Array).has(2),
		"灌银毒刃头像提示应向客户端下发原伤害、伤害类型和受伤目标：%s" % str(灌问))
	引擎._reply = {"args": [], "card_ids": [法术.id], "dst_ids": []}
	引擎._has_reply = true
	角色.p_timeline_6({"src": 1, "dst": 2, "harm": 伤害})
	检(int(伤害["point"]) == 1, "灌银毒刃应让本次伤害 -1")
	检(靶.hand_cards.has(法术.id), "灌银毒刃应把移除的魔力瓶加入目标手牌")
	检(猎.cross_num == 1, "灌银毒刃应让自己 +1 治疗")

	# 偷袭前提：1 水晶 + 2 个魔力瓶 + 攻击行动结束；满足时应先问发动者。
	猎.cover_cards.clear()
	猎.cover_cards.append(法术.id)
	猎.cover_cards.append(法术.id)
	猎.hand_cards.clear()
	猎.hand_cards.append(法术.id)
	猎.set_crystal(1)
	引擎._states.clear()
	引擎._清空等待()
	引擎.current_id = 1
	角色._touxi_step = 0
	角色._used_touxi = false
	引擎._push_action_end_hooks("p_after_attack", {"player": 1, "dst": 2}, false, 0)
	引擎.run()
	检(引擎._await_id == 1 and 引擎._await_kind == GConst.Msg.Respond,
		"满足 1 水晶 + 2 魔力瓶 + 法术牌时，偷袭应弹出询问")
	var 偷袭问: Dictionary = {}
	for r: Dictionary in 引擎._最后询问.get(1, {}).get("commands", []):
		if int(r.get("respond_id", 0)) == 4205:
			偷袭问 = r
	var 偷袭参数: Array = 偷袭问.get("args", [])
	var 偷袭需牌: Array = 偷袭问.get("option_need_cards", [])
	检(偷袭参数.size() >= 3 and int(偷袭参数[2]) == GConst.CardSource.Cover
		and not 偷袭需牌.is_empty() and int(偷袭需牌[0]) == 2,
		"偷袭发动询问应让发动者同一步选择 2 张盖牌：参数=%s 选项需牌=%s"
		% [str(偷袭参数), str(偷袭需牌)])

	# 水晶可以用宝石替代：只有 1 宝石、没有水晶时也要能触发偷袭
	猎.set_crystal(0)
	猎.set_gem(1)
	引擎._states.clear()
	引擎._清空等待()
	引擎.current_id = 1
	角色._touxi_step = 0
	角色._used_touxi = false
	引擎._push_action_end_hooks("p_after_attack", {"player": 1, "dst": 2}, false, 0)
	引擎.run()
	检(引擎._await_id == 1 and 引擎._await_kind == GConst.Msg.Respond,
		"只有宝石没有水晶时，宝石应可作为水晶的替代支付偷袭")

	# 法术剥离：先问发动者，确认后目标弃 1 张牌成瓶
	猎.cover_cards.clear()
	靶.hand_cards.clear()
	靶.hand_cards.append(法术.id)
	引擎._states.clear()
	引擎._清空等待()
	角色._boshi_step = 0
	检(角色.p_timeline_2_hit({"src": 1, "dst": 2, "is_active": true, "harm": {}}) == BattleRole.WAIT,
		"法术剥离应先询问发动者")
	引擎._reply = {"args": [1], "card_ids": [], "dst_ids": []}
	引擎._has_reply = true
	检(角色.p_timeline_2_hit({"src": 1, "dst": 2, "is_active": true, "harm": {}}) == BattleRole.WAIT,
		"法术剥离确认后应询问目标弃牌")
	引擎._reply = {"args": [], "card_ids": [靶.hand_cards[0]], "dst_ids": []}
	引擎._has_reply = true
	角色.p_timeline_2_hit({"src": 1, "dst": 2, "is_active": true, "harm": {}})
	检(猎.cover_cards.size() == 1, "法术剥离弃牌应成为 1 个魔力瓶")

	# 同系追加：伤害后单独选目标
	引擎._states.clear()
	引擎._清空等待()
	角色._touxi_same_step = 0
	检(角色.p_touxi_same({"player": 1}) == BattleRole.WAIT,
		"偷袭同系追加应在伤害结算后再次询问目标")
	引擎._reply = {"args": [], "card_ids": [], "dst_ids": [2]}
	引擎._has_reply = true
	角色.p_touxi_same({"player": 1})
	检(not 引擎._states.is_empty(), "偷袭同系追加应压入 1 点法术伤害")
