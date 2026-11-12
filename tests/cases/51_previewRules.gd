extends 自检用例
## 用例 51：攻击伤害预览的「规则词表 / 目标派生表 / 服务端给数但自己排版」。
##
## 这些路径只跟「服务端给的规则串 / 表里的规则 / 提示自己的排版」有关，
## 不需要真引擎，直接构造 pending 喂给 BattleUIMobile 的对应函数即可；
## 「真引擎 → 协议 → 客户端」的闭环由用例 50 负责。

var 窗: Control = null
var 火牌: int = 0
var 水牌: int = 0


func _init() -> void:
	名称 = "攻击伤害预览规则"


func 等帧(_数: int = 2) -> void:
	var 截止: int = Time.get_ticks_msec() + 120
	while Time.get_ticks_msec() < 截止:
		await get_tree().process_frame


func _找牌(元素: int) -> int:
	for c: GCard in Data.card_db:
		if c != null and c.element_enum() == 元素:
			return c.id
	return 0


func _重置询问(技能号: int, pending: Dictionary) -> void:
	窗.set("_mode", 3)
	窗.set("_skill_ask_id", 技能号)
	窗.set("_pending", pending)
	窗.set("_sel_players", [] as Array[int])
	窗.set("_sel_cards", [] as Array[int])
	窗.set("_已选参数", [])
	窗.set("_二级选项", [])
	窗.set("_二级选中", -1)
	窗.set("_skill_need_card", 0)
	窗.set("_skill_ask_need_target", 0)


func 跑() -> void:
	await 等帧(2)
	UI.goto_lobby()
	await 等帧(2)
	火牌 = _找牌(GConst.CardElement.Fire)
	水牌 = _找牌(GConst.CardElement.Water)
	检(火牌 > 0 and 水牌 > 0, "卡库找不到火系/水系牌，用例前提不成立")
	if 火牌 <= 0 or 水牌 <= 0:
		return

	Logic.my_player_id = 1
	var 玩家: Array[GPlayer] = [
		GPlayer.new(1, GConst.BLUE, "我"),
		GPlayer.new(2, GConst.RED, "对手A"),
		GPlayer.new(3, GConst.RED, "对手B"),
	]
	Data.player_list = 玩家
	Data.hand_cards = [] as Array[GCard]
	Data.cover_cards = [] as Array[GCard]
	var 旧蓝: GTeam = Data.blue
	var 旧红: GTeam = Data.red
	Data.blue = GTeam.new(false)
	Data.red = GTeam.new(true)

	窗 = (load("res://scenes/BattleUIMobile.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(窗)
	await 等帧(2)

	_检规则词表()
	_检派生伤害(玩家)
	_检服务端给数自己排版()
	_检无询问攻击技能()

	Data.blue = 旧蓝
	Data.red = 旧红
	窗.free()


## preview_rule 的四个词 + option 默认项 + 带常数要选满
func _检规则词表() -> void:
	# card:3 —— 每张所选火系牌 +1；禁断之力还有「反噬同点数」的自身附带
	_重置询问(GConst.技能_禁断之力,
		{"preview_base": 2, "preview_rule": "card:3", "preview_ids": [2]})
	窗.set("_sel_cards", [火牌, 水牌] as Array[int])
	var 禁断: Dictionary = 窗.call("_攻击伤害头像提示")
	检(str(禁断.get(2, "")) == "[zwj]2 攻击伤害\n3 攻击伤害",
		"card:3 应只数火系牌（实际：%s）" % str(禁断.get(2, "")))
	检(str(禁断.get(1, "")) == "1 法术伤害",
		"禁断之力应把反噬点数写在自己头像上（实际：%s）" % str(禁断.get(1, "")))

	# option,card,-2 —— 战纹碎击：默认第一项选项（不额外翻转）+ 弃 2 张 - 2
	_重置询问(GConst.技能_战纹碎击,
		{"preview_base": 3, "preview_rule": "option,card,-2", "preview_ids": [2]})
	窗.set("_skill_need_card", 2)
	窗.set("_二级选项", [{"参数": [1], "可用": true}])
	窗.set("_sel_cards", [火牌, 水牌] as Array[int])
	var 战纹: Dictionary = 窗.call("_攻击伤害头像提示")
	检(str(战纹.get(2, "")) == "[zwj]3 攻击伤害\n4 攻击伤害",
		"option,card,-2 在选满 2 张时应 +1（实际：%s）" % str(战纹.get(2, "")))
	# 只选 1 张：带常数的规则按 0 算，不能出现负数
	窗.set("_sel_cards", [火牌] as Array[int])
	var 战纹少: Dictionary = 窗.call("_攻击伤害头像提示")
	检(战纹少.is_empty(), "没选满牌时不该按带常数的规则加伤（实际：%s）" % str(战纹少))

	# option —— 未选时按第一项可用选项的值
	_重置询问(GConst.技能_战纹碎击,
		{"preview_base": 2, "preview_rule": "option", "preview_ids": [2]})
	窗.set("_二级选项", [{"参数": [2], "可用": true}])
	var 选项: Dictionary = 窗.call("_攻击伤害头像提示")
	检(str(选项.get(2, "")) == "[zwj]2 攻击伤害\n4 攻击伤害",
		"option 未选时应按第一项可用选项算（实际：%s）" % str(选项.get(2, "")))

	# eff:3 —— 索拉：子弹是火系 +1，水系不加
	_重置询问(GConst.技能_元素射击SORA,
		{"preview_base": 2, "preview_rule": "eff:3", "preview_ids": [2]})
	窗.set("_sel_cards", [火牌] as Array[int])
	var 索拉火: Dictionary = 窗.call("_攻击伤害头像提示")
	检(str(索拉火.get(2, "")) == "[zwj]2 攻击伤害\n3 攻击伤害",
		"eff:3 在火系子弹时应 +1（实际：%s）" % str(索拉火.get(2, "")))
	窗.set("_sel_cards", [水牌] as Array[int])
	var 索拉水: Dictionary = 窗.call("_攻击伤害头像提示")
	检(索拉水.is_empty(), "水系子弹不该按 eff:3 加伤（实际：%s）" % str(索拉水))


## 攻击技能派生伤害表：圣光爆裂（每个有治疗的目标 +1）/ 天火断空（目标队伍士气更高时 +1）
func _检派生伤害(玩家: Array[GPlayer]) -> void:
	窗.set("_mode", 4)
	窗.set("_pending_skill_id", GConst.技能_圣光爆裂)
	窗.set("_已选参数", [2, 1])
	窗.set("_sel_players", [2, 3] as Array[int])
	玩家[1].cross_num = 1
	玩家[2].cross_num = 0
	var 爆裂: Dictionary = 窗.call("_圣光爆裂头像提示")
	检(str(爆裂.get(2, "")) == "3 攻击伤害",
		"圣光爆裂对「有治疗」的目标应是 2+1=3（实际：%s）" % str(爆裂.get(2, "")))
	# 加伤按「所有目标里有几个带治疗」算，选中的人共用同一个数
	检(str(爆裂.get(3, "")) == "3 攻击伤害",
		"同一批目标共用 2+1=3（实际：%s）" % str(爆裂.get(3, "")))
	检(str(爆裂.get(1, "")) == "移除 1 治疗\n弃 1 张牌",
		"圣光爆裂的代价文案不应变（实际：%s）" % str(爆裂.get(1, "")))
	# 一个带治疗的都没有时回到基础 2
	玩家[1].cross_num = 0
	var 爆裂零: Dictionary = 窗.call("_圣光爆裂头像提示")
	检(str(爆裂零.get(2, "")) == "2 攻击伤害",
		"没有目标带治疗时圣光爆裂应是 2（实际：%s）" % str(爆裂零.get(2, "")))

	窗.set("_pending_skill_id", GConst.技能_天火断空)
	窗.set("_sel_players", [2] as Array[int])
	Data.blue.set_morale(10)
	Data.red.set_morale(12)
	var 天火: Dictionary = 窗.call("_天火断空头像提示")
	检(str(天火.get(2, "")) == "[zwj]3 法术伤害\n4 法术伤害",
		"目标队伍士气更高时天火断空应是 3→4（实际：%s）" % str(天火.get(2, "")))
	检(str(天火.get(1, "")) == str(天火.get(2, "")),
		"天火断空对自己写同一个点数（实际：%s）" % str(天火.get(1, "")))
	Data.red.set_morale(10)
	var 天火平: Dictionary = 窗.call("_天火断空头像提示")
	检(str(天火平.get(2, "")) == "3 法术伤害",
		"士气持平时天火断空只显示 3 点（实际：%s）" % str(天火平.get(2, "")))


## 服务端给数、提示自己排版：朝圣 / 英灵召唤 / 神威 / 圣裁
func _检服务端给数自己排版() -> void:
	_重置询问(GConst.技能_朝圣,
		{"preview_base": 3, "preview_damage": 2, "preview_kind": GConst.HarmType.Attack})
	var 朝圣: Dictionary = 窗.call("_朝圣头像提示")
	检(str(朝圣.get(1, "")) == "[zwj]3 点攻击伤害\n2 点攻击伤害",
		"朝圣应写「3 点攻击伤害 → 2 点」（实际：%s）" % str(朝圣.get(1, "")))

	_重置询问(GConst.技能_英灵召唤,
		{"preview_base": 3, "preview_damage": 4, "preview_ids": [2]})
	窗.set("_sel_players", [3] as Array[int])
	var 英灵: Dictionary = 窗.call("_英灵召唤头像提示")
	检(str(英灵.get(2, "")) == "[zwj]3 攻击伤害\n4 攻击伤害",
		"英灵召唤应写「3 → 4」（实际：%s）" % str(英灵.get(2, "")))
	检(str(英灵.get(3, "")) == "+1 治疗",
		"英灵召唤应在治疗目标上写「+1 治疗」（实际：%s）" % str(英灵.get(3, "")))

	_重置询问(4302,
		{"preview_base": 3, "preview_damage": 4, "preview_ids": [2]})
	var 神威: Dictionary = 窗.call("_神威头像提示")
	检(str(神威.get(2, "")) == "[zwj]3 攻击伤害\n4 攻击伤害",
		"神威应写「3 → 4」（实际：%s）" % str(神威.get(2, "")))

	_重置询问(4303, {"preview_base": 3, "preview_ids": [2]})
	窗.set("_已选参数", [2])
	var 圣裁: Dictionary = 窗.call("_圣裁头像提示")
	检(str(圣裁.get(2, "")) == "1 法术伤害\n[zwj]3 攻击伤害\n4 攻击伤害",
		"圣裁 X=2 应写「1 法术伤害 + 3→4」（实际：%s）" % str(圣裁.get(2, "")))


## 无询问攻击技能：一张表配系别来源 + 荒神判定
func _检无询问攻击技能() -> void:
	窗.set("_mode", 4)
	窗.set("_sel_players", [2] as Array[int])
	# 场上给一名结界师，盖牌区一张火系【结界】→ 火系攻击荒神 +1
	Data.player_list[2].role_id = GConst.角色_结界师
	Data.player_list[2].cover_opens = [火牌] as Array[int]

	窗.set("_pending_skill_id", GConst.技能_圣屑飓暴)
	窗.set("_sel_cards", [火牌] as Array[int])
	窗.set("_已选参数", [])
	var 圣屑: Dictionary = 窗.call("_攻击技能伤害头像提示")
	检(str(圣屑.get(2, "")) == "3 攻击伤害",
		"圣屑飓暴（火系牌 + 火系结界）应是 2+1=3（实际：%s）" % str(圣屑.get(2, "")))

	窗.set("_pending_skill_id", GConst.技能_欺诈)
	窗.set("_sel_cards", [] as Array[int])
	窗.set("_已选参数", [火牌])
	var 欺诈: Dictionary = 窗.call("_攻击技能伤害头像提示")
	检(str(欺诈.get(2, "")) == "3 攻击伤害",
		"欺诈（虚牌火系 + 火系结界）应是 3（实际：%s）" % str(欺诈.get(2, "")))

	窗.set("_pending_skill_id", GConst.技能_转换)
	窗.set("_sel_cards", [火牌] as Array[int])
	窗.set("_已选参数", [])
	var 转换: Dictionary = 窗.call("_攻击技能伤害头像提示")
	检(str(转换.get(2, "")) == "3 攻击伤害",
		"转换（法术牌视为火系攻击 + 火系结界）应是 3（实际：%s）" % str(转换.get(2, "")))
	# 没有同系结界时回到 2
	Data.player_list[2].cover_opens = [水牌] as Array[int]
	var 圣屑2: Dictionary = 窗.call("_攻击技能伤害头像提示")
	检(str(圣屑2.get(2, "")) == "2 攻击伤害",
		"结界系别不匹配时应只有基础 2 点（实际：%s）" % str(圣屑2.get(2, "")))
