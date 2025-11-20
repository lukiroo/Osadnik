extends Node2D
class_name WaterBath

## Łaźnia wodna o trzech stanach pracy:
## OFF → WARMING → BOILING.
## W stanie BOILING każda probówka otrzymuje indywidualny czas ogrzewania (`TAG_BOIL_TIME`).
## Po przekroczeniu `boil_delay` probówka uznawana jest za „rozgrzaną” (TAG_BOILING_NOW = true).
## Informacje te trafiają do `Mixture.tags` i mogą być wykorzystywane w reakcjach QualEngine.

@export var warmup_seconds: float = 10.0       ## Czas przejścia z WARMING do BOILING.
@export var boil_delay: float = 5.0            ## Minimalny czas ogrzewania probówki, aby uzyskała status „bath_boiling”.

@onready var slots_container: Node  = $Slots
@onready var heat_button: Area2D   = $HeatButton
@onready var led_hot: Node2D       = $LedOn

enum State { OFF, WARMING, BOILING }
var state: State = State.OFF

var _warmup_timer: Timer = null

## Aktualny czas ogrzewania probówek w stanie BOILING (liczony per instancja probówki).
var _boil_time_s: Dictionary = {}   ## { probe: float_seconds }

## Mapowanie slot → probówka, ułatwia zarządzanie tagami przy wkładaniu/wyjmowaniu.
var _slot_probe: Dictionary = {}    ## { ProbeSlot: Probe }

## Nazwy tagów stosowane w `Mixture.tags` (zgodne z oczekiwaniami QualEngine).
const TAG_BOIL_TIME   := "bath_boil_time"
const TAG_BOILING_NOW := "bath_boiling"


func _ready() -> void:
	## Inicjalizacja: podłączamy się do slotów i konfigurujemy timer nagrzewania.
	for slot: ProbeSlot in _get_slots_list():
		if not slot.is_connected("occupied_changed", Callable(self, "_on_slot_occupied_changed")):
			slot.occupied_changed.connect(_on_slot_occupied_changed)

		var p := slot.get_current_probe() as Node2D
		if p:
			_slot_probe[slot] = p

	_warmup_timer = Timer.new()
	_warmup_timer.one_shot = true
	add_child(_warmup_timer)
	_warmup_timer.timeout.connect(_on_warmup_done)

	_update_led()
	_reset_probe_heat()


func _physics_process(delta: float) -> void:
	## W stanie BOILING aktualizujemy licznik czasu ogrzewania dla każdej probówki.
	if state == State.BOILING:
		for slot: ProbeSlot in _get_slots_list():
			var probe := slot.get_current_probe() as Node2D
			if probe == null:
				continue

			var previous_t := float(_boil_time_s.get(probe, 0.0))
			var new_t := previous_t + delta
			_boil_time_s[probe] = new_t

			# Aktualizacja tagów (czas + ewentualne osiągnięcie progu nagrzania).
			_set_probe_heat_tags(probe, true, new_t)

			# Przy przekroczeniu pełnej sekundy można zlecić przeliczenie reakcji.
			if int(previous_t) != int(new_t):
				_request_recompute(probe)

	else:
		## W stanach OFF i WARMING tagi termiczne są resetowane.
		for slot: ProbeSlot in _get_slots_list():
			var probe := slot.get_current_probe() as Node2D
			if probe == null:
				continue

			if float(_boil_time_s.get(probe, 0.0)) > 0.0:
				_boil_time_s[probe] = 0.0
				_set_probe_heat_tags(probe, false, 0.0)
				_request_recompute(probe)


# -------------------------------------------------------------------
# Sterowanie łaźnią – przycisk grzania
# -------------------------------------------------------------------
func _on_heat_button_input_event(_vp: Viewport, event: InputEvent, _shape_idx: int) -> void:
	## Reakacja na klik w przycisk grzania – tylko gdy Lab jest w trybie IDLE.
	if not _lab_is_idle():
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_on_heat_button_clicked()


func _on_heat_button_clicked() -> void:
	match state:
		State.OFF:
			## Start nagrzewania (OFF → WARMING).
			state = State.WARMING
			_update_led()

			_warmup_timer.stop()
			_warmup_timer.wait_time = max(0.0, warmup_seconds)
			_warmup_timer.start()

			_reset_probe_heat()

		_:
			## Wyłączenie łaźni z dowolnego innego stanu.
			state = State.OFF
			_update_led()
			_warmup_timer.stop()

			for slot: ProbeSlot in _get_slots_list():
				var probe := slot.get_current_probe() as Node2D
				if probe:
					_boil_time_s[probe] = 0.0
					_set_probe_heat_tags(probe, false, 0.0)
					_request_recompute(probe)


func _on_warmup_done() -> void:
	## Łaźnia osiągnęła wrzenie – przejście do stanu BOILING.
	state = State.BOILING
	_update_led()

	for slot: ProbeSlot in _get_slots_list():
		var probe := slot.get_current_probe() as Node2D
		if probe:
			_boil_time_s[probe] = 0.0
			_set_probe_heat_tags(probe, true, 0.0)
			_request_recompute(probe)


# -------------------------------------------------------------------
# Sloty i probówki
# -------------------------------------------------------------------
func _get_slots_list() -> Array[ProbeSlot]:
	var result: Array[ProbeSlot] = []
	if slots_container == null:
		return result

	for child in slots_container.get_children():
		if child is ProbeSlot:
			result.append(child as ProbeSlot)

	return result


func _on_slot_occupied_changed(slot: ProbeSlot, probe: Node) -> void:
	## Obsługa zmiany zawartości slotu – czyszczenie starych tagów i inicjalizacja nowych.
	var previous := _slot_probe.get(slot, null) as Node2D

	# Probówka, która stała w slocie wcześniej, ale została usunięta lub podmieniona.
	if previous and (probe == null or previous != probe):
		_clear_probe_heat_tags(previous)
		_boil_time_s.erase(previous)
		_request_recompute(previous)

	# Nowa probówka w slocie.
	if probe and probe is Node2D:
		var p := probe as Node2D
		_slot_probe[slot] = p
		_boil_time_s[p] = 0.0

		var boiling_now := (state == State.BOILING)
		_set_probe_heat_tags(p, boiling_now, 0.0)
		_request_recompute(p)
	else:
		_slot_probe.erase(slot)


func _reset_probe_heat() -> void:
	## Resetuje stan „termiczny” wszystkich probówek przy zmianie trybu łaźni.
	var boiling_now := (state == State.BOILING)

	for slot: ProbeSlot in _get_slots_list():
		var probe := slot.get_current_probe() as Node2D
		if probe:
			_slot_probe[slot] = probe
			_boil_time_s[probe] = 0.0
			_set_probe_heat_tags(probe, boiling_now, 0.0)
			_request_recompute(probe)


# -------------------------------------------------------------------
# Tagowanie stanu ogrzewania probówek
# -------------------------------------------------------------------
func _set_probe_heat_tags(probe: Node2D, boiling: bool, boil_time_s: float) -> void:
	var mix := probe.get("mixture") as Mixture
	if mix == null:
		return

	if not (mix.tags is Dictionary):
		mix.tags = {}
	var tags: Dictionary = mix.tags

	if boiling:
		# Aktualizacja łącznego czasu ogrzewania (w sekundach).
		tags[TAG_BOIL_TIME] = boil_time_s

		# Probówka uzyskuje status „bath_boiling” dopiero po przekroczeniu progu opóźnienia.
		if boil_time_s >= boil_delay:
			tags[TAG_BOILING_NOW] = true
		else:
			tags.erase(TAG_BOILING_NOW)
	else:
		# Przy wyjściu ze stanu BOILING tagi termiczne są usuwane.
		_clear_probe_heat_tags(probe)


func _clear_probe_heat_tags(probe: Node2D) -> void:
	var mix := probe.get("mixture") as Mixture
	if mix == null or not (mix.tags is Dictionary):
		return

	var tags: Dictionary = mix.tags
	tags.erase(TAG_BOIL_TIME)
	tags.erase(TAG_BOILING_NOW)


func _request_recompute(probe: Node2D) -> void:
	## Delikatne zlecenie przeliczenia chemii – probówka sama wywoła QualEngine.
	if probe.has_method("_schedule_recalc"):
		probe.call_deferred("_schedule_recalc")


# -------------------------------------------------------------------
# LED + kontrola trybu pracy laboratorium
# -------------------------------------------------------------------
func _update_led() -> void:
	## Dioda świeci zawsze, gdy łaźnia nie jest w stanie OFF.
	if led_hot:
		led_hot.visible = (state != State.OFF)


func _lab_is_idle() -> bool:
	## Sprawdza, czy Lab jest w trybie IDLE – inne tryby mogą blokować przełączanie łaźni.
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
