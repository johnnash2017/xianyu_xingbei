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
## 荒神祭仪后半段一次提交时选中的那张【结界】（实例号）
## 琉璃境两条链的进度键前缀（键本身＝阶段；候选 / 弃牌人 / 牌 = 前缀 + 后缀）
const 键_琉璃: String = "_jiejie_琉璃"
## 同步掉士气链（合成星杯 / 逆反居合斩 / 暗月诅咒）扣完士气后补问的那条
const 键_琉璃后: String = "_jiejie_琉璃后"
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
		engine.报错(GConst.文本("报错_结界仪式牌不在手牌"), player.id)
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
		engine.报错(GConst.文本("报错_禁魔境目标或祭不成立"), player.id)
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
var _荒神已发动: bool = false
## 白二羯磨：第 1 段「发动」了才问第 2 段（框架的「答完」不能中止整条链，用标记 + 跳过表达）
var _白二已发动: bool = false
var _荒神_手: int = -1
var _荒神_盖: int = -1
var _荒神收尾步: int = 0
## 琉璃境：按前缀（两次掉士气来源）分别记候选 / 要弃牌的人 / 展示出来的那张牌
var _琉璃候选: Dictionary = {}
var _琉璃弃牌人: Dictionary = {}
var _琉璃牌: Dictionary = {}


func p_timeline_1(ctx: Dictionary) -> int:
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	# 入口的「有结界 / 这张牌是攻击牌且同系」只挡新的一次发动：正等收尾时不能再拦 ——
	# 收尾第 2 步（横置 + 查破散）恰恰发生在最后一个结界已经被移除之后。
	if not 多步询问进行中(HUANG_SHEN_JI_YI) and not 多步询问待收尾(HUANG_SHEN_JI_YI):
		var 系别: Array[int] = _结界系别()
		if 系别.is_empty():
			return SUCCESS
		var 卡: GCard = Data.get_card(int(ctx.get("card_id", -1)))
		if 卡 == null or not 卡.is_attack() or not 系别.has(卡.element_enum()):
			return SUCCESS
	# 【祭】已满、又没有手牌 / 结界可付后半段代价时，这次响应什么都不会发生，不弹询问
	# （链已经在走 / 正等收尾时不能再拦：后半段付完代价就会变成「祭满 + 无结界」）
	if not 多步询问进行中(HUANG_SHEN_JI_YI) and not 多步询问待收尾(HUANG_SHEN_JI_YI) \
			and player.token_num(JI_SLOT) >= player.token_max(JI_SLOT) \
			and (player.hand_cards.is_empty() or _结界().is_empty()):
		return SUCCESS
	# 入口状态只在新的一次响应开始时清：重入时要保留「已发动 / 选好的牌 / 要移除的结界」
	if not 多步询问进行中(HUANG_SHEN_JI_YI) and not 多步询问待收尾(HUANG_SHEN_JI_YI):
		_荒神已发动 = false
		_荒神_手 = -1
		_荒神_盖 = -1
		_荒神收尾步 = 0
	# 荒神祭祀：先问发不发动（+1 祭）→ 再问「额外移除 3 祭 + 弃 1 张手牌 + 移 1 个结界」
	return 多步询问(HUANG_SHEN_JI_YI, [
		{"询问文案": _荒神_发动提示(), "取消": _荒神取消,
		 "答完": _荒神发动答完},
		{"需牌": 2, "来源": GConst.CardSource.HandOrCover, "牌上限": 2,
		 "需盖牌": 1, "盖牌最多": 1, "手牌数": 1,
		 "询问文案": 提示原文(HUANG_SHEN_JI_YI, 1),
		 "跳过": func(_答案: Array) -> bool: return not _荒神有后半段(),
		 "校验": _荒神选牌合法, "超时默认": [],
		 "答完": _荒神选牌答完},
	], _荒神结算, _荒神收尾)


## 这一段还能不能问：发动过 + 祭够 3 + 手里有牌 + 有结界
func _荒神有后半段() -> bool:
	return _荒神已发动 and player.token_num(JI_SLOT) >= 3 \
		and not player.hand_cards.is_empty() and not _结界().is_empty()


## 第 1 段答完：发动就 +1 祭（可能压伏魔境钩子）
func _荒神发动答完(回: Dictionary, _答案: Array) -> int:
	if not _是发动(回):
		return SUCCESS
	_荒神已发动 = true
	notice_skill(HUANG_SHEN_JI_YI, [player.id])
	# 祭增加会触发【伏魔境】：压了询问钩子就先让它跑完，再回本步问后半段
	if _加祭(1):
		return URGENT
	return SUCCESS


## 第 2 段的合法性：正好 1 张手牌 + 1 张盖牌
func _荒神选牌合法(回: Dictionary) -> bool:
	var 手: int = 0
	var 盖: int = 0
	for c: Variant in 回.get("cards", []):
		var cid: int = int(c)
		if player.手牌实例(cid) >= 0:
			手 += 1
		elif player.盖牌实例(cid) >= 0:
			盖 += 1
	return 手 == 1 and 盖 == 1


## 第 2 段取消 / 超时：没付额外代价，前面 +1 祭保留
func _荒神取消() -> int:
	return SUCCESS


## 第 2 段答完：移除 3 祭 → 弃 1 张手牌（面朝下）；结界留到收尾里移除
func _荒神选牌答完(回: Dictionary, _答案: Array) -> int:
	_荒神_手 = -1
	_荒神_盖 = -1
	for c: Variant in 回.get("cards", []):
		var cid: int = int(c)
		if _荒神_手 < 0 and player.手牌实例(cid) >= 0:
			_荒神_手 = player.手牌实例(cid)
		elif _荒神_盖 < 0 and player.盖牌实例(cid) >= 0:
			_荒神_盖 = player.盖牌实例(cid)
	if _荒神_手 < 0 or _荒神_盖 < 0:
		return SUCCESS
	if not player.remove_token(JI_SLOT, 3):
		_荒神_手 = -1
		_荒神_盖 = -1
		return SUCCESS
	notice_skill(HUANG_SHEN_JI_YI, [player.id])
	engine._broadcast_game()
	# 结算顺序照原文：移除 3 点【祭】→ 弃 1 张牌 → 移除 1 个【结界】→ 横置
	engine.take_from_hand(player.id, [_荒神_手])
	engine.to_discard([_荒神_手], {"owner": player.id, "source": "hand",
		"cause": HUANG_SHEN_JI_YI, "face_up": false})
	engine._log_discard(player.id, [_荒神_手])
	return URGENT


## 结算后的收尾（会再压状态，所以拆两步）：先移除结界，再横置并查破散
func _荒神收尾() -> int:
	if _荒神收尾步 == 0:
		_荒神收尾步 = 1
		if _荒神_盖 >= 0:
			_移除结界并弃置([_荒神_盖], HUANG_SHEN_JI_YI)
		return URGENT
	_荒神收尾步 = 0
	_荒神_盖 = -1
	_横置并查破散()
	return SUCCESS


## 两段都答完（或跳过）：付过额外代价（有要移除的结界）才继续 收尾 回调（移除结界 → 横置）
func _荒神结算(_答案: Array) -> int:
	_荒神_手 = -1
	if _荒神_盖 < 0:
		return SUCCESS
	return _荒神收尾()
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
	var 链号: int = LIU_LI_JING if 前缀 == 键_琉璃 else LIU_LI_JING + 1
	var 链中: bool = 多步询问进行中(链号)
	if not 链中 and int(ctx.get(前缀, 0)) == 0 and not player.tap:
		return SUCCESS
	var 掉方: BattlePlayer = engine.p(int(ctx.get("dst", -1)))
	if 掉方 == null or 掉方.color != player.color:
		return SUCCESS
	if not 链中:
		ctx[前缀] = STEP_DONE
		_琉璃牌[前缀] = -1
		_琉璃弃牌人[前缀] = -1
		_琉璃候选[前缀] = []
	# 琉璃境：发动（重置 + 战绩区 +1 宝石）→ 选一名有手牌的角色 → 他弃 1 张牌【展示】
	# → 问结界师要不要把这张牌放进盖牌区当【结界】（放不下 / 不发动就进弃牌堆）
	return 多步询问(链号, [
		{"技能号": LIU_LI_JING, "取消": _琉璃不发动, "答完": func(_回: Dictionary, _答案: Array) -> int:
			return _琉璃发动答完(前缀)},
		{"技能号": LIU_LI_JING, "需目标": 1,
		 "目标白": func(_答案: Array) -> Array: return _琉璃候选[前缀],
		 "可取消": false, "询问文案": 提示原文(LIU_LI_JING, 2),
		 "跳过": func(_答案: Array) -> bool: return (_琉璃候选[前缀] as Array).is_empty(),
		 "答完": func(回: Dictionary, _答案: Array) -> int: return _琉璃选人答完(前缀, 回)},
		{"技能号": LIU_LI_JING, "问谁": func(_答案: Array) -> int: return _琉璃弃牌人[前缀],
		 "响应": {"type": GConst.RespondType.Discard,
			"args": func(_答案: Array) -> Array:
				return [_琉璃弃牌人[前缀], LIU_LI_JING, 1]},
		 "可取消": false,
		 "跳过": func(_答案: Array) -> bool: return _琉璃弃牌人[前缀] < 0,
		 "答完": func(回: Dictionary, _答案: Array) -> int: return _琉璃取牌答完(前缀, 回)},
		{"技能号": LIU_LI_JING, "可取消": true,
		 "询问文案": 提示原文(LIU_LI_JING, 4),
		 "跳过": func(_答案: Array) -> bool:
			return _琉璃牌[前缀] < 0 or not player.can_add_cover_cards(1),
		 "取消": func() -> int: return _琉璃弃置(前缀)},
	], func(答案: Array) -> int: return _琉璃结算(前缀, 答案), func() -> int: return SUCCESS)


## 第 1 段取消 / 超时：不发动
func _琉璃不发动() -> int:
	return SUCCESS


## 第 1 段答完：发动（重置自己、战绩区 +1 宝石），算出「有手牌的角色」候选
func _琉璃发动答完(前缀: String) -> int:
	notice_skill(LIU_LI_JING, [player.id])
	player.tap = false
	engine.set_team_gem(player.color, engine.team_gem[player.color] + 1)
	engine._broadcast_game()
	_琉璃候选[前缀] = _有手牌角色()
	return SUCCESS


## 第 2 段答完：记下要弃牌的人（必须是候选之一）
func _琉璃选人答完(前缀: String, 回: Dictionary) -> int:
	var ds: Array = 回.get("dsts", [])
	var 目标: int = int(ds[0]) if ds.size() == 1 else -1
	var 候选: Array = _琉璃候选[前缀]
	if not 候选.has(目标):
		_琉璃弃牌人[前缀] = -1
		return SUCCESS
	_琉璃弃牌人[前缀] = 目标
	return SUCCESS


## 第 3 段答完：取他弃的牌，公开【展示】并离手；压了展示钩子，等它结算完再问要不要放盖牌区
func _琉璃取牌答完(前缀: String, 回: Dictionary) -> int:
	var tgt: BattlePlayer = engine.p(_琉璃弃牌人[前缀])
	if tgt == null or tgt.hand_cards.is_empty():
		_琉璃弃牌人[前缀] = -1
		return SUCCESS
	var cid: int = _取一张手牌(tgt, 回.get("cards", []))
	if cid < 0:
		_琉璃弃牌人[前缀] = -1
		return SUCCESS
	_琉璃牌[前缀] = cid
	# 【展示】：先公开再决定去向（作为结界 / 进弃牌堆）
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": tgt.id, "dst_id": tgt.id,
		"card_ids": [cid], "is_real": true,
	})
	engine.take_from_hand(tgt.id, [cid], true)
	# 压了「展示手牌」钩子：先让它结算完，回来再问要不要放进盖牌区
	return URGENT


## 第 4 段取消 / 超时：不放进盖牌区 → 那张牌进弃牌堆
func _琉璃弃置(前缀: String) -> int:
	var cid: int = _琉璃牌[前缀]
	var 主人: int = _琉璃弃牌人[前缀]
	_琉璃牌[前缀] = -1
	_琉璃弃牌人[前缀] = -1
	if cid >= 0 and 主人 >= 0:
		engine.to_discard([cid], {"owner": 主人, "source": "hand", "cause": LIU_LI_JING})
		engine._log_discard(主人, [cid])
		engine._broadcast_game()
	return SUCCESS


## 第 4 段答完：发动＝放进盖牌区当【结界】；否则进弃牌堆
func _琉璃结算(前缀: String, 答案: Array) -> int:
	var cid: int = _琉璃牌[前缀]
	if cid < 0:
		return SUCCESS
	var 发动: bool = false
	if 答案.size() > 3:
		var 回: Dictionary = 答案[3]
		发动 = _是发动(回) and player.can_add_cover_cards(1)
	if not 发动:
		return _琉璃弃置(前缀)
	_琉璃牌[前缀] = -1
	_琉璃弃牌人[前缀] = -1
	engine.add_cover(player.id, [cid], player.id, LIU_LI_JING, true)
	return URGENT
func _白二_结界选项() -> Array:
	var out: Array = []
	for cid: int in player.cover_cards:
		var 卡: GCard = Data.get_card(cid)
		if 卡 == null:
			continue
		var 系名: String = GConst.element_to_chinese(卡.element_enum())
		var 标签: String = GConst.文本("通用_结界加入手牌") % 卡.card_name
		if not 系名.is_empty() and 系名 != "?":
			标签 = GConst.按钮原文(白二羯磨, 0) % [系名, 卡.card_name]
		out.append({"value": cid, "label": 标签, "card_id": cid})
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
	# （链已经在走时不能再拦：第 1 段发动的 +1 祭可能刚好把祭加满）
	if not 多步询问进行中(白二羯磨) \
			and player.token_num(JI_SLOT) >= player.token_max(JI_SLOT) and _结界().is_empty():
		return SUCCESS
	if not 多步询问进行中(白二羯磨):
		_白二已发动 = false
	# 白二羯磨：【绝界】持有者攻击行动结束时问他要不要发动 → 结界师给他 1 个【结界】（强制，超时拿第一个）
	return 多步询问(白二羯磨, [
		{"问谁": 持有者, "取消": _白二不发动, "答完": func(回: Dictionary, _答案: Array) -> int:
			return _白二发动答完(持有者, 回)},
		{"问谁": 持有者, "选项": func(_答案: Array) -> Array: return _白二_结界选项(),
		 "可取消": false, "询问文案": GConst.skill_desc(白二羯磨),
		 "跳过": func(_答案: Array) -> bool: return not _白二已发动 or _结界().is_empty()},
	], _白二结算)


## 第 1 段取消 / 超时：不发动
func _白二不发动() -> int:
	return SUCCESS


## 第 1 段答完：发动时 +1【祭】（可能压伏魔境钩子），再问给哪个结界
func _白二发动答完(持有者: int, 回: Dictionary) -> int:
	if not _是发动(回):
		return SUCCESS
	_白二已发动 = true
	notice_skill(白二羯磨, [持有者])
	# 祭增加会触发【伏魔境】：先让它结算完，再给持有者发牌
	if _加祭(1):
		return URGENT
	return SUCCESS


## 第 2 段答完：把选中的【结界】交给持有者（超时 / 非法选项改拿第一个）
func _白二结算(答案: Array) -> int:
	if not _白二已发动:
		return SUCCESS
	var args: Array = (答案[1] as Dictionary).get("args", []) if 答案.size() > 1 else []
	var cid: int = int(args[0]) if not args.is_empty() else -1
	if cid < 0 or not player.有盖牌(cid):
		cid = int(player.cover_cards[0]) if not player.cover_cards.is_empty() else -1
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
					# 一次问完：选目标对手 + 确认＝发动；取消＝不发动。提示用完整技能说明
					询问(player.id, FU_MO_JING, 0, 1, GConst.CardSource.Hand, [], 0, "", [],
						true, 0, -1, enemy_ids(), -1, {}, 0, 0, false, [], true, -1, 0,
						GConst.skill_desc(FU_MO_JING))
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
					# 后半段（移除我方战绩区 1 星石 + 1 水晶）：同样用完整技能说明
					询问(player.id, FU_MO_JING, 0, 0, GConst.CardSource.Hand, _星石选项(),
						0, "", [], true, 0, -1, [], -1, {}, 0, 0, false, [], true, -1, 0,
						GConst.skill_desc(FU_MO_JING))
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
	var 宝石文: String = GConst.文本("通用_星石_我方战绩区减一宝石")
	var 水晶文: String = GConst.文本("通用_星石_我方战绩区减一水晶")
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
	return GConst.文本("通用_技能提示") % [
		GConst.skill_name(HUANG_SHEN_JI_YI), 说明.get_slice("；", 0).strip_edges()]


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
