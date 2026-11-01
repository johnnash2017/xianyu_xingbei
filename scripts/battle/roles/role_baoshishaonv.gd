extends BattleRole
## 暴食少女（roleID 47）—— 特典版本
## 技能：
##   甜点冲击（4701，法术 / 普通）：弃 1 张法术牌【展示】→ 我方【战绩区】+1【宝石】；
##     2 名目标对手各弃 1 张法术牌，每有人不如此做，你对他造成 2 点法术伤害③、你弃 1 张牌。
##   食欲的黑洞（4702，响应 / 普通）：我方（队友，不含自己）承受伤害时⑥，弃 1 张【魔弹】【展示】→
##     改由你承受此伤害；你不会因此造成士气下降。
##   美味融合（4703，响应 / 普通）：你的水系或火系牌可以当【魔弹】传递。
##   三秒原则（4704，响应 / 普通）：目标队友手牌 / 盖牌中的【魔弹】正面朝上进入弃牌前，
##     你弃 1 张牌，获得该【魔弹】。
##   美食风暴（4705，法术 / 必杀技 / 宝石）：【宝石】对 2 名目标对手各造成 2 点法术伤害③。
##
## 口径（见 data-audit A19~A22、F1 的魔弹配置、F6 的 转移伤害 / 弃牌前拦截）：
##   - 4701：结算顺序与魔法少女【魔爆冲击】(801) 完全一致 —— 弃发动牌 +1 宝石后，按点选顺序
##     逐个问目标「弃 1 张法术牌」；谁不弃就**当场**结算（先对他造成 2 点法术伤害，再让你弃
##     1 张牌），结算完才问下一名。目标弃牌是可选响应：取消 / 超时 / 硬提交非法牌都按
##     「不如此做」结算惩罚。你自己的弃牌走引擎的 SRequestDiscard（每次 1 张，手牌不足就跳过）。
##   - 4702：只在「同色队友（不含自己）是本次伤害的承受者」时问；自己已经是承受者 / 敌方受伤 /
##     手里没有【魔弹】都不问。转移走 F6 的 转移伤害()：改 harm["dst"]、记录 redirect_from，
##     并声明本次伤害不因手牌超限掉士气。⑥ 在治疗回应之后，新目标不再有治疗回应。
##   - 4703：按 A21 只扩展「响应传递」（v_remissile），不提供主动使用入口；传递播报用 4703。
##   - 4704：走 F6 的 p_before_discard 拦截钩子（wants_before_discard 同步预判 + p_before_discard 认领），
##     拦「手牌 / 盖牌来源、牌主是同色队友（不含自己）」且自己手里还有牌可弃的【魔弹】。
##     口径（需求方）：暗弃（爆牌 / 技能弃置）也算 —— 收走时把那几张【魔弹】亮出来【展示】；
##     牌库顶移除（source=deck）与没有 owner/source 的弃置（灵魂镜像 / 百鬼夜行）不拦。
##     同一次弃牌里有多张【魔弹】时一次全收：每张弃 1 张自己的牌当代价。
##   - 4705：【宝石】费用必须真宝石（不能用宝石顶水晶那套规则），用 player.gem 判断、set_gem 支付。
##     2 名目标各 2 点法术伤害，按玩家点选顺序结算（伤害状态是栈，逆序压栈）。
##
## 提示列（0 基）：4701 序号 2＝「{dst} 弃 1 张法术牌，否则受 2 点法术伤害」、序号 3＝「你弃 1 张牌」；
##   4702 序号 0；4704 序号 0。技能本体的选牌 / 选目标（4701 的发动牌、4705 的宝石与目标）由技能栏下发。
##   4701~4705 的提示列目前为空（DATA 任务补齐），本文件只按下标取，不硬编码文案。

const 甜点冲击: int = 4701          # 甜点冲击（法术技能）
const 食欲的黑洞: int = 4702        # 食欲的黑洞（响应）
const 美味融合: int = 4703          # 美味融合（响应 / 魔弹传递）
const 三秒原则: int = 4704          # 三秒原则（响应 / 弃牌前拦截）
const 美食风暴: int = 4705          # 美食风暴（法术技能 / 必杀技 / 宝石）

## 4701 / 4705 的伤害与目标数（两颗技能都要求恰好 2 名互不相同的对手）
const 甜点伤害: int = 2
const 美食伤害: int = 2
const 双目标数: int = 2

## 4701 问目标弃牌时读技能表提示列的下标
const 提示序号_目标弃牌: int = 2

## 4701 的逐目标流程（放在自有变量里：跨若干次询问，不能依赖被别的钩子轮次改写的 step）。
## 与魔法少女【魔爆冲击】(801) 严格同构 —— 见 role_modao.gd 的 _mo_bao_targets / _mo_bao_index / _mo_bao_settling
var _4701目标: Array[int] = []
## 下一个要问的目标下标（问完 = 等于 _4701目标.size()）
var _4701下标: int = 0
## 本步的「伤害 → 自己弃牌」是否已压栈、正在等它们跑完：
## 钩子回头时据此跳过已经消费掉的那次回复，从下一名继续
var _4701结算中: bool = false


# ============================================================
# 技能栏
# ============================================================
func available_skills() -> Array:
	var 法术牌: Array[int] = magic_hand_ids()
	var 对手: Array[int] = enemy_ids()
	var 有宝石: bool = player.gem > 0
	# 条件不满足时照常下发、只置灰（《技能维护约定》：不能把技能从栏里删掉）
	return [
		{
			"type": GConst.ActionType.MagicSkill,
			"id": 甜点冲击,
			"need_card": 1,
			"need_target": 双目标数,
			"target_max": 双目标数,
			"targets": 对手,
			"cards": 法术牌,
			"enabled": not 法术牌.is_empty() and 对手.size() >= 双目标数,
		},
		{
			"type": GConst.ActionType.MagicSkill,
			"id": 美食风暴,
			"need_card": 0,
			"need_target": 双目标数,
			"target_max": 双目标数,
			"targets": 对手,
			"enabled": 有宝石 and 对手.size() >= 双目标数,
		},
	]


# ============================================================
# 主动法术技能：校验
# ============================================================
func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	match int(action.get("action_id", 0)):
		甜点冲击:
			return _校验甜点(action)
		美食风暴:
			return _校验美食(action)
	return GConst.GE_INVALID_ACTION


## 甜点冲击：弃 1 张法术牌 + 恰好 2 名互不相同的对手
func _校验甜点(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	if cards.size() != 1:
		return GConst.GE_INVALID_CARDID
	var cid: int = int(cards[0])
	var card: GCard = Data.get_card(cid)
	if card == null or not player.has_hand_card(cid) or not card.is_magic():
		return GConst.GE_INVALID_CARDID
	return _校验两名对手(action.get("dst_ids", []))


## 美食风暴：1 颗真宝石 + 恰好 2 名互不相同的对手
func _校验美食(action: Dictionary) -> int:
	if player.gem <= 0:
		return GConst.GE_INVALID_ACTION
	return _校验两名对手(action.get("dst_ids", []))


## 恰好 2 名互不相同、存在且是敌方的目标（与魔导师 801/804 的 checkTwoTarget 同口径）
func _校验两名对手(dsts: Array) -> int:
	if dsts.size() != 双目标数:
		return GConst.GE_INVALID_PLAYERID
	var 已见: Array[int] = []
	for d: Variant in dsts:
		var pid: int = int(d)
		if 已见.has(pid):
			return GConst.GE_INVALID_PLAYERID
		已见.append(pid)
		var pp: BattlePlayer = engine.p(pid)
		if pp == null or pp.color == player.color:
			return GConst.GE_INVALID_PLAYERID
	return GConst.GE_SUCCESS


# ============================================================
# 主动法术技能：结算入口
# ============================================================
func p_magic_skill(action: Dictionary) -> int:
	match int(action.get("action_id", 0)):
		甜点冲击:
			return _p_甜点冲击(action)
		美食风暴:
			return _p_美食风暴(action)
	return EMPTY_HANDLE


## 甜点冲击：弃发动牌【展示】→ 我方战绩区 +1 宝石 → 交给 p_tian_dian_ask 逐个问目标
func _p_甜点冲击(action: Dictionary) -> int:
	var 校验: int = _校验甜点(action)
	if 校验 != GConst.GE_SUCCESS:
		return 校验
	var cid: int = int((action.get("card_ids", []) as Array)[0])
	var dsts: Array = action.get("dst_ids", [])
	# 逐个问目标要牌的次序＝玩家点选顺序
	_4701目标.clear()
	for d: Variant in dsts:
		_4701目标.append(int(d))
	_4701下标 = 0
	_4701结算中 = false
	notice_skill(甜点冲击, dsts)
	# 发动牌【展示】后进弃牌堆
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": [cid], "is_real": true,
	})
	engine.take_from_hand(player.id, [cid], true)
	engine.to_discard([cid], {"owner": player.id, "source": "hand", "cause": 甜点冲击})
	engine._log_discard(player.id, [cid], false)
	# 我方【战绩区】+1【宝石】：无条件、在任何目标询问之前先结算
	engine.set_team_gem(player.color, engine.team_gem[player.color] + 1)
	engine._broadcast_game()
	# 逐个询问 / 结算交给钩子：它能在中途等待玩家，也能在压入其它状态后挂起再回来
	engine.push(BattleEngine.SHook.new("p_tian_dian_ask", {"player": player.id}, []))
	return URGENT


## 美食风暴：支付 1 宝石，对 2 名目标各 2 点法术伤害
func _p_美食风暴(action: Dictionary) -> int:
	var 校验: int = _校验美食(action)
	if 校验 != GConst.GE_SUCCESS:
		return 校验
	var dsts: Array = action.get("dst_ids", [])
	notice_skill(美食风暴, dsts)
	player.set_gem(player.gem - 1)
	engine._broadcast_game()
	# 伤害状态是栈（后压先算）：逆序压栈，让先点选的目标先结算
	for i: int in range(dsts.size() - 1, -1, -1):
		engine.push_harm({
			"src": player.id, "dst": int(dsts[i]), "point": 美食伤害,
			"cause": 美食风暴, "type": GConst.HarmType.Magic,
		})
	return URGENT


# ============================================================
# 4701 的逐目标流程（与 801【魔爆冲击】严格同构：对全体角色各调一次，只认 ctx 里点名的自己）
# ============================================================
## 甜点冲击的逐目标推进：问第 _4701下标 名目标「弃 1 张法术牌」；
## 没弃就当场结算（先对他造成 2 点法术伤害、再让自己弃 1 张牌），结算完才问下一名。
## 钩子轮次会对每个玩家的角色各调一次，故必须按 ctx 点名的那名玩家过滤。
func p_tian_dian_ask(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	# 上一轮把「伤害 → 自己弃牌」压了栈并返回 URGENT：这次回到这里＝那两步跑完了，
	# 接着问下一名（那次回复已经消费掉，不能重复处理）
	if _4701结算中:
		_4701结算中 = false
	while _4701下标 < _4701目标.size():
		var 目标id: int = _4701目标[_4701下标]
		if not engine.has_reply():
			# 只能弃法术牌（card_rule = "magic"）：否则界面会把攻击牌等也点亮，
			# 玩家点错提交后服务端按「不弃」处理，白白吃 2 点伤害。
			# 头像提示：本次伤害落在目标身上（预览基准 / 类型 / 目标）
			询问(目标id, 甜点冲击, 1, 0, GConst.CardSource.Hand, [], 0, "magic", [], true,
				提示序号_目标弃牌, 目标id, [目标id], -1, {}, 甜点伤害, GConst.HarmType.Magic, false, [目标id])
			return WAIT
		var r: Dictionary = take_skill_reply_full()
		_4701下标 += 1
		if _目标弃法术牌(目标id, r):
			# 弃了法术牌：本次不结算，接着问下一名
			continue
		# 没弃：压入本次结算 —— 后压先算，先压「自己弃 1 张牌」、再压伤害
		# → 执行顺序＝伤害 → 自己弃牌 → （本钩子被回头再调）问下一名
		engine.push(BattleEngine.SRequestDiscard.new(player.id, 1, 0, 甜点冲击))
		engine.push_harm({
			"src": player.id, "dst": 目标id, "point": 甜点伤害,
			"cause": 甜点冲击, "type": GConst.HarmType.Magic,
		})
		_4701结算中 = true
		engine._broadcast_game()
		return URGENT
	_4701下标 = 0
	return SUCCESS


## 目标是否真的弃出了 1 张手牌里的法术牌【展示】；成功返回 true
## （与 801 的 _target_discard_magic 同一套判定：必须是本人手牌里的法术牌）
func _目标弃法术牌(dst_id: int, r: Dictionary) -> bool:
	var dst: BattlePlayer = engine.p(dst_id)
	if dst == null:
		return false
	var args: Array = r.get("args", [])
	var given: Array = r.get("card_ids", [])
	if args.is_empty() or int(args[0]) != 1 or given.is_empty():
		return false
	var cid: int = int(given[0])
	var card: GCard = Data.get_card(cid)
	if card == null or not card.is_magic() or not dst.has_hand_card(cid):
		return false
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": dst.id, "dst_id": dst.id,
		"card_ids": [cid], "is_real": true,
	})
	engine.take_from_hand(dst.id, [cid], true)
	engine.to_discard([cid], {"owner": dst.id, "source": "hand", "cause": 甜点冲击})
	engine._log_discard(dst.id, [cid], false)
	engine._broadcast_game()
	return true



# ============================================================
# 4702 食欲的黑洞：队友（不含自己）承受伤害时⑥，弃 1 张【魔弹】把伤害转给自己
# ============================================================
func p_timeline_6(ctx: Dictionary) -> int:
	var harm: Dictionary = ctx.get("harm", {})
	if harm.is_empty():
		return SUCCESS
	# 同一次伤害的进度记在 ctx 上：每次伤害都是一份新的钩子上下文
	var 阶段: int = int(ctx.get("_4702阶段", 0))
	if 阶段 >= STEP_DONE:
		return SUCCESS
	var 承受者: BattlePlayer = engine.p(int(harm.get("dst", -1)))
	if 承受者 == null or 承受者.color != player.color or 承受者.id == player.id:
		ctx["_4702阶段"] = STEP_DONE
		return SUCCESS
	if int(harm.get("point", 0)) <= 0:
		ctx["_4702阶段"] = STEP_DONE
		return SUCCESS
	var 魔弹表: Array[int] = _手牌魔弹()
	# 手里没有【魔弹】也照样弹询问（玩家看得见「这个技能触发了」，只是点不了牌、只能取消）；
	# 牌表给 [手牌白名单_全禁]，界面上手牌整片置灰，不会让人误以为能随便弃一张
	if 魔弹表.is_empty():
		魔弹表 = [GConst.手牌白名单_全禁]
	if 阶段 == 0:
		ctx["_4702阶段"] = 1
		# 头像提示：转移后的伤害落在自己身上，写本次伤害数值与类型
		询问(player.id, 食欲的黑洞, 1, 0, GConst.CardSource.Hand, [], 0, "", 魔弹表, true,
			0, -1, [player.id], -1, {}, int(harm.get("point", 0)), int(harm.get("type", 0)), false, [player.id])
		return WAIT
	if not engine.has_reply():
		return WAIT
	ctx["_4702阶段"] = STEP_DONE
	var r: Dictionary = take_skill_reply_full()
	var args: Array = r.get("args", [])
	var given: Array = r.get("card_ids", [])
	if args.is_empty() or int(args[0]) != 1 or given.is_empty():
		return SUCCESS
	var cid: int = int(given[0])
	if not player.has_discard_card(cid) or not _是魔弹(cid):
		return SUCCESS
	notice_skill(食欲的黑洞, [player.id])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": [cid], "is_real": true,
	})
	engine.take_from_hand(player.id, [cid], true)
	engine.to_discard([cid], {"owner": player.id, "source": "hand", "cause": 食欲的黑洞})
	engine._log_discard(player.id, [cid], false)
	# ⑥ 伤害转移：改 harm["dst"] 并声明本次伤害不因手牌超限掉士气
	var 结果: int = 转移伤害(harm, player.id, true)
	if 结果 != GConst.GE_SUCCESS:
		return SUCCESS
	engine._broadcast_game()
	# 展示牌 / 弃牌前拦截可能压入了新状态：先让它们跑完，再回到本次伤害流水线
	return URGENT


# ============================================================
# 4703 美味融合：水系 / 火系牌可以当【魔弹】传递（不扩展主动使用）
# ============================================================
func missile_fusion_elements() -> Array[int]:
	return [GConst.CardElement.Water, GConst.CardElement.Fire]


## 响应传递时按 4703 播报（不借用魔导师的 803 / 节日魔导的 7602）
func missile_fusion_skill() -> int:
	return 美味融合


func v_remissile(card_id: int) -> int:
	if not player.has_hand_card(card_id):
		return GConst.GE_INVALID_CARDID
	if not can_use_as_missile(Data.get_card(card_id)):
		return GConst.GE_INVALID_CARDID
	return GConst.GE_SUCCESS


# ============================================================
# 4704 三秒原则：队友的【魔弹】正面朝上进入弃牌前，弃 1 张牌获得它（F6 拦截钩子）
# ============================================================
## 同步预判：只有「可能响应」时引擎才会把这次弃牌推迟到 p_before_discard（可等待玩家）。
## 这里不能询问玩家 / 改状态，只按 ctx 里的牌与牌主判断。
func wants_before_discard(ctx: Dictionary) -> bool:
	return _可拦截三秒原则(ctx)


func p_before_discard(ctx: Dictionary) -> int:
	# 进度按「哪个暴食少女」分开记（同一队万一有两个，不能共用一份阶段 / 待收清单，
	# 否则后来那位会把前一位的「等回复」当成自己也在等，一直挂到超时）
	var 进度键: String = "_4704进度_%d" % player.id
	var 进度: Dictionary = ctx.get(进度键, {})
	if int(进度.get("阶段", 0)) >= STEP_DONE:
		return SUCCESS
	if 进度.is_empty():
		if not _可拦截三秒原则(ctx):
			ctx[进度键] = {"阶段": STEP_DONE}
			return SUCCESS
		var 魔弹表: Array[int] = _待弃魔弹(ctx.get("cards", []))
		if 魔弹表.is_empty():
			ctx[进度键] = {"阶段": STEP_DONE}
			return SUCCESS
		# 每张【魔弹】单独响应一次：问一张、答一张；收下的先记在进度里，
		# 全部问完再交给引擎（从待弃牌里剔除、加进自己手牌）
		进度 = {"阶段": 1, "待收": 魔弹表, "下标": 0, "认领": []}
		ctx[进度键] = 进度
	var 待收: Array = 进度.get("待收", [])
	while int(进度.get("下标", 0)) < 待收.size():
		var 下标: int = int(进度["下标"])
		var 这张: int = int(待收[下标])
		if not engine.has_reply():
			var 牌主: int = int(ctx.get("owner", -1))
			# 只有一个选项、且默认替玩家选中：玩家只要挑 1 张代价牌按「确定」
			var 选项名: String = "获得 1 张【魔弹】"
			询问(player.id, 三秒原则, 0, 0, GConst.CardSource.Hand, [{
				"text": 选项名, "label": 选项名, "value": 1, "args": [1],
				"need_card": 1, "preview_cards": [这张],
				"enabled": not player.hand_cards.is_empty(),
			}], 0, "", player.hand_cards.duplicate(), true, 0, -1, [牌主], -1, {}, 0, 0, false, [牌主], true, -1, 0, "", 0)
			return WAIT
		# 这一张答完了：取消 / 交不出代价＝这张不收，下标照样往后走
		进度["下标"] = 下标 + 1
		var r: Dictionary = take_skill_reply_full()
		var args: Array = r.get("args", [])
		var given: Array = r.get("card_ids", [])
		if not args.is_empty() and int(args[0]) > 0 and not given.is_empty():
			var 代价: int = -1
			for c: Variant in given:
				var cid: int = int(c)
				if player.has_discard_card(cid):
					代价 = cid
					break
			if 代价 >= 0:
				notice_skill(三秒原则, [int(ctx.get("owner", -1))])
				engine.take_from_hand(player.id, [代价])
				engine.to_discard([代价], {"owner": player.id, "source": "hand", "cause": 三秒原则, "face_up": false})
				engine._log_discard(player.id, [代价])
				# 收走时把这张【魔弹】亮出来【展示】—— 原弃牌哪怕是暗弃也要公开牌面
				engine.broadcast(GConst.Msg.Card, {
					"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
					"card_ids": [这张], "is_real": true,
				})
				(进度["认领"] as Array).append(这张)
				engine._broadcast_game()
		ctx[进度键] = 进度
	# 全部问完：把收下的几张从待弃牌里剔除、加进手里（【强制】获得）
	var 认领: Array = 进度.get("认领", [])
	ctx[进度键] = {"阶段": STEP_DONE, "认领": 认领}
	ctx["taker"] = player.id if not 认领.is_empty() else -1
	ctx["taken"] = 认领
	engine._broadcast_game()
	return SUCCESS


## 这次弃牌能不能被【三秒原则】拦截（预判与结算共用同一口径）。
## 按需求方口径：暗弃（爆牌 / 技能弃置）也照样算 —— 收走时会把那张【魔弹】亮出来【展示】，
## 不要求弃牌时就已是正面朝上。
func _可拦截三秒原则(ctx: Dictionary) -> bool:
	if engine == null or player == null:
		return false
	if int(ctx.get("taker", -1)) >= 0:
		return false
	var 来源: String = str(ctx.get("source", ""))
	if 来源 != "hand" and 来源 != "cover":
		return false
	var 牌主: BattlePlayer = engine.p(int(ctx.get("owner", -1)))
	if 牌主 == null or 牌主.id == player.id or 牌主.color != player.color:
		return false
	# 手里一张牌都没有：付不起「弃 1 张牌」的代价，不弹询问
	if player.hand_cards.is_empty():
		return false
	return not _待弃魔弹(ctx.get("cards", [])).is_empty()


## 本次待弃牌里的【魔弹】（魔弹本体，不是 4703 扩展的水 / 火材料）
func _待弃魔弹(cards: Array) -> Array[int]:
	var out: Array[int] = []
	for c: Variant in cards:
		var cid: int = int(c)
		if _是魔弹(cid) and not out.has(cid):
			out.append(cid)
	return out


# ============================================================
# 工具
# ============================================================
## 自己手里的【魔弹】本体（4702 的发动代价）
func _手牌魔弹() -> Array[int]:
	return hand_ids_where(func(_cid: int, c: GCard) -> bool:
		return c.card_name_enum() == GConst.CardName.Missile)


## 这张牌是不是【魔弹】本体（4703 扩展的水 / 火材料不算「弃 1 张【魔弹】」的代价）
func _是魔弹(cid: int) -> bool:
	var card: GCard = Data.get_card(cid)
	return card != null and card.card_name_enum() == GConst.CardName.Missile
