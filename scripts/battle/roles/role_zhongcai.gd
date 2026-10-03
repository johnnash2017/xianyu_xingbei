extends BattleRole
## 仲裁者（roleID 14）—— 移植自服务端 role/ZhongCai.cpp
## 被动：仲裁法则（开局 +2 水晶）、审判浪潮（1404，每承受一次伤害 +1 审判）
## 指示物：tokens[0] = 审判，上限 4
## 技能：仲裁仪式（1402，启动：1 宝石转[审判形态]，手牌上限恒定为 5；
##                 该形态下每次回合开始 +1 审判）、
##       仪式中断（1401，启动：仅[审判形态]下发动，脱离该形态，我方战绩区 +1 宝石，手牌上限恢复 6）、
##       末日审判（1403，法术：移除所有审判，对目标造成等量法术伤害）、
##       判决天平（1405，必杀技：1 能量 +1 审判，选择弃光手牌 或 补手牌到上限且战绩区 +1 宝石）
## 覆写校验：v_allow_action——审判满 4 时只能发动【末日审判】（服务端 ZhongCai::v_allow_action）

const YI_SHI_ZHONG_DUAN: int = 1401
const ZHONG_CAI_YI_SHI: int = 1402
const MO_RI_SHEN_PAN: int = 1403
const SHEN_PAN_LANG_CHAO: int = 1404
const PAN_JUE_TIAN_PING: int = 1405

const TOKEN_MAX: int = 4
## 服务端 setHandCardsMaxFixed：普通形态 6，审判形态 5
const HAND_MAX_NORMAL: int = 6
const HAND_MAX_TRIAL: int = 5


func setup(p: BattlePlayer, e: BattleEngine) -> void:
	super.setup(p, e)
	# 仲裁法则：游戏初始时，你 +2 水晶
	p.set_crystal(2)
	p.tokens[0] = {"name": "审判", "max": TOKEN_MAX, "num": 0}


func available_skills() -> Array:
	var out: Array = []
	var t: int = int(player.tokens[0]["num"])
	if t > 0:
		out.append({"type": GConst.ActionType.MagicSkill, "id": MO_RI_SHEN_PAN, "need_card": 0, "need_target": 1})
	if t < TOKEN_MAX and player.get_energy() > 0:
		out.append({"type": GConst.ActionType.MagicSkill, "id": PAN_JUE_TIAN_PING, "need_card": 0, "need_target": 0,
			"arg_choices": [
				{"text": "弃光手牌", "args": [0]},
				{"text": "补满手牌，我方 +1 宝石", "args": [1]},
			]})
	return out


# ============================================================
# 行动校验覆写：审判达到上限时强制只能发动【末日审判】
# 对应服务端 ZhongCai::v_allow_action：token[0] 满 4 时，攻击 / 法术 / 特殊 / 放弃一律非法
# 引擎的钩子不携带 action_id，故此处只按动作类型放行「法术技能」，
# 非【末日审判】的法术（如判决天平）由 v_magic_skill 中的 token 上限检查继续驳回
# ============================================================
func v_allow_action(action_type: int, args: Array, allow: int, can_give_up: bool) -> int:
	var base: int = player.base_v_allow_action(action_type, args, allow, can_give_up)
	if int(player.tokens[0]["num"]) < TOKEN_MAX:
		return base
	# 服务端 ZhongCai::v_allow_action：满审判时仍允许「放弃行动」
	if can_give_up and action_type == GConst.ActionType.None:
		return GConst.GE_SUCCESS
	if action_type == GConst.ActionType.MagicSkill:
		return GConst.GE_SUCCESS
	return GConst.GE_INVALID_ACTION


# ============================================================
# 回合开始：[审判形态]下 +1 审判
# ============================================================
func p_turn_begin(_ctx: Dictionary) -> int:
	if engine.current_id != player.id or not player.tap:
		return SUCCESS
	_add_token(1)
	return SUCCESS


## 【仲裁仪式 / 仪式中断】的推进阶段（0＝还没开始 / YI_SHI_ZHONG_DUAN＝在问仪式中断 / ZHONG_CAI_YI_SHI＝在问仲裁仪式）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨若干次询问，
## 中途一旦被别的钩子轮次（改手牌 / 盖牌 / 基础效果 / 横置…）插进来，step 就被抹掉、流程退回第 0 步。
## 每次自己回合开始（p_boot）触发一次，收尾清回 0（留 STEP_DONE 会让下一次触发不再发动）
var _zhong_cai_boot_step: int = 0


# ============================================================
# 启动：仪式中断（1401）/ 仲裁仪式（1402）
# ============================================================
func p_boot(_ctx: Dictionary) -> int:
	if engine.current_id != player.id:
		return SUCCESS
	if _zhong_cai_boot_step >= STEP_DONE:
		return SUCCESS
	if _zhong_cai_boot_step == 0:
		if player.tap:
			_zhong_cai_boot_step = YI_SHI_ZHONG_DUAN
		elif player.gem > 0:
			_zhong_cai_boot_step = ZHONG_CAI_YI_SHI
		else:
			return SUCCESS
	if _zhong_cai_boot_step == YI_SHI_ZHONG_DUAN:
		if not engine.has_reply():
			询问(player.id, YI_SHI_ZHONG_DUAN, 0, 0)
			return WAIT
		_zhong_cai_boot_step = 0
		if not take_skill_reply():
			return SUCCESS
		notice_skill(YI_SHI_ZHONG_DUAN, [player.id])
		engine.set_team_gem(player.color, engine.team_gem[player.color] + 1)
		player.tap = false
		player.hand_cards_max = HAND_MAX_NORMAL
		engine._broadcast_game()
		return SUCCESS
	if _zhong_cai_boot_step == ZHONG_CAI_YI_SHI:
		if not engine.has_reply():
			询问(player.id, ZHONG_CAI_YI_SHI, 0, 0)
			return WAIT
		_zhong_cai_boot_step = 0
		if not take_skill_reply():
			return SUCCESS
		notice_skill(ZHONG_CAI_YI_SHI, [player.id])
		player.set_gem(player.gem - 1)
		player.tap = true
		player.hand_cards_max = HAND_MAX_TRIAL
		engine._broadcast_game()
	return SUCCESS


# ============================================================
# 审判浪潮（1404）：承受一次伤害 +1 审判
# ============================================================
func p_timeline_6_drawn(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("dst", -1)) != player.id:
		return SUCCESS
	if int(harm.get("type", -1)) == GConst.HarmType.None:
		return SUCCESS
	notice_skill(SHEN_PAN_LANG_CHAO, [player.id])
	_add_token(1)
	return SUCCESS


# ============================================================
# 主动法术技能
# ============================================================
func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	var aid: int = int(action.get("action_id", 0))
	var token: int = int(player.tokens[0]["num"])
	match aid:
		MO_RI_SHEN_PAN:
			if token == 0:
				return GConst.GE_INVALID_ACTION
			if action.get("dst_ids", []).is_empty():
				return GConst.GE_INVALID_ACTION
		PAN_JUE_TIAN_PING:
			if token >= TOKEN_MAX or action.get("args", []).is_empty() or player.get_energy() == 0:
				return GConst.GE_INVALID_ACTION
		_:
			return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	match int(action.get("action_id", 0)):
		MO_RI_SHEN_PAN:
			return _mo_ri_shen_pan(action)
		PAN_JUE_TIAN_PING:
			return _pan_jue_tian_ping(action)
	return GConst.GE_INVALID_ACTION


## 末日审判：移除所有[审判]，对目标造成等量法术伤害
func _mo_ri_shen_pan(action: Dictionary) -> int:
	var dsts: Array = action.get("dst_ids", [])
	var dst_id: int = int(dsts[0])
	var point: int = int(player.tokens[0]["num"])
	notice_skill(MO_RI_SHEN_PAN, [dst_id])
	player.tokens[0]["num"] = 0
	engine.push_harm({
		"src": player.id, "dst": dst_id, "point": point,
		"cause": MO_RI_SHEN_PAN, "type": GConst.HarmType.Magic,
	})
	engine._broadcast_game()
	return URGENT


## 判决天平：消耗 1 能量 +1 审判；args[0]==0 弃光手牌，否则补手牌到上限且战绩区 +1 宝石
func _pan_jue_tian_ping(action: Dictionary) -> int:
	var args: Array = action.get("args", [])
	var choice: int = int(args[0]) if not args.is_empty() else 1
	if player.crystal > 0:
		player.set_crystal(player.crystal - 1)
	else:
		player.set_gem(player.gem - 1)
	_add_token(1)
	notice_skill(PAN_JUE_TIAN_PING, [player.id])
	if choice == 0:
		var all_cards: Array = player.hand_cards.duplicate()
		engine.take_from_hand(player.id, all_cards)
		engine.to_discard(all_cards)
		engine._log_discard(player.id, all_cards)
	else:
		var need: int = player.hand_cards_max - player.hand_cards.size()
		if need > 0:
			engine.draw(player.id, need)
		engine.set_team_gem(player.color, engine.team_gem[player.color] + 1)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 工具
# ============================================================
## 增加审判指示物（以指示物上限封顶）
func _add_token(n: int) -> void:
	var v: int = int(player.tokens[0]["num"]) + n
	v = clampi(v, 0, int(player.tokens[0]["max"]))
	player.tokens[0]["num"] = v
	engine._broadcast_game()
