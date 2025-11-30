extends Node2D
class_name ProbeSlot

## =========================================================================
## probe_slot.gd – pojedynczy slot na probówkę
## -------------------------------------------------------------------------
## Odpowiada za:
## - decyzję, czy probówka może się „zadokować” (promień snapu, enabled),
## - przechowywanie referencji do aktualnej probówki,
## - sygnał o zmianie zajętości (wejście / wyjście probówki).
## =========================================================================

signal occupied_changed(slot: ProbeSlot, probe: Node2D)   ## probe == null → slot się zwolnił


# -----------------------------
# USTAWIENIA SLOTU
# -----------------------------

@export var snap_radius: float = 48.0          ## Promień akceptacji dropu (w pikselach).
@export var allow_when_occupied: bool = false  ## Czy wolno nadpisać istniejącą probówkę.
@onready var anchor: Node2D = $Anchor          ## Lokalna „kotwica” (punkt docelowy dla probówki).

@export var enabled: bool = true               ## Czy slot przyjmuje dropy (aktywny / zablokowany).
@export var dim_when_disabled: float = 0.65    ## Przygaszenie wizualne, gdy slot jest wyłączony (feedback).


# -----------------------------
# STAN WEWNĘTRZNY
# -----------------------------

## Probówka aktualnie stojąca w slocie (lub null).
var _current_probe: Node2D = null


# =========================================================================
# INIT I STAN POCZĄTKOWY
# =========================================================================

## Przygotowuje slot po starcie:
## - podpina się do sygnału child_exiting_tree,
## - sprawdza, czy w scenie startowej jest już probówka w środku.
func _ready() -> void:
	if not is_connected("child_exiting_tree", Callable(self, "_on_child_exiting_tree")):
		child_exiting_tree.connect(_on_child_exiting_tree)

	for child in get_children():
		if child is Node2D and child.is_in_group("probes"):
			_maybe_bind_probe(child as Node2D)


# =========================================================================
# API WYWOŁYWANE Z ZEWNĄTRZ
# =========================================================================

## Sprawdza, czy slot jest aktualnie zajęty.
func is_occupied() -> bool:
	return _current_probe != null \
		and is_instance_valid(_current_probe) \
		and _current_probe.get_parent() == self


## Zwraca obecną probówkę lub null, jeśli slot jest wolny.
func get_current_probe() -> Node2D:
	return _current_probe if is_occupied() else null


## Zwraca globalną pozycję „kotwicy” slotu.
func get_anchor_global() -> Vector2:
	return anchor.global_position if anchor else global_position


## Ustawia, czy slot jest włączony:
## - wyłączony slot nie przyjmuje nowych probówek,
## - probówka stojąca w środku zostaje,
## - dzieci CanvasItem są opcjonalnie przygaszane.
func set_enabled(on: bool) -> void:
	enabled = on

	var dim_factor: float = (dim_when_disabled if not enabled else 1.0)
	for child in get_children():
		if child is CanvasItem:
			var canvas_item := child as CanvasItem
			var color: Color = canvas_item.modulate
			color.a = dim_factor
			canvas_item.modulate = color


## Reaguje na start dragowania probówki:
## - jeśli to probówka tego slota, slot się zwalnia.
func on_probe_pickup(probe: Node2D) -> void:
	if _current_probe == probe:
		_current_probe = null
		occupied_changed.emit(self, null)


## Próbuje przyjąć probówkę do slotu:
## - sprawdza widoczność beakera, typ obiektu, enabled, promień snapu,
## - przy allow_when_occupied może nadpisać istniejącą probówkę,
## - ustawia parent, pozycję i emituje occupied_changed.
func accept_probe(probe: Node, at_global_pos: Vector2) -> bool:
	# Sloty w niewidocznych beakerach nie łapią probówek.
	if not _is_in_visible_beaker():
		return false

	if not (probe is Node2D):
		return false
	if not enabled:
		return false
	if is_occupied() and not allow_when_occupied:
		return false

	var anchor_pos: Vector2 = get_anchor_global()
	if at_global_pos.distance_to(anchor_pos) > snap_radius:
		return false

	# Opcjonalne nadpisanie istniejącej probówki (np. sloty w łaźni wodnej).
	if is_occupied() and allow_when_occupied and _current_probe and is_instance_valid(_current_probe):
		_current_probe.queue_free()
		_current_probe = null

	var probe_node := probe as Node2D
	if probe_node.get_parent():
		probe_node.get_parent().remove_child(probe_node)

	add_child(probe_node)
	probe_node.global_position = anchor_pos

	_current_probe = probe_node
	_maybe_bind_probe(probe_node)
	occupied_changed.emit(self, probe_node)
	return true


## Reaguje na powrót probówki tweenem:
## - jeśli probówka wróciła do tego slota, ustawia ją jako bieżącą.
func on_probe_returned(probe: Node2D) -> void:
	if probe != null and probe.get_parent() == self:
		_current_probe = probe
		occupied_changed.emit(self, probe)


# =========================================================================
# POWIĄZANIA ZE STOJĄCĄ PROBÓWKĄ
# =========================================================================

## Ustala ten slot jako właściciela probówki, jeśli stoi ona w tym slocie,
## oraz podpina się pod sygnał drag_started probówki.
func _maybe_bind_probe(probe_node: Node2D) -> void:
	if probe_node.is_in_group("probes") and probe_node.get_parent() == self:
		_current_probe = probe_node

	if probe_node.has_signal("drag_started"):
		var cb := Callable(self, "_on_child_drag_started")
		if probe_node.is_connected("drag_started", cb):
			probe_node.disconnect("drag_started", cb)
		probe_node.connect("drag_started", cb)


## Reaguje na rozpoczęcie dragowania probówki:
## - jeżeli probówka należy do tego slota, slot się zwalnia.
func _on_child_drag_started(probe: Node) -> void:
	if _current_probe == probe:
		_current_probe = null
		occupied_changed.emit(self, null)


## Reaguje na wychodzenie dziecka z drzewa:
## - jeżeli jest to probówka tego slota, slot się zwalnia.
func _on_child_exiting_tree(child: Node) -> void:
	if _current_probe == child:
		_current_probe = null
		occupied_changed.emit(self, null)


# =========================================================================
# POMOCNICZE – BEAKERY I WIDOCZNOŚĆ
# =========================================================================

## Sprawdza, czy slot należy do beakera, który jest widoczny:
## - dla ProbeBeakerów niewidocznych (visible = false) slot nie powinien działać,
## - dla slotów poza beakerem zwraca true (normalne sloty racków).
func _is_in_visible_beaker() -> bool:
	var node_it: Node = self
	while node_it:
		if String(node_it.name).begins_with("ProbeBeaker") and node_it is CanvasItem:
			return (node_it as CanvasItem).visible
		node_it = node_it.get_parent()
	# jeśli slot nie jest w beakerze, traktujemy go jako „normalny”
	return true
