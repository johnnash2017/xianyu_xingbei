class_name ProtoSchema
extends RefCounted
## 协议字段表
## 只描述「协议号 → 字段号 → 字段类型」，供 ProtoCodec 通用编解码。
## 类型取值：i32/u32/i64/u64/bool/enum（变长整数）、str/bytes/msg（长度定界）
## 字段定义：{ "n": 字段名, "t": 类型, "r": 可选，repeated, "s": 可选，msg 的子消息名 }

## 玩家信息字段表：SinglePlayerInfo 子消息与 SinglePlayer 独立消息共用同一份，
## 避免两处各写一份、改一处漏一处导致字段漂移。
const PLAYER_INFO_FIELDS: Dictionary = {
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
	# 这一路的往返延迟（毫秒，服务端心跳测出）：游戏内「玩家列表」右侧显示连接质量
	26: {"n": "ping", "t": "u32"},
	# 盖牌上限（角色表「指示物」列槽 2 的上限）：客户端「查看盖牌」时按它摆出空槽，
	# 让玩家看见自己最多能放几张（0＝这个角色没有盖牌区）
	27: {"n": "max_covered", "t": "u32"},
	# 血色剑灵【血蔷薇庭院】独立状态（不是横置形态）：客户端据此在状态图标区画庭院图标
	28: {"n": "xue_qiang_wei", "t": "bool"},
	# 圣弓专属技正反面：0=【圣煌辉光炮】、1=【圣煌余辉】、2=已移除。
	# 客户端按角色号 37 过滤，只有圣弓会画这个状态图标。
	29: {"n": "sheng_huang_side", "t": "u32"},
	# 梦想剑 4503 当前档位（0=未启用 / 1 / 2 / 3）：客户端角色说明据此逐段标绿
	30: {"n": "dream_tier", "t": "u32"},
	# 本回合「下一次主动攻击只能攻击这名玩家」（0＝无限制）：剑之子【剑残影】10804 的回合级标记。
	# 服务端在 base_v_attack 里按它拒掉别的目标；客户端据此把其余敌方头像置灰。
	# 必须随快照下发，否则客户端只能等提交后被驳回（玩家会以为点了没反应）。
	31: {"n": "attack_lock", "t": "u32"},
	# 盖牌区里**面朝上**的牌（所有人可见）：结界师【结界】这种“放在角色旁、牌面公开”的旁置牌。
	# 面朝下的盖牌照旧只下发张数（covered_count），这里只列公开的那几张的牌面。
	32: {"n": "cover_opens", "t": "u32", "r": true},
	# 【律法】（星坠女巫）：放在角色面前的律法标记（0/1/2/3 由角色定义），客户端在状态区显示名字。
	33: {"n": "laws", "t": "u32", "r": true},
	# 本人手牌每张牌的当前系别（与 hands 一一对应）：
	# 魔刃/异刃这类可切换系别的牌，重连/换手后要按服务端当前状态恢复卡面与元素图标
	34: {"n": "hand_elements", "t": "u32", "r": true},
	# 公开信息：该玩家手牌里的魔刃/异刃（1005/1006）。客户端在头像旁显示状态图标和名字，
	# 让所有玩家知道「他手里有一张魔刃/异刃」；具体手牌内容仍不公开。
	35: {"n": "hand_blades", "t": "u32", "r": true},
}

## 子消息字段表（作为 msg 类型的 schema）
const SUB: Dictionary = {
	"RoomInfo": {
		1: {"n": "room_id", "t": "i32"},
		2: {"n": "room_name", "t": "str"},
		3: {"n": "max_player", "t": "i32"},
		# 在线玩家数（对局中掉线的人座位还留着，不算进来）：房间列表显示「在线/上限」
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
		# 这间房里还留着「我」的座位吗（对局中退出/掉线后重进能直接坐回去）：房间列表据此显示「可重连」
		15: {"n": "can_reenter", "t": "bool"},
		# 已占座位数（含掉线保留的座位）：「满不满」看它（服务端也是按座位放人）
		16: {"n": "seat_count", "t": "i32"},
		# 观战者人数：房间列表单列一栏显示
		17: {"n": "watchers", "t": "u32"},
		# 房主建房时是否勾了「作弊」（调试模式）：房间列表只在开着时把这一段显示出来
		18: {"n": "debug", "t": "bool"},
		# 本房间开启的角色版本位掩码（角色表「版本」列；房间列表显示、选角/随机池过滤）
		19: {"n": "role_versions", "t": "u32"},
	},
	"SinglePlayerInfo": PLAYER_INFO_FIELDS,
	# 场卡（不属于任何人的手牌/盖牌，摆在场上或某人面前）：
	# 【异端裁决所】（圣庭检察士）/【末日预言】（异教徒）/【绝界】（结界师）都走这一份。
	# 只下发能让人看见的东西（计数、状态、隐藏牌堆张数），牌堆内容不下发。
	"FieldCard": {
		1: {"n": "id", "t": "str"},
		2: {"n": "owner", "t": "i32"},
		# 挂在谁面前（-1＝不挂人）：【绝界】用它在拥有者面板上显示
		3: {"n": "attached", "t": "i32"},
		4: {"n": "counter", "t": "u32"},
		5: {"n": "counter_max", "t": "u32"},
		# 0/1/2… 语义由角色定义（末日预言：0=正面 / 1=天雷劫火 / 2=地裂波涛）
		6: {"n": "state", "t": "u32"},
		# 隐藏牌堆（【预言】）的张数
		7: {"n": "pile_count", "t": "u32"},
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
		# 上面那个基准数值的「类型」（0＝没有），取 GConst.HarmType（1＝攻击、2＝法术）。
		# 客户端现算头像提示时用它定措辞与颜色，如蝶舞者【朝圣】要按本次伤害的类型写「法术伤害 / 攻击伤害」
		23: {"n": "preview_kind", "t": "u32"},
		# 带选项的询问里，每个选项各自的目标白名单（与 args 里的选项值一一对应，空＝这一项不限制）：
		# 如吟游诗人【希望赋格曲】二选一 —— 「放置」只能点除自己外的队友、「转移」可以点含自己在内的我方
		# （除当前持有者）。客户端选中该项后按它收紧可点头像（见 battle_mobile._参数选项目标白名单）
		24: {"n": "option_targets", "t": "msg", "r": true, "s": "OptionTargets"},
		# 现算头像提示要画在哪几名角色身上（0＝沿用 dst_ids）：
		# 当这条询问的「可点目标」与「要写提示的角色」不是同一批时用它 ——
		# 如女武神【英灵召唤】：可点目标是接受治疗的角色，而伤害 +1 要写在本次攻击的目标头像上
		25: {"n": "preview_ids", "t": "u32", "r": true},
		# 这条技能命令本次能不能用（false＝条件不满足）：界面照样把按钮摆出来，但半透明、点不动。
		# 省略＝可用（客户端按 true 处理）—— 所以只有真正不可用的那条才会把这个字段写上线
		26: {"n": "enabled", "t": "bool"},
		# 带选项的询问里，每项本次是否可用（与 args 里的选项值一一对应，省略＝都可用）。
		# 如魔纹融合在魔纹不够时的「额外翻转」档：按钮照样摆出来，但置灰点不动。
		27: {"n": "option_enabled", "t": "bool", "r": true},
		# 这条技能询问本次能不能用【圣光】抵挡（省略＝可以；false＝不能用，如式神咒束/一击无念）。
		# 少这一项，真实联机时客户端拿不到 false，会以为圣光还能点。
		28: {"n": "can_light", "t": "bool"},
		# 这条技能询问对应的本次攻击伤害（「受到 N 伤害攻击」用；省略＝没有）。
		29: {"n": "preview_damage", "t": "u32"},
		# 额外行动的来源 cause（如苍白之月 3507）；普通行动省略
		30: {"n": "extra_cause", "t": "u32"},
		# 带选项的询问里，每个选项各自对应的一张牌（与 args 里的选项值一一对应，0＝这一项不对应牌）：
		# >0 时客户端悬停该选项按钮直接摊这张牌的卡面（如【剑守誓言】的「选 1 张加入手牌」）。
		# 这个字段必须随网络下发，否则服务端把牌号塞进命令、客户端永远收不到，悬停只剩文字。
		31: {"n": "option_card_ids", "t": "u32", "r": true},
		# 带选项的询问里，每个选项各自要求选择几名目标（与 args 里的选项值一一对应，0＝不选目标）：
		# 如攻击结束二选一：剑残影要选 1 名目标、剑影*断念不选目标。客户端选中该项后据此放开/收紧目标。
		32: {"n": "option_need_targets", "t": "u32", "r": true},
		# 「这次询问里可用的额外攻击行动」cause 列表，**顺序就是显示顺序**（由引擎 额外行动序列 排好）：
		# 攻击结束响应里摆成红色快捷按钮（玩家点一个就放弃剩余响应、直接进入该额外攻击）；
		# 额外行动阶段的行动询问里也用它摆技能栏那一排（此时包含当前正在行动的这份）。
		# 客户端一律照这个顺序渲染，不得再自己排序 —— 以前客户端按 extra_order 重排，
		# 而 extra_order 没进这张字段表（永远收不到、恒为 0），技能栏和响应的顺序就对不上了。
		33: {"n": "extra_attack_causes", "t": "u32", "r": true},
		# 与同一条命令里的「额外行动列表」一一对应的动作种类（GConst.ActionType；与 args 的 cause 对应，
		# 或与 extra_attack_causes 对应）：客户端据此把按钮写成「额外【攻击行动】/【法术行动】」，
		# 两类都放行（AttackMagic）时写「额外【攻击行动】或【法术行动】」。
		34: {"n": "allow_actions", "t": "u32", "r": true},
		# 与 extra_attack_causes 一一对应的出牌 / 目标白名单：
		# 客户端选中某项后据此只点亮合法的牌 / 目标，点手牌 + 敌方头像即发起攻击。
		35: {"n": "extra_attack_cards", "t": "msg", "r": true, "s": "OptionTargets"},
		36: {"n": "extra_attack_targets", "t": "msg", "r": true, "s": "OptionTargets"},
		# 与 extra_attack_causes 一一对应的限定系别（CardElement；0＝不限）
		37: {"n": "extra_attack_elements", "t": "u32", "r": true},
		# 这份额外行动的唯一 ID（当前行动 / 可切换项各带一个）：
		# 同一个技能可以同时挂着好几份行动，界面提交时回这个 ID，服务端按它认人。
		38: {"n": "extra_uid", "t": "u32"},
		# 与 extra_attack_causes 一一对应的唯一 ID（攻击结束响应快捷按钮 / 额外行动阶段技能栏共用）
		39: {"n": "extra_attack_uids", "t": "u32", "r": true},
		# 与 args 里的选项值一一对应的唯一 ID（AdditionalAction 询问：选哪一份额外行动）。
		# 客户端提交时回 ID（放进 args[0]），不按 cause 认 —— cause 相同的两份分得清。
		40: {"n": "option_uids", "t": "u32", "r": true},
		# 带选项的询问里默认替玩家选中的那一项（0 基下标，与 args 里的选项值一一对应）。
		# 省略＝不预选；行动结束响应（聚合器）固定下发 0：一排可选行动摆出来时先点亮第一项，
		# 玩家不用先点一次选项才能按「确定」。客户端遇到该项不可用时顺延到下一项可用的。
		41: {"n": "default_option", "t": "u32"},
		# 带选项的询问：不要摆「被问的技能」本体那颗按钮（选项本身就是全部可选项）。
		# 行动结束响应（聚合器）固定下发：它的 respond_id 只是列表里的第一项，并不存在「父技能」，
		# 摆出来会和同名选项并排成两个一模一样的按钮（如女武神【神圣追击】）。
		42: {"n": "no_parent", "t": "bool"},
		# 当前额外行动限定的命格（GConst.FatePattern）。只按命格限制的额外行动（如技之剑意＝技类）
		# 不再下发「全部技类攻击牌」的牌号名单，客户端直接比对牌面的「命格」字段。
		43: {"n": "extra_fate", "t": "u32"},
		# 与 extra_attack_causes 一一对应的命格（额外行动切换列表用，0＝那一份不限命格）
		44: {"n": "extra_attack_fates", "t": "u32", "r": true},
		# 当前额外行动限定的系别（GConst.CardElement）：按钮写成「额外X系【攻击行动】」用。
		# 以前引擎写了这个字段、字段表里却没有，真实联机时被丢掉，客户端只能按技能号查兜底表。
		45: {"n": "extra_element", "t": "u32"},
		# 这条技能会把本次出牌固定视为哪个系别（如 3805 精灵的剑舞＝风系；0＝不固定）：
		# 客户端在额外行动阶段本地切换行动时，据此把与所选行动系别不符的技能按钮置灰。
		46: {"n": "skill_element", "t": "u32"},
		# 整段「专属提示」：非空时提示条直接用它，不再套技能表的说明
		# （如萝莉番长【爱死天流】9703 改写后的【血腥咆哮】整段文案）。
		47: {"n": "ask_prompt", "t": "str"},
		# 本次攻击不能用来应战的牌的卡名（GConst.CardName；如 9703 禁【暗灭】应战）：
		# 应战询问里下发，客户端据此把这些牌置灰；服务端仍会复核。
		48: {"n": "ban_reattack_card_names", "t": "u32", "r": true},
		# 这一条命令要「顺带点亮给人看」的角色（纯展示：不参与选择、不参与提交）：
		# 与 dst_ids 的区别是 dst_ids 表示「可点选的目标白名单」，这里只是头像高亮 + 提示落点。
		# 用于目标由别人代选、或效果落在不受玩家选择的角色身上的技能 ——
		# 如怠惰少女【别烦我……】10601：发动时点亮替她发动的右手边队友，
		# 目标被问「弃 1 张法术牌」时再点亮「不弃就 +1 治疗」的那名队友。
		49: {"n": "highlight_ids", "t": "u32", "r": true},
		# 带选项的询问里，每个选项各自「悬停要摊出来的预览牌」（与 args 里的选项值一一对应）：
		# 如暴食少女【三秒原则】的「获得 2 张【魔弹】」悬停时把那两张魔弹的卡面并排显示。
		50: {"n": "option_preview_cards", "t": "msg", "r": true, "s": "OptionTargets"},
	},
	# 技能参数选项的一项（battle_engine 组装命令时放进 arg_choices）
	"ArgChoice": {
		1: {"n": "text", "t": "str"},
		2: {"n": "args", "t": "u32", "r": true},
		3: {"n": "need_card", "t": "u32"},
		4: {"n": "need_target", "t": "u32"},
		5: {"n": "targets", "t": "u32", "r": true},
		# 该项自带的选牌来源 / 需盖牌数：-1 / 0 ＝ 沿用技能本体的
		# （如【倒逆之蝶】第 ② 项要在盖牌区点 2 张【茧】）
		6: {"n": "card_source", "t": "i32"},
		7: {"n": "cover_need", "t": "u32"},
		# 该选项的具体效果说明：按钮只放短标签（如「移除【水晶】」），
		# 选中后底部提示条显示这段说明（如散华轮舞的水晶 / 宝石方案）
		8: {"n": "说明", "t": "str"},
		# 该项本次是否可选（false＝按钮半透明、点不动）：如散华轮舞没有【水晶】时的水晶方案。
		# 省略＝可用；这个字段必须随网络下发，否则客户端会把不可用的选项也画成可点。
		9: {"n": "enabled", "t": "bool"},
		# 选项对应的系别（CardElement）：仅用于按钮文字配色，如欺诈的五种虚牌斩。
		10: {"n": "element", "t": "u32"},
		# 该选项自己的选牌上限（0/省略＝沿用技能本体）；如欺诈 2 张档最多 2、暗系 3 张档最多 3。
		11: {"n": "card_max", "t": "u32"},
		# 该项对应的技能号（>0 表示这个选项本身就是个技能：按钮按该技能的类型色显示，
		# 鼠标指向时弹它的技能说明，如矜贵之女 7802 的第 2 档＝响应 7805 友情羁绊）。
		12: {"n": "skill_id", "t": "u32"},
		# 该项自己可点哪些牌（牌面；空＝沿用技能本体的牌白名单）：
		# 如灵熙之潮【海神御巫】切到「地之封印」后，手里其它系别的封印 / 赐福牌都要置灰。
		13: {"n": "cards", "t": "u32", "r": true},
		# 鼠标指向这个选项时要摊出来的「预览牌」（牌面）：如暴食少女【三秒原则】的
		# 「获得 2 张【魔弹】」悬停时并排显示那两张魔弹的卡面（多张一起显示）。
		14: {"n": "preview_cards", "t": "u32", "r": true},
		# 鼠标指向这个选项时要显示的一组技能说明（技能号）：如噬神者【御刃】的「魔刃」选项
		# 要同时显示【魔刃】和【渗蚀】两条被动。客户端按角色技能提示.单个技能 拼成悬停说明。
		15: {"n": "技能组", "t": "u32", "r": true},
		# 选项涉及的可选系别（CardElement，按配置顺序）：如御刃「魔刃」选项的火/水系。
		# 只用于把选项文字里的「火系/水系」按系别标色，不参与提交。
		16: {"n": "elements", "t": "u32", "r": true},
	},
	# 某个选项各自的可点目标（option_targets 的一项）
	"OptionTargets": {
		1: {"n": "ids", "t": "u32", "r": true},
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
		# 客户端身份标识（局域网测试 = 昵称；以后上 Steam = SteamID）：服务端靠它认领原座位
		5: {"n": "client_id", "t": "str"},
		# 游戏版本号（project.godot 的 application/config/version）：两边不一致时服务端直接拒绝进房。
		# 大厅隔离标记 / 局域网发现里的版本只能保证「列表里看得出来版本不同」，这份挡的是真进房间
		6: {"n": "game_version", "t": "str"},
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
		# 调试模式：房主建房时勾选，房内所有人都能用测试指令（见 BattleEngine.room_debug）
		11: {"n": "debug", "t": "bool"},
		# 房间开启的角色版本位掩码（角色表「版本」列）；0/省略＝旧客户端，按全部版本处理
		12: {"n": "role_versions", "t": "u32"},
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
	GConst.Msg.SinglePlayer: PLAYER_INFO_FIELDS,
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
		# 房间的调试模式：开了客户端才响应测试指令、才显示可拖拽的测试提示
		21: {"n": "debug", "t": "bool"},
		# 观战者昵称：游戏内「玩家列表」里单列一段（没人观战就是空数组）
		22: {"n": "watchers", "t": "str", "r": true},
		# 是否处于选角阶段：准备室的观战提示据此显示「正在等待选角 / 正在等待开始」
		23: {"n": "picking", "t": "bool"},
		# 开局倒计时剩余毫秒（0 = 没在倒计时）：准备室据此显示「N 秒后开始」
		24: {"n": "start_countdown_ms", "t": "u32"},
		# 等待序号（本地扩展）：每开始一次新等待 +1，客户端据此避免重发快照重复弹「正在等待 X 操作」
		25: {"n": "wait_seq", "t": "u32"},
		# 本局是否已经打完：房主随即解散房间，客户端据此留在结算界面看结果（见 client_logic）
		26: {"n": "over", "t": "bool"},
		# 房主座位号（-1 = 没记录）：客户端「玩家列表」据此给房主标星号
		27: {"n": "host_seat", "t": "i32"},
		# 士气上限（固定 15）：随快照下发，客户端直接用它初始化队伍，
		# 别在客户端再写死一个数字
		28: {"n": "morale_max", "t": "u32"},
		# 选角阶段「已准备」的座位号（本地扩展）：选角界面底部「立即开始（x/X）」据此显示
		29: {"n": "pick_ready", "t": "u32", "r": true},
		# 场卡列表：【异端裁决所】/【末日预言】/【绝界】这类摆在场上（或某人面前）的卡（见 FieldCard）
		30: {"n": "field_cards", "t": "msg", "r": true, "s": "FieldCard"},
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
		# 聊天发言者的显示名（「昵称[角色名]」/「昵称[观战]」）：由服务端拼好 ——
		# 观战者不在玩家表里，客户端拿 id 反查不到人；角色名也只有服务端手里最新
		5: {"n": "name", "t": "str"},
		# 特殊行动（购买 / 合成 / 提炼）：值见 GConst.SpecialAction（购买 = 0，所以客户端用
		# has("special_action") 判断有没有这个字段，而不是拿 0 当「没有」）。普通 Gossip 不带
		6: {"n": "special_action", "t": "u32"},
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
		# 本地扩展：重连补发时带上「我已经选过的角色」（0 = 还没选），客户端直接显示等待界面
		8: {"n": "picked_role", "t": "u32"},
	},
	GConst.Msg.PickBan: {
		1: {"n": "strategy", "t": "u32"},
		2: {"n": "is_pick", "t": "bool"},
		3: {"n": "role_ids", "t": "u32", "r": true},
		# 客户端底部那颗「准备」按钮：true＝我点了准备。可反复发（服务端只记「已准备」），
		# 点了准备照样能改选 —— 改选只带 role_ids、不带这个标记，服务端的「已准备」不会被抹掉
		4: {"n": "ready", "t": "bool"},
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
		# 额外行动阶段「这一手要消耗哪份额外行动」的唯一 ID（0/省略＝不换，仍用当前那份）：
		# 打牌、技能行动都会带，服务端先换队再按换后的放行种类判合法性。
		# 这样「先点行动、再点技能」也能选中想用的那份行动，而不是总消耗服务端当前那一份。
		7: {"n": "extra_uid", "t": "u32"},
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
	GConst.Msg.CardElement: {
		1: {"n": "card_id", "t": "u32"},
		2: {"n": "element", "t": "u32"},
		# 服务端下行时带的「刷新后的行动命令」：客户端只在原地更新技能按钮，不重置当前操作
		3: {"n": "commands", "t": "msg", "r": true, "s": "Command"},
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
		# 虚拟攻击牌不继承卡面命格（目前是冒险家【欺诈】）：客户端显示卡名时不要加「·命格」。
		# 其他 is_real=false 的虚拟牌（如圣屑飓暴的圣命格虚牌）不填，仍按真实卡面命格显示。
		8: {"n": "virtual_no_fate", "t": "bool"},
		# 展示（CardMsgType.Show）是否一直留在展示区，直到下一条 Pick / Show 消息：
		# 10803 剑守誓言把牌库顶 X+1 张摊开后要一直摆着，等玩家慢慢选，不能 6.4 秒自动收起。
		9: {"n": "persist", "t": "bool"},
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
		# 本次播报用的技能显示名（覆盖技能表里的名字）：如元素射击按子弹系别显示
		# 「元素射击*SORA*风系」。空＝用技能表里的名字。
		4: {"n": "name", "t": "str"},
	},
	# 测试用（本项目本地扩展）：按测试按键做的操作，kind 见 GConst.DebugKey
	GConst.Msg.DebugReq: {
		1: {"n": "kind", "t": "u32"},
	},
	# 受伤飘字（本项目本地扩展）：伤害流水线跑完后广播的最终实际伤害
	GConst.Msg.HurtFloat: {
		1: {"n": "dst_id", "t": "u32"},
		2: {"n": "point", "t": "u32"},
		3: {"n": "type", "t": "u32"},
	},
}


## 取某协议号的字段表
static func fields(msg_type: int) -> Dictionary:
	return TABLE.get(msg_type, {})


## 取子消息字段表
static func sub_fields(name: String) -> Dictionary:
	return SUB.get(name, {})
