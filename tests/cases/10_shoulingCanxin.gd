extends 自检用例
## 用例 10：兽灵武士【武者残心】——残心已达上限时不再询问「加不加」（加了也会被上限吃掉），
## 但仍照常授予【一击无念】。

const 兽灵武士: int = 36
const 一击无念: int = 3602


func _init() -> void:
	名称 = "武者残心满上限不询问"


func 跑() -> void:
	await 等帧()
	var 引擎: BattleEngine = BattleEngine.new()
	引擎.add_player(1, GConst.BLUE, "兽灵")
	var 玩家: BattlePlayer = 引擎.p(1)
	玩家.role_id = 兽灵武士
	var 兽灵: BattleRole = BattleRole.create(兽灵武士, 玩家, 引擎)
	玩家.role = 兽灵
	# 残心拉满
	玩家.tokens[0]["num"] = int(玩家.tokens[0]["max"])
	引擎._states.clear()
	引擎._清空等待()
	引擎.phase = BattleEngine.Phase.Playing

	var r: int = 兽灵.p_after_attack({"player": 1})
	检(r != BattleRole.WAIT, "残心满时武者残心仍在等待询问（返回 %d）" % r)
	检(not (引擎._最后询问 as Dictionary).has(1), "残心满时仍弹出了武者残心询问")
	检(玩家.additional_actions.size() == 1, "残心满时没有照常授予一击无念")
	if 玩家.additional_actions.size() == 1:
		检(int(玩家.additional_actions[0]["cause"]) == 一击无念,
			"残心满时授予的额外行动不是一击无念：%s" % str(玩家.additional_actions))
