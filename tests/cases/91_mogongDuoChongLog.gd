extends 自检用例
## 用例 91：魔弓【多重射击】「打出的牌」是那张真实风系【充能】，攻击按暗灭表现
##
## 用户口径：多重射击打出的还是原来那张风系【充能】（展示 / 日志按它写），
## 但这次攻击是暗系攻击 —— 客户端用 as_card_id=暗灭 播暗系弹道 / 音效。
##
## 覆盖：_resolve_duo_chong 发出的 Card Use 消息里
##   card_ids = 实际被移除的那张充能（牌面）、is_real = true、as_card_id = 暗灭(39)；
##   且风系【充能】确实被移除。

const 角色脚本: GDScript = preload("res://scripts/battle/roles/role_mogong.gd")
const 暗灭: int = 39

var 引擎: BattleEngine = null
var 角色: BattleRole = null
var 玩家: BattlePlayer = null
var 消息: Array = []


func _init() -> void:
	名称 = "多重射击打出真实充能"


func 跑() -> void:
	await 等帧(1)
	_建引擎()
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

	var 使用卡: Dictionary = {}
	for 条: Dictionary in 消息:
		if int(条["type"]) != GConst.Msg.Card:
			continue
		var d: Dictionary = 条["data"]
		if int(d.get("type", 0)) != GConst.CardMsgType.Use:
			continue
		使用卡 = d
		break
	检(not 使用卡.is_empty(), "多重射击没有广播「使用」的 Card 消息")
	if not 使用卡.is_empty():
		var 打出: Array = 使用卡.get("card_ids", [])
		检(打出.size() == 1 and int(打出[0]) == GConst.牌号(风牌),
			"打出的应是那张真实风系充能（牌面 %d），实际 %s" % [GConst.牌号(风牌), str(打出)])
		检(bool(使用卡.get("is_real", false)), "打出的真实充能应标 is_real=true")
		检(int(使用卡.get("as_card_id", -1)) == 暗灭,
			"攻击表现应按暗灭播（as_card_id=39），实际 %s" % str(使用卡.get("as_card_id", -1)))
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
