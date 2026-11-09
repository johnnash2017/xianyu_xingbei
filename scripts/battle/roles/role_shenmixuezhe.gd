extends BattleRole
## 神秘学者（roleID 80）
##
## 【言灵】＝角色旁面朝上的牌（盖牌区 open=true，上限读角色表盖牌槽：3）；【秘术】＝0 号指示物（上限 4）。
##
## 技能：
##   言灵术 8001（法术）：将 1~2 张手牌面朝上作为【言灵】；你摸 1 张牌【强制】；
##       （摸牌后，若你额外弃 1 张与现存【言灵】系别相同的牌【展示】）你 +1【秘术】。
##   守护灵 8002（被动）：【言灵】数>0 且你被主动攻击命中②（其他角色结算效果前）→ 移除 1 个【言灵】；
##       若【秘术】>0，移除 1 点【秘术】，把 1 张手牌面朝上作为【言灵】。
##   真言术 8003（法术）：把 1 个除光系外的【言灵】当手牌打出，执行对应行动；
##       若该【言灵】是咏类命格或法术牌（或你额外移除 1 点【秘术】），行动结算完对目标对手 1 点法术伤害③。
##   禁忌秘法 8004（响应）：你的回合开始前，移除 3 点【秘术】→ 指定 2 名角色各弃 1 张牌，
##       你把弃牌面朝上作为【言灵】。
##   妖精秘术 8005（响应【回合限定】）：【真言术】或【真言压制】结算后，立即执行一次【攻击行动】；
##       若本次执行的攻击命中②，你 +2【秘术】。
##   真言压制 8006（响应·必杀【水晶】）：【真言术】结算后，对目标角色 1 点法术伤害③，
##       你可立即执行一次【真言术】。
##
## 参考实现：9303 / 8601 的「把牌作为相应行动发出」（加入手牌 + direct 额外行动 + 白名单），
## 7802 的多步询问与「摸牌后重入技能本体」（技能URGENT后重入），7805 的「别人弃牌先问本人」。

const YAN_LING_SHU: int = 8001
const SHOU_HU_LING: int = 8002
const ZHEN_YAN_SHU: int = 8003
const JIN_JI_MI_FA: int = 8004
const YAO_JING_MI_SHU: int = 8005
const ZHEN_YAN_YA_ZHI: int = 8006

const 秘术槽: int = 0

## 言灵术：0＝未开始 / 1＝已放言灵等摸牌 / 2＝等额外弃牌 / 3＝完成
var _言灵术阶段: int = 0
## 出牌那一下：盖牌区里的【言灵】可以当手牌用（同步窗口，出牌调用返回就关掉）
var _真言行动中: bool = false
## 真言术这次用掉的言灵是不是咏类 / 法术牌（行动结束后据此决定要不要问【秘术】）
var _真言加伤: bool = false
## 真言术行动结束后的收尾阶段：0＝未处理 / 1＝等「是否额外移除 1 点【秘术】」 / 2＝等选伤害目标 / 3＝已结算
var _真言伤阶段: int = 0
## 禁忌秘法：0＝未开始 / 1＝等选 2 名目标 / 2＝等两名目标各弃 1 张
var _禁忌阶段: int = 0
var _禁忌目标: Array = []
var _禁忌弃牌: Array = []
## 真言压制：0＝没挂 / 1＝等那 1 点伤害结算完 / 2＝等「是否发动真言术」/ 3＝等选言灵+目标
var _真言压制阶段: int = 0
## 妖精秘术：本回合已用；给出的攻击行动进行中
var _妖精已用: bool = false
var _妖精攻击中: bool = false
## 守护灵：0＝未问 / 1＝等选言灵（+手牌）
var _守护灵阶段: int = 0


# ============================================================
# 技能栏
# ============================================================
func available_skills() -> Array:
	return [
		{
			"type": GConst.ActionType.MagicSkill,
			"id": YAN_LING_SHU,
			"need_card": 1,
			"card_max": 2,
			"need_target": 0,
			# 【言灵】允许超过盖牌上限：多出来的由引擎的「盖牌超限」询问让玩家自己弃
			# （与魔弓【充能】同一套处理，见 SCoverOverflow）；所以这里不再看 cover_space
			"enabled": not player.hand_cards.is_empty(),
		},
		_真言技能项(),
	]


## 【真言术】的技能栏规格（和别的技能一样由 available_skills 声明选牌 / 选目标，
## 客户端点技能按钮就直接进「盖牌区点 1 张言灵 + 点 1 名目标」的选牌状态，不另开询问）
func _真言技能项() -> Dictionary:
	var 可用: Array = _可用言灵()
	return {
		"type": GConst.ActionType.MagicSkill,
		"id": ZHEN_YAN_SHU,
		"need_card": 1,
		"need_target": 1,
		"card_source": GConst.CardSource.Cover,
		"cards": 可用,
		"targets": 全部角色(),
		"enabled": not 可用.is_empty(),
	}


func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	var 技能号: int = int(action.get("action_id", 0))
	if 技能号 == YAN_LING_SHU:
		var cards: Array = action.get("card_ids", [])
		# 不再限制「不能超过盖牌上限」：超出的部分由盖牌超限询问让玩家弃（同魔弓【充能】）
		if cards.is_empty() or cards.size() > 2:
			return GConst.GE_INVALID_ACTION
		for c: Variant in cards:
			if player.手牌实例(int(c)) < 0:
				return GConst.GE_INVALID_ACTION
		_言灵术阶段 = 0
		return GConst.GE_SUCCESS
	if 技能号 == ZHEN_YAN_SHU:
		# 提交的是「盖牌区里的一张言灵 + 一名目标」：逐项复核（客户端只是体验过滤）
		var cards2: Array = action.get("card_ids", [])
		var dsts: Array = action.get("dst_ids", [])
		if _可用言灵().is_empty() or cards2.size() != 1 or dsts.size() != 1:
			return GConst.GE_INVALID_ACTION
		var 实例: int = player.盖牌实例(int(cards2[0]))
		if 实例 < 0 or not _可用言灵().has(实例):
			return GConst.GE_INVALID_CARDID
		var 牌: GCard = Data.get_card(实例)
		if 牌 == null:
			return GConst.GE_INVALID_ACTION
		if not _真言能打(实例, 牌, int(dsts[0])):
			return GConst.GE_INVALID_ACTION
		_真言加伤 = false
		_真言伤阶段 = 0
		_真言压制阶段 = 0
		return GConst.GE_SUCCESS
	return GConst.GE_INVALID_ACTION


func p_magic_skill(action: Dictionary) -> int:
	var 技能号: int = int(action.get("action_id", 0))
	if 技能号 == YAN_LING_SHU:
		return _言灵术(action)
	if 技能号 == ZHEN_YAN_SHU:
		return _真言术(action)
	return EMPTY_HANDLE


## 言灵术：放 1~2 张言灵 → 摸 1 张（状态版）→ 回来问「额外弃 1 张同系牌」
func _言灵术(action: Dictionary) -> int:
	if _言灵术阶段 == 3:
		return SUCCESS
	if _言灵术阶段 == 0:
		var cards: Array = action.get("card_ids", [])
		notice_skill(YAN_LING_SHU, [player.id])
		engine.take_from_hand(player.id, cards)
		engine.add_cover(player.id, cards, player.id, YAN_LING_SHU, true)
		_言灵术阶段 = 1
		engine.push_强制摸牌(player.id, 1, YAN_LING_SHU)
		# 公开亮出手牌（触发封印类响应）；压在摸牌之后 → 先结算展示响应，再摸牌
		engine.展示手牌(player.id, cards)
		return URGENT
	if _言灵术阶段 == 1:
		# 摸牌（含超限弃牌 / 言灵超限）结算完回来：不管有没有同系手牌都要问这一问
		# （手里没有能弃的牌时，白名单用「全禁」，玩家只能点「取消」——这一步仍然摆出来）
		var 同系: Array = _同系手牌()
		_言灵术阶段 = 2
		询问(player.id, YAN_LING_SHU, 1, 0, GConst.CardSource.Hand, [], 0, "",
			同系 if not 同系.is_empty() else [GConst.手牌白名单_全禁], true,
			0, -1, [], -1, {})
		return WAIT
	# 阶段 2：额外弃 1 张同系牌 → +1【秘术】
	var r: Dictionary = take_skill_reply_full()
	_言灵术阶段 = 3
	var cards2: Array = r.get("card_ids", [])
	if cards2.is_empty():
		return SUCCESS
	var 弃: int = -1
	for c: Variant in cards2:
		var 实例: int = player.手牌实例(int(c))
		if 实例 >= 0 and _同系手牌().has(实例):
			弃 = 实例
			break
	if 弃 < 0:
		# 白名单已经把可弃的牌限死；走到这里说明是硬提交的非法牌
		engine.报错("【言灵术】提交的牌与现存【言灵】不同系或不在手里", player.id)
		return SUCCESS
	# 这张牌是公开弃掉的（技能表写的是弃 1 张【展示】）：走统一入口，顺带走「展示手牌」钩子。
	# 压在最后 → LIFO 下先结算展示响应（封印类），再跑这次技能的行动结束。
	engine.take_from_hand(player.id, [弃])
	engine.to_discard([弃], {"owner": player.id, "source": "hand", "cause": YAN_LING_SHU})
	engine._log_discard(player.id, [弃], false)
	player.add_token(秘术槽, 1)
	engine.展示手牌(player.id, [弃])
	return URGENT


## 摸完牌要回来接着问「额外弃牌」：只放行 8001 的这一步
func 技能URGENT后重入(action: Dictionary = {}) -> bool:
	return int(action.get("action_id", 0)) == YAN_LING_SHU and _言灵术阶段 == 1


# ============================================================
# 真言术：把 1 个非光系【言灵】当手牌打出
# 和别的技能一样由 available_skills 声明「选 1 张盖牌 + 选 1 名目标」：
#   点技能按钮 → 客户端直接进选牌状态（盖牌区亮出来）→ 点言灵 → 点目标 → 确定，
#   这一次提交里就带着「哪张言灵 + 打谁」，服务端直接当那张牌打出去。
#   点「取消」＝技能不发动，退回行动阶段。
# ============================================================
func _真言术(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	if cards.is_empty() or dsts.is_empty():
		return SUCCESS
	var 选中: int = player.盖牌实例(int(cards[0]))
	if 选中 < 0:
		return SUCCESS
	var 牌: GCard = Data.get_card(选中)
	if 牌 == null:
		return SUCCESS
	var dst: int = int(dsts[0])
	notice_skill(ZHEN_YAN_SHU, [dst])
	# 出牌这一步里这张盖牌要能当手牌用（引擎出牌路径靠 has_hand_card 认牌、remove_hand_cards 从盖牌区删）
	_真言行动中 = true
	var 种类: int = GConst.ActionType.Attack if 牌.is_attack() else GConst.ActionType.Magic
	var 结果: int = engine.技能出牌(player.id, 种类, [选中], [dst], ZHEN_YAN_SHU)
	_真言行动中 = false
	if 结果 < 0:
		engine.报错("【真言术】这张【言灵】打不出去", player.id)
		return SUCCESS
	engine._broadcast_game()
	return URGENT


## 这张言灵能不能对这名角色用（与引擎出牌路径同一套 v_* 校验；v_magic_skill 用它复核提交）
func _真言能打(cid: int, 牌: GCard, dst: int) -> bool:
	var dp: BattlePlayer = engine.p(dst)
	if dp == null:
		return false
	# v_attack / v_shield 这些校验都走 has_hand_card：校验期间要把这张盖牌当手牌用
	var 原窗口: bool = _真言行动中
	_真言行动中 = true
	var 结果: bool = _真言能打内(牌, cid, dst, dp)
	_真言行动中 = 原窗口
	return 结果


func _真言能打内(牌: GCard, cid: int, dst: int, dp: BattlePlayer) -> bool:
	if 牌.is_attack():
		return player.v_attack(cid, dst, engine.players) == GConst.GE_SUCCESS \
			and dp.v_attacked() == GConst.GE_SUCCESS
	match 牌.card_name_enum():
		GConst.CardName.Shield:
			return player.v_shield(dst, engine.players) == GConst.GE_SUCCESS \
				and engine.v_basic_effect_target(dst, cid) == GConst.GE_SUCCESS
		GConst.CardName.Weaken:
			return player.v_weaken(dst, engine.players) == GConst.GE_SUCCESS
		GConst.CardName.Poison:
			return engine.v_basic_effect_target(dst, cid) == GConst.GE_SUCCESS
		GConst.CardName.Missile:
			return player.v_missile(cid, dst) == GConst.GE_SUCCESS
	return false


## 出牌那一下盖牌区里的【言灵】可以当手牌用（引擎 has_hand_card / remove_hand_cards 都认）
func 盖牌可当手牌() -> bool:
	return _真言行动中


## 技能表「说明」的后半段（第一个「；」之后）。「额外移除 1 点【秘术】」那一问的提示只用这半句。
func _真言后半段() -> String:
	var 全: String = GConst.skill_desc(ZHEN_YAN_SHU)
	var 切: int = 全.find("；")
	return 全.substr(切 + 1).strip_edges() if 切 >= 0 else 全


## 真言术 / 真言压制 结算后的响应：妖精秘术（攻击行动）/ 真言压制（水晶 1 点法术伤害）
func action_end_options(ctx: Dictionary) -> Array:
	var cause: int = int(ctx.get("extra_cause", 0))
	if int(ctx.get("player", -1)) != player.id or (cause != ZHEN_YAN_SHU and cause != ZHEN_YAN_YA_ZHI):
		return []
	if not bool(ctx.get("is_extra", false)):
		return []
	var out: Array = []
	if not _妖精已用:
		out.append({
			"value": YAO_JING_MI_SHU,
			"label": GConst.按钮原文(YAO_JING_MI_SHU, 0),
			"text": GConst.按钮原文(YAO_JING_MI_SHU, 0),
			"skill_id": YAO_JING_MI_SHU,
			"enabled": true,
			"need_target": 0,
		})
	out.append({
		"value": ZHEN_YAN_YA_ZHI,
		"label": GConst.按钮原文(ZHEN_YAN_YA_ZHI, 0),
		"text": GConst.按钮原文(ZHEN_YAN_YA_ZHI, 0),
		"skill_id": ZHEN_YAN_YA_ZHI,
		"need_target": 1,
		"targets": 全部角色(),
		# 选这一项时把盖牌区亮出来给玩家看（纯展示、一张都点不动）：
		# 让他先知道还有没有【言灵】可以接着发动真言术
		"展示盖牌": true,
		"enabled": player.get_energy() >= 1,
	})
	return out


func resolve_action_end_option(cause: int, reply: Dictionary, _ctx: Dictionary) -> int:
	if cause == YAO_JING_MI_SHU:
		_妖精已用 = true
		_妖精攻击中 = true
		notice_skill(YAO_JING_MI_SHU, [player.id])
		player.add_action(GConst.ActionType.Attack, YAO_JING_MI_SHU, true)
		engine._broadcast_game()
		return SUCCESS
	if cause == ZHEN_YAN_YA_ZHI:
		var dsts: Array = reply.get("dst_ids", [])
		if dsts.is_empty():
			# 聚合器被唤醒后的「续跑」没有回复：这条技能的多步结算已经自己接管
			# （伤害 → p_harm_end 问是否发动真言术 → …），这里直接返回成功，
			# 让聚合器继续收集并询问剩下的选项（妖精秘术就是这么被漏掉的）
			return GConst.GE_SUCCESS
		if player.get_energy() < 1:
			return GConst.GE_INVALID_ARGUMENT
		var dst: int = int(dsts[0])
		if engine.p(dst) == null:
			return GConst.GE_INVALID_PLAYERID
		notice_skill(ZHEN_YAN_YA_ZHI, [dst])
		player.remove_energy(1)
		# 「你可立即执行一次【真言术】」＝响应后白送的一次发动，不消耗任何行动：
		# 先结算这 1 点法术伤害，伤害结算完再问「是否发动真言术」（见 p_harm_end）
		_真言压制阶段 = 1
		engine.push_harm({"src": player.id, "dst": dst, "point": 1,
			"cause": ZHEN_YAN_YA_ZHI, "type": GConst.HarmType.Magic})
		engine._broadcast_game()
		return URGENT
	return resolve_queued_extra_action(cause)


## 真言压制那 1 点法术伤害结算完之后：问「是否发动真言术」；选发动再走真言术的选牌流程。
## 真言术的说明全文（「【真言术】：…」）：真言压制触发的那次询问直接拿它当提示条
func _真言说明全文() -> String:
	var 说明: String = GConst.skill_desc(ZHEN_YAN_SHU).replace("\\n", "").replace("\n", "").strip_edges()
	if 说明.is_empty():
		return ""
	return "【%s】：%s" % [GConst.skill_name(ZHEN_YAN_SHU), 说明]


## 「哪张【言灵】+ 打谁」的询问（真言压制白送的那次真言术用它，取消＝不发动）
func _问真言选牌() -> void:
	_真言压制阶段 = 2
	询问(player.id, ZHEN_YAN_SHU, 1, 1, GConst.CardSource.Cover, [], 0, "", _可用言灵(), true,
		0, -1, 全部角色(), -1, {}, 0, 0, false, [], true, -1, 0, _真言说明全文())
## 这一整段都不消耗行动（不是额外行动，也不进行动阶段）。
func p_harm_end(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("src", -1)) != player.id or int(harm.get("cause", 0)) != ZHEN_YAN_YA_ZHI:
		return SUCCESS
	# 读完「哪张言灵 + 打谁」：合法就直接当那张牌打出去（技能出牌，不消耗行动）
	if _真言压制阶段 == 2:
		var r: Dictionary = take_skill_reply_full()
		_真言压制阶段 = 0
		var cards: Array = r.get("card_ids", [])
		var dsts: Array = r.get("dst_ids", [])
		if cards.is_empty() or dsts.is_empty():
			# 取消 ＝ 不发动【真言术】
			return SUCCESS
		var 实例: int = player.盖牌实例(int(cards[0]))
		var 牌: GCard = Data.get_card(实例) if 实例 >= 0 else null
		if 牌 == null or not _真言能打(实例, 牌, int(dsts[0])):
			# 这张言灵对这名角色不合法：报错重问，别让玩家白丢这次机会
			engine.报错("【真言压制】这张【言灵】不能对这名角色使用", player.id)
			_问真言选牌()
			return WAIT
		# 这次真言术是「真言压制白送」的：不再单开一轮行动结束响应，
		# 等它结算完直接回到外层那次响应的待决里继续问（否则会一层层套娃、取消很多次）
		engine.技能出牌不开响应 = true
		return _真言术(r)
	if _真言压制阶段 != 1:
		return SUCCESS
	_真言压制阶段 = 0
	# 「你可立即执行一次【真言术】」直接进真言术的选牌（省掉中间那一问）：
	# 没有可用【言灵】就不发动；玩家不想发动点取消即可。
	if _可用言灵().is_empty():
		return SUCCESS
	_问真言选牌()
	return WAIT

## 真言术给出的行动结算完：按「咏类/法术牌 → 直接打；否则有【秘术】才问」处理那 1 点法术伤害③
func p_action_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if not bool(ctx.get("is_extra", false)):
		return SUCCESS
	match int(ctx.get("extra_cause", 0)):
		ZHEN_YAN_SHU:
			# 第二段统一一条路（攻击牌 / 法术牌完全一样）：
			#   ① 打完先判断这次用的是不是咏类命格或法术牌；
			#   ② 问一次「两个选项 + 1 名目标」，两条选项由上面的判断点亮（可取消＝不打伤害）；
			#   ③ 确认后（选第 2 项要先移除 1 点【秘术】）对目标造成 1 点法术伤害。
			if _真言伤阶段 == 3:
				return SUCCESS
			if _真言伤阶段 == 1:
				# 读第二段的答复：取消 / 没选目标 / 选项非法 → 不对目标造成伤害
				var r: Dictionary = take_skill_reply_full()
				_真言伤阶段 = 3
				var args: Array = r.get("args", [])
				var dsts: Array = r.get("dst_ids", [])
				if args.is_empty() or dsts.is_empty():
					return SUCCESS
				var 档: int = int(args[0])
				var dst: int = int(dsts[0])
				if not enemy_ids().has(dst):
					return SUCCESS
				if 档 == 2:
					if _真言加伤 or player.token_num(秘术槽) <= 0:
						return SUCCESS
					player.remove_token(秘术槽, 1)
					engine._broadcast_game()
				elif 档 != 1 or not _真言加伤:
					return SUCCESS
				engine.push_harm({"src": player.id, "dst": dst, "point": 1,
					"cause": ZHEN_YAN_SHU, "type": GConst.HarmType.Magic})
				return URGENT
			var 用牌: GCard = Data.get_card(int(ctx.get("card_id", -1)))
			_真言加伤 = 用牌 != null and (用牌.is_magic() \
				or 用牌.fate_pattern_enum() == GConst.FatePattern.Cast)
			var 有秘术: bool = player.token_num(秘术槽) > 0
			if not _真言加伤 and not 有秘术:
				# 两条加成的条件都不成立：第二段不发生
				_真言伤阶段 = 3
				return SUCCESS
			# 选项固定两条，按这次用的牌点亮其中一条：
			#   第 1 项＝（【言灵】为咏类命格或法术牌）→ 是才亮
			#   第 2 项＝（额外移除 1 点【秘术】）→ 不是、且还有【秘术】才亮
			_真言伤阶段 = 1
			询问(player.id, ZHEN_YAN_SHU, 0, 1, GConst.CardSource.Hand, [
				# no_prompt_change：点这两个选项时不把提示条换成别的内容（保持第二段说明原文）
				{"value": 1, "label": "【言灵】为咏类命格或法术牌", "enabled": _真言加伤,
					"no_prompt_change": true},
				{"value": 2, "label": "额外移除 1 点【秘术】", "enabled": (not _真言加伤) and 有秘术,
					"no_prompt_change": true},
			], 0, "", [], true,
				0, -1, enemy_ids(), -1, {}, 1, GConst.HarmType.Magic, false, [], true, -1, 0,
				_真言后半段(), -1, _真言后半段())
			return WAIT
		YAO_JING_MI_SHU:
			_妖精攻击中 = false
	return SUCCESS


## 回合结束：清掉真言术残留的分步标记（正常在行动结束时已经清完）
func p_turn_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	_妖精攻击中 = false
	_真言压制阶段 = 0
	_真言伤阶段 = 0
	_真言行动中 = false
	return SUCCESS


## 命中②：守护灵（自己被主动攻击命中，先拆 1 个言灵、可再用 1 秘术补 1 张）；
## 妖精秘术给出的攻击命中则 +2【秘术】
func p_timeline_2_hit(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if _妖精攻击中 and int(harm.get("src", -1)) == player.id and bool(ctx.get("is_active", false)):
		player.add_token(秘术槽, 2)
		notice_skill(YAO_JING_MI_SHU, [player.id])
		engine._broadcast_game()
	if int(harm.get("dst", -1)) != player.id or not bool(ctx.get("is_active", false)):
		return SUCCESS
	if int(harm.get("src", -1)) < 0:
		return SUCCESS
	if _言灵数() == 0:
		return SUCCESS
	var 可补: bool = player.token_num(秘术槽) > 0 and not player.hand_cards.is_empty()
	if _守护灵阶段 == 0:
		_守护灵阶段 = 1
		if 可补:
			# 一个言灵 + 一张手牌，同一步选完（cover_need=1 / hand_need=1 走混选）
			询问(player.id, SHOU_HU_LING, 2, 0, GConst.CardSource.HandOrCover, [], 0, "", [], false,
				0, -1, [], -1, {}, 0, 0, false, [], true, -1, 1, "", -1, "", [], [], 0, 1)
		else:
			询问(player.id, SHOU_HU_LING, 1, 0, GConst.CardSource.Cover, [], 0, "", [], false,
				0, -1, [], -1, {})
		return WAIT
	_守护灵阶段 = 0
	var r: Dictionary = take_skill_reply_full()
	var 拆: int = -1
	var 补: int = -1
	for c: Variant in r.get("card_ids", []):
		var 盖实例: int = player.盖牌实例(int(c))
		if 盖实例 >= 0 and 拆 < 0:
			拆 = 盖实例
			continue
		var 手实例: int = player.手牌实例(int(c))
		if 手实例 >= 0 and 补 < 0:
			补 = 手实例
	if 拆 < 0:
		# 强制项：超时 / 空回复按言灵顺序补一个
		拆 = int(player.cover_cards[0])
	notice_skill(SHOU_HU_LING, [player.id])
	engine.remove_cover(player.id, [拆], player.id, SHOU_HU_LING)
	engine.to_discard([拆], {"owner": player.id, "source": "cover", "cause": SHOU_HU_LING})
	engine._log_discard(player.id, [拆], false)
	if 可补 and player.token_num(秘术槽) > 0:
		if 补 < 0:
			补 = int(player.hand_cards[0])
		player.remove_token(秘术槽, 1)
		# 这张手牌面朝上当作【言灵】摆出来：走统一入口（亮牌 + 触发封印 + 离手 + 进盖牌）
		engine.展示手牌进盖牌(player.id, [补], SHOU_HU_LING)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 禁忌秘法：回合开始前移 3 秘术 → 2 名角色各弃 1 张，弃牌作言灵
# ============================================================
func p_before_turn_begin(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	_妖精已用 = false
	_真言压制阶段 = 0
	if _禁忌阶段 == 2:
		return _禁忌弃牌推进()
	if _禁忌阶段 == 1:
		return _禁忌秘法()
	if player.token_num(秘术槽) < 3:
		return SUCCESS
	_禁忌阶段 = 1
	询问(player.id, JIN_JI_MI_FA, 0, 2, GConst.CardSource.Hand, [], 0, "", [], true,
		0, -1, 全部角色(), -1, {})
	return WAIT


func _禁忌秘法() -> int:
	var r: Dictionary = take_skill_reply_full()
	var dsts: Array = r.get("dst_ids", [])
	_禁忌阶段 = 0
	if dsts.is_empty():
		return SUCCESS
	if player.token_num(秘术槽) < 3:
		return SUCCESS
	var 选: Array = []
	for d: Variant in dsts:
		if engine.p(int(d)) != null and not 选.has(int(d)):
			选.append(int(d))
		if 选.size() >= 2:
			break
	if 选.size() < 2:
		engine.报错("【禁忌秘法】目标不足 2 名", player.id)
		return SUCCESS
	player.remove_token(秘术槽, 3)
	notice_skill(JIN_JI_MI_FA, 选)
	_禁忌弃牌 = []
	_禁忌目标 = 选
	_禁忌阶段 = 2
	return _禁忌弃牌推进()


## 两名目标依次由本人选 1 张牌弃掉（标准弃牌应答），弃牌再面朝上作为【言灵】
func _禁忌弃牌推进() -> int:
	while _禁忌弃牌.size() < _禁忌目标.size():
		var dp: BattlePlayer = engine.p(int(_禁忌目标[_禁忌弃牌.size()]))
		if dp == null:
			_禁忌弃牌.append({})
			continue
		if dp.hand_cards.is_empty():
			_禁忌弃牌.append({})
			continue
		if not engine.has_reply():
			engine.ask_respond(dp.id, GConst.RespondType.Discard, [dp.id, JIN_JI_MI_FA, 1], [dp.id])
			engine.wait_for(dp.id, GConst.Msg.Respond)
			return WAIT
		var r弃: Dictionary = take_skill_reply_full()
		var 弃: int = -1
		for c: Variant in r弃.get("card_ids", []):
			var 实例: int = dp.手牌实例(int(c))
			if 实例 >= 0:
				弃 = 实例
				break
		if 弃 < 0:
			for c0: int in dp.hand_cards:
				if dp.has_discard_card(c0):
					弃 = c0
					break
		if 弃 < 0:
			_禁忌弃牌.append({})
			continue
		engine.take_from_hand(dp.id, [弃])
		engine.to_discard([弃], {"owner": dp.id, "source": "hand", "cause": JIN_JI_MI_FA})
		engine._log_discard(dp.id, [弃])
		_禁忌弃牌.append({"pid": dp.id, "card": 弃})
	# 弃牌都进弃牌堆之后，把它们面朝上放到自己角色旁作为【言灵】
	# （允许超过盖牌上限：多出来的由引擎的盖牌超限询问让玩家自己弃，同魔弓【充能】）
	var 得: Array = []
	for 项: Dictionary in _禁忌弃牌:
		var cid: int = int(项.get("card", -1))
		if cid < 0:
			continue
		var 取回: int = engine.deck.取出实例(cid)
		if 取回 < 0:
			continue
		得.append(取回)
	_禁忌弃牌 = []
	_禁忌目标 = []
	_禁忌阶段 = 0
	if 得.is_empty():
		engine._broadcast_game()
		return SUCCESS
	engine.add_cover(player.id, 得, player.id, JIN_JI_MI_FA, true)
	# 注意：这两张是别人手里弃掉的牌（不是自己从手里展示出来的），
	# 封印类「从手中打出或展示出」不触发，所以走 展示牌（只广播、不压展示钩子）。
	engine.展示牌(player.id, 得)
	return SUCCESS


# ============================================================
# 工具
# ============================================================
func _言灵数() -> int:
	return player.cover_cards.size()


## 可当【真言术】素材的言灵（除光系外）。0 是合法实例号，判空只能用 < 0
func _可用言灵() -> Array:
	var out: Array = []
	for cid: int in player.cover_cards:
		var 牌: GCard = Data.get_card(cid)
		if 牌 == null:
			continue
		if 牌.element_enum() == GConst.CardElement.Light:
			continue
		out.append(cid)
	return out


## 手牌里与现存【言灵】系别相同的牌（言灵术「额外弃 1 张」的可选牌）
func _同系手牌() -> Array:
	var 系们: Array = []
	for cid: int in player.cover_cards:
		var 牌: GCard = Data.get_card(cid)
		if 牌 != null and not 系们.has(牌.element_enum()):
			系们.append(牌.element_enum())
	var out: Array = []
	for cid: int in player.hand_cards:
		var 牌: GCard = Data.get_card(cid)
		if 牌 != null and 系们.has(牌.element_enum()):
			out.append(cid)
	return out


func 全部角色() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		out.append(pid)
	return out
