extends 自检用例
## 用例 50：攻击伤害预览的「真服务端 → 真协议 → 真客户端」闭环。
##
## 和其它用例不同，这里**不手搓 CmdReq**：
##   1) 用真的 BattleEngine + 真的角色脚本发询问；
##   2) 从引擎的 send_cb 里抓下发的 CmdReq（也就是线上真正会发出去的那条）；
##   3) 把它喂给真的 BattleUIMobile，检查头像提示画出来的数字。
##
## 覆盖两条最容易回归的路径：
##   · 格斗【蓄力一击 / 气绝崩击】：同一个询问两个选项、伤害不同（preview_base + option_damages）；
##   · 狂战士【血影狂刀】：狂化 +1 由服务端并进 preview_base（preview_damage 再加刀本身的 +2）。

var 引擎: BattleEngine = null
var 发送记录: Array = []


func _init() -> void:
	名称 = "攻击伤害预览（真引擎）"


## 客户端发完应答会「稍等一拍」再清界面：断言按真实时间等，不按帧数
func 等帧(_数: int = 2) -> void:
	var 截止: int = Time.get_ticks_msec() + 220
	while Time.get_ticks_msec() < 截止:
		await get_tree().process_frame


func _建引擎(角色号: int) -> BattleRole:
	引擎 = BattleEngine.new()
	发送记录.clear()
	引擎.send_cb = func(pid: int, msg: int, data: Dictionary) -> void:
		发送记录.append({"pid": pid, "msg": msg, "data": data})
	引擎.add_player(1, GConst.BLUE, "我")
	引擎.add_player(2, GConst.BLUE, "队友")
	引擎.add_player(3, GConst.RED, "对手甲")
	引擎.add_player(4, GConst.RED, "对手乙")
	引擎.start_with_roles({})
	var 玩家: BattlePlayer = 引擎.p(1)
	var 脚本: GDScript = load(str(Data.role_script(角色号))) as GDScript
	var 角色: BattleRole = 脚本.new()
	# 先定身份、再 setup：BattleRole.setup 按 player.role_id 建指示物 / 盖牌槽
	玩家.role_id = 角色号
	角色.setup(玩家, 引擎)
	玩家.role = 角色
	玩家.hand_cards.clear()
	引擎.phase = BattleEngine.Phase.Playing
	引擎.round_id = 1
	return 角色


## 最近一次发给某玩家的 CmdReq 里的第一条询问
func _最近询问(pid: int) -> Dictionary:
	for i: int in range(发送记录.size() - 1, -1, -1):
		var r: Dictionary = 发送记录[i]
		if int(r.get("msg", 0)) != GConst.Msg.CmdReq or int(r.get("pid", -1)) != pid:
			continue
		var cmds: Array = (r.get("data", {}) as Dictionary).get("commands", [])
		if not cmds.is_empty():
			return cmds[0]
	return {}


func _建窗() -> Control:
	Logic.my_player_id = 1
	var 玩家: Array[GPlayer] = [
		GPlayer.new(1, GConst.BLUE, "我"),
		GPlayer.new(2, GConst.RED, "对手A"),
		GPlayer.new(3, GConst.RED, "对手B"),
	]
	Data.player_list = 玩家
	Data.hand_cards = [] as Array[GCard]
	Data.cover_cards = [] as Array[GCard]
	var 窗: Control = (load("res://scenes/BattleUIMobile.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(窗)
	return 窗


func 跑() -> void:
	await 等帧(2)
	UI.goto_lobby()
	await 等帧(2)
	await _检格斗蓄力气绝()
	await _检血影狂刀()
	await _检多重射击()
	await _检狂化结算()
	await _检染污者结算()


## 格斗：百式形态下问蓄力/气绝 —— 基准＝保持百式（2+2），蓄力档 = 当前 +1
func _检格斗蓄力气绝() -> void:
	var 角色: BattleRole = _建引擎(GConst.角色_格斗)
	var 玩家: BattlePlayer = 引擎.p(1)
	玩家.tap = true
	角色.set("bai_shi_target", 3)
	角色._set_dou_qi(1)
	var harm: Dictionary = {"src": 1, "dst": 3, "point": 2,
		"type": GConst.HarmType.Attack, "is_active": true}
	var ctx: Dictionary = {"src": 1, "dst": 3, "is_active": true, "harm": harm}
	角色._询问攻击加成(ctx)
	var cmd: Dictionary = _最近询问(1)
	检(not cmd.is_empty(), "格斗的蓄力/气绝询问没有下发")
	检(int(cmd.get("preview_base", 0)) == 4,
		"基准应是「保持百式」的 4 点（实际 %d）" % int(cmd.get("preview_base", 0)))
	var 选项伤害: Array = cmd.get("option_damages", [])
	检(选项伤害 == [3, 4],
		"两个选项应各带自己的伤害 [3, 4]（实际 %s）" % str(选项伤害))

	var 窗: Control = _建窗()
	await 等帧(2)
	Logic.command_received.emit({"cmd_type": GConst.CmdType.Respond, "commands": [cmd]})
	await 等帧(2)
	检(int(窗.get("_mode")) == 3, "真实询问没让客户端进入应答态（_mode=%d）" % int(窗.get("_mode")))
	窗.call("_选中二级选项", GConst.技能_蓄力一击, 0)
	await 等帧(1)
	var 提示: Dictionary = 窗.call("_攻击伤害头像提示")
	检(str(提示.get(3, "")) == "[zwj]4 攻击伤害\n3 攻击伤害",
		"选【蓄力一击】应画「4 划掉 → 3」（实际：%s）" % str(提示.get(3, "")))
	窗.call("_选中二级选项", GConst.技能_气绝崩击, 1)
	await 等帧(1)
	var 气绝: Dictionary = 窗.call("_攻击伤害头像提示")
	检(气绝.is_empty(), "选【气绝崩击】不改伤害，不该画两行（实际：%s）" % str(气绝))
	var 单值: Dictionary = 窗.call("_预览伤害头像提示")
	检(str(单值.get(3, "")) == "4 攻击伤害",
		"气绝/取消时应显示保持百式的 4 点（实际：%s）" % str(单值.get(3, "")))
	窗.free()


## 狂战士：狂化 +1 已并进基准，血影狂刀再 +2
func _检血影狂刀() -> void:
	var 牌号: int = 0
	for c: GCard in Data.card_db:
		if c != null and c.has_skill_id(GConst.技能_血影狂刀):
			牌号 = c.id
			break
	检(牌号 > 0, "卡库里找不到带【血影狂刀】的牌，用例前提不成立")
	if 牌号 <= 0:
		return

	var 角色: BattleRole = _建引擎(GConst.角色_狂战士)
	# 目标手牌 2 张 → 刀加伤 +2；攻击者手牌为空 → 狂化只有无条件的 +1
	引擎.p(3).hand_cards = [Data.card_db[0].id, Data.card_db[1].id] as Array[int]
	var harm: Dictionary = {"src": 1, "dst": 3, "point": 2,
		"type": GConst.HarmType.Attack, "is_active": true}
	var ctx: Dictionary = {"src": 1, "dst": 3, "is_active": true, "card_id": 牌号, "harm": harm}
	角色._xue_ying_kuang_dao(ctx)
	var cmd: Dictionary = _最近询问(1)
	检(not cmd.is_empty(), "血影狂刀的询问没有下发")
	检(int(cmd.get("preview_base", 0)) == 3,
		"基准应含狂化 +1（2+1=3，实际 %d）" % int(cmd.get("preview_base", 0)))
	检(int(cmd.get("preview_damage", -1)) == 5,
		"发动后应是 3+2=5（实际 %d）" % int(cmd.get("preview_damage", -1)))

	var 窗: Control = _建窗()
	await 等帧(2)
	Logic.command_received.emit({"cmd_type": GConst.CmdType.Respond, "commands": [cmd]})
	await 等帧(2)
	var 提示: Dictionary = 窗.call("_攻击伤害头像提示")
	检(str(提示.get(3, "")) == "[zwj]3 攻击伤害\n5 攻击伤害",
		"血影狂刀应画「3 划掉 → 5」（实际：%s）" % str(提示.get(3, "")))
	窗.free()


## 魔弓【多重射击】：行动结束响应的选项自带「基准 + 发动后的伤害」；
## 虚拟攻击是暗系，场上结界师有暗系【结界】时基准要含荒神 +1
func _检多重射击() -> void:
	var 风牌: int = 0
	var 暗牌: int = 0
	for c: GCard in Data.card_db:
		if c == null:
			continue
		if 风牌 == 0 and c.element_enum() == GConst.CardElement.Wind:
			风牌 = c.id
		if 暗牌 == 0 and c.element_enum() == GConst.CardElement.Darkness:
			暗牌 = c.id
	检(风牌 > 0 and 暗牌 > 0, "卡库找不到风系/暗系牌，用例前提不成立")
	if 风牌 <= 0 or 暗牌 <= 0:
		return

	var 魔弓: BattleRole = _建引擎(26)   # 魔弓（roleID 26，工程里没有 角色_魔弓 常量）
	引擎.p(1).cover_cards = [风牌] as Array[int]
	# 给乙挂结界师，盖牌区里放一张暗系【结界】→ 暗系攻击荒神 +1
	var 脚本: GDScript = load(str(Data.role_script(GConst.角色_结界师))) as GDScript
	var 结界角色: BattleRole = 脚本.new()
	引擎.p(2).role_id = GConst.角色_结界师
	结界角色.setup(引擎.p(2), 引擎)
	引擎.p(2).role = 结界角色
	引擎.p(2).cover_cards = [暗牌] as Array[int]
	检(引擎.攻击元素加伤(GConst.CardElement.Darkness) == 1,
		"暗系结界在场时，暗系的按系别加伤应为 1（实际 %d）" % 引擎.攻击元素加伤(GConst.CardElement.Darkness))

	var 选项们: Array = 魔弓.action_end_options({})
	检(not 选项们.is_empty(), "有多重射击可发动时，行动结束选项不该为空")
	if 选项们.is_empty():
		return
	var 项: Dictionary = 选项们[0]
	检(bool(项.get("enabled", false)), "有风系充能、有可攻目标时多重射击应可发动")
	检(int(项.get("preview_base", 0)) == 3,
		"多重射击基准应是 2+荒神 1=3（实际 %d）" % int(项.get("preview_base", 0)))
	检(int(项.get("damage", 0)) == 2,
		"多重射击发动后应是 3-1=2（实际 %d）" % int(项.get("damage", 0)))


## 结算走同一个入口：命中时引擎按 p_attack_preview 把狂化并进 harm（角色自己不再改）
func _检狂化结算() -> void:
	var 角色: BattleRole = _建引擎(GConst.角色_狂战士)
	引擎.p(3).hand_cards = [] as Array[int]
	var harm: Dictionary = {"src": 1, "dst": 3, "point": 2, "cause": GConst.CAUSE_ATTACK,
		"type": GConst.HarmType.Attack, "is_active": true, "card_id": 0}
	引擎.push(BattleEngine.STimeline2Hit.new(harm))
	引擎.run()
	检(int(harm["point"]) == 3,
		"狂化应由引擎统一并入结算：2+1=3（实际 %d）" % int(harm["point"]))


## 染污者的被动：攻击伤害走引擎统一入口，法术伤害仍由角色自己加
func _检染污者结算() -> void:
	var 角色: BattleRole = _建引擎(83)   # 染污者（roleID 83）
	var 攻击: Dictionary = {"src": 1, "dst": 3, "point": 2, "cause": GConst.CAUSE_ATTACK,
		"type": GConst.HarmType.Attack, "is_active": true, "card_id": 0}
	引擎.push(BattleEngine.STimeline2Hit.new(攻击))
	引擎.run()
	检(int(攻击["point"]) == 2,
		"目标没有治疗、自己没横置时，染污者的攻击不该有被动加伤（实际 %d）" % int(攻击["point"]))
	# 法术伤害：不进 T2，仍由 _被动改伤 在 T3 加（这里直接调它验证分支没被误删）
	var 法术: Dictionary = {"src": 1, "dst": 3, "point": 2, "type": GConst.HarmType.Magic}
	角色.call("_被动改伤", 法术)
	检(int(法术["point"]) == 2,
		"没触发条件时法术伤害也不该加（实际 %d）" % int(法术["point"]))
