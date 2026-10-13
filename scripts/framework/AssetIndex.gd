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
			# 导出后 res:// 目录里只剩 *.import（真实数据在 .godot/imported/），
			# 编辑器里则是「原始文件 + 同名 .import」。两种形态统一还原成原始文件名再建索引，
			# 索引值也必须用原始路径——ResourceLoader 会经 .import 里的 path= 解析到实际的 .ctex。
			var 文件名: String = entry
			if 文件名.ends_with(".import"):
				文件名 = 文件名.substr(0, 文件名.length() - ".import".length())
			var base: String = 文件名.get_basename().to_lower()
			var ext: String = 文件名.get_extension().to_lower()
			if ext in ["png", "jpg", "jpeg", "webp"]:
				if not _images.has(base):
					_images[base] = dir_path.path_join(文件名)
			elif ext in ["ogg", "wav", "mp3"]:
				if not _audio.has(base):
					_audio[base] = dir_path.path_join(文件名)
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
