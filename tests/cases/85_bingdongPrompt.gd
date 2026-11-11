extends 自检用例
## 用例 85：元素师【冰冻】的治疗子询问文案
##
## 冰冻（1102）造成伤害后，p_after_magic 里再问一次「指定角色 +1 治疗」。
## 这个子询问用的技能号 11021 没有技能表行；以前不带文案，客户端就落到
## 「强制询问」的兜底文案：「【冰冻】：请选1名目标，本次必须执行，不能取消」——看不出在做治疗。
## 现在文案取技能表 1102 的「提示」列：「【冰冻】：指定 1 名角色+1【治疗】」。
##
## 覆盖：p_after_magic 下发的询问 respond_id=11021、ask_text 就是这条提示、不能取消、
## 且不含「必须执行」。

const 角色脚本: GDScript = preload("res://scripts/battle/roles/role_yuansu.gd")
const 期望文案: String = "【冰冻】：指定 1 名角色+1【治疗】"

var 引擎: BattleEngine = null
var 角色: BattleRole = null
var 玩家: BattlePlayer = null


func _init() -> void:
	名称 = "冰冻治疗提示"


func 跑() -> void:
	await 等帧(1)
	_建引擎()
	# 技能表配置本身
	检(GConst.提示原文(GConst.技能_冰冻, 0) == 期望文案,
		"技能表 1102「提示」列不对：%s" % GConst.提示原文(GConst.技能_冰冻, 0))
	# 走 p_after_magic：应下发治疗目标询问，文案就用上面那条
	角色.p_after_magic({"player": 1, "action_id": GConst.技能_冰冻})
	var 命令表: Array = (引擎._最后询问.get(1, {}) as Dictionary).get("commands", [])
	检(not 命令表.is_empty(), "冰冻没有下发治疗目标询问")
	if 命令表.is_empty():
		return
	var 命令: Dictionary = 命令表[0]
	检(int(命令.get("respond_id", 0)) == GConst.技能_冰冻治疗,
		"治疗询问号不是 11021：%d" % int(命令.get("respond_id", 0)))
	var 文案: String = str(命令.get("ask_text", ""))
	检(文案 == 期望文案, "冰冻治疗询问文案不对：%s" % 文案)
	检(not 文案.contains("必须执行"), "冰冻治疗询问不应出现「必须执行」兜底文案：%s" % 文案)
	检(not bool(命令.get("can_cancel", true)), "冰冻治疗询问应不可取消")
	var 参数: Array = 命令.get("args", []); 检(参数.size() >= 2 and int(参数[1]) == 1, "冰冻治疗询问应让选 1 名目标：%s" % str(参数))
	检((命令.get("dst_ids", []) as Array).size() == 4, "冰冻治疗询问的目标白名单应是全体 4 人")


func _建引擎() -> void:
	引擎 = BattleEngine.new()
	引擎.add_player(1, GConst.BLUE, "元素师")
	引擎.add_player(2, GConst.BLUE, "队友")
	引擎.add_player(3, GConst.RED, "敌一")
	引擎.add_player(4, GConst.RED, "敌二")
	引擎.start_with_roles({})
	玩家 = 引擎.p(1)
	玩家.role_id = 11
	角色 = 角色脚本.new()
	角色.setup(玩家, 引擎)
	玩家.role = 角色
