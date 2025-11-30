extends Node2D
class_name IndicatorPaper

## =========================================================================
## indicator_paper.gd – papierek wskaźnikowy (litmus)
## -------------------------------------------------------------------------
## Odpowiada za:
## - śledzenie kursora (gdy follow_mouse == true),
## - jednokrotne „użycie” na probówce i emisję used_on_probe,
## - ustawienie koloru końcówki na podstawie oceny pH (grade -3..+3),
## - obsługę shadera z uniformem `tip_color` (jeśli jest obecny).
## =========================================================================

signal used_on_probe(probe: Node, grade: int)

# -------------------------- REFERENCJE SCENY ------------------------------

@onready var paper_sprite: Sprite2D = $Paper  ## Główny sprite papierka (z shaderem / teksturą).
@onready var tip_sprite: Sprite2D   = $Tip    ## Sprite końcówki, na którym widać kolor po reakcjach.

# -------------------------- RUCH / ZACHOWANIE -----------------------------

## Czy papierek ma automatycznie śledzić pozycję myszy.
var follow_mouse: bool = true

## Przesunięcie względem kursora, żeby grafika nie zasłaniała wskaźnika myszy.
@export var cursor_offset: Vector2 = Vector2(8, -40)

## Flaga: czy papierek został już użyty (po użyciu blokujemy kolejne pomiary).
var is_spent: bool = false

# -------------------------- SHADER / KOLORY -------------------------------

## Czy shader papierka ma uniform `tip_color` – wtedy ustawiamy kolor także tam.
var _has_tip_uniform: bool = false

## 7 poziomów pH (-3..+3) mapowanych na 7 kolorów.
const COLOR_VERY_STRONG_ACID := Color(0.80, 0.00, 0.00, 0.80)
const COLOR_STRONG_ACID      := Color(0.95, 0.20, 0.00, 0.80)
const COLOR_ACID             := Color(1.00, 0.52, 0.00, 0.80)
const COLOR_NEUTRAL          := Color(0.78, 0.59, 0.07, 0.40)
const COLOR_BASE             := Color(0.15, 0.75, 0.25, 0.80)
const COLOR_STRONG_BASE      := Color(0.00, 0.55, 0.85, 0.80)
const COLOR_VERY_STRONG_BASE := Color(0.25, 0.15, 0.70, 0.80)

const GRADE_COLORS: Array[Color] = [
	COLOR_VERY_STRONG_ACID, # index 0 → grade -3
	COLOR_STRONG_ACID,      # index 1 → grade -2
	COLOR_ACID,             # index 2 → grade -1
	COLOR_NEUTRAL,          # index 3 → grade  0
	COLOR_BASE,             # index 4 → grade +1
	COLOR_STRONG_BASE,      # index 5 → grade +2
	COLOR_VERY_STRONG_BASE  # index 6 → grade +3
]


# =========================================================================
# INICJALIZACJA W SCENIE
# =========================================================================

## Przy starcie:
## - ustawia wysoki z_index, żeby papierek był nad stołem,
## - ukrywa końcówkę do czasu pierwszego „zamoczenia”,
## - sprawdza, czy shader ma uniform `tip_color`,
## - włącza/wyłącza _process w zależności od follow_mouse.
func _ready() -> void:
	z_index = 100

	if tip_sprite:
		tip_sprite.visible = false

	if paper_sprite and paper_sprite.material is ShaderMaterial:
		var shader_material: ShaderMaterial = paper_sprite.material as ShaderMaterial
		if shader_material.shader != null:
			for uniform_info in shader_material.shader.get_shader_uniform_list():
				var uniform_name := String(uniform_info.get("name", ""))
				if uniform_name == "tip_color":
					_has_tip_uniform = true
					break

	set_process(follow_mouse)


## Jeżeli follow_mouse == true, trzyma papierek przy kursorze z zadanym offsetem.
func _process(_delta: float) -> void:
	if follow_mouse:
		global_position = get_global_mouse_position() + cursor_offset


# =========================================================================
# API (Lab → IndicatorPaper)
# =========================================================================

## Używa papierek na konkretnej probówce:
## - ustawia kolor dla podanego grade,
## - oznacza papierek jako zużyty,
## - emituje used_on_probe, żeby Lab mógł zapisać wynik.
func use_on_probe(probe: Node, grade: int) -> void:
	if is_spent:
		return

	set_grade(grade)
	is_spent = true
	used_on_probe.emit(probe, grade)


## Ustawia kolor końcówki papierka w zależności od grade (-3..+3).
func set_grade(grade: int) -> void:
	var tip_color: Color = _grade_to_color(grade)
	_apply_tip_color(tip_color)
	_show_tip()


## Włącza albo wyłącza tryb „przyklejony do kursora”.
func set_follow_mouse(enabled: bool) -> void:
	follow_mouse = enabled
	set_process(enabled)


## Pozwala z zewnątrz zmienić przesunięcie względem kursora.
func set_cursor_offset(offset: Vector2) -> void:
	cursor_offset = offset


# =========================================================================
# WEWNĘTRZNE FUNKCJE POMOCNICZE (tip / kolory)
# =========================================================================

## Ujawnia końcówkę papierka, jeśli była wcześniej ukryta.
func _show_tip() -> void:
	if tip_sprite:
		tip_sprite.visible = true


## Mapuje grade [-3..+3] na kolor z tablicy GRADE_COLORS.
func _grade_to_color(grade: int) -> Color:
	var clamped_grade: int = clampi(grade, -3, 3)
	return GRADE_COLORS[clamped_grade + 3]


## Ustawia kolor końcówki:
## - przez uniform `tip_color` w shaderze (jeśli istnieje),
## - oraz przez modulate na tip_sprite.
func _apply_tip_color(tip_color: Color) -> void:
	if _has_tip_uniform and paper_sprite and paper_sprite.material is ShaderMaterial:
		var shader_material: ShaderMaterial = paper_sprite.material as ShaderMaterial
		shader_material.set_shader_parameter("tip_color", tip_color)

	if tip_sprite:
		tip_sprite.modulate = tip_color
