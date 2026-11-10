extends 自检用例
## 用例 83：启动技（散华轮舞 3406）之后，下一次行动的目标必须还能点
##
## 用户反馈：用完【散华轮舞】再打【地裂斩】，对手头像不亮、选不了目标。
##
## 根因：散华轮舞的指示器配了「自动选目标：自己 + 锁定不可取消」，
## `_选择技能` 会把 `_目标锁死` 置 true；服务端接下这次启动后**很快**又发一条行动询问，
## 而 `_稍后清空待选` 发现「新询问已经来了」就不再走 `_清空待选`（那里才复位 `_目标锁死`），
## `_进入待选` 自己又没复位 → 锁死状态漏到下一次行动，`_玩家可选` 第一道判断就把所有头像挡掉。
##
## 覆盖：散华轮舞发动后 `_目标锁死` 为真；新的行动询问进来后必须复位；
## 并且此时点一张攻击牌，对手应可选中。

const 角色脚本: GDScript = preload("res://scripts/battle/roles/role_xuejian.gd")

var 引擎: BattleEngine = null
var 角色: BattleRole = null
var 玩家: BattlePlayer = null
var 窗: Control = null


func _init() -> void:
	名称 = "散华轮舞后目标可点"


func 跑() -> void:
	await 等帧(1)
	Logic.my_player_id = 1
	_建引擎()
	_建窗()
	var 项: Dictionary = {}
	for s: Dictionary in 角色.available_skills():
		if int(s.get("id", 0)) == 3406:
			项 = s
			break
	检(not 项.is_empty(), "散华轮舞不在技能栏里（前提不成立）")
	# ---- 1) 发动画散轮舞：按指示器「自动选目标自己」，客户端应把目标锁死 ----
	窗.call("_选择技能", 3406, int(项.get("type", GConst.ActionType.SpecialSkill)),
		int(项.get("need_card", 0)), int(项.get("need_target", 0)),
		项.get("targets", []), 项.get("cards", []), int(项.get("card_max", 0)),
		int(项.get("target_max", 0)), 0, GConst.CardSource.Hand, "",
		0, 0, 项.get("arg_choices", []), null, 0, [])
	await 等帧(1)
	检(bool(窗.get("_目标锁死")), "散华轮舞应把自己锁成目标（指示器：自动选目标自己）")

	# ---- 2) 服务端接下这次启动技，同一玩家继续行动：新的行动询问到达 ----
	Logic.command_received.emit({"cmd_type": GConst.CmdType.Action,
		"commands": [{"respond_id": GConst.ActionType.Attack, "src_id": 1, "args": []}]})
	await 等帧(3)
	检(int(窗.get("_mode")) == 1, "新的行动询问后应回到行动模式（实际 %d）" % int(窗.get("_mode")))
	检(not bool(窗.get("_目标锁死")),
		"新的行动询问后 _目标锁死 没有复位：之后所有头像都会点不亮（散华轮舞之后再攻击选不了目标）")

	# ---- 3) 点一张攻击牌，对手应可选中 ----
	var 攻击牌: GCard = null
	for c: GCard in Data.hand_cards:
		if c != null and c.is_attack():
			攻击牌 = c
			break
	if 攻击牌 != null:
		窗.call("_on_card_clicked", 攻击牌.id)
		await 等帧(1)
		var 对手id: int = 3 if Logic.my_player_id != 3 else 4
		检(bool(窗.call("_玩家可选", 对手id)), "散华轮舞之后点攻击牌，对手头像应可选中")
	窗.queue_free()
	await 等帧(1)


func _建引擎() -> void:
	引擎 = BattleEngine.new()
	引擎.add_player(1, GConst.BLUE, "血色剑灵")
	引擎.add_player(2, GConst.BLUE, "队友")
	引擎.add_player(3, GConst.RED, "敌一")
	引擎.add_player(4, GConst.RED, "敌二")
	引擎.start_with_roles({})
	玩家 = 引擎.p(1)
	玩家.role_id = 34
	玩家.set_crystal(1)
	角色 = 角色脚本.new()
	角色.setup(玩家, 引擎)
	玩家.role = 角色


func _建窗() -> void:
	Logic.my_player_id = 1
	Logic.game_info_updated.emit({"is_started": true, "room_id": 7,
		"blue_morale": 15, "red_morale": 15, "blue_gem": 2, "blue_crystal": 1,
		"red_gem": 1, "red_crystal": 2})
	窗 = (load("res://scenes/BattleUIMobile.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(窗)
