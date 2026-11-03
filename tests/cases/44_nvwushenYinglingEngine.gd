extends 自检用例
## 女武神【英灵召唤】拆段：通过真实引擎状态栈走两问。
## 场景二专门盯「横置压入 p_tap 钩子、中间插入别的询问把第二问回复顶掉」这个坑
## （兽灵【兽魂警戒】在 p_tap 里开询问时，弃了法术牌也拿不到治疗）。

var 引擎: BattleEngine = null
var 玩家: BattlePlayer = null
var 角色: BattleRole = null


## 模拟「别人横置时会在 p_tap 里开询问」的角色（兽灵【兽魂警戒】那类）
class 横置响应角色:
	extends BattleRole

	## 已经问过一次就不再问（避免同一次横置反复打断）
	var 问过: bool = false

	func p_tap(ctx: Dictionary) -> int:
		if int(ctx.get("id", -1)) == player.id or not bool(ctx.get("tap", false)):
			return SUCCESS
		if 问过:
			return SUCCESS
		问过 = true
		询问(player.id, 9001, 0, 0, GConst.CardSource.Hand, [], 0, "", [], true)
		return WAIT


func _init() -> void:
	名称 = "女武神英灵召唤拆段"


func 跑() -> void:
	_场景一()
	_场景二()
	_场景三()


func _建局() -> void:
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
	引擎.current_id = 1
	玩家.set_crystal(2)
	玩家.hand_cards.clear()


## 起一次「自己攻击命中」的伤害钩子，返回 harm（伤害值以它为准）
func _起命中() -> Dictionary:
	var harm: Dictionary = {"src": 1, "dst": 2, "point": 1,
		"type": GConst.HarmType.Attack}
	引擎.push(BattleEngine.SHook.new("p_timeline_2_hit", {"harm": harm}, []))
	引擎.run()
	return harm


## 场景一：正常的「问是否发动 → 弃法术牌 + 选目标」
func _场景一() -> void:
	_建局()
	var 法术牌: int = 4
	玩家.add_hand_cards([法术牌])
	var harm: Dictionary = _起命中()
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
	检(玩家.tap, "自己回合内发动应横置（英灵形态）")


## 场景二：横置会压入一轮 p_tap 钩子，2 号角色在里面开询问（兽魂警戒那类）。
## 第二问的回复不能被这轮钩子顶掉：弃牌与治疗必须已经结算完。
func _场景二() -> void:
	_建局()
	var 拦截: BattleRole = 横置响应角色.new()
	拦截.setup(引擎.p(2), 引擎)
	引擎.p(2).role = 拦截
	var 法术牌: int = 4
	玩家.add_hand_cards([法术牌])
	_起命中()
	引擎.on_message(1, GConst.Msg.Respond, {"respond_id": 2505, "args": [1],
		"card_ids": [], "dst_ids": []})
	检(引擎._await_id == 1, "场景二：第二问应还在等玩家 1：%s" % str(引擎._await_id))
	引擎.on_message(1, GConst.Msg.Respond, {"respond_id": GConst.技能_英灵召唤治疗,
		"args": [1], "card_ids": [法术牌], "dst_ids": [3]})
	检(not 玩家.hand_cards.has(法术牌), "场景二：横置插入询问后，弃法术牌被顶掉了")
	检(引擎.p(3).cross_num == 1, "场景二：横置插入询问后，治疗被顶掉了")
	检(玩家.tap, "场景二：自己回合内发动应横置（英灵形态）")
	检(引擎._await_id == 2, "场景二：横置后应在等 2 号回答 p_tap 里的询问：%s" % str(引擎._await_id))
	引擎.on_message(2, GConst.Msg.Respond, {"respond_id": 9001, "args": [1],
		"card_ids": [], "dst_ids": []})


## 场景三：第二问取消（不额外弃牌）时，英灵召唤本身照旧结算：仍横置，但不弃牌、不加治疗
func _场景三() -> void:
	_建局()
	var 法术牌: int = 4
	玩家.add_hand_cards([法术牌])
	_起命中()
	引擎.on_message(1, GConst.Msg.Respond, {"respond_id": 2505, "args": [1],
		"card_ids": [], "dst_ids": []})
	引擎.on_message(1, GConst.Msg.Respond, {"respond_id": GConst.技能_英灵召唤治疗,
		"args": [], "card_ids": [], "dst_ids": []})
	检(玩家.hand_cards.has(法术牌), "场景三：取消第二问不应弃牌")
	检(引擎.p(3).cross_num == 0, "场景三：取消第二问不应加治疗")
	检(玩家.tap, "场景三：取消第二问也应横置（英灵召唤已发动）")
