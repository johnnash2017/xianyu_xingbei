shader_type canvas_item;
// 受击震荡波：以命中点为中心向外扩散的一圈「画面扭曲」
// 波带内的像素按「朝外 / 朝内」偏移采样屏幕，看起来像一圈涟漪把画面推出去；
// 越接近波前越明显，进度越大越弱，最后靠 alpha 淡出。
// 注：着色器标识符沿用本工程其余 .gdshader 的 ASCII 风格（中文名在 Godot 着色器里不保证可解析）
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec2 center_uv = vec2(0.5, 0.5);   // 命中点（屏幕 UV）
uniform float aspect = 1.7777778;          // 屏幕 宽 / 高：把 UV 距离还原成近似等比，波才是圆的
uniform float progress = 0.0;              // 0→1：波前从中心推到最大半径
uniform float radius = 0.42;               // 波前最大半径（按屏幕高算的 UV 单位）
uniform float band = 0.055;                // 波带厚度
uniform float strength = 0.05;             // 波带内的最大位移（UV 单位）
uniform float fade = 1.0;                  // 整体透明度

void fragment() {
	// 把 UV 距离按长宽比拉正，得到以命中点为中心的「等比」位移
	vec2 offset = (SCREEN_UV - center_uv) * vec2(aspect, 1.0);
	float dist = length(offset);
	float front = progress * radius;
	// 只有落在波带里的像素才弯折（smoothstep 的边反过来写＝离波前越近越强）
	float in_band = smoothstep(band, 0.0, abs(dist - front));
	float amount = in_band * (1.0 - progress) * strength;
	vec2 dir = dist > 0.0001 ? offset / dist : vec2(0.0);
	// 朝波心外侧偏移采样＝画面被向外推出去
	vec4 col = texture(screen_tex, SCREEN_UV - dir * amount);
	COLOR = vec4(col.rgb, col.a * fade);
}
