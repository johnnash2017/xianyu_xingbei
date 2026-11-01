extends BattleRole
## 贪婪少女（roleID 87）—— 特典版本
## 技能：
##   贪欲黑洞（8701，法术 / 回合限定）：弃 1 张法术牌【展示】，我方【战绩区】+1【水晶】；
##       目标对手弃 1 张法术牌【展示】，若他不如此做，你对其造成 2 点法术伤害③，你 +1【法术行动】。
##       本回合你无法发动【亡女的金库】。
##   殓金魔法（8702，响应）：你使用【魔弹】造成伤害后⑥，我方【战绩区】+1【水晶】。
##   炼金术（8703，响应）：你的雷系或火系牌可以当【魔弹】使用（主动使用 / 响应传递）。
##   亡女的金库（8704，法术 / 必杀技 / 水晶）：支付 1【水晶】，对 2 名目标对手各造成 1 点法术伤害③；
##       可额外移除我方【战绩区】所有星石，每移除 2 星石伤害 +1；
##       若本次移除的星石中【宝石】>1，伤害结算完成后将对方 1 点士气转移给我方。
##
## 口径（见 data-audit A21 / A31 / A32 与 F1 / F8）：
##   - 8703 原文写「使用」：主动使用（技能栏里的魔弹融合入口 8703）与响应传递（v_remissile）都扩展；
##     系别走 missile_fusion_elements() 的雷 / 火，播报用本角色自己的 8703，不借用 803 / 7602；
##   - 8701 的目标是 1 名对手，弃牌可选：不弃 / 取消 / 超时回空都按「不如此做」结算惩罚；
##     发动后本回合 8704 置灰并在校验里驳回，回合开始清除（A31）；
##   - 8704 的【水晶】费用按《技能维护约定》用 get_energy() 判断、remove_energy(1) 支付（宝石可顶水晶）；
##     「每移除 2 星石 +1」向下取整、宝石 >1＝≥2、士气转移在两名目标的伤害都结算完之后（A32）。
##   - 8702 的⑥是 p_timeline_6：只认「伤害来源＝自己 且 cause＝【魔弹】」，是自动效果，不额外询问。

const TAN_YU_HEI_DONG: int = 8701     # 贪欲黑洞（法术 / 回合限定）
const LIAN_JIN_MO_FA: int = 8702      # 殓金魔法（响应 / 【魔弹】伤害后）
const LIAN_JIN_SHU: int = 8703        # 炼金术（响应 / 魔弹融合入口）
const WANG_NV_DE_JIN_KU: int = 8704   # 亡女的金库（法术 / 必杀技 / 水晶）

const TAN_YU_HARM_POINT: int = 2      # 8701：目标不弃法术牌时受到的法术伤害
const WANG_NV_BASE_POINT: int = GConst.亡女金库基础伤害  # 8704：每名目标的基础法术伤害
## 8704「每移除 2 星石，伤害 +1」：每几颗星石加 1 点
const WANG_NV每星石: int = GConst.亡女金库每星石
## 8704「本次移除的星石中【宝石】>1」：至少几颗宝石才触发士气转移
const WANG_NV宝石门槛: int = GConst.亡女金库宝石门槛

## 8701 本回合是否已发动（技能名带【回合限定】）
var _used_tan_yu: bool = false
## 8701 发动后本回合禁止发动 8704（技能原文），回合开始清除
var _locked_wan_nv: bool = false
## 8701 的分步进度：0＝还没开始 / 1＝已弃自己的牌、在等目标弃牌 / STEP_DONE＝本回合已处理完
var _tan_yu_step: int = 0
## 8704 的分步进度：0＝还没问额外移除 / 1＝在等额外移除的选项 / STEP_DONE＝本次已在结算
var _wan_nv_step: int = 0
## 8704 本次是否选择额外移除战绩区所有星石（选项值 1；未问 / 选 0 / 取消都是 false）
var _wan_nv_额外移除: bool = false
## 8704 待转移的士气（非空＝这次发动要转移 1 点）：不在伤害中间转，
## 记下来等整次法术结算完（p_after_magic，两名目标的伤害 / 摸牌 / 超限掉士气都跑完）再转
var _wan_nv_待转移: Dictionary = {}


# ============================================================
# 回合开始：清回合限定标记与分步进度
# ============================================================
func p_before_turn_begin(_ctx: Dictionary) -> int:
	if engine == null or player == null or int(engine.current_id) != player.id:
		return SUCCESS
	_used_tan_yu = false
	_locked_wan_nv = false
	_tan_yu_step = 0
	_wan_nv_step = 0
	_wan_nv_额外移除 = false
	_wan_nv_待转移 = {}
	return SUCCESS


# ============================================================
# 技能栏：8701 贪欲黑洞 / 8703 炼金术（魔弹融合入口）/ 8704 亡女的金库
# 条件不满足时照常下发、只置灰（客户端能看见技能存在）
# ============================================================
func available_skills() -> Array:
	var 对手: Array[int] = enemy_ids()
	var 法术牌: Array[int] = magic_hand_ids()
	var 魔弹牌: Array[int] = missile_fusion_hand_ids()
	var 落点: Array[int] = missile_targets(player.id)
	return [
		{
			"type": GConst.ActionType.MagicSkill,
			"id": TAN_YU_HEI_DONG,
			"need_card": 1,
			"need_target": 1,
			"targets": 对手,
			"cards": 法术牌,
			"enabled": not _used_tan_yu and not 法术牌.is_empty() and not 对手.is_empty(),
		},
		{
			"type": GConst.ActionType.MagicSkill,
			"id": LIAN_JIN_SHU,
			"need_card": 1,
			"need_target": 1,
			"targets": 落点,
			"cards": 魔弹牌,
			"enabled": not 魔弹牌.is_empty() and not 落点.is_empty(),
		},
		{
			"type": GConst.ActionType.MagicSkill,
			"id": WANG_NV_DE_JIN_KU,
			"need_card": 0,
			# 目标在二级技能栏选完星石档之后才选（同魔弓【魔眼】）：本体不给目标数，
			# 两档各自带 need_target = 2 + 对手白名单
			"need_target": 0,
			"targets": 对手,
			"arg_choices": _亡女额外移除选项(engine.战绩区构成(player.color)),
			"enabled": _可发动亡女的金库() and 对手.size() >= 2,
		},
	]


func _可发动亡女的金库() -> bool:
	if _locked_wan_nv:
		return false
	return player.get_energy() >= 1


# ============================================================
# 炼金术（8703）：雷系 / 火系牌当【魔弹】使用
# 主动使用走技能栏入口（法术技能 8703），响应传递走 v_remissile；
# 两者都复用 BattleRole 的魔弹融合链（牌表 / 落点 / 传递询问）。
# ============================================================
func missile_fusion_elements() -> Array[int]:
	return [GConst.CardElement.Thunder, GConst.CardElement.Fire]


## 本角色的魔弹融合技能号：播报 / 日志用 8703，不借用魔导师的 803 / 节日魔导的 7602
func missile_fusion_skill() -> int:
	return LIAN_JIN_SHU


# ============================================================
# 法术技能校验
# ============================================================
func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	match int(action.get("action_id", 0)):
		TAN_YU_HEI_DONG:
			return _校验贪欲黑洞(action)
		LIAN_JIN_SHU:
			return v_missile_fusion(action)
		WANG_NV_DE_JIN_KU:
			return _校验亡女的金库(action)
	return GConst.GE_INVALID_ACTION


## 8701：1 张手牌里的法术牌 + 1 名对手；回合限定用过后驳回
func _校验贪欲黑洞(action: Dictionary) -> int:
	if _used_tan_yu:
		return GConst.GE_INVALID_ACTION
	var cards: Array = action.get("card_ids", [])
	if cards.size() != 1:
		return GConst.GE_INVALID_CARDID
	var cid: int = int(cards[0])
	var card: GCard = Data.get_card(cid)
	if card == null or card.is_virtual or not card.is_magic() or not player.has_hand_card(cid):
		return GConst.GE_INVALID_CARDID
	return _校验敌人目标(action, 1)


## 8704：至少 1 点能量（水晶可被宝石顶）、选项值 0/1、恰好 2 名互不相同的对手、本回合未被 8701 锁住。
## 星石档由二级技能栏选（args[0]）后随这一手一起提交，不再由服务端补问一次
func _校验亡女的金库(action: Dictionary) -> int:
	if _locked_wan_nv:
		return GConst.GE_INVALID_ACTION
	if player.get_energy() <= 0:
		return GConst.GE_INVALID_ACTION
	var 参数: Array = action.get("args", [])
	if 参数.is_empty() or int(参数[0]) < 0 or int(参数[0]) > 1:
		return GConst.GE_INVALID_ARGUMENT
	return _校验敌人目标(action, 2)


## 目标表必须恰好 数量 名、互不相同、都是场上对手
func _校验敌人目标(action: Dictionary, 数量: int) -> int:
	var dsts: Array = action.get("dst_ids", [])
	if dsts.size() != 数量:
		return GConst.GE_INVALID_PLAYERID
	var 已见: Array[int] = []
	for 值: Variant in dsts:
		var pid: int = int(值)
		if 已见.has(pid):
			return GConst.GE_INVALID_PLAYERID
		已见.append(pid)
		var p0: BattlePlayer = engine.p(pid)
		if p0 == null or p0.color == player.color:
			return GConst.GE_INVALID_PLAYERID
	return GConst.GE_SUCCESS


# ============================================================
# 牌类校验覆写：雷系 / 火系牌可以当【魔弹】使用与响应传递
# 与魔导师 v_missile / v_remissile 同一口径，只是系别换成 8703 的两系。
# ============================================================
func v_missile(card_id: int, _dst_id: int) -> int:
	if not _can_use_missile(card_id):
		return GConst.GE_INVALID_CARDID
	return GConst.GE_SUCCESS


func v_remissile(card_id: int) -> int:
	if not _can_use_missile(card_id):
		return GConst.GE_INVALID_CARDID
	return GConst.GE_SUCCESS


# ============================================================
# 法术技能结算
# ============================================================
func p_magic_skill(action: Dictionary) -> int:
	match int(action.get("action_id", 0)):
		TAN_YU_HEI_DONG:
			return _贪欲黑洞结算(action)
		LIAN_JIN_SHU:
			return cast_missile_fusion(action)
		WANG_NV_DE_JIN_KU:
			return _亡女的金库结算(action)
	return EMPTY_HANDLE


## 8701：弃自己的法术牌【展示】→ 我方战绩区 +1 水晶 → 让目标弃 1 张法术牌；
## 目标弃出了就结束，不弃（含取消 / 非法牌 / 超时回空）则 2 点法术伤害③＋自己 +1 法术行动。
func _贪欲黑洞结算(action: Dictionary) -> int:
	if _tan_yu_step >= STEP_DONE:
		return SUCCESS
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	var dst: BattlePlayer = engine.p(int(dsts[0])) if not dsts.is_empty() else null
	if dst == null:
		return SUCCESS
	if _tan_yu_step == 0:
		# 代价牌只在第一步校验：等目标回复的重入里它已经弃掉了，不能再按手牌校验
		var cid: int = int(cards[0]) if not cards.is_empty() else -1
		var card: GCard = Data.get_card(cid)
		if card == null or not card.is_magic() or not player.has_hand_card(cid):
			return SUCCESS
		_used_tan_yu = true
		_locked_wan_nv = true
		notice_skill(TAN_YU_HEI_DONG, [dst.id])
		# 弃 1 张法术牌【展示】（自己的技能代价）
		engine.broadcast(GConst.Msg.Card, {
			"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
			"card_ids": [cid], "is_real": true,
		})
		if not engine.take_from_hand(player.id, [cid], true):
			return SUCCESS
		engine.to_discard([cid], {"owner": player.id, "source": "hand"})
		engine._log_discard(player.id, [cid], false)
		# 我方【战绩区】+1【水晶】：无条件、先结算
		engine.set_team_crystal(player.color, engine.team_crystal[player.color] + 1)
		engine._broadcast_game()
		_tan_yu_step = 1
	# 目标可选是否弃牌：不弃 / 取消 / 超时回空都按「不如此做」结算。
	# 和魔法少女【魔爆冲击】一样：目标手里有没有法术牌都照问一次，让他自己决定
	# （没牌时界面把牌整片置灰，他只能取消 → 吃 2 点法术伤害）
	if not engine.has_reply():
		询问(dst.id, TAN_YU_HEI_DONG, 1, 0, GConst.CardSource.Hand, [], 0, "magic", [], true, 1)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	_tan_yu_step = STEP_DONE
	if _目标弃法术(dst, r):
		return SUCCESS
	return _贪欲黑洞惩罚(dst.id)


## 8701 的惩罚：2 点法术伤害③ + 自己 +1【法术行动】（direct：直接进入额外法术行动）
func _贪欲黑洞惩罚(dst_id: int) -> int:
	_tan_yu_step = STEP_DONE
	engine.push_harm({
		"src": player.id, "dst": dst_id, "point": TAN_YU_HARM_POINT,
		"cause": TAN_YU_HEI_DONG, "type": GConst.HarmType.Magic, "is_active": false,
	})
	player.add_action(GConst.ActionType.Magic, TAN_YU_HEI_DONG, true, true)
	engine._broadcast_game()
	return URGENT


## 8704：星石档由二级技能栏选好、随这一手 action 一起提交（args[0] = 0 不额外移除 / 1 额外移除）；
## 扣 1 点能量后按星石数结算。伤害都结算完之后（自定义钩子）才做士气转移，
## 避免转移插在两名目标的伤害中间。
func _亡女的金库结算(action: Dictionary) -> int:
	_wan_nv_step = STEP_DONE
	var 参数: Array = action.get("args", [])
	_wan_nv_额外移除 = not 参数.is_empty() and int(参数[0]) == 1
	# 目标表在校验时已保证是 2 名对手；这里再兜一次（防御改包）
	var 目标: Array[int] = []
	for 值: Variant in action.get("dst_ids", []):
		var pid: int = int(值)
		var p0: BattlePlayer = engine.p(pid)
		if p0 != null and p0.color != player.color and not 目标.has(pid):
			目标.append(pid)
	if 目标.size() != 2 or player.get_energy() <= 0:
		_wan_nv_step = 0
		return SUCCESS
	var 移除星石: int = 0
	var 移除宝石: int = 0
	# 先播报技能，再清空战绩区 / 扣费：日志顺序与技能原文一致
	notice_skill(WANG_NV_DE_JIN_KU, 目标)
	if _wan_nv_额外移除:
		var 构成: Dictionary = engine.清空战绩区(player.color)
		移除星石 = int(构成.get("total", 0))
		移除宝石 = int(构成.get("gem", 0))
	# 支付 1【水晶】（宝石可顶）：扣费后立刻补一次对局快照，客户端能量不滞后
	player.remove_energy(1)
	engine._broadcast_game()
	@warning_ignore("integer_division")
	var 加伤: int = 移除星石 / WANG_NV每星石
	var 伤害: int = WANG_NV_BASE_POINT + 加伤
	# 士气转移排在整次结算的最后：这里只记下来，等 p_after_magic（伤害 / 摸牌 / 超限掉士气
	# 全部跑完）再真转 —— 压钩子的做法只能保证排在两名目标的伤害之后，
	# 会插在「伤害」和「因伤害超限掉的士气」之间
	if 移除宝石 >= WANG_NV宝石门槛:
		var p0: BattlePlayer = engine.p(目标[0])
		var 敌色: int = p0.color if p0 != null else -1
		_wan_nv_待转移 = {"from_color": 敌色, "to_color": player.color}
	# 两名目标按玩家点选顺序结算；伤害栈 LIFO → 逆序压栈
	for i: int in range(目标.size() - 1, -1, -1):
		engine.push_harm({
			"src": player.id, "dst": 目标[i], "point": 伤害,
			"cause": WANG_NV_DE_JIN_KU, "type": GConst.HarmType.Magic, "is_active": false,
		})
	engine._broadcast_game()
	return URGENT


## 8704 的额外移除选项：固定两项都下发，不利项也保留（按《技能维护约定》§二级技能栏选项）。
## 两档各自带「选 2 名对手」+ 对手白名单：二级技能栏打开、选完这一档才放开点头像（同【魔眼】）。
## 星石够 1 颗【宝石】门槛时在额外移除那一档后面追加士气转移的说明。
func _亡女额外移除选项(构成: Dictionary) -> Array:
	var 总数: int = int(构成.get("total", 0))
	var 宝石: int = int(构成.get("gem", 0))
	var 额外文案: String = "额外移除【战绩区】所有星石，当前 %d 颗" % 总数
	if 宝石 >= WANG_NV宝石门槛:
		额外文案 += "；将对方 1 点士气转移给我方"
	var 对手: Array[int] = enemy_ids()
	return [
		{"value": 0, "text": "不额外移除【战绩区】星石", "args": [0],
			"need_target": 2, "targets": 对手},
		{"value": 1, "text": 额外文案, "args": [1],
			"need_target": 2, "targets": 对手, "enabled": 总数 > 0},
	]


## 8704 的士气转移：整次法术结算完（两名目标的伤害 / 摸牌 / 超限掉士气都跑完）才做，
## 由 p_after_magic 承接 —— 否则会插在「伤害」和「因伤害超限掉的士气」中间
func p_after_magic(ctx: Dictionary) -> int:
	if _wan_nv_待转移.is_empty():
		return SUCCESS
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	var 待转: Dictionary = _wan_nv_待转移
	_wan_nv_待转移 = {}
	engine.转移士气(int(待转.get("from_color", -1)), int(待转.get("to_color", player.color)), 1)
	return SUCCESS


# ============================================================
# 殓金魔法（8702）：你使用【魔弹】造成伤害后⑥ → 我方【战绩区】+1【水晶】
# ⑥ 对应 p_timeline_6（治疗回应之后、按点数摸牌之前）；【魔弹】伤害的 cause 固定是 CAUSE_MISSILE。
# ============================================================
func p_timeline_6(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("src", -1)) != player.id:
		return SUCCESS
	if int(harm.get("cause", 0)) != GConst.CAUSE_MISSILE:
		return SUCCESS
	if int(harm.get("point", 0)) <= 0:
		return SUCCESS
	notice_skill(LIAN_JIN_MO_FA, [int(harm.get("dst", -1))])
	engine.set_team_crystal(player.color, engine.team_crystal[player.color] + 1)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 工具
# ============================================================
## 这张手牌能否当【魔弹】使用 / 响应传递（【魔弹】本体，或 8703 扩展的雷 / 火系牌）
func _can_use_missile(card_id: int) -> bool:
	if player == null or not player.has_hand_card(card_id):
		return false
	return can_use_as_missile(Data.get_card(card_id))


## 某玩家手牌里的法术牌（8701 让目标弃牌时下发白名单）
func _手牌法术(持有者: BattlePlayer) -> Array[int]:
	var out: Array[int] = []
	if 持有者 == null:
		return out
	for cid: int in 持有者.hand_cards:
		var c: GCard = Data.get_card(cid)
		if c != null and c.is_magic():
			out.append(cid)
	return out


## 目标是否真的弃出了 1 张手牌里的法术牌【展示】；成功返回 true
func _目标弃法术(dst: BattlePlayer, r: Dictionary) -> bool:
	var args: Array = r.get("args", [])
	var given: Array = r.get("card_ids", [])
	if args.is_empty() or int(args[0]) != 1 or given.is_empty():
		return false
	var cid: int = int(given[0])
	var card: GCard = Data.get_card(cid)
	if card == null or not card.is_magic() or dst == null or not dst.has_hand_card(cid):
		return false
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": dst.id, "dst_id": dst.id,
		"card_ids": [cid], "is_real": true,
	})
	engine.take_from_hand(dst.id, [cid], true)
	engine.to_discard([cid], {"owner": dst.id, "source": "hand"})
	engine._log_discard(dst.id, [cid], false)
	engine._broadcast_game()
	return true
