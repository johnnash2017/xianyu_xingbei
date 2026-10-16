extends BattleRole
## 精灵射手（roleID 32）—— 移植自服务端 role/JingLingSheShou.cpp
## 形态：tap（【精灵祝福形态】）；盖牌：【祝福】(cover_cards_max)，上限见角色表
## 技能：元素射击（3201，响应・回合限定：主动攻击时若攻击牌非暗系，弃 1 张法术牌或移除 1 张【祝福】，
##                 按攻击牌系别附加元素箭：火 +1 伤害 / 地 命中后额外 1 点法术伤害 /
##                 风 攻击行动结束后额外 1 次攻击行动 / 雷 本次攻击无法应战 / 水 命中后目标 +1 治疗）、
##       动物伙伴（3202，响应：你造成伤害结算后，你摸 1 张牌【强制】弃 1 张牌）、
##       宠物强化（3204，响应：触发【动物伙伴】时若你有【水晶】，可多付 1【水晶】
##                 把效果改为「令 1 名角色摸 1 张牌【强制】弃 1 张牌」）、
##       精灵密仪（3203，启动：技能栏按钮，耗 1 宝石并【横置】转为【精灵祝福形态】，牌库顶 3 张作为【祝福】；
##                 回合结束时若没有【祝福】则【重置】脱离该形态，并对目标角色造成 2 点法术伤害）

const YUAN_SU_SHE_JI: int = 3201
## 元素射击「命中结算」的两种箭：各自的询问号与客户端指示器条目（见 GConst.技能_水之矢 / 技能_地之矢）
const SHUI_ZHI_SHI: int = 32012
const DI_ZHI_SHI: int = 32013
const DONG_WU_HUO_BAN: int = 3202
const DONG_WU_HUO_BAN_DISCARD: int = 32021
const CHONG_WU_QIANG_HUA: int = 3204
const JING_LING_MI_YI: int = 3203
const JING_LING_MI_YI_BOOT: int = 32031


## 元素箭待结算标记（命中后生效）
var shui_zhi_shi: bool = false
var di_zhi_shi: bool = false
## 本回合是否已发动元素射击
var used_yuan_su_she_ji: bool = false
## 动物伙伴指定的弃牌角色
var _dw_target: int = -1


func p_before_turn_begin(_ctx: Dictionary) -> int:
	used_yuan_su_she_ji = false
	return SUCCESS


## 说明：【精灵祝福形态】下你的【祝福】可视为手牌使用或打出（打牌 / 应战）——
## 因此出牌合法性（BattlePlayer.has_hand_card）、打牌落位（remove_hand_cards）都把【祝福】当手牌。
## 弃牌不算：任何弃手牌效果（爆牌、技能代价、他人令弃）只认真实手牌
## （BattlePlayer.has_discard_card），盖牌不会被列出、也不能被弃掉
func 盖牌可当手牌() -> bool:
	return player.tap


# ============================================================
# 行动阶段可发动的技能：精灵密仪（3203）为「启动」，不消耗行动
# （is_free_skill 认可，发动后引擎重新进入行动阶段让玩家继续本回合行动）
# ============================================================
func available_skills() -> Array:
	var out: Array = []
	# 精灵密仪：有宝石且未横置（未处于【精灵祝福形态】）时才能发动（耗 1 宝石并横置）
	out.append({"type": GConst.ActionType.SpecialSkill, "id": JING_LING_MI_YI,
		"need_card": 0, "need_target": 0,
		"enabled": player.gem > 0 and not player.tap})
	return out


## 【精灵密仪】为「启动」：不消耗本回合行动，发动后行动阶段照旧继续
func is_free_skill(skill_id: int) -> bool:
	return skill_id == JING_LING_MI_YI


func v_special_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != JING_LING_MI_YI:
		return GConst.GE_INVALID_ACTION
	# 无宝石或已处于【精灵祝福形态】：不能发动
	if player.gem <= 0 or player.tap:
		return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


## 精灵密仪（启动）：耗 1 宝石并【横置】转入【精灵祝福形态】，牌库顶 3 张面朝下作为【祝福】。
## 由技能栏按钮直接发动（不再在回合开始弹「要不要发动」的询问）
func p_special_skill(_action: Dictionary) -> int:
	notice_skill(JING_LING_MI_YI, [player.id])
	player.boot_skill_used = true
	engine.set_tap(player.id, true)
	player.set_gem(player.gem - 1)
	# 牌库顶 3 张面朝下放置于角色旁作为【祝福】
	var cards: Array = engine.draw(player.id, 3)
	if not cards.is_empty():
		engine.take_from_hand(player.id, cards)
		engine.add_cover(player.id, cards, player.id, JING_LING_MI_YI_BOOT)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 回合结束：精灵密仪（无【祝福】时脱离形态并对目标角色 2 点法术伤害）
# ============================================================
## 【精灵密仪】的推进阶段（0＝还没开始 / JING_LING_MI_YI＝已脱形态、等目标回复）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而本流程一开场就脱形态
## （player.tap = false 会压入一轮 p_tap 钩子）—— 那一轮开始把 step 抹掉后，流程退回第 0 步，
## 入口条件（要有形态）此刻已不成立 → 2 点法术伤害整条不生效。每回合结束都可能触发，收尾清回 0
var _mi_yi_step: int = 0


func p_turn_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if _mi_yi_step >= STEP_DONE:
		return SUCCESS
	# 入口条件（处于形态、没有【祝福】）只在第 0 步判：本条流程一开场就把 player.tap 置回 false，
	# 之后重入（等回复回来时会再进一次本钩子）不能再用 tap 当门槛，否则伤害整条不生效
	if _mi_yi_step == 0:
		if not player.tap or player.cover_count() > 0:
			return SUCCESS
		_mi_yi_step = JING_LING_MI_YI
	if _mi_yi_step != JING_LING_MI_YI:
		return SUCCESS
	# 服务端先【重置】再询问目标；未提供目标时以自己为目标
	player.tap = false
	engine._broadcast_game()
	if not engine.has_reply():
		询问(player.id, JING_LING_MI_YI, 0, 1)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	_mi_yi_step = 0
	var dsts: Array = r.get("dst_ids", [])
	var dst_id: int = int(dsts[0]) if not dsts.is_empty() else player.id
	notice_skill(JING_LING_MI_YI, [dst_id])
	engine.push_harm({
		"src": player.id, "dst": dst_id, "point": 2,
		"cause": JING_LING_MI_YI, "type": GConst.HarmType.Magic,
	})
	engine._broadcast_game()
	return URGENT


# ============================================================
# 主动攻击宣告时：元素射击（弃 1 张法术牌或移除 1 张【祝福】，按攻击牌系别附加元素箭）
# ============================================================
func p_timeline_1(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id or not bool(ctx.get("is_active", false)):
		return SUCCESS
	if used_yuan_su_she_ji:
		return SUCCESS
	var atk: GCard = Data.get_card(int(ctx.get("card_id", -1)))
	if atk == null or atk.element_enum() == GConst.CardElement.Darkness:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if step == 0:
		step = YUAN_SU_SHE_JI
	if step != YUAN_SU_SHE_JI:
		return SUCCESS
	if not engine.has_reply():
		# 不设二级选项：法术手牌与【祝福】盖牌合成一份白名单下发，玩家点哪张就走哪一支
		# （界面把攻击牌等其余手牌置灰；服务端下面再按选中的那张牌最终校验）
		var 可弃: Array[int] = magic_hand_ids()
		可弃.append_array(player.cover_cards)
		询问(player.id, YUAN_SU_SHE_JI, 1, 0, GConst.CardSource.HandOrCover, [], 1, "", 可弃)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	var cards: Array = r.get("card_ids", [])
	if cards.is_empty():
		return SUCCESS
	var cid: int = int(cards[0])
	# 没有选项：选中的是盖牌就移除【祝福】，是手牌就必须是法术牌
	var 用盖牌: bool = player.cover_cards.has(cid)
	if not 用盖牌:
		var card: GCard = Data.get_card(cid)
		if card == null or not card.is_magic() or not player.has_hand_card(cid):
			return SUCCESS
	notice_skill(YUAN_SU_SHE_JI, [int(ctx.get("dst", -1))])
	used_yuan_su_she_ji = true
	var harm: Dictionary = ctx.get("harm", {})
	match atk.element_enum():
		GConst.CardElement.Fire:
			harm["point"] = int(harm.get("point", 0)) + 1
		GConst.CardElement.Earth:
			di_zhi_shi = true
		GConst.CardElement.Thunder:
			ctx["hit_rate"] = GConst.HitRate.NoReattack
		GConst.CardElement.Water:
			shui_zhi_shi = true
		GConst.CardElement.Wind:
			player.add_action(GConst.ActionType.Attack, YUAN_SU_SHE_JI, true)
		_:
			# 服务端 default：技能已发动并记录，但不结算弃牌
			engine._broadcast_game()
			return SUCCESS
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": [cid], "is_real": true,
	})
	if 用盖牌:
		engine.remove_cover(player.id, [cid], player.id, YUAN_SU_SHE_JI)
	else:
		engine.take_from_hand(player.id, [cid], true)
	engine.to_discard([cid])
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 主动攻击命中后：元素箭（水之矢 +1 治疗 / 地之矢 1 点法术伤害）
# ============================================================
## 本次命中结算要走的箭号：水之矢 / 地之矢各一条询问号，客户端按各自的指示器条目画提示
func 本次箭号() -> int:
	return SHUI_ZHI_SHI if shui_zhi_shi else DI_ZHI_SHI


func p_timeline_2_hit(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id or not bool(ctx.get("is_active", false)):
		return SUCCESS
	if not shui_zhi_shi and not di_zhi_shi:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if step == 0:
		step = 本次箭号()
	if step != 本次箭号():
		return SUCCESS
	if not engine.has_reply():
		询问(player.id, 本次箭号(), 0, 1)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	var dsts: Array = r.get("dst_ids", [])
	var dst_id: int = int(dsts[0]) if not dsts.is_empty() else player.id
	if shui_zhi_shi:
		shui_zhi_shi = false
		notice_skill(SHUI_ZHI_SHI, [dst_id])
		var dp: BattlePlayer = engine.p(dst_id)
		if dp != null:
			施加治疗(dp.id, 1)
		engine._broadcast_game()
		return SUCCESS
	di_zhi_shi = false
	notice_skill(DI_ZHI_SHI, [dst_id])
	engine.push_harm({
		"src": player.id, "dst": dst_id, "point": 1,
		"cause": DI_ZHI_SHI, "type": GConst.HarmType.Magic,
	})
	engine._broadcast_game()
	return URGENT


func p_timeline_2_miss(_ctx: Dictionary) -> int:
	shui_zhi_shi = false
	di_zhi_shi = false
	return SUCCESS


# ============================================================
# 造成伤害结算后：动物伙伴（3202，说明为准：**你**摸 1 张【强制】弃 1 张）
#   若你有【水晶】，这次会多出【宠物强化】（3204）的选项：多付 1【水晶】改为
#   「令 1 名角色摸 1 张【强制】弃 1 张」（选人放在第二步；费用先付，故那一步不可取消）
# 顺序：先摸 1 张（走 push_draw，先让角色响应，如【水影】），再由被指定的角色强制弃 1 张
# ============================================================
## 【动物伙伴】的推进阶段（0＝还没问 / DONG_WU_HUO_BAN＝等「怎么发动」/ DONG_WU_HUO_BAN_DISCARD＝等弃牌）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨两次询问、
## 中间还为目标摸 1 张牌（走 push_draw，会另起一轮钩子）。弃牌那步放在独立钩子 p_dong_wu_huo_ban_discard
## 里执行（排在摸牌之后），这样「摸牌前响应（如【水影】）」和「弃牌时含刚摸进来的牌」都成立。收尾清回 0
var _dw_step: int = 0


func p_timeline_6_drawn(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("src", -1)) != player.id or engine.current_id != player.id:
		return SUCCESS
	if _dw_step >= STEP_DONE:
		return SUCCESS
	if _dw_step == 0:
		_dw_step = DONG_WU_HUO_BAN
	if _dw_step == DONG_WU_HUO_BAN:
		if not engine.has_reply():
			# 有能量才多出【宠物强化】那个选项（说明：消耗 1【水晶】；
			# 【水晶】可用【宝石】替代支付，与【圣疗】/【剑影】等水晶消耗技能同一口径）
			# 序号 1：第 0 条提示是「叫别人交牌」用的，这步「怎么发动」读第 1 条
			var 选项: Array = [{"value": 1, "label": "你摸 1 张、弃 1 张【强制】"}]
			if player.get_energy() >= 1:
				# 绑上【宠物强化】的技能号：选项按钮悬停能看它的技能说明，提示条也按它称呼
				选项.append({"value": 2, "skill_id": CHONG_WU_QIANG_HUA,
					"label": "消耗 1 能量，改为令 1 名角色摸 1 张、弃 1 张【强制】"})
			询问(player.id, DONG_WU_HUO_BAN, 0, 0, GConst.CardSource.Hand, 选项, 0, "", [], true, 1)
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		var args: Array = r.get("args", [])
		var choice: int = int(args[0]) if not args.is_empty() else 0
		if choice == 1:
			# 【动物伙伴】本体：自己摸 1 张、弃 1 张
			_dw_step = DONG_WU_HUO_BAN_DISCARD
			_dw_target = player.id
			notice_skill(DONG_WU_HUO_BAN, [player.id])
			engine._broadcast_game()
			engine.push(BattleEngine.SHook.new("p_dong_wu_huo_ban_discard", {"player": _dw_target}, []))
			engine.push_draw(_dw_target, 1)
			return SUCCESS
		if choice != 2 or player.get_energy() < 1:
			# 不发动（或能量在中途被消耗掉了）：这条流程到此为止
			_dw_step = 0
			return SUCCESS
		# 【宠物强化】：目标与「选哪个选项」在同一次询问里选好后一起提交
		# （客户端指示器配了「选项目标数 {2: 1}」，选中该项即放开点头像），故这里直接读本次回复的 dst_ids
		var dsts: Array = r.get("dst_ids", [])
		if dsts.is_empty():
			# 没点目标（例如选好选项就超时）＝当作没发动，不扣能量
			_dw_step = 0
			return SUCCESS
		# 付 1 能量（先扣【水晶】、不够再用【宝石】）
		player.remove_energy(1)
		_dw_step = DONG_WU_HUO_BAN_DISCARD
		_dw_target = int(dsts[0])
		notice_skill(CHONG_WU_QIANG_HUA, [_dw_target])
		engine._broadcast_game()
		# 目标先摸 1 张再弃 1 张：摸牌走 push_draw（先让角色响应，如【水影】）；弃牌另起一轮钩子，
		# 先压弃牌钩子、后压摸牌（LIFO）→ 先摸牌、后弃牌，弃牌时手里已含刚摸进来的牌
		engine.push(BattleEngine.SHook.new("p_dong_wu_huo_ban_discard", {"player": _dw_target}, []))
		engine.push_draw(_dw_target, 1)
	return SUCCESS


## 动物伙伴 / 宠物强化：目标摸完 1 张后，从手牌（含刚摸进来的牌）**强制**弃 1 张
## （独立钩子轮次，保证「摸」先于「弃」）
func p_dong_wu_huo_ban_discard(ctx: Dictionary) -> int:
	if _dw_step != DONG_WU_HUO_BAN_DISCARD or int(ctx.get("player", -1)) != _dw_target:
		return SUCCESS
	var t: BattlePlayer = engine.p(_dw_target)
	if t == null or t.hand_cards.is_empty():
		_dw_step = 0
		return SUCCESS
	if not engine.has_reply():
		# 强制交牌：不给「取消」（服务端 canGiveUp = false；超时由下方兜底自动取首张）
		询问(t.id, DONG_WU_HUO_BAN, 1, 0, GConst.CardSource.Hand, [], 0, "", [], false, 0)
		return WAIT
	_dw_step = 0
	var r3: Dictionary = take_skill_reply_full()
	var cid: int = _hand_card_of(t, r3.get("card_ids", []))
	if cid < 0:
		# 取消/超时：必须交出，故自动取首张
		cid = int(t.hand_cards[0])
	engine.take_from_hand(t.id, [cid])
	engine.to_discard([cid])
	engine._broadcast_game()
	return SUCCESS


## 取回复中第一张目标手里真实存在的手牌（无则 -1）。弃牌不能弃【祝福】，
## 故这里用 has_discard_card 而不是 has_hand_card（后者会把视同手牌的盖牌也算进来）
func _hand_card_of(t: BattlePlayer, ids: Array) -> int:
	for c: Variant in ids:
		if t.has_discard_card(int(c)):
			return int(c)
	return -1
