extends BattleRole
## 英灵人形（roleID 27）—— 移植自服务端 role/YingLingRenXing.cpp
## 技能：怒火压制（响应 2704：主动攻击未命中时翻转 1 个【战纹】为【魔纹】）、
##       魔纹融合（响应 2701：主动攻击未命中时翻转 1 个【魔纹】，弃 X 张异系牌对目标造成 (X-1) 点法术伤害；
##         两者在同一次未命中里二选一，不能同时发动）、
##       战纹碎击（响应 2703：主动攻击命中时，翻转 1 个【战纹】，弃 X 张同系牌使本次伤害 +(X-1)）、
##       符文改造（启动 2705：宝石 ×1 转为【蓄势迸发形态】，手牌上限 +1、摸 1 张牌并重排【战纹】/【魔纹】）、
##       双重回响（响应 2706：对目标造成伤害时，能量 ×1 对另一目标造成等量（最高 3）法术伤害，且不造成士气下降）
## 【战纹】tokens[0]、【魔纹】tokens[1】，上限见角色表；【蓄势迸发形态】用 tap 表示。

const NU_HUO_YA_ZHI: int = 2704       # 怒火压制（响应）
const MO_WEN_RONG_HE: int = 2701      # 魔纹融合（响应）
const ZHAN_WEN_SUI_JI: int = 2703     # 战纹碎击（响应）
## 怒火压制／魔纹融合 的开局二选一
const CHOICE_NU_HUO_YA_ZHI: int = 1
const CHOICE_MO_WEN_RONG_HE: int = 2
## 怒火压制／魔纹融合 的流程阶段：第一段二选一 → 第二段魔纹融合的翻转档
const 阶段_二选一: int = 1
const 阶段_魔纹选择: int = 2
## 角色内部流程返回值（只在 p_timeline_2_miss 里用，不交给引擎）：
##   第一段选中魔纹融合＝进第二段 / 第二段取消＝退回第一段
const 进入魔纹子项: int = 10
const 返回二选一: int = 11
const FU_WEN_GAI_ZAO: int = 2705      # 符文改造（启动）
const SHUANG_CHONG_HUI_XIANG: int = 2706 # 双重回响（响应）

const TOKEN_ZHAN_WEN: int = 0         # 「战纹」指示物下标
const TOKEN_MO_WEN: int = 1           # 「魔纹」指示物下标
const FU_WEN_HAND_ADD: int = 1        # 符文改造期间手牌上限 +1

enum ElementKind { Invalid = 0, AllDifferent = 1, AllSame = 2 }

var shuangChongHuiXiangUsed: bool = false


func setup(p: BattlePlayer, e: BattleEngine) -> void:
	super.setup(p, e)
	# 【战纹】开局就带 3 点（表里只记上限，初始数量在这里补）
	p.tokens[TOKEN_ZHAN_WEN]["num"] = 3


## 行动阶段可发动的技能：【符文改造】为「启动」，不消耗行动
## （is_free_skill 认可，发动后引擎重新进入行动阶段让玩家继续本回合行动）
func available_skills() -> Array:
	var out: Array = []
	# 符文改造：有宝石时才能发动（耗 1 宝石并横置进入蓄势迸发形态、手牌上限 +1、摸 1 张）；
	# 重排【战纹】/【魔纹】的取值做成参数按钮，点哪个即以该值作为 args[0] 提交
	out.append({"type": GConst.ActionType.SpecialSkill, "id": FU_WEN_GAI_ZAO,
		"need_card": 0, "need_target": 0, "arg_choices": _fu_wen_gai_zao_choices(),
		"enabled": player.gem > 0})
	return out


## 【符文改造】为「启动」：不消耗本回合行动，发动后行动阶段照旧继续
func is_free_skill(skill_id: int) -> bool:
	return skill_id == FU_WEN_GAI_ZAO


# ============================================================
# 指示物：战纹 / 魔纹
# ============================================================
func _zhan_wen() -> int:
	return int(player.tokens[TOKEN_ZHAN_WEN]["num"])


func _mo_wen() -> int:
	return int(player.tokens[TOKEN_MO_WEN]["num"])


func _wen_max() -> int:
	return int(player.tokens[TOKEN_ZHAN_WEN]["max"])


func _set_zhan_wen(v: int) -> void:
	player.tokens[TOKEN_ZHAN_WEN]["num"] = clampi(v, 0, _wen_max())


func _set_mo_wen(v: int) -> void:
	player.tokens[TOKEN_MO_WEN]["num"] = clampi(v, 0, _wen_max())


# ============================================================
# 回合开始
# ============================================================
func p_turn_begin(_ctx: Dictionary) -> int:
	shuangChongHuiXiangUsed = false
	return SUCCESS


## 符文改造的重排【战纹】/【魔纹】选项（两者之和为 3）：每项一个按钮，
## 点哪个即以该项 args[0]（要保留的【战纹】数）作为技能参数提交
func _fu_wen_gai_zao_choices() -> Array:
	var out: Array = []
	for n: int in range(0, _wen_max() + 1):
		out.append({"text": 提示(FU_WEN_GAI_ZAO, 0, n, -1, {"n2": _wen_max() - n}), "args": [n]})
	return out


# ============================================================
# 启动技能（行动阶段按钮）：符文改造
# （「每回合只能发动一个启动技能」由引擎统一把关，这里只校验本技能自己的条件）
# ============================================================
func v_special_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != FU_WEN_GAI_ZAO:
		return GConst.GE_INVALID_ACTION
	# 宝石不足 1 点：不能发动
	if player.gem < 1:
		return GConst.GE_INVALID_ACTION
	var args: Array = action.get("args", [])
	# 对照原版 FuWenGaiZaoToken 的超时分支：没给重排值（超时）按 1 处理，发动照旧成立
	if not args.is_empty() and (int(args[0]) < 0 or int(args[0]) > _wen_max()):
		return GConst.GE_INVALID_ARGUMENT
	return GConst.GE_SUCCESS


func p_special_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != FU_WEN_GAI_ZAO:
		return GConst.GE_INVALID_ACTION
	_apply_fu_wen_gai_zao(action)
	return SUCCESS


## 符文改造：消耗 1 宝石转为蓄势迸发形态，手牌上限 +1 并摸 1 张牌，再按所选值重排【战纹】/【魔纹】
func _apply_fu_wen_gai_zao(action: Dictionary) -> void:
	var args: Array = action.get("args", [])
	# 对照原版：重排值缺省（超时）时按 1 处理
	var num: int = int(args[0]) if not args.is_empty() else 1
	notice_skill(FU_WEN_GAI_ZAO, [player.id])
	player.boot_skill_used = true
	player.set_gem(player.gem - 1)
	player.hand_cards_max += FU_WEN_HAND_ADD
	engine.push_draw(player.id, 1)
	engine.set_tap(player.id, true)
	_set_zhan_wen(num)
	_set_mo_wen(_wen_max() - _zhan_wen())
	engine._broadcast_game()


# ============================================================
# 主动攻击命中后：战纹碎击
# ============================================================
## 【战纹碎击】的推进阶段（0＝还没开始 / ZHAN_WEN_SUI_JI＝在问弃牌与额外翻转）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨一次询问，
## 中途一旦被别的钩子轮次（改手牌 / 盖牌 / 基础效果 / 横置…）插进来，step 就被抹掉、流程退回第 0 步。
## 每次自己主动攻击命中（p_timeline_2_hit）触发一次，收尾清回 0（留 STEP_DONE 会让下一次触发不再发动）。
## 结算完会返回 URGENT（压入了展示 / 弃牌后的伤势推进），引擎在 URGENT 挂起后会重入本钩子：
## 这里仍旧借引擎 step 记「本轮已完成」来挡住重入（自有变量已清回 0，不影响这次拦截）。
var _zhan_wen_step: int = 0


func p_timeline_2_hit(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	# 只要还有【战纹】、且手上凑得出 2 张牌就问（同系牌至少要 2 张，手牌不足 2 张根本选不出来）
	if _zhan_wen() == 0 or player.hand_count() < 2:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if _zhan_wen_step == 0:
		_zhan_wen_step = ZHAN_WEN_SUI_JI
	if _zhan_wen_step == ZHAN_WEN_SUI_JI:
		var r: int = _zhan_wen_sui_ji(ctx)
		if r == WAIT:
			return WAIT
		_zhan_wen_step = 0
		if r == URGENT:
			step = STEP_DONE
			return URGENT
	return SUCCESS


## 战纹碎击：翻转 1 个战纹，弃 X 张同系牌，本次伤害 +(X-1)（可额外翻转 Y 个战纹，再 +Y）
func _zhan_wen_sui_ji(ctx: Dictionary) -> int:
	if not engine.has_reply():
		# 弃 X 张同系牌（X≥2）：上限放到手牌数，并让客户端只让同系牌可点
		# 额外翻转的【战纹】数做成选项按钮：value = 1 + Y（Y=0 表示不额外翻转）。
		# 三档固定摆出；当前形态 / 战纹不够的档置灰，不再隐藏。
		var 选项: Array = []
		for y: int in range(0, 3):
			var 可用: bool = y == 0 or (player.tap and _zhan_wen() >= y + 1)
			var 名: String = 提示(ZHAN_WEN_SUI_JI, 1) if y == 0 else 提示(ZHAN_WEN_SUI_JI, 2, y)
			选项.append({"value": y + 1, "label": 名, "enabled": 可用})
		# 目标与「本次攻击原本的伤害」一并下发：客户端在目标头像上现算
		# 「原伤害 + 弃牌加伤」，随玩家选 / 退牌实时变（本次 need_target 是 0，头像本来就点不动）
		var dst: int = int(ctx.get("dst", -1))
		var 本次伤害: Dictionary = ctx.get("harm", {})
		# 座位号从 0 起：0 号也是合法目标，判「没取到」只能用 < 0
		var 伤害目标: Array = [dst] if dst >= 0 else []
		询问(player.id, ZHAN_WEN_SUI_JI, 2, 0, GConst.CardSource.Hand, 选项, player.hand_count(), "same",
			[], true, 0, -1, 伤害目标, -1, {}, int(本次伤害.get("point", 0)))
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) < 1:
		return SUCCESS
	var addition: int = int(args[0]) - 1
	var cards: Array = r.get("card_ids", [])
	if _zhan_wen() < 1 or cards.size() < 2:
		return GConst.GE_INVALID_ARGUMENT
	if _element_check(cards) != ElementKind.AllSame or not _has_cards(cards):
		return GConst.GE_INVALID_CARDID
	_set_zhan_wen(_zhan_wen() - 1)
	_set_mo_wen(_mo_wen() + 1)
	if addition > 0:
		if _zhan_wen() < addition:
			return GConst.GE_INVALID_ARGUMENT
		_set_zhan_wen(_zhan_wen() - addition)
		_set_mo_wen(_mo_wen() + addition)
	notice_skill(ZHAN_WEN_SUI_JI, [int(ctx.get("dst", -1))])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": cards, "is_real": true,
	})
	engine.take_from_hand(player.id, cards, true)
	engine.to_discard(cards)
	var harm: Dictionary = ctx.get("harm", {})
	harm["point"] = int(harm.get("point", 0)) + cards.size() - 1 + addition
	engine._broadcast_game()
	return URGENT


# ============================================================
# 主动攻击未命中后：怒火压制 / 魔纹融合（两段式：先二选一，再选魔纹融合的翻转档）
# ============================================================
## 推进阶段：0＝还没开始 / 阶段_二选一＝在问「怒火压制 / 魔纹融合」 /
## 阶段_魔纹选择＝在问魔纹融合的翻转档（这一段取消＝退回二选一，不算放弃整次响应）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨两次询问，
## 中途一旦被别的钩子轮次（改手牌 / 盖牌 / 基础效果 / 横置…）插进来，step 就被抹掉、流程退回第 0 步。
## 每次自己主动攻击未命中（p_timeline_2_miss）触发一次，收尾清回 0（留 STEP_DONE 会让下一次触发不再发动）。
## 魔纹融合分支会返回 URGENT（压入了法术伤害），引擎在 URGENT 挂起后会重入本钩子：
## 这里仍旧借引擎 step 记「本轮已完成」来挡住重入（自有变量已清回 0，不影响这次拦截）。
var _nu_huo_step: int = 0


func p_timeline_2_miss(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if _nu_huo_step == 0:
		_nu_huo_step = 阶段_二选一
	var r: int = SUCCESS
	var r2: int = SUCCESS
	while true:
		if _nu_huo_step == 阶段_二选一:
			r = _nu_huo_xuan(ctx)
			if r == WAIT:
				return WAIT
			if r == 进入魔纹子项:
				_nu_huo_step = 阶段_魔纹选择
				continue
			_nu_huo_step = 0
			if r == URGENT:
				step = STEP_DONE
			return r
		r2 = _nu_huo_mo_wen_xuan(ctx)
		if r2 == WAIT:
			return WAIT
		if r2 == 返回二选一:
			_nu_huo_step = 阶段_二选一
			continue
		_nu_huo_step = 0
		if r2 == URGENT:
			step = STEP_DONE
		return r2
	# while true 里每条分支都会 return；这一行只为满足 GDScript 的「所有路径都有返回值」检查
	return SUCCESS


## 第一段：怒火压制（2704）/ 魔纹融合（2701）二选一，二级技能栏里只摆这两颗。
## 选魔纹融合只是「进第二段」，这里不弃牌、也不结算；选怒火压制当场结算。
## 询问挂在魔纹融合（2701）名下（它带着伤害 cause）；怒火压制分支按自己的号 2704 上报发动通知。
func _nu_huo_xuan(ctx: Dictionary) -> int:
	var dst_id: int = int(ctx.get("dst", -1))
	var 魔纹可用: bool = _mo_wen() >= 1 and player.hand_count() >= 2
	if not engine.has_reply():
		var 选项: Array = [
			{"value": CHOICE_NU_HUO_YA_ZHI, "label": GConst.skill_desc_name(NU_HUO_YA_ZHI),
				"skill_id": NU_HUO_YA_ZHI, "need_card": 0, "enabled": _zhan_wen() >= 1},
			{"value": CHOICE_MO_WEN_RONG_HE, "label": 提示原文(MO_WEN_RONG_HE, 1),
				"skill_id": MO_WEN_RONG_HE, "need_card": 0, "enabled": 魔纹可用},
		]
		var 伤害目标: Array = [dst_id] if dst_id >= 0 else []
		engine.ask_skill(player.id, MO_WEN_RONG_HE, 0, 0, GConst.CardSource.Hand, 选项,
			0, "diff", [], true, 提示原文(MO_WEN_RONG_HE, 0), 伤害目标)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	var choice: int = int(args[0]) if not args.is_empty() else 0
	if choice == CHOICE_NU_HUO_YA_ZHI:
		if _zhan_wen() < 1:
			return SUCCESS
		notice_skill(NU_HUO_YA_ZHI, [dst_id])
		_set_zhan_wen(_zhan_wen() - 1)
		_set_mo_wen(_mo_wen() + 1)
		engine._broadcast_game()
		return SUCCESS
	if choice == CHOICE_MO_WEN_RONG_HE:
		return 进入魔纹子项
	return SUCCESS


## 第二段：魔纹融合的三个翻转档（客户端会在这三颗左边摆出技能本体，共四个按钮）。
## 取消（空 args）＝退回第一段二选一，不放弃整次响应。
func _nu_huo_mo_wen_xuan(ctx: Dictionary) -> int:
	var dst_id: int = int(ctx.get("dst", -1))
	var 有牌可弃: bool = player.hand_count() >= 2
	var 魔纹基础可用: bool = _mo_wen() >= 1 and 有牌可弃
	var 魔纹额外1可用: bool = player.tap and _mo_wen() >= 2 and 有牌可弃 \
			and (_wen_max() - _zhan_wen() - 1) >= 1
	var 魔纹额外2可用: bool = player.tap and _mo_wen() >= 3 and 有牌可弃 \
			and (_wen_max() - _zhan_wen() - 1) >= 2
	if not engine.has_reply():
		var 选项: Array = [
			{"value": CHOICE_MO_WEN_RONG_HE, "label": 提示原文(MO_WEN_RONG_HE, 2),
				"skill_id": MO_WEN_RONG_HE, "need_card": 2, "enabled": 魔纹基础可用},
			{"value": CHOICE_MO_WEN_RONG_HE + 1, "label": 提示原文(MO_WEN_RONG_HE, 3),
				"skill_id": MO_WEN_RONG_HE, "need_card": 2, "enabled": 魔纹额外1可用},
			{"value": CHOICE_MO_WEN_RONG_HE + 2, "label": 提示原文(MO_WEN_RONG_HE, 4),
				"skill_id": MO_WEN_RONG_HE, "need_card": 2, "enabled": 魔纹额外2可用},
		]
		var 伤害目标: Array = [dst_id] if dst_id >= 0 else []
		engine.ask_skill(player.id, MO_WEN_RONG_HE, 0, 0, GConst.CardSource.Hand, 选项,
			player.hand_count(), "diff", [], true, 提示原文(MO_WEN_RONG_HE, 0), 伤害目标)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	if args.is_empty():
		return 返回二选一
	var choice: int = int(args[0])
	if choice < CHOICE_MO_WEN_RONG_HE:
		return SUCCESS
	return _nu_huo_rong_he(dst_id, choice - CHOICE_MO_WEN_RONG_HE, r.get("card_ids", []))


## 魔纹融合结算：弃 ≥2 张互异系牌【展示】，对目标造成 (张数 - 1 + 额外翻转数) 点法术伤害
func _nu_huo_rong_he(dst_id: int, addition: int, cards: Array) -> int:
	# 取消 / 没选够（客户端按 "diff" 规则拦着，正常提交到不了这）：当作放弃
	if cards.size() < 2:
		return SUCCESS
	if _mo_wen() < 1:
		return GConst.GE_INVALID_ARGUMENT
	if _element_check(cards) != ElementKind.AllDifferent or not _has_cards(cards):
		return GConst.GE_INVALID_CARDID
	# 额外翻转要本来的 1 个 + addition 个魔纹都够；先验再改，避免先扣资源后报错
	if _mo_wen() < 1 + addition:
		return GConst.GE_INVALID_ARGUMENT
	_set_zhan_wen(_zhan_wen() + 1)
	_set_mo_wen(_mo_wen() - 1)
	if addition > 0:
		_set_zhan_wen(_zhan_wen() + addition)
		_set_mo_wen(_mo_wen() - addition)
	notice_skill(MO_WEN_RONG_HE, [dst_id])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": cards, "is_real": true,
	})
	engine.push_harm({
		"src": player.id, "dst": dst_id, "point": cards.size() - 1 + addition,
		"cause": MO_WEN_RONG_HE, "type": GConst.HarmType.Magic,
	})
	engine.take_from_hand(player.id, cards, true)
	engine.to_discard(cards)
	engine._broadcast_game()
	return URGENT


# ============================================================
# 对目标造成伤害时：双重回响
# ============================================================
## 【双重回响】的推进阶段（0＝还没开始 / SHUANG_CHONG_HUI_XIANG＝在问是否发动与目标）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨一次询问，
## 中途一旦被别的钩子轮次（改手牌 / 盖牌 / 基础效果 / 横置…）插进来，step 就被抹掉、流程退回第 0 步。
## 每次自己造成伤害（p_timeline_3）触发一次，收尾清回 0（留 STEP_DONE 会让下一次触发不再发动）。
## 收尾会返回 URGENT（压入了法术伤害），引擎在 URGENT 挂起后会重入本钩子：
## 此时 shuangChongHuiXiangUsed 已置位，入口即被挡下，不会重复发动。
var _hui_xiang_step: int = 0


func p_timeline_3(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("src", -1)) != player.id:
		return SUCCESS
	if player.get_energy() < 1 or shuangChongHuiXiangUsed:
		return SUCCESS
	if _hui_xiang_step >= STEP_DONE:
		return SUCCESS
	if _hui_xiang_step == 0:
		_hui_xiang_step = SHUANG_CHONG_HUI_XIANG
	if _hui_xiang_step == SHUANG_CHONG_HUI_XIANG:
		var r: int = _shuang_chong_hui_xiang(harm)
		if r == WAIT:
			return WAIT
		_hui_xiang_step = 0
		if r == URGENT:
			return URGENT
	return SUCCESS


func _shuang_chong_hui_xiang(harm: Dictionary) -> int:
	var from_dst: int = int(harm.get("dst", -1))
	if not engine.has_reply():
		# 不能选「当前正被这次伤害打中的人」（原版这里判非法）：把合法目标（除他以外的所有人）一并下发，
		# 让那名角色的头像点不动 —— 否则玩家选了他，服务端只能重问一次，看着像「选好目标却点不下去」
		var 合法目标: Array = []
		for pid: int in engine.order:
			if pid != from_dst:
				合法目标.append(pid)
		# 伤害＝本次伤害点数与 3 取小；只有服务端算得出来，随询问下发（preview_base），
		# 客户端据此在选中目标的头像上写「N 法术伤害」
		询问(player.id, SHUANG_CHONG_HUI_XIANG, 0, 1, GConst.CardSource.Hand, [], 0, "", [], true, 0, -1, 合法目标, -1, {},
			mini(int(harm.get("point", 0)), 3))
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		return SUCCESS
	var dsts: Array = r.get("dst_ids", [])
	if dsts.is_empty():
		return SUCCESS
	var dst_id: int = int(dsts[0])
	if dst_id == from_dst:
		# 不能选当前受伤者：服务端会重问同一名玩家（moveIterator 不推进）
		return _shuang_chong_hui_xiang(harm)
	notice_skill(SHUANG_CHONG_HUI_XIANG, [dst_id])
	shuangChongHuiXiangUsed = true
	if player.crystal > 0:
		player.set_crystal(player.crystal - 1)
	else:
		player.set_gem(player.gem - 1)
	engine.push_harm({
		"src": player.id, "dst": dst_id, "point": mini(int(harm.get("point", 0)), 3),
		"cause": SHUANG_CHONG_HUI_XIANG, "type": GConst.HarmType.Magic,
	})
	engine._broadcast_game()
	return URGENT


## 双重回响的伤害不造成士气下降（服务端据 con->harm.cause == 双重回响 判定）
func p_before_lose_morale(ctx: Dictionary) -> int:
	if int(ctx.get("harm_cause", 0)) == SHUANG_CHONG_HUI_XIANG:
		ctx["amount"] = 0
	return SUCCESS


# ============================================================
# 回合结束：脱离蓄势迸发形态
# ============================================================
func p_turn_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id or not player.tap:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	step = STEP_DONE
	notice_skill(FU_WEN_GAI_ZAO, [player.id])
	player.hand_cards_max -= FU_WEN_HAND_ADD
	engine.set_tap(player.id, false)
	engine._broadcast_game()
	return URGENT


# ============================================================
# 工具
# ============================================================
## 判元素：全同 / 全异 / 其它
func _element_check(cards: Array) -> int:
	var elements: Array[int] = []
	for c: Variant in cards:
		var card: GCard = Data.get_card(int(c))
		if card == null:
			return ElementKind.Invalid
		var e: int = card.element_enum()
		if not elements.has(e):
			elements.append(e)
	if elements.size() == 1:
		return ElementKind.AllSame
	if elements.size() == cards.size():
		return ElementKind.AllDifferent
	return ElementKind.Invalid


## 是否全部为手牌（且非空）
func _has_cards(cards: Array) -> bool:
	if cards.is_empty():
		return false
	for c: Variant in cards:
		if not player.has_hand_card(int(c)):
			return false
	return true
