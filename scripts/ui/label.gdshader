// The map's labels from their atlas (see LabelAtlas): the texture holds each
// label's coverage (white on black), the quad's tint its colour.
shader_type canvas_item;
render_mode blend_mix;

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	COLOR = vec4(tint.rgb, tint.a * texture(TEXTURE, UV).r);
}
