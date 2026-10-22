extends 自检用例
## 用例 12：月女【新月庇护】应在队友超限弃牌前询问；
## 发动时把“本次本来要弃的那几张牌”变成【暗月】、本次不掉士气；不发动才正常弃牌 + 掉士气。

func _init() -> void:
	名称 = "月女新月庇护引擎"


func 跑() -> void:
	await 等帧(2)

	var 牌号: Array[int] = []
	for c: GCard in Data.card_db:
		if not c.is_virtual:
			牌号.append(c.id)
		if 牌号.size() >= 4:
			break
	检(牌号.size() >= 4, "找不到 4 张实体牌做手牌")
	if 牌号.size() < 4:
		return

	var 引擎: BattleEngine = BattleEngine.new()
	引擎.add_player(1, GConst.BLUE, "月女")
	引擎.add_player(2, GConst.BLUE, "队友")
	引擎.add_player(3, GConst.RED, "对手")
	引擎.start_with_roles({1: 35, 2: 0, 3: 0})
	引擎._states.clear()
	引擎._清空等待()
	引擎.phase = BattleEngine.Phase.Playing
	引擎.team_morale[GConst.BLUE] = 10
	引擎.team_morale[GConst.RED] = 10

	var 月女: BattlePlayer = 引擎.p(1)
	var 队友: BattlePlayer = 引擎.p(2)
	月女.tap = false
	月女.cover_cards.clear()
	队友.hand_cards_max = 2
	队友.hand_cards = [牌号[0], 牌号[1], 牌号[2], 牌号[3]] as Array[int]

	# 第一次：发动新月庇护
	引擎.push(BattleEngine.SHandOverflow.new(GConst.CAUSE_ATTACK, GConst.HarmType.Attack))
	引擎.run()
	检(引擎._await_id == 2, "超限没有先让队友选要弃的牌（await=%s）" % str(引擎._await_id))
	引擎.on_message(2, GConst.Msg.Respond, {
		"respond_id": GConst.RespondType.Discard, "src_id": 2,
		"args": [2, GConst.CAUSE_OVERLOAD, 2],
		"card_ids": [牌号[0], 牌号[1]], "dst_ids": [2],
	})
	检(引擎._await_id == 1, "队友选好牌后没有在弃牌前询问月女（await=%s）" % str(引擎._await_id))
	检(int(引擎._pending_respond_id) == 3501, "询问月女的不是新月庇护（respond=%s）" % str(引擎._pending_respond_id))
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 3501, "src_id": 1, "args": [1], "card_ids": [], "dst_ids": [],
	})
	检(月女.cover_cards.size() == 2, "发动后应有 2 张牌变成【暗月】，实际 %d" % 月女.cover_cards.size())
	检(月女.tap, "发动后月女应进入【暗月形态】")
	检(队友.hand_cards.size() == 2, "发动后队友手牌应降到上限 2，实际 %d" % 队友.hand_cards.size())
	检(int(引擎.team_morale[GConst.BLUE]) == 10, "发动后不应掉士气，实际 %d" % int(引擎.team_morale[GConst.BLUE]))

	# 第二次：不发动，正常弃牌 + 掉士气
	月女.tap = false
	月女.cover_cards.clear()
	队友.hand_cards = [牌号[0], 牌号[1], 牌号[2], 牌号[3]] as Array[int]
	引擎.team_morale[GConst.BLUE] = 10
	引擎._states.clear()
	引擎._清空等待()
	引擎.phase = BattleEngine.Phase.Playing
	引擎.push(BattleEngine.SHandOverflow.new(GConst.CAUSE_ATTACK, GConst.HarmType.Attack))
	引擎.run()
	引擎.on_message(2, GConst.Msg.Respond, {
		"respond_id": GConst.RespondType.Discard, "src_id": 2,
		"args": [2, GConst.CAUSE_OVERLOAD, 2],
		"card_ids": [牌号[0], 牌号[1]], "dst_ids": [2],
	})
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 3501, "src_id": 1, "args": [0], "card_ids": [], "dst_ids": [],
	})
	检(月女.cover_cards.is_empty(), "不发动时不应产生【暗月】")
	检(队友.hand_cards.size() == 2, "不发动时队友仍应弃到上限，实际 %d" % 队友.hand_cards.size())
	# 本次超限 2 张＝掉 2 点士气（与原有 SHandOverflow 结算一致）
	检(int(引擎.team_morale[GConst.BLUE]) == 8, "不发动时应掉 2 点士气，实际 %d" % int(引擎.team_morale[GConst.BLUE]))
