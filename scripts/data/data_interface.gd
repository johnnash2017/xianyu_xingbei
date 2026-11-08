extends Node
## 数据接口（autoload 名：Data）
## 对照客户端 data/DataInterface.cpp：卡牌库、角色表、技能文本、玩家列表、队伍

# ---------------- 卡牌与角色数据 ----------------
var card_db: Array[GCard] = []
## 运行时卡牌实例：实例号 -> 独立 GCard 副本（当前系别 / 归属者写在副本上）。
## 牌面表里的 GCard 只提供静态定义；普通单系别牌不强制建副本，多系别/特殊牌按需建。
var 实例卡: Dictionary = {}
var _card_by_id: Dictionary = {}         # 卡号 -> GCard（get_card 查这张；虚拟牌 1000+ 不能按数组下标取）
var role_list: Dictionary = {}          # roleID -> 显示名（「[剑圣]」这种，取自角色表的显示名列）
## 可出场的角色号（角色表「启用」列 = 1 的）：随机分配、三选一/五选一/任选的候选池都取自这里
var role_pool: Array[int] = []
## 角色号 -> 版本（角色表「版本」列的枚举值，如十周年=1、特典=5）
var role_version_db: Dictionary = {}
## 当前角色表里实际有启用角色的版本，按 GConst.ROLE_VERSION_ORDER 排序：
## 每项 {value:int, name:String, count:int}，建房面板据此摆版本复选框
var role_version_options: Array[Dictionary] = []
var role_skill_db: Dictionary = {}      # roleID -> 技能文本
## roleID -> 技能条目（结构化）：每项 {大类, 专属卡牌, 文本}。
## 悬停说明按「专属卡牌」分组画子框时用（见 角色技能提示.悬浮提示块）
var role_skill_entries: Dictionary = {}
var role_personal_name_db: Dictionary = {}  # roleID -> 姓名（角色表「姓名」列，如 猎巫人 → 白狼卡拉马）
var role_fate_pattern_db: Dictionary = {}   # roleID -> 命格（技 / 血 / 幻 / 咏 / 圣）
var role_tokens_db: Dictionary = {}     # roleID -> { 槽位: {name, max} }（取自角色表的指示物列）
## 角色号 -> 角色表那一行（懒建一次；角色表 id 是名字型，协议/代码用的角色号在「角色索引」列）
var _角色索引到行: Dictionary = {}

# ---------------- 对局视图状态 ----------------
var player_list: Array[GPlayer] = []
var hand_cards: Array[GCard] = []
var cover_cards: Array[GCard] = []
## 手牌 / 盖牌各自的**实例号**，与上面两个数组一一对应。
## 服务端下发的 hands / covereds 就是实例号（同一牌面可能有多份副本，身份靠它区分）；
## 界面渲染、选中、节点复用都用这里的值，规则比较一律先折回牌面（GConst.牌号）。
var hand_iids: Array[int] = []
## 本地已经切好、但服务端还没回 CardElement 确认的卡牌系别（实例号 -> CardElement）。
## 作用：切系别后快照可能还在路上（生成于切换前），_sync_my_cards 用这份覆盖，
## 避免客户端先切成水系、又被旧快照打回火系闪一下。服务端确认后由 battle_mobile 清掉。
var 本地待确认元素: Dictionary = {}
var cover_iids: Array[int] = []
var red: GTeam
var blue: GTeam
var my_team: GTeam
var other_team: GTeam
var game_info: Dictionary = {}
## 场卡（F1）：【异端裁决所】/【末日预言】/【绝界】这类摆在场上或某人面前的公共卡。
## 每项 {id, owner, attached, counter, counter_max, state, pile_count}（见 proto_schema 的 FieldCard）
var 场卡表: Array[Dictionary] = []

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
	_load_role_personal_name()
	_load_role_skill_db()
	_load_role_fate_pattern()
	_load_role_tokens()


# ============================================================
# 数据加载（全部取自 Table/TableScripts/DataTables.gd，由 设计表.xlsx 生成）
# ============================================================
## 卡牌：数据来自 DataTables.gd 的「卡表」（含 5 张无卡面的虚拟牌 + 1005/1006 两张真实特殊攻击牌；
## 资源名交给 AssetIndex 解析到 assets/textures/card/）
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
	role_version_db.clear()
	role_version_options.clear()
	var 列索引: Dictionary = 数据表格.表元数据["角色表"]["列索引"]
	var 显示列: int = int(列索引["显示名"])
	var 名列: int = int(列索引["职业名"])
	var 索引列: int = int(列索引["角色索引"])
	var 启用列: int = int(列索引["启用"])
	var 版本列: int = int(列索引.get("版本", -1))
	var 版本计数: Dictionary = {}
	for key: String in 数据表格.角色表.keys():
		var row: Array = 数据表格.角色表[key]
		var 名: String = str(row[显示列]).strip_edges()
		if 名 == "":
			名 = str(row[名列]).strip_edges()
		var 角色号: int = int(row[索引列])
		role_list[角色号] = 名
		var 版本: int = int(row[版本列]) if 版本列 >= 0 and 版本列 < row.size() else 0
		role_version_db[角色号] = 版本
		# 「启用」列 = 1 的才进候选池；停用一个角色就把它那格改成 0
		if int(row[启用列]) > 0:
			role_pool.append(角色号)
			if 版本 > 0:
				版本计数[版本] = int(版本计数.get(版本, 0)) + 1
	role_pool.sort()
	for v: int in GConst.ROLE_VERSION_ORDER:
		if int(版本计数.get(v, 0)) <= 0:
			continue
		role_version_options.append({
			"value": v,
			"name": str(GConst.ROLE_VERSION_NAMES.get(v, "版本%d" % v)),
			"count": int(版本计数[v]),
		})


## 角色姓名：取自「角色表」的「姓名」列，与职业名分开。
## 白板、未移植的特典角色可能没有姓名，返回空串。
func _load_role_personal_name() -> void:
	role_personal_name_db.clear()
	var 列索引: Dictionary = 数据表格.表元数据["角色表"]["列索引"]
	var 姓名列: int = int(列索引.get("姓名", -1))
	if 姓名列 < 0:
		return
	var 索引列: int = int(列索引["角色索引"])
	for key: String in 数据表格.角色表.keys():
		var row: Array = 数据表格.角色表[key]
		if 姓名列 >= row.size():
			continue
		var 姓名: String = str(row[姓名列]).strip_edges()
		if 姓名 != "":
			role_personal_name_db[int(row[索引列])] = 姓名


## 技能表「大类」列的取值 → 界面上的分段标题；数组顺序即显示顺序
const 技能分段顺序: Array[String] = ["普通", "独有技", "专属技", "必杀技"]
const 技能分段标题: Dictionary = {"普通": "普通技", "独有技": "独有技", "专属技": "专属技", "必杀技": "必杀技"}


## 角色技能文本：按「角色表」的「技能」引用逐条拼装（角色ID -> 技能文本）
## 一级标题取技能表的「大类」列；每条技能一行，技能表里的「说明」已经不带头，
## 这里把「类型」「说明说明名」拼回去，成「【响应】疾风技【回合限定】：说明」的样子。
## 角色说明（选角卡、战斗内头像悬停）与技能栏按钮用「说明说明名」列；
## 日志、提示条、单个技能悬停说明等其他地方仍用「技能名」列（见 GConst.skill_name）。
func _load_role_skill_db() -> void:
	role_skill_db.clear()
	role_skill_entries.clear()
	var 列索引: Dictionary = 数据表格.表元数据["技能表"]["列索引"]
	var 分段列: int = int(列索引["大类"])
	# 「专属卡牌」列是后加的：老导表产物里没有这一列时按 -1 兜底（＝所有技能都没有专属卡牌）
	var 专属列: int = int(列索引.get("专属卡牌", -1))
	var 角色索引列: int = int(数据表格.表元数据["角色表"]["列索引"]["角色索引"])
	for key: String in 数据表格.角色表.keys():
		var 角色行: Array = 数据表格.角色表[key]
		var 角色号: int = int(角色行[角色索引列])
		var 分组: Dictionary = {}
		var 条目列表: Array = []
		for 技能号: int in role_skills(角色号):
			var row: Array = GConst.技能行(技能号)
			if row.is_empty():
				continue
			var 说明: String = GConst.skill_desc(技能号)
			if 说明 == "":
				continue
			var 条目: String = "【%s】%s：%s" % [
				GConst.skill_type(技能号), GConst.skill_desc_name(技能号), 说明]
			var 分段: String = str(row[分段列])
			var 专属: String = ""
			if 专属列 >= 0 and 专属列 < row.size():
				专属 = str(row[专属列]).strip_edges()
			条目列表.append({"大类": 分段, "专属卡牌": 专属, "文本": 条目})
			if not 分组.has(分段):
				分组[分段] = []
			var 本段行: Array = 分组[分段]
			if not 本段行.has(条目):
				本段行.append(条目)
		role_skill_db[角色号] = _拼技能文本(分组)
		role_skill_entries[角色号] = 条目列表


## 某角色的技能条目（结构化）：每项 {大类, 专属卡牌, 文本}。
## 悬停说明按「专属卡牌」分组画子框时用（见 角色技能提示.悬浮提示块）
func role_skill_条目(角色号: int) -> Array:
	return role_skill_entries.get(角色号, [])


## 把某角色的分段字典拼成一段文本：一级标题（大类）一行，该段每条技能各占一行。
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


## 角色命格（技 / 血 / 幻 / 咏 / 圣）：取自「角色表」的命格列（参考工程里对应角色命格的字段）
func _load_role_fate_pattern() -> void:
	role_fate_pattern_db.clear()
	# 列下标按列名从表元数据取，改表结构时这里不用跟着改数字
	var 命格列: int = int(数据表格.表元数据["角色表"]["列索引"]["命格"])
	var 索引列: int = int(数据表格.表元数据["角色表"]["列索引"]["角色索引"])
	for key: String in 数据表格.角色表.keys():
		var row: Array = 数据表格.角色表[key]
		role_fate_pattern_db[int(row[索引列])] = str(row[命格列]).strip_edges()


# ============================================================
# 查询
# ============================================================
func role_name(rid: int) -> String:
	return str(role_list.get(rid, "角色"))


## 角色姓名（角色表的「姓名」列）；与显示名/职业名分开，未配置时返回空串
func role_personal_name(rid: int) -> String:
	return str(role_personal_name_db.get(rid, ""))


## 角色势力（角色表的「势力」列，如「战技殿堂」「神圣教廷」）；未配置 / 没有这一列时返回空串。
## 角色悬停说明的名字一行会把它接在职业名 + 姓名后面（见 角色技能提示.悬浮提示）
func role_faction(rid: int) -> String:
	var row: Array = _角色行(rid)
	if row.is_empty():
		return ""
	var 列: int = int(数据表格.表元数据["角色表"]["列索引"].get("势力", -1))
	if 列 < 0 or 列 >= row.size():
		return ""
	return str(row[列]).strip_edges()


## 该角色属于哪个版本（未定义返回 0）
func role_version(rid: int) -> int:
	return int(role_version_db.get(rid, 0))


## 角色星数（使用难度）：角色表「星数」列；白板/未配置返回 0
func role_star(rid: int) -> float:
	var row: Array = _角色行(rid)
	if row.is_empty():
		return 0.0
	var 列: int = int(数据表格.表元数据["角色表"]["列索引"].get("星数", -1))
	if 列 < 0 or 列 >= row.size():
		return 0.0
	return float(row[列])


## 当前所有有启用角色的版本掩码（位：1 << 版本号）
func role_versions_all_mask() -> int:
	var mask: int = 0
	for 项: Dictionary in role_version_options:
		mask |= GConst.role_version_bit(int(项.get("value", 0)))
	return mask


## 按房间版本掩码筛出可出场角色；mask=0 视为「没限制」（兼容旧客户端 / 旧建房请求）
func role_pool_for_versions(mask: int) -> Array[int]:
	var out: Array[int] = []
	if mask == 0:
		out.append_array(role_pool)
		return out
	for rid: int in role_pool:
		var bit: int = GConst.role_version_bit(role_version(rid))
		if bit != 0 and (mask & bit) != 0:
			out.append(rid)
	return out


## 版本掩码 → 房间列表显示用的中文串（没有可用版本时给破折号）
func role_versions_text(mask: int) -> String:
	var 文: String = GConst.role_versions_text(mask)
	return 文 if 文 != "" else "—"


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


## 角色命格（技 / 血 / 幻 / 咏 / 圣）；角色表里没有的角色返回空串（界面据此不显示命格图标）
func role_fate_pattern(rid: int) -> String:
	return role_fate_pattern_db.get(rid, "")


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


## 技能表「大类」：普通 / 独有技 / 专属技 / 必杀技。
## 角色说明按这个分组；剑之子借用 4503/4504 时也据此放回对应分段底部。
func 技能分段(技能号: int) -> String:
	var 行: Array = GConst.技能行(技能号)
	if 行.is_empty():
		return ""
	var 列索引: Dictionary = 数据表格.表元数据["技能表"]["列索引"]
	if not 列索引.has("大类"):
		return ""
	return str(行[int(列索引["大类"])]).strip_edges()


## 按卡号取牌（虚拟牌号是 1000+，与数组下标不一致，所以走 id 索引）。
## 也接受「实例号」：实例号 = 序号 × GConst.实例步长 + 牌号，取牌面时先折回牌号（见 GConst.牌号），
## 这样服务端区域里存的实例号可以直接拿去查牌面，规则侧不用关心是哪一份副本。
## 清空运行时实例（新开一局时调用；牌面数据不动）
func 清空实例卡() -> void:
	实例卡.clear()


## 取/创建一张运行时实例卡：
## iid 必须是唯一实例号（不能是裸牌面 1005，否则所有噬神者会共用）；
## 首次创建时从牌面复制，之后返回同一副本；元素 >0 时同步设置当前系别。
func 取实例卡(iid: int, 元素: int = 0, 归属: int = -1) -> GCard:
	var 已有: GCard = 实例卡.get(iid, null)
	if 已有 != null:
		if 元素 > 0:
			已有.设置当前元素(元素)
		if 归属 >= 0:
			已有.归属者 = 归属
		return 已有
	var 面: GCard = get_card(GConst.牌号(iid))
	if 面 == null:
		return null
	var c: GCard = 面.复制()
	c.实例号 = iid
	c.归属者 = 归属
	if 元素 > 0:
		c.设置当前元素(元素)
	实例卡[iid] = c
	return c


func get_card(cid: int) -> GCard:
	if 实例卡.has(cid):
		return 实例卡[cid]
	if _card_by_id.has(cid):
		return _card_by_id[cid]
	var 面: int = GConst.牌号(cid)
	if 面 != cid and _card_by_id.has(面):
		return _card_by_id[面]
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


## 某名玩家名下的场卡（客户端画状态图标用）：
## 挂在某人面前（attached >= 0）的只归那个人；没挂人的才归拥有者（owner）。
## 【绝界】owner=结界师、attached=目标：只画在目标面板上，不能同时画在结界师身上。
func 玩家场卡(pid: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for 表: Dictionary in 场卡表:
		var 挂: int = int(表.get("attached", -1))
		if 挂 >= 0:
			if 挂 == pid:
				out.append(表)
		elif int(表.get("owner", -1)) == pid:
			out.append(表)
	return out


func team_of(color: int) -> GTeam:
	return red if color == GConst.RED else blue


# ============================================================
# 房间/玩家列表构建
# ============================================================
## 用服务端下发的 GameInfo 重建玩家列表（以自己为视角，座次从我方开始）
func build_player_list(info: Dictionary) -> void:
	game_info = info
	场卡表.clear()
	for 项: Variant in info.get("field_cards", []):
		if 项 is Dictionary:
			场卡表.append(项 as Dictionary)
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
	hand_iids.clear()
	cover_iids.clear()
	if my_pos < 0 or my_pos >= infos.size():
		return
	var me: Dictionary = infos[my_pos]
	var 元素表: Array = me.get("hand_elements", [])
	var i: int = 0
	for cid: Variant in me.get("hands", []):
		var iid: int = int(cid)
		var 元素: int = int(元素表[i]) if i < 元素表.size() else 0
		# 手牌一律用运行时实例副本：同一牌面的不同实例可以有各自的当前系别
		var c: GCard = 取实例卡(iid, 元素)
		if c != null:
			hand_cards.append(c)
			hand_iids.append(iid)
		i += 1
	for cid: Variant in me.get("covereds", []):
		var iid2: int = int(cid)
		var c2: GCard = 取实例卡(iid2)
		if c2 != null:
			cover_cards.append(c2)
			cover_iids.append(iid2)
	# 本地已切、服务端还没确认的系别优先于快照：避免切换后收到「切换前生成」的快照又弹回旧系别
	for j: int in range(hand_iids.size()):
		if 本地待确认元素.has(hand_iids[j]):
			hand_cards[j].设置当前元素(int(本地待确认元素[hand_iids[j]]))
	# 牌已经不在手里（用掉/交给别人）：这条待确认作废，别让新一局同实例号误用
	for 键: Variant in 本地待确认元素.keys():
		if not hand_iids.has(int(键)):
			本地待确认元素.erase(键)


## 把单条 SinglePlayerInfo 应用到玩家视图
func _apply_player_info(p: GPlayer, pi: Dictionary) -> void:
	p.set_team(int(pi.get("team", -1)))
	p.set_nickname(str(pi.get("nickname", "")))
	p.set_role(int(pi.get("role_id", 0)))
	p.id = int(pi.get("id", p.id))
	p.hand_cards_num = int(pi.get("hand_count", 0))
	p.cross_num = int(pi.get("heal_count", 0))
	p.no_heal = bool(pi.get("no_heal", false))
	p.gem = int(pi.get("gem", 0))
	p.crystal = int(pi.get("crystal", 0))
	p.tap = bool(pi.get("is_knelt", false))
	# 梦想剑档位：客户端角色说明据此把梦想剑标绿
	p.dream_tier = int(pi.get("dream_tier", 0))
	# 本回合「下次主动攻击只能打谁」（剑残影 10804）：客户端据此把其余敌方头像置灰
	p.attack_lock = int(pi.get("attack_lock", -1))
	# 血色剑灵【血蔷薇庭院】：独立状态，不是横置形态
	p.xue_qiang_wei = bool(pi.get("xue_qiang_wei", false))
	# 圣弓专属技正反面：客户端画【圣煌辉光炮】/【圣煌余辉】状态图标
	p.sheng_huang_side = int(pi.get("sheng_huang_side", 0))
	# 额外回合的加伤（剑守誓言 10803）：客户端在状态区画「剑守誓言」图标
	p.extra_turn_cause = int(pi.get("extra_turn_cause", 0))
	p.extra_turn_bonus = int(pi.get("extra_turn_bonus", 0))
	p.ready = bool(pi.get("ready", false))
	p.leader = int(pi.get("leader", 0)) == 1
	p.online = bool(pi.get("online", true))
	p.ping = int(pi.get("ping", GConst.PING_未测))
	# 面朝上的盖牌（结界师【结界】等）：牌面公开，按服务端下发的牌面重建
	p.cover_opens.clear()
	for cid: Variant in pi.get("cover_opens", []):
		p.cover_opens.append(int(cid))
	# 公开的「手牌里有魔刃/异刃」：头像状态
	p.hand_blades.clear()
	for cid: Variant in pi.get("hand_blades", []):
		var 面: int = int(cid)
		if not p.hand_blades.has(面):
			p.hand_blades.append(面)
	# 【律法】标记（星坠女巫）
	p.laws.clear()
	for 号: Variant in pi.get("laws", []):
		p.laws.append(int(号))
	if pi.has("max_hand"):
		p.hand_cards_max = int(pi["max_hand"])
	# 治疗上限：角色被动改过（如神官【圣使守护】+4），按服务端下发的值显示
	if pi.has("max_heal"):
		p.set_cross_max(int(pi["max_heal"]))
	# 能量上限：角色被动改过（如贤者 +1），判「星石已满 / 还有空位」用它
	if pi.has("max_energy"):
		p.set_energy_max(int(pi["max_energy"]))
	# 盖牌上限：客户端「查看盖牌」时按它摆空槽
	if pi.has("max_covered"):
		p.cover_cards_max = int(pi["max_covered"])
	# 基础效果
	p.clean_basic_status()
	for cid: Variant in pi.get("basic_cards", []):
		var card: GCard = get_card(int(cid))
		if card != null:
			# 存原始 id（可能是实例号）：点选 / 带走基础效果牌时要按它认人
			p.add_basic_status(0, card, int(cid))
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
	hand_iids.clear()
	cover_iids.clear()
