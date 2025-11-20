extends Node2D

## Pudełko z papierkami wskaźnikowymi leżące na stole.
## Wystawia sygnał kliknięcia oraz prosty efekt podświetlenia przy najechaniu.

signal left_clicked(box: Node)

# --------------------- REFERENCJE DO WĘZŁÓW ---------------------
@onready var hit_area: Area2D = $Area2D
@onready var box_sprite: Sprite2D = $Sprite2D

# --------------------- STAN HOVER / SHADER ---------------------
var _shader_mat: ShaderMaterial = null        ## Lokalna kopia materiału sprita.
var _hover_enabled: bool = true               ## Flaga umożliwiająca wyłączenie reakcji na hover.

# =================================================================
# INIT – przygotowanie materiału i stanu początkowego
# =================================================================
func _ready() -> void:
	## Duplikujemy materiał, żeby ta instancja mogła niezależnie sterować uniformami.
	if box_sprite and box_sprite.material:
		box_sprite.material = box_sprite.material.duplicate()
	_shader_mat = box_sprite.material as ShaderMaterial

	## Na starcie outline jest wyłączony.
	_set_outline(false)

# =================================================================
# INPUT – kliknięcie w Area2D
# =================================================================
func _on_area_input(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	## Kliknięcie LPM w obszar pudełka – Lab decyduje, co zrobić dalej.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		left_clicked.emit(self)

# =================================================================
# HOVER – włączanie/wyłączanie outline
# =================================================================
func _on_mouse_entered() -> void:
	## Podświetlamy pudełko, jeśli hover jest włączony
	## i nie trwa aktualnie przeciąganie (LPM wciśnięty).
	if _hover_enabled and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_set_outline(true)

func _on_mouse_exited() -> void:
	## Po opuszczeniu obszaru przez kursor wyłączamy outline.
	_set_outline(false)

func _input(event: InputEvent) -> void:
	## Każde kliknięcie LPM gasi outline, niezależnie od miejsca kliknięcia.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_set_outline(false)

# =================================================================
# STEROWANIE Z LAB – włączanie/wyłączanie hover
# =================================================================
func set_hover_enabled(enabled: bool) -> void:
	## Proste sterowanie tym, czy pudełko reaguje na hover.
	_hover_enabled = enabled
	if not enabled:
		_set_outline(false)

# =================================================================
# WIZUAL – obsługa parametrów shadera
# =================================================================
func _set_outline(on: bool) -> void:
	if _shader_mat == null:
		return
	_set_shader_param_safe(_shader_mat, "highlight", on)
	_set_shader_param_safe(_shader_mat, "highlight_strength", (1.0 if on else 0.0))

func _set_shader_param_safe(mat: ShaderMaterial, param_name: String, value) -> void:
	## Ustawia uniform tylko wtedy, gdy shader posiada taki parametr.
	if mat == null or mat.shader == null:
		return
	for u in mat.shader.get_shader_uniform_list():
		var info: Dictionary = u
		if String(info.get("name", "")) == param_name:
			mat.set_shader_parameter(param_name, value)
			return
