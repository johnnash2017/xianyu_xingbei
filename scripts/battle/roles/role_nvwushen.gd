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

## 军神威光的第二段子步骤：step 为 0 时选效果，到它以后改为选「移除哪两颗星石」
const JUN_SHEN_WEI_GUANG_XUAN_XING_SHI: int = 25042


func available_skills() -> Array:
	# 秩序之印无消耗，随时可用
	return [{"type": GConst.ActionType.MagicSkill, "id": ZHI_XU_ZHI_YIN, "need_card": 0, "need_target": 0}]


func p_before_turn_begin(_ctx: Dictionary) -> int:
	added_shen_sheng_zhui_ji = false
	return SUCCESS


## 【军神威光】的推进阶段（0＝还没开始 / JUN_SHEN_WEI_GUANG_XUAN_XING_SHI＝在问移除哪两颗星石）。
## 用自有变量而不是引擎的 step：钩子轮次开始会把所有角色的 step 清零，而这条流程要跨若干次询问，
## 中途一旦被别的钩子轮次（改手牌 / 盖牌 / 基础效果 / 横置…）插进来，step 就被抹掉、流程退回第 0 步。
## 每次自己回合开始且处于横置（p_turn_begin）触发一次，收尾清回 0（留 STEP_DONE 会让下一次触发不再发动）
var _jun_shen_step: int = 0


# ============================================================
# 回合开始：军神威光（仅自身回合且处于横置形态时询问）
# 直接弹选项窗问「发动哪个效果」，取消＝不发动，没有多余的「是否发动」一步。
# 选「移除 2 星石」时再弹第二段问移除哪两颗（对照原版 JunShenWeiGuang → JunShenWeiGuang2）
# ============================================================
func p_turn_begin(_ctx: Dictionary) -> int:
	if engine.current_id != player.id or not player.tap:
		return SUCCESS
	if _jun_shen_step >= STEP_DONE:
		return SUCCESS
	# 第一段：选发动哪个效果
	if _jun_shen_step < JUN_SHEN_WEI_GUANG_XUAN_XING_SHI:
		if not engine.has_reply():
			询问(player.id, JUN_SHEN_WEI_GUANG, 0, 0, GConst.CardSource.Hand, _jun_shen_wei_guang_choices())
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		var args: Array = r.get("args", [])
		var choice: int = int(args[0]) if not args.is_empty() else 0
		if choice == 1:
			_jun_shen_step = 0
			notice_skill(JUN_SHEN_WEI_GUANG, [player.id])
			施加治疗(player.id, 1)
			engine._broadcast_game()
			return SUCCESS
		if choice != 2:
			# 取消 / 超时：不发动
			_jun_shen_step = 0
			return SUCCESS
		_jun_shen_step = JUN_SHEN_WEI_GUANG_XUAN_XING_SHI
	# 第二段：选移除哪两颗星石（取消＝不发动）
	if not engine.has_reply():
		询问(player.id, JUN_SHEN_WEI_GUANG, 0, 0, GConst.CardSource.Hand, _jun_shen_wei_guang_energy_choices(), 0, "", [], true, 1)
		return WAIT
	var r2: Dictionary = take_skill_reply_full()
	_jun_shen_step = 0
	var args2: Array = r2.get("args", [])
	var 组合: int = int(args2[0]) if not args2.is_empty() else 0
	if 组合 < 1 or 组合 > 3:
		return SUCCESS
	# 1＝两水晶 / 2＝一宝石一水晶 / 3＝两宝石
	var use_gem: int = 组合 - 1
	notice_skill(JUN_SHEN_WEI_GUANG, [player.id])
	engine.set_team_gem(player.color, engine.team_gem[player.color] - use_gem)
	engine.set_team_crystal(player.color, engine.team_crystal[player.color] - (2 - use_gem))
	# 无视上限 +2 治疗：走与普通加治疗同一入口（会写战斗日志，且超过上限时只加不减）
	施加治疗_突破(player.id, 2, 0)
	engine._broadcast_game()
	return SUCCESS


## 军神威光第一段选项：+1 治疗，或（团队能量 > 1 时）移除 2 星石换无视上限 +2 治疗
func _jun_shen_wei_guang_choices() -> Array:
	var 选项: Array = [{"value": 1, "label": "你 +1【治疗】"}]
	if engine.team_gem[player.color] + engine.team_crystal[player.color] > 1:
		选项.append({"value": 2, "label": "移除我方【战绩区】2 星石，无视上限 +2【治疗】"})
	return 选项


## 军神威光第二段选项：按战绩区现有的星石列出可行的两颗组合
## （value 1＝两水晶 / 2＝一宝石一水晶 / 3＝两宝石，与服务端的换算一一对应）
func _jun_shen_wei_guang_energy_choices() -> Array:
	var 宝石: int = engine.team_gem[player.color]
	var 水晶: int = engine.team_crystal[player.color]
	var 选项: Array = []
	if 水晶 >= 2:
		选项.append({"value": 1, "label": "移除 2 个【水晶】"})
	if 宝石 >= 1 and 水晶 >= 1:
		选项.append({"value": 2, "label": "移除 1 个【宝石】和 1 个【水晶】"})
	if 宝石 >= 2:
		选项.append({"value": 3, "label": "移除 2 个【宝石】"})
	return 选项


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
# 自身攻击命中后：英灵召唤（耗 1 能量横置，伤害 +1，可弃 0~1 张法术牌再 +1）
# ============================================================
func p_timeline_2_hit(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("src", -1)) != player.id or player.get_energy() == 0:
		return SUCCESS
	if step >= STEP_DONE:
		return SUCCESS
	if not engine.has_reply():
		# 弃牌是可选的：need_card=0（一张不弃也能发动）、最多 1 张、只让法术牌可点
		询问(player.id, YING_LING_ZHAO_HUAN, 0, 0, GConst.CardSource.Hand, [], 1, "magic")
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
	# 额外弃 1 张法术牌再 +1：客户端把「玩家选中的牌」放在 card_ids，
	# 技能询问不回 args[1] 这一维（原版客户端是每条技能自己拼 [发动, 是否弃牌] 的）
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
	施加治疗(player.id, 1)
	player.set_crystal(player.crystal + 1)
	engine._broadcast_game()
	return SUCCESS
