extends BattleRole
## 血色剑灵（roleID 34）—— 以设计表当前「技能表」说明为准。
## 指示物：tokens[0] = 【鲜血】（上限见角色表，默认 3）
## 状态：xue_qiang_wei = 【血蔷薇庭院】在场（独立状态图标，不是横置形态）
## 技能：
##   血色荆棘（3401，被动）：攻击命中时 +1【鲜血】。主动攻击、应战攻击、额外攻击都算。
##   赤色一闪（3402，响应）：攻击行动结束后可发动；-1【鲜血】、自己受 2 点法术伤害，
##                 额外 +1【攻击行动】。【鲜血】不足 1 时不询问、也不能发动。
##   血染蔷薇（3403，法术）：-2【鲜血】；目标角色 -2【治疗】；
##                 若我方有角色拥有【水晶】，再选择一名我方角色，将其 1【水晶】翻面为 1【宝石】；
##                 若【血蔷薇庭院】在场，额外对所有角色各造成 1 点法术伤害。
##   血气屏障（3404，响应）：受到法术伤害时，可 -1【鲜血】，本次法术伤害 -1，
##                 并对目标对手造成 1 点法术伤害。目标由玩家自己选择，只能选对手；
##                 自己对自己造成的法术伤害也会触发，也不检查伤害来源。
##   血蔷薇庭院（3405，被动）：此卡在场时，所有角色的【治疗】无法用于抵御伤害；
##                 血色剑灵的回合结束时移除此卡。
##   散华轮舞（3406，启动）：选择一项发动：
##                 ● -1【水晶】：将【血蔷薇庭院】放置于场上，+2【鲜血】。
##                 ● -1【宝石】：将【血蔷薇庭院】放置于场上，无视【鲜血】上限 +2【鲜血】
##                   （【鲜血】最高为 4），并将手牌弃至 4 张。

const XUE_SE_JING_JI: int = 3401
const CHI_SE_YI_SHAN: int = 3402
const XUE_RAN_QIANG_WEI: int = 3403
## 血染蔷薇的第二步：选择一名有【水晶】的友方角色（内部询问号，不单独占技能表行）
const XUE_RAN_QIANG_WEI_CRYSTAL: int = 34031
const XUE_QI_PING_ZHANG: int = 3404
const XUE_QIANG_WEI: int = 3405
const SAN_HUA_LUN_WU: int = 3406

## 血染蔷薇的分步进度：0＝还没走到第二步 / XUE_RAN_QIANG_WEI_CRYSTAL＝在等选择友方水晶目标
var _xue_ran_step: int = 0


func available_skills() -> Array:
	var out: Array = []
	# 血染蔷薇：先选 1 名目标（任意角色）；第二步若存在有【水晶】的友方，再问一次。
	out.append({"type": GConst.ActionType.MagicSkill, "id": XUE_RAN_QIANG_WEI, "need_card": 0, "need_target": 1,
		"enabled": int(player.tokens[0]["num"]) >= 2})
	# 散华轮舞：启动技能，技能栏按钮；点了才在二级栏里二选一。
	# 弃牌张数只放在宝石选项自己的 need_card 上：水晶选项不弃牌，技能本体不能设 card_max，
	# 否则客户端会把宝石方案的最多牌数当成普惠上限，导致水晶选项也被要求先选牌。
	var 需弃: int = maxi(player.hand_cards.size() - 4, 0)
	out.append({"type": GConst.ActionType.SpecialSkill, "id": SAN_HUA_LUN_WU,
		"need_card": 0, "need_target": 0,
		"arg_choices": [
			{"text": 提示原文(SAN_HUA_LUN_WU, 0),
				"说明": 提示原文(SAN_HUA_LUN_WU, 1),
				"args": [1], "enabled": player.crystal > 0 or player.gem > 0},
			{"text": 提示原文(SAN_HUA_LUN_WU, 2),
				"说明": 提示原文(SAN_HUA_LUN_WU, 3),
				"args": [2], "need_card": 需弃, "enabled": player.gem > 0},
		],
		"enabled": player.crystal > 0 or player.gem > 0})
	return out


## 【散华轮舞】为「启动」：不消耗本回合行动，发动后行动阶段照旧继续
func is_free_skill(skill_id: int) -> bool:
	return skill_id == SAN_HUA_LUN_WU


## 加【鲜血】：不超过 上限；当前已经高于 上限（散华轮舞宝石方案到 4）时不往下压
func _gain_blood(n: int, 上限: int) -> void:
	var t: Dictionary = player.tokens[0]
	var 新值: int = int(t["num"]) + n
	t["num"] = mini(新值, maxi(上限, int(t["num"])))


## 从客户端交来的牌里挑出该玩家真正拥有的前 n 张
func _pick_cards(target: BattlePlayer, ids: Array, n: int) -> Array:
	var out: Array = []
	for c: Variant in ids:
		if out.size() >= n:
			break
		var cid: int = int(c)
		if target.has_hand_card(cid) and not out.has(cid):
			out.append(cid)
	return out


## 我方角色（含自己）：血染蔷薇第二步必须从这里面选一名；
## 不再要求目标先有【水晶】——没有水晶也可以选，翻面效果空放
func _friendly_ids() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		var p0: BattlePlayer = engine.p(pid)
		if p0 != null and p0.color == player.color:
			out.append(pid)
	return out


# ============================================================
# 自身攻击命中后：血色荆棘（+1【鲜血】，被动）
# ============================================================
func p_timeline_2_hit(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("src", -1)) != player.id:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	step = STEP_DONE
	notice_skill(XUE_SE_JING_JI, [player.id])
	_gain_blood(1, int(player.tokens[0]["max"]))
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 攻击行动结束后：赤色一闪（有【鲜血】才挂额外攻击；代价在玩家选中时结算）
# ============================================================
func p_after_attack(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id or int(player.tokens[0]["num"]) < 1:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	step = STEP_DONE
	player.add_action(GConst.ActionType.Attack, CHI_SE_YI_SHAN, false, false, {
		"in_end_response": true,
	})
	return SUCCESS


## 玩家选中额外行动时：-1【鲜血】，自己受 2 点法术伤害



## 行动结束响应点选赤色一闪时立即扣 1 鲜血并受 2 点法术伤害（方案 A）
func 行动结束确认代价(cause: int) -> int:
	if cause != CHI_SE_YI_SHAN:
		return SUCCESS
	if int(player.tokens[0]["num"]) < 1:
		return GConst.GE_INVALID_ACTION
	player.tokens[0]["num"] = int(player.tokens[0]["num"]) - 1
	engine._broadcast_game()
	engine.push_harm({
		"src": player.id, "dst": player.id, "point": 2,
		"cause": CHI_SE_YI_SHAN, "type": GConst.HarmType.Magic,
	})
	return URGENT


func p_additional_action(_ctx: Dictionary) -> int:
	return SUCCESS


# ============================================================
# 主动法术技能：血染蔷薇
# ============================================================
func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != XUE_RAN_QIANG_WEI:
		return GConst.GE_INVALID_ACTION
	if not engine.has_reply():
		_xue_ran_step = 0
	if int(player.tokens[0]["num"]) < 2:
		return GConst.GE_INVALID_ACTION
	var dsts: Array = action.get("dst_ids", [])
	if dsts.size() != 1:
		return GConst.GE_INVALID_ACTION
	if engine.p(int(dsts[0])) == null:
		return GConst.GE_INVALID_PLAYERID
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != XUE_RAN_QIANG_WEI:
		return GConst.GE_INVALID_ACTION
	var dsts: Array = action.get("dst_ids", [])
	if dsts.size() != 1:
		return GConst.GE_INVALID_ACTION
	var 第一目标: int = int(dsts[0])
	var 第二目标: int = -1
	if _xue_ran_step == 0:
		var 友方: Array[int] = _friendly_ids()
		# 第二步不再因为「没有友方带水晶」而跳过：所有友方都可选，
		# 选中的人有水晶才翻面，没有水晶就空放，其他效果照常结算。
		_xue_ran_step = XUE_RAN_QIANG_WEI_CRYSTAL
		engine.ask_skill(player.id, XUE_RAN_QIANG_WEI_CRYSTAL, 0, 1, GConst.CardSource.Hand,
			[], 0, "", [], false,
			提示原文(XUE_RAN_QIANG_WEI, 0),
			友方)
		return WAIT
	elif _xue_ran_step == XUE_RAN_QIANG_WEI_CRYSTAL:
		var r: Dictionary = take_skill_reply_full()
		_xue_ran_step = 0
		var 选出: Array = r.get("dst_ids", [])
		if 选出.is_empty():
			return SUCCESS
		第二目标 = int(选出[0])
		if not _friendly_ids().has(第二目标):
			return SUCCESS
	var 目标1: BattlePlayer = engine.p(第一目标)
	if 目标1 == null:
		return SUCCESS
	notice_skill(XUE_RAN_QIANG_WEI, [第一目标] if 第二目标 < 0 else [第一目标, 第二目标])
	player.tokens[0]["num"] = maxi(int(player.tokens[0]["num"]) - 2, 0)
	# 目标角色 -2【治疗】
	目标1.sub_cross_num(2)
	# 第二步选中的友方角色：1【水晶】翻面为 1【宝石】
	if 第二目标 >= 0:
		var 目标2: BattlePlayer = engine.p(第二目标)
		if 目标2 != null and 目标2.crystal > 0:
			目标2.set_crystal(目标2.crystal - 1)
			目标2.set_gem(目标2.gem + 1)
	engine._broadcast_game()
	if not player.xue_qiang_wei:
		return SUCCESS
	# 【血蔷薇庭院】在场：按座位顺序对每名角色各造成 1 点法术伤害
	# 服务端先收集 [自己, post...] 再 reverse 后压栈（LIFO），实际结算顺序是「自己 → post 顺序」；
	# 本引擎 push 同样是 LIFO，故这里按反序压栈以还原同一次序
	var ids: Array[int] = []
	var nid: int = player.id
	for _i: int in range(engine.order.size()):
		ids.append(nid)
		nid = engine.next_id(nid)
	for i: int in range(ids.size() - 1, -1, -1):
		engine.push_harm({
			"src": player.id, "dst": ids[i], "point": 1,
			"cause": XUE_RAN_QIANG_WEI, "type": GConst.HarmType.Magic,
		})
	engine._broadcast_game()
	return URGENT


# ============================================================
# 受到法术伤害时：血气屏障（-1【鲜血】、本次伤害 -1、对目标对手 1 点法术伤害）
# ============================================================
func p_timeline_3(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("dst", -1)) != player.id:
		return SUCCESS
	if int(harm.get("type", -1)) != GConst.HarmType.Magic:
		return SUCCESS
	if int(player.tokens[0]["num"]) <= 0:
		return SUCCESS
	if int(harm.get("point", 0)) <= 0:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if not engine.has_reply():
		var 对手: Array[int] = enemy_ids()
		if 对手.is_empty():
			return SUCCESS
		engine.ask_skill(player.id, XUE_QI_PING_ZHANG, 0, 1, GConst.CardSource.Hand,
			[], 0, "", [], true,
			提示原文(XUE_QI_PING_ZHANG, 0),
			对手, int(harm.get("point", 0)), GConst.HarmType.Magic)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		return SUCCESS
	var dsts: Array = r.get("dst_ids", [])
	if dsts.is_empty():
		return SUCCESS
	var 目标: int = int(dsts[0])
	if not enemy_ids().has(目标):
		return SUCCESS
	notice_skill(XUE_QI_PING_ZHANG, [目标])
	harm["point"] = maxi(int(harm.get("point", 0)) - 1, 0)
	player.tokens[0]["num"] = maxi(int(player.tokens[0]["num"]) - 1, 0)
	engine.push_harm({
		"src": player.id, "dst": 目标, "point": 1,
		"cause": XUE_QI_PING_ZHANG, "type": GConst.HarmType.Magic,
	})
	engine._broadcast_game()
	return URGENT


# ============================================================
# 血蔷薇庭院（被动）：在场时关闭所有角色用【治疗】抵御伤害
# ============================================================
func p_timeline_4(ctx: Dictionary) -> int:
	if not player.xue_qiang_wei:
		return SUCCESS
	var harm: Dictionary = ctx.get("harm", {})
	harm["cross_available"] = 0
	return SUCCESS


# ============================================================
# 启动：散华轮舞（3406）
# ============================================================
func v_special_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != SAN_HUA_LUN_WU:
		return GConst.GE_INVALID_ACTION
	var args: Array = action.get("args", [])
	var choose: int = int(args[0]) if not args.is_empty() else 0
	if choose == 1:
		# 本游戏的通用规则：没有【水晶】时，宝石可以当水晶用
		if player.crystal <= 0 and player.gem <= 0:
			return GConst.GE_INVALID_ACTION
	elif choose == 2:
		if player.gem <= 0:
			return GConst.GE_INVALID_ACTION
		var 需弃: int = maxi(player.hand_cards.size() - 4, 0)
		var cards: Array = action.get("card_ids", [])
		if cards.size() != 需弃:
			return GConst.GE_INVALID_ARGUMENT
		for c: Variant in cards:
			if not player.has_hand_card(int(c)):
				return GConst.GE_INVALID_CARDID
	else:
		return GConst.GE_INVALID_ARGUMENT
	return GConst.GE_SUCCESS


func p_special_skill(action: Dictionary) -> int:
	var args: Array = action.get("args", [])
	var choose: int = int(args[0]) if not args.is_empty() else 0
	var 需弃: int = maxi(player.hand_cards.size() - 4, 0)
	var 弃牌: Array = []
	if choose == 1:
		if player.crystal <= 0 and player.gem <= 0:
			return SUCCESS
	elif choose == 2:
		if player.gem <= 0:
			return SUCCESS
		弃牌 = _pick_cards(player, action.get("card_ids", []), 需弃)
		if 弃牌.size() != 需弃:
			return SUCCESS
	else:
		return SUCCESS
	notice_skill(SAN_HUA_LUN_WU, [player.id])
	player.boot_skill_used = true
	if choose == 1:
		# 有【水晶】先扣水晶；没有就用【宝石】代替
		if player.crystal > 0:
			player.set_crystal(player.crystal - 1)
		else:
			player.set_gem(player.gem - 1)
		_gain_blood(2, int(player.tokens[0]["max"]))
	else:
		player.set_gem(player.gem - 1)
		_gain_blood(2, 4)
		if not 弃牌.is_empty():
			engine.take_from_hand(player.id, 弃牌)
			engine.to_discard(弃牌)
			engine._log_discard(player.id, 弃牌)
	player.xue_qiang_wei = true
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 血色剑灵的回合结束：移除【血蔷薇庭院】
# ============================================================
func p_turn_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id or not player.xue_qiang_wei:
		return SUCCESS
	player.xue_qiang_wei = false
	engine._broadcast_game()
	return SUCCESS
