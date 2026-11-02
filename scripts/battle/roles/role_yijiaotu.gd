extends BattleRole
## 异教徒（95）：异端邪说 / 审判 / 献祭 / 末日预言 / 放逐 / 贪婪
##
## 【末日预言】＝场卡（F1）：id = "末日预言"，owner = 自己，counter = 【预言】张数（上限 6），
## pile = 隐藏的【预言】牌（实例号）。翻面之后 id 变成 "天雷劫火" / "地裂波涛"（state 记 1/2）。
##
## 口径：
## 1. 【异端邪说】开局 +1 水晶；【末日预言】在场时手牌上限 -1（每次自己回合开始重算）。
## 2. 【末日预言】的「因承受伤害摸牌时第 1 张改从【预言】处获得」用 F8 同步钩子
##    伤害摸牌替换(pid)：任意角色因伤害摸牌都生效；从预言堆顶取 1 张、张数 -1。
## 3. 翻面：预言堆**取空的那一次结算完**，问玩家选【天雷劫火】/【地裂波涛】，
##    移除【末日预言】、换一张同名场卡入场，然后立刻结算它的「展示时」效果（见 _翻面）。
## 4. 【审判】逐名队友问「弃 1 张牌【展示】」，然后各自摸 1 张【强制】，再由你选 1 张弃牌
##    交给目标对手；【末日预言】在场时其余弃牌洗混放到预言堆顶。
## 5. 【放逐】摸 6~8 张后，把手牌 6 张面朝下洗混作为新预言堆，所以手牌最终不多，
##    不需要额外处理手牌上限。额外行动二选一（攻击 / 法术）。

const YI_DUAN_XIE_SHUO: int = 9501
const SHEN_PAN: int = 9502
const XIAN_JI: int = 9503
const MO_RI_YU_YAN: int = 9504
const FANG_ZHU: int = 9505
const TAN_LAN: int = 9506

const 末日预言名: String = "末日预言"
const 天雷劫火名: String = "天雷劫火"
const 地裂波涛名: String = "地裂波涛"
const 预言上限: int = 6

## 本回合是否对对手造成过伤害（【审判】的发动条件）
var _本回合造成伤害: bool = false
## 审判进度
var _审判步: int = 0
var _审判下标: int = 0
var _审判弃牌: Array[int] = []
var _审判对手: int = -1
## 翻面 / 展示时的进度
var _翻面步: int = 0
var _展示系: int = 0
var _展示X: int = 0
var _展示对手: int = -1


func setup(p: BattlePlayer, e: BattleEngine) -> void:
	super.setup(p, e)
	# 【异端邪说】：游戏初始时你 +1【水晶】
	player.set_crystal(player.crystal + 1)


# ============================================================
# 技能栏
# ============================================================
func available_skills() -> Array:
	var 有末日: bool = engine.有场卡(末日预言名)
	var 手牌: Array[int] = player.hand_cards.duplicate()
	return [
		{
			"type": GConst.ActionType.MagicSkill,
			"id": XIAN_JI,
			"enabled": 有末日 and engine.取场卡(末日预言名).get("pile", []).size() > 0,
		},
		{
			"type": GConst.ActionType.MagicSkill,
			"id": FANG_ZHU,
			"enabled": player.get_energy() >= 1,
		},
	]


func is_free_skill(skill_id: int) -> bool:
	return skill_id == XIAN_JI


func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	match int(action.get("action_id", 0)):
		XIAN_JI:
			if not engine.有场卡(末日预言名):
				return GConst.GE_INVALID_ACTION
			if (engine.取场卡(末日预言名).get("pile", []) as Array).is_empty():
				return GConst.GE_INVALID_ACTION
			return GConst.GE_SUCCESS
		FANG_ZHU:
			if player.get_energy() < 1:
				return GConst.GE_INVALID_ACTION
			return GConst.GE_SUCCESS
	return GConst.GE_INVALID_ACTION


func p_magic_skill(action: Dictionary) -> int:
	match int(action.get("action_id", 0)):
		XIAN_JI:
			return _p_献祭()
		FANG_ZHU:
			return _p_放逐()
	return EMPTY_HANDLE


# ============================================================
# 9501 异端邪说
# ============================================================
func p_before_turn_begin(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	_本回合造成伤害 = false
	_重算手牌上限()
	# 【灾殃止息】：回合开始时若存在【天雷劫火】/【地裂波涛】→ 移除
	if engine.有场卡(天雷劫火名):
		engine.移除场卡(天雷劫火名)
	if engine.有场卡(地裂波涛名):
		engine.移除场卡(地裂波涛名)
	return SUCCESS


func _重算手牌上限() -> void:
	player.hand_cards_max = GConst.HAND_CARDS_MAX - (1 if engine.有场卡(末日预言名) else 0)


## 本回合对对手造成过伤害（【审判】条件）
func p_harm_end(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) == player.id:
		var dst: BattlePlayer = engine.p(int(ctx.get("dst", -1)))
		if dst != null and dst.color != player.color:
			_本回合造成伤害 = true
	return SUCCESS


# ============================================================
# 9504 末日预言：F8 同步钩子 —— 因承受伤害摸牌时第 1 张从预言堆拿
# ============================================================
func 伤害摸牌替换(_pid: int) -> int:
	if not engine.有场卡(末日预言名):
		return -1
	var 表: Dictionary = engine.取场卡(末日预言名)
	var 堆: Array = 表.get("pile", [])
	if 堆.is_empty():
		return -1
	var 牌: int = int(堆.pop_back())
	表["counter"] = 堆.size()
	# 最后 1 张被拿走的这一次结算完就要翻面：压一个钩子，等这次伤害摸牌流程跑完再问
	if 堆.is_empty():
		engine.push(BattleEngine.SHook.new("p_yi_jiao_tu_ask", {"player": player.id, "翻面": true}, []))
	return 牌


# ============================================================
# 9502 审判：自己的回合结束时
# ============================================================
func p_turn_end(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	if not _本回合造成伤害:
		return SUCCESS
	if _审判步 != 0:
		return SUCCESS
	_审判步 = 1
	if not engine.has_reply():
		询问(player.id, SHEN_PAN, 0, 0, GConst.CardSource.Hand, [], 0, "", [], true,
			0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0,
			"是否发动【审判】：我方所有角色各弃 1 张牌【展示】、各摸 1 张牌，然后把其中 1 张弃牌交给目标对手？")
		return WAIT
	if not take_skill_reply():
		_审判步 = 0
		return SUCCESS
	notice_skill(SHEN_PAN, [])
	_审判弃牌 = []
	_审判下标 = 0
	_审判步 = 2
	engine.push(BattleEngine.SHook.new("p_yi_jiao_tu_ask", {"player": player.id}, []))
	return URGENT


# ============================================================
# 9503 献祭：展示预言堆顶 1 张
# ============================================================
func _p_献祭() -> int:
	var 表: Dictionary = engine.取场卡(末日预言名)
	var 堆: Array = 表.get("pile", [])
	if 堆.is_empty():
		return GConst.GE_INVALID_ACTION
	_献祭牌 = int(堆.back())
	_献祭步 = 1
	engine.push(BattleEngine.SHook.new("p_yi_jiao_tu_ask", {"player": player.id}, []))
	return URGENT

var _献祭步: int = 0
var _献祭牌: int = -1


# ============================================================
# 9505 放逐：摸 6~8 → 移除旧预言 → 入场 → 6 张手牌作预言 → 额外行动
# ============================================================
func _p_放逐() -> int:
	if player.get_energy() < 1:
		return GConst.GE_INVALID_ACTION
	player.remove_energy(1)
	notice_skill(FANG_ZHU, [player.id])
	_放逐步 = 1
	engine.push(BattleEngine.SHook.new("p_yi_jiao_tu_ask", {"player": player.id}, []))
	return URGENT

var _放逐步: int = 0


# ============================================================
# 9504 / 9506：翻面成【天雷劫火】/【地裂波涛】并结算「展示时」效果
# ============================================================
func p_yi_jiao_tu_ask(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	# 翻面：选变成哪一张
	if _翻面步 == 1:
		_翻面步 = 2
		if not engine.has_reply():
			询问(player.id, MO_RI_YU_YAN, 0, 0, GConst.CardSource.Hand,
				[1, 2], 0, "", [], false,
				0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0,
				"【末日预言】的【预言】已空：翻面为【天雷劫火】或【地裂波涛】（1=天雷劫火 / 2=地裂波涛）")
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		var args: Array = r.get("args", [])
		var 选: int = int(args[0]) if not args.is_empty() else 0
		var 名: String = 地裂波涛名 if 选 == 2 else 天雷劫火名
		engine.移除场卡(末日预言名)
		engine.加场卡({"id": 名, "owner": player.id, "attached": -1,
			"counter": 0, "counter_max": 0, "state": 1})
		notice_skill(MO_RI_YU_YAN, [player.id])
		_在展示 = 名
		_展示步 = 1
		engine.push(BattleEngine.SHook.new("p_yi_jiao_tu_ask", {"player": player.id}, []))
		return URGENT
	# 展示时：先选系别（天雷劫火=雷/火；地裂波涛=地/水）
	if _展示步 == 1:
		_展示步 = 2
		var 系表: Array[int] = _展示系别()
		if not engine.has_reply():
			询问(player.id, MO_RI_YU_YAN, 0, 0, GConst.CardSource.Hand, 系表, 0, "", [], false,
				0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0,
				"【%s】：选择 1 种系别发动（弃 X 张该系牌摸 X 张，然后对目标对手造成 X+1 点法术伤害）"
				% _在展示)
			return WAIT
		var r2: Dictionary = take_skill_reply_full()
		var args2: Array = r2.get("args", [])
		_展示系 = int(args2[0]) if not args2.is_empty() else int(系表[0])
		_展示步 = 3
		engine.push(BattleEngine.SHook.new("p_yi_jiao_tu_ask", {"player": player.id}, []))
		return URGENT
	# 展示时：选 X（弃几张该系牌，最多 4，且不能超过手里该系牌数）
	if _展示步 == 3:
		var 同系: Array[int] = hand_ids_where(
			func(_cid: int, c: GCard) -> bool: return c.element_enum() == _展示系)
		_展示X = mini(4, 同系.size())
		_展示步 = 4
		if _展示X <= 0:
			_展示步 = 5
			engine.push(BattleEngine.SHook.new("p_yi_jiao_tu_ask", {"player": player.id}, []))
			return URGENT
		if not engine.has_reply():
			询问(player.id, MO_RI_YU_YAN, _展示X, 0, GConst.CardSource.Hand, [], _展示X, "", [], false,
				0, player.id, [], _展示X, {}, 0, 0, false, [], true, -1, 0,
				"【%s】：弃最多 %d 张该系牌【展示】" % [_在展示, _展示X])
			return WAIT
		var r3: Dictionary = take_skill_reply_full()
		var cards: Array = r3.get("card_ids", [])
		var 弃: Array = []
		for c: Variant in cards:
			if 弃.size() < _展示X and player.有手牌(int(c)):
				弃.append(int(c))
		if not 弃.is_empty():
			engine.broadcast(GConst.Msg.Card, {
				"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
				"card_ids": 弃, "is_real": true,
			})
			engine.take_from_hand(player.id, 弃, false)
			engine.to_discard(弃, {"owner": player.id, "source": "hand", "cause": MO_RI_YU_YAN})
			engine._log_discard(player.id, 弃, false)
		_展示X = 弃.size()
		_展示步 = 5
		engine.push(BattleEngine.SHook.new("p_yi_jiao_tu_ask", {"player": player.id}, []))
		return URGENT
	# 展示时：选目标对手 → 摸 X 张 + 造成 X+1 点法术伤害
	if _展示步 == 5:
		_展示步 = 6
		engine.push_draw(player.id, _展示X, MO_RI_YU_YAN)
		if not engine.has_reply():
			询问(player.id, MO_RI_YU_YAN, 0, 1, GConst.CardSource.Hand, [], 0, "", [], false,
				0, -1, enemy_ids(), -1, {}, 0, 0, false, [], true, -1, 0,
				"【%s】：指定 1 名目标对手（弃牌与摸牌后结算伤害）" % _在展示)
			return WAIT
		var r5: Dictionary = take_skill_reply_full()
		var ds: Array = r5.get("dst_ids", [])
		_展示步 = 0
		if ds.size() == 1:
			engine.push_harm({
				"src": player.id, "dst": int(ds[0]), "point": _展示X + 1,
				"cause": MO_RI_YU_YAN, "type": GConst.HarmType.Magic,
			})
			return URGENT
		return SUCCESS
	# 审判：逐名队友弃 1 张牌【展示】
	if _审判步 == 2:
		var 队友: Array[int] = _我方角色()
		if _审判下标 >= 队友.size():
			# 各自摸 1 张【强制】
			for pid: int in 队友:
				engine.强制摸牌(pid, 1, SHEN_PAN)
			_审判步 = 3
			engine.push(BattleEngine.SHook.new("p_yi_jiao_tu_ask", {"player": player.id}, []))
			return URGENT
		var pid2: int = int(队友[_审判下标])
		var pp: BattlePlayer = engine.p(pid2)
		if pp == null or pp.hand_cards.is_empty():
			_审判下标 += 1
			engine.push(BattleEngine.SHook.new("p_yi_jiao_tu_ask", {"player": player.id}, []))
			return URGENT
		if not engine.has_reply():
			询问(pid2, SHEN_PAN, 1, 0, GConst.CardSource.Hand, [], 1, "", [], false,
				0, pid2, [], 1, {}, 0, 0, false, [], true, -1, 0,
				"【审判】：弃 1 张牌【展示】")
			return WAIT
		var r6: Dictionary = take_skill_reply_full()
		var cards6: Array = r6.get("card_ids", [])
		if not cards6.is_empty() and pp.有手牌(int(cards6[0])):
			var cid: int = int(cards6[0])
			engine.broadcast(GConst.Msg.Card, {
				"type": GConst.CardMsgType.Show, "src_id": pid2, "dst_id": pid2,
				"card_ids": [cid], "is_real": true,
			})
			engine.take_from_hand(pid2, [cid], false)
			_审判弃牌.append(cid)
		_审判下标 += 1
		engine.push(BattleEngine.SHook.new("p_yi_jiao_tu_ask", {"player": player.id}, []))
		return URGENT
	# 审判：选 1 张弃牌给目标对手；其余进预言堆
	if _审判步 == 3:
		if _审判弃牌.is_empty():
			_审判步 = 0
			return SUCCESS
		if not engine.has_reply():
			询问(player.id, SHEN_PAN, 0, 1, GConst.CardSource.Hand, [], 0, "", [], true,
				0, -1, _审判弃牌, -1, {}, 0, 0, false, [], true, -1, 0,
				"【审判】：选 1 张弃牌交给目标对手")
			return WAIT
		var r7: Dictionary = take_skill_reply_full()
		var ds7: Array = r7.get("dst_ids", [])
		_审判步 = 4
		_审判对手 = int(ds7[0]) if ds7.size() == 1 else -1
		engine.push(BattleEngine.SHook.new("p_yi_jiao_tu_ask", {"player": player.id}, []))
		return URGENT
	if _审判步 == 4:
		_审判步 = 0
		var 给: Array = []
		if _审判对手 > 0:
			var 敌: BattlePlayer = engine.p(_审判对手)
			if 敌 != null:
				var 选张: int = int(_审判弃牌[0])
				for c2: Variant in _审判弃牌:
					if int(c2) == 选张:
						给.append(int(c2))
				敌.add_hand_cards(给)
		var 其余: Array = []
		for c3: Variant in _审判弃牌:
			if not 给.has(int(c3)):
				其余.append(int(c3))
		if engine.有场卡(末日预言名):
			var 表2: Dictionary = engine.取场卡(末日预言名)
			var 堆2: Array = 表2.get("pile", [])
			for c4: Variant in 其余:
				堆2.append(int(c4))
			表2["pile"] = 堆2
			表2["counter"] = 堆2.size()
			engine._broadcast_game()
		else:
			engine.to_discard(其余, {"owner": player.id, "source": "hand", "cause": SHEN_PAN})
		_审判弃牌 = []
		return SUCCESS
	# 献祭：先选系别，再结算
	if _献祭步 == 1:
		_献祭步 = 2
		if not engine.has_reply():
			var 系表2: Array = [GConst.CardElement.Wind, GConst.CardElement.Water,
				GConst.CardElement.Fire, GConst.CardElement.Earth, GConst.CardElement.Thunder]
			询问(player.id, XIAN_JI, 0, 0, GConst.CardSource.Hand, 系表2, 0, "", [], false,
				0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0,
				"【献祭】：指定 1 种系别，展示【预言】堆顶 1 张")
			return WAIT
		var r8: Dictionary = take_skill_reply_full()
		var args8: Array = r8.get("args", [])
		var 系: int = int(args8[0]) if not args8.is_empty() else 0
		var 表3: Dictionary = engine.取场卡(末日预言名)
		var 堆3: Array = 表3.get("pile", [])
		_献祭步 = 0
		if 堆3.is_empty():
			return SUCCESS
		var 牌: int = int(堆3.back())
		engine.broadcast(GConst.Msg.Card, {
			"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
			"card_ids": [牌], "is_real": true,
		})
		var 卡: GCard = Data.get_card(牌)
		if 卡 != null and 卡.element_enum() == 系:
			# 同系：移除该预言，我方战绩区 +1 宝石
			堆3.pop_back()
			表3["counter"] = 堆3.size()
			engine.set_team_gem(player.color, engine.team_gem[player.color] + 1)
			engine.to_discard([牌], {"owner": player.id, "source": "other", "cause": XIAN_JI})
		else:
			# 不同系：与牌库顶 1 张交换，然后把该预言加入你手牌
			var 顶: Array[int] = engine.移除牌库顶(1)
			if not 顶.is_empty():
				堆3.pop_back()
				堆3.append(int(顶[0]))
				表3["pile"] = 堆3
				表3["counter"] = 堆3.size()
				player.add_hand_cards([牌])
				engine._broadcast_game()
		engine._broadcast_game()
		_检查预言取空()
		return SUCCESS
	# 放逐：选摸几张（6~8）
	if _放逐步 == 1:
		_放逐步 = 2
		if not engine.has_reply():
			询问(player.id, FANG_ZHU, 0, 0, GConst.CardSource.Hand, [6, 7, 8], 0, "", [], false,
				0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0,
				"【放逐】：选择摸几张牌（6~8）")
			return WAIT
		var r9: Dictionary = take_skill_reply_full()
		var args9: Array = r9.get("args", [])
		var 张: int = int(args9[0]) if not args9.is_empty() else 6
		张 = clampi(张, 6, 8)
		engine.push_draw(player.id, 张, FANG_ZHU)
		_放逐步 = 3
		engine.push(BattleEngine.SHook.new("p_yi_jiao_tu_ask", {"player": player.id}, []))
		return URGENT
	# 放逐：移除旧场卡 → 放新的 → 6 张手牌作预言 → 额外行动二选一
	if _放逐步 == 3:
		_放逐步 = 4
		engine.移除场卡(末日预言名)
		engine.移除场卡(天雷劫火名)
		engine.移除场卡(地裂波涛名)
		var 新堆: Array = []
		var 手: Array = player.hand_cards.duplicate()
		for i: int in range(mini(6, 手.size())):
			var c5: int = player.取出实例(player.hand_cards, int(手[i]))
			if c5 > 0:
				新堆.append(c5)
		engine.加场卡({
			"id": 末日预言名, "owner": player.id, "attached": -1,
			"counter": 新堆.size(), "counter_max": 预言上限, "state": 0, "pile": 新堆,
		})
		_重算手牌上限()
		engine.push(BattleEngine.SHook.new("p_yi_jiao_tu_ask", {"player": player.id}, []))
		return URGENT
	if _放逐步 == 4:
		_放逐步 = 0
		if not engine.has_reply():
			询问(player.id, FANG_ZHU, 0, 0, GConst.CardSource.Hand,
				[GConst.ActionType.Attack, GConst.ActionType.Magic], 0, "", [], false,
				0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0,
				"【放逐】：额外 +1【攻击行动】或【法术行动】")
			return WAIT
		var r10: Dictionary = take_skill_reply_full()
		var args10: Array = r10.get("args", [])
		var 种类: int = int(args10[0]) if not args10.is_empty() else GConst.ActionType.Attack
		player.add_action(种类, FANG_ZHU, true, true)
		engine._broadcast_game()
		return SUCCESS
	return SUCCESS

var _在展示: String = ""
var _展示步: int = 0


# ============================================================
# 小工具
# ============================================================
## 翻面 / 预言取空的检查：堆空且还挂着【末日预言】就进入翻面询问
func _检查预言取空() -> void:
	if not engine.有场卡(末日预言名):
		return
	if not (engine.取场卡(末日预言名).get("pile", []) as Array).is_empty():
		return
	if _翻面步 != 0:
		return
	_翻面步 = 1
	engine.push(BattleEngine.SHook.new("p_yi_jiao_tu_ask", {"player": player.id}, []))


## 【天雷劫火】/【地裂波涛】的两种系别
func _展示系别() -> Array[int]:
	if _在展示 == 地裂波涛名:
		return [GConst.CardElement.Earth, GConst.CardElement.Water]
	return [GConst.CardElement.Thunder, GConst.CardElement.Fire]


func _我方角色() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		var pp: BattlePlayer = engine.p(pid)
		if pp != null and pp.color == player.color:
			out.append(pid)
	return out


