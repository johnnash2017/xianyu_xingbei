extends BattleRole
## 灵魂术士（roleID 22）—— 移植自服务端 role/LingHun.cpp
## 指示物：tokens[0] = 黄魂（上限 6）、tokens[1] = 蓝魂（上限 6）
## 技能：灵魂吞噬（2204，被动：我方每损失 1 点士气 → +1 黄魂）、
##       灵魂增幅（2203，启动：耗 1 宝石 → +2 黄魂 +2 蓝魂）、
##       灵魂链接（2208，启动：耗 1 黄魂 +1 蓝魂，把【灵魂链接】放置于一名队友面前）、
##       灵魂链接·转移（2209，响应：移除 X 点蓝魂，把 X 点伤害转移给另一人）、
##       灵魂转换（2206，主动攻击宣告后：黄魂与蓝魂互转 1 点）、
##       灵魂召还（2205，法术：弃 X 张法术牌 → +（X＋1）蓝魂）、
##       灵魂震爆（2201，法术：弃 1 张带【灵魂震爆】的牌 + 3 黄魂 →
##                 目标 3 点法术伤害（目标手牌＜3 且手牌上限＞5 时为 5 点））、
##       灵魂赐予（2202，法术：弃 1 张带【灵魂赐予】的牌 + 3 蓝魂 → 目标 +2 宝石）、
##       灵魂镜像（2207，法术：耗 2 黄魂 → 自身弃最多 3 张牌，目标摸牌最多 3 张（不超其手牌上限））
##
## 受限说明：
## - 灵魂吞噬仅能感知「自己」掉士气：本引擎 lose_morale 只调用伤害承受者本人的 p_true_lose_morale，
##   队友掉士气时灵魂术士的角色对象不会收到通知（服务端 StateTrueLoseMorale 会遍历全场）。

const LING_HUN_ZHEN_BAO: int = 2201          # 灵魂震爆
const LING_HUN_CI_YU: int = 2202             # 灵魂赐予
const LING_HUN_ZENG_FU: int = 2203           # 灵魂增幅
const LING_HUN_TUN_SHI: int = 2204           # 灵魂吞噬（被动）
const LING_HUN_ZHAO_HUAN: int = 2205         # 灵魂召还
const LING_HUN_ZHUAN_HUAN: int = 2206        # 灵魂转换
const LING_HUN_JING_XIANG: int = 2207        # 灵魂镜像
const LING_HUN_LIAN_JIE: int = 2208          # 灵魂链接
const LING_HUN_LIAN_JIE_REACT: int = 2209    # 灵魂链接·转移

const TAG_ZHEN_BAO: String = "灵魂震爆"
const TAG_CI_YU: String = "灵魂赐予"

const TOKEN_HUANG: int = 0                   # 黄魂（tokens[0]）
const TOKEN_LAN: int = 1                     # 蓝魂（tokens[1]）
const TOKEN_MAX: int = 6

var used_zeng_fu: bool = false               # 本回合是否已用【灵魂增幅】
var used_lian_jie: bool = false              # 整局是否已放置【灵魂链接】
var using_lian_jie: bool = false             # 本次伤害流程是否正在转移
var connect_id: int = -1                     # 灵魂链接的另一端


func setup(p: BattlePlayer, e: BattleEngine) -> void:
	super.setup(p, e)
	p.tokens[TOKEN_HUANG] = {"name": "黄魂", "max": TOKEN_MAX, "num": 0}
	p.tokens[TOKEN_LAN] = {"name": "蓝魂", "max": TOKEN_MAX, "num": 0}


func available_skills() -> Array:
	var out: Array = []
	if _hand_has_magic():
		out.append({"type": GConst.ActionType.MagicSkill, "id": LING_HUN_ZHAO_HUAN, "need_card": 1, "need_target": 0})
	if _huang() >= 2:
		out.append({"type": GConst.ActionType.MagicSkill, "id": LING_HUN_JING_XIANG, "need_card": 1, "need_target": 1})
	if _huang() >= 3 and _hand_has_tag(TAG_ZHEN_BAO):
		out.append({"type": GConst.ActionType.MagicSkill, "id": LING_HUN_ZHEN_BAO, "need_card": 1, "need_target": 1})
	if _lan() >= 3 and _hand_has_tag(TAG_CI_YU):
		out.append({"type": GConst.ActionType.MagicSkill, "id": LING_HUN_CI_YU, "need_card": 1, "need_target": 1})
	return out


# ============================================================
# 指示物与手牌工具
# ============================================================
func _huang() -> int:
	var t: Dictionary = player.tokens[TOKEN_HUANG]
	return int(t["num"])


func _lan() -> int:
	var t: Dictionary = player.tokens[TOKEN_LAN]
	return int(t["num"])


## 设置灵魂数（以指示物上限封顶，服务端 setToken 同样如此）
func _set_token(idx: int, v: int) -> void:
	var t: Dictionary = player.tokens[idx]
	t["num"] = clampi(v, 0, int(t["max"]))


func _hand_has_magic() -> bool:
	for cid: int in player.hand_cards:
		var c: GCard = Data.get_card(cid)
		if c != null and c.is_magic():
			return true
	return false


func _hand_has_tag(tag: String) -> bool:
	for cid: int in player.hand_cards:
		var c: GCard = Data.get_card(cid)
		if c != null and c.has_speciality_name(tag):
			return true
	return false


## 从客户端给出的牌中挑出 n 张手牌（不足时按手牌顺序补齐）
func _pick_cards(ids: Array, n: int) -> Array:
	var out: Array = []
	for c: Variant in ids:
		if out.size() >= n:
			break
		var cid: int = int(c)
		if player.has_hand_card(cid) and not out.has(cid):
			out.append(cid)
	for cid2: int in player.hand_cards:
		if out.size() >= n:
			break
		if not out.has(cid2):
			out.append(cid2)
	return out


func _show_and_discard(cards: Array) -> void:
	if cards.is_empty():
		return
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": cards, "is_real": true,
	})
	engine.take_from_hand(player.id, cards)
	engine.to_discard(cards)


# ============================================================
# 灵魂吞噬（2204，被动）：我方每损失 1 点士气 → +1 黄魂
# ============================================================
func p_true_lose_morale(ctx: Dictionary) -> int:
	if int(ctx.get("dst", -1)) != player.id:
		return SUCCESS
	var amount: int = int(ctx.get("amount", 0))
	if amount <= 0:
		return SUCCESS
	_set_token(TOKEN_HUANG, _huang() + amount)
	notice_skill(LING_HUN_TUN_SHI, [player.id])
	engine._broadcast_game()
	return SUCCESS


func p_before_turn_begin(_ctx: Dictionary) -> int:
	used_zeng_fu = false
	return SUCCESS


# ============================================================
# 启动（自己回合）：灵魂增幅（2203）→ 灵魂链接（2208）
# ============================================================
func p_boot(_ctx: Dictionary) -> int:
	if engine.current_id != player.id:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if step == 0:
		step = LING_HUN_ZENG_FU
	if step == LING_HUN_ZENG_FU:
		var r: int = _zeng_fu()
		if r == WAIT:
			return WAIT
		if _huang() > 0 and _lan() > 0 and not used_lian_jie and not used_zeng_fu:
			step = LING_HUN_LIAN_JIE
		else:
			step = STEP_DONE
	if step == LING_HUN_LIAN_JIE:
		var r2: int = _lian_jie()
		if r2 == WAIT:
			return WAIT
		step = STEP_DONE
	return SUCCESS


## 灵魂增幅：耗 1 宝石 → +2 黄魂 +2 蓝魂
func _zeng_fu() -> int:
	if player.gem <= 0:
		return SUCCESS
	if not engine.has_reply():
		engine.ask_skill(player.id, LING_HUN_ZENG_FU, 0, 0)
		return WAIT
	if not take_skill_reply():
		return SUCCESS
	used_zeng_fu = true
	notice_skill(LING_HUN_ZENG_FU, [player.id])
	player.set_gem(player.gem - 1)
	_set_token(TOKEN_HUANG, _huang() + 2)
	_set_token(TOKEN_LAN, _lan() + 2)
	engine._broadcast_game()
	return SUCCESS


## 灵魂链接：耗 1 黄魂 +1 蓝魂，双方获得【灵魂链接】独有效果
func _lian_jie() -> int:
	# 服务端：手牌为 0 且黄魂＜3 时不发动；4 人局不发动
	if (player.hand_cards.is_empty() and _huang() < 3) or engine.order.size() == 4:
		return SUCCESS
	if not engine.has_reply():
		engine.ask_skill(player.id, LING_HUN_LIAN_JIE, 0, 1)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	var dsts: Array = r.get("dst_ids", [])
	if args.is_empty() or int(args[0]) != 1 or dsts.is_empty():
		return SUCCESS
	var dst: BattlePlayer = engine.p(int(dsts[0]))
	if dst == null:
		return SUCCESS
	notice_skill(LING_HUN_LIAN_JIE, [dst.id])
	dst.add_exclusive_effect(GConst.Exclusive.LingHunLianJie)
	player.add_exclusive_effect(GConst.Exclusive.LingHunLianJie)
	_set_token(TOKEN_HUANG, _huang() - 1)
	_set_token(TOKEN_LAN, _lan() - 1)
	connect_id = dst.id
	used_lian_jie = true
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 灵魂转换（2206）：主动攻击宣告后可转换 1 点灵魂颜色
# ============================================================
func p_timeline_1(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	if _huang() <= 0 and _lan() <= 0:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if not engine.has_reply():
		engine.ask_skill(player.id, LING_HUN_ZHUAN_HUAN, 0, 0)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	var args: Array = r.get("args", [])
	if args.is_empty():
		return SUCCESS
	var choice: int = int(args[0])
	if choice == 0 and _huang() > 0:
		# 黄 → 蓝
		_set_token(TOKEN_HUANG, _huang() - 1)
		_set_token(TOKEN_LAN, _lan() + 1)
	elif choice == 1 and _lan() > 0:
		# 蓝 → 黄
		_set_token(TOKEN_HUANG, _huang() + 1)
		_set_token(TOKEN_LAN, _lan() - 1)
	else:
		return SUCCESS
	notice_skill(LING_HUN_ZHUAN_HUAN, [player.id])
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 灵魂链接·转移（2209）：伤害结算前把 X 点伤害转移给另一端
# 服务端把转移后的伤害以「目标摸 X 张牌」结算（Timeline6）
# ============================================================
func p_timeline_6(ctx: Dictionary) -> int:
	if not used_lian_jie:
		return SUCCESS
	var harm: Dictionary = ctx.get("harm", {})
	var dst_id: int = int(harm.get("dst", -1))
	if dst_id != player.id and dst_id != connect_id:
		return SUCCESS
	if _lan() < 1 or using_lian_jie or int(harm.get("point", 0)) < 1:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if not engine.has_reply():
		engine.ask_skill(player.id, LING_HUN_LIAN_JIE_REACT, 0, 0)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	var args: Array = r.get("args", [])
	var howmany: int = int(args[0]) if not args.is_empty() else 0
	if howmany <= 0 or howmany > _lan():
		return SUCCESS
	var other_id: int = connect_id if dst_id == player.id else player.id
	notice_skill(LING_HUN_LIAN_JIE_REACT, [other_id])
	using_lian_jie = true
	_set_token(TOKEN_LAN, _lan() - howmany)
	harm["point"] = int(harm.get("point", 0)) - howmany
	engine.draw(other_id, howmany)
	engine._broadcast_game()
	return SUCCESS


func p_harm_end(_ctx: Dictionary) -> int:
	using_lian_jie = false
	return SUCCESS


# ============================================================
# 主动法术技能
# ============================================================
func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	var aid: int = int(action.get("action_id", 0))
	var cards: Array = action.get("card_ids", [])
	match aid:
		LING_HUN_CI_YU:
			if cards.is_empty():
				return GConst.GE_INVALID_CARDID
			if action.get("dst_ids", []).is_empty():
				return GConst.GE_INVALID_ACTION
			var cid: int = int(cards[0])
			var card: GCard = Data.get_card(cid)
			if not player.has_hand_card(cid) or card == null or not card.has_speciality_name(TAG_CI_YU) or _lan() < 3:
				return GConst.GE_INVALID_ACTION
		LING_HUN_ZHEN_BAO:
			if cards.is_empty():
				return GConst.GE_INVALID_CARDID
			if action.get("dst_ids", []).is_empty():
				return GConst.GE_INVALID_ACTION
			var cid2: int = int(cards[0])
			var card2: GCard = Data.get_card(cid2)
			if not player.has_hand_card(cid2) or card2 == null or not card2.has_speciality_name(TAG_ZHEN_BAO) or _huang() < 3:
				return GConst.GE_INVALID_ACTION
		LING_HUN_JING_XIANG:
			if _huang() < 2:
				return GConst.GE_INVALID_ACTION
			if action.get("dst_ids", []).is_empty():
				return GConst.GE_INVALID_ACTION
		LING_HUN_ZHAO_HUAN:
			# 服务端 v_magic_skill 对灵魂召还不做任何校验
			pass
		_:
			return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	match int(action.get("action_id", 0)):
		LING_HUN_CI_YU:
			return _ci_yu(action)
		LING_HUN_ZHEN_BAO:
			return _zhen_bao(action)
		LING_HUN_JING_XIANG:
			return _jing_xiang(action)
		LING_HUN_ZHAO_HUAN:
			return _zhao_huan(action)
	return GConst.GE_INVALID_ACTION


## 灵魂赐予：耗 3 蓝魂，目标 +2 宝石
func _ci_yu(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	var cid: int = int(cards[0])
	var dst_id: int = int(dsts[0])
	var dst: BattlePlayer = engine.p(dst_id)
	notice_skill(LING_HUN_CI_YU, [dst_id])
	_set_token(TOKEN_LAN, _lan() - 3)
	if dst != null:
		dst.set_gem(dst.gem + 2)
	_show_and_discard([cid])
	engine._broadcast_game()
	return URGENT


## 灵魂震爆：耗 3 黄魂，对目标 3（或 5）点法术伤害
func _zhen_bao(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	var cid: int = int(cards[0])
	var dst_id: int = int(dsts[0])
	var dst: BattlePlayer = engine.p(dst_id)
	var point: int = 3
	if dst != null and dst.hand_cards.size() < 3 and dst.hand_cards_max > 5:
		point = 5
	notice_skill(LING_HUN_ZHEN_BAO, [dst_id])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": [cid], "is_real": true,
	})
	_set_token(TOKEN_HUANG, _huang() - 3)
	engine.push_harm({
		"src": player.id, "dst": dst_id, "point": point,
		"cause": LING_HUN_ZHEN_BAO, "type": GConst.HarmType.Magic,
	})
	engine.take_from_hand(player.id, [cid])
	engine.to_discard([cid])
	engine._broadcast_game()
	return URGENT


## 灵魂镜像：耗 2 黄魂，自身弃最多 3 张牌，目标摸牌（不超其手牌上限）
func _jing_xiang(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	var dst_id: int = int(dsts[0])
	var dst: BattlePlayer = engine.p(dst_id)
	if dst == null:
		return GConst.GE_INVALID_ACTION
	_set_token(TOKEN_HUANG, _huang() - 2)
	var card_num: int = mini(cards.size(), 3)
	notice_skill(LING_HUN_JING_XIANG, [dst_id])
	var max_hand: int = dst.hand_cards_max
	var current: int = dst.hand_cards.size()
	var draw_num: int = 3 if (current + 3) < max_hand else (max_hand - current)
	if dst_id == player.id:
		# 对自己使用时先弃牌再摸牌（服务端 drawNum 按弃牌后的手牌计算）
		draw_num = 3 if (current - card_num + 3) < max_hand else (max_hand - (current - card_num))
	if card_num > 0:
		_show_and_discard(_pick_cards(cards, card_num))
	if draw_num > 0:
		engine.draw(dst_id, draw_num)
	engine._broadcast_game()
	return SUCCESS


## 灵魂召还：弃 X 张法术牌 → +（X＋1）蓝魂
func _zhao_huan(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var card_num: int = cards.size()
	notice_skill(LING_HUN_ZHAO_HUAN, [player.id])
	_set_token(TOKEN_LAN, _lan() + card_num + 1)
	if card_num > 0:
		_show_and_discard(_pick_cards(cards, card_num))
	engine._broadcast_game()
	return SUCCESS
