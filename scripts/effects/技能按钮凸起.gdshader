shader_type canvas_item;

// 技能按钮「凸起」：不改变底色（片元里 COLOR = 样式底色 × modulate，主题/覆写的常态、悬停、按下都在里面），
// 只沿上、左边缘叠高光，下、右边缘叠暗边，做出立体按钮的观感。
//
// 用顶点本地坐标（而非 UV）判断到边缘的距离：StyleBoxFlat 带圆角 + 边框时会拆成多条绘制指令，
// 各自 UV 都是 0~1，用 UV 会算错；本地坐标 + rect_size 则与绘制指令无关。

uniform vec2 rect_size = vec2(110.0, 46.0);                   // 按钮尺寸（像素），由 SkillUI.gd 随尺寸刷新
uniform float edge_px : hint_range(1.0, 24.0) = 6.0;          // 高光 / 暗边的带宽（像素）
uniform float light_strength : hint_range(0.0, 1.0) = 0.5;    // 上、左受光加亮
uniform float shade_strength : hint_range(0.0, 1.0) = 0.5;    // 下、右背光压暗

varying vec2 local_pos;

void vertex() {
	// VERTEX = 节点本地像素坐标，控件左上角为 (0,0)
	local_pos = VERTEX;
}

void fragment() {
	vec4 base = COLOR;
	float lit = clamp(min(local_pos.x, local_pos.y) / edge_px, 0.0, 1.0);
	float dark = clamp(min(rect_size.x - local_pos.x, rect_size.y - local_pos.y) / edge_px, 0.0, 1.0);
	// 靠近上 / 左边缘 lit→0 加亮，靠近下 / 右边缘 dark→0 压暗
	float shade = (1.0 - lit) * light_strength - (1.0 - dark) * shade_strength;
	// 乘 base.a：圆角外的透明像素保持不变，不把高光画到按钮外面
	base.rgb = clamp(base.rgb + shade * base.a, 0.0, 1.0);
	COLOR = base;
}
