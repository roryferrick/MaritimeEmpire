# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name RegionMap
extends RefCounted
## Where each market region (markets.json regions) is on the globe: every
## point belongs to the region of its nearest port. Worked out once, on the
## GPU (scripts/ui/region_map.gdshader), into an image over longitude -180 to
## 180 and latitude 90 down to -90, each pixel's red its region's number (its
## index in the regions, plus 1). The map's shader shades locked regions from
## it (texture), and the map looks up the region under the mouse (region_at()).

const SIZE := Vector2i(2048, 1024)
const SHADER := preload("res://scripts/ui/region_map.gdshader")

static var texture: Texture2D = null
static var image: Image = null
static var _building := false
## Each region's middle (lon, lat), where its unlock button goes (see center()).
static var _centers: Array[Vector2] = []


## Works the image out (once, for every map), using a node in the tree to
## draw it. It's ready (texture and image set) a frame or two later.
static func build(host: Node) -> void:
	if image != null or _building:
		return
	_building = true
	var regions: Array = GameData.markets.get("regions", [])
	var ports := Image.create(GameData.ports.size(), 1, false, Image.FORMAT_RGBAF)
	for i in GameData.ports.size():
		var port: Dictionary = GameData.ports[i]
		var unit := _unit(Vector2(float(port.get("lon", 0.0)), float(port.get("lat", 0.0))))
		var index := regions.find(GameData.port_region(port.id))
		ports.set_pixel(i, 0, Color(unit.x, unit.y, unit.z, index + 1))
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"ports", ImageTexture.create_from_image(ports))
	material.set_shader_parameter(&"count", GameData.ports.size())
	var viewport := SubViewport.new()
	viewport.size = SIZE
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var canvas := ColorRect.new()
	canvas.size = SIZE
	canvas.material = material
	viewport.add_child(canvas)
	host.add_child(viewport)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	image = viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	viewport.queue_free()
	texture = ImageTexture.create_from_image(image)
	_building = false


static func is_ready() -> bool:
	return image != null


## The region (its index in markets.json regions) at a (lon, lat), or -1.
static func region_at(lon_lat: Vector2) -> int:
	if image == null:
		return -1
	var x := clampi(floori(fposmod(lon_lat.x + 180.0, 360.0) / 360.0 * SIZE.x), 0, SIZE.x - 1)
	var y := clampi(floori((90.0 - lon_lat.y) / 180.0 * SIZE.y), 0, SIZE.y - 1)
	return image.get_pixel(x, y).r8 - 1


static func region_id(index: int) -> String:
	var regions: Array = GameData.markets.get("regions", [])
	return str(regions[index].id) if index >= 0 and index < regions.size() else ""


static func index_of(region_id: String) -> int:
	var regions: Array = GameData.markets.get("regions", [])
	for i in regions.size():
		if regions[i].id == region_id:
			return i
	return -1


## A region's middle (lon, lat): the middle of its ports on the globe, or, if
## that falls in another region's area, the region's port nearest it.
## Vector2.INF until the image is ready.
static func center(index: int) -> Vector2:
	if image == null:
		return Vector2.INF
	if _centers.is_empty():
		for region: Dictionary in GameData.markets.get("regions", []):
			var sum := Vector3.ZERO
			for port_id: String in region.ports:
				sum += _unit(_port_lon_lat(port_id))
			var middle := _lon_lat(sum.normalized())
			if region_at(middle) != _centers.size():
				var nearest := INF
				for port_id: String in region.ports:
					var distance := Geo.distance_nm(middle, _port_lon_lat(port_id))
					if distance < nearest:
						nearest = distance
						middle = _port_lon_lat(port_id)
			_centers.append(middle)
	return _centers[index]


static func _port_lon_lat(port_id: String) -> Vector2:
	var port := GameData.get_port(port_id)
	return Vector2(float(port.get("lon", 0.0)), float(port.get("lat", 0.0)))


static func _unit(lon_lat: Vector2) -> Vector3:
	var lon := deg_to_rad(lon_lat.x)
	var lat := deg_to_rad(lon_lat.y)
	return Vector3(cos(lat) * cos(lon), cos(lat) * sin(lon), sin(lat))


static func _lon_lat(unit: Vector3) -> Vector2:
	return Vector2(rad_to_deg(atan2(unit.y, unit.x)), rad_to_deg(asin(clampf(unit.z, -1.0, 1.0))))
