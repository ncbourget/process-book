extends Node3D
class_name BookPage

@export var hinge_path: NodePath
@export var mesh_path: NodePath
@export_enum("x", "y", "z") var hinge_axis: String = "z"
@export var base_turn_angle_degrees: float = 180.0
@export var turned_angle_offset_degrees: float = 0.0

var page_index: int = -1
var is_turned: bool = false
var is_torn_out: bool = false
var turn_tween: Tween

@onready var hinge: Node3D = get_node(hinge_path) as Node3D
@onready var page_mesh: MeshInstance3D = get_node(mesh_path) as MeshInstance3D

func set_textures(front: Texture2D, back: Texture2D) -> void:
	var shader: Shader = load("res://Shaders/page_double_sided.gdshader") as Shader
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("front_tex", front)
	material.set_shader_parameter("back_tex", back)
	page_mesh.set_surface_override_material(0, material)

func get_closed_angle_rad() -> float:
	return 0.0

func get_open_angle_rad() -> float:
	return deg_to_rad(base_turn_angle_degrees + turned_angle_offset_degrees)

func set_turn_progress(progress: float) -> void:
	if is_torn_out:
		return
	var target_angle: float = lerp(get_closed_angle_rad(), get_open_angle_rad(), progress)
	_set_hinge_angle(target_angle)

func turn_to_left() -> void:
	if is_torn_out:
		return
	if turn_tween:
		turn_tween.kill()
	_set_hinge_angle(get_open_angle_rad())
	is_turned = true

func turn_to_right() -> void:
	if is_torn_out:
		return
	if turn_tween:
		turn_tween.kill()
	_set_hinge_angle(get_closed_angle_rad())
	is_turned = false

func animate_to_left(duration: float = 0.35) -> void:
	if is_torn_out:
		return
	if turn_tween:
		turn_tween.kill()
	turn_tween = create_tween()
	_tween_hinge_angle(get_open_angle_rad(), duration)
	is_turned = true

func animate_to_right(duration: float = 0.35) -> void:
	if is_torn_out:
		return
	if turn_tween:
		turn_tween.kill()
	turn_tween = create_tween()
	_tween_hinge_angle(get_closed_angle_rad(), duration)
	is_turned = false

func toggle_page() -> void:
	if is_torn_out:
		return
	if is_turned:
		animate_to_right()
	else:
		animate_to_left()

func tear_out_to(loose_pages_parent: Node3D) -> Node3D:
	if is_torn_out:
		return null

	if turn_tween:
		turn_tween.kill()

	var loose_root: Node3D = Node3D.new()
	loose_root.name = "TornPage_%03d" % page_index
	loose_pages_parent.add_child(loose_root)

	var loose_mesh: MeshInstance3D = MeshInstance3D.new()
	loose_mesh.mesh = page_mesh.mesh
	loose_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var surface_material: Material = page_mesh.get_surface_override_material(0)
	if surface_material != null:
		loose_mesh.set_surface_override_material(0, surface_material)

	loose_root.add_child(loose_mesh)
	loose_root.global_transform = page_mesh.global_transform

	is_torn_out = true
	visible = false

	return loose_root

func _set_hinge_angle(angle: float) -> void:
	match hinge_axis:
		"x":
			hinge.rotation.x = angle
		"y":
			hinge.rotation.y = angle
		"z":
			hinge.rotation.z = angle

func _tween_hinge_angle(target: float, duration: float) -> void:
	match hinge_axis:
		"x":
			turn_tween.tween_property(hinge, "rotation:x", target, duration)
		"y":
			turn_tween.tween_property(hinge, "rotation:y", target, duration)
		"z":
			turn_tween.tween_property(hinge, "rotation:z", target, duration)
