extends BattleRole
## 游击士（roleID 38）—— 3.5 星 / 特典 / 技
## 指示物：槽 2 盖牌【子弹】（上限见角色表）；开局从牌库顶取 6 张面朝下作为【子弹】。
## 技能：
##   精灵赠礼（3801，被动：游戏初始时牌库顶 6 张面朝下作为【子弹】）
##   元素射击*索拉（3802，响应：主动攻击时①移除 1 个【子弹】，按子弹系别追加效果）
##   二重剑影（3803，响应 / 回合限定：攻击行动结束且本次命中②，额外 +1 同系攻击行动）
##   附魔之术（3804，响应：执行提炼时若没有【子弹】，消耗提炼的 1 能量，把 1 张手牌面朝下作为【子弹】）
##   精灵的剑舞（3805，响应 / 必杀技 / 水晶：主动攻击前①支付 1 水晶，本次攻击牌系别视为风系）
##
## 3805 的「视为风系」：引擎的 p_attack_card（改用牌）在攻击宣告前就执行，角色钩子此时无法再询问，
## 故按【攻击技能】实现——支付 1 能量后用一张风系虚拟牌（风神斩 66，与冒险家【欺诈】的虚牌同源）
## 发起一次主动攻击：本次攻击牌按风系结算（应战同系判定、3803 的同系白名单都按风系），
## 真牌照常展示并进弃牌堆。这样「视为风系」在攻击宣告与应战阶段都真实生效。
## 命格口径：本次攻击由 66 这张虚牌结算，虚牌既不继承真实攻击牌的命格、也不采用 66 卡面的【幻】命格，
## harm 标 virtual_no_fate（与冒险家【欺诈】1201 同一口径），阴阳师【阴阳转换】等「同命格」判定不能匹配。
##
## 3802 的分支：火 = 本次攻击伤害 +1（①宣告时）；水 = 命中时目标 +1 治疗（②）；
##             风 = 攻击行动结束后额外 +1 攻击行动；雷 = 本次攻击无法应战；
##             地 = 命中时对目标 1 点法术伤害（②、③）；光/暗 = 移除时选一种视为系别。
## 3802 的子弹系别与 3805 的攻击牌系别互相独立（3805 只改攻击牌，不改子弹）。

const JING_LING_ZENG_LI: int = 3801
const YUAN_SU_SHE_JI: int = 3802
const ER_CHONG_JIAN_YING: int = 3803
const FU_MO_ZHI_SHU: int = 3804
const JING_LING_DE_JIAN_WU: int = 3805

## 开局【子弹】张数（角色表只配上限 6，起始牌数属于脚本职责）
const 开局子弹数: int = 6

## 「视为风系」用的虚拟牌：风系【风神斩】(66)。只借卡名 / 系别 / 攻击类型，
## 与冒险家【欺诈】的风系虚牌是同一张。虚牌不代表真实攻击牌的命格，也不采用 66 自己的
## 【幻】命格：本次攻击的 harm 标 virtual_no_fate（见 p_attack_skill）。
const VIRTUAL_WIND_SLASH: int = 66


# ============================================================
# 开局：精灵赠礼（3801）
# ============================================================
func setup(p: BattlePlayer, e: BattleEngine) -> void:
	super.setup(p, e)
	# 牌库顶 6 张面朝下放进盖牌区（槽 2 的【子弹】）。draw_cover 会按盖牌上限截断：
	# 角色表没配槽 2 时返回 0，不会凭空给出子弹。
	if engine != null and engine.deck != null:
		engine.draw_cover(player.id, 开局子弹数, player.id, JING_LING_ZENG_LI)


# ============================================================
# 精灵的剑舞（3805）：攻击技能，本次攻击牌视为风系
# ============================================================
func available_skills() -> Array:
	var 攻击牌: Array[int] = hand_ids_where(func(_cid: int, c: GCard) -> bool: return c.is_attack())
	return [{
		"type": GConst.ActionType.AttackSkill, "id": JING_LING_DE_JIAN_WU,
		"need_card": 1, "need_target": 1,
		"cards": 攻击牌, "targets": _可攻击目标(),
		# 缺能量 / 缺攻击牌时只置灰，不把按钮收掉
		"enabled": player.get_energy() >= 1 and not 攻击牌.is_empty(),
	}]


## 3805：一次主动攻击（攻击牌 + 1 名对手），费用【水晶】（宝石可顶）
func v_attack_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != JING_LING_DE_JIAN_WU:
		return GConst.GE_INVALID_ACTION
	if player.get_energy() <= 0:
		return GConst.GE_INVALID_ACTION
	var cards: Array = action.get("card_ids", [])
	if cards.size() != 1:
		return GConst.GE_INVALID_CARDID
	var dsts: Array = action.get("dst_ids", [])
	if dsts.size() != 1:
		return GConst.GE_INVALID_PLAYERID
	# 通用攻击校验：在手、攻击牌、目标不同队、被【挑衅】锁定时只能打放牌者
	var rc: int = player.base_v_attack(int(cards[0]), int(dsts[0]), engine.players)
	if rc != GConst.GE_SUCCESS:
		return rc
	# 防守方角色可拒绝被选为目标（如暗杀者潜行中「不能成为主动攻击的目标」）：
	# 普通攻击由引擎 _do_attack 统一检查，攻击技能必须由角色自查（同猎魔人 4201 / 冒险家 1201）
	var dst: BattlePlayer = engine.p(int(dsts[0]))
	if dst == null or dst.v_attacked() != GConst.GE_SUCCESS:
		return GConst.GE_INVALID_PLAYERID
	return GConst.GE_SUCCESS


## 3805「视为风系」：额外行动的白名单校验要按风系攻击牌放行（如 3803 二重剑影给的同系攻击行动）。
## 3803+3805 联动踩过：先 3805 出风系牌 → 3803 给「只能用风系攻击牌」的额外攻击行动 →
## 再用 3805 把地系牌视为风系打出去，服务端按真实牌（地系）驳回。
func 技能视为系别(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) == JING_LING_DE_JIAN_WU:
		return GConst.CardElement.Wind
	return 0


func p_attack_skill(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	var cid: int = int(cards[0])
	var dst_id: int = int(dsts[0])
	notice_skill(JING_LING_DE_JIAN_WU, [dst_id])
	# 支付 1 能量（水晶优先，水晶不够时宝石可顶）
	player.remove_energy(1)
	# 真牌照常展示并进弃牌堆；本次攻击按风系虚拟牌结算
	var 视为: int = VIRTUAL_WIND_SLASH
	engine.push(BattleEngine.SAttackCard.new(player.id, dst_id, 视为, {
		"src": player.id, "dst": dst_id, "point": BattleEngine.ATTACK_BASE_POINT,
		"cause": GConst.CAUSE_ATTACK, "type": GConst.HarmType.Attack,
		"card_id": 视为, "is_active": true,
		# 虚牌不是真实卡：本次攻击不参与「同命格」判定（阴阳转换等），
		# 也不采用 66 卡面的【幻】命格（与欺诈 1201 同一口径）
		"virtual_no_fate": true,
	}))
	engine.take_from_hand(player.id, [cid], true)
	engine.to_discard([cid], {"owner": player.id, "source": "hand"})
	# 出牌播报用真牌（card_ids＝真牌、is_real＝true），卡名 / 命格按真牌显示；
	# 「视为风系」只体现在 as_card_id（客户端按它出声 / 出特效）与上面 harm 的 card_id 上。
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Use, "src_id": player.id, "dst_id": dst_id,
		"card_ids": [cid], "is_real": true, "as_card_id": 视为,
	})
	engine._broadcast_game()
	return URGENT


# ============================================================
# 每回合重置（回合限定标记 / 分步进度）
# ============================================================
## 本次攻击宣告后的分步进度（0＝还没开始 / 1＝在问是否发动 / 2＝在选子弹 /
## 3＝光暗子弹选视为系别 / STEP_DONE＝已处理完）。用自有变量而不是引擎的 step：
## 钩子轮次之间会互相插队，而这条流程要跨多次询问。
var _timeline_1_step: int = 0
## 本次移除的子弹牌 / 结算系别（光暗选完后为视为系别）
var _子弹牌: int = -1
var _子弹系别: int = 0
## 子弹的后续效果是否还在等「命中② / 攻击行动结束」
var _子弹待命中: bool = false
var _子弹待行动结束: bool = false
## 本次主动攻击是否命中②（3803 用；攻击牌 / 目标 / 实际系别在宣告时记下）
var _本次攻击命中: bool = false
var _本次攻击目标: int = -1
var _本次攻击系别: int = 0
## 3803 本回合是否已发动（技能名带【回合限定】）
var _3803_已用: bool = false
## 3803 授予的额外攻击行动的「与本次攻击同系」白名单用系别
var _3803_系别: int = 0
## 3804 的提炼标记与分步进度（0＝在问是否发动 / 1＝在选要扣置的手牌）
var _提炼待补子弹: bool = false
var _提炼获得能量: int = 0
var _附魔_step: int = 0


func p_before_turn_begin(_ctx: Dictionary) -> int:
	_timeline_1_step = 0
	_子弹牌 = -1
	_子弹系别 = 0
	_子弹待命中 = false
	_子弹待行动结束 = false
	_本次攻击命中 = false
	_本次攻击目标 = -1
	_本次攻击系别 = 0
	_3803_已用 = false
	_3803_系别 = 0
	_提炼待补子弹 = false
	_提炼获得能量 = 0
	_附魔_step = 0
	return SUCCESS


# ============================================================
# 元素射击*索拉（3802）：主动攻击时①移除 1 个【子弹】并按系别追加效果
# 一次询问完成：直接选 1 个【子弹】（选完按确定即发动，取消＝不发动），不再先问一次「是否发动」。
# ============================================================
func p_timeline_1(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	# 同一次攻击只处理一次：子弹结算时若压入新的伤害（地系），钩子会带同一份 ctx 重入
	if bool(ctx.get("youjishi_3802_done", false)):
		return SUCCESS
	if _timeline_1_step == 0:
		# 新一次主动攻击宣告：清掉上一次的子弹 / 命中标记，记下本次攻击的信息
		_本次攻击命中 = false
		_本次攻击目标 = int(ctx.get("dst", -1))
		_本次攻击系别 = _牌系别(int(ctx.get("card_id", -1)))
		_子弹牌 = -1
		_子弹系别 = 0
		_子弹待命中 = false
		_子弹待行动结束 = false
		if player.cover_count() <= 0:
			ctx["youjishi_3802_done"] = true
			return SUCCESS
		_timeline_1_step = 1
	if _timeline_1_step == 1:
		# 一步到位：直接选 1 个【子弹】（盖牌，本人可见牌面），选中＋确定即发动，取消＝不发动。
		# 光/暗子弹「视为任一系别」也合并在同一次询问里：五个系别选项一直下发，
		# 客户端只在选中光/暗子弹时点亮，普通子弹直接确定。
		if not engine.has_reply():
			询问(player.id, YUAN_SU_SHE_JI, 1, 0, GConst.CardSource.Cover, _视为系别选项())
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		var cid: int = _取盖牌(r.get("card_ids", []))
		if cid < 0:
			return _收尾_3802(ctx)
		_子弹牌 = cid
		_子弹系别 = _牌系别(cid)
		if _子弹系别 == GConst.CardElement.Light or _子弹系别 == GConst.CardElement.Darkness:
			# 光/暗必须选一种视为系别（客户端在选中光/暗子弹前会把选项置灰、不让确定）
			var args: Array = r.get("args", [])
			var 视为: int = int(args[0]) if not args.is_empty() else 0
			if not _视为系别表().has(视为):
				return _收尾_3802(ctx)
			_子弹系别 = 视为
		_timeline_1_step = 3
	if _timeline_1_step == 3:
		return _结算子弹(ctx)
	return SUCCESS


## 3802 的收尾：标记本次攻击已处理（挡住地系伤害 URGENT 的重入），进度清回 0
func _收尾_3802(ctx: Dictionary) -> int:
	ctx["youjishi_3802_done"] = true
	_timeline_1_step = 0
	_子弹牌 = -1
	return SUCCESS


## 移除选中的【子弹】、展示牌面并按系别挂上后续效果
func _结算子弹(ctx: Dictionary) -> int:
	var cid: int = _子弹牌
	if cid < 0 or not player.有盖牌(cid):
		return _收尾_3802(ctx)
	# 按子弹系别显示技能名（如「元素射击*索拉*风系」）：播报与战斗日志都用这个名字
	notice_skill(YUAN_SU_SHE_JI, [_本次攻击目标],
		"%s*%s系" % [GConst.skill_name(YUAN_SU_SHE_JI), GConst.element_to_chinese(_子弹系别)])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": [cid], "is_real": true,
	})
	engine.remove_cover(player.id, [cid], player.id, YUAN_SU_SHE_JI)
	engine.to_discard([cid], {"owner": player.id, "source": "cover"})
	var harm: Dictionary = ctx.get("harm", {})
	match _子弹系别:
		GConst.CardElement.Fire:
			# 火系：本次攻击伤害额外 +1（宣告阶段就加，应战提示里也是加后的伤害）
			if not harm.is_empty():
				harm["point"] = int(harm.get("point", 0)) + 1
		GConst.CardElement.Thunder:
			# 雷系：本次攻击无法应战
			ctx["hit_rate"] = GConst.HitRate.NoReattack
		GConst.CardElement.Water:
			_子弹待命中 = true
		GConst.CardElement.Earth:
			_子弹待命中 = true
		GConst.CardElement.Wind:
			_子弹待行动结束 = true
	engine._broadcast_game()
	return _收尾_3802(ctx)


## 光 / 暗子弹可选视为的五系（顺序照技能原文：火 / 水 / 风 / 雷 / 地）
func _视为系别表() -> Array[int]:
	return [GConst.CardElement.Fire, GConst.CardElement.Water, GConst.CardElement.Wind,
		GConst.CardElement.Thunder, GConst.CardElement.Earth]


## 光 / 暗子弹的视为系别选项：固定五项全部下发，点选后按该项结算
func _视为系别选项() -> Array:
	var out: Array = []
	for 元素: int in _视为系别表():
		out.append({"value": 元素, "label": GConst.按钮原文(YUAN_SU_SHE_JI, 0) % GConst.element_to_chinese(元素), "element": 元素})
	return out


## 3802 的命中②：水系给「玩家选的目标」+1 治疗；地系对「玩家选的目标」造成 1 点法术伤害③。
## 目标由玩家选（技能原文是「目标角色」，不限被攻击者）；超时 / 取消按被攻击者结算——
## 子弹已经花掉，不能白弃。
func p_timeline_2_hit(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("src", -1)) != player.id:
		return SUCCESS
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	_本次攻击命中 = true
	if not _子弹待命中:
		return SUCCESS
	if not engine.has_reply():
		# 直接问「选 1 名角色」（水系提示 3 / 地系提示 4），目标不限敌我。
		# 头像预览：水系 +1 治疗、地系 1 点法术伤害 —— 客户端只在「已点选」的目标头像上画
		# （与技能指示器同一套体验），不给每个候选人都画一遍
		询问(player.id, YUAN_SU_SHE_JI, 0, 1, GConst.CardSource.Hand, [], 0, "", [], true,
			2 if _子弹系别 == GConst.CardElement.Water else 3,
			-1, [], -1, {}, 1,
			GConst.预览类型_治疗 if _子弹系别 == GConst.CardElement.Water else GConst.HarmType.Magic)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var 目标: int = int(harm.get("dst", -1))
	var dsts: Array = r.get("dst_ids", [])
	if not dsts.is_empty() and engine.p(int(dsts[0])) != null:
		目标 = int(dsts[0])
	# 先消费掉标记：地系压入伤害后本钩子会重入，不能重复结算
	_子弹待命中 = false
	if _子弹系别 == GConst.CardElement.Water:
		施加治疗(目标, 1)
		engine._broadcast_game()
		return SUCCESS
	if _子弹系别 == GConst.CardElement.Earth:
		engine.push_harm({
			"src": player.id, "dst": 目标, "point": 1,
			"cause": YUAN_SU_SHE_JI, "type": GConst.HarmType.Magic,
		})
		engine._broadcast_game()
		return URGENT
	return SUCCESS


# ============================================================
# 攻击行动结束时：3802 风系的额外攻击行动 + 3803 二重剑影
# ============================================================
func p_after_attack(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	var 命中: bool = _本次攻击命中
	_本次攻击命中 = false
	# 3802 风系：攻击行动结束后额外 +1 攻击行动（无出牌限制），直接给、不再弹一次响应询问
	if _子弹待行动结束:
		_子弹待行动结束 = false
		player.add_action(GConst.ActionType.Attack, YUAN_SU_SHE_JI, true, true)
	# 3803 二重剑影：本次攻击命中②、回合限定，额外 +1「与本次攻击同系」的攻击行动
	if 命中 and not _3803_已用:
		_3803_已用 = true
		_3803_系别 = _本次攻击系别
		notice_skill(ER_CHONG_JIAN_YING, [_本次攻击目标])
		# 同系限制只写系别（授予时已定系别），引擎按「该系攻击牌」规则算可用牌
		player.add_action(GConst.ActionType.Attack, ER_CHONG_JIAN_YING, false, true, {
			"element": _3803_系别,
			"in_end_response": true,
		})
	return SUCCESS

# ============================================================
# 附魔之术（3804）：执行提炼时若没有【子弹】，消耗提炼的 1 能量补 1 张盖牌
# ============================================================
## 提炼校验：照通用实现；提炼成立时记下「本次提炼获得了多少能量」，
## 供 p_after_special 判断能否支付 3804（引擎的 p_after_special 上下文不带 action_id，
## 只能靠校验钩子先做标记来区分「这次特殊行动是提炼」）。
func v_extract(args: Array, team_gem: int, team_crystal: int, _dst_ids: Array) -> int:
	_提炼待补子弹 = false
	_提炼获得能量 = 0
	_附魔_step = 0
	var rc: int = player.base_v_extract(args, team_gem, team_crystal)
	if rc != GConst.GE_SUCCESS:
		return rc
	_提炼待补子弹 = true
	_提炼获得能量 = int(args[0]) + int(args[1])
	return rc


func p_after_special(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if not bool(ctx.get("special_action", false)):
		return SUCCESS
	if not _提炼待补子弹:
		return SUCCESS
	if _附魔_step >= STEP_DONE:
		return SUCCESS
	# 发动条件：提炼出了能量、能量够付、没有【子弹】（盖牌区空）、手里有牌可扣置
	var 可发动: bool = _提炼获得能量 >= 1 and player.get_energy() >= 1 \
		and player.cover_count() == 0 and player.can_add_cover_cards(1) \
		and not player.hand_cards.is_empty()
	if not 可发动:
		_提炼待补子弹 = false
		return SUCCESS
	# 一步到位：直接选 1 张手牌面朝下作为【子弹】，选中＋确定即发动，取消＝不发动
	if not engine.has_reply():
		询问(player.id, FU_MO_ZHI_SHU, 1, 0, GConst.CardSource.Hand)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	_提炼待补子弹 = false
	_附魔_step = STEP_DONE
	var cid: int = _取手牌(r.get("card_ids", []))
	if cid < 0:
		return SUCCESS
	notice_skill(FU_MO_ZHI_SHU, [player.id])
	player.remove_energy(1)
	engine.take_from_hand(player.id, [cid])
	engine.add_cover(player.id, [cid], player.id, FU_MO_ZHI_SHU)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 工具
# ============================================================
## 3805 的合法目标：敌方且「可被主动攻击」。暗杀者潜行（横置）期间不能成为主动攻击的目标，
## 普通攻击由引擎 _do_attack 检查；攻击技能的技能栏目标也要按同一口径过滤（服务端在
## v_attack_skill 里再自查一次，客户端即使硬提交也会被驳回）。
func _可攻击目标() -> Array[int]:
	var out: Array[int] = []
	for pid: int in enemy_ids():
		var p0: BattlePlayer = engine.p(pid)
		if p0 == null or p0.v_attacked() != GConst.GE_SUCCESS:
			continue
		out.append(pid)
	return out


## 取回复里第一张自己真实拥有的盖牌（没有则 -1）
func _取盖牌(ids: Array) -> int:
	for c: Variant in ids:
		if player.有盖牌(int(c)):
			return int(c)
	return -1


## 取回复里第一张自己真实拥有的手牌（没有则 -1）
func _取手牌(ids: Array) -> int:
	for c: Variant in ids:
		if player.有手牌(int(c)):
			return int(c)
	return -1


## 某张牌的系别（取不到返回 0）
func _牌系别(card_id: int) -> int:
	var card: GCard = Data.get_card(card_id)
	return card.element_enum() if card != null else 0
