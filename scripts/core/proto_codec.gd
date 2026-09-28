class_name ProtoCodec
extends RefCounted
## protobuf 线格式通用编解码
## 与 C++ 端保持一致：只按「协议号 + 字段号」处理，不做 .proto 类型的强类型还原。
## 编码产物即 protobuf 消息体（不含帧头）。

# ============================================================
# 对外接口
# ============================================================

## 按协议号把字段字典编码成 protobuf 字节
static func encode(msg_type: int, values: Dictionary) -> PackedByteArray:
	return _encode_fields(ProtoSchema.fields(msg_type), values)


## 按协议号把 protobuf 字节解码成字段字典
static func decode(msg_type: int, data: PackedByteArray) -> Dictionary:
	return _decode_fields(ProtoSchema.fields(msg_type), data)


## 按子消息名编码（RoomInfo / SinglePlayerInfo / Command）
static func encode_named(sub_name: String, values: Dictionary) -> PackedByteArray:
	return _encode_fields(ProtoSchema.sub_fields(sub_name), values)


## 按子消息名解码
static func decode_named(sub_name: String, data: PackedByteArray) -> Dictionary:
	return _decode_fields(ProtoSchema.sub_fields(sub_name), data)


# ============================================================
# 编码
# ============================================================
static func _encode_fields(fs: Dictionary, values: Dictionary) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	var keys: Array = fs.keys()
	keys.sort()
	for fnum: int in keys:
		var f: Dictionary = fs[fnum]
		var name: String = f["n"]
		if not values.has(name):
			continue
		var value: Variant = values[name]
		if f.get("r", false):
			for item: Variant in (value as Array):
				_write_field(out, fnum, f, item)
		else:
			_write_field(out, fnum, f, value)
	return out


static func _write_field(out: PackedByteArray, fnum: int, f: Dictionary, value: Variant) -> void:
	var t: String = f["t"]
	match t:
		"bool":
			_write_tag(out, fnum, 0)
			_write_varint(out, 1 if value else 0)
		"i32", "u32", "i64", "u64", "enum":
			_write_tag(out, fnum, 0)
			_write_varint(out, int(value))
		"str":
			var b: PackedByteArray = str(value).to_utf8_buffer()
			_write_tag(out, fnum, 2)
			_write_varint(out, b.size())
			out.append_array(b)
		"bytes":
			var b: PackedByteArray = value
			_write_tag(out, fnum, 2)
			_write_varint(out, b.size())
			out.append_array(b)
		"msg":
			var sub: PackedByteArray = _encode_fields(ProtoSchema.sub_fields(f["s"]), value)
			_write_tag(out, fnum, 2)
			_write_varint(out, sub.size())
			out.append_array(sub)


static func _write_tag(out: PackedByteArray, fnum: int, wire_type: int) -> void:
	_write_varint(out, (fnum << 3) | wire_type)


## 按 protobuf 规则写变长整数；负数按 64 位补码展开为 10 字节
static func _write_varint(out: PackedByteArray, value: int) -> void:
	var v: int = value
	if v < 0:
		# 逻辑右移 7 位等价于「算术右移后只保留低 57 位」
		const LOW57: int = 0x01FFFFFFFFFFFFFF
		for i: int in range(9):
			out.append((v & 0x7F) | 0x80)
			v = (v >> 7) & LOW57
		out.append(v & 0x7F)
		return
	while v > 0x7F:
		out.append((v & 0x7F) | 0x80)
		v >>= 7
	out.append(v)


# ============================================================
# 解码
# ============================================================
static func _decode_fields(fs: Dictionary, data: PackedByteArray) -> Dictionary:
	var result: Dictionary = {}
	var pos: int = 0
	var total: int = data.size()
	while pos < total:
		var rd: Array = _read_varint(data, pos)
		var tag: int = rd[0]
		pos = rd[1]
		var fnum: int = tag >> 3
		var wire: int = tag & 7
		var f: Dictionary = fs.get(fnum, {})
		match wire:
			0:
				var rd2: Array = _read_varint(data, pos)
				pos = rd2[1]
				if not f.is_empty():
					_store(result, f, _cast_int(f["t"], rd2[0]))
			1:
				pos += 8
			5:
				pos += 4
			2:
				var rl: Array = _read_varint(data, pos)
				pos = rl[1]
				var ln: int = rl[0]
				if not f.is_empty():
					var chunk: PackedByteArray = data.slice(pos, pos + ln)
					_store(result, f, _cast_bytes(f, chunk))
				pos += ln
			_:
				push_error("ProtoCodec: 未知 wire type %d (字段 %d)" % [wire, fnum])
				return result
	return result


static func _store(result: Dictionary, f: Dictionary, value: Variant) -> void:
	var name: String = f["n"]
	if f.get("r", false):
		if not result.has(name):
			result[name] = []
		(result[name] as Array).append(value)
	else:
		result[name] = value


static func _cast_int(t: String, raw: int) -> int:
	match t:
		"i32":
			# 截断到 32 位并做符号扩展
			var v: int = raw & 0xFFFFFFFF
			if v >= 0x80000000:
				v -= 0x100000000
			return v
		"u32":
			return raw & 0xFFFFFFFF
		_:
			return raw


static func _cast_bytes(f: Dictionary, chunk: PackedByteArray) -> Variant:
	var t: String = f["t"]
	match t:
		"str":
			return chunk.get_string_from_utf8()
		"msg":
			return _decode_fields(ProtoSchema.sub_fields(f["s"]), chunk)
		_:
			return chunk


## 读变长整数，返回 [值, 新位置]
static func _read_varint(data: PackedByteArray, pos: int) -> Array:
	var result: int = 0
	var shift: int = 0
	while true:
		if pos >= data.size():
			push_error("ProtoCodec: 变长整数越界")
			return [result, pos]
		var b: int = data[pos]
		pos += 1
		result |= (b & 0x7F) << shift
		if (b & 0x80) == 0:
			break
		shift += 7
		if shift > 63:
			break
	return [result, pos]
