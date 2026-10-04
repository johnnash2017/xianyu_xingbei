shader_type canvas_item;

// 技能按钮「选中外发光」：沿按钮轮廓外侧画一圈柔和光晕，表示这个技能被点中了。
// 发光节点挂在「背景板」下面、比它大 glow_px，且在按钮之前绘制，所以只看得见按钮外侧那一圈。
// 轮廓形状跟着按钮走：honeycomb 勾上时按蜂窝形（左右尖角）外扩。

uniform vec2 rect_size = vec2(110.0, 44.0);                 // 内侧按钮尺寸（像素），由 SkillUI.gd 刷新
uniform float glow_px : hint_range(0.0, 40.0) = 12.0;       // 光晕外扩宽度（像素）
uniform float corner_radius : hint_range(0.0, 40.0) = 8.0;  // 与按钮圆角一致（非蜂窝时用）
uniform bool honeycomb = false;                             // 按钮为蜂窝形：轮廓改成左右尖角的六边形
uniform float hex_slant : hint_range(0.0, 200.0) = 22.0;    // 蜂窝形上下平直段的左右缩进（像素），与「凸起」保持一致
uniform vec4 glow_color : source_color = vec4(1.0, 0.86, 0.25, 1.0); // 黄色

varying vec2 local_pos;

void vertex() {
	// VERTEX = 节点本地像素坐标，左上角为 (0,0)
	local_pos = VERTEX;
}

// 圆角矩形有符号距离：p 相对矩形中心，b 半尺寸，r 圆角；矩形内为负、外为正
float rounded_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;
}

void fragment() {
	// d = 到按钮轮廓的有符号距离（内为负、外为正）
	float d;
	if (honeycomb) {
		// 按钮在本节点内占 [glow_px, glow_px] ~ [glow_px + rect_size]，先换算回按钮本地坐标
		vec2 p = local_pos - vec2(glow_px);
		float ratio = abs(p.y - rect_size.y * 0.5) / max(rect_size.y * 0.5, 0.001);
		float left_edge = hex_slant * ratio;
		float right_edge = rect_size.x - hex_slant * ratio;
		float inside = min(min(p.x - left_edge, right_edge - p.x), min(p.y, rect_size.y - p.y));
		d = -inside;
	} else {
		vec2 half_size = rect_size * 0.5;
		vec2 center = vec2(glow_px) + half_size;
		d = rounded_box(local_pos - center, half_size, corner_radius);
	}
	// 只画外侧：d>0 才有光晕，贴边最亮，向外 glow_px 处衰减到 0
	float t = clamp(1.0 - d / glow_px, 0.0, 1.0) * step(0.0, d);
	COLOR = vec4(glow_color.rgb, t * glow_color.a);
}
