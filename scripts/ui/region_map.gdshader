// Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
// Each market region's area (RegionMap): over the whole globe, longitude -180
// to 180 across and latitude 90 down to -90, every point takes the region of
// its nearest port along the globe. Red is the region's number (its index in
// markets.json regions, plus 1).
shader_type canvas_item;

// One texel per port: its point on the unit sphere, and its region's number.
uniform sampler2D ports : filter_nearest;
uniform int count;

void fragment() {
	float lon = (UV.x * 2.0 - 1.0) * PI;
	float lat = (0.5 - UV.y) * PI;
	vec3 p = vec3(cos(lat) * cos(lon), cos(lat) * sin(lon), sin(lat));
	float best = -2.0;
	float region = 0.0;
	for (int i = 0; i < count; i++) {
		vec4 port = texelFetch(ports, ivec2(i, 0), 0);
		float closeness = dot(p, port.xyz);
		if (closeness > best) {
			best = closeness;
			region = port.w;
		}
	}
	COLOR = vec4(region / 255.0, 0.0, 0.0, 1.0);
}
