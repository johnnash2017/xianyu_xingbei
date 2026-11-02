extends BattleRole
## 怠惰少女（roleID 106）—— 特典版本
## 技能：
##   别烦我……（10601，法术）：（你右手边最近的队友随机丢弃你 1 张手牌，并指定目标对手摸 1 张牌【强制】）
##       我方【战绩区】+1【水晶】，该对手弃 1 张法术牌【展示】；
##       （若该对手不如此做）他摸 1 张牌【强制】，你右手边最近的队友 +1【治疗】。
##   让我躺平（10602，响应）：你的回合开始时，若你手牌 > 3，目标队友 +1【治疗】，然后跳过你的行动阶段。
##   想用魔弹（10603，响应）：你需要使用【魔弹】时，弃 2 张同系牌【展示】，视为使用【魔弹】。
##   不想提炼（10604，被动）：你无法执行【提炼】；（目标队友指定【提炼】时）你 +1【宝石】，
##       移除我方【战绩区】1 星石。
##   再睡一下（10605，被动 / 必杀技 / 宝石）：【宝石】（你跳过行动阶段后强制触发【强制】）
##       弃 1 张牌，所有队友各 +1【治疗】；（若如此导致有队友【治疗】溢出）我方 +1【士气】。
##
## 口径（data-audit A41~A45）：
##   - 10601 由右手边最近的队友指定目标对手（F9 跨玩家询问 nearest_teammate_id）：目标先【强制】摸 1 张，
##     我方战绩区 +1 水晶；目标「弃 1 张法术牌【展示】」是可选响应（取消 / 超时 / 硬提交非法牌都按
##     「不如此做」结算惩罚）；「随机丢弃你 1 张手牌」走 F9 随机弃手牌，不需要任何人选牌；
##     队友的指定目标询问是**不可取消**的（can_cancel=false）：超时由引擎从下发的合法目标里代选，
##     硬提交的取消 / 空回复 / 非法目标也按 A41「AI / 掉线按默认规则代选」取第一名合法对手；
##   - 10602 在回合开始、手牌 > 3 且场上有队友时询问：治疗所选队友后请求跳过行动阶段（F9），
##     引擎的「本回合跳过行动阶段 / 来源」供 10605 读取；目标队友不含自己；
##   - 10603 是独立入口（不走【魔弹融合】）：弃 2 张彼此同系的牌【展示】，视为打出一张【魔弹】
##     （2 点、不获得【魔弹掌控】）。主动使用与响应传递两个半边都接入：
##     被【魔弹】传递时，SMissileAsk 的选牌上限放宽到 2；2 张同系牌由 v_remissile_multi 校验，
##     通过后弃掉两张、按「视为魔弹」继续传递（伤害 +1），并补发 10603 技能通知；
##   - 10604 用 v_extract 禁止自己提炼；p_after_extract（F9）在任意队友提炼结算完成后触发，
##     移除的星石类型由自己选（宝石 / 水晶固定两项都下发、不可用的置灰）；这条询问**不可取消**
##     （A44 是被动强制，玩家只选移除哪种星石）：超时 / 空回复 / 非法值按「第一种可移除的星石」
##     兜底结算，+1【宝石】照给；战绩区为空时不询问、不移除，但 +1【宝石】照给；
##   - 10605 的【宝石】必须真宝石（不能用【水晶】顶），在 p_turn_end 检查「本回合跳过行动阶段」；
##     队友治疗溢出＝加治疗前该队友已到治疗上限；士气不超过士气上限。

const BIE_FAN_WO: int = 10601          # 别烦我……（法术）
const RANG_WO_TANG_PING: int = 10602   # 让我躺平（响应 / 回合开始）
const XIANG_YONG_MO_DAN: int = 10603   # 想用魔弹（响应 / 主动使用的独立魔弹入口）
const BU_XIANG_TI_LIAN: int = 10604    # 不想提炼（被动）
const ZAI_SHUI_YI_XIA: int = 10605     # 再睡一下（被动 / 必杀技 / 宝石）

## 10601：指定目标对手后【强制】摸的张数 / 不弃法术牌时的惩罚摸牌数 / 队友治疗数
const 目标摸牌数: int = 1
const 惩罚摸牌数: int = 1
const 惩罚治疗数: int = 1
## 10603：当作【魔弹】打出的同系牌张数
const 魔弹发动牌数: int = 2
## 10605：弃牌张数 / 每个队友的治疗数
const 再睡弃牌数: int = 1
const 再睡治疗数: int = 1

## 10601 的分步进度（主动技能走 SkillRun，不经钩子轮次，用实例变量记进度）：
## 0＝还没开始 / 1＝在等右手边队友指定目标 / 2＝目标已定：等超限结算 / 等目标弃法术牌 / STEP_DONE＝已完成
var _bie_fan_step: int = 0
## 本次 10601 的队友与目标（等回复期间可能被别的钩子插入，不能现算）
var _bie_fan_队友: int = -1
var _bie_fan_目标: int = -1

## 10602 / 10604 / 10605 都是钩子里的多步询问：进度存「本次钩子的上下文」，
## 同一次钩子重入拿同一份字典，下一次触发天然是新的一份（与 role_jidushaonv 的 10704 同一写法）
const KEY_10602: String = "_daduoshaonv_10602_step"
const KEY_10604: String = "_daduoshaonv_10604_step"
const KEY_10605: String = "_daduoshaonv_10605_step"
## 钩子内「已经问过、在等回复」的阶段值（0＝还没问）
const HOOK_STEP_ASK: int = 1


# ============================================================
# 回合开始：让我躺平（10602）
# ============================================================
func p_before_turn_begin(ctx: Dictionary) -> int:
	if engine == null or player == null:
		return SUCCESS
	# 开局初始化（start_with_roles 会给每个角色发一次 init）：只做必要的同步清理，不弹询问
	if bool(ctx.get("init", false)):
		return SUCCESS
	if engine.current_id != player.id:
		return SUCCESS
	return _rang_wo_tang_ping(ctx)


## 10602：自己的回合开始、手牌 > 3 且有队友时，可让目标队友 +1 治疗并跳过自己的行动阶段。
## 查询 / 跳过都走引擎接口：请求跳过写在回合开始钩子里，轮到 SActionPhase 时生效，
## 并记下「本回合跳过行动阶段 / 来源」供 10605 读取。
func _rang_wo_tang_ping(ctx: Dictionary) -> int:
	var 阶段: int = int(ctx.get(KEY_10602, 0))
	if 阶段 >= STEP_DONE:
		return SUCCESS
	if player.hand_cards.size() <= 3 or nearest_teammate_id(player.id, true) < 0:
		ctx[KEY_10602] = STEP_DONE
		return SUCCESS
	var 目标队友: Array[int] = ally_ids()
	if 目标队友.is_empty():
		ctx[KEY_10602] = STEP_DONE
		return SUCCESS
	if 阶段 == 0:
		ctx[KEY_10602] = HOOK_STEP_ASK
		if not engine.has_reply():
			询问(player.id, RANG_WO_TANG_PING, 0, 1, GConst.CardSource.Hand, [], 0, "", [], true,
				0, -1, 目标队友)
			return WAIT
	if 阶段 != HOOK_STEP_ASK:
		return SUCCESS
	if not engine.has_reply():
		return WAIT
	ctx[KEY_10602] = STEP_DONE
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	var dsts: Array = r.get("dst_ids", [])
	if args.is_empty() or int(args[0]) != 1 or dsts.size() != 1:
		return SUCCESS
	var dst_id: int = int(dsts[0])
	if not ally_ids().has(dst_id):
		return SUCCESS
	notice_skill(RANG_WO_TANG_PING, [dst_id])
	施加治疗(dst_id, 1)
	engine.请求跳过行动阶段(RANG_WO_TANG_PING)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 技能栏：别烦我……（10601）/ 想用魔弹（10603）
# ============================================================
## 10601 摸牌后要先让超限结算，再回来问「弃 1 张法术牌」：让引擎在 URGENT 结算完重入技能本体。
## 只对 10601 生效 —— 10603 的 URGENT 是「魔弹结算完技能就结束」，重入会再打一发。
func 技能URGENT后重入(action: Dictionary = {}) -> bool:
	return int(action.get("action_id", 0)) == BIE_FAN_WO


func available_skills() -> Array:
	var 有队友: bool = nearest_teammate_id(player.id, true) >= 0
	var 魔弹牌: Array[int] = _可作魔弹的牌()
	var 落点: Array[int] = missile_targets(player.id)
	return [{
		"type": GConst.ActionType.MagicSkill,
		"id": BIE_FAN_WO,
		"need_card": 0,
		"need_target": 0,
		# 没有右手边队友 / 没有对手时照常下发、只置灰（界面看得见技能存在）
		"enabled": 有队友 and not enemy_ids().is_empty(),
	}, {
		"type": GConst.ActionType.MagicSkill,
		"id": XIANG_YONG_MO_DAN,
		"need_card": 魔弹发动牌数,
		"need_target": 1,
		"cards": 魔弹牌,
		"targets": 落点,
		# 手里没有能凑成同系两张的牌 / 没有对手时置灰
		"enabled": not 魔弹牌.is_empty() and not 落点.is_empty(),
	}]


## 手里能当 10603 发动牌的牌：至少还有另一张同元素（且非虚拟、非无元素）的牌。
## 只用于界面白名单；服务端 v_magic_skill 仍逐张复核，两边口径一致。
func _可作魔弹的牌() -> Array[int]:
	var out: Array[int] = []
	for cid: int in player.hand_cards:
		var card: GCard = Data.get_card(cid)
		if card == null or card.is_virtual or card.element_enum() <= 0:
			continue
		for 别的: int in player.hand_cards:
			if 别的 == cid:
				continue
			var c2: GCard = Data.get_card(别的)
			if c2 == null or c2.is_virtual or c2.element_enum() <= 0:
				continue
			if c2.element_enum() == card.element_enum():
				out.append(cid)
				break
	return out


func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	var 技能号: int = int(action.get("action_id", 0))
	if 技能号 == BIE_FAN_WO:
		return _v_bie_fan_wo(action)
	if 技能号 == XIANG_YONG_MO_DAN:
		return _v_xiang_yong_mo_dan(action)
	return GConst.GE_INVALID_ACTION


func p_magic_skill(action: Dictionary) -> int:
	var 技能号: int = int(action.get("action_id", 0))
	if 技能号 == BIE_FAN_WO:
		return _p_bie_fan_wo()
	if 技能号 == XIANG_YONG_MO_DAN:
		return _p_xiang_yong_mo_dan(action)
	return EMPTY_HANDLE


# ============================================================
# 别烦我……（10601）：右手边队友指定目标对手
# ============================================================
## 10601 本人不选牌 / 不选目标（目标由队友指定），所以这里只校验发动条件。
func _v_bie_fan_wo(action: Dictionary) -> int:
	if nearest_teammate_id(player.id, true) < 0:
		return GConst.GE_INVALID_ACTION
	if enemy_ids().is_empty():
		return GConst.GE_INVALID_PLAYERID
	if not (action.get("card_ids", []) as Array).is_empty() or not (action.get("dst_ids", []) as Array).is_empty():
		return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func _p_bie_fan_wo() -> int:
	# 上一次 10601 已完成：本次是新的技能行动，重置分步
	if _bie_fan_step >= STEP_DONE:
		_bie_fan_step = 0
	if _bie_fan_step == 0:
		_bie_fan_队友 = nearest_teammate_id(player.id, true)
		_bie_fan_目标 = -1
		if _bie_fan_队友 < 0 or enemy_ids().is_empty():
			_bie_fan_step = STEP_DONE
			engine.取消技能行动()
			return SUCCESS
		_bie_fan_step = 1
		# 技能原文：队友先随机丢弃你 1 张手牌，再来指定目标对手
		engine.随机弃手牌(player.id, 1, BIE_FAN_WO)
		engine._broadcast_game()
		if not engine.has_reply():
			# 由右手边队友（不是当前行动者）指定目标对手：回复仍回到本次 SkillRun。
			# can_cancel=false（A41：必须给出目标；超时由引擎从合法目标里随机代选）。
			# 询问文案直接给整段技能效果（技能太复杂，提示列那一句说不清）
			询问(_bie_fan_队友, BIE_FAN_WO, 0, 1, GConst.CardSource.Hand, [], 0, "", [], false,
				0, -1, enemy_ids(), -1, {}, 0, 0, false, [], true, -1, 0, "",
				-1, "【别烦我……】：（指定目标对手摸1张牌【强制】）我方【战绩区】+1【水晶】，"
				+ "该对手弃1张法术牌【展示】；（若该对手不如此做）他摸1张牌【强制】，你+1【治疗】。")
			return WAIT
	if _bie_fan_step == 1:
		if not engine.has_reply():
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		var dsts: Array = r.get("dst_ids", [])
		var dst_id: int = int(dsts[0]) if dsts.size() == 1 else -1
		if not enemy_ids().has(dst_id):
			# 询问不可取消：引擎超时会从合法目标里随机代选；客户端硬发的取消 / 空回复 / 非法目标
			# 也按 A41「AI / 掉线按默认规则代选」兜底成随机一名合法对手，不让队友的回复吞掉整次技能行动
			var 候选: Array[int] = enemy_ids()
			if 候选.is_empty():
				_bie_fan_step = STEP_DONE
				engine.取消技能行动()
				return SUCCESS
			dst_id = int(候选[engine._rng.randi_range(0, 候选.size() - 1)])
		_bie_fan_目标 = dst_id
		_bie_fan_step = 2
		notice_skill(BIE_FAN_WO, [dst_id])
		# 目标【强制】摸 1 张 → 我方战绩区 +1 水晶（随机弃牌已在指定目标之前做掉了）
		engine.强制摸牌(dst_id, 目标摸牌数, BIE_FAN_WO)
		engine.set_team_crystal(player.color, engine.team_crystal[player.color] + 1)
		engine._broadcast_game()
		# 目标这一摸可能把手牌摸超上限：先压超限结算（弃到上限 + 按超限张数掉士气），
		# 结算完再回来问「弃 1 张法术牌」。摸牌是【强制】（不走 p_before_draw），所以这里显式补一次；
		# 否则下一步「弃 1 张法术牌」正好把牌弃回上限，超限永远判不到。
		engine.push(BattleEngine.SHandOverflow.new())
		return URGENT
	if _bie_fan_step != 2:
		return SUCCESS
	# 第二步：超限结算完之后问目标「弃 1 张法术牌」（超时 / 取消＝不走，按惩罚结算）。
	# 手里有没有法术牌都照问一次：没有法术牌时界面整片置灰，只能取消 → 同样按「不如此做」结算
	if not engine.has_reply():
		询问(_bie_fan_目标, BIE_FAN_WO, 1, 0, GConst.CardSource.Hand, [], 0, "magic", [], true, 1)
		return WAIT
	var r2: Dictionary = take_skill_reply_full()
	_bie_fan_step = STEP_DONE
	if _目标弃出法术牌(_bie_fan_目标, r2):
		engine._broadcast_game()
		return SUCCESS
	return _bie_fan_惩罚()


## 目标「不如此做」的惩罚：他摸 1 张【强制】，右手边队友 +1【治疗】。
func _bie_fan_惩罚() -> int:
	_bie_fan_step = STEP_DONE
	engine.强制摸牌(_bie_fan_目标, 惩罚摸牌数, BIE_FAN_WO)
	var 队友: BattlePlayer = engine.p(_bie_fan_队友)
	if 队友 != null:
		施加治疗(队友.id, 惩罚治疗数)
	engine._broadcast_game()
	return SUCCESS


## 目标是否真的弃出了 1 张手牌里的法术牌【展示】；成功返回 true
func _目标弃出法术牌(dst_id: int, r: Dictionary) -> bool:
	var dst: BattlePlayer = engine.p(dst_id)
	if dst == null:
		return false
	var args: Array = r.get("args", [])
	var given: Array = r.get("card_ids", [])
	if args.is_empty() or int(args[0]) != 1 or given.is_empty():
		return false
	var cid: int = int(given[0])
	var card: GCard = Data.get_card(cid)
	if card == null or not card.is_magic() or not dst.has_hand_card(cid):
		return false
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": dst.id, "dst_id": dst.id,
		"card_ids": [cid], "is_real": true,
	})
	engine.take_from_hand(dst.id, [cid], true)
	engine.to_discard([cid], {"owner": dst.id, "source": "hand", "cause": BIE_FAN_WO})
	engine._log_discard(dst.id, [cid], false)
	return true


## 某玩家手牌里的法术牌（10601 让目标弃牌时用它下发白名单）
func _手牌法术牌(持有者: BattlePlayer) -> Array[int]:
	var out: Array[int] = []
	if 持有者 == null:
		return out
	for cid: int in 持有者.hand_cards:
		var card: GCard = Data.get_card(cid)
		if card != null and card.is_magic():
			out.append(cid)
	return out


# ============================================================
# 想用魔弹（10603）：弃 2 张同系牌，视为打出一张【魔弹】
# ============================================================
func _v_xiang_yong_mo_dan(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	var 牌结果: int = _校验同系牌(cards)
	if 牌结果 != GConst.GE_SUCCESS:
		return 牌结果
	if dsts.size() != 1:
		return GConst.GE_INVALID_PLAYERID
	if not missile_targets(player.id).has(int(dsts[0])):
		return GConst.GE_INVALID_PLAYERID
	return GConst.GE_SUCCESS


## 10603 的选牌校验：恰好 2 张、彼此不同、都在手牌、非虚拟、元素相同且有效。
## 主动使用（_v_xiang_yong_mo_dan）与响应传递（v_remissile_multi）共用同一口径。
func _校验同系牌(cards: Array) -> int:
	if cards.size() != 魔弹发动牌数:
		return GConst.GE_INVALID_CARDID
	var 已见: Array[int] = []
	var 系别: int = -1
	for 值: Variant in cards:
		var cid: int = int(值)
		if 已见.has(cid):
			return GConst.GE_INVALID_CARDID
		已见.append(cid)
		if not player.has_hand_card(cid):
			return GConst.GE_HANDCARD_NOT_FOUND
		var card: GCard = Data.get_card(cid)
		if card == null or card.is_virtual:
			return GConst.GE_INVALID_CARDID
		var 元素: int = card.element_enum()
		if 元素 <= 0:
			return GConst.GE_INVALID_CARDID
		if 系别 < 0:
			系别 = 元素
		elif 元素 != 系别:
			return GConst.GE_INVALID_CARDID
	return GConst.GE_SUCCESS


## 响应【魔弹】传递：被问到时允许选 2 张牌（能凑出同系两张时才放宽；否则保持 1 张）。
func missile_relay_card_max() -> int:
	return 魔弹发动牌数 if not _可作魔弹的牌().is_empty() else 1


func remissile_multi_skill() -> int:
	return XIANG_YONG_MO_DAN


## 响应传递的多牌校验：只校验 2 张同系，不校验目标（传递落点由引擎的魔弹链决定）。
func v_remissile_multi(cards: Array) -> int:
	return _校验同系牌(cards)


## 结算：两张同系牌【展示】弃掉，随后走与普通【魔弹】完全一致的传递询问（SMissileAsk）。
## 返回 URGENT：传递询问已经压在栈顶，本次技能行动等它结算完再跑 p_after_magic。
func _p_xiang_yong_mo_dan(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	var cid0: int = int(cards[0])
	var dst_id: int = int(dsts[0])
	notice_skill(XIANG_YONG_MO_DAN, [dst_id])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": cards.duplicate(), "is_real": true,
	})
	# 真正打出的两张牌仍写在 card_ids 里（要展示、确实进弃牌堆）；另用 as_card_id 说明这次视为【魔弹】
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Use, "src_id": player.id, "dst_id": dst_id,
		"card_ids": cards.duplicate(), "is_real": true, "as_card_id": engine.missile_as_card(cid0),
	})
	if not engine.take_from_hand(player.id, cards):
		return SUCCESS
	engine.to_discard(cards, {"owner": player.id, "source": "hand", "cause": XIANG_YONG_MO_DAN})
	engine._log_discard(player.id, cards, false)
	var 顺向: bool = dst_id == nearest_enemy_id(player.id, true)
	engine.push(BattleEngine.SMissileAsk.new(dst_id, player.id, BattleEngine.MISSILE_BASE_POINT, 顺向,
		[player.id, dst_id]))
	# 展示手牌钩子最后压：压在魔弹传递询问之上先执行（与引擎普通【魔弹】路径同一顺序）
	engine.push_show_hand(player.id, cards)
	engine._broadcast_game()
	return URGENT


# ============================================================
# 不想提炼（10604）：自己不能提炼；队友提炼后 +1 宝石并移除我方 1 星石
# ============================================================
func v_extract(_args: Array, _team_gem: int, _team_crystal: int, _dst_ids: Array) -> int:
	return GConst.GE_INVALID_ACTION


## 提炼后钩子（F9）：星石已经移动；只处理「队友提炼」，自己提炼被 v_extract 挡住了。
## 该钩子可以等待玩家输入（选移除哪种星石）。
func p_after_extract(ctx: Dictionary) -> int:
	if engine == null or player == null:
		return SUCCESS
	var 提炼者: BattlePlayer = engine.p(int(ctx.get("player", -1)))
	if 提炼者 == null or 提炼者.id == player.id or 提炼者.color != player.color:
		return SUCCESS
	var 阶段: int = int(ctx.get(KEY_10604, 0))
	if 阶段 >= STEP_DONE:
		return SUCCESS
	if 阶段 == 0:
		var 可移除: Array[int] = _可移除的星石()
		# 个人【宝石】已满、我方战绩区也没有可移除的星石：这一下什么都不会发生，不弹询问
		var 个人已满: bool = player.gem >= maxi(player.energy_max - player.crystal, 0)
		if 个人已满 and 可移除.is_empty():
			ctx[KEY_10604] = STEP_DONE
			return SUCCESS
		ctx[KEY_10604] = HOOK_STEP_ASK
		if not engine.has_reply():
			# 三项固定下发（移除宝石 / 移除水晶 / 不移除星石）：战绩区没有的那种置灰；
			# 战绩区一颗星石都没有时「不移除」可点并默认选中（星石不足就用这个选项）。
			# can_cancel=false（A44：被动强制，只能选移除哪种星石，不能整个跳过）
			询问(player.id, BU_XIANG_TI_LIAN, 0, 0, GConst.CardSource.Hand, _星石选项(可移除),
				0, "", [], false, 0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0, "",
				2 if 可移除.is_empty() else -1)
			return WAIT
	if 阶段 != HOOK_STEP_ASK:
		return SUCCESS
	if not engine.has_reply():
		return WAIT
	ctx[KEY_10604] = STEP_DONE
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	# 超时（is_timeout / 空回复）：自动选 —— 优先移除【水晶】，没有水晶再移除【宝石】，
	# 一颗都没有就不移（0＝不移除星石）
	var 超时: bool = bool(r.get("is_timeout", false)) or args.is_empty()
	var 方式: int = 0 if 超时 else int(args[0])
	if 超时:
		for 候选: int in [2, 1]:
			if _可移除的星石().has(候选):
				方式 = 候选
				break
	elif 方式 != 0 and not _可移除的星石().has(方式):
		# 非法值按「第一种可移除的星石」兜底，+1【宝石】照给（A44）；
		# 等回复期间战绩区可能被别处改动，所以这里按最新战绩区复核
		var 可移除: Array[int] = _可移除的星石()
		方式 = int(可移除[0]) if not 可移除.is_empty() else 0
	_bu_xiang_ti_lian结算(方式)
	return SUCCESS


## 可移除的星石类型：1＝宝石 / 2＝水晶（按我方战绩区现算）
func _可移除的星石() -> Array[int]:
	var out: Array[int] = []
	if engine.team_gem[player.color] > 0:
		out.append(1)
	if engine.team_crystal[player.color] > 0:
		out.append(2)
	return out


## 固定三项都下发：移除宝石 / 移除水晶 / 不移除星石；当前战绩区没有的那种标 enabled=false 置灰。
## 「不移除星石」只在战绩区一颗星石都没有时可选（星石不足就用它）。
## 纯参数选项 —— 按钮文案直接给文本，标签也用同一句（ask_skill 走 label、arg_choices 走 text）
func _星石选项(可移除: Array[int]) -> Array:
	var 无星石: bool = 可移除.is_empty()
	return [
		{"value": 1, "text": "我方【战绩区】-1【宝石】", "label": "我方【战绩区】-1【宝石】",
			"args": [1], "enabled": 可移除.has(1)},
		{"value": 2, "text": "我方【战绩区】-1【水晶】", "label": "我方【战绩区】-1【水晶】",
			"args": [2], "enabled": 可移除.has(2)},
		{"value": 0, "text": "【战绩区】星石不足，不移除星石", "label": "【战绩区】星石不足，不移除星石",
			"args": [0], "enabled": 无星石},
	]


func _bu_xiang_ti_lian结算(方式: int) -> void:
	notice_skill(BU_XIANG_TI_LIAN, [player.id])
	# 「你 +1【宝石】」：个人能量上限内加宝石
	player.set_gem(player.gem + 1)
	if 方式 == 1:
		engine.set_team_gem(player.color, engine.team_gem[player.color] - 1)
	elif 方式 == 2:
		engine.set_team_crystal(player.color, engine.team_crystal[player.color] - 1)
	engine._broadcast_game()


# ============================================================
# 再睡一下（10605）：跳过行动阶段后，支付 1【宝石】弃 1 张牌，所有队友 +1 治疗
# ============================================================
func p_turn_end(ctx: Dictionary) -> int:
	if engine == null or player == null:
		return SUCCESS
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if not engine.本回合跳过行动阶段:
		return SUCCESS
	var 阶段: int = int(ctx.get(KEY_10605, 0))
	if 阶段 >= STEP_DONE:
		return SUCCESS
	if 阶段 == 0:
		# 【宝石】必须真宝石（不能用【水晶】顶）；没牌可弃也发不了
		if player.gem <= 0 or player.hand_cards.is_empty():
			ctx[KEY_10605] = STEP_DONE
			return SUCCESS
		ctx[KEY_10605] = HOOK_STEP_ASK
		if not engine.has_reply():
			# 不可取消：有宝石就发动，玩家只能选「弃哪张」；超时由引擎兜底空回复，
			# 下面按「自动弃一张照样发动」处理。
			# 提示条用技能原本的说明（整段效果），不用提示列那一句
			询问(player.id, ZAI_SHUI_YI_XIA, 1, 0, GConst.CardSource.Hand, [], 0, "",
				player.hand_cards.duplicate(), false, 0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0, "",
				-1, GConst.skill_desc(ZAI_SHUI_YI_XIA))
			return WAIT
	if 阶段 != HOOK_STEP_ASK:
		return SUCCESS
	if not engine.has_reply():
		return WAIT
	ctx[KEY_10605] = STEP_DONE
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	# 不可取消：超时（空回复 / is_timeout）也照发动，只是牌由下面自动挑
	var 超时: bool = bool(r.get("is_timeout", false))
	if not 超时 and (args.is_empty() or int(args[0]) != 1):
		return SUCCESS
	# 等回复期间资源可能变了，付款 / 弃牌前再复核一次
	if player.gem <= 0:
		return SUCCESS
	var 选: Array[int] = []
	for 值: Variant in r.get("card_ids", []):
		var cid: int = int(值)
		if 选.size() >= 再睡弃牌数:
			break
		if player.has_discard_card(cid) and not 选.has(cid):
			选.append(cid)
	if 选.is_empty():
		if 超时:
			# 超时没选牌：自动随机弃 1 张，然后照常发动
			if player.hand_cards.is_empty():
				return SUCCESS
			player.set_gem(player.gem - 1)
			notice_skill(ZAI_SHUI_YI_XIA, [])
			engine.随机弃手牌(player.id, 再睡弃牌数, ZAI_SHUI_YI_XIA)
			_zai_shui_yi_xia结算()
			engine._broadcast_game()
		return SUCCESS
	player.set_gem(player.gem - 1)
	notice_skill(ZAI_SHUI_YI_XIA, [])
	engine.take_from_hand(player.id, 选)
	engine.to_discard(选, {"owner": player.id, "source": "hand", "cause": ZAI_SHUI_YI_XIA, "face_up": false})
	engine._log_discard(player.id, 选)
	_zai_shui_yi_xia结算()
	engine._broadcast_game()
	return SUCCESS


## 所有队友各 +1 治疗；若因此有队友治疗溢出（加之前就到上限），我方 +1 士气（不超过士气上限）。
## 「队友」不含自己（自己不会因这条回复治疗）。
func _zai_shui_yi_xia结算() -> void:
	var 溢出: bool = false
	for pid: int in ally_ids():
		var p0: BattlePlayer = engine.p(pid)
		if p0 == null:
			continue
		if p0.cross_num >= p0.cross_max:
			溢出 = true
		施加治疗(pid, 再睡治疗数)
	if not 溢出:
		return
	if engine.team_morale[player.color] >= engine.士气上限():
		return
	engine.set_morale(player.color, engine.team_morale[player.color] + 1)
	# 立刻把新士气发进快照（客户端据此写「蓝队士气 x → y」那一行），再发这条士气播报。
	# 注意不能走 _broadcast_game：它在状态推进期间只会记「待发」，要等整轮 run 结束才真的发，
	# 那时已经轮到下一回合了，日志里士气变化就跑到 [回合] 行后面去
	engine._发送对局快照()
	engine.broadcast(GConst.Msg.Gossip, {
		"type": GConst.GossipType.Morale,
		"txt": "%s 方士气 +1" % ("红" if player.color == GConst.RED else "蓝"),
		"id": player.id,
	})
