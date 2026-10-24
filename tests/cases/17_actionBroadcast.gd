extends 自检用例
## 用例 17：行动播报（头像上飘卡牌名 / 技能名）。
## 前半段测文本规则：真正「打出」才播卡牌名；技能直接写技能名（不加【】）。
## 后半段挂一份真实战斗界面，确认展示卡牌不播、打出的播报确实作为 Label 出现在该玩家头像所在的面板旁。

func _init() -> void:
	名称 = "行动播报文本与显示"


func 跑() -> void:
	await 等帧(1)
	检(Data.card_db.size() >= 2, "卡库没有加载出卡牌，无法验证行动播报")

	var 窗: Control = load("res://scripts/ui/battle_mobile.gd").new()

	# 单张「使用」：卡名带命格后缀，与日志里的写法一致
	var 牌: GCard = Data.card_db[0]
	var 期望单张: String = 牌.card_name
	if not 牌.fate_pattern.is_empty():
		期望单张 += "·" + 牌.fate_pattern
	var 单张: String = str(窗.call("_卡牌播报文本", {
		"type": GConst.CardMsgType.Use, "card_ids": [牌.id],
	}))
	检(单张 == 期望单张, "使用卡牌的播报应为「%s」，实际「%s」" % [期望单张, 单张])

	# 多张：用顿号连接
	var 牌2: GCard = Data.card_db[1]
	var 期望多张: String = 期望单张
	var 名2: String = 牌2.card_name
	if not 牌2.fate_pattern.is_empty():
		名2 += "·" + 牌2.fate_pattern
	期望多张 += "、" + 名2
	var 多张: String = str(窗.call("_卡牌播报文本", {
		"type": GConst.CardMsgType.Use, "card_ids": [牌.id, 牌2.id],
	}))
	检(多张 == 期望多张, "多张卡牌的播报应为「%s」，实际「%s」" % [期望多张, 多张])

	# 展示 / 交给别人：都不算「打出」，不应有播报
	检(str(窗.call("_卡牌播报文本", {
		"type": GConst.CardMsgType.Show, "card_ids": [牌.id],
	})).is_empty(), "展示卡牌不应播报卡牌名")
	检(str(窗.call("_卡牌播报文本", {
		"type": GConst.CardMsgType.Give, "card_ids": [牌.id],
	})).is_empty(), "交牌不应播报卡牌名")

	# 技能名直接显示，不加【】；没有技能号时返回空串
	var 技能名: String = GConst.skill_name(2001)
	var 技能文本: String = str(窗.call("_技能播报文本", {"skill_id": 2001}))
	检(技能文本 == 技能名, "技能播报应为「%s」，实际「%s」" % [技能名, 技能文本])
	检(str(窗.call("_技能播报文本", {"skill_id": 0})).is_empty(), "技能号为 0 时不应播报")

	# 特殊行动：购买 / 合成 / 提炼都有名字，未知值不飘
	检(str(窗.call("_特殊行动播报名", GConst.SpecialAction.Buy)) == "购买", "购买的特殊行动播报名不对")
	检(str(窗.call("_特殊行动播报名", GConst.SpecialAction.Synthesize)) == "合成", "合成的特殊行动播报名不对")
	检(str(窗.call("_特殊行动播报名", GConst.SpecialAction.Extract)) == "提炼", "提炼的特殊行动播报名不对")
	检(str(窗.call("_特殊行动播报名", -1)).is_empty(), "未知特殊行动不应播报")

	# 特殊行动字段必须真的过网络协议（购买 = 0，不能靠 0 当「没有」）
	var 特殊日志: Dictionary = {
		"type": GConst.GossipType.Skill, "txt": "测试 执行【购买】",
		"id": 1, "special_action": GConst.SpecialAction.Buy,
	}
	var 解码日志: Dictionary = ProtoCodec.decode(GConst.Msg.Gossip,
		ProtoCodec.encode(GConst.Msg.Gossip, 特殊日志))
	检(解码日志.has("special_action"), "特殊行动字段没有过 Gossip 协议")
	检(int(解码日志.get("special_action", -1)) == GConst.SpecialAction.Buy,
		"特殊行动过协议后的值不对：%s" % str(解码日志.get("special_action", -1)))

	# 地/火牌当魔弹：识别为【魔弹融合】出牌（头像只飘技能名，不飘地/火牌名）
	var 地火牌: GCard = null
	for c: GCard in Data.card_db:
		if c.element_enum() == GConst.CardElement.Fire or c.element_enum() == GConst.CardElement.Earth:
			地火牌 = c
			break
	var 魔弹号: int = Data.card_id_by_name_enum(GConst.CardName.Missile)
	检(地火牌 != null and 魔弹号 > 0, "卡库里找不到地/火牌或【魔弹】，无法验证魔弹融合播报")
	if 地火牌 != null and 魔弹号 > 0:
		var 测试玩家: GPlayer = GPlayer.new(777, GConst.BLUE, "魔导")
		测试玩家.role_id = 8
		Data.player_list.append(测试玩家)
		var 融合消息: Dictionary = {
			"type": GConst.CardMsgType.Use, "src_id": 777,
			"as_card_id": 魔弹号, "card_ids": [地火牌.id],
		}
		检(bool(窗.call("_是魔弹融合出牌", 融合消息)), "地/火牌当【魔弹】出牌没有被识别为魔弹融合")
		融合消息["as_card_id"] = 0
		检(not bool(窗.call("_是魔弹融合出牌", 融合消息)), "普通地/火牌出牌不应被当成魔弹融合")
		测试玩家.role_id = 9
		融合消息["as_card_id"] = 魔弹号
		检(not bool(窗.call("_是魔弹融合出牌", 融合消息)), "没有魔弹融合的角色不应被当成魔弹融合")
		Data.player_list.erase(测试玩家)

	# 预制体存在，且有正文 / 描边样式（尺寸、字号是观感的一部分）
	var 播报场景: PackedScene = load("res://scenes/prefabs/battlemobile/ActionNameFloat.tscn")
	检(播报场景 != null, "行动播报预制体加载失败")
	if 播报场景 != null:
		var 播报: Label = 播报场景.instantiate() as Label
		检(播报 != null, "行动播报预制体不是 Label")
		if 播报 != null:
			检(播报.get_theme_font_size("font_size") >= 24, "行动播报字号太小，看不清")
			检(播报.get_theme_constant("outline_size") >= 4, "行动播报缺少足够粗的描边，暗底上看不清")
			检(播报.get_theme_color("font_color") == Color.WHITE, "行动播报不是白色字")
			播报.free()

	窗.free()

	# ---- 集成：真实战斗界面里确实出现一行播报 ----
	# 直接调 _排行动播报，不走 Card/Skill 广播：后者还会摊牌、放粒子特效，headless 下没必要测。
	var 旧id: int = Logic.my_player_id
	var 旧玩家: Array[GPlayer] = Data.player_list
	var 旧手牌: Array[GCard] = Data.hand_cards
	var 旧盖牌: Array[GCard] = Data.cover_cards
	Logic.my_player_id = 1
	var 新玩家: Array[GPlayer] = [
		GPlayer.new(1, GConst.BLUE, "我"),
		GPlayer.new(2, GConst.RED, "对手"),
	]
	Data.player_list = 新玩家
	Data.hand_cards = []
	Data.cover_cards = []
	var 战: Control = (load("res://scenes/BattleUIMobile.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(战)
	await 等帧(2)
	Logic.game_info_updated.emit({
		"is_started": true, "room_id": 1,
		"blue_morale": 15, "red_morale": 15, "blue_gem": 0, "blue_crystal": 0,
		"red_gem": 0, "red_crystal": 0,
	})
	await 等帧(2)

	var 根: Control = 战.get("Root")
	var 主面板: 战斗玩家面板 = 战.get("MainPlayer")
	检(根 != null and 主面板 != null and 主面板.ID == 1,
		"战斗界面没有把 1 号玩家放到主面板上（ID=%s）" % str(主面板.ID if 主面板 != null else -999))
	if 根 != null:
		# 展示卡牌（亮牌 / 超限换牌）不是「打出」，不能飘卡牌名
		战.call("_on_card", {
			"type": GConst.CardMsgType.Show, "src_id": 1, "dst_id": 1,
			"card_ids": [牌.id], "is_real": false,
		})
		await 等帧(1)
		var 展示误播: bool = false
		for 子: Node in 根.get_children():
			if 子 is Label and (子 as Label).text == 期望单张:
				展示误播 = true
				break
		检(not 展示误播, "展示卡牌「%s」不应飘出卡牌名" % 期望单张)

		战.call("_排行动播报", 1, "测试技能")
		await 等帧(1)
		var 找到: bool = false
		for 子: Node in 根.get_children():
			if 子 is Label and (子 as Label).text == "测试技能":
				找到 = true
				break
		检(找到, "调用 _排行动播报 后，战斗界面上没有出现「测试技能」这一行")

		# 等上一行播完，再验同名 Skill 连发只飘一次、日志也只记一条
		await get_tree().create_timer(2.4).timeout
		var 日志前: String = str(战.get("_日志"))
		战.call("_on_skill", {"skill_id": 2001, "src_id": 1})
		战.call("_on_skill", {"skill_id": 2001, "src_id": 1})
		await 等帧(1)
		var 技能飘报数: int = 0
		for 子: Node in 根.get_children():
			if 子 is Label and (子 as Label).text == 技能名:
				技能飘报数 += 1
		检(技能飘报数 == 1, "连续两条同名 Skill 通知应只飘一次「%s」，实际 %d 次" % [技能名, 技能飘报数])
		var 新增日志: String = str(战.get("_日志")).substr(日志前.length())
		检(新增日志.count(技能名) == 1,
			"连续两条同名 Skill 通知的日志应只有一条「%s」，实际：%s" % [技能名, 新增日志])

		# 等技能行播完，再验特殊行动的信号能落到头像播报上
		await get_tree().create_timer(2.4).timeout
		Logic.special_action_received.emit(1, GConst.SpecialAction.Buy)
		await 等帧(1)
		var 特殊播报找到: bool = false
		for 子: Node in 根.get_children():
			if 子 is Label and (子 as Label).text == "购买":
				特殊播报找到 = true
				break
		检(特殊播报找到, "收到特殊行动事件后，战斗界面上没有出现「购买」这一行")

	# 等这一行的播放协程走完再拆界面，避免在 await 里被 free
	await get_tree().create_timer(2.4).timeout
	战.queue_free()
	await 等帧(2)
	Data.player_list = 旧玩家
	Data.hand_cards = 旧手牌
	Data.cover_cards = 旧盖牌
	Logic.my_player_id = 旧id
