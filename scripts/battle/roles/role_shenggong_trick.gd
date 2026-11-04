extends BattleRole
## 原初之弓Trick（roleID 88）—— 圣弓（原「原初之弓」，roleID 37）的完整副本，供两个版本独立调整。
## 原始实现移植自服务端 role/ShengGong.cpp；改动时请与 role_shenggong.gd 分开维护。
## 指示物：tokens[0] = 信仰（上限见角色表）；治疗上限 3
## 技能：天之弓（8801，被动：开局拥有【圣煌辉光炮】、治疗上限 +1；
##                 主动攻击非【圣】命格伤害 -1；攻击命中且为【圣】命格 +1 信仰，应战命中也算）、
##       圣屑飓暴（8802，法术：弃 2 张同系牌，以该系【圣】命格攻击牌对目标发起一次攻击；
##                 若弃的是两张【圣光】，则改用暗系【暗灭】）、
##       圣屑飓暴·未命中（88021，响应：耗 X 治疗，X 最高 2；目标队友弃 X 张牌，可取消）、
##       圣煌模式（8803，法术：耗 2 治疗或 2 信仰 → 横置进入圣煌形态并额外 +1 法术行动；
##                 圣煌形态下执行特殊行动时重置并 +1 治疗）、
##       圣光爆裂（8804，法术：圣煌形态下二选一，见 _sheng_guang_bao_lie_choices）、
##       圣流星弹（8805，响应：圣煌形态下主动攻击前，耗 1 治疗或 1 信仰，我方目标 +1 治疗）、
##       圣煌辉光炮（8806，法术：圣煌形态下，全场手牌补/弃到 min(4, 手牌上限)、星杯 +1、
##                 双方士气拉平、我方各 +1 治疗、自己额外 +1 攻击或法术行动，然后翻面为【圣煌余辉】）、
##       圣煌余辉（8808，法术：圣煌形态下，同上的手牌/星杯/士气效果，然后移除本技能）、
##       自动填充（8807，回合结束：先选消耗水晶/宝石，再手选加治疗或信仰；超时才按治疗空位自动优先治疗）
##
## 说明：
## - 圣煌形态 = player.tap（横置）。圣煌模式（8803）进入，执行特殊行动时由 p_before_special 解除。
## - 圣流星弹（8805）在主动攻击宣告后、结算前（p_timeline_1）询问；旧版的“特殊行动时重置”
##   已按设计表说明归到 8803 的形态效果里，不再占用 8805。
## - 圣煌辉光炮/圣煌余辉是同一张专属技的正反面：状态记在 player.sheng_huang_side
##   （0=正面、1=背面、2=已移除）；界面上两颗技能都摆出来，按状态置灰（不删除），
##   同时由客户端在状态图标区显示对应的专属技图标。
## - 服务端 v_magic_skill 对法术技能不做任何校验，此处按设计表说明补最小校验。

const TIAN_ZHI_GONG: int = 8801
const SHENG_XIE_JU_BAO: int = 8802
const SHENG_XIE_MISS: int = 88021
const SHENG_HUANG_MO_SHI: int = 8803
const SHENG_GUANG_BAO_LIE: int = 8804
const SHENG_LIU_XING_DAN: int = 8805
const HUI_GUANG_PAO: int = 8806
const ZI_DONG_TIAN_CHONG: int = 8807
const HUI_GUANG_YU_HUI: int = 8808

## 本引擎自有的分步标记（服务端把子步骤实现为压栈状态，此处只用 step 记录进度）
const SHENG_XIE_MISS_DISCARD: int = 88022   # 圣屑飓暴·未命中：请目标弃牌

const TOKEN_XIN_YANG: int = 0
const CROSS_MAX_SHENG_GONG: int = 3
const SHENG_GUANG_BAO_LIE_BASE: int = 2     # 圣光爆裂基础伤害
const ATTACK_BASE_POINT: int = 2            # 攻击牌基础伤害
const HUI_GUANG_KEEP: int = 4               # 圣煌辉光炮/余辉：全场手牌补/弃到 4 张（上限不足 4 的补到上限）
const HUI_GUANG_PAO_COST: int = 4           # 圣煌辉光炮/余辉：基础信仰消耗；另加落后士气差
const HUI_GUANG_SIDE_FRONT: int = 0
const HUI_GUANG_SIDE_BACK: int = 1
const HUI_GUANG_SIDE_REMOVED: int = 2

var no_tian_chong: bool = false             # 本回合是否进行过特殊行动（跳过自动填充）

## 圣屑飓暴·未命中的中间状态
var sheng_xie_miss_dst: int = -1
var sheng_xie_miss_num: int = 0

## 圣煌辉光炮的进度（-1 表示未开始；主动法术技能不在钩子轮次内，step 不会被重置）
var hui_guang_index: int = -1
## 本次调整中待摸牌的角色（按逆时针顺序记录）。中途等别人弃牌时不能丢，故放在成员上。
var hui_guang_draws: Array = []


func setup(p: BattlePlayer, e: BattleEngine) -> void:
	super.setup(p, e)
	p.cross_max = CROSS_MAX_SHENG_GONG
	# 天之弓：游戏初始时拥有【圣煌辉光炮】。客户端据 player.sheng_huang_side 画状态图标。
	p.sheng_huang_side = HUI_GUANG_SIDE_FRONT


func available_skills() -> Array:
	var out: Array = []
	# 圣屑飓暴要弃 2 张同系牌：只让「手里该系不少于 2 张、且该系有【圣】命格攻击牌」的牌可点，
	# 界面据此把同系孤张与没有虚拟牌的系置灰（与 v_magic_skill 的校验一致）
	var 同系牌: Array[int] = _sheng_xie_hand_ids()
	# 手里没有「该系至少 2 张且有【圣】命格攻击牌」的牌时置灰。
	# card_rule="same" 让界面在第一张选定后只亮同系牌，避免从两个不同系各选一张、
	# 点确定后被 v_magic_skill 驳回。
	out.append({"type": GConst.ActionType.MagicSkill, "id": SHENG_XIE_JU_BAO, "need_card": 2, "need_target": 1,
		"cards": 同系牌, "card_rule": "same", "targets": enemy_ids(), "enabled": not 同系牌.is_empty()})
	# 圣煌模式：两种资源都摆成选项，不够的那一项置灰；已横置时整颗技能置灰。
	out.append({"type": GConst.ActionType.MagicSkill, "id": SHENG_HUANG_MO_SHI, "need_card": 0, "need_target": 0,
		"arg_choices": _sheng_huang_mo_shi_choices(),
		"enabled": not player.tap and (player.cross_num > 1 or _xin_yang() > 1)})
	# 圣光爆裂：两个分支都摆成选项；未横置、没有治疗，或两个分支都没有合法目标时整颗技能置灰。
	# 每个选项自带 need_card / need_target / target_max / targets，切换选项后界面按该项收紧。
	var 爆裂选项: Array = _sheng_guang_bao_lie_choices()
	var 爆裂可用: bool = false
	for 项: Dictionary in 爆裂选项:
		if bool(项.get("enabled", true)):
			爆裂可用 = true
			break
	out.append({"type": GConst.ActionType.MagicSkill, "id": SHENG_GUANG_BAO_LIE, "need_card": 0, "need_target": 0,
		"arg_choices": 爆裂选项, "enabled": player.tap and 爆裂可用})
	# 圣煌辉光炮 / 圣煌余辉：同一张专属技的正反面，两颗都摆出来，按 player.sheng_huang_side 置灰。
	# 只要求圣煌形态 + 信仰足够支付（落后士气差 + 4）；设计表没有把“士气落后”写成发动条件。
	var 炮选项: Array = _hui_guang_pao_choices(true, HUI_GUANG_PAO)
	var 余辉选项: Array = _hui_guang_pao_choices(false, HUI_GUANG_YU_HUI)
	out.append({"type": GConst.ActionType.MagicSkill, "id": HUI_GUANG_PAO, "need_card": 0, "need_target": 0,
		"arg_choices": 炮选项, "enabled": _hui_guang_enabled(HUI_GUANG_SIDE_FRONT)})
	out.append({"type": GConst.ActionType.MagicSkill, "id": HUI_GUANG_YU_HUI, "need_card": 0, "need_target": 0,
		"arg_choices": 余辉选项, "enabled": _hui_guang_enabled(HUI_GUANG_SIDE_BACK)})
	return out


## 圣煌模式的两种支付方式。两项都返回，资源不够的那项由 enabled=false 置灰。
func _sheng_huang_mo_shi_choices() -> Array:
	return [
		{"text": GConst.按钮原文(SHENG_HUANG_MO_SHI, 0), "args": [1], "enabled": player.cross_num > 1},
		{"text": GConst.按钮原文(SHENG_HUANG_MO_SHI, 1), "args": [2], "enabled": _xin_yang() > 1},
	]


## 圣光爆裂的第一层选项（args[0]=1 单体 / 2 群体）：
##   1：移除 1 治疗，摸 1 张牌，对 1 名手牌数少于你的对手造成 2 点攻击伤害，+1 信仰；
##   2：群体，具体的 X（移除多少治疗）由客户端二级技能栏再选，最终 args=[2, x]。
## 单体的 need_card / need_target / target_max / targets 照旧；群体第一层不要求目标 / 牌，
## 选完群体后由客户端摆出 X=1..3 的第二层选项，再按 X 收紧弃牌数与目标。
func _sheng_guang_bao_lie_choices() -> Array:
	var out: Array = []
	var 单体目标: Array[int] = _sheng_guang_mode1_targets()
	out.append({
		"text": GConst.按钮原文(SHENG_GUANG_BAO_LIE, 0),
		"args": [1],
		"need_card": 0,
		"need_target": 1,
		"target_max": 1,
		"targets": 单体目标,
		"enabled": player.cross_num > 0 and not 单体目标.is_empty(),
		# 单体分支先摸 1 张再判定伤害；摸牌受手牌上限约束，目标手牌须严格小于摸牌后的手牌数。
		"说明": "摸 1 牌，对 1 名手牌数小于 %d 的对手造成 2 点攻击伤害，你 +1【信仰】。" % _sheng_guang_single_hand_limit(),
	})
	var 群体目标: Array[int] = _sheng_guang_mode2_targets(1)
	out.append({
		"text": GConst.按钮原文(SHENG_GUANG_BAO_LIE, 1),
		"args": [2],
		"need_card": 0,
		"need_target": 0,
		"target_max": 0,
		"targets": [],
		"enabled": player.cross_num > 0 and not 群体目标.is_empty(),
		"说明": "移除 X 治疗，弃 X 张牌，对最多 X 名手牌数小于（你的手牌数 - X + 1）的对手各造成（Y+2）点攻击伤害，Y为目标中拥有【治疗】的人数，你获得 X 点【信仰】。X 在下一步选择。",
	})
	return out


## 圣光爆裂·单体：摸牌后你的手牌是 H+1，所以目标手牌数 <= H 即满足「小于你」。
## 圣光爆裂·单体：先摸 1 张，摸牌受手牌上限约束；目标手牌必须严格小于摸牌后的手牌数。
func _sheng_guang_single_hand_limit() -> int:
	return mini(player.hand_cards.size() + 1, player.hand_cards_max)


func _sheng_guang_mode1_targets() -> Array[int]:
	var out: Array[int] = []
	var 阈值: int = _sheng_guang_single_hand_limit()
	for pid: int in engine.order:
		var p0: BattlePlayer = engine.p(pid)
		if p0 != null and p0.color != player.color and p0.hand_cards.size() < 阈值:
			out.append(pid)
	return out


## 圣光爆裂·群体：目标手牌数 <= 你的手牌数 - x（结算弃牌前判定）。
func _sheng_guang_mode2_targets(x: int) -> Array[int]:
	var out: Array[int] = []
	var 上限: int = player.hand_cards.size() - x
	if 上限 < 0:
		return out
	for pid: int in engine.order:
		var p0: BattlePlayer = engine.p(pid)
		if p0 != null and p0.color != player.color and p0.hand_cards.size() <= 上限:
			out.append(pid)
	return out


func _enemy_color() -> int:
	return GConst.BLUE if player.color == GConst.RED else GConst.RED


func _my_morale() -> int:
	return engine.team_morale[player.color]


func _enemy_morale() -> int:
	return engine.team_morale[_enemy_color()]


## 圣煌辉光炮/余辉的信仰消耗：基础 4 + 我方落后士气差。
func _hui_guang_cost() -> int:
	return HUI_GUANG_PAO_COST + maxi(_enemy_morale() - _my_morale(), 0)


func _hui_guang_enabled(side: int) -> bool:
	return player.sheng_huang_side == side and player.tap and _xin_yang() >= _hui_guang_cost()


## 辉光炮/余辉的士气方向选项。辉光炮的额外行动固定是「攻击或法术行动」，
## 不再在选项里选攻击/法术；余辉没有额外行动。两者都只选士气方向。
## 技能号 区分正反两面（8806 辉光炮 / 8808 余辉），按钮文案各读各的技能行。
func _hui_guang_pao_choices(含额外行动: bool, 技能号: int) -> Array:
	var 额外说明: String = "然后你获得 1 次攻击或法术行动。" if 含额外行动 else ""
	return [
		{"text": GConst.按钮原文(技能号, 0), "args": [1],
			"说明": "我方士气调整为与敌方相同。" + 额外说明},
		{"text": GConst.按钮原文(技能号, 1), "args": [0],
			"说明": "敌方士气调整为与我方相同。" + 额外说明},
	]


## 自动填充第一层只给两个资源选项：
##   1＝消耗 1 水晶（没有水晶时用宝石替代）；2＝消耗 1 宝石。
## 具体加治疗还是加信仰由客户端第二层选，最终 args=[资源, 效果]。
## 资源不足的项照样下发，由 enabled=false 置灰。
func _auto_fill_choices() -> Array:
	var 有能量: bool = player.crystal > 0 or player.gem > 0
	return [
		{"value": 1, "label": GConst.按钮原文(ZI_DONG_TIAN_CHONG, 0), "enabled": 有能量},
		{"value": 2, "label": GConst.按钮原文(ZI_DONG_TIAN_CHONG, 1), "enabled": player.gem > 0},
	]


## 当前还能加几点治疗：治疗上限 - 当前治疗（已超过上限时按 0 算）。
func _auto_fill_heal_slots() -> int:
	return maxi(player.cross_max - player.cross_num, 0)


# ============================================================
# 指示物与工具
# ============================================================
func _xin_yang() -> int:
	var t: Dictionary = player.tokens[TOKEN_XIN_YANG]
	return int(t["num"])


func _set_token(idx: int, v: int) -> void:
	var t: Dictionary = player.tokens[idx]
	t["num"] = clampi(v, 0, int(t["max"]))


func _same_element(a: int, b: int) -> bool:
	var ca: GCard = Data.get_card(a)
	var cb: GCard = Data.get_card(b)
	if ca == null or cb == null:
		return false
	return ca.element_enum() == cb.element_enum()


## 圣屑飓暴可弃的手牌：该系手里至少有 2 张，且该系存在【圣】命格攻击牌可当虚拟牌用
func _sheng_xie_hand_ids() -> Array[int]:
	var out: Array[int] = []
	for cid: int in player.hand_cards:
		var c: GCard = Data.get_card(cid)
		if c == null or _sheng_xie_virtual_card(c.element_enum()) < 0:
			continue
		var 同系数: int = 0
		for other: int in player.hand_cards:
			var o: GCard = Data.get_card(other)
			if o != null and o.element_enum() == c.element_enum():
				同系数 += 1
		if 同系数 >= 2:
			out.append(cid)
	return out


## 该系【圣】命格攻击牌（发动时当作打出的虚拟牌）；取值与服务端客户端 ShengGong.cpp 的硬编码一致
func _sheng_xie_virtual_card(element: int) -> int:
	match element:
		GConst.CardElement.Earth: return 54       # 地裂斩
		GConst.CardElement.Wind: return 75        # 风神斩
		GConst.CardElement.Water: return 137      # 水涟斩
		GConst.CardElement.Thunder: return 117    # 雷光斩
		GConst.CardElement.Fire: return 96        # 火焰斩
		GConst.CardElement.Darkness: return 39    # 暗灭
		GConst.CardElement.Light: return 39       # 两张【圣光】按设计表视为暗系【暗灭】
	return -1


## 从 ids 中挑出 n 张手牌（不足时按手牌顺序补齐）
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


func _discard_own(ids: Array, n: int) -> void:
	var want: int = mini(n, player.hand_cards.size())
	if want <= 0:
		return
	var chosen: Array = _pick_cards(player, ids, want)
	engine.take_from_hand(player.id, chosen)
	engine.to_discard(chosen, {"owner": player.id, "source": "hand"})


## 请某名角色弃 n 张牌（服务端 StateRequestHand）
func _request_discard(pid: int, n: int, cause: int) -> int:
	var target: BattlePlayer = engine.p(pid)
	if target == null or n <= 0 or target.hand_cards.is_empty():
		return SUCCESS
	# 要弃的张数最多到他的手牌数：询问时就按真实张数下发，界面提示里的 {n} 才是真的
	var want: int = mini(n, target.hand_cards.size())
	if not engine.has_reply():
		询问(pid, cause, want)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var chosen: Array = _pick_cards(target, r.get("card_ids", []), want)
	engine.take_from_hand(pid, chosen)
	engine.to_discard(chosen, {"owner": pid, "source": "hand"})
	# 弃牌不是亮牌：只写「谁弃掉几张」并让客户端播弃牌特效，不能悄悄改手牌
	engine._log_discard(pid, chosen)
	engine._broadcast_game()
	return SUCCESS


## 我方所有角色（含自己）
func _all_allies() -> Array[int]:
	var out: Array[int] = [player.id]
	out.append_array(ally_ids())
	return out


## 辉光炮/余辉把目标手牌补/弃到几张：最多 4，且不超过他的手牌上限。
func _hui_guang_target_hand(dp: BattlePlayer) -> int:
	return mini(HUI_GUANG_KEEP, dp.hand_cards_max)


## 圣煌辉光炮/余辉的处理顺序：从圣弓自己开始，逆时针（pre_id）绕一圈。
func _ids_from_self() -> Array[int]:
	var ids: Array[int] = []
	var cur: int = player.id
	var guard: int = engine.order.size() + 1
	while guard > 0:
		ids.append(cur)
		var cur_p: BattlePlayer = engine.p(cur)
		if cur_p == null:
			break
		cur = cur_p.pre_id
		guard -= 1
		if cur == player.id:
			break
	return ids


func p_before_turn_begin(_ctx: Dictionary) -> int:
	no_tian_chong = false
	return SUCCESS


## 【天之弓 / 圣流星弹】的推进阶段（0＝还没开始 / TIAN_ZHI_GONG＝天之弓减伤 /
## SHENG_LIU_XING_DAN＝在问是否发动圣流星弹）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨若干次询问，
## 中途一旦被别的钩子轮次（改手牌 / 盖牌 / 基础效果 / 横置…）插进来，step 就被抹掉、流程退回第 0 步。
## 每次自己主动宣告攻击（p_timeline_1）触发一次，收尾清回 0（留 STEP_DONE 会让下一次触发不再发动）
var _timeline_1_step: int = 0


# ============================================================
# 攻击宣告后（timeline_1）：天之弓（8801）→ 圣流星弹（8805）
# ============================================================
func p_timeline_1(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id or not bool(ctx.get("is_active", false)):
		return SUCCESS
	if _timeline_1_step >= STEP_DONE:
		return SUCCESS
	if _timeline_1_step == 0:
		_timeline_1_step = TIAN_ZHI_GONG
	if _timeline_1_step == TIAN_ZHI_GONG:
		# 非【圣】命格的攻击牌：本次伤害 -1
		var card: GCard = Data.get_card(int(ctx.get("card_id", -1)))
		if card != null and card.fate_pattern_enum() != GConst.FatePattern.Holy:
			var harm: Dictionary = ctx.get("harm", {})
			harm["point"] = int(harm.get("point", 0)) - 1
		_timeline_1_step = SHENG_LIU_XING_DAN
	if _timeline_1_step == SHENG_LIU_XING_DAN:
		var r: int = _sheng_liu_xing_atk()
		if r == WAIT:
			return WAIT
		_timeline_1_step = 0
	return SUCCESS


## 圣流星弹：圣煌形态下，主动攻击宣告后耗 1 治疗或 1 信仰，令我方目标 +1 治疗。
## 两种支付方式都摆出来，资源不够的那项置灰；目标只能是友方（含自己）。
func _sheng_liu_xing_atk() -> int:
	if not player.tap:
		return SUCCESS
	var 友方: Array[int] = [player.id]
	友方.append_array(ally_ids())
	var 选项: Array = [
		{"value": 1, "label": GConst.按钮原文(SHENG_LIU_XING_DAN, 0), "enabled": player.cross_num > 0},
		{"value": 2, "label": GConst.按钮原文(SHENG_LIU_XING_DAN, 1), "enabled": _xin_yang() > 0},
	]
	var 有可用: bool = player.cross_num > 0 or _xin_yang() > 0
	if not 有可用:
		return SUCCESS
	if not engine.has_reply():
		询问(player.id, SHENG_LIU_XING_DAN, 0, 1, GConst.CardSource.Hand, 选项,
				0, "", [], true, 0, -1, 友方)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	var dsts: Array = r.get("dst_ids", [])
	var choice: int = int(args[0]) if not args.is_empty() else 0
	if dsts.is_empty():
		return SUCCESS
	var dst_id: int = int(dsts[0])
	if not 友方.has(dst_id):
		return SUCCESS
	if choice == 1:
		if player.cross_num <= 0:
			return SUCCESS
		player.sub_cross_num(1)
	elif choice == 2:
		if _xin_yang() <= 0:
			return SUCCESS
		_set_token(TOKEN_XIN_YANG, _xin_yang() - 1)
	else:
		return SUCCESS
	施加治疗(dst_id, 1)
	notice_skill(SHENG_LIU_XING_DAN, [dst_id])
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 攻击命中后（timeline_2_hit）：天之弓（8801）的 +1 信仰（主动 / 应战都算）
# ============================================================
func p_timeline_2_hit(ctx: Dictionary) -> int:
	# 设计表只写「攻击命中时」，没有限定主动攻击；应战反击命中同样 +1 信仰。
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	step = STEP_DONE
	var card: GCard = Data.get_card(int(ctx.get("card_id", -1)))
	if card != null and card.fate_pattern_enum() == GConst.FatePattern.Holy:
		notice_skill(TIAN_ZHI_GONG, [player.id])
		_set_token(TOKEN_XIN_YANG, _xin_yang() + 1)
		engine._broadcast_game()
	return SUCCESS


# ============================================================
# 主动攻击未命中后（timeline_2_miss）：圣屑飓暴·未命中（88021）
# ============================================================
## 圣屑飓暴·未命中的参数选项：治疗数 X（1..min(当前治疗, 2)）各对应「弃 X 张」。
## 只保留「弃 X 张」：value 就是 X（1..min(当前治疗, 2)），目标只限队友（不含自己）。
func _sheng_xie_miss_choices() -> Array:
	var out: Array = []
	var n: int = mini(player.cross_num, 2)
	for x: int in range(1, n + 1):
		out.append({"value": x, "label": GConst.按钮原文(SHENG_XIE_JU_BAO, 0) % x})
	return out


## 【圣屑飓暴·未命中】的推进阶段（0＝还没开始 / SHENG_XIE_MISS＝在问丢几张与目标队友 /
## SHENG_XIE_MISS_DISCARD＝在请目标队友弃牌）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨若干次询问，
## 中途一旦被别的钩子轮次（改手牌 / 盖牌 / 基础效果 / 横置…）插进来，step 就被抹掉、流程退回第 0 步。
## 每次圣屑飓暴未命中（p_timeline_2_miss）触发一次，收尾清回 0（留 STEP_DONE 会让下一次触发不再发动）
var _miss_step: int = 0


func p_timeline_2_miss(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	# 只有【圣屑飓暴】打出的那次攻击未命中才触发；别的攻击未命中不能白拿这个效果。
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("cause", 0)) != SHENG_XIE_JU_BAO:
		return SUCCESS
	if _miss_step >= STEP_DONE:
		return SUCCESS
	var 可耗: int = mini(player.cross_num, 2)
	if 可耗 <= 0:
		_miss_step = 0
		return SUCCESS
	var 队友: Array[int] = ally_ids()
	if 队友.is_empty():
		_miss_step = 0
		return SUCCESS
	if _miss_step == 0:
		_miss_step = SHENG_XIE_MISS
	if _miss_step == SHENG_XIE_MISS:
		if not engine.has_reply():
			# 序号 1：第 0 条提示是「先弃 2 张」用的，这步「指定队友弃几张」读第 1 条。
			# 张数做成选项（见 _sheng_xie_miss_choices），服务端读 args[0]。
			询问(player.id, SHENG_XIE_MISS, 0, 1, GConst.CardSource.Hand,
					_sheng_xie_miss_choices(), 0, "", [], true, 1, -1, 队友)
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		var args: Array = r.get("args", [])
		var dsts: Array = r.get("dst_ids", [])
		var num: int = int(args[0]) if not args.is_empty() else 0
		if num <= 0 or num > 可耗 or dsts.is_empty():
			_miss_step = 0
			return SUCCESS
		var dst_id: int = int(dsts[0])
		if not 队友.has(dst_id):
			_miss_step = 0
			return SUCCESS
		sheng_xie_miss_dst = dst_id
		sheng_xie_miss_num = num
		player.sub_cross_num(num)
		notice_skill(SHENG_XIE_MISS, [dst_id])
		engine._broadcast_game()
		_miss_step = SHENG_XIE_MISS_DISCARD
	if _miss_step == SHENG_XIE_MISS_DISCARD:
		var r2: int = _request_discard(sheng_xie_miss_dst, sheng_xie_miss_num, SHENG_XIE_MISS)
		if r2 == WAIT:
			return WAIT
		_miss_step = 0
	return SUCCESS


# ============================================================
# 特殊行动前：圣煌模式（8803）的形态效果——横置时重置并 +1 治疗，且本回合跳过自动填充
# ============================================================
func p_before_special(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	# 服务端在本钩子中无条件置位（无论是否横置）
	no_tian_chong = true
	if not player.tap:
		return SUCCESS
	notice_skill(SHENG_HUANG_MO_SHI, [player.id])
	player.tap = false
	施加治疗(player.id, 1)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 回合结束：自动填充（8807）
# ============================================================
func p_turn_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if no_tian_chong or player.get_energy() < 1:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if step == 0:
		step = ZI_DONG_TIAN_CHONG
	var 选项: Array = _auto_fill_choices()
	var 有可用: bool = false
	for 项: Dictionary in 选项:
		if bool(项.get("enabled", true)):
			有可用 = true
			break
	if not 有可用:
		step = STEP_DONE
		return SUCCESS
	if not engine.has_reply():
		# 两个选项：消耗水晶 / 消耗宝石。必须选一项，can_cancel=false。
		询问(player.id, ZI_DONG_TIAN_CHONG, 0, 0, GConst.CardSource.Hand, 选项, 0, "", [], false)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	var args: Array = r.get("args", [])
	var 资源: int = 0
	var 效果: int = 0
	# 空 args / [0] 是超时：优先用宝石，没有宝石才用水晶；
	# 然后按治疗空位自动选治疗，空位不足才选信仰。
	if args.is_empty() or int(args[0]) == 0:
		if player.gem > 0:
			资源 = 2
		elif player.crystal > 0:
			资源 = 1
		else:
			return SUCCESS
		var 超时需空位: int = 2 if 资源 == 2 else 1
		效果 = 1 if _auto_fill_heal_slots() >= 超时需空位 else 2
	else:
		# 手动：第一层选资源，第二层选治疗/信仰，最终 args=[资源, 效果]。
		if args.size() < 2:
			return SUCCESS
		资源 = int(args[0])
		效果 = int(args[1])
		if (资源 != 1 and 资源 != 2) or (效果 != 1 and 效果 != 2):
			return SUCCESS
		if 资源 == 1:
			if player.crystal <= 0 and player.gem <= 0:
				return SUCCESS
		elif player.gem <= 0:
			return SUCCESS
	notice_skill(ZI_DONG_TIAN_CHONG, [player.id])
	if 资源 == 1:
		if player.crystal > 0:
			player.set_crystal(player.crystal - 1)
		else:
			player.set_gem(player.gem - 1)
	else:
		player.set_gem(player.gem - 1)
		player.set_crystal(player.crystal + 1)
	if 效果 == 1:
		施加治疗(player.id, 2 if 资源 == 2 else 1)
	else:
		_set_token(TOKEN_XIN_YANG, _xin_yang() + (2 if 资源 == 2 else 1))
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 主动法术技能
# ============================================================
func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	var args: Array = action.get("args", [])
	match int(action.get("action_id", 0)):
		SHENG_XIE_JU_BAO:
			# 弃 2 张同系手牌，虚拟牌（该系【圣】命格攻击牌）由服务端按元素自己取，客户端不用传。
			if cards.size() != 2 or dsts.size() != 1:
				return GConst.GE_INVALID_ACTION
			if int(cards[0]) == int(cards[1]):
				return GConst.GE_INVALID_CARDID
			if not player.has_hand_card(int(cards[0])) or not player.has_hand_card(int(cards[1])):
				return GConst.GE_INVALID_ACTION
			if not _same_element(int(cards[0]), int(cards[1])):
				return GConst.GE_INVALID_CARDID
			var first: GCard = Data.get_card(int(cards[0]))
			if first == null or _sheng_xie_virtual_card(first.element_enum()) < 0:
				return GConst.GE_INVALID_CARDID
			var dst0: BattlePlayer = engine.p(int(dsts[0]))
			if dst0 == null or dst0.color == player.color:
				return GConst.GE_INVALID_ACTION
		SHENG_HUANG_MO_SHI:
			# 技能要横置自己，已经横置就不能再发动；args[0] 明确选了治疗还是信仰。
			if player.tap or args.is_empty():
				return GConst.GE_INVALID_ACTION
			var 支付: int = int(args[0])
			if 支付 == 1:
				if player.cross_num < 2:
					return GConst.GE_INVALID_ACTION
			elif 支付 == 2:
				if _xin_yang() < 2:
					return GConst.GE_INVALID_ACTION
			else:
				return GConst.GE_INVALID_ACTION
		SHENG_GUANG_BAO_LIE:
			if player.cross_num < 1 or not player.tap or args.is_empty():
				return GConst.GE_INVALID_ACTION
			var 模式: int = int(args[0])
			if 模式 == 1:
				if not cards.is_empty() or dsts.size() != 1:
					return GConst.GE_INVALID_ACTION
				var 单体: BattlePlayer = engine.p(int(dsts[0]))
				if 单体 == null or 单体.color == player.color:
					return GConst.GE_INVALID_ACTION
				# 单体分支先摸 1 张（受手牌上限约束），目标手牌须严格小于摸牌后的手牌数。
				if 单体.hand_cards.size() >= _sheng_guang_single_hand_limit():
					return GConst.GE_INVALID_ACTION
			elif 模式 == 2:
				if args.size() < 2:
					return GConst.GE_INVALID_ACTION
				var x: int = int(args[1])
				if x < 1 or x > player.cross_num:
					return GConst.GE_INVALID_ACTION
				if cards.size() != x or _has_duplicate(cards):
					return GConst.GE_INVALID_ACTION
				for c: Variant in cards:
					if not player.has_hand_card(int(c)):
						return GConst.GE_INVALID_CARDID
				if dsts.is_empty() or dsts.size() > x or _has_duplicate(dsts):
					return GConst.GE_INVALID_ACTION
				var 手牌上限: int = player.hand_cards.size() - x
				if 手牌上限 < 0:
					return GConst.GE_INVALID_ACTION
				for d: Variant in dsts:
					var dp: BattlePlayer = engine.p(int(d))
					if dp == null or dp.color == player.color:
						return GConst.GE_INVALID_ACTION
					if dp.hand_cards.size() > 手牌上限:
						return GConst.GE_INVALID_ACTION
			else:
				return GConst.GE_INVALID_ACTION
		HUI_GUANG_PAO:
			if not cards.is_empty() or not dsts.is_empty() or not _hui_guang_enabled(HUI_GUANG_SIDE_FRONT):
				return GConst.GE_INVALID_ACTION
			# args 只有士气方向；额外行动固定为攻击或法术行动，不再由选项决定。
			if args.is_empty() or (int(args[0]) != 0 and int(args[0]) != 1):
				return GConst.GE_INVALID_ACTION
		HUI_GUANG_YU_HUI:
			if not cards.is_empty() or not dsts.is_empty() or not _hui_guang_enabled(HUI_GUANG_SIDE_BACK):
				return GConst.GE_INVALID_ACTION
			# 余辉没有额外行动，args 只有士气方向
			if args.size() < 1 or (int(args[0]) != 0 and int(args[0]) != 1):
				return GConst.GE_INVALID_ACTION
		_:
			return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	match int(action.get("action_id", 0)):
		SHENG_XIE_JU_BAO:
			return _sheng_xie_ju_bao(action)
		SHENG_HUANG_MO_SHI:
			return _sheng_huang_mo_shi(action)
		SHENG_GUANG_BAO_LIE:
			return _sheng_guang_bao_lie(action)
		HUI_GUANG_PAO, HUI_GUANG_YU_HUI:
			return _hui_guang_pao(action)
	return GConst.GE_INVALID_ACTION


## 圣屑飓暴：弃 2 张同系牌，用该系【圣】命格攻击牌（虚拟牌）发起一次攻击
func _sheng_xie_ju_bao(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	var dst_id: int = int(dsts[0])
	var use_cards: Array = [int(cards[0]), int(cards[1])]
	var virtual_card: int = _sheng_xie_virtual_card(Data.get_card(int(cards[0])).element_enum())
	notice_skill(SHENG_XIE_JU_BAO, [dst_id])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": use_cards, "is_real": true,
	})
	# 虚牌视为一次主动攻击：按【欺诈】同款方式播一次 Use（虚拟牌不摊牌，只播声音 / 斩击特效）。
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Use, "src_id": player.id, "dst_id": dst_id,
		"card_ids": [virtual_card], "is_real": false,
	})
	var harm: Dictionary = {
		"src": player.id, "dst": dst_id, "point": ATTACK_BASE_POINT,
		"cause": SHENG_XIE_JU_BAO, "type": GConst.HarmType.Attack,
		"card_id": virtual_card, "is_active": true,
	}
	engine.push(BattleEngine.SAttackCard.new(player.id, dst_id, virtual_card, harm))
	engine.take_from_hand(player.id, use_cards, true)
	engine.to_discard(use_cards, {"owner": player.id, "source": "hand"})
	engine._broadcast_game()
	return URGENT


## 圣煌模式：耗 2 治疗或 2 信仰 → 横置进入圣煌形态，并额外 +1 法术行动
func _sheng_huang_mo_shi(action: Dictionary) -> int:
	var args: Array = action.get("args", [])
	var choice: int = int(args[0]) if not args.is_empty() else 0
	if choice == 1:
		if player.cross_num < 2:
			return GConst.GE_INVALID_ACTION
		player.sub_cross_num(2)
	elif choice == 2:
		if _xin_yang() < 2:
			return GConst.GE_INVALID_ACTION
		_set_token(TOKEN_XIN_YANG, _xin_yang() - 2)
	else:
		return GConst.GE_INVALID_ACTION
	notice_skill(SHENG_HUANG_MO_SHI, [player.id])
	player.tap = true
	player.add_action(GConst.ActionType.Magic, SHENG_HUANG_MO_SHI, true, true)
	engine._broadcast_game()
	return SUCCESS


## 圣光爆裂：
##   模式 1：移除 1 治疗 → 摸 1 张 → 对 1 名手牌数少于你的对手造成 2 点攻击伤害 → +1 信仰。
##   模式 2：移除 X 治疗 → 弃 X 张牌 → 对最多 X 名合法对手各造成 (Y+2) 点攻击伤害 → +X 信仰。
func _sheng_guang_bao_lie(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	var args: Array = action.get("args", [])
	var 模式: int = int(args[0]) if not args.is_empty() else 0
	if 模式 == 1:
		var dst_id: int = int(dsts[0])
		var dst: BattlePlayer = engine.p(dst_id)
		if dst == null or dst.color == player.color or player.cross_num < 1:
			return GConst.GE_INVALID_ACTION
		player.sub_cross_num(1)
		_set_token(TOKEN_XIN_YANG, _xin_yang() + 1)
		notice_skill(SHENG_GUANG_BAO_LIE, [player.id, dst_id])
		engine._broadcast_game()
		engine.push_harm({
			"src": player.id, "dst": dst_id, "point": SHENG_GUANG_BAO_LIE_BASE,
			"cause": SHENG_GUANG_BAO_LIE, "type": GConst.HarmType.Attack,
		})
		# 先摸 1 张再结算伤害：后压的摸牌状态先执行（LIFO），伤害在摸牌完成后才落。
		# 【强制】仍走 push_draw，允许暗杀者【水影】这类“摸牌前”响应（已确认）。
		engine.push_draw(player.id, 1, SHENG_GUANG_BAO_LIE)
		return URGENT
	if 模式 != 2 or args.size() < 2:
		return GConst.GE_INVALID_ACTION
	var x: int = int(args[1])
	if x < 1 or x > player.cross_num or cards.size() != x:
		return GConst.GE_INVALID_ACTION
	var point: int = SHENG_GUANG_BAO_LIE_BASE
	for d: Variant in dsts:
		var dp: BattlePlayer = engine.p(int(d))
		if dp != null and dp.cross_num > 0:
			point += 1
	player.sub_cross_num(x)
	_set_token(TOKEN_XIN_YANG, _xin_yang() + x)
	engine.take_from_hand(player.id, cards)
	engine.to_discard(cards, {"owner": player.id, "source": "hand"})
	engine._log_discard(player.id, cards)
	notice_skill(SHENG_GUANG_BAO_LIE, [player.id])
	engine._broadcast_game()
	# 逆序压栈，实际结算顺序与客户端选择顺序一致。
	for i: int in range(dsts.size() - 1, -1, -1):
		engine.push_harm({
			"src": player.id, "dst": int(dsts[i]), "point": point,
			"cause": SHENG_GUANG_BAO_LIE, "type": GConst.HarmType.Attack,
		})
	return URGENT


## 圣煌辉光炮（8806）/ 圣煌余辉（8808）：
## 从圣弓开始逆时针，把每名角色的手牌调整到 min(4, 他的手牌上限) → 星杯 +1 →
## 一方士气拉平到另一方。星杯 +1 不额外扣对方士气，set_morale 也不走掉士气钩子。
## 8806 再给我方所有角色 +1 治疗、自己 +1 攻击或法术行动，然后把专属技翻面成 8808；
## 8808 没有治疗和额外行动，用完把专属技移除。
func _hui_guang_pao(action: Dictionary) -> int:
	var aid: int = int(action.get("action_id", 0))
	var 是余辉: bool = aid == HUI_GUANG_YU_HUI
	var 面: int = HUI_GUANG_SIDE_BACK if 是余辉 else HUI_GUANG_SIDE_FRONT
	if player.sheng_huang_side != 面:
		return GConst.GE_INVALID_ACTION
	if hui_guang_index < 0:
		hui_guang_index = 0
		hui_guang_draws.clear()
		notice_skill(aid, [player.id])
		engine._broadcast_game()
	if hui_guang_index >= 0:
		var ids: Array = _ids_from_self()
		while hui_guang_index < ids.size():
			var pid: int = int(ids[hui_guang_index])
			var dp: BattlePlayer = engine.p(pid)
			if dp == null:
				hui_guang_index += 1
				continue
			# 目标手牌数 = min(4, 他的手牌上限)：上限不足 4 的只补到上限。
			var diff: int = dp.hand_cards.size() - _hui_guang_target_hand(dp)
			if diff < 0:
				# 摸牌状态是 LIFO：先记下来，最后逆序压，实际就按逆时针顺序结算。
				hui_guang_draws.append({"pid": pid, "n": -diff})
				hui_guang_index += 1
				continue
			if diff == 0:
				hui_guang_index += 1
				continue
			var r: int = _request_discard(pid, diff, aid)
			if r == WAIT:
				return WAIT
			hui_guang_index += 1
		for i: int in range(hui_guang_draws.size() - 1, -1, -1):
			engine.push_draw(int(hui_guang_draws[i]["pid"]), int(hui_guang_draws[i]["n"]), aid)
		var 压了摸牌: bool = not hui_guang_draws.is_empty()
		hui_guang_draws.clear()
		var my_color: int = player.color
		var en_color: int = _enemy_color()
		var my_morale: int = engine.team_morale[my_color]
		var en_morale: int = engine.team_morale[en_color]
		var gap: int = maxi(en_morale - my_morale, 0)
		var args: Array = action.get("args", [])
		var choice: int = int(args[0]) if not args.is_empty() else 0
		engine.team_grail[my_color] += 1
		if choice == 1:
			engine.set_morale(my_color, en_morale)
		else:
			engine.set_morale(en_color, my_morale)
		_set_token(TOKEN_XIN_YANG, _xin_yang() - gap - HUI_GUANG_PAO_COST)
		if 是余辉:
			# 余辉只做手牌 / 星杯 / 士气三件事，没有治疗和额外行动，用完移除。
			player.sheng_huang_side = HUI_GUANG_SIDE_REMOVED
		else:
			for pid2: int in _all_allies():
				施加治疗(pid2, 1)
			player.sheng_huang_side = HUI_GUANG_SIDE_BACK
			# 额外行动固定放行攻击或法术：玩家进入额外行动阶段后自己决定，
			# 不再由本技能的选项预先选攻击/法术。
			player.add_action(GConst.ActionType.AttackMagic, HUI_GUANG_PAO, true, true)
		engine._broadcast_game()
		if engine.team_grail[my_color] >= GConst.GRAIL_WIN:
			engine._game_over(my_color)
		hui_guang_index = -1
		# 压了补牌就必须 URGENT：先补完手牌，再压行动结束响应 / 进入额外行动
		if 压了摸牌:
			return URGENT
	return SUCCESS
