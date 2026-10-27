class_name 神箭手技能
extends RefCounted
## F5-A：神箭手（弓之女神，角色 3）独有技 helper ——【301 精准射击】/【302 闪光陷阱】。
##
## 为什么单独抽一份：75 EX魔弓【7503 弓神候补】写着「你可以使用神箭手的独有技」，但
## role_gongnv.gd 的钩子直接挂在弓之女神自己身上，不能拿来给别的角色用。这里把两颗牌的
## 「校验 + 询问 + 结算」抽成与角色无关的对象，借用角色只在四个入口转发一次；
## 原角色 role_gongnv.gd 保持不动，确保它现在的行为零回归。
##
## 接入示例（用 preload，不依赖编辑器生成的全局类缓存）：
##   const 神箭手技能脚本: GDScript = preload("res://scripts/battle/skills/skill_archer.gd")
##   var 神箭手 = 神箭手技能脚本.new(self)   # 构造传自己的 BattleRole
##
##   func available_skills() -> Array:
##       var out: Array = []
##       out.append_array(神箭手.可用技能())
##       # …自己的技能…
##       return out
##
##   func v_magic_skill(action: Dictionary) -> int:
##       var rc: int = 神箭手.v_magic_skill(action)
##       if rc != BattleRole.V_NOT_OVERRIDE:
##           return rc
##       # …自己的法术技能…
##
##   func p_magic_skill(action: Dictionary) -> int:
##       var rc: int = 神箭手.p_magic_skill(action)
##       if rc != BattleRole.EMPTY_HANDLE:
##           return rc
##       # …自己的法术技能…
##
##   func p_timeline_1(ctx: Dictionary) -> int:
##       # …自己的攻击宣告被动（如 7501 风系无法应战）…
##       return 神箭手.应答攻击(ctx)
##
## 技能号沿用技能表的 301 / 302（借用的就是这两行技能，不新建同名技能行）：
## 播报、头像提示、技能指示器、测试都按这两个号取。
## 301 不是技能栏按钮（原版也只能在「主动攻击宣告」时响应），可用技能() 只给 302。
## 301 的询问分步状态放在本实例变量里，不写进玩家 / 角色。

const 精准射击: int = 301
const 闪光陷阱: int = 302

## 对借用角色只持弱引用，避免「角色 → helper → 角色」互相强引用、RefCounted 回收不掉
var _role_ref: WeakRef = null
## 301 的询问进度：0＝还没问；精准射击(301)＝已问、等回复；STEP_DONE＝本次攻击已处理完
var _精准射击_step: int = 0
## 上一次询问对应哪张攻击牌：换了一张牌＝新的一次攻击宣告，重新允许询问
var _精准射击_牌: int = -1


func _init(role: BattleRole) -> void:
	_role_ref = weakref(role) if role != null else null


func _取角色() -> BattleRole:
	return _role_ref.get_ref() as BattleRole if _role_ref != null else null


func _取玩家() -> BattlePlayer:
	var r: BattleRole = _取角色()
	return r.player if r != null else null


func _取引擎() -> BattleEngine:
	var r: BattleRole = _取角色()
	return r.engine if r != null else null


# ============================================================
# 对借用角色公开的入口
# ============================================================
## 本 helper 负责的技能号（301 / 302）
func 技能号() -> Array[int]:
	return [精准射击, 闪光陷阱]


## 借用角色判断某个技能号要不要交给本 helper
func 是否借用技能(skill_id: int) -> bool:
	return skill_id == 精准射击 or skill_id == 闪光陷阱


## 技能栏按钮（302 闪光陷阱）。没有带 302 的发动牌时照常下发、只把 enabled 置 false，
## 符合「不可用项置灰、不消失」的约定；cards 与 v_magic_skill 的牌校验同一口径。
func 可用技能() -> Array:
	var r: BattleRole = _取角色()
	if r == null:
		return []
	var 牌: Array[int] = r.hand_ids_with_skill(闪光陷阱)
	return [{
		"type": GConst.ActionType.MagicSkill,
		"id": 闪光陷阱,
		"need_card": 1,
		"need_target": 1,
		"enabled": not 牌.is_empty(),
		"cards": 牌,
	}]


## 302 的发动校验（v_magic_skill 用）：手牌里带【闪光陷阱】的牌作发动牌，目标必须是场上角色。
## 不是 302 时返回 V_NOT_OVERRIDE，借用角色据此继续走自己的校验。
func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != 闪光陷阱:
		return BattleRole.V_NOT_OVERRIDE
	var p: BattlePlayer = _取玩家()
	if p == null:
		return GConst.GE_INVALID_ACTION
	if int(action.get("src_id", -1)) != p.id:
		return GConst.GE_INVALID_PLAYERID
	var cards: Array = action.get("card_ids", [])
	if cards.is_empty():
		return GConst.GE_INVALID_CARDID
	var cid: int = int(cards[0])
	var card: GCard = Data.get_card(cid)
	if not p.has_hand_card(cid) or card == null or not card.has_skill_id(闪光陷阱):
		return GConst.GE_INVALID_ACTION
	var dsts: Array = action.get("dst_ids", [])
	if dsts.is_empty():
		return GConst.GE_INVALID_PLAYERID
	var e: BattleEngine = _取引擎()
	if e == null or e.p(int(dsts[0])) == null:
		return GConst.GE_INVALID_PLAYERID
	return GConst.GE_SUCCESS


## 302 的结算：亮出发动牌 → 弃置 → 对目标造成 2 点法术伤害③。
## 结算链与 role_gongnv._shan_guang_xian_jing 保持一致（先播报、再压伤害、最后离手入弃牌）。
## 不是 302 时返回 EMPTY_HANDLE，借用角色据此继续处理自己的法术技能。
func p_magic_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != 闪光陷阱:
		return BattleRole.EMPTY_HANDLE
	var r: BattleRole = _取角色()
	var p: BattlePlayer = _取玩家()
	var e: BattleEngine = _取引擎()
	if r == null or p == null or e == null:
		return BattleRole.EMPTY_HANDLE
	var cards: Array = action.get("card_ids", [])
	if cards.is_empty():
		return BattleRole.SUCCESS
	var cid: int = int(cards[0])
	var dsts: Array = action.get("dst_ids", [])
	var dst_id: int = int(dsts[0]) if not dsts.is_empty() else p.id
	r.notice_skill(闪光陷阱, [dst_id])
	e.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": p.id, "dst_id": p.id,
		"card_ids": [cid], "is_real": true,
	})
	e.push_harm({
		"src": p.id, "dst": dst_id, "point": 2,
		"cause": 闪光陷阱, "type": GConst.HarmType.Magic,
	})
	e.take_from_hand(p.id, [cid], true)
	e.to_discard([cid])
	e._broadcast_game()
	return BattleRole.URGENT


## 301 的发动条件：这张攻击牌带【精准射击】（与原版 role_gongnv 的检查一致）
func 可精准射击(card_id: int) -> bool:
	var card: GCard = Data.get_card(card_id)
	return card != null and card.has_skill_id(精准射击)


## 主动攻击宣告（p_timeline_1）时的 301 响应：先问是否发动，发动则本次攻击强制命中、伤害 -1。
## 借用角色在自己的 p_timeline_1 末尾转发本方法；返回值遵守角色钩子约定（SUCCESS / WAIT）。
func 应答攻击(ctx: Dictionary) -> int:
	var r: BattleRole = _取角色()
	var p: BattlePlayer = _取玩家()
	var e: BattleEngine = _取引擎()
	if r == null or p == null or e == null or int(ctx.get("src", -1)) != p.id:
		return BattleRole.SUCCESS
	var cid: int = int(ctx.get("card_id", -1))
	if not 可精准射击(cid):
		return BattleRole.SUCCESS
	# 换了一张攻击牌＝新的一次攻击宣告：允许重新询问（同一张牌处理完就不再问）
	if cid != _精准射击_牌:
		_精准射击_牌 = cid
		_精准射击_step = 0
	if _精准射击_step == BattleRole.STEP_DONE:
		return BattleRole.SUCCESS
	if _精准射击_step == 0:
		_精准射击_step = 精准射击
		var 原伤害: int = 0
		var harm: Variant = ctx.get("harm", null)
		if harm is Dictionary:
			原伤害 = int((harm as Dictionary).get("point", 0))
		# 目标随询问下发（客户端自动选中并锁死），并把发动前的本次攻击伤害作为预览基准：
		# 技能指示器【精准射击】的 -1 由客户端在头像上现算「原值划掉 → 新值」
		r.询问(p.id, 精准射击, 0, 0, GConst.CardSource.Hand, [], 0, "", [], true,
			0, -1, [int(ctx.get("dst", -1))], -1, {}, 原伤害)
		return BattleRole.WAIT
	# 已问过、正等回复：回复还没回来就继续等
	if not e.has_reply():
		return BattleRole.WAIT
	var 发动: bool = r.take_skill_reply()
	_精准射击_step = BattleRole.STEP_DONE
	if not 发动:
		return BattleRole.SUCCESS
	_应用精准射击(ctx)
	return BattleRole.SUCCESS


## 301 的结算：强制命中（NoMiss）、本次攻击伤害 -1（与技能说明一致）
func _应用精准射击(ctx: Dictionary) -> void:
	var r: BattleRole = _取角色()
	if r == null:
		return
	r.notice_skill(精准射击, [int(ctx.get("dst", -1))])
	ctx["hit_rate"] = GConst.HitRate.NoMiss
	var harm: Variant = ctx.get("harm", null)
	if harm is Dictionary:
		var 伤害: Dictionary = harm as Dictionary
		伤害["point"] = int(伤害.get("point", 0)) - 1
