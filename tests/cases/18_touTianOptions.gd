extends 自检用例
## 偷天换日：二级栏两种用法必须始终摆出来，当前做不了的只置灰（enabled=false），不能直接消失。
## 原版 12 和 Trick 89 都要保持同一套结构。

func _init() -> void:
	名称 = "偷天换日选项置灰"


func 跑() -> void:
	await 等帧(1)

	for rid: int in [12, 89]:
		var 引擎: BattleEngine = BattleEngine.new()
		引擎.add_player(1, GConst.BLUE, "蓝一")
		引擎.add_player(2, GConst.RED, "红二")
		var 玩家: BattlePlayer = 引擎.p(1)
		玩家.role_id = rid
		var 角色: BattleRole = BattleRole.create(rid, 玩家, 引擎)
		检(角色 != null, "%d 号冒险家脚本没有创建出来" % rid)
		if 角色 == null:
			continue

		# 两种用法都做不了：两条选项仍然都在，但都带 enabled=false
		引擎.team_gem.fill(0)
		引擎.team_crystal.fill(0)
		var 选项: Array = 角色.call("_tou_tian_options")
		检(选项.size() == 2, "%d 号偷天换日应始终摆出两条用法，实际 %d 条" % [rid, 选项.size()])
		if 选项.size() == 2:
			检(not bool(选项[0].get("enabled", true)), "%d 号无宝石时「转移宝石」应置灰" % rid)
			检(not bool(选项[1].get("enabled", true)), "%d 号无水晶时「水晶转宝石」应置灰" % rid)

		# 只有对方有宝石：转移可点，转换置灰
		引擎.team_gem[1 - 玩家.color] = 1
		选项 = 角色.call("_tou_tian_options")
		检(选项.size() == 2, "%d 号偷天换日选项数量不应随可行性变化" % rid)
		if 选项.size() == 2:
			检(bool(选项[0].get("enabled", false)), "%d 号有对方宝石时「转移宝石」应可点" % rid)
			检(not bool(选项[1].get("enabled", true)), "%d 号无水晶时「水晶转宝石」应置灰" % rid)

		# 只有我方有水晶：转换可点，转移置灰
		引擎.team_gem.fill(0)
		引擎.team_crystal[玩家.color] = 1
		选项 = 角色.call("_tou_tian_options")
		检(选项.size() == 2, "%d 号偷天换日选项数量不应随可行性变化" % rid)
		if 选项.size() == 2:
			检(not bool(选项[0].get("enabled", true)), "%d 号无对方宝石时「转移宝石」应置灰" % rid)
			检(bool(选项[1].get("enabled", false)), "%d 号有水晶时「水晶转宝石」应可点" % rid)

		# 两种都可做：技能本体应放行
		引擎.team_gem[1 - 玩家.color] = 1
		检(bool(角色.call("_tou_tian_any_enabled")), "%d 号两种用法都可做时技能本体应可点" % rid)
