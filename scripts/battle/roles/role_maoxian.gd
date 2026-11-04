extends BattleRole
## 冒险家（roleID 12）—— 移植自服务端 role/MaoXian.cpp
## 技能：欺诈（响应/攻击技能 1201：弃 2 张同系牌视为任意非暗系攻击，或弃 3 张同系牌视为暗系攻击）、
##       冒险者天堂（1202：提炼出的水晶和宝石全部交给一名目标队友；不占技能栏）、
##       偷天换日（必杀法术技能 1203，回合限定：转移对方 1 宝石 或 把我方水晶全部转宝石，额外 +1 攻击或法术行动）
## 被动：强运（每发动欺诈 +1 水晶）、地下法则（购买时改为战绩区 +2 宝石）

const QI_ZHA: int = 1201                     # 欺诈（攻击技能）
const MAO_XIAN_ZHE_TIAN_TANG: int = 1202     # 冒险者天堂（提炼时改给队友的询问号）
const TOU_TIAN_HUAN_RI: int = 1203           # 偷天换日（法术技能）

## 偷天换日的两种用法（arg_choices 的 args[0]）：转移对方 1 宝石 / 把我方水晶全部转宝石
const TOU_TIAN_TRANSFER: int = 0
const TOU_TIAN_CONVERT: int = 1

## 偷天换日 的回合限定标记（每回合只能发动一次）
var used_TouTianHuanRi: bool = false


func p_before_turn_begin(_ctx: Dictionary) -> int:
	used_TouTianHuanRi = false
	return SUCCESS


func available_skills() -> Array:
	var out: Array = []
	# 欺诈：两档同系牌——
	#   2 张：视为除暗系外的任意系主动攻击，虚牌系别由二级栏选项决定；
	#   3 张：视为暗系主动攻击。
	# 两档都放手牌可选，最多 3 张；每个选项用 need_card / card_max 收自己的张数。
	# 手里至少要有一对同系牌才放行；没有同系对时按钮仍摆出、置灰。
	out.append({"type": GConst.ActionType.AttackSkill, "id": QI_ZHA, "need_card": 2, "card_max": 3,
		"need_target": 1, "targets": enemy_ids(), "card_rule": "same",
		"arg_choices": _qi_zha_options(), "enabled": _has_same_element_pair()})
	# 偷天换日：先在二级技能栏里二选一（转移对方 1 宝石 / 我方水晶全部转宝石）；
	# 条件不满足（无能量 / 本回合已用 / 两种用法都不可行）时按钮仍摆出、置灰
	var 选项: Array = _tou_tian_options()
	out.append({"type": GConst.ActionType.MagicSkill, "id": TOU_TIAN_HUAN_RI, "need_card": 0, "need_target": 0,
		"arg_choices": 选项,
		"enabled": player.get_energy() > 0 and not used_TouTianHuanRi and _tou_tian_any_enabled()})
	return out


## 手里是否有至少一对同系牌（欺诈 2 张档的发动前提）
func _has_same_element_pair() -> bool:
	var 计数: Dictionary[int, int] = {}
	for cid: int in player.hand_cards:
		var c: GCard = Data.get_card(cid)
		if c == null:
			continue
		var e: int = c.element_enum()
		计数[e] = int(计数.get(e, 0)) + 1
		if int(计数[e]) >= 2:
			return true
	return false


## 手里是否有至少三张同系牌（欺诈 3 张暗系档的发动前提）
func _has_same_element_triple() -> bool:
	var 计数: Dictionary[int, int] = {}
	for cid: int in player.hand_cards:
		var c: GCard = Data.get_card(cid)
		if c == null:
			continue
		var e: int = c.element_enum()
		计数[e] = int(计数.get(e, 0)) + 1
		if int(计数[e]) >= 3:
			return true
	return false


## 两张牌是否同系（服务端校验用；对照 role_shenggong.gd 的 _same_element）
func _same_element(a: int, b: int) -> bool:
	var ca: GCard = Data.get_card(a)
	var cb: GCard = Data.get_card(b)
	if ca == null or cb == null:
		return false
	return ca.element_enum() == cb.element_enum()


# ============================================================
# 地下法则：购买
# ============================================================
func v_buy(args: Array) -> int:
	if player.hand_cards.size() + 3 > player.hand_cards_max:
		return GConst.GE_INVALID_ACTION
	if args.size() < 2:
		return GConst.GE_INVALID_ARGUMENT
	var gem: int = int(args[0])
	var crystal: int = int(args[1])
	if gem < 3 and crystal == 0:
		return GConst.GE_SUCCESS
	return GConst.GE_INVALID_ACTION


# ============================================================
# 欺诈（攻击技能）：弃 2 张同系牌视为非暗系攻击，或弃 3 张同系牌视为暗系攻击
# 虚牌（改成哪种系别的攻击）由客户端二级技能栏的选项随行动一起提交（args[0] = 虚牌 id）
# ============================================================
func v_attack_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != QI_ZHA:
		return GConst.GE_INVALID_ACTION
	var cards: Array = action.get("card_ids", [])
	if cards.size() != 2 and cards.size() != 3:
		return GConst.GE_INVALID_CARDID
	# 虚牌必须是可选的那几张：2 张档＝除暗系外的五系，3 张档＝暗系
	var args: Array = action.get("args", [])
	if args.is_empty():
		return GConst.GE_INVALID_ARGUMENT
	var virtual_card: int = int(args[0])
	if not _qi_zha_virtual_cards().has(virtual_card):
		return GConst.GE_INVALID_ACTION
	if virtual_card == QI_ZHA_DARK_CARD and cards.size() != 3:
		return GConst.GE_INVALID_CARDID
	if virtual_card != QI_ZHA_DARK_CARD and cards.size() != 2:
		return GConst.GE_INVALID_CARDID
	for c: Variant in cards:
		if not player.has_hand_card(int(c)):
			return GConst.GE_HANDCARD_NOT_FOUND
	# 所选牌必须全部同系（card_rule:"same" 只下发给客户端置灰，服务端仍要校验）
	for i: int in range(1, cards.size()):
		if not _same_element(int(cards[0]), int(cards[i])):
			return GConst.GE_INVALID_CARDID
	var dsts: Array = action.get("dst_ids", [])
	if dsts.is_empty():
		return GConst.GE_INVALID_ARGUMENT
	var dst: BattlePlayer = engine.p(int(dsts[0]))
	if dst == null:
		return GConst.GE_INVALID_PLAYERID
	if dst.color == player.color:
		return GConst.GE_INVALID_PLAYERID
	# 服务端 MaoXian::v_attack_skill 会调 v_attack：补上通用攻击限制
	# （面前有【挑衅】时目标只能是放牌者；目标角色可拒绝被攻击，如暗杀者潜行中）
	if player.check_exclusive_effect(GConst.Exclusive.TiaoXin) \
			and dst.id != player.exclusive_owner(GConst.Exclusive.TiaoXin):
		return GConst.GE_INVALID_PLAYERID
	if dst.v_attacked() != GConst.GE_SUCCESS:
		return GConst.GE_INVALID_PLAYERID
	return GConst.GE_SUCCESS


## 欺诈：虚牌由客户端二级技能栏的选项一并提交（args[0]），这里直接按它结算，不再中途问一次。
## 万一收到非法值（正常不该发生）：随机选一张可选虚牌。
func p_attack_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != QI_ZHA:
		return GConst.GE_INVALID_ACTION
	var args: Array = action.get("args", [])
	var 合法: Array[int] = _qi_zha_virtual_cards()
	var virtual_card: int = int(args[0]) if not args.is_empty() else -1
	if not 合法.has(virtual_card):
		# 3 张合法同系牌走暗系档；否则退回一张非暗虚牌
		virtual_card = QI_ZHA_DARK_CARD if action.get("card_ids", []).size() == 3 \
			else _qi_zha_default_virtual(_qi_zha_non_dark_cards())
	return _qi_zha(action, virtual_card)


func _qi_zha(action: Dictionary, virtual_card: int) -> int:
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	var dst_id: int = int(dsts[0])
	notice_skill(QI_ZHA, [dst_id])
	# 强运：+1 水晶
	player.set_crystal(player.crystal + 1)
	# 展示并弃掉所选牌
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": cards, "is_real": true,
	})
	# 虚牌视为一次主动攻击（非真实牌，不移动）
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Use, "src_id": player.id, "dst_id": dst_id,
		"card_ids": [virtual_card], "is_real": false, "virtual_no_fate": true,
	})
	engine._broadcast_game()
	var harm: Dictionary = {
		"src": player.id, "dst": dst_id, "point": 2, "cause": GConst.CAUSE_ATTACK,
		"type": GConst.HarmType.Attack, "card_id": virtual_card, "is_active": true,
		# 虚牌不是真实卡：不继承卡面的命格，阴阳转换等「同命格」效果不能匹配
		"virtual_no_fate": true,
	}
	engine.push(BattleEngine.SAttackCard.new(player.id, dst_id, virtual_card, harm))
	engine.take_from_hand(player.id, cards, true)
	engine.to_discard(cards, {"owner": player.id, "source": "hand"})
	return URGENT


# ============================================================
# 偷天换日（必杀法术技能 1203）：转移对方 1 宝石 / 我方水晶全部转宝石
# ============================================================
## 偷天换日的两种用法选项（二级技能栏里先选，选完按「确定」发动）：
## 两种用法始终都摆出来；当前做不了的项标 enabled=false，由界面置灰，而不是直接消失。
func _tou_tian_options() -> Array:
	return [
		{"text": GConst.按钮原文(TOU_TIAN_HUAN_RI, 0), "args": [TOU_TIAN_TRANSFER],
			"enabled": engine.team_gem[1 - player.color] >= 1},
		{"text": GConst.按钮原文(TOU_TIAN_HUAN_RI, 1), "args": [TOU_TIAN_CONVERT],
			"enabled": engine.team_crystal[player.color] >= 1},
	]


## 两种用法里至少有一种当前可做（决定技能本体按钮是否可点）
func _tou_tian_any_enabled() -> bool:
	return engine.team_gem[1 - player.color] >= 1 or engine.team_crystal[player.color] >= 1


## 本次偷天换日的用法：读二级技能栏送来的 args[0]；缺失（异常）时按可行性挑一种
func _tou_tian_mode(action: Dictionary) -> int:
	var args: Array = action.get("args", [])
	var mode: int = int(args[0]) if not args.is_empty() else -1
	if mode == TOU_TIAN_TRANSFER or mode == TOU_TIAN_CONVERT:
		return mode
	return TOU_TIAN_TRANSFER if engine.team_gem[1 - player.color] >= 1 else TOU_TIAN_CONVERT


func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if used_TouTianHuanRi:
		return GConst.GE_INVALID_ACTION
	if int(action.get("action_id", 0)) != TOU_TIAN_HUAN_RI:
		return GConst.GE_INVALID_ACTION
	if player.get_energy() <= 0:
		return GConst.GE_INVALID_ACTION
	match _tou_tian_mode(action):
		TOU_TIAN_TRANSFER:
			if engine.team_gem[1 - player.color] < 1:
				return GConst.GE_INVALID_ACTION
		TOU_TIAN_CONVERT:
			if engine.team_crystal[player.color] < 1:
				return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != TOU_TIAN_HUAN_RI:
		return GConst.GE_INVALID_ACTION
	if _tou_tian_mode(action) == TOU_TIAN_CONVERT:
		return _tou_tian_convert()
	return _tou_tian_transfer()


## 偷天换日·转移：消耗 1 能量，将对方战绩区 1 宝石转移到我方，额外 +1 攻击/法术行动
func _tou_tian_transfer() -> int:
	notice_skill(TOU_TIAN_HUAN_RI, [player.id])
	_consume_one_energy()
	var enemy: int = 1 - player.color
	engine.set_team_gem(enemy, engine.team_gem[enemy] - 1)
	engine.set_team_gem(player.color, engine.team_gem[player.color] + 1)
	player.add_action(GConst.ActionType.AttackMagic, TOU_TIAN_HUAN_RI, true, true)
	used_TouTianHuanRi = true
	engine._broadcast_game()
	return SUCCESS


## 偷天换日·转换：消耗 1 能量，我方水晶全部替换为宝石，额外 +1 攻击/法术行动
func _tou_tian_convert() -> int:
	notice_skill(TOU_TIAN_HUAN_RI, [player.id])
	_consume_one_energy()
	var crystal_have: int = engine.team_crystal[player.color]
	engine.set_team_crystal(player.color, 0)
	engine.set_team_gem(player.color, engine.team_gem[player.color] + crystal_have)
	player.add_action(GConst.ActionType.AttackMagic, TOU_TIAN_HUAN_RI, true, true)
	used_TouTianHuanRi = true
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 冒险者天堂：提炼出的水晶和宝石全部交给一名目标队友
# ============================================================
## 提炼校验覆写。头位不是 GConst.提炼天堂标记（即常规提炼的 [宝石, 水晶]）＝退回通用校验；否则是【冒险者天堂】：
##   args = [标记, 自己的宝石, 自己的水晶, 给队友的宝石, 给队友的水晶, 额外能量 X, 目标颗数]
##   当前版本没有额外提炼，自己的宝石/水晶恒为 0、X 恒为 0；
##   提炼出的总数 1~2 颗全部交给唯一一名目标队友（不能给自己，不能拆分）。
func v_extract(args: Array, team_gem: int, team_crystal: int, dst_ids: Array) -> int:
	if args.is_empty() or int(args[0]) != GConst.提炼天堂标记:
		return V_NOT_OVERRIDE
	if args.size() != 7 or dst_ids.size() != 1:
		return GConst.GE_INVALID_ARGUMENT
	var 自己宝石: int = int(args[1])
	var 自己水晶: int = int(args[2])
	var 队友宝石: int = int(args[3])
	var 队友水晶: int = int(args[4])
	var x: int = int(args[5])
	var 目标颗数: int = int(args[6])
	var 总数: int = 队友宝石 + 队友水晶
	if 自己宝石 != 0 or 自己水晶 != 0 or x != 0:
		return GConst.GE_INVALID_ACTION
	if 队友宝石 < 0 or 队友水晶 < 0 or 总数 < 1 or 总数 > 2:
		return GConst.GE_INVALID_ACTION
	if 目标颗数 != 总数:
		return GConst.GE_INVALID_ACTION
	var t: BattlePlayer = engine.p(int(dst_ids[0]))
	if t == null or t.color != player.color or t.id == player.id:
		return GConst.GE_INVALID_PLAYERID
	if 总数 > t.energy_max - t.get_energy():
		return GConst.GE_INVALID_ACTION
	if 队友宝石 > team_gem or 队友水晶 > team_crystal:
		return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


## 提炼改给队友后：广播【冒险者天堂】的发动通知（对照服务端 MaoXian::p_special_skill 的 noticeSkill）
func p_extract_to(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	notice_skill(MAO_XIAN_ZHE_TIAN_TANG, ctx.get("dst_ids", []))
	return SUCCESS


# ============================================================
# 工具
# ============================================================
## 欺诈虚牌：各系别对应的一张攻击牌（顺序照原客户端：风 / 水 / 火 / 地 / 雷）。
## 虚牌只借卡名 / 系别 / 攻击类型，不继承卡面的命格。
const QI_ZHA_CARDS: Array[int] = [66, 133, 87, 45, 110]
## 3 张同系档使用的暗系虚牌（暗灭）
const QI_ZHA_DARK_CARD: int = 39


## 欺诈可选的虚牌 id：非暗五系 + 暗系
func _qi_zha_virtual_cards() -> Array[int]:
	var out: Array[int] = []
	out.append_array(QI_ZHA_CARDS)
	out.append(QI_ZHA_DARK_CARD)
	return out


func _qi_zha_non_dark_cards() -> Array[int]:
	return QI_ZHA_CARDS


## 欺诈的虚牌选项（二级技能栏里先选，选完才让选牌 / 选目标）：
## 非暗五系走 2 张档；暗系走 3 张档。每项用 need_card / card_max 收自己的牌数。
func _qi_zha_options() -> Array:
	var 有对: bool = _has_same_element_pair()
	var 有暗: bool = _has_same_element_triple()
	var out: Array = []
	for cid: int in QI_ZHA_CARDS:
		var c: GCard = Data.get_card(cid)
		out.append({"text": GConst.按钮原文(QI_ZHA, 0) % c.card_name, "args": [cid],
			"element": c.element_enum(), "need_card": 2, "card_max": 2, "enabled": 有对})
	var 暗: GCard = Data.get_card(QI_ZHA_DARK_CARD)
	out.append({"text": GConst.按钮原文(QI_ZHA, 1) % 暗.card_name, "args": [QI_ZHA_DARK_CARD],
		"element": 暗.element_enum(), "need_card": 3, "card_max": 3, "enabled": 有暗})
	return out


## 欺诈弹窗超时（或收到非法值）的默认虚牌：随机选一张可选虚牌
func _qi_zha_default_virtual(合法: Array[int]) -> int:
	return 合法[randi_range(0, 合法.size() - 1)]


## 消耗 1 点个人能量（优先扣水晶，与服务端一致）
func _consume_one_energy() -> void:
	if player.crystal > 0:
		player.set_crystal(player.crystal - 1)
	else:
		player.set_gem(player.gem - 1)
