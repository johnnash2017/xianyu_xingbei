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

var tap: bool = false
var tokens: Array = [null, null, null]      # [{name, max, num}]

var pre_id: int = -1
var post_id: int = -1
var additional_actions: Array[Dictionary] = []   # [{allow_action:int, cause:int}]

var ready: bool = false
var online: bool = true

## 角色对象（未移植的角色为 null，按通用规则结算）
var role: BattleRole = null


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
		hand_cards.erase(int(c))


func has_hand_card(cid: int) -> bool:
	return hand_cards.has(cid)


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


## 是否拥有某个特技标签的基础效果
func check_basic_effect_tag(tag: String) -> bool:
	for e: Dictionary in basic_effects:
		var c: GCard = Data.get_card(int(e["card"]))
		if c != null and c.has_speciality_name(tag):
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
func add_cross_num(v: int) -> void:
	cross_num = mini(cross_num + v, cross_max)


func sub_cross_num(v: int) -> void:
	cross_num = maxi(cross_num - v, 0)


func set_gem(v: int) -> void:
	gem = clampi(v, 0, energy_max)


func set_crystal(v: int) -> void:
	crystal = clampi(v, 0, energy_max)


func get_energy() -> int:
	return gem + crystal


# ============================================================
# 额外行动
# ============================================================
## 代替应战者 id（-1 表示无）：本玩家受到攻击时由其代替应战（如阴阳师式神咒束）
var reattacker: int = -1


func add_action(allow_action: int, cause: int) -> void:
	additional_actions.append({"allow_action": allow_action, "cause": cause})


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
func v_allow_action(action_type: int, args: Array) -> int:
	if role != null:
		var rc: int = role.v_allow_action(action_type, args)
		if rc != BattleRole.V_NOT_OVERRIDE:
			return rc
	return base_v_allow_action(action_type, args)


## 总校验：当前玩家是否被允许执行该类型动作
func base_v_allow_action(action_type: int, _args: Array) -> int:
	match action_type:
		GConst.ActionType.None, GConst.ActionType.Unactional:
			return GConst.GE_SUCCESS
		GConst.ActionType.Any:
			return GConst.GE_SUCCESS
		GConst.ActionType.Attack, GConst.ActionType.AttackSkill:
			return GConst.GE_SUCCESS
		GConst.ActionType.Magic, GConst.ActionType.MagicSkill:
			return GConst.GE_SUCCESS
		GConst.ActionType.Special, GConst.ActionType.SpecialSkill:
			return GConst.GE_SUCCESS
		GConst.ActionType.AttackMagic:
			return GConst.GE_SUCCESS
	return GConst.GE_INVALID_ACTION


## 攻击校验
func v_attack(card_id: int, dst_id: int, players: Dictionary) -> int:
	if role != null:
		var rc: int = role.v_attack(card_id, dst_id, players)
		if rc != BattleRole.V_NOT_OVERRIDE:
			return rc
	return base_v_attack(card_id, dst_id, players)


## 攻击校验通用实现：目标不同队、持有该攻击牌
func base_v_attack(card_id: int, dst_id: int, players: Dictionary) -> int:
	var dst: BattlePlayer = players.get(dst_id)
	if dst == null:
		return GConst.GE_INVALID_PLAYERID
	if dst.color == color:
		return GConst.GE_INVALID_ACTION
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


func base_v_shield(dst_id: int, players: Dictionary) -> int:
	var dst: BattlePlayer = players.get(dst_id)
	if dst == null:
		return GConst.GE_INVALID_PLAYERID
	if dst.check_basic_effect_name(GConst.CardName.Shield):
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


func base_v_buy(args: Array) -> int:
	if hand_cards.size() + 3 > hand_cards_max:
		return GConst.GE_CARD_NOT_ENOUGH
	if args.size() < 2:
		return GConst.GE_INVALID_ARGUMENT
	return GConst.GE_SUCCESS


## 被攻击校验（防守方视角，角色可拒绝被选为目标）
func v_attacked() -> int:
	if role != null:
		var rc: int = role.v_attacked()
		if rc != BattleRole.V_NOT_OVERRIDE:
			return rc
	return GConst.GE_SUCCESS


## 合成校验
func v_synthesize(args: Array, team_energy: int) -> int:
	if hand_cards.size() + 3 > hand_cards_max:
		return GConst.GE_CARD_NOT_ENOUGH
	if team_energy < 3:
		return GConst.GE_CARD_NOT_ENOUGH
	if args.size() < 2:
		return GConst.GE_INVALID_ARGUMENT
	return GConst.GE_SUCCESS


## 提炼校验
func v_extract(args: Array, team_gem: int, team_crystal: int) -> int:
	if args.size() < 2:
		return GConst.GE_INVALID_ARGUMENT
	if get_energy() >= energy_max:
		return GConst.GE_INVALID_ACTION
	if int(args[0]) > team_gem or int(args[1]) > team_crystal:
		return GConst.GE_CARD_NOT_ENOUGH
	return GConst.GE_SUCCESS


## 序列化为 SinglePlayerInfo 字段字典
func to_proto(viewer_id: int) -> Dictionary:
	var d: Dictionary = {
		"id": id,
		"team": color,
		"role_id": role_id,
		"hand_count": hand_cards.size(),
		"heal_count": cross_num,
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
