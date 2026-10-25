extends 自检用例
## 用例 5：技能指示器「切换用法」后对已选内容的重校验 ——
## 目标（普通选择 / 点头像分配）与手牌都要按新用法的白名单复检：合法的保留、不合法的清掉。
## 复现的缺陷：神官【神圣领域】先选「队友」用法并给队友分配 1 点治疗，再切到「敌人」用法时，
## 队友已不在新用法的目标白名单里，却仍留在分配记录里（头像指示器不消、且旧逻辑可被带去误伤队友）。

func _init() -> void:
	名称 = "指示器切用法复检"

func 跑() -> void:
	await 等帧(2)
	UI.goto_lobby()
	await 等帧(2)

	var 旧id: int = Logic.my_player_id
	var 旧玩家: Array[GPlayer] = Data.player_list
	var 旧手牌: Array[GCard] = Data.hand_cards
	var 旧盖牌: Array[GCard] = Data.cover_cards
	Logic.my_player_id = 1
	var 玩家: Array[GPlayer] = [
		GPlayer.new(1, GConst.BLUE, "我"),
		GPlayer.new(2, GConst.RED, "对手A"),
		GPlayer.new(3, GConst.RED, "对手B"),
		GPlayer.new(4, GConst.BLUE, "队友"),
	]
	Data.player_list = 玩家
	玩家[0].role_id = 15
	var 牌: Array[GCard] = []
	for c: GCard in Data.card_db:
		牌.append(c)
		if 牌.size() >= 2:
			break
	Data.hand_cards = 牌
	Data.cover_cards = []

	var 窗: Control = (load("res://scenes/BattleUIMobile.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(窗)
	await 等帧(2)
	Logic.game_info_updated.emit({"is_started": true, "room_id": 7, "blue_morale": 15, "red_morale": 15,
		"blue_gem": 2, "blue_crystal": 1, "red_gem": 1, "red_crystal": 2})
	await 等帧(2)

	# 神圣领域（1506）：两种用法各带自己的目标白名单（0＝队友含自己；1＝敌人）
	var 选项: Array = [
		{"text": "队友用法", "args": [0], "need_target": 1, "targets": [1, 4]},
		{"text": "敌人用法", "args": [1], "need_target": 1, "targets": [2, 3]},
	]
	窗.call("_选择技能", 1506, GConst.ActionType.MagicSkill, 2, 1, [1, 4, 2, 3], [], 0, 0, 0,
		GConst.CardSource.Hand, "", 0, 0, 选项, null, 0)
	await 等帧(2)
	检(bool(窗.get("_先弹选项")), "神圣领域没进「先弹选项」流程")
	var 二级: Array = 窗.get("_二级选项")
	检(二级.size() == 2, "二级选项数量不对：%d" % 二级.size())
	if 二级.size() == 2:
		检((二级[0]["目标白名单"] as Array) == [1, 4], "用法0 的目标白名单丢了：%s" % str(二级[0]["目标白名单"]))
		检((二级[1]["目标白名单"] as Array) == [2, 3], "用法1 的目标白名单丢了：%s" % str(二级[1]["目标白名单"]))

	# 选「队友」用法 → 给队友（id 4）分配 1 点治疗
	窗.call("_选中二级选项", 1506, 0)
	await 等帧()
	检(bool(窗.call("_玩家可选", 4)), "选了队友用法后队友仍不可点")
	窗.call("_on_player_clicked", 4)
	await 等帧()
	检((窗.get("_治疗分配") as Array) == [4], "队友没被记进分配：%s" % str(窗.get("_治疗分配")))

	# 切到「敌人」用法：队友已不合法，分配记录与头像指示器都必须清掉
	窗.call("_选中二级选项", 1506, 1)
	await 等帧()
	检((窗.get("_治疗分配") as Array).is_empty(),
		"切换用法后不合法的队友仍留在分配里：%s" % str(窗.get("_治疗分配")))
	检(not (窗.get("_sel_players") as Array).has(4), "切换用法后队友头像仍被标为已选")
	检((窗.get("BtnOK") as Button).disabled, "目标不合法时「确定」却是可用的")

	# 冒险家【欺诈】：取消二级技能栏后再次点技能，二级栏必须重新打开
	var 风名: String = Data.get_card(66).card_name
	var 欺诈选项: Array = [
		{"text": "视为%s" % 风名, "args": [66], "element": GConst.CardElement.Wind},
		{"text": "视为%s" % Data.get_card(133).card_name, "args": [133], "element": GConst.CardElement.Water},
		{"text": "视为%s" % Data.get_card(87).card_name, "args": [87], "element": GConst.CardElement.Fire},
		{"text": "视为%s" % Data.get_card(45).card_name, "args": [45], "element": GConst.CardElement.Earth},
		{"text": "视为%s" % Data.get_card(110).card_name, "args": [110], "element": GConst.CardElement.Thunder},
	]
	窗.call("_选择技能", GConst.技能_欺诈, GConst.ActionType.AttackSkill, 2, 1, [2, 3], [], 0, 0, 0,
		GConst.CardSource.Hand, "same", 0, 0, 欺诈选项, null, 0)
	await 等帧(2)
	检(bool(窗.get("_二级栏")), "欺诈第一次没有进入二级技能栏")
	检((窗.get("_二级选项") as Array).size() == 5, "欺诈二级栏没有摆出 5 个虚牌系别")
	if (窗.get("_二级选项") as Array).size() == 5:
		var 首项: Dictionary = (窗.get("_二级选项") as Array)[0]
		var 首钮: 技能按钮 = 首项.get("按钮")
		检(首钮.skillName.text.contains("[color=#9BE7A2]%s[/color]" % 风名),
			"欺诈风系选项应只给卡名上色：%s" % 首钮.skillName.text)
		检(not 首钮.skillName.text.contains("【"),
			"欺诈选项文案不应再用【】包卡名：%s" % 首钮.skillName.text)
	窗.call("_on_cancel")
	await 等帧(2)
	检(not bool(窗.get("_二级栏")), "取消欺诈后二级栏状态没有清掉")
	检(int(窗.get("_need_cards")) == 1, "取消欺诈后行动阶段没有恢复成只选 1 张牌")
	检(str(窗.get("_skill_card_rule")) == "", "取消欺诈后仍残留技能选牌规则")
	检(欺诈选项.size() == 5, "取消欺诈后把技能声明里的原参数选项数组清空了")
	窗.call("_选择技能", GConst.技能_欺诈, GConst.ActionType.AttackSkill, 2, 1, [2, 3], [], 0, 0, 0,
		GConst.CardSource.Hand, "same", 0, 0, 欺诈选项, null, 0)
	await 等帧(2)
	检(bool(窗.get("_二级栏")), "取消欺诈后再次点技能，二级栏没有重新打开")
	检((窗.get("_二级选项") as Array).size() == 5, "取消欺诈后再次点技能，二级栏选项没有重建")

	# 同类选项型技能（偷天换日）：取消后也必须能重新打开二级栏
	var 偷天选项: Array = [
		{"text": "转移对方 1【宝石】", "args": [0]},
		{"text": "我方【水晶】全部转为【宝石】", "args": [1]},
	]
	窗.call("_选择技能", GConst.技能_偷天换日, GConst.ActionType.MagicSkill, 0, 0, [2, 3], [], 0, 0, 0,
		GConst.CardSource.Hand, "", 0, 0, 偷天选项, null, 0)
	await 等帧(2)
	检(bool(窗.get("_二级栏")) and (窗.get("_二级选项") as Array).size() == 2,
		"偷天换日第一次没有进入二级技能栏")
	窗.call("_on_cancel")
	await 等帧(2)
	窗.call("_选择技能", GConst.技能_偷天换日, GConst.ActionType.MagicSkill, 0, 0, [2, 3], [], 0, 0, 0,
		GConst.CardSource.Hand, "", 0, 0, 偷天选项, null, 0)
	await 等帧(2)
	检(bool(窗.get("_二级栏")) and (窗.get("_二级选项") as Array).size() == 2,
		"取消偷天换日后再次点技能，二级栏没有重新打开")

	# 军神威光第一段第二项：点选项应直接提交，不再等玩家按「确定」
	窗.set("_是技能询问", true)
	窗.set("_pending_type", GConst.Msg.Respond)
	窗.set("_skill_ask_id", GConst.技能_军神威光)
	窗.set("_pending", {
		"respond_id": GConst.技能_军神威光, "is_skill": true,
		"args": [0, 0, GConst.CardSource.Hand, 2, 1, 2],
		"notes": ["脱离英灵形态", "移除星石"],
		"can_cancel": false,
	})
	窗.call("_进入技能询问")
	await 等帧(2)
	窗.call("_选中二级选项", GConst.技能_军神威光, 1)
	await 等帧(2)
	检(int(窗.get("_mode")) == 0 and (窗.get("_pending") as Dictionary).is_empty(),
		"点军神威光第一段第二项没有直接提交进入下一段")

	# 军神威光第二段：选项 5 档，必须提供「返回」按钮（服务端把空应答当退回第一段）
	窗.set("_是技能询问", true)
	窗.set("_pending_type", GConst.Msg.Respond)
	窗.set("_skill_ask_id", GConst.技能_军神威光)
	窗.set("_pending", {
		"respond_id": GConst.技能_军神威光, "is_skill": true,
		"args": [0, 1, GConst.CardSource.Hand, 5, 1, 2, 3, 4, 5],
		"notes": ["组合一", "组合二", "组合三", "组合四", "组合五"],
		"can_cancel": true,
	})
	窗.call("_进入技能询问")
	await 等帧(2)
	var 有返回: bool = false
	for 子: Node in 窗.get("_技能按钮"):
		if 子 is 技能按钮 and (子 as 技能按钮).skillName.text == "返回":
			有返回 = true
			break
	检(有返回, "军神威光第二段没有摆出「返回」按钮")
	检(not str(GConst.提示原文(GConst.技能_军神威光, 2)).contains("返回上级"),
		"军神威光第二段提示仍带「返回上级」后缀")

	# 12 号冒险家新版【冒险者天堂】：选完构成后点一次队友，整份星石都给同一人
	玩家[0].role_id = 12
	var 蓝队2: GTeam = Data.team_of(GConst.BLUE)
	蓝队2.gem = 2
	蓝队2.crystal = 1
	窗.call("_选特殊行动", GConst.SpecialAction.Extract)
	await 等帧(2)
	检(bool(窗.get("_提炼全给一人")), "12 号冒险家提炼没有进入整份给一人的流程")
	检(int(窗.get("_提炼阶段")) == 4, "12 号冒险家提炼没有进入选构成步骤")
	var 提炼选项: Array = 窗.get("_二级选项") as Array
	检(not 提炼选项.is_empty(), "12 号冒险家提炼没有列出星石构成")
	if not 提炼选项.is_empty():
		窗.call("_选中二级选项", GConst.技能_冒险者天堂, 0)
		await 等帧()
		var 总颗数: int = int(窗.get("_提炼宝石")) + int(窗.get("_提炼水晶"))
		检(总颗数 >= 1, "12 号冒险家提炼选出的总颗数不对")
		窗.call("_on_player_clicked", 4)
		await 等帧()
		var 分配: Array = 窗.get("_治疗分配")
		检(分配.size() == 总颗数 and 分配.all(func(id: Variant) -> bool: return int(id) == 4),
			"12 号冒险家提炼应把整份星石全部交给同一名队友：%s" % str(分配))
	窗.call("_on_cancel")
	await 等帧(2)

	Logic.my_player_id = 旧id
	Data.player_list = 旧玩家
	Data.hand_cards = 旧手牌
	Data.cover_cards = 旧盖牌
	窗.queue_free()
	await 等帧(3)
