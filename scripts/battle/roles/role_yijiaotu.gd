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
##    移除【末日预言】、换一张同名场卡入场，然后立刻结算它的「展示时」效果。
##    展示结算完把 _翻面步 归零（【放逐】放进新的【末日预言】后还能再翻一次）。
## 4. 【天雷劫火】/【地裂波涛】「展示时」：选 1 种系别 → 弃 X 张该系牌（≤4，可为 0）→
##    摸 X 张【强制】→ 选 1 名目标对手 → 他自选弃任意张该系牌【展示】（可不弃）→
##    造成 X+1 点法术伤害③。两项（雷/火 或 地/水）二选一发动。
##    【贪婪】9506：展示时花 1 点能量，把「选一项」改成「两项都发动、顺序由你决定」。
##    结算后场卡**不立刻移除**，留到异教徒自己回合开始的【灾殃止息】9509 再移除。
## 5. 【审判】逐名队友问「弃 1 张牌【展示】」，然后各自摸 1 张【强制】，再由你选 1 张弃牌
##    交给目标对手；【末日预言】在场时其余弃牌洗混放到预言堆顶。
## 6. 【放逐】「无视手牌上限摸 6-8 张」：摸牌期间把 hand_cards_max 临时抬到「现有手牌 + 8」，
##    摸完在 step3 把 6 张手牌挪成【预言】，再 _重算手牌上限() 恢复。额外行动二选一（攻击 / 法术）。

const YI_DUAN_XIE_SHUO: int = 9501
const SHEN_PAN: int = 9502
const XIAN_JI: int = 9503
const MO_RI_YU_YAN: int = 9504
const FANG_ZHU: int = 9505
const TAN_LAN: int = 9506
## 专属技关键词：翻面后的两张（展示时发动）、以及回合开始移除它们的被动
const TIAN_LEI_JIE_HUO: int = 9507
const DI_LIE_BO_TAO: int = 9508
const ZAI_YANG_ZHI_XI: int = 9509

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
## 审判：把哪一张弃牌交给对手（_审判弃牌 的下标）
var _审判给: int = 0
## 翻面 / 展示时的进度
var _翻面步: int = 0
var _展示系: int = 0
var _展示X: int = 0
var _展示对手: int = -1
## 展示时这一轮要依次结算的系别（贪婪＝两项都发动，顺序由玩家选）
var _展示模式: Array[int] = []
var _展示序号: int = 0
var _展示贪婪: bool = false


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
	if engine.有场卡(天雷劫火名) or engine.有场卡(地裂波涛名):
		notice_skill(ZAI_YANG_ZHI_XI, [player.id])
		if engine.有场卡(天雷劫火名):
			engine.移除场卡(天雷劫火名)
		if engine.有场卡(地裂波涛名):
			engine.移除场卡(地裂波涛名)
		engine._broadcast_game()
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
	if _审判步 != 0 and not engine.has_reply():
		# 等回复期间（_审判步 == 1 且有回复）放行到下面 take
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
	# 「无视你的手牌上限摸 6-8 张」：摸牌期间把上限临时抬到「现有手牌 + 8」，
	# 摸完再把 6 张挪成【预言】、上限按【末日预言】在场与否重算（见 step3）
	player.hand_cards_max = player.hand_cards.size() + 8
	_放逐步 = 1
	engine.push(BattleEngine.SHook.new("p_yi_jiao_tu_ask", {"player": player.id}, []))
	return URGENT

var _放逐步: int = 0


# ============================================================
# 9504 翻面 → 9507 / 9508「展示时」效果（9506 贪婪改「两项都发动」、9509 灾殃止息移除）
# ============================================================
func p_yi_jiao_tu_ask(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	# 翻面：选变成哪一张
	if _翻面步 == 1:
		if not engine.has_reply():
			询问(player.id, MO_RI_YU_YAN, 0, 0, GConst.CardSource.Hand,
				[{"value": 1, "label": "天雷劫火"}, {"value": 2, "label": "地裂波涛"}], 0, "", [], false,
				0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0,
				"【末日预言】的【预言】已空：翻面为【天雷劫火】或【地裂波涛】（1=天雷劫火 / 2=地裂波涛）")
			return WAIT
		# 阶段在取完回复之后再推进：重入时 _翻面步 仍是 1
		var r: Dictionary = take_skill_reply_full()
		_翻面步 = 2
		var args: Array = r.get("args", [])
		var 选: int = int(args[0]) if not args.is_empty() else 0
		var 名: String = 地裂波涛名 if 选 == 2 else 天雷劫火名
		engine.移除场卡(末日预言名)
		engine.加场卡({"id": 名, "owner": player.id, "attached": -1,
			"counter": 0, "counter_max": 0, "state": 1})
		notice_skill(MO_RI_YU_YAN, [player.id])
		_在展示 = 名
		_展示模式.clear()
		_展示序号 = 0
		_展示贪婪 = false
		_展示对手 = -1
		# 先把「是否发动贪婪」问掉，再决定发动一项还是两项（贪婪＝两项都发动、顺序自定）。
		# 这里必须用递归继续，不要再压一个新钩子：当前钩子还在栈上，等新钩子跑完它会被重新
		# 执行一次，用同一份 _展示步 再问一遍。
		_展示步 = 10
		return p_yi_jiao_tu_ask(ctx)
	# 展示时：是否发动【贪婪】（消耗 1 水晶 → 两项都发动）
	if _展示步 == 10:
		if player.get_energy() <= 0:
			_展示步 = 1
			return p_yi_jiao_tu_ask(ctx)
		if not engine.has_reply():
			询问(player.id, TAN_LAN, 0, 0, GConst.CardSource.Hand, [], 0, "", [], true,
				0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0,
				"是否发动【贪婪】（消耗 1 点能量）：本次【%s】改为两项都发动，顺序由你决定？" % _在展示)
			return WAIT
		_展示贪婪 = take_skill_reply()
		if _展示贪婪:
			player.remove_energy(1)
			notice_skill(TAN_LAN, [player.id])
			_展示步 = 11
		else:
			_展示步 = 1
		return p_yi_jiao_tu_ask(ctx)
	# 展示时（贪婪）：选两项的发动顺序
	if _展示步 == 11:
		var 序表: Array[int] = _展示系别()
		if not engine.has_reply():
			询问(player.id, TAN_LAN, 0, 0, GConst.CardSource.Hand,
				[{"value": 1, "label": "先%s后%s" % [GConst.element_to_chinese(序表[0]), GConst.element_to_chinese(序表[1])]},
				 {"value": 2, "label": "先%s后%s" % [GConst.element_to_chinese(序表[1]), GConst.element_to_chinese(序表[0])]}],
				0, "", [], false,
				0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0,
				"【贪婪】：选择发动顺序（1＝先%s后%s / 2＝先%s后%s）"
				% [GConst.element_to_chinese(序表[0]), GConst.element_to_chinese(序表[1]),
					GConst.element_to_chinese(序表[1]), GConst.element_to_chinese(序表[0])])
			return WAIT
		var rq: Dictionary = take_skill_reply_full()
		var aq: Array = rq.get("args", [])
		var 先: int = int(aq[0]) if not aq.is_empty() else 1
		# 类型化数组不能直接赋一个无类型字面量（运行时会报 Array → Array[int]），逐项 append
		_展示模式.clear()
		if 先 == 2:
			_展示模式.append(序表[1])
			_展示模式.append(序表[0])
		else:
			_展示模式.append(序表[0])
			_展示模式.append(序表[1])
		_展示序号 = 0
		_展示步 = 3
		return p_yi_jiao_tu_ask(ctx)
	# 展示时（不发动贪婪）：选 1 种系别发动
	if _展示步 == 1:
		var 系表: Array[int] = _展示系别()
		if not engine.has_reply():
			询问(player.id, _展示技能号(), 0, 0, GConst.CardSource.Hand, _系别选项(系表), 0, "", [], false,
				0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0,
				"【%s】：选择 1 种系别发动（弃 X 张该系牌摸 X 张；目标对手弃任意张该系牌后，你对他造成 X+1 点法术伤害）"
				% _在展示)
			return WAIT
		var r2: Dictionary = take_skill_reply_full()
		var args2: Array = r2.get("args", [])
		var 选系: int = int(args2[0]) if not args2.is_empty() else int(系表[0])
		if not 系表.has(选系):
			选系 = int(系表[0])
		_展示模式.clear()
		_展示模式.append(选系)
		_展示序号 = 0
		_展示步 = 3
		return p_yi_jiao_tu_ask(ctx)
	# 展示时（每一项）：选 X（弃几张该系牌，最多 4，且不能超过手里该系牌数）
	if _展示步 == 3:
		if _展示序号 >= _展示模式.size():
			# 本次展示全部结算完：清状态、清翻面标记（放逐放进新的【末日预言】后还能再翻）
			_展示步 = 0
			_展示模式.clear()
			_展示对手 = -1
			_翻面步 = 0
			return SUCCESS
		_展示系 = int(_展示模式[_展示序号])
		var 同系: Array[int] = hand_ids_where(
			func(_cid: int, c: GCard) -> bool: return c.element_enum() == _展示系)
		_展示X = mini(4, 同系.size())
		if _展示X <= 0:
			_展示步 = 5
			return p_yi_jiao_tu_ask(ctx)
		var 展示系名: String = GConst.element_to_chinese(_展示系)
		if not engine.has_reply():
			询问(player.id, _展示技能号(), _展示X, 0, GConst.CardSource.Hand, [], _展示X, "", [], false,
				0, player.id, [], _展示X, {}, 0, 0, false, [], true, -1, 0,
				"【%s】：弃最多 %d 张%s系牌【展示】" % [_在展示, _展示X, 展示系名])
			return WAIT
		var r3: Dictionary = take_skill_reply_full()
		var cards: Array = r3.get("card_ids", [])
		var 弃: Array = []
		for c: Variant in cards:
			if 弃.size() < _展示X and player.有手牌(int(c)):
				var 卡: GCard = Data.get_card(int(c))
				if 卡 != null and 卡.element_enum() == _展示系 and not 弃.has(int(c)):
					弃.append(int(c))
		if not 弃.is_empty():
			engine.broadcast(GConst.Msg.Card, {
				"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
				"card_ids": 弃, "is_real": true,
			})
			engine.take_from_hand(player.id, 弃, false)
			engine.to_discard(弃, {"owner": player.id, "source": "hand", "cause": _展示技能号()})
			engine._log_discard(player.id, 弃, false)
		_展示X = 弃.size()
		_展示步 = 5
		return p_yi_jiao_tu_ask(ctx)
	# 展示时（每一项）：摸 X 张【强制】→ 选目标对手
	if _展示步 == 5:
		if _展示X > 0:
			engine.push_draw(player.id, _展示X, _展示技能号())
		# 摸牌先压进栈；阶段推进到「等目标回复」，回来由 6 号分支取回复（避免重复摸牌）
		_展示步 = 6
		if not engine.has_reply():
			询问(player.id, _展示技能号(), 0, 1, GConst.CardSource.Hand, [], 0, "", [], false,
				0, -1, enemy_ids(), -1, {}, 0, 0, false, [], true, -1, 0,
				"【%s】：指定 1 名目标对手（他弃牌后你造成 %d 点法术伤害）" % [_在展示, _展示X + 1])
			return WAIT
	if _展示步 == 6:
		if not engine.has_reply():
			return WAIT
		var r5: Dictionary = take_skill_reply_full()
		var ds: Array = r5.get("dst_ids", [])
		_展示对手 = int(ds[0]) if ds.size() == 1 else -1
		if _展示对手 < 0 or engine.p(_展示对手) == null:
			return _展示本项结束()
		_展示步 = 7
		return p_yi_jiao_tu_ask(ctx)
	# 展示时（每一项）：目标对手自选弃任意张该系牌【展示】（可不弃）
	if _展示步 == 7:
		var 对手: BattlePlayer = engine.p(_展示对手)
		var 牌面: Array = []
		var 上限: int = 0
		if 对手 != null:
			for cid: int in 对手.hand_cards:
				var 卡2: GCard = Data.get_card(cid)
				if 卡2 == null or 卡2.element_enum() != _展示系:
					continue
				上限 += 1
				var 面2: int = GConst.牌号(int(cid))
				if not 牌面.has(面2):
					牌面.append(面2)
		if 上限 <= 0:
			return _展示本项伤害()
		if not engine.has_reply():
			询问(_展示对手, _展示技能号(), 0, 0, GConst.CardSource.Hand, [], 上限, "", 牌面, true,
				0, _展示对手, [], 上限, {}, 0, 0, false, [], true, -1, 0,
				"【%s】：请弃任意张%s系牌【展示】（可不弃）"
				% [_在展示, GConst.element_to_chinese(_展示系)])
			return WAIT
		var r7: Dictionary = take_skill_reply_full()
		var 已弃: Array = []
		var 对手2: BattlePlayer = engine.p(_展示对手)
		if 对手2 != null:
			for c: Variant in r7.get("card_ids", []):
				var cid2: int = int(c)
				var 卡3: GCard = Data.get_card(cid2)
				if 已弃.size() < 上限 and 对手2.有手牌(cid2) and 卡3 != null 						and 卡3.element_enum() == _展示系 and not 已弃.has(cid2):
					已弃.append(cid2)
			if not 已弃.is_empty():
				engine.broadcast(GConst.Msg.Card, {
					"type": GConst.CardMsgType.Show, "src_id": _展示对手, "dst_id": _展示对手,
					"card_ids": 已弃, "is_real": true,
				})
				engine.take_from_hand(_展示对手, 已弃, false)
				engine.to_discard(已弃, {"owner": _展示对手, "source": "hand", "cause": _展示技能号()})
				engine._log_discard(_展示对手, 已弃, false)
		return _展示本项伤害()
	# 展示时（每一项）：伤害结算完 → 进入下一项（贪婪）或收尾
	if _展示步 == 9:
		return _展示本项结束()
	# 审判：逐名队友弃 1 张牌【展示】
	if _审判步 == 2:
		var 队友: Array[int] = _我方角色()
		if _审判下标 >= 队友.size():
			# 各自摸 1 张【强制】
			for pid: int in 队友:
				engine.强制摸牌(pid, 1, SHEN_PAN)
			_审判步 = 3
			return p_yi_jiao_tu_ask({"player": player.id})
		var pid2: int = int(队友[_审判下标])
		var pp: BattlePlayer = engine.p(pid2)
		if pp == null or pp.hand_cards.is_empty():
			_审判下标 += 1
			return p_yi_jiao_tu_ask({"player": player.id})
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
		return p_yi_jiao_tu_ask({"player": player.id})
	# 审判：选 1 张弃牌给目标对手；其余进预言堆
	if _审判步 == 3:
		if _审判弃牌.is_empty():
			_审判步 = 0
			return SUCCESS
		if not engine.has_reply():
			var 弃牌选项: Array = []
			for i: int in range(_审判弃牌.size()):
				var 弃卡: GCard = Data.get_card(int(_审判弃牌[i]))
				弃牌选项.append({"value": i + 1,
					"label": 弃卡.card_name if 弃卡 != null else "弃牌", "card_id": int(_审判弃牌[i])})
			询问(player.id, SHEN_PAN, 0, 1, GConst.CardSource.Hand, 弃牌选项, 0, "", [], false,
				0, -1, enemy_ids(), -1, {}, 0, 0, false, [], true, -1, 0,
				"【审判】：选 1 张弃牌交给目标对手")
			return WAIT
		var r7: Dictionary = take_skill_reply_full()
		var ds7: Array = r7.get("dst_ids", [])
		var args7: Array = r7.get("args", [])
		_审判步 = 4
		_审判对手 = int(ds7[0]) if ds7.size() == 1 else -1
		_审判给 = int(args7[0]) - 1 if not args7.is_empty() else 0
		return p_yi_jiao_tu_ask({"player": player.id})
	if _审判步 == 4:
		_审判步 = 0
		var 给: Array = []
		if _审判对手 > 0 and not _审判弃牌.is_empty():
			var 敌: BattlePlayer = engine.p(_审判对手)
			var 下标: int = clampi(_审判给, 0, _审判弃牌.size() - 1)
			if 敌 != null:
				给.append(int(_审判弃牌[下标]))
				敌.add_hand_cards(给)
		var 其余: Array = []
		for c3: Variant in _审判弃牌:
			if not 给.has(int(c3)):
				其余.append(int(c3))
		if engine.有场卡(末日预言名):
			var 表2: Dictionary = engine.取场卡(末日预言名)
			var 堆2: Array = 表2.get("pile", [])
			# 「将其余弃牌面朝下洗混放置到【预言】堆顶部」：只打乱这批弃牌，再压到顶部
			其余.shuffle()
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
		if not engine.has_reply():
			var 系表2: Array[int] = [GConst.CardElement.Wind, GConst.CardElement.Water,
				GConst.CardElement.Fire, GConst.CardElement.Earth, GConst.CardElement.Thunder]
			询问(player.id, XIAN_JI, 0, 0, GConst.CardSource.Hand, _系别选项(系表2), 0, "", [], false,
				0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0,
				"【献祭】：指定 1 种系别，展示【预言】堆顶 1 张")
			return WAIT
		# 阶段在取完回复之后再推进：重入时 _献祭步 仍是 1
		var r8: Dictionary = take_skill_reply_full()
		_献祭步 = 2
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
		if not engine.has_reply():
			询问(player.id, FANG_ZHU, 0, 0, GConst.CardSource.Hand,
				[{"value": 6, "label": "摸 6 张"}, {"value": 7, "label": "摸 7 张"}, {"value": 8, "label": "摸 8 张"}],
				0, "", [], false,
				0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0,
				"【放逐】：选择摸几张牌（6~8）")
			return WAIT
		# 阶段在取完回复之后再推进：重入时 _放逐步 仍是 1
		var r9: Dictionary = take_skill_reply_full()
		_放逐步 = 2
		var args9: Array = r9.get("args", [])
		var 张: int = int(args9[0]) if not args9.is_empty() else 6
		张 = clampi(张, 6, 8)
		# 只压摸牌状态、返回 URGENT：摸完当前钩子会被重新执行，接着走 _放逐步 == 3
		_放逐步 = 3
		engine.push_draw(player.id, 张, FANG_ZHU)
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
		_翻面步 = 0
		return p_yi_jiao_tu_ask({"player": player.id})
	if _放逐步 == 4:
		if not engine.has_reply():
			询问(player.id, FANG_ZHU, 0, 0, GConst.CardSource.Hand,
				[{"value": GConst.ActionType.Attack, "label": "额外攻击行动"},
				 {"value": GConst.ActionType.Magic, "label": "额外法术行动"}], 0, "", [], false,
				0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0,
				"【放逐】：额外 +1【攻击行动】或【法术行动】")
			return WAIT
		var r10: Dictionary = take_skill_reply_full()
		_放逐步 = 0
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


## 系别枚举 → 询问选项（ask_skill 只收 {value,label} 字典，纯数字数组会在运行时出错）
func _系别选项(系表: Array) -> Array:
	var out: Array = []
	for 系: Variant in 系表:
		out.append({"value": int(系), "label": "%s系" % GConst.element_to_chinese(int(系))})
	return out


## 当前展示的这张牌该用哪个技能号（天雷劫火 9507 / 地裂波涛 9508）：询问与伤害来源都用它
func _展示技能号() -> int:
	return DI_LIE_BO_TAO if _在展示 == 地裂波涛名 else TIAN_LEI_JIE_HUO


## 展示流程里「每一项」的伤害：目标对手弃完牌后造成 X+1 点法术伤害③
func _展示本项伤害() -> int:
	_展示步 = 9
	if _展示对手 > 0:
		engine.push_harm({
			"src": player.id, "dst": _展示对手, "point": _展示X + 1,
			"cause": _展示技能号(), "type": GConst.HarmType.Magic,
		})
		return URGENT
	return _展示本项结束()


## 一项结算完：下一项（贪婪）或收尾（清翻面标记，放逐放进新【末日预言】后还能再翻）
func _展示本项结束() -> int:
	_展示对手 = -1
	_展示序号 += 1
	_展示步 = 3
	return p_yi_jiao_tu_ask({"player": player.id})


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


