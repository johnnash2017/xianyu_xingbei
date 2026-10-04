class_name BattlePlayer
extends RefCounted
## 战斗玩家实体（对照服务端 DiceGameServer/PlayerEntity）
## 权威数据：手牌/盖牌/基础效果/独有效果/个人能量/治疗/横置/指示物/额外行动

var id: int = 0
var role_id: int = 0
var color: int = GConst.BLUE          # 1 红 / 0 蓝
var player_name: String = ""

var hand_cards: Array[int] = []
var hand_cards_max: int = GConst.HAND_CARDS_MAX
var cover_cards: Array[int] = []
var cover_cards_max: int = 0
var basic_effects: Array[Dictionary] = []   # [{card:int, src:int}]
var exclusive_effects: Array[bool] = [false, false, false, false, false]

var gem: int = 0
var crystal: int = 0
var energy_max: int = GConst.ENERGY_MAX
var cross_num: int = 0
var cross_max: int = GConst.CROSS_MAX

var _形态: bool = false
## 形态（横置）：进入/退出的通知统一走 setter —— 写战斗日志 + 触发 p_tap 钩子。
## 所以任何位置直接写 player.tap = X 都与 engine.set_tap(player.id, X) 等价，不会绕过日志
var tap: bool:
	get: return _形态
	set(v):
		var 变了: bool = v != _形态
		_形态 = v
		if engine != null:
			engine.形态变更(self, v, 变了)
var tokens: Array = [null, null, null]      # [{name, max, num}]

var pre_id: int = -1
var post_id: int = -1
var additional_actions: Array[Dictionary] = []   # [{allow_action:int, cause:int}]

## 本回合是否已发动过「启动」技能（角色 is_free_skill 认可的那些）：
## 规则是每回合所有启动技能里只能发动一个，发动后其余启动技能不再下发、再点也会被拒。
## 由引擎在回合开始清零（SCheckTurnStart），发动成功时由角色把它置 true
var boot_skill_used: bool = false

var ready: bool = false
var online: bool = true

## 角色对象（未移植的角色为 null，按通用规则结算）
var role: BattleRole = null
## 所属引擎（服务端权威）。tap 的 setter 靠它通知形态变化（写日志 / 触发 p_tap）
var engine: BattleEngine = null


func _init(pid: int = 0, c: int = GConst.BLUE, nm: String = "") -> void:
	id = pid
	color = c
	player_name = nm


# ============================================================
# 手牌
# ============================================================
func add_hand_cards(cards: Array) -> void:
	for c: Variant in cards:
		hand_cards.append(int(c))


func remove_hand_cards(cards: Array) -> void:
	for c: Variant in cards:
		var cid: int = int(c)
		# 精灵射手(32) 可能是从盖牌区打出的（她的盖牌算手牌），手牌里没有就去盖牌里删
		if hand_cards.has(cid):
			hand_cards.erase(cid)
		else:
			cover_cards.erase(cid)


## 手牌里有没有这张牌（对照服务端 PlayerEntity::checkOneHandCard）：
## 精灵射手(32) 的盖牌同时算手牌 —— 她的【祝福】盖牌可以直接当手牌打出
func has_hand_card(cid: int) -> bool:
	if hand_cards.has(cid):
		return true
	return role_id == 32 and cover_cards.has(cid)


func hand_count() -> int:
	return hand_cards.size()


# ============================================================
# 盖牌
# ============================================================
func add_cover_cards(cards: Array) -> void:
	for c: Variant in cards:
		cover_cards.append(int(c))


func remove_cover_cards(cards: Array) -> void:
	for c: Variant in cards:
		cover_cards.erase(int(c))


func cover_count() -> int:
	return cover_cards.size()


# ============================================================
# 基础效果
# ============================================================
func add_basic_effect(card_id: int, src: int) -> void:
	basic_effects.append({"card": card_id, "src": src})


func remove_basic_effect(card_id: int) -> void:
	for i: int in range(basic_effects.size() - 1, -1, -1):
		if int(basic_effects[i]["card"]) == card_id:
			basic_effects.remove_at(i)
			return


## 是否拥有某张卡名的基础效果
func check_basic_effect_name(card_name: int) -> bool:
	for e: Dictionary in basic_effects:
		var c: GCard = Data.get_card(int(e["card"]))
		if c != null and c.card_name_enum() == card_name:
			return true
	return false


## 是否拥有带某个技能的基础效果（技能号见 技能表，如【天使之墙】= 701）
func check_basic_effect_skill(技能号: int) -> bool:
	for e: Dictionary in basic_effects:
		var c: GCard = Data.get_card(int(e["card"]))
		if c != null and c.has_skill_id(技能号):
			return true
	return false


# ============================================================
# 独有效果
# ============================================================
func add_exclusive_effect(idx: int) -> void:
	if idx >= 0 and idx < GConst.EXCLUSIVE_NUM:
		exclusive_effects[idx] = true


func remove_exclusive_effect(idx: int) -> void:
	if idx >= 0 and idx < GConst.EXCLUSIVE_NUM:
		exclusive_effects[idx] = false


func check_exclusive_effect(idx: int) -> bool:
	if idx >= 0 and idx < GConst.EXCLUSIVE_NUM:
		return exclusive_effects[idx]
	return false


# ============================================================
# 治疗 / 能量
# ============================================================
## 加治疗：不超过上限 cross_max；但若当前已因「突破上限」而高于上限，则只加不减 ——
## 否则超过上限后再加一次治疗会被硬拉回上限（治疗倒退）。所有加治疗都该经这里（或引擎的
## add_cross / add_cross_pierce），不要直接写 cross_num
func add_cross_num(v: int) -> void:
	cross_num = maxi(mini(cross_num + v, cross_max), cross_num)


func sub_cross_num(v: int) -> void:
	cross_num = maxi(cross_num - v, 0)


## 能量（宝石 / 水晶）：两项之和不超过上限（对照服务端 PlayerEntity::setGem / setCrystal，
## 原版是「加上另一项再截断」，所以对已有水晶的角色 +宝石会把宝石压到 上限－水晶）
func set_gem(v: int) -> void:
	gem = clampi(v, 0, maxi(energy_max - crystal, 0))


func set_crystal(v: int) -> void:
	crystal = clampi(v, 0, maxi(energy_max - gem, 0))


func get_energy() -> int:
	return gem + crystal


# ============================================================
# 额外行动
# ============================================================
## 代替应战者 id（-1 表示无）：本玩家受到攻击时由其代替应战（如阴阳师式神咒束）
var reattacker: int = -1


## direct=true 的额外行动不需要询问、也不用玩家再点一次技能按钮：引擎会直接进入它的额外行动阶段
## （该阶段允许「放弃行动」，想跳过在那里放弃即可）。
## 判定标准：这份额外行动「被选中」时不额外消耗代价（p_additional_action 无扣费/无移除资源）。
## 代价在选中时才结算的（如剑圣【剑影】扣能量、剑帝【不屈意志】扣能量）仍要询问，保留玩家「不付代价退出」的权利。
func add_action(allow_action: int, cause: int, direct: bool = false) -> void:
	additional_actions.append({"allow_action": allow_action, "cause": cause, "direct": direct})


## 额外行动「被选中」时的二次校验（角色可覆写）
func v_additional_action(cause: int) -> int:
	if role != null:
		var rc: int = role.v_additional_action(cause)
		if rc != BattleRole.V_NOT_OVERRIDE:
			return rc
	return GConst.GE_SUCCESS


func contains_action() -> bool:
	return not additional_actions.is_empty()


func clear_additional_action() -> void:
	additional_actions.clear()


# ============================================================
# 动作合法性校验
# 通用实现放在 base_v_*；v_* 先问角色（角色可覆写/追加限制），角色无意见时用通用实现
# 角色侧通过 BattleRole.V_NOT_OVERRIDE 表示「不覆写」
# ============================================================
func v_allow_action(action_type: int, args: Array, allow: int, can_give_up: bool) -> int:
	if role != null:
		var rc: int = role.v_allow_action(action_type, args, allow, can_give_up)
		if rc != BattleRole.V_NOT_OVERRIDE:
			return rc
	return base_v_allow_action(action_type, args, allow, can_give_up)


## 是否允许宣告「无法行动」（对照服务端 PlayerEntity::v_unactional，默认总是允许；角色可覆写）
func v_unactional() -> int:
	if role != null:
		var rc: int = role.v_unactional()
		if rc != BattleRole.V_NOT_OVERRIDE:
			return rc
	return GConst.GE_SUCCESS


## 总校验（对照服务端 PlayerEntity::v_allow_action(action, allow, canGiveUp)）：
## allow = 本行动阶段放行的种类（Any / Attack / AttackMagic …），技能类归入它对应的基础种类；
## 「无法行动」只有正常行动阶段（allow = Any）能宣告；「放弃行动」只在 can_give_up 时合法
func base_v_allow_action(action_type: int, _args: Array, allow: int, can_give_up: bool) -> int:
	if GConst.放行动作(action_type, allow):
		return GConst.GE_SUCCESS
	# 只有正常行动阶段能宣告「无法行动」
	if allow == GConst.ActionType.Any and action_type == GConst.ActionType.Unactional:
		return v_unactional()
	if can_give_up and action_type == GConst.ActionType.None:
		return GConst.GE_SUCCESS
	return GConst.GE_INVALID_ACTION


## 攻击校验
func v_attack(card_id: int, dst_id: int, players: Dictionary) -> int:
	if role != null:
		var rc: int = role.v_attack(card_id, dst_id, players)
		if rc != BattleRole.V_NOT_OVERRIDE:
			return rc
	return base_v_attack(card_id, dst_id, players)


## 攻击校验通用实现：面前有【挑衅】时只能打勇者、目标不同队、持有该攻击牌
func base_v_attack(card_id: int, dst_id: int, players: Dictionary) -> int:
	# 对照服务端 PlayerEntity::v_attack 开头：攻击者面前有【挑衅】时，目标只能是勇者（roleID 21）
	if check_exclusive_effect(GConst.Exclusive.TiaoXin):
		var 挑衅目标: BattlePlayer = players.get(dst_id)
		if 挑衅目标 == null or 挑衅目标.role_id != 21:
			return GConst.GE_INVALID_PLAYERID
	var dst: BattlePlayer = players.get(dst_id)
	if dst == null:
		return GConst.GE_INVALID_PLAYERID
	if dst.color == color:
		return GConst.GE_INVALID_PLAYERID
	if not has_hand_card(card_id):
		return GConst.GE_HANDCARD_NOT_FOUND
	var card: GCard = Data.get_card(card_id)
	if card == null or not card.is_attack():
		return GConst.GE_INVALID_CARDID
	return GConst.GE_SUCCESS


## 应战校验
func v_reattack(card_id: int, attack_card_id: int) -> int:
	if role != null:
		var rc: int = role.v_reattack(card_id, attack_card_id)
		if rc != BattleRole.V_NOT_OVERRIDE:
			return rc
	return base_v_reattack(card_id, attack_card_id)


## 应战校验通用实现：暗系可应战任意系，否则需同系
func base_v_reattack(card_id: int, attack_card_id: int) -> int:
	if not has_hand_card(card_id):
		return GConst.GE_HANDCARD_NOT_FOUND
	var card: GCard = Data.get_card(card_id)
	var atk: GCard = Data.get_card(attack_card_id)
	if card == null or atk == null or not card.is_attack():
		return GConst.GE_INVALID_CARDID
	if atk.element_enum() == GConst.CardElement.Darkness:
		return GConst.GE_INVALID_ACTION
	if card.element_enum() != atk.element_enum() and card.element_enum() != GConst.CardElement.Darkness:
		return GConst.GE_INVALID_CARDID
	return GConst.GE_SUCCESS


## 格挡校验（圣光）
func v_block(card_id: int) -> int:
	if role != null:
		var rc: int = role.v_block(card_id)
		if rc != BattleRole.V_NOT_OVERRIDE:
			return rc
	return base_v_block(card_id)


func base_v_block(card_id: int) -> int:
	if not has_hand_card(card_id):
		return GConst.GE_HANDCARD_NOT_FOUND
	var card: GCard = Data.get_card(card_id)
	if card == null or card.card_name_enum() != GConst.CardName.HolyLight:
		return GConst.GE_INVALID_CARDID
	return GConst.GE_SUCCESS


## 魔弹校验
func v_missile(card_id: int, dst_id: int) -> int:
	if role != null:
		var rc: int = role.v_missile(card_id, dst_id)
		if rc != BattleRole.V_NOT_OVERRIDE:
			return rc
	return base_v_missile(card_id, dst_id)


func base_v_missile(card_id: int, _dst_id: int) -> int:
	if not has_hand_card(card_id):
		return GConst.GE_HANDCARD_NOT_FOUND
	var card: GCard = Data.get_card(card_id)
	if card == null or card.card_name_enum() != GConst.CardName.Missile:
		return GConst.GE_INVALID_CARDID
	return GConst.GE_SUCCESS


## 响应魔弹（转弹）校验
func v_remissile(card_id: int) -> int:
	if role != null:
		var rc: int = role.v_remissile(card_id)
		if rc != BattleRole.V_NOT_OVERRIDE:
			return rc
	return base_v_remissile(card_id)


func base_v_remissile(card_id: int) -> int:
	if not has_hand_card(card_id):
		return GConst.GE_HANDCARD_NOT_FOUND
	var card: GCard = Data.get_card(card_id)
	if card == null or card.card_name_enum() != GConst.CardName.Missile:
		return GConst.GE_INVALID_CARDID
	return GConst.GE_SUCCESS


## 圣盾校验
func v_shield(dst_id: int, players: Dictionary) -> int:
	if role != null:
		var rc: int = role.v_shield(dst_id, players)
		if rc != BattleRole.V_NOT_OVERRIDE:
			return rc
	return base_v_shield(dst_id, players)


## 格挡校验（圣盾）：对照服务端 PlayerEntity::v_shield —— 目标面前已有【圣盾】或
## 【天使之墙】都不能再放（【天使之墙】视作圣盾）
func base_v_shield(dst_id: int, players: Dictionary) -> int:
	var dst: BattlePlayer = players.get(dst_id)
	if dst == null:
		return GConst.GE_INVALID_PLAYERID
	if dst.check_basic_effect_name(GConst.CardName.Shield) or dst.check_basic_effect_skill(GConst.技能_天使之墙):
		return GConst.GE_BASIC_EFFECT_ALREADY_EXISTS
	return GConst.GE_SUCCESS


## 虚弱校验
func v_weaken(dst_id: int, players: Dictionary) -> int:
	if role != null:
		var rc: int = role.v_weaken(dst_id, players)
		if rc != BattleRole.V_NOT_OVERRIDE:
			return rc
	return base_v_weaken(dst_id, players)


func base_v_weaken(dst_id: int, players: Dictionary) -> int:
	var dst: BattlePlayer = players.get(dst_id)
	if dst == null:
		return GConst.GE_INVALID_PLAYERID
	if dst.check_basic_effect_name(GConst.CardName.Weaken):
		return GConst.GE_BASIC_EFFECT_ALREADY_EXISTS
	return GConst.GE_SUCCESS


## 购买校验
func v_buy(args: Array) -> int:
	if role != null:
		var rc: int = role.v_buy(args)
		if rc != BattleRole.V_NOT_OVERRIDE:
			return rc
	return base_v_buy(args)


## 购买校验（对照服务端 PlayerEntity::v_buy）：手牌留得下 3 张，宝石、水晶各自最多买 1 点
func base_v_buy(args: Array) -> int:
	if hand_cards.size() + 3 > hand_cards_max:
		return GConst.GE_INVALID_ACTION
	if args.size() < 2:
		return GConst.GE_INVALID_ARGUMENT
	var 买宝石: int = int(args[0])
	var 买水晶: int = int(args[1])
	if (买宝石 == 0 or 买宝石 == 1) and (买水晶 == 0 or 买水晶 == 1):
		return GConst.GE_SUCCESS
	return GConst.GE_INVALID_ACTION


## 被攻击校验（防守方视角，角色可拒绝被选为目标）
func v_attacked() -> int:
	if role != null:
		var rc: int = role.v_attacked()
		if rc != BattleRole.V_NOT_OVERRIDE:
			return rc
	return GConst.GE_SUCCESS


## 合成校验（对照服务端 PlayerEntity::v_synthesize）：
## 手牌留得下 3 张、队伍能量 ≥ 3，且这次要花的宝石＋水晶正好 3 点、各自不超过队伍存量
func v_synthesize(args: Array, team_energy: int, team_gem: int, team_crystal: int) -> int:
	if hand_cards.size() + 3 > hand_cards_max:
		return GConst.GE_INVALID_ACTION
	if team_energy < 3:
		return GConst.GE_INVALID_ACTION
	if args.size() < 2:
		return GConst.GE_INVALID_ARGUMENT
	var 花宝石: int = int(args[0])
	var 花水晶: int = int(args[1])
	if 花宝石 + 花水晶 != 3 or 花宝石 > team_gem or 花水晶 > team_crystal:
		return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


## 提炼校验（角色可覆写，如冒险家【冒险者天堂】把提炼出的星石给队友时按队友空位算）
func v_extract(args: Array, team_gem: int, team_crystal: int, dst_id: int = -1) -> int:
	if role != null:
		var rc: int = role.v_extract(args, team_gem, team_crystal, dst_id)
		if rc != BattleRole.V_NOT_OVERRIDE:
			return rc
	return base_v_extract(args, team_gem, team_crystal)


## 提炼校验（对照服务端 PlayerEntity::v_extract）：
## 要提的宝石 / 水晶不超过队伍存量，且自己的能量没满
func base_v_extract(args: Array, team_gem: int, team_crystal: int) -> int:
	if args.size() < 2:
		return GConst.GE_INVALID_ARGUMENT
	if int(args[0]) > team_gem or int(args[1]) > team_crystal or get_energy() >= energy_max:
		return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


## 序列化为 SinglePlayerInfo 字段字典
func to_proto(viewer_id: int) -> Dictionary:
	var d: Dictionary = {
		"id": id,
		"team": color,
		"role_id": role_id,
		"hand_count": hand_cards.size(),
		"heal_count": cross_num,
		# 治疗上限：角色被动会改（神官 +4 等），客户端按它画治疗格的空位
		"max_heal": cross_max,
		# 能量上限：角色被动会改（如贤者 +1），客户端判「星石已满 / 还有空位」要用它
		"max_energy": energy_max,
		"gem": gem,
		"crystal": crystal,
		"covered_count": cover_cards.size(),
		"is_knelt": tap,
		"max_hand": hand_cards_max,
		"nickname": player_name,
		"ready": ready,
		"online": online,
		"leader": 0,
	}
	var bas: Array = []
	for e: Dictionary in basic_effects:
		bas.append(int(e["card"]))
	d["basic_cards"] = bas
	var exs: Array = []
	for i: int in range(GConst.EXCLUSIVE_NUM):
		if exclusive_effects[i]:
			exs.append(i)
	d["ex_cards"] = exs
	# 只有本人能看到自己的手牌/盖牌
	if viewer_id == id:
		d["hands"] = hand_cards.duplicate()
		d["covereds"] = cover_cards.duplicate()
	var yellow: int = 0
	var blue: int = 0
	var third: int = 0
	if tokens[0] != null:
		third = int(tokens[0]["num"])
	if tokens[1] != null:
		yellow = int(tokens[1]["num"])
	if tokens[2] != null:
		blue = int(tokens[2]["num"])
	d["yellow_token"] = yellow
	d["blue_token"] = blue
	d["third_token"] = third
	return d
