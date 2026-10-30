extends BattleRole
## 矜贵之女（roleID 78）—— 神子创临版本
## 技能：
##   高岭之花（7801，被动）：你执行【提炼】时，若本次提炼至少包含 1【宝石】，你 +1【水晶】。
##   魔法入门（7802，法术 / 普通 / 无）：你摸 1 张牌【强制】【展示】，根据所展示的牌依序触发：
##       （若有法术牌）对 2 名目标对手各造成 1 点法术伤害③；
##       （若有 X 张咏类命格）你对 X 名目标角色各造成 1 点法术伤害③；
##       （若有 X 张水系牌）指定 X 名目标角色各 +1【治疗】。
##   Magic!（7803，响应 / 普通 / 无）：【魔法入门】展示牌触发效果时，你弃 2 张牌；
##       【魔法入门】展示牌未触发任何效果时，你额外 +1【法术行动】；
##       本回合第 3 次【魔法入门】结算时，我方【战绩区】+2【宝石】。
##   强予愿行（7804，启动 / 必杀技 / 水晶）：支付 1【水晶】，将你的手牌调整为 4 张【强制】；
##       若你额外移除我方【战绩区】1 星石，将一名其他角色手牌调整为 4 张【强制】。
##   友情羁绊（7805，响应 / 必杀技 / 宝石 / 回合限定）：发动【魔法入门】时，将「你摸 1 张牌
##       【强制】【展示】」改为「我方 2 名角色各弃 1 张牌【强制】【展示】，技能效果结束前
##       各摸 1 张牌【强制】」。
##
## 口径（见 data-audit A27~A30）：
##   - A27：7802 的 X＝本次「展示牌集合」里满足条件的张数；7805 后集合是那 2 张弃牌，X≤2；
##     三种效果按「法术牌 → 咏类命格 → 水系牌」依序触发（各自的 X 独立计算）；
##   - A28：7803 的三个触发独立、各自可选；「第 3 次」只在本回合第 3 次 7802 结算时问一次；
##     弃 2 张是可选代价（技能原文没有写后续效果，按字面只弃牌）；额外法术行动直接进入
##     （direct，玩家已经为发动 7803 做过一次确认）；
##   - A29：7804 的星石类型由发动者选；「额外移除」是可选分支（不选则只调整自己）；
##     其他角色由牌主自己选弃哪张（走 F9 的 调整手牌到，不替牌主选牌）；
##     选星石 / 选角色这两个子询问的取消与超时都按「放弃额外移除」处理（不扣星石、不改他人手牌），
##     不替玩家补默认星石 / 默认目标；
##   - A30：7805 的「我方 2 名角色」可含自己、必须互异；只有最初展示的 2 张弃牌触发 7802 效果，
##     技能结束前各自摸的 1 张【强制】不再并入展示集合；这 2 张弃牌在各自选定时立即离手
##     （入弃牌堆在结算统一做），保证后面（更早于技能结算的）7803 询问选不到它们、结算时也不会重复入弃；
##   - 【水晶】费用按《技能维护约定》用 get_energy() 判断、remove_energy(1) 支付（宝石可顶水晶）；
##     【宝石】费用必须是真宝石（7805）。
##
## 实现要点：
##   - 7802 是「法术技能」（SkillRun kind=magic），分步推进用引擎按状态实例隔离的 step，
##     每一步询问后返回 WAIT，重入继续；所有状态（伤害 / 展示 / 弃牌）留到最后一步一次性压栈，
##     避免把展示响应 / 伤害结算夹在两次询问中间；
##   - 展示牌钩子（p_show_hand）压在伤害与弃牌状态之上（最后 push），其他角色的「展示牌」响应
##     先结算，再跑本次的伤害 / 行动结束，与引擎 _do_magic 的 LIFO 顺序一致；
##   - 7804 是「启动」技能（is_free_skill 认可）：不消耗本回合行动，结算完重新进入行动阶段，
##     本回合只能发动一个启动技能（player.boot_skill_used 置位）。
##   - 7805 的 2 张弃牌在选定时就 take_from_hand 离手（不是等到 _结算魔法入门）：
##     7803 分支 1 的询问比技能结算更早，牌还留在手里会被再选一次。入弃牌堆统一放到结算做，
##     避免「弃牌前拦截」的等待链夹在后续询问中间；结算时再整组 take_from_hand 还会因为其中一张
##     已离手而整组失败，整组照样入弃就会让同一张牌在弃牌堆出现两次（引擎 1946~1956）。
##   - 7803 的弃 2 张在结算时逐张判断「还真实在手里」才离手入弃，只处理实际移除成功的牌。

const 高岭之花: int = 7801          # 被动：提炼含宝石 +1 水晶
const 魔法入门: int = 7802          # 法术技能：摸 1 展示，依序触发三组效果
const MAGIC_BANG: int = 7803        # 响应：三个独立触发
const 强予愿行: int = 7804          # 启动 / 必杀技 / 水晶：手牌调整为 4
const 友情羁绊: int = 7805          # 响应 / 必杀技 / 宝石 / 回合限定：改写 7802 的摸牌

## 7802 每一步的进度（step 由引擎按当前 SkillRun 实例隔离，每次发动从 0 开始）
const 步_友情选角色: int = 2
const 步_友情弃牌: int = 3
const 步_准备展示: int = 4
const 步_法术目标: int = 5
const 步_咏目标: int = 6
const 步_水目标: int = 7
const 步_7803触发: int = 8
const 步_7803弃牌: int = 9
const 步_7803未触发: int = 10
const 步_7803第三次: int = 11
const 步_结算: int = 12

## 7804 每一步的进度
const 步_强予选星石: int = 2
const 步_强予选角色: int = 3
const 步_强予结算: int = 4

## 7802 三类效果的目标数上限 / 伤害点数
const 法术目标上限: int = 2
const 法术伤害值: int = 1
const 基础治疗值: int = 1

## 7804 的手牌目标张数
const 强予手牌数: int = 4

## 本回合已发动的【魔法入门】次数（7803 的「第 3 次」用；回合开始清零）
var _本回合魔法入门次数: int = 0
## 本回合是否已发动 7805【友情羁绊】（技能名带【回合限定】）
var _本回合已用友情羁绊: bool = false

## 7802 本次发动的分步数据（每次发动在 step==0 时重置）
var _7802启用友情羁绊: bool = false
var _7802友情角色: Array[int] = []
var _7802友情弃牌: Array = []          # [{pid:int, card:int}]
var _7802展示牌: Array[int] = []
var _7802有法术牌: bool = false
var _7802咏数量: int = 0
var _7802水数量: int = 0
var _7802法术目标: Array[int] = []
var _7802咏目标: Array[int] = []
var _7802水目标: Array[int] = []
var _7802_7803弃牌: Array[int] = []
var _7802_7803额外行动: bool = false
## 本次 7802 是否已经结算过：结算会返回 URGENT，引擎重入技能本体时据此直接收尾、不重复结算
var _7802已结算: bool = false
var _7802_7803加宝石: bool = false

## 7804 本次发动的分步数据
var _7804额外移除: bool = false
var _7804移除类型: int = 0             # 1＝宝石 / 2＝水晶（0＝不额外移除）
var _7804目标: int = -1


# ============================================================
# 回合开始：清回合限定的计数与标记
# ============================================================
func p_before_turn_begin(_ctx: Dictionary) -> int:
	_本回合魔法入门次数 = 0
	_本回合已用友情羁绊 = false
	return SUCCESS


# ============================================================
# 技能栏：7802【魔法入门】/ 7804【强予愿行】
# ============================================================
func available_skills() -> Array:
	return [
		{
			"type": GConst.ActionType.MagicSkill,
			"id": 魔法入门,
			"need_card": 0,
			"need_target": 0,
			"enabled": true,
		},
		{
			"type": GConst.ActionType.SpecialSkill,
			"id": 强予愿行,
			"need_card": 0,
			"need_target": 0,
			# 能量不够时照常下发、只置灰（界面看得见技能存在）；宝石可顶水晶
			"enabled": player.get_energy() > 0,
		},
	]


## 7804 是「启动」技能：不消耗本回合行动，结算完重新进入行动阶段
func is_free_skill(skill_id: int) -> bool:
	return skill_id == 强予愿行


## 7802 摸展示牌后要先让超限结算，再接着选目标 / 结算：让引擎在 URGENT 结算完重入技能本体。
## 只对 7802 生效（7804 的 URGENT 是技能收尾，不能重入）。
func 技能URGENT后重入(action: Dictionary = {}) -> bool:
	return int(action.get("action_id", 0)) == 魔法入门


# ============================================================
# 高岭之花（7801）：执行提炼时若至少含 1 宝石，你 +1 水晶
# ============================================================
func p_after_extract(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	# 只看本次提炼实际取得的星石构成（A26）；0 宝石不触发
	if int(ctx.get("gem", 0)) < 1:
		return SUCCESS
	# 能量已满时 +1 水晶无实际收益，不播报
	if player.get_energy() >= player.energy_max:
		return SUCCESS
	player.set_crystal(player.crystal + 1)
	notice_skill(高岭之花, [player.id])
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 魔法入门（7802）：摸 1 展示 → 依序触发三组效果（可被 7805 改写）
# ============================================================
## 7802 水系效果的治疗回调：作为自定义钩子压在这次技能的伤害状态之下，等伤害结算完再结算治疗
## （效果顺序：法术伤害 → 咏类伤害 → 水系治疗；治疗放在伤害之前会白挡掉伤害）。
## 引擎对每个角色都会调这个钩子名，只有本角色实现了它，其他角色不受影响。
func p_jinguizhinv_水系治疗(ctx: Dictionary) -> int:
	for 值: Variant in ctx.get("targets", []):
		施加治疗(int(值), 基础治疗值)
	engine._broadcast_game()
	return SUCCESS


func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != 魔法入门:
		return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != 魔法入门:
		return EMPTY_HANDLE
	# 已经结算过（URGENT 挂起后引擎重入本体）：不要再结算一次，直接收尾。
	# 见 技能URGENT后重入()：7802 摸牌后要挂起走超限，挂起结束会重入这里。
	if _7802已结算:
		return SUCCESS
	if step == 0:
		_初始化魔法入门()
		_本回合魔法入门次数 += 1
		step = 步_友情选角色
	while true:
		match step:
			步_友情选角色:
				# 一步到位：直接选 2 名角色＝发动【友情羁绊】；取消＝不发动，按普通【魔法入门】继续
				if not _可发动友情羁绊():
					_7802启用友情羁绊 = false
					step = 步_准备展示
					continue
				var 候选: Array[int] = _友情羁绊候选角色()
				if 候选.size() < 2:
					# 候选在询问前已保证 ≥2；这里兜底回退成普通【魔法入门】
					_7802启用友情羁绊 = false
					step = 步_准备展示
					continue
				if not engine.has_reply():
					询问(player.id, 友情羁绊, 0, 2, GConst.CardSource.Hand, [], 0, "",
						[], true, 0, -1, 候选)
					return WAIT
				var r角色: Dictionary = take_skill_reply_full()
				_7802友情角色 = _取目标(r角色.get("dst_ids", []), 候选, 2)
				if _7802友情角色.size() < 2:
					# 取消 / 没选够：不发动友情羁绊，按普通【魔法入门】继续
					_7802启用友情羁绊 = false
					step = 步_准备展示
					continue
				_7802启用友情羁绊 = true
				# 选好 2 名角色后才付 1 宝石（取消/非法选择不付费）
				player.set_gem(player.gem - 1)
				_本回合已用友情羁绊 = true
				notice_skill(友情羁绊, _7802友情角色)
				engine._broadcast_game()
				step = 步_友情弃牌
			步_友情弃牌:
				if _7802友情弃牌.size() >= _7802友情角色.size():
					step = 步_准备展示
					continue
				var 弃牌人: int = _7802友情角色[_7802友情弃牌.size()]
				if not engine.has_reply():
					询问(弃牌人, 友情羁绊, 1, 0, GConst.CardSource.Hand, [], 0, "",
						[], false, 0)
					return WAIT
				var r弃: Dictionary = take_skill_reply_full()
				var 选牌: Array[int] = _取手牌(弃牌人, r弃.get("card_ids", []), 1)
				var 弃出: int = int(选牌[0]) if not 选牌.is_empty() else -1
				if 弃出 < 0:
					# 7805 原文是「各弃 1 张牌【强制】【展示】」：目标超时 / 空回复时按手牌顺序补一张，
					# 不能白跳过（少一张展示牌会连带改变 7802 的 X 和后续效果）
					var 弃牌者: BattlePlayer = engine.p(弃牌人)
					if 弃牌者 != null:
						for cid替: int in 弃牌者.hand_cards:
							if 弃牌者.has_discard_card(cid替):
								弃出 = cid替
								break
				# 7805：选定的牌当场离手 —— 7803 的「弃 2 张」询问比技能结算更早，
				# 牌留在手里会被再选一次。入弃牌堆统一放到 _结算魔法入门：那时不再向玩家提问，
				# 不会把「弃牌前拦截」的等待链夹在后续询问中间。
				var 已离手: bool = false
				if 弃出 >= 0:
					已离手 = engine.take_from_hand(弃牌人, [弃出])
				# 候选角色在询问前已保证手里有牌；这里只做防御，空选不崩溃、后续按无效牌跳过
				_7802友情弃牌.append({"pid": 弃牌人, "card": 弃出 if 已离手 else -1})
			步_准备展示:
				_准备7802展示()
				step = 步_法术目标
				# 摸到的展示牌可能把手牌摸超上限：先压超限结算（弃到上限 + 掉士气），
				# 回来再从「选目标」继续（本角色覆写 技能URGENT后重入()＝true，引擎会重入技能本体）。
				engine.push(BattleEngine.SHandOverflow.new())
				return URGENT
			步_法术目标:
				var 法术目标数: int = mini(法术目标上限, enemy_ids().size()) if _7802有法术牌 else 0
				if 法术目标数 <= 0:
					step = 步_咏目标
					continue
				if not engine.has_reply():
					询问(player.id, 魔法入门, 0, 法术目标数, GConst.CardSource.Hand, [], 0, "",
						[], false, 0, -1, enemy_ids())
					return WAIT
				var r法: Dictionary = take_skill_reply_full()
				_7802法术目标 = _取目标(r法.get("dst_ids", []), enemy_ids(), 法术目标数)
				step = 步_咏目标
			步_咏目标:
				var 咏目标数: int = mini(_7802咏数量, engine.order.size())
				if 咏目标数 <= 0:
					step = 步_水目标
					continue
				if not engine.has_reply():
					询问(player.id, 魔法入门, 0, 咏目标数, GConst.CardSource.Hand, [], 0, "",
						[], false, 1, -1, _全体角色id())
					return WAIT
				var r咏: Dictionary = take_skill_reply_full()
				_7802咏目标 = _取目标(r咏.get("dst_ids", []), _全体角色id(), 咏目标数)
				step = 步_水目标
			步_水目标:
				var 水目标数: int = mini(_7802水数量, engine.order.size())
				if 水目标数 <= 0:
					step = 步_7803触发
					continue
				if not engine.has_reply():
					询问(player.id, 魔法入门, 0, 水目标数, GConst.CardSource.Hand, [], 0, "",
						[], false, 1, -1, _全体角色id())
					return WAIT
				var r水: Dictionary = take_skill_reply_full()
				_7802水目标 = _取目标(r水.get("dst_ids", []), _全体角色id(), 水目标数)
				step = 步_7803触发
			步_7803触发:
				if _7802触发效果():
					# 分支 1：展示牌触发了效果 → 直接选 2 张牌弃掉（选中＋确定＝发动；取消＝不弃）
					if player.hand_cards.size() >= 2:
						step = 步_7803弃牌
						continue
					step = 步_7803第三次
					continue
				# 分支 2：展示牌未触发任何效果 → 可选额外 +1 法术行动
				step = 步_7803未触发
				continue
			步_7803弃牌:
				if not engine.has_reply():
					询问(player.id, MAGIC_BANG, 2, 0, GConst.CardSource.Hand, [], 0, "",
						[], true, 0)
					return WAIT
				var r弃2: Dictionary = take_skill_reply_full()
				var 选牌2: Array = r弃2.get("card_ids", [])
				# 空应答＝取消（7803 的弃 2 张是可选的）：不能走 _取手牌 的「不够就补手牌」口径，
				# 否则取消也会被强制弃 2 张
				if 选牌2.is_empty():
					_7802_7803弃牌.clear()
				else:
					_7802_7803弃牌 = _取手牌(player.id, 选牌2, 2)
				step = 步_7803第三次
				continue
			步_7803未触发:
				if not engine.has_reply():
					询问(player.id, MAGIC_BANG, 0, 0)
					return WAIT
				if take_skill_reply():
					_7802_7803额外行动 = true
				step = 步_7803第三次
			步_7803第三次:
				# 分支 3：本回合第 3 次【魔法入门】结算时（每回合只在该次数上问一次）
				if _本回合魔法入门次数 == 3:
					if not engine.has_reply():
						询问(player.id, MAGIC_BANG, 0, 0, GConst.CardSource.Hand, [], 0, "",
							[], true, 1)
						return WAIT
					if take_skill_reply():
						_7802_7803加宝石 = true
				step = 步_结算
			步_结算:
				# 先记「已结算」再结算：结算会压伤害 / 钩子并返回 URGENT，引擎重入本体时不能再来一次
				_7802已结算 = true
				return _结算魔法入门()
	return SUCCESS


## 7802 分步数据复位（每次新的技能行动）
func _初始化魔法入门() -> void:
	_7802启用友情羁绊 = false
	_7802友情角色.clear()
	_7802友情弃牌.clear()
	_7802展示牌.clear()
	_7802有法术牌 = false
	_7802咏数量 = 0
	_7802水数量 = 0
	_7802法术目标.clear()
	_7802咏目标.clear()
	_7802水目标.clear()
	_7802_7803弃牌.clear()
	_7802_7803额外行动 = false
	_7802_7803加宝石 = false
	_7802已结算 = false


## 7802 准备阶段：确定展示牌集合并算出三类效果的触发情况
func _准备7802展示() -> void:
	if _7802启用友情羁绊:
		for 项: Dictionary in _7802友情弃牌:
			_7802展示牌.append(int(项.get("card", -1)))
	else:
		# 普通流程：摸 1 张【强制】（不走 p_before_draw，不能被「摸牌前」响应改写）
		_7802展示牌 = engine.强制摸牌(player.id, 1, 魔法入门)
	for cid: int in _7802展示牌:
		var card: GCard = Data.get_card(cid)
		if card == null:
			continue
		if card.is_magic():
			_7802有法术牌 = true
		if card.fate_pattern_enum() == GConst.FatePattern.Cast:
			_7802咏数量 += 1
		if card.element_enum() == GConst.CardElement.Water:
			_7802水数量 += 1
	_广播7802展示()


## 把展示集合亮给全场（7805 时逐张按归属者展示；这两张牌在选定时已离手，这里只是亮牌）
func _广播7802展示() -> void:
	if _7802启用友情羁绊:
		for 项: Dictionary in _7802友情弃牌:
			var pid: int = int(项.get("pid", -1))
			var cid: int = int(项.get("card", -1))
			if pid < 0 or cid < 0:
				continue
			engine.broadcast(GConst.Msg.Card, {
				"type": GConst.CardMsgType.Show, "src_id": pid, "dst_id": pid,
				"card_ids": [cid], "is_real": true,
			})
	elif not _7802展示牌.is_empty():
		engine.broadcast(GConst.Msg.Card, {
			"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
			"card_ids": _7802展示牌, "is_real": true,
		})


## 7802 的「展示牌触发效果」判定：三组效果任意一组成立即算触发
func _7802触发效果() -> bool:
	return _7802有法术牌 or _7802咏数量 > 0 or _7802水数量 > 0


## 7802 结算：先播报 / 展示，再结算 7803，再造成伤害 / 治疗，最后压展示钩子（LIFO 先跑）
func _结算魔法入门() -> int:
	var 所有目标: Array[int] = []
	for pid: int in _7802法术目标:
		if not 所有目标.has(pid):
			所有目标.append(pid)
	for pid: int in _7802咏目标:
		if not 所有目标.has(pid):
			所有目标.append(pid)
	for pid: int in _7802水目标:
		if not 所有目标.has(pid):
			所有目标.append(pid)
	notice_skill(魔法入门, 所有目标)
	# 7805 的 2 张弃牌在选定时已离手（见 步_友情弃牌），这里统一入弃牌堆并写日志。
	# 放在结算做：这时不再向玩家提问，不会把「弃牌前拦截」的等待链夹在后续询问中间。
	if _7802启用友情羁绊:
		for 项: Dictionary in _7802友情弃牌:
			var pid2: int = int(项.get("pid", -1))
			var cid2: int = int(项.get("card", -1))
			if pid2 < 0 or cid2 < 0:
				continue
			engine.to_discard([cid2], {"owner": pid2, "source": "hand", "cause": 友情羁绊})
			engine._log_discard(pid2, [cid2], false)
	# 7803 分支 1：弃 2 张牌（无后续效果，按技能字面）。只处理还真实在手里的牌：
	# 逐张判断而不是整组 take_from_hand —— 组里有一张已离手时整组会失败，整组照样入弃会造成牌数重复。
	if not _7802_7803弃牌.is_empty():
		var 实际弃2: Array[int] = _离手入弃(player.id, _7802_7803弃牌, MAGIC_BANG)
		if not 实际弃2.is_empty():
			notice_skill(MAGIC_BANG, [player.id])
	# 7803 分支 2：额外 +1 法术行动（选中即进入，不再二次追问；上面已播报 7803）
	if _7802_7803额外行动:
		notice_skill(MAGIC_BANG, [player.id])
		player.add_action(GConst.ActionType.Magic, MAGIC_BANG, true, true)
	# 7803 分支 3：我方战绩区 +2 宝石
	if _7802_7803加宝石:
		notice_skill(MAGIC_BANG, [player.id])
		engine.set_team_gem(player.color, engine.team_gem[player.color] + 2)
	# 治疗：水系效果是「依序」里的最后一项。把它作为自定义钩子压在所有伤害状态之下，
	# 等伤害全部结算完再 +1 治疗 —— 否则先治疗再受伤时，治疗会白挡掉本该结算的伤害。
	if not _7802水目标.is_empty():
		engine.push(BattleEngine.SHook.new("p_jinguizhinv_水系治疗", {
			"player": player.id, "targets": _7802水目标.duplicate(),
		}, []))
	# 伤害：先压咏类伤害、再压法术伤害 —— 状态栈 LIFO，法术伤害先结算，符合技能「依序」
	for pid4: int in _倒序结算(_7802咏目标):
		engine.push_harm({
			"src": player.id, "dst": pid4, "point": 法术伤害值,
			"cause": 魔法入门, "type": GConst.HarmType.Magic, "is_active": false,
		})
	for pid5: int in _倒序结算(_7802法术目标):
		engine.push_harm({
			"src": player.id, "dst": pid5, "point": 法术伤害值,
			"cause": 魔法入门, "type": GConst.HarmType.Magic, "is_active": false,
		})
	# 7805：技能效果结束前，2 名角色各摸 1 张【强制】（不再并入展示集合）
	if _7802启用友情羁绊:
		for 项2: Dictionary in _7802友情弃牌:
			engine.强制摸牌(int(项2.get("pid", -1)), 1, 友情羁绊)
	# 展示牌钩子最后压：其他角色的「展示牌」响应先于伤害 / 行动结束结算
	if _7802启用友情羁绊:
		for 项3: Dictionary in _7802友情弃牌:
			var pid6: int = int(项3.get("pid", -1))
			var cid3: int = int(项3.get("card", -1))
			if pid6 >= 0 and cid3 >= 0:
				engine.push_show_hand(pid6, [cid3])
	elif not _7802展示牌.is_empty():
		engine.push_show_hand(player.id, _7802展示牌)
	engine._broadcast_game()
	return URGENT


# ============================================================
# 友情羁绊（7805）：改写 7802 的摸牌
# ============================================================
## 能否发动 7805：每回合一次、有真宝石、我方至少 2 名角色手里有牌
func _可发动友情羁绊() -> bool:
	if _本回合已用友情羁绊:
		return false
	if player.gem < 1:
		return false
	return _友情羁绊候选角色().size() >= 2


## 7805 可选的「我方角色」：同队、手里至少 1 张牌（可含自己）
func _友情羁绊候选角色() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		var p0: BattlePlayer = engine.p(pid)
		if p0 == null or p0.color != player.color:
			continue
		if p0.hand_cards.is_empty():
			continue
		out.append(pid)
	return out


# ============================================================
# 强予愿行（7804）：启动 / 必杀技 / 水晶
# ============================================================
func v_special_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != 强予愿行:
		return GConst.GE_INVALID_ACTION
	# 【水晶】费用：宝石可顶（get_energy）
	if player.get_energy() <= 0:
		return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_special_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != 强予愿行:
		return EMPTY_HANDLE
	if step == 0:
		_7804额外移除 = false
		_7804移除类型 = 0
		_7804目标 = -1
		step = 步_强予选星石
	while true:
		match step:
			步_强予选星石:
				# 一步到位：直接选 1 种星石＝做额外移除（取消＝不做额外移除，直接进结算）。
				# 战绩区没有星石时没有「额外移除」这一档，直接结算。
				if not _有战绩区星石():
					step = 步_强予结算
					continue
				if not engine.has_reply():
					询问(player.id, 强予愿行, 0, 0, GConst.CardSource.Hand, _星石选项(), 0, "",
						[], true, 0)
					return WAIT
				var r星: Dictionary = take_skill_reply_full()
				var 参数: Array = r星.get("args", [])
				var 类型: int = int(参数[0]) if not 参数.is_empty() else 0
				# 取消 / 超时（空 args）或选了不可用的星石 → 放弃额外移除：
				# 不替玩家默认扣一颗星石（见 A29；额外移除本来就是可选分支）。
				if not _星石可选(类型):
					_放弃强予额外移除()
					step = 步_强予结算
					continue
				_7804额外移除 = true
				_7804移除类型 = 类型
				step = 步_强予选角色
			步_强予选角色:
				var 候选: Array[int] = _其他角色id()
				if 候选.is_empty():
					_放弃强予额外移除()
					step = 步_强予结算
					continue
				if not engine.has_reply():
					询问(player.id, 强予愿行, 0, 1, GConst.CardSource.Hand, [], 0, "",
						[], true, 1, -1, 候选)
					return WAIT
				var r人: Dictionary = take_skill_reply_full()
				var 目标: Array[int] = []
				for 值: Variant in r人.get("dst_ids", []):
					var pid2: int = int(值)
					if 候选.has(pid2) and not 目标.has(pid2):
						目标.append(pid2)
						break
				# 取消 / 超时（空 dst）或没给出合法目标 → 放弃额外移除：
				# 不按候选顺序补第一名角色（见 A29：宁愿不额外移除，也不替玩家扣星石 / 改他人手牌）。
				if 目标.is_empty():
					_放弃强予额外移除()
					step = 步_强予结算
					continue
				_7804目标 = 目标[0]
				step = 步_强予结算
			步_强予结算:
				return _结算强予愿行()
	return SUCCESS


## 7804 结算：付 1 水晶 → 可选移除 1 星石 → 自己（与他人的）手牌调整为 4 张
func _结算强予愿行() -> int:
	# 费用：水晶可用宝石顶（remove_energy 先扣水晶再扣宝石）
	player.remove_energy(1)
	# 只有「星石类型选中且目标也选中」才真的额外移除（子询问取消 / 超时会走 _放弃强予额外移除）
	if _7804额外移除 and _7804目标 >= 0:
		if _7804移除类型 == 1 and engine.team_gem[player.color] > 0:
			engine.set_team_gem(player.color, engine.team_gem[player.color] - 1)
		elif _7804移除类型 == 2 and engine.team_crystal[player.color] > 0:
			engine.set_team_crystal(player.color, engine.team_crystal[player.color] - 1)
	player.boot_skill_used = true
	notice_skill(强予愿行, [_7804目标] if _7804目标 >= 0 else [player.id])
	var 挂起: bool = false
	# 先自己、再其他角色：不足强制摸、超出由牌主自己选弃（F9 调整手牌到）
	if engine.调整手牌到(player.id, 强予手牌数, 强予愿行, false):
		挂起 = true
	if _7804目标 >= 0 and engine.调整手牌到(_7804目标, 强予手牌数, 强予愿行, false):
		挂起 = true
	engine._broadcast_game()
	return URGENT if 挂起 else SUCCESS


## 战绩区有没有可移除的星石（宝石 / 水晶）
func _有战绩区星石() -> bool:
	return engine.team_gem[player.color] > 0 or engine.team_crystal[player.color] > 0


## 某类星石此刻能不能选：1＝宝石 / 2＝水晶
func _星石可选(类型: int) -> bool:
	if 类型 == 1:
		return engine.team_gem[player.color] > 0
	if 类型 == 2:
		return engine.team_crystal[player.color] > 0
	return false


## 两档星石固定下发，当前没有的置灰（不删项）
func _星石选项() -> Array:
	return [
		{"value": 1, "label": "宝石", "enabled": _星石可选(1)},
		{"value": 2, "label": "水晶", "enabled": _星石可选(2)},
	]


## 弃掉 7804 的「额外移除 1 星石」这一可选分支（子询问取消 / 超时 / 无合法选择时走这里）：
## 不扣星石、不调整其他角色，结算时只把自己的手牌调整到 4 张
func _放弃强予额外移除() -> void:
	_7804额外移除 = false
	_7804移除类型 = 0
	_7804目标 = -1


## 其他角色的 id（「将一名其他角色手牌调整为 4 张」）
func _其他角色id() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		if pid != player.id:
			out.append(pid)
	return out


# ============================================================
# 工具
# ============================================================
## 场上所有角色的 id（7802 的咏类 / 水系效果目标可以是任意角色，含自己）
func _全体角色id() -> Array[int]:
	var out: Array[int] = []
	for pid: int in engine.order:
		var p0: BattlePlayer = engine.p(pid)
		if p0 != null:
			out.append(pid)
	return out


## 把牌真正移出该玩家手牌并送进弃牌堆：只处理「还真实在手里」的牌（逐张判断）。
## 引擎的 take_from_hand 是整组原子操作 —— 组里有一张已经离手就一张都不移除，调用方若照样 to_discard
## 就会让同一张牌在弃牌堆出现两次、另一张还留在手里（R78 7805↔7803 的坑）。返回实际离手入弃的牌。
func _离手入弃(pid: int, cards: Array, cause: int, 播特效: bool = true) -> Array[int]:
	var 实际: Array[int] = []
	for 值: Variant in cards:
		var cid: int = int(值)
		if cid < 0 or 实际.has(cid):
			continue
		if engine.take_from_hand(pid, [cid]):
			实际.append(cid)
	if 实际.is_empty():
		return 实际
	engine.to_discard(实际, {"owner": pid, "source": "hand", "cause": cause})
	engine._log_discard(pid, 实际, 播特效)
	return 实际


## 取回复里的合法目标：去重、只保留 合法 里的；不足 n 个时按 合法 顺序补齐
func _取目标(ids: Array, 合法: Array[int], n: int) -> Array[int]:
	var out: Array[int] = []
	for 值: Variant in ids:
		if out.size() >= n:
			break
		var pid: int = int(值)
		if 合法.has(pid) and not out.has(pid):
			out.append(pid)
	for pid2: int in 合法:
		if out.size() >= n:
			break
		if not out.has(pid2):
			out.append(pid2)
	return out


## 取回复里的合法手牌：去重、只保留该玩家真实手牌；不足 n 张时按手牌顺序补齐（强制弃牌用）
func _取手牌(pid: int, ids: Array, n: int) -> Array[int]:
	var out: Array[int] = []
	var p0: BattlePlayer = engine.p(pid)
	if p0 == null or n <= 0:
		return out
	for 值: Variant in ids:
		if out.size() >= n:
			break
		var cid: int = int(值)
		if p0.has_discard_card(cid) and not out.has(cid):
			out.append(cid)
	for cid2: int in p0.hand_cards:
		if out.size() >= n:
			break
		if not out.has(cid2):
			out.append(cid2)
	return out


## 群伤压栈顺序：状态是栈（LIFO），按「正序结算顺序」的逆序压栈，自己 / 下家才会最先结算
func _倒序结算(目标: Array[int]) -> Array[int]:
	var 正序: Array[int] = 结算顺序(目标)
	var out: Array[int] = []
	for i: int in range(正序.size() - 1, -1, -1):
		out.append(正序[i])
	return out
