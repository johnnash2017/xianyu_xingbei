class_name GConst
extends RefCounted
## 全局常量与枚举
## 对照 C++ 端：客户端 data/Common.h、服务端 DiceGameServer/GameGrailCommon.h、CardEntity.h

# ============================================================
# 协议号（base.proto MessageType / action_respond.proto MessageType2）
# ============================================================
enum Msg {
	RegisterReq = 1,
	RegisterRep = 2,
	LoginReq = 3,
	LoginRep = 4,
	LogoutReq = 5,
	LogoutRep = 6,
	RoomListReq = 7,
	RoomListRep = 8,
	CreateRoomReq = 9,
	EnterRoomReq = 10,
	EnterRoomRep = 11,
	LeaveRoomReq = 12,
	JoinTeamReq = 13,
	ReadyForGameReq = 14,
	SinglePlayer = 15,
	Game = 16,
	Talk = 17,
	Gossip = 18,
	Error = 19,
	HeartBeat = 20,
	BecomeLeaderReq = 21,
	BecomeLeaderRep = 22,
	PollingReq = 23,
	PollingRep = 24,
	# ---- action_respond.proto（101 起）----
	RoleReq = 101,
	PickBan = 102,
	Action = 103,
	Respond = 104,
	CmdReq = 106,
	ErrorInput = 107,
	Hit = 108,
	TurnBegin = 109,
	Card = 110,
	Hurt = 111,
	Skill = 112,
}

# ============================================================
# 选角策略 / 布座模式
# ============================================================
enum RoleStrategy {
	Random = 1,
	Strategy31 = 2,
	Any = 5,
	## 六选一：与 31 同一套候选流程，只是每人候选发 6 个（取自服务端不用的 RANK_SOLO 值）
	Strategy61 = 6,
	All = 9,
}

enum SeatMode {
	Random = 1,
	Combo2 = 2,
	Combo3 = 3,
	Interlace = 4,
	RbbRrb = 5,
}

# ============================================================
# 行动类型（action_respond.proto BasicActionType）
# ============================================================
enum ActionType {
	Attack = 1,
	Magic = 2,
	Special = 3,
	AttackSkill = 4,
	MagicSkill = 5,
	SpecialSkill = 6,
	Any = 7,
	AttackMagic = 8,
	Unactional = 9,
	None = 100000,
}

# ============================================================
# 响应类型（action_respond.proto BasicRespondType）
# ============================================================
enum RespondType {
	ReplyAttack = 10,
	Bullet = 11,
	Heal = 12,
	Discard = 13,
	Weaken = 14,
	AdditionalAction = 15,
	DiscardCover = 16,
	Role = 17,
	InsertBan = 18,
}

# 指令类型（CommandRequest / ErrorInput）
enum CmdType {
	Action = 1,
	Respond = 2,
}

# 卡牌消息类型
enum CardMsgType {
	Use = 1,
	Show = 2,
}

# 公告类型
enum GossipType {
	Talk = 1,
	Notice = 2,
}

# 队伍/阵营
const RED: int = 1
const BLUE: int = 0
const TEAM_NONE: int = -1
# 观战者（房间满员时的 playerId）
const GUEST: int = 9

# 伤害类型
enum HarmType {
	None = 0,
	Attack = 1,
	Magic = 2,
}

# 命中率
enum HitRate {
	Normal = 0,
	NoReattack = 1,
	NoMiss = 2,
}

# 应战选择
enum Reattack {
	Attack = 0,
	Block = 1,
	GiveUp = 2,
}

# 特殊行动
enum SpecialAction {
	Buy = 0,
	Synthesize = 1,
	Extract = 2,
}

## 技能询问时的选牌来源（ask_skill 的 card_source）
enum CardSource {
	Hand = 0,        # 只能选自己的手牌
	Cover = 1,       # 只能选自己的盖牌
	HandOrCover = 2, # 手牌或盖牌皆可（由角色的选项决定具体用哪种）
	BasicEffect = 3, # 只能选场上基础效果牌（如【封印破碎】把任意一张基础效果牌收入手中）
}

# ============================================================
# 错误码（GrailError）
# ============================================================
const GE_SUCCESS: int = 0
const GE_EMPTY_HANDLE: int = 3
const GE_CARD_NOT_ENOUGH: int = 5
const GE_HANDCARD_NOT_FOUND: int = 7
const GE_BASIC_EFFECT_ALREADY_EXISTS: int = 9
const GE_INVALID_TABLEID: int = 15
const GE_INVALID_PLAYERID: int = 16
const GE_INVALID_CARDID: int = 17
const GE_INVALID_ACTION: int = 19
const GE_INVALID_ARGUMENT: int = 22
const GE_PLAYER_FULL: int = 28
const GE_DISCONNECTED: int = 30
const GE_NOT_WELCOME: int = 31
const GE_WRONG_PASSWORD: int = 32
const GE_VIP_ONLY: int = 33

# ============================================================
# 伤害/效果来源（CAUSE 常用子集）
# ============================================================
const CAUSE_OVERLOAD: int = 1
const CAUSE_USE: int = 2
const CAUSE_ATTACK: int = 3
const CAUSE_POISON: int = 4
const CAUSE_MISSILE: int = 6

# ============================================================
# 卡牌元素 / 命格 / 卡名（CardEntity.h）
# ============================================================
enum CardElement {
	Wind = 1,
	Water = 2,
	Fire = 3,
	Earth = 4,
	Thunder = 5,
	Light = 6,
	Darkness = 7,
}

enum CardProperty {
	Blood = 1,
	Martial = 2,
	Phantom = 3,
	Cast = 4,
	Holy = 5,
}

enum CardName {
	Poison = 1,
	Weaken = 2,
	Shield = 3,
	Missile = 4,
	HolyLight = 5,
	WindSlash = 6,
	WaterSlash = 7,
	FireSlash = 8,
	EarthSlash = 9,
	ThunderSlash = 10,
	DarkSlash = 11,
	WuXingShuFu = 12,
	TongShengGongSi = 13,
	TiaoXin = 14,
	LingHunLianJie = 15,
	YongHengYueZhang = 16,
}

# 独有效果索引（Exclusive）
enum Exclusive {
	WuXiShuFu = 0,
	TiaoXin = 1,
	LingHunLianJie = 2,
	TongShengGongSi = 3,
	YongHengYueZhang = 4,
}

# ============================================================
# 规则常量（GameGrailCommon.h / PlayerEntity.cpp / GameGrail.cpp）
# ============================================================
const CARDSUM: int = 150          # 牌库总数
const MAX_PLAYER: int = 8         # 最大玩家数
const HAND_CARDS_MAX: int = 6     # 默认手牌上限
const CROSS_MAX: int = 2          # 默认治疗上限
const ENERGY_MAX: int = 3         # 默认个人能量上限
const TEAM_ENERGY_MAX: int = 5    # 团队 宝石+水晶 上限
const MORALE_DEFAULT: int = 15    # 士气上限（非 8 人局）
const MORALE_8P: int = 18         # 士气上限（8 人局）
const GRAIL_WIN: int = 5          # 星杯获胜数
const START_HAND: int = 4         # 开局每人手牌
const EXCLUSIVE_NUM: int = 5

# 服务器默认端口（DiceServerConfig.xml）
const DEFAULT_PORT: int = 11111
# 局域网发现广播端口（与服务器端口、多开槽位端口刻意错开）
const DISCOVERY_PORT: int = 11112
# 多开槽位占用端口基数（仅绑回环地址）
const SLOT_PORT_BASE: int = 11130
const MAX_SLOT: int = 8


# ============================================================
# 代码里要按号判断的跨角色技能（号 = 「技能表#N」的 N）
# 集中一处，避免同一个号在多个脚本里各写一份
# ============================================================
const 技能_风之封印: int = 401
const 技能_水之封印: int = 402
const 技能_火之封印: int = 403
const 技能_地之封印: int = 404
const 技能_雷之封印: int = 405
const 技能_天使之墙: int = 701
const 技能_迅捷赐福: int = 1601
const 技能_威力赐福: int = 1602


# ============================================================
# 技能名与分类（全部取自设计表「技能表」，技能号就是 技能表#N 的 N）
# ============================================================
static func skill_name(skill_id: int) -> String:
	var row: Array = 技能行(skill_id)
	if row.is_empty():
		return "技能%d" % skill_id
	return str(row[_技能列("技能名")]).strip_edges()


## 技能的分类标签（派系·类型，如「独有技·响应」）；技能表里查不到就返回空串
static func skill_tag(skill_id: int) -> String:
	var row: Array = 技能行(skill_id)
	if row.is_empty():
		return ""
	var 派系: String = str(row[_技能列("派系")]).strip_edges()
	# 表里普通技写的是「普通」，界面上补回「技」字，与独有技/专属技/必杀技一致
	if 派系 == "普通":
		派系 = "普通技"
	var 类型: String = str(row[_技能列("类型")]).strip_edges()
	if 派系 == "":
		return 类型
	if 类型 == "":
		return 派系
	return "%s·%s" % [派系, 类型]


## 技能表的 id 是名字型（如「技能#地之封印」）；脚本判断用的技能号另存在「脚本号」列，
## 下面两个函数负责两边互查：技能 id → 技能号、技能号 → 技能行。
static func 技能号(技能id: String) -> int:
	var row: Array = 数据表格.技能表.get(技能id.strip_edges(), [])
	if row.is_empty():
		return 0
	return int(row[_技能列("脚本号")])


## 技能号 → 技能表那一行（首次访问时按「脚本号」列建索引）；查不到返回空数组
static func 技能行(skill_id: int) -> Array:
	if _技能号到行.is_empty():
		for key: String in 数据表格.技能表.keys():
			var row: Array = 数据表格.技能表[key]
			var 号: int = int(row[_技能列("脚本号")])
			if 号 != 0:
				_技能号到行[号] = row
	return _技能号到行.get(skill_id, [])


## 技能号 → 技能行 的索引（懒建一次；技能表是启动时生成的静态数据，不会中途变）
static var _技能号到行: Dictionary = {}


static func _技能列(字段: String) -> int:
	return int(数据表格.表元数据["技能表"]["列索引"][字段])


## 日志/提示用的技能全称：「【独有技·响应】疾风技」；查不到分类就退回「【疾风技】」
static func skill_title(skill_id: int) -> String:
	var 标签: String = skill_tag(skill_id)
	if 标签 == "":
		return "【%s】" % skill_name(skill_id)
	return "【%s】%s" % [标签, skill_name(skill_id)]


## 元素字符串 → 枚举值
static func element_from_string(s: String) -> int:
	match s:
		"wind": return CardElement.Wind
		"water": return CardElement.Water
		"fire": return CardElement.Fire
		"earth": return CardElement.Earth
		"thunder": return CardElement.Thunder
		"light": return CardElement.Light
		"darkness": return CardElement.Darkness
	return 0


## 元素枚举值 → 中文字符串
static func element_to_chinese(e: int) -> String:
	match e:
		CardElement.Wind: return "风"
		CardElement.Water: return "水"
		CardElement.Fire: return "火"
		CardElement.Earth: return "地"
		CardElement.Thunder: return "雷"
		CardElement.Light: return "光"
		CardElement.Darkness: return "暗"
	return "?"


## 命格字符串 → 枚举值
static func property_from_string(s: String) -> int:
	match s:
		"血": return CardProperty.Blood
		"技": return CardProperty.Martial
		"幻": return CardProperty.Phantom
		"咏": return CardProperty.Cast
		"圣": return CardProperty.Holy
	return 0


## 卡名中文字符串 → 枚举值
static func card_name_from_string(s: String) -> int:
	match s:
		"中毒": return CardName.Poison
		"虚弱": return CardName.Weaken
		"圣盾": return CardName.Shield
		"魔弹": return CardName.Missile
		"圣光": return CardName.HolyLight
		"风神斩": return CardName.WindSlash
		"水涟斩": return CardName.WaterSlash
		"火焰斩": return CardName.FireSlash
		"地裂斩": return CardName.EarthSlash
		"雷光斩": return CardName.ThunderSlash
		"暗灭": return CardName.DarkSlash
		"五行束缚": return CardName.WuXingShuFu
		"同生共死": return CardName.TongShengGongSi
		"挑衅": return CardName.TiaoXin
		"灵魂链接": return CardName.LingHunLianJie
		"永恒乐章": return CardName.YongHengYueZhang
	return 0
