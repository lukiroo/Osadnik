extends Node2D
class_name IndicatorPaper

## Papierek wskaźnikowy (litmus).
## - Tworzony dynamicznie z PackedScene przez Lab.
## - Może podążać za kursorem (follow_mouse).
## - Po użyciu na probówce zmienia kolor końcówki na podstawie „oceny pH” (grade -3..+3).
## - Emityje sygnał used_on_probe, dzięki czemu Lab wie, że ten egzemplarz został zużyty.

signal used_on_probe(probe: Node, grade: int)

# --------------------- REFERENCJE DO WĘZŁÓW ---------------------
@onready var paper_sprite: Sprite2D = $Paper  ## Główny sprite, zwykle z shaderem.
@onready var tip_sprite: Sprite2D   = $Tip    ## Końcówka papierka, na niej widać kolor.

# --------------------- KONFIGURACJA RUCHU -----------------------
@export var follow_mouse: bool = true                  ## Czy papierek ma automatycznie śledzić kursor.
@export var cursor_offset: Vector2 = Vector2(8, -40)   ## Przesunięcie względem pozycji myszy, żeby nie zasłaniać kursora.

var is_spent: bool = false                             ## Flaga „zużyty” – po użyciu blokujemy kolejne oznaczenia.

# --------------------- SHADER / KOLORY --------------------------
var _has_tip_uniform: bool = false                     ## Czy shader ma uniform „tip_color”.

# 7 poziomów pH (-3..+3) mapujemy na 7 kolorów.
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


# =================================================================
# INICJALIZACJA W SCENIE
# =================================================================
func _ready() -> void:
	## Przy starcie:
	## - ustawiamy wysoki z_index, żeby papierek był nad stołem,
	## - ukrywamy końcówkę do czasu pierwszego „zamoczenia”,
	## - sprawdzamy, czy shader udostępnia uniform `tip_color`,
	## - włączamy albo wyłączamy _process w zależności od follow_mouse.
	z_index = 100

	if tip_sprite:
		tip_sprite.visible = false

	if paper_sprite and paper_sprite.material is ShaderMaterial:
		var sm := paper_sprite.material as ShaderMaterial
		if sm.shader != null:
			for u in sm.shader.get_shader_uniform_list():
				if String(u.get("name", "")) == "tip_color":
					_has_tip_uniform = true
					break

	set_process(follow_mouse)


func _process(_delta: float) -> void:
	## Jeżeli flaga follow_mouse jest włączona, papierek trzyma się pozycji kursora
	## z zadanym offsetem, dzięki czemu jest czytelny wizualnie.
	if follow_mouse:
		global_position = get_global_mouse_position() + cursor_offset


# =================================================================
# METODY WYWOŁYWANE Z LAB.GD
# =================================================================
func use_on_probe(probe: Node, grade: int) -> void:
	## Główne wywołanie z Lab:
	## - wyliczamy kolor na podstawie grade,
	## - oznaczamy papierek jako zużyty,
	## - emitujemy sygnał, żeby Lab mógł zareagować (np. zapisać wynik).
	if is_spent:
		return

	set_grade(grade)
	is_spent = true
	used_on_probe.emit(probe, grade)


func set_grade(grade: int) -> void:
	## Ustawia kolor końcówki papierka w zależności od grade (-3..+3)
	var col := _grade_to_color(grade)
	_apply_tip_color(col)
	_show_tip()


func set_follow_mouse(enabled: bool) -> void:
	## Włącza/wyłącza tryb „przyklejony do kursora”.
	follow_mouse = enabled
	set_process(enabled)


func set_cursor_offset(offset: Vector2) -> void:
	## Pozwala z zewnątrz dostroić przesunięcie względem kursora.
	cursor_offset = offset


# =================================================================
# WEWNĘTRZNE FUNKCJE POMOCNICZE (kolor, tip)
# =================================================================
func _show_tip() -> void:
	## Ujawnia końcówkę, jeśli wcześniej była schowana.
	if tip_sprite:
		tip_sprite.visible = true


func _grade_to_color(grade: int) -> Color:
	## Mapowanie zakresu [-3..+3] na indeks tablicy GRADE_COLORS.
	var clamped: int = clampi(grade, -3, 3)
	return GRADE_COLORS[clamped + 3]


func _apply_tip_color(color: Color) -> void:
	## Ustawienie koloru:
	## 1) próbujemy przez uniform `tip_color` w shaderze (jeśli istnieje),
	## 2) dodatkowo ustawiamy modulate na sprite końcówki.
	if _has_tip_uniform and paper_sprite and paper_sprite.material is ShaderMaterial:
		var sm := paper_sprite.material as ShaderMaterial
		sm.set_shader_parameter("tip_color", color)

	if tip_sprite:
		tip_sprite.modulate = color
