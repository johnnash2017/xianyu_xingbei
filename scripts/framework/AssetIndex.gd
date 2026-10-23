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
	var 文件: Array[String] = []
	var 子目录: Array[String] = []
	d.list_dir_begin()
	var entry := d.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = d.get_next()
			continue
		if d.current_is_dir():
			子目录.append(entry)
		else:
			文件.append(entry)
		entry = d.get_next()
	d.list_dir_end()
	# 先收本层文件、再进子目录，两层都按名字排序：
	# 同一个基名可能在多个地方各有一份（如 card/anMie.png 与 card/新图标/anMie.png），
	# 索引「先到先得」—— 不排序的话，导出后 DirAccess 的枚举顺序和编辑器不一样
	# （实测导出包里会先给子目录），同一张牌在编辑器里取正式卡面、在导出包里取到备用图。
	# 先文件后目录保证同层的正式资源优先，排序则让两个环境的结果完全一致。
	文件.sort()
	子目录.sort()
	for 名: String in 文件:
		_收文件(dir_path, 名)
	for 名: String in 子目录:
		_scan(dir_path.path_join(名))


## 把本层的一个文件按扩展名收进索引。导出后 res:// 目录里只剩 *.import（真实数据在
## .godot/imported/），编辑器里则是「原始文件 + 同名 .import」。两种形态统一还原成原始
## 文件名再建索引，索引值也必须用原始路径——ResourceLoader 会经 .import 里的 path= 解析到
## 实际的 .ctex。
func _收文件(dir_path: String, entry: String) -> void:
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
