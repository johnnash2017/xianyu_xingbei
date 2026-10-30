extends 自检用例
## 用例 11：应战询问里的新字段必须真的过网络协议。
## 界面 / 引擎用例直接看字典，绕过了 ProtoCodec，字段没进 schema 也发现不了；
## 这里专门做一次 Command 子消息的编码 → 解码往返。

func _init() -> void:
	名称 = "应战询问字段过协议"


func 跑() -> void:
	await 等帧()
	var 原始: Dictionary = {
		"respond_id": GConst.技能_阴阳转换, "src_id": 1,
		"args": [0, 0, GConst.CardSource.Hand, 3, 1, 2, 3],
		"preview_base": 45, "preview_ids": [2],
		"can_light": false, "preview_damage": 2,
		# 行动结束响应预选第一项：必须过协议，否则客户端收不到、选项仍要手动点一下
		"default_option": 0,
		# 行动结束响应不摆「被问技能」本体：必须过协议，否则会和同名选项重名
		"no_parent": true,
	}
	var 编码: PackedByteArray = ProtoCodec.encode_named("Command", 原始)
	var 解码: Dictionary = ProtoCodec.decode_named("Command", 编码)
	检(not bool(解码.get("can_light", true)), "can_light=false 没有过 Command 协议")
	检(int(解码.get("preview_damage", -1)) == 2, "preview_damage 没有过 Command 协议")
	检(int(解码.get("default_option", -1)) == 0, "default_option 没有过 Command 协议")
	检(bool(解码.get("no_parent", false)), "no_parent 没有过 Command 协议")
