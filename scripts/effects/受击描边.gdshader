shader_type canvas_item;
// 受击描边：只把方块贴图自带的那圈深色描边染成红色，方块填充色不动。
// mix_amount = 1 时描边全红、0 时保持原样；受击时由代码把它从 1 淡回 0。
// 描边像素约为 (44,45,45)，各填充色都明显更亮（绿 124,190,81 / 红 190,81,81 /
// 蓝 83,167,222 / 空位 66,66,68）—— 用「最大通道」卡在 0.22 一带就能把描边和填充分开。
//
// 注意：fragment 进来的 COLOR 已经等于「贴图 × 节点自身的 modulate」（面板置灰 / 选中染色都靠它），
// 直接整个覆盖 COLOR 会让方块不再跟着置灰。这里用 COLOR / 贴图 还原出 modulate，
// 给新染的红描边乘上同一份，置灰时红描边才会一起变暗。
uniform vec4 outline_color : source_color = vec4(1.0, 0.25, 0.25, 1.0);
uniform float mix_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	float maxc = max(t.r, max(t.g, t.b));
	float is_outline = 1.0 - smoothstep(0.195, 0.245, maxc);
	vec3 modulate_rgb = COLOR.rgb / max(t.rgb, vec3(0.02));
	COLOR.rgb = mix(COLOR.rgb, outline_color.rgb * modulate_rgb, is_outline * mix_amount);
}
