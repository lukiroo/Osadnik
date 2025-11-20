@tool
extends Node2D
class_name ReagentBottle

## Butelka z odczynnikiem na półce.
## - reaguje na klik LMB (sygnał left_clicked → Lab wchodzi w tryb HOLDING),
## - wyświetla etykietę z nazwą odczynnika,
## - kolor cieczy jest brany z zasobu Reagent.

signal left_clicked(bottle: ReagentBottle)

# -------------------- WĘZŁY SCENY --------------------
@onready var area: Area2D            = $BottleArea2D
@onready var full_sprite: Sprite2D   = $BottleClosed
@onready var empty_sprite: Sprite2D  = $BottleOpened
@onready var liquid_sprite: Sprite2D = $BottleLiquid

@export var label_path: NodePath = ^"Label"
@onready var label: Label = get_node_or_null(label_path) as Label

# -------------------- ZASÓB ODCZYNNIKA --------------------
var _reagent: Reagent = null

@export var reagent: Reagent:
	set(value):
		_reagent = value
		_apply_label()
		_apply_liquid_color()
	get:
		return _reagent

# -------------------- MATERIAŁY / HOVER --------------------
var mat_full: ShaderMaterial = null  ## Materiał sprita „pełnej” butelki (duplikowany per instancja).
var mat_empty: ShaderMaterial = null ## Materiał sprita „pustej” butelki.
var hover_enabled: bool = true       ## Czy butelka reaguje na hover (outline).

const U_HIGHLIGHT := "highlight"
const U_HIGHLIGHT_STRENGTH := "highlight_strength"


# =================================================================
# INIT – konfiguracja butelki i materiałów
# =================================================================
func _ready() -> void:
	## Rejestracja w grupie – Lab może szukać butelek przez `get_nodes_in_group("bottles")`.
	add_to_group("bottles")

	## Duplikacja materiałów shaderowych, żeby parametry były per-instancja.
	mat_full = _dup_shader_if_any(full_sprite)
	mat_empty = _dup_shader_if_any(empty_sprite)

	## Stan początkowy: butelka „pełna”, brak outline, etykieta i kolor ustawione z reagentu.
	show_full(true)
	_set_outline(false)
	_apply_label()
	_apply_liquid_color()


# =================================================================
# INPUT / HOVER
# =================================================================
func _on_area_input_event(_vp: Node, event: InputEvent, _shape_idx: int) -> void:
	## Reagujemy tylko na lewy przycisk myszy.
	if event is InputEventMouseButton and event.pressed:
		## Jeśli korzystasz z InputMap, używamy akcji "left_click".
		if event.is_action_pressed("left_click"):
			left_clicked.emit(self)
			get_viewport().set_input_as_handled()


func _on_mouse_entered() -> void:
	## Outline pojawia się przy wejściu kursora,
	## ale tylko jeśli hover jest włączony i LMB nie jest aktualnie wciśnięty.
	if hover_enabled and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_set_outline(true)


func _on_mouse_exited() -> void:
	## Wyjście kursora z obszaru – gasimy outline.
	_set_outline(false)


func _input(event: InputEvent) -> void:
	## Każde wciśnięcie LMB gdziekolwiek na ekranie gasi outline,
	## żeby efekt nie zostawał „przyklejony”.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_set_outline(false)


# =================================================================
# HOVER – sterowanie z zewnątrz (np. z Lab)
# =================================================================
func set_hover_enabled(enabled: bool) -> void:
	## Pozwala globalnie włączyć/wyłączyć podświetlenie butelki.
	hover_enabled = enabled
	if not enabled:
		_set_outline(false)


func _set_outline(on: bool) -> void:
	## Ustawia parametry outline w materiałach shaderowych (jeśli istnieją).
	var strength := (1.0 if on else 0.0)
	if mat_full:
		_set_highlight_uniforms(mat_full, on, strength)
	if mat_empty:
		_set_highlight_uniforms(mat_empty, on, strength)
	## Ciecz nie ma outline – za podświetlenie odpowiada kontur butelki.


# =================================================================
# STAN „PEŁNA / PUSTA” – warstwa graficzna
# =================================================================
func show_full(v: bool) -> void:
	## Ustawia wariant graficzny: butelka pełna albo otwarta/pusta.
	if full_sprite:
		full_sprite.visible = v
	if liquid_sprite:
		liquid_sprite.visible = v
	if empty_sprite:
		empty_sprite.visible = not v


func show_empty() -> void:
	## Skrót dla show_full(false).
	show_full(false)


func is_full() -> bool:
	## Informacja pomocnicza – czy aktualnie używany jest wariant „pełny”.
	return full_sprite != null and full_sprite.visible


# =================================================================
# API DLA LAB – identyfikacja odczynnika
# =================================================================
func get_reagent_id() -> String:
	## Zwraca techniczny identyfikator odczynnika (np. "HCl").
	return _reagent.id if _reagent else ""


func get_reagent_display_name() -> String:
	## Zwraca nazwę wyświetlaną na etykiecie (display_name albo id).
	if _reagent == null:
		return ""
	if _reagent.display_name != "":
		return _reagent.display_name
	return _reagent.id


# =================================================================
# ETYKIETA I KOLOR CIECZY
# =================================================================
func _apply_label() -> void:
	## Aktualizacja tekstu etykiety na podstawie zasobu Reagent.
	if label == null:
		return

	var txt := ""
	if _reagent:
		if _reagent.display_name != "":
			txt = _reagent.display_name
		else:
			txt = _reagent.id

	label.text = txt
	label.visible = (txt != "")


func _apply_liquid_color() -> void:
	## Ustawia kolor cieczy na podstawie pola `liquid_color` w Reagent.
	if liquid_sprite == null:
		return

	var tint := Color(1, 1, 1, 0.0)  ## Domyślnie „pusta” butelka (alpha = 0).
	if _reagent and _reagent.has_method("get"):
		var v: Variant = _reagent.get("liquid_color")
		if v is Color:
			tint = v

	liquid_sprite.modulate = tint


# =================================================================
# POMOCNICZE – materiały shaderowe i highlight
# =================================================================
func _dup_shader_if_any(spr: Sprite2D) -> ShaderMaterial:
	## Jeżeli sprite ma materiał ShaderMaterial, duplikujemy go
	## i zwracamy referencję do kopii (per instancja).
	if spr and spr.material and spr.material is ShaderMaterial:
		var dupe := (spr.material as ShaderMaterial).duplicate()
		spr.material = dupe
		return dupe
	return null


func _set_highlight_uniforms(mat: ShaderMaterial, on: bool, strength: float) -> void:
	## Bezpieczne ustawianie uniformów odpowiedzialnych za outline.
	if mat == null or mat.shader == null:
		return

	var has_h := false
	var has_s := false

	for u in mat.shader.get_shader_uniform_list():
		var ud: Dictionary = u
		var u_name := String(ud.get("name", ""))
		if u_name == U_HIGHLIGHT:
			has_h = true
		elif u_name == U_HIGHLIGHT_STRENGTH:
			has_s = true

	if has_h:
		mat.set_shader_parameter(U_HIGHLIGHT, on)
	if has_s:
		mat.set_shader_parameter(U_HIGHLIGHT_STRENGTH, strength)
