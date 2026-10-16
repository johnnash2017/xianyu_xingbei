shader_type spatial;
render_mode unshaded, cull_disabled;

uniform float effect_decay : hint_range(0.0, 1.0, 0.01) = 0.0;

group_uniforms Color;
uniform vec3 primary_color : source_color;
uniform vec3 secondary_color : source_color;
uniform vec3 tertiary_color : source_color;
uniform float emission = 2.0;

group_uniforms Noise;
uniform sampler2D noise_texture;
uniform vec2 noise_scale = vec2(1.0);
uniform vec2 noise_scroll = vec2(1.0, 0.0);
uniform float noise_shape = 1.0;

group_uniforms Pulse;
uniform float pulse_frequency = 1.0;
uniform float pulse_amount : hint_range(0.0, 1.0, 0.01) = 0.8;

group_uniforms Transparency;
uniform float edge_position : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float edge_hardness : hint_range(0.0, 1.0, 0.01) = 0.0;

void fragment() {
	float radius = length(UV * 2.0 - 1.0);
	
	float circle_mask = step(radius, 1.0);
	float slash = circle_mask * (pow(UV.x, 6.0) - (1.0 - radius) * 0.5);
	slash = clamp(slash, 0.0, 1.0);
	slash = smoothstep(0.0, 0.6, slash);
	
	float wave = sin(radius * TAU * pulse_frequency + (TIME * noise_scroll.x * TAU * pulse_frequency));
	wave = wave * circle_mask * max(UV.x * 2.0 - (2.0 - pulse_amount), 0.0);
	slash += abs(wave);
	
	float noise_mask = max(circle_mask, step(UV.x, 0.5));
	// 底数必须先夹到 >= 0：右半、圆外的那两个角上 (noise_mask - |2y-1|^4) 是负数，
	// 而 GLSL 的 pow(负数, 0.6) 是未定义行为 —— 换驱动/着色器编译器（编辑器用 D3D12、导出包回退
	// Vulkan 这类情况）就可能算成 NaN：NaN 顺着 noise_mask → value → ALPHA 一路传下去，
	// 那几个角最后被当不透明画出来，整条斩击看着就"糊成一个方块"。
	// 夹到 0 之后这些像素得到 value=0（透明），正是原本想要的结果；底数为正时不受影响。
	noise_mask = pow(max((noise_mask - pow(abs(UV.y * 2.0 - 1.0), 4.0)) * UV.x, 0.0), 0.6);
	
	
	vec2 noise_uv = UV * noise_scale + noise_scroll * TIME;
	float noise = texture(noise_texture, noise_uv).r;
	noise = pow(noise, noise_shape);
	
	float value = clamp(noise - (1.0 - noise_mask) + slash, 0.0, 1.0);
	value = max(value - effect_decay - edge_position, 0.0);
	
	float gradient = clamp(circle_mask + step(UV.x, 0.5), 0.0, 1.0) * pow(UV.x, 4.0);
	gradient = max(gradient - effect_decay, 0.0);
	
	vec3 color = mix(secondary_color, primary_color, value);
	color = max(color, tertiary_color);
	
	ALBEDO = color * emission;
	
	float alpha = max(value, gradient * 0.2);
	alpha = clamp(alpha / (1.0 - edge_hardness), 0.0, 1.0);
	alpha = max(alpha - effect_decay, 0.0);
	
	ALPHA = alpha;
}