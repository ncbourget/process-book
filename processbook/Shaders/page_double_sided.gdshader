shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D front_tex : source_color;
uniform sampler2D back_tex : source_color;

void fragment() {
	vec4 col;

	if (FRONT_FACING) {
		vec2 front_uv = vec2(1.0 - UV.x, 1.0 - UV.y);
		col = texture(front_tex, front_uv);
	} else {
		vec2 back_uv = vec2(UV.x, 1.0 - UV.y);
		col = texture(back_tex, back_uv);
	}

	ALBEDO = col.rgb;
	ALPHA = col.a;
}