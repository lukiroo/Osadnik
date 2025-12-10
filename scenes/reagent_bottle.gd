extends Node2D
class_name ReagentBottle

## =========================================================================
## reagent_bottle.gd – butelka z odczynnikiem na półce
## -------------------------------------------------------------------------
## Odpowiada za:
## - reagowanie na klik LPM (sygnał left_clicked → Lab wchodzi w tryb HOLDING),
## - wyświetlanie etykiety z nazwą odczynnika (display_name / id),
## - pokazywanie koloru cieczy w butelce na podstawie Reagent.liquid_color,
## - prosty outline przy hoverze, sterowany z Lab (set_hover_enabled).
## =========================================================================

signal left_clicked(bottle: ReagentBottle)

# -----------------------------
# WĘZŁY SCENY
# -----------------------------

@onready var area: Area2D            = $BottleArea2D
@onready var full_sprite: Sprite2D   = $BottleClosed
@onready var empty_sprite: Sprite2D  = $BottleOpened
@onready var liquid_sprite: Sprite2D = $BottleLiquid

@export var label_path: NodePath = ^"Label"
@onready var label: Label = get_node_or_null(label_path) as Label


# -----------------------------
# ZASÓB ODCZYNNIKA
# -----------------------------

var _reagent: Reagent = null

@export var reagent: Reagent:
	set(value):
		_reagent = value
		_apply_label()
		_apply_liquid_color()
	get:
		return _reagent


# -----------------------------
# MATERIAŁY / HOVER
# -----------------------------

var mat_full: ShaderMaterial = null
var mat_empty: ShaderMaterial = null
var hover_enabled: bool = true

const U_HIGHLIGHT := "highlight"
const U_HIGHLIGHT_STRENGTH := "highlight_strength"


# =========================================================================
# INICJALIZACJA – konfiguracja butelki i materiałów
# =========================================================================

## Przygotowuje butelkę po starcie:
## - dodaje do grupy "bottles" (Lab szuka po tej grupie),
## - duplikuje materiały shaderowe, żeby highlight był per instancja,
## - ustawia stan „pełna” + etykietę i kolor cieczy z reagenta.
func _ready() -> void:
	add_to_group("bottles")

	mat_full  = _dup_shader_if_any(full_sprite)
	mat_empty = _dup_shader_if_any(empty_sprite)

	show_full(true)
	_set_outline(false)
	_apply_label()
	_apply_liquid_color()


# =========================================================================
# INPUT / HOVER
# =========================================================================

## Obsługuje input na obszarze butelki:
## - reaguje na LPM,
## - emituje left_clicked(bottle), Lab przełącza się w tryb HOLDING.
func _on_area_input_event(_vp: Node, event: InputEvent, _shape_idx: int) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		left_clicked.emit(self)
		get_viewport().set_input_as_handled()


## Reaguje na wejście kursora nad butelkę – włącza outline, jeśli hover_enabled.
func _on_mouse_entered() -> void:
	if hover_enabled and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_set_outline(true)


## Reaguje na wyjście kursora z butelki – gasi outline.
func _on_mouse_exited() -> void:
	_set_outline(false)


## Gasi outline przy każdym wciśnięciu LPM – żeby nie został po kliknięciu.
func _input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_set_outline(false)


# =========================================================================
# HOVER – sterowanie z zewnątrz (Lab)
# =========================================================================

## Umożliwia globalne włączenie/wyłączenie podświetlenia butelki.
func set_hover_enabled(enabled: bool) -> void:
	hover_enabled = enabled
	if not enabled:
		_set_outline(false)


## Ustawia parametry outline w materiałach shaderowych (pełna/pusta).
func _set_outline(on: bool) -> void:
	var strength: float = (1.0 if on else 0.0)
	if mat_full:
		_set_highlight_uniforms(mat_full, on, strength)
	if mat_empty:
		_set_highlight_uniforms(mat_empty, on, strength)


# =========================================================================
# STAN „PEŁNA / PUSTA” – warstwa graficzna
# =========================================================================

## Ustawia wariant graficzny: butelka pełna albo otwarta/pusta.
func show_full(is_full_state: bool) -> void:
	if full_sprite:
		full_sprite.visible = is_full_state
	if liquid_sprite:
		liquid_sprite.visible = is_full_state
	if empty_sprite:
		empty_sprite.visible = not is_full_state


## Skrót dla show_full(false).
func show_empty() -> void:
	show_full(false)


## Zwraca informację, czy aktualnie wyświetlana jest grafika „pełnej” butelki.
func is_full() -> bool:
	return full_sprite != null and full_sprite.visible


# =========================================================================
# POBRANIE ID ODCZYNNIKA – etykieta butelki
# =========================================================================

## Zwraca identyfikator odczynnika (id z Reagent, np. "HCl").
func get_reagent_id() -> String:
	return _reagent.id if _reagent else ""


## Zwraca nazwę wyświetlaną na etykiecie (display_name albo id).
func get_reagent_display_name() -> String:
	if _reagent == null:
		return ""
	if _reagent.display_name != "":
		return _reagent.display_name
	return _reagent.id


# =========================================================================
# ETYKIETA I KOLOR CIECZY
# =========================================================================

## Aktualizuje tekst etykiety na podstawie zasobu Reagent.
func _apply_label() -> void:
	if label == null:
		return

	var label_text: String = ""
	if _reagent:
		label_text = _reagent.display_name if _reagent.display_name != "" else _reagent.id

	label.text = label_text
	label.visible = (label_text != "")


## Ustawia kolor cieczy w butelce na podstawie Reagent.liquid_color:
## - jeśli reagent jest przypisany, moduluje sprite kolorem liquid_color,
## - jeśli brak reagenta, ciecz jest „niewidoczna” (alpha = 0).
func _apply_liquid_color() -> void:
	if liquid_sprite == null:
		return

	var tint := Color(1, 1, 1, 0.0)
	if _reagent:
		tint = _reagent.liquid_color

	liquid_sprite.modulate = tint


# =========================================================================
# POMOCNICZE – materiały shaderowe i highlight
# =========================================================================

## Duplikuje materiał ShaderMaterial ze sprita, jeżeli istnieje, i ustawia go na spricie.
func _dup_shader_if_any(sprite_node: Sprite2D) -> ShaderMaterial:
	if sprite_node and sprite_node.material is ShaderMaterial:
		var duplicate_material := (sprite_node.material as ShaderMaterial).duplicate()
		sprite_node.material = duplicate_material
		return duplicate_material
	return null


## Ustawia uniformy odpowiedzialne za outline w materiale shadera.
func _set_highlight_uniforms(mat: ShaderMaterial, on: bool, strength: float) -> void:
	if mat == null:
		return
	mat.set_shader_parameter(U_HIGHLIGHT, on)
	mat.set_shader_parameter(U_HIGHLIGHT_STRENGTH, strength)
