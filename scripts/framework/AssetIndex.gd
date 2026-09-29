## 资源索引 —— 替代 Unity 的 AssetBundleManager.LoadAsset(bundle, name)
## 原工程按名字从 AssetBundle 取资源（如 "card/moDan"、"shengDun"）；
## Godot 里把 assets/ 下的 png/jpg/ogg 全部按文件名建索引，查找时忽略大小写与扩展名。
extends Node

var _images: Dictionary = {}     # 小写基名 -> res:// 路径
var _audio: Dictionary = {}
var _ready_done := false

func _ready() -> void:
	index_all()

func index_all() -> void:
	_images.clear()
	_audio.clear()
	_scan("res://assets")
	_ready_done = true

func _scan(dir_path: String) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var entry := d.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = d.get_next()
			continue
		var full := dir_path.path_join(entry)
		if d.current_is_dir():
			_scan(full)
		else:
			var base := entry.get_basename().to_lower()
			var ext := entry.get_extension().to_lower()
			if ext in ["png", "jpg", "jpeg", "webp"]:
				if not _images.has(base):
					_images[base] = full
			elif ext in ["ogg", "wav", "mp3"]:
				if not _audio.has(base):
					_audio[base] = full
		entry = d.get_next()
	d.list_dir_end()

## 对应 LoadAsset<Sprite>(bundle, name)：name 可以是 "card/moDan" 这类带目录的写法
func image(asset_name: String) -> String:
	if asset_name == "":
		return ""
	var key := asset_name.get_file().get_basename().to_lower()
	return _images.get(key, "")

## 对应 LoadAsset<AudioClip>(bundle, name)
func audio(clip_name: String) -> String:
	return _audio.get(clip_name.to_lower(), "")

func image_count() -> int:
	return _images.size()

func audio_count() -> int:
	return _audio.size()
