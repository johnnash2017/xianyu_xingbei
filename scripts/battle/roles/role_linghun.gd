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

const LING_HUN_ZHEN_BAO: int = 2201          # 灵魂震爆
const LING_HUN_CI_YU: int = 2202             # 灵魂赐予
const LING_HUN_ZENG_FU: int = 2203           # 灵魂增幅
const LING_HUN_TUN_SHI: int = 2204           # 灵魂吞噬（被动）
const LING_HUN_ZHAO_HUAN: int = 2205         # 灵魂召还
const LING_HUN_ZHUAN_HUAN: int = 2206        # 灵魂转换
const LING_HUN_JING_XIANG: int = 2207        # 灵魂镜像
const LING_HUN_LIAN_JIE: int = 2208          # 灵魂链接
const LING_HUN_LIAN_JIE_REACT: int = 2209    # 灵魂链接·转移

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
		# 灵魂召还：弃 X 张法术牌 → +（X＋1）蓝魂。只让手牌里的法术牌可点，上限＝手里的法术牌数
		# （v_magic_skill 校验同一条件）
		var 法术牌: Array[int] = magic_hand_ids()
		out.append({"type": GConst.ActionType.MagicSkill, "id": LING_HUN_ZHAO_HUAN, "need_card": 1, "need_target": 0,
			"cards": 法术牌, "card_max": 法术牌.size()})
	if _huang() >= 2:
		# v_magic_skill 只校验黄魂数与目标；执行体最多弃 3 张（mini(cards.size(), 3)），
		# 服务端允许一张都不弃（cardNum 可为 0），故 need_card=0、上限放开到 3
		out.append({"type": GConst.ActionType.MagicSkill, "id": LING_HUN_JING_XIANG, "need_card": 0, "need_target": 1,
			"card_max": 3})
	# 灵魂震爆/灵魂赐予：只有手中带对应特技的牌可作发动牌，下发给界面把其余手牌置灰
	# （v_magic_skill 校验同一张牌：须在手且带该特技）
	var 震爆牌: Array[int] = hand_ids_with_skill(LING_HUN_ZHEN_BAO)
	if _huang() >= 3 and not 震爆牌.is_empty():
		out.append({"type": GConst.ActionType.MagicSkill, "id": LING_HUN_ZHEN_BAO, "need_card": 1, "need_target": 1,
			"cards": 震爆牌})
	var 赐予牌: Array[int] = hand_ids_with_skill(LING_HUN_CI_YU)
	if _lan() >= 3 and not 赐予牌.is_empty():
		out.append({"type": GConst.ActionType.MagicSkill, "id": LING_HUN_CI_YU, "need_card": 1, "need_target": 1,
			"cards": 赐予牌})
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


## 展示并弃掉这些手牌。展示 = false 时改为面朝下弃掉（不亮牌、也不触发展示手牌钩子）——
## 服务端【灵魂镜像】的这步 isShown=false，只有【灵魂赐予】【灵魂召还】才是公开的。
func _show_and_discard(cards: Array, 展示: bool = true) -> void:
	if cards.is_empty():
		return
	if 展示:
		engine.broadcast(GConst.Msg.Card, {
			"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
			"card_ids": cards, "is_real": true,
		})
	engine.take_from_hand(player.id, cards, 展示)
	engine.to_discard(cards)


# ============================================================
# 灵魂吞噬（2204，被动）：我方每损失 1 点士气 → +1 黄魂
# ============================================================
func p_true_lose_morale(ctx: Dictionary) -> int:
	var dst: BattlePlayer = engine.p(int(ctx.get("dst", -1)))
	if dst == null or dst.color != player.color:
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
## 【灵魂增幅 / 灵魂链接】的推进阶段（0＝还没开始 / LING_HUN_ZENG_FU＝在处理灵魂增幅 / LING_HUN_LIAN_JIE＝在处理灵魂链接）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨若干次询问，
## 中途一旦被别的钩子轮次（改手牌 / 盖牌 / 基础效果 / 横置…）插进来，step 就被抹掉、流程退回第 0 步。
## 自己回合启动（p_boot）触发一次，收尾清回 0（留 STEP_DONE 会让下一次触发不再发动）
var _boot_step: int = 0


func p_boot(_ctx: Dictionary) -> int:
	if engine.current_id != player.id:
		return SUCCESS
	if _boot_step >= STEP_DONE:
		return SUCCESS
	if _boot_step == 0:
		_boot_step = LING_HUN_ZENG_FU
	if _boot_step == LING_HUN_ZENG_FU:
		var r: int = _zeng_fu()
		if r == WAIT:
			return WAIT
		if _huang() > 0 and _lan() > 0 and not used_lian_jie and not used_zeng_fu:
			_boot_step = LING_HUN_LIAN_JIE
		else:
			_boot_step = 0
	if _boot_step == LING_HUN_LIAN_JIE:
		var r2: int = _lian_jie()
		if r2 == WAIT:
			return WAIT
		_boot_step = 0
	return SUCCESS


## 灵魂增幅：耗 1 宝石 → +2 黄魂 +2 蓝魂
func _zeng_fu() -> int:
	if player.gem <= 0:
		return SUCCESS
	if not engine.has_reply():
		询问(player.id, LING_HUN_ZENG_FU, 0, 0)
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
		询问(player.id, LING_HUN_LIAN_JIE, 0, 1)
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
## 【灵魂转换】的推进阶段（0＝还没问 / 处理完本次转换后清回 0）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨一次询问，
## 中途一旦被别的钩子轮次（改手牌 / 盖牌 / 基础效果 / 横置…）插进来，step 就被抹掉、流程退回第 0 步。
## 每次自己主动宣告攻击（p_timeline_1）触发一次，收尾清回 0（留 STEP_DONE 会让下一次触发不再发动）
var _timeline_1_step: int = 0


func p_timeline_1(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	if _huang() <= 0 and _lan() <= 0:
		return SUCCESS
	if _timeline_1_step >= STEP_DONE:
		return SUCCESS
	if not engine.has_reply():
		# 两个方向各做成一个选项（value 0=黄→蓝、1=蓝→黄），只列当前真有对应灵魂的项；
		# 「取消」回空 args＝不发动（通用客户端不再拿 0 当取消，0 才能正常当选项值）
		var 选项: Array = []
		if _huang() > 0:
			选项.append({"value": 0, "label": "黄 → 蓝"})
		if _lan() > 0:
			选项.append({"value": 1, "label": "蓝 → 黄"})
		询问(player.id, LING_HUN_ZHUAN_HUAN, 0, 0, GConst.CardSource.Hand, 选项)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	_timeline_1_step = 0
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
## 【灵魂链接·转移】的推进阶段（0＝还没问 / 处理完本次转移后清回 0）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨一次询问，
## 中途一旦被别的钩子轮次（改手牌 / 盖牌 / 基础效果 / 横置…）插进来，step 就被抹掉、流程退回第 0 步。
## 每次【灵魂链接】的一端承受伤害（p_timeline_6）触发一次，收尾清回 0（留 STEP_DONE 会让下一次触发不再发动）
var _timeline_6_step: int = 0


func p_timeline_6(ctx: Dictionary) -> int:
	if not used_lian_jie:
		return SUCCESS
	var harm: Dictionary = ctx.get("harm", {})
	var dst_id: int = int(harm.get("dst", -1))
	if dst_id != player.id and dst_id != connect_id:
		return SUCCESS
	if _lan() < 1 or using_lian_jie or int(harm.get("point", 0)) < 1:
		return SUCCESS
	if _timeline_6_step >= STEP_DONE:
		return SUCCESS
	if not engine.has_reply():
		# 可转移点数上限＝min(蓝魂数, 本次伤害)：做成选项按钮（服务端会把 con->harm.point 下发给客户端限制）
		var 上限: int = mini(_lan(), int(harm.get("point", 0)))
		var options: Array = []
		for x: int in range(1, 上限 + 1):
			options.append({"value": x, "label": "转移 %d 点（耗 %d 蓝魂，由另一端摸 %d 张）" % [x, x, x]})
		询问(player.id, LING_HUN_LIAN_JIE_REACT, 0, 0, GConst.CardSource.Hand, options)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	_timeline_6_step = 0
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
			if not player.has_hand_card(cid) or card == null or not card.has_skill_id(LING_HUN_CI_YU) or _lan() < 3:
				return GConst.GE_INVALID_ACTION
		LING_HUN_ZHEN_BAO:
			if cards.is_empty():
				return GConst.GE_INVALID_CARDID
			if action.get("dst_ids", []).is_empty():
				return GConst.GE_INVALID_ACTION
			var cid2: int = int(cards[0])
			var card2: GCard = Data.get_card(cid2)
			if not player.has_hand_card(cid2) or card2 == null or not card2.has_skill_id(LING_HUN_ZHEN_BAO) or _huang() < 3:
				return GConst.GE_INVALID_ACTION
		LING_HUN_JING_XIANG:
			if _huang() < 2:
				return GConst.GE_INVALID_ACTION
			if action.get("dst_ids", []).is_empty():
				return GConst.GE_INVALID_ACTION
		LING_HUN_ZHAO_HUAN:
			# 弃 X 张法术牌 → +（X＋1）蓝魂：至少弃 1 张，且每张都得是自己手里的法术牌
			if cards.is_empty():
				return GConst.GE_INVALID_CARDID
			for c: Variant in cards:
				var 法术牌: GCard = Data.get_card(int(c))
				if 法术牌 == null or not 法术牌.is_magic() or not player.has_hand_card(int(c)):
					return GConst.GE_INVALID_ACTION
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
	engine.take_from_hand(player.id, [cid], true)
	engine.to_discard([cid])
	# 牌已在上面展示过：只写日志、不播弃牌特效
	engine._log_discard(player.id, [cid], false)
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
		# 服务端【灵魂镜像】这一步 isShown=false：面朝下弃牌
		_show_and_discard(_pick_cards(cards, card_num), false)
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
