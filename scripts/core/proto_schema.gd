class_name ProtoSchema
extends RefCounted
## 协议字段表
## 只描述「协议号 → 字段号 → 字段类型」，供 ProtoCodec 通用编解码。
## 类型取值：i32/u32/i64/u64/bool/enum（变长整数）、str/bytes/msg（长度定界）
## 字段定义：{ "n": 字段名, "t": 类型, "r": 可选，repeated, "s": 可选，msg 的子消息名 }

## 子消息字段表（作为 msg 类型的 schema）
const SUB: Dictionary = {
	"RoomInfo": {
		1: {"n": "room_id", "t": "i32"},
		2: {"n": "room_name", "t": "str"},
		3: {"n": "max_player", "t": "i32"},
		4: {"n": "now_player", "t": "i32"},
		5: {"n": "role_strategy", "t": "enum"},
		6: {"n": "seat_mode", "t": "i32"},
		7: {"n": "role_range", "t": "i32"},
		8: {"n": "allow_guest", "t": "bool"},
		9: {"n": "has_password", "t": "bool"},
		10: {"n": "first_extension", "t": "bool"},
		11: {"n": "second_extension", "t": "bool"},
		12: {"n": "sp_mo_dao", "t": "bool"},
		13: {"n": "playing", "t": "bool"},
		14: {"n": "silence", "t": "bool"},
	},
	"SinglePlayerInfo": {
		1: {"n": "id", "t": "u32"},
		2: {"n": "team", "t": "u32"},
		3: {"n": "role_id", "t": "u32"},
		4: {"n": "hand_count", "t": "u32"},
		5: {"n": "heal_count", "t": "u32"},
		6: {"n": "ex_cards", "t": "u32", "r": true},
		7: {"n": "basic_cards", "t": "u32", "r": true},
		8: {"n": "gem", "t": "u32"},
		9: {"n": "crystal", "t": "u32"},
		10: {"n": "yellow_token", "t": "u32"},
		11: {"n": "blue_token", "t": "u32"},
		12: {"n": "covered_count", "t": "u32"},
		13: {"n": "is_knelt", "t": "bool"},
		14: {"n": "hands", "t": "u32", "r": true},
		15: {"n": "covereds", "t": "u32", "r": true},
		16: {"n": "max_hand", "t": "u32"},
		17: {"n": "nickname", "t": "str"},
		18: {"n": "ready", "t": "bool"},
		19: {"n": "delete_field", "t": "str", "r": true},
		20: {"n": "leader", "t": "u32"},
		21: {"n": "online", "t": "bool"},
		22: {"n": "third_token", "t": "u32"},
	},
	"Command": {
		1: {"n": "respond_id", "t": "u32"},
		2: {"n": "src_id", "t": "u32"},
		3: {"n": "dst_ids", "t": "u32", "r": true},
		4: {"n": "card_ids", "t": "u32", "r": true},
		5: {"n": "args", "t": "u32", "r": true},
		# 技能询问的可选项按钮文案（与 args 里紧随的选项值一一对应）
		6: {"n": "notes", "t": "str", "r": true},
	},
}

## 主协议表：协议号 → 字段表
const TABLE: Dictionary = {
	# ---------------- base.proto ----------------
	GConst.Msg.RegisterReq: {
		1: {"n": "user_id", "t": "str"},
		2: {"n": "user_password", "t": "str"},
		3: {"n": "nickname", "t": "str"},
		4: {"n": "mobile", "t": "str"},
		5: {"n": "email", "t": "str"},
	},
	GConst.Msg.RegisterRep: {
		1: {"n": "state", "t": "u32"},
	},
	GConst.Msg.LoginReq: {
		1: {"n": "as_guest", "t": "bool"},
		2: {"n": "user_id", "t": "str"},
		3: {"n": "user_password", "t": "str"},
		4: {"n": "version", "t": "i32"},
		5: {"n": "client_id", "t": "str"},
	},
	GConst.Msg.LoginRep: {
		1: {"n": "state", "t": "i32"},
		2: {"n": "nickname", "t": "str"},
	},
	GConst.Msg.LogoutReq: {},
	GConst.Msg.LogoutRep: {
		1: {"n": "args", "t": "u32", "r": true},
	},
	GConst.Msg.RoomListReq: {
		1: {"n": "role_strategy", "t": "enum"},
	},
	GConst.Msg.RoomListRep: {
		1: {"n": "rooms", "t": "msg", "r": true, "s": "RoomInfo"},
	},
	GConst.Msg.CreateRoomReq: {
		1: {"n": "room_name", "t": "str"},
		2: {"n": "max_player", "t": "i32"},
		3: {"n": "role_strategy", "t": "enum"},
		4: {"n": "first_extension", "t": "bool"},
		5: {"n": "second_extension", "t": "bool"},
		6: {"n": "sp_mo_dao", "t": "bool"},
		7: {"n": "seat_mode", "t": "i32"},
		8: {"n": "allow_guest", "t": "bool"},
		9: {"n": "password", "t": "str"},
		10: {"n": "silence", "t": "bool"},
	},
	GConst.Msg.EnterRoomReq: {
		1: {"n": "room_id", "t": "i32"},
		2: {"n": "password", "t": "str"},
	},
	GConst.Msg.EnterRoomRep: {},
	GConst.Msg.LeaveRoomReq: {},
	GConst.Msg.JoinTeamReq: {
		1: {"n": "team", "t": "enum"},
	},
	GConst.Msg.ReadyForGameReq: {
		1: {"n": "type", "t": "enum"},
	},
	GConst.Msg.SinglePlayer: {
		1: {"n": "id", "t": "u32"},
		2: {"n": "team", "t": "u32"},
		3: {"n": "role_id", "t": "u32"},
		4: {"n": "hand_count", "t": "u32"},
		5: {"n": "heal_count", "t": "u32"},
		6: {"n": "ex_cards", "t": "u32", "r": true},
		7: {"n": "basic_cards", "t": "u32", "r": true},
		8: {"n": "gem", "t": "u32"},
		9: {"n": "crystal", "t": "u32"},
		10: {"n": "yellow_token", "t": "u32"},
		11: {"n": "blue_token", "t": "u32"},
		12: {"n": "covered_count", "t": "u32"},
		13: {"n": "is_knelt", "t": "bool"},
		14: {"n": "hands", "t": "u32", "r": true},
		15: {"n": "covereds", "t": "u32", "r": true},
		16: {"n": "max_hand", "t": "u32"},
		17: {"n": "nickname", "t": "str"},
		18: {"n": "ready", "t": "bool"},
		19: {"n": "delete_field", "t": "str", "r": true},
		20: {"n": "leader", "t": "u32"},
		21: {"n": "online", "t": "bool"},
		22: {"n": "third_token", "t": "u32"},
	},
	GConst.Msg.Game: {
		1: {"n": "room_id", "t": "i32"},
		2: {"n": "player_id", "t": "i32"},
		3: {"n": "red_morale", "t": "u32"},
		4: {"n": "blue_morale", "t": "u32"},
		5: {"n": "red_gem", "t": "u32"},
		6: {"n": "blue_gem", "t": "u32"},
		7: {"n": "red_crystal", "t": "u32"},
		8: {"n": "blue_crystal", "t": "u32"},
		9: {"n": "red_grail", "t": "u32"},
		10: {"n": "blue_grail", "t": "u32"},
		11: {"n": "pile", "t": "u32"},
		12: {"n": "discard", "t": "u32"},
		13: {"n": "is_started", "t": "bool"},
		14: {"n": "player_infos", "t": "msg", "r": true, "s": "SinglePlayerInfo"},
		# 当前在等谁回复（-1 表示没有等待）、剩余毫秒、本次等待总时长（客户端画等待进度条）
		15: {"n": "wait_pid", "t": "i32"},
		16: {"n": "wait_ms", "t": "u32"},
		17: {"n": "wait_total_ms", "t": "u32"},
		# 房名与房间设定人数：房间准备室据此显示房名、并从一开始就把所有空座位摆出来
		18: {"n": "room_name", "t": "str"},
		19: {"n": "max_player", "t": "i32"},
	},
	GConst.Msg.Talk: {
		1: {"n": "txt", "t": "str"},
	},
	GConst.Msg.Gossip: {
		1: {"n": "type", "t": "enum"},
		2: {"n": "txt", "t": "str"},
		3: {"n": "id", "t": "u32"},
	},
	GConst.Msg.Error: {
		1: {"n": "id", "t": "i32"},
		2: {"n": "dst_id", "t": "i32"},
		3: {"n": "args", "t": "i32", "r": true},
	},
	GConst.Msg.HeartBeat: {},
	GConst.Msg.BecomeLeaderReq: {},
	GConst.Msg.BecomeLeaderRep: {
		1: {"n": "yes", "t": "bool"},
	},
	GConst.Msg.PollingReq: {
		1: {"n": "type", "t": "enum"},
	},
	GConst.Msg.PollingRep: {
		1: {"n": "option", "t": "u32"},
	},
	# ---------------- action_respond.proto ----------------
	GConst.Msg.RoleReq: {
		1: {"n": "id", "t": "u32"},
		2: {"n": "strategy", "t": "enum"},
		3: {"n": "role_ids", "t": "u32", "r": true},
		4: {"n": "args", "t": "i32", "r": true},
		5: {"n": "opration", "t": "u32"},
		# 6/7 是本地扩展（原协议没有）：选角倒计时，客户端据此画进度条
		6: {"n": "wait_ms", "t": "u32"},
		7: {"n": "wait_total_ms", "t": "u32"},
	},
	GConst.Msg.PickBan: {
		1: {"n": "strategy", "t": "u32"},
		2: {"n": "is_pick", "t": "bool"},
		3: {"n": "role_ids", "t": "u32", "r": true},
	},
	GConst.Msg.TurnBegin: {
		1: {"n": "id", "t": "u32"},
		2: {"n": "round", "t": "u32"},
	},
	GConst.Msg.Action: {
		1: {"n": "action_type", "t": "u32"},
		2: {"n": "action_id", "t": "u32"},
		3: {"n": "src_id", "t": "u32"},
		4: {"n": "dst_ids", "t": "u32", "r": true},
		5: {"n": "card_ids", "t": "u32", "r": true},
		6: {"n": "args", "t": "u32", "r": true},
	},
	GConst.Msg.Respond: {
		1: {"n": "respond_id", "t": "u32"},
		2: {"n": "src_id", "t": "u32"},
		3: {"n": "dst_ids", "t": "u32", "r": true},
		4: {"n": "card_ids", "t": "u32", "r": true},
		5: {"n": "args", "t": "u32", "r": true},
	},
	GConst.Msg.CmdReq: {
		1: {"n": "cmd_type", "t": "enum"},
		2: {"n": "commands", "t": "msg", "r": true, "s": "Command"},
	},
	GConst.Msg.ErrorInput: {
		1: {"n": "error_type", "t": "enum"},
		2: {"n": "commands", "t": "msg", "r": true, "s": "Command"},
	},
	GConst.Msg.Hit: {
		1: {"n": "cmd_id", "t": "u32"},
		2: {"n": "hit", "t": "u32"},
		3: {"n": "src_id", "t": "u32"},
		4: {"n": "dst_id", "t": "u32"},
	},
	GConst.Msg.Card: {
		1: {"n": "type", "t": "u32"},
		2: {"n": "src_id", "t": "u32"},
		3: {"n": "dst_id", "t": "u32"},
		4: {"n": "card_ids", "t": "u32", "r": true},
		5: {"n": "is_real", "t": "bool"},
	},
	GConst.Msg.Hurt: {
		1: {"n": "src_id", "t": "u32"},
		2: {"n": "dst_id", "t": "u32"},
		3: {"n": "hurt", "t": "u32"},
		4: {"n": "cause", "t": "u32"},
		5: {"n": "type", "t": "u32"},
	},
	GConst.Msg.Skill: {
		1: {"n": "skill_id", "t": "u32"},
		2: {"n": "src_id", "t": "u32"},
		3: {"n": "dst_ids", "t": "u32", "r": true},
	},
}


## 取某协议号的字段表
static func fields(msg_type: int) -> Dictionary:
	return TABLE.get(msg_type, {})


## 取子消息字段表
static func sub_fields(name: String) -> Dictionary:
	return SUB.get(name, {})
