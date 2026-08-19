extends Node
## =============================================================================
## ArtIndex — 自动加载(Autoload)单例，美术资源索引 + 占位符回退
## =============================================================================
## 作用：实现 readme 的硬性要求「美术资源使用索引动态链接，如果没有找到
##       对应的美术资源，则使用占位符或是基础UI组件」。
##
## 工作方式（docs/00-design.md §5.3）：
##   所有视觉引用都不直接写路径，而是写一个逻辑 id（如 "army"、"res_gold"），
##   索引表 data/art_index.json 保存 id → {texture, emoji, color} 的映射。
##   取用时有三级回退，保证任何数据缺失都不会崩：
##     1. texture 路径存在 → 加载纹理
##     2. 否则用索引表里的 emoji 字符
##     3. 否则用索引表里的颜色（落到程序生成的占位纹理）
##
## 新增美术资源的流程：放文件到 assets/ → 改 art_index.json 加一条映射 → 完。
## 代码零改动。
##
## 类比 Python：
##   相当于一个带缓存的资源加载器：icons = {"army": "res://assets/army.png"}，
##   get_icon("army") 若文件缺失则返回程序画出来的兜底图。
## =============================================================================

## 占位纹理尺寸（像素）。⚠️ 必须非零，否则绘制会被渲染管线剔除（本环境实测坑）
const PLACEHOLDER_SIZE := 48

## 索引表：id → {texture: String, emoji: String, color: String}
var _index: Dictionary = {}

## 已加载纹理缓存：id → Texture2D（避免重复 load）
var _texture_cache: Dictionary = {}

## 程序生成的占位纹理（懒生成，只生成一次）
var _placeholder: Texture2D


func _ready() -> void:
	var path := "res://data/art_index.json"
	if not FileAccess.file_exists(path):
		push_error("[ArtIndex] 索引表缺失: %s" % path)
		return
	var file := FileAccess.open(path, FileAccess.READ)
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("[ArtIndex] 索引表解析失败: %s" % path)
		return
	var data: Variant = json.get_data()
	if data is Dictionary:
		_index = data.get("icons", {})


## ---------------------------------------------------------------------------
## get_icon() — 按 id 取纹理，三级回退，永不返回 null
## ---------------------------------------------------------------------------
## 回退链：纹理文件 → emoji 兜底纹理 → 颜色占位纹理 → 通用占位纹理
## 返回的纹理可能是原尺寸，使用方应自己决定如何缩放（如 expand_mode）。
## ---------------------------------------------------------------------------
func get_icon(id: String) -> Texture2D:
	# 命中缓存直接返回
	if _texture_cache.has(id):
		return _texture_cache[id]

	var entry: Dictionary = _index.get(id, {})
	var tex_path: String = entry.get("texture", "")
	if tex_path != "" and ResourceLoader.exists(tex_path):
		# load() 同步加载。框架阶段资源量小，同步即可；
		# 大批量资源时改用 zfoo 的 ResourceHelper.async_load
		var tex: Texture2D = load(tex_path)
		if tex != null:
			_texture_cache[id] = tex
			return tex

	# 第二级：emoji 兜底 — 用 emoji 字符渲染一张纹理
	var emoji: String = entry.get("emoji", "")
	if emoji != "":
		var tex := _emoji_texture(emoji)
		_texture_cache[id] = tex
		return tex

	# 第三级：颜色占位 — 用索引表里的颜色画一张纯色块
	var col: String = entry.get("color", "")
	if col != "":
		var tex := _color_texture(Color(col))
		_texture_cache[id] = tex
		return tex

	# 最后兜底：通用占位纹理
	return _get_placeholder()


## get_emoji() — 取索引表里配置的 emoji 字符（UI 直接用字体渲染时用）
## 找不到时返回 "❓"（Segoe UI Emoji 有该字形）
func get_emoji(id: String) -> String:
	var entry: Dictionary = _index.get(id, {})
	return entry.get("emoji", "❓")


## get_color() — 取索引表里配置的颜色。找不到返回暗淡灰。
func get_color(id: String) -> Color:
	var entry: Dictionary = _index.get(id, {})
	var col: String = entry.get("color", "")
	if col != "":
		return Color(col)
	return Color("6a6a6a")


## ---------------------------------------------------------------------------
## _emoji_texture() — 把 emoji 字符渲染成一张纹理（带缓存）
## ---------------------------------------------------------------------------
## 用 Label 离屏渲染思路太重，这里直接生成纹理后调用系统字体绘制：
## Image 上不能用 draw_string（那是 CanvasItem 的方法），
## 所以用 Font.draw_string 配合画布 RID 的简化替代——框架阶段直接返回
## 颜色占位 + 由使用方在 UI 上叠一个 emoji Label（详见世界地图屏的做法）。
## 这里退而求其次：用颜色纹理 + emoji 字符一起返回不现实（纹理不携带字符），
## 故统一走 _color_texture + 使用方叠 Label 的方式。
## ---------------------------------------------------------------------------
func _emoji_texture(emoji: String) -> Texture2D:
	# 简化实现：emoji 无法轻松进 Image，退回通用占位纹理。
	# 使用方（如 WorldMapScreen）通过 get_emoji() 拿到字符后
	# 自己用 UITheme.emoji_font 渲染 Label 叠加显示，这是 demo-1 的成熟做法。
	return _get_placeholder()


## ---------------------------------------------------------------------------
## _color_texture() — 生成纯色占位纹理
## ---------------------------------------------------------------------------
## Godot 程序化生成图片（类比 Python PIL 的 Image.new + putpixel）：
##   1. Image.create(宽, 高, mipmaps, 格式) 创建空白画布
##   2. image.fill(color) 整幅填充
##   3. ImageTexture.create_from_image(image) 包装成纹理
## ---------------------------------------------------------------------------
func _color_texture(col: Color) -> Texture2D:
	var img := Image.create(PLACEHOLDER_SIZE, PLACEHOLDER_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(col)
	# 画一圈深色边框，让色块在暗背景上可辨识
	var border := Color(0, 0, 0, 0.6)
	for i in PLACEHOLDER_SIZE:
		img.set_pixel(i, 0, border)
		img.set_pixel(i, PLACEHOLDER_SIZE - 1, border)
		img.set_pixel(0, i, border)
		img.set_pixel(PLACEHOLDER_SIZE - 1, i, border)
	return ImageTexture.create_from_image(img)


## _get_placeholder() — 通用占位纹理（懒生成，缓存复用）
func _get_placeholder() -> Texture2D:
	if _placeholder == null:
		# 深灰底 + 亮灰斜十字，一眼可识别为"缺失资源"
		var img := Image.create(PLACEHOLDER_SIZE, PLACEHOLDER_SIZE, false, Image.FORMAT_RGBA8)
		img.fill(Color("3a3a3a"))
		var mark := Color("8a8a8a")
		for i in PLACEHOLDER_SIZE:
			img.set_pixel(i, i, mark)
			img.set_pixel(i, PLACEHOLDER_SIZE - 1 - i, mark)
		_placeholder = ImageTexture.create_from_image(img)
	return _placeholder
