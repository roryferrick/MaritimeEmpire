// Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
// Night over the globe (MapView._update_night()): a full-view rect over the
// map art, land drawings, marinas, ships and birds that darkens the side of
// the globe turned away from the sun, with dusk and dawn a soft band between.
// Each pixel's point on the sphere is worked out as MapView._unit_to_screen()
// does it in reverse; off the globe, nothing. The lights (ships, lighthouses,
// marina entrances, port towns) are drawn over this (MapView._draw_lights()).
shader_type canvas_item;

uniform vec3 east;
uniform vec3 north;
uniform vec3 toward;
// The globe's middle (px, in the map's own coordinates) and radius (px).
uniform vec2 center;
uniform float radius = 1.0;
// Towards the sun (the sub-solar point on the unit sphere).
uniform vec3 sun = vec3(1.0, 0.0, 0.0);
// How much of what's under is lost at the darkest (1: all).
uniform float darkness = 0.93;
uniform vec3 tint = vec3(0.015, 0.025, 0.06);

varying vec2 local;

void vertex() {
	local = VERTEX;
}

void fragment() {
	vec2 q = (local - center) / radius;
	q.y = -q.y;
	float rr = dot(q, q);
	if (rr > 1.0) {
		COLOR = vec4(0.0);
	} else {
		vec3 p = q.x * east + q.y * north + sqrt(1.0 - rr) * toward;
		float day = smoothstep(-0.14, 0.1, dot(p, sun));
		COLOR = vec4(tint, (1.0 - day) * darkness);
	}
}
