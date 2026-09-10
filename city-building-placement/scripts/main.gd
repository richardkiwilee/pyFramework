class_name Main
extends Node3D
## 主场景根：连接相机拾取 -> 世界高亮 / UI 分发。

func _ready() -> void:
	var world: World = get_node("World") as World
	var camera: CameraDrag = get_node("Camera") as CameraDrag
	var ui: GameUI = get_node("UI/Root") as GameUI
	camera.map_clicked.connect(ui.on_tile_clicked)
	camera.map_hovered.connect(world.on_hover)
	ui.refresh_all()
