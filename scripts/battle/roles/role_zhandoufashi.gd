extends BattleRole
## 战斗法师（roleID 41）—— 异端业火版本
## 技能：
##   符文置换（4101，法术 / 回合限定）：弃 2 张同系手牌【展示】→ 摸 1 张【强制】；
##       若弃牌包含咏类命格或法术牌，额外 +1【攻击行动】。
##   附魔打击（4102，响应 / 回合限定）：主动攻击命中时②，额外 +1【法术行动】；
##       主动攻击未命中②且攻击牌为咏类命格时，额外 +1【法术行动】。
##   熵变（4103，响应）：本回合第 3 次行动结束时，消耗我方【战绩区】1【宝石】
##       或队友【能量区】1【能量】，对 2 名目标对手各造成 1 点法术伤害③。
##   魔力熵增（4104，响应 / 必杀技 / 水晶）：每次额外行动结束时支付 1【水晶】，
##       对 1 名目标对手造成 1 点法术伤害③；若未因此造成士气下降，我方【战绩区】+1【宝石】。
##
## 行动计数与通用「行动结束」上下文由 F2 提供（BattlePlayer.record_action / BattleRole.p_action_end）：
##   4103 看 ctx.action_count == 3（攻击 / 法术 / 特殊 / 额外行动统一计数）；
##   4104 看 ctx.is_extra（任何额外行动结束都触发）。
##
## 口径（见 data-audit A6~A9）：
##   - 4101 的「同系」＝两张牌彼此同元素；只能用手牌（技能写「牌【展示】」，没有盖牌来源）；
##   - 4102 用【回合限定】约束为每回合最多一次；额外法术行动进入额外行动队列，可放弃；
##   - 4103 的第三次行动包含额外行动；支付来源由发动者选；队友能量＝get_energy()（水晶 + 宝石）；
##   - 4104 的【水晶】费用按约定用 get_energy() 判断、remove_energy(1) 支付（宝石可顶水晶）。

const FU_WEN_ZHI_HUAN: int = 4101      # 符文置换（法术 / 回合限定）
const FU_MO_DA_JI: int = 4102          # 附魔打击（响应 / 回合限定）
const SHANG_BIAN: int = 4103           # 熵变（响应）
## 熵变「选支付来源 + 点队友」的内部询问号：客户端按它取「先弹选项 / 选项目标数」，
## 伤害头像提示仍挂 4103（只在选敌人那一步显示）
const SHANG_BIAN_PAY: int = GConst.技能_熵变支付
const MO_LI_SHANG_ZENG: int = 4104     # 魔力熵增（响应 / 必杀技 / 水晶）

## 4101【符文置换】本回合是否已发动（技能名带【回合限定】）
var _used_fu_wen_zhi_huan: bool = false
## 4102【附魔打击】本回合是否已触发（技能名带【回合限定】）
var _used_fu_mo_da_ji: bool = false
## 4102 的分步进度：0＝本次攻击还没处理 / FU_MO_DA_JI＝在等是否发动 / STEP_DONE＝本次已处理。
## 用自有变量而不是引擎 step：等回复期间可能被别的钩子轮次插进来。
var _fu_mo_step: int = 0

## 4103 的分步进度：0＝还没开始 / 1＝在等支付来源 / 2＝在等目标 / STEP_DONE＝本回合已处理完。
## 同一次行动结束里可能还要接着跑 4104，所以两个技能各用一套进度，最后统一压伤害。
var _shang_bian_step: int = 0
var _shang_bian_支付方式: int = 0
## 支付方式 2（消耗队友能量）时选中的那名队友；-1＝没选 / 走的是战绩区宝石
var _shang_bian_队友: int = -1
var _shang_bian_待结算目标: Array[int] = []

## 4104 的进度：按「本回合第几次行动」区分是不是同一次额外行动结束（等回复期间会被重入）。
var _mo_li_计数: int = -1
var _mo_li_step: int = 0
var _mo_li_已处理: bool = false
var _mo_li_待结算目标: int = -1
## 已经压进状态栈、等 p_harm_end 收尾的那次 4104 伤害目标（-1＝没有待收尾的伤害）
var _mo_li_已压伤害目标: int = -1
## 本次 4104 伤害结算前，目标所在队伍的士气（p_harm_end 里对比，判断「是否因此造成士气下降」）
var _mo_li_伤害前士气: int = 0


# ============================================================
# 回合开始：清回合限定标记与各技能分步进度
# ============================================================
func p_before_turn_begin(_ctx: Dictionary) -> int:
	if engine == null or player == null or int(engine.current_id) != player.id:
		return SUCCESS
	_used_fu_wen_zhi_huan = false
	_used_fu_mo_da_ji = false
	_fu_mo_step = 0
	_shang_bian_step = 0
	_shang_bian_支付方式 = 0
	_shang_bian_队友 = -1
	_shang_bian_待结算目标.clear()
	_mo_li_计数 = -1
	_mo_li_step = 0
	_mo_li_已处理 = false
	_mo_li_待结算目标 = -1
	_mo_li_已压伤害目标 = -1
	return SUCCESS


# ============================================================
# 符文置换（4101）：技能栏 + 校验 + 结算
# ============================================================
## 手里能凑成「同系两张」的牌：只有这类牌可点（客户端据此高亮，服务端仍按 v_magic_skill 兜底）
func _符文置换可选牌() -> Array[int]:
	var out: Array[int] = []
	for cid: int in player.hand_cards:
		var card: GCard = Data.get_card(cid)
		if card == null:
			continue
		for 别的: int in player.hand_cards:
			if 别的 == cid:
				continue
			var c2: GCard = Data.get_card(别的)
			if c2 != null and c2.element_enum() == card.element_enum():
				out.append(cid)
				break
	return out


func available_skills() -> Array:
	var 可选: Array[int] = _符文置换可选牌()
	# 回合限定用过了就置灰；没有同系两张也置灰 —— 都照常下发，玩家能看见技能存在
	return [{
		"type": GConst.ActionType.MagicSkill,
		"id": FU_WEN_ZHI_HUAN,
		"need_card": 2,
		"need_target": 0,
		"cards": 可选,
		"enabled": not _used_fu_wen_zhi_huan and not 可选.is_empty(),
	}]


func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != FU_WEN_ZHI_HUAN:
		return GConst.GE_INVALID_ACTION
	if _used_fu_wen_zhi_huan:
		return GConst.GE_INVALID_ACTION
	var cards: Array = action.get("card_ids", [])
	if cards.size() != 2:
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
		if 系别 < 0:
			系别 = card.element_enum()
		elif card.element_enum() != 系别:
			return GConst.GE_INVALID_CARDID
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != FU_WEN_ZHI_HUAN:
		return EMPTY_HANDLE
	var cards: Array = action.get("card_ids", [])
	if cards.size() != 2:
		return SUCCESS
	var 第一张: GCard = Data.get_card(int(cards[0]))
	var 第二张: GCard = Data.get_card(int(cards[1]))
	if 第一张 == null or 第二张 == null:
		return SUCCESS
	_used_fu_wen_zhi_huan = true
	notice_skill(FU_WEN_ZHI_HUAN, [])
	# 弃 2 张同系牌【展示】
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": cards, "is_real": true,
	})
	if not engine.take_from_hand(player.id, cards, true):
		return SUCCESS
	engine.to_discard(cards, {"owner": player.id, "source": "hand"})
	engine._log_discard(player.id, cards)
	# 弃牌含咏类命格或法术牌 → 额外 +1 攻击行动（direct：直接进入额外攻击阶段，可放弃）
	if 第一张.fate_pattern_enum() == GConst.FatePattern.Cast or 第一张.is_magic() \
			or 第二张.fate_pattern_enum() == GConst.FatePattern.Cast or 第二张.is_magic():
		player.add_action(GConst.ActionType.Attack, FU_WEN_ZHI_HUAN, true, true)
	# 摸 1 张【强制】：走 push_draw，允许【水影】这类「摸牌前」响应
	engine.push_draw(player.id, 1, FU_WEN_ZHI_HUAN)
	engine._broadcast_game()
	return URGENT


# ============================================================
# 附魔打击（4102）：主动攻击命中 / 未命中（咏类命格攻击牌）→ 额外 +1 法术行动
# ============================================================
func p_timeline_1(ctx: Dictionary) -> int:
	# 新的一次自己主动攻击宣告：清掉上一击遗留的「本次攻击已处理」标记
	if int(ctx.get("src", -1)) == player.id:
		_fu_mo_step = 0
	return SUCCESS


func p_timeline_2_hit(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	return _fu_mo_da_ji()


func p_timeline_2_miss(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	# 未命中分支只对「攻击牌为咏类命格」生效
	var card: GCard = Data.get_card(int(ctx.get("card_id", -1)))
	if card == null or card.fate_pattern_enum() != GConst.FatePattern.Cast:
		return SUCCESS
	return _fu_mo_da_ji()


## 询问是否发动【附魔打击】，同意则额外 +1 法术行动（进入额外行动队列，可放弃）
func _fu_mo_da_ji() -> int:
	if _used_fu_mo_da_ji or _fu_mo_step >= STEP_DONE:
		return SUCCESS
	if _fu_mo_step == 0:
		_fu_mo_step = FU_MO_DA_JI
		if not engine.has_reply():
			询问(player.id, FU_MO_DA_JI, 0, 0)
			return WAIT
	if _fu_mo_step != FU_MO_DA_JI:
		return SUCCESS
	if not engine.has_reply():
		return WAIT
	_fu_mo_step = STEP_DONE
	if not take_skill_reply():
		return SUCCESS
	_used_fu_mo_da_ji = true
	notice_skill(FU_MO_DA_JI, [])
	player.add_action(GConst.ActionType.Magic, FU_MO_DA_JI, true, true)
	return SUCCESS


# ============================================================
# 行动结束：4103 熵变（第 3 次）→ 4104 魔力熵增（每次额外行动）
# ============================================================
## 两个技能都挂在通用「行动结束」钩子上：同一次行动结束可能同时满足
## （第 3 次行动本身就是额外行动），所以一次 p_action_end 里顺序跑完两者的询问，
## 最后统一把伤害压进状态栈（等回复期间不提前压伤害，避免下一次询问被夹在伤害结算中间）。
## 两个技能互不影响：各自问完、各自选完目标就立刻把自己的伤害压栈结算，
## 用 URGENT 先跑完这一份伤害再回来跑另一个（以前是两者都问完再一起压栈，
## 会出现「熵变选完还要等魔力熵增选目标」的问题）。
func p_action_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	var r1: int = _处理_shang_bian(ctx)
	if r1 == WAIT:
		return WAIT
	# 熵变选完目标立刻结算；URGENT 回来后再轮到魔力熵增
	if _推送熵变伤害():
		return URGENT
	var r2: int = _处理_mo_li_shang_zeng(ctx)
	if r2 == WAIT:
		return WAIT
	if _推送魔力熵增伤害():
		return URGENT
	return SUCCESS


## 4103 熵变：本回合第 3 次行动结束时，先选支付来源，再（走队友能量时）点队友头像选人，
## 最后选 2 名目标对手
func _处理_shang_bian(ctx: Dictionary) -> int:
	if _shang_bian_step >= STEP_DONE:
		return SUCCESS
	if int(ctx.get("action_count", 0)) != 3:
		return SUCCESS
	if _shang_bian_step == 0:
		if not _shang_bian可支付(1) and not _shang_bian可支付(2):
			_shang_bian_step = STEP_DONE
			return SUCCESS
		_shang_bian_step = 1
		if not engine.has_reply():
			# 一次问完：选支付来源；选「队友能量」那一档时顺手点 1 名队友，按确定一起提交。
			# 用内部询问号 41031：它不带伤害文案，队友头像不会冒出「1 法术伤害」（技能表提示借用 4103 的）
			engine.ask_skill(player.id, SHANG_BIAN_PAY, 0, 0, GConst.CardSource.Hand,
				_shang_bian支付选项(), 0, "", [], true, 提示(SHANG_BIAN, 0), _shang_bian队友们())
			return WAIT
	if _shang_bian_step == 1:
		if not engine.has_reply():
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		var args: Array = r.get("args", [])
		var 方式: int = int(args[0]) if not args.is_empty() else 0
		if (方式 != 1 and 方式 != 2) or not _shang_bian可支付(方式):
			_shang_bian_step = STEP_DONE
			return SUCCESS
		_shang_bian_支付方式 = 方式
		_shang_bian_队友 = -1
		if 方式 == 2:
			# 队友是同一次提交里点头像选的：必须是「有能量的队友」之一
			var 候选: Array[int] = _shang_bian队友们()
			var dsts: Array = r.get("dst_ids", [])
			var 队友id: int = int(dsts[0]) if not dsts.is_empty() else -1
			if not 候选.has(队友id):
				_shang_bian_step = STEP_DONE
				return SUCCESS
			_shang_bian_队友 = 队友id
		_shang_bian_step = 3
	if _shang_bian_step != 3:
		return SUCCESS
	var 目标数: int = mini(2, enemy_ids().size())
	if 目标数 <= 0:
		_shang_bian_step = STEP_DONE
		return SUCCESS
	if not engine.has_reply():
		询问(player.id, SHANG_BIAN, 0, 目标数, GConst.CardSource.Hand, [], 0, "", [], true,
			1, -1, enemy_ids())
		return WAIT
	var r2: Dictionary = take_skill_reply_full()
	var 目标: Array[int] = []
	for 值: Variant in r2.get("dst_ids", []):
		var pid: int = int(值)
		if enemy_ids().has(pid) and not 目标.has(pid):
			目标.append(pid)
		if 目标.size() >= 目标数:
			break
	if 目标.size() < 目标数:
		_shang_bian_step = STEP_DONE
		return SUCCESS
	if not _支付_shang_bian代价():
		_shang_bian_step = STEP_DONE
		return SUCCESS
	_shang_bian_待结算目标 = 目标
	_shang_bian_step = STEP_DONE
	return SUCCESS


## 4103 的支付方式是否可行：1＝我方战绩区 1 宝石；2＝任意一名队友的能量（由玩家选具体是谁）
func _shang_bian可支付(方式: int) -> bool:
	if 方式 == 1:
		return engine.team_gem[player.color] >= 1
	if 方式 == 2:
		return not _shang_bian队友们().is_empty()
	return false


## 支付方式 2 时可选的队友：同队、不是自己、还有能量（水晶 + 宝石）
func _shang_bian队友们() -> Array[int]:
	var out: Array[int] = []
	for pid: int in ally_ids():
		var p0: BattlePlayer = engine.p(pid)
		if p0 != null and p0.get_energy() >= 1:
			out.append(pid)
	return out


## 二级选项：固定两项都下发，当前做不了的标 enabled=false 置灰（不删项）。
## 「队友能量」那一档带 need_target/targets：玩家点完选项再点 1 名队友，按确定一次性提交。
func _shang_bian支付选项() -> Array:
	var 队友们: Array[int] = _shang_bian队友们()
	return [
		{"value": 1, "label": "我方战绩区 1【宝石】", "enabled": _shang_bian可支付(1)},
		{"value": 2, "label": "队友 1【能量】", "enabled": not 队友们.is_empty(),
			"need_target": 1, "targets": 队友们},
	]


func _支付_shang_bian代价() -> bool:
	if _shang_bian_支付方式 == 1:
		if engine.team_gem[player.color] < 1:
			return false
		engine.set_team_gem(player.color, engine.team_gem[player.color] - 1)
		return true
	if _shang_bian_支付方式 == 2:
		var p0: BattlePlayer = engine.p(_shang_bian_队友)
		if p0 == null or p0.get_energy() < 1:
			return false
		p0.remove_energy(1)
		return true
	return false


## 4104 魔力熵增：每次额外行动结束都问一次；支付 1 水晶，对 1 名目标对手 1 点法术伤害
func _处理_mo_li_shang_zeng(ctx: Dictionary) -> int:
	if not bool(ctx.get("is_extra", false)):
		return SUCCESS
	var 次数: int = int(ctx.get("action_count", 0))
	if 次数 != _mo_li_计数:
		_mo_li_计数 = 次数
		_mo_li_step = 0
		_mo_li_已处理 = false
	if _mo_li_已处理:
		return SUCCESS
	if _mo_li_step == 0:
		if player.get_energy() <= 0 or enemy_ids().is_empty():
			_mo_li_step = STEP_DONE
			_mo_li_已处理 = true
			return SUCCESS
		_mo_li_step = 1
		if not engine.has_reply():
			询问(player.id, MO_LI_SHANG_ZENG, 0, 1, GConst.CardSource.Hand, [], 0, "", [], true,
				0, -1, enemy_ids())
			return WAIT
	if _mo_li_step != 1:
		return SUCCESS
	if not engine.has_reply():
		return WAIT
	_mo_li_step = STEP_DONE
	_mo_li_已处理 = true
	var r: Dictionary = take_skill_reply_full()
	var dsts: Array = r.get("dst_ids", [])
	var dst_id: int = int(dsts[0]) if not dsts.is_empty() else -1
	if not enemy_ids().has(dst_id) or player.get_energy() <= 0:
		return SUCCESS
	player.remove_energy(1)
	_mo_li_待结算目标 = dst_id
	return SUCCESS


## 4103 熵变的伤害：选完目标就压栈（返回 true＝压了，调用方返回 URGENT 让它先结算）
func _推送熵变伤害() -> bool:
	if _shang_bian_待结算目标.is_empty():
		return false
	var 目标: Array[int] = _shang_bian_待结算目标.duplicate()
	_shang_bian_待结算目标.clear()
	notice_skill(SHANG_BIAN, 目标)
	for pid: int in 目标:
		engine.push_harm({
			"src": player.id, "dst": pid, "point": 1,
			"cause": SHANG_BIAN, "type": GConst.HarmType.Magic, "is_active": false,
		})
	engine._broadcast_game()
	return true


## 4104 魔力熵增的伤害：选完目标就压栈（返回 true＝压了，调用方返回 URGENT 让它先结算）
func _推送魔力熵增伤害() -> bool:
	if _mo_li_待结算目标 < 0:
		return false
	var dst_id: int = _mo_li_待结算目标
	_mo_li_待结算目标 = -1
	var dst: BattlePlayer = engine.p(dst_id)
	if dst == null:
		return false
	# 记录伤害前的队伍士气：p_harm_end 比较它判断「是否因此造成士气下降」
	_mo_li_伤害前士气 = engine.team_morale[dst.color]
	_mo_li_已压伤害目标 = dst_id
	notice_skill(MO_LI_SHANG_ZENG, [dst_id])
	engine.push_harm({
		"src": player.id, "dst": dst_id, "point": 1,
		"cause": MO_LI_SHANG_ZENG, "type": GConst.HarmType.Magic, "is_active": false,
	})
	engine._broadcast_game()
	return true


## 4104 伤害结算完：若这次伤害没有让目标队伍掉士气，我方战绩区 +1 宝石
func p_harm_end(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("cause", 0)) != MO_LI_SHANG_ZENG:
		return SUCCESS
	if int(harm.get("src", -1)) != player.id:
		return SUCCESS
	var dst: BattlePlayer = engine.p(int(harm.get("dst", -1)))
	if dst == null or dst.id != _mo_li_已压伤害目标:
		return SUCCESS
	_mo_li_已压伤害目标 = -1
	if engine.team_morale[dst.color] >= _mo_li_伤害前士气:
		engine.set_team_gem(player.color, engine.team_gem[player.color] + 1)
		engine._broadcast_game()
	return SUCCESS
