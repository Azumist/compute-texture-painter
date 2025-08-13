class_name Painter extends Node3D

@export_group("Nodes")
@export var mesh_instance: MeshInstance3D
@export var camera: Camera3D

@export_group("Painter settings")
@export var paint_color: Color = Color.RED
@export var brush_size_px := 10
@export var brush_image: Texture2D
@export var brush_rotation: float
@export var painted_texture_size: Vector2i = Vector2i(1024, 1024)
@export_flags_3d_physics var collision_mask: int = 1 << 0

var mdt: MeshDataTool
var space_state: PhysicsDirectSpaceState3D
var query:PhysicsRayQueryParameters3D 
var result: Dictionary
var painted_texture: Texture2DRD
var is_painting := false

func _ready() -> void:
	space_state = get_world_3d().direct_space_state
	query = PhysicsRayQueryParameters3D.new()

	if mesh_instance && mesh_instance.mesh:
		mdt = MeshDataTool.new()
		mdt.create_from_surface(mesh_instance.mesh, 0)
	
		var material = mesh_instance.get_surface_override_material(0)

		if material && material is StandardMaterial3D:
			var standard_mat_3d := (material as StandardMaterial3D)

			# expecting Texture2DRD, overwrite existing or create new if not found
			if !standard_mat_3d.albedo_texture || !(standard_mat_3d.albedo_texture is Texture2DRD):
				standard_mat_3d.albedo_texture = Texture2DRD.new()
			
			painted_texture = standard_mat_3d.albedo_texture
			RenderingServer.call_on_render_thread(_initialize_compute.bind(painted_texture_size, Color.WHITE))

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE: 
		_cleanup()

func _unhandled_input(event):
	if event is InputEventMouseButton:
		is_painting = event.pressed && event.button_index == MOUSE_BUTTON_LEFT
		if is_painting:
			paint_on_mesh(event.position)
	
	if is_painting and event is InputEventMouseMotion:
		paint_on_mesh(event.position)

func paint_on_mesh(screen_pos: Vector2) -> void:
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 100.0

	query.collision_mask = collision_mask
	query.from = from
	query.to = to

	result.clear()
	result = space_state.intersect_ray(query)

	if not result.is_empty():
		var face_index: int = result.get(&"face_index", -1)
		var hit_point: Vector3 = result.get(&"position")
		
		if face_index >= 0:
			paint_at_face(face_index, hit_point)

func paint_at_face(face_index: int, world_hit_point: Vector3):
	var local_hit_point := mesh_instance.global_transform.inverse() * world_hit_point
	
	var v0_idx = mdt.get_face_vertex(face_index, 0)
	var v1_idx = mdt.get_face_vertex(face_index, 1)
	var v2_idx = mdt.get_face_vertex(face_index, 2)
	
	var vertices := PackedVector3Array()
	vertices.push_back(mdt.get_vertex(v0_idx))
	vertices.push_back(mdt.get_vertex(v1_idx))
	vertices.push_back(mdt.get_vertex(v2_idx))

	var uvs := PackedVector2Array()
	uvs.push_back(mdt.get_vertex_uv(v0_idx))
	uvs.push_back(mdt.get_vertex_uv(v1_idx))
	uvs.push_back(mdt.get_vertex_uv(v2_idx))

	RenderingServer.call_on_render_thread(_render_process.bind(local_hit_point, vertices, uvs))

###############################################################################
# Everything after this point is designed to run on rendering thread.

var rd: RenderingDevice

var shader: RID
var pipeline: RID

var painted_texture_rd: RID
var brush_texture_rd: RID
var painted_texture_set: RID
var brush_sampler_rd: RID

func _initialize_compute(painted_texture_size: Vector2i, init_color: Color) -> bool:
	rd = RenderingServer.get_rendering_device()

	var pipeline_res := _create_pipeline(load("res://painter/texture_paint.glsl"))
	if pipeline_res.is_empty():
		return false
	shader = pipeline_res.shader
	pipeline = pipeline_res.pipeline

	painted_texture_rd = RID()
	painted_texture_set = RID()

	var tf := RDTextureFormat.new()
	tf.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	tf.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	tf.width = painted_texture_size.x
	tf.height = painted_texture_size.y
	tf.depth = 1
	tf.array_layers = 1
	tf.mipmaps = 1
	tf.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT |
		RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT |
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT |
		RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT |
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	)

	painted_texture_rd = rd.texture_create(tf, RDTextureView.new(), [])
	rd.texture_clear(painted_texture_rd, init_color, 0, 1, 0, 1)

	brush_sampler_rd = _create_sampler()
	brush_texture_rd = _create_brush_from_texture_2d(brush_image)

	# painted_texture_set = _create_uniform_set(painted_texture_rd)
	painted_texture_set = _create_uniform_set(painted_texture_rd, brush_texture_rd)

	# assign our newly created texture to the material
	painted_texture.texture_rd_rid = painted_texture_rd

	return true

#brush_color: Color, brush_size_px: float, tex_size: Vector2i
func _render_process(local_hit_point: Vector3, vertices: PackedVector3Array, uvs: PackedVector2Array) -> void:
	# 16-bytes aligned
	var push_constant := PackedFloat32Array()

	# brush_color (vec4)
	push_constant.push_back(paint_color.r)
	push_constant.push_back(paint_color.g) 
	push_constant.push_back(paint_color.b)
	push_constant.push_back(paint_color.a)

	# local_hit_point (vec3) + brush_size_px (float)
	push_constant.push_back(local_hit_point.x)
	push_constant.push_back(local_hit_point.y)
	push_constant.push_back(local_hit_point.z)
	push_constant.push_back(brush_size_px)

	# vertex_0 (vec3) + texture_width (float)
	push_constant.push_back(vertices[0].x)
	push_constant.push_back(vertices[0].y)
	push_constant.push_back(vertices[0].z)
	push_constant.push_back(float(painted_texture_size.x))

	# vertex_1 (vec3) + texture_height (float)  
	push_constant.push_back(vertices[1].x)
	push_constant.push_back(vertices[1].y)
	push_constant.push_back(vertices[1].z)
	push_constant.push_back(float(painted_texture_size.y))

	# vertex_2 (vec3) + brush rotation (float)
	push_constant.push_back(vertices[2].x)
	push_constant.push_back(vertices[2].y)
	push_constant.push_back(vertices[2].z)
	push_constant.push_back(brush_rotation)

	# uvs (vec2 x 3) + padding (vec2)
	push_constant.push_back(uvs[0].x)
	push_constant.push_back(uvs[0].y)
	push_constant.push_back(uvs[1].x)
	push_constant.push_back(uvs[1].y)

	push_constant.push_back(uvs[2].x)
	push_constant.push_back(uvs[2].y)
	push_constant.push_back(0.0) # padding vec2
	push_constant.push_back(0.0)

	@warning_ignore("integer_division")
	var x_groups := (painted_texture_size.x - 1) / 8 + 1
	@warning_ignore("integer_division")
	var y_groups := (painted_texture_size.y - 1) / 8 + 1

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, painted_texture_set, 0)
	rd.compute_list_set_push_constant(compute_list, push_constant.to_byte_array(), push_constant.size() * 4)
	rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
	rd.compute_list_end()

func _create_pipeline(shader_file: RDShaderFile) -> Dictionary:
	var spirv: RDShaderSPIRV = shader_file.get_spirv()

	if spirv.compile_error_compute != "":
		printerr(spirv.compile_error_compute)
		return {}

	var _shader = rd.shader_create_from_spirv(spirv)
	if !_shader.is_valid():
		printerr("Compute Texture Paint: Invalid shader %s" % shader_file.resource_name)
		return {}

	var _pipeline = rd.compute_pipeline_create(_shader)
	if !_pipeline.is_valid():
		printerr("Compute Texture Paint: Invalid compute pipeline %s" % shader_file.resource_name)
		return {}
	
	return {
		&"shader": _shader,
		&"pipeline": _pipeline
	}

# func _create_uniform_set(texture_rd: RID, binding: int = 0) -> RID:
# 	var uniform := RDUniform.new()
# 	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
# 	uniform.binding = binding
# 	uniform.add_id(texture_rd)
	
# 	return rd.uniform_set_create([uniform], shader, 0)

func _create_uniform_set(texture_rd: RID, brush_texture_rd: RID) -> RID:
	var uniforms := []
	
	var image_uniform := RDUniform.new()
	image_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	image_uniform.binding = 0
	image_uniform.add_id(texture_rd)
	uniforms.push_back(image_uniform)
	
	var sampler_uniform := RDUniform.new()
	sampler_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	sampler_uniform.binding = 1
	sampler_uniform.add_id(brush_sampler_rd) 
	sampler_uniform.add_id(brush_texture_rd)
	uniforms.push_back(sampler_uniform)
	
	return rd.uniform_set_create(uniforms, shader, 0)

func _create_brush_from_texture_2d(texture: Texture2D) -> RID:
	if !texture:
		printerr("Brush texture is null")
		return RID()
		
	var image := texture.get_image()
	
	if !image:
		printerr("Failed to get image from texture")
		return RID()

	if image.is_compressed():
		var error = image.decompress()
		if error != OK:
			printerr("Failed to decompress brush image: ", error)
			return RID()

	# only way i found to get this working
	var clean_image := Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	clean_image.blit_rect(image, Rect2i(0, 0, image.get_width(), image.get_height()), Vector2i.ZERO)
	
	var img_width = clean_image.get_width()
	var img_height = clean_image.get_height()


	var tf := RDTextureFormat.new()
	tf.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	tf.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	tf.width = img_width
	tf.height = img_height
	tf.depth = 1
	tf.array_layers = 1
	tf.mipmaps = 1
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT

	var texture_rd = rd.texture_create(tf, RDTextureView.new(), [clean_image.get_data()])
	return texture_rd

func _create_sampler() -> RID:
	var sampler_state := RDSamplerState.new()
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	return rd.sampler_create(sampler_state)

func _cleanup() -> void:
	if painted_texture:
		painted_texture.texture_rd_rid = RID()

	var rids := [painted_texture_rd, brush_texture_rd, brush_sampler_rd, pipeline, shader]

	for rid in rids:
		if rid && rid.is_valid(): rd.free_rid(rid)
