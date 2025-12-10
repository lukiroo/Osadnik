extends Node2D
class_name IndicatorBox

## =========================================================================
## indicator_box.gd – pudełko z papierkami wskaźnikowymi
## -------------------------------------------------------------------------
## Odpowiada za:
## - emitowanie sygnału left_clicked po kliknięciu LPM,
## - proste podświetlenie (outline) przy najechaniu kursorem.
## =========================================================================

signal left_clicked(box: Node)

# --------------------- REFERENCJE DO WĘZŁÓW ---------------------

@onready var hit_area: Area2D = $Area2D
@onready var box_sprite: Sprite2D = $Sprite2D

# --------------------- STAN HOVER / SHADER ---------------------

var _shader_mat: ShaderMaterial = null        ## Lokalna kopia materiału sprita.
var _hover_enabled: bool = true               ## Flaga umożliwiająca wyłączenie reakcji na hover.


# =========================================================================
# INICJALIZACJA – przygotowanie materiału i stanu początkowego
# =========================================================================

## Przygotowuje pudełko:
## - duplikuje materiał sprita,
## - wyłącza outline na starcie.
func _ready() -> void:
	if box_sprite.material:
		box_sprite.material = box_sprite.material.duplicate()
	_shader_mat = box_sprite.material as ShaderMaterial
	_set_outline(false)


# =========================================================================
# INPUT – kliknięcie w Area2D
# =========================================================================

## Obsługuje kliknięcie LPM w obszar pudełka – emituje left_clicked(box).
func _on_area_input(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	var mouse_event := event as InputEventMouseButton
	if mouse_event and mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
		left_clicked.emit(self)


# =========================================================================
# HOVER – włączanie/wyłączanie outline
# =========================================================================

## Reaguje na wejście kursora – włącza outline, jeżeli hover jest włączony i LPM nie jest wciśnięty.
func _on_mouse_entered() -> void:
	if _hover_enabled and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_set_outline(true)


## Reaguje na wyjście kursora – wyłącza outline.
func _on_mouse_exited() -> void:
	_set_outline(false)


## Globalnie reaguje na LPM – każdy klik gasi outline, żeby nie zostawał „przyklejony”.
func _input(event: InputEvent) -> void:
	var mouse_event := event as InputEventMouseButton
	if mouse_event and mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
		_set_outline(false)


# =========================================================================
# STEROWANIE Z LAB – włączanie/wyłączanie hover
# =========================================================================

## Włącza lub wyłącza reakcję na hover dla pudełka.
func set_hover_enabled(enabled: bool) -> void:
	_hover_enabled = enabled
	if not enabled:
		_set_outline(false)


# =========================================================================
# WIZUAL – obsługa parametrów shadera
# =========================================================================

## Ustawia parametry outline w shaderze (highlight / highlight_strength).
func _set_outline(on: bool) -> void:
	if _shader_mat == null:
		return
	_shader_mat.set_shader_parameter("highlight", on)
	_shader_mat.set_shader_parameter("highlight_strength", (1.0 if on else 0.0))
