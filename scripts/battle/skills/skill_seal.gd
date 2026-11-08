extends RefCounted
## 五系封印（401~405）的借用 helper（F5-D）。
##
## 封印师（4）的独有技会在 46 灵熙之潮【海神御巫】（4606）里被借用：手里那张带
## 【风之封印】~【雷之封印】的牌，照原角色规则放到目标对手面前，该对手之后打出 / 展示出
## 同系牌时强制触发「3 点法术伤害并移除封印」。这里把 role_fengyin.gd 的「放置 + 展示触发」
## 抽成 helper **只复用、不改动** role_fengyin.gd，保证 4 号封印师行为不回归。
##
## 借用角色的接法（在自己的 v_* / p_* 里路由）：
##   const SkillSeal = preload("res://scripts/battle/skills/skill_seal.gd")
##   var _封印: SkillSeal
##   func setup(p: BattlePlayer, e: BattleEngine) -> void:
##       super.setup(p, e)
##       _封印 = SkillSeal.new(self)              # 构造传借用角色本身
##   func available_skills() -> Array:            # 需要直接摆出五系封印时
##       return _封印.available_skills()
##   func v_magic_skill(action: Dictionary) -> int:
##       return _封印.v_place(action, 借用技能号)  # 借用自己的技能行（如 4606）时传牌上带的 401~405
##   func p_magic_skill(action: Dictionary) -> int:
##       return _封印.p_place(action, 借用技能号)
##   func p_show_hand(ctx: Dictionary) -> int:
##       return _封印.p_show_hand(ctx)
##
## 判定口径与 role_fengyin.gd 一致：
## - 放置：牌必须在手里且带对应封印技能号；目标必须是异色、且身上没有同种封印；
## - 触发：展示 = 基础效果里的「攻击牌 + 幻命格」视为封印牌，按牌面系别与本次展示的牌比对；
##   不校验封印是谁布的（多封印师 / 借用者同场时各自结算，靠 ctx["seals_triggered"] 防重复）。

## 五系封印技能号（技能表：401 风 / 402 水 / 403 火 / 404 地 / 405 雷）
const 风之封印: int = 401
const 水之封印: int = 402
const 火之封印: int = 403
const 地之封印: int = 404
const 雷之封印: int = 405
const 封印技能号列表: Array[int] = [风之封印, 水之封印, 火之封印, 地之封印, 雷之封印]

## 封印触发时的法术伤害（技能原文：3 点法术伤害）
const 封印伤害: int = 3

## 借用角色（只读；构造时传入）
var 角色: BattleRole = null


var 引擎: BattleEngine:
	get:
		return 角色.engine if 角色 != null else null


var 玩家: BattlePlayer:
	get:
		return 角色.player if 角色 != null else null


func _init(借用角色: BattleRole) -> void:
	角色 = 借用角色


# ============================================================
# 静态判定
# ============================================================
## 是不是「封印牌」：攻击牌 + 幻命格（与 role_fengyin.gd 的 _is_seal_card 同口径）。
## 展示触发不按技能号认封印牌，也不校验是谁布的（与原角色一致）。
static func 是封印牌(card: GCard) -> bool:
	return card != null and card.is_attack() and card.fate_pattern_enum() == GConst.FatePattern.Phantom


## 元素 → 对应封印技能号
static func 封印技能号(元素值: int) -> int:
	match 元素值:
		GConst.CardElement.Wind:
			return 风之封印
		GConst.CardElement.Water:
			return 水之封印
		GConst.CardElement.Fire:
			return 火之封印
		GConst.CardElement.Earth:
			return 地之封印
		GConst.CardElement.Thunder:
			return 雷之封印
	return 0


## 封印技能号 → 元素
static func 封印元素(技能号值: int) -> int:
	match 技能号值:
		风之封印:
			return GConst.CardElement.Wind
		水之封印:
			return GConst.CardElement.Water
		火之封印:
			return GConst.CardElement.Fire
		地之封印:
			return GConst.CardElement.Earth
		雷之封印:
			return GConst.CardElement.Thunder
	return 0


# ============================================================
# 可选牌 / 合法目标 / 技能栏
# ============================================================
## 本 helper 支持的五系封印技能号（默认 401~405）
func 技能号列表() -> Array[int]:
	return 封印技能号列表.duplicate()


## 手里带指定封印技能的牌（技能栏的 "cards" 与 v_place 共用同一口径，
## 否则会出现「界面让点、服务端拒收」或「该亮的没亮」）
func 手上封印牌(技能号值: int) -> Array[int]:
	var out: Array[int] = []
	if 玩家 == null:
		return out
	for cid: int in 玩家.hand_cards:
		var card: GCard = Data.get_card(cid)
		if card != null and card.has_skill_id(技能号值):
			out.append(cid)
	return out


## 该封印的合法目标：异色、且身上没有同种封印（与 v_place 的校验完全一致）
func 合法目标(技能号值: int) -> Array[int]:
	if 角色 == null or 玩家 == null:
		var 空: Array[int] = []
		return 空
	var 自己: BattlePlayer = 玩家
	return 角色.player_ids_where(func(p: BattlePlayer) -> bool:
		return p.color != 自己.color and not p.check_basic_effect_skill(技能号值))


## 技能栏里的五系封印条目（结构对照 role_fengyin.gd.available_skills）：
## 没有对应封印牌时照样下发条目，只把 enabled 置 false（界面半透明、点不动）。
func available_skills() -> Array:
	var out: Array = []
	if 角色 == null or 玩家 == null:
		return out
	for 号: int in 封印技能号列表:
		var 封印牌: Array[int] = 手上封印牌(号)
		out.append({
			"type": GConst.ActionType.MagicSkill, "id": 号, "need_card": 1, "need_target": 1,
			"cards": 封印牌, "enabled": not 封印牌.is_empty(),
			"targets": 合法目标(号),
		})
	return out


# ============================================================
# 放置（借用角色的 v_magic_skill / p_magic_skill 转发）
# ============================================================
## 放置校验。借用的技能号：0 = 用 action.action_id；借用自己的技能行（如 4606）时，
## 传牌上实际带的封印号（401~405），播报与基础效果的 cause 都会用这个号。
func v_place(action: Dictionary, 借用的技能号: int = 0) -> int:
	if 角色 == null or 引擎 == null or 玩家 == null:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("src_id", -1)) != 玩家.id:
		return GConst.GE_INVALID_PLAYERID
	var aid: int = 借用的技能号 if 借用的技能号 != 0 else int(action.get("action_id", 0))
	if not 封印技能号列表.has(aid):
		return GConst.GE_INVALID_ACTION
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	if cards.is_empty() or dsts.is_empty():
		return GConst.GE_INVALID_CARDID
	var cid: int = int(cards[0])
	var card: GCard = Data.get_card(cid)
	if not 玩家.has_hand_card(cid) or card == null or not card.has_skill_id(aid):
		return GConst.GE_INVALID_ACTION
	var dst: BattlePlayer = 引擎.p(int(dsts[0]))
	if dst == null or dst.color == 玩家.color or dst.check_basic_effect_skill(aid):
		return GConst.GE_INVALID_PLAYERID
	return GConst.GE_SUCCESS


## 放置结算：展示封印牌 → 挂到目标对手的基础效果区 → 封印牌离手（触发展示钩子）。
## 返回 URGENT：基础效果变动 / 展示都压了钩子，本次技能行动要等它们结算完（与原角色一致）。
func p_place(action: Dictionary, 借用的技能号: int = 0) -> int:
	if 角色 == null or 引擎 == null or 玩家 == null:
		return BattleRole.SUCCESS
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	if cards.is_empty() or dsts.is_empty():
		return BattleRole.SUCCESS
	var aid: int = 借用的技能号 if 借用的技能号 != 0 else int(action.get("action_id", 0))
	var cid: int = int(cards[0])
	var dst_id: int = int(dsts[0])
	角色.notice_skill(aid, [dst_id])
	引擎.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": 玩家.id, "dst_id": dst_id,
		"card_ids": [cid], "is_real": true,
	})
	引擎.add_basic_effect(dst_id, cid, 玩家.id, aid)
	引擎.take_from_hand(玩家.id, [cid], true)
	引擎._broadcast_game()
	return BattleRole.URGENT


# ============================================================
# 展示触发（借用角色的 p_show_hand 转发）
# ============================================================
## 目标打出手牌 / 展示牌后：遍历他面前的基础效果，每张封印牌各自比对本次展示牌的系别；
## 命中则「3 点法术伤害 + 移除封印」，返回 URGENT 让引擎先结算这次伤害、再回到本钩子
## 继续触发同一玩家身上的其它封印。ctx["seals_triggered"] 记本批已触发过的封印牌，
## 多封印师 / 多个借用者同场时不会把同一张封印结算两次。
func p_show_hand(ctx: Dictionary) -> int:
	if 角色 == null or 引擎 == null or 玩家 == null:
		return BattleRole.SUCCESS
	var target: BattlePlayer = 引擎.p(int(ctx.get("player", -1)))
	if target == null or target.基础效果禁用:
		return BattleRole.SUCCESS
	var 已触发: Array = ctx.get("seals_triggered", [])
	var 展示牌: Array = ctx.get("cards", [])
	for 效果: Dictionary in target.basic_effects:
		var 封印牌: int = int(效果["card"])
		if 已触发.has(封印牌):
			continue
		var 封印: GCard = Data.get_card(封印牌)
		if not 是封印牌(封印):
			continue
		var 元素值: int = 封印.element_enum()
		for 牌: Variant in 展示牌:
			var 展示: GCard = Data.get_card(int(牌))
			if 展示 == null or 展示.element_enum() != 元素值:
				continue
			_触发封印(target, 封印牌, 元素值)
			已触发.append(封印牌)
			ctx["seals_triggered"] = 已触发
			return BattleRole.URGENT
	return BattleRole.SUCCESS


## 封印触发结算：播报 → 移除基础效果 → 封印牌进弃牌堆 → 3 点法术伤害（来源＝借用者）
func _触发封印(target: BattlePlayer, 封印牌: int, 元素值: int) -> void:
	var cause: int = 封印技能号(元素值)
	角色.notice_skill(cause, [target.id])
	引擎.remove_basic_effect(target.id, 封印牌, cause, 玩家.id)
	引擎.to_discard([封印牌])
	引擎.push_harm({
		"src": 玩家.id, "dst": target.id, "point": 封印伤害,
		"cause": cause, "type": GConst.HarmType.Magic,
	})
	引擎._broadcast_game()
