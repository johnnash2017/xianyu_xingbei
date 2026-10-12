extends BattleRole
## 魔枪（roleID 29）—— 移植自服务端 role/MoQiang.cpp
## 形态：tap = [幻影形态]（暗之解放进入，幻影星辰解除；形态下手牌上限恒定为 5，解除后恢复 6）
## 技能：暗之解放（2901，启动：转[幻影形态]，本回合下次主动攻击伤害 +1；
##                 不能发动漆黑之枪和充盈）、
##       幻影星辰（2902，启动：仅[幻影形态]下，对自身 2 点法术伤害并脱离[幻影形态]；
##                 若没有因此造成士气下降，则对目标角色 2 点法术伤害）、
##       黑暗束缚（2903，被动：你始终不能使用法术牌，由 v_allow_action / v_missile / v_shield / v_weaken /
##                  v_block / v_remissile 覆写实现）、
##       暗之障壁（2904，响应：任何人对你造成伤害时，二选一：弃 X 张法术牌 或 弃 X 张雷系牌[展示]）、
##       充盈（2905，法术：弃 1 张法术牌或雷系牌[展示]，所有人各弃 1 张牌，
##             除你以外每有人弃法术牌或雷系牌则本回合下次主动攻击伤害 +1，额外 +1 攻击行动）、
##       漆黑之枪（2906，响应：仅[幻影形态]下，主动攻击命中手牌 1~2 的对手后，
##                 耗 X 能量，本次攻击伤害 +(X+2)）

const AN_ZHI_JIE_FANG: int = 2901
const HUAN_YING_XING_CHEN: int = 2902
const HEI_AN_SHU_FU: int = 2903
const AN_ZHI_ZHANG_BI: int = 2904
const CHONG_YING: int = 2905
const QI_HEI_ZHI_QIANG: int = 2906

const HAND_MAX_ILLUSION: int = 5
const HAND_MAX_NORMAL: int = 6

var card_count: int = 0
var hurt_id: int = -1
var using_an_zhi_jie_fang: bool = false
var using_huan_ying_xing_chen: bool = false
var availabel_qi_hei_zhi_qiang: bool = true
var availabel_chong_ying: bool = true
var used_chong_ying: bool = false
var used_an_zhi_jie_fang: bool = false
## 幻影星辰本次自伤是否已造成士气下降（服务端 p_true_lose_morale 置位 HuanYingXingChenEffectFlag：
## 置位则不再对目标追加 2 点法术伤害）；引擎 lose_morale 的 ctx 提供 harm_cause，故按该字段判定
var huan_ying_morale_lost: bool = false
## 充盈询问目标与游标（跨 WAIT 重入保留）
var _chong_targets: Array[int] = []
var _chong_index: int = 0


func p_before_turn_begin(_ctx: Dictionary) -> int:
	card_count = 0
	using_an_zhi_jie_fang = false
	using_huan_ying_xing_chen = false
	availabel_qi_hei_zhi_qiang = true
	availabel_chong_ying = true
	used_chong_ying = false
	used_an_zhi_jie_fang = false
	huan_ying_morale_lost = false
	hurt_id = -1
	return SUCCESS


func available_skills() -> Array:
	var out: Array = []
	# 黑暗束缚：始终不能使用法术牌（服务端 v_allow_action 整类驳回，见文件末尾；客户端据此置灰）
	# 暗之解放后本回合不能发动充盈
	if availabel_chong_ying and (_hand_has_thunder() or _hand_has_magic()):
		# 充盈要弃 1 张法术牌或雷系牌：只让这些牌可点（v_magic_skill 校验同一条）
		out.append({"type": GConst.ActionType.MagicSkill, "id": CHONG_YING, "need_card": 1, "need_target": 0,
			"cards": hand_ids_where(func(_cid: int, c: GCard) -> bool:
				return c.is_magic() or c.element_enum() == GConst.CardElement.Thunder)})
	# 启动（由 is_free_skill 认可）：按当前形态只给对应的那一条，避免出现不可发动的那项
	# （每回合只能发动一个启动技能由引擎统一过滤，这里不重复判）
	if not player.tap:
		# 未横置：[暗之解放]
		out.append({"type": GConst.ActionType.SpecialSkill, "id": AN_ZHI_JIE_FANG,
			"need_card": 0, "need_target": 0})
	else:
		# 横置[幻影形态]：[幻影星辰]，须选 1 名对手为追加伤害目标
		out.append({"type": GConst.ActionType.SpecialSkill, "id": HUAN_YING_XING_CHEN,
			"need_card": 0, "need_target": 1, "targets": enemy_ids()})
	return out


## 【暗之解放】【幻影星辰】为「启动」：不消耗本回合行动，发动后行动阶段照旧继续
func is_free_skill(skill_id: int) -> bool:
	return skill_id == AN_ZHI_JIE_FANG or skill_id == HUAN_YING_XING_CHEN


# ============================================================
# 牌类校验覆写（对照服务端 MoQiang.cpp）
# 【黑暗束缚】（2903）：你始终不能使用法术牌——
#   · 整类「法术」行动由 v_allow_action 一律驳回（法术技能如【充盈】走 ActionType.MagicSkill，不受影响）；
#   · v_missile / v_shield / v_weaken 另行堵住「魔弹 / 圣盾 / 虚弱」这三张牌自己的校验路径；
#   · v_block / v_remissile 禁止用【圣光】格挡攻击、反【魔弹】。
# 对照参考客户端 MoQiang::normal() 的 handArea->disableMagic()：魔枪手里的【法术牌】平时整片置灰，
# 客户端那份名单见 battle_mobile 的 行动阶段禁用法术牌角色。
# ============================================================
## 【黑暗束缚】（2903）：整类「法术」行动直接禁掉（中毒等其它法术牌也不再漏放）
func v_allow_action(action_type: int, _args: Array, _allow: int, _can_give_up: bool) -> int:
	if action_type != GConst.ActionType.Magic:
		return V_NOT_OVERRIDE
	return GConst.GE_INVALID_ACTION


func v_missile(_card_id: int, _dst_id: int) -> int:
	return GConst.GE_INVALID_CARDID


func v_shield(_dst_id: int, _players: Dictionary) -> int:
	return GConst.GE_INVALID_CARDID


func v_weaken(_dst_id: int, _players: Dictionary) -> int:
	return GConst.GE_INVALID_CARDID


## 不能使用【圣光】格挡
func v_block(_card_id: int) -> int:
	return GConst.GE_INVALID_CARDID


## 不能响应【魔弹】（转弹）
func v_remissile(_card_id: int) -> int:
	return GConst.GE_INVALID_CARDID


# ============================================================
# 启动技能（行动阶段按钮）：暗之解放（2901）/ 幻影星辰（2902）
# （「每回合只能发动一个启动技能」由引擎统一把关，这里只校验各技能自己的条件）
# ============================================================
func v_special_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	match int(action.get("action_id", 0)):
		AN_ZHI_JIE_FANG:
			# 已在[幻影形态]（横置）中：不能再发动暗之解放
			if player.tap:
				return GConst.GE_INVALID_ACTION
		HUAN_YING_XING_CHEN:
			# 仅[幻影形态]（横置）下可发动，且必须指定一名对手作为追加伤害目标
			if not player.tap:
				return GConst.GE_INVALID_ACTION
			var dsts: Array = action.get("dst_ids", [])
			if dsts.is_empty():
				return GConst.GE_INVALID_ARGUMENT
			if not enemy_ids().has(int(dsts[0])):
				return GConst.GE_INVALID_PLAYERID
		_:
			return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_special_skill(action: Dictionary) -> int:
	match int(action.get("action_id", 0)):
		AN_ZHI_JIE_FANG:
			_apply_an_zhi_jie_fang()
		HUAN_YING_XING_CHEN:
			return _apply_huan_ying_xing_chen(action)
	return SUCCESS


## 暗之解放：转[幻影形态]，手牌上限 5；本回合下次主动攻击 +1，禁用漆黑之枪与充盈
func _apply_an_zhi_jie_fang() -> void:
	notice_skill(AN_ZHI_JIE_FANG, [player.id])
	player.boot_skill_used = true
	using_an_zhi_jie_fang = true
	availabel_qi_hei_zhi_qiang = false
	availabel_chong_ying = false
	engine.set_tap(player.id, true)
	player.hand_cards_max = HAND_MAX_ILLUSION
	engine._broadcast_game()


## 幻影星辰：对自身 2 点法术伤害（脱离[幻影形态]与追加伤害见 p_harm_end）
func _apply_huan_ying_xing_chen(action: Dictionary) -> int:
	var dsts: Array = action.get("dst_ids", [])
	var dst_id: int = int(dsts[0])
	notice_skill(HUAN_YING_XING_CHEN, [dst_id])
	player.boot_skill_used = true
	hurt_id = dst_id
	using_huan_ying_xing_chen = true
	huan_ying_morale_lost = false
	engine.push_harm({
		"src": player.id, "dst": player.id, "point": 2,
		"cause": HUAN_YING_XING_CHEN, "type": GConst.HarmType.Magic,
	})
	engine._broadcast_game()
	return URGENT


## 幻影星辰：因该技能自伤造成士气下降时置位（服务端 MoQiang::p_true_lose_morale）
## 引擎 lose_morale 的 ctx 提供「harm_cause」（最近一次伤害的 cause），据此识别本次自伤
func p_true_lose_morale(ctx: Dictionary) -> int:
	if int(ctx.get("dst", -1)) != player.id:
		return SUCCESS
	if int(ctx.get("amount", 0)) < 1:
		return SUCCESS
	if not using_huan_ying_xing_chen:
		return SUCCESS
	if int(ctx.get("harm_cause", 0)) != HUAN_YING_XING_CHEN:
		return SUCCESS
	huan_ying_morale_lost = true
	return SUCCESS


## 幻影星辰自伤结算完成（p_harm_end 在整条伤害流水线末尾触发）：脱离[幻影形态]、恢复手牌上限；
## 若自伤未造成士气下降，则再对目标角色 2 点法术伤害
func p_harm_end(ctx: Dictionary) -> int:
	if not using_huan_ying_xing_chen:
		return SUCCESS
	if int(ctx.get("dst", -1)) != player.id:
		return SUCCESS
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("cause", -1)) != HUAN_YING_XING_CHEN:
		return SUCCESS
	# 脱离[幻影形态]
	using_huan_ying_xing_chen = false
	player.tap = false
	player.hand_cards_max = HAND_MAX_NORMAL
	var morale_lost: bool = huan_ying_morale_lost
	huan_ying_morale_lost = false
	var dst_id: int = hurt_id
	hurt_id = -1
	engine._broadcast_game()
	if morale_lost:
		# 自伤已造成士气下降：不追加伤害
		return SUCCESS
	engine.push_harm({
		"src": player.id, "dst": dst_id, "point": 2,
		"cause": HUAN_YING_XING_CHEN, "type": GConst.HarmType.Magic,
	})
	engine._broadcast_game()
	return URGENT


## 【暗之解放加伤 / 充盈加伤 / 漆黑之枪】的推进阶段（0＝还没开始 / AN_ZHI_JIE_FANG＝暗之解放加伤 /
## CHONG_YING＝充盈加伤 / QI_HEI_ZHI_QIANG＝在问是否耗能量发动漆黑之枪）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨若干次询问，
## 中途一旦被别的钩子轮次（改手牌 / 盖牌 / 基础效果 / 横置…）插进来，step 就被抹掉、流程退回第 0 步。
## 每次自己主动攻击命中（p_timeline_2_hit）触发一次，收尾清回 0（留 STEP_DONE 会让下一次触发不再发动）
var _hit_step: int = 0


# ============================================================
# 主动攻击命中后：暗之解放 +1 伤害（2901）→ 充盈加伤（2905）→ 漆黑之枪（2906）
# ============================================================
func p_timeline_2_hit(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("src", -1)) != player.id:
		return SUCCESS
	if _hit_step >= STEP_DONE:
		return SUCCESS
	if _hit_step == 0:
		_hit_step = AN_ZHI_JIE_FANG
	if _hit_step == AN_ZHI_JIE_FANG:
		_an_zhi_jie_fang_effect(ctx)
		_hit_step = CHONG_YING
	if _hit_step == CHONG_YING:
		_chong_ying_add_harm(ctx)
		_hit_step = QI_HEI_ZHI_QIANG
	if _hit_step == QI_HEI_ZHI_QIANG:
		return _qi_hei_zhi_qiang(ctx)
	return SUCCESS


## 攻击预告加伤：幻影形态下已启动【暗之解放】、本回合还没用掉时，本次主动攻击命中会 +1；
## 或者【充盈】已激活（且非【暗之解放】）时，命中会 +本回合累计的充盈数
## （对应 p_timeline_2_hit 里的 _an_zhi_jie_fang_effect / _chong_ying_add_harm；只用于被攻击者提示）
func p_attack_preview(ctx: Dictionary) -> int:
	if not bool(ctx.get("is_active", false)):
		return 0
	if using_an_zhi_jie_fang and not used_an_zhi_jie_fang:
		return 1
	if used_chong_ying and not using_an_zhi_jie_fang:
		return card_count
	return 0


## 暗之解放：仅[幻影形态]下本回合首次主动攻击伤害 +1
func _an_zhi_jie_fang_effect(ctx: Dictionary) -> void:
	if not using_an_zhi_jie_fang or used_an_zhi_jie_fang:
		return
	if not bool(ctx.get("is_active", false)):
		return
	var harm: Dictionary = ctx["harm"]
	notice_skill(AN_ZHI_JIE_FANG, [int(harm.get("dst", -1))])
	harm["point"] = int(harm.get("point", 0)) + 1
	used_an_zhi_jie_fang = true


## 充盈加伤：本回合下次主动攻击伤害 +（其他角色弃掉的雷系/法术牌数）
func _chong_ying_add_harm(ctx: Dictionary) -> void:
	if not used_chong_ying or using_an_zhi_jie_fang:
		return
	if not bool(ctx.get("is_active", false)):
		return
	var harm: Dictionary = ctx["harm"]
	harm["point"] = int(harm.get("point", 0)) + card_count
	card_count = 0


## 漆黑之枪：仅[幻影形态]下，耗 X 能量，本次伤害 +(X+2)
func _qi_hei_zhi_qiang(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx["harm"]
	var dst_p: BattlePlayer = engine.p(int(harm.get("dst", -1)))
	if dst_p == null or not availabel_qi_hei_zhi_qiang:
		_hit_step = 0
		return SUCCESS
	if dst_p.hand_cards.size() < 1 or dst_p.hand_cards.size() > 2:
		_hit_step = 0
		return SUCCESS
	if not bool(ctx.get("is_active", false)) or using_an_zhi_jie_fang:
		_hit_step = 0
		return SUCCESS
	if not player.tap or player.get_energy() == 0:
		_hit_step = 0
		return SUCCESS
	if not engine.has_reply():
		# 通用客户端只回一维 args：把「投入能量数」做成 options，args[0] 即选中项的 value
		# （原版是靠 respond 的第二个参数 args[1] 传能量数，移植版拿不到所以恒为 0、伤害固定 +2）
		# 选项文案取技能表「提示」列第 1 条（「投入 {n} 点能量（伤害 +{n2}）」）；
		# 本次询问的指令条文案改用第 2 条（「发动【漆黑之枪】：选择投入的能量」），故 序号 传 1
		var options: Array = []
		for n: int in range(1, player.get_energy() + 1):
			options.append({"value": n, "label": 提示(QI_HEI_ZHI_QIANG, 0, n, -1, {"n2": n + 2})})
		询问(player.id, QI_HEI_ZHI_QIANG, 0, 0, GConst.CardSource.Hand, options, 0, "", [], true, 1)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	_hit_step = 0
	var args: Array = r.get("args", [])
	# args[0] 是所选能量数；取消/超时回 0，此时不发动（不扣能量、不加伤）
	var use: int = int(args[0]) if not args.is_empty() else 0
	if use <= 0:
		return SUCCESS
	use = clampi(use, 1, player.get_energy())
	for _i: int in range(use):
		if player.crystal > 0:
			player.set_crystal(player.crystal - 1)
		else:
			player.set_gem(player.gem - 1)
	notice_skill(QI_HEI_ZHI_QIANG, [dst_p.id])
	harm["point"] = int(harm.get("point", 0)) + use + 2
	engine._broadcast_game()
	return SUCCESS


func p_timeline_2_miss(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id or not bool(ctx.get("is_active", false)):
		return SUCCESS
	if used_chong_ying:
		card_count = 0
	used_an_zhi_jie_fang = true
	return SUCCESS


# ============================================================
# 受到伤害时：暗之障壁（2904，弃 X 张法术牌或雷系牌）
# ============================================================
func p_timeline_3(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("dst", -1)) != player.id:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	# 说明：法术牌 / 雷系牌 二选一，弃任意 X 张（X＝1~手里的合法牌数）。
	# 白名单给两类牌的并集，card_rule="an_zhi" 让界面以「先选的牌」为基准，把与它不共享类别的牌置灰；
	# card_max=合法牌数 放宽点选上限（不给就默认「恰好 1 张」）。
	# 两类都没有「可弃的牌」时也照旧询问（对照原版 MoQiang::AnZhiZhangBi 是无条件 askForSkill）——
	# 这时手牌里没有合法牌可选，「确定」按不了，玩家点「取消」即可。
	# 可弃 在函数作用域声明：结算时还要用它复核玩家回传的牌。
	# 额外把「本次受到的伤害」下发进询问文案（技能表提示列写作「受到 {伤害} 伤害」，见 提示文本 的占位替换）
	var 可弃: Array[int] = hand_ids_where(func(_cid: int, c: GCard) -> bool: return c.is_magic() or c.element_enum() == GConst.CardElement.Thunder)
	if not engine.has_reply():
		询问(player.id, AN_ZHI_ZHANG_BI, 1, 0, GConst.CardSource.Hand, [], 可弃.size(), "an_zhi", 可弃,
			true, 0, -1, [], -1, {"伤害": int(harm.get("point", 0))})
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		return SUCCESS
	# 所选牌必须同属「法术」或「雷系」中的同一类（既是法术又是雷系的牌两边都算）。
	# 取覆盖所选牌最多的那一类作为本次组合，只保留属于该类的牌。
	# 全是「两类都属」的牌时两类计数相等（无多数派），此时取法术类也不会丢牌（这些牌本就属法术）
	var cards: Array = r.get("card_ids", [])
	var 候选: Array[int] = []
	for c: Variant in cards:
		var cid: int = int(c)
		if not player.has_hand_card(cid) or not 可弃.has(cid):
			continue
		if Data.get_card(cid) != null:
			候选.append(cid)
	var 法术数: int = 0
	var 雷系数: int = 0
	for cid2: int in 候选:
		var c2: GCard = Data.get_card(cid2)
		if c2.is_magic():
			法术数 += 1
		if c2.element_enum() == GConst.CardElement.Thunder:
			雷系数 += 1
	var 取法术: bool = 法术数 >= 雷系数
	var chosen: Array = []
	for cid3: int in 候选:
		var c3: GCard = Data.get_card(cid3)
		var 属于该类: bool = c3.is_magic() if 取法术 else c3.element_enum() == GConst.CardElement.Thunder
		if 属于该类:
			chosen.append(cid3)
	if chosen.is_empty():
		return SUCCESS
	notice_skill(AN_ZHI_ZHANG_BI, [player.id])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": chosen, "is_real": true,
	})
	engine.take_from_hand(player.id, chosen, true)
	engine.to_discard(chosen)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 幻影星辰自伤结算：手牌为 0 时，治疗最多只能使用 1 点
# （服务端 crossAvailable 为可抵御点数；本引擎用 harm["cross_max_point"] 限制本次可抵御点数）
# ============================================================
func p_timeline_4(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("dst", -1)) != player.id:
		return SUCCESS
	if int(harm.get("cause", -1)) != HUAN_YING_XING_CHEN:
		return SUCCESS
	if int(harm.get("cross_available", 1)) <= 0:
		return SUCCESS
	if not player.hand_cards.is_empty() or player.cross_num <= 1:
		return SUCCESS
	harm["cross_max_point"] = 1
	return SUCCESS


# ============================================================
# 主动法术技能：充盈（2905）
# ============================================================
func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != CHONG_YING or not availabel_chong_ying:
		return GConst.GE_INVALID_ACTION
	var cards: Array = action.get("card_ids", [])
	if cards.is_empty():
		return GConst.GE_INVALID_CARDID
	var cid: int = int(cards[0])
	var card: GCard = Data.get_card(cid)
	# 只能弃法术牌或雷系牌（技能原文，原先服务端漏了这条；客户端按同一条给 cards 白名单）
	if not player.has_hand_card(cid) or card == null \
			or (not card.is_magic() and card.element_enum() != GConst.CardElement.Thunder):
		return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != CHONG_YING:
		return GConst.GE_INVALID_ACTION
	return _chong_ying(action)


## 充盈：弃 1 张法术牌或雷系牌，所有人各弃 1 张牌（敌方强制、我方可选），
## 除你以外每有人弃雷系/法术牌则本回合下次主动攻击 +1，额外 +1 攻击行动
func _chong_ying(action: Dictionary) -> int:
	if step == 0:
		var cards: Array = action.get("card_ids", [])
		var cid: int = int(cards[0])
		var card: GCard = Data.get_card(cid)
		# 服务端：既非法术牌也非雷系牌则不发动的落空分支
		if card == null:
			return GConst.GE_INVALID_ACTION
		notice_skill(CHONG_YING, [player.id])
		engine.broadcast(GConst.Msg.Card, {
			"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
			"card_ids": [cid], "is_real": true,
		})
		engine.take_from_hand(player.id, [cid], true)
		engine.to_discard([cid])
		card_count = 0
		used_chong_ying = true
		_chong_targets = _all_ids_from_self()
		_chong_index = 0
		player.add_action(GConst.ActionType.Attack, CHONG_YING, true)
		engine._broadcast_game()
		step = 1
	if step == 1:
		while _chong_index < _chong_targets.size():
			var tid: int = _chong_targets[_chong_index]
			var tp: BattlePlayer = engine.p(tid)
			if tp == null:
				_chong_index += 1
				continue
			if not engine.has_reply():
				if tp.color != player.color:
					# 服务端对敌方用不可放弃的 StateRequestHand：敌方必须弃 1 张
					engine.ask_respond(tid, GConst.RespondType.Discard, [tid, CHONG_YING, 1], [tid])
					engine.wait_for(tid, GConst.Msg.Respond)
				else:
					询问(tid, CHONG_YING, 1)
				return WAIT
			var r: Dictionary = take_skill_reply_full()
			_chong_index += 1
			var cs: Array = r.get("card_ids", [])
			if cs.is_empty():
				# 敌方不允许放弃：没选牌就从其手牌强制取 1 张
				if tp.color != player.color and not tp.hand_cards.is_empty():
					cs = [tp.hand_cards[0]]
				else:
					continue
			var ccid: int = int(cs[0])
			if not tp.has_hand_card(ccid):
				continue
			var c2: GCard = Data.get_card(ccid)
			if c2 == null:
				continue
			var counted: bool = c2.is_magic() or c2.element_enum() == GConst.CardElement.Thunder
			notice_skill(CHONG_YING, [tid])
			engine.broadcast(GConst.Msg.Card, {
				"type": GConst.CardMsgType.Show, "src_id": tid, "dst_id": tid,
				"card_ids": [ccid], "is_real": true,
			})
			engine.take_from_hand(tid, [ccid], true)
			engine.to_discard([ccid])
			if counted and tid != player.id:
				card_count += 1
			engine._broadcast_game()
		step = STEP_DONE
	return SUCCESS


# ============================================================
# 工具
# ============================================================
func _hand_has_thunder() -> bool:
	for cid: int in player.hand_cards:
		var c: GCard = Data.get_card(cid)
		if c != null and c.element_enum() == GConst.CardElement.Thunder:
			return true
	return false


func _hand_has_magic() -> bool:
	for cid: int in player.hand_cards:
		var c: GCard = Data.get_card(cid)
		if c != null and c.is_magic():
			return true
	return false


## 自己以外、从下家开始按座位序的所有角色 id
func _other_ids_from_self() -> Array[int]:
	var ids: Array[int] = []
	var cur: int = player.post_id
	var guard: int = engine.order.size()
	while cur != player.id and guard > 0:
		ids.append(cur)
		cur = engine.next_id(cur)
		guard -= 1
	return ids


## 充盈的处理顺序（含自己）：自己最先，再下家起按座位序绕一圈。
## 服务端把其他人从自己上家起反向压栈、最后压自己（LIFO → 自己最先被问到）
func _all_ids_from_self() -> Array[int]:
	var ids: Array[int] = []
	ids.append(player.id)
	ids.append_array(_other_ids_from_self())
	return ids
