// 星空背景横向滚动 —— 贴图由材质传入，节点是纯 ColorRect（不带 texture）。
//
// 为什么用 ColorRect + 材质直传贴图：
//   TextureRect 自己会把贴图画一份，shader 里如果再采一次，就等于渲染了两份 ——
//   「一张在滚、一张静止」就是这么来的。ColorRect 不带贴图，画面完全由 shader 决定，
//   所以只会出现一份。
//
// 头尾过渡（这次改对的地方）：
//   和第 1 帧与第 N 帧重叠的循环动画一样处理 —— 让两个采样**恰好相隔一整张图**：
//       A = u        当前这一份
//       B = u - 1    前一份（负 uv 用 fract 绕回图尾）
//   fade 区内把 A 渐变到 B。淡化区末端 u = 1 时 B = 0，B 采到的正是「图头」，
//   与 A 在 u = 1 处的「图尾」对齐；循环绕回后 u = 0 采到的也是图头 ——
//   两边同值，接缝自然消失。
//
//   之前写错在：B 的采样被 clamp 在 [0,1]，越界后压到图边，和真内容对不上，
//   于是只有一侧有渐变、另一侧是硬边（就是你看到的那条线）。
//
// 采样全部用 fract 折回 [0,1]，所以贴图**不需要**开 Repeat，不依赖 .import 设置。
shader_type canvas_item;
render_mode unshaded;

// 星空贴图（由 StarBackgroundLayer.gd 在运行时灌入）
uniform sampler2D star_tex : filter_linear, repeat_disable;
// 每秒横向偏移多少 UV
uniform float speed = 0.02;
// 亮度增益（原图平均色只有 (4,41,79)，偏暗）
uniform float gain : hint_range(0.0, 4.0) = 2.2;
// 头尾交叉过渡占整张图的比例
uniform float fade : hint_range(0.02, 0.5) = 0.18;

// uv 折回 [0,1]：负值继续向左绕（取小数部分即可），y 夹紧
vec2 wrap_uv(vec2 uv) {
	return vec2(fract(uv.x), clamp(uv.y, 0.0, 1.0));
}

void fragment() {
	// 采样位置沿 x 匀速平移
	float u = UV.x + TIME * speed;
	vec3 c = texture(star_tex, wrap_uv(vec2(u, UV.y))).rgb;

	// fade 区内与「前一份」交叉淡化：两者相隔整张图，末端天然对齐
	float w = clamp((fract(u) - (1.0 - fade)) / fade, 0.0, 1.0);
	if (w > 0.0) {
		vec3 prev = texture(star_tex, wrap_uv(vec2(u - 1.0, UV.y))).rgb;
		c = mix(c, prev, w);
	}

	c = c * gain + c * c * 1.1;
	COLOR = vec4(c, 1.0);
}
