extends 自检用例
## 用例 88：被【挑衅】的角色仍然可以使用「启动」技能
##
## 勇者【挑衅】把目标压成「本回合只能攻击」；但「启动」技能（is_free_skill）不消耗行动，
## 被挑衅时也应该能发动。覆盖两处卡口：
##   服务端 _技能按钮命令：被挑衅时启动技能仍 enabled（其它特殊技能仍置灰）
##   客户端 _按钮可用核心：被挑衅时不再按「只放行攻击」拦启动技能
##
## 用血色剑灵【散华轮舞】3406 当启动技能样本（role.is_free_skill(3406) == true）。

const 角色脚本: GDScript = preload("res://scripts/battle/roles/role_xuejian.gd")

var 引擎: BattleEngine = null
var 角色: BattleRole = null
var 玩家: BattlePlayer = null


func _init() -> void:
	名称 = "被挑衅可用启动"


func 跑() -> void:
	await 等帧(1)
	_建引擎()
	检(角色.is_free_skill(3406), "散华轮舞应是启动技能（前提不成立）")

	# ---- 1) 正常状态：只放行攻击时，启动技能置灰 ----
	var 技能: Dictionary = {"type": GConst.ActionType.SpecialSkill, "id": 3406, "enabled": true}
	var 命令: Dictionary = 引擎.call("_技能按钮命令", 玩家, 技能, GConst.ActionType.Attack)
	检(not bool(命令.get("enabled", true)), "没被挑衅时，只放行攻击的阶段不该放行启动技能")

	# ---- 2) 被挑衅：启动技能可用 ----
	玩家.exclusive_effects[GConst.Exclusive.TiaoXin] = true
	命令 = 引擎.call("_技能按钮命令", 玩家, 技能, GConst.ActionType.Attack)
	检(bool(命令.get("enabled", false)), "被挑衅时应能用启动技能")
	# 非启动的特殊技能仍然置灰
	var 非启动: Dictionary = {"type": GConst.ActionType.SpecialSkill, "id": 999999, "enabled": true}
	var 命令2: Dictionary = 引擎.call("_技能按钮命令", 玩家, 非启动, GConst.ActionType.Attack)
	检(not bool(命令2.get("enabled", true)), "非启动的特殊技能被挑衅时仍应置灰")

	# ---- 3) 客户端判定：被挑衅时启动技能不再被放行种类拦住 ----
	Logic.my_player_id = 1
	var 旧列表: Array[GPlayer] = []
	旧列表.append_array(Data.player_list)
	Data.player_list.clear()
	var 我: GPlayer = GPlayer.new(1, GConst.BLUE, "剑灵")
	我.set_special(GConst.Exclusive.TiaoXin, true)
	Data.player_list.append(我)
	var 窗: Control = (load("res://scenes/BattleUIMobile.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(窗)
	await 等帧(1)
	检(bool(窗.call("_按钮可用核心", true, GConst.ActionType.SpecialSkill, 0,
		GConst.ActionType.Attack, 0)), "被挑衅时客户端应放行启动技能按钮")
	检(not bool(窗.call("_按钮可用核心", true, GConst.ActionType.Attack, 0,
		GConst.ActionType.Magic, 0)), "只放行攻击时，法术行动按钮仍应拦下")
	窗.queue_free()
	await 等帧(1)
	Data.player_list.clear()
	Data.player_list.append_array(旧列表)


func _建引擎() -> void:
	引擎 = BattleEngine.new()
	引擎.add_player(1, GConst.BLUE, "血色剑灵")
	引擎.add_player(2, GConst.RED, "敌人")
	引擎.add_player(3, GConst.BLUE, "队友")
	引擎.add_player(4, GConst.RED, "敌二")
	引擎.start_with_roles({})
	玩家 = 引擎.p(1)
	玩家.role_id = 34
	玩家.set_crystal(1)
	角色 = 角色脚本.new()
	角色.setup(玩家, 引擎)
	玩家.role = 角色
