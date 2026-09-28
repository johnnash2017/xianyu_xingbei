class_name 自检用例
extends Node
## 自检用例基类：tests/用例/ 下的脚本继承它，用 检() 断言，运行器会汇总 失败 里的信息

var 名称: String = ""
var 失败: Array[String] = []


## 断言：不成立就记一条失败（不中断，尽量一次把问题报完）
func 检(条件: bool, 说明: String) -> void:
	if not 条件:
		失败.append(说明)


## 等若干帧（界面切换、刷新用）
func 等帧(数: int = 2) -> void:
	for _i: int in range(数):
		await get_tree().process_frame


## 子类实现，可 await
func 跑() -> void:
	pass
