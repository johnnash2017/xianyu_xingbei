extends 自检用例
## 用例 54：把「判定助手」的纯函数钉死。
## 这些函数是阶段 3/4 从几个几百行的大函数里拆出来的，当时逐条对照过原实现；
## 这里用固定的输入把结论写下来，以后再动它们时有回归网。
## 覆盖：按钮可用性核心（三输入真值表）、选项规整的默认值、平行数组取数、
## 选项值对齐校验、按模式取需牌数、本步要不要选牌。

func _init() -> void:
	名称 = "判定助手等价性"


func 跑() -> void:
	await 等帧()
	var 窗: Control = load("res://scripts/ui/battle_mobile.gd").new()

	# ---- ① _按钮可用核心：enabled / 放行种类 / 系别 三个条件 ----
	var 风: int = GConst.CardElement.Wind
	var 火: int = GConst.CardElement.Fire
	var 攻击: int = GConst.ActionType.Attack
	var 法术: int = GConst.ActionType.Magic
	检(not 窗.call("_按钮可用核心", false, 攻击, 0, 攻击, 0), "服务端标了不可用时应置灰")
	检(bool(窗.call("_按钮可用核心", true, 攻击, 0, 攻击, 0)), "可用 + 放行攻击 + 不限系别 → 应可点")
	检(not bool(窗.call("_按钮可用核心", true, 法术, 0, 攻击, 0)), "本阶段只放行攻击时，法术技能应置灰")
	检(bool(窗.call("_按钮可用核心", true, GConst.ActionType.AttackSkill, 0, 攻击, 0)),
		"攻击类技能应归入攻击，被放行")
	检(not bool(窗.call("_按钮可用核心", true, 攻击, 风, 攻击, 火)), "技能固定风系、本阶段要求火系 → 应置灰")
	检(bool(窗.call("_按钮可用核心", true, 攻击, 风, 攻击, 风)), "系别相符 → 应可点")
	检(bool(窗.call("_按钮可用核心", true, 攻击, 风, 攻击, 0)), "本阶段不限系别时，固定系别不构成阻碍")
	检(bool(窗.call("_按钮可用核心", true, 法术, 0, GConst.ActionType.AttackMagic, 0)),
		"放行「攻击或法术」时，法术技能可点")

	# ---- ② _规整选项：缺省的键必须落回同一套默认值 ----
	var 空项: Dictionary = 窗.call("_规整选项", {})
	检(str(空项.get("文本", "x")) == "", "规整后 文本 默认空串")
	检(bool(空项.get("可用", false)), "规整后 可用 默认 true")
	检(int(空项.get("技能号", -9)) == 0, "规整后 技能号 默认 0")
	检(int(空项.get("卡牌", 0)) == -1, "规整后 卡牌 默认 -1")
	检(int(空项.get("需牌", -9)) == 0 and int(空项.get("需目标", -9)) == 0, "规整后 需牌 / 需目标 默认 0")
	检(int(空项.get("选牌来源", 0)) == -1, "规整后 选牌来源 默认 -1（沿用技能本体）")
	检((空项.get("牌白", [1]) as Array).is_empty(), "规整后 牌白 默认空")
	检(not bool(空项.get("不改提示", true)), "规整后 不改提示 默认 false")
	# 未知键要原样透传（以后加开关不会因为白名单漏抄而丢）
	var 带未知: Dictionary = 窗.call("_规整选项", {"未来开关": 7})
	检(int(带未知.get("未来开关", 0)) == 7, "规整选项 应把未知键原样透传")

	# ---- ③ 平行数组取数：越界落回默认，不抛错 ----
	检(int(窗.call("_第i项", [10, 20], 1, 99)) == 20, "_第i项 取第 2 个")
	检(int(窗.call("_第i项", [10, 20], 5, 99)) == 99, "_第i项 越界应落回默认")
	var 子: Array = 窗.call("_子id", {"ids": [3, 4]})
	检(子 == [3, 4], "_子id 取 ids")
	检((窗.call("_子id", {}) as Array).is_empty(), "_子id 缺省应给空数组")

	# ---- ④ 选项值对齐校验：条数对上还不够，每个 value 也要对上 ----
	窗.set("_skill_options", [1, 2] as Array[int])
	检(bool(窗.call("_选项值对得上", [{"value": 1}, {"value": 2}])), "value 逐个对上 → 通过")
	检(not bool(窗.call("_选项值对得上", [{"value": 1}, {"value": 9}])), "有一个 value 不符 → 拒绝")
	检(not bool(窗.call("_选项值对得上", [{"value": 1}, 2])), "不是字典的项 → 拒绝")

	# ---- ⑤ 按模式取需牌数 & 本步要不要选牌 ----
	窗.set("_skill_need_card", 2)
	窗.set("_skill_card_max", 3)
	窗.set("_need_cards", 1)
	窗.set("_mode", 3)
	检(int(窗.call("_选牌需求张数")) == 2, "mode 3 取询问通道的需牌")
	窗.set("_mode", 4)
	检(int(窗.call("_选牌需求张数")) == 2, "mode 4 取发动技能通道的需牌（合并后同一个字段）")
	窗.set("_mode", 2)
	检(int(窗.call("_选牌需求张数")) == 0, "应答类不按技能需牌算")
	窗.set("_mode", 3)
	窗.set("_skill_need_card", 0)
	窗.set("_skill_card_max", 0)
	检(not bool(窗.call("_牌过本步需牌数")), "mode 3 需牌和最多牌都为 0 → 整片灰")
	窗.set("_skill_card_max", 2)
	检(bool(窗.call("_牌过本步需牌数")), "mode 3 有最多牌（可弃可不弃）→ 可点")
	窗.set("_mode", 2)
	窗.set("_need_cards", 0)
	检(not bool(窗.call("_牌过本步需牌数")), "mode 2 不选牌 → 整片灰")
	窗.set("_need_cards", 1)
	检(bool(窗.call("_牌过本步需牌数")), "mode 2 要选牌 → 可点")
	窗.set("_mode", 1)
	检(bool(窗.call("_牌过本步需牌数")), "行动阶段不归这条管 → 放行")

	窗.free()
