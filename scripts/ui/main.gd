extends Control
## 主场景（project.godot 的 run/main_scene）
## 整个游戏只有这一处画背景；登录/大厅/战斗/选将这些界面都由 UI 管理器（autoload 名 UI）
## 挂到「界面层」上，一层层叠在这张背景之上。

@export var 界面层: Control


func _ready() -> void:
	UI.attach(界面层)
	UI.goto_enter()
