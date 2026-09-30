# 文件名: CsvToGd.gd
# 功能: 将合法 CSV 文件夹转换为单例数据表脚本（纯净表字典 + 表元数据）
# 版本: 16.0 (增量生成优化)
class_name CsvToGd

# ==================== 多线程相关变量 ====================
var _互斥锁: Mutex
var _信号量: Semaphore
var _解析结果队列: Array
var _线程结束标志: bool
var _工作线程数量: int = 8  # 0 表示使用默认值（CPU核心数）
var _已完成文件数: int

# ==================== 增量生成缓存 ====================
var _表生成缓存: Dictionary = {}  # 表名称 -> { "哈希": String, "代码": String }
var _文件哈希缓存: Dictionary = {}  # 文件路径 -> 哈希值

# ==================== 线程数设置 ====================
func 设置工作线程数(数量: int) -> void:
	_工作线程数量 = max(1, 数量)

# ==================== 公共接口 ====================
func 转换文件夹为数据表(文件夹路径: String, 输出路径: String) -> bool:
	var 开始时刻 = Time.get_ticks_msec()  # 记录开始毫秒数
	
	_全局ID表.clear()
	_表信息数据库.clear()
	
	#print("[性能分析] 开始处理文件夹: %s" % 文件夹路径)
	
	var 扫描开始 = Time.get_ticks_msec()
	var CSV文件列表 = _扫描CSV文件夹(文件夹路径)
	var 扫描结束 = Time.get_ticks_msec()
	#print("[性能分析] 扫描文件耗时: %.2f 秒, 找到 %d 个CSV文件" % [(扫描结束 - 扫描开始) / 1000.0, CSV文件列表.size()])
	
	if CSV文件列表.is_empty():
		print_rich("[color=red]未找到任何 CSV 文件[/color]")
		print("运行时间: %.2f 秒" % ((Time.get_ticks_msec() - 开始时刻) / 1000.0))
		return false
	
	# 初始化多线程相关变量
	_互斥锁 = Mutex.new()
	_信号量 = Semaphore.new()
	_解析结果队列 = []
	_线程结束标志 = false
	_已完成文件数 = 0
	
	# 默认使用CPU核心数，至少1个线程
	if _工作线程数量 == 0:
		_工作线程数量 = max(1, OS.get_processor_count())
	
	print("[性能分析] 启动 %d 个线程进行文件解析..." % _工作线程数量)
	
	# 多线程解析CSV文件
	var 解析开始 = Time.get_ticks_msec()
	var 解析错误列表 = _多线程解析CSV文件(CSV文件列表)
	var 解析结束 = Time.get_ticks_msec()
	print("[性能分析] 解析CSV文件耗时: %.2f 秒" % ((解析结束 - 解析开始) / 1000.0))
	
	if 解析错误列表.size() > 0:
		print_rich("[color=red][警告] 解析阶段发现 %d 个问题，继续处理可用文件：[/color]" % 解析错误列表.size())
		for 错误信息 in 解析错误列表:
			print_rich("[color=red]  %s[/color]" % 错误信息)
	
	if _表信息数据库.is_empty():
		print_rich("[color=red][错误] 没有成功解析任何CSV文件[/color]")
		print("运行时间: %.2f 秒" % ((Time.get_ticks_msec() - 开始时刻) / 1000.0))
		return false
	
	var 校验开始 = Time.get_ticks_msec()
	var 校验错误列表 = _校验所有表数据完整性()
	var 校验结束 = Time.get_ticks_msec()
	print("[性能分析] 校验数据完整性耗时: %.2f 秒" % ((校验结束 - 校验开始) / 1000.0))
	
	if 校验错误列表.size() > 0:
		print_rich("[color=red][警告] 数据校验阶段发现 %d 个问题，跳过有问题的表：[/color]" % 校验错误列表.size())
		for 错误信息 in 校验错误列表:
			print_rich("[color=red]  %s[/color]" % 错误信息)
	
	if _表信息数据库.is_empty():
		print_rich("[color=red][错误] 没有可用的数据表[/color]")
		print("运行时间: %.2f 秒" % ((Time.get_ticks_msec() - 开始时刻) / 1000.0))
		return false
	
	var 生成开始 = Time.get_ticks_msec()
	var 脚本代码 = _生成数据表格脚本()
	var 生成结束 = Time.get_ticks_msec()
	print("[性能分析] 生成脚本代码耗时: %.2f 秒" % ((生成结束 - 生成开始) / 1000.0))
	
	var 写入开始 = Time.get_ticks_msec()
	
	# 读取已有文件内容进行比较，避免不必要的写入触发的编辑器重载
	var 已有内容: String = ""
	if FileAccess.file_exists(输出路径):
		var 已有文件: FileAccess = FileAccess.open(输出路径, FileAccess.READ)
		if 已有文件:
			已有内容 = 已有文件.get_as_text()
			已有文件.close()
	
	if 已有内容 == 脚本代码:
		print("[增量生成] 内容未变更，跳过文件写入")
	else:
		var 输出文件: FileAccess = FileAccess.open(输出路径, FileAccess.WRITE)
		if not 输出文件:
			print_rich("[color=red]无法写入文件: %s[/color]" % 输出路径)
			print("运行时间: %.2f 秒" % ((Time.get_ticks_msec() - 开始时刻) / 1000.0))
			return false
		输出文件.store_string(脚本代码)
		输出文件.close()
	var 写入结束 = Time.get_ticks_msec()
	print("[性能分析] 写入文件耗时: %.2f 秒" % ((写入结束 - 写入开始) / 1000.0))
	
	#print("成功生成数据表格脚本: ", 输出路径)
	print("[性能分析] 总运行时间: %.2f 秒" % ((Time.get_ticks_msec() - 开始时刻) / 1000.0))
	return true

# ==================== 内部变量 ====================
var _全局ID表 = {}
var _表信息数据库 = {}

# ==================== 多线程解析 ====================
func _多线程解析CSV文件(CSV文件路径列表: Array[String]) -> Array[String]:
	# 1个线程时直接处理，避免死锁
	if _工作线程数量 == 1:
		var 错误信息列表: Array[String] = []
		var 结果: Dictionary = _解析单个线程(CSV文件路径列表)
		if 结果.has("错误"):
			错误信息列表.append_array(结果["错误"])
		if 结果.has("表信息"):
			for 表名称 in 结果["表信息"]:
				_表信息数据库[表名称] = 结果["表信息"][表名称]
		if 结果.has("ID映射"):
			for ID值 in 结果["ID映射"]:
				if _全局ID表.has(ID值):
					错误信息列表.append("[错误] ID '%s' 在多个表中重复 (表: %s, %s)" % [ID值, _全局ID表[ID值], 结果["ID映射"][ID值]])
				else:
					_全局ID表[ID值] = 结果["ID映射"][ID值]
		return 错误信息列表
	
	# 多线程处理
	var 错误信息列表: Array[String] = []
	var 线程列表: Array[Thread] = []
	var 文件分配: Array = []
	var 总文件数 = CSV文件路径列表.size()
	
	# 优化任务分配：按文件大小或复杂度分配，这里使用简单的轮询分配
	for i in range(_工作线程数量):
		文件分配.append([])
	
	# 更均匀的文件分配
	for 索引 in range(总文件数):
		文件分配[索引 % _工作线程数量].append(CSV文件路径列表[索引])
	
	# 启动线程
	for i in range(_工作线程数量):
		if 文件分配[i].is_empty():
			continue
		var 线程 = Thread.new()
		var 错误 = 线程.start(_解析线程函数.bind([i, 文件分配[i]]), Thread.PRIORITY_HIGH)
		if 错误 != OK:
			错误信息列表.append("[错误] 启动线程 %d 失败" % i)
		else:
			线程列表.append(线程)
	
	# 收集结果（优化：批量处理结果，减少信号量操作）
	# 注意：每个工作线程结束时只提交 1 份结果、只 post 1 次信号量，所以这里的进度
	# 必须和"已启动的线程数"比较，不能和文件总数比较 —— 否则当 CSV 文件数 > 线程数时，
	# 主线程会永远卡在 _信号量.wait() 上（编辑器无响应、CPU 占用为 0，只能强杀）。
	# 同时改成"轮询 + 线程存活检查"：万一某个线程因脚本错误提前退出（不会再 post），
	# 也不会把主线程永久阻塞。
	var 待收集线程数: int = 线程列表.size()
	while true:
		var 线程全部结束: bool = not _有存活线程(线程列表)
		_互斥锁.lock()
		# 批量处理所有待处理的结果
		while _解析结果队列.size() > 0:
			var 结果 = _解析结果队列.pop_front()
			if 结果.has("错误"):
				错误信息列表.append_array(结果["错误"])
			if 结果.has("表信息"):
				for 表名称 in 结果["表信息"]:
					_表信息数据库[表名称] = 结果["表信息"][表名称]
			if 结果.has("ID映射"):
				for ID值 in 结果["ID映射"]:
					if _全局ID表.has(ID值):
						错误信息列表.append("[错误] ID '%s' 在多个表中重复 (表: %s, %s)" % [ID值, _全局ID表[ID值], 结果["ID映射"][ID值]])
					else:
						_全局ID表[ID值] = 结果["ID映射"][ID值]
			# 增加已完成文件数
			_已完成文件数 += 1
		_互斥锁.unlock()
		if _已完成文件数 >= 待收集线程数 or 线程全部结束:
			break
		OS.delay_msec(1)
	
	# 等待所有线程结束
	_线程结束标志 = true
	# 确保所有线程都能退出
	for i in range(线程列表.size()):
		_信号量.post()
	for 线程 in 线程列表:
		线程.wait_to_finish()
	
	return 错误信息列表

# 收集结果时用：是否还有工作线程在跑。
# 线程若因脚本错误提前退出，就永远不会再 post 信号量，只靠信号量计数会永久阻塞主线程。
func _有存活线程(线程列表: Array[Thread]) -> bool:
	for 线程 in 线程列表:
		if 线程.is_alive():
			return true
	return false

func _解析单个线程(文件列表: Array[String]) -> Dictionary:
	var 本地错误列表: Array[String] = []
	var 本地表信息: Dictionary = {}
	var 本地ID映射: Dictionary = {}
	
	for 文件路径 in 文件列表:
		var 表名称: String = 文件路径.get_file().get_basename()
		var 文件内容数组: Array = _读取CSV文件内容(文件路径)
		
		if 文件内容数组.is_empty():
			本地错误列表.append("[错误] 文件 %s 为空或无法读取" % 文件路径)
			continue
		
		if 文件内容数组.size() < 3:
			本地错误列表.append("[错误] %s 行数不足3行" % 文件路径)
			continue
		
		var 原始列名行: Array = _分割CSV行数据(文件内容数组[0])
		var 原始类型定义行: Array = _分割类型定义行(文件内容数组[2])
		
		while 原始类型定义行.size() < 原始列名行.size():
			原始类型定义行.append("")
		
		var 需要忽略的列索引字典: Dictionary = {}
		var 需要忽略的列索引列表: Array[int] = []
		for 索引 in range(原始列名行.size()):
			if 原始列名行[索引].strip_edges().is_empty() or 原始类型定义行[索引].strip_edges() == "不导出":
				需要忽略的列索引字典[索引] = true
				需要忽略的列索引列表.append(索引)
		
		var 列名数组: Array[String] = []
		var 类型定义数组: Array[String] = []
		列名数组.resize(原始列名行.size())
		类型定义数组.resize(原始列名行.size())
		var 实际列数: int = 0
		for 索引 in range(原始列名行.size()):
			if not 需要忽略的列索引字典.has(索引):
				列名数组[实际列数] = 原始列名行[索引]
				类型定义数组[实际列数] = 原始类型定义行[索引]
				实际列数 += 1
		列名数组.resize(实际列数)
		类型定义数组.resize(实际列数)
		
		if 列名数组.size() != 类型定义数组.size():
			本地错误列表.append("[错误] %s 过滤后列名行与数据类型行列数不一致" % 文件路径)
			continue
		
		var ID列索引: int = 列名数组.find("id")
		if ID列索引 == -1:
			本地错误列表.append("[错误] %s 缺少id列" % 文件路径)
			continue
		
		var 类型描述数组: Array = []
		类型描述数组.resize(类型定义数组.size())
		var 是否解析失败: bool = false
		for 索引 in range(类型定义数组.size()):
			var 类型定义字符串: String = 类型定义数组[索引]
			if 类型定义字符串.strip_edges().is_empty():
				本地错误列表.append("[错误] %s 第3行, 列'%s': 数据类型不能为空" % [文件路径, 列名数组[索引]])
				是否解析失败 = true
				break
			
			var 类型描述字典: Dictionary = _解析类型定义(类型定义字符串)
			if 类型描述字典 == null:
				本地错误列表.append("[错误] %s 第3行, 列'%s': 数据类型语法错误" % [文件路径, 列名数组[索引]])
				是否解析失败 = true
				break
			
			类型描述数组[索引] = 类型描述字典
		
		if 是否解析失败:
			continue
		
		var 数据行数组: Array = 文件内容数组.slice(3)
		
		var 是否是多行表: bool = false
		var 上一行ID: String = ""
		var 所有ID列表: Array = []
		所有ID列表.resize(数据行数组.size())
		var ID计数: int = 0
		var 当前实体ID: String = ""
		
		for 行号 in range(数据行数组.size()):
			var 原始行数据: String = 数据行数组[行号]
			
			var 是全空行: bool = true
			var 原始单元格数组: Array = _分割CSV行数据(原始行数据)
			for 索引 in range(原始单元格数组.size()):
				if not 需要忽略的列索引字典.has(索引) and not 原始单元格数组[索引].strip_edges().is_empty():
					是全空行 = false
					break
			if 是全空行:
				continue
			
			var 过滤后单元格数组: Array = []
			for 索引 in range(原始单元格数组.size()):
				if not 需要忽略的列索引字典.has(索引):
					过滤后单元格数组.append(原始单元格数组[索引].strip_edges())
			
			var 当前行ID: String = ""
			if ID列索引 < 过滤后单元格数组.size():
				当前行ID = 过滤后单元格数组[ID列索引]
			
			if not 是否是多行表 and 上一行ID != "" and 当前行ID.is_empty():
				是否是多行表 = true
			
			if 是否是多行表:
				if 当前行ID.is_empty():
					if 当前实体ID != "":
						所有ID列表[ID计数] = 当前实体ID
						ID计数 += 1
				else:
					当前实体ID = 当前行ID
					所有ID列表[ID计数] = 当前实体ID
					ID计数 += 1
			else:
				if 当前行ID.is_empty():
					本地错误列表.append("[错误] %s 第%d行: 单行表id不能为空" % [文件路径, 行号+4])
				else:
					所有ID列表[ID计数] = 当前行ID
					ID计数 += 1
			
			上一行ID = 当前行ID
		
		所有ID列表.resize(ID计数)
		
		var 唯一ID字典: Dictionary = {}
		var 唯一ID列表: Array = []
		for ID值 in 所有ID列表:
			if not 唯一ID字典.has(ID值):
				唯一ID字典[ID值] = true
				唯一ID列表.append(ID值)
		
		if not 是否是多行表 and 所有ID列表.size() > 唯一ID列表.size():
			本地错误列表.append("[错误] %s 单行表中存在重复ID，跳过该文件" % 文件路径)
			continue
		
		本地表信息[表名称] = {
			"文件路径": 文件路径,
			"列名数组": 列名数组,
			"类型描述数组": 类型描述数组,
			"ID列索引": ID列索引,
			"是否是多行表": 是否是多行表,
			"唯一ID列表": 唯一ID列表,
			"数据行数组": 数据行数组,
			"需要忽略的列索引列表": 需要忽略的列索引列表
		}
		
		for ID值 in 唯一ID列表:
			本地ID映射[ID值] = 表名称
	
	return {
		"错误": 本地错误列表,
		"表信息": 本地表信息,
		"ID映射": 本地ID映射
	}

func _解析线程函数(参数: Array) -> void:
	var 线程ID = 参数[0]
	var 文件列表 = 参数[1]
	var 线程开始时刻: int = Time.get_ticks_msec()
	
	#print("[性能分析] 线程 %d 开始处理 %d 个文件" % [线程ID, 文件列表.size()])
	
	var 本地错误列表: Array[String] = []
	var 本地表信息: Dictionary = {}
	var 本地ID映射: Dictionary = {}
	
	# 处理分配的文件
	for 文件路径 in 文件列表:
		var 文件开始时刻: int = Time.get_ticks_msec()
		
		if _线程结束标志:
			break
		
		var 表名称: String = 文件路径.get_file().get_basename()
		var 文件内容数组: Array = _读取CSV文件内容(文件路径)
		
		var 文件结束时刻: int = Time.get_ticks_msec()
		#print("[性能分析] 线程 %d 处理文件 %s 耗时: %.2f 秒" % [线程ID, 文件路径.get_file(), (文件结束时刻 - 文件开始时刻) / 1000.0])
		
		if 文件内容数组.is_empty():
			本地错误列表.append("[错误] 文件 %s 为空或无法读取" % 文件路径)
			continue
		
		if 文件内容数组.size() < 3:
			本地错误列表.append("[错误] %s 行数不足3行" % 文件路径)
			continue
		
		var 原始列名行: Array = _分割CSV行数据(文件内容数组[0])
		var 原始类型定义行: Array = _分割类型定义行(文件内容数组[2])
		
		# 优化：预分配数组大小
		var 原始列名行数: int = 原始列名行.size()
		while 原始类型定义行.size() < 原始列名行数:
			原始类型定义行.append("")
		
		# 优化：使用字典代替数组查找，提高速度
		var 需要忽略的列索引字典: Dictionary = {}
		var 需要忽略的列索引列表: Array[int] = []
		for 索引 in range(原始列名行数):
			if 原始列名行[索引].strip_edges().is_empty() or 原始类型定义行[索引].strip_edges() == "不导出":
				需要忽略的列索引字典[索引] = true
				需要忽略的列索引列表.append(索引)
		
		# 优化：预分配数组大小
		var 列名数组: Array[String] = []
		var 类型定义数组: Array[String] = []
		列名数组.resize(原始列名行数)
		类型定义数组.resize(原始列名行数)
		var 实际列数: int = 0
		for 索引 in range(原始列名行数):
			if not 需要忽略的列索引字典.has(索引):
				列名数组[实际列数] = 原始列名行[索引]
				类型定义数组[实际列数] = 原始类型定义行[索引]
				实际列数 += 1
		# 裁剪数组到实际大小
		列名数组.resize(实际列数)
		类型定义数组.resize(实际列数)
		
		if 列名数组.size() != 类型定义数组.size():
			本地错误列表.append("[错误] %s 过滤后列名行与数据类型行列数不一致" % 文件路径)
			continue
		
		var ID列索引: int = 列名数组.find("id")
		if ID列索引 == -1:
			本地错误列表.append("[错误] %s 缺少id列" % 文件路径)
			continue
		
		# 优化：预分配数组大小
		var 类型描述数组: Array = []
		类型描述数组.resize(类型定义数组.size())
		var 是否解析失败: bool = false
		for 索引 in range(类型定义数组.size()):
			var 类型定义字符串: String = 类型定义数组[索引]
			if 类型定义字符串.strip_edges().is_empty():
				本地错误列表.append("[错误] %s 第3行, 列'%s': 数据类型不能为空" % [文件路径, 列名数组[索引]])
				是否解析失败 = true
				break
			
			var 类型描述字典: Dictionary = _解析类型定义(类型定义字符串)
			if 类型描述字典 == null:
				本地错误列表.append("[错误] %s 第3行, 列'%s': 数据类型语法错误" % [文件路径, 列名数组[索引]])
				是否解析失败 = true
				break
			
			类型描述数组[索引] = 类型描述字典
		
		if 是否解析失败:
			continue
		
		var 数据行数组: Array = 文件内容数组.slice(3)
		var 数据行数量: int = 数据行数组.size()
		
		# 优化：合并两个循环，减少函数调用
		var 是否是多行表: bool = false
		var 上一行ID: String = ""
		var 所有ID列表: Array = []
		所有ID列表.resize(数据行数量)
		var ID计数: int = 0
		var 当前实体ID: String = ""
		
		for 行号 in range(数据行数量):
			var 原始行数据: String = 数据行数组[行号]
			
			# 内联 _检测是否全空行 逻辑
			var 是全空行: bool = true
			var 原始单元格数组: Array = _分割CSV行数据(原始行数据)
			for 索引 in range(原始单元格数组.size()):
				if not 需要忽略的列索引字典.has(索引) and not 原始单元格数组[索引].strip_edges().is_empty():
					是全空行 = false
					break
			if 是全空行:
				continue
			
			# 内联 _过滤单元格数组 逻辑
			var 过滤后单元格数组: Array = []
			for 索引 in range(原始单元格数组.size()):
				if not 需要忽略的列索引字典.has(索引):
					过滤后单元格数组.append(原始单元格数组[索引])
			
			var 当前行ID: String = ""
			if ID列索引 < 过滤后单元格数组.size():
				当前行ID = 过滤后单元格数组[ID列索引]
			
			# 检测是否是多行表
			if not 是否是多行表 and 上一行ID != "" and 当前行ID.is_empty():
				是否是多行表 = true
			
			# 收集ID
			if 是否是多行表:
				if 当前行ID.is_empty():
					if 当前实体ID != "":
						所有ID列表[ID计数] = 当前实体ID
						ID计数 += 1
				else:
					当前实体ID = 当前行ID
					所有ID列表[ID计数] = 当前实体ID
					ID计数 += 1
			else:
				if 当前行ID.is_empty():
					本地错误列表.append("[错误] %s 第%d行: 单行表id不能为空" % [文件路径, 行号+4])
				else:
					所有ID列表[ID计数] = 当前行ID
					ID计数 += 1
			
			上一行ID = 当前行ID
		
		# 裁剪数组到实际大小
		所有ID列表.resize(ID计数)
		
		# 优化：使用字典去重，提高速度
		var 唯一ID字典: Dictionary = {}
		var 唯一ID列表: Array = []
		for ID值 in 所有ID列表:
			if not 唯一ID字典.has(ID值):
				唯一ID字典[ID值] = true
				唯一ID列表.append(ID值)
		
		if not 是否是多行表 and 所有ID列表.size() > 唯一ID列表.size():
			本地错误列表.append("[错误] %s 单行表中存在重复ID，跳过该文件" % 文件路径)
			continue
		
		本地表信息[表名称] = {
			"文件路径": 文件路径,
			"列名数组": 列名数组,
			"类型描述数组": 类型描述数组,
			"ID列索引": ID列索引,
			"是否是多行表": 是否是多行表,
			"唯一ID列表": 唯一ID列表,
			"数据行数组": 数据行数组,
			"需要忽略的列索引列表": 需要忽略的列索引列表
		}
		
		for ID值 in 唯一ID列表:
			本地ID映射[ID值] = 表名称
	
	# 批量添加结果，减少锁竞争
	_互斥锁.lock()
	_解析结果队列.append({
		"错误": 本地错误列表,
		"表信息": 本地表信息,
		"ID映射": 本地ID映射
	})
	_互斥锁.unlock()
	
	# 只发送一次信号，减少信号量操作
	_信号量.post()
	
	var 线程结束时刻 = Time.get_ticks_msec()
	#print("[性能分析] 线程 %d 完成处理，总耗时: %.2f 秒" % [线程ID, (线程结束时刻 - 线程开始时刻) / 1000.0])

# ==================== CSV 文件扫描 ====================
func _扫描CSV文件夹(文件夹路径: String) -> Array[String]:
	var CSV文件列表: Array[String] = []
	var 目录对象 = DirAccess.open(文件夹路径)
	if 目录对象:
		目录对象.list_dir_begin()
		var 当前文件名 = 目录对象.get_next()
		while 当前文件名 != "":
			if 当前文件名.ends_with(".csv") and not 目录对象.current_is_dir():
				CSV文件列表.append(文件夹路径.path_join(当前文件名))
			当前文件名 = 目录对象.get_next()
		目录对象.list_dir_end()
	else:
		push_error("无法打开文件夹: ", 文件夹路径)
	CSV文件列表.sort()
	return CSV文件列表

# ==================== 空行检测 ====================
func _检测是否全空行(原始行数据: String, 需要忽略的列索引列表: Array[int]) -> bool:
	var 原始单元格数组 = _分割CSV行数据(原始行数据)
	var 过滤后单元格数组 = _过滤单元格数组(原始单元格数组, 需要忽略的列索引列表)
	for 单元格内容 in 过滤后单元格数组:
		if 单元格内容.strip_edges() != "":
			return false
	return true

# ==================== CSV 解析核心 ====================

# 安全读取文件文本，绕过Excel等程序的文件锁
func _读取文件文本安全(文件路径: String) -> String:
	# 第一次尝试
	var 文件对象: FileAccess = FileAccess.open(文件路径, FileAccess.READ)
	if 文件对象:
		var 文本: String = 文件对象.get_as_text()
		文件对象.close()
		return 文本
	
	# 短暂等待后重试一次（Excel可能正在保存）
	OS.delay_msec(50)
	文件对象 = FileAccess.open(文件路径, FileAccess.READ)
	if 文件对象:
		var 文本: String = 文件对象.get_as_text()
		文件对象.close()
		return 文本
	
	# 文件被锁（如Excel打开中），用PowerShell + .NET FileShare.ReadWrite 绕过锁读取
	var 系统路径: String = ProjectSettings.globalize_path(文件路径)
	# 每个文件用独立的临时路径，防止多线程互相覆盖
	var 临时系统路径: String = OS.get_user_data_dir().path_join(
		"_csv_%s_%d.tmp" % [文件路径.get_file().get_basename(), Time.get_ticks_usec()]
	)
	var ps脚本: String = (
		"$src = '%s'; $dst = '%s'; " +
		"try { " +
		"  $fs = [System.IO.File]::Open($src, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite); " +
		"  $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8); " +
		"  $content = $sr.ReadToEnd(); $sr.Close(); $fs.Close(); " +
		"  [System.IO.File]::WriteAllText($dst, $content, [System.Text.Encoding]::UTF8); " +
		"  exit 0; " +
		"} catch { exit 1; }"
	) % [系统路径, 临时系统路径]
	var 退出码: int = OS.execute("powershell.exe", ["-NoProfile", "-Command", ps脚本], [], true)
	if 退出码 == 0:
		var 临时文件: FileAccess = FileAccess.open(临时系统路径, FileAccess.READ)
		if 临时文件:
			var 文本: String = 临时文件.get_as_text()
			临时文件.close()
			DirAccess.remove_absolute(临时系统路径)
			return 文本
		DirAccess.remove_absolute(临时系统路径)
	
	print_rich("[color=red]无法打开文件: %s[/color]" % 文件路径)
	return ""

func _读取CSV文件内容(文件路径: String) -> Array[String]:
	var 文本: String = _读取文件文本安全(文件路径)
	if 文本.is_empty():
		return []

	if 文本.begins_with("\uFEFF"):
		文本 = 文本.substr(1)

	# 优化：使用字符串缓冲区
	var 逻辑行数组: Array[String] = []
	var 当前行 = ""
	var 在引号内 = false
	var 长度 = 文本.length()
	var 索引 = 0

	# 优化：使用字符串缓冲区
	var 字符缓冲区 = []

	while 索引 < 长度:
		var 字符 = 文本[索引]
		
		if 字符 == '"':
			if 在引号内 and 索引 + 1 < 长度 and 文本[索引+1] == '"':
				# 转义引号：原样保留两个引号，交给 _分割CSV行数据 处理
				# （只追加一个的话，后面的引号配对会错位，单元格里的逗号会被当成分隔符）
				字符缓冲区.append('""')
				索引 += 1
			else:
				在引号内 = not 在引号内
				字符缓冲区.append('"')
		elif 字符 == '\n':
			if 在引号内:
				字符缓冲区.append('\n')
			else:
				# 构建当前行并添加到数组
				当前行 = "".join(字符缓冲区)
				逻辑行数组.append(当前行)
				字符缓冲区.clear()  # 清空缓冲区
		elif 字符 == '\r':
			pass
		else:
			字符缓冲区.append(字符)
		索引 += 1

	if 字符缓冲区.size() > 0:
		当前行 = "".join(字符缓冲区)
		逻辑行数组.append(当前行)
	return 逻辑行数组

func _分割CSV行数据(行文本: String) -> Array[String]:
	var 单元格数组: Array[String] = []
	var 字符缓冲区: PackedStringArray = PackedStringArray()
	var 在引号内: bool = false
	var 索引: int = 0
	var 长度: int = 行文本.length()
	var 最后字符是逗号: bool = false

	while 索引 < 长度:
		var 字符: String = 行文本[索引]
		
		if 字符 == '"':
			if 在引号内 and 索引 + 1 < 长度 and 行文本[索引+1] == '"':
				字符缓冲区.append('"')
				索引 += 1
			else:
				在引号内 = not 在引号内
			最后字符是逗号 = false
		elif 字符 == ',' and not 在引号内:
			单元格数组.append("".join(字符缓冲区))
			字符缓冲区.clear()
			最后字符是逗号 = true
		else:
			字符缓冲区.append(字符)
			最后字符是逗号 = false
		索引 += 1

	if 字符缓冲区.size() > 0:
		单元格数组.append("".join(字符缓冲区))
	elif 最后字符是逗号:
		单元格数组.append("")
	
	for i in 单元格数组.size():
		var 单元格: String = 单元格数组[i]
		if 单元格.length() >= 2 and 单元格[0] == '"' and 单元格[-1] == '"':
			单元格数组[i] = 单元格.substr(1, 单元格.length() - 2).replace('""', '"')

	return 单元格数组

func _分割类型定义行(行文本: String) -> Array[String]:
	# 优化：使用字符串缓冲区
	var 结果数组: Array[String] = []
	
	# 优化：使用字符串缓冲区
	var 字符缓冲区: Array = []
	
	var 括号嵌套深度: int = 0
	var 当前位置: int = 0
	var 长度: int = 行文本.length()

	while 当前位置 < 长度:
		var 当前字符: String = 行文本[当前位置]
		if 当前字符 == '(':
			括号嵌套深度 += 1
			字符缓冲区.append(当前字符)
		elif 当前字符 == ')':
			括号嵌套深度 -= 1
			字符缓冲区.append(当前字符)
		elif 当前字符 == ',' and 括号嵌套深度 == 0:
			# 构建当前字段并添加到数组
			var 当前字段: String = "".join(字符缓冲区)
			结果数组.append(当前字段.strip_edges())
			字符缓冲区.clear()  # 清空缓冲区
		else:
			字符缓冲区.append(当前字符)
		当前位置 += 1

	if 字符缓冲区.size() > 0:
		var 当前字段: String = "".join(字符缓冲区)
		结果数组.append(当前字段.strip_edges())

	return 结果数组

func _分割字符串忽略括号(输入字符串: String, 分隔字符: String) -> Array[String]:
	# 优化：使用字符串缓冲区
	var 结果数组: Array[String] = []
	
	# 优化：使用字符串缓冲区
	var 字符缓冲区: Array = []
	
	var 括号嵌套深度: int = 0
	var 当前位置: int = 0
	var 长度: int = 输入字符串.length()

	while 当前位置 < 长度:
		var 当前字符: String = 输入字符串[当前位置]
		if 当前字符 == "(":
			括号嵌套深度 += 1
			字符缓冲区.append(当前字符)
		elif 当前字符 == ")":
			括号嵌套深度 -= 1
			字符缓冲区.append(当前字符)
		elif 当前字符 == 分隔字符 and 括号嵌套深度 == 0:
			# 构建当前片段并添加到数组
			var 当前片段: String = "".join(字符缓冲区)
			结果数组.append(当前片段)
			字符缓冲区.clear()  # 清空缓冲区
		else:
			字符缓冲区.append(当前字符)
		当前位置 += 1

	if 字符缓冲区.size() > 0:
		var 当前片段: String = "".join(字符缓冲区)
		结果数组.append(当前片段)
	return 结果数组

func _过滤单元格数组(原始数组: Array[String], 需要忽略的索引列表: Array[int]) -> Array[String]:
	# 优化：使用字典提高查找速度
	var 过滤后数组: Array[String] = []
	var 需要忽略的索引字典: Dictionary = {}
	for 索引 in 需要忽略的索引列表:
		需要忽略的索引字典[索引] = true
	
	for 索引 in range(原始数组.size()):
		if not 需要忽略的索引字典.has(索引):
			过滤后数组.append(原始数组[索引].strip_edges())
	return 过滤后数组

# ==================== 数据类型解析 ====================
func _解析类型定义(类型定义字符串: String) -> Variant:
	var 处理后字符串: String = 类型定义字符串.strip_edges()
	# 去除外围引号（如果存在）
	if 处理后字符串.length() >= 2 and 处理后字符串[0] == '"' and 处理后字符串[-1] == '"':
		处理后字符串 = 处理后字符串.substr(1, 处理后字符串.length() - 2).strip_edges()
	
	var 默认值: Variant = null
	var 分隔符: Variant = null
	var 核心类型定义: String = 处理后字符串
	
	var 后缀开始位置: int = 核心类型定义.find("#")
	while 后缀开始位置 != -1:
		var 括号嵌套深度: int = 0
		var 是否有效: bool = true
		for 索引 in range(后缀开始位置):
			var 当前字符: String = 核心类型定义[索引]
			if 当前字符 == "(":
				括号嵌套深度 += 1
			elif 当前字符 == ")":
				括号嵌套深度 -= 1
			if 括号嵌套深度 < 0:
				是否有效 = false
				break
		if 括号嵌套深度 != 0:
			是否有效 = false
		if 是否有效:
			var 后缀结束位置: int = 后缀开始位置 + 1
			var 嵌套括号深度: int = 0
			while 后缀结束位置 < 核心类型定义.length():
				var 当前字符2: String = 核心类型定义[后缀结束位置]
				if 当前字符2 == "(":
					嵌套括号深度 += 1
				elif 当前字符2 == ")":
					嵌套括号深度 -= 1
				elif 当前字符2 == "#" and 嵌套括号深度 == 0:
					break
				后缀结束位置 += 1
			var 后缀内容: String = 核心类型定义.substr(后缀开始位置, 后缀结束位置 - 后缀开始位置)
			var 小写后缀内容: String = 后缀内容.to_lower()
			if 小写后缀内容.begins_with("#def(") and 后缀内容.ends_with(")"):
				var 默认值内容: String = 后缀内容.substr(5, 后缀内容.length()-6)
				默认值 = 默认值内容
				核心类型定义 = 核心类型定义.erase(后缀开始位置, 后缀结束位置-后缀开始位置)
			elif 小写后缀内容.begins_with("#sep(") and 后缀内容.ends_with(")"):
				var 分隔符内容: String = 后缀内容.substr(5, 后缀内容.length()-6)
				分隔符 = 分隔符内容
				核心类型定义 = 核心类型定义.erase(后缀开始位置, 后缀结束位置-后缀开始位置)
			else:
				break
			后缀开始位置 = 核心类型定义.find("#")
		else:
			后缀开始位置 = 核心类型定义.find("#", 后缀开始位置 + 1)
	
	核心类型定义 = 核心类型定义.strip_edges()
	if 核心类型定义.is_empty():
		return null
	
	# 联合类型 A|B|C：这一处可以填其中任意一种类型的值（写进 list 里就能穿插着配）。
	# 只看括号外的 | —— list(A|B) 里的 | 属于 list 内部，不能当成顶层联合来切
	var 类型描述字典: Dictionary = {}
	var 顶层候选数组: Array = _分割字符串忽略括号(核心类型定义, "|")
	if 顶层候选数组.size() > 1:
		var 候选描述数组: Array = []
		for 候选字符串: String in 顶层候选数组:
			var 候选描述: Variant = _解析类型定义(候选字符串)
			if 候选描述 == null:
				return null
			候选描述数组.append(候选描述)
		类型描述字典["类型"] = "union"
		类型描述字典["候选类型"] = 候选描述数组
		# 元素之间统一用分号（元组内字段才用逗号），可用 #sep(...) 覆盖
		if 分隔符 == null:
			类型描述字典["分隔符"] = ";"
		return 类型描述字典
	
	var 小写核心: String = 核心类型定义.to_lower()
	
	if 小写核心 in ["int", "float", "string", "bool", "time"]:
		类型描述字典["类型"] = 小写核心
	elif 小写核心 in ["vector2", "vector3", "vector4", "color"]:
		类型描述字典["类型"] = 小写核心
	elif 小写核心.begins_with("list(") and 核心类型定义.ends_with(")"):
		类型描述字典["类型"] = "list"
		var 列表内部内容: Variant = _提取括号内部内容(核心类型定义)
		if 列表内部内容 == null:
			return null
		var 子类型字符串数组: Array = _分割字符串忽略括号(列表内部内容, ",")
		var 子类型描述数组: Array = []
		for 子类型字符串 in 子类型字符串数组:
			var 子类型描述: Variant = _解析类型定义(子类型字符串)
			if 子类型描述 == null:
				return null
			子类型描述数组.append(子类型描述)
		类型描述字典["子类型"] = 子类型描述数组
		# 默认分隔符：元素之间统一用分号（元组内字段固定用逗号），可用 #sep(...) 覆盖
		if 分隔符 == null:
			类型描述字典["分隔符"] = ";"
	elif 小写核心.begins_with("enum(") and 核心类型定义.ends_with(")"):
		类型描述字典["类型"] = "enum"
		var 枚举内部内容: Variant = _提取括号内部内容(核心类型定义)
		if 枚举内部内容 == null:
			return null
		var 枚举映射字典: Dictionary = {}
		var 键值对数组: Array = _分割字符串忽略括号(枚举内部内容, ",")
		for 键值对 in 键值对数组:
			var 分割结果: Array = 键值对.split(":", false)
			if 分割结果.size() != 2:
				return null
			var 键: String = 分割结果[0].strip_edges()
			var 值字符串: String = 分割结果[1].strip_edges()
			if 值字符串.is_valid_int():
				枚举映射字典[键] = 值字符串.to_int()
			else:
				枚举映射字典[键] = 值字符串
		类型描述字典["枚举映射"] = 枚举映射字典
	else:
		类型描述字典["类型"] = 核心类型定义
	
	if 默认值 != null:
		类型描述字典["默认值"] = 默认值
	if 分隔符 != null:
		类型描述字典["分隔符"] = 分隔符
	
	return 类型描述字典

func _提取括号内部内容(完整字符串: String) -> Variant:
	var 开始位置: int = 完整字符串.find("(") + 1
	var 结束位置: int = 完整字符串.rfind(")")
	if 开始位置 <= 0 or 结束位置 <= 开始位置:
		return null
	return 完整字符串.substr(开始位置, 结束位置-开始位置)

# ==================== 时间校验 ====================
func _是否为合法时间(字符串: String) -> bool:
	var 待检查: String = 字符串.strip_edges()
	if 待检查.is_empty():
		return false
	
	var 正则: RegEx = RegEx.new()
	var 模式: String = "^(\\d{4})[-/](\\d{1,2})[-/](\\d{1,2})(?:[ T](\\d{1,2}):(\\d{1,2})(?::(\\d{1,2}))?)?$"
	正则.compile(模式)
	
	var 匹配: RegExMatch = 正则.search(待检查)
	if not 匹配:
		return false
	
	var 组: Array = 匹配.get_strings()
	var 年: int = int(组[1])
	var 月: int = int(组[2])
	var 日: int = int(组[3])
	var 时: int = 0
	var 分: int = 0
	var 秒: int = 0
	var 有时间: bool = 组.size() >= 5 and 组[4] != null and 组[4] != ""
	if 有时间:
		时 = int(组[4])
		分 = int(组[5])
		if 组.size() >= 7 and 组[6] != null and 组[6] != "":
			秒 = int(组[6])
	
	if 月 < 1 or 月 > 12:
		return false
	var 该月最大天数: Array = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	var 是闰年: bool = (年 % 4 == 0 and 年 % 100 != 0) or (年 % 400 == 0)
	if 是闰年:
		该月最大天数[2] = 29
	if 日 < 1 or 日 > 该月最大天数[月]:
		return false
	if 有时间:
		if 时 < 0 or 时 > 23:
			return false
		if 分 < 0 or 分 > 59:
			return false
		if 秒 < 0 or 秒 > 59:
			return false
	return true

# ==================== Vector/Color 辅助函数 ====================
func _解析向量字符串(字符串: String, 预期数量: int, 分隔符: String) -> Variant:
	var 待处理: String = 字符串.strip_edges()
	if 待处理.is_empty():
		return null
	
	if 待处理.begins_with("(") and 待处理.ends_with(")"):
		待处理 = 待处理.substr(1, 待处理.length() - 2)
	
	var 部分数组: Array = 待处理.split(分隔符)
	if 预期数量 != -1 and 部分数组.size() != 预期数量:
		return null
	
	var 数字数组: Array = []
	for 部分 in 部分数组:
		var 数字: float = 部分.strip_edges().to_float()
		数字数组.append(数字)
	return 数字数组

func _校验向量(值: String, 预期数量: int, 分隔符: String, 文件路径: String, 行号: int, 列名称: String) -> String:
	var 数字数组: Variant = _解析向量字符串(值, 预期数量, 分隔符)
	if 数字数组 == null:
		return "[错误] %s 第%d行, 列'%s': 值'%s'不是合法的%d维向量" % [文件路径, 行号, 列名称, 值, 预期数量]
	return ""

func _转换向量(值: String, 类型: String, 分隔符: String) -> Variant:
	var 数字数组: Variant = _解析向量字符串(值, -1, 分隔符)
	if 数字数组 == null:
		return null
	match 类型:
		"vector2":
			if 数字数组.size() >= 2:
				return Vector2(数字数组[0], 数字数组[1])
		"vector3":
			if 数字数组.size() >= 3:
				return Vector3(数字数组[0], 数字数组[1], 数字数组[2])
		"vector4":
			if 数字数组.size() >= 4:
				return Vector4(数字数组[0], 数字数组[1], 数字数组[2], 数字数组[3])
	return null

func _校验颜色(值: String, 文件路径: String, 行号: int, 列名称: String) -> String:
	var 待检查: String = 值.strip_edges()
	if 待检查.is_empty():
		return ""
	var 正则16进制: RegEx = RegEx.new()
	正则16进制.compile("^#([A-Fa-f0-9]{3}|[A-Fa-f0-9]{4}|[A-Fa-f0-9]{6}|[A-Fa-f0-9]{8})$")
	if 正则16进制.search(待检查):
		return ""
	var 正则函数: RegEx = RegEx.new()
	正则函数.compile("^rgba?\\((\\d{1,3}),\\s*(\\d{1,3}),\\s*(\\d{1,3})(?:,\\s*(\\d{1,3}))?\\)$")
	var 匹配: RegExMatch = 正则函数.search(待检查)
	if 匹配:
		var 组: Array = 匹配.get_strings()
		var r: int = 组[1].to_int()
		var g: int = 组[2].to_int()
		var b: int = 组[3].to_int()
		var a: int = 255
		if 组.size() >= 5 and 组[4] != null:
			a = 组[4].to_int()
		if r < 0 or r > 255 or g < 0 or g > 255 or b < 0 or b > 255 or a < 0 or a > 255:
			return "[错误] %s 第%d行, 列'%s': 颜色分量超出0-255范围" % [文件路径, 行号, 列名称]
		return ""
	return "[错误] %s 第%d行, 列'%s': 值'%s'不是合法颜色（支持#RGB/#RRGGBB或rgb/rgba函数）" % [文件路径, 行号, 列名称, 值]

func _转换颜色(值: String) -> Variant:
	var 待检查: String = 值.strip_edges()
	if 待检查.is_empty():
		return null
	if 待检查.begins_with("#"):
		var 十六进制: String = 待检查.substr(1)
		var 颜色: Color = Color()
		match 十六进制.length():
			3:  # RGB
				颜色.r = (十六进制[0] + 十六进制[0]).hex_to_int() / 255.0
				颜色.g = (十六进制[1] + 十六进制[1]).hex_to_int() / 255.0
				颜色.b = (十六进制[2] + 十六进制[2]).hex_to_int() / 255.0
				颜色.a = 1.0
			4:  # RGBA
				颜色.r = (十六进制[0] + 十六进制[0]).hex_to_int() / 255.0
				颜色.g = (十六进制[1] + 十六进制[1]).hex_to_int() / 255.0
				颜色.b = (十六进制[2] + 十六进制[2]).hex_to_int() / 255.0
				颜色.a = (十六进制[3] + 十六进制[3]).hex_to_int() / 255.0
			6:  # RRGGBB
				颜色 = Color(待检查)
			8:  # RRGGBBAA
				颜色 = Color(待检查)
		return 颜色
	var 正则函数: RegEx = RegEx.new()
	正则函数.compile("^rgba?\\((\\d{1,3}),\\s*(\\d{1,3}),\\s*(\\d{1,3})(?:,\\s*(\\d{1,3}))?\\)$")
	var 匹配: RegExMatch = 正则函数.search(待检查)
	if 匹配:
		var 组: Array = 匹配.get_strings()
		var r: int = 组[1].to_int()
		var g: int = 组[2].to_int()
		var b: int = 组[3].to_int()
		var a: int = 255
		if 组.size() >= 5 and 组[4] != null:
			a = 组[4].to_int()
		return Color(r/255.0, g/255.0, b/255.0, a/255.0)
	return null

# ==================== 结构解析 ====================
func _解析所有CSV文件结构(CSV文件路径列表: Array[String]) -> Array[String]:
	var 错误信息列表: Array[String] = []
	
	for 文件路径 in CSV文件路径列表:
		var 表名称: String = 文件路径.get_file().get_basename()
		var 文件内容数组: Array = _读取CSV文件内容(文件路径)
		
		if 文件内容数组.is_empty():
			错误信息列表.append("[错误] 文件 %s 为空或无法读取" % 文件路径)
			continue
		
		if 文件内容数组.size() < 3:
			错误信息列表.append("[错误] %s 行数不足3行" % 文件路径)
			continue
		
		var 原始列名行: Array = _分割CSV行数据(文件内容数组[0])
		var 原始类型定义行: Array = _分割类型定义行(文件内容数组[2])
		
		while 原始类型定义行.size() < 原始列名行.size():
			原始类型定义行.append("")
		
		var 需要忽略的列索引列表: Array[int] = []
		for 索引 in range(原始列名行.size()):
			if 原始列名行[索引].strip_edges().is_empty() or 原始类型定义行[索引].strip_edges() == "不导出":
				需要忽略的列索引列表.append(索引)
		
		var 列名数组: Array[String] = []
		var 类型定义数组: Array[String] = []
		for 索引 in range(原始列名行.size()):
			if 索引 in 需要忽略的列索引列表:
				continue
			列名数组.append(原始列名行[索引])
			类型定义数组.append(原始类型定义行[索引])
		
		if 列名数组.size() != 类型定义数组.size():
			错误信息列表.append("[错误] %s 过滤后列名行与数据类型行列数不一致" % 文件路径)
			continue
		
		var ID列索引: int = 列名数组.find("id")
		if ID列索引 == -1:
			错误信息列表.append("[错误] %s 缺少id列" % 文件路径)
			continue
		
		var 类型描述数组: Array = []
		var 是否解析失败: bool = false
		for 索引 in range(类型定义数组.size()):
			var 类型定义字符串: String = 类型定义数组[索引]
			if 类型定义字符串.strip_edges().is_empty():
				错误信息列表.append("[错误] %s 第3行, 列'%s': 数据类型不能为空" % [文件路径, 列名数组[索引]])
				是否解析失败 = true
				break
			
			var 类型描述字典: Dictionary = _解析类型定义(类型定义字符串)
			if 类型描述字典 == null:
				错误信息列表.append("[错误] %s 第3行, 列'%s': 数据类型语法错误" % [文件路径, 列名数组[索引]])
				是否解析失败 = true
				break
			
			类型描述数组.append(类型描述字典)
		
		if 是否解析失败:
			continue
		
		var 数据行数组: Array = 文件内容数组.slice(3)
		
		var 是否是多行表: bool = false
		var 上一行ID: String = ""
		for 行号 in range(数据行数组.size()):
			var 原始行数据: String = 数据行数组[行号]
			if _检测是否全空行(原始行数据, 需要忽略的列索引列表):
				continue
			
			var 原始单元格数组: Array = _分割CSV行数据(原始行数据)
			var 过滤后单元格数组: Array = _过滤单元格数组(原始单元格数组, 需要忽略的列索引列表)
			var 当前行ID: String = 过滤后单元格数组[ID列索引] if ID列索引 < 过滤后单元格数组.size() else ""
			
			if 上一行ID != "" and 当前行ID.is_empty():
				是否是多行表 = true
				break
			
			上一行ID = 当前行ID
		
		var 所有ID列表: Array = []
		var 当前实体ID: String = ""
		
		for 行号 in range(数据行数组.size()):
			var 原始行数据: String = 数据行数组[行号]
			if _检测是否全空行(原始行数据, 需要忽略的列索引列表):
				continue
			
			var 原始单元格数组: Array = _分割CSV行数据(原始行数据)
			var 过滤后单元格数组: Array = _过滤单元格数组(原始单元格数组, 需要忽略的列索引列表)
			var 当前行ID: String = 过滤后单元格数组[ID列索引] if ID列索引 < 过滤后单元格数组.size() else ""
			
			if 是否是多行表:
				if 当前行ID.is_empty():
					if 当前实体ID != "":
						所有ID列表.append(当前实体ID)
				else:
					当前实体ID = 当前行ID
					所有ID列表.append(当前实体ID)
			else:
				if 当前行ID.is_empty():
					错误信息列表.append("[错误] %s 第%d行: 单行表id不能为空" % [文件路径, 行号+4])
				else:
					所有ID列表.append(当前行ID)
		
		var 唯一ID列表 = []
		for ID值 in 所有ID列表:
			if not 唯一ID列表.has(ID值):
				唯一ID列表.append(ID值)
		
		if not 是否是多行表 and 所有ID列表.size() > 唯一ID列表.size():
			错误信息列表.append("[错误] %s 单行表中存在重复ID，跳过该文件" % 文件路径)
			continue
		
		_表信息数据库[表名称] = {
			"文件路径": 文件路径,
			"列名数组": 列名数组,
			"类型描述数组": 类型描述数组,
			"ID列索引": ID列索引,
			"是否是多行表": 是否是多行表,
			"唯一ID列表": 唯一ID列表,
			"数据行数组": 数据行数组,
			"需要忽略的列索引列表": 需要忽略的列索引列表
		}
		
		for ID值 in 唯一ID列表:
			if _全局ID表.has(ID值):
				错误信息列表.append("[错误] ID '%s' 在多个表中重复 (表: %s, %s)" % [ID值, _全局ID表[ID值], 表名称])
			else:
				_全局ID表[ID值] = 表名称
	
	return 错误信息列表

# ==================== 数据完整性校验 ====================
func _校验所有表数据完整性() -> Array[String]:
	var 错误信息列表: Array[String] = []
	var 有问题的表: Array[String] = []
	
	for 表名称 in _表信息数据库:
		var 表信息 = _表信息数据库[表名称]
		var 文件路径 = 表信息["文件路径"]
		var 列名数组 = 表信息["列名数组"]
		var 类型描述数组 = 表信息["类型描述数组"]
		var ID列索引 = 表信息["ID列索引"]
		var 是否是多行表 = 表信息["是否是多行表"]
		var 数据行数组 = 表信息["数据行数组"]
		var 需要忽略的列索引列表 = 表信息["需要忽略的列索引列表"]
		var 列数 = 列名数组.size()
		
		# 优化：预构建需要忽略的列索引字典
		var 需要忽略的列索引字典: Dictionary = {}
		for 索引 in 需要忽略的列索引列表:
			需要忽略的列索引字典[索引] = true
		
		var 数据行分组结果 = []
		
		if 是否是多行表:
			var 当前实体行组 = []
			var 当前实体ID = ""
			
			for 行号 in range(数据行数组.size()):
				var 原始行数据 = 数据行数组[行号]
				
				# 内联 _检测是否全空行 逻辑
				var 是全空行 = true
				var 原始单元格数组 = _分割CSV行数据(原始行数据)
				for 索引 in range(原始单元格数组.size()):
					if not 需要忽略的列索引字典.has(索引) and not 原始单元格数组[索引].strip_edges().is_empty():
						是全空行 = false
						break
				
				if 是全空行:
					if 当前实体行组.size() > 0:
						数据行分组结果.append({"id": 当前实体ID, "行组": 当前实体行组})
						当前实体行组 = []
						当前实体ID = ""
					continue
				
				# 内联 _过滤单元格数组 逻辑
				var 过滤后单元格数组 = []
				for 索引 in range(原始单元格数组.size()):
					if not 需要忽略的列索引字典.has(索引):
						过滤后单元格数组.append(原始单元格数组[索引].strip_edges())
				
				var 当前行ID = 过滤后单元格数组[ID列索引] if ID列索引 < 过滤后单元格数组.size() else ""
				
				if 当前行ID.is_empty():
					if 当前实体ID != "":
						当前实体行组.append({
							"原始行数据": 原始行数据,
							"过滤后单元格数组": 过滤后单元格数组,
							"原始行号": 行号
						})
				else:
					if 当前实体行组.size() > 0:
						数据行分组结果.append({"id": 当前实体ID, "行组": 当前实体行组})
					当前实体ID = 当前行ID
					当前实体行组 = [{
						"原始行数据": 原始行数据,
						"过滤后单元格数组": 过滤后单元格数组,
						"原始行号": 行号
					}]
			
			if 当前实体行组.size() > 0:
				数据行分组结果.append({"id": 当前实体ID, "行组": 当前实体行组})
		else:
			for 行号 in range(数据行数组.size()):
				var 原始行数据 = 数据行数组[行号]
				
				# 内联 _检测是否全空行 逻辑
				var 是全空行 = true
				var 原始单元格数组 = _分割CSV行数据(原始行数据)
				for 索引 in range(原始单元格数组.size()):
					if not 需要忽略的列索引字典.has(索引) and not 原始单元格数组[索引].strip_edges().is_empty():
						是全空行 = false
						break
				
				if 是全空行:
					continue
				
				# 内联 _过滤单元格数组 逻辑
				var 过滤后单元格数组 = []
				for 索引 in range(原始单元格数组.size()):
					if not 需要忽略的列索引字典.has(索引):
						过滤后单元格数组.append(原始单元格数组[索引].strip_edges())
				
				var 当前行ID = 过滤后单元格数组[ID列索引] if ID列索引 < 过滤后单元格数组.size() else ""
				
				if 当前行ID.is_empty():
					错误信息列表.append("[错误] %s 第%d行: 单行表id不能为空" % [文件路径, 行号+4])
				else:
					数据行分组结果.append({"id": 当前行ID, "行组": [{
						"原始行数据": 原始行数据,
						"过滤后单元格数组": 过滤后单元格数组,
						"原始行号": 行号
					}]})
		
		var 表有错误 = false
		for 实体 in 数据行分组结果:
			var 实体ID = 实体["id"]
			var 实体行组 = 实体["行组"]
			
			for 行组索引 in range(实体行组.size()):
				var 行数据对象 = 实体行组[行组索引]
				var 过滤后单元格数组 = 行数据对象["过滤后单元格数组"]
				var 原始行号 = 行数据对象["原始行号"]
				
				var 实际列数 = 过滤后单元格数组.size()
				var 定义列数 = 列名数组.size()
				
				if 实际列数 != 定义列数:
					错误信息列表.append("[错误] %s 第%d行: 列数不匹配, 实际%d列, 应为%d列" % [文件路径, 原始行号+4, 实际列数, 定义列数])
					表有错误 = true
					continue
				
				var 当前行ID = 过滤后单元格数组[ID列索引] if ID列索引 < 过滤后单元格数组.size() else ""
				var 是否为延续行 = (当前行ID.is_empty() and 是否是多行表)
				
				for 列索引 in range(定义列数):
					var 列名称 = 列名数组[列索引]
					if 是否为延续行 and 列索引 == ID列索引:
						continue
					
					var 类型描述字典 = 类型描述数组[列索引]
					var 原始单元格值 = 过滤后单元格数组[列索引]
					
					# 内联 _校验单个单元格值 逻辑的核心部分
					if 原始单元格值.is_empty():
						if 类型描述字典.has("必填") and 类型描述字典["必填"]:
							错误信息列表.append("[错误] %s 第%d行: 列 '%s' 不能为空" % [文件路径, 原始行号+4, 列名称])
							表有错误 = true
						else:
							# 空值跳过类型校验
							continue
					else:
						# 这里可以保留对复杂类型的校验，或者根据需要内联更多逻辑
						var 校验错误 = _校验单个单元格值(
							原始单元格值, 类型描述字典, 实体ID, 表名称, 
							文件路径, 原始行号+4, 列名称
						)
						if 校验错误 != "":
							错误信息列表.append(校验错误)
							表有错误 = true
		
		if 表有错误:
			有问题的表.append(表名称)
	
	# 移除有问题的表
	for 表名称 in 有问题的表:
		_表信息数据库.erase(表名称)
	
	return 错误信息列表

func _校验单个单元格值(
	原始值: String, 类型描述: Dictionary, 实体ID: String, 
	当前表名称: String, 文件路径: String, 行号: int, 列名称: String) -> String:
	
	var 单元格值 = 原始值
	
	if 单元格值.is_empty():
		if 类型描述.has("默认值"):
			单元格值 = 类型描述["默认值"]
		else:
			return ""
	
	var 单元格类型 = 类型描述["类型"]
	
	match 单元格类型:
		"int", "float", "string", "bool", "time":
			match 单元格类型:
				"int":
					return "" if 单元格值.is_valid_int() else "[错误] %s 第%d行, 列'%s': 值'%s'不是整数" % [文件路径, 行号, 列名称, 单元格值]
				"float":
					return "" if 单元格值.is_valid_float() else "[错误] %s 第%d行, 列'%s': 值'%s'不是浮点数" % [文件路径, 行号, 列名称, 单元格值]
				"string":
					return ""
				"bool":
					var 小写值 = 单元格值.to_lower()
					if 小写值 in ["true", "false", "1", "0", "是", "否", "真", "假", "yes", "no"]:
						return ""
					else:
						return "[错误] %s 第%d行, 列'%s': 值'%s'不是布尔值" % [文件路径, 行号, 列名称, 单元格值]
				"time":
					if 单元格值.is_empty():
						return ""
					if _是否为合法时间(单元格值):
						return ""
					else:
						return "[错误] %s 第%d行, 列'%s': 值'%s'不是合法时间" % [文件路径, 行号, 列名称, 单元格值]
		"vector2", "vector3", "vector4":
			var 预期数量 = 2 if 单元格类型 == "vector2" else (3 if 单元格类型 == "vector3" else 4)
			var 分隔符 = 类型描述.get("分隔符", ";")
			var 错误 = _校验向量(单元格值, 预期数量, 分隔符, 文件路径, 行号, 列名称)
			if 错误 != "":
				return 错误
			return ""
		"color":
			var 错误 = _校验颜色(单元格值, 文件路径, 行号, 列名称)
			if 错误 != "":
				return 错误
			return ""
		"list":
			var 子类型数组 = 类型描述["子类型"]  # 元组字段类型
			var 外层分隔符 = 类型描述.get("分隔符", ";")  # 默认分号分隔顶层元组
			var 内层分隔符 = ","  # 固定逗号分隔元组内字段
			
			# 空列表允许
			if 单元格值.is_empty():
				return ""
			
			# 分割顶层元组
			var 顶层元素数组 = _分割字符串忽略括号(单元格值, 外层分隔符)
			
			# 只写了一个子类型（含联合类型）：每个元素就是一个值，逐个按该子类型校验
			if 子类型数组.size() == 1:
				for 元素索引 in range(顶层元素数组.size()):
					var 元素错误 = _校验单个单元格值(
						顶层元素数组[元素索引].strip_edges(), 子类型数组[0], 实体ID,
						当前表名称, 文件路径, 行号,
						"%s[%d]" % [列名称, 元素索引]
					)
					if 元素错误:
						return 元素错误
				return ""
			
			# 遍历每个顶层元素（每个元素应是一个元组）
			for 元组索引 in range(顶层元素数组.size()):
				var 元组字符串 = 顶层元素数组[元组索引].strip_edges()
				# 分割元组内的字段
				var 字段数组 = 元组字符串.split(内层分隔符)
				if 字段数组.size() != 子类型数组.size():
					return "[错误] %s 第%d行, 列'%s': 第%d个元组元素字段个数不符, 预期%d个, 实际%d个" % [文件路径, 行号, 列名称, 元组索引+1, 子类型数组.size(), 字段数组.size()]
				
				# 校验每个字段
				for 字段索引 in range(字段数组.size()):
					var 字段值 = 字段数组[字段索引].strip_edges()
					var 子类型描述 = 子类型数组[字段索引]
					var 子错误 = _校验单个单元格值(
						字段值, 子类型描述, 实体ID, 
						当前表名称, 文件路径, 行号, 
						"%s[%d][%d]" % [列名称, 元组索引, 字段索引]
					)
					if 子错误:
						return 子错误
			return ""
		"enum":
			var 枚举映射字典 = 类型描述["枚举映射"]
			# 允许单元格填写键或值
			var 匹配值 = null
			# 检查是否匹配键
			if 单元格值 in 枚举映射字典:
				匹配值 = 枚举映射字典[单元格值]
			else:
				# 检查是否匹配值（转为字符串比较）
				for 键 in 枚举映射字典:
					if str(枚举映射字典[键]) == 单元格值:
						匹配值 = 枚举映射字典[键]
						break
			if 匹配值 != null:
				return ""
			else:
				var 选项字符串数组 = []
				for 键 in 枚举映射字典:
					选项字符串数组.append("%s:%s" % [键, 枚举映射字典[键]])
				return "[错误] %s 第%d行, 列'%s': 值'%s'不在枚举选项[%s]中" % [文件路径, 行号, 列名称, 单元格值, ",".join(选项字符串数组)]
		"union":
			var 候选类型数组 = 类型描述["候选类型"]
			for 候选类型 in 候选类型数组:
				var 候选错误 = _校验单个单元格值(
					单元格值, 候选类型, 实体ID,
					当前表名称, 文件路径, 行号, 列名称
				)
				if 候选错误.is_empty():
					return ""
			return "[错误] %s 第%d行, 列'%s': 值'%s'不属于联合类型中的任何一种" % [文件路径, 行号, 列名称, 单元格值]
		_:
			if 单元格值.is_empty():
				return ""
			var 引用表名 = 单元格类型
			var 表存在 = false
			var 实际表名 = ""
			for 已有表名 in _表信息数据库:
				if 已有表名.to_lower() == 引用表名.to_lower():
					表存在 = true
					实际表名 = 已有表名
					break
			if not 表存在:
				return "[错误] %s 第%d行, 列'%s': 引用的表'%s'不存在" % [文件路径, 行号, 列名称, 引用表名]
			var 目标表信息 = _表信息数据库[实际表名]
			if not 目标表信息["唯一ID列表"].has(单元格值):
				return "[错误] %s 第%d行, 列'%s': 引用的ID'%s'在表'%s'中不存在" % [文件路径, 行号, 列名称, 单元格值, 实际表名]
			return ""
	
	return ""

# ==================== 实体分组 ====================
func _获取表实体列表(表信息: Dictionary) -> Array:
	var 数据行数组 = 表信息["数据行数组"]
	var ID列索引 = 表信息["ID列索引"]
	var 是否是多行表 = 表信息["是否是多行表"]
	var 需要忽略的列索引列表 = 表信息["需要忽略的列索引列表"]
	
	var 实体分组结果 = []
	
	if 是否是多行表:
		var 当前实体行组 = []
		var 当前实体ID = ""
		
		for 行号 in range(数据行数组.size()):
			var 原始行数据 = 数据行数组[行号]
			
			if _检测是否全空行(原始行数据, 需要忽略的列索引列表):
				if 当前实体行组.size() > 0:
					实体分组结果.append({"id": 当前实体ID, "行组": 当前实体行组})
					当前实体行组 = []
					当前实体ID = ""
				continue
			
			var 原始单元格数组 = _分割CSV行数据(原始行数据)
			var 过滤后单元格数组 = _过滤单元格数组(原始单元格数组, 需要忽略的列索引列表)
			var 当前行ID = 过滤后单元格数组[ID列索引] if ID列索引 < 过滤后单元格数组.size() else ""
			
			if 当前行ID.is_empty():
				if 当前实体ID != "":
					当前实体行组.append({
						"原始行数据": 原始行数据,
						"过滤后单元格数组": 过滤后单元格数组
					})
			else:
				if 当前实体行组.size() > 0:
					实体分组结果.append({"id": 当前实体ID, "行组": 当前实体行组})
				当前实体ID = 当前行ID
				当前实体行组 = [{
					"原始行数据": 原始行数据,
					"过滤后单元格数组": 过滤后单元格数组
				}]
		
		if 当前实体行组.size() > 0:
			实体分组结果.append({"id": 当前实体ID, "行组": 当前实体行组})
	else:
		for 行号 in range(数据行数组.size()):
			var 原始行数据 = 数据行数组[行号]
			if _检测是否全空行(原始行数据, 需要忽略的列索引列表):
				continue
			
			var 原始单元格数组 = _分割CSV行数据(原始行数据)
			var 过滤后单元格数组 = _过滤单元格数组(原始单元格数组, 需要忽略的列索引列表)
			var 当前行ID = 过滤后单元格数组[ID列索引] if ID列索引 < 过滤后单元格数组.size() else ""
			
			if 当前行ID != "":
				实体分组结果.append({
					"id": 当前行ID, 
					"行组": [{
						"原始行数据": 原始行数据,
						"过滤后单元格数组": 过滤后单元格数组
					}]
				})
	
	return 实体分组结果

# ==================== 值转换 ====================
func _转换单元格值为GDScript值(原始值: String, 类型描述: Dictionary) -> Variant:
	var 转换值 = 原始值
	if 转换值.is_empty() and 类型描述.has("默认值"):
		转换值 = 类型描述["默认值"]
	
	var 值类型 = 类型描述["类型"]
	var 结果: Variant
	
	match 值类型:
		"int":
			结果 = int(转换值) if 转换值.is_valid_int() else 0
		"float":
			结果 = float(转换值) if 转换值.is_valid_float() else 0.0
		"string":
			结果 = 转换值
		"bool":
			var 小写值 = 转换值.to_lower()
			match 小写值:
				"true", "1", "是", "真", "yes":
					结果 = true
				"false", "0", "否", "假", "no":
					结果 = false
				_:
					结果 = false
		"time":
			结果 = 转换值
		"vector2":
			var 分隔符 = 类型描述.get("分隔符", ";")
			var 向量 = _转换向量(转换值, "vector2", 分隔符)
			结果 = Vector2() if 向量 == null else 向量
		"vector3":
			var 分隔符 = 类型描述.get("分隔符", ";")
			var 向量 = _转换向量(转换值, "vector3", 分隔符)
			结果 = Vector3() if 向量 == null else 向量
		"vector4":
			var 分隔符 = 类型描述.get("分隔符", ";")
			var 向量 = _转换向量(转换值, "vector4", 分隔符)
			结果 = Vector4() if 向量 == null else 向量
		"color":
			var 颜色 = _转换颜色(转换值)
			结果 = 颜色 if 颜色 != null else Color()
		"list":
			var 子类型数组 = 类型描述["子类型"]
			var 外层分隔符 = 类型描述.get("分隔符", ";")
			var 内层分隔符 = ","
			
			if 转换值.is_empty():
				结果 = []
			else:
				var 顶层元素数组 = _分割字符串忽略括号(转换值, 外层分隔符)
				var 转换结果数组 = []
				
				# 只写了一个子类型（含联合类型）：每个元素就是一个值，不再拆“元组内字段”
				if 子类型数组.size() == 1:
					for 元素字符串 in 顶层元素数组:
						var 元素值 = _转换单元格值为GDScript值(元素字符串.strip_edges(), 子类型数组[0])
						转换结果数组.append([元素值])
				else:
					for 元组字符串 in 顶层元素数组:
						var 处理后字符串 = 元组字符串.strip_edges()
						var 字段数组 = 处理后字符串.split(内层分隔符)
						var 元组值数组 = []
						for 字段索引 in range(字段数组.size()):
							var 字段值 = 字段数组[字段索引].strip_edges()
							var 子类型描述 = 子类型数组[字段索引]
							元组值数组.append(_转换单元格值为GDScript值(字段值, 子类型描述))
						转换结果数组.append(元组值数组)
				结果 = 转换结果数组
		"enum":
			var 枚举映射字典 = 类型描述["枚举映射"]
			if 转换值 in 枚举映射字典:
				结果 = 枚举映射字典[转换值]
			else:
				var 找到 = false
				for 键 in 枚举映射字典:
					if str(枚举映射字典[键]) == 转换值:
						结果 = 枚举映射字典[键]
						找到 = true
						break
				if not 找到:
					结果 = 转换值
		_:
			结果 = 转换值
	
	return 结果

# ==================== 生成数据表格脚本 ====================
func _生成数据表格脚本() -> String:
	var 脚本内容缓冲区: PackedStringArray = PackedStringArray()
	# @tool：纯数据脚本，编辑器里也需要读取其静态变量（如怪物图集生成），无副作用
	脚本内容缓冲区.append("@tool\n")
	脚本内容缓冲区.append("class_name 数据表格\n")
	脚本内容缓冲区.append("# 自动生成的数据表格，请勿手动修改\n")
	脚本内容缓冲区.append("# 生成时间: %s\n" % Time.get_datetime_string_from_system(false, true))
	
	# 1. 生成枚举定义
	var 枚举定义代码: String = _生成枚举定义代码()
	if not 枚举定义代码.is_empty():
		脚本内容缓冲区.append("\n")
		脚本内容缓冲区.append(枚举定义代码)
	
	var 表名称列表: Array = _表信息数据库.keys()
	表名称列表.sort()
	var 表元数据条目: Array = []
	var 表数据缓冲区: PackedStringArray = PackedStringArray()
	var 重新生成的表数: int = 0
	var 从缓存读取的表数: int = 0
	var 重新生成的表名列表: Array[String] = []
	var 从缓存读取的表名列表: Array[String] = []
	
	# 2. 收集表数据和元数据
	for 表名称 in 表名称列表:
		var 表信息: Dictionary = _表信息数据库[表名称]
		
		if _检查表是否需要重新生成(表名称, 表信息):
			var 结果: Dictionary = _生成单个表(表名称, 表信息)
			表数据缓冲区.append(结果["脚本代码"])
			表元数据条目.append(结果)
			_保存表缓存代码(表名称, 结果["脚本代码"], 表信息["文件路径"])
			重新生成的表数 += 1
			重新生成的表名列表.append(表名称)
		else:
			var 缓存代码: String = _获取表缓存代码(表名称)
			if not 缓存代码.is_empty():
				表数据缓冲区.append(缓存代码)
				从缓存读取的表数 += 1
				从缓存读取的表名列表.append(表名称)
				# 重新生成元数据条目（列索引不含 id 列，id 由字典键提供，索引为去除 id 列后的新索引）
				var 列索引字典: Dictionary = {}
				var 列名数组: Array = 表信息["列名数组"]
				var 类型描述数组: Array = 表信息["类型描述数组"]
				var 新索引: int = 0
				for 索引 in range(列名数组.size()):
					if 列名数组[索引] == "id":
						continue
					列索引字典[列名数组[索引]] = 新索引
					新索引 += 1
				var 列索引字典字符串: String = _列索引转GDScript字符串(列索引字典)
				var 表变量名: String = _生成合法变量名(表名称)
				var 是否是多行表: bool = 表信息["是否是多行表"]
				表元数据条目.append({
					"表名称": 表名称,
					"变量名": 表变量名,
					"脚本代码": 缓存代码,
					"列索引": 列索引字典字符串,
					"是否多行": "true" if 是否是多行表 else "false"
				})
			else:
				var 结果: Dictionary = _生成单个表(表名称, 表信息)
				表数据缓冲区.append(结果["脚本代码"])
				表元数据条目.append(结果)
				_保存表缓存代码(表名称, 结果["脚本代码"], 表信息["文件路径"])
				重新生成的表数 += 1
				重新生成的表名列表.append(表名称)

	var 重生成表名文本: String = "（" + "；".join(重新生成的表名列表) + "）" if not 重新生成的表名列表.is_empty() else ""
	var 缓存表名文本: String = "（" + "；".join(从缓存读取的表名列表) + "）" if not 从缓存读取的表名列表.is_empty() else ""
	print("[增量生成] 重新生成 %d 个表%s，从缓存读取 %d 个表%s" % [重新生成的表数, 重生成表名文本, 从缓存读取的表数, 缓存表名文本])
	
	# 3. 输出表数据
	for 表代码: String in 表数据缓冲区:
		脚本内容缓冲区.append(表代码)
	
	# 4. 输出元数据（必须在表数据之后，因为元数据key引用了static var）
	脚本内容缓冲区.append("\n")
	脚本内容缓冲区.append("static var 表元数据: Dictionary = {\n")
	for 条目 in 表元数据条目:
		脚本内容缓冲区.append("    \"%s\": {\n" % 条目["表名称"])
		脚本内容缓冲区.append("        \"列索引\": %s,\n" % 条目["列索引"])
		脚本内容缓冲区.append("        \"是否多行\": %s\n" % 条目["是否多行"])
		脚本内容缓冲区.append("    },\n")
	脚本内容缓冲区.append("}\n")
	
	return "".join(脚本内容缓冲区)

# 从所有表信息中收集枚举定义，生成GDScript枚举代码
func _生成枚举定义代码() -> String:
	var 枚举集合: Dictionary = {}  # 枚举签名字符串 -> {枚举名称, 映射表, 来源}
	
	for 表名称: String in _表信息数据库:
		var 表信息: Dictionary = _表信息数据库[表名称]
		var 列名数组: Array = 表信息["列名数组"]
		var 类型描述数组: Array = 表信息["类型描述数组"]
		var 表变量名: String = _生成合法变量名(表名称)
		
		for 索引: int in range(列名数组.size()):
			if 索引 >= 类型描述数组.size():
				break
			var 类型描述: Dictionary = 类型描述数组[索引]
			if 类型描述.get("类型", "") != "enum":
				continue
			
			var 列名: String = 列名数组[索引]
			var 枚举映射: Dictionary = 类型描述["枚举映射"]
			var 列变量名: String = _生成合法变量名(列名)
			var 枚举名称: String = "%s_%s" % [表变量名, 列变量名]
			
			# 生成签名字符串用于去重
			var 签名: String = _生成枚举签名字符串(枚举映射)
			if not 枚举集合.has(签名):
				枚举集合[签名] = {"名称": 枚举名称, "映射": 枚举映射}
	
	if 枚举集合.is_empty():
		return ""
	
	var 缓冲区: PackedStringArray = PackedStringArray()
	缓冲区.append("# ====== 枚举定义（由CSV自动生成） ======\n")
	
	for 签名: String in 枚举集合:
		var 条目: Dictionary = 枚举集合[签名]
		var 枚举名称: String = 条目["名称"]
		var 映射: Dictionary = 条目["映射"]
		
		缓冲区.append("enum %s { " % 枚举名称)
		var 键列表: Array = 映射.keys()
		for i: int in range(键列表.size()):
			var 键: String = 键列表[i]
			var 值 = 映射[键]
			var 值字符串: String
			if 值 is int or 值 is float:
				值字符串 = str(值)
			else:
				值字符串 = "\"%s\"" % str(值)
			
			缓冲区.append("%s = %s" % [键, 值字符串])
			if i < 键列表.size() - 1:
				缓冲区.append(", ")
		缓冲区.append(" }\n")
	
	return "".join(缓冲区)

func _生成枚举签名字符串(映射: Dictionary) -> String:
	var 键列表: Array = 映射.keys()
	键列表.sort()
	var 部分: PackedStringArray = PackedStringArray()
	for 键: String in 键列表:
		var 值 = 映射[键]
		部分.append("%s:%s" % [键, str(值)])
	return "|".join(部分)

func _生成单个表(表名称: String, 表信息: Dictionary) -> Dictionary:
	var 实体列表: Array = _获取表实体列表(表信息)
	var 是否是多行表: bool = 表信息["是否是多行表"]
	var 列名数组: Array = 表信息["列名数组"]
	var 需要忽略的列索引列表: Array = 表信息["需要忽略的列索引列表"]
	var 类型描述数组: Array = 表信息["类型描述数组"]
	var 列数: int = 列名数组.size()
	
	var 需要忽略的列索引字典: Dictionary = {}
	for 索引 in 需要忽略的列索引列表:
		需要忽略的列索引字典[索引] = true
	
	# 列索引字典不含 id 列（id 由字典键提供，不再重复存储），索引为去除 id 列后的新索引
	var 列索引字典: Dictionary = {}
	var ID列索引: int = -1
	var 输出列索引: int = 0
	for 索引 in range(列数):
		if 列名数组[索引] == "id":
			ID列索引 = 索引
			continue
		列索引字典[列名数组[索引]] = 输出列索引
		输出列索引 += 1
	var 列索引字典字符串: String = _列索引转GDScript字符串(列索引字典)
	
	var 字典条目列表: PackedStringArray = PackedStringArray()
	
	for 实体 in 实体列表:
		var 实体ID: String = 实体["id"]
		var 实体行组: Array = 实体["行组"]
		
		var 行数组字符串列表: PackedStringArray = PackedStringArray()
		for 行数据 in 实体行组:
			var 原始单元格数组: Array = _分割CSV行数据(行数据["原始行数据"])
			
			var 过滤后单元格数组: Array = []
			for 索引 in range(原始单元格数组.size()):
				if not 需要忽略的列索引字典.has(索引):
					过滤后单元格数组.append(原始单元格数组[索引].strip_edges())
			
			var 行字符串缓冲区: PackedStringArray = PackedStringArray()
			行字符串缓冲区.append("[")
			
			# 跳过 ID 列：ID 由字典键提供，不在行数组中重复存储
			var 已输出列数: int = 0
			for 列索引 in range(列数):
				if 列索引 == ID列索引:
					continue
				if 已输出列数 > 0:
					行字符串缓冲区.append(", ")
				行字符串缓冲区.append(_直接转换单元格为字符串(过滤后单元格数组[列索引], 类型描述数组[列索引]))
				已输出列数 += 1
			
			行字符串缓冲区.append("]")
			行数组字符串列表.append("".join(行字符串缓冲区))
		
		var 值字符串: String
		if 是否是多行表:
			值字符串 = "[\n        " + ",\n        ".join(行数组字符串列表) + "\n    ]"
		else:
			值字符串 = 行数组字符串列表[0]
		
		字典条目列表.append("\"%s\": %s" % [实体ID, 值字符串])

	var 字典字面量 = "{\n        " + ",\n        ".join(字典条目列表) + "\n    }"
	var 表变量名 = _生成合法变量名(表名称)
	var 脚本代码 = "static var %s: Dictionary = %s\n" % [表变量名, 字典字面量]

	return {
		"表名称": 表名称,
		"变量名": 表变量名,
		"脚本代码": 脚本代码,
		"列索引": 列索引字典字符串,
		"是否多行": "true" if 是否是多行表 else "false"
	}

func _直接转换单元格为字符串(原始值: String, 类型描述: Dictionary) -> String:
	var 转换值: String = 原始值
	if 转换值.is_empty() and 类型描述.has("默认值"):
		转换值 = 类型描述["默认值"]
	
	var 值类型: String = 类型描述["类型"]
	
	match 值类型:
		"int":
			if 转换值.is_valid_int():
				return 转换值
			return "0"
		"float":
			if 转换值.is_valid_float():
				return 转换值
			return "0.0"
		"string":
			return _快速转义字符串(转换值)
		"bool":
			var 小写值: String = 转换值.to_lower()
			if 小写值 in ["true", "1", "是", "真", "yes"]:
				return "true"
			return "false"
		"time":
			return _快速转义字符串(转换值)
		"vector2":
			var 分隔符: String = 类型描述.get("分隔符", ";")
			var 向量: Variant = _转换向量(转换值, "vector2", 分隔符)
			if 向量 == null:
				return "Vector2()"
			return "Vector2(%s, %s)" % [向量.x, 向量.y]
		"vector3":
			var 分隔符: String = 类型描述.get("分隔符", ";")
			var 向量: Variant = _转换向量(转换值, "vector3", 分隔符)
			if 向量 == null:
				return "Vector3()"
			return "Vector3(%s, %s, %s)" % [向量.x, 向量.y, 向量.z]
		"vector4":
			var 分隔符: String = 类型描述.get("分隔符", ";")
			var 向量: Variant = _转换向量(转换值, "vector4", 分隔符)
			if 向量 == null:
				return "Vector4()"
			return "Vector4(%s, %s, %s, %s)" % [向量.x, 向量.y, 向量.z, 向量.w]
		"color":
			var 颜色: Variant = _转换颜色(转换值)
			if 颜色 == null:
				return "Color()"
			return "Color(%s, %s, %s, %s)" % [颜色.r, 颜色.g, 颜色.b, 颜色.a]
		"list":
			var 子类型数组: Array = 类型描述["子类型"]
			var 外层分隔符: String = 类型描述.get("分隔符", ";")
			if 转换值.is_empty():
				return "[]"
			var 顶层元素数组: Array = _分割字符串忽略括号(转换值, 外层分隔符)
			var 元素字符串列表: PackedStringArray = PackedStringArray()
			# 只写了一个子类型（含联合类型）：每个元素就是一个值，不再拆“元组内字段”
			if 子类型数组.size() == 1:
				for 元素字符串 in 顶层元素数组:
					var 元素值: String = _直接转换单元格为字符串(元素字符串.strip_edges(), 子类型数组[0])
					元素字符串列表.append("[" + 元素值 + "]")
				return "[" + ", ".join(元素字符串列表) + "]"
			for 元组字符串 in 顶层元素数组:
				var 处理后字符串: String = 元组字符串.strip_edges()
				var 字段数组: Array = 处理后字符串.split(",")
				var 字段字符串列表: PackedStringArray = PackedStringArray()
				for 字段索引 in range(字段数组.size()):
					var 字段值: String = 字段数组[字段索引].strip_edges()
					字段字符串列表.append(_直接转换单元格为字符串(字段值, 子类型数组[字段索引]))
				元素字符串列表.append("[" + ", ".join(字段字符串列表) + "]")
			return "[" + ", ".join(元素字符串列表) + "]"
		"enum":
			var 枚举映射字典: Dictionary = 类型描述["枚举映射"]
			if 转换值 in 枚举映射字典:
				return _生成枚举字面量(枚举映射字典[转换值])
			for 键 in 枚举映射字典:
				if str(枚举映射字典[键]) == 转换值:
					return _生成枚举字面量(枚举映射字典[键])
			return _快速转义字符串(转换值)
		_:
			return _快速转义字符串(转换值)

func _生成枚举字面量(枚举值: Variant) -> String:
	if 枚举值 is int or 枚举值 is float:
		return str(枚举值)
	return _快速转义字符串(str(枚举值))

func _快速转义字符串(原始字符串: String) -> String:
	if 原始字符串.is_empty():
		return "\"\""
	var 需要转义: bool = false
	for c in 原始字符串:
		if c == '\\' or c == '"' or c == '\n' or c == '\r' or c == '\t':
			需要转义 = true
			break
	if not 需要转义:
		return "\"" + 原始字符串 + "\""
	var 缓冲区: PackedStringArray = PackedStringArray()
	缓冲区.append("\"")
	for c in 原始字符串:
		match c:
			'\\':
				缓冲区.append("\\\\")
			'"':
				缓冲区.append("\\\"")
			'\n':
				缓冲区.append("\\n")
			'\r':
				缓冲区.append("\\r")
			'\t':
				缓冲区.append("\\t")
			_:
				缓冲区.append(c)
	缓冲区.append("\"")
	return "".join(缓冲区)

# ==================== 辅助函数 ====================
func _生成合法变量名(表名称: String) -> String:
	var 缓冲区: PackedStringArray = PackedStringArray()
	for 字符 in 表名称:
		var 字符编码: int = 字符.unicode_at(0)
		if (字符编码 >= 65 and 字符编码 <= 90) or (字符编码 >= 97 and 字符编码 <= 122) or (字符编码 >= 48 and 字符编码 <= 57) or 字符编码 == 95 or (字符编码 >= 0x4E00 and 字符编码 <= 0x9FFF):
			缓冲区.append(字符)
		else:
			缓冲区.append("_")
	
	var 合法名称: String = "".join(缓冲区)
	if 合法名称.length() > 0 and (合法名称[0] >= '0' and 合法名称[0] <= '9'):
		return "_" + 合法名称
	
	return 合法名称

func _数组转GDScript字符串(数组: Array) -> String:
	if 数组.is_empty():
		return "[]"
	var 元素字符串列表: PackedStringArray = PackedStringArray()
	for 元素 in 数组:
		元素字符串列表.append(_值转GDScript字符串(元素))
	return "[" + ", ".join(元素字符串列表) + "]"

func _值转GDScript字符串(值: Variant) -> String:
	var 值类型: int = typeof(值)
	if 值类型 == TYPE_NIL:
		return "null"
	if 值类型 == TYPE_BOOL:
		return "true" if 值 else "false"
	if 值类型 == TYPE_INT or 值类型 == TYPE_FLOAT:
		return str(值)
	if 值类型 == TYPE_STRING:
		return _转义字符串(值)
	if 值类型 == TYPE_ARRAY:
		return _数组转GDScript字符串(值)
	if 值类型 == TYPE_DICTIONARY:
		return _字典转GDScript字符串(值)
	if 值类型 == TYPE_VECTOR2:
		return "Vector2(%s, %s)" % [值.x, 值.y]
	if 值类型 == TYPE_VECTOR3:
		return "Vector3(%s, %s, %s)" % [值.x, 值.y, 值.z]
	if 值类型 == TYPE_VECTOR4:
		return "Vector4(%s, %s, %s, %s)" % [值.x, 值.y, 值.z, 值.w]
	if 值类型 == TYPE_COLOR:
		return "Color(%s, %s, %s, %s)" % [值.r, 值.g, 值.b, 值.a]
	return str(值)

func _转义字符串(原始字符串: String) -> String:
	if 原始字符串.is_empty():
		return "\"\""
	var 需要转义: bool = false
	for i in range(原始字符串.length()):
		var c: String = 原始字符串[i]
		if c == '\\' or c == '"' or c == '\n' or c == '\r' or c == '\t':
			需要转义 = true
			break
	if not 需要转义:
		return "\"" + 原始字符串 + "\""
	var 缓冲区: PackedStringArray = PackedStringArray()
	缓冲区.append("\"")
	for i in range(原始字符串.length()):
		var c: String = 原始字符串[i]
		match c:
			'\\':
				缓冲区.append("\\\\")
			'"':
				缓冲区.append("\\\"")
			'\n':
				缓冲区.append("\\n")
			'\r':
				缓冲区.append("\\r")
			'\t':
				缓冲区.append("\\t")
			_:
				缓冲区.append(c)
	缓冲区.append("\"")
	return "".join(缓冲区)

func _字典转GDScript字符串(字典: Dictionary) -> String:
	if 字典.is_empty():
		return "{}"
	var 键列表: Array = 字典.keys()
	键列表.sort()
	var 键值对列表: PackedStringArray = PackedStringArray()
	for 键 in 键列表:
		键值对列表.append("\"%s\": %s" % [键, _值转GDScript字符串(字典[键])])
	return "{" + ", ".join(键值对列表) + "}"

# 列索引字典按索引值升序输出（0, 1, 2, ...），便于阅读定位
func _列索引转GDScript字符串(列索引字典: Dictionary) -> String:
	if 列索引字典.is_empty():
		return "{}"
	var 键值对列表: Array = []
	for 键 in 列索引字典:
		键值对列表.append([键, 列索引字典[键]])
	键值对列表.sort_custom(func(a: Array, b: Array) -> bool:
		return a[1] < b[1])
	var 结果列表: PackedStringArray = PackedStringArray()
	for 键值对 in 键值对列表:
		结果列表.append("\"%s\": %s" % [键值对[0], _值转GDScript字符串(键值对[1])])
	return "{" + ", ".join(结果列表) + "}"

# ==================== 增量生成 ====================
func _计算文件哈希(路径: String) -> String:
	var s: String = _读取文件文本安全(路径)
	if s.is_empty():
		return ""
	return str(s.hash())

func _检查表是否需要重新生成(表名: String, 表信息: Dictionary) -> bool:
	var 路径: String = 表信息["文件路径"]
	var 当前哈希: String = _计算文件哈希(路径)
	
	if _文件哈希缓存.has(路径):
		var 旧哈希: String = _文件哈希缓存[路径]
		if 旧哈希 == 当前哈希:
			return false
	
	_文件哈希缓存[路径] = 当前哈希
	return true

func _获取表缓存代码(表名: String) -> String:
	if _表生成缓存.has(表名):
		return _表生成缓存[表名]["代码"]
	return ""

func _保存表缓存代码(表名: String, 表代码: String, 路径: String):
	var 哈希: String = _文件哈希缓存.get(路径, "")
	_表生成缓存[表名] = {
		"哈希": 哈希,
		"代码": 表代码
	}
