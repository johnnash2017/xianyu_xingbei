extends Node
## 数据接口（autoload 名：Data）
## 对照客户端 data/DataInterface.cpp：卡牌库、角色表、技能文本、玩家列表、队伍

# ---------------- 卡牌与角色数据 ----------------
var card_db: Array[GCard] = []
var role_list: Dictionary = {}          # roleID -> 显示名（「[剑圣]」这种，取自角色表的显示名列）
var role_skill_db: Dictionary = {}      # roleID -> 技能文本
var role_property_db: Dictionary = {}   # roleID -> 派系（技 / 血 / 幻 / 咏 / 圣）
var role_tokens_db: Dictionary = {}     # roleID -> { 槽位: {name, max} }（取自角色表的指示物列）

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
	_load_role_tokens()


# ============================================================
# 数据加载（全部取自 Table/TableScripts/DataTables.gd，由 设计表.xlsx 生成）
# ============================================================
## 卡牌：数据来自 DataTables.gd 的「卡面表」（资源名交给 AssetIndex 解析到 assets/textures/card/）
func _load_card_db() -> void:
	card_db.clear()
	for key: String in 数据表格.卡面表.keys():
		var row: Array = 数据表格.卡面表[key]
		if row.size() < 7:
			continue
		# GCard.from_row 要的是「id + 其余各列」，这里把字典键里的 id 补回去
		var cells: PackedStringArray = PackedStringArray([key.get_slice("#", 1)])
		for v: Variant in row:
			cells.append(str(v))
		card_db.append(GCard.from_row(cells))


func _load_role_list() -> void:
	role_list.clear()
	var 列索引: Dictionary = 数据表格.表元数据["角色表"]["列索引"]
	var 显示列: int = int(列索引["显示名"])
	var 名列: int = int(列索引["角色名"])
	for key: String in 数据表格.角色表.keys():
		var row: Array = 数据表格.角色表[key]
		var 名: String = str(row[显示列]).strip_edges()
		if 名 == "":
			名 = str(row[名列]).strip_edges()
		role_list[int(key.get_slice("#", 1))] = 名


## 技能表「派系」列的取值 → 界面上的分段标题；数组顺序即显示顺序
const 技能分段顺序: Array[String] = ["普通", "独有技", "专属技", "必杀技"]
const 技能分段标题: Dictionary = {"普通": "普通技", "独有技": "独有技", "专属技": "专属技", "必杀技": "必杀技"}


## 角色技能文本：按「角色表」的「技能」引用逐条拼装（角色ID -> 技能文本）
## 分段标题取技能表的「派系」列；同一说明只留一条（历史上一个技能会占多个槽）
func _load_role_skill_db() -> void:
	role_skill_db.clear()
	var 列索引: Dictionary = 数据表格.表元数据["技能表"]["列索引"]
	var 分段列: int = int(列索引["派系"])
	var 说明列: int = int(列索引["说明"])
	for key: String in 数据表格.角色表.keys():
		var 角色号: int = int(key.get_slice("#", 1))
		var 分组: Dictionary = {}
		for 技能号: int in role_skills(角色号):
			var row: Array = 数据表格.技能表.get("技能表#%d" % 技能号, [])
			if row.is_empty():
				continue
			var 说明: String = str(row[说明列]).strip_edges()
			if 说明 == "":
				continue
			var 分段: String = str(row[分段列])
			if not 分组.has(分段):
				分组[分段] = []
			var 本段行: Array = 分组[分段]
			if not 本段行.has(说明):
				本段行.append(说明)
		role_skill_db[角色号] = _拼技能文本(分组)


## 把某角色的分段字典拼成一段文本：分段标题一行，该段每条说明各占一行
func _拼技能文本(段字典: Dictionary) -> String:
	var 行列表: Array[String] = []
	for 分段: String in 技能分段顺序:
		if not 段字典.has(分段):
			continue
		行列表.append(str(技能分段标题.get(分段, 分段)))
		var 本段行: Array = 段字典[分段]
		for 说明: String in 本段行:
			# 说明里的 # 是换行标记（与卡表/按钮说明同一约定）
			for 行: String in 说明.split("#"):
				var 文本: String = 行.strip_edges()
				if 文本 != "":
					行列表.append(文本)
	return "\n".join(行列表)


## 角色派系（技 / 血 / 幻 / 咏 / 圣）：取自「角色表」的派系列（同参考工程 RoleBase.RoleProperty）
func _load_role_property() -> void:
	role_property_db.clear()
	# 列下标按列名从表元数据取，改表结构时这里不用跟着改数字
	var 派系列: int = int(数据表格.表元数据["角色表"]["列索引"]["派系"])
	for key: String in 数据表格.角色表.keys():
		var row: Array = 数据表格.角色表[key]
		role_property_db[int(key.get_slice("#", 1))] = str(row[派系列]).strip_edges()


# ============================================================
# 查询
# ============================================================
func role_name(rid: int) -> String:
	return role_list.get(rid, "角色")


## 角色表里某角色那一行（「除 id 以外的各列」）；没有这个角色就返回空数组
func _角色行(rid: int) -> Array:
	return 数据表格.角色表.get("角色表#%d" % rid, [])


## 该角色引用的技能号（角色表的「技能」列，形如 "技能表#101,技能表#102"）
func role_skills(rid: int) -> Array[int]:
	var 结果: Array[int] = []
	var row: Array = _角色行(rid)
	if row.is_empty():
		return 结果
	var 列索引: Dictionary = 数据表格.表元数据["角色表"]["列索引"]
	for 引用: String in str(row[int(列索引["技能"])]).split(","):
		var 文本: String = 引用.strip_edges()
		if 文本 != "":
			结果.append(int(文本.get_slice("#", 1)))
	return 结果


## 该角色的战斗实现脚本路径（角色表的「脚本」列）；空串 = 未移植，按通用规则结算
func role_script(rid: int) -> String:
	var row: Array = _角色行(rid)
	if row.is_empty():
		return ""
	var 列索引: Dictionary = 数据表格.表元数据["角色表"]["列索引"]
	return str(row[int(列索引["脚本"])]).strip_edges()


## 该角色的形态图资源名（角色表的「形态图」列）；空串 = 没有形态图
func role_tap(rid: int) -> String:
	var row: Array = _角色行(rid)
	if row.is_empty():
		return ""
	var 列索引: Dictionary = 数据表格.表元数据["角色表"]["列索引"]
	return str(row[int(列索引["形态图"])]).strip_edges()


## 角色派系（技 / 血 / 幻 / 咏 / 圣）；角色表里没有的角色返回空串（界面据此不显示派系图标）
func role_property(rid: int) -> String:
	return role_property_db.get(rid, "")


## 角色专属指示物：「角色表」的「指示物」列，写法 `槽位:名称:上限`，多个用 `;` 隔开
## 例：「0:重生:4」「0:剑气:5;2:剑魂:3」（原客户端 data/Player.cpp 的 addToken）
func _load_role_tokens() -> void:
	role_tokens_db.clear()
	var 列索引: Dictionary = 数据表格.表元数据["角色表"]["列索引"]
	var 指示物列: int = int(列索引["指示物"])
	for key: String in 数据表格.角色表.keys():
		var row: Array = 数据表格.角色表[key]
		var 配置: String = str(row[指示物列]).strip_edges()
		if 配置 == "":
			continue
		var 槽字典: Dictionary = {}
		for 段: String in 配置.split(";"):
			var 项: PackedStringArray = 段.strip_edges().split(":")
			if 项.size() < 3:
				continue
			槽字典[int(项[0])] = {"name": 项[1], "max": int(项[2])}
		if not 槽字典.is_empty():
			role_tokens_db[int(key.get_slice("#", 1))] = 槽字典


func role_token_def(role_id: int, slot: int) -> Dictionary:
	var m: Dictionary = role_tokens_db.get(role_id, {})
	return m.get(slot, {})


func role_skill_info(rid: int) -> String:
	return role_skill_db.get(rid, "")


## 技能按钮说明：技能号 → 文本（技能表的「按钮说明」列就是正文）
func button_info(skill_id: int) -> String:
	var 技能行: Array = 数据表格.技能表.get("技能表#%d" % skill_id, [])
	if 技能行.is_empty():
		return ""
	var 技能列: Dictionary = 数据表格.表元数据["技能表"]["列索引"]
	return str(技能行[int(技能列["按钮说明"])]).replace("#", "\n")


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
