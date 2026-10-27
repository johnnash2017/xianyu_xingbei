extends BattleRole
## 剑之魔女（roleID 45）—— 特典
## 技能：
##   技之剑意（4501，响应）：攻击行动结束时，额外 +1「技类命格攻击牌」的攻击行动
##   臆想剑（4502，响应 / 回合限定）：主动攻击命中时，目标弃 1 张牌【强制】【展示】；
##       若为攻击牌，你可以获得该牌并额外 +1 攻击行动；若为法术牌，本次攻击伤害 +2
##   梦想剑（4503，被动）：本回合第 1 次攻击行动后，主动攻击无视圣盾；第 2 次后，对方无法应战；
##       第 4 次后，强制命中（第 3 次没有新效果；额外攻击行动也计入本回合次数）
##   剑影*断念（4504，响应 / 必杀技 / 回合限定）：攻击行动结束时支付 1【宝石】（必须真宝石），
##       弃 2 张手牌，摸 1 张牌【强制】，额外 +1 攻击行动
##
## 4501 / 4504 的额外攻击行动都带「选中即进入」（direct）：玩家已经为这份行动做过一次确认，
## 不再让引擎二次追问；进入后仍可在额外行动阶段放弃。
## 4503 的第 1 / 2 / 4 档用本角色实例标记记「本回合已激活到哪一档」，回合开始清零。
## 4502 的目标弃牌带【展示】：弃牌后先 return URGENT 让 p_show_hand 响应（可能等待）结算完，
## 重入时才问「是否获得该攻击牌」，否则询问会插在展示响应之前。

const JI_ZHI_JIAN_YI: int = 4501
const YI_XIANG_JIAN: int = 4502
const MENG_XIANG_JIAN: int = 4503
const JIAN_YING_DUAN_NIAN: int = 4504

## 4501 / 4504 在同一份「攻击行动结束」上下文里的推进进度。
## 存在 ctx 里而不是角色实例：同一次攻击的钩子重入拿的是同一份 ctx，天然不会把上一击的进度带过来。
const KEY_AFTER_STEP: String = "_jianzhimoni_after_step"
const AFTER_STEP_4501: int = 1
## 4502 的分步进度：0 未开始 / 1 已发动、等目标弃牌 / 2 已弃牌、等【展示】响应结算 /
##                 3 等是否获得攻击牌。
const KEY_YI_XIANG_STEP: String = "_jianzhimoni_yixiang_step"
const KEY_YI_XIANG_CARD: String = "_jianzhimoni_yixiang_card"
const YI_XIANG_STEP_SHOWED: int = 2
const YI_XIANG_STEP_ASK_OBTAIN: int = 3
## 4504 的分步进度：0 未开始 / 1 已支付宝石、等弃 2 张牌。
const KEY_DUAN_NIAN_STEP: String = "_jianzhimoni_duannian_step"

## 回合限定：本回合是否已经发动过 4502 / 4504
var used_yi_xiang_jian: bool = false
var used_jian_ying_duan_nian: bool = false

## 4503 梦想剑本回合已激活的档位（回合开始清零）
var dream_ignore_shield: bool = false
var dream_no_reattack: bool = false
var dream_no_miss: bool = false
## 展示档位：攻击行动结算完、进入「攻击结束」响应（p_after_attack）时推进，
## 供客户端说明逐段标绿；此时还没到本回合结束阶段，实际效果仍由 dream_* 在 p_action_end 后生效。
var dream_display_tier: int = 0


## 梦想剑当前展示档位（供客户端角色说明标绿）：3 最强，其次 2、1，都没激活返回 0。
func dream_tier() -> int:
	return dream_display_tier


## 攻击行动结算完、进入攻击结束响应时，按「本次是第几次攻击行动」推进展示档；
## 不改变实际效果 flags（flags 仍在 p_action_end 推进）。
func _更新梦想剑展示档() -> void:
	# 记录行动在攻击宣告前已经 +1，所以这里直接用当前计数＝本次是第几次攻击
	var 序号: int = player.attack_action_count
	var 档位: int = 1 if 序号 < 2 else (2 if 序号 < 4 else 3)
	if 档位 > dream_display_tier:
		dream_display_tier = 档位
		if engine != null:
			engine._broadcast_game()


## 兜底：如果这次行动结束没有经过 p_after_attack（正常不会），按 flags 补齐展示档。
func _同步梦想剑展示档() -> void:
	var 档位: int = 3 if dream_no_miss else (2 if dream_no_reattack else (1 if dream_ignore_shield else 0))
	if 档位 > dream_display_tier:
		dream_display_tier = 档位


func p_before_turn_begin(_ctx: Dictionary) -> int:
	used_yi_xiang_jian = false
	used_jian_ying_duan_nian = false
	dream_ignore_shield = false
	dream_no_reattack = false
	dream_no_miss = false
	dream_display_tier = 0
	return SUCCESS


# ============================================================
# 攻击宣告时（timeline_1）：梦想剑的当前档位只作用于「主动攻击」
# ============================================================
func p_timeline_1(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	# 应战反击（is_active=false）不是主动攻击，梦想剑不生效
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	if dream_no_miss:
		ctx["hit_rate"] = GConst.HitRate.NoMiss
	elif dream_no_reattack:
		ctx["hit_rate"] = GConst.HitRate.NoReattack
	if dream_ignore_shield:
		ctx["check_shield"] = false
	return SUCCESS


# ============================================================
# 攻击行动结束时（after_attack）：技之剑意（4501）→ 剑影*断念（4504）
# ============================================================
func p_after_attack(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	# 攻击已经结算完、进入「攻击结束」响应：此时才推进展示档，既不会在攻击宣告时就变绿，
	# 也能让 4501 / 4504 这类响应技能在决定时看到本回合的新档位（实际效果仍在 p_action_end 生效）。
	_更新梦想剑展示档()
	var 阶段: int = int(ctx.get(KEY_AFTER_STEP, 0))
	if 阶段 >= STEP_DONE:
		return SUCCESS
	if 阶段 == 0:
		var r: int = _ji_zhi_jian_yi()
		# 等回复期间不能推进阶段：重入时还要回到 4501 里把这份回复读掉
		if r == WAIT:
			return WAIT
		阶段 = AFTER_STEP_4501
		ctx[KEY_AFTER_STEP] = 阶段
	if 阶段 == AFTER_STEP_4501:
		var r2: int = _jian_ying_duan_nian(ctx)
		if r2 == WAIT:
			return WAIT
		ctx[KEY_AFTER_STEP] = STEP_DONE
		if r2 == URGENT:
			return URGENT
	return SUCCESS


## 4501 技之剑意：攻击行动结束时，额外 +1 只能使用「技类命格攻击牌」的攻击行动。
## 手里一张技类攻击牌都没有时不询问 —— 这份额外行动一张牌都出不了，只会让玩家多按一次放弃。
func _ji_zhi_jian_yi() -> int:
	if not engine.has_reply():
		if _martial_attack_hand_ids().is_empty():
			return SUCCESS
		询问(player.id, JI_ZHI_JIAN_YI, 0, 0)
		return WAIT
	if not take_skill_reply():
		return SUCCESS
	notice_skill(JI_ZHI_JIAN_YI, [player.id])
	# direct=true：选中即进入额外攻击行动，不再二次追问；skip_notice=true：上面已经播报过 4501
	player.add_action(GConst.ActionType.Attack, JI_ZHI_JIAN_YI, true, true)
	return SUCCESS


## 4504 剑影*断念：支付 1【宝石】（不能用宝石顶水晶那套，必须是真宝石）→ 弃 2 张手牌
## → 摸 1 张【强制】→ 额外 +1 攻击行动。摸牌走 push_draw，故返回 URGENT 让摸牌先结算。
func _jian_ying_duan_nian(ctx: Dictionary) -> int:
	var 阶段: int = int(ctx.get(KEY_DUAN_NIAN_STEP, 0))
	if 阶段 >= STEP_DONE:
		return SUCCESS
	# 回合限定只挡「新的一次发动」；已经付过宝石、正在等弃牌时 used 已经是 true，必须继续
	if 阶段 == 0 and used_jian_ying_duan_nian:
		return SUCCESS
	if 阶段 == 0 and (player.gem <= 0 or player.hand_cards.size() < 2):
		return SUCCESS
	if 阶段 == 0:
		if not engine.has_reply():
			engine.ask_skill(player.id, JIAN_YING_DUAN_NIAN)
			return WAIT
		if not take_skill_reply():
			return SUCCESS
		used_jian_ying_duan_nian = true
		notice_skill(JIAN_YING_DUAN_NIAN, [player.id])
		player.set_gem(player.gem - 1)
		engine._broadcast_game()
		ctx[KEY_DUAN_NIAN_STEP] = 1
		阶段 = 1
	if 阶段 == 1:
		if not engine.has_reply():
			询问(player.id, JIAN_YING_DUAN_NIAN, 2, 0, GConst.CardSource.Hand, [], 0, "", [], false, 0)
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		var 弃牌: Array = _pick_hand_cards(player, r.get("card_ids", []), 2)
		_fill_from_hand(player, 弃牌, 2)
		if not 弃牌.is_empty():
			engine.take_from_hand(player.id, 弃牌)
			engine.to_discard(弃牌)
			engine._log_discard(player.id, 弃牌)
		engine._broadcast_game()
		ctx[KEY_DUAN_NIAN_STEP] = STEP_DONE
		# 先挂上额外攻击行动，再摸牌：摸牌可能触发摸牌前响应 / 手牌超限，都排在行动结束之前结算
		player.add_action(GConst.ActionType.Attack, JIAN_YING_DUAN_NIAN, true, true)
		engine.push_draw(player.id, 1, JIAN_YING_DUAN_NIAN)
		return URGENT
	return SUCCESS


# ============================================================
# 主动攻击命中时（timeline_2_hit）：臆想剑（4502）
# ============================================================
func p_timeline_2_hit(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	var 阶段: int = int(ctx.get(KEY_YI_XIANG_STEP, 0))
	if 阶段 >= STEP_DONE:
		return SUCCESS
	# 回合限定只挡「新的一次发动」；已经发动、正在走弃牌 / 获得流程时 used 已经是 true，必须继续
	if 阶段 == 0 and used_yi_xiang_jian:
		return SUCCESS
	var dst: BattlePlayer = engine.p(int(ctx.get("dst", -1)))
	if dst == null:
		return SUCCESS
	# 目标没有手牌：弃不了牌，也就没有后续的获得 / 加伤
	if 阶段 == 0 and dst.hand_cards.is_empty():
		return SUCCESS
	if 阶段 == 0:
		if not engine.has_reply():
			engine.ask_skill(player.id, YI_XIANG_JIAN)
			return WAIT
		if not take_skill_reply():
			ctx[KEY_YI_XIANG_STEP] = STEP_DONE
			return SUCCESS
		used_yi_xiang_jian = true
		notice_skill(YI_XIANG_JIAN, [dst.id])
		ctx[KEY_YI_XIANG_STEP] = 1
		阶段 = 1
	if 阶段 == 1:
		if dst.hand_cards.is_empty():
			ctx[KEY_YI_XIANG_STEP] = STEP_DONE
			return SUCCESS
		if not engine.has_reply():
			询问(dst.id, YI_XIANG_JIAN, 1, 0, GConst.CardSource.Hand, [], 0, "", [], false, 0)
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		var 弃牌: Array = _pick_hand_cards(dst, r.get("card_ids", []), 1)
		_fill_from_hand(dst, 弃牌, 1)
		if 弃牌.is_empty():
			ctx[KEY_YI_XIANG_STEP] = STEP_DONE
			return SUCCESS
		var cid: int = int(弃牌[0])
		# 【强制】【展示】：全场公开牌面，再离手进弃牌堆
		engine.broadcast(GConst.Msg.Card, {
			"type": GConst.CardMsgType.Show, "src_id": dst.id, "dst_id": dst.id,
			"card_ids": [cid], "is_real": true,
		})
		engine.take_from_hand(dst.id, [cid], true)
		engine.to_discard([cid])
		engine._log_discard(dst.id, [cid], false)
		ctx[KEY_YI_XIANG_CARD] = cid
		# 弃牌带【展示】：take_from_hand(..., true) 已经压入了 p_show_hand 钩子。必须先让展示响应
		# 结算完（可能是等待型响应，如圣女弃出水系牌触发【冰霜祷言】），再回重入里问「是否获得」——
		# 否则询问会排在展示响应之前下发，玩家的第一次回答还会被后面的展示等待吞掉。
		ctx[KEY_YI_XIANG_STEP] = YI_XIANG_STEP_SHOWED
		engine._broadcast_game()
		return URGENT
	# 2：【展示】响应已经结算完。法术牌直接加伤；攻击牌进入「是否获得」询问。
	if 阶段 == YI_XIANG_STEP_SHOWED:
		var cid2: int = int(ctx.get(KEY_YI_XIANG_CARD, -1))
		var card: GCard = Data.get_card(cid2) if cid2 >= 0 else null
		if card != null and card.is_magic():
			# 法术牌：本次攻击伤害 +2（本次攻击的 harm 与 ctx 是同一份字典）
			var harm: Dictionary = ctx.get("harm", {})
			harm["point"] = int(harm.get("point", 0)) + 2
			ctx[KEY_YI_XIANG_STEP] = STEP_DONE
			return SUCCESS
		if card == null or not card.is_attack() or not engine.deck.discard.has(cid2):
			ctx[KEY_YI_XIANG_STEP] = STEP_DONE
			return SUCCESS
		ctx[KEY_YI_XIANG_STEP] = YI_XIANG_STEP_ASK_OBTAIN
		阶段 = YI_XIANG_STEP_ASK_OBTAIN
	if 阶段 == YI_XIANG_STEP_ASK_OBTAIN:
		if not engine.has_reply():
			# 提示列第 2 条：攻击牌可获得并额外 +1 攻击行动（获得与额外行动绑定在一起）
			询问(player.id, YI_XIANG_JIAN, 0, 0, GConst.CardSource.Hand, [], 0, "", [], true, 1)
			return WAIT
		ctx[KEY_YI_XIANG_STEP] = STEP_DONE
		if not take_skill_reply():
			return SUCCESS
		var cid3: int = int(ctx.get(KEY_YI_XIANG_CARD, -1))
		if cid3 < 0 or not engine.deck.discard.has(cid3):
			return SUCCESS
		engine.deck.remove_one(cid3)
		player.add_hand_cards([cid3])
		player.add_action(GConst.ActionType.Attack, YI_XIANG_JIAN, true, true)
		engine._broadcast_game()
	return SUCCESS


# ============================================================
# 攻击行动结束后的通用钩子：梦想剑档位推进（4503）
# ============================================================
func p_action_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if str(ctx.get("kind", "")) != "attack":
		return SUCCESS
	var n: int = player.attack_action_count
	if n == 1 and not dream_ignore_shield:
		dream_ignore_shield = true
		notice_skill(MENG_XIANG_JIAN, [player.id])
	elif n == 2 and not dream_no_reattack:
		dream_no_reattack = true
		notice_skill(MENG_XIANG_JIAN, [player.id])
	elif n >= 4 and not dream_no_miss:
		dream_no_miss = true
		notice_skill(MENG_XIANG_JIAN, [player.id])
	_同步梦想剑展示档()
	return SUCCESS


# ============================================================
# 额外行动限制（F2）：4501 的攻击行动只能使用技类命格攻击牌
# ============================================================
func extra_action_card_ids(cause: int, action_type: int) -> Array:
	if cause != JI_ZHI_JIAN_YI or action_type != GConst.ActionType.Attack:
		return []
	var 牌表: Array[int] = _martial_attack_hand_ids()
	# 空表会被引擎当成「没配限制」；一张都没有时显式给全禁
	return 牌表 if not 牌表.is_empty() else [GConst.手牌白名单_全禁]


# ============================================================
# 工具
# ============================================================
## 手牌里的「技类命格攻击牌」
func _martial_attack_hand_ids() -> Array[int]:
	var out: Array[int] = []
	for cid: int in player.hand_cards:
		var c: GCard = Data.get_card(cid)
		if c != null and c.is_attack() and c.fate_pattern_enum() == GConst.FatePattern.Martial:
			out.append(cid)
	return out


## 只保留玩家真正选中的、确实还在手牌里的牌（不补牌）
func _pick_hand_cards(持有人: BattlePlayer, ids: Array, n: int) -> Array:
	var out: Array = []
	for v: Variant in ids:
		if out.size() >= n:
			break
		var cid: int = int(v)
		if 持有人.has_discard_card(cid) and not out.has(cid):
			out.append(cid)
	return out


## 强制弃牌用：玩家没选满（超时 / 空回复）时按手牌顺序补到 n 张
func _fill_from_hand(持有人: BattlePlayer, out: Array, n: int) -> void:
	for cid: int in 持有人.hand_cards:
		if out.size() >= n:
			break
		if not out.has(cid):
			out.append(cid)
