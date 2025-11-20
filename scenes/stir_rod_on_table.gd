extends Node2D
class_name StirRodOnTable

## Bagietka laboratoryjna leżąca na stole.
## Podświetla się przy najechaniu kursorem i emituje sygnał po kliknięciu LPM.

signal left_clicked(rod: Node)

# -------------------- REFERENCJE DO WĘZŁÓW --------------------
@onready var hit_area: Area2D = $Area2D
@onready var rod_sprite: Sprite2D = $Sprite2D

# -------------------- STAN HOVER / SHADER --------------------
var _shader_mat: ShaderMaterial = null        ## Kopia materiału sprita przypisana do tej instancji.
var _hover_enabled: bool = true               ## Flaga umożliwiająca wyłączenie hoveru z kodu Lab.gd.

# =================================================================
# INIT – przygotowanie materiału i stanu początkowego
# =================================================================
func _ready() -> void:
	## Duplikacja materiału sprita – uniformy nie będą współdzielone z innymi obiektami.
	if rod_sprite and rod_sprite.material:
		rod_sprite.material = rod_sprite.material.duplicate()
	_shader_mat = rod_sprite.material as ShaderMaterial

	## Na starcie bagietka jest bez podświetlenia.
	_set_outline(false)

# =================================================================
# INPUT – obsługa kliknięć w Area2D
# =================================================================
func _on_area_input(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	## Kliknięcie LPM w obszar bagietki – Lab może na tej podstawie podnieść narzędzie.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		left_clicked.emit(self)

# =================================================================
# HOVER – podświetlenie przy najechaniu
# =================================================================
func _on_mouse_entered() -> void:
	## Włączamy outline tylko gdy hover jest aktywny
	## i nie trwa aktualnie przeciąganie (LPM wciśnięty).
	if _hover_enabled and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_set_outline(true)

func _on_mouse_exited() -> void:
	## Po zejściu kursora z obszaru bagietki wyłączamy podświetlenie.
	_set_outline(false)

# =================================================================
# STEROWANIE Z LAB – włączanie/wyłączanie reakcji na hover
# =================================================================
func set_hover_enabled(enabled: bool) -> void:
	## Umożliwia sterowanie podświetleniem z Lab (np. wyłączenie hoveru w innych trybach).
	_hover_enabled = enabled
	if not enabled:
		_set_outline(false)

# =================================================================
# WIZUAL – obsługa shadera
# =================================================================
func _set_outline(on: bool) -> void:
	if _shader_mat == null:
		return
	_set_shader_param_safe(_shader_mat, "highlight", on)
	_set_shader_param_safe(_shader_mat, "highlight_strength", (1.0 if on else 0.0))

func _set_shader_param_safe(mat: ShaderMaterial, param_name: String, value) -> void:
	## Helper: ustawia parametr shadera tylko wtedy, gdy shader go posiada.
	if mat == null or mat.shader == null:
		return
	for u in mat.shader.get_shader_uniform_list():
		var info: Dictionary = u
		if String(info.get("name", "")) == param_name:
			mat.set_shader_parameter(param_name, value)
			return
