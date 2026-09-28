extends 自检用例
## 用例 1：数据表与素材齐全（卡表、卡面、角色立绘、界面音效文件）

## 表里的 0 号是表头名「角色」，不是真角色
const 非角色ID: Array[int] = [0]
## 源工程本身就没有的素材，不算缺失
const 已知缺立绘: Array[int] = [37]
## 代码里会用到的界面 wav 音效（Art.play_sfx 的入参）
const 界面音效: Array[String] = ["Equip", "Skill", "It's your turn", "TurnBegin"]
const 卡面目录: String = "res://资源/卡面/"
const 音效目录: String = "res://资源/音效/"


func _init() -> void:
	名称 = "数据与素材"


func 跑() -> void:
	await 等帧()
	检(not Data.card_db.is_empty(), "卡表为空（数据/cardDB.txt 没读到）")
	检(not Data.role_list.is_empty(), "角色表为空（数据/角色表 没读到）")

	var 缺卡面: Array[String] = []
	for 卡: GCard in Data.card_db:
		if Art.card_face(卡) == null:
			缺卡面.append("%d号" % 卡.id)
	检(缺卡面.is_empty(), "缺卡面：%s" % str(缺卡面))

	var 缺立绘: Array[String] = []
	for rid: Variant in Data.role_list.keys():
		if int(rid) in 非角色ID or int(rid) in 已知缺立绘:
			continue
		if Art.role_avatar(int(rid)) == null:
			缺立绘.append("%d(%s)" % [int(rid), Data.role_name(int(rid))])
	检(缺立绘.is_empty(), "缺立绘：%s" % str(缺立绘))

	for 名: String in 界面音效:
		var 找到: bool = false
		for 后缀: String in [".wav", ".ogg"]:
			if ResourceLoader.exists(音效目录 + 名 + 后缀):
				找到 = true
				break
		检(找到, "缺界面音效文件：%s" % 名)

	print("[自检] 卡表 %d 张、卡面文件 %d 个、角色 %d 个" % [
		Data.card_db.size(), DirAccess.get_files_at(卡面目录).size(), Data.role_list.size()])
