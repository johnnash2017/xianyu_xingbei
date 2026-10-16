extends BattleRole
## 灵符师（roleID 18）—— 移植自服务端 role/LingFu.cpp
## 【法术】灵符-雷鸣（1802）：弃 1 张雷系手牌，对 2 名角色各造成 1 点法术伤害
## 【法术】灵符-风行（1801）：弃 1 张风系手牌，指定 2 名角色各弃 1 张手牌
## 【响应】念咒（1803）：每次发动【灵符】时可将自己 1 张手牌作为【妖力】（盖牌，上限见角色表）
## 【响应】百鬼夜行（1804）：主动攻击命中后移除 1 个【妖力】，对目标角色造成 1 点法术伤害；
##                  若该【妖力】为火系牌可展示，改为指定 2 名角色，对除他们以外的所有角色各 1 点法术伤害
## 【响应】灵力崩解（1805）：与【灵符-雷鸣】或【百鬼夜行】同时发动，本次每次造成的伤害 +1（耗 1 能量）

const FENG_XING: int = 1801
const LEI_MING: int = 1802
const NIAN_ZHOU: int = 1803
const BAI_GUI_YE_XING: int = 1804
const LING_LI_BENG_JIE: int = 1805

## 本次【灵符-雷鸣】/【百鬼夜行】是否发动了【灵力崩解】（每次伤害 +1）
var _beng_jie: bool = false
## 百鬼夜行：是否展示了火系妖力（对除指定 2 名角色外的所有角色造成伤害）
var _expose: bool = false
var _expose_dsts: Array[int] = []
## 本次主动攻击是否已发动【百鬼夜行】（引擎在钩子返回 URGENT 后会重入钩子，用于避免重复触发）
var _bai_gui_done: bool = false
## 【百鬼夜行】的推进阶段：0＝还没问、1＝已选好效果（等灵力崩解）、2＝该结算了。
## 不能用引擎的 step：钩子轮次开始会把所有角色的 step 清零（只豁免 SkillRun 型的技能挂起），
## 而这条技能要跨「百鬼夜行 → 灵力崩解」两次询问等待 —— 中途被别的钩子轮次插进来
## （选妖力要 remove_cover，会压入一轮 p_cover_change）就会被打回第 0 步：重跑一次选效果、
## 拿崩解的回复去解析、判定失败 → 整条技能静默不生效。手上没星石时不等崩解，才看不出这个毛病。
var _bai_gui_phase: int = 0


func available_skills() -> Array:
	var out: Array = []
	# 灵符-风行/雷鸣：只有对应系别的手牌可作发动牌，下发给界面把其余手牌置灰（v_magic_skill 校验同一条）；
	# 手里没有对应系别牌时按钮仍摆出、置灰
	var 风系牌: Array[int] = hand_ids_where(func(_cid: int, c: GCard) -> bool: return c.element_enum() == GConst.CardElement.Wind)
	out.append({"type": GConst.ActionType.MagicSkill, "id": FENG_XING, "need_card": 1, "need_target": 2,
		"cards": 风系牌, "enabled": not 风系牌.is_empty()})
	var 雷系牌: Array[int] = hand_ids_where(func(_cid: int, c: GCard) -> bool: return c.element_enum() == GConst.CardElement.Thunder)
	out.append({"type": GConst.ActionType.MagicSkill, "id": LEI_MING, "need_card": 1, "need_target": 2,
		"cards": 雷系牌, "enabled": not 雷系牌.is_empty()})
	return out


# ============================================================
# 主动法术技能：灵符-风行 / 灵符-雷鸣
# ============================================================
func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	var aid: int = int(action.get("action_id", 0))
	if aid != FENG_XING and aid != LEI_MING:
		return GConst.GE_INVALID_ACTION
	var cards: Array = action.get("card_ids", [])
	if cards.is_empty():
		return GConst.GE_INVALID_CARDID
	var cid: int = int(cards[0])
	var card: GCard = Data.get_card(cid)
	var need_elem: int = GConst.CardElement.Wind if aid == FENG_XING else GConst.CardElement.Thunder
	# 必须是自己的手牌且为对应系别
	if not player.has_hand_card(cid) or card == null or card.element_enum() != need_elem:
		return GConst.GE_INVALID_CARDID
	if action.get("dst_ids", []).size() != 2:
		return GConst.GE_INVALID_PLAYERID
	# 两名目标必须是不同的人（说明是「2 名角色」）：同一人被点两次不算
	if _has_duplicate(action.get("dst_ids", [])):
		return GConst.GE_INVALID_PLAYERID
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	match int(action.get("action_id", 0)):
		FENG_XING:
			return _feng_xing(action)
		LEI_MING:
			return _lei_ming(action)
	return GConst.GE_INVALID_ACTION


## 灵符-风行：弃 1 张风系牌，指定 2 名角色各弃 1 张手牌
## 服务端压栈顺序（后进先出）为：弃掉打出的灵符 → 念咒 → 各目标弃牌
func _feng_xing(action: Dictionary) -> int:
	var dsts: Array = action.get("dst_ids", [])
	var cid: int = int(action.get("card_ids", [])[0])
	if step == 0:
		step = 1
		notice_skill(FENG_XING, dsts)
		_discard_played(cid)
	if step == 1:
		var r: int = _nian_zhou()
		if r == WAIT:
			return WAIT
		step = 2
	if step == 2:
		return _feng_targets_discard(dsts)
	return SUCCESS


## 灵符-雷鸣：弃 1 张雷系牌，念咒 → 灵力崩解 → 对 2 名角色各造成 1 点法术伤害
func _lei_ming(action: Dictionary) -> int:
	var dsts: Array = action.get("dst_ids", [])
	var cid: int = int(action.get("card_ids", [])[0])
	if step == 0:
		_beng_jie = false
		step = 1
		notice_skill(LEI_MING, dsts)
		_discard_played(cid)
	if step == 1:
		var r: int = _nian_zhou()
		if r == WAIT:
			return WAIT
		step = NIAN_ZHOU
	if step == NIAN_ZHOU:
		var r2: int = _ling_li_beng_jie(dsts)
		if r2 == WAIT:
			return WAIT
		step = LING_LI_BENG_JIE
	if step == LING_LI_BENG_JIE:
		var point: int = 2 if _beng_jie else 1
		# 2 名目标按玩家点选顺序结算；伤害状态是栈（后压先算）→ 逆序压栈
		for i: int in range(dsts.size() - 1, -1, -1):
			engine.push_harm({
				"src": player.id, "dst": int(dsts[i]), "point": point,
				"cause": LEI_MING, "type": GConst.HarmType.Magic,
			})
		step = STEP_DONE
		engine._broadcast_game()
		return URGENT
	return SUCCESS


## 念咒：妖力未达上限时，询问是否将 1 张手牌作为【妖力】
func _nian_zhou() -> int:
	if player.cover_cards.size() > 1:
		return SUCCESS
	if not engine.has_reply():
		询问(player.id, NIAN_ZHOU, 1, 0)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		return SUCCESS
	var cid: int = _first_hand_card(r.get("card_ids", []))
	if cid < 0:
		return SUCCESS
	notice_skill(NIAN_ZHOU, [player.id])
	# 【念咒】是把牌「面朝下」当【妖力】盖下（技能原文），不能亮给全场看：
	# 之前这里发了一条全场广播的「展示」，等于把这张牌公开了。盖牌变动本身会随状态同步刷新，
	# 对手只能看到盖牌数量变化，看不到是哪张牌
	engine.take_from_hand(player.id, [cid])
	engine.add_cover(player.id, [cid], player.id, NIAN_ZHOU)
	engine._broadcast_game()
	return SUCCESS


## 灵力崩解：耗 1 能量（优先水晶），使本次每次伤害 +1。
## dsts ＝ 本次实际会挨打的那几名角色：随询问下发给客户端，由它把这些头像选中并写「2 法术伤害」
## （基础 1 点在技能表那一侧显示，见 技能_灵符雷鸣 / 技能_百鬼夜行 的指示器）
func _ling_li_beng_jie(dsts: Array) -> int:
	_beng_jie = false
	if player.get_energy() < 1:
		return SUCCESS
	if not engine.has_reply():
		询问(player.id, LING_LI_BENG_JIE, 0, 0, GConst.CardSource.Hand, [], 0, "", [], true, 0, -1, dsts)
		return WAIT
	if not take_skill_reply():
		return SUCCESS
	notice_skill(LING_LI_BENG_JIE, [player.id])
	if player.crystal > 0:
		player.set_crystal(player.crystal - 1)
	else:
		player.set_gem(player.gem - 1)
	_beng_jie = true
	engine._broadcast_game()
	return SUCCESS


## 风行：按玩家点选顺序，逐个强制弃 1 张手牌
## 直接复用引擎通用的「按要求弃牌」状态：手牌为空的目标会被自动跳过（want=0）
func _feng_targets_discard(dsts: Array) -> int:
	# 引擎状态栈是后进先出 → 逆序压入，实际按点选顺序依次结算
	for i: int in range(dsts.size() - 1, -1, -1):
		engine.push(BattleEngine.SRequestDiscard.new(int(dsts[i]), 1, 0, FENG_XING))
	step = STEP_DONE
	return URGENT


# ============================================================
# 百鬼夜行：主动攻击命中后，移除 1 个【妖力】
# ============================================================
## 每次自己宣告主动攻击时重置【百鬼夜行】标记
func p_timeline_1(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) == player.id:
		_bai_gui_done = false
		_bai_gui_phase = 0
	return SUCCESS


func p_timeline_2_hit(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("src", -1)) != player.id:
		return SUCCESS
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	if _bai_gui_done:
		return SUCCESS
	if _bai_gui_phase == 0:
		if player.cover_cards.is_empty():
			_bai_gui_done = true
			return SUCCESS
		if not engine.has_reply():
			# 只有盖牌区里真有火系【妖力】才给「展示」那个选项 —— 没火牌根本展示不了，
			# 摆出来只会让玩家选了个必然落空的分支
			var 选项: Array = []
			if _有火系妖力():
				选项.append({"value": 1, "label": 提示(BAI_GUI_YE_XING, 1)})
			选项.append({"value": 0, "label": 提示(BAI_GUI_YE_XING, 2)})
			# can_cancel = false：选中攻击命中后【百鬼夜行】必须执行，不给「取消」这条路
			# （客户端会先在居中弹窗里让玩家选效果，选完再选妖力与目标、按「确定」发动）
			询问(player.id, BAI_GUI_YE_XING, 1, 2, GConst.CardSource.Cover, 选项, 0, "", [], false)
			return WAIT
		if not _bai_gui_cast():
			_bai_gui_done = true
			return SUCCESS
		_bai_gui_phase = 1
	if _bai_gui_phase == 1:
		var r: int = _ling_li_beng_jie(_bai_gui_damage_targets())
		if r == WAIT:
			return WAIT
		_bai_gui_phase = 2
	if _bai_gui_phase == 2:
		_bai_gui_done = true
		_bai_gui_phase = 0
		return _bai_gui_effect()
	return SUCCESS


## 解析百鬼夜行的选择：args[0]=1 展示火系妖力（指定 2 名角色），args[0]=0 指定 1 名角色
func _bai_gui_cast() -> bool:
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	var cards: Array = r.get("card_ids", [])
	if args.is_empty() or cards.is_empty():
		return false
	var cid: int = int(cards[0])
	if not player.cover_cards.has(cid):
		return false
	var dsts: Array = r.get("dst_ids", [])
	_expose_dsts = []
	var choice: int = int(args[0])
	if choice == 1:
		var card: GCard = Data.get_card(cid)
		if card == null or card.element_enum() != GConst.CardElement.Fire or dsts.size() != 2:
			return false
		_expose = true
		_expose_dsts.append(int(dsts[0]))
		_expose_dsts.append(int(dsts[1]))
	elif choice == 0:
		if dsts.size() != 1:
			return false
		_expose = false
		_expose_dsts.append(int(dsts[0]))
	else:
		return false
	notice_skill(BAI_GUI_YE_XING, _expose_dsts)
	if _expose:
		# 服务端只在「展示火系【妖力】」分支才明牌；选「不展示」时隐藏这张牌
		engine.broadcast(GConst.Msg.Card, {
			"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
			"card_ids": [cid], "is_real": true,
		})
	engine.to_discard([cid])
	engine.remove_cover(player.id, [cid], player.id, BAI_GUI_YE_XING)
	engine._broadcast_game()
	return true


## 百鬼夜行伤害：展示时为「除指定 2 名角色外的所有角色」，否则为指定的 1 名角色
func _bai_gui_effect() -> int:
	var point: int = 2 if _beng_jie else 1
	# 按服务端座位序（自己 / 下家先）结算；伤害状态是栈（后压先算）→ 逆序压栈
	var 顺序: Array[int] = 结算顺序(_bai_gui_damage_targets())
	for i: int in range(顺序.size() - 1, -1, -1):
		engine.push_harm({
			"src": player.id, "dst": 顺序[i], "point": point,
			"cause": BAI_GUI_YE_XING, "type": GConst.HarmType.Magic,
		})
	engine._broadcast_game()
	return URGENT


## 本次【百鬼夜行】实际会挨伤害的角色：展示火系妖力＝除指定 2 名角色外全体（含自己）；
## 不展示＝指定的那 1 名角色。（灵力崩解的询问也拿它当「会挨打的人」下发，见 _ling_li_beng_jie）
func _bai_gui_damage_targets() -> Array[int]:
	if not _expose:
		return [_expose_dsts[0]] if not _expose_dsts.is_empty() else []
	var out: Array[int] = []
	for pid: int in engine.order:
		if not _expose_dsts.has(pid):
			out.append(pid)
	return out


# ============================================================
# 工具
# ============================================================
## 盖牌区里有没有火系【妖力】（只有真有火牌才给「展示火系妖力」那个效果）
func _有火系妖力() -> bool:
	for cid: int in player.cover_cards:
		var c: GCard = Data.get_card(cid)
		if c != null and c.element_enum() == GConst.CardElement.Fire:
			return true
	return false


## 取回复中第一张仍在手牌里的牌
func _first_hand_card(cards: Array) -> int:
	for c: Variant in cards:
		if player.has_hand_card(int(c)):
			return int(c)
	return -1


## 展示并弃掉打出的灵符
func _discard_played(cid: int) -> void:
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": [cid], "is_real": true,
	})
	engine.take_from_hand(player.id, [cid], true)
	engine.to_discard([cid])
	engine._broadcast_game()
