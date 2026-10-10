shader_type canvas_item;
// 卡牌「可选」发光框换色：贴图本身是纯色（b02_selected_card.png 是纯绿 0,255,6），
// 用 modulate 只能把它乘暗、乘不出红色，所以这里直接把颜色整体换成 glow_color；
// 只保留贴图自身的透明度（发光框的渐变）与节点自身的 modulate（卡牌置灰靠它）。
uniform vec4 glow_color : source_color = vec4(0.0, 1.0, 0.024, 1.0);

void fragment() {
	// COLOR 进来时 = 贴图 × modulate；取最大通道还原「亮暗」（白 modulate 为 1，置灰 0.5 时为 0.5）
	float lum = max(COLOR.r, max(COLOR.g, COLOR.b));
	COLOR = vec4(glow_color.rgb * lum, COLOR.a);
}
