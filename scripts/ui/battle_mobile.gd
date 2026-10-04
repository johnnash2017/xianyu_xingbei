extends Control
## 战斗界面（手机版）容器 —— 把本项目的战斗数据灌进「参考工程搬来的」BattleUIMobile 控件里。
##
## 背景与取舍：
##  * 被搬过来的容器脚本 scripts/BattleUIMobile.gd 是参考工程原件，依赖 BattleData / Dialog /
##    Lobby / UIManager / GameManager / MessageSystem 等本工程不存在的单例，本脚本不再使用它，
##    只把它当作「控件结构与参考行为」的参考。
##  * 数据映射照参考工程搬来的桌面战斗界面抄：监听 Logic 的信号，读 Data.player_list 与
##    Logic.last_info 刷新界面。
##  * 本步骤只做「显示」。手牌区/出牌/选目标/技能/应战等交互是下一步（脚本里以「第三步」留白），
##    音频也下一步统一搬。
##  * 节点引用一律 @export 在检查器绑定（对应 scenes/BattleUIMobile.tscn 的 NodePath）。

# ---------------- 界面节点（@export 绑定） ----------------
## Root 目前只用于「出牌箭头」这类要挂到根上的动画节点（第三步）。
@export var Root: Control
@export var MainPlayer: 战斗玩家面板
@export var PlayerStatusMobileR: 战斗玩家面板
@export var PlayerStatusMobileUR: 战斗玩家面板
@export var PlayerStatusMobileU: 战斗玩家面板
@export var PlayerStatusMobileUL: 战斗玩家面板
@export var PlayerStatusMobileL: 战斗玩家面板
@export var BlueMorale: Label
@export var RedMorale: Label
@export var BlueEnergy: GridContainer
@export var RedEnergy: GridContainer
@export var BlueGrail: GridContainer
@export var RedGrail: GridContainer
@export var TxtTurn: Label
@export var TxtRID: Label
@export var TxtHint: Label
@export var Hint: Control
## 屏幕右下角的测试指令提示（测试用，仅显示键位说明）
@export var 测试提示: Label
@export var Content_2: RichTextLabel    # 日志控件（场景里挂着 AutoClearLog.gd；RichTextLabel 才能按行上色）
@export var MsgRoot: ScrollContainer    # 日志滚动区（展开日志时滚到最新一条）
@export var Content: GridContainer     # 聊天条目容器
@export var InputField: LineEdit
@export var BtnSubmit: Button
@export var BtnLogExpand: Button
@export var BtnChatExpand: Button
@export var WinPanel: Control
@export var EndTxt: Label
@export var BtnBack: Button
@export var LogRoot: Control           # 日志面板根（展开/收起用）
@export var ChatRoot: Control          # 聊天面板根（展开/收起用）
# ---- 交互层用到的控件（第三步） ----
@export var HandArea: Control        # 我的手牌区（Root/HandArea；一行手排，位置由 刷新手牌 算）
@export var ShowCardArea: Control      # 屏幕中间的展示卡牌区（Root/ShowCardArea；出牌/展示时把牌摊出来）
@export var SkillArea: Control         # 技能区底图（Root/SkillArea）
@export var ChildrenSkillArea: GridContainer  # 技能按钮容器（Root/ChildrenSkillArea）
@export var ChooseArea: Control        # 盖牌选择区（Root/ChooseArea）
@export var BtnOK: Button              # 确定
@export var BtnCancel: Button          # 取消
@export var BtnCovered: Button         # 「盖牌」按钮（点开/收起查看自己的盖牌）
@export var BtnSpecila: Button         # 行动阶段＝「特殊行动」（购买/合成/提炼）；魔弹传递时＝「放弃」
@export var BtnResign: Button          # 行动阶段＝「放弃行动」（对照参考工程 PlayerAgentUI 的 BtnResign → ResignAction）
## 特殊行动专用窗口（购买/合成/提炼，搬自参考工程 SpecialActionUI）：预制体在 _ready 里挂到本界面最上层
const 特殊行动窗预制: PackedScene = preload("res://scenes/prefabs/battlemobile/SpecialActionUI.tscn")
var 特殊行动窗: 特殊行动窗口 = null
## 参数选择窗口（特殊行动的第二层「用哪些星石」，搬自参考工程 ChooseArgsUI）
const 参数选择窗预制: PackedScene = preload("res://scenes/prefabs/battlemobile/ChooseArgsUI.tscn")
var 参数选择窗: 参数选择窗口 = null
## 英雄详情窗（技能说明，搬自参考工程 InfomationUI）：平时点一名玩家的头像就弹它
const 英雄详情窗预制: PackedScene = preload("res://scenes/prefabs/battlemobile/InfomationUI.tscn")
var 英雄详情窗: 英雄详情窗口 = null
## 参数选择窗口是为哪个特殊行动打开的（选完星石要按它提交）
var _待定特殊行动: int = GConst.SpecialAction.Buy
## 参数选择窗口这次是给「发动技能」用的（如【风之洁净】确定后列出目标身上的基础效果供选）：
## true 时选中的 args 按当前待发动技能提交，点「取消」也只是关窗、回到原来的选牌/选目标状态
var _参数选择_技能: bool = false
## 参数选择窗口这次是给「多份额外行动」用的（如剑圣【风怒追击】+【剑影】）：
## 在窗里选一项＝发动它，点窗里的「取消」＝跳过（与单份的「取消」等价）
var _参数选择_额外行动: bool = false
## 本地询问（不经服务端）：冒险家【冒险者天堂】提炼前先问把星石给谁
var _本地询问: bool = false
## 【冒险者天堂】选定的队友（-1＝没选，星石给自己）
var _提炼目标: int = -1

## 预制体目录（格子/聊天条目与参考脚本一致）
const 预制目录: String = "res://scenes/prefabs/battlemobile/"
## 提示显示后自动隐藏的秒数（同参考工程的 Invoke("hideHint", 3f)）
const 提示停留秒: float = 3.0
## 日志最多保留的行数（同参考工程 AutoClearLog 的裁剪行数）
const 日志最大行: int = 233
## 宝石/水晶/星杯格子的最小尺寸（Unity 转过来的 Image 预制体是 0×0，必须给尺寸）
## 正方形：贴图本身近似正方形（宝石 29×30、水晶 29×30、星杯 23×23），
## 给 30×40 会把它们上下拉伸；队伍条容器高 30、5 列正好 5×30=150
const 格子最小尺寸: Vector2 = Vector2(30.0, 30.0)
## 卡牌预制体（挂 scripts/CardUI.gd，已解耦为「塞数据 + 点击回调」）
const 卡牌预制: PackedScene = preload("res://scenes/prefabs/battlemobile/Card.tscn")
## 技能按钮预制体（挂 scripts/SkillUI.gd，同上）
const 技能预制: PackedScene = preload("res://scenes/prefabs/battlemobile/Skill.tscn")
## 给牌动效预制体（一张卡背从交牌人飘到收牌人，见 _给牌特效）
const 给牌预制: PackedScene = preload("res://scenes/prefabs/effects/给牌.tscn")
## 交多张给牌动效之间的起飞间隔（秒）：一张接一张，不叠在一起
const 给牌间隔: float = 0.12
## 弃牌动效预制体（卡背从弃牌者身上飞向画面中心并淡出，见 _弃牌特效）
const 弃牌预制: PackedScene = preload("res://scenes/prefabs/effects/弃牌.tscn")
## 弃多张时各张之间的起飞间隔（秒）
const 弃牌间隔: float = 0.09
## 手牌卡面尺寸（参考脚本 showCard 用的 136×190，这里略窄一点好让 6 张能排下）
const 手牌尺寸: Vector2 = Vector2(130.0, 192.0)
## 「可选」发光框的颜色：平常绿光；正在弃牌时改红光（更醒目，也和「打出」区分开）
const 可选发光_绿: Color = Color(0.0, 1.0, 0.024)
const 可选发光_红: Color = Color(1.0, 0.25, 0.25)
## 底栏提示文案的字号：场景里是 25，文案过长时按提示框宽度自动缩，最小缩到 14
const 提示基础字号: int = 25
const 提示最小字号: int = 14
## 选中的手牌往上抽出来的距离（视觉上「已拿出、等确定」）；顶部提示的上移量也取它
const 选中上浮像素: float = 23.0
## 新补进手牌的「向下放置」动画：从比「点击抽出」更高的位置落回原位
const 补牌落下高度: float = 92.0
const 补牌落下时长: float = 0.3
## 手牌排布：牌少时彼此贴着排（空隙 0）并整体居中；一行放不下才压缩，压到负数就是相邻两张叠着放
const 手牌最多重叠比例: float = 0.45
## 盖牌尺寸（盖牌选择区里手排用；与手牌同尺寸＝正常卡牌大小）
const 盖牌尺寸: Vector2 = 手牌尺寸
## 盖牌之间的默认空隙；一行放不下时压缩（可以为负＝叠着放），见 刷新盖牌
const 盖牌间距: float = 8.0
## 技能按钮最小尺寸（Skill.tscn 根按钮的实际尺寸是 110×90）
const 技能尺寸: Vector2 = Vector2(110.0, 90.0)
## 玩家面板：常态 / 选中（目标）颜色
const 面板常态色: Color = Color(1.0, 1.0, 1.0)
const 面板选中色: Color = Color(1.0, 1.0, 0.55)
## 当前不可选的玩家面板整体压暗（视觉上「点不动」，同卡牌那套置灰）
const 面板置灰色: Color = Color(0.5, 0.5, 0.5)
## 头像提示的框宽与单行高度（挂在 Root 上的独立控件，见 _取治疗提示）；
## 框高按文案行数现算，见 _贴头像提示（RichTextLabel 会裁掉超出框的内容）
const 治疗提示宽: float = 140.0
const 提示行高: float = 34.0
## 头像提示的文字配色（BBCode 十六进制）：治疗＝浅蓝、法术伤害＝洋红，见 _提示上色
const 提示色_治疗: String = "9ED9FF"
const 提示色_法术伤害: String = "FF3CFF"
## 治疗加号特效：单个「+」的占位尺寸、配色与数量区间（见 _播放治疗加号）；
## 加号色与上面的 提示色_治疗 是同一个浅蓝
const 加号尺寸: Vector2 = Vector2(56.0, 56.0)
const 加号色: Color = Color(0.62, 0.85, 1.0)
const 加号描边色: Color = Color(0.08, 0.26, 0.45)
## 加号特效的散布范围 / 错开延迟 / 上升速度的倍率（1.0 = 原始手感）：
## 范围与延迟按需求放大到 3 倍，上升速度保持原速（时长 = 基础 × 时间倍率 ÷ 速度倍率）
const 加号范围倍率: float = 3.0
const 加号时间倍率: float = 3.0
const 加号速度倍率: float = 1.0

## 战斗日志的样式：每行开头一个彩色的「[类别]」标识，后面的正文一律白字（方便一眼扫类别）。
## 颜色是暗底上柔和的低饱和色，避免刺眼。
const 日志标签色: Dictionary = {
	"系统": "#D8DEE9",     # 开局 / 终局 / 其它公告
	"回合": "#FFD98A",     # 轮到谁 / 回合数
	"行动": "#93E6A8",     # 出牌 / 发动技能
	"伤害": "#FF9A9A",     # 攻击 / 命中 / 伤害 / 抵挡
	"治疗": "#8FC7FF",     # 治疗 / 恢复
	"卡牌": "#B9B4C7",     # 出牌 / 弃牌 / 交牌 / 资源消耗 / 手牌数量与上限变化
	"指示物": "#C6A6FF",   # 指示物变化
	"提示": "#FFB27A",     # 超时 / 掉线 / 无效操作 / 错误
	"聊天": "#8FE0D8",     # 玩家发言
}
## 日志正文的颜色（白）
const 日志正文色: String = "#FFFFFF"
## 日志正文里玩家名（角色名[玩家名]）与卡名的着色：正文仍以白字为底，只把专名挑出来上色
const 日志玩家色: String = "#FFD98A"
const 日志卡牌色: String = "#8FD3FF"
## 星石的着色：宝石红、水晶蓝（正文里凡提到星石都按这个上色）
const 日志宝石色: String = "#FF6B6B"
const 日志水晶色: String = "#6BB8FF"


## GConst.GossipType → 日志类别（决定那一行的 [标签] 与颜色）
func _日志标签(kind: int) -> String:
	match kind:
		GConst.GossipType.Talk:
			return "聊天"
		GConst.GossipType.Combat:
			return "伤害"
		GConst.GossipType.Heal:
			return "治疗"
		GConst.GossipType.Discard:
			return "卡牌"
		GConst.GossipType.Skill:
			return "行动"
		GConst.GossipType.Turn:
			return "回合"
		GConst.GossipType.Token:
			return "指示物"
		GConst.GossipType.Warn:
			return "提示"
		_:
			return "系统"

## 能把地系 / 火系牌当【魔弹】打出去的角色（【魔弹融合】803，对照 role_modao / role_spmodao）
const 地火可作魔弹角色: Array[int] = [8, 108]
## 拥有【魔弹掌握】（802）的角色：主动打【魔弹】时左右两个方向都能选（对照 skillDB 802「可选逆向传递」）。
## 注意只在「主动使用」那一步生效 —— 魔弹打出后传递方向就固定了，传递时不能改向
const 魔弹掌握角色: Array[int] = [8]
## 【黑暗束缚】2903：不能用【魔弹】转弹、也不能用【圣光】格挡（对照 role_moqiang）
const 魔弹全禁角色: Array[int] = [29]
## 行动阶段不能使用法术牌的角色（【暗影抗拒】904，对照 role_mojian 的 v_allow_action）
const 行动阶段禁用法术牌角色: Array[int] = [9]
## 仲裁者：审判满上限时本回合只能发动【末日审判】（对照 ZhongCai::v_allow_action）
const 仲裁者角色: int = 14

## 玩家面板顺序：自己的面板固定是 MainPlayer，其余按 Data.player_list 顺序依次填
var _面板列表: Array[战斗玩家面板] = []
## 日志缓冲：Content_2 上的 AutoClearLog 按行裁剪，需要整段文本
var _日志: String = ""
## 当前回合玩家 id（用于面板高亮）
var _当前回合: int = -1
## 当前「背后的 Turn 亮着」的玩家 id：轮到谁行动 / 在等谁回复都算，变了才重播动画
var _高亮玩家id: int = -2
## 正在等谁回复、还剩多少秒（由对局快照刷新）
var _等待方: int = -1
var _等待剩余: float = 0.0
## 本次等待的总时长（秒）：进度条按「剩余 / 总时长」画
var _等待总时长: float = 0.0
## 提示自动隐藏：token 变了说明来了新提示，旧的倒计时作废（同参考脚本的做法）
var _提示计时器: Timer = null
var _提示token: int = 0
var _当前提示token: int = 0
## 对局是否已开始：开局日志只写一次
var _已开局: bool = false
## 胜负是否已结算：公告与终局信号可能重复，只结算一次
var _胜负已定: bool = false
## 数值快照：判断士气 / 宝石水晶 / 治疗的变化并播对应音效
var _上次士气: Array[int] = [0, 0]
var _上次宝石: Array[int] = [0, 0]
var _上次水晶: Array[int] = [0, 0]
var _上次治疗: int = 0

# ---------------- 交互状态 ----------------
## 0 空闲 / 1 行动 / 2 响应 / 3 技能询问 / 4 发动技能
var _mode: int = 0
## 本次行动询问是否允许「放弃行动」：服务端下发了 ACTION_NONE 命令才置真
## （对照原版 canGiveUp：普通行动阶段不容许放弃，被挑衅 / 额外行动阶段才容许）
var _可放弃行动: bool = false
## 本次行动阶段放行动作的种类（GConst.ActionType：Any / Attack / AttackMagic / Magic…），
## 由服务端的行动询问下发。额外攻击行动（如女武神【神圣追击】）只给 Attack，
## 界面据此把法术牌置灰——不放行还亮着的话点了必被服务端拒
var _行动允许: int = GConst.ActionType.Any
## 当前 CMD_REQ 的单条命令
var _pending: Dictionary = {}
## 当前询问的类型（GConst.Msg.Action / Msg.Respond）
var _pending_type: int = -1
## 本次要选几张牌 / 几个目标
var _need_cards: int = 0
var _need_players: int = 0
## 已选中
var _sel_cards: Array[int] = []
var _sel_players: Array[int] = []
## 目标是否已锁死（【瘟疫】/【剧毒新星】：进场自动选中全体打架目标，点头像也改不了，只能用「取消」退出）
var _目标锁死: bool = false
## 我的手牌上一次刷新时的牌 id：用来认出这一轮新补进来的牌，只给它们播「向下放置」动画
var _上次手牌: Array[int] = []
## 新补牌的落点起算时刻（card_id → 毫秒），落回原位后清掉
var _补牌起点: Dictionary = {}
## 「分配型」指示器（点头像分配）的分配记录：按点击顺序存每次点击的目标（同一个人可重复出现）。
## 点一次＝给该角色加「每次」点治疗；分满上限后再点一次＝重新分配，本次点击成为第 1 次。
var _治疗分配: Array[int] = []
## 头像上那句提示（「N 治疗」「N 法术伤害」「给你 N 张牌」）的 Label 池：
## player_id -> 挂在 Root 上的 Label（不挂在面板里，避免被面板选中效果染黄/盖住）
var _治疗提示表: Dictionary = {}
## 魔弹 / 念弹这类「数值只能现算」的提示这一帧画过哪几个头像（下一次不再提示时要收起那几个）
var _动态提示过的头像: Array[int] = []
## 技能询问：正在询问是否发动的技能号（-1 表示没有；靠 _是技能询问 判断是不是真的技能询问）
var _skill_ask_id: int = -1
## 当前这条应答是不是「是否发动某技能」的技能询问：
## 由服务端在命令里显式标记 is_skill 下发，客户端不再拿询问号大小去猜
var _是技能询问: bool = false
## 额外行动询问里只有一份可选额外行动时，记下它的 cause：不再摆「选项」按钮，
## 直接问「是否发动？」，点「确定」发动 / 「取消」跳过（-1 表示没有，仍走多选项按钮）
var _额外行动单选: int = -1
## 上面那份额外行动此刻能不能发动（引擎在询问的 dst_ids 里下发「可发动」列表）：
## 不能发动时「确定」置灰、只能「取消」跳过（如手里没有风系攻击牌时的【风怒追击】）
var _额外行动可选: bool = true
var _skill_ask_need_card: int = 0
var _skill_ask_need_target: int = 0
## 技能询问的选牌来源（GConst.CardSource）
var _skill_ask_card_source: int = 0
## 本次技能询问能不能点「取消」（false＝强制，如【水之神力】的交牌）
var _skill_ask_can_cancel: bool = true
## 本次询问是否要选盖牌（盖牌区可见且可点）
var _selecting_cover: bool = false
## 是否正在「查看盖牌」（点「盖牌」按钮打开，只读，不影响回合）
var _查看盖牌: bool = false
## 技能询问的可选项值（非空时渲染选项按钮）
var _skill_options: Array[int] = []
## 当前询问要用的「居中参数选择窗」选项（非空＝这次询问改用弹窗渲染；
## 如【神之庇护】抵消几点、治疗抵挡几点——只选参数、不用选牌选目标）
var _弹窗选项: Array = []
## 上面那个弹窗的标题
var _弹窗标题: String = ""
## 「先弹选项」型询问（技能指示器配了「先弹选项」，如灵符师【百鬼夜行】）：
## 进入询问先弹居中的效果选择窗，窗里只记下选了哪一项，选完再选牌 / 选目标，按「确定」才提交
var _先弹选项: bool = false
## 上面那个弹窗里已选定的效果 args（原样随「确定」上交；没选之前「确定」不可用）
var _已选参数: Array = []
## 「先弹选项」型询问里服务端原本给的目标数：选完效果后若「选项目标数」没配该效果，用它还原
## （如【剑气斩】：没配「选项目标数」，选完剑气数后仍要能选 1 名目标）
var _选项原始目标数: int = 0
## 同上，「先弹选项」型发动技能时临时清零、选完效果再还原的最多目标数 / 需牌 / 最多牌
## （选效果之前不让点牌、不让点目标，选完才放开 —— 见 _选择技能 / _应用选项目标数）
var _选项原始最多目标: int = 0
var _选项原始需牌: int = 0
var _选项原始最多牌: int = 0
## 已选定要发动的技能号与它对应的 action_type
var _pending_skill_id: int = -1
var _pending_skill_type: int = -1
var _skill_need_card: int = 0
var _skill_need_target: int = 0
## 本次发动技能的合法目标（服务端在技能上给的 targets，非空时只让这几名玩家亮；
## 例：【魔弹融合】默认只有右手边最近的对手，有【魔弹掌握】时左右各一个）
var _skill_targets: Array[int] = []
## 本次发动技能的合法手牌（服务端在技能上给的 cards，非空时只让这几张牌可点；
## 例：【暗影流星】只能弃法术牌）
var _skill_cards: Array[int] = []
## 本次发动技能的点选上限（服务端在技能上给的 card_max，≥ 需牌数；如【欺诈】可弃 2~3 张）
var _skill_card_max: int = 0
## 本次发动技能的选牌系别规则（服务端给的 card_rule：""＝不限 / "same"＝必须同系 / "diff"＝必须互异系）
var _skill_card_rule: String = ""
## 本次发动技能的目标数上限（服务端在技能上给的 target_max，≥ 需目标数；省略＝刚好需目标数）
var _skill_target_max: int = 0
## 目标数上限随已选牌数变化的减数（服务端给的 target_max_from_cards；0＝不适用）。
## 上限 = 已选牌数 - 该值，至少 1 名（如【圣洁法典】＝弃牌数 - 2）——玩家取消一张牌后上限要跟着降
var _skill_target_max_from_cards: int = 0
## 逐张选牌的条件（服务端给的 card_slot_skill / card_slot_element；0＝不要求）：
## 第 1 张必须带该技能、第 2 张必须是该系的牌（如元素师独有法术的「发动牌 + 该系加伤牌」）
var _skill_slot_skill: int = 0
var _skill_slot_element: int = 0
## 本次发动技能的选牌来源（GConst.CardSource：手牌 / 盖牌区 / 场上基础效果牌）
var _skill_card_source: int = GConst.CardSource.Hand
## 本次发动技能的参数选项（服务端在技能上给的 arg_choices：每项一个按钮，点它就用当前已选的牌/目标提交）
var _skill_arg_choices: Array = []
## 参数选项按钮 [{按钮, 需牌, 需目标}]：选项可以要求先选够牌/目标，没选够就压灰
var _参数按钮: Array = []
## 技能区当前渲染出来的按钮（行动阶段技能 / 选项 / 额外行动 / 特殊行动共用）
var _技能按钮: Array[Node] = []
## 本次行动询问下发的全部命令（取消技能/特殊行动时用它把技能按钮摆回来）
var _行动命令: Array = []
## 【地下法则】的持有者：冒险家（购买时只加宝石、一次可加 2 点，对照 role_maoxian.v_buy）
const 冒险家角色号: int = 12
## 【冒险者天堂】的技能号：冒险家提炼前先问把星石给谁（对照 role_maoxian）
const 冒险者天堂技能号: int = 1202


func _ready() -> void:
	_面板列表 = [MainPlayer, PlayerStatusMobileR, PlayerStatusMobileUR,
		PlayerStatusMobileU, PlayerStatusMobileUL, PlayerStatusMobileL]
	Logic.game_info_updated.connect(_on_game_info)
	Logic.turn_changed.connect(_on_turn)
	Logic.card_shown.connect(_on_card)
	Logic.hit_received.connect(_on_hit)
	Logic.hurt_received.connect(_on_hurt)
	Logic.skill_received.connect(_on_skill)
	Logic.gossip_received.connect(_on_gossip)
	Logic.notice_received.connect(_on_notice)
	Logic.heal_received.connect(_on_heal_received)
	Logic.discard_received.connect(_on_discard_received)
	Logic.error_received.connect(_on_error)
	BtnSubmit.pressed.connect(_on_submit)
	InputField.text_submitted.connect(func(_t: String) -> void: _on_submit())
	BtnLogExpand.pressed.connect(_展开日志)
	BtnChatExpand.pressed.connect(_展开聊天)
	BtnBack.pressed.connect(_on_back)
	# 初始收起日志/聊天（同参考脚本 Start 里的处理）
	LogRoot.visible = false
	ChatRoot.visible = false
	# 顶部提示抬高一段「选中手牌上浮」的高度，免得被抽出来等着确定的牌盖住
	Hint.offset_top -= 选中上浮像素
	Hint.offset_bottom -= 选中上浮像素
	# ---- 交互层（第三步）：接收询问 + 确定/取消/盖牌/特殊行动/放弃行动 ----
	Logic.command_received.connect(_on_command)
	# 让「操作无效」（ErrorInput）能回调到本界面
	Logic.battle = self
	BtnOK.pressed.connect(_on_ok)
	BtnCancel.pressed.connect(_on_cancel)
	BtnCovered.pressed.connect(_on_cover_view)
	BtnSpecila.pressed.connect(_on_giveup)
	BtnResign.pressed.connect(_on_resign)
	# 特殊行动窗口挂在最上层（最后 add_child → 画在最上面），平时自己隐藏
	特殊行动窗 = 特殊行动窗预制.instantiate()
	add_child(特殊行动窗)
	特殊行动窗.选择了.connect(_on_special_action_chosen)
	特殊行动窗.取消了.connect(_on_special_action_cancelled)
	参数选择窗 = 参数选择窗预制.instantiate()
	add_child(参数选择窗)
	参数选择窗.选择了.connect(_on_参数选择)
	参数选择窗.取消了.connect(_on_参数选择取消)
	英雄详情窗 = 英雄详情窗预制.instantiate()
	add_child(英雄详情窗)
	for 面板: 战斗玩家面板 in _面板列表:
		面板.pressed.connect(_on_player_pressed.bind(面板))
		面板.基础效果牌点击.connect(_on_基础牌点击)
	ChooseArea.visible = false
	_隐藏技能区()
	# 手牌是按 HandArea 的实际宽度手排成一行的，尺寸一变（窗口缩放）就重排
	HandArea.resized.connect(刷新手牌)
	# 测试指令提示（测试用，挂在屏幕右下角；清单见 测试指令表）
	var 说明行: Array[String] = []
	for 项: Array in 测试指令表:
		说明行.append("%s %s" % [OS.get_keycode_string(int(项[0])), str(项[1])])
	测试提示.text = "\n".join(说明行)
	# 场景被重新挂上时，可能有已经到达的快照
	if not Logic.last_info.is_empty():
		_on_game_info(Logic.last_info)
	else:
		_刷新交互()


func _exit_tree() -> void:
	if Logic.battle == self:
		Logic.battle = null


## 测试指令清单：[键位（Key 值）, 说明]。右下角的说明文字与快捷按钮都由它生成，避免两处重复
const 测试指令表: Array = [
	[KEY_0, "跳过当前行动玩家的回合"],
	[KEY_1, "清空手牌"],
	[KEY_2, "发技能牌"],
	[KEY_3, "发 3 张同系斩 + 3 张异系法术"],
	[KEY_4, "当前倒计时压到 1 秒"],
	[KEY_5, "双方士气拉满到 99"],
	[KEY_6, "全员标识物拉满"],
	[KEY_7, "随机填充双方战绩区星石"],
	[KEY_8, "清空治疗"],
	[KEY_9, "治疗/宝石拉满"],
]


## 测试快捷键（只在战斗界面里生效；键位与 GConst.DebugKey 的取值一致）
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var 键: InputEventKey = event as InputEventKey
	if not 键.pressed or 键.echo:
		return
	_测试指令(键.keycode)


## 执行一条测试指令（键盘按键、右下角快捷按钮点一下，走同一条路）
func _测试指令(键: int) -> void:
	match 键:
		KEY_0:
			# 正被询问「是否发动 / 是否应战 / 弃哪几张」等：按 0 = 取消这次询问（不发动），
			# 等价于点「取消」；轮到自己在行动阶段（没有询问）时 = 跳过自己这一回合（测试用）
			if _mode == 0 or _mode == 1:
				Logic.debug_key(GConst.DebugKey.SkipTurn)
			else:
				_on_cancel()
		KEY_1:
			Logic.debug_key(GConst.DebugKey.Clear)
		KEY_2:
			Logic.debug_key(GConst.DebugKey.SkillCards)
		KEY_3:
			Logic.debug_key(GConst.DebugKey.Cards)
		KEY_4:
			Logic.debug_key(GConst.DebugKey.ShortenWait)
		KEY_5:
			Logic.debug_key(GConst.DebugKey.MoraleFull)
		KEY_6:
			Logic.debug_key(GConst.DebugKey.MaxTokens)
		KEY_7:
			Logic.debug_key(GConst.DebugKey.RandomEnergy)
		KEY_8:
			Logic.debug_key(GConst.DebugKey.CrossClear)
		KEY_9:
			Logic.debug_key(GConst.DebugKey.HealEnergy)


# ============================================================
# 刷新
# ============================================================
## 对局快照 → 刷新队伍数值、房间号、玩家面板
func _on_game_info(info: Dictionary) -> void:
	var started: bool = bool(info.get("is_started", false))
	# 留着「上一条快照是否已开局」：开局那一条只做记录，否则士气 0 → 初始值会白响一声
	var 之前已开局: bool = _已开局
	if started and not _已开局:
		_已开局 = true
		# 房间等待阶段仍是大厅音乐，真开打才换战斗曲
		Audio.播放音乐(Audio.场景战斗)
		_日志追加("房间 %d 对局开始" % int(info.get("room_id", 0)), "系统")
	_播音效_数值变化(info, 之前已开局 and started)
	_刷新队伍(info)
	_刷新玩家面板()
	_读取等待(info)
	TxtRID.text = str(int(info.get("room_id", 0)))
	# 手牌/盖牌/目标可选状态跟着快照走（Data.build_player_list 已同步好）
	_刷新交互()


## 等待提示：读「正在等谁回复、还剩多久」
func _读取等待(info: Dictionary) -> void:
	_等待方 = int(info.get("wait_pid", -1))
	_等待总时长 = float(info.get("wait_total_ms", 0)) / 1000.0
	_等待剩余 = float(info.get("wait_ms", 0)) / 1000.0
	_刷新等待条()
	# 服务端已经在等别人了，说明挂在手上那条询问早已作废（最典型的是自己超时后服务端径自往下走）：
	# 立刻退回等待态 —— 手牌/目标置灰、技能收起，否则会出现「别人的回合我还能点还能选目标」
	if _等待方 >= 0 and _等待方 != Logic.my_player_id and _mode != 0:
		_清空待选()
	if _等待方 < 0:
		return
	# 在等谁回复（应战 / 圣盾 / 魔弹传递…）就把谁的面板高亮起来
	_高亮玩家(_等待方)
	# 自己手上正有询问时，提示交给交互层写，别被等待文案盖掉
	if _mode != 0:
		return
	var 名: String = _称号(_等待方)
	var 文本: String = "正在等待你的操作…" if _等待方 == Logic.my_player_id else "正在等待 %s 操作…" % 名
	_提示(文本)


## 等待进度条：服务端只在「开始等待 / 等待结束」广播，剩余时间由客户端自己倒数
func _process(delta: float) -> void:
	if _等待方 < 0:
		return
	_等待剩余 = maxf(_等待剩余 - delta, 0.0)
	_刷新等待条()


## 超时进度条画在「正在被等的那名玩家」的名牌上方，其余面板收起（传负值）
func _刷新等待条() -> void:
	var 比例: float = -1.0
	if _等待方 >= 0 and _等待总时长 > 0.0:
		比例 = clampf(_等待剩余 / _等待总时长, 0.0, 1.0)
	for 面板: 战斗玩家面板 in _面板列表:
		面板.WaitProgress = 比例 if 面板.ID == _等待方 else -1.0


## 数值变化音效（对照参考项目 MoraleChange / GemChange / CrystalChange / PlayerHealChange）
func _播音效_数值变化(info: Dictionary, 生效: bool) -> void:
	var 士气: Array[int] = [int(info.get("red_morale", 0)), int(info.get("blue_morale", 0))]
	var 宝石: Array[int] = [int(info.get("red_gem", 0)), int(info.get("blue_gem", 0))]
	var 水晶: Array[int] = [int(info.get("red_crystal", 0)), int(info.get("blue_crystal", 0))]
	var 治疗: int = 0
	for p: GPlayer in Data.player_list:
		治疗 += p.cross_num
	if 生效:
		if 士气 != _上次士气:
			Audio.播音效("sys-morale")
		elif 宝石 != _上次宝石 or 水晶 != _上次水晶:
			Audio.播音效("sys-energy")
		if 治疗 != _上次治疗:
			Audio.播音效("sys-heal")
	_上次士气 = 士气
	_上次宝石 = 宝石
	_上次水晶 = 水晶
	_上次治疗 = 治疗


## 士气 / 宝石 / 水晶 / 星杯（读 Logic.last_info 的绝对值）
func _刷新队伍(info: Dictionary) -> void:
	BlueMorale.text = str(int(info.get("blue_morale", 0)))
	RedMorale.text = str(int(info.get("red_morale", 0)))
	_重建能量(BlueEnergy, int(info.get("blue_gem", 0)), int(info.get("blue_crystal", 0)))
	_重建能量(RedEnergy, int(info.get("red_gem", 0)), int(info.get("red_crystal", 0)))
	_重建格子(BlueGrail, int(info.get("blue_grail", 0)), "grail")
	_重建格子(RedGrail, int(info.get("red_grail", 0)), "grail")


## 能量格：宝石在前、水晶在后（与参考脚本 gemChange / crystalChange 的落位一致）
func _重建能量(容器: GridContainer, 宝石数: int, 水晶数: int) -> void:
	_清空格子(容器)
	for _i: int in range(maxi(宝石数, 0)):
		_加格子(容器, "gem")
	for _j: int in range(maxi(水晶数, 0)):
		_加格子(容器, "crystal")


## 单一贴图的格子（星杯）
func _重建格子(容器: GridContainer, 数量: int, 贴图名: String) -> void:
	_清空格子(容器)
	for _i: int in range(maxi(数量, 0)):
		_加格子(容器, 贴图名)


func _清空格子(容器: GridContainer) -> void:
	for c: Node in 容器.get_children():
		c.queue_free()


## 单个格子：用 battlemobile/Image.tscn，贴图交给 AssetIndex 按文件名取
func _加格子(容器: GridContainer, 贴图名: String) -> void:
	var ps: PackedScene = load(预制目录 + "Image.tscn")
	if ps == null:
		return
	var go: Node = ps.instantiate()
	if go is TextureRect:
		var 路径: String = AssetIndex.image(贴图名)
		if 路径 != "":
			(go as TextureRect).texture = load(路径)
	if go is Control:
		var 格子: Control = go as Control
		格子.custom_minimum_size = 格子最小尺寸
		# 队伍条是纯装饰、又排在玩家面板上层：格子必须放行点击，
		# 否则落在队伍条那一条（y<128）上的头像点击会被它吃掉
		格子.mouse_filter = Control.MOUSE_FILTER_IGNORE
	容器.add_child(go)


## 玩家面板：自己的面板固定是 MainPlayer，其余按 Data.player_list 顺序依次填。
## Data.build_player_list() 已按「我」的视角旋转过，player_list[0] 就是自己；这里仍显式按
## Logic.my_player_id 找到自己的下标，保证 MainPlayer 一定是自己。
## 注：参考工程 4 人房会把 U/UR 两个面板 queue_free 掉；本步骤改为「按顺序填、多出来的隐藏」，
## 不做销毁（避免刷新后无法恢复）。
func _刷新玩家面板() -> void:
	var 玩家列表: Array[GPlayer] = Data.player_list
	var n: int = 玩家列表.size()
	var 我的下标: int = 0
	for i: int in range(n):
		if 玩家列表[i].id == Logic.my_player_id:
			我的下标 = i
			break
	for idx: int in range(_面板列表.size()):
		var 面板: 战斗玩家面板 = _面板列表[idx]
		# 座位不够的面板藏起来（原来这行写在 continue 后面，是走不到的死代码，人一多就不会再显示）
		面板.visible = idx < n
		if idx >= n:
			# 空面板给个哨兵 ID：默认值是 0，会和「0 号位玩家」撞上 —— 按 ID 找面板 / 画提示时
			# 会把东西摆到这块藏起来的面板上（表现就是提示文字飘到别处）
			面板.ID = -1
			continue
		_填面板(面板, 玩家列表[(我的下标 + idx) % n])


## 把一名玩家的视图数据塞进一块面板（setter 的取值形状见 PlayerStatusMobile.gd）
func _填面板(面板: 战斗玩家面板, p: GPlayer) -> void:
	面板.set("ID", p.id)
	面板.set("NickName", p.nickname)
	# 未分队时不改队色（参考工程的 Team 只有蓝 0 / 红 1，没有「未分队」）
	if p.color != GConst.TEAM_NONE:
		面板.set("Team", p.color)
	面板.set("RoleID", p.role_id)
	# HandCount 的入参语义是 (手牌上限, 当前手牌)，见 PlayerStatusMobile.set_HandCount
	面板.set("HandCount", Vector2i(p.hand_cards_max, p.hand_cards_num))
	面板.set("HealCount", p.cross_num)
	# Energy 的入参语义是 (宝石, 水晶)，见 PlayerStatusMobile.set_Energy
	面板.set("Energy", Vector2i(p.gem, p.crystal))
	面板.set("Knelt", p.tap)
	# 状态图标：基础效果（牌）+ 独有效果（GConst.Exclusive 下标）
	var 基础牌: Array = []
	for st: GPlayer.BasicStatus in p.basic_status_list:
		if st.card != null:
			基础牌.append(st.card.id)
	面板.set("BasicAndExCards", 基础牌)
	var 独有效果: Array = []
	for i: int in range(GConst.EXCLUSIVE_NUM):
		if p.specials[i]:
			独有效果.append(i)
	面板.set("ExclusiveCards", 独有效果)
	# 指示物：槽 0/1/2 → 面板的 token0/1/2（那三个 setter 的名字沿用原客户端对三个槽的叫法）
	for slot: int in range(3):
		var 值: int = 0
		if p.tokens[slot] != null:
			值 = int((p.tokens[slot] as GPlayer.Token).num)
		match slot:
			0: 面板.set("YellowToken", 值)
			1: 面板.set("BlueToken", 值)
			2: 面板.set("Covered", 值)
	面板.set("Turn", p.id == _高亮玩家id)
	# 本步骤只显示：IsEnable（能否点选为目标）留待第三步交互时驱动
	面板.set("IsEnable", false)


func _on_turn(player_id: int, round_id: int) -> void:
	_当前回合 = player_id
	# 别人的回合刚开始：自己若还停在上一条询问上（超时后被服务端推进），先退回等待态
	if player_id != Logic.my_player_id and _mode != 0:
		_清空待选()
	TxtTurn.text = str(round_id)
	_高亮玩家(player_id)
	var p: GPlayer = Data.get_player_by_id(player_id)
	# 轮到这个角色就放他自己的语音；没有语音的角色（如 37 号）沿用界面提示音
	if p != null and Audio.有声效(str(p.role_id)):
		Audio.播音效(str(p.role_id))
	else:
		Art.play_sfx("It's your turn" if player_id == Logic.my_player_id else "TurnBegin")
	if p != null:
		_日志追加("第 %d 回合，轮到 %s" % [round_id, _称号(player_id)], "回合")


## 把某个玩家面板背后的 Turn 点亮（自己 / 别人都有）。
## 动画在 PlayerStatusMobile.TurnBegin() 里：Turn 贴图先放大再缩回（同参考工程的 DOScale）。
## 只在「高亮目标变了」时才播，否则每次对局快照刷新都会重新弹一下。
func _高亮玩家(player_id: int) -> void:
	if player_id == _高亮玩家id:
		return
	_高亮玩家id = player_id
	for 面板: 战斗玩家面板 in _面板列表:
		if 面板.ID == player_id:
			面板.TurnBegin()
		else:
			面板.Turn = false


# ============================================================
# 提示
# ============================================================
## 顶部提示：显示后 3 秒自动隐藏（参考脚本用 Timer + token 的做法）
func _提示(txt: String) -> void:
	TxtHint.text = txt
	TxtHint.visible = true
	Hint.visible = true
	_提示token += 1
	_当前提示token = _提示token
	if _提示计时器 == null:
		_提示计时器 = Timer.new()
		_提示计时器.name = "提示计时器"
		_提示计时器.one_shot = true
		_提示计时器.timeout.connect(_on_提示超时)
		add_child(_提示计时器)
	_提示计时器.start(提示停留秒)


func _on_提示超时() -> void:
	if _当前提示token == _提示token:
		Hint.visible = false


## 常驻指令提示：交互提示不该 3 秒后消失（同参考脚本的 Invoke("hideHint") 只用于弹窗消息）
func _指令提示(txt: String) -> void:
	# 让上一轮「自动隐藏」的倒计时作废
	_提示token += 1
	TxtHint.text = txt
	_自适应提示字号()
	TxtHint.visible = true
	Hint.visible = true


## 提示文案自适应：超过提示框宽度就按比例缩字号（长文案如「虚弱和束缚」也能完整显示一行），
## 放得下就还原成基础字号，避免上一条长文案把后面的短文案也缩着。
func _自适应提示字号() -> void:
	var 字体: Font = TxtHint.get_theme_font("font")
	if 字体 == null:
		return
	var 允许宽: float = maxf(Hint.size.x - 24.0, 120.0)
	var 字号: int = 提示基础字号
	while 字号 > 提示最小字号 and 字体.get_string_size(TxtHint.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 字号).x > 允许宽:
		字号 -= 1
	TxtHint.add_theme_font_size_override("font_size", 字号)


func _收起提示() -> void:
	_提示token += 1
	Hint.visible = false
	TxtHint.visible = false


func _on_error(_err_id: int, msg: String) -> void:
	_日志追加(msg, "提示")
	_提示(msg)


# ============================================================
# 屏幕中间的展示卡牌区（Root/ShowCardArea）
# ============================================================
## 展示停留秒数，到点自动收起
const 展示停留秒数: float = 1.6
## 卡牌视图预制体：和手牌同一个 Card.tscn（卡图 + 左上角命格/元素 + 底部字形与技能名1/2）
const 卡牌视图预制: PackedScene = preload("res://scenes/prefabs/battlemobile/Card.tscn")


## 把这几张牌摊到屏幕中间给所有人看；连着来第二拨时先把上一拨收掉
func _展示卡牌(卡号表: Array) -> void:
	_收起展示卡牌()
	for cid: Variant in 卡号表:
		var 卡: GCard = Data.get_card(int(cid))
		if 卡 == null:
			continue
		var 视图: Control = 卡牌视图预制.instantiate()
		# Card.tscn 的根节点本身是 0 尺寸的（手牌区是代码给尺寸的），
		# 塞进 GridContainer 必须显式给尺寸，否则列宽被算成 0、卡图就不画了
		视图.set_anchors_preset(Control.PRESET_TOP_LEFT)
		视图.custom_minimum_size = 手牌尺寸
		视图.size = 手牌尺寸
		ShowCardArea.add_child(视图)
		# 「可用」传 true 才是正常亮度（false 会把整张牌置灰）；展示只是给人看，顺手关掉「可选」发光框
		视图.call("设置卡牌", 卡, true)
		(视图.get("canSelectBorder") as TextureRect).visible = false
	await get_tree().create_timer(展示停留秒数).timeout
	_收起展示卡牌()


## 收掉当前摊出来的牌
func _收起展示卡牌() -> void:
	for 旧: Node in ShowCardArea.get_children():
		旧.queue_free()


# ============================================================
# 广播消息 → 日志 / 聊天
# ============================================================
func _on_card(msg: Dictionary) -> void:
	var src: int = int(msg.get("src_id", -1))
	var dst: int = int(msg.get("dst_id", -1))
	# 「给牌」不发牌面、也不进这里写日志（日志由服务端的 Gossip 写好了），
	# 只是要播一个「牌从甲飘到乙」的动效 —— 见 engine._log_give_cards
	if int(msg.get("type", 0)) == GConst.CardMsgType.Give:
		_给牌特效(src, dst, int(msg.get("count", 1)))
		return
	# 展示（亮牌/超限换牌）没有「对谁使用」的概念，单独写一行
	var 是展示: bool = int(msg.get("type", 0)) == GConst.CardMsgType.Show
	var names: Array[String] = []
	var 首张: GCard = null
	for cid: Variant in msg.get("card_ids", []):
		var c: GCard = Data.get_card(int(cid))
		if c != null:
			names.append(c.card_name)
			if 首张 == null:
				首张 = c
	# 出牌音效（对照参考项目 AudioManager 的 CARDMSG 分支）：攻击牌 atk-<系别>，法术牌 spell-<卡名>。
	# 这次出牌「视为」另一张牌时（msg.as_card_id，如地/火牌当【魔弹】打）按那张牌出声；
	# 摊牌与日志仍用真正打出的牌（card_ids）。
	var 表现牌: GCard = _视为牌(msg)
	if 表现牌 == null:
		表现牌 = 首张
	if 表现牌 != null and not 是展示:
		if 表现牌.is_attack():
			Audio.播音效("atk-" + 表现牌.element)
		else:
			Audio.播音效("spell-" + 表现牌.card_name)
	var 谁: String = _称号(src)
	var 目标: GPlayer = Data.get_player_by_id(dst)
	# 屏幕中间把牌摊出来（自己和其他人都看得到）。
	# 虚拟牌（如【欺诈】变出来的那张攻击牌，is_real=false）不摊牌，只播声音 / 特效 / 日志
	if bool(msg.get("is_real", true)):
		_展示卡牌(msg.get("card_ids", []))
	if 是展示:
		_日志追加("%s 展示：%s" % [谁, ", ".join(names)], "行动")
		return
	if 目标 == null or dst == src:
		_日志追加("%s 对自己打出：%s" % [谁, ", ".join(names)], "行动")
	else:
		_日志追加("%s 对 %s 打出：%s" % [谁, _称号(dst), ", ".join(names)], "行动")
	_播出手特效(src, dst, msg)


## 出手特效分发：这几种牌放专属粒子特效（打向别人时飞过去、对自己结算时原地炸开），
## 其它指向性牌退化成公用弹道。
func _播出手特效(src: int, dst: int, msg: Dictionary) -> void:
	if src < 0 or dst < 0:
		return
	var 牌号: int = _特效牌号(msg)
	if 牌号 >= 0:
		_粒子特效(src, dst, 牌号, dst != src)
	elif dst != src:
		_行动弹道(src, dst)


## 出手时放专属特效的牌 → 特效预制体（scenes/prefabs/effects/）
## 斩击类（水 / 火 / 地 / 风 / 雷 / 暗灭）是把 3D 斩击素材经 SubViewport 转成 2D 的预制体，见 scripts/effects/斩击2D.gd；
## 魔弹同样是把 3D 弹道素材经 SubViewport 转成 2D 的预制体，见 scripts/effects/魔弹2D.gd；
## 圣光是原生 2D 粒子（GPUParticles2D），见 scripts/effects/粒子特效.gd。
const 特效预制表: Dictionary = {
	GConst.CardName.WaterSlash: preload("res://scenes/prefabs/effects/水斩.tscn"),
	GConst.CardName.FireSlash: preload("res://scenes/prefabs/effects/火斩.tscn"),
	GConst.CardName.EarthSlash: preload("res://scenes/prefabs/effects/地斩.tscn"),
	GConst.CardName.WindSlash: preload("res://scenes/prefabs/effects/风斩.tscn"),
	GConst.CardName.ThunderSlash: preload("res://scenes/prefabs/effects/雷斩.tscn"),
	GConst.CardName.DarkSlash: preload("res://scenes/prefabs/effects/暗灭.tscn"),
	GConst.CardName.Missile: preload("res://scenes/prefabs/effects/魔弹.tscn"),
	GConst.CardName.HolyLight: preload("res://scenes/prefabs/effects/圣光.tscn"),
}


## 这次出牌「视为」的那张牌（Card 消息的 as_card_id）：值为 0 或查不到时返回 null。
## 地/火牌当【魔弹】打出去时这里是【魔弹】——音效、特效按它走；摊牌与日志仍用 card_ids。
func _视为牌(msg: Dictionary) -> GCard:
	var 视为号: int = int(msg.get("as_card_id", 0))
	if 视为号 <= 0:
		return null
	return Data.get_card(视为号)


## 这条 Card 消息该放哪张牌的特效：这次出牌「视为」另一张牌时放那张牌的特效
## （如地/火牌当【魔弹】打 → 放【魔弹】特效）；否则按打出的牌找。没有匹配返回 -1
func _特效牌号(msg: Dictionary) -> int:
	var 视为: GCard = _视为牌(msg)
	if 视为 != null and 特效预制表.has(视为.card_name_enum()):
		return 视为.id
	for raw: Variant in msg.get("card_ids", []):
		var 牌: GCard = Data.get_card(int(raw))
		if 牌 != null and 特效预制表.has(牌.card_name_enum()):
			return 牌.id
	return -1


## 出手特效：按卡名取专属预制体，放到出牌者 / 目标身上播一次。
## 飞行 = true 从出牌者飞向目标（攻击 / 应战反击 / 指向性法术）；
## 飞行 = false 在目标身上原地炸开（【圣光】抵挡：引擎广播的 src 与 dst 是同一人）。
func _粒子特效(src_id: int, dst_id: int, card_id: int, 飞行: bool) -> void:
	var 牌: GCard = Data.get_card(card_id)
	var 起点: 战斗玩家面板 = _玩家面板(src_id)
	var 终点: 战斗玩家面板 = _玩家面板(dst_id)
	if 牌 == null or 起点 == null or 终点 == null or Root == null:
		return
	var go: Node2D = (特效预制表[牌.card_name_enum()] as PackedScene).instantiate() as Node2D
	Root.add_child(go)
	go.call("播放", 起点.get_global_rect().get_center(), 终点.get_global_rect().get_center(), 飞行)


## 公用的出牌弹道：从出牌者面板飞一道粒子到目标面板（对照参考工程 BattleUIMobile.actionAnim）
func _行动弹道(src_id: int, dst_id: int) -> void:
	var 起点: 战斗玩家面板 = _玩家面板(src_id)
	var 终点: 战斗玩家面板 = _玩家面板(dst_id)
	if 起点 == null or 终点 == null or Root == null:
		return
	var ps: PackedScene = load(预制目录 + "Arrow.tscn")
	if ps == null:
		return
	var go: Node = ps.instantiate()
	Root.add_child(go)
	# 取面板中心（立绘所在处）而不是左上角：AnimationPos 在移植时退化成了面板自身
	var 起: Vector2 = 起点.get_global_rect().get_center()
	var 止: Vector2 = 终点.get_global_rect().get_center()
	go.call("SetParms", Vector3(起.x, 起.y, 0.0), Vector3(止.x, 止.y, 0.0))


## 给牌动效：卡背从交牌人飘到收牌人（牌面不公开），配一声给牌音效。
## 交几张就飞几张，每张沿贝塞尔弧线先后起飞，中间留一点间隔；音效只响一次（叠着响太吵）。
## 找人 / 找面板失败就不播（音效也不响，免得只听响不见牌）
func _给牌特效(src_id: int, dst_id: int, 张数: int) -> void:
	var 起点: 战斗玩家面板 = _玩家面板(src_id)
	var 终点: 战斗玩家面板 = _玩家面板(dst_id)
	if 起点 == null or 终点 == null or Root == null:
		return
	Audio.播音效("给牌")
	var 起: Vector2 = 起点.get_global_rect().get_center()
	var 止: Vector2 = 终点.get_global_rect().get_center()
	for i: int in range(maxi(张数, 1)):
		var 动效: 给牌2D = 给牌预制.instantiate() as 给牌2D
		Root.add_child(动效)
		动效.延迟时长 = 给牌间隔 * float(i)
		动效.播放(起, 止)


## 按玩家 id 找面板（找不到返回 null）
func _玩家面板(player_id: int) -> 战斗玩家面板:
	for 面板: 战斗玩家面板 in _面板列表:
		if 面板.ID == player_id:
			return 面板
	return null


func _on_hit(src_id: int, dst_id: int, hit: int) -> void:
	# 命中音（斩击 / 魔弹命中）：只在真命中时响（未命中不出声）
	if hit == 1:
		Audio.播音效("sys-hit")
	_日志追加("%s 对 %s 的攻击%s" % [
		_称号(src_id),
		_称号(dst_id),
		"命中" if hit == 1 else "未命中",
	], "伤害")


func _on_hurt(msg: Dictionary) -> void:
	var cause: int = int(msg.get("cause", 0))
	# 攻击命中 / 魔弹命中只响「命中音」sys-hit，不再叠受伤音：攻击命中的那声在 _on_hit 里播过，
	# 魔弹没有命中判定，在这里补；其余来源（法术 / 技能）没有命中判定，响「受伤音」sys-hurt
	if cause == GConst.CAUSE_MISSILE:
		Audio.播音效("sys-hit")
	elif cause != GConst.CAUSE_ATTACK:
		Audio.播音效("sys-hurt")
	var dst: int = int(msg.get("dst_id", -1))
	var src: int = int(msg.get("src_id", -1))
	# 受击表现（泛红 / 抖动 / 卡肉）由被打的面板自己播；画面扭曲震荡波只在「斩命中 / 魔弹命中」时叠
	var 受击面板: 战斗玩家面板 = _玩家面板(dst)
	if 受击面板 != null:
		受击面板.Hurted(cause == GConst.CAUSE_ATTACK or cause == GConst.CAUSE_MISSILE)
	_日志追加("%s 对 %s 造成 %d 点%s伤害" % [
		_称号(src),
		_称号(dst),
		int(msg.get("hurt", 0)),
		"法术" if int(msg.get("type", 0)) == GConst.HarmType.Magic else "攻击",
	], "伤害")


func _on_skill(msg: Dictionary) -> void:
	var src: int = int(msg.get("src_id", -1))
	# 技能全称带分类，如「发动【独有技·响应】疾风技」（对照设计表「技能表」的派系/类型列）
	_日志追加("%s 发动%s" % [
		_称号(src),
		GConst.skill_title(int(msg.get("skill_id", 0))),
	], "行动")


## 玩家发言：既进日志，也在聊天区加一条
func _on_gossip(txt: String) -> void:
	_日志追加(txt, "聊天")
	_加聊天(txt)
	_判胜负(txt)


## 系统公告（超时 / 掉线 / 重连 / 终局等）：只进日志，不进聊天区；按 kind 取 [类别] 标签
func _on_notice(txt: String, kind: int = 0) -> void:
	_日志追加(txt, _日志标签(kind))
	_判胜负(txt)


## 聊天条目：ChatItem.tscn（挂 ChatItem.gd，有 set_Msg / set_IsMainPlayer）
func _加聊天(txt: String) -> void:
	var ps: PackedScene = load(预制目录 + "ChatItem.tscn")
	if ps == null:
		return
	var go: Node = ps.instantiate()
	if go is Control:
		(go as Control).position = Vector2.ZERO
		(go as Control).scale = Vector2.ONE
	Content.add_child(go)
	go.call("set_Msg", txt)
	go.call("set_IsMainPlayer", false)


## 日志里称呼玩家的统一写法：角色名[玩家名]（取不到玩家时退化为 id）
func _称号(player_id: int) -> String:
	var p: GPlayer = Data.get_player_by_id(player_id)
	if p == null:
		return str(player_id)
	return "%s[%s]" % [p.nickname, p.role_name]


## 给日志正文里的玩家名与卡名单独上色（其余仍是白字）。
## 放在 _日志追加 里统一处理：客户端自己拼的行与服务端下发的公告都能着色。
func _日志着色(t: String) -> String:
	var 结果: String = t
	# 玩家：整段「玩家名[角色名]」一起染（与 _称号 的写法一致）
	for p: GPlayer in Data.player_list:
		var 称号: String = "%s[%s]" % [p.nickname, p.role_name]
		if 结果.find(称号) >= 0:
			结果 = 结果.replace(称号, "[color=%s]%s[/color]" % [日志玩家色, 称号])
	# 卡名：长名先替，避免短名（如「圣光」）把长名切碎而留下半边未着色
	var 卡名表: Array[String] = []
	for 卡: GCard in Data.card_db:
		if not 卡.card_name.is_empty() and not 卡名表.has(卡.card_name):
			卡名表.append(卡.card_name)
	卡名表.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
	for 名: String in 卡名表:
		if 结果.find(名) >= 0:
			结果 = 结果.replace(名, "[color=%s]%s[/color]" % [日志卡牌色, 名])
	# 「自身」代指发起者自己，也按玩家名的颜色染（服务端的治疗等日志用它）
	结果 = 结果.replace("自身", "[color=%s]自身[/color]" % 日志玩家色)
	# 星石：宝石红、水晶蓝（正文里凡提到星石都上色）
	结果 = 结果.replace("宝石", "[color=%s]宝石[/color]" % 日志宝石色)
	结果 = 结果.replace("水晶", "[color=%s]水晶[/color]" % 日志水晶色)
	# 技能名 / 状态名外面的【】统一去掉（日志里有的带、有的不带，看着不齐）
	结果 = 结果.replace("【", "").replace("】", "")
	return 结果


## 日志：攒进缓冲后交给 Content_2 上的 AutoClearLog 按行裁剪。
## 每行形如「[color=标签色][类别][/color][color=白]正文[/color]」——
## 开头的 [类别] 带颜色标识类型，正文一律白字，其中的玩家名与卡名单独上色
## （日志控件是 RichTextLabel，支持 BBCode）
func _日志追加(t: String, 标签: String = "系统") -> void:
	var 色: String = str(日志标签色.get(标签, 日志标签色["系统"]))
	_日志 += "[color=%s][%s][/color][color=%s] %s[/color]\n" % [色, 标签, 日志正文色, _日志着色(t)]
	if Content_2.has_method("AutoClearText"):
		Content_2.call("AutoClearText", _日志, 日志最大行)
	else:
		Content_2.text = _日志


# ============================================================
# 结算 / 返回
# ============================================================
## 从公告文本里认「获胜」两个字：本项目没有单独的终局信号
func _判胜负(txt: String) -> void:
	if _胜负已定 or not txt.contains("获胜"):
		return
	var 胜方: int = GConst.RED if txt.contains("红") else (GConst.BLUE if txt.contains("蓝") else GConst.TEAM_NONE)
	_结算(胜方)


## 结算：胜负音乐 + 结算面板（只做一次）
func _结算(胜方: int) -> void:
	if _胜负已定 or 胜方 == GConst.TEAM_NONE:
		return
	_胜负已定 = true
	var me: GPlayer = Data.get_player_by_id(Logic.my_player_id)
	var 胜: bool = me != null and me.color == 胜方
	# 胜负切音乐（对照参考项目 AudioManager：Win/Lose → play_bgm_scene(2, 胜否)）
	Audio.播放音乐(Audio.场景战斗, 胜)
	EndTxt.text = "胜利" if 胜 else "失败"
	# WinPanel 及其子节点在场景里都是 visible=false，展开时一并打开
	# （同参考脚本 _show_win_children 的处理）
	WinPanel.visible = true
	EndTxt.visible = true
	BtnBack.visible = true
	_日志追加("游戏结束：%s" % ("红队获胜" if 胜方 == GConst.RED else "蓝队获胜"), "系统")


## 返回大厅
func _on_back() -> void:
	Logic.leave_room()
	UI.goto_lobby()


# ============================================================
# 聊天输入
# ============================================================
func _on_submit() -> void:
	var txt: String = InputField.text.strip_edges()
	if txt == "":
		return
	InputField.text = ""
	Logic.talk(txt)


# ============================================================
# 日志 / 聊天面板展开、收起（同参考脚本 onBtnLogExpandClick / onBtnChatExpandClick）
# ============================================================
## 日志面板展开/收起：面板位置在场景里就已排好（LogRoot 锚在右边缘、offset_left = -面板宽，
## 所以它一直贴在右侧、开合只靠显隐）。参考工程那套 ±宽/2 是 Unity 的 anchoredPosition
## 语义，搬进 Godot 的 position 里算出来是错的，这里不再搬。
## 展开时滚到最新一条（滚到底）。
func _展开日志() -> void:
	LogRoot.visible = not LogRoot.visible
	if LogRoot.visible:
		# 面板收起时宽度没定死，日志高度会按 0 宽换行量得偏大、底下拖出一片空白。
		# 先等一帧让可见后的宽度算定，再让日志按新宽度重新量一次高度，最后滚到底。
		await get_tree().process_frame
		Content_2.call("AutoClearText", _日志, 日志最大行)
		await get_tree().process_frame
		MsgRoot.scroll_vertical = 1 << 30


## 聊天面板展开/收起：同日志面板 —— 位置在场景里排好（ChatRoot_ 锚在左边缘、占左侧 641px），
## 开合只靠显隐。原来那套 ±宽/2 是照搬 Unity 的 anchoredPosition，在 Godot 里算出来跑到屏幕中间。
func _展开聊天() -> void:
	ChatRoot.visible = not ChatRoot.visible


# ============================================================
# 第三步：交互层（手牌 / 选目标 / 确定 / 取消 / 放弃 / 技能）
# 状态机与判定照参考工程搬来的桌面战斗界面，渲染换成新界面的控件。
# 音频仍下一步统一搬。
# ============================================================

# ---------------- 收到服务端询问 ----------------
func _on_command(data: Dictionary) -> void:
	var cmds: Array = data.get("commands", [])
	if cmds.is_empty():
		return
	# 每次询问先清掉上一轮的技能按钮，避免残留
	_清空技能按钮()
	# 上一条询问可能已经作废（典型的：弹窗还开着的时候自己超时，服务端径自跳过）：
	# 先把居中选项窗关掉再处理新询问，等同于点「取消」——旧询问不再提交
	参数选择窗.visible = false
	_参数选择_技能 = false
	_参数选择_额外行动 = false
	_弹窗选项.clear()
	_弹窗标题 = ""
	# 上一条询问的选牌约束也一并复位：新询问若根本不用选牌（如额外行动询问【神圣追击】），
	# 不能沿用上一条的「最多 1 张 / 只能选法术牌」（【英灵召唤】），否则手牌会亮错。
	# 需要选牌的分支（技能询问 / 发动技能 / 点选行动）都会自己把这几项重新设好
	_skill_ask_id = -1
	_是技能询问 = false
	_本地询问 = false
	_额外行动单选 = -1
	_额外行动可选 = true
	_skill_ask_need_card = 0
	_skill_ask_need_target = 0
	_skill_card_max = 0
	_skill_card_rule = ""
	_skill_card_source = GConst.CardSource.Hand
	_skill_cards.clear()
	_skill_targets.clear()
	_selecting_cover = false
	_need_cards = 0
	_need_players = 0
	var cmd: Dictionary = cmds[0]
	var cmd_type: int = int(data.get("cmd_type", 0))
	var respond_id: int = int(cmd.get("respond_id", 0))
	if cmd_type == GConst.CmdType.Action:
		# 行动询问：第一项是通用行动，其余是角色可选技能
		if int(cmd.get("src_id", -1)) != Logic.my_player_id:
			return
		# 允许「放弃行动」时服务端会额外下发一条 ACTION_NONE 命令（被挑衅 / 额外行动阶段）
		_行动允许 = respond_id
		_可放弃行动 = false
		for c: Dictionary in cmds:
			if int(c.get("respond_id", 0)) == GConst.ActionType.None:
				_可放弃行动 = true
				break
		_构建技能按钮(cmds)
	else:
		# 服务端显式标记 is_skill 的才是「是否发动某技能」的技能询问
		if bool(cmd.get("is_skill", false)):
			if int(cmd.get("src_id", -1)) != Logic.my_player_id:
				return
			_是技能询问 = true
			_skill_ask_id = respond_id
			_pending = cmd
			_pending_type = GConst.Msg.Respond
			_进入技能询问()
			return
		var args: Array = cmd.get("args", [])
		var target_id: int = -1
		if respond_id == GConst.RespondType.ReplyAttack and args.size() > 2:
			target_id = int(args[2])
		elif respond_id == GConst.RespondType.Discard or respond_id == GConst.RespondType.DiscardCover:
			target_id = int(args[0]) if args.size() > 0 else -1
		elif respond_id == GConst.RespondType.Weaken or respond_id == GConst.RespondType.Heal:
			target_id = int(args[0]) if args.size() > 0 else -1
		elif respond_id == GConst.RespondType.Bullet:
			# 魔弹传递询问：args[0] = 当前持有者（也就是该由谁来应答）
			target_id = int(args[0]) if args.size() > 0 else -1
		elif respond_id == GConst.RespondType.AdditionalAction:
			_进入额外行动(args, cmd.get("dst_ids", []))
			return
		if target_id != Logic.my_player_id:
			return
	_pending = cmd
	_pending_type = GConst.Msg.Action if cmd_type == GConst.CmdType.Action else GConst.Msg.Respond
	_进入待选()


## 进入待选状态（行动 / 各种响应）：决定要选几张牌、几个目标，并写提示
func _进入待选() -> void:
	_sel_cards.clear()
	_sel_players.clear()
	_重置治疗分配()
	# 来了新询问：技能说明窗先收起来，别盖住操作
	英雄详情窗.visible = false
	_skill_targets.clear()
	_skill_cards.clear()
	_skill_card_rule = ""
	_弹窗选项.clear()
	_弹窗标题 = ""
	_mode = 0
	_selecting_cover = false
	var respond_id: int = int(_pending.get("respond_id", 0))
	var args: Array = _pending.get("args", [])
	if _pending_type == GConst.Msg.Action:
		# 行动阶段
		_mode = 1
		_need_cards = 1
		_need_players = 0
		# 额外行动（【疾风技】【不屈意志】【戒骄戒躁】等给的行动）不写「轮到你了」，按本阶段放行的种类点名
		if bool(_pending.get("is_extra", false)):
			match respond_id:
				GConst.ActionType.Attack, GConst.ActionType.AttackSkill:
					_指令提示("获得额外攻击行动")
				GConst.ActionType.Magic, GConst.ActionType.MagicSkill:
					_指令提示("获得额外法术行动")
				_:
					_指令提示("获得额外行动")
		else:
			_指令提示("轮到你行动了")
	else:
		match respond_id:
			GConst.RespondType.ReplyAttack:
				_mode = 2
				_need_cards = 1
				# 应战要指定「反击目标」（敌方、且不是原攻击者）
				_need_players = 1
				if _可应战():
					_指令提示("打出同系斩应战 或 【圣光】抵挡，或取消放弃")
				else:
					_指令提示("无法应战：出【圣光】抵挡，或取消放弃")
			GConst.RespondType.Discard:
				_mode = 2
				_need_cards = int(args[2]) if args.size() > 2 else 1
				_指令提示(_弃牌提示(int(args[1]) if args.size() > 1 else -1, _need_cards))
			GConst.RespondType.DiscardCover:
				# 盖牌超限（对照服务端 StateRequestCover）：从盖牌区选牌弃掉
				_mode = 2
				_selecting_cover = true
				_need_cards = int(args[2]) if args.size() > 2 else 1
				_指令提示("盖牌超限：请从盖牌区选择 %d 张牌弃掉" % _need_cards)
			GConst.RespondType.Weaken:
				_mode = 2
				_need_cards = 0
				# args: [目标, 应摸总数, 束缚摸牌数, 虚弱牌数]；只中了哪个就说哪个，两个都有才写「和」
				var 强摸: int = int(args[1]) if args.size() > 1 else 0
				var 有束缚: bool = (int(args[2]) if args.size() > 2 else 0) > 0
				var 有虚弱: bool = (int(args[3]) if args.size() > 3 else 0) > 0
				var 状态名: String = "虚弱和束缚" if (有虚弱 and 有束缚) else ("虚弱" if 有虚弱 else "束缚")
				_指令提示("你被%s了：点「确定」强摸 %d 张牌，或点「取消」直接结束回合" % [状态名, 强摸])
			GConst.RespondType.Heal:
				_mode = 2
				_need_cards = 0
				# args: [目标, 伤害点数, 伤害类型, 可抵御上限]；文案按类型说「攻击 / 法术」（对照原版 Role::cure）
				var 伤害点数: int = int(args[1]) if args.size() > 1 else 0
				var 伤害类型: int = int(args[2]) if args.size() > 2 else GConst.HarmType.Magic
				var 抵御上限: int = int(args[3]) if args.size() > 3 else 0
				var 类型名: String = "攻击" if 伤害类型 == GConst.HarmType.Attack else "法术"
				var 抵: int = mini(伤害点数, 抵御上限)
				_skill_ask_id = respond_id
				_弹窗选项.clear()
				_弹窗标题 = ""
				if 抵 > 0:
					# 用居中弹窗列出「不抵挡 / 用几点治疗抵挡」：与【神之庇护】同一套交互
					_弹窗标题 = "用几点治疗抵挡本次 %d 点%s伤害？（最多 %d 点）" % [伤害点数, 类型名, 抵]
					_弹窗选项.append({"text": "不用治疗（承受全部伤害）", "args": [0]})
					for n: int in range(1, 抵 + 1):
						_弹窗选项.append({"text": "用 %d 点治疗抵挡" % n, "args": [n]})
				else:
					_指令提示("是否用治疗抵挡本次 %d 点%s伤害？（点「确定」使用）" % [伤害点数, 类型名])
			GConst.RespondType.Bullet:
				_mode = 2
				_need_cards = 1
				_指令提示("魔弹传递：出【魔弹】继续传递（选好牌后点亮起的敌人头像）、出【圣光】抵挡，或点「取消」承受伤害")
			_:
				_mode = 2
				_need_cards = 0
	_刷新交互()
	# 这次询问若是「弹窗型」（治疗抵挡几点），进完状态就把居中的选项窗弹出来
	if not _弹窗选项.is_empty():
		_弹出参数选项(_弹窗标题, _弹窗选项)


## 被要求弃牌时的指令提示：按原因（应答 args[1] = cause）说清为什么弃牌。
## CAUSE_OVERLOAD＝手牌超限；下发的是技能号（如【灵符－风行】逼别人弃牌）就点名那个技能；
## 认不出来的（CAUSE_USE 之类牌的效果）只说「请弃牌」—— 不能一律写成「手牌超限」，
## 那样没超限的场合文案就明显是错的
func _弃牌提示(cause: int, 张数: int) -> String:
	if cause == GConst.CAUSE_OVERLOAD:
		return "手牌超限：请选择 %d 张牌弃掉" % 张数
	if not GConst.技能行(cause).is_empty():
		return "【%s】：请选择 %d 张牌弃掉" % [GConst.skill_name(cause), 张数]
	return "请选择 %d 张牌弃掉" % 张数


## 是否发动技能的询问：确定=发动，取消=放弃
## args 编码：args[0]=需选牌 args[1]=需选目标 args[2]=选盖牌 args[3]=选项数 args[4..]=选项值
## 选项文案在命令的 notes 里；有选项时改为渲染选项按钮，点哪个就回哪个值
func _进入技能询问() -> void:
	_mode = 3
	var args: Array = _pending.get("args", [])
	_skill_ask_need_card = int(args[0]) if args.size() > 0 else 0
	_skill_ask_need_target = int(args[1]) if args.size() > 1 else 0
	_skill_ask_card_source = int(args[2]) if args.size() > 2 else GConst.CardSource.Hand
	_skill_ask_can_cancel = bool(_pending.get("can_cancel", true))
	# card_max 给了就放宽点选上限（如【法术反弹】弃 1~N 张同系牌）；没给就是刚好 need_card 张
	_skill_card_max = maxi(_skill_ask_need_card, int(_pending.get("card_max", 0)))
	_skill_card_rule = str(_pending.get("card_rule", ""))
	_skill_card_source = _skill_ask_card_source
	# 「目标上限随选牌数变化」与「逐张选牌条件」只用于发动技能（mode 4）；询问这条通道不认它们，清零免得串味
	_skill_target_max_from_cards = 0
	_skill_slot_skill = 0
	_skill_slot_element = 0
	# 服务端给了合法牌白名单就只让这几张可点（如【魔能反转】只能弃法术牌）
	_skill_cards.clear()
	for 合法牌id: Variant in _pending.get("card_ids", []):
		_skill_cards.append(int(合法牌id))
	# 服务端给了合法目标白名单就只让这几名玩家可点（如【天使之歌】只能选面前有基础效果的人）；空＝不限制
	_skill_targets.clear()
	for 合法目标id: Variant in _pending.get("dst_ids", []):
		_skill_targets.append(int(合法目标id))
	# 复用 _need_cards 驱动点选上限与「确定」可用性
	_need_cards = _skill_card_max
	_need_players = _skill_ask_need_target
	var 选项数: int = int(args[3]) if args.size() > 3 else 0
	_skill_options.clear()
	for i: int in range(选项数):
		if args.size() > 4 + i:
			_skill_options.append(int(args[4 + i]))
	# 只有「从盖牌区选牌」的技能询问才把盖牌区亮出来（HandAndBasicEffect 的手牌整片置灰，与盖牌无关）
	_selecting_cover = _skill_ask_card_source == GConst.CardSource.Cover \
			or _skill_ask_card_source == GConst.CardSource.HandOrCover
	_sel_cards.clear()
	_sel_players.clear()
	_重置治疗分配()
	_清空技能按钮()
	# 只选一个参数、不用选牌选目标的询问（如【神之庇护】抵消几点）改用居中的参数选择窗：
	# 在技能区摆一排按钮看着像在问「是否发动」，弹窗才说得清「在问什么、有哪些选择」
	_弹窗选项.clear()
	_弹窗标题 = ""
	if not _skill_options.is_empty() and _skill_ask_need_card <= 0 and _skill_ask_need_target <= 0:
		_弹窗标题 = "【%s】请选择" % GConst.skill_name(_skill_ask_id)
		var notes: Array = _pending.get("notes", [])
		for i: int in range(_skill_options.size()):
			var 名: String = str(notes[i]) if i < notes.size() and str(notes[i]) != "" else str(_skill_options[i])
			_弹窗选项.append({"text": 名, "args": [int(_skill_options[i])]})
	# 「先弹选项」型（技能指示器配了「先弹选项」，如【百鬼夜行】）：先把居中的效果选择窗弹出来。
	# 窗里只记下选了哪一项效果、不提交；选完再选牌 / 选目标，按「确定」才把该项 args 一起上交。
	# 选效果之前目标数按 0 处理（头像点不动），选完再按「选项目标数」重设目标数
	var 指示配置: Dictionary = GConst.技能指示器.get(_skill_ask_id, {})
	_先弹选项 = bool(指示配置.get("先弹选项", false)) \
			and not _skill_options.is_empty() and _弹窗选项.is_empty()
	_已选参数.clear()
	if _先弹选项:
		# 选效果之前头像点不动（目标数按 0 处理）；服务端原本给的目标数先记下，选完效果再还原
		_选项原始目标数 = _skill_ask_need_target
		_skill_ask_need_target = 0
		_need_players = 0
	# 技能询问同时写一行日志：它只挂在提示条上，错过就会一直等（看着像「点了确定没反应」）
	# 被问的人看到的应是「要我做什么」：服务端下发了技能表「提示」列里对应的那一条
	# （谁交给谁、几张）就直接用它，否则才退回「是否发动【X】？」
	# 弹窗型询问（【军神威光】/【神之庇护】）例外：弹出选项只代表「要你选一个效果」，
	# 选中之前都还没发动，日志里不能写「发动【X】」——那句要等服务端广播技能通知时才出现
	var 询问文案: String = str(_pending.get("ask_text", ""))
	if not _弹窗选项.is_empty() or _先弹选项:
		_日志追加("【%s】请在弹出的选项里选择" % GConst.skill_name(_skill_ask_id), "行动")
	elif not 询问文案.is_empty():
		_日志追加(询问文案, "行动")
	else:
		_日志追加("【%s】等你决定" % GConst.skill_name(_skill_ask_id), "行动")
	var 指示提示: String = str(指示配置.get("提示", ""))
	if _先弹选项:
		_指令提示("【%s】请先在弹窗里选择效果" % GConst.skill_name(_skill_ask_id))
	elif not _弹窗选项.is_empty():
		_指令提示(_弹窗标题)
	elif not 询问文案.is_empty():
		_指令提示(询问文案)
	elif not 指示提示.is_empty():
		_指令提示(指示提示)
	elif not _skill_options.is_empty():
		var 选牌提示: String = "先选好需要的牌/目标，再点下面的选项"
		if _selecting_cover:
			选牌提示 += "（盖牌在盖牌区可点选）"
		_指令提示("【%s】：%s" % [GConst.skill_name(_skill_ask_id), 选牌提示])
	elif _skill_ask_card_source == GConst.CardSource.HandAndBasicEffect:
		_指令提示("【%s】：点一名面前有基础效果的角色，按「确定」后选择要移除的效果" % GConst.skill_name(_skill_ask_id))
	elif _selecting_cover:
		_指令提示("【%s】：请从盖牌区中选择一张" % GConst.skill_name(_skill_ask_id))
	elif not _skill_ask_can_cancel:
		_指令提示("【%s】：请%s%s，选好后点「确定」（本次必须执行，不能取消）" % [
			GConst.skill_name(_skill_ask_id),
			"（需选牌）" if _skill_ask_need_card > 0 else "",
			"（需选目标）" if _skill_ask_need_target > 0 else "",
		])
	else:
		_指令提示("是否发动【%s】？%s%s" % [
			GConst.skill_name(_skill_ask_id),
			"（需选牌）" if _skill_ask_need_card > 0 else "",
			"（需选目标）" if _skill_ask_need_target > 0 else "",
		])
	_刷新交互()
	# 选项按钮与上面的提示分支不互斥：技能表给这个技能配了「提示」文案时也要把按钮摆出来，
	# 否则玩家只看到一句提示、没有可点的地方（只剩「确定」）。
	# 「先弹选项」型的选项摆在弹窗里，不用再在技能区摆一排
	if _弹窗选项.is_empty() and not _先弹选项 and not _skill_options.is_empty():
		_构建选项按钮(_skill_options, _pending.get("notes", []))
	# 弹窗型询问（【神之庇护】抵消几点）：把居中的选项窗弹出来。
	# 独立于上面的提示分支——技能表配了「提示」文案时提示条会被它占用，弹窗照样要出来
	if not _弹窗选项.is_empty():
		_弹出参数选项(_弹窗标题, _弹窗选项)
	elif _先弹选项:
		_弹出效果选项()


## 「先弹选项」型询问（如【百鬼夜行】）的效果选择窗：选项文案取服务端 notes、值取服务端下发的那串选项。
## 窗里选一项只记下效果，不提交；关窗后由玩家选牌 / 选目标，再按「确定」把这项 args 一起上交。
## 这类询问是否显示「取消」按服务端下发的 can_cancel：不可取消的（如【百鬼夜行】）必须选一项；
## 可取消的（如【剑气斩】）点「取消」＝这次不发动
func _弹出效果选项() -> void:
	var notes: Array = _pending.get("notes", [])
	var 选项: Array = []
	for i: int in range(_skill_options.size()):
		var 名: String = str(notes[i]) if i < notes.size() and str(notes[i]) != "" else str(_skill_options[i])
		选项.append({"text": 名, "args": [int(_skill_options[i])]})
	_参数选择_技能 = true
	参数选择窗.打开("【%s】请选择效果" % GConst.skill_name(_skill_ask_id), 选项, _skill_ask_can_cancel)
	_更新按键()


## 「先弹选项」型：效果选定后把该项要求的目标数放进本次询问（【百鬼夜行】展示＝2 人、不展示＝1 人），
## 并刷新提示与可点状态 —— 之后玩家选牌 / 选目标，按「确定」提交。
## 发动技能（mode 4，如【死亡之触】）还要还原选效果前临时清零的需牌 / 目标数
func _应用选项目标数() -> void:
	var 技能号: int = _pending_skill_id if _mode == 4 else _skill_ask_id
	var 配置: Dictionary = GConst.技能指示器.get(技能号, {})
	var 表: Dictionary = 配置.get("选项目标数", {})
	# 该效果配了目标数就按它，没配就还原原本给的目标数（如【剑气斩】固定 1 名）
	var 目标数: int = _选项原始目标数
	if not _已选参数.is_empty() and 表.has(int(_已选参数[0])):
		目标数 = int(表[int(_已选参数[0])])
	if _mode == 4:
		_skill_need_card = _选项原始需牌
		_skill_card_max = _选项原始最多牌
		_need_cards = _skill_card_max
		_skill_need_target = 目标数
		_skill_target_max = maxi(目标数, _选项原始最多目标)
		_need_players = 目标数
		_指令提示("发动【%s】：%s%s点「确定」" % [
			GConst.skill_name(技能号), _需选牌提示(_skill_need_card), _需选目标提示(_skill_need_target),
		])
		_刷新交互()
		return
	_skill_ask_need_target = 目标数
	_need_players = _skill_ask_need_target
	var 片段: Array[String] = []
	if _skill_ask_need_card > 0:
		片段.append("选%d张盖牌" % _skill_ask_need_card if _skill_ask_card_source == GConst.CardSource.Cover
			else "选%d张牌" % _skill_ask_need_card)
	if _skill_ask_need_target > 0:
		片段.append("选%d名目标" % _skill_ask_need_target)
	_指令提示("【%s】：%s，选好后点「确定」发动" % [GConst.skill_name(_skill_ask_id), "、".join(片段)])
	_刷新交互()


## 额外行动询问：把每个可选 cause 变成一个按钮
func _进入额外行动(causes: Array, 可发动: Array) -> void:
	_mode = 3
	_是技能询问 = false
	_skill_ask_id = -1
	_额外行动单选 = -1
	_额外行动可选 = true
	_pending = {"args": causes}
	_pending_type = GConst.Msg.Respond
	_sel_cards.clear()
	_sel_players.clear()
	_清空技能按钮()
	if causes.size() == 1:
		# 只有一份额外行动：不摆「选项」按钮，直接问「是否发动？」——
		# 「确定」按引擎下发的「可发动」置灰与否（如手里没风系攻击牌时的【风怒追击】），「取消」始终可点
		_额外行动单选 = int(causes[0])
		_额外行动可选 = 可发动.has(_额外行动单选)
		_指令提示("是否发动【%s】？" % GConst.skill_name(_额外行动单选))
	else:
		# 多份额外行动（如剑圣【风怒追击】+【剑影】）：弹居中的选择窗来问，不在技能区摆两个按钮
		var 选项: Array = []
		for cause: Variant in causes:
			var c: int = int(cause)
			选项.append({"text": GConst.skill_name(c), "args": [c], "可用": 可发动.has(c)})
		_参数选择_额外行动 = true
		参数选择窗.打开("请选择要发动的额外行动", 选项)
		_指令提示("有额外行动可用，请选择")
	_刷新交互()


## 技能询问的选项按钮：每个可选值一个按钮，点击即回复该值
## （留在技能区，适用于还要同时选牌/选目标的询问；纯选参数的询问走 _弹出参数选项）
## 提示条文案由调用方决定（技能表配了「提示」就用它），这里只管摆按钮
func _构建选项按钮(values: Array[int], labels: Array) -> void:
	_清空技能按钮()
	for i: int in range(values.size()):
		var v: int = values[i]
		var label: String = str(labels[i]) if i < labels.size() and str(labels[i]) != "" else GConst.skill_name(v)
		_加文本按钮(label, _选择技能选项.bind(v))


## 行动询问里附带的技能 → 生成技能按钮
func _构建技能按钮(cmds: Array) -> void:
	# 存一份，取消技能 / 取消特殊行动时要把这批技能按钮重新摆回来
	_行动命令 = cmds
	for i: int in range(1, cmds.size()):
		var c: Dictionary = cmds[i]
		var 技能类型: int = int(c.get("respond_id", 0))
		# 本阶段不放行的技能不摆（额外攻击行动里法术技能也会亮，点了必被服务端拒）
		if not GConst.放行动作(技能类型, _行动允许):
			continue
		var args: Array = c.get("args", [])
		if args.is_empty():
			continue
		var 技能号: int = int(args[0])
		var 需牌: int = int(args[1]) if args.size() > 1 else 0
		var 需目标: int = int(args[2]) if args.size() > 2 else 0
		var 最多目标: int = int(args[3]) if args.size() > 3 else 0
		var 选牌来源: int = int(args[4]) if args.size() > 4 else GConst.CardSource.Hand
		var 合法目标: Array = c.get("dst_ids", [])
		var 合法牌: Array = c.get("card_ids", [])
		var 最多牌: int = int(c.get("card_max", 0))
		var 目标上限减牌数: int = int(c.get("target_max_from_cards", 0))
		var 选牌规则: String = str(c.get("card_rule", ""))
		var 首张技能: int = int(c.get("card_slot_skill", 0))
		var 次张系别: int = int(c.get("card_slot_element", 0))
		var 参数选项: Array = c.get("arg_choices", [])
		var go: Node = 技能预制.instantiate()
		if go is Control:
			(go as Control).custom_minimum_size = 技能尺寸
		ChildrenSkillArea.add_child(go)
		go.call("设置技能", 技能号)
		go.connect("点击", _选择技能.bind(技能类型, 需牌, 需目标, 合法目标, 合法牌, 最多牌,
			最多目标, 目标上限减牌数, 选牌来源, 选牌规则, 首张技能, 次张系别, 参数选项, go))
		_技能按钮.append(go)
		_显示技能区()


# ---------------- 点选 ----------------
func _on_card_clicked(card_id: int) -> void:
	# 置灰（不可用）的牌不做任何响应，也不弹提示
	if not _卡牌能点(card_id):
		return
	if _sel_cards.has(card_id):
		_sel_cards.erase(card_id)
	else:
		if _need_cards > 0 and _sel_cards.size() >= _need_cards:
			_sel_cards.clear()
		_sel_cards.append(card_id)
	# 换了牌，先前选中的目标可能不再合法（例如法术→攻击牌后队友不能再打），顺手清掉。
	# 但「点头像分配」型指示器技能的目标由分配自己管（如【辉耀】进场就全员选中、【惩戒】点头像选），
	# 不随牌变化，别在这里清掉（否则选完牌指示器就暗了）；
	# 目标已锁死的（【瘟疫】/【剧毒新星】自动选全体）同理：换牌不许动这批目标
	if _分配配置().is_empty() and not _目标锁死:
		for pid: int in _sel_players.duplicate():
			if not _玩家可选(pid):
				_sel_players.erase(pid)
	刷新手牌()
	刷新盖牌()
	# 换了牌就要重算「哪些敌人能打」：攻击牌选出后目标才亮
	刷新选中面板()
	_更新按键()


func _on_player_pressed(面板: 战斗玩家面板) -> void:
	_on_player_clicked(面板.ID)


## 点玩家面板：只有亮起（_玩家可选）的玩家点得动；攻击 / 应战选中即出手，其余先累积选择再按「确定」。
## 点不动的时候（不是该选目标的时机 / 他不是合法目标）＝看他这名角色的技能说明
## （对照参考工程 PlayerStatusMobile.onClick：不可选就走 onLongPress → 打开英雄详情窗）
func _on_player_clicked(player_id: int) -> void:
	# 目标已锁死（【瘟疫】/【剧毒新星】自动选全体）：点头像什么都不做，也不弹角色说明
	if _目标锁死:
		return
	if not _玩家可选(player_id):
		# 效果选择窗（【百鬼夜行】）还开着时点谁都不弹角色说明：先把效果选完
		if _先弹选项 and _已选参数.is_empty():
			return
		_弹出角色技能说明(player_id)
		return
	# 点头像分配型：点一次给该角色加「每次」点治疗（配置允许时可重复点同一人），分满后确定
	if not _分配配置().is_empty():
		_点治疗目标(player_id)
		return
	# 攻击：选好攻击牌后点敌方头像就直接打出去，不用再按「确定」
	if _mode == 1 and _选中是攻击牌():
		_发送行动(GConst.ActionType.Attack, 0, [player_id], _sel_cards, [])
		return
	# 法术：选好法术牌后点目标就直接释放（不点目标＝对自己，那条走「确定」）
	if _mode == 1 and _选中是法术牌():
		_发送行动(GConst.ActionType.Magic, 0, [player_id], _sel_cards, [])
		return
	# 应战：选好应战牌后点反击目标就直接应战（【圣光】抵挡不需要目标，不会走到这里）
	if _mode == 2 and int(_pending.get("respond_id", 0)) == GConst.RespondType.ReplyAttack:
		_发送应答(GConst.RespondType.ReplyAttack, [player_id], _sel_cards, [GConst.Reattack.Attack])
		return
	# 魔弹传递：选好【魔弹】后点亮起的敌人头像就把伤害传下去
	if _mode == 2 and int(_pending.get("respond_id", 0)) == GConst.RespondType.Bullet:
		_发送应答(GConst.RespondType.Bullet, [player_id], _sel_cards, [GConst.Reattack.Attack])
		return
	if _sel_players.has(player_id):
		_sel_players.erase(player_id)
	elif _need_players > 1:
		# 多目标：累积选择，超过上限则重新开始
		if _sel_players.size() >= _need_players:
			_sel_players.clear()
		_sel_players.append(player_id)
	else:
		_sel_players = [player_id]
	刷新选中面板()
	_更新按键()


## 这张牌此刻能不能点选
## 同一条判定同时决定「是否置灰」与「点击是否响应」，两者不会不一致
func _卡牌能点(card_id: int) -> bool:
	# 盖牌只在本阶段确实要选盖牌时才点得动（盖牌超限弃牌 / 来源为盖牌区的技能询问）；
	# 其余场合（行动出牌、普通弃牌…）盖牌一律不给点 —— 否则会被当成手牌选中提交，
	# 服务端判「操作无效」再推一份快照回来，画面就会闪一下
	if _is_my_cover(card_id) and not _selecting_cover:
		return false
	# 「先弹选项」型：选定的效果若限定了发动牌系别（如【百鬼夜行】展示火系妖力必须真用火系牌），
	# 其余系的牌整片置灰 —— 否则选错牌提交后服务端判无效、整条技能静默不生效（看着像「只打了一个人」）
	if _先弹选项 and not _已选参数.is_empty():
		var 系表: Dictionary = _指示器配置().get("选项牌系", {})
		var 需系: int = int(系表.get(int(_已选参数[0]), 0))
		if 需系 > 0:
			var 当前牌: GCard = Data.get_card(card_id)
			if 当前牌 == null or 当前牌.element_enum() != 需系:
				return false
	# 技能询问里「一张牌都用不到」的才整片置灰；need_card=0 但给了 card_max 表示可弃可不弃
	# （如【英灵召唤】可额外弃 0~1 张法术牌），这种仍要能点
	if _mode == 3 and _skill_ask_need_card <= 0 and _skill_card_max <= 0:
		return false
	# 应答（应战/抵挡、弃牌、魔弹传递等）同样要能点手牌
	if _mode == 2 and _need_cards <= 0:
		return false
	# 弃牌询问的选牌来源：普通弃牌只手牌，盖牌超限只盖牌
	if _mode == 2:
		var 应答号: int = int(_pending.get("respond_id", 0))
		if 应答号 == GConst.RespondType.Discard and _is_my_cover(card_id):
			return false
		if 应答号 == GConst.RespondType.DiscardCover and not _is_my_cover(card_id):
			return false
	if _mode != 1 and _mode != 2 and _mode != 3 and _mode != 4:
		return false
	# 选牌来源限制：盖牌询问只收盖牌，手牌询问只收手牌，两者皆可则都收
	if _mode == 3 and _是技能询问:
		if _skill_ask_card_source == GConst.CardSource.Cover and not _is_my_cover(card_id):
			return false
		if _skill_ask_card_source == GConst.CardSource.Hand and _is_my_cover(card_id):
			return false
	# 应战：只有「同系攻击牌」和【圣光】能用
	if _mode == 2 and int(_pending.get("respond_id", 0)) == GConst.RespondType.ReplyAttack:
		return _可应战牌(card_id)
	# 魔弹传递：只有【圣光】（抵挡）或【魔弹】/火系/地系牌（继续传递）能用
	if _mode == 2 and int(_pending.get("respond_id", 0)) == GConst.RespondType.Bullet:
		return _可回魔弹牌(card_id)
	# 行动阶段：只有能主动出手的牌可点（【圣光】只作响应，回合内置灰点不动）。
	# 服务端给了普通行动的手牌白名单时（如【修罗连斩】的额外攻击只能出火系攻击牌），只有白名单里的牌可点
	if _mode == 1:
		var 白名单: Array = _pending.get("card_ids", [])
		if not 白名单.is_empty() and not 白名单.has(card_id):
			return false
		return _可主动使用牌(card_id)
	# 发动技能 / 技能询问：按服务端给的选牌来源过滤（手牌 / 盖牌区 / 场上基础效果牌），
	# 再看合法牌白名单与选牌系别规则（如【魔道法典】只能选互异系、【法术反弹】只能选同系）
	if _mode == 4 or _mode == 3:
		# 这个技能一张牌都不用选（如女武神【秩序之印】）：手牌整片置灰，只留「确定 / 取消」
		if _mode == 4 and _skill_need_card <= 0 and _skill_card_max <= 0:
			return false
		match _skill_card_source:
			GConst.CardSource.Cover:
				if not _is_my_cover(card_id):
					return false
			GConst.CardSource.BasicEffect:
				if not _是场上基础效果牌(card_id):
					return false
			_:
				if _is_my_cover(card_id):
					return false
		if not _skill_cards.is_empty() and not _skill_cards.has(card_id):
			return false
		return _符合选牌规则(card_id)
	# 特殊行动（购买/合成/提炼）期间不点牌
	if _mode == 5 or _mode == 6:
		return false
	return true


## 按选牌规则过滤可点牌（服务端给的 card_rule）：
## "same"＝只能选与已选牌同系的；"diff"＝只能选与已选牌互异系的；
## "sameprop"＝只能选与已选牌同命格的（如【式神降临】）；""＝不限。
## 服务端只做最终校验，这里先一步把不合规的牌置灰，免得玩家点了一堆却被判「操作无效」。
func _符合选牌规则(card_id: int) -> bool:
	# 已选中的牌随时能点掉（取消选择）；否则下面按「第 1 张 / 第 2 张」分的槽位条件会把已选的牌反手卡住
	if _sel_cards.has(card_id):
		return true
	# 逐张选牌条件（如元素师独有法术：第 1 张须带该技能、第 2 张须为该系）
	if not _符合选牌槽位(card_id):
		return false
	# magic＝只能选法术牌（如女武神【英灵召唤】额外弃 1 张法术牌）
	if _skill_card_rule == "magic":
		var 法术牌: GCard = Data.get_card(card_id)
		return 法术牌 != null and 法术牌.is_magic()
	if _skill_card_rule == "" or _sel_cards.is_empty():
		return true
	var 牌: GCard = Data.get_card(card_id)
	if 牌 == null:
		return true
	for c: Variant in _sel_cards:
		var 已选号: int = int(c)
		# 跳过自己：一张牌与自己当然「同系」，不跳过就会被 diff 规则判成不合规，
		# 把已经选中的牌反手置灰（如【魔道法典】取消后重选）
		if 已选号 == card_id:
			continue
		var 已选: GCard = Data.get_card(已选号)
		if 已选 == null:
			continue
		# 同命格：如阴阳师【式神降临】要弃 2 张同命格牌
		if _skill_card_rule == "sameprop":
			if 已选.property_enum() != 牌.property_enum():
				return false
			continue
		var 同系: bool = 已选.element_enum() == 牌.element_enum()
		if _skill_card_rule == "same" and not 同系:
			return false
		if _skill_card_rule == "diff" and 同系:
			return false
	return true


## 逐张牌的合法条件（服务端给的槽位规则：第 1 张须带某技能 / 第 2 张须为某系）。
## 两张都没配就一律放行；只出现在「发动牌 + 加伤牌」这类技能上（元素师独有法术）
func _符合选牌槽位(card_id: int) -> bool:
	if _skill_slot_skill <= 0 and _skill_slot_element <= 0:
		return true
	var 牌: GCard = Data.get_card(card_id)
	if 牌 == null:
		return false
	match _sel_cards.size():
		0:
			return _skill_slot_skill <= 0 or 牌.has_skill_id(_skill_slot_skill)
		1:
			return _skill_slot_element <= 0 or 牌.element_enum() == _skill_slot_element
	return true


## 行动阶段能不能拿这张牌出手：攻击牌，以及能主动施放的【圣盾 / 虚弱 / 中毒 / 魔弹】。
## 【圣光】只作响应（应战攻击 / 抵挡魔弹），回合内打出去只会被服务端拒，所以直接置灰。
func _可主动使用牌(card_id: int) -> bool:
	var 牌: GCard = Data.get_card(card_id)
	if 牌 == null:
		return false
	# 仲裁者审判已满：手牌一律不给点，必须去点【末日审判】
	if _末日审判锁死行动():
		return false
	# 本阶段放行哪几类动作由服务端下发（额外攻击行动只放行攻击）：
	# 不放行的牌整片置灰，不要等点了才被服务端拒
	if 牌.is_attack():
		return GConst.放行动作(GConst.ActionType.Attack, _行动允许)
	# 【暗影抗拒】（904）：行动阶段不能使用法术牌 —— 整片置灰，点了必被服务端拒
	var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
	if 我 != null and 行动阶段禁用法术牌角色.has(我.role_id):
		return false
	match 牌.card_name_enum():
		GConst.CardName.Shield, GConst.CardName.Weaken, GConst.CardName.Poison, GConst.CardName.Missile:
			return GConst.放行动作(GConst.ActionType.Magic, _行动允许)
		_:
			return false


## 仲裁者（14）审判满上限时，本回合只能发动【末日审判】：手牌与特殊行动都锁死。
## 审判是 tokens[0]，名称/上限来自角色表；没有该指示物格时（未进入过审判形态）自然不锁
func _末日审判锁死行动() -> bool:
	var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
	if 我 == null or 我.role_id != 仲裁者角色:
		return false
	var t: GPlayer.Token = 我.tokens[0]
	return t != null and t.max_num > 0 and t.num >= t.max_num


## 这张牌能不能用来回应【魔弹】：
##   任何角色：出【魔弹】继续传递、出【圣光】抵挡；
##   魔导 / 特殊魔导（【魔弹融合】803）：地系、火系牌也能当【魔弹】打出去传递；
##   魔枪（【黑暗束缚】2903）：既不能转弹也不能圣光格挡，只能放弃。
## role_id 对照 battle_role.gd 的角色工厂与 role_modao / role_spmodao / role_moqiang 的校验覆写。
func _可回魔弹牌(card_id: int) -> bool:
	var 牌: GCard = Data.get_card(card_id)
	var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
	if 牌 == null or 我 == null:
		return false
	if 魔弹全禁角色.has(我.role_id):
		return false
	var 卡名: int = 牌.card_name_enum()
	if 卡名 == GConst.CardName.HolyLight or 卡名 == GConst.CardName.Missile:
		return true
	if not 地火可作魔弹角色.has(我.role_id):
		return false
	var 元素: int = 牌.element_enum()
	return 元素 == GConst.CardElement.Fire or 元素 == GConst.CardElement.Earth


## 这张牌能不能用来应战本次攻击（规则对照服务端 BattlePlayer.base_v_reattack / base_v_block）：
## 需为攻击牌且与本次攻击同系（暗系攻击牌可替任意系）；本次攻击本身是暗系则一律不可应战；【圣光】走抵挡
func _可应战牌(card_id: int) -> bool:
	var 牌: GCard = Data.get_card(card_id)
	if 牌 == null:
		return false
	if 牌.card_name_enum() == GConst.CardName.HolyLight:
		return _可圣光抵挡()
	if not _可应战() or not 牌.is_attack():
		return false
	var args: Array = _pending.get("args", [])
	var 攻击牌: GCard = Data.get_card(int(args[1])) if args.size() > 1 else null
	if 攻击牌 == null or 攻击牌.element_enum() == GConst.CardElement.Darkness:
		return false
	return 牌.element_enum() == 攻击牌.element_enum() or 牌.element_enum() == GConst.CardElement.Darkness


## 本次攻击能否用【圣光】抵挡（args[4] = can_light，有技能会让对方无法抵挡）
func _可圣光抵挡() -> bool:
	var args: Array = _pending.get("args", [])
	return int(args[4]) != 0 if args.size() > 4 else true


# ---------------- 确定 / 取消 / 放弃 ----------------
func _on_ok() -> void:
	var respond_id: int = int(_pending.get("respond_id", 0))
	var args: Array = _pending.get("args", [])
	# 弹窗型询问（【神之庇护】/ 治疗抵挡）：点「确定」＝把选项窗重新弹出来（选项窗被关掉后还能再开）
	if not _弹窗选项.is_empty():
		_弹出参数选项(_弹窗标题, _弹窗选项)
		return
	# 是否发动技能的询问
	if _mode == 3:
		# 本地询问（【冒险者天堂】选给谁）：选定后继续走提炼
		if _本地询问:
			_本地询问 = false
			_是技能询问 = false
			var 目标: int = int(_sel_players[0]) if not _sel_players.is_empty() else -1
			# 选自己＝按常规提炼给自己（不带目标，走通用校验 / 结算）
			if 目标 == Logic.my_player_id:
				目标 = -1
			_选特殊行动(GConst.SpecialAction.Extract, 目标)
			return
		# 单份额外行动（如【迅捷赐福】）：确定＝发动它
		if _额外行动单选 >= 0:
			_选择额外行动(_额外行动单选)
			return
		if not _分配配置().is_empty():
			_发送治疗分配()
			return
		# 「手牌 + 场上基础效果牌」的技能询问（如【天使之歌】）：确定后弹出目标身上的效果 + 用哪种能量供选
		if _skill_ask_card_source == GConst.CardSource.HandAndBasicEffect:
			_弹出基础效果选择()
			return
		if _是技能询问:
			# 「先弹选项」型（【百鬼夜行】）提交的是弹窗里选定的那个效果值；普通询问固定回 [1]（发动）
			_发送应答(_skill_ask_id, _sel_players, _sel_cards, _已选参数 if _先弹选项 else [1])
		return
	# 发动技能
	if _mode == 4:
		if not _分配配置().is_empty():
			_发送治疗分配()
			return
		# 「手牌 + 场上基础效果牌」的技能（如【风之洁净】）：确定后弹出目标身上的基础效果供选
		if _skill_card_source == GConst.CardSource.HandAndBasicEffect:
			_弹出基础效果选择()
			return
		# 「先弹选项」型（【死亡之触】）提交的是弹窗里选定的那个效果值
		_发送行动(_pending_skill_type, _pending_skill_id, _sel_players, _sel_cards, _已选参数 if _先弹选项 else [])
		return
	if _pending_type == GConst.Msg.Action:
		if _sel_cards.is_empty():
			_指令提示("请先选择一张手牌")
			return
		var card: GCard = Data.get_card(_sel_cards[0])
		if card == null:
			_指令提示("这张牌已不在手里，请重新选一张")
			return
		if card.is_attack():
			if _sel_players.is_empty():
				_指令提示("攻击请点敌方头像出手（选好攻击牌后直接点要打的人）")
				return
			_发送行动(GConst.ActionType.Attack, 0, _sel_players, _sel_cards, [])
		else:
			var dst: Array = _sel_players
			if dst.is_empty():
				dst = [Logic.my_player_id]
			_发送行动(GConst.ActionType.Magic, 0, dst, _sel_cards, [])
		return
	match respond_id:
		GConst.RespondType.ReplyAttack:
			if _sel_cards.is_empty():
				_指令提示("请先选择一张手牌（同系攻击牌应战，或【圣光】抵挡）")
				return
			var card2: GCard = Data.get_card(_sel_cards[0])
			if card2 == null:
				_指令提示("这张牌已不在手里，请重新选一张")
				return
			# 【圣光】抵挡：不需要反击目标
			if card2.card_name_enum() == GConst.CardName.HolyLight:
				_发送应答(respond_id, [], _sel_cards, [GConst.Reattack.Block])
				return
			if not _可应战():
				_指令提示("无法应战：出【圣光】抵挡，或取消放弃")
				return
			if _sel_players.is_empty():
				_指令提示("应战：点敌方头像反击，或取消放弃")
				return
			_发送应答(respond_id, _sel_players, _sel_cards, [GConst.Reattack.Attack])
		GConst.RespondType.Bullet:
			# 出【圣光】＝抵挡（魔弹终止）；出【魔弹】＝点下一个落点把伤害传下去
			if _sel_cards.is_empty():
				_指令提示("请先选一张手牌：出【魔弹】继续传递，或出【圣光】抵挡")
				return
			if _选中是圣光():
				_发送应答(respond_id, [], _sel_cards, [GConst.Reattack.Block])
				return
			if _sel_players.is_empty():
				_指令提示("魔弹传递请点亮起的敌人头像（选好牌后直接点他），或点「取消」承受伤害")
				return
			_发送应答(respond_id, _sel_players, _sel_cards, [GConst.Reattack.Attack])
		GConst.RespondType.Discard, GConst.RespondType.DiscardCover:
			_发送应答(respond_id, [], _sel_cards, [])
		GConst.RespondType.Weaken:
			_发送应答(respond_id, [], [], [1])
		GConst.RespondType.Heal:
			var harm: int = int(args[1]) if args.size() > 1 else 0
			_发送应答(respond_id, [], [], [harm])
		_:
			_发送应答(respond_id, [], _sel_cards, [])


func _on_cancel() -> void:
	# 不能取消的那次技能询问（如【水之神力】交牌）直接忽略：键盘快捷键也得挡住，
	# 否则会回一个空应答，服务端只好替玩家随机交一张，等于「取消」反而生效了
	if _mode == 3 and _是技能询问 and not _skill_ask_can_cancel:
		return
	var respond_id: int = int(_pending.get("respond_id", 0))
	# 技能询问：取消=放弃。回空 args（不再回 [0]）——「取消」用「没有给值」表达，
	# 这样 0 就能当正常的选项值用（如【魔女之怒】的「摸 0 张牌」）
	if _mode == 3:
		# 本地询问（【冒险者天堂】选给谁）：取消＝星石给自己，继续走提炼
		if _本地询问:
			_本地询问 = false
			_是技能询问 = false
			_选特殊行动(GConst.SpecialAction.Extract, -1)
			return
		if _是技能询问:
			_发送应答(_skill_ask_id, [], [], [])
		else:
			# 额外行动：空 args 表示跳过
			Logic.send_respond(GConst.RespondType.AdditionalAction, [], [], [])
			_清空待选()
		return
	# 发动技能 / 特殊行动三选一 / 特殊行动星石选择时取消：退回行动阶段
	if _mode == 4 or _mode == 5 or _mode == 6:
		_pending_skill_id = -1
		_回到行动阶段()
		return
	# 虚弱：取消＝不强摸
	if _pending_type == GConst.Msg.Respond and respond_id == GConst.RespondType.Weaken:
		_发送应答(respond_id, [], [], [0])
		return
	# 应战：取消＝放弃应战（原先这一功能挂在「放弃行动」按钮上，挪到「取消」上）
	if _pending_type == GConst.Msg.Respond and respond_id == GConst.RespondType.ReplyAttack:
		_发送应答(respond_id, [], [], [GConst.Reattack.GiveUp])
		return
	# 魔弹传递：取消＝不转弹、不抵挡，直接承受这次魔弹伤害
	if _pending_type == GConst.Msg.Respond and respond_id == GConst.RespondType.Bullet:
		_发送应答(respond_id, [], [], [GConst.Reattack.GiveUp])
		return
	# 治疗抵御：取消＝不用治疗，按原伤害结算（不回的话服务端要一直等到超时）
	if _pending_type == GConst.Msg.Respond and respond_id == GConst.RespondType.Heal:
		_发送应答(respond_id, [], [], [0])
		return
	# 其余：只清空已选，仍停留在本次询问
	_sel_cards.clear()
	_sel_players.clear()
	刷新手牌()
	刷新盖牌()
	刷新选中面板()
	_更新按键()


## 「盖牌」按钮（场景里的 BtnCovered，图标就是「盖牌」）：点开/收起自己的盖牌，只读，不结束回合
func _on_cover_view() -> void:
	if Data.cover_cards.is_empty():
		return
	_查看盖牌 = not _查看盖牌
	刷新盖牌()


## 弹出某名玩家的角色技能说明（点头像点不动时走这条：不是该选目标的时机 / 他不是合法目标）
func _弹出角色技能说明(player_id: int) -> void:
	var p: GPlayer = Data.get_player_by_id(player_id)
	if p == null or p.role_id <= 0:
		return
	英雄详情窗.打开(p.role_id)


## 放弃行动（场景里的 BtnResign；对照参考工程 RoleBase 的 ResignAction → ACTION_NONE）
func _on_resign() -> void:
	_发送行动(GConst.ActionType.None, 0, [], [], [])


## 特殊行动 / 放弃（场景 BtnSpecila，图标就是 action 键）
func _on_giveup() -> void:
	# 行动阶段：打开「购买 / 合成 / 提炼」（对照参考工程 PlayerAgentUI.onBtnSpecialClick → SpecialActionUI）
	if _mode == 1:
		_进入特殊行动()
		return
	var respond_id: int = int(_pending.get("respond_id", 0))
	if _pending_type == GConst.Msg.Respond and respond_id == GConst.RespondType.ReplyAttack:
		_发送应答(respond_id, [], [], [GConst.Reattack.GiveUp])
		return
	if _pending_type == GConst.Msg.Respond and respond_id == GConst.RespondType.Bullet:
		_发送应答(respond_id, [], [], [GConst.Reattack.GiveUp])
		return
	_发送行动(GConst.ActionType.None, 0, [], [], [])


# ---------------- 特殊行动（购买 / 合成 / 提炼） ----------------
## 行动阶段点「特殊行动」进来：三选一。
## 可用性逐条对照原客户端 Role::normal / Role::buy / Role::synthetize / Role::extract：
##   购买 = 手牌放得下 3 张；合成 = 放得下且我方战绩区星石 ≥ 3；
##   提炼 = 战绩区有星石，且自己（或冒险家【冒险者天堂】时任一有空的队友）还收得下
func _进入特殊行动() -> void:
	var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
	if 我 == null or 我.color == GConst.TEAM_NONE:
		return
	_mode = 5
	_清空技能按钮()
	var 战绩: GTeam = Data.team_of(我.color)
	var 星石: int = 战绩.gem + 战绩.crystal
	var 放得下: bool = 我.hand_cards_num + 3 <= 我.hand_cards_max
	var 可提炼: bool = 星石 > 0 and (我.get_energy() < 我.energy_max \
			or (我.role_id == 冒险家角色号 and _有队友可收星石()))
	特殊行动窗.打开(放得下, 放得下 and 星石 >= 3, 可提炼)
	# 窗口自带标题和三个写着「购买/合成/提炼」的大按钮，战斗界面的提示条要收起来：
	# 提示条就在窗口标题那一行上，不收就会两段文字叠在一起
	_收起提示()
	刷新选中面板()
	_更新按键()


## 特殊行动窗口里选中了一种行动：先关窗，再进入「用哪些星石」那一层（或直接提交）
func _on_special_action_chosen(action_id: int) -> void:
	特殊行动窗.visible = false
	_选特殊行动(action_id)


## 特殊行动窗口里点了取消：退回行动阶段
func _on_special_action_cancelled() -> void:
	特殊行动窗.visible = false
	_回到行动阶段()


## 用居中的参数选择窗弹出若干选项（每项 {"text":..., "args":[...]}）：选中就按当前询问/技能提交 args。
## 用于「只需选一个参数、不用选牌选目标」的询问（【神之庇护】抵消几点、治疗抵挡几点）
func _弹出参数选项(标题: String, 选项: Array) -> void:
	_参数选择_技能 = true
	参数选择窗.打开(标题, 选项, _skill_ask_can_cancel)
	_更新按键()


## 基础效果选择窗 / 提示里用的动词：按技能号从技能指示器取，取不到就是「移除」
## （【封印破碎】是「拿走」进自己手牌，天使【风之洁净】/【天使之歌】是「移除」弃掉）
func _基础效果动作(技能号: int) -> String:
	return str(GConst.技能指示器.get(技能号, {}).get("基础效果动作", "移除"))


## 【风之洁净】【天使之歌】【封印破碎】这类「选目标 → 场上基础效果牌」的技能：按下「确定」后，
## 按已选目标身上现有的基础效果列出选项（args 里带该效果牌 id），选哪张就处理哪张。对应原客户端
## 选中目标后在提示区列出该玩家全部基础效果、再点其一确定的做法。
## 【天使之歌】还要额外消耗 1 点能量（对照服务端 TianShi::TianShiZhiGe：args[0] = 用宝石?），
## 所以它的选项再带上「用宝石 / 用水晶」，且只列当前真有那种能量的项（能量不足的会被服务端拒）；
## 【封印破碎】不用手牌也不用在这里选能量（能量由服务端自动扣），只是把动词显示成「拿走」
func _弹出基础效果选择() -> void:
	if _sel_players.is_empty():
		return
	var 目标: GPlayer = Data.get_player_by_id(int(_sel_players[0]))
	if 目标 == null:
		return
	# 能量组合：[{args 前缀, 文案前缀}]；只有技能询问（天使之歌）才带能量
	var 能量组合: Array = [{"args": [], "文案": ""}]
	if _mode == 3:
		能量组合 = []
		var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
		if 我 != null:
			if 我.gem > 0:
				能量组合.append({"args": [1], "文案": "用宝石 "})
			if 我.crystal > 0:
				能量组合.append({"args": [0], "文案": "用水晶 "})
		if 能量组合.is_empty():
			return
	# 显示动词按技能号取（【封印破碎】是「拿走」进自己手牌，天使【风之洁净】/【天使之歌】是「移除」弃掉）
	var 技能号: int = _pending_skill_id if _mode == 4 else _skill_ask_id
	var 动作: String = _基础效果动作(技能号)
	var 选项: Array = []
	for 效果: GPlayer.BasicStatus in 目标.basic_status_list:
		if 效果.card == null:
			continue
		for 组合: Dictionary in 能量组合:
			选项.append({
				"text": "%s%s【%s】" % [str(组合["文案"]), 动作, 效果.card.card_name],
				"args": (组合["args"] as Array) + [效果.card.id],
			})
	if 选项.is_empty():
		_指令提示("该目标面前没有可%s的基础效果" % 动作)
		return
	_参数选择_技能 = true
	参数选择窗.打开("选择要%s的基础效果" % 动作, 选项)
	_指令提示("请选择要%s的基础效果" % 动作)
	_更新按键()


## 参数选择窗口里选好了一项：特殊行动按当初选的那个提交；技能询问回的是应答、发动技能回的是行动
func _on_参数选择(参数: Array) -> void:
	if _参数选择_额外行动:
		# 多份额外行动的选择窗：选中一项＝发动它
		_参数选择_额外行动 = false
		if not 参数.is_empty():
			_选择额外行动(int(参数[0]))
		return
	if _参数选择_技能:
		# 「先弹选项」型（【百鬼夜行】/【剑气斩】）：窗里只记下选了哪一项效果，等玩家选好牌 / 目标再按「确定」提交；
		# 顺手把这步选择报给服务端（partial）：选目标阶段若超时，服务端据此自动结算（【剑气斩】自动释放），
		# 而弹窗还没选就超时＝取消
		if _先弹选项:
			参数选择窗.visible = false
			_参数选择_技能 = false
			_已选参数 = 参数.duplicate()
			# 技能询问（如【百鬼夜行】）顺手把这步报给服务端（partial）：选目标阶段若超时，服务端据此自动结算；
			# 发动技能（如【死亡之触】）只本地记住，等服务端收到那条 Action 才知道
			if _mode == 3:
				Logic.send_respond(_skill_ask_id, [], [], _已选参数, true)
			_应用选项目标数()
			return
		_参数选择_技能 = false
		# 这条询问回「应答」还是「行动」按当初那条命令的类型定（不再按 mode 猜）：
		# 技能询问 / 治疗抵挡走应答，发动技能参数选项走行动
		if _pending_type == GConst.Msg.Respond:
			_发送应答(_skill_ask_id, _sel_players, _sel_cards, 参数)
		else:
			_发送行动(_pending_skill_type, _pending_skill_id, _sel_players, _sel_cards, 参数)
		return
	if 参数.size() < 2:
		return
	_发送特殊行动(_待定特殊行动, int(参数[0]), int(参数[1]))


## 参数选择窗口里点了取消：
##   弹窗型询问（【神之庇护】抵消几点 / 治疗抵挡几点）与「先弹选项」型（【剑气斩】）＝这次询问的
##     「取消」本身，直接放弃，不再让玩家回头补按一次界面上的「取消」；
##   先选牌选目标、确定后才弹窗的（【风之洁净】/【天使之歌】）＝只关窗，保留选牌 / 选目标状态让玩家改选；
##   特殊行动退回上一层「购买 / 合成 / 提炼」三选一
func _on_参数选择取消() -> void:
	if _参数选择_额外行动:
		# 多份额外行动的选择窗：取消＝跳过本次额外行动
		_参数选择_额外行动 = false
		Logic.send_respond(GConst.RespondType.AdditionalAction, [], [], [])
		_清空待选()
		return
	if _参数选择_技能:
		_参数选择_技能 = false
		if _先弹选项 or not _弹窗选项.is_empty():
			_先弹选项 = false
			_on_cancel()
			return
		_更新按键()
		return
	_进入特殊行动()


## 冒险家【冒险者天堂】：是否有队友还收得下星石（除自己外、能量没满）
func _有队友可收星石() -> bool:
	var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
	if 我 == null:
		return false
	for p: GPlayer in Data.player_list:
		if p.id != 我.id and p.color == 我.color and p.get_energy() < p.energy_max:
			return true
	return false


## 冒险家【冒险者天堂】：提炼前先问把星石给谁——点队友头像选，或点「取消」给自己。
## 用本地合成的技能询问复用头像选目标的交互（这一步不发给服务端；提交提炼时才把目标一起上交）
func _本地询问提炼目标() -> void:
	var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
	if 我 == null:
		return
	var 候选: Array = []
	# 候选＝还收得下的己方角色（含自己，选自己＝按常规提炼）
	if 我.get_energy() < 我.energy_max:
		候选.append(我.id)
	for p: GPlayer in Data.player_list:
		if p.id != 我.id and p.color == 我.color and p.get_energy() < p.energy_max:
			候选.append(p.id)
	# 只有自己一个可选项时不必问，直接给自己
	if 候选.is_empty() or (候选.size() == 1 and int(候选[0]) == 我.id):
		_选特殊行动(GConst.SpecialAction.Extract, -1)
		return
	_pending = {
		"respond_id": 冒险者天堂技能号, "args": [0, 1, GConst.CardSource.Hand, 0],
		"dst_ids": 候选, "is_skill": true,
		# 自己还有空位时才允许「取消＝给自己」；自己已满就必须选一名队友
		"can_cancel": 我.get_energy() < 我.energy_max,
	}
	_是技能询问 = true
	_skill_ask_id = 冒险者天堂技能号
	_pending_type = GConst.Msg.Respond
	_本地询问 = true
	_进入技能询问()


## 选定一种特殊行动后，再选「用哪些星石」——选项逐条对照原客户端
## Role::buy（战绩区 4 个时二选一、5 个已满）/ Role::synthetize / Role::extract 的选项盒
## 提炼目标：只有提炼用得上——-2＝还没问【冒险者天堂】给谁；-1＝给自己；>=0＝给该队友
func _选特殊行动(action_id: int, 提炼目标: int = -2) -> void:
	var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
	if 我 == null or 我.color == GConst.TEAM_NONE:
		return
	var 战绩: GTeam = Data.team_of(我.color)
	var 宝石: int = 战绩.gem
	var 水晶: int = 战绩.crystal
	var 组合: Array = []
	match action_id:
		GConst.SpecialAction.Buy:
			# 冒险家（【地下法则】）只加宝石、一次最多 2 点（role_maoxian.v_buy）
			var 地下法则: bool = 我.role_id == 冒险家角色号
			if 宝石 + 水晶 < 4:
				if 地下法则:
					组合.append({"text": "战绩区 +2 宝石", "gem": 2, "crystal": 0})
				else:
					组合.append({"text": "战绩区 +1 宝石 +1 水晶", "gem": 1, "crystal": 1})
			elif 宝石 + 水晶 == 4:
				组合.append({"text": "一个宝石", "gem": 1, "crystal": 0})
				if not 地下法则:
					组合.append({"text": "一个水晶", "gem": 0, "crystal": 1})
			else:
				组合.append({"text": "战绩区已满，不再加星石", "gem": 0, "crystal": 0})
		GConst.SpecialAction.Synthesize:
			if 水晶 >= 3:
				组合.append({"text": "三个水晶", "gem": 0, "crystal": 3})
			if 水晶 >= 2 and 宝石 >= 1:
				组合.append({"text": "两个水晶和一个宝石", "gem": 1, "crystal": 2})
			if 水晶 >= 1 and 宝石 >= 2:
				组合.append({"text": "一个水晶和两个宝石", "gem": 2, "crystal": 1})
			if 宝石 >= 3:
				组合.append({"text": "三个宝石", "gem": 3, "crystal": 0})
		_:
			# 提炼：冒险家先问【冒险者天堂】把星石给谁（空位按目标算），再列可选组合
			if 提炼目标 == -2 and 我.role_id == 冒险家角色号:
				_本地询问提炼目标()
				return
			var 目标: GPlayer = Data.get_player_by_id(提炼目标) if 提炼目标 >= 0 else 我
			var 余量: int = 目标.energy_max - 目标.get_energy()
			if 余量 >= 2:
				if 宝石 >= 2:
					组合.append({"text": "两个宝石", "gem": 2, "crystal": 0})
				if 水晶 >= 2:
					组合.append({"text": "两个水晶", "gem": 0, "crystal": 2})
				if 宝石 >= 1 and 水晶 >= 1:
					组合.append({"text": "一个宝石和一个水晶", "gem": 1, "crystal": 1})
			if 宝石 >= 1:
				组合.append({"text": "一个宝石", "gem": 1, "crystal": 0})
			if 水晶 >= 1:
				组合.append({"text": "一个水晶", "gem": 0, "crystal": 1})
			_提炼目标 = 提炼目标
	if 组合.is_empty():
		_指令提示("没有可用的星石组合")
		return
	if 组合.size() == 1:
		# 只有一种组合（如购买时的「+1 宝石 +1 水晶」「战绩区已满」）就不用再问一遍
		var 只: Dictionary = 组合[0]
		_发送特殊行动(action_id, int(只["gem"]), int(只["crystal"]))
		return
	_mode = 6
	_清空技能按钮()
	# 第二层（选「用哪些星石」）用从参考工程搬来的参数选择窗口 —— 对应 ChooseArgsUI 的 "Energy" 分支
	var 选项: Array = []
	for 项: Variant in 组合:
		var d: Dictionary = 项
		选项.append({"text": str(d["text"]), "args": [int(d["gem"]), int(d["crystal"])]})
	_待定特殊行动 = action_id
	_参数选择_技能 = false
	# 合成 / 提炼是从战绩区把星石花掉，标题写「消耗能量」；购买是往战绩区加星石，写「选择能量」
	var 标题: String = "选择能量" if action_id == GConst.SpecialAction.Buy else "消耗能量"
	参数选择窗.打开(标题, 选项)
	_指令提示("请选择要使用的星石")
	刷新选中面板()
	_更新按键()


## 发出特殊行动：args = [宝石数, 水晶数]（服务端 _do_special 按这个口径结算）
## 提炼指定了队友（【冒险者天堂】）时带上目标，服务端把星石给该队友而不给自己
func _发送特殊行动(action_id: int, gem: int, crystal: int) -> void:
	var dst: Array = []
	if action_id == GConst.SpecialAction.Extract and _提炼目标 >= 0:
		dst = [_提炼目标]
	_发送行动(GConst.ActionType.Special, action_id, dst, [], [gem, crystal])


## 退回行动阶段（取消发动技能 / 取消特殊行动时用），顺手把本回合的技能按钮摆回来
func _回到行动阶段() -> void:
	_mode = 1
	特殊行动窗.visible = false
	参数选择窗.visible = false
	英雄详情窗.visible = false
	_sel_cards.clear()
	_sel_players.clear()
	_重置治疗分配()
	# 取消「先弹选项」型技能（如【死亡之触】）时把弹窗那套状态一并清掉
	_先弹选项 = false
	_已选参数.clear()
	_参数选择_技能 = false
	_目标锁死 = false
	_清空技能按钮()
	if not _行动命令.is_empty():
		_构建技能按钮(_行动命令)
	_指令提示("轮到你了：选择一张手牌作为攻击/法术，或点「特殊行动」「放弃行动」")
	刷新手牌()
	刷新盖牌()
	刷新选中面板()
	_更新按键()


# ---------------- 技能动作 ----------------
## 选中并准备发动某个技能（行动阶段点技能按钮）
## 合法目标 / 合法牌由服务端的技能声明给出（targets / cards），非空时界面只让它们可点；
## 需牌是最少张数、最多牌（card_max）是点选上限（省略＝刚好 need_card 张），目标数同理走 target_max；
## 选牌来源 card_source 决定是从手牌、盖牌区还是场上基础效果牌里选；
## 参数选项 arg_choices 非空时改由选项按钮提交（服务端靠 args 的技能都走这条）
func _选择技能(技能号: int, 技能类型: int, 需牌: int, 需目标: int, 合法目标: Array = [], 合法牌: Array = [],
		最多牌: int = 0, 最多目标: int = 0, 目标上限减牌数: int = 0,
		选牌来源: int = GConst.CardSource.Hand, 选牌规则: String = "",
		首张技能: int = 0, 次张系别: int = 0, 参数选项: Array = [], 按钮: Node = null) -> void:
	_mode = 4
	_标记选中技能(按钮)
	# 重新点技能按钮＝从头来一遍：先前为某技能弹出的效果选择窗一并关掉，免得留着上一轮的选项
	参数选择窗.visible = false
	_参数选择_技能 = false
	_pending_skill_type = 技能类型
	_pending_skill_id = 技能号
	_skill_need_card = 需牌
	_skill_need_target = 需目标
	_skill_card_max = maxi(需牌, 最多牌)
	_skill_target_max = maxi(需目标, 最多目标)
	_skill_target_max_from_cards = 目标上限减牌数
	_skill_card_source = 选牌来源
	# 选牌规则随技能一起带过来（不能沿用「建技能按钮」时循环残留的那个，否则多技能角色会串味）
	_skill_card_rule = 选牌规则
	_skill_slot_skill = 首张技能
	_skill_slot_element = 次张系别
	_skill_arg_choices = 参数选项
	# 复用 _need_cards / _need_players 驱动点选上限与「确定」可用性（同 _进入技能询问）
	_need_cards = _skill_card_max
	_need_players = _skill_target_max
	_skill_targets.clear()
	for t: Variant in 合法目标:
		_skill_targets.append(int(t))
	_skill_cards.clear()
	for 牌号: Variant in 合法牌:
		_skill_cards.append(int(牌号))
	_sel_cards.clear()
	_sel_players.clear()
	_重置治疗分配()
	# 盖牌来源才让盖牌区亮起来；基础效果牌由玩家面板上的图标直接点
	_selecting_cover = 选牌来源 == GConst.CardSource.Cover
	var 指示配置: Dictionary = GConst.技能指示器.get(技能号, {})
	# 「自动选」的技能（【辉耀】自动选全体、【圣光祈愈】自动选自己）：不用点头像，
	# 进场即把目标选中并画「N 治疗」
	match str(指示配置.get("自动选", "")):
		"全体":
			for 玩家: GPlayer in Data.player_list:
				_治疗分配.append(玩家.id)
		"自己":
			_治疗分配.append(Logic.my_player_id)
	if not _治疗分配.is_empty():
		_刷新治疗分配()
	# 「自动选目标」型（【瘟疫】/【剧毒新星】：对除自己外所有人）：进场即把该打的人全选中并锁死，
	# 点头像也改不了（只能靠「取消」退出）；被选中的头像上直接画即将受到的伤害
	_目标锁死 = str(指示配置.get("自动选目标", "")) != ""
	match str(指示配置.get("自动选目标", "")):
		"他人":
			for 玩家: GPlayer in Data.player_list:
				if 玩家.id != Logic.my_player_id:
					_sel_players.append(玩家.id)
		"全体":
			for 玩家: GPlayer in Data.player_list:
				_sel_players.append(玩家.id)
	# 「先弹选项」型（如【死亡之触】）：点技能立刻弹出居中的效果选择窗（问消耗多少治疗），
	# 窗里只记下选了哪一项、不提交；选完再选牌 / 选目标，按「确定」才把该项 args 一起上交
	_先弹选项 = bool(指示配置.get("先弹选项", false)) and not 参数选项.is_empty()
	_已选参数.clear()
	if _先弹选项:
		# 选效果之前不让点牌、不让点目标：把需牌 / 目标数临时清零，选完在 _应用选项目标数 里还原
		_选项原始需牌 = _skill_need_card
		_选项原始最多牌 = _skill_card_max
		_选项原始目标数 = _skill_need_target
		_选项原始最多目标 = _skill_target_max
		_skill_need_card = 0
		_skill_card_max = 0
		_need_cards = 0
		_skill_need_target = 0
		_skill_target_max = 0
		_need_players = 0
		var 弹窗选项: Array = []
		for 项: Variant in 参数选项:
			var d: Dictionary = 项
			弹窗选项.append({"text": str(d.get("text", "")), "args": d.get("args", [])})
		_参数选择_技能 = true
		var 选项窗标题: String = str(指示配置.get("选项窗标题", ""))
		参数选择窗.打开(选项窗标题 if not 选项窗标题.is_empty() else "【%s】请选择效果" % GConst.skill_name(技能号), 弹窗选项)
	var 指示提示: String = str(指示配置.get("提示", ""))
	if _先弹选项:
		_指令提示("【%s】请先在弹窗里选择效果" % GConst.skill_name(技能号))
	elif not 指示提示.is_empty():
		_指令提示(指示提示)
	elif not 参数选项.is_empty():
		_构建技能参数按钮()
		_指令提示("发动【%s】：%s%s再点下面的选项" % [
			GConst.skill_name(技能号), _需选牌提示(需牌), _需选目标提示(需目标),
		])
	elif 选牌来源 == GConst.CardSource.HandAndBasicEffect:
		_指令提示("发动【%s】：%s%s按「确定」后选择要%s的基础效果" % [
			GConst.skill_name(技能号), _需选牌提示(需牌), _需选目标提示(需目标), _基础效果动作(技能号),
		])
	else:
		_指令提示("发动【%s】：%s%s点「确定」" % [
			GConst.skill_name(技能号), _需选牌提示(需牌), _需选目标提示(需目标),
		])
	_刷新交互()


## 「要选几张牌」的提示文案（含来源：手牌 / 盖牌 / 场上基础效果牌）
func _需选牌提示(需牌: int) -> String:
	if 需牌 <= 0:
		return ""
	var 来源: String = "手牌"
	match _skill_card_source:
		GConst.CardSource.Cover:
			来源 = "盖牌"
		GConst.CardSource.BasicEffect:
			来源 = "场上基础效果牌"
	return "从%s中选%d张，" % [来源, 需牌]


func _需选目标提示(需目标: int) -> String:
	if 需目标 <= 0:
		return ""
	if _skill_target_max > 需目标:
		return "选%d~%d名目标，" % [需目标, _skill_target_max]
	return "选%d名目标，" % 需目标


## 把服务端给的参数选项（arg_choices）渲染成按钮：点哪个就用当前已选的牌/目标提交该项 args
## 每项可带 need_card / need_target：要求先选够牌或目标才让点（如「对目标造成伤害」「弃光手牌」）
func _构建技能参数按钮() -> void:
	_清空技能按钮()
	for 项: Variant in _skill_arg_choices:
		var d: Dictionary = 项
		_加文本按钮(str(d.get("text", "")), _提交技能参数.bind(d.get("args", [])))
		_参数按钮.append({
			"按钮": _技能按钮[_技能按钮.size() - 1],
			"需牌": int(d.get("need_card", 0)),
			"需目标": int(d.get("need_target", 0)),
			"目标白名单": d.get("targets", []),
		})


func _提交技能参数(参数: Array) -> void:
	_发送行动(_pending_skill_type, _pending_skill_id, _sel_players, _sel_cards, 参数)


## 当前技能的「技能指示器」配置（展示键 + 交互键的统一表），没有则空字典。
## 发动技能（mode 4，看 _pending_skill_id）与技能询问（mode 3，看 _skill_ask_id）两条通道都认
func _指示器配置() -> Dictionary:
	var 技能号: int = -1
	if _mode == 4:
		技能号 = _pending_skill_id
	elif _mode == 3:
		技能号 = _skill_ask_id
	if 技能号 < 0:
		return {}
	return GConst.技能指示器.get(技能号, {})


## 只取「点头像分配」型的那份配置（配了「每次」才算）：它接管目标选取与提交
## （args 是各目标点数 / 用法），纯展示型返回空
func _分配配置() -> Dictionary:
	var 配置: Dictionary = _指示器配置()
	return 配置 if int(配置.get("每次", 0)) > 0 else {}


## 本次已分配的总点数（点击数 × 每次）
func _分配点数() -> int:
	return _治疗分配.size() * int(_分配配置().get("每次", 1))


## 点数是否已分够、可以点「确定」：需分满时要求分满上限；否则至少分一次就行（神官【神圣契约】）
func _分配已满() -> bool:
	var 配置: Dictionary = _分配配置()
	if 配置.is_empty():
		return false
	if str(配置.get("自动选", "")) != "":
		# 配了「自动选」的技能是自动选满的，不需要玩家分点
		return true
	var 需要: int = _分配上限() if bool(配置.get("需分满", true)) else int(配置.get("每次", 1))
	return 需要 > 0 and _分配点数() >= 需要


## 本次最多能分几点：配置给了正数就用它；<= 0 表示按自己当前的治疗量（神官【神圣契约】转几分自己定）
func _分配上限() -> int:
	var 配置: Dictionary = _分配配置()
	if 配置.is_empty():
		return 0
	var 上限: int = int(配置.get("上限", 0))
	if 上限 > 0:
		return 上限
	var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
	return 我.cross_num if 我 != null else 0


## 点一次头像：给该角色加上「每次」点治疗。
## 已分满再点＝重新分配（本次点击算第 1 次）；「不可多目标」时点了别人就整份挪过去；
## 「不可重复」时点已选过的角色不生效
func _点治疗目标(player_id: int) -> void:
	var 配置: Dictionary = _分配配置()
	if str(配置.get("自动选", "")) != "":
		# 配了「自动选」的技能已经自动选中目标，点谁都不改选
		return
	var 每次: int = int(配置.get("每次", 1))
	var 上限: int = _分配上限()
	if 每次 <= 0 or 上限 <= 0:
		return
	if not bool(配置.get("可多目标", true)) and not _治疗分配.is_empty() and int(_治疗分配[0]) != player_id:
		_治疗分配 = [player_id]
		_刷新治疗分配()
		return
	if not bool(配置.get("可重复", false)) and _治疗分配.has(player_id):
		return
	if (_治疗分配.size() + 1) * 每次 > 上限:
		_治疗分配 = [player_id]
	else:
		_治疗分配.append(player_id)
	_刷新治疗分配()


## 把已分配的点数刷到各玩家头像上（「N 治疗」；没分到的不显示）。
## 同时把有分配的角色塞进 _sel_players，借「刷新选中面板」复用原本的选中高亮效果。
## 配了「阵营效果」的技能（如【神圣领域】）另走一条：按目标算我方还是敌方，分别写两边的效果
func _刷新治疗分配() -> void:
	_sel_players.clear()
	# 先全部收起，再只给「有提示」的面板重画（藏起来的空面板 ID 是哨兵 -1，不会误命中）
	for pid: int in _治疗提示表:
		var 提示: RichTextLabel = _治疗提示表[pid]
		if is_instance_valid(提示):
			提示.visible = false
	var 配置: Dictionary = _分配配置()
	var 阵营表: Dictionary = 配置.get("阵营效果", {})
	if not 阵营表.is_empty():
		_刷新阵营提示(阵营表)
	else:
		var 每次: int = int(配置.get("每次", 1))
		for 面板: 战斗玩家面板 in _面板列表:
			var 次数: int = 0
			for id: int in _治疗分配:
				if id == 面板.ID:
					次数 += 1
			if 次数 <= 0:
				continue
			_刷治疗提示(面板, 次数 * 每次, 0)
			_sel_players.append(面板.ID)
	刷新选中面板()
	_更新按键()


## 「阵营效果」的提示：按当前选中的目标定分支（选队友＝加治疗、选敌人＝打伤害），
## 目标头上写分支的「目标治疗 / 目标伤害」，自己头上写分支的「自身治疗」；自己是目标时两份合并
func _刷新阵营提示(阵营表: Dictionary) -> void:
	var 目标: int = int(_治疗分配[0]) if not _治疗分配.is_empty() else -1
	var 分支: Dictionary = 阵营表.get(_阵营键(目标), {}) if 目标 >= 0 else {}
	for 面板: 战斗玩家面板 in _面板列表:
		var 治疗值: int = 0
		var 伤害值: int = 0
		if 面板.ID == 目标:
			治疗值 += int(分支.get("目标治疗", 0))
			伤害值 += int(分支.get("目标伤害", 0))
		if 面板.ID == Logic.my_player_id:
			治疗值 += int(分支.get("自身治疗", 0))
		if 治疗值 == 0 and 伤害值 == 0:
			continue
		_刷治疗提示(面板, 治疗值, 伤害值)
		if 面板.ID == 目标:
			_sel_players.append(面板.ID)


## 目标算「队友」还是「敌人」：自己与同队都算队友（【神圣领域】选自己＝自己也吃队友那一份）
func _阵营键(player_id: int) -> String:
	if player_id == Logic.my_player_id or _是队友(player_id):
		return "队友"
	return "敌人"


## 把「N 治疗」/「N 法术伤害」画到该面板头像正中
func _刷治疗提示(面板: 战斗玩家面板, 治疗值: int, 伤害值: int) -> void:
	_贴头像提示(面板, _取治疗提示(面板.ID), _效果文本(治疗值, 伤害值))


## 头像提示的文案：治疗一律写成「N 治疗」（加治疗不带 +，减治疗保留负号）；
## 伤害写成「N 法术伤害」（同一个人两样都有就换行）
func _效果文本(治疗值: int, 伤害值: int) -> String:
	var 段: Array[String] = []
	if 治疗值 != 0:
		段.append("%d 治疗" % 治疗值)
	if 伤害值 > 0:
		段.append("%d 法术伤害" % 伤害值)
	return "\n".join(段)


## 取（必要时新建）某玩家的治疗提示控件。用 RichTextLabel 是为了按内容上色
## （治疗＝浅蓝、法术伤害＝洋红，见 _提示上色）。
## 刻意挂在 Root 上而不是玩家面板里：面板被选中时会整体染黄，挂在里面的文字会跟着变黄、
## 看起来像被选中效果盖住；挂 Root 上就在面板之上、且不受它的 modulate 影响
func _取治疗提示(player_id: int) -> RichTextLabel:
	if _治疗提示表.has(player_id):
		return _治疗提示表[player_id]
	var 提示: RichTextLabel = RichTextLabel.new()
	提示.size = Vector2(治疗提示宽, 提示行高)
	提示.bbcode_enabled = true
	提示.scroll_active = false
	提示.autowrap_mode = TextServer.AUTOWRAP_OFF
	提示.mouse_filter = Control.MOUSE_FILTER_IGNORE
	提示.add_theme_font_size_override("normal_font_size", 26)
	提示.add_theme_color_override("default_color", Color.WHITE)
	提示.add_theme_color_override("font_outline_color", Color.BLACK)
	提示.add_theme_constant_override("outline_size", 6)
	提示.visible = false
	Root.add_child(提示)
	_治疗提示表[player_id] = 提示
	return 提示


## 头像提示的按内容上色：含「法术伤害」的行用洋红、含「治疗」的行用浅蓝，其余保持白色。
## 同一个头像上治疗与伤害可能各占一行（_效果文本 用换行拼接），所以逐行判定、
## 逐行居中（RichTextLabel 没有 horizontal_alignment，居中只能靠 BBCode 的 [center]）
func _提示上色(文: String) -> String:
	if 文.is_empty():
		return ""
	var 行: Array[String] = []
	for 段: String in 文.split("\n"):
		if 段.contains("法术伤害"):
			行.append("[color=#%s]%s[/color]" % [提示色_法术伤害, 段])
		elif 段.contains("治疗"):
			行.append("[color=#%s]%s[/color]" % [提示色_治疗, 段])
		else:
			行.append(段)
	return "[center]%s[/center]" % "\n".join(行)


## 把一句话贴到该面板头像正中：框高按文案行数现算（RichTextLabel 会裁掉超出框的内容，
## 单行 / 多行都得留够高度），再整体居中。文为空就收起
func _贴头像提示(面板: 战斗玩家面板, 提示: RichTextLabel, 文: String) -> void:
	提示.visible = 文 != ""
	if 文.is_empty():
		return
	提示.text = _提示上色(文)
	提示.size = Vector2(治疗提示宽, 提示行高 * float(文.split("\n").size()))
	提示.position = 面板.get_rect().get_center() - 提示.size * 0.5


## 收到一次治疗：在目标头像上喷一片浅蓝色「+」（治疗点数越多，冒得越多）
func _on_heal_received(pid: int, num: int) -> void:
	_播放治疗加号(pid, num)


## 治疗加号特效：在头像附近随机撒一圈「+」，各自上浮、放大并淡出
func _播放治疗加号(player_id: int, 点数: int) -> void:
	var 中心: Vector2 = _面板中心(player_id)
	if 中心.x < 0.0:
		return
	var 个数: int = clampi(6 + 点数 * 3, 6, 20)
	for _i: int in range(个数):
		_生成治疗加号(中心)


## 单个「+」：随机起点静置一小会儿，再向上飘走，同时放大并淡出，放完自毁
func _生成治疗加号(中心: Vector2) -> void:
	var 加号: Label = Label.new()
	加号.text = "+"
	加号.size = 加号尺寸
	加号.pivot_offset = 加号尺寸 * 0.5
	加号.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	加号.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	加号.mouse_filter = Control.MOUSE_FILTER_IGNORE
	加号.add_theme_font_size_override("font_size", randi_range(30, 46))
	加号.add_theme_color_override("font_color", 加号色)
	加号.add_theme_color_override("font_outline_color", 加号描边色)
	加号.add_theme_constant_override("outline_size", 6)
	Root.add_child(加号)
	var 起点: Vector2 = 中心 + Vector2(randf_range(-40.0, 40.0), randf_range(-26.0, 26.0)) * 加号范围倍率
	加号.position = 起点 - 加号尺寸 * 0.5
	加号.scale = Vector2.ONE * randf_range(0.6, 0.9)
	var 时长: float = randf_range(0.55, 0.95) * 加号时间倍率 / 加号速度倍率
	var 延迟: float = randf_range(0.0, 0.25) * 加号时间倍率
	var 终点: Vector2 = 起点 + Vector2(randf_range(-30.0, 30.0), randf_range(-140.0, -80.0)) * 加号范围倍率
	var t: Tween = create_tween()
	t.set_parallel(true)
	t.tween_property(加号, "position", 终点, 时长).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT).set_delay(延迟)
	t.tween_property(加号, "scale", Vector2.ONE * 1.25, 时长).set_delay(延迟)
	t.tween_property(加号, "modulate:a", 0.0, 时长 * 0.85).set_delay(延迟 + 时长 * 0.15)
	t.chain().tween_callback(加号.queue_free)


## 某玩家面板的中心点（与治疗方案提示同一坐标系，都挂在 Root 上）；没有这个面板时返回 (-1, -1)
func _面板中心(player_id: int) -> Vector2:
	for 面板: 战斗玩家面板 in _面板列表:
		if 面板.ID == player_id:
			return 面板.get_rect().get_center()
	return Vector2(-1.0, -1.0)


## 受击反馈（泛红 / 抖动 / 画面扭曲震荡波 / 卡肉）已移进角色头像面板（战斗玩家面板.Hurted），
## 由 _on_hurt 直接调面板播放。


## 收到弃牌事件（服务端弃牌日志带来的人与张数）→ 在弃牌者身上播弃牌特效
func _on_discard_received(pid: int, num: int) -> void:
	_弃牌特效(pid, num)


## 弃牌特效：从弃牌者身上朝画面中心飞出若干张卡背（弃牌堆所在处），边飞边淡出。
## 弃几张就飞几张，每张先后起飞、落点与朝向各自随机；找人失败就不播。
## 取全局坐标（与 _给牌特效 一致）：特效是 Node2D，挂在 Root 下、位置按 global_position 给
func _弃牌特效(player_id: int, 张数: int) -> void:
	var 面板: 战斗玩家面板 = _玩家面板(player_id)
	if 面板 == null or Root == null:
		return
	var 起: Vector2 = 面板.get_global_rect().get_center()
	var 止: Vector2 = Root.get_global_rect().get_center()
	for i: int in range(maxi(张数, 1)):
		var 动效: 弃牌2D = 弃牌预制.instantiate() as 弃牌2D
		Root.add_child(动效)
		动效.延迟时长 = 弃牌间隔 * float(i)
		动效.播放(起, 止)


## 清掉分配记录并收起头像上的提示（取消 / 提交 / 回到行动阶段时用）
func _重置治疗分配() -> void:
	_治疗分配.clear()
	for pid: int in _治疗提示表:
		var 提示: RichTextLabel = _治疗提示表[pid]
		if is_instance_valid(提示):
			提示.visible = false


## 分配型指示器确定：把点选结果整理成「去重后的目标列表 + 各自点数」提交；
## 配了「阵营效果」的技能（【神圣领域】）另走一条，args 是「用哪种用法」。
## 技能询问（发动与否）与发动技能两条通道分别回不同的包
func _发送治疗分配() -> void:
	# 配了「阵营效果」的技能（【神圣领域】）：只有一个目标，args 不是点数而是「用哪种用法」——
	# 选队友（含自己）＝0（自己 +2、目标 +1 治疗），选敌人＝1（移除自己 1 治疗、目标受 2 点法术伤害）
	var 阵营表: Dictionary = _分配配置().get("阵营效果", {})
	if not 阵营表.is_empty():
		var 目标: int = int(_治疗分配[0]) if not _治疗分配.is_empty() else -1
		var 用法: int = 1 if _阵营键(目标) == "敌人" else 0
		if _mode == 3:
			_发送应答(_skill_ask_id, [目标], _sel_cards, [用法])
		else:
			_发送行动(_pending_skill_type, _pending_skill_id, [目标], _sel_cards, [用法])
		return
	var 每次: int = int(_分配配置().get("每次", 1))
	var 目标表: Array[int] = []
	var 点数表: Array[int] = []
	for pid: int in _治疗分配:
		var 序: int = 目标表.find(pid)
		if 序 < 0:
			目标表.append(pid)
			点数表.append(每次)
		else:
			点数表[序] += 每次
	# 技能询问（如冰霜祷言 / 神圣契约）：args 就是各目标的点数 ——
	# 冰霜祷言只有 1 点，args[0]==1 正好等于「发动」的语义；神圣契约则靠它说明各转几点
	if _mode == 3:
		_发送应答(_skill_ask_id, 目标表, _sel_cards, 点数表)
	else:
		_发送行动(_pending_skill_type, _pending_skill_id, 目标表, _sel_cards, 点数表)


## 选择某技能选项：连同已选目标/卡牌一并回传
func _选择技能选项(值: int) -> void:
	_发送应答(_skill_ask_id, _sel_players, _sel_cards, [值])


func _选择额外行动(cause: int) -> void:
	Logic.send_respond(GConst.RespondType.AdditionalAction, [], [], [cause])
	_清空待选()


# ---------------- 提交 / 复位 ----------------
func _发送行动(action_type: int, action_id: int, dst: Array, cards: Array, args: Array) -> void:
	Logic.send_action(action_type, action_id, dst, cards, args)
	_清空待选()


func _发送应答(respond_id: int, dst: Array, cards: Array, args: Array) -> void:
	Logic.send_respond(respond_id, dst, cards, args)
	_清空待选()


func _清空待选() -> void:
	_pending = {}
	_pending_type = -1
	_mode = 0
	英雄详情窗.visible = false
	_行动命令.clear()
	_skill_ask_id = -1
	_是技能询问 = false
	_额外行动单选 = -1
	_额外行动可选 = true
	_skill_ask_need_card = 0
	_skill_ask_need_target = 0
	_skill_ask_card_source = 0
	_selecting_cover = false
	_skill_options.clear()
	_弹窗选项.clear()
	_弹窗标题 = ""
	_先弹选项 = false
	_已选参数.clear()
	_目标锁死 = false
	_pending_skill_id = -1
	_pending_skill_type = -1
	_skill_target_max = 0
	_skill_target_max_from_cards = 0
	_skill_slot_skill = 0
	_skill_slot_element = 0
	_skill_card_source = GConst.CardSource.Hand
	_skill_arg_choices.clear()
	_skill_ask_can_cancel = true
	_本地询问 = false
	_提炼目标 = -1
	_查看盖牌 = false
	特殊行动窗.visible = false
	参数选择窗.visible = false
	_参数选择_技能 = false
	_参数选择_额外行动 = false
	_sel_cards.clear()
	_sel_players.clear()
	_重置治疗分配()
	_清空技能按钮()
	_收起提示()
	_刷新交互()


## 操作无效（ErrorInput 由 Logic 回调进来）：提示并重新进入本次询问
func on_invalid_input(_data: Dictionary) -> void:
	_进入待选()
	# 放在 _进入待选 之后：那个函数会写「轮到你了…」，这里再盖成失败原因，
	# 不然玩家只看到选择被清空、完全不知道刚才那手为什么没生效（日志里也留一行）
	_指令提示("操作无效，请重新选择")
	_日志追加("操作无效，请重新选择", "提示")


# ---------------- 规则判定 ----------------
## 本次应战询问是否允许应战（args[0] = 命中率：非普通命中率不允许应战）
func _可应战() -> bool:
	var args: Array = _pending.get("args", [])
	if args.is_empty():
		return true
	return int(args[0]) == GConst.HitRate.Normal


## 本次攻击的原攻击者（args[3]）：应战的反击目标不能是他
func _原攻击者() -> int:
	var args: Array = _pending.get("args", [])
	return int(args[3]) if args.size() > 3 else -1


## 应战的反击目标是否可选：敌方玩家、且不是原攻击者（规则同服务端 v_reattack）
func _可作反击目标(player_id: int) -> bool:
	if player_id == Logic.my_player_id or player_id == _原攻击者():
		return false
	return _是敌方(player_id)


## 是不是「敌方玩家」：双方都已分队、且队色不同。
## 服务端 v_attack 对同队直接回 GE_INVALID_ACTION（19），v_reattack 还要求目标非 TEAM_NONE ——
## 这里取两者的交集：不符合的玩家不亮、也点不动，不会等发出去了才被服务端拒。
func _是敌方(player_id: int) -> bool:
	var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
	var 他: GPlayer = Data.get_player_by_id(player_id)
	if 我 == null or 他 == null:
		return false
	return 我.color != GConst.TEAM_NONE and 他.color != GConst.TEAM_NONE and 我.color != 他.color


## 暗杀者（角色号 5）：潜行＝横置；潜行期间「不能成为主动攻击的目标」（对应服务端暗杀者 v_attacked）。
## 攻击指示器据此把他排除，否则点亮后点了会被服务端拒（表现为客户端闪一下、没反应）
const 暗杀者角色号: int = 5


func _潜行中(player_id: int) -> bool:
	var 他: GPlayer = Data.get_player_by_id(player_id)
	return 他 != null and 他.role_id == 暗杀者角色号 and 他.tap


## 这名玩家是不是我的队友（同队，且不是自己；未分队时不算）
func _是队友(player_id: int) -> bool:
	if player_id == Logic.my_player_id:
		return false
	var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
	var 他: GPlayer = Data.get_player_by_id(player_id)
	if 我 == null or 他 == null:
		return false
	return 我.color != GConst.TEAM_NONE and 他.color != GConst.TEAM_NONE and 我.color == 他.color


## 法术牌的可选目标：对照服务端 BattleEngine._do_magic 的分支
##   圣盾 / 虚弱：目标面前不能已有同名基础效果（v_shield / v_weaken 会拒）；
##               其中【圣盾】要把【天使之墙】也算作已有（见 _有圣盾效果）
##   中毒：任意玩家
##   魔弹：默认落点是右手边最近的敌人（服务端 _nearest_enemy 沿 post 方向找），只有他亮；
##         本地角色有【魔弹掌握】802 时左右各一个都能选
##   其余法术牌（如【圣光】只作响应）不能主动施放 → 谁都不亮
func _可作法术目标(牌: GCard, player_id: int) -> bool:
	match 牌.card_name_enum():
		GConst.CardName.Shield:
			return not _有圣盾效果(player_id)
		GConst.CardName.Weaken:
			return not _有基础效果(player_id, GConst.CardName.Weaken)
		GConst.CardName.Poison:
			return true
		GConst.CardName.Missile:
			# 默认只有右手边那个对手；有【魔弹掌握】时左手边那个也能选（逆向传递）
			return player_id == _魔弹目标() or (_有魔弹掌握() and player_id == _魔弹逆向目标())
		_:
			return false


## 【魔弹】的落点：右手边（post 方向）最近的一名敌人 —— 服务端 _nearest_enemy 就是这么走的。
## 没有【魔弹掌握】时目标就固定是他；界面只让他亮，点了他才释放。
func _魔弹目标() -> int:
	return _沿方向找敌人(1)


## 【魔弹】的逆向落点：左手边（pre 方向）最近的一名敌人 —— 只有【魔弹掌握】802 能选
func _魔弹逆向目标() -> int:
	return _沿方向找敌人(-1)


## 从自己在座位表里的位置出发，按 step（+1 = 右手边 / -1 = 左手边）找最近的一名敌人
func _沿方向找敌人(step: int) -> int:
	var 列表: Array[GPlayer] = Data.player_list
	var n: int = 列表.size()
	var 我的: int = -1
	for i: int in range(n):
		if 列表[i].id == Logic.my_player_id:
			我的 = i
			break
	if 我的 < 0:
		return -1
	for k: int in range(1, n):
		var p: GPlayer = 列表[(我的 + step * k + n * n) % n]
		if _是敌方(p.id):
			return p.id
	return -1


## 本地角色有没有【魔弹掌握】（802）：有的话打【魔弹】时左手边那个对手也亮
func _有魔弹掌握() -> bool:
	var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
	return 我 != null and 魔弹掌握角色.has(我.role_id)


## 魔弹传递的可选落点：服务端在询问的 dst_ids 里给，只有当前传出方向上那个人
## （传递时不能改向，【魔弹掌握】只作用于主动打出那一步）。界面只把这个点亮，点他就传过去。
func _魔弹传递目标列表() -> Array[int]:
	var out: Array[int] = []
	for t: Variant in _pending.get("dst_ids", []):
		out.append(int(t))
	return out


## 这名玩家面前是否已经有某个基础效果（取自快照里的 basic_cards）
func _有基础效果(player_id: int, 卡名: int) -> bool:
	var 他: GPlayer = Data.get_player_by_id(player_id)
	if 他 == null:
		return false
	for 效果: GPlayer.BasicStatus in 他.basic_status_list:
		if 效果.card != null and 效果.card.card_name_enum() == 卡名:
			return true
	return false


## 这名玩家面前是否已有「圣盾」类基础效果：【圣盾】牌，或视作圣盾的【天使之墙】。
## 与服务端 base_v_shield 同一规则（battle_player.gd），选目标时按它把人挡住，
## 不要等发出去了才被服务端拒。
func _有圣盾效果(player_id: int) -> bool:
	var 他: GPlayer = Data.get_player_by_id(player_id)
	if 他 == null:
		return false
	return 他.has_status_skill(GConst.技能_天使之墙) or _有基础效果(player_id, GConst.CardName.Shield)


## 选中的手牌是否是【圣光】（抵挡用，不需要反击目标）
func _选中是圣光() -> bool:
	if _sel_cards.is_empty():
		return false
	var card: GCard = Data.get_card(_sel_cards[0])
	return card != null and card.card_name_enum() == GConst.CardName.HolyLight


## 选中的手牌是否是【圣盾】（行动阶段靠点人头像定目标：点谁贴给谁，点自己头像＝贴给自己）
func _选中是圣盾牌() -> bool:
	if _sel_cards.is_empty():
		return false
	var card: GCard = Data.get_card(_sel_cards[0])
	return card != null and card.card_name_enum() == GConst.CardName.Shield


## 选中的手牌是不是攻击牌（点目标即出手）
func _选中是攻击牌() -> bool:
	if _sel_cards.is_empty():
		return false
	var card: GCard = Data.get_card(_sel_cards[0])
	return card != null and card.is_attack()


## 选中的手牌是不是法术牌（同样点目标即释放，只是目标规则不同）
func _选中是法术牌() -> bool:
	if _sel_cards.is_empty():
		return false
	var card: GCard = Data.get_card(_sel_cards[0])
	return card != null and card.is_magic()


## 该卡牌是否为自己的盖牌
func _is_my_cover(card_id: int) -> bool:
	for cc: GCard in Data.cover_cards:
		if cc != null and cc.id == card_id:
			return true
	return false


# ============================================================
# 渲染：手牌 / 盖牌 / 玩家面板选中 / 按钮
# ============================================================
func _刷新交互() -> void:
	刷新手牌()
	刷新盖牌()
	刷新选中面板()
	_更新按键()
	# 只有选牌来源为 BasicEffect（从场上基础效果牌里选一张）的技能才让面板上的基础效果图标可点
	var 基础可点: bool = _mode == 4 and _skill_card_source == GConst.CardSource.BasicEffect
	for 面板: 战斗玩家面板 in _面板列表:
		面板.set_基础牌可点(基础可点)


## 点了场上的某枚基础效果图标（CardSource.BasicEffect 要选的就是它）：连它所在的玩家一起记下来
func _on_基础牌点击(玩家id: int, 牌id: int) -> void:
	if _mode != 4 or _skill_card_source != GConst.CardSource.BasicEffect:
		return
	if not _卡牌能点(牌id):
		return
	_sel_cards = [牌id]
	_sel_players = [玩家id]
	刷新盖牌()
	刷新选中面板()
	_更新按键()


## 我的手牌：固定排成一行并水平居中；位置够就摊开，不够才压间距（压到负数会叠着放），绝不换行
## 每张牌按 _卡牌能点 单独判定：够格的亮起来，其余的置灰且点不动
func 刷新手牌() -> void:
	for c: Node in HandArea.get_children():
		c.queue_free()
	var 张数: int = Data.hand_cards.size()
	if 张数 == 0:
		return
	var 可用宽: float = HandArea.size.x
	# 相邻两张之间的空隙：牌少时贴着排（0 是最好的），一行放不下才压成负数（叠着放）
	var 空隙: float = 0.0
	if 张数 > 1:
		空隙 = clampf((可用宽 - 手牌尺寸.x * float(张数)) / float(张数 - 1),
			-手牌尺寸.x * 手牌最多重叠比例, 0.0)
	# 两牌「左边」的距离 = 牌宽 + 空隙
	var 间距: float = 手牌尺寸.x + 空隙
	var 起点: float = (可用宽 - (手牌尺寸.x * float(张数) + 空隙 * float(张数 - 1))) * 0.5
	var 现在: int = Time.get_ticks_msec()
	var 还在手: Array[int] = []
	for i: int in range(张数):
		var card: GCard = Data.hand_cards[i]
		还在手.append(card.id)
		# 这一轮才补进来的牌：记下起算时刻，接下来按「已经过多久」往下落
		if not _上次手牌.has(card.id) and not _补牌起点.has(card.id):
			_补牌起点[card.id] = 现在
		var go: Node = _加卡牌(HandArea, card, 手牌尺寸, _卡牌能点(card.id))
		var 选中: bool = _sel_cards.has(card.id)
		go.call("设置选中", 选中)
		var ctl: Control = go as Control
		# 选中的牌往上抽出一截：表示「已经拿出来，等你按确定」
		var 上浮: float = 选中上浮像素 if 选中 else 0.0
		var 目标y: float = (HandArea.size.y - 手牌尺寸.y) * 0.5 - 上浮
		# 新补的牌从高处向下落回原位。手牌会因为广播反复重建，所以位置按「已过多久」现算，
		# 重建也接着演，不会中途跳回终点
		var 落高: float = _补牌落高(card.id, 现在)
		ctl.position = Vector2(起点 + 间距 * float(i), 目标y - 落高)
		if 落高 > 0.0:
			var 剩余: float = maxf(补牌落下时长 * (1.0 - _补牌进度(card.id, 现在)), 0.05)
			var t: Tween = ctl.create_tween()
			t.tween_property(ctl, "position:y", 目标y, 剩余).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_上次手牌 = 还在手
	for 记: Variant in _补牌起点.keys():
		if not 还在手.has(int(记)):
			_补牌起点.erase(记)


## 新补牌的落下进度 0～1（超过时长就清掉记录，返回 1）
func _补牌进度(card_id: int, 现在: int) -> float:
	if not _补牌起点.has(card_id):
		return 1.0
	var 已过: float = float(现在 - int(_补牌起点[card_id])) / 1000.0
	if 已过 >= 补牌落下时长:
		_补牌起点.erase(card_id)
		return 1.0
	return clampf(已过 / 补牌落下时长, 0.0, 1.0)


## 新补牌此刻该往上偏多少：起点最高，越接近结尾越小，最后回到 0（缓出，像轻轻放下）
func _补牌落高(card_id: int, 现在: int) -> float:
	var p: float = _补牌进度(card_id, 现在)
	if p >= 1.0:
		return 0.0
	return 补牌落下高度 * pow(1.0 - p, 2.0)


## 我的盖牌渲染进 ChooseArea（它不是布局容器，所以这里手工排成一行、整行居中）。
## 「要选盖牌」时可见且可点；点「盖牌」按钮查看时只可见、点不动。
## 张数多到一行放不下时压缩间距（可以叠着放），不会溢到区外。
func 刷新盖牌() -> void:
	for c: Node in ChooseArea.get_children():
		c.queue_free()
	var 张数: int = 0
	for cc: GCard in Data.cover_cards:
		if cc != null:
			张数 += 1
	if 张数 == 0:
		ChooseArea.visible = false
		return
	var 间距: float = 盖牌间距
	if 张数 > 1:
		间距 = clampf((ChooseArea.size.x - 盖牌尺寸.x * float(张数)) / float(张数 - 1),
			-盖牌尺寸.x * 手牌最多重叠比例, 盖牌间距)
	var 总宽: float = 盖牌尺寸.x * float(张数) + 间距 * float(张数 - 1)
	var 序: int = 0
	for cc: GCard in Data.cover_cards:
		if cc == null:
			continue
		var 可点: bool = _selecting_cover and _卡牌能点(cc.id)
		# 只是「点盖牌按钮查看」时一律保持原色（只读、不给点，但牌面要看得清）；
		# 只有在「要选盖牌」的询问里选不了的那几张才置灰
		var go: Node = _加卡牌(ChooseArea, cc, 盖牌尺寸, 可点, _selecting_cover)
		if go is Control:
			(go as Control).position = Vector2(
				(ChooseArea.size.x - 总宽) * 0.5 + float(序) * (盖牌尺寸.x + 间距),
				(ChooseArea.size.y - 盖牌尺寸.y) * 0.5)
		go.call("设置选中", _sel_cards.has(cc.id))
		序 += 1
	ChooseArea.visible = _selecting_cover or _查看盖牌


## 造一张卡牌节点挂到指定容器下（Card.tscn + scripts/CardUI.gd），点击回调统一接进来。
## 可置灰 = false 时「不可用」也保持原色（如只读查看自己的盖牌）
func _加卡牌(父: Node, card: GCard, 尺寸: Vector2, 可用: bool, 可置灰: bool = true) -> Node:
	var go: Node = 卡牌预制.instantiate()
	var ctl: Control = go as Control
	ctl.set_anchors_preset(Control.PRESET_TOP_LEFT)
	ctl.custom_minimum_size = 尺寸
	ctl.size = 尺寸
	ctl.scale = Vector2.ONE
	父.add_child(go)
	go.call("设置卡牌", card, 可用, 可置灰)
	go.call("设置发光色", 可选发光_红 if _正在弃牌() else 可选发光_绿)
	go.connect("点击", _on_card_clicked)
	return go


## 当前这次选牌是不是「弃牌」：应答式弃牌（手牌超限 / 被令弃牌），或技能询问的文案里提到弃。
## 「可选」发光框据此改用红光；出牌 / 应战 / 选目标仍用默认绿光。
func _正在弃牌() -> bool:
	if _mode == 2:
		var 应答号: int = int(_pending.get("respond_id", 0))
		return 应答号 == GConst.RespondType.Discard or 应答号 == GConst.RespondType.DiscardCover
	if _mode == 3:
		return str(_pending.get("ask_text", "")).contains("弃")
	return false


## 玩家面板：选中的目标染黄；当前可选的目标保持常色并亮起「可选中」光圈；
## 其余在「自己正在操作」（行动 / 应答 / 技能询问）期间压暗置灰 —— 亮着才点得动。
## 不是自己操作时（_mode == 0）不压暗，免得把别人面板上的 Turn 高亮一起压下去。
func 刷新选中面板() -> void:
	for 面板: 战斗玩家面板 in _面板列表:
		var pid: int = 面板.ID
		var 可选: bool = _玩家可选(pid)
		if _sel_players.has(pid):
			面板.modulate = 面板选中色
		elif _mode != 0 and not 可选 and pid != Logic.my_player_id:
			面板.modulate = 面板置灰色
		else:
			面板.modulate = 面板常态色
		面板.set("IsEnable", 可选)
	# 选中目标后顺带把提示画到他们头像上（配了「展示型」指示器的技能才有，如「给 X 张牌」「2 法术伤害」）
	_刷新头像提示()


## 当前技能的「展示型」指示器配置（配了「文案」才算）：选中目标后把一句话画到他们头像上。
## 分配型由 _刷新治疗分配 自己画，不走这里。发动技能（mode 4）与技能询问（mode 3）两条通道都认。
## 「选项提示」型的技能按弹窗里选定的效果取对应那份子配置（如【百鬼夜行】展示 / 不展示各一套）
func _头像提示配置() -> Dictionary:
	var 技能号: int = -1
	if _mode == 4:
		技能号 = _pending_skill_id
	elif _mode == 3:
		技能号 = _skill_ask_id
	if 技能号 < 0:
		return {}
	var 配置: Dictionary = GConst.技能指示器.get(技能号, {})
	# 「先弹选项」型还没在弹窗里选效果时不画任何头像提示
	if bool(配置.get("先弹选项", false)) and _已选参数.is_empty():
		return {}
	var 分效果: Dictionary = 配置.get("选项提示", {})
	if not 分效果.is_empty():
		if _已选参数.is_empty():
			return {}
		return 分效果.get(int(_已选参数[0]), {})
	return 配置 if 配置.has("文案") or 配置.has("分目标") else {}


## 一句展示提示的最终数值：先取它自己的固定值（「每目标」或「总数 ÷ 选中人数」），
## 再由 _提示数值 按「每牌 / 每能量」现算
func _显示数值(配置: Dictionary) -> int:
	var 固定: int = int(配置.get("每目标", 0))
	if 固定 <= 0:
		固定 = int(配置.get("总数", 0)) / maxi(_sel_players.size(), 1)
	return _提示数值(配置, 固定)


## 展示型提示的数值，按配置挑一种算法：
##   每牌   —— 每牌 × 已选牌数 + 偏移（如【魔道法典】伤害＝弃牌数 - 1）；一张牌都没选时无意义，按 0 处理。
##              再配「加参数」＝把弹窗里选定的效果值也算进来（如【死亡之触】伤害＝消耗治疗 + 弃牌数 - 3）
##   每能量 —— 每能量 × 自己当前星石总数（宝石 + 水晶）+ 偏移（如元素师【月光】）
##   其余   —— 用固定值（「每目标」或「总数 ÷ 选中人数」）
func _提示数值(配置: Dictionary, 固定值: int) -> int:
	if 配置.has("每牌"):
		if _sel_cards.is_empty():
			return 0
		var 值: int = int(配置.get("每牌", 0)) * _sel_cards.size() + int(配置.get("偏移", 0))
		if bool(配置.get("加参数", false)) and not _已选参数.is_empty():
			值 += int(_已选参数[0])
		return 值
	if 配置.has("每能量"):
		var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
		if 我 == null:
			return 0
		return int(配置.get("每能量", 0)) * (我.gem + 我.crystal) + int(配置.get("偏移", 0))
	return 固定值


## 把提示写到被选中的目标头像上：给了「每目标」就各写该值（如【魔爆冲击】每名对手 2 法术伤害）；
## 否则按「总数 ÷ 选中人数」平均分（如【天使祝福】2 张：选 1 人＝他给你 2 张，选 2 人＝各给你 1 张）。
## 没选中的收起提示。与分配型共用同一批 Label（_取治疗提示），只是文案来源不同
func _刷新头像提示() -> void:
	# 魔弹 / 念弹这类「写不进静态指示器表、只能现算」的提示优先：
	# 魔弹的数值随传递递增；念弹的自身伤害取决于目标有无治疗与自身斗气数
	var 动态提示: Dictionary = _魔弹头像提示()
	if 动态提示.is_empty():
		动态提示 = _念弹头像提示()
	# 先把上一帧画过、这一帧不再画的头像收起（否则切换目标时旧目标的文本会残留）
	for 旧: int in _动态提示过的头像:
		if not 动态提示.has(旧):
			_取治疗提示(旧).visible = false
	_动态提示过的头像.clear()
	if not 动态提示.is_empty():
		for 面板: 战斗玩家面板 in _面板列表:
			var 文: String = str(动态提示.get(面板.ID, ""))
			if 文.is_empty():
				continue
			_贴头像提示(面板, _取治疗提示(面板.ID), 文)
			_动态提示过的头像.append(面板.ID)
		return
	var 配置: Dictionary = _头像提示配置()
	if 配置.is_empty():
		return
	# 「分目标」按已选顺序给每个目标各配一句（如【冰冻】第 1 个吃伤害、第 2 个 +1 治疗）；
	# 「自身」那句（如【魔道法典】对自己也有伤害）画在自己头像上，自己同时是目标就并成两行
	var 分目标: Array = 配置.get("分目标", [])
	var 自身配置: Dictionary = 配置.get("自身", {})
	# 「反选」＝提示画在「没被选中的」角色身上（如【百鬼夜行】展示火系妖力：选中的 2 人是被保下来的，
	# 其余所有角色挨伤害）；不配就是常规——只画在选中的目标身上。
	# 「序 < 0」＝这名角色没被选中，与 反选 同真同假时才画（常规要选中、反选要没选中）
	var 反选: bool = bool(配置.get("反选", false))
	for 面板: 战斗玩家面板 in _面板列表:
		# 座位不够的隐藏面板 ID 是哨兵 -1（见 _填面板 那段）：它们背后没有玩家。
		# 常规提示只画「已选中」的人，本来就碰不到它们；「反选」是画「没选中的人」，必须显式排除
		if 面板.ID < 0:
			continue
		var 段: Array[String] = []
		var 序: int = _sel_players.find(面板.ID)
		if (序 < 0) == 反选:
			var 子配置: Dictionary = 配置
			if not 分目标.is_empty():
				子配置 = 分目标[序] if 序 >= 0 and 序 < 分目标.size() else {}
			var 子文案: String = str(子配置.get("文案", ""))
			if not 子文案.is_empty():
				var 目标值: int = _显示数值(子配置)
				if 目标值 > 0:
					段.append(子文案 % 目标值)
		if 面板.ID == Logic.my_player_id and not 自身配置.is_empty():
			var 自身值: int = _显示数值(自身配置)
			if 自身值 > 0:
				段.append(str(自身配置["文案"]) % 自身值)
		if 段.is_empty():
			_取治疗提示(面板.ID).visible = false
			continue
		_贴头像提示(面板, _取治疗提示(面板.ID), "\n".join(段))


## 魔弹「准备打出」时要画在各落点头像上的伤害提示：player_id -> 文案。
## 两种情况：主动打出【魔弹】显示基础伤害；魔弹传递时显示「当前伤害 + 1」（每次传递递增 1，
## 当前伤害由服务端写在询问的 args[1] 里）。只有真能继续传递的牌才提示（出【圣光】是抵挡、不传伤害）
func _魔弹头像提示() -> Dictionary:
	var out: Dictionary = {}
	if _mode == 2 and int(_pending.get("respond_id", 0)) == GConst.RespondType.Bullet:
		if _sel_cards.size() != 1 or not _可继续传递魔弹(Data.get_card(_sel_cards[0])):
			return out
		var args: Array = _pending.get("args", [])
		var 当前: int = int(args[1]) if args.size() > 1 else GConst.魔弹基础伤害
		for t: int in _魔弹传递目标列表():
			out[t] = "%d 法术伤害" % (当前 + 1)
		return out
	if _mode == 1 and _sel_cards.size() == 1:
		var 牌: GCard = Data.get_card(_sel_cards[0])
		if 牌 == null or 牌.card_name_enum() != GConst.CardName.Missile:
			return out
		# 主动打出的【魔弹】按基础伤害算；地 / 火牌当魔弹走【魔弹融合】803，由静态指示器负责
		for 面板: 战斗玩家面板 in _面板列表:
			if _可作法术目标(牌, 面板.ID):
				out[面板.ID] = "%d 法术伤害" % GConst.魔弹基础伤害
		return out
	return out


## 格斗【念弹】的指示器（选中目标时现算）：目标受 1 点法术伤害；若目标没有治疗，则自己也受「斗气数」点法术伤害。
## 数值取决于目标的治疗数与自身斗气数，写不进静态指示器表（同【魔弹】，只能现算）
func _念弹头像提示() -> Dictionary:
	var out: Dictionary = {}
	if _mode != 3 or _skill_ask_id != GConst.技能_念弹 or _sel_players.is_empty():
		return out
	var 目标id: int = int(_sel_players[0])
	var 目标: GPlayer = Data.get_player_by_id(目标id)
	if 目标 == null:
		return out
	out[目标id] = "1 法术伤害"
	# 目标有治疗 → 由治疗抵挡、自己不吃伤害；没有治疗 → 自己受等于【斗气】数的法术伤害
	if 目标.cross_num == 0 and 目标id != Logic.my_player_id:
		var 斗气: int = _斗气数()
		if 斗气 > 0:
			out[Logic.my_player_id] = "%d 法术伤害" % 斗气
	return out


## 我的【斗气】数（格斗专有指示物，槽 0；对应角色表的「0:斗气:6」）
func _斗气数() -> int:
	var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
	if 我 == null or 我.tokens.is_empty():
		return 0
	var t: GPlayer.Token = 我.tokens[0] as GPlayer.Token
	return t.num if t != null else 0


## 这张牌在魔弹传递里是「继续传递」而不是「圣光抵挡」：抵挡不往下传伤害，也就不该画伤害提示
func _可继续传递魔弹(牌: GCard) -> bool:
	if 牌 == null or 牌.card_name_enum() == GConst.CardName.HolyLight:
		return false
	return _可回魔弹牌(牌.id)


## 发动技能时选中的目标数是否合法：服务端给的最少~最多（target_max 省略＝必须刚好 need_target 个）。
## 配了 target_max_from_cards 的技能上限随已选牌数现算（如【圣洁法典】＝弃牌数 - 2）：
## 玩家取消一张牌后上限就降了，光看下发的静态 target_max 会让「确定」继续可点、提交却被服务端拒
func _目标数合法() -> bool:
	# 目标已锁死（【瘟疫】/【剧毒新星】自动选全体）：当前这批就是全部目标，不再按数量校验
	if _目标锁死:
		return true
	if _skill_need_target <= 0:
		return _sel_players.is_empty()
	if _sel_players.size() < _skill_need_target:
		return false
	if _skill_target_max_from_cards > 0:
		# 上限随已选牌数现算（如【圣洁法典】＝弃牌数 - 2），且不低于「最少目标数」；
		# 这条必须单独判，不能并进下面那句「上限 ≤ 需目标数就放行」——
		# 取消一张牌后上限正好掉到「最少目标数」（如 3 张牌 → 上限 1），并进去就会被误放行
		var 上限: int = maxi(_skill_need_target, _sel_cards.size() - _skill_target_max_from_cards)
		return _sel_players.size() <= 上限
	return _skill_target_max <= _skill_need_target or _sel_players.size() <= _skill_target_max


## 当前已选目标是否都落在给定白名单里（白名单为空＝不限制）
func _目标在白名单(白名单: Array) -> bool:
	if 白名单.is_empty():
		return true
	for pid: int in _sel_players:
		if not 白名单.has(pid):
			return false
	return true


## 参数选项各自目标白名单的并集：不同选项允许的目标可能不同（如【神圣领域】给队友加血 / 打敌方）
func _参数选项目标白名单() -> Array:
	var out: Array = []
	for 项: Variant in _skill_arg_choices:
		var 单: Array = (项 as Dictionary).get("targets", [])
		for pid: Variant in 单:
			if not out.has(int(pid)):
				out.append(int(pid))
	return out


## 这张牌此刻是否躺在某名玩家的基础效果区（CardSource.BasicEffect 要选的就是它）
func _是场上基础效果牌(card_id: int) -> bool:
	for p: GPlayer in Data.player_list:
		for st: GPlayer.BasicStatus in p.basic_status_list:
			if st.card != null and st.card.id == card_id:
				return true
	return false


## 这名玩家此刻能不能被点选为目标：同时决定面板「可选中」箭头是否亮起、以及点下去是否生效
## （不亮就是点不动，不再靠「点到不能选的再提示」）
## 注意：**自己也可以是合法目标** —— 服务端 _do_magic 里【圣盾】【虚弱】【中毒】都允许指向自己
## （不给 dst 时它甚至默认就是自己），所以这里不再一律排除自己，改由各分支自己判：
##   攻击牌（v_attack 拒同队）、应战反击（v_reattack 拒自己与同队）、魔弹落点（只可能是敌人）天然不含自己。
func _玩家可选(player_id: int) -> bool:
	if player_id < 0 or player_id == GConst.GUEST:
		return false
	# 目标已锁死（【瘟疫】/【剧毒新星】自动选全体）：头像一律不可点，改不了目标
	if _目标锁死:
		return false
	if _mode == 1:
		# 先选牌、再亮目标：还没选牌时谁都不亮
		var 牌: GCard = Data.get_card(_sel_cards[0]) if not _sel_cards.is_empty() else null
		if 牌 == null:
			return false
		# 攻击牌只能打敌方（服务端 v_attack 对同队直接拒）；法术按 _do_magic 的分支判
		if 牌.is_attack():
			# 暗杀者潜行（横置）期间不能被主动攻击选中（否则点亮后点了会被服务端拒，客户端闪一下没反应）
			return _是敌方(player_id) and not _潜行中(player_id)
		return _可作法术目标(牌, player_id)
	if _mode == 2:
		var rid: int = int(_pending.get("respond_id", 0))
		if rid == GConst.RespondType.ReplyAttack:
			# 应战同样先选牌；选【圣光】抵挡时不需要反击目标
			return not _sel_cards.is_empty() and not _选中是圣光() and _可作反击目标(player_id)
		if rid == GConst.RespondType.Bullet:
			# 魔弹传递：选好传递牌后，只有服务端给的那几个落点亮（【圣光】抵挡不需要目标）
			return not _sel_cards.is_empty() and not _选中是圣光() and _魔弹传递目标列表().has(player_id)
		return false
	if _mode == 3:
		# 分配型指示器配了「仅队友」时（如神官【神圣契约】），只有队友头像能点（不含自己）
		if bool(_分配配置().get("仅队友", false)) and not _是队友(player_id):
			return false
		if _skill_ask_need_target <= 0:
			return false
		# 服务端给了合法目标就只让这几名玩家亮（如【天使之歌】只能选面前有基础效果的人）
		return _skill_targets.is_empty() or _skill_targets.has(player_id)
	if _mode == 4:
		if bool(_分配配置().get("仅队友", false)) and not _是队友(player_id):
			return false
		if _skill_need_target <= 0 and _skill_target_max <= 0:
			return false
		# 参数选项带了各自的目标白名单时，按它们的并集点亮（如【神圣领域】两种用法打不同的人）
		var 选项白名单: Array = _参数选项目标白名单()
		if not 选项白名单.is_empty():
			return 选项白名单.has(player_id)
		# 服务端给了合法目标就只让这几名玩家亮（如【魔弹融合】只打右手边最近的对手）
		return _skill_targets.is_empty() or _skill_targets.has(player_id)
	return false


## 确定/取消/盖牌/放弃行动 的可见与可用（场景里那几个按钮默认都是 visible=false）
func _更新按键() -> void:
	BtnOK.visible = _mode != 0
	BtnCancel.visible = _mode != 0
	BtnOK.disabled = _确定不可用()
	BtnCancel.disabled = not _取消可用()
	# 「盖牌」按钮：只有自己有盖牌时才显示，点开只是查看盖牌（不结束回合）
	BtnCovered.visible = not Data.cover_cards.is_empty()
	BtnCovered.disabled = Data.cover_cards.is_empty()
	BtnResign.visible = _模式可放弃行动()
	BtnResign.disabled = not _模式可放弃行动()
	var 特殊可用: bool = _按钮是特殊行动() or _按钮是放弃()
	BtnSpecila.visible = 特殊可用
	# 仲裁者审判满时「特殊行动」也锁死：按钮留着但灰掉
	BtnSpecila.disabled = not 特殊可用 or (_按钮是特殊行动() and _末日审判锁死行动())
	# 参数选项按钮：选够它要求的牌/目标、且目标落在它自己的白名单里才让点
	for 项: Variant in _参数按钮:
		var d: Dictionary = 项
		var b: Button = d["按钮"] as Button
		if not is_instance_valid(b):
			continue
		var 缺: bool = _sel_cards.size() < int(d["需牌"]) or _sel_players.size() < int(d["需目标"])
		if not 缺 and not _目标在白名单(d["目标白名单"]):
			缺 = true
		b.disabled = 缺


func _确定不可用() -> bool:
	# 特殊行动（购买/合成/提炼）没有「确定」，由菜单里的按钮直接提交
	if _mode == 5 or _mode == 6:
		return true
	# 弹窗型询问（【神之庇护】/ 治疗抵挡）：确定＝把居中的选项窗重新弹出来
	if not _弹窗选项.is_empty():
		return false
	# 参数选择窗开着时（【风之洁净】/【天使之歌】确定后弹出的选择）不再重复弹，等玩家选完
	if 参数选择窗.visible:
		return true
	if _mode == 1:
		# 【圣盾】：目标只能点人头像来定（点谁就把盾贴在谁面前，自己也不例外，点自己头像即可）。
		# 不给目标提交时服务端默认就是对自己施放，按「确定」很容易误把自己贴成目标 —— 所以直接灰掉
		if _选中是圣盾牌():
			return true
		return _sel_cards.is_empty() and _sel_players.is_empty()
	if _mode == 3:
		# 单份额外行动（如【迅捷赐福】/【风怒追击】）：确定＝发动它；引擎判「不能发动」时置灰
		if _额外行动单选 >= 0:
			return not _额外行动可选
		# 分配型指示器（如冰霜祷言）：选够治疗点、且要选牌时选够牌才让「确定」
		if not _分配配置().is_empty():
			var 治疗牌够: bool = _sel_cards.size() >= _skill_ask_need_card if _skill_ask_need_card > 0 else true
			return not (治疗牌够 and _分配已满())
		if not _是技能询问:
			return true
		# need_card 是「最少要选几张」，点选上限另由 _skill_card_max 管（如【法术反弹】可弃 1~N 张同系牌），
		# 所以这里用 ≥ 而不是 ==，否则多选了反而点不动「确定」
		var 牌够: bool = _sel_cards.size() >= _skill_ask_need_card if _skill_ask_need_card > 0 else true
		var 目标够: bool = _sel_players.size() >= _skill_ask_need_target if _skill_ask_need_target > 0 else true
		# 「先弹选项」型（【百鬼夜行】）：效果已在弹窗里选好，这里跟普通询问同一条判定 —— 选够牌 / 目标才让点
		if _先弹选项:
			return not (牌够 and 目标够 and not _已选参数.is_empty())
		# 有选项时「确定」始终不可用，由选项按钮提交
		return true if not _skill_options.is_empty() else not (牌够 and 目标够)
	if _mode == 4:
		# 分配型指示器（如圣疗 / 治愈之光 / 治疗术 / 神圣领域）：选够治疗点、且要选牌时选够牌才让「确定」
		if not _分配配置().is_empty():
			var 治疗牌够: bool = _sel_cards.size() >= _skill_need_card if _skill_need_card > 0 else true
			return not (治疗牌够 and _分配已满())
		# 「先弹选项」型（【死亡之触】）：还没在弹窗里选效果时不能确定；选完后跟普通技能同一条判定
		if _先弹选项 and _已选参数.is_empty():
			return true
		# 有参数选项时「确定」始终不可用，由选项按钮提交（「先弹选项」型是弹窗里选、再按「确定」，除外）
		if not _skill_arg_choices.is_empty() and not _先弹选项:
			return true
		# 需牌是最少张数（如【暗影流星】要弃 2 张、【欺诈】可弃 2~3 张），选够才让点「确定」
		# need_card==0 表示「一张都不选也可以」（如【灵魂镜像】最多弃 3 张、也可不弃），
		# 点选上限另由 card_max 管，故这里直接放行
		var 牌够: bool = _sel_cards.size() >= _skill_need_card if _skill_need_card > 0 else true
		return not (牌够 and _目标数合法())
	if _mode == 2:
		match int(_pending.get("respond_id", 0)):
			GConst.RespondType.ReplyAttack:
				if _sel_cards.is_empty():
					return true
				if _选中是圣光():
					return false
				if not _可应战():
					return true
				return _sel_players.is_empty()
			GConst.RespondType.Bullet:
				if _sel_cards.is_empty():
					return true
				# 【圣光】抵挡不需要目标；【魔弹】要先点亮的落点
				return not _选中是圣光() and _sel_players.is_empty()
			GConst.RespondType.Discard, GConst.RespondType.DiscardCover:
				return _sel_cards.size() != _need_cards
			GConst.RespondType.Weaken, GConst.RespondType.Heal:
				return false
			_:
				return false
	return true


## 行动阶段才能「无法行动」
func _模式可放弃行动() -> bool:
	# 「放弃行动」不是标准行为（原版普通行动阶段 canGiveUp=false）：只有服务端在本次询问里
	# 下发了放弃命令（被【挑衅】或额外行动阶段）才让点；想跳过自己回合用测试键 8
	return _mode == 1 and _可放弃行动


## 场景 BtnSpecila 在行动阶段是「特殊行动」（购买 / 合成 / 提炼）。
## 本阶段不放行特殊行动时不show：额外行动阶段只放行它声明的种类（如【特殊加工】给的是
## 「攻击/法术行动」，见 GConst.放行动作），被【挑衅】时也只放行攻击，都不该出现特殊行动按钮
func _按钮是特殊行动() -> bool:
	return _mode == 1 and GConst.放行动作(GConst.ActionType.Special, _行动允许)


## 场景 BtnSpecila 在魔弹传递的询问里仍是「放弃」（沿用旧用法；应战时的放弃已挪给「取消」）
func _按钮是放弃() -> bool:
	return _mode == 2 and int(_pending.get("respond_id", 0)) == GConst.RespondType.Bullet


## 「取消」是否可用：技能询问 / 发动技能 / 特殊行动 / 应战放弃 / 魔弹放弃传递 / 虚弱强摸 / 治疗抵御
func _取消可用() -> bool:
	if _mode == 3:
		# 技能询问：强制的那次（can_cancel=false，如【水之神力】交牌）不许取消
		if _是技能询问:
			return _skill_ask_can_cancel
		return true
	if _mode == 4 or _mode == 5 or _mode == 6:
		return true
	if _mode == 2:
		var rid: int = int(_pending.get("respond_id", 0))
		return rid == GConst.RespondType.ReplyAttack \
			or rid == GConst.RespondType.Bullet \
			or rid == GConst.RespondType.Weaken \
			or rid == GConst.RespondType.Heal
	return false


# ---------------- 技能区 ----------------
## 加一个纯文字按钮（技能选项 / 额外行动 / 特殊行动用；技能本体走 Skill.tscn）
func _加文本按钮(文本: String, 回调: Callable, 可用: bool = true) -> void:
	var b: Button = Button.new()
	b.text = 文本
	b.custom_minimum_size = Vector2(164.0, 44.0)
	b.add_theme_font_size_override("font_size", 22)
	b.disabled = not 可用
	b.pressed.connect(回调)
	ChildrenSkillArea.add_child(b)
	_技能按钮.append(b)
	_显示技能区()


func _显示技能区() -> void:
	SkillArea.visible = true
	ChildrenSkillArea.visible = true


func _隐藏技能区() -> void:
	SkillArea.visible = false
	ChildrenSkillArea.visible = false


## 点中的技能按钮亮起黄色外发光，其余熄灭。
## 取消 / 提交行动都会 _清空技能按钮（或重建），发光随之复位，不用额外清。
func _标记选中技能(按钮: Node) -> void:
	for b: Node in _技能按钮:
		if b is 技能按钮:
			(b as 技能按钮).设置选中(b == 按钮)


func _清空技能按钮() -> void:
	for b: Node in _技能按钮:
		if is_instance_valid(b):
			b.queue_free()
	_技能按钮.clear()
	_参数按钮.clear()
	_隐藏技能区()
