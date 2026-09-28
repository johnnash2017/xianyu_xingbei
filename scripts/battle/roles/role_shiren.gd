extends BattleRole
## 吟游诗人（roleID 31）—— 移植自服务端 role/ShiRen.cpp
## 指示物：tokens[0] = 灵感（上限 4）
## 独有效果：【永恒乐章】GConst.Exclusive.YongHengYueZhang（放置于某名角色面前，由持有者触发）
## 技能：沉沦协奏曲（3101，响应：一回合内我方对 ≥2 名敌方角色造成法术伤害并结算完后，
##                 弃 2 张同系牌【展示】→ 对目标造成 1 点法术伤害）、
##       不谐和弦（3102，法术：移除 X 点灵感（X＞1）→ 你与目标各摸 X－1 张牌，或各弃 X－1 张牌）、
##       歌咏天赋（3103，被动：永恒乐章被触发后 +1 灵感并把乐章收回；
##                 若灵感已达上限则横置并对自己造成 3 点法术伤害）、
##       暴风前奏曲（3104，服务端仅有枚举、无任何实现，故未移植）、
##       激昂狂想曲（31052，响应：回合开始时若当前角色持有永恒乐章 →
##                 对两名目标各 1 点法术伤害，或弃 2 张牌）、
##       胜利交响诗（31061，响应：回合结束时若当前角色持有永恒乐章 →
##                 将我方 1 星石提炼为自身能量，或我方 +1 宝石且自身 +1 治疗）、
##       希望赋格曲（3107，启动：耗 1 能量把永恒乐章转移到一名队友面前）
##
## 变通说明：
## - 服务端在 STATE_TURN_BEGIN_SHIREN 调用 p_turn_begin_shiren；本引擎只在回合开始调用
##   p_turn_begin，故「激昂狂想曲」并入 p_turn_begin（判定当前回合角色是否为乐章持有者）。
## - 灵感上限：服务端 tokenMax[0] = 3，技能文本与任务要求均为 4，此处取 4。
## - 服务端构造时「诗人初始拥有永恒乐章」的语句被注释掉（YueZhangDst = -1），
##   即开局乐章不在任何人面前，需靠希望赋格曲放置；此处与服务端保持一致。

const CHEN_LUN_XIE_ZOU_QU: int = 3101
const BU_XIE_HE_XIAN: int = 3102
const GE_YONG_TIAN_FU: int = 3103
const BAO_FENG_QIAN_ZOU_QU: int = 3104
const JI_ANG_KUANG_XIANG_QU: int = 3105
const JI_ANG_KUANG_XIANG_QU_2: int = 31052
const SHENG_LI_JIAO_XIANG_SHI: int = 3106
const SHENG_LI_JIAO_XIANG_SHI_2: int = 31061
const XI_WANG_FU_GE_QU: int = 3107

## 本引擎自有的分步标记（服务端把子步骤实现为压栈状态，此处只用 step 记录进度）
const JI_ANG_DISCARD: int = 31054          # 激昂狂想曲：当前角色弃 2 张牌

const TOKEN_LING_GAN: int = 0
const LING_GAN_MAX: int = 4
const GE_YONG_HARM: int = 3                # 歌咏天赋：灵感已满时的自伤
const CHEN_LUN_NEED_KINDS: int = 2         # 沉沦协奏曲：需要命中的敌方角色种类数

var yue_zhang_dst: int = -1                # 永恒乐章当前所在角色（-1 表示不在任何人面前）
var use_yue_zhang: bool = false            # 本次触发是否使用了永恒乐章
var chen_lun_used: bool = false            # 本回合是否已发动沉沦协奏曲
var chen_lun_dsts: Array = []              # 本回合我方法术伤害命中的敌方角色

## 不谐和弦的进度（主动法术技能不在钩子轮次内，step 不会被重置，故单独记阶段）
var bu_xie_phase: int = 0
var bu_xie_dst: int = -1
var bu_xie_num: int = 0


func setup(p: BattlePlayer, e: BattleEngine) -> void:
	super.setup(p, e)
	p.tokens[TOKEN_LING_GAN] = {"name": "灵感", "max": LING_GAN_MAX, "num": 0}


func available_skills() -> Array:
	var out: Array = []
	if _ling_gan() > 1:
		out.append({"type": GConst.ActionType.MagicSkill, "id": BU_XIE_HE_XIAN, "need_card": 0, "need_target": 1})
	return out


# ============================================================
# 指示物与工具
# ============================================================
func _ling_gan() -> int:
	var t: Dictionary = player.tokens[TOKEN_LING_GAN]
	return int(t["num"])


func _set_ling_gan(v: int) -> void:
	var t: Dictionary = player.tokens[TOKEN_LING_GAN]
	t["num"] = clampi(v, 0, int(t["max"]))


## 从 ids 中挑出 n 张目标手牌（不足时按其手牌顺序补齐）
func _pick_cards(target: BattlePlayer, ids: Array, n: int) -> Array:
	var out: Array = []
	for c: Variant in ids:
		if out.size() >= n:
			break
		var cid: int = int(c)
		if target.has_hand_card(cid) and not out.has(cid):
			out.append(cid)
	for cid2: int in target.hand_cards:
		if out.size() >= n:
			break
		if not out.has(cid2):
			out.append(cid2)
	return out


## 请某名角色弃 n 张牌（服务端 StateRequestHand）
func _request_discard(pid: int, n: int, cause: int) -> int:
	var target: BattlePlayer = engine.p(pid)
	if target == null or n <= 0 or target.hand_cards.is_empty():
		return SUCCESS
	if not engine.has_reply():
		engine.ask_skill(pid, cause, 1, 0)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var want: int = mini(n, target.hand_cards.size())
	var chosen: Array = _pick_cards(target, r.get("card_ids", []), want)
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": pid, "dst_id": pid,
		"card_ids": chosen, "is_real": true,
	})
	engine.take_from_hand(pid, chosen)
	engine.to_discard(chosen)
	engine._broadcast_game()
	return SUCCESS


func _all_hand_light() -> bool:
	for cid: int in player.hand_cards:
		var c: GCard = Data.get_card(cid)
		if c == null or c.element_enum() != GConst.CardElement.Light:
			return false
	return true


## 希望赋格曲的发动条件（服务端含一段 do-while 条件）
func _can_xi_wang() -> bool:
	if player.get_energy() < 1 or yue_zhang_dst != -1:
		return false
	if _ling_gan() > 1:
		return true
	if player.hand_cards.is_empty():
		return false
	if _all_hand_light() and player.hand_cards.size() < 4:
		return false
	return true


func p_before_turn_begin(_ctx: Dictionary) -> int:
	chen_lun_used = false
	chen_lun_dsts.clear()
	use_yue_zhang = false
	return SUCCESS


# ============================================================
# 回合开始：激昂狂想曲（31052）+ 歌咏天赋（3103）
# （服务端由 p_turn_begin_shiren 触发，本引擎并入 p_turn_begin）
# ============================================================
func p_turn_begin(_ctx: Dictionary) -> int:
	if engine.current_id != yue_zhang_dst:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if step == 0:
		step = JI_ANG_KUANG_XIANG_QU_2
	if step == JI_ANG_KUANG_XIANG_QU_2:
		if not engine.has_reply():
			engine.ask_skill(engine.current_id, JI_ANG_KUANG_XIANG_QU_2, 0, 1)
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		var args: Array = r.get("args", [])
		var choice: int = int(args[0]) if not args.is_empty() else 0
		if choice == 1:
			# 对两名目标各 1 点法术伤害
			use_yue_zhang = true
			_ji_ang_harm(r.get("dst_ids", []))
			step = GE_YONG_TIAN_FU
			return URGENT
		if choice == 2:
			step = JI_ANG_DISCARD
		else:
			step = STEP_DONE
	if step == JI_ANG_DISCARD:
		# 由当前角色（乐章持有者）弃 2 张牌
		if _request_discard(engine.current_id, 2, JI_ANG_KUANG_XIANG_QU) == WAIT:
			return WAIT
		use_yue_zhang = true
		step = GE_YONG_TIAN_FU
	if step == GE_YONG_TIAN_FU:
		var r2: int = SUCCESS
		if use_yue_zhang:
			r2 = _ge_yong_tian_fu()
		step = STEP_DONE
		if r2 == URGENT:
			return URGENT
	return SUCCESS


## 激昂狂想曲的伤害：从当前角色的上家开始按座位序绕一圈
func _ji_ang_harm(dsts: Array) -> void:
	var holder: BattlePlayer = engine.p(engine.current_id)
	if holder == null:
		return
	var cur: int = holder.pre_id
	for _i: int in range(engine.order.size()):
		var cp: BattlePlayer = engine.p(cur)
		if cp == null:
			break
		if dsts.has(cur):
			engine.push_harm({
				"src": player.id, "dst": cur, "point": 1,
				"cause": JI_ANG_KUANG_XIANG_QU, "type": GConst.HarmType.Magic,
			})
		cur = cp.pre_id
	engine._broadcast_game()


## 歌咏天赋：乐章被触发后 +1 灵感并收回乐章；灵感已满则横置并自伤 3 点
func _ge_yong_tian_fu() -> int:
	notice_skill(GE_YONG_TIAN_FU, [player.id])
	use_yue_zhang = false
	if _ling_gan() < LING_GAN_MAX:
		_set_ling_gan(_ling_gan() + 1)
		var holder: BattlePlayer = engine.p(yue_zhang_dst)
		if holder != null:
			holder.remove_exclusive_effect(GConst.Exclusive.YongHengYueZhang)
		yue_zhang_dst = -1
		engine._broadcast_game()
		return SUCCESS
	if not player.tap:
		player.tap = true
	engine.push_harm({
		"src": player.id, "dst": player.id, "point": GE_YONG_HARM,
		"cause": GE_YONG_TIAN_FU, "type": GConst.HarmType.Magic,
	})
	engine._broadcast_game()
	return URGENT


# ============================================================
# 回合结束：胜利交响诗（31061）+ 歌咏天赋（3103）
# ============================================================
func p_turn_end(_ctx: Dictionary) -> int:
	if step >= STEP_DONE:
		return SUCCESS
	if step == 0:
		step = SHENG_LI_JIAO_XIANG_SHI_2
	if step == SHENG_LI_JIAO_XIANG_SHI_2:
		if yue_zhang_dst != engine.current_id:
			return SUCCESS
		if _sheng_li_jiao_xiang_shi() == WAIT:
			return WAIT
		step = GE_YONG_TIAN_FU
	if step == GE_YONG_TIAN_FU:
		var r: int = SUCCESS
		if use_yue_zhang:
			r = _ge_yong_tian_fu()
		step = STEP_DONE
		if r == URGENT:
			return URGENT
	return SUCCESS


## 胜利交响诗：提炼我方 1 星石为当前角色能量，或我方 +1 宝石且当前角色 +1 治疗
func _sheng_li_jiao_xiang_shi() -> int:
	var holder: BattlePlayer = engine.p(engine.current_id)
	if holder == null:
		return SUCCESS
	var color: int = holder.color
	var choice: int = 2
	if engine.team_energy(color) > 0:
		choice += 1
	if not engine.has_reply():
		engine.ask_skill(engine.current_id, SHENG_LI_JIAO_XIANG_SHI_2, 0, 0)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	var answer: int = int(args[0]) if not args.is_empty() else 0
	if answer == 1:
		var kind: int = int(args[1]) if args.size() > 1 else 0
		if kind == 1:
			holder.set_crystal(holder.crystal + 1)
			engine.set_team_crystal(color, engine.team_crystal[color] - 1)
		elif kind == 2:
			holder.set_gem(holder.gem + 1)
			engine.set_team_gem(color, engine.team_gem[color] - 1)
		else:
			answer = 2
	if answer == 2:
		engine.set_team_gem(color, engine.team_gem[color] + 1)
		holder.add_cross_num(1)
	use_yue_zhang = true
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 伤害结算后：沉沦协奏曲（3101）
# ============================================================
func p_harm_end(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("type", -1)) != GConst.HarmType.Magic:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if step == 0:
		step = CHEN_LUN_XIE_ZOU_QU
	if step == CHEN_LUN_XIE_ZOU_QU:
		var dst_id: int = int(ctx.get("dst", -1))
		var src_id: int = int(harm.get("src", -1))
		var dst_p: BattlePlayer = engine.p(dst_id)
		var src_p: BattlePlayer = engine.p(src_id)
		if dst_p == null or src_p == null:
			return SUCCESS
		# 受伤者须为敌方、施害者须为我方，且自身未横置、本回合未发动过
		if dst_p.color == player.color or src_p.color != player.color:
			return SUCCESS
		if chen_lun_used or player.tap:
			return SUCCESS
		if not chen_lun_dsts.has(dst_id):
			chen_lun_dsts.append(dst_id)
		if chen_lun_dsts.size() < CHEN_LUN_NEED_KINDS:
			step = STEP_DONE
			return SUCCESS
		if not engine.has_reply():
			engine.ask_skill(player.id, CHEN_LUN_XIE_ZOU_QU, 1, 1)
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		step = STEP_DONE
		var args: Array = r.get("args", [])
		var dsts: Array = r.get("dst_ids", [])
		var cards: Array = r.get("card_ids", [])
		if args.is_empty() or int(args[0]) != 1 or dsts.is_empty() or cards.size() != 2:
			return SUCCESS
		if not player.has_hand_card(int(cards[0])) or not player.has_hand_card(int(cards[1])):
			return SUCCESS
		var c0: GCard = Data.get_card(int(cards[0]))
		var c1: GCard = Data.get_card(int(cards[1]))
		if c0 == null or c1 == null or c0.element_enum() != c1.element_enum():
			return SUCCESS
		var use_cards: Array = [int(cards[0]), int(cards[1])]
		chen_lun_used = true
		notice_skill(CHEN_LUN_XIE_ZOU_QU, dsts)
		engine.broadcast(GConst.Msg.Card, {
			"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
			"card_ids": use_cards, "is_real": true,
		})
		engine.take_from_hand(player.id, use_cards)
		engine.to_discard(use_cards)
		engine._broadcast_game()
		if c0.is_magic() or c1.is_magic():
			engine.push_harm({
				"src": player.id, "dst": int(dsts[0]), "point": 1,
				"cause": CHEN_LUN_XIE_ZOU_QU, "type": GConst.HarmType.Magic,
			})
			engine._broadcast_game()
			return URGENT
	return SUCCESS


# ============================================================
# 启动（自己回合）：希望赋格曲（3107）
# ============================================================
func p_boot(_ctx: Dictionary) -> int:
	if engine.current_id != player.id:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if step == 0:
		step = XI_WANG_FU_GE_QU
	if not _can_xi_wang():
		step = STEP_DONE
		return SUCCESS
	if not engine.has_reply():
		engine.ask_skill(player.id, XI_WANG_FU_GE_QU, 0, 1)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	var args: Array = r.get("args", [])
	var dsts: Array = r.get("dst_ids", [])
	if args.is_empty() or int(args[0]) != 1 or dsts.is_empty():
		return SUCCESS
	var dst: BattlePlayer = engine.p(int(dsts[0]))
	if dst == null or dst.color != player.color:
		return SUCCESS
	notice_skill(XI_WANG_FU_GE_QU, [dst.id])
	if player.crystal > 0:
		player.set_crystal(player.crystal - 1)
	else:
		player.set_gem(player.gem - 1)
	if yue_zhang_dst != -1:
		var old: BattlePlayer = engine.p(yue_zhang_dst)
		if old != null:
			old.remove_exclusive_effect(GConst.Exclusive.YongHengYueZhang)
	yue_zhang_dst = dst.id
	dst.add_exclusive_effect(GConst.Exclusive.YongHengYueZhang)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 主动法术技能：不谐和弦（3102）
# ============================================================
func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	match int(action.get("action_id", 0)):
		BU_XIE_HE_XIAN:
			var args: Array = action.get("args", [])
			if args.size() < 2:
				return GConst.GE_INVALID_ARGUMENT
			var num: int = int(args[0])
			var choice: int = int(args[1])
			if num <= 1 or num > _ling_gan() or choice < 1 or choice > 2:
				return GConst.GE_INVALID_ARGUMENT
			if action.get("dst_ids", []).is_empty():
				return GConst.GE_INVALID_ACTION
		_:
			return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != BU_XIE_HE_XIAN:
		return GConst.GE_INVALID_ACTION
	return _bu_xie_he_xian(action)


## 不谐和弦：移除 X 点灵感，你与目标各摸 X－1 张牌（或各弃 X－1 张牌）
func _bu_xie_he_xian(action: Dictionary) -> int:
	var args: Array = action.get("args", [])
	var num: int = int(args[0])
	var choice: int = int(args[1])
	var dsts: Array = action.get("dst_ids", [])
	var dst_id: int = int(dsts[0])
	if bu_xie_phase == 0:
		if player.tap:
			player.tap = false
		_set_ling_gan(_ling_gan() - num)
		notice_skill(BU_XIE_HE_XIAN, [dst_id])
		bu_xie_num = num
		bu_xie_dst = dst_id
		engine._broadcast_game()
		if choice == 1:
			engine.draw(dst_id, num - 1)
			engine.draw(player.id, num - 1)
			engine._broadcast_game()
			return SUCCESS
		bu_xie_phase = 1
	if bu_xie_phase == 1:
		if _request_discard(bu_xie_dst, bu_xie_num - 1, BU_XIE_HE_XIAN) == WAIT:
			return WAIT
		bu_xie_phase = 2
	if bu_xie_phase == 2:
		if _request_discard(player.id, bu_xie_num - 1, BU_XIE_HE_XIAN) == WAIT:
			return WAIT
		bu_xie_phase = 0
	return SUCCESS
