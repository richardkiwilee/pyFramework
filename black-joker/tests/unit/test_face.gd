extends TestBase
## FaceDrawer 测试：52 张牌面两两唯一、牌面与牌背不同、底色/边框正确


func test_all_52_faces_unique() -> void:
	var seen := {}
	for card in CardData.all_cards():
		var img := FaceDrawer.render_face_image(card.suit, card.rank)
		seen[img.get_data()] = true
	assert_eq(seen.size(), 52, "52 张牌面两两不同")


func test_face_differs_from_back() -> void:
	var face := FaceDrawer.render_face_image(CardData.Suit.SPADES, CardData.Rank.ACE)
	var back := BackDrawer.render_back_image(CardData.Suit.SPADES, CardData.Rank.ACE)
	assert_true(face.get_data() != back.get_data(), "牌面与牌背不同")


func test_face_colors() -> void:
	var spade := FaceDrawer.render_face_image(CardData.Suit.SPADES, CardData.Rank.SEVEN)
	var heart := FaceDrawer.render_face_image(CardData.Suit.HEARTS, CardData.Rank.SEVEN)
	var p_spade := spade.get_pixel(3, 3)
	var p_heart := heart.get_pixel(3, 3)
	assert_eq(p_spade, Color("f2ead8"), "牌面象牙白底")
	assert_eq(p_heart, Color("f2ead8"), "牌面象牙白底")
	# 中央符号颜色：采样符号圆形瓣的圆心（心/桃两瓣之间有空隙，中心点不可用）
	var c_spade := spade.get_pixel(58, 107)
	var c_heart := heart.get_pixel(58, 89)
	assert_eq(c_spade, Color("16120d"), "黑桃中央符号为黑")
	assert_eq(c_heart, Color("c0392b"), "红桃中央符号为红")


func test_bitmap_text_renders() -> void:
	# 角标文字区有非底色像素（文字已画上）
	var img := FaceDrawer.render_face_image(CardData.Suit.SPADES, CardData.Rank.ACE)
	var has_ink := false
	for x in range(8, 30):
		for y in range(6, 26):
			if img.get_pixel(x, y) != Color("f2ead8"):
				has_ink = true
	assert_true(has_ink, "角标文字区域有墨色像素")


func test_texture_creation() -> void:
	var tex := FaceDrawer.face_texture(0, 1)
	assert_true(tex != null, "纹理创建成功")
	assert_eq(tex.get_width(), 140, "纹理宽 140")
