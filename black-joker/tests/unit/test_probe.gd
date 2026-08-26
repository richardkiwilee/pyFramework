extends TestBase
## 探针：验证"引用其他全局类的类型化数组构造"在真实运行环境是否可用


func test_probe_typed_array_of_other_class() -> void:
	var arr: Array[CardData] = []
	arr.append(CardData.new(0, 1))
	assert_eq(arr.size(), 1, "类型化数组构造成功")
	assert_eq(arr[0].value(), 1, "元素可访问")


func test_probe_new_of_other_class() -> void:
	var c := CardData.new(1, 13)
	assert_eq(c.id(), "1-13", "其他类 new() 成功")
