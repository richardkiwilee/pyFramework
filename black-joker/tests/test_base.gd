class_name TestBase
extends RefCounted
## =============================================================================
## TestBase — 测试基类
## =============================================================================
## 测试脚本 extend 本类并编写 test* 无参方法。断言失败走 push_error
## （必须用 push_error 而不是 Log.error——runner 靠 printerr 输出定位问题，
## 且与仓库既定约定一致）。failures 为静态计数，runner 结束时据此定退出码。
## =============================================================================

static var failures: int = 0

## runner 注入的运行上下文（含 tree、失败计数）；异步测试经此访问场景树
var ctx: Dictionary = {}


## 记录一次断言失败（不改执行流，与 zfoo gdtest 的 FAIL 语义一致）
func _fail(template: String, args: Array = []) -> void:
	failures += 1
	push_error("[test] " + template.format(args, "{}"))


func assert_true(cond: bool, msg: String = "条件为假") -> void:
	if not cond:
		_fail(msg)


func assert_false(cond: bool, msg: String = "条件为真") -> void:
	if cond:
		_fail(msg)


func assert_eq(got: Variant, expected: Variant, msg: String = "") -> void:
	if got != expected:
		var label := "期望 %s, 实际 %s" % [str(expected), str(got)]
		_fail(msg + " — " + label if msg != "" else label)
