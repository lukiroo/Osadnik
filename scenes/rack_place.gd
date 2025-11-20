extends Node2D
class_name RackPlace

## Proste miejsce dokowania stojaka (półka / blat).
## Przechowuje informację:
## - jakiego typu jest miejsce (`place_type`: "table" lub "shelf"),
## - czy jest aktualnie zajęte,
## - oraz pokazuje zarys stojaka jako podpowiedź.

@export var place_type: String = "table"        ## "table" albo "shelf".
@export var hint_node_path: NodePath = ^"Hint"  ## Węzeł z cieniem (Sprite2D / inne CanvasItem).
@export var hint_alpha_free: float = 0.7        ## Przezroczystość, gdy miejsce jest dostępne.
@export var hint_alpha_taken: float = 0.25      ## Przezroczystość, gdy miejsce zajęte (np. sugerujemy brak miejsca).

var _occupied_by: Node = null                   ## Obiekt, który aktualnie zajmuje miejsce (zwykle ProbeRack).

@onready var _hint_node: CanvasItem = get_node_or_null(hint_node_path) as CanvasItem


# =================================================================
# FUNKCJE UŻYTKOWE (API DLA ProbeRack)
# =================================================================
func is_free() -> bool:
	## True, jeśli nikt nie zajął miejsca.
	return _occupied_by == null


func claim(by: Node) -> bool:
	## Próba zajęcia miejsca przez podany obiekt.
	## Zwraca true, jeśli miejsce było wolne.
	if not is_free():
		return false

	_occupied_by = by
	return true


func release(by: Node) -> void:
	## Zwolnienie miejsca – tylko przez obiekt, który je wcześniej zajął.
	if _occupied_by == by:
		_occupied_by = null


func show_hint(shadow: bool, available: bool = true) -> void:
	## Sterowanie cieniem pod stojakiem:
	## - `shadow` decyduje, czy w ogóle pokazywać,
	## - `available` wybiera intensywność (miejsce wolne / zajęte).
	if _hint_node == null:
		return

	_hint_node.visible = shadow

	var color := _hint_node.modulate
	color.a = (hint_alpha_free if available else hint_alpha_taken)
	_hint_node.modulate = color
