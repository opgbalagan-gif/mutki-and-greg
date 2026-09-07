shader_type canvas_item;

varying vec4 sprite_tint;

void vertex() {
	sprite_tint = COLOR;
}

// The keyed footage contains low-alpha gray/green background around the body.
// Rebuild its coverage without changing the fully opaque illustrated details.
void fragment() {
	vec4 texel = texture(TEXTURE, UV);
	float body_alpha = smoothstep(0.35, 0.90, texel.a);
	// White motion trails are intentionally translucent, unlike the gray matte.
	float white_trail = smoothstep(0.72, 0.94, min(texel.r, min(texel.g, texel.b)));
	float trail_alpha = texel.a * white_trail * smoothstep(0.12, 0.40, texel.a);
	texel.a = max(body_alpha, trail_alpha);
	COLOR = texel * sprite_tint;
}
