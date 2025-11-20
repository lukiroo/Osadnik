extends Node2D
class_name StirRodCursor

## Wersja bagietki mieszającej przy kursorze z krótką animację po mieszaniu

signal cancel_requested()   # Lab nasłuchuje, żeby odłożyć bagietkę (RMB / ESC)

# -------------------- USTAWIENIA OGÓLNE --------------------
@export var follow_mouse: bool = false  # Jeśli true – kursor sam śledzi myszkę.
@export var show_z_index: int = 99      # Z-index, gdy bagietka jest aktywna.

# Proste parametry animacji „bujnięcia” po mieszaniu.
@export var wobble_angle_deg: float = 10.0
@export var wobble_time: float = 0.18
@export var wobble_damping: float = 0.6
@export var wobble_scale_boost: float = 0.04

# -------------------- STAN WEWNĘTRZNY --------------------
var is_active: bool = false
var _wobble_tween: Tween = null
var _base_pos: Vector2 = Vector2.ZERO   # Pozycja z edytora jako pozycja bazowa.


# =================================================================
# INICJALIZACJA I SPRZĄTANIE
# =================================================================
func _ready() -> void:
	# Startowo bagietka-kursor jest wyłączona i ukryta, ale proces działa zawsze
	# (żeby reagować na RMB/ESC niezależnie od trybu gry).
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	is_active = false
	_base_pos = position

func _exit_tree() -> void:
	# Na wyjście z drzewa sprzątamy tween, żeby nie pozostał „sierotą”.
	if is_instance_valid(_wobble_tween):
		_wobble_tween.kill()
	_wobble_tween = null


# =================================================================
# METODY UŻYWANE PRZEZ LAB – POKAZANIE / SCHOWANIE
# =================================================================
func show_tool() -> void:
	# Wywoływane, gdy użytkownik „bierze bagietkę do ręki”.
	is_active = true
	visible = true
	z_index = show_z_index

func hide_tool() -> void:
	# Odkładamy bagietkę – wyłączamy widoczność, zatrzymujemy animację i przywracamy transform.
	is_active = false
	visible = false

	if is_instance_valid(_wobble_tween):
		_wobble_tween.kill()
		_wobble_tween = null

	rotation_degrees = 0.0
	scale = Vector2.ONE
	position = _base_pos   # powrót do pozycji z edytora


# =================================================================
# FEEDBACK WIZUALNY: „BUJNIĘCIE” PO MIESZANIU
# =================================================================
func play_mix_wobble() -> void:
	# Krótka animacja rotacji i skali jako informacja zwrotna po mieszaniu.
	if is_instance_valid(_wobble_tween):
		_wobble_tween.kill()

	_wobble_tween = create_tween()
	_wobble_tween.set_trans(Tween.TRANS_SINE)
	_wobble_tween.set_ease(Tween.EASE_OUT)

	rotation_degrees = 0.0
	scale = Vector2.ONE

	var a1 := wobble_angle_deg
	var a2 := -wobble_angle_deg * wobble_damping
	var a3 := wobble_angle_deg * wobble_damping * wobble_damping
	var t := wobble_time

	var peak_scale := Vector2.ONE * (1.0 + wobble_scale_boost)

	# 1. pierwsze wychylenie
	_wobble_tween.tween_property(self, "rotation_degrees", a1, t * 0.9)
	_wobble_tween.parallel().tween_property(self, "scale", peak_scale, t * 0.9)

	# 2. odbicie na drugą stronę i powrót skali
	_wobble_tween.tween_property(self, "rotation_degrees", a2, t)
	_wobble_tween.parallel().tween_property(self, "scale", Vector2.ONE, t)

	# 3. lekkie domknięcie do zera
	_wobble_tween.tween_property(self, "rotation_degrees", a3, t)
	_wobble_tween.tween_property(self, "rotation_degrees", 0.0, t * 0.85)


# =================================================================
# OPCJONALNE ŚLEDZENIE MYSZY
# =================================================================
func _process(_dt: float) -> void:
	# Jeżeli follow_mouse jest aktywne, pozycję kursorowej bagietki wiążemy z kursorem.
	if is_active and follow_mouse:
		global_position = get_global_mouse_position()


# =================================================================
# GLOBALNY INPUT – ANULOWANIE (RMB / ESC)
# =================================================================
func _unhandled_input(event: InputEvent) -> void:
	# Prawy przycisk myszy lub ESC oznacza prośbę o odłożenie narzędzia.
	if not is_active:
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		cancel_requested.emit()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel_requested.emit()
		get_viewport().set_input_as_handled()
