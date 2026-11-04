extends BattleRole
## 阴阳师（roleID 33）—— 移植自服务端 role/YinYang.cpp
## 指示物：tokens[0] = 鬼火，上限见角色表
## 技能：式神咒束（3301，响应：队友被主动攻击时由自己代替其应战）※ 受限，见文末、
##       黑暗祭礼（3302，回合结束：鬼火达到上限时清空所有鬼火，对目标造成 2 点法术伤害）、
##       式神降临（3303，法术：弃 2 张同命格手牌 → +1 鬼火、横置进入式神形态、额外 +1 攻击行动）、
##       生命结界（3304，法术：耗 1 能量 → +1 鬼火，二选一：
##                 ① 目标队友 +1 宝石 +1 治疗，自己受 X 点法术伤害；
##                 ② 仅式神形态：弃 2 张同命格牌退出形态，目标队友弃 1 张牌）、
##       式神转换（3305，与阴阳转换同时发动：摸 1 张牌并额外 +1 鬼火）、
##       阴阳转换（3306，响应：应战后 +1 鬼火；仅式神形态下把这次反击伤害改为鬼火数并退出形态）
##
## 受限说明：
## - 式神咒束（3301）的「代替队友应战」改由引擎 BattlePlayer.reattacker 实现：把自己的 id
##   写入队友的 reattacker，引擎在该队友被攻击时改问自己是否应战；应战成功后原攻击对队友
##   判定为未命中，并由自己向攻击者发起反击（服务端 popGameState + setStateReattack 的
##   应战状态重排由本引擎自动完成）。
## - 阴阳转换（3306）的「同命格应战」由 v_reattack 实现：发动阴阳转换时不能用光系牌，
##   光系是格挡；不发动阴阳转换时，光系牌照常按普通格挡处理。

const SHI_SHEN_ZHOU_SHU: int = 3301
const HEI_AN_JI_LI: int = 3302
const SHI_SHEN_JIANG_LIN: int = 3303
const SHENG_MING_JIE_JIE: int = 3304
const SHI_SHEN_ZHUAN_HUAN: int = 3305
const YIN_YANG_ZHUAN_HUAN: int = 3306

const TOKEN_GUI_HUO: int = 0

## 阴阳转换已经选好、但还没选应战牌：选牌时放开同命格限制
var _yin_yang_pending: bool = false
## 本次攻击牌是无命格的虚拟牌（如欺诈）：阴阳转换无法匹配命格
var _yin_yang_attack_no_fate: bool = false
## 本次阴阳转换同时发动了式神转换（摸 1 张 + 再 +1 鬼火）
var _shi_shen_pending: bool = false
## 应战牌选好后，在真正打出这次应战时结算 +鬼火 / 摸牌 / 退出形态
var _apply_yin_yang_after_use: bool = false
## 式神咒束已经宣告、还没选应战牌：选牌成功后才扣战绩区能量
var _shi_shen_zhou_shu_pending: bool = false
## 式神咒束要保护的目标队友（宣告时记下，真正打出应战牌时才发技能通知）
var _shi_shen_zhou_shu_dst: int = -1
## 客户端攒操作时随 3301 应答带上来的 3306 选择（0＝没带，仍走普通询问）
var _yin_yang_choice: int = 0


func available_skills() -> Array:
	var out: Array = []
	# 式神降临要弃 2 张同命格牌：card_rule="same_fate_pattern" 让界面选第 1 张后只亮同命格的牌。
	# 已经是式神形态（横置）时不能再开，必须等重置回普通形态。
	out.append({"type": GConst.ActionType.MagicSkill, "id": SHI_SHEN_JIANG_LIN, "need_card": 2, "need_target": 0,
		"card_rule": "same_fate_pattern", "enabled": not player.tap and _has_same_fate_pattern_pair()})
	# 生命结界：两档效果；目标只能是队友。费用什么能量都行（水晶优先扣）。
	var 队友: Array[int] = ally_ids()
	out.append({"type": GConst.ActionType.MagicSkill, "id": SHENG_MING_JIE_JIE, "need_card": 0, "need_target": 1,
		"targets": 队友, "card_rule": "same_fate_pattern",
		"arg_choices": [
			{"text": GConst.按钮原文(SHENG_MING_JIE_JIE, 0), "args": [1],
				"enabled": player.get_energy() >= 1 and not 队友.is_empty()},
			{"text": GConst.按钮原文(SHENG_MING_JIE_JIE, 1), "args": [2], "need_card": 2,
				"enabled": player.tap and player.get_energy() >= 1 and _has_same_fate_pattern_pair()},
		],
		"enabled": player.get_energy() >= 1 and not 队友.is_empty()})
	return out


# ============================================================
# 指示物与工具
# ============================================================
func _gui_huo() -> int:
	var t: Dictionary = player.tokens[TOKEN_GUI_HUO]
	return int(t["num"])


func _gui_huo_max() -> int:
	return int(player.tokens[TOKEN_GUI_HUO]["max"])


func _set_gui_huo(v: int) -> void:
	var t: Dictionary = player.tokens[TOKEN_GUI_HUO]
	t["num"] = clampi(v, 0, int(t["max"]))


## 手牌中是否存在 2 张同命格的牌（式神降临的条件）
func _has_same_fate_pattern_pair() -> bool:
	for i: int in range(player.hand_cards.size()):
		var ci: GCard = Data.get_card(player.hand_cards[i])
		if ci == null:
			continue
		for j: int in range(i + 1, player.hand_cards.size()):
			var cj: GCard = Data.get_card(player.hand_cards[j])
			if cj != null and cj.fate_pattern_enum() == ci.fate_pattern_enum():
				return true
	return false


## 校验「2 张命格相同的手牌」：两张不同、都在手、命格相同。返回 GE_* 错误码。
## 式神降临和生命结界第二档共用，避免两边各写一套。
func _check_same_fate_pattern_pair(cards: Array) -> int:
	if cards.size() != 2:
		return GConst.GE_INVALID_CARDID
	var c0: int = int(cards[0])
	var c1: int = int(cards[1])
	if c0 == c1:
		return GConst.GE_INVALID_CARDID
	var a0: GCard = Data.get_card(c0)
	var a1: GCard = Data.get_card(c1)
	if a0 == null or a1 == null or a0.fate_pattern_enum() != a1.fate_pattern_enum():
		return GConst.GE_INVALID_CARDID
	if not player.has_hand_card(c0) or not player.has_hand_card(c1):
		return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


## 展示并弃掉自己手里的牌（客户端摊牌 + p_show_hand 钩子 + 弃牌日志）。
## 3303 / 3304 第二档共用；不负责最终的 _broadcast_game()。
func _展示并弃(cards: Array) -> void:
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": cards, "is_real": true,
	})
	_弃手牌(player.id, cards, true)


## 弃掉某人的手牌（展示 可选：走 p_show_hand 钩子）；不负责广播快照。
func _弃手牌(pid: int, cards: Array, 展示: bool = false) -> void:
	engine.take_from_hand(pid, cards, 展示)
	engine.to_discard(cards, {"owner": pid, "source": "hand"})
	engine._log_discard(pid, cards)


# ============================================================
# 攻击宣告（timeline_1 之前）：阴阳转换（3306）与应战伤害变化
# ============================================================
func p_attacked(ctx: Dictionary) -> int:
	var src_id: int = int(ctx.get("src", -1))
	var dst_id: int = int(ctx.get("dst", -1))
	# 自己被攻击：先问阴阳转换
	if dst_id == player.id:
		return _yin_yang_zhuan_huan(ctx)
	# 队友被攻击、自己已经用式神咒束代替他应战：接着问阴阳转换
	var dst: BattlePlayer = engine.p(dst_id)
	if dst != null and dst.reattacker == player.id:
		return _yin_yang_zhuan_huan(ctx)
	# 自己应战打出的这次反击：此时应战牌已经打出，结算 +鬼火 / 摸牌 / 退出形态
	var harm: Dictionary = ctx.get("harm", {})
	if src_id == player.id and _apply_yin_yang_after_use and bool(harm.get("reattack", false)):
		_结算阴阳转换后效(harm)
	return SUCCESS


## 阴阳转换（3306）：客户端把效果、应战牌、反击目标放在同一条应答里一起提交；
## 这里把牌 / 目标预置给引擎紧接着的应战询问，玩家不必再被问第二次。
## 式神咒束那条链会在 3301 的应答里带上 3306 的选择（_yin_yang_choice），此时直接结算。
func _yin_yang_zhuan_huan(ctx: Dictionary) -> int:
	if int(ctx.get("hit_rate", GConst.HitRate.Normal)) != GConst.HitRate.Normal:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	var atk_id: int = int(ctx.get("card_id", -1))
	var harm: Dictionary = ctx.get("harm", {})
	# 欺诈虚牌无命格：阴阳转换要求同命格，不能匹配
	var 无命格: bool = bool(harm.get("virtual_no_fate", false))
	_yin_yang_attack_no_fate = 无命格
	if _yin_yang_choice > 0:
		var 已选: int = _yin_yang_choice
		_yin_yang_choice = 0
		step = STEP_DONE
		if not 无命格:
			_应用阴阳转换选择(已选)
		return SUCCESS
	# 即便手里没有同系 / 同命格牌，也照样询问（三档全部置灰）：
	# 不询问会让对手从「没弹询问」直接推断出阴阳师手里没有对应牌。
	var 可阴阳: bool = not 无命格 and _has_same_fate_pattern_attack(atk_id)
	# 【圣光】也能算「仅应战」：手里没有同系攻击牌、但能用圣光抵挡时，仍要给玩家这一档，
	# 否则他只能先取消、再等引擎的普通应战询问，又变回两步操作。
	var 可圣光: bool = bool(ctx.get("can_light", true)) and _has_holy_light()
	var 有基础应战: bool = _has_base_reattack_card(atk_id) or 可圣光
	# 提示里的「受到 N 伤害攻击」：自己挨打和替队友挡都用本次攻击的同一个伤害。
	var 预览伤害: int = engine._应战提示伤害(int(ctx.get("src", -1)), ctx, harm)
	if not engine.has_reply():
		# 三档始终都摆出来：本次用不了的那档由 enabled=false 置灰（对照其他技能的 option_enabled），
		# 不能直接省略——否则玩家会以为这套技能少了一档。
		询问(player.id, YIN_YANG_ZHUAN_HUAN, 0, 0, GConst.CardSource.Hand,
			_阴阳转换选项(有基础应战, 可阴阳),
			0, "", [], true, 0, -1, [], -1, {},
			atk_id, 0, false, [int(ctx.get("src", -1))], bool(ctx.get("can_light", true)), 预览伤害)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	# 客户端攒操作：应战牌 / 反击目标随 3306 的应答一起上来，先预置给引擎紧接着的应战询问，
	# 这样玩家只选一次（点效果 → 选牌选目标 → 确定），不再被第二次询问打断。
	_预置应战答复(r)
	var args: Array = r.get("args", [])
	var choice: int = int(args[0]) if not args.is_empty() else 0
	# 自己被攻击时取消（或超时）＝放弃整次应战：仅应战已经在选项里了，
	# 不需要再回退到普通应战询问让玩家取消第二次。预置一个「放弃」答复给引擎直接消费。
	# 替队友应战的取消不这样做——那时回退普通询问还要继续替队友挡。
	if choice <= 0 and int(ctx.get("dst", -1)) == player.id:
		engine.prepare_reply(player.id, {
			"respond_id": GConst.RespondType.ReplyAttack,
			"args": [GConst.Reattack.GiveUp],
			"card_ids": [],
			"dst_ids": [],
		})
		return SUCCESS
	# 选择 1（仅应战）不发动阴阳转换；替队友应战时的取消也走到这里（回退普通询问继续替队友挡）
	if choice <= 1:
		return SUCCESS
	# 先记下选择；应战牌选好、真正打出后再加鬼火 / 摸牌 / 退出形态
	_应用阴阳转换选择(choice)
	return SUCCESS


## 3306 / 3301 共用的三档选项：仅应战 / 阴阳转换 / 阴阳转换+式神转换。
## 本次用不了的那档也返回（enabled=false），客户端按其他技能的 option_enabled 置灰显示。
func _阴阳转换选项(有基础应战: bool, 可阴阳: bool) -> Array:
	return [
		{"value": 1, "label": "仅应战", "enabled": 有基础应战},
		{"value": 2, "label": GConst.文本("提示_阴阳转换_应战转换"), "enabled": 可阴阳},
		{"value": 3, "label": GConst.文本("提示_阴阳转换_再次转换"), "enabled": 可阴阳},
	]


## 记录本次 3306 的选择；真正 +鬼火 / 摸牌 / 改伤害在应战牌打出后结算（_结算阴阳转换后效）。
func _应用阴阳转换选择(选择: int) -> void:
	# 无命格的虚牌不能匹配阴阳转换；即使客户端硬提交也忽略
	if 选择 >= 2 and not _yin_yang_attack_no_fate:
		_yin_yang_pending = true
		_shi_shen_pending = 选择 > 2
		engine._broadcast_game()


## 应战牌已经打出：按“先应战，再加鬼火，再退出形态”的顺序结算
func _结算阴阳转换后效(harm: Dictionary) -> void:
	notice_skill(YIN_YANG_ZHUAN_HUAN, [player.id])
	# 先记下应战时是否处于式神形态：只有式神形态下才是「本次攻击伤害为 X（鬼火数）」，
	# 并且才「重置脱离式神形态」；普通形态只加鬼火，不改伤害、也不退出形态。
	var 在式神形态: bool = player.tap
	_set_gui_huo(_gui_huo() + 1)
	if _shi_shen_pending:
		notice_skill(SHI_SHEN_ZHUAN_HUAN, [player.id])
		# 【强制】摸 1 张：走标准摸牌流程（先跑摸牌前响应，再摸进手牌），
		# 和项目里其它摸牌保持一致。
		engine.push_draw(player.id, 1, SHI_SHEN_ZHUAN_HUAN)
		_set_gui_huo(_gui_huo() + 1)
	if 在式神形态:
		harm["point"] = _gui_huo()
		player.tap = false
	_apply_yin_yang_after_use = false
	_yin_yang_pending = false
	_yin_yang_attack_no_fate = false
	_shi_shen_pending = false
	_shi_shen_zhou_shu_pending = false
	_shi_shen_zhou_shu_dst = -1
	_yin_yang_choice = 0
	engine._broadcast_game()


## 把客户端随 3306 应答一起带上来的应战牌 / 反击目标，预置成引擎下一次应战询问的答复。
## 带【圣光】时按「抵挡」提交（不需要反击目标）；带攻击牌时按「应战」提交，必须有反击目标。
func _预置应战答复(r: Dictionary) -> void:
	var 牌组: Array = r.get("card_ids", [])
	if 牌组.is_empty():
		return
	var 牌号: int = int(牌组[0])
	var 牌: GCard = Data.get_card(牌号)
	if 牌 == null:
		return
	var 打法: int = GConst.Reattack.Block if 牌.card_name_enum() == GConst.CardName.HolyLight \
			else GConst.Reattack.Attack
	var 目标组: Array = r.get("dst_ids", [])
	var 目标: Array = [int(目标组[0])] if not 目标组.is_empty() else []
	if 打法 == GConst.Reattack.Attack and 目标.is_empty():
		return
	engine.prepare_reply(player.id, {
		"respond_id": GConst.RespondType.ReplyAttack,
		"args": [打法],
		"card_ids": [牌号],
		"dst_ids": 目标,
	})


## 手里有没有【圣光】（可以作抵挡）
func _has_holy_light() -> bool:
	for cid: int in player.hand_cards:
		var card: GCard = Data.get_card(cid)
		if card != null and card.card_name_enum() == GConst.CardName.HolyLight:
			return true
	return false


# ============================================================
# 应战校验覆写：阴阳转换（3306）放宽应战牌要求
# ============================================================
func v_reattack(card_id: int, attack_card_id: int) -> int:
	if _yin_yang_pending:
		# 无命格的虚牌不能匹配阴阳转换
		if _yin_yang_attack_no_fate:
			return GConst.GE_INVALID_CARDID
		if not player.has_hand_card(card_id):
			return GConst.GE_INVALID_CARDID
		var card: GCard = Data.get_card(card_id)
		var atk: GCard = Data.get_card(attack_card_id)
		if not GCard.可阴阳应战(card, atk):
			return GConst.GE_INVALID_CARDID
		return GConst.GE_SUCCESS
	return player.base_v_reattack(card_id, attack_card_id)


# ============================================================
# 应战牌选好后
# - 式神咒束：到这一步才扣战绩区能量
# - 阴阳转换：记下“打出后结算”，不在这里提前退出形态
# - 普通光系牌：视作格挡（不进行阴阳转换时的正常用法）
# ============================================================
func p_reattack(ctx: Dictionary) -> int:
	if int(ctx.get("doer", -1)) != player.id:
		return SUCCESS
	# 式神咒束的代价：选好合法应战牌后才扣，取消选牌不会白付
	if _shi_shen_zhou_shu_pending:
		if _can_pay_shi_shen_cost():
			_pay_shi_shen_cost()
			notice_skill(SHI_SHEN_ZHOU_SHU, [_shi_shen_zhou_shu_dst] if _shi_shen_zhou_shu_dst >= 0 else [])
		_shi_shen_zhou_shu_pending = false
		_shi_shen_zhou_shu_dst = -1
	var c: GCard = Data.get_card(int(ctx.get("card_id", -1)))
	if _yin_yang_pending:
		# 光系牌在 v_reattack 已被挡掉；真走到这里就按普通格挡处理，不发动阴阳转换
		if c != null and c.element_enum() != GConst.CardElement.Light:
			_apply_yin_yang_after_use = true
			return SUCCESS
		_yin_yang_pending = false
		_shi_shen_pending = false
	if c != null and c.element_enum() == GConst.CardElement.Light:
		ctx["block"] = true
		ctx["real"] = true
	return SUCCESS


## 原攻击命中＝应战没成立（取消选牌 / 放弃）：清掉还没结算的待办，别留到下一次攻击
func p_timeline_2_hit(_ctx: Dictionary) -> int:
	_清空应战待办()
	return SUCCESS


func p_timeline_2_miss(_ctx: Dictionary) -> int:
	# 应战成功时原攻击会走 miss，此时 _apply_yin_yang_after_use 已置位，不能清
	if not _apply_yin_yang_after_use:
		_清空应战待办()
	return SUCCESS


func p_before_turn_begin(_ctx: Dictionary) -> int:
	_清空应战待办()
	return SUCCESS


func _清空应战待办() -> void:
	_yin_yang_pending = false
	_yin_yang_attack_no_fate = false
	_shi_shen_pending = false
	_apply_yin_yang_after_use = false
	_shi_shen_zhou_shu_pending = false
	_shi_shen_zhou_shu_dst = -1
	_yin_yang_choice = 0


# ============================================================
# 攻击应战阶段：式神咒束（3301）
# 对应服务端 YinYang::p_attacked 的式神咒束分支 + ShiShenZhouShu：
# 队友被主动攻击时，由自己代替其应战；三档效果（仅应战 / 阴阳转换 / 阴阳转换+式神转换）
# 与直接 3306 共用选项和后续结算。
# ============================================================
func p_timeline_1(ctx: Dictionary) -> int:
	if step >= STEP_DONE:
		return SUCCESS
	# 仅「队友被主动攻击」时发动（不含自己、不含由应战发起的反击）
	var dst_id: int = int(ctx.get("dst", -1))
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	if not ally_ids().has(dst_id):
		return SUCCESS
	var dst: BattlePlayer = engine.p(dst_id)
	# 须处于式神形态，且命中率为普通。即便手里没有合法应战牌也照样询问（三档全部置灰），
	# 避免对手从「没弹询问」推断出阴阳师手里没有对应牌。
	# 替队友应战时不能用【圣光】帮队友抵挡，所以「仅应战」只认普通攻击牌 / 同命格攻击牌。
	if not player.tap:
		return SUCCESS
	if int(ctx.get("hit_rate", GConst.HitRate.Normal)) != GConst.HitRate.Normal:
		return SUCCESS
	var atk_id: int = int(ctx.get("card_id", -1))
	if not _can_pay_shi_shen_cost():
		return SUCCESS
	# 替队友挡时也把这次攻击的伤害带给客户端，提示里才能写「受到 N 伤害攻击」
	var harm: Dictionary = ctx.get("harm", {})
	# 欺诈虚牌无命格：阴阳转换要求同命格，不能匹配
	var 无命格: bool = bool(harm.get("virtual_no_fate", false))
	_yin_yang_attack_no_fate = 无命格
	var 预览伤害: int = engine._应战提示伤害(int(ctx.get("src", -1)), ctx, harm)
	if not engine.has_reply():
		# 和直接 3306 用同一张三档选项：仅应战 / 阴阳转换 / 阴阳转换+式神转换。
		# 用不了的档同样置灰显示；同时把本次攻击牌和攻击者带给客户端。
		# 可圣光传 false：3301 这条不能用圣光抵挡，客户端据此把【圣光】置灰。
		询问(player.id, SHI_SHEN_ZHOU_SHU, 0, 0, GConst.CardSource.Hand,
			_阴阳转换选项(_has_base_reattack_card(atk_id),
				not 无命格 and _has_same_fate_pattern_attack(atk_id)),
			0, "", [], true, 0, -1, [], -1, {},
			atk_id, 0, false, [int(ctx.get("src", -1))], false, 预览伤害)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	var choice: int = int(args[0]) if not args.is_empty() else 0
	if choice <= 0:
		step = STEP_DONE
		return SUCCESS
	# 式神咒束只能用攻击牌应战，替队友挡不能出圣光：把本次攻击的 can_light 关掉，
	# 后续应战询问 / 格挡判定与客户端保持同一口径。
	ctx["can_light"] = false
	# 客户端攒操作时 args[1] 是 3306 已经选好的效果；没带就仍由 p_attacked 再问
	var 阴阳选择: int = int(args[1]) if args.size() > 1 else 0
	# 无命格虚牌：选项 2/3 已置灰，硬提交也忽略
	if 阴阳选择 > 0 and not _yin_yang_attack_no_fate:
		_yin_yang_choice = 阴阳选择
	# 客户端把应战牌和反击目标也一起攒上来了：与直接 3306 共用同一套预置逻辑
	_预置应战答复(r)
	# 由自己代替队友应战；技能通知与代价都等应战牌真正打出后再结算（见 p_reattack）
	dst.reattacker = player.id
	_shi_shen_zhou_shu_pending = true
	_shi_shen_zhou_shu_dst = dst.id
	# 让同一回合的 p_attacked 还能接着问阴阳转换
	step = 0
	engine._broadcast_game()
	return SUCCESS


## 普通应战牌（同系 / 暗系）是否存在
func _has_base_reattack_card(attack_card_id: int) -> bool:
	for cid: int in player.hand_cards:
		if player.base_v_reattack(cid, attack_card_id) == GConst.GE_SUCCESS:
			return true
	return false


## 同命格攻击牌是否存在（阴阳转换用；光系不算，暗系攻击本身不可应战）
func _has_same_fate_pattern_attack(attack_card_id: int) -> bool:
	var atk: GCard = Data.get_card(attack_card_id)
	if atk == null or atk.element_enum() == GConst.CardElement.Darkness:
		return false
	for cid: int in player.hand_cards:
		if GCard.可阴阳应战(Data.get_card(cid), atk):
			return true
	return false


## 式神咒束的代价可否支付（战绩区）：1 水晶 + 1 宝石，或 2 宝石
func _can_pay_shi_shen_cost() -> bool:
	var c: int = player.color
	return engine.team_gem[c] > 0 and engine.team_energy(c) > 1


func _pay_shi_shen_cost() -> void:
	var c: int = player.color
	if engine.team_crystal[c] > 0:
		engine.set_team_crystal(c, engine.team_crystal[c] - 1)
		engine.set_team_gem(c, engine.team_gem[c] - 1)
	else:
		engine.set_team_gem(c, engine.team_gem[c] - 2)


# ============================================================
# 回合结束：黑暗祭礼（3302）
# ============================================================
## 【黑暗祭礼】的推进阶段（0＝还没开始 / HEI_AN_JI_LI＝等选目标）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨一次询问。
## 鬼火等选完目标后才清空；询问不能取消，超时由引擎自动选一名敌人。
var _ji_li_step: int = 0


func p_turn_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	# 本次黑暗祭礼已结算：URGENT 回来后引擎会用同一 ctx 再进本钩子，直接挡掉，别重复询问/重复伤害
	if bool(ctx.get("ji_li_settled", false)):
		return SUCCESS
	if _ji_li_step >= STEP_DONE:
		return SUCCESS
	if _ji_li_step == 0:
		if _gui_huo() < _gui_huo_max():
			return SUCCESS
		_ji_li_step = HEI_AN_JI_LI
	if _ji_li_step == HEI_AN_JI_LI:
		if not engine.has_reply():
			# 只选目标，没有别的选项；不能取消，超时由引擎从敌方里自动选一个目标
			询问(player.id, HEI_AN_JI_LI, 0, 1, GConst.CardSource.Hand, [], 0, "", [], false)
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		_ji_li_step = 0
		# 标记本次已结算，挡住 URGENT 回来时的重入（同一 ctx）
		ctx["ji_li_settled"] = true
		var dsts: Array = r.get("dst_ids", [])
		var dst_id: int = int(dsts[0]) if not dsts.is_empty() else -1
		if engine.p(dst_id) == null:
			dst_id = _随机敌人()
		if dst_id < 0:
			dst_id = player.id
		# 选完目标后才清空鬼火，再打目标 2 点法术伤害
		_set_gui_huo(0)
		notice_skill(HEI_AN_JI_LI, [dst_id])
		engine.push_harm({
			"src": player.id, "dst": dst_id, "point": 2,
			"cause": HEI_AN_JI_LI, "type": GConst.HarmType.Magic,
		})
		engine._broadcast_game()
		return URGENT
	return SUCCESS


## 黑暗祭礼超时兜底：随机一名敌人；没有敌人返回 -1
func _随机敌人() -> int:
	var ids: Array[int] = enemy_ids()
	return int(ids.pick_random()) if not ids.is_empty() else -1


# ============================================================
# 生命结界（3304）：满鬼火时该次自伤不造成我方士气下降
# 服务端据 con->harm.cause == 3304 && 鬼火 == 3 判定（YinYang::p_before_lose_morale）；
# 引擎 lose_morale 的 ctx 提供「harm_cause」（最近一次伤害的 cause），故据此判定
# ============================================================
func p_before_lose_morale(ctx: Dictionary) -> int:
	if int(ctx.get("dst", -1)) != player.id:
		return SUCCESS
	if int(ctx.get("harm_cause", 0)) != SHENG_MING_JIE_JIE:
		return SUCCESS
	if _gui_huo() != _gui_huo_max():
		return SUCCESS
	ctx["amount"] = 0
	return SUCCESS


# ============================================================
# 主动法术技能
# ============================================================
func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	var aid: int = int(action.get("action_id", 0))
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	match aid:
		SHI_SHEN_JIANG_LIN:
			# 已经是式神形态时不能再开
			if player.tap:
				return GConst.GE_INVALID_ACTION
			var 降临错误: int = _check_same_fate_pattern_pair(cards)
			if 降临错误 != GConst.GE_SUCCESS:
				return 降临错误
		SHENG_MING_JIE_JIE:
			if player.get_energy() < 1:
				return GConst.GE_INVALID_ACTION
			if dsts.size() != 1:
				return GConst.GE_INVALID_ACTION
			var dst: BattlePlayer = engine.p(int(dsts[0]))
			# 目标只能是队友（不含自己）
			if dst == null or not ally_ids().has(dst.id):
				return GConst.GE_INVALID_PLAYERID
			var args: Array = action.get("args", [])
			var opt: int = int(args[0]) if not args.is_empty() else 1
			if opt == 2:
				if not player.tap:
					return GConst.GE_INVALID_CARDID
				var 结界错误: int = _check_same_fate_pattern_pair(cards)
				if 结界错误 != GConst.GE_SUCCESS:
					return 结界错误
			elif opt != 1:
				return GConst.GE_INVALID_ARGUMENT
		_:
			return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	match int(action.get("action_id", 0)):
		SHI_SHEN_JIANG_LIN:
			return _shi_shen_jiang_lin(action)
		SHENG_MING_JIE_JIE:
			return _sheng_ming_jie_jie(action)
	return GConst.GE_INVALID_ACTION


## 式神降临：弃 2 张同命格手牌 → +1 鬼火、横置、额外 +1 攻击行动
func _shi_shen_jiang_lin(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var use_cards: Array = [int(cards[0]), int(cards[1])]
	notice_skill(SHI_SHEN_JIANG_LIN, [player.id])
	_set_gui_huo(_gui_huo() + 1)
	player.add_action(GConst.ActionType.Attack, SHI_SHEN_JIANG_LIN, true, true)
	engine.set_tap(player.id, true)
	_展示并弃(use_cards)
	engine._broadcast_game()
	return URGENT


## 生命结界第二档：目标队友弃 1 张牌（等这一步跨一次询问）
var _sheng_ming_step: int = 0
var _sheng_ming_dst: int = -1


## 生命结界：耗 1 能量 → +1 鬼火，然后二选一：
##   1. 目标队友 +1 宝石 +1 治疗；自己受 X 点法术伤害
##   2. 仅式神形态：弃 2 张同命格牌【展示】，重置脱离形态；目标队友弃 1 张牌
func _sheng_ming_jie_jie(action: Dictionary) -> int:
	if _sheng_ming_step != 0:
		# 第二档：等目标队友弃牌
		var back: Dictionary = take_skill_reply_full()
		var want_ids: Array = back.get("card_ids", [])
		var victim: BattlePlayer = engine.p(_sheng_ming_dst)
		var chosen: Array = []
		if victim != null:
			for cid: Variant in want_ids:
				var id: int = int(cid)
				# 弃手牌只认真手牌（盖牌可当手牌，但不能用来弃）
				if victim.has_discard_card(id) and not chosen.has(id):
					chosen.append(id)
					if chosen.size() >= 1:
						break
			if chosen.is_empty() and not victim.hand_cards.is_empty():
				chosen.append(int(victim.hand_cards[0]))
			if not chosen.is_empty():
				_弃手牌(victim.id, chosen)
		_sheng_ming_step = 0
		_sheng_ming_dst = -1
		engine._broadcast_game()
		return URGENT

	var dsts: Array = action.get("dst_ids", [])
	var dst_id: int = int(dsts[0])
	var dst: BattlePlayer = engine.p(dst_id)
	var args: Array = action.get("args", [])
	var opt: int = int(args[0]) if not args.is_empty() else 1
	# 费用：什么能量都行，水晶优先
	player.remove_energy(1)
	notice_skill(SHENG_MING_JIE_JIE, [dst_id])
	_set_gui_huo(_gui_huo() + 1)

	if opt == 2:
		# 方案二：弃 2 张同命格牌，退出式神形态，再让目标队友弃 1 张
		var cards: Array = action.get("card_ids", [])
		var use_cards: Array = [int(cards[0]), int(cards[1])]
		_展示并弃(use_cards)
		if player.tap:
			player.tap = false
		if dst != null and not dst.hand_cards.is_empty():
			_sheng_ming_step = 1
			_sheng_ming_dst = dst.id
			engine.ask_skill(dst.id, SHENG_MING_JIE_JIE, 1, 0, GConst.CardSource.Hand,
				[], 0, "", [], false, 提示原文(SHENG_MING_JIE_JIE, 2, {"n": 1}))
			engine._broadcast_game()
			return WAIT
		engine._broadcast_game()
		return URGENT

	# 方案一：目标队友 +1 宝石 +1 治疗；自己受 X 点法术伤害
	if dst != null:
		dst.set_gem(dst.gem + 1)
		施加治疗(dst.id, 1)
	var point: int = _gui_huo()
	engine.push_harm({
		"src": player.id, "dst": player.id, "point": point,
		"cause": SHENG_MING_JIE_JIE, "type": GConst.HarmType.Magic,
	})
	engine._broadcast_game()
	return URGENT
