extends 自检用例
## 节日魔导（76）：魔弹掌握 / 魔弹融合 / 魔爆冲击 / 法力护盾 / 毁灭风暴的基础引擎验证。
## 重点盯住本次翻新的三处：
##   1. 技能号必须走 7601~7605，不能再用魔导师的 801~804；
##   2. 【魔弹掌握】要真的给出左右两个落点；
##   3. 【法力护盾】可以弃 1~X 张（不是只能弃 1 张），并按张数减伤。

var 引擎: BattleEngine


func _init() -> void:
	名称 = "节日魔导"


func _取法术(数量: int) -> Array[GCard]:
	var out: Array[GCard] = []
	for c: GCard in Data.card_db:
		if c == null or c.is_virtual or not c.is_magic():
			continue
		out.append(c)
		if out.size() >= 数量:
			break
	return out


func _取系(元素: int) -> GCard:
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.element_enum() == 元素 \
				and c.card_name_enum() != GConst.CardName.Missile:
			return c
	return null


func _取水系法术() -> GCard:
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.is_magic() \
				and c.element_enum() == GConst.CardElement.Water \
				and c.card_name_enum() != GConst.CardName.Missile:
			return c
	return null


func _找技能(表: Array, 技能号: int) -> Dictionary:
	for sk: Dictionary in 表:
		if int(sk.get("id", 0)) == 技能号:
			return sk
	return {}


func _取询问(pid: int, 技能号: int) -> Dictionary:
	for r: Dictionary in 引擎._最后询问.get(pid, {}).get("commands", []):
		if int(r.get("respond_id", 0)) == 技能号:
			return r
	return {}


## 在 _states 里找一条指定来源 / 目标的伤害，返回它的伤害字典；找不到返回空字典
func _找伤害(cause: int, dst: int) -> Dictionary:
	for st: Variant in 引擎._states:
		if st == null:
			continue
		var h: Variant = st.get("harm")
		if h is Dictionary and int((h as Dictionary).get("cause", 0)) == cause \
				and int((h as Dictionary).get("dst", -1)) == dst:
			return h as Dictionary
	return {}


func 跑() -> void:
	await 等帧(1)
	检(str(Data.role_list.get(76, "")) == "节日魔导", "76 号角色名不是「节日魔导」")
	检(Data.role_pool.has(76), "节日魔导已启用，应进入选角池")
	检(Data.role_skills(76) == [7601, 7602, 7603, 7604, 7605],
		"节日魔导技能号不对：%s" % str(Data.role_skills(76)))
	检(GConst.技能_节日魔导魔弹掌握 == 7601 and GConst.技能_节日魔导魔弹融合 == 7602
		and GConst.技能_节日魔导魔爆冲击 == 7603 and GConst.技能_节日魔导法力护盾 == 7604
		and GConst.技能_节日魔导毁灭风暴 == 7605, "节日魔导的技能号常量没接上")
	# 三个主动技能都要有头像提示配置，否则选目标时不会写「2 法术伤害」
	检(GConst.技能指示器.has(7602) and GConst.技能指示器.has(7603)
		and GConst.技能指示器.has(7605), "节日魔导的主动技能没接上技能指示器配置")
	# 数据链路：脚本路径能加载、技能行能查到、角色说明里五颗技能都在
	检(Data.role_script(76) == "res://scripts/battle/roles/role_spmodao.gd", "节日魔导的脚本路径不对")
	检(ResourceLoader.exists(Data.role_script(76)), "节日魔导的脚本文件不存在")
	for 技能号: int in [7601, 7602, 7603, 7604, 7605]:
		检(not GConst.技能行(技能号).is_empty(), "技能表里查不到 %d" % 技能号)
	var 技能文本: String = Data.role_skill_info(76)
	for 技能名: String in ["魔弹掌握", "魔弹融合", "魔爆冲击", "法力护盾", "毁灭风暴"]:
		检(技能文本.contains(技能名), "角色技能说明里缺【%s】：%s" % [技能名, 技能文本])

	var 法术: Array[GCard] = _取法术(3)
	检(法术.size() >= 3, "卡库里的法术牌不足 3 张")
	var 火: GCard = _取系(GConst.CardElement.Fire)
	var 地: GCard = _取系(GConst.CardElement.Earth)
	var 水法术: GCard = _取水系法术()
	检(火 != null and 地 != null, "卡库找不到火系 / 地系牌")
	检(水法术 != null, "卡库找不到水系法术牌")
	if 法术.size() < 3 or 火 == null or 地 == null or 水法术 == null:
		return

	引擎 = BattleEngine.new()
	引擎.add_player(1, GConst.BLUE, "魔导")
	引擎.add_player(2, GConst.RED, "红二")
	引擎.add_player(3, GConst.BLUE, "蓝三")
	引擎.add_player(4, GConst.RED, "红四")
	引擎.start_with_roles({1: 76, 2: 0, 3: 0, 4: 0})
	引擎._states.clear()
	引擎._清空等待()
	var 魔导: BattlePlayer = 引擎.p(1)
	var 靶: BattlePlayer = 引擎.p(2)
	var 角色: BattleRole = 魔导.role
	检(角色 != null, "76 号角色脚本无法创建")
	if 角色 == null:
		return

	魔导.hand_cards.clear()
	for c: GCard in [火, 地, 水法术, 法术[0], 法术[1], 法术[2]]:
		if not 魔导.hand_cards.has(c.id):
			魔导.hand_cards.append(c.id)

	# ---- 魔弹掌握（7601）：主动打【魔弹】时左右两个落点都能选 ----
	检(角色.has_missile_mastery(), "节日魔导应有【魔弹掌握】：主动打魔弹时可逆向传递")
	var 落点: Array[int] = 角色.missile_targets(1)
	检(落点.size() == 2 and 落点.has(2) and 落点.has(4),
		"【魔弹掌握】应给出左右两个落点（红二、红四），实际：%s" % str(落点))
	var 技能表: Array = 角色.available_skills()
	var 融合技能: Dictionary = _找技能(技能表, 7602)
	检(not 融合技能.is_empty(), "【魔弹融合】应作为技能栏按钮下发")
	检((融合技能.get("targets", []) as Array).has(4),
		"【魔弹融合】的可选落点应包含逆向的红四：%s" % str(融合技能.get("targets", [])))
	var 融合牌: Array = 融合技能.get("cards", [])
	检(融合牌.has(火.id) and 融合牌.has(地.id) and not 融合牌.has(水法术.id),
		"【魔弹融合】的可点牌应只有地 / 火牌：%s" % str(融合牌))
	检(_找技能(技能表, 7603).get("enabled", false), "手里有法术牌时【魔爆冲击】应可点")
	检(_找技能(技能表, 7605).get("enabled", false) == false,
		"没有宝石时【毁灭风暴】应置灰（不是消失）")

	# ---- 魔弹融合（7602）：地 / 火牌可当魔弹，水系牌不行 ----
	检(角色.v_missile(火.id, 2) == GConst.GE_SUCCESS, "火系牌应能当【魔弹】使用")
	检(角色.v_missile(地.id, 4) == GConst.GE_SUCCESS, "地系牌应能当【魔弹】逆向使用")
	检(角色.v_missile(水法术.id, 2) == GConst.GE_INVALID_CARDID, "水系牌不能当【魔弹】使用")
	检(角色.v_remissile(地.id) == GConst.GE_SUCCESS, "地系牌应能响应传递【魔弹】")
	检(角色.v_remissile(水法术.id) == GConst.GE_INVALID_CARDID, "水系牌不能响应传递【魔弹】")
	var 融合动作: Dictionary = {"src_id": 1, "action_id": 7602, "card_ids": [火.id], "dst_ids": [4]}
	检(角色.v_magic_skill(融合动作) == GConst.GE_SUCCESS, "地 / 火牌应能当魔弹打向逆向落点")
	var 非法融合: Dictionary = {"src_id": 1, "action_id": 7602, "card_ids": [水法术.id], "dst_ids": [2]}
	检(角色.v_magic_skill(非法融合) == GConst.GE_INVALID_CARDID, "水系牌不能经【魔弹融合】打出")

	# 结算顺序：魔弹询问要压在 p_after_magic 之上（先结算魔弹，再跑行动结束钩子）
	引擎._states.clear()
	引擎._清空等待()
	角色._持久进度 = 0
	引擎.current_id = 1
	魔导.hand_cards.clear()
	魔导.hand_cards.append(火.id)
	var 融合施放: Dictionary = {"src_id": 1, "action_id": 7602, "card_ids": [火.id], "dst_ids": [2]}
	var 技能运行 = BattleEngine.SkillRun.new("magic", 融合施放)
	检(技能运行.handle(引擎) == BattleEngine.SUSPEND,
		"【魔弹融合】压入魔弹询问后应挂起技能行动，等魔弹结算完再收尾")
	var 栈顶: Variant = 引擎._states[-1] if not 引擎._states.is_empty() else null
	检(栈顶 is BattleEngine.SMissileAsk, "【魔弹融合】的魔弹询问应在状态栈顶（先于 p_after_magic）")
	技能运行.handle(引擎)
	栈顶 = 引擎._states[-1] if not 引擎._states.is_empty() else null
	检(栈顶 is BattleEngine.SHook and str(栈顶.get("hook")) == "p_after_magic",
		"魔弹结算完回到技能行动后，应压入 p_after_magic")

	# ---- 魔爆冲击（7603）：弃 1 张法术牌，+1 宝石；目标不弃则受 2 点法术伤害 ----
	引擎._states.clear()
	引擎._清空等待()
	角色._持久进度 = 0
	引擎.team_gem[GConst.BLUE] = 0
	魔导.hand_cards.clear()
	魔导.hand_cards.append(法术[0].id)
	靶.hand_cards.clear()
	靶.hand_cards.append(法术[1].id)
	var 爆动作: Dictionary = {"src_id": 1, "action_id": 7603, "card_ids": [法术[0].id], "dst_ids": [2]}
	检(角色.v_magic_skill(爆动作) == GConst.GE_SUCCESS, "【魔爆冲击】校验不通过")
	var 爆队友: Dictionary = {"src_id": 1, "action_id": 7603, "card_ids": [法术[0].id], "dst_ids": [3]}
	检(角色.v_magic_skill(爆队友) == GConst.GE_INVALID_PLAYERID, "【魔爆冲击】不能指定队友")
	检(角色.p_magic_skill(爆动作) == BattleRole.WAIT, "【魔爆冲击】应先询问目标是否弃法术牌")
	检(引擎.team_gem[GConst.BLUE] == 1, "【魔爆冲击】应无条件让战绩区 +1 宝石")
	检(not 魔导.hand_cards.has(法术[0].id), "【魔爆冲击】的代价牌应当场弃掉")
	var 爆问: Dictionary = _取询问(2, 7603)
	检(str(爆问.get("card_rule", "")) == "magic", "【魔爆冲击】的目标只能弃法术牌")
	检(str(爆问.get("ask_text", "")).contains("法术伤害"),
		"【魔爆冲击】给目标的提示里应写明不弃会受法术伤害：%s" % str(爆问.get("ask_text", "")))
	引擎._reply = {"args": [], "card_ids": [], "dst_ids": []}
	引擎._has_reply = true
	检(角色.p_magic_skill(爆动作) == BattleRole.URGENT, "目标不弃牌应压入 2 点法术伤害")
	检(not _找伤害(7603, 2).is_empty(), "【魔爆冲击】没压入对目标的伤害")
	检(int(_找伤害(7603, 2).get("point", 0)) == 2, "【魔爆冲击】的伤害应为 2 点")

	# 目标弃了法术牌：不再造成伤害
	引擎._states.clear()
	引擎._清空等待()
	角色._持久进度 = 0
	引擎.team_gem[GConst.BLUE] = 0
	魔导.hand_cards.clear()
	魔导.hand_cards.append(法术[0].id)
	靶.hand_cards.clear()
	靶.hand_cards.append(法术[1].id)
	角色.p_magic_skill(爆动作)
	引擎._reply = {"args": [1], "card_ids": [法术[1].id], "dst_ids": []}
	引擎._has_reply = true
	检(角色.p_magic_skill(爆动作) == BattleRole.SUCCESS, "目标弃了法术牌就不该再造成伤害")
	检(靶.hand_cards.is_empty(), "目标弃的法术牌应离手")
	检(_找伤害(7603, 2).is_empty(), "目标弃牌后不应再压伤害")
	检(引擎.team_gem[GConst.BLUE] == 1, "【魔爆冲击】仍应先 +1 宝石")

	# ---- 毁灭风暴（7605）：耗 1 宝石，对 2 名对手各 2 点法术伤害 ----
	引擎._states.clear()
	引擎._清空等待()
	魔导.set_gem(1)
	检(bool(_找技能(角色.available_skills(), 7605).get("enabled", false)),
		"有 1 颗宝石时【毁灭风暴】应可点")
	var 风暴动作: Dictionary = {"src_id": 1, "action_id": 7605, "card_ids": [], "dst_ids": [2, 4]}
	检(角色.v_magic_skill(风暴动作) == GConst.GE_SUCCESS, "【毁灭风暴】校验不通过")
	var 少目标: Dictionary = {"src_id": 1, "action_id": 7605, "card_ids": [], "dst_ids": [2]}
	检(角色.v_magic_skill(少目标) == GConst.GE_INVALID_PLAYERID, "【毁灭风暴】必须恰好 2 名对手")
	var 含队友: Dictionary = {"src_id": 1, "action_id": 7605, "card_ids": [], "dst_ids": [2, 3]}
	检(角色.v_magic_skill(含队友) == GConst.GE_INVALID_PLAYERID, "【毁灭风暴】不能指定队友")
	检(角色.p_magic_skill(风暴动作) == BattleRole.URGENT, "【毁灭风暴】应压入 2 点群体伤害")
	检(魔导.gem == 0, "【毁灭风暴】应消耗 1 宝石")
	检(int(_找伤害(7605, 2).get("point", 0)) == 2
		and int(_找伤害(7605, 4).get("point", 0)) == 2,
		"【毁灭风暴】应对 2 名目标各压入 2 点法术伤害")

	# ---- 法力护盾（7604）：弃 1~X 张法术牌，按张数减伤 ----
	引擎._states.clear()
	引擎._清空等待()
	角色._dun_step = 0
	魔导.hand_cards.clear()
	for c: GCard in 法术:
		魔导.hand_cards.append(c.id)
	var 伤害: Dictionary = {"src": 2, "dst": 1, "point": 3, "cause": 0, "type": GConst.HarmType.Magic}
	检(角色.p_timeline_3({"harm": 伤害, "src": 2, "dst": 1}) == BattleRole.WAIT,
		"【法力护盾】应先问是否发动")
	var 盾问: Dictionary = _取询问(1, 7604)
	检(int(盾问.get("card_max", 0)) == 3,
		"【法力护盾】应允许弃 1~3 张（最多把 3 点伤害减到 0），实际 card_max=%s" % str(盾问.get("card_max", 0)))
	检(str(盾问.get("card_rule", "")) == "magic", "【法力护盾】只能弃法术牌")
	检(str(盾问.get("ask_text", "")).contains("伤害"),
		"【法力护盾】的询问提示应写明本次伤害：%s" % str(盾问.get("ask_text", "")))
	检(int(盾问.get("preview_base", 0)) == 3
		and int(盾问.get("preview_kind", 0)) == GConst.HarmType.Magic
		and (盾问.get("preview_ids", []) as Array).has(1),
		"【法力护盾】应向客户端下发原伤害、伤害类型和受伤者：%s" % str(盾问))
	引擎._reply = {"args": [1], "card_ids": [法术[0].id, 法术[1].id], "dst_ids": []}
	引擎._has_reply = true
	角色.p_timeline_3({"harm": 伤害, "src": 2, "dst": 1})
	检(int(伤害["point"]) == 1, "弃 2 张法术牌应让 3 点伤害减到 1")
	检(魔导.hand_cards.size() == 1, "弃掉的 2 张法术牌应离手")

	# 取消发动：不减伤
	角色._dun_step = 0
	var 伤害2: Dictionary = {"src": 2, "dst": 1, "point": 2, "cause": 0, "type": GConst.HarmType.Magic}
	检(角色.p_timeline_3({"harm": 伤害2, "src": 2, "dst": 1}) == BattleRole.WAIT,
		"【法力护盾】取消前应先问一次")
	引擎._reply = {"args": [0], "card_ids": [], "dst_ids": []}
	引擎._has_reply = true
	角色.p_timeline_3({"harm": 伤害2, "src": 2, "dst": 1})
	检(int(伤害2["point"]) == 2, "取消发动【法力护盾】不应减伤")

	# X 由玩家决定：即使伤害只有 1 点，也允许弃 1~3 张；多弃的部分只把伤害截到 0
	角色._dun_step = 0
	魔导.hand_cards.clear()
	for c: GCard in 法术:
		魔导.hand_cards.append(c.id)
	var 伤害3: Dictionary = {"src": 2, "dst": 1, "point": 1, "cause": 0, "type": GConst.HarmType.Magic}
	角色.p_timeline_3({"harm": 伤害3, "src": 2, "dst": 1})
	var 盾问3: Dictionary = _取询问(1, 7604)
	检(int(盾问3.get("card_max", 0)) == 3,
		"【法力护盾】的点选上限应等于手里法术牌数 3（X 由玩家决定），实际 card_max=%s" % str(盾问3.get("card_max", 0)))
	引擎._reply = {"args": [1], "card_ids": [法术[0].id, 法术[1].id], "dst_ids": []}
	引擎._has_reply = true
	角色.p_timeline_3({"harm": 伤害3, "src": 2, "dst": 1})
	检(int(伤害3["point"]) == 0, "弃 2 张法术牌应把 1 点伤害减到 0，不能变成负数")

	# 别人受伤不触发
	检(角色.p_timeline_3({"harm": {"src": 4, "dst": 2, "point": 2, "type": GConst.HarmType.Magic}}) == BattleRole.SUCCESS,
		"【法力护盾】只在自己受伤时触发")
