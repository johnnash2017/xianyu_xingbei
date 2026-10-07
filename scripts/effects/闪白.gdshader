shader_type canvas_item;
// 闪白：把「图形本身」按 flash 往白色推，透明处保持透明 —— 不能铺一层白色方块，
// 那样整格（连透明背景）都会白掉。用法：给格子套 ShaderMaterial，把 flash 从 1 淡到 0。
uniform float flash : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	// COLOR 进来时已经等于「贴图 × 节点 modulate」，只改 rgb、不动 alpha：
	// 透明像素 alpha 为 0，无论 rgb 怎么变都不会显示出来
	COLOR.rgb = mix(COLOR.rgb, vec3(1.0), flash);
}
