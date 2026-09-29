extends Control
## 选将界面（弹层）
## 由 Logic 收到服务端 RoleReq 后实例化并叠在当前界面之上，处理三选一/任意选与 Ban-Pick（含 CM）。
## 不使用 UI.goto 整屏切换；角色立绘、Ban/Pick 标记与按钮贴图统一通过 Art 接口取用。
## 遮罩/面板/标题/网格/按钮等结构都在 role_pick.tscn 里（可所见即所得地改），
## 本脚本只负责「每个角色一个按钮」这类动态内容。

## 角色卡片网格参数（设计基准 1920x1080；网格列数等版面参数在场景里设）
const ROLE_BTN_W: float = 192.0
const ROLE_BTN_H: float = 243.0
## 角色立绘尺寸（与 资源/角色 原图一致：42x120）及卡片内的排布
const ROLE_CARD_W: float = 67.0
const ROLE_CARD_H: float = 192.0
const ROLE_CARD_TOP: float = 6.0
const ROLE_NAME_H: float = 42.0

## 角色在本次选将中的标记（决定叠加的 Ban/Pick 图标与是否还能选）
enum RoleMark {
	None = 0,      # 可选
	Ban = 1,       # 已被禁用
	ExtraBan = 2,  # CM 额外禁用
	Pick = 3,      # 已被选择
}

# ---- 当前 RoleReq 数据 ----
var _strategy: int = 0
var _operation: int = 0
var _ask_id: int = -1
var _role_ids: Array[int] = []
var _args: Array[int] = []
## 是否轮到自己操作（决定按钮是否可点）
var _interactive: bool = false

# ---- 场景里绑定的界面节点（结构在 role_pick.tscn 里，可所见即所得地改） ----
@export var 标题: Label
@export var 提示: Label
@export var 网格: GridContainer
@export var 确定按钮: Button
@export var 取消按钮: Button

## 角色按钮的互斥组（每次刷新重建）
var _group: ButtonGroup


func _ready() -> void:
	确定按钮.pressed.connect(_on_ok_pressed)
	取消按钮.pressed.connect(_on_cancel_pressed)
	# 选将结束后（对局开始）自动关闭
	Logic.game_info_updated.connect(_on_game_info)


# ============================================================
# 对外接口
# ============================================================
## 应用（或更新）一条 RoleReq 数据；重复收到时复用本实例刷新内容，避免叠层
func apply_request(data: Dictionary) -> void:
	_strategy = int(data.get("strategy", 0))
	_operation = int(data.get("opration", 0))
	_ask_id = int(data.get("id", -1))
	_role_ids.clear()
	var raw_roles: Array = data.get("role_ids", [])
	for rid: int in raw_roles:
		_role_ids.append(rid)
	_args.clear()
	var raw_args: Array = data.get("args", [])
	for v: int in raw_args:
		_args.append(v)
	_interactive = _ask_id == Logic.my_player_id and _can_choose()
	# 只有轮到自己操作时才提示，避免全量广播快照反复响（对照参考项目 ChooseRole → sys-turn）
	if _interactive:
		Audio.播音效("sys-turn")
	_refresh()


# ============================================================
# 刷新内容
# ============================================================
func _refresh() -> void:
	标题.text = _mode_title()
	提示.text = _status_text()
	确定按钮.visible = _interactive
	确定按钮.disabled = true
	取消按钮.visible = _interactive and _is_extra_ban()

	for c: Node in 网格.get_children():
		网格.remove_child(c)
		c.queue_free()
	# 每次刷新都重建按钮组，清掉上一次的选择
	_group = ButtonGroup.new()
	for i: int in range(_role_ids.size()):
		var rid: int = _role_ids[i]
		var step: int = _args[i] if i < _args.size() else 0
		网格.add_child(_build_role_button(rid, _role_mark(step), _role_team(step)))


## 一个角色卡片：立绘 + 角色名 + Ban/Pick 叠加标记
func _build_role_button(rid: int, mark: int, team: int) -> Button:
	var btn: Button = Button.new()
	btn.toggle_mode = true
	btn.button_group = _group
	btn.custom_minimum_size = Vector2(ROLE_BTN_W, ROLE_BTN_H)
	btn.set_meta("role_id", rid)
	btn.pressed.connect(_on_role_pressed)

	var state_text: String = _role_state_text(mark)
	var tip_text: String = Data.role_name(rid)
	if state_text != "":
		tip_text += "（%s）" % state_text
	var info: String = Data.role_skill_info(rid)
	if info != "":
		tip_text += "\n" + info
	btn.tooltip_text = tip_text

	var face_pos: Vector2 = Vector2((ROLE_BTN_W - ROLE_CARD_W) * 0.5, ROLE_CARD_TOP)
	var face_size: Vector2 = Vector2(ROLE_CARD_W, ROLE_CARD_H)
	var face_tex: Texture2D = Art.role_avatar(rid)
	if face_tex != null:
		var face: TextureRect = TextureRect.new()
		face.texture = face_tex
		face.position = face_pos
		face.size = face_size
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(face)
	else:
		# 立绘缺失（尚无素材的角色）：用深色占位块，避免格子出现空洞
		var hole: ColorRect = ColorRect.new()
		hole.color = Color(0.18, 0.19, 0.24, 1.0)
		hole.position = face_pos
		hole.size = face_size
		hole.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(hole)

	var name_label: Label = Label.new()
	name_label.text = "%d.%s" % [rid, Data.role_name(rid)]
	name_label.position = Vector2(0.0, ROLE_CARD_TOP + ROLE_CARD_H)
	name_label.size = Vector2(ROLE_BTN_W, ROLE_NAME_H)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 19)
	if _is_ban_mark(mark):
		name_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.55))
	elif mark == RoleMark.Pick:
		name_label.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(name_label)

	# 已被禁/选的角色不可再选
	btn.disabled = (mark != RoleMark.None) or (not _interactive)
	if mark != RoleMark.None:
		_add_mark_overlay(btn, face_pos, face_size, mark, team, rid)
	return btn


## 在立绘上叠加标记；找不到对应素材时退化为半透明遮罩 + 文字
func _add_mark_overlay(btn: Button, face_pos: Vector2, face_size: Vector2, mark: int, team: int, rid: int) -> void:
	var icon: Texture2D = _mark_icon(mark, team, rid)
	if icon != null:
		var mark_rect: TextureRect = TextureRect.new()
		mark_rect.texture = icon
		mark_rect.position = face_pos
		mark_rect.size = face_size
		mark_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mark_rect.stretch_mode = TextureRect.STRETCH_SCALE
		mark_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(mark_rect)
		return
	var mask: ColorRect = ColorRect.new()
	mask.color = _mark_mask_color(mark)
	mask.position = face_pos
	mask.size = face_size
	mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(mask)
	var text_label: Label = Label.new()
	text_label.text = _role_state_text(mark)
	text_label.position = face_pos
	text_label.size = face_size
	text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.add_theme_font_size_override("font_size", 19)
	text_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	text_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	text_label.add_theme_constant_override("outline_size", 5)
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(text_label)


## 标记对应的叠加图标（缺图返回 null，由调用方退化处理）
func _mark_icon(mark: int, team: int, rid: int) -> Texture2D:
	match mark:
		RoleMark.Ban:
			return Art.bp_icon("Ban%d" % rid)
		RoleMark.ExtraBan:
			return Art.bp_icon("GameInsertBan")
		RoleMark.Pick:
			if team == GConst.RED:
				return Art.bp_icon("GamePickRed")
			if team == GConst.BLUE:
				return Art.bp_icon("GamePickBlue")
			return null
	return null


## 无图标时遮罩颜色：禁用类为红、选择为绿
func _mark_mask_color(mark: int) -> Color:
	if mark == RoleMark.Pick:
		return Color(0.25, 0.85, 0.4, 0.55)
	return Color(0.9, 0.2, 0.2, 0.55)


func _is_ban_mark(mark: int) -> bool:
	return mark == RoleMark.Ban or mark == RoleMark.ExtraBan


func _mode_title() -> String:
	if _strategy == GConst.RoleStrategy.Strategy31 or _strategy == GConst.RoleStrategy.Any:
		return "请选择角色" if _interactive else "选将"
	if _strategy == GConst.RoleStrategy.BP:
		if _operation == GConst.BpOperation.Ban:
			return "请禁用一角色"
		if _operation == GConst.BpOperation.Pick:
			return "请选择一角色"
		return "Ban-Pick 选将"
	if _strategy == GConst.RoleStrategy.CM:
		if _operation == GConst.CmOperation.RedBan or _operation == GConst.CmOperation.BlueBan:
			return "请禁用一角色"
		if _operation == GConst.CmOperation.RedPick or _operation == GConst.CmOperation.BluePick:
			return "请选择一角色"
		if _is_extra_ban():
			return "请额外禁用角色，或点「取消」"
		return "选将（CM）"
	return "选将"


func _status_text() -> String:
	if _interactive:
		return "选中一个角色后点「确定」"
	if _ask_id == Logic.my_player_id:
		return "等待其他玩家选择角色…"
	return "等待玩家 %s 选择角色…" % _ask_player_name()


## 只有被询问的玩家本人、且当前需要其操作时才能点击
func _can_choose() -> bool:
	if _strategy == GConst.RoleStrategy.Strategy31 or _strategy == GConst.RoleStrategy.Any:
		return true
	if _strategy == GConst.RoleStrategy.BP:
		return _operation == GConst.BpOperation.Ban or _operation == GConst.BpOperation.Pick
	if _strategy == GConst.RoleStrategy.CM:
		return _operation != GConst.CmOperation.Null
	return false


## CM 的「额外禁用」步骤允许点「取消」跳过
func _is_extra_ban() -> bool:
	if _strategy != GConst.RoleStrategy.CM:
		return false
	return _operation == GConst.CmOperation.RedInsertBan or _operation == GConst.CmOperation.BlueInsertBan


func _ask_player_name() -> String:
	var p: GPlayer = Data.get_player_by_id(_ask_id)
	if p != null and p.nickname != "":
		return p.nickname
	return "%d 号" % _ask_id


## 依据 args 中的步骤值判断角色在本次选将中的标记
func _role_mark(step: int) -> int:
	if step <= 0:
		return RoleMark.None
	if _strategy == GConst.RoleStrategy.BP:
		# 与服务端一致：每 4 步为一轮，前 2 步禁用、后 2 步选择
		return RoleMark.Ban if ((step - 1) % 4) < 2 else RoleMark.Pick
	# CM：args 即 CmOperation 值，>10 表示第十步之后发生的额外禁用
	var op: int = step - 10 if step > 10 else step
	if op == GConst.CmOperation.RedBan or op == GConst.CmOperation.BlueBan:
		return RoleMark.Ban
	if op == GConst.CmOperation.RedInsertBan or op == GConst.CmOperation.BlueInsertBan:
		return RoleMark.ExtraBan
	if op == GConst.CmOperation.RedPick or op == GConst.CmOperation.BluePick:
		return RoleMark.Pick
	# 步骤含义未知时统一按已禁用展示，保证该角色不可再被选走
	return RoleMark.Ban


## 标记的中文说明（用于 tooltip 与无图标时的遮罩文字）
func _role_state_text(mark: int) -> String:
	match mark:
		RoleMark.Ban:
			return "已禁"
		RoleMark.ExtraBan:
			return "已额外禁"
		RoleMark.Pick:
			return "已选"
	return ""


## 该角色被哪一队禁/选；判断不出返回 GConst.TEAM_NONE
func _role_team(step: int) -> int:
	if step <= 0:
		return GConst.TEAM_NONE
	if _strategy == GConst.RoleStrategy.BP:
		# 服务端：颜色 = 步 % 2，奇数步为红队行动、偶数步为蓝队行动
		return GConst.RED if step % 2 == 1 else GConst.BLUE
	var op: int = step - 10 if step > 10 else step
	if op == GConst.CmOperation.RedBan or op == GConst.CmOperation.RedInsertBan or op == GConst.CmOperation.RedPick:
		return GConst.RED
	if op == GConst.CmOperation.BlueBan or op == GConst.CmOperation.BlueInsertBan or op == GConst.CmOperation.BluePick:
		return GConst.BLUE
	return GConst.TEAM_NONE


# ============================================================
# 交互
# ============================================================
func _on_role_pressed() -> void:
	确定按钮.disabled = false


func _on_ok_pressed() -> void:
	var pressed_btn: BaseButton = _group.get_pressed_button()
	if pressed_btn == null:
		return
	Art.play_sfx("Equip")
	var rid: int = int(pressed_btn.get_meta("role_id"))
	if _strategy == GConst.RoleStrategy.BP:
		Logic.send_pick_ban(GConst.RoleStrategy.BP, _operation == GConst.BpOperation.Pick, [rid])
	elif _strategy == GConst.RoleStrategy.CM:
		var is_pick: bool = _operation == GConst.CmOperation.RedPick or _operation == GConst.CmOperation.BluePick
		Logic.send_pick_ban(GConst.RoleStrategy.CM, is_pick, [rid])
	else:
		Logic.send_pick_ban(_strategy, true, [rid])
	_set_submitted()


func _on_cancel_pressed() -> void:
	Art.play_sfx("Equip")
	# 取消额外禁用：上行哨兵角色 id
	Logic.send_pick_ban(GConst.RoleStrategy.CM, false, [GConst.CM_CANCEL_ROLE_ID])
	_set_submitted()


## 已提交：锁定界面，等待下一条 RoleReq 或对局开始
func _set_submitted() -> void:
	for c: Node in 网格.get_children():
		if c is Button:
			(c as Button).disabled = true
	确定按钮.disabled = true
	取消按钮.visible = false
	提示.text = "已提交，等待其他玩家…"


func _on_game_info(info: Dictionary) -> void:
	if bool(info.get("is_started", false)):
		if Logic.role_pick_layer == self:
			Logic.role_pick_layer = null
		queue_free()
