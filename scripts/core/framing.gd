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


## 组帧：协议号 + protobuf 体 → 完整帧。
## 体太大（帧头 + 体超过 2 字节长度字段能表示的范围）时返回空数组 —— 长度会被截断，
## 发出去对方必然解错帧并清空缓冲，宁可不发（调用方见空数组就跳过）。
static func pack(msg_type: int, body: PackedByteArray) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	var l: int = HEADER_SIZE + body.size()
	if l > MAX_FRAME:
		push_error("Framing: 帧过大（%d > %d），已丢弃：协议号 %d" % [l, MAX_FRAME, msg_type])
		return out
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
	## 单次喂数据里最多滑动搜索多少次帧头：设上限是防止病态输入（一大片垃圾字节）
	## 把逐字节切片的耗时拖成平方级，把主线程卡住
	const MAX_RESYNC_TRIES: int = 64

	var _buf: PackedByteArray = PackedByteArray()

	## 喂入数据并返回所有已完整的帧 [[协议号, 体], ...]
	func feed(data: PackedByteArray) -> Array:
		_buf.append_array(data)
		var frames: Array = []
		var 重同步次数: int = 0
		while true:
			if _buf.size() < 4:
				break
			var l: int = _read_u32(0)
			# l 为「帧头 + 体」长度，总帧长 = 4 + l
			if l < 4 or l > Framing.MAX_FRAME:
				# 长度非法：只把缓冲开头这 1 个字节丢掉、往前滑动重新找帧头，
				# 而不是整段清空 —— 缓冲里可能还跟着完好的帧，不能连它们一起扔
				# （已经解出来的帧早已放进 frames，不受影响）。
				if 重同步次数 >= MAX_RESYNC_TRIES:
					push_error("Framing: 非法帧长 %d，连续 %d 次都找不到帧头，清空接收缓冲" % [l, 重同步次数])
					_buf.clear()
					break
				重同步次数 += 1
				_buf = _buf.slice(1)
				continue
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
