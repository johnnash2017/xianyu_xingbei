## 角色技能说明文本的组装与排版（上色 + 悬停提示）。
## 原先这里是个「英雄详情窗」（搬自参考工程 InfomationUI）：战斗内点头像弹它；
## 现在战斗内也改成和选角界面一样「鼠标指向头像就地弹提示」，那个窗不再需要，
## 只留下这组静态函数 —— 谁要显示角色技能说明都调 悬浮提示()。
class_name 角色技能提示
extends RefCounted

## 技能文本里正文行的前缀（data_interface._拼技能文本 给每条技能正文加的「　　」）；
## 拿它区分「四个一级标题」（无前缀）与「技能正文」（有前缀）
const 正文前缀: String = "　　"
## 悬停提示里技能正文的字号
const 提示框正文字号: int = 18
## 悬停提示里角色名的字号（原 72 的一半）
const 提示框姓名行字号: int = 36
## 悬停提示里「普通技 / 独有技 / 专属技 / 必杀技」这些分段标题的字号（原 54 的一半）
const 提示框标题字号: int = 27
## 分段标题上方的留白：用一行「小字号空行」撑出来（字号越小留白越少）。
## 标题字号比正文大，行盒自带一点余量，但它和上面那段技能之间的间距还是比正文行之间更挤，
## 这里补一行，让每类标题和上一坨技能之间有和其他间距一样的呼吸。
const 标题上方留白字号: int = 8


## 悬停提示的完整文本：角色名一行 + 技能说明（上色排版），含 BBCode。
## 战斗外选角卡与战斗内玩家头像的悬浮说明都用它 —— 组装规则只有这一份。
## 字号缩放：调用方想让整块文字等比小一点时传（战斗内的框要压一档），1.0＝原样
static func 悬浮提示(角色号: int, 字号缩放: float = 1.0) -> String:
	var 正文号: int = maxi(1, int(round(float(提示框正文字号) * 字号缩放)))
	var 姓名号: int = maxi(1, int(round(float(提示框姓名行字号) * 字号缩放)))
	var 标题号: int = maxi(1, int(round(float(提示框标题字号) * 字号缩放)))
	var 文本: String = "[font_size=%d]%s[/font_size]" % [姓名号, Data.role_name(角色号)]
	var 信息: String = Data.role_skill_info(角色号)
	if 信息 != "":
		# 角色名就压在最上面，第一个分段标题（普通技）上方也要留白，和后面几类一致
		文本 += "\n" + 上色(信息, 正文号, 标题号, true)
	return 文本


## 单个技能的说明文本（技能按钮的悬停提示用）：一行「【类型】技能名：说明」，【类型】按类型上色。
## 查不到该技能或没写说明就返回空串（调用方据此不弹提示）。
static func 单个技能(技能号: int, 正文字号: int = 0) -> String:
	var 说明: String = 还原换行(GConst.skill_desc(技能号))
	if 说明 == "":
		return ""
	var 行: String = "【%s】%s：%s" % [GConst.skill_type(技能号), GConst.skill_name(技能号), 说明]
	if 正文字号 > 0:
		行 = "[font_size=%d]%s[/font_size]" % [正文字号, 行]
	return _染类型(行)


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
			var 正文行: String = "[indent]%s[/indent]" % _染类型(还原换行(行文本.substr(正文前缀.length())))
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


## 行首（可带缩进）是「【类型】」时给这截连同方括号一起上色（BBCode）；别的行原样返回
static func _染类型(行文本: String) -> String:
	var 缩进: String = 行文本.substr(0, 行文本.length() - 行文本.lstrip("　 ").length())
	var 正文: String = 行文本.substr(缩进.length())
	for 类型: String in GConst.技能类型颜色:
		var 前缀: String = "【%s】" % 类型
		if 正文.begins_with(前缀):
			return "%s[color=#%s]%s[/color]%s" % [
				缩进, (GConst.技能类型颜色[类型] as Color).to_html(false), 前缀, 正文.substr(前缀.length())]
	return 行文本
