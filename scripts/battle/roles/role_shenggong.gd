extends BattleRole
## 圣弓（roleID 37）—— 移植自服务端 role/ShengGong.cpp
## 指示物：tokens[0] = 信仰（上限见角色表）；治疗上限 3
## 技能：天之弓（3701，被动：主动攻击使用的牌非【圣】命格时本次伤害 -1）、
##       圣屑飓暴（3702，法术：弃 2 张同系牌，以该系【圣】命格攻击牌对目标发起一次攻击）、
##       圣屑飓暴·未命中（37021，响应：耗 X 治疗，目标弃 X 张牌或摸 X 张牌）、
##       圣煌模式（3703，法术：耗 2 治疗或 2 信仰 → 横置并额外 +1 法术行动）、
##       圣光爆裂（3704，法术：耗 X 治疗并 +1 信仰，对目标造成 2 点（＋目标中有治疗者数）
##                 攻击伤害，然后自身弃 X 张牌或摸 X 张牌）、
##       圣流星弹（3705，响应：特殊行动时若横置则重置并 +1 治疗）、
##       圣流星弹·攻击（37051，响应：主动攻击宣告后耗 1 治疗或 1 信仰，目标 +1 治疗）、
##       圣流星弹·命中（37052，被动：主动攻击命中且为【圣】命格时 +1 信仰）、
##       圣煌辉光炮（3706，法术：全场手牌调整到 4 张，星杯 +1，并使双方士气相等）、
##       自动填充（3707，回合结束：耗 1 能量换成信仰或治疗）
##
## 说明：
## - 圣流星弹（3705）在 p_before_special 中触发（引擎在当前玩家发动特殊行动前调用该钩子；
##   服务端同在特殊行动前触发，且只做横置解除与恢复治疗，不需要玩家输入）。
## - 服务端 v_magic_skill 对法术技能不做任何校验，此处按客户端规则补最小校验（动作号、牌数、目标）。

const TIAN_ZHI_GONG: int = 3701
const SHENG_XIE_JU_BAO: int = 3702
const SHENG_XIE_MISS: int = 37021
const SHENG_HUANG_MO_SHI: int = 3703
const SHENG_GUANG_BAO_LIE: int = 3704
const SHENG_LIU_XING_DAN: int = 3705
const SHENG_LIU_XING_ATK: int = 37051
const SHENG_LIU_XING_HIT: int = 37052
const HUI_GUANG_PAO: int = 3706
const ZI_DONG_TIAN_CHONG: int = 3707

## 本引擎自有的分步标记（服务端把子步骤实现为压栈状态，此处只用 step 记录进度）
const SHENG_XIE_MISS_DISCARD: int = 37022   # 圣屑飓暴·未命中：请目标弃牌

const TOKEN_XIN_YANG: int = 0
const CROSS_MAX_SHENG_GONG: int = 3
const SHENG_GUANG_BAO_LIE_BASE: int = 2     # 圣光爆裂基础伤害
const ATTACK_BASE_POINT: int = 2            # 攻击牌基础伤害
const HUI_GUANG_KEEP: int = 4               # 圣煌辉光炮：全场手牌调整到 4 张
const HUI_GUANG_PAO_COST: int = 5           # 圣煌辉光炮：信仰消耗为士气差 + 5

var no_tian_chong: bool = false             # 本回合是否进行过特殊行动（跳过自动填充）

## 圣屑飓暴·未命中的中间状态
var sheng_xie_miss_dst: int = -1
var sheng_xie_miss_num: int = 0

## 圣煌辉光炮的进度（-1 表示未开始；主动法术技能不在钩子轮次内，step 不会被重置）
var hui_guang_index: int = -1


func setup(p: BattlePlayer, e: BattleEngine) -> void:
	super.setup(p, e)
	p.cross_max = CROSS_MAX_SHENG_GONG


func available_skills() -> Array:
	var out: Array = []
	# 圣屑飓暴要弃 2 张同系牌：只让「手里该系不少于 2 张、且该系有【圣】命格攻击牌」的牌可点，
	# 界面据此把同系孤张与没有虚拟牌的系置灰（与 v_magic_skill 的校验一致）
	var 同系牌: Array[int] = _sheng_xie_hand_ids()
	if not 同系牌.is_empty():
		out.append({"type": GConst.ActionType.MagicSkill, "id": SHENG_XIE_JU_BAO, "need_card": 2, "need_target": 1,
			"cards": 同系牌})
	if (_xin_yang() > 1 or player.cross_num > 1) and not player.tap:
		out.append({"type": GConst.ActionType.MagicSkill, "id": SHENG_HUANG_MO_SHI, "need_card": 0, "need_target": 0})
	if player.cross_num > 0 and player.tap:
		# v_magic_skill 只校验治疗数与横置，不校验任何牌，故不强制选牌。
		# 治疗数与「弃/摸」原本由原版客户端拼成 args=[1或2, 治疗数]，通用客户端点「确定」只回 args=[]，
		# 故改用 arg_choices：每个候选点数一个按钮，点它即回完整 args（服务端照旧读 args[0]/args[1]）。
		out.append({"type": GConst.ActionType.MagicSkill, "id": SHENG_GUANG_BAO_LIE, "need_card": 0, "need_target": 1,
			"arg_choices": _sheng_guang_bao_lie_choices()})
	# 圣煌辉光炮：仅当我方士气低于敌方且信仰足够支付（士气差 + 5）时可选（客户端同此判定）
	var en_color: int = GConst.BLUE if player.color == GConst.RED else GConst.RED
	var my_morale: int = engine.team_morale[player.color]
	var en_morale: int = engine.team_morale[en_color]
	if my_morale < en_morale and _xin_yang() >= (en_morale - my_morale) + HUI_GUANG_PAO_COST:
		# v_magic_skill 不校验任何牌/目标；执行体 _hui_guang_pao 用 args[0] 决定把哪一方士气拉到与另一方相等
		out.append({"type": GConst.ActionType.MagicSkill, "id": HUI_GUANG_PAO, "need_card": 0, "need_target": 0,
			"arg_choices": [
				{"text": "敌方士气拉平到我方（提升敌方）", "args": [0]},
				{"text": "我方士气拉平到敌方（降低我方）", "args": [1]},
			]})
	return out


## 圣光爆裂的参数选项：治疗数 X（1..当前治疗）各对应「弃 X 张」或「摸 X 张」；
## args = [1, X] 为弃、[2, X] 为摸，与服务端 _sheng_guang_bao_lie 读取的 args[0]/args[1] 一致。
## 每项 need_target=1：本技能要选目标，客户端需先选好目标才让点该选项按钮。
func _sheng_guang_bao_lie_choices() -> Array:
	var out: Array = []
	for x: int in range(1, player.cross_num + 1):
		out.append({"text": "弃 %d 张牌" % x, "args": [1, x], "need_target": 1})
		out.append({"text": "摸 %d 张牌" % x, "args": [2, x], "need_target": 1})
	return out


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
	engine.to_discard(chosen)


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
	engine.to_discard(chosen)
	engine._broadcast_game()
	return SUCCESS


## 圣煌辉光炮的处理顺序：从自己开始、沿行动顺序绕一圈（自己最先）
## 服务端把目标 reverse 后逐个压栈，而状态是栈（LIFO）又把它翻回原序，实际就是「自己 → 下家 → …」
func _ids_from_self() -> Array:
	var ids: Array = []
	var cur: int = player.id
	var guard: int = engine.order.size() + 1
	while guard > 0:
		ids.append(cur)
		cur = engine.next_id(cur)
		guard -= 1
		if cur == player.id:
			break
	return ids


func p_before_turn_begin(_ctx: Dictionary) -> int:
	no_tian_chong = false
	return SUCCESS


## 【天之弓 / 圣流星弹·攻击】的推进阶段（0＝还没开始 / TIAN_ZHI_GONG＝天之弓减伤 /
## SHENG_LIU_XING_ATK＝在问是否发动圣流星弹·攻击）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨若干次询问，
## 中途一旦被别的钩子轮次（改手牌 / 盖牌 / 基础效果 / 横置…）插进来，step 就被抹掉、流程退回第 0 步。
## 每次自己主动宣告攻击（p_timeline_1）触发一次，收尾清回 0（留 STEP_DONE 会让下一次触发不再发动）
var _timeline_1_step: int = 0


# ============================================================
# 攻击宣告后（timeline_1）：天之弓（3701）→ 圣流星弹·攻击（37051）
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
		if card != null and card.property_enum() != GConst.CardProperty.Holy:
			var harm: Dictionary = ctx.get("harm", {})
			harm["point"] = int(harm.get("point", 0)) - 1
		_timeline_1_step = SHENG_LIU_XING_ATK
	if _timeline_1_step == SHENG_LIU_XING_ATK:
		var r: int = _sheng_liu_xing_atk()
		if r == WAIT:
			return WAIT
		_timeline_1_step = 0
	return SUCCESS


## 圣流星弹·攻击：耗 1 治疗或 1 信仰，令目标 +1 治疗
func _sheng_liu_xing_atk() -> int:
	if not player.tap or (player.cross_num == 0 and _xin_yang() == 0):
		return SUCCESS
	if not engine.has_reply():
		# 两条路径做成选项（value 1=耗治疗、2=耗信仰），只列当前真有那种资源的项；
		# 「取消」回空 args＝不发动（通用客户端不再拿 0 当取消）
		var 选项: Array = []
		if player.cross_num > 0:
			选项.append({"value": 1, "label": "移除 1 点治疗，令目标 +1 治疗"})
		if _xin_yang() > 0:
			选项.append({"value": 2, "label": "移除 1 点信仰，令目标 +1 治疗"})
		询问(player.id, SHENG_LIU_XING_ATK, 0, 1, GConst.CardSource.Hand, 选项)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	var dsts: Array = r.get("dst_ids", [])
	var choice: int = int(args[0]) if not args.is_empty() else 0
	if choice <= 0 or dsts.is_empty():
		return SUCCESS
	if choice == 1:
		player.sub_cross_num(1)
	else:
		_set_token(TOKEN_XIN_YANG, _xin_yang() - 1)
	var dst: BattlePlayer = engine.p(int(dsts[0]))
	if dst != null:
		施加治疗(dst.id, 1)
	notice_skill(SHENG_LIU_XING_ATK, dsts)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 主动攻击命中后（timeline_2_hit）：圣流星弹·命中（37052）
# ============================================================
func p_timeline_2_hit(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id or not bool(ctx.get("is_active", false)):
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	step = STEP_DONE
	var card: GCard = Data.get_card(int(ctx.get("card_id", -1)))
	if card != null and card.property_enum() == GConst.CardProperty.Holy:
		notice_skill(SHENG_LIU_XING_HIT, [player.id])
		_set_token(TOKEN_XIN_YANG, _xin_yang() + 1)
		engine._broadcast_game()
	return SUCCESS


# ============================================================
# 主动攻击未命中后（timeline_2_miss）：圣屑飓暴·未命中（37021）
# ============================================================
## 圣屑飓暴·未命中的参数选项：治疗数 X（1..当前治疗）各对应「弃 X 张」或「摸 X 张」。
## 原版用两维 args（[弃=1/摸=2, 治疗数]），通用客户端只回一维 args，故把「弃/摸 + 张数」编码进选项值：
## value 1..N＝弃 N 张，value N+1..2N＝摸 N 张（N=当前治疗数），服务端再解码回 choice 与 num。
func _sheng_xie_miss_choices() -> Array:
	var out: Array = []
	var n: int = player.cross_num
	for x: int in range(1, n + 1):
		out.append({"value": x, "label": "弃 %d 张牌" % x})
	for x: int in range(1, n + 1):
		out.append({"value": n + x, "label": "摸 %d 张牌" % x})
	return out


## 【圣屑飓暴·未命中】的推进阶段（0＝还没开始 / SHENG_XIE_MISS＝在问弃/摸与目标 /
## SHENG_XIE_MISS_DISCARD＝在请目标弃牌）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨若干次询问，
## 中途一旦被别的钩子轮次（改手牌 / 盖牌 / 基础效果 / 横置…）插进来，step 就被抹掉、流程退回第 0 步。
## 每次圣屑飓暴未命中（p_timeline_2_miss）触发一次，收尾清回 0（留 STEP_DONE 会让下一次触发不再发动）
var _miss_step: int = 0


func p_timeline_2_miss(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	if _miss_step >= STEP_DONE:
		return SUCCESS
	if _miss_step == 0:
		_miss_step = SHENG_XIE_MISS
	if _miss_step == SHENG_XIE_MISS:
		if not engine.has_reply():
			# 序号 1：第 0 条提示是「叫别人弃牌」用的，这步「指定谁弃牌/摸牌」读第 1 条。
			# 治疗数与「弃/摸」做成选项（见 _sheng_xie_miss_choices），服务端读 args[0] 解码。
			询问(player.id, SHENG_XIE_MISS, 0, 1, GConst.CardSource.Hand, _sheng_xie_miss_choices(), 0, "", [], true, 1)
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		var args: Array = r.get("args", [])
		var dsts: Array = r.get("dst_ids", [])
		# 选项值解码回「弃/摸」与张数（等价于原版 args=[弃=1/摸=2, 治疗数]）
		var value: int = int(args[0]) if not args.is_empty() else 0
		var 治疗数: int = player.cross_num
		var choice: int = 0
		var num: int = 0
		if value > 0 and 治疗数 > 0:
			if value <= 治疗数:
				choice = 1
				num = value
			else:
				choice = 2
				num = value - 治疗数
		if choice <= 0 or num <= 0 or num > 治疗数 or dsts.is_empty():
			_miss_step = 0
			return SUCCESS
		sheng_xie_miss_dst = int(dsts[0])
		sheng_xie_miss_num = num
		player.sub_cross_num(num)
		notice_skill(SHENG_XIE_MISS, dsts)
		engine._broadcast_game()
		if choice == 1:
			_miss_step = SHENG_XIE_MISS_DISCARD
		else:
			engine.push_draw(sheng_xie_miss_dst, num)
			engine._broadcast_game()
			_miss_step = 0
	if _miss_step == SHENG_XIE_MISS_DISCARD:
		var r2: int = _request_discard(sheng_xie_miss_dst, sheng_xie_miss_num, SHENG_XIE_MISS)
		if r2 == WAIT:
			return WAIT
		_miss_step = 0
	return SUCCESS


# ============================================================
# 特殊行动前：圣流星弹（3705）——横置时重置并 +1 治疗，且本回合跳过自动填充
# ============================================================
func p_before_special(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	# 服务端在本钩子中无条件置位（无论是否横置）
	no_tian_chong = true
	if not player.tap:
		return SUCCESS
	notice_skill(SHENG_LIU_XING_DAN, [player.id])
	player.tap = false
	施加治疗(player.id, 1)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 回合结束：自动填充（3707）
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
	if not engine.has_reply():
		# 四种转换各做一个选项（value 1~4，与服务端 match 分支一一对应）；
		# 「取消」回空 args＝走服务端的超时兜底分支（choice 0）
		询问(player.id, ZI_DONG_TIAN_CHONG, 0, 0, GConst.CardSource.Hand, [
			{"value": 1, "label": "1 宝石 → 1 水晶 + 2 信仰"},
			{"value": 2, "label": "1 宝石 → 1 水晶 + 2 治疗"},
			{"value": 3, "label": "1 水晶（无则 1 宝石）→ 1 信仰"},
			{"value": 4, "label": "1 水晶（无则 1 宝石）→ 1 治疗"},
		])
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	var args: Array = r.get("args", [])
	var choice: int = int(args[0]) if not args.is_empty() else 0
	if choice == 0:
		# 超时/取消兜底：服务端超时分支（有水晶则 -1 水晶 +1 信仰，否则 -1 宝石 +1 水晶 +2 信仰）
		notice_skill(ZI_DONG_TIAN_CHONG, [player.id])
		if player.crystal > 0:
			player.set_crystal(player.crystal - 1)
			_set_token(TOKEN_XIN_YANG, _xin_yang() + 1)
		else:
			player.set_gem(player.gem - 1)
			player.set_crystal(player.crystal + 1)
			_set_token(TOKEN_XIN_YANG, _xin_yang() + 2)
		engine._broadcast_game()
		return SUCCESS
	if choice < 1 or choice > 4:
		return SUCCESS
	notice_skill(ZI_DONG_TIAN_CHONG, [player.id])
	match choice:
		1:
			player.set_gem(player.gem - 1)
			player.set_crystal(player.crystal + 1)
			_set_token(TOKEN_XIN_YANG, _xin_yang() + 2)
		2:
			player.set_gem(player.gem - 1)
			player.set_crystal(player.crystal + 1)
			施加治疗(player.id, 2)
		3:
			if player.crystal > 0:
				player.set_crystal(player.crystal - 1)
			else:
				player.set_gem(player.gem - 1)
			_set_token(TOKEN_XIN_YANG, _xin_yang() + 1)
		4:
			if player.crystal > 0:
				player.set_crystal(player.crystal - 1)
			else:
				player.set_gem(player.gem - 1)
			施加治疗(player.id, 1)
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
	match int(action.get("action_id", 0)):
		SHENG_XIE_JU_BAO:
			# 弃 2 张同系手牌，虚拟牌（该系【圣】命格攻击牌）由服务端按元素自己取，客户端不用传
			if cards.size() != 2 or dsts.is_empty():
				return GConst.GE_INVALID_ACTION
			if not player.has_hand_card(int(cards[0])) or not player.has_hand_card(int(cards[1])):
				return GConst.GE_INVALID_ACTION
			if not _same_element(int(cards[0]), int(cards[1])):
				return GConst.GE_INVALID_CARDID
			var first: GCard = Data.get_card(int(cards[0]))
			if first == null or _sheng_xie_virtual_card(first.element_enum()) < 0:
				return GConst.GE_INVALID_CARDID
		SHENG_HUANG_MO_SHI:
			# 技能要横置自己，已经横置就不能再发动（客户端门槛同此，这里补齐服务端漏掉的一条）
			if player.tap or (player.cross_num < 2 and _xin_yang() < 2):
				return GConst.GE_INVALID_ACTION
		SHENG_GUANG_BAO_LIE:
			if player.cross_num < 1 or not player.tap:
				return GConst.GE_INVALID_ACTION
		HUI_GUANG_PAO:
			pass
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
		HUI_GUANG_PAO:
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
	var harm: Dictionary = {
		"src": player.id, "dst": dst_id, "point": ATTACK_BASE_POINT,
		"cause": SHENG_XIE_JU_BAO, "type": GConst.HarmType.Attack,
		"card_id": virtual_card, "is_active": true,
	}
	engine.push(BattleEngine.SAttackCard.new(player.id, dst_id, virtual_card, harm))
	engine.take_from_hand(player.id, use_cards, true)
	engine.to_discard(use_cards)
	engine._broadcast_game()
	return URGENT


## 圣煌模式：耗 2 治疗或 2 信仰 → 横置并额外 +1 法术行动
func _sheng_huang_mo_shi(action: Dictionary) -> int:
	var args: Array = action.get("args", [])
	var choice: int = int(args[0]) if not args.is_empty() else 0
	notice_skill(SHENG_HUANG_MO_SHI, [player.id])
	if choice == 1:
		player.sub_cross_num(2)
	else:
		_set_token(TOKEN_XIN_YANG, _xin_yang() - 2)
	player.tap = true
	player.add_action(GConst.ActionType.Magic, SHENG_HUANG_MO_SHI, true)
	engine._broadcast_game()
	return SUCCESS


## 圣光爆裂：耗 X 治疗并 +1 信仰，对目标造成 2（＋目标中有治疗者数）点攻击伤害，再弃/摸 X 张牌
func _sheng_guang_bao_lie(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	var args: Array = action.get("args", [])
	var howmany: int = int(args[1]) if args.size() > 1 else 0
	var choice: int = int(args[0]) if not args.is_empty() else 0
	notice_skill(SHENG_GUANG_BAO_LIE, [player.id])
	var point: int = SHENG_GUANG_BAO_LIE_BASE
	for d: Variant in dsts:
		var dp: BattlePlayer = engine.p(int(d))
		if dp != null and dp.cross_num > 0:
			point += 1
	_set_token(TOKEN_XIN_YANG, _xin_yang() + 1)
	player.sub_cross_num(howmany)
	engine._broadcast_game()
	# 按座位逆序绕一圈（服务端从自己上家开始），对选中目标造成伤害
	var cur: int = player.pre_id
	for _i: int in range(engine.order.size()):
		var cp: BattlePlayer = engine.p(cur)
		if cp == null:
			break
		if dsts.has(cur):
			engine.push_harm({
				"src": player.id, "dst": cur, "point": point,
				"cause": SHENG_GUANG_BAO_LIE, "type": GConst.HarmType.Attack,
			})
		cur = cp.pre_id
	if choice == 1:
		_discard_own(cards, howmany)
	else:
		engine.push_draw(player.id, howmany)
	engine._broadcast_game()
	return URGENT


## 圣煌辉光炮：全场手牌调整到 4 张，星杯 +1，并使双方士气相等（信仰消耗为士气差 + 5）
func _hui_guang_pao(action: Dictionary) -> int:
	if hui_guang_index < 0:
		hui_guang_index = 0
		notice_skill(HUI_GUANG_PAO, [player.id])
		engine._broadcast_game()
	if hui_guang_index >= 0:
		var ids: Array = _ids_from_self()
		while hui_guang_index < ids.size():
			var pid: int = int(ids[hui_guang_index])
			var dp: BattlePlayer = engine.p(pid)
			if dp == null:
				hui_guang_index += 1
				continue
			var diff: int = dp.hand_cards.size() - HUI_GUANG_KEEP
			if diff < 0:
				engine.push_draw(pid, -diff)
				hui_guang_index += 1
				continue
			if diff == 0:
				hui_guang_index += 1
				continue
			var r: int = _request_discard(pid, diff, HUI_GUANG_PAO)
			if r == WAIT:
				return WAIT
			hui_guang_index += 1
		var my_color: int = player.color
		var en_color: int = GConst.BLUE if my_color == GConst.RED else GConst.RED
		var my_morale: int = engine.team_morale[my_color]
		var en_morale: int = engine.team_morale[en_color]
		var gap: int = absi(my_morale - en_morale)
		var args: Array = action.get("args", [])
		var choice: int = int(args[0]) if not args.is_empty() else 0
		if choice == 1:
			engine.set_morale(my_color, en_morale)
		else:
			engine.set_morale(en_color, my_morale)
		engine.team_grail[my_color] += 1
		_set_token(TOKEN_XIN_YANG, _xin_yang() - gap - HUI_GUANG_PAO_COST)
		engine._broadcast_game()
		if engine.team_grail[my_color] >= GConst.GRAIL_WIN:
			engine._game_over(my_color)
		hui_guang_index = -1
	return SUCCESS
