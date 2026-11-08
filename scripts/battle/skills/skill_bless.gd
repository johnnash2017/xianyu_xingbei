extends RefCounted
## F5-E 祈祷师（16）独有技 helper：1601 迅捷赐福 / 1602 威力赐福
##
## 供「借用祈祷师独有技」的角色（如灵熙之潮 4606）使用：只做校验 + 结算，不绑定角色号。
##
## 借用角色用法（构造传借用角色自己，setup 里创建）：
##   const 赐福技能 = preload("res://scripts/battle/skills/skill_bless.gd")
##   var _赐福: 赐福技能
##   func setup(p: BattlePlayer, e: BattleEngine) -> void:
##       super.setup(p, e)
##       _赐福 = 赐福技能.new(self)
##   func available_skills() -> Array: return _赐福.available_skills()
##   func v_magic_skill(a: Dictionary) -> int: return _赐福.v_magic_skill(a)
##   func p_magic_skill(a: Dictionary) -> int: return _赐福.p_magic_skill(a)
##   func p_timeline_2_hit(ctx: Dictionary) -> int: return _赐福.p_timeline_2_hit(ctx)
##   func p_after_attack(ctx: Dictionary) -> int: return _赐福.p_after_attack(ctx)
##   func p_after_magic(ctx: Dictionary) -> int: return _赐福.p_after_magic(ctx)
##   func p_additional_action(ctx: Dictionary) -> int: return _赐福.p_additional_action(ctx)
##
## 赐福是「放在队友面前的基础效果」，与普通主动技能不同：
## - 放置：目标限同色队友（不含自己）且面前没有同类赐福；发动牌必须在手且带对应技能；
## - 威力赐福（1602）：**攻击命中**时由牌的所有者（攻击者）决定是否发动，+2 伤害后移除该牌；
## - 迅捷赐福（1601）：牌的所有者**行动结束**时授予 +1 攻击行动，选择该额外行动时再移除；
## - 同类赐福全局不叠加（不区分来源）；触发/移除按「持有者面前有没有该技能的牌」，
##   这样祈祷师把赐福贴到别的角色面前、由持有者的角色脚本转发时也能正常校验与移除。
##
## 进度放在 helper 实例变量里（按「本次伤害字典」区分是否换了一次命中），不占角色的 step，
## 借用角色在同一钩子里还接别的 helper / 自己的分支时不会互相踩进度。

const XUN_JIE_CI_FU: int = 1601   # 迅捷赐福（祈祷师技能行）
const WEI_LI_CI_FU: int = 1602    # 威力赐福（祈祷师技能行）

## 威力赐福的询问进度：0＝未开始；1＝已询问、等牌的所有者回复；2＝本次命中已处理完
const 威力阶段_未开始: int = 0
const 威力阶段_待回复: int = 1
const 威力阶段_已完成: int = 2

## 借用它的角色（构造时传入；helper 不持有自己的 player / engine）
var 角色: BattleRole = null

var 引擎: BattleEngine:
	get:
		return 角色.engine if 角色 != null else null


var 玩家: BattlePlayer:
	get:
		return 角色.player if 角色 != null else null

## 本次【威力赐福】询问对应的伤害字典；换成新的一份伤害＝新的一次命中，进度归零
var _威力伤害: Dictionary = {}
var _威力阶段: int = 威力阶段_未开始


func _init(借用角色: BattleRole) -> void:
	角色 = 借用角色


## helper 是否已绑定到可用角色（角色、玩家、引擎都在）
func 可用() -> bool:
	return 角色 != null and 角色.player != null and 角色.engine != null


# ============================================================
# 技能栏：两张赐福作为主动法术技能下发
# ============================================================
func available_skills() -> Array:
	var out: Array = []
	if not 可用():
		return out
	out.append(_技能条目(XUN_JIE_CI_FU))
	out.append(_技能条目(WEI_LI_CI_FU))
	return out


func _技能条目(技能号: int) -> Dictionary:
	var 发动牌: Array[int] = 角色.hand_ids_with_skill(技能号)
	# 条件不满足时也要下发（enabled=false 置灰），玩家得看得见技能存在
	return {
		"type": GConst.ActionType.MagicSkill,
		"id": 技能号,
		"need_card": 1,
		"need_target": 1,
		"cards": 发动牌,
		"targets": 可选目标(技能号),
		"enabled": not 发动牌.is_empty(),
	}


## 可放置赐福的队友 id：同色、不含自己、面前没有同类赐福（不区分谁放的，同类全局不叠加）
func 可选目标(技能号: int) -> Array[int]:
	var out: Array[int] = []
	if not 可用():
		return out
	var 自己: BattlePlayer = 角色.player
	return 角色.player_ids_where(func(p: BattlePlayer) -> bool:
		return p.color == 自己.color and find_blessing(p, 技能号, -1) < 0)


# ============================================================
# 主动法术技能：校验 + 放置
# ============================================================
func v_magic_skill(action: Dictionary) -> int:
	if not 可用():
		return GConst.GE_INVALID_ACTION
	if int(action.get("src_id", -1)) != 角色.player.id:
		return GConst.GE_INVALID_PLAYERID
	var 技能号: int = int(action.get("action_id", 0))
	if not _是赐福(技能号):
		return GConst.GE_INVALID_ACTION
	var dsts: Array = action.get("dst_ids", [])
	if dsts.is_empty():
		return GConst.GE_INVALID_ACTION
	var 目标: BattlePlayer = 角色.engine.p(int(dsts[0]))
	if not _目标合法(目标, 技能号):
		return GConst.GE_INVALID_ACTION
	var cards: Array = action.get("card_ids", [])
	if cards.is_empty():
		return GConst.GE_INVALID_CARDID
	var cid: int = int(cards[0])
	var card: GCard = Data.get_card(cid)
	if card == null or not 角色.player.has_hand_card(cid) or not card.has_skill_id(技能号):
		return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	var 技能号: int = int(action.get("action_id", 0))
	if not _是赐福(技能号):
		return GConst.GE_INVALID_ACTION
	var 结果: int = v_magic_skill(action)
	if 结果 != GConst.GE_SUCCESS:
		return 结果
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	var 放: int = 放置赐福(int(cards[0]), int(dsts[0]), 技能号)
	if 放 != GConst.GE_SUCCESS:
		return 放
	return BattleRole.URGENT


## 把手里带该技能的牌放到目标队友面前（供 4606 这类「先选独有技再选目标」的借用方直接调：
## 不需要自己拼 action 字典，也能拿到与主动技能一致的错误码）。
## 成功返回 GE_SUCCESS，并已压入基础效果变更钩子（调用方应返回 URGENT 让引擎先结算）。
func 放置赐福(cid: int, dst_id: int, 技能号: int) -> int:
	if not 可用() or not _是赐福(技能号):
		return GConst.GE_INVALID_ACTION
	var 自己: BattlePlayer = 角色.player
	var card: GCard = Data.get_card(cid)
	if card == null or not 自己.has_hand_card(cid) or not card.has_skill_id(技能号):
		return GConst.GE_INVALID_ACTION
	var 目标: BattlePlayer = 角色.engine.p(dst_id)
	if not _目标合法(目标, 技能号):
		return GConst.GE_INVALID_ACTION
	角色.notice_skill(技能号, [dst_id])
	角色.engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": 自己.id, "dst_id": 自己.id,
		"card_ids": [cid], "is_real": true,
	})
	角色.engine.add_basic_effect(dst_id, cid, 自己.id, 技能号)
	角色.engine.take_from_hand(自己.id, [cid], true)
	角色.engine._broadcast_game()
	return GConst.GE_SUCCESS


# ============================================================
# 威力赐福（1602）：攻击命中时，由牌的所有者决定是否 +2 伤害并移除
# ============================================================
func p_timeline_2_hit(ctx: Dictionary) -> int:
	if not 可用():
		return BattleRole.SUCCESS
	var harm: Dictionary = ctx.get("harm", {})
	# 换成另一份伤害 ＝ 新的一次命中：进度归零（不占角色 step，也不怕同一钩子里别的分支）
	if not is_same(harm, _威力伤害):
		_威力伤害 = harm
		_威力阶段 = 威力阶段_未开始
	if _威力阶段 == 威力阶段_已完成:
		return BattleRole.SUCCESS
	var 攻击者id: int = int(harm.get("src", ctx.get("src", -1)))
	var 攻击者: BattlePlayer = 角色.engine.p(攻击者id)
	if 攻击者 == null or 攻击者.基础效果禁用:
		return BattleRole.SUCCESS
	var 赐福牌: int = find_blessing(攻击者, WEI_LI_CI_FU, 角色.player.id)
	if 赐福牌 < 0:
		return BattleRole.SUCCESS
	var 受伤者id: int = int(harm.get("dst", -1))
	if 受伤者id < 0:
		return BattleRole.SUCCESS
	var 原伤害: int = int(harm.get("point", 0))
	var 伤害类型: int = int(harm.get("type", GConst.HarmType.Attack))
	if _威力阶段 == 威力阶段_未开始:
		# 响应方是牌的所有者（攻击者）；受伤目标固定，作为 targets 下发，客户端自动选中并锁死，
		# 头像上画「原伤害划掉 → +2 后的伤害」
		_威力阶段 = 威力阶段_待回复
		角色.询问(攻击者id, WEI_LI_CI_FU, 0, 0, GConst.CardSource.Hand, [], 0, "", [], true,
			0, -1, [受伤者id], -1, {}, 原伤害, 伤害类型)
		return BattleRole.WAIT
	if not 角色.engine.has_reply():
		return BattleRole.WAIT
	_威力阶段 = 威力阶段_已完成
	if not 角色.take_skill_reply():
		return BattleRole.SUCCESS
	角色.engine.broadcast(GConst.Msg.Skill, {
		"skill_id": WEI_LI_CI_FU, "src_id": 攻击者id, "dst_ids": [攻击者id],
	})
	harm["point"] = 原伤害 + 2
	_移除赐福(攻击者id, 赐福牌, WEI_LI_CI_FU)
	return BattleRole.URGENT


# ============================================================
# 迅捷赐福（1601）：牌的所有者行动结束时授予 +1 攻击行动
# ============================================================
func p_after_attack(ctx: Dictionary) -> int:
	if 可用():
		触发迅捷赐福(int(ctx.get("player", -1)))
	return BattleRole.SUCCESS


func p_after_magic(ctx: Dictionary) -> int:
	if 可用():
		触发迅捷赐福(int(ctx.get("player", -1)))
	return BattleRole.SUCCESS


## 给 pid 授予 +1 攻击行动（持有者面前有【迅捷赐福】且对方有手牌时）。
## 同类赐福全局不叠加，所以只要面前有 1601 即可触发，不区分是谁放的——
## 祈祷师把赐福贴到队友面前时，队友的角色转发本 helper 也能触发。
## 不在这里移除赐福牌：等服务端真正进入这份额外行动时由 p_additional_action 移除。
func 触发迅捷赐福(pid: int) -> void:
	if not 可用():
		return
	var 持有者: BattlePlayer = 角色.engine.p(pid)
	if 持有者 == null or 持有者.hand_cards.is_empty() or 持有者.基础效果禁用:
		return
	for a: Dictionary in 持有者.additional_actions:
		if int(a.get("cause", 0)) == XUN_JIE_CI_FU:
			return
	if find_blessing(持有者, XUN_JIE_CI_FU, -1) < 0:
		return
	# 作为「基础效果授予的额外行动」交给引擎统一确认（确认时移除赐福牌）
	持有者.add_action(GConst.ActionType.Attack, XUN_JIE_CI_FU)


## 牌的所有者选择该额外行动时：移除并弃置赐福牌
func p_additional_action(ctx: Dictionary) -> int:
	if not 可用() or int(ctx.get("cause", 0)) != XUN_JIE_CI_FU:
		return BattleRole.SUCCESS
	var 持有者id: int = int(ctx.get("player", -1))
	var 持有者: BattlePlayer = 角色.engine.p(持有者id)
	if 持有者 == null:
		return BattleRole.SUCCESS
	var 赐福牌: int = find_blessing(持有者, XUN_JIE_CI_FU, -1)
	if 赐福牌 < 0:
		return BattleRole.SUCCESS
	_移除赐福(持有者id, 赐福牌, XUN_JIE_CI_FU)
	return BattleRole.SUCCESS


# ============================================================
# 查询 / 工具
# ============================================================
## 在目标面前找一张带指定技能的基础效果牌；没有返回 -1。
## 来源传 -1 时只按技能号找（同类判重 / 触发 / 移除都用这个口径）；传具体玩家 id 时只看他放的。
func find_blessing(target: BattlePlayer, 技能号: int, 来源: int = -1) -> int:
	if target == null:
		return -1
	for be: Dictionary in target.basic_effects:
		if 来源 >= 0 and int(be.get("src", -1)) != 来源:
			continue
		var card: GCard = Data.get_card(int(be.get("card", -1)))
		if card != null and card.has_skill_id(技能号):
			return int(be["card"])
	return -1


func _是赐福(技能号: int) -> bool:
	return 技能号 == XUN_JIE_CI_FU or 技能号 == WEI_LI_CI_FU


## 赐福目标是否合法：同色队友（不含自己）且面前没有同类赐福（同类赐福不叠加）
func _目标合法(目标: BattlePlayer, 技能号: int) -> bool:
	if 目标 == null or not 可用():
		return false
	if 目标.id == 角色.player.id or 目标.color != 角色.player.color:
		return false
	# 同类赐福全局不叠加（不区分来源）
	return find_blessing(目标, 技能号, -1) < 0


## 移除赐福牌 + 进弃牌堆（发动者记本角色，供 p_basic_effect_change / 天使羁绊这类钩子区分）
func _移除赐福(dst_id: int, card_id: int, 技能号: int) -> void:
	if not 可用():
		return
	# 虚空境：目标的基础效果一律不触发，赐福也不消耗
	if 角色.engine.基础效果被禁止(dst_id):
		return
	角色.engine.remove_basic_effect(dst_id, card_id, 技能号, 角色.player.id)
	角色.engine.to_discard([card_id])
	角色.engine._broadcast_game()
