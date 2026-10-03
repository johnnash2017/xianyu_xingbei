## 日志行数裁剪 —— 对应 AutoClearLog（Assembly-CSharp 根命名空间）
## 挂载点：BattleUIMobile.tscn 里 [node name="Content_2"]、[node name="Content_3"] 等日志节点。
## 端口里把这些节点从 Label 换成了 RichTextLabel：日志要按行上色，只有 RichTextLabel 支持 BBCode。
extends RichTextLabel

## 对应 C# private List<string> ContentLines = new List<string>();
var ContentLines: Array = []
## 对应 C# private float CurrentLogPos;
var CurrentLogPos: float = 0.0


func _ready() -> void:
	# 用 BBCode 给每行上色；高度按内容撑开，滚动交给外面的 ScrollContainer
	bbcode_enabled = true
	fit_content = true
	scroll_active = false

## 对应 C# public void AutoClearText(string content, int maxLineCount)
func AutoClearText(content: String, maxLineCount: int) -> void:
	# 对应 C# content.Split(new string[1] { Environment.NewLine }, StringSplitOptions.None)
	var array := content.replace("\r\n", "\n").split("\n")
	var num := array.size()
	var out_text := content
	if num > maxLineCount:
		out_text = ""
		for i in range(num):
			if array[i].begins_with("</color>"):
				# 对应 C# array[i - 1] += "</color>"; array[i] = array[i].Remove(0, 8);
				# 原 C# 在 i == 0 时会访问 array[-1] 抛异常，这里做了保护。
				if i > 0:
					array[i - 1] = array[i - 1] + "</color>"
					array[i] = array[i].substr(8)
		# 对应 C# for (int j = num - maxLineCount; j < num; j++) text += array[j] + Environment.NewLine;
		for j in range(num - maxLineCount, num):
			out_text = out_text + array[j] + "\n"
	# 对应 C# GetComponent<Text>().text = text;
	self.text = out_text
	# 场景里这个 Label 的高度是 0（只写了 anchor_bottom=1、offset 全是 0），父节点又是
	# clip_contents 的 ScrollContainer —— 不按内容撑高的话日志文字被整个裁掉，点开日志面板
	# 一片空白（battle_audit A-6）。这里按文本自身的最小高度把 custom_minimum_size 撑起来。
	var need_h := get_minimum_size().y
	if need_h > custom_minimum_size.y:
		custom_minimum_size = Vector2(custom_minimum_size.x, need_h)

## 对应 C# private void UpdateContentLines(string[] fixedDatas)
func UpdateContentLines(fixedDatas: Array) -> void:
	for item in fixedDatas:
		var s := str(item)
		# 对应 C# if (!ContentLines.Contains(item)) ContentLines.Add(item);
		if not ContentLines.has(s):
			ContentLines.append(s)
