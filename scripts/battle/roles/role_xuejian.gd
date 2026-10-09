extends BattleRole
## 血色剑灵（roleID 34）—— 移植自服务端 role/XueJian.cpp
## 形态：tap（血蔷薇庭院/横置形态，禁用全场治疗结算）+ 鲜血指示物（上限 3）
## 技能：血色荆棘（3401，被动：自身攻击命中后 +1 鲜血）、
##       赤色一闪（3402，额外攻击行动：鲜血≥1 时追加一次攻击，耗 1 鲜血并自身受 2 点法术伤害）、
##       血染蔷薇（3403，法术技能：耗 2 鲜血，目标 -2 治疗、另一角色 1 水晶转 1 宝石；
##                 横置形态下再对全场每名角色各 1 点法术伤害）、
##       血气屏障（3404，响应：受法术伤害且有鲜血时询问，伤害 -1、耗 1 鲜血并对指定角色 1 点法术伤害）、
##       血蔷薇庭院（3405，启动：耗 1 宝石或 1 水晶进入横置形态并 +2 鲜血，宝石方案还需弃牌到 4 张）

const XUE_SE_JING_JI: int = 3401
const CHI_SE_YI_SHAN: int = 3402
const XUE_RAN_QIANG_WEI: int = 3403
const XUE_QI_PING_ZHANG: int = 3404
const XUE_QIANG_WEI_BOOT: int = 3405

func available_skills() -> Array:
	var out: Array = []
	if int(player.tokens[0]["num"]) >= 2:
		out.append({"type": GConst.ActionType.MagicSkill, "id": XUE_RAN_QIANG_WEI, "need_card": 0, "need_target": 2})
	return out


# ============================================================
# 自身攻击命中后：血色荆棘（+1 鲜血，被动）
# ============================================================
func p_timeline_2_hit(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("src", -1)) != player.id:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	step = STEP_DONE
	notice_skill(XUE_SE_JING_JI, [player.id])
	# 服务端 setToken(0, token+1)：以指示物上限封顶
	if int(player.tokens[0]["num"]) < int(player.tokens[0]["max"]):
		player.tokens[0]["num"] = int(player.tokens[0]["num"]) + 1
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 攻击行动结束后：赤色一闪（鲜血≥1 时授予一次攻击行动，代价在选中时结算）
# ============================================================
func p_after_attack(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id or int(player.tokens[0]["num"]) < 1:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	step = STEP_DONE
	player.add_action(GConst.ActionType.Attack, CHI_SE_YI_SHAN)
	return SUCCESS


# ============================================================
# 玩家选中额外行动时：结算赤色一闪的代价（耗 1 鲜血并自身受 2 点法术伤害）
# 引擎在选中时会统一广播技能通知，故此处只结算指示物与伤害
# ============================================================
func p_additional_action(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if int(ctx.get("cause", 0)) != CHI_SE_YI_SHAN:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	step = STEP_DONE
	player.tokens[0]["num"] = int(player.tokens[0]["num"]) - 1
	engine._broadcast_game()
	engine.push_harm({
		"src": player.id, "dst": player.id, "point": 2,
		"cause": CHI_SE_YI_SHAN, "type": GConst.HarmType.Magic,
	})
	return URGENT


# ============================================================
# 主动法术技能：血染蔷薇
# ============================================================
func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != XUE_RAN_QIANG_WEI:
		return GConst.GE_INVALID_ACTION
	if int(player.tokens[0]["num"]) < 2:
		return GConst.GE_INVALID_ACTION
	# 服务端直接取 dst_ids(0)/dst_ids(1)
	var dsts: Array = action.get("dst_ids", [])
	if dsts.size() < 2:
		return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != XUE_RAN_QIANG_WEI:
		return GConst.GE_INVALID_ACTION
	var dsts: Array = action.get("dst_ids", [])
	if dsts.size() < 2:
		return GConst.GE_INVALID_ACTION
	notice_skill(XUE_RAN_QIANG_WEI, dsts)
	player.tokens[0]["num"] = int(player.tokens[0]["num"]) - 2
	# 目标 -2 治疗
	var dst1: BattlePlayer = engine.p(int(dsts[0]))
	if dst1 != null:
		dst1.sub_cross_num(2)
	# 己方角色 1 水晶转 1 宝石
	var dst2: BattlePlayer = engine.p(int(dsts[1]))
	if dst2 != null and dst2.crystal > 0:
		dst2.set_crystal(dst2.crystal - 1)
		dst2.set_gem(dst2.gem + 1)
	engine._broadcast_game()
	if not player.tap:
		return SUCCESS
	# 横置形态：按座位顺序对每名角色各造成 1 点法术伤害
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
# 受到法术伤害时：血气屏障（伤害 -1、耗 1 鲜血并对指定角色 1 点法术伤害）
# ============================================================
func p_timeline_3(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("dst", -1)) != player.id:
		return SUCCESS
	if int(harm.get("type", -1)) != GConst.HarmType.Magic:
		return SUCCESS
	if int(player.tokens[0]["num"]) <= 0:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if not engine.has_reply():
		询问(player.id, XUE_QI_PING_ZHANG, 0, 1)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		return SUCCESS
	var dsts: Array = r.get("dst_ids", [])
	if dsts.is_empty():
		return SUCCESS
	notice_skill(XUE_QI_PING_ZHANG, dsts)
	harm["point"] = int(harm.get("point", 0)) - 1
	player.tokens[0]["num"] = int(player.tokens[0]["num"]) - 1
	engine.push_harm({
		"src": player.id, "dst": int(dsts[0]), "point": 1,
		"cause": XUE_QI_PING_ZHANG, "type": GConst.HarmType.Magic,
	})
	engine._broadcast_game()
	return URGENT


# ============================================================
# 血蔷薇庭院：横置形态下关闭本次治疗结算（服务端 XueJian::p_timeline_4：crossAvailable = 0）
# ============================================================
func p_timeline_4(ctx: Dictionary) -> int:
	if not player.tap:
		return SUCCESS
	var harm: Dictionary = ctx.get("harm", {})
	harm["cross_available"] = 0
	return SUCCESS


# ============================================================
# 启动：血蔷薇庭院（自身回合且有能量时询问）
# ============================================================
func p_boot(_ctx: Dictionary) -> int:
	if engine.current_id != player.id or player.get_energy() == 0:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if not engine.has_reply():
		# 两个方案（args[0]）：1=宝石、2=水晶（无水晶则 1 宝石）；宝石方案可选要弃的牌
		询问(player.id, XUE_QIANG_WEI_BOOT, maxi(player.hand_cards.size() - 4, 0), 0,
			GConst.CardSource.Hand, [
				{"value": 1, "label": "耗 1 宝石：+2 鲜血并弃牌到 4 张"},
				{"value": 2, "label": "耗 1 水晶（无则 1 宝石）：+2 鲜血"},
			])
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	var args: Array = r.get("args", [])
	if args.is_empty():
		return SUCCESS
	var choice: int = int(args[0])
	if choice == 1:
		# 宝石方案：-1 宝石，鲜血置为「大于 1 则 4，否则 +2」并把多余手牌弃到 4 张
		player.set_gem(player.gem - 1)
		player.tap = true
		player.tokens[0]["num"] = 4 if int(player.tokens[0]["num"]) > 1 else int(player.tokens[0]["num"]) + 2
		notice_skill(XUE_QIANG_WEI_BOOT, [player.id])
		engine._broadcast_game()
		var cards: Array = r.get("card_ids", [])
		_discard_down_to_4(cards)
		return SUCCESS
	if choice == 2:
		# 水晶方案：-1 水晶（无水晶则 -1 宝石），鲜血 +2（以指示物上限封顶）
		if player.crystal > 0:
			player.set_crystal(player.crystal - 1)
		else:
			player.set_gem(player.gem - 1)
		player.tap = true
		var v: int = int(player.tokens[0]["num"]) + 2
		var cap: int = int(player.tokens[0]["max"])
		if v <= cap:
			player.tokens[0]["num"] = v
		elif int(player.tokens[0]["num"]) <= cap:
			player.tokens[0]["num"] = cap
		notice_skill(XUE_QIANG_WEI_BOOT, [player.id])
		engine._broadcast_game()
	return SUCCESS


## 把手牌弃到 4 张（客户端优先给出要弃的牌，不足时从手牌补齐）
func _discard_down_to_4(cards: Array) -> void:
	var over: int = player.hand_cards.size() - 4
	if over <= 0:
		return
	var chosen: Array = []
	for c: Variant in cards:
		if chosen.size() < over and player.has_hand_card(int(c)):
			chosen.append(int(c))
	if chosen.size() < over:
		for cid: int in player.hand_cards:
			if chosen.size() >= over:
				break
			if not chosen.has(cid):
				chosen.append(cid)
	engine.take_from_hand(player.id, chosen)
	engine.to_discard(chosen)
	engine._log_discard(player.id, chosen)
	engine._broadcast_game()


func p_turn_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id or not player.tap:
		return SUCCESS
	player.tap = false
	engine._broadcast_game()
	return SUCCESS
