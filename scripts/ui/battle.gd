extends Control
## 战斗/房间界面（对照客户端 widget/RoomScene + PlayerArea + HandArea + ButtonArea + DecisionArea + TipArea）
## 同一场景承载两态：开局前（房间等待：选边/准备）与开局后（战斗）。
## 静态结构（提示条/手牌层/按钮区/日志/聊天/等待按钮行）都在 battle.tscn 里，
## 可在编辑器里所见即所得地改；本脚本只负责「每个玩家一块面板」「每张牌一个节点」这类动态内容。
## 背景由主场景 Main.tscn 统一提供，本界面不画背景。

## 设计基准 1920x1080（project.godot 的 viewport 尺寸）：所有数值都写在这个坐标系里；
## 其它窗口尺寸由引擎的 canvas_items 拉伸整体缩放，界面只需按设计尺寸排版即可。
const PANEL_W: int = 280
const PANEL_H: int = 186
const CARD_W: int = 154
const CARD_H: int = 210
const 底部行高: float = 48.0            # 底部按钮与聊天行的高度（动态技能按钮沿用）
## ---- 玩家面板内部尺寸 ----
const AVATAR_W: float = 60.0            # 立绘框宽
const AVATAR_H: float = 116.0           # 立绘框高
const STATUS_ICON_SIZE: float = 32.0    # 状态/独有效果图标
const TOKEN_ICON_SIZE: float = 22.0     # 指示物图标
const NAME_FONT: int = 18
const INFO_FONT: int = 16
const TINY_FONT: int = 14
const BUTTON_FONT: int = 22

# ---- 界面节点（结构在 battle.tscn 里，可在编辑器里所见即所得地改） ----
@export var _team_bar: Label
@export var _tip: Label
@export var _log: RichTextLabel
@export var _players_root: Control
@export var _hand_root: Control
@export var _cover_box: HBoxContainer
@export var _decision_box: HBoxContainer
@export var _action_box: VBoxContainer
@export var _waiting_box: HBoxContainer
@export var _ok_btn: Button
@export var _cancel_btn: Button
@export var _unaction_btn: Button
@export var _giveup_btn: Button
@export var _ready_btn: Button
@export var _buy_btn: Button
@export var _synth_btn: Button
@export var _extract_btn: Button
@export var _chat_edit: LineEdit
@export var _chat_btn: Button
@export var _red_btn: Button
@export var _blue_btn: Button
@export var _rand_btn: Button
@export var _leave_btn: Button

# ---- 交互状态 ----
var _panel_of: Dictionary = {}          # player_id -> Panel
## 等待进度条：player_id -> ProgressBar（画在该玩家面板底部）
var _等待条: Dictionary = {}
## 当前正在等谁回复、剩余秒数、本次等待总秒数（由 Game 消息刷新）
var _等待方: int = -1
var _等待剩余: float = 0.0
var _等待总时长: float = 0.0
## 座位椭圆的圆心与半径（由 _布局() 按实际视口算好，供 _refresh_players() 使用）
var _中心: Vector2 = Vector2.ZERO
var _半径x: float = 0.0
var _半径y: float = 0.0
var _sel_cards: Array[int] = []
var _sel_players: Array[int] = []
var _pending: Dictionary = {}           # 当前 CMD_REQ 的单条命令
var _pending_type: int = -1             # GConst.Msg.Action / Msg.Respond
var _mode: int = 0                      # 0 空闲 / 1 行动 / 2 响应 / 3 技能询问 / 4 发动技能
var _need_cards: int = 0
var _need_players: int = 0
var _cur_player_id: int = -1
## 技能相关
var _skill_ask_id: int = -1             # 正在询问是否发动的技能号
var _skill_ask_need_card: int = 0       # 该技能询问是否需要选牌
var _skill_ask_need_target: int = 0     # 该技能询问是否需要选目标
var _skill_ask_card_source: int = 0     # 该技能询问的选牌来源（GConst.CardSource）
var _selecting_cover: bool = false      # 该询问是否允许点选盖牌（盖牌区可点选）
var _skill_options: Array[int] = []     # 该技能询问的可选项值（非空时渲染选项按钮）
var _pending_skill_id: int = -1         # 已选定要发动的技能号
var _pending_skill_type: int = -1       # 技能对应的 action_type
var _skill_need_card: int = 0
var _skill_need_target: int = 0
var _skill_buttons: Array = []          # 行动阶段动态技能按钮
## 胜负音效是否已播放（Gossip 提示与 game_over 可能先后到达，只响一次）
var _result_sfx_done: bool = false
## 数值快照：用来判断士气/宝石水晶/治疗的变化并播对应音效
var _上次已开局: bool = false
var _上次士气: Array[int] = [0, 0]
var _上次宝石: Array[int] = [0, 0]
var _上次水晶: Array[int] = [0, 0]
var _上次治疗: int = 0
## 上次看到的房间人数：等待阶段有人加入就播加入房间音效
var _上次房间人数: int = -1


func _ready() -> void:
	UI.register(self)
	Logic.battle = self
	Logic.game_info_updated.connect(_on_game_info)
	Logic.command_received.connect(_on_command)
	Logic.turn_changed.connect(_on_turn)
	Logic.hit_received.connect(_on_hit)
	Logic.card_shown.connect(_on_card)
	Logic.hurt_received.connect(_on_hurt)
	Logic.gossip_received.connect(_on_gossip)
	Logic.notice_received.connect(_on_gossip)
	Logic.game_over.connect(_on_game_over)
	Logic.error_received.connect(func(_id: int, msg: String) -> void: _set_tip(msg))
	# 场景里各按钮接上自己的处理
	_buy_btn.pressed.connect(func() -> void: _act_special(GConst.SpecialAction.Buy, [1, 0]))
	_synth_btn.pressed.connect(func() -> void: _act_special(GConst.SpecialAction.Synthesize, [0, 3]))
	_extract_btn.pressed.connect(func() -> void: _act_special(GConst.SpecialAction.Extract, [1, 0]))
	_ok_btn.pressed.connect(_on_ok)
	_cancel_btn.pressed.connect(_on_cancel)
	_unaction_btn.pressed.connect(_on_unactional)
	_giveup_btn.pressed.connect(_on_giveup)
	_chat_btn.pressed.connect(_on_chat_send)
	_chat_edit.text_submitted.connect(func(_t: String) -> void: _on_chat_send())
	_red_btn.pressed.connect(func() -> void: Logic.join_team(2))
	_blue_btn.pressed.connect(func() -> void: Logic.join_team(1))
	_rand_btn.pressed.connect(func() -> void: Logic.join_team(3))
	_ready_btn.pressed.connect(_on_ready_toggle)
	_leave_btn.pressed.connect(_on_leave)
	if not Logic.last_info.is_empty():
		_on_game_info(Logic.last_info)
	resized.connect(_on_resized)


func _exit_tree() -> void:
	if Logic.battle == self:
		Logic.battle = null


## 视口尺寸变化（如多开时窗口被摆成不同长宽比）→ 重画
func _on_resized() -> void:
	_refresh_players()
	_refresh_hand()


## 座位椭圆：中心取「提示下沿 ~ 盖牌区上沿」的中点，半径按可用空间定。
## 顶部/底部各区域的位置尺寸都在 battle.tscn 里用锚点定，这里只按它们的实际位置推导椭圆
func _刷新座位椭圆() -> void:
	if size.x <= 1.0 or size.y <= 1.0:
		return
	var 上: float = _tip.position.y + _tip.size.y
	var 下: float = _cover_box.position.y
	_中心 = Vector2(size.x * 0.5, (上 + 下) * 0.5 + 20.0)
	_半径x = size.x * 0.40
	_半径y = (下 - 上) * 0.40


# ============================================================
# 刷新
# ============================================================
func _on_game_info(info: Dictionary) -> void:
	var started: bool = bool(info.get("is_started", false))
	# 房间等待阶段继续用主界面音乐，真正开打才换战斗音乐；开新一局时允许再播一次胜负音
	if started and not _上次已开局:
		_result_sfx_done = false
		Audio.播放音乐(Audio.场景战斗)
	# 等待阶段：人数增加（含自己刚进房的首条信息）就播加入房间音效
	if not started:
		var 人数: int = 0
		for p: GPlayer in Data.player_list:
			if p.id >= 0:
				人数 += 1
		if 人数 > _上次房间人数:
			Audio.播音效("sys-energy")
		_上次房间人数 = 人数
	_读取等待(info)
	_播音效_数值变化(info)
	_refresh_team_bar(info)
	_refresh_players()
	_refresh_hand()
	_waiting_box.visible = not started
	_action_box.visible = started
	_decision_box.visible = started
	if not started:
		_tip.text = "等待所有玩家准备…（红/蓝队可在下方选择）"
	else:
		_ready_btn.text = "准备"
	_上次已开局 = started


## 士气 / 宝石水晶 / 治疗 变化时播对应音效
## （对照参考项目 AudioManager 监听的 MoraleChange / GemChange / CrystalChange / PlayerHealChange）
func _播音效_数值变化(info: Dictionary) -> void:
	var 士气: Array[int] = [int(info.get("red_morale", 0)), int(info.get("blue_morale", 0))]
	var 宝石: Array[int] = [int(info.get("red_gem", 0)), int(info.get("blue_gem", 0))]
	var 水晶: Array[int] = [int(info.get("red_crystal", 0)), int(info.get("blue_crystal", 0))]
	var 治疗: int = 0
	for p: GPlayer in Data.player_list:
		治疗 += p.cross_num
	# 开局那一条只做记录：否则「士气 0 → 初始值」会白响一声
	if _上次已开局 and bool(info.get("is_started", false)):
		if 士气 != _上次士气:
			Audio.播音效("sys-morale")
		elif 宝石 != _上次宝石 or 水晶 != _上次水晶:
			Audio.播音效("sys-energy")
		if 治疗 != _上次治疗:
			Audio.播音效("sys-heal")
	_上次士气 = 士气
	_上次宝石 = 宝石
	_上次水晶 = 水晶
	_上次治疗 = 治疗


## 每帧推进等待进度条（服务端只在等待开始/结束时广播，剩余时间由客户端自己倒数）
func _process(delta: float) -> void:
	if _等待方 < 0:
		return
	if _等待剩余 > 0.0:
		_等待剩余 = maxf(_等待剩余 - delta, 0.0)
	_刷新等待条()


## 读取「正在等谁回复、还剩多久」
func _读取等待(info: Dictionary) -> void:
	_等待方 = int(info.get("wait_pid", -1))
	_等待总时长 = float(info.get("wait_total_ms", 0)) / 1000.0
	_等待剩余 = float(info.get("wait_ms", 0)) / 1000.0
	_刷新等待提示()


## 顶部提示：自己手上没有询问时，把「正在等谁」说清楚，别让人以为卡住了
func _刷新等待提示() -> void:
	if _mode != 0 or _等待方 < 0:
		return
	var p: GPlayer = Data.get_player_by_id(_等待方)
	var 名: String = ("%d号 %s" % [p.id, p.nickname]) if p != null else ("%d号" % _等待方)
	if _等待方 == Logic.my_player_id:
		_set_tip("正在等待你的操作…")
	else:
		_set_tip("正在等待 %s 操作…" % 名)


## 把等待进度条更新到对应玩家的面板底部（其余玩家隐藏）
func _刷新等待条() -> void:
	for pid: int in _等待条.keys():
		var 条: ProgressBar = _等待条[pid]
		if not is_instance_valid(条):
			continue
		if pid != _等待方 or _等待总时长 <= 0.0:
			条.visible = false
		else:
			条.visible = true
			条.value = clampf(_等待剩余 / _等待总时长, 0.0, 1.0)


func _refresh_team_bar(info: Dictionary) -> void:
	_team_bar.text = "红方 士气 %d   宝石 %d   水晶 %d   星杯 %d      ｜      蓝方 士气 %d   宝石 %d   水晶 %d   星杯 %d      ｜  牌库 %d  弃牌 %d  房间 %d" % [
		int(info.get("red_morale", 0)), int(info.get("red_gem", 0)), int(info.get("red_crystal", 0)), int(info.get("red_grail", 0)),
		int(info.get("blue_morale", 0)), int(info.get("blue_gem", 0)), int(info.get("blue_crystal", 0)), int(info.get("blue_grail", 0)),
		int(info.get("pile", 0)), int(info.get("discard", 0)), int(info.get("room_id", 0)),
	]


func _refresh_players() -> void:
	_刷新座位椭圆()
	for c: Node in _players_root.get_children():
		c.queue_free()
	_panel_of.clear()
	_等待条.clear()
	var n: int = Data.player_list.size()
	if n == 0:
		return
	for i: int in range(n):
		var p: GPlayer = Data.player_list[i]
		# 自己排在底部（角度 90°），其余顺时针
		var ang: float = PI / 2.0 + TAU * float(i) / float(n)
		var pos: Vector2 = _中心 + Vector2(cos(ang) * _半径x, sin(ang) * _半径y) - Vector2(PANEL_W / 2.0, PANEL_H / 2.0)
		var panel: Panel = _make_player_panel(p)
		panel.position = pos
		_players_root.add_child(panel)
		_panel_of[p.id] = panel
	_refresh_panel_selection()
	_刷新等待条()


func _make_player_panel(p: GPlayer) -> Panel:
	var panel: Panel = Panel.new()
	panel.size = Vector2(PANEL_W, PANEL_H)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.clip_contents = true
	panel.add_theme_stylebox_override("panel", _make_panel_style(p))

	# 已准备：叠一层准备框贴图（与底框同尺寸）
	if p.ready:
		var ready_tex: Texture2D = Art.ui("playerReadyRed" if p.color == GConst.RED else ("playerReadyBlue" if p.color == GConst.BLUE else "playerReady"))
		if ready_tex != null:
			var ready_rect: TextureRect = TextureRect.new()
			ready_rect.position = Vector2.ZERO
			ready_rect.size = Vector2(PANEL_W, PANEL_H)
			ready_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ready_rect.stretch_mode = TextureRect.STRETCH_SCALE
			ready_rect.texture = ready_tex
			panel.add_child(ready_rect)

	# 文字底衬：压暗底框上的装饰花纹，保证信息可读
	var scrim: ColorRect = ColorRect.new()
	scrim.position = Vector2(70, 3)
	scrim.size = Vector2(PANEL_W - 72, 118)
	scrim.color = Color(0, 0, 0, 0.35)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(scrim)

	# 立绘（小图，保持比例）
	var avatar: TextureRect = _make_icon_rect(Vector2(AVATAR_W, AVATAR_H))
	avatar.position = Vector2(8, 6)
	avatar.texture = Art.role_avatar(p.role_id)
	panel.add_child(avatar)

	# 形态图标：横置时叠在立绘下沿
	if p.tap:
		var tap_tex: Texture2D = Art.role_tap(p.role_id)
		if tap_tex != null:
			var tap_rect: TextureRect = _make_icon_rect(Vector2(AVATAR_W, 21.0))
			tap_rect.position = Vector2(8, 97)
			tap_rect.texture = tap_tex
			panel.add_child(tap_rect)

	# 名称：N号 + 角色名 + 昵称
	var nm: Label = Label.new()
	nm.position = Vector2(74, 6)
	nm.size = Vector2(PANEL_W - 80, 48)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.text = "%d号 %s\n%s%s" % [p.id, p.role_name, p.nickname, "（你）" if p.id == Logic.my_player_id else ""]
	nm.add_theme_font_size_override("font_size", NAME_FONT)
	panel.add_child(nm)

	# 数值信息：手牌 / 治疗 / 宝石 / 水晶 / 能量，已准备时补一行
	var info: VBoxContainer = VBoxContainer.new()
	info.position = Vector2(74, 54)
	info.size = Vector2(PANEL_W - 80, 68)
	info.add_theme_constant_override("separation", 0)
	panel.add_child(info)
	var line_hand: HBoxContainer = HBoxContainer.new()
	line_hand.add_theme_constant_override("separation", 3)
	info.add_child(line_hand)
	_add_icon_text(line_hand, Art.ui("card"), "手牌 %d/%d" % [p.hand_cards_num, p.hand_cards_max], INFO_FONT)
	_add_icon_text(line_hand, Art.ui("heal"), "治疗 %d/%d" % [p.cross_num, p.cross_max], INFO_FONT)
	var line_energy: HBoxContainer = HBoxContainer.new()
	line_energy.add_theme_constant_override("separation", 3)
	info.add_child(line_energy)
	_add_icon_text(line_energy, Art.ui("gem"), str(p.gem), INFO_FONT)
	_add_icon_text(line_energy, Art.ui("crystal"), str(p.crystal), INFO_FONT)
	_add_icon_text(line_energy, null, "能量 %d/%d" % [p.gem + p.crystal, p.energy_max], INFO_FONT)
	if p.ready:
		_add_icon_text(info, null, "已准备", TINY_FONT)

	# 底部图标区：状态/独有效果图标行 + 指示物行
	var icons: VBoxContainer = VBoxContainer.new()
	icons.position = Vector2(8, 122)
	icons.size = Vector2(PANEL_W - 16, 54)
	icons.add_theme_constant_override("separation", 2)
	panel.add_child(icons)
	var status_row: HBoxContainer = HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 2)
	_add_status_icons(status_row, p)
	if status_row.get_child_count() > 0:
		icons.add_child(status_row)
	var token_row: HBoxContainer = HBoxContainer.new()
	token_row.add_theme_constant_override("separation", 6)
	_add_token_entries(token_row, p)
	if token_row.get_child_count() > 0:
		icons.add_child(token_row)

	# 面板底部：操作等待进度条（只在「正在等这名玩家回复」时显示，由 _刷新等待条() 控制）
	panel.add_child(_make_wait_bar(p.id))

	panel.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_on_player_clicked(p.id))
	return panel


## 面板底部的等待进度条：底色暗、填充亮，长度表示「本次等待还剩多少」
func _make_wait_bar(pid: int) -> ProgressBar:
	var 条: ProgressBar = ProgressBar.new()
	条.show_percentage = false
	条.min_value = 0.0
	条.max_value = 1.0
	条.value = 0.0
	条.position = Vector2(8, PANEL_H - 9)
	条.size = Vector2(PANEL_W - 16, 8)
	条.visible = false
	条.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var 底: StyleBoxFlat = StyleBoxFlat.new()
	底.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	底.set_corner_radius_all(4)
	条.add_theme_stylebox_override("background", 底)
	var 填充: StyleBoxFlat = StyleBoxFlat.new()
	填充.bg_color = Color(1.0, 0.82, 0.3)
	填充.set_corner_radius_all(4)
	条.add_theme_stylebox_override("fill", 填充)
	_等待条[pid] = 条
	return 条


## 面板底框：优先用队伍边框贴图（红/蓝/无队伍），贴图缺失时退回纯色
func _make_panel_style(p: GPlayer) -> StyleBox:
	var frame_name: String = "playerFrameRed" if p.color == GConst.RED else ("playerFrameBlue" if p.color == GConst.BLUE else "playerFrameNone")
	var frame: Texture2D = Art.ui(frame_name)
	if frame != null:
		var st: StyleBoxTexture = StyleBoxTexture.new()
		st.texture = frame
		return st
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.55, 0.12, 0.12, 0.85) if p.color == GConst.RED else (Color(0.12, 0.2, 0.5, 0.85) if p.color == GConst.BLUE else Color(0.25, 0.25, 0.25, 0.85))
	sb.border_width_bottom = 2
	sb.border_color = Color(0.9, 0.85, 0.4)
	return sb


## 生成按比例缩放的小图标框
func _make_icon_rect(sz: Vector2) -> TextureRect:
	var tex: TextureRect = TextureRect.new()
	tex.size = sz
	tex.custom_minimum_size = sz
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return tex


## 往水平容器追加「图标 + 文本」，无图标时只显示文本
func _add_icon_text(box: BoxContainer, icon_tex: Texture2D, text: String, font_size: int) -> void:
	if icon_tex != null:
		var icon: TextureRect = _make_icon_rect(Vector2(21, 21))
		icon.texture = icon_tex
		box.add_child(icon)
	var lb: Label = Label.new()
	lb.text = text
	lb.add_theme_font_size_override("font_size", font_size)
	box.add_child(lb)


## 基础效果 + 独有效果图标行（无图标时退化为卡名文字）
func _add_status_icons(box: HBoxContainer, p: GPlayer) -> void:
	for st: GPlayer.BasicStatus in p.basic_status_list:
		if st.card == null:
			continue
		var tex: Texture2D = Art.status_icon(st.card.card_name)
		if tex != null:
			var icon: TextureRect = _make_icon_rect(Vector2(STATUS_ICON_SIZE, STATUS_ICON_SIZE))
			icon.texture = tex
			icon.tooltip_text = st.card.card_name
			box.add_child(icon)
		else:
			var lb: Label = Label.new()
			lb.text = st.card.card_name
			lb.add_theme_font_size_override("font_size", TINY_FONT)
			box.add_child(lb)
	for i: int in range(p.specials.size()):
		if not p.specials[i]:
			continue
		var ex_tex: Texture2D = Art.exclusive_icon(i)
		if ex_tex != null:
			var ex_icon: TextureRect = _make_icon_rect(Vector2(STATUS_ICON_SIZE, STATUS_ICON_SIZE))
			ex_icon.texture = ex_tex
			box.add_child(ex_icon)


## 指示物行：图标 + 名称 数值/上限（图标缺失时退化为纯文字）
func _add_token_entries(box: HBoxContainer, p: GPlayer) -> void:
	for slot: int in range(p.tokens.size()):
		var tk: Variant = p.tokens[slot]
		if tk == null:
			continue
		var entry: HBoxContainer = HBoxContainer.new()
		entry.add_theme_constant_override("separation", 1)
		var tk_tex: Texture2D = Art.token_icon(slot)
		if tk_tex != null:
			var tk_icon: TextureRect = _make_icon_rect(Vector2(TOKEN_ICON_SIZE, TOKEN_ICON_SIZE))
			tk_icon.texture = tk_tex
			entry.add_child(tk_icon)
		var lb: Label = Label.new()
		lb.text = "%s %d/%d" % [tk.token_name, tk.num, tk.max_num]
		lb.add_theme_font_size_override("font_size", TINY_FONT)
		entry.add_child(lb)
		box.add_child(entry)


func _refresh_hand() -> void:
	for c: Node in _hand_root.get_children():
		c.queue_free()
	var cards: Array[GCard] = Data.hand_cards
	var n: int = cards.size()
	# 手牌层是场景里定宽的一条带；牌在这条带里居中排，超过上限就重叠
	var 区宽: float = _hand_root.size.x
	var total_w: float = CARD_W * n
	if n > 0:
		total_w = minf(float(CARD_W) * n, 区宽)
	var 起始x: float = maxf((区宽 - total_w) * 0.5, 0.0)
	_cover_box.position.x = _hand_root.position.x
	_refresh_cover()
	for i: int in range(n):
		var card: GCard = cards[i]
		var node: Control = _make_card_node(card)
		var x: float = 起始x + float(i) * (total_w / maxf(float(n), 1.0))
		node.position = Vector2(x, 0)
		if _sel_cards.has(card.id):
			node.position = Vector2(x, -18)
			node.modulate = Color(1.0, 1.0, 0.6)
		_hand_root.add_child(node)


## 盖牌区：标题 + 每张盖牌的卡面缩略图（悬浮显示卡名与说明）
## 「选盖牌」模式下缩略图可点选（用于技能要求指定一张盖牌，如蝶舞的毒粉）
func _refresh_cover() -> void:
	for c: Node in _cover_box.get_children():
		c.queue_free()
	var cards: Array[GCard] = []
	for cc: GCard in Data.cover_cards:
		if cc != null:
			cards.append(cc)
	if cards.is_empty():
		return
	var title: Label = Label.new()
	title.text = "盖牌（%d）%s" % [cards.size(), "：请选择" if _selecting_cover else ""]
	title.add_theme_font_size_override("font_size", 19)
	_cover_box.add_child(title)
	for card: GCard in cards:
		var thumb: TextureRect = TextureRect.new()
		thumb.custom_minimum_size = Vector2(38, 54)
		thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		thumb.texture = Art.card_face(card)
		thumb.tooltip_text = _card_tip(card)
		if _selecting_cover:
			thumb.mouse_filter = Control.MOUSE_FILTER_STOP
			thumb.modulate = Color(1.0, 1.0, 0.6) if _sel_cards.has(card.id) else Color.WHITE
			thumb.gui_input.connect(func(ev: InputEvent) -> void:
				if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
					_on_card_clicked(card.id))
		else:
			thumb.mouse_filter = Control.MOUSE_FILTER_PASS
		_cover_box.add_child(thumb)


## 卡牌悬浮提示文本（手牌与盖牌共用）
func _card_tip(card: GCard) -> String:
	return "%s【%s】\n%s" % [card.card_name, card.property, card.description]


## 该卡牌是否为自己的盖牌
func _is_my_cover(card_id: int) -> bool:
	for cc: GCard in Data.cover_cards:
		if cc != null and cc.id == card_id:
			return true
	return false


func _make_card_node(card: GCard) -> Control:
	var node: Control = Control.new()
	node.size = Vector2(CARD_W, CARD_H)
	node.mouse_filter = Control.MOUSE_FILTER_STOP
	var tex: TextureRect = TextureRect.new()
	tex.size = Vector2(CARD_W, CARD_H)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_SCALE
	var path: String = card.texture_path()
	if path != "" and ResourceLoader.exists(path):
		tex.texture = load(path)
	node.add_child(tex)
	var tag: Label = Label.new()
	tag.position = Vector2(3, CARD_H - 54)
	tag.size = Vector2(CARD_W - 6, 52)
	tag.add_theme_font_size_override("font_size", 18)
	tag.text = "%s·%s" % [GConst.element_to_chinese(card.element_enum()), card.card_name]
	node.add_child(tag)
	node.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_on_card_clicked(card.id))
	node.tooltip_text = _card_tip(card)
	return node


# ============================================================
# 收到服务端询问
# ============================================================
func _on_command(data: Dictionary) -> void:
	var cmds: Array = data.get("commands", [])
	if cmds.is_empty():
		return
	var cmd: Dictionary = cmds[0]
	var cmd_type: int = int(data.get("cmd_type", 0))
	var respond_id: int = int(cmd.get("respond_id", 0))
	if cmd_type == GConst.CmdType.Action:
		# 行动询问：第一项是通用行动，其余是角色可选技能
		if int(cmd.get("src_id", -1)) != Logic.my_player_id:
			return
		_build_skill_buttons(cmds)
	else:
		# respond_id >= 100 视为「是否发动某技能」的询问
		if respond_id >= 100:
			if int(cmd.get("src_id", -1)) != Logic.my_player_id:
				return
			_skill_ask_id = respond_id
			_pending = cmd
			_pending_type = GConst.Msg.Respond
			_enter_skill_ask()
			return
		var args: Array = cmd.get("args", [])
		var target_id: int = -1
		if respond_id == GConst.RespondType.ReplyAttack and args.size() > 2:
			target_id = int(args[2])
		elif respond_id == GConst.RespondType.Discard or respond_id == GConst.RespondType.DiscardCover:
			target_id = int(args[0]) if args.size() > 0 else -1
		elif respond_id == GConst.RespondType.Weaken or respond_id == GConst.RespondType.Heal:
			target_id = int(args[0]) if args.size() > 0 else -1
		elif respond_id == GConst.RespondType.AdditionalAction:
			_enter_additional_action(args)
			return
		if target_id != Logic.my_player_id:
			return
	_pending = cmd
	_pending_type = GConst.Msg.Action if cmd_type == GConst.CmdType.Action else GConst.Msg.Respond
	_enter_pending()


## 是否发动技能的询问：确定=发动，取消=放弃
## args 编码：args[0]=需选牌 args[1]=需选目标 args[2]=选盖牌 args[3]=选项数 args[4..]=选项值
## 选项文案在命令的 notes 里；有选项时改为渲染选项按钮，点哪个就回哪个值
func _enter_skill_ask() -> void:
	_mode = 3
	var args: Array = _pending.get("args", [])
	_skill_ask_need_card = int(args[0]) if args.size() > 0 else 0
	_skill_ask_need_target = int(args[1]) if args.size() > 1 else 0
	_skill_ask_card_source = int(args[2]) if args.size() > 2 else GConst.CardSource.Hand
	# need_card 为需要选出的牌数（1 或 2），复用 _need_cards 驱动点选上限与「确定」可用性
	_need_cards = _skill_ask_need_card
	_need_players = _skill_ask_need_target
	var 选项数: int = int(args[3]) if args.size() > 3 else 0
	_skill_options.clear()
	for i: int in range(选项数):
		if args.size() > 4 + i:
			_skill_options.append(int(args[4 + i]))
	_selecting_cover = _skill_ask_card_source != GConst.CardSource.Hand
	_sel_cards.clear()
	_sel_players.clear()
	_cancel_btn.disabled = false
	_unaction_btn.disabled = true
	_giveup_btn.disabled = true
	if not _skill_options.is_empty():
		_build_skill_option_buttons(_skill_options, _pending.get("notes", []))
	elif _selecting_cover:
		_ok_btn.disabled = true
		_set_tip("【%s】：请从下方盖牌中选择一张" % GConst.skill_name(_skill_ask_id))
	else:
		_set_tip("是否发动【%s】？%s%s" % [
			GConst.skill_name(_skill_ask_id),
			"（需选牌）" if _skill_ask_need_card == 1 else "",
			"（需选目标）" if _skill_ask_need_target == 1 else "",
		])
	_refresh_hand()
	_refresh_panel_selection()
	_update_ok_state()


## 技能询问的选项按钮：每个可选值一个按钮，点击即回复该值
func _build_skill_option_buttons(values: Array[int], labels: Array) -> void:
	_clear_skill_buttons()
	_ok_btn.disabled = true
	var 提示: String = "【%s】：先选好需要的牌/目标，再点选项" % GConst.skill_name(_skill_ask_id)
	if _selecting_cover:
		提示 += "（盖牌在下方可点选）"
	_set_tip(提示)
	for i: int in range(values.size()):
		var v: int = values[i]
		var label: String = str(labels[i]) if i < labels.size() and str(labels[i]) != "" else GConst.skill_name(v)
		var b: Button = Button.new()
		b.text = label
		b.custom_minimum_size = Vector2(233.0, 底部行高)
		b.add_theme_font_size_override("font_size", BUTTON_FONT)
		b.pressed.connect(func() -> void: _choose_skill_option(v))
		_action_box.add_child(b)
		_skill_buttons.append(b)


## 选择某技能选项：连同已选目标/卡牌一并回传
func _choose_skill_option(value: int) -> void:
	_send_respond(_skill_ask_id, _sel_players, _sel_cards, [value])


## 额外行动询问：把每个可选 cause 变成一个按钮
func _enter_additional_action(causes: Array) -> void:
	_mode = 3
	_skill_ask_id = -1
	_pending = {"args": causes}
	_pending_type = GConst.Msg.Respond
	_ok_btn.disabled = true
	_cancel_btn.disabled = false
	_unaction_btn.disabled = true
	_giveup_btn.disabled = true
	_clear_skill_buttons()
	for i: int in range(causes.size()):
		var cause: int = int(causes[i])
		var b: Button = Button.new()
		b.text = GConst.skill_name(cause)
		b.custom_minimum_size = Vector2(200.0, 底部行高)
		b.add_theme_font_size_override("font_size", BUTTON_FONT)
		b.pressed.connect(func() -> void: _choose_additional_action(cause))
		_action_box.add_child(b)
		_skill_buttons.append(b)
	_set_tip("有额外行动可用，请选择")


func _choose_additional_action(cause: int) -> void:
	Logic.send_respond(GConst.RespondType.AdditionalAction, [], [], [cause])
	_clear_skill_buttons()
	_clear_pending()


## 行动询问里附带的技能 → 生成按钮
func _build_skill_buttons(cmds: Array) -> void:
	_clear_skill_buttons()
	for i: int in range(1, cmds.size()):
		var c: Dictionary = cmds[i]
		var sk_type: int = int(c.get("respond_id", 0))
		var args: Array = c.get("args", [])
		if args.is_empty():
			continue
		var sk_id: int = int(args[0])
		var need_card: int = int(args[1]) if args.size() > 1 else 0
		var need_target: int = int(args[2]) if args.size() > 2 else 0
		var b: Button = Button.new()
		b.text = GConst.skill_name(sk_id)
		b.custom_minimum_size = Vector2(164.0, 底部行高)
		b.add_theme_font_size_override("font_size", BUTTON_FONT)
		b.pressed.connect(func() -> void: _choose_skill(sk_type, sk_id, need_card, need_target))
		_action_box.add_child(b)
		_skill_buttons.append(b)


func _clear_skill_buttons() -> void:
	for b: Node in _skill_buttons:
		if is_instance_valid(b):
			b.queue_free()
	_skill_buttons.clear()


func _choose_skill(sk_type: int, sk_id: int, need_card: int, need_target: int) -> void:
	_mode = 4
	_pending_skill_type = sk_type
	_pending_skill_id = sk_id
	_skill_need_card = need_card
	_skill_need_target = need_target
	_sel_cards.clear()
	_sel_players.clear()
	_unaction_btn.disabled = true
	_giveup_btn.disabled = true
	_ok_btn.disabled = true
	_cancel_btn.disabled = false
	_set_tip("发动【%s】：%s%s点「确定」" % [
		GConst.skill_name(sk_id),
		"选择卡牌，" if need_card == 1 else "",
		"选择目标，" if need_target == 1 else "",
	])
	_refresh_hand()
	_refresh_panel_selection()
	_update_ok_state()


func _enter_pending() -> void:
	_sel_cards.clear()
	_sel_players.clear()
	_mode = 0
	var respond_id: int = int(_pending.get("respond_id", 0))
	var args: Array = _pending.get("args", [])
	_ok_btn.disabled = true
	_cancel_btn.disabled = true
	_unaction_btn.disabled = true
	_giveup_btn.disabled = true
	if _pending_type == GConst.Msg.Action:
		# 行动阶段
		_mode = 1
		_need_cards = 1
		_need_players = 0
		_set_tip("轮到你了：选择一张手牌作为攻击/法术，或点「无法行动」「放弃行动」")
		_unaction_btn.disabled = false
		_giveup_btn.disabled = false
		_buy_btn.disabled = false
		_synth_btn.disabled = false
		_extract_btn.disabled = false
	else:
		match respond_id:
			GConst.RespondType.ReplyAttack:
				_mode = 2
				_need_cards = 1
				# 应战要指定「反击目标」（敌方、且不是原攻击者），所以这里也要选 1 名玩家
				_need_players = 1
				if _可应战():
					_set_tip("你被攻击了：出同系攻击牌「应战」并选一名敌方玩家作为反击目标（不能选原攻击者），或出【圣光】「抵挡」，或点「放弃行动」")
				else:
					_set_tip("你被攻击了：本次攻击无法应战，出【圣光】「抵挡」或点「放弃行动」")
				_giveup_btn.disabled = false
			GConst.RespondType.Discard, GConst.RespondType.DiscardCover:
				_mode = 2
				_need_cards = int(args[2]) if args.size() > 2 else 1
				_set_tip("手牌超限：请选择 %d 张牌弃掉" % _need_cards)
			GConst.RespondType.Weaken:
				_mode = 2
				_need_cards = 0
				_set_tip("你被虚弱了：点「确定」强摸 %d 张牌，或点「取消」直接结束回合" % (int(args[1]) if args.size() > 1 else 0))
				_ok_btn.disabled = false
				_cancel_btn.disabled = false
			GConst.RespondType.Heal:
				_mode = 2
				_need_cards = 0
				_set_tip("是否用治疗抵御本次 %d 点法术伤害？（点「确定」使用）" % (int(args[1]) if args.size() > 1 else 0))
				_ok_btn.disabled = false
				_cancel_btn.disabled = false
			GConst.RespondType.Bullet:
				_mode = 2
				_need_cards = 1
				_set_tip("魔弹传递：出【魔弹】继续传递，或点「放弃行动」")
				_giveup_btn.disabled = false
			_:
				_mode = 2
				_need_cards = 0
	_refresh_hand()
	_refresh_panel_selection()


# ============================================================
# 交互
# ============================================================
func _on_card_clicked(card_id: int) -> void:
	if _mode == 3 and _skill_ask_need_card != 1:
		return
	# 应答（应战/抵挡、弃牌、魔弹传递等）同样要能点手牌
	if _mode == 2 and _need_cards <= 0:
		return
	if _mode != 1 and _mode != 2 and _mode != 3 and _mode != 4:
		return
	# 选牌来源限制：盖牌询问只收盖牌，手牌询问只收手牌，两者皆可则都收
	if _mode == 3 and _skill_ask_id >= 100:
		if _skill_ask_card_source == GConst.CardSource.Cover and not _is_my_cover(card_id):
			return
		if _skill_ask_card_source == GConst.CardSource.Hand and _is_my_cover(card_id):
			return
	if _sel_cards.has(card_id):
		_sel_cards.erase(card_id)
	else:
		if _need_cards > 0 and _sel_cards.size() >= _need_cards:
			_sel_cards.clear()
		_sel_cards.append(card_id)
	_refresh_hand()
	_update_ok_state()


func _on_player_clicked(player_id: int) -> void:
	if _mode == 3 and _skill_ask_need_target <= 0:
		return
	# 应答里需要目标的（目前只有应战的反击目标）也要能点玩家面板
	if _mode == 2 and _need_players <= 0:
		return
	if _mode != 1 and _mode != 2 and _mode != 3 and _mode != 4:
		return
	if player_id == Logic.my_player_id:
		return
	# 应战的反击目标：只能选敌方、且不能是原攻击者（规则同服务端）
	if _mode == 2 and int(_pending.get("respond_id", 0)) == GConst.RespondType.ReplyAttack and not _可作反击目标(player_id):
		_set_tip("反击目标只能选「敌方玩家」，且不能选原攻击者")
		return
	if _sel_players.has(player_id):
		_sel_players.erase(player_id)
	elif _need_players > 1:
		# 多目标：累积选择，超过上限则重新开始
		if _sel_players.size() >= _need_players:
			_sel_players.clear()
		_sel_players.append(player_id)
	else:
		_sel_players = [player_id]
	_refresh_panel_selection()
	_update_ok_state()


func _update_ok_state() -> void:
	if _mode == 1:
		_ok_btn.disabled = _sel_cards.is_empty() and _sel_players.is_empty()
	elif _mode == 3:
		if _skill_ask_id < 100:
			_ok_btn.disabled = true
		else:
			var 牌够: bool = _sel_cards.size() == _skill_ask_need_card if _skill_ask_need_card > 0 else true
			var 目标够: bool = _sel_players.size() == _skill_ask_need_target if _skill_ask_need_target > 0 else true
			# 有选项时「确定」始终不可用，由选项按钮提交；选项按钮不随选牌状态禁用
			# （不同选项的前置条件不同，交由角色侧校验）
			_ok_btn.disabled = true if not _skill_options.is_empty() else not (牌够 and 目标够)
	elif _mode == 4:
		_ok_btn.disabled = (_skill_need_card == 1 and _sel_cards.is_empty()) or (_skill_need_target == 1 and _sel_players.is_empty())
	elif _mode == 2:
		match int(_pending.get("respond_id", 0)):
			GConst.RespondType.ReplyAttack:
				if _sel_cards.is_empty():
					_ok_btn.disabled = true
				elif _选中是圣光():
					# 圣光抵挡不需要反击目标
					_ok_btn.disabled = false
				elif not _可应战():
					_ok_btn.disabled = true
				else:
					# 应战：必须同时选定反击目标
					_ok_btn.disabled = _sel_players.is_empty()
			GConst.RespondType.Bullet:
				_ok_btn.disabled = _sel_cards.is_empty()
			GConst.RespondType.Discard, GConst.RespondType.DiscardCover:
				_ok_btn.disabled = _sel_cards.size() != _need_cards
			GConst.RespondType.Weaken, GConst.RespondType.Heal:
				_ok_btn.disabled = false
			_:
				_ok_btn.disabled = false


## 本次应战询问是否允许应战（args[0] = 命中率：非普通命中率不允许应战）
func _可应战() -> bool:
	var args: Array = _pending.get("args", [])
	if args.is_empty():
		return true
	return int(args[0]) == GConst.HitRate.Normal


## 本次攻击的原攻击者（args[3]）：应战的反击目标不能是他
func _原攻击者() -> int:
	var args: Array = _pending.get("args", [])
	return int(args[3]) if args.size() > 3 else -1


## 应战的反击目标是否可选：敌方玩家、且不是原攻击者（规则同服务端 v_reattack）
func _可作反击目标(player_id: int) -> bool:
	if player_id == Logic.my_player_id or player_id == _原攻击者():
		return false
	var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
	var 他: GPlayer = Data.get_player_by_id(player_id)
	if 我 == null or 他 == null:
		return false
	return 我.color != GConst.TEAM_NONE and 他.color != GConst.TEAM_NONE and 我.color != 他.color


## 选中的手牌是否是【圣光】（抵挡用，不需要反击目标）
func _选中是圣光() -> bool:
	if _sel_cards.is_empty():
		return false
	var card: GCard = Data.get_card(_sel_cards[0])
	return card != null and card.card_name_enum() == GConst.CardName.HolyLight


func _refresh_panel_selection() -> void:
	for pid: int in _panel_of.keys():
		var panel: Panel = _panel_of[pid]
		if _sel_players.has(pid):
			panel.modulate = Color(1.0, 1.0, 0.5)
		elif pid == _cur_player_id:
			panel.modulate = Color(0.7, 1.0, 0.7)
		else:
			panel.modulate = Color.WHITE


# ============================================================
# 确定 / 取消 / 放弃
# ============================================================
func _on_ok() -> void:
	var respond_id: int = int(_pending.get("respond_id", 0))
	var args: Array = _pending.get("args", [])
	# 是否发动技能的询问
	if _mode == 3:
		if _skill_ask_id >= 100:
			_send_respond(_skill_ask_id, _sel_players, _sel_cards, [1])
		return
	# 发动技能
	if _mode == 4:
		_send_action(_pending_skill_type, _pending_skill_id, _sel_players, _sel_cards, [])
		return
	if _pending_type == GConst.Msg.Action:
		if _sel_cards.is_empty():
			_set_tip("请先选择一张手牌")
			return
		var card: GCard = Data.get_card(_sel_cards[0])
		if card == null:
			return
		if card.is_attack():
			if _sel_players.is_empty():
				_set_tip("攻击需要先选择一个对手")
				return
			_send_action(GConst.ActionType.Attack, 0, _sel_players, _sel_cards, [])
		else:
			var dst: Array = _sel_players
			if dst.is_empty():
				dst = [Logic.my_player_id]
			_send_action(GConst.ActionType.Magic, 0, dst, _sel_cards, [])
		return
	match respond_id:
		GConst.RespondType.ReplyAttack:
			if _sel_cards.is_empty():
				_set_tip("请先选择一张手牌（同系攻击牌应战，或【圣光】抵挡）")
				return
			var card2: GCard = Data.get_card(_sel_cards[0])
			if card2 == null:
				return
			# 【圣光】抵挡：不需要反击目标
			if card2.card_name_enum() == GConst.CardName.HolyLight:
				_send_respond(respond_id, [], _sel_cards, [GConst.Reattack.Block])
				return
			if not _可应战():
				_set_tip("本次攻击无法应战：请出【圣光】「抵挡」，或点「放弃行动」")
				return
			if _sel_players.is_empty():
				_set_tip("应战要先选一名反击目标（敌方玩家，且不能是原攻击者）")
				return
			_send_respond(respond_id, _sel_players, _sel_cards, [GConst.Reattack.Attack])
		GConst.RespondType.Bullet:
			_send_respond(respond_id, [], _sel_cards, [GConst.Reattack.Attack])
		GConst.RespondType.Discard, GConst.RespondType.DiscardCover:
			_send_respond(respond_id, [], _sel_cards, [])
		GConst.RespondType.Weaken:
			_send_respond(respond_id, [], [], [1])
		GConst.RespondType.Heal:
			var harm: int = int(args[1]) if args.size() > 1 else 0
			_send_respond(respond_id, [], [], [harm])
		_:
			_send_respond(respond_id, [], _sel_cards, [])


func _on_cancel() -> void:
	var respond_id: int = int(_pending.get("respond_id", 0))
	# 技能询问：取消=放弃
	if _mode == 3:
		if _skill_ask_id >= 100:
			_send_respond(_skill_ask_id, [], [], [0])
		else:
			# 额外行动：空 args 表示跳过
			_clear_skill_buttons()
			Logic.send_respond(GConst.RespondType.AdditionalAction, [], [], [])
			_clear_pending()
		return
	# 发动技能时取消：退回行动阶段
	if _mode == 4:
		_pending_skill_id = -1
		_mode = 1
		_sel_cards.clear()
		_sel_players.clear()
		_ok_btn.disabled = true
		_unaction_btn.disabled = false
		_giveup_btn.disabled = false
		_refresh_hand()
		_refresh_panel_selection()
		return
	if _pending_type == GConst.Msg.Respond and respond_id == GConst.RespondType.Weaken:
		_send_respond(respond_id, [], [], [0])
		return
	_sel_cards.clear()
	_sel_players.clear()
	_refresh_hand()
	_refresh_panel_selection()
	_update_ok_state()


func _on_unactional() -> void:
	_send_action(GConst.ActionType.Unactional, 0, [], [], [])


func _on_giveup() -> void:
	var respond_id: int = int(_pending.get("respond_id", 0))
	if _pending_type == GConst.Msg.Respond and respond_id == GConst.RespondType.ReplyAttack:
		_send_respond(respond_id, [], [], [GConst.Reattack.GiveUp])
		return
	if _pending_type == GConst.Msg.Respond and respond_id == GConst.RespondType.Bullet:
		_send_respond(respond_id, [], [], [GConst.Reattack.GiveUp])
		return
	_send_action(GConst.ActionType.None, 0, [], [], [])


func _act_special(aid: int, args: Array) -> void:
	if _mode != 1 or _pending_type != GConst.Msg.Action:
		return
	_send_action(GConst.ActionType.Special, aid, [], [], args)


func _send_action(action_type: int, action_id: int, dst: Array, cards: Array, args: Array) -> void:
	Logic.send_action(action_type, action_id, dst, cards, args)
	_clear_pending()


func _send_respond(respond_id: int, dst: Array, cards: Array, args: Array) -> void:
	Logic.send_respond(respond_id, dst, cards, args)
	_clear_pending()


func _clear_pending() -> void:
	_pending = {}
	_pending_type = -1
	_mode = 0
	_skill_ask_id = -1
	_skill_ask_need_card = 0
	_skill_ask_need_target = 0
	_skill_ask_card_source = 0
	_selecting_cover = false
	_skill_options.clear()
	_pending_skill_id = -1
	_pending_skill_type = -1
	_sel_cards.clear()
	_sel_players.clear()
	_clear_skill_buttons()
	_refresh_cover()
	_ok_btn.disabled = true
	_cancel_btn.disabled = true
	_unaction_btn.disabled = true
	_giveup_btn.disabled = true
	_refresh_hand()
	_refresh_panel_selection()


func on_invalid_input(_data: Dictionary) -> void:
	_set_tip("操作无效，请重新选择")
	_enter_pending()


# ============================================================
# 广播消息
# ============================================================
func _on_turn(player_id: int, round_id: int) -> void:
	_cur_player_id = player_id
	_refresh_panel_selection()
	var p: GPlayer = Data.get_player_by_id(player_id)
	# 轮到这个角色就放他自己的语音（对照参考工程 audio/<角色id>）；
	# 没有语音的角色（如 37 号）沿用原来的界面提示音，保证听得出轮到谁
	if p != null and Audio.有声效(str(p.role_id)):
		Audio.播音效(str(p.role_id))
	else:
		Art.play_sfx("It's your turn" if player_id == Logic.my_player_id else "TurnBegin")
	if p != null:
		_log_append("[回合 %d] 轮到 %s（%s）" % [round_id, p.nickname, p.role_name])


func _on_hit(src_id: int, dst_id: int, hit: int) -> void:
	var s: GPlayer = Data.get_player_by_id(src_id)
	var d: GPlayer = Data.get_player_by_id(dst_id)
	_log_append("%s 对 %s 的攻击%s" % [
		s.nickname if s != null else str(src_id),
		d.nickname if d != null else str(dst_id),
		"命中" if hit == 1 else "未命中",
	])
	if hit == 1:
		# 受击音效：这两条 ogg 的实际听感与文件名相反（参考工程是 HITMSG→sys-hit、HURTMSG→sys-hurt），按听感取 sys-hurt
		Audio.播音效("sys-hurt")
		_flash_panel(dst_id, Color(1.0, 0.7, 0.7))
	else:
		_float_text(dst_id, "未命中", Color(0.85, 0.85, 0.85))


func _on_card(msg: Dictionary) -> void:
	var src: int = int(msg.get("src_id", -1))
	var dst: int = int(msg.get("dst_id", -1))
	# 展示（亮牌/超限换牌）没有「对谁使用」的概念，单独写一行
	var 是展示: bool = int(msg.get("type", 0)) == GConst.CardMsgType.Show
	var p: GPlayer = Data.get_player_by_id(src)
	var names: Array = []
	var first_card: GCard = null
	for cid: Variant in msg.get("card_ids", []):
		var c: GCard = Data.get_card(int(cid))
		if c != null:
			names.append(c.card_name)
			if first_card == null:
				first_card = c
	# 出牌音效（对照参考项目 AudioManager 的 CARDMSG 分支）：攻击牌 atk-<系别>，法术牌 spell-<卡名>
	if first_card != null and not 是展示:
		if first_card.is_attack():
			Audio.播音效("atk-" + first_card.element)
		else:
			Audio.播音效("spell-" + first_card.card_name)
	var 谁: String = p.nickname if p != null else str(src)
	var 目标: GPlayer = Data.get_player_by_id(dst)
	if 是展示:
		_log_append("%s 展示：%s" % [谁, ", ".join(names)])
	elif 目标 == null or dst == src:
		_log_append("%s 对自己打出：%s" % [谁, ", ".join(names)])
	else:
		_log_append("%s 对 %s 打出：%s" % [谁, 目标.nickname, ", ".join(names)])
	if p != null:
		_flash_panel(src, Color(0.8, 1.0, 0.8))


func _on_hurt(msg: Dictionary) -> void:
	Audio.播音效("sys-hit")   # 同 _on_hit：两条音按听感对调
	var dst: int = int(msg.get("dst_id", -1))
	var src: int = int(msg.get("src_id", -1))
	var d: GPlayer = Data.get_player_by_id(dst)
	var s: GPlayer = Data.get_player_by_id(src)
	_log_append("%s 对 %s 造成 %d 点%s伤害" % [
		s.nickname if s != null else str(src),
		d.nickname if d != null else str(dst),
		int(msg.get("hurt", 0)),
		"法术" if int(msg.get("type", 0)) == GConst.HarmType.Magic else "攻击",
	])
	_float_text(dst, "-%d" % int(msg.get("hurt", 0)), Color(1.0, 0.45, 0.45))
	_flash_panel(dst, Color(1.0, 0.6, 0.6))


# ============================================================
# 表现：伤害飘字与面板闪烁
# ============================================================
## 在玩家面板上方浮现文字并上移淡出
func _float_text(pid: int, txt: String, color: Color) -> void:
	var panel: Panel = _panel_of.get(pid)
	if panel == null or not is_instance_valid(panel):
		return
	var lb: Label = Label.new()
	lb.text = txt
	lb.add_theme_font_size_override("font_size", 32)
	lb.add_theme_color_override("font_color", color)
	lb.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lb.add_theme_constant_override("outline_size", 6)
	lb.position = panel.position + Vector2(PANEL_W * 0.5 - 30.0, 6.0)
	lb.z_index = 10
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lb)
	var tw: Tween = create_tween().set_parallel(true)
	tw.tween_property(lb, "position:y", lb.position.y - 60.0, 0.7)
	tw.tween_property(lb, "modulate:a", 0.0, 0.7)
	tw.finished.connect(lb.queue_free)


## 玩家面板短暂泛色后恢复
func _flash_panel(pid: int, color: Color) -> void:
	var panel: Panel = _panel_of.get(pid)
	if panel == null or not is_instance_valid(panel):
		return
	panel.modulate = color
	var tw: Tween = create_tween()
	tw.tween_property(panel, "modulate", Color.WHITE, 0.35)


## 公告：写日志，并识别「游戏结束，X 方获胜」的胜负提示
func _on_gossip(txt: String) -> void:
	_log_append(txt)
	_play_result_sfx(txt, GConst.TEAM_NONE)


func _on_game_over(winner: int) -> void:
	_play_result_sfx("", winner)


## 胜负音效：只播一次；winner 为 TEAM_NONE 时从公告文本里识别获胜方
func _play_result_sfx(txt: String, winner: int) -> void:
	if _result_sfx_done:
		return
	var win_color: int = winner
	if win_color == GConst.TEAM_NONE:
		if not txt.contains("获胜"):
			return
		win_color = GConst.RED if txt.contains("红") else (GConst.BLUE if txt.contains("蓝") else GConst.TEAM_NONE)
		if win_color == GConst.TEAM_NONE:
			return
	var me: GPlayer = Data.get_player_by_id(Logic.my_player_id)
	if me == null:
		return
	_result_sfx_done = true
	# 胜负切音乐（对照参考项目 AudioManager：Win/Lose → play_bgm_scene(2, 胜否)）
	Audio.播放音乐(Audio.场景战斗, me.color == win_color)


# ============================================================
# 房间等待阶段操作
# ============================================================
func _on_ready_toggle() -> void:
	var me: GPlayer = Data.get_player_by_id(Logic.my_player_id)
	var is_ready: bool = me != null and me.ready
	Logic.set_ready(2 if is_ready else 1)
	_ready_btn.text = "取消准备" if not is_ready else "准备"


func _on_leave() -> void:
	Logic.leave_room()
	UI.goto_lobby()


## 发送聊天：服务端广播 Talk 后由 _on_gossip 回显到日志
func _on_chat_send() -> void:
	var txt: String = _chat_edit.text.strip_edges()
	if txt == "":
		return
	_chat_edit.text = ""
	Logic.talk(txt)


# ============================================================
# 小工具
# ============================================================
func _set_tip(t: String) -> void:
	_tip.text = t


func _log_append(t: String) -> void:
	_log.append_text(t + "\n")
