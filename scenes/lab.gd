extends Node2D  ## Główny węzeł sceny stołu laboratoryjnego – centralny kontroler logiki.

## =========================================================================
## Lab.gd – główny kontroler stołu (tryby, narzędzia, highlighty)
## -------------------------------------------------------------------------
## - Pilnuje globalnego trybu interakcji (IDLE / HOLDING / TRANSFER / INDICATOR / STIR_ROD / SQUIRT).
## - Zarządza „kursorami” narzędzi (pipeta, dropper, papierek wskaźnikowy, bagietka, butelka z wodą).
## - Steruje podświetleniami probówek i hoverami narzędzi na stole.
## - Obsługuje strumienie pobierania / przelewania / dolewania wody.
## - Odpowiada za odkładanie narzędzi i spójne blokady interakcji.
## =========================================================================

@onready var level_manager: LevelManager = $LevelManager      ## Odpowiada za tryb ćwiczenia i odpowiedzi.
@onready var finish_btn: Button = $FinishBtn                  ## Przycisk zakończenia ćwiczenia / przejścia do wyników.

# ==============================
# TRYBY GLOBALNE
# ==============================
enum Mode { IDLE, HOLDING, TRANSFER, INDICATOR, STIR_ROD, SQUIRT }
var mode: Mode = Mode.IDLE                                   ## Aktualny tryb pracy stołu.

@export var tool_return_time: float = 0.6                    ## Czas animacji odkładania narzędzia na stół.

var _probe_drag_active: bool = false                         ## Czy jakaś probówka jest aktualnie przeciągana.
var _rmb_down_prev: bool = false                             ## Poprzedni stan prawego przycisku myszy (do wykrycia zmiany).

## Globalny stan highlightów pobierany z autoloada Settings.
var _highlights_enabled_global: bool = true

# ==============================
# PIPETA (HOLDING – butelki z reagentami)
# ==============================
var active_bottle: Node = null                               ## Aktualnie „aktywna” butelka (ta, z której kapie).
var active_reagent_id: StringName = &""                      ## Id reagenta z aktywnej butelki.

@onready var pipette: Node2D = $PipetteCursor                ## Kursor pipety (grafika przyklejona do myszy).
const PIPETTE_OFFSET: Vector2 = Vector2(8, -50)              ## Przesunięcie pipety względem kursora.

var _pipette_returning: bool = false                         ## Czy w trakcie animacji powrotu pipety.
var _pipette_return_target_bottle: Node = null               ## Butelka, do której wraca „duch” pipety.
var _pipette_return_tween: Tween = null
var _pipette_return_ghost: Node2D = null                     ## Tymczasowy duplikat pipety używany przy animacji powrotu.

# ==============================
# DROPPER (TRANSFER – pobieranie/przelewanie)
# ==============================
@onready var dropper_cursor: Node2D = $DropperCursor         ## Kursor droppera (nad myszą).
@onready var dropper_on_table: Node2D = $DropperOnTable      ## Dropper leżący na stole.

@export var dropper_capacity_units: float = 0.75             ## Umowna pojemność droppera (w „units”).
@export var pickup_rate_units_per_sec: float = 0.50          ## Ile units/s dropper zasysa z probówki.
@export var pour_rate_units_per_sec: float = 0.60            ## Ile units/s dropper wylewa do probówki.

var dropper_loaded: bool = false                             ## Czy dropper ma aktualnie jakąś ciecz.
var dropper_mix: Mixture = null                              ## Mieszanina aktualnie w dropperze.
var dropper_units: float = 0.0                               ## Ile „units” cieczy siedzi w dropperze.

enum PressMode { NONE, PICKING, POURING }                    ## Pod-tryb droppera – czy właśnie pobieramy, czy wylewamy.
var _press_mode: PressMode = PressMode.NONE
var _pick_src: Node = null                                   ## Probówka źródłowa (pobieranie).
var _pour_dst: Node = null                                   ## Probówka docelowa (wylewanie).

const DROPPER_OFFSET: Vector2 = Vector2(8, -40)              ## Offset kursorowego droppera względem myszy.

# ==============================
# WSKAŹNIK (PAPIEREK)
# ==============================
@export var indicator_paper_scene: PackedScene               ## PackedScene papierka wskaźnikowego.
@onready var indicator_box: Node2D = $IndicatorBox           ## „Pudełko” na papierek, leżące na stole.

var indicator_active: bool = false                           ## Czy papierek jest obecnie w użyciu.
var indicator_paper: IndicatorPaper = null                   ## Aktualny instancjonowany papierek.

# ==============================
# BAGIETKA (STIR ROD)
# ==============================
@onready var stir_rod_on_table: Node2D = $StirRodOnTable     ## Bagietka leżąca na stole.
@onready var stir_rod_cursor: Node2D = $StirRodCursor        ## Bagietka w ręku (kursor).

const STIR_ROD_OFFSET: Vector2 = Vector2(6, -28)             ## Offset bagietki względem myszy.

# ==============================
# SQUIRT BOTTLE (BUTELKA Z WODĄ)
# ==============================
@onready var squirt_on_table: Node2D = $SquirtBottleOnTable  ## Butelka z wodą na stole.
@onready var squirt_cursor: Node2D = $SquirtBottleCursor     ## Butelka „w ręce” – na kursorze.

const SQUIRT_OFFSET: Vector2 = Vector2(8, -40)               ## Offset butelki względem myszy.

@export var squirt_rate_units_per_sec: float = 0.60          ## Tempo dolewania wody [units/s].
var _squirt_active: bool = false                             ## Czy stoimy w trybie SQUIRT.
var _squirt_dst: Node = null                                 ## Probówka docelowa, do której wlewamy wodę.
var _squirt_lmb_down: bool = false                           ## Czy LPM jest trzymany podczas wlewania.

# =============================================================================
# LIFECYCLE – inicjalizacja i pętla klatkowa
# =============================================================================
func _ready() -> void:
	## Przy starcie:
	## - dodaje się do grupy "lab_root" (żeby Probe mogły nas łatwo znaleźć),
	## - pobiera opcje z autoloada Settings,
	## - podpina sygnały "left_clicked" z narzędzi na stole,
	## - odświeża highlighty, hover-y i widget droppera.
	add_to_group("lab_root")

	# Snapshot opcji highlightów z autoloada Settings.
	var settings_node: Node = get_tree().get_root().get_node_or_null("Settings")
	if settings_node:
		if settings_node.has_method("are_highlights_enabled"):
			_highlights_enabled_global = bool(settings_node.are_highlights_enabled())
		elif "highlights_enabled" in settings_node:
			_highlights_enabled_global = bool(settings_node.highlights_enabled)
		else:
			_highlights_enabled_global = true

		if settings_node.has_signal("changed") and not settings_node.changed.is_connected(_on_settings_changed):
			settings_node.changed.connect(_on_settings_changed)
	else:
		_highlights_enabled_global = true

	if squirt_on_table:
		squirt_on_table.visible = true
		if squirt_on_table.has_signal("left_clicked"):
			squirt_on_table.left_clicked.connect(_on_squirt_on_table_clicked)

	# Podpinamy butelki z reagentami (grupa "bottles").
	for bottle_node: Node in get_tree().get_nodes_in_group("bottles"):
		if bottle_node and bottle_node.has_signal("left_clicked"):
			bottle_node.left_clicked.connect(_on_bottle_left_clicked)

	if dropper_on_table and dropper_on_table.has_signal("left_clicked"):
		dropper_on_table.left_clicked.connect(_on_dropper_on_table_clicked)

	if indicator_box and indicator_box.has_signal("left_clicked"):
		indicator_box.left_clicked.connect(_on_indicator_box_clicked)

	if stir_rod_on_table and stir_rod_on_table.has_signal("left_clicked"):
		stir_rod_on_table.left_clicked.connect(_on_stir_rod_on_table_clicked)

	if stir_rod_cursor and stir_rod_cursor.has_signal("cancel_requested"):
		stir_rod_cursor.cancel_requested.connect(_on_stir_rod_cancel)

	_ensure_probes_pickable()

	_set_all_bottles_hover(true)
	_set_all_probes_highlight(false)
	_refresh_table_hovers()
	_update_dropper_ui()
	_refresh_probe_highlights()
	# Drugi refresh po 1 klatce – na wypadek, gdyby racki/probówki przestawiły się po _ready.
	call_deferred("_refresh_probe_highlights")


func _process(delta: float) -> void:
	## Pętla logiki w czasie rzeczywistym:
	## - aktualizuje pozycje kursorów narzędzi (pipeta, dropper, bagietka, butelka),
	## - obsługuje przytrzymane strumienie: pobieranie, przelewanie, dolewanie wody,
	## - reaguje na zmianę stanu PPM (rmb) – do aktualizacji highlightów.
	match mode:
		Mode.HOLDING:
			if pipette:
				pipette.global_position = get_global_mouse_position() + PIPETTE_OFFSET

		Mode.TRANSFER:
			if dropper_cursor:
				dropper_cursor.global_position = get_global_mouse_position() + DROPPER_OFFSET
			match _press_mode:
				PressMode.PICKING:
					_tick_pick(delta)
				PressMode.POURING:
					_tick_pour(delta)
				_:
					pass

		Mode.STIR_ROD:
			if stir_rod_cursor:
				stir_rod_cursor.global_position = get_global_mouse_position() + STIR_ROD_OFFSET

		Mode.SQUIRT:
			if squirt_cursor:
				squirt_cursor.global_position = get_global_mouse_position() + SQUIRT_OFFSET
			_tick_squirt(delta)

		_:
			pass

	_update_dropper_ui()

	var rmb_current: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if rmb_current != _rmb_down_prev:
		_rmb_down_prev = rmb_current
		_refresh_probe_highlights()


# =============================================================================
# SETTINGS – reakcja na zmianę opcji (autoload Settings)
# =============================================================================
func _on_settings_changed() -> void:
	## Wywoływane, gdy autoload Settings zgłasza sygnał "changed".
	## Aktualizuje flagę globalnych highlightów i odświeża hover-y / highlighty.
	var settings_node: Node = get_tree().get_root().get_node_or_null("Settings")
	if settings_node:
		if settings_node.has_method("are_highlights_enabled"):
			_highlights_enabled_global = bool(settings_node.are_highlights_enabled())
		elif "highlights_enabled" in settings_node:
			_highlights_enabled_global = bool(settings_node.highlights_enabled)

	_refresh_table_hovers()
	_refresh_probe_highlights()
	_set_all_bottles_hover(true)  # odświeżenie hoverów butelek zgodnie z globalnym stanem


# =============================================================================
# INPUT (GLOBAL) – RMB, ESC i kończenie strumieni
# =============================================================================
func _unhandled_input(event: InputEvent) -> void:
	## Globalny input:
	## - puszczenie LPM kończy PICKING/POURING/SQUIRT,
	## - PPM odkłada aktualne narzędzie (jeśli to ma sens),
	## - ESC odkłada wybrane narzędzia (bez droppera).
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _press_mode == PressMode.PICKING:
			_press_mode = PressMode.NONE
			_pick_src = null
		elif _press_mode == PressMode.POURING:
			_press_mode = PressMode.NONE
			_pour_dst = null
		if mode == Mode.SQUIRT:
			_squirt_lmb_down = false
			_squirt_dst = null

	if event is InputEventMouseButton and event.pressed and (
		event.button_index == MOUSE_BUTTON_RIGHT or event.is_action_pressed("right_click")
	):
		match mode:
			Mode.TRANSFER:
				if _dropper_can_put_back():
					_dropper_put_back(true)
				else:
					_dropper_deny_put_back_feedback()
				get_viewport().set_input_as_handled()

			Mode.INDICATOR:
				_indicator_put_back(true)
				get_viewport().set_input_as_handled()

			Mode.HOLDING:
				_pipette_put_back(true)
				get_viewport().set_input_as_handled()

			Mode.STIR_ROD:
				_stir_rod_put_back(true)
				get_viewport().set_input_as_handled()

			Mode.SQUIRT:
				_squirt_put_back(true)
				get_viewport().set_input_as_handled()

			_:
				pass

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		match mode:
			Mode.INDICATOR:
				_indicator_put_back(true)
				get_viewport().set_input_as_handled()
			Mode.STIR_ROD:
				_stir_rod_put_back(true)
				get_viewport().set_input_as_handled()
			Mode.SQUIRT:
				_squirt_put_back(true)
				get_viewport().set_input_as_handled()
			_:
				pass


# =============================================================================
# FINISH – zapis kontekstu i przejście do ekranu wyników
# =============================================================================
func _on_finish_btn_pressed() -> void:
	## Handler przycisku "Zakończ":
	## - zbiera kontekst z LevelManagera,
	## - dorzuca mapę odpowiedzi/odpowiedzi złożonych,
	## - zapisuje to w /root/Settings,
	## - przełącza scenę na ekran wyników.
	if level_manager == null:
		push_error("[Lab] Brak węzła LevelManager.")
		return

	var mode_str: String = _mode_to_string(level_manager.get("mode"))
	var group_id: int = int(level_manager.get("group_id"))

	var ctx: Dictionary = {
		"mode_str": mode_str,
		"group_id": group_id
	}

	if mode_str == "EXERCISE_SINGLE":
		var answer_map: Dictionary = {}
		if level_manager.has_method("get_single_answer_map"):
			answer_map = level_manager.call("get_single_answer_map")
		ctx["single_answer_map"] = answer_map
		print("[Lab] single_answer_map.size() = ", answer_map.size())
	elif mode_str == "EXERCISE_MIX":
		var answer_list: Array = []
		if level_manager.has_method("get_mix_answer_list"):
			answer_list = level_manager.call("get_mix_answer_list")
		ctx["mix_answer_list"] = answer_list
		print("[Lab] mix_answer_list = ", answer_list)

	var settings_node: Node = get_tree().get_root().get_node_or_null("Settings")
	if settings_node:
		settings_node.set_last_run_context(ctx)
	else:
		push_error("[Lab] Nie znaleziono /root/Settings – autoload nie jest włączony?")

	print_rich(
		"[color=yellow][Lab] ctx zapisany: mode=", ctx.get("mode_str"),
		", group=", ctx.get("group_id"),
		", single_keys=", ((ctx["single_answer_map"] as Dictionary).keys() if ctx.has("single_answer_map") else []),
		", mix=", (ctx["mix_answer_list"] if ctx.has("mix_answer_list") else []),
		"[/color]"
	)

	get_tree().change_scene_to_file("res://scenes/menu/results.tscn")


func _mode_to_string(mode_value: int) -> String:
	## Zamienia tryb numeryczny LevelManagera na string używany w kontekście.
	match mode_value:
		1:
			return "EXERCISE_SINGLE"
		2:
			return "EXERCISE_MIX"
		_:
			return "SANDBOX"


# =============================================================================
# HOLDING (pipeta + butelki)
# =============================================================================
func _on_bottle_left_clicked(bottle: Node) -> void:
	## Kliknięcie w butelkę z reagentem:
	## - w IDLE → podnosimy pipetę i przechodzimy w HOLDING,
	## - w HOLDING na tej samej butelce → odkładamy pipetę i włączamy pełną butelkę.
	if _pipette_returning and _pipette_return_target_bottle == bottle:
		get_viewport().set_input_as_handled()
		return

	if mode in [Mode.TRANSFER, Mode.INDICATOR, Mode.STIR_ROD, Mode.SQUIRT]:
		return

	if mode == Mode.IDLE:
		active_bottle = bottle
		var reagent_id_local: StringName = &""

		if bottle.has_method("get_reagent_id"):
			reagent_id_local = StringName(str(bottle.get_reagent_id()))
		elif bottle.get("reagent") != null:
			var reagent_resource: Resource = bottle.get("reagent") as Resource
			if reagent_resource:
				if reagent_resource.has_method("get") and reagent_resource.get("id") != null:
					reagent_id_local = StringName(str(reagent_resource.get("id")))
				elif "id" in reagent_resource:
					reagent_id_local = StringName(str(reagent_resource.id))

		active_reagent_id = reagent_id_local

		if bottle.has_method("show_empty"):
			bottle.show_empty()

		if pipette:
			pipette.visible = true

		mode = Mode.HOLDING

		_set_bottles_hover_except(active_bottle)
		_refresh_probe_highlights()
		_refresh_table_hovers()

	elif mode == Mode.HOLDING and bottle == active_bottle:
		if bottle.has_method("show_full"):
			bottle.show_full(true)
		_reset_pipette_only()
		_set_all_bottles_hover(true)
		_refresh_probe_highlights()
		_refresh_table_hovers()


func _reset_pipette_only() -> void:
	## Prosty reset pipety – bez animacji powrotu.
	if pipette:
		pipette.visible = false
	mode = Mode.IDLE
	active_reagent_id = &""
	active_bottle = null
	_refresh_table_hovers()


# =============================================================================
# TRANSFER (dropper) – podnoszenie/odkładanie + strumienie
# =============================================================================
func _on_dropper_on_table_clicked(_stand: Node) -> void:
	## Kliknięcie droppera na stole – podnosimy, jeśli jesteśmy w IDLE.
	if mode != Mode.IDLE:
		return
	_dropper_take_from_table()


func _dropper_take_from_table() -> void:
	## Podniesienie droppera ze stołu:
	## - tylko gdy nie używamy innych narzędzi,
	## - przełącza tryb na TRANSFER i resetuje stan droppera.
	mode = Mode.TRANSFER
	_clear_dropper_state()

	if dropper_cursor:
		dropper_cursor.visible = true
	if dropper_on_table:
		dropper_on_table.visible = false

	_set_all_bottles_hover(false)
	_refresh_probe_highlights()
	_refresh_table_hovers()
	_update_dropper_ui()


func _dropper_can_put_back() -> bool:
	## Dropper można odstawić tylko, jeśli jest pusty.
	return not dropper_loaded and dropper_units <= 0.000001


func _dropper_put_back(animated: bool = false) -> void:
	## Odkładanie droppera na stół (z animacją lub bez).
	mode = Mode.IDLE
	_set_all_bottles_hover(true)
	_refresh_probe_highlights()
	_refresh_table_hovers()

	if not dropper_cursor or not dropper_on_table:
		if dropper_cursor:
			dropper_cursor.visible = false
		if dropper_on_table:
			dropper_on_table.visible = true
		_clear_dropper_state()
		_update_dropper_ui()
		return

	var target_pos: Vector2 = _get_anchor_global(dropper_on_table) + DROPPER_OFFSET

	var finish_put_back := func() -> void:
		if dropper_cursor:
			dropper_cursor.visible = false
		if dropper_on_table:
			dropper_on_table.visible = true
		_clear_dropper_state()
		_update_dropper_ui()
		_refresh_probe_highlights()

	if animated:
		var tween: Tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(dropper_cursor, "global_position", target_pos, tool_return_time)
		tween.finished.connect(finish_put_back)
	else:
		dropper_cursor.global_position = target_pos
		finish_put_back.call()


func _dropper_deny_put_back_feedback() -> void:
	## Krótkie „potrząśnięcie” dropperem, kiedy próbujemy go odłożyć pełnego.
	if not dropper_cursor:
		return
	var base_rotation: float = dropper_cursor.rotation_degrees
	var tween: Tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(dropper_cursor, "rotation_degrees", base_rotation + 7.0, 0.06)
	tween.tween_property(dropper_cursor, "rotation_degrees", base_rotation - 7.0, 0.10)
	tween.tween_property(dropper_cursor, "rotation_degrees", base_rotation, 0.06)


func _dropper_pick(source_probe: Node) -> void:
	## Start strumienia zasysania z probówki do droppera (LPM na probówce).
	if source_probe and _probe_is_in_shelved_rack(source_probe):
		return
	if dropper_loaded:
		return
	if mode != Mode.TRANSFER or _press_mode != PressMode.NONE:
		return
	if not source_probe or not source_probe.has_method("take_volume"):
		return
	if _locked(source_probe):
		return

	_press_mode = PressMode.PICKING
	_pick_src = source_probe


func _dropper_drop(target_probe: Node) -> void:
	## Start strumienia przelewania zawartości droppera do probówki (LPM na probówce).
	if target_probe and _probe_is_in_shelved_rack(target_probe):
		return
	if not dropper_loaded:
		return
	if mode != Mode.TRANSFER or _press_mode != PressMode.NONE:
		return
	if not target_probe or not target_probe.has_method("receive_mixture"):
		return
	if _locked(target_probe):
		return

	_press_mode = PressMode.POURING
	_pour_dst = target_probe


func _tick_pick(delta: float) -> void:
	## Krok strumienia pobierania do droppera:
	## - wylicza ile units możemy jeszcze wciągnąć,
	## - woła take_volume na probówce,
	## - scala mieszaniny w dropperze.
	if _pick_src == null:
		return

	var free_capacity: float = dropper_capacity_units - dropper_units
	if free_capacity <= 0.000001:
		_press_mode = PressMode.NONE
		_pick_src = null
		return

	var max_rate: float = max(0.0, pickup_rate_units_per_sec)
	var requested_units: float = min(free_capacity, max_rate * delta)
	if requested_units <= 0.0:
		return

	var take_result: Variant = _pick_src.take_volume(requested_units)
	if take_result == null:
		return

	var picked_mixture: Mixture = null
	var picked_units: float = 0.0

	if take_result is Mixture:
		picked_mixture = take_result as Mixture
		if picked_mixture.tags is Dictionary and (picked_mixture.tags as Dictionary).has("vol_u"):
			picked_units = float((picked_mixture.tags as Dictionary).get("vol_u", requested_units))
		else:
			picked_units = requested_units
	elif take_result is Dictionary:
		picked_mixture = (take_result as Dictionary).get("mix") as Mixture
		picked_units = float((take_result as Dictionary).get("units", requested_units))
	else:
		return

	if picked_units <= 0.0 or picked_mixture == null:
		return

	if dropper_mix == null:
		dropper_mix = picked_mixture.clone()
	else:
		_dropper_merge_extensive(dropper_mix, picked_mixture)

	dropper_units = min(dropper_capacity_units, dropper_units + picked_units)

	var was_loaded: bool = dropper_loaded
	dropper_loaded = (dropper_units > 0.000001)
	if dropper_loaded and not was_loaded:
		_refresh_probe_highlights()

	if dropper_units >= dropper_capacity_units - 0.000001:
		_press_mode = PressMode.NONE
		_pick_src = null


func _tick_pour(delta: float) -> void:
	## Krok strumienia wylewania droppera do probówki:
	## - wylicza ile units możemy wylać w tej klatce,
	## - tworzy porcję mieszaniny (scaled_fraction),
	## - przekazuje ją do probówki docelowej (receive_mixture),
	## - aktualizuje stan droppera.
	if _pour_dst == null or not dropper_loaded or dropper_mix == null:
		return

	var pour_speed: float = max(0.0, pour_rate_units_per_sec)
	var requested_units: float = min(dropper_units, pour_speed * delta)
	if requested_units <= 0.0:
		return

	var previous_units: float = max(0.000001, dropper_units)
	var wanted_fraction: float = clamp(requested_units / previous_units, 0.0, 1.0)

	var poured_portion: Mixture = _dropper_make_portion(dropper_mix, wanted_fraction)

	var receive_result: Variant = _pour_dst.receive_mixture(poured_portion, requested_units)
	var accepted_units: float = (float(receive_result) if (receive_result is float or receive_result is int) else requested_units)

	if accepted_units <= 0.000001:
		_press_mode = PressMode.NONE
		_pour_dst = null
		return

	var accepted_fraction: float = clamp(accepted_units / previous_units, 0.0, 1.0)

	_dropper_apply_fraction_loss(dropper_mix, accepted_fraction)

	dropper_units -= accepted_units
	if dropper_units <= 0.000001:
		dropper_units = 0.0
		dropper_loaded = false
		dropper_mix = null
		_press_mode = PressMode.NONE
		_pour_dst = null
		_refresh_probe_highlights()


# ==============================
# DROP HELPERS — spójność z Mixture
# ==============================
func _dropper_make_portion(source_mix: Mixture, fraction_value: float) -> Mixture:
	## Tworzy porcję mieszaniny do wylania z droppera.
	var clamped_fraction: float = clamp(fraction_value, 0.0, 1.0)
	var portion: Mixture = source_mix.scaled_fraction(clamped_fraction, false)
	portion.tags = {}
	return portion


func _dropper_apply_fraction_loss(target_mix: Mixture, fraction_value: float) -> void:
	## Odcina z mieszaniny w dropperze część, którą wylaliśmy.
	var clamped_fraction: float = clamp(fraction_value, 0.0, 1.0)
	target_mix.subtract_fraction_in_place(clamped_fraction, false)
	if target_mix.tags is Dictionary:
		(target_mix.tags as Dictionary).erase("pH")
		(target_mix.tags as Dictionary).erase("ph_samples")


func _dropper_merge_extensive(target_mix: Mixture, source_mix: Mixture) -> void:
	## Scala mieszaniny w dropperze w sposób „ekstensywny”
	## (żadnego uśredniania – Mixture.merge_from).
	if target_mix == null or source_mix == null:
		return
	target_mix.merge_from(source_mix)
	if target_mix.tags is Dictionary and (target_mix.tags as Dictionary).has("ph_samples"):
		(target_mix.tags as Dictionary).erase("ph_samples")


# =============================================================================
# INDICATOR (papierek) – podnoszenie/odkładanie i użycie
# =============================================================================
func _on_indicator_box_clicked(_box: Node) -> void:
	## Kliknięcie pudełka na papierek:
	## - w IDLE → podnosimy papierek,
	## - gdy papierek jest aktywny → odkładamy go z powrotem.
	if mode not in [Mode.IDLE, Mode.INDICATOR]:
		return
	if indicator_active:
		_indicator_put_back(true)
	else:
		_indicator_pick()


func _indicator_pick() -> void:
	## Podnosi nowy papierek wskaźnikowy z pudełka.
	if indicator_paper_scene == null:
		push_warning("indicator_paper_scene not set")
		return
	if indicator_active:
		return

	indicator_paper = indicator_paper_scene.instantiate() as IndicatorPaper
	add_child(indicator_paper)
	indicator_paper.follow_mouse = true
	indicator_paper.cursor_offset = Vector2(8, -40)

	indicator_active = true
	mode = Mode.INDICATOR

	if indicator_paper and not indicator_paper.is_connected("used_on_probe", Callable(self, "_on_indicator_used")):
		indicator_paper.used_on_probe.connect(_on_indicator_used)

	_set_all_bottles_hover(false)
	_refresh_probe_highlights()
	_refresh_table_hovers()


func _on_indicator_used(_probe: Node, _grade: int) -> void:
	## Papierek został użyty na probówce – wystarczy odświeżyć highlighty.
	_refresh_probe_highlights()


func _indicator_put_back(animated: bool = false) -> void:
	## Odkłada papierek do pudełka (z animacją lub bez).
	mode = Mode.IDLE
	_set_all_bottles_hover(true)
	_refresh_probe_highlights()
	_refresh_table_hovers()

	if not indicator_paper:
		indicator_active = false
		return

	if "follow_mouse" in indicator_paper:
		indicator_paper.follow_mouse = false

	var target_pos: Vector2 = _get_anchor_global(indicator_box)

	var finish_put_back := func() -> void:
		if indicator_paper:
			indicator_paper.queue_free()
		indicator_paper = null
		indicator_active = false
		_refresh_table_hovers()
		_refresh_probe_highlights()

	if animated:
		var tween: Tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(indicator_paper, "global_position", target_pos, tool_return_time)
		tween.finished.connect(finish_put_back)
	else:
		indicator_paper.global_position = target_pos
		finish_put_back.call()


func _indicator_use_on_probe(probe: Node) -> void:
	## Użycie papierka na probówce:
	## - odrzuca probówki na półce i puste,
	## - wyciąga „ocenę pH” z probówki i przekazuje ją do papierka.
	if probe and _probe_is_in_shelved_rack(probe):
		return
	if not indicator_active or indicator_paper == null:
		return
	if indicator_paper.is_spent:
		return
	if probe == null or not _has_liquid(probe):
		get_viewport().set_input_as_handled()
		return
	if _locked(probe):
		get_viewport().set_input_as_handled()
		return

	var grade: int = 0
	if probe and probe.has_method("get_indicator_grade"):
		grade = int(probe.get_indicator_grade())

	indicator_paper.use_on_probe(probe, grade)


func _indicator_use(probe: Node) -> void:
	## Alias – uproszczone API zewnętrzne.
	_indicator_use_on_probe(probe)


# =============================================================================
# BAGIETKA (stir rod) – podnoszenie/odkładanie i użycie
# =============================================================================
func _on_stir_rod_on_table_clicked(_node: Node) -> void:
	## Kliknięcie bagietki na stole – podnosimy ją.
	if mode != Mode.IDLE:
		return
	_stir_rod_take_from_table()


func _stir_rod_take_from_table() -> void:
	## Przełącza w tryb STIR_ROD i aktywuje bagietkę na kursorze.
	mode = Mode.STIR_ROD

	if stir_rod_cursor:
		stir_rod_cursor.visible = true
		stir_rod_cursor.global_position = get_global_mouse_position() + STIR_ROD_OFFSET
	if stir_rod_on_table:
		stir_rod_on_table.visible = false

	_set_all_bottles_hover(false)
	_refresh_probe_highlights()
	_refresh_table_hovers()


func _stir_rod_put_back(animated: bool = true) -> void:
	## Odkładanie bagietki na stół (z animacją lub bez).
	mode = Mode.IDLE
	_set_all_bottles_hover(true)
	_refresh_probe_highlights()
	_refresh_table_hovers()

	if not stir_rod_cursor or not stir_rod_on_table:
		if stir_rod_cursor:
			stir_rod_cursor.visible = false
		if stir_rod_on_table:
			stir_rod_on_table.visible = true
		return

	var target_pos: Vector2 = _get_anchor_global(stir_rod_on_table) + STIR_ROD_OFFSET

	var finish_put_back := func() -> void:
		if stir_rod_cursor:
			stir_rod_cursor.visible = false
		if stir_rod_on_table:
			stir_rod_on_table.visible = true
		_refresh_table_hovers()
		_refresh_probe_highlights()

	if animated:
		var tween: Tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(stir_rod_cursor, "global_position", target_pos, tool_return_time)
		tween.finished.connect(finish_put_back)
	else:
		stir_rod_cursor.global_position = target_pos
		finish_put_back.call()


func _on_stir_rod_cancel() -> void:
	## Anulowanie bagietki (np. sygnał z kursora).
	_stir_rod_put_back(true)


func _stir_rod_use_on_probe(probe: Node) -> void:
	## Użycie bagietki na probówce:
	## - odrzuca probówki na półce i bez cieczy,
	## - woła stir_with_rod na probówce,
	## - odpala prosty efekt „mix_wobble” na kursorze bagietki.
	if probe and _probe_is_in_shelved_rack(probe):
		return
	if mode != Mode.STIR_ROD:
		return
	if probe == null or not _has_liquid(probe):
		get_viewport().set_input_as_handled()
		return
	if _locked(probe):
		get_viewport().set_input_as_handled()
		return

	if probe.has_method("stir_with_rod"):
		probe.stir_with_rod(0.65)
		if stir_rod_cursor and stir_rod_cursor.has_method("play_mix_wobble"):
			stir_rod_cursor.play_mix_wobble()
		get_viewport().set_input_as_handled()


# =============================================================================
# SQUIRT BOTTLE (woda) – podnoszenie, wylewanie ciągłe i odkładanie
# =============================================================================
func _on_squirt_on_table_clicked(_node: Node) -> void:
	## Kliknięcie butelki z wodą na stole.
	if mode != Mode.IDLE:
		return
	_squirt_take_from_table()


func _squirt_take_from_table() -> void:
	## Podnosi butelkę z wodą – wchodzimy w tryb SQUIRT.
	mode = Mode.SQUIRT
	_squirt_active = true
	_squirt_dst = null
	_squirt_lmb_down = false

	if squirt_cursor:
		squirt_cursor.visible = true
		squirt_cursor.global_position = get_global_mouse_position() + SQUIRT_OFFSET
	if squirt_on_table:
		squirt_on_table.visible = false

	_set_all_bottles_hover(false)
	_refresh_probe_highlights()
	_refresh_table_hovers()


func _squirt_put_back(animated: bool = true) -> void:
	## Odkłada butelkę z wodą na stół i wychodzi z trybu SQUIRT.
	mode = Mode.IDLE
	_squirt_active = false
	_squirt_lmb_down = false
	_squirt_dst = null

	_set_all_bottles_hover(true)
	_refresh_probe_highlights()
	_refresh_table_hovers()

	if not squirt_cursor or not squirt_on_table:
		if squirt_cursor:
			squirt_cursor.visible = false
		if squirt_on_table:
			squirt_on_table.visible = true
		return

	var target_pos: Vector2 = _get_anchor_global(squirt_on_table) + SQUIRT_OFFSET

	var finish_put_back := func() -> void:
		if squirt_cursor:
			squirt_cursor.visible = false
		if squirt_on_table:
			squirt_on_table.visible = true
		_refresh_table_hovers()
		_refresh_probe_highlights()

	if animated:
		var tween: Tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(squirt_cursor, "global_position", target_pos, tool_return_time)
		tween.finished.connect(finish_put_back)
	else:
		squirt_cursor.global_position = target_pos
		finish_put_back.call()


func _squirt_begin(dst: Node) -> void:
	## Start ciągłego wlewania wody do probówki.
	if dst and _probe_is_in_shelved_rack(dst):
		return
	if mode != Mode.SQUIRT:
		return
	if not dst or not dst.has_method("receive_mixture"):
		return
	if _locked(dst):
		return
	_squirt_dst = dst
	_squirt_lmb_down = true
	get_viewport().set_input_as_handled()


func _squirt_end() -> void:
	## Zatrzymuje strumień wody (bez odkładania butelki).
	_squirt_lmb_down = false
	_squirt_dst = null


func _tick_squirt(delta: float) -> void:
	## Krok strumienia wody:
	## - kończy, jeśli LPM został puszczony,
	## - pilnuje, żeby nie przepełnić probówki,
	## - tworzy „czystą” wodę i woła receive_mixture.
	if mode != Mode.SQUIRT:
		return

	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_squirt_end()
		return

	if not _squirt_lmb_down or _squirt_dst == null:
		return
	if not is_instance_valid(_squirt_dst):
		_squirt_end()
		return

	if _squirt_dst.has_method("is_full") and _squirt_dst.is_full():
		if _squirt_dst.has_method("_deny_fill_feedback"):
			_squirt_dst._deny_fill_feedback()
		_squirt_end()
		return

	var rate: float = max(0.0, squirt_rate_units_per_sec)
	var requested_units: float = rate * delta
	if requested_units <= 0.0:
		return

	var water: Mixture = Mixture.new()
	water.tags = {}

	var accepted_units: float = 0.0
	if _squirt_dst.has_method("receive_mixture"):
		accepted_units = float(_squirt_dst.receive_mixture(water, requested_units))

	if accepted_units <= 0.00001:
		_squirt_end()
		return
	# Bilans pH/objętości liczy Probe/QualEngine.


# =============================================================================
# HIGHLIGHTS – probówki + globalny OFF
# =============================================================================
func _locked(node: Node) -> bool:
	## Sprawdza, czy probówka jest „zablokowana” do interakcji:
	## - stoi w racku na półce,
	## - albo ma are_interactions_enabled() == false.
	if node and _probe_is_in_shelved_rack(node):
		return true
	return (
		node
		and node.has_method("are_interactions_enabled")
		and not bool(node.are_interactions_enabled())
	)


func _has_liquid(probe: Node) -> bool:
	## Czy probówka zawiera jakąkolwiek ciecz / osad.
	if probe and probe.has_method("has_any_liquid"):
		return bool(probe.has_any_liquid())
	if probe and probe.has_method("get"):
		var level: Variant = probe.get("fill_level")
		if level is float or level is int:
			return float(level) > 0.001
	return false


func _is_full(probe: Node) -> bool:
	## Krótkie sprawdzenie, czy probówka „pełna” (is_full).
	return (probe and probe.has_method("is_full") and bool(probe.is_full()))


func _set_highlights_by(predicate: Callable) -> void:
	## Stosuje highlight do probówek na podstawie prostego predykatu:
	## - od razu wyłącza highlighty, jeśli globalna flaga jest OFF,
	## - ignoruje probówki na półce.
	if not _highlights_enabled_global:
		_set_all_probes_highlight(false)
		return

	for probe in get_tree().get_nodes_in_group("probes"):
		if not probe:
			continue
		if _probe_is_in_shelved_rack(probe):
			if probe.has_method("set_highlight_enabled"):
				probe.set_highlight_enabled(false)
			continue
		if probe.has_method("set_highlight_enabled"):
			var enable_highlight: bool = bool(predicate.call(probe))
			probe.set_highlight_enabled(enable_highlight)


func _refresh_probe_highlights() -> void:
	## Główny „mózg” highlightów:
	## - w trybie IDLE pokazuje wszystkie probówki (poza półką / beakerem),
	## - w innych trybach podświetla tylko sensowne cele (np. niepełne / z cieczą),
	## - gdy trwa drag probówki – highlighty są wyłączone, żeby nie migały.
	_apply_shelf_guard_to_all_probes()

	if not _highlights_enabled_global:
		_set_all_probes_highlight(false)
		return

	if _probe_drag_active:
		_set_all_probes_highlight(false)
		return


	if mode == Mode.IDLE:
		_set_highlights_by(func(probe: Node) -> bool:
			return not _probe_is_in_shelved_rack(probe) and not _probe_is_in_beaker(probe)
		)
		return

	match mode:
		Mode.HOLDING:
			_set_highlights_by(func(probe: Node) -> bool:
				return not _locked(probe) and not _is_full(probe)
			)

		Mode.TRANSFER:
			if not dropper_loaded:
				_set_highlights_by(func(probe: Node) -> bool:
					return not _locked(probe) and _has_liquid(probe)
				)
			else:
				_set_highlights_by(func(probe: Node) -> bool:
					return not _locked(probe) and not _is_full(probe)
				)

		Mode.INDICATOR, Mode.STIR_ROD:
			_set_highlights_by(func(probe: Node) -> bool:
				return not _locked(probe) and _has_liquid(probe)
			)

		Mode.SQUIRT:
			_set_highlights_by(func(probe: Node) -> bool:
				return not _locked(probe) and not _is_full(probe)
			)

		_:
			for probe in get_tree().get_nodes_in_group("probes"):
				if probe and probe.has_method("set_highlight_enabled"):
					probe.set_highlight_enabled(false)


# ======================================================================
# SHELF GUARD – probówki w racku na półce są nieinteraktywne
# ======================================================================
func _probe_is_in_shelved_rack(probe: Node) -> bool:
	## Sprawdza, czy probówka stoi w racku, który jest na półce (rack._is_on_shelf()).
	if probe == null:
		return false

	var node_it: Node = probe
	var rack: ProbeRack = null
	while node_it:
		if node_it is ProbeRack:
			rack = node_it as ProbeRack
			break
		node_it = node_it.get_parent()

	if rack == null:
		return false

	return rack._is_on_shelf()


func _set_probe_interactive(probe: Node, enabled: bool) -> void:
	## Włącza/wyłącza input pickable + monitoring dla Area2D probówki.
	if probe and probe.has_node("ProbeArea2D"):
		var area_node: Node = probe.get_node("ProbeArea2D")
		if area_node is Area2D:
			var area2d: Area2D = area_node as Area2D
			area2d.input_pickable = enabled
			area2d.monitoring = enabled


func _apply_shelf_guard_to_all_probes() -> void:
	## Zastosowanie „strażnika półki” do wszystkich probówek:
	## - probówki na półce nie są interaktywne i nie mają highlightu.
	for probe: Node in get_tree().get_nodes_in_group("probes"):
		var on_shelf: bool = _probe_is_in_shelved_rack(probe)
		_set_probe_interactive(probe, not on_shelf)
		if probe and probe.has_method("set_highlight_enabled") and on_shelf:
			probe.set_highlight_enabled(false)


func _probe_is_in_beaker(probe: Node) -> bool:
	## Sprawdza, czy probówka siedzi w zlewce (ProbeBeaker / probe_beaker).
	if probe == null:
		return false

	var node_it: Node = probe
	while node_it:
		var name_lower: String = str(node_it.name).to_lower()
		if name_lower == "probebeaker" or name_lower == "probe_beaker":
			return true
		node_it = node_it.get_parent()

	return false


# =============================================================================
# HELPERS / HOUSEKEEPING – sprzątanie stanów i narzędzia UI
# =============================================================================
func _reset_to_idle() -> void:
	## Ogólny „panic reset” do IDLE:
	## - zamyka butelkę, chowa pipetę,
	## - odkłada ewentualne narzędzia (bez animacji),
	## - odświeża highlighty i hover-y.
	if active_bottle and active_bottle.has_method("show_full"):
		active_bottle.show_full(true)

	active_bottle = null
	active_reagent_id = &""
	if pipette:
		pipette.visible = false

	if mode == Mode.TRANSFER and _dropper_can_put_back():
		_dropper_put_back(false)
	elif mode == Mode.INDICATOR and indicator_active:
		_indicator_put_back(false)
	elif mode == Mode.STIR_ROD:
		_stir_rod_put_back(false)
	elif mode == Mode.SQUIRT:
		_squirt_put_back(false)
	else:
		mode = Mode.IDLE

	_set_all_bottles_hover(true)
	_refresh_probe_highlights()
	_refresh_table_hovers()
	_update_dropper_ui()


func _clear_dropper_state() -> void:
	## Czyści wewnętrzny stan droppera (bez animacji / wizualek).
	dropper_loaded = false
	dropper_mix = null
	dropper_units = 0.0
	_press_mode = PressMode.NONE
	_pick_src = null
	_pour_dst = null


func _set_all_bottles_hover(enabled: bool) -> void:
	## Włącza/wyłącza hover dla wszystkich butelek (z wyjątkiem kursora pipety).
	var allow_hover: bool = enabled and _highlights_enabled_global
	for bottle_node: Node in get_tree().get_nodes_in_group("bottles"):
		if bottle_node and bottle_node.has_method("set_hover_enabled"):
			# PipetteCursor jest też w grupie "bottles", ale nie używa hovera.
			var skip_pipette: bool = (bottle_node is Node2D and bottle_node.name == "PipetteCursor")
			bottle_node.set_hover_enabled(allow_hover and not skip_pipette)


func _set_bottles_hover_except(only_this: Node) -> void:
	## Włącza hover tylko na jednej, aktywnej butelce.
	for bottle_node: Node in get_tree().get_nodes_in_group("bottles"):
		if bottle_node and bottle_node.has_method("set_hover_enabled"):
			var allow_hover: bool = (bottle_node == only_this) and _highlights_enabled_global
			bottle_node.set_hover_enabled(allow_hover)


func _set_all_probes_highlight(on: bool) -> void:
	## Włącza/wyłącza highlight na wszystkich probówkach (poza półką).
	var allow_highlight: bool = _highlights_enabled_global and on
	for probe: Node in get_tree().get_nodes_in_group("probes"):
		if probe and probe.has_method("set_highlight_enabled"):
			var final_on: bool = (allow_highlight and not _probe_is_in_shelved_rack(probe))
			probe.set_highlight_enabled(final_on)
		_set_probe_interactive(probe, not _probe_is_in_shelved_rack(probe))


func _ensure_probes_pickable() -> void:
	## Upewnia się, że wszystkie probówki mają włączony input pickable/monitoring na Area2D.
	for probe: Node in get_tree().get_nodes_in_group("probes"):
		if probe and probe.has_node("ProbeArea2D"):
			var area_node: Node = probe.get_node("ProbeArea2D")
			if area_node is Area2D:
				var area2d: Area2D = area_node as Area2D
				area2d.input_pickable = true
				area2d.monitoring = true
	_apply_shelf_guard_to_all_probes()


func _refresh_table_hovers() -> void:
	## Odświeża hover dla narzędzi leżących na stole.
	_update_dropper_table_hover()
	_update_indicator_table_hover()
	_update_stir_rod_table_hover()
	_update_squirt_table_hover()



func _can_pick_table_tool() -> bool:
	## Sprawdza, czy w danym momencie możemy w ogóle podnieść narzędzie ze stołu.
	return mode == Mode.IDLE \
		and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)



func _update_dropper_table_hover() -> void:
	## Ustawia hover na dropperze leżącym na stole.
	var can_highlight: bool = _can_pick_table_tool() and _highlights_enabled_global
	if dropper_on_table and dropper_on_table.has_method("set_hover_enabled"):
		dropper_on_table.set_hover_enabled(can_highlight)


func _update_indicator_table_hover() -> void:
	## Ustawia hover na pudełku z papierkiem.
	var can_highlight: bool = _can_pick_table_tool() and _highlights_enabled_global
	if indicator_box and indicator_box.has_method("set_hover_enabled"):
		indicator_box.set_hover_enabled(can_highlight)


func _update_stir_rod_table_hover() -> void:
	## Ustawia hover na bagietce leżącej na stole.
	var can_highlight: bool = _can_pick_table_tool() and _highlights_enabled_global
	if stir_rod_on_table and stir_rod_on_table.has_method("set_hover_enabled"):
		stir_rod_on_table.set_hover_enabled(can_highlight)


func _update_squirt_table_hover() -> void:
	## Ustawia hover na butelce z wodą na stole.
	var can_highlight: bool = _can_pick_table_tool() and _highlights_enabled_global
	if squirt_on_table and squirt_on_table.has_method("set_hover_enabled"):
		squirt_on_table.set_hover_enabled(can_highlight)


func _update_dropper_ui() -> void:
	## Aktualizuje mały „FillDot” na kursorze droppera (wizualizacja poziomu).
	if not dropper_cursor:
		return
	var fill: float = clamp(dropper_units / max(0.0001, dropper_capacity_units), 0.0, 1.0)

	var fill_dot: Node = dropper_cursor.get_node_or_null("FillDot")
	if fill_dot and fill_dot.has_method("set_fill01"):
		fill_dot.call("set_fill01", fill)


# =============================================================================
# PIPETTE RETURN (animowany „duch” wracający do butelki)
# =============================================================================
func _pipette_put_back(animated: bool = true) -> void:
	## Odkłada pipetę:
	## - resetuje stan aktywnej butelki,
	## - ewentualnie tworzy „ducha” pipety lecącego do butelki,
	## - na końcu przywraca hover-y i highlighty.
	if not pipette:
		return

	var target_bottle: Node = active_bottle

	mode = Mode.IDLE
	_set_all_bottles_hover(true)
	_refresh_table_hovers()
	_refresh_probe_highlights()

	active_bottle = null
	active_reagent_id = &""

	if _pipette_return_tween:
		_pipette_return_tween.kill()
		_pipette_return_tween = null
	if _pipette_return_ghost:
		_pipette_return_ghost.queue_free()
		_pipette_return_ghost = null
	_pipette_returning = false
	_pipette_return_target_bottle = null

	if not animated or target_bottle == null:
		pipette.visible = false
		if target_bottle and target_bottle.has_method("show_full"):
			target_bottle.show_full(true)
		return

	pipette.visible = false
	_pipette_return_ghost = pipette.duplicate() as Node2D
	add_child(_pipette_return_ghost)
	_pipette_return_ghost.global_position = pipette.global_position
	_pipette_return_ghost.z_index = pipette.z_index
	_pipette_return_ghost.visible = true

	_pipette_returning = true
	_pipette_return_target_bottle = target_bottle

	var target_pos: Vector2 = _get_anchor_global(target_bottle) + PIPETTE_OFFSET

	_pipette_return_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_pipette_return_tween.tween_property(_pipette_return_ghost, "global_position", target_pos, tool_return_time)
	_pipette_return_tween.finished.connect(func() -> void:
		if _pipette_return_target_bottle and _pipette_return_target_bottle.has_method("show_full"):
			_pipette_return_target_bottle.show_full(true)
		if _pipette_return_ghost:
			_pipette_return_ghost.queue_free()
		_pipette_return_ghost = null
		_pipette_return_tween = null
		_pipette_return_target_bottle = null
		_pipette_returning = false
		_refresh_table_hovers()
		_refresh_probe_highlights()
	)


# =============================================================================
# UTILS – pozycja „kotwicy” do animacji powrotu
# =============================================================================
func _get_anchor_global(node: Node) -> Vector2:
	## Zwraca globalną pozycję „kotwicy”:
	## - jeśli w węźle jest dziecko "Anchor" (Node2D),
	## - inaczej – global_position samego węzła (jeśli to Node2D),
	## - fallback: Vector2.ZERO.
	if node == null:
		return Vector2.ZERO
	var anchor: Node2D = node.get_node_or_null("Anchor") as Node2D
	if anchor:
		return anchor.global_position
	var node_2d: Node2D = node as Node2D
	if node_2d:
		return node_2d.global_position
	return Vector2.ZERO


# =============================================================================
# PUBLICZNE API DRAG-GUARD (dla Probe.gd)
# =============================================================================
func probe_drag_started() -> void:
	## Wołane przez Probe.gd przy rozpoczęciu przeciągania probówki.
	_probe_drag_active = true
	_refresh_probe_highlights()


func probe_drag_ended() -> void:
	## Wołane przez Probe.gd po zakończeniu przeciągania probówki.
	_probe_drag_active = false
	_refresh_probe_highlights()
