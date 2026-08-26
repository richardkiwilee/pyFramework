extends TestBase
## BackDrawer 单元测试：编码恒等、52 张牌背两两唯一、放大渲染尺寸


func test_stud_count_matches_rank() -> void:
	for r in range(1, 14):
		assert_eq(BackDrawer.stud_count(r), r, "铆钉数等于点数")


func test_suit_tint_per_suit() -> void:
	var seen := {}
	for s in CardData.Suit.values():
		seen[BackDrawer.suit_tint(int(s)).to_html()] = true
	assert_eq(seen.size(), 4, "四种花色四种色调")


func test_all_52_backs_unique() -> void:
	# 渲染 52 张牌背，像素数据作 Dictionary 键去重（PackedByteArray 可作键）
	var seen := {}
	for card in CardData.all_cards():
		var img := BackDrawer.render_back_image(card.suit, card.rank)
		seen[img.get_data()] = true
	assert_eq(seen.size(), 52, "52 张牌背两两不同")


func test_same_suit_differs_by_rank() -> void:
	var img_a := BackDrawer.render_back_image(CardData.Suit.SPADES, CardData.Rank.ACE)
	var img_k := BackDrawer.render_back_image(CardData.Suit.SPADES, CardData.Rank.KING)
	assert_true(img_a.get_data() != img_k.get_data(), "同花色 A 与 K 牌背不同")


func test_same_rank_differs_by_suit() -> void:
	var seen := {}
	for s in CardData.Suit.values():
		var img := BackDrawer.render_back_image(int(s), CardData.Rank.SEVEN)
		seen[img.get_data()] = true
	assert_eq(seen.size(), 4, "同点数 4 花色牌背不同")


func test_magnified_scale() -> void:
	var img := BackDrawer.render_back_image(0, 1, 3)
	assert_eq(img.get_width(), 420, "3 倍放大宽 420")
	assert_eq(img.get_height(), 588, "3 倍放大高 588")


func test_texture_creation() -> void:
	var tex := BackDrawer.back_texture(0, 1)
	assert_true(tex != null, "纹理创建成功")
	assert_eq(tex.get_width(), 140, "纹理宽 140")
	# 缓存命中：再次取同一张应返回同一实例
	var tex2 := BackDrawer.back_texture(0, 1)
	assert_true(tex == tex2, "缓存命中")
