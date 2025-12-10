extends Node2D
class_name PlatinRodOnTable

## =========================================================================
## platin_rod_cursor.gd – drucik platynowy przy kursorze
## -------------------------------------------------------------------------
## Odpowiada za:
## - wyświetlanie drucika przy kursorze (follow_mouse + offset),
## - prostą animację obrotu po pobraniu próbki z probówki,
## - przechowywanie informacji o tym, czy drucik ma „próbkę” (Mixture),
## - proste API show_tool / hide_tool używane przez Lab.
## =========================================================================

signal left_clicked(rod: Node)

# -------------------- REFERENCJE DO WĘZŁÓW --------------------

@onready var hit_area: Area2D = $Area2D
@onready var rod_sprite: Sprite2D = $Sprite2D

# -------------------- STAN HOVER / SHADER --------------------

var _shader_mat: ShaderMaterial = null        ## Kopia materiału sprita przypisana do tej instancji.
var _hover_enabled: bool = true               ## Flaga umożliwiająca wyłączenie hoveru z Lab.gd.


# =========================================================================
# INICJALIZACJA – przygotowanie materiału i stanu początkowego
# =========================================================================

## Przygotowuje drucik po starcie:
## - wyłącza outline na starcie.
func _ready() -> void:
	_shader_mat = rod_sprite.material as ShaderMaterial
	_set_outline(false)


# =========================================================================
# INPUT – obsługa kliknięć w Area2D
# =========================================================================

## Obsługuje kliknięcie LPM w obszar drucika – emituje left_clicked(rod).
func _on_area_input(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	var mouse_event := event as InputEventMouseButton
	if mouse_event and mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
		left_clicked.emit(self)


# =========================================================================
# HOVER – podświetlenie przy najechaniu
# =========================================================================

## Reaguje na wejście kursora – włącza outline, gdy hover jest aktywny i LPM nie jest wciśnięty.
func _on_mouse_entered() -> void:
	if _hover_enabled and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_set_outline(true)


## Reaguje na wyjście kursora – wyłącza outline.
func _on_mouse_exited() -> void:
	_set_outline(false)


## Gasi outline przy każdym kliknięciu LPM – zapobiega „zaczepieniu” efektu przy dragowaniu.
func _input(event: InputEvent) -> void:
	var mouse_event := event as InputEventMouseButton
	if mouse_event and mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
		_set_outline(false)


# =========================================================================
# STEROWANIE Z LAB – włączanie/wyłączanie reakcji na hover
# =========================================================================

## Steruje podświetleniem drucika z poziomu Lab (np. wyłączenie w innych trybach).
func set_hover_enabled(enabled: bool) -> void:
	_hover_enabled = enabled
	if not enabled:
		_set_outline(false)


# =========================================================================
# WIZUAL – obsługa shadera
# =========================================================================

## Ustawia parametry outline (highlight / highlight_strength) w shaderze sprita.
func _set_outline(on: bool) -> void:
	if _shader_mat == null:
		return
	_shader_mat.set_shader_parameter("highlight", on)
	_shader_mat.set_shader_parameter("highlight_strength", (1.0 if on else 0.0))
