extends 自检用例
## 用例 12c：苍白之月第一项授予的是“额外攻击行动”，只有点中这份额外行动时，
## 该次攻击才无法应战；不是“下一次任意主动攻击”都无应战。

func _init() -> void:
	名称 = "月女苍白无应战"


func 跑() -> void:
	await 等帧(2)
	var 引擎: BattleEngine = BattleEngine.new()
	引擎.add_player(1, GConst.BLUE, "月女")
	引擎.add_player(2, GConst.RED, "对手")
	引擎.start_with_roles({1: 35, 2: 0})
	引擎._states.clear()
	引擎._清空等待()
	引擎.phase = BattleEngine.Phase.Playing
	var 月女: BattlePlayer = 引擎.p(1)
	var 角色: BattleRole = 月女.role
	检(角色 != null, "月女没有绑定角色脚本")
	if 角色 == null:
		return
	月女.gem = 1
	月女.tokens[1]["num"] = 3
	角色.p_magic_skill({"action_id": 3507, "args": [1]})
	检(not 角色._cang_bai_attack, "刚发动苍白之月时不应立刻标记“下次任意主动攻击”")

	# 点中其它额外行动：不置位
	角色.p_additional_action({"player": 1, "cause": 0})
	检(not 角色._cang_bai_attack, "点其它额外行动不应标记苍白之月")

	# 点中苍白之月授予的额外攻击行动：置位
	角色.p_additional_action({"player": 1, "cause": 3507})
	检(角色._cang_bai_attack, "点中苍白之月的额外攻击后应标记该次攻击无法应战")

	# 该次额外攻击吃标记并清除
	var 额外攻击: Dictionary = {"src": 1, "is_active": true, "hit_rate": GConst.HitRate.Normal}
	角色.p_timeline_1(额外攻击)
	检(int(额外攻击["hit_rate"]) == GConst.HitRate.NoReattack, "苍白之月的额外攻击应无法应战")
	检(not 角色._cang_bai_attack, "该次额外攻击后应清除标记")

	# 后续普通主动攻击恢复普通
	var 后续攻击: Dictionary = {"src": 1, "is_active": true, "hit_rate": GConst.HitRate.Normal}
	角色.p_timeline_1(后续攻击)
	检(int(后续攻击["hit_rate"]) == GConst.HitRate.Normal, "后续主动攻击应恢复可应战")

	# 回合开始会清掉残留标记（额外攻击行动只在本次回合内）
	角色._cang_bai_attack = true
	角色.p_before_turn_begin({})
	检(not 角色._cang_bai_attack, "回合开始应清除额外的无法应战标记")
