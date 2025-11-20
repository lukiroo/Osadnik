extends Node2D
class_name SquirtBottleOnTable

## Tryskawka z wodą leżąca na stole.
## Służy jako źródło sygnału kliknięcia; właściwe dolewanie obsługuje Lab.gd.

signal left_clicked(bottle: Node)

# -------------------- REFERENCJE DO WĘZŁÓW --------------------
@onready var hit_area: Area2D = $Area2D
@onready var bottle_sprite: Sprite2D = $Sprite2D

# -------------------- STAN HOVER / SHADER --------------------
var _shader_mat: ShaderMaterial = null        ## Lokalna kopia materiału sprita.
var _hover_enabled: bool = true               ## Czy aktualnie reagujemy na hover (sterowane z Lab).

# =================================================================
# INIT – konfiguracja materiału i stanu początkowego
# =================================================================
func _ready() -> void:
	## Duplikujemy materiał i wyłączamy outline na starcie.
	if bottle_sprite and bottle_sprite.material:
		bottle_sprite.material = bottle_sprite.material.duplicate()
	_shader_mat = bottle_sprite.material as ShaderMaterial

	_set_outline(false)

# =================================================================
# INPUT – kliknięcie w Area2D
# =================================================================
func _on_area_input(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	## Kliknięcie LPM w obrys butelki.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		left_clicked.emit(self)

# =================================================================
# HOVER – wejście/wyjście kursora
# =================================================================
func _on_mouse_entered() -> void:
	## Włączamy podświetlenie tylko jeśli hover jest aktywny
	## i nie klikamy jednocześnie LPM.
	if _hover_enabled and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_set_outline(true)

func _on_mouse_exited() -> void:
	## Wyłączenie outline po opuszczeniu obszaru sprita.
	_set_outline(false)

# =================================================================
# STEROWANIE Z LAB – włączanie/wyłączanie hover
# =================================================================
func set_hover_enabled(enabled: bool) -> void:
	## Pozwala globalnie wyłączyć hover (np. gdy butelka jest „w ręce” użytkownika).
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
	## Bezpieczne ustawianie uniformu w shaderze.
	if mat == null or mat.shader == null:
		return
	for u in mat.shader.get_shader_uniform_list():
		var info: Dictionary = u
		if String(info.get("name", "")) == param_name:
			mat.set_shader_parameter(param_name, value)
			return
