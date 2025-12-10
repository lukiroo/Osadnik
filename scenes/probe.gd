extends Node2D
class_name Probe
 
## =========================================================================
## probe.gd – probówka robocza / startowa
## -------------------------------------------------------------------------
## Odpowiada za:
## - przechowywanie mieszaniny chemicznej (Mixture),
## - komunikację z QualEngine (reakcje, pH, bufory),
## - obsługę drag & drop (przenoszenie probówki po stole i między slotami),
## - pokazywanie mętności, kryształków i pelletu po wirowaniu,
## - obsługę chłodzenia w łaźni (cooling_ready / cooled_enough),
## - obsługę narzędzi z poziomu Lab (dropper, papierek, bagietka, butelka z wodą).
## =========================================================================

enum TubeRole { STARTER, WORK }

@export_group("Rola probówki")
@export var tube_role: TubeRole = TubeRole.WORK

signal drag_started(probe: Node)
signal drag_ended(probe: Node)
signal drag_released(probe: Node, at_global_pos: Vector2)

# -----------------------------
# Referencje do pod-węzłów
# -----------------------------

@onready var area: Area2D            = $ProbeArea2D
@onready var glass_sprite: Sprite2D  = $GlassSprite2D
@onready var turbidity: Sprite2D     = $LiquidFill/TurbidityOverlay
@onready var crystal_fx: Sprite2D    = $LiquidFill/CrystalFX
@onready var pellet: Sprite2D        = $LiquidFill/Pellet
@onready var label: Label            = $NumLabel

@onready var liquid_body: Sprite2D          = $LiquidFill/LiquidBody
@onready var liquid_level_sprite: Sprite2D  = $LiquidFill/LiquidLevelSprite2D

var glass_mat: ShaderMaterial = null
var hover_enabled: bool = false


# =========================================================================
# DRAG & DROP – parametry i stan
# =========================================================================

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


# =========================================================================
# ANIMACJA WYLEWANIA (pivot)
# =========================================================================

@export_group("Animacja wylewania")
@export_range(-200.0, 200.0, 1.0) var pivot_offset_y: float = -50.0
@export_range(0.0, 180.0, 1.0) var dump_tilt_deg: float = 120.0
@export_range(0.0, 1.0, 0.01) var dump_tilt_time: float = 0.18
@export_range(0.0, 1.0, 0.01) var dump_tilt_hold: float = 0.07

var _dump_anim_pending: bool = false
var _tilt_node: Node2D = null


# =========================================================================
# CHEMIA I OBJĘTOŚĆ
# =========================================================================

@export_group("Chemia i objętość")
@export var mixture: Mixture = Mixture.new()

@export_subgroup("Poziom cieczy")
@export_range(0.0, 1.0, 0.01) var fill_level: float = 1.0
@export_range(0.0, 0.5, 0.01) var min_fill_level: float = 0
@export_range(0.05, 15.0, 0.05) var capacity_units: float = 1.0

@export_subgroup("Krople reagentów")
@export_range(0.0, 0.5, 0.005) var reagent_level_per_drop: float = 0.10


# =========================================================================
# MĘTNOŚĆ / KOLOR CIECZY
# =========================================================================

@export_group("Mętność / kolor cieczy")
@export_range(0.0, 1.0, 0.01) var initial_turbidity: float = 0.0

## Przechowuje aktualny kolor mętności / osadu w zawiesinie.
var turbidity_color: Color = Color.WHITE

## Docelowy poziom mętności (do interpolacji).
var turbidity_target: float = 0.0

## Rzeczywisty poziom mętności pokazywany użytkownikowi.
var display_turbidity: float = 0.0

## Informuje, czy kiedykolwiek w tej probówce strącił się osad.
var ever_precipitated: bool = false

## Informuje, że przeliczenie reakcji jest zaplanowane (call_deferred).
var _recalc_scheduled: bool = false


# =========================================================================
# CHŁODZENIE (ŁAŹNIA WODNA)
# =========================================================================

@export_group("Chłodzenie (łaźnia)")
@export_range(0.0, 60.0, 0.5) var cooling_time_s: float = 80.0

const TAG_BATH_BOILING   := "bath_boiling"
const TAG_COOLING_READY  := "cooling_ready"
const TAG_COOLING_T      := "cooling_t_s"
const TAG_COOLED_ENOUGH  := "cooled_enough"


# =========================================================================
# PELLET / KRYSTALIZACJA (FX)
# =========================================================================

@export_group("Pellet / krystalizacja (FX)")
@export_range(0.0, 2.0, 0.01) var pellet_brightness: float = 0.9
@export_range(0.0, 1.0, 0.01) var pellet_opacity: float = 1.0

## Ostatni tryb osadu, jaki był użyty do FX ("none"/"floc"/"crystal").
var last_precip_mode: String = "none"

## Informuje, czy przed wirowaniem występował krystaliczny osad.
var had_crystal_before_spin: bool = false

const FILL_EPS := 0.001


# =========================================================================
# INICJALIZACJA PROBÓWKI
# =========================================================================

## Przygotowuje probówkę po dodaniu do sceny:
## - duplikuje materiały, żeby uniformy były per-probówka,
## - ustawia shader menisku,
## - przygotowuje początkowe FX (mętność, crystal_fx, pellet),
## - tworzy pivot do animacji wylewania i przenosi dzieci pod _Tilt.
func _ready() -> void:
	# oddzielne materiały na każdą probówkę
	if glass_sprite.material:
		glass_sprite.material = glass_sprite.material.duplicate()
	if turbidity and turbidity.material:
		turbidity.material = turbidity.material.duplicate()
	if liquid_level_sprite and liquid_level_sprite.material:
		liquid_level_sprite.material = liquid_level_sprite.material.duplicate()
	if crystal_fx and crystal_fx.material:
		crystal_fx.material = crystal_fx.material.duplicate()

	glass_mat = glass_sprite.material as ShaderMaterial

	# materiał od menisku
	if liquid_level_sprite:
		liquid_level_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var level_material := liquid_level_sprite.material as ShaderMaterial
		if level_material and level_material.shader:
			if _shader_has_uniform(level_material, "use_mask"):
				level_material.set_shader_parameter("use_mask", true)
				if liquid_body and liquid_body.texture:
					level_material.set_shader_parameter("mask_tex", liquid_body.texture)
					var size: Vector2i = liquid_body.texture.get_size()
					if size.x > 0 and size.y > 0:
						level_material.set_shader_parameter(
							"mask_texel",
							Vector2(1.0 / float(size.x), 1.0 / float(size.y))
						)
			if _shader_has_uniform(level_material, "edge_softness_px"):
				level_material.set_shader_parameter("edge_softness_px", 0.5)

	_apply_highlight(false)
	add_to_group("probes")

	# startowe FX
	turbidity_color = Color.WHITE
	turbidity_target = clamp(initial_turbidity, 0.0, 1.0)
	display_turbidity = turbidity_target
	_set_turbidity_value(display_turbidity)

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

	# pivot do animacji wylewania
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



	# --- konfiguracja turbidity: maska = LiquidBody ---
	if turbidity and turbidity.material is ShaderMaterial and liquid_body and liquid_body.texture:
		var tmat := turbidity.material as ShaderMaterial
		tmat.set_shader_parameter("use_mask", true)
		tmat.set_shader_parameter("mask_tex", liquid_body.texture)
		var size: Vector2i = liquid_body.texture.get_size()
		if size.x > 0 and size.y > 0:
			tmat.set_shader_parameter("mask_texel", Vector2(1.0 / float(size.x), 1.0 / float(size.y)))

	_apply_liquid_fill_visual()
	# dalej pivot, _Tilt itd...


## Aktualizuje probówkę w każdej klatce:
## - przelicza chłodzenie dla łaźni wodnej,
## - płynnie „dochodzi” do nowej mętności.
func _physics_process(delta: float) -> void:
	_update_cooling(delta)

	var step: float = 4.0 * delta
	display_turbidity = move_toward(display_turbidity, turbidity_target, step)
	_set_turbidity_value(display_turbidity)
	# Pellet jest osobnym sprite’em – mętność może współistnieć z pelletem.


# =========================================================================
# OBSŁUGA REAGENTÓW / ROZTWORÓW W PROBÓWCE
# =========================================================================

## Zgłasza do probówki, że ma wykonać animację „wylewania” po upuszczeniu.
func request_dump_anim() -> void:
	_dump_anim_pending = true


## Sprawdza, czy probówka jest pełna (fill_level ~ 1.0).
func is_full() -> bool:
	return fill_level >= 1.0 - FILL_EPS


## Odbiera porcję reagentu z butelki (HCl, NaOH itd.):
## - sprawdza przepełnienie,
## - woła QualEngine.add_drop_to_tube,
## - podbija fill_level o reagent_level_per_drop.
func receive_drop(reagent_id: String) -> void:
	if is_full():
		return

	Qualengine.add_drop_to_tube(self, reagent_id)

	if reagent_level_per_drop > 0.0:
		var level_delta: float = reagent_level_per_drop / max(0.0001, capacity_units)
		_set_fill_level(min(1.0, fill_level + level_delta))


## Zwraca „ocenę pH” w skali -3..+3 na podstawie Mixture.tags["ph_grade7"].
func get_indicator_grade() -> int:
	return _get_ph_grade7()


## Zwraca słownik {grade, ph} – na razie ph = NAN (opcjonalne rozwinięcie).
func get_indicator_grade_and_ph() -> Dictionary:
	return {"grade": _get_ph_grade7(), "ph": NAN}


## Odczytuje ph_grade7 z tags i zwraca go jako int.
func _get_ph_grade7() -> int:
	if mixture.tags is Dictionary:
		var grade_val: Variant = (mixture.tags as Dictionary).get("ph_grade7", null)
		if grade_val is int or grade_val is float:
			return int(grade_val)
	return 0


# =========================================================================
# FX: OSAD, MĘTNOŚĆ, KRYSZTAŁKI
# =========================================================================

## Wyświetla efekt strącenia osadu (floc/crystal/cloudy) w probówce:
## - ustawia last_precip_mode i turbidity_color,
## - dla trybu "crystal" odpala CrystalFX i lekko mąci roztwór,
## - dla floc/cloudy ustawia mętność na docelowy poziom.
func play_precip(mode: String, turb_color: Color, _sed_color: Color, intensity: float) -> void:
	last_precip_mode = mode
	ever_precipitated = true
	turbidity_color = turb_color

	var amount: float = clamp(intensity, 0.0, 1.0)

	if mode == "crystal":
		_show_crystal_fx(turbidity_color, amount)
		turbidity_target = max(initial_turbidity, 0.3 * amount)
	else:
		_hide_crystal_fx()
		turbidity_target = max(turbidity_target, max(initial_turbidity, amount))


# =========================================================================
# HIGHLIGHT I INPUT MYSZY NA PROBÓWCE
# =========================================================================

## Ustawia włączenie/wyłączenie highlightu probówki.
func set_highlight_enabled(enabled: bool) -> void:
	hover_enabled = enabled
	if not enabled:
		_apply_highlight(false)


## Reaguje na wejście kursora w obszar probówki – włącza highlight.
func _on_probe_area_2d_mouse_entered() -> void:
	if hover_enabled:
		_apply_highlight(true)


## Reaguje na wyjście kursora z obszaru probówki – wyłącza highlight.
func _on_probe_area_2d_mouse_exited() -> void:
	_apply_highlight(false)


## Ustawia parametry highlightu w shaderze szkła.
func _apply_highlight(on: bool) -> void:
	if glass_mat == null:
		return
	_set_shader_param_safe(glass_mat, "highlight", on)
	_set_shader_param_safe(glass_mat, "highlight_strength", (1.0 if on else 0.0))


## Reaguje na kliknięcia LPM na obszarze probówki:
## - w zależności od trybu Lab (HOLDING/TRANSFER/INDICATOR/STIR_ROD/SQUIRT)
##   przekazuje kontrolę do odpowiednich metod w Lab.gd,
## - w IDLE uruchamia drag & drop probówki.
func _on_probe_area_2d_input_event(_vp: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if _returning:
		get_viewport().set_input_as_handled()
		return

	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return

	var lab: Node = get_tree().get_first_node_in_group("lab_root")
	if lab == null:
		return

	var ModeEnum = lab.Mode
	var cur_mode = lab.mode

	if cur_mode == ModeEnum.STIR_ROD:
		lab._stir_rod_use_on_probe(self)
		get_viewport().set_input_as_handled()
		return

	if cur_mode == ModeEnum.INDICATOR:
		if lab.has_method("_indicator_use_on_probe"):
			lab._indicator_use_on_probe(self)
		else:
			lab._indicator_use(self)
		get_viewport().set_input_as_handled()
		return

	if cur_mode == ModeEnum.TRANSFER:
		var dropper_is_loaded: bool = bool(lab.dropper_loaded)
		if not dropper_is_loaded:
			if has_any_liquid():
				lab._dropper_pick(self)
		else:
			lab._dropper_drop(self)
		get_viewport().set_input_as_handled()
		return

	if cur_mode == ModeEnum.SQUIRT:
		lab._squirt_begin(self)
		return

	if cur_mode == ModeEnum.HOLDING:
		var reagent_id := String(lab.active_reagent_id)
		if reagent_id != "":
			receive_drop(reagent_id)
			get_viewport().set_input_as_handled()
		return

	if cur_mode == ModeEnum.PLATIN_ROD:
		lab._platin_rod_use_on_probe(self)
		get_viewport().set_input_as_handled()
		return

	if draggable:
		_start_drag()
		get_viewport().set_input_as_handled()


## Obsługuje ruch myszy i puszczenie LPM w trakcie dragowania probówki.
func _input(event: InputEvent) -> void:
	if _returning or not _dragging:
		return

	if event is InputEventMouseMotion:
		global_position = get_global_mouse_position() + _drag_offset
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_end_drag(true)
		get_viewport().set_input_as_handled()


# =========================================================================
# DRAG & DROP – LOGIKA PRZECIĄGANIA PROBÓWKI
# =========================================================================

## Startuje drag & drop probówki:
## - ustawia wewnętrzny stan dragowania,
## - podnosi probówkę (z-index),
## - zgłasza do Lab i parenta, że probówka została podniesiona.
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
	if lab:
		lab.probe_drag_started()


## Kończy drag & drop probówki:
## - próbuje umieścić probówkę w dropzone,
## - w razie niepowodzenia odtwarza animację powrotu,
## - zgłasza sygnały drag_released / drag_ended.
func _end_drag(emit_release: bool) -> void:
	if not _dragging:
		return

	_dragging = false

	var lab := get_tree().get_first_node_in_group("lab_root")
	if lab:
		lab.probe_drag_ended()

	var accepted: bool = _try_drop_into_target()

	if not accepted and _dump_anim_pending:
		_returning = true
		_dump_anim_pending = false

		var rotate_node: Node2D = _tilt_node if _tilt_node else self
		var angle := -dump_tilt_deg

		var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(rotate_node, "rotation_degrees", angle, dump_tilt_time)
		tween.tween_interval(dump_tilt_hold)
		tween.tween_property(rotate_node, "rotation_degrees", 0.0, 0.16)
		tween.finished.connect(func() -> void:
			_start_return_tween(accepted))
	else:
		_start_return_tween(accepted)

	z_index = _drag_origin_z

	if emit_release:
		emit_signal("drag_released", self, global_position)
	emit_signal("drag_ended", self)


## Startuje tween powrotu probówki na miejsce początkowe albo tylko kończy stan „returning”.
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


## Zamyka stan „returning” po animacji powrotu.
func _unlock_returning() -> void:
	_returning = false


## Próbuje odłożyć probówkę do dropzone z grupy "probe_dropzones".
func _try_drop_into_target() -> bool:
	for dropzone in get_tree().get_nodes_in_group("probe_dropzones"):
		if dropzone and dropzone.has_method("accept_probe"):
			if dropzone.accept_probe(self, global_position) == true:
				return true
	return false


# =========================================================================
# OPERACJE NA MIESZANINIE (OD STRONY PROBÓWKI)
# =========================================================================

## Sprawdza, czy probówka zawiera jakąkolwiek ciecz (kolumnę roztworu).
## - same solids (pellet) bez supernatantu nie liczą się jako „ciecz do pracy”.
func has_any_liquid() -> bool:
	if fill_level > 0.001:
		return true

	if mixture.ions is Dictionary and mixture.ions.size() > 0:
		return true

	return false


## Pobiera z probówki określoną ilość units (vol_u) do droppera:
## - zwraca słownik {"mix": Mixture, "units": real_units},
## - przy pellecie: supernatant nie niesie solids, pellet zostaje w probówce,
## - przy zwykłej zawiesinie: jony i osady dzielą się proporcjonalnie.
func take_volume(units: float):
	var requested_units: float = max(0.0, units)
	var max_units: float = fill_level * capacity_units
	if requested_units <= 0.0 or max_units <= 0.00001:
		return null

	var real_units: float = min(requested_units, max_units)

	if not (mixture.tags is Dictionary):
		mixture.tags = {}

	var total_volume: float = 0.0
	var vol_tag: Variant = mixture.tags.get("vol_u", 0.0)
	if vol_tag is float or vol_tag is int:
		total_volume = float(vol_tag)

	if total_volume <= 1e-9:
		total_volume = max_units
		mixture.tags["vol_u"] = total_volume

	var fraction: float = clamp(real_units / max(1e-9, total_volume), 0.0, 1.0)
	var had_pellet: bool = _has_pellet_ready()

	var taken: Mixture = mixture.scaled_fraction(fraction, false)
	taken.ensure_tags()
	taken.tags["vol_u"] = real_units
	(taken.tags as Dictionary).erase("pH")
	(taken.tags as Dictionary).erase("ph_samples")

	if had_pellet:
		taken.solids.clear()
		(taken.tags as Dictionary).erase("precip_mode")

		var solids_backup: Dictionary = {}
		if mixture.solids is Dictionary:
			solids_backup = mixture.solids.duplicate(true)

		mixture.subtract_fraction_in_place(fraction)

		if solids_backup.size() > 0:
			mixture.solids = solids_backup
	else:
		mixture.subtract_fraction_in_place(fraction)

	_set_fill_level(fill_level - real_units / max(0.0001, capacity_units))

	if fill_level <= 0.0001 and not had_pellet:
		_clear_contents_completely()
		_schedule_recalc()

	return {"mix": taken, "units": real_units}


## Pobiera ułamek objętości probówki (np. 0.5) i zwraca Mixture (bez słownika).
func take_fraction(frac: float) -> Mixture:
	var f: float = clamp(frac, 0.0, 1.0)
	var result: Variant = take_volume(f * capacity_units)
	if result == null:
		return null
	return result["mix"] as Mixture


## Odbiera mieszaninę wylewaną z droppera:
## - obsługuje czystą wodę (pasuje do QualEngine.add_water_volume_step),
## - dla zwykłej mieszaniny skaluje porę i scala ją z mixture,
## - przy pellecie resetuje FX mętności, zostawiając pellet jako stan.
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
		var tag_val: Variant = mixture_in.tags.get("vol_u", 0.0)
		if tag_val is float or tag_val is int:
			source_total_volume = float(tag_val)
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


## Ustawia fill_level i odświeża wizualizację kolumny cieczy w probówce.
func _set_fill_level(value: float) -> void:
	fill_level = clamp(value, 0.0, 1.0)
	_apply_liquid_fill_visual()


## Aktualizuje wizualną wysokość cieczy i powiązane shadery.
func _apply_liquid_fill_visual() -> void:
	var level01: float = clamp(fill_level, 0.0, 1.0)

	# wysokość cieczy – LiquidBody
	if liquid_body:
		liquid_body.scale.y = level01

	# poziom menisku (shader)
	if liquid_level_sprite:
		var level_material := liquid_level_sprite.material as ShaderMaterial
		if level_material and level_material.shader and _shader_has_uniform(level_material, "level01"):
			_set_shader_param_safe(level_material, "level01", level01)

	# turbidity – tylko uniform level01, BEZ skalowania sprite’a
	if turbidity:
		var turb_mat := turbidity.material as ShaderMaterial
		if turb_mat and turb_mat.shader and _shader_has_uniform(turb_mat, "level01"):
			_set_shader_param_safe(turb_mat, "level01", level01)

	# (opcjonalnie) maska dla crystal_fx tak jak wcześniej
	if crystal_fx:
		var crystal_material := crystal_fx.material as ShaderMaterial
		if crystal_material and crystal_material.shader:
			if _shader_has_uniform(crystal_material, "level01"):
				_set_shader_param_safe(crystal_material, "level01", level01)
			if _shader_has_uniform(crystal_material, "use_mask"):
				crystal_material.set_shader_parameter("use_mask", true)
				if liquid_body and liquid_body.texture:
					crystal_material.set_shader_parameter("mask_tex", liquid_body.texture)
					var size: Vector2i = liquid_body.texture.get_size()
					if size.x > 0 and size.y > 0 and _shader_has_uniform(crystal_material, "mask_texel"):
						crystal_material.set_shader_parameter(
							"mask_texel",
							Vector2(1.0 / float(size.x), 1.0 / float(size.y))
						)



# =========================================================================
# MĘTNOŚĆ – SHADER I FALLBACK
# =========================================================================

## Ustawia poziom mętności w shaderze lub przez alpha modulate.
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


## Ustawia docelową wartość mętności (clamp) i przekazuje ją do _apply_turbidity_level.
func _set_turbidity_value(value: float) -> void:
	var clamped_value: float = clamp(value, 0.0, 1.0)
	_apply_turbidity_level(clamped_value, turbidity_color)


# =========================================================================
# SHADER – HELPERY
# =========================================================================

## Ustawia parametr shaderowy tylko jeśli shader posiada odpowiedni uniform.
func _set_shader_param_safe(shader_material: ShaderMaterial, param_name: String, value) -> void:
	if shader_material == null or shader_material.shader == null:
		return
	for uniform in shader_material.shader.get_shader_uniform_list():
		var info: Dictionary = uniform
		if String(info.get("name", "")) == param_name:
			shader_material.set_shader_parameter(param_name, value)
			return


## Sprawdza, czy shader posiada uniform o danej nazwie.
func _shader_has_uniform(shader_material: ShaderMaterial, uniform_name: String) -> bool:
	if shader_material == null or shader_material.shader == null:
		return false
	for uniform in shader_material.shader.get_shader_uniform_list():
		var info: Dictionary = uniform
		if String(info.get("name", "")) == uniform_name:
			return true
	return false


# =========================================================================
# KOMUNIKACJA Z QUALENGINE
# =========================================================================

## Planowo zgłasza do QualEngine, że mieszanina się zmieniła (on_mixture_changed).
func _schedule_recalc() -> void:
	if _has_pellet_ready():
		return
	if _recalc_scheduled:
		return
	_recalc_scheduled = true
	call_deferred("_run_recalc")


## Wywoływane w kolejnej klatce – odpala QualEngine.on_mixture_changed.
func _run_recalc() -> void:
	_recalc_scheduled = false
	if Qualengine and Qualengine.has_method("on_mixture_changed"):
		Qualengine.on_mixture_changed(self)


# =========================================================================
# RESET ZAWARTOŚCI PROBÓWKI
# =========================================================================

## Czyści zawartość probówki (jony, osady, tagi) i resetuje FX wizualne.
func _clear_contents_completely() -> void:
	mixture.clear_all()

	if not (mixture.tags is Dictionary):
		mixture.tags = {}

	(mixture.tags as Dictionary).erase("pH")
	(mixture.tags as Dictionary).erase("ph_samples")
	(mixture.tags as Dictionary).erase("pellet_ready")

	ever_precipitated = false
	turbidity_color = Color.WHITE
	turbidity_target = initial_turbidity
	display_turbidity = initial_turbidity
	_set_turbidity_value(display_turbidity)

	if crystal_fx:
		var crystal_material := crystal_fx.material as ShaderMaterial
		if crystal_material and crystal_material.shader and _shader_has_uniform(crystal_material, "progress"):
			crystal_material.set_shader_parameter("progress", 0.0)
		crystal_fx.visible = false

	if pellet:
		pellet.visible = false
		pellet.modulate = Color(1, 1, 1, 1)


# =========================================================================
# CHŁODZENIE (ŁAŹNIA WODNA)
# =========================================================================

## Aktualizuje stan chłodzenia probówki po wyjęciu z łaźni:
## - restartuje licznik gdy bath_boiling == true,
## - po upływie cooling_time_s ustawia cooled_enough = true i zgłasza recalculację.
func _update_cooling(delta: float) -> void:
	if not (mixture.tags is Dictionary):
		return

	var tags_dict: Dictionary = mixture.tags

	if not bool(tags_dict.get(TAG_COOLING_READY, false)):
		return

	# W trakcie wrzenia licznik chłodzenia stoi w miejscu.
	if bool(tags_dict.get(TAG_BATH_BOILING, false)):
		tags_dict[TAG_COOLING_T] = 0.0
		tags_dict.erase(TAG_COOLED_ENOUGH)
		return

	var current_t: float = 0.0
	var t_val: Variant = tags_dict.get(TAG_COOLING_T, 0.0)
	if t_val is float or t_val is int:
		current_t = float(t_val)

	current_t += max(0.0, delta)
	tags_dict[TAG_COOLING_T] = current_t

	if current_t >= max(0.0, cooling_time_s) and not bool(tags_dict.get(TAG_COOLED_ENOUGH, false)):
		tags_dict[TAG_COOLED_ENOUGH] = true
		_schedule_recalc()


# =========================================================================
# CZYSZCZENIE FX (DLA QUALENGINE)
# =========================================================================

## Czyści FX osadów w probówce:
## - wygasza mętność do initial_turbidity,
## - wygasza crystal_fx,
## - chowa pellet i usuwa pellet_ready,
## - resetuje flagę ever_precipitated.
func clear_precip_fx(fade_sec: float = 0.35) -> void:
	var start_turb: float = display_turbidity
	var target_turb: float = initial_turbidity
	var time: float = max(0.0, fade_sec)

	var turb_tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	turb_tween.tween_method(
		func(value): _set_turbidity_value(value),
		start_turb,
		target_turb,
		time
	)

	# kryształy
	if crystal_fx:
		var crystal_material := crystal_fx.material as ShaderMaterial
		if crystal_material and crystal_material.shader and _shader_has_uniform(crystal_material, "progress"):
			var current_progress: float = 0.0
			var pv: Variant = crystal_material.get_shader_parameter("progress")
			if pv is float:
				current_progress = float(pv)
			create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT) \
				.tween_method(
					func(value): crystal_material.set_shader_parameter("progress", value),
					current_progress,
					0.0,
					time
				)

		var fade_tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		fade_tween.tween_property(crystal_fx, "modulate:a", 0.0, time)
		fade_tween.finished.connect(func () -> void:
			if crystal_fx:
				crystal_fx.visible = false
				var crystal_material2 := crystal_fx.material as ShaderMaterial
				if crystal_material2 and crystal_material2.shader and _shader_has_uniform(crystal_material2, "progress"):
					crystal_material2.set_shader_parameter("progress", 0.0)
				var c := crystal_fx.modulate
				c.a = 1.0
				crystal_fx.modulate = c)

	# pellet
	if pellet:
		pellet.visible = false
		pellet.modulate = Color(1, 1, 1, 1)

	if mixture.tags is Dictionary:
		(mixture.tags as Dictionary).erase("pellet_ready")

	turbidity_target = initial_turbidity
	display_turbidity = initial_turbidity
	ever_precipitated = false


# =========================================================================
# CRYSTAL FX – HELPERY
# =========================================================================

## Pokazuje efekt kryształków w probówce (CrystalFX).
func _show_crystal_fx(color: Color, progress_target: float) -> void:
	if not crystal_fx:
		return

	crystal_fx.visible = true
	crystal_fx.modulate.a = 1.0

	var crystal_material := crystal_fx.material as ShaderMaterial
	if crystal_material and crystal_material.shader:
		if _shader_has_uniform(crystal_material, "crystal_color"):
			crystal_material.set_shader_parameter("crystal_color", color)
		if _shader_has_uniform(crystal_material, "progress"):
			var start_progress: float = 0.0
			var pv: Variant = crystal_material.get_shader_parameter("progress")
			if pv is float:
				start_progress = float(pv)
			create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT) \
				.tween_method(
					func(value): crystal_material.set_shader_parameter("progress", value),
					start_progress,
					clamp(progress_target, 0.0, 1.0),
					0.4
				)


## Ukrywa efekt kryształków i resetuje progress.
func _hide_crystal_fx() -> void:
	if not crystal_fx:
		return
	var crystal_material := crystal_fx.material as ShaderMaterial
	if crystal_material and crystal_material.shader and _shader_has_uniform(crystal_material, "progress"):
		crystal_material.set_shader_parameter("progress", 0.0)
	crystal_fx.visible = false


## Sprawdza, czy efekt CrystalFX jest aktualnie aktywny.
func _crystal_fx_active() -> bool:
	if crystal_fx == null:
		return false
	if not crystal_fx.visible:
		return false
	var crystal_material := crystal_fx.material as ShaderMaterial
	if crystal_material and crystal_material.shader and _shader_has_uniform(crystal_material, "progress"):
		var pv: Variant = crystal_material.get_shader_parameter("progress")
		if pv is float:
			return float(pv) > 0.01
	return crystal_fx.modulate.a > 0.01


## Wymusza wyłączenie efektu CrystalFX.
func _force_crystal_fx_off() -> void:
	if not crystal_fx:
		return
	crystal_fx.visible = false
	var crystal_material := crystal_fx.material as ShaderMaterial
	if crystal_material and crystal_material.shader and _shader_has_uniform(crystal_material, "progress"):
		crystal_material.set_shader_parameter("progress", 0.0)
	var c := crystal_fx.modulate
	c.a = 0.0
	crystal_fx.modulate = c


# =========================================================================
# WIROWANIE / PELLET
# =========================================================================

## Reaguje na zakończenie wirowania:
## - zapamiętuje tryb osadu sprzed wirowania,
## - chowa CrystalFX,
## - ustawia pellet na dnie w kolorze turbidity_color,
## - resetuje mętność.
func on_centrifuge_compact() -> void:
	last_precip_mode = "floc"
	if _crystal_fx_active():
		last_precip_mode = "crystal"
	had_crystal_before_spin = (last_precip_mode == "crystal")

	_hide_crystal_fx()

	var pellet_color := turbidity_color
	show_pellet(true, pellet_color)

	turbidity_target = 0.0
	display_turbidity = 0.0
	_set_turbidity_value(0.0)


## Sprawdza, czy probówka ma pellet (sprite lub tag pellet_ready).
func _has_pellet_ready() -> bool:
	return (pellet != null and pellet.visible) \
		or ((mixture.tags is Dictionary) and bool(mixture.tags.get("pellet_ready", false)))


## Sprawdza, czy probówka zawiera suchy pellet (bez cieczy):
## - przydatne do późniejszego drucika do próby płomieniowej.
func has_dry_pellet() -> bool:
	var pellet_ready := _has_pellet_ready()

	var no_liquid := (fill_level <= 0.001) \
		and (mixture.ions is Dictionary) \
		and mixture.ions.size() == 0

	return pellet_ready and no_liquid


## Pokazuje pellet o zadanym kolorze w probówce i ustawia pellet_ready w tags.
func show_pellet(on: bool, color: Color = Color.WHITE) -> void:
	if pellet == null:
		return
	if not on:
		hide_pellet()
		return

	var alpha: float = clamp(pellet_opacity, 0.0, 1.0)
	var final_color := Color(
		color.r * pellet_brightness,
		color.g * pellet_brightness,
		color.b * pellet_brightness,
		alpha
	)
	pellet.modulate = final_color
	pellet.visible = true

	ever_precipitated = false
	turbidity_target = 0.0
	display_turbidity = 0.0
	_set_turbidity_value(0.0)

	if mixture.tags is Dictionary:
		(mixture.tags as Dictionary)["pellet_ready"] = true


## Chowa pellet i usuwa tag pellet_ready.
func hide_pellet() -> void:
	if pellet:
		pellet.visible = false
		pellet.modulate = Color(1, 1, 1, 1)
	if mixture.tags is Dictionary:
		(mixture.tags as Dictionary).erase("pellet_ready")


# =========================================================================
# MIESZANIE BAGIETKĄ
# =========================================================================

## Miesza zawartość probówki bagietką:
## - dla pelletu: resuspenzuje go na osad floc/crystal, czyści tag centrifuged,
## - dla kryształków: podbija progres CrystalFX,
## - dla zwykłej mętności: lekko zwiększa mętność,
## - na koniec zgłasza recalculację do QualEngine.
func stir_with_rod(strength: float = 0.6) -> void:
	var stir_strength: float = clamp(strength, 0.0, 1.0)

	if not has_any_liquid() and not _has_pellet_ready():
		return

	var was_pellet := _has_pellet_ready()

	if was_pellet:
		hide_pellet()

		if mixture.tags is Dictionary:
			var tags_dict := mixture.tags as Dictionary
			tags_dict.erase("centrifuged")

		if last_precip_mode == "crystal" or had_crystal_before_spin:
			ever_precipitated = false
			turbidity_target = initial_turbidity
			display_turbidity = initial_turbidity
			_set_turbidity_value(display_turbidity)
			var crystal_progress: float = clamp(0.35 + 0.6 * stir_strength, 0.0, 1.0)
			_show_crystal_fx(turbidity_color, crystal_progress)
			last_precip_mode = "crystal"
		else:
			_hide_crystal_fx()
			ever_precipitated = true
			var bump: float = clamp(0.3 + 0.5 * stir_strength, 0.0, 1.0)
			turbidity_target = max(turbidity_target, bump)
			display_turbidity = max(display_turbidity, bump)
			_set_turbidity_value(display_turbidity)
			last_precip_mode = "floc"

		_schedule_recalc()
		return

	if _crystal_fx_active():
		var prog_target: float = clamp(0.4 + 0.4 * stir_strength, 0.0, 1.0)
		_show_crystal_fx(turbidity_color, prog_target)
		return

	if not has_any_liquid():
		return

	if not _has_any_precipitate_or_suspension():
		ever_precipitated = false
		turbidity_target = initial_turbidity
		display_turbidity = initial_turbidity
		_set_turbidity_value(display_turbidity)
		return

	_hide_crystal_fx()
	ever_precipitated = true
	var bump2: float = clamp(0.2 + 0.5 * stir_strength, 0.0, 1.0)
	turbidity_target = max(turbidity_target, bump2)
	display_turbidity = max(display_turbidity, bump2)
	_set_turbidity_value(display_turbidity)

	_schedule_recalc()


## Alias do stir_with_rod – resuspenduje pellet (używane np. z innych miejsc).
func resuspend_pellet(strength: float = 0.6) -> void:
	stir_with_rod(strength)


## Sprawdza, czy w probówce jest jakakolwiek postać osadu (pellet, solids, kryształki).
func _has_any_precipitate_or_suspension() -> bool:
	if _has_pellet_ready():
		return true
	if mixture.solids is Dictionary and mixture.solids.size() > 0:
		return true
	if _crystal_fx_active():
		return true
	return false
