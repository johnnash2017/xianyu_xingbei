extends BattleRole
## EX魔弓（roleID 75）—— 特典版本
## 技能：
##   神风矢（7501，被动）：你的风系攻击牌对手无法应战
##   疾风追射（7502，响应）：主动攻击未命中时，弃 1 张法术牌【展示】，对本次攻击目标造成 2 点法术伤害
##   弓神候补（7503，被动）：可以使用神箭手的独有技（301 精准射击 / 302 闪光陷阱）
##   狙击（7504，必杀技 / 法术）：支付 1【水晶】，目标角色手牌补到 5 张【强制】，额外 +1【攻击行动】
##
## 借用关系（见《禁用3星与3.5星角色开发计划》F5 / data-audit A24）：
##   7503 只借用 301 / 302，且必须有带该技能的发动牌；不借用 303 ——
##   7504 与 303 同名但**独立技能行**，按本角色自己的 7504 播报与校验。
##   借用的源技能沿用技能表里的 301 / 302 号（播报、提示、指示器都按源技能取），
##   校验 + 询问 + 结算全部在 scripts/battle/skills/skill_archer.gd 里，本角色只做路由。
## 7501 / 7502 与弓之女神（3）的【闪电箭】(304) /【贯穿射击】(305) 同一口径：
##   同一套时机（攻击宣告 p_timeline_1 / 未命中 p_timeline_2_miss），改的只是系别与技能号。

const 神箭手技能脚本: GDScript = preload("res://scripts/battle/skills/skill_archer.gd")

const SHEN_FENG_SHI: int = 7501      # 神风矢（被动）
const JI_FENG_ZHUI_SHE: int = 7502   # 疾风追射（响应）
const GONG_SHEN_HOU_BU: int = 7503   # 弓神候补（被动，转发 301 / 302）
const JU_JI: int = 7504              # 狙击（法术 / 必杀技）

## 7503 借用的神箭手独有技 helper（构造传自己；301 的询问分步状态存在 helper 实例里）
var _神箭手 = null

## 神风矢本次攻击是否已处理：0＝本次攻击宣告还没播报 / SHEN_FENG_SHI＝已播报。
## 用自有变量而不是引擎 step：等【精准射击】回复时钩子会被重入，
## 重入时不能再播一次神风矢（与 role_gongnv 的闪电箭同一写法）。
var _shen_feng_shi_step: int = 0
## 疾风追射的推进阶段：0＝本次未命中还没处理 / STEP_DONE＝本次已处理（挡住 URGENT 重入）。
## 每次新的主动攻击宣告在 p_timeline_1 清回 0。
var _ji_feng_step: int = 0


func _init() -> void:
	_神箭手 = 神箭手技能脚本.new(self)


# ============================================================
# 技能栏：借用的【闪光陷阱】(302) + 自己的【狙击】(7504)
# ============================================================
func available_skills() -> Array:
	var out: Array = []
	# 7503 弓神候补：技能栏里出现的是借用的源技能 302【闪光陷阱】
	# （301 在弓之女神那边也不是技能栏按钮，只能在攻击宣告时响应，见 helper 可用技能()）
	out.append_array(_神箭手.可用技能())
	# 7504 狙击：有能量（水晶 / 宝石可顶）就能点；没有时照常下发、只置灰
	out.append({
		"type": GConst.ActionType.MagicSkill,
		"id": JU_JI,
		"need_card": 0,
		"need_target": 1,
		"enabled": player.get_energy() > 0,
	})
	return out


# ============================================================
# 法术技能校验 / 结算
# ============================================================
func v_magic_skill(action: Dictionary) -> int:
	# 302 交给神箭手 helper 校验；它不认识的号返回 V_NOT_OVERRIDE，交回这里
	var rc: int = _神箭手.v_magic_skill(action)
	if rc != V_NOT_OVERRIDE:
		return rc
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != JU_JI:
		return GConst.GE_INVALID_ACTION
	# 【水晶】费用：宝石可以顶水晶，用 get_energy() 统一判断（见《技能维护约定》猎巫人复盘第 2 条）
	if player.get_energy() <= 0:
		return GConst.GE_INVALID_ACTION
	# 目标角色（可以是自己）：允许客户端没带目标时按自己结算（与弓之女神【狙击】303 一致）
	var dsts: Array = action.get("dst_ids", [])
	if not dsts.is_empty() and engine.p(int(dsts[0])) == null:
		return GConst.GE_INVALID_PLAYERID
	return GConst.GE_SUCCESS


func p_magic_skill(action: Dictionary) -> int:
	# 302 交给神箭手 helper 结算；不是它负责的号返回 EMPTY_HANDLE，交回这里
	var rc: int = _神箭手.p_magic_skill(action)
	if rc != EMPTY_HANDLE:
		return rc
	if int(action.get("action_id", 0)) != JU_JI:
		return EMPTY_HANDLE
	return _ju_ji(action)


## 7504 狙击：支付 1 水晶（宝石可顶）→ 目标角色手牌补到 5 张【强制】→ 额外 +1 攻击行动。
## 摸牌走 push_draw（【强制】同样允许暗杀者【水影】这类「摸牌前」响应），
## 所以压入摸牌后返回 URGENT：引擎先结算摸牌，再跑行动结束钩子，最后才进入这份额外攻击行动。
func _ju_ji(action: Dictionary) -> int:
	var dsts: Array = action.get("dst_ids", [])
	var dst_id: int = int(dsts[0]) if not dsts.is_empty() else player.id
	var dst: BattlePlayer = engine.p(dst_id)
	if dst == null:
		return SUCCESS
	notice_skill(JU_JI, [dst_id])
	player.remove_energy(1)
	# direct=true：选中即进入额外攻击行动，不再多问一次；skip_notice=true：上面已播报过 7504
	player.add_action(GConst.ActionType.Attack, JU_JI, true, true)
	var 补: int = 5 - dst.hand_cards.size()
	engine._broadcast_game()
	if 补 > 0:
		engine.push_draw(dst_id, 补, JU_JI)
		return URGENT
	return SUCCESS


# ============================================================
# 攻击宣告后：神风矢（被动）→ 借用的精准射击（301）
# ============================================================
func p_timeline_1(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	if _shen_feng_shi_step == 0:
		_shen_feng_shi_step = SHEN_FENG_SHI
		# 新的一次主动攻击宣告：清掉上一击遗留的「疾风追射已处理」标记，
		# 否则上一击把它留在 STEP_DONE 后，这一击未命中就不再询问（同 role_gongnv 的贯穿射击）
		_ji_feng_step = 0
		_shen_feng_shi(ctx)
	# 7503 借用的 301 精准射击：带 301 的攻击牌才询问；没带就直接放行
	var r: int = _神箭手.应答攻击(ctx)
	if r == WAIT:
		return WAIT
	_shen_feng_shi_step = 0
	return SUCCESS


## 7501 神风矢：风系攻击牌对手无法应战（被动，无需询问；命中率直接置 NoReattack）。
## 暗系攻击本身已由引擎置 NoReattack，这里只补风系，不动其它系别。
func _shen_feng_shi(ctx: Dictionary) -> void:
	var card: GCard = Data.get_card(int(ctx.get("card_id", -1)))
	if card == null or card.element_enum() != GConst.CardElement.Wind:
		return
	ctx["hit_rate"] = GConst.HitRate.NoReattack
	notice_skill(SHEN_FENG_SHI, [int(ctx.get("dst", -1))])


# ============================================================
# 主动攻击未命中后：疾风追射（可选）
# ============================================================
func p_timeline_2_miss(ctx: Dictionary) -> int:
	if int(ctx.get("src", -1)) != player.id:
		return SUCCESS
	# 只对「主动攻击」生效（应战反击 is_active=false 不触发，与 305 贯穿射击一致）
	if not bool(ctx.get("is_active", false)):
		return SUCCESS
	if _ji_feng_step >= STEP_DONE:
		return SUCCESS
	if _ji_feng_step == 0:
		_ji_feng_step = JI_FENG_ZHUI_SHE
	# 只能弃法术牌：手里没有法术牌就没什么可弃，不弹询问（弹了也只能取消）
	var 法术牌: Array[int] = magic_hand_ids()
	if 法术牌.is_empty():
		_ji_feng_step = STEP_DONE
		return SUCCESS
	if not engine.has_reply():
		# cards 白名单与服务端校验同一口径：界面只让这些法术牌可点
		询问(player.id, JI_FENG_ZHUI_SHE, 1, 0, GConst.CardSource.Hand, [], 0, "magic", 法术牌)
		return WAIT
	var r: Dictionary = take_skill_reply_full()
	# 本次未命中已处理：置 STEP_DONE 挡住 URGENT 回来时的重入；下一次攻击在 p_timeline_1 清回 0
	_ji_feng_step = STEP_DONE
	var args: Array = r.get("args", [])
	if args.is_empty() or int(args[0]) != 1:
		return SUCCESS
	var cards: Array = r.get("card_ids", [])
	if cards.is_empty():
		return SUCCESS
	var cid: int = int(cards[0])
	var card: GCard = Data.get_card(cid)
	if card == null or not card.is_magic() or not player.has_hand_card(cid):
		return SUCCESS
	var dst_id: int = int(ctx.get("dst", -1))
	if engine.p(dst_id) == null:
		return SUCCESS
	notice_skill(JI_FENG_ZHUI_SHE, [dst_id])
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": [cid], "is_real": true,
	})
	engine.push_harm({
		"src": player.id, "dst": dst_id, "point": 2,
		"cause": JI_FENG_ZHUI_SHE, "type": GConst.HarmType.Magic,
	})
	engine.take_from_hand(player.id, [cid], true)
	engine.to_discard([cid], {"owner": player.id, "source": "hand", "cause": JI_FENG_ZHUI_SHE})
	engine._broadcast_game()
	return URGENT
