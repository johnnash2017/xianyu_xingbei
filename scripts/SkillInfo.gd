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
