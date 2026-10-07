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
		# 治疗上限（角色被动会改，如神官【圣使守护】+4）：客户端要按它画治疗格的上限
		23: {"n": "max_heal", "t": "u32"},
		# 能量上限（角色被动会改，如贤者 +1）：客户端判「星石已满 / 还有空位」要用它
		24: {"n": "max_energy", "t": "u32"},
		# 与 ex_cards 一一对应：每张专属牌是**谁放的**（-1＝没记）。
		# 【挑衅】靠它知道「被挑衅的人只能主动攻击哪个玩家」（多勇者时也锁死放牌者本人）
		25: {"n": "ex_from", "t": "i32", "r": true},
	},
	"Command": {
		1: {"n": "respond_id", "t": "u32"},
		2: {"n": "src_id", "t": "u32"},
		3: {"n": "dst_ids", "t": "u32", "r": true},
		4: {"n": "card_ids", "t": "u32", "r": true},
		5: {"n": "args", "t": "u32", "r": true},
		# 技能询问的可选项按钮文案（与 args 里紧随的选项值一一对应）
		6: {"n": "notes", "t": "str", "r": true},
		# 点选上限（如【欺诈】弃 2~3 张；0 表示就按最少张数选）
		7: {"n": "card_max", "t": "u32"},
		# 技能参数选项：每项渲染成一个按钮（如【冒险者天堂】选要用哪些星石）
		8: {"n": "arg_choices", "t": "msg", "r": true, "s": "ArgChoice"},
		# 选牌的系别规则（""＝不限；"same"＝必须同系，如【法术反弹】；"diff"＝必须互异系，如【魔道法典】）
		9: {"n": "card_rule", "t": "str"},
		# 这次询问能不能「取消」（省略＝可以；false 表示强制，界面把「取消」置灰，
		# 如神官【水之神力】第二次问「交哪张牌给队友」——不选也会随机交一张）
		10: {"n": "can_cancel", "t": "bool"},
		# 询问「别人」（不是发起者自己）时的指令条文案，如【天使祝福】的「请选择 1 张手牌交给 天使[x]」
		11: {"n": "ask_text", "t": "str"},
		# 这条应答是不是「是否发动某技能」的技能询问（服务端 ask_skill 下发；其余应战/弃牌等通用应答不带）
		12: {"n": "is_skill", "t": "bool"},
		# 目标数上限随已选牌数变化的减数（0＝不适用）：上限 = 已选牌数 - 该值，至少 1 名
		# （如贤者【圣洁法典】＝弃牌数 - 2）。只有静态 target_max 会在玩家取消选牌后漏判
		13: {"n": "target_max_from_cards", "t": "u32"},
		# 逐张选牌的条件（0＝不要求）：第 1 张必须带这个技能
		# （如元素师独有法术：第 1 张是发动牌，第 2 张才是加伤的该系牌）
		14: {"n": "card_slot_skill", "t": "u32"},
		# 第 2 张必须是这个系的牌（技能原文「额外弃 1 张 X 系牌【展示】」）
		15: {"n": "card_slot_element", "t": "u32"},
		# 这条行动询问是不是「额外行动」阶段（客户端据此改提示文案）
		16: {"n": "is_extra", "t": "bool"},
		# 技能按钮自带的发动提示里那句「选牌」说明（如【充能】的代价是「弃到 4 张牌」）：
		# 非空时覆盖客户端默认的「从手牌中选 N 张」
		17: {"n": "card_prompt", "t": "str"},
		# 本阶段禁止特殊行动（发动过「启动」技能后：客户端据此把「特殊行动」按钮收掉）
		18: {"n": "no_special", "t": "bool"},
		# 手牌 + 盖牌混选时，要求其中几张必须是盖牌（如【魔贯冲击】：1 张攻击牌 + 1 张火系【充能】）
		19: {"n": "cover_need", "t": "u32"},
		# 带选项的询问里，每个选项各自对应的「技能号」（与 args 里的选项值一一对应，0＝这一项不是技能）：
		# >0 表示该选项本身就是个技能（如【蓄力一击】/【气绝崩击】/【风怒追击】），
		# 客户端鼠标指向这个选项按钮时按它弹技能说明（同普通技能按钮）
		20: {"n": "option_skill_ids", "t": "u32", "r": true},
		# 带选项的询问里，每个选项各自要弃几张牌（与 args 里的选项值一一对应，0＝这一项不用弃牌）：
		# 如英灵人形【魔纹融合】的二选一 —— 选【魔纹融合】要弃 ≥2 张异系牌、选【怒火压制】一张都不用，
		# 两件事在同一次询问里完成（客户端选中该项后才放出手牌，见 _应用选项目标数）
		21: {"n": "option_need_cards", "t": "u32", "r": true},
		# 客户端现算头像提示时要用到的基准数值（0＝没有）：
		# 如英灵人形【战纹碎击】—— 提示要把「本次攻击原本的伤害」和「弃牌加伤」合起来显示，
		# 原伤害只有服务端算得出来；【双重回响】也用它下发要复制的那份伤害（与 3 取小后的值），
		# 随这条询问下发（见 _战纹碎击头像提示 / _双重回响头像提示）
		22: {"n": "preview_base", "t": "u32"},
	},
	# 技能参数选项的一项（battle_engine 组装命令时放进 arg_choices）
	"ArgChoice": {
		1: {"n": "text", "t": "str"},
		2: {"n": "args", "t": "u32", "r": true},
		3: {"n": "need_card", "t": "u32"},
		4: {"n": "need_target", "t": "u32"},
		5: {"n": "targets", "t": "u32", "r": true},
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
		# 正在等谁做什么（如「等待应战响应」）：客户端写在被等玩家的头像上
		20: {"n": "wait_text", "t": "str"},
	},
	GConst.Msg.Talk: {
		1: {"n": "txt", "t": "str"},
	},
	GConst.Msg.Gossip: {
		1: {"n": "type", "t": "enum"},
		2: {"n": "txt", "t": "str"},
		3: {"n": "id", "t": "u32"},
		# 附带的数量：治疗类＝治疗点数（客户端据此冒几个「+」）、弃牌类＝弃牌张数（据此播弃牌特效）；
		# 其余类别不带，按 0 处理
		4: {"n": "num", "t": "i32"},
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
		# 分步应答标记（如【剑气斩】先在弹窗选好剑气数）：只报「这一步选好的值」，不算本次询问的最终回复
		6: {"n": "partial", "t": "bool"},
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
		# 这次出牌「视为」哪张牌用（0 = 就是 card_ids 里那张）。
		# 例：地/火牌当【魔弹】打出去（【魔弹融合】803、响应魔弹继续传递）时值为【魔弹】牌号：
		# 出牌音效/特效、以及后续任何「这次是不是魔弹」的判断都按它走；
		# card_ids 仍是真正打出的那张牌（要展示、也确实进了弃牌堆）。
		6: {"n": "as_card_id", "t": "u32"},
		# 「给牌」（CardMsgType.Give）专用：交了几张。不公开牌面，只给客户端播动效用
		# （交几张就飞几张卡背）；其他 Card 消息不填
		7: {"n": "count", "t": "u32"},
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
	# 测试用（本项目本地扩展）：按测试按键做的操作，kind 见 GConst.DebugKey
	GConst.Msg.DebugReq: {
		1: {"n": "kind", "t": "u32"},
	},
}


## 取某协议号的字段表
static func fields(msg_type: int) -> Dictionary:
	return TABLE.get(msg_type, {})


## 取子消息字段表
static func sub_fields(name: String) -> Dictionary:
	return SUB.get(name, {})
