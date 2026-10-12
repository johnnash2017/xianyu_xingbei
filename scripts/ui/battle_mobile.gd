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
## 屏幕左上角的测试指令提示（测试用，仅显示键位说明）
@export var 测试提示: Label
## 测试提示的常态透明度（取自 .tscn 里设的 modulate；鼠标指上去变不透明，移开恢复）
var _测试提示常态透明: float = 1.0
## 拖动测试提示时鼠标相对面板左上角的偏移（零向量 = 当前没在拖）
var _测试提示拖动偏移: Vector2 = Vector2.ZERO
## 本房间是否开了调试模式（房主建房时勾选、服务端随 Game 快照下发）：
## 关着时不响应测试指令，也不显示那个可拖拽的测试提示
var _调试模式: bool = false
@export var Content_2: RichTextLabel    # 日志控件（场景里挂着 AutoClearLog.gd；RichTextLabel 才能按行上色）
@export var MsgRoot: ScrollContainer    # 日志滚动区（展开日志时滚到最新一条）
@export var Content: GridContainer     # 聊天条目容器
@export var InputField: LineEdit
@export var BtnSubmit: Button
@export var BtnLogExpand: Button
@export var BtnChatExpand: Button
@export var WinPanel: Control
@export var WinImg: TextureRect
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
@export var BtnSetting: Button         # 右下角设置：打开设置浮层（调背景音乐 / 效果音音量）
## 本地「先选一项」的星石步骤是为哪个特殊行动开的（选完要按它提交）
var _待定特殊行动: int = GConst.SpecialAction.Buy
## 本地询问（不经服务端）：冒险家【冒险者天堂】提炼后点头像分配星石
var _本地询问: bool = false
## 本地「先在二级技能栏里选一项」的步骤（不走服务端，0＝没有）：
##   1＝冒险者天堂选额外提炼数  2＝特殊行动（购买/合成/提炼）选星石组合
##   3＝特殊行动三选一          4＝冒险家提炼前问是否触发【冒险者天堂】
var _本地选项阶段: int = 0
## 【冒险者天堂】提炼流程的阶段（0＝不在流程中）：4＝选取星石组合并点头像分配
var _提炼阶段: int = 0
## 本次提炼是不是冒险家那条（【冒险者天堂】）流程：是的话跳过常规提炼，直接问额外提炼数 X，
## 再把「基本提炼 2 颗 + 额外 X 颗」合成一份选构成、分给队友（见 _天堂问触发 → _天堂列组合）
var _提炼是冒险家流程: bool = false
## 【冒险者天堂】本次提炼总数＝基本提炼 2 颗 + 额外提炼 X 颗
var _提炼总数: int = 0
## 【冒险者天堂】选定的额外提炼数 X（同时就是要移除的自身能量数）
var _提炼减能量: int = 0
## 【冒险者天堂】选定的整份星石构成（宝石 / 水晶颗数，加起来＝_提炼总数）
var _提炼宝石: int = 0
var _提炼水晶: int = 0

## 预制体目录（格子/聊天条目与参考脚本一致）
const 预制目录: String = "res://scenes/prefabs/battlemobile/"
## 提示显示后自动隐藏的秒数（同参考工程的 Invoke("hideHint", 3f)）
const 提示停留秒: float = 3.0
## 结算界面的 VICTORY 横幅：按胜方队伍取图（同参考工程 TipArea::win 的 resource/GameWin*.png）
const 红队胜利图: Texture2D = preload("res://assets/textures/battle/GameWinRed.png")
const 蓝队胜利图: Texture2D = preload("res://assets/textures/battle/GameWinBlue.png")
## 日志最多保留的行数（同参考工程 AutoClearLog 的裁剪行数）
const 日志最大行: int = 233
## 宝石/水晶/星杯格子的最小尺寸（Unity 转过来的 Image 预制体是 0×0，必须给尺寸）
## 正方形：贴图本身近似正方形（宝石 29×30、水晶 29×30、星杯 23×23），
## 给 30×40 会把它们上下拉伸；队伍条容器高 30、5 列正好 5×30=150
const 格子最小尺寸: Vector2 = Vector2(30.0, 30.0)
## 队伍条上星杯格子的悬停提示
const 星杯提示: String = "星杯 凑齐五个圣杯达成特殊胜利。"
## 队伍条上士气数字的悬停提示
const 士气提示: String = "士气 士气归零的一方战斗失败"
## 卡牌预制体（挂 scripts/CardUI.gd，已解耦为「塞数据 + 点击回调」）
const 卡牌预制: PackedScene = preload("res://scenes/prefabs/battlemobile/Card.tscn")
## 技能按钮预制体（挂 scripts/SkillUI.gd，同上）
const 技能预制: PackedScene = preload("res://scenes/prefabs/battlemobile/Skill.tscn")
## 悬浮说明框预制体（框 + 富文本结构都在场景里，见 说明提示框）
const 说明框预制: PackedScene = preload("res://scenes/prefabs/ui/TipBox.tscn")
## 头像提示控件预制体（治疗 / 法术 / 攻击伤害的文字，见 _取治疗提示）
const 治疗提示预制: PackedScene = preload("res://scenes/prefabs/battlemobile/HealTip.tscn")
## 头像提示里被划掉的行的粗删除线（见 _铺粗删除线）
const 删除线预制: PackedScene = preload("res://scenes/prefabs/battlemobile/StrikeLine.tscn")
## 治疗加号特效（见 _生成治疗加号）
const 加号预制: PackedScene = preload("res://scenes/prefabs/battlemobile/HealPlus.tscn")
## 受伤飘字（见 _生成伤害飘字）
const 飘字预制: PackedScene = preload("res://scenes/prefabs/battlemobile/HurtFloat.tscn")
## 给牌动效预制体（一张卡背从交牌人飘到收牌人，见 _给牌特效）
const 给牌预制: PackedScene = preload("res://scenes/prefabs/effects/dealCard.tscn")
## 交多张给牌动效之间的起飞间隔（秒）：一张接一张，不叠在一起
const 给牌间隔: float = 0.12

## 法术牌名（卡表卡名）→ 出牌音效后缀名（assets/media/audio 下 spell-<后缀>.ogg）
const 法术音效后缀: Dictionary = {
	"圣光": "holyLight", "魔弹": "magicBullet", "圣盾": "holyShield",
	"中毒": "poison", "虚弱": "weakness",
}
## 弃牌动效预制体（卡背从弃牌者身上飞向画面中心并淡出，见 _弃牌特效）
const 弃牌预制: PackedScene = preload("res://scenes/prefabs/effects/discardCard.tscn")
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
## 盖牌区里实际渲染的缩放：点「盖牌」按钮看自己的盖牌、以及要选盖牌时都按它缩一档
const 盖牌显示缩放: float = 0.7
## 盖牌区里整行相对「区正中」再往下偏这么多像素（微调它和上下别的元素之间的空隙）
const 盖牌显示下移: float = 40.0
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
## 头像提示里被 [zwj] 标记的行，另外压一条这么粗的浅灰线（颜色在 StrikeLine.tscn 里）。
## 不直接用 BBCode 的 [s]：字体自带的那条删除线在 26 号字下只有 1~2px，而且位置偏低，
## 所以配置里只留 [zwj]（零宽、自己不渲染）当标记，线整个由 _铺粗删除线 画
const 删除线粗细: float = 3.5
## 头像提示的文字配色（BBCode 十六进制）：治疗＝浅蓝、法术伤害＝洋红、攻击伤害 / 物理伤害＝红，见 _提示上色
const 提示色_治疗: String = "9ED9FF"
const 提示色_法术伤害: String = "FF3CFF"
const 提示色_攻击伤害: String = "FF3C3C"
## 治疗加号特效：单个「+」的占位尺寸（配色在 HealPlus.tscn 里，与上面的 提示色_治疗 是同一个浅蓝）
const 加号尺寸: Vector2 = Vector2(56.0, 56.0)
## 加号特效的散布范围 / 错开延迟 / 上升速度的倍率（1.0 = 原始手感）：
## 范围与延迟按需求放大到 3 倍，上升速度保持原速（时长 = 基础 × 时间倍率 ÷ 速度倍率）
const 加号范围倍率: float = 3.0
const 加号时间倍率: float = 3.0
const 加号速度倍率: float = 1.0

## 受伤飘字（受到的伤害数字）：从头像中间冒出、向上飘出并淡掉（见 _生成伤害飘字）。
## 字色与上面的 提示色_法术伤害 / 提示色_攻击伤害 是同一套：法术＝洋红、攻击＝红。
## 字号 / 描边在 HurtFloat.tscn 里，时长 1.8 秒（＝上飘距离不变、速度减半）
const 飘字尺寸: Vector2 = Vector2(240.0, 120.0)
## 数字大小的「基准缩放」按本次伤害点数走：1 点最小 0.8 倍、7 点及以上最大 1.5 倍，中间线性过渡
const 飘字最小缩放: float = 0.8
const 飘字最大缩放: float = 1.5
const 飘字最小点数: int = 1
const 飘字最大点数: int = 7
## 冒头动画：出场先是基准大小（× 1），用 放大时长 撑到「基准 × 冒头倍率」，再用 缩回时长 缩回基准，
## 缩回之后才开始上飘
const 飘字冒头倍率: float = 3.0
const 飘字放大时长: float = 0.25
const 飘字缩回时长: float = 0.25
## 上飘距离与时长（冒头动画结束后才开始算）
const 飘字上飘: float = 96.0
const 飘字时长: float = 1.8
const 飘字色_法术伤害: Color = Color("ff3cff")
const 飘字色_攻击伤害: Color = Color("ff3c3c")

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
	"士气": "#E8A0D8",     # 队伍士气升降
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
## 拥有【魔弹掌控】（802）的角色：主动打【魔弹】时左右两个方向都能选（对照 skillDB 802「可选逆向传递」）。
## 注意只在「主动使用」那一步生效 —— 魔弹打出后传递方向就固定了，传递时不能改向
const 魔弹掌控角色: Array[int] = [8]
## 【黑暗束缚】2903 的「响应侧」：不能用【魔弹】转弹、也不能用【圣光】格挡（对照 role_moqiang 的
## v_remissile / v_block）。「主动阶段整片禁用法术牌」那半条在下面的 行动阶段禁用法术牌角色 里
const 魔弹全禁角色: Array[int] = [29]
## 行动阶段不能使用法术牌的角色：
##   魔剑士【暗影抗拒】904（对照 role_mojian 的 v_allow_action）
##   魔枪【黑暗束缚】2903「你始终不能使用法术牌」（对照 role_moqiang 的 v_allow_action；
##   同参考客户端 MoQiang::normal() 里的 handArea->disableMagic()，「充盈」这类要选法术牌的技能询问不受影响）
const 行动阶段禁用法术牌角色: Array[int] = [9, 29]
## 仲裁者：审判满上限时本回合只能发动【末日审判】（对照 ZhongCai::v_allow_action）
const 仲裁者角色: int = 14
## 苍炎魔女：【烈焰形态】下除水系、暗系外的攻击牌视为火系（对照 role_monv._is_fire_like）
const 苍炎魔女角色: int = 30

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
## 本次等待的说明（服务端下发，如「等待应战响应」）：写在被等玩家的头像上
var _等待文案: String = ""
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
## 所有玩家手上的宝石总数：除队伍宝石池之外再记一份 —— 【灵魂赐予】这类
## 「直接给玩家宝石」的变动只动个人宝石，队伍池不变，只有它看得出来
var _上次个人宝石: int = 0

# ---------------- 交互状态 ----------------
## 0 空闲 / 1 行动 / 2 响应 / 3 技能询问 / 4 发动技能 / 6 本地选项步骤（特殊行动三选一、选星石等）
var _mode: int = 0
## 本次行动询问是否允许「放弃行动」：服务端下发了 ACTION_NONE 命令才置真
## （对照原版 canGiveUp：普通行动阶段不容许放弃，被挑衅 / 额外行动阶段才容许）
var _可放弃行动: bool = false
## 本次行动阶段是否「不可行动」（非额外行动阶段、技能栏没技能、手牌全打不出去）：
## 置真时提示玩家点「确定」把手牌全弃掉摸 4 张（服务端 Unactional）
var _不可行动: bool = false
## 本次行动阶段放行动作的种类（GConst.ActionType：Any / Attack / AttackMagic / Magic…），
## 由服务端的行动询问下发。额外攻击行动（如女武神【神圣追击】）只给 Attack，
## 界面据此把法术牌置灰——不放行还亮着的话点了必被服务端拒
var _行动允许: int = GConst.ActionType.Any
## 本阶段是否禁止特殊行动（发动过「启动」技能后：只能再攻击 / 法术）
var _行动禁特殊: bool = false
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
## 这次「多份额外行动」是用二级技能栏列的（选中哪项就把 _额外行动单选 设成它，交给「确定」发动）
var _额外行动用二级栏: bool = false
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
## 「先弹选项」型（技能指示器配了「先弹选项」，如灵符师【百鬼夜行】）：在二级技能栏里选效果之前
## 不让点牌 / 点目标（需牌 / 目标数临时清零），选完效果在 _应用选项目标数 里还原 / 收紧
var _先弹选项: bool = false
## 二级技能栏里已选定的效果 args（原样随「确定」上交；没选之前「确定」不可用）
var _已选参数: Array = []
## 「先弹选项」型询问里服务端原本给的目标数：选完效果后若「选项目标数」没配该效果，用它还原
## （如【剑气斩】：没配「选项目标数」，选完剑气数后仍要能选 1 名目标）
var _选项原始目标数: int = 0
## 同上，「先弹选项」型发动技能时临时清零、选完效果再还原的最多目标数 / 需牌 / 最多牌
## （选效果之前不让点牌、不让点目标，选完才放开 —— 见 _选择技能 / _应用选项目标数）
var _选项原始最多目标: int = 0
var _选项原始需牌: int = 0
var _选项原始最多牌: int = 0
## 同上，技能本体的选牌来源 / 需盖牌数：选项自带这两个值时以选项为准
## （如【倒逆之蝶】第 ② 项要在盖牌区点 2 张【茧】，来源就变成「手牌+盖牌」、需盖牌 2）
var _选项原始来源: int = GConst.CardSource.Hand
var _选项原始盖牌需数: int = 0
## 已选定要发动的技能号与它对应的 action_type
var _pending_skill_id: int = -1
var _pending_skill_type: int = -1
var _skill_need_card: int = 0
var _skill_need_target: int = 0
## 本次发动技能的合法目标（服务端在技能上给的 targets，非空时只让这几名玩家亮；
## 例：【魔弹融合】默认只有右手边最近的对手，有【魔弹掌控】时左右各一个）
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
## 手牌 + 盖牌混选时要求其中几张必须是盖牌（服务端给的 cover_need；0＝不要求，
## 如【魔贯冲击】：1 张手牌攻击牌 + 1 张火系【充能】）
var _skill_cover_need: int = 0
## 本次发动技能的参数选项（服务端在技能上给的 arg_choices：每项一个按钮，点它就用当前已选的牌/目标提交）
var _skill_arg_choices: Array = []
## 二级技能栏：点「带选项的技能」后，技能区只留被点的技能（最左）+ 它的选项（紧挨它右边、同样用技能按钮显示），
## 其余技能暂时隐藏；选项先选中（亮黄），点「确定」才提交、点「取消」才退出（退出后恢复原来的技能栏）。
var _二级栏: bool = false
## 二级栏里的选项按钮 [{按钮: 技能按钮, 参数: Array, 需牌: int, 需目标: int, 目标白名单: Array}]
var _二级选项: Array = []
## 当前选中的选项下标（-1＝还没选）
var _二级选中: int = -1
## 二级栏最左那颗「被点的技能」按钮（没有就是 null）。目标变化后要重填选项时沿用它，
## 免得重造一颗、把玩家刚点的那颗藏起来（见 _刷新基础效果选项）
var _二级栏父按钮: 技能按钮 = null
## 技能区当前渲染出来的按钮（行动阶段技能 / 选项 / 额外行动 / 特殊行动共用）
var _技能按钮: Array[Node] = []
## 本次行动询问下发的全部命令（取消技能/特殊行动时用它把技能按钮摆回来）
var _行动命令: Array = []
## 【地下法则】的持有者：冒险家（购买时只加宝石、一次可加 2 点，对照 role_maoxian.v_buy）
const 冒险家角色号: int = 12
## 【冒险者天堂】的技能号：冒险家提炼前先问把星石给谁（对照 role_maoxian）
const 冒险者天堂技能号: int = 1202
## 这几个技能要从盖牌区选【充能】作代价：进入选牌界面时先把可选的最大张数全选上，
## 玩家要改再自己点掉（雷光散射＝全选雷系、魔贯冲击＝1 张火系、多重射击＝1 张风系）
const 自动选盖牌技能: Array[int] = [2601, 2602, 2603]


func _ready() -> void:
	_面板列表 = [MainPlayer, PlayerStatusMobileR, PlayerStatusMobileUR,
		PlayerStatusMobileU, PlayerStatusMobileUL, PlayerStatusMobileL]
	# 悬浮说明框挂在界面根节点下：坐标 / 缩放 / 可用范围都按本界面算，盖在所有面板之上
	_说明提示 = 说明框预制.instantiate() as 说明提示框
	add_child(_说明提示)
	Logic.game_info_updated.connect(_on_game_info)
	Logic.turn_changed.connect(_on_turn)
	Logic.card_shown.connect(_on_card)
	Logic.hit_received.connect(_on_hit)
	Logic.hurt_received.connect(_on_hurt)
	Logic.hurt_float_received.connect(_on_hurt_float)
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
	BtnSetting.pressed.connect(UI.切换设置)
	# 初始收起日志/聊天（同参考脚本 Start 里的处理）
	LogRoot.visible = false
	ChatRoot.visible = false
	# 顶部提示抬高一段「选中手牌上浮」的高度，免得被抽出来等着确定的牌盖住
	Hint.offset_top -= 选中上浮像素
	Hint.offset_bottom -= 选中上浮像素
	# ---- 交互层（第三步）：接收询问 + 确定/取消/盖牌/特殊行动/放弃行动 ----
	Logic.command_received.connect(_on_command)
	# 让「操作无效」（ErrorInput）能回调到本界面（订阅信号，不用反向持有界面引用）
	Logic.invalid_input_received.connect(on_invalid_input)
	BtnOK.pressed.connect(_on_ok)
	BtnCancel.pressed.connect(_on_cancel)
	BtnCovered.pressed.connect(_on_cover_view)
	BtnSpecila.pressed.connect(_on_giveup)
	BtnResign.pressed.connect(_on_resign)
	for 面板: 战斗玩家面板 in _面板列表:
		面板.pressed.connect(_on_player_pressed.bind(面板))
		面板.基础效果牌点击.connect(_on_基础牌点击)
		# 鼠标指向头像：用和点头像同一份说明框弹在面板正上方
		面板.悬停.connect(_显示角色说明)
		面板.离开悬停.connect(_隐藏角色说明)
		# 鼠标指向状态图标（基础效果牌 / 指示物）：还是同一份说明框，只弹一行短说明
		面板.状态图标悬停.connect(_显示状态图标说明)
		面板.状态图标离开悬停.connect(_隐藏状态图标说明)
	# 队伍条上的士气数字：悬停出提示
	_接悬停提示(BlueMorale, 士气提示)
	_接悬停提示(RedMorale, 士气提示)
	ChooseArea.visible = false
	_隐藏技能区()
	# 手牌是按 HandArea 的实际宽度手排成一行的，尺寸一变（窗口缩放）就重排
	HandArea.resized.connect(刷新手牌)
	# 测试指令提示（测试用，挂在屏幕左上角；清单见 测试指令表）
	var 说明行: Array[String] = []
	for 项: Array in 测试指令表:
		说明行.append("%s %s" % [OS.get_keycode_string(int(项[0])), str(项[1])])
	测试提示.text = "\n".join(说明行)
	_接测试提示()
	# 场景被重新挂上时，可能有已经到达的快照
	if not Logic.last_info.is_empty():
		_on_game_info(Logic.last_info)
	else:
		_刷新交互()


## 测试提示（测试用）：常态半透明、鼠标指上去变不透明、按住左键可以拖到别处，免得挡住画面
func _接测试提示() -> void:
	_测试提示常态透明 = 测试提示.modulate.a
	# 先按「没开调试模式」藏起来：第一条快照到了再按房间设定决定显不显示
	测试提示.visible = false
	测试提示.mouse_entered.connect(func() -> void: 测试提示.modulate.a = 1.0)
	测试提示.mouse_exited.connect(func() -> void: 测试提示.modulate.a = _测试提示常态透明)
	测试提示.gui_input.connect(_on_测试提示_gui_input)


## 应用房间的调试模式：关着时藏起测试提示，同时测试指令也不再响应
func _应用调试模式(开: bool) -> void:
	if _调试模式 == 开:
		return
	_调试模式 = 开
	测试提示.visible = 开


## 按住测试提示拖动：按下时记下鼠标在面板内的位置，移动时按同样的偏移摆回去（松手结束拖动）
func _on_测试提示_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var 鼠标: InputEventMouseButton = event as InputEventMouseButton
		if 鼠标.button_index == MOUSE_BUTTON_LEFT:
			_测试提示拖动偏移 = 测试提示.get_local_mouse_position() if 鼠标.pressed else Vector2.ZERO
	elif event is InputEventMouseMotion and _测试提示拖动偏移 != Vector2.ZERO:
		测试提示.position = 测试提示.get_parent().get_local_mouse_position() - _测试提示拖动偏移


## 测试指令清单：[键位（Key 值）, 说明]。右下角的说明文字与快捷按钮都由它生成，避免两处重复
const 测试指令表: Array = [
	[KEY_0, "跳过当前行动玩家的回合"],
	[KEY_1, "给自己发 4 张圣光"],
	[KEY_2, "发技能牌"],
	[KEY_3, "发 3 张同系斩 + 3 张异系法术；再按清空手牌"],
	[KEY_4, "当前倒计时压到 1 秒"],
	[KEY_5, "双方士气拉满到 99"],
	[KEY_6, "自己标识物拉满；再按清空"],
	[KEY_7, "随机填充双方战绩区星石；再按清空"],
	[KEY_8, "自己治疗拉满；再按清零"],
	[KEY_9, "自己宝石补满；再按清空"],
	[KEY_QUOTELEFT, "退出战斗界面并断开本场战斗"],
]


## 测试快捷键（只在战斗界面、且房间开了调试模式时生效；键位与 GConst.DebugKey 的取值一致）
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var 键: InputEventKey = event as InputEventKey
	if not 键.pressed or 键.echo:
		return
	_测试指令(键.keycode)


## 执行一条测试指令（只在房间开了调试模式时生效；服务端也拦了一道）
func _测试指令(键: int) -> void:
	if not _调试模式:
		return
	match 键:
		KEY_0:
			# 跳过当前行动玩家的这一回合；他这时正被询问（弃牌 / 应战 / 是否发动…）的话，
			# 由服务端替他取消掉，免得卡在询问上（不分是谁按的键，也不动我自己界面上的询问）
			Logic.debug_key(GConst.DebugKey.SkipTurn)
		KEY_1:
			Logic.debug_key(GConst.DebugKey.GiveHolyLight)
		KEY_2:
			Logic.debug_key(GConst.DebugKey.SkillCards)
		KEY_3:
			Logic.debug_key(GConst.DebugKey.ToggleCards)
		KEY_4:
			Logic.debug_key(GConst.DebugKey.ShortenWait)
		KEY_5:
			Logic.debug_key(GConst.DebugKey.MoraleFull)
		KEY_6:
			Logic.debug_key(GConst.DebugKey.ToggleTokens)
		KEY_7:
			Logic.debug_key(GConst.DebugKey.RandomEnergy)
		KEY_8:
			Logic.debug_key(GConst.DebugKey.ToggleHeal)
		KEY_9:
			Logic.debug_key(GConst.DebugKey.ToggleGem)
		KEY_QUOTELEFT:
			# `~`（数字 1 左边）：退出战斗界面并断开本场战斗（回大厅；服务端会把我从这间房移除）
			_on_back()


# ============================================================
# 刷新
# ============================================================
## 对局快照 → 刷新队伍数值、房间号、玩家面板
func _on_game_info(info: Dictionary) -> void:
	_应用调试模式(bool(info.get("debug", false)))
	var started: bool = bool(info.get("is_started", false))
	# 留着「上一条快照是否已开局」：开局那一条只做记录，否则士气 0 → 初始值会白响一声
	var 之前已开局: bool = _已开局
	if started and not _已开局:
		_已开局 = true
		# 房间等待阶段仍是大厅音乐，真开打才换战斗曲
		Audio.播放音乐(Audio.场景战斗)
		_日志追加("房间 %d 对局开始" % int(info.get("room_id", 0)), "系统")
	_处理数值变化(info, 之前已开局 and started)
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
	_等待文案 = str(info.get("wait_text", ""))
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
	_推进法术伤害队列(delta)
	if _等待方 < 0:
		return
	_等待剩余 = maxf(_等待剩余 - delta, 0.0)
	_刷新等待条()


# ============================================================
# 法术伤害结算的顺序表现
# ============================================================
## 法术伤害结算的表现间隔（秒）：群伤（一次打多名）时服务端同一拍把几条伤害一起发过来，
## 若同时播出来，几个头像一起泛红、数字一起冒，看不出谁先谁后 —— 排队逐个播：
## 空闲时第一条立即播，其后每条间隔这么多秒。攻击 / 魔弹伤害不受影响（照旧即时，带震荡波）
const 法术结算间隔: float = 0.25
var _法术待播: Array[Dictionary] = []
var _法术计时: float = 0.0


func _推进法术伤害队列(delta: float) -> void:
	if _法术待播.is_empty():
		_法术计时 = 0.0
		return
	_法术计时 -= delta
	if _法术计时 > 0.0:
		return
	_法术计时 = 法术结算间隔
	_播放法术伤害(_法术待播.pop_front())


## 播放一条法术伤害的表现：受击音 + 面板泛红抖动 + 日志 + 伤害飘字（顺序与攻击一致：先数字后表现）
func _播放法术伤害(项: Dictionary) -> void:
	var dst: int = int(项.get("dst", -1))
	var src: int = int(项.get("src", -1))
	var point: int = int(项.get("point", 0))
	Audio.播音效("sys-hurt")
	var 受击面板: 战斗玩家面板 = _玩家面板(dst)
	if 受击面板 != null:
		受击面板.Hurted(false)
	_日志追加("%s 对 %s 造成 %d 点法术伤害" % [_称号(src), _称号(dst), point], "伤害")
	_伤害飘字(dst, point, 飘字色_法术伤害)


## 超时进度条画在「正在被等的那名玩家」的名牌上方，其余面板收起（传负值）；
## 头像上的行动说明（如「等待应战响应」）同样只写给被等的那名「别人」——
## 自己在等时另有一条「正在等待你的操作…」的提示，写在自己头像上会像在等自己操作
func _刷新等待条() -> void:
	var 比例: float = -1.0
	if _等待方 >= 0 and _等待总时长 > 0.0:
		比例 = clampf(_等待剩余 / _等待总时长, 0.0, 1.0)
	var 文案: String = _等待文案 if (_等待方 >= 0 and _等待方 != Logic.my_player_id) else ""
	for 面板: 战斗玩家面板 in _面板列表:
		面板.WaitProgress = 比例 if 面板.ID == _等待方 else -1.0
		面板.WaitAction = 文案 if 面板.ID == _等待方 else ""


## 数值变化（对照参考项目 MoraleChange / GemChange / CrystalChange / PlayerHealChange）：
## 播对应音效；队伍士气变了还额外写一条战斗日志（服务端只给绝对值，升降由上一次快照算出来）
func _处理数值变化(info: Dictionary, 生效: bool) -> void:
	var 士气: Array[int] = [int(info.get("red_morale", 0)), int(info.get("blue_morale", 0))]
	var 宝石: Array[int] = [int(info.get("red_gem", 0)), int(info.get("blue_gem", 0))]
	var 水晶: Array[int] = [int(info.get("red_crystal", 0)), int(info.get("blue_crystal", 0))]
	var 治疗: int = 0
	var 个人宝石: int = 0
	for p: GPlayer in Data.player_list:
		治疗 += p.cross_num
		个人宝石 += p.gem
	if 生效:
		if 士气 != _上次士气:
			Audio.播音效("sys-morale")
			_写士气日志(士气)
		# 士气与星石各响各的（对照参考项目：MoraleChange / GemChange 是两条独立通知），
		# 不用 elif —— 否则同一次快照里士气与星石一起变时（如魔爆冲击：掉士气又 +1 宝石）只有士气那声
		if _宝石水晶有动静(宝石, 水晶, 个人宝石):
			Audio.播音效("sys-energy")
		if 治疗 != _上次治疗:
			Audio.播音效("sys-heal")
	_上次士气 = 士气
	_上次宝石 = 宝石
	_上次水晶 = 水晶
	_上次治疗 = 治疗
	_上次个人宝石 = 个人宝石


## 该不该响「宝石 / 水晶」那一声（对照参考项目 GemChange / CrystalChange）：
## 队伍宝石池 / 水晶池、玩家手上宝石，只要数值变了就响 —— 增加与减少都响，
## 「获得宝石 / 水晶」必须有这一声，不做「只在减少时响」的过滤
func _宝石水晶有动静(宝石: Array[int], 水晶: Array[int], 个人宝石: int) -> bool:
	return 宝石 != _上次宝石 or 水晶 != _上次水晶 or 个人宝石 != _上次个人宝石


## 队伍士气变化写进战斗日志：逐个队写「旧值 → 新值」
## 快照里红在前、蓝在后（见 _处理数值变化），所以下标 0 是红队、1 是蓝队
func _写士气日志(新士气: Array[int]) -> void:
	if 新士气[0] != _上次士气[0]:
		_日志追加("红队士气%d → %d" % [_上次士气[0], 新士气[0]], "士气")
	if 新士气[1] != _上次士气[1]:
		_日志追加("蓝队士气%d → %d" % [_上次士气[1], 新士气[1]], "士气")


## 士气 / 宝石 / 水晶 / 星杯（读 Logic.last_info 的绝对值）
func _刷新队伍(info: Dictionary) -> void:
	BlueMorale.text = str(int(info.get("blue_morale", 0)))
	RedMorale.text = str(int(info.get("red_morale", 0)))
	_重建能量(BlueEnergy, int(info.get("blue_gem", 0)), int(info.get("blue_crystal", 0)))
	_重建能量(RedEnergy, int(info.get("red_gem", 0)), int(info.get("red_crystal", 0)))
	_重建格子(BlueGrail, int(info.get("blue_grail", 0)), "grail", 星杯提示)
	_重建格子(RedGrail, int(info.get("red_grail", 0)), "grail", 星杯提示)


## 能量格：宝石在前、水晶在后（与参考脚本 gemChange / crystalChange 的落位一致）；
## 每格都能悬停出提示，说明这颗是宝石还是水晶
func _重建能量(容器: GridContainer, 宝石数: int, 水晶数: int) -> void:
	_清空格子(容器)
	for _i: int in range(maxi(宝石数, 0)):
		_加格子(容器, "gem", "星石-宝石")
	for _j: int in range(maxi(水晶数, 0)):
		_加格子(容器, "crystal", "星石-水晶")


## 单一贴图的格子（星杯）；提示 传给每格做悬停说明
func _重建格子(容器: GridContainer, 数量: int, 贴图名: String, 提示: String = "") -> void:
	_清空格子(容器)
	for _i: int in range(maxi(数量, 0)):
		_加格子(容器, 贴图名, 提示)


func _清空格子(容器: GridContainer) -> void:
	for c: Node in 容器.get_children():
		c.queue_free()


## 单个格子：用 battlemobile/Image.tscn，贴图交给 AssetIndex 按文件名取。
## 提示 非空时这个格子可被鼠标拾取、悬停弹提示；空串＝纯装饰、放行点击
func _加格子(容器: GridContainer, 贴图名: String, 提示: String = "") -> void:
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
		if 提示 != "":
			_接悬停提示(格子, 提示)
		else:
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
## 悬停基础效果牌时摊出的「状态名 + 完整卡面」预制体（见 悬停卡预览）
const 悬停卡预览预制: PackedScene = preload("res://scenes/prefabs/battlemobile/HoverCardView.tscn")


## 把这几张牌摊到屏幕中间给所有人看；连着来第二拨时先把上一拨收掉
func _展示卡牌(卡号表: Array) -> void:
	_收起展示卡牌()
	var 视图表: Array[Control] = []
	for cid: Variant in 卡号表:
		var 卡: GCard = Data.get_card(int(cid))
		if 卡 == null:
			continue
		var 视图: Control = 卡牌视图预制.instantiate()
		# Card.tscn 的根节点本身是 0 尺寸的（手牌区是代码给尺寸的），得显式给尺寸才画得出来
		视图.set_anchors_preset(Control.PRESET_TOP_LEFT)
		视图.custom_minimum_size = 手牌尺寸
		视图.size = 手牌尺寸
		视图.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ShowCardArea.add_child(视图)
		# 「可用」传 true 才是正常亮度（false 会把整张牌置灰）；展示只是给人看，顺手关掉「可选」发光框
		视图.call("设置卡牌", 卡, true)
		(视图.get("canSelectBorder") as TextureRect).visible = false
		视图表.append(视图)
	# 排成一行并水平居中：位置够就摊开，牌多了就像手牌一样挤在一起（同一套间距算法），绝不换行
	var 排布: Array = _单行间距与起点(视图表.size(), ShowCardArea.size.x, 手牌尺寸, 手牌最多重叠比例)
	var 间距: float = float(排布[0])
	var 起点: float = float(排布[1])
	var 行y: float = (ShowCardArea.size.y - 手牌尺寸.y) * 0.5
	for i: int in range(视图表.size()):
		视图表[i].position = Vector2(起点 + 间距 * float(i), 行y)
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
			var 后缀: String = str(法术音效后缀.get(表现牌.card_name, ""))
			if 后缀 != "":
				Audio.播音效("spell-" + 后缀)
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
## 斩击类（水 / 火 / 地 / 风 / 雷 / 暗灭）是把 3D 斩击素材经 SubViewport 转成 2D 的预制体，见 scripts/effects/slash2D.gd；
## 魔弹同样是把 3D 弹道素材经 SubViewport 转成 2D 的预制体，见 scripts/effects/magicBullet2D.gd；
## 圣光是原生 2D 粒子（GPUParticles2D），见 scripts/effects/particleEffect.gd。
const 特效预制表: Dictionary = {
	GConst.CardName.WaterSlash: preload("res://scenes/prefabs/effects/waterSlash.tscn"),
	GConst.CardName.FireSlash: preload("res://scenes/prefabs/effects/fireSlash.tscn"),
	GConst.CardName.EarthSlash: preload("res://scenes/prefabs/effects/earthSlash.tscn"),
	GConst.CardName.WindSlash: preload("res://scenes/prefabs/effects/windSlash.tscn"),
	GConst.CardName.ThunderSlash: preload("res://scenes/prefabs/effects/thunderSlash.tscn"),
	GConst.CardName.DarkSlash: preload("res://scenes/prefabs/effects/darkAnnihilation.tscn"),
	GConst.CardName.Missile: preload("res://scenes/prefabs/effects/magicBullet.tscn"),
	GConst.CardName.HolyLight: preload("res://scenes/prefabs/effects/holyLight.tscn"),
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
	Audio.播音效("dealCard")
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
	# 法术伤害：交给队列逐个播（群伤时才有视觉先后）；攻击 / 魔弹 / 其它照旧即时播
	if int(msg.get("type", GConst.HarmType.None)) == GConst.HarmType.Magic \
			and cause != GConst.CAUSE_ATTACK and cause != GConst.CAUSE_MISSILE:
		_法术待播.append({
			"dst": int(msg.get("dst_id", -1)),
			"src": int(msg.get("src_id", -1)),
			"point": int(msg.get("hurt", 0)),
		})
		return
	# 魔弹是法术伤害（type=Magic）却走上面那条「即时」路，而 _on_hurt_float 对法术飘字一律跳过
	# （数字留给队列那一路）——两边一叠加魔弹就一个数字都不冒。这里补上：先冒数字，再播受击表现
	if int(msg.get("type", GConst.HarmType.None)) == GConst.HarmType.Magic:
		_伤害飘字(int(msg.get("dst_id", -1)), int(msg.get("hurt", 0)), 飘字色_法术伤害)
	# 攻击命中 / 魔弹命中只响「命中音」sys-hit，不再叠受伤音：攻击命中的那声在 _on_hit 里播过，
	# 魔弹没有命中判定，在这里补；其余来源（法术 / 技能）没有命中判定，响「受伤音」sys-hurt
	if cause == GConst.CAUSE_MISSILE:
		Audio.播音效("sys-hit")
	elif cause != GConst.CAUSE_ATTACK:
		Audio.播音效("sys-hurt")
	var dst: int = int(msg.get("dst_id", -1))
	var src: int = int(msg.get("src_id", -1))
	# 受击表现（泛红 / 抖动）由被打的面板自己播；画面扭曲震荡波只在「斩命中 / 魔弹命中」时叠
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
	# 顶部 VICTORY 横幅按「胜方队伍」取图（参考工程 TipArea::win：红队胜 → GameWinRed，蓝队胜 → GameWinBlue）
	WinImg.texture = 红队胜利图 if 胜方 == GConst.RED else 蓝队胜利图
	# WinPanel 及其子节点在场景里都是 visible=false，展开时一并打开
	# （同参考脚本 _show_win_children 的处理）
	WinPanel.visible = true
	WinImg.visible = true
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
	# 上一条询问可能已经作废（典型的：特殊行动选星石的二级栏还摆着，服务端径自跳过）：
	# 先把本地那一步收掉再处理新询问，等同于点「取消」——旧询问不再提交
	_本地选项阶段 = 0
	_本地询问 = false
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
	_skill_cover_need = 0
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
		# 发动过「启动」技能后：本阶段禁止特殊行动（服务端在命令里标 no_special）
		_行动禁特殊 = bool(cmd.get("no_special", false))
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
	_skill_targets.clear()
	_skill_cards.clear()
	_skill_card_rule = ""
	_mode = 0
	_selecting_cover = false
	_不可行动 = false
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
			# 非额外行动阶段：技能栏没有可用技能、手牌也全部打不出去、且特殊行动也做不了 → 不可行动，
			# 提示玩家点「确定」把手牌全弃掉、摸 4 张（服务端 Unactional）
			_不可行动 = _行动允许 == GConst.ActionType.Any and _无可用技能() \
					and _手里没有能用的牌() and not _可特殊行动()
			if _不可行动:
				_指令提示("你不可行动，点「确定」将手牌弃掉抽到 4 张牌。")
			else:
				_指令提示("轮到你行动了")
	else:
		match respond_id:
			GConst.RespondType.ReplyAttack:
				_mode = 2
				_need_cards = 1
				# 应战要指定「反击目标」（敌方、且不是原攻击者）
				_need_players = 1
				# 本次攻击伤害（服务端随询问下发，args[5]）＋攻击者的角色被动加伤
				# （如狂战士【狂化】+1 —— 服务端在命中时才结算，这里提前算进去）：
				# 写在提示最前面，让被攻击者一眼看到不阻止的话要挨多少
				var 受伤前缀: String = ""
				if args.size() > 5:
					var 攻击者: GPlayer = Data.get_player_by_id(_原攻击者())
					var 被动加伤: int = int(GConst.攻击提示角色加成.get(攻击者.role_id, 0)) if 攻击者 != null else 0
					受伤前缀 = "受到 %d 伤害攻击：" % (int(args[5]) + 被动加伤)
				if _可应战():
					if _可圣光抵挡():
						_指令提示(受伤前缀 + "打出同系斩应战 或 【圣光】抵挡，或取消放弃")
					else:
						_指令提示(受伤前缀 + "打出同系斩应战，或取消放弃")
				else:
					if _可圣光抵挡():
						_指令提示(受伤前缀 + "无法应战，出【圣光】抵挡，或取消放弃")
					else:
						_指令提示(受伤前缀 + "无法应战，只能点「取消」放弃")
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
				# args: [目标, 应摸总数, 束缚摸牌数, 虚弱牌数]；束缚恒为 0（【五系束缚】已改在行动阶段入口单独询问），
				# 故「虚弱和束缚」那句走不到，这里实际只会说「虚弱」
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
				if 抵 > 0:
					# 二级技能栏列出「不抵挡 / 挡几点」：和其它技能选项同一套交互（选中再点「确定」）。
					# 文案刻意短 —— 这一排可能有十来颗（抵几点就有几颗），长了会从技能区溢出去
					var 选项: Array = [{"text": "不抵挡", "args": [0]}]
					for n: int in range(1, 抵 + 1):
						选项.append({"text": "挡 %d 点" % n, "args": [n]})
					_进入二级技能栏(0, null, _选项项(选项), 二级选项底色_治疗)
					# 默认选中「挡最多」的那一项（最后一项，抵挡值最大）—— 玩家直接点「确定」就是挡满
					_先弹选项 = false
					_选中二级选项(0, _二级选项.size() - 1)
				_指令提示("用治疗抵挡本次 %d 点%s伤害，「确定」使用" % [伤害点数, 类型名])
			GConst.RespondType.Bullet:
				_mode = 2
				_need_cards = 1
				# 当前魔弹伤害（服务端随询问下发，args[1]）：写在提示开头，说明放弃传递要挨多少
				var 魔弹伤害: int = int(args[1]) if args.size() > 1 else GConst.魔弹基础伤害
				_指令提示("受到 %d 伤害魔弹攻击，出【魔弹】继续传递，或出【圣光】抵挡，或点「取消」承受伤害" % 魔弹伤害)
			_:
				_mode = 2
				_need_cards = 0
	_刷新交互()


## 被要求弃牌时的指令提示：按原因（应答 args[1] = cause）说清为什么弃牌。
## CAUSE_OVERLOAD＝手牌超限；下发的是技能号（如【灵符-风行】逼别人弃牌）就点名那个技能；
## 认不出来的（CAUSE_USE 之类牌的效果）只说「请弃牌」—— 不能一律写成「手牌超限」，
## 那样没超限的场合文案就明显是错的
func _弃牌提示(cause: int, 张数: int) -> String:
	if cause == GConst.CAUSE_OVERLOAD:
		return "手牌超限：请选择 %d 张牌弃掉" % 张数
	if not GConst.技能行(cause).is_empty():
		# 「提示列本就是给这次弃牌询问写的」技能（如贤者【智慧法典】）在技能指示器里声明了
		# 「弃牌提示取表」：直接用技能表「提示」列第 1 条（写明了 +2 宝石、请弃 1 张牌这类完整语义）。
		# 其余技能（【魔爆冲击】/【灵符-风行】等）第 1 条是「发动【X】：…」整句，直接拿来会让弃牌提示
		# 变长、语义怪，故仍退回默认的「【X】：请选择 N 张牌弃掉」
		if bool(GConst.技能指示器.get(cause, {}).get("弃牌提示取表", false)):
			var 表提示: String = GConst.提示文本(cause, 0, "", 张数)
			if not 表提示.is_empty():
				return 表提示
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
	# 询问这条通道没有「手牌+盖牌混选」的需盖牌数（那是技能按钮才有的），清零免得串味
	_skill_cover_need = 0
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
	# 多重射击这类从盖牌区选【充能】作代价的询问：进来先按最大张数全选上，玩家要改再自己点
	_自动选盖牌(_skill_ask_id)
	_清空技能按钮()
	# 带选项的询问（如英灵人形【怒火压制/魔纹融合】的二选一、【百鬼夜行】的展示与否）：
	# 进「二级技能栏」—— 技能区只留这个技能（最左）+ 它的选项（紧挨右侧，同样用技能按钮显示），
	# 选项先选中（亮黄），按「确定」才提交、按「取消」放弃。
	var 指示配置: Dictionary = GConst.技能指示器.get(_skill_ask_id, {})
	_先弹选项 = bool(指示配置.get("先弹选项", false)) and not _skill_options.is_empty()
	# 「自动选目标」型（如【毒粉】：服务端在询问里点名挨这次伤害的角色）：进场即把目标选中并锁死，
	# 头像上直接画技能指示器的效果（点头像也改不了）
	_目标锁死 = _套用自动选目标(指示配置)
	_已选参数.clear()
	if _先弹选项:
		# 服务端原本给的目标数 / 需牌先记下，选完效果由 _应用选项目标数 还原 / 收紧
		_选项原始目标数 = _skill_ask_need_target
		_选项原始需牌 = _skill_ask_need_card
		_选项原始最多牌 = _skill_card_max
		# 默认选效果前不让点牌 / 点目标（数量按 0 处理）；配了「允许先选牌」的技能不清零
		if not bool(指示配置.get("允许先选牌", false)):
			_skill_ask_need_target = 0
			_need_players = 0
			_skill_ask_need_card = 0
			_skill_card_max = 0
			_need_cards = 0
	if not _skill_options.is_empty():
		var notes: Array = _pending.get("notes", [])
		# 服务端标了「这一项本身就是技能」时（如【蓄力一击】/【气绝崩击】），选项按钮绑上技能号，
		# 鼠标指向它就同普通技能按钮一样弹技能说明（见 技能按钮.设置选项 / _显示技能说明）
		var 选项技能号: Array = _pending.get("option_skill_ids", [])
		# 服务端标了这一项「选中后要弃几张牌」时（如【魔纹融合】弃 ≥2 张、【怒火压制】一张不用）
		# 记下来，选中它才放出手牌可选（见 _应用选项目标数）
		var 选项需牌: Array = _pending.get("option_need_cards", [])
		# 服务端标了这一项「可点哪些目标」时（如吟游诗人【希望赋格曲】的「放置」不含自己、
		# 「转移」含自己）：选中该项后按它收紧可点头像（见 _参数选项目标白名单）
		var 选项目标: Array = _pending.get("option_targets", [])
		var 项们: Array = []
		for i: int in range(_skill_options.size()):
			var 名: String = str(notes[i]) if i < notes.size() and str(notes[i]) != "" else str(_skill_options[i])
			var 项: Dictionary = {"文本": 名, "参数": [int(_skill_options[i])]}
			if i < 选项技能号.size():
				项["技能号"] = int(选项技能号[i])
			if i < 选项需牌.size():
				项["需牌"] = int(选项需牌[i])
			if i < 选项目标.size():
				var 白名单: Dictionary = 选项目标[i]
				项["目标白名单"] = 白名单.get("ids", [])
			项们.append(项)
		# 「无父技能」型（格斗【蓄力一击 / 气绝崩击】这条询问）：选项本身就是技能，
		# 这一排只摆选项，不摆「被问的技能」那颗本体（否则会多出一颗与选项同名的按钮）
		var 父技能号: int = 0 if bool(指示配置.get("无父技能", false)) else _skill_ask_id
		_进入二级技能栏(父技能号, null, 项们)
	elif _skill_ask_card_source == GConst.CardSource.HandAndBasicEffect:
		# 【天使之歌】：询问一到就把二级技能栏摆出来（此刻只有技能本体一颗），
		# 选完目标再由 _刷新基础效果选项 把该目标面前的基础效果填进去 —— 不用先按一次「确定」
		_进入二级技能栏(_skill_ask_id, null, [])
	# 技能询问同时写一行日志：它只挂在提示条上，错过就会一直等（看着像「点了确定没反应」）
	# 被问的人看到的应是「要我做什么」：服务端下发了技能表「提示」列里对应的那一条
	# （谁交给谁、几张）就直接用它，否则才退回「是否发动【X】？」
	# 带选项的询问（【军神威光】/【神之庇护】这类）例外：列出选项只代表「要你选一个效果」，
	# 选中之前都还没发动，日志里不能写「发动【X】」——那句要等服务端广播技能通知时才出现
	var 询问文案: String = str(_pending.get("ask_text", ""))
	if not _skill_options.is_empty():
		_日志追加(询问文案 if not 询问文案.is_empty() else "【%s】请在技能栏里选一个效果" % GConst.skill_name(_skill_ask_id), "行动")
	elif not 询问文案.is_empty():
		_日志追加(询问文案, "行动")
	else:
		_日志追加("【%s】等你决定" % GConst.skill_name(_skill_ask_id), "行动")
	var 指示提示: String = _发动提示(_skill_ask_id)
	if not 询问文案.is_empty():
		_指令提示(询问文案)
	elif not _skill_options.is_empty():
		_刷新二级栏提示()
	elif not 指示提示.is_empty():
		_指令提示(指示提示)
	elif _skill_ask_card_source == GConst.CardSource.HandAndBasicEffect:
		_指令提示("【%s】：点一名面前有基础效果的角色，技能栏里就会列出可%s的效果" % [
			GConst.skill_name(_skill_ask_id), _基础效果动作(_skill_ask_id),
		])
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


## 「先弹选项」型：在二级技能栏里选定效果后，把该项要求的目标数放进本次询问（【百鬼夜行】展示＝2 人、不展示＝1 人），
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
		# 选中的那一项若自带「需目标」（如魔弓【魔眼】的「指定一名角色弃 1 张牌」），目标数按它给；
		# 选的是不要目标的那项时它本来就没有目标数、技能级也是 0，这里保持 0（谁都不亮，也就点不动）
		var 项: Dictionary = _二级选中项()
		if not 项.is_empty():
			目标数 = maxi(目标数, int(项["需目标"]))
		_skill_need_card = _选项原始需牌
		_skill_card_max = _选项原始最多牌
		_need_cards = _skill_card_max
		_skill_need_target = 目标数
		_skill_target_max = maxi(目标数, _选项原始最多目标)
		_need_players = 目标数
		# 该项自带「需牌」时（如舞蝶【舞动】选「弃 1 张」那档要 1 张手牌），提示按它说，别少说一张
		var 提示需牌: int = _skill_need_card
		if not 项.is_empty():
			提示需牌 = maxi(提示需牌, int(项["需牌"]))
		_指令提示("发动【%s】：%s%s点「确定」" % [
			GConst.skill_name(技能号), _需选牌提示(提示需牌), _需选目标提示(_skill_need_target),
		])
		_刷新交互()
		return
	_skill_ask_need_card = _选项原始需牌
	_skill_card_max = _选项原始最多牌
	_need_cards = _skill_card_max
	_skill_ask_need_target = 目标数
	_need_players = _skill_ask_need_target
	# 选中的那一项若自带「需牌」（如英灵人形【魔纹融合】要弃 ≥2 张异系牌），牌数按它给
	var 选中项: Dictionary = _二级选中项()
	if not 选中项.is_empty():
		_skill_ask_need_card = maxi(_skill_ask_need_card, int(选中项["需牌"]))
	var 片段: Array[String] = []
	if _skill_ask_need_card > 0:
		片段.append("选%d张盖牌" % _skill_ask_need_card if _skill_ask_card_source == GConst.CardSource.Cover
			else "选%d张牌" % _skill_ask_need_card)
	if _skill_ask_need_target > 0:
		片段.append("选%d名目标" % _skill_ask_need_target)
	# 选项本身就是技能时（如【怒火压制】/【魔纹融合】二选一），提示条写选中的那一颗的名字：
	# 这次询问挂在魔纹融合名下，照它写会把「选了怒火压制」也说成魔纹融合
	var 说话技能号: int = _skill_ask_id
	if not 选中项.is_empty() and int(选中项.get("技能号", 0)) > 0:
		说话技能号 = int(选中项["技能号"])
	if 片段.is_empty():
		_指令提示("【%s】已选好，点「确定」发动" % GConst.skill_name(说话技能号))
	else:
		_指令提示("【%s】：%s，选好后点「确定」发动" % [GConst.skill_name(说话技能号), "、".join(片段)])
	_刷新交互()


## 「先弹选项」型技能（发动技能这条）换了效果后修剪已点目标：尽量保留，
## 只把不再合法（新效果的目标白名单不收）或超出新目标数上限的裁掉。
## 调用前需先 _应用选项目标数()，这里读的就是它刚算好的 _skill_target_max
func _保留合法目标() -> void:
	var 保留: Array[int] = []
	for pid: int in _sel_players:
		if 保留.size() >= _skill_target_max:
			break
		if _玩家可选(pid) and not 保留.has(pid):
			保留.append(pid)
	_sel_players = 保留


## 切换用法后重校验本次已选的牌与目标：合法的保留、不合法的丢掉。
## 「点头像分配」型的目标存在 _治疗分配 里（不在 _sel_players），必须单独按新用法的
## 目标白名单过滤 —— 否则上一个用法选好的队友会被带到「对敌」用法上误伤。
## 调用前需已按选中项更新过 _skill_need_card / _skill_target_max 等（见 _应用选项目标数）。
func _换选项后重校验() -> void:
	# 手牌：按新用法的可点条件（牌系 / 来源 / 白名单…）逐张复检，并受新的点选上限约束
	var 牌保留: Array[int] = []
	for cid: Variant in _sel_cards:
		if 牌保留.size() >= _skill_card_max:
			break
		if _卡牌能点(int(cid)) and not 牌保留.has(int(cid)):
			牌保留.append(int(cid))
	_sel_cards = 牌保留
	if not _分配配置().is_empty():
		# 「点头像分配」型：分配记录按新用法的目标白名单过滤，再整体刷新（顺带重建 _sel_players）
		var 分配保留: Array[int] = []
		for pid: int in _治疗分配:
			if _玩家可选(pid):
				分配保留.append(pid)
		_治疗分配 = 分配保留
		_刷新治疗分配()
		return
	_保留合法目标()
	刷新选中面板()
	_更新按键()


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
		# 多份额外行动（如剑圣【风怒追击】+【剑影】）：用二级技能栏列出这几颗，选中再按「确定」发动。
		# 这次没有「被点的技能」，所以最左不放技能本体，这一排就是那几个额外行动
		var 选项: Array = []
		for cause: Variant in causes:
			var c: int = int(cause)
			# 发不动的（如手里没风系攻击牌时的【风怒追击】）直接不列 —— 列出来点了也是白点
			if not 可发动.has(c):
				continue
			# skill_id：这几项本身就是技能，鼠标指向选项按钮时据此弹技能说明
			选项.append({"text": GConst.skill_name(c), "args": [c], "skill_id": c})
		_额外行动单选 = -1
		_进入二级技能栏(0, null, _选项项(选项))
		# 这面标记必须在进二级栏「之后」设：_进入二级技能栏 开头会 _清空二级选项()，那里会把它清回 false，
		# 先设就被抹掉，选中选项后 _选中二级选项 认不出这条通道，「确定」会一直灰着点不动
		_额外行动用二级栏 = true
		_刷新二级栏提示()
	_刷新交互()


## 悬浮说明框：技能按钮的「技能说明」与角色头像的「角色技能说明」共用一份，鼠标指到谁就显示谁。
## 技能区贴着屏幕最底，Godot 自带的 tooltip 跟着光标走、会顶出可视区，所以自己摆一个。整局一份就够。
## 底板样式、行距、加宽 / 缩小兜底、角色说明的排版都在 说明提示框 里 —— 战斗与选角同款效果。
var _说明提示: 说明提示框 = null
## 此刻鼠标指着的技能按钮（null＝没指着；用来区分「移到另一个按钮」与「真的离开了」）
var _悬停技能按钮: 技能按钮 = null
## 此刻鼠标指着的玩家面板（null＝没指着）
var _悬停角色面板: 战斗玩家面板 = null
## 此刻鼠标指着状态图标（用来区分「移到别的东西上」与「真的离开了」）
var _悬停状态图标: bool = false
## 「正在点头像选目标」（用指示器分配 / 选目标）时指向头像：技能说明要停留这么久才弹（秒）。
## 那种场合鼠标会扫过一排头像去点目标，指到就弹的说明框会不停闪、挡住选取；其余场合仍是指到就弹
const 选目标悬停说明延迟: float = 1.0
## 上面那条延迟的计时器，以及「等的是哪块面板」（详见 _显示角色说明 的三个帮手）
var _面板说明计时器: Timer = null
var _待说明面板: 战斗玩家面板 = null
## 技能说明的就一行多点，窄一点、字小一点，像个提示而不是一条横幅；
## 角色说明是整块文本 —— 宽度 / 字号 / 缩放、加宽与缩小兜底都在 说明提示框 里（战斗与选角共用同一套）
const 技能说明宽度: float = 400.0
const 技能说明字号: int = 16
## 状态图标的小提示只有一行（指示物＝「名字 当前/上限」、基础效果牌＝「卡名（派系·元素）」），
## 宽度交给说明框按内容自适应（见 显示 的宽度参数）
const 状态图标说明字号: int = 16
## 悬停基础效果牌时摊出来的完整卡面尺寸：照手牌卡面大小，牌名 / 命格 / 元素都看得清
const 悬停卡牌尺寸: Vector2 = 手牌尺寸


## 鼠标指向技能按钮：把该技能的说明摆在按钮正上方
func _显示技能说明(按钮: 技能按钮) -> void:
	if 按钮 == null:
		return
	var 文本: String = 角色技能提示.单个技能(按钮.技能号)
	if 文本.is_empty():
		return
	_悬停角色面板 = null
	_悬停状态图标 = false
	_悬停技能按钮 = 按钮
	_说明提示.显示(文本, 按钮.get_global_rect(), 技能说明宽度, 技能说明字号)


## 鼠标离开技能按钮（或点了按钮）：延后一帧再收 —— 从一个按钮移到另一个时引擎会先报「离开」，
## 新的「指向」马上又把框摆好了，这时不能把框收掉
func _隐藏技能说明() -> void:
	_悬停技能按钮 = null
	_收说明框.call_deferred()


## 此刻点头像是不是「有选取含义」（选目标 / 点头像分配，由技能指示器驱动）：任一头像亮着就算。
## 这种时候鼠标指向头像不弹角色技能说明 —— 选目标时玩家看的是头像上的伤害/治疗提示，
## 再飘一块说明上来会把它们挡住，还会跟「点他去选他」这件事打架。
func _正在选目标() -> bool:
	for 面板: 战斗玩家面板 in _面板列表:
		if 面板 != null and _玩家可选(面板.ID):
			return true
	return false


## 鼠标指向玩家面板：把该角色的技能说明摆到面板正上方。
## 正在点头像选目标时改成「停留 选目标悬停说明延迟 秒才弹」（见 _启动面板说明计时器）
func _显示角色说明(面板: 战斗玩家面板) -> void:
	if 面板 == null:
		return
	if _正在选目标():
		_待说明面板 = 面板
		_启动面板说明计时器()
		return
	_取消面板说明计时()
	_弹出角色说明(面板)


## 把某名角色的技能说明摆到他面板正上方（延迟到时后也走这里）
func _弹出角色说明(面板: 战斗玩家面板) -> void:
	var 玩家: GPlayer = Data.get_player_by_id(面板.ID)
	if 玩家 == null:
		return
	_悬停技能按钮 = null
	_悬停状态图标 = false
	_悬停角色面板 = 面板
	_说明提示.显示角色说明(玩家.role_id, 面板.get_global_rect())


## 鼠标离开玩家面板：同上，延后一帧再收（先看新的「指向」有没有接手）
func _隐藏角色说明() -> void:
	_悬停角色面板 = null
	_取消面板说明计时()
	_收说明框.call_deferred()


## 选目标时「等弹说明」的倒计时，被鼠标左键一点就重新开始：
## 玩家在一排头像上点着选目标时，说明框不该趁两次点击之间的空档冒出来挡住头像。
## 用 _input 而不是 _unhandled_input —— 点头像的事件会被按钮/面板吃掉，收不到。
func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var 鼠标: InputEventMouseButton = event as InputEventMouseButton
	if 鼠标.button_index != MOUSE_BUTTON_LEFT or not 鼠标.pressed:
		return
	# 只有「正在等弹说明」的这一轮才重新计时；其余点击跟说明框无关
	if _待说明面板 != null:
		_启动面板说明计时器()


## 选目标时的延迟弹出：起一次性计时；重复进入同一块面板就重新计时（＝必须连续停留够久才弹）
func _启动面板说明计时器() -> void:
	if _面板说明计时器 == null:
		_面板说明计时器 = Timer.new()
		_面板说明计时器.name = "面板说明计时器"
		_面板说明计时器.one_shot = true
		_面板说明计时器.timeout.connect(_面板说明到时)
		add_child(_面板说明计时器)
	_面板说明计时器.start(选目标悬停说明延迟)


func _取消面板说明计时() -> void:
	if _面板说明计时器 != null:
		_面板说明计时器.stop()
	_待说明面板 = null


func _面板说明到时() -> void:
	var 面板: 战斗玩家面板 = _待说明面板
	_待说明面板 = null
	# 鼠标可能已经移开（离开悬停会取消计时）、或者这一轮选目标已经结束了
	if 面板 == null or not _正在选目标() or not is_instance_valid(面板):
		return
	_弹出角色说明(面板)


## 鼠标指向状态图标（基础效果牌 / 指示物）：在图标正上方弹提示 ——
## 基础效果牌摊出这张牌的完整卡面 + 状态名，指示物只有一行「名字 当前/上限」
func _显示状态图标说明(图标: Control, 文本: String, 牌id: int) -> void:
	_悬停技能按钮 = null
	_悬停角色面板 = null
	_悬停状态图标 = true
	var 卡面: Control = _造悬停卡牌(牌id, 文本)
	if 卡面 != null:
		_说明提示.显示内容(卡面, 图标.get_global_rect())
		return
	_说明提示.显示(文本, 图标.get_global_rect(), 0.0, 状态图标说明字号)


## 给某个控件接上「悬停出一行提示」（整局共用一份提示框，见 _说明提示）。
## 顺手把鼠标拾取打开 —— Label / 纯装饰图默认是 IGNORE，不拾取就收不到 hover
func _接悬停提示(控件: Control, 文本: String) -> void:
	控件.mouse_filter = Control.MOUSE_FILTER_STOP
	控件.mouse_entered.connect(func() -> void: _显示状态图标说明(控件, 文本, -1))
	控件.mouse_exited.connect(_隐藏状态图标说明)


## 造一张「悬停预览」用的卡牌视图 + 状态名（没牌号 / 取不到卡或卡面就返回 null，调用方退回纯文字）。
## 状态名单独写一行：光看卡面认不出「这是哪一版」（如【圣盾】的幻 / 圣 / 咏三版卡图是同一张）。
## 只给人看：不可点、不置灰，卡牌自己那圈「可选」发光也关掉
func _造悬停卡牌(牌id: int, 状态名: String) -> Control:
	if 牌id < 0:
		return null
	var 牌: GCard = Data.get_card(牌id)
	if 牌 == null or Art.card_face(牌) == null:
		return null
	var 视图: 悬停卡预览 = 悬停卡预览预制.instantiate()
	# 预制体本身就是「状态名一行 + 卡面」的竖排，尺寸 / 字号 / 忽略鼠标都在 悬停卡预览.设置 里
	视图.设置(牌, 状态名, 悬停卡牌尺寸, 状态图标说明字号)
	return 视图


## 鼠标离开状态图标：同上，延后一帧再收（先看新的「指向」有没有接手）
func _隐藏状态图标说明() -> void:
	_悬停状态图标 = false
	_收说明框.call_deferred()


func _收说明框() -> void:
	if _悬停技能按钮 != null or _悬停角色面板 != null or _悬停状态图标:
		return
	_说明提示.收起()


## 收掉所有说明：新一轮询问 / 收起技能区的时候用 —— 状态一变，挂着的说明就不该再留着
func _收起所有说明() -> void:
	_悬停技能按钮 = null
	_悬停角色面板 = null
	_悬停状态图标 = false
	_取消面板说明计时()
	_说明提示.收起()


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
		var 盖牌需数: int = int(c.get("cover_need", 0))
		var go: 技能按钮 = _新技能按钮(技能号)
		go.connect("点击", _选择技能.bind(技能类型, 需牌, 需目标, 合法目标, 合法牌, 最多牌,
			最多目标, 目标上限减牌数, 选牌来源, 选牌规则, 首张技能, 次张系别, 参数选项, go, 盖牌需数))
		# 点下去就把挂着的技能说明收掉，别挡着选牌选目标（悬停 / 离开悬停由 _新技能按钮 统一接）
		go.connect("点击", func(_技能号: int) -> void: _隐藏技能说明())
	# 技能全排一行：技能多的角色（如元素师 7 个技能）不能被场景里配的 6 列折到第二行去
	_排技能区一行()


## 造一颗技能按钮挂进技能区（只 Instantiate + 设置技能 + 接悬停说明，点击回调由调用方做）
func _新技能按钮(技能号: int) -> 技能按钮:
	var go: Node = 技能预制.instantiate()
	if go is Control:
		(go as Control).custom_minimum_size = 技能尺寸
	ChildrenSkillArea.add_child(go)
	go.call("设置技能", 技能号)
	# 鼠标指向技能按钮：把它的技能说明摆到按钮正上方（点下去收起另接）。
	# 接在这里而不是各调用点：二级技能栏里现造的「父技能」与「本身就是技能」的选项按钮都要有这一份；
	# 技能号为 0 的纯参数选项查不到说明，悬停自然不弹
	go.connect("悬停", _显示技能说明)
	go.connect("离开悬停", _隐藏技能说明)
	_技能按钮.append(go)
	_显示技能区()
	return go as 技能按钮


## 技能区永远只排一行：把 GridContainer 的列数设成「当下可见的按钮数」。
## 场景里配的是 6 列，技能多的角色（如元素师 7 个技能）第 7 颗会折到第二行，
## 从只有一行高的技能区里溢出去。GridContainer 会跳过隐藏的子节点，所以按可见数算正好 ——
## 二级技能栏里其余技能是藏着的，也一并适用（见 _进入二级技能栏）
func _排技能区一行() -> void:
	var 可见数: int = 0
	for b: Node in _技能按钮:
		if is_instance_valid(b) and b is Control and (b as Control).visible:
			可见数 += 1
	ChildrenSkillArea.columns = maxi(1, 可见数)


# ---------------- 二级技能栏 ----------------
## 把服务端下发的 arg_choices 归一成二级栏的选项项
## （键名统一成 文本 / 参数 / 需牌 / 需目标 / 目标白名单 / 技能号 / 选牌来源 / 需盖牌）
func _选项项(参数选项: Array) -> Array:
	var out: Array = []
	for 项: Variant in 参数选项:
		var d: Dictionary = 项
		out.append({
			"文本": str(d.get("text", "")),
			"参数": d.get("args", []),
			# false＝这一项条件不满足：照样摆出来，但半透明、点不动（如特殊行动的购买 / 合成 / 提炼）
			"可用": bool(d.get("enabled", true)),
			"需牌": int(d.get("need_card", 0)),
			"需目标": int(d.get("need_target", 0)),
			"目标白名单": d.get("targets", []),
			# >0＝这一项本身就是个技能（如【风怒追击】/【剑影】），选项按钮据此绑技能号、悬停弹说明
			"技能号": int(d.get("skill_id", 0)),
			# 该项自带的选牌来源 / 需盖牌数（-1 / 0 ＝ 沿用技能本体的；如【倒逆之蝶】第 ② 项的 2 张【茧】）
			"选牌来源": int(d.get("card_source", -1)),
			"需盖牌": int(d.get("cover_need", 0)),
		})
	return out


## 二级技能栏里纯参数选项按钮统一的底色（黑灰）：这类选项只是「参数」，不跟技能类型色走 ——
## 一排五颜六色反而看不出哪个是被点的技能，黑灰也让它们和左边那颗真技能按钮一眼分得开。
## （选项「本身就是技能」时不走这个底色，改用技能自己的类型色，见 技能按钮.设置选项）
const 二级选项底色: Color = Color(0.24, 0.24, 0.26)
## 「治疗抵挡」那几个选项用蓝色，和黑灰的技能选项区分开
const 二级选项底色_治疗: Color = Color("3b82f6")
## 特殊行动（购买 / 合成 / 提炼，含冒险者天堂那两步）的选项用绿色，和技能选项一眼分得开
const 二级选项底色_特殊行动: Color = Color("16a34a")
## 本次二级栏最左那颗「被点的技能」（0＝这一排只有选项，如多份额外行动 / 治疗抵挡）：提示条据此写名字
var _二级栏父技能号: int = 0


## 进入二级技能栏：把「父技能」摆到最左，其余技能先藏起来，选项用技能按钮紧挨着排在它右边。
## 选项项：{"文本": 按钮上的字, "参数": 提交用的 args, "需牌": N, "需目标": N, "目标白名单": [...],
##          "技能号": 该项本身就是技能时给它的技能号}
## 父按钮为 null 且父技能号 > 0 时（技能询问那条通道没有现成的按钮）按父技能号现造一颗；
## 两者都空（如「多份额外行动」那种没有点击本体的场合）＝这一排只有选项。
## 选项底色默认为统一的黑灰；「治疗抵挡」那条通道传蓝色，让治疗所属的选项一眼可辨。
## 选项「本身就是技能」时（带技能号）不用这个底色，改用技能自己的类型色，见 技能按钮.设置选项
func _进入二级技能栏(父技能号: int, 父按钮: 技能按钮, 选项: Array,
		选项底色: Color = 二级选项底色) -> void:
	_清空二级选项()
	# 父按钮要现造时（技能询问那条通道没有现成的按钮）：那颗只是「这次在问哪个技能」的牌子，
	# 不接点击 —— 响应弹出的询问不该有「再点一下就回退」，只能走右下角的「确定 / 取消」
	var 父: 技能按钮 = 父按钮
	if 父 == null and 父技能号 > 0:
		父 = _新技能按钮(父技能号)
	for b: Node in _技能按钮:
		if b is Control:
			(b as Control).visible = b == 父
	if 父 != null:
		ChildrenSkillArea.move_child(父, 0)
		父.设置选中(true)
	for i: int in range(选项.size()):
		var d: Dictionary = 选项[i]
		var 按钮: 技能按钮 = _新技能按钮(0)
		# 该项本身就是技能时绑上技能号：鼠标指向它就和普通技能按钮一样弹技能说明
		按钮.设置选项(str(d.get("文本", "")), 选项底色, int(d.get("技能号", 0)))
		# 条件不满足的项照样摆着，但半透明、点不动（见 技能按钮.设置选项可用）
		var 项可用: bool = bool(d.get("可用", true))
		按钮.设置选项可用(项可用)
		按钮.connect("点击", _选中二级选项.bind(i))
		_二级选项.append({
			"按钮": 按钮,
			"参数": d.get("参数", []),
			"可用": 项可用,
			"技能号": int(d.get("技能号", 0)),
			"需牌": int(d.get("需牌", 0)),
			"需目标": int(d.get("需目标", 0)),
			"目标白名单": d.get("目标白名单", []),
			"选牌来源": int(d.get("选牌来源", -1)),
			"需盖牌": int(d.get("需盖牌", 0)),
		})
	# 技能本体 + 选项全排一行（按当下可见的按钮数定列数，选项多了也不折行）
	_排技能区一行()
	_二级栏父技能号 = 父技能号 if 父 != null else 0
	_二级栏父按钮 = 父
	_二级栏 = true
	_二级选中 = -1
	_已选参数.clear()
	_显示技能区()
	_更新按键()


## 清掉二级栏的状态与选项按钮（技能本体按钮与其余技能由 _清空技能按钮 统一收）
func _清空二级选项() -> void:
	for 项: Dictionary in _二级选项:
		var b: Node = 项["按钮"]
		if is_instance_valid(b):
			_技能按钮.erase(b)
			b.queue_free()
	_二级选项.clear()
	_二级栏 = false
	_二级选中 = -1
	_二级栏父技能号 = 0
	_二级栏父按钮 = null
	_额外行动用二级栏 = false


## 点了二级栏里的某个选项：记下它的 args 并点亮它，其余选项熄灭（选好再按「确定」才提交）
func _选中二级选项(_技能号: int, 序号: int) -> void:
	if 序号 < 0 or 序号 >= _二级选项.size():
		return
	_二级选中 = 序号
	_已选参数 = (_二级选项[序号]["参数"] as Array).duplicate()
	for i: int in range(_二级选项.size()):
		var b: 技能按钮 = _二级选项[i]["按钮"]
		if is_instance_valid(b):
			b.设置选中(i == 序号)
	# 「多份额外行动」这条：选项就是几个可发的额外行动，选中＝把「确定」要发的那一个记下来
	# （这条通道没有技能本体，提交走的是 _选择额外行动，直接发应答，不经过 _已选参数）
	if _额外行动用二级栏 and not _已选参数.is_empty():
		_额外行动单选 = int(_已选参数[0])
		_额外行动可选 = true
	# 「先弹选项」型（如【百鬼夜行】）：选完效果才按它还原 / 收紧需牌与目标数；
	# 技能询问这条通道顺手把这步选择报给服务端（partial）：后面选目标时若超时，服务端据此自动结算
	# （如【剑气斩】自动释放），而还没选效果就超时＝取消
	if _先弹选项:
		if _mode == 4:
			# 发动技能这条（如【死亡之触】换「消耗多少治疗」）：已经点好的目标保留下来（用户要求），
			# 换效果后只把不再合法（新效果的目标白名单不收）或超出新目标数上限的裁掉；牌同理
			_应用选项目标数()
			_换选项后重校验()
		else:
			# 技能询问这条：改了效果＝上一次的点选作废 —— 原先选的目标未必还是新效果的合法目标
			# （如【神圣领域】先点了队友、又改成敌人用法），清掉重选
			_重置治疗分配()
			_刷新治疗分配()
			_应用选项目标数()
			_换选项后重校验()
			Logic.send_respond(_skill_ask_id, [], [], _已选参数, true)
	elif _mode == 4 and not _二级选项.is_empty():
		# 发动技能时按「选中的效果」收紧本次要选的牌 / 目标：
		# 效果自带「需牌」而技能本体没要牌时要把牌数补上（如蝶舞者【舞动】的「弃 1 张」，
		# 否则手牌整片置灰、根本点不动）；效果不需要目标时也不该再点亮头像
		# （如【倒逆之蝶】三选一里只有「对目标」那一项要选目标）。
		# 效果还能自带选牌来源 / 需盖牌数（如【倒逆之蝶】第 ② 项要在盖牌区点 2 张【茧】，
		# 来源变「手牌+盖牌」后盖牌区自己亮出来、手牌照样能点）。
		# 技能本体已有需牌 / 需目标 / 来源的（如【欺诈】弃 2~3 张）以本体为准，选项只会往上加、不会削减
		var 项: Dictionary = _二级选中项()
		var 项需牌: int = int(项.get("需牌", 0))
		var 项需目标: int = int(项.get("需目标", 0))
		var 项来源: int = int(项.get("选牌来源", -1))
		_skill_card_source = 项来源 if 项来源 >= 0 else _选项原始来源
		_skill_cover_need = maxi(_选项原始盖牌需数, int(项.get("需盖牌", 0)))
		_selecting_cover = _skill_card_source == GConst.CardSource.Cover \
			or _skill_card_source == GConst.CardSource.HandOrCover or _skill_cover_need > 0
		_skill_need_card = maxi(_选项原始需牌, 项需牌)
		_skill_card_max = maxi(_选项原始最多牌, _skill_need_card)
		_need_cards = _skill_card_max
		_skill_need_target = maxi(_选项原始目标数, 项需目标)
		_skill_target_max = maxi(_选项原始最多目标, _skill_need_target)
		_need_players = _skill_target_max
		# 换了效果后把已选的牌 / 目标按新效果复检：合法的保留、不合法的丢掉
		# （原先超过上限就整片清掉，把合法的那几张也一起丢了）
		_换选项后重校验()
	# 冒险家【冒险者天堂】：选额外提炼数时把「要移除的自身能量」预览在自己头像上；
	# 最后一步选构成时记下取法，并刷新提示条与头像上的分配
	if _本地选项阶段 == 1:
		_刷新提炼能量预览()
	elif _提炼阶段 == 4:
		_应用提炼组合()
	_刷新二级栏提示()
	_刷新交互()


## 二级栏里当前选中那一项（还没选就是空字典）
func _二级选中项() -> Dictionary:
	if _二级选中 < 0 or _二级选中 >= _二级选项.size():
		return {}
	return _二级选项[_二级选中]


## 二级栏的指令条：还没选效果就说「先选」，选好了就说清还差什么才能确定。
## 没有技能本体（多份额外行动 / 治疗抵挡）时不写「【】」那一截，「发动」也换成中性说法
func _刷新二级栏提示() -> void:
	# 本地二级栏选项步骤（冒险者天堂选额外 / 特殊行动选星石）：提示条保留进栏时那句说明
	# （通用那套会写成「…点「确定」发动」，用在提炼 / 购买上不对味）
	if _本地选项阶段 > 0 or _提炼阶段 == 4:
		return
	var 前缀: String = "【%s】：" % GConst.skill_name(_二级栏父技能号) if _二级栏父技能号 > 0 else ""
	var 动作: String = "发动" if _二级栏父技能号 > 0 else ""
	if _二级选中 < 0:
		_指令提示("%s请在技能栏里选一个选项" % 前缀)
		return
	var 需牌: int = _skill_need_card if _mode == 4 else _skill_ask_need_card
	var 需目标: int = _skill_need_target if _mode == 4 else _skill_ask_need_target
	var 片段: String = _需选牌提示(需牌)
	if 需目标 > 0:
		片段 += "选%d名目标，" % 需目标
	if 片段.is_empty():
		_指令提示("%s选项已选好，点「确定」%s" % [前缀, 动作])
		return
	_指令提示("%s%s选好后点「确定」%s" % [前缀, 片段, 动作])


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
## 点不动的时候（不是该选目标的时机 / 他不是合法目标）什么都不做。
## 想看某人的角色技能说明：鼠标指向他的头像即可（说明框由容器摆，见 _显示角色说明）
func _on_player_clicked(player_id: int) -> void:
	# 目标已锁死（【瘟疫】/【剧毒新星】自动选全体）：点头像什么都不做
	if _目标锁死:
		return
	if not _玩家可选(player_id):
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
	# 「基础效果牌」这类（【封印破碎】/【风之洁净】/【天使之歌】）：目标一变就把技能栏里的
	# 「基础效果」选项跟着换（取消选中目标＝清空）
	if _二级栏 and (_技能是基础效果牌型()):
		_刷新基础效果选项()


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
			GConst.CardSource.HandOrCover:
				# 手牌 + 盖牌混选（如【魔贯冲击】）：两边都收，具体由白名单与 cover_need 约束
				pass
			_:
				if _is_my_cover(card_id):
					return false
		if not _skill_cards.is_empty() and not _skill_cards.has(card_id):
			return false
		return _符合选牌规则(card_id)
	# 特殊行动（购买/合成/提炼）与本地选项步骤期间不点牌
	if _mode == 6:
		return false
	return true


## 按选牌规则过滤可点牌（服务端给的 card_rule）：
## "same"＝只能选与已选牌同系的；"diff"＝只能选与已选牌互异系的；
## "sameprop"＝只能选与已选牌同命格的（如【式神降临】）；
## "an_zhi"＝暗之障壁：所选牌须同属「法术 / 雷系」中的同一类（两类都属的牌不锁类别）；""＝不限。
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
	# 暗之障壁（2904）：所选牌须同属「法术 / 雷系」中的同一类
	if _skill_card_rule == "an_zhi":
		return _暗之障壁可同组(_sel_cards, 牌)
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


## 暗之障壁：所选牌必须同属「法术」或「雷系」中的同一类。
## 先看已选牌 + 新牌能否被「法术」或「雷系」中的某一类整体覆盖（两类都属的牌两边都算、不锁类别）：
## 只选了雷系法术牌时两类都还行；一旦选了纯雷系牌，就只剩雷系可选，纯法术牌随即置灰（反之亦然）。
## 已选牌全是「两类都属」的牌时没有多数派，两类都仍可选，直到补入一张纯雷系 / 纯法术牌才定下类别。
func _暗之障壁可同组(已选: Array, 牌: GCard) -> bool:
	var 可法术: bool = 牌.is_magic()
	var 可雷系: bool = 牌.element_enum() == GConst.CardElement.Thunder
	for c: Variant in 已选:
		var 已: GCard = Data.get_card(int(c))
		if 已 == null:
			continue
		if not 已.is_magic():
			可法术 = false
		if 已.element_enum() != GConst.CardElement.Thunder:
			可雷系 = false
	return 可法术 or 可雷系


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


## 本次行动里技能栏有没有可用的技能（行动询问里第 1 项起就是技能；第 0 项是通用行动）
func _无可用技能() -> bool:
	for i: int in range(1, _行动命令.size()):
		var c: Dictionary = _行动命令[i]
		var 技能类型: int = int(c.get("respond_id", 0))
		if not GConst.放行动作(技能类型, _行动允许):
			continue
		if (c.get("args", []) as Array).is_empty():
			continue
		return false
	return true


## 手里的牌是不是一张都打不出去（全部无法在行动阶段主动使用）
func _手里没有能用的牌() -> bool:
	for card: GCard in Data.hand_cards:
		if card != null and _可主动使用牌(card.id):
			return false
	return true


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


## 这张牌能不能用来应战本次攻击（规则对照服务端 BattlePlayer.base_v_reattack / role_monv.v_reattack）：
## 需为攻击牌且「实际系别」与本次攻击同系（暗系攻击牌可替任意系）；本次攻击本身是暗系则一律不可应战；【圣光】走抵挡
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
	return _实际系别(牌) == 攻击牌.element_enum() or 牌.element_enum() == GConst.CardElement.Darkness


## 我这边的这张牌「实际算」哪一系：苍炎魔女【烈焰形态】下，除水系、暗系外的攻击牌视为火系
## （服务端 getCardElement / role_monv._is_fire_like）。凡是「按系别放行」的判定都得用它，
## 不然客户端把牌点亮、发出去却被服务端拒，玩家只看到一句「操作无效」
func _实际系别(牌: GCard) -> int:
	var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
	if 我 != null and 我.role_id == 苍炎魔女角色 and 我.tap and 牌.is_attack():
		var 系: int = 牌.element_enum()
		if 系 != GConst.CardElement.Water and 系 != GConst.CardElement.Darkness:
			return GConst.CardElement.Fire
	return 牌.element_enum()


## 本次攻击能否用【圣光】抵挡：
##   args[4] = can_light（有技能会让本次攻击无法抵挡，如魔剑士【暗影抗拒】）；
##   魔枪【黑暗束缚】（魔弹全禁角色）：始终不能用【圣光】格挡，这里也一并置灰（对照 role_moqiang 的 v_block）。
func _可圣光抵挡() -> bool:
	var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
	if 我 != null and 魔弹全禁角色.has(我.role_id):
		return false
	var args: Array = _pending.get("args", [])
	return int(args[4]) != 0 if args.size() > 4 else true


# ---------------- 确定 / 取消 / 放弃 ----------------
func _on_ok() -> void:
	# 本地二级栏选项步骤（不走服务端）：确定＝按当前这一步分派
	# （冒险者天堂最后一步的确定走下面 mode 3 的「本地询问」通道，提交点头像分配的结果）
	if _本地选项阶段 == 4:
		_确认天堂触发()
		return
	if _本地选项阶段 == 1:
		_天堂确认额外()
		return
	if _本地选项阶段 == 2:
		_确认特殊行动选石()
		return
	if _本地选项阶段 == 3:
		_确认特殊行动()
		return
	var respond_id: int = int(_pending.get("respond_id", 0))
	var args: Array = _pending.get("args", [])
	# 是否发动技能的询问
	if _mode == 3:
		# 本地询问（【冒险者天堂】点头像分配星石）：确定＝按分配结果提交提炼
		if _本地询问:
			_发送治疗分配()
			return
		# 单份额外行动（如【迅捷赐福】）：确定＝发动它
		if _额外行动单选 >= 0:
			_选择额外行动(_额外行动单选)
			return
		if not _分配配置().is_empty():
			_发送治疗分配()
			return
		if _是技能询问:
			# 二级技能栏提交的是技能栏里选定的那个效果值（【天使之歌】的选项在选完目标时就填进技能栏了）；
			# 普通询问固定回 [1]（发动）
			_发送应答(_skill_ask_id, _sel_players, _sel_cards, _已选参数 if _二级栏 else [1])
		return
	# 发动技能
	if _mode == 4:
		if not _分配配置().is_empty():
			_发送治疗分配()
			return
		# 二级技能栏提交的是技能栏里选定的那个效果值（没选项的技能 _已选参数 本来就是空的）；
		# 「基础效果牌」这类（【封印破碎】/【风之洁净】）选项在选完目标时就填进技能栏了，这里直接提交
		_发送行动(_pending_skill_type, _pending_skill_id, _sel_players, _sel_cards, _已选参数)
		return
	if _pending_type == GConst.Msg.Action:
		# 不可行动：确定＝把手牌全弃掉、摸 4 张
		if _不可行动:
			_发送行动(GConst.ActionType.Unactional, 0, [], [], [])
			return
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
	# 二级技能栏里选好了（应答这条通道只有「治疗抵挡几点」）：确定＝把选的那点数交上去
	if _二级栏 and _二级选中 >= 0:
		_发送应答(respond_id, [], [], _已选参数)
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
	# 本地二级栏选项步骤：取消＝退回上一层
	# （提炼前那一问 → 特殊行动三选一；额外提炼数 → 退回那一问；购买/合成/常规提炼选星石 → 三选一）
	if _本地选项阶段 == 4:
		_取消特殊行动选石()
		return
	if _本地选项阶段 == 1:
		_天堂问触发()
		return
	if _本地选项阶段 == 2:
		_取消特殊行动选石()
		return
	if _本地选项阶段 == 3:
		# 特殊行动三选一里取消＝收回这次特殊行动，退回行动阶段
		_回到行动阶段()
		return
	# 冒险者天堂最后一步（点头像分配）取消＝整次提炼作废，退回行动阶段
	if _提炼阶段 == 4:
		_回到行动阶段()
		return
	# 不能取消的那次技能询问（如【水之神力】交牌）直接忽略：键盘快捷键也得挡住，
	# 否则会回一个空应答，服务端只好替玩家随机交一张，等于「取消」反而生效了
	if _mode == 3 and _是技能询问 and not _skill_ask_can_cancel:
		return
	var respond_id: int = int(_pending.get("respond_id", 0))
	# 技能询问：取消=放弃。回空 args（不再回 [0]）——「取消」用「没有给值」表达，
	# 这样 0 就能当正常的选项值用（如【魔女之怒】的「摸 0 张牌」）
	if _mode == 3:
		# 本地询问（【冒险者天堂】点头像分配星石）：取消＝整个提炼作废，退回行动阶段
		if _本地询问:
			_本地询问 = false
			_回到行动阶段()
			return
		if _是技能询问:
			_发送应答(_skill_ask_id, [], [], [])
		else:
			# 额外行动：空 args 表示跳过
			Logic.send_respond(GConst.RespondType.AdditionalAction, [], [], [])
			_清空待选()
		return
	# 发动技能 / 特殊行动三选一 / 特殊行动星石选择时取消：退回行动阶段
	if _mode == 4 or _mode == 6:
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


## 放弃行动（场景里的 BtnResign；对照参考工程 RoleBase 的 ResignAction → ACTION_NONE）
func _on_resign() -> void:
	_发送行动(GConst.ActionType.None, 0, [], [], [])


## 特殊行动 / 放弃（场景 BtnSpecila，图标就是 action 键）
func _on_giveup() -> void:
	# 行动阶段：进「购买 / 合成 / 提炼」三选一（选项摆进二级技能栏，见 _进入特殊行动）
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
## 行动阶段点「特殊行动」进来：购买 / 合成 / 提炼 三选一 —— 选项摆进二级技能栏（本地步骤）。
## 可用性逐条对照原客户端 Role::normal / Role::buy / Role::synthetize / Role::extract：
##   购买 = 手牌放得下 3 张；合成 = 放得下且我方战绩区星石 ≥ 3；
##   提炼 = 战绩区有星石，且自己（或冒险家【冒险者天堂】时任一有空的队友）还收得下
func _进入特殊行动() -> void:
	var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
	if 我 == null or 我.color == GConst.TEAM_NONE:
		return
	var 可用: Array[bool] = _特殊行动可用()
	# 三种都摆出来：条件不满足的那几种半透明、点不动（而不是干脆不显示）
	var 选项: Array = [
		{"text": "购买", "args": [GConst.SpecialAction.Buy], "enabled": 可用[0]},
		{"text": "合成", "args": [GConst.SpecialAction.Synthesize], "enabled": 可用[1]},
		{"text": "提炼", "args": [GConst.SpecialAction.Extract], "enabled": 可用[2]},
	]
	_进入本地选项(3, 0, 选项, "选择特殊行动：购买 / 合成 / 提炼")


## 特殊行动（购买 / 合成 / 提炼）此刻各自可不可用，返回 [购买, 合成, 提炼]。
## 判定逐条对照原客户端 Role::normal / buy / synthetize / extract：
##   购买 = 手牌放得下 3 张；合成 = 放得下且我方战绩区星石 ≥ 3；
##   提炼 = 战绩区有星石，且自己收得下；冒险家【冒险者天堂】只要还有队友收得下也行（提炼出的星石能分给队友）
func _特殊行动可用() -> Array[bool]:
	var 结果: Array[bool] = [false, false, false]
	# 本阶段不放行特殊行动（额外行动只放行攻击/法术），或发动过「启动」技能后禁特殊 → 全都不可用
	if _行动禁特殊 or not GConst.放行动作(GConst.ActionType.Special, _行动允许):
		return 结果
	var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
	if 我 == null or 我.color == GConst.TEAM_NONE:
		return 结果
	var 战绩: GTeam = Data.team_of(我.color)
	var 星石: int = 战绩.gem + 战绩.crystal
	结果[0] = 我.hand_cards_num + 3 <= 我.hand_cards_max
	结果[1] = 结果[0] and 星石 >= 3
	结果[2] = 星石 > 0 and (我.get_energy() < 我.energy_max \
			or (我.role_id == 冒险家角色号 and not _提炼候选队友().is_empty()))
	return 结果


## 此刻能不能做特殊行动（三种里有任意一种可用）
func _可特殊行动() -> bool:
	var 可用: Array[bool] = _特殊行动可用()
	return 可用[0] or 可用[1] or 可用[2]


## 本地二级栏选项（特殊行动三选一）：确定＝进入选中的那一种（再选「用哪些星石」）
func _确认特殊行动() -> void:
	if _二级选中 < 0:
		return
	var 参数: Array = _已选参数
	_本地选项阶段 = 0
	_本地询问 = false
	_选特殊行动(int(参数[0]) if not 参数.is_empty() else GConst.SpecialAction.Extract)


## 基础效果选择窗 / 提示里用的动词：按技能号从技能指示器取，取不到就是「移除」
## （【封印破碎】是「拿走」进自己手牌，天使【风之洁净】/【天使之歌】是「移除」弃掉）
func _基础效果动作(技能号: int) -> String:
	return str(GConst.技能指示器.get(技能号, {}).get("基础效果动作", "移除"))


## 本次要选的是不是「选目标 → 场上基础效果牌」那类技能（【封印破碎】/【风之洁净】/【天使之歌】）：
## 发动技能与技能询问两条通道各看自己的选牌来源
func _技能是基础效果牌型() -> bool:
	if _mode == 4:
		return _skill_card_source == GConst.CardSource.HandAndBasicEffect
	if _mode == 3:
		return _skill_ask_card_source == GConst.CardSource.HandAndBasicEffect
	return false


## 【风之洁净】【天使之歌】【封印破碎】这类「选目标 → 场上基础效果牌」技能的选项：
## 按已选目标身上现有的基础效果列出（args 里带该效果牌 id），选哪张就处理哪张。对应原客户端
## 选中目标后在提示区列出该玩家全部基础效果、再点其一确定的做法。
## 【天使之歌】还要额外消耗 1 点能量（对照服务端 TianShi::TianShiZhiGe：args[0] = 用宝石?），
## 所以它的选项再带上「用宝石 / 用水晶」，且只列当前真有那种能量的项（能量不足的会被服务端拒）；
## 【封印破碎】不用手牌也不用在这里选能量（能量由服务端自动扣），只是把动词显示成「拿走」。
## 没选目标 / 该目标面前没有可处理的效果时返回空数组
func _基础效果选项() -> Array:
	if _sel_players.is_empty():
		return []
	var 目标: GPlayer = Data.get_player_by_id(int(_sel_players[0]))
	if 目标 == null:
		return []
	# 能量组合：[{args 前缀, 文案后缀}]；只有技能询问（天使之歌）才带能量。
	# 后缀写得短（·宝石 / ·水晶）：选项要挤在一行技能按钮里，长了会从技能区溢出
	var 能量组合: Array = [{"args": [], "后缀": ""}]
	if _mode == 3:
		能量组合 = []
		var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
		if 我 != null:
			if 我.gem > 0:
				能量组合.append({"args": [1], "后缀": "·宝石"})
			if 我.crystal > 0:
				能量组合.append({"args": [0], "后缀": "·水晶"})
		if 能量组合.is_empty():
			return []
	# 显示动词按技能号取（【封印破碎】是「拿走」进自己手牌，天使【风之洁净】/【天使之歌】是「移除」弃掉）
	var 技能号: int = _pending_skill_id if _mode == 4 else _skill_ask_id
	var 动作: String = _基础效果动作(技能号)
	var 选项: Array = []
	for 效果: GPlayer.BasicStatus in 目标.basic_status_list:
		if 效果.card == null:
			continue
		for 组合: Dictionary in 能量组合:
			选项.append({
				"text": "%s【%s】%s" % [动作, 效果.card.card_name, str(组合["后缀"])],
				"args": (组合["args"] as Array) + [效果.card.id],
			})
	return 选项


## 【封印破碎】/【风之洁净】/【天使之歌】：选完目标就地重填技能栏里的基础效果选项
## （技能本体那颗按钮沿用原来那颗，不重造）。没选目标 / 该目标没有可处理的效果时只剩技能本体一颗
func _刷新基础效果选项() -> void:
	var 技能号: int = _pending_skill_id if _mode == 4 else _skill_ask_id
	var 动作: String = _基础效果动作(技能号)
	var 父: 技能按钮 = _二级栏父按钮
	_进入二级技能栏(技能号, 父, _选项项(_基础效果选项()))
	if _二级选项.is_empty():
		_指令提示("【%s】：点一名面前有基础效果的角色，技能栏里就会列出可%s的基础效果" % [
			GConst.skill_name(技能号), 动作,
		])
	else:
		_指令提示("选择要%s的基础效果：在技能栏里选一个，再点「确定」" % 动作)


## 冒险家【冒险者天堂】：能接收星石的队友（同队、不含自己、还有能量空位）
func _提炼候选队友() -> Array[int]:
	var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
	var 候选: Array[int] = []
	if 我 == null:
		return 候选
	for p: GPlayer in Data.player_list:
		if p.id != 我.id and p.color == 我.color and p.get_energy() < p.energy_max:
			候选.append(p.id)
	return 候选


## 冒险家点「提炼」后先问是否触发【冒险者天堂】（对照 role_maoxian）：
##   触发＝额外提炼（基本 2 颗 + 额外 X 颗合成一份，分给队友）；
##   不触发＝走一次常规提炼。若此刻根本触发不了（没能量 / 没空位 / 战绩区不够），「触发」项半透明点不动。
func _天堂问触发() -> void:
	_提炼是冒险家流程 = false
	_提炼阶段 = 0
	_提炼总数 = 0
	_提炼减能量 = 0
	_提炼宝石 = 0
	_提炼水晶 = 0
	var 选项: Array = [
		{"text": "发动【冒险者天堂】给目标队友提炼星石", "args": [1], "enabled": _天堂额外上限() >= 1},
		{"text": "不触发，常规提炼", "args": [0], "enabled": true},
	]
	_进入本地选项(4, 冒险者天堂技能号, 选项, "是否触发【冒险者天堂】？", 二级选项底色)


## 【冒险者天堂】能额外提炼的最大数 X，受四头限制：
##   自身能量（每颗额外提炼的代价是移除自身 1 点能量）、总颗数上限（GConst.提炼总数上限）、
##   队友能收的星石空位合计（2 + X 颗只能分给队友，自己那份不能领）、战绩区现存量（2 + X 颗都从战绩区出）
func _天堂额外上限() -> int:
	var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
	if 我 == null:
		return 0
	var 星石总数: int = _队伍宝石() + _队伍水晶()
	return mini(mini(我.get_energy(), GConst.提炼总数上限 - 2),
		mini(_提炼可分配空位() - 2, 星石总数 - 2))


## 【冒险者天堂】：选额外提炼数 X（基本提炼 2 颗 + 额外 X 颗＝本次总数）
func _天堂问额外数量() -> void:
	var 选项: Array = []
	for x: int in range(1, maxi(_天堂额外上限(), 0) + 1):
		选项.append({"text": "额外提炼 %d" % x, "args": [x]})
	if 选项.is_empty():
		# 触发不了：退回常规提炼（正常走不到，「触发」项已按同一上限置灰）
		_指令提示("无法触发【冒险者天堂】，改为常规提炼")
		_列提炼组合()
		return
	# 提示取技能表 1202「提示」列第 1 条（序号 0）；表里没配才退回硬编码那句
	var 提示: String = GConst.提示文本(冒险者天堂技能号, 0, "", 0)
	if 提示.is_empty():
		提示 = "发动【冒险者天堂】：选择额外提炼数量"
	_进入本地选项(1, 冒险者天堂技能号, 选项, 提示, 二级选项底色)


## 我方战绩区的宝石（查不到返回 0）
func _队伍宝石() -> int:
	var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
	if 我 == null:
		return 0
	var 战绩: GTeam = Data.team_of(我.color)
	return 战绩.gem if 战绩 != null else 0


## 我方战绩区的水晶（查不到返回 0）
func _队伍水晶() -> int:
	var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
	if 我 == null:
		return 0
	var 战绩: GTeam = Data.team_of(我.color)
	return 战绩.crystal if 战绩 != null else 0


## 本地二级栏选项步骤：进 mode 6 把选项摆进二级技能栏（不走服务端）；「确定 / 取消」按
## _本地选项阶段 分派（见 _on_ok / _on_cancel）。父技能号 > 0 时最左摆那颗技能按钮，0＝只有选项。
## 底色默认走「特殊行动」绿（购买 / 合成 / 提炼这一条）；【冒险者天堂】那条传通用灰
func _进入本地选项(阶段: int, 父技能号: int, 选项: Array, 提示: String,
		选项底色: Color = 二级选项底色_特殊行动) -> void:
	_本地选项阶段 = 阶段
	_本地询问 = true
	_是技能询问 = false
	_mode = 6
	# 上一步摆在头像上的选中高亮 / 分配提示先收掉：这一步是全新的选择
	# （典型的：冒险者天堂走到「点头像分配」又取消，退回常规提炼时头像还亮着）
	_sel_players.clear()
	_重置治疗分配()
	_清空技能按钮()
	_进入二级技能栏(父技能号, null, _选项项(选项), 选项底色)
	_指令提示(提示)
	刷新选中面板()
	_更新按键()


## 本地二级栏选项（特殊行动选星石）：确定＝按当初那个特殊行动提交（购买 / 合成 / 常规提炼给自己）
func _确认特殊行动选石() -> void:
	if _二级选中 < 0:
		return
	var 参数: Array = _已选参数
	_本地选项阶段 = 0
	_本地询问 = false
	_发送特殊行动(_待定特殊行动, int(参数[0]) if 参数.size() > 0 else 0, int(参数[1]) if 参数.size() > 1 else 0)


## 本地二级栏选项（特殊行动选星石）：取消＝退回「购买 / 合成 / 提炼」三选一
func _取消特殊行动选石() -> void:
	_本地选项阶段 = 0
	_本地询问 = false
	_进入特殊行动()


## 冒险家提炼前那一问（本地二级栏）：触发【冒险者天堂】＝问额外提炼数；不触发＝走常规提炼
func _确认天堂触发() -> void:
	if _二级选中 < 0:
		return
	var 触发: int = int(_已选参数[0]) if not _已选参数.is_empty() else 0
	_本地选项阶段 = 0
	_本地询问 = false
	if 触发 == 0:
		_列提炼组合()
		return
	_提炼是冒险家流程 = true
	_天堂问额外数量()


## 冒险家【冒险者天堂】第 2 步：选定额外提炼数 X → 本次总数＝基本提炼 2 颗 + 额外 X 颗 → 选构成并分配
func _天堂确认额外() -> void:
	if _二级选中 < 0:
		return
	_提炼减能量 = int(_已选参数[0]) if not _已选参数.is_empty() else 0
	_提炼总数 = 2 + _提炼减能量
	_本地选项阶段 = 0
	_天堂列组合()


## 冒险家【冒险者天堂】最后一步：选整份星石（2 + X 颗）的构成，并在同一个窗口里点头像
## 把星石分给队友（先宝石、后水晶，点一次一颗，点够总数才能「确定」；自己那份不能领）。
## 选项列出所有「x 宝石 y 水晶」（x + y＝本次总数，各不超过战绩区现存量）；
## 进栏先把第一项选上，提示条当场报出要分的份数，玩家可以直接点头像；换选法就点别的选项。
## 点「取消」＝整次提炼作废，退回行动阶段（见 _on_cancel）
func _天堂列组合() -> void:
	var 宝石: int = _队伍宝石()
	var 水晶: int = _队伍水晶()
	var 选项: Array = []
	var 最少宝石: int = maxi(0, _提炼总数 - 水晶)
	var 最多宝石: int = mini(_提炼总数, 宝石)
	for g: int in range(最少宝石, 最多宝石 + 1):
		选项.append({"text": _星石文案(g, _提炼总数 - g), "args": [g, _提炼总数 - g]})
	if 选项.is_empty():
		_指令提示("战绩区星石不足，无法提炼")
		_回到行动阶段()
		return
	# 只能分给队友（自己的那份不能领）：点头像按颗数分，先宝石后水晶
	var 候选: Array[int] = _提炼候选队友()
	_提炼阶段 = 4
	_本地询问 = true
	_是技能询问 = false
	_skill_ask_id = 冒险者天堂技能号
	_提炼宝石 = 0
	_提炼水晶 = 0
	# 借「本地技能询问」这条通道进 mode 3：点头像分配那套（_玩家可选 / _点治疗目标 /
	# _刷新治疗分配 / 确定提交）全都认这个模式，选项则自己摆进二级技能栏
	_pending_type = GConst.Msg.Respond
	_pending = {
		"respond_id": 冒险者天堂技能号, "args": [0, 1, GConst.CardSource.Hand, 0],
		"dst_ids": 候选, "can_cancel": true,
	}
	_进入技能询问()
	_进入二级技能栏(冒险者天堂技能号, null, _选项项(选项), 二级选项底色)
	_重置治疗分配()
	# 默认选上第一项：提示条与头像立刻可用
	_选中二级选项(冒险者天堂技能号, 0)


## 冒险家【冒险者天堂】最后一步：把二级栏里选定的构成记下来（args = [宝石, 水晶]），
## 顺手刷新提示条与头像上的分配（换构成只改宝石 / 水晶的搭配，总颗数不变）
func _应用提炼组合() -> void:
	_提炼宝石 = int(_已选参数[0]) if _已选参数.size() > 0 else 0
	_提炼水晶 = int(_已选参数[1]) if _已选参数.size() > 1 else 0
	_刷新治疗分配()
	_指令提示("分配提取的 %s，点击优先分配宝石" % _星石文案(_提炼宝石, _提炼水晶))


## 冒险家【冒险者天堂】：选额外提炼数时把「要移除的自身能量」预览在自己头像上
## （选的额外提炼数就是移除的自身能量数；还没选就收掉）
func _刷新提炼能量预览() -> void:
	_重置治疗分配()
	var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
	if 我 == null or _已选参数.is_empty():
		return
	var 移除数: int = int(_已选参数[0])
	if 移除数 <= 0:
		return
	# 移除自身能量优先扣水晶（与服务端 BattlePlayer.remove_energy 同一口径）
	var 用水晶: int = mini(移除数, 我.crystal)
	var 用宝石: int = 移除数 - 用水晶
	for 面板: 战斗玩家面板 in _面板列表:
		if 面板.ID == Logic.my_player_id:
			_贴头像提示(面板, _取治疗提示(面板.ID), "移除 " + _星石文案(用宝石, 用水晶))
			return


## 某玩家的能量空位（energy_max 减当前能量；查不到返回 0）
func _玩家空位(pid: int) -> int:
	var p: GPlayer = Data.get_player_by_id(pid)
	return (p.energy_max - p.get_energy()) if p != null else 0


## 冒险家【冒险者天堂】：两名队友合计能收的星石上限（取空位最多的两名，保证后面点头像分得下）
func _提炼可分配空位() -> int:
	var 空位表: Array[int] = []
	for pid: int in _提炼候选队友():
		空位表.append(_玩家空位(pid))
	空位表.sort()
	var 合计: int = 0
	for i: int in range(mini(2, 空位表.size())):
		合计 += 空位表[空位表.size() - 1 - i]
	return 合计


## 星石颗数的文案：「3 宝石 2 水晶」（某一类为 0 就只写另一类）
func _星石文案(宝石: int, 水晶: int) -> String:
	var 段: Array[String] = []
	if 宝石 > 0:
		段.append("%d 宝石" % 宝石)
	if 水晶 > 0:
		段.append("%d 水晶" % 水晶)
	return " ".join(段) if not 段.is_empty() else "0 星石"


## 冒险家【冒险者天堂】：按点击先后把整份星石摊到各队友头上——前「宝石总数」颗算宝石、
## 其余算水晶（头像提示与提交用同一口径，见 _提炼分配文本表 / _发送冒险家提炼分配）。
## 返回 {队友id: [宝石颗数, 水晶颗数]}，键序即首次点击先后
func _提炼逐人颗数() -> Dictionary:
	var 逐人: Dictionary = {}
	var 序: int = 0
	for id: int in _治疗分配:
		序 += 1
		var 数: Array = 逐人.get(id, [0, 0])
		if 序 <= _提炼宝石:
			数[0] = int(数[0]) + 1
		else:
			数[1] = int(数[1]) + 1
		逐人[id] = 数
	return 逐人


## 冒险家【冒险者天堂】：点头像分配结果提交。dst_ids＝各队友（去重、按点击先后），
## args＝[天堂标记, 自己的宝石, 自己的水晶, 给队友的宝石, 给队友的水晶, 移除的自身能量 X,
##        队友1颗数, 队友2颗数]（头位标记让服务端认出这是天堂，而不是数参数个数；
## 星石只能分给队友，所以中间那两位恒为 0，队友那份按颗数拆成宝石 / 水晶）
func _发送冒险家提炼分配() -> void:
	var 队友宝石: int = 0
	var 队友水晶: int = 0
	var 目标表: Array[int] = []
	var 颗数表: Array[int] = []
	var 逐人: Dictionary = _提炼逐人颗数()
	for pid: Variant in 逐人:
		var 数: Array = 逐人[pid]
		目标表.append(int(pid))
		颗数表.append(int(数[0]) + int(数[1]))
		队友宝石 += int(数[0])
		队友水晶 += int(数[1])
	var args: Array = [GConst.提炼天堂标记, 0, 0, 队友宝石, 队友水晶, _提炼减能量]
	args.append_array(颗数表)
	# 提交前把流程状态收掉（这份 args 已带全「给自己 / 给队友」两份）
	_提炼阶段 = 0
	_本地选项阶段 = 0
	_本地询问 = false
	_提炼是冒险家流程 = false
	_发送行动(GConst.ActionType.Special, GConst.SpecialAction.Extract, 目标表, [], args)


## 选定一种特殊行动后，再选「用哪些星石」——选项逐条对照原客户端
## Role::buy（战绩区 4 个时二选一、5 个已满）/ Role::synthetize / Role::extract 的选项盒。
## 冒险家点「提炼」时不走这里，改成先问一次是否触发【冒险者天堂】（见 _天堂问触发）
func _选特殊行动(action_id: int) -> void:
	var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
	if 我 == null or 我.color == GConst.TEAM_NONE:
		return
	# 提炼单开一条（冒险家还要先问是否触发【冒险者天堂】），这里只处理购买 / 合成
	if action_id == GConst.SpecialAction.Extract:
		_提炼是冒险家流程 = false
		if 我.role_id == 冒险家角色号:
			_天堂问触发()
			return
		_列提炼组合()
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
	if 组合.is_empty():
		_指令提示("没有可用的星石组合")
		return
	if 组合.size() == 1:
		# 只有一种组合（如购买时的「+1 宝石 +1 水晶」「战绩区已满」）就不用再问一遍
		var 只: Dictionary = 组合[0]
		_发送特殊行动(action_id, int(只["gem"]), int(只["crystal"]))
		return
	# 第二层（选「用哪些星石」）走二级技能栏（本地步骤）：选项排成一行，选好点「确定」提交
	var 选项: Array = []
	for 项: Variant in 组合:
		var d: Dictionary = 项
		选项.append({"text": str(d["text"]), "args": [int(d["gem"]), int(d["crystal"])]})
	_待定特殊行动 = action_id
	_进入本地选项(2, 0, 选项,
		"选择要购买的星石" if action_id == GConst.SpecialAction.Buy else "选择要合成的星石")


## 常规提炼：把战绩区能取出的星石列成组合（取给自己），进二级技能栏点「确定」提交。
## 自己星石满了就提炼不出来，此时列表照摆但「确定」是灰的（见 _确定不可用）
func _列提炼组合() -> void:
	var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
	if 我 == null or 我.color == GConst.TEAM_NONE:
		return
	_提炼是冒险家流程 = false
	var 战绩: GTeam = Data.team_of(我.color)
	var 宝石: int = 战绩.gem
	var 水晶: int = 战绩.crystal
	var 余量: int = 我.energy_max - 我.get_energy()
	var 组合: Array = []
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
	if 组合.is_empty():
		_指令提示("没有可用的星石组合")
		return
	# 唯一一种组合也直接提交（自己装得下才有意义；装不下就摆出来让「确定」灰着，见 _确定不可用）
	if 组合.size() == 1 and 余量 >= 1:
		var 只: Dictionary = 组合[0]
		_发送特殊行动(GConst.SpecialAction.Extract, int(只["gem"]), int(只["crystal"]))
		return
	var 选项: Array = []
	for 项: Variant in 组合:
		var d: Dictionary = 项
		选项.append({"text": str(d["text"]), "args": [int(d["gem"]), int(d["crystal"])]})
	_待定特殊行动 = GConst.SpecialAction.Extract
	_进入本地选项(2, 0, 选项,
		"选择要提炼的星石" if 余量 >= 1 else "自己星石已满，无法常规提炼")


## 发出特殊行动：args = [宝石数, 水晶数]（服务端 _do_special 按这个口径结算）。
## 常规提炼＝给自己，不带 dst；【冒险者天堂】给队友那条走 _发送冒险家提炼分配
func _发送特殊行动(action_id: int, gem: int, crystal: int) -> void:
	_发送行动(GConst.ActionType.Special, action_id, [], [], [gem, crystal])


## 退回行动阶段（取消发动技能 / 取消特殊行动时用），顺手把本回合的技能按钮摆回来
func _回到行动阶段() -> void:
	_mode = 1
	_sel_cards.clear()
	_sel_players.clear()
	_重置治疗分配()
	# 取消「先弹选项」型技能（如【死亡之触】）时把二级栏里选定的那个效果一并清掉
	_先弹选项 = false
	_已选参数.clear()
	_目标锁死 = false
	# 退回行动阶段＝放弃【冒险者天堂】提炼流程 / 特殊行动的选星石步骤
	_提炼阶段 = 0
	_本地选项阶段 = 0
	_本地询问 = false
	# 退回行动阶段就不再选盖牌了：不关掉会把盖牌区一直亮着、挡住界面（如取消【雷光散射】）
	_selecting_cover = false
	_skill_cover_need = 0
	_清空技能按钮()
	if not _行动命令.is_empty():
		_构建技能按钮(_行动命令)
	_指令提示("轮到你了：选择一张手牌作为攻击/法术，或点「特殊行动」「放弃行动」")
	刷新手牌()
	刷新盖牌()
	刷新选中面板()
	_更新按键()


# ---------------- 技能动作 ----------------
## 「自动选目标」型：进场即把目标选中并锁死（点头像也改不了，只能靠「取消」退出），
## 被选中的头像上直接画技能指示器的效果。值：
##   自己 / 他人 / 全体 —— 按角色表语义（如【瘟疫】对除自己外所有人、【逆流】只有自己）
##   询问目标           —— 服务端在本次询问里点名的那个角色（如【毒粉】：挨这次伤害的人）
## 返回 true＝本次属于这一型（调用方据此把 _目标锁死 置位）
func _套用自动选目标(指示配置: Dictionary) -> bool:
	var 型: String = str(指示配置.get("自动选目标", ""))
	if 型.is_empty():
		return false
	match 型:
		"自己":
			_sel_players.append(Logic.my_player_id)
		"他人":
			for 玩家: GPlayer in Data.player_list:
				if 玩家.id != Logic.my_player_id:
					_sel_players.append(玩家.id)
		"全体":
			for 玩家: GPlayer in Data.player_list:
				_sel_players.append(玩家.id)
		"询问目标":
			_sel_players.append_array(_skill_targets)
	return true


## 选中并准备发动某个技能（行动阶段点技能按钮）
## 合法目标 / 合法牌由服务端的技能声明给出（targets / cards），非空时界面只让它们可点；
## 需牌是最少张数、最多牌（card_max）是点选上限（省略＝刚好 need_card 张），目标数同理走 target_max；
## 选牌来源 card_source 决定是从手牌、盖牌区还是场上基础效果牌里选；
## 参数选项 arg_choices 非空时改由选项按钮提交（服务端靠 args 的技能都走这条）
func _选择技能(技能号: int, 技能类型: int, 需牌: int, 需目标: int, 合法目标: Array = [], 合法牌: Array = [],
		最多牌: int = 0, 最多目标: int = 0, 目标上限减牌数: int = 0,
		选牌来源: int = GConst.CardSource.Hand, 选牌规则: String = "",
		首张技能: int = 0, 次张系别: int = 0, 参数选项: Array = [], 按钮: Node = null, 盖牌需数: int = 0) -> void:
	# 二级栏正开着、点的又是它最左那颗父技能按钮：这一下＝收起二级栏，等同「取消」本次技能选择。
	# 只有「玩家自己点技能开出来的二级栏」走这条；响应弹出的询问（技能询问那条通道）没有回退，
	# 那颗父技能牌只当牌子用，只能靠右下角的「确定 / 取消」
	if _二级栏 and 按钮 != null and 按钮 == _二级栏父按钮:
		_on_cancel()
		return
	_mode = 4
	_标记选中技能(按钮)
	# 重新点技能按钮＝从头来一遍：上次留下的二级栏选项由下面带选项时重进二级栏的 _清空二级选项 收掉
	# （本地「先选一项」的星石步骤也一并收掉，免得还认着上一轮的特殊行动）
	_本地选项阶段 = 0
	_本地询问 = false
	_pending_skill_type = 技能类型
	_pending_skill_id = 技能号
	_skill_need_card = 需牌
	_skill_need_target = 需目标
	_skill_card_max = maxi(需牌, 最多牌)
	_skill_target_max = maxi(需目标, 最多目标)
	_skill_target_max_from_cards = 目标上限减牌数
	_skill_card_source = 选牌来源
	# 手牌 + 盖牌混选（如【魔贯冲击】）：其中若干张必须是盖牌
	_skill_cover_need = 盖牌需数
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
	# 盖牌来源才让盖牌区亮起来；手牌+盖牌混选（盖牌需数>0）也要亮；
	# 基础效果牌由玩家面板上的图标直接点
	_selecting_cover = 选牌来源 == GConst.CardSource.Cover \
		or 选牌来源 == GConst.CardSource.HandOrCover or 盖牌需数 > 0
	# 雷光散射 / 魔贯冲击这类要选盖牌作代价的技能：进来先按最大张数全选上，玩家要改再自己点
	_自动选盖牌(技能号)
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
	# 「自动选目标」型（【瘟疫】/【剧毒新星】：对除自己外所有人；【逆流】：只有自己）：
	# 进场即把目标选中并锁死，点头像也改不了（只能靠「取消」退出）；被选中的头像上直接画效果
	_目标锁死 = _套用自动选目标(指示配置)
	# 带选项的技能（arg_choices）：进「二级技能栏」—— 被点的技能留在最左，选项用技能按钮排在它右边，
	# 选项先选中（亮黄），按「确定」才提交、按「取消」退回行动阶段。
	# 「先弹选项」型只是多一步：选效果之前不让点牌 / 点目标
	_先弹选项 = bool(指示配置.get("先弹选项", false)) and not 参数选项.is_empty()
	_已选参数.clear()
	# 记下技能本体给的需牌 / 目标数 / 选牌来源：选中带这些的效果时要拿它当基准
	# （「先弹选项」型由 _应用选项目标数 还原 / 收紧；其余型见 _选中二级选项）。
	# 【封印破碎】/【风之洁净】/【天使之歌】这类「选完目标才由客户端补选项」的也必须记：
	# 进技能时参数选项还是空的，但之后点那些基础效果选项照样会走 _选中二级选项 里
	# 「以本体为准」那一段 —— 不记就会拿 0 当基准，把需牌算成 0、已选的牌被清掉并整片置灰，
	# 表现就是「选完牌再点选项，牌点不动、技能放不出来」
	if not 参数选项.is_empty() or 选牌来源 == GConst.CardSource.HandAndBasicEffect:
		_选项原始需牌 = _skill_need_card
		_选项原始最多牌 = _skill_card_max
		_选项原始目标数 = _skill_need_target
		_选项原始最多目标 = _skill_target_max
		_选项原始来源 = _skill_card_source
		_选项原始盖牌需数 = _skill_cover_need
	# 「先弹选项」默认在选效果前不让点牌 / 点目标（把需牌 / 目标数临时清零，选完在 _应用选项目标数 里还原）；
	# 配了「允许先选牌」的技能（神官【神圣领域】）不清零：可以先点要弃的牌，用法仍必须先选
	if _先弹选项 and not bool(指示配置.get("允许先选牌", false)):
		_skill_need_card = 0
		_skill_card_max = 0
		_need_cards = 0
		_skill_need_target = 0
		_skill_target_max = 0
		_need_players = 0
	if not 参数选项.is_empty():
		_进入二级技能栏(技能号, 按钮 as 技能按钮, _选项项(参数选项))
		# 「默认选首项」型（如冒险家【欺诈】）：进栏就替玩家把第一个选项选上 ——
		# 手牌不锁、随手就能选牌，也不必先点一次选项才能按「确定」；想换效果再点别的选项
		if bool(指示配置.get("默认选首项", false)):
			_选中二级选项(技能号, 0)
	elif 选牌来源 == GConst.CardSource.HandAndBasicEffect:
		# 【封印破碎】/【风之洁净】：进技能就把二级技能栏摆出来（此刻只有技能本体一颗），
		# 选完目标再由 _刷新基础效果选项 把该目标面前的基础效果填进去 —— 不用先按一次「确定」
		_进入二级技能栏(技能号, 按钮 as 技能按钮, [])
	var 指示提示: String = _发动提示(技能号)
	if not 参数选项.is_empty():
		# 效果选择窗标题配了就用它（如【死亡之触】的「消耗多少治疗？」），否则说「先选一个效果」
		var 选项窗标题: String = str(指示配置.get("选项窗标题", ""))
		if not 选项窗标题.is_empty():
			_指令提示(选项窗标题)
		elif bool(指示配置.get("选项抬头用提示", false)) and not 指示提示.is_empty():
			# 声明「选项抬头用提示」的选项型技能（如【偷天换日】）：抬头改用技能表「提示」列第 1 条，
			# 把几种用法一次说清，不再只说「请在技能栏里选一个选项」
			_指令提示(指示提示)
		else:
			_刷新二级栏提示()
	elif not 指示提示.is_empty():
		_指令提示(指示提示)
	elif 选牌来源 == GConst.CardSource.HandAndBasicEffect:
		_指令提示("发动【%s】：%s%s再在技能栏里选要%s的基础效果" % [
			GConst.skill_name(技能号), _需选牌提示(需牌), _需选目标提示(需目标), _基础效果动作(技能号),
		])
	else:
		# 技能按钮自带自定义选牌提示时用它（如【充能】的代价是「弃到 4 张牌」，说「从手牌中选 4 张」不准确）
		var 选牌提示: String = _技能自定义选牌提示(技能号)
		if 选牌提示.is_empty():
			选牌提示 = _需选牌提示(需牌)
		_指令提示("发动【%s】：%s%s点「确定」" % [
			GConst.skill_name(技能号), 选牌提示, _需选目标提示(需目标),
		])
	_刷新交互()


## 技能按钮自带的选牌提示（action_commands 里的 card_prompt，如【充能】的「弃到 4 张牌，」）：
## 非空时替代默认的「从手牌中选 N 张」
func _技能自定义选牌提示(技能号: int) -> String:
	for i: int in range(1, _行动命令.size()):
		var c: Dictionary = _行动命令[i]
		var args: Array = c.get("args", [])
		if not args.is_empty() and int(args[0]) == 技能号:
			return str(c.get("card_prompt", ""))
	return ""


## 「要选几张牌」的提示文案（含来源：手牌 / 盖牌 / 场上基础效果牌）
func _需选牌提示(需牌: int) -> String:
	if 需牌 <= 0:
		return ""
	var 来源: String = "手牌"
	match _skill_card_source:
		GConst.CardSource.Cover:
			来源 = "盖牌"
		GConst.CardSource.HandOrCover:
			来源 = "手牌或盖牌"
		GConst.CardSource.BasicEffect:
			来源 = "场上基础效果牌"
	return "从%s中选%d张，" % [来源, 需牌]


func _需选目标提示(需目标: int) -> String:
	if 需目标 <= 0:
		return ""
	if _skill_target_max > 需目标:
		return "选%d~%d名目标，" % [需目标, _skill_target_max]
	return "选%d名目标，" % 需目标


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


## 技能「发动提示」：优先用技能指示器里的「提示」（直接写死）；没写就按「提示序号」
## 取技能表「提示」列的第 N 条（魔弓【雷光散射】/【魔眼】的台词放在技能表，改文案不用动代码）
func _发动提示(技能号: int) -> String:
	var 配置: Dictionary = GConst.技能指示器.get(技能号, {})
	var 写死: String = str(配置.get("提示", ""))
	if not 写死.is_empty():
		return 写死
	if 配置.has("提示序号"):
		return GConst.提示文本(技能号, int(配置.get("提示序号", 0)), "", 0)
	return ""


## 只取「点头像分配」型的那份配置（配了「每次」才算）：它接管目标选取与提交
## （args 是各目标点数 / 用法），纯展示型返回空
func _分配配置() -> Dictionary:
	var 配置: Dictionary = _指示器配置()
	return 配置 if int(配置.get("每次", 0)) > 0 else {}


## 本次已分配的总点数（点击数 × 每次）
func _分配点数() -> int:
	return _治疗分配.size() * int(_分配配置().get("每次", 1))


## 本次已分配到的不同角色数（同一人点多次只算一名）；配了「目标数上限」的技能用它限制人数
func _分配目标数() -> int:
	var 去重: Dictionary = {}
	for id: int in _治疗分配:
		去重[id] = true
	return 去重.size()


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
	# 【冒险者天堂】的上限＝本次提炼出的星石总数（取到的宝石 + 水晶）
	if _mode == 3 and _skill_ask_id == 冒险者天堂技能号:
		return _提炼宝石 + _提炼水晶
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
	# 配了「目标数上限」的技能（红莲骑士【血腥祷言】：1~2 名队友）：已分满这么多名队友后再点新的一名，
	# 就把整份挪到它身上（与下面「点数超过上限」的处理一致）——保证别让人点出第 3 名
	var 目标数上限: int = int(配置.get("目标数上限", 0))
	if 目标数上限 > 0 and not _治疗分配.has(player_id) and _分配目标数() >= 目标数上限:
		_治疗分配 = [player_id]
		_刷新治疗分配()
		return
	if not bool(配置.get("可重复", false)) and _治疗分配.has(player_id):
		return
	# 突破上限的转移有封顶（如神官【神圣契约】「无视其治疗上限、但最高到 4 点」）：
	# 点到封顶就不再往这个目标加，免得分超了、多出的点数被服务端截掉白费
	if bool(配置.get("突破上限", false)):
		var 封顶: int = int(配置.get("突破封顶", 0))
		if 封顶 > 0:
			var 目标已有: int = 0
			for id: int in _治疗分配:
				if id == player_id:
					目标已有 += 每次
			if 目标已有 + 每次 > 封顶:
				return
	# 【冒险者天堂】每名队友各有限额（其能量空位）：已装不下的队友再点不再增加
	if _mode == 3 and _skill_ask_id == 冒险者天堂技能号:
		var 已有: int = 0
		for id: int in _治疗分配:
			if id == player_id:
				已有 += 每次
		if 已有 + 每次 > _玩家空位(player_id):
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
		# 【冒险者天堂】分的是星石颗数，还要按「先宝石、后水晶」拆开写（见 _提炼分配文本表）
		var 提炼文本: Dictionary = {}
		if _mode == 3 and _skill_ask_id == 冒险者天堂技能号:
			提炼文本 = _提炼分配文本表()
		# 【血腥祷言】这类：转出去多少点治疗，自己就吃等量法术伤害（配置「转出反噬」），
		# 那句写在自己头像上 —— 自己不在分配名单里，所以单独画一句
		var 反噬: int = _治疗分配.size() * 每次 if bool(配置.get("转出反噬", false)) else 0
		for 面板: 战斗玩家面板 in _面板列表:
			var 次数: int = 0
			for id: int in _治疗分配:
				if id == 面板.ID:
					次数 += 1
			if 面板.ID == Logic.my_player_id and 反噬 > 0:
				_刷治疗提示(面板, 次数 * 每次, 反噬)
				continue
			if 次数 <= 0:
				continue
			if not 提炼文本.is_empty():
				_贴头像提示(面板, _取治疗提示(面板.ID), str(提炼文本.get(面板.ID, "")))
			else:
				_刷治疗提示(面板, 次数 * 每次, 0)
			_sel_players.append(面板.ID)
	刷新选中面板()
	_更新按键()


## 【冒险者天堂】各队友头像上的「x 宝石 x 水晶」：口径同 _提炼逐人颗数
func _提炼分配文本表() -> Dictionary:
	var out: Dictionary = {}
	var 逐人: Dictionary = _提炼逐人颗数()
	for id: Variant in 逐人:
		var 数: Array = 逐人[id]
		out[id] = _星石文案(int(数[0]), int(数[1]))
	return out


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
## （治疗＝浅蓝、法术伤害＝洋红、攻击伤害＝红，见 _提示上色）。
## 刻意挂在 Root 上而不是玩家面板里：面板被选中时会整体染黄，挂在里面的文字会跟着变黄、
## 看起来像被选中效果盖住；挂 Root 上就在面板之上、且不受它的 modulate 影响
func _取治疗提示(player_id: int) -> RichTextLabel:
	if _治疗提示表.has(player_id):
		return _治疗提示表[player_id]
	# 尺寸 / 字号 / 上色 / 描边 / 默认隐藏都在 HealTip.tscn 里
	var 提示: RichTextLabel = 治疗提示预制.instantiate()
	Root.add_child(提示)
	_治疗提示表[player_id] = 提示
	return 提示


## 头像提示的按内容上色：含「法术伤害」的行用洋红、攻击那类伤害（「攻击伤害」/「物理伤害」）的行用红、
## 含「治疗」的行用浅蓝，其余保持白色。
## 同一个头像上治疗与伤害可能各占一行（_效果文本 用换行拼接），所以逐行判定、
## 逐行居中（RichTextLabel 没有 horizontal_alignment，居中只能靠 BBCode 的 [center]）
func _提示上色(文: String) -> String:
	if 文.is_empty():
		return ""
	var 行: Array[String] = []
	for 段: String in 文.split("\n"):
		if 段.contains("法术伤害"):
			行.append("[color=#%s]%s[/color]" % [提示色_法术伤害, 段])
		elif 段.contains("攻击伤害") or 段.contains("物理伤害"):
			行.append("[color=#%s]%s[/color]" % [提示色_攻击伤害, 段])
		elif 段.contains("治疗"):
			行.append("[color=#%s]%s[/color]" % [提示色_治疗, 段])
		else:
			行.append(段)
	return "[center]%s[/center]" % "\n".join(行)


## 把一句话贴到该面板头像正中：框宽按最长一行现算（RichTextLabel 会裁掉超出框的文字，
## 像「本次法术伤害+1」这种长文案按固定宽度就会显示不全），框高按文案行数现算，再整体居中。
## 文为空就收起
func _贴头像提示(面板: 战斗玩家面板, 提示: RichTextLabel, 文: String) -> void:
	提示.visible = 文 != ""
	if 文.is_empty():
		return
	提示.text = _提示上色(文)
	# 量宽度与行数要用「解析后的纯文本」：文案里可能带 BBCode（如 [zwj] 删除线标记、[color]），
	# 标签本身不该算进宽度，否则框会被撑得很宽
	var 行: PackedStringArray = 提示.get_parsed_text().split("\n")
	var 字体: Font = 提示.get_theme_font("normal_font")
	var 字号: int = 提示.get_theme_font_size("normal_font_size")
	var 宽: float = 治疗提示宽
	for 行文: String in 行:
		# 最长一行两侧各留 8px 余量：描边画在字外，贴着框边会被切掉
		宽 = maxf(宽, 字体.get_string_size(行文, HORIZONTAL_ALIGNMENT_LEFT, -1, 字号).x + 16.0)
	提示.size = Vector2(宽, 提示行高 * float(行.size()))
	提示.position = 面板.get_rect().get_center() - 提示.size * 0.5
	_铺粗删除线(提示, 文.split("\n"), 行, 字体, 字号)


## 给提示里被 [zwj] 标记的那些行，各压一条加粗横线（[zwj] 是零宽标记、自己不渲染，
## 字体自带的 [s] 删除线太细又偏下，所以整条线由这里自己画）。
## 线做成提示框的子节点：跟着框一起平移缩放，不用另算全局坐标。
## 竖坐标取「行高的一半」（＝字体上沿与下沿的正中），看上去正好穿过字的中腰
func _铺粗删除线(提示: RichTextLabel, 原文行: PackedStringArray, 纯文行: PackedStringArray,
		字体: Font, 字号: int) -> void:
	for 子: Node in 提示.get_children():
		提示.remove_child(子)
		子.queue_free()
	var 行高: float = 字体.get_height(字号)
	for i: int in range(原文行.size()):
		if not 原文行[i].contains("[zwj"):
			continue
		var 文字宽: float = 字体.get_string_size(纯文行[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 字号).x
		var 条: ColorRect = 删除线预制.instantiate()
		条.size = Vector2(文字宽, 删除线粗细)
		条.position = Vector2((提示.size.x - 文字宽) * 0.5,
			float(i) * 行高 + (行高 - 删除线粗细) * 0.5)
		提示.add_child(条)


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
	# 文字「+」/ 尺寸 / 居中 / 配色 / 描边都在 HealPlus.tscn 里（字号每颗随机，运行时设）
	var 加号: Label = 加号预制.instantiate()
	加号.add_theme_font_size_override("font_size", randi_range(30, 46))
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


## 受伤飘字：服务端广播「本次伤害点数（含各类加成，尚未经治疗抵挡/抵御扣减）」—— 在该角色头像中间冒出数字，
## 向上飘出并淡掉。法术伤害洋红、攻击伤害红（见 飘字色_*），所有人都看得到
func _on_hurt_float(dst_id: int, point: int, 类型: int) -> void:
	# 法术伤害的飘字由 _播放法术伤害 在排队轮到它时生成（与受击表现同一条、有先后），这里不重复飘
	if 类型 == GConst.HarmType.Magic:
		return
	_伤害飘字(dst_id, point, 飘字色_法术伤害 if 类型 == GConst.HarmType.Magic else 飘字色_攻击伤害)


## 本次伤害数字的基准缩放：1 点最小、7 点及以上最大，中间按点数线性过渡
func _飘字基准缩放(点数: int) -> float:
	var 比例: float = clampf(
		float(点数 - 飘字最小点数) / float(飘字最大点数 - 飘字最小点数), 0.0, 1.0)
	return lerpf(飘字最小缩放, 飘字最大缩放, 比例)


## 单个伤害数字：从头像正中冒出（出场先弹出到「基准 × 冒头倍率」，再缩回基准），然后向上飘走并淡出，放完自毁。
## 数字大小随伤害点数走（1 点最小、7 点及以上最大），见 _飘字基准缩放
func _生成伤害飘字(中心: Vector2, 点数: int, 色: Color) -> void:
	# 尺寸 / 居中 / 字号 / 描边都在 HurtFloat.tscn 里（文本与字色随伤害点数走，运行时设）
	var 飘字: Label = 飘字预制.instantiate()
	飘字.text = str(点数)
	飘字.add_theme_color_override("font_color", 色)
	Root.add_child(飘字)
	# 起点是「左上角」，终点必须也从左上角往上抬 —— 原来拿中心点当左上角用，
	# 于是横向平白多走了半个框宽（240/2＝120px），看着就是横着飘
	var 起点: Vector2 = 中心 - 飘字尺寸 * 0.5
	var 终点: Vector2 = 起点 + Vector2(0.0, -飘字上飘)
	var 基准: float = _飘字基准缩放(点数)
	飘字.position = 起点
	# 起手就是基准大小，冒头时先撑到峰值再缩回来
	飘字.scale = Vector2.ONE * 基准
	var t: Tween = create_tween()
	# ① 弹出：基准 → 基准 × 冒头倍率
	t.tween_property(飘字, "scale", Vector2.ONE * 基准 * 飘字冒头倍率, 飘字放大时长) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# ② 缩回：基准 × 冒头倍率 → 基准
	t.tween_property(飘字, "scale", Vector2.ONE * 基准, 飘字缩回时长) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# ③ 缩回之后才开始上飘；淡出与上飘并行（后 60% 的时间里淡掉）
	t.tween_property(飘字, "position", 终点, 飘字时长).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.set_parallel(true)
	t.tween_property(飘字, "modulate:a", 0.0, 飘字时长 * 0.6).set_delay(飘字时长 * 0.4)
	t.chain().tween_callback(飘字.queue_free)


## 伤害飘字的统一入口：格斗家【念气力场】（被动）会把每次受到的伤害压到 GConst.念气力场上限 点，
## 于是给他的飘字直接写成压低后的数值（不划掉、不换行）
func _伤害飘字(dst_id: int, 点数: int, 色: Color) -> void:
	if 点数 <= 0:
		return
	var 中心: Vector2 = _面板中心(dst_id)
	if 中心.x < 0.0:
		return
	var 目标: GPlayer = Data.get_player_by_id(dst_id)
	var 显示点数: int = 点数
	if 目标 != null and 目标.role_id == GConst.角色_格斗:
		显示点数 = mini(点数, GConst.念气力场上限)
	_生成伤害飘字(中心, 显示点数, 色)


## 某玩家面板的中心点（与治疗方案提示同一坐标系，都挂在 Root 上）；没有这个面板时返回 (-1, -1)
func _面板中心(player_id: int) -> Vector2:
	for 面板: 战斗玩家面板 in _面板列表:
		if 面板.ID == player_id:
			return 面板.get_rect().get_center()
	return Vector2(-1.0, -1.0)


## 受击反馈（泛红 / 抖动 / 画面扭曲震荡波）已移进角色头像面板（战斗玩家面板.Hurted），
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
	# 【冒险者天堂】分配的不是「点数」而是「星石颗数」，且走特殊行动（提炼）提交，单独一条
	if _mode == 3 and _skill_ask_id == 冒险者天堂技能号:
		_发送冒险家提炼分配()
		return
	# 配了「阵营效果」的技能（【神圣领域】）：只有一个目标，args 不是点数而是「用哪种用法」——
	# 选队友（含自己）＝0（自己 +2、目标 +1 治疗），选敌人＝1（移除自己 1 治疗、目标受 2 点法术伤害）
	var 阵营表: Dictionary = _分配配置().get("阵营效果", {})
	if not 阵营表.is_empty():
		var 目标: int = int(_治疗分配[0]) if not _治疗分配.is_empty() else -1
		# 用法以二级技能栏里选定那一项为准（【神圣领域】第一步的二选一）；没走过二级栏才按目标我方/敌方推
		var 用法: int = int(_已选参数[0]) if not _已选参数.is_empty() else (1 if _阵营键(目标) == "敌人" else 0)
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
	_行动命令.clear()
	_skill_ask_id = -1
	_是技能询问 = false
	_额外行动单选 = -1
	_额外行动可选 = true
	_skill_ask_need_card = 0
	_skill_ask_need_target = 0
	_skill_ask_card_source = 0
	_selecting_cover = false
	_不可行动 = false
	_行动禁特殊 = false
	_skill_options.clear()
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
	_skill_cover_need = 0
	_skill_arg_choices.clear()
	_skill_ask_can_cancel = true
	_本地询问 = false
	_本地选项阶段 = 0
	_提炼阶段 = 0
	_提炼是冒险家流程 = false
	_提炼总数 = 0
	_提炼减能量 = 0
	_提炼宝石 = 0
	_提炼水晶 = 0
	_查看盖牌 = false
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
##         本地角色有【魔弹掌控】802 时左右各一个都能选
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
			# 默认只有右手边那个对手；有【魔弹掌控】时左手边那个也能选（逆向传递）
			return player_id == _魔弹目标() or (_有魔弹掌控() and player_id == _魔弹逆向目标())
		_:
			return false


## 【魔弹】的落点：右手边（post 方向）最近的一名敌人 —— 服务端 _nearest_enemy 就是这么走的。
## 没有【魔弹掌控】时目标就固定是他；界面只让他亮，点了他才释放。
func _魔弹目标() -> int:
	return _沿方向找敌人(1)


## 【魔弹】的逆向落点：左手边（pre 方向）最近的一名敌人 —— 只有【魔弹掌控】802 能选
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


## 本地角色有没有【魔弹掌控】（802）：有的话打【魔弹】时左手边那个对手也亮
func _有魔弹掌控() -> bool:
	var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
	return 我 != null and 魔弹掌控角色.has(我.role_id)


## 魔弹传递的可选落点：服务端在询问的 dst_ids 里给，只有当前传出方向上那个人
## （传递时不能改向，【魔弹掌控】只作用于主动打出那一步）。界面只把这个点亮，点他就传过去。
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


## 选中的手牌是否是「靠点人头像定目标」的法术牌（【圣盾】/【虚弱】/【中毒】）。
## 这三张不点目标就提交时，服务端默认对自己施放，所以要按下面 _确定不可用 的规则把「确定」灰掉
func _选中是点头像定目标的牌() -> bool:
	if _sel_cards.is_empty():
		return false
	var card: GCard = Data.get_card(_sel_cards[0])
	if card == null:
		return false
	var 名: int = card.card_name_enum()
	return 名 == GConst.CardName.Shield or 名 == GConst.CardName.Weaken or 名 == GConst.CardName.Poison


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


## 进入技能选牌界面时，若本技能在「自动选盖牌」名单里，就把盖牌区能选的最大张数先全选上
## （玩家想少用几张，自己把多出来的点掉即可）
func _自动选盖牌(技能号: int) -> void:
	if not _selecting_cover or not 自动选盖牌技能.has(技能号):
		return
	# 能选几张：手牌+盖牌混选型看「需盖牌数」（如魔贯冲击＝1），纯盖牌型看点选上限（如雷光散射＝全部雷系）
	var 上限: int = _skill_cover_need if _skill_cover_need > 0 else _skill_card_max
	if 上限 <= 0:
		return
	for 牌: GCard in Data.cover_cards:
		if 牌 == null:
			continue
		if _sel_cards.size() >= 上限:
			break
		if _卡牌能点(牌.id):
			_sel_cards.append(牌.id)


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


## 单行排列的「相邻两张左边的距离（间距）」与「首张左边的 x（起点）」：
## 位置够就贴着排（相邻空隙 0），一行放不下才把空隙压成负数（叠着放、最多重叠 最多重叠比例）。
## 手牌区与展示卡牌区共用这一套算法
func _单行间距与起点(张数: int, 可用宽: float, 尺寸: Vector2, 最多重叠比例: float) -> Array:
	if 张数 <= 0:
		return [尺寸.x, 0.0]
	# 相邻两张之间的空隙：牌少时贴着排（0 是最好的），一行放不下才压成负数（叠着放）
	var 空隙: float = 0.0
	if 张数 > 1:
		空隙 = clampf((可用宽 - 尺寸.x * float(张数)) / float(张数 - 1), -尺寸.x * 最多重叠比例, 0.0)
	# 两牌「左边」的距离 = 牌宽 + 空隙
	var 间距: float = 尺寸.x + 空隙
	var 起点: float = (可用宽 - (尺寸.x * float(张数) + 空隙 * float(张数 - 1))) * 0.5
	return [间距, 起点]


## 我的手牌：固定排成一行并水平居中；位置够就摊开，不够才压间距（压到负数会叠着放），绝不换行
## 每张牌按 _卡牌能点 单独判定：够格的亮起来，其余的置灰且点不动
func 刷新手牌() -> void:
	# 复用同 id 的已有卡牌节点：每份快照都销毁重建整排手牌的话，每张都要重新实例化、重画卡面，
	# 快照一多客户端就卡（见性能诊断报告）。只新建「新出现的牌」，旧牌原地更新。
	var 旧: Dictionary = {}
	for c: Node in HandArea.get_children():
		var 旧卡: GCard = c.get("card") as GCard
		if 旧卡 != null:
			旧[旧卡.id] = c
	var 张数: int = Data.hand_cards.size()
	var 排布: Array = _单行间距与起点(maxi(张数, 1), HandArea.size.x, 手牌尺寸, 手牌最多重叠比例)
	var 间距: float = float(排布[0])
	var 起点: float = float(排布[1])
	var 现在: int = Time.get_ticks_msec()
	var 还在手: Array[int] = []
	for i: int in range(张数):
		var card: GCard = Data.hand_cards[i]
		还在手.append(card.id)
		var 可用: bool = _卡牌能点(card.id)
		var go: Node = 旧.get(card.id)
		var 是新建: bool = go == null
		if 是新建:
			# 这一轮才补进来的牌：记下起算时刻，接下来按「已经过多久」往下落
			if not _上次手牌.has(card.id) and not _补牌起点.has(card.id):
				_补牌起点[card.id] = 现在
			go = _加卡牌(HandArea, card, 手牌尺寸, 可用)
		else:
			旧.erase(card.id)
			# 复用节点也要按最新的可用性重画（省去重新实例化）
			go.call("设置卡牌", card, 可用, true)
			go.call("设置发光色", 可选发光_红 if _正在弃牌() else 可选发光_绿)
		HandArea.move_child(go, i)
		var 选中: bool = _sel_cards.has(card.id)
		go.call("设置选中", 选中)
		var ctl: Control = go as Control
		# 选中的牌往上抽出一截：表示「已经拿出来，等你按确定」
		var 上浮: float = 选中上浮像素 if 选中 else 0.0
		var 目标y: float = (HandArea.size.y - 手牌尺寸.y) * 0.5 - 上浮
		ctl.position = Vector2(起点 + 间距 * float(i), 目标y)
		if 是新建:
			# 只有新补的牌才从高处落下（复用/重画不重播这个动画）
			var 落高: float = _补牌落高(card.id, 现在)
			if 落高 > 0.0:
				ctl.position.y = 目标y - 落高
				var 剩余: float = maxf(补牌落下时长 * (1.0 - _补牌进度(card.id, 现在)), 0.05)
				var t: Tween = ctl.create_tween()
				t.tween_property(ctl, "position:y", 目标y, 剩余).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	for 废弃: Variant in 旧.values():
		(废弃 as Node).queue_free()
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
	# 与手牌一样复用节点：盖牌没变时不重建（每份快照都重建同样很重）
	var 旧: Dictionary = {}
	for c: Node in ChooseArea.get_children():
		var 旧卡: GCard = c.get("card") as GCard
		if 旧卡 != null:
			旧[旧卡.id] = c
	var 张数: int = 0
	for cc: GCard in Data.cover_cards:
		if cc != null:
			张数 += 1
	if 张数 == 0:
		for 废弃: Variant in 旧.values():
			(废弃 as Node).queue_free()
		ChooseArea.visible = false
		return
	# 盖牌区里的牌比手牌小一档（见 盖牌显示缩放）：整行更容易挤进 ChooseArea，也不至于压到别处
	var 尺寸: Vector2 = 盖牌尺寸 * 盖牌显示缩放
	var 间距: float = 盖牌间距
	if 张数 > 1:
		间距 = clampf((ChooseArea.size.x - 尺寸.x * float(张数)) / float(张数 - 1),
			-尺寸.x * 手牌最多重叠比例, 盖牌间距)
	var 总宽: float = 尺寸.x * float(张数) + 间距 * float(张数 - 1)
	var 序: int = 0
	for cc: GCard in Data.cover_cards:
		if cc == null:
			continue
		var 可点: bool = _selecting_cover and _卡牌能点(cc.id)
		# 只是「点盖牌按钮查看」时一律保持原色（只读、不给点，但牌面要看得清）；
		# 只有在「要选盖牌」的询问里选不了的那几张才置灰
		var go: Node = 旧.get(cc.id)
		if go == null:
			go = _加卡牌(ChooseArea, cc, 尺寸, 可点, _selecting_cover)
		else:
			旧.erase(cc.id)
			var 复: Control = go as Control
			复.custom_minimum_size = 尺寸
			复.size = 尺寸
			go.call("设置卡牌", cc, 可点, _selecting_cover)
			go.call("设置发光色", 可选发光_红 if _正在弃牌() else 可选发光_绿)
		ChooseArea.move_child(go, 序)
		if go is Control:
			(go as Control).position = Vector2(
				(ChooseArea.size.x - 总宽) * 0.5 + float(序) * (尺寸.x + 间距),
				(ChooseArea.size.y - 尺寸.y) * 0.5 + 盖牌显示下移)
		go.call("设置选中", _sel_cards.has(cc.id))
		序 += 1
	for 废弃: Variant in 旧.values():
		(废弃 as Node).queue_free()
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


## 当前这次选牌是不是「手牌 / 盖牌溢出、被迫弃牌」：只有这种才把「可选」发光框改成红光。
## 技能代价等主动弃牌（暗之障壁 / 充盈 / 被令弃牌…）不算溢出，仍用默认绿光。
func _正在弃牌() -> bool:
	if _mode != 2:
		return false
	var 应答号: int = int(_pending.get("respond_id", 0))
	if 应答号 != GConst.RespondType.Discard and 应答号 != GConst.RespondType.DiscardCover:
		return false
	# args = [目标, 原因, 张数]；只有溢出原因（CAUSE_OVERLOAD）才标红
	var 参数: Array = _pending.get("args", [])
	return 参数.size() > 1 and int(参数[1]) == GConst.CAUSE_OVERLOAD


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
		# 绿框＝还能选，黄框＝已经选中
		面板.设置已选中(_sel_players.has(pid))
	# 选中目标后顺带把提示画到他们头像上（配了「展示型」指示器的技能才有，如「给 X 张牌」「2 法术伤害」）
	_刷新头像提示()


## 当前正在操作的技能号（发动技能 mode 4 / 技能询问 mode 3），没有则 -1
func _当前技能号() -> int:
	if _mode == 4:
		return _pending_skill_id
	if _mode == 3:
		return _skill_ask_id
	return -1


## 「目标随牌」配置（技能指示器）：已选牌数达到该值时，才需要（且才允许）选 1 名目标
## （如【雷光散射】选超过 1 张雷系【充能】时才指定额外受伤的那名对手）。返回 0＝本技能没配这条规则
func _目标随牌阈值() -> int:
	var 技能号: int = _当前技能号()
	if 技能号 < 0:
		return 0
	return int(GConst.技能指示器.get(技能号, {}).get("目标随牌", 0))


## 「目标需法术牌」配置（技能指示器）：为 true 时必须先在已选牌里挑到一张法术牌，目标才可点
## （如吟游诗人【沉沦协奏曲】：弃的 2 张同系牌里得有法术牌，才有那 1 点法术伤害）
func _目标需法术牌() -> bool:
	var 技能号: int = _当前技能号()
	if 技能号 < 0:
		return false
	return bool(GConst.技能指示器.get(技能号, {}).get("目标需法术牌", false))


## 已选中的牌里有没有法术牌（【沉沦协奏曲】的头像提示与「目标需法术牌」共用）
func _已选牌含法术() -> bool:
	for 牌id: int in _sel_cards:
		var 牌: GCard = Data.get_card(牌id)
		if 牌 != null and 牌.is_magic():
			return true
	return false


## 当前技能的「展示型」指示器配置（配了「文案」/「分目标」/「自身」才算）：选中目标后把一句话画到他们头像上
## （只配「自身」的如【血之哀伤】：那句永远画在自己头像上，不看有没有选目标）。
## 分配型由 _刷新治疗分配 自己画，不走这里。发动技能（mode 4）与技能询问（mode 3）两条通道都认。
## 「选项提示」型的技能按二级技能栏里选定的效果取对应那份子配置（如【百鬼夜行】展示 / 不展示各一套）
func _头像提示配置() -> Dictionary:
	var 技能号: int = _当前技能号()
	if 技能号 < 0:
		return {}
	# 【沉沦协奏曲】那句「1 法术伤害」是有条件的（弃牌里得有法术牌），交给 _沉沦协奏曲头像提示 现算；
	# 这里不出静态配置，免得没挑到法术牌时也照画一句
	if 技能号 == GConst.技能_沉沦协奏曲:
		return {}
	var 配置: Dictionary = GConst.技能指示器.get(技能号, {})
	# 「先弹选项」型还没在二级技能栏里选效果时不画任何头像提示
	if bool(配置.get("先弹选项", false)) and _已选参数.is_empty():
		return {}
	var 分效果: Dictionary = 配置.get("选项提示", {})
	if not 分效果.is_empty():
		if _已选参数.is_empty():
			return {}
		return 分效果.get(int(_已选参数[0]), {})
	return 配置 if 配置.has("文案") or 配置.has("分目标") or 配置.has("自身") else {}


## 一句展示提示的最终数值：先取它自己的固定值（「每目标」或「总数 ÷ 选中人数」），
## 再由 _提示数值 按「每牌 / 每能量」现算
func _显示数值(配置: Dictionary) -> int:
	var 固定: int = int(配置.get("每目标", 0))
	if 固定 <= 0:
		# 「总数 ÷ 选中人数」本来就要整数（每人几颗），显式忽略整数除法警告
		@warning_ignore("integer_division")
		固定 = int(配置.get("总数", 0)) / maxi(_sel_players.size(), 1)
	return _提示数值(配置, 固定)


## 展示型提示的数值，按配置挑一种算法：
##   每牌   —— 每牌 × 已选牌数 + 偏移（如【魔道法典】伤害＝弃牌数 - 1）；一张牌都没选时无意义，按 0 处理。
##              再配「加参数」＝把二级技能栏里选定的效果值也算进来（如【死亡之触】伤害＝消耗治疗 + 弃牌数 - 3）
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
	if 动态提示.is_empty():
		动态提示 = _雷光散射头像提示()
	if 动态提示.is_empty():
		动态提示 = _魔眼头像提示()
	if 动态提示.is_empty():
		动态提示 = _灵魂镜像头像提示()
	if 动态提示.is_empty():
		动态提示 = _灵魂震爆头像提示()
	if 动态提示.is_empty():
		动态提示 = _灵魂赐予头像提示()
	if 动态提示.is_empty():
		动态提示 = _魔纹融合头像提示()
	if 动态提示.is_empty():
		动态提示 = _战纹碎击头像提示()
	if 动态提示.is_empty():
		动态提示 = _双重回响头像提示()
	if 动态提示.is_empty():
		动态提示 = _多重射击头像提示()
	if 动态提示.is_empty():
		动态提示 = _血之悲鸣头像提示()
	if 动态提示.is_empty():
		动态提示 = _杀戮盛宴头像提示()
	if 动态提示.is_empty():
		动态提示 = _禁断之力头像提示()
	if 动态提示.is_empty():
		动态提示 = _英灵召唤头像提示()
	if 动态提示.is_empty():
		动态提示 = _军神威光头像提示()
	if 动态提示.is_empty():
		动态提示 = _攻击加成头像提示()
	if 动态提示.is_empty():
		动态提示 = _天火断空头像提示()
	if 动态提示.is_empty():
		动态提示 = _末日审判头像提示()
	if 动态提示.is_empty():
		动态提示 = _朝圣头像提示()
	if 动态提示.is_empty():
		动态提示 = _沉沦协奏曲头像提示()
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


## 魔弓【雷光散射】的指示器（现算，写不进静态表 —— 要画在「所有敌方」而不是选中的目标身上）：
## 每名对手各 1 点法术伤害；已选雷系【充能】超过 1 张时，被指定的那名对手改为受「已选张数」点
func _雷光散射头像提示() -> Dictionary:
	var out: Dictionary = {}
	if _mode != 4 or _pending_skill_id != GConst.技能_雷光散射:
		return out
	var 张数: int = _sel_cards.size()
	var 指定: int = int(_sel_players[0]) if not _sel_players.is_empty() else -1
	for 面板: 战斗玩家面板 in _面板列表:
		if 面板.ID < 0:
			continue
		# 只画在合法目标（敌方）身上；服务端的合法目标白名单写在技能声明里
		if not (_skill_targets.is_empty() or _skill_targets.has(面板.ID)):
			continue
		out[面板.ID] = "%d 法术伤害" % (张数 if (面板.ID == 指定 and 张数 > 1) else 1)
	return out


## 魔弓【魔眼】的指示器（现算，只在发动它那次 mode 4 的界面画）：
## 只有二级技能栏里选了「指定一名角色弃 1 张牌」那一项、并且真点了某名角色时，
## 才在那名角色头像上写「弃 1 张牌」；选「自己摸 3 张牌」或还没点目标时谁都不写
func _魔眼头像提示() -> Dictionary:
	var out: Dictionary = {}
	if _mode != 4 or _pending_skill_id != GConst.技能_魔眼:
		return out
	if _已选参数.is_empty() or int(_已选参数[0]) != 1 or _sel_players.is_empty():
		return out
	out[int(_sel_players[0])] = "弃 1 张牌"
	return out


## 【魔纹融合】二级技能栏里选项值的基准：值 1＝【怒火压制】（不弃牌），值 2+Y＝【魔纹融合】
## （额外翻转 Y 个【魔纹】）。与服务端 role_yinglingrenxing.gd 的 CHOICE_MO_WEN_RONG_HE 对应
const 魔纹融合_选项基准: int = 2


## 英灵人形【魔纹融合】的指示器（现算，写不进静态指示器表）：
## 伤害＝弃牌数 - 1 + 额外翻转数，随玩家选 / 退牌实时变；画在这次攻击的目标头像上
## （这次询问问的是「自己弃几张」，目标不由玩家点选，故用服务端下发的 _skill_targets，
##  而不是自己点出来的 _sel_players）。选了【怒火压制】那一档不造成伤害，什么都不画
func _魔纹融合头像提示() -> Dictionary:
	var out: Dictionary = {}
	if _mode != 3 or _skill_ask_id != GConst.技能_魔纹融合 or _已选参数.is_empty():
		return out
	var 额外翻转: int = int(_已选参数[0]) - 魔纹融合_选项基准
	if 额外翻转 < 0 or _skill_targets.is_empty():
		return out
	var 伤害: int = _sel_cards.size() - 1 + 额外翻转
	if 伤害 <= 0:
		return out
	for 目标id: int in _skill_targets:
		out[目标id] = "%d 法术伤害" % 伤害
	return out


## 英灵人形【战纹碎击】的指示器（现算，写不进静态指示器表）：
## 伤害＝本次攻击原本的伤害 + 弃牌加伤（张数 - 1）+ 额外翻转数，随玩家选 / 退牌实时变；
## 画在这次攻击的目标头像上（这次询问问的是「弃几张」，目标不由玩家点选，故用服务端下发的 _skill_targets）。
## 原本的伤害只有服务端算得出来，随询问下发（preview_base）；还没选效果时按不额外翻转算
## 有加伤时写两行（学【灵力崩解】）：上行原伤害划掉（行首 [zwj]）、下行加上后的伤害
func _战纹碎击头像提示() -> Dictionary:
	var out: Dictionary = {}
	if _mode != 3 or _skill_ask_id != GConst.技能_战纹碎击 or _skill_targets.is_empty():
		return out
	# 选项值 = 1 + Y：值 1 是不额外翻转（Y = 0）；还没选效果时也按不额外翻转算
	var 额外翻转: int = int(_已选参数[0]) - 1 if not _已选参数.is_empty() else 0
	# 弃牌加伤那部分是「张数 - 1」，还没选够 2 张时按 0 算（此时显示的就是原本的伤害）
	var 原伤害: int = int(_pending.get("preview_base", 0))
	var 加伤: int = maxi(_sel_cards.size() - 1, 0) + 额外翻转
	if 原伤害 <= 0:
		return out
	for 目标id: int in _skill_targets:
		if 加伤 == 0:
			out[目标id] = "%d 攻击伤害" % 原伤害
		else:
			out[目标id] = "[zwj]%d 攻击伤害\n%d 攻击伤害" % [原伤害, 原伤害 + 加伤]
	return out


## 英灵人形【双重回响】的指示器（现算，写不进静态指示器表）：
## 伤害＝本次伤害点数与 3 取小，画在玩家点选的那名目标头像上（这次询问就是让他点一个目标）
func _双重回响头像提示() -> Dictionary:
	var out: Dictionary = {}
	if _mode != 3 or _skill_ask_id != GConst.技能_双重回响 or _sel_players.is_empty():
		return out
	# 伤害值随询问下发（preview_base），客户端不重复算「与 3 取小」
	var 伤害: int = int(_pending.get("preview_base", 0))
	if 伤害 <= 0:
		return out
	for 目标id: int in _sel_players:
		out[int(目标id)] = "%d 法术伤害" % 伤害
	return out


## 魔弓【多重射击】的指示器（现算）：这次额外攻击是暗系、伤害 -1，
## 所以在点选的敌人头像上写「本次攻击伤害」＝主动攻击基础 − 多重射击减伤。
## 目标由玩家在这次询问里点选，故用 _sel_players（不是服务端那张合法目标白名单）。
func _多重射击头像提示() -> Dictionary:
	var out: Dictionary = {}
	if _mode != 3 or _skill_ask_id != GConst.技能_多重射击 or _sel_players.is_empty():
		return out
	var 伤害: int = BattleEngine.ATTACK_BASE_POINT - GConst.多重射击减伤
	for 目标id: int in _sel_players:
		out[int(目标id)] = "%d 攻击伤害" % 伤害
	return out


## 血之巫女【血之悲鸣】的指示器（现算，数值就是选中的那一档）：
## 对目标与自己各造成「所选点数」法术伤害 —— 自己那句一选好档位就画在自己头像上，
## 目标那句等选好目标再画到目标头像上（两边同一个数）。
## 目标选的就是自己时，两下都落在自己身上，自己头像上写两行
func _血之悲鸣头像提示() -> Dictionary:
	var out: Dictionary = {}
	if _mode != 4 or _pending_skill_id != GConst.技能_血之悲鸣 or _已选参数.is_empty():
		return out
	var 点数: int = int(_已选参数[0])
	if 点数 <= 0:
		return out
	var 句: String = "%d 法术伤害" % 点数
	out[Logic.my_player_id] = 句
	for 目标id: int in _sel_players:
		if int(目标id) == Logic.my_player_id:
			out[Logic.my_player_id] = "%s\n%s" % [句, 句]
		else:
			out[int(目标id)] = 句
	return out


## 红莲骑士【杀戮盛宴】的指示器（现算）：发动后这次攻击的伤害 +2，所以敌人头像上写
## 两行（学【灵力崩解】）——上行原伤害划掉（行首 [zwj]）、下行 +2 后的伤害
## （原伤害只有服务端算得出来，随询问下发 preview_base）；
## 自己还要吃 4 点法术伤害，那句写在自己头像上
func _杀戮盛宴头像提示() -> Dictionary:
	var out: Dictionary = {}
	if _mode != 3 or _skill_ask_id != GConst.技能_杀戮盛宴:
		return out
	var 原伤害: int = int(_pending.get("preview_base", 0))
	for 目标id: int in _skill_targets:
		if 原伤害 > 0:
			out[int(目标id)] = "[zwj]%d 物理伤害\n%d 物理伤害" % [原伤害, 原伤害 + 2]
		else:
			out[int(目标id)] = "%d 物理伤害" % (原伤害 + 2)
	out[Logic.my_player_id] = "4 法术伤害"
	return out


## 勇者【禁断之力】的指示器（现算，写不进静态指示器表）：命中后发动时弃牌加伤 ——
## 敌人头像写「本次攻击伤害」＝发动前伤害（已含怒吼等）+ 已选火系牌数；
## 弃了火系牌时写两行（学【灵力崩解】）：上行原伤害划掉（行首 [zwj]）、下行加上后的伤害。
## 自己头像写弃掉的火系牌会造成的等量法术伤害。数值随选 / 退牌实时变。
## 这次询问问的是「弃哪些牌」，目标不由玩家点选，故用服务端下发的 _skill_targets；
## 未命中那条（服务端不发 targets）谁都不画。
func _禁断之力头像提示() -> Dictionary:
	var out: Dictionary = {}
	if _mode != 3 or _skill_ask_id != GConst.技能_禁断之力 or _skill_targets.is_empty():
		return out
	var 火系数: int = 0
	for cid: int in _sel_cards:
		var 牌: GCard = Data.get_card(cid)
		if 牌 != null and 牌.element_enum() == GConst.CardElement.Fire:
			火系数 += 1
	var 原伤害: int = int(_pending.get("preview_base", 0))
	var 攻击伤害: int = 原伤害 + 火系数
	if 攻击伤害 > 0:
		for 目标id: int in _skill_targets:
			if 原伤害 > 0 and 火系数 > 0:
				out[int(目标id)] = "[zwj]%d 攻击伤害\n%d 攻击伤害" % [原伤害, 攻击伤害]
			else:
				out[int(目标id)] = "%d 攻击伤害" % 攻击伤害
	if 火系数 > 0:
		out[Logic.my_player_id] = "%d 法术伤害" % 火系数
	return out


## 女武神【军神威光】第 2 段（选移除哪几个星石 + 点一名角色 +X 治疗）：在点中的目标头像上写「X 治疗」。
## X ＝ 所选星石组合的星石数，与服务端共用 GConst.军神威光组合，客户端不必自己另立一张表
func _军神威光头像提示() -> Dictionary:
	var out: Dictionary = {}
	if _mode != 3 or _skill_ask_id != GConst.技能_军神威光:
		return out
	var 治疗量: int = GConst.军神威光治疗量(int(_已选参数[0]) if not _已选参数.is_empty() else 0)
	if 治疗量 <= 0:
		return out
	for pid: int in _sel_players:
		out[pid] = "%d 治疗" % 治疗量
	return out


## 女武神【英灵召唤】的指示器（现算）：自身攻击命中后询问「是否发动 + 弃不弃法术牌 + 治疗给谁」——
## 发动则本次攻击伤害 +1（服务端下发 preview_base＝原伤害、preview_ids＝本次攻击目标），
## 在攻击目标头像上写两行（学【灵力崩解】）：上行原伤害划掉（行首 [zwj]）、下行 +1 后的伤害。
## 治疗那行（额外弃 1 张法术牌后选中的角色 +1 治疗）照静态指示器画在选中的目标上
func _英灵召唤头像提示() -> Dictionary:
	var out: Dictionary = {}
	if _mode != 3 or _skill_ask_id != GConst.技能_英灵召唤:
		return out
	var 原伤害: int = int(_pending.get("preview_base", 0))
	for 目标id: Variant in _pending.get("preview_ids", []):
		var pid: int = int(目标id)
		if 原伤害 > 0:
			out[pid] = "[zwj]%d 攻击伤害\n%d 攻击伤害" % [原伤害, 原伤害 + 1]
		else:
			out[pid] = "%d 攻击伤害" % (原伤害 + 1)
	# 治疗那行：与静态指示器的「每目标 1 / 文案 %d 治疗」一致（选中的治疗目标才画）
	for pid2: int in _sel_players:
		var 治疗句: String = "1 治疗"
		if out.has(pid2):
			out[pid2] = "%s\n%s" % [out[pid2], 治疗句]
		else:
			out[pid2] = 治疗句
	return out


## 「攻击宣告阶段响应、会改变本次攻击伤害」的技能的指示器（现算，规则见 GConst.攻击提示加成）：
## 在目标头像上写「本次攻击伤害」＝基础伤害 + 技能加成。两种入口都算 ——
## 被询问时（技能询问）＝服务端随询问下发的发动前伤害；从技能栏点它发起攻击时（发动技能）
## ＝主动攻击基础伤害。如【怒吼】+2、【精准射击】-1、【血影狂刀】按目标手牌数算
## 有加成时写两行（学【灵力崩解】）：上行原伤害划掉（行首 [zwj]）、下行加上后的伤害。
## 特例：格斗在【百式幻龙拳】形态下发【蓄力一击】会脱离该形态（丢掉百式的 +2）——
## 划掉的那行写「保持百式」的伤害（4），下面是用了蓄力之后的伤害（3）
func _攻击加成头像提示() -> Dictionary:
	var out: Dictionary = {}
	var 技能号: int = _当前技能号()
	var 规则: Variant = GConst.攻击提示加成.get(技能号, null)
	if 规则 == null:
		return out
	# 格斗【蓄力一击 / 气绝崩击】共用一条二选一询问：只有选中【蓄力一击】那档才加这 1 点
	if 技能号 == GConst.技能_蓄力一击 and not _选中蓄力一击():
		return out
	var 基础: int = 0
	var 目标们: Array[int] = []
	if _mode == 3:
		基础 = int(_pending.get("preview_base", 0))
		for 目标id: int in _skill_targets:
			目标们.append(int(目标id))
	elif _mode == 4:
		基础 = BattleEngine.ATTACK_BASE_POINT
		for 目标id: int in _sel_players:
			目标们.append(int(目标id))
	else:
		return out
	# 角色被动（如狂战士【狂化】）对所有主动攻击都加成，与具体技能无关。
	# 它是「不发动本技能时就有的伤害」，并入划掉的那一行；只有本技能自己的加成才另起一行写新伤害
	var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
	var 被动: int = int(GConst.攻击提示角色加成.get(我.role_id, 0))
	# 格斗【蓄力一击】会脱离【百式幻龙拳】（主动攻击 +2）：这一下不是「只 +1」，而是先丢掉百式的 +2。
	# 于是划掉的那行写「保持百式」的伤害（基础 + 百式 +2），下面写用了【蓄力一击】之后的伤害（基础 +1）
	var 破百式: bool = 技能号 == GConst.技能_蓄力一击 \
			and 我.role_id == GConst.角色_格斗 and 我.tap
	for 目标id: int in 目标们:
		var 原伤害: int = maxi(基础 + 被动, 0)
		var 加成: int = _攻击加成值(规则, 目标id)
		if 破百式:
			out[目标id] = "[zwj]%d 攻击伤害\n%d 攻击伤害" % [
				原伤害 + GConst.百式幻龙拳主动加成, maxi(原伤害 + 加成, 0)]
		elif 加成 > 0:
			# 加伤时划掉原值另起一行；减伤（如【精准射击】-1）维持原来的一行
			out[目标id] = "[zwj]%d 攻击伤害\n%d 攻击伤害" % [原伤害, 原伤害 + 加成]
		else:
			out[目标id] = "%d 攻击伤害" % maxi(原伤害 + 加成, 0)
	return out


## 蝶舞者【朝圣】的指示器（现算）：自己挨伤害时问要不要弃【茧】抵御 ——
## 头像选中自己并锁死（「自动选目标＝自己」，见 技能指示器 的 技能_朝圣），提示两行：
## 上面是本次受到的伤害（划掉）、下面是抵御 1 点之后的伤害。
## 措辞与颜色随本次伤害的类型走（法术＝洋红、攻击＝红，由 _提示上色 认关键词分色）；
## 两个数值只有服务端算得出来，随询问下发 preview_base（本次伤害）与 preview_kind（类型）
func _朝圣头像提示() -> Dictionary:
	var out: Dictionary = {}
	if _mode != 3 or _skill_ask_id != GConst.技能_朝圣:
		return out
	var 伤害: int = int(_pending.get("preview_base", 0))
	if 伤害 <= 0:
		return out
	var 词: String = "法术伤害" if int(_pending.get("preview_kind", 0)) == GConst.HarmType.Magic else "攻击伤害"
	# 【朝圣】抵御 1 点：下面那行就是本次伤害 - 1（最低 0）。
	# 第一行开头挂 [zwj] 当标记 —— 界面据此给它压一条删除线（见 _铺粗删除线）
	out[Logic.my_player_id] = "[zwj]%d 点%s\n%d 点%s" % [伤害, 词, maxi(伤害 - 1, 0), 词]
	return out


## 吟游诗人【沉沦协奏曲】的指示器（现算）：弃 2 张同系牌【展示】，其中要有【法术】牌，弃完才追加
## 那 1 点法术伤害（服务端同判，见 role_shiren.p_harm_end 的 is_magic 校验）——
## 所以没挑到法术牌时这行整条不画（静态指示器表那条也已在 _头像提示配置 里让开）。
## 文案与数值仍取静态指示器表（技能指示器的 文案 / 每目标），这里只负责「什么时候画」
func _沉沦协奏曲头像提示() -> Dictionary:
	var out: Dictionary = {}
	if _当前技能号() != GConst.技能_沉沦协奏曲:
		return out
	if not _已选牌含法术():
		return out
	var 配置: Dictionary = GConst.技能指示器.get(GConst.技能_沉沦协奏曲, {})
	for pid: int in _sel_players:
		out[pid] = str(配置.get("文案", "")) % int(配置.get("每目标", 1))
	return out


## 苍炎魔女【天火断空】的指示器（现算，写不进静态指示器表）：对目标角色与自己各造成法术伤害，
## 平时 GConst.天火断空基础伤害 点，但「目标的队伍士气 > 自己的队伍士气」时 +1 —— 点数随双方当前士气现算。
## 目标那句写在他头像上，自己那句永远写在自己头像上（服务端两句用的是同一个点数）。
## 触发 +1 时写两行（学【灵力崩解】）：上行原伤害划掉（行首 [zwj]）、下行加伤后的伤害
func _天火断空头像提示() -> Dictionary:
	var out: Dictionary = {}
	if _mode != 4 or _pending_skill_id != GConst.技能_天火断空:
		return out
	var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
	if 我 == null:
		return out
	var 我方士气: int = Data.team_of(我.color).morale
	var 加伤: bool = false
	for 目标id: int in _sel_players:
		var 目标: GPlayer = Data.get_player_by_id(int(目标id))
		if 目标 != null and Data.team_of(目标.color).morale > 我方士气:
			加伤 = true
	var 文: String = "%d 法术伤害" % GConst.天火断空基础伤害
	if 加伤:
		文 = "[zwj]%d 法术伤害\n%d 法术伤害" % [
			GConst.天火断空基础伤害, GConst.天火断空基础伤害 + GConst.天火断空士气落后加成]
	for 目标id: int in _sel_players:
		out[int(目标id)] = 文
	out[Logic.my_player_id] = 文
	return out


## 仲裁者【末日审判】的指示器（现算，写不进静态指示器表）：移除自身全部【审判】，
## 对目标造成「当前【审判】数」点法术伤害 —— 点数随指示物变，选中目标时写在目标头像上。
## 【审判】是 tokens[0]（对应角色表的「0:审判:4」，见 _末日审判锁死行动）
func _末日审判头像提示() -> Dictionary:
	var out: Dictionary = {}
	if _mode != 4 or _pending_skill_id != GConst.技能_末日审判 or _sel_players.is_empty():
		return out
	var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
	if 我 == null or 我.tokens.is_empty():
		return out
	var t: GPlayer.Token = 我.tokens[0] as GPlayer.Token
	if t == null or t.num <= 0:
		return out
	for 目标id: int in _sel_players:
		out[int(目标id)] = "%d 法术伤害" % t.num
	return out


## 本技能对某名目标的实际加成（规则见 GConst.攻击提示加成 的取值说明）
func _攻击加成值(规则: Variant, 目标id: int) -> int:
	if 规则 is int:
		return int(规则)
	# "目标手牌"：【血影狂刀】目标手牌 2 张 +2、3 张 +1，其余张数不加
	var 目标: GPlayer = Data.get_player_by_id(目标id)
	if 目标 == null:
		return 0
	# 客户端玩家视图只有手牌「张数」（hand_cards_num），没有服务端那套 hand_count()
	var 张数: int = 目标.hand_cards_num
	if 张数 == 2:
		return 2
	if 张数 == 3:
		return 1
	return 0


## 格斗的加成询问里，当前要发动的（二级技能栏选中的 / 技能栏点的 / 单项直接问的）是不是【蓄力一击】
## （选【气绝崩击】、或直接问【气绝崩击】时不改伤害，不画攻击伤害提示）
func _选中蓄力一击() -> bool:
	if _mode == 4:
		return _pending_skill_id == GConst.技能_蓄力一击
	# 只有一个可发动时走「一问一答」，这次询问没有选项：问的就是【蓄力一击】自己
	if _二级选项.is_empty():
		return _skill_ask_id == GConst.技能_蓄力一击
	return int(_二级选中项().get("技能号", 0)) == GConst.技能_蓄力一击


## 灵魂术士【灵魂镜像】的指示器（现算）：在选中的目标头像上写他「会摸几张」——
## 摸牌数被他的手牌上限卡住，目标是自己的话还随「弃几张」变动，写不进静态指示器表
func _灵魂镜像头像提示() -> Dictionary:
	var out: Dictionary = {}
	if _mode != 4 or _pending_skill_id != GConst.技能_灵魂镜像 or _sel_players.is_empty():
		return out
	for 目标id: int in _sel_players:
		var 目标: GPlayer = Data.get_player_by_id(目标id)
		if 目标 == null:
			continue
		out[目标id] = "摸 %d 张牌" % _灵魂镜像摸牌数(目标)
	return out


## 【灵魂镜像】会让这名目标摸几张：最多 GConst.灵魂镜像张数 张、且不超他的手牌上限；
## 目标是自己时先弃掉已选的牌再摸，按弃牌后的手牌数算（与服务端 LingHun::_jing_xiang 一致）
func _灵魂镜像摸牌数(目标: GPlayer) -> int:
	# 手牌数用 hand_cards_num：别人的手牌内容不下发，只有这个数量是准的
	var 现有: int = 目标.hand_cards_num
	if 目标.id == Logic.my_player_id:
		现有 -= mini(_sel_cards.size(), GConst.灵魂镜像张数)
	return GConst.灵魂镜像摸牌数(现有, 目标.hand_cards_max)


## 灵魂术士【灵魂震爆】的指示器（现算）：在选中的目标头像上写他「会挨几点法术伤害」——
## 目标手牌少于 3 张、且手牌上限高于 5 时是 5 点，否则 3 点，写不进静态指示器表
func _灵魂震爆头像提示() -> Dictionary:
	var out: Dictionary = {}
	if _mode != 4 or _pending_skill_id != GConst.技能_灵魂震爆 or _sel_players.is_empty():
		return out
	for 目标id: int in _sel_players:
		var 目标: GPlayer = Data.get_player_by_id(目标id)
		if 目标 == null:
			continue
		out[目标id] = "%d 法术伤害" % GConst.灵魂震爆伤害(目标.hand_cards_num, 目标.hand_cards_max)
	return out


## 灵魂术士【灵魂赐予】的指示器：在选中的目标头像上写「N 宝石」，告诉玩家会给他多少宝石
func _灵魂赐予头像提示() -> Dictionary:
	var out: Dictionary = {}
	if _mode != 4 or _pending_skill_id != GConst.技能_灵魂赐予 or _sel_players.is_empty():
		return out
	for 目标id: int in _sel_players:
		if Data.get_player_by_id(目标id) == null:
			continue
		out[目标id] = "%d 宝石" % GConst.灵魂赐予宝石
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
	# 「目标需法术牌」型（如【沉沦协奏曲】）：已选牌里没挑到法术牌时本来就没那 1 点伤害，
	# 这时不必选目标（选 0 名也能点「确定」）
	if _目标需法术牌() and not _已选牌含法术():
		return true
	# 「目标随牌」的技能（如【雷光散射】）：够阈值必须正好 1 名目标，不够则一名也不选
	var 随牌阈值: int = _目标随牌阈值()
	if 随牌阈值 > 0:
		return _sel_players.size() == (1 if _sel_cards.size() >= 随牌阈值 else 0)
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


## 参数选项各自目标白名单：已经选定某个选项时就只按那一项自己的白名单
## （如【神圣领域】选了「打敌人」就只点敌人）；还没选（或那一项没带白名单）就退回所有选项的并集
func _参数选项目标白名单() -> Array:
	var 选中项: Dictionary = _二级选中项()
	if not 选中项.is_empty():
		var 单选: Array = 选中项.get("目标白名单", [])
		if not 单选.is_empty():
			return 单选
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
			if not (_是敌方(player_id) and not _潜行中(player_id)):
				return false
			# 我面前有【挑衅】时，本回合必须且只能主动攻击「放挑衅的那个玩家」（对照卡表【挑衅】；
			# 服务端 base_v_attack 同样校验，这里把其余敌人置灰，别让玩家白点）
			var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
			if 我 != null and 我.get_special(GConst.Exclusive.TiaoXin):
				return player_id == 我.get_special_from(GConst.Exclusive.TiaoXin)
			return true
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
		# 「目标随牌」的技能（如女武神【英灵召唤】：弃了法术牌才给治疗）：没选够牌时谁都不亮、点不动
		# （取消牌后 _on_card_clicked 会再问一次 _玩家可选，把已点的目标一并清掉）
		var 随牌阈值: int = _目标随牌阈值()
		if 随牌阈值 > 0 and _sel_cards.size() < 随牌阈值:
			return false
		# 「目标需法术牌」型（如【沉沦协奏曲】）：弃的牌里还没挑到法术牌时谁都不亮、点不动
		if _目标需法术牌() and not _已选牌含法术():
			return false
		if _skill_ask_need_target <= 0:
			return false
		# 参数选项带了各自的目标白名单时，按选中那一项（还没选就按并集）点亮 ——
		# 如吟游诗人【希望赋格曲】的「放置」不含自己、「转移」含自己
		var 选项白名单: Array = _参数选项目标白名单()
		if not 选项白名单.is_empty():
			return 选项白名单.has(player_id)
		# 服务端给了合法目标就只让这几名玩家亮（如【天使之歌】只能选面前有基础效果的人）
		return _skill_targets.is_empty() or _skill_targets.has(player_id)
	if _mode == 4:
		# 「先弹选项」型：还没选用法时不让点目标（如神官【神圣领域】：用法决定打队友还是打敌人、
		# 目标白名单也不同）。选了某项后 _已选参数 才有值，这时才按它的白名单点亮
		if _先弹选项 and _已选参数.is_empty():
			return false
		if bool(_分配配置().get("仅队友", false)) and not _是队友(player_id):
			return false
		# 「目标随牌」的技能（如【雷光散射】）：已选牌数够阈值时才点亮目标（选 1 张时不选目标）
		var 随牌阈值: int = _目标随牌阈值()
		if 随牌阈值 > 0:
			return _sel_cards.size() >= 随牌阈值 and (_skill_targets.is_empty() or _skill_targets.has(player_id))
		# 「目标需法术牌」型（如【沉沦协奏曲】）：弃的牌里还没挑到法术牌时谁都不亮、点不动
		if _目标需法术牌() and not _已选牌含法术():
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
	# （购买 / 合成 / 提炼 哪个做不了，在二级技能栏里按项半透明、点不动，入口按钮不必再拦）
	BtnSpecila.disabled = not 特殊可用 or (_按钮是特殊行动() and _末日审判锁死行动())


func _确定不可用() -> bool:
	# 本地二级栏选项步骤（冒险者天堂选额外数 / 特殊行动选星石）：选好一项才让点「确定」
	# （冒险者天堂最后一步走 mode 3 的分配通道，确定＝分满才可用，见下面 _分配配置 那一段）
	if _本地选项阶段 > 0:
		# 常规提炼：自己星石满了就提炼不出来，列表照摆但「确定」置灰
		if _本地选项阶段 == 2 and _待定特殊行动 == GConst.SpecialAction.Extract \
				and not _提炼是冒险家流程:
			var 我: GPlayer = Data.get_player_by_id(Logic.my_player_id)
			if 我 != null and 我.get_energy() >= 我.energy_max:
				return true
		return _二级选中 < 0
	if _mode == 1:
		# 不可行动：手牌要全弃掉换 4 张，只等玩家点「确定」
		if _不可行动:
			return false
		# 【圣盾】【虚弱】【中毒】：目标只能点人头像来定（点谁就施加给谁，点自己头像＝施加给自己）。
		# 不给目标提交时服务端默认就是对自己施放，按「确定」会误把自己当成目标 —— 所以直接灰掉，
		# 不再允许「按确定给自己施加效果」
		if _选中是点头像定目标的牌():
			return true
		return _sel_cards.is_empty() and _sel_players.is_empty()
	if _mode == 3:
		# 单份额外行动（如【迅捷赐福】/【风怒追击】）：确定＝发动它；引擎判「不能发动」时置灰
		if _额外行动单选 >= 0:
			return not _额外行动可选
		# 分配型指示器（如冰霜祷言）：选够治疗点、且要选牌时选够牌才让「确定」
		if not _分配配置().is_empty():
			var 治疗牌够: bool = _sel_cards.size() >= _skill_ask_need_card if _skill_ask_need_card > 0 else true
			if not (治疗牌够 and _分配已满()):
				return true
			# 分配到的目标也必须还在当前用法的白名单里（换了用法后可能已不合法）
			for pid: int in _治疗分配:
				if not _玩家可选(pid):
					return true
			return false
		if not _是技能询问:
			return true
		# need_card 是「最少要选几张」，点选上限另由 _skill_card_max 管（如【法术反弹】可弃 1~N 张同系牌），
		# 所以这里用 ≥ 而不是 ==，否则多选了反而点不动「确定」
		var 牌够: bool = _sel_cards.size() >= _skill_ask_need_card if _skill_ask_need_card > 0 else true
		# 「目标需法术牌」型（如【沉沦协奏曲】）：没挑到法术牌时本来就没那 1 点伤害，不必选目标；
		# 挑到了就必须选目标（按服务端给的需求数判）。注意这里不能直接借 _目标数合法() ——
		# 那个函数读的是发动技能通道的 _skill_need_target，与询问通道的 _skill_ask_need_target 不是一回事
		var 免选目标: bool = _目标需法术牌() and not _已选牌含法术()
		# 目标数：「目标随牌」的技能（如女武神【英灵召唤】：弃了法术牌才给治疗）随已选牌数现算 ——
		# 没弃牌就一个人都不用选、弃了就必须正好选 1 名（见 _目标数合法）；其余按服务端给的需求数
		var 目标够: bool = 免选目标 or (_目标数合法() if _目标随牌阈值() > 0 \
			else (_sel_players.size() >= _skill_ask_need_target if _skill_ask_need_target > 0 else true))
		# 二级技能栏：先在技能栏里选一个效果，再选够牌 / 目标，才让点「确定」
		if _二级栏:
			return not (牌够 and 目标够 and _二级选中 >= 0)
		return not (牌够 and 目标够)
	if _mode == 4:
		# 分配型指示器（如圣疗 / 治愈之光 / 治疗术 / 神圣领域）：选够治疗点、且要选牌时选够牌才让「确定」
		if not _分配配置().is_empty():
			var 治疗牌够: bool = _sel_cards.size() >= _skill_need_card if _skill_need_card > 0 else true
			if not (治疗牌够 and _分配已满()):
				return true
			# 分配到的目标也必须还在当前用法的白名单里（换了用法后可能已不合法）
			for pid: int in _治疗分配:
				if not _玩家可选(pid):
					return true
			return false
		# 二级技能栏：得先在技能栏里选一个效果，且选够它要求的牌 / 目标，才让点「确定」
		# （「先弹选项」型的需牌 / 目标已在选效果时由 _应用选项目标数 还原 / 收紧）
		if _二级栏:
			var 项: Dictionary = _二级选中项()
			if 项.is_empty():
				return true
			var 需牌: int = maxi(_skill_need_card, int(项["需牌"]))
			var 需目标: int = maxi(_skill_need_target, int(项["需目标"]))
			# 手牌+盖牌混选的项（如【倒逆之蝶】第 ② 项：2 张手牌 + 2 张【茧】）还要数够盖牌张数
			var 盖选中: int = 0
			for c: Variant in _sel_cards:
				if _is_my_cover(int(c)):
					盖选中 += 1
			# 不叫「牌够」：同一个函数后面另有一个 牌够，重名会触发 CONFUSABLE_LOCAL_DECLARATION
			var 本项牌够: bool = _sel_cards.size() >= 需牌 if 需牌 > 0 else true
			if _skill_cover_need > 0 and 盖选中 < _skill_cover_need:
				本项牌够 = false
			var 目标够: bool = _sel_players.size() >= 需目标 if 需目标 > 0 else true
			return not (本项牌够 and 目标够 and _目标在白名单(项["目标白名单"]) and _目标数合法())
		# 手牌 + 盖牌混选型（如【魔贯冲击】：1 张攻击牌 + 1 张火系【充能】）：
		# 分别校验手牌数与盖牌数，不能只数总张数（否则选两张手牌也能按「确定」，提交后才被服务端拒）
		if _skill_cover_need > 0:
			var 盖选中: int = 0
			for c: Variant in _sel_cards:
				if _is_my_cover(int(c)):
					盖选中 += 1
			var 手选中: int = _sel_cards.size() - 盖选中
			if 手选中 < _skill_need_card - _skill_cover_need or 盖选中 < _skill_cover_need:
				return true
			return not _目标数合法()
		# 需牌是最少张数（如【暗影流星】要弃 2 张、【欺诈】要弃 2 张），选够才让点「确定」
		# need_card==0 表示「一张都不选也可以」（如【灵魂镜像】最多弃 GConst.灵魂镜像张数 张、也可不弃），
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
## 本阶段不放行特殊行动时不show：额外行动阶段只放行它声明的种类（如【偷天换日】给的是
## 「攻击/法术行动」，见 GConst.放行动作），被【挑衅】时也只放行攻击，都不该出现特殊行动按钮
func _按钮是特殊行动() -> bool:
	return _mode == 1 and not _行动禁特殊 and GConst.放行动作(GConst.ActionType.Special, _行动允许)


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
	if _mode == 4 or _mode == 6:
		return true
	if _mode == 2:
		var rid: int = int(_pending.get("respond_id", 0))
		return rid == GConst.RespondType.ReplyAttack \
			or rid == GConst.RespondType.Bullet \
			or rid == GConst.RespondType.Weaken \
			or rid == GConst.RespondType.Heal
	return false


# ---------------- 技能区 ----------------
func _显示技能区() -> void:
	SkillArea.visible = true
	ChildrenSkillArea.visible = true


func _隐藏技能区() -> void:
	SkillArea.visible = false
	ChildrenSkillArea.visible = false
	# 技能区一收，说明框也跟着收（技能按钮多半马上就被清掉了，收不到 mouse_exited）
	_收起所有说明()


## 点中的技能按钮亮起黄色外发光，其余熄灭。
## 取消 / 提交行动都会 _清空技能按钮（或重建），发光随之复位，不用额外清；
## 二级技能栏里被点的父技能也保持发光（见 _进入二级技能栏）。
func _标记选中技能(按钮: Node) -> void:
	for b: Node in _技能按钮:
		if b is 技能按钮:
			(b as 技能按钮).设置选中(b == 按钮)


func _清空技能按钮() -> void:
	# 二级技能栏的选项按钮也登记在 _技能按钮 里，先按二级栏那本账把它们摘掉
	_清空二级选项()
	for b: Node in _技能按钮:
		if is_instance_valid(b):
			b.queue_free()
	_技能按钮.clear()
	_隐藏技能区()
