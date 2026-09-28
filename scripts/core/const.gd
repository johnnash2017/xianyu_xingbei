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
	BP = 3,
	CM = 4,
	Any = 5,
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

# 轮询类型
enum PollingType {
	ForceWait = 1,
	LegalLeave = 2,
	Mvp = 3,
}

# 队伍/阵营
const RED: int = 1
const BLUE: int = 0
const TEAM_NONE: int = -1
# 观战者（房间满员时的 playerId）
const GUEST: int = 9
# 无目标玩家
const PLAYER_NONE_ID: int = 100000

# ============================================================
# 牌区（DECK）
# ============================================================
enum Deck {
	Pile = 1,
	Discard = 2,
	Hand = 4,
	BasicEffect = 5,
	Cover = 6,
}

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

# 角色选择操作（BP / CM）
enum BpOperation {
	Null = 1,
	Ban = 2,
	Pick = 3,
}

## 技能询问时的选牌来源（ask_skill 的 card_source）
enum CardSource {
	Hand = 0,        # 只能选自己的手牌
	Cover = 1,       # 只能选自己的盖牌
	HandOrCover = 2, # 手牌或盖牌皆可（由角色的选项决定具体用哪种）
}

enum CmOperation {
	Null = 1,
	RedBan = 2,
	RedInsertBan = 3,
	RedPick = 4,
	BlueBan = 5,
	BlueInsertBan = 6,
	BluePick = 7,
}

## CM「取消额外禁用」的哨兵角色 id（服务端按 chosen != 100 判定）
const CM_CANCEL_ROLE_ID: int = 100

# ============================================================
# 错误码（GrailError）
# ============================================================
const GE_SUCCESS: int = 0
const GE_TIMEOUT: int = 1
const GE_URGENT: int = 2
const GE_EMPTY_HANDLE: int = 3
const GE_DECK_OVERFLOW: int = 4
const GE_CARD_NOT_ENOUGH: int = 5
const GE_USERID_NOT_FOUND: int = 6
const GE_HANDCARD_NOT_FOUND: int = 7
const GE_BASIC_EFFECT_NOT_FOUND: int = 8
const GE_BASIC_EFFECT_ALREADY_EXISTS: int = 9
const GE_EXCLUSIVE_EFFECT_NOT_FOUND: int = 10
const GE_COVERCARD_NOT_FOUND: int = 11
const GE_MOVECARD_FAILED: int = 12
const GE_INCONSISTENT_STATE: int = 13
const GE_FATAL_ERROR: int = 14
const GE_INVALID_TABLEID: int = 15
const GE_INVALID_PLAYERID: int = 16
const GE_INVALID_CARDID: int = 17
const GE_INVALID_ROLEID: int = 18
const GE_INVALID_ACTION: int = 19
const GE_INVALID_STEP: int = 20
const GE_INVALID_EXCLUSIVE_EFFECT: int = 21
const GE_INVALID_ARGUMENT: int = 22
const GE_NO_STATE: int = 23
const GE_NO_CONTEXT: int = 24
const GE_NO_REPLY: int = 25
const GE_INTERRUPTED: int = 26
const GE_NOT_SUPPORTED: int = 27
const GE_PLAYER_FULL: int = 28
const GE_GUEST_FULL: int = 29
const GE_DISCONNECTED: int = 30
const GE_NOT_WELCOME: int = 31
const GE_WRONG_PASSWORD: int = 32
const GE_VIP_ONLY: int = 33

# ============================================================
# 伤害/效果来源（CAUSE 常用子集）
# ============================================================
const CAUSE_DEFAULT: int = 0
const CAUSE_OVERLOAD: int = 1
const CAUSE_USE: int = 2
const CAUSE_ATTACK: int = 3
const CAUSE_POISON: int = 4
const CAUSE_WEAKEN: int = 5
const CAUSE_MISSILE: int = 6
const CAUSE_BUY: int = 7
const CAUSE_SYNTHESIZE: int = 8

# ============================================================
# 卡牌类型 / 元素 / 命格 / 卡名（CardEntity.h）
# ============================================================
enum CardType {
	Attack = 1,
	Magic = 2,
}

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
const MAX_ROLES: int = 20
const HAND_CARDS_MAX: int = 6     # 默认手牌上限
const CROSS_MAX: int = 2          # 默认治疗上限
const ENERGY_MAX: int = 3         # 默认个人能量上限
const TEAM_ENERGY_MAX: int = 5    # 团队 宝石+水晶 上限
const MORALE_DEFAULT: int = 15    # 士气上限（非 8 人局）
const MORALE_8P: int = 18         # 士气上限（8 人局）
const GRAIL_WIN: int = 5          # 星杯获胜数
const START_HAND: int = 4         # 开局每人手牌
const EXCLUSIVE_NUM: int = 5
const COVER_CARDS_MAX_DEFAULT: int = 0  # 盖牌上限由角色决定

# 服务器默认端口（DiceServerConfig.xml）
const DEFAULT_PORT: int = 11111
# 局域网发现广播端口（与服务器端口、多开槽位端口刻意错开）
const DISCOVERY_PORT: int = 11112
# 多开槽位占用端口基数（仅绑回环地址）
const SLOT_PORT_BASE: int = 11130
const MAX_SLOT: int = 8
# 心跳
const HEARTBEAT_INTERVAL: float = 5.0


# ============================================================
# 技能名（CAUSE 子集；用于客户端显示技能按钮与询问文案）
# ============================================================
const SKILL_NAMES: Dictionary = {
	# 剑圣
	101: "疾风技", 102: "烈风技", 103: "连续技", 104: "圣剑", 105: "剑影",
	# 狂战士
	201: "血影狂刀", 202: "血腥咆哮", 203: "狂化", 204: "血影狂刀(已用)", 205: "撕裂",
	# 弓之女神
	301: "精准射击", 302: "闪光陷阱", 303: "狙击", 304: "闪电箭", 305: "贯穿射击",
	# 天使
	701: "天使之墙", 702: "天使祝福", 703: "风之洁净", 704: "天使羁绊", 705: "天使之歌", 706: "神之庇护",
	# 圣女
	601: "治疗术", 602: "治愈之光", 603: "冰霜祷言", 604: "怜悯", 605: "圣疗",
	# 圣枪
	1001: "辉耀", 1002: "惩戒", 1003: "圣光祈愈", 1004: "天枪", 1005: "地枪",
	1006: "神圣信仰", 1007: "圣击",
	# 贤者
	1701: "智慧法典", 1702: "魔道法典", 1703: "圣洁法典", 1704: "法术反弹",
	# 元素师
	1101: "风刃", 1102: "冰冻", 1103: "火球", 1104: "陨石", 1105: "雷击",
	1106: "元素点燃", 1107: "月光", 1108: "元素吸收",
	# 神官
	1501: "神圣启示", 1502: "神圣祈福", 1503: "水之神力", 1504: "圣使守护",
	1505: "神圣契约", 1506: "神圣领域",
	# 格斗家
	2001: "念气力场", 2002: "蓄力一击", 2003: "念弹", 2004: "百式幻龙拳",
	2005: "苍炎之魂", 2006: "斗神天驱",
	# 女武神
	2501: "神圣追击", 2502: "秩序之印", 2503: "和平行者", 2504: "军神威光", 2505: "英灵召唤",
	# 红莲骑士
	2801: "腥红圣约", 2802: "腥红信仰", 2803: "血腥祷言", 2806: "杀戮盛宴",
	2807: "热血沸腾", 2808: "戒骄戒躁", 2809: "腥红十字",
	# 血色剑灵
	3401: "血色荆棘", 3402: "赤色一闪", 3403: "血染蔷薇", 3404: "血气屏障", 3405: "血蔷薇庭院",
	# 封印师
	401: "风之封印", 402: "水之封印", 403: "火之封印", 404: "地之封印", 405: "雷之封印",
	406: "法术激荡", 407: "五系束缚", 408: "封印破碎",
	# 暗杀者
	501: "反噬", 502: "水影", 503: "潜行",
	# 魔导师 / sp魔导师
	801: "魔爆冲击", 802: "魔弹掌握", 803: "魔弹融合", 804: "毁灭风暴",
	805: "sp魔爆冲击", 806: "法力护盾",
	# 魔剑
	901: "修罗连斩", 902: "暗影凝聚", 903: "暗影之力", 904: "暗影抗拒", 905: "暗影流星", 906: "黑暗震颤",
	# 冒险家
	1201: "欺诈", 1202: "冒险者天堂", 1203: "偷天换日", 1204: "特殊加工",
	# 死灵法师
	1301: "不朽", 1302: "圣渎", 1303: "瘟疫", 1304: "死亡之触", 1305: "墓碑陨落",
	# 仲裁者
	1401: "仪式中断", 1402: "仲裁仪式", 1403: "末日审判", 1404: "审判浪潮", 1405: "判决天平",
	# 祈祷师
	1601: "迅捷赐福", 1602: "威力赐福", 1603: "祈祷", 1604: "光辉信仰", 1605: "漆黑信仰", 1606: "法力潮汐",
	# 灵符师
	1801: "灵符-风行", 1802: "灵符-雷鸣", 1803: "念咒", 1804: "百鬼夜行", 1805: "灵力崩解",
	# 剑帝
	1901: "剑魂守护", 1902: "佯攻", 1903: "剑气斩", 1904: "天使与恶魔", 1905: "天使之魂",
	1906: "恶魔之魂", 1907: "不屈意志",
	# 勇者
	2101: "挑衅", 2102: "禁断之力", 2103: "怒吼", 2104: "明镜止水", 2105: "死斗", 2106: "精疲力竭",
	# 灵魂术士
	2201: "灵魂震爆", 2202: "灵魂赐予", 2203: "灵魂增幅", 2204: "灵魂吞噬", 2205: "灵魂召还",
	2206: "灵魂转换", 2207: "灵魂镜像", 2208: "灵魂链接", 2209: "灵魂链接-反应",
	# 巫女
	2301: "血之悲鸣", 2302: "同生共死", 2303: "血之哀伤", 2304: "逆流", 2306: "流血",
	# 蝶舞者
	2401: "生命之火", 2402: "舞动", 2403: "毒粉", 2404: "朝圣", 2405: "镜花水月",
	2406: "凋零", 2407: "蛹化", 2408: "倒逆之蝶",
	# 魔弓
	2601: "魔贯冲击", 2602: "雷光散射", 2603: "多重射击", 2604: "充能", 2605: "魔眼", 2606: "充能/魔眼",
	# 英灵人形
	2701: "战纹掌控", 2702: "怒火压制", 2703: "战纹碎击", 2704: "魔纹融合", 2705: "符文改造", 2706: "双重回响",
	# 魔枪
	2901: "暗之解放", 2902: "幻影星辰", 2903: "黑暗束缚", 2904: "暗之障壁", 2905: "充盈", 2906: "漆黑之枪",
	# 苍炎魔女
	3001: "苍炎法典", 3002: "天火断空", 3003: "魔女之怒", 3004: "替身玩偶", 3005: "永生银时计",
	3006: "痛苦链接", 3007: "魔能翻转",
	# 吟游诗人
	3101: "沉沦协奏曲", 3102: "不谐和弦", 3103: "歌咏天赋", 3104: "暴风前奏曲",
	3105: "激昂狂想曲", 3106: "胜利交响诗", 3107: "希望赋格曲",
	# 精灵射手
	3201: "元素射击", 3202: "动物伙伴", 3203: "精灵秘仪",
	# 阴阳师
	3301: "式神咒束", 3302: "黑暗祭礼", 3303: "式神降临", 3304: "生命结界", 3305: "式神转换", 3306: "阴阳转换",
	# 月之女神
	3501: "新月庇护", 3502: "暗月诅咒", 3503: "美杜莎之眼", 3504: "月之轮回", 3505: "月读",
	3506: "暗月斩", 3507: "苍白之月",
	# 兽灵武士
	3601: "武者残心", 3602: "一击无念", 3603: "兽魂意念", 3604: "兽魂警戒", 3605: "兽返",
	3606: "逆返居合斩", 3607: "御魂流居合式",
	# 圣弓
	3701: "天之弓", 3702: "圣邪巨胞", 3703: "圣煌魔矢", 3704: "圣光爆裂", 3705: "圣流星弹",
	3706: "辉光炮", 3707: "自动天冲",
}


static func skill_name(skill_id: int) -> String:
	return SKILL_NAMES.get(skill_id, "技能%d" % skill_id)


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
	return 0
