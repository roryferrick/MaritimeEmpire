// The fleet's lanes as one mesh on the globe (see LanePainter.build_mesh()
// and MapView._draw_active_lanes()): each vertex carries its lane point's
// longitude and latitude (radians) and the way the ribbon runs there (UV: x
// its bearing, radians from east towards north; y how far a mitred corner
// reaches out), and is put on screen here from the view's basis, so dragging
// the map costs the lanes nothing but a few uniforms. A pair of vertices a
// point (VERTEX_ID even and odd) make the ribbon, half_px wide each side (the
// last pixel a feather); the sides come from the bearing alone, so a sharp
// turn can't swap a quad's corners (no triangle of the line goes missing).
shader_type canvas_item;
render_mode blend_mix;

uniform vec3 right = vec3(1.0, 0.0, 0.0);
uniform vec3 up = vec3(0.0, 0.0, 1.0);
uniform vec3 toward = vec3(0.0, 1.0, 0.0);
uniform float radius = 100.0;
uniform vec2 middle = vec2(0.0);
uniform float half_px = 1.75;

varying float across;
varying float hidden;

vec3 unit_of(vec2 lon_lat) {
	float c = cos(lon_lat.y);
	return vec3(c * cos(lon_lat.x), c * sin(lon_lat.x), sin(lon_lat.y));
}

// A point on screen; past the globe's edge, pushed to the edge (and marked).
vec2 project(vec3 u, out float behind) {
	float facing = dot(u, toward);
	behind = facing < 0.0 ? 1.0 : 0.0;
	vec2 s = vec2(dot(u, right), -dot(u, up));
	if (facing < 0.0) {
		float len = length(s);
		s = len > 0.00001 ? s / len : vec2(1.0, 0.0);
	}
	return middle + s * radius;
}

void vertex() {
	float behind;
	vec2 sp = project(unit_of(VERTEX), behind);
	// The way it runs, on the globe (east and north at the point) and so on screen.
	vec3 east = vec3(-sin(VERTEX.x), cos(VERTEX.x), 0.0);
	vec3 north = vec3(-sin(VERTEX.y) * cos(VERTEX.x), -sin(VERTEX.y) * sin(VERTEX.x), cos(VERTEX.y));
	vec3 way = cos(UV.x) * east + sin(UV.x) * north;
	vec2 dir = vec2(dot(way, right), -dot(way, up));
	float len = length(dir);
	vec2 n = len > 0.0001 ? vec2(-dir.y, dir.x) / len : vec2(0.0);
	float side = (VERTEX_ID % 2 == 0) ? -1.0 : 1.0;
	VERTEX = sp + n * side * half_px * UV.y;
	across = side;
	hidden = behind;
}

void fragment() {
	COLOR.a *= clamp((1.0 - abs(across)) * half_px, 0.0, 1.0) * (1.0 - hidden);
}
