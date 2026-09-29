extends Node
## 数据接口（autoload 名：Data）
## 对照客户端 data/DataInterface.cpp：卡牌库、角色表、技能文本、玩家列表、队伍

# ---------------- 卡牌与角色数据 ----------------
var card_db: Array[GCard] = []
var role_list: Dictionary = {}          # roleID -> 角色名
var role_skill_db: Dictionary = {}      # roleID -> 技能文本
var role_property_db: Dictionary = {}   # roleID -> 派系（技 / 血 / 幻 / 咏 / 圣）
var button_db: Dictionary = {}          # 技能名 -> 按钮说明
## 角色表（角色 id / 角色名 / 简称 / 派系…），第 13 列是派系
const HERO_INFO_PATH: String = "res://assets/data/heroInfo.txt"

# ---------------- 对局视图状态 ----------------
var player_list: Array[GPlayer] = []
var hand_cards: Array[GCard] = []
var cover_cards: Array[GCard] = []
var red: GTeam
var blue: GTeam
var my_team: GTeam
var other_team: GTeam
var game_info: Dictionary = {}
var first_player_id: int = 0
var myself: GPlayer = null
var id: int = 0
var player_max: int = 6
var nick_name: String = ""
var identity: int = 0                   # ACCOUNT_STATUS（去登录后固定为普通/游客）


func _ready() -> void:
	red = GTeam.new(true)
	blue = GTeam.new(false)
	_load_card_db()
	_load_role_list()
	_load_role_skill_db()
	_load_role_property()
	_load_button_db()


# ============================================================
# 数据加载
# ============================================================
func _load_card_db() -> void:
	card_db.clear()
	for line: String in _read_lines("res://数据/cardDB.txt"):
		var cells: PackedStringArray = line.split("\t")
		if cells.size() < 8 or cells[0] == "":
			continue
		card_db.append(GCard.from_row(cells))


func _load_role_list() -> void:
	role_list = {
		0: "角色", 1: "[剑圣]", 2: "[狂战士]", 3: "[弓之女神]", 4: "[封印师]",
		5: "[暗杀者]", 6: "[圣女]", 7: "[天使]", 8: "[魔导师]", 9: "[魔剑]",
		10: "[圣枪]", 11: "[元素师]", 12: "[冒险家]", 13: "[死灵法师]", 14: "[仲裁者]",
		15: "[神官]", 16: "[祈祷师]", 17: "[贤者]", 18: "[灵符师]", 19: "[剑帝]",
		20: "[格斗家]", 21: "[勇者]", 22: "[灵魂术士]", 23: "[巫女]", 24: "[蝶舞者]",
		25: "[女武神]", 26: "[魔弓]", 27: "[英灵人形]", 28: "[红莲骑士]", 29: "[魔枪]",
		30: "[苍炎魔女]", 31: "[吟游诗人]", 32: "[精灵射手]", 33: "[阴阳师]", 34: "[血色剑灵]",
		35: "[月之女神]", 36: "[兽灵武士]", 37: "[圣弓]", 108: "[sp魔导师]",
	}


func _load_role_skill_db() -> void:
	role_skill_db.clear()
	for line: String in _read_lines("res://数据/skillDB.txt"):
		var cells: PackedStringArray = line.split("\t")
		if cells.size() < 2 or cells[0] == "":
			continue
		role_skill_db[int(cells[0])] = cells[1].replace("#", "\n")


## 角色派系（技 / 血 / 幻 / 咏 / 圣）：取自角色表第 13 列（同参考工程 RoleBase.RoleProperty）
func _load_role_property() -> void:
	role_property_db.clear()
	for line: String in _read_lines(HERO_INFO_PATH):
		var cells: PackedStringArray = line.split("\t")
		if cells.size() < 13 or cells[0] == "":
			continue
		role_property_db[int(cells[0])] = cells[12].strip_edges()


func _load_button_db() -> void:
	button_db.clear()
	for line: String in _read_lines("res://数据/buttonDB.txt"):
		var cells: PackedStringArray = line.split("\t")
		if cells.size() < 2 or cells[0] == "":
			continue
		button_db[cells[0]] = cells[1].replace("#", "\n")


func _read_lines(path: String) -> PackedStringArray:
	if not FileAccess.file_exists(path):
		push_error("Data: 找不到数据文件 %s" % path)
		return PackedStringArray()
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	var lines: PackedStringArray = []
	while not f.eof_reached():
		var line: String = f.get_line()
		if line.strip_edges() == "":
			continue
		lines.append(line)
	f.close()
	return lines


# ============================================================
# 查询
# ============================================================
func role_name(rid: int) -> String:
	return role_list.get(rid, "角色")


## 角色派系（技 / 血 / 幻 / 咏 / 圣）；角色表里没有的角色返回空串（界面据此不显示派系图标）
func role_property(rid: int) -> String:
	return role_property_db.get(rid, "")


## 角色专属指示物定义（槽位 → {name, max}），逐行对照原客户端 data/Player.cpp 的 addToken
const ROLE_TOKENS: Dictionary = {
	11: {0: {"name": "元素", "max": 3}},
	14: {0: {"name": "审判", "max": 4}},
	16: {0: {"name": "符文", "max": 3}},
	18: {2: {"name": "妖力", "max": 2}},
	19: {0: {"name": "剑气", "max": 5}, 2: {"name": "剑魂", "max": 3}},
	20: {0: {"name": "斗气", "max": 6}},
	21: {0: {"name": "怒气", "max": 4}, 1: {"name": "知性", "max": 4}},
	22: {0: {"name": "黄魂", "max": 6}, 1: {"name": "蓝魂", "max": 6}},
	24: {0: {"name": "蛹", "max": 99}, 2: {"name": "茧", "max": 8}},
	26: {2: {"name": "充能", "max": 8}},
	27: {0: {"name": "战纹", "max": 3}, 1: {"name": "魔纹", "max": 3}},
	28: {0: {"name": "血印", "max": 2}},
	30: {0: {"name": "重生", "max": 4}},
	31: {0: {"name": "灵感", "max": 4}},
	32: {2: {"name": "祝福", "max": 3}},
	33: {0: {"name": "鬼火", "max": 3}},
	34: {0: {"name": "鲜血", "max": 3}},
	35: {0: {"name": "新月", "max": 2}, 1: {"name": "石化", "max": 3}, 2: {"name": "暗月", "max": 99}},
	36: {0: {"name": "残心", "max": 4}, 1: {"name": "兽魂", "max": 2}},
	37: {0: {"name": "信仰", "max": 10}},
}


func role_token_def(role_id: int, slot: int) -> Dictionary:
	var m: Dictionary = ROLE_TOKENS.get(role_id, {})
	return m.get(slot, {})


func role_skill_info(rid: int) -> String:
	return role_skill_db.get(rid, "")


func button_info(skill: String) -> String:
	return button_db.get(skill, skill)


func get_card(cid: int) -> GCard:
	if cid >= 0 and cid < card_db.size():
		return card_db[cid]
	return null


func get_player_by_id(pid: int) -> GPlayer:
	for p: GPlayer in player_list:
		if p.id == pid:
			return p
	return null


func get_red_team() -> GTeam:
	return red


func get_blue_team() -> GTeam:
	return blue


func team_of(color: int) -> GTeam:
	return red if color == GConst.RED else blue


# ============================================================
# 房间/玩家列表构建
# ============================================================
## 用服务端下发的 GameInfo 重建玩家列表（以自己为视角，座次从我方开始）
func build_player_list(info: Dictionary) -> void:
	game_info = info
	var infos: Array = info.get("player_infos", [])
	player_max = infos.size()
	var my_viewpoint: int = 0 if id == GConst.GUEST else id
	# 找到自己的座位下标
	var my_pos: int = 0
	for i: int in range(infos.size()):
		if int(infos[i].get("id", -1)) == my_viewpoint:
			my_pos = i
			break
	player_list.clear()
	# 从我方座位开始顺时针排
	for k: int in range(infos.size()):
		var idx: int = (my_pos + k) % infos.size()
		var pi: Dictionary = infos[idx]
		var pid: int = int(pi.get("id", 0))
		var p: GPlayer = GPlayer.new(pid, int(pi.get("team", -1)), str(pi.get("nickname", "")))
		_apply_player_info(p, pi)
		player_list.append(p)
	first_player_id = int(infos[0].get("id", 0)) if infos.size() > 0 else 0
	myself = player_list[0] if player_list.size() > 0 else null
	_sync_my_cards(infos, my_pos)


## 同步「我的手牌/盖牌」到本地卡牌对象列表（只有本人那一条含 hands/covereds）
func _sync_my_cards(infos: Array, my_pos: int) -> void:
	hand_cards.clear()
	cover_cards.clear()
	if my_pos < 0 or my_pos >= infos.size():
		return
	var me: Dictionary = infos[my_pos]
	for cid: Variant in me.get("hands", []):
		var c: GCard = get_card(int(cid))
		if c != null:
			hand_cards.append(c)
	for cid: Variant in me.get("covereds", []):
		var c2: GCard = get_card(int(cid))
		if c2 != null:
			cover_cards.append(c2)


## 把单条 SinglePlayerInfo 应用到玩家视图
func _apply_player_info(p: GPlayer, pi: Dictionary) -> void:
	p.set_team(int(pi.get("team", -1)))
	p.set_nickname(str(pi.get("nickname", "")))
	p.set_role(int(pi.get("role_id", 0)))
	p.id = int(pi.get("id", p.id))
	p.hand_cards_num = int(pi.get("hand_count", 0))
	p.cross_num = int(pi.get("heal_count", 0))
	p.gem = int(pi.get("gem", 0))
	p.crystal = int(pi.get("crystal", 0))
	p.tap = bool(pi.get("is_knelt", false))
	p.ready = bool(pi.get("ready", false))
	p.leader = int(pi.get("leader", 0)) == 1
	p.online = bool(pi.get("online", true))
	if pi.has("max_hand"):
		p.hand_cards_max = int(pi["max_hand"])
	# 基础效果
	p.clean_basic_status()
	for cid: Variant in pi.get("basic_cards", []):
		var card: GCard = get_card(int(cid))
		if card != null:
			p.add_basic_status(0, card)
	# 独有效果
	for idx: int in range(GConst.EXCLUSIVE_NUM):
		p.specials[idx] = false
	for ex: Variant in pi.get("ex_cards", []):
		p.set_special(int(ex), true)
	# 指示物：槽0→third_token、槽1→yellow_token、槽2→blue_token；名称/上限取角色专属定义
	p.tokens[0] = null
	p.tokens[1] = null
	p.tokens[2] = null
	for slot: int in range(3):
		var 值: int = 0
		match slot:
			0: 值 = int(pi.get("third_token", 0))
			1: 值 = int(pi.get("yellow_token", 0))
			2: 值 = int(pi.get("blue_token", 0))
		if 值 <= 0:
			continue
		var 定义: Dictionary = role_token_def(p.role_id, slot)
		p.tokens[slot] = GPlayer.Token.new(str(定义.get("name", "指示物")), int(定义.get("max", 99)), 值)


## 队伍数值与牌堆数量
func apply_team_info(info: Dictionary) -> void:
	red.set_morale(int(info.get("red_morale", 0)))
	blue.set_morale(int(info.get("blue_morale", 0)))
	red.set_gem(int(info.get("red_gem", 0)))
	blue.set_gem(int(info.get("blue_gem", 0)))
	red.set_crystal(int(info.get("red_crystal", 0)))
	blue.set_crystal(int(info.get("blue_crystal", 0)))
	red.set_grail(int(info.get("red_grail", 0)))
	blue.set_grail(int(info.get("blue_grail", 0)))


## 设置士气上限（开局时）
func init_team(morale_max: int) -> void:
	red.set_morale_max(morale_max)
	blue.set_morale_max(morale_max)
	if myself != null and myself.color == GConst.RED:
		my_team = red
		other_team = blue
	else:
		my_team = blue
		other_team = red


func clean_room() -> void:
	red.set_crystal(0)
	red.set_gem(0)
	red.set_grail(0)
	red.set_morale(0)
	blue.set_crystal(0)
	blue.set_gem(0)
	blue.set_grail(0)
	blue.set_morale(0)
	hand_cards.clear()
	cover_cards.clear()
