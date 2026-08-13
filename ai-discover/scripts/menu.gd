extends Control
## =============================================================================
## menu.gd — AI Discover 主菜单
## =============================================================================
## 功能发现实验室的入口：列出所有已实现的功能点卡片，
## 点击卡片进入对应子场景；每个子场景左上角都有"返回主菜单"按钮。
## 新增功能时，只需在 FEATURES 里追加一条记录（卡片自动生成）。
## =============================================================================

const FEATURES: Array = [
	# 每完成一个功能点，在此追加：
	# {"icon": 表情, "name": 名称, "desc": 一句话描述, "scene": 场景路径}
	{"icon": "🌊", "name": "水面倒影", "desc": "3D 波光水面与镜像倒影", "scene": "res://features/water_reflection/water_reflection.tscn"},
	{"icon": "⬡", "name": "六边形地图", "desc": "轴向六边形网格与寻路", "scene": "res://features/hex_map/hex_map.tscn"},
	{"icon": "🎰", "name": "老虎机", "desc": "三轴滚动与中奖判定", "scene": "res://features/slot_machine/slot_machine.tscn"},
	{"icon": "🌀", "name": "传送门", "desc": "漩涡能量门与空间传送", "scene": "res://features/portal/portal.tscn"},
	{"icon": "📊", "name": "血条组件包", "desc": "幽灵血条/施法条/耐力条", "scene": "res://features/ui_bars/ui_bars.tscn"},
	{"icon": "🎆", "name": "粒子烟花", "desc": "点击夜空发射彩色烟花", "scene": "res://features/fireworks/fireworks.tscn"},
	{"icon": "🎒", "name": "背包拖拽", "desc": "物品拖拽交换位置", "scene": "res://features/inventory/inventory.tscn"},
	{"icon": "👊", "name": "命中反馈", "desc": "震屏/白闪/飘字/连击", "scene": "res://features/hit_feedback/hit_feedback.tscn"},
	{"icon": "⚔️", "name": "刀光斩击", "desc": "拖拽挥出月牙刀光", "scene": "res://features/slash/slash.tscn"},
	{"icon": "🛰", "name": "小地图雷达", "desc": "俯视小地图与雷达扫描", "scene": "res://features/radar/radar.tscn"},
	{"icon": "🧭", "name": "A* 寻路", "desc": "启发式搜索逐步可视化", "scene": "res://features/astar/astar.tscn"},
	{"icon": "🌗", "name": "昼夜循环", "desc": "太阳轨道与光照渐变", "scene": "res://features/daynight/daynight.tscn"},
	{"icon": "🌈", "name": "鼠标拖尾", "desc": "彩虹彗尾与点击光环", "scene": "res://features/mouse_trail/mouse_trail.tscn"},
	{"icon": "💧", "name": "点击波纹", "desc": "水面扩散涟漪shader", "scene": "res://features/ripple/ripple.tscn"},
	{"icon": "🎲", "name": "骰子", "desc": "物理投掷与点数读数", "scene": "res://features/dice/dice.tscn"},
	{"icon": "🌫", "name": "战争迷雾", "desc": "双层探索与视野揭示", "scene": "res://features/fog_of_war/fog_of_war.tscn"},
	{"icon": "🃏", "name": "卡牌手牌", "desc": "扇形手牌与打出补牌", "scene": "res://features/card_hand/card_hand.tscn"},
	{"icon": "🧲", "name": "磁力吸附", "desc": "拖拽方块自动吸附槽位", "scene": "res://features/magnet_snap/magnet_snap.tscn"},
]

@onready var grid: GridContainer = $CenterBox/VBox/Grid
@onready var count_label: Label = $CenterBox/VBox/FooterLabel


func _ready() -> void:
	for f in FEATURES:
		grid.add_child(_make_card(f))
	_refresh_footer()


## 生成一张功能卡片按钮（深色圆角卡 + 悬停提亮）
func _make_card(f: Dictionary) -> Button:
	var btn := Button.new()
	btn.text = "%s  %s\n%s" % [f["icon"], f["name"], f["desc"]]
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.custom_minimum_size = Vector2(236, 96)
	btn.add_theme_font_size_override("font_size", 15)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.11, 0.13, 0.20)
	normal.border_color = Color(0.28, 0.34, 0.50)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(12)
	normal.content_margin_left = 14.0
	normal.content_margin_right = 14.0
	var hover := normal.duplicate()
	hover.bg_color = Color(0.17, 0.20, 0.30)
	hover.border_color = Color(0.55, 0.65, 1.0)
	var pressed := hover.duplicate()
	pressed.bg_color = Color(0.13, 0.16, 0.26)
	for state in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(state, normal if state == "normal" else (hover if state == "hover" else pressed))

	btn.pressed.connect(_open_feature.bind(f["scene"]))
	return btn


func _open_feature(path: String) -> void:
	get_tree().change_scene_to_file(path)


func _refresh_footer() -> void:
	if FEATURES.is_empty():
		count_label.text = "还没有功能点——正在头脑风暴中…"
	else:
		count_label.text = "已实现 %d 个功能点 · 持续更新中" % FEATURES.size()
