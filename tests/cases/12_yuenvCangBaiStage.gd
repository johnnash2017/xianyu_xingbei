extends 自检用例
## 用例 12g：苍白之月只有两项；第二项点进去后本地再选 1/2 点【新月】，
## 第二步选完之前不提交服务端。

func _init() -> void:
	名称 = "月女苍白两步选项"


func 跑() -> void:
	await 等帧(2)
	var 牌: GCard = null
	for c: GCard in Data.card_db:
		if not c.is_virtual:
			牌 = c
			break
	检(牌 != null, "找不到一张手牌")
	if 牌 == null:
		return

	var 引擎: BattleEngine = BattleEngine.new()
	引擎.add_player(1, GConst.BLUE, "月女")
	引擎.add_player(2, GConst.RED, "对手")
	引擎.start_with_roles({1: 35, 2: 0})
	引擎._states.clear()
	引擎._清空等待()
	引擎.phase = BattleEngine.Phase.Playing
	var 月女: BattlePlayer = 引擎.p(1)
	月女.gem = 1
	月女.tokens[0]["num"] = 2
	月女.tokens[1]["num"] = 3
	月女.hand_cards = [牌.id] as Array[int]
	var 角色: BattleRole = 月女.role
	var 选项: Array = 角色._cang_bai_choices()
	检(选项.size() == 2, "苍白之月应只有两个选项：%s" % str(选项))
	if 选项.size() == 2:
		检(str(选项[0].get("text", "")) == "移除3点【石化】+1无法应战【攻击行动】。+1回合。",
			"第一项文案不对：%s" % str(选项[0].get("text", "")))
		检((选项[1].get("args", []) as Array) == [2],
			"第二项第一段不应带具体新月数：%s" % str(选项[1].get("args", [])))
		检(bool(选项[1].get("enabled", false)), "有手牌且有对手时第二项应可用")

	# 条件不满足的项也要摆出来，只是置灰
	月女.tokens[1]["num"] = 0
	月女.tokens[0]["num"] = 1
	var 缺料选项: Array = 角色._cang_bai_choices()
	检(缺料选项.size() == 2, "石化不足时第一项不应整项消失：%s" % str(缺料选项.size()))
	if 缺料选项.size() == 2:
		检(not bool(缺料选项[0].get("enabled", true)), "石化不足时第一项应置灰")
		检(bool(缺料选项[1].get("enabled", false)), "新月 1 点且有手牌时第二项仍可用")
	月女.tokens[1]["num"] = 3
	月女.tokens[0]["num"] = 2

	# 苍白之月给的额外行动是 direct：行动询问本身也要带 extra_cause，客户端才能写「无法应战」
	var 直接命令: Array = 引擎.action_commands(1, GConst.ActionType.Attack, true, true, false, GConst.技能_苍白之月)
	检(not 直接命令.is_empty() and bool((直接命令[0] as Dictionary).get("is_extra", false)),
		"额外攻击行动询问没有标记 is_extra")
	检(int((直接命令[0] as Dictionary).get("extra_cause", 0)) == GConst.技能_苍白之月,
		"额外行动询问没有把来源（苍白之月）带下来：%s" % str((直接命令[0] as Dictionary).get("extra_cause", 0)))

	# UI 第二步：点第二项后只摆 1/2 点【新月】，选中 X 后 _已选参数 才是 [2, X]
	var 旧id: int = Logic.my_player_id
	var 旧玩家: Array[GPlayer] = Data.player_list
	Logic.my_player_id = 1
	var 我: GPlayer = GPlayer.new(1, GConst.BLUE, "月女")
	我.tokens = [GPlayer.Token.new("新月", 2, 1), GPlayer.Token.new("石化", 3, 3), null]
	var 敌: GPlayer = GPlayer.new(2, GConst.RED, "对手")
	Data.player_list = [我, 敌] as Array[GPlayer]
	var 窗: Control = (load("res://scenes/BattleUIMobile.tscn") as PackedScene).instantiate()
	add_child(窗)
	await 等帧(2)
	窗.set("_mode", 4)
	窗.set("_pending_skill_id", GConst.技能_苍白之月)
	窗.set("_二级栏", true)
	窗.set("_二级栏父技能号", GConst.技能_苍白之月)
	窗.set("_二级栏父按钮", null)
	窗.set("_skill_arg_choices", [
		{"text": "移除3点【石化】+1无法应战【攻击行动】。+1回合。", "args": [1]},
		{"text": "移除X点【新月】+1【石化】，弃 1 张牌。对目标对手造成 X+1点法术伤害。",
			"args": [2], "need_card": 1, "need_target": 1, "targets": [2]},
	])
	窗.set("_已选参数", [2])
	窗.call("_进入苍白月第二段")
	检(bool(窗.get("_苍白第二步")), "点第二项后应进入本地第二步")
	var 二段: Array = 窗.get("_二级选项")
	检(二段.size() == 2, "新月 2 点时应摆出移除 1 点 / 2 点两项：%s" % str(二段.size()))
	if 二段.size() == 2:
		检((二段[0].get("参数", []) as Array) == [2, 1], "第二步第一项应是移除 1 点")
		检((二段[1].get("参数", []) as Array) == [2, 2], "第二步第二项应是移除 2 点")
		检(bool(二段[1].get("可用", true)) == false, "新月只有 1 点时「移除 2 点」应显示但置灰")
	窗.call("_选中二级选项", GConst.技能_苍白之月, 0)
	检((窗.get("_已选参数") as Array) == [2, 1], "第二步选 1 点后参数应为 [2, 1]")

	# 第二步取消＝退回第一层两项，而不是取消整个技能
	窗.call("_on_cancel")
	检(not bool(窗.get("_苍白第二步")), "取消第二步后应回到第一层")
	var 回一层: Array = 窗.get("_二级选项")
	检(回一层.size() == 2, "取消第二步后应重新摆出第一层两项：%s" % str(回一层.size()))
	if 回一层.size() == 2:
		检((回一层[0].get("参数", []) as Array) == [1], "第一层第一项仍是石化")
		检((回一层[1].get("参数", []) as Array) == [2], "第一层第二项仍不带新月数")
	检((窗.get("_已选参数") as Array).is_empty(), "退回第一层后不应保留第二步的 [2, X] 参数")
	检(int(窗.get("_skill_target_max")) == 0 and int(窗.get("_need_players")) == 0,
		"回到第一层后不应再点亮目标（第一项不需要目标）")

	Logic.my_player_id = 旧id
	Data.player_list = 旧玩家
	窗.queue_free()
