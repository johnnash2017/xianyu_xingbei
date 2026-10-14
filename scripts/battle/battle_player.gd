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
## 与 exclusive_effects 一一对应：每张专属牌是谁放的（-1＝没记）。
## 【挑衅】要靠它知道「被挑衅的人只能主动攻击哪个玩家」（见 exclusive_owner / base_v_attack）
var exclusive_owners: Array[int] = [-1, -1, -1, -1, -1]

var gem: int = 0
var crystal: int = 0
var energy_max: int = GConst.ENERGY_MAX
var cross_num: int = 0
## 治疗上限：只限制「之后还能再加到多少」。升、降上限都不回收当前治疗量 ——
## 上限被降下来时（如圣枪【神圣信仰】星杯数被对方反超），已拥有的治疗照旧留着，不压到新上限。
## 只有「花掉 / 被移除治疗」才会让 cross_num 下降（sub_cross_num）
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

## 角色对象（未移植的角色为 null，按通用规则结算）。
## 绑定（setup：写 player/engine、按表初始化标识物、角色自身的开局加成）由 BattleRole.create() 负责，
## 这里只做「挂上 / 卸下」与旧角色的解绑 —— 再调一次 setup 会让角色加成重复结算（如神官治疗上限 +4 变 +8）
var _role: BattleRole = null
var role: BattleRole:
	get: return _role
	set(value):
		if _role != value:
			if _role != null:
				_role.player = null
				_role.engine = null
			_role = value
## 所属引擎（服务端权威）。tap 的 setter 靠它通知形态变化（写日志 / 触发 p_tap）
var _engine_ref: WeakRef = null
var engine: BattleEngine:
	get: return _engine_ref.get_ref() as BattleEngine if _engine_ref != null else null
	set(value): _engine_ref = weakref(value) if value != null else null


func _init(pid: int = 0, c: int = GConst.BLUE, nm: String = "") -> void:
	id = pid
	color = c
	player_name = nm


func 解绑() -> void:
	role = null
	engine = null


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
func add_exclusive_effect(idx: int, 放牌者: int = -1) -> void:
	if idx >= 0 and idx < GConst.EXCLUSIVE_NUM:
		exclusive_effects[idx] = true
		exclusive_owners[idx] = 放牌者


func remove_exclusive_effect(idx: int) -> void:
	if idx >= 0 and idx < GConst.EXCLUSIVE_NUM:
		exclusive_effects[idx] = false
		exclusive_owners[idx] = -1


func check_exclusive_effect(idx: int) -> bool:
	if idx >= 0 and idx < GConst.EXCLUSIVE_NUM:
		return exclusive_effects[idx]
	return false


## 某张专属牌是谁放的（没挂或没记 → -1）。
## 【挑衅】用它锁定「被挑衅的人只能主动攻击哪个玩家」（多勇者时也锁死放牌者本人，见 base_v_attack）
func exclusive_owner(idx: int) -> int:
	if idx >= 0 and idx < GConst.EXCLUSIVE_NUM:
		return exclusive_owners[idx]
	return -1


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


## 移除自身 n 点能量（先扣水晶再扣宝石，与服务端消耗能量的顺序一致）。
## 供【冒险者天堂】提炼时「移除自身 X 能量」用。
func remove_energy(n: int) -> void:
	if n <= 0:
		return
	var 扣水晶: int = mini(n, crystal)
	set_crystal(crystal - 扣水晶)
	set_gem(gem - (n - 扣水晶))


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


## 攻击校验通用实现：面前有【挑衅】时只能打放牌者、目标不同队、持有该攻击牌
func base_v_attack(card_id: int, dst_id: int, players: Dictionary) -> int:
	# 对照服务端 PlayerEntity::v_attack 开头：攻击者面前有【挑衅】时，目标只能是「放挑衅的那个玩家」
	# （按放牌者判，不是按勇者角色号 —— 场上允许同角色重复，多勇者时也要锁死放牌者本人）
	if check_exclusive_effect(GConst.Exclusive.TiaoXin) \
			and dst_id != exclusive_owner(GConst.Exclusive.TiaoXin):
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


## 提炼校验（角色可覆写，如冒险家【冒险者天堂】把提炼出的星石分给至多 2 名队友时按队友空位算）
func v_extract(args: Array, team_gem: int, team_crystal: int, dst_ids: Array = []) -> int:
	if role != null:
		var rc: int = role.v_extract(args, team_gem, team_crystal, dst_ids)
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


## 这名玩家到服务端（房主）这一路的往返延迟（毫秒）：由服务端心跳测出后写进来，
## 跟着快照下发给所有人（观战者也看得到，见「玩家列表」的右侧一列）。
## 未被测出时是哨兵值 GConst.PING_未测 —— 不能拿 0 当未测：房主自己那一路是 0ms
var ping_ms: int = GConst.PING_未测


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
		"ping": ping_ms,
		"leader": 0,
	}
	var bas: Array = []
	for e: Dictionary in basic_effects:
		bas.append(int(e["card"]))
	d["basic_cards"] = bas
	var exs: Array = []
	var ex_from: Array = []
	for i: int in range(GConst.EXCLUSIVE_NUM):
		if exclusive_effects[i]:
			exs.append(i)
			# 与 ex_cards 一一对应：这张专属牌是谁放的（-1＝没记）
			ex_from.append(exclusive_owners[i])
	d["ex_cards"] = exs
	d["ex_from"] = ex_from
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
