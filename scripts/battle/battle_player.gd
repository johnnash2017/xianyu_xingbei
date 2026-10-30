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
## 血色剑灵【血蔷薇庭院】是否在场上：这是独立状态，不是「横置形态」。
## 只影响【治疗】抵御与【血染蔷薇】的群伤；客户端在状态图标区显示对应图标。
var xue_qiang_wei: bool = false
## 圣弓专属技正反面：0=【圣煌辉光炮】、1=【圣煌余辉】、2=已移除。
## 客户端据此在状态图标区显示正面/背面图标；其他角色保持 0 但不显示（按角色号过滤）。
var sheng_huang_side: int = 0
## 本回合「下一次主动攻击只能攻击这名玩家」（0＝无限制）：回合级标记，由技能设置
## （如剑之子【剑残影】10804），下一次主动攻击打出时由引擎消费掉、新回合开始时清零。
## 服务端在 base_v_attack 里按它拒掉别的目标；客户端按快照里的 attack_lock 把其余敌人头像置灰。
var attack_lock_id: int = 0
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


## 从一列牌里认「这张」：先按实例号精确找（玩家点选 / 摸牌拿到的是实际那一份），
## 找不到再按牌面找第一张（角色脚本大多只传牌号；调试克隆出来的副本实例号与牌号不同）。
## 两张同牌面的副本对规则来说完全等价，按牌面删哪一张都一样。
func _找一张(列: Array[int], id: int) -> int:
	for i: int in range(列.size()):
		if 列[i] == id:
			return i
	var 面: int = GConst.牌号(id)
	for i2: int in range(列.size()):
		if GConst.牌号(列[i2]) == 面:
			return i2
	return -1


## 这一列里有没有这张牌（按实例号或牌面都算）
func _有这张(列: Array[int], id: int) -> bool:
	return _找一张(列, id) >= 0


## 从一列牌里删掉指定的一张，返回是否删到
func _删一张(列: Array[int], id: int) -> bool:
	var 位置: int = _找一张(列, id)
	if 位置 < 0:
		return false
	列.remove_at(位置)
	return true


## 从一列牌里取出指定的一张，返回它**实际的实例号**（找不到返回 -1，且什么都不删）。
## 「把这张牌交给别人 / 挪到另一个区域」必须带着返回的实例号走：直接 add 牌号会退化成
## 「删掉一张、再凭空补一张同牌面的新牌」，牌库里那张的实例号就会和它撞号。
func 取出实例(列: Array[int], id: int) -> int:
	var 位置: int = _找一张(列, id)
	if 位置 < 0:
		return -1
	var 实例: int = 列[位置]
	列.remove_at(位置)
	return 实例


## 取出一张手牌（含「盖牌视同手牌」形态下的盖牌），返回实际实例号；找不到返回 -1
func 取出一张手牌(id: int) -> int:
	var 实例: int = 取出实例(hand_cards, id)
	if 实例 >= 0:
		return 实例
	if role != null and role.盖牌可当手牌():
		return 取出实例(cover_cards, id)
	return -1


## 盖牌区里有没有这张（按实例号或牌面；替代直接 cover_cards.has 的写法）
func 有盖牌(id: int) -> bool:
	return _有这张(cover_cards, id)


## 盖牌区里这一张实际是哪一份（不改动，找不到返回 -1）。
## 给「先拿到实例号、再交给引擎 remove_cover 删除」这类场景用，避免删完之后拿牌号去补一张新的。
func 盖牌实例(id: int) -> int:
	var 位置: int = _找一张(cover_cards, id)
	if 位置 < 0:
		return -1
	return cover_cards[位置]


## 手牌里这一张实际是哪一份（不改动，找不到返回 -1）
func 手牌实例(id: int) -> int:
	var 位置: int = _找一张(hand_cards, id)
	if 位置 < 0:
		return -1
	return hand_cards[位置]


## 手牌里有没有这张（只看真实手牌，语义同 has_discard_card）
func 有手牌(id: int) -> bool:
	return _有这张(hand_cards, id)


func remove_hand_cards(cards: Array) -> void:
	for c: Variant in cards:
		var cid: int = int(c)
		# 打出一张「盖牌视同手牌」的牌（精灵射手【精灵祝福形态】下的【祝福】）时，
		# 手牌里没有就从盖牌区删。弃牌路径不会走到这里 —— 弃牌一律只认真实手牌（见 has_discard_card）
		if _删一张(hand_cards, cid):
			continue
		if role != null and role.盖牌可当手牌():
			_删一张(cover_cards, cid)


## 手牌里有没有这张牌（对照服务端 PlayerEntity::checkOneHandCard）：
## 盖牌能当手牌用的形态下，盖牌同时算手牌（如精灵射手的【祝福】）——
## 只用于「打出 / 应战」这类把牌用出去的场合
func has_hand_card(cid: int) -> bool:
	if _有这张(hand_cards, cid):
		return true
	return role != null and role.盖牌可当手牌() and _有这张(cover_cards, cid)


## 这张牌能不能作为「弃手牌」的对象：只看真实手牌。
## 【祝福】这类「盖牌视同手牌」只用于出牌 / 应战，任何弃手牌效果（爆牌、技能代价、
## 他人令弃）都不能弃盖牌，也不把盖牌列出来给玩家选
func has_discard_card(cid: int) -> bool:
	return _有这张(hand_cards, cid)


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
		_删一张(cover_cards, int(c))


func cover_count() -> int:
	return cover_cards.size()


## 盖牌区还剩几个空位（上限来自角色表「指示物」列的槽 2）
func cover_space() -> int:
	return maxi(cover_cards_max - cover_cards.size(), 0)


## 现在还能不能再放 n 张盖牌：角色没配盖牌槽（上限 0）时永远不能放，已满时也不能放。
## 只做通用判断；真正把牌放进盖牌区走引擎 add_cover（会广播快照 / 触发 p_cover_change）。
func can_add_cover_cards(n: int = 1) -> bool:
	return cover_cards_max > 0 and cover_cards.size() + n <= cover_cards_max


# ============================================================
# 指示物（F3）
# 槽位名称 / 上限来自角色表「指示物」列（Data.role_token_def）；槽 0 / 1 是计数型指示物，
# 槽 2 是盖牌（实际牌在 cover_cards，不在这里）。角色脚本不要自己拼 tokens 字典或
# 自己判上限，统一用下面这几个方法，数值始终与角色表一致。
# ============================================================
## 某槽位的指示物定义 {name, max, num}；该角色没配这个槽位返回空字典。
## 槽 2 不在这里（盖牌看 cover_cards / cover_cards_max）。
func token_def(slot: int) -> Dictionary:
	if slot < 0 or slot >= tokens.size():
		return {}
	var 槽: Variant = tokens[slot]
	return 槽 if 槽 is Dictionary else {}


func token_name(slot: int) -> String:
	return str(token_def(slot).get("name", ""))


func token_num(slot: int) -> int:
	return int(token_def(slot).get("num", 0))


func token_max(slot: int) -> int:
	return int(token_def(slot).get("max", 0))


## 加指示物并按角色表上限截断，返回实际增加的数量（没配槽位 / 已满时返回 0）。
## 如 46 灵涌（上限 4）：3 → add_token(0, 3) 只加 1；93 元子（上限 3）同理。
func add_token(slot: int, n: int = 1) -> int:
	if n <= 0:
		return 0
	var 定义: Dictionary = token_def(slot)
	if 定义.is_empty():
		return 0
	var 当前: int = int(定义.get("num", 0))
	var 上限: int = int(定义.get("max", 0))
	var 实际: int = clampi(上限 - 当前, 0, n)
	if 实际 > 0:
		定义["num"] = 当前 + 实际
	return 实际


## 消耗指示物：不够 n 个时不改动并返回 false（调用方据此判「能不能发动」）；
## n = 0 视为成功（无操作）。如 93 元子重塑花 2、4605 清空灵涌见 clear_token。
func remove_token(slot: int, n: int = 1) -> bool:
	if n < 0:
		return false
	if n == 0:
		return true
	var 定义: Dictionary = token_def(slot)
	if 定义.is_empty():
		return false
	var 当前: int = int(定义.get("num", 0))
	if 当前 < n:
		return false
	定义["num"] = 当前 - n
	return true


## 清空某槽位指示物（如 46 怒潮荒涛移除全部灵涌），返回清掉的数量。
func clear_token(slot: int) -> int:
	var 定义: Dictionary = token_def(slot)
	if 定义.is_empty():
		return 0
	var 当前: int = int(定义.get("num", 0))
	定义["num"] = 0
	return 当前


## 直接设成 n（按 0..角色表上限夹取），返回设完的值；用于「设为上限 / 归零」这类明确写法。
func set_token_num(slot: int, n: int) -> int:
	var 定义: Dictionary = token_def(slot)
	if 定义.is_empty():
		return 0
	var 值: int = clampi(n, 0, int(定义.get("max", 0)))
	定义["num"] = 值
	return 值


## 按角色表「指示物」列初始化槽 0 / 1 的计数指示物与槽 2 的盖牌上限。
## 角色脚本的 BattleRole.setup() 会按同一份数据初始化；这里给「还没写角色脚本的白板角色」兜底，
## 让 38 子弹 / 46 灵涌 / 93 元子这类纯数据指示物也能正确显示 / 计数。
## 名称、上限只认设计表；计数一律从 0 开始（38 开局 6 张子弹属于角色技能效果，不在这里）。
func 按表初始化指示物() -> void:
	for 槽: int in [0, 1]:
		var 定义: Dictionary = Data.role_token_def(role_id, 槽)
		if 定义.is_empty():
			tokens[槽] = null
			continue
		tokens[槽] = {"name": str(定义["name"]), "max": int(定义["max"]), "num": 0}
	var 盖牌: Dictionary = Data.role_token_def(role_id, 2)
	cover_cards_max = int(盖牌.get("max", 0))


# ============================================================
# 基础效果
# ============================================================
## 只记录「牌 + 施放者」。基础效果本身不是额外行动，不占额外行动的获取序号；
## 它最终授予的那份额外行动，等真正被确认（进入队列）时才取号，见
## BattleEngine._确认基础效果额外行动。
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
# 回合级标记：下一次主动攻击只能打谁
# ============================================================
## 设置 / 清除「本回合下一次主动攻击只能攻击这名玩家」（0＝无限制）。
## 由授予限制的技能写（如剑之子【剑残影】10804），引擎在下一次主动攻击打出时消费、
## 回合开始时清零；服务端 base_v_attack 与客户端 _玩家可选 读同一份状态。
func set_attack_lock(pid: int) -> void:
	attack_lock_id = maxi(pid, 0)


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
## 额外行动获取序号：切换当前额外行动时按它恢复原队列顺序，避免用掉一份后整体重排
var _额外行动序号: int = 0
## 额外行动唯一 ID：同一技能可同时挂多份行动，选项/切换/进入按 ID 认人（见 额外行动新ID）
var _额外行动uid: int = 0
## 历史字段：旧规则里「取消行动结束响应」会置 true 跳过本回合后续额外攻击；
## 新规则取消只取消响应、不再清空 / 跳过额外行动，因此这里恒为 false（角色里的判断保留兼容）。
var 跳过额外攻击行动: bool = false
## 响应里已选好、等待进入的快捷额外攻击（按玩家保存，不再用引擎全局字段）
var 快捷额外行动: int = -1
var 快捷额外行动卡: int = 0
var 快捷额外行动目标: int = 0


## 取下一个额外行动序号（切换/补授予时保持稳定顺序）
func 额外行动新序号() -> int:
	var 最大: int = _额外行动序号
	for a: Dictionary in additional_actions:
		最大 = maxi(最大, int(a.get("order", 0)))
	_额外行动序号 = 最大 + 1
	return _额外行动序号


## direct=true 的额外行动不需要询问、也不用玩家再点一次技能按钮：引擎会直接进入它的额外行动阶段
## （该阶段允许「放弃行动」，想跳过在那里放弃即可）。
## 判定标准：这份额外行动「被选中」时不额外消耗代价（p_additional_action 无扣费/无移除资源）。
## 代价在选中时才结算的（如剑圣【剑影】扣能量、剑帝【不屈意志】扣能量）仍要询问，保留玩家「不付代价退出」的权利。
## skip_notice=true：授予这份额外行动的技能已经自己发过 Skill 通告（如式神降临、充盈、辉耀），
## 引擎进入额外行动时不要再补发一次，否则同一技能会多一条「发动…」日志/头像播报。
## 获取序号在这里取：先加进队列的行动序号永远更小，响应里的快捷按钮 / 额外行动阶段的技能栏
## 都按它排列（先获得的在前，不区分来源是角色技能还是基础效果）。
##
## spec＝这份行动自己的规格（授予时由技能算好，引擎只照单执行，不再按 cause 回问角色）：
##   cards           出牌白名单；空＝不限；[GConst.手牌白名单_全禁]（-1）＝一张都不给
##   targets         目标白名单；空＝不限；[GConst.目标白名单_无]（-1）＝一个都没有
##   element         行动限定的牌系：**也是限制**——cards 为空时，只看该系攻击牌
##                   （引擎按卡库现算，不看授予那一刻的手牌快照，见 BattleEngine.额外行动出牌白名单）；
##                   同时用于界面文案 / 按钮配色
##   card_fate       行动限定的命格（GConst.FatePattern）：同样是限制，cards 为空时只看该命格攻击牌
##   switchable      额外攻击阶段能否切走（默认 true）
##   in_end_response 是否作为「行动结束响应」的选项（默认 false）
func add_action(allow_action: int, cause: int, direct: bool = false,
		skip_notice: bool = false, spec: Dictionary = {}) -> void:
	var 数据: Dictionary = {
		"allow_action": allow_action, "cause": cause, "direct": direct,
		"skip_notice": skip_notice, "order": 额外行动新序号(),
		# 唯一 ID：同一个技能可以同时挂着好几份行动（如连续两张【疾风技】），
		# 界面上的选项、切换、进入都按它认人，不能按 cause 认（会同时点亮/进错份）。
		"uid": 额外行动新ID(),
		"cards": [],
		"targets": [],
		"element": 0,
		"card_fate": 0,
		"switchable": true,
		"in_end_response": false,
	}
	# spec 里的键一律照抄（数组复制一份）：技能写了什么规格就存什么，
	# 引擎不认识的键也不会被悄悄丢掉（以前这里是白名单赋值，新增 spec 键忘了同步就会静默失效）。
	for 键: Variant in spec:
		if spec[键] is Array:
			数据[键] = (spec[键] as Array).duplicate()
		else:
			数据[键] = spec[键]
	additional_actions.append(数据)
	额外行动排序()


## 额外行动的唯一 ID（只增不减，不随队列增删/换队变化）
func 额外行动新ID() -> int:
	_额外行动uid += 1
	return _额外行动uid


## 按唯一 ID 找这份行动（正在行动的那份也认）。选项/切换/进入都走这里认人。
func 额外行动按ID(uid: int) -> Dictionary:
	if uid <= 0:
		return {}
	if engine != null and not engine.当前额外行动数据.is_empty() \
			and int(engine.当前额外行动数据.get("uid", 0)) == uid:
		return engine.当前额外行动数据
	for a: Dictionary in additional_actions:
		if int(a.get("uid", 0)) == uid:
			return a
	return {}


## 按唯一 ID 找它在队列里的下标（不在队列＝-1）
func 额外行动下标按ID(uid: int) -> int:
	for i: int in range(additional_actions.size()):
		if int(additional_actions[i].get("uid", 0)) == uid:
			return i
	return -1


## 队列按获取序号排好（数组顺序＝获取顺序）。**所有界面共用这一个顺序**：
## 行动结束响应里的快捷按钮、额外行动阶段的技能栏、额外行动选择框都直接照这个顺序摆，
## 谁都不再自己排序（以前客户端按 extra_order 重排，那个字段没进协议、永远是 0，
## 于是技能栏退回按技能号排，和响应对不上）。
func 额外行动排序() -> void:
	additional_actions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("order", 0)) < int(b.get("order", 0)))


## 队列里某来源的那份额外行动（没有＝空字典；返回的是那份数据本身，可直接改规格）。
## 正在行动的那份已经不在队列里，但引擎用同一份数据推进（见 BattleEngine._进入），
## 所以这里也认「当前正在行动的这份」。
func 额外行动数据(cause: int) -> Dictionary:
	if engine != null and not engine.当前额外行动数据.is_empty() \
			and int(engine.当前额外行动数据.get("cause", 0)) == cause:
		return engine.当前额外行动数据
	for a: Dictionary in additional_actions:
		if int(a.get("cause", 0)) == cause:
			return a
	return {}


## 只按「队列」找某来源的额外行动（不看正在行动的那一份）。
## 行动结束响应里确认 / 扣费 / 标 direct 必须落在**队列里这一份**：
## 上一个同来源的行动用完后 引擎.当前额外行动数据 还留着那份数据，
## 用 额外行动数据() 会被它顶掉，新入队的这份永远标不上 direct，
## 响应结束后又被当成选项问一次（血色剑灵【赤色一闪】连续两次踩过）。
## 未确认=true：只找还没标 direct 的那份 —— 同一来源可能已经有一份确认过、正排着等进入的
## （迅捷赐福的行动先确认、赤色一闪后确认，前一份还没用掉时下一轮又入队一份新的），
## 按 cause 取第一份会标到旧的那份上，新的一份永远确认不了 → 响应反复问。
func 额外行动队列数据(cause: int, 未确认: bool = false) -> Dictionary:
	for a: Dictionary in additional_actions:
		if int(a.get("cause", 0)) != cause:
			continue
		if 未确认 and bool(a.get("direct", false)):
			continue
		return a
	return {}


## 技能自己撤单：这份额外行动现在不可用了（如同回合已用过、赐福牌没了）
func 撤回额外行动(cause: int) -> void:
	for i: int in range(additional_actions.size() - 1, -1, -1):
		if int(additional_actions[i].get("cause", 0)) == cause:
			additional_actions.remove_at(i)


## 改写某来源行动的规格：进入行动时按「此刻」的状态重算白名单 / 目标（如 10704 的手牌数比较）。
## 只改 spec 里给出的键，其余保持不变；数组一律复制，别把调用方的临时数组塞进行动里。
func 改写额外行动(cause: int, spec: Dictionary) -> void:
	var 数据: Dictionary = 额外行动数据(cause)
	if 数据.is_empty():
		return
	for 键: Variant in spec:
		if spec[键] is Array:
			数据[键] = (spec[键] as Array).duplicate()
		else:
			数据[键] = spec[键]


func contains_action() -> bool:
	return not additional_actions.is_empty()


func clear_additional_action() -> void:
	additional_actions.clear()


# ============================================================
# 每回合行动计数（F2）
# 攻击 / 法术 / 特殊各自累加；「额外行动」不单独占一个种类，而是计入它实际使用的种类
# （额外攻击仍算攻击行动），另用 extra_action_count 记其中有多少次是额外行动 ——
# 所以四项计数分开看，总次数不重复计。
# 引擎在行动宣告成立时记一次（record_action），回合开始（SCheckTurnStart）清零；
# 被取消的技能行动由引擎撤销（undo_action）。
# ============================================================
var attack_action_count: int = 0
var magic_action_count: int = 0
var special_action_count: int = 0
var extra_action_count: int = 0


## 本回合已行动的总次数（额外行动也计一次，不会因为「额外」重复计）
func action_count() -> int:
	return attack_action_count + magic_action_count + special_action_count


## 某一类行动本回合的次数：kind = "attack" / "magic" / "special"
## （额外行动按其实际种类计，额外次数另见 extra_action_count）
func action_count_of(kind: String) -> int:
	match kind:
		"attack": return attack_action_count
		"magic": return magic_action_count
		"special": return special_action_count
	return 0


## 记一次行动，返回记完后的本回合总次数（引擎在行动宣告成立时调用）
func record_action(kind: String, is_extra: bool) -> int:
	match kind:
		"attack": attack_action_count += 1
		"magic": magic_action_count += 1
		"special": special_action_count += 1
	if is_extra:
		extra_action_count += 1
	return action_count()


## 撤销一次行动计数（技能行动被取消时由引擎调用）：那次行动没真正发生，不能留在计数里
func undo_action(kind: String, is_extra: bool) -> void:
	match kind:
		"attack": attack_action_count = maxi(attack_action_count - 1, 0)
		"magic": magic_action_count = maxi(magic_action_count - 1, 0)
		"special": special_action_count = maxi(special_action_count - 1, 0)
	if is_extra:
		extra_action_count = maxi(extra_action_count - 1, 0)


## 回合开始清零（引擎在 SCheckTurnStart 调用）
func reset_action_counts() -> void:
	attack_action_count = 0
	magic_action_count = 0
	special_action_count = 0
	extra_action_count = 0


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


## 攻击校验通用实现：面前有【挑衅】时只能打放牌者、本回合有「下次主动攻击只能打谁」的标记时
## 只能打标记的人、目标不同队、持有该攻击牌
func base_v_attack(card_id: int, dst_id: int, players: Dictionary) -> int:
	# 对照服务端 PlayerEntity::v_attack 开头：攻击者面前有【挑衅】时，目标只能是「放挑衅的那个玩家」
	# （按放牌者判，不是按勇者角色号 —— 场上允许同角色重复，多勇者时也要锁死放牌者本人）
	if check_exclusive_effect(GConst.Exclusive.TiaoXin) \
			and dst_id != exclusive_owner(GConst.Exclusive.TiaoXin):
		return GConst.GE_INVALID_PLAYERID
	# 回合级标记（剑之子【剑残影】10804）：本回合的下次主动攻击只能打标记的那名玩家。
	# 它是玩家身上的标记，不是这份行动 / 这张牌的规格 —— 别的主动攻击同样受它限制。
	if attack_lock_id > 0 and dst_id != attack_lock_id:
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
	if not GCard.可普通应战(card, atk):
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


## 多牌响应魔弹（10603）：角色不覆写/不合法一律拒绝；返回 V_NOT_OVERRIDE 也按拒绝处理。
func v_remissile_multi(cards: Array) -> int:
	if role != null:
		var rc: int = role.v_remissile_multi(cards)
		if rc != BattleRole.V_NOT_OVERRIDE:
			return rc
	return GConst.GE_INVALID_CARDID


func missile_relay_card_max() -> int:
	if role != null:
		return role.missile_relay_card_max()
	return 1


func remissile_multi_skill() -> int:
	if role != null:
		return role.remissile_multi_skill()
	return 0


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


## 目标资格校验（F4 / 4601）：自己能不能被放上这张基础效果；由自己的角色判定，默认可以。
## 引擎在 add_basic_effect、【圣盾】/【虚弱】/【中毒】的出牌校验与技能行动的基础效果放置校验里
## 统一走这里，所以角色只需要覆写 BattleRole.v_basic_effect_target，不用改各条施放路径。
func v_basic_effect_target(card_id: int) -> int:
	if role != null:
		return role.v_basic_effect_target(self, card_id)
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
		# 盖牌上限（角色表「指示物」列槽 2 的上限）：客户端「查看盖牌」时按它摆出空槽，
		# 让玩家看见自己最多能放几张；0 表示这个角色根本没有盖牌区
		"max_covered": cover_cards_max,
		"is_knelt": tap,
		# 血色剑灵【血蔷薇庭院】：独立状态，客户端画状态图标（不是形态名）
		"xue_qiang_wei": xue_qiang_wei,
		# 圣弓专属技正反面（0/1/2）：客户端画【圣煌辉光炮】/【圣煌余辉】状态图标
		"sheng_huang_side": sheng_huang_side,
		"max_hand": hand_cards_max,
		"nickname": player_name,
		"ready": ready,
		"online": online,
		"ping": ping_ms,
		"leader": 0,
		# 梦想剑 4503 当前档位（0=未启用 / 1 / 2 / 3）：客户端角色说明据此把梦想剑标绿
		"dream_tier": role.dream_tier() if role != null else 0,
		# 本回合「下一次主动攻击只能攻击这名玩家」（0＝无限制）：客户端据此把其余敌方头像置灰
		"attack_lock": attack_lock_id,
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
