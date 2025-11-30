extends Node2D
class_name RackPlace

## =========================================================================
## rack_place.gd – miejsce dokowania stojaka
## -------------------------------------------------------------------------
## Odpowiada za:
## - przechowywanie typu miejsca (`place_type`: "table" / "shelf"),
## - informację, czy miejsce jest aktualnie zajęte (claim / release),
## - pokazywanie cienia stojaka jako podpowiedzi (hint).
## =========================================================================

@export var place_type: String = "table"        ## "table" albo "shelf".
@export var hint_node_path: NodePath = ^"Hint"  ## Węzeł z cieniem (Sprite2D / inne CanvasItem).
@export var hint_alpha_free: float = 0.7        ## Przezroczystość cienia, gdy miejsce jest wolne.
@export var hint_alpha_taken: float = 0.25      ## Przezroczystość cienia, gdy miejsce jest zajęte.

## Obiekt, który aktualnie zajmuje miejsce (zwykle ProbeRack).
var _occupied_by: Node = null

@onready var _hint_node: CanvasItem = get_node_or_null(hint_node_path) as CanvasItem


# =========================================================================
# ZARZĄDZANIE MIEJSCAMI STOJAKA
# =========================================================================

## Sprawdza, czy miejsce jest wolne.
func is_free() -> bool:
	return _occupied_by == null


## Próbuje zająć miejsce przez podany obiekt:
## - zwraca true, jeśli miejsce było wolne,
## - w przeciwnym razie nic nie zmienia.
func claim(by: Node) -> bool:
	if not is_free():
		return false

	_occupied_by = by
	return true


## Zwalnia miejsce:
## - tylko, gdy wywołuje je obiekt, który wcześniej je zajął.
func release(by: Node) -> void:
	if _occupied_by == by:
		_occupied_by = null


## Ustawia widoczność i alfa cienia (hint) pod stojakiem:
## - shadow = czy w ogóle pokazywać cień,
## - available = czy miejsce jest wolne (intensywniejszy cień) czy „zajęte” (słabszy cień).
func show_hint(shadow: bool, available: bool = true) -> void:
	if _hint_node == null:
		return

	_hint_node.visible = shadow

	var color: Color = _hint_node.modulate
	color.a = hint_alpha_free if available else hint_alpha_taken
	_hint_node.modulate = color
