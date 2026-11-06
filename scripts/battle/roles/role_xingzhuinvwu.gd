extends BattleRole
## 星坠女巫（40）：命定之理 / 星环 / 星刻 / 群星启示 / 黄金律 / 繁星 / 影月 / 蚀日 / 创刻律动
##
## 【卢恩】＝盖牌区面朝下的牌（角色表「指示物」列 2:卢恩:6），放进时 tag = "卢恩"、open = false。
## 【律法】＝ player.laws（1=繁星 / 2=影月 / 3=蚀日，放在角色面前的标记，随快照下发）。
##
## 口径：
## 1. 【命定之理】手牌上限 = 基础值 + (1 - 律法数)：律法数每次变化后重算。
## 2. 【星环】X 由玩家实际选的地系牌张数决定：目标最多 X-1 名（可以是场上任意角色，含自己）。
##    有可选目标时必须选满 min(X-1, 场上角色数)；X-1 超过场上角色数时多出来的名额就"溢出"，
##    代价照付、不补目标。
##    结算按目标逐个进行：先 +1 治疗、再【强制】摸 1 张（等摸牌完整结算完），最后轮到自己，收尾 +1 法术行动。
## 3. 【星刻】在攻击 / 法术行动结束时先询问是否发动：确认后从牌库顶取 1 张面朝下放进盖牌区（tag="卢恩"）。
##    add_cover 自己会让出执行权先跑 p_cover_change，这里不能 return URGENT（会重入再加一张）。
## 4. 【群星启示】两种模式都走它自己的技能按钮（二级技能栏选 1/2）：
##    ① 1 张手牌作【卢恩】+ 选 1 个未拥有的【律法】+ 摸 0~1 张；
##    ② 直接选 X 个【卢恩】→ 逐个询问当前拥有的、条件成立的律法是否发动 → 由玩家选择移除 1 个【律法】。
## 5. 【黄金律】群星启示结算完、手牌 < 2 时强制摸 1 张；之后可将 1 张手牌与 1 个【卢恩】交换。
## 6. 【繁星】/【影月】/【蚀日】判定都用「本次移除的那 X 个卢恩」的牌面，且只发动**自己拥有**的律法：
##    繁星＝4 个不同系别 或 4 个不同命格；影月＝成对的同系 / 同命格数；蚀日＝每 3 个同系 / 同命格。

const MING_DING_ZHI_LI: int = 4001
const XING_HUAN: int = 4002
const XING_KE: int = 4003
const QUN_XING_QI_SHI: int = 4004
const HUANG_JIN_LV: int = 4005
const FAN_XING: int = 4006
const YING_YUE: int = 4007
const SHI_RI: int = 4008
const CHUANG_KE_LV_DONG: int = 4009

## 影月·同命格的治疗分配是 4007 的子询问（技能表不单独占行，名字/说明折到 4007）
const 影月治疗询问: int = 40071

const LU_EN标记: String = "卢恩"
const 律法_繁星: int = 1
const 律法_影月: int = 2
const 律法_蚀日: int = 3
const 律法表: Array[int] = [律法_繁星, 律法_影月, 律法_蚀日]

## 当前步骤（0＝空闲）；子流程统一由 p_xing_zhui_ask 接管
const 步_启示选律法: int = 1
const 步_启示摸牌: int = 2
const 步_黄金律交换: int = 7
const 步_创刻摸牌: int = 8
const 步_创刻卢恩: int = 9
const 步_星环结算: int = 10
const 步_律法移除: int = 11
const 步_律法选发动: int = 12
const 步_律法效果: int = 13

var _步: int = 0
## 【星环】是回合限定：本回合发动过就置位，自己回合开始时清回 false
var _星环已用: bool = false
## 【星环】逐个结算的目标队列（先 X-1 名其他角色，最后是自己）与当前下标
var _星环队列: Array[int] = []
var _星环下标: int = 0
## 群星启示②：本次要逐条询问的律法效果、当前问到第几个
var _律法队列: Array[Dictionary] = []
var _律法下标: int = 0
## 群星启示②：本次移除的卢恩判定结果（法号 → {技能号, 效果[]}）与已发动过的律法
var _律法结果: Dictionary = {}
var _已发动律法: Array[int] = []


# ============================================================
# 初始化与手牌上限
# ============================================================
func setup(p: BattlePlayer, e: BattleEngine) -> void:
	super.setup(p, e)
	# 【命定之理】：游戏初始时你拥有【律法：繁星】
	player.加律法(律法_繁星)
	_重算手牌上限()


func _重算手牌上限() -> void:
	player.hand_cards_max = GConst.HAND_CARDS_MAX + 1 - player.律法数()


func p_before_turn_begin(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) == player.id:
		_星环已用 = false
		_星环队列.clear()
		_星环下标 = 0
		_重算手牌上限()
	return SUCCESS


# ============================================================
# 技能栏
# ============================================================
func available_skills() -> Array:
	var 地系: Array[int] = _地系手牌()
	var 卢恩: Array[int] = _卢恩()
	# 【星环】的 X 由玩家实际选了几张地系牌决定：可选的牌数上限 = 地系张数；
	# 目标最多 X-1 名，**可以是场上任意角色（含自己）**；X-1 超过场上角色数时多出来的名额"溢出"，
	# 有可选目标时必须选满、只有目标不够时才允许少于 X-1。服务端在 v_magic_skill 里按同一口径复核
	var 星环技能: Dictionary = {
		"type": GConst.ActionType.MagicSkill,
		"id": XING_HUAN,
		"need_card": 1,
		"card_max": maxi(1, 地系.size()),
		"cards": 地系,
		"need_target": 0,
		"target_max_from_cards": 1,
		"enabled": not _星环已用 and not 地系.is_empty(),
		"targets": _全体角色(),
	}
	# 两个模式是固定分支：条件不满足也照样下发，用 enabled 置灰（约定 #1）
	var 模式1可用: bool = not player.hand_cards.is_empty() and player.can_add_cover_cards(1) \
		and not _未拥有律法().is_empty()
	var 启示选项: Array = [
		{
			"value": 1, "text": GConst.按钮原文(QUN_XING_QI_SHI, 0), "args": [1],
			"need_card": 1, "card_source": GConst.CardSource.Hand, "enabled": 模式1可用,
		},
		{
			"value": 2, "text": GConst.按钮原文(QUN_XING_QI_SHI, 1), "args": [2],
			# 这两个键只用于客户端下级界面的选牌配置（盖牌区 1~N 个【卢恩】）；
			# 实际提交时 args 会变成 [2, 法号]，card_ids 仍是选中的卢恩
			"need_card": 1, "card_max": maxi(卢恩.size(), 1),
			"card_source": GConst.CardSource.Cover, "cards": _牌面表(卢恩),
			"enabled": not 卢恩.is_empty(),
		},
	]
	return [
		星环技能,
		{
			# 群星启示是「启动」：必须是 SpecialSkill（见 v_special_skill / p_special_skill）
			"type": GConst.ActionType.SpecialSkill,
			"id": QUN_XING_QI_SHI,
			"arg_choices": 启示选项,
			"enabled": 模式1可用 or not 卢恩.is_empty(),
		},
		{
			"type": GConst.ActionType.MagicSkill,
			"id": CHUANG_KE_LV_DONG,
			"enabled": player.gem >= 1,
		},
	]


func is_free_skill(skill_id: int) -> bool:
	return skill_id == QUN_XING_QI_SHI


# ============================================================
# 校验
# ============================================================
func v_special_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != QUN_XING_QI_SHI:
		return GConst.GE_INVALID_ACTION
	var args: Array = action.get("args", [])
	var cards: Array = action.get("card_ids", [])
	var 模式: int = int(args[0]) if not args.is_empty() else 0
	match 模式:
		1:
			# 模式①：恰好 1 张手牌作【卢恩】，且盖牌区放得下、还有没拥有的律法可选
			if cards.size() != 1 or not player.有手牌(int(cards[0])):
				return GConst.GE_INVALID_CARDID
			if not player.can_add_cover_cards(1):
				return GConst.GE_INVALID_ACTION
			if _未拥有律法().is_empty():
				return GConst.GE_INVALID_ACTION
		2:
			# 模式②：args=[2, 法号]（0=不发动），card_ids 是本次要移除的【卢恩】。
			# 选律法 + 选卢恩在下级界面里一次提交；不发动只有在没有任何律法可发动时才允许。
			if args.size() < 2:
				return GConst.GE_INVALID_ARGUMENT
			var 法号: int = int(args[1])
			if 法号 < 0 or 法号 > 律法表.size():
				return GConst.GE_INVALID_ARGUMENT
			if cards.is_empty() or cards.size() > _卢恩().size():
				return GConst.GE_INVALID_CARDID
			var 已见: Array = []
			for c: Variant in cards:
				var cid: int = int(c)
				if 已见.has(cid) or not _是卢恩(cid):
					return GConst.GE_INVALID_CARDID
				已见.append(cid)
			var 结果: Dictionary = _判定律法(cards)
			if 法号 == 0:
				# 不发动：只有一条可用效果都没有时才允许
				for 号: int in 律法表:
					if _结果律法可用(结果, 号):
						return GConst.GE_INVALID_ACTION
			else:
				if not player.有律法(法号) or not _结果律法可用(结果, 法号):
					return GConst.GE_INVALID_ACTION
		_:
			return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	match int(action.get("action_id", 0)):
		XING_HUAN:
			# 总张数 X ＝ 选中的地系牌张数；目标最多 X-1 名（可以是场上任意角色，含自己）：
			# 有可选目标时必须选满 min(X-1, 场上角色数)，只有目标不够时才允许少于 X-1
			var cards: Array = action.get("card_ids", [])
			var dsts: Array = action.get("dst_ids", [])
			var x: int = cards.size()
			if x < 1:
				return GConst.GE_INVALID_CARDID
			if dsts.size() != mini(x - 1, _全体角色().size()):
				return GConst.GE_INVALID_ARGUMENT
			var 已见: Array = []
			for c: Variant in cards:
				var cid: int = int(c)
				var 卡: GCard = Data.get_card(cid)
				if 卡 == null or not player.有手牌(cid) or 卡.element_enum() != GConst.CardElement.Earth:
					return GConst.GE_INVALID_CARDID
			for d: Variant in dsts:
				var pid: int = int(d)
				if 已见.has(pid) or engine.p(pid) == null:
					return GConst.GE_INVALID_ARGUMENT
				已见.append(pid)
			return GConst.GE_SUCCESS
		CHUANG_KE_LV_DONG:
			if player.gem < 1:
				return GConst.GE_INVALID_ACTION
			return GConst.GE_SUCCESS
	return GConst.GE_INVALID_ACTION


# ============================================================
# 技能本体
# ============================================================
func p_special_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != QUN_XING_QI_SHI:
		return EMPTY_HANDLE
	var rc: int = _p_群星启示(action)
	if rc == SUCCESS or rc == WAIT or rc == URGENT:
		player.boot_skill_used = true
	return rc


func p_magic_skill(action: Dictionary) -> int:
	match int(action.get("action_id", 0)):
		XING_HUAN:
			return _p_星环(action)
		CHUANG_KE_LV_DONG:
			return _p_创刻律动()
	return EMPTY_HANDLE


## 4002 星环：弃 X 张地系牌【展示】 → 指定 min(X-1, 场上角色数) 名角色（含自己，有可选目标时必须选满；
## X-1 超出时多出来的名额"溢出"，代价照付）→ 他们与你各 +1 治疗、各摸 1 张【强制】，你 +1【法术行动】。
## X 由选牌张数决定；结算按目标逐个进行：先加治疗、再摸牌（等这次摸牌完整结算完），才轮到下一个目标。
func _p_星环(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	_星环已用 = true
	notice_skill(XING_HUAN, dsts)
	_展示(cards)
	# 「【展示】」要照常触发展示手牌类响应（如封印师的五系封印），所以带 已展示=true
	engine.take_from_hand(player.id, cards, true)
	engine.to_discard(cards, {"owner": player.id, "source": "hand", "cause": XING_HUAN})
	engine._log_discard(player.id, cards, true)
	_星环队列.clear()
	for d: Variant in dsts:
		_星环队列.append(int(d))
	# 最后才轮到自己（原文「…与你各 +1 治疗并各摸 1 张牌」）
	_星环队列.append(player.id)
	_星环下标 = 0
	_步 = 步_星环结算
	engine.push(BattleEngine.SHook.new("p_xing_zhui_ask", {"player": player.id}, []))
	return URGENT


## 星环的逐个结算：一个目标「先治疗 → 再摸 1 张」，摸完（含超限结算）由续跑钩子回来处理下一个
func _星环结算() -> int:
	if _星环下标 < _星环队列.size():
		var pid: int = _星环队列[_星环下标]
		_星环下标 += 1
		施加治疗(pid, 1)
		engine.push_强制摸牌(pid, 1, XING_HUAN, "p_xing_zhui_ask",
			{"player": player.id, "星环续": true})
		return URGENT
	_步 = 0
	_星环队列.clear()
	_星环下标 = 0
	player.add_action(GConst.ActionType.Magic, XING_HUAN, true, true)
	engine._broadcast_game()
	return SUCCESS


## 4004 群星启示：按二级技能栏选定的模式进入各自的子流程
func _p_群星启示(action: Dictionary) -> int:
	var args: Array = action.get("args", [])
	var cards: Array = action.get("card_ids", [])
	var 模式: int = int(args[0]) if not args.is_empty() else 0
	notice_skill(QUN_XING_QI_SHI, [player.id])
	if 模式 == 2:
		var 法号: int = int(args[1]) if args.size() > 1 else 0
		return _启示移除卢恩(cards, 法号)
	# 模式①：先把这 1 张手牌面朝下放成【卢恩】，再选律法
	var 实例: int = player.取出一张手牌(int(cards[0]))
	if 实例 < 0:
		engine.报错("【群星启示】要放成【卢恩】的手牌已不在手里", player.id)
		return SUCCESS
	engine.add_cover(player.id, [实例], player.id, QUN_XING_QI_SHI, false, LU_EN标记)
	_步 = 步_启示选律法
	engine.push(BattleEngine.SHook.new("p_xing_zhui_ask", {"player": player.id}, []))
	return URGENT


## 4009 创刻律动：付 1 宝石 → 无视手牌上限摸 0~1 张 → 最多 (1+律法数) 张手牌作【卢恩】
func _p_创刻律动() -> int:
	player.set_gem(player.gem - 1)
	notice_skill(CHUANG_KE_LV_DONG, [player.id])
	_步 = 步_创刻摸牌
	engine.push(BattleEngine.SHook.new("p_xing_zhui_ask", {"player": player.id}, []))
	return URGENT


# ============================================================
# 4003 星刻：攻击 / 法术行动结束时，牌库顶 1 张面朝下作为【卢恩】
# ============================================================
func p_action_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	var 种类: String = str(ctx.get("kind", ""))
	if 种类 != "attack" and 种类 != "magic":
		return SUCCESS
	# 同一次行动结束只问一次（问完 / 放弃后重入不再问）
	if bool(ctx.get("星刻已处理", false)):
		return SUCCESS
	if not player.can_add_cover_cards(1) or engine.deck.pile.is_empty():
		ctx["星刻已处理"] = true
		return SUCCESS
	if not engine.has_reply():
		# 不自动发动：先问是否放置【卢恩】；取消＝不发动
		询问(player.id, XING_KE, 0, 0, GConst.CardSource.Hand, [], 0, "", [], true)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	ctx["星刻已处理"] = true
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		return SUCCESS
	var 顶: Array[int] = engine.移除牌库顶(1)
	if 顶.is_empty():
		return SUCCESS
	engine.add_cover(player.id, [int(顶[0])], player.id, XING_KE, false, LU_EN标记)
	notice_skill(XING_KE, [player.id])
	# add_cover 已压入 p_cover_change，SHook 会先让出执行权再回来；这里 return URGENT 会把同一钩子
	# 重跑一遍、一次行动放满 6 个【卢恩】（约定 #13）
	return SUCCESS


# ============================================================
# 统一子流程
# ============================================================
func p_xing_zhui_ask(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	# 摸牌 / 不爆牌这类「状态结算完再继续」的续跑点：标记只消费一次，之后按 _步 走
	if bool(ctx.get("星环续", false)):
		ctx["星环续"] = false
		return _星环结算()
	if bool(ctx.get("启示摸完", false)):
		ctx["启示摸完"] = false
		return _黄金律()
	if bool(ctx.get("黄金律摸完", false)):
		ctx["黄金律摸完"] = false
		return _黄金律交换()
	if bool(ctx.get("创刻摸完", false)):
		ctx["创刻摸完"] = false
		engine.解除不爆牌(player.id)
		return _创刻选卢恩()
	match _步:
		步_启示选律法:
			return _启示选律法()
		步_启示摸牌:
			return _启示摸牌()
		步_律法效果:
			return _律法效果()
		步_律法选发动:
			return _律法选发动面板()
		步_黄金律交换:
			return _黄金律交换()
		步_创刻摸牌:
			return _创刻选摸牌()
		步_创刻卢恩:
			return _创刻选卢恩()
		步_星环结算:
			return _星环结算()
		步_律法移除:
			return _律法移除()
	return SUCCESS


# ============================================================
# 群星启示①：选律法 → 摸 0~1 张 → 黄金律
# ============================================================
## 选律法的三个选项：文案取技能表「按钮5~7」（【律法：繁星】…），
## 并带「技能组」＝对应的律法技能行 —— 客户端鼠标指向选项时弹出那颗技能的说明。
## 三个律法是固定分支：已拥有的照样列出，只置灰（约定 #1）。
func _律法选项() -> Array:
	var 选项: Array = []
	for 法号: int in 律法表:
		选项.append({
			"value": 法号,
			"label": GConst.按钮原文(QUN_XING_QI_SHI, 4 + 法号 - 1),
			"技能组": [int(GConst.律法技能.get(法号, 0))],
			"enabled": not player.有律法(法号),
		})
	return 选项


func _启示选律法() -> int:
	if not engine.has_reply():
		# 不带额外提示文案：提示条全程用【群星启示】自身的技能说明
		询问(player.id, QUN_XING_QI_SHI, 0, 0, GConst.CardSource.Hand, _律法选项(), 0, "", [], false,
			0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0, "")
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	var 号: int = int(args[0]) if not args.is_empty() else 0
	if player.有律法(号):
		if not bool(r.get("is_timeout", false)):
			engine.send(player.id, GConst.Msg.ErrorInput,
				{"error_type": GConst.CmdType.Respond, "commands": []})
			return _启示选律法()
		# 超时兜底：取第一个还没拥有的律法
		for 可选: int in 律法表:
			if not player.有律法(可选):
				号 = 可选
				break
	player.加律法(号)
	_重算手牌上限()
	_步 = 步_启示摸牌
	return URGENT


func _启示摸牌() -> int:
	if not engine.has_reply():
		# 不带额外提示文案：提示条全程用【群星启示】自身的技能说明
		询问(player.id, QUN_XING_QI_SHI, 0, 0, GConst.CardSource.Hand, _摸牌选项(QUN_XING_QI_SHI), 0, "", [], false,
			0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0, "")
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	var 摸: int = int(args[0]) if not args.is_empty() else 0
	_步 = 0
	if 摸 <= 0:
		return _黄金律()
	# 摸完再回来走黄金律：先压「继续」的钩子、再压摸牌（栈顶是摸牌）
	engine.push(BattleEngine.SHook.new("p_xing_zhui_ask",
		{"player": player.id, "启示摸完": true}, []))
	engine.push_draw(player.id, 1, QUN_XING_QI_SHI)
	return URGENT


# ============================================================
# 群星启示②：移除卢恩 → 选律法（下级界面同时选卢恩）→ 移除 1 个律法 → 黄金律
# ============================================================
func _启示移除卢恩(选择: Array, 法号: int) -> int:
	var 卢恩表: Array[int] = []
	for c: Variant in 选择:
		var 实例: int = player.盖牌实例(int(c))
		if 实例 >= 0:
			卢恩表.append(实例)
	if 卢恩表.is_empty():
		engine.报错("【群星启示】选中的牌已经不在盖牌区", player.id)
		return SUCCESS
	_展示(卢恩表)
	for 实例: int in 卢恩表:
		engine.remove_cover(player.id, [实例], player.id, QUN_XING_QI_SHI)
		engine.to_discard([实例], {"owner": player.id, "source": "cover", "cause": QUN_XING_QI_SHI})
	engine._log_discard(player.id, 卢恩表, false)
	_律法结果 = _判定律法(卢恩表)
	_已发动律法.clear()
	if 法号 <= 0:
		# 不发动：本次卢恩没有凑出任何律法，直接进「移除律法」
		_步 = 步_律法移除
	else:
		_已发动律法.append(法号)
		_载入律法效果(法号)
		_步 = 步_律法效果
	engine.push(BattleEngine.SHook.new("p_xing_zhui_ask", {"player": player.id}, []))
	return URGENT


## 把一颗律法的效果装进逐条结算队列
func _载入律法效果(法号: int) -> void:
	_律法队列.clear()
	var 效果表: Array = _律法结果[法号]["效果"]
	for 效果: Variant in 效果表:
		_律法队列.append(效果 as Dictionary)
	_律法下标 = 0


## 本次移除的卢恩还能发动哪些律法（没发动过、且至少一条效果条件成立）
func _剩余可发动() -> Array[int]:
	var out: Array[int] = []
	for 号: int in 律法表:
		if not _已发动律法.has(号) and _律法有可用效果(号):
			out.append(号)
	return out


## 选律法面板：三颗律法各一个选项（可发动的才亮），最后一项「不发动」只在没有律法可发动时亮
func _律法发动选项(剩余: Array[int]) -> Array:
	var 选项: Array = []
	for 法号: int in 律法表:
		var 技能号: int = int(GConst.律法技能.get(法号, 0))
		选项.append({
			"value": 法号,
			"label": _发动律法文案(法号),
			"skill_id": 技能号,
			"技能组": [技能号],
			"enabled": 剩余.has(法号),
		})
	选项.append({
		"value": 0,
		"label": _不发动文案(),
		"enabled": 剩余.is_empty(),
	})
	return 选项


## 选下一个要发动的律法；没有可发动的时候面板只剩「不发动」，点了才进「移除律法」
func _律法选发动面板() -> int:
	var 剩余: Array[int] = _剩余可发动()
	if not engine.has_reply():
		# 不带额外提示文案：提示条全程用【群星启示】自身的技能说明
		询问(player.id, QUN_XING_QI_SHI, 0, 0, GConst.CardSource.Hand, _律法发动选项(剩余), 0, "", [], false,
			0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0, "")
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	var 法号: int = int(args[0]) if not args.is_empty() else -1
	if 剩余.is_empty():
		# 只剩「不发动」：选它（或超时）就进移除律法
		if 法号 != 0 and not bool(r.get("is_timeout", false)):
			engine.send(player.id, GConst.Msg.ErrorInput,
				{"error_type": GConst.CmdType.Respond, "commands": []})
			return _律法选发动面板()
		_步 = 步_律法移除
		return _律法移除()
	if not 剩余.has(法号):
		if not bool(r.get("is_timeout", false)):
			engine.send(player.id, GConst.Msg.ErrorInput,
				{"error_type": GConst.CmdType.Respond, "commands": []})
			return _律法选发动面板()
		# 超时兜底：不再发动剩余律法，直接进「移除律法」（避免替玩家白嫖效果）
		_步 = 步_律法移除
		return _律法移除()
	_已发动律法.append(法号)
	_载入律法效果(法号)
	_步 = 步_律法效果
	return URGENT


## 当前律法的一条效果：先问「是否发动」（条件不满足只能取消），确认后结算；
## 需要目标的效果在同一次询问里让玩家自己选，不再自动挑目标。
func _律法效果() -> int:
	if _律法下标 >= _律法队列.size():
		return _律法效果完成()
	var 律: Dictionary = _律法队列[_律法下标]
	var 种类: String = str(律["种类"])
	var 可用: bool = bool(律.get("可用", false))
	if 种类 == "繁星队友" and ally_ids().is_empty():
		可用 = false
	if not engine.has_reply():
		var 需目标: int = 0
		var 目标: Array[int] = []
		var 预览基准: int = 0
		var 预览类型: int = 0
		if 种类 == "繁星队友":
			需目标 = 1
			目标 = ally_ids()
		elif 种类 == "影月伤害":
			需目标 = 1
			目标 = _全体角色()
			# 让头像上直接显示「X 点法术伤害」
			预览基准 = int(律.get("值", 0))
			预览类型 = GConst.HarmType.Magic
		elif 种类 == "影月治疗":
			需目标 = 1
			目标 = _我方角色()
			预览基准 = int(律.get("值", 0))
			预览类型 = GConst.预览类型_治疗
		_问律法效果(律, 需目标, 目标, 预览基准, 预览类型, 可用)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	# 条件不满足：即使硬提交也当作不发动
	if not 可用:
		_律法下标 += 1
		_步 = 步_律法效果
		return URGENT
	var dsts: Array = r.get("dst_ids", [])
	var args: Array = r.get("args", [])
	var 发动: bool = (not dsts.is_empty()) or (args.size() > 0 and int(args[0]) == 1)
	if not 发动:
		_律法下标 += 1
		_步 = 步_律法效果
		return URGENT
	var 超时: bool = bool(r.get("is_timeout", false))
	match 种类:
		"繁星AOE":
			notice_skill(FAN_XING, enemy_ids())
			for pid: int in enemy_ids():
				engine.push_harm({
					"src": player.id, "dst": pid, "point": 1,
					"cause": FAN_XING, "type": GConst.HarmType.Magic,
				})
		"繁星队友":
			var 友id: int = int(dsts[0]) if not dsts.is_empty() else -1
			if not ally_ids().has(友id):
				if not 超时:
					engine.send(player.id, GConst.Msg.ErrorInput,
						{"error_type": GConst.CmdType.Respond, "commands": []})
					return _律法效果()
				# 超时：放弃这条效果
			else:
				var 友: BattlePlayer = engine.p(友id)
				if 友 != null:
					友.set_gem(友.gem + 1)
				notice_skill(FAN_XING, [友id])
				engine._broadcast_game()
		"影月伤害":
			var 目标id: int = int(dsts[0]) if not dsts.is_empty() else -1
			if not _全体角色().has(目标id):
				if not 超时:
					engine.send(player.id, GConst.Msg.ErrorInput,
						{"error_type": GConst.CmdType.Respond, "commands": []})
					return _律法效果()
				# 超时：放弃这条效果
			else:
				notice_skill(YING_YUE, [目标id])
				engine.push_harm({
					"src": player.id, "dst": 目标id, "point": int(律["值"]),
					"cause": YING_YUE, "type": GConst.HarmType.Magic,
				})
		"影月治疗":
			var 点数: int = int(律["值"])
			var 合计: int = 0
			var 合法: bool = not dsts.is_empty() and dsts.size() <= 2 and dsts.size() == args.size()
			var 已见: Array = []
			for i: int in range(dsts.size()):
				var pid2: int = int(dsts[i])
				var 点: int = int(args[i]) if i < args.size() else 0
				if not _我方角色().has(pid2) or 已见.has(pid2) or 点 <= 0:
					合法 = false
				已见.append(pid2)
				合计 += 点
			if not 合法 or 合计 != 点数:
				if not 超时:
					engine.send(player.id, GConst.Msg.ErrorInput,
						{"error_type": GConst.CmdType.Respond, "commands": []})
					return _律法效果()
				# 超时：放弃这条效果，不替玩家选目标
			else:
				notice_skill(YING_YUE, dsts)
				for i: int in range(dsts.size()):
					施加治疗(int(dsts[i]), int(args[i]))
		"蚀日自身":
			notice_skill(SHI_RI, [player.id])
			player.set_gem(player.gem + int(律["值"]))
			engine._broadcast_game()
		"蚀日队伍":
			notice_skill(SHI_RI, [player.id])
			engine.set_team_gem(player.color, engine.team_gem[player.color] + int(律["值"]))
			engine._broadcast_game()
		_:
			engine.报错("【群星启示】未知的律法效果：%s" % 种类, player.id)
	_律法下标 += 1
	_步 = 步_律法效果
	return URGENT


## 一颗律法的两条效果都问完：回面板继续选（没有可发动的时面板只剩「不发动」，点了才进移除律法）
func _律法效果完成() -> int:
	_律法队列.clear()
	_律法下标 = 0
	_步 = 步_律法选发动
	return _律法选发动面板()


## 一条律法效果的询问：提示用该条效果自己的文案；目标在同一次里选；条件不满足时确定置灰
func _问律法效果(律: Dictionary, 需目标: int, 目标: Array[int],
		预览基准: int, 预览类型: int, 可用: bool) -> void:
	var 技能号: int = int(律.get("技能号", 0))
	var 询问号: int = int(律.get("询问技能号", 技能号))
	# 影月的治疗分配走 40071 的子询问配置（分配界面），提示仍用 4007 的效果文案
	if str(律["种类"]) == "影月治疗":
		询问号 = 影月治疗询问
	var 预览伤害: int = int(律["值"]) if str(律["种类"]) == "影月伤害" else -1
	询问(player.id, 询问号, 0, 需目标, GConst.CardSource.Hand, [], 0, "", [], true,
		0, -1, 目标, -1, {}, 预览基准, 预览类型, false, [], true, 预览伤害, 0,
		_效果提示(律), -1, "", [], [], 可用)


## 该条效果自己的提示文案（技能表「提示」列；%d 用本效果的点数填）
func _效果提示(律: Dictionary) -> String:
	var 技能号: int = int(律.get("技能号", 0))
	var 序号: int = int(律.get("提示序号", 0))
	var 文: String = GConst.提示原文(技能号, 序号)
	if not 文.is_empty() and 律.has("值") and 文.contains("%d"):
		var 值: int = int(律["值"])
		if 值 > 0:
			文 = 文 % 值
		else:
			# 条件不成立时点数不适用：显示 X，别写「造成 0 点」误导玩家
			文 = 文.replace("%d", "X")
	return 文


## 律法发动选项文案：文本表「通用_发动律法」填【律法：X】；表没加载到就按同句式兜底
func _发动律法文案(法号: int) -> String:
	var 名: String = str(GConst.律法名.get(法号, ""))
	var 模板: String = GConst.文本("通用_发动律法", false)
	if 模板.contains("%s"):
		return 模板.replace("%s", 名)
	return "发动【律法：%s】" % 名


func _不发动文案() -> String:
	var 文: String = GConst.文本("通用_不发动", false)
	return 文 if not 文.is_empty() and 文 != "通用_不发动" else "不发动"


## 移除哪个律法由玩家选：只列当前拥有的（没拥有的移除不了），文案与悬停同选律法
func _移除律法选项() -> Array:
	var 选项: Array = []
	for 法号: int in 律法表:
		if not player.有律法(法号):
			continue
		选项.append({
			"value": 法号,
			"label": GConst.按钮原文(QUN_XING_QI_SHI, 4 + 法号 - 1),
			"技能组": [int(GConst.律法技能.get(法号, 0))],
		})
	return 选项


## 群星启示②：发动完律法后，移除 1 个【律法】—— 问玩家移除哪一个
func _律法移除() -> int:
	var 选项: Array = _移除律法选项()
	if 选项.is_empty():
		_步 = 0
		return _黄金律()
	if not engine.has_reply():
		# 不带额外提示文案：提示条全程用【群星启示】自身的技能说明
		询问(player.id, QUN_XING_QI_SHI, 0, 0, GConst.CardSource.Hand, 选项, 0, "", [], false,
			0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0, "")
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	var 号: int = int(args[0]) if not args.is_empty() else -1
	if not player.有律法(号):
		if not bool(r.get("is_timeout", false)):
			engine.send(player.id, GConst.Msg.ErrorInput,
				{"error_type": GConst.CmdType.Respond, "commands": []})
			return _律法移除()
		# 超时兜底：移除选项里的第一个（最保守）
		号 = int(选项[0].get("value", -1))
	if player.有律法(号):
		player.移除律法(号)
		_重算手牌上限()
		engine._broadcast_game()
	_步 = 0
	return _黄金律()


# ============================================================
# 4005 黄金律：群星启示结算完、手牌 < 2 → 强制摸 1 张，并可将 1 张手牌与 1 个【卢恩】交换
# ============================================================
func _黄金律() -> int:
	if player.hand_cards.size() >= 2:
		return SUCCESS
	notice_skill(HUANG_JIN_LV, [player.id])
	engine.push_强制摸牌(player.id, 1, HUANG_JIN_LV, "p_xing_zhui_ask",
		{"player": player.id, "黄金律摸完": true})
	return URGENT


func _黄金律交换() -> int:
	var 卢恩: Array[int] = _卢恩()
	if player.hand_cards.is_empty() or 卢恩.is_empty():
		_步 = 0
		return SUCCESS
	if not engine.has_reply():
		# 1 张手牌 + 1 个【卢恩】，一次选完提交；取消＝不交换
		_步 = 步_黄金律交换
		询问(player.id, HUANG_JIN_LV, 2, 0, GConst.CardSource.HandOrCover, [], 2, "", [],
			true, 0, -1, [], -1, {}, 0, 0, false, [], true, -1, 1)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var 提交: Array = r.get("card_ids", [])
	if 提交.is_empty() or bool(r.get("is_timeout", false)):
		# 空提交＝取消，不交换
		_步 = 0
		return SUCCESS
	var 手: int = -1
	var 盖: int = -1
	for c: Variant in 提交:
		var cid: int = int(c)
		if 手 < 0 and player.有手牌(cid):
			手 = cid
			continue
		if 盖 < 0 and _是卢恩(cid):
			盖 = cid
	if 手 < 0 or 盖 < 0:
		engine.send(player.id, GConst.Msg.ErrorInput,
			{"error_type": GConst.CmdType.Respond, "commands": []})
		return _黄金律交换()
	var 手实例: int = player.取出实例(player.hand_cards, 手)
	var 盖实例: int = player.盖牌实例(盖)
	if 手实例 < 0 or 盖实例 < 0:
		engine.报错("【黄金律】交换的牌已不在原区域", player.id)
		_步 = 0
		return SUCCESS
	engine.remove_cover(player.id, [盖实例], player.id, HUANG_JIN_LV)
	player.add_hand_cards([盖实例])
	engine.add_cover(player.id, [手实例], player.id, HUANG_JIN_LV, false, LU_EN标记)
	_步 = 0
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 创刻律动：摸 0~1 张（无视手牌上限）→ 最多 (1+律法数) 张手牌作【卢恩】
# ============================================================
func _创刻选摸牌() -> int:
	if not engine.has_reply():
		询问(player.id, CHUANG_KE_LV_DONG, 0, 0, GConst.CardSource.Hand, _摸牌选项(CHUANG_KE_LV_DONG), 0, "", [], false,
			0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0,
			GConst.提示原文(CHUANG_KE_LV_DONG, 1))
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	var 摸: int = int(args[0]) if not args.is_empty() else 0
	_步 = 步_创刻卢恩
	if 摸 <= 0:
		return _创刻选卢恩()
	# 「无视你的手牌上限摸」：本次结算期间进入「不爆牌」，摸完在续跑钩子里解除
	engine.进入不爆牌(player.id)
	engine.push(BattleEngine.SHook.new("p_xing_zhui_ask",
		{"player": player.id, "创刻摸完": true}, []))
	engine.push_draw(player.id, 1, CHUANG_KE_LV_DONG)
	return URGENT


func _创刻选卢恩() -> int:
	var 可放: int = mini(1 + player.律法数(), player.cover_space())
	var 可选: int = mini(可放, player.hand_cards.size())
	if 可选 <= 0:
		_步 = 0
		return SUCCESS
	if not engine.has_reply():
		询问(player.id, CHUANG_KE_LV_DONG, 0, 0, GConst.CardSource.Hand, [], 可选, "",
			player.hand_cards.duplicate(), true, 0, player.id, [], 可选, {}, 0, 0, false, [], true, -1, 0,
			GConst.提示原文(CHUANG_KE_LV_DONG, 2) % 可选)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var 提交: Array = r.get("card_ids", [])
	var 放: Array = []
	for c: Variant in 提交:
		var cid: int = int(c)
		if 放.size() >= 可选 or not player.有手牌(cid):
			continue
		var 实例: int = player.取出实例(player.hand_cards, cid)
		if 实例 >= 0:
			放.append(实例)
	if 放.is_empty() and not 提交.is_empty() and not bool(r.get("is_timeout", false)):
		# 选了牌却一张都不合法＝硬提交，驳回重问；空提交（取消 / 不放）合法，直接结束
		engine.send(player.id, GConst.Msg.ErrorInput,
			{"error_type": GConst.CmdType.Respond, "commands": []})
		return _创刻选卢恩()
	_步 = 0
	if not 放.is_empty():
		engine.add_cover(player.id, 放, player.id, CHUANG_KE_LV_DONG, false, LU_EN标记)
		engine._broadcast_game()
	return SUCCESS


# ============================================================
# 律法判定
# ============================================================
## 对本次移除的卢恩做组成判定，只保留**自己拥有**的律法：
##   繁星：4 个不同系别 或 4 个不同命格（两者同时 → 双，目标队友 +1 宝石）
##   影月：成对的同系 / 同命格（对数 > 1 才发动；两个条件都满足时两个效果都算）
##   蚀日：每 3 个同系 / 每 3 个同命格
## 返回 法号 → {技能号, 效果[]}；一颗律法一个选项，效果按「先后两个条件」的顺序排。
func _判定律法(牌表: Array) -> Dictionary:
	var 系计数: Dictionary = {}
	var 命计数: Dictionary = {}
	for cid: Variant in 牌表:
		var 卡: GCard = Data.get_card(int(cid))
		if 卡 == null:
			continue
		var 系: int = 卡.element_enum()
		var 命: int = 卡.fate_pattern_enum()
		if 系 > 0:
			系计数[系] = int(系计数.get(系, 0)) + 1
		if 命 > 0:
			命计数[命] = int(命计数.get(命, 0)) + 1
	var 系对: int = 0
	var 命对: int = 0
	var 系三: int = 0
	var 命三: int = 0
	for k: Variant in 系计数.keys():
		系对 += int(系计数[k]) / 2
		系三 += int(系计数[k]) / 3
	for k2: Variant in 命计数.keys():
		命对 += int(命计数[k2]) / 2
		命三 += int(命计数[k2]) / 3
	var 四系: bool = 系计数.size() >= 4
	var 四命: bool = 命计数.size() >= 4
	var out: Dictionary = {}
	if player.有律法(律法_繁星):
		out[律法_繁星] = {
			"技能号": FAN_XING,
			"效果": [
				{"种类": "繁星AOE", "技能号": FAN_XING, "询问技能号": 40061, "提示序号": 0, "可用": 四系 or 四命},
				{"种类": "繁星队友", "技能号": FAN_XING, "提示序号": 1, "可用": 四系 and 四命},
			],
		}
	if player.有律法(律法_影月):
		out[律法_影月] = {
			"技能号": YING_YUE,
			"效果": [
				{"种类": "影月伤害", "技能号": YING_YUE, "提示序号": 0, "值": 系对, "可用": 系对 > 1},
				{"种类": "影月治疗", "技能号": YING_YUE, "提示序号": 1, "值": 命对, "可用": 命对 > 1},
			],
		}
	if player.有律法(律法_蚀日):
		out[律法_蚀日] = {
			"技能号": SHI_RI,
			"效果": [
				{"种类": "蚀日自身", "技能号": SHI_RI, "提示序号": 0, "值": 系三, "可用": 系三 > 0},
				{"种类": "蚀日队伍", "技能号": SHI_RI, "提示序号": 1, "值": 命三, "可用": 命三 > 0},
			],
		}
	return out


## 判定结果里这颗律法有没有「条件成立」的效果（v_* 校验用，不依赖当前 _律法结果）
func _结果律法可用(结果: Dictionary, 法号: int) -> bool:
	if not 结果.has(法号):
		return false
	var 效果表: Array = 结果[法号]["效果"]
	for 效果: Variant in 效果表:
		if bool((效果 as Dictionary).get("可用", false)):
			return true
	return false


## 一颗律法里还有没有「条件成立」的效果（面板选项是否点亮看它）
func _律法有可用效果(法号: int) -> bool:
	return _结果律法可用(_律法结果, 法号)


# ============================================================
# 小工具
# ============================================================
func _地系手牌() -> Array[int]:
	return hand_ids_where(
		func(_cid: int, c: GCard) -> bool: return c.element_enum() == GConst.CardElement.Earth)


func _卢恩() -> Array[int]:
	return player.盖牌按标记(LU_EN标记)


func _是卢恩(id: int) -> bool:
	var 实例: int = player.盖牌实例(id)
	return 实例 >= 0 and player.盖牌标记(实例) == LU_EN标记


func _未拥有律法() -> Array[int]:
	var out: Array[int] = []
	for 号: int in 律法表:
		if not player.有律法(号):
			out.append(号)
	return out


func _全体角色() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		if engine.p(pid) != null:
			out.append(pid)
	return out


func _我方角色() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		var pp: BattlePlayer = engine.p(pid)
		if pp != null and pp.color == player.color:
			out.append(pid)
	return out


## 「摸 0~1 张」的可选项：文案取技能表「按钮3 / 按钮4」（不摸牌 / 摸 1 张牌），
## 不允许只写数字（选项禁止纯数字，见技能维护约定）。
## 注意：这里走的是 ask_skill 的 options，客户端读的是 `label`（不是 arg_choices 的 `text`），
## 键写错会退回显示选项值（0 / 1）。
func _摸牌选项(技能号: int) -> Array:
	return [
		{"value": 0, "label": GConst.按钮原文(技能号, 2)},
		{"value": 1, "label": GConst.按钮原文(技能号, 3)},
	]


## 展示这几张牌（广播 Card.Show；牌只做展示，移动由调用方做）
func _展示(cards: Array) -> void:
	if cards.is_empty():
		return
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": _牌面表(cards), "is_real": true,
	})


## 选项里的牌白名单要按牌面下发（arg_choices 不经过引擎折面）
func _牌面表(cards: Array) -> Array:
	var out: Array = []
	for c: Variant in cards:
		out.append(GConst.牌号(int(c)))
	return out
