shader_type canvas_item;
// 白描边：沿图标四周向内画一圈白边。
// 素材是满幅的（整张 20×20 一个透明像素都没有），图标的外轮廓就是控件边界，
// 所以不缩内容、直接沿边界内圈描边 —— 这样图标与图标之间不会留出任何缝（相邻图标直接相接）。
// 注意：Godot 的着色器不允许在 fragment 里用 return，分支只能写成 if / else
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 0.5);
uniform float outline_width : hint_range(0.0, 8.0) = 0.5;

void fragment() {
	// COLOR 进来时已经是「贴图 × 节点 modulate」，按受击描边的老办法还原出 modulate，
	// 这样面板置灰 / 选中染色的效果不会被这里丢掉
	vec4 t0 = texture(TEXTURE, UV);
	vec3 mod_rgb = COLOR.rgb / max(t0.rgb, vec3(0.02));
	float mod_a = COLOR.a / max(t0.a, 0.02);
	// 到最近边界（上下左右哪边都算）的距离，单位是「描边宽度」；<= 1 就是边缘那一圈
	vec2 px = max(TEXTURE_PIXEL_SIZE * outline_width, vec2(0.0001));
	vec2 to_edge = min(UV, vec2(1.0) - UV);
	float dist = min(to_edge.x / px.x, to_edge.y / px.y);
	float edge_mix = dist <= 1.0 ? outline_color.a : 0.0;
	COLOR = vec4(mix(t0.rgb * mod_rgb, outline_color.rgb, edge_mix), t0.a * mod_a);
}
