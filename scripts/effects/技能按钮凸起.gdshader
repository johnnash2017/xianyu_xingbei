shader_type canvas_item;

// 技能按钮「凸起」：底色由着色器上色 —— 技能类型色（button_color，代码传入）× 样式灰度（常态 / 悬停 / 按下），
// 可选把它整体减淡；再沿受光边叠高光、背光边叠暗边，做出立体按钮的观感；还可沿按钮边界内侧画一圈白描边。
//
// 两种形状：
//   普通：圆角矩形，用「上/左受光、下/右背光」的轴对齐打光；
//   蜂窝（honeycomb）：整体宽度不变、上下平直、左右收成尖角；打光按「离得最近那条边朝向光源的程度」算，
//   所以尖角两侧的斜面也会正确受光 / 背光。
//
// 用顶点本地坐标（而非 UV）判断形状：StyleBoxFlat 带圆角 + 边框时会拆成多条绘制指令，
// 各自 UV 都是 0~1，用 UV 会算错；本地坐标 + rect_size 则与绘制指令无关。

uniform vec2 rect_size = vec2(110.0, 46.0);                   // 按钮尺寸（像素），由 SkillUI.gd 随尺寸刷新
uniform vec4 button_color : source_color = vec4(1.0, 1.0, 1.0, 1.0); // 按钮底色 = 技能类型色，由 SkillUI.gd 传入
uniform float lighten : hint_range(0.0, 1.0) = 0.0;           // 减淡：底色向白混合的比例（0 = 不动，1 = 全白）
uniform float edge_px : hint_range(1.0, 24.0) = 6.0;          // 高光 / 暗边的带宽（像素）
uniform float light_strength : hint_range(0.0, 1.0) = 0.5;    // 受光面加亮
uniform float shade_strength : hint_range(0.0, 1.0) = 0.5;    // 背光面压暗
uniform bool flip_light = false;                              // 翻转受光方向：勾上变成下、右受光，上、左背光

uniform bool honeycomb = false;                               // 蜂窝状：左右收成尖角
uniform float hex_slant : hint_range(0.0, 200.0) = 22.0;      // 蜂窝形上下平直段的左右缩进（像素），≈ 高度一半时接近正六边形
uniform float honeycomb_softness : hint_range(0.0, 24.0) = 6.0; // 蜂窝立体光在棱角处的过渡圆滑程度（只影响打光，不把棱角磨圆）

uniform float corner_radius : hint_range(0.0, 40.0) = 8.0;    // 与按钮圆角一致（非蜂窝时的白描边用）
uniform float outline_px : hint_range(0.0, 16.0) = 0.0;       // 白描边宽度（像素，0 = 不画）
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

varying vec2 local_pos;

void vertex() {
	// VERTEX = 节点本地像素坐标，控件左上角为 (0,0)
	local_pos = VERTEX;
}

// 圆角矩形有符号距离：p 相对矩形中心，b 半尺寸，r 圆角；矩形内为负、外为正
float rounded_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - r;
}

// 平滑取小（多项式）：k 越大过渡越圆滑，k→0 退化成 min。
// 蜂窝形用它合并各边的距离，顶点附近距离场连续，法线不突跳 → 没有折痕
float smin(float a, float b, float k) {
	float t = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, t) - k * t * (1.0 - t);
}

void fragment() {
	// 底色 = 技能类型色（button_color）× 样式的灰度：类型色负责颜色，样式灰度保留常态 / 悬停 / 按下的明暗差
	float lum = max(COLOR.r, max(COLOR.g, COLOR.b));
	vec4 base = vec4(button_color.rgb * lum, COLOR.a);
	// 减淡：底色向白混合；乘 base.a 使形状外的透明像素保持不变
	base.rgb = mix(base.rgb, vec3(1.0), lighten * base.a);

	if (honeycomb) {
		// 六边形 6 条边「到边的有符号距离」（内部为正）。都用真正的垂直距离（斜边除以法线长度），
		// 每条边的立体带才等宽，边与边相接处不会因距离尺度不同而错位。
		float hh = rect_size.y;
		float ww = rect_size.x;
		float sl = hex_slant;
		float diag = sqrt(hh * hh + 4.0 * sl * sl);
		float d_top = local_pos.y;
		float d_bottom = hh - local_pos.y;
		float d_ul = (hh * local_pos.x + 2.0 * sl * local_pos.y - sl * hh) / diag;
		float d_ll = (hh * local_pos.x - 2.0 * sl * local_pos.y + sl * hh) / diag;
		float d_ur = (hh * (ww - local_pos.x) + 2.0 * sl * local_pos.y - sl * hh) / diag;
		float d_lr = (hh * (ww - local_pos.x) - 2.0 * sl * local_pos.y + sl * hh) / diag;
		// 形状 / 描边用「硬 min」：六边形棱边保持尖角，不做圆角
		float inside = min(min(d_top, d_bottom), min(min(d_ul, d_lr), min(d_ll, d_ur)));
		// 裁形：形状外透明
		base.a *= smoothstep(-1.0, 1.0, inside);

		// 立体边：最近的边朝光源越正越亮、背光越正越暗。
		// 法线改从「平滑取小」的距离场取：棱角处法线连续过渡 → 没有折痕，且不动形状（尖角还在）
		float k = max(honeycomb_softness, 0.001);
		float inside_soft = smin(smin(smin(d_top, d_bottom, k), smin(d_ul, d_lr, k), k),
			smin(d_ll, d_ur, k), k);
		vec2 g = vec2(dFdx(inside_soft), dFdy(inside_soft));
		vec2 n = length(g) > 0.0001 ? normalize(g) : vec2(0.0);
		vec2 light_dir = normalize(flip_light ? vec2(1.0, 1.0) : vec2(-1.0, -1.0));
		float facing = dot(n, light_dir);
		float band = 1.0 - smoothstep(0.0, edge_px, inside);
		float strength = facing >= 0.0 ? light_strength : shade_strength;
		base.rgb = clamp(base.rgb + facing * strength * band * base.a, 0.0, 1.0);

		if (outline_px > 0.0) {
			float stroke = 1.0 - smoothstep(outline_px - 1.0, outline_px + 1.0, inside);
			base.rgb = mix(base.rgb, outline_color.rgb, stroke * outline_color.a * base.a);
		}
	} else {
		// 圆角矩形：上 / 左（lit→0）受光，下 / 右（dark→0）背光；flip_light 时两者对调
		float lit = clamp(min(local_pos.x, local_pos.y) / edge_px, 0.0, 1.0);
		float dark = clamp(min(rect_size.x - local_pos.x, rect_size.y - local_pos.y) / edge_px, 0.0, 1.0);
		float lit_amount = (1.0 - lit) * light_strength;
		float shade_amount = (1.0 - dark) * shade_strength;
		float shade = flip_light ? (shade_amount - lit_amount) : (lit_amount - shade_amount);
		// 乘 base.a：圆角外的透明像素保持不变，不把高光画到按钮外面
		base.rgb = clamp(base.rgb + shade * base.a, 0.0, 1.0);

		if (outline_px > 0.0) {
			vec2 half_size = rect_size * 0.5;
			float d = rounded_box(local_pos - half_size, half_size, corner_radius);
			// [-outline_px, 0] 为描边带；两侧各留 1px 过渡做抗锯齿
			float stroke = smoothstep(-outline_px - 1.0, -outline_px + 1.0, d) * (1.0 - smoothstep(-1.0, 1.0, d));
			base.rgb = mix(base.rgb, outline_color.rgb, stroke * outline_color.a * base.a);
		}
	}
	COLOR = base;
}
