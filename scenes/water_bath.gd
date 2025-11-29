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

@export var warmup_seconds: float = 10.0  ## Czas nagrzewania łaźni od OFF do BOILING.
@export var boil_delay: float = 5.0       ## Minimalny czas gotowania probówki, aby dostała bath_boiling = true.

@onready var slots_root: Node   = $Slots
@onready var heat_button: Area2D = $HeatButton
@onready var led_hot: Node2D    = $LedOn

enum State { OFF, WARMING, BOILING }

## Aktualny stan łaźni.
var state: State = State.OFF

## Timer do odmierzania nagrzewania łaźni (OFF → BOILING).
var warmup_timer: Timer = null

## Mapa: probe (Node2D) -> czas gotowania [s].
var probe_boil_time: Dictionary = {}

## Mapa: slot (ProbeSlot) -> aktualna probówka (do czyszczenia tagów przy wyjęciu).
var slot_probe_map: Dictionary = {}

const TAG_BOIL_TIME   := "bath_boil_time"
const TAG_BOILING_NOW := "bath_boiling"


# =========================================================================
# INICJALIZACJA
# =========================================================================

## Inicjalizuje łaźnię:
## - podpina sygnały do slotów,
## - tworzy timer nagrzewania,
## - ustawia stan diody LED,
## - resetuje tagi termiczne probówek.
func _ready() -> void:
	for slot: ProbeSlot in _get_slots():
		if not slot.is_connected("occupied_changed", Callable(self, "_on_slot_occupied_changed")):
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
		for slot: ProbeSlot in _get_slots():
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
		for slot: ProbeSlot in _get_slots():
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

## Obsługuje input na przycisku grzania:
## - reaguje na klik LPM tylko gdy Lab jest w trybie IDLE,
## - wywołuje _on_heat_button_clicked().
func _on_heat_button_input_event(_vp: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if not _lab_is_idle():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_on_heat_button_clicked()


## Obsługuje kliknięcie przycisku grzania:
## - OFF → WARMING: startuje timer nagrzewania,
## - WARMING/BOILING → OFF: wyłącza łaźnię, resetuje tagi probówek.
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

			for slot: ProbeSlot in _get_slots():
				var probe := slot.get_current_probe() as Node2D
				if probe:
					probe_boil_time[probe] = 0.0
					_set_probe_heat_tags(probe, false, 0.0)
					_request_recalc(probe)


## Reaguje na zakończenie nagrzewania łaźni:
## - ustawia stan BOILING,
## - resetuje licznik boil_time dla probówek,
## - ustawia tagi termiczne i prosi probówki o przeliczenie reakcji.
func _on_warmup_done() -> void:
	state = State.BOILING
	_update_led()

	for slot: ProbeSlot in _get_slots():
		var probe := slot.get_current_probe() as Node2D
		if probe:
			probe_boil_time[probe] = 0.0
			_set_probe_heat_tags(probe, true, 0.0)
			_request_recalc(probe)


# =========================================================================
# SLOTY I PROBÓWKI
# =========================================================================

## Zwraca listę slotów łaźni (dzieci slots_root będące ProbeSlot).
func _get_slots() -> Array[ProbeSlot]:
	var result: Array[ProbeSlot] = []
	if slots_root == null:
		return result

	for child in slots_root.get_children():
		if child is ProbeSlot:
			result.append(child as ProbeSlot)
	return result


## Reaguje na zmianę zajętości slotu:
## - dla starej probówki czyści tagi i licznik oraz zgłasza recalculację,
## - dla nowej probówki ustawia początkowy stan termiczny i schładza licznik,
## - aktualizuje mapę slot_probe_map.
func _on_slot_occupied_changed(slot: ProbeSlot, probe: Node) -> void:
	var previous_probe := slot_probe_map.get(slot, null) as Node2D

	# Stara probówka – czyści tagi i licznik.
	if previous_probe and (probe == null or previous_probe != probe):
		_clear_probe_heat_tags(previous_probe)
		probe_boil_time.erase(previous_probe)
		_request_recalc(previous_probe)

	# Nowa probówka w slocie.
	if probe and probe is Node2D:
		var probe_2d := probe as Node2D
		slot_probe_map[slot] = probe_2d
		probe_boil_time[probe_2d] = 0.0

		var is_boiling_now := (state == State.BOILING)
		_set_probe_heat_tags(probe_2d, is_boiling_now, 0.0)
		_request_recalc(probe_2d)
	else:
		slot_probe_map.erase(slot)


## Resetuje stan termiczny wszystkich probówek w slotach:
## - zeruje czas gotowania,
## - ustawia tagi w zależności od aktualnego stanu łaźni,
## - zgłasza recalculację.
func _reset_all_probes_heat() -> void:
	var is_boiling_now := (state == State.BOILING)

	for slot: ProbeSlot in _get_slots():
		var probe := slot.get_current_probe() as Node2D
		if probe:
			slot_probe_map[slot] = probe
			probe_boil_time[probe] = 0.0
			_set_probe_heat_tags(probe, is_boiling_now, 0.0)
			_request_recalc(probe)


# =========================================================================
# TAGI TERMICZNE W Mixture.tags
# =========================================================================

## Ustawia tagi termiczne probówki:
## - gdy boiling == true: ustawia bath_boil_time oraz bath_boiling (po boil_delay),
## - gdy boiling == false: czyści tagi termiczne przez _clear_probe_heat_tags.
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


## Czyści tagi termiczne probówki (bath_boil_time, bath_boiling).
func _clear_probe_heat_tags(probe: Node2D) -> void:
	var mixture := probe.get("mixture") as Mixture
	if mixture == null or not (mixture.tags is Dictionary):
		return
	var tags_dict: Dictionary = mixture.tags
	tags_dict.erase(TAG_BOIL_TIME)
	tags_dict.erase(TAG_BOILING_NOW)


## Prosi probówkę o przeliczenie chemii (wywołuje _schedule_recalc deferred).
func _request_recalc(probe: Node2D) -> void:
	if probe.has_method("_schedule_recalc"):
		probe.call_deferred("_schedule_recalc")


# =========================================================================
# LED + SPRAWDZENIE TRYBU LABORATORIUM
# =========================================================================

## Aktualizuje stan diody LED (świeci, gdy łaźnia nie jest w stanie OFF).
func _update_led() -> void:
	if led_hot:
		led_hot.visible = (state != State.OFF)


## Sprawdza, czy główny Lab jest w trybie IDLE:
## - inne tryby mogą blokować interakcję z łaźnią.
func _lab_is_idle() -> bool:
	var lab := get_tree().get_first_node_in_group("lab_root")
	if lab == null:
		return true

	var mode_enum: Variant = lab.get("Mode")
	var cur_mode: Variant  = lab.get("mode")

	if mode_enum is Dictionary and mode_enum.has("IDLE"):
		return cur_mode == mode_enum["IDLE"]

	if cur_mode is int:
		return int(cur_mode) == 0

	return false
