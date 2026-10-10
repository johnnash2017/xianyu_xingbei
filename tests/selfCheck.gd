extends Node
## 自检运行器（headless，不开窗口）
## 用法：godot --headless --path <工程> res://tests/selfCheck.tscn
## 跑 tests/用例/ 下全部用例，逐条打印 [通过] / [失败]，最后一行是汇总；有用例失败时退出码为 1。

const 用例目录: String = "res://tests/cases/"


func _ready() -> void:
	# 等一帧：启动时 root 正忙于挂主场景，这时 add_child 会失败
	await get_tree().process_frame
	# 主场景照真实启动走一遍（登录界面由它自动挂到界面层），用例都在它之上跑
	var 主: Control = (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(主)
	await get_tree().process_frame
	await get_tree().process_frame

	var 路径列表: Array[String] = []
	for 文件: String in DirAccess.get_files_at(用例目录):
		if 文件.ends_with(".gd"):
			路径列表.append(用例目录 + 文件)
	路径列表.sort()

	var 通过数: int = 0
	var 失败数: int = 0
	for 路径: String in 路径列表:
		var 脚本: GDScript = load(路径)
		var 用例: 自检用例 = 脚本.new()
		add_child(用例)
		await 用例.跑()
		if 用例.失败.is_empty():
			通过数 += 1
			print("[通过] %s" % 用例.名称)
		else:
			失败数 += 1
			for 说明: String in 用例.失败:
				print("[失败] %s：%s" % [用例.名称, 说明])
		用例.queue_free()
	print("[自检] 用例 %d 个：通过 %d，失败 %d" % [通过数 + 失败数, 通过数, 失败数])
	# 先收掉场景再退出，免得报一堆 RID / 资源仍在用的退出噪音
	主.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if 失败数 == 0 else 1)
