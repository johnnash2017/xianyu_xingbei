class_name Framing
extends RefCounted
## 帧格式（与 C++ 端 codec.cpp + zSocket2 完全一致）
##
## 线上完整一帧（小端）：
##   [0]  uint32 外层长度 L = 4 + protobuf 体长度
##   [4]  uint16 帧头长度     = 4 + protobuf 体长度（等于 L）
##   [6]  uint16 协议号
##   [8]  protobuf 体（可为 0 字节，空负载帧也必须被消费）
## 总帧长 = 4 + L

const HEADER_SIZE: int = 4
const MAX_FRAME: int = 65535


## 组帧：协议号 + protobuf 体 → 完整帧
static func pack(msg_type: int, body: PackedByteArray) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	var l: int = HEADER_SIZE + body.size()
	_push_u32(out, l)
	_push_u16(out, l)
	_push_u16(out, msg_type)
	out.append_array(body)
	return out


static func _push_u32(buf: PackedByteArray, v: int) -> void:
	buf.append(v & 0xFF)
	buf.append((v >> 8) & 0xFF)
	buf.append((v >> 16) & 0xFF)
	buf.append((v >> 24) & 0xFF)


static func _push_u16(buf: PackedByteArray, v: int) -> void:
	buf.append(v & 0xFF)
	buf.append((v >> 8) & 0xFF)


## 流式分帧器：不断喂入字节，吐出完整帧
class FrameDecoder extends RefCounted:
	var _buf: PackedByteArray = PackedByteArray()

	## 喂入数据并返回所有已完整的帧 [[协议号, 体], ...]
	func feed(data: PackedByteArray) -> Array:
		_buf.append_array(data)
		var frames: Array = []
		while true:
			if _buf.size() < 4:
				break
			var l: int = _read_u32(0)
			# l 为「帧头 + 体」长度，总帧长 = 4 + l
			if l < 4 or l > Framing.MAX_FRAME:
				# 长度非法：丢弃整个缓冲，避免后续全部解错
				push_error("Framing: 非法帧长 %d，清空接收缓冲" % l)
				_buf.clear()
				break
			var total: int = 4 + l
			if _buf.size() < total:
				break
			var msg_type: int = _read_u16(6)
			var body: PackedByteArray = _buf.slice(8, total)
			frames.append([msg_type, body])
			_buf = _buf.slice(total)
		return frames

	func clear() -> void:
		_buf.clear()

	func _read_u32(offset: int) -> int:
		return _buf[offset] | (_buf[offset + 1] << 8) | (_buf[offset + 2] << 16) | (_buf[offset + 3] << 24)

	func _read_u16(offset: int) -> int:
		return _buf[offset] | (_buf[offset + 1] << 8)
