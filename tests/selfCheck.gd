extends Node
## 自检运行器（headless，不开窗口）
## 用法：godot --headless --path <工程> res://tests/selfCheck.tscn
## 跑 tests/用例/ 下全部用例，逐条打印 [通过] / [失败]，最后一行是汇总；有用例失败时退出码为 1。

const 用例目录: String = "res://tests/cases/"

## 关键脚本：先确认它们能加载。改坏语法时这些脚本 load() 返回 null，
## 界面用例会因为「窗口没有脚本、get/call 全是 null」而**假通过**（踩过一次）。
const 关键脚本: Array[String] = [
	"res://scripts/battle/battle_engine.gd",
	"res://scripts/battle/battle_role.gd",
	"res://scripts/battle/battle_player.gd",
	"res://scripts/ui/battle_mobile.gd",
	"res://scripts/ui/tip_box.gd",
]


func _ready() -> void:
	# 可选：只跑名字里含某个子串的用例（排查不稳定用例时用，整包跑太慢）
	#   godot --headless --path <工程> res://tests/selfCheck.tscn -- --case=战斗法师
	var 筛选: String = ""
	for 参数: String in OS.get_cmdline_user_args():
		if 参数.begins_with("--case="):
			筛选 = 参数.trim_prefix("--case=")

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

	# 关键脚本先验一遍：坏了就别跑用例（否则界面用例会全员假通过）。
	# 注意 load() 对「有语法错的脚本」仍可能返回对象，必须用 reload() 看编译结果。
	var 坏: Array[String] = []
	for p: String in 关键脚本:
		var 脚本: GDScript = load(p) as GDScript
		if 脚本 == null or 脚本.reload() != OK:
			坏.append(p)
	if not 坏.is_empty():
		print("[自检] 关键脚本加载失败（语法错？）：%s" % str(坏))
		get_tree().quit(2)
		return
	if not 筛选.is_empty():
		var 保留: Array[String] = []
		for 路径: String in 路径列表:
			if 路径.contains(筛选):
				保留.append(路径)
		路径列表 = 保留

	var 通过数: int = 0
	var 失败数: int = 0
	for 路径: String in 路径列表:
		var 脚本: GDScript = load(路径)
		# 用例脚本语法坏时不要 new 出 null：那会让 await 永远等不到，整包挂死（79 号用例踩过）
		if 脚本 == null or not 脚本.can_instantiate():
			print("[失败] %s：脚本加载失败（语法错？）" % 路径)
			失败数 += 1
			continue
		var 用例: 自检用例 = 脚本.new()
		add_child(用例)
		# 名称筛选（名称在 _init 里就定好了）：--case=战斗法师 只跑名字含「战斗法师」的用例
		if not 筛选.is_empty() and not 用例.名称.contains(筛选) and not 路径.contains(筛选):
			用例.queue_free()
			continue
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
