extends BattleRole
## 魔弓（roleID 26）—— 移植自服务端 role/MoGong.cpp
## 【响应】魔贯冲击（2601）：主动攻击前移除 1 个火系【充能】，本次伤害 +1；不能攻击手牌达到上限的对手；
##                  若命中可再移除 1 个火系【充能】使伤害再 +1；若未命中则对对方造成 3 点法术伤害③
## 【法术】雷光散射（2602）：移除雷系【充能】，对所有对手各 1 点法术伤害③；
##                  若额外移除 X 个雷系【充能】，指定一名对手额外受 X 点
## 【响应】多重射击（2603）：【攻击行动】结束时移除 1 个风系【充能】，视为额外 1 次暗系主动攻击，
##                  不能攻击上次的目标且伤害 -1（攻击行动结束直接询问，确认＝发动，
##                  并在同一次询问里让玩家选要移除的风系【充能】和目标；
##                  本次攻击结束后若还有风系【充能】可继续发动，无每回合次数限制）
## 【启动】充能（2604）：耗 1 能量，弃到四张、摸 X 张牌，可将至多 X 张手牌作为【充能】
## 【启动】魔眼（2605）：耗 1 宝石。点技能时二选一 —— 点一名角色（别人弃 1 张牌 / 自己摸 3 张牌），
##                  或点一张自己的手牌弃掉；然后将 1 张手牌作为【充能】，+1 水晶
## 两者均为「启动」：显示为技能栏按钮，点了才发动，不消耗本回合行动
## 【充能】为专属盖牌，上限见角色表

const MO_GUAN_CHONG_JI: int = 2601
const LEI_GUANG_SAN_SHE: int = 2602
const DUO_CHONG_SHE_JI: int = 2603
const CHONG_NENG: int = 2604
const MO_YAN: int = 2605

## 【充能】弃到几张：弃到 4 张是发动代价（写进 available_skills 的 need_card，同格斗家【斗神天驱】）
const CHONG_NENG_KEEP_HAND: int = 4

## 子步骤不再单独占技能表行：主技能行在「提示2」列多配一条文案，代码用 序号=1 取它；
## 下面是流程内部的分段标记（不会拿去查表）
const PHASE_ASK_EXTRA: int = -1    # 【魔贯冲击】命中追加：在问是否再移除 1 个火系【充能】

## 【多重射击】使用的虚拟攻击牌（服务端 virtualCardID = 39）
## 本工程卡 39 即「暗灭」（暗系攻击），出牌特效/音效按它走
const VIRTUAL_DUO_CHONG_CARD: int = 39

## 本回合是否发动过【魔贯冲击】/【多重射击】
var _using_mo_guan: bool = false
var _using_duo_chong: bool = false
## 本回合是否还能发动【魔贯冲击】/【雷光散射】/【多重射击】
var _available_mo_guan: bool = true
var _available_lei_guang: bool = true
var _available_duo_chong: bool = true
## 【魔贯冲击（2601）】的推进阶段（0＝还没开始 / MO_GUAN_CHONG_JI＝在问是否发动，收尾清回 0）。
## 带火系【充能】的普通出牌攻击按原版弹窗询问是否发动，发动则由玩家选 1 张火系【充能】移除。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零。
## 每次自己主动宣告攻击（p_timeline_1）触发一次，收尾清回 0（留 STEP_DONE 会让下一次触发不再发动）
var _timeline_1_step: int = 0
## 【充能】的摸牌数（决定【充能改牌】可放入盖牌区的手牌数）
var _chong_neng_num: int = 0
## 待办的盖牌步骤（主技能号；0＝无）+ 最多可盖几张。盖牌不紧跟摸牌，而是挂在 p_cover_after_skill：
## 摸牌若顶过手牌上限，引擎会先结算爆牌 + 掉士气，再回到那里问盖牌（充能＝摸牌数、魔眼＝1）
var _待盖牌技能: int = 0
var _待盖牌上限: int = 0
## 上次主动攻击的目标（【多重射击】不能攻击同一目标）
var _last_target: int = -1


func available_skills() -> Array:
	var out: Array = []
	# 充能 / 魔眼：「启动」技能，显示为技能栏按钮，点了才发动且不消耗本回合行动。
	# 【充能】「弃到 4 张」是发动代价，写进 need_card（同格斗家【斗神天驱】）；
	# 摸几张由 arg_choices 在二级技能栏里选 —— 点技能后弃牌与摸牌数一起选，最后按一次「确定」，
	# 不再先确定、再由服务端补问一次摸牌数
	if player.get_energy() > 0:
		var 需弃: int = maxi(player.hand_cards.size() - CHONG_NENG_KEEP_HAND, 0)
		out.append({"type": GConst.ActionType.SpecialSkill, "id": CHONG_NENG, "need_card": 需弃, "need_target": 0,
			"arg_choices": _chong_neng_choices()})
	if player.gem > 0:
		# 魔眼：点技能后先在二级技能栏里二选一（对照原服务端 MoGong::MoYan）——
		# 「自己摸 3 张牌」不点目标；「指定一名角色弃 1 张牌」再点 1 名角色（可点自己）。
		# need_target 给 0、不给 target_max：目标数完全由选项自带（选了要目标的那项客户端才放开点头像）
		out.append({"type": GConst.ActionType.SpecialSkill, "id": MO_YAN, "need_card": 0, "need_target": 0,
			"arg_choices": _mo_yan_choices()})
	if _available_lei_guang:
		# 雷光散射：从盖牌区选雷系牌（至少 1 张、可多选）。选超过 1 张时可指定一名对手额外受伤，
		# 目标限敌方（白名单下发界面；「选超过 1 张才需要选目标」由技能指示器的「目标随牌」规则定）
		var 雷系盖牌: Array[int] = _cover_ids_of_element(GConst.CardElement.Thunder)
		if not 雷系盖牌.is_empty():
			out.append({"type": GConst.ActionType.MagicSkill, "id": LEI_GUANG_SAN_SHE, "need_card": 1,
				"card_source": GConst.CardSource.Cover, "cards": 雷系盖牌, "card_max": 雷系盖牌.size(),
				"targets": enemy_ids()})
	# 【魔贯冲击】不再提供技能栏按钮：它只能在主动攻击宣告时响应发动
	return out


## 充能 / 魔眼 为「启动」：不消耗本回合行动，发动后行动阶段照旧继续
func is_free_skill(skill_id: int) -> bool:
	return skill_id == CHONG_NENG or skill_id == MO_YAN


# ============================================================
# 回合开始：重置本回合限用标记（服务端在 p_before_turn_begin 无条件重置）
# ============================================================
func p_before_turn_begin(_ctx: Dictionary) -> int:
	_using_mo_guan = false
	_using_duo_chong = false
	_available_mo_guan = true
	_available_lei_guang = true
	_available_duo_chong = true
	_chong_neng_num = 0
	_待盖牌技能 = 0
	_待盖牌上限 = 0
	_last_target = -1
	return SUCCESS


# ============================================================
# 主动法术技能：雷光散射
# ============================================================
func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != LEI_GUANG_SAN_SHE:
		return GConst.GE_INVALID_ACTION
	if not _available_lei_guang:
		return GConst.GE_INVALID_ACTION
	# 服务端要求盖牌区存在雷系牌
	if not _cover_has_element(GConst.CardElement.Thunder):
		return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != LEI_GUANG_SAN_SHE:
		return GConst.GE_INVALID_ACTION
	return _lei_guang_san_she(action)


## 雷光散射：移除雷系【充能】，对所有对手各 1 点法术伤害；指定一名对手额外受（移除数）点
func _lei_guang_san_she(action: Dictionary) -> int:
	var dsts: Array = action.get("dst_ids", [])
	var dest_id: int = int(dsts[0]) if not dsts.is_empty() else -1
	var used: Array = []
	for c: Variant in action.get("card_ids", []):
		var cid: int = int(c)
		var card: GCard = Data.get_card(cid)
		if card != null and card.element_enum() == GConst.CardElement.Thunder and player.cover_cards.has(cid):
			if not used.has(cid):
				used.append(cid)
	# 全部敌方角色（从自己的下家开始按行动顺序绕一圈）
	var enemies: Array[int] = []
	var nid: int = player.post_id
	for _i: int in range(engine.order.size() - 1):
		var ep: BattlePlayer = engine.p(nid)
		if ep != null and ep.color != player.color:
			enemies.append(nid)
		nid = engine.next_id(nid)
	# 服务端把目标表 reverse 后逐个压栈（LIFO），实际结算顺序＝「从自己右侧第一个角色起，按行动顺序绕一圈」
	var 通报: Array = []
	for i: int in range(enemies.size() - 1, -1, -1):
		通报.append(enemies[i])
	notice_skill(LEI_GUANG_SAN_SHE, 通报)
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": used, "is_real": true,
	})
	_remove_cover(used, LEI_GUANG_SAN_SHE)
	var extra: int = used.size()
	for i: int in range(enemies.size() - 1, -1, -1):
		var e: int = enemies[i]
		var point: int = extra if e == dest_id else 1
		engine.push_harm({
			"src": player.id, "dst": e, "point": point,
			"cause": LEI_GUANG_SAN_SHE, "type": GConst.HarmType.Magic,
		})
	engine._broadcast_game()
	return URGENT


# ============================================================
# 攻击宣告后：魔贯冲击 / 多重射击的伤害修正
# ============================================================
func p_timeline_1(ctx: Dictionary) -> int:
	var src: int = int(ctx.get("src", -1))
	if src != player.id or not bool(ctx.get("is_active", false)):
		return SUCCESS
	_last_target = int(ctx.get("dst", -1))
	if _using_duo_chong:
		# 多重射击：暗系攻击，对方无法应战且伤害 -1
		ctx["hit_rate"] = GConst.HitRate.NoReattack
		var h0: Dictionary = ctx.get("harm", {})
		h0["point"] = int(h0.get("point", 0)) - GConst.多重射击减伤
		_using_duo_chong = false
		return SUCCESS
	# 普通出牌攻击：按原版询问流程（是否发动【魔贯冲击】，发动则由玩家选 1 张火系【充能】移除）
	if _timeline_1_step >= STEP_DONE:
		return SUCCESS
	if _timeline_1_step == 0:
		_timeline_1_step = MO_GUAN_CHONG_JI
	if _timeline_1_step == MO_GUAN_CHONG_JI:
		var r: int = _mo_guan_chong_ji(ctx)
		if r == WAIT:
			return WAIT
		_timeline_1_step = 0
	return SUCCESS


## 魔贯冲击（原版询问流程）：弹窗询问是否发动，发动则由玩家选 1 张火系【充能】移除，本次伤害 +1
func _mo_guan_chong_ji(ctx: Dictionary) -> int:
	var dst: BattlePlayer = engine.p(int(ctx.get("dst", -1)))
	if dst == null or not _available_mo_guan:
		return SUCCESS
	# 不能攻击手牌达到上限的对手
	if dst.hand_cards.size() == dst.hand_cards_max:
		return SUCCESS
	if not _cover_has_element(GConst.CardElement.Fire):
		return SUCCESS
	if not engine.has_reply():
		# 只能移除火系【充能】：下发火系盖牌白名单，界面把其余盖牌置灰；
		# 顺带下发攻击目标与发动前的伤害，客户端据此在目标头像上现算「本次攻击伤害」
		询问(player.id, MO_GUAN_CHONG_JI, 1, 0, GConst.CardSource.Cover, [], 0, "",
			_cover_ids_of_element(GConst.CardElement.Fire), true, 0, -1, [dst.id], -1, {},
			int(ctx.get("harm", {}).get("point", 0)))
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		return SUCCESS
	var cid: int = _cover_card_of_element(r.get("card_ids", []), GConst.CardElement.Fire)
	if cid < 0:
		return SUCCESS
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": [cid], "is_real": true,
	})
	_remove_cover([cid], MO_GUAN_CHONG_JI)
	_结算魔贯冲击(ctx)
	return SUCCESS


## 魔贯冲击：本次攻击伤害 +1，并禁用本回合的【多重射击】
func _结算魔贯冲击(ctx: Dictionary) -> void:
	notice_skill(MO_GUAN_CHONG_JI, [int(ctx.get("dst", -1))])
	var harm: Dictionary = ctx.get("harm", {})
	harm["point"] = int(harm.get("point", 0)) + 1
	_using_mo_guan = true
	# 每次发动【魔贯冲击】都清空「命中追加」的推进阶段，好让本次命中仍能问一次是否追加
	_mo_guan_hit_step = 0
	_available_duo_chong = false
	engine._broadcast_game()


# ============================================================
# 命中 / 未命中的追加效果
# ============================================================
## 【魔贯冲击·命中追加】的推进：0＝还没开始 / PHASE_ASK_EXTRA＝在问是否追加。
## 用自有变量而不是引擎 step：钩子轮次开始会把 step 清零，而这条流程要跨一次询问。
## 每次发动【魔贯冲击】时由 _结算魔贯冲击 清回 0，收尾置 STEP_DONE
var _mo_guan_hit_step: int = 0


func p_timeline_2_hit(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id or not _using_mo_guan:
		return SUCCESS
	if _mo_guan_hit_step >= STEP_DONE:
		return SUCCESS
	if _mo_guan_hit_step == 0:
		_mo_guan_hit_step = PHASE_ASK_EXTRA
	if _mo_guan_hit_step == PHASE_ASK_EXTRA:
		# 对照原版 MoGuanChongJi_Hit：命中后询问是否追加发动，发动则由玩家选 1 张火系【充能】移除
		# （序号 1 = 技能表「提示2」列的「发动【魔贯冲击】：再移除 {n} 个火系【充能】」）；
		# 同样下发攻击目标与当前伤害，客户端据此在目标头像上写「再 +1 后」的伤害
		if not engine.has_reply():
			询问(player.id, MO_GUAN_CHONG_JI, 1, 0, GConst.CardSource.Cover, [], 0, "",
				_cover_ids_of_element(GConst.CardElement.Fire), true, 1,
				-1, [int(ctx.get("dst", -1))], -1, {}, int(ctx.get("harm", {}).get("point", 0)))
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		var args: Array = r.get("args", [])
		_using_mo_guan = false
		_mo_guan_hit_step = STEP_DONE
		if args.is_empty() or int(args[0]) != 1:
			return SUCCESS
		var cid: int = _cover_card_of_element(r.get("card_ids", []), GConst.CardElement.Fire)
		if cid < 0:
			return SUCCESS
		notice_skill(MO_GUAN_CHONG_JI, [int(ctx.get("dst", -1))])
		engine.broadcast(GConst.Msg.Card, {
			"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
			"card_ids": [cid], "is_real": true,
		})
		_remove_cover([cid], MO_GUAN_CHONG_JI)
		var harm: Dictionary = ctx.get("harm", {})
		harm["point"] = int(harm.get("point", 0)) + 1
		engine._broadcast_game()
		return SUCCESS
	return SUCCESS


func p_timeline_2_miss(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id or not _using_mo_guan:
		return SUCCESS
	_using_mo_guan = false
	step = STEP_DONE
	engine.push_harm({
		"src": player.id, "dst": int(ctx.get("dst", -1)), "point": 3,
		"cause": MO_GUAN_CHONG_JI, "type": GConst.HarmType.Magic,
	})
	engine._broadcast_game()
	return URGENT


# ============================================================
# 攻击行动结束后：问玩家是否发动【多重射击】（确认＝发动，并在询问里选要移除的风系【充能】和目标）。
# 每次【多重射击】本身也是一次暗系主动攻击，其攻击行动结束会再走到这里——
# 只要盖牌区里还有风系【充能】，就能一次接一次地继续发动（无每回合次数限制）
# ============================================================
func p_after_attack(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	return _duo_chong_she_ji_ask()


## 【多重射击】：问玩家是否发动；发动则由他自己选要移除的风系【充能】和攻击目标
##（同【魔贯冲击】那样把代价放进询问）。确认后视为额外 1 次暗系主动攻击
##（伤害 -1、对方不能应战，在 p_timeline_1 里按 _using_duo_chong 结算）
func _duo_chong_she_ji_ask() -> int:
	if not _available_duo_chong or not _cover_has_element(GConst.CardElement.Wind):
		return SUCCESS
	# 可攻击的敌方目标（不含上次的目标；潜行等不能成为目标的人也不列）
	var 可攻目标: Array[int] = player_ids_where(_duo_chong_dst_ok)
	if 可攻目标.is_empty():
		return SUCCESS
	if not engine.has_reply():
		询问(player.id, DUO_CHONG_SHE_JI, 1, 1, GConst.CardSource.Cover, [], 0, "",
			_cover_ids_of_element(GConst.CardElement.Wind), true, 0, -1, 可攻目标)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		return SUCCESS
	var 充能: int = _cover_card_of_element(r.get("card_ids", []), GConst.CardElement.Wind)
	if 充能 < 0:
		return SUCCESS
	var dsts: Array = r.get("dst_ids", [])
	if dsts.is_empty():
		return SUCCESS
	var dst_id: int = int(dsts[0])
	if not _duo_chong_dst_ok(engine.p(dst_id)):
		return SUCCESS
	notice_skill(DUO_CHONG_SHE_JI, [dst_id])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": [充能], "is_real": true,
	})
	_remove_cover([充能], DUO_CHONG_SHE_JI)
	# 多重射击本身视为一次暗系主动攻击：广播一张「暗灭」虚拟牌（is_real=false 不摊牌），
	# 客户端据此播放暗灭弹道与暗系出牌音效（对照【欺诈】虚牌广播的写法）
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Use, "src_id": player.id, "dst_id": dst_id,
		"card_ids": [VIRTUAL_DUO_CHONG_CARD], "is_real": false,
	})
	# 本回合不能再发动【魔贯冲击】；本次攻击的暗系修正交给 p_timeline_1
	_available_mo_guan = false
	_using_duo_chong = true
	var harm: Dictionary = {
		"src": player.id, "dst": dst_id, "point": 2,
		"cause": DUO_CHONG_SHE_JI, "type": GConst.HarmType.Attack,
		"card_id": VIRTUAL_DUO_CHONG_CARD, "is_active": true,
	}
	# 【多重射击】本身视为一次暗系主动攻击：这次攻击结算完后，再触发一次「攻击行动结束」
	# （p_after_attack），在那里继续问要不要接着发动。
	# 即「每一次多重射击都是独立的一次攻击，攻击结束后才接下一次」，而不是一次攻击行动结束时连问多次。
	# 压栈顺序：先压钩子、后压攻击，攻击先跑（LIFO），跑完才轮到钩子
	engine.push(BattleEngine.SHook.new("p_after_attack",
		{"player": player.id, "card_id": VIRTUAL_DUO_CHONG_CARD, "dst": dst_id}, []))
	engine.push(BattleEngine.SAttackCard.new(player.id, dst_id, VIRTUAL_DUO_CHONG_CARD, harm))
	engine._broadcast_game()
	return SUCCESS


## 【多重射击】的合法目标：敌方、不是上次主动攻击的目标，且可被主动攻击（如暗杀者潜行中不行）
func _duo_chong_dst_ok(p0: BattlePlayer) -> bool:
	if p0 == null or p0.color == player.color:
		return false
	if p0.id == _last_target:
		return false
	# 面前有【挑衅】时只能打放牌者
	if player.check_exclusive_effect(GConst.Exclusive.TiaoXin) \
			and p0.id != player.exclusive_owner(GConst.Exclusive.TiaoXin):
		return false
	return p0.v_attacked() == GConst.GE_SUCCESS


# ============================================================
# 启动技能（技能栏按钮）：充能 / 魔眼
# （「每回合只能发动一个启动技能」由引擎统一把关，这里只校验各技能自己的条件）
# ============================================================
## 校验：充能需 1 能量（优先水晶）且已按代价弃到 4 张；魔眼需 1 宝石
func v_special_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	match int(action.get("action_id", 0)):
		CHONG_NENG:
			if player.get_energy() <= 0:
				return GConst.GE_INVALID_ACTION
			# 弃到 4 张必须执行：张数由服务端复核（客户端少弃 / 多弃都驳回）
			var 弃牌: Array = action.get("card_ids", [])
			if 弃牌.size() != maxi(player.hand_cards.size() - CHONG_NENG_KEEP_HAND, 0):
				return GConst.GE_INVALID_ACTION
			for c: Variant in 弃牌:
				if not player.has_hand_card(int(c)):
					return GConst.GE_INVALID_ACTION
		MO_YAN:
			if player.gem <= 0:
				return GConst.GE_INVALID_ACTION
			# 二级技能栏里选了「指定一名角色弃 1 张牌」那一项时，必须带一个真实存在的目标
			var 魔眼参数: Array = action.get("args", [])
			if not 魔眼参数.is_empty() and int(魔眼参数[0]) == 1:
				var 魔眼目标: Array = action.get("dst_ids", [])
				if 魔眼目标.is_empty() or engine.p(int(魔眼目标[0])) == null:
					return GConst.GE_INVALID_ARGUMENT
		_:
			return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_special_skill(action: Dictionary) -> int:
	match int(action.get("action_id", 0)):
		CHONG_NENG:
			return _run_chong_neng(action)
		MO_YAN:
			return _run_mo_yan(action)
	return SUCCESS


## 【充能】【魔眼】的盖牌步骤挂在独立钩子上：该钩子在摸牌（含【水影】这类摸牌前响应）与
## 随后的爆牌 / 掉士气之后才跑，故可以按「摸牌之后、爆牌之后」的当前手牌选盖牌的牌。
## 由 _chong_neng / _mo_yan 在压摸牌（或弃牌）状态**之前**压栈 —— 状态栈后进先出，
## 先压的钩子才会排在摸牌之后跑（像早期写成 p_after_special 就不行了：摸牌改走 push_draw 之后
## 它是延迟结算的，而 SkillRun 的 after 钩子后压先跑，会抢在摸牌前面 → 变成先选盖牌再摸牌）
func p_cover_after_skill(ctx: Dictionary) -> int:
	if _待盖牌技能 == 0 or int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	# 盖牌上限＝min(摸牌数, 手牌数-1)：盖完必须至少留 1 张手牌，
	# 否则本回合无法执行攻击 / 法术行动（规则：充能后必须能行动）
	var 可盖: int = mini(_待盖牌上限, maxi(player.hand_cards.size() - 1, 0))
	var r: int = SUCCESS
	if 可盖 > 0:
		r = _gai_pai(_待盖牌技能, 可盖)
	if r == WAIT:
		return WAIT
	_待盖牌技能 = 0
	return SUCCESS


## 充能：耗 1 能量，弃到 4 张（发动时已作为代价选好）、摸 X 张牌，然后把至多 X 张手牌作为【充能】
## 盖牌不在这里问，而是压在摸牌状态之前、由 p_cover_after_skill 承接：
## 摸牌顶过手牌上限时，引擎会先结算爆牌 + 掉士气，再回来问盖牌（顺序：弃牌 → 摸牌 → 爆牌 → 盖牌）
func _run_chong_neng(action: Dictionary) -> int:
	_chong_neng(action)
	# 没实际发动（没给摸牌数）：直接结束，连盖牌步骤也不挂
	if not player.boot_skill_used:
		return SUCCESS
	_待盖牌技能 = CHONG_NENG
	_待盖牌上限 = _chong_neng_num
	return SUCCESS


## 充能的摸牌数选项（二级技能栏）：1~4 张各一颗，文案取技能表「提示」列第 4 条（"摸 {n} 张"）。
## 注意：序号 2（技能表「提示2」列那条「弃到 {n} 张牌，」）现在没有代码在读，但**不能删** ——
## 客户端按「第几个非空提示」取文案，删掉它序号会整体前移，这里的「摸 {n} 张」就取不到了
func _chong_neng_choices() -> Array:
	var out: Array = []
	for i: int in range(1, 5):
		out.append({"text": 提示(CHONG_NENG, 3, i), "args": [i]})
	return out


## 魔眼：先结算二级技能栏里选的那一项（自己摸 3 张 / 指定一名角色弃 1 张），
## 再把盖牌压在那一项的状态之前、由 p_cover_after_skill 承接 —— 摸 3 张若顶过手牌上限，
## 引擎会先结算爆牌 + 掉士气，之后才回来问盖牌（和【充能】同一条路，避免先问盖牌、后爆牌）
func _run_mo_yan(action: Dictionary) -> int:
	var r: int = _mo_yan(action)
	_待盖牌技能 = MO_YAN
	_待盖牌上限 = 1
	return r


## 充能：耗 1 能量（优先水晶）→ 摸牌 → 爆牌 / 掉士气（引擎在状态边界补）→ 盖牌。
## 「弃到 4 张」的牌与「摸几张」都由客户端随这次行动一起提交
## （args[0] = 摸牌数，已由二级技能栏的选项选定；弃牌张数已在 v_special_skill 复核）
func _chong_neng(action: Dictionary) -> int:
	var args: Array = action.get("args", [])
	# args[0] 是「摸牌数」选项的 value（1~4）；没带（正常到不了）视为不发动、连能量也不扣
	if args.is_empty() or int(args[0]) <= 0:
		return SUCCESS
	var draw_n: int = clampi(int(args[0]), 1, 4)
	var 弃牌: Array[int] = []
	for c: Variant in action.get("card_ids", []):
		弃牌.append(int(c))
	notice_skill(CHONG_NENG, [player.id])
	player.boot_skill_used = true
	_available_mo_guan = false
	_available_lei_guang = false
	_chong_neng_num = draw_n
	if player.crystal > 0:
		player.set_crystal(player.crystal - 1)
	else:
		player.set_gem(player.gem - 1)
	# 顺序对照原版：先弃到 4 张 → 再摸 X 张 → 超限结算 → 盖牌
	if not 弃牌.is_empty():
		engine.take_from_hand(player.id, 弃牌)
		engine.to_discard(弃牌)
		engine._log_discard(player.id, 弃牌)
	# 先压盖牌钩子、后压摸牌（状态栈后进先出 → 摸牌与随后的爆牌先跑，再问盖牌）
	engine.push(BattleEngine.SHook.new("p_cover_after_skill", {"player": player.id}, []))
	engine.push_draw(player.id, draw_n)
	engine._broadcast_game()
	# 摸牌顶过手牌上限不用在这里处理：引擎在每个状态跑完后都会补 _check_hand_overflow()，
	# 爆牌 + 掉士气会在盖牌步骤之前先结算完
	return SUCCESS


## 魔眼的两个选项（二级技能栏二选一，对照原服务端 MoGong::MoYan）：
## args[0]=0 不指定目标 → 自己摸 3 张牌；args[0]=1 指定一名角色 → 该角色弃 1 张牌。
## 「指定」那项的白名单是全场（含自己，对照原版 playerArea->enableAll），所以点自己＝自己弃 1 张
func _mo_yan_choices() -> Array:
	return [
		{"text": 提示(MO_YAN, 2), "args": [0]},
		{"text": 提示(MO_YAN, 3), "args": [1], "need_target": 1, "targets": _all_player_ids()},
	]


## 场内所有玩家 id（含自己）：魔眼「指定一名角色」的目标白名单用它
func _all_player_ids() -> Array[int]:
	return player_ids_where(func(_p: BattlePlayer) -> bool: return true, true)


## 魔眼：耗 1 宝石、+1 水晶。效果由二级技能栏里选的那一项决定：
##   · args[0]=0 不指定目标 —— 自己摸 3 张牌；
##   · args[0]=1 指定一名角色 —— 该角色弃 1 张牌（含自己；手里没牌就不弃）。
## 「把手牌作【充能】」的盖牌步骤不在这里，压在下面那一项状态之前、由 p_cover_after_skill 承接
func _mo_yan(action: Dictionary) -> int:
	notice_skill(MO_YAN, [player.id])
	player.boot_skill_used = true
	player.set_gem(player.gem - 1)
	player.set_crystal(player.crystal + 1)
	var args: Array = action.get("args", [])
	var dsts: Array = action.get("dst_ids", [])
	# 先压盖牌钩子、后压这一项的状态（状态栈后进先出 → 先结算这一项，再问盖牌）
	engine.push(BattleEngine.SHook.new("p_cover_after_skill", {"player": player.id}, []))
	# 选了「指定一名角色」：走引擎通用的弃牌状态（它自己记弃牌日志，客户端据此播弃牌动画）
	if not args.is_empty() and int(args[0]) == 1 and not dsts.is_empty():
		engine.push(BattleEngine.SRequestDiscard.new(int(dsts[0]), 1, 0, MO_YAN))
		engine._broadcast_game()
		return URGENT
	# 其余（选「自己摸 3 张牌」，或异常没带目标）：自己摸 3 张
	engine.push_draw(player.id, 3)
	engine._broadcast_game()
	return SUCCESS


## 充能改牌 / 魔眼改牌：把至多 max_n 张手牌作为【充能】。skill_id 用主技能 id，
## 序号 1 读技能表「提示2」列的那条（如【充能】的「把手牌作【充能】」）
func _gai_pai(skill_id: int, max_n: int) -> int:
	if not engine.has_reply():
		# 至多 max_n 张：把点选上限放宽到 max_n（默认只会按 need_card 限 1 张）
		# 提示文案里的张数用 max_n（可盖的张数上限），而不是最少张数
		询问(player.id, skill_id, 1, 0, GConst.CardSource.Hand, [], max_n, "", [], true, 1, -1, [], max_n)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		return SUCCESS
	var cards: Array = []
	for c: Variant in r.get("card_ids", []):
		if cards.size() >= max_n:
			break
		if player.has_hand_card(int(c)) and not cards.has(int(c)):
			cards.append(int(c))
	if cards.is_empty():
		return SUCCESS
	notice_skill(skill_id, [player.id])
	engine.take_from_hand(player.id, cards)
	_add_cover(cards, skill_id)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 工具
# ============================================================
## 盖牌区某系别的全部牌 id（雷光散射的 cards 用它限制只能选雷系盖牌）
func _cover_ids_of_element(elem: int) -> Array[int]:
	var out: Array[int] = []
	for cid: int in player.cover_cards:
		var c: GCard = Data.get_card(cid)
		if c != null and c.element_enum() == elem:
			out.append(cid)
	return out


## 盖牌区是否有某系别的【充能】
func _cover_has_element(elem: int) -> bool:
	return not _cover_ids_of_element(elem).is_empty()


## 取回复中第一张指定系别的盖牌（玩家在代价/追加询问里选的那张）
func _cover_card_of_element(cards: Array, elem: int) -> int:
	for c: Variant in cards:
		var cid: int = int(c)
		if not player.cover_cards.has(cid):
			continue
		var card: GCard = Data.get_card(cid)
		if card != null and card.element_enum() == elem:
			return cid
	return -1


## 把牌作为【充能】加入盖牌区（超限由引擎询问玩家弃哪几张，对照 StateRequestCover）
func _add_cover(cards: Array, cause: int = 0) -> void:
	engine.add_cover(player.id, cards, player.id, cause)


## 从盖牌区移除【充能】并弃置
func _remove_cover(cards: Array, cause: int = 0) -> void:
	if cards.is_empty():
		return
	engine.to_discard(cards)
	engine.remove_cover(player.id, cards, player.id, cause)
