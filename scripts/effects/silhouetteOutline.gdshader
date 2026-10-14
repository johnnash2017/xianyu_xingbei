shader_type canvas_item;
// 白描边（沿「图形轮廓」外扩一圈）：给有透明边距的图素用 —— 例：战斗面板上的掉线标记 signal.png
// （512×512、四周透明，轮廓就是图形边缘）。
//
// 与同目录的 whiteOutline.gdshader 的区别：那份假设素材满幅不透明、图形轮廓等于控件边界，
// 于是沿边界内圈描；这份从「邻域有没有不透明像素」反推轮廓，不依赖控件尺寸。
//
// 做法：对每个像素取 8 个方向 × 2 个半径的透明度，只要邻域里有不透明像素、而自己本身透明，
// 就把这一格涂成描边色 —— 于是描边落在图素之外，图形本体颜色与 modulate 都不受影响。
// （标识符沿用工程里其他 shader 的 ASCII 写法，注释中文）
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// 描边宽度。单位是「源图素」：源图在屏幕上被缩得越小，描边就越细（见节点上的 scale）
uniform float outline_width : hint_range(0.0, 24.0) = 8.0;

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	// 还原 modulate（同 hitOutline / whiteOutline 的老办法）：面板置灰、选中染色都不丢
	vec3 mod_rgb = COLOR.rgb / max(base.rgb, vec3(0.02));
	float mod_a = COLOR.a / max(base.a, 0.02);
	// 八方向 × 两圈：外圈负责描边外沿、内圈把靠近图形的部分补满，单靠一圈会描成一条细虚线
	float around = 0.0;
	vec2 step_uv = TEXTURE_PIXEL_SIZE * outline_width;
	for (int i = 0; i < 8; i++) {
		float ang = float(i) * 0.7853981634;      // 2π/8
		vec2 dir = vec2(cos(ang), sin(ang));
		around = max(around, texture(TEXTURE, UV + dir * step_uv).a);
		around = max(around, texture(TEXTURE, UV + dir * step_uv * 0.5).a);
	}
	// 自己透明 + 邻域有不透明像素 = 这里该画描边（step(0.5, x)：x >= 0.5 取 1）
	float is_outline = step(0.5, around) * (1.0 - step(0.5, base.a));
	vec3 rgb = mix(base.rgb * mod_rgb, outline_color.rgb, is_outline);
	float a = max(base.a * mod_a, is_outline * outline_color.a);
	COLOR = vec4(rgb, a);
}
