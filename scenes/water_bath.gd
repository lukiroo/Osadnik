extends Node2D
class_name WaterBath

## =========================================================================
## water_bath.gd – łaźnia wodna
## -------------------------------------------------------------------------
## Odpowiada za:
## - przełączanie stanów pracy: OFF → WARMING → BOILING,
## - podgrzewanie probówek w slotach (przypiętych do $Slots),
## - naliczanie czasu gotowania „bath_boil_time” osobno dla każdej probówki,
## - ustawianie taga „bath_boiling” po przekroczeniu progu boil_delay,
## - czyszczenie tagów termicznych po wyłączeniu łaźni lub wyjęciu probówki.
## =========================================================================

@export var warmup_seconds: float = 10.0
@export var boil_delay: float = 10.0

@onready var slots_root: Node    = $Slots
@onready var heat_button: Area2D = $HeatButton
@onready var led_hot: Node2D     = $LedOn
@onready var water_sprite: Sprite2D = $HeaterSprite2D/WaterSprite2D

enum State { OFF, WARMING, BOILING }

var state: State = State.OFF

var warmup_timer: Timer = null

## Mapa: probe -> czas gotowania [s].
var probe_boil_time: Dictionary = {}

## Mapa: slot -> aktualna probówka.
var slot_probe_map: Dictionary = {}

const TAG_BOIL_TIME   := "bath_boil_time"
const TAG_BOILING_NOW := "bath_boiling"


# =========================================================================
# INICJALIZACJA
# =========================================================================

func _ready() -> void:
	for slot in _get_slots():
		slot.occupied_changed.connect(_on_slot_occupied_changed)

		var probe := slot.get_current_probe() as Node2D
		if probe:
			slot_probe_map[slot] = probe

	warmup_timer = Timer.new()
	warmup_timer.one_shot = true
	add_child(warmup_timer)
	warmup_timer.timeout.connect(_on_warmup_done)

	_update_led()
	_reset_all_probes_heat()


## Aktualizuje stan łaźni w każdej klatce:
## - w stanie BOILING zwiększa czas gotowania dla probówek i aktualizuje tagi,
## - w stanach OFF/WARMING resetuje czas i tagi termiczne probówek.
func _physics_process(delta: float) -> void:
	if state == State.BOILING:
		for slot in _get_slots():
			var probe := slot.get_current_probe() as Node2D
			if probe == null:
				continue

			var previous_time: float = float(probe_boil_time.get(probe, 0.0))
			var new_time: float = previous_time + delta
			probe_boil_time[probe] = new_time

			_set_probe_heat_tags(probe, true, new_time)

			# Raz na pełną sekundę prosimy probówkę o przeliczenie chemii.
			if int(previous_time) != int(new_time):
				_request_recalc(probe)
	else:
		# OFF / WARMING – licznik i tagi wracają do zera.
		for slot in _get_slots():
			var probe := slot.get_current_probe() as Node2D
			if probe == null:
				continue

			if float(probe_boil_time.get(probe, 0.0)) > 0.0:
				probe_boil_time[probe] = 0.0
				_set_probe_heat_tags(probe, false, 0.0)
				_request_recalc(probe)


# =========================================================================
# PRZYCISK GRZANIA
# =========================================================================

func _on_heat_button_input_event(_vp: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if not _lab_is_idle():
		return
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		_on_heat_button_clicked()


func _on_heat_button_clicked() -> void:
	match state:
		State.OFF:
			state = State.WARMING
			_update_led()

			warmup_timer.stop()
			warmup_timer.wait_time = max(0.0, warmup_seconds)
			warmup_timer.start()

			_reset_all_probes_heat()

		_:
			state = State.OFF
			_update_led()
			warmup_timer.stop()

			for slot in _get_slots():
				var probe := slot.get_current_probe() as Node2D
				if probe:
					probe_boil_time[probe] = 0.0
					_set_probe_heat_tags(probe, false, 0.0)
					_request_recalc(probe)


func _on_warmup_done() -> void:
	state = State.BOILING
	_update_led()

	for slot in _get_slots():
		var probe := slot.get_current_probe() as Node2D
		if probe:
			probe_boil_time[probe] = 0.0
			_set_probe_heat_tags(probe, true, 0.0)
			_request_recalc(probe)



func _update_bubble_shader() -> void:
	if water_sprite and water_sprite.material is ShaderMaterial:
		var mat := water_sprite.material as ShaderMaterial
		mat.set_shader_parameter("boiling", state == State.BOILING)




# =========================================================================
# SLOTY I PROBÓWKI
# =========================================================================

func _get_slots() -> Array[ProbeSlot]:
	var result: Array[ProbeSlot] = []
	if slots_root == null:
		return result

	for child in slots_root.get_children():
		if child is ProbeSlot:
			result.append(child as ProbeSlot)
	return result


func _on_slot_occupied_changed(slot: ProbeSlot, probe: Node) -> void:
	var previous_probe := slot_probe_map.get(slot, null) as Node2D

	# Stara probówka – czyści tagi i licznik.
	if previous_probe and probe != previous_probe:
		_clear_probe_heat_tags(previous_probe)
		probe_boil_time.erase(previous_probe)
		_request_recalc(previous_probe)

	# Nowa probówka w slocie.
	var probe_2d := probe as Node2D
	if probe_2d:
		slot_probe_map[slot] = probe_2d
		probe_boil_time[probe_2d] = 0.0

		var is_boiling_now := (state == State.BOILING)
		_set_probe_heat_tags(probe_2d, is_boiling_now, 0.0)
		_request_recalc(probe_2d)
	else:
		slot_probe_map.erase(slot)


func _reset_all_probes_heat() -> void:
	var is_boiling_now := (state == State.BOILING)

	for slot in _get_slots():
		var probe := slot.get_current_probe() as Node2D
		if probe:
			slot_probe_map[slot] = probe
			probe_boil_time[probe] = 0.0
			_set_probe_heat_tags(probe, is_boiling_now, 0.0)
			_request_recalc(probe)


# =========================================================================
# TAGI TERMICZNE W Mixture.tags
# =========================================================================

func _set_probe_heat_tags(probe: Node2D, boiling: bool, boil_time: float) -> void:
	var mixture := probe.get("mixture") as Mixture
	if mixture == null:
		return
	if not (mixture.tags is Dictionary):
		mixture.tags = {}
	var tags_dict: Dictionary = mixture.tags

	if boiling:
		tags_dict[TAG_BOIL_TIME] = boil_time
		if boil_time >= boil_delay:
			tags_dict[TAG_BOILING_NOW] = true
		else:
			tags_dict.erase(TAG_BOILING_NOW)
	else:
		_clear_probe_heat_tags(probe)


func _clear_probe_heat_tags(probe: Node2D) -> void:
	var mixture := probe.get("mixture") as Mixture
	if mixture == null or not (mixture.tags is Dictionary):
		return
	var tags_dict: Dictionary = mixture.tags
	tags_dict.erase(TAG_BOIL_TIME)
	tags_dict.erase(TAG_BOILING_NOW)


func _request_recalc(probe: Node2D) -> void:
	if probe.has_method("_schedule_recalc"):
		probe.call_deferred("_schedule_recalc")


# =========================================================================
# LED + SPRAWDZENIE TRYBU LABORATORIUM
# =========================================================================

func _update_led() -> void:
	if led_hot:
		led_hot.visible = (state != State.OFF)
	_update_bubble_shader()



func _lab_is_idle() -> bool:
	var lab := get_tree().get_first_node_in_group("lab_root")
	if lab == null:
		return true

	return lab.mode == lab.Mode.IDLE
