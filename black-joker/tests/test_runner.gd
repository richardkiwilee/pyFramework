extends Node
## =============================================================================
## TestRunner — 极简单元测试 runner（自研，替代 zfoo gdtest）
## =============================================================================
## 用法（见 docs/01-plan.md 阶段 0）：
##   godot --headless --path <abs> res://tests/test_runner.tscn
## 行为：
##   - 扫描 tests/unit/ 下所有 *.gd，实例化后运行其方法名(小写)含 "test" 的无参方法；
##   - 测试脚本 extend TestBase（tests/test_base.gd），用 assert_eq/assert_true 断言；
##   - 失败经 push_error 记录（与 fullver-1 约定一致），结束时 quit(失败数)，
##     退出码 0 = 全部通过。
## 注意：不依赖任何 zfoo 组件，避免 IntegrationTest 退出 SIGSEGV 的已知问题。
## =============================================================================

const UNIT_DIR := "res://tests/unit"


func _ready() -> void:
	# 等场景树就绪后开始（call_deferred 让 autoload 都初始化完）
	_run.call_deferred()


## 递归扫描目录下所有 .gd 测试文件
func _scan(dir: String, out: Array[String]) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		push_error("[test_runner] 无法打开目录: " + dir)
		return
	da.list_dir_begin()
	var entry := da.get_next()
	while entry != "":
		var full := dir.path_join(entry)
		if da.current_is_dir():
			_scan(full, out)
		elif entry.ends_with(".gd") and entry.begins_with("test_"):
			out.append(full)
		entry = da.get_next()
	da.list_dir_end()


func _run() -> void:
	var files: Array[String] = []
	_scan(UNIT_DIR, files)
	files.sort()
	var total := 0
	var start_failures: int = TestBase.failures
	for path in files:
		var script: GDScript = load(path) as GDScript
		# 解析失败的脚本 load() 仍返回非 null 的坏对象，须用 can_instantiate 判断
		if script == null or not script.can_instantiate():
			TestBase.failures += 1
			push_error("[test_runner] 加载失败: " + path)
			continue
		var obj: RefCounted = script.new()
		if obj is not TestBase:
			push_error("[test_runner] %s 未继承 TestBase，跳过" % path)
			continue
		# 注入运行上下文（异步测试经 ctx["tree"] 访问场景树；缺了它测试体
		# 会在 ctx["tree"] 处运行时错误中止 → 断言不执行 → 假绿）
		obj.set("ctx", {"tree": get_tree()})
		var methods: Array[String] = []
		for m in script.get_script_method_list():
			var mname: String = m["name"]
			var args: Array = m.get("args", [])
			if mname.to_lower().contains("test") and args.is_empty():
				methods.append(mname)
		methods.sort()
		for mname in methods:
			# 协程测试方法必须 await 完再计数——不 await 会假绿。
			# obj.call() 对协程是 fire-and-forget（返回 Nil），只有
			# `await Callable(obj, name).call()` 能真正等待协程完成。
			var cb := Callable(obj, mname)
			await cb.call()
			total += 1
	print("[test_runner] 共运行 %d 个测试" % total)
	var fails: int = TestBase.failures - start_failures
	if fails > 0:
		printerr("[test_runner] 失败 %d 个" % fails)
	else:
		print("[test_runner] 全部通过")
	get_tree().quit(fails)
