extends Node2D
class_name Centrifuge

## Wirówka laboratoryjna.
## Odpowiada za:
## - przełączanie stanów pracy: CLOSED_IDLE / OPEN_IDLE / SPINNING,
## - przyjmowanie probówek do bębna (do `capacity` sztuk),
## - uruchomienie cyklu wirowania na zadany czas (`spin_time_s`),
## - oznaczenie probówek z osadem tagiem w `Mixture.tags`
##   i wywołanie `on_centrifuge_compact()` po zakończonym spinie,
## - otwieranie/zamykanie pokrywy i wyjmowanie probówek w kolejności LIFO.

@export var capacity: int = 4                      ## Maksymalna liczba probówek w bębnie.
@export var spin_time_s: float = 5.0               ## Czas pojedynczego cyklu wirowania [s].

@export var set_tag_after_spin_key: String = "centrifuged"
@export var set_tag_after_spin_value: bool = true  ## Wartość przypisywana pod kluczem `set_tag_after_spin_key`.

@export var debug_log: bool = false

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
@onready var stored: Node              = $Stored   ## Kontener, w którym trzymamy probówki „ukryte” w bębnie.

enum State { CLOSED_IDLE, OPEN_IDLE, SPINNING }
var state: State = State.CLOSED_IDLE

## Stos probówek w bębnie (LIFO – pobieramy zawsze ostatnio włożoną).
var _stack: Array[Node2D] = []
var _spin_timer: Timer = null

signal spin_started()
signal spin_finished()
signal probe_accepted(probe: Node2D)
signal probe_picked_for_drag(probe: Node2D)
signal probe_returned(probe: Node2D)


func _ready() -> void:
	## Inicjalizacja timera odpowiedzialnego za zakończenie cyklu wirowania.
	_spin_timer = Timer.new()
	_spin_timer.one_shot = true
	add_child(_spin_timer)
	_spin_timer.timeout.connect(_on_spin_done)

	## Po starcie scena powinna być w spójnym stanie wizualnym i interakcyjnym.
	_refresh_visual()
	_update_interactibility()
	_update_led()


# -------------------------------------------------------------------
# DROPZONE – przyjmowanie probówek do bębna
# -------------------------------------------------------------------
func accept_probe(probe: Node, at_global_pos: Vector2) -> bool:
	## Próba odłożenia probówki do bębna.
	## Zwraca true, jeśli wirówka „przyjęła” probówkę do środka (logicznie),
	## ale faktyczny parent jest zawsze $Stored.
	if state != State.OPEN_IDLE:
		return false
	if not (probe is Node2D):
		return false
	if _stack.size() >= capacity:
		return false
	if not _point_hits_area(pickup_area, at_global_pos):
		return false

	var p := probe as Node2D

	# Probówki bez mieszaniny są ignorowane – nie ma sensu ich wirować.
	var mix := p.get("mixture") as Mixture
	if mix == null or mix.is_empty():
		if debug_log:
			print("[CENTRIFUGE] reject empty probe: ", p.name)
		return false

	# Ponowne odłożenie tej samej probówki (już jest w bębnie).
	if _stack.has(p):
		_internalize_probe(p)
		_refresh_visual()
		return true

	_internalize_probe(p)
	_stack.append(p)
	_refresh_visual()
	emit_signal("probe_accepted", p)
	return true


func _internalize_probe(p: Node2D) -> void:
	## Przenosi probówkę do węzła $Stored i wyłącza jej własną interakcję.
	if p.get_parent():
		p.get_parent().remove_child(p)

	stored.add_child(p)
	p.visible = false

	var area := p.get_node_or_null("ProbeArea2D") as Area2D
	if area:
		area.monitoring = false
		area.input_pickable = false


# -------------------------------------------------------------------
# Obsługa pokrywy – otwieranie i zamykanie
# -------------------------------------------------------------------
func _on_lid_closed_area_input(_vp: Viewport, ev: InputEvent, _idx: int) -> void:
	## Klik w grafikę zamkniętej pokrywy – próba otwarcia.
	if not _lab_is_idle():
		return
	if not (ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed):
		return

	if state == State.CLOSED_IDLE:
		state = State.OPEN_IDLE
		_refresh_visual()
		_update_interactibility()


func _on_lid_open_area_input(_vp: Viewport, ev: InputEvent, _idx: int) -> void:
	## Klik w grafikę otwartej pokrywy – zamknięcie i blokada wkładania/pobierania.
	if not _lab_is_idle():
		return
	if not (ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed):
		return

	if state == State.OPEN_IDLE:
		state = State.CLOSED_IDLE
		_refresh_visual()
		_update_interactibility()


# -------------------------------------------------------------------
# Start i zakończenie wirowania
# -------------------------------------------------------------------
func _on_start_button_input(_vp: Viewport, ev: InputEvent, _idx: int) -> void:
	## Start cyklu wirowania po kliknięciu przycisku.
	if not _lab_is_idle():
		return
	if not (ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed):
		return

	_start_spin()


func _start_spin() -> void:
	## Uruchomienie wirówki – możliwe tylko przy zamkniętej pokrywie i niepustym bębnie.
	if state != State.CLOSED_IDLE:
		return
	if _stack.is_empty():
		return

	state = State.SPINNING
	_update_interactibility()
	_update_led()
	emit_signal("spin_started")

	_spin_timer.stop()
	_spin_timer.wait_time = max(0.0, spin_time_s)
	_spin_timer.start()


func _on_spin_done() -> void:
	## Zakończenie cyklu wirowania.
	## Przechodzimy po probówkach i wykonujemy operacje tylko dla tych z osadami.
	var any_with_solids := false

	for p in _stack:
		if p == null:
			continue

		var mix := p.get("mixture") as Mixture
		var has_solids := false

		if mix != null and (mix.solids is Dictionary):
			var solids_dict: Dictionary = mix.solids
			if solids_dict.size() > 0:
				has_solids = true

		# Probówki bez osadu nie są objęte logiką „pelletu”.
		if not has_solids:
			if debug_log:
				print("[CENTRIFUGE] skip pellet for clear probe: ", p.name)
			continue

		any_with_solids = true

		# Tagowanie probówki po spinie (np. do późniejszych reakcji w QE).
		if set_tag_after_spin_key != "":
			_set_probe_tag(p, set_tag_after_spin_key, set_tag_after_spin_value)

		# Callback odpowiadający za aktualizację wyglądu osadu po wirowaniu.
		if p.has_method("on_centrifuge_compact"):
			if debug_log:
				print("[CENTRIFUGE] on_centrifuge_compact -> ", p.name)
			p.on_centrifuge_compact()
		elif debug_log:
			print("[CENTRIFUGE] WARN: missing on_centrifuge_compact on ", (str(p.name) if p else "<null>"))

	if debug_log and not any_with_solids:
		print("[CENTRIFUGE] no solids in any probe – nothing to compact")

	emit_signal("spin_finished")

	state = State.CLOSED_IDLE
	_update_interactibility()
	_update_led()
	_refresh_visual()


# -------------------------------------------------------------------
# Wyjmowanie probówek (LIFO)
# -------------------------------------------------------------------
func _on_pickup_area_input(_vp: Viewport, ev: InputEvent, _idx: int) -> void:
	## Klik w obszar pobierania – wyjęcie probówki z bębna.
	if not _lab_is_idle():
		return
	if not (ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed):
		return
	if state != State.OPEN_IDLE:
		return
	if _stack.is_empty():
		return

	var last_index := _stack.size() - 1
	var p := _stack[last_index]
	_stack.remove_at(last_index)

	# Przywrócenie interakcji probówki z otoczeniem.
	var area := p.get_node_or_null("ProbeArea2D") as Area2D
	if area:
		area.monitoring = true
		area.input_pickable = true

	p.visible = true
	p.global_position = get_global_mouse_position()

	# Lab nasłuchuje „drag_ended”, więc podłączamy callback.
	var cb := Callable(self, "_on_probe_drag_ended")
	if p.has_signal("drag_ended"):
		if p.is_connected("drag_ended", cb):
			p.disconnect("drag_ended", cb)
		p.connect("drag_ended", cb)

	# Możliwe zlecenie logiki dragowania po stronie probówki.
	if p.has_method("_start_drag"):
		p.call_deferred("_start_drag")

	emit_signal("probe_picked_for_drag", p)
	_refresh_visual()


func _on_probe_drag_ended(probe: Node) -> void:
	## Wywoływane po zakończeniu dragowania probówki.
	if not is_instance_valid(probe):
		return
	if not (probe is Node2D):
		return
	var p := probe as Node2D

	# Jeżeli probówka nadal jest dzieckiem $Stored, traktujemy to jako odłożenie do bębna.
	if p.get_parent() == stored:
		if not _stack.has(p) and _stack.size() < capacity:
			var area := p.get_node_or_null("ProbeArea2D") as Area2D
			if area:
				area.monitoring = false
				area.input_pickable = false

			p.visible = false
			_stack.append(p)
			emit_signal("probe_returned", p)

		_refresh_visual()
	else:
		# Probówka trafiła gdzie indziej – odpinamy się od sygnału.
		var cb := Callable(self, "_on_probe_drag_ended")
		if p.is_connected("drag_ended", cb):
			p.disconnect("drag_ended", cb)


# -------------------------------------------------------------------
# Aktualizacja wyglądu i interakcji
# -------------------------------------------------------------------
func _refresh_visual() -> void:
	## Ustawienie grafiki odpowiedniej do stanu i liczby probówek.
	var count := clampi(_stack.size(), 0, capacity)

	# Przełączenie między „zamkniętą” a „otwartą” grafiką.
	if state == State.CLOSED_IDLE or state == State.SPINNING:
		if closed_sprite:
			closed_sprite.visible = true
		if open_container:
			open_container.visible = false
	else:
		if closed_sprite:
			closed_sprite.visible = false
		if open_container:
			open_container.visible = true

	# Warianty Open0..Open4 – reprezentują liczbę probówek w bębnie przy otwartej pokrywie.
	if open_container:
		var variants := [open0, open1, open2, open3, open4]
		for i in variants.size():
			if variants[i]:
				variants[i].visible = (state == State.OPEN_IDLE and i == count)


func _update_interactibility() -> void:
	## Udostępnienie odpowiednich obszarów kliknięć w zależności od stanu wirówki.
	if lid_closed_area:
		lid_closed_area.input_pickable = (state == State.CLOSED_IDLE)
	if lid_open_area:
		lid_open_area.input_pickable   = (state == State.OPEN_IDLE)
	if pickup_area:
		pickup_area.input_pickable     = (state == State.OPEN_IDLE)
	if start_button:
		start_button.input_pickable    = (state == State.CLOSED_IDLE and not _stack.is_empty())


func _update_led() -> void:
	## Prosta sygnalizacja diodą – aktywna tylko podczas wirowania.
	if led_on:
		led_on.visible = (state == State.SPINNING)


# -------------------------------------------------------------------
# Funkcje pomocnicze
# -------------------------------------------------------------------
func _set_probe_tag(p: Node2D, key: String, value: Variant) -> void:
	## Ustawienie wpisu w `Mixture.tags` dla danej probówki.
	if p == null:
		return
	var mix := p.get("mixture") as Mixture
	if mix == null:
		return
	if not (mix.tags is Dictionary):
		mix.tags = {}
	mix.tags[key] = value


func _point_hits_area(area: Area2D, world_pos: Vector2) -> bool:
	## Sprawdza, czy punkt w przestrzeni świata znajduje się w danym Area2D.
	if area == null:
		return false

	var dss := area.get_world_2d().direct_space_state
	var q := PhysicsPointQueryParameters2D.new()
	q.position = world_pos
	q.collide_with_areas = true
	q.collide_with_bodies = false
	q.collision_mask = area.collision_layer

	var hits := dss.intersect_point(q, 16)
	for info in hits:
		if info.has("collider") and info["collider"] == area:
			return true

	return false


func _lab_is_idle() -> bool:
	## Sprawdza, czy nadrzędna scena Lab znajduje się w trybie IDLE
	## (inne tryby mogą blokować interakcje z wirówką).
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
