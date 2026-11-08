extends BattleRole
## 结界师（82）：结界仪式 / 荒神之力 / 荒神祭仪 / 禁魔境 / 琉璃境 / 灭界破散 / 白二羯磨 / 虚空境 / 伏魔境
##
## 区域与标记：
## - 【祭】= 0 号指示物（角色表 0:祭:3），统一用 player.add_token(0) / remove_token(0)。
## - 【结界】= 盖牌区里**面朝上**的牌（角色表盖牌槽 2；指示物 2:结界:2 只是给这个槽起名）：
##   放进去用 engine.add_cover(..., open = true)，她盖牌区里的牌都当【结界】。
## - 【绝界】= 场卡：owner = 结界师，attached = 拥有它的角色；三条专属技（8206 / 8208 / 8209）
##   都只认「绝界挂在谁面前」，不是认结界师自己（见 _绝界持有者）。
##
## 口径与参考（参考对象都取 79 以下的角色）：
## 1. 分步流程用**本次钩子的 ctx** 记步骤，不在角色身上放 _mod_step：同一次钩子重入拿同一份 ctx，
##    不同钩子（士气下降 / 攻击宣告 / 行动结束）天然各走各的，不会互相改掉步骤。
##    写法照剑之子【风之剑】10802、圣庭检察士【狂信徒】3901。
## 2. 8201 放牌进盖牌区照魔弓【充能】2604：take_from_hand -> add_cover；牌是【展示】的，
##    take_from_hand(..., true) 会压「展示手牌」钩子，压了钩子就 return URGENT，别让行动结束响应插到前面。
## 3. 8202 在 p_before_attack 改 harm.point：后面的应战提示、荒神祭仪的询问都拿得到加后的伤害
##    （同游击士【元素射击】3802 在宣告阶段改点数的口径）。
## 4. 8203 是响应：先问是否发动，确认才 +1【祭】；额外移除 3 点【祭】、弃 1 张牌、移除 1 个【结界】
##    合成**一次**询问：直接传「手牌 hand_need=1 张 + 盖牌 cover_need=1 张」，
##    取消＝不额外移除。结算顺序固定：移除 3 祭 → 弃手牌 → 移除结界 → 横置。
## 5. 8204 摸场卡照圣庭检察士【狂信徒】3901：engine.加场卡 写 id / owner / attached。
## 6. 8205 是 p_lose_morale 里的响应，照天使【神之庇护】706 直接在本钩子里询问；
##    让别人弃牌走 engine.ask_respond(RespondType.Discard)（矜贵之女【友情羁绊】7805），
##    不用技能询问把发动者的整段说明丢给被弃牌的人。
##    lose_morale() 是同步调用（合成星杯 / 逆反居合斩 / 暗月诅咒），钩子里不能等玩家输入，
##    引擎在那条路径的 ctx 里打了 sync 标记，这里直接放行（与 706 只处理可等待路径同一口径）。
## 7. 8207 照战斗法师【魔力熵增】4104：伤害前记两队士气，p_harm_end 里比最终目标那一队。
##    「移除我方【战绩区】1 星石」按 10802【风之剑】/ 7804【强予愿行】的口径由玩家选宝石/水晶，
##    两个选项始终下发、做不了的置灰。
## 8. 8206 / 8208 的「选 1 个【结界】」都由结界师选：盖牌区在客户端只有本人能点，
##    让绝界持有者选是点不动的（原版也是由结界师决定交/移除哪一个）。

const JIE_JIE_YI_SHI: int = 8201
const HUANG_SHEN_JI_YI: int = 8203
const JIN_MO_JING: int = 8204
const LIU_LI_JING: int = 8205
## 【绝界】场卡的三条能力各自成行：
const 灭界破散: int = 8206
const FU_MO_JING: int = 8207
const 白二羯磨: int = 8208

const JI_SLOT: int = 0
const 绝界名: String = "绝界"
## 星石类型（「移除战绩区 1 星石」的选项值）
const 星石_宝石: int = 1
const 星石_水晶: int = 2

## ctx 里的分步键：每个钩子一份，互不干扰
const 键_荒神: String = "_jiejie_荒神"
## 荒神祭仪后半段一次提交时选中的那张【结界】（实例号）
const 键_荒神_盖: String = "_jiejie_荒神盖"
## 琉璃境两条链的进度键前缀（键本身＝阶段；候选 / 弃牌人 / 牌 = 前缀 + 后缀）
const 键_琉璃: String = "_jiejie_琉璃"
## 同步掉士气链（合成星杯 / 逆反居合斩 / 暗月诅咒）扣完士气后补问的那条
const 键_琉璃后: String = "_jiejie_琉璃后"
const 键_白二: String = "_jiejie_白二"
const 键_灭界: String = "_jiejie_灭界"
const 键_伏魔: String = "_jiejie_伏魔"
## 挂在伤害字典上：伏魔境伤害前的两队士气（p_harm_end 拿来比）
const 键_伏魔前士气: String = "_jiejie_伏魔前士气"
## p_harm_end 的分步（和 p_fu_mo_ask 的键分开）
const 键_伏魔尾: String = "_jiejie_伏魔尾"
## 荒神之力写进 harm 的「本次攻击已加过」标记（与攻击 ctx 的分步键分开）
const 键_荒神加伤: String = "_jiejie_荒神加伤"


# ============================================================
# 技能栏（8202 被动 / 8205、8207 响应 / 8206、8208、8209 是【绝界】的专属技，都不上技能栏）
# ============================================================
func available_skills() -> Array:
	var 祭: int = player.token_num(JI_SLOT)
	return [
		{
			"type": GConst.ActionType.MagicSkill,
			"id": JIE_JIE_YI_SHI,
			"need_card": 2,
			"cards": player.hand_cards.duplicate(),
			"enabled": player.hand_cards.size() >= 2 and player.cover_space() >= 2,
		},
		{
			"type": GConst.ActionType.MagicSkill,
			"id": JIN_MO_JING,
			"need_target": 1,
			"targets": _全体角色(),
			"enabled": 祭 >= 1,
		},
	]


func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	match int(action.get("action_id", 0)):
		JIE_JIE_YI_SHI:
			var cards: Array = action.get("card_ids", [])
			# 恰好 2 张、互不相同、都在手牌；盖牌槽要放得下 2 张
			if cards.size() != 2 or _has_duplicate(cards):
				return GConst.GE_INVALID_CARDID
			for c: Variant in cards:
				if not player.有手牌(int(c)):
					return GConst.GE_INVALID_CARDID
			if not player.can_add_cover_cards(2):
				return GConst.GE_INVALID_ACTION
			return GConst.GE_SUCCESS
		JIN_MO_JING:
			if player.token_num(JI_SLOT) < 1:
				return GConst.GE_INVALID_ACTION
			var dsts: Array = action.get("dst_ids", [])
			if dsts.size() != 1 or engine.p(int(dsts[0])) == null:
				return GConst.GE_INVALID_PLAYERID
			return GConst.GE_SUCCESS
	return GConst.GE_INVALID_ACTION


func p_magic_skill(action: Dictionary) -> int:
	match int(action.get("action_id", 0)):
		JIE_JIE_YI_SHI:
			return _p_结界仪式(action)
		JIN_MO_JING:
			return _p_禁魔境(action)
	return EMPTY_HANDLE


## 8201 结界仪式：2 张手牌面朝上放进盖牌区作为【结界】，你 +1【祭】。
## 牌是【展示】的（take_from_hand(..., true) 压展示钩子），又放了盖牌（压 p_cover_change），
## 祭增加还可能问【伏魔境】：这些状态都要先跑完，所以返回 URGENT。
func _p_结界仪式(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var 放: Array[int] = []
	for c: Variant in cards:
		var cid: int = player.手牌实例(int(c))
		if cid >= 0:
			放.append(cid)
	if 放.size() != 2 or 放[0] == 放[1]:
		engine.报错("【结界仪式】提交的牌已不在手牌", player.id)
		return SUCCESS
	notice_skill(JIE_JIE_YI_SHI, [player.id])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": 放, "is_real": true,
	})
	# 压栈顺序（后压先跑）：先压【伏魔境】的询问，再压盖牌变动、最后压「展示手牌」，
	# 这样展示响应 → 盖牌变动 → 伏魔境依次结算（祭增加发生在展示之后，响应也排在后面）。
	_加祭(1)
	engine.add_cover(player.id, 放, player.id, JIE_JIE_YI_SHI, true)
	engine.take_from_hand(player.id, 放, true)
	return URGENT


## 8204 禁魔境：移除 1 点【祭】，把【绝界】转移 / 放置到目标角色前，你弃 1 张牌。
func _p_禁魔境(action: Dictionary) -> int:
	var dsts: Array = action.get("dst_ids", [])
	var dst: int = int(dsts[0]) if not dsts.is_empty() else -1
	if dst < 0 or not player.remove_token(JI_SLOT, 1):
		engine.报错("【禁魔境】目标或【祭】不成立", player.id)
		return SUCCESS
	notice_skill(JIN_MO_JING, [dst])
	# 同一张【绝界】只存在一份：加场卡按 id 顶掉旧的（转移＝换个 attached / 重新放置）
	var 旧持有者: int = _绝界持有者()
	if 旧持有者 >= 0 and 旧持有者 != dst:
		_设置绝界基础效果禁用(旧持有者, false)
	engine.加场卡({
		"id": 绝界名, "owner": player.id, "attached": dst,
		"counter": 0, "counter_max": 0, "state": 0,
	})
	# 虚空境：绝界挂在谁面前，谁的基础效果一律不触发
	_设置绝界基础效果禁用(dst, true)
	engine._broadcast_game()
	# 灭界破散是「结界为 0 时」的状态：她这时没有【结界】，绝界放下就当场破散
	_检查绝界破散()
	# 「你弃 1 张牌」是强制：走 SRequestDiscard，超时按手牌顺序补一张（技能维护约定 §16）
	engine.push(BattleEngine.SRequestDiscard.new(player.id, 1, 0, JIN_MO_JING))
	return URGENT


# ============================================================
# 8202 荒神之力：所有与【结界】系别相同的攻击伤害额外 +1。
# 结算放在攻击宣告前（p_before_attack）：后面所有询问拿到的 harm.point 都已含这 1 点。
# 一次攻击只加一次（同系多张【结界】不叠加），harm 上打标记防钩子回栈重跑。
# ============================================================
func p_before_attack(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if harm.is_empty() or bool(harm.get(键_荒神加伤, false)):
		return SUCCESS
	var 卡: GCard = Data.get_card(int(ctx.get("card_id", -1)))
	if 卡 == null or not 卡.is_attack():
		return SUCCESS
	var 系别: Array[int] = _结界系别()
	if 系别.is_empty() or not 系别.has(卡.element_enum()):
		return SUCCESS
	harm["point"] = int(harm.get("point", 0)) + 1
	harm[键_荒神加伤] = true
	return SUCCESS


# ============================================================
# 8203 荒神祭仪：目标角色主动攻击①、系别与【结界】相同时，先问是否发动；
# 确认后 +1【祭】；（可额外移除 3 点【祭】）你弃 1 张牌、移除 1 个【结界】并【横置】。
# 分步全记在攻击 ctx 上：同一次攻击重入不重复询问，也不会被别的钩子改掉。
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
	# 【祭】已满、又没有手牌 / 结界可付后半段代价时，这次响应什么都不会发生，不弹询问
	if player.token_num(JI_SLOT) >= player.token_max(JI_SLOT) \
			and (player.hand_cards.is_empty() or _结界().is_empty()):
		return SUCCESS
	while true:
		match int(ctx.get(键_荒神, 0)):
			0:
				ctx[键_荒神] = 1
				if not engine.has_reply():
					# 发动询问的提示用技能说明的前半段（只讲 +1 祭），后半段在额外代价那条询问里由「提示2」说明
					询问(player.id, HUANG_SHEN_JI_YI, 0, 0, GConst.CardSource.Hand, [], 0, "", [],
						true, 0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0, _荒神_发动提示())
					return WAIT
			1:
				if not engine.has_reply():
					return WAIT
				var r: Dictionary = take_skill_reply_full()
				if not _是发动(r):
					ctx[键_荒神] = STEP_DONE
					return SUCCESS
				ctx[键_荒神] = 2
				notice_skill(HUANG_SHEN_JI_YI, [player.id])
				# 祭增加会触发【伏魔境】：压了询问钩子就先让它跑完，再回本步问后半段
				if _加祭(1):
					return URGENT
			2:
				if player.token_num(JI_SLOT) < 3 or player.hand_cards.is_empty() \
						or _结界().is_empty():
					ctx[键_荒神] = STEP_DONE
					return SUCCESS
				ctx[键_荒神] = 3
				if not engine.has_reply():
					# 一次问完：确认额外移除 3 祭 + 选 1 张手牌弃掉 + 选 1 个【结界】移除。
					# 直接传「手牌 1 张（hand_need）+ 盖牌 1 张（cover_need）」，客户端按张数卡死。
					# 取消＝不额外移除（保留前面 +1 祭）。
					询问(player.id, HUANG_SHEN_JI_YI, 2, 0, GConst.CardSource.HandOrCover, [], 2, "", [],
						true, 0, -1, [], -1, {}, 0, 0, false, [], true, -1, 1,
						提示原文(HUANG_SHEN_JI_YI, 1), -1, "", [], [], 1, 1)
					return WAIT
			3:
				if not engine.has_reply():
					return WAIT
				var r2: Dictionary = take_skill_reply_full()
				if not _是发动(r2):
					ctx[键_荒神] = STEP_DONE
					return SUCCESS
				var 提交: Array = r2.get("card_ids", [])
				var 手卡: int = -1
				var 盖卡: int = -1
				for c: Variant in 提交:
					var cid2: int = int(c)
					if 手卡 < 0 and player.有手牌(cid2):
						手卡 = cid2
					elif 盖卡 < 0 and player.有盖牌(cid2):
						盖卡 = cid2
				if 提交.size() != 2 or 手卡 < 0 or 盖卡 < 0:
					# 硬提交了不合法的组合（如两张手牌 / 两张盖牌）：驳回重问，不静默换牌
					engine.send(player.id, GConst.Msg.ErrorInput,
						{"error_type": GConst.CmdType.Respond, "commands": []})
					ctx[键_荒神] = 2
					continue
				var 手实例: int = player.手牌实例(手卡)
				var 盖实例: int = player.盖牌实例(盖卡)
				if 手实例 < 0 or 盖实例 < 0 or not player.remove_token(JI_SLOT, 3):
					ctx[键_荒神] = STEP_DONE
					return SUCCESS
				ctx[键_荒神_盖] = 盖实例
				notice_skill(HUANG_SHEN_JI_YI, [player.id])
				engine._broadcast_game()
				# 结算顺序照原文：移除 3 点【祭】→ 弃 1 张牌 → 移除 1 个【结界】→ 横置
				engine.take_from_hand(player.id, [手实例])
				engine.to_discard([手实例], {"owner": player.id, "source": "hand",
					"cause": HUANG_SHEN_JI_YI, "face_up": false})
				engine._log_discard(player.id, [手实例])
				ctx[键_荒神] = 4
				return URGENT
			4:
				var 移: int = int(ctx.get(键_荒神_盖, -1))
				ctx[键_荒神] = 5
				if 移 >= 0:
					_移除结界并弃置([移], HUANG_SHEN_JI_YI)
				return URGENT
			5:
				ctx[键_荒神] = STEP_DONE
				_横置并查破散()
				return SUCCESS
			_:
				return SUCCESS
	return SUCCESS


# ============================================================
# 8205 琉璃境：我方士气下降时，若你已【横置】→【重置】、战绩区 +1 宝石、
# 指定 1 名目标角色弃 1 张牌【展示】，你可把该弃牌面朝上放进盖牌区作为【结界】。
#
# 两条链分开记进度：
#   · 可等待的掉士气（伤害 / 超限）：SOverloadMorale 里 p_lose_morale 直接问；
#   · 同步掉士气（合成星杯 / 逆反居合斩 / 暗月诅咒）：同步链不能等玩家输入，
#     引擎在 lose_morale 扣完士气后补压 p_lose_morale_after，由那条钩子问。
# ============================================================
func p_lose_morale(ctx: Dictionary) -> int:
	# 同步链不在这里问：扣完士气后由 p_lose_morale_after 补问
	if bool(ctx.get("sync", false)):
		return SUCCESS
	return _琉璃响应(ctx, 键_琉璃)


## 同步链扣完士气后补问（ctx.sync=true）：士气已经扣完，响应只做后半段。
func p_lose_morale_after(ctx: Dictionary) -> int:
	return _琉璃响应(ctx, 键_琉璃后)


## 琉璃境响应流程。前缀区分两条链的进度键，互不覆盖。
func _琉璃响应(ctx: Dictionary, 前缀: String) -> int:
	# 「已横置」只在流程起点判：发动后她自己会【重置】（tap=false），
	# 重入时不能再拿它当门槛，否则后面的选人 / 弃牌 / 放结界整段不生效（约定 §20）。
	if int(ctx.get(前缀, 0)) == 0 and not player.tap:
		return SUCCESS
	var 掉方: BattlePlayer = engine.p(int(ctx.get("dst", -1)))
	if 掉方 == null or 掉方.color != player.color:
		return SUCCESS
	while true:
		match int(ctx.get(前缀, 0)):
			0:
				ctx[前缀] = 1
				if not engine.has_reply():
					询问(player.id, LIU_LI_JING)
					return WAIT
			1:
				if not engine.has_reply():
					return WAIT
				var r: Dictionary = take_skill_reply_full()
				if not _是发动(r):
					ctx[前缀] = STEP_DONE
					return SUCCESS
				notice_skill(LIU_LI_JING, [player.id])
				player.tap = false
				engine.set_team_gem(player.color, engine.team_gem[player.color] + 1)
				engine._broadcast_game()
				var 有牌: Array[int] = _有手牌角色()
				if 有牌.is_empty():
					ctx[前缀] = STEP_DONE
					return SUCCESS
				ctx[前缀 + "候选"] = 有牌
				ctx[前缀] = 2
				if not engine.has_reply():
					# 「目标角色」＝场上任意一名角色（自己 / 队友 / 对手都能选），没手牌的人不可选
					询问(player.id, LIU_LI_JING, 0, 1, GConst.CardSource.Hand, [], 0, "", [],
						false, 0, -1, 有牌, -1, {}, 0, 0, false, [], true, -1, 0,
						提示原文(LIU_LI_JING, 2))
					return WAIT
			2:
				if not engine.has_reply():
					return WAIT
				var r2: Dictionary = take_skill_reply_full()
				var 候选: Array = ctx.get(前缀 + "候选", [])
				var ds: Array = r2.get("dst_ids", [])
				var 目标: int = int(ds[0]) if ds.size() == 1 else -1
				if not 候选.has(目标):
					ctx[前缀] = STEP_DONE
					return SUCCESS
				ctx[前缀 + "弃牌人"] = 目标
				ctx[前缀] = 3
				# 让别人弃牌走标准弃牌应答：客户端提示条自动写「【琉璃境】：请选择 1 张牌弃掉」
				engine.ask_respond(目标, GConst.RespondType.Discard, [目标, LIU_LI_JING, 1], [目标])
				engine.wait_for(目标, GConst.Msg.Respond)
				return WAIT
			3:
				if not engine.has_reply():
					return WAIT
				var r3: Dictionary = take_skill_reply_full()
				var tgt: BattlePlayer = engine.p(int(ctx.get(前缀 + "弃牌人", -1)))
				if tgt == null or tgt.hand_cards.is_empty():
					ctx[前缀] = STEP_DONE
					return SUCCESS
				var cid: int = _取一张手牌(tgt, r3.get("card_ids", []))
				if cid < 0:
					ctx[前缀] = STEP_DONE
					return SUCCESS
				ctx[前缀 + "牌"] = cid
				# 【展示】：先公开再决定去向（作为结界 / 进弃牌堆）
				engine.broadcast(GConst.Msg.Card, {
					"type": GConst.CardMsgType.Show, "src_id": tgt.id, "dst_id": tgt.id,
					"card_ids": [cid], "is_real": true,
				})
				engine.take_from_hand(tgt.id, [cid], true)
				# 压了「展示手牌」钩子：先让它结算完，回来再问要不要放进盖牌区
				ctx[前缀] = 4
				return URGENT
			4:
				if int(ctx.get(前缀 + "牌", -1)) < 0:
					ctx[前缀] = STEP_DONE
					return SUCCESS
				if not player.can_add_cover_cards(1):
					_弃置琉璃弃牌(ctx, 前缀)
					return URGENT
				ctx[前缀] = 5
				if not engine.has_reply():
					询问(player.id, LIU_LI_JING, 0, 0, GConst.CardSource.Hand, [], 0, "", [],
						true, 0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0,
						提示原文(LIU_LI_JING, 4))
					return WAIT
			5:
				if not engine.has_reply():
					return WAIT
				var r5: Dictionary = take_skill_reply_full()
				if not _是发动(r5):
					_弃置琉璃弃牌(ctx, 前缀)
					return URGENT
				var 放: int = int(ctx.get(前缀 + "牌", -1))
				ctx[前缀] = STEP_DONE
				engine.add_cover(player.id, [放], player.id, LIU_LI_JING, true)
				return URGENT
			_:
				return SUCCESS
	return SUCCESS


## 琉璃境那张弃牌不进盖牌区：进弃牌堆（owner 必须是真正弃牌的人）
func _弃置琉璃弃牌(ctx: Dictionary, 前缀: String) -> void:
	var cid: int = int(ctx.get(前缀 + "牌", -1))
	var 主人: int = int(ctx.get(前缀 + "弃牌人", -1))
	ctx[前缀] = STEP_DONE
	ctx[前缀 + "牌"] = -1
	if cid < 0:
		return
	if 主人 < 0:
		return
	engine.to_discard([cid], {"owner": 主人, "source": "hand", "cause": LIU_LI_JING})
	engine._log_discard(主人, [cid])
	engine._broadcast_game()


# ============================================================
# 8206 灭界破散（被动）/ 8208 白二羯磨（响应）/ 8209 虚空境（被动）
# 三条都只认「绝界挂在谁面前」：attached 那名角色才是「拥有此卡的角色」。
# ============================================================
## 白二羯磨：把结界师的每个【结界】做成给持有者点的选项（值＝盖牌实例号）。
func _白二_结界选项() -> Array:
	var out: Array = []
	for cid: int in player.cover_cards:
		var 卡: GCard = Data.get_card(cid)
		if 卡 == null:
			continue
		out.append({"value": cid, "label": 卡.card_name, "card_id": cid})
	return out


## 8208 白二羯磨：拥有【绝界】的角色【攻击行动】结束时发动 ——
## 「你」＝绝界持有者：由他决定发不发动；结界师 +1【祭】，他再把 1 个【结界】加入手牌【强制】。
## 客户端点不了别人的盖牌区，所以「拿哪个结界」做成选项列表给持有者点。
func p_action_end(ctx: Dictionary) -> int:
	if str(ctx.get("kind", "")) != "attack":
		return SUCCESS
	var 持有者: int = _绝界持有者()
	if 持有者 < 0 or int(ctx.get("player", -1)) != 持有者:
		return SUCCESS
	# 【祭】已满、又没有【结界】可给时，这次响应什么都不做，不弹询问
	if player.token_num(JI_SLOT) >= player.token_max(JI_SLOT) and _结界().is_empty():
		return SUCCESS
	while true:
		match int(ctx.get(键_白二, 0)):
			0:
				ctx[键_白二] = 1
				if not engine.has_reply():
					# 原文「你」＝拥有【绝界】的人，不是结界师：发不发动由他说
					询问(持有者, 白二羯磨)
					return WAIT
			1:
				if not engine.has_reply():
					return WAIT
				var r: Dictionary = take_skill_reply_full()
				if not _是发动(r):
					ctx[键_白二] = STEP_DONE
					return SUCCESS
				ctx[键_白二] = 2
				notice_skill(白二羯磨, [持有者])
				# 祭增加会触发【伏魔境】：先让它结算完，再给持有者发牌
				if _加祭(1):
					return URGENT
			2:
				if _结界().is_empty():
					ctx[键_白二] = STEP_DONE
					return SUCCESS
				var 选项: Array = _白二_结界选项()
				if 选项.is_empty():
					ctx[键_白二] = STEP_DONE
					return SUCCESS
				ctx[键_白二] = 3
				if not engine.has_reply():
					# 持有者挑 1 个【结界】（选项值＝盖牌实例号）
					询问(持有者, 白二羯磨, 0, 0, GConst.CardSource.Hand, 选项, 0, "", [],
						false, 0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0,
						GConst.skill_desc(白二羯磨))
					return WAIT
			3:
				if not engine.has_reply():
					return WAIT
				var r3: Dictionary = take_skill_reply_full()
				var args: Array = r3.get("args", [])
				var cid: int = int(args[0]) if not args.is_empty() else -1
				ctx[键_白二] = STEP_DONE
				# 超时 / 非法选项：技能是【强制】的，改拿结界师的第一个【结界】
				if cid < 0 or not player.有盖牌(cid):
					cid = player.cover_cards[0] if not player.cover_cards.is_empty() else -1
				if cid < 0 or not player.有盖牌(cid):
					return SUCCESS
				var 目标: int = _绝界持有者()
				var 收牌人: BattlePlayer = engine.p(目标)
				if 收牌人 == null:
					return SUCCESS
				engine.remove_cover(player.id, [cid], player.id, 白二羯磨)
				收牌人.add_hand_cards([cid])
				engine._log_give_cards(player.id, 收牌人.id, [cid])
				engine._broadcast_game()
				_检查绝界破散()
				return SUCCESS
			_:
				return SUCCESS
	return SUCCESS


## 8206 灭界破散：拥有【绝界】的角色回合结束前，结界师移除 1 个【结界】；
## 结界为 0 时（不论何时变 0）结界师【横置】、移除【绝界】。
func p_turn_end(ctx: Dictionary) -> int:
	var 持有者: int = _绝界持有者()
	if 持有者 < 0 or int(ctx.get("player", -1)) != 持有者:
		return SUCCESS
	if _结界().is_empty():
		_检查绝界破散()
		return SUCCESS
	while true:
		match int(ctx.get(键_灭界, 0)):
			0:
				ctx[键_灭界] = 1
				if not engine.has_reply():
					_问选结界(灭界破散)
					return WAIT
			1:
				if not engine.has_reply():
					return WAIT
				var cid: int = _取询问盖牌()
				ctx[键_灭界] = STEP_DONE
				if cid >= 0:
					notice_skill(灭界破散, [player.id])
					_移除结界并弃置([cid], 灭界破散)
				_检查绝界破散()
				return SUCCESS
			_:
				return SUCCESS
	return SUCCESS


## 她的【结界】什么时候变成 0，就在什么时候破散。
## 自己技能移除走 remove_cover → 这里；禁魔境放下时、白二羯磨 / 回合结束移除后另有显式检查。
## （盖牌超限是引擎直接 remove_cover_cards，不过她的槽只有 2 个、放牌前都查过空位，走不到超限。）
func p_cover_change(ctx: Dictionary) -> int:
	if int(ctx.get("dst", -1)) != player.id:
		return SUCCESS
	if int(ctx.get("direction", -1)) != GConst.CHANGE_REMOVE:
		return SUCCESS
	if not _结界().is_empty() or _绝界持有者() < 0:
		return SUCCESS
	_检查绝界破散()
	return SUCCESS


## 8209 虚空境：不再走角色钩子 —— 绝界持有者的「禁止基础效果生效」属性由
## _设置绝界基础效果禁用 维护，引擎各结算点直接看这个属性。

## 虚空境：绝界挂在谁面前，谁的基础效果就一律不触发（属性随快照下发，客户端置灰图标）。
func _设置绝界基础效果禁用(pid: int, 禁用: bool) -> void:
	if pid < 0:
		return
	var 目标: BattlePlayer = engine.p(pid)
	if 目标 == null or 目标.基础效果禁用 == 禁用:
		return
	目标.基础效果禁用 = 禁用
	engine._broadcast_game()


## 结界为 0 时：结界师【横置】，移除【绝界】（同步结算，不询问）
func _检查绝界破散() -> void:
	var 持有者: int = _绝界持有者()
	if 持有者 < 0 or not _结界().is_empty():
		return
	_设置绝界基础效果禁用(持有者, false)
	# 已经横置时不要再写一次 tap：setter 会无条件压一轮 p_tap，
	# 兽灵【兽魂警戒】会把「本来就横置」误当成一次新的横置
	if not player.tap:
		player.tap = true
	engine.移除场卡(绝界名)
	notice_skill(灭界破散, [player.id])
	engine._broadcast_game()


# ============================================================
# 8207 伏魔境：【水晶】（每当你【祭】增加时发动）对目标对手造成 1 点法术伤害③；
# （若因此造成对方士气下降，移除我方【战绩区】1 星石）你 +1【水晶】。
# 单独一个询问钩子（不走其它流程的 ctx）：祭增加随时可能发生，压进来跑完再回去。
# ============================================================
func p_fu_mo_ask(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	while true:
		match int(ctx.get(键_伏魔, 0)):
			0:
				if player.get_energy() < 1 or enemy_ids().is_empty():
					ctx[键_伏魔] = STEP_DONE
					return SUCCESS
				ctx[键_伏魔] = 1
				if not engine.has_reply():
					# 一次问完：选目标对手 + 确认＝发动；取消＝不发动。提示用技能说明第一段
					询问(player.id, FU_MO_JING, 0, 1, GConst.CardSource.Hand, [], 0, "", [],
						true, 0, -1, enemy_ids(), -1, {}, 0, 0, false, [], true, -1, 0,
						_伏魔_发动提示())
					return WAIT
			1:
				if not engine.has_reply():
					return WAIT
				var r: Dictionary = take_skill_reply_full()
				var ds: Array = r.get("dst_ids", [])
				var 目标: int = int(ds[0]) if ds.size() == 1 else -1
				ctx[键_伏魔] = STEP_DONE
				if not enemy_ids().has(目标) or engine.p(目标) == null:
					return SUCCESS
				# 费用写【水晶】：宝石可顶，用 remove_energy 支付（先水晶后宝石）
				if player.get_energy() < 1:
					return SUCCESS
				player.remove_energy(1)
				notice_skill(FU_MO_JING, [目标])
				var harm: Dictionary = {
					"src": player.id, "dst": 目标, "point": 1,
					"cause": FU_MO_JING, "type": GConst.HarmType.Magic, "is_active": false,
				}
				# p_harm_end 在伤害流水线最末尾跑，那时才判得出「是否造成士气下降」
				harm[键_伏魔前士气] = [engine.team_morale[GConst.BLUE], engine.team_morale[GConst.RED]]
				engine.push_harm(harm)
				engine._broadcast_game()
				return URGENT
			_:
				return SUCCESS
	return SUCCESS


## 伏魔境的伤害结算完：对方士气下降 → 询问是否移除我方战绩区 1 星石；
## 确认移除才扣星石并 +1【水晶】，取消 / 没有星石都不给。
func p_harm_end(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if int(harm.get("cause", 0)) != FU_MO_JING or int(harm.get("src", -1)) != player.id:
		return SUCCESS
	if not harm.has(键_伏魔前士气):
		return SUCCESS
	var 目标: BattlePlayer = engine.p(int(harm.get("dst", -1)))
	if 目标 == null or 目标.color == player.color:
		# 伤害被转移到我方角色身上时不是「对方士气下降」，不触发后半段
		return SUCCESS
	var 前: Array = harm.get(键_伏魔前士气, [])
	while true:
		match int(ctx.get(键_伏魔尾, 0)):
			0:
				if engine.team_morale[目标.color] >= int(前[目标.color]):
					ctx[键_伏魔尾] = STEP_DONE
					return SUCCESS
				if engine.team_gem[player.color] + engine.team_crystal[player.color] <= 0:
					# 没有星石可移除：后半段做不了，不给水晶（必须移除才加）
					ctx[键_伏魔尾] = STEP_DONE
					return SUCCESS
				ctx[键_伏魔尾] = 1
				if not engine.has_reply():
					# 后半段（移除我方战绩区 1 星石 + 1 水晶）：提示用技能说明第二段
					询问(player.id, FU_MO_JING, 0, 0, GConst.CardSource.Hand, _星石选项(),
						0, "", [], true, 0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0,
						_伏魔_尾提示())
					return WAIT
			1:
				if not engine.has_reply():
					return WAIT
				var r: Dictionary = take_skill_reply_full()
				var args: Array = r.get("args", [])
				var 选择: int = int(args[0]) if not args.is_empty() else -1
				ctx[键_伏魔尾] = STEP_DONE
				# 取消 / 超时 / 非法：不移除 → 不给【水晶】
				if 选择 == 星石_宝石 and engine.team_gem[player.color] > 0:
					engine.set_team_gem(player.color, engine.team_gem[player.color] - 1)
				elif 选择 == 星石_水晶 and engine.team_crystal[player.color] > 0:
					engine.set_team_crystal(player.color, engine.team_crystal[player.color] - 1)
				else:
					return SUCCESS
				player.set_crystal(player.crystal + 1)
				engine._broadcast_game()
				return SUCCESS
			_:
				return SUCCESS
	return SUCCESS


## 「移除战绩区 1 星石」的两个选项：固定两项，做不了的置灰（照 10802 风之剑 / 7804 强予愿行）
func _星石选项() -> Array:
	var 宝石文: String = GConst.文本("通用_星石_一个宝石")
	var 水晶文: String = GConst.文本("通用_星石_一个水晶")
	return [
		{"value": 星石_宝石, "label": 宝石文, "text": 宝石文,
			"enabled": engine.team_gem[player.color] > 0},
		{"value": 星石_水晶, "label": 水晶文, "text": 水晶文,
			"enabled": engine.team_crystal[player.color] > 0},
	]


# ============================================================
# 内部
# ============================================================
## 荒神祭仪的发动询问提示：只取技能说明的前半段（到第一个「；」），前面套「【荒神祭仪】：」。
## 说明的后半段（额外 3 祭换弃牌 / 移除结界 / 横置）由第二次询问的「提示2」说明，不在这一步重复。
func _荒神_发动提示() -> String:
	var 说明: String = GConst.skill_desc(HUANG_SHEN_JI_YI)
	return "【%s】：%s" % [GConst.skill_name(HUANG_SHEN_JI_YI), 说明.get_slice("；", 0).strip_edges()]


## 伏魔境第一段（选目标 / 造成 1 点法术伤害）用技能说明的第一段；
## 第二段（移除星石 + 水晶）用第二段。和荒神祭仪同一口径：只取到「；」为止的那一段。
func _伏魔_发动提示() -> String:
	var 说明: String = GConst.skill_desc(FU_MO_JING)
	return "【%s】：%s" % [GConst.skill_name(FU_MO_JING), 说明.get_slice("；", 0).strip_edges()]


func _伏魔_尾提示() -> String:
	var 说明: String = GConst.skill_desc(FU_MO_JING)
	var 第二段: String = 说明.get_slice("；", 1).strip_edges()
	if 第二段.is_empty():
		第二段 = 说明
	return "【%s】：%s" % [GConst.skill_name(FU_MO_JING), 第二段]


## 加【祭】；真的加上去了才触发【伏魔境】（返回 true＝压了询问钩子，调用方要 return URGENT）
func _加祭(n: int) -> bool:
	if player.add_token(JI_SLOT, n) <= 0:
		return false
	engine._broadcast_game()
	if player.get_energy() < 1 or enemy_ids().is_empty():
		return false
	engine.push(BattleEngine.SHook.new("p_fu_mo_ask", {"player": player.id}, []))
	return true


## 【绝界】的持有者（attached；没在场卡时 -1）
func _绝界持有者() -> int:
	if not engine.有场卡(绝界名):
		return -1
	return int(engine.取场卡(绝界名).get("attached", -1))


## 她的【结界】牌＝盖牌区里的全部牌（面朝上）
func _结界() -> Array[int]:
	return player.cover_cards.duplicate()


## 结界里出现的系别（去重；0＝无系别不算）
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
	询问(player.id, 技能号, 1, 0, GConst.CardSource.Cover, [], 0, "", [], false)


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
func _取一张手牌(tgt: BattlePlayer, ids: Array) -> int:
	for c: Variant in ids:
		if tgt.有手牌(int(c)):
			return int(c)
	for cid: int in tgt.hand_cards:
		return cid
	return -1


## 把【结界】移出盖牌区并弃置（先 to_discard 再 remove_cover，与 2605 / 2407 同序）
func _移除结界并弃置(cards: Array, cause: int) -> void:
	if cards.is_empty():
		return
	engine.to_discard(cards, {"owner": player.id, "source": "cover", "cause": cause, "face_up": true})
	engine.remove_cover(player.id, cards, player.id, cause)
	engine._broadcast_game()


## 荒神祭仪的收尾：【横置】，再按「结界是否为 0」判一次破散
func _横置并查破散() -> void:
	if not player.tap:
		player.tap = true
	engine._broadcast_game()
	_检查绝界破散()


## 询问回复是不是「发动 / 是」（选项值 / 确定都按 args[0] == 1）
func _是发动(r: Dictionary) -> bool:
	var args: Array = r.get("args", [])
	return args.size() > 0 and int(args[0]) == 1


func _全体角色() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		if engine.p(pid) != null:
			out.append(pid)
	return out


## 有手牌的角色（琉璃境的「指定 1 名目标角色」候选人）
func _有手牌角色() -> Array[int]:
	var out: Array[int] = []
	for pid: int in _全体角色():
		var p0: BattlePlayer = engine.p(pid)
		if p0 != null and not p0.hand_cards.is_empty():
			out.append(pid)
	return out
