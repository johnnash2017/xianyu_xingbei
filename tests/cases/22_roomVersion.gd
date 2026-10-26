extends 自检用例
## 房间角色版本：角色表版本列读取、版本掩码过滤、协议字段与建房版本复选框。

func _init() -> void:
	名称 = "房间角色版本"


func 跑() -> void:
	await 等帧(1)
	var 十周年: int = 1 << 1
	var 特典: int = 1 << 5
	检(Data.role_version(37) == 1, "37 号圣弓应属于十周年，实际 %d" % Data.role_version(37))
	检(Data.role_version(88) == 5 and Data.role_version(89) == 5,
		"88/89 号应属于特典，实际 %d/%d" % [Data.role_version(88), Data.role_version(89)])
	var 版本值: Array[int] = []
	for 项: Dictionary in Data.role_version_options:
		版本值.append(int(项.get("value", 0)))
	检(版本值.has(1) and 版本值.has(5), "建房版本选项缺少十周年/特典：%s" % str(版本值))
	var 全部: int = Data.role_versions_all_mask()
	检((全部 & 十周年) != 0 and (全部 & 特典) != 0, "全部版本掩码没有覆盖十周年/特典：%d" % 全部)

	var 十周年池: Array[int] = Data.role_pool_for_versions(十周年)
	检(十周年池.has(37), "十周年房间应包含 37 号圣弓")
	检(not 十周年池.has(88) and not 十周年池.has(89),
		"十周年房间不应包含特典角色：%s" % str(十周年池))
	var 特典池: Array[int] = Data.role_pool_for_versions(特典)
	检(特典池.has(88) and 特典池.has(89), "特典房间应包含 88/89")
	检(not 特典池.has(37), "特典房间不应包含十周年角色")
	检(Data.role_pool_for_versions(全部).size() == Data.role_pool.size(),
		"全部版本过滤后应等于完整角色池")
	# 服务端实际开局/选角用的池也必须按房间版本过滤（不能只用 Data 层测试）
	var 服务端: LocalServer = LocalServer.new()
	var 房间池: Array = 服务端.call("_房间角色池", {"role_versions": 十周年})
	检(房间池.has(37) and not 房间池.has(88), "服务端角色池没有按房间版本过滤：%s" % str(房间池))
	检(Data.role_versions_text(全部).contains("十周年")
		and Data.role_versions_text(全部).contains("特典"),
		"全部版本的中文显示不对：%s" % Data.role_versions_text(全部))

	# 房间列表/建房请求必须真的能把版本带过协议
	var 房间信息: Dictionary = {
		"room_id": 1, "room_name": "版本测试", "max_player": 4,
		"role_versions": 全部, "role_strategy": GConst.RoleStrategy.Random,
	}
	var 信息解码: Dictionary = ProtoCodec.decode_named("RoomInfo",
		ProtoCodec.encode_named("RoomInfo", 房间信息))
	检(int(信息解码.get("role_versions", -1)) == 全部,
		"房间列表的房间版本没有过 RoomInfo 协议：%s" % str(信息解码.get("role_versions", null)))
	var 建房: Dictionary = {
		"room_name": "版本测试", "max_player": 4,
		"role_strategy": GConst.RoleStrategy.Random, "seat_mode": GConst.SeatMode.Random,
		"role_versions": 十周年,
	}
	var 建房解码: Dictionary = ProtoCodec.decode(GConst.Msg.CreateRoomReq,
		ProtoCodec.encode(GConst.Msg.CreateRoomReq, 建房))
	检(int(建房解码.get("role_versions", -1)) == 十周年,
		"建房请求的角色版本没有过协议：%s" % str(建房解码.get("role_versions", null)))

	# 全角色预览要按版本分组，版本枚举越小越靠前
	var 预览: Control = load("res://scripts/ui/role_pick.gd").new()
	var 预览分组: Array = 预览.call("_预览分组")
	var 预览版本: Array[int] = []
	for 组: Dictionary in 预览分组:
		预览版本.append(int(组.get("version", -1)))
	检(预览版本.size() >= 2 and 预览版本[0] == 1
		and 预览版本[预览版本.size() - 1] == 5,
		"全角色预览版本分组顺序不对：%s" % str(预览版本))
	预览.free()

	# 大厅建房面板必须有版本复选框，默认至少开启一个版本
	UI.goto_lobby()
	await 等帧(2)
	var 厅: Node = UI.current
	if 厅 == null or not 厅.has_method("_读取版本掩码"):
		检(false, "大厅脚本没有版本复选框逻辑")
		return
	var 版本选项: HBoxContainer = 厅.get("版本选项") as HBoxContainer
	检(版本选项 != null and 版本选项.get_child_count() > 0, "建房面板没有版本复选框")
	if 版本选项 != null and 版本选项.get_child_count() > 0:
		var 勾选数: int = 0
		for 子: Node in 版本选项.get_children():
			var 钮: CheckBox = 子 as CheckBox
			if 钮 != null and 钮.button_pressed:
				勾选数 += 1
		检(勾选数 > 0, "建房面板默认没有勾选任何版本")
		检(int(厅.call("_读取版本掩码")) > 0, "建房面板读出的版本掩码为 0")
	# 房间列表行要显示「房间开启的角色版本」，不是游戏客户端版本
	var 列表行: Dictionary = 厅.call("_房间行", {
		"room_id": 1, "room_name": "版本房", "max_player": 4,
		"now_player": 1, "role_versions": 十周年, "version": Cfg.游戏版本(),
	})
	var 列表列: PackedStringArray = 列表行.get("列", PackedStringArray())
	检(列表列.size() == 7, "房间列表行应新增「角色版本」列，实际 %d 列" % 列表列.size())
	if 列表列.size() == 7:
		检(列表列[4].contains("十周年"), "房间列表没有显示角色版本：%s" % 列表列[4])
	# 全角色预览左侧版本列表：点按钮跳到对应版本分组
	var 预览层: Control = load("res://scenes/role_pick.tscn").instantiate()
	add_child(预览层)
	await 等帧(1)
	预览层.call("进入全角色预览")
	await 等帧(1)
	var 按钮区: VBoxContainer = 预览层.get("版本按钮区") as VBoxContainer
	检(按钮区 != null and 按钮区.get_child_count() >= 2, "全角色预览左侧没有版本按钮")
	if 按钮区 != null and 按钮区.get_child_count() >= 2:
		var 第二钮: Button = 按钮区.get_child(1) as Button
		第二钮.pressed.emit()
		await 等帧()
		检(int(预览层.get("滚动").get("scroll_vertical")) > 0,
			"点击第二个版本按钮后没有跳到对应版本")
		var 列表右: float = (预览层.get("版本列表") as Control).get_global_rect().end.x
		var 卡片左: float = (预览层.get("滚动") as Control).get_global_rect().position.x
		检(卡片左 >= 列表右, "左侧版本列表和角色卡重叠：列表右 %.1f，卡片左 %.1f" % [列表右, 卡片左])
	预览层.queue_free()
	await 等帧(1)

	# 这是第 22 个用例，按文件名会排在界面用例之前；把当前界面还给登录界面，
	# 后面的用例仍按「启动后是登录界面」的约定跑。
	UI.goto_enter()
	await 等帧(2)
