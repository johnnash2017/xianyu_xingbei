shader_type canvas_item;

// 技能按钮「选中外发光」：沿按钮轮廓外侧画一圈柔和光晕，表示这个技能被点中了。
// 发光节点挂在「背景板」下面、比它大 glow_px，且在按钮之前绘制，所以只看得见按钮外侧那一圈。
// 轮廓形状跟着按钮走：honeycomb 勾上时按蜂窝形（上下平直、左右尖角）外扩。

uniform vec2 rect_size = vec2(110.0, 44.0);                 // 内侧按钮尺寸（像素），由 SkillUI.gd 刷新
uniform float glow_px : hint_range(0.0, 40.0) = 20.0;       // 光晕外扩宽度（像素）
uniform float corner_radius : hint_range(0.0, 40.0) = 8.0;  // 与按钮圆角一致（非蜂窝时用）
uniform bool honeycomb = false;                             // 按钮为蜂窝形：轮廓改成左右尖角的六边形
uniform float hex_slant : hint_range(0.0, 200.0) = 22.0;    // 蜂窝形上下平直段的左右缩进（像素），与「凸起」保持一致
uniform vec4 glow_color : source_color = vec4(1.0, 0.87, 0.28, 0.8); // 黄色（略带透明，贴轮廓处也不会白到过曝）
uniform sampler2D fade_curve : hint_default_black;          // 透明度曲线：横轴＝离轮廓的距离（0＝贴边，1＝glow_px 处），纵轴＝透明度

varying vec2 local_pos;


// 平滑取小：棱角处的距离场不出现折线（同「凸起」着色器里那套）
float smin(float a, float b, float k) {
	float t = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, t) - k * t * (1.0 - t);
}


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
		float hh = rect_size.y;
		float ww = rect_size.x;
		float diag = sqrt(hh * hh + 4.0 * hex_slant * hex_slant);
		// 六条边各自的有符号距离（内侧为正），公式与「凸起」着色器完全一致
		float d_top = p.y;
		float d_bottom = hh - p.y;
		float d_ul = (hh * p.x + 2.0 * hex_slant * p.y - hex_slant * hh) / diag;
		float d_ll = (hh * p.x - 2.0 * hex_slant * p.y + hex_slant * hh) / diag;
		float d_ur = (hh * (ww - p.x) + 2.0 * hex_slant * p.y - hex_slant * hh) / diag;
		float d_lr = (hh * (ww - p.x) - 2.0 * hex_slant * p.y + hex_slant * hh) / diag;
		// 用「平滑取小」而不是硬 min：硬 min 在棱角外侧算出的距离偏小，
		// 光晕会在角上鼓出来一块（看着就是折痕），平滑后角上过渡成圆滑外扩
		float k = max(glow_px * 0.5, 0.001);
		float inside = smin(smin(smin(d_top, d_bottom, k), smin(d_ul, d_lr, k), k), smin(d_ll, d_ur, k), k);
		d = -inside;
	} else {
		vec2 half_size = rect_size * 0.5;
		vec2 center = vec2(glow_px) + half_size;
		d = rounded_box(local_pos - center, half_size, corner_radius);
	}
	// 实心发光：按钮底下也整块铺满（内圈被按钮自己挡住，正好把轮廓误差漏出来的缝补掉），
	// 只在按钮外按曲线渐隐。曲线的横轴 0＝贴着轮廓、1＝glow_px 处，所以直接拿归一化距离采样
	// （内部 d<0 会被 clamp 成 0，也就是实心满亮）
	float fade = clamp(d / glow_px, 0.0, 1.0);
	float t = texture(fade_curve, vec2(fade, 0.5)).a;
	COLOR = vec4(glow_color.rgb, t * glow_color.a);
}
