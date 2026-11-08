extends 自检用例
## 用例 12b：美杜莎之眼的同系【暗月】白名单、两个按钮的可用状态与对手目标白名单。

func _init() -> void:
	名称 = "月女美杜莎引擎"


func 跑() -> void:
	await 等帧(2)
	var 攻击牌: GCard = null
	var 同系普通: GCard = null
	var 同系法术: GCard = null
	var 异系法术: GCard = null
	for c: GCard in Data.card_db:
		if c.is_virtual:
			continue
		if 攻击牌 == null and c.is_attack() \
				and c.element_enum() != GConst.CardElement.Light \
				and c.element_enum() != GConst.CardElement.Darkness:
			攻击牌 = c
	if 攻击牌 != null:
		for c: GCard in Data.card_db:
			if c.is_virtual or c.id == 攻击牌.id:
				continue
			if 同系普通 == null and c.element_enum() == 攻击牌.element_enum() and not c.is_magic():
				同系普通 = c
			if 同系法术 == null and c.element_enum() == 攻击牌.element_enum() and c.is_magic():
				同系法术 = c
			if 异系法术 == null and c.element_enum() != 攻击牌.element_enum() and c.is_magic():
				异系法术 = c
	检(攻击牌 != null and 同系普通 != null and 同系法术 != null and 异系法术 != null,
		"找不到美杜莎测试所需的同系普通 / 同系法术 / 异系法术牌")
	if 攻击牌 == null or 同系普通 == null or 同系法术 == null or 异系法术 == null:
		return

	var 手牌: GCard = null
	for c: GCard in Data.card_db:
		if c.is_virtual or c.id == 同系普通.id or c.id == 同系法术.id or c.id == 异系法术.id:
			continue
		手牌 = c
		break
	检(手牌 != null, "找不到一张手牌给美杜莎弃")
	if 手牌 == null:
		return

	var 引擎: BattleEngine = BattleEngine.new()
	引擎.add_player(1, GConst.BLUE, "月女")
	引擎.add_player(2, GConst.BLUE, "队友")
	引擎.add_player(3, GConst.RED, "对手")
	引擎.start_with_roles({1: 35, 2: 0, 3: 0})
	引擎._states.clear()
	引擎._清空等待()
	引擎.phase = BattleEngine.Phase.Playing
	var 月女: BattlePlayer = 引擎.p(1)
	月女.cover_cards = [同系普通.id, 同系法术.id, 异系法术.id] as Array[int]
	月女.hand_cards = [手牌.id] as Array[int]

	var harm: Dictionary = {
		"src": 3, "dst": 2, "point": 2,
		"cause": GConst.CAUSE_ATTACK, "type": GConst.HarmType.Attack, "card_id": 攻击牌.id,
	}
	引擎.push(BattleEngine.SAttackCard.new(3, 2, 攻击牌.id, harm))
	引擎.run()
	检(引擎._await_id == 1, "对手攻击后没有询问月女美杜莎（await=%s）" % str(引擎._await_id))
	检(int(引擎._pending_respond_id) == 3503, "询问月女的不是美杜莎（respond=%s）" % str(引擎._pending_respond_id))

	var 问: Dictionary = {}
	for r: Dictionary in 引擎._最后询问.get(1, {}).get("commands", []):
		if int(r.get("respond_id", 0)) == 3503:
			问 = r
	检(not 问.is_empty(), "没有找到发给月女的美杜莎询问")
	if 问.is_empty():
		return
	检((问.get("card_ids", []) as Array) == [同系普通.id, 同系法术.id, 手牌.id],
		"可选牌应是同系暗月 + 手牌：%s" % str(问.get("card_ids", [])))
	检(int(问.get("cover_need", 0)) == 1,
		"应要求至少 1 张盖牌：%s" % str(问.get("cover_need", 0)))
	检((问.get("option_need_cards", []) as Array) == [1, 2],
		"普通分支选 1 张、法术牌分支选 2 张（暗月+弃牌）：%s" % str(问.get("option_need_cards", [])))
	var 选项: Array = 问.get("options", [])
	检(选项.size() == 2
		and int((选项[0] as Dictionary).get("hand_need", -1)) == 0
		and int((选项[1] as Dictionary).get("hand_need", -1)) == 1,
		"两个分支的手牌张数应直接下发 0 / 1：%s" % str(选项))
	var 可用: Array = 问.get("option_enabled", [])
	# 两项都可用时服务端省略 option_enabled（客户端按 true 处理）
	检(可用.is_empty() or (可用.size() == 2 and bool(可用[0]) and bool(可用[1])),
		"两个按钮应都可点：%s" % str(可用))
	var 选项目标: Array = 问.get("option_targets", [])
	检(选项目标.size() == 2 and (选项目标[1] as Dictionary).get("ids", []) == [3],
		"法术牌分支的目标白名单应只有对手 3：%s" % str(选项目标))

	# 法术牌分支：暗月盖牌 + 手牌 + 目标一次交；服务端不应再单独问一次弃牌
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 3503, "src_id": 1, "args": [2],
		"card_ids": [同系法术.id, 手牌.id], "dst_ids": [3],
	})
	检(not 月女.hand_cards.has(手牌.id), "同一步交上来的手牌应立即弃掉")
	检(not 月女.cover_cards.has(同系法术.id), "该张法术牌【暗月】应被移除")
	检(int((月女.tokens[1] as Dictionary).get("num", 0)) == 1, "应 +1【石化】")
	var 又弃: bool = false
	for r: Dictionary in 引擎._最后询问.get(1, {}).get("commands", []):
		if int(r.get("respond_id", 0)) == GConst.RespondType.Discard:
			又弃 = true
	检(not 又弃, "不应再单独弹出一次弃牌询问")
