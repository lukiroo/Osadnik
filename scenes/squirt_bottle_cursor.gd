extends Node2D
class_name SquirtBottleCursor

## =========================================================================
## squirt_bottle_cursor.gd – tryskawka przy kursorze
## -------------------------------------------------------------------------
## Odpowiada za:
## - wyświetlanie butelki z wodą przy kursorze (follow_mouse + offset),
## - animację „ściśnięcia” przy dolewaniu wody,
## =========================================================================

# -------------------- USTAWIENIA OGÓLNE --------------------

@export var follow_mouse: bool = false                 ## Czy butelka ma sama podążać za kursorem.
@export var cursor_offset: Vector2 = Vector2(8, -40)   ## Przesunięcie względem pozycji myszy.
@export var show_z_index: int = 99                     ## Z-index, gdy narzędzie jest aktywne.

## Parametry animacji „ściśnięcia” przy dolewaniu wody.
@export var squeeze_scale_x: float = 1.06
@export var squeeze_scale_y: float = 0.88
@export var squeeze_in_time: float = 0.07
@export var squeeze_hold_time: float = 0.05
@export var squeeze_out_time: float = 0.10
@export var squeeze_rot_deg: float = 0.0   ## Ewentualny niewielki obrót przy ścisku.

# -------------------- STAN WEWNĘTRZNY --------------------

var is_active: bool = false
var _squeeze_tween: Tween = null
var _base_pos: Vector2 = Vector2.ZERO      ## Pozycja z edytora traktowana jako bazowa.


# =========================================================================
# INICJALIZACJA I SPRZĄTANIE
# =========================================================================

## Przygotowuje kursor butelki:
## - ustawia process_mode na ALWAYS,
## - chowa sprite i resetuje flagi.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	is_active = false
	_base_pos = position


## Sprząta tweena po wyjściu z drzewa.
func _exit_tree() -> void:
	if is_instance_valid(_squeeze_tween):
		_squeeze_tween.kill()
	_squeeze_tween = null


# =========================================================================
# POKAZANIE / SCHOWANIE
# =========================================================================

## Włącza butelkę przy kursorze:
## - ustawia is_active, widoczność i z_index.
func show_tool() -> void:
	is_active = true
	visible = true
	z_index = show_z_index


## Chowa butelkę, zatrzymuje animację i resetuje transformację.
func hide_tool() -> void:
	is_active = false
	visible = false
	_stop_tween()
	_reset_transform()


# =========================================================================
# WEWNĘTRZNE: RESET I OBSŁUGA TWEENÓW
# =========================================================================

## Przywraca transformację (pozycja, skala, rotacja) do stanu bazowego.
func _reset_transform() -> void:
	rotation_degrees = 0.0
	scale = Vector2.ONE
	position = _base_pos


## Zatrzymuje ewentualną animację „ściśnięcia”.
func _stop_tween() -> void:
	if is_instance_valid(_squeeze_tween):
		_squeeze_tween.kill()
	_squeeze_tween = null


# =========================================================================
# FEEDBACK – ANIMACJA „ŚCIŚNIĘCIA” PRZY DOLANIU
# =========================================================================

## Odtwarza animację „ściśnięcia”:
## - lekko spłaszcza sprite, opcjonalnie dodaje rotację,
## - krótką chwilę trzyma ścisk,
## - wraca do normalnych wartości.
func play_squeeze() -> void:
	_stop_tween()
	_squeeze_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	var squashed_scale := Vector2(squeeze_scale_x, squeeze_scale_y)
	var target_rot: float = squeeze_rot_deg

	# 1) wejście w ścisk
	_squeeze_tween.tween_property(self, "scale", squashed_scale, squeeze_in_time)
	if squeeze_rot_deg != 0.0:
		_squeeze_tween.parallel().tween_property(self, "rotation_degrees", target_rot, squeeze_in_time)

	# 2) krótka pauza w „ściśniętej” pozycji
	if squeeze_hold_time > 0.0:
		_squeeze_tween.tween_interval(squeeze_hold_time)

	# 3) powrót do normalnej skali i rotacji
	_squeeze_tween.tween_property(self, "scale", Vector2.ONE, squeeze_out_time)
	if squeeze_rot_deg != 0.0:
		_squeeze_tween.parallel().tween_property(self, "rotation_degrees", 0.0, squeeze_out_time)


# =========================================================================
# OPCJONALNE ŚLEDZENIE MYSZY
# =========================================================================

## Jeśli follow_mouse == true i narzędzie jest aktywne,
## utrzymuje butelkę przy kursorze z zadanym offsetem.
func _process(_delta: float) -> void:
	if is_active and follow_mouse:
		global_position = get_global_mouse_position() + cursor_offset
