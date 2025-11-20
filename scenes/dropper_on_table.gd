extends Node2D
class_name DropperOnTable

## Pipeta leżąca na stole.
## Scena emituje sygnał po kliknięciu, a dalsza logika jest obsługiwana w Lab.gd.

signal left_clicked(dropper: Node)

# -------------------- REFERENCJE DO WĘZŁÓW --------------------
@onready var hit_area: Area2D = $Area2D
@onready var dropper_sprite: Sprite2D = $Sprite2D

# -------------------- STAN HOVER / SHADER --------------------
var _shader_mat: ShaderMaterial = null        ## Skopiowany materiał sprita (osobny dla tej instancji).
var _hover_enabled: bool = true               ## Możliwość czasowego wyłączenia podświetlenia z Lab.gd.

# =================================================================
# INIT – konfiguracja materiału i stanu początkowego
# =================================================================
func _ready() -> void:
	## Przygotowanie materiału: duplikujemy go, żeby uniformy nie były współdzielone.
	if dropper_sprite and dropper_sprite.material:
		dropper_sprite.material = dropper_sprite.material.duplicate()
	_shader_mat = dropper_sprite.material as ShaderMaterial

	## Na starcie pipeta jest bez podświetlenia.
	_set_outline(false)

# =================================================================
# INPUT – kliknięcie w Area2D
# =================================================================
func _on_area_input(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	## Kliknięcie LPM bezpośrednio w obszar pipety.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		left_clicked.emit(self)

# =================================================================
# HOVER – reakcja na wejście/wyjście kursora
# =================================================================
func _on_mouse_entered() -> void:
	## Podświetlenie aktywne tylko gdy hover jest włączony
	## i użytkownik nie trzyma wciśniętego LPM (żeby nie mrugało przy dragowaniu).
	if _hover_enabled and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_set_outline(true)

func _on_mouse_exited() -> void:
	## Po wyjściu kursora z obszaru wyłączamy podświetlenie.
	_set_outline(false)

func _input(event: InputEvent) -> void:
	## Każdy klik LPM (niezależnie od miejsca) wyłącza outline – zapobiega „zaczepieniu” efektu.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_set_outline(false)

# =================================================================
# STEROWANIE Z LAB – włączanie/wyłączanie hover
# =================================================================
func set_hover_enabled(enabled: bool) -> void:
	## Umożliwia globalne wyłączenie hoveru (np. kiedy pipeta jest „w ręce” w innym trybie).
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
	## Bezpieczne ustawianie uniformu – tylko jeśli shader faktycznie definiuje dany parametr.
	if mat == null or mat.shader == null:
		return
	for u in mat.shader.get_shader_uniform_list():
		var info: Dictionary = u
		if String(info.get("name", "")) == param_name:
			mat.set_shader_parameter(param_name, value)
			return
