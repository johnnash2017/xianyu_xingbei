extends 自检用例
## R7 新角色（39 / 40 / 43 / 79 / 82 / 84 / 95）数据与核心契约自检。
##
## 本分支按需求「先功能后角色」，只做代码检查、未跑全量自检；本用例覆盖
## **不依赖完整对局流程**的部分：数据行、技能栏入口、区域/场卡初始化、关键钩子的契约。
## 完整流水线（逐技能真实结算）留给后续联调。

const 脚本表: Dictionary = {
	39: "res://scripts/battle/roles/role_shengtingjianchashi.gd",
	40: "res://scripts/battle/roles/role_xingzhuinvwu.gd",
	43: "res://scripts/battle/roles/role_shengdianqishi.gd",
	79: "res://scripts/battle/roles/role_shishenzhe.gd",
	82: "res://scripts/battle/roles/role_jiejieshi.gd",
	84: "res://scripts/battle/roles/role_zhoufushi.gd",
	95: "res://scripts/battle/roles/role_yijiaotu.gd",
}
const 技能表: Dictionary = {
	39: [3901, 3902, 3903, 3904, 3905, 3906, 3907],
	40: [4001, 4002, 4003, 4004, 4005, 4006, 4007, 4008, 4009],
	43: [4301, 4302, 4303, 4304, 4305, 4306, 4307],
	79: [7901, 7902, 7903, 7904, 7905, 7909, 7910, 7911, 7907, 7908],
	82: [8201, 8202, 8203, 8204, 8205, 8206, 8207],
	84: [8401, 8402, 8403, 8404, 8405],
	95: [9501, 9502, 9503, 9504, 9507, 9508, 9509, 9505, 9506],
}

var 引擎: BattleEngine = null
var 发送记录: Array = []


func 跑() -> void:
	名称 = "新角色（39/40/43/79/82/84/95）：数据与核心契约"
	_检数据()
	_检技能行()
	_检噬神者被动()
	# 噬神者的用例放在前面：后面的角色用例如果有既有问题失败了，
	# 也不会把「御刃 / 魔刃攻击入口」这几条本轮新修的断言一起跳过。
	await _检噬神者()
	await _检切换后复检()
	await _检咒符师()
	await _检结界师()
	await _检圣殿骑士()
	await _检圣庭检察士()
	await _检异教徒()
	await _检星坠女巫()


## 角色表/卡表/脚本文件都在
func _检数据() -> void:
	for 角色号: int in 脚本表.keys():
		var 路径: String = str(脚本表[角色号])
		检(ResourceLoader.exists(路径), "%d 的角色脚本不存在：%s" % [角色号, 路径])
		检(FileAccess.file_exists(路径), "%d 的角色脚本文件不存在：%s" % [角色号, 路径])
		检(not Data.role_name(角色号).is_empty(), "%d 没有角色名" % 角色号)
		检(Data.role_script(角色号) == 路径,
			"%d 角色表「脚本」列没挂上（%s）：%s" % [角色号, 路径, Data.role_script(角色号)])
	# 噬神者的两张特殊卡
	for 卡号: int in [1005, 1006]:
		var 卡: GCard = Data.get_card(卡号)
		检(卡 != null, "卡表缺 %d（魔刃/异刃）" % 卡号)
		if 卡 != null:
			检(卡.is_attack(), "%d 应是攻击牌" % 卡号)
			检(not 卡.is_virtual, "%d 不应是虚拟牌（它是真实攻击牌）" % 卡号)
			检(卡.element_enum() > 0, "%d 应有真实的当前系别" % 卡号)
			检(卡.fate_pattern_enum() == GConst.FatePattern.Blood, "%d 应是血命格" % 卡号)


## 技能表里 7 个角色的技能行齐全、有说明
func _检技能行() -> void:
	for 角色号: int in 技能表.keys():
		var 技能: Array = Data.role_skills(角色号)
		for 号: int in 技能表[角色号]:
			检(技能.has(号), "%d 的技能列表里缺 %d" % [角色号, 号])
			检(not GConst.skill_desc(号).is_empty(), "技能 %d 没有说明文案" % 号)


## 79 噬神者：三个专属被动各自成行（魔刃 / 异刃 / 渗蚀）；技能表里没有「刃」，
## 也没有 7912 / 7913 攻击入口（两张牌本身就是普通攻击牌）
func _检噬神者被动() -> void:
	var 技能: Array[int] = Data.role_skills(79)
	检(GConst.技能行(7906).is_empty(), "技能表里不应再有 7906「刃」")
	检(GConst.技能行(7912).is_empty() and GConst.技能行(7913).is_empty(),
		"技能表里不应再有 7912 / 7913 攻击入口")
	检(not 技能.has(7912) and not 技能.has(7913), "7912 / 7913 已删除，不应写进角色技能引用")
	for 号: int in [7909, 7910, 7911]:
		检(技能.has(号), "噬神者技能列表缺 %d" % 号)
	var 说明: String = Data.role_skill_info(79)
	检(说明.contains("【被动】魔刃："), "【魔刃】没有单独成行（找不到「【被动】魔刃：」）")
	检(说明.contains("【被动】异刃："), "【异刃】没有单独成行（找不到「【被动】异刃：」）")
	检(说明.contains("【被动】渗蚀："), "【渗蚀】没有单独成行（找不到「【被动】渗蚀：」）")
	检(not 说明.contains("【被动】刃："), "技能表里不应再有「刃」这个被动")
	检(not GConst.skill_desc(7909).contains("渗蚀") and not GConst.skill_desc(7909).contains("异刃；"),
		"【魔刃】的说明里混进了其它被动")
	检(not GConst.skill_desc(7910).contains("渗蚀") and not GConst.skill_desc(7910).contains("魔刃；"),
		"【异刃】的说明里混进了其它被动")


## 重建一个 4 人引擎并给 1 号挂上指定角色脚本
func _建引擎(角色号: int) -> BattleRole:
	引擎 = BattleEngine.new()
	发送记录.clear()
	引擎.send_cb = func(pid: int, msg: int, data: Dictionary) -> void:
		发送记录.append({"pid": pid, "msg": msg, "data": data})
	引擎.add_player(1, GConst.BLUE, "甲")
	引擎.add_player(2, GConst.RED, "乙")
	引擎.add_player(3, GConst.BLUE, "丙")
	引擎.add_player(4, GConst.RED, "丁")
	引擎.start_with_roles({})
	var 玩家: BattlePlayer = 引擎.p(1)
	var 脚本: GDScript = load(str(脚本表[角色号])) as GDScript
	var 角色: BattleRole = 脚本.new()
	# 先定身份、再 setup：BattleRole.setup 会按 player.role_id 从角色表建指示物 / 盖牌槽，
	# 顺序反了这些槽一个都建不出来（引擎侧 _assign_roles 也是先写 role_id 再 create/setup）。
	玩家.role_id = 角色号
	角色.setup(玩家, 引擎)
	玩家.role = 角色
	if 角色号 == 79:
		引擎.确保噬神者刃(1)
	引擎.phase = BattleEngine.Phase.Playing
	引擎.round_id = 1
	return 角色


## 84 咒符师：技能栏入口与费用校验；【念咒】把牌放进盖牌区当【妖力】
func _检咒符师() -> void:
	var 角色: BattleRole = _建引擎(84)
	var 玩家: BattlePlayer = 引擎.p(1)
	var 火法术: int = _找牌("火", "magic")
	var 水法术: int = _找牌("水", "magic")
	检(火法术 > 0 and 水法术 > 0, "找不到火/水系法术牌")
	# start_with_roles 会随机发 4 张开局手牌；不清空的话，手上碰巧有张水系牌时
	# 下面「没有水系牌时【冻天】应置灰」就会随机红。这里只放指定的那一张。
	玩家.hand_cards.clear()
	玩家.add_hand_cards([火法术])
	var 技能: Array = 角色.available_skills()
	检(技能.size() >= 2, "咒符师应有【火璃】【冻天】两个技能入口")
	var 火璃: Dictionary = _找技能(技能, 8401)
	检(not 火璃.is_empty() and bool(火璃.get("enabled", false)), "有火系牌时【火璃】应可点")
	var 冻天: Dictionary = _找技能(技能, 8402)
	检(not 冻天.is_empty() and not bool(冻天.get("enabled", true)), "没有水系牌时【冻天】应置灰")
	检(int(角色.v_magic_skill({"src_id": 1, "action_id": 8401,
		"card_ids": [水法术], "dst_ids": [2]})) != GConst.GE_SUCCESS,
		"【火璃】拿水系牌当费用应被拒")
	检(int(角色.v_magic_skill({"src_id": 1, "action_id": 8401,
		"card_ids": [火法术], "dst_ids": [2]})) == GConst.GE_SUCCESS,
		"【火璃】用火系牌 + 合法目标应通过校验")
	# 【念咒】：放 1 张手牌进盖牌区当【妖力】
	玩家.add_cover_cards([水法术])
	玩家.记盖牌标记(水法术, false, "妖力")
	检(玩家.盖牌按标记("妖力").has(水法术), "【妖力】应能在盖牌区按标记检索到")


## 82 结界师：结界仪式放 2 张面朝上的盖牌 +1 祭；荒神之力对同系攻击 +1
func _检结界师() -> void:
	var 角色: BattleRole = _建引擎(82)
	var 玩家: BattlePlayer = 引擎.p(1)
	var 两张: Array = _找两张牌("火")
	检(两张.size() == 2, "找不到两张火系牌")
	for c: int in 两张:
		玩家.add_hand_cards([c])
	检(int(角色.v_magic_skill({"src_id": 1, "action_id": 8201, "card_ids": 两张})) == GConst.GE_SUCCESS,
		"【结界仪式】2 张手牌应通过校验")
	引擎.add_cover(1, 两张, 1, 8201, true, "结界")
	检(玩家.盖牌按标记("结界").size() == 2, "【结界】应放进盖牌区并打上标记")
	检(玩家.公开盖牌牌面().size() == 2, "【结界】应面朝上（公开牌面）")
	玩家.add_token(0, 1)
	检(玩家.token_num(0) == 1, "【祭】应加进 0 号指示物")
	# 荒神之力：火系攻击 +1
	var harm: Dictionary = {"src": 2, "dst": 1, "point": 1, "type": GConst.HarmType.Attack}
	var 火攻击: int = _找牌("火", "attack")
	var ctx: Dictionary = {"src": 2, "dst": 1, "is_active": true, "card_id": 火攻击, "harm": harm}
	角色.p_timeline_2_hit(ctx)
	检(int(harm.get("point", 0)) == 2, "【荒神之力】应让同系攻击伤害 +1：%d" % int(harm.get("point", 0)))
	# 卡表#0 是合法牌、座位 0 是合法人：琉璃境不能把 0 当「没有」
	# 先把上面塞满的两张【结界】收走，留出盖牌位（结界师只有 2 个结界槽）
	引擎.remove_cover(1, 两张, 1, 8201)
	角色._mod_step = 5
	角色._琉璃_step = 4
	角色._琉璃待放 = 0
	角色._琉璃弃牌人 = 0
	引擎._reply = {"args": [1], "card_ids": [], "dst_ids": [], "respond_id": 0}
	引擎._has_reply = true
	引擎._await_state = 引擎._当前状态
	检(角色.p_jie_jie_ask({"player": 1}) == BattleRole.URGENT,
		"琉璃境：0 号牌也要能放进盖牌区作为【结界】")
	检(玩家.盖牌按标记("结界").has(0), "0 号牌应作为【结界】进盖牌区")
	# 不做成结界时：0 号牌必须进弃牌堆（不能被 > 0 吞掉而凭空消失）
	角色._mod_step = 5
	角色._琉璃待放 = 0
	角色._琉璃弃牌人 = 0
	引擎._reply = {"args": [0], "card_ids": [], "dst_ids": [], "respond_id": 0}
	引擎._has_reply = true
	引擎._await_state = 引擎._当前状态
	角色.p_jie_jie_ask({"player": 1})
	检(引擎.deck.discard.has(0), "琉璃境：0 号牌不当作结界时必须进弃牌堆")


## 43 圣殿骑士：治疗上限 -1；神威让本次攻击无法应战并禁止双方获得治疗
func _检圣殿骑士() -> void:
	var 角色: BattleRole = _建引擎(43)
	var 玩家: BattlePlayer = 引擎.p(1)
	检(玩家.cross_max == GConst.CROSS_MAX - 1,
		"【神选者】应让治疗上限 -1：%d" % 玩家.cross_max)
	玩家.add_token(0, 2)
	检(玩家.token_num(0) == 2, "【圣印】应能加到 2")
	var harm: Dictionary = {"src": 1, "dst": 2, "point": 1, "type": GConst.HarmType.Attack}
	var ctx: Dictionary = {"src": 1, "dst": 2, "is_active": true, "card_id": _找牌("火", "attack"),
		"harm": harm, "hit_rate": GConst.HitRate.Normal, "can_light": true}
	# 第一次询问：神威
	角色.p_timeline_1(ctx)
	检(引擎._await_id == 1, "【神威】应问发动者")
	# 手工驱动钩子时不能走引擎的 on_message：它会把回复交给状态机（这里没有正在跑的状态），
	# 引擎会顺手继续跑自己的回合流程，回复到不了钩子上。按「引擎重入钩子时能看到回复」的状态直接喂。
	引擎._reply = {"respond_id": 4302, "src_id": 1, "args": [1], "card_ids": [], "dst_ids": []}
	引擎._has_reply = true
	引擎._await_state = 引擎._当前状态
	# 钩子返回 WAIT 后，真实流程是「引擎收到回复 → 重新进入同一钩子把回复取走并结算」，
	# 这里按同样的方式重入一次。
	角色.p_timeline_1(ctx)
	检(int(ctx.get("hit_rate", 0)) == GConst.HitRate.NoReattack,
		"【神威】应把本次攻击设成无法应战")
	检(bool(ctx.get("can_light", true)) == false, "【神威】应关掉【圣光】")
	检(玩家.无法获得治疗(), "【神威】应让发动者本回合无法获得治疗")
	检(引擎.p(2).无法获得治疗(), "【神威】应让攻击目标本回合无法获得治疗")
	检(玩家.token_num(0) == 0, "【神威】应移除 2 点【圣印】")


## 39 圣庭检察士：开局拥有【异端裁决所】；裁决论定让裁决所 +1 治疗并 +1 水晶
func _检圣庭检察士() -> void:
	var 角色: BattleRole = _建引擎(39)
	var 玩家: BattlePlayer = 引擎.p(1)
	检(引擎.有场卡("异端裁决所"), "【狂信徒】开局应放下【异端裁决所】")
	检(int(引擎.取场卡("异端裁决所").get("owner", -1)) == 1, "【异端裁决所】的拥有者应是 1 号")
	检(int(引擎.取场卡("异端裁决所").get("counter_max", 0)) == 4,
		"【异端裁决所】的治疗上限应是 4：%s" % str(引擎.取场卡("异端裁决所").get("counter_max", 0)))
	var 水晶前: int = 玩家.crystal
	角色.p_heal_overflow({"player": 3, "overflow": 1, "before": 2, "amount": 2, "src": 1})
	检(int(引擎.取场卡("异端裁决所").get("counter", 0)) == 1,
		"【裁决论定】应给裁决所 +1 治疗")
	检(玩家.crystal == 水晶前 + 1, "【裁决论定】应让发动者 +1 水晶")
	# 【裁决者】是启动技：必须作为 SpecialSkill 下发，且不能有法术技能入口
	var 裁决项: Dictionary = {}
	for 项: Dictionary in 角色.available_skills():
		if int(项.get("id", 0)) == 3906:
			裁决项 = 项
	检(int(裁决项.get("type", 0)) == GConst.ActionType.SpecialSkill,
		"【裁决者】应作为启动技（SpecialSkill）下发")
	检(角色.v_magic_skill({"action_id": 3906, "src_id": 1}) == GConst.GE_INVALID_ACTION,
		"【裁决者】不应有法术技能入口")
	# 【狂信徒】攻击行动结束时由玩家指定 1 名「目标角色」+1 治疗 ——
	# 原文「目标角色」＝场上任意一名角色（自己 / 队友 / 对手都能选），不是自动给本次攻击目标加
	var 行动ctx: Dictionary = {"player": 1, "kind": "attack"}
	角色.p_action_end(行动ctx)
	检(引擎._await_id == 1, "【狂信徒】攻击行动结束应问发动者指定目标角色")
	检(引擎._pending_skill_need_target == 1, "【狂信徒】应要求选 1 名目标角色")
	检(not 引擎._pending_skill_can_cancel, "【狂信徒】选目标不能取消（原文没有「可」）")
	检(引擎._pending_skill_targets.size() == 4,
		"【狂信徒】目标白名单应是场上全部角色：%d" % 引擎._pending_skill_targets.size())
	var 攻击目标治疗: int = 引擎.p(2).cross_num
	var 指定治疗: int = 引擎.p(3).cross_num
	# 手工驱动钩子时不能走 on_message（它会把回复交给状态机），
	# 按「引擎重入钩子时能看到回复」的状态直接喂一条「指定 3 号」的回复
	引擎._reply = {"respond_id": 3901, "src_id": 1, "args": [1], "card_ids": [], "dst_ids": [3]}
	引擎._has_reply = true
	引擎._await_state = 引擎._当前状态
	角色.p_action_end(行动ctx)
	检(引擎.p(3).cross_num == 指定治疗 + 1, "【狂信徒】应给指定的 3 号 +1 治疗")
	检(引擎.p(2).cross_num == 攻击目标治疗, "【狂信徒】不应自动给本次攻击目标加治疗")
	# 场卡【异端裁决所】的状态图标：计数像指示物一样写在图标上；说明显示【庇护领域】(3905)
	var 战斗界面脚本: GDScript = load("res://scripts/ui/battle_mobile.gd")
	var 显示项: Dictionary = 战斗界面脚本.场卡状态项("异端裁决所",
		{"id": "异端裁决所", "counter": 2, "counter_max": 4})
	检(int(显示项.get("count", -1)) == 2, "【异端裁决所】应在图标上显示计数：%s" % str(显示项))
	检(int(显示项.get("被动技能", -1)) == 3905, "【异端裁决所】的说明应走【庇护领域】3905")
	检(str(显示项.get("desc", "")) == GConst.skill_desc(3905),
		"【异端裁决所】的说明应是【庇护领域】的技能说明")
	检(str(显示项.get("tip", "")).begins_with("异端裁决所 2/4"),
		"【异端裁决所】的悬停提示应写成「当前/4」：%s" % str(显示项.get("tip", "")))
	# 计数为 0 也写数字（与指示物一致），否则玩家看不出还能不能发动【庇护领域】
	var 零计数项: Dictionary = 战斗界面脚本.场卡状态项("异端裁决所",
		{"id": "异端裁决所", "counter": 0, "counter_max": 4})
	检(int(零计数项.get("count", -1)) == 0, "【异端裁决所】计数为 0 时也应在图标上写 0")
	检(str(零计数项.get("tip", "")).begins_with("异端裁决所 0/4"),
		"【异端裁决所】计数为 0 时提示也应是 0/4：%s" % str(零计数项.get("tip", "")))
	# 超过上限不再涨（裁决论定 / 裁决者加到 4 就打住）
	检(引擎.场卡加计数("异端裁决所", 10) == 4, "【异端裁决所】的治疗点数应封顶在 4")
	# 原先按卡号写死的三张场卡改走同一张配置表，行为不能变
	var 雷项: Dictionary = 战斗界面脚本.场卡状态项("天雷劫火",
		{"id": "天雷劫火", "counter": 0, "counter_max": 0})
	检(int(雷项.get("被动技能", -1)) == 9507, "【天雷劫火】的说明仍应走 9507")
	检(int(雷项.get("count", 0)) == -1, "【天雷劫火】没配计数时不应在图标上写数字")

	# ---- 【恩典神授】照【冒险者天堂】：提炼时把星石直接交给目标队友，代价在结算时扣 ----
	角色 = _建引擎(39)
	玩家 = 引擎.p(1)
	引擎.set_team_gem(GConst.BLUE, 2)
	检(角色.v_extract([3903, 0, 0, 1, 0, 0, 1, 0], 2, 0, [1]) == GConst.GE_INVALID_PLAYERID,
		"【恩典神授】的目标必须是非自己的队友")
	检(角色.v_extract([1, 0], 2, 0, []) == BattleRole.V_NOT_OVERRIDE,
		"常规提炼（头位不是 3903）应退回通用校验")
	检(角色.v_extract([3903, 0, 0, 1, 0, 0, 1, 0], 2, 0, [3]) == GConst.GE_INVALID_ACTION,
		"代价付不起时【恩典神授】应驳回（此时裁决所 0、全队治疗 0）")
	检(角色.v_extract([3903, 0, 0, 1, 0, 0, 1, 7], 2, 0, [3]) == GConst.GE_INVALID_ACTION,
		"未知的代价类型应驳回")
	# 给够代价：裁决所 3 治疗
	引擎.场卡加计数("异端裁决所", 3)
	# 代价按「玩家选的那一种」复核：选了「我方合计 2 治疗」就要求治疗够，不能拿裁决所顶
	检(角色.v_extract([3903, 0, 0, 1, 0, 0, 1, 1], 2, 0, [3]) == GConst.GE_INVALID_ACTION,
		"选「我方合计 2 治疗」作代价时，全队治疗 0 应驳回")
	检(角色.v_extract([3903, 0, 0, 1, 0, 0, 1, 0], 2, 0, [3]) == GConst.GE_SUCCESS,
		"裁决所 3 治疗时应可付「裁决所 3 治疗」这一种代价")
	# 让 1 号成为当前行动者（建引擎后可能已经轮到别人），并放行特殊行动
	引擎.current_id = 1
	引擎.行动允许 = GConst.ActionType.Any
	# 手里只留一张圣类命格的牌：打完能走「展示 → 1 点法术伤害」那条
	var 圣牌: int = -1
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.fate_pattern_enum() == GConst.FatePattern.Holy:
			圣牌 = c.id
			break
	检(圣牌 >= 0, "卡库里应有圣类命格的牌")
	玩家.hand_cards.clear()
	玩家.add_hand_cards([圣牌])
	引擎.resolve_action(GConst.ActionType.Special, {
		"action_id": GConst.SpecialAction.Extract,
		"dst_ids": [3], "card_ids": [], "args": [3903, 0, 0, 2, 0, 0, 2, 0],
	})
	引擎.run()
	检(引擎.p(3).gem == 2, "【恩典神授】应把提炼出的星石直接交给目标队友：%d" % 引擎.p(3).gem)
	检(玩家.gem == 0, "【恩典神授】不该给自己留星石：%d" % 玩家.gem)
	检(引擎.team_gem[GConst.BLUE] == 0, "战绩区应扣掉提炼的 2 宝石：%d" % 引擎.team_gem[GConst.BLUE])
	检(int(引擎.取场卡("异端裁决所").get("counter", 0)) == 0,
		"代价应扣裁决所 3 治疗：%d" % int(引擎.取场卡("异端裁决所").get("counter", 0)))
	检(引擎._await_id == 1 and 引擎._pending_respond_id == 3903,
		"提炼结算完应问「弃 1 张牌」：等待 %s / 询问号 %s"
		% [str(引擎._await_id), str(引擎._pending_respond_id)])
	# 弃那张圣牌：展示 + 对目标对手 1 点法术伤害
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 3903, "src_id": 1, "args": [], "card_ids": [圣牌], "dst_ids": [],
	})
	引擎.run()
	检(引擎.deck.discard.has(圣牌), "【恩典神授】弃掉的牌应进弃牌堆")
	检(引擎._await_id == 1 and 引擎._pending_respond_id == 3903
		and 引擎._pending_skill_need_target == 1, "圣类弃牌后应问目标对手")
	引擎.on_message(1, GConst.Msg.Respond, {
		"respond_id": 3903, "src_id": 1, "args": [], "card_ids": [], "dst_ids": [2],
	})
	引擎.run()
	var 有伤害: bool = false
	for r: Dictionary in 发送记录:
		if int(r["msg"]) != GConst.Msg.Hurt:
			continue
		var d: Dictionary = r["data"]
		if int(d.get("dst_id", -1)) == 2 and int(d.get("hurt", 0)) == 1:
			有伤害 = true
	检(有伤害, "【恩典神授】展示圣牌后应对目标对手造成 1 点法术伤害")

	# ---- 代价类型 1：由玩家指定从哪几名我方角色身上扣（1 人 2 点 / 2 人各 1 点）----
	角色 = _建引擎(39)
	玩家 = 引擎.p(1)
	引擎.set_team_gem(GConst.BLUE, 2)
	引擎.p(3).add_cross_num(2)      # 3 号队友有 2 点治疗
	检(角色.v_extract([3903, 0, 0, 1, 0, 0, 1, 1, 1, 1, 2, 0, 0], 2, 0, [3])
		== GConst.GE_INVALID_ACTION, "治疗不够扣的目标不能当代价目标（1 号此时没有治疗）")
	检(角色.v_extract([3903, 0, 0, 1, 0, 0, 1, 1, 1, 2, 2, 0, 0], 2, 0, [3])
		== GConst.GE_INVALID_ACTION, "敌方角色不能当治疗代价目标")
	检(角色.v_extract([3903, 0, 0, 1, 0, 0, 1, 1, 1, 3, 2, 0, 0], 2, 0, [3])
		== GConst.GE_SUCCESS, "3 号有 2 点治疗时应可通过「单人扣 2 点」")
	检(角色.v_extract([3903, 0, 0, 1, 0, 0, 1, 1, 2, 3, 1, 3, 1], 2, 0, [3])
		== GConst.GE_INVALID_ACTION, "同一名角色不能当两个代价目标")
	# 真跑一次：星石交给 3 号，代价也从 3 号扣 2 点
	玩家.hand_cards.clear()
	引擎.current_id = 1
	引擎.行动允许 = GConst.ActionType.Any
	引擎.resolve_action(GConst.ActionType.Special, {
		"action_id": GConst.SpecialAction.Extract,
		"dst_ids": [3], "card_ids": [],
		"args": [3903, 0, 0, 2, 0, 0, 2, 1, 1, 3, 2, 0, 0],
	})
	引擎.run()
	检(引擎.p(3).cross_num == 0, "代价应从指定的 3 号扣掉 2 点治疗：%d" % 引擎.p(3).cross_num)
	检(引擎.p(3).gem == 2, "星石应交给 3 号队友：%d" % 引擎.p(3).gem)

	# ---- 客户端上下游：3903 的指示器只服务「提炼分星石」那一步 ----
	# （以前同一个技能号后面的「弃 1 张牌」「选目标打伤害」也被当成分配型：确定永远灰着、
	#   对手头像被「仅队友」挡住，两处都是实战报出来的）
	var 窗: Control = load("res://scripts/ui/battle_mobile.gd").new()
	窗.set("_mode", 3)
	窗.set("_skill_ask_id", 3903)
	窗.set("_提炼阶段", 4)
	检(not (窗.call("_分配配置") as Dictionary).is_empty(),
		"提炼分星石那一步应认 3903 的分配规则")
	窗.set("_提炼阶段", 0)
	检((窗.call("_分配配置") as Dictionary).is_empty(),
		"3903 的弃牌 / 伤害询问不能被当成分配型")
	# 弃牌询问：选了 1 张牌就能点「确定」
	var 一手牌: Array[int] = [1]
	var 空目标: Array[int] = []
	var 对手表: Array[int] = [2]
	var 队友表: Array[int] = [3]
	窗.set("_是技能询问", true)
	窗.set("_skill_ask_need_card", 1)
	窗.set("_skill_ask_need_target", 0)
	窗.set("_sel_cards", 一手牌)
	窗.set("_本地选项阶段", 0)
	检(not bool(窗.call("_确定不可用")), "弃 1 张牌后「确定」应可用")
	# 伤害目标询问：服务端给的白名单里的对手应可点（不能被「仅队友」挡住）
	窗.set("_skill_ask_need_target", 1)
	窗.set("_skill_targets", 对手表)
	检(bool(窗.call("_玩家可选", 2)), "伤害目标询问里白名单内的对手应可点")
	# 选代价那一步（mode 6）：只让点「我方有治疗」的白名单角色（口径同【天使祝福】点头像选目标）
	窗.set("_mode", 6)
	窗.set("_本地选项阶段", 6)
	窗.set("_skill_targets", 空目标)
	检(not bool(窗.call("_玩家可选", 3)), "没选「我方合计 2 治疗」时不该让点头像")
	窗.set("_skill_targets", 队友表)
	检(bool(窗.call("_玩家可选", 3)), "选代价目标时白名单内的我方角色应可点")
	检(not bool(窗.call("_玩家可选", 2)), "选代价目标时白名单外的角色不可点")
	# 选中「我方合计 2 治疗」但一个头像都没点时，「确定」应灰着
	var 代价参数: Array[int] = [1]
	窗.set("_二级选中", 0)
	窗.set("_已选参数", 代价参数)
	窗.set("_sel_players", 空目标)
	检(bool(窗.call("_恩典代价选人中")), "选中「我方合计 2 治疗」后应进入选代价目标状态")
	检(bool(窗.call("_确定不可用")), "还没点头像时「确定」应灰着")
	# 提示条要带技能名（和响应询问同一条口径），不能只甩一段说明
	检(str(窗.call("_技能效果提示", 3903)).begins_with("【恩典神授】："),
		"技能说明提示应写成「【恩典神授】：说明」：%s" % str(窗.call("_技能效果提示", 3903)).substr(0, 24))
	窗.free()


## 95 异教徒：开局 +1 水晶；末日预言的预言堆给 F8 用
func _检异教徒() -> void:
	var 角色: BattleRole = _建引擎(95)
	var 玩家: BattlePlayer = 引擎.p(1)
	检(玩家.crystal == 1, "【异端邪说】开局应 +1 水晶：%d" % 玩家.crystal)
	# 造一个带 2 张预言的末日预言
	var 牌组: Array = _找两张牌("风")
	引擎.加场卡({"id": "末日预言", "owner": 1, "attached": -1,
		"counter": 牌组.size(), "counter_max": 6, "state": 0, "pile": 牌组})
	检(引擎.有场卡("末日预言"), "应能放入【末日预言】场卡")
	var 替换: int = 角色.伤害摸牌替换(2)
	检(替换 == int(牌组[牌组.size() - 1]), "F8 应返回预言堆顶那张：%d" % 替换)
	检(int(引擎.取场卡("末日预言").get("counter", 0)) == 1, "取走 1 张后预言堆应剩 1 张")


## 79 噬神者：御刃给出两条选项；拿牌后点【魔刃】/【异刃】先选系别再攻击
func _检噬神者() -> void:
	# 先单独验证【御刃】：启动技能 + 选项走 available_skills 的 arg_choices
	# （和魔眼一样：点开即进二级栏、可返回、按确定才提交；不再走服务端二次询问）
	var 御刃角色: BattleRole = _建引擎(79)
	var 御刃玩家: BattlePlayer = 引擎.p(1)
	var 御刃: Dictionary = _找技能(御刃角色.available_skills(), 7901)
	检(not 御刃.is_empty() and int(御刃.get("type", 0)) == GConst.ActionType.SpecialSkill,
		"【御刃】应是启动技能（SpecialSkill）")
	var 刃选项: Array = 御刃.get("arg_choices", [])
	检(刃选项.size() == 2, "两张刃都不在场时【御刃】应给两条选项：%d" % 刃选项.size())
	检(not 刃选项.is_empty() and (刃选项[0] as Dictionary).has("text")
			and (刃选项[0] as Dictionary).get("args", []) == [1],
		"【御刃】的选项应是客户端格式（text / args）：%s" % str(刃选项))
	# 选项悬停要带对应被动：魔刃 → 魔刃 + 渗蚀；异刃 → 异刃 + 渗蚀
	检((刃选项[0] as Dictionary).get("技能组", []) == [7909, 7911],
		"【御刃·魔刃】选项应带【魔刃】+【渗蚀】的说明：%s" % str(刃选项[0]))
	检((刃选项[0] as Dictionary).get("preview_cards", []) == [1005]
		and (刃选项[1] as Dictionary).get("preview_cards", []) == [1006],
		"【御刃】选项悬停应带对应刃的卡面：%s" % str(刃选项))
	检((刃选项[1] as Dictionary).get("技能组", []) == [7910, 7911],
		"【御刃·异刃】选项应带【异刃】+【渗蚀】的说明：%s" % str(刃选项[1]))
	检(str((刃选项[0] as Dictionary).get("text", "")) == "【魔刃】火系/水系加入手牌",
		"【御刃·魔刃】选项文本不对：%s" % str(刃选项[0]))
	检(str((刃选项[1] as Dictionary).get("text", "")) == "【异刃】雷系/风系加入手牌",
		"【御刃·异刃】选项文本不对：%s" % str(刃选项[1]))
	检((刃选项[0] as Dictionary).get("elements", []) == [GConst.CardElement.Fire, GConst.CardElement.Water]
		and (刃选项[1] as Dictionary).get("elements", []) == [GConst.CardElement.Thunder, GConst.CardElement.Wind],
		"【御刃】选项应带可标色的系别列表：%s / %s" % [str(刃选项[0]), str(刃选项[1])])
	var 选项协议解: Dictionary = ProtoCodec.decode_named("ArgChoice",
		ProtoCodec.encode_named("ArgChoice", {"elements": [GConst.CardElement.Fire, GConst.CardElement.Water]}))
	检(选项协议解.get("elements", []) == [GConst.CardElement.Fire, GConst.CardElement.Water],
		"御刃选项的可选系别应能通过 ArgChoice 协议：%s" % str(选项协议解))
	检(int(御刃角色.v_special_skill({"src_id": 1, "action_id": 7901, "args": [1]}))
		== GConst.GE_SUCCESS, "两张刃都不在场时【御刃·魔刃】应通过校验")
	检(int(御刃角色.v_special_skill({"src_id": 1, "action_id": 7901, "args": [3]}))
		!= GConst.GE_SUCCESS, "【御刃】没有第 3 个选项，应被拒")
	检(int(御刃角色.p_special_skill({"src_id": 1, "action_id": 7901, "args": [1]}))
		== BattleRole.SUCCESS, "【御刃·魔刃】确认后应直接结算")
	检(御刃玩家.有手牌(御刃玩家.魔刃实例) and 御刃玩家.boot_skill_used,
		"【御刃】确认后应把魔刃加入手牌并置启动已用")
	检(御刃玩家.hand_cards.has(御刃玩家.魔刃实例),
		"【御刃】加入的魔刃应是本人唯一实例，实际手牌=%s / 实例=%d" % [
			str(御刃玩家.hand_cards), 御刃玩家.魔刃实例])
	var 公开快照: Dictionary = 御刃玩家.to_proto(2)
	检((公开快照.get("hand_blades", []) as Array).has(1005),
		"其他玩家快照应公开手牌里的魔刃，实际 %s" % str(公开快照.get("hand_blades", [])))
	# 同调只对噬神者自己使用/弃置生效；其他人仍 3 点
	检(int(御刃角色.call("_渗蚀伤害", 1)) == 1, "同调：噬神者自己使用/弃置渗蚀应为 1 点")
	检(int(御刃角色.call("_渗蚀伤害", 2)) == 3, "同调：其他人使用/弃置渗蚀应为 3 点")
	# 攻击入口已删除：魔刃/异刃现在就是普通攻击牌，按当前系别直接打
	检(GConst.技能行(7912).is_empty() and GConst.技能行(7913).is_empty(),
		"技能表里不应再有 7912 / 7913（攻击）入口")
	var 角色: BattleRole = _建引擎(79)
	var 玩家: BattlePlayer = 引擎.p(1)
	var 魔实例: int = 玩家.魔刃实例
	var 异实例: int = 玩家.异刃实例
	检(魔实例 > 0 and 异实例 > 0 and 魔实例 != 异实例,
		"噬神者应持有自己的两张唯一刃实例：%d / %d" % [魔实例, 异实例])
	检(引擎.刃归属者(魔实例) == 1 and 引擎.刃归属者(异实例) == 1,
		"两张刃的归属者应是噬神者本人")
	检(not 引擎.刃在场(1, GConst.噬神者_魔刃卡) and not 引擎.刃在场(1, GConst.噬神者_异刃卡),
		"开局两张刃应在场外（不在场）")
	检(引擎.移除牌堆.has(魔实例) and 引擎.移除牌堆.has(异实例),
		"开局两张刃应收纳在移除牌堆里")
	var 刃在任何区域: bool = false
	for pid: int in 引擎.order:
		var pp: BattlePlayer = 引擎.p(pid)
		if pp.hand_cards.has(魔实例) or pp.cover_cards.has(魔实例) 				or pp.hand_cards.has(异实例) or pp.cover_cards.has(异实例):
			刃在任何区域 = true
	检(not 刃在任何区域 and not 引擎.deck.discard.has(魔实例) and not 引擎.deck.pile.has(魔实例) 		and not 引擎.deck.discard.has(异实例) and not 引擎.deck.pile.has(异实例),
		"开局两张刃不应出现在手牌/盖牌/牌库/弃牌堆")
	引擎.刃加入手牌(1, 引擎.从移除牌堆取出(魔实例))
	引擎.刃加入手牌(1, 引擎.从移除牌堆取出(异实例))
	var 魔卡: GCard = Data.get_card(魔实例)
	var 异卡: GCard = Data.get_card(异实例)
	# 盖牌渗蚀：同一个盖牌变动（同一个 seq）被 URGENT 回栈重跑时只能触发一次
	var 盖牌上下文: Dictionary = {
		"direction": GConst.CHANGE_ADD, "dst": 2, "cards": [魔实例], "seq": 999,
	}
	检(int(角色.call("p_cover_change", 盖牌上下文)) == BattleRole.URGENT,
		"魔刃作为盖牌首次放进盖牌区时应触发渗蚀")
	检(int(角色.call("p_cover_change", 盖牌上下文)) == BattleRole.SUCCESS,
		"同一个盖牌变动回栈重跑时不应再次触发渗蚀")
	# 共振四选一：不加 / 魔刃 / 异刃 / 两者；后三项都带 1 名目标，文案带系别与技能组
	角色.set("_步", 6)
	角色.set("_共振系", GConst.CardElement.Fire)
	角色.call("p_shi_shen_ask", {"player": 1})
	var 共振问: Dictionary = (引擎.get("_最后询问") as Dictionary).get(1, {})
	var 共振命令表: Array = 共振问.get("commands", [])
	var 共振命令: Dictionary = 共振命令表[0] if not 共振命令表.is_empty() else {}
	检(共振命令.get("option_need_targets", []) == [0, 1, 1, 1],
		"共振询问应下发每项需目标数 [0,1,1,1]，实际 %s" % str(共振命令.get("option_need_targets", [])))
	检((共振命令.get("option_targets", []) as Array).size() == 4,
		"共振询问应下发 4 项目标白名单，实际 %s" % str(共振命令.get("option_targets", [])))
	检(共振命令.get("option_enabled", []) == [true, false, false, false],
		"魔刃/异刃已在手牌时，共振询问应下发 [true,false,false,false] 的可用状态，实际 %s" %
		str(共振命令.get("option_enabled", [])))
	var 共振选项: Array = 角色.call("_共振选项")
	检(共振选项.size() == 4, "共振应直接给出 4 个选项，实际 %d" % 共振选项.size())
	if 共振选项.size() == 4:
		var 零项: Dictionary = 共振选项[0]
		var 魔项: Dictionary = 共振选项[1]
		var 异项: Dictionary = 共振选项[2]
		var 双项: Dictionary = 共振选项[3]
		检(str(零项.get("label", "")) == "不加入手牌"
			and int(零项.get("need_target", 0)) == 0,
			"共振第 1 项应是不加入手牌、不选目标")
		检(str(魔项.get("label", "")) == "【魔刃】火系/水系加入手牌"
			and 魔项.get("elements", []) == [GConst.CardElement.Fire, GConst.CardElement.Water]
			and 魔项.get("技能组", []) == [7909, 7911]
			and int(魔项.get("need_target", 0)) == 1,
			"共振第 2 项应与御刃魔刃选项一致并带目标")
		检(not bool(魔项.get("enabled", true)) and not bool(异项.get("enabled", true))
			and not bool(双项.get("enabled", true)),
			"魔刃/异刃已在手牌时，包含它们的选项应置灰")
		# 第一步弃牌代价把魔刃弃掉（渗蚀移除 → 收进移除牌堆），第二步应允许重新加回
		var 取走的魔刃: int = 玩家.取出一张手牌(魔实例)
		检(取走的魔刃 >= 0, "测试前应能从手牌取出魔刃")
		if 取走的魔刃 >= 0:
			引擎.放入移除牌堆(取走的魔刃)
		var 重选选项: Array = 角色.call("_共振选项")
		检(重选选项.size() == 4 and bool((重选选项[1] as Dictionary).get("enabled", false)),
			"弃掉魔刃后，共振的魔刃选项应重新可用")
		if 取走的魔刃 >= 0:
			检(not 引擎.刃在场(1, GConst.噬神者_魔刃卡), "移除的刃应算不在场")
			var 取出刃: int = 引擎.刃从移除牌堆取出(取走的魔刃)
			检(取出刃 == 取走的魔刃, "应从移除牌堆取出同一实例：%d / %d" % [取出刃, 取走的魔刃])
			检(引擎.刃加入手牌(1, 取出刃), "共振/御刃应能把取出的刃按同一实例加回")
			检(玩家.有手牌(取走的魔刃), "加回后魔刃应在手牌里")
		检(str(异项.get("label", "")) == "【异刃】雷系/风系加入手牌"
			and 异项.get("elements", []) == [GConst.CardElement.Thunder, GConst.CardElement.Wind]
			and 异项.get("技能组", []) == [7910, 7911]
			and int(异项.get("need_target", 0)) == 1,
			"共振第 3 项应与御刃异刃选项一致并带目标")
		检(str(双项.get("label", "")) == "【魔刃】火系/水系和【异刃】雷系/风系加入手牌"
			and 双项.get("elements", []) == [
				GConst.CardElement.Fire, GConst.CardElement.Water,
				GConst.CardElement.Thunder, GConst.CardElement.Wind]
			and 双项.get("技能组", []) == [7909, 7910, 7911]
			and int(双项.get("need_target", 0)) == 1,
			"共振第 4 项应是魔刃+异刃总和并带目标")
		检(魔项.get("preview_cards", []) == [1005] and 异项.get("preview_cards", []) == [1006]
			and 双项.get("preview_cards", []) == [1005, 1006],
			"共振选项悬停应带对应刃的卡面：%s" % str([魔项.get("preview_cards", []), 异项.get("preview_cards", []), 双项.get("preview_cards", [])]))
	var 共振选项协议: Dictionary = ProtoCodec.decode_named("Command",
		ProtoCodec.encode_named("Command", {
			"option_elements": [{"ids": [GConst.CardElement.Fire, GConst.CardElement.Water]}],
			"option_skill_groups": [{"ids": [7909, 7911]}],
		}))
	var 协议元素: Array = 共振选项协议.get("option_elements", [])
	var 协议技能组: Array = 共振选项协议.get("option_skill_groups", [])
	检(协议元素.size() == 1 and (协议元素[0] as Dictionary).get("ids", [])
		== [GConst.CardElement.Fire, GConst.CardElement.Water]
		and 协议技能组.size() == 1 and (协议技能组[0] as Dictionary).get("ids", []) == [7909, 7911],
		"共振选项的系别/技能组应通过 Command 协议")
	var 噬灭可弃: Array = 角色.call("_噬灭可弃", [GConst.CardElement.Water, GConst.CardElement.Fire])
	检(噬灭可弃.has(魔实例) and not 噬灭可弃.has(异实例),
		"【噬灭】只能弃水/火，异刃（雷）不应进入合法弃牌名单：%s" % str(噬灭可弃))
	var 噬灭指示: Dictionary = GConst.技能指示器.get(GConst.技能_噬灭, {})
	var 殇灭指示: Dictionary = GConst.技能指示器.get(GConst.技能_殇灭, {})
	检(str(噬灭指示.get("文案", "")).contains("移除") and str(噬灭指示.get("文案", "")).contains("治疗")
		and str(噬灭指示.get("自动选目标", "")) == "询问目标",
		"噬灭指示器应写移除治疗并自动高亮攻击目标：%s" % str(噬灭指示))
	检(str(殇灭指示.get("文案", "")).contains("移除") and str(殇灭指示.get("文案", "")).contains("治疗"),
		"殇灭指示器应写移除治疗：%s" % str(殇灭指示))
	# 噬灭询问应直接进入选牌（旧的「先确定发动」已删）；白名单只含合法牌，且可取消
	角色.set("_噬灭技能", 7903)
	角色.set("_噬灭目标", 2)
	角色.set("_步", 2)
	角色.call("p_shi_shen_ask", {"player": 1})
	var 问: Dictionary = (引擎.get("_最后询问") as Dictionary).get(1, {})
	var 问命令表: Array = 问.get("commands", [])
	var 问命令: Dictionary = 问命令表[0] if not 问命令表.is_empty() else {}
	var 问参数: Array = 问命令.get("args", [])
	var 问合法牌: Array = 问命令.get("card_ids", [])
	检(not 问参数.is_empty() and int(问参数[0]) == 1,
		"噬灭应直接进入选牌询问（need_card=1），不能先弹是否发动")
	检(问合法牌.has(1005) and not 问合法牌.has(1006),
		"噬灭询问白名单应只含水/火牌，实际 %s" % str(问合法牌))
	检(bool(问命令.get("can_cancel", false)), "噬灭选牌应允许取消（取消=不发动）")
	检(str(问命令.get("ask_prompt", "")) == "",
		"噬灭不应在服务端硬编码提示，应交给客户端通用「【技能名】：说明」逻辑：%s" % str(问命令.get("ask_prompt", "")))
	检((问命令.get("dst_ids", []) as Array).has(2),
		"噬灭询问应带上本次攻击目标（2）用于头像高亮，实际：%s" % str(问命令.get("dst_ids", [])))
	# 殇灭：同一个询问同时选弃牌与目标，不再分两步
	角色.set("_噬灭技能", 7904)
	角色.set("_噬灭目标", 2)
	角色.set("_步", 2)
	角色.call("p_shi_shen_ask", {"player": 1})
	var 殇灭问: Dictionary = (引擎.get("_最后询问") as Dictionary).get(1, {})
	var 殇灭命令表: Array = 殇灭问.get("commands", [])
	var 殇灭命令: Dictionary = 殇灭命令表[0] if not 殇灭命令表.is_empty() else {}
	检((殇灭命令.get("args", []) as Array).size() > 1
		and int((殇灭命令.get("args", []) as Array)[1]) == 1
		and (殇灭命令.get("dst_ids", []) as Array).has(4)
		and not (殇灭命令.get("dst_ids", []) as Array).has(2),
		"殇灭应在同一个询问里选弃牌和目标（目标=除攻击目标外的敌方），实际：%s" % str(殇灭问))
	角色.set("_步", 0)
	检(魔卡.可选元素 == [GConst.CardElement.Fire, GConst.CardElement.Water]
		and 魔卡.element_enum() == GConst.CardElement.Fire,
		"【魔刃】应配置 fire or water、默认火系：%s / %d" % [str(魔卡.可选元素), 魔卡.element_enum()])
	# textures/icon/ 下有同名状态图标（moRen / yiRen），卡面必须仍然只从 card/ 取
	检(魔卡.sprite_path().begins_with("res://assets/textures/card/"),
		"【魔刃】卡面应取 card/：%s" % 魔卡.sprite_path())
	检(异卡.sprite_path().begins_with("res://assets/textures/card/"),
		"【异刃】卡面应取 card/：%s" % 异卡.sprite_path())
	检(魔卡.sprite_path() != AssetIndex.image_in("res://assets/textures/icon", "moRen"),
		"【魔刃】卡面不应取到 icon/ 下的同名状态图标")
	检(异卡.可选元素 == [GConst.CardElement.Thunder, GConst.CardElement.Wind]
		and 异卡.element_enum() == GConst.CardElement.Thunder,
		"【异刃】应配置 thunder or wind、默认雷系：%s / %d" % [str(异卡.可选元素), 异卡.element_enum()])
	检(_找技能(角色.available_skills(), 7912).is_empty()
		and _找技能(角色.available_skills(), 7913).is_empty(),
		"魔刃/异刃不应再有攻击技能按钮")
	检(int(玩家.v_attack(魔实例, 2, 引擎.players)) == GConst.GE_SUCCESS,
		"【魔刃】当前火系应能直接作为普通攻击牌打出")
	检(int(角色.p_attack_card({"player": 1, "card_id": 1005, "card_id_instance": 魔实例, "改用": 1005})) == BattleRole.SUCCESS,
		"【魔刃】普通攻击时应记录本次用的牌")
	检(角色._本次刃 == 魔实例, "【魔刃】普通攻击应记录本人实例号，实际 %d / 期望 %d" % [角色._本次刃, 魔实例])
	# 额外行动按系别算攻击牌白名单时，虚拟牌魔刃/异刃也要按当前系别进入
	检((引擎.call("_规则攻击牌", GConst.CardElement.Fire, 0, 1) as Array).has(1005),
		"火系额外行动白名单应包含当前火系【魔刃】")
	检(not (引擎.call("_规则攻击牌", GConst.CardElement.Water, 0, 1) as Array).has(1005),
		"【魔刃】当前是火系时不应进水系白名单")
	检(引擎.攻击表现牌(魔实例) == 87, "火系【魔刃】应用火焰斩特效表现牌 87")
	检(引擎.攻击表现牌(异实例) == 108, "雷系【异刃】应用雷光斩特效表现牌 108")
	# 切成水系：卡面系别、普通攻击校验都要跟着变；服务端回一条 CardElement
	检(引擎.设置卡牌元素(1, 魔实例, GConst.CardElement.Water), "【魔刃】切水系应成功")
	检(魔卡.element_enum() == GConst.CardElement.Water, "切换后【魔刃】当前系别应是水")
	检(int(玩家.v_attack(魔实例, 2, 引擎.players)) == GConst.GE_SUCCESS,
		"【魔刃】当前水系仍应能直接作为普通攻击牌打出")
	检((引擎.call("_规则攻击牌", GConst.CardElement.Water, 0, 1) as Array).has(1005),
		"水系额外行动白名单应包含当前水系【魔刃】")
	检(not (引擎.call("_规则攻击牌", GConst.CardElement.Fire, 0, 1) as Array).has(1005),
		"【魔刃】切水后不应再进火系白名单")
	# 带玩家上下文：按该玩家手里刃实例的当前系别算
	检((引擎.call("_规则攻击牌", GConst.CardElement.Water, 0, 1) as Array).has(1005)
		and not (引擎.call("_规则攻击牌", GConst.CardElement.Fire, 0, 1) as Array).has(1005),
		"额外行动白名单应按玩家手里实例的当前系别筛选魔刃")
	检(引擎.攻击表现牌(魔实例) == 129, "水系【魔刃】应用水涟斩特效表现牌 129")
	检(引擎.设置卡牌元素(1, 异实例, GConst.CardElement.Wind), "【异刃】切风系应成功")
	检(引擎.攻击表现牌(异实例) == 66, "风系【异刃】应用风神斩特效表现牌 66")
	引擎.设置卡牌元素(1, 异实例, GConst.CardElement.Thunder)
	var 有元素消息: bool = false
	for r: Dictionary in 发送记录:
		if int(r["msg"]) == GConst.Msg.CardElement:
			有元素消息 = true
			break
	检(有元素消息, "切换系别后服务端应回 CardElement")
	# 复原默认火系，避免影响后续用例
	引擎.设置卡牌元素(1, 魔实例, GConst.CardElement.Fire)
	# 手里没有两张同系牌时，共振仍应发出询问（不能静默跳过）
	var 无同系角色: BattleRole = _建引擎(79)
	var 无同系玩家: BattlePlayer = 引擎.p(1)
	无同系玩家.hand_cards.clear()
	var 火法: int = _找牌("fire", "magic")
	var 水法: int = _找牌("water", "magic")
	if 火法 > 0 and 水法 > 0:
		无同系玩家.add_hand_cards([火法, 水法])
	无同系玩家.set_gem(1)
	无同系玩家.set_crystal(0)
	无同系角色.call("p_timeline_3", {"harm": {"dst": 1, "type": GConst.HarmType.Magic}})
	无同系角色.call("p_shi_shen_ask", {"player": 1})
	var 无同系问: Dictionary = (引擎.get("_最后询问") as Dictionary).get(1, {})
	var 无同系命令: Array = 无同系问.get("commands", [])
	检(not 无同系命令.is_empty() and int((无同系命令[0] as Dictionary).get("respond_id", 0)) == 7907,
		"没有同系牌时共振也应发出 7907 询问：%s" % str(无同系问))
	# 侵刻是响应技能：命中后应先弹 7902 询问，不能直接加牌
	无同系角色.set("_步", 0)
	无同系角色.set("_侵刻已处理", false)
	无同系角色.set("_本次刃", 无同系玩家.魔刃实例)
	无同系角色.set("_本次刃面", 1005)
	# 应战反击也属于「攻击命中」，is_active=false 时同样应询问侵刻
	var 侵刻返回: int = int(无同系角色.call("p_timeline_2_hit", {"is_active": false, "dst": 2}))
	var 侵刻问: Dictionary = (引擎.get("_最后询问") as Dictionary).get(1, {})
	var 侵刻命令: Array = 侵刻问.get("commands", [])
	检(侵刻返回 == BattleRole.WAIT and not 侵刻命令.is_empty()
		and int((侵刻命令[0] as Dictionary).get("respond_id", 0)) == 7902,
		"【侵刻】命中后应弹出发动询问，实际返回=%d 询问=%s" % [侵刻返回, str(侵刻问)])
	# 手牌不足时噬灭仍然要发起询问
	无同系玩家.hand_cards.clear()
	无同系角色.set("_步", 0)
	无同系角色.set("_噬灭已处理", false)
	无同系角色.set("_本次刃", 无同系玩家.魔刃实例)
	无同系角色.set("_本次刃面", 1005)
	无同系角色.call("p_timeline_1", {"is_active": true, "dst": 2})
	无同系角色.call("p_shi_shen_ask", {"player": 1})
	var 无牌问: Dictionary = (引擎.get("_最后询问") as Dictionary).get(1, {})
	var 无牌命令: Array = 无牌问.get("commands", [])
	检(not 无牌命令.is_empty() and int((无牌命令[0] as Dictionary).get("respond_id", 0)) == 7903
		and (无牌命令[0] as Dictionary).get("card_ids", []).has(GConst.手牌白名单_全禁),
		"手牌不足时噬灭也应发出询问，并用全禁哨兵防止客户端放开所有牌：%s" % str(无牌问))
	# 应战时牌在别人手里、归属者自己不持有，也要能记录本次刃并进入侵刻
	var 防: BattlePlayer = 引擎.p(2)
	防.hand_cards.clear()
	防.add_hand_cards([无同系玩家.魔刃实例])
	无同系角色.set("_本次刃", 0)
	无同系角色.set("_侵刻已处理", false)
	无同系角色.set("_步", 0)
	无同系角色.call("p_attack_card", {"player": 2, "card_id": 1005,
		"card_id_instance": 无同系玩家.魔刃实例, "改用": 1005, "reattack": true})
	检(无同系角色.get("_本次刃") == 无同系玩家.魔刃实例,
		"应战刃在别人手里时，归属者也应记录本次刃")
	var 应战侵刻返回: int = int(无同系角色.call("p_timeline_2_hit",
		{"is_active": false, "dst": 1, "harm": {"reattack": true}}))
	var 应战侵刻问: Dictionary = (引擎.get("_最后询问") as Dictionary).get(1, {})
	var 应战侵刻命令: Array = 应战侵刻问.get("commands", [])
	检(应战侵刻返回 == BattleRole.WAIT and not 应战侵刻命令.is_empty()
		and int((应战侵刻命令[0] as Dictionary).get("respond_id", 0)) == 7902,
		"应战回击命中后也应弹侵刻 7902 询问：%s" % str(应战侵刻问))
	# 火系魔刃攻击：敌方普通火系攻击牌应能通过 v_reattack
	var 火应战: int = _找牌("fire", "attack")
	防.hand_cards.clear()
	防.add_hand_cards([火应战])
	Data.get_card(魔实例).设置当前元素(GConst.CardElement.Fire)
	# 故意把共用牌面设成水：应战判定应按攻击牌实例的当前系（火），不能看牌面
	Data.get_card(1005).设置当前元素(GConst.CardElement.Water)
	检(int(防.v_reattack(火应战, 魔实例)) == GConst.GE_SUCCESS,
		"火系魔刃攻击时，敌方普通火系攻击牌应能应战（按实例系别判定）")
	# 诸神终焉的目标询问钩子只能处理一次：引擎 URGENT 回栈重跑时不能再推一次
	无同系角色.set("_诸神问已处理", false)
	var 诸神问一次: int = int(无同系角色.call("p_shi_shen_诸神问", {"player": 1}))
	var 诸神问二次: int = int(无同系角色.call("p_shi_shen_诸神问", {"player": 1}))
	检(诸神问一次 == BattleRole.URGENT and 诸神问二次 == BattleRole.SUCCESS,
		"诸神终焉目标询问钩子应只触发一次，实际 %d / %d" % [诸神问一次, 诸神问二次])


## 手牌系别切换后：已选中的牌不合法要取消选中并置灰；原本不合法、切回后合法要重新亮起
	# 嵌套弃牌：拦截过程中弃刃（共振代价）仍要走拦截，不能直接塞进弃牌堆
	_建引擎(79)
	var 嵌套玩家: BattlePlayer = 引擎.p(1)
	嵌套玩家.hand_cards.clear()
	var 嵌套魔刃: int = 嵌套玩家.魔刃实例
	引擎.刃加入手牌(1, 引擎.从移除牌堆取出(嵌套魔刃))
	引擎._running = true
	引擎._弃牌拦截中 = true
	引擎.to_discard([嵌套魔刃], {"owner": 1, "source": "hand", "cause": 7907}, true)
	检(not 引擎._states.is_empty() and not 引擎.deck.discard.has(嵌套魔刃),
		"拦截过程中弃刃应排队走拦截，不能直接进弃牌堆")
	引擎._states.clear()
	引擎._running = false
	引擎._弃牌拦截中 = false

func _检切换后复检() -> void:
	var 原手牌: Array[GCard] = Data.hand_cards.duplicate()
	var 原Iids: Array[int] = Data.hand_iids.duplicate()
	var 窗: Control = (load("res://scenes/BattleUIMobile.tscn") as PackedScene).instantiate()
	add_child(窗)
	await 等帧()
	Data.hand_cards = [Data.get_card(1005), Data.get_card(87), Data.get_card(88)]
	Data.hand_iids = [1005, 87, 88]
	Data.get_card(1005).设置当前元素(GConst.CardElement.Fire)
	var 通用提示: String = str(窗.call("_技能效果提示", 7903))
	var 噬灭说明: String = GConst.skill_desc(7903).replace("\\n", "").replace("\n", "").strip_edges()
	检(通用提示 == "【%s】：%s" % [GConst.skill_name(7903), 噬灭说明],
		"噬灭提示应走客户端通用「【技能名】：说明」：%s" % 通用提示)
	# 侵刻目标提示：按最近打出的刃写「给予【魔刃/异刃】」
	窗.set("_mode", 3)
	窗.set("_skill_ask_id", GConst.技能_侵刻)
	窗.set("_最近攻击牌", GConst.噬神者_魔刃卡)
	var 选中: Array[int] = 窗.get("_sel_players")
	选中.clear()
	选中.append(2)
	var 侵刻提示: Dictionary = 窗.call("_侵刻头像提示")
	检(str(侵刻提示.get(2, "")) == "给予【魔刃】",
		"侵刻目标提示应写「给予【魔刃】」：%s" % str(侵刻提示))
	选中.clear()
	窗.set("_最近攻击牌", 0)
	窗.set("_mode", 4)
	# 诸神终焉：同一目标持有两张自己的刃，应画两行 3 点
	窗.set("_pending_skill_id", GConst.技能_诸神终焉)
	var 高亮: Array[int] = 窗.get("_高亮目标")
	高亮.clear()
	高亮.append(2)
	var 高亮计数: Dictionary = 窗.get("_高亮计数")
	高亮计数.clear()
	高亮计数[2] = 2
	var 诸神提示: Dictionary = 窗.call("_诸神终焉头像提示")
	检(str(诸神提示.get(2, "")) == "3 法术伤害\n3 法术伤害",
		"同一目标持有两张刃时应显示两行 3 点：%s" % str(诸神提示))
	高亮.clear()
	高亮计数.clear()
	窗.set("_pending_skill_id", 0)
	窗.set("_skill_card_max", 2)
	窗.set("_skill_need_card", 2)
	窗.set("_skill_card_source", GConst.CardSource.Hand)
	窗.set("_skill_card_rule", "same")
	窗.set("_skill_cards", [])
	窗.call("刷新手牌")
	await 等帧()
	var 选: Array[int] = [1005, 87]
	窗.set("_sel_cards", 选)
	# 1005 火 + 87 火：same 规则下合法；切成水后 1005 没有水系搭档，应取消自己
	Data.get_card(1005).设置当前元素(GConst.CardElement.Water)
	窗.call("_切换后复检手牌")
	var 选后: Array = 窗.get("_sel_cards")
	检(选后 == [87], "切换后不合法的 1005 应从选中里取消，实际 %s" % str(选后))
	var 百节点: Node = _手牌节点(窗, 1005)
	var 八七节点: Node = _手牌节点(窗, 87)
	检(百节点 != null and not bool(百节点.get("_可用")) and not bool(百节点.get("_选中")),
		"1005 切水系后没有同系搭档，应置灰且取消选中")
	检(八七节点 != null and bool(八七节点.get("_可用")) and bool(八七节点.get("_选中")),
		"87 仍与 88 同火系，应保持可点与选中")
	# 切回火：1005 重新和 87/88 同系，应亮起（不自动重新选中）
	Data.get_card(1005).设置当前元素(GConst.CardElement.Fire)
	窗.call("_切换后复检手牌")
	检(bool(百节点.get("_可用")), "1005 切回火系后应重新亮起")
	检(not bool(百节点.get("_选中")), "1005 切回火系后不应自动重新选中")
	检(not (窗.get("_sel_cards") as Array).has(1005), "1005 切回火系后仍不应在选中里")
	# 魔刃状态悬停内容：标题（名字+系别）→ 卡面 → 两条被动说明
	var 悬停内容: Control = 窗.call("_造噬神者刃状态内容", Data.get_card(1005))
	检(悬停内容 != null and 悬停内容.get_child_count() == 3,
		"魔刃悬停应依次有标题、卡面、技能说明三段，实际 %d 段" %
		(悬停内容.get_child_count() if 悬停内容 != null else -1))
	if 悬停内容 != null and 悬停内容.get_child_count() == 3:
		var 标题: RichTextLabel = 悬停内容.get_child(0) as RichTextLabel
		var 卡面: Control = 悬停内容.get_child(1) as Control
		var 技能: RichTextLabel = 悬停内容.get_child(2) as RichTextLabel
		检(标题 != null and 标题.text.contains("【魔刃】") and 标题.text.contains("[color="),
			"悬停第一段应是带系别配色的【魔刃】标题")
		检(卡面 is 悬停卡预览 and not (卡面 as 悬停卡预览).状态名.visible,
			"悬停第二段应是完整卡面（隐藏重复的状态名行）")
		检(技能 != null and 技能.text.contains("渗蚀"),
			"悬停第三段应包含【渗蚀】说明")
	# 所有状态图标共用 StatusIcon：Text 是计数、Name 是底部名字，位置由预制体控制
	var 状态预制路径: String = "res://scenes/prefabs/battlemobile/StatusIcon.tscn"
	var 状态预制: PackedScene = load(状态预制路径) as PackedScene
	检(状态预制 != null, "缺少状态图标预制体：%s" % 状态预制路径)
	var 状态实例: Node = 状态预制.instantiate() if 状态预制 != null else null
	检(状态实例 is TextureRect and 状态实例.get_node_or_null("Text") is Label
		and 状态实例.get_node_or_null("Name") is Label,
		"状态图标预制体应包含 Text / Name 两个文字节点：%s" % 状态预制路径)
	if 状态实例 != null:
		状态实例.queue_free()
	# 客户端收到选项 enabled=false 后必须把对应二级选项置灰
	var 测试命令: Dictionary = {
		"respond_id": 7907, "src_id": 1, "is_skill": true,
		"args": [0, 0, 0, 4, 1, 2, 3, 4],
		"notes": ["不加入手牌", "【魔刃】火系/水系加入手牌",
			"【异刃】雷系/风系加入手牌", "【魔刃】火系/水系和【异刃】雷系/风系加入手牌"],
		"option_enabled": [true, false, false, false],
		"option_need_targets": [0, 1, 1, 1],
		"option_targets": [{"ids": []}, {"ids": [1, 2]}, {"ids": [1, 2]}, {"ids": [1, 2]}],
	}
	窗.set("_pending", 测试命令)
	窗.set("_pending_type", GConst.Msg.Respond)
	窗.call("_进入技能询问")
	var 测试二级: Array = 窗.get("_二级选项")
	检(测试二级.size() == 4 and not bool((测试二级[1] as Dictionary).get("可用", true))
		and not bool((测试二级[2] as Dictionary).get("可用", true))
		and not bool((测试二级[3] as Dictionary).get("可用", true)),
		"共振选项 enabled=false 应传成二级按钮的不可用状态")
	Data.hand_cards = 原手牌
	Data.hand_iids = 原Iids
	窗.queue_free()
	await 等帧()


func _手牌节点(窗: Control, 实例: int) -> Node:
	var 容器: Control = 窗.get("HandArea") as Control
	if 容器 == null:
		return null
	for 子: Node in 容器.get_children():
		if 子.get("实例号") != null and int(子.get("实例号")) == 实例:
			return 子
	return null


## 40 星坠女巫：开局有【律法：繁星】、手牌上限按律法数算；星刻放【卢恩】
func _检星坠女巫() -> void:
	var 角色: BattleRole = _建引擎(40)
	var 玩家: BattlePlayer = 引擎.p(1)
	检(玩家.律法数() == 1 and 玩家.有律法(1), "开局应拥有 1 个【律法】（繁星）")
	检(玩家.hand_cards_max == GConst.HAND_CARDS_MAX,
		"1 个律法时手牌上限应回到基础值：%d" % 玩家.hand_cards_max)
	玩家.加律法(2)
	玩家.移除律法()
	玩家.加律法(3)
	# 手牌上限的重算口径是「回合开始时」（角色 p_before_turn_begin 里 _重算手牌上限），
	# 不是 player.加律法 / 移除律法 里即时重算；这里按游戏里的方式触发一次再断言。
	角色.p_before_turn_begin({"player": 1})
	检(玩家.hand_cards_max == GConst.HAND_CARDS_MAX + 1 - 玩家.律法数(),
		"手牌上限应随律法数变化")
	# 【群星启示】是启动技：必须作为 SpecialSkill 下发，且不能有法术技能入口
	var 启示项: Dictionary = {}
	for 项: Dictionary in 角色.available_skills():
		if int(项.get("id", 0)) == 4004:
			启示项 = 项
	检(int(启示项.get("type", 0)) == GConst.ActionType.SpecialSkill,
		"【群星启示】应作为启动技（SpecialSkill）下发")
	检(角色.v_magic_skill({"action_id": 4004, "src_id": 1}) == GConst.GE_INVALID_ACTION,
		"【群星启示】不应有法术技能入口")
	# 星刻：攻击行动结束时牌库顶 1 张面朝下作为【卢恩】
	检(玩家.can_add_cover_cards(1), "星坠女巫应有盖牌槽（卢恩）")
	var 牌数前: int = 引擎.deck.pile.size()
	角色.p_action_end({"player": 1, "kind": "attack"})
	检(玩家.盖牌按标记("卢恩").size() == 1, "【星刻】应放下 1 个【卢恩】")
	检(引擎.deck.pile.size() == 牌数前 - 1, "【星刻】应从牌库顶取 1 张")
	检(玩家.公开盖牌牌面().is_empty(), "【卢恩】应面朝下（不公开牌面）")


# ============================================================
# 小工具
# ============================================================
## 「火」/「fire」都认：卡表里 element 存的是英文，调用方有的写中文 ——
## 以前直接比 c.element != 系，传中文的调用永远找不到牌（异教徒那一段因此数组越界）。
func _元素号(系: String) -> int:
	var e: int = GConst.element_from_string(系)
	if e != 0:
		return e
	match 系:
		"风": return GConst.CardElement.Wind
		"水": return GConst.CardElement.Water
		"火": return GConst.CardElement.Fire
		"地": return GConst.CardElement.Earth
		"雷": return GConst.CardElement.Thunder
		"光": return GConst.CardElement.Light
		"暗": return GConst.CardElement.Darkness
	return 0


func _找牌(系: String, 类型: String) -> int:
	var 元素: int = _元素号(系)
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual or c.element_enum() != 元素:
			continue
		if 类型 == "attack" and c.is_attack():
			return c.id
		if 类型 == "magic" and c.is_magic():
			return c.id
	return 0


func _找两张牌(系: String) -> Array:
	var out: Array = []
	var 元素: int = _元素号(系)
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual or c.element_enum() != 元素:
			continue
		out.append(c.id)
		if out.size() >= 2:
			break
	return out


func _找技能(技能: Array, 号: int) -> Dictionary:
	for s: Dictionary in 技能:
		if int(s.get("id", 0)) == 号:
			return s
	return {}
