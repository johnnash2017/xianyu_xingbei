## 聊天条目 —— 对应 AGrail.ChatItem
## 转换后的 scenes/prefabs/battlemobile/ChatItem.tscn 根节点类型是 HBoxContainer，
## 因此这里 extends HBoxContainer（Editor 里挂脚本不会类型不匹配）。
extends HBoxContainer

## Msg 是全局 class_name（见 scripts/framework/Msg.gd），直接用即可。
## 这里原来写了一份 `const Msg := preload(...)`，与全局类重名 —— Godot 会报
## SHADOWED_GLOBAL_IDENTIFIER，所以删掉（Msg.T.Xxx 的写法不受影响）。

## 对应 C# [SerializeField] private Image role;  （场景里的 Icon）
@onready var role: TextureRect = _find_node("Icon")
## 对应 C# [SerializeField] private Text msg;  （场景里的 ChatBG/Text）
@onready var msg: Label = _find_node("Text")

func _find_node(nm: String) -> Node:
	var n := find_child(nm, true, false)
	if n == null:
		push_warning("%s: 找不到节点 %s" % [name, nm])
	return n

## 对应 AssetBundleManager.LoadAsset<Sprite>("hero_s", value + "S")
## Godot 侧由 AssetIndex 按文件名索引 assets/ 下的图片（对应 C# 的 AssetBundle 取图）
func _load_hero_sprite(sprite_name: String) -> Texture2D:
	var path := AssetIndex.image(sprite_name)
	if path == "":
		return null
	return load(path)

## 对应 C# public uint? RoleID 的 setter
func set_RoleID(value: Variant) -> void:
	if value == null:
		return
	var sprite := _load_hero_sprite("%sS" % str(value))
	if sprite != null and role != null:
		role.texture = sprite

## 对应 C# public string Msg 的 setter
func set_Msg(value: String) -> void:
	if msg != null:
		msg.text = value

## 对应 C# public bool IsMainPlayer 的 setter
## Unity 的 transform.SetAsLastSibling() -> Godot 的 move_child
func set_IsMainPlayer(value: bool) -> void:
	if not value and role != null:
		move_child(role, get_child_count() - 1)
