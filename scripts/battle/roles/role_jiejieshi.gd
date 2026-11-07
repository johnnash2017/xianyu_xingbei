extends BattleRole
## 结界师（82）：结界仪式 / 荒神之力 / 荒神祭仪 / 禁魔境 / 琉璃境 / 绝界 / 伏魔境
##
## 区域与标记：
## - 【祭】＝0 号指示物（角色表 0:祭:3，上限 3），统一用 player.add_token(0) / remove_token(0)。
## - 【结界】＝盖牌区**面朝上**的牌（角色表盖牌槽 2；指示物第 2 格 2:结界:2 只是给这个槽起名）：
##   放进去用 engine.add_cover(..., open = true)，她的盖牌区里的牌都当【结界】。
## - 【绝界】＝场卡（F1）：owner＝结界师，attached＝拥有它的角色；拥有者的基础效果无法触发。
##
## 口径（逐条对照 79 以下的参考角色）：
## 1. 【荒神之力】原文「所有与【结界】系别相同的攻击伤害额外 +1」：主动攻击与反击都算，
##    同系多张结界也只 +1（写在 harm.point 上并打标记防重复，同 4203【法术剥离】那类加伤）。
## 2. 【荒神祭仪】对所有角色的**主动攻击**生效：同系先 +1【祭】（纯收益，不问）；
##    再问要不要额外移除 3【祭】—— 是则：弃 1 张牌（SRequestDiscard，强制、超时按手牌顺序补弃）
##    → 由她选 1 个【结界】移除 → 【横置】。移除哪个结界必须让她选（系别影响后续判定）；
##    横置放在所有询问之后（技能维护约定 §19：改形态别放在还要问玩家的询问之前）。
## 3. 【禁魔境】把【绝界】转移 / 放置到目标角色前；「你弃 1 张牌」是强制，走 SRequestDiscard。
## 4. 【琉璃境】目标弃 1 张牌【展示】参照兽灵【兽魂警戒】3604：不可取消、超时按手牌顺序补弃、
##    先公开（take_from_hand 的「已展示」）再决定去向；之后可把这 1 张面朝上放进盖牌区当【结界】。
## 5. 【绝界】灭界破散在**每次结界减少后**判（荒神祭仪 / 白二羯磨 / 拥有者回合结束）：
##    结界为 0 时她【横置】并移除【绝界】。白二羯磨与回合结束移除哪个结界都由她选。
## 6. 【伏魔境】是「【祭】增加时」的响应（必杀技，耗 1 水晶），**不进技能栏**；
##    伤害若造成对方士气下降 → 移除我方战绩区 1 星石、她 +1 水晶。

const JIE_JIE_YI_SHI: int = 8201
const HUANG_SHEN_ZHI_LI: int = 8202
const HUANG_SHEN_JI_YI: int = 8203
const JIN_MO_JING: int = 8204
const LIU_LI_JING: int = 8205
const JUE_JIE: int = 8206
const FU_MO_JING: int = 8207

const JI_SLOT: int = 0
const 绝界名: String = "绝界"

## 小段询问钩子 p_jie_jie_ask 的步骤（琉璃境沿用 3/4/5，测试用例按老编号驱动）
const 步_琉璃选人: int = 3
const 步_琉璃目标弃牌: int = 4
const 步_琉璃问放置: int = 5
const 步_荒神问额外: int = 20
const 步_荒神弃牌: int = 21
const 步_荒神选结界: int = 22
const 步_绝界给结界: int = 30
const 步_绝界回合结束: int = 31

var _mod_step: int = 0
var _琉璃_step: int = 0
var _琉璃弃牌人: int = -1
var _琉璃待放: int = -1
## 【伏魔境】的询问步骤（0＝不在问 / 1＝等「是否发动」/ 2＝等选目标）。
## 单独用一份状态，不和 _mod_step 抢：祭增加是随时可能发生的，压进来的钩子
## 不能把正在跑的荒神祭仪 / 绝界流程的步骤改掉。
var _伏魔步: int = 0
## 【伏魔境】：记下最近一次发动时对手队伍的士气，用于「若因此造成对方士气下降」的判定
var _伏魔待查: Dictionary = {}


# ============================================================
# 技能栏（伏魔境是响应，不进技能栏）
# ============================================================
func available_skills() -> Array:
	var 全体: Array[int] = _全体角色()
	var 手牌数: int = player.hand_cards.size()
	var 祭: int = player.token_num(JI_SLOT)
	return [
		{
			"type": GConst.ActionType.MagicSkill,
			"id": JIE_JIE_YI_SHI,
			"need_card": 2,
			"cards": player.hand_cards.duplicate(),
			"enabled": 手牌数 >= 2 and player.cover_space() >= 2,
		},
		{
			"type": GConst.ActionType.MagicSkill,
			"id": JIN_MO_JING,
			"need_target": 1,
			"targets": 全体,
			"enabled": 祭 >= 1 and not 全体.is_empty(),
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
			if player.token_num(JI_SLOT) < 1:
				return GConst.GE_INVALID_ACTION
			var dsts: Array = action.get("dst_ids", [])
			if dsts.size() != 1 or engine.p(int(dsts[0])) == null:
				return GConst.GE_INVALID_ACTION
			return GConst.GE_SUCCESS
	return GConst.GE_INVALID_ACTION


func p_magic_skill(action: Dictionary) -> int:
	match int(action.get("action_id", 0)):
		JIE_JIE_YI_SHI:
			return _p_结界仪式(action)
		JIN_MO_JING:
			return _p_禁魔境(action)
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
	var 放: Array[int] = []
	for c: Variant in cards:
		var cid: int = player.取出实例(player.hand_cards, int(c))
		if cid >= 0:
			放.append(cid)
	if 放.is_empty():
		return SUCCESS
	engine.add_cover(player.id, 放, player.id, JIE_JIE_YI_SHI, true)
	_加祭(1, JIE_JIE_YI_SHI)
	return URGENT


# ============================================================
# 8204 禁魔境：移除 1 祭 → 把【绝界】转移 / 放置到目标角色前 → 你弃 1 张牌（强制）
# ============================================================
func _p_禁魔境(action: Dictionary) -> int:
	var 校验: int = v_magic_skill(action)
	if 校验 != GConst.GE_SUCCESS:
		return 校验
	var dst: int = int((action.get("dst_ids", []) as Array)[0])
	player.remove_token(JI_SLOT, 1)
	notice_skill(JIN_MO_JING, [dst])
	# 同一张【绝界】只存在一份：加场卡会按 id 顶掉旧的（转移＝换个 attached / 重新放置）
	engine.加场卡({
		"id": 绝界名, "owner": player.id, "attached": dst,
		"counter": 0, "counter_max": 0, "state": 0,
	})
	engine._broadcast_game()
	# 「你弃 1 张牌」是强制：走 SRequestDiscard，超时按手牌顺序补弃（技能维护约定 §16）
	engine.push(BattleEngine.SRequestDiscard.new(player.id, 1, 0, JIN_MO_JING))
	return URGENT


# ============================================================
# 8202 荒神之力：与【结界】系别相同的攻击伤害 +1（主动攻击与反击都算）
# ============================================================
func p_timeline_2_hit(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if harm.is_empty() or bool(harm.get("荒神之力已加", false)):
		return SUCCESS
	var 卡: GCard = Data.get_card(int(ctx.get("card_id", -1)))
	if 卡 == null or not 卡.is_attack():
		return SUCCESS
	var 系别: Array[int] = _结界系别()
	if 系别.is_empty() or not 系别.has(卡.element_enum()):
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
	notice_skill(HUANG_SHEN_JI_YI, [player.id])
	_加祭(1, HUANG_SHEN_JI_YI)
	# 后半段是可选：祭够 3 点、手里有牌才问（取消＝不发动后半段）
	if player.token_num(JI_SLOT) < 3 or player.hand_cards.is_empty():
		return SUCCESS
	_mod_step = 步_荒神问额外
	engine.push(BattleEngine.SHook.new("p_jie_jie_ask", {"player": player.id}, []))
	return URGENT


# ============================================================
# 8205 琉璃境：我方士气下降时，若你已【横置】→【重置】、战绩区 +1 宝石、
# 指定 1 名角色弃 1 张牌【展示】，可把该弃牌面朝上放进盖牌区作为【结界】
# ============================================================
func p_lose_morale(ctx: Dictionary) -> int:
	if not player.tap:
		return SUCCESS
	var 掉方: BattlePlayer = engine.p(int(ctx.get("dst", -1)))
	if 掉方 == null or 掉方.color != player.color:
		return SUCCESS
	if _琉璃_step == 0:
		_琉璃_step = 1
		if not engine.has_reply():
			询问(player.id, LIU_LI_JING, 0, 0, GConst.CardSource.Hand, [], 0, "", [], true,
				0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0,
				GConst.提示原文(LIU_LI_JING, 1))
			return WAIT
	if _琉璃_step != 1 or not engine.has_reply():
		return SUCCESS
	if not take_skill_reply():
		_琉璃_step = 0
		return SUCCESS
	_琉璃_step = 2
	player.tap = false
	engine.set_team_gem(player.color, engine.team_gem[player.color] + 1)
	notice_skill(LIU_LI_JING, [])
	engine._broadcast_game()
	_mod_step = 步_琉璃选人
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
	notice_skill(JUE_JIE, [拥有者])
	_加祭(1, JUE_JIE)
	if _结界().is_empty():
		return SUCCESS
	_mod_step = 步_绝界给结界
	engine.push(BattleEngine.SHook.new("p_jie_jie_ask", {"player": player.id}, []))
	return URGENT


## 拥有者的回合结束：结界师移除 1 个结界；结界已经为 0 → 破散（横置 + 移除绝界）
func p_turn_end(ctx: Dictionary) -> int:
	var 拥有者: int = _绝界拥有者()
	if 拥有者 < 0 or int(ctx.get("player", -1)) != 拥有者:
		return SUCCESS
	if _结界().is_empty():
		return _检查绝界破散()
	_mod_step = 步_绝界回合结束
	engine.push(BattleEngine.SHook.new("p_jie_jie_ask", {"player": player.id}, []))
	return URGENT


## 结界为 0 时：结界师【横置】，移除【绝界】
func _检查绝界破散() -> int:
	if _绝界拥有者() < 0:
		return SUCCESS
	if not _结界().is_empty():
		return SUCCESS
	player.tap = true
	engine.移除场卡(绝界名)
	notice_skill(JUE_JIE, [player.id])
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 绝界：拥有者的基础效果无法触发（引擎在触发前问这个钩子）
# ============================================================
func 基础效果被禁止(pid: int) -> bool:
	return engine.玩家有场卡(pid, 绝界名)


# ============================================================
# 统一的「小段询问」钩子：琉璃境 / 伏魔境 / 荒神祭仪后半段 / 绝界
# ============================================================
func p_jie_jie_ask(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	match _mod_step:
		步_琉璃选人:
			return _琉璃_选人()
		步_琉璃目标弃牌:
			return _琉璃_目标弃牌(ctx)
		步_琉璃问放置:
			return _琉璃_问放置()
		步_荒神问额外:
			return _荒神_问额外()
		步_荒神弃牌:
			# 强制弃牌的状态已经跑完，接着选要移除的结界
			_mod_step = 步_荒神选结界
			if _结界().is_empty():
				player.tap = true
				_mod_step = 0
				return _检查绝界破散()
			_问选结界(HUANG_SHEN_JI_YI)
			return WAIT
		步_荒神选结界:
			var cid: int = _取询问盖牌()
			_mod_step = 0
			if cid >= 0:
				engine.remove_cover(player.id, [cid], player.id, HUANG_SHEN_JI_YI)
				engine.to_discard([cid], {"owner": player.id, "source": "cover",
					"cause": HUANG_SHEN_JI_YI, "face_up": true})
			player.tap = true
			notice_skill(HUANG_SHEN_JI_YI, [player.id])
			engine._broadcast_game()
			return _检查绝界破散()
		步_绝界给结界:
			if not engine.has_reply():
				_问选结界(JUE_JIE)
				return WAIT
			var 给: int = _取询问盖牌()
			_mod_step = 0
			if 给 < 0:
				return SUCCESS
			var 拥有: int = _绝界拥有者()
			engine.remove_cover(player.id, [给], player.id, JUE_JIE)
			var 拥有者: BattlePlayer = engine.p(拥有)
			if 拥有者 != null:
				拥有者.add_hand_cards([给])
			notice_skill(JUE_JIE, [拥有])
			engine._broadcast_game()
			return _检查绝界破散()
		步_绝界回合结束:
			if not engine.has_reply():
				_问选结界(JUE_JIE)
				return WAIT
			var 移: int = _取询问盖牌()
			_mod_step = 0
			if 移 >= 0:
				engine.remove_cover(player.id, [移], player.id, JUE_JIE)
				engine.to_discard([移], {"owner": player.id, "source": "cover",
					"cause": JUE_JIE, "face_up": true})
				engine._broadcast_game()
			return _检查绝界破散()
	return SUCCESS


## 琉璃境：指定 1 名有手牌的角色（没有这样的人就整段跳过）
func _琉璃_选人() -> int:
	var 有牌: Array[int] = _有手牌角色()
	if 有牌.is_empty():
		_mod_step = 0
		_琉璃_step = 0
		return SUCCESS
	if not engine.has_reply():
		询问(player.id, LIU_LI_JING, 0, 1, GConst.CardSource.Hand, [], 0, "", [], true,
			0, -1, 有牌, -1, {}, 0, 0, false, [], true, -1, 0,
			GConst.提示原文(LIU_LI_JING, 2))
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	var ds: Array = r.get("dst_ids", [])
	_mod_step = 0
	if ds.size() != 1 or not 有牌.has(int(ds[0])):
		_琉璃_step = 0
		return SUCCESS
	_琉璃弃牌人 = int(ds[0])
	_mod_step = 步_琉璃目标弃牌
	return _琉璃_目标弃牌({})


## 琉璃境：目标弃 1 张牌【展示】（不可取消，超时按手牌顺序补一张）
func _琉璃_目标弃牌(_ctx: Dictionary) -> int:
	var tgt: BattlePlayer = engine.p(_琉璃弃牌人)
	if tgt == null or tgt.hand_cards.is_empty():
		_琉璃弃牌人 = -1
		_mod_step = 0
		_琉璃_step = 0
		return SUCCESS
	if not engine.has_reply():
		询问(tgt.id, LIU_LI_JING, 1, 0, GConst.CardSource.Hand, [], 1, "", [], false,
			0, player.id, [], 1, {}, 0, 0, false, [], true, -1, 0,
			GConst.提示原文(LIU_LI_JING, 3))
		return WAIT
	var cid: int = _取回复手牌(tgt, take_skill_reply_full())
	if cid < 0:
		_琉璃弃牌人 = -1
		_mod_step = 0
		_琉璃_step = 0
		return SUCCESS
	# 【展示】：先公开，再决定去向（作为结界 / 进弃牌堆）
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": tgt.id, "dst_id": tgt.id,
		"card_ids": [cid], "is_real": true,
	})
	engine.take_from_hand(tgt.id, [cid], true)
	_琉璃待放 = cid
	if player.can_add_cover_cards(1):
		_mod_step = 步_琉璃问放置
		return _琉璃_问放置()
	_琉璃_进弃牌堆()
	_琉璃弃牌人 = -1
	_琉璃_step = 0
	return SUCCESS


## 琉璃境：问要不要把这 1 张弃牌面朝上放进盖牌区当【结界】
func _琉璃_问放置() -> int:
	if not engine.has_reply():
		询问(player.id, LIU_LI_JING, 0, 0, GConst.CardSource.Hand, [], 0, "", [], true,
			0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0,
			GConst.提示原文(LIU_LI_JING, 4))
		return WAIT
	var 要: bool = take_skill_reply()
	_mod_step = 0
	_琉璃_step = 0
	if 要 and _琉璃待放 >= 0 and player.can_add_cover_cards(1):
		engine.add_cover(player.id, [_琉璃待放], player.id, LIU_LI_JING, true)
		_琉璃待放 = -1
		_琉璃弃牌人 = -1
		return URGENT
	# 不进盖牌区：进弃牌堆时 owner 还要用真正的弃牌人，重置放在这之后
	_琉璃_进弃牌堆()
	_琉璃弃牌人 = -1
	return SUCCESS


## 琉璃境：那张弃牌不进盖牌区时进弃牌堆（owner 必须是真正弃牌的人）
func _琉璃_进弃牌堆() -> void:
	if _琉璃待放 < 0:
		return
	engine.to_discard([_琉璃待放], {
		"owner": _琉璃弃牌人 if _琉璃弃牌人 >= 0 else player.id,
		"source": "hand", "cause": LIU_LI_JING,
	})
	_琉璃待放 = -1


## 伏魔境：祭增加时的响应（必杀技，耗 1 水晶）——
## 先问是否发动，再选 1 名对手，扣能量后造成 1 点法术伤害；士气下降的后续在 p_harm_end。
## 单独一个钩子（不走 p_jie_jie_ask 的 _mod_step）：祭增加随时可能发生，
## 不能把正在跑的荒神祭仪 / 绝界流程的步骤改掉。
func p_fu_mo_ask(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	# ① 第一次进来：先问「是否发动」
	if _伏魔步 == 0:
		if player.get_energy() < 1 or enemy_ids().is_empty():
			return SUCCESS
		_伏魔步 = 1
		if not engine.has_reply():
			询问(player.id, FU_MO_JING, 0, 0, GConst.CardSource.Hand, [], 0, "", [], true,
				0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0,
				GConst.提示原文(FU_MO_JING, 1))
			return WAIT
	# ② 等「是否发动」的回复：不发动＝整段结束
	if _伏魔步 == 1:
		if not engine.has_reply():
			return SUCCESS
		if not take_skill_reply():
			_伏魔步 = 0
			return SUCCESS
		var 对手: Array[int] = enemy_ids()
		if 对手.is_empty() or player.get_energy() < 1:
			_伏魔步 = 0
			return SUCCESS
		_伏魔步 = 2
		询问(player.id, FU_MO_JING, 0, 1, GConst.CardSource.Hand, [], 0, "", [], true,
			0, -1, 对手, -1, {}, 0, 0, false, [], true, -1, 0,
			GConst.提示原文(FU_MO_JING, 2))
		return WAIT
	# ③ 等选目标的回复：扣 1 水晶 → 1 点法术伤害
	if _伏魔步 != 2 or not engine.has_reply():
		return SUCCESS
	var r: Dictionary = take_skill_reply_full()
	var ds: Array = r.get("dst_ids", [])
	_伏魔步 = 0
	if ds.size() != 1 or not enemy_ids().has(int(ds[0])):
		return SUCCESS
	var dst: int = int(ds[0])
	var 敌: BattlePlayer = engine.p(dst)
	if 敌 == null or player.get_energy() < 1:
		return SUCCESS
	player.remove_energy(1)
	notice_skill(FU_MO_JING, [dst])
	_伏魔待查 = {"color": 敌.color, "morale": engine.team_morale[敌.color]}
	engine.push_harm({
		"src": player.id, "dst": dst, "point": 1,
		"cause": FU_MO_JING, "type": GConst.HarmType.Magic,
	})
	return URGENT


## 荒神祭仪后半段：问要不要额外移除 3 祭
func _荒神_问额外() -> int:
	if player.token_num(JI_SLOT) < 3:
		_mod_step = 0
		return SUCCESS
	if not engine.has_reply():
		询问(player.id, HUANG_SHEN_JI_YI, 0, 0, GConst.CardSource.Hand, [], 0, "", [], true,
			0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0,
			GConst.提示原文(HUANG_SHEN_JI_YI, 1))
		return WAIT
	if not take_skill_reply():
		_mod_step = 0
		return SUCCESS
	if not player.remove_token(JI_SLOT, 3):
		_mod_step = 0
		return SUCCESS
	notice_skill(HUANG_SHEN_JI_YI, [player.id])
	engine._broadcast_game()
	# 顺序照原文：先弃 1 张牌，再移除结界、横置。弃牌走状态，回来接着选结界
	if player.hand_cards.is_empty():
		_mod_step = 步_荒神选结界
		_问选结界(HUANG_SHEN_JI_YI)
		return WAIT
	_mod_step = 步_荒神弃牌
	engine.push(BattleEngine.SRequestDiscard.new(player.id, 1, 0, HUANG_SHEN_JI_YI))
	return URGENT


# ============================================================
# 内部
# ============================================================
## 【绝界】的拥有者（没在场卡时 -1）
func _绝界拥有者() -> int:
	if not engine.有场卡(绝界名):
		return -1
	return int(engine.取场卡(绝界名).get("attached", -1))


## 她的【结界】牌＝盖牌区里的全部牌（面朝上）
func _结界() -> Array[int]:
	return player.cover_cards.duplicate()


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


## 让她从自己的【结界】里选 1 张（不可取消，超时按盖牌顺序补一张）
func _问选结界(技能号: int) -> void:
	询问(player.id, 技能号, 1, 0, GConst.CardSource.Cover, [], 0, "", [], false,
		0, -1, [], 1, {}, 0, 0, false, [], true, -1, 0)


## 取回复里选中的那张盖牌；空回复 / 超时按盖牌顺序补一张（约定 §16）
func _取询问盖牌() -> int:
	var r: Dictionary = take_skill_reply_full()
	for c: Variant in r.get("card_ids", []):
		if player.有盖牌(int(c)):
			return int(c)
	for cid: int in player.cover_cards:
		return cid
	return -1


## 取回复里选中的那张手牌；空回复 / 超时按手牌顺序补一张（约定 §16）
func _取回复手牌(tgt: BattlePlayer, r: Dictionary) -> int:
	for c: Variant in r.get("card_ids", []):
		if tgt.有手牌(int(c)):
			return int(c)
	for cid: int in tgt.hand_cards:
		return cid
	return -1


## 加【祭】并处理【伏魔境】的「每当你【祭】增加时」响应：先加，再压一个询问钩子
func _加祭(n: int, cause: int) -> void:
	var 实际: int = player.add_token(JI_SLOT, n)
	if 实际 <= 0:
		return
	engine._broadcast_game()
	if player.get_energy() >= 1 and not enemy_ids().is_empty():
		engine.push(BattleEngine.SHook.new("p_fu_mo_ask",
			{"player": player.id, "加祭": cause}, []))


# ============================================================
# 【伏魔境】：伤害结算完查「对方士气是否下降」
# ============================================================
func p_harm_end(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if _伏魔待查.is_empty() or int(harm.get("cause", 0)) != FU_MO_JING:
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


func _有手牌角色() -> Array[int]:
	var out: Array[int] = []
	for pid: int in _全体角色():
		var p0: BattlePlayer = engine.p(pid)
		if p0 != null and not p0.hand_cards.is_empty():
			out.append(pid)
	return out
