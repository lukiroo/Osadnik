extends Node2D
class_name ProbeRack

## =========================================================================
## probe_rack.gd – stojak na probówki
## -------------------------------------------------------------------------
## Odpowiada za:
## - przenoszenie stojaka między półką a stołem (uchwyt HandleArea2D),
## - zajmowanie miejsc typu RackPlace (półka + dwa miejsca na blacie),
## - włączanie/wyłączanie interakcji slotów i probówek, gdy stojak stoi na półce,
## - prosty drag LMB (tylko z półki na stół) i RMB (stół ↔ stół / półka).
## =========================================================================

# -------------------- USTAWIENIA --------------------

@export var start_on_shelf: bool = false          ## Czy stojak startuje na półce.
@export var shelf_scale: float = 0.8              ## Skala stojaka na półce.
@export var table_scale: float = 1.0              ## Skala stojaka na stole.
@export var tween_time: float = 0.22              ## Czas tweena przy przenoszeniu stojaka.
@export var accept_radius: float = 100.0          ## Promień „trafienia” RackPlace.
@export var disable_probe_interactions_on_shelf: bool = true  ## Czy sloty/probówki są wyłączone na półce.

@export var shelf_place_path: NodePath
@export var table_place1_path: NodePath
@export var table_place2_path: NodePath

@onready var _handle: Area2D = $HandleArea2D

@onready var _shelf_place: RackPlace  = get_node_or_null(shelf_place_path) as RackPlace
@onready var _table_place1: RackPlace = get_node_or_null(table_place1_path) as RackPlace
@onready var _table_place2: RackPlace = get_node_or_null(table_place2_path) as RackPlace


# -------------------- STAN WEWNĘTRZNY --------------------

## Aktualne miejsce stojaka (shelf / table).
var _current_place: RackPlace = null

## Czy stojak jest aktualnie przeciągany.
var _is_dragging: bool = false

## Którym przyciskiem myszy rozpoczęto drag.
var _drag_button: int = 0

## Wektor offsetu między pozycją stojaka a kursorem (przy starcie dragowania).
var _drag_offset: Vector2 = Vector2.ZERO

## Pozycja stojaka sprzed przeciągania (fallback, gdy nie uda się znaleźć miejsca).
var _drag_start_pos: Vector2 = Vector2.ZERO

## Miejsce, z którego stojak wystartował (RackPlace).
var _drag_start_place: RackPlace = null

## Zapisany z_index przed dragowaniem (żeby przywrócić kolejność na końcu).
var _z_before_drag: int = 0


# =========================================================================
# INIT I STAN STARTOWY
# =========================================================================

## Przygotowuje stojak po starcie:
## - włącza input na uchwycie,
## - ustala miejsce startowe (półka / stół),
## - po jednej klatce jeszcze raz nakłada tryb (półka/stół) na sloty.
func _ready() -> void:
	if _handle:
		_handle.input_pickable = true

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

	# Po jednej klatce sloty są już gotowe – jeszcze raz dopasowujemy tryb.
	call_deferred("_reapply_place_mode_after_ready")


## Powtórnie nakłada tryb place_type na stojak po tym, jak wszystkie dzieci się zainicjalizują.
func _reapply_place_mode_after_ready() -> void:
	var place_type := (_current_place.place_type if _current_place != null else ("shelf" if start_on_shelf else "table"))
	_apply_place_mode(place_type)


## Aktualizuje pozycję stojaka w trakcie dragowania (podąża za kursorem).
func _process(_delta: float) -> void:
	if _is_dragging:
		global_position = get_global_mouse_position() + _drag_offset


# =========================================================================
# GLOBAL INPUT – PUSZCZENIE PRZYCISKU POZA UCHWYTEM
# =========================================================================

## Obsługuje globalne puszczenie przycisku myszy:
## - jeśli stojak jest przeciągany i puszczono przycisk, który rozpoczął dragowanie,
##   kończy drag (_end_drag).
func _unhandled_input(event: InputEvent) -> void:
	if not _is_dragging:
		return

	if event is InputEventMouseButton and not event.pressed and event.button_index == _drag_button:
		_end_drag()
		get_viewport().set_input_as_handled()


# =========================================================================
# INPUT NA UCHWYCIE
# =========================================================================

## Obsługuje input na uchwycie stojaka:
## - LMB (z półki) → start dragowania w stronę stołu,
## - RMB (ze stołu) → start dragowania na stół/półkę,
## - puszczenie przycisku kończy dragowanie.
func _on_handle_input_event(_vp, event: InputEvent, _shape_idx: int) -> void:
	if not _can_drag_now():
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			# LMB: tylko z półki na stół.
			if _is_on_shelf():
				_begin_drag(MOUSE_BUTTON_LEFT)
				get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# RMB: tylko ze stołu (stół → stół / półka).
			if _is_on_table():
				_begin_drag(MOUSE_BUTTON_RIGHT)
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and not event.pressed:
		if _is_dragging and event.button_index == _drag_button:
			_end_drag()
			get_viewport().set_input_as_handled()


# =========================================================================
# ROZPOCZĘCIE I ZAKOŃCZENIE DRAGOWANIA
# =========================================================================

## Rozpoczyna dragowanie stojaka:
## - zapamiętuje przycisk, offset, pozycję startową, miejsce startowe,
## - podnosi z_index,
## - zwalnia miejsce w RackPlace,
## - włącza podpowiedzi (hints) dla miejsc docelowych.
func _begin_drag(button: int) -> void:
	_is_dragging = true
	_drag_button = button
	_drag_offset = global_position - get_global_mouse_position()
	_drag_start_pos = global_position
	_drag_start_place = _current_place

	_z_before_drag = z_index
	z_index = 99   # Na czas dragowania stojak idzie „na wierzch”.

	if _current_place:
		_current_place.release(self)
		_current_place = null

	_update_place_hints(true)


## Kończy dragowanie stojaka:
## - szuka docelowego RackPlace (w promieniu accept_radius),
## - zależnie od przycisku wybiera tylko stoły (LMB) albo stół/półkę (RMB),
## - gdy nic nie pasuje – próbuje wrócić na miejsce startowe, albo wraca tweenem.
func _end_drag() -> void:
	_update_place_hints(false)
	_is_dragging = false
	z_index = _z_before_drag

	var target_place: RackPlace = null

	if _drag_button == MOUSE_BUTTON_LEFT:
		# Półka → stół – szukamy najbliższego wolnego stołu.
		target_place = _pick_nearest_free_table_place(global_position, accept_radius)
	else:
		# RMB: stół → stół / półka.
		target_place = _pick_nearest_free_table_place(global_position, accept_radius)
		if target_place == null and _shelf_place and _shelf_place.is_free():
			if _shelf_place.global_position.distance_to(global_position) <= accept_radius:
				target_place = _shelf_place

	# Jeśli nie znaleźliśmy sensownego miejsca – próbujemy wrócić na start.
	if target_place == null:
		if _drag_start_place and _drag_start_place.claim(self):
			_current_place = _drag_start_place
			_snap_to(_drag_start_place.global_position, false)
			_apply_place_mode(_drag_start_place.place_type)
			_notify_lab_refresh_probes()
		else:
			# Jeszcze jeden fallback: wracamy w poprzednie miejsce bez claimu.
			create_tween().tween_property(self, "global_position", _drag_start_pos, tween_time)
		return

	_claim_and_snap(target_place, false)


# =========================================================================
# CLAIM + SNAP + TRYB PRACY
# =========================================================================

## Przejmuje miejsce w RackPlace i ustawia stojak w tym miejscu:
## - jeśli claim się uda, wywołuje _snap_to i _apply_place_mode,
## - powiadamia Lab o zmianie (refresh highlightów probówek).
func _claim_and_snap(place: RackPlace, instant: bool) -> void:
	if not place or not place.claim(self):
		return

	_current_place = place
	_snap_to(place.global_position, instant)
	_apply_place_mode(place.place_type)
	_notify_lab_refresh_probes()


## Ustawia global_position stojaka:
## - instant = true → bez tweena,
## - instant = false → z tweenem.
func _snap_to(target_pos: Vector2, instant: bool) -> void:
	if instant:
		global_position = target_pos
	else:
		create_tween().tween_property(self, "global_position", target_pos, tween_time)


## Nakłada tryb „półka/stół” na stojak:
## - skaluje stojak (shelf_scale / table_scale),
## - gdy disable_probe_interactions_on_shelf == true,
##   włącza/wyłącza interakcje slotów i probówek.
func _apply_place_mode(place_type: String) -> void:
	var target_scale: float = table_scale if place_type == "table" else shelf_scale
	create_tween().tween_property(self, "scale", Vector2(target_scale, target_scale), tween_time)

	var allow_probes: bool = (place_type == "table")
	if disable_probe_interactions_on_shelf:
		for slot in _get_my_slots():
			if slot.has_method("set_enabled"):
				slot.call("set_enabled", allow_probes)

			if slot.has_method("get_current_probe"):
				var probe_node := slot.call("get_current_probe") as Node2D
				if probe_node:
					_set_probe_interactions(probe_node, allow_probes)


# =========================================================================
# WYBÓR MIEJSCA (RACKPLACE)
# =========================================================================

## Sprawdza, czy stojak stoi na półce.
func _is_on_shelf() -> bool:
	return _is_place_type(_current_place, "shelf")


## Sprawdza, czy stojak stoi na stole.
func _is_on_table() -> bool:
	return _is_place_type(_current_place, "table")


## Sprawdza, czy konkretne miejsce ma określony typ (np. "shelf", "table").
func _is_place_type(place: RackPlace, place_type: String) -> bool:
	return place != null and place.place_type == place_type


## Zwraca dowolne wolne miejsce na stole (najbliższe aktualnej pozycji stojaka).
func _pick_free_table_place() -> RackPlace:
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


## Zwraca najbliższe wolne miejsce na stole w zadanym promieniu.
func _pick_nearest_free_table_place(from_pos: Vector2, radius: float) -> RackPlace:
	var best_place: RackPlace = null
	var best_dist: float = INF

	var candidates: Array = []
	if _table_place1 and _table_place1.is_free():
		candidates.append(_table_place1)
	if _table_place2 and _table_place2.is_free():
		candidates.append(_table_place2)

	for place in candidates:
		var rack_place := place as RackPlace
		if rack_place == null:
			continue

		var dist: float = rack_place.global_position.distance_to(from_pos)
		if dist <= radius and dist < best_dist:
			best_dist = dist
			best_place = rack_place

	return best_place


# =========================================================================
# SLOTY W STOJAKU I BLOKADA INTERAKCJI PROBÓWEK
# =========================================================================

## Zwraca wszystkie sloty należące do tego stojaka:
## - szuka dzieci i wnuków w grupie "work_slots".
func _get_my_slots() -> Array:
	var result: Array = []

	for child in get_children():
		if child is Node and child.is_in_group("work_slots"):
			result.append(child)

		for grand in child.get_children():
			if grand is Node and grand.is_in_group("work_slots"):
				result.append(grand)

	return result


## Ustawia interakcje probówki (drag, highlight, input pickable) na włączone/wyłączone.
func _set_probe_interactions(probe: Node2D, enabled: bool) -> void:
	if probe.has_method("set_highlight_enabled"):
		probe.call("set_highlight_enabled", enabled)

	if probe.has_method("set"):
		probe.set("draggable", enabled)

	var probe_area := probe.get_node_or_null("ProbeArea2D") as Area2D
	if probe_area:
		probe_area.input_pickable = enabled


# =========================================================================
# KIEDY WOLNO PRZECIĄGAĆ STOJAK
# =========================================================================

## Sprawdza, czy stojak wolno w danym momencie przeciągać:
## - blokuje drag, gdy Lab ma aktywne narzędzie (papierek, pipeta itd.),
## - preferuje enum Mode z kluczem "IDLE".
func _can_drag_now() -> bool:
	var lab := get_tree().get_first_node_in_group("lab_root")
	if lab == null:
		return true

	var mode_enum: Variant = lab.get("Mode")
	var current_mode: Variant = lab.get("mode")

	if mode_enum is Dictionary and mode_enum.has("IDLE"):
		return current_mode == mode_enum["IDLE"]

	var tool_active: Variant = lab.get("tool_active")
	if tool_active is bool and tool_active:
		return false

	var holding: Variant = lab.get("holding")
	if holding is bool and holding:
		return false

	return true


# =========================================================================
# PODPOWIEDZI (RACKPLACE HINTY) PODCZAS DRAGU
# =========================================================================

## Aktualizuje podpowiedzi dla miejsc RackPlace podczas dragowania:
## - LMB: shelf → table → pokazuje tylko wolne stoły,
## - RMB: table → table/shelf → pokazuje wolne stoły i ewentualnie półkę.
func _update_place_hints(show_hints: bool) -> void:
	var allow_table: bool = (_drag_button == MOUSE_BUTTON_LEFT) or (_drag_button == MOUSE_BUTTON_RIGHT)
	var allow_shelf: bool = (_drag_button == MOUSE_BUTTON_RIGHT)

	if _table_place1:
		var free1: bool = _table_place1.is_free()
		var visible1: bool = show_hints and allow_table and free1
		_table_place1.show_hint(visible1, true)

	if _table_place2:
		var free2: bool = _table_place2.is_free()
		var visible2: bool = show_hints and allow_table and free2
		_table_place2.show_hint(visible2, true)

	if _shelf_place:
		var free_shelf: bool = _shelf_place.is_free()
		var visible_shelf: bool = show_hints and allow_shelf and free_shelf
		_shelf_place.show_hint(visible_shelf, true)


# =========================================================================
# POWIADOMIENIE LAB O ZMIANIE POZYCJI STOJAKA
# =========================================================================

## Informuje Lab, że stojak zmienił miejsce:
## - Lab może odświeżyć highlighty probówek, dostępność itp.
func _notify_lab_refresh_probes() -> void:
	var lab := get_tree().get_first_node_in_group("lab_root")
	if lab and lab.has_method("_refresh_probe_highlights"):
		lab._refresh_probe_highlights()
