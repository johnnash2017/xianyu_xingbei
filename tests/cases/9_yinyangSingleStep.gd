extends 自检用例
## 用例 9：阴阳师【阴阳转换】（3306）直接询问（没有先走式神咒束）时，
## 选效果后同一步选应战牌 + 反击目标，确定一次性提交（不再被第二次应战询问打断）。

func _init() -> void:
	名称 = "阴阳转换单步应战"


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
	]
	Data.player_list = 玩家
	玩家[0].role_id = 33

	# 找两张同命格、非光系的攻击牌：一张当本次攻击牌，一张当应战牌
	var 攻击牌: GCard = null
	var 应战牌: GCard = null
	for c: GCard in Data.card_db:
		if c.is_attack() and c.element_enum() != GConst.CardElement.Darkness:
			攻击牌 = c
			break
	if 攻击牌 != null:
		for c: GCard in Data.card_db:
			if c != 攻击牌 and c.is_attack() and c.element_enum() != GConst.CardElement.Light \
					and c.property_enum() == 攻击牌.property_enum():
				应战牌 = c
				break
	检(攻击牌 != null and 应战牌 != null, "找不到同命格攻击牌，用例前提不成立")
	if 攻击牌 == null or 应战牌 == null:
		await _收尾(null, 旧id, 旧玩家, 旧手牌, 旧盖牌)
		return

	Data.hand_cards = [应战牌] as Array[GCard]
	Data.cover_cards = [] as Array[GCard]
	var 窗: Control = (load("res://scenes/BattleUIMobile.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(窗)
	await 等帧(2)
	Logic.game_info_updated.emit({"is_started": true, "room_id": 8, "blue_morale": 15, "red_morale": 15,
		"blue_gem": 1, "blue_crystal": 0, "red_gem": 1, "red_crystal": 0})
	await 等帧(2)

	# 3306 直接询问（没有先走式神咒束）：三档都摆出来，仅应战本次用不了 → 置灰
	Logic.command_received.emit({
		"cmd_type": GConst.CmdType.Respond,
		"commands": [{
			"respond_id": GConst.技能_阴阳转换,
			"src_id": 1, "dst_ids": [], "card_ids": [],
			"args": [0, 0, GConst.CardSource.Hand, 3, 1, 2, 3],
			"notes": ["仅应战", "发动阴阳转换并应战（+1 鬼火）",
				"发动阴阳转换，再发动式神转换并应战（摸 1 张，+2 鬼火）"],
			"is_skill": true,
			"preview_base": 攻击牌.id,
			"preview_ids": [2],
			"option_enabled": [false, true, true],
		}],
	})
	await 等帧(2)
	检(int(窗.get("_mode")) == 3, "3306 询问没有进入应答态（_mode=%s）" % str(窗.get("_mode")))
	var 首问选项: Array = 窗.get("_二级选项") as Array
	检(首问选项.size() == 3, "3306 的二级技能栏没摆出三档效果")
	# 阴阳转换询问的提示条应是技能说明，不是自定义操作指引
	var 阴阳说明: String = "【%s】：%s" % [GConst.skill_name(GConst.技能_阴阳转换),
		GConst.skill_desc(GConst.技能_阴阳转换).replace("\\n", "").replace("\n", "").strip_edges()]
	检(str(窗.get("_提示原文")) == 阴阳说明,
		"阴阳转换询问的提示不是技能说明：%s" % str(窗.get("_提示原文")))
	if 首问选项.size() == 3:
		检((首问选项[0]["按钮"] as 技能按钮).plateButton.disabled, "用不了的「仅应战」没有置灰")
		检(not (首问选项[1]["按钮"] as 技能按钮).plateButton.disabled, "可用的阴阳转换选项被置灰了")
		检(not (首问选项[2]["按钮"] as 技能按钮).plateButton.disabled, "可用的式神转换选项被置灰了")
	# 还没选效果：牌和目标都不能点（避免拿普通规则误选）
	检(not bool(窗.call("_卡牌能点", 应战牌.id)), "还没选效果就能点应战牌")
	检(not bool(窗.call("_玩家可选", 3)), "还没选效果就能点反击目标")
	var 确定: Button = 窗.get("BtnOK")
	检(确定.disabled, "还没选效果，「确定」就已经可用")

	# 点「发动阴阳转换」这一档（index 1）：立即放开选牌 / 选目标
	窗.call("_选中二级选项", GConst.技能_阴阳转换, 1)
	await 等帧()
	检(bool(窗.get("_攒应战选应战")), "点效果后没有进入同一步选应战")
	检(bool(窗.call("_卡牌能点", 应战牌.id)), "阴阳转换下同命格应战牌点不动")
	检(str(窗.get("_提示原文")).find("命格的斩应战，再选择攻击目标") >= 0,
		"阴阳转换提示没有写成「命格的斩 / 攻击目标」：%s" % str(窗.get("_提示原文")))
	检(bool(窗.call("_玩家可选", 3)), "反击目标没有亮起")
	检(not bool(窗.call("_玩家可选", 1)), "自己不该成为反击目标")
	检(not bool(窗.call("_玩家可选", 2)), "原攻击者不该成为反击目标")
	检(确定.disabled, "只选了效果、还没选牌时「确定」不该可用")

	# 先点目标、再点牌（顺序不限），确定应可点
	窗.call("_on_player_clicked", 3)
	await 等帧()
	窗.call("_on_card_clicked", 应战牌.id)
	await 等帧()
	检((窗.get("_sel_cards") as Array) == [应战牌.id], "点应战牌后没有被选中")
	检((窗.get("_sel_players") as Array) == [3], "先点的反击目标被清掉了")
	检(not 确定.disabled, "牌和目标都选好后「确定」仍不可用")

	# 头像上的伤害预览：不在式神形态时按普通应战基础伤害，进入式神形态后才显示鬼火数
	var 头像提示: Dictionary = 窗.call("_攒应战头像提示")
	检(str(头像提示.get(3, "")) == "%d 攻击伤害" % BattleEngine.ATTACK_BASE_POINT,
		"不在式神形态时不应预览鬼火伤害：%s" % str(头像提示))
	玩家[0].tap = true
	头像提示 = 窗.call("_攒应战头像提示")
	var 预期鬼火伤害: int = mini(int(窗.call("_我的鬼火数")) + 1, int(窗.call("_我的鬼火上限")))
	检(str(头像提示.get(3, "")) == "%d 攻击伤害" % 预期鬼火伤害,
		"式神形态下应预览鬼火伤害：%s" % str(头像提示))
	玩家[0].tap = false

	# 切换效果（阴阳转换 → 阴阳转换+式神转换）应保留已选牌与目标，只是重新校验合法性
	窗.call("_选中二级选项", GConst.技能_阴阳转换, 2)
	await 等帧()
	检((窗.get("_sel_cards") as Array) == [应战牌.id], "切换效果后已选应战牌被清掉了")
	检((窗.get("_sel_players") as Array) == [3], "切换效果后已选反击目标被清掉了")
	检(not 确定.disabled, "切换效果后「确定」反而不可用了")
	# 再切回原来的效果，仍应保留
	窗.call("_选中二级选项", GConst.技能_阴阳转换, 1)
	await 等帧()
	检((窗.get("_sel_cards") as Array) == [应战牌.id] and (窗.get("_sel_players") as Array) == [3],
		"切回效果后已选牌 / 目标没有保留")

	# 确定：一次性提交，界面回到等待态（不再弹第二次询问）
	窗.call("_on_ok")
	await 等帧(2)
	检(int(窗.get("_mode")) == 0, "点确定后没有一次性提交（_mode=%s）" % str(窗.get("_mode")))
	检(not bool(窗.get("_攒应战选应战")), "提交后仍停在阴阳转换选应战状态")
	# 提交后「同命格」许可必须撤掉，否则下一次普通应战也会按同命格过滤（圣光 / 同系牌全点不动）
	检(not bool(窗.get("_应战同命格")), "提交后「同命格」许可没有清掉")
	检(int(窗.get("_攒应战回退攻击牌")) == 攻击牌.id and int(窗.get("_攒应战回退选择")) == 2,
		"提交后没有记下回退用的攻击牌 / 选择")

	# 服务器万一回退成普通应战询问（同一张攻击牌）：客户端要把同命格过滤恢复
	Logic.command_received.emit({
		"cmd_type": GConst.CmdType.Respond,
		"commands": [{
			"respond_id": GConst.RespondType.ReplyAttack,
			"args": [GConst.HitRate.Normal, 攻击牌.id, 1, 3],
		}],
	})
	await 等帧(2)
	检(int(窗.get("_mode")) == 2, "回退的应战询问没有进入响应态（_mode=%s）" % str(窗.get("_mode")))
	检(bool(窗.get("_应战同命格")), "回退的应战询问没有恢复同命格过滤")
	(窗.get("BtnCancel") as Button).pressed.emit()
	await 等帧(2)
	检(int(窗.get("_mode")) == 0, "回退的应战询问取消失败")
	检(not bool(窗.get("_应战同命格")), "放弃应战后「同命格」许可没有清掉")

	# 切换效果后，新效果下不再合法的牌要丢掉，合法的目标仍保留
	var 同命格异系牌: GCard = null
	var 同系应战牌: GCard = null
	for c: GCard in Data.card_db:
		if c == 攻击牌 or not c.is_attack():
			continue
		var 元: int = c.element_enum()
		if 元 == GConst.CardElement.Light or 元 == GConst.CardElement.Darkness:
			continue
		if 元 == 攻击牌.element_enum() and c.id != 攻击牌.id:
			同系应战牌 = c
		if c.property_enum() == 攻击牌.property_enum() and 元 != 攻击牌.element_enum():
			同命格异系牌 = c
		if 同系应战牌 != null and 同命格异系牌 != null:
			break
	检(同命格异系牌 != null and 同系应战牌 != null, "找不到「同命格异系 / 同系应战」牌，用例前提不成立")
	if 同命格异系牌 != null and 同系应战牌 != null:
		Data.hand_cards = [同命格异系牌, 同系应战牌] as Array[GCard]
		Logic.command_received.emit({
			"cmd_type": GConst.CmdType.Respond,
			"commands": [{
				"respond_id": GConst.技能_阴阳转换,
				"src_id": 1, "dst_ids": [], "card_ids": [],
				"args": [0, 0, GConst.CardSource.Hand, 3, 1, 2, 3],
				"notes": ["仅应战", "发动阴阳转换并应战（+1 鬼火）",
					"发动阴阳转换，再发动式神转换并应战（摸 1 张，+2 鬼火）"],
				"is_skill": true,
				"preview_base": 攻击牌.id,
				"preview_ids": [2],
			}],
		})
		await 等帧(2)
		# 先选「阴阳转换」档（index 1），拿同命格异系牌 + 目标
		窗.call("_选中二级选项", GConst.技能_阴阳转换, 1)
		await 等帧()
		窗.call("_on_card_clicked", 同命格异系牌.id)
		await 等帧()
		窗.call("_on_player_clicked", 3)
		await 等帧()
		检((窗.get("_sel_cards") as Array) == [同命格异系牌.id], "阴阳转换档下同命格异系牌没有选中")
		# 切到「仅应战」（index 0）：这张牌不合法应丢掉；目标仍合法应保留
		窗.call("_选中二级选项", GConst.技能_阴阳转换, 0)
		await 等帧()
		检((窗.get("_sel_cards") as Array).is_empty(), "切换效果后不合法的应战牌没有丢掉")
		检((窗.get("_sel_players") as Array) == [3], "切换效果后合法的反击目标被清掉了")
		# 补选一张同系应战牌后应能确定
		窗.call("_on_card_clicked", 同系应战牌.id)
		await 等帧()
		检((窗.get("_sel_cards") as Array) == [同系应战牌.id], "补选同系应战牌后没有选中")
		检(not (窗.get("BtnOK") as Button).disabled, "补选合法应战牌后「确定」不可用")
		窗.call("_on_ok")
		await 等帧(2)
		检(int(窗.get("_mode")) == 0, "仅应战没有一次性提交（_mode=%s）" % str(窗.get("_mode")))

	# 仅应战 + 圣光：抵挡不需要反击目标
	var 圣光: GCard = null
	for c: GCard in Data.card_db:
		if c.card_name_enum() == GConst.CardName.HolyLight:
			圣光 = c
			break
	检(圣光 != null, "卡库里找不到【圣光】")
	if 圣光 != null:
		Data.hand_cards = [圣光] as Array[GCard]
		Logic.command_received.emit({
			"cmd_type": GConst.CmdType.Respond,
			"commands": [{
				"respond_id": GConst.技能_阴阳转换,
				"src_id": 1, "dst_ids": [], "card_ids": [],
				"args": [0, 0, GConst.CardSource.Hand, 3, 1, 2, 3],
				"notes": ["仅应战", "发动阴阳转换并应战（+1 鬼火）",
					"发动阴阳转换，再发动式神转换并应战（摸 1 张，+2 鬼火）"],
				"is_skill": true,
				"preview_base": 攻击牌.id,
				"preview_ids": [2],
			}],
		})
		await 等帧(2)
		窗.call("_选中二级选项", GConst.技能_阴阳转换, 0)
		await 等帧()
		检(bool(窗.call("_卡牌能点", 圣光.id)), "仅应战下【圣光】点不动")
		检(bool(窗.call("_玩家可选", 3)), "仅应战下反击目标应仍可点")
		窗.call("_on_card_clicked", 圣光.id)
		await 等帧()
		检((窗.get("_sel_players") as Array).is_empty(), "选【圣光】后反击目标没有清掉")
		检(not (窗.get("BtnOK") as Button).disabled, "仅应战选【圣光】后「确定」不可用")
		窗.call("_on_ok")
		await 等帧(2)
		检(int(窗.get("_mode")) == 0, "【圣光】抵挡没有一次性提交（_mode=%s）" % str(窗.get("_mode")))

		# 服务端：把应战牌/目标预置给引擎紧接着的应战询问（不再弹第二次询问）
		var 引擎: BattleEngine = BattleEngine.new()
		var 服务端玩家: BattlePlayer = BattlePlayer.new(1, GConst.BLUE, "我")
		服务端玩家.hand_cards = [应战牌.id]
		var 角色: BattleRole = load("res://scripts/battle/roles/role_yinyang.gd").new()
		角色.setup(服务端玩家, 引擎)
		角色.call("_预置应战答复", {"args": [2], "card_ids": [应战牌.id], "dst_ids": [3]})
		var 预置: Dictionary = 引擎.take_prepared_reply(1)
		var 预置args: Array = 预置.get("args", [])
		检(not 预置.is_empty() and int(预置args[0]) == GConst.Reattack.Attack,
			"应战牌没有按「应战」预置给引擎")
		检((预置.get("card_ids", []) as Array) == [应战牌.id]
			and (预置.get("dst_ids", []) as Array) == [3], "预置的应战牌 / 反击目标不对")
		# 【圣光】按「抵挡」预置，不需要目标
		服务端玩家.hand_cards = [圣光.id]
		角色.call("_预置应战答复", {"args": [1], "card_ids": [圣光.id], "dst_ids": []})
		预置 = 引擎.take_prepared_reply(1)
		预置args = 预置.get("args", [])
		检(not 预置.is_empty() and int(预置args[0]) == GConst.Reattack.Block,
			"【圣光】没有按「抵挡」预置给引擎")
		# 攻击牌缺目标：不预置，退回引擎的普通应战询问
		角色.call("_预置应战答复", {"args": [2], "card_ids": [应战牌.id], "dst_ids": []})
		检(引擎.take_prepared_reply(1).is_empty(), "应战牌缺反击目标时不应预置")

	# 手里没有对应牌：3306 仍要弹出，三档全部显示但都点不了，只能取消
	Data.hand_cards = [] as Array[GCard]
	Logic.command_received.emit({
		"cmd_type": GConst.CmdType.Respond,
		"commands": [{
			"respond_id": GConst.技能_阴阳转换,
			"src_id": 1, "dst_ids": [], "card_ids": [],
			"args": [0, 0, GConst.CardSource.Hand, 3, 1, 2, 3],
			"notes": ["仅应战", "发动阴阳转换并应战（+1 鬼火）",
				"发动阴阳转换，再发动式神转换并应战（摸 1 张，+2 鬼火）"],
			"is_skill": true,
			"preview_base": 攻击牌.id,
			"preview_ids": [2],
			"option_enabled": [false, false, false],
		}],
	})
	await 等帧(2)
	var 无牌选项: Array = 窗.get("_二级选项") as Array
	检(无牌选项.size() == 3, "没有对应牌时 3306 仍应摆出三档选项")
	for 项: Dictionary in 无牌选项:
		检((项["按钮"] as 技能按钮).plateButton.disabled, "没有对应牌时选项没有置灰")
	检((窗.get("BtnOK") as Button).disabled, "没有可用选项时「确定」不该可用")
	检(str(窗.get("_提示原文")).find("当前没有可用的应战方式") >= 0,
		"三档全灰时提示条没有说明只能取消：%s" % str(窗.get("_提示原文")))
	(窗.get("BtnCancel") as Button).pressed.emit()
	await 等帧(2)
	检(int(窗.get("_mode")) == 0, "三档全灰时点取消没有退出询问")

	await _收尾(窗, 旧id, 旧玩家, 旧手牌, 旧盖牌)
	print("[自检] 阴阳转换：选效果 → 同一步选牌选目标 → 确定一次性提交")


func _收尾(窗: Node, 旧id: int, 旧玩家: Array[GPlayer], 旧手牌: Array[GCard], 旧盖牌: Array[GCard]) -> void:
	if 窗 != null:
		窗.queue_free()
	Logic.my_player_id = 旧id
	Data.player_list = 旧玩家
	Data.hand_cards = 旧手牌
	Data.cover_cards = 旧盖牌
	await 等帧(2)
