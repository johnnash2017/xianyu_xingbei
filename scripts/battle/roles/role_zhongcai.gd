extends BattleRole
## 仲裁者（roleID 14）—— 移植自服务端 role/ZhongCai.cpp
## 被动：仲裁法则（开局 +2 水晶）、审判浪潮（1404，每承受一次伤害 +1 审判）
## 指示物：tokens[0] = 审判，上限见角色表
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

## 服务端 setHandCardsMaxFixed：普通形态 6，审判形态 5
const HAND_MAX_NORMAL: int = 6
const HAND_MAX_TRIAL: int = 5


func setup(p: BattlePlayer, e: BattleEngine) -> void:
	super.setup(p, e)
	# 仲裁法则：游戏初始时，你 +2 水晶
	p.set_crystal(2)


## 【审判】指示物的上限（以角色表为准）
func _shen_pan_max() -> int:
	return int(player.tokens[0]["max"])


func available_skills() -> Array:
	var out: Array = []
	var t: int = int(player.tokens[0]["num"])
	out.append({"type": GConst.ActionType.MagicSkill, "id": MO_RI_SHEN_PAN, "need_card": 0, "need_target": 1,
		"enabled": t > 0})
	out.append({"type": GConst.ActionType.MagicSkill, "id": PAN_JUE_TIAN_PING, "need_card": 0, "need_target": 0,
		"arg_choices": [
			{"text": 提示(PAN_JUE_TIAN_PING, 0), "args": [0]},
			{"text": 提示(PAN_JUE_TIAN_PING, 1), "args": [1]},
		],
		"enabled": t < _shen_pan_max() and player.get_energy() > 0})
	# 启动技能：按形态互斥（每回合只能发动一个，由引擎统一下发/校验）
	out.append({"type": GConst.ActionType.SpecialSkill, "id": YI_SHI_ZHONG_DUAN, "need_card": 0, "need_target": 0,
		"enabled": player.tap})
	out.append({"type": GConst.ActionType.SpecialSkill, "id": ZHONG_CAI_YI_SHI, "need_card": 0, "need_target": 0,
		"enabled": not player.tap and player.gem > 0})
	return out


## 【仪式中断】【仲裁仪式】为「启动」：不消耗本回合行动，发动后行动阶段照旧继续
func is_free_skill(skill_id: int) -> bool:
	return skill_id == YI_SHI_ZHONG_DUAN or skill_id == ZHONG_CAI_YI_SHI


# ============================================================
# 行动校验覆写：审判达到上限时强制只能发动【末日审判】
# 对应服务端 ZhongCai::v_allow_action：token[0] 满 4 时，攻击 / 法术 / 特殊 / 放弃一律非法
# 引擎的钩子不携带 action_id，故此处只按动作类型放行「法术技能」，
# 非【末日审判】的法术（如判决天平）由 v_magic_skill 中的 token 上限检查继续驳回
# ============================================================
func v_allow_action(action_type: int, args: Array, allow: int, can_give_up: bool) -> int:
	var base: int = player.base_v_allow_action(action_type, args, allow, can_give_up)
	if int(player.tokens[0]["num"]) < _shen_pan_max():
		return base
	# 服务端 ZhongCai::v_allow_action：满审判时仍允许「放弃行动」
	if can_give_up and action_type == GConst.ActionType.None:
		return GConst.GE_SUCCESS
	if action_type == GConst.ActionType.MagicSkill:
		return GConst.GE_SUCCESS
	# 【仪式中断】【仲裁仪式】是「启动」技能，原版在行动阶段之前询问、不受满审判限制
	# （【仪式中断】还是脱离审判形态的唯一手段），故这里放行 SpecialSkill；
	# 具体哪个技能能不能发动由 v_special_skill 按技能号继续把关
	if action_type == GConst.ActionType.SpecialSkill:
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


# ============================================================
# 启动技能（行动阶段按钮）：仪式中断（1401）/ 仲裁仪式（1402）
# （「每回合只能发动一个启动技能」由引擎统一把关，这里只校验各自的形态/资源条件）
# ============================================================
func v_special_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	match int(action.get("action_id", 0)):
		YI_SHI_ZHONG_DUAN:
			# 仅【审判形态】（横置）下可发动
			if not player.tap:
				return GConst.GE_INVALID_ACTION
		ZHONG_CAI_YI_SHI:
			# 未横置（不在形态里）且有宝石时可发动
			if player.tap or player.gem <= 0:
				return GConst.GE_INVALID_ACTION
		_:
			return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_special_skill(action: Dictionary) -> int:
	match int(action.get("action_id", 0)):
		YI_SHI_ZHONG_DUAN:
			_apply_yi_shi_zhong_duan()
		ZHONG_CAI_YI_SHI:
			_apply_zhong_cai_yi_shi()
	return SUCCESS


## 仪式中断：脱离【审判形态】，我方战绩区 +1 宝石，手牌上限恢复
func _apply_yi_shi_zhong_duan() -> void:
	notice_skill(YI_SHI_ZHONG_DUAN, [player.id])
	player.boot_skill_used = true
	engine.set_team_gem(player.color, engine.team_gem[player.color] + 1)
	player.tap = false
	player.hand_cards_max = HAND_MAX_NORMAL
	engine._broadcast_game()


## 仲裁仪式：耗 1 宝石，横置进入【审判形态】，手牌上限固定为 5
func _apply_zhong_cai_yi_shi() -> void:
	notice_skill(ZHONG_CAI_YI_SHI, [player.id])
	player.boot_skill_used = true
	player.set_gem(player.gem - 1)
	player.tap = true
	player.hand_cards_max = HAND_MAX_TRIAL
	engine._broadcast_game()


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
			if token >= _shen_pan_max() or action.get("args", []).is_empty() or player.get_energy() == 0:
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
			engine.push_draw(player.id, need)
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
