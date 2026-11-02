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
##   - 10701 先问发动者是否发动（响应技能）→ 发动者**指定 1 名「目标角色」**（场上的角色都能选，
##     不限于本次攻击的目标）→ 那名角色弃 1 张法术牌【展示】：可以取消，取消 / 手里没有法术牌 /
##     超时 / 硬提交非法牌都按「不如此做」算（与【魔爆冲击】同口径）；不弃就直接吃 2 点法术伤害，
##     同时我方【战绩区】+1【水晶】；
##   - 10702 的逆向只在它授予的那份额外法术行动内有效：has_missile_mastery() 只在
##     「当前额外行动阶段的来源＝10702」时返回 true；「只能使用【魔弹】」由
##     行动规格里的两套白名单（cards / skill_cards）：普通法术行动只放行【魔弹】本体，
##     10703 技能行动另放行地/风系牌当【魔弹】——地/风系【圣盾】/【虚弱】/【中毒】不能借
##     普通法术行动结算；
##   - 10703 同时扩展「主动使用」（技能栏里的魔弹融合入口 10703）与「响应传递」（v_remissile），
##     按 A21：10703 原文写「使用」，两组都扩；
##   - 10704 的【水晶】费用按约定用 get_energy() 判断、remove_energy(1) 支付（宝石可顶水晶）；
##     目标限制写进行动规格（targets），进入时按当时双方手牌数重算。
##
## 牌类校验与魔导师（8）/ 节日魔导（76）的【魔弹融合】同一条链：系别由 missile_fusion_elements()
## 配置，本角色是地 / 风；播报 / 提示用本角色自己的 10703，不借用 803 / 7602。

const CU_YI_XIU_XIN: int = 10701      # 醋意羞心（响应）
const XU_RONG_ZHANG_WO: int = 10702   # 虚荣掌握（响应）
const XIANG_SI_BING: int = 10703      # 相思病（响应 / 魔弹融合入口）
const JI_DU_ZHUI_FANG: int = 10704    # 嫉妒追放（响应 / 必杀技 / 回合限定）

const CU_YI_HARM_POINT: int = 2       # 10701：目标不弃法术牌时受到的法术伤害

## 10701 / 10702 在「本次攻击」里的分步进度：0＝还没处理 / 1＝已问发动者 / 2＝已让发动者指定目标
## / 3＝已问目标弃牌（10701）；10702 只用到 0 / 1。
## 每次新的主动攻击宣告在 p_timeline_1 清回 0（与 role_exmogong 的疾风追射同一写法）。
var _cu_yi_step: int = 0
var _xu_rong_step: int = 0

## 10701 由发动者指定的「目标角色」（step 2 选出来的；等回复期间不能现算）
var _cu_yi_目标: int = -1

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
## 规格里的空表会被引擎当成「没配限制」，所以「一个合法目标都没有」要显式给哨兵挡住硬提交。
const TARGET_NONE: int = -1


# ============================================================
# 回合开始：清回合限定与残留分步进度
# ============================================================
func p_before_turn_begin(_ctx: Dictionary) -> int:
	_used_ji_du_zhui_fang = false
	_xu_rong_extra_granted = false
	_cu_yi_step = 0
	_cu_yi_目标 = -1
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
		_cu_yi_目标 = -1
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
	# 第 1 步：「是否发动」与「选目标角色」合并成一次询问 ——
	# 点技能 → 直接选 1 名「目标角色」→ 按确定就发动；取消＝不发动（不再先单问一次「要不要发动」）。
	if _cu_yi_step == 0:
		_cu_yi_step = 1
		_cu_yi_目标 = -1
		if not engine.has_reply():
			# 文案不在这里写死：客户端对响应技能默认就显示**完整的技能说明**
			# （原文写了效果落在谁身上，比一句「请指定 1 名目标角色」更清楚）。
			# 目标范围＝场上全部角色（技能原文写「目标角色」＝玩家可以指定一名角色）。
			engine.ask_skill(player.id, CU_YI_XIU_XIN, 0, 1, GConst.CardSource.Hand, [], 0, "",
				[], true, "", _全部角色())
			return WAIT
	# 第 2 步：读「选了谁」；接着问那名角色弃不弃法术牌（第 3 步等它的回复）
	if _cu_yi_step == 1:
		if not engine.has_reply():
			return WAIT
		var 选人: Dictionary = take_skill_reply_full()
		var 目标表: Array = 选人.get("dst_ids", [])
		if 目标表.is_empty():
			# 取消 / 超时回空：视为不发动
			_cu_yi_step = STEP_DONE
			return SUCCESS
		var 目标号: int = int(目标表[0]) if 目标表.size() == 1 else -1
		if 目标号 < 0 or engine.p(目标号) == null:
			# 硬提交的非法目标：按「AI / 掉线按默认规则代选」兜底成随机一名角色
			目标号 = _cu_yi_兜底目标()
		if 目标号 < 0:
			_cu_yi_step = STEP_DONE
			return SUCCESS
		_cu_yi_目标 = 目标号
		_cu_yi_step = 2
		notice_skill(CU_YI_XIU_XIN, [目标号])
		# 只能弃法术牌（card_rule = "magic"），不下发牌号白名单：手里没有法术牌时界面整片置灰，
		# 与【魔爆冲击】/【贪欲黑洞】同口径 —— **可以取消**：取消 / 超时 / 硬提交非法牌都按
		# 「不如此做」结算（2 点法术伤害 + 发动者一方战绩区 +1 水晶）。
		# 提示整段从**目标视角**写（「你受到…」「我方 / 对方战绩区」）：
		# 发动者与目标同队时水晶进的是目标自己这边（我方），否则是对面（对方）。
		# 用 ask_prompt 下发（整段专属提示）：can_cancel=true 时客户端会拿技能说明盖掉 ask_text，
		# 只有 ask_prompt 能保证这句「我方 / 对方」按目标视角原样显示。
		# 同时把「要挨的 2 点法术伤害」随询问下发（预览基准 / 类型 / 目标）：客户端在**目标自己**的
		# 头像上写「2 法术伤害」（他就是要挨这一下的人）。
		engine.ask_skill(目标号, CU_YI_XIU_XIN, 1, 0, GConst.CardSource.Hand, [], 0, "magic",
			[], true, "", [], CU_YI_HARM_POINT, GConst.HarmType.Magic, false, [目标号],
			true, -1, 0, false, -1, false, _cu_yi_弃牌文案(目标号))
		return WAIT
	# 第 3 步：目标「弃 / 不弃」的回复；弃不出（回空、非法牌、手里已没有）一律走惩罚
	if not engine.has_reply():
		return WAIT
	_cu_yi_step = STEP_DONE
	var dst: BattlePlayer = engine.p(_cu_yi_目标)
	if dst == null:
		return SUCCESS
	var r: Dictionary = take_skill_reply_full()
	if _target_discard_magic(dst, r):
		return SUCCESS
	return _cu_yi_惩罚(dst.id)


## 发动者没给出合法目标（超时 / 改包）时的兜底：从场上所有角色里随机一名
func _cu_yi_兜底目标() -> int:
	var 候选: Array[int] = _全部角色()
	if 候选.is_empty():
		return -1
	return int(候选[engine._rng.randi_range(0, 候选.size() - 1)])


## 场上所有角色（含自己与队友）：「目标角色」型的技能用它下发可选目标（玩家可以指定一名角色）
func _全部角色() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		out.append(pid)
	return out


## 10701 目标弃牌那一步的提示：整段从**目标视角**写 ——
## 「你受到 2 点法术伤害」＋水晶归属用「我方 / 对方」：
## 发动者与目标同队时水晶进的是目标自己这边（我方），否则是对面（对方）。
func _cu_yi_弃牌文案(dst_id: int) -> String:
	var 目标: BattlePlayer = engine.p(dst_id)
	var 阵营: String = "我方" if 目标 != null and 目标.color == player.color else "对方"
	return "【%s】：弃 1 张法术牌【展示】，（若不这么做）你受到 %d 点法术伤害，%s【战绩区】+1【水晶】" \
		% [GConst.skill_name(CU_YI_XIU_XIN), CU_YI_HARM_POINT, 阵营]


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
		_xu_rong_step = 1
		if not engine.has_reply():
			# 不管手里有没有能当【魔弹】的牌都问一次（需求方口径）：拿到这份行动后还可能摸牌 /
			# 被别人给牌，白名单也会在「进入 / 切到这份行动时」按当时手牌重算，不在这里预先挡掉。
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
	# 「本次只能出【魔弹】」写在行动自己的规格里，见 虚荣掌握规格()
	player.add_action(GConst.ActionType.Magic, XU_RONG_ZHANG_WO, true, true, 虚荣掌握规格())
	return SUCCESS


## 10702 那份额外法术行动的规格：
##   cards       —— 普通法术行动可出的牌：只放行【魔弹】本体（地/风系牌不能按普通法术结算）
##   skill_cards —— 技能行动可出的牌：10703 魔弹融合能用能当【魔弹】的地/风系牌
## 授予与进入时各算一次（手牌可能变过）。
func 虚荣掌握规格() -> Dictionary:
	return {
		"cards": _白名单或全禁(_missile_body_hand_ids()),
		"skill_cards": _白名单或全禁(missile_fusion_hand_ids()),
	}


## 10704 那份额外攻击行动的规格：只能打手牌数大于你的对手（一个都没有时给 TARGET_NONE）。
func 嫉妒追放规格() -> Dictionary:
	return {"targets": _白名单或全禁(_more_hand_enemies(), TARGET_NONE)}


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
## 10702 的「只能出【魔弹】」写在行动自己的规格里（cards＝普通法术行动可出的牌、
## skill_cards＝技能行动可出的牌），授予 / 进入时由本角色的 _白名单或全禁 算好；
## 引擎照单执行，不再按 cause 回问角色。


## 空表在行动规格里等于「不限制」：一张都没有时要显式给全禁 / 无目标哨兵。
## 10702 与 10704 共用（前者是手牌白名单，后者是目标白名单）。
func _白名单或全禁(表: Array, 哨兵: int = GConst.手牌白名单_全禁) -> Array:
	return 表 if not 表.is_empty() else [哨兵]


## 手里【魔弹】本体的牌 id：10702 的额外法术行动里，普通法术行动只能出它。
func _missile_body_hand_ids() -> Array[int]:
	return hand_ids_where(func(_cid: int, c: GCard) -> bool:
		return c.card_name_enum() == GConst.CardName.Missile)


## 进入额外行动那一刻按「此刻」的手牌 / 手牌数重算规格：
## 授予到进入之间手牌可能变过（摸牌、弃牌），白名单与目标限制不能停在授予那一刻。
func p_additional_action(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	var 规格: Dictionary = 额外行动规格(int(ctx.get("cause", 0)))
	if not 规格.is_empty():
		player.改写额外行动(int(ctx.get("cause", 0)), 规格)
	return SUCCESS


## 手牌变了：10702 的白名单是手牌快照，当前那份额外行动要立刻重算 ——
## 否则摸到的【魔弹】不在白名单里（客户端点不动、硬提交也会被驳回）。
func p_hand_change(_ctx: Dictionary) -> int:
	if engine == null or player == null:
		return SUCCESS
	if int(engine.当前额外行动数据.get("cause", 0)) == XU_RONG_ZHANG_WO:
		player.改写额外行动(XU_RONG_ZHANG_WO, 虚荣掌握规格())
	return SUCCESS


## 额外行动规格按「此刻」重算：引擎在「进入这份额外行动」和「本地切换到它」时都会回调。
## 10702 的白名单是手牌快照、10704 的目标限制是双方手牌数快照，都必须现算 ——
## 否则授予之后新拿到的【魔弹】/ 手牌数变多的对手会被旧快照挡住（切过去时打不出魔弹就是这里）。
func 额外行动规格(cause: int) -> Dictionary:
	match cause:
		XU_RONG_ZHANG_WO:
			return 虚荣掌握规格()
		JI_DU_ZHUI_FANG:
			return 嫉妒追放规格()
	return {}


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
	# direct=true：代价已付、已问过，直接进入额外攻击行动；
	# 「只能打手牌数大于你的对手」写在行动自己的规格里（targets，进入时还会按当时手牌数重算）
	player.add_action(GConst.ActionType.Attack, JI_DU_ZHUI_FANG, true, true, 嫉妒追放规格())
	return SUCCESS


# ============================================================
# 工具
# ============================================================
## 这张手牌能否当【魔弹】使用 / 响应传递（【魔弹】本体，或 10703 扩展的地/风系牌）
func _can_use_missile(card_id: int) -> bool:
	if not player.has_hand_card(card_id):
		return false
	return can_use_as_missile(Data.get_card(card_id))


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
	engine.to_discard([cid], {"owner": dst.id, "source": "hand"})
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
