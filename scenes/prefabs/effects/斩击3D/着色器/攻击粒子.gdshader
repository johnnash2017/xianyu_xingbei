shader_type spatial;
render_mode unshaded, cull_disabled, blend_add;

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
uniform bool align_noise = false;
uniform bool use_icon = false;
uniform sampler2D icon_texture;

group_uniforms Transparency;
uniform float edge_position : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float edge_hardness : hint_range(0.0, 1.0, 0.01) = 0.0;

void vertex() {
	// Called for every vertex the material is visible on.
}

void fragment() {
	float value = 0.0;
	
	if(!use_icon){
		vec2 centered_uv = UV * 2.0 - 1.0;
		
		float radius = length(centered_uv);
		
		vec2 scroll = align_noise ? TIME * vec2(noise_scroll.y, noise_scroll.x) : TIME * noise_scroll;
		vec2 scale = align_noise ? vec2(noise_scale.y, noise_scale.x) : noise_scale;
		
		vec2 noise_uv = UV * 0.5 * scale + COLOR.r;
		noise_uv += scroll * 0.5;
		float noise = texture(noise_texture, noise_uv).r;
		noise = pow(noise, noise_shape);
		
		value = max(noise - radius - (1.0 - COLOR.a), 0.0);
		
	} else {
		vec4 icon = texture(icon_texture, UV);
		
		value = icon.a * COLOR.a;
	}
	
	value = max(value - edge_position, 0.0);
	
	vec3 color = mix(secondary_color, primary_color, value);
	color = mix(tertiary_color, color, COLOR.a);
	
	ALBEDO = color;
	
	float alpha = clamp(value / (1.0 - edge_hardness), 0.0, 1.0);
	
	ALPHA = alpha;
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
