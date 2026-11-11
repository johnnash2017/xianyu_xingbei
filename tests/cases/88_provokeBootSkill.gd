extends 自检用例
## 用例 88：【挑衅】+「启动」的放行规则
##
## 规则（用户口径）：
##   - 启动是免费动作，只能在本回合**第一个行动之前**执行；
##   - 被【挑衅】时仍可先用启动（启动不消耗行动）；
##   - 额外行动阶段不能用启动；
##   - 已经做过攻击 / 法术 / 特殊行动后不能再用启动；
##   - 非启动的特殊技能，被挑衅时仍置灰。
##
## 样本：血色剑灵【散华轮舞】3406（role.is_free_skill(3406) == true）。

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
	var 技能: Dictionary = {"type": GConst.ActionType.ActivateSkill, "id": 3406, "enabled": true}

	# ---- 1) 普通行动阶段、还没行动、没被挑衅：启动可用 ----
	var 命令: Dictionary = 引擎.call("_技能按钮命令", 玩家, 技能, GConst.ActionType.Any)
	检(bool(命令.get("enabled", false)), "本回合第一个行动前应能启动")

	# ---- 2) 只放行攻击（被挑衅）：启动仍可用 ----
	玩家.exclusive_effects[GConst.Exclusive.TiaoXin] = true
	命令 = 引擎.call("_技能按钮命令", 玩家, 技能, GConst.ActionType.Attack)
	检(bool(命令.get("enabled", false)), "被挑衅时应能用启动技能")
	# 反例用「消耗特殊行动的特殊技」（SpecialSkill，本工程暂无实例）：被挑衅时仍应置灰
	var 非启动: Dictionary = {"type": GConst.ActionType.SpecialSkill, "id": 999999, "enabled": true}
	var 命令2: Dictionary = 引擎.call("_技能按钮命令", 玩家, 非启动, GConst.ActionType.Attack)
	检(not bool(命令2.get("enabled", true)), "非启动的特殊技能被挑衅时仍应置灰")

	# ---- 3) 额外行动阶段：不能用启动 ----
	引擎.行动额外 = true
	命令 = 引擎.call("_技能按钮命令", 玩家, 技能, GConst.ActionType.Attack)
	检(not bool(命令.get("enabled", true)), "额外行动阶段不该放行启动技能")
	引擎.行动额外 = false

	# ---- 4) 已经做过行动：不能用启动 ----
	玩家.attack_action_count = 1
	命令 = 引擎.call("_技能按钮命令", 玩家, 技能, GConst.ActionType.Any)
	检(not bool(命令.get("enabled", true)), "已经攻击过之后不该再用启动")
	检(not bool(引擎.call("可发动启动", 玩家.id)), "本回合做过行动后 可发动启动 应为假")
	玩家.attack_action_count = 0
	检(bool(引擎.call("可发动启动", 玩家.id)), "计数清零后 可发动启动 应为真")

	# ---- 5) 客户端判定：被挑衅时启动按钮放行 ----
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
	检(bool(窗.call("_按钮可用核心", true, GConst.ActionType.ActivateSkill, 0,
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
