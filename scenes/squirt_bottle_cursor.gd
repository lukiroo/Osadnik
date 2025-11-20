extends Node2D
class_name SquirtBottleCursor

## Wersja tryskawki przy kursorze
## Kliknięcia mają trafiać w probówki, a nie kolidować z samą butelką.

@export var follow_mouse: bool = false                 # Czy narzędzie ma samodzielnie podążać za kursorem.
@export var cursor_offset: Vector2 = Vector2(8, -40)   # Przesunięcie względem pozycji myszy.
@export var show_z_index: int = 99                     # Z-index po aktywacji (ma być nad stołem).

# Parametry krótkiej animacji „ściśnięcia” przy dolewaniu wody.
@export var squeeze_scale_x: float = 1.06
@export var squeeze_scale_y: float = 0.88
@export var squeeze_in_time: float = 0.07
@export var squeeze_hold_time: float = 0.05
@export var squeeze_out_time: float = 0.10
@export var squeeze_rot_deg: float = 0.0   # Ewentualny niewielki obrót przy ścisku.

var is_active: bool = false
var _squeeze_tween: Tween = null
var _base_pos: Vector2 = Vector2.ZERO      # Pozycja z edytora traktowana jako bazowa.


# =================================================================
# INICJALIZACJA I SPRZĄTANIE
# =================================================================
func _ready() -> void:
	# Kursor działa zawsze (RMB, ESC itp.), ale domyślnie jest schowany.
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	is_active = false
	_base_pos = position

func _exit_tree() -> void:
	# Na wyjściu z drzewa upewniamy się, że tween nie zostanie osierocony.
	if is_instance_valid(_squeeze_tween):
		_squeeze_tween.kill()
	_squeeze_tween = null


# =================================================================
# METODY WYKORZYSTYWANE PRZEZ LAB – POKAŻ / SCHOWAJ
# =================================================================
func show_tool() -> void:
	# Wywoływane przez Lab, gdy użytkownik „bierze butelkę do ręki”.
	is_active = true
	visible = true
	z_index = show_z_index

func hide_tool() -> void:
	# Odkładamy butelkę – wyłączamy widoczność, zatrzymujemy animację i resetujemy transformację.
	is_active = false
	visible = false
	_stop_tween()
	_reset_transform()


# =================================================================
# WEWNĘTRZNE: RESET I OBSŁUGA TWEENÓW
# =================================================================
func _reset_transform() -> void:
	# Przywracamy pozycję/skalę/rotację do stanu domyślnego.
	rotation_degrees = 0.0
	scale = Vector2.ONE
	position = _base_pos

func _stop_tween() -> void:
	# Bezpieczne zatrzymanie ewentualnej animacji squeeze.
	if is_instance_valid(_squeeze_tween):
		_squeeze_tween.kill()
	_squeeze_tween = null


# =================================================================
# FEEDBACK: ANIMACJA „ŚCIŚNIĘCIA” PRZY DOLANIU
# =================================================================
func play_squeeze() -> void:
	# Wywoływane z Lab.gd w momencie faktycznego dolania wody do probówki.
	_stop_tween()
	_squeeze_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	var target_scale := Vector2(squeeze_scale_x, squeeze_scale_y)
	var target_rot := squeeze_rot_deg

	# 1) wejście w ścisk
	_squeeze_tween.tween_property(self, "scale", target_scale, squeeze_in_time)
	if squeeze_rot_deg != 0.0:
		_squeeze_tween.parallel().tween_property(self, "rotation_degrees", target_rot, squeeze_in_time)

	# 2) krótka pauza w „ściśniętej” pozycji
	if squeeze_hold_time > 0.0:
		_squeeze_tween.tween_interval(squeeze_hold_time)

	# 3) powrót do normalnej skali i rotacji
	_squeeze_tween.tween_property(self, "scale", Vector2.ONE, squeeze_out_time)
	if squeeze_rot_deg != 0.0:
		_squeeze_tween.parallel().tween_property(self, "rotation_degrees", 0.0, squeeze_out_time)


# =================================================================
# OPCJONALNE FOLLOW MOUSE
# =================================================================
func _process(_dt: float) -> void:
	# Jeśli follow_mouse = true i narzędzie jest aktywne, pozycję narzędzia wiążemy z kursorem.
	if is_active and follow_mouse:
		global_position = get_global_mouse_position() + cursor_offset
