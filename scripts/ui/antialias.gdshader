// Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
// Antialiasing over the map (MapView._antialias, Settings.antialias): a
// full-view rect under the map's labels, ships and birds that smooths jagged edges in
// one pass over what's on screen. The Compatibility renderer has no 2D MSAA
// and no FXAA, so it's done here, as cheaply as it can be: each pixel first
// looks at itself and its four neighbours, and most (flat colour, no edge)
// stop there. On an edge, the 3x3 round it gives the edge's direction
// (Sobel), and the pixel is blended with `span` pixels along the edge (3, 5
// or 9: low, medium, high), tent-weighted, more where the edge is stronger.
// Along a staircase that turns its steps into a ramp; a straight edge or a
// thin line along it is left as it is.
shader_type canvas_item;

uniform sampler2D screen : hint_screen_texture, filter_linear;
// Pixels blended along an edge (odd: 3, 5 or 9).
uniform int span = 3;
// The least contrast (luma, 0 to 1) that counts as an edge, and the share of
// the brightest neighbour's luma it must also reach (FXAA's thresholds).
const float EDGE_MIN = 0.0312;
const float EDGE_SHARE = 0.125;

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec2 uv = SCREEN_UV;
	vec3 c = textureLod(screen, uv, 0.0).rgb;
	float lc = luma(c);
	float ln = luma(textureLod(screen, uv + vec2(0.0, -px.y), 0.0).rgb);
	float ls = luma(textureLod(screen, uv + vec2(0.0, px.y), 0.0).rgb);
	float le = luma(textureLod(screen, uv + vec2(px.x, 0.0), 0.0).rgb);
	float lw = luma(textureLod(screen, uv + vec2(-px.x, 0.0), 0.0).rgb);
	float most = max(lc, max(max(ln, ls), max(le, lw)));
	float range = most - min(lc, min(min(ln, ls), min(le, lw)));
	COLOR = vec4(c, 1.0);
	if (range >= max(EDGE_MIN, most * EDGE_SHARE)) {
		float lnw = luma(textureLod(screen, uv + vec2(-px.x, -px.y), 0.0).rgb);
		float lne = luma(textureLod(screen, uv + vec2(px.x, -px.y), 0.0).rgb);
		float lsw = luma(textureLod(screen, uv + vec2(-px.x, px.y), 0.0).rgb);
		float lse = luma(textureLod(screen, uv + vec2(px.x, px.y), 0.0).rgb);
		vec2 g = vec2((lne + 2.0 * le + lse) - (lnw + 2.0 * lw + lsw),
			(lsw + 2.0 * ls + lse) - (lnw + 2.0 * ln + lne));
		float strength = length(g);
		if (strength > 0.0001) {
			vec2 along = vec2(-g.y, g.x) / strength * px;
			int half_span = span / 2;
			float w0 = float(half_span + 1);
			vec3 sum = c * w0;
			float weights = w0;
			for (int k = 1; k <= half_span; k++) {
				float w = float(half_span + 1 - k);
				sum += (textureLod(screen, uv + along * float(k), 0.0).rgb
					+ textureLod(screen, uv - along * float(k), 0.0).rgb) * w;
				weights += 2.0 * w;
			}
			COLOR.rgb = mix(c, sum / weights, smoothstep(0.0, 0.25, range));
		}
	}
}
