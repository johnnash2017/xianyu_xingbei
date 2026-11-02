extends 自检用例
## R106 怠惰少女（106）：10601 别烦我…… / 10602 让我躺平 / 10603 想用魔弹 /
## 10604 不想提炼 / 10605 再睡一下。
##
## 任务范围只有 role + test：角色表「脚本」列留给 DATA，用例里手动挂角色脚本。
## 覆盖：
##   - 数据：角色名 / 姓名 / 星数 / 五颗技能行 / 技能说明 / 脚本文件；
##   - 10601：技能栏（本人不选牌 / 目标，由右手边队友指定）；队友的指定目标询问不可取消（can_cancel=false），
##            硬提交非法目标 / 空回复按 A41「AI / 掉线按默认规则代选」取第一名合法对手并正常结算；
##            队友超时 → 引擎从下发的合法目标里代选并正常结算；
##            合法目标 → 目标【强制】摸 1 张、队友随机弃自己 1 张、
##            我方战绩区 +1 水晶；目标无法术牌 → 直接惩罚（目标再摸 1 张、队友 +1 治疗）；
##            目标有法术牌 → 询问目标弃牌，弃出则不惩罚、不弃 / 取消则惩罚；
##   - 10602：回合开始手牌 > 3 才询问；目标只能是队友（不含自己）；发动后队友 +1 治疗并跳过行动阶段，
##            引擎「本回合跳过行动阶段 / 来源」可由 p_turn_end 读到；手牌 = 3 / 取消 / 非自己回合 / 无队友时不询问；
##   - 10603：技能栏牌表（需两张彼此同系）/ 落点；校验（不同系 / 重复 / 不在手牌 / 非法落点 / 错误来源）；
##            真实结算：两张牌【展示】离手进弃牌堆、播报 10603、视为【魔弹】造成 2 点伤害；
##   - 10604：自己提炼被驳回；队友提炼后询问移除哪种星石（固定两项，不可用置灰），选宝石 / 水晶各自生效；
##            询问不可取消：空回复 / 硬发取消 / 超时都按第一种可移除的星石兜底（+1 宝石照给）；
##            战绩区为空时不再询问但仍 +1 宝石；
##   - 10605：跳过行动阶段后询问支付 1 真宝石并弃 1 张牌，队友 +1 治疗；治疗溢出 → 我方 +1 士气；
##            势力上限；无宝石 / 未跳过 / 取消 / 空手牌 / 非自己回合都不触发。
##
## 提示列 10601~10605 目前为空（DATA 任务补齐），用例不依赖提示文案。

const 角色脚本: GDScript = preload("res://scripts/battle/roles/role_daduoshaonv.gd")

## dummy 观察角色：记录「自己回合结束」时引擎的跳过行动阶段标记（10602 → 10605 的衔接）
class 跳过观察角色:
	extends BattleRole

	var 记录: Array = []

	func p_turn_end(ctx: Dictionary) -> int:
		if int(ctx.get("player", -1)) == 1:
			记录.append({
				"跳过": engine.本回合跳过行动阶段,
				"来源": engine.本回合跳过行动阶段来源,
			})
		return SUCCESS


var 引擎: BattleEngine = null
## 1 = 怠惰少女（蓝），2 = 队友（蓝），3 / 4 = 对手（红）
var 玩家1: BattlePlayer = null
var 玩家2: BattlePlayer = null
var 玩家3: BattlePlayer = null
var 玩家4: BattlePlayer = null
var 观察: 跳过观察角色 = null
var 角色: BattleRole = null
## send_cb 记录：{pid, msg, data}
var 发送记录: Array = []


func _init() -> void:
	名称 = "怠惰少女"


# ============================================================
# 工具
# ============================================================
## 卡库里第一张满足条件的非虚拟牌
func _取牌(条件: Callable, 排除: Array = []) -> GCard:
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual or 排除.has(c.id):
			continue
		if bool(条件.call(c)):
			return c
	return null


## n 张互不相同的非虚拟牌 id（只用来填手牌，不从牌堆里扣）
func _取牌组(数量: int, 排除: Array = []) -> Array[int]:
	var out: Array[int] = []
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual or 排除.has(c.id) or out.has(c.id):
			continue
		out.append(c.id)
		if out.size() >= 数量:
			break
	return out


## 把一张牌从牌堆 / 弃牌堆移到某人手里（模拟真实持有）
func _给牌(持有者: BattlePlayer, cid: int) -> void:
	引擎.deck.remove_one(cid)
	持有者.add_hand_cards([cid])


func _换手牌(p0: BattlePlayer, cards: Array) -> void:
	p0.hand_cards.clear()
	for c: Variant in cards:
		p0.hand_cards.append(int(c))


func _找技能(表: Array, id: int) -> Dictionary:
	for sk: Dictionary in 表:
		if int(sk.get("id", 0)) == id:
			return sk
	return {}


## 某玩家最近一次询问里指定 respond_id 的那条命令
func _取询问(pid: int, respond_id: int) -> Dictionary:
	for r: Dictionary in 引擎._最后询问.get(pid, {}).get("commands", []):
		if int(r.get("respond_id", 0)) == respond_id:
			return r
	return {}


## 给某玩家下发过几次指定 respond_id 的询问（按实际发送记录数）
func _询问次数(pid: int, respond_id: int) -> int:
	var n: int = 0
	for r: Dictionary in 发送记录:
		if int(r.get("msg", 0)) != GConst.Msg.CmdReq or int(r.get("pid", -1)) != pid:
			continue
		for c: Dictionary in (r.get("data", {}) as Dictionary).get("commands", []):
			if int(c.get("respond_id", 0)) == respond_id:
				n += 1
	return n


## 某技能号播报过几次
func _播报次数(技能号: int) -> int:
	var n: int = 0
	for r: Dictionary in 发送记录:
		if int(r.get("msg", 0)) != GConst.Msg.Skill:
			continue
		if int((r.get("data", {}) as Dictionary).get("skill_id", 0)) == 技能号:
			n += 1
	return n


## 发送记录里找一条满足条件的广播消息
func _找消息(消息类型: int, 条件: Callable) -> Dictionary:
	for r: Dictionary in 发送记录:
		if int(r.get("msg", 0)) != 消息类型:
			continue
		var 数据: Dictionary = r.get("data", {})
		if bool(条件.call(数据)):
			return 数据
	return {}


func _有错误输入(pid: int) -> bool:
	for r: Dictionary in 发送记录:
		if int(r.get("pid", -1)) == pid and int(r.get("msg", 0)) == GConst.Msg.ErrorInput:
			return true
	return false


func _重置战斗() -> void:
	引擎._states.clear()
	引擎._清空等待()
	引擎._最后询问.clear()
	引擎._最后行动命令.clear()
	引擎.phase = BattleEngine.Phase.Playing
	引擎.current_id = 1
	引擎.round_id = 1
	引擎.行动允许 = GConst.ActionType.Any
	引擎.行动可放弃 = false
	引擎.行动额外 = false
	引擎.行动额外来源 = 0
	引擎.行动禁特殊 = false
	引擎.skip_action_phase = false
	引擎.跳过行动阶段来源 = 0
	引擎.本回合跳过行动阶段 = false
	引擎.本回合跳过行动阶段来源 = 0
	引擎.额外回合玩家 = -1
	引擎.额外回合攻击加伤 = 0
	引擎.额外回合来源 = 0
	引擎.当前额外回合玩家 = -1
	引擎.当前额外回合攻击加伤 = 0
	引擎.测试跳过回合 = -1
	引擎.last_harm_cause = 0
	引擎.last_harm_type = 0
	引擎.team_morale = [引擎.士气上限(), 引擎.士气上限()]
	引擎.team_gem = [0, 0]
	引擎.team_crystal = [0, 0]
	发送记录.clear()
	for pid: int in 引擎.order:
		var p0: BattlePlayer = 引擎.p(pid)
		p0.hand_cards.clear()
		p0.cover_cards.clear()
		p0.basic_effects.clear()
		p0.additional_actions.clear()
		p0.cross_num = 0
		p0.cross_max = GConst.CROSS_MAX
		p0.energy_max = GConst.ENERGY_MAX
		p0.hand_cards_max = GConst.HAND_CARDS_MAX
		p0.set_gem(0)
		p0.set_crystal(0)
		p0.reset_action_counts()
		p0.boot_skill_used = false
	观察.记录.clear()


## 发动一次 10601（法术技能行动）：返回 run 之后的状态由调用方检查
func _发动10601() -> void:
	引擎.resolve_action(GConst.ActionType.MagicSkill, {
		"src_id": 1, "action_id": 10601, "card_ids": [], "dst_ids": [],
	})
	引擎.run()


## 让当前等待的玩家作一次技能询问回复
func _回复(pid: int, respond_id: int, args: Array, cards: Array = [], dsts: Array = []) -> void:
	引擎.on_message(pid, GConst.Msg.Respond, {
		"respond_id": respond_id, "src_id": pid,
		"args": args, "card_ids": cards, "dst_ids": dsts,
	})


# ============================================================
# 用例主体
# ============================================================
func 跑() -> void:
	await 等帧(1)

	# ---- 数据：角色 / 技能号 / 技能行 / 技能说明 / 脚本 ----
	检(str(Data.role_list.get(106, "")) == "怠惰少女", "106 号角色名不是「怠惰少女」")
	检(Data.role_personal_name(106) == "妮亚", "106 号角色姓名不是「妮亚」")
	检(absf(Data.role_star(106) - 3.0) < 0.01, "怠惰少女应是 3.0 星，实际 %s" % str(Data.role_star(106)))
	检(Data.role_skills(106) == [10601, 10602, 10603, 10604, 10605],
		"怠惰少女技能号不对：%s" % str(Data.role_skills(106)))
	检(ResourceLoader.exists("res://scripts/battle/roles/role_daduoshaonv.gd"), "怠惰少女的角色脚本文件不存在")
	for 技能号: int in [10601, 10602, 10603, 10604, 10605]:
		检(not GConst.技能行(技能号).is_empty(), "技能表里查不到 %d" % 技能号)
	检(GConst.技能号("技能#怠惰少女#别烦我……") == 10601, "【别烦我……】技能号应为 10601")
	检(GConst.技能号("技能#怠惰少女#让我躺平") == 10602, "【让我躺平】技能号应为 10602")
	检(GConst.技能号("技能#怠惰少女#想用魔弹") == 10603, "【想用魔弹】技能号应为 10603")
	检(GConst.技能号("技能#怠惰少女#不想提炼") == 10604, "【不想提炼】技能号应为 10604")
	检(GConst.技能号("技能#怠惰少女#再睡一下") == 10605, "【再睡一下】技能号应为 10605")
	var 技能说明: String = Data.role_skill_info(106)
	for 技能名: String in ["别烦我……", "让我躺平", "想用魔弹", "不想提炼", "再睡一下"]:
		检(技能说明.contains(技能名), "角色技能说明里缺【%s】：%s" % [技能名, 技能说明])

	# ---- 建引擎：1 / 2 同队，3 / 4 是对手；4 号挂观察角色 ----
	引擎 = BattleEngine.new()
	引擎.send_cb = func(pid: int, msg: int, data: Dictionary) -> void:
		发送记录.append({"pid": pid, "msg": msg, "data": data})
	引擎.add_player(1, GConst.BLUE, "怠惰")
	引擎.add_player(2, GConst.BLUE, "队友")
	引擎.add_player(3, GConst.RED, "对手甲")
	引擎.add_player(4, GConst.RED, "对手乙")
	引擎.start_with_roles({})
	玩家1 = 引擎.p(1)
	玩家2 = 引擎.p(2)
	玩家3 = 引擎.p(3)
	玩家4 = 引擎.p(4)
	玩家1.role_id = 106
	角色 = 角色脚本.new()
	角色.setup(玩家1, 引擎)
	玩家1.role = 角色
	观察 = 跳过观察角色.new()
	观察.setup(玩家4, 引擎)
	玩家4.role = 观察
	_重置战斗()

	_测试_10601()
	_测试_10602()
	_测试_10603()
	_测试_10604()
	_测试_10605()

	# 收尾
	引擎._states.clear()
	引擎._清空等待()
	引擎.send_cb = Callable()
	_重置战斗()


# ============================================================
# 10601 别烦我……
# ============================================================
func _测试_10601() -> void:
	# ---- 技能栏 / 校验 ----
	_重置战斗()
	var 栏: Array = 角色.available_skills()
	检(栏.size() == 2, "106 应有 10601 / 10603 两个主动技能，实际 %d 项：%s" % [栏.size(), str(栏)])
	var 项: Dictionary = _找技能(栏, 10601)
	检(not 项.is_empty(), "10601 应下发到技能栏")
	检(int(项.get("type", 0)) == GConst.ActionType.MagicSkill, "10601 应作为法术技能按钮下发")
	检(int(项.get("need_card", 0)) == 0 and int(项.get("need_target", 0)) == 0,
		"10601 本人不选牌 / 不选目标")
	检(bool(项.get("enabled", false)), "有右手边队友与对手时 10601 应可点")
	检(_找技能(栏, 10602).is_empty() and _找技能(栏, 10604).is_empty() and _找技能(栏, 10605).is_empty(),
		"10602 / 10604 / 10605 是被动/回合开始效果，不应占主动技能栏")
	# 场上没有队友时置灰、校验拒绝
	玩家2.color = GConst.RED
	var 项无队友: Dictionary = _找技能(角色.available_skills(), 10601)
	检(not 项无队友.is_empty() and not bool(项无队友.get("enabled", true)),
		"没有右手边队友时 10601 应置灰而不是消失")
	检(角色.v_magic_skill({"src_id": 1, "action_id": 10601}) != GConst.GE_SUCCESS,
		"没有队友时 10601 校验应拒绝")
	玩家2.color = GConst.BLUE
	检(角色.v_magic_skill({"src_id": 2, "action_id": 10601}) == GConst.GE_INVALID_PLAYERID,
		"10601 不是本人发动的应拒绝")
	检(角色.v_magic_skill({"src_id": 1, "action_id": 9999}) == GConst.GE_INVALID_ACTION,
		"错误的技能号应拒绝")
	检(角色.v_magic_skill({"src_id": 1, "action_id": 10601, "card_ids": [1]}) != GConst.GE_SUCCESS,
		"10601 本人提交牌应拒绝（目标由队友选）")
	检(角色.v_magic_skill({"src_id": 1, "action_id": 10601}) == GConst.GE_SUCCESS,
		"合法的 10601 应通过校验")

	# ---- 队友指定目标：不可取消，硬提交非法目标按默认规则代选第一名对手 ----
	_重置战斗()
	var 攻牌1: GCard = _取牌(func(c: GCard) -> bool: return c.is_attack())
	var 攻牌2: GCard = _取牌(func(c: GCard) -> bool: return c.is_attack(), [攻牌1.id] if 攻牌1 != null else [])
	var 攻牌3: GCard = _取牌(func(c: GCard) -> bool: return c.is_attack(),
		[攻牌1.id, 攻牌2.id] if 攻牌1 != null and 攻牌2 != null else [])
	检(攻牌1 != null and 攻牌2 != null and 攻牌3 != null, "卡库找不到足够的攻击牌")
	if 攻牌1 == null or 攻牌2 == null or 攻牌3 == null:
		return
	# 控制牌库顶：后面的【强制】摸牌都摸到攻击牌，保证目标手里没有法术牌
	引擎.deck.pile = [攻牌1.id, 攻牌2.id, 攻牌3.id]
	玩家2.hand_cards.clear()
	玩家3.hand_cards.clear()
	玩家4.hand_cards.clear()
	_换手牌(玩家1, _取牌组(3))
	_发动10601()
	检(引擎._await_id == 2, "10601 应由右手边队友 2 号指定目标，实际等待 %s" % str(引擎._await_id))
	var 询问队友: Dictionary = _取询问(2, 10601)
	检(not 询问队友.is_empty(), "队友 2 号应收到 10601 的询问")
	检((询问队友.get("dst_ids", []) as Array) == [3, 4], "队友可选的目标应是对手 3 / 4：%s"
		% str(询问队友.get("dst_ids", [])))
	检(bool(询问队友.get("is_skill", true)), "10601 的询问应是技能询问")
	检(询问队友.get("can_cancel", true) == false, "10601 的队友指定目标询问应不可取消（A41：AI / 掉线代选）")
	# 指定目标之前就应该先随机丢掉 1 张手牌（技能原文的顺序）
	检(玩家1.hand_cards.size() == 2,
		"队友指定目标之前就应先随机丢掉 1 张手牌，实际 %d" % 玩家1.hand_cards.size())
	# 队友的询问文案直接用整段技能说明
	检(str(询问队友.get("ask_text", "")).contains("右手边最近的队友随机丢弃"),
		"队友的询问文案应是整段技能说明：%s" % str(询问队友.get("ask_text", "")))
	# 指定目标时头像上不写任何提示（效果太长）
	检(not GConst.技能指示器.has(10601), "10601 指定目标时不应在头像上写任何提示")
	_回复(2, 10601, [1], [], [2])
	检(引擎.team_crystal[GConst.BLUE] == 1, "队友提交非法目标时应按默认规则代选第一名对手并照常 +1 水晶")
	检(玩家1.hand_cards.size() == 2, "代选后应照常随机弃掉自己 1 张手牌，实际 %d" % 玩家1.hand_cards.size())
	检(玩家3.hand_cards.size() == 2, "代选的目标（3 号）应强制摸 1 张 + 不弃惩罚再摸 1 张，实际 %d"
		% 玩家3.hand_cards.size())
	检(玩家2.cross_num == 1, "代选后应照常惩罚治疗（队友 +1 治疗）")
	检(玩家1.action_count() == 1, "正常结算的 10601 应记一次行动，实际 %d" % 玩家1.action_count())
	检(not _有错误输入(2), "队友选非法目标是代选兜底，不应报操作无效")

	# ---- 队友超时：不可取消 → 引擎从下发的合法目标里代选并正常结算 ----
	_重置战斗()
	引擎.deck.pile = [攻牌1.id, 攻牌2.id, 攻牌3.id]
	玩家2.hand_cards.clear()
	玩家3.hand_cards.clear()
	玩家4.hand_cards.clear()
	_换手牌(玩家1, _取牌组(3))
	_发动10601()
	检(引擎._await_id == 2, "10601 应由队友指定目标")
	# 超时兜底：引擎给「不可取消的技能询问」构造默认回复（args=[1] + 合法目标里随机一名）
	引擎.wait_deadline_ms = 1
	引擎.tick()
	检(引擎.team_crystal[GConst.BLUE] == 1, "队友超时后应代选目标并照常 +1 水晶")
	检(玩家1.hand_cards.size() == 2, "队友超时后也应随机弃掉自己 1 张手牌，实际 %d"
		% 玩家1.hand_cards.size())
	检(玩家3.hand_cards.size() + 玩家4.hand_cards.size() == 2,
		"超时代选的目标应强制摸 1 张 + 不弃惩罚再摸 1 张，实际 %d"
		% (玩家3.hand_cards.size() + 玩家4.hand_cards.size()))
	检(玩家2.cross_num == 1, "超时代选后应照常惩罚治疗（队友 +1 治疗）")

	# ---- 目标没有法术牌：强制摸牌 + 我方水晶 + 随机弃牌 + 惩罚 ----
	_重置战斗()
	引擎.deck.pile = [攻牌1.id, 攻牌2.id, 攻牌3.id]
	玩家3.hand_cards.clear()
	玩家2.hand_cards.clear()
	var 原手牌: Array = _取牌组(3)
	_换手牌(玩家1, 原手牌)
	_发动10601()
	检(引擎._await_id == 2, "10601 应由队友指定目标")
	_回复(2, 10601, [1], [], [3])
	# 目标无法术牌 → 立即结算惩罚，不再等目标回复
	检(引擎.team_crystal[GConst.BLUE] == 1, "我方战绩区应 +1 水晶")
	检(玩家1.hand_cards.size() == 2, "队友应随机弃掉自己 1 张手牌，实际剩 %d" % 玩家1.hand_cards.size())
	var 弃牌: int = -1
	for c: Variant in 原手牌:
		if not 玩家1.hand_cards.has(int(c)):
			弃牌 = int(c)
	检(弃牌 >= 0 and 引擎.deck.discard.has(弃牌), "随机弃掉的牌应进弃牌堆")
	检(玩家3.hand_cards.size() == 2, "目标先【强制】摸 1 张 + 不弃惩罚再摸 1 张，实际 %d"
		% 玩家3.hand_cards.size())
	检(玩家2.cross_num == 1, "目标不弃法术牌时队友应 +1 治疗")
	检(_播报次数(10601) == 1, "10601 应播报一次")

	# ---- 目标有法术牌：询问弃牌，弃出则不惩罚 ----
	_重置战斗()
	var 法术牌: GCard = _取牌(func(c: GCard) -> bool: return c.is_magic())
	检(法术牌 != null, "卡库找不到法术牌")
	if 法术牌 == null:
		return
	引擎.deck.pile = [攻牌1.id, 攻牌2.id, 攻牌3.id]
	玩家3.hand_cards.clear()
	玩家3.add_hand_cards([法术牌.id])
	玩家2.hand_cards.clear()
	_换手牌(玩家1, _取牌组(3))
	_发动10601()
	检(引擎._await_id == 2, "10601 应由队友指定目标")
	_回复(2, 10601, [1], [], [3])
	检(引擎._await_id == 3, "目标有法术牌时应等待它决定弃不弃，实际等待 %s" % str(引擎._await_id))
	var 询问目标: Dictionary = _取询问(3, 10601)
	检(not 询问目标.is_empty(), "目标 3 号应收到弃牌询问")
	检(str(询问目标.get("card_rule", "")) == "magic", "目标弃牌询问应限定法术牌")
	检((询问目标.get("card_ids", []) as Array).has(法术牌.id), "目标弃牌白名单应包含它的法术牌")
	_回复(3, 10601, [1], [法术牌.id])
	检(玩家3.hand_cards.size() == 1, "目标弃出法术牌后应只剩强制摸到的 1 张，实际 %d"
		% 玩家3.hand_cards.size())
	检(引擎.deck.discard.has(法术牌.id), "目标弃出的法术牌应进弃牌堆")
	检(玩家2.cross_num == 0, "目标弃出了法术牌则队友不加治疗")

	# ---- 目标取消弃牌：按不弃结算惩罚 ----
	_重置战斗()
	引擎.deck.pile = [攻牌1.id, 攻牌2.id, 攻牌3.id]
	玩家3.hand_cards.clear()
	玩家3.add_hand_cards([法术牌.id])
	玩家2.hand_cards.clear()
	_换手牌(玩家1, _取牌组(3))
	_发动10601()
	_回复(2, 10601, [1], [], [3])
	检(引擎._await_id == 3, "目标有法术牌时应等待它决定弃不弃")
	_回复(3, 10601, [0])
	检(玩家3.hand_cards.size() == 3, "目标取消弃牌应吃惩罚（初始 1 张法术牌 + 强制 1 张 + 惩罚 1 张）")
	检(玩家2.cross_num == 1, "目标取消弃牌时队友应 +1 治疗")

	# ---- 目标满手牌：强制摸 1 张先走超限弃牌 + 掉士气，再问「弃 1 张法术牌」----
	_重置战斗()
	引擎.deck.pile = [攻牌1.id, 攻牌2.id, 攻牌3.id]
	var 满手法术: GCard = 法术牌
	var 五张非法术: Array[int] = []
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual or c.is_magic() or c.id == 满手法术.id:
			continue
		五张非法术.append(c.id)
		if 五张非法术.size() >= 5:
			break
	检(五张非法术.size() == 5, "卡库找不到 5 张非法术牌")
	if 五张非法术.size() == 5:
		玩家3.hand_cards.clear()
		玩家3.add_hand_cards([满手法术.id])
		for cid: int in 五张非法术:
			玩家3.add_hand_cards([cid])
		玩家2.hand_cards.clear()
		_换手牌(玩家1, _取牌组(3))
		_发动10601()
		检(引擎._await_id == 2, "10601 应由队友指定目标")
		_回复(2, 10601, [1], [], [3])
		# 目标 6 张 + 强制摸 1 张 = 7 张 → 先走超限弃牌（不是直接问弃法术牌）
		检(引擎._await_id == 3 and int(引擎._pending_respond_id) == GConst.RespondType.Discard,
			"目标被摸到 7 张时应先走超限弃牌，实际等待 %s / 询问号 %s"
			% [str(引擎._await_id), str(引擎._pending_respond_id)])
		检(玩家3.hand_cards.size() == 7, "强制摸牌后目标应有 7 张手牌，实际 %d" % 玩家3.hand_cards.size())
		var 超限弃: Array = [五张非法术[0]]
		_回复(3, GConst.RespondType.Discard, [3, GConst.CAUSE_OVERLOAD, 1], 超限弃, [3])
		检(int(引擎.team_morale[GConst.RED]) == 14,
			"超限 1 张应掉 1 点士气，实际 %d" % int(引擎.team_morale[GConst.RED]))
		检(玩家3.hand_cards.size() == 6, "超限弃牌后目标应回到上限 6，实际 %d" % 玩家3.hand_cards.size())
		检(引擎._await_id == 3 and int(引擎._pending_respond_id) == 10601,
			"超限结算完应继续问目标弃 1 张法术牌，实际询问号 %s" % str(引擎._pending_respond_id))
		_回复(3, 10601, [1], [满手法术.id])
		检(玩家3.hand_cards.size() == 5, "再弃 1 张法术牌后目标应剩 5 张，实际 %d"
			% 玩家3.hand_cards.size())
		检(not 玩家3.hand_cards.has(满手法术.id), "弃出的法术牌应离开手牌")
		检(玩家2.cross_num == 0, "目标弃出法术牌则队友不加治疗")


# ============================================================
# 10602 让我躺平
# ============================================================
func _测试_10602() -> void:
	# 手牌 4：回合开始询问 → 治疗队友并跳过行动阶段
	_重置战斗()
	引擎.current_id = 1
	_换手牌(玩家1, _取牌组(4))
	引擎.push(BattleEngine.SCheckTurnStart.new())
	引擎.run()
	检(引擎._await_id == 1, "回合开始手牌 > 3 时应询问 10602，实际等待 %s" % str(引擎._await_id))
	var 询问: Dictionary = _取询问(1, 10602)
	检(not 询问.is_empty(), "10602 应下发询问")
	检((询问.get("dst_ids", []) as Array) == [2], "10602 的目标队友应只有 2 号（不含自己）：%s"
		% str(询问.get("dst_ids", [])))
	_回复(1, 10602, [1], [], [2])
	检(玩家2.cross_num == 1, "所选队友应 +1 治疗")
	检(观察.记录.size() == 1, "跳过后回合结束钩子应记录一次")
	if not 观察.记录.is_empty():
		检(bool(观察.记录[0].get("跳过", false)), "回合结束时应记录「本回合跳过行动阶段」")
		检(int(观察.记录[0].get("来源", -1)) == 10602, "跳过来源应为 10602")
	检(引擎.current_id == 2, "跳过行动阶段后应正常轮到 2 号，实际 %d" % 引擎.current_id)
	检(_播报次数(10602) == 1, "10602 应播报一次")

	# 手牌 = 3：不询问，正常进入行动阶段
	_重置战斗()
	引擎.current_id = 1
	_换手牌(玩家1, _取牌组(3))
	引擎.push(BattleEngine.SCheckTurnStart.new())
	引擎.run()
	检(引擎._await_id == 1 and 引擎._await_kind == GConst.Msg.Action,
		"手牌 = 3 时不应询问 10602，应直接进入行动阶段")
	检(观察.记录.is_empty(), "手牌 = 3 不应记录跳过行动阶段")

	# 取消：不治疗、不跳过
	_重置战斗()
	引擎.current_id = 1
	_换手牌(玩家1, _取牌组(4))
	引擎.push(BattleEngine.SCheckTurnStart.new())
	引擎.run()
	检(引擎._await_id == 1, "回合开始手牌 > 3 时应询问 10602")
	_回复(1, 10602, [0])
	检(玩家2.cross_num == 0, "取消 10602 不应加治疗")
	检(引擎._await_id == 1 and 引擎._await_kind == GConst.Msg.Action,
		"取消 10602 后应正常进入行动阶段")
	检(观察.记录.is_empty(), "取消 10602 不应跳过行动阶段")

	# 非法目标（选了对手）：不生效
	_重置战斗()
	引擎.current_id = 1
	_换手牌(玩家1, _取牌组(4))
	引擎.push(BattleEngine.SCheckTurnStart.new())
	引擎.run()
	_回复(1, 10602, [1], [], [3])
	检(玩家2.cross_num == 0 and 玩家3.cross_num == 0, "非法目标不应加治疗")
	检(引擎._await_id == 1 and 引擎._await_kind == GConst.Msg.Action,
		"非法目标后应正常进入行动阶段")

	# 不是自己的回合：不询问
	_重置战斗()
	引擎.current_id = 2
	_换手牌(玩家1, _取牌组(4))
	引擎.push(BattleEngine.SCheckTurnStart.new())
	引擎.run()
	检(_询问次数(1, 10602) == 0, "不是自己回合时不应询问 10602")

	# 没有队友：不询问
	_重置战斗()
	玩家2.color = GConst.RED
	玩家4.color = GConst.RED
	引擎.current_id = 1
	_换手牌(玩家1, _取牌组(4))
	引擎.push(BattleEngine.SCheckTurnStart.new())
	引擎.run()
	检(_询问次数(1, 10602) == 0, "没有队友时不应询问 10602")
	检(引擎._await_id == 1 and 引擎._await_kind == GConst.Msg.Action,
		"没有队友时应正常进入行动阶段")
	玩家2.color = GConst.BLUE
	玩家4.color = GConst.RED


# ============================================================
# 10603 想用魔弹
# ============================================================
func _测试_10603() -> void:
	# ---- 技能栏：两张彼此同系的牌才可点 ----
	_重置战斗()
	var 风1: GCard = _取牌(func(c: GCard) -> bool:
		return c.element_enum() == GConst.CardElement.Wind and c.card_name_enum() != GConst.CardName.Missile)
	var 风2: GCard = _取牌(func(c: GCard) -> bool:
		return c.element_enum() == GConst.CardElement.Wind and c.card_name_enum() != GConst.CardName.Missile,
		[风1.id] if 风1 != null else [])
	检(风1 != null and 风2 != null, "卡库找不到两张不同的风系牌")
	if 风1 == null or 风2 == null:
		return
	_给牌(玩家1, 风1.id)
	var 单张: Dictionary = _找技能(角色.available_skills(), 10603)
	检(not 单张.is_empty(), "10603 应下发到技能栏")
	检(not bool(单张.get("enabled", true)), "只有 1 张牌时 10603 应置灰")
	检((单张.get("cards", []) as Array).is_empty(), "凑不出同系两张时 10603 的牌表应为空")
	_给牌(玩家1, 风2.id)
	var 项: Dictionary = _找技能(角色.available_skills(), 10603)
	检(int(项.get("type", 0)) == GConst.ActionType.MagicSkill, "10603 应作为法术技能按钮下发")
	检(int(项.get("need_card", 0)) == 2 and int(项.get("need_target", 0)) == 1,
		"10603 应要求 2 张同系牌 + 1 名目标")
	检((项.get("cards", []) as Array).has(风1.id) and (项.get("cards", []) as Array).has(风2.id),
		"10603 的牌表应包含两张同系牌")
	检((项.get("targets", []) as Array) == [3], "10603 的落点应只有右手边最近的对手 3：%s"
		% str(项.get("targets", [])))
	检(bool(项.get("enabled", false)), "有两张同系牌与对手时 10603 应可点")

	# ---- 校验 ----
	var 火1: GCard = _取牌(func(c: GCard) -> bool: return c.element_enum() == GConst.CardElement.Fire)
	检(火1 != null, "卡库找不到火系牌")
	if 火1 == null:
		return
	_给牌(玩家1, 火1.id)
	检(角色.v_magic_skill({"src_id": 1, "action_id": 10603, "card_ids": [风1.id, 风2.id], "dst_ids": [3]})
		== GConst.GE_SUCCESS, "两张风系牌的 10603 应通过校验")
	检(角色.v_magic_skill({"src_id": 1, "action_id": 10603, "card_ids": [风1.id, 火1.id], "dst_ids": [3]})
		!= GConst.GE_SUCCESS, "不同系的两张牌应拒绝")
	检(角色.v_magic_skill({"src_id": 1, "action_id": 10603, "card_ids": [风1.id], "dst_ids": [3]})
		!= GConst.GE_SUCCESS, "只提交 1 张牌应拒绝")
	检(角色.v_magic_skill({"src_id": 1, "action_id": 10603, "card_ids": [风1.id, 风1.id], "dst_ids": [3]})
		!= GConst.GE_SUCCESS, "重复的同一张牌应拒绝")
	检(角色.v_magic_skill({"src_id": 1, "action_id": 10603, "card_ids": [风1.id, 风2.id], "dst_ids": [4]})
		!= GConst.GE_SUCCESS, "落点不在魔弹候选里应拒绝")
	检(角色.v_magic_skill({"src_id": 2, "action_id": 10603, "card_ids": [风1.id, 风2.id], "dst_ids": [3]})
		== GConst.GE_INVALID_PLAYERID, "不是本人发动的 10603 应拒绝")
	检(角色.v_magic_skill({"src_id": 1, "action_id": 9999, "card_ids": [风1.id, 风2.id], "dst_ids": [3]})
		== GConst.GE_INVALID_ACTION, "错误的技能号应拒绝")

	# ---- 真实结算：两张牌离手进弃牌堆 → 视为【魔弹】2 点伤害 ----
	_重置战斗()
	var 魔弹牌: GCard = _取牌(func(c: GCard) -> bool:
		return c.card_name_enum() == GConst.CardName.Missile)
	检(魔弹牌 != null, "卡库找不到【魔弹】牌")
	_给牌(玩家1, 风1.id)
	_给牌(玩家1, 风2.id)
	玩家3.hand_cards.clear()
	引擎.resolve_action(GConst.ActionType.MagicSkill, {
		"src_id": 1, "action_id": 10603, "card_ids": [风1.id, 风2.id], "dst_ids": [3],
	})
	引擎.run()
	检(引擎._await_id == 3, "10603 视为魔弹后应等待目标 3 应战，实际等待 %s" % str(引擎._await_id))
	检(玩家1.hand_cards.is_empty(), "10603 的两张发动牌应已离手")
	检(引擎.deck.discard.has(风1.id) and 引擎.deck.discard.has(风2.id), "10603 的两张牌应进弃牌堆")
	检(_播报次数(10603) == 1, "10603 应播报一次")
	if 魔弹牌 != null:
		var 用牌广播: Dictionary = _找消息(GConst.Msg.Card, func(d: Dictionary) -> bool:
			return int(d.get("as_card_id", 0)) == 魔弹牌.id and (d.get("card_ids", []) as Array).has(风1.id))
		检(not 用牌广播.is_empty(), "10603 应以 as_card_id=【魔弹】广播用牌")
	_回复(3, GConst.RespondType.Bullet, [GConst.Reattack.GiveUp])
	检(玩家3.hand_cards.size() == BattleEngine.MISSILE_BASE_POINT,
		"视为【魔弹】应造成 %d 点伤害（目标摸 %d 张），实际 %d 张"
		% [BattleEngine.MISSILE_BASE_POINT, BattleEngine.MISSILE_BASE_POINT, 玩家3.hand_cards.size()])
	检(引擎.last_harm_cause == GConst.CAUSE_MISSILE, "10603 的伤害来源应是【魔弹】")

	# ---- 响应传递：被【魔弹】问到时弃 2 张同系牌，视为魔弹继续传递 ----
	_重置战斗()
	_给牌(玩家1, 风1.id)
	_给牌(玩家1, 风2.id)
	发送记录.clear()
	# 1 号是当前持有者（被 3 号的魔弹指向），本轮已参与 3 / 1
	引擎.push(BattleEngine.SMissileAsk.new(1, 3, 2, true, [3, 1]))
	引擎.run()
	检(引擎._await_id == 1, "魔弹传递应先问 106，实际等待 %s" % str(引擎._await_id))
	var 传递问: Dictionary = _取询问(1, GConst.RespondType.Bullet)
	检(int(传递问.get("card_max", 1)) == 2, "106 被魔弹问到时选牌上限应放宽到 2：%s" % str(传递问))
	检(str(传递问.get("ask_text", "")).contains("同系"), "询问提示应说明可弃 2 张同系牌视为魔弹")
	检(角色.missile_relay_card_max() == 2, "手里有两张同系牌时 missile_relay_card_max 应为 2")
	检(角色.v_remissile_multi([风1.id, 风2.id]) == GConst.GE_SUCCESS,
		"两张同系牌的响应传递应通过校验")
	检(角色.v_remissile_multi([风1.id, 风1.id]) != GConst.GE_SUCCESS,
		"重复的同一张牌不能作为响应传递的两张牌")
	检(角色.v_remissile_multi([风1.id]) != GConst.GE_SUCCESS,
		"只交 1 张牌不能作为 10603 的响应传递")
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": GConst.RespondType.Bullet, "src_id": 1,
		"args": [GConst.Reattack.Attack], "card_ids": [风1.id, 风2.id], "dst_ids": [],
	})
	检(not 玩家1.has_hand_card(风1.id) and not 玩家1.has_hand_card(风2.id),
		"10603 响应传递的两张牌都应离手")
	检(引擎.deck.discard.has(风1.id) and 引擎.deck.discard.has(风2.id),
		"10603 响应传递的两张牌都应进弃牌堆")
	检(_播报次数(10603) == 1, "10603 响应传递应播报一次")


# ============================================================
# 10604 不想提炼
# ============================================================
func _测试_10604() -> void:
	# ---- 自己不能提炼 ----
	_重置战斗()
	引擎.team_gem[GConst.BLUE] = 2
	引擎.team_crystal[GConst.BLUE] = 1
	引擎.current_id = 1
	引擎.resolve_action(GConst.ActionType.Special, {
		"action_id": GConst.SpecialAction.Extract, "args": [1, 1], "dst_ids": [],
	})
	引擎.run()
	检(_有错误输入(1), "106 自己提炼应被驳回")
	检(引擎.team_gem[GConst.BLUE] == 2 and 引擎.team_crystal[GConst.BLUE] == 1,
		"被驳回的提炼不应移动战绩区星石")
	检(玩家1.gem == 0 and 玩家1.crystal == 0, "被驳回的提炼不应给个人能量")

	# ---- 队友提炼：询问移除哪种星石，选宝石 ----
	_重置战斗()
	引擎.team_gem[GConst.BLUE] = 2
	引擎.team_crystal[GConst.BLUE] = 1
	引擎.current_id = 2
	引擎.resolve_action(GConst.ActionType.Special, {
		"action_id": GConst.SpecialAction.Extract, "args": [1, 0], "dst_ids": [],
	})
	引擎.run()
	检(引擎._await_id == 1, "队友提炼后应询问 106 选移除哪种星石，实际等待 %s" % str(引擎._await_id))
	var 询问: Dictionary = _取询问(1, 10604)
	检(not 询问.is_empty(), "10604 应下发询问")
	var 询问args: Array = 询问.get("args", [])
	检(询问args.size() >= 6 and int(询问args[3]) == 2, "10604 应下发宝石 / 水晶两项固定选项：%s"
		% str(询问args))
	# 两项都可点时引擎不下发 option_enabled（缺省＝全可用）
	检(not 询问.has("option_enabled") or (询问.get("option_enabled", []) as Array) == [true, true],
		"战绩区两种星石都有时两项都应可点：%s" % str(询问.get("option_enabled", [])))
	检(询问.get("can_cancel", true) == false, "10604 的选星石询问应不可取消（A44：被动强制，只能选移除哪种）")
	_回复(1, 10604, [1])
	检(引擎.team_gem[GConst.BLUE] == 0, "选宝石后应移除我方 1 宝石，实际 %d" % 引擎.team_gem[GConst.BLUE])
	检(引擎.team_crystal[GConst.BLUE] == 1, "选宝石不应动我方水晶")
	检(玩家1.gem == 1, "10604 应 +1 个人宝石，实际 %d" % 玩家1.gem)
	检(玩家2.gem == 1, "提炼者应拿到提炼的 1 宝石")
	检(_播报次数(10604) == 1, "10604 应播报一次")

	# ---- 战绩区只有水晶：宝石项置灰，选水晶 ----
	_重置战斗()
	引擎.team_crystal[GConst.BLUE] = 1
	引擎.current_id = 2
	引擎.resolve_action(GConst.ActionType.Special, {
		"action_id": GConst.SpecialAction.Extract, "args": [0, 0], "dst_ids": [],
	})
	引擎.run()
	检(引擎._await_id == 1, "队友提炼后应询问 106 选移除哪种星石")
	var 询问2: Dictionary = _取询问(1, 10604)
	检(not 询问2.is_empty(), "10604 应下发询问")
	检((询问2.get("option_enabled", []) as Array) == [false, true],
		"只有水晶时宝石项应置灰、水晶项可点：%s" % str(询问2.get("option_enabled", [])))
	_回复(1, 10604, [2])
	检(引擎.team_crystal[GConst.BLUE] == 0, "选水晶后应移除我方 1 水晶")
	检(玩家1.gem == 1, "10604 应 +1 个人宝石")

	# ---- 战绩区为空：不询问但仍 +1 宝石 ----
	_重置战斗()
	引擎.current_id = 2
	引擎.resolve_action(GConst.ActionType.Special, {
		"action_id": GConst.SpecialAction.Extract, "args": [0, 0], "dst_ids": [],
	})
	引擎.run()
	检(_询问次数(1, 10604) == 0, "战绩区为空时不应询问移除星石")
	检(玩家1.gem == 1, "战绩区为空时 10604 仍应 +1 宝石")

	# ---- 询问不可取消：硬发取消 / 空回复按「第一种可移除的星石」兜底（+1 宝石照给） ----
	_重置战斗()
	引擎.team_gem[GConst.BLUE] = 1
	引擎.current_id = 2
	引擎.resolve_action(GConst.ActionType.Special, {
		"action_id": GConst.SpecialAction.Extract, "args": [0, 0], "dst_ids": [],
	})
	引擎.run()
	检(引擎._await_id == 1, "队友提炼后应询问 106 选移除哪种星石")
	_回复(1, 10604, [0])
	检(玩家1.gem == 1, "取消 / 空回复也应按 A44 +1 宝石，实际 %d" % 玩家1.gem)
	检(引擎.team_gem[GConst.BLUE] == 0, "取消 / 空回复应按第一种可移除星石（宝石）兜底，实际 %d"
		% 引擎.team_gem[GConst.BLUE])

	# ---- 超时：同样按第一种可移除的星石兜底 ----
	_重置战斗()
	引擎.team_crystal[GConst.BLUE] = 1
	引擎.current_id = 2
	引擎.resolve_action(GConst.ActionType.Special, {
		"action_id": GConst.SpecialAction.Extract, "args": [0, 0], "dst_ids": [],
	})
	引擎.run()
	检(引擎._await_id == 1, "队友提炼后应询问 106 选移除哪种星石")
	引擎.wait_deadline_ms = 1
	引擎.tick()
	检(玩家1.gem == 1, "超时兜底仍应 +1 宝石，实际 %d" % 玩家1.gem)
	检(引擎.team_crystal[GConst.BLUE] == 0, "超时兜底应按第一种可移除星石（水晶）移除，实际 %d"
		% 引擎.team_crystal[GConst.BLUE])


# ============================================================
# 10605 再睡一下
# ============================================================
## 直接触发一次「回合结束」钩子（10605 在这里检查跳过行动阶段）
func _触发回合结束(最后行动者: int) -> void:
	引擎.current_id = 最后行动者
	引擎.push(BattleEngine.SHook.new("p_turn_end", {
		"player": 最后行动者, "extra_turn": false, "attack_bonus": 0,
	}, []))
	引擎.run()


func _测试_10605() -> void:
	# ---- 主路径：支付 1 宝石、弃 1 张牌、队友 +1 治疗（刚好到上限，不算溢出） ----
	_重置战斗()
	玩家1.set_gem(1)
	_换手牌(玩家1, _取牌组(2))
	玩家2.cross_num = 1
	引擎.team_morale[GConst.BLUE] = 10
	引擎.本回合跳过行动阶段 = true
	引擎.本回合跳过行动阶段来源 = 10602
	_触发回合结束(1)
	检(引擎._await_id == 1, "跳过行动阶段后应询问 10605，实际等待 %s" % str(引擎._await_id))
	var 询问: Dictionary = _取询问(1, 10605)
	检(not 询问.is_empty(), "10605 应下发询问")
	检(int((询问.get("args", [0]) as Array)[0]) == 1, "10605 的询问应要求弃 1 张牌")
	var 弃牌: int = 玩家1.hand_cards[0]
	_回复(1, 10605, [1], [弃牌])
	检(玩家1.gem == 0, "10605 应支付 1 宝石，实际剩 %d" % 玩家1.gem)
	检(玩家1.hand_cards.size() == 1, "10605 应弃掉 1 张牌（2→1），实际 %d" % 玩家1.hand_cards.size())
	检(引擎.deck.discard.has(弃牌), "10605 弃掉的牌应进弃牌堆")
	检(玩家2.cross_num == 2, "队友应 +1 治疗（1→2），实际 %d" % 玩家2.cross_num)
	检(引擎.team_morale[GConst.BLUE] == 10, "治疗刚好到上限不算溢出，士气不应变化")
	检(_播报次数(10605) == 1, "10605 应播报一次")

	# ---- 治疗溢出：队友已满 → 我方 +1 士气 ----
	_重置战斗()
	玩家1.set_gem(1)
	_换手牌(玩家1, _取牌组(2))
	玩家2.cross_num = 2
	引擎.team_morale[GConst.BLUE] = 10
	引擎.本回合跳过行动阶段 = true
	_触发回合结束(1)
	检(引擎._await_id == 1, "跳过行动阶段后应询问 10605")
	_回复(1, 10605, [1], [玩家1.hand_cards[0]])
	检(玩家2.cross_num == 2, "已满时治疗不再增加")
	检(引擎.team_morale[GConst.BLUE] == 11, "队友治疗溢出应使我方 +1 士气，实际 %d"
		% 引擎.team_morale[GConst.BLUE])

	# ---- 士气已到上限：溢出不再加 ----
	_重置战斗()
	玩家1.set_gem(1)
	_换手牌(玩家1, _取牌组(2))
	玩家2.cross_num = 2
	引擎.team_morale[GConst.BLUE] = 引擎.士气上限()
	引擎.本回合跳过行动阶段 = true
	_触发回合结束(1)
	_回复(1, 10605, [1], [玩家1.hand_cards[0]])
	检(引擎.team_morale[GConst.BLUE] == 引擎.士气上限(), "士气不应超过上限")

	# ---- 只有水晶、没有真宝石：不询问 ----
	_重置战斗()
	玩家1.set_crystal(1)
	_换手牌(玩家1, _取牌组(2))
	引擎.本回合跳过行动阶段 = true
	_触发回合结束(1)
	检(_询问次数(1, 10605) == 0, "没有真宝石时不应询问 10605（水晶不能顶宝石）")
	检(玩家1.crystal == 1 and 玩家1.hand_cards.size() == 2, "没有宝石时不应扣水晶 / 弃牌")

	# ---- 没有跳过行动阶段：不询问 ----
	_重置战斗()
	玩家1.set_gem(1)
	_换手牌(玩家1, _取牌组(2))
	引擎.本回合跳过行动阶段 = false
	_触发回合结束(1)
	检(_询问次数(1, 10605) == 0, "没有跳过行动阶段时不应询问 10605")

	# ---- 取消：不扣宝石、不弃牌、不加治疗 ----
	_重置战斗()
	玩家1.set_gem(1)
	_换手牌(玩家1, _取牌组(2))
	玩家2.cross_num = 0
	引擎.本回合跳过行动阶段 = true
	_触发回合结束(1)
	检(引擎._await_id == 1, "跳过行动阶段后应询问 10605")
	_回复(1, 10605, [0])
	检(玩家1.gem == 1 and 玩家1.hand_cards.size() == 2, "取消 10605 不应扣宝石 / 弃牌")
	检(玩家2.cross_num == 0, "取消 10605 不应加治疗")

	# ---- 空手牌：没牌可弃，不询问 ----
	_重置战斗()
	玩家1.set_gem(1)
	引擎.本回合跳过行动阶段 = true
	_触发回合结束(1)
	检(_询问次数(1, 10605) == 0, "空手牌时不应询问 10605")
	检(玩家1.gem == 1, "空手牌时不应扣宝石")

	# ---- 不是自己的回合：不询问 ----
	_重置战斗()
	玩家1.set_gem(1)
	_换手牌(玩家1, _取牌组(2))
	引擎.本回合跳过行动阶段 = true
	_触发回合结束(2)
	检(_询问次数(1, 10605) == 0, "不是自己回合时不应询问 10605")
	检(玩家1.gem == 1, "不是自己回合时不应扣宝石")
