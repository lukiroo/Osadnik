extends Node2D
class_name BunsenBurner

## =========================================================================
## bunsen_burner.gd – palnik Bunsena
## -------------------------------------------------------------------------
## Odpowiada za:
## - przełączanie płomienia między stanami OFF / YELLOW / BLUE,
## - reagowanie na kliknięcia w kurek (ValveArea2D),
## - reagowanie na wejście kursora w płomień (FlameArea2D),
## - sterowanie shaderem płomienia (flame_mode, test_color itp.),
## - prostą logikę próby płomieniowej na podstawie jonów w próbce.
## =========================================================================

# -----------------------------
# WĘZŁY SCENY
# -----------------------------

@onready var valve_area: Area2D      = $ValveArea2D         ## Obszar klikalny kurka.
@onready var valve_sprite: Sprite2D  = $ValveArea2D/Valve   ## Grafika kurka.

@onready var flame_area: Area2D      = $FlameArea2D         ## Obszar płomienia.
@onready var flame_sprite: Sprite2D  = $FlameArea2D/Flame   ## Grafika płomienia (z shaderem).


# -----------------------------
# STAN PALNIKA
# -----------------------------

enum FlameState { OFF, YELLOW, BLUE }

var flame_state: FlameState = FlameState.OFF   ## Aktualny stan płomienia.

## Materiał płomienia – zakładamy, że jest ustawiony w inspectorze.
var _flame_material: ShaderMaterial = null

## Timer do resetowania barwy testowej (próba płomieniowa).
@export var test_duration_sec: float = 2.0
var _test_timer: Timer = null


# -----------------------------
# SYGNAŁY
# -----------------------------

signal flame_state_changed(burner: BunsenBurner, state: int)
signal flame_entered(burner: BunsenBurner)
signal flame_test_finished(burner: BunsenBurner)
signal flame_exited(burner: BunsenBurner)


# =========================================================================
# INICJALIZACJA
# =========================================================================

## Przygotowuje palnik:
## - pobiera materiał płomienia,
## - tworzy timer do resetowania barwy testowej,
## - ustawia początkowy stan OFF (płomień niewidoczny).
func _ready() -> void:
	if flame_sprite:
		_flame_material = flame_sprite.material as ShaderMaterial

	_test_timer = Timer.new()
	_test_timer.one_shot = true
	add_child(_test_timer)
	_test_timer.timeout.connect(_on_test_timeout)

	_set_flame_state(FlameState.OFF)


# =========================================================================
# OBSŁUGA KURKA (ValveArea2D)
# =========================================================================
## Sprawdza, czy scena Lab jest w trybie IDLE
func _lab_is_idle() -> bool:
	var lab := get_tree().get_first_node_in_group("lab_root")
	if lab == null:
		return true

	var mode_enum: Variant = lab.get("Mode")
	var cur_mode: Variant  = lab.get("mode")

	# Preferowane: enum jako słownik z kluczem "IDLE"
	if mode_enum is Dictionary and mode_enum.has("IDLE"):
		return cur_mode == mode_enum["IDLE"]

	# Fallback: zakładamy, że 0 = IDLE
	if cur_mode is int:
		return int(cur_mode) == 0

	return false


## Reaguje na kliknięcia w kurek:
## - LPM: OFF -> YELLOW -> BLUE -> OFF (cyklicznie),
## - PPM: niezależnie od stanu gasi palnik (OFF).
func _on_valve_area_input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	# Blokada: kurek działa tylko, gdy Lab jest w trybie IDLE
	if not _lab_is_idle():
		return

	var mouse_event := event as InputEventMouseButton
	if mouse_event == null or not mouse_event.pressed:
		return

	if mouse_event.button_index == MOUSE_BUTTON_LEFT:
		_cycle_flame_state()
		get_viewport().set_input_as_handled()
	elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		if flame_state != FlameState.OFF:
			_set_flame_state(FlameState.OFF)
			get_viewport().set_input_as_handled()


## Przełącza stan płomienia: OFF -> YELLOW -> BLUE -> OFF.
func _cycle_flame_state() -> void:
	match flame_state:
		FlameState.OFF:
			_set_flame_state(FlameState.YELLOW)
		FlameState.YELLOW:
			_set_flame_state(FlameState.BLUE)
		FlameState.BLUE:
			_set_flame_state(FlameState.OFF)


## Ustawia konkretny stan płomienia i odświeża grafikę + shader.
func _set_flame_state(new_state: FlameState) -> void:
	flame_state = new_state

	match flame_state:
		FlameState.OFF:
			if flame_sprite:
				flame_sprite.visible = false
			_clear_flame_test_color()
		FlameState.YELLOW:
			if flame_sprite:
				flame_sprite.visible = true
			_update_flame_shader_mode(0)  # 0 = żółty
			_clear_flame_test_color()
		FlameState.BLUE:
			if flame_sprite:
				flame_sprite.visible = true
			_update_flame_shader_mode(1)  # 1 = niebieski
			# Test barwny ustawiany jest osobno przez apply_flame_test_for_ions().

	flame_state_changed.emit(self, int(flame_state))


# =========================================================================
# OBSŁUGA PŁOMIENIA (FlameArea2D)
# =========================================================================

## Reaguje na wejście kursora w obszar płomienia.
## Lab może w trybie PLATIN_ROD nasłuchiwać flame_entered i przekazać próbkę do palnika.
func _on_flame_area_mouse_entered() -> void:
	if flame_state == FlameState.OFF:
		return
	flame_entered.emit(self)


## Wywoływane, gdy kursor opuszcza obszar płomienia – resetuje barwę testową.
func _on_flame_area_mouse_exited() -> void:
	_clear_flame_test_color()
	flame_exited.emit(self)


# =========================================================================
# PRÓBA PŁOMIENIOWA
# =========================================================================

## Ustawia barwę testową na podstawie słownika jonów (np. z próbki na druciku).
## Logika „jaki kation → jaki kolor” jest trzymana bezpośrednio w skrypcie palnika.
func apply_flame_test_for_ions(ions: Dictionary) -> void:
	if flame_state != FlameState.BLUE:
		return
	if _flame_material == null:
		return
	if ions == null or not (ions is Dictionary) or ions.size() == 0:
		return

	var test_color: Color = _pick_test_color_from_ions(ions)

	# Jeśli żaden kation nie ma charakterystycznej barwy – nie robimy nic.
	if test_color.a <= 0.0:
		_clear_flame_test_color()
		return

	_flame_material.set_shader_parameter("test_color", test_color)
	_flame_material.set_shader_parameter("test_mix", 0.8)
	_flame_material.set_shader_parameter("use_test_color", true)
	# Płomień trochę wyższy, gdy coś się spala:
	_flame_material.set_shader_parameter("height_scale", 1.2)


	if _test_timer:
		_test_timer.start(test_duration_sec)


## Wewnętrzna pomocnicza: wybiera kolor płomienia na podstawie obecnych kationów.
## Jeśli brak rozpoznanego kationu – zwraca Color(0,0,0,0) jako „brak reakcji”.
func _pick_test_color_from_ions(ions: Dictionary) -> Color:
	var result: Color = Color(0, 0, 0, 0)

	for ion_name in ions.keys():
		var id := String(ion_name)

		match id:
			"Na+":
				# Żółty płomień sodowy
				result = Color(1.0, 0.9, 0.4, 1.0)
			"K+":
				# Fioletowo-różowy (potas)
				result = Color(0.8, 0.5, 1.0, 1.0)
			"Ba2+":
				# Zielonkawy (bar)
				result = Color(0.6, 1.0, 0.4, 1.0)
			"Sr2+":
				# Ceglastoczerwony (stront)
				result = Color(1.0, 0.45, 0.2, 1.0)
			"Ca2+":
				# Ceglastoczerwony trochę jaśniejszy (wapń)
				result = Color(1.0, 0.55, 0.3, 1.0)
			"Cu2+":
				# Niebiesko-zielony (miedź)
				result = Color(0.3, 1.0, 0.9, 1.0)
			_:
				pass

		if result.a > 0.0:
			break

	return result


## Czyści barwę testową i zatrzymuje timer.
func _clear_flame_test_color() -> void:
	if _flame_material:
		_flame_material.set_shader_parameter("use_test_color", false)
		_flame_material.set_shader_parameter("height_scale", 1.0)

	if _test_timer and not _test_timer.is_stopped():
		_test_timer.stop()



## Handler timera – resetuje barwę po upływie test_duration_sec.
func _on_test_timeout() -> void:
	_clear_flame_test_color()
	flame_test_finished.emit(self)


# =========================================================================
# WIZUAL – SHADER PŁOMIENIA
# =========================================================================

## Ustawia tryb płomienia w shaderze.
func _update_flame_shader_mode(mode_value: int) -> void:
	if _flame_material == null or _flame_material.shader == null:
		return

	for uniform_info in _flame_material.shader.get_shader_uniform_list():
		var info_dict: Dictionary = uniform_info
		if String(info_dict.get("name", "")) == "flame_mode":
			_flame_material.set_shader_parameter("flame_mode", mode_value)
			return
