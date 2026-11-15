extends BattleRole
## 传教士（roleID 96 / 技能 9601~9608）
##
## 【路标】＝一张场卡（owner 始终是传教士，attached＝当前持有者）；【虔诚】＝0 号指示物（上限 4）。
## 左右手约定：座位链的 pre_id 是左手边、post_id 是右手边。
##
## 逐技能口径（原文见技能表）：
##   神的门徒 9601（被动·恒定）：队友数 > 1（6 人局）时你无法成为【路标】的目标；4 人局此技能无效。
##       ⚠「你的行动顺序改为拥有【路标】的角色之后」引擎没有动态行动顺序，未实现（见遗留）。
##   信仰之路 9602（被动）：你的第一回合开始把【路标】放到你左手边最近的角色面前；
##       你的回合结束若本回合未执行【特殊行动】，把【路标】转移到持有者左手边最近的角色面前。
##   传道 9603（启动）：摸 0~1 张牌、弃 1 张牌【强制】【展示】，你 +1【虔诚】；
##       持有【路标】的角色弃 1 张牌【展示】，你获得该牌【强制】；
##       该牌与你弃的牌同系别或同命格 → 你额外 +1【虔诚】。
##   启示 9604（响应·转移前）：移除 2 点【虔诚】，二选一 —— 目标角色 +1【治疗】；
##       或你摸 1 张牌【强制】【展示】，是法术牌 / 圣类命格就取消本次转移、把【路标】放到目标角色面前。
##   事奉 9605（响应）：你因自身技能弃的牌置入弃牌堆时，移除你 1【治疗】，把该牌交给【路标】持有者；
##       若没有因此让他掉士气，指定除你外的目标角色 +1【治疗】。
##   路标 9606（响应·专属技·告解式·回合限定）：此卡被转移到你面前时，你摸 2 张牌【强制】，
##       我方【战绩区】+1【水晶】，然后把此卡转移至你左手边最近的角色面前，传教士弃 1 张牌。
##   属灵恩赐 9607（启动·必杀【水晶】）：你 +1【治疗】，弃 1 张牌。
##   弥撒 9608（响应·必杀【水晶】）：【路标】转移或放置后，你 +1【虔诚】，二选一 ——
##       弃 1 张牌【展示】（是【虚弱】/【中毒】/【圣盾】就放到【路标】持有者面前作为基础效果）；
##       或把持有者面前 1 张基础效果牌收入自己手中，你额外 +1【虔诚】。
##
## 写法：分几次问玩家统一走 `BattleRole.多步询问`（约定见 项目文档/技能维护约定.md），
## 副作用放段「答完」/结算里。【路标】到达之后的推进集中在 `_到达后续()`：
##   0 空闲 / 1 到达判定（告解只认「转移」，放置直接跳到 5）/ 2 告解摸牌已结算（+1 水晶、转交）/
##   3 传教士弃牌 / 4 等启示链 / 5 收尾弥撒
## 任何重入（钩子重入、启示链回来）都从 `_到达后续()` 这同一个入口继续，不在里面递归新链。
## 告解（9606）的触发条件写的是「此卡被转移至你面前」，弥撒（9608）写的是「转移或放置后」——
## 所以「放置」（信仰之路第一回合放、启示取消转移后改放）只走弥撒，不走告解。

const SHEN_DE_MEN_TU: int = 9601
const XIN_YANG_ZHI_LU: int = 9602
const CHUAN_DAO: int = 9603
const QI_SHI: int = 9604
const SHI_FENG: int = 9605
const LU_BIAO: int = 9606
const SHU_LING_EN_CI: int = 9607
const MI_SA: int = 9608

const 虔诚槽: int = 0
const 路标名: String = "路标"
## 【虚弱】/【中毒】/【圣盾】是「放到角色面前」的基础效果牌（弥撒二选一里用）
const 基础效果牌名: Array[int] = [
	GConst.CardName.Shield, GConst.CardName.Weaken, GConst.CardName.Poison,
]
## 事奉在弃牌上下文里打的「这次由我接管」标记（每个 ctx 是一次弃牌事件，天然唯一）
const _事奉接管键: String = "_事奉接管"

## 信仰之路：第一回合的路标已经放过了
var _首回合已放: bool = false
## 【路标】到达之后的推进阶段，取值见文件头
var _到达阶段: int = 0
## 告解式【回合限定】：本回合是否已经发动过（每进入一个回合复位，见 p_before_turn_begin）
var _告解已用: bool = false
## 告解式正在问谁：问的是「路标刚到他面前」的那个人，不一定是传教士自己
var _告解到: int = -1
## 信仰之路：本回合的「回合结束转移」已经做过了。
## 钩子在压了状态后返回 URGENT 会被引擎重跑同一个钩子（SHook 不推进座位），
## 没有这个标记的话，告解摸牌 / 传教士弃牌一结算完就会再转移一次。
var _本回合已转移: bool = false

## 传道：段 2 答完时弃掉的自己的那张（段 3 收下对方的牌后比系别 / 命格用）
var _传道自己弃: int = -1
## 传道：这一步的「摸 1 张牌」已经摸过了（摸牌会等引擎跑完并重入技能本体）
var _传道已摸: bool = false
## 传道：摸牌结算完还要重入本技能接着问弃牌（见 技能URGENT后重入）
var _传道待续: bool = false

## 启示：本次原定转移到的目标 / 选的分支 / 启示结束后回到的阶段
var _转移目标: int = -1
## 分支②摸到的那张是不是「法术牌 / 圣类命格」（收尾里算一次，重入靠它）
var _启示成立: bool = false
## 分支②的「摸牌判定」是否已经做过（收尾会因压状态被重入）
var _启示已判定: bool = false
## 分支②的「落标 + 接着跑到达链」是否已经开始（同样只做一次）
var _启示已落标: bool = false
## 启示落标之后接着跑哪一段：1＝新到达（跑告解）/ 3＝告解链内（接着弃牌）
var _启示后阶段: int = 1
## 启示选中的目标（分支①的治疗对象 / 分支②要把【路标】放谁面前）
var _启示目标: int = -1
## 这次到达算不算「转移」（告解式只认转移；放置只走弥撒）
## 启示分支②：摸牌前的手牌快照、摸到的那张（-2＝还没判定 / -1＝没摸到）
var _启示摸前: Array = []
var _启示新牌: int = -2

## 弥撒：第 1 段选的分支、以及「收哪张基础效果」的候选表
var _弥撒选择: int = 0
var _弥撒可选: Array = []

## 事奉：本次要转交的牌 / 收牌人 / 会不会让他爆牌（＝会不会因此掉士气）/ 那条弃牌上下文
var _事奉牌: Array = []
var _事奉收牌人: int = -1
var _事奉可给治疗: bool = false
var _事奉上下文: Dictionary = {}


# ============================================================
# 技能栏 / 校验 / 入口
# ============================================================
func available_skills() -> Array:
	return [
		{
			"type": GConst.ActionType.ActivateSkill,
			"id": CHUAN_DAO,
			"need_card": 0,
			"need_target": 0,
			# 「摸 0~1 张」的点法同魔弓【魔眼】：点技能进二级技能栏选一项，点「返回」退出来
			"arg_choices": _传道选项(),
			"enabled": _传道可用(),
		},
		{
			"type": GConst.ActionType.ActivateSkill,
			"id": SHU_LING_EN_CI,
			"need_card": 1,
			"need_target": 0,
			"enabled": player.get_energy() >= 1 and not player.hand_cards.is_empty(),
		},
	]


## 传道要付「弃 1 张牌（强制）」：手里有牌，或者摸得到 1 张。
## 两样都没有时整颗发不动（否则会白占本回合的启动、还一张牌都弃不了）。
func _传道可用() -> bool:
	return not player.hand_cards.is_empty() or _牌库还有牌()


func _牌库还有牌() -> bool:
	return not engine.deck.pile.is_empty() or not engine.deck.discard.is_empty()


func is_free_skill(skill_id: int) -> bool:
	return skill_id == CHUAN_DAO or skill_id == SHU_LING_EN_CI


func v_special_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	match int(action.get("action_id", 0)):
		CHUAN_DAO:
			if not _传道可用():
				return GConst.GE_INVALID_ACTION
			var 参数: Array = action.get("args", [])
			var 摸: int = int(参数[0]) if not 参数.is_empty() else 0
			if 摸 != 0 and 摸 != 1:
				return GConst.GE_INVALID_ARGUMENT
			# 一次发动只初始化一次：v_ 每份行动只走一遍，p_ 会因为摸牌结算重入
			_传道自己弃 = -1
			_传道已摸 = false
			_传道待续 = false
			player.boot_skill_used = true
			notice_skill(CHUAN_DAO, [player.id])
			# 「你+1【虔诚】」按描述在发动这一步就结算，不等摸牌 / 弃牌 / 收牌走完
			player.add_token(虔诚槽, 1)
			engine._broadcast_game()
			return GConst.GE_SUCCESS
		SHU_LING_EN_CI:
			# 【水晶】费用：宝石可顶水晶（get_energy）；代价「弃 1 张牌」必须真交一张手牌
			if player.get_energy() < 1 or _提交的手牌(action.get("card_ids", [])) < 0:
				return GConst.GE_INVALID_ACTION
			return GConst.GE_SUCCESS
	return GConst.GE_INVALID_ACTION


func p_special_skill(action: Dictionary) -> int:
	match int(action.get("action_id", 0)):
		SHU_LING_EN_CI:
			return _属灵恩赐(action)
		CHUAN_DAO:
			return _传道(action)
	return SUCCESS


# ============================================================
# 属灵恩赐 9607：水晶 → +1 治疗、弃 1 张
# ============================================================
func _属灵恩赐(action: Dictionary) -> int:
	var 弃: int = _提交的手牌(action.get("card_ids", []))
	if 弃 < 0:
		return SUCCESS
	player.boot_skill_used = true
	notice_skill(SHU_LING_EN_CI, [player.id])
	player.remove_energy(1)
	施加治疗(player.id, 1)
	engine.take_from_hand(player.id, [弃])
	engine.to_discard([弃], {"owner": player.id, "source": "hand", "cause": SHU_LING_EN_CI})
	engine._log_discard(player.id, [弃])
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 传道 9603（启动）：摸 0~1 → 弃 1【展示】(+1 虔诚) → 持有者弃 1【展示】、你收下
# ============================================================
func _传道(action: Dictionary) -> int:
	var 参数: Array = action.get("args", [])
	var 要摸: bool = not 参数.is_empty() and int(参数[0]) == 1
	# 「你摸 0-1 张牌」：选了摸就先摸（摸完引擎重入，见 技能URGENT后重入）再问弃牌
	if 要摸 and not _传道已摸:
		_传道已摸 = true
		_传道待续 = true
		engine.push_draw(player.id, 1, CHUAN_DAO)
		return URGENT
	_传道待续 = false
	return 多步询问(CHUAN_DAO, [
		# 自己的代价：弃 1 张牌【强制】【展示】（提示条＝整段技能说明）
		{"需牌": 1, "牌白": _传道自己的手牌, "可取消": false, "超时默认": [],
		 "选项": _传道弃牌选项(), "默认选项": 1,
		 "跳过": _传道无需弃牌, "答完": _传道弃自己的, "询问文案": _传道提示()},
		# 持有【路标】的角色弃 1 张【展示】，你获得该牌【强制】
		# 这一步是「被传教士点名弃牌」，不是他自己发动传道 —— 不摆选项，问一句「弃 1 张牌」即可
		{"问谁": _传道收牌人, "需牌": 1, "牌白": _传道对方的手牌,
		 "可取消": false, "超时默认": [],
		 "跳过": _传道无需收牌, "答完": _传道收牌, "询问文案": _传道收牌提示()},
	], _传道结算)


## 「弃 1 张牌」这一步的选项：只摆这一个、并且默认选中（玩家点手牌 + 确定就行，
## 二级技能栏也不会空着）。文案优先读技能表「按钮3」，没配就用这句。
func _传道弃牌选项() -> Array:
	var 文案: String = GConst.按钮原文(CHUAN_DAO, 2)
	if 文案.is_empty():
		文案 = "弃 1 张牌"
	return [{"value": 1, "label": 文案, "text": 文案}]


## 传道两步弃牌的提示条（一次性初始化在 v_special_skill 里做，那里每份行动只走一遍）：
## 自己那一步是整个技能在推进 → 标准整体提示「【技能名】：说明」；
## 对方那一步只做「弃 1 张给他、可能再加虔诚」→ 写清他要做什么、之后会发生什么。
func _传道提示() -> String:
	return "【%s】：%s" % [GConst.skill_name(CHUAN_DAO), GConst.skill_desc(CHUAN_DAO)]


func _传道收牌提示() -> String:
	return "【%s】：弃 1 张牌【展示】，传教士获得该牌【强制】，（若该牌与你的弃牌系别或命格相同）传教士额外+1【虔诚】" % GConst.skill_name(CHUAN_DAO)


## 二级技能栏里的两个选项（同魔弓【魔眼】：点技能进栏选，点「返回」退出）
func _传道选项() -> Array:
	var out: Array = []
	for i: int in range(2):
		out.append({"text": GConst.按钮原文(CHUAN_DAO, i), "args": [i]})
	return out


func _传道自己的手牌(_答案: Array) -> Array:
	return player.hand_cards


func _传道无需弃牌(_答案: Array) -> bool:
	return player.hand_cards.is_empty()


func _传道收牌人(_答案: Array) -> int:
	return 路标持有者()


func _传道对方的手牌(_答案: Array) -> Array:
	var dp: BattlePlayer = engine.p(路标持有者())
	return dp.hand_cards if dp != null else []


## 第 3 段要不要问：持有者得是「别人」且手里有牌（否则这半句弃不了牌、也收不到牌）
func _传道无需收牌(_答案: Array) -> bool:
	return not _可向他收牌(路标持有者())


## 向某人收牌的前提：是别人、且手里有牌
func _可向他收牌(pid: int) -> bool:
	var dp: BattlePlayer = engine.p(pid)
	return pid >= 0 and dp != null and not dp.hand_cards.is_empty()


## 第 1 段答完：把自己的代价牌【展示】弃掉（+1【虔诚】已在发动时结算）
func _传道弃自己的(回: Dictionary, _答案: Array) -> int:
	var 弃: int = _认一张手牌(player, 回.get("cards", []))
	if 弃 < 0:
		return SUCCESS
	_传道自己弃 = 弃
	# 「弃 1 张牌【强制】【展示】」：统一入口（亮牌 + 触发封印 + 离手 + 弃牌堆 + 日志）
	engine.展示手牌并弃(player.id, [弃], {"cause": CHUAN_DAO})
	engine._broadcast_game()
	return SUCCESS


## 第 3 段答完：持有者弃的那张【展示】后归你；与你弃的牌同系别或同命格 → 再 +1【虔诚】
func _传道收牌(回: Dictionary, _答案: Array) -> int:
	var 到: int = 路标持有者()
	var dp: BattlePlayer = engine.p(到)
	if dp == null:
		return SUCCESS
	var 得: int = _认一张手牌(dp, 回.get("cards", []))
	if 得 < 0:
		return SUCCESS
	# 「弃 1 张牌【展示】，你获得该牌【强制】」：牌从他的手直接到你手里，不进弃牌堆，
	# 所以不走 to_discard（别人的「弃牌前拦截」等的是「置入弃牌堆」，这半句根本没进弃牌堆）
	engine.展示手牌(到, [得])
	engine.take_from_hand(到, [得])
	player.add_hand_cards([得])
	# 统一入口：日志「X 交给 Y 【牌】」+ 客户端「牌从甲飘到乙」的给牌动效
	engine._log_give_cards(到, player.id, [得])
	var 我: GCard = Data.get_card(_传道自己弃)
	var 他: GCard = Data.get_card(得)
	if 我 != null and 他 != null and (我.element_enum() == 他.element_enum()
			or 我.fate_pattern_enum() == 他.fate_pattern_enum()):
		player.add_token(虔诚槽, 1)
	engine._broadcast_game()
	return SUCCESS


func _传道结算(_答案: Array) -> int:
	engine._broadcast_game()
	return SUCCESS


## 摸牌那段答完会返回 URGENT：让 SkillRun 放行重入技能本体，接着问第 2 段
func 技能URGENT后重入(_action: Dictionary = {}) -> bool:
	# 传道：选「摸 1 张牌」时先压了一张摸牌、链还没建起来 —— 这时也必须放行重入，
	# 否则摸完这一手就结束了（漏掉两步弃牌）。_传道待续 只在「摸牌→接着问」这一跳里为真。
	if int(_action.get("action_id", 0)) == CHUAN_DAO:
		return _传道待续
	return false


# ============================================================
# 信仰之路 9602：第一回合放【路标】；回合结束（未执行特殊行动）转移【路标】
# ============================================================
## 告解式的【回合限定】＝本回合一次：每进入一个回合复位一次。
## 本钩子自己从不等待，所以每个回合只会跑一次，不会因为重入把标记提前清掉。
func p_before_turn_begin(_ctx: Dictionary) -> int:
	_告解已用 = false
	_本回合已转移 = false
	return SUCCESS


func p_turn_begin(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	var 续: int = _收尾没走完的部分()
	if 续 != SUCCESS:
		return 续
	if not _首回合已放:
		var 左: int = _下一个可持路标者(player.id)
		if 左 >= 0:
			_首回合已放 = true
			return _放置路标(左)
	return SUCCESS


func p_turn_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	var 续: int = _收尾没走完的部分()
	if 续 != SUCCESS:
		return 续
	# 本回合的转移已经做过（重入）：只把剩下的链跑完，别再转移一次
	if _本回合已转移:
		return SUCCESS
	# 本回合执行过【特殊行动】就不转移
	if player.action_count_of("special") > 0:
		return SUCCESS
	var 持有者: int = 路标持有者()
	if 持有者 < 0:
		return SUCCESS
	var 左: int = _下一个可持路标者(持有者)
	if 左 < 0:
		return SUCCESS
	_本回合已转移 = true
	# 转移前先给【启示】一次机会（落点 1＝转移完是一次新到达，接着跑告解 / 弥撒）
	return _转移路标(左, 1)


## 上一次的路标到达 / 弥撒链被打断时，先把它们走完再处理这次的新触发
func _收尾没走完的部分() -> int:
	if _到达阶段 != 0:
		return _到达后续()
	if 多步询问进行中(QI_SHI) or 多步询问待收尾(QI_SHI):
		return _启示链()
	if 多步询问进行中(MI_SA):
		return _弥撒()
	return SUCCESS


# ============================================================
# 路标放置 / 转移：到达后依次跑【告解式】与【弥撒】
# ============================================================
## 把【路标】放到某人面前（保留 owner），并接着跑到达链。
## 「放到某人面前」不管是放置还是转移，都算一次到达：告解式与弥撒都要按到达者问
##（信仰之路第一回合的放置漏问过告解式，需求方指出是 bug）。
func _放置路标(目标: int) -> int:
	_路标放下(目标)
	_到达阶段 = 1
	return _到达后续()


## 只挪位置，不跑链（链由 `_到达后续()` 推）。
## 「神的门徒」下不能被放路标的角色（6 人局里的她自己）直接不挪。
func _路标放下(目标: int) -> void:
	if not _可持路标(目标):
		return
	engine.加场卡({"id": 路标名, "owner": player.id, "attached": 目标})


## 转移【路标】给某人：先问【启示】（虔诚 ≥ 2 时才有得选），落标之后回到 落点 阶段。
## 落点 1（默认）＝转移完算一次新到达（跑告解 / 弥撒）；落点 3＝告解链内部的「转到左手边」，接着弃牌。
func _转移路标(目标: int, 落点: int = 1) -> int:
	_启示后阶段 = 落点
	if player.token_num(虔诚槽) < 2:
		_路标放下(目标)
		_到达阶段 = 落点
		if 落点 != 1:
			return SUCCESS
		return _到达后续()
	_转移目标 = 目标
	_启示摸前 = []
	_启示新牌 = -2
	_启示已判定 = false
	_启示已落标 = false
	_到达阶段 = 4
	return _启示链()


## 【路标】到达之后的推进：告解（摸 2 → 战绩区 +1 水晶 → 转到左手边 → 传教士弃 1 张）→ 弥撒
func _到达后续() -> int:
	while true:
		if _到达阶段 == 0:
			return SUCCESS
		if _到达阶段 == 1:
			var 到: int = 路标持有者()
			# 只要【路标】到了某人面前就问他要不要发动告解式（放置、转移都算到达）
			if not _可发动告解(到):
				_到达阶段 = 5
				continue
			# 告解式是【响应】：先问到他面前的那个人要不要发动，确认了才摸牌、加水晶、往下传
			return _问告解(到)
		if _到达阶段 == 2:
			engine.set_team_crystal(player.color, engine.team_crystal[player.color] + 1)
			var 下: int = _下一个可持路标者(路标持有者())
			_到达阶段 = 3
			if 下 < 0:
				continue
			# 「将此卡转移至你左手边最近的角色面前」也是一次转移 → 转移前同样可以【启示】
			var 返: int = _转移路标(下, 3)
			if 返 != SUCCESS:
				return 返
			continue
		if _到达阶段 == 3:
			_到达阶段 = 5
			if player.hand_cards.is_empty():
				continue
			engine.push(BattleEngine.SRequestDiscard.new(player.id, 1, 0, LU_BIAO))
			return URGENT
		if _到达阶段 == 4:
			# 正在问启示（或在跑它的收尾：摸牌后要看摸到什么）：把这条链接上
			if 多步询问进行中(QI_SHI) or 多步询问待收尾(QI_SHI):
				return _启示链()
			_到达阶段 = _启示后阶段
			continue
		# 5：收尾 → 弥撒
		_到达阶段 = 0
		if player.get_energy() < 1 or not _弥撒可用():
			return SUCCESS
		return _弥撒()
	return SUCCESS


## 【路标】告解式：问「路标到谁面前」的那个人要不要发动（【响应】技能，不是自动生效）。
## 确认后才摸 2 张、我方战绩区 +1【水晶】、把卡转到他左手边、传教士弃 1 张（阶段 2 起接着跑）。
func _问告解(到: int) -> int:
	_告解到 = 到
	return 多步询问(LU_BIAO, [
		# 不摆选项：标准「是否发动」询问，客户端就是「确定 / 取消」两下
		{"问谁": func(_答案: Array) -> int: return _告解到,
		 "可取消": true,
		 "取消": _告解不发动,
		 "询问文案": _告解询问文案()},
	], _告解结算)


## 提示条就写技能原文（标准写法：「【技能名】：说明」），不另编一句话
func _告解询问文案() -> String:
	return "【%s】：%s" % [GConst.skill_name(LU_BIAO), GConst.skill_desc(LU_BIAO)]


## 取消 / 超时＝不发动：告解式整段跳过，直接进弥撒
func _告解不发动() -> int:
	_到达阶段 = 5
	return _到达后续()


## 走到结算＝玩家按了「确定」（按取消 / 超时走 _告解不发动，不进来）
func _告解结算(_答案: Array) -> int:
	_告解已用 = true
	notice_skill(LU_BIAO, [_告解到])
	# 先记阶段再压摸牌：摸牌跑完回到 _到达后续 时从阶段 2 接着走（同原来的写法）
	_到达阶段 = 2
	engine.push_强制摸牌(_告解到, 2, LU_BIAO)
	return URGENT


## 告解式能不能发动：【回合限定】（本回合一次），且到达者不是传教士自己（2V2 除外）
func _可发动告解(到: int) -> bool:
	return not _告解已用 and _可持路标(到)


# ============================================================
# 启示 9604（响应·路标转移前）：移除 2【虔诚】→ 二选一
# ============================================================
func _启示链() -> int:
	# 两个选项各自要选 1 名目标：选效果的同一步就点头像，再按确定（不再先选效果、后补问目标）
	return 多步询问(QI_SHI, [
		{"选项": _启示选项(), "取消": _启示不发动, "询问文案": _启示提示()},
	], _启示结算, _启示摸牌收尾)


## 「目标角色」原文＝谁都能选；分支②要放【路标】，所以按「能被放路标」过滤（神的门徒：不选自己）
func _启示选项() -> Array:
	var 治疗白: Array = 全部角色()
	# 分支②的文案按需求方口径整句写死（表里「按钮2」还是旧的短句，等表里改了再切回 GConst.按钮原文）
	var 摸牌文: String = "你摸 1 张牌【强制】【展示】，若为法术牌或圣类命格，转移【路标】"
	return [
		{"value": 1, "label": GConst.按钮原文(QI_SHI, 0), "text": GConst.按钮原文(QI_SHI, 0),
		 "need_target": 1, "targets": 治疗白},
		{"value": 2, "label": 摸牌文, "text": 摸牌文,
		 "need_target": 1, "targets": _可持路标列表()},
	]


## 询问文案＝整段技能说明（标准写法）
func _启示提示() -> String:
	return "【%s】：%s" % [GConst.skill_name(QI_SHI), GConst.skill_desc(QI_SHI)]


## 启示不发动（第 1 段取消 / 超时）：什么都不扣，照常把路标转移到原定目标
func _启示不发动() -> int:
	_启示摸前 = []
	_启示新牌 = -2
	return _落标并继续(_转移目标)


## 分支②摸到的那张是不是「法术牌或者圣类命格」：摸牌前拍过快照，只差这一张。
## 判定只做一次（跳过会被重复求值），顺手把它【展示】出来。
func _启示摸牌成立() -> bool:
	if _启示新牌 == -2:
		_启示新牌 = -1
		for c: Variant in player.hand_cards:
			if not _启示摸前.has(int(c)):
				_启示新牌 = int(c)
				break
		if _启示新牌 >= 0:
			# 「你摸 1 张牌【强制】【展示】」：亮给全场（封印类响应压在后面的结算之上）
			engine.展示手牌(player.id, [_启示新牌])
	var 牌: GCard = Data.get_card(_启示新牌) if _启示新牌 >= 0 else null
	return 牌 != null and (牌.is_magic() or 牌.fate_pattern_enum() == GConst.FatePattern.Holy)


func _启示结算(答案: Array) -> int:
	var 回: Dictionary = 答案[0] if not 答案.is_empty() else {}
	var args: Array = 回.get("args", [])
	var dsts: Array = 回.get("dsts", [])
	var 分支: int = int(args[0]) if not args.is_empty() else 1
	var 目标: int = int(dsts[0]) if dsts.size() == 1 else -1
	# 发动代价：移除 2 点【虔诚】（不发动 / 超时时不扣，见 _启示不发动）
	player.remove_token(虔诚槽, 2)
	var 播报: Array = []
	if 目标 >= 0:
		播报.append(目标)
	else:
		播报.append(player.id)
	notice_skill(QI_SHI, 播报)
	engine._broadcast_game()
	_启示目标 = 目标
	if 分支 == 1:
		# ① 目标角色 +1【治疗】，本次转移照常进行
		施加治疗(目标, 1)
		engine._broadcast_game()
		# 放置路标会顺带压告解 / 弥撒：那是别的流程，不登记本链的收尾
		多步询问跳过收尾(QI_SHI)
		var 返1: int = _落标并继续(_转移目标)
		if 返1 == SUCCESS:
			多步询问重置(QI_SHI)
		return 返1
	# ② 先摸 1 张牌；摸完由收尾判断「是不是法术牌 / 圣类命格」，成立就把路标改放到目标面前
	_启示摸前 = player.hand_cards.duplicate()
	_启示新牌 = -2
	_启示已判定 = false
	_启示已落标 = false
	engine.push_强制摸牌(player.id, 1, QI_SHI)
	return URGENT


## 分支②摸完牌后的收尾：法术牌 / 圣类命格 → 取消本次转移、把【路标】放到选中的目标面前。
## 判定与落标各只做一次：收尾会因为后面压出的告解 / 弥撒被反复重入。
func _启示摸牌收尾() -> int:
	if not _启示已判定:
		_启示已判定 = true
		_启示成立 = _启示摸牌成立()
		_启示摸前 = []
		_启示新牌 = -2
		if _启示成立 and _启示目标 >= 0:
			engine.移除场卡(路标名)
	var 目的: int = _启示目标 if (_启示成立 and _启示目标 >= 0) else _转移目标
	if not _启示已落标:
		_启示已落标 = true
		return _落标并继续(目的)
	var 返: int = _到达后续()
	if 返 == SUCCESS:
		_启示已判定 = false
		_启示成立 = false
		_启示已落标 = false
	return 返


## 把【路标】挪到某人面前，并按「这次属于哪条流程」继续（见 _启示后阶段）。
## 放置和转移都会触发告解式（见 _放置路标 的说明）。
func _落标并继续(目标: int) -> int:
	_路标放下(目标)
	_到达阶段 = _启示后阶段
	return _到达后续()


# ============================================================
# 事奉 9605：因自身技能弃牌时，移除 1【治疗】把该牌交给路标持有者；没害他爆牌再给 1【治疗】
# ============================================================
func wants_before_discard(ctx: Dictionary) -> bool:
	return _事奉可发动(ctx)


## 只有 wants_before_discard 返回 true，引擎才会推迟这次弃牌、跑 p_before_discard
func _事奉可发动(ctx: Dictionary) -> bool:
	if int(ctx.get("owner", -1)) != player.id:
		return false
	if str(ctx.get("source", "")) != "hand":
		return false
	if not _自身技能弃牌(int(ctx.get("cause", 0))):
		return false
	if player.cross_num <= 0:
		return false
	var 持有者: int = 路标持有者()
	return 持有者 >= 0 and 持有者 != player.id


## 「你因自身技能弃的牌」＝ 传道 / 属灵恩赐 / 弥撒 / 路标 这四颗技能的弃牌
func _自身技能弃牌(cause: int) -> bool:
	return cause == CHUAN_DAO or cause == SHU_LING_EN_CI or cause == MI_SA or cause == LU_BIAO


func p_before_discard(ctx: Dictionary) -> int:
	# 这次弃牌已经由【事奉】接管（回复回来 / 压了状态被重入）：先把链跑完。
	# 必须放在资源门槛之前 —— 发动时已经扣过 1 点【治疗】，重入时它可能正好是 0，
	# 再判一次门槛就会把回复吞掉（约定 §20）。
	if bool(ctx.get(_事奉接管键, false)):
		return _事奉链() if 多步询问进行中(SHI_FENG) else SUCCESS
	if not _事奉可发动(ctx):
		return SUCCESS
	ctx[_事奉接管键] = true
	_事奉上下文 = ctx
	_事奉收牌人 = 路标持有者()
	_事奉牌 = (ctx.get("cards", []) as Array).duplicate()
	_事奉可给治疗 = false
	return _事奉链()


## 两段：先问发不发动（取消＝不发动，代价是移除 1 点【治疗】）；
## 发动后若不会让持有者爆牌（＝不因此掉士气），再问一次「除你外的目标角色 +1【治疗】」
func _事奉链() -> int:
	return 多步询问(SHI_FENG, [
		{"取消": _事奉不发动, "答完": _事奉发动},
		{"需目标": 1, "目标白": 除自己(), "可取消": false, "超时目标": 除自己(),
		 "跳过": _事奉无需给治疗,
		 "预览基准": 1, "预览类型": GConst.预览类型_治疗},
	], _事奉结算)


func _事奉无需给治疗(_答案: Array) -> bool:
	return not _事奉可给治疗


## 第 1 段答完：发动 —— 扣 1【治疗】，把这次弃的牌改交给他（taken / taker 交给引擎结算）
func _事奉发动(_回: Dictionary, _答案: Array) -> int:
	var 他: BattlePlayer = engine.p(_事奉收牌人)
	if 他 == null:
		_事奉可给治疗 = false
		return SUCCESS
	player.sub_cross_num(1)
	_事奉上下文["taken"] = _事奉牌
	_事奉上下文["taker"] = _事奉收牌人
	notice_skill(SHI_FENG, [_事奉收牌人])
	engine._broadcast_game()
	# 「若没有因此造成该角色阵营士气下降」＝这几张牌交过去不会让他爆牌。
	# 提前估算（超限掉士气要等弃牌结算完才知道，这里只做得到「加进来会不会超上限」）。
	_事奉可给治疗 = 他.hand_cards.size() + _事奉牌.size() <= 他.hand_cards_max
	return SUCCESS


func _事奉不发动() -> int:
	_事奉牌 = []
	_事奉上下文 = {}
	engine._broadcast_game()
	return SUCCESS


func _事奉结算(答案: Array) -> int:
	var 目标: int = -1
	if 答案.size() > 1:
		var dsts: Array = (答案[1] as Dictionary).get("dsts", [])
		if not dsts.is_empty():
			目标 = int(dsts[0])
	_事奉牌 = []
	_事奉上下文 = {}
	if 目标 >= 0:
		施加治疗(目标, 1)
		engine._broadcast_game()
	return SUCCESS


# ============================================================
# 弥撒 9608（响应·必杀【水晶】）：路标转移/放置后，+1【虔诚】，二选一
# ============================================================
func _弥撒() -> int:
	# 跨段状态只在新的一条链开始时清：第 2 段回复回来重入时还要用它判断是哪一支
	if not 多步询问进行中(MI_SA):
		_弥撒选择 = 0
		_弥撒可选 = []
	return 多步询问(MI_SA, [
		{"选项": _弥撒选项(), "答完": _弥撒记录选择},
		{"选项": func(_答案: Array) -> Array: return _收入选项(_弥撒可选),
		 "可取消": false,
		 "跳过": func(_答案: Array) -> bool: return not _弥撒需要二段()},
	], _弥撒结算)


## 弥撒的两档都可能是「没得选」（手里没牌 / 持有者面前没有基础效果）：都不可用就不问
func _弥撒可用() -> bool:
	if not player.hand_cards.is_empty():
		return true
	var dp: BattlePlayer = engine.p(路标持有者())
	return dp != null and not _基础效果列表(dp).is_empty()


## 第 1 段答完：只记下选择；选②时把持有者面前的基础效果表抄下来给第 2 段用
func _弥撒记录选择(回: Dictionary, _答案: Array) -> int:
	var args: Array = 回.get("args", [])
	_弥撒选择 = int(args[0]) if not args.is_empty() else 0
	_弥撒可选 = []
	if _弥撒选择 == 2:
		var dp: BattlePlayer = engine.p(路标持有者())
		_弥撒可选 = _基础效果列表(dp) if dp != null else []
	return SUCCESS


## 选②且持有者面前有 ≥2 张基础效果时才问第 2 段「收哪一张」
func _弥撒需要二段() -> bool:
	return _弥撒选择 == 2 and _弥撒可选.size() > 1


func _弥撒结算(答案: Array) -> int:
	if _弥撒选择 != 1 and _弥撒选择 != 2:
		return SUCCESS
	var 持有: int = 路标持有者()
	var dp: BattlePlayer = engine.p(持有)
	if dp == null:
		return SUCCESS
	if _弥撒选择 == 1:
		return _弥撒弃牌(答案, 持有)
	return _弥撒收牌(答案, dp)


## ① 弃 1 张牌【展示】；是【虚弱】/【中毒】/【圣盾】就挂到持有者面前作为基础效果
func _弥撒弃牌(答案: Array, 持有: int) -> int:
	var cards: Array = (答案[0] as Dictionary).get("cards", []) if not 答案.is_empty() else []
	var 弃: int = _提交的手牌(cards)
	if 弃 < 0:
		return SUCCESS
	player.remove_energy(1)
	player.add_token(虔诚槽, 1)
	notice_skill(MI_SA, [持有])
	engine._broadcast_game()
	engine.展示手牌(player.id, [弃])
	engine.take_from_hand(player.id, [弃])
	var 牌: GCard = Data.get_card(弃)
	# 目标不能接收基础效果（如灵熙之潮 4601）时不能白吃这张牌：照常弃掉
	var 能挂: bool = 牌 != null and 基础效果牌名.has(牌.card_name_enum()) \
		and engine.v_basic_effect_target(持有, 弃) == GConst.GE_SUCCESS
	if 能挂:
		engine.add_basic_effect(持有, 弃, player.id, MI_SA)
	else:
		engine.to_discard([弃], {"owner": player.id, "source": "hand", "cause": MI_SA})
		engine._log_discard(player.id, [弃], false)
	engine._broadcast_game()
	return SUCCESS


## ② 把持有者面前 1 张基础效果牌收入手中，额外 +1【虔诚】
func _弥撒收牌(答案: Array, dp: BattlePlayer) -> int:
	var 可选: Array = _弥撒可选 if _弥撒需要二段() else _基础效果列表(dp)
	if 可选.is_empty():
		return SUCCESS
	var 序: int = 0
	if _弥撒需要二段():
		var args2: Array = (答案[1] as Dictionary).get("args", []) if 答案.size() > 1 else []
		if args2.is_empty():
			return SUCCESS
		序 = int(args2[0]) - 1
		if 序 < 0 or 序 >= 可选.size():
			engine.报错("【弥撒】选项号越界", player.id)
			return SUCCESS
	player.remove_energy(1)
	player.add_token(虔诚槽, 2)
	notice_skill(MI_SA, [dp.id])
	engine._broadcast_game()
	var 牌: int = int(可选[序])
	engine.remove_basic_effect(dp.id, 牌, MI_SA, player.id)
	player.add_hand_cards([牌])
	engine.播获得牌日志(player.id, [牌])
	engine._broadcast_game()
	return SUCCESS


func _弥撒选项() -> Array:
	var dp: BattlePlayer = engine.p(路标持有者())
	var 有基础: bool = dp != null and not _基础效果列表(dp).is_empty()
	return [
		{
			"value": 1,
			"label": GConst.按钮原文(MI_SA, 0),
			"text": GConst.按钮原文(MI_SA, 0),
			"need_card": 1,
			"enabled": not player.hand_cards.is_empty(),
		},
		{
			"value": 2,
			"label": GConst.按钮原文(MI_SA, 1),
			"text": GConst.按钮原文(MI_SA, 1),
			"enabled": 有基础,
		},
	]


## 持有者面前的基础效果牌（跳过【Tricky】占位：那张是捣蛋萝莉的代理牌，真实牌面在别处）
func _基础效果列表(dp: BattlePlayer) -> Array:
	var out: Array = []
	for be: Dictionary in dp.basic_effects:
		if int(be["card"]) != GConst.卡_Tricky:
			out.append(int(be["card"]))
	return out


func _收入选项(表: Array) -> Array:
	var out: Array = []
	for i: int in range(表.size()):
		var 牌: GCard = Data.get_card(int(表[i]))
		var 文案: String = 牌.card_name if 牌 != null else ""
		out.append({"value": i + 1, "label": 文案, "text": 文案, "card_id": int(表[i])})
	return out


# ============================================================
# 小工具
# ============================================================
## 提交的牌里第一张「确实在他手里」的实例号；没有（超时 / 空回复）就按手牌顺序补第一张。
## 强制弃牌不能静默不发生（约定 §16）。返回 -1＝他手里一张牌都没有。
func _认一张手牌(dp: BattlePlayer, 提交: Array) -> int:
	for c: Variant in 提交:
		var 实例: int = dp.手牌实例(int(c))
		if 实例 >= 0:
			return 实例
	if dp.hand_cards.is_empty():
		return -1
	return int(dp.hand_cards[0])


## 提交的牌里第一张「确实在自己手里」的实例号（没有返回 -1）
func _提交的手牌(cards: Array) -> int:
	for c: Variant in cards:
		var 实例: int = player.手牌实例(int(c))
		if 实例 >= 0:
			return 实例
	return -1


## 左手边最近的玩家（座位链的 pre_id）；找不到返回 -1
func 左手边(pid: int) -> int:
	var p0: BattlePlayer = engine.p(pid)
	if p0 == null:
		return -1
	return p0.pre_id


func 路标持有者() -> int:
	var 表: Dictionary = engine.取场卡(路标名)
	if 表.is_empty():
		return -1
	return int(表.get("attached", -1))


## 神的门徒 9601：队友数 > 1（6 人局）时她无法成为【路标】的目标【恒定】；
## 4 人局（队友只有 1 人）此技能无效，她也可以是【路标】的落点。
func _可持路标(pid: int) -> bool:
	if engine.p(pid) == null:
		return false
	return pid != player.id or 队友数() > 1


func 队友数() -> int:
	var n: int = 0
	for pid: int in engine.order:
		var p0: BattlePlayer = engine.p(pid)
		if p0 != null and pid != player.id and p0.color == player.color:
			n += 1
	return n


## 从某人往里找「左手边最近、且能被放路标」的角色；找不到返回 -1
func _下一个可持路标者(从前: int) -> int:
	var 当前: int = 从前
	for _i: int in range(engine.order.size()):
		当前 = 左手边(当前)
		if 当前 < 0:
			return -1
		if 当前 != 从前 and _可持路标(当前):
			return 当前
	return -1


## 能被放【路标】的全部角色（启示分支②选落点用，口径同 _可持路标）
func _可持路标列表() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		if _可持路标(pid):
			out.append(pid)
	return out


## 除自己以外的全部在场角色（事奉的治疗目标：原文写明「除你外」）
func 除自己() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		if pid != player.id:
			out.append(pid)
	return out


func 全部角色() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		out.append(pid)
	return out
