extends BattleRole
## 结界师（82）：结界仪式 / 荒神之力 / 荒神祭仪 / 禁魔境 / 琉璃境 / 绝界 / 伏魔境
##
## 区域与标记：
## - 【祭】＝0 号指示物（角色表「指示物」0:祭:3，上限 3），统一用 player.add_token(0) / remove_token(0)。
## - 【结界】＝盖牌区**面朝上**的牌（角色表槽 2 上限 2），放进去用
##   engine.add_cover(..., open = true, tag = "结界")，读出来用 player.盖牌按标记("结界")。
##   面朝上意味着牌面公开：快照的 cover_opens 会带上牌面，客户端在面板状态区按卡面显示。
## - 【绝界】＝场卡（F1）：owner＝结界师，attached＝拥有它的角色；拥有者的基础效果无法触发。
##
## 口径：
## 1. 【荒神之力】按「结界里有没有与本次攻击同系的牌」判，多张同系也只 +1（原文只说 +1）。
## 2. 【荒神祭仪】的「目标角色主动攻击时①」对**所有角色**的攻击都看（不只自己）：
##    攻击系别与任一张结界同系 → 先 +1 祭；再问要不要额外移除 3 祭做后半段（弃 1 张牌、
##    移除 1 个结界并横置）。横置＝player.tap = true，【持续】＝要等琉璃境的重置。
## 3. 【绝界】的「拥有此卡的角色回合结束前，结界师移除 1 个结界」在拥有者的回合结束时结算。

const JIE_JIE_YI_SHI: int = 8201
const HUANG_SHEN_ZHI_LI: int = 8202
const HUANG_SHEN_JI_YI: int = 8203
const JIN_MO_JING: int = 8204
const LIU_LI_JING: int = 8205
const JUE_JIE: int = 8206
const FU_MO_JING: int = 8207

const JI_SLOT: int = 0
const JIE_JIE标记: String = "结界"
const 绝界名: String = "绝界"

var _t1_step: int = 0
var _琉璃_step: int = 0
## 【伏魔境】：记下最近一次发动时对手队伍的士气，用于「若因此造成对方士气下降」的判定
var _伏魔待查: Dictionary = {}


# ============================================================
# 技能栏
# ============================================================
func available_skills() -> Array:
	var 全体: Array[int] = _全体角色()
	var 对手: Array[int] = enemy_ids()
	var 手牌数: int = player.hand_cards.size()
	var 祭: int = player.token_num(JI_SLOT)
	return [
		{
			"type": GConst.ActionType.MagicSkill,
			"id": JIE_JIE_YI_SHI,
			"need_card": 2,
			"target_max": 2,
			"cards": player.hand_cards.duplicate(),
			"enabled": 手牌数 >= 2 and player.cover_space() >= 2,
		},
		{
			"type": GConst.ActionType.MagicSkill,
			"id": JIN_MO_JING,
			"need_card": 0,
			"need_target": 1,
			"targets": 全体,
			"enabled": 祭 >= 1 and 手牌数 >= 1 and not 全体.is_empty(),
		},
		{
			"type": GConst.ActionType.MagicSkill,
			"id": FU_MO_JING,
			"need_target": 1,
			"targets": 对手,
			"enabled": player.get_energy() >= 1 and not 对手.is_empty(),
		},
	]


func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	match int(action.get("action_id", 0)):
		JIE_JIE_YI_SHI:
			var cards: Array = action.get("card_ids", [])
			if cards.size() != 2:
				return GConst.GE_INVALID_CARDID
			if not player.can_add_cover_cards(2):
				return GConst.GE_INVALID_ACTION
			for c: Variant in cards:
				if not player.有手牌(int(c)):
					return GConst.GE_INVALID_CARDID
			return GConst.GE_SUCCESS
		JIN_MO_JING:
			if player.token_num(JI_SLOT) < 1 or player.hand_cards.is_empty():
				return GConst.GE_INVALID_ACTION
			var dsts: Array = action.get("dst_ids", [])
			if dsts.size() != 1 or engine.p(int(dsts[0])) == null:
				return GConst.GE_INVALID_ACTION
			return GConst.GE_SUCCESS
		FU_MO_JING:
			if player.get_energy() < 1:
				return GConst.GE_INVALID_ACTION
			var ds: Array = action.get("dst_ids", [])
			if ds.size() != 1 or engine.p(int(ds[0])) == null:
				return GConst.GE_INVALID_ACTION
			return GConst.GE_SUCCESS
	return GConst.GE_INVALID_ACTION


func p_magic_skill(action: Dictionary) -> int:
	match int(action.get("action_id", 0)):
		JIE_JIE_YI_SHI:
			return _p_结界仪式(action)
		JIN_MO_JING:
			return _p_禁魔境(action)
		FU_MO_JING:
			return _p_伏魔境(action)
	return EMPTY_HANDLE


# ============================================================
# 8201 结界仪式：2 张手牌面朝上放进盖牌区作为【结界】→ 你 +1【祭】
# ============================================================
func _p_结界仪式(action: Dictionary) -> int:
	var 校验: int = v_magic_skill(action)
	if 校验 != GConst.GE_SUCCESS:
		return 校验
	var cards: Array = action.get("card_ids", [])
	notice_skill(JIE_JIE_YI_SHI)
	var 放: Array = []
	for c: Variant in cards:
		var cid: int = player.取出实例(player.hand_cards, int(c))
		if cid >= 0:
			放.append(cid)
	if 放.is_empty():
		return SUCCESS
	engine.add_cover(player.id, 放, player.id, JIE_JIE_YI_SHI, true, JIE_JIE标记)
	_加祭(1, JIE_JIE_YI_SHI)
	return URGENT


# ============================================================
# 8204 禁魔境：移除 1 祭 → 把【绝界】转移 / 放置到目标角色前 → 你弃 1 张牌
# ============================================================
func _p_禁魔境(action: Dictionary) -> int:
	var 校验: int = v_magic_skill(action)
	if 校验 != GConst.GE_SUCCESS:
		return 校验
	var dst: int = int((action.get("dst_ids", []) as Array)[0])
	player.remove_token(JI_SLOT, 1)
	notice_skill(JIN_MO_JING, [dst])
	# 同一张【绝界】只存在一份：先移除旧的（转移＝换个 attached）
	engine.加场卡({
		"id": 绝界名, "owner": player.id, "attached": dst,
		"counter": 0, "counter_max": 0, "state": 0,
	})
	# 弃 1 张牌由玩家选：押一个询问等回复
	_mod_step = 1
	engine.push(BattleEngine.SHook.new("p_jie_jie_ask", {"player": player.id}, []))
	return URGENT


# ============================================================
# 8207 伏魔境（必杀）：消耗 1 能量 → 目标对手 1 点法术伤害；
# 若因此造成对方士气下降 → 移除我方战绩区 1 星石、你 +1 水晶
# ============================================================
func _p_伏魔境(action: Dictionary) -> int:
	var 校验: int = v_magic_skill(action)
	if 校验 != GConst.GE_SUCCESS:
		return 校验
	var dst: int = int((action.get("dst_ids", []) as Array)[0])
	player.remove_energy(1)
	notice_skill(FU_MO_JING, [dst])
	var 敌: BattlePlayer = engine.p(dst)
	_伏魔待查 = {
		"color": 敌.color if 敌 != null else -1,
		"morale": engine.team_morale[敌.color] if 敌 != null else 0,
	}
	engine.push_harm({
		"src": player.id, "dst": dst, "point": 1,
		"cause": FU_MO_JING, "type": GConst.HarmType.Magic,
	})
	return URGENT


# ============================================================
# 8202 荒神之力：与【结界】系别相同的攻击伤害 +1（所有角色的攻击都算）
# ============================================================
func p_timeline_2_hit(ctx: Dictionary) -> int:
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	var 系别: Array[int] = _结界系别()
	if 系别.is_empty():
		return SUCCESS
	var 卡: GCard = Data.get_card(int(ctx.get("card_id", -1)))
	if 卡 == null or not 卡.is_attack():
		return SUCCESS
	if not 系别.has(卡.element_enum()):
		return SUCCESS
	var harm: Dictionary = ctx.get("harm", {})
	if harm.is_empty() or bool(harm.get("荒神之力已加", false)):
		return SUCCESS
	harm["point"] = int(harm.get("point", 0)) + 1
	harm["荒神之力已加"] = true
	return SUCCESS


# ============================================================
# 8203 荒神祭仪：目标角色主动攻击①，若攻击系别与结界相同 → 你 +1 祭；
# 可再额外移除 3 祭：弃 1 张牌、移除 1 个结界并横置【持续】
# ============================================================
func p_timeline_1(ctx: Dictionary) -> int:
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	var 系别: Array[int] = _结界系别()
	if 系别.is_empty():
		return SUCCESS
	var 卡: GCard = Data.get_card(int(ctx.get("card_id", -1)))
	if 卡 == null or not 卡.is_attack() or not 系别.has(卡.element_enum()):
		return SUCCESS
	if bool(ctx.get("荒神祭仪已结算", false)):
		return SUCCESS
	ctx["荒神祭仪已结算"] = true
	_加祭(1, HUANG_SHEN_JI_YI)
	# 后半段：额外移除 3 祭（默认不发动的可取消询问）
	if player.token_num(JI_SLOT) < 3 or player.hand_cards.is_empty():
		return SUCCESS
	if _t1_step == 0:
		_t1_step = 1
		if not engine.has_reply():
			询问(player.id, HUANG_SHEN_JI_YI, 0, 0, GConst.CardSource.Hand, [], 0, "", [], true,
				0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0,
				GConst.提示原文(HUANG_SHEN_JI_YI, 1))
			return WAIT
	if _t1_step != 1:
		return SUCCESS
	_t1_step = 0
	if not take_skill_reply():
		return SUCCESS
	if not player.remove_token(JI_SLOT, 3):
		return SUCCESS
	# 移除 1 个结界
	var 结界: Array[int] = player.盖牌按标记(JIE_JIE标记)
	if not 结界.is_empty():
		engine.remove_cover(player.id, [int(结界[0])], player.id, HUANG_SHEN_JI_YI)
		engine.to_discard([int(结界[0])], {"owner": player.id, "source": "cover", "cause": HUANG_SHEN_JI_YI})
	player.tap = true
	notice_skill(HUANG_SHEN_JI_YI, [player.id])
	# 弃 1 张牌：问一次（可取消）
	_mod_step = 2
	engine.push(BattleEngine.SHook.new("p_jie_jie_ask", {"player": player.id}, []))
	return URGENT


# ============================================================
# 8205 琉璃境：我方士气下降时，若你已【横置】→【重置】、战绩区 +1 宝石、
# 指定 1 名角色弃 1 张牌【展示】，可把该弃牌面朝上放进盖牌区作为【结界】
# ============================================================
func p_lose_morale(ctx: Dictionary) -> int:
	if not player.tap:
		return SUCCESS
	var dst: int = int(ctx.get("dst", -1))
	var 掉方: BattlePlayer = engine.p(dst)
	if 掉方 == null or 掉方.color != player.color:
		return SUCCESS
	if _琉璃_step != 0 and not engine.has_reply():
		# 等回复期间（_琉璃_step == 1 且有回复）放行到下面 take，否则回复被挡住、技能静默不结算
		return SUCCESS
	_琉璃_step = 1
	if not engine.has_reply():
		询问(player.id, LIU_LI_JING, 0, 0, GConst.CardSource.Hand, [], 0, "", [], true,
			0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0,
			GConst.提示原文(LIU_LI_JING, 1))
		return WAIT
	if not take_skill_reply():
		_琉璃_step = 0
		return SUCCESS
	_琉璃_step = 2
	_mod_step = 3
	player.tap = false
	engine.set_team_gem(player.color, engine.team_gem[player.color] + 1)
	notice_skill(LIU_LI_JING, [])
	engine._broadcast_game()
	engine.push(BattleEngine.SHook.new("p_jie_jie_ask", {"player": player.id}, []))
	return URGENT


# ============================================================
# 8206 绝界（场卡）：结界为 0 时移除；拥有者回合结束前结界师移除 1 个结界；
# 拥有者攻击行动结束时，结界师 +1 祭、拥有者把 1 个结界加入手牌
# ============================================================
func p_action_end(ctx: Dictionary) -> int:
	var 拥有者: int = _绝界拥有者()
	if 拥有者 < 0 or int(ctx.get("player", -1)) != 拥有者:
		return SUCCESS
	if str(ctx.get("kind", "")) != "attack":
		return SUCCESS
	if not player.remove_token(JI_SLOT, 0):
		return SUCCESS
	_加祭(1, JUE_JIE)
	var 结界: Array[int] = player.盖牌按标记(JIE_JIE标记)
	if 结界.is_empty():
		return SUCCESS
	var 取: int = int(结界[0])
	engine.remove_cover(player.id, [取], player.id, JUE_JIE)
	var 拥有: BattlePlayer = engine.p(拥有者)
	if 拥有 != null:
		拥有.add_hand_cards([取])
	notice_skill(JUE_JIE, [拥有者])
	engine._broadcast_game()
	return URGENT


## 拥有者的回合结束：结界师移除 1 个结界；若结界已经为 0 → 破散（横置 + 移除绝界）
func p_turn_end(ctx: Dictionary) -> int:
	var 拥有者: int = _绝界拥有者()
	if 拥有者 < 0:
		return SUCCESS
	if int(ctx.get("player", -1)) != 拥有者:
		return SUCCESS
	var 结界: Array[int] = player.盖牌按标记(JIE_JIE标记)
	if not 结界.is_empty():
		var 取: int = int(结界[0])
		engine.remove_cover(player.id, [取], player.id, JUE_JIE)
		engine.to_discard([取], {"owner": player.id, "source": "cover", "cause": JUE_JIE})
		engine._broadcast_game()
		var 余: Array[int] = player.盖牌按标记(JIE_JIE标记)
		if not 余.is_empty():
			return SUCCESS
	return _检查绝界破散()


## 结界为 0 时：结界师【横置】，移除【绝界】
func _检查绝界破散() -> int:
	if _绝界拥有者() < 0:
		return SUCCESS
	var 结界: Array[int] = player.盖牌按标记(JIE_JIE标记)
	if not 结界.is_empty():
		return SUCCESS
	# 拥有者回合结束前移除 1 个结界：这里再补一次（没有结界就直接破散）
	player.tap = true
	engine.移除场卡(绝界名)
	notice_skill(JUE_JIE, [player.id])
	return SUCCESS


# ============================================================
# 绝界：拥有者的基础效果无法触发（引擎在触发前问这个钩子）
# ============================================================
func 基础效果被禁止(pid: int) -> bool:
	return engine.玩家有场卡(pid, 绝界名)


# ============================================================
# 内部
# ============================================================
## 【绝界】的拥有者（没在场卡时 -1）
func _绝界拥有者() -> int:
	if not engine.有场卡(绝界名):
		return -1
	return int(engine.取场卡(绝界名).get("attached", -1))


## 场上的【结界】牌（盖牌区面朝上、标记为结界）
func _结界() -> Array[int]:
	return player.盖牌按标记(JIE_JIE标记)


## 结界里出现的系别（去重）
func _结界系别() -> Array[int]:
	var out: Array[int] = []
	for cid: int in _结界():
		var 卡: GCard = Data.get_card(cid)
		if 卡 == null:
			continue
		var 系: int = 卡.element_enum()
		if 系 > 0 and not out.has(系):
			out.append(系)
	return out


## 加【祭】并处理【伏魔境】的「每当你【祭】增加时」响应：先加，再问是否发动 8207
func _加祭(n: int, cause: int) -> void:
	var 实际: int = player.add_token(JI_SLOT, n)
	if 实际 <= 0:
		return
	engine._broadcast_game()
	# 【伏魔境】的响应交给钩子：这里只压一个询问钩子（可等待），避免在别的技能中间直接问
	_伏魔可发动 = player.get_energy() >= 1 and not enemy_ids().is_empty()
	if _伏魔可发动:
		_mod_step = 6
		engine.push(BattleEngine.SHook.new("p_jie_jie_ask", {"player": player.id, "加祭": cause}, []))


# ============================================================
# 统一的「小段询问」钩子：禁魔境 / 荒神祭仪 / 琉璃境 / 伏魔境 的选牌选人都在这里
# ============================================================
var _mod_step: int = 0

func p_jie_jie_ask(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	match _mod_step:
		1:  # 禁魔境：弃 1 张牌
			if player.hand_cards.is_empty():
				_mod_step = 0
				return SUCCESS
			if not engine.has_reply():
				询问(player.id, JIN_MO_JING, 1, 0, GConst.CardSource.Hand, [], 1, "", [], true,
					0, player.id, [], 1, {}, 0, 0, false, [], true, -1, 0,
					GConst.提示原文(JIN_MO_JING, 1))
				return WAIT
			var r: Dictionary = take_skill_reply_full()
			var cards: Array = r.get("card_ids", [])
			_mod_step = 0
			if not cards.is_empty() and player.有手牌(int(cards[0])):
				var cid: int = int(cards[0])
				engine.take_from_hand(player.id, [cid], false)
				engine.to_discard([cid], {"owner": player.id, "source": "hand", "cause": JIN_MO_JING})
				engine._log_discard(player.id, [cid], false)
			return SUCCESS
		2:  # 荒神祭仪 / 琉璃境：弃 1 张牌
			if player.hand_cards.is_empty():
				_mod_step = 0
				return SUCCESS
			if not engine.has_reply():
				询问(player.id, HUANG_SHEN_JI_YI, 1, 0, GConst.CardSource.Hand, [], 1, "", [], true,
					0, player.id, [], 1, {}, 0, 0, false, [], true, -1, 0,
					"弃 1 张牌")
				return WAIT
			var r2: Dictionary = take_skill_reply_full()
			var cards2: Array = r2.get("card_ids", [])
			_mod_step = 0
			if cards2.is_empty() or not player.有手牌(int(cards2[0])):
				return SUCCESS
			var cid2: int = int(cards2[0])
			engine.take_from_hand(player.id, [cid2], false)
			engine.to_discard([cid2], {"owner": player.id, "source": "hand", "cause": HUANG_SHEN_JI_YI})
			engine._log_discard(player.id, [cid2], false)
			return SUCCESS
		3:  # 琉璃境：指定 1 名角色弃 1 张牌，弃牌可放进盖牌区作为结界
			if not engine.has_reply():
				询问(player.id, LIU_LI_JING, 0, 1, GConst.CardSource.Hand, [], 0, "", [], true,
					0, -1, _全体角色(), -1, {}, 0, 0, false, [], true, -1, 0,
					GConst.提示原文(LIU_LI_JING, 2))
				return WAIT
			var r3: Dictionary = take_skill_reply_full()
			var ds: Array = r3.get("dst_ids", [])
			_mod_step = 0
			if ds.size() != 1:
				return SUCCESS
			var tgt: BattlePlayer = engine.p(int(ds[0]))
			if tgt == null or tgt.hand_cards.is_empty():
				return SUCCESS
			_琉璃_step = 3
			_琉璃弃牌人 = tgt.id
			_mod_step = 4
			engine.push(BattleEngine.SHook.new("p_jie_jie_ask", {"player": player.id}, []))
			return URGENT
		4:  # 琉璃境：目标自己选 1 张牌弃（展示）
			var tgt4: BattlePlayer = engine.p(_琉璃弃牌人)
			if tgt4 == null or tgt4.hand_cards.is_empty():
				_mod_step = 0
				return SUCCESS
			if not engine.has_reply():
				询问(tgt4.id, LIU_LI_JING, 1, 0, GConst.CardSource.Hand, [], 1, "", [], false,
					0, player.id, [], 1, {}, 0, 0, false, [], true, -1, 0,
					GConst.提示原文(LIU_LI_JING, 3))
				return WAIT
			var r4: Dictionary = take_skill_reply_full()
			var cards4: Array = r4.get("card_ids", [])
			_mod_step = 0
			if cards4.is_empty() or not tgt4.有手牌(int(cards4[0])):
				return SUCCESS
			var cid4: int = int(cards4[0])
			engine.broadcast(GConst.Msg.Card, {
				"type": GConst.CardMsgType.Show, "src_id": tgt4.id, "dst_id": tgt4.id,
				"card_ids": [cid4], "is_real": true,
			})
			engine.take_from_hand(tgt4.id, [cid4], false)
			engine._log_discard(tgt4.id, [cid4], false)
			# 可把这 1 张弃牌面朝上放进盖牌区作为【结界】
			if player.can_add_cover_cards(1):
				_琉璃待放 = cid4
				_琉璃_step = 4
				_mod_step = 5
				engine.push(BattleEngine.SHook.new("p_jie_jie_ask", {"player": player.id}, []))
				return URGENT
			engine.to_discard([cid4], {"owner": tgt4.id, "source": "hand", "cause": LIU_LI_JING})
			return SUCCESS
		5:  # 琉璃境：问要不要把该弃牌当作【结界】
			if not engine.has_reply():
				询问(player.id, LIU_LI_JING, 0, 0, GConst.CardSource.Hand, [], 0, "", [], true,
					0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0,
					GConst.提示原文(LIU_LI_JING, 4))
				return WAIT
			var 要: bool = take_skill_reply()
			_mod_step = 0
			_琉璃_step = 0
			if 要 and _琉璃待放 > 0 and player.can_add_cover_cards(1):
				engine.add_cover(player.id, [_琉璃待放], player.id, LIU_LI_JING, true, JIE_JIE标记)
				_琉璃待放 = -1
				return URGENT
			if _琉璃待放 > 0:
				# 这张牌是目标角色弃的：owner 必须写他（否则【渗蚀】等弃牌触发的伤害会打到结界师）
				engine.to_discard([_琉璃待放], {"owner": _琉璃弃牌人 if _琉璃弃牌人 > 0 else player.id,
					"source": "hand", "cause": LIU_LI_JING})
				_琉璃待放 = -1
			return SUCCESS
		6:  # 伏魔境：祭增加时，问是否发动（消耗 1 点能量）
			if not engine.has_reply():
				询问(player.id, FU_MO_JING, 0, 0, GConst.CardSource.Hand, [], 0, "", [], true,
					0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0,
					GConst.提示原文(FU_MO_JING, 1))
				return WAIT
			if not take_skill_reply():
				_mod_step = 0
				return SUCCESS
			_mod_step = 7
			engine.push(BattleEngine.SHook.new("p_jie_jie_ask", {"player": player.id}, []))
			return URGENT
		7:  # 伏魔境：选目标对手
			if not engine.has_reply():
				询问(player.id, FU_MO_JING, 0, 1, GConst.CardSource.Hand, [], 0, "", [], true,
					0, -1, enemy_ids(), -1, {}, 0, 0, false, [], true, -1, 0,
					GConst.提示原文(FU_MO_JING, 2))
				return WAIT
			var r7: Dictionary = take_skill_reply_full()
			var ds7: Array = r7.get("dst_ids", [])
			_mod_step = 0
			if ds7.size() != 1:
				return SUCCESS
			var dst7: int = int(ds7[0])
			var 敌7: BattlePlayer = engine.p(dst7)
			if 敌7 == null or player.get_energy() < 1:
				return SUCCESS
			player.remove_energy(1)
			notice_skill(FU_MO_JING, [dst7])
			_伏魔待查 = {"color": 敌7.color, "morale": engine.team_morale[敌7.color]}
			engine.push_harm({
				"src": player.id, "dst": dst7, "point": 1,
				"cause": FU_MO_JING, "type": GConst.HarmType.Magic,
			})
			return URGENT
	return SUCCESS

var _琉璃弃牌人: int = -1
var _琉璃待放: int = -1
var _伏魔可发动: bool = false


# ============================================================
# 【伏魔境】：祭增加时的响应（由 _加祭 压进来的钩子）
# ============================================================
func p_harm_end(ctx: Dictionary) -> int:
	# 伤害结算完：伏魔境「若因此造成对方士气下降」的后续（士气在伤害结算里已经掉过）
	var harm: Dictionary = ctx.get("harm", {})
	if _伏魔待查.is_empty():
		return SUCCESS
	if int(harm.get("cause", 0)) != FU_MO_JING:
		return SUCCESS
	var color: int = int(_伏魔待查.get("color", -1))
	var 前: int = int(_伏魔待查.get("morale", 0))
	_伏魔待查 = {}
	if color < 0 or engine.team_morale[color] >= 前:
		return SUCCESS
	# 对方士气下降了：移除我方战绩区 1 星石 → 你 +1 水晶
	if engine.team_gem[player.color] > 0:
		engine.set_team_gem(player.color, engine.team_gem[player.color] - 1)
	player.set_crystal(player.crystal + 1)
	notice_skill(FU_MO_JING, [])
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 小工具
# ============================================================
func _全体角色() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		if engine.p(pid) != null:
			out.append(pid)
	return out
