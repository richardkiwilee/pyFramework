extends TestBase
## 冒烟测试：验证 runner 能发现并运行测试方法、断言失败能被计数


func test_assert_true_works() -> void:
	assert_true(1 + 1 == 2, "基础算术")


func test_assert_eq_works() -> void:
	assert_eq("a", "a", "字符串相等")


func test_async_aa_probe() -> void:
	# 探针：若 runner 没有真正 await 协程方法，本方法体异步部分不执行，
	# ctx["async_ran"] 不会被置位，test_async_ab_flag 会失败。
	await ctx["tree"].process_frame
	await ctx["tree"].process_frame
	ctx["async_ran"] = true


func test_async_ab_flag() -> void:
	assert_true(bool(ctx.get("async_ran", false)), "runner 未 await 协程测试方法（假绿风险）")
