extends 自检用例
## 用例 82：二级栏「返回」的可用性与语义（圣弓 自动填充 / 圣煌降临）
##
## 用户反馈：点击选项后「取消」能用，「返回」却是置灰的；按「可以取消就应该可以返回」，
## 返回必须是可用的一步（返回＝退回上一层，取消＝放弃）。
##
## 回归点：
##   - 自动填充（3707/8807，mode 3 的本地第二层）：摆第二层时 `_本地二层` 还没落，
##     `_取消可用` 把「返回」按强制询问（can_cancel=false）算成不可用 → 置灰；
##   - 圣煌降临（3703/8803，mode 4 带效果选项）：技能配了「锁定不可取消」，
##     原来「返回」和「取消」一起失效；而且它的回调就是取消（退出技能），不是退回上一层。
##
## 覆盖：
##   - 自动填充第二层：「返回」存在且可用；点它退回第一层（本地二层清空、重新摆出晶/宝两项）；
##   - 圣煌降临：「返回」存在且可用；点它只清掉选中的效果（_已选参数 / _二级选中 归零），
##     仍停在技能上（_mode=4、_二级栏=true）；「取消」才是放弃技能（回 _mode=1）。

const 角色脚本: GDScript = preload("res://scripts/battle/roles/role_shenggong.gd")

var 引擎: BattleEngine = null
var 角色: BattleRole = null
var 玩家: BattlePlayer = null


func _init() -> void:
	名称 = "圣弓返回按钮"


func 跑() -> void:
	await 等帧(1)
	Logic.my_player_id = 1
	_建引擎()

	# ================= 自动填充 3707 =================
	玩家.set_crystal(1)
	角色.p_turn_end({"player": 1})
	var 命令表: Array = (引擎._最后询问.get(1, {}) as Dictionary).get("commands", [])
	检(not 命令表.is_empty(), "自动填充没有下发询问")
	var 窗: Control = (load("res://scenes/BattleUIMobile.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(窗)
	await 等帧(1)
	窗.call("_on_command", {"cmd_type": GConst.CmdType.Respond, "commands": 命令表})
	await 等帧(1)
	检((窗.get("_二级选项") as Array).size() == 2, "自动填充第一层应有两个资源选项")
	检(_返回按钮(窗) == null, "自动填充第一层（强制询问）不该有返回")
	窗.call("_选中二级选项", int(命令表[0].get("respond_id", 0)), 0)
	await 等帧(1)
	检(not (窗.get("_本地二层") as Dictionary).is_empty(), "点第一层选项后没有进本地第二层")
	检((窗.get("_二级选项") as Array).size() == 2, "自动填充第二层应有两个效果选项")
	var 返回一: 技能按钮 = _返回按钮(窗)
	检(返回一 != null, "自动填充第二层没有「返回」按钮")
	if 返回一 != null:
		检(not 返回一.plateButton.disabled, "自动填充第二层的「返回」是置灰的")
		返回一.plateButton.pressed.emit()
		await 等帧(1)
		检((窗.get("_本地二层") as Dictionary).is_empty(), "点「返回」后没有退出本地第二层")
		检((窗.get("_二级选项") as Array).size() == 2, "点「返回」后没有退回第一层的两个资源选项")
		检(_返回按钮(窗) == null, "退回第一层后不该还摆着「返回」")
	窗.queue_free()
	await 等帧(1)

	# ================= 圣煌降临 3703 =================
	var 项: Dictionary = {}
	for s: Dictionary in 角色.available_skills():
		if int(s.get("id", 0)) == 3703:
			项 = s
			break
	检(not 项.is_empty(), "圣煌降临不在技能栏里")
	var 窗2: Control = (load("res://scenes/BattleUIMobile.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(窗2)
	await 等帧(1)
	窗2.call("_选择技能", 3703, int(项.get("type", GConst.ActionType.MagicSkill)),
		int(项.get("need_card", 0)), int(项.get("need_target", 0)),
		项.get("targets", []), 项.get("cards", []), int(项.get("card_max", 0)),
		int(项.get("target_max", 0)), 0, GConst.CardSource.Hand, "",
		0, 0, 项.get("arg_choices", []), null, 0, [])
	await 等帧(1)
	var 返回二: 技能按钮 = _返回按钮(窗2)
	检(返回二 != null, "圣煌降临的二级栏没有「返回」按钮")
	if 返回二 != null:
		检(not 返回二.plateButton.disabled, "圣煌降临的「返回」是置灰的")
	# 先手动选中一项效果（资源不足时选项可能置灰，这里直接调选中，验证「返回」清的是选择状态）
	窗2.call("_选中二级选项", 3703, 0)
	await 等帧(1)
	检(not (窗2.get("_已选参数") as Array).is_empty(), "选中效果后 _已选参数 应非空")
	if 返回二 != null:
		返回二.plateButton.pressed.emit()
		await 等帧(1)
		检(int(窗2.get("_mode")) == 1 and not bool(窗2.get("_二级栏")),
			"点「返回」应退回上一层（行动阶段技能栏）")
		检((窗2.get("_已选参数") as Array).is_empty(), "退回后不该还留着已选效果")
	窗2.queue_free()
	await 等帧(1)

	# ================= 全量审计：所有「锁定不可取消」的技能 =================
	# 返回 => 只要按钮存在就必须可用（不再跟 _取消可用 连坐）；锁定只该锁「取消」。
	var 锁定技能: Array[int] = []
	for 键: Variant in GConst.技能指示器:
		if bool((GConst.技能指示器[键] as Dictionary).get("锁定不可取消", false)):
			锁定技能.append(int(键))
	检(锁定技能.size() >= 10, "带「锁定不可取消」的技能数量异常：%d" % 锁定技能.size())
	var 窗3: Control = (load("res://scenes/BattleUIMobile.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(窗3)
	await 等帧(1)
	var 灰的: Array = []
	for 技能号: int in 锁定技能:
		窗3.set("_mode", 4)
		窗3.set("_pending_skill_id", 技能号)
		窗3.set("_目标锁死", true)
		窗3.call("_进入二级技能栏", 技能号, null, [], Color(0, 0, 0, 0),
			Callable(窗3, "_on_cancel"))
		await 等帧(1)
		var 返回钮: 技能按钮 = _返回按钮(窗3)
		检(返回钮 != null, "锁定技能 %d 的二级栏没有「返回」" % 技能号)
		if 返回钮 != null and 返回钮.plateButton.disabled:
			灰的.append(技能号)
	检(灰的.is_empty(), "这些「锁定不可取消」技能的「返回」仍是置灰的：%s" % str(灰的))
	窗3.queue_free()
	await 等帧(1)


## 二级栏里那颗「返回」按钮（没有返回 null）
func _返回按钮(窗: Control) -> 技能按钮:
	for 子: Node in (窗.get("_技能按钮") as Array):
		if 子 is 技能按钮:
			var 钮: 技能按钮 = 子
			if 钮.visible and 钮.skillName != null and str(钮.skillName.text) == "返回":
				return 钮
	return null


func _建引擎() -> void:
	引擎 = BattleEngine.new()
	引擎.add_player(1, GConst.BLUE, "圣弓")
	引擎.add_player(2, GConst.RED, "靶子")
	引擎.add_player(3, GConst.BLUE, "队友")
	引擎.add_player(4, GConst.RED, "敌二")
	引擎.start_with_roles({})
	玩家 = 引擎.p(1)
	玩家.role_id = 37
	角色 = 角色脚本.new()
	角色.setup(玩家, 引擎)
	玩家.role = 角色
