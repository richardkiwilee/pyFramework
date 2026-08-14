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
	{"icon": "🎶", "name": "音乐可视化", "desc": "合成和弦驱动频谱光柱", "scene": "res://features/audio_visualizer/audio_visualizer.tscn"},
	{"icon": "🏭", "name": "传送带物流", "desc": "折线传送带与收集计数", "scene": "res://features/conveyor/conveyor.tscn"},
	{"icon": "💣", "name": "物理塔", "desc": "炮弹轰击积木塔连锁倒塌", "scene": "res://features/physics_tower/physics_tower.tscn"},
	{"icon": "💬", "name": "打字机对话", "desc": "逐字显示与分支选项", "scene": "res://features/dialog/dialog.tscn"},
	{"icon": "🎯", "name": "弹道预测", "desc": "抛物线瞄准虚线炮击", "scene": "res://features/trajectory/trajectory.tscn"},
	{"icon": "🧬", "name": "生命游戏", "desc": "Conway元胞自动机演化", "scene": "res://features/game_of_life/game_of_life.tscn"},
	{"icon": "🐍", "name": "贪吃蛇", "desc": "经典小游戏吃食增长", "scene": "res://features/snake/snake.tscn"},
	{"icon": "🎥", "name": "分屏双视角", "desc": "同世界跟随+俯视双屏", "scene": "res://features/split_screen/split_screen.tscn"},
	{"icon": "🎨", "name": "像素画板", "desc": "点画+油漆桶泛洪填充", "scene": "res://features/pixel_painter/pixel_painter.tscn"},
	{"icon": "🔦", "name": "激光反射", "desc": "拖镜面引导光束命中靶心", "scene": "res://features/laser/laser.tscn"},
	{"icon": "🛤", "name": "轨道编辑器", "desc": "样条轨道布点与列车行驶", "scene": "res://features/path_editor/path_editor.tscn"},
	{"icon": "👕", "name": "布料模拟", "desc": "Verlet物理布料与风", "scene": "res://features/cloth/cloth.tscn"},
	{"icon": "🔦", "name": "手电筒光照", "desc": "光锥shader照亮藏宝图", "scene": "res://features/flashlight/flashlight.tscn"},
	{"icon": "✨", "name": "粒子光环", "desc": "轨道粒子环与旋转星盘", "scene": "res://features/particle_halo/particle_halo.tscn"},
	{"icon": "🏔", "name": "程序化地形", "desc": "fbm噪声高度图彩色地形", "scene": "res://features/terrain_gen/terrain_gen.tscn"},
	{"icon": "💎", "name": "三消游戏", "desc": "交换宝石三连消除连锁", "scene": "res://features/match3/match3.tscn"},
	{"icon": "🎹", "name": "合成器键盘", "desc": "实时复音合成钢琴键盘", "scene": "res://features/synth_keyboard/synth_keyboard.tscn"},
	{"icon": "⛓", "name": "弹簧绳索", "desc": "Verlet绳索惯性甩动", "scene": "res://features/rope/rope.tscn"},
	{"icon": "🔮", "name": "万花筒", "desc": "扇形折叠对称图案shader", "scene": "res://features/kaleidoscope/kaleidoscope.tscn"},
	{"icon": "🔴", "name": "弹珠迷宫", "desc": "倾斜滚动惯性撞墙", "scene": "res://features/marble_maze/marble_maze.tscn"},
	{"icon": "🎡", "name": "转盘抽奖", "desc": "扇形转盘缓动抽奖", "scene": "res://features/wheel/wheel.tscn"},
	{"icon": "🧠", "name": "记忆翻牌", "desc": "配对记忆与翻转动画", "scene": "res://features/memory/memory.tscn"},
	{"icon": "🎱", "name": "台球", "desc": "弹性碰撞瞄准击球", "scene": "res://features/billiards/billiards.tscn"},
	{"icon": "🌀", "name": "迷宫生成", "desc": "递归回溯完美迷宫+BFS解法", "scene": "res://features/maze_gen/maze_gen.tscn"},
	{"icon": "🕹", "name": "打砖块", "desc": "挡板弹球消砖计分", "scene": "res://features/breakout/breakout.tscn"},
	{"icon": "🌳", "name": "分形树", "desc": "递归分支随机生长", "scene": "res://features/fractal_tree/fractal_tree.tscn"},
	{"icon": "⌨️", "name": "打字练习", "desc": "下落单词击破+WPM统计", "scene": "res://features/typing_game/typing_game.tscn"},
	{"icon": "🎨", "name": "粒子画笔", "desc": "拖拽作画+粒子飞溅", "scene": "res://features/particle_brush/particle_brush.tscn"},
	{"icon": "🪐", "name": "重力弹射", "desc": "行星引力拖拽弹射彗星", "scene": "res://features/gravity_sling/gravity_sling.tscn"},
	{"icon": "🪀", "name": "弹簧滑块", "desc": "弹簧物理UI滑块吸附回弹", "scene": "res://features/spring_slider/spring_slider.tscn"},
	{"icon": "📜", "name": "惯性滚动列表", "desc": "拖拽惯性滑行边界回弹", "scene": "res://features/scroll_list/scroll_list.tscn"},
	{"icon": "🎼", "name": "波形画板", "desc": "手绘波形实时合成发声", "scene": "res://features/waveform_painter/waveform_painter.tscn"},
	{"icon": "🌌", "name": "星空飞越", "desc": "深度投影星流鼠标转向", "scene": "res://features/starfield/starfield.tscn"},
	{"icon": "🎲", "name": "多米诺骨牌", "desc": "连锁倾倒链式反应", "scene": "res://features/dominoes/dominoes.tscn"},
	{"icon": "🔨", "name": "打地鼠", "desc": "30秒限时敲击计分", "scene": "res://features/whack_a_mole/whack_a_mole.tscn"},
	{"icon": "🔺", "name": "帕斯卡三角", "desc": "模N染色谢尔宾斯基图案", "scene": "res://features/pascal_triangle/pascal_triangle.tscn"},
	{"icon": "🎨", "name": "颜色拾取器", "desc": "HSV色环+明度饱和度方形", "scene": "res://features/color_picker/color_picker.tscn"},
	{"icon": "💥", "name": "弹幕躲避", "desc": "鼠标躲避弹幕生存30秒", "scene": "res://features/bullet_hell/bullet_hell.tscn"},
	{"icon": "🎵", "name": "节拍器", "desc": "BPM可调合成节拍音", "scene": "res://features/metronome/metronome.tscn"},
	{"icon": "⚫", "name": "五子棋", "desc": "双人轮流五连取胜", "scene": "res://features/gomoku/gomoku.tscn"},
	{"icon": "🕐", "name": "数码管时钟", "desc": "七段LED实时时间", "scene": "res://features/segment_clock/segment_clock.tscn"},
	{"icon": "🌧", "name": "雨滴特效", "desc": "雨丝下落溅花+随机闪电", "scene": "res://features/rain/rain.tscn"},
	{"icon": "🧩", "name": "滑动拼图", "desc": "15-puzzle数字滑块", "scene": "res://features/sliding_puzzle/sliding_puzzle.tscn"},
	{"icon": "🔢", "name": "2048", "desc": "滑动合并合成2048", "scene": "res://features/game_2048/game_2048.tscn"},
	{"icon": "☁️", "name": "程序化云朵", "desc": "重叠圆云团视差漂移", "scene": "res://features/clouds/clouds.tscn"},
	{"icon": "🐤", "name": "像素小鸟", "desc": "拍翼穿管道得分", "scene": "res://features/flappy/flappy.tscn"},
	{"icon": "📺", "name": "故障风特效", "desc": "CRT扫描线RGB偏移撕裂", "scene": "res://features/glitch/glitch.tscn"},
	{"icon": "🪐", "name": "太阳系轨道", "desc": "行星公转尾迹可加星", "scene": "res://features/orbit/orbit.tscn"},
	{"icon": "🕰", "name": "模拟挂钟", "desc": "三针平滑走时罗马表盘", "scene": "res://features/analog_clock/analog_clock.tscn"},
	{"icon": "📝", "name": "便利贴板", "desc": "可拖拽可编辑便签板", "scene": "res://features/sticky_notes/sticky_notes.tscn"},
	{"icon": "🟢", "name": "矩阵代码雨", "desc": "绿色字符雨特效", "scene": "res://features/matrix_rain/matrix_rain.tscn"},
	{"icon": "🟦", "name": "俄罗斯方块", "desc": "七种方块旋转消行", "scene": "res://features/tetris/tetris.tscn"},
	{"icon": "🎯", "name": "弹簧床", "desc": "重力弹跳形变最高点", "scene": "res://features/trampoline/trampoline.tscn"},
	{"icon": "✍️", "name": "签名板", "desc": "手写签名导出PNG", "scene": "res://features/signature_pad/signature_pad.tscn"},
	{"icon": "💗", "name": "心形粒子", "desc": "点击喷发爱心粒子", "scene": "res://features/heart_burst/heart_burst.tscn"},
	{"icon": "🔍", "name": "放大镜", "desc": "圆形透镜放大屏幕内容", "scene": "res://features/magnifier/magnifier.tscn"},
	{"icon": "⏱", "name": "秒表", "desc": "计时暂停计次重置", "scene": "res://features/stopwatch/stopwatch.tscn"},
	{"icon": "🎧", "name": "3D环绕音效", "desc": "音源绕头旋转立体声", "scene": "res://features/spatial_audio/spatial_audio.tscn"},
	{"icon": "📋", "name": "拖拽排序列表", "desc": "拖动行重排待办清单", "scene": "res://features/reorder_list/reorder_list.tscn"},
	{"icon": "🎵", "name": "木琴", "desc": "点击音条发声回弹", "scene": "res://features/xylophone/xylophone.tscn"},
	{"icon": "🎴", "name": "视差卡片", "desc": "卡片随鼠标伪3D倾斜", "scene": "res://features/parallax_cards/parallax_cards.tscn"},
	{"icon": "❌", "name": "井字棋", "desc": "对战Minimax不败AI", "scene": "res://features/tic_tac_toe/tic_tac_toe.tscn"},
	{"icon": "🔐", "name": "密码强度计", "desc": "六项规则实时评估", "scene": "res://features/password_meter/password_meter.tscn"},
	{"icon": "⚙️", "name": "齿轮传动", "desc": "啮合齿轮齿比联动", "scene": "res://features/gears/gears.tscn"},
]

@onready var grid: GridContainer = $CenterBox/VBox/Scroll/Grid
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
