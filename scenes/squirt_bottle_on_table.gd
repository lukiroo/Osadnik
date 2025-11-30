extends Node2D
class_name SquirtBottleOnTable

## =========================================================================
## squirt_bottle_on_table.gd – butelka z wodą na stole
## -------------------------------------------------------------------------
## Odpowiada za:
## - emitowanie sygnału left_clicked po kliknięciu LPM,
## - podświetlenie przy najechaniu kursorem,
## - duplikację materiału, żeby highlight był per instancja.
## =========================================================================

signal left_clicked(bottle: Node)

# -------------------- REFERENCJE DO WĘZŁÓW --------------------

@onready var hit_area: Area2D = $Area2D
@onready var bottle_sprite: Sprite2D = $Sprite2D

# -------------------- STAN HOVER / SHADER --------------------

var _shader_mat: ShaderMaterial = null        ## Lokalna kopia materiału sprita.
var _hover_enabled: bool = true               ## Czy aktualnie reagujemy na hover (sterowane z Lab).


# =========================================================================
# INIT – konfiguracja materiału i stanu początkowego
# =========================================================================

## Przygotowuje butelkę:
## - duplikuje materiał sprita,
## - wyłącza outline na starcie.
func _ready() -> void:
	if bottle_sprite and bottle_sprite.material:
		bottle_sprite.material = bottle_sprite.material.duplicate()
	_shader_mat = bottle_sprite.material as ShaderMaterial

	_set_outline(false)


# =========================================================================
# INPUT – kliknięcie w Area2D
# =========================================================================

## Obsługuje kliknięcie LPM w obrys butelki – emituje left_clicked(bottle).
func _on_area_input(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		left_clicked.emit(self)


# =========================================================================
# HOVER – wejście/wyjście kursora
# =========================================================================

## Reaguje na wejście kursora – włącza outline, gdy hover jest aktywny i LPM nie jest wciśnięty.
func _on_mouse_entered() -> void:
	if _hover_enabled and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_set_outline(true)


## Reaguje na wyjście kursora – wyłącza outline.
func _on_mouse_exited() -> void:
	_set_outline(false)


# =========================================================================
# STEROWANIE Z LAB – włączanie/wyłączanie hover
# =========================================================================

## Włącza lub wyłącza reakcję na hover dla butelki (np. gdy jest „w ręce”).
func set_hover_enabled(enabled: bool) -> void:
	_hover_enabled = enabled
	if not enabled:
		_set_outline(false)


# =========================================================================
# WIZUAL – obsługa shadera
# =========================================================================

## Ustawia parametry outline w shaderze (highlight / highlight_strength).
func _set_outline(on: bool) -> void:
	if _shader_mat == null:
		return
	_set_shader_param_safe(_shader_mat, "highlight", on)
	_set_shader_param_safe(_shader_mat, "highlight_strength", (1.0 if on else 0.0))


## Ustawia uniform w shaderze tylko, jeśli shader posiada dany parametr.
func _set_shader_param_safe(mat: ShaderMaterial, param_name: String, value) -> void:
	if mat == null or mat.shader == null:
		return
	for u in mat.shader.get_shader_uniform_list():
		var info: Dictionary = u
		if String(info.get("name", "")) == param_name:
			mat.set_shader_parameter(param_name, value)
			return
