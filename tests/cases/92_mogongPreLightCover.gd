extends 自检用例
## 用例 92：魔弓三招「自动预亮本次使用的盖牌」
##
## 用户口径：服务端自己挑盖牌的三招，询问时要把这次要用到的盖牌提前选上、亮起来。
##   魔贯冲击 2601（含命中追加第二段）：亮第一张火系【充能】
##   多重射击 2603：亮第一张风系【充能】
##   雷光散射 2602：二级栏选 X 张时，亮前 X 张雷系【充能】
## 预亮只做高亮（_预亮盖牌），不写进 _sel_cards、不改变提交内容。

const 角色脚本: GDScript = preload("res://scripts/battle/roles/role_mogong.gd")

var 引擎: BattleEngine = null
var 角色: BattleRole = null
var 玩家: BattlePlayer = null


func _init() -> void:
	名称 = "魔弓预亮盖牌"


func 跑() -> void:
	await 等帧(1)
	var 旧我: int = Logic.my_player_id
	var 旧列表: Array[GPlayer] = []
	旧列表.append_array(Data.player_list)
	# 盖牌区的客户端数据是全局的：用完要还原，否则会污染后面的用例
	var 旧盖牌: Array[GCard] = []
	旧盖牌.append_array(Data.cover_cards)
	var 旧盖牌实例: Array[int] = []
	旧盖牌实例.append_array(Data.cover_iids)
	Logic.my_player_id = 1
	_建引擎()
	# 盖牌区：火、风、雷各 2 张（顺序：火1 雷1 风1 火2 雷2 风2）
	var 火: Array[int] = _同系攻击牌(GConst.CardElement.Fire, 2)
	var 风: Array[int] = _同系攻击牌(GConst.CardElement.Wind, 2)
	var 雷: Array[int] = _同系攻击牌(GConst.CardElement.Thunder, 2)
	检(火.size() == 2 and 风.size() == 2 and 雷.size() == 2, "卡库缺某系攻击牌（前提不成立）")
	玩家.cover_cards = [火[0], 雷[0], 风[0], 火[1], 雷[1], 风[1]] as Array[int]

	# 客户端从同一份数据读盖牌区
	var 我: GPlayer = GPlayer.new(1, GConst.BLUE, "魔弓")
	我.role_id = 26
	我.cover_cards_max = 6
	Data.player_list.clear()
	Data.player_list.append(我)
	Data.cover_cards = []
	Data.cover_iids = []
	for cid: int in 玩家.cover_cards:
		Data.cover_cards.append(Data.get_card(cid))
		Data.cover_iids.append(cid)
	var 窗: Control = (load("res://scenes/BattleUIMobile.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(窗)
	await 等帧(2)

	# ---- 1) 魔贯冲击：亮第一张火系【充能】 ----
	角色.p_timeline_1({"src": 1, "dst": 3, "is_active": true, "harm": {"point": 2}})
	var 问: Dictionary = _命令(1)
	检(int(问.get("respond_id", 0)) == 2601, "应下发魔贯冲击询问（实际 %s）" % str(问.get("respond_id", 0)))
	窗.call("_on_command", {"cmd_type": GConst.CmdType.Respond, "commands": [问]})
	await 等帧(2)
	var 预亮: Array = _取数组(窗, "_预亮盖牌")
	检(预亮 == ([火[0]] as Array[int]), "魔贯冲击应预亮第一张火系充能：%s" % str(预亮))
	检((窗.get("_sel_cards") as Array).is_empty(), "预亮不该写进 _sel_cards")
	窗.call("_清空待选")
	await 等帧(1)
	检(_取数组(窗, "_预亮盖牌").is_empty(), "询问结束后预亮应收掉")

	# ---- 2) 多重射击：走真实的「行动结束响应（聚合器）」询问，选中它后亮盖牌 ----
	_重置盖牌()
	角色._available_duo_chong = true
	角色._last_target = -1
	# 造一份行动结束响应：手里一张攻击牌 + 一张风系盖牌 + 一张迅捷赐福基础效果
	var 攻击牌: int = -1
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.is_attack():
			攻击牌 = c.id
			break
	var 迅捷牌: int = -1
	for c2: GCard in Data.card_db:
		if c2 != null and not c2.is_virtual and c2.has_skill_id(GConst.技能_迅捷赐福):
			迅捷牌 = c2.id
			break
	检(攻击牌 >= 0 and 迅捷牌 >= 0, "找不到攻击牌 / 迅捷赐福载体（前提不成立）")
	玩家.hand_cards = [攻击牌] as Array[int]
	检(引擎.add_basic_effect(1, 迅捷牌, 2, GConst.技能_迅捷赐福) == GConst.GE_SUCCESS,
		"迅捷赐福应能贴上")
	引擎.current_id = 1
	引擎._push_action_end_hooks("p_after_attack", {"player": 1}, false, 0)
	引擎.run()
	var 问2: Dictionary = _命令(1)
	检(not 问2.is_empty(), "行动结束响应没有下发询问")
	窗.call("_on_command", {"cmd_type": GConst.CmdType.Respond, "commands": [问2]})
	await 等帧(2)
	# 在响应列表里选中多重射击那一项
	var 序号: int = -1
	var 选项表: Array = 窗.get("_二级选项")
	for i: int in range(选项表.size()):
		if int((选项表[i] as Dictionary).get("技能号", 0)) == 2603:
			序号 = i
			break
	检(序号 >= 0, "行动结束响应里应有【多重射击】：%s" % str(选项表))
	if 序号 >= 0:
		窗.call("_选中二级选项", int(问2.get("respond_id", 0)), 序号)
		await 等帧(2)
		var 预亮2: Array = _取数组(窗, "_预亮盖牌")
		检(预亮2 == ([风[0]] as Array[int]), "多重射击应预亮第一张风系充能：%s" % str(预亮2))
		检(bool(窗.get("_selecting_cover")), "选中多重射击后应把盖牌区摆出来")
		var 盖牌区: Node = 窗.get("ChooseArea")
		检(盖牌区 != null and (盖牌区 as Control).visible, "选中多重射击后盖牌区应可见")
	窗.call("_清空待选")
	await 等帧(1)

	# ---- 3) 雷光散射：选 X 张亮前 X 张雷系【充能】 ----
	_重置盖牌()
	var 选项: Array = [
		{"text": "移除 1 张", "args": [1]},
		{"text": "移除 2 张", "args": [2]},
	]
	窗.call("_选择技能", 2602, GConst.ActionType.MagicSkill, 0, 0, [3, 4], [], 0, 0, 0,
		GConst.CardSource.Cover, "", 0, 0, 选项, null, 0)
	await 等帧(2)
	窗.call("_选中二级选项", 2602, 1)
	await 等帧(2)
	var 预亮3: Array = _取数组(窗, "_预亮盖牌")
	检(预亮3 == ([雷[0], 雷[1]] as Array[int]), "雷光散射选 2 张应预亮两张雷系充能：%s" % str(预亮3))
	窗.call("_选中二级选项", 2602, 0)
	await 等帧(2)
	var 预亮4: Array = _取数组(窗, "_预亮盖牌")
	检(预亮4 == ([雷[0]] as Array[int]), "雷光散射改选 1 张应只亮第一张：%s" % str(预亮4))

	窗.queue_free()
	await 等帧(1)
	Data.player_list.clear()
	Data.player_list.append_array(旧列表)
	Data.cover_cards = 旧盖牌
	Data.cover_iids = 旧盖牌实例
	Logic.my_player_id = 旧我


func _取数组(窗: Control, 名: String) -> Array:
	var v: Variant = 窗.get(名)
	return (v as Array) if v is Array else []


func _重置盖牌() -> void:
	玩家.cover_cards = Data.cover_iids.duplicate()


func _命令(pid: int) -> Dictionary:
	var 表: Array = (引擎._最后询问.get(pid, {}) as Dictionary).get("commands", [])
	return 表[0] if not 表.is_empty() else {}


func _同系攻击牌(元素: int, 数量: int) -> Array[int]:
	var out: Array[int] = []
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.is_attack() and c.element_enum() == 元素:
			out.append(c.id)
			if out.size() >= 数量:
				break
	return out


func _建引擎() -> void:
	引擎 = BattleEngine.new()
	引擎.add_player(1, GConst.BLUE, "魔弓")
	引擎.add_player(2, GConst.BLUE, "队友")
	引擎.add_player(3, GConst.RED, "敌一")
	引擎.add_player(4, GConst.RED, "敌二")
	引擎.start_with_roles({})
	玩家 = 引擎.p(1)
	玩家.role_id = 26
	角色 = 角色脚本.new()
	角色.setup(玩家, 引擎)
	玩家.role = 角色
