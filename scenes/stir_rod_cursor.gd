extends Node2D
class_name StirRodCursor

## =========================================================================
## stir_rod_cursor.gd – bagietka przy kursorze
## -------------------------------------------------------------------------
## Odpowiada za:
## - pokazywanie bagietki przy kursorze (follow_mouse),
## - krótką animację „bujnięcia” po mieszaniu (feedback),
## - emisję sygnału cancel_requested (RMB / ESC) do Lab.
## =========================================================================

signal cancel_requested()   ## Lab nasłuchuje, żeby odłożyć bagietkę (RMB / ESC).

# -------------------- USTAWIENIA OGÓLNE --------------------

@export var follow_mouse: bool = false  ## Jeśli true – bagietka śledzi myszkę w _process.
@export var show_z_index: int = 99      ## Z-index, gdy bagietka jest aktywna.

## Proste parametry animacji „bujnięcia” po mieszaniu.
@export var wobble_angle_deg: float = 10.0
@export var wobble_time: float = 0.18
@export var wobble_damping: float = 0.6
@export var wobble_scale_boost: float = 0.04

# -------------------- STAN WEWNĘTRZNY --------------------

var is_active: bool = false
var _wobble_tween: Tween = null
var _base_pos: Vector2 = Vector2.ZERO   ## Pozycja z edytora traktowana jako bazowa.


# =========================================================================
# INICJALIZACJA I SPRZĄTANIE
# =========================================================================

## Przygotowuje bagietkę-kursor:
## - ustawia process_mode na ALWAYS (żeby reagować na RMB/ESC),
## - chowa sprite i resetuje flagi.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	is_active = false
	_base_pos = position


## Sprząta tweena po wyjściu z drzewa, żeby nie został „sierotą”.
func _exit_tree() -> void:
	if is_instance_valid(_wobble_tween):
		_wobble_tween.kill()
	_wobble_tween = null


# =========================================================================
# API LAB – POKAZANIE / SCHOWANIE NARZĘDZIA
# =========================================================================

## Włącza bagietkę przy kursorze:
## - ustawia is_active, widoczność oraz z_index.
func show_tool() -> void:
	is_active = true
	visible = true
	z_index = show_z_index


## Chowa bagietkę i resetuje animację oraz transformację.
func hide_tool() -> void:
	is_active = false
	visible = false

	if is_instance_valid(_wobble_tween):
		_wobble_tween.kill()
		_wobble_tween = null

	rotation_degrees = 0.0
	scale = Vector2.ONE
	position = _base_pos


# =========================================================================
# FEEDBACK WIZUALNY – ANIMACJA „BUJNIĘCIA” PO MIESZANIU
# =========================================================================

## Odtwarza krótką animację rotacji i skali jako feedback po mieszaniu.
func play_mix_wobble() -> void:
	if is_instance_valid(_wobble_tween):
		_wobble_tween.kill()

	_wobble_tween = create_tween()
	_wobble_tween.set_trans(Tween.TRANS_SINE)
	_wobble_tween.set_ease(Tween.EASE_OUT)

	rotation_degrees = 0.0
	scale = Vector2.ONE

	var angle1: float = wobble_angle_deg
	var angle2: float = -wobble_angle_deg * wobble_damping
	var angle3: float = wobble_angle_deg * wobble_damping * wobble_damping
	var t: float = wobble_time

	var peak_scale := Vector2.ONE * (1.0 + wobble_scale_boost)

	# 1) pierwsze wychylenie + powiększenie
	_wobble_tween.tween_property(self, "rotation_degrees", angle1, t * 0.9)
	_wobble_tween.parallel().tween_property(self, "scale", peak_scale, t * 0.9)

	# 2) odbicie na drugą stronę i powrót skali
	_wobble_tween.tween_property(self, "rotation_degrees", angle2, t)
	_wobble_tween.parallel().tween_property(self, "scale", Vector2.ONE, t)

	# 3) lekkie domknięcie do zera
	_wobble_tween.tween_property(self, "rotation_degrees", angle3, t)
	_wobble_tween.tween_property(self, "rotation_degrees", 0.0, t * 0.85)


# =========================================================================
# OPCJONALNE ŚLEDZENIE MYSZY
# =========================================================================

## Jeżeli follow_mouse == true i bagietka jest aktywna, trzyma ją przy kursorze.
func _process(_delta: float) -> void:
	if is_active and follow_mouse:
		global_position = get_global_mouse_position()


# =========================================================================
# GLOBALNY INPUT – ANULOWANIE (RMB / ESC)
# =========================================================================

## Reaguje globalnie na RMB / ESC:
## - gdy bagietka jest aktywna, emituje cancel_requested → Lab chowa bagietkę.
func _unhandled_input(event: InputEvent) -> void:
	if not is_active:
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		cancel_requested.emit()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel_requested.emit()
		get_viewport().set_input_as_handled()
