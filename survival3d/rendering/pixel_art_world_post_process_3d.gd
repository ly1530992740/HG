@tool
extends CanvasLayer
class_name PixelArtWorldPostProcess3D

@export_group("像素采样")
@export_range(1.0, 4.0, 0.25) var pixel_block_size := 2.0:
	set(value):
		pixel_block_size = value
		_apply_parameters()
@export_range(8.0, 64.0, 1.0) var color_levels := 24.0:
	set(value):
		color_levels = value
		_apply_parameters()
@export_range(0.0, 1.0, 0.01) var dither_strength := 0.16:
	set(value):
		dither_strength = value
		_apply_parameters()

@export_group("画面基调")
@export_range(0.5, 1.5, 0.01) var saturation := 0.88:
	set(value):
		saturation = value
		_apply_parameters()
@export_range(0.5, 1.5, 0.01) var contrast := 1.05:
	set(value):
		contrast = value
		_apply_parameters()
@export_range(-0.2, 0.2, 0.005) var brightness_offset := 0.025:
	set(value):
		brightness_offset = value
		_apply_parameters()

@onready var _screen_rect := $ScreenEffect as ColorRect

func _ready() -> void:
	layer = -1
	_apply_parameters()

func _apply_parameters() -> void:
	var screen_rect := get_node_or_null("ScreenEffect") as ColorRect
	if screen_rect == null or not (screen_rect.material is ShaderMaterial):
		return
	var shader_material := screen_rect.material as ShaderMaterial
	shader_material.set_shader_parameter("pixel_block_size", pixel_block_size)
	shader_material.set_shader_parameter("color_levels", color_levels)
	shader_material.set_shader_parameter("dither_strength", dither_strength)
	shader_material.set_shader_parameter("saturation", saturation)
	shader_material.set_shader_parameter("contrast", contrast)
	shader_material.set_shader_parameter("brightness_offset", brightness_offset)
