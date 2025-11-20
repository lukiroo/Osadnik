extends Node2D
class_name DropperFillDot

## Mała kula pokazująca aktualny poziom napełnienia droppera (zakres 0..1).
## Poziom jest przekazywany do shadera przez uniform `level01`.

# -------------------- WĘZŁY DZIECI --------------------
@onready var outline_sprite: Sprite2D = $Circle      # obrys – pojawia się dopiero przy sensownym napełnieniu
@onready var fill_sprite: Sprite2D    = $CircleFill  # wypełnienie – materiał ze sterowaniem przez uniform `level01`

# -------------------- STAN ---------------------------
var _fill01: float = 0.0       # aktualny ułamek napełnienia (0.0 = pusto, 1.0 = pełny)
var _has_level01: bool = false # czy shader w ogóle wystawia uniform o nazwie "level01"

@export var outline_threshold: float = 0.001  # poniżej tej wartości obrys jest ukrywany, żeby nie mrugał przy 0.0


# =================================================================
# INICJALIZACJA W SCENIE
# =================================================================
func _ready() -> void:
	# Duplikujemy materiał wypełnienia, żeby każda instancja miała własne uniformy.
	if fill_sprite and fill_sprite.material:
		fill_sprite.material = fill_sprite.material.duplicate()
		var sm := fill_sprite.material as ShaderMaterial
		if sm and sm.shader:
			for u in sm.shader.get_shader_uniform_list():
				if String(u.get("name", "")) == "level01":
					_has_level01 = true
					break

	# Ustawiamy grafikę dla stanu początkowego (0.0).
	_apply_visuals()


# =================================================================
# METODY WYWOŁYWANE Z ZEWNĄTRZ
# =================================================================
func set_fill01(value: float) -> void:
	# Ustawia poziom napełnienia (zabezpieczamy się clampem do 0..1) i odświeża widok.
	_fill01 = clamp(value, 0.0, 1.0)
	_apply_visuals()

func get_fill01() -> float:
	# Zwraca bieżący poziom napełnienia (0..1), przydatne np. do debugowania.
	return _fill01

func reset() -> void:
	# Resetuje stan do pustego droppera.
	_fill01 = 0.0
	_apply_visuals()


# =================================================================
# AKTUALIZACJA WYGLĄDU
# =================================================================
func _apply_visuals() -> void:
	# 1) Wypełnienie – jeśli shader wspiera uniform `level01`, przekazujemy tam ułamek napełnienia.
	if fill_sprite and _has_level01:
		var sm := fill_sprite.material as ShaderMaterial
		if sm and sm.shader:
			sm.set_shader_parameter("level01", _fill01)

	# 2) Obrys – pokazujemy tylko powyżej progu, żeby pusta kropka nie „świeciła”.
	if outline_sprite:
		outline_sprite.visible = (_fill01 > outline_threshold)
