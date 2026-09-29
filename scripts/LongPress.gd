## 长按检测 —— 对应 Framework.UI.LongPress（C# 是 UIBehaviour + IPointerDownHandler/IPointerUpHandler）
## 该脚本在转换后的 battlemobile/*.tscn 里被声明为 ext_resource（id=5_LongPressgd），
## 但没有任何节点挂上它；这些预制体的根节点分别是 TextureRect / Label / VBoxContainer，
## 共同基类是 Control，故取 extends Control（可挂到上述任意节点）。
##
## ⚠ C# 在长按结束时会 `interceptBtn.enabled = false; interceptBtn.enabled = true;` 强制按钮重算状态 ——
## 那是 Unity 特有的写法。搬到 Godot 后 interceptBtn 就是玩家面板自己那个 Button，
## 而 Godot 的 `disabled = true` 会**清掉按钮当前的按下状态**（press_attempt / pressed 全归零），
## 于是「按下超过 0.5 秒再松手」的这一次点击根本不会发 pressed ——
## 表现就是「点对方头像没反应，得再点一次（或先点别人再点回来）」。这里不再做那个动作。
extends Control

## 对应 C# [FormerlySerializedAs("onLongPress")][SerializeField] private UnityEvent m_OnLongPress;
## UnityEvent -> Godot signal；另外保留 AddListener/RemoveListener 便于按 C# 写法注册。
signal OnLongPress

## 对应 C# [SerializeField][Range(0f, 5f)] private float LONG_PRESS_TIME = 0.5f;
var LONG_PRESS_TIME: float = 0.5

## 对应 C# private float pressTime = -1f;
var pressTime: float = -1.0


## 对应 C# private void Update()
func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if pressTime > 0.0 and now - pressTime > LONG_PRESS_TIME:
		pressTime = -1.0
		OnLongPress.emit()


## 对应 C# public void OnPointerDown(PointerEventData eventData)
func OnPointerDown(_event: InputEvent = null) -> void:
	pressTime = Time.get_ticks_msec() / 1000.0


## 对应 C# public void OnPointerUp(PointerEventData eventData)
func OnPointerUp(_event: InputEvent = null) -> void:
	pressTime = -1.0


## Unity 的 IPointerDownHandler/IPointerUpHandler -> Godot 的 _gui_input
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			OnPointerDown(mb)
		else:
			OnPointerUp(mb)
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			OnPointerDown(st)
		else:
			OnPointerUp(st)

# ---------------- UnityEvent 兼容入口 ----------------

## 对应 C# LongPress.OnLongPress.AddListener(cb)
func AddListener(cb: Callable) -> void:
	if not OnLongPress.is_connected(cb):
		OnLongPress.connect(cb)

## 对应 C# LongPress.OnLongPress.RemoveListener(cb)
func RemoveListener(cb: Callable) -> void:
	if OnLongPress.is_connected(cb):
		OnLongPress.disconnect(cb)

## 对应 C# LongPress.OnLongPress.RemoveAllListeners()
func RemoveAllListeners() -> void:
	for c in OnLongPress.get_connections():
		OnLongPress.disconnect(c["callable"])
