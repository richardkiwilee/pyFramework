extends Control
## =============================================================================
## ReelOverlay — 滚轮覆盖层（ReelView 的 4 个覆盖子层共用一个脚本）
## =============================================================================
## 作用：在滚轮 item 之上绘制 UI 层。Godot 中绘制只允许在节点自身的
##       _draw() 内进行（实测 draw 信号回调里绘图会报错），因此覆盖层
##       需要各自独立的 _draw()，这里用一个脚本按 mode 分派到 ReelView
##       的公开绘制方法。
##
## 模式：
##   INDICATOR   — 居中指示框（金色上下边 + 两侧发光圆点）
##   MASK_TOP / MASK_BOTTOM — 上下遮罩（阶梯色带模拟渐变）
##   SPOTLIGHT   — 聚光灯（零尺寸节点，position=选中单位格中心）
## =============================================================================

enum Mode { INDICATOR, MASK_TOP, MASK_BOTTOM, SPOTLIGHT }

## 所属的 ReelView（几何与绘制逻辑都在 ReelView 上）
var reel: Control = null
var mode: int = Mode.INDICATOR


func _draw() -> void:
	if reel == null:
		return
	match mode:
		Mode.INDICATOR:
			reel.draw_indicator_overlay(self)
		Mode.MASK_TOP:
			reel.draw_mask_overlay(self, true)
		Mode.MASK_BOTTOM:
			reel.draw_mask_overlay(self, false)
		Mode.SPOTLIGHT:
			reel.draw_spotlight_overlay(self)
