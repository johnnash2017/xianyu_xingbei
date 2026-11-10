extends 自检用例
## 用例 9c：式神咒束（3301）与阴阳转换（3306）共用同一套「攒应战」界面流程。
## 这里单独验证 3301 这条的差异：选项由服务端下发、仅应战不允许【圣光】。

## 客户端发完应答要「稍等一拍（0.15s）再清界面」避免闪屏，断言得等它跑完。
## 按帧轮询（不用计时器：headless 下计时器不推进会把用例挂住）。
func _等提交(p窗: Control) -> void:
	for _i: int in range(600):
		await get_tree().process_frame
		if int(p窗.get("_mode")) == 0:
			return


func _init() -> void:
	名称 = "式神咒束单步应战"


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
	# 3301 只在式神形态下才会被询问
	玩家[0].tap = true

	var 攻击牌: GCard = null
	var 应战牌: GCard = null
	var 备选应战牌: GCard = null
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
			# 优先找「同系 + 同命格」的牌：仅应战和阴阳转换两档都能用
			if c.element_enum() == 攻击牌.element_enum():
				应战牌 = c
				break
			if 备选应战牌 == null:
				备选应战牌 = c
		if 应战牌 == null:
			应战牌 = 备选应战牌
	检(攻击牌 != null and 应战牌 != null and 圣光 != null, "找不到同命格攻击牌 / 圣光，用例前提不成立")
	if 攻击牌 == null or 应战牌 == null or 圣光 == null:
		await _收尾(null, 旧id, 旧玩家, 旧手牌, 旧盖牌)
		return

	Data.hand_cards = [应战牌, 圣光] as Array[GCard]
	Data.cover_cards = [] as Array[GCard]
	var 窗: Control = (load("res://scenes/BattleUIMobile.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(窗)
	await 等帧(2)
	Logic.game_info_updated.emit({"is_started": true, "room_id": 9, "blue_morale": 15, "red_morale": 15,
		"blue_gem": 1, "blue_crystal": 0, "red_gem": 1, "red_crystal": 0})
	await 等帧(2)

	# 3301：替队友应战不能用【圣光】。这里故意不带 can_light / 按默认 true，
	# 客户端也必须按技能号硬拦（不依赖服务端字段）。
	Logic.command_received.emit({
		"cmd_type": GConst.CmdType.Respond,
		"commands": [{
			"respond_id": GConst.技能_式神咒束,
			"src_id": 1, "dst_ids": [], "card_ids": [],
			"args": [0, 0, GConst.CardSource.Hand, 3, 1, 2, 3],
			"notes": ["仅应战", "发动阴阳转换并应战（+1 鬼火）",
				"发动阴阳转换，再发动式神转换并应战（摸 1 张，+2 鬼火）"],
			"is_skill": true,
			"preview_base": 攻击牌.id,
			"preview_ids": [2],
			"preview_damage": 2,
		}],
	})
	await 等帧(2)
	检(int(窗.get("_mode")) == 3, "3301 询问没有进入应答态（_mode=%s）" % str(窗.get("_mode")))
	检(int(窗.get("_攒应战应答号")) == GConst.技能_式神咒束, "3301 没有进入共用的攒应战状态")
	检(not bool(窗.get("_攒应战允圣光")), "3301 替队友应战不应允许【圣光】")
	var 选项: Array = 窗.get("_二级选项") as Array
	检(选项.size() == 3, "3301 的二级技能栏没摆出三档效果")
	检(not bool(窗.call("_卡牌能点", 应战牌.id)), "还没选效果就能点应战牌")

	# 点「仅应战」：只有普通攻击牌能点，【圣光】不能替队友挡
	窗.call("_选中二级选项", GConst.技能_式神咒束, 0)
	await 等帧()
	检(bool(窗.call("_卡牌能点", 应战牌.id)), "3301 的普通应战牌点不动")
	检(not bool(窗.call("_卡牌能点", 圣光.id)), "3301 替队友应战不应允许【圣光】")
	检(str(窗.get("_提示原文")).find("点击头像选择应战目标") >= 0,
		"3301 的仅应战提示没有写「点击头像选择应战目标」：%s" % str(窗.get("_提示原文")))
	检(str(窗.get("_提示原文")).find("代其应战") >= 0,
		"3301 的仅应战提示没有写「代其应战」：%s" % str(窗.get("_提示原文")))
	检(str(窗.get("_提示原文")).find("队友受到 2 点伤害攻击，") >= 0,
		"3301 替队友挡的提示没有带本次伤害说明：%s" % str(窗.get("_提示原文")))

	# 切到「发动阴阳转换」这一档（index 1）：牌和目标放开，【圣光】在阴阳转换下也不能用
	窗.call("_选中二级选项", GConst.技能_式神咒束, 1)
	await 等帧()
	检(bool(窗.get("_攒应战选应战")), "3301 点效果后没有进入同一步选应战")
	检(bool(窗.call("_卡牌能点", 应战牌.id)), "3301 同命格应战牌点不动")
	检(not bool(窗.call("_卡牌能点", 圣光.id)), "阴阳转换下不应允许【圣光】")
	检(str(窗.get("_提示原文")).find("命格的斩代其应战，点击头像选择应战目标") >= 0,
		"3301 的阴阳转换提示没有写成「命格的斩代其应战 / 点击头像」：%s" % str(窗.get("_提示原文")))
	检(bool(窗.call("_玩家可选", 3)), "3301 的反击目标没有亮起")
	检(not bool(窗.call("_玩家可选", 1)) and not bool(窗.call("_玩家可选", 2)),
		"自己 / 原攻击者不该成为反击目标")

	# 选牌和目标后切到「阴阳转换+式神转换」，应保留合法的牌 / 目标
	窗.call("_on_card_clicked", 应战牌.id)
	await 等帧()
	窗.call("_on_player_clicked", 3)
	await 等帧()
	窗.call("_选中二级选项", GConst.技能_式神咒束, 2)
	await 等帧()
	检((窗.get("_sel_cards") as Array) == [应战牌.id], "3301 切换效果后应战牌被清掉了")
	检((窗.get("_sel_players") as Array) == [3], "3301 切换效果后反击目标被清掉了")
	检(not (窗.get("BtnOK") as Button).disabled, "3301 切换效果后「确定」不可用")

	窗.call("_on_ok")
	await _等提交(窗)
	检(int(窗.get("_mode")) == 0, "3301 点确定后没有一次性提交（_mode=%s）" % str(窗.get("_mode")))
	检(int(窗.get("_攒应战应答号")) == 0, "3301 提交后仍停在攒应战状态")

	await _收尾(窗, 旧id, 旧玩家, 旧手牌, 旧盖牌)
	print("[自检] 式神咒束：与阴阳转换共用攒应战，选效果 → 选牌选目标 → 一次提交")


func _收尾(窗: Node, 旧id: int, 旧玩家: Array[GPlayer], 旧手牌: Array[GCard], 旧盖牌: Array[GCard]) -> void:
	if 窗 != null:
		窗.queue_free()
	Logic.my_player_id = 旧id
	Data.player_list = 旧玩家
	Data.hand_cards = 旧手牌
	Data.cover_cards = 旧盖牌
	await 等帧(2)
