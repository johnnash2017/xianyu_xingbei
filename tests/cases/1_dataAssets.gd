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

	# 冒险家两版：12＝冒险家，89＝冒险家Trick，脚本与头像资源都必须各自齐全
	检(str(Data.role_list.get(12, "")) == "冒险家", "12 号角色名不是「冒险家」")
	检(str(Data.role_list.get(89, "")) == "冒险家Trick", "89 号角色名不是「冒险家Trick」")
	检(Data.role_pool.has(12) and Data.role_pool.has(89), "冒险家两版没有同时进入可选角色池")
	检(Data.role_script(12) == "res://scripts/battle/roles/role_maoxian.gd", "12 号角色脚本路径不对")
	检(Data.role_script(89) == "res://scripts/battle/roles/role_maoxian_trick.gd", "89 号角色脚本路径不对")
	检(ResourceLoader.exists(Data.role_script(89)), "89 号角色脚本不存在")
	检(load(Data.role_script(89)) != null, "89 号角色脚本无法加载/编译")
	检(Data.role_skills(12) == [1201, 1202, 1203, 1205, 1206], "12 号冒险家的技能号被改坏了")
	检(Data.role_skills(89) == [8901, 8902, 8903, 8905, 8906],
		"89 号冒险家Trick 应引用一套独立的 Trick 技能号，实际：%s" % str(Data.role_skills(89)))
	检(GConst.技能号("技能#欺诈Trick") == 8901, "技能#欺诈Trick 的脚本号没接上")
	检(GConst.技能号("技能#冒险者天堂Trick") == 8902, "技能#冒险者天堂Trick 的脚本号没接上")
	检(GConst.技能号("技能#偷天换日Trick") == 8903, "技能#偷天换日Trick 的脚本号没接上")
	检(GConst.技能行(8901).size() > 0 and GConst.技能行(8902).size() > 0
		and GConst.技能行(8903).size() > 0 and GConst.技能行(8905).size() > 0
		and GConst.技能行(8906).size() > 0, "Trick 技能行有缺失")
	检(GConst.技能指示器.has(GConst.技能_欺诈Trick)
		and GConst.技能指示器.has(GConst.技能_冒险者天堂Trick)
		and GConst.技能指示器.has(GConst.技能_偷天换日Trick), "Trick 的冒险家技能没接上技能指示器")
	检(Art.role_hero(89) != null, "89 号冒险家Trick 缺选角立绘")
	检(ResourceLoader.exists("res://assets/textures/hero/small/89S.png"), "89 号缺战斗小头像")
	检(ResourceLoader.exists("res://assets/textures/hero/large/89L.png"), "89 号缺战斗大头像")
	检(Audio.有声效("89"), "89 号冒险家Trick 缺回合语音")

	# 圣弓两版：37＝圣弓，88＝原初之弓Trick，技能与资源各自独立
	检(str(Data.role_list.get(37, "")) == "圣弓", "37 号角色名不是「圣弓」")
	检(str(Data.role_list.get(88, "")) == "原初之弓Trick", "88 号角色名不是「原初之弓Trick」")
	检(Data.role_pool.has(37) and Data.role_pool.has(88), "圣弓两版没有同时进入可选角色池")
	检(Data.role_script(37) == "res://scripts/battle/roles/role_shenggong.gd", "37 号角色脚本路径不对")
	检(Data.role_script(88) == "res://scripts/battle/roles/role_shenggong_trick.gd", "88 号角色脚本路径不对")
	检(load(Data.role_script(88)) != null, "88 号原初之弓Trick 脚本无法加载/编译")
	检(Data.role_skills(37) == [3701, 3702, 3703, 3704, 3705, 3706, 3707],
		"37 号圣弓的新技能号不对：%s" % str(Data.role_skills(37)))
	检(Data.role_skills(88) == [8801, 8802, 8803, 8804, 8805, 8806, 8808, 8807],
		"88 号原初之弓Trick 应引用独立的 Trick 技能号，实际：%s" % str(Data.role_skills(88)))
	检(GConst.技能号("技能#圣屑飓暴Trick") == 8802, "技能#圣屑飓暴Trick 的脚本号没接上")
	检(GConst.技能号("技能#圣光爆裂Trick") == 8804, "技能#圣光爆裂Trick 的脚本号没接上")
	检(GConst.技能号("技能#圣流星弹Trick") == 8805, "技能#圣流星弹Trick 的脚本号没接上")
	检(GConst.技能指示器.has(GConst.技能_圣屑飓暴Trick)
		and GConst.技能指示器.has(GConst.技能_圣光爆裂Trick)
		and GConst.技能指示器.has(GConst.技能_圣流星弹Trick), "原初之弓Trick 技能没接上技能指示器")
	检(int(GConst.技能子步骤母号.get(88021, 0)) == 8802, "原初之弓Trick 圣屑未命中子步骤没有映射")
	检(Art.role_hero(88) != null, "88 号原初之弓Trick 缺选角立绘")
	检(ResourceLoader.exists("res://assets/textures/hero/small/88S.png"), "88 号缺战斗小头像")
	检(ResourceLoader.exists("res://assets/textures/hero/large/88L.png"), "88 号缺战斗大头像")
	检(GConst.圣弓角色号.has(88), "原初之弓Trick 没有进入圣弓角色判断")
	var 弓引擎: BattleEngine = BattleEngine.new()
	弓引擎.add_player(1, GConst.BLUE, "弓手")
	var 弓玩家: BattlePlayer = 弓引擎.p(1)
	弓玩家.role_id = 88
	var 弓角色: BattleRole = BattleRole.create(88, 弓玩家, 弓引擎)
	检(弓角色 != null, "88 号原初之弓Trick 无法创建")
	if 弓角色 != null:
		var 弓技能号: Array[int] = []
		for 技术: Dictionary in 弓角色.available_skills():
			弓技能号.append(int(技术.get("id", 0)))
		检(弓技能号.has(8802) and 弓技能号.has(8803) and 弓技能号.has(8804)
			and 弓技能号.has(8806) and 弓技能号.has(8808),
			"88 号原初之弓Trick 的可用技能号不对：%s" % str(弓技能号))

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
