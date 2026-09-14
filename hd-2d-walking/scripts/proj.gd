extends RefCounted
## 伪立体投影：把"俯视格坐标 + 高度"映射到屏幕坐标与景深。
##
## 由一台倾斜相机推导。相机俯角 θ 满足 tanθ = ROW_H / ELEV_H = 16/12（约 53°）：
##   屏幕上：往北走一格，画面上移 ROW_H；升高一级，画面上移 ELEV_H。
##   深度：  越靠南（y 大）越近，越高也越近 ——  深度 ∝ y·ELEV_H + h·ROW_H。
##
## 深度公式里高度必须乘以 ROW_H 而不是随便一个小系数：视觉上一个身位的高度
## 与"往南走 ROW_H/ELEV_H 格"在屏幕上等价，权重必须和投影一致，否则站在坡上
## 的角色会被坡下的物体错误遮挡。

const TILE := 16       ## 一格多少像素（横向）
const ROW_H := 16      ## 一格多少像素（纵向）
const ELEV_H := 12     ## 每升高一级，画面上移多少像素
const MAX_H := 3


## 格坐标 → 该格"地面点"的屏幕坐标（未取整，调用方可自行 round）
static func world_to_screen(tx: float, ty: float, h: float) -> Vector2:
	return Vector2(tx * TILE, ty * ROW_H - h * ELEV_H)


## 景深键：值越大越靠近相机，绘制越晚（越覆盖前面的东西）
static func depth(ty: float, h: float) -> int:
	return int(ty * ELEV_H + h * ROW_H)


## 一整条地形波段的 z_index。波段 = 连续 4 行的烘焙贴图。
## 取 48b - 1 而不是 48b：波段内所有物件的深度都 >= 48b，
## 于是"自己站在自己的地面上"，而更靠南的波段会盖住它 —— 崖壁遮挡关系自然成立。
static func band_z(first_row: int) -> int:
	return int(first_row) * ELEV_H - 1


## 屏幕坐标 → 格坐标（用于鼠标拾取、调试）
static func screen_to_world(p: Vector2, h: float) -> Vector2:
	return Vector2(p.x / TILE, (p.y + h * ELEV_H) / ROW_H)
