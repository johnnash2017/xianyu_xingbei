extends 自检用例
## 用例 15：场景 / 资源文件里引用的外部资源都还在
## 为什么单列一条：导出时引用缺失不是「少一张图」那么轻 —— 导出后的 .scn 会整份加载失败，
## 连带 preload 它的脚本一起失效。之前删掉 playerSelected.png 后，Skill.tscn 还引着它，
## 导出包里的战斗界面脚本整个没挂上（只剩默认面板、无法操作），而编辑器里只打印一行 Parse Error。
## 这里把「文件还在不在」提前查出来，别等到打包后的 Steam 客户端才发现。

## 只查这些后缀：场景与资源文件（脚本里的 preload 在导出时同样致命，但路径写法多样，
## 这里先兜住绝大多数的 .tscn / .tres 引用）
const 查的后缀: Array[String] = [".tscn", ".tres"]


func _init() -> void:
	名称 = "场景资源引用"


func 跑() -> void:
	await 等帧(1)
	var 缺失: Array[String] = []
	_扫目录("res://", 缺失)
	检(缺失.is_empty(), "场景 / 资源引用了不存在的文件：\n%s" % "\n".join(缺失))


func _扫目录(目录: String, 缺失: Array[String]) -> void:
	var d: DirAccess = DirAccess.open(目录)
	if d == null:
		return
	for 子目录: String in d.get_directories():
		# .godot 是导入缓存，addons 是第三方插件，都不归本用例管
		if 子目录.begins_with(".") or 子目录 == "addons":
			continue
		_扫目录(目录.path_join(子目录), 缺失)
	for 文件: String in d.get_files():
		var 是目标: bool = false
		for 后缀: String in 查的后缀:
			if 文件.ends_with(后缀):
				是目标 = true
				break
		if 是目标:
			_查引用(目录.path_join(文件), 缺失)


## 把一行里的 `path="res://xxx"` 解析出来逐个查（.tscn / .tres 的 ext_resource 就是这种写法）
func _查引用(文件路径: String, 缺失: Array[String]) -> void:
	var f: FileAccess = FileAccess.open(文件路径, FileAccess.READ)
	if f == null:
		return
	var 文本: String = f.get_as_text()
	f.close()
	for 行: String in 文本.split("\n"):
		var 标记: int = 行.find("path=\"res://")
		if 标记 < 0:
			continue
		var 起点: int = 标记 + "path=\"res://".length()
		var 终点: int = 行.find("\"", 起点)
		if 终点 < 0:
			continue
		var 资源路径: String = 行.substr(起点, 终点 - 起点)
		if 资源路径.begins_with(".godot/"):
			continue
		if not FileAccess.file_exists("res://" + 资源路径):
			缺失.append("%s → res://%s" % [文件路径, 资源路径])
