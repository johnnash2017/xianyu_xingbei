extends 自检用例
## 用例 52：角色状态标记（魔枪加伤 / 剑圣圣剑）——「角色 → 协议 → 客户端数据 → 图标配置」。
##
## 这条链路负责客户头像旁的状态图标：角色状态变了 → to_proto 带 state_marks / state_mark_counts
## → 客户端 _apply_player_info 填进 GPlayer → 面板按 GConst.角色状态图标 画图标与计数。
## 面板里「数量变多时弹一下」的动画不在这里断言（要真渲染，联机测试覆盖运行不报错）。

var 引擎: BattleEngine = null


func _init() -> void:
	名称 = "角色状态标记"


func _建引擎(角色号: int) -> BattleRole:
	引擎 = BattleEngine.new()
	引擎.send_cb = func(_pid: int, _msg: int, _data: Dictionary) -> void: pass
	引擎.add_player(1, GConst.BLUE, "我")
	引擎.add_player(2, GConst.RED, "对手")
	引擎.start_with_roles({})
	var 玩家: BattlePlayer = 引擎.p(1)
	var 脚本: GDScript = load(str(Data.role_script(角色号))) as GDScript
	var 角色: BattleRole = 脚本.new()
	玩家.role_id = 角色号
	角色.setup(玩家, 引擎)
	玩家.role = 角色
	return 角色


func _标记(玩家: BattlePlayer) -> Array:
	var d: Dictionary = 玩家.to_proto(1)
	return [d.get("state_marks", []), d.get("state_mark_counts", [])]


func 跑() -> void:
	# ---- 魔枪：暗之解放（2901，优先）/ 充盈（2905，带计数） ----
	var 魔枪: BattleRole = _建引擎(29)
	var 玩家: BattlePlayer = 引擎.p(1)
	魔枪.set("using_an_zhi_jie_fang", true)
	魔枪.set("used_an_zhi_jie_fang", false)
	var 标记: Array = _标记(玩家)
	检(标记[0] == [2901] and 标记[1] == [1],
		"暗之解放未用掉时应下发 2901×1（实际 %s / %s）" % [str(标记[0]), str(标记[1])])
	# 用掉之后暗之解放消失
	魔枪.set("used_an_zhi_jie_fang", true)
	标记 = _标记(玩家)
	检((标记[0] as Array).is_empty(), "暗之解放用掉后标记应消失（实际 %s）" % str(标记[0]))
	# 充盈：累计张数写在计数上
	魔枪.set("using_an_zhi_jie_fang", false)
	魔枪.set("used_chong_ying", true)
	魔枪.set("card_count", 5)
	标记 = _标记(玩家)
	检(标记[0] == [2905] and 标记[1] == [5],
		"充盈应下发 2905×5（实际 %s / %s）" % [str(标记[0]), str(标记[1])])

	# ---- 剑圣：圣剑已砍刀数（104）----
	var 剑圣: BattleRole = _建引擎(1)
	玩家 = 引擎.p(1)
	剑圣.set("attack_count", 3)
	标记 = _标记(玩家)
	检(标记[0] == [104] and 标记[1] == [3],
		"圣剑应下发 104×3（实际 %s / %s）" % [str(标记[0]), str(标记[1])])
	剑圣.set("attack_count", 0)
	标记 = _标记(玩家)
	检((标记[0] as Array).is_empty(), "刀数归零后圣剑标记应消失（实际 %s）" % str(标记[0]))

	# ---- 客户端数据层：协议字段 → GPlayer ----
	var 视图: GPlayer = GPlayer.new(1, GConst.BLUE, "我")
	Data.call("_apply_player_info", 视图,
		{"id": 1, "team": GConst.BLUE, "nickname": "我",
		"state_marks": [2905, 104], "state_mark_counts": [2, 3]})
	检(视图.state_marks == [2905, 104] and 视图.state_mark_counts == [2, 3],
		"客户端没把 state_marks / state_mark_counts 填进 GPlayer（实际 %s / %s）" %
		[str(视图.state_marks), str(视图.state_mark_counts)])

	# ---- 图标配置：每个标记号都要有图标且资源存在 ----
	for 技能号: int in [104, 2901, 2905]:
		var 配置: Dictionary = GConst.角色状态图标.get(技能号, {})
		检(not 配置.is_empty(), "标记 %d 没有配 GConst.角色状态图标" % 技能号)
		if 配置.is_empty():
			continue
		var 图标: String = str(配置.get("icon", ""))
		检(图标 != "" and ResourceLoader.exists(图标),
			"标记 %d 的图标不存在：%s" % [技能号, 图标])
		检(GConst.skill_name(技能号) != "", "标记 %d 取不到技能名" % 技能号)
	检(bool((GConst.角色状态图标.get(104, {}) as Dictionary).get("技能说明", false)),
		"剑圣【圣剑】的图标应按「技能说明」悬停（大图 + 技能说明）")
