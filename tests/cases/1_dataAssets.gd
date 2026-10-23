extends 自检用例
## 用例 1：数据表与素材齐全（卡表、卡面、界面音效文件）
## 立绘 / 形态图不作为自检项：这两类素材按需补，不作为完整性门槛。

## 代码里会用到的界面 wav 音效（Art.play_sfx 的入参）
## TurnBegin / Skill / It's your turn 是原版客户端遗留素材，均已删除（2026-10-22）；
## 现在只剩按钮点击音 Equip
const 界面音效: Array[String] = ["Equip"]
const 卡面目录: String = "res://assets/textures/card/"
const 音效目录: String = "res://assets/media/sfx/"


func _init() -> void:
	名称 = "数据与素材"


func 跑() -> void:
	await 等帧()
	检(not Data.card_db.is_empty(), "卡表为空（DataTables.gd 的卡表没读到）")
	检(not Data.role_list.is_empty(), "角色表为空（数据/角色表 没读到）")

	var 缺卡面: Array[String] = []
	for 卡: GCard in Data.card_db:
		if 卡.is_virtual:
			continue   # 虚拟牌（五系束缚/挑衅/灵魂链接/同生共死/永恒乐章）本来就没有卡面
		if Art.card_face(卡) == null:
			缺卡面.append("%d号" % 卡.id)
	检(缺卡面.is_empty(), "缺卡面：%s" % str(缺卡面))

	# 卡面优先级：card/ 根目录与 card/新图标/ 各有一套同名图，索引必须取根目录那份正式卡面。
	# 导出后 DirAccess 的枚举顺序和编辑器不一样，这里把「取哪一份」定死，别到导出包里才发现。
	var 卡面取错: Array[String] = []
	var 卡面所在目录: DirAccess = DirAccess.open("res://assets/textures/card/")
	if 卡面所在目录 != null:
		for 文件: String in 卡面所在目录.get_files():
			if not 文件.ends_with(".png"):
				continue
			var 应取: String = "res://assets/textures/card/" + 文件
			var 实际: String = AssetIndex.image(文件.get_basename())
			if 实际 != 应取:
				卡面取错.append("%s → %s" % [文件, 实际])
	检(卡面取错.is_empty(), "卡面取到了子目录里的备用图：%s" % str(卡面取错))

	# 表驱动素材（状态图标 / 独有图标 / 指示物 / 命格图标）：名字都配在代码常量或数据表里，
	# 编辑器引用兜不住，只能在这里逐个查
	var 缺状态图标: Array[String] = []
	for 卡名: Variant in Art.STATUS_ICON.keys():
		if Art.status_icon(str(卡名)) == null:
			缺状态图标.append(str(卡名))
	检(缺状态图标.is_empty(), "缺状态图标：%s" % str(缺状态图标))

	var 缺独有图标: Array[String] = []
	for i: int in range(Art.EXCLUSIVE_ICON.size()):
		if Art.exclusive_icon(i) == null:
			缺独有图标.append(Art.EXCLUSIVE_ICON[i])
	检(缺独有图标.is_empty(), "缺独有图标：%s" % str(缺独有图标))

	var 缺指示物: Array[String] = []
	for i: int in range(Art.TOKEN_ICON.size()):
		if Art.token_icon(i) == null:
			缺指示物.append(Art.TOKEN_ICON[i])
	检(缺指示物.is_empty(), "缺指示物：%s" % str(缺指示物))

	var 缺命格图标: Array[String] = []
	for 命格: Variant in Art.FATE_PATTERN_ICON.keys():
		if Art.role_fate_pattern_icon(str(命格)) == null:
			缺命格图标.append(str(命格))
	检(缺命格图标.is_empty(), "缺命格图标：%s" % str(缺命格图标))

	for 名: String in 界面音效:
		var 找到: bool = false
		for 后缀: String in [".wav", ".ogg"]:
			if ResourceLoader.exists(音效目录 + 名 + 后缀):
				找到 = true
				break
		检(找到, "缺界面音效文件：%s" % 名)

	print("[自检] 卡表 %d 张、卡面文件 %d 个、角色 %d 个" % [
		Data.card_db.size(), DirAccess.get_files_at(卡面目录).size(), Data.role_list.size()])
