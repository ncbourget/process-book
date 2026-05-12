extends Node3D

@export var page_scene: PackedScene
@export var pages_container_path: NodePath

# Web-safe: drag your page images here in order.
@export var page_textures: Array[Texture2D] = []

@export var page_thickness: float = 0.00005
@export var turned_page_angle_step: float = -0.2

# Camera zoom
@export var camera_rig: Node3D
@export var camera: Camera3D
@export_range(0.0, 1.0, 0.001) var zoom: float = 0.0
@export var zoom_scroll_sensitivity: float = 0.08
@export var zoom_smooth_speed: float = 12.0
@export var zoom_close_distance: float = 0.22
@export var zoom_plane_y: float = 0.0

# Fan mode
@export var fan_angle_range_degrees: float = 160.0
@export var fan_lift: float = 0.03
@export var fan_anim_time: float = 0.35
@export var fan_direction: float = 1.0
@export var fan_hover_radius_px: float = 120.0

@onready var pages_container: Node3D = get_node(pages_container_path) as Node3D

var sheets: Array[BookPage] = []
var current_sheet_index: int = 0

var is_dragging: bool = false
var drag_page: BookPage = null
var drag_target_left: bool = false

var is_fan_mode: bool = false
var fan_hovered_index: int = -1

var zoom_target: float = 0.0
var zoom_focus: Vector3 = Vector3.ZERO
var base_camera_pos: Vector3 = Vector3.ZERO
var base_camera_rot: Vector3 = Vector3.ZERO


func _ready() -> void:
	if camera == null:
		camera = get_viewport().get_camera_3d()

	if camera_rig == null and camera != null:
		camera_rig = camera

	if camera_rig != null:
		base_camera_pos = camera_rig.global_position
		base_camera_rot = camera_rig.rotation

	zoom_target = zoom
	zoom_focus = global_position

	build_book()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE and not is_fan_mode:
			flip_current_sheet_forward()
		elif event.keycode == KEY_F:
			toggle_fan_mode()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton

		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			commit_zoom_focus(mouse_event.position)
			zoom_target = clamp(zoom_target + zoom_scroll_sensitivity, 0.0, 1.0)
			return

		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			commit_zoom_focus(mouse_event.position)
			zoom_target = clamp(zoom_target - zoom_scroll_sensitivity, 0.0, 1.0)
			return

	if is_fan_mode:
		if event is InputEventMouseButton:
			var mb: InputEventMouseButton = event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
				var clicked_index: int = get_fan_page_from_mouse(mb.position)
				if clicked_index != -1:
					jump_to_sheet(clicked_index)
		return

	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				start_drag(mouse_event.position)
			else:
				end_drag()


func _process(delta: float) -> void:
	update_zoom(delta)

	if is_fan_mode:
		fan_hovered_index = get_fan_page_from_mouse(get_viewport().get_mouse_position())
		return

	if is_dragging and drag_page != null:
		update_drag()


func build_book() -> void:
	for child: Node in pages_container.get_children():
		child.queue_free()

	sheets.clear()
	current_sheet_index = 0
	is_dragging = false
	drag_page = null
	drag_target_left = false
	is_fan_mode = false
	fan_hovered_index = -1

	if page_textures.is_empty():
		push_error("No page textures assigned. Drag your exported page images into the Page Textures array on the Book node.")
		return

	if page_textures.size() % 2 != 0:
		page_textures.append(make_blank_texture())

	var sheet_count: int = page_textures.size() / 2

	for i: int in range(sheet_count):
		var sheet_instance: Node = page_scene.instantiate()
		if sheet_instance == null:
			push_error("Could not instantiate page scene.")
			return

		var sheet: BookPage = sheet_instance as BookPage
		if sheet == null:
			push_error("The page scene root is not a BookPage. Make sure page.gd is attached to the Page scene root.")
			return

		pages_container.add_child(sheet)
		sheet.name = "Sheet_%03d" % i
		sheet.position = Vector3(0.0, 0.0, -float(i) * page_thickness)

		var front_tex: Texture2D = page_textures[i * 2]
		var back_tex: Texture2D = page_textures[i * 2 + 1]

		sheet.page_index = i
		sheet.turned_angle_offset_degrees = float(i) * turned_page_angle_step
		sheet.turn_to_right()
		sheet.set_textures(front_tex, back_tex)

		sheets.append(sheet)

	normalize_current_sheet_index()


func commit_zoom_focus(mouse_pos: Vector2) -> void:
	if camera == null:
		return

	var ray_origin: Vector3 = camera.project_ray_origin(mouse_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(mouse_pos)

	if abs(ray_dir.y) < 0.00001:
		return

	var t: float = (zoom_plane_y - ray_origin.y) / ray_dir.y
	if t < 0.0:
		return

	zoom_focus = ray_origin + ray_dir * t


func update_zoom(delta: float) -> void:
	if camera_rig == null:
		return

	var smooth: float = 1.0 - exp(-zoom_smooth_speed * delta)
	zoom = lerp(zoom, zoom_target, smooth)

	var dir_from_focus: Vector3 = base_camera_pos - zoom_focus
	if dir_from_focus.length() < 0.001:
		return

	var close_pos: Vector3 = zoom_focus + dir_from_focus.normalized() * zoom_close_distance
	var desired_pos: Vector3 = base_camera_pos.lerp(close_pos, zoom)

	camera_rig.global_position = camera_rig.global_position.lerp(desired_pos, smooth)
	camera_rig.rotation.x = lerp_angle(camera_rig.rotation.x, base_camera_rot.x, smooth)
	camera_rig.rotation.y = lerp_angle(camera_rig.rotation.y, base_camera_rot.y, smooth)
	camera_rig.rotation.z = lerp_angle(camera_rig.rotation.z, base_camera_rot.z, smooth)


func flip_current_sheet_forward() -> void:
	var index: int = get_next_right_sheet_index()
	if index == -1:
		return

	var sheet: BookPage = sheets[index]
	sheet.animate_to_left()
	current_sheet_index = index + 1
	normalize_current_sheet_index()


func start_drag(mouse_pos: Vector2) -> void:
	if sheets.is_empty() or is_dragging:
		return

	var screen_width: float = get_viewport().get_visible_rect().size.x
	if screen_width <= 0.0:
		return

	var clicked_left_side: bool = mouse_pos.x < screen_width * 0.5

	if clicked_left_side:
		var left_index: int = get_previous_left_sheet_index()
		if left_index == -1:
			return
		drag_page = sheets[left_index]
		drag_target_left = false
	else:
		var right_index: int = get_next_right_sheet_index()
		if right_index == -1:
			return
		drag_page = sheets[right_index]
		drag_target_left = true

	is_dragging = true


func update_drag() -> void:
	if drag_page == null:
		return

	var mouse_x: float = get_viewport().get_mouse_position().x
	var screen_width: float = get_viewport().get_visible_rect().size.x

	if screen_width <= 0.0:
		return

	var t: float = mouse_x / screen_width
	t = clamp(t, 0.0, 1.0)

	var progress: float = 1.0 - t
	drag_page.set_turn_progress(progress)


func end_drag() -> void:
	if not is_dragging or drag_page == null:
		return

	var open_angle: float = abs(drag_page.get_open_angle_rad())
	var hinge_rot: float = 0.0

	match drag_page.hinge_axis:
		"x":
			hinge_rot = abs(drag_page.hinge.rotation.x)
		"y":
			hinge_rot = abs(drag_page.hinge.rotation.y)
		"z":
			hinge_rot = abs(drag_page.hinge.rotation.z)

	var opened_far_enough: bool = hinge_rot > open_angle * 0.5

	if opened_far_enough:
		drag_page.animate_to_left()
		current_sheet_index = drag_page.page_index + 1
	else:
		drag_page.animate_to_right()
		current_sheet_index = drag_page.page_index

	normalize_current_sheet_index()

	is_dragging = false
	drag_page = null
	drag_target_left = false


func toggle_fan_mode() -> void:
	if is_fan_mode:
		exit_fan_mode()
	else:
		enter_fan_mode()


func enter_fan_mode() -> void:
	if sheets.is_empty():
		return

	is_fan_mode = true
	is_dragging = false
	drag_page = null
	drag_target_left = false

	var count: int = sheets.size()
	if count <= 0:
		return

	for i: int in range(count):
		var sheet: BookPage = sheets[i]
		var tween: Tween = create_tween()

		var t: float = 0.5
		if count > 1:
			t = float(i) / float(count - 1)

		var angle_deg: float = lerp(fan_angle_range_degrees * 0.5, -fan_angle_range_degrees * 0.5, t)
		var angle_rad: float = deg_to_rad(angle_deg) * fan_direction

		var target_pos: Vector3 = Vector3(
			0.0,
			fan_lift,
			-float(i) * page_thickness
		)

		tween.parallel().tween_property(sheet, "position", target_pos, fan_anim_time)

		match sheet.hinge_axis:
			"x":
				tween.parallel().tween_property(sheet.hinge, "rotation:x", angle_rad, fan_anim_time)
			"y":
				tween.parallel().tween_property(sheet.hinge, "rotation:y", angle_rad, fan_anim_time)
			"z":
				tween.parallel().tween_property(sheet.hinge, "rotation:z", angle_rad, fan_anim_time)


func exit_fan_mode() -> void:
	is_fan_mode = false
	fan_hovered_index = -1
	apply_reading_state(true)


func apply_reading_state(animated: bool) -> void:
	for i: int in range(sheets.size()):
		var sheet: BookPage = sheets[i]
		var target_pos: Vector3 = Vector3(0.0, 0.0, -float(i) * page_thickness)
		var target_angle: float = 0.0

		if i < current_sheet_index:
			target_angle = deg_to_rad(sheet.base_turn_angle_degrees + sheet.turned_angle_offset_degrees)
			sheet.is_turned = true
		else:
			target_angle = 0.0
			sheet.is_turned = false

		if animated:
			var tween: Tween = create_tween()
			tween.parallel().tween_property(sheet, "position", target_pos, fan_anim_time)

			match sheet.hinge_axis:
				"x":
					tween.parallel().tween_property(sheet.hinge, "rotation:x", target_angle, fan_anim_time)
				"y":
					tween.parallel().tween_property(sheet.hinge, "rotation:y", target_angle, fan_anim_time)
				"z":
					tween.parallel().tween_property(sheet.hinge, "rotation:z", target_angle, fan_anim_time)
		else:
			sheet.position = target_pos
			match sheet.hinge_axis:
				"x":
					sheet.hinge.rotation.x = target_angle
				"y":
					sheet.hinge.rotation.y = target_angle
				"z":
					sheet.hinge.rotation.z = target_angle


func get_fan_page_from_mouse(mouse_pos: Vector2) -> int:
	var best_index: int = -1
	var best_dist: float = INF

	for i: int in range(sheets.size()):
		var sheet: BookPage = sheets[i]
		var screen_pos: Vector2 = get_sheet_screen_center(sheet)
		var dist: float = screen_pos.distance_to(mouse_pos)

		if dist < best_dist:
			best_dist = dist
			best_index = i

	if best_dist <= fan_hover_radius_px:
		return best_index

	return -1


func get_sheet_screen_center(sheet: BookPage) -> Vector2:
	var world_pos: Vector3 = sheet.page_mesh.global_transform.origin
	var active_camera: Camera3D = camera
	if active_camera == null:
		active_camera = get_viewport().get_camera_3d()

	if active_camera == null:
		return Vector2.ZERO

	return active_camera.unproject_position(world_pos)


func jump_to_sheet(target_index: int) -> void:
	if target_index < 0 or target_index >= sheets.size():
		return

	current_sheet_index = target_index
	is_fan_mode = false
	fan_hovered_index = -1
	apply_reading_state(true)


func get_next_right_sheet_index() -> int:
	var i: int = current_sheet_index
	while i < sheets.size():
		var sheet: BookPage = sheets[i]
		if not sheet.is_torn_out and not sheet.is_turned:
			return i
		i += 1
	return -1


func get_previous_left_sheet_index() -> int:
	var i: int = min(current_sheet_index - 1, sheets.size() - 1)
	while i >= 0:
		var sheet: BookPage = sheets[i]
		if not sheet.is_torn_out and sheet.is_turned:
			return i
		i -= 1
	return -1


func normalize_current_sheet_index() -> void:
	var i: int = clamp(current_sheet_index, 0, sheets.size())
	while i < sheets.size():
		var sheet: BookPage = sheets[i]
		if not sheet.is_torn_out and not sheet.is_turned:
			break
		i += 1
	current_sheet_index = clamp(i, 0, sheets.size())


func make_blank_texture() -> Texture2D:
	var image: Image = Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 1, 1, 1))
	return ImageTexture.create_from_image(image)
