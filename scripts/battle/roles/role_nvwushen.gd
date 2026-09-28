extends BattleRole
## 女武神（roleID 25）—— 移植自服务端 role/NvWuShen.cpp
## 形态：tap（横置/神灵形态）+ cross_num（治疗）驱动
## 技能：神圣追击（2501，攻击/法术结束后治疗≥1 时追加一次攻击行动）、
##       秩序之印（2502，法术技能：摸 2 张牌并 +1 治疗 +1 水晶）、
##       和平行者（2503，被动：横置形态下主动攻击时解除横置）、
##       军神威光（2504，回合开始且横置时询问：+1 治疗，或耗团队宝石/水晶换 +2 治疗）、
##       英灵召唤（2505，自身攻击命中时询问：耗 1 能量并横置，伤害 +1，可再弃 1 张法术牌 +1）

const SHEN_SHENG_ZHUI_JI: int = 2501
const ZHI_XU_ZHI_YIN: int = 2502
const HE_PING_XING_ZHE: int = 2503
const JUN_SHEN_WEI_GUANG: int = 2504
const YING_LING_ZHAO_HUAN: int = 2505


## 本回合是否已授予过「神圣追击」（服务端 added_SHEN_SHENG_ZHUI_JI）
var added_shen_sheng_zhui_ji: bool = false


func available_skills() -> Array:
	# 秩序之印无消耗，随时可用
	return [{"type": GConst.ActionType.MagicSkill, "id": ZHI_XU_ZHI_YIN, "need_card": 0, "need_target": 0}]


func p_before_turn_begin(_ctx: Dictionary) -> int:
	added_shen_sheng_zhui_ji = false
	return SUCCESS


# ============================================================
# 回合开始：军神威光（仅自身回合且处于横置形态时询问）
# ============================================================
func p_turn_begin(_ctx: Dictionary) -> int:
	if engine.current_id != player.id or not player.tap:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if not engine.has_reply():
		engine.ask_skill(player.id, JUN_SHEN_WEI_GUANG, 0, 0)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	var args: Array = r.get("args", [])
	if args.is_empty():
		return SUCCESS
	var choice: int = int(args[0])
	if choice != 1 and choice != 2:
		return SUCCESS
	notice_skill(JUN_SHEN_WEI_GUANG, [player.id])
	if choice == 1:
		player.add_cross_num(1)
	else:
		# 放弃 +1 治疗：扣团队宝石/水晶，换 +2 治疗（服务端 addCrossNum(2,-2)，无视上限）
		var use_gem: int = int(args[1]) if args.size() > 1 else 0
		var use_crystal: int = int(args[2]) if args.size() > 2 else 0
		engine.set_team_gem(player.color, engine.team_gem[player.color] - use_gem)
		engine.set_team_crystal(player.color, engine.team_crystal[player.color] - use_crystal)
		player.cross_num = player.cross_num + 2
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 攻击宣告后：和平行者（横置形态下主动攻击解除横置，被动）
# ============================================================
func p_timeline_1(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	if not bool(ctx.get("is_active", false)) or not player.tap:
		return SUCCESS
	notice_skill(HE_PING_XING_ZHE, [player.id])
	player.tap = false
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 自身攻击命中后：英灵召唤（耗 1 能量横置，伤害 +1，可弃 1 张法术牌再 +1）
# ============================================================
func p_timeline_2_hit(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("src", -1)) != player.id or player.get_energy() == 0:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if not engine.has_reply():
		engine.ask_skill(player.id, YING_LING_ZHAO_HUAN, 1, 0)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	step = STEP_DONE
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		return SUCCESS
	notice_skill(YING_LING_ZHAO_HUAN, [int(harm.get("dst", -1))])
	if player.crystal > 0:
		player.set_crystal(player.crystal - 1)
	else:
		player.set_gem(player.gem - 1)
	player.tap = true
	harm["point"] = int(harm.get("point", 0)) + 1
	if args.size() > 1 and int(args[1]) == 1:
		var cards: Array = r.get("card_ids", [])
		if not cards.is_empty():
			var cid: int = int(cards[0])
			var card: GCard = Data.get_card(cid)
			if card != null and card.is_magic() and player.has_hand_card(cid):
				harm["point"] = int(harm["point"]) + 1
				engine.broadcast(GConst.Msg.Card, {
					"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
					"card_ids": [cid], "is_real": true,
				})
				engine.take_from_hand(player.id, [cid])
				engine.to_discard([cid])
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 攻击/法术行动结束后：神圣追击（治疗≥1 时追加一次攻击行动）
# ============================================================
func p_after_attack(ctx: Dictionary) -> int:
	return _shen_sheng_zhui_ji(int(ctx.get("player", -1)))


func p_after_magic(ctx: Dictionary) -> int:
	# 法术牌走 _do_magic（ctx 用 src），法术技能走 SkillRun（ctx 用 player）
	return _shen_sheng_zhui_ji(int(ctx.get("player", ctx.get("src", -1))))


## 神圣追击：攻击/法术结束后治疗≥1 时授予一次额外攻击行动
## 只挂行动并置回合内的「已授予」标记，扣治疗与技能通知在玩家选中时结算
func _shen_sheng_zhui_ji(pid: int) -> int:
	if pid != player.id or player.cross_num < 1 or added_shen_sheng_zhui_ji:
		return SUCCESS
	player.add_action(GConst.ActionType.Attack, SHEN_SHENG_ZHUI_JI)
	added_shen_sheng_zhui_ji = true
	return SUCCESS


# ============================================================
# 玩家选中额外行动时：结算神圣追击的代价（-1 治疗）
# 引擎在选中时会统一广播技能通知；服务端选中后会把「已授予」标记置回 false，
# 使本次额外攻击结束后仍可再次授予，故此处同步重置
# ============================================================
func p_additional_action(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if int(ctx.get("cause", 0)) != SHEN_SHENG_ZHUI_JI:
		return SUCCESS
	player.sub_cross_num(1)
	added_shen_sheng_zhui_ji = false
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 主动法术技能：秩序之印
# ============================================================
func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != ZHI_XU_ZHI_YIN:
		return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != ZHI_XU_ZHI_YIN:
		return GConst.GE_INVALID_ACTION
	notice_skill(ZHI_XU_ZHI_YIN, [player.id])
	# 服务端先压入「摸 2 张」状态（URGENT），再执行 +1 治疗 +1 水晶
	engine.draw(player.id, 2)
	player.add_cross_num(1)
	player.set_crystal(player.crystal + 1)
	engine._broadcast_game()
	return SUCCESS
