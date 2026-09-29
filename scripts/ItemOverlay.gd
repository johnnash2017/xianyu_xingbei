## 网格重叠修正 —— 对应 UnityEngine.UI.ItemOverlay（[RequireComponent(typeof(GridLayoutGroup))]）
## 注意：本移植里该脚本的宿主节点不一定是 GridContainer（ChooseArea 就是 TextureRect），
## 所以基类取 Control，网格相关的调用运行时按类型判断。
extends Control

## 对应 C# private int noOverLayCnt;
var noOverLayCnt: int = 0
## 对应 C# private float layoutSizeX;（RectTransform.sizeDelta.x）
var layoutSizeX: float = 0.0
## 对应 C# private float layoutCellSizeX;（GridLayoutGroup.cellSize.x）
var layoutCellSizeX: float = 0.0

## 对应 C# private void Awake()
func _ready() -> void:
	# Godot 里格子宽度由子节点最小尺寸决定，用子节点最大最小宽度近似 cellSize.x
	layoutCellSizeX = _measure_cell_size_x()
	layoutSizeX = size.x
	noOverLayCnt = _calc_no_overlay_cnt()

## 对应 C# private void Update()
func _process(_delta: float) -> void:
	# 布局尺寸在 _ready 时可能还没算好（那时容器里还没有子节点，格子宽度量到 0），
	# 所以「宽度或格子宽度任一为 0」都要重算一遍 —— 原来只判 layoutSizeX <= 0，
	# 而 size.x=691 永远成立不假，格子宽度就永久停在 0，重叠压缩分支从不触发（battle_audit D-4）。
	if layoutCellSizeX <= 0.0 or layoutSizeX <= 0.0:
		layoutSizeX = size.x
		if layoutCellSizeX <= 0.0:
			layoutCellSizeX = _measure_cell_size_x()
		noOverLayCnt = _calc_no_overlay_cnt()
	var cnt := get_child_count()
	var sep := 0
	# 对应 C# if (transform.childCount > noOverLayCnt) spacing.x = (layoutSizeX - layoutCellSizeX * childCount) / (childCount - 1);
	if cnt > noOverLayCnt and cnt > 1:
		sep = int((layoutSizeX - layoutCellSizeX * float(cnt)) / float(cnt - 1))
	# 对应 C# layout.spacing = spacing;（GridLayoutGroup.spacing.x -> GridContainer 的 h_separation）
	# 用的是**自己**（C# 是 GetComponent<GridLayoutGroup>()，即「取自己」）；原来写成 get_parent()，
	# 父节点是 Root（Control）→ 恒为 null，h_separation 从来没设过（battle_audit D-4）。
	# 宿主节点可能不是 GridContainer（ChooseArea 是 TextureRect），只在确实是容器时设置。
	# 注意先落到 Node 再向下转型：直接 `self as GridContainer` 会被 Godot 静态判成
	# 「脚本类型 -> GridContainer」的非法转换（Parse Error）。
	var self_node: Node = self
	var grid := self_node as GridContainer
	if grid != null:
		grid.add_theme_constant_override("h_separation", sep)

# ---------------- 辅助 ----------------

func _calc_no_overlay_cnt() -> int:
	if layoutCellSizeX <= 0.0:
		# 无法推算格子宽度时不做重叠修正
		return 1 << 30
	return int(layoutSizeX / layoutCellSizeX)

func _measure_cell_size_x() -> float:
	var w := 0.0
	for c in get_children():
		if c is Control:
			w = maxf(w, (c as Control).get_combined_minimum_size().x)
	return w
