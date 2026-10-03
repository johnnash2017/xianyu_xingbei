extends BattleRole
## 蝶舞者（roleID 24）—— 移植自服务端 role/DieWu.cpp
## 【被动】生命之火：手牌上限 = max(3, 6 - 【蛹】数)
## 【法术】舞动（2402）：摸 1 张牌或弃 1 张牌，将牌库顶 1 张作为【茧】
## 【响应】毒粉（2403）：有角色产生 1 点法术伤害时，移除 1 个【茧】使该伤害 +1
## 【响应】朝圣（2404）：自身承受伤害时，移除 1 个【茧】抵御该来源 1 点伤害
## 【响应】镜花水月（2405）：有角色产生 2 点法术伤害时，移除 2 个同系【茧】抵御该伤害，
##                  并对伤害目标造成 2 次各 1 点法术伤害
## 【响应】凋零（2406）：每次移除【茧】时，若该牌为法术牌可展示：对目标角色 1 点、对自己 2 点法术伤害；
##                  此形态持续到自己下个回合开始前，期间对方士气最少为 1
## 【法术】蛹化（2407）：耗 1 宝石，+1【蛹】，将牌库顶 4 张作为【茧】
## 【法术】倒逆之蝶（2408）：耗 1 能量、弃 2 张手牌，选择：对目标角色造成 1 点不能以治疗抵御的法术伤害；
##                  或（移除 2 个【茧】或对自己造成 4 点法术伤害）后移除 1 点【蛹】
## 【茧】为专属盖牌，上限 8；【蛹】为专属指示物，无上限

const SHENG_MING_ZHI_HUO: int = 2401
const WU_DONG: int = 2402
const WU_DONG_EXTRA: int = 24021
const DU_FEN: int = 2403
const CHAO_SHENG: int = 2404
const JING_HUA_SHUI_YUE: int = 2405
const DIAO_LING: int = 2406
const YONG_HUA: int = 2407
const DAO_NI_ZHI_DIE: int = 2408

## 待结算【凋零】的茧（每次移除【茧】时逐张询问是否发动）
var _diao_queue: Array[int] = []
var _diao_idx: int = 0
var _diao_harms: Array[Dictionary] = []


func setup(p: BattlePlayer, e: BattleEngine) -> void:
	super.setup(p, e)
	# 【茧】为专属盖牌，上限 8；【蛹】为专属指示物（无上限，服务端 tokenMax[0] = 99）
	p.cover_cards_max = 8
	p.tokens[0] = {"name": "蛹", "max": 99, "num": 0}
	p.hand_cards_max = _life_fire_max()


func available_skills() -> Array:
	var out: Array = []
	# 舞动：服务端不校验，args[0]=1 摸 1 张，否则弃 1 张（弃牌时才需选 1 张手牌）
	out.append({"type": GConst.ActionType.MagicSkill, "id": WU_DONG, "need_card": 0, "need_target": 0,
		"arg_choices": [
			{"text": "摸 1 张牌", "args": [1]},
			{"text": "弃 1 张牌", "args": [0], "need_card": 1},
		]})
	if player.gem > 0:
		out.append({"type": GConst.ActionType.MagicSkill, "id": YONG_HUA, "need_card": 0, "need_target": 0})
	if player.get_energy() > 0:
		out.append({"type": GConst.ActionType.MagicSkill, "id": DAO_NI_ZHI_DIE, "need_card": 2, "need_target": 0,
			"target_max": 1, "arg_choices": _dao_ni_choices()})
	return out


## 倒逆之蝶的参数选项：弃 2 张手牌后选择分支
## ●choice=1 对目标造成 1 点法术伤害（需目标）；●choice=2 移除一对【茧】（args 带两张盖牌 id）
func _dao_ni_choices() -> Array:
	var out: Array = [
		{"text": "对目标造成 1 点法术伤害", "args": [1], "need_card": 2, "need_target": 1},
		{"text": "对自己造成 4 点法术伤害", "args": [0], "need_card": 2},
	]
	# 【茧】两两组合，args 里按 id 升序放两张盖牌（服务端从 args(1..2) 读取）
	var covers: Array = player.cover_cards
	for i: int in range(covers.size()):
		for j: int in range(i + 1, covers.size()):
			var a: int = mini(int(covers[i]), int(covers[j]))
			var b: int = maxi(int(covers[i]), int(covers[j]))
			out.append({
				"text": "移除【茧】%s、%s" % [_cover_name(a), _cover_name(b)],
				"args": [2, a, b], "need_card": 2,
			})
	return out


## 取【茧】（盖牌）的卡名，用于参数按钮文案
func _cover_name(cid: int) -> String:
	var card: GCard = Data.get_card(cid)
	return card.card_name if card != null else str(cid)


# ============================================================
# 主动法术技能
# ============================================================
func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	var aid: int = int(action.get("action_id", 0))
	var args: Array = action.get("args", [])
	match aid:
		WU_DONG:
			return GConst.GE_SUCCESS
		YONG_HUA:
			if player.gem == 0:
				return GConst.GE_INVALID_ACTION
			return GConst.GE_SUCCESS
		DAO_NI_ZHI_DIE:
			if player.get_energy() == 0:
				return GConst.GE_INVALID_ACTION
			var choice: int = int(args[0]) if not args.is_empty() else 0
			# 服务端：非第一分支时必须拥有【蛹】
			if choice != 1 and int(player.tokens[0]["num"]) < 1:
				return GConst.GE_INVALID_ACTION
			if action.get("card_ids", []).size() < 2:
				return GConst.GE_INVALID_CARDID
			return GConst.GE_SUCCESS
	return GConst.GE_INVALID_ACTION


func p_magic_skill(action: Dictionary) -> int:
	match int(action.get("action_id", 0)):
		WU_DONG:
			return _wu_dong(action)
		YONG_HUA:
			return _yong_hua()
		DAO_NI_ZHI_DIE:
			return _dao_ni_zhi_die(action)
	return GConst.GE_INVALID_ACTION


## 舞动：args[0]=1 摸 1 张牌，否则弃 1 张牌；随后将牌库顶 1 张作为【茧】
func _wu_dong(action: Dictionary) -> int:
	var args: Array = action.get("args", [])
	var flag: int = int(args[0]) if not args.is_empty() else 0
	notice_skill(WU_DONG, [player.id])
	if flag == 1:
		engine.draw(player.id, 1)
	else:
		_discard_hand_cards(action.get("card_ids", []), 1)
	var top: Array[int] = engine.deck.draw(1)
	_add_cover(top, WU_DONG)
	engine._broadcast_game()
	return SUCCESS


## 蛹化：耗 1 宝石，+1【蛹】，将牌库顶 4 张作为【茧】
func _yong_hua() -> int:
	notice_skill(YONG_HUA, [player.id])
	player.set_gem(player.gem - 1)
	_set_yong(1)
	var top: Array[int] = engine.deck.draw(4)
	_add_cover(top, YONG_HUA)
	engine._broadcast_game()
	return SUCCESS


## 倒逆之蝶：弃 2 张手牌、耗 1 能量，随后按分支结算
func _dao_ni_zhi_die(action: Dictionary) -> int:
	var args: Array = action.get("args", [])
	var choice: int = int(args[0]) if not args.is_empty() else 0
	var dsts: Array = action.get("dst_ids", [])
	if step == 0:
		notice_skill(DAO_NI_ZHI_DIE, dsts if choice == 1 else [player.id])
		_discard_hand_cards(action.get("card_ids", []), 2)
		if player.crystal > 0:
			player.set_crystal(player.crystal - 1)
		else:
			player.set_gem(player.gem - 1)
		if choice == 1 and not dsts.is_empty():
			# ●对目标角色造成 1 点法术伤害（治疗不可抵御，见 p_timeline_4）
			engine.push_harm({
				"src": player.id, "dst": int(dsts[0]), "point": 1,
				"cause": DAO_NI_ZHI_DIE, "type": GConst.HarmType.Magic,
			})
			step = STEP_DONE
			engine._broadcast_game()
			return URGENT
		if choice == 2:
			# ●移除 2 个【茧】（服务端从 args(1..2) 读取）；移除本身会在 p_cover_change 里触发【凋零】
			var cover: Array = _cover_cards_from_args(action, 2)
			_remove_cover(cover, DAO_NI_ZHI_DIE)
		else:
			# ●对自己造成 4 点法术伤害
			engine.push_harm({
				"src": player.id, "dst": player.id, "point": 4,
				"cause": DAO_NI_ZHI_DIE, "type": GConst.HarmType.Magic,
			})
		# 移除 1 点【蛹】（服务端的第二阶段）
		_set_yong(-1)
		step = STEP_DONE
		engine._broadcast_game()
		return URGENT
	return SUCCESS


## 【毒粉 / 镜花水月】的推进阶段（0＝还没开始 / DU_FEN＝在问毒粉 / JING_HUA_SHUI_YUE＝在问镜花水月）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨若干次询问，
## 中途一旦被别的钩子轮次（改手牌 / 盖牌 / 基础效果 / 横置…）插进来，step 就被抹掉、流程退回第 0 步。
## 每次有角色产生法术伤害（p_timeline_5）触发一次，收尾清回 0（留 STEP_DONE 会让下一次触发不再发动）
var _du_fen_step: int = 0


# ============================================================
# 法术伤害结算时（timeline_5）：毒粉 → 镜花水月
# （凋零不在这里：它在「移除【茧】」时由 p_cover_change 触发）
# ============================================================
func p_timeline_5(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("type", -1)) != GConst.HarmType.Magic:
		return SUCCESS
	if _du_fen_step == 0:
		_du_fen_step = DU_FEN
	if _du_fen_step == DU_FEN:
		var r: int = _du_fen(harm)
		if r == WAIT:
			return WAIT
		_du_fen_step = JING_HUA_SHUI_YUE
		if r == URGENT:
			return URGENT
	if _du_fen_step == JING_HUA_SHUI_YUE:
		var r2: int = _jing_hua_shui_yue(harm)
		if r2 == WAIT:
			return WAIT
		_du_fen_step = 0
		return r2
	return SUCCESS


## 毒粉：伤害恰为 1 点时，移除 1 个【茧】使该伤害 +1
func _du_fen(harm: Dictionary) -> int:
	if int(harm.get("point", 0)) != 1 or player.cover_cards.is_empty():
		return SUCCESS
	if not engine.has_reply():
		询问(player.id, DU_FEN, 1, 0, GConst.CardSource.Cover)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		return SUCCESS
	var cid: int = _cover_card_from_reply(r)
	if cid < 0:
		return SUCCESS
	notice_skill(DU_FEN, [int(harm.get("dst", -1))])
	# 服务端移牌 isShown=false：不移牌展示这张【茧】
	_remove_cover([cid], DU_FEN)
	harm["point"] = int(harm.get("point", 0)) + 1
	engine._broadcast_game()
	# 服务端移除盖牌后返回 GE_URGENT：让 p_cover_change（凋零）先跑，再回来继续镜花水月
	return URGENT


## 镜花水月：伤害恰为 2 点时，移除 2 个同系【茧】抵御该伤害，并对伤害目标造成 2 次 1 点法术伤害
func _jing_hua_shui_yue(harm: Dictionary) -> int:
	if int(harm.get("point", 0)) != 2 or player.cover_cards.size() < 2:
		return SUCCESS
	if not engine.has_reply():
		# 恰好 2 张，且必须同系：让客户端只让与已选牌同系的【茧】可点（服务端比较两张牌系别相同）
		询问(player.id, JING_HUA_SHUI_YUE, 2, 0, GConst.CardSource.Cover, [], 0, "same")
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		return SUCCESS
	var cards: Array = []
	for c: Variant in r.get("card_ids", []):
		if player.cover_cards.has(int(c)) and not cards.has(int(c)):
			cards.append(int(c))
	if cards.size() != 2 or _cover_elements_differ(cards[0], cards[1]):
		return SUCCESS
	var dst_id: int = int(harm.get("dst", -1))
	notice_skill(JING_HUA_SHUI_YUE, [dst_id])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": cards, "is_real": true,
	})
	# 抵御该次伤害，并各 1 点对伤害目标造成 2 次法术伤害
	harm["point"] = 0
	for _i: int in range(2):
		engine.push_harm({
			"src": player.id, "dst": dst_id, "point": 1,
			"cause": JING_HUA_SHUI_YUE, "type": GConst.HarmType.Magic,
		})
	_remove_cover(cards, JING_HUA_SHUI_YUE)
	engine._broadcast_game()
	return URGENT


## 【朝圣】的推进阶段（0＝还没开始 / 处理完本次朝圣后清回 0）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨若干次询问，
## 中途一旦被别的钩子轮次（改手牌 / 盖牌 / 基础效果 / 横置…）插进来，step 就被抹掉、流程退回第 0 步。
## 每次自身承受伤害（p_timeline_6）触发一次，收尾清回 0（留 STEP_DONE 会让下一次触发不再发动）
var _chao_sheng_step: int = 0


# ============================================================
# 自身承受伤害时（timeline_6）：朝圣
# ============================================================
func p_timeline_6(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("dst", -1)) != player.id:
		return SUCCESS
	# 本次朝圣已经处理过就不再重入：末段返回 URGENT 让 p_cover_change（凋零）先跑，
	# 引擎随后会重入本钩子，靠 ctx 上的标记挡住（原来靠 step = STEP_DONE 挡，已改用自有变量）
	if bool(ctx.get("chao_sheng_done", false)):
		return SUCCESS
	if _chao_sheng_step >= STEP_DONE:
		return SUCCESS
	if _chao_sheng_step == 0:
		if player.cover_cards.is_empty() or int(harm.get("point", 0)) < 1:
			_chao_sheng_step = 0
			return SUCCESS
		if not engine.has_reply():
			询问(player.id, CHAO_SHENG, 1, 0, GConst.CardSource.Cover)
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		var args: Array = r.get("args", [])
		if args.is_empty() or int(args[0]) != 1:
			_chao_sheng_step = 0
			return SUCCESS
		var cid: int = _chao_sheng_card(r)
		if cid < 0:
			_chao_sheng_step = 0
			return SUCCESS
		notice_skill(CHAO_SHENG, [player.id])
		# 服务端移牌 isShown=true：展示这张【茧】
		engine.broadcast(GConst.Msg.Card, {
			"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
			"card_ids": [cid], "is_real": true,
		})
		_remove_cover([cid], CHAO_SHENG)
		# 抵御该来源 1 点伤害
		harm["point"] = int(harm.get("point", 0)) - 1
		ctx["chao_sheng_done"] = true
		_chao_sheng_step = 0
		# 服务端移除盖牌后返回 GE_URGENT：让 p_cover_change（凋零）先跑
		return URGENT
	return SUCCESS


# ============================================================
# 倒逆之蝶第一分支的伤害不可用治疗抵御（服务端 DaoNiCross）
# ============================================================
func p_timeline_4(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("cause", 0)) == DAO_NI_ZHI_DIE:
		harm["cross_available"] = 0
	return SUCCESS


# ============================================================
# 凋零形态：直到自己下个回合开始前，对方的士气最少为 1
# 对应服务端 StateFixMorale 阶段（掉士气链中的 p_fix_morale）
# ============================================================
func p_fix_morale(ctx: Dictionary) -> int:
	if not player.tap:
		return SUCCESS
	var dst: BattlePlayer = engine.p(int(ctx.get("dst", -1)))
	if dst == null or dst.color == player.color:
		return SUCCESS
	var amount: int = int(ctx.get("amount", 0))
	if amount <= 0:
		return SUCCESS
	var limit: int = maxi(engine.team_morale[dst.color] - 1, 0)
	if amount > limit:
		ctx["amount"] = limit
	return SUCCESS


func p_before_turn_begin(_ctx: Dictionary) -> int:
	if engine.current_id != player.id:
		return SUCCESS
	if player.tap:
		player.tap = false
		engine._broadcast_game()
	return SUCCESS


# ============================================================
# 凋零：逐张询问被移除的【茧】是否发动
# ============================================================
func _diao_ling_process() -> int:
	while _diao_idx < _diao_queue.size():
		if not engine.has_reply():
			询问(player.id, DIAO_LING, 0, 1)
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		var args: Array = r.get("args", [])
		var dsts: Array = r.get("dst_ids", [])
		if not args.is_empty() and int(args[0]) == 1 and not dsts.is_empty():
			_diao_harms.append({"dst": int(dsts[0]), "card": _diao_queue[_diao_idx]})
		_diao_idx += 1
	var out: int = SUCCESS
	if not _diao_harms.is_empty():
		player.tap = true
		for h: Dictionary in _diao_harms:
			notice_skill(DIAO_LING, [int(h["dst"])])
			engine.broadcast(GConst.Msg.Card, {
				"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
				"card_ids": [int(h["card"])], "is_real": true,
			})
			# 先对自己 2 点、再对目标 1 点（引擎后进先出，目标先结算）
			engine.push_harm({
				"src": player.id, "dst": player.id, "point": 2,
				"cause": DIAO_LING, "type": GConst.HarmType.Magic,
			})
			engine.push_harm({
				"src": player.id, "dst": int(h["dst"]), "point": 1,
				"cause": DIAO_LING, "type": GConst.HarmType.Magic,
			})
		engine._broadcast_game()
		out = URGENT
	_diao_queue.clear()
	_diao_harms.clear()
	_diao_idx = 0
	return out


# ============================================================
# 工具
# ============================================================
## 生命之火：手牌上限最少为 3，且随【蛹】数量减少
func _life_fire_max() -> int:
	return maxi(3, GConst.HAND_CARDS_MAX - int(player.tokens[0]["num"]))


## 变更【蛹】数量并同步手牌上限
func _set_yong(delta: int) -> void:
	var t: Dictionary = player.tokens[0]
	t["num"] = clampi(int(t["num"]) + delta, 0, int(t["max"]))
	player.hand_cards_max = _life_fire_max()


## 把牌作为【茧】加入盖牌区（超限由引擎询问玩家弃哪几张，对照 StateRequestCover）
func _add_cover(cards: Array, cause: int = 0) -> void:
	engine.add_cover(player.id, cards, player.id, cause)


## 从盖牌区移除【茧】并弃置
func _remove_cover(cards: Array, cause: int = 0) -> void:
	if cards.is_empty():
		return
	engine.to_discard(cards)
	engine.remove_cover(player.id, cards, player.id, cause)


## 【凋零】触发点（服务端 DieWu::p_cover_change）：每次移除【茧】时对每一张逐一询问是否发动。
## ctx: {dst, direction, howMany, cards, doer, cause}
func p_cover_change(ctx: Dictionary) -> int:
	if int(ctx.get("doer", -1)) != player.id or int(ctx.get("direction", -1)) != GConst.CHANGE_REMOVE:
		return SUCCESS
	if not bool(ctx.get("diao_started", false)):
		ctx["diao_started"] = true
		for c: Variant in ctx.get("cards", []):
			_diao_queue.append(int(c))
	return _diao_ling_process()


## 弃掉至多 n 张手牌（客户端未给出合法牌时从手牌补齐）
func _discard_hand_cards(cards: Array, n: int) -> void:
	if n <= 0:
		return
	var chosen: Array = []
	for c: Variant in cards:
		if chosen.size() >= n:
			break
		if player.has_hand_card(int(c)) and not chosen.has(int(c)):
			chosen.append(int(c))
	while chosen.size() < n and chosen.size() < player.hand_cards.size():
		for cid: int in player.hand_cards:
			if chosen.size() >= n:
				break
			if not chosen.has(cid):
				chosen.append(cid)
	if chosen.is_empty():
		return
	engine.take_from_hand(player.id, chosen)
	engine.to_discard(chosen)
	engine._log_discard(player.id, chosen)


## 从回复中取第一张合法【茧】
func _cover_card_from_reply(r: Dictionary) -> int:
	for c: Variant in r.get("card_ids", []):
		if player.cover_cards.has(int(c)):
			return int(c)
	return -1


## 朝圣：【茧】可能位于 card_ids(0) 或 args(1)
func _chao_sheng_card(r: Dictionary) -> int:
	var cid: int = _cover_card_from_reply(r)
	if cid >= 0:
		return cid
	var args: Array = r.get("args", [])
	if args.size() > 1 and player.cover_cards.has(int(args[1])):
		return int(args[1])
	return -1


## 倒逆之蝶：从 args(1..n) 取【茧】
func _cover_cards_from_args(action: Dictionary, n: int) -> Array:
	var out: Array = []
	var args: Array = action.get("args", [])
	for i: int in range(n):
		var idx: int = i + 1
		if idx >= args.size():
			break
		if player.cover_cards.has(int(args[idx])) and not out.has(int(args[idx])):
			out.append(int(args[idx]))
	return out


## 两张盖牌的系别是否不同（【镜花水月】要求同系，不同系视为无效）
func _cover_elements_differ(a: int, b: int) -> bool:
	var ca: GCard = Data.get_card(a)
	var cb: GCard = Data.get_card(b)
	if ca == null or cb == null:
		return true
	return ca.element_enum() != cb.element_enum()
