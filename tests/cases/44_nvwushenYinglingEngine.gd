extends 自检用例
## 女武神【英灵召唤】拆段：通过真实引擎状态栈走两问。

var 引擎: BattleEngine = null
var 玩家: BattlePlayer = null
var 角色: BattleRole = null


func _init() -> void:
	名称 = "女武神英灵召唤拆段"


func 跑() -> void:
	引擎 = BattleEngine.new()
	引擎.add_player(1, GConst.BLUE, "甲")
	引擎.add_player(2, GConst.RED, "乙")
	引擎.add_player(3, GConst.BLUE, "丙")
	引擎.add_player(4, GConst.RED, "丁")
	引擎.start_with_roles({})
	玩家 = 引擎.p(1)
	玩家.role_id = 25
	角色 = load("res://scripts/battle/roles/role_nvwushen.gd").new()
	角色.setup(玩家, 引擎)
	玩家.role = 角色
	引擎.phase = BattleEngine.Phase.Playing
	引擎.round_id = 1
	玩家.set_crystal(2)
	var 法术牌: int = 4
	玩家.add_hand_cards([法术牌])
	var harm: Dictionary = {"src": 1, "dst": 2, "point": 1,
		"type": GConst.HarmType.Attack}
	引擎.push(BattleEngine.SHook.new("p_timeline_2_hit", {"harm": harm}, []))
	引擎.run()
	检(引擎._await_id == 1, "第一问应等玩家 1：%s" % str(引擎._await_id))
	# 确认发动
	引擎.on_message(1, GConst.Msg.Respond, {"respond_id": 2505, "args": [1],
		"card_ids": [], "dst_ids": []})
	检(引擎._await_id == 1, "第二问应继续等玩家 1：%s" % str(引擎._await_id))
	检(玩家.crystal == 1, "发动应扣 1 水晶")
	检(int(harm.get("point", 0)) == 2, "发动应先 +1 伤害")
	# 第二问：选法术牌 + 目标 3
	引擎.on_message(1, GConst.Msg.Respond, {"respond_id": GConst.技能_英灵召唤治疗,
		"args": [1], "card_ids": [法术牌], "dst_ids": [3]})
	检(not 玩家.hand_cards.has(法术牌), "确认第二问应弃法术牌")
	检(引擎.p(3).cross_num == 1, "确认第二问应给目标 +1 治疗")
