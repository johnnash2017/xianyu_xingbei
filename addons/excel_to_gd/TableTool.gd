# 文件名: TableTool.gd
# 功能: 数据表辅助工具，提供查询、排序、随机等便捷方法
# 版本: 4.1 (支持 Vector2/3/4 和 Color 类型)
class_name TableTool

enum 排序方式 { 升序, 降序 }

# 从表名字符串获取对应的数据字典（表名与导表生成的 数据表格 静态变量一一对应）
static func _获取表字典(表名: String) -> Dictionary:
	match 表名:
		"卡牌表": return 数据表格.卡牌表
		"卡组表": return 数据表格.卡组表
		"属性类型表": return 数据表格.属性类型表
		"文本表": return 数据表格.文本表
		_: return {}

static func _获取元数据(表名: String) -> Dictionary:
	if not 数据表格.表元数据.has(表名):
		push_error("TableTool: 无效的表名 '%s'" % 表名)
		return {}
	return 数据表格.表元数据[表名]

static func _行转字典(行数组: Array, 列索引: Dictionary, 行标识符: String) -> Dictionary:
	var 结果 = {}
	# id 不再存储在行数组中，由字典键提供，转字典时补回
	结果["id"] = 行标识符
	for 列名称 in 列索引:
		var 索引 = 列索引[列名称]
		if 索引 < 行数组.size():
			结果[列名称] = 行数组[索引]
	return 结果

# 辅助：将任意值转为可比较的字符串（用于排序）
static func _值转可比较字符串(值: Variant) -> String:
	match typeof(值):
		TYPE_VECTOR2:
			return "Vector2(%s,%s)" % [值.x, 值.y]
		TYPE_VECTOR3:
			return "Vector3(%s,%s,%s)" % [值.x, 值.y, 值.z]
		TYPE_VECTOR4:
			return "Vector4(%s,%s,%s,%s)" % [值.x, 值.y, 值.z, 值.w]
		TYPE_COLOR:
			return "Color(%s,%s,%s,%s)" % [值.r, 值.g, 值.b, 值.a]
		_:
			return str(值)

static func 获取行(表名: String, 行标识符: String) -> Variant:
	var 元数据 = _获取元数据(表名)
	if 元数据.is_empty(): return null
	var 表字典 = _获取表字典(表名)
	var 原始数据 = 表字典.get(行标识符, null)
	if 原始数据 == null: return null
	var 是否多行 = 元数据["是否多行"]
	var 列索引 = 元数据["列索引"]
	if 是否多行:
		if typeof(原始数据) == TYPE_ARRAY:
			var 结果 = []
			for 行 in 原始数据:
				结果.append(_行转字典(行, 列索引, 行标识符))
			return 结果
	else:
		if typeof(原始数据) == TYPE_ARRAY:
			return _行转字典(原始数据, 列索引, 行标识符)
	return null

static func 包含行(表名: String, 行标识符: String) -> bool:
	var 表字典 = _获取表字典(表名)
	return 表字典.has(行标识符)

static func 获取行数(表名: String) -> int:
	var 表字典 = _获取表字典(表名)
	return 表字典.size()

static func 获取行列值(表名: String, 行标识符: String, 列名称: String, 行索引: int = 0) -> Variant:
	var 元数据 = _获取元数据(表名)
	if 元数据.is_empty():
		push_error("TableTool: 无效的表名 '%s'" % 表名)
		return null
	var 表字典 = _获取表字典(表名)
	var 原始数据 = 表字典.get(行标识符, null)
	if 原始数据 == null:
		push_error("TableTool: 表中不存在行标识符 '%s'" % 行标识符)
		return null
	# id 列不再存储在行数组中，直接由行标识符提供
	if 列名称 == "id":
		return 行标识符
	var 列索引字典 = 元数据["列索引"]
	var 索引 = 列索引字典.get(列名称, -1)
	if 索引 == -1:
		push_error("TableTool: 表中不存在列名称 '%s'" % 列名称)
		return null
	var 是否多行 = 元数据["是否多行"]
	if 是否多行:
		if typeof(原始数据) != TYPE_ARRAY or 原始数据.size() == 0:
			push_error("TableTool: 多行表中ID为 '%s' 的数据格式错误" % 行标识符)
			return null
		if 行索引 < 0 or 行索引 >= 原始数据.size():
			push_error("TableTool: 行索引 '%s' 超出范围 (0-%d)" % [行索引, 原始数据.size() - 1])
			return null
		var 行 = 原始数据[行索引]
		if typeof(行) != TYPE_ARRAY or 索引 >= 行.size():
			push_error("TableTool: 行数据格式错误或列索引超出范围")
			return null
		return 行[索引]
	else:
		if 行索引 != 0:
			push_error("TableTool: 单行表只支持行索引 0")
			return null
		if typeof(原始数据) != TYPE_ARRAY or 索引 >= 原始数据.size():
			push_error("TableTool: 行数据格式错误或列索引超出范围")
			return null
		return 原始数据[索引]

static func 获取实体行数(表名: String, 行标识符: String) -> int:
	var 表字典 = _获取表字典(表名)
	var 原始数据 = 表字典.get(行标识符, null)
	return 原始数据.size() if typeof(原始数据) == TYPE_ARRAY else 0

static func 获取排序首行(表名: String, 列名称: String, 排序: 排序方式) -> Variant:
	var 元数据 = _获取元数据(表名)
	if 元数据.is_empty(): return null
	var 表字典 = _获取表字典(表名)
	var 列索引字典 = 元数据["列索引"]
	var 列索引值 = 列索引字典.get(列名称, -1)
	if 列索引值 == -1: return null
	var 是否多行 = 元数据["是否多行"]
	var 有效行 = []
	for 行标识符 in 表字典:
		var 原始数据 = 表字典[行标识符]
		if 是否多行:
			if typeof(原始数据) != TYPE_ARRAY: continue
			for 行索引 in range(原始数据.size()):
				var 当前行 = 原始数据[行索引]
				if typeof(当前行) != TYPE_ARRAY or 列索引值 >= 当前行.size(): continue
				var 值 = 当前行[列索引值]
				有效行.append([行标识符, 行索引, _值转可比较字符串(值)])
		else:
			if typeof(原始数据) != TYPE_ARRAY or 列索引值 >= 原始数据.size(): continue
			var 值 = 原始数据[列索引值]
			有效行.append([行标识符, 0, _值转可比较字符串(值)])
	if 有效行.is_empty(): return null
	if 排序 == 排序方式.升序:
		有效行.sort_custom(func(a,b): return a[2] < b[2])
	else:
		有效行.sort_custom(func(a,b): return a[2] > b[2])
	var 目标值 = 有效行[0][2]
	var 候选行 = []
	for 项 in 有效行:
		if 项[2] == 目标值: 候选行.append([项[0], 项[1]])
		else: break
	if 候选行.is_empty(): return null
	var 随机 = RandomNumberGenerator.new()
	随机.randomize()
	var 选中 = 候选行[随机.randi() % 候选行.size()]
	var 原始数据 = 表字典[选中[0]]
	if 是否多行:
		return _行转字典(原始数据[选中[1]], 列索引字典, 选中[0])
	else:
		return _行转字典(原始数据, 列索引字典, 选中[0])

static func 按权重随机获取行(表名: String, 权重列名称: String) -> Variant:
	var 元数据 = _获取元数据(表名)
	if 元数据.is_empty(): return null
	var 表字典 = _获取表字典(表名)
	var 列索引字典 = 元数据["列索引"]
	var 权重索引 = 列索引字典.get(权重列名称, -1)
	if 权重索引 == -1: return null
	var 是否多行 = 元数据["是否多行"]
	var 权重列表 = []
	var 总权重 = 0.0
	for 行标识符 in 表字典:
		var 原始数据 = 表字典[行标识符]
		var 权重值 = null
		if 是否多行:
			if typeof(原始数据) != TYPE_ARRAY or 原始数据.size() == 0: continue
			var 第一行 = 原始数据[0]
			if typeof(第一行) != TYPE_ARRAY or 权重索引 >= 第一行.size(): continue
			权重值 = 第一行[权重索引]
		else:
			if typeof(原始数据) != TYPE_ARRAY or 权重索引 >= 原始数据.size(): continue
			权重值 = 原始数据[权重索引]
		
		var 权重数字 = 0.0
		if typeof(权重值) == TYPE_BOOL:
			权重数字 = 1.0 if 权重值 else 0.0
		elif typeof(权重值) in [TYPE_INT, TYPE_FLOAT]:
			权重数字 = float(权重值)
		else:
			if 权重值 != null:
				push_warning("TableTool: 权重列 '%s' 的值 '%s' 不是数值类型，已忽略" % [权重列名称, 权重值])
			continue
		
		if 权重数字 > 0:
			权重列表.append([行标识符, 0, 权重数字])
			总权重 += 权重数字
	
	if 权重列表.is_empty() or 总权重 <= 0: return null
	var 随机 = RandomNumberGenerator.new()
	随机.randomize()
	var 随机值 = 随机.randf() * 总权重
	var 累积 = 0.0
	for 项 in 权重列表:
		累积 += 项[2]
		if 随机值 <= 累积:
			var 原始数据 = 表字典[项[0]]
			if 是否多行:
				return _行转字典(原始数据[项[1]], 列索引字典, 项[0])
			else:
				return _行转字典(原始数据, 列索引字典, 项[0])
	return null
