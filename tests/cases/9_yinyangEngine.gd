extends 自检用例
## 用例 9b：阴阳转换（3306）服务端引擎集成 —— 3306 应答里带上应战牌 / 反击目标后，
## 引擎直接消费预置答复，不再问第二次应战；只有式神形态下才把反击伤害改为鬼火数。

func _init() -> void:
	名称 = "阴阳转换引擎集成"


func 跑() -> void:
	await 等帧(2)

	var 攻击牌: GCard = null
	var 应战牌: GCard = null
	for c: GCard in Data.card_db:
		if c.is_attack() and c.element_enum() != GConst.CardElement.Darkness:
			攻击牌 = c
			break
	if 攻击牌 != null:
		for c: GCard in Data.card_db:
			if c != 攻击牌 and c.is_attack() and c.element_enum() != GConst.CardElement.Light \
					and c.fate_pattern_enum() == 攻击牌.fate_pattern_enum():
				应战牌 = c
				break
	检(攻击牌 != null and 应战牌 != null, "找不到同命格攻击牌，用例前提不成立")
	if 攻击牌 == null or 应战牌 == null:
		return

	var 引擎: BattleEngine = BattleEngine.new()
	var 发送记录: Array = []
	引擎.send_cb = func(pid: int, msg: int, data: Dictionary) -> void:
		发送记录.append({"pid": pid, "msg": msg, "data": data})
	引擎.add_player(1, GConst.BLUE, "我")
	引擎.add_player(2, GConst.RED, "攻")
	引擎.add_player(3, GConst.RED, "目标")
	引擎.start_with_roles({1: 33, 2: 0, 3: 0})
	# 清掉开局留下的状态 / 等待，手工发起一次「2 打 1」的攻击
	引擎._states.clear()
	引擎._清空等待()
	引擎.phase = BattleEngine.Phase.Playing
	引擎.p(1).hand_cards = [应战牌.id] as Array[int]
	引擎.p(2).hand_cards = [攻击牌.id] as Array[int]
	发送记录.clear()
	var harm: Dictionary = {
		"src": 2, "dst": 1, "point": BattleEngine.ATTACK_BASE_POINT,
		"cause": GConst.CAUSE_ATTACK, "type": GConst.HarmType.Attack, "card_id": 攻击牌.id,
	}
	引擎.push(BattleEngine.SAttackCard.new(2, 1, 攻击牌.id, harm))
	引擎.run()

	var 问3306: Dictionary = {}
	for r: Dictionary in 发送记录:
		if int(r["pid"]) == 1 and int(r["msg"]) == GConst.Msg.CmdReq:
			var cmds: Array = (r["data"] as Dictionary).get("commands", [])
			if not cmds.is_empty() and int((cmds[0] as Dictionary).get("respond_id", 0)) == GConst.技能_阴阳转换:
				问3306 = cmds[0]
	检(not 问3306.is_empty(), "攻击后没有向阴阳师发出 3306 询问")
	if 问3306.is_empty():
		return
	检(int(问3306.get("preview_base", 0)) == 攻击牌.id, "3306 询问没带本次攻击牌")
	检((问3306.get("preview_ids", []) as Array) == [2], "3306 询问没带攻击者")
	检(int(问3306.get("preview_damage", -1)) == BattleEngine.ATTACK_BASE_POINT,
		"3306 询问没带本次攻击的伤害预览：%s" % str(问3306))

	# 回复 3306：发动阴阳转换 + 应战牌 + 反击目标 3
	发送记录.clear()
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": GConst.技能_阴阳转换, "src_id": 1,
		"args": [2], "card_ids": [应战牌.id], "dst_ids": [3],
	})
	var 又问1应战: bool = false
	for r: Dictionary in 发送记录:
		if int(r["pid"]) == 1 and int(r["msg"]) == GConst.Msg.CmdReq:
			var cmds: Array = (r["data"] as Dictionary).get("commands", [])
			if not cmds.is_empty() and int((cmds[0] as Dictionary).get("respond_id", 0)) == GConst.RespondType.ReplyAttack:
				又问1应战 = true
	检(not 又问1应战, "3306 已带牌带目标，却又问了阴阳师一次应战")
	检(引擎._await_id == 3, "应战成立后没有转而询问反击目标（_await_id=%s）" % str(引擎._await_id))

	# 反击目标放弃应战 → 反击命中：不在式神形态时只 +1 鬼火，伤害仍按普通应战基础值
	引擎.on_message(3, GConst.Msg.Respond, {
		"respond_id": GConst.RespondType.ReplyAttack, "src_id": 3,
		"args": [GConst.Reattack.GiveUp], "card_ids": [], "dst_ids": [],
	})
	var 鬼火: int = int((引擎.p(1).tokens[0] as Dictionary).get("num", -1))
	检(鬼火 == 1, "本次阴阳转换后鬼火应为 1，实际 %d" % 鬼火)
	# 普通形态下不应把伤害改成鬼火数：仍是普通应战的 2
	var 反击伤害: int = -1
	for r: Dictionary in 发送记录:
		if int(r["msg"]) == GConst.Msg.Hurt \
				and int((r["data"] as Dictionary).get("dst_id", -1)) == 3:
			反击伤害 = int((r["data"] as Dictionary).get("hurt", -1))
	检(反击伤害 == BattleEngine.ATTACK_BASE_POINT,
		"不在式神形态时反击伤害不应改成鬼火数（应为 %d，实际 %d）" % [
			BattleEngine.ATTACK_BASE_POINT, 反击伤害])
	检(not 引擎.p(1).tap, "普通形态下不应被阴阳转换改动式神形态")

	# 式神形态下：伤害才改成鬼火数，并在结算后重置脱离形态
	引擎._states.clear()
	引擎._清空等待()
	引擎.phase = BattleEngine.Phase.Playing
	引擎.p(1).hand_cards = [应战牌.id] as Array[int]
	引擎.p(1).tokens[0]["num"] = 0
	引擎.p(1).tap = true
	引擎._states.clear()
	发送记录.clear()
	var 形态攻击: Dictionary = {
		"src": 2, "dst": 1, "point": BattleEngine.ATTACK_BASE_POINT,
		"cause": GConst.CAUSE_ATTACK, "type": GConst.HarmType.Attack, "card_id": 攻击牌.id,
	}
	引擎.push(BattleEngine.SAttackCard.new(2, 1, 攻击牌.id, 形态攻击))
	引擎.run()
	var 形态问3306: Dictionary = {}
	for r: Dictionary in 发送记录:
		if int(r["pid"]) == 1 and int(r["msg"]) == GConst.Msg.CmdReq:
			var cmds: Array = (r["data"] as Dictionary).get("commands", [])
			if not cmds.is_empty() and int((cmds[0] as Dictionary).get("respond_id", 0)) == GConst.技能_阴阳转换:
				形态问3306 = cmds[0]
	检(not 形态问3306.is_empty(), "式神形态下被攻击没有发出 3306 询问")
	if not 形态问3306.is_empty():
		发送记录.clear()
		引擎.on_message(1, GConst.Msg.Respond, {
			"respond_id": GConst.技能_阴阳转换, "src_id": 1,
			"args": [2], "card_ids": [应战牌.id], "dst_ids": [3],
		})
		引擎.on_message(3, GConst.Msg.Respond, {
			"respond_id": GConst.RespondType.ReplyAttack, "src_id": 3,
			"args": [GConst.Reattack.GiveUp], "card_ids": [], "dst_ids": [],
		})
		var 形态鬼火: int = int((引擎.p(1).tokens[0] as Dictionary).get("num", -1))
		var 形态伤害: int = -1
		for r: Dictionary in 发送记录:
			if int(r["msg"]) == GConst.Msg.Hurt \
					and int((r["data"] as Dictionary).get("dst_id", -1)) == 3:
				形态伤害 = int((r["data"] as Dictionary).get("hurt", -1))
		检(形态鬼火 == 1, "式神形态下阴阳转换后鬼火应为 1，实际 %d" % 形态鬼火)
		检(形态伤害 == 1, "式神形态下反击伤害应改为鬼火数 1，实际 %d" % 形态伤害)
		检(not 引擎.p(1).tap, "式神形态下阴阳转换结算后应重置脱离形态")

	# 再次被攻击：3306 点「取消」＝直接放弃整次应战，不再回退普通应战询问
	引擎._states.clear()
	引擎._清空等待()
	引擎.phase = BattleEngine.Phase.Playing
	引擎.p(1).hand_cards = [应战牌.id] as Array[int]
	# 上一段反击让目标摸到超限，先清掉，避免弃牌询问挡住这次新攻击
	引擎.p(3).hand_cards.clear()
	发送记录.clear()
	var 取消用攻击: Dictionary = {
		"src": 2, "dst": 1, "point": BattleEngine.ATTACK_BASE_POINT,
		"cause": GConst.CAUSE_ATTACK, "type": GConst.HarmType.Attack, "card_id": 攻击牌.id,
	}
	引擎.push(BattleEngine.SAttackCard.new(2, 1, 攻击牌.id, 取消用攻击))
	引擎.run()
	var 再问3306: Dictionary = {}
	for r: Dictionary in 发送记录:
		if int(r["pid"]) == 1 and int(r["msg"]) == GConst.Msg.CmdReq:
			var cmds: Array = (r["data"] as Dictionary).get("commands", [])
			if not cmds.is_empty() and int((cmds[0] as Dictionary).get("respond_id", 0)) == GConst.技能_阴阳转换:
				再问3306 = cmds[0]
	检(not 再问3306.is_empty(), "第二次攻击没有向阴阳师发出 3306 询问")
	if not 再问3306.is_empty():
		发送记录.clear()
		引擎.on_message(1, GConst.Msg.Respond, {
			"respond_id": GConst.技能_阴阳转换, "src_id": 1,
			"args": [], "card_ids": [], "dst_ids": [],
		})
		var 取消后又问应战: bool = false
		var 被命中: bool = false
		for r: Dictionary in 发送记录:
			if int(r["pid"]) == 1 and int(r["msg"]) == GConst.Msg.CmdReq:
				var cmds: Array = (r["data"] as Dictionary).get("commands", [])
				if not cmds.is_empty() and int((cmds[0] as Dictionary).get("respond_id", 0)) == GConst.RespondType.ReplyAttack:
					取消后又问应战 = true
			if int(r["msg"]) == GConst.Msg.Hurt \
					and int((r["data"] as Dictionary).get("dst_id", -1)) == 1:
				被命中 = true
		检(not 取消后又问应战, "3306 点取消后不该再问一次普通应战")
		检(被命中, "3306 点取消后原攻击应直接命中（放弃应战）")

	# 手里完全没有对应牌：仍然要弹 3306（三档全部置灰），避免对手从「没弹询问」推断手牌
	引擎._states.clear()
	引擎._清空等待()
	引擎.phase = BattleEngine.Phase.Playing
	引擎.p(1).hand_cards.clear()
	引擎.p(3).hand_cards.clear()
	发送记录.clear()
	var 无牌攻击: Dictionary = {
		"src": 2, "dst": 1, "point": BattleEngine.ATTACK_BASE_POINT,
		"cause": GConst.CAUSE_ATTACK, "type": GConst.HarmType.Attack, "card_id": 攻击牌.id,
	}
	引擎.push(BattleEngine.SAttackCard.new(2, 1, 攻击牌.id, 无牌攻击))
	引擎.run()
	var 无牌问3306: Dictionary = {}
	for r: Dictionary in 发送记录:
		if int(r["pid"]) == 1 and int(r["msg"]) == GConst.Msg.CmdReq:
			var cmds: Array = (r["data"] as Dictionary).get("commands", [])
			if not cmds.is_empty() and int((cmds[0] as Dictionary).get("respond_id", 0)) == GConst.技能_阴阳转换:
				无牌问3306 = cmds[0]
	检(not 无牌问3306.is_empty(), "手里没有对应牌时仍应弹出 3306 询问（避免泄露手牌）")
	if not 无牌问3306.is_empty():
		检((无牌问3306.get("option_enabled", []) as Array) == [false, false, false],
			"没有对应牌时三档都应置灰：%s" % str(无牌问3306.get("option_enabled", [])))
		发送记录.clear()
		引擎.on_message(1, GConst.Msg.Respond, {
			"respond_id": GConst.技能_阴阳转换, "src_id": 1,
			"args": [], "card_ids": [], "dst_ids": [],
		})
		var 无牌命中: bool = false
		var 无牌又问应战: bool = false
		for r: Dictionary in 发送记录:
			if int(r["msg"]) == GConst.Msg.Hurt \
					and int((r["data"] as Dictionary).get("dst_id", -1)) == 1:
				无牌命中 = true
			if int(r["pid"]) == 1 and int(r["msg"]) == GConst.Msg.CmdReq:
				var cmds: Array = (r["data"] as Dictionary).get("commands", [])
				if not cmds.is_empty() and int((cmds[0] as Dictionary).get("respond_id", 0)) == GConst.RespondType.ReplyAttack:
					无牌又问应战 = true
		检(not 无牌又问应战, "没有对应牌时点取消也不该再问一次普通应战")
		检(无牌命中, "没有对应牌时点取消应直接放弃应战、原攻击命中")

	# 选项 3（阴阳转换 + 式神转换）：+2 鬼火、摸 1 张；顺带验证 3305 摸牌走标准流程
	引擎._states.clear()
	引擎._清空等待()
	引擎.phase = BattleEngine.Phase.Playing
	引擎.p(1).hand_cards = [应战牌.id] as Array[int]
	引擎.p(1).tokens[0]["num"] = 0
	引擎.p(1).tap = true
	引擎._states.clear()
	引擎.p(3).hand_cards.clear()
	发送记录.clear()
	var 转换攻击: Dictionary = {
		"src": 2, "dst": 1, "point": BattleEngine.ATTACK_BASE_POINT,
		"cause": GConst.CAUSE_ATTACK, "type": GConst.HarmType.Attack, "card_id": 攻击牌.id,
	}
	引擎.push(BattleEngine.SAttackCard.new(2, 1, 攻击牌.id, 转换攻击))
	引擎.run()
	var 转换问3306: Dictionary = {}
	for r: Dictionary in 发送记录:
		if int(r["pid"]) == 1 and int(r["msg"]) == GConst.Msg.CmdReq:
			var cmds: Array = (r["data"] as Dictionary).get("commands", [])
			if not cmds.is_empty() and int((cmds[0] as Dictionary).get("respond_id", 0)) == GConst.技能_阴阳转换:
				转换问3306 = cmds[0]
	检(not 转换问3306.is_empty(), "选项 3 场景没有发出 3306 询问")
	if not 转换问3306.is_empty():
		发送记录.clear()
		引擎.on_message(1, GConst.Msg.Respond, {
			"respond_id": GConst.技能_阴阳转换, "src_id": 1,
			"args": [3], "card_ids": [应战牌.id], "dst_ids": [3],
		})
		引擎.on_message(3, GConst.Msg.Respond, {
			"respond_id": GConst.RespondType.ReplyAttack, "src_id": 3,
			"args": [GConst.Reattack.GiveUp], "card_ids": [], "dst_ids": [],
		})
		var 转换鬼火: int = int((引擎.p(1).tokens[0] as Dictionary).get("num", -1))
		var 转换手牌: int = 引擎.p(1).hand_cards.size()
		var 转换伤害: int = -1
		for r: Dictionary in 发送记录:
			if int(r["msg"]) == GConst.Msg.Hurt \
					and int((r["data"] as Dictionary).get("dst_id", -1)) == 3:
				转换伤害 = int((r["data"] as Dictionary).get("hurt", -1))
		检(转换鬼火 == 2, "阴阳转换 + 式神转换后鬼火应为 2，实际 %d" % 转换鬼火)
		检(转换手牌 == 1, "式神转换的摸牌没有走标准流程（应战牌弃掉后应摸回 1 张，实际 %d 张）" % 转换手牌)
		检(转换伤害 == 2, "式神形态下鬼火 2 的反击伤害应为 2，实际 %d" % 转换伤害)
		检(not 引擎.p(1).tap, "阴阳转换结算后没有退出式神形态")

	# 欺诈虚牌无命格：同命格应战牌不能选，3306 的「阴阳转换」两档都必须置灰
	引擎._states.clear()
	引擎._清空等待()
	引擎.phase = BattleEngine.Phase.Playing
	引擎.p(1).hand_cards = [应战牌.id] as Array[int]
	引擎.p(1).tap = false
	引擎.p(1).tokens[0]["num"] = 0
	引擎.p(3).hand_cards.clear()
	发送记录.clear()
	var 虚牌攻击: Dictionary = {
		"src": 2, "dst": 1, "point": BattleEngine.ATTACK_BASE_POINT,
		"cause": GConst.CAUSE_ATTACK, "type": GConst.HarmType.Attack, "card_id": 攻击牌.id,
		"virtual_no_fate": true,
	}
	引擎.push(BattleEngine.SAttackCard.new(2, 1, 攻击牌.id, 虚牌攻击))
	引擎.run()
	var 虚牌问3306: Dictionary = {}
	for r: Dictionary in 发送记录:
		if int(r["pid"]) == 1 and int(r["msg"]) == GConst.Msg.CmdReq:
			var cmds: Array = (r["data"] as Dictionary).get("commands", [])
			if not cmds.is_empty() and int((cmds[0] as Dictionary).get("respond_id", 0)) == GConst.技能_阴阳转换:
				虚牌问3306 = cmds[0]
	检(not 虚牌问3306.is_empty(), "无命格虚牌攻击仍应弹 3306 询问（三档照摆）")
	if not 虚牌问3306.is_empty():
		var 虚牌可用: Array = 虚牌问3306.get("option_enabled", [])
		检(虚牌可用.size() == 3 and bool(虚牌可用[0]) \
				and not bool(虚牌可用[1]) and not bool(虚牌可用[2]),
			"无命格虚牌不应允许阴阳转换两档：%s" % str(虚牌可用))
		发送记录.clear()
		引擎.on_message(1, GConst.Msg.Respond, {
			"respond_id": GConst.技能_阴阳转换, "src_id": 1,
			"args": [2], "card_ids": [应战牌.id], "dst_ids": [3],
		})
		var 虚牌鬼火: int = int((引擎.p(1).tokens[0] as Dictionary).get("num", -1))
		检(虚牌鬼火 == 0, "硬提交阴阳转换也不应给无命格虚牌加鬼火，实际 %d" % 虚牌鬼火)

	print("[自检] 阴阳转换引擎：3306 一次应答直接应战，不再问第二次")
