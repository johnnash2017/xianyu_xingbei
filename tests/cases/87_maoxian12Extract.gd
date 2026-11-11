extends 自检用例
## 用例 87：12 号冒险家【冒险者天堂】——提炼时要能选「给自己」也能选「给队友」
##
## 用户反馈：12 号冒险家点提炼直接进了「全给队友」流程，没有「提炼给自己」这条路。
## 现在与 89 号 Trick 版对齐（12 没有额外提炼档）：先选
##   提炼给自己 1~2 颗（走普通提炼） / 提炼给队友 1~2 颗（整份交给一名队友）。
##
## 覆盖：
##   客户端：方式层两个选项、文案取技能表；选给自己→普通提炼（_提炼全给一人=false）；
##           选给队友→天堂分配（_提炼全给一人=true、_提炼阶段=4）；
##   服务端：v_extract 认「给队友」的标记形式，普通提炼返回 V_NOT_OVERRIDE。

const 角色脚本: GDScript = preload("res://scripts/battle/roles/role_maoxian.gd")

var 引擎: BattleEngine = null
var 角色: BattleRole = null
var 玩家: BattlePlayer = null


func _init() -> void:
	名称 = "12号冒险家提炼方式"


func 跑() -> void:
	await 等帧(1)
	_建引擎()
	# ---- 服务端 v_extract ----
	var 队友: BattlePlayer = 引擎.p(2)
	var 给队友: int = 角色.v_extract(
		[GConst.提炼天堂标记, 0, 0, 1, 0, 0, 1], 2, 1, [队友.id])
	检(给队友 == GConst.GE_SUCCESS, "给队友 1 颗应合法（实际 %d）" % 给队友)
	var 自己份: int = 角色.v_extract(
		[GConst.提炼天堂标记, 1, 0, 0, 0, 0, 0], 2, 1, [队友.id])
	检(自己份 == GConst.GE_INVALID_ACTION, "标记形式里带自己那份应被拒（实际 %d）" % 自己份)
	var 普通: int = 角色.v_extract([1, 0], 2, 1, [])
	检(普通 == BattleRole.V_NOT_OVERRIDE, "普通提炼应交给通用校验（实际 %d）" % 普通)

	# ---- 客户端方式层 ----
	var 旧我: int = Logic.my_player_id
	var 旧列表: Array[GPlayer] = []
	旧列表.append_array(Data.player_list)
	Logic.my_player_id = 1
	var 我: GPlayer = GPlayer.new(1, GConst.BLUE, "冒险家")
	我.role_id = 12
	我.energy_max = 3
	我.gem = 0
	我.crystal = 0
	var 友: GPlayer = GPlayer.new(2, GConst.BLUE, "队友")
	友.energy_max = 3
	var 敌: GPlayer = GPlayer.new(3, GConst.RED, "敌人")
	Data.player_list.clear()
	Data.player_list.append(我)
	Data.player_list.append(友)
	Data.player_list.append(敌)
	Data.blue.set_gem(2)
	Data.blue.set_crystal(1)
	Data.red.set_gem(0)
	Data.red.set_crystal(0)

	var 窗: Control = (load("res://scenes/BattleUIMobile.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(窗)
	await 等帧(1)
	窗.call("_冒险家12提炼")
	await 等帧(1)
	检(int(窗.get("_本地选项阶段")) == 7, "12 号提炼应先停在方式选择（实际阶段 %d）" % int(窗.get("_本地选项阶段")))
	var 选项: Array = 窗.get("_二级选项")
	检(选项.size() == 2, "提炼方式应有 2 个选项（实际 %d）" % 选项.size())
	if 选项.size() == 2:
		检(str((选项[0] as Dictionary).get("文本", "")) == GConst.按钮原文(1202, 0),
			"第一项应是「提炼给自己」：%s" % str((选项[0] as Dictionary).get("文本", "")))
		检(str((选项[1] as Dictionary).get("文本", "")) == GConst.按钮原文(1202, 1),
			"第二项应是「提炼给队友」：%s" % str((选项[1] as Dictionary).get("文本", "")))
	# 选「给自己」→ 普通提炼（不进天堂分配）
	窗.call("_选中二级选项", 1202, 0)
	窗.call("_确认12提炼方式")
	await 等帧(1)
	检(not bool(窗.get("_提炼全给一人")), "选「给自己」后不该走全给一人流程")
	检(int(窗.get("_本地选项阶段")) == 2, "选「给自己」应进入普通提炼的选星石（实际阶段 %d）" % int(窗.get("_本地选项阶段")))
	# 选「给队友」→ 天堂分配
	窗.call("_冒险家12提炼")
	await 等帧(1)
	窗.call("_选中二级选项", 1202, 1)
	窗.call("_确认12提炼方式")
	await 等帧(1)
	检(bool(窗.get("_提炼全给一人")), "选「给队友」后应进入整份交给一人")
	检(int(窗.get("_提炼阶段")) == 4, "选「给队友」后应停在点头像分配（实际阶段 %d）" % int(窗.get("_提炼阶段")))
	检(int(窗.get("_提炼总数")) == 2, "12 号没有额外提炼，总数上限应是基本 1~2")
	窗.queue_free()
	await 等帧(1)
	Data.player_list.clear()
	Data.player_list.append_array(旧列表)
	Logic.my_player_id = 旧我


func _建引擎() -> void:
	引擎 = BattleEngine.new()
	引擎.add_player(1, GConst.BLUE, "冒险家")
	引擎.add_player(2, GConst.BLUE, "队友")
	引擎.add_player(3, GConst.RED, "敌人")
	引擎.start_with_roles({})
	玩家 = 引擎.p(1)
	玩家.role_id = 12
	引擎.team_gem[GConst.BLUE] = 2
	引擎.team_crystal[GConst.BLUE] = 1
	角色 = 角色脚本.new()
	角色.setup(玩家, 引擎)
	玩家.role = 角色
