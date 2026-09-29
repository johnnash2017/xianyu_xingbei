## 技能按钮 —— 由参考工程的 AGrail.SkillUI 解耦而来。
##
## 现在只做两件事：显示一个技能名、被点击时发 `点击(技能号)`。
## 数据由容器塞进来（scripts/ui/battle_mobile.gd），不再引用参考工程的
## BattleData / RoleFactory / MessageSystem。
##
## 根节点就是那个按钮（Skill.tscn 的根是 Button），故直接 extends Button；
## 其余节点引用 @export，在 res://scenes/prefabs/battlemobile/Skill.tscn 里绑定。
extends Button

## 技能按钮被点击 —— 容器据此进入「发动技能」或提交技能询问
signal 点击(技能号: int)

## 对应 Skill.tscn 里的 SkillName（技能名文字）
@export var skillName: Label
## 对应 Skill.tscn 里的 SelectBorder（选中高亮框）
@export var selectBorder: TextureRect

## 这个按钮代表的技能号
var 技能号: int = 0


func _ready() -> void:
	pressed.connect(_on_pressed)
	if selectBorder != null:
		selectBorder.visible = false


## 设置这个按钮显示哪个技能
func 设置技能(id: int, 名: String) -> void:
	技能号 = id
	if skillName != null:
		skillName.text = 名
	if selectBorder != null:
		selectBorder.visible = false


## 是否处于「已选中」
func 设置选中(值: bool) -> void:
	if selectBorder != null:
		selectBorder.visible = 值


func _on_pressed() -> void:
	点击.emit(技能号)
