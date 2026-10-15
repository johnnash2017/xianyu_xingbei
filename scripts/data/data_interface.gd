extends Node
## 数据接口（autoload 名：Data）
## 对照客户端 data/DataInterface.cpp：卡牌库、角色表、技能文本、玩家列表、队伍

# ---------------- 卡牌与角色数据 ----------------
var card_db: Array[GCard] = []
var _card_by_id: Dictionary = {}         # 卡号 -> GCard（get_card 查这张；虚拟牌 1000+ 不能按数组下标取）
var role_list: Dictionary = {}          # roleID -> 显示名（「[剑圣]」这种，取自角色表的显示名列）
## 可出场的角色号（角色表「启用」列 = 1 的）：随机分配、三选一/六选一/任选的候选池都取自这里
var role_pool: Array[int] = []
var role_skill_db: Dictionary = {}      # roleID -> 技能文本
var role_property_db: Dictionary = {}   # roleID -> 派系（技 / 血 / 幻 / 咏 / 圣）
var role_tokens_db: Dictionary = {}     # roleID -> { 槽位: {name, max} }（取自角色表的指示物列）
## 角色号 -> 角色表那一行（懒建一次；角色表 id 是名字型，协议/代码用的角色号在「角色索引」列）
var _角色索引到行: Dictionary = {}

# ---------------- 对局视图状态 ----------------
var player_list: Array[GPlayer] = []
var hand_cards: Array[GCard] = []
var cover_cards: Array[GCard] = []
var red: GTeam
var blue: GTeam
var my_team: GTeam
var other_team: GTeam
var game_info: Dictionary = {}
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
## 卡牌：数据来自 DataTables.gd 的「卡表」（含 5 张无卡面的虚拟牌；资源名交给 AssetIndex 解析到 assets/textures/card/）
func _load_card_db() -> void:
	card_db.clear()
	_card_by_id.clear()
	for key: String in 数据表格.卡表.keys():
		var row: Array = 数据表格.卡表[key]
		if row.size() < 7:
			continue
		# 列下标由 GCard.from_row 按「卡表」的列名自查，这里只把字典键里的 id 传过去
		var 卡: GCard = GCard.from_row(int(key.get_slice("#", 1)), row)
		card_db.append(卡)
		_card_by_id[卡.id] = 卡


func _load_role_list() -> void:
	role_list.clear()
	role_pool.clear()
	var 列索引: Dictionary = 数据表格.表元数据["角色表"]["列索引"]
	var 显示列: int = int(列索引["显示名"])
	var 名列: int = int(列索引["角色名"])
	var 索引列: int = int(列索引["角色索引"])
	var 启用列: int = int(列索引["启用"])
	for key: String in 数据表格.角色表.keys():
		var row: Array = 数据表格.角色表[key]
		var 名: String = str(row[显示列]).strip_edges()
		if 名 == "":
			名 = str(row[名列]).strip_edges()
		var 角色号: int = int(row[索引列])
		role_list[角色号] = 名
		# 「启用」列 = 1 的才进候选池；停用一个角色就把它那格改成 0
		if int(row[启用列]) > 0:
			role_pool.append(角色号)
	role_pool.sort()


## 技能表「派系」列的取值 → 界面上的分段标题；数组顺序即显示顺序
const 技能分段顺序: Array[String] = ["普通", "独有技", "专属技", "必杀技"]
const 技能分段标题: Dictionary = {"普通": "普通技", "独有技": "独有技", "专属技": "专属技", "必杀技": "必杀技"}


## 角色技能文本：按「角色表」的「技能」引用逐条拼装（角色ID -> 技能文本）
## 一级标题取技能表的「派系」列；每条技能一行，技能表里的「说明」已经不带头，
## 这里把「类型」「技能名」拼回去，成「【响应】疾风技：说明」的样子
func _load_role_skill_db() -> void:
	role_skill_db.clear()
	var 列索引: Dictionary = 数据表格.表元数据["技能表"]["列索引"]
	var 分段列: int = int(列索引["派系"])
	var 类型列: int = int(列索引["类型"])
	var 名字列: int = int(列索引["技能名"])
	var 说明列: int = int(列索引["说明"])
	var 角色索引列: int = int(数据表格.表元数据["角色表"]["列索引"]["角色索引"])
	for key: String in 数据表格.角色表.keys():
		var 角色行: Array = 数据表格.角色表[key]
		var 角色号: int = int(角色行[角色索引列])
		var 分组: Dictionary = {}
		for 技能号: int in role_skills(角色号):
			var row: Array = GConst.技能行(技能号)
			if row.is_empty():
				continue
			var 说明: String = str(row[说明列]).strip_edges()
			if 说明 == "":
				continue
			var 条目: String = "【%s】%s：%s" % [
				str(row[类型列]).strip_edges(), str(row[名字列]).strip_edges(), 说明]
			var 分段: String = str(row[分段列])
			if not 分组.has(分段):
				分组[分段] = []
			var 本段行: Array = 分组[分段]
			if not 本段行.has(条目):
				本段行.append(条目)
		role_skill_db[角色号] = _拼技能文本(分组)


## 把某角色的分段字典拼成一段文本：一级标题（派系）一行，该段每条技能各占一行。
## 行与行之间的间距不在这里插空行，改由 上色 配合 RichTextLabel 的 paragraph_separation 统一控制
func _拼技能文本(段字典: Dictionary) -> String:
	var 行列表: Array[String] = []
	for 分段: String in 技能分段顺序:
		if not 段字典.has(分段):
			continue
		行列表.append(str(技能分段标题.get(分段, 分段)))
		var 本段行: Array = 段字典[分段]
		for 条目: String in 本段行:
			# 换行标记只有一种：导表器把单元格内换行转义出来的字面 \n；
			# 只有第一行带「【类型】技能名：」前缀；正文（含说明的续行）整体缩进两格，与一级标题拉开
			for 行: String in 条目.replace("\\n", "\n").split("\n"):
				var 文本: String = 行.strip_edges()
				if 文本 != "":
					行列表.append("　　" + 文本)
	return "\n".join(行列表)


## 角色派系（技 / 血 / 幻 / 咏 / 圣）：取自「角色表」的派系列（同参考工程 RoleBase.RoleProperty）
func _load_role_property() -> void:
	role_property_db.clear()
	# 列下标按列名从表元数据取，改表结构时这里不用跟着改数字
	var 派系列: int = int(数据表格.表元数据["角色表"]["列索引"]["派系"])
	var 索引列: int = int(数据表格.表元数据["角色表"]["列索引"]["角色索引"])
	for key: String in 数据表格.角色表.keys():
		var row: Array = 数据表格.角色表[key]
		role_property_db[int(row[索引列])] = str(row[派系列]).strip_edges()


# ============================================================
# 查询
# ============================================================
func role_name(rid: int) -> String:
	return str(role_list.get(rid, "角色"))


## 角色表里某角色那一行（「除 id 以外的各列」）；没有这个角色就返回空数组
## 角色号取自「角色索引」列（角色表 id 是名字型，建一次索引后按号查）
func _角色行(rid: int) -> Array:
	if _角色索引到行.is_empty():
		var 索引列: int = int(数据表格.表元数据["角色表"]["列索引"]["角色索引"])
		for key: String in 数据表格.角色表.keys():
			var row: Array = 数据表格.角色表[key]
			_角色索引到行[int(row[索引列])] = row
	return _角色索引到行.get(rid, [])


## 该角色引用的技能号（角色表的「技能」列写技能 id，类型是 list(技能表)）
## 导表器把 list 的每一项都包成一层字段数组，所以这里取每项的第 0 格
func role_skills(rid: int) -> Array[int]:
	var 结果: Array[int] = []
	var row: Array = _角色行(rid)
	if row.is_empty():
		return 结果
	var 列索引: Dictionary = 数据表格.表元数据["角色表"]["列索引"]
	for 项: Array in row[int(列索引["技能"])]:
		if 项.is_empty():
			continue
		var 技能id: String = str(项[0]).strip_edges()
		if 技能id != "":
			结果.append(GConst.技能号(技能id))
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


## 该角色的形态名（角色表「横置形态」列，类型 list(string)；一个角色未来可能有多形态，
## 目前 tap 只有真假两态，取第一个）。导表器把 list 的每一项都包成一层字段数组，故取每项第 0 格
func role_forms(rid: int) -> Array[String]:
	var 结果: Array[String] = []
	var row: Array = _角色行(rid)
	if row.is_empty():
		return 结果
	var 列索引: Dictionary = 数据表格.表元数据["角色表"]["列索引"]
	for 项: Array in row[int(列索引["横置形态"])]:
		if 项.is_empty():
			continue
		var 名: String = str(项[0]).strip_edges()
		if 名 != "":
			结果.append(名)
	return 结果


## 角色派系（技 / 血 / 幻 / 咏 / 圣）；角色表里没有的角色返回空串（界面据此不显示派系图标）
func role_property(rid: int) -> String:
	return role_property_db.get(rid, "")


## 状态标签底板色（角色表「状态底色」列，写 #RRGGBB / #RRGGBBAA）。
## 该列要在设计表里加好并重新生成数据表后才有；列不存在或没填时用默认深色
const 状态底色默认: Color = Color(0.13, 0.16, 0.24, 0.95)

func role_status_bg(rid: int) -> Color:
	var 列索引: Dictionary = 数据表格.表元数据["角色表"]["列索引"]
	var 列: int = int(列索引.get("状态底色", -1))
	var row: Array = _角色行(rid)
	if 列 < 0 or row.is_empty() or 列 >= row.size():
		return 状态底色默认
	var 文本: String = str(row[列]).strip_edges()
	return Color.from_string(文本, 状态底色默认) if 文本 != "" else 状态底色默认


## 角色专属指示物：「角色表」的「指示物」列，写法 `槽位:名称:上限`，多个用 `;` 隔开
## 例：「0:重生:4」「0:剑气:5;2:剑魂:3」（原客户端 data/Player.cpp 的 addToken）
func _load_role_tokens() -> void:
	role_tokens_db.clear()
	var 列索引: Dictionary = 数据表格.表元数据["角色表"]["列索引"]
	var 指示物列: int = int(列索引["指示物"])
	var 索引列: int = int(列索引["角色索引"])
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
			role_tokens_db[int(row[索引列])] = 槽字典


func role_token_def(role_id: int, slot: int) -> Dictionary:
	var m: Dictionary = role_tokens_db.get(role_id, {})
	return m.get(slot, {})


## 角色技能说明文本。里面的词缀关键字（如「【治疗】」）已换成图标，见 GConst.词缀文本
func role_skill_info(rid: int) -> String:
	return GConst.词缀文本(str(role_skill_db.get(rid, "")))


## 按卡号取牌（虚拟牌号是 1000+，与数组下标不一致，所以走 id 索引）
func get_card(cid: int) -> GCard:
	if _card_by_id.has(cid):
		return _card_by_id[cid]
	return null


## 按「卡名」取一张牌的代表牌号（同名有多份时取卡表里第一份；找不到返回 -1）。
## 用于「把手中的某张牌当作另一张牌用」的技能（如【魔弹融合】把地/火牌当【魔弹】）。
func card_id_by_name_enum(名字: int) -> int:
	for 卡: GCard in card_db:
		if 卡.card_name_enum() == 名字:
			return 卡.id
	return -1


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
	p.ping = int(pi.get("ping", GConst.PING_未测))
	if pi.has("max_hand"):
		p.hand_cards_max = int(pi["max_hand"])
	# 治疗上限：角色被动改过（如神官【圣使守护】+4），按服务端下发的值显示
	if pi.has("max_heal"):
		p.set_cross_max(int(pi["max_heal"]))
	# 能量上限：角色被动改过（如贤者 +1），判「星石已满 / 还有空位」用它
	if pi.has("max_energy"):
		p.set_energy_max(int(pi["max_energy"]))
	# 基础效果
	p.clean_basic_status()
	for cid: Variant in pi.get("basic_cards", []):
		var card: GCard = get_card(int(cid))
		if card != null:
			p.add_basic_status(0, card)
	# 独有效果
	for idx: int in range(GConst.EXCLUSIVE_NUM):
		p.specials[idx] = false
		p.specials_from[idx] = -1
	var 专属: Array = pi.get("ex_cards", [])
	for ex: Variant in 专属:
		p.set_special(int(ex), true)
	# 独有效果的放牌者：ex_from 与 ex_cards 一一对应（【挑衅】靠它知道被挑衅的人只能攻击谁）
	var 专属来源: Array = pi.get("ex_from", [])
	for i: int in range(mini(专属.size(), 专属来源.size())):
		p.set_special_from(int(专属[i]), int(专属来源[i]))
	# 指示物：槽0→third_token、槽1→yellow_token、槽2→covered_count；名称/上限取角色专属定义。
	# 槽 2 是「盖牌」（茧 / 剑魂 / 充能 / 祝福 / 暗月 …）：服务端只把它写进盖牌区（cover_cards），
	# 从不填 tokens[2]，所以这里必须取 covered_count —— 之前取 blue_token 恒为 0，盖牌数永远显示 0
	p.tokens[0] = null
	p.tokens[1] = null
	p.tokens[2] = null
	for slot: int in range(3):
		var 值: int = 0
		match slot:
			0: 值 = int(pi.get("third_token", 0))
			1: 值 = int(pi.get("yellow_token", 0))
			2: 值 = int(pi.get("covered_count", 0))
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
