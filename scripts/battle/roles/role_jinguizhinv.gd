extends BattleRole
## 矜贵之女（roleID 78）—— 神子创临版本
## 技能：
##   高岭之花（7801，被动）：你执行【提炼】时，若本次提炼至少包含 1【宝石】，你 +1【水晶】。
##   魔法入门（7802，法术 / 普通 / 无）：你摸 1 张牌【强制】【展示】，根据所展示的牌依序触发：
##       （若有法术牌）对 2 名目标对手各造成 1 点法术伤害③；
##       （若有 X 张咏类命格）你对 X 名目标角色各造成 1 点法术伤害③；
##       （若有 X 张水系牌）指定 X 名目标角色各 +1【治疗】。
##   Magic!（7803，响应 / 普通 / 无）：【魔法入门】展示牌触发效果时，你弃 2 张牌；
##       【魔法入门】展示牌未触发任何效果时，你额外 +1【法术行动】；
##       本回合第 3 次【魔法入门】结算时，我方【战绩区】+2【宝石】。
##   强予愿行（7804，启动 / 必杀技 / 水晶）：支付 1【水晶】，将你的手牌调整为 4 张【强制】；
##       若你额外移除我方【战绩区】1 星石，将一名其他角色手牌调整为 4 张【强制】。
##   友情羁绊（7805，响应 / 必杀技 / 宝石 / 回合限定）：发动【魔法入门】时，将「你摸 1 张牌
##       【强制】【展示】」改为「我方 2 名角色各弃 1 张牌【强制】【展示】，技能效果结束前
##       各摸 1 张牌【强制】」。
##
## 口径（见 data-audit A27~A30）：
##   - A27：7802 的 X＝本次「展示牌集合」里满足条件的张数；7805 后集合是那 2 张弃牌，X≤2；
##     三种效果按「法术牌 → 咏类命格 → 水系牌」依序触发（各自的 X 独立计算）；
##   - A28：7803 的三个触发独立、各自可选；「第 3 次」只在本回合第 3 次 7802 结算时问一次；
##     弃 2 张是可选代价（技能原文没有写后续效果，按字面只弃牌）；额外法术行动直接进入
##     （direct，玩家已经为发动 7803 做过一次确认）；
##   - A29：7804 的星石类型由发动者选；「额外移除」是可选分支（不选则只调整自己）；
##     其他角色由牌主自己选弃哪张（走 F9 的 调整手牌到，不替牌主选牌）；
##     选星石 / 选角色这两个子询问的取消与超时都按「放弃额外移除」处理（不扣星石、不改他人手牌），
##     不替玩家补默认星石 / 默认目标；
##   - A30：7805 的「我方 2 名角色」可含自己、必须互异；只有最初展示的 2 张弃牌触发 7802 效果，
##     技能结束前各自摸的 1 张【强制】不再并入展示集合；这 2 张弃牌在各自选定时立即离手
##     （入弃牌堆在结算统一做），保证后面（更早于技能结算的）7803 询问选不到它们、结算时也不会重复入弃；
##   - 【水晶】费用按《技能维护约定》用 get_energy() 判断、remove_energy(1) 支付（宝石可顶水晶）；
##     【宝石】费用必须是真宝石（7805）。
##
## 实现要点：
##   - 7802 是「法术技能」（SkillRun kind=magic），分步推进用引擎按状态实例隔离的 step，
##     每一步询问后返回 WAIT，重入继续；所有状态（伤害 / 展示 / 弃牌）留到最后一步一次性压栈，
##     避免把展示响应 / 伤害结算夹在两次询问中间；
##   - 展示牌钩子（p_show_hand）压在伤害与弃牌状态之上（最后 push），其他角色的「展示牌」响应
##     先结算，再跑本次的伤害 / 行动结束，与引擎 _do_magic 的 LIFO 顺序一致；
##   - 7804 是「启动」技能（is_free_skill 认可）：不消耗本回合行动，结算完重新进入行动阶段，
##     本回合只能发动一个启动技能（player.boot_skill_used 置位）。
##   - 7805 的 2 张弃牌在选定时就 take_from_hand 离手（不是等到 _结算魔法入门）：
##     7803 分支 1 的询问比技能结算更早，牌还留在手里会被再选一次。入弃牌堆统一放到结算做，
##     避免「弃牌前拦截」的等待链夹在后续询问中间；结算时再整组 take_from_hand 还会因为其中一张
##     已离手而整组失败，整组照样入弃就会让同一张牌在弃牌堆出现两次（引擎 1946~1956）。
##   - 7803 的弃 2 张在结算时逐张判断「还真实在手里」才离手入弃，只处理实际移除成功的牌。

const 高岭之花: int = 7801          # 被动：提炼含宝石 +1 水晶
const 魔法入门: int = 7802          # 法术技能：摸 1 展示，依序触发三组效果
const MAGIC_BANG: int = 7803        # 响应：三个独立触发
const 强予愿行: int = 7804          # 启动 / 必杀技 / 水晶：手牌调整为 4
const 友情羁绊: int = 7805          # 响应 / 必杀技 / 宝石 / 回合限定：改写 7802 的摸牌

## 7802 每一步的进度（step 由引擎按当前 SkillRun 实例隔离，每次发动从 0 开始）

## 7804 每一步的进度（选项由 available_skills 的 arg_choices 在客户端选，服务端一次行动内结算）

## 7802 三类效果的目标数上限 / 伤害点数
const 法术目标上限: int = 2
const 法术伤害值: int = 1
const 基础治疗值: int = 1

## 7804 的手牌目标张数
const 强予手牌数: int = 4

## 本回合已发动的【魔法入门】次数（7803 的「第 3 次」用；回合开始清零）
var _本回合魔法入门次数: int = 0
## 本回合是否已发动 7805【友情羁绊】（技能名带【回合限定】）
var _本回合已用友情羁绊: bool = false

## 7802 本次发动的分步数据（每次发动在 step==0 时重置）
var _7802启用友情羁绊: bool = false
var _7802友情角色: Array[int] = []
var _7802友情弃牌: Array = []          # [{pid:int, card:int}]
var _7802展示牌: Array[int] = []
## 展示摸牌是否已经压过状态（防止摸到空牌时重复压）
var _7802展示已摸: bool = false
## 友情羁绊逐个问弃牌的下标 / 展示牌是否已经做好准备（算过三组效果数量）
var _7802友情下标: int = 0
var _7802展示已准备: bool = false
var _7802有法术牌: bool = false
var _7802咏数量: int = 0
var _7802水数量: int = 0
var _7802法术目标: Array[int] = []
var _7802咏目标: Array[int] = []
var _7802水目标: Array[int] = []
var _7802_7803弃牌: Array[int] = []
var _7802_7803额外行动: bool = false
## 本次 7802 是否已经结算过：结算会返回 URGENT，引擎重入技能本体时据此直接收尾、不重复结算
var _7802已结算: bool = false
var _7802_7803加宝石: bool = false
## 本次 7802 的「展示牌」钩子是否已压栈：一个效果一个效果结算时只压一次，
## 且要压在第一个效果的状态之上（先结算「展示牌」响应，再结算伤害 / 治疗）。
var _7802展示钩子已压: bool = false
## 本次 7802 里 Magic!（7803）三项分支是否已经处理过：处理过的分支在后续选项里置灰。
var _7803弃牌已处理: bool = false
var _7803行动已处理: bool = false
var _7803宝石已处理: bool = false

## 7804 本次发动的分步数据
var _7804额外移除: bool = false
var _7804移除类型: int = 0             # 1＝宝石 / 2＝水晶（0＝不额外移除）
var _7804目标: int = -1
## 7804 里「弃到 4 张」的牌：跟选项在同一个询问里提交，结算时先弃掉再补足 / 兜底
var _7804弃牌: Array[int] = []


# ============================================================
# 回合开始：清回合限定的计数与标记
# ============================================================
func p_before_turn_begin(_ctx: Dictionary) -> int:
	_本回合魔法入门次数 = 0
	_本回合已用友情羁绊 = false
	return SUCCESS


# ============================================================
# 技能栏：7802【魔法入门】/ 7804【强予愿行】
# ============================================================
func available_skills() -> Array:
	return [
		{
			"type": GConst.ActionType.MagicSkill,
			"id": 魔法入门,
			"need_card": 0,
			"need_target": 0,
			# 两个固定选项（同魔弓【魔眼】走 arg_choices，点技能直接进二级技能栏）：
			#   1 你摸 1 张牌【强制】（不发动友情羁绊）
			#   2 -1【宝石】…（响应 7805 友情羁绊；按钮按「响应」紫色显示）
			"arg_choices": _魔法入门参数选项(),
			"enabled": true,
		},
		{
			"type": GConst.ActionType.SpecialSkill,
			"id": 强予愿行,
			"need_card": 0,
			"need_target": 0,
			# 三个消耗档由二级技能栏选（同魔弓【魔眼】）：点技能直接进二级栏，
			# 选中后在同一步选牌 / 选角色，最后按一次「确定」随行动一起提交。
			"targets": _其他角色id(),
			"arg_choices": _强予参数选项(),
			# 能量不够时照常下发、只置灰（界面看得见技能存在）；宝石可顶水晶
			"enabled": player.get_energy() > 0,
		},
	]


## 7804 是「启动」技能：不消耗本回合行动，结算完重新进入行动阶段
func is_free_skill(skill_id: int) -> bool:
	return skill_id == 强予愿行


## 7802 摸展示牌后要先让超限结算，再接着选目标 / 结算：让引擎在 URGENT 结算完重入技能本体。
## 只对 7802 生效（7804 的 URGENT 是技能收尾，不能重入）。
func 技能URGENT后重入(action: Dictionary = {}) -> bool:
	return int(action.get("action_id", 0)) == 魔法入门


# ============================================================
# 高岭之花（7801）：执行提炼时若至少含 1 宝石，你 +1 水晶
# ============================================================
func p_after_extract(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	# 只看本次提炼实际取得的星石构成（A26）；0 宝石不触发
	if int(ctx.get("gem", 0)) < 1:
		return SUCCESS
	# 能量已满时 +1 水晶无实际收益，不播报
	if player.get_energy() >= player.energy_max:
		return SUCCESS
	player.set_crystal(player.crystal + 1)
	notice_skill(高岭之花, [player.id])
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 魔法入门（7802）：摸 1 展示 → 依序触发三组效果（可被 7805 改写）
# ============================================================
## 7802 水系效果的治疗回调：作为自定义钩子压在这次技能的伤害状态之下，等伤害结算完再结算治疗
## （效果顺序：法术伤害 → 咏类伤害 → 水系治疗；治疗放在伤害之前会白挡掉伤害）。
## 引擎对每个角色都会调这个钩子名，只有本角色实现了它，其他角色不受影响。
func p_jinguizhinv_水系治疗(ctx: Dictionary) -> int:
	for 值: Variant in ctx.get("targets", []):
		施加治疗(int(值), 基础治疗值)
	engine._broadcast_game()
	return SUCCESS


## 7805 的「技能效果结束前各摸 1 张【强制】」：压在伤害 / 治疗状态之下，等它们全部结算完才摸。
## 摸牌一律走标准摸牌状态（摸完由状态边界结算超限），逐个压栈后 URGENT；重入时靠 ctx 标记只摸一次。
func p_jinguizhinv_友情摸牌(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if bool(ctx.get("已摸", false)):
		return SUCCESS
	ctx["已摸"] = true
	# 摸牌状态是 LIFO：按 targets 逆序压栈，实际结算顺序才是 targets 的正序
	var 表: Array = ctx.get("targets", [])
	var 压了: bool = false
	for i: int in range(表.size() - 1, -1, -1):
		if int(表[i]) >= 0:
			engine.push_draw(int(表[i]), 1, 友情羁绊)
			压了 = true
	return URGENT if 压了 else SUCCESS


## 7802 展示摸牌的回调：状态版强制摸牌摸完后把牌交给这里，记进展示集合供本体重入后计算。
func p_jinguizhinv_7802摸到(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	for c: Variant in ctx.get("cards", []):
		_7802展示牌.append(int(c))
	return SUCCESS


## 7802 的两个固定选项（点技能直接进二级技能栏，同魔弓【魔眼】）：
##   1 你摸 1 张牌【强制】（不发动友情羁绊）
##   2 -1【宝石】我方 2 名角色各弃 1 张牌【强制】，技能效果结束前各摸 1 张牌【强制】
## 选项 2 绑 7805 的技能号：二级栏按钮按「响应」紫色显示；2 名角色随选项同一步选。
func _魔法入门参数选项() -> Array:
	var 候选: Array[int] = _友情羁绊候选角色()
	return [
		{"text": GConst.按钮原文(魔法入门, 0), "args": [1]},
		{"text": GConst.按钮原文(魔法入门, 1),
			"args": [2], "skill_id": 友情羁绊,
			"enabled": _可发动友情羁绊() and 候选.size() >= 2,
			"need_target": 2, "targets": 候选},
	]


func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != 魔法入门:
		return GConst.GE_INVALID_ACTION
	var 参数: Array = action.get("args", [])
	var 选择: int = int(参数[0]) if not 参数.is_empty() else 1
	if 选择 < 1 or 选择 > 2:
		return GConst.GE_INVALID_ARGUMENT
	if 选择 == 2:
		# 发动友情羁绊：-1【宝石】、我方至少 2 名有手牌的角色，并且要选够 2 名
		if not _可发动友情羁绊():
			return GConst.GE_INVALID_ACTION
		var 候选: Array[int] = _友情羁绊候选角色()
		var 目标: Array[int] = []
		for 值: Variant in action.get("dst_ids", []):
			var pid2: int = int(值)
			if not 候选.has(pid2):
				return GConst.GE_INVALID_ARGUMENT
			if not 目标.has(pid2):
				目标.append(pid2)
		if 目标.size() != 2:
			return GConst.GE_INVALID_ARGUMENT
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != 魔法入门:
		return EMPTY_HANDLE
	# 新的一次发动（SkillRun 新建 → step 从 0 开始）：先初始化，再处理「友情羁绊」的配套提交。
	# **必须先初始化再判 _7802已结算**：上一次发动结束时这个标记会一直留着，若先判它，
	# 第二次起的每次发动都会被当成「URGENT 挂起后的重入」直接收尾（表现：放魔法入门会跳过自己回合）。
	if step == 0:
		_初始化魔法入门()
		_本回合魔法入门次数 += 1
		# 技能宣告在发动时播报一次即可：后面三组效果各自结算，不再重复播报
		notice_skill(魔法入门, [])
		# 友情羁绊的发动与否在魔法入门的二级技能栏里选（1 普通 / 2 响应友情羁绊），
		# 2 名角色随同一次行动一起提交，不再由服务端另发一条询问。
		var 参数0: Array = action.get("args", [])
		var 选择0: int = int(参数0[0]) if not 参数0.is_empty() else 1
		_7802友情下标 = 0
		if 选择0 == 2 and _可发动友情羁绊():
			var 候选0: Array[int] = _友情羁绊候选角色()
			var 目标0: Array[int] = []
			for 值0: Variant in action.get("dst_ids", []):
				var pid0: int = int(值0)
				if 候选0.has(pid0) and not 目标0.has(pid0):
					目标0.append(pid0)
			if 目标0.size() >= 2:
				_7802启用友情羁绊 = true
				_7802友情角色 = [目标0[0], 目标0[1]]
				# 选好 2 名角色才付 1 宝石（v_magic_skill 已校验，这里只结算）
				player.set_gem(player.gem - 1)
				_本回合已用友情羁绊 = true
				notice_skill(友情羁绊, _7802友情角色)
				engine._broadcast_game()
		# 没发动友情羁绊：先摸 1 张当展示牌（走状态版摸牌，摸完回来再准备展示）
		if not _7802启用友情羁绊 and not _7802展示已摸:
			_7802展示已摸 = true
			# step 推到下一步：摸牌回来重入时不能再跑一遍初始化（否则会再摸一张、再播报一次）
			step = 1
			engine.push_强制摸牌(player.id, 1, 魔法入门,
				"p_jinguizhinv_7802摸到", {"player": player.id})
			return URGENT
		step = 1
	# 已经结算过（URGENT 挂起后引擎重入本体）：不要再结算一次，直接收尾。
	if _7802已结算 and not 多步询问进行中(魔法入门):
		return SUCCESS
	_确保7802展示准备()
	# 魔法入门：友情羁绊逐人弃牌（循环）→ 法术/咏/水三组效果各自「选目标 → 当场结算 → 再问下一组」
	# → Magic! 三档触发（循环，最多三档）→ 结算
	return 多步询问(魔法入门, [
		{"响应": {"type": GConst.RespondType.Discard,
			"args": func(_答案: Array) -> Array:
				return [_7802友情角色[_7802友情下标], 友情羁绊, 1]},
		 "问谁": func(_答案: Array) -> int: return _7802友情角色[_7802友情下标],
		 # 强制弃牌：超时也要由答完按手牌顺序补一张
		 "可取消": false,
		 "跳过": func(_答案: Array) -> bool:
			return not _7802启用友情羁绊 or _7802友情下标 >= _7802友情角色.size(),
		 "答完": _7802友情弃牌答完,
		 "重复": func(_回: Dictionary, _答案: Array) -> bool:
			return _7802启用友情羁绊 and _7802友情下标 < _7802友情角色.size()},
		{"需目标": func(_答案: Array) -> int: return _7802法术目标数(),
		 "目标白": func(_答案: Array) -> Array: return enemy_ids(),
		 "跳过": func(_答案: Array) -> bool: return _7802法术目标数() <= 0,
		 "可取消": false, "预览基准": 法术伤害值, "预览类型": GConst.HarmType.Magic,
		 "答完": _7802法术目标答完},
		{"需目标": func(_答案: Array) -> int: return _7802咏目标数(),
		 "目标白": func(_答案: Array) -> Array: return _全体角色id(),
		 "跳过": func(_答案: Array) -> bool: return _7802咏目标数() <= 0,
		 "可取消": false, "提示序号": 1,
		 "张数": func(_答案: Array) -> int: return _7802咏数量,
		 "预览基准": 法术伤害值, "预览类型": GConst.HarmType.Magic,
		 "答完": _7802咏目标答完},
		{"需目标": func(_答案: Array) -> int: return _7802水目标数(),
		 "目标白": func(_答案: Array) -> Array: return _全体角色id(),
		 "跳过": func(_答案: Array) -> bool: return _7802水目标数() <= 0,
		 "可取消": false, "提示序号": 2,
		 "张数": func(_答案: Array) -> int: return _7802水数量,
		 "预览基准": 基础治疗值, "预览类型": GConst.预览类型_治疗,
		 "答完": _7802水目标答完},
		{"选项": func(_答案: Array) -> Array: return _7803选项(_7803下一档()),
		 "跳过": func(_答案: Array) -> bool: return _7803下一档() <= 0,
		 # 取消 / 超时＝后面的档不再问，但已经选过的档和 7805 收尾仍要结算
		 "取消": _7803取消处理,
		 "答完": _7803答完,
		 "重复": func(_回: Dictionary, _答案: Array) -> bool: return _7803下一档() > 0},
	], _7802收尾结算)


## 7803 取消 / 超时：剩余档位不再问，已选档与 7805 收尾照常结算
func _7803取消处理() -> int:
	_7803分支配平()
	return _7802收尾结算([])


## 展示牌准备（摸到展示牌之后做一次）：算出法术 / 咏 / 水各自的触发数量。
## 友情羁绊这一路不摸展示牌（展示集合就是两名队友弃掉的牌），直接准备。
func _确保7802展示准备() -> void:
	if _7802展示已准备:
		return
	if not _7802启用友情羁绊 and not _7802展示已摸:
		return
	if _7802启用友情羁绊 and _7802友情下标 < _7802友情角色.size():
		return
	_7802展示已准备 = true
	_准备7802展示()


## 法术牌效果的目标数（没有法术牌就是 0）
func _7802法术目标数() -> int:
	return mini(法术目标上限, enemy_ids().size()) if _7802有法术牌 else 0


## 咏（命格）效果的目标数
func _7802咏目标数() -> int:
	return mini(_7802咏数量, engine.order.size())


## 水（治疗）效果的目标数
func _7802水目标数() -> int:
	return mini(_7802水数量, engine.order.size())


## 友情羁绊：一个队友答完弃牌（超时 / 空回复按手牌顺序补一张）；两个都问完就摸展示牌
func _7802友情弃牌答完(回: Dictionary, _答案: Array) -> int:
	var 弃牌人: int = _7802友情角色[_7802友情下标]
	var 选牌: Array[int] = _取手牌(弃牌人, 回.get("cards", []), 1)
	var 弃出: int = int(选牌[0]) if not 选牌.is_empty() else -1
	if 弃出 < 0:
		# 原文是「各弃 1 张牌【强制】【展示】」：超时 / 空回复按手牌顺序补一张
		var 弃牌者: BattlePlayer = engine.p(弃牌人)
		if 弃牌者 != null:
			for cid替: int in 弃牌者.hand_cards:
				if 弃牌者.has_discard_card(cid替):
					弃出 = cid替
					break
	# 选定的牌当场离手：7803 的「弃 2 张」询问比技能结算更早，牌留在手里会被再选一次。
	# 入弃牌堆统一放到 _结算魔法入门：那时不再向玩家提问。
	var 已离手: bool = false
	if 弃出 >= 0:
		已离手 = engine.take_from_hand(弃牌人, [弃出])
	_7802友情弃牌.append({"pid": 弃牌人, "card": 弃出 if 已离手 else -1})
	_7802友情下标 += 1
	# 两个队友都问完：展示集合就是这两张牌，立刻准备（后面几段的触发数要靠它）
	if _7802友情下标 >= _7802友情角色.size():
		_确保7802展示准备()
	return SUCCESS


## 法术牌效果：选目标 → 当场压伤害 → 等展示响应结算完再问下一组
func _7802法术目标答完(回: Dictionary, _答案: Array) -> int:
	_7802法术目标 = _取目标(回.get("dsts", []), enemy_ids(), _7802法术目标数(), enemy_ids())
	for pid4: int in _倒序结算(_7802法术目标):
		engine.push_harm({
			"src": player.id, "dst": pid4, "point": 法术伤害值,
			"cause": 魔法入门, "type": GConst.HarmType.Magic, "is_active": false,
		})
	_压展示钩子()
	return URGENT


## 咏效果：超时只认敌人；正常手选可以是任意角色
func _7802咏目标答完(回: Dictionary, _答案: Array) -> int:
	var 咏合法: Array[int] = enemy_ids() if bool(回.get("timeout", false)) else _全体角色id()
	_7802咏目标 = _取目标(回.get("dsts", []), 咏合法, _7802咏目标数(), enemy_ids())
	for pid5: int in _倒序结算(_7802咏目标):
		engine.push_harm({
			"src": player.id, "dst": pid5, "point": 法术伤害值,
			"cause": 魔法入门, "type": GConst.HarmType.Magic, "is_active": false,
		})
	_压展示钩子()
	return URGENT


## 水效果：超时只认自己 / 队友；治疗压成钩子，等它结算完再问 7803
func _7802水目标答完(回: Dictionary, _答案: Array) -> int:
	var 水合法: Array[int] = _友方角色id() if bool(回.get("timeout", false)) else _全体角色id()
	_7802水目标 = _取目标(回.get("dsts", []), 水合法, _7802水目标数(), _友方角色id())
	engine.push(BattleEngine.SHook.new("p_jinguizhinv_水系治疗", {
		"player": player.id, "targets": _7802水目标.duplicate(),
	}, []))
	_压展示钩子()
	return URGENT


## Magic! 一档触发：选中就结算这一档；取消 / 超时 / 硬提交置灰项＝剩余档不再问
func _7803答完(回: Dictionary, _答案: Array) -> int:
	var 档: int = _7803下一档()
	var 参数: Array = 回.get("args", [])
	var 选择: int = int(参数[0]) if not 参数.is_empty() else 0
	if 选择 != 档:
		_7803分支配平()
		return SUCCESS
	if 档 == 1:
		# 「弃 2 张牌」的选牌跟选项合在同一个询问里（选项自带 need_card=2）
		var 选牌2: Array = 回.get("cards", [])
		var 有效: Array[int] = []
		for 值: Variant in 选牌2:
			if 有效.size() >= 2:
				break
			var cid: int = int(值)
			if player.has_discard_card(cid) and not 有效.has(cid):
				有效.append(cid)
		_7803弃牌已处理 = true
		if 有效.size() >= 2:
			_7802_7803弃牌 = 有效
			# 「弃 2 张牌」当场结算完：先真正入弃牌堆 + 播弃牌提示，再弹第 3 次的宝石档
			var 实际弃: Array[int] = _离手入弃(player.id, _7802_7803弃牌, MAGIC_BANG)
			if not 实际弃.is_empty():
				notice_skill(MAGIC_BANG, [player.id])
			engine._broadcast_game()
			return URGENT
		_7802_7803弃牌.clear()
		return SUCCESS
	if 档 == 2:
		_7802_7803额外行动 = true
		_7803行动已处理 = true
		return SUCCESS
	_7802_7803加宝石 = true
	_7803宝石已处理 = true
	return SUCCESS


## 三组效果 + Magic! 都走完：先记「已结算」再收尾（收尾可能压 7805 的摸牌钩子并返回 URGENT）
func _7802收尾结算(_答案: Array) -> int:
	_7802已结算 = true
	return _结算魔法入门()


## 7802 分步数据复位（每次新的技能行动）
func _初始化魔法入门() -> void:
	_7802启用友情羁绊 = false
	_7802友情角色.clear()
	_7802友情弃牌.clear()
	_7802展示牌.clear()
	_7802展示已摸 = false
	_7802展示已准备 = false
	_7802友情下标 = 0
	_7802有法术牌 = false
	_7802咏数量 = 0
	_7802水数量 = 0
	_7802法术目标.clear()
	_7802咏目标.clear()
	_7802水目标.clear()
	_7802_7803弃牌.clear()
	_7802_7803额外行动 = false
	_7802_7803加宝石 = false
	_7802已结算 = false
	_7802展示钩子已压 = false
	_7803弃牌已处理 = false
	_7803行动已处理 = false
	_7803宝石已处理 = false


## 7802 准备阶段：确定展示牌集合并算出三类效果的触发情况
func _准备7802展示() -> void:
	if _7802启用友情羁绊:
		for 项: Dictionary in _7802友情弃牌:
			_7802展示牌.append(int(项.get("card", -1)))
# 普通流程的展示牌已由状态版摸牌 + p_jinguizhinv_7802摸到 填好，
	# 这里只按展示牌计算触发情况（摸牌不在这里做，避免绕过状态边界的超限结算）
	for cid: int in _7802展示牌:
		var card: GCard = Data.get_card(cid)
		if card == null:
			continue
		if card.is_magic():
			_7802有法术牌 = true
		if card.fate_pattern_enum() == GConst.FatePattern.Cast:
			_7802咏数量 += 1
		if card.element_enum() == GConst.CardElement.Water:
			_7802水数量 += 1
	_广播7802展示()


## 把「展示牌」钩子压到栈顶：排在本次已压入的伤害 / 治疗状态之上，先结算其他角色的展示响应。
## 一次发动只压一次（一个效果一个效果结算时，第一次需要压时调用；没有可展示的牌就只置标记）。
## 返回 true＝这次真的压了状态（调用方需要返回 URGENT 等它跑完）。
func _压展示钩子() -> bool:
	if _7802展示钩子已压:
		return false
	_7802展示钩子已压 = true
	var 压了: bool = false
	if _7802启用友情羁绊:
		for 项: Dictionary in _7802友情弃牌:
			var pid: int = int(项.get("pid", -1))
			var cid: int = int(项.get("card", -1))
			if pid >= 0 and cid >= 0:
				engine.push_show_hand(pid, [cid])
				压了 = true
	elif not _7802展示牌.is_empty():
		engine.push_show_hand(player.id, _7802展示牌)
		压了 = true
	return 压了


## 把展示集合亮给全场（7805 时是那 2 张弃牌）。
## 7805 的 2 张牌分属不同角色，但它们是**同一次**【展示】；分成两条 Card 消息发出去时，
## 客户端的展示区会「新一拨顶掉上一拨」，实际只能看到最后一张 —— 整批发一条，两张一起摊开。
## （服务端的 p_show_hand 仍按各自的归属者分别压栈，展示归属不受这条广播影响。）
func _广播7802展示() -> void:
	if _7802启用友情羁绊:
		var 展示号: Array[int] = []
		for 项: Dictionary in _7802友情弃牌:
			var cid: int = int(项.get("card", -1))
			if cid >= 0 and not 展示号.has(cid):
				展示号.append(cid)
		if not 展示号.is_empty():
			engine.broadcast(GConst.Msg.Card, {
				"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
				"card_ids": 展示号, "is_real": true,
			})
	elif not _7802展示牌.is_empty():
		engine.broadcast(GConst.Msg.Card, {
			"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
			"card_ids": _7802展示牌, "is_real": true,
		})


## 7802 的「展示牌触发效果」判定：三组效果任意一组成立即算触发
func _7802触发效果() -> bool:
	return _7802有法术牌 or _7802咏数量 > 0 or _7802水数量 > 0


# ============================================================
# Magic!（7803）：三项固定选项，每次实际触发只问一档
# ============================================================
## 下一个实际触发的是哪一档（0＝没有可问的了）：
##   1 弃 2 张牌 —— 展示牌触发了效果、且手里还有 2 张牌
##   2 额外 +1【法术行动】—— 展示牌没触发任何效果
##   3 我方【战绩区】+2【宝石】—— 本回合第 3 次【魔法入门】结算时
## 三档各自独立：前两档处理完（或本来不可用）才会轮到第 3 次的宝石档，
## 所以宝石不会和前两档在同一问里同时亮。
func _7803下一档() -> int:
	if _7802触发效果():
		if player.hand_cards.size() >= 2 and not _7803弃牌已处理:
			return 1
	elif not _7803行动已处理:
		return 2
	if _本回合魔法入门次数 == 3 and not _7803宝石已处理:
		return 3
	return 0


## 本次询问的固定三选项：文案始终完整下发，只有「本次实际触发的那一档」enabled=true。
func _7803选项(档: int) -> Array:
	return [
		{"value": 1, "label": GConst.按钮原文(MAGIC_BANG, 0), "enabled": 档 == 1,
			# 选项自带选牌需求：选中它就点 2 张手牌、按一次确定一起提交（不再单独发选牌询问）
			"need_card": 2},
		{"value": 2, "label": GConst.按钮原文(MAGIC_BANG, 1), "enabled": 档 == 2},
		{"value": 3, "label": GConst.按钮原文(MAGIC_BANG, 2), "enabled": 档 == 3},
	]


## 玩家在 Magic! 选项里取消 / 超时 / 硬提交了置灰项：剩余档都不再问
func _7803分支配平() -> void:
	_7803弃牌已处理 = true
	_7803行动已处理 = true
	_7803宝石已处理 = true


## 7802 收尾：7803 的分支代价 / 奖励、7805 的弃牌入弃与「技能结束前各摸 1 张」。
## 三组伤害 / 治疗已经在各自的「选完目标」步骤里一个效果一个效果地压栈结算完
## （见 _7802法术目标答完 / _7802咏目标答完 / _7802水目标答完），这里不再重复压；7802 的播报已在发动时发过。
func _结算魔法入门() -> int:
# 7805 的 2 张弃牌在选定时已离手（见 _7802友情弃牌答完），这里统一入弃牌堆并写日志。
	# 放在结算做：这时不再向玩家提问，不会把「弃牌前拦截」的等待链夹在后续询问中间。
	if _7802启用友情羁绊:
		for 项: Dictionary in _7802友情弃牌:
			var pid2: int = int(项.get("pid", -1))
			var cid2: int = int(项.get("card", -1))
			if pid2 < 0 or cid2 < 0:
				continue
			engine.to_discard([cid2], {"owner": pid2, "source": "hand", "cause": 友情羁绊, "face_up": false})
			engine._log_discard(pid2, [cid2], false)
	# 7803 分支 1：弃 2 张牌（无后续效果，按技能字面）。只处理还真实在手里的牌：
	# 逐张判断而不是整组 take_from_hand —— 组里有一张已离手时整组会失败，整组照样入弃会造成牌数重复。
	if not _7802_7803弃牌.is_empty():
		var 实际弃2: Array[int] = _离手入弃(player.id, _7802_7803弃牌, MAGIC_BANG)
		if not 实际弃2.is_empty():
			notice_skill(MAGIC_BANG, [player.id])
	# 7803 分支 2：额外 +1 法术行动（选中即进入，不再二次追问；上面已播报 7803）
	if _7802_7803额外行动:
		notice_skill(MAGIC_BANG, [player.id])
		player.add_action(GConst.ActionType.Magic, MAGIC_BANG, true, true)
	# 7803 分支 3：我方战绩区 +2 宝石
	if _7802_7803加宝石:
		notice_skill(MAGIC_BANG, [player.id])
		engine.set_team_gem(player.color, engine.team_gem[player.color] + 2)
	# 7805：技能效果结束前，2 名角色各摸 1 张【强制】（不再并入展示集合）。
	# 三组效果已经结算完，这里压成钩子最后摸；摸牌超限交给状态边界统一结算。
	if _7802启用友情羁绊:
		var 摸牌者: Array[int] = []
		for 项2: Dictionary in _7802友情弃牌:
			var pid7: int = int(项2.get("pid", -1))
			if pid7 >= 0 and not 摸牌者.has(pid7):
				摸牌者.append(pid7)
		if not 摸牌者.is_empty():
			engine.push(BattleEngine.SHook.new("p_jinguizhinv_友情摸牌",
				{"player": player.id, "targets": 摸牌者}, []))
	engine._broadcast_game()
	return URGENT


# ============================================================
# 友情羁绊（7805）：改写 7802 的摸牌
# ============================================================
## 能否发动 7805：每回合一次、有真宝石、我方至少 2 名角色手里有牌
func _可发动友情羁绊() -> bool:
	if _本回合已用友情羁绊:
		return false
	if player.gem < 1:
		return false
	return _友情羁绊候选角色().size() >= 2


## 7805 可选的「我方角色」：同队、手里至少 1 张牌（可含自己）
func _友情羁绊候选角色() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		var p0: BattlePlayer = engine.p(pid)
		if p0 == null or p0.color != player.color:
			continue
		if p0.hand_cards.is_empty():
			continue
		out.append(pid)
	return out


# ============================================================
# 强予愿行（7804）：启动 / 必杀技 / 水晶
# ============================================================
func v_special_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != 强予愿行:
		return GConst.GE_INVALID_ACTION
	# 【水晶】费用：宝石可顶（get_energy）
	if player.get_energy() <= 0:
		return GConst.GE_INVALID_ACTION
	var 参数: Array = action.get("args", [])
	var 选择: int = int(参数[0]) if not 参数.is_empty() else 0
	# 只认三档；2/3 要求战绩区还有对应星石（选项置灰时硬提交驳回）
	if 选择 < 1 or 选择 > 3:
		return GConst.GE_INVALID_ARGUMENT
	if 选择 == 2 and engine.team_crystal[player.color] <= 0:
		return GConst.GE_INVALID_ARGUMENT
	if 选择 == 3 and engine.team_gem[player.color] <= 0:
		return GConst.GE_INVALID_ARGUMENT
	# 弃到 4 张必须执行：张数由服务端复核（同魔弓【充能】），牌必须是真实手牌
	var 弃牌: Array = action.get("card_ids", [])
	if 弃牌.size() != maxi(player.hand_cards.size() - 强予手牌数, 0):
		return GConst.GE_INVALID_ACTION
	for c: Variant in 弃牌:
		if not player.has_discard_card(int(c)):
			return GConst.GE_INVALID_ACTION
	# 2/3 必须带一个真实存在的「其他角色」
	if 选择 != 1:
		var 目标: Array = action.get("dst_ids", [])
		if 目标.is_empty() or not _其他角色id().has(int(目标[0])):
			return GConst.GE_INVALID_ARGUMENT
	return GConst.GE_SUCCESS


func p_special_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != 强予愿行:
		return EMPTY_HANDLE
	_7804额外移除 = false
	_7804移除类型 = 0
	_7804目标 = -1
	_7804弃牌.clear()
	var 参数: Array = action.get("args", [])
	var 选择: int = int(参数[0]) if not 参数.is_empty() else 1
	if 选择 != 1:
		var 目标: Array = action.get("dst_ids", [])
		if not 目标.is_empty():
			_7804额外移除 = true
			_7804移除类型 = 2 if 选择 == 2 else 1
			_7804目标 = int(目标[0])
	# 「弃到 4 张」的牌是这次行动一起提交的代价（v_special_skill 已按张数校验）
	_7804弃牌 = _取提交弃牌(action.get("card_ids", []))
	return _结算强予愿行()


## 7804 结算：付 1 水晶 →（选项 2/3）移除 1 星石 → 自己（与他人的）手牌调整为 4 张
func _结算强予愿行() -> int:
	# 费用：水晶可用宝石顶（remove_energy 先扣水晶再扣宝石）
	player.remove_energy(1)
	# 选项 2/3 的额外移除：选项可点已保证战绩区有对应星石，这里再兜一次底
	if _7804额外移除 and _7804目标 >= 0:
		if _7804移除类型 == 1 and engine.team_gem[player.color] > 0:
			engine.set_team_gem(player.color, engine.team_gem[player.color] - 1)
		elif _7804移除类型 == 2 and engine.team_crystal[player.color] > 0:
			engine.set_team_crystal(player.color, engine.team_crystal[player.color] - 1)
	player.boot_skill_used = true
	notice_skill(强予愿行, [_7804目标] if _7804目标 >= 0 else [player.id])
	var 挂起: bool = false
	# 自己的手牌调整到 4：同一问里选好的弃牌先离手入弃（正常提交正好弃到 4 张）；
	# 不足 4 张的再强制摸；若提交的牌不够（异常提交）剩下的交给 调整手牌到 再问牌主。
	if not _7804弃牌.is_empty():
		_离手入弃(player.id, _7804弃牌, 强予愿行)
		_7804弃牌.clear()
	if engine.调整手牌到(player.id, 强予手牌数, 强予愿行, false):
		挂起 = true
	# 选项 2/3：其他角色手牌调整到 4（超出由牌主自己选弃，见 A29）
	if _7804目标 >= 0 and engine.调整手牌到(_7804目标, 强予手牌数, 强予愿行, false):
		挂起 = true
	engine._broadcast_game()
	return URGENT if 挂起 else SUCCESS


## 7804 的三个选项（同魔弓【魔眼】走 available_skills 的 arg_choices，点技能直接进二级栏）：
##   1 仅调整自己手牌为 4
##   2 【战绩区】-1【水晶】调整其他角色手牌为 4
##   3 【战绩区】-1【宝石】调整其他角色手牌为 4
## 每项都自带「弃到 4 张」：need_card＝当前手牌超出的张数；2/3 再自带选 1 名其他角色。
func _强予参数选项() -> Array:
	var 需弃: int = maxi(player.hand_cards.size() - 强予手牌数, 0)
	var 候选: Array[int] = _其他角色id()
	return [
		{"text": GConst.按钮原文(强予愿行, 0), "args": [1], "enabled": true, "need_card": 需弃},
		{"text": GConst.按钮原文(强予愿行, 1), "args": [2],
			"enabled": engine.team_crystal[player.color] > 0,
			"need_card": 需弃, "need_target": 1, "targets": 候选},
		{"text": GConst.按钮原文(强予愿行, 2), "args": [3],
			"enabled": engine.team_gem[player.color] > 0,
			"need_card": 需弃, "need_target": 1, "targets": 候选},
	]


## 7804：从回复里取「弃到 4 张」的牌 —— 只认真实手牌，最多收当前超出的张数
func _取提交弃牌(ids: Array) -> Array[int]:
	var 超出: int = maxi(player.hand_cards.size() - 强予手牌数, 0)
	var 有效: Array[int] = []
	for 值: Variant in ids:
		if 有效.size() >= 超出:
			break
		var cid: int = int(值)
		if player.has_discard_card(cid) and not 有效.has(cid):
			有效.append(cid)
	return 有效


## 其他角色的 id（「将一名其他角色手牌调整为 4 张」）
func _其他角色id() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		if pid != player.id:
			out.append(pid)
	return out


# ============================================================
# 工具
# ============================================================
## 场上所有角色的 id（7802 的咏类 / 水系效果目标可以是任意角色，含自己）
func _全体角色id() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		var p0: BattlePlayer = engine.p(pid)
		if p0 != null:
			out.append(pid)
	return out


## 我方角色 id（含自己）：7802 水系治疗超时 / 跳过时的兜底目标
func _友方角色id() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		var p0: BattlePlayer = engine.p(pid)
		if p0 != null and p0.color == player.color:
			out.append(pid)
	return out


## 把牌真正移出该玩家手牌并送进弃牌堆：只处理「还真实在手里」的牌（逐张判断）。
## 引擎的 take_from_hand 是整组原子操作 —— 组里有一张已经离手就一张都不移除，调用方若照样 to_discard
## 就会让同一张牌在弃牌堆出现两次、另一张还留在手里（R78 7805↔7803 的坑）。返回实际离手入弃的牌。
func _离手入弃(pid: int, cards: Array, cause: int, 播特效: bool = true) -> Array[int]:
	var 实际: Array[int] = []
	for 值: Variant in cards:
		var cid: int = int(值)
		if cid < 0 or 实际.has(cid):
			continue
		if engine.take_from_hand(pid, [cid]):
			实际.append(cid)
	if 实际.is_empty():
		return 实际
	engine.to_discard(实际, {"owner": pid, "source": "hand", "cause": cause, "face_up": false})
	engine._log_discard(pid, 实际, 播特效)
	return 实际


## 取回复里的合法目标：去重、只保留 合法 里的；不足 n 个时按 合法 顺序补齐
## 取回复里的合法目标：去重、只保留 合法 里的；不足 n 个时按 兜底 顺序补齐。
## 兜底默认＝合法（普通情况）；魔法入门的三组效果要分开：伤害补敌人、治疗补自己 / 队友。
func _取目标(ids: Array, 合法: Array[int], n: int, 兜底: Array[int] = []) -> Array[int]:
	var out: Array[int] = []
	for 值: Variant in ids:
		if out.size() >= n:
			break
		var pid: int = int(值)
		if 合法.has(pid) and not out.has(pid):
			out.append(pid)
	if 兜底.is_empty():
		兜底 = 合法
	for pid2: int in 兜底:
		if out.size() >= n:
			break
		if 合法.has(pid2) and not out.has(pid2):
			out.append(pid2)
	return out


## 取回复里的合法手牌：去重、只保留该玩家真实手牌；不足 n 张时按手牌顺序补齐（强制弃牌用）
func _取手牌(pid: int, ids: Array, n: int) -> Array[int]:
	var out: Array[int] = []
	var p0: BattlePlayer = engine.p(pid)
	if p0 == null or n <= 0:
		return out
	for 值: Variant in ids:
		if out.size() >= n:
			break
		var cid: int = int(值)
		if p0.has_discard_card(cid) and not out.has(cid):
			out.append(cid)
	for cid2: int in p0.hand_cards:
		if out.size() >= n:
			break
		if not out.has(cid2):
			out.append(cid2)
	return out


## 群伤压栈顺序：状态是栈（LIFO），按「正序结算顺序」的逆序压栈，自己 / 下家才会最先结算
func _倒序结算(目标: Array[int]) -> Array[int]:
	var 正序: Array[int] = 结算顺序(目标)
	var out: Array[int] = []
	for i: int in range(正序.size() - 1, -1, -1):
		out.append(正序[i])
	return out
