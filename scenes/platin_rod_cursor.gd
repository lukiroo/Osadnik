extends Node2D
class_name PlatinRodCursor

## =========================================================================
## platin_rod_cursor.gd – drucik platynowy przy kursorze
## -------------------------------------------------------------------------
## Odpowiada za:
## - wyświetlanie drucika przy kursorze,
## - animację obrotu po pobraniu próbki z probówki,
## - przechowywanie informacji o tym, czy drucik ma próbkę,
## =========================================================================

# -------------------- USTAWIENIA OGÓLNE --------------------

@export var follow_mouse: bool = false                 ## Czy drucik ma sam podążać za kursorem.
@export var cursor_offset: Vector2 = Vector2(6, -20)   ## Przesunięcie względem pozycji myszy.
@export var show_z_index: int = 99                     ## Z-index, gdy narzędzie jest aktywne.

## Parametry animacji obrotu przy pobraniu próbki.
@export var sample_rot_deg: float = 45.0        ## Kąt wychylenia przy pobieraniu próbki.
@export var sample_rot_time: float = 0.4       ## Czas obrotu od 0° do sample_rot_deg.


# -------------------- STAN WEWNĘTRZNY --------------------

var is_active: bool = false            ## Czy drucik jest aktualnie „w ręku”.
var has_sample: bool = false           ## Czy drucik ma na sobie pobraną próbkę.
var sample_mix: Mixture = null         ## Skopiowana próbka mieszaniny (np. do próby płomieniowej).

var _rotate_tween: Tween = null
var _base_pos: Vector2 = Vector2.ZERO  ## Pozycja z edytora traktowana jako pozycja bazowa.


# =========================================================================
# INICJALIZACJA I SPRZĄTANIE
# =========================================================================

## Przygotowuje kursor drucika:
## - ustawia process_mode na ALWAYS,
## - chowa sprite i resetuje stan.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	is_active = false
	has_sample = false
	sample_mix = null
	_base_pos = position


## Sprząta ewentualny tween przy wyjściu z drzewa.
func _exit_tree() -> void:
	_stop_tween()


# =========================================================================
# POKAZANIE / SCHOWANIE
# =========================================================================

## Włącza drucik przy kursorze:
## - oznacza go jako aktywny,
## - ustawia widoczność i z_index.
func show_tool() -> void:
	is_active = true
	visible = true
	z_index = show_z_index


## Odkłada drucik:
## - wyłącza widoczność,
## - czyści pobraną próbkę,
## - resetuje transformację i zatrzymuje animację.
func hide_tool() -> void:
	is_active = false
	visible = false
	has_sample = false
	sample_mix = null
	_stop_tween()
	_reset_transform()


# =========================================================================
# STAN PRÓBKI
# =========================================================================

## Ustawia próbkę mieszaniny na druciku (kopię, żeby nie bawić się referencjami).
func set_sample(sample: Mixture) -> void:
	if sample == null:
		has_sample = false
		sample_mix = null
		return

	sample_mix = sample.clone()
	has_sample = true


## Czyści próbkę z drucika.
func clear_sample() -> void:
	has_sample = false
	sample_mix = null


# =========================================================================
# WEWNĘTRZNE: RESET I OBSŁUGA TWEENÓW
# =========================================================================

## Przywraca pozycję, skalę i rotację do stanu bazowego.
func _reset_transform() -> void:
	rotation_degrees = 0.0
	scale = Vector2.ONE
	position = _base_pos


## Zatrzymuje ewentualną animację obrotu.
func _stop_tween() -> void:
	if is_instance_valid(_rotate_tween):
		_rotate_tween.kill()
	_rotate_tween = null


# =========================================================================
# OBRÓT PRZY POBRANIU I SPALENIU PRÓBKI
# =========================================================================

## Odtwarza prostą animację obrotu:
## - wychyla drucik z 0° do sample_rot_deg i zostawia go w tej pozycji
func play_sample_rotation() -> void:
	_stop_tween()
	rotation_degrees = 0.0
	_rotate_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_rotate_tween.tween_property(self, "rotation_degrees", sample_rot_deg, sample_rot_time)


## Płynny powrót drucika do pozycji bazowej po spaleniu próbki.
func tween_back_to_base() -> void:
	_stop_tween()
	_rotate_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_rotate_tween.tween_property(self, "rotation_degrees", 0.0, sample_rot_time)


# =========================================================================
# OPCJONALNE ŚLEDZENIE MYSZY
# =========================================================================

## Jeśli follow_mouse == true i narzędzie jest aktywne,
## utrzymuje drucik przy kursorze z zadanym offsetem.
func _process(_delta: float) -> void:
	if is_active and follow_mouse:
		global_position = get_global_mouse_position() + cursor_offset
