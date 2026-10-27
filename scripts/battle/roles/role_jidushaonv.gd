extends BattleRole
## 忌妒少女（roleID 107）—— 特典版本
## 技能：
##   醋意羞心（10701，响应）：主动攻击未命中时②，目标角色弃 1 张法术牌【展示】；
##       若他不如此做，你对他造成 2 点法术伤害③，我方【战绩区】+1【水晶】
##   虚荣掌握（10702，响应）：主动攻击命中时②，额外 +1【法术行动】；
##       本次法术行动只能使用【魔弹】，且可以选择逆向传递（＝这份额外行动内的临时【魔弹掌控】）
##   相思病（10703，响应）：你的地系牌或风系牌可以当【魔弹】使用（主动使用 / 响应传递）
##   嫉妒追放（10704，响应 / 必杀技 / 回合限定 / 水晶）：【攻击行动】或【法术行动】后，
##       支付 1【水晶】额外 +1【攻击行动】；本次攻击行动只能攻击手牌数大于你的目标对手
##
## 口径（见 data-audit A46~A48 与 A21）：
##   - 10701 先问发动者是否发动（响应技能），目标强制弃 1 张法术牌（A46，不可取消），弃不出
##     （没有 / 硬提交非法牌 / 超时回空）就直接吃 2 点法术伤害，同时我方【战绩区】+1【水晶】；
##   - 10702 的逆向只在它授予的那份额外法术行动内有效：has_missile_mastery() 只在
##     「当前额外行动阶段的来源＝10702」时返回 true；「只能使用【魔弹】」由
##     extra_action_card_ids(10702, Magic) 的两套白名单实现：普通法术行动只放行【魔弹】本体，
##     10703 技能行动另放行地/风系牌当【魔弹】——地/风系【圣盾】/【虚弱】/【中毒】不能借
##     普通法术行动结算；
##   - 10703 同时扩展「主动使用」（技能栏里的魔弹融合入口 10703）与「响应传递」（v_remissile），
##     按 A21：10703 原文写「使用」，两组都扩；
##   - 10704 的【水晶】费用按约定用 get_energy() 判断、remove_energy(1) 支付（宝石可顶水晶）；
##     目标限制按「宣告时比较双方手牌数」现算（extra_action_targets）。
##
## 牌类校验与魔导师（8）/ 节日魔导（76）的【魔弹融合】同一条链：系别由 missile_fusion_elements()
## 配置，本角色是地 / 风；播报 / 提示用本角色自己的 10703，不借用 803 / 7602。

const CU_YI_XIU_XIN: int = 10701      # 醋意羞心（响应）
const XU_RONG_ZHANG_WO: int = 10702   # 虚荣掌握（响应）
const XIANG_SI_BING: int = 10703      # 相思病（响应 / 魔弹融合入口）
const JI_DU_ZHUI_FANG: int = 10704    # 嫉妒追放（响应 / 必杀技 / 回合限定）

const CU_YI_HARM_POINT: int = 2       # 10701：目标不弃法术牌时受到的法术伤害

## 10701 / 10702 在「本次攻击」里的分步进度：0＝还没处理 / 1＝已问发动者 / 2＝已问目标弃牌。
## 每次新的主动攻击宣告在 p_timeline_1 清回 0（与 role_exmogong 的疾风追射同一写法）。
var _cu_yi_step: int = 0
var _xu_rong_step: int = 0

## 10704 本回合是否已发动（技能名带【回合限定】），回合开始清零
var _used_ji_du_zhui_fang: bool = false

## 本回合是否已由 10702 授予「额外法术行动」：p_before_magic 的兜底用。
## 引擎在额外行动被驳回时会把阶段重置成普通行动（_reject_action 压的是默认行动阶段），
## 额外标志会丢；靠这个标记让「本次法术行动只能使用【魔弹】」在重置后依然生效。
var _xu_rong_extra_granted: bool = false

## 10704 在同一次「行动结束」上下文里的分步进度（存 ctx：同一次行动的重入拿同一份 ctx，
## 下一次行动天然是新的一份，不会把上一击的进度带过来）
const KEY_JI_DU_STEP: String = "_jidushaonv_ji_du_step"
const JI_DU_STEP_ASK: int = 1

## 10704 没有合法目标时下发的占位玩家号（-1 不可能是真玩家）：
## extra_action_targets 返回空表会被引擎当成「没配限制」，这里显式挡住硬提交。
const TARGET_NONE: int = -1


# ============================================================
# 回合开始：清回合限定与残留分步进度
# ============================================================
func p_before_turn_begin(_ctx: Dictionary) -> int:
	_used_ji_du_zhui_fang = false
	_xu_rong_extra_granted = false
	_cu_yi_step = 0
	_xu_rong_step = 0
	return SUCCESS


# ============================================================
# 技能栏：10703【相思病】的魔弹融合入口
# ============================================================
func available_skills() -> Array:
	var 魔弹牌: Array[int] = missile_fusion_hand_ids()
	var 落点: Array[int] = missile_targets(player.id)
	# 手里没有地/风系牌、或场上没有对手时照常下发、只置灰
	return [{
		"type": GConst.ActionType.MagicSkill,
		"id": XIANG_SI_BING,
		"need_card": 1,
		"need_target": 1,
		"targets": 落点,
		"cards": 魔弹牌,
		"enabled": not 魔弹牌.is_empty() and not 落点.is_empty(),
	}]


# ============================================================
# 相思病（10703）：地系 / 风系牌当【魔弹】使用
# 主动使用走技能栏入口（法术技能 10703），响应传递走 v_remissile；
# 两者都复用 BattleRole 的魔弹融合链（牌表 / 落点 / 传递询问）。
# ============================================================
func missile_fusion_elements() -> Array[int]:
	return [GConst.CardElement.Earth, GConst.CardElement.Wind]


## 本角色的魔弹融合技能号：播报 / 日志用 10703，不借用魔导师的 803 / 节日魔导的 7602
func missile_fusion_skill() -> int:
	return XIANG_SI_BING


## 【魔弹掌控】的临时版本（10702）：只有它授予的那份额外法术行动内可以逆向传递。
## 落点候选由基类 missile_targets() 按它现算，客户端刷新技能栏时也会走到这里。
func has_missile_mastery() -> bool:
	if engine == null:
		return false
	return bool(engine.行动额外) and int(engine.行动额外来源) == XU_RONG_ZHANG_WO


func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != XIANG_SI_BING:
		return GConst.GE_INVALID_ACTION
	return v_missile_fusion(action)


func p_magic_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != XIANG_SI_BING:
		return EMPTY_HANDLE
	return cast_missile_fusion(action)


# ============================================================
# 牌类校验覆写：地系 / 风系牌可以当【魔弹】使用与响应传递
# 与魔导师 v_missile / v_remissile 同一口径，只是系别换成 10703 的两系。
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
# 攻击宣告：新的一次主动攻击，清掉上一击的分步标记
# ============================================================
func p_timeline_1(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) == player.id:
		_cu_yi_step = 0
		_xu_rong_step = 0
	return SUCCESS


# ============================================================
# 醋意羞心（10701）：主动攻击未命中
# ============================================================
func p_timeline_2_miss(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	if _cu_yi_step >= STEP_DONE:
		return SUCCESS
	var dst: BattlePlayer = engine.p(int(ctx.get("dst", -1)))
	if dst == null:
		_cu_yi_step = STEP_DONE
		return SUCCESS
	if _cu_yi_step == 0:
		_cu_yi_step = 1
		if not engine.has_reply():
			# 响应技能先问发动者：确认＝发动，取消＝不发动（见《技能维护约定》猎巫人复盘第 1 条）。
			# 第一步用默认文案：技能表「提示」第 1 条留给下面「目标弃 1 张法术牌【展示】」那一步，
			# 这里读提示会把目标步骤的说明错挂到「是否发动」上（与 4502 臆想剑同一处理）。
			engine.ask_skill(player.id, CU_YI_XIU_XIN)
			return WAIT
	if _cu_yi_step == 1:
		if not engine.has_reply():
			return WAIT
		if not take_skill_reply():
			_cu_yi_step = STEP_DONE
			return SUCCESS
		notice_skill(CU_YI_XIU_XIN, [dst.id])
		_cu_yi_step = 2
		# 目标手里没有法术牌：弃不了，直接结算惩罚（不再白问一次）
		var 可弃: Array[int] = _hand_magic_ids(dst)
		if 可弃.is_empty():
			return _cu_yi_惩罚(dst.id)
		if not engine.has_reply():
			# 只能弃法术牌（card_rule = "magic" + cards 白名单同一口径）。
			# A46：弃牌是强制的，can_cancel=false 让客户端把「取消」置灰；服务端对
			# 超时回空 / 硬提交取消 / 非法牌仍按「没弃出」结算惩罚，兜住改包。
			询问(dst.id, CU_YI_XIU_XIN, 1, 0, GConst.CardSource.Hand, [], 0, "magic", 可弃, false)
			return WAIT
	# 阶段 2：读目标「弃 / 不弃」的回复；弃不出（回空、非法牌、手里已没有）一律走惩罚
	if not engine.has_reply():
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	_cu_yi_step = STEP_DONE
	if _target_discard_magic(dst, r):
		return SUCCESS
	return _cu_yi_惩罚(dst.id)


## 目标不弃法术牌的惩罚：我方【战绩区】+1【水晶】，并对他造成 2 点法术伤害③。
## 返回 URGENT：伤害压栈，等它结算完再回到本次未命中钩子（届时 _cu_yi_step 已是 STEP_DONE）。
func _cu_yi_惩罚(dst_id: int) -> int:
	_cu_yi_step = STEP_DONE
	engine.set_team_crystal(player.color, engine.team_crystal[player.color] + 1)
	engine.push_harm({
		"src": player.id, "dst": dst_id, "point": CU_YI_HARM_POINT,
		"cause": CU_YI_XIU_XIN, "type": GConst.HarmType.Magic, "is_active": false,
	})
	engine._broadcast_game()
	return URGENT


# ============================================================
# 虚荣掌握（10702）：主动攻击命中 → 额外 +1【法术行动】
# ============================================================
func p_timeline_2_hit(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	if _xu_rong_step >= STEP_DONE:
		return SUCCESS
	if _xu_rong_step == 0:
		# 手里一张能当【魔弹】的牌都没有：这份额外法术行动一张牌也出不了，不弹无用询问
		if _missile_hand_ids().is_empty():
			_xu_rong_step = STEP_DONE
			return SUCCESS
		_xu_rong_step = 1
		if not engine.has_reply():
			询问(player.id, XU_RONG_ZHANG_WO, 0, 0)
			return WAIT
	if _xu_rong_step != 1:
		return SUCCESS
	if not engine.has_reply():
		return WAIT
	_xu_rong_step = STEP_DONE
	if not take_skill_reply():
		return SUCCESS
	notice_skill(XU_RONG_ZHANG_WO, [])
	_xu_rong_extra_granted = true
	# direct=true：选中即进入额外法术行动，不再二次追问；skip_notice=true：上面已播报过 10702。
	# 逆向传递与「只能使用【魔弹】」由 has_missile_mastery / extra_action_card_ids 在该阶段内提供。
	player.add_action(GConst.ActionType.Magic, XU_RONG_ZHANG_WO, true, true)
	return SUCCESS


## 10702 的普通法术兜底：引擎把被驳回的额外行动重置成默认普通行动阶段时，额外标志会丢，
## 这里按「本回合 10702 授予过额外法术行动」继续禁止非【魔弹】牌走普通法术。
## p_before_magic 只在普通法术行动时被引擎调用（技能行动走 SkillRun / p_magic_skill），
## 所以不会挡住 10703 用地/风系牌当【魔弹】。
func p_before_magic(ctx: Dictionary) -> int:
	if not _xu_rong_extra_granted:
		return SUCCESS
	var card: GCard = Data.get_card(int(ctx.get("card_id", -1)))
	if card != null and card.card_name_enum() == GConst.CardName.Missile:
		return SUCCESS
	ctx["forbidden"] = true
	return SUCCESS


# ============================================================
# 额外行动限制（F2）
# ============================================================
## 10702 的额外法术行动只能使用【魔弹】。引擎把技能入口归入基础种类，普通法术行动与
## 10703 技能行动都按 ActionType.Magic 送进这里，所以拆成两套白名单：
##   - 普通法术行动（直接打出手牌）：只放行【魔弹】本体。地/风系【圣盾】【虚弱】【中毒】
##     虽然带地/风系，但不能在本次额外行动里当普通法术结算（只能走 10703 技能当【魔弹】）；
##   - 10703 技能行动（技能栏里的魔弹融合）：放行能当【魔弹】的地/风系牌（见 _正在_10703技能行动）。
## 没有可用的牌时显式「全禁」，避免空表被引擎当成「没配限制」而放行任意法术牌。
func extra_action_card_ids(cause: int, action_type: int) -> Array:
	if cause != XU_RONG_ZHANG_WO or action_type != GConst.ActionType.Magic:
		return []
	var 牌表: Array[int] = missile_fusion_hand_ids() if _正在_10703技能行动() else _missile_body_hand_ids()
	return 牌表 if not 牌表.is_empty() else [GConst.手牌白名单_全禁]


## 引擎当前正在处理的是不是 10703 的法术技能行动（SkillRun）。
## 校验额外行动限制 对技能行动传的是基础种类 Magic，与普通法术行动同值；只能靠
## 「当前正在处理的状态」区分，才能在同一个额外行动里给出两套白名单。
## 普通法术行动走 _do_magic（当前状态是行动阶段），不会命中这里。
func _正在_10703技能行动() -> bool:
	if engine == null or not (engine._当前状态 is BattleEngine.SkillRun):
		return false
	var 运行: BattleEngine.SkillRun = engine._当前状态
	return 运行.kind == "magic" and int(运行.action.get("action_id", 0)) == XIANG_SI_BING


## 手里【魔弹】本体的牌 id：10702 的额外法术行动里，普通法术行动只能出它。
func _missile_body_hand_ids() -> Array[int]:
	return hand_ids_where(func(_cid: int, c: GCard) -> bool:
		return c.card_name_enum() == GConst.CardName.Missile)


## 10704 的额外攻击行动只能攻击手牌数大于你的目标对手（按当前状态现算）。
## 一个合法目标都没有时下发 TARGET_NONE（-1），同样避免空表被当成「没配限制」。
func extra_action_targets(cause: int) -> Array:
	if cause != JI_DU_ZHUI_FANG:
		return []
	var 目标: Array[int] = _more_hand_enemies()
	return 目标 if not 目标.is_empty() else [TARGET_NONE]


# ============================================================
# 嫉妒追放（10704）：攻击 / 法术行动后支付 1【水晶】→ 额外 +1【攻击行动】
# ============================================================
func p_action_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	var kind: String = str(ctx.get("kind", ""))
	if kind != "attack" and kind != "magic":
		return SUCCESS
	if _used_ji_du_zhui_fang:
		return SUCCESS
	var 阶段: int = int(ctx.get(KEY_JI_DU_STEP, 0))
	if 阶段 >= STEP_DONE:
		return SUCCESS
	if 阶段 == 0:
		# 没有能量（水晶 + 宝石）或没有「手牌数大于你」的对手：这份额外攻击用不上，不问
		if player.get_energy() <= 0 or _more_hand_enemies().is_empty():
			ctx[KEY_JI_DU_STEP] = STEP_DONE
			return SUCCESS
		ctx[KEY_JI_DU_STEP] = JI_DU_STEP_ASK
		if not engine.has_reply():
			询问(player.id, JI_DU_ZHUI_FANG, 0, 0)
			return WAIT
	if 阶段 != JI_DU_STEP_ASK:
		return SUCCESS
	if not engine.has_reply():
		return WAIT
	ctx[KEY_JI_DU_STEP] = STEP_DONE
	if not take_skill_reply():
		return SUCCESS
	# 等回复期间状态可能已经变了，付款前再复核一次
	if player.get_energy() <= 0 or _more_hand_enemies().is_empty():
		return SUCCESS
	_used_ji_du_zhui_fang = true
	notice_skill(JI_DU_ZHUI_FANG, [])
	player.remove_energy(1)
	# 支付后立刻补一次对局快照（与 7504 / 4504 同口径）：否则客户端能量显示要等下一次快照
	engine._broadcast_game()
	# direct=true：代价已付、已问过，直接进入额外攻击行动；目标限制由 extra_action_targets 现算
	player.add_action(GConst.ActionType.Attack, JI_DU_ZHUI_FANG, true, true)
	return SUCCESS


# ============================================================
# 工具
# ============================================================
## 这张手牌能否当【魔弹】使用 / 响应传递（【魔弹】本体，或 10703 扩展的地/风系牌）
func _can_use_missile(card_id: int) -> bool:
	if not player.has_hand_card(card_id):
		return false
	return can_use_as_missile(Data.get_card(card_id))


## 手里能当【魔弹】的牌 id（10702 的额外行动白名单与询问条件用它）
func _missile_hand_ids() -> Array[int]:
	return hand_ids_where(func(_cid: int, c: GCard) -> bool: return can_use_as_missile(c))


## 某玩家手牌里的法术牌（10701 让目标弃牌时用它下发白名单）
func _hand_magic_ids(持有者: BattlePlayer) -> Array[int]:
	var out: Array[int] = []
	if 持有者 == null:
		return out
	for cid: int in 持有者.hand_cards:
		var c: GCard = Data.get_card(cid)
		if c != null and c.is_magic():
			out.append(cid)
	return out


## 目标是否真的弃出了 1 张手牌里的法术牌【展示】；成功返回 true
func _target_discard_magic(dst: BattlePlayer, r: Dictionary) -> bool:
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
	engine.to_discard([cid])
	engine._log_discard(dst.id, [cid], false)
	engine._broadcast_game()
	return true


## 手牌数严格大于自己的对手 id（10704 的目标限制 / 可发动条件）
func _more_hand_enemies() -> Array[int]:
	var out: Array[int] = []
	for pid: int in enemy_ids():
		var p0: BattlePlayer = engine.p(pid)
		if p0 != null and p0.hand_cards.size() > player.hand_cards.size():
			out.append(pid)
	return out
