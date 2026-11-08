## 角色技能说明文本的组装与排版（上色 + 悬停提示）。
## 原先这里是个「英雄详情窗」（搬自参考工程 InfomationUI）：战斗内点头像弹它；
## 现在战斗内也改成和选角界面一样「鼠标指向头像就地弹提示」，那个窗不再需要，
## 只留下这组静态函数 —— 谁要显示角色技能说明都调 悬浮提示()。
class_name 角色技能提示
extends RefCounted

## 技能文本里正文行的前缀（data_interface._拼技能文本 给每条技能正文加的「　　」）；
## 拿它区分「四个一级标题」（无前缀）与「技能正文」（有前缀）
const 正文前缀: String = "　　"
## 失效技能的零宽标记：\u2060 标在「每一条失效技能的正文行」类型之后，仅用于把该行置灰。
## 不画删除线；用零宽字符而不是 BBCode 的 [s]，避免字体自带的细线又冒出来。
const 失效行标记: String = "\u2060"
## 梦想剑 4503 启用时技能说明的绿：与卡面「独有技」技能名同色（CardUI.技能字色_有）
const 梦想剑启用色: String = "A9FF00"
## 悬停提示里技能正文的字号
const 提示框正文字号: int = 18
## 悬停提示里角色名的字号（原 72 的一半）
const 提示框姓名行字号: int = 36
## 悬停提示里角色名后面「势力」的字号：比名字小一档，跟着技能说明尺寸一起等比缩放
const 提示框势力字号: int = 22
## 悬停提示里「普通技 / 独有技 / 专属技 / 必杀技」这些分段标题的字号（原 54 的一半）
const 提示框标题字号: int = 27
## 分段标题上方的留白：用一行「小字号空行」撑出来（字号越小留白越少）。
## 标题字号比正文大，行盒自带一点余量，但它和上面那段技能之间的间距还是比正文行之间更挤，
## 这里补一行，让每类标题和上一坨技能之间有和其他间距一样的呼吸。
const 标题上方留白字号: int = 8
## 悬停提示右下角「专属标识物」那一行的字号缩放（相对技能正文）：脚注性质，压小一档
const 提示框标识物字号缩放: float = 0.9
## 那一行的颜色：比正文暗的青灰，看一眼就知道是附加信息，不和技能说明抢眼
const 提示框标识物颜色: Color = Color(0.76, 0.8, 0.88)
## 无限符号 ∞ 的额外字号：正文字体里它只画到数字一半高，脚注行又压小了一档，
## 不放大就只剩几个像素。只在显示时套 [font_size]，标识物一览() 返回的仍是纯文本
const 提示框无限字号增量: int = 8
## 命格描边统一的不透明度（50%）：改这一处就能整体调浓淡
const 命格描边透明度: float = 0.5
## 角色说明框的描边颜色：按命格区分 —— 血红 / 咏橙 / 技绿 / 圣蓝 / 幻紫。
## 统一 50% 不透明度：颜色能一眼分开，又不抢技能正文的注意力。
## 键是角色表「命格」列的文字；没配命格（白板 / 未启用角色）返回全透明，
## 由 说明提示框 用自己的默认描边（见 tip_box._默认描边）
const 命格描边颜色: Dictionary = {
	"血": Color(0.86, 0.22, 0.22, 命格描边透明度),
	"咏": Color(1.0, 0.62, 0.16, 命格描边透明度),
	"技": Color(0.36, 0.85, 0.36, 命格描边透明度),
	"圣": Color(0.38, 0.64, 1.0, 命格描边透明度),
	"幻": Color(0.70, 0.42, 0.96, 命格描边透明度),
}


## 这个角色说明框该用的描边颜色；命格没配时返回 alpha=0 的颜色（＝用提示框默认描边）
static func 描边颜色(角色号: int) -> Color:
	var 色: Variant = 命格描边颜色.get(Data.role_fate_pattern(角色号), null)
	return 色 if 色 is Color else Color(0, 0, 0, 0)


## 悬停提示的完整文本：角色名一行 + 技能说明（上色排版）+ 右下角的专属标识物一览，含 BBCode。
## 战斗外选角卡与战斗内玩家头像的悬浮说明都用它 —— 组装规则只有这一份。
## 字号缩放：调用方想让整块文字等比小一点时传（战斗内的框要压一档），1.0＝原样
## 对局中：只有战斗内传 true（选角界面传 false）。剑之子的倾慕/剑守誓言要按场上有没有
## 剑之魔女动态改文本；选角时没有对局，按「剑之魔女不在场」处理（追加的借用技划掉）。
static func 悬浮提示(角色号: int, 字号缩放: float = 1.0, 对局中: bool = false) -> String:
	var 正文号: int = maxi(1, int(round(float(提示框正文字号) * 字号缩放)))
	var 姓名号: int = maxi(1, int(round(float(提示框姓名行字号) * 字号缩放)))
	var 标题号: int = maxi(1, int(round(float(提示框标题字号) * 字号缩放)))
	var 角色名: String = Data.role_name(角色号)
	var 姓名: String = Data.role_personal_name(角色号)
	if 姓名 != "":
		角色名 = "%s %s" % [角色名, 姓名]
	var 文本: String = "[font_size=%d]%s[/font_size]" % [姓名号, 角色名]
	# 势力名接在名字后面、用空格隔开，字号比名字小一档（提示框势力字号，如 22）
	# （角色表「势力」列，如「风之剑圣 威斯特姆 战技殿堂」）
	var 势力: String = Data.role_faction(角色号)
	if 势力 != "":
		var 势力号: int = maxi(1, int(round(float(提示框势力字号) * 字号缩放)))
		文本 += " [font_size=%d]%s[/font_size]" % [势力号, 势力]
	var 信息: String = Data.role_skill_info(角色号)
	if 角色号 == 108 and 信息 != "":
		信息 = 剑之子对局说明(信息, 对局中 and _剑之魔女在场())
	# 借用 / 视为自己拥有的独有技：统一按 GConst.角色借用独有技 追加到「独有技」分段
	# （剑之子 101/102 置灰、EX魔弓 301/302 正常显示；以后新角色只改那张表）
	if 信息 != "":
		信息 = 追加借用独有技(信息, 角色号)
	# 梦想剑按当前档位逐段标绿：第 1 次攻击后第一段、第 2 次后两段、第 4 次后三段。
	# 剑之魔女（45）与借到梦想剑的剑之子（108）都按各自快照里的 dream_tier 现算。
	if 对局中 and (角色号 == 45 or (角色号 == 108 and _剑之魔女在场())):
		var 档位: int = _梦想剑档位(角色号)
		if 档位 > 0:
			信息 = 梦想剑标绿(信息, 档位)
	if 信息 != "":
		# 角色名就压在最上面，第一个分段标题（普通技）上方也要留白，和后面几类一致
		文本 += "\n" + 上色(信息, 正文号, 标题号, true)
	var 标识物: String = 标识物一览(角色号)
	if 标识物 != "":
		# 右下角：先垫一行小字号空行再单独一段 + [right] 靠右。
		# 空行是因为这行字号小、又紧贴最后一句技能，不垫一下会被当成技能正文的最后一行；
		# 提示框的折行宽度就是内容宽度，所以右对齐的末段正好落在框的右下（内边距以内），
		# 不用另做一个角标节点
		var 标识物号: int = maxi(1, int(round(float(正文号) * 提示框标识物字号缩放)))
		# ∞ 按上面的增量单独放大；其余文字保持脚注字号
		标识物 = 标识物.replace("∞",
			"[font_size=%d]∞[/font_size]" % (标识物号 + 提示框无限字号增量))
		文本 += "\n[font_size=%d] [/font_size]\n[right][font_size=%d][color=#%s]%s[/color][/font_size][/right]" % [
			标题上方留白字号, 标识物号, 提示框标识物颜色.to_html(false), 标识物]
	return 文本


## 悬停提示的「分块」版本：技能表里「专属卡牌」非空的技能单独收进一块分组，
## 由提示框用和整框同色的边框画一个小框（标题＝那个字符串）。
## 返回空数组＝这个角色没有配专属卡牌，调用方走原来的整段文本（行为完全不变）。
## 每块：{"文本": 已上色的 BBCode} 或 {"分组": true, "标题": 专属卡牌名, "文本": BBCode}
static func 悬浮提示块(角色号: int, 字号缩放: float = 1.0, _对局中: bool = false) -> Array:
	var 正文号: int = maxi(1, int(round(float(提示框正文字号) * 字号缩放)))
	var 姓名号: int = maxi(1, int(round(float(提示框姓名行字号) * 字号缩放)))
	var 标题号: int = maxi(1, int(round(float(提示框标题字号) * 字号缩放)))
	var 条目: Array = Data.role_skill_条目(角色号)
	var 有分组: bool = false
	for 项: Variant in 条目:
		if not str((项 as Dictionary).get("专属卡牌", "")).is_empty():
			有分组 = true
			break
	if not 有分组:
		return []
	var 块: Array = []
	# 角色名 + 势力（与整段版同一套写法）
	var 角色名: String = Data.role_name(角色号)
	var 姓名: String = Data.role_personal_name(角色号)
	if 姓名 != "":
		角色名 = "%s %s" % [角色名, 姓名]
	var 名行: String = "[font_size=%d]%s[/font_size]" % [姓名号, 角色名]
	var 势力: String = Data.role_faction(角色号)
	if 势力 != "":
		var 势力号: int = maxi(1, int(round(float(提示框势力字号) * 字号缩放)))
		名行 += " [font_size=%d]%s[/font_size]" % [势力号, 势力]
	块.append({"文本": 名行})
	# 按大类分块：普通条目一块，每个「专属卡牌」各自一块（标题＝那个字符串）
	for 分段: String in Data.技能分段顺序:
		var 普通行: Array = []
		var 组序: Array = []
		var 组表: Dictionary = {}
		for 项2: Variant in 条目:
			var d: Dictionary = 项2
			if str(d.get("大类", "")) != 分段:
				continue
			var 专: String = str(d.get("专属卡牌", ""))
			if 专.is_empty():
				普通行.append(正文前缀 + str(d.get("文本", "")))
			else:
				if not 组表.has(专):
					组表[专] = []
					组序.append(专)
				(组表[专] as Array).append(正文前缀 + str(d.get("文本", "")))
		var 本段行: Array = [str(Data.技能分段标题.get(分段, 分段))]
		本段行.append_array(普通行)
		if 本段行.size() > 1 or not 组序.is_empty():
			块.append({"文本": 上色("\n".join(本段行), 正文号, 标题号, true)})
		for 专名: String in 组序:
			块.append({"分组": true, "标题": 专名,
				"文本": 上色("\n".join(组表[专名]), 正文号, 标题号)})
	# 右下角：专属标识物一览
	var 标识物: String = 标识物一览(角色号)
	if 标识物 != "":
		var 标识物号: int = maxi(1, int(round(float(正文号) * 提示框标识物字号缩放)))
		标识物 = 标识物.replace("∞", "[font_size=%d]∞[/font_size]" % (标识物号 + 提示框无限字号增量))
		块.append({"文本": "[right][font_size=%d][color=#%s]%s[/color][/font_size][/right]" % [
			标识物号, 提示框标识物颜色.to_html(false), 标识物]})
	return 块

## 剑之子（108）的角色说明动态部分：
##  - 剑之魔女在场时，【剑守誓言】10803 无法发动，整段划删除线；
##  - 【倾慕】10801 下面**始终**追加借用来的 4504 / 4503 说明：剑之魔女在场时正常显示，
##    不在场时整段划删除线（让玩家看到「本来会获得什么」）。
## 原文来自 Data.role_skill_info(108)，行首「　　」是正文前缀；返回仍用同一套行格式给 上色()。
static func 剑之子对局说明(原文: String, 有剑之魔女: bool) -> String:
	var 行列表: Array[String] = []
	for 行: String in 原文.split("\n"):
		行列表.append(行)
	# 先标记剑守誓言整段失效（避免后面按分段插入时下标变化）
	var 誓言起: int = -1
	for i: int in range(行列表.size()):
		if 行列表[i].lstrip("　 ").begins_with("【响应】剑守誓言"):
			誓言起 = i
			break
	if 有剑之魔女 and 誓言起 >= 0:
		var 誓言终: int = 誓言起
		while 誓言终 + 1 < 行列表.size() \
				and 行列表[誓言终 + 1].begins_with(正文前缀) \
				and not _是技能正文起(行列表[誓言终 + 1]):
			誓言终 += 1
		for i: int in range(誓言起, 誓言终 + 1):
			行列表[i] = _标记失效行(行列表[i])
	# 借用的 4503 / 4504 不放倾慕下面，而是按技能表「大类」追加到对应分段底部：
	# 4503 梦想剑 → 普通技；4504 剑影*断念 → 必杀技。
	for 技能号: int in [4503, 4504]:
		var 分段: String = Data.技能分段(技能号)
		if 分段 == "":
			continue
		var 标题: String = {"普通": "普通技", "必杀技": "必杀技"}.get(分段, 分段)
		_在分段底部插入(行列表, 标题, _构造借用技能行(技能号, 有剑之魔女))
	# 风之剑（10802）借用的剑圣独有技 101 / 102 由 追加借用独有技（GConst.角色借用独有技）
	# 统一追加，不在这里各写一遍；这里只返回剑之子自己的动态改动。
	return "\n".join(行列表)


## 把剑圣独有技插到「独有技」分段：已有该标题就追加在段底；
## 没有就新建在「普通技」之后、「必杀技」之前（技能分段顺序：普通→独有→专属→必杀）。
static func _插入独有技分段(行列表: Array[String], 插入: Array[String]) -> void:
	if 插入.is_empty():
		return
	for 行: String in 行列表:
		if 行.strip_edges() == "独有技":
			_在分段底部插入(行列表, "独有技", 插入)
			return
	var 普通起: int = -1
	for i: int in range(行列表.size()):
		if 行列表[i].strip_edges() == "普通技":
			普通起 = i
			break
	if 普通起 < 0:
		行列表.append("独有技")
		行列表.append_array(插入)
		return
	var 普通终: int = 普通起
	while 普通终 + 1 < 行列表.size() and 行列表[普通终 + 1].begins_with(正文前缀):
		普通终 += 1
	var 新行: Array[String] = []
	新行.append_array(行列表.slice(0, 普通终 + 1))
	新行.append("独有技")
	新行.append_array(插入)
	新行.append_array(行列表.slice(普通终 + 1))
	行列表.assign(新行)


## 把借用技能的正文行追加到某个大类分段的最后一条技能之后（下一个一级标题之前）。
static func _在分段底部插入(行列表: Array[String], 分段标题: String, 插入: Array[String]) -> void:
	if 插入.is_empty():
		return
	var 分段起: int = -1
	for i: int in range(行列表.size()):
		if 行列表[i].strip_edges() == 分段标题:
			分段起 = i
			break
	if 分段起 < 0:
		行列表.append_array(插入)
		return
	var 分段终: int = 分段起
	while 分段终 + 1 < 行列表.size() and 行列表[分段终 + 1].begins_with(正文前缀):
		分段终 += 1
	var 新行: Array[String] = []
	新行.append_array(行列表.slice(0, 分段终 + 1))
	新行.append_array(插入)
	新行.append_array(行列表.slice(分段终 + 1))
	行列表.assign(新行)


## 生成一颗借用技能的正文行；正常显示＝false 时逐行打上失效（置灰）标记。
## 角色号用于取「被该角色改写后的说明 / 改名」（GConst.技能说明覆盖 / 技能名覆盖；省略＝按技能表原样）。
static func _构造借用技能行(技能号: int, 正常显示: bool, 角色号: int = -1) -> Array[String]:
	var 行列表: Array[String] = []
	var 说明: String = GConst.技能说明覆盖(角色号, 技能号)
	if 说明 == "":
		说明 = GConst.skill_desc(技能号)
	if 说明 == "":
		return 行列表
	# 技能名按角色改名（如【雷击*见习制片】），没改名就是技能表默认名
	var 条目: String = GConst.词缀文本("【%s】%s：%s" % [
		GConst.skill_type(技能号), GConst.技能名显示(角色号, 技能号), 说明])
	for 子行: String in 条目.replace("\\n", "\n").split("\n"):
		var 文本: String = 子行.strip_edges()
		if 文本 == "":
			continue
		var 行: String = "　　" + 文本
		if not 正常显示:
			行 = _标记失效行(行)
		行列表.append(行)
	return 行列表


## 借用 / 视为自己拥有的独有技：按 GConst.角色借用独有技 把说明追加到「独有技」分段。
## 「说明置灰」＝false 时正常显示（视作自己的独有技），true 时整段置灰（继承来的、自身不拥有）。
## 卡面标绿（CardUI.显示技能）与测试指令 2（BattleEngine.debug_key）读的是同一张表。
static func 追加借用独有技(原文: String, 角色号: int) -> String:
	var 技能表: Array[int] = GConst.借用独有技(角色号)
	if 技能表.is_empty():
		return 原文
	var 行列表: Array[String] = []
	for 行: String in 原文.split("\n"):
		行列表.append(行)
	var 正常显示: bool = not GConst.借用独有技置灰(角色号)
	var 独有行: Array[String] = []
	for 技能号: int in 技能表:
		# 被该角色改写的技能（如 97 的 9703 改血腥咆哮、93 的 9304 改雷击）：
		# 说明取改写版，技能名取改名后的【血腥咆哮*萝莉番长】/【雷击*见习制片】，不再另列原版。
		独有行.append_array(_构造借用技能行(技能号, 正常显示, 角色号))
	_插入独有技分段(行列表, 独有行)
	return "\n".join(行列表)


## 这一行是不是「一条新技能」的正文首行（而不是上一条技能的续行 / 分段标题）。
## 所有正文行都以「　　」开头，只能靠缩进后的【类型】区分。
static func _是技能正文起(行: String) -> bool:
	return 行.begins_with(正文前缀) and 行.lstrip("　 ").begins_with("【")


## 标记一行角色技能正文失效：行首的【类型】保留原色，正文行首插零宽标记；
## 续行没有类型前缀，标记插在缩进后。只用于置灰，不画删除线。
static func _标记失效行(行: String) -> String:
	var 缩进长: int = 行.length() - 行.lstrip("　 ").length()
	var 缩进: String = 行.substr(0, 缩进长)
	var 正文: String = 行.substr(缩进长)
	var 右括号: int = 正文.find("】")
	if 正文.begins_with("【") and 右括号 >= 0:
		return 缩进 + 正文.substr(0, 右括号 + 1) + 失效行标记 + 正文.substr(右括号 + 1)
	return 缩进 + 失效行标记 + 正文


## 梦想剑 4503 技能说明标绿：只标「技能名 + 说明」，行首【被动】保留原类型色。
## 绿值与卡面「独有技」技能名同色（A9FF00）。启用中技能在多行时也只处理首行。
static func 梦想剑标绿(原文: String, 档位: int) -> String:
	if 档位 <= 0:
		return 原文
	var 短语表: Array[String] = [
		"回合内你的主动攻击无视【圣盾】",
		"回合内你的主动攻击对方无法应战",
		"回合内你的主动攻击强制命中",
	]
	var 行列表: Array[String] = []
	for 行: String in 原文.split("\n"):
		if 行.lstrip("　 ").begins_with("【被动】梦想剑"):
			for i: int in range(mini(档位, 短语表.size())):
				var 短语: String = 短语表[i]
				var 位置: int = 行.find(短语)
				if 位置 >= 0:
					行 = 行.substr(0, 位置) + "[color=#%s]%s[/color]" % [
						梦想剑启用色, 短语] + 行.substr(位置 + 短语.length())
		行列表.append(行)
	return "\n".join(行列表)


## 客户端快照里该角色的梦想剑档位（45 / 108 各一份）；没有该角色或未推进返回 0。
static func _梦想剑档位(角色号: int) -> int:
	var 最高: int = 0
	for 玩家: GPlayer in Data.player_list:
		if 玩家 != null and 玩家.role_id == 角色号:
			最高 = maxi(最高, int(玩家.dream_tier))
	return 最高


## 场上是否有剑之魔女（45）；选角/非对局由调用方传 对局中=false，不会读旧快照。
static func _剑之魔女在场() -> bool:
	for 玩家: GPlayer in Data.player_list:
		if 玩家 != null and 玩家.role_id == 45:
			return true
	return false


## 角色星数文本（提示框右上角）：整数显示 `★3`，半星显示 `★3.5`；没有星数返回空串。
## 项目字体没有 ⭐（U+2B50）的字形，用同形的 ★（U+2605）。
static func 星数文本(角色号: int) -> String:
	var 星: float = Data.role_star(角色号)
	if 星 <= 0.0:
		return ""
	var 整: float = roundf(星)
	if is_equal_approx(星, 整):
		return "★%d" % int(整)
	return "★%.1f" % 星


## 某个角色的专属标识物一览（纯文本）：`专属标识物【黄魂】上限为6，【蓝魂】上限为6`。
## 上限 99 在角色表里表示「没有上限」，显示成无限符号 ∞（和指示物悬浮提示同一套写法）。
## 没有标识物返回空串。
## 槽 0 / 1 / 2 都算：三枚在头像上都有图标（槽 2 是盖牌区，图标提示里叫「XX盖牌」，
## 这里仍按角色表记的名字写 —— 一行里混两种叫法反而乱）
static func 标识物一览(角色号: int) -> String:
	var 条目: Array[String] = []
	for 槽: int in [0, 1, 2]:
		var 定义: Dictionary = Data.role_token_def(角色号, 槽)
		var 名: String = str(定义.get("name", "")).strip_edges()
		if 名 == "":
			continue
		var 上限: int = int(定义.get("max", 0))
		条目.append("【%s】上限为%s" % [名, "∞" if 上限 == 99 else str(上限)])
	if 条目.is_empty():
		return ""
	return "专属标识物" + "，".join(条目)


## 单个技能的说明文本（技能按钮的悬停提示用）：一行「【类型】技能名：说明」，【类型】按类型上色。
## 查不到该技能或没写说明就返回空串（调用方据此不弹提示）。
## 单颗技能的说明（悬停技能按钮 / 技能按钮自带说明用）。
## 角色号省略时按「当前玩家自己的角色」取 —— 有角色改写了别人技能（GConst.角色技能说明覆盖）时用它，
## 例：萝莉番长 9703 覆盖【血腥咆哮】的说明。
static func 单个技能(技能号: int, 正文字号: int = 0, 角色号: int = -1) -> String:
	if 角色号 < 0:
		角色号 = 当前角色号()
	var 覆盖: String = GConst.技能说明覆盖(角色号, 技能号)
	var 说明: String = 还原换行(覆盖 if 覆盖 != "" else GConst.skill_desc(技能号))
	if 说明 == "":
		return ""
	var 行: String = "【%s】%s：%s" % [
		GConst.skill_type(技能号), GConst.技能名显示(角色号, 技能号), 说明]
	# 先上色（_染类型 靠行首的「【类型】」识别），再套字号；
	# 反过来的话行首变成 [font_size=…]，类型就永远匹配不到、不会标色
	行 = _染类型(行)
	if 正文字号 > 0:
		行 = "[font_size=%d]%s[/font_size]" % [正文字号, 行]
	return 行


## 当前玩家自己的角色号（不在对局 / 没选角时 0＝没有覆盖）
static func 当前角色号() -> int:
	if Logic == null or Logic.my_player_id < 0:
		return 0
	var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
	return 我.role_id if 我 != null else 0


## 给一段拼好的技能说明上色并排版：
##  - 一级标题按 正文字号 的 1.5 倍放大；
##  - 正文整行用 [indent] 缩进（用 [indent] 而非前缀空格，自动换行的续行也跟着缩进，不再和标题同列）；
##  - 行首的【类型】套 BBCode 颜色。
## 普通的行间距不靠插空行：改由 RichTextLabel 的 paragraph_separation 主题常量统一给
## （见 说明提示框._ready，tip_box.gd）——空行会占掉一整行高，反而没法把间距压小。
## 唯一的例外是分段标题上方的留白：那处普通行距撑不开，见 标题上方留白字号。
## 正文字号 0＝除上色外不做排版；
## 标题字号 >0 时用它替代默认的「正文字号 × 1.5」来放大一级标题；
## 首标题上方留白：第一个分段标题上方本来还有内容（悬停提示里的角色名）时传 true，
## 这样「普通技」上方也能和后面几类一样留白
static func 上色(技能文本: String, 正文字号: int = 0, 标题字号: int = 0, 首标题上方留白: bool = false) -> String:
	var 用标题字号: int = 标题字号 if 标题字号 > 0 else int(正文字号 * 1.5)
	var 行列表: Array[String] = []
	for 行文本: String in 技能文本.split("\n"):
		if 行文本.begins_with(正文前缀):
			# 正文：去掉「　　」前缀，改用 [indent] 整体缩进；正文字号 >0 时整行套 [font_size]
			# （先还原说明里写成「\n」的换行，再上色 —— 换行必须在「按前缀分类」之后做，
			#   否则说明内部的续行会掉进「一级标题」那一档被放大）
			var 正文: String = 还原换行(行文本.substr(正文前缀.length()))
			var 失效: bool = 正文.contains(失效行标记)
			var 染色: String = _染类型(正文, 失效)
			if 失效:
				# 保留【类型】原色但降透明度；技能名 / 说明用同样的半透明白压灰，
				# 不是换成纯灰 —— 类型色还认得出来，只是整体变淡。
				染色 = "[color=#FFFFFF8C]%s[/color]" % 染色
			var 正文行: String = "[indent]%s[/indent]" % 染色
			if 正文字号 > 0:
				正文行 = "[font_size=%d]%s[/font_size]" % [正文字号, 正文行]
			行列表.append(正文行)
		elif 用标题字号 > 0:
			# 一级标题（普通技 / 独有技 / 专属技 / 必杀技）：放大字号。
			# 上方还有内容（前面的技能正文，或悬停提示里的角色名）就先补一行小字号空行当留白
			if not 行列表.is_empty() or 首标题上方留白:
				行列表.append("[font_size=%d] [/font_size]" % 标题上方留白字号)
			行列表.append("[font_size=%d]%s[/font_size]" % [用标题字号, 行文本])
		else:
			行列表.append(_染类型(行文本))
	return "\n".join(行列表)


## 技能表里的说明把换行写成「\n」（反斜杠 + n，Excel 单元格里存不了真换行）。
## RichTextLabel 不认这个转义，会原样把「\n」两个字画出来 —— 显示前统一换成真换行，
## 于是悬停提示（富文本）里就能正常断行。注意只在「按前缀分好类」之后做：
## 说明内部的续行没有正文前缀，提前换行会被当成一级标题放大
static func 还原换行(文: String) -> String:
	return 文.replace("\\n", "\n")


## 行首（可带缩进）是「【类型】」时给这截连同方括号一起上色（BBCode）；别的行原样返回。
## 失效=true 时类型色保留色相、只降透明度（配合外层半透明白，整条技能置灰）。
static func _染类型(行文本: String, 失效: bool = false) -> String:
	var 缩进: String = 行文本.substr(0, 行文本.length() - 行文本.lstrip("　 ").length())
	var 正文: String = 行文本.substr(缩进.length())
	for 类型: String in GConst.技能类型颜色:
		var 前缀: String = "【%s】" % 类型
		if 正文.begins_with(前缀):
			var 色: Color = GConst.技能类型颜色[类型]
			if 失效:
				色 = Color(色.r, 色.g, 色.b, 0.55)
			return "%s[color=#%s]%s[/color]%s" % [
				缩进, 色.to_html(失效), 前缀, 正文.substr(前缀.length())]
	return 行文本
