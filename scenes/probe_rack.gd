extends Node2D
class_name ProbeRack

## Stojak na probówki.
## Główne właściwości
## - LMB: półka → stół (rack startowo na półce, przenosimy na blat),
## - RMB: stół → stół lub półka,
## - zna trzy „miejsca dokowania” typu RackPlace (półka + dwa miejsca na stole),
## - gdy stoi na półce, może wyłączyć interakcje slotów i probówek.

# -------------------- USTAWIENIA --------------------
@export var start_on_shelf: bool = false
@export var shelf_scale: float = 0.8
@export var table_scale: float = 1.0
@export var tween_time: float = 0.22
@export var accept_radius: float = 100.0                     ## Promień „trafienia” RackPlace.
@export var disable_probe_interactions_on_shelf: bool = true ## sloty/probówki wyłączone na półce.

@export var shelf_place_path: NodePath
@export var table_place1_path: NodePath
@export var table_place2_path: NodePath

@onready var _handle: Area2D = $HandleArea2D


# -------------------- STAN WEWNĘTRZNY --------------------
var _current_place: RackPlace = null

var _is_dragging: bool = false
var _drag_button: int = 0
var _drag_offset: Vector2 = Vector2.ZERO
var _drag_start_pos: Vector2 = Vector2.ZERO
var _drag_start_place: RackPlace = null

var _z_before_drag: int = 0

@onready var _shelf_place: RackPlace  = get_node_or_null(shelf_place_path) as RackPlace
@onready var _table_place1: RackPlace = get_node_or_null(table_place1_path) as RackPlace
@onready var _table_place2: RackPlace = get_node_or_null(table_place2_path) as RackPlace


# =================================================================
# INIT I STAN STARTOWY
# =================================================================

func _ready() -> void:
	if _handle:
		_handle.input_pickable = true


	## Ustalenie miejsca startowego: półka lub najbliższy wolny stół.
	var start_place: RackPlace = null

	if start_on_shelf:
		if _shelf_place and _shelf_place.is_free():
			start_place = _shelf_place
	else:
		start_place = _pick_free_table_place()

	if start_place == null:
		var side := "shelf" if start_on_shelf else "table"
		push_warning("Brak wolnego miejsca startowego dla stojaka (%s)." % side)
		_apply_place_mode(side)
	else:
		_claim_and_snap(start_place, true)

	## Po jednej klatce sloty są już gotowe – jeszcze raz dopasowujemy tryb.
	call_deferred("_reapply_place_mode_after_ready")


func _reapply_place_mode_after_ready() -> void:
	var place_type := (_current_place.place_type if _current_place != null else ("shelf" if start_on_shelf else "table"))
	_apply_place_mode(place_type)


func _process(_dt: float) -> void:
	## Gdy przeciągamy stojak, jego pozycja nadąża za kursorem.
	if _is_dragging:
		global_position = get_global_mouse_position() + _drag_offset


# =================================================================
# GLOBAL INPUT – puszczenie przycisku poza uchwytem
# =================================================================
func _unhandled_input(event: InputEvent) -> void:
	if not _is_dragging:
		return

	if event is InputEventMouseButton and not event.pressed and event.button_index == _drag_button:
		_end_drag()
		get_viewport().set_input_as_handled()


# =================================================================
# INPUT NA UCHWYCIE
# =================================================================
func _on_handle_input_event(_vp, event: InputEvent, _shape_idx: int) -> void:
	if not _can_drag_now():
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			## LMB: tylko z półki na stół.
			if _is_on_shelf():
				_begin_drag(MOUSE_BUTTON_LEFT)
				get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			## RMB: tylko ze stołu (stół → stół / półka).
			if _is_on_table():
				_begin_drag(MOUSE_BUTTON_RIGHT)
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and not event.pressed:
		if _is_dragging and event.button_index == _drag_button:
			_end_drag()
			get_viewport().set_input_as_handled()


# =================================================================
# ROZPOCZĘCIE I ZAKOŃCZENIE DRAGOWANIA
# =================================================================
func _begin_drag(button: int) -> void:
	_is_dragging = true
	_drag_button = button
	_drag_offset = global_position - get_global_mouse_position()
	_drag_start_pos = global_position
	_drag_start_place = _current_place

	_z_before_drag = z_index
	z_index = 99   ## Na czas dragowania stojak idzie „na wierzch”.

	## Na czas przeciągania zwalniamy miejsce.
	if _current_place:
		_current_place.release(self)
		_current_place = null

	_update_place_hints(true)


func _end_drag() -> void:
	_update_place_hints(false)
	_is_dragging = false
	z_index = _z_before_drag

	var target_place: RackPlace = null

	if _drag_button == MOUSE_BUTTON_LEFT:
		## Półka → stół – szukamy najbliższego wolnego stołu.
		target_place = _pick_nearest_free_table_place(global_position, accept_radius)
	else:
		## RMB: stół → stół / półka.
		target_place = _pick_nearest_free_table_place(global_position, accept_radius)
		if target_place == null and _shelf_place and _shelf_place.is_free():
			if _shelf_place.global_position.distance_to(global_position) <= accept_radius:
				target_place = _shelf_place

	## Jeśli nie znaleźliśmy sensownego miejsca – próbujemy wrócić na start.
	if target_place == null:
		if _drag_start_place and _drag_start_place.claim(self):
			_current_place = _drag_start_place
			_snap_to(_drag_start_place.global_position, false)
			_apply_place_mode(_drag_start_place.place_type)
			_notify_lab_refresh_probes()
		else:
			## Jeszcze jeden fallback: wracamy w poprzednie miejsce bez claimu.
			create_tween().tween_property(self, "global_position", _drag_start_pos, tween_time)
		return

	_claim_and_snap(target_place, false)


# =================================================================
# CLAIM + SNAP + TRYB PRACY
# =================================================================
func _claim_and_snap(place: RackPlace, instant: bool) -> void:
	if not place or not place.claim(self):
		return

	_current_place = place
	_snap_to(place.global_position, instant)
	_apply_place_mode(place.place_type)
	_notify_lab_refresh_probes()


func _snap_to(pos: Vector2, instant: bool) -> void:
	if instant:
		global_position = pos
	else:
		create_tween().tween_property(self, "global_position", pos, tween_time)


func _apply_place_mode(place_type: String) -> void:
	## Skalowanie stojaka w zależności od miejsca (półka vs stół)
	var target_scale := table_scale if place_type == "table" else shelf_scale
	create_tween().tween_property(self, "scale", Vector2(target_scale, target_scale), tween_time)

	## Przy stojaku na półce można globalnie wyłączyć interakcje slotów i probówek.
	var allow_probes := (place_type == "table")
	if disable_probe_interactions_on_shelf:
		for slot in _get_my_slots():
			if slot.has_method("set_enabled"):
				slot.call("set_enabled", allow_probes)

			if slot.has_method("get_current_probe"):
				var p := slot.call("get_current_probe") as Node2D
				if p:
					_set_probe_interactions(p, allow_probes)


# =================================================================
# WYBÓR MIEJSCA (RACKPLACE)
# =================================================================
func _is_on_shelf() -> bool:
	return _is_place_type(_current_place, "shelf")


func _is_on_table() -> bool:
	return _is_place_type(_current_place, "table")


func _is_place_type(place: RackPlace, t: String) -> bool:
	return place != null and place.place_type == t


func _pick_free_table_place() -> RackPlace:
	## Zwraca dowolne wolne miejsce na stole (najbliższe aktualnej pozycji).
	var candidates: Array = []

	if _table_place1 and _table_place1.is_free():
		candidates.append(_table_place1)
	if _table_place2 and _table_place2.is_free():
		candidates.append(_table_place2)

	if candidates.is_empty():
		return null

	candidates.sort_custom(
		func(a, b) -> bool:
			return a.global_position.distance_to(global_position) < b.global_position.distance_to(global_position)
	)

	return candidates[0]


func _pick_nearest_free_table_place(from_pos: Vector2, radius: float) -> RackPlace:
	## Wybór najbliższego wolnego stołu w zadanym promieniu.
	var best: RackPlace = null
	var best_dist: float = INF

	var candidates: Array = []
	if _table_place1 and _table_place1.is_free():
		candidates.append(_table_place1)
	if _table_place2 and _table_place2.is_free():
		candidates.append(_table_place2)

	for place in candidates:
		var rp := place as RackPlace
		if rp == null:
			continue

		var d := rp.global_position.distance_to(from_pos)
		if d <= radius and d < best_dist:
			best_dist = d
			best = rp

	return best


# =================================================================
# SLOTY W STOJAKU I BLOKADA INTERAKCJI PROBÓWEK
# =================================================================
func _get_my_slots() -> Array:
	## Zbiera wszystkie dzieci (oraz wnuki) oznaczone grupą "work_slots".
	var result: Array = []

	for child in get_children():
		if child is Node and child.is_in_group("work_slots"):
			result.append(child)

		for grand in child.get_children():
			if grand is Node and grand.is_in_group("work_slots"):
				result.append(grand)

	return result


func _set_probe_interactions(probe: Node2D, enabled: bool) -> void:
	## Proste „włącz / wyłącz” pod kątem dragowania i highlightu probówki.
	if probe.has_method("set_highlight_enabled"):
		probe.call("set_highlight_enabled", enabled)

	if probe.has_method("set"):
		probe.set("draggable", enabled)

	var area := probe.get_node_or_null("ProbeArea2D") as Area2D
	if area:
		area.input_pickable = enabled


# =================================================================
# KIEDY WOLNO PRZECIĄGAĆ STOJAK
# =================================================================
func _can_drag_now() -> bool:
	## Blokada dragowania, gdy Lab ma aktywne narzędzie (pipeta, papierek itd.).
	var lab := get_tree().get_first_node_in_group("lab_root")
	if lab == null:
		return true

	var mode_enum: Variant = lab.get("Mode")
	var current_mode: Variant = lab.get("mode")

	# Preferowane: enum jako słownik z kluczem "IDLE".
	if mode_enum is Dictionary and mode_enum.has("IDLE"):
		return current_mode == mode_enum["IDLE"]

	# Fallback do starszej logiki.
	var tool_active: Variant = lab.get("tool_active")
	if tool_active is bool and tool_active:
		return false

	var holding: Variant = lab.get("holding")
	if holding is bool and holding:
		return false

	return true


# =================================================================
# PODPOWIEDZI (cienie RackPlace) PODCZAS DRAGU
# =================================================================
func _update_place_hints(show_hints: bool) -> void:
	## Podpowiedzi dla użytkownika: podświetlenie miejsc, gdzie można odłożyć stojak.
	## LMB: shelf → table → pokazujemy tylko wolne stoły.
	## RMB: table → table/shelf → pokazujemy wolne stoły i ewentualną półkę.
	var allow_table := (_drag_button == MOUSE_BUTTON_LEFT) or (_drag_button == MOUSE_BUTTON_RIGHT)
	var allow_shelf := (_drag_button == MOUSE_BUTTON_RIGHT)

	if _table_place1:
		var free1 := _table_place1.is_free()
		var vis1 := show_hints and allow_table and free1
		_table_place1.show_hint(vis1, true)

	if _table_place2:
		var free2 := _table_place2.is_free()
		var vis2 := show_hints and allow_table and free2
		_table_place2.show_hint(vis2, true)

	if _shelf_place:
		var free_shelf := _shelf_place.is_free()
		var vis_shelf := show_hints and allow_shelf and free_shelf
		_shelf_place.show_hint(vis_shelf, true)


# =================================================================
# POWIADOMIENIE LAB O ZMIANIE POZYCJI STOJAKA
# =================================================================
func _notify_lab_refresh_probes() -> void:
	var lab := get_tree().get_first_node_in_group("lab_root")
	if lab and lab.has_method("_refresh_probe_highlights"):
		lab._refresh_probe_highlights()
