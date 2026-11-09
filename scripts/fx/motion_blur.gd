class_name MotionBlur
extends CanvasLayer
## Light motion blur (Settings > Graphics). Measures how fast the active
## camera turns and how fast you're going, and feeds a 6-tap screen blur.
## The overlay hides itself when there's nothing to blur, so it costs
## nothing while you stand still.

const SHADER := preload("res://assets/materials/shaders/motion_blur.gdshader")
const STRENGTH := 0.45

var speed_source: Callable   # returns current speed (m/s)
var _rect: ColorRect
var _material: ShaderMaterial
var _last_basis := Basis.IDENTITY
var _has_last := false


func _ready() -> void:
	layer = 5
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _material
	_rect.visible = false
	add_child(_rect)


func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or not GameSettings.motion_blur or delta <= 0.0:
		_rect.visible = false
		_has_last = false
		return
	var basis := camera.global_basis.orthonormalized()
	var dir := Vector2.ZERO
	if _has_last:
		# Rotation since last frame, expressed in camera space.
		var delta_rot := basis.inverse() * _last_basis
		var forward := delta_rot * Vector3.FORWARD
		var fov := deg_to_rad(camera.fov)
		dir = Vector2(forward.x, -forward.y) / maxf(fov, 0.1) * STRENGTH
	_last_basis = basis
	_has_last = true
	var speed := 0.0
	if speed_source.is_valid():
		speed = float(speed_source.call())
	var radial := clampf((speed - 14.0) / 60.0, 0.0, 1.0) * 0.035
	var active := dir.length() > 0.0015 or radial > 0.002
	_rect.visible = active
	if active:
		_material.set_shader_parameter("blur_dir", dir.limit_length(0.04))
		_material.set_shader_parameter("radial", radial)
