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
	95: [9501, 9502, 9503, 9504, 9505, 9506],
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
			检(卡.is_virtual, "%d 应标成虚拟牌（不进牌库）" % 卡号)
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
	角色.setup(玩家, 引擎)
	玩家.role = 角色
	玩家.role_id = 角色号
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
	引擎.on_message(1, GConst.Msg.Respond, {"respond_id": 4302, "src_id": 1,
		"args": [1], "card_ids": [], "dst_ids": []})
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
	var 水晶前: int = 玩家.crystal
	角色.p_heal_overflow({"player": 3, "overflow": 1, "before": 2, "amount": 2, "src": 1})
	检(int(引擎.取场卡("异端裁决所").get("counter", 0)) == 1,
		"【裁决论定】应给裁决所 +1 治疗")
	检(玩家.crystal == 水晶前 + 1, "【裁决论定】应让发动者 +1 水晶")


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
	检((刃选项[1] as Dictionary).get("技能组", []) == [7910, 7911],
		"【御刃·异刃】选项应带【异刃】+【渗蚀】的说明：%s" % str(刃选项[1]))
	检(str((刃选项[0] as Dictionary).get("text", "")) == "【魔刃】火系/水系加入手牌",
		"【御刃·魔刃】选项文本不对：%s" % str(刃选项[0]))
	检(str((刃选项[1] as Dictionary).get("text", "")) == "【异刃】雷系/风系加入手牌",
		"【御刃·异刃】选项文本不对：%s" % str(刃选项[1]))
	检(int(御刃角色.v_special_skill({"src_id": 1, "action_id": 7901, "args": [1]}))
		== GConst.GE_SUCCESS, "两张刃都不在场时【御刃·魔刃】应通过校验")
	检(int(御刃角色.v_special_skill({"src_id": 1, "action_id": 7901, "args": [3]}))
		!= GConst.GE_SUCCESS, "【御刃】没有第 3 个选项，应被拒")
	检(int(御刃角色.p_special_skill({"src_id": 1, "action_id": 7901, "args": [1]}))
		== BattleRole.SUCCESS, "【御刃·魔刃】确认后应直接结算")
	检(御刃玩家.有手牌(1005) and 御刃玩家.boot_skill_used,
		"【御刃】确认后应把魔刃加入手牌并置启动已用")
	# 攻击入口已删除：魔刃/异刃现在就是普通攻击牌，按当前系别直接打
	检(GConst.技能行(7912).is_empty() and GConst.技能行(7913).is_empty(),
		"技能表里不应再有 7912 / 7913（攻击）入口")
	var 角色: BattleRole = _建引擎(79)
	var 玩家: BattlePlayer = 引擎.p(1)
	玩家.add_hand_cards([1005, 1006])
	var 魔卡: GCard = Data.get_card(1005)
	var 异卡: GCard = Data.get_card(1006)
	检(魔卡.可选元素 == [GConst.CardElement.Fire, GConst.CardElement.Water]
		and 魔卡.element_enum() == GConst.CardElement.Fire,
		"【魔刃】应配置 fire or water、默认火系：%s / %d" % [str(魔卡.可选元素), 魔卡.element_enum()])
	检(异卡.可选元素 == [GConst.CardElement.Thunder, GConst.CardElement.Wind]
		and 异卡.element_enum() == GConst.CardElement.Thunder,
		"【异刃】应配置 thunder or wind、默认雷系：%s / %d" % [str(异卡.可选元素), 异卡.element_enum()])
	检(_找技能(角色.available_skills(), 7912).is_empty()
		and _找技能(角色.available_skills(), 7913).is_empty(),
		"魔刃/异刃不应再有攻击技能按钮")
	检(int(玩家.v_attack(1005, 2, 引擎.players)) == GConst.GE_SUCCESS,
		"【魔刃】当前火系应能直接作为普通攻击牌打出")
	检(int(角色.p_attack_card({"player": 1, "card_id": 1005, "改用": 1005})) == BattleRole.SUCCESS,
		"【魔刃】普通攻击时应记录本次用的牌")
	检(角色._本次刃 == 1005, "【魔刃】普通攻击应记录实例号，实际 %d" % 角色._本次刃)
	# 切成水系：卡面系别、普通攻击校验都要跟着变；服务端回一条 CardElement
	检(引擎.设置卡牌元素(1, 1005, GConst.CardElement.Water), "【魔刃】切水系应成功")
	检(魔卡.element_enum() == GConst.CardElement.Water, "切换后【魔刃】当前系别应是水")
	检(int(玩家.v_attack(1005, 2, 引擎.players)) == GConst.GE_SUCCESS,
		"【魔刃】当前水系仍应能直接作为普通攻击牌打出")
	var 有元素消息: bool = false
	for r: Dictionary in 发送记录:
		if int(r["msg"]) == GConst.Msg.CardElement:
			有元素消息 = true
			break
	检(有元素消息, "切换系别后服务端应回 CardElement")
	# 复原默认火系，避免影响后续用例
	引擎.设置卡牌元素(1, 1005, GConst.CardElement.Fire)


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
	检(玩家.hand_cards_max == GConst.HAND_CARDS_MAX + 1 - 玩家.律法数(),
		"手牌上限应随律法数变化")
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
func _找牌(系: String, 类型: String) -> int:
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual:
			continue
		if c.element != 系:
			continue
		if 类型 == "attack" and c.is_attack():
			return c.id
		if 类型 == "magic" and c.is_magic():
			return c.id
	return 0


func _找两张牌(系: String) -> Array:
	var out: Array = []
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual or c.element != 系:
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
