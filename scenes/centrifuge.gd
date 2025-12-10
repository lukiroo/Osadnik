extends Node2D
class_name Centrifuge

## =========================================================================
## centrifuge.gd – wirówka laboratoryjna
## -------------------------------------------------------------------------
## Odpowiada za:
## - przełączanie stanów pracy: CLOSED_IDLE / OPEN_IDLE / SPINNING,
## - przyjmowanie probówek do bębna (do `capacity` sztuk),
## - uruchomienie cyklu wirowania na zadany czas (`spin_time_s`),
## - oznaczenie probówek z osadem tagiem w `Mixture.tags`
##   i wywołanie `on_centrifuge_compact()` po zakończonym wirowaniu,
## - otwieranie/zamykanie pokrywy i wyjmowanie probówek w kolejności LIFO.
## =========================================================================

@export var capacity: int = 4                      ## Maksymalna liczba probówek w bębnie.
@export var spin_time_s: float = 5.0               ## Czas pojedynczego cyklu wirowania [s].

@onready var set_tag_after_spin_key: String = "centrifuged"
@onready var set_tag_after_spin_value: bool = true  ## Wartość przypisywana pod kluczem `set_tag_after_spin_key`.

# Węzły graficzne
@onready var closed_sprite: Sprite2D   = $CentrifugeClosed
@onready var open_container: Node2D    = $CentrifugeOpen
@onready var open0: Sprite2D           = $CentrifugeOpen/Open0
@onready var open1: Sprite2D           = $CentrifugeOpen/Open1
@onready var open2: Sprite2D           = $CentrifugeOpen/Open2
@onready var open3: Sprite2D           = $CentrifugeOpen/Open3
@onready var open4: Sprite2D           = $CentrifugeOpen/Open4

# Obszary interakcji
@onready var lid_closed_area: Area2D   = $LidClosedArea
@onready var lid_open_area: Area2D     = $LidOpenArea
@onready var start_button: Area2D      = $StartButton
@onready var pickup_area: Area2D       = $PickupArea
@onready var led_on: Sprite2D          = $LedOn
@onready var stored: Node              = $Stored   ## Kontener, w którym trzymamy probówki „schowane” w bębnie.

enum State { CLOSED_IDLE, OPEN_IDLE, SPINNING }

## Aktualny stan wirówki (zamknięta/otwarta/spinning).
var state: State = State.CLOSED_IDLE

## Stos probówek w bębnie (LIFO – pobieramy zawsze ostatnio włożoną).
var _probe_stack: Array[Node2D] = []

## Timer odpowiedzialny za zakończenie wirowania.
var _spin_timer: Timer

signal spin_started()
signal spin_finished()
signal probe_accepted(probe: Node2D)
signal probe_picked_for_drag(probe: Node2D)
signal probe_returned(probe: Node2D)


# =========================================================================
# INICJALIZACJA
# =========================================================================

## Inicjalizuje wirówkę:
## - tworzy timer,
## - ustawia początkowy widok, interaktywność i LED.
func _ready() -> void:
	_spin_timer = Timer.new()
	_spin_timer.one_shot = true
	add_child(_spin_timer)
	_spin_timer.timeout.connect(_on_spin_done)

	_refresh_view()
	_update_interactive_areas()
	_update_led()


# =========================================================================
# DROPZONE – PRZYJMOWANIE PROBÓWEK DO BĘBNA
# =========================================================================

## Próbuje przyjąć probówkę do bębna:
## - sprawdza stan wirówki, typ węzła, pojemność i trafienie w pickup_area,
## - odrzuca probówki bez mieszaniny,
## - przenosi probówkę do węzła $Stored i wyłącza jej interakcję,
## - stos LIFO.
func accept_probe(probe: Node, at_global_pos: Vector2) -> bool:
	if state != State.OPEN_IDLE:
		return false
	if not (probe is Node2D):
		return false
	if _probe_stack.size() >= capacity:
		return false
	if not _point_hits_area(pickup_area, at_global_pos):
		return false

	var probe_2d: Node2D = probe as Node2D
	var mixture: Mixture = probe_2d.get("mixture") as Mixture
	if mixture == null or mixture.is_empty():
		return false

	# Ponowne odłożenie tej samej probówki (już jest w bębnie).
	if _probe_stack.has(probe_2d):
		_store_probe_inside(probe_2d)
		_refresh_view()
		return true

	_store_probe_inside(probe_2d)
	_probe_stack.append(probe_2d)
	_refresh_view()
	emit_signal("probe_accepted", probe_2d)
	return true


## Przenosi probówkę do węzła $Stored i wyłącza jej własną interakcję.
func _store_probe_inside(probe_2d: Node2D) -> void:
	var parent := probe_2d.get_parent()
	if parent:
		parent.remove_child(probe_2d)

	stored.add_child(probe_2d)
	probe_2d.visible = false

	var probe_area: Area2D = probe_2d.get_node_or_null("ProbeArea2D") as Area2D
	if probe_area:
		probe_area.monitoring = false
		probe_area.input_pickable = false


# =========================================================================
# OBSŁUGA POKRYWY – OTWIERANIE I ZAMYKANIE
# =========================================================================

## Obsługuje kliknięcie w zamkniętą pokrywę:
## - jeżeli Lab jest w trybie IDLE i stan to CLOSED_IDLE,
##   przełącza wirówkę w tryb OPEN_IDLE.
func _on_lid_closed_area_input(_vp: Viewport, event: InputEvent, _idx: int) -> void:
	if not _lab_is_idle():
		return
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and state == State.CLOSED_IDLE:
		state = State.OPEN_IDLE
		_refresh_view()
		_update_interactive_areas()


## Obsługuje kliknięcie w otwartą pokrywę:
## - jeżeli Lab jest w trybie IDLE i stan to OPEN_IDLE,
##   zamyka pokrywę i przełącza stan na CLOSED_IDLE.
func _on_lid_open_area_input(_vp: Viewport, event: InputEvent, _idx: int) -> void:
	if not _lab_is_idle():
		return
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and state == State.OPEN_IDLE:
		state = State.CLOSED_IDLE
		_refresh_view()
		_update_interactive_areas()


# =========================================================================
# START I ZAKOŃCZENIE WIROWANIA
# =========================================================================

## Obsługuje kliknięcie w przycisk startu:
## - sprawdza tryb Lab,
## - wywołuje wewnętrzne _start_spin().
func _on_start_button_input(_vp: Viewport, event: InputEvent, _idx: int) -> void:
	if not _lab_is_idle():
		return
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		_start_spin()


## Uruchamia wirówkę:
## - wymaga stanu CLOSED_IDLE oraz niepustego stosu probówek,
## - ustawia stan SPINNING,
## - odpala timer cyklu wirowania,
## - emituje sygnał spin_started.
func _start_spin() -> void:
	if state != State.CLOSED_IDLE:
		return
	if _probe_stack.is_empty():
		return

	state = State.SPINNING
	_update_interactive_areas()
	_update_led()
	emit_signal("spin_started")

	_spin_timer.stop()
	_spin_timer.wait_time = max(0.0, spin_time_s)
	_spin_timer.start()


## Kończy cykl wirowania:
## - dla każdej probówki z osadami ustawia tag (set_tag_after_spin_key),
## - wywołuje on_centrifuge_compact() na probówce, jeśli istnieje,
## - emituje sygnał spin_finished i wraca do stanu CLOSED_IDLE.
func _on_spin_done() -> void:
	for probe_2d in _probe_stack:
		if probe_2d == null:
			continue

		var mixture: Mixture = probe_2d.get("mixture") as Mixture
		var has_solids := mixture \
			and (mixture.solids is Dictionary) \
			and (mixture.solids as Dictionary).size() > 0

		if not has_solids:
			continue

		if set_tag_after_spin_key != "":
			_set_probe_tag(probe_2d, set_tag_after_spin_key, set_tag_after_spin_value)

		if probe_2d.has_method("on_centrifuge_compact"):
			probe_2d.on_centrifuge_compact()

	emit_signal("spin_finished")

	state = State.CLOSED_IDLE
	_update_interactive_areas()
	_update_led()
	_refresh_view()


# =========================================================================
# WYJMOWANIE PROBÓWEK (LIFO)
# =========================================================================

## Obsługuje kliknięcie w obszar pickup:
## - wyjmuje ostatnią probówkę ze stosu,
## - przywraca jej interakcję z otoczeniem,
## - ustawia ją pod kursorem i rozpoczyna drag,
## - emituje sygnał probe_picked_for_drag.
func _on_pickup_area_input(_vp: Viewport, event: InputEvent, _idx: int) -> void:
	if not _lab_is_idle():
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if state != State.OPEN_IDLE:
		return
	if _probe_stack.is_empty():
		return

	var last_index: int = _probe_stack.size() - 1
	var probe_2d: Node2D = _probe_stack[last_index]
	_probe_stack.remove_at(last_index)

	var probe_area: Area2D = probe_2d.get_node_or_null("ProbeArea2D") as Area2D
	if probe_area:
		probe_area.monitoring = true
		probe_area.input_pickable = true

	probe_2d.visible = true
	probe_2d.global_position = get_global_mouse_position()

	var cb := Callable(self, "_on_probe_drag_ended")
	if probe_2d.has_signal("drag_ended"):
		if probe_2d.is_connected("drag_ended", cb):
			probe_2d.disconnect("drag_ended", cb)
		probe_2d.connect("drag_ended", cb)

	if probe_2d.has_method("_start_drag"):
		probe_2d.call_deferred("_start_drag")

	emit_signal("probe_picked_for_drag", probe_2d)
	_refresh_view()


## Reaguje na zakończenie dragowania probówki:
## - jeśli probówka nadal jest dzieckiem $Stored, traktuje to jako odłożenie do bębna,
## - w przeciwnym razie odpina się od sygnału drag_ended.
func _on_probe_drag_ended(probe: Node) -> void:
	if not (probe is Node2D):
		return

	var probe_2d: Node2D = probe as Node2D

	if probe_2d.get_parent() == stored:
		if not _probe_stack.has(probe_2d) and _probe_stack.size() < capacity:
			var probe_area: Area2D = probe_2d.get_node_or_null("ProbeArea2D") as Area2D
			if probe_area:
				probe_area.monitoring = false
				probe_area.input_pickable = false

			probe_2d.visible = false
			_probe_stack.append(probe_2d)
			emit_signal("probe_returned", probe_2d)

		_refresh_view()
	else:
		var cb := Callable(self, "_on_probe_drag_ended")
		if probe_2d.is_connected("drag_ended", cb):
			probe_2d.disconnect("drag_ended", cb)


# =========================================================================
# AKTUALIZACJA WYGLĄDU I INTERAKCJI
# =========================================================================

## Aktualizuje widok wirówki:
## - przełącza między grafiką zamkniętą i otwartą,
## - pokazuje sprite Open0..Open4 w zależności od stanu i liczby probówek.
func _refresh_view() -> void:
	var count: int = clampi(_probe_stack.size(), 0, capacity)

	if state == State.CLOSED_IDLE or state == State.SPINNING:
		closed_sprite.visible = true
		open_container.visible = false
	else:
		closed_sprite.visible = false
		open_container.visible = true

	var variants: Array[Sprite2D] = [open0, open1, open2, open3, open4]
	for i in variants.size():
		var sprite: Sprite2D = variants[i]
		if sprite:
			sprite.visible = (state == State.OPEN_IDLE and i == count)


## Aktualizuje interaktywność obszarów (pokrywa, start, pickup) w zależności od stanu.
func _update_interactive_areas() -> void:
	lid_closed_area.input_pickable = (state == State.CLOSED_IDLE)
	lid_open_area.input_pickable = (state == State.OPEN_IDLE)
	pickup_area.input_pickable = (state == State.OPEN_IDLE)
	start_button.input_pickable = (state == State.CLOSED_IDLE and not _probe_stack.is_empty())


## Aktualizuje diodę LED – świeci tylko podczas wirowania.
func _update_led() -> void:
	led_on.visible = (state == State.SPINNING)


# =========================================================================
# FUNKCJE POMOCnicze
# =========================================================================

## Ustawia w `Mixture.tags` daną parę (key,value) dla probówki.
func _set_probe_tag(probe_2d: Node2D, key: String, value: Variant) -> void:
	var mixture: Mixture = probe_2d.get("mixture") as Mixture
	if mixture == null:
		return
	if not (mixture.tags is Dictionary):
		mixture.tags = {}
	(mixture.tags as Dictionary)[key] = value


## Sprawdza, czy podany punkt trafia w dany Area2D (używane do pickup_area).
func _point_hits_area(area: Area2D, world_pos: Vector2) -> bool:
	if area == null:
		return false

	var space_state := area.get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.position = world_pos
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = area.collision_layer

	var hits := space_state.intersect_point(query, 16)
	for info in hits:
		if info.get("collider") == area:
			return true

	return false


## Sprawdza, czy nadrzędna scena Lab jest w trybie IDLE:
## - inne tryby mogą blokować interakcje z wirówką.
func _lab_is_idle() -> bool:
	var lab := get_tree().get_first_node_in_group("lab_root")
	if lab == null:
		return true
	return lab.mode == lab.Mode.IDLE
