## 全局消息总线 —— 对应 Framework.Message.MessageSystem<T>
## C# 用 Dictionary<T, List<IMessageListener<T>>> 注册/派发；
## GDScript 用单个 signal + 监听表实现同样的语义。
extends Node

var _maps: Dictionary = {}          # msg:int -> Array[Object]
var _callback: Dictionary = {}      # Object -> Callable

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

## 注册监听；cb 形如 func(msg: int, params: Array) -> void
func regist(msg: int, listener: Object, cb: Callable) -> void:
	if not _maps.has(msg):
		_maps[msg] = []
	if not (_maps[msg] as Array).has(listener):
		(_maps[msg] as Array).append(listener)
	_callback[listener] = cb

## 支持不传 cb：按约定调用 listener.on_event_trigger(msg, params)
func regist_obj(msg: int, listener: Object, cb: Callable = Callable()) -> void:
	regist(msg, listener, cb)

func unregist(msg: int, listener: Object) -> void:
	if _maps.has(msg):
		(_maps[msg] as Array).erase(listener)
		if (_maps[msg] as Array).is_empty():
			_maps.erase(msg)

func unregist_all(listener: Object) -> void:
	for k in _maps.keys():
		unregist(k, listener)
	_callback.erase(listener)

func notify(msg: int, params: Array = []) -> void:
	if not _maps.has(msg):
		return
	for listener in (_maps[msg] as Array).duplicate():
		if listener == null or not is_instance_valid(listener):
			unregist(msg, listener)
			continue
		var cb: Callable = _callback.get(listener, Callable())
		if cb.is_valid():
			cb.call(msg, params)
		elif listener.has_method("on_event_trigger"):
			listener.on_event_trigger(msg, params)

func has_listener(msg: int) -> bool:
	return _maps.has(msg) and not (_maps[msg] as Array).is_empty()
