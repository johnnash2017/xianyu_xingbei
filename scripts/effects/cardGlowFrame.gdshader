shader_type canvas_item;
// 卡牌边框外发光 —— 整圈由着色器画，不再依赖贴图的 alpha 渐变。
//
// 形状 = 沿卡面矩形向外的一圈光：紧贴卡面一段是实心，再往外平滑渐隐到 0。
// 距离是在真实像素上算的，所以无论框放大多少倍，四周的宽度和渐变都均匀一致
// （贴图版是按 UV 拉伸，放大以后渐变会跟着变形、外圈发虚）。
// 可选（绿）/ 弃牌询问（红）/ 选中（黄）三种状态共用这一个节点、同一套形状，
// 只有 glow_color 不同；宽度等参数由 CardUI 的 @export 下发。
// 卡面里侧不画：卡面自身若带圆角/透明边，免得透出底色。
// 边框节点是 ColorRect（底色透明、不参与画面），只是用来占出这块矩形，颜色一律由 glow_color 定。
// 不乘节点的 modulate：置灰的卡本来就不显示这个框（可见性由 CardUI 控制）。
uniform vec4 glow_color : source_color = vec4(0.0, 1.0, 0.024, 1.0);
// 卡面半宽（像素）与框带宽度（像素）—— 由脚本按当前卡牌尺寸下发
uniform vec2 face_half_px = vec2(65.0, 96.0);
uniform float band_px = 37.0;
// 卡面拐角半径（像素），框跟着卡面的拐角走（0 = 直角）
uniform float corner_px = 0.0;
// 实心段占整条框带的比例：0 = 纯渐变；0.35 = 内侧 35% 实心、其余渐隐
uniform float glow_core : hint_range(0.0, 0.95) = 0.35;
// 整体不透明度
uniform float glow_intensity : hint_range(0.0, 3.0) = 1.0;
// 渐隐曲线（横轴 = 实心段结束 → 框带外缘，纵轴 = 不透明度）：由 CardUI 的「框渐隐曲线」下发。
// 这条曲线决定透明度往外「涨」得多快 —— 两端拉平＝外缘收得慢、中间拉陡＝中段掉得快
uniform sampler2D fade_curve : hint_default_white;

void fragment() {
	// 以节点中心为原点的像素坐标（节点半宽 = 卡面半宽 + 框带宽）
	vec2 p = (UV - vec2(0.5)) * 2.0 * (face_half_px + vec2(band_px));
	// 圆角矩形有向距离：卡面边缘 = 0，向外为正
	vec2 q = abs(p) - (face_half_px - vec2(corner_px));
	float dist = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - corner_px;
	// t：0 = 卡面边缘，1 = 框带外缘
	float t = clamp(dist / max(band_px, 0.0001), 0.0, 1.0);
	float core = clamp(glow_core, 0.0, 0.95);
	// u：0 = 实心段刚结束，1 = 框带外缘（曲线只作用在这一段上）
	float u = clamp((t - core) / max(1.0 - core, 0.0001), 0.0, 1.0);
	float fade = texture(fade_curve, vec2(u, 0.5)).r;
	float alpha = fade * glow_intensity * step(0.0, dist);
	COLOR = vec4(glow_color.rgb, clamp(alpha, 0.0, 1.0));
}
