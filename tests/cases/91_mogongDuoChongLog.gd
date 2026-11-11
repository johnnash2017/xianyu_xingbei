extends 自检用例
## 用例 91：魔弓【多重射击】的虚拟攻击牌播报不带命格
##
## 多重射击广播一张「暗灭」（卡 39，卡表命格=圣）来播暗系弹道 / 音效。
## 那张牌只是借来用的虚拟牌：如果没标 virtual_no_fate，战斗日志 / 飘字会按卡表写
## 「暗灭·圣」，看起来像是打出了一张圣命格攻击牌。
##
## 覆盖：_resolve_duo_chong 发出的 Card Use 消息里 card_ids=[39]、is_real=false、
## 且 virtual_no_fate=true；同时确认这一手确实移除了风系【充能】。

const 角色脚本: GDScript = preload("res://scripts/battle/roles/role_mogong.gd")
const 虚拟牌: int = 39

var 引擎: BattleEngine = null
var 角色: BattleRole = null
var 玩家: BattlePlayer = null
var 消息: Array = []


func _init() -> void:
	名称 = "多重射击播报无命格"


func 跑() -> void:
	await 等帧(1)
	_建引擎()
	# 放一张风系盖牌当【充能】
	var 风牌: int = -1
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.element_enum() == GConst.CardElement.Wind \
				and c.is_attack():
			风牌 = c.id
			break
	检(风牌 >= 0, "卡库里找不到风系攻击牌（前提不成立）")
	玩家.cover_cards.append(风牌)

	消息.clear()
	引擎.send_cb = func(_target: int, 类型: int, 数据: Dictionary) -> void:
		消息.append({"type": 类型, "data": 数据})
	角色.call("_resolve_duo_chong", 3)

	# 找那一条「使用暗灭」的 Card 消息
	var 使用卡: Dictionary = {}
	for 条: Dictionary in 消息:
		if int(条["type"]) != GConst.Msg.Card:
			continue
		var d: Dictionary = 条["data"]
		if int(d.get("type", 0)) != GConst.CardMsgType.Use:
			continue
		if (d.get("card_ids", []) as Array).has(虚拟牌):
			使用卡 = d
			break
	检(not 使用卡.is_empty(), "多重射击没有广播「使用暗灭」的 Card 消息")
	if not 使用卡.is_empty():
		检(not bool(使用卡.get("is_real", true)), "暗灭虚拟牌应标 is_real=false")
		检(bool(使用卡.get("virtual_no_fate", false)),
			"暗灭虚拟牌应标 virtual_no_fate（否则日志会写成「暗灭·圣」）：%s" % str(使用卡))
	检(not 玩家.cover_cards.has(风牌), "多重射击应移除 1 张风系【充能】")


func _建引擎() -> void:
	引擎 = BattleEngine.new()
	引擎.add_player(1, GConst.BLUE, "魔弓")
	引擎.add_player(2, GConst.BLUE, "队友")
	引擎.add_player(3, GConst.RED, "敌一")
	引擎.add_player(4, GConst.RED, "敌二")
	引擎.start_with_roles({})
	玩家 = 引擎.p(1)
	玩家.role_id = 26
	角色 = 角色脚本.new()
	角色.setup(玩家, 引擎)
	玩家.role = 角色
