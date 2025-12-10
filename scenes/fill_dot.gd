extends Node2D
class_name DropperFillDot

## =========================================================================
## dropper_fill_dot.gd – wskaźnik napełnienia droppera
## -------------------------------------------------------------------------
## Odpowiada za:
## - pokazywanie aktualnego poziomu napełnienia droppera (0.0–1.0),
## - przekazywanie wartości do shadera przez uniform `level01`,
## - ukrywanie obrysu, gdy dropper jest praktycznie pusty.
## =========================================================================

# -------------------- WĘZŁY DZIECI --------------------

@onready var outline_sprite: Sprite2D = $Circle      ## Obrys – widoczny dopiero przy sensownym napełnieniu.
@onready var fill_sprite: Sprite2D    = $CircleFill  ## Wypełnienie – sterowane uniformem `level01` w shaderze.


# -------------------- STAN WEWNĘTRZNY --------------------

## Aktualny ułamek napełnienia (0.0 = pusto, 1.0 = pełny).
var _fill01: float = 0.0

## Informuje, czy shader w ogóle ma uniform o nazwie "level01".
var _has_level01: bool = false

@export var outline_threshold: float = 0.001  ## Poniżej tej wartości obrys jest ukrywany (żeby nie mrugał przy 0.0).


# =========================================================================
# INICJALIZACJA
# =========================================================================

## Przygotowuje wskaźnik po starcie:
## - sprawdza, czy shader wystawia uniform `level01`,
## - nakłada stan początkowy (0.0).
func _ready() -> void:
	if fill_sprite and fill_sprite.material is ShaderMaterial:
		var shader_material: ShaderMaterial = fill_sprite.material as ShaderMaterial
		if shader_material.shader:
			for uniform: Dictionary in shader_material.shader.get_shader_uniform_list():
				if String(uniform.get("name", "")) == "level01":
					_has_level01 = true
					break

	_apply_visuals()


# =========================================================================
# METODY WYWOŁYWANE Z ZEWNĄTRZ
# =========================================================================

## Ustawia poziom napełnienia (0..1) i odświeża widok.
func set_fill01(value: float) -> void:
	_fill01 = clamp(value, 0.0, 1.0)
	_apply_visuals()


## Zwraca bieżący poziom napełnienia (0..1).
func get_fill01() -> float:
	return _fill01


## Resetuje wskaźnik do stanu pustego droppera.
func reset() -> void:
	_fill01 = 0.0
	_apply_visuals()


# =========================================================================
# AKTUALIZACJA WYGLĄDU
# =========================================================================

## Aktualizuje wygląd wskaźnika:
## - ustawia uniform `level01` w shaderze wypełnienia,
## - pokazuje/ukrywa obrys w zależności od progu outline_threshold.
func _apply_visuals() -> void:
	# Wypełnienie – jeżeli shader wspiera uniform `level01`, przekazujemy mu ułamek napełnienia.
	if _has_level01 and fill_sprite and fill_sprite.material is ShaderMaterial:
		var shader_material: ShaderMaterial = fill_sprite.material as ShaderMaterial
		if shader_material:
			shader_material.set_shader_parameter("level01", _fill01)

	# Obrys – widoczny tylko powyżej progu, żeby pusta kropka nie „świeciła”.
	if outline_sprite:
		outline_sprite.visible = _fill01 > outline_threshold
