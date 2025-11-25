extends Node2D
class_name ProbeSlot

## Pojedynczy slot na probówkę.
## Odpowiada za:
## - decyzję, czy probówka może się „zadokować” (promień snapu, enabled),
## - przechowywanie referencji do aktualnej probówki,
## - sygnał o zmianie zajętości (wejście / wyjście probówki),
## - dołączenie się do grupy `probe_dropzones`.

signal occupied_changed(slot: ProbeSlot, probe: Node2D)   ## probe == null → slot się zwolnił

# -------------------- USTAWIENIA --------------------
@export var snap_radius: float = 48.0                      ## Promień akceptacji dropu.
@export var allow_when_occupied: bool = false              ## Czy wolno nadpisać istniejącą probówkę.
@onready var anchor: Node2D = $Anchor

@export var enabled: bool = true                           ## Czy slot przyjmuje dropy.
@export var dim_when_disabled: float = 0.65                ## Przygaszenie, gdy slot jest wyłączony.

# -------------------- STAN WEWNĘTRZNY --------------------
var _current_probe: Node2D = null                          ## Probówka aktualnie stojąca w slocie (lub null).


# =================================================================
# INIT I STAN POCZĄTKOWY
# =================================================================
func _ready() -> void:

	## Jeśli scena startuje już z probówką w środku, traktuje ją jako zajętą.
	for child in get_children():
		if child is Node2D and child.is_in_group("probes"):
			_maybe_bind_probe(child as Node2D)


# =================================================================
# FUNKCJE WYWOŁYWANE Z ZEWNĄTRZ
# =================================================================
func is_occupied() -> bool:
	## Slot uznajemy za zajęty wtedy, gdy:
	## - ma zapamiętaną probówkę,
	## - probówka ma ten slot jako parent.
	return _current_probe != null \
		and is_instance_valid(_current_probe) \
		and _current_probe.get_parent() == self


func get_current_probe() -> Node2D:
	## Zwraca obecną probówkę lub null, jeśli slot jest wolny.
	return _current_probe if is_occupied() else null


func get_anchor_global() -> Vector2:
	## Domyślnie węzeł `Anchor`; jeśli go nie ma, używamy pozycji samego slota.
	return anchor.global_position if anchor else global_position


func set_enabled(on: bool) -> void:
	## Używane np. przez ProbeRack – stojak na półce → sloty wyłączone.
	## Nie wyrzucamy probówki, tylko blokujemy nowe dokowania.
	enabled = on


func on_probe_pickup(probe: Node2D) -> void:
	## Wołane z Probe.gd przy starcie dragowania probówki.
	## Jeśli to ta probówka, która stała w tym slocie, uznaje że slot się zwolnił.
	if _current_probe == probe:
		_current_probe = null
		occupied_changed.emit(self, null)


func accept_probe(probe: Node, at_global_pos: Vector2) -> bool:
	## Sloty w niewidocznych beakerach nie łapią probówek.
	if not _is_in_visible_beaker(): 
		return false
	## Główne wejście dropu – probówka próbuje się „zadokować”.
	if not (probe is Node2D):
		return false
	if not enabled:
		return false
	if is_occupied() and not allow_when_occupied:
		return false

	## Sprawdza, czy punkt dropu mieści się w promieniu snapu wokół doku.
	var anchor_pos := get_anchor_global()
	if at_global_pos.distance_to(anchor_pos) > snap_radius:
		return false

	## Opcjonalne nadpisanie istniejącej probówki (np. sloty w łaźni wodnej).
	if is_occupied() and allow_when_occupied and _current_probe and is_instance_valid(_current_probe):
		_current_probe.queue_free()
		_current_probe = null

	var p := probe as Node2D
	if p.get_parent():
		p.get_parent().remove_child(p)

	add_child(p)
	p.global_position = anchor_pos

	_current_probe = p
	_maybe_bind_probe(p)
	occupied_changed.emit(self, p)
	return true


func on_probe_returned(probe: Node2D) -> void:
	## Wołane, gdy probówka tweenem wróciła do slota po nieudanym dropie.
	if probe != null and probe.get_parent() == self:
		_current_probe = probe
		occupied_changed.emit(self, probe)


# =================================================================
# POWIĄZANIA ZE STOJĄCĄ PROBÓWKĄ
# =================================================================
func _maybe_bind_probe(p: Node2D) -> void:
	## Ustala ten slot jako „właściciela” probówki, jeśli ta faktycznie tu stoi
	## i podłącza się pod sygnał `drag_started`.
	if p.is_in_group("probes") and p.get_parent() == self:
		_current_probe = p

	if p.has_signal("drag_started"):
		var cb := Callable(self, "_on_child_drag_started")
		if p.is_connected("drag_started", cb):
			p.disconnect("drag_started", cb)
		p.connect("drag_started", cb)


func _on_child_drag_started(probe: Node) -> void:
	## Gdy probówka zaczyna dragowanie, slot przestaje być zajęty.
	if _current_probe == probe:
		_current_probe = null
		occupied_changed.emit(self, null)


func _on_child_exiting_tree(child: Node) -> void:
	## Gdy probówka jest niszczona lub przepinana gdzie indziej, slot też się zwalnia.
	if _current_probe == child:
		_current_probe = null
		occupied_changed.emit(self, null)


func _is_in_visible_beaker() -> bool:
	var node_it: Node = self
	while node_it:
		if String(node_it.name).begins_with("ProbeBeaker") and node_it is CanvasItem:
			return (node_it as CanvasItem).visible
		node_it = node_it.get_parent()
	# jeśli slot nie jest w beakerze, traktujemy go jako „normalny”
	return true
