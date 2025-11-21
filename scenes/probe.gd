extends Node2D
class_name Probe

## Probówka:
## - Drag & drop po stole, dropzony, animacja „wylewania”.
## - Trzyma Mixture (chemia) i gada z QualEngine.
## - Obsługuje mętność, osad, kryształki i pellet z wirówki.

enum TubeRole { STARTER, WORK }

@export_group("Rola probówki")
@export var tube_role: TubeRole = TubeRole.WORK

signal drag_started(probe: Node)
signal drag_ended(probe: Node)
signal drag_released(probe: Node, at_global_pos: Vector2)

@onready var area: Area2D            = $ProbeArea2D
@onready var glass_sprite: Sprite2D  = $GlassSprite2D
@onready var turbidity: Sprite2D     = $LiquidFill/TurbidityOverlay
@onready var sediment: Node2D        = $Sediment
@onready var crystal_fx: Sprite2D    = $LiquidFill/CrystalFX
@onready var pellet: Sprite2D        = $LiquidFill/Pellet
@onready var label: Label            = $NumLabel

@onready var liquid_body: Sprite2D          = $LiquidFill/LiquidBody
@onready var liquid_level_sprite: Sprite2D  = $LiquidFill/LiquidLevelSprite2D

var glass_mat: ShaderMaterial
var hover_enabled: bool = false

@export_group("Drag & Drop")
@export var draggable: bool = true

var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _drag_origin_pos: Vector2 = Vector2.ZERO
var _drag_origin_z: int = 0
@export var drag_raise_z: int = 500

@export_range(0.0, 2.0, 0.01) var drag_return_duration: float = 0.6
@export var drag_return_trans: Tween.TransitionType = Tween.TRANS_CUBIC
@export var drag_return_ease: Tween.EaseType = Tween.EASE_OUT
var _drag_return_tween: Tween = null
var _drag_origin_parent: Node = null
var _returning: bool = false

@export_group("Animacja wylewania")
@export_range(-200.0, 200.0, 1.0) var pivot_offset_y: float = -50.0
@export_range(0.0, 180.0, 1.0) var dump_tilt_deg: float = 120.0
@export_range(0.0, 1.0, 0.01) var dump_tilt_time: float = 0.18
@export_range(0.0, 1.0, 0.01) var dump_tilt_hold: float = 0.07

var _dump_anim_pending: bool = false
var _tilt_node: Node2D = null

@export_group("Chemia i objętość")
@export var mixture := Mixture.new()
var sediment_level: float = 0.0

@export_subgroup("Poziom cieczy")
@export_range(0.0, 1.0, 0.01) var fill_level: float = 1.0
@export_range(0.0, 0.5, 0.01) var min_fill_level: float = 0.10
@export_range(0.05, 15.0, 0.05) var capacity_units: float = 1.0

@export_subgroup("Krople reagentów")
@export_range(0.0, 0.5, 0.005) var reagent_level_per_drop: float = 0.10

@export_group("Mętność i osad (FX)")
@export_range(0.0, 5.0, 0.01) var settle_delay: float = 1.0
@export_range(0.1, 60.0, 0.1) var settle_tau:   float = 20.0
@export_range(0.0, 1.0, 0.01) var turbidity_floor: float = 0.6
@export_range(0.1, 10.0, 0.1) var turbidity_smooth: float = 3.0
@export_range(5.0, 120.0, 0.5) var turbidity_decay_time: float = 45.0
@export_range(0.0, 1.0, 0.01) var initial_turbidity: float = 0.02

var settle_delay_left: float = 0.0
var suspended: float = 0.0
var precip_total: float = 0.0

var turbidity_color: Color = Color.WHITE
var sediment_color: Color = Color.WHITE

var turbidity_target: float = 0.0
var display_turbidity: float = 0.0
var ever_precipitated: bool = false

var _recalc_scheduled: bool = false

@export_group("Chłodzenie (łaźnia)")
@export_range(0.0, 60.0, 0.5) var cooling_time_s: float = 5.0

const TAG_BATH_BOILING   := "bath_boiling"
const TAG_COOLING_READY  := "cooling_ready"
const TAG_COOLING_T      := "cooling_t_s"
const TAG_COOLED_ENOUGH  := "cooled_enough"

@export_group("Pellet / Krystalizacja (FX)")
@export_range(0.0, 2.0, 0.01) var pellet_brightness: float = 0.9
@export_range(0.0, 1.0, 0.01) var pellet_opacity: float = 0.9

var last_precip_mode: String = "floc"
var had_crystal_before_spin: bool = false

const FILL_EPS := 0.001


func _ready() -> void:
	# Duplikacja materiałów, żeby uniformy były per-probówka.
	if glass_sprite.material:
		glass_sprite.material = glass_sprite.material.duplicate()
	if turbidity and turbidity.material:
		turbidity.material = turbidity.material.duplicate()
	if liquid_level_sprite and liquid_level_sprite.material:
		liquid_level_sprite.material = liquid_level_sprite.material.duplicate()
	if crystal_fx and crystal_fx.material:
		crystal_fx.material = crystal_fx.material.duplicate()

	glass_mat = glass_sprite.material as ShaderMaterial

	# Shader poziomu cieczy.
	if liquid_level_sprite:
		liquid_level_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var level_material := liquid_level_sprite.material as ShaderMaterial
		if level_material and level_material.shader:
			if _shader_has_uniform(level_material, "use_mask"):
				level_material.set_shader_parameter("use_mask", true)
				var mask_source := liquid_body
				if mask_source and mask_source.texture:
					level_material.set_shader_parameter("mask_tex", mask_source.texture)
					var mask_size: Vector2i = mask_source.texture.get_size()
					if mask_size.x > 0 and mask_size.y > 0:
						level_material.set_shader_parameter(
							"mask_texel",
							Vector2(1.0 / float(mask_size.x), 1.0 / float(mask_size.y))
						)
			if _shader_has_uniform(level_material, "edge_softness_px"):
				level_material.set_shader_parameter("edge_softness_px", 0.5)

	_apply_highlight(false)
	add_to_group("probes")

	turbidity_color = Color.WHITE
	sediment_color  = Color.WHITE
	turbidity_target = clamp(initial_turbidity, 0.0, 1.0)
	display_turbidity = turbidity_target
	_set_turbidity_value(display_turbidity)

	if sediment:
		sediment.scale.y = 0.0
		sediment.visible = false

	if crystal_fx:
		crystal_fx.visible = false
		var crystal_material := crystal_fx.material as ShaderMaterial
		if crystal_material and crystal_material.shader and _shader_has_uniform(crystal_material, "progress"):
			crystal_material.set_shader_parameter("progress", 0.0)

	if pellet:
		pellet.visible = false
		if pellet.material:
			pellet.material = pellet.material.duplicate()

	_apply_liquid_fill_visual()

	# Pivot do wylewania.
	_tilt_node = Node2D.new()
	_tilt_node.name = "_Tilt"
	add_child(_tilt_node)
	_tilt_node.position = Vector2(0.0, pivot_offset_y)

	var children_to_move: Array = []
	for child in get_children():
		if child == _tilt_node or child == area:
			continue
		children_to_move.append(child)

	for child in children_to_move:
		var old_pos: Vector2 = child.position
		remove_child(child)
		_tilt_node.add_child(child)
		child.position = old_pos - Vector2(0.0, pivot_offset_y)

	_tilt_node.rotation_degrees = 0.0


func _physics_process(delta: float) -> void:
	_update_cooling(delta)

	# Opadanie zawiesiny do osadu na dnie.
	if settle_delay_left > 0.0:
		settle_delay_left = max(0.0, settle_delay_left - delta)
	else:
		if suspended > 0.0 and settle_tau > 0.0:
			var settle_step: float = suspended * (delta / settle_tau)
			suspended = max(0.0, suspended - settle_step)
			_grow_sediment(sediment_color, settle_step)

	# Prosty model mętności w czasie.
	if ever_precipitated and not _has_pellet_ready():
		var floor_val: float = max(turbidity_floor, initial_turbidity)
		var decay_step: float = delta / max(0.001, turbidity_decay_time)
		turbidity_target = move_toward(turbidity_target, floor_val, decay_step)
	else:
		var decay_step_clean: float = delta / max(0.001, turbidity_decay_time)
		turbidity_target = move_toward(turbidity_target, initial_turbidity, decay_step_clean)

	var lerp_step: float = turbidity_smooth * delta
	display_turbidity = move_toward(display_turbidity, turbidity_target, lerp_step)
	_set_turbidity_value(display_turbidity)

	if _has_pellet_ready():
		_force_crystal_fx_off()


func request_dump_anim() -> void:
	_dump_anim_pending = true


func is_full() -> bool:
	return fill_level >= 1.0 - FILL_EPS


func receive_drop(reagent_id: String) -> void:
	if is_full():
		return

	Qualengine.add_drop_to_tube(self, reagent_id)

	if reagent_level_per_drop > 0.0:
		var level_delta: float = reagent_level_per_drop / max(0.0001, capacity_units)
		_set_fill_level(min(1.0, fill_level + level_delta))


func get_indicator_grade() -> int:
	return _get_ph_grade7()


func get_indicator_grade_and_ph() -> Dictionary:
	return {"grade": _get_ph_grade7(), "ph": NAN}


func _get_ph_grade7() -> int:
	if mixture and (mixture.tags is Dictionary):
		var grade_value: Variant = (mixture.tags as Dictionary).get("ph_grade7", null)
		if grade_value is int or grade_value is float:
			return int(grade_value)
	return 0


func play_precip(mode: String, turb_color: Color, sed_color: Color, intensity: float) -> void:
	if _has_pellet_ready():
		return

	var amount: float = clamp(intensity, 0.0, 1.0)

	if mode == "crystal":
		_show_crystal_fx(turb_color, amount)
		turbidity_color = turb_color
		ever_precipitated = true

		var boost: float = max(0.1, amount * 0.4)
		turbidity_target = clamp(turbidity_target + boost, initial_turbidity, 1.0)
		display_turbidity = max(display_turbidity, turbidity_target)

		_set_turbidity_value(display_turbidity)
		_burst_turbidity(turbidity_color, display_turbidity)

		settle_delay_left = 0.0
		last_precip_mode = "crystal"
	else:
		hide_pellet()
		_hide_crystal_fx()

		ever_precipitated = true
		turbidity_color = turb_color
		set_sediment_color(sed_color)

		precip_total = clamp(precip_total + amount, 0.0, 1.0)
		suspended    = clamp(suspended    + amount, 0.0, 1.0)

		var boost2: float = max(0.25, amount * 0.8)
		var new_target: float = clamp(turbidity_target + boost2, turbidity_floor, 1.0)
		turbidity_target = max(turbidity_target, new_target)
		display_turbidity = max(display_turbidity, turbidity_target)

		_set_turbidity_value(display_turbidity)
		_burst_turbidity(turbidity_color, display_turbidity)

		settle_delay_left = settle_delay
		last_precip_mode = "floc"


func set_sediment_color(color: Color) -> void:
	sediment_color = color
	if sediment:
		var solid_color := color
		solid_color.a = 1.0
		sediment.modulate = solid_color
		sediment.visible = true


func set_highlight_enabled(enabled: bool) -> void:
	hover_enabled = enabled
	if not enabled:
		_apply_highlight(false)


func _on_probe_area_2d_mouse_entered() -> void:
	if hover_enabled:
		_apply_highlight(true)


func _on_probe_area_2d_mouse_exited() -> void:
	_apply_highlight(false)


func _apply_highlight(on: bool) -> void:
	if glass_mat == null:
		return
	_set_shader_param_safe(glass_mat, "highlight", on)
	_set_shader_param_safe(glass_mat, "highlight_strength", (1.0 if on else 0.0))


func _on_probe_area_2d_input_event(_vp: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if _returning:
		get_viewport().set_input_as_handled()
		return

	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return

	var lab: Node = get_tree().get_first_node_in_group("lab_root")
	var ModeEnum: Variant = lab.get("Mode")
	var cur_mode: Variant = lab.get("mode")

	if cur_mode == ModeEnum.STIR_ROD:
		if lab.has_method("_stir_rod_use_on_probe"):
			lab._stir_rod_use_on_probe(self)
		get_viewport().set_input_as_handled()
		return

	if cur_mode == ModeEnum.INDICATOR:
		if lab.has_method("_indicator_use_on_probe"):
			lab._indicator_use_on_probe(self)
		elif lab.has_method("_indicator_use"):
			lab._indicator_use(self)
		get_viewport().set_input_as_handled()
		return

	if cur_mode == ModeEnum.TRANSFER:
		var dropper_loaded: bool = bool(lab.get("dropper_loaded"))
		if not dropper_loaded:
			if has_any_liquid() and lab.has_method("_dropper_pick"):
				lab._dropper_pick(self)
		else:
			if lab.has_method("_dropper_drop"):
				lab._dropper_drop(self)
		get_viewport().set_input_as_handled()
		return

	if cur_mode == ModeEnum.SQUIRT:
		if lab.has_method("_squirt_begin"):
			lab._squirt_begin(self)
		return

	if cur_mode == ModeEnum.HOLDING:
		var reagent_id := String(lab.get("active_reagent_id"))
		if reagent_id != "":
			receive_drop(reagent_id)
			get_viewport().set_input_as_handled()
		return

	if draggable:
		_start_drag()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if _returning:
		return
	if not _dragging:
		return

	if event is InputEventMouseMotion:
		global_position = get_global_mouse_position() + _drag_offset
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_end_drag(true)
		get_viewport().set_input_as_handled()


func _start_drag() -> void:
	if _returning or _dragging:
		return

	if is_instance_valid(_drag_return_tween):
		_drag_return_tween.kill()
	_drag_return_tween = null

	_dragging = true
	_apply_highlight(false)

	_drag_offset = global_position - get_global_mouse_position()
	_drag_origin_pos = global_position
	_drag_origin_z = z_index
	z_index = drag_raise_z

	emit_signal("drag_started", self)

	_drag_origin_parent = get_parent()
	if _drag_origin_parent and _drag_origin_parent.has_method("on_probe_pickup"):
		_drag_origin_parent.call("on_probe_pickup", self)

	var lab := get_tree().get_first_node_in_group("lab_root")
	if lab and lab.has_method("probe_drag_started"):
		lab.probe_drag_started()


func _end_drag(emit_release: bool) -> void:
	if not _dragging:
		return

	_dragging = false

	var lab := get_tree().get_first_node_in_group("lab_root")
	if lab and lab.has_method("probe_drag_ended"):
		lab.probe_drag_ended()

	var accepted: bool = _try_drop_into_target()

	if not accepted and _dump_anim_pending:
		_returning = true
		_dump_anim_pending = false

		var rot_node: Node2D = _tilt_node if _tilt_node else self
		var angle := -dump_tilt_deg

		var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(rot_node, "rotation_degrees", angle, dump_tilt_time)
		tween.tween_interval(dump_tilt_hold)
		tween.tween_property(rot_node, "rotation_degrees", 0.0, 0.16)
		tween.finished.connect(func() -> void:
			_start_return_tween(accepted))
	else:
		_start_return_tween(accepted)

	z_index = _drag_origin_z

	if emit_release:
		emit_signal("drag_released", self, global_position)
	emit_signal("drag_ended", self)


func _start_return_tween(accepted: bool) -> void:
	_returning = true

	if not accepted:
		_drag_return_tween = create_tween().set_trans(drag_return_trans).set_ease(drag_return_ease)
		_drag_return_tween.tween_property(self, "global_position", _drag_origin_pos, drag_return_duration)
		_drag_return_tween.finished.connect(func () -> void:
			if _drag_origin_parent and is_instance_valid(_drag_origin_parent) and get_parent() == _drag_origin_parent:
				if _drag_origin_parent.has_method("on_probe_returned"):
					_drag_origin_parent.call("on_probe_returned", self)
			_drag_origin_parent = null
			_returning = false)
	else:
		call_deferred("_unlock_returning")


func _unlock_returning() -> void:
	_returning = false


func _try_drop_into_target() -> bool:
	for dropzone in get_tree().get_nodes_in_group("probe_dropzones"):
		if dropzone and dropzone.has_method("accept_probe"):
			if dropzone.accept_probe(self, global_position) == true:
				return true
	return false


func has_any_liquid() -> bool:
	if fill_level > 0.001:
		return true
	return mixture.ions.size() > 0 or mixture.solids.size() > 0


func take_volume(units: float):
	var requested_units: float = max(0.0, units)
	var max_units: float = fill_level * capacity_units
	if requested_units <= 0.0 or max_units <= 0.00001:
		return null

	var real_units: float = min(requested_units, max_units)

	if not (mixture.tags is Dictionary):
		mixture.tags = {}

	var stored_total_volume: float = 0.0
	var stored_volume_tag: Variant = mixture.tags.get("vol_u", 0.0)
	if stored_volume_tag is float or stored_volume_tag is int:
		stored_total_volume = float(stored_volume_tag)

	if stored_total_volume <= 1e-9:
		stored_total_volume = max_units
		mixture.tags["vol_u"] = stored_total_volume

	var fraction: float = clamp(real_units / max(1e-9, stored_total_volume), 0.0, 1.0)
	var had_pellet: bool = _has_pellet_ready()

	var taken: Mixture = mixture.scaled_fraction(fraction, false)
	taken.ensure_tags()
	taken.tags["vol_u"] = real_units
	(taken.tags as Dictionary).erase("pH")
	(taken.tags as Dictionary).erase("ph_samples")

	mixture.subtract_fraction_in_place(fraction, false)

	_set_fill_level(fill_level - real_units / max(0.0001, capacity_units))

	if fill_level <= 0.0001 and not had_pellet:
		_clear_contents_completely()
		_schedule_recalc()

	return {"mix": taken, "units": real_units}


func take_fraction(frac: float) -> Mixture:
	var clamped_frac: float = clamp(frac, 0.0, 1.0)
	var ret: Variant = take_volume(clamped_frac * capacity_units)
	if ret == null:
		return null
	return ret["mix"] as Mixture


func receive_mixture(mixture_in: Mixture, units: float = 0.18) -> float:
	if mixture_in == null:
		return 0.0

	var free_units: float = max(0.0, (1.0 - fill_level) * capacity_units)
	if free_units <= 0.0001:
		return 0.0

	var requested_units: float = max(0.0, units)
	var real_units: float = min(requested_units, free_units)

	var is_pure_water := true
	if mixture_in.ions is Dictionary and mixture_in.ions.size() > 0:
		is_pure_water = false
	if mixture_in.solids is Dictionary and mixture_in.solids.size() > 0:
		is_pure_water = false

	var source_total_volume: float = 0.0
	if mixture_in.tags is Dictionary:
		var volume_tag_value: Variant = mixture_in.tags.get("vol_u", 0.0)
		if volume_tag_value is float or volume_tag_value is int:
			source_total_volume = float(volume_tag_value)
	if source_total_volume <= 1e-9:
		source_total_volume = requested_units

	var source_fraction: float = clamp(real_units / max(1e-9, source_total_volume), 0.0, 1.0)

	if is_pure_water:
		_set_fill_level(min(1.0, fill_level + real_units / max(0.0001, capacity_units)))
		if Qualengine and Qualengine.has_method("add_water_volume_step"):
			Qualengine.add_water_volume_step(self, real_units)
		return real_units

	var scaled_in: Mixture = mixture_in.scaled_fraction(source_fraction, false)
	scaled_in.ensure_tags()
	scaled_in.tags["vol_u"] = real_units
	(scaled_in.tags as Dictionary).erase("pH")
	(scaled_in.tags as Dictionary).erase("ph_samples")

	var had_pellet := _has_pellet_ready()

	mixture.merge_from(scaled_in)
	_set_fill_level(min(1.0, fill_level + real_units / max(0.0001, capacity_units)))

	if had_pellet:
		ever_precipitated = false
		turbidity_target = 0.0
		display_turbidity = 0.0
		_set_turbidity_value(0.0)
		mixture.tags["pellet_ready"] = true
	else:
		var bump: float = initial_turbidity + 0.05
		turbidity_target = max(turbidity_target, bump)
		display_turbidity = max(display_turbidity, bump)
		_set_turbidity_value(display_turbidity)

	_schedule_recalc()
	return real_units


func _set_fill_level(value: float) -> void:
	fill_level = clamp(value, 0.0, 1.0)
	_apply_liquid_fill_visual()


func _apply_liquid_fill_visual() -> void:
	var level01: float = clamp(fill_level, 0.0, 1.0)
	var visual_scale: float = level01 if (pellet != null and pellet.visible) else max(min_fill_level, level01)

	if liquid_body:
		liquid_body.scale.y = visual_scale

	if turbidity:
		var turbidity_material := turbidity.material as ShaderMaterial
		if turbidity_material and turbidity_material.shader and _shader_has_uniform(turbidity_material, "level01"):
			_set_shader_param_safe(turbidity_material, "level01", level01)

	if liquid_level_sprite:
		var level_material := liquid_level_sprite.material as ShaderMaterial
		if level_material and level_material.shader and _shader_has_uniform(level_material, "level01"):
			_set_shader_param_safe(level_material, "level01", level01)

	if crystal_fx:
		var crystal_material := crystal_fx.material as ShaderMaterial
		if crystal_material and crystal_material.shader:
			if _shader_has_uniform(crystal_material, "level01"):
				_set_shader_param_safe(crystal_material, "level01", clamp(fill_level, 0.0, 1.0))
			if _shader_has_uniform(crystal_material, "use_mask"):
				crystal_material.set_shader_parameter("use_mask", true)
				if liquid_body and liquid_body.texture:
					crystal_material.set_shader_parameter("mask_tex", liquid_body.texture)
					var mask_size: Vector2i = liquid_body.texture.get_size()
					if mask_size.x > 0 and mask_size.y > 0 and _shader_has_uniform(crystal_material, "mask_texel"):
						crystal_material.set_shader_parameter(
							"mask_texel",
							Vector2(1.0 / float(mask_size.x), 1.0 / float(mask_size.y))
						)


func _apply_turbidity_level(level: float, color: Color) -> void:
	if turbidity == null:
		return

	var turbidity_material := turbidity.material as ShaderMaterial
	if turbidity_material and turbidity_material.shader:
		_set_shader_param_safe(turbidity_material, "fog_color", color)
		_set_shader_param_safe(turbidity_material, "turbidity", level)
	else:
		var c: Color = turbidity.modulate
		c.a = level
		turbidity.modulate = c


func _set_turbidity_value(value: float) -> void:
	if _has_pellet_ready():
		_apply_turbidity_level(0.0, turbidity_color)
		ever_precipitated = false
		return

	var t: float = clamp(value, 0.0, 1.0)
	_apply_turbidity_level(t, turbidity_color)


func _burst_turbidity(color: Color, amount: float) -> void:
	if _has_pellet_ready() or turbidity == null:
		return

	var burst_amount: float = clamp(amount, 0.0, 1.0)
	turbidity_target = max(turbidity_target, burst_amount)

	var turbidity_material := turbidity.material as ShaderMaterial

	if turbidity_material and turbidity_material.shader:
		_set_shader_param_safe(turbidity_material, "fog_color", color)

		var start_turbidity: float = 0.0
		var cur_val: Variant = turbidity_material.get_shader_parameter("turbidity")
		if cur_val is float or cur_val is int:
			start_turbidity = float(cur_val)

		var target: float = max(start_turbidity, burst_amount)

		create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT) \
			.tween_method(
				func(new_t: float) -> void:
					_apply_turbidity_level(new_t, color),
				start_turbidity,
				target,
				0.25
			)
	else:
		var start_alpha: float = turbidity.modulate.a
		var target_alpha: float = max(start_alpha, burst_amount)

		create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT) \
			.tween_property(turbidity, "modulate:a", target_alpha, 0.25)


func _grow_sediment(color: Color, delta_amount: float) -> void:
	if sediment == null:
		return
	sediment.visible = true
	var solid_color := color
	solid_color.a = 1.0
	sediment.modulate = solid_color
	sediment_level = clamp(sediment_level + delta_amount, 0.0, 1.0)
	create_tween().tween_property(sediment, "scale:y", sediment_level, 0.6)


func _set_shader_param_safe(shader_material: ShaderMaterial, param_name: String, value) -> void:
	if shader_material == null or shader_material.shader == null:
		return
	for uniform in shader_material.shader.get_shader_uniform_list():
		var uniform_dict: Dictionary = uniform
		if String(uniform_dict.get("name", "")) == param_name:
			shader_material.set_shader_parameter(param_name, value)
			return


func _shader_has_uniform(shader_material: ShaderMaterial, uniform_name: String) -> bool:
	if shader_material == null or shader_material.shader == null:
		return false
	for uniform in shader_material.shader.get_shader_uniform_list():
		var uniform_dict: Dictionary = uniform
		if String(uniform_dict.get("name", "")) == uniform_name:
			return true
	return false


func _schedule_recalc() -> void:
	if _has_pellet_ready():
		return
	if _recalc_scheduled:
		return
	_recalc_scheduled = true
	call_deferred("_run_recalc")


func _run_recalc() -> void:
	_recalc_scheduled = false
	if Qualengine and Qualengine.has_method("on_mixture_changed"):
		Qualengine.on_mixture_changed(self)


func _clear_contents_completely() -> void:
	if mixture and mixture.has_method("clear_all"):
		mixture.clear_all()
	else:
		mixture = Mixture.new()

	if not (mixture.tags is Dictionary):
		mixture.tags = {}

	(mixture.tags as Dictionary).erase("pH")
	(mixture.tags as Dictionary).erase("ph_samples")

	ever_precipitated = false
	suspended = 0.0
	precip_total = 0.0
	turbidity_color = Color.WHITE
	sediment_color  = Color.WHITE
	turbidity_target = initial_turbidity
	display_turbidity = initial_turbidity
	_set_turbidity_value(display_turbidity)

	if sediment:
		sediment_level = 0.0
		sediment.scale.y = 0.0
		sediment.visible = false

	if crystal_fx:
		var crystal_material := crystal_fx.material as ShaderMaterial
		if crystal_material and crystal_material.shader and _shader_has_uniform(crystal_material, "progress"):
			crystal_material.set_shader_parameter("progress", 0.0)
		crystal_fx.visible = false

	if pellet:
		pellet.visible = false
		pellet.modulate = Color(1, 1, 1, 1)

	if mixture and (mixture.tags is Dictionary):
		(mixture.tags as Dictionary).erase("pellet_ready")


func _update_cooling(delta: float) -> void:
	if not (mixture.tags is Dictionary):
		return

	var tags: Dictionary = mixture.tags

	if not bool(tags.get(TAG_COOLING_READY, false)):
		return

	if bool(tags.get(TAG_BATH_BOILING, false)):
		tags[TAG_COOLING_T] = 0.0
		tags.erase(TAG_COOLED_ENOUGH)
		return

	var cooling_time: float = 0.0
	var cooling_time_tag: Variant = tags.get(TAG_COOLING_T, 0.0)
	if cooling_time_tag is float or cooling_time_tag is int:
		cooling_time = float(cooling_time_tag)

	cooling_time += max(0.0, delta)
	tags[TAG_COOLING_T] = cooling_time

	if cooling_time >= max(0.0, cooling_time_s) and not bool(tags.get(TAG_COOLED_ENOUGH, false)):
		tags[TAG_COOLED_ENOUGH] = true
		_schedule_recalc()


func clear_precip_fx(fade_sec: float = 0.35) -> void:
	var start_turbidity := display_turbidity
	var target_turbidity := initial_turbidity
	var fade_time : Variant = max(0.0, fade_sec)

	var main_tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	main_tween.tween_method(func(value): _set_turbidity_value(value), start_turbidity, target_turbidity, fade_time)

	if sediment:
		var sediment_tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		sediment_tween.tween_property(sediment, "scale:y", 0.0, fade_time)
		create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT) \
			.tween_property(sediment, "modulate:a", 0.0, fade_time)
		sediment_tween.finished.connect(func () -> void:
			if sediment:
				sediment.visible = false
				sediment_level = 0.0)

	if crystal_fx:
		var crystal_material := crystal_fx.material as ShaderMaterial
		if crystal_material and crystal_material.shader and _shader_has_uniform(crystal_material, "progress"):
			var current_progress := 0.0
			var progress_value: Variant = crystal_material.get_shader_parameter("progress")
			if progress_value is float:
				current_progress = float(progress_value)
			create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT) \
				.tween_method(
					func(value): crystal_material.set_shader_parameter("progress", value),
					current_progress,
					0.0,
					fade_time
				)

		var crystal_fade := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		crystal_fade.tween_property(crystal_fx, "modulate:a", 0.0, fade_time)
		crystal_fade.finished.connect(func () -> void:
			if crystal_fx:
				crystal_fx.visible = false
				var crystal_material2 := crystal_fx.material as ShaderMaterial
				if crystal_material2 and crystal_material2.shader and _shader_has_uniform(crystal_material2, "progress"):
					crystal_material2.set_shader_parameter("progress", 0.0)
				var fx_color: Color = crystal_fx.modulate
				fx_color.a = 1.0
				crystal_fx.modulate = fx_color)

	if pellet:
		pellet.visible = false
		pellet.modulate = Color(1, 1, 1, 1)

	if mixture and (mixture.tags is Dictionary):
		(mixture.tags as Dictionary).erase("pellet_ready")

	turbidity_target = initial_turbidity
	display_turbidity = initial_turbidity

	ever_precipitated = false
	suspended = 0.0
	precip_total = 0.0


func _show_crystal_fx(color: Color, progress_target: float) -> void:
	if _has_pellet_ready():
		return
	if not crystal_fx:
		return

	crystal_fx.visible = true
	crystal_fx.modulate.a = 1.0

	var crystal_material := crystal_fx.material as ShaderMaterial
	if crystal_material and crystal_material.shader:
		if _shader_has_uniform(crystal_material, "crystal_color"):
			crystal_material.set_shader_parameter("crystal_color", color)
		if _shader_has_uniform(crystal_material, "progress"):
			var start_progress := 0.0
			var current_progress_value: Variant = crystal_material.get_shader_parameter("progress")
			if current_progress_value is float:
				start_progress = float(current_progress_value)
			create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT) \
				.tween_method(
					func(value): crystal_material.set_shader_parameter("progress", value),
					start_progress,
					clamp(progress_target, 0.0, 1.0),
					0.4
				)


func _hide_crystal_fx() -> void:
	if not crystal_fx:
		return
	var crystal_material := crystal_fx.material as ShaderMaterial
	if crystal_material and crystal_material.shader and _shader_has_uniform(crystal_material, "progress"):
		crystal_material.set_shader_parameter("progress", 0.0)
	crystal_fx.visible = false


func _crystal_fx_active() -> bool:
	if crystal_fx == null:
		return false
	if not crystal_fx.visible:
		return false
	var crystal_material := crystal_fx.material as ShaderMaterial
	if crystal_material and crystal_material.shader and _shader_has_uniform(crystal_material, "progress"):
		var progress_value: Variant = crystal_material.get_shader_parameter("progress")
		if progress_value is float:
			return float(progress_value) > 0.01
	return crystal_fx.modulate.a > 0.01


func on_centrifuge_compact() -> void:
	last_precip_mode = "floc"
	if _crystal_fx_active():
		last_precip_mode = "crystal"
	had_crystal_before_spin = (last_precip_mode == "crystal")

	_hide_crystal_fx()

	var pellet_color := sediment_color
	if pellet_color == Color.WHITE and turbidity_color != Color.WHITE:
		pellet_color = turbidity_color

	show_pellet(true, pellet_color)

	suspended = 0.0
	precip_total = 0.0
	turbidity_target = 0.0
	display_turbidity = 0.0
	_set_turbidity_value(0.0)


func _has_pellet_ready() -> bool:
	return (pellet != null and pellet.visible) \
		or ((mixture.tags is Dictionary) and bool(mixture.tags.get("pellet_ready", false)))


func show_pellet(on: bool, color: Color = Color.WHITE) -> void:
	if pellet == null:
		return
	if not on:
		hide_pellet()
		return

	var alpha: float = clamp(pellet_opacity, 0.0, 1.0)
	var final_pellet_color := Color(color.r * pellet_brightness, color.g * pellet_brightness, color.b * pellet_brightness, alpha)
	pellet.modulate = final_pellet_color
	pellet.visible = true

	ever_precipitated = false
	turbidity_target = 0.0
	display_turbidity = 0.0
	_set_turbidity_value(0.0)

	if mixture and (mixture.tags is Dictionary):
		mixture.tags["pellet_ready"] = true


func show_pellet_from_sediment() -> void:
	show_pellet(true, sediment_color)


func hide_pellet() -> void:
	if pellet:
		pellet.visible = false
		pellet.modulate = Color(1, 1, 1, 1)
	if mixture and (mixture.tags is Dictionary):
		(mixture.tags as Dictionary).erase("pellet_ready")


func stir_with_rod(strength: float = 0.6) -> void:
	var stir_strength: float = clamp(strength, 0.0, 1.0)

	if not has_any_liquid() and not _has_pellet_ready():
		return

	var was_pellet := _has_pellet_ready()

	if was_pellet:
		hide_pellet()
		if last_precip_mode == "crystal" or had_crystal_before_spin:
			ever_precipitated = false
			turbidity_target = initial_turbidity
			display_turbidity = initial_turbidity
			_set_turbidity_value(display_turbidity)
			var prog: float = clamp(0.35 + 0.6 * stir_strength, 0.0, 1.0)
			_show_crystal_fx(sediment_color, prog)
			last_precip_mode = "crystal"
		else:
			_hide_crystal_fx()
			ever_precipitated = true
			var kick: float = clamp(0.15 * stir_strength + sediment_level * 0.7, 0.0, 1.0)
			suspended = clamp(suspended + kick, 0.0, 1.0)
			var bump :Variant= max(suspended, initial_turbidity + 0.1 * stir_strength)
			turbidity_target = clamp(max(turbidity_target, bump), turbidity_floor, 1.0)
			display_turbidity = max(display_turbidity, bump)
			turbidity_color = sediment_color
			_set_turbidity_value(display_turbidity)
			_burst_turbidity(sediment_color, display_turbidity)
			settle_delay_left = settle_delay
			last_precip_mode = "floc"

		_schedule_recalc()
		return

	if _crystal_fx_active():
		hide_pellet()
		ever_precipitated = false
		suspended = 0.0
		turbidity_target = max(turbidity_target, initial_turbidity)
		display_turbidity = max(display_turbidity, initial_turbidity)
		_set_turbidity_value(display_turbidity)
		var prog_target: float = clamp(0.35 + 0.45 * stir_strength, 0.0, 1.0)
		_show_crystal_fx(sediment_color, prog_target)
		last_precip_mode = "crystal"
		settle_delay_left = 0.0
		_schedule_recalc()
		return

	if not has_any_liquid():
		return

	if not _has_any_precipitate_or_suspension():
		ever_precipitated = false
		suspended = 0.0
		turbidity_target = initial_turbidity
		display_turbidity = initial_turbidity
		_set_turbidity_value(display_turbidity)
		return

	hide_pellet()
	_hide_crystal_fx()
	ever_precipitated = true

	var kick2: float = clamp(0.15 * stir_strength + sediment_level * 0.7, 0.0, 1.0)
	suspended = clamp(suspended + kick2, 0.0, 1.0)
	var bump2 :Variant= max(suspended, initial_turbidity + 0.1 * stir_strength)
	turbidity_target = clamp(max(turbidity_target, bump2), turbidity_floor, 1.0)
	display_turbidity = max(display_turbidity, bump2)
	turbidity_color = sediment_color
	_set_turbidity_value(display_turbidity)
	_burst_turbidity(sediment_color, display_turbidity)
	settle_delay_left = settle_delay

	_schedule_recalc()


func resuspend_pellet(strength: float = 0.6) -> void:
	stir_with_rod(strength)


func _force_crystal_fx_off() -> void:
	if not crystal_fx:
		return
	crystal_fx.visible = false
	var crystal_material := crystal_fx.material as ShaderMaterial
	if crystal_material and crystal_material.shader and _shader_has_uniform(crystal_material, "progress"):
		crystal_material.set_shader_parameter("progress", 0.0)
	var fx_color := crystal_fx.modulate
	fx_color.a = 0.0
	crystal_fx.modulate = fx_color


func _has_any_precipitate_or_suspension() -> bool:
	if _has_pellet_ready():
		return true
	if suspended > 0.000001 or precip_total > 0.000001 or sediment_level > 0.000001:
		return true
	if mixture and (mixture.solids is Dictionary) and mixture.solids.size() > 0:
		return true
	if _crystal_fx_active():
		return true
	return false
