extends 自检用例
## F1【魔弹融合】系别可配：
## - 基类默认仍是地 / 火，8 号魔导师 / 76 号节日魔导的行为与技能号不变；
## - dummy 水 / 火角色只接受水、火发动【魔弹融合】，地系被拒；
## - 【魔弹】本身始终能当魔弹使用 / 响应传递，但不算【魔弹融合】的发动牌。

## dummy 借用角色：模拟 47 爆食少女的「水 / 火可当魔弹」配置。
## 真实角色（47 / 87 / 107）在各自脚本里覆写 missile_fusion_elements()，
## 并在 v_missile / v_remissile 里路由到 can_use_as_missile() 即可复用同一套配置。
class 水火魔弹角色 extends BattleRole:
	func missile_fusion_elements() -> Array[int]:
		return [GConst.CardElement.Water, GConst.CardElement.Fire]

	func v_missile(card_id: int, _dst_id: int) -> int:
		if not player.has_hand_card(card_id) or not can_use_as_missile(Data.get_card(card_id)):
			return GConst.GE_INVALID_CARDID
		return GConst.GE_SUCCESS

	func v_remissile(card_id: int) -> int:
		if not player.has_hand_card(card_id) or not can_use_as_missile(Data.get_card(card_id)):
			return GConst.GE_INVALID_CARDID
		return GConst.GE_SUCCESS


func _init() -> void:
	名称 = "魔弹融合系别可配"


func _取系(元素: int) -> GCard:
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.element_enum() == 元素 \
				and c.card_name_enum() != GConst.CardName.Missile:
			return c
	return null


func _取魔弹() -> GCard:
	for c: GCard in Data.card_db:
		if c != null and not c.is_virtual and c.card_name_enum() == GConst.CardName.Missile:
			return c
	return null


func _放入手牌(玩家: BattlePlayer, 牌表: Array) -> void:
	玩家.hand_cards.clear()
	for 牌: GCard in 牌表:
		if 牌 != null and not 玩家.hand_cards.has(牌.id):
			玩家.hand_cards.append(牌.id)


func 跑() -> void:
	await 等帧(1)

	# ---- 基类默认：地 / 火（8 / 76 的现状），不依赖 player ----
	var 基类: BattleRole = BattleRole.new()
	检(基类.missile_fusion_elements() == [GConst.CardElement.Fire, GConst.CardElement.Earth],
		"基类【魔弹融合】的默认系别应仍是地 / 火")
	var 水: GCard = _取系(GConst.CardElement.Water)
	var 火: GCard = _取系(GConst.CardElement.Fire)
	var 地: GCard = _取系(GConst.CardElement.Earth)
	var 魔弹牌: GCard = _取魔弹()
	检(水 != null and 火 != null and 地 != null and 魔弹牌 != null,
		"卡库缺少水 / 火 / 地 / 魔弹牌，无法验证系别配置")
	if 水 == null or 火 == null or 地 == null or 魔弹牌 == null:
		return
	检(基类.can_use_as_missile(火) and 基类.can_use_as_missile(地),
		"基类默认配置应接受火系 / 地系牌")
	检(not 基类.can_use_as_missile(水), "基类默认配置不应接受水系牌")
	检(基类.can_use_as_missile(魔弹牌), "【魔弹】本身应始终可以当魔弹使用")
	检(not 基类.can_use_as_missile_fusion(魔弹牌), "【魔弹】本身不应算【魔弹融合】的发动牌")

	# ---- 4 人交替座次：1 蓝、2 红、3 蓝、4 红；dummy 放 1 号，真实 8 / 76 放 2 / 3 号 ----
	var 引擎: BattleEngine = BattleEngine.new()
	引擎.add_player(1, GConst.BLUE, "蓝一")
	引擎.add_player(2, GConst.RED, "红二")
	引擎.add_player(3, GConst.BLUE, "蓝三")
	引擎.add_player(4, GConst.RED, "红四")
	var 蓝一: BattlePlayer = 引擎.p(1)
	var 红二: BattlePlayer = 引擎.p(2)
	var 蓝三: BattlePlayer = 引擎.p(3)

	# dummy 水 / 火角色（47 的配置）
	蓝一.role_id = 47
	var 水火角色: 水火魔弹角色 = 水火魔弹角色.new()
	蓝一.role = 水火角色
	水火角色.setup(蓝一, 引擎)

	# 真实 8 / 76：脚本能创建，默认配置不变
	红二.role_id = 8
	var 魔导角色: BattleRole = BattleRole.create(8, 红二, 引擎)
	检(魔导角色 != null, "8 号角色脚本无法创建")
	if 魔导角色 == null:
		return
	红二.role = 魔导角色
	蓝三.role_id = 76
	var 节日角色: BattleRole = BattleRole.create(76, 蓝三, 引擎)
	检(节日角色 != null, "76 号角色脚本无法创建")
	if 节日角色 == null:
		return
	蓝三.role = 节日角色

	_放入手牌(蓝一, [水, 火, 地, 魔弹牌])
	_放入手牌(红二, [水, 火, 地, 魔弹牌])
	_放入手牌(蓝三, [水, 火, 魔弹牌])

	# ---- dummy 水 / 火：配置生效，牌表与校验同一口径 ----
	检(水火角色.missile_fusion_elements() == [GConst.CardElement.Water, GConst.CardElement.Fire],
		"dummy 角色的【魔弹融合】系别配置没生效")
	检(水火角色.can_use_as_missile(水) and 水火角色.can_use_as_missile(火),
		"水 / 火配置下应接受水系、火系牌")
	检(not 水火角色.can_use_as_missile(地), "水 / 火配置下不应接受地系牌")
	检(水火角色.can_use_as_missile(魔弹牌), "水 / 火配置下【魔弹】本身仍应能当魔弹使用")
	检(not 水火角色.can_use_as_missile_fusion(魔弹牌), "【魔弹】本身不应算【魔弹融合】的发动牌")
	var 融合牌: Array[int] = 水火角色.missile_fusion_hand_ids()
	检(融合牌.has(水.id) and 融合牌.has(火.id),
		"【魔弹融合】的牌表应包含配置的水 / 火牌：%s" % str(融合牌))
	检(not 融合牌.has(地.id), "【魔弹融合】的牌表不应包含地系牌：%s" % str(融合牌))
	检(not 融合牌.has(魔弹牌.id), "【魔弹融合】的牌表不应包含【魔弹】本身：%s" % str(融合牌))
	检(水火角色.v_missile(水.id, 2) == GConst.GE_SUCCESS, "水系牌应能当【魔弹】主动打出")
	检(水火角色.v_missile(地.id, 2) == GConst.GE_INVALID_CARDID, "地系牌不应能当【魔弹】主动打出")
	检(水火角色.v_remissile(水.id) == GConst.GE_SUCCESS, "水系牌应能响应传递【魔弹】")
	检(水火角色.v_remissile(魔弹牌.id) == GConst.GE_SUCCESS, "【魔弹】本身应能响应传递【魔弹】")
	检(水火角色.v_remissile(地.id) == GConst.GE_INVALID_CARDID, "地系牌不应能响应传递【魔弹】")

	var 水系融合: Dictionary = {"src_id": 1, "card_ids": [水.id], "dst_ids": [2]}
	检(水火角色.v_missile_fusion(水系融合) == GConst.GE_SUCCESS, "水系牌应能经【魔弹融合】打出")
	var 地系融合: Dictionary = {"src_id": 1, "card_ids": [地.id], "dst_ids": [2]}
	检(水火角色.v_missile_fusion(地系融合) == GConst.GE_INVALID_CARDID,
		"地系牌不应经水 / 火配置的【魔弹融合】打出")
	var 魔弹融合: Dictionary = {"src_id": 1, "card_ids": [魔弹牌.id], "dst_ids": [2]}
	检(水火角色.v_missile_fusion(魔弹融合) == GConst.GE_INVALID_CARDID,
		"【魔弹】本身不应占用【魔弹融合】的发动入口")
	var 队友目标: Dictionary = {"src_id": 1, "card_ids": [水.id], "dst_ids": [3]}
	检(水火角色.v_missile_fusion(队友目标) == GConst.GE_INVALID_PLAYERID,
		"【魔弹融合】的落点不应包含队友")

	# ---- 8 号魔导师：默认地 / 火与技能号 803 不变 ----
	检(魔导角色.missile_fusion_elements() == [GConst.CardElement.Fire, GConst.CardElement.Earth],
		"8 号魔导师的【魔弹融合】系别应仍是地 / 火")
	检(魔导角色.missile_fusion_skill() == 803, "8 号魔导师的【魔弹融合】技能号应仍是 803")
	检(魔导角色.can_use_as_missile(火) and 魔导角色.can_use_as_missile(地),
		"8 号魔导师应接受火 / 地牌当魔弹")
	检(not 魔导角色.can_use_as_missile(水), "8 号魔导师不应接受水系牌当魔弹")
	var 八融合牌: Array[int] = 魔导角色.missile_fusion_hand_ids()
	检(八融合牌.has(火.id) and 八融合牌.has(地.id) and not 八融合牌.has(水.id)
		and not 八融合牌.has(魔弹牌.id),
		"8 号魔导师的【魔弹融合】牌表应仍是火 / 地：%s" % str(八融合牌))
	var 八水融合: Dictionary = {"src_id": 2, "card_ids": [水.id], "dst_ids": [3]}
	检(魔导角色.v_missile_fusion(八水融合) == GConst.GE_INVALID_CARDID,
		"8 号魔导师不应把水系牌当【魔弹融合】打出")
	var 八火融合: Dictionary = {"src_id": 2, "card_ids": [火.id], "dst_ids": [3]}
	检(魔导角色.v_missile_fusion(八火融合) == GConst.GE_SUCCESS,
		"8 号魔导师仍应能把火系牌当【魔弹融合】打出")
	检(魔导角色.has_missile_mastery(), "8 号魔导师的【魔弹掌控】不应被 F1 改坏")

	# ---- 76 号节日魔导：默认地 / 火与技能号 7602 不变 ----
	检(节日角色.missile_fusion_elements() == [GConst.CardElement.Fire, GConst.CardElement.Earth],
		"76 号节日魔导的【魔弹融合】系别应仍是地 / 火")
	检(节日角色.missile_fusion_skill() == 7602, "76 号节日魔导的【魔弹融合】技能号应仍是 7602")
	检(节日角色.can_use_as_missile(火) and not 节日角色.can_use_as_missile(水),
		"76 号节日魔导仍应只认地 / 火")
	var 七六水融合: Dictionary = {"src_id": 3, "card_ids": [水.id], "dst_ids": [4]}
	检(节日角色.v_missile_fusion(七六水融合) == GConst.GE_INVALID_CARDID,
		"76 号节日魔导不应把水系牌当【魔弹融合】打出")
	var 七六火融合: Dictionary = {"src_id": 3, "card_ids": [火.id], "dst_ids": [4]}
	检(节日角色.v_missile_fusion(七六火融合) == GConst.GE_SUCCESS,
		"76 号节日魔导仍应能把火系牌当【魔弹融合】打出")
	检(节日角色.has_missile_mastery(), "76 号节日魔导的【魔弹掌握】不应被 F1 改坏")
