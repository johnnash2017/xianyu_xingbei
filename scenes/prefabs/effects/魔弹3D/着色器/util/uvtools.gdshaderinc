vec2 uv_align(vec2 uv, int align_mode) {
	switch(align_mode){
		case 0: return vec2(uv.x, uv.y);
		case 1: return vec2(uv.y, uv.x);
		case 2: return vec2(1.0 - uv.x, uv.y);
		case 3: return vec2(1.0 - uv.y, uv.x);
	}
	return vec2(uv.x, uv.y);
}

vec2 uv_radial(vec2 uv){
	vec2 centered_uv = uv - vec2(0.5);
	float r = sqrt(pow(centered_uv.x,2.0)+pow(centered_uv.y,2.0));
	float theta = atan(centered_uv.x, centered_uv.y) / (2.0 * PI);
	return vec2(theta, r);
}

vec2 uv_rotate(vec2 uv, float angle)
{
	vec2 pivot = vec2(0.5,0.5);
	mat2 rotation = mat2(vec2(sin(angle), -cos(angle)),
						vec2(cos(angle), sin(angle)));

	uv -= pivot;
	uv = uv * rotation;
	uv += pivot;
	return uv;
}
