// Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
// Wraps the map art (drawn in projected map coordinates, see Geo) round the
// globe: each point goes onto the unit sphere and is seen straight on from
// above the view's middle (MapView._orient()), in the map's own pixels. The
// far side is cut away, and the globe is shaded a little towards its edge,
// fading into a pale haze like the air seen edge on. Masked (the biomes), it
// is cut to the land as drawn into land_mask (MapView._land_mask). As the
// regions' overlay, it shades the locked market regions (RegionMap) and,
// while one is being chosen, outlines them and lights up the hovered one.
shader_type canvas_item;

uniform vec3 east;
uniform vec3 north;
uniform vec3 toward;
uniform vec2 center;
uniform float radius;
uniform vec3 haze = vec3(0.72, 0.84, 1.0);
uniform bool masked = false;
uniform sampler2D land_mask : filter_linear, repeat_disable, hint_default_white;
uniform bool regions = false;
uniform sampler2D region_map : filter_nearest, repeat_disable, hint_default_black;
// Bit i set: region i (RegionMap) is locked.
uniform int locked_mask = 0;
uniform int hovered = -1;
uniform bool choosing = false;
uniform vec4 shade_color = vec4(0.02, 0.03, 0.07, 0.6);
uniform vec4 hover_color = vec4(1.0, 0.78, 0.25, 0.45);
uniform vec4 border_color = vec4(1.0, 0.95, 0.8, 0.7);

varying float facing;
varying vec2 mask_uv;
varying vec2 lon_lat_uv;

void vertex() {
	float lon = radians(VERTEX.x);
	float m = radians(VERTEX.y);
	// Web Mercator's northing m back to the latitude's cos and sin.
	float c = 1.0 / cosh(m);
	vec3 p = vec3(c * cos(lon), c * sin(lon), tanh(m));
	lon_lat_uv = vec2((VERTEX.x + 180.0) / 360.0, 0.5 - asin(tanh(m)) / PI);
	facing = dot(p, toward);
	VERTEX = center + radius * vec2(dot(p, east), -dot(p, north));
	mask_uv = VERTEX / (center * 2.0);
}

int region_at(vec2 uv) {
	return int(texture(region_map, uv).r * 255.0 + 0.5) - 1;
}

void fragment() {
	if (facing < 0.0) {
		discard;
	}
	if (regions) {
		int region = region_at(lon_lat_uv);
		vec4 color = vec4(0.0);
		if (region >= 0 && ((locked_mask >> region) & 1) == 1) {
			color = shade_color;
		}
		if (choosing) {
			if (region == hovered) {
				color = hover_color;
			}
			// An edge a pixel or two wide where the region changes.
			vec2 reach = fwidth(lon_lat_uv) * 1.5;
			if (region_at(lon_lat_uv + vec2(reach.x, 0.0)) != region || region_at(lon_lat_uv - vec2(reach.x, 0.0)) != region
					|| region_at(lon_lat_uv + vec2(0.0, reach.y)) != region || region_at(lon_lat_uv - vec2(0.0, reach.y)) != region) {
				color = border_color;
			}
		}
		COLOR = color;
	} else {
		if (masked) {
			COLOR.a *= texture(land_mask, mask_uv).a;
		}
		float edge = 1.0 - facing;
		COLOR.rgb = mix(COLOR.rgb * (0.82 + 0.18 * sqrt(facing)), haze, edge * edge * edge * 0.45);
	}
}
