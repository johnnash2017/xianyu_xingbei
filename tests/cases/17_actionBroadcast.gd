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

	# 欺诈虚牌没有命格：服务端必须明确标 virtual_no_fate；仅 is_real=false 不能去命格
	var 命格攻击牌: GCard = null
	for c: GCard in Data.card_db:
		if c.is_attack() and not c.fate_pattern.is_empty():
			命格攻击牌 = c
			break
	检(命格攻击牌 != null, "卡库里找不到带命格的攻击牌，无法验证虚拟牌去命格")
	if 命格攻击牌 != null:
		var 期望真实: String = "%s·%s" % [命格攻击牌.card_name, 命格攻击牌.fate_pattern]
		var 真实播报: String = str(窗.call("_卡牌播报文本", {
			"type": GConst.CardMsgType.Use, "card_ids": [命格攻击牌.id], "is_real": true,
		}))
		var 虚拟播报: String = str(窗.call("_卡牌播报文本", {
			"type": GConst.CardMsgType.Use, "card_ids": [命格攻击牌.id],
			"is_real": false, "virtual_no_fate": true,
		}))
		var 有命格虚拟播报: String = str(窗.call("_卡牌播报文本", {
			"type": GConst.CardMsgType.Use, "card_ids": [命格攻击牌.id], "is_real": false,
		}))
		检(真实播报 == 期望真实, "真实牌的播报仍应带命格：%s" % 真实播报)
		检(虚拟播报 == 命格攻击牌.card_name, "无命格虚牌播报不应带命格：%s" % 虚拟播报)
		检(有命格虚拟播报 == 期望真实,
			"其他虚拟牌（如圣屑飓暴的圣命格虚牌）仍应显示命格：%s" % 有命格虚拟播报)
		var 虚牌消息: Dictionary = {
			"type": GConst.CardMsgType.Use, "card_ids": [命格攻击牌.id],
			"is_real": false, "virtual_no_fate": true,
		}
		var 虚牌解码: Dictionary = ProtoCodec.decode(GConst.Msg.Card,
			ProtoCodec.encode(GConst.Msg.Card, 虚牌消息))
		检(bool(虚牌解码.get("virtual_no_fate", false)), "无命格虚牌标记没有过 Card 协议")

	# 选项的系别颜色：字段要过协议；客户端只把卡名染成系别色，不再整段覆盖字色
	var 选项原名: Dictionary = {
		"text": "视为风神斩", "args": [66], "element": GConst.CardElement.Wind,
	}
	var 选项解码: Dictionary = ProtoCodec.decode_named("ArgChoice",
		ProtoCodec.encode_named("ArgChoice", 选项原名))
	检(int(选项解码.get("element", -1)) == GConst.CardElement.Wind,
		"选项系别没有过 ArgChoice 协议：%s" % str(选项解码.get("element", null)))
	# 选项绑技能号（如矜贵之女 7802 第 2 档＝响应 7805 友情羁绊）：字段要过协议，
	# 客户端才能按响应色显示、悬停弹技能说明。
	var 技能选项原名: Dictionary = {"text": "响应友情羁绊", "args": [2], "skill_id": 7805}
	var 技能选项解码: Dictionary = ProtoCodec.decode_named("ArgChoice",
		ProtoCodec.encode_named("ArgChoice", 技能选项原名))
	检(int(技能选项解码.get("skill_id", 0)) == 7805,
		"选项技能号没有过 ArgChoice 协议：%s" % str(技能选项解码.get("skill_id", null)))
	var 技能选项归一: Array = 窗.call("_选项项", [技能选项解码])
	检(not 技能选项归一.is_empty()
		and int((技能选项归一[0] as Dictionary).get("技能号", 0)) == 7805,
		"选项技能号应归一成二级栏的『技能号』：%s" % str(技能选项归一))
	var 归一选项: Array = 窗.call("_选项项", [选项解码])
	var 选项文本: String = ""
	var 选项字色: Color = Color.TRANSPARENT
	if not 归一选项.is_empty():
		选项文本 = str((归一选项[0] as Dictionary).get("文本", ""))
		var 字色值: Variant = (归一选项[0] as Dictionary).get("字色", Color.TRANSPARENT)
		if 字色值 is Color:
			选项字色 = 字色值
	检(选项文本.contains("[color=#9BE7A2]风神斩[/color]"),
		"风系选项只应给卡名「风神斩」上色：%s" % 选项文本)
	检(not 选项文本.contains("【") and not 选项文本.contains("（"),
		"选项文案不应再用括号包说明：%s" % 选项文本)
	检(选项字色.a == 0.0, "选项不应再整段覆盖字色：%s" % str(选项字色))

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

	# 暗之障壁：还没选牌时，第一张也必须是非雷非法术之外的法术 / 雷系牌
	var 非法牌: GCard = null
	var 法术牌: GCard = null
	var 雷牌: GCard = null
	for c: GCard in Data.card_db:
		if 非法牌 == null and not c.is_magic() and c.element_enum() != GConst.CardElement.Thunder:
			非法牌 = c
		if 法术牌 == null and c.is_magic():
			法术牌 = c
		if 雷牌 == null and c.element_enum() == GConst.CardElement.Thunder:
			雷牌 = c
	检(非法牌 != null and 法术牌 != null and 雷牌 != null,
		"卡库里找不到「非雷非法术 / 法术 / 雷系」样本，无法验证暗之障壁选牌规则")
	if 非法牌 != null and 法术牌 != null and 雷牌 != null:
		var 空选: Array[int] = []
		窗.set("_skill_card_rule", "an_zhi")
		窗.set("_sel_cards", 空选)
		检(not bool(窗.call("_符合选牌规则", 非法牌.id)),
			"暗之障壁还没选牌时，非雷非法术的「%s」不应可点" % 非法牌.card_name)
		检(bool(窗.call("_符合选牌规则", 法术牌.id)),
			"暗之障壁还没选牌时，法术牌「%s」应可点" % 法术牌.card_name)
		检(bool(窗.call("_符合选牌规则", 雷牌.id)),
			"暗之障壁还没选牌时，雷系牌「%s」应可点" % 雷牌.card_name)

		# 通用 "magic" 规则（魔能反转等）：也没选牌时非法术牌就应置灰
		窗.set("_skill_card_rule", "magic")
		检(not bool(窗.call("_符合选牌规则", 非法牌.id)),
			"magic 规则还没选牌时，非法术牌「%s」不应可点" % 非法牌.card_name)
		检(bool(窗.call("_符合选牌规则", 法术牌.id)),
			"magic 规则还没选牌时，法术牌「%s」应可点" % 法术牌.card_name)
		窗.set("_skill_card_rule", "")

	# 同系规则的孤张也不应亮：手里凑不出第二张同系牌时，第一张就置灰
	var 同系甲: GCard = null
	var 同系乙: GCard = null
	var 孤张: GCard = null
	for c: GCard in Data.card_db:
		if 同系甲 == null:
			同系甲 = c
		elif 同系乙 == null and c.element_enum() == 同系甲.element_enum():
			同系乙 = c
		elif 孤张 == null and c.element_enum() != 同系甲.element_enum():
			孤张 = c
		if 同系甲 != null and 同系乙 != null and 孤张 != null:
			break
	检(同系甲 != null and 同系乙 != null and 孤张 != null,
		"卡库里找不到同系对 + 异系孤张样本，无法验证同系首张过滤")
	if 同系甲 != null and 同系乙 != null and 孤张 != null:
		var 旧手牌: Array[GCard] = Data.hand_cards
		var 样本手牌: Array[GCard] = [同系甲, 同系乙, 孤张]
		Data.hand_cards = 样本手牌
		var 无选: Array[int] = []
		var 空白: Array[int] = []
		窗.set("_mode", 4)
		窗.set("_skill_need_card", 2)
		窗.set("_skill_card_max", 2)
		窗.set("_skill_card_source", GConst.CardSource.Hand)
		窗.set("_skill_card_rule", "same")
		窗.set("_sel_cards", 无选)
		窗.set("_skill_cards", 空白)
		检(bool(窗.call("_符合选牌规则", 同系甲.id)),
			"同系首张：有同系搭档的「%s」应可点" % 同系甲.card_name)
		检(not bool(窗.call("_符合选牌规则", 孤张.id)),
			"同系首张：没有同系搭档的孤张「%s」不应可点" % 孤张.card_name)

		# 点技能时已经拿起的牌要复检：还能用的继续亮着，不合法的才收回
		var 原选同系: Array[int] = [同系甲.id, 同系乙.id]
		var 留同系: Array = 窗.call("_筛出当前技能可留的牌", 原选同系)
		检(留同系.size() == 2, "点技能时合法的同系对不应被收回，实际只留 %d 张" % 留同系.size())
		var 原选孤张: Array[int] = [孤张.id]
		var 留孤张: Array = 窗.call("_筛出当前技能可留的牌", 原选孤张)
		检(留孤张.is_empty(), "点技能时不合法的孤张应收回")
		# 一张就够的技能：合法的单张必须保留
		窗.set("_skill_need_card", 1)
		窗.set("_skill_card_max", 1)
		窗.set("_skill_card_rule", "")
		var 原选单张: Array[int] = [同系甲.id]
		var 留单张: Array = 窗.call("_筛出当前技能可留的牌", 原选单张)
		检(留单张.size() == 1 and int(留单张[0]) == 同系甲.id,
			"点技能时合法的单张牌不应被收回")
		# 不需要牌的技能：旧选择全部收回
		窗.set("_skill_need_card", 0)
		窗.set("_skill_card_max", 0)
		var 留零张: Array = 窗.call("_筛出当前技能可留的牌", 原选单张)
		检(留零张.is_empty(), "点不需要牌的技能时旧选牌应全部收回")

		# 先弹选项型技能换效果：已经选过效果后，已选牌不能因为“先弹选项”被整批清掉
		窗.set("_skill_need_card", 1)
		窗.set("_skill_card_max", 1)
		窗.set("_skill_card_rule", "")
		窗.set("_先弹选项", true)
		窗.set("_已选参数", [1])
		var 换效果保留: Array = 窗.call("_筛出当前技能可留的牌", 原选单张)
		检(换效果保留.size() == 1, "先弹选项技能换效果时，已选牌被误清空")
		窗.set("_已选参数", [])
		var 未选效果保留: Array = 窗.call("_筛出当前技能可留的牌", 原选单张)
		检(未选效果保留.is_empty(), "先弹选项技能还没选效果时，旧选牌应收回")
		窗.set("_先弹选项", false)

		# 取消技能退回行动阶段：技能通道的选牌上限 / 同组规则必须复位，
		# 否则行动阶段会继续按技能的 2 张、同命格规则点牌。
		窗.set("_need_cards", 2)
		窗.set("_need_players", 1)
		窗.set("_skill_need_card", 2)
		窗.set("_skill_need_target", 1)
		窗.set("_skill_card_max", 2)
		窗.set("_skill_target_max", 1)
		窗.set("_skill_card_rule", "same_fate_pattern")
		窗.set("_skill_card_source", GConst.CardSource.Cover)
		窗.set("_skill_cover_need", 1)
		窗.set("_skill_slot_skill", GConst.技能_死亡之触)
		窗.set("_skill_slot_element", GConst.CardElement.Fire)
		var 技能白名单: Array[int] = [同系甲.id]
		var 技能目标: Array[int] = [1]
		窗.set("_skill_cards", 技能白名单)
		窗.set("_skill_targets", 技能目标)
		窗.call("_复位行动阶段选牌状态")
		检(int(窗.get("_need_cards")) == 1, "取消技能后行动阶段仍按技能的 2 张牌选牌")
		检(int(窗.get("_need_players")) == 0, "取消技能后仍残留技能的目标数")
		检(str(窗.get("_skill_card_rule")) == "", "取消技能后仍残留同系 / 同命格选牌规则")
		检(int(窗.get("_skill_card_max")) == 0 and int(窗.get("_skill_need_card")) == 0,
			"取消技能后仍残留技能的需牌 / 点选上限")
		检(int(窗.get("_skill_card_source")) == GConst.CardSource.Hand, "取消技能后选牌来源没有复位")
		检((窗.get("_skill_cards") as Array).is_empty(), "取消技能后技能白名单没有清空")
		检((窗.get("_skill_targets") as Array).is_empty(), "取消技能后技能目标白名单没有清空")
		检(int(窗.get("_skill_slot_skill")) == 0 and int(窗.get("_skill_slot_element")) == 0,
			"取消技能后逐张槽位条件没有复位")
		Data.hand_cards = 旧手牌
		窗.set("_mode", 0)
		窗.set("_skill_card_rule", "")

	# 同系技能在技能声明里必须带 card_rule="same"，否则会从两个不同系各选一张
	var 死灵引擎: BattleEngine = BattleEngine.new()
	死灵引擎.add_player(1, GConst.BLUE, "规则")
	var 死灵玩家: BattlePlayer = 死灵引擎.p(1)
	死灵玩家.role_id = 13
	var 死灵: BattleRole = BattleRole.create(13, 死灵玩家, 死灵引擎)
	死灵玩家.role = 死灵
	var 死亡项: Dictionary = {}
	for 项: Dictionary in 死灵.available_skills():
		if int(项.get("id", 0)) == GConst.技能_死亡之触:
			死亡项 = 项
	检(str(死亡项.get("card_rule", "")) == "same", "死亡之触没有下发同系选牌规则")
	var 圣弓引擎: BattleEngine = BattleEngine.new()
	圣弓引擎.add_player(1, GConst.BLUE, "规则")
	var 圣弓玩家: BattlePlayer = 圣弓引擎.p(1)
	圣弓玩家.role_id = 37
	var 圣弓: BattleRole = BattleRole.create(37, 圣弓玩家, 圣弓引擎)
	圣弓玩家.role = 圣弓
	var 圣屑项: Dictionary = {}
	for 项: Dictionary in 圣弓.available_skills():
		if int(项.get("id", 0)) == GConst.技能_圣屑飓暴:
			圣屑项 = 项
	检(str(圣屑项.get("card_rule", "")) == "same", "圣屑飓暴没有下发同系选牌规则")

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

		# 真牌展示：展示区视图必须真的记住牌号。Godot 只接受 ASCII 元数据键，
		# 写成中文会报 Invalid metadata identifier、set_meta 静默失败，选走时按牌号就找不到视图。
		战.call("_on_card", {
			"type": GConst.CardMsgType.Show, "src_id": 1, "dst_id": 1,
			"card_ids": [牌.id], "is_real": true,
		})
		await 等帧(1)
		var 展示区: Node = 战.get("ShowCardArea")
		var 记住牌号: bool = false
		if 展示区 != null:
			for 子: Node in 展示区.get_children():
				if 子 is Control and (子 as Control).has_meta(&"show_card_id"):
					记住牌号 = true
		检(记住牌号, "展示卡牌视图没有记住牌号（元数据键必须是 ASCII 标识符）")

		战.call("_排行动播报", 1, "测试技能")
		await 等帧(1)
		var 找到: bool = false
		for 子: Node in 根.get_children():
			if 子 is Label and (子 as Label).text == "测试技能":
				找到 = true
				break
		检(找到, "调用 _排行动播报 后，战斗界面上没有出现「测试技能」这一行")

		# 每次 Skill 通知都写日志、都排一条头像飘字（不再按同名去重）
		await get_tree().create_timer(4.8).timeout
		var 日志前: String = str(战.get("_日志"))
		战.call("_on_skill", {"skill_id": 2001, "src_id": 1})
		战.call("_on_skill", {"skill_id": 2001, "src_id": 1})
		var 新增日志: String = str(战.get("_日志")).substr(日志前.length())
		检(新增日志.count(技能名) == 2,
			"两条 Skill 通知应各写一条日志「%s」，实际：%s" % [技能名, 新增日志])
		# 队列间隔 1 秒：等第二条排到后再数
		await get_tree().create_timer(1.3).timeout
		var 技能飘报数: int = 0
		for 子: Node in 根.get_children():
			if 子 is Label and (子 as Label).text == 技能名:
				技能飘报数 += 1
		检(技能飘报数 == 2, "两条 Skill 通知应各飘一次「%s」，实际 %d 次" % [技能名, 技能飘报数])

		# 等技能行播完，再验特殊行动的信号能落到头像播报上
		await get_tree().create_timer(4.8).timeout
		Logic.special_action_received.emit(1, GConst.SpecialAction.Buy)
		await 等帧(1)
		var 特殊播报找到: bool = false
		for 子: Node in 根.get_children():
			if 子 is Label and (子 as Label).text == "购买":
				特殊播报找到 = true
				break
		检(特殊播报找到, "收到特殊行动事件后，战斗界面上没有出现「购买」这一行")

		# 欺诈：技能名照常占用播报队列
		var 欺诈名: String = GConst.skill_name(GConst.技能_欺诈)
		战.call("_on_skill", {"skill_id": GConst.技能_欺诈, "src_id": 2})
		await 等帧(1)
		var 欺诈飘报: bool = false
		for 子: Node in 根.get_children():
			if 子 is Label and (子 as Label).text == 欺诈名:
				欺诈飘报 = true
				break
		检(欺诈飘报, "欺诈技能名应正常占用播报队列并飘出")

	# 等这一行的播放协程走完再拆界面，避免在 await 里被 free
	await get_tree().create_timer(4.8).timeout
	战.queue_free()
	await 等帧(2)
	Data.player_list = 旧玩家
	Data.hand_cards = 旧手牌
	Data.cover_cards = 旧盖牌
	Logic.my_player_id = 旧id
