extends Node
## 临时：验证潜行改为「二级技能栏选 摸 1 张牌 / 不摸牌」后的行为（用完即删）


func _ready() -> void:
	await get_tree().process_frame
	_情形(0)
	_情形(1)


func _情形(选中: int) -> void:
	var e: BattleEngine = BattleEngine.new()
	e.add_player(1, GConst.BLUE, "暗杀者")
	e.add_player(2, GConst.RED, "对手")
	e.start_with_roles({1: 5, 2: 0})
	var 暗杀者: BattlePlayer = e.p(1)
	var 角色: BattleRole = 暗杀者.role
	暗杀者.set_gem(2)
	if 选中 == 0:
		for sk: Dictionary in 角色.available_skills():
			if int(sk.get("id", 0)) == 503:
				print("【结果】潜行技能项 arg_choices=%s" % str(sk.get("arg_choices", [])))
		for c: Variant in e.action_commands(1, GConst.ActionType.SpecialSkill, true, false, false):
			var d: Dictionary = c
			var a: Array = d.get("args", [])
			if not a.is_empty() and int(a[0]) == 503:
				print("【结果】下发给界面的潜行 arg_choices=%s" % str(d.get("arg_choices", [])))
	var 手牌前: int = 暗杀者.hand_cards.size()
	var 宝石前: int = 暗杀者.gem
	var 上限前: int = 暗杀者.hand_cards_max
	角色.p_special_skill({"action_id": 503, "args": [选中], "src_id": 1})
	var 栈: Array = []
	for st: Variant in e._states:
		if st is BattleEngine.SDraw:
			栈.append("SDraw")
		elif st is BattleEngine.SHook:
			栈.append("SHook")
		else:
			栈.append("其它")
	print("【结果】选中=%d → tap=%s gem %d→%d 上限 %d→%d 手牌 %d→%d 栈(底→顶)=%s" % [
		选中, str(暗杀者.tap), 宝石前, 暗杀者.gem, 上限前, 暗杀者.hand_cards_max,
		手牌前, 暗杀者.hand_cards.size(), str(栈)])
	if 选中 == 1:
		get_tree().quit()
