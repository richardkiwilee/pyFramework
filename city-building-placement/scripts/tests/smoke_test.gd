extends SceneTree
## 冒烟测试（headless）：核心逻辑 + 主场景可加载 + UI 可构建。
## 运行：godot --headless --path <abs> --script res://scripts/tests/smoke_test.gd
## 退出码 0 = 全部通过。

const BuildingData := preload("res://scripts/data/building_data.gd")
const TerrainData := preload("res://scripts/data/terrain_data.gd")

var _fail_count: int = 0


func _init() -> void:
	_run()


func _run() -> void:
	var err: int = change_scene_to_file("res://scenes/main.tscn")
	if err != OK:
		_check(false, "主场景加载")
		quit(1)
		return
	for i in 40:
		await process_frame
	var cs: Node = root.get_node("CityState")
	_check(int(cs.get("owned").size()) == 7, "开局拥有 1 环 7 格")
	_check(bool(cs.call("is_built", Vector2i.ZERO)), "市中心已放置")
	_check(int(cs.get("resources").get(BuildingData.Res.GOLD, 0)) == 200, "初始金币 200")

	# 开拓 (1,1)：环2 平原，接壤 (1,0)
	_check(bool(cs.call("can_expand", Vector2i(1, 1))), "(1,1) 可开拓")
	var cost: Dictionary = cs.call("expand_cost", Vector2i(1, 1))
	_check(int(cost.get(BuildingData.Res.GOLD, 0)) == 41, "开拓费用金=41（30×1.35）")
	_check(int(cost.get(BuildingData.Res.WOOD, 0)) == 27, "开拓费用木=27（20×1.35）")
	_check(bool(cs.call("expand", Vector2i(1, 1))), "开拓成功")
	_check(int(cs.get("owned").size()) == 8, "地块数 8")

	# 在 (1,1) 建农场：水域加成 2 格 + 匹配平原 → 食物 2+2+1=5
	_check(bool(cs.call("can_build", Vector2i(1, 1), "farm")), "(1,1) 可建农场")
	_check(bool(cs.call("build", Vector2i(1, 1), "farm")), "建造农场成功")
	var fy: Dictionary = cs.call("building_yield", Vector2i(1, 1))
	_check(int(fy.get(BuildingData.Res.FOOD, 0)) == 5, "农场产出=5食（基础2+水域2+匹配1）")

	# 磨坊相邻要求：无水的 (0,-1) 被拒；临湖的 (2,0) 可行
	var reason: String = cs.call("build_block_reason", Vector2i(0, -1), "mill")
	_check(reason.contains("相邻要求"), "磨坊在无水处被拒（%s）" % reason)
	_check(cs.call("build_block_reason", Vector2i(2, 0), "mill") == "", "(2,0) 磨坊要求满足")

	# 采石场仅丘陵：平原 (0,-1) 被拒、丘陵 (-1,0) 可行
	_check(cs.call("build_block_reason", Vector2i(0, -1), "quarry") != "", "采石场在平原被拒")
	_check(cs.call("build_block_reason", Vector2i(-1, 0), "quarry") == "", "采石场在丘陵可行")

	# 升级：农场 Lv1 -> Lv2，费用 = 基础 ×2
	var ucost: Dictionary = cs.call("upgrade_cost", Vector2i(1, 1))
	_check(int(ucost.get(BuildingData.Res.GOLD, 0)) == 20, "升级费金=20")
	_check(bool(cs.call("upgrade", Vector2i(1, 1))), "升级成功")
	var fy2: Dictionary = cs.call("building_yield", Vector2i(1, 1))
	_check(int(fy2.get(BuildingData.Res.FOOD, 0)) == 9, "Lv2 农场产出=9食（3基础+2×(1+1)水域+2匹配）")

	# 市中心不可拆
	_check(not bool(cs.call("can_demolish", Vector2i.ZERO)), "市中心不可拆除")

	# 回合结算：中心(3金1木1食1石) + Lv2 农场(9食)
	var income: Dictionary = cs.call("net_income")
	_check(int(income.get(BuildingData.Res.FOOD, 0)) == 10, "净收入食物=10")
	cs.call("end_turn")
	_check(int(cs.get("turn_count")) == 1, "回合数 1")

	# UI 可构建：建造窗口 20 张卡
	var ui: Node = root.get_node("Main/UI/Root")
	if ui.has_method("open_build_window"):
		ui.call("open_build_window", Vector2i(0, -1))
		var grid: Node = ui.get("bw_grid")
		_check(int(grid.get_child_count()) == 20, "建造窗口 20 张卡片")
		ui.call("select_card", "farm")
		_check(not bool(ui.get("bw_build_button").get("disabled")), "选中农场后建造按钮启用")
		ui.call("_on_cancel_build_pressed")
		_check(not bool(ui.get("bw_overlay").get("visible")), "取消建造后窗口关闭回到地图")
		ui.call("open_expand_confirm", Vector2i(1, 1))
		ui.call("open_building_popup", Vector2i(1, 1))
		_check(bool(ui.get("expand_overlay").get("visible")), "开拓确认框打开")
		# 市中心弹窗必须有可用的关闭按钮（曾卡死全部输入）
		ui.call("open_building_popup", Vector2i.ZERO)
		_check(bool(ui.get("bp_overlay").get("visible")), "市中心弹窗打开")
		ui.call("_on_popup_close_pressed")
		_check(not bool(ui.get("bp_overlay").get("visible")), "市中心弹窗可关闭")
	else:
		_check(false, "UI 脚本加载（open_build_window 存在）")

	if _fail_count == 0:
		print("SMOKE: 全部通过")
		quit(0)
	else:
		push_error("SMOKE: %d 项失败" % _fail_count)
		quit(1)


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  PASS: %s" % label)
	else:
		_fail_count += 1
		push_error("  FAIL: %s" % label)
