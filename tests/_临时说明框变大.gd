extends Node
## 临时诊断：先弹角色说明、再弹技能说明，看说明框尺寸怎么变。用完即删。

func _ready() -> void:
	await get_tree().process_frame
	Logic.my_player_id = 1
	var 玩家: Array[GPlayer] = [GPlayer.new(1, GConst.BLUE, "我"), GPlayer.new(2, GConst.RED, "敌")]
	Data.player_list = 玩家
	玩家[0].role_id = 27
	Data.hand_cards = []
	Data.cover_cards = []

	var 窗: Control = (load("res://scenes/BattleUIMobile.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(窗)
	await get_tree().process_frame
	Logic.game_info_updated.emit({"is_started": true, "blue_morale": 15, "red_morale": 15,
		"blue_gem": 0, "blue_crystal": 0, "red_gem": 0, "red_crystal": 0})
	await get_tree().process_frame
	await get_tree().process_frame

	var 框: PanelContainer = 窗.get("_说明框")
	var 文本: RichTextLabel = 窗.get("_说明文本")

	# 1) 先弹角色说明
	var 我面板: 战斗玩家面板 = null
	for 面板: 战斗玩家面板 in (窗.get("_面板列表") as Array):
		if 面板 != null and 面板.ID == 1:
			我面板 = 面板
	我面板.emit_signal("mouse_entered")
	await get_tree().process_frame
	await get_tree().process_frame
	_报(框, 文本, "弹完角色说明")
	我面板.emit_signal("mouse_exited")
	await get_tree().process_frame
	await get_tree().process_frame

	# 2) 再弹技能说明
	var 技能: Control = (load("res://scenes/prefabs/battlemobile/Skill.tscn") as PackedScene).instantiate()
	(窗.get("ChildrenSkillArea") as GridContainer).add_child(技能)
	技能.call("设置技能", 2701)
	窗.call("_显示技能区")
	技能.connect("悬停", Callable(窗, "_显示技能说明"))
	await get_tree().process_frame
	技能.get("plateButton").emit_signal("mouse_entered")
	await get_tree().process_frame
	await get_tree().process_frame
	_报(框, 文本, "弹完技能说明")
	print("  技能说明文本=%s" % str(文本.text))
	get_tree().quit(0)


func _报(框: PanelContainer, 文本: RichTextLabel, 场合: String) -> void:
	print("[%s] 框尺寸=%s 文本最小尺寸=%s 自定义最小=%s fit_content=%s 字号=%s" % [
		场合, str(框.size), str(文本.get_combined_minimum_size()), str(文本.custom_minimum_size),
		str(文本.fit_content), str(文本.get_theme_font_size("normal_font_size"))])
