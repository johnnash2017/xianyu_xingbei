## 技能详情面板 —— 对应 AGrail.SkillInfo
## 转换后的 scenes/prefabs/battlemobile/SKillInfo.tscn 根节点类型是 VBoxContainer，
## 因此这里 extends VBoxContainer。
extends VBoxContainer

## 对应 C# [SerializeField] private Text skillName;
@onready var skillName: Label = _find_node("SkillName") as Label
## 对应 C# [SerializeField] private Text skillTag;
@onready var skillTag: Label = _find_node("skilltag") as Label
## 对应 C# [SerializeField] private Text skillDescription;
@onready var skillDescription: Label = _find_node("SkillContent") as Label
## 对应 C# [SerializeField] public Image skillImage;
@onready var skillImage: TextureRect = _find_node("SkillImage") as TextureRect

func _find_node(nm: String) -> Node:
	var n := find_child(nm, true, false)
	if n == null:
		push_warning("%s: 找不到节点 %s" % [name, nm])
	return n

func _ready() -> void:
	# Unity 的 Text 支持富文本；Godot 的 Label 不支持，只有 RichTextLabel 才有 bbcode_enabled。
	# 这里按实际节点类型启用，避免对 Label 赋值 bbcode_enabled 报错。
	for lbl in [skillTag, skillDescription, skillName]:
		if lbl is RichTextLabel:
			(lbl as RichTextLabel).bbcode_enabled = true
	if skillDescription != null:
		# 对应 C# skillDescription.alignment = TextAnchor.MiddleLeft;
		skillDescription.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		skillDescription.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

## 对应 C# public Mation Mation { get; set; }
## 注意：这里必须是一个**属性**。外部是按 C# 的写法 `go.set("Mation", m)` 赋值的，
## 而 Object.set() 只认属性表里的名字；只写一个 set_Mation() 方法的话它会静默失败，
## 于是详情窗里每条技能都停在预制体的空模板上（只有「技能标签/技能描述」这种占位文字）。
var Mation: Mation = null:
	set(value):
		_apply_mation(value)

## 对应 C# public Mation Mation 的 setter（C# 风格调用入口，等价于上面的属性赋值）
func set_Mation(value: Mation) -> void:
	_apply_mation(value)

func _apply_mation(value: Mation) -> void:
	if value == null:
		return
	if skillTag != null:
		# 对应 C# skillTag.text.Replace("【", "") / Replace("】", "\u3000")
		var tag := value.MationTag.replace("【", "")
		tag = tag.replace("】", "\u3000")
		skillTag.text = tag
	if skillDescription != null:
		# 对应 C# skillDescription.text.Replace("\\n", "\n")
		skillDescription.text = value.MationDesc.replace("\\n", "\n")
	if skillName != null:
		skillName.text = value.MationName
