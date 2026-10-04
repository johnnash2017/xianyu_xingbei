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
	# ---- 测试用（本项目本地扩展，参考工程协议里没有这一段）----
	DebugReq = 113,
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
# 测试用：战斗界面里的测试按键（取值与按键一致）
# ============================================================
enum DebugKey {
	SkipTurn = 0,     # 跳过当前正在行动玩家的回合
	Clear = 1,        # 清空自己的手牌（全部进弃牌堆）
	SkillCards = 2,   # 技能牌：每个技能随机抽一张给自己（卡表里技能属于该角色的牌）
	Cards = 3,        # 发测试牌：3 张随机同系攻击牌（斩）+ 3 张随机异系法术牌
	ShortenWait = 4,  # 把当前正在进行的询问倒计时压到 1 秒
	MoraleFull = 5,   # 双方士气拉到 99
	MaxTokens = 6,    # 全员标识物（指示物）加到满
	RandomEnergy = 7, # 随机填充星石：清空双方战绩区，再各按战绩区上限逐颗随机填成宝石 / 水晶
	CrossClear = 8,   # 全员治疗清零
	HealEnergy = 9,   # 全员治疗拉满、全员能量（宝石）补满
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

## 本行动阶段是否放行某个「动作种类」（对照服务端 PlayerEntity::v_allow_action 的 allow 判定）：
## Any 放行攻击/法术/特殊；AttackMagic 放行攻击与法术；其余只放行完全相同的种类。
## 技能类（AttackSkill / MagicSkill / SpecialSkill）先归入对应的基础种类。
## 服务端行动总闸 base_v_allow_action 与客户端「手牌、技能按钮能不能点」共用这一处规则，
## 免得界面上亮着、点下去却被服务端拒。
static func 放行动作(动作种类: int, 允许: int) -> bool:
	var 类别: int = 动作种类
	match 类别:
		ActionType.AttackSkill:
			类别 = ActionType.Attack
		ActionType.MagicSkill:
			类别 = ActionType.Magic
		ActionType.SpecialSkill:
			类别 = ActionType.Special
	match 允许:
		ActionType.Any:
			return 类别 == ActionType.Attack or 类别 == ActionType.Magic or 类别 == ActionType.Special
		ActionType.AttackMagic:
			return 类别 == ActionType.Attack or 类别 == ActionType.Magic
		_:
			return 类别 == 允许

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
	Give = 3,      # 交给别人：不公开牌面，只用来播一个「牌从甲飘到乙」的给牌动效
}

# 公告类型
enum GossipType {
	Talk = 1,      # 玩家发言（进日志 + 聊天区）
	Notice = 2,    # 系统公告（默认中性色）
	Combat = 3,    # 攻击 / 命中 / 伤害
	Heal = 4,      # 治疗
	Discard = 5,   # 弃牌 / 交牌 / 资源消耗
	Skill = 6,     # 技能发动
	Turn = 7,      # 回合 / 阶段
	Token = 8,     # 指示物变化
	Warn = 9,      # 超时 / 掉线 / 无效操作
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
	# 先按 Hand 选手牌作发动牌，再选一张场上基础效果牌，其 id 作为 args[0] 回传
	# （如天使【风之洁净】：选好风系牌与目标后按「确定」，由客户端弹出目标身上的基础效果供选）
	HandAndBasicEffect = 4,
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
# 区域变动方向（对照服务端 CHANGE，用于 p_cover_change 等钩子）
# ============================================================
const CHANGE_ADD: int = 0
const CHANGE_REMOVE: int = 1

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
## 【魔弹】的初始伤害（每被传递一次 +1）——服务端结算与客户端「准备打出」的头像提示共用这一处
const 魔弹基础伤害: int = 2
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
## 封印师【封印破碎】也走「技能指示器」：基础效果选择窗里的动词显示成「拿走」（收入自己手中）
const 技能_封印破碎: int = 408
## 死灵法师【死亡之触】也走「技能指示器」：点技能先弹窗选「消耗多少治疗」，选完再选牌 / 选目标
const 技能_死亡之触: int = 1304
## 死灵法师【瘟疫】/【剧毒新星】也走「技能指示器」：进场自动选中「除自己外所有人」并锁死，头像显示伤害
const 技能_瘟疫: int = 1303
const 技能_剧毒新星: int = 1305
const 技能_天使之墙: int = 701
## 技能指示器（见下方的 技能指示器 表）里的技能号
const 技能_天使祝福: int = 702
const 技能_水之神力: int = 1503
const 技能_魔爆冲击: int = 801
const 技能_毁灭风暴: int = 804
## 神箭手【闪光陷阱】也走「技能指示器」：把即将造成的法术伤害写在头像上
const 技能_闪光陷阱: int = 302
## 神箭手【狙击】也走「技能指示器」：选择目标时在其头像上显示「补到 5 张」
const 技能_狙击: int = 303
## 格斗【念弹】：客户端现算指示器——目标 1 点法术伤害；目标无治疗时自身另受「斗气数」点法术伤害
const 技能_念弹: int = 2003
## 剑帝【剑气斩】也走「技能指示器」：先弹窗选移除几点【剑气】，再点一名本次攻击目标以外的角色，
## 被点头像显示「X 法术伤害」（X＝所选剑气数）
const 技能_剑气斩: int = 1903
const 技能_治疗术: int = 601
const 技能_治愈之光: int = 602
const 技能_冰霜祷言: int = 603
const 技能_圣疗: int = 605
const 技能_神圣契约: int = 1505
const 技能_神圣领域: int = 1506
const 技能_迅捷赐福: int = 1601
const 技能_威力赐福: int = 1602
## 祈祷师【光辉信仰】/【黑暗诅咒】也走「技能指示器」：把即将产生的治疗 / 法术伤害写在头像上
const 技能_光辉信仰: int = 1604
const 技能_黑暗诅咒: int = 1605
## 红莲骑士【血腥祷言】也走「点头像分配治疗」：把自身治疗分给队友
const 技能_血腥祷言: int = 2803
## 圣枪骑士【惩戒】也走「点头像」：选一名有治疗的角色，他 -1 治疗、你 +1 治疗
const 技能_惩戒: int = 1002
## 圣枪骑士【辉耀】也走「技能指示器」：不用点头像，进场即全场各 +1 治疗
const 技能_辉耀: int = 1001
## 圣枪骑士【圣光祈愈】也走「技能指示器」：不用点头像，进场即自己 +2 治疗
const 技能_圣光祈愈: int = 1003
## 魔导师 / 特殊魔导【魔弹融合】：地 / 火牌当【魔弹】打出去，用指示器显示落点将受到的伤害
const 技能_魔弹融合: int = 803
## 贤者【圣洁法典】：选中的每名角色各 +2 治疗、自己受（弃牌数 - 1）法术伤害，用指示器写在头像上
const 技能_圣洁法典: int = 1703
## 贤者【魔道法典】/【法术反弹】：也用指示器把伤害写在头像上
const 技能_魔道法典: int = 1702
const 技能_法术反弹: int = 1704
## 元素师：陨石 / 风刃 / 火球 / 雷击 / 冰冻 / 元素点燃 / 月光，都用指示器把伤害写在头像上
const 技能_风刃: int = 1101
const 技能_冰冻: int = 1102
const 技能_火球: int = 1103
const 技能_陨石: int = 1104
const 技能_雷击: int = 1105
const 技能_元素点燃: int = 1106
const 技能_月光: int = 1107
## 魔剑士【暗影流星】（905）：仅[暗影形态]下弃 2 张法术牌，对目标造成 2 点法术伤害
const 技能_暗影流星: int = 905
## 灵符师：灵符－风行 / 灵符－雷鸣 都用指示器把效果写在已选目标头像上
const 技能_灵符风行: int = 1801
const 技能_灵符雷鸣: int = 1802
## 灵符师【百鬼夜行】：先用居中弹窗选效果，再选牌 / 选目标，按「确定」发动
const 技能_百鬼夜行: int = 1804


# ============================================================
# 技能指示器：「在玩家头像上做文章」的技能的统一配置（客户端与服务端共用一份）。
# 一个技能可以只配「展示键」，也可以再配「交互键」—— 配了「每次」就变成「点头像分配」型。
#
# 展示键（不接管选取与提交，照常「点目标 → 确定」；选中后把提示画到每名已选目标头像正中）：
#   文案     —— 头像提示模板，%d 是该目标的数值
#   每目标   —— 每名已选目标各一个固定数值（如【魔爆冲击】每名对手 2 点法术伤害）
#   总数     —— 一共要分多少（按选中人数平均分，如 2 张分给 2 人＝每人 1 张）；配了「每目标」就不用它
#   每牌     —— 数值随「已选牌数」变化（如【魔道法典】伤害＝弃牌数 - 1 → 每牌 1、偏移 -1）；
#               配了它就不用「每目标 / 总数」。数值算出来 ≤ 0 时该头像不画
#   每能量   —— 数值随「自己当前星石总数（宝石 + 水晶）」变化（如元素师【月光】伤害＝当前能量）
#   偏移     —— 配合「每牌 / 每能量」的固定加减（公式：倍率 × 数量 + 偏移）
#   分目标   —— 按「已选目标的顺序」逐人配一句，形如 [{"文案": "…", "每牌": 1}, {"文案": "…", "每目标": 1}]；
#               如【冰冻】第 1 个目标吃伤害、第 2 个目标 +1 治疗。配了它就不用顶层「文案」
#   自身     —— 同一技能对自己也有数值时另写一句，形如
#               {"文案": "%d 法术伤害", "每牌": 1, "偏移": -1}（键与上面同）；自己同时是目标就并成两行
#   反选     —— true＝提示画在「没被选中的」角色身上（如【百鬼夜行】展示火系妖力：选中的 2 人是
#               被保下来的，其余所有角色挨伤害）；不配就是常规 —— 画在选中的目标身上
#
# 交互键（配了「每次」即为「点头像分配」型：接管目标选取与提交，args 是各目标点数 / 用法）：
#   每次     —— 点一次给该目标加几点治疗
#   上限     —— 要分配的总点数；<= 0 表示「按自己当前的治疗量」（神官【神圣契约】转多少自己定）
#   可重复   —— 能否把多点分给同一个人
#   可多目标 —— 能否分给多个人（false 时只能在一个人身上分配，点了别人就整份挪过去）
#   需分满   —— 是否必须分满「上限」才能确定（false 表示至少分一次就能确定，如神圣契约想转几点都行）
#   仅队友   —— 目标是否只能选队友（同队，且不含自己）
#   突破上限 —— 加治疗时是否无视目标的治疗上限（服务端结算读它）
#   突破封顶 —— 突破上限时的封顶值（<= 0 表示不额外封顶）
#   阵营效果 —— 提示随「目标算我方还是敌方」变化（如【神圣领域】选队友加治疗、选敌人打伤害），形如
#               {"队友": {"目标治疗": 1, "自身治疗": 2}, "敌人": {"目标伤害": 2, "自身治疗": -1}}：
#               「目标治疗 / 目标伤害」画在目标头像上，「自身治疗」画在自己头像上（可正可负）
#   自动选   —— 不用点头像，进入技能就自动把谁选中并画「N 治疗」：
#               "全体"＝在场所有人（如【辉耀】全场 +1 治疗）、"自己"＝只有自己（如【圣光祈愈】）；
#               配了它就不能再点头像改选
#
# 先选效果键（技能询问先弹居中窗选效果，选完再选牌 / 选目标，按「确定」提交）：
#   先弹选项 —— true＝进入本次询问先弹出居中的效果选择窗（选项来自服务端下发的选项与文案），
#               窗里只记下选了哪一项、不提交；关窗后再选牌 / 选目标，按「确定」才把该项 args 一起上交。
#               （如灵符师【百鬼夜行】：先选「展示火系妖力 / 不展示」，再选妖力与目标）
#   选项目标数 —— 各效果值 → 该效果要选几名目标，形如 {1: 2, 0: 1}
#               （如【百鬼夜行】展示火系妖力指定 2 人、不展示只指定 1 人）；不配就沿用服务端给的目标数
#   选项提示 —— 各效果值 → 该效果各自的头像提示配置，形如
#               {1: {"反选": true, "文案": "%d 法术伤害", "每目标": 1}, 0: {"文案": "%d 法术伤害", "每目标": 1}}；
#               键就是上面那套展示键（含「反选」）。没选效果之前不画提示
#   选项牌系 —— 各效果值 → 该效果要求发动牌是这一系，形如 {1: GConst.CardElement.Fire}
#               （如【百鬼夜行】展示火系妖力：必须真拿火系【妖力】发动）。
#               选了该效果后，其它系的牌整片置灰 —— 免得选错牌提交、服务端静默不生效
#
# 通用键：
#   提示     —— 指令条上的说明文案（仅客户端用）
# ============================================================
const 技能指示器: Dictionary = {
	技能_治疗术: {"每次": 2, "上限": 2, "可重复": false, "可多目标": false, "需分满": true,
		"仅队友": false, "突破上限": false, "突破封顶": 0,
		"提示": "点头像选择 1 名角色 +2 治疗，选好后点「确定」"},
	技能_治愈之光: {"每次": 1, "上限": 3, "可重复": false, "可多目标": true, "需分满": true,
		"仅队友": false, "突破上限": false, "突破封顶": 0,
		"提示": "点头像选择 3 名不同的角色各 +1 治疗（不可重复），选满后点「确定」"},
	技能_冰霜祷言: {"每次": 1, "上限": 1, "可重复": false, "可多目标": false, "需分满": true,
		"仅队友": false, "突破上限": false, "突破封顶": 0,
		"提示": "点头像选择 1 名角色 +1 治疗，选好后点「确定」"},
	技能_圣疗: {"每次": 1, "上限": 3, "可重复": true, "可多目标": true, "需分满": true,
		"仅队友": false, "突破上限": false, "突破封顶": 0,
		"提示": "点头像分配 3 点治疗（同一人可点多次；点第 4 次重新分配），选满后点「确定」"},
	技能_神圣契约: {"每次": 1, "上限": 0, "可重复": true, "可多目标": true, "需分满": false,
		"仅队友": true, "突破上限": true, "突破封顶": 4,
		"提示": "点头像把治疗转移给队友（只能选队友、不含自己，可分给多人；无视其治疗上限、但最高到 4 点），转几点由你点几次决定，点「确定」发动"},
	技能_神圣领域: {"每次": 1, "上限": 1, "可重复": false, "可多目标": false, "需分满": true,
		"仅队友": false, "突破上限": false, "突破封顶": 0,
		"提示": "先选好要弃的牌，再点头像选目标，选好后点「确定」：选队友（含自己）→ 你 +2 治疗、他 +1 治疗；选敌人 → 你 -1 治疗、他受 2 点法术伤害（治疗不足时点不了敌人）",
		"阵营效果": {
			"队友": {"目标治疗": 1, "自身治疗": 2},
			"敌人": {"目标伤害": 2, "自身治疗": -1},
		}},
	# 红莲骑士【血腥祷言】：把自身当前治疗转移给队友（只能选队友、不含自己）。
	# 上限 0＝按自己当前的治疗量，点几次＝转几点（每点扣 1 自身治疗、给对方 +1），
	# 总量受自身治疗量限制；回包的 args 与 dst_ids 平行，即各目标的点数（取消回 args=[0]）。
	技能_血腥祷言: {"每次": 1, "上限": 0, "可重复": true, "可多目标": true, "需分满": false,
		"仅队友": true, "突破上限": false, "突破封顶": 0,
		"提示": "点头像把治疗分给队友（只能选队友、不含自己；同一人可点多次、也可分给多人），分几点由你点几次决定，点「确定」发动"},
	# 圣枪骑士【惩戒】：另需弃 1 张法术牌，选一名有治疗的其他角色，把 1 点治疗转移给你。
	# 队友与敌人是同一份效果（目标 -1、自己 +1），所以两个分支写成一样；走「阵营效果」这条只是为了
	# 能分别把「目标 -1」画在目标头像、「自己 +1」画在自己头像（普通分配路径只会画正数治疗）
	技能_惩戒: {"每次": 1, "上限": 1, "可重复": false, "可多目标": false, "需分满": true,
		"仅队友": false, "突破上限": false, "突破封顶": 0,
		"提示": "先选好要弃的法术牌，再点一名有治疗的角色：他 -1 治疗、你 +1 治疗，选好后点「确定」",
		"阵营效果": {
			"队友": {"目标治疗": -1, "自身治疗": 1},
			"敌人": {"目标治疗": -1, "自身治疗": 1},
		}},
	# 圣枪骑士【辉耀】：另需弃 1 张水系牌，全场所有人各 +1 治疗。不用点头像（自动选全体）
	技能_辉耀: {"每次": 1, "上限": 1, "可重复": false, "可多目标": true, "需分满": true,
		"仅队友": false, "突破上限": false, "突破封顶": 0, "自动选": "全体",
		"提示": "先选好要弃的水系牌：所有人各 +1 治疗，选好后点「确定」"},
	# 圣枪骑士【圣光祈愈】：耗 1 宝石，自己 +2 治疗（无视上限、最高到 5），另 +1 攻击行动。
	# 只作用于自己，故自动选「自己」
	技能_圣光祈愈: {"每次": 2, "上限": 2, "可重复": false, "可多目标": false, "需分满": true,
		"仅队友": false, "突破上限": false, "突破封顶": 0, "自动选": "自己",
		"提示": "消耗 1 宝石，你 +2 治疗（无视上限、最高到 5），并额外 +1 攻击行动"},
	# ---- 展示型：不接管选取与提交，选中目标后只在头像上写一句话 ----
	技能_天使祝福: {"总数": 2, "文案": "给你 %d 张牌"},
	技能_水之神力: {"总数": 1, "文案": "给他 %d 张牌"},
	# 魔导师【魔爆冲击】/【毁灭风暴】：选中的每名对手各 2 点法术伤害
	# （「不弃则我方战绩区 +1 宝石」那半句是给被问者看的，写在技能表「提示」列，由询问下发）
	技能_魔爆冲击: {"每目标": 2, "文案": "%d 法术伤害"},
	技能_毁灭风暴: {"每目标": 2, "文案": "%d 法术伤害"},
	# 神箭手【闪光陷阱】：选中的目标受 2 点法术伤害
	技能_闪光陷阱: {"每目标": 2, "文案": "%d 法术伤害"},
	# 神箭手【狙击】：选中的对手手牌直接补到 5 张
	技能_狙击: {"每目标": 5, "文案": "补到 %d 张"},
	# 魔导师 / 特殊魔导【魔弹融合】：地 / 火牌当【魔弹】打出去，落点受基础伤害
	# （后续传递递增的部分由客户端按询问里的当前伤害动态算，不走这张静态表）
	技能_魔弹融合: {"每目标": 魔弹基础伤害, "文案": "%d 法术伤害"},
	# 贤者【魔道法典】：对目标与自己各造成「弃牌数 - 1」法术伤害
	技能_魔道法典: {"文案": "%d 法术伤害", "每牌": 1, "偏移": -1,
		"自身": {"文案": "%d 法术伤害", "每牌": 1, "偏移": -1}},
	# 贤者【圣洁法典】：选中的每名角色各 +2 治疗；自己受「弃牌数 - 1」法术伤害
	技能_圣洁法典: {"每目标": 2, "文案": "%d 治疗",
		"自身": {"文案": "%d 法术伤害", "每牌": 1, "偏移": -1}},
	# 贤者【法术反弹】：自己受「弃牌数」法术伤害、目标受「弃牌数 - 1」
	技能_法术反弹: {"文案": "%d 法术伤害", "每牌": 1, "偏移": -1,
		"自身": {"文案": "%d 法术伤害", "每牌": 1, "偏移": 0}},
	# 元素师：陨石 / 风刃 / 雷击 按弃牌数结算（弃 1~2 张，伤害就是张数）
	技能_陨石: {"文案": "%d 法术伤害", "每牌": 1},
	技能_风刃: {"文案": "%d 法术伤害", "每牌": 1},
	技能_雷击: {"文案": "%d 法术伤害", "每牌": 1},
	# 冰冻：第 1 个目标吃「牌数」点伤害，第 2 个目标（技能原文「指定 1 名角色」）+1 治疗
	技能_冰冻: {"分目标": [
		{"文案": "%d 法术伤害", "每牌": 1},
		{"文案": "%d 治疗", "每目标": 1},
	]},
	# 火球：比弃牌数多 1 点
	技能_火球: {"文案": "%d 法术伤害", "每牌": 1, "偏移": 1},
	# 元素点燃：固定 2 点
	技能_元素点燃: {"文案": "%d 法术伤害", "每目标": 2},
	# 月光：伤害＝自己当前星石总数（宝石 + 水晶）
	技能_月光: {"文案": "%d 法术伤害", "每能量": 1},
	# 魔剑士【暗影流星】：选中的目标受 2 点法术伤害
	技能_暗影流星: {"每目标": 2, "文案": "%d 法术伤害"},
	# 灵符师【灵符－风行】：选中的 2 名角色各弃 1 张手牌
	技能_灵符风行: {"每目标": 1, "文案": "弃 %d 牌"},
	# 灵符师【灵符－雷鸣】：选中的 2 名角色各受 1 点法术伤害
	# （【灵力崩解】的「本次每次伤害 +1」要到结算前才决定，指示器按基础值 1 显示）
	技能_灵符雷鸣: {"每目标": 1, "文案": "%d 法术伤害"},
	# 灵符师【百鬼夜行】：先弹居中窗选效果 —— 展示火系【妖力】＝除选中的 2 人外全体各 1 点法术伤害
	# （选中的 2 人是被保下来的，所以提示「反选」：画在没选中的人身上）；
	# 不展示＝选中的 1 人受 1 点法术伤害（常规：画在选中的目标身上）
	技能_百鬼夜行: {"先弹选项": true, "选项目标数": {1: 2, 0: 1},
		"选项牌系": {1: GConst.CardElement.Fire},
		"选项提示": {
			1: {"反选": true, "文案": "%d 法术伤害", "每目标": 1},
			0: {"文案": "%d 法术伤害", "每目标": 1},
		}},
	# 祈祷师【光辉信仰】：选中的队友 +1 治疗（发动时须弃 min(2, 手牌) 张牌，见 role_qidao）
	技能_光辉信仰: {"每目标": 1, "文案": "%d 治疗"},
	# 祈祷师【黑暗诅咒】：对目标与自己各造成 2 点法术伤害（自己那句另画在自己头像上）
	技能_黑暗诅咒: {"每目标": 2, "文案": "%d 法术伤害",
		"自身": {"每目标": 2, "文案": "%d 法术伤害"}},
	# 剑帝【剑气斩】：先弹窗选「移除几点【剑气】」，再点一名「本次攻击目标以外」的角色；
	# 被点头像写「X 法术伤害」（X＝所选剑气数）。不能取消，超时自动打一个目标（见 role_jiandi）
	技能_剑气斩: {"先弹选项": true,
		"选项提示": {
			1: {"文案": "%d 法术伤害", "每目标": 1},
			2: {"文案": "%d 法术伤害", "每目标": 2},
			3: {"文案": "%d 法术伤害", "每目标": 3},
		}},
	# 封印师【封印破碎】：基础效果选择窗里把动词显示成「拿走」（对照角色实际行为：收入自己手中）
	技能_封印破碎: {"基础效果动作": "拿走"},
	# 死灵【死亡之触】：点技能先弹窗选「消耗多少治疗」，选完再选牌 / 选目标；
	# 被选中的目标头像上按「消耗治疗 + 弃牌数 - 3」现算要打过去的法术伤害
	技能_死亡之触: {"先弹选项": true, "选项窗标题": "消耗多少治疗？",
		"文案": "%d 法术伤害", "每牌": 1, "偏移": -3, "加参数": true},
	# 死灵【瘟疫】：进场自动把「除自己外所有人」选中并锁死（头像点不掉，只能靠「取消」退出），
	# 被选中的头像上直接显示即将受到的 1 点法术伤害
	技能_瘟疫: {"自动选目标": "他人", "文案": "%d 法术伤害", "每目标": 1},
	# 死灵【剧毒新星】：同上（每人 2 点），施放后另给自己 +1 治疗
	技能_剧毒新星: {"自动选目标": "他人", "文案": "%d 法术伤害", "每目标": 2},
}


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


## 技能表「类型」列（响应 / 启动 / 被动 / 法术…）；技能表里查不到就返回空串
static func skill_type(skill_id: int) -> String:
	var row: Array = 技能行(skill_id)
	if row.is_empty():
		return ""
	return str(row[_技能列("类型")]).strip_edges()


## 技能类型 → 标色（技能说明里【类型】的颜色，技能按钮底色也用它）
const 技能类型颜色: Dictionary = {
	"被动": Color(0.29, 0.62, 1.0),    # 蓝 #4a9eff
	"响应": Color(0.54, 0.31, 0.87),   # 深紫 #8a4fdd
	"法术": Color(1.0, 0.35, 0.82),    # 洋红 #ff5ad2
	"启动": Color(1.0, 0.67, 0.25),    # 橙 #ffab40
}


## 技能类型对应的标色；未知类型返回白色（不着色）
static func skill_type_color(skill_id: int) -> Color:
	return 技能类型颜色.get(skill_type(skill_id), Color.WHITE)


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


## 技能表「提示」列（list(String)）：这个技能要说给玩家听的文案，按需要排成多条。
## 不区分「问别人」还是「问自己」——读第几条、当什么用，由角色脚本自己决定（读哪个下标就是哪条）。
## 文案支持占位符 {src} = 发起者称号、{dst} = 收牌人称号、{n} = 要交/弃的张数；
## 表里没配（或该行没这一列）就返回空数组，客户端退回默认文案（「是否发动【X】？」）。
static func 技能提示列表(skill_id: int) -> Array[String]:
	var 列索引: Dictionary = 数据表格.表元数据["技能表"]["列索引"]
	var 列: int = int(列索引.get("提示", -1))
	if 列 < 0:
		return []
	var row: Array = 技能行(skill_id)
	if row.size() <= 列:
		return []
	var 格子: Variant = row[列]
	if not (格子 is Array):
		return []
	var out: Array[String] = []
	for 元素: Variant in (格子 as Array):
		var 文本: String = _提示元素文本(元素)
		if not 文本.is_empty():
			out.append(文本)
	return out


## 「提示」列的一项转成字符串：导表把 list(String) 的每项生成成「单元素数组」，这里取回那一个串
static func _提示元素文本(元素: Variant) -> String:
	if 元素 is Array and not (元素 as Array).is_empty():
		return str((元素 as Array)[0]).strip_edges()
	return str(元素).strip_edges()


## 取「提示」列的第 序号 条（从 0 起）并填好占位符；没配或序号越界就返回空串
static func 提示文本(skill_id: int, 序号: int, 发起者: String, 张数: int, 收牌人: String = "") -> String:
	var 列表: Array[String] = 技能提示列表(skill_id)
	if 序号 < 0 or 序号 >= 列表.size():
		return ""
	return 列表[序号].replace("{src}", 发起者).replace("{n}", str(张数)).replace("{dst}", 收牌人)


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
