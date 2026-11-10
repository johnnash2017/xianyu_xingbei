extends 自检用例
## 用例 9d：式神咒束（3301）服务端引擎集成 —— 3301 询问直接带三档选项，
## 应答里带「发动 + 3306 选择 + 应战牌 + 反击目标」；引擎一次消费，不再问第二次。

func _init() -> void:
	名称 = "式神咒束引擎集成"


func 跑() -> void:
	await 等帧(2)

	var 攻击牌: GCard = null
	var 应战牌: GCard = null
	var 备选同命格: GCard = null
	var 圣光: GCard = null
	for c: GCard in Data.card_db:
		if c.card_name_enum() == GConst.CardName.HolyLight:
			圣光 = c
		if 攻击牌 == null and c.is_attack() and c.element_enum() != GConst.CardElement.Darkness:
			攻击牌 = c
	if 攻击牌 != null:
		for c: GCard in Data.card_db:
			if c == 攻击牌 or not c.is_attack() or c.element_enum() == GConst.CardElement.Light:
				continue
			if c.fate_pattern_enum() != 攻击牌.fate_pattern_enum():
				continue
			# 优先找「同命格但不同系」的牌：这样「仅应战」不可用，能验证服务端下发的 enabled
			if c.element_enum() != 攻击牌.element_enum():
				应战牌 = c
				break
			if 备选同命格 == null:
				备选同命格 = c
		if 应战牌 == null:
			应战牌 = 备选同命格
	检(攻击牌 != null and 应战牌 != null, "找不到同命格攻击牌，用例前提不成立")
	if 攻击牌 == null or 应战牌 == null:
		return

	var 引擎: BattleEngine = BattleEngine.new()
	var 发送记录: Array = []
	引擎.send_cb = func(pid: int, msg: int, data: Dictionary) -> void:
		发送记录.append({"pid": pid, "msg": msg, "data": data})
	引擎.add_player(1, GConst.BLUE, "阴阳师")
	引擎.add_player(2, GConst.BLUE, "队友")
	引擎.add_player(3, GConst.RED, "攻击者")
	引擎.add_player(4, GConst.RED, "反击目标")
	引擎.start_with_roles({1: 33, 2: 0, 3: 0, 4: 0})
	# 清掉开局状态，手工布置：阴阳师处于式神形态、队伍有 2 宝石可付式神咒束代价
	引擎.p(1).tap = true
	引擎._states.clear()
	引擎._清空等待()
	引擎.phase = BattleEngine.Phase.Playing
	引擎.team_gem[GConst.BLUE] = 2
	引擎.team_crystal[GConst.BLUE] = 0
	var 手牌: Array[int] = [应战牌.id]
	if 圣光 != null:
		手牌.append(圣光.id)
	引擎.p(1).hand_cards = 手牌
	引擎.p(3).hand_cards = [攻击牌.id] as Array[int]
	发送记录.clear()

	var harm: Dictionary = {
		"src": 3, "dst": 2, "point": BattleEngine.ATTACK_BASE_POINT,
		"cause": GConst.CAUSE_ATTACK, "type": GConst.HarmType.Attack, "card_id": 攻击牌.id,
		"card_id_instance": 攻击牌.id,
	}
	引擎.push(BattleEngine.SAttackCard.new(3, 2, 攻击牌.id, harm))
	引擎.run()

	var 问3301: Dictionary = {}
	for r: Dictionary in 发送记录:
		if int(r["pid"]) == 1 and int(r["msg"]) == GConst.Msg.CmdReq:
			var cmds: Array = (r["data"] as Dictionary).get("commands", [])
			if not cmds.is_empty() and int((cmds[0] as Dictionary).get("respond_id", 0)) == GConst.技能_式神咒束:
				问3301 = cmds[0]
	检(not 问3301.is_empty(), "队友被攻击后没有向阴阳师发出 3301 询问")
	检(not bool(问3301.get("can_light", true)), "3301 询问没有下发 can_light=false（替队友不能用圣光）")
	if 问3301.is_empty():
		return
	var 参数: Array = 问3301.get("args", [])
	检(参数.size() >= 7 and int(参数[3]) == 3, "3301 询问没下发三档选项（args=%s）" % str(参数))
	# 应战牌是同命格异系时，「仅应战」在 3301 这条不可用；
	# 手里即使有【圣光】，也不能让 3301 的「仅应战」变成可用（替队友不能用圣光挡）
	if 应战牌.element_enum() != 攻击牌.element_enum():
		检((问3301.get("option_enabled", []) as Array) == [false, true, true],
			"3301 的「仅应战」应为不可用（手里只有同命格异系牌 + 圣光）：%s" % str(问3301.get("option_enabled", [])))
	检(int(问3301.get("preview_base", 0)) == 攻击牌.id, "3301 询问没带本次攻击牌")
	检((问3301.get("preview_ids", []) as Array) == [3], "3301 询问没带攻击者")
	检(int(问3301.get("preview_damage", -1)) == BattleEngine.ATTACK_BASE_POINT,
		"3301 询问没带本次攻击的伤害预览")

	# 应答 3301：发动式神咒束 + 阴阳转换 + 同命格应战牌 + 反击目标 4
	发送记录.clear()
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": GConst.技能_式神咒束, "src_id": 1,
		"args": [1, 2], "card_ids": [应战牌.id], "dst_ids": [4],
	})
	var 又问1应战: bool = false
	for r: Dictionary in 发送记录:
		if int(r["pid"]) == 1 and int(r["msg"]) == GConst.Msg.CmdReq:
			var cmds: Array = (r["data"] as Dictionary).get("commands", [])
			if not cmds.is_empty() and int((cmds[0] as Dictionary).get("respond_id", 0)) == GConst.RespondType.ReplyAttack:
				又问1应战 = true
	检(not 又问1应战, "3301 已带牌带目标，却又问了阴阳师一次应战")
	检(引擎._await_id == 4, "式神咒束应战成立后没有转而询问反击目标（_await_id=%s）" % str(引擎._await_id))
	检(int(引擎.team_gem[GConst.BLUE]) == 0, "式神咒束代价没有扣（宝石应 2→0，实际 %d）" % int(引擎.team_gem[GConst.BLUE]))

	# 反击目标放弃应战 → 反击命中：阴阳转换 +1 鬼火，并退出式神形态
	发送记录.clear()
	引擎.on_message(4, GConst.Msg.Respond, {
		"respond_id": GConst.RespondType.ReplyAttack, "src_id": 4,
		"args": [GConst.Reattack.GiveUp], "card_ids": [], "dst_ids": [],
	})
	var 鬼火: int = int((引擎.p(1).tokens[0] as Dictionary).get("num", -1))
	检(鬼火 == 1, "式神咒束里的阴阳转换后鬼火应为 1，实际 %d" % 鬼火)
	检(not 引擎.p(1).tap, "阴阳转换结算后没有退出式神形态")

	# 手里完全没有对应牌：仍然要弹 3301（三档全部置灰），避免对手从「没弹询问」推断手牌
	引擎._states.clear()
	引擎._清空等待()
	引擎.phase = BattleEngine.Phase.Playing
	引擎.p(1).tap = true
	引擎._states.clear()
	引擎.p(1).hand_cards.clear()
	引擎.p(2).hand_cards.clear()
	引擎.p(3).hand_cards.clear()
	引擎.p(4).hand_cards.clear()
	引擎.team_gem[GConst.BLUE] = 2
	引擎.team_crystal[GConst.BLUE] = 0
	发送记录.clear()
	var 无牌攻击: Dictionary = {
		"src": 3, "dst": 2, "point": BattleEngine.ATTACK_BASE_POINT,
		"cause": GConst.CAUSE_ATTACK, "type": GConst.HarmType.Attack, "card_id": 攻击牌.id,
		"card_id_instance": 攻击牌.id,
	}
	引擎.push(BattleEngine.SAttackCard.new(3, 2, 攻击牌.id, 无牌攻击))
	引擎.run()
	var 无牌问3301: Dictionary = {}
	for r: Dictionary in 发送记录:
		if int(r["pid"]) == 1 and int(r["msg"]) == GConst.Msg.CmdReq:
			var cmds: Array = (r["data"] as Dictionary).get("commands", [])
			if not cmds.is_empty() and int((cmds[0] as Dictionary).get("respond_id", 0)) == GConst.技能_式神咒束:
				无牌问3301 = cmds[0]
	检(not 无牌问3301.is_empty(), "手里没有对应牌时仍应弹出 3301 询问（避免泄露手牌）")
	if not 无牌问3301.is_empty():
		检((无牌问3301.get("option_enabled", []) as Array) == [false, false, false],
			"没有对应牌时 3301 三档都应置灰：%s" % str(无牌问3301.get("option_enabled", [])))
		发送记录.clear()
		引擎.on_message(1, GConst.Msg.Respond, {
			"respond_id": GConst.技能_式神咒束, "src_id": 1,
			"args": [], "card_ids": [], "dst_ids": [],
		})
		检(引擎._await_id == 2, "取消 3301 后应由队友自己应战（_await_id=%s）" % str(引擎._await_id))
		检(int(引擎.team_gem[GConst.BLUE]) == 2, "取消 3301 不应扣式神咒束代价")

	print("[自检] 式神咒束引擎：3301 一次应答直接应战，不再问第二次")
