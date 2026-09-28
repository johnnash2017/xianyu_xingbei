class_name BattleRole
extends RefCounted
## 角色基类（对照服务端 DiceGameServer/PlayerEntity 的 p_* / v_* 钩子 + role/*）
##
## 钩子约定：
## - 统一签名为 func p_xxx(ctx: Dictionary) -> int，返回 SUCCESS / WAIT / URGENT
## - 引擎在对应时机对「每个玩家」调用一次；若某角色返回 WAIT，则整个钩子轮次暂停，
##   收到该玩家的回复后从同一位玩家继续调用（因此角色内部用 step 记录进度）
## - step 由引擎在每次钩子轮次开始时统一重置为 0；角色用 engine.ask_skill() 请求玩家输入
## - 若角色在钩子内压入了新的引擎状态（如 push_harm 造成伤害），应「先把 step 推进过该子技能」
##   再返回 URGENT，引擎会先执行新状态、之后再回到本钩子继续

const SUCCESS: int = 0
const EMPTY_HANDLE: int = 1
const WAIT: int = 2
const URGENT: int = 3
## 子步骤「已完成」标记。取值必须大于所有子步骤常量（各角色的子步骤用 5 位技能号变体，
## 如 32031 / 36063 / 37052），否则 `step >= STEP_DONE` 的守卫会把「刚压入的子步骤」误判为已完成，
## 导致等待玩家回复后不再回到该钩子继续结算。
const STEP_DONE: int = 1000000
## 牌类校验返回此值表示「角色不覆写」，引擎会退回通用实现
const V_NOT_OVERRIDE: int = -1

var player: BattlePlayer = null
var engine: BattleEngine = null
var step: int = 0


func setup(p: BattlePlayer, e: BattleEngine) -> void:
	player = p
	engine = e


# ============================================================
# 钩子（默认空实现）
# ============================================================
func p_before_turn_begin(_ctx: Dictionary) -> int: return SUCCESS
func p_turn_begin(_ctx: Dictionary) -> int: return SUCCESS
func p_turn_begin_shiren(_ctx: Dictionary) -> int: return SUCCESS
func p_between_weak_and_action(_ctx: Dictionary) -> int: return SUCCESS
func p_before_action(_ctx: Dictionary) -> int: return SUCCESS
func p_boot(_ctx: Dictionary) -> int: return SUCCESS
func p_before_attack(_ctx: Dictionary) -> int: return SUCCESS
func p_after_attack(_ctx: Dictionary) -> int: return SUCCESS
func p_before_magic(_ctx: Dictionary) -> int: return SUCCESS
func p_after_magic(_ctx: Dictionary) -> int: return SUCCESS
func p_before_special(_ctx: Dictionary) -> int: return SUCCESS
func p_after_special(_ctx: Dictionary) -> int: return SUCCESS
func p_attacked(_ctx: Dictionary) -> int: return SUCCESS
func p_timeline_1(_ctx: Dictionary) -> int: return SUCCESS
func p_timeline_2_hit(_ctx: Dictionary) -> int: return SUCCESS
func p_timeline_2_miss(_ctx: Dictionary) -> int: return SUCCESS
func p_timeline_3(_ctx: Dictionary) -> int: return SUCCESS
func p_timeline_4(_ctx: Dictionary) -> int: return SUCCESS
func p_timeline_5(_ctx: Dictionary) -> int: return SUCCESS
func p_timeline_6(_ctx: Dictionary) -> int: return SUCCESS
func p_timeline_6_drawn(_ctx: Dictionary) -> int: return SUCCESS
func p_harm_end(_ctx: Dictionary) -> int: return SUCCESS
func p_before_lose_morale(_ctx: Dictionary) -> int: return SUCCESS
func p_lose_morale(_ctx: Dictionary) -> int: return SUCCESS
func p_true_lose_morale(_ctx: Dictionary) -> int: return SUCCESS
# 说明：服务端的 p_cover_change / p_hand_change（盖牌/手牌变动时对全体触发）在本引擎没有通用触发点，
# 相关角色的效果改由各自的显式触发点处理（如蝶舞在移除【茧】处调用凋灵、巫女在多个结算点检查脱形态），
# 因此这里不再保留同名空钩子，避免被误当成「已接入」。
func p_show_hand(_ctx: Dictionary) -> int: return SUCCESS
func p_tap(_ctx: Dictionary) -> int: return SUCCESS
func p_basic_effect_change(_ctx: Dictionary) -> int: return SUCCESS
func p_additional_action(_ctx: Dictionary) -> int: return SUCCESS
func p_turn_end(_ctx: Dictionary) -> int: return SUCCESS
func p_after_turn_end(_ctx: Dictionary) -> int: return SUCCESS


# ============================================================
# 牌类校验覆写（返回 V_NOT_OVERRIDE 表示不覆写，退回通用实现）
# 想「通用校验 + 追加限制」时，先调 player.base_v_xxx(...) 再判断
# ============================================================
func v_allow_action(_action_type: int, _args: Array) -> int: return V_NOT_OVERRIDE
func v_attack(_card_id: int, _dst_id: int, _players: Dictionary) -> int: return V_NOT_OVERRIDE
func v_reattack(_card_id: int, _attack_card_id: int) -> int: return V_NOT_OVERRIDE
func v_block(_card_id: int) -> int: return V_NOT_OVERRIDE
func v_shield(_dst_id: int, _players: Dictionary) -> int: return V_NOT_OVERRIDE
func v_weaken(_dst_id: int, _players: Dictionary) -> int: return V_NOT_OVERRIDE
func v_missile(_card_id: int, _dst_id: int) -> int: return V_NOT_OVERRIDE
func v_remissile(_card_id: int) -> int: return V_NOT_OVERRIDE
func v_buy(_args: Array) -> int: return V_NOT_OVERRIDE
func v_attacked() -> int: return V_NOT_OVERRIDE
func v_additional_action(_cause: int) -> int: return V_NOT_OVERRIDE


# ============================================================
# 校验与技能执行（默认无效）
# ============================================================
func v_attack_skill(_action: Dictionary) -> int: return GConst.GE_EMPTY_HANDLE
func v_magic_skill(_action: Dictionary) -> int: return GConst.GE_EMPTY_HANDLE
func v_special_skill(_action: Dictionary) -> int: return GConst.GE_EMPTY_HANDLE
func p_attack_skill(_action: Dictionary) -> int: return EMPTY_HANDLE
func p_magic_skill(_action: Dictionary) -> int: return EMPTY_HANDLE
func p_special_skill(_action: Dictionary) -> int: return EMPTY_HANDLE


## 行动阶段可选的技能列表；每项：
## { "type": ActionType.*_Skill, "id": CAUSE, "name": 按钮名, "need_card": 0/1, "need_target": 0/1 }
func available_skills() -> Array:
	return []


## 引擎按名字调用钩子
func call_hook(hook: String, ctx: Dictionary) -> int:
	if not has_method(hook):
		return SUCCESS
	return call(hook, ctx)


# ============================================================
# 常用工具
# ============================================================
## 询问本角色是否发动某技能（对应客户端「确定/取消」），返回 WAIT
func ask_self_skill(skill_id: int) -> int:
	engine.ask_skill(player.id, skill_id)
	return WAIT


## 读取技能询问回复：返回 true=发动、false=放弃
func take_skill_reply() -> bool:
	var r: Dictionary = engine.take_reply()
	var args: Array = r.get("args", [])
	return args.size() > 0 and int(args[0]) == 1


## 读取技能询问的完整回复（需要卡牌/目标时用）
func take_skill_reply_full() -> Dictionary:
	return engine.take_reply()


## 广播技能发动
func notice_skill(skill_id: int, dst_ids: Array = []) -> void:
	engine.broadcast(GConst.Msg.Skill, {"skill_id": skill_id, "src_id": player.id, "dst_ids": dst_ids})


# ============================================================
# 角色工厂
# ============================================================
static func create(role_id: int, p: BattlePlayer, e: BattleEngine) -> BattleRole:
	var script_path: String = _script_of(role_id)
	if script_path == "" or not ResourceLoader.exists(script_path):
		return null
	var scr: GDScript = load(script_path)
	var r: BattleRole = scr.new()
	r.setup(p, e)
	return r


static func _script_of(role_id: int) -> String:
	# 只登记已移植的角色；未移植的返回空（按通用规则结算）
	match role_id:
		1: return "res://scripts/battle/roles/role_jiansheng.gd"
		2: return "res://scripts/battle/roles/role_kuangzhan.gd"
		3: return "res://scripts/battle/roles/role_gongnv.gd"
		4: return "res://scripts/battle/roles/role_fengyin.gd"
		5: return "res://scripts/battle/roles/role_ansha.gd"
		6: return "res://scripts/battle/roles/role_shengnv.gd"
		7: return "res://scripts/battle/roles/role_tianshi.gd"
		8: return "res://scripts/battle/roles/role_modao.gd"
		9: return "res://scripts/battle/roles/role_mojian.gd"
		10: return "res://scripts/battle/roles/role_shengqiang.gd"
		11: return "res://scripts/battle/roles/role_yuansu.gd"
		12: return "res://scripts/battle/roles/role_maoxian.gd"
		13: return "res://scripts/battle/roles/role_siling.gd"
		14: return "res://scripts/battle/roles/role_zhongcai.gd"
		15: return "res://scripts/battle/roles/role_shenguan.gd"
		16: return "res://scripts/battle/roles/role_qidao.gd"
		17: return "res://scripts/battle/roles/role_xianzhe.gd"
		18: return "res://scripts/battle/roles/role_lingfu.gd"
		19: return "res://scripts/battle/roles/role_jiandi.gd"
		20: return "res://scripts/battle/roles/role_gedou.gd"
		21: return "res://scripts/battle/roles/role_yongzhe.gd"
		22: return "res://scripts/battle/roles/role_linghun.gd"
		23: return "res://scripts/battle/roles/role_wunu.gd"
		24: return "res://scripts/battle/roles/role_diewu.gd"
		25: return "res://scripts/battle/roles/role_nvwushen.gd"
		26: return "res://scripts/battle/roles/role_mogong.gd"
		27: return "res://scripts/battle/roles/role_yinglingrenxing.gd"
		28: return "res://scripts/battle/roles/role_honglian.gd"
		29: return "res://scripts/battle/roles/role_moqiang.gd"
		30: return "res://scripts/battle/roles/role_monv.gd"
		31: return "res://scripts/battle/roles/role_shiren.gd"
		32: return "res://scripts/battle/roles/role_jinglingsheshou.gd"
		33: return "res://scripts/battle/roles/role_yinyang.gd"
		34: return "res://scripts/battle/roles/role_xuejian.gd"
		35: return "res://scripts/battle/roles/role_yuenv.gd"
		36: return "res://scripts/battle/roles/role_shouling.gd"
		37: return "res://scripts/battle/roles/role_shenggong.gd"
		108: return "res://scripts/battle/roles/role_spmodao.gd"
	return ""
