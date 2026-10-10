// Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
// Wraps the map art (drawn in projected map coordinates, see Geo) round the
// globe: each point goes onto the unit sphere and is seen straight on from
// above the view's middle (MapView._orient()), in the map's own pixels. The
// far side is cut away, and the globe is shaded a little towards its edge,
// fading into a pale haze like the air seen edge on. Masked (the biomes), it
// is cut to the land as drawn into land_mask (MapView._land_mask). As the
// regions' overlay, it shades the locked market regions (RegionMap) and,
// while one is being chosen, outlines them and lights up the hovered one. As
// the sky, it draws the clouds (thicker where the real world is cloudier,
// drifting, faded as the map zooms in: cloud_alpha) and the storms in the
// same cloud, thick and dark: hurricanes, typhoons and cyclones wound into
// spiral bands round a dense core (with a clear eye once strong), other
// storms ragged masses of rain cloud.
shader_type canvas_item;

uniform vec3 east;
uniform vec3 north;
uniform vec3 toward;
uniform vec2 center;
uniform float radius;
uniform vec3 haze = vec3(0.72, 0.84, 1.0);
// The land colors (MapView.LAND_COLORS) span x -180 to 180 and y land_top down
// to -land_top (projected: Geo.MAX_LAT), worked out here from where a point is.
uniform float land_top = 179.4;
uniform bool masked = false;
// Snow on the land (the biomes, masked) beyond these latitudes (degrees from
// the equator; 999: none), north and south: see MapView._update_seasons().
uniform float snow_lat_north = 999.0;
uniform float snow_lat_south = 999.0;
uniform vec3 snow_color = vec3(0.93, 0.95, 0.97);
uniform sampler2D land_mask : filter_linear, repeat_disable, hint_default_white;
uniform bool regions = false;
uniform sampler2D region_map : filter_nearest, repeat_disable, hint_default_black;
// The ports, a texel each: their point on the sphere and region number (RegionMap).
uniform sampler2D region_ports : filter_nearest, hint_default_black;
// Bit i set: region i (RegionMap) is locked.
uniform int locked_mask = 0;
uniform int hovered = -1;
uniform bool choosing = false;
uniform vec4 shade_color = vec4(0.02, 0.03, 0.07, 0.6);
uniform vec4 hover_color = vec4(1.0, 0.78, 0.25, 0.45);
uniform vec4 border_color = vec4(1.0, 0.95, 0.8, 0.7);
uniform bool sky = false;
uniform float cloud_alpha = 1.0;
uniform float storm_alpha = 1.0;
uniform float time = 0.0;
// Up to 16 storms: [centre on the sphere, radius in radians] and [strength
// 0..1, 1 if tropical, 1 north of the equator (-1 south), a seed].
uniform int storm_count = 0;
uniform vec4 storm_a[16];
uniform vec4 storm_b[16];

varying float facing;
varying vec2 mask_uv;
varying vec2 lon_lat_uv;
varying vec3 sphere;

void vertex() {
	UV = vec2((VERTEX.x + 180.0) / 360.0, (land_top - VERTEX.y) / (2.0 * land_top));
	float lon = radians(VERTEX.x);
	float m = radians(VERTEX.y);
	// Web Mercator's northing m back to the latitude's cos and sin.
	float c = 1.0 / cosh(m);
	vec3 p = vec3(c * cos(lon), c * sin(lon), tanh(m));
	sphere = p;
	lon_lat_uv = vec2((VERTEX.x + 180.0) / 360.0, 0.5 - asin(tanh(m)) / PI);
	facing = dot(p, toward);
	VERTEX = center + radius * vec2(dot(p, east), -dot(p, north));
	mask_uv = VERTEX / (center * 2.0);
}

// The region at a point, exactly: the region of whichever is nearest of the
// nearest ports of the region map's four texels round it. x: the region
// (-1 for none); y: how much nearer its port is than the nearest other
// region's (1 if none is in reach), for drawing edges.
vec2 region_at(vec3 p, vec2 uv) {
	vec2 size = vec2(textureSize(region_map, 0));
	vec2 cell = floor(uv * size - 0.5);
	float best = -2.0;
	float region = -1.0;
	float closeness[4];
	float found[4];
	for (int k = 0; k < 4; k++) {
		int col = int(mod(cell.x + float(k % 2), size.x));
		int row = int(clamp(cell.y + float(k / 2), 0.0, size.y - 1.0));
		vec4 texel = texelFetch(region_map, ivec2(col, row), 0);
		int index = int(texel.g * 255.0 + 0.5) + int(texel.b * 255.0 + 0.5) * 256;
		vec4 port = texelFetch(region_ports, ivec2(index, 0), 0);
		closeness[k] = dot(p, port.xyz);
		found[k] = port.w - 1.0;
		if (closeness[k] > best) {
			best = closeness[k];
			region = found[k];
		}
	}
	float other = -2.0;
	for (int k = 0; k < 4; k++) {
		if (abs(found[k] - region) > 0.5) {
			other = max(other, closeness[k]);
		}
	}
	return vec2(region, other > -2.0 ? best - other : 1.0);
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(hash(i + vec3(0.0, 1.0, 0.0)), hash(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(hash(i + vec3(0.0, 0.0, 1.0)), hash(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(hash(i + vec3(0.0, 1.0, 1.0)), hash(i + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}

float fbm(vec3 p, int octaves) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < octaves; i++) {
		sum += amp * noise(p);
		p = p * 2.03 + vec3(1.7, -2.3, 0.9);
		amp *= 0.5;
	}
	return sum;
}

// The clouds here: [color, opacity].
vec4 clouds(vec3 p) {
	if (cloud_alpha <= 0.005) {
		return vec4(0.0);
	}
	float lat = degrees(asin(clamp(p.z, -1.0, 1.0)));
	vec3 q = p * 3.2 + vec3(time * 0.004, -time * 0.003, time * 0.0025);
	float warp = fbm(q * 1.6 + vec3(3.1, 7.7, 1.3), 3);
	float n = fbm(q + vec3(warp, -warp, warp) * 0.8, 5);
	// Cloudier along the equator and the storm tracks of the middle latitudes,
	// clearer over the subtropics' high pressure.
	float tropics = exp(-pow(lat / 8.0, 2.0));
	float storm_tracks = exp(-pow((abs(lat) - 55.0) / 13.0, 2.0));
	float dry = exp(-pow((abs(lat) - 24.0) / 7.0, 2.0));
	float threshold = 0.55 - 0.1 * tropics - 0.12 * storm_tracks + 0.07 * dry;
	float density = smoothstep(threshold, threshold + 0.16, n);
	vec3 color = mix(vec3(0.78, 0.81, 0.86), vec3(1.0), smoothstep(threshold, threshold + 0.3, n));
	return vec4(color, density * 0.82 * cloud_alpha);
}

// The storms here: [color, opacity].
vec4 storms(vec3 p) {
	float thickness = 0.0;
	for (int i = 0; i < 16; i++) {
		if (i >= storm_count) {
			break;
		}
		vec4 a = storm_a[i];
		vec4 b = storm_b[i];
		vec3 offset = p - a.xyz;
		float d = length(offset) / a.w;
		if (d > 1.2) {
			continue;
		}
		vec3 storm_east = normalize(cross(vec3(0.0, 0.0, 1.0), a.xyz) + vec3(0.00001, 0.0, 0.0));
		vec3 storm_north = cross(a.xyz, storm_east);
		vec2 local = vec2(dot(offset, storm_east), dot(offset, storm_north)) / a.w;
		float density;
		if (b.y > 0.5) {
			// Spiral bands winding into a dense core (anticlockwise in the north).
			float r = length(local);
			float angle = atan(local.y, local.x);
			float spiral = sin(3.0 * angle - b.z * 4.2 * log(r + 0.06) + b.z * time * 0.6 + b.w);
			float bands = smoothstep(-0.4, 0.7, spiral);
			float breakup = fbm(vec3(local * 4.0, b.w) + vec3(time * 0.02), 4);
			density = (1.0 - smoothstep(0.35, 1.05, r)) * mix(0.55, 1.0, bands) * mix(0.8, 1.25, breakup);
			density = max(density, (1.0 - smoothstep(0.1, 0.55, r)) * 0.98);
			if (b.x > 0.6) {
				density *= smoothstep(0.025, 0.08, r);  // The eye.
			}
		} else {
			// A ragged mass of rain cloud, longer east-west, its edge torn by the wind.
			vec2 l = local * vec2(0.75, 1.15);
			float tear = fbm(vec3(l * 2.4 + vec2(b.w), time * 0.01), 4) - 0.5;
			float r = length(l) + tear * 0.75;
			density = (1.0 - smoothstep(0.2, 1.0, r)) * mix(0.65, 1.15, fbm(vec3(l * 5.0 - vec2(b.w), time * 0.02), 4));
		}
		thickness = max(thickness, clamp(density * mix(0.5, 1.0, b.x), 0.0, 1.0));
	}
	vec3 color = mix(vec3(0.36, 0.38, 0.42), vec3(0.09, 0.1, 0.13), thickness);
	return vec4(color, smoothstep(0.02, 0.5, thickness) * 0.93 * storm_alpha);
}

void fragment() {
	if (facing < 0.0) {
		discard;
	}
	if (sky) {
		vec3 p = normalize(sphere);
		vec4 cloud = clouds(p);
		vec4 storm = storm_count > 0 ? storms(p) : vec4(0.0);
		float alpha = 1.0 - (1.0 - cloud.a) * (1.0 - storm.a);
		vec3 color = (storm.rgb * storm.a + cloud.rgb * cloud.a * (1.0 - storm.a)) / max(alpha, 0.0001);
		float edge = 1.0 - facing;
		COLOR = vec4(mix(color, haze, edge * edge * 0.3), alpha);
	} else if (regions) {
		vec2 found = region_at(normalize(sphere), lon_lat_uv);
		int region = int(round(found.x));
		vec4 color = vec4(0.0);
		if (region >= 0 && ((locked_mask >> region) & 1) == 1) {
			color = shade_color;
		}
		if (choosing) {
			if (region == hovered) {
				color = hover_color;
			}
			// An edge a pixel or two wide where the region changes.
			if (found.y < fwidth(found.y) * 1.5) {
				color = border_color;
			}
		}
		COLOR = color;
	} else {
		if (masked) {
			COLOR.a *= texture(land_mask, mask_uv).a;
			// Snow beyond the snow line, its edge a few degrees wide.
			float lat = degrees(asin(clamp(sphere.z / length(sphere), -1.0, 1.0)));
			float line = lat >= 0.0 ? snow_lat_north : snow_lat_south;
			float snow = smoothstep(line - 3.0, line + 1.0, abs(lat));
			COLOR.rgb = mix(COLOR.rgb, snow_color, snow * 0.9);
		}
		float edge = 1.0 - facing;
		COLOR.rgb = mix(COLOR.rgb * (0.82 + 0.18 * sqrt(facing)), haze, edge * edge * edge * 0.45);
	}
}
