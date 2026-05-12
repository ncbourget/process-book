extends Node3D

@export var page_scene: PackedScene
@export var pages_container_path: NodePath

@export var page_textures: Array[Texture2D] = []

# Positive = pages stack upward in Y.
# If the stack visually goes down, flip this to -0.00005.
@export var page_thickness: float = 0.00005

# Left stack: front cover flat, later turned pages angle slightly upward.
# Right stack: back cover flat, pages above it angle the opposite way.
@export var turned_stack_angle_step: float = 0.12
@export var closed_stack_angle_step: float = -0.12

# Camera zoom
@export var camera_rig: Node3D
@export var camera: Camera3D
@export var cursor_marker: Node3D

@export_range(0.0, 10.0, 0.001) var zoom: float = 0.0
@export var zoom_min: float = 0.0
@export var zoom_max: float = 7.5
@export var zoom_scroll_sensitivity: float = 0.5
@export var trackpad_zoom_sensitivity: float = 0.035
@export var invert_trackpad_zoom: bool = false
@export var zoom_smooth_speed: float = 12.0

@export var zoom_plane_y: float = 0.0
@export var zoom_forward_strength: float = 0.08
@export var zoom_focus_strength: float = 1.0
@export var zoom_focus_clamp_x: float = 0.22
@export var zoom_focus_clamp_z: float = 0.30

# Page skipping
@export var shift_skip_pages: int = 10

@onready var pages_container: Node3D = get_node(pages_container_path) as Node3D

var sheets: Array[BookPage] = []
var current_sheet_index: int = 0

var is_dragging: bool = false
var drag_page: BookPage = null
var drag_target_left: bool = false
var is_skipping_pages: bool = false

var zoom_target: float = 0.0
var zoom_focus: Vector3 = Vector3.ZERO
var base_camera_rig_pos: Vector3 = Vector3.ZERO
var base_camera_rig_rot: Vector3 = Vector3.ZERO


func _ready() -> void:
	if camera == null:
		camera = get_viewport().get_camera_3d()

	if camera_rig == null and camera != null:
		camera_rig = camera

	if camera_rig != null:
		base_camera_rig_pos = camera_rig.global_position
		base_camera_rig_rot = camera_rig.rotation

	zoom_target = clamp(zoom, zoom_min, zoom_max)
	zoom = zoom_target
	zoom_focus = global_position

	build_book()


func _input(event: InputEvent) -> void:
	if event is InputEventPanGesture:
		var pan_event: InputEventPanGesture = event as InputEventPanGesture
		var direction: float = -pan_event.delta.y

		if invert_trackpad_zoom:
			direction *= -1.0

		update_zoom_focus(get_viewport().get_mouse_position())
		zoom_target = clamp(
			zoom_target + direction * trackpad_zoom_sensitivity,
			zoom_min,
			zoom_max
		)
		return

	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton

		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			update_zoom_focus(mouse_event.position)
			zoom_target = clamp(
				zoom_target + zoom_scroll_sensitivity,
				zoom_min,
				zoom_max
			)
			return

		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			update_zoom_focus(mouse_event.position)
			zoom_target = clamp(
				zoom_target - zoom_scroll_sensitivity,
				zoom_min,
				zoom_max
			)
			return

	if event is InputEventMouseButton:
		var click_event: InputEventMouseButton = event as InputEventMouseButton

		if click_event.button_index == MOUSE_BUTTON_LEFT:
			if click_event.pressed:
				start_drag(click_event.position)
			else:
				end_drag()


func _process(delta: float) -> void:
	update_cursor_marker()
	update_zoom(delta)

	if is_dragging and drag_page != null:
		update_drag()


func update_cursor_marker() -> void:
	if cursor_marker == null or camera == null:
		return

	var hit: Vector3 = get_mouse_on_book_plane(get_viewport().get_mouse_position())
	cursor_marker.global_position = hit


func update_zoom_focus(mouse_pos: Vector2) -> void:
	zoom_focus = get_mouse_on_book_plane(mouse_pos)

	if cursor_marker != null:
		cursor_marker.global_position = zoom_focus


func get_mouse_on_book_plane(mouse_pos: Vector2) -> Vector3:
	if camera == null:
		return global_position

	var ray_origin: Vector3 = camera.project_ray_origin(mouse_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(mouse_pos)

	if abs(ray_dir.y) < 0.00001:
		return zoom_focus

	var t: float = (zoom_plane_y - ray_origin.y) / ray_dir.y
	if t < 0.0:
		return zoom_focus

	var hit: Vector3 = ray_origin + ray_dir * t

	hit.y = zoom_plane_y
	hit.x = clamp(
		hit.x,
		global_position.x - zoom_focus_clamp_x,
		global_position.x + zoom_focus_clamp_x
	)
	hit.z = clamp(
		hit.z,
		global_position.z - zoom_focus_clamp_z,
		global_position.z + zoom_focus_clamp_z
	)

	return hit


func update_zoom(delta: float) -> void:
	if camera_rig == null or camera == null:
		return

	var smooth: float = 1.0 - exp(-zoom_smooth_speed * delta)
	zoom = lerp(zoom, zoom_target, smooth)

	var zoom_alpha: float = clamp(zoom / max(zoom_max, 0.001), 0.0, 1.0)
	var forward: Vector3 = -camera.global_transform.basis.z.normalized()

	var flat_focus_offset: Vector3 = Vector3(
		zoom_focus.x - global_position.x,
		0.0,
		zoom_focus.z - global_position.z
	)

	var desired_pos: Vector3 = (
		base_camera_rig_pos
		+ flat_focus_offset * zoom_focus_strength * zoom_alpha
		+ forward * zoom * zoom_forward_strength
	)

	camera_rig.global_position = camera_rig.global_position.lerp(
		desired_pos,
		smooth
	)

	camera_rig.rotation.x = lerp_angle(camera_rig.rotation.x, base_camera_rig_rot.x, smooth)
	camera_rig.rotation.y = lerp_angle(camera_rig.rotation.y, base_camera_rig_rot.y, smooth)
	camera_rig.rotation.z = lerp_angle(camera_rig.rotation.z, base_camera_rig_rot.z, smooth)


func build_book() -> void:
	for child: Node in pages_container.get_children():
		child.queue_free()

	sheets.clear()
	current_sheet_index = 0
	is_dragging = false
	drag_page = null
	drag_target_left = false
	is_skipping_pages = false

	if page_textures.is_empty():
		push_error("No page textures assigned. Drag your page images into Page Textures on the Book node.")
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
			push_error("The page scene root is not a BookPage.")
			return

		pages_container.add_child(sheet)
		sheet.name = "Sheet_%03d" % i

		var front_tex: Texture2D = page_textures[i * 2]
		var back_tex: Texture2D = page_textures[i * 2 + 1]

		sheet.page_index = i
		sheet.turn_to_right()
		sheet.set_textures(front_tex, back_tex)

		sheets.append(sheet)

	apply_reading_state(false)


func update_stack_targets() -> void:
	var total: int = sheets.size()

	for i: int in range(total):
		var sheet: BookPage = sheets[i]

		if i < current_sheet_index:
			# LEFT / TURNED STACK
			# Front cover is layer 0 and stays flat.
			# Each later turned page sits higher and turns a little more.
			var open_layer: int = i

			sheet.position = Vector3(
				0.0,
				float(open_layer) * page_thickness,
				0.0
			)

			sheet.turned_angle_offset_degrees = (
				float(open_layer) * turned_stack_angle_step
			)

		else:
			# RIGHT / CLOSED STACK
			# Back cover is layer 0 and stays flat.
			# Pages above it sit higher and turn the opposite way.
			var closed_layer: int = (total - 1) - i

			sheet.position = Vector3(
				0.0,
				float(closed_layer) * page_thickness,
				0.0
			)

			sheet.closed_angle_offset_degrees = (
				float(closed_layer) * closed_stack_angle_step
			)


func apply_reading_state(animated: bool) -> void:
	update_stack_targets()

	for i: int in range(sheets.size()):
		var sheet: BookPage = sheets[i]

		var target_pos: Vector3 = sheet.position
		var target_angle: float = 0.0

		if i < current_sheet_index:
			target_angle = sheet.get_open_angle_rad()
			sheet.is_turned = true
		else:
			target_angle = sheet.get_closed_angle_rad()
			sheet.is_turned = false

		if animated:
			var tween: Tween = create_tween()

			tween.parallel().tween_property(
				sheet,
				"position",
				target_pos,
				0.25
			)

			match sheet.hinge_axis:
				"x":
					tween.parallel().tween_property(sheet.hinge, "rotation:x", target_angle, 0.25)
				"y":
					tween.parallel().tween_property(sheet.hinge, "rotation:y", target_angle, 0.25)
				"z":
					tween.parallel().tween_property(sheet.hinge, "rotation:z", target_angle, 0.25)
		else:
			sheet.position = target_pos

			match sheet.hinge_axis:
				"x":
					sheet.hinge.rotation.x = target_angle
				"y":
					sheet.hinge.rotation.y = target_angle
				"z":
					sheet.hinge.rotation.z = target_angle


func flip_current_sheet_forward() -> void:
	if is_skipping_pages:
		return

	var index: int = get_next_right_sheet_index()
	if index == -1:
		return

	current_sheet_index = index + 1
	apply_reading_state(true)


func skip_pages_forward(page_amount: int) -> void:
	if sheets.is_empty() or is_skipping_pages:
		return

	is_skipping_pages = true

	var sheet_amount: int = max(1, int(ceil(float(page_amount) / 2.0)))
	current_sheet_index = min(current_sheet_index + sheet_amount, sheets.size())

	apply_reading_state(true)

	is_skipping_pages = false


func skip_pages_backward(page_amount: int) -> void:
	if sheets.is_empty() or is_skipping_pages:
		return

	is_skipping_pages = true

	var sheet_amount: int = max(1, int(ceil(float(page_amount) / 2.0)))
	current_sheet_index = max(current_sheet_index - sheet_amount, 0)

	apply_reading_state(true)

	is_skipping_pages = false


func start_drag(mouse_pos: Vector2) -> void:
	if sheets.is_empty() or is_dragging or is_skipping_pages:
		return

	update_stack_targets()

	if Input.is_key_pressed(KEY_SHIFT):
		var screen_width_shift: float = get_viewport().get_visible_rect().size.x
		var clicked_left_shift: bool = mouse_pos.x < screen_width_shift * 0.5

		if clicked_left_shift:
			skip_pages_backward(shift_skip_pages)
		else:
			skip_pages_forward(shift_skip_pages)

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

	var axis_angle: float = get_page_axis_angle(drag_page)
	var closed_angle: float = drag_page.get_closed_angle_rad()
	var open_angle: float = drag_page.get_open_angle_rad()

	var progress: float = 0.0
	var denom: float = open_angle - closed_angle

	if abs(denom) > 0.00001:
		progress = (axis_angle - closed_angle) / denom

	progress = clamp(progress, 0.0, 1.0)

	if progress > 0.5:
		current_sheet_index = drag_page.page_index + 1
	else:
		current_sheet_index = drag_page.page_index

	apply_reading_state(true)

	is_dragging = false
	drag_page = null
	drag_target_left = false


func get_page_axis_angle(page: BookPage) -> float:
	match page.hinge_axis:
		"x":
			return page.hinge.rotation.x
		"y":
			return page.hinge.rotation.y
		"z":
			return page.hinge.rotation.z

	return 0.0


func get_next_right_sheet_index() -> int:
	if current_sheet_index >= 0 and current_sheet_index < sheets.size():
		return current_sheet_index

	return -1


func get_previous_left_sheet_index() -> int:
	var index: int = current_sheet_index - 1

	if index >= 0 and index < sheets.size():
		return index

	return -1


func make_blank_texture() -> Texture2D:
	var image: Image = Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 1, 1, 1))
	return ImageTexture.create_from_image(image)
