extends Node2D  ## Główny węzeł sceny stołu laboratoryjnego – centralny kontroler logiki widoku „lab”.

## =========================================================================
## lab.gd – główny kontroler stołu (tryby, narzędzia, highlighty)
## -------------------------------------------------------------------------
## Odpowiada za:
## - pilnowanie globalnego trybu interakcji:
##   IDLE / HOLDING (pipeta) / TRANSFER (dropper) / INDICATOR (papierek) /
##   STIR_ROD (bagietka) / SQUIRT (butelka z wodą),
## - sterowanie „kursorami” narzędzi (pipeta, dropper, papierek wskaźnikowy,
##   bagietka, butelka z wodą) i ich odpowiednikami leżącymi na stole,
## - integrację z LevelManagerem (tryb: ćwiczenie 1/2, egzamin, sandbox;
##   gałąź: kationy / aniony / sandbox),
## - zarządzanie highlightami probówek (co można kliknąć, co jest zablokowane,
##   co stoi na półce),
## - obsługę strumieni pobierania / przelewania / dolewania wody (procesy
##   działające podczas przytrzymania LPM),
## - spójne odkładanie narzędzi (PPM / ESC) i blokady tak, aby narzędzia
##   nie kolidowały ze sobą.
## =========================================================================

@onready var level_manager: LevelManager = $LevelManager      ## Odpowiada za tryb ćwiczenia, gałąź (kationy / aniony / sandbox) i poprawne odpowiedzi.
@onready var back_btn: TextureButton = $BackBtn
@onready var finish_btn: TextureButton = $FinishBtn

const DEBUG_LOG_FINISH_CTX := false                          ## Flaga do debugowego logowania kontekstu przy „Zakończ”.

# ==============================
# TRYBY GLOBALNE STOŁU
# ==============================
enum Mode { IDLE, HOLDING, TRANSFER, INDICATOR, STIR_ROD, SQUIRT }
var mode: Mode = Mode.IDLE   ## Aktualny tryb pracy stołu – określa, co robią kliknięcia myszy.

@export_group("Tools Parameters")
@export var tool_return_time: float = 0.6                    ## Czas animacji odkładania narzędzia na stół (pipeta / dropper / bagietka / butelka).

var _probe_drag_active: bool = false                         ## Czy jakaś probówka jest aktualnie przeciągana (drag).
var _rmb_down_prev: bool = false                             ## Poprzedni stan prawego przycisku myszy – do wykrywania zmiany.

## Globalny stan highlightów pobierany z autoloada Settings (czy w ogóle podświetla obiekty).
var _highlights_enabled_global: bool = true

# ==============================
# PIPETA (HOLDING – butelki z reagentami)
# ==============================
var active_bottle: Node = null                               ## Aktualnie „aktywna” butelka (ta, z której kapie reagent).
var active_reagent_id: StringName = &""                      ## Id reagentu z aktywnej butelki – przekazywane do QualEngine.

@onready var pipette: Node2D = $PipetteCursor                ## Kursor pipety (grafika podążająca za myszą).
const PIPETTE_OFFSET: Vector2 = Vector2(8, -50)              ## Przesunięcie pipety względem fizycznego kursora myszy.

var _pipette_returning: bool = false                         ## Czy trwa animacja „ducha” pipety wracającego do butelki.
var _pipette_return_target_bottle: Node = null               ## Butelka, do której wraca pipeta w animacji.
var _pipette_return_tween: Tween = null
var _pipette_return_ghost: Node2D = null                     ## Tymczasowy duplikat pipety używany tylko do animacji powrotu.

# ==============================
# DROPPER (TRANSFER – pobieranie/przelewanie)
# ==============================
@onready var dropper_cursor: Node2D = $DropperCursor         ## Dropper jako narzędzie „w ręku” – przypięty do kursora.
@onready var dropper_on_table: Node2D = $DropperOnTable      ## Dropper leżący na stole – kliknięcie go podnosi.

@export var dropper_capacity_units: float = 1.00             ## Umowna pojemność droppera (w jednostkach zgodnych z Mixture.vol_u).
@export var pickup_rate_units_per_sec: float = 0.50          ## Ile units/s dropper zasysa z probówki.
@export var pour_rate_units_per_sec: float = 0.60            ## Ile units/s dropper wylewa do probówki.

var dropper_loaded: bool = false                             ## Czy dropper zawiera aktualnie ciecz.
var dropper_mix: Mixture = null                              ## Mieszanina aktualnie w dropperze (model chemiczny).
var dropper_units: float = 0.0                               ## Ile „units” cieczy siedzi w dropperze (spójne z vol_u).

enum PressMode { NONE, PICKING, POURING }                    ## Pod-tryb droppera – pobieranie (PICKING) lub wylewanie (POURING).
var _press_mode: PressMode = PressMode.NONE
var _pick_src: Node = null                                   ## Probówka źródłowa przy pobieraniu do droppera.
var _pour_dst: Node = null                                   ## Probówka docelowa przy wylewaniu z droppera.

const DROPPER_OFFSET: Vector2 = Vector2(8, -40)              ## Offset kursorowego droppera względem myszy.

# ==============================
# WSKAŹNIK (PAPIEREK)
# ==============================
var indicator_paper_scene: PackedScene = preload("res://scenes/indicator_paper.tscn")
@onready var indicator_box: Node2D = $IndicatorBox           ## „Pudełko” na papierek, leżące na stole.

var indicator_active: bool = false                           ## Czy papierek wskaźnikowy jest obecnie w użyciu i śledzi mysz.
var indicator_paper: IndicatorPaper = null                   ## Aktualna instancja papierka – jednorazowa, potem usuwana.

# ==============================
# BAGIETKA (STIR ROD)
# ==============================
@onready var stir_rod_on_table: Node2D = $StirRodOnTable     ## Bagietka leżąca na stole.
@onready var stir_rod_cursor: Node2D = $StirRodCursor        ## Bagietka w ręku (kursor).

const STIR_ROD_OFFSET: Vector2 = Vector2(6, -28)             ## Offset bagietki względem kursora myszy.

# ==============================
# SQUIRT BOTTLE (BUTELKA Z WODĄ)
# ==============================
@onready var squirt_on_table: Node2D = $SquirtBottleOnTable  ## Butelka z wodą na stole.
@onready var squirt_cursor: Node2D = $SquirtBottleCursor     ## Butelka „w ręku” – przypięta do kursora myszy.

const SQUIRT_OFFSET: Vector2 = Vector2(8, -40)               ## Offset butelki względem myszy.

@export var squirt_rate_units_per_sec: float = 0.60          ## Tempo dolewania wody [units/s] – ile jednostek na sekundę dodaje.
var _squirt_active: bool = false                             ## Czy jest w trybie SQUIRT (butelka w ręku).
var _squirt_dst: Node = null                                 ## Probówka docelowa, do której wlewa wodę.
var _squirt_lmb_down: bool = false                           ## Czy LPM jest trzymany podczas wlewania (ciągły strumień).


# =============================================================================
# INICJALIZACJA W SCENIE
# =============================================================================

## Inicjalizuje scenę stołu:
## - dodaje węzeł do grupy "lab_root",
## - synchronizuje flagi z autoloadem Settings,
## - podpina sygnały narzędzi i butelek,
## - ustawia stan startowy highlightów i hoverów.
func _ready() -> void:
	add_to_group("lab_root")

	# W sandboxie przy prostych eksperymentach przycisk „Zakończ” nie jest potrzebny.
	if level_manager.is_sandbox_branch() and finish_btn:
		finish_btn.visible = false

	# Kopiuje stan opcji highlightów z autoloada Settings.
	_highlights_enabled_global = Settings.highlights_enabled
	if not Settings.changed.is_connected(_on_settings_changed):
		Settings.changed.connect(_on_settings_changed)

	# Butelka z wodą na stole (squirt).
	if squirt_on_table:
		squirt_on_table.visible = true
		if squirt_on_table.has_signal("left_clicked"):
			squirt_on_table.left_clicked.connect(_on_squirt_on_table_clicked)

	# Podpina butelki z reagentami (grupa "bottles").
	for bottle_node: Node in get_tree().get_nodes_in_group("bottles"):
		if bottle_node and bottle_node.has_signal("left_clicked"):
			bottle_node.left_clicked.connect(_on_bottle_left_clicked)

	# Podnoszenie droppera ze stołu.
	if dropper_on_table and dropper_on_table.has_signal("left_clicked"):
		dropper_on_table.left_clicked.connect(_on_dropper_on_table_clicked)

	# Papierek wskaźnikowy.
	if indicator_box and indicator_box.has_signal("left_clicked"):
		indicator_box.left_clicked.connect(_on_indicator_box_clicked)

	# Bagietka leżąca na stole + sygnał anulowania z kursora bagietki.
	if stir_rod_on_table and stir_rod_on_table.has_signal("left_clicked"):
		stir_rod_on_table.left_clicked.connect(_on_stir_rod_on_table_clicked)

	if stir_rod_cursor and stir_rod_cursor.has_signal("cancel_requested"):
		stir_rod_cursor.cancel_requested.connect(_on_stir_rod_cancel)

	# Upewnia się, że probówki mają poprawnie ustawiony input pickable/monitoring.
	_ensure_probes_pickable()

	# Początkowe ustawienia hoverów i highlightów.
	_set_all_bottles_hover(true)
	_set_all_probes_highlight(false)
	_refresh_table_hovers()
	_update_dropper_ui()
	_refresh_probe_highlights()
	# Drugi refresh po 1 klatce – zabezpiecza przypadek, gdy racki/probówki zmienią pozycję w _ready.
	call_deferred("_refresh_probe_highlights")


## Obsługuje logikę w każdej klatce:
## - przesuwa narzędzia przypięte do kursora za myszą,
## - aktualizuje strumienie (pobieranie, przelewanie, dolewanie),
## - odświeża UI droppera i highlighty przy zmianie stanu PPM.
func _process(delta: float) -> void:
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

## Reaguje na sygnał Settings.changed:
## - aktualizuje globalną flagę highlightów,
## - odświeża hover-y stołu i highlighty probówek.
func _on_settings_changed() -> void:
	_highlights_enabled_global = Settings.highlights_enabled
	_refresh_table_hovers()
	_refresh_probe_highlights()
	_set_all_bottles_hover(true)


# =============================================================================
# INPUT (GLOBAL) – RMB, ESC i kończenie strumieni
# =============================================================================

## Obsługuje globalne zdarzenia wejścia:
## - puszczenie LPM kończy strumienie PICKING / POURING / SQUIRT,
## - PPM próbuje odłożyć aktualne narzędzie,
## - ESC odkłada wybrane narzędzia i wraca do IDLE.
func _unhandled_input(event: InputEvent) -> void:
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
# ZAKOŃCZENIE – powrót / zapis kontekstu i przejście do wyników
# =============================================================================

## Obsługuje kliknięcie „Wróć”:
## - w sandboxie wraca do głównego menu,
## - w gałęzi anionowej do wyboru poziomu anionów,
## - w pozostałych przypadkach do wyboru poziomu kationów.
func _on_back_btn_pressed() -> void:
	if level_manager.is_sandbox_branch():
		get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")
	elif level_manager.is_anions_branch():
		get_tree().change_scene_to_file("res://scenes/menu/level_select_anions.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/menu/level_select_cations.tscn")


## Obsługuje kliknięcie „Zakończ”:
## - buduje kontekst podejścia (tryb, grupa, poprawne odpowiedzi),
## - zapisuje go w Settings jako last_run_context,
## - przełącza scenę na ekran wyników kationów lub anionów.
func _on_finish_btn_pressed() -> void:
	if level_manager.is_sandbox_branch():
		return  # w sandboxie „Zakończ” nie ma sensu – brak ocenianych wyników

	# Tryb i grupa z LevelManagera.
	var mode_str: String = _mode_to_string(level_manager.mode)
	var group_id: int = level_manager.group_id

	# Kontekst z domyślnie pustymi listami/mapami.
	var ctx: Dictionary = {
		"mode_str": mode_str,
		"group_id": group_id,
		"single_answer_map": {},
		"mix_answer_list": []
	}

	if mode_str == "EXERCISE_SINGLE":
		ctx["single_answer_map"] = level_manager.get_single_answer_map()
		if DEBUG_LOG_FINISH_CTX:
			var answer_map: Dictionary = ctx["single_answer_map"] as Dictionary
			print("[Lab] single_answer_map.size() = ", answer_map.size())
	elif mode_str == "EXERCISE_MIX":
		ctx["mix_answer_list"] = level_manager.get_mix_answer_list()
		if DEBUG_LOG_FINISH_CTX:
			var answer_list: Array = ctx["mix_answer_list"] as Array
			print("[Lab] mix_answer_list = ", answer_list)

	# Zapisuje kontekst podejścia niezależnie od trybu.
	Settings.set_last_run_context(ctx)

	if DEBUG_LOG_FINISH_CTX:
		print_rich(
			"[color=yellow][Lab] ctx zapisany: mode=", ctx.get("mode_str"),
			", group=", ctx.get("group_id"),
			", single_keys=", ((ctx["single_answer_map"] as Dictionary).keys() if ctx.has("single_answer_map") else []),
			", mix=", (ctx["mix_answer_list"] if ctx.has("mix_answer_list") else []),
			"[/color]"
		)

	# Przechodzi na odpowiedni ekran wyników.
	if level_manager.is_cations_branch():
		get_tree().change_scene_to_file("res://scenes/menu/results_cations.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/menu/results_anions.tscn")


## Konwertuje tryb z LevelManager.Mode na string dla kontekstu Results:
## - 1 → EXERCISE_SINGLE,
## - 2 → EXERCISE_MIX,
## - pozostałe → SANDBOX.
func _mode_to_string(mode_value: int) -> String:
	match mode_value:
		1:
			return "EXERCISE_SINGLE"
		2:
			return "EXERCISE_MIX"
		_:
			return "SANDBOX"



# =============================================================================
# HOLDING (pipeta + butelki z reagentami)
# =============================================================================

## Obsługuje kliknięcie w butelkę z reagentem:
## - w IDLE podnosi pipetę i ustawia stan „pusta butelka” (show_empty),
## - w HOLDING na tej samej butelce odkłada pipetę i przywraca show_full.
func _on_bottle_left_clicked(bottle: Node) -> void:
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


## Czyści stan pipety i wraca do IDLE (bez animacji „ducha”).
func _reset_pipette_only() -> void:
	if pipette:
		pipette.visible = false
	mode = Mode.IDLE
	active_reagent_id = &""
	active_bottle = null
	_refresh_table_hovers()


# =============================================================================
# TRANSFER (dropper) – podnoszenie/odkładanie + strumienie
# =============================================================================

## Obsługuje kliknięcie droppera na stole – podnosi go tylko w IDLE.
func _on_dropper_on_table_clicked(_stand: Node) -> void:
	if mode != Mode.IDLE:
		return
	_dropper_take_from_table()


## Podnosi dropper ze stołu:
## - przechodzi w tryb TRANSFER,
## - resetuje stan droppera,
## - chowa wersję „na stole” i pokazuje wersję kursorową,
## - aktualizuje hover-y i highlighty.
func _dropper_take_from_table() -> void:
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


## Sprawdza, czy dropper można odstawić (tylko gdy jest pusty).
func _dropper_can_put_back() -> bool:
	return not dropper_loaded and dropper_units <= 0.000001


## Odkłada dropper na stół (opcjonalnie z animacją powrotu).
## Przywraca IDLE, hover-y i czyści stan droppera.
func _dropper_put_back(animated: bool = false) -> void:
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


## Daje krótką animację „wstrząśnięcia”, gdy użytkownik próbuje odłożyć pełny dropper.
func _dropper_deny_put_back_feedback() -> void:
	if not dropper_cursor:
		return
	var base_rotation: float = dropper_cursor.rotation_degrees
	var tween: Tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(dropper_cursor, "rotation_degrees", base_rotation + 7.0, 0.06)
	tween.tween_property(dropper_cursor, "rotation_degrees", base_rotation - 7.0, 0.10)
	tween.tween_property(dropper_cursor, "rotation_degrees", base_rotation, 0.06)


## Startuje strumień zasysania cieczy do droppera (LPM na probówce).
## Wymaga trybu TRANSFER, pustego droppera i odblokowanej probówki.
func _dropper_pick(source_probe: Node) -> void:
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


## Startuje strumień przelewania z droppera do probówki docelowej.
## Wymaga trybu TRANSFER, załadowanego droppera i odblokowanej probówki.
func _dropper_drop(target_probe: Node) -> void:
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


## Jedna klatka pobierania do droppera:
## - oblicza ile units wciągnąć,
## - wywołuje take_volume na probówce źródłowej,
## - scala mieszaniny w dropperze i aktualizuje dropper_units.
func _tick_pick(delta: float) -> void:
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

	var previously_loaded: bool = dropper_loaded
	dropper_loaded = (dropper_units > 0.000001)
	if dropper_loaded and not previously_loaded:
		_refresh_probe_highlights()

	if dropper_units >= dropper_capacity_units - 0.000001:
		_press_mode = PressMode.NONE
		_pick_src = null


## Jedna klatka wylewania z droppera do probówki:
## - wycina porcję mieszaniny (scaled_fraction),
## - przekazuje ją docelowej probówce,
## - aktualizuje dropper_mix i dropper_units o zaakceptowaną część.
func _tick_pour(delta: float) -> void:
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

## Tworzy porcję mieszaniny do wylania z droppera:
## - używa scaled_fraction na Mixture,
## - czyści tags (pH liczy QualEngine na docelowej probówce).
func _dropper_make_portion(source_mix: Mixture, fraction_value: float) -> Mixture:
	var clamped_fraction: float = clamp(fraction_value, 0.0, 1.0)
	var portion: Mixture = source_mix.scaled_fraction(clamped_fraction, false)
	portion.tags = {}
	return portion


## Odejmuje z mieszaniny w dropperze ułamek, który został wylany:
## - używa subtract_fraction_in_place,
## - usuwa ph_samples i pH z tags.
func _dropper_apply_fraction_loss(target_mix: Mixture, fraction_value: float) -> void:
	var clamped_fraction: float = clamp(fraction_value, 0.0, 1.0)
	target_mix.subtract_fraction_in_place(clamped_fraction, false)
	if target_mix.tags is Dictionary:
		(target_mix.tags as Dictionary).erase("pH")
		(target_mix.tags as Dictionary).erase("ph_samples")


## Scala dwie mieszaniny w dropperze ekstensywnie (bez uśredniania) i czyści ph_samples.
func _dropper_merge_extensive(target_mix: Mixture, source_mix: Mixture) -> void:
	if target_mix == null or source_mix == null:
		return
	target_mix.merge_from(source_mix)
	if target_mix.tags is Dictionary and (target_mix.tags as Dictionary).has("ph_samples"):
		(target_mix.tags as Dictionary).erase("ph_samples")


# =============================================================================
# INDICATOR (papierek) – podnoszenie/odkładanie i użycie
# =============================================================================

## Obsługuje kliknięcie pudełka z papierkiem:
## - w IDLE podnosi nowy papierek (INDICATOR),
## - w INDICATOR odkłada aktualny papierek.
func _on_indicator_box_clicked(_box: Node) -> void:
	if mode not in [Mode.IDLE, Mode.INDICATOR]:
		return
	if indicator_active:
		_indicator_put_back(true)
	else:
		_indicator_pick()


## Podnosi nowy papierek wskaźnikowy:
## - tworzy instancję IndicatorPaper,
## - włącza śledzenie myszy i łączy sygnał used_on_probe,
## - przełącza tryb na INDICATOR.
func _indicator_pick() -> void:
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


## Reaguje na użycie papierka na probówce:
## - po zużyciu odświeża highlighty (stan próbki mógł się zmienić).
func _on_indicator_used(_probe: Node, _grade: int) -> void:
	_refresh_probe_highlights()


## Odkłada papierek do pudełka:
## - przełącza tryb na IDLE,
## - animuje powrót (opcjonalnie),
## - usuwa instancję papierka.
func _indicator_put_back(animated: bool = false) -> void:
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


## Używa papierka na konkretnej probówce:
## - odrzuca probówki na półce, puste i zablokowane,
## - pobiera grade z get_indicator_grade i przekazuje do papierka.
func _indicator_use_on_probe(probe: Node) -> void:
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


## Publiczny alias do _indicator_use_on_probe (np. z Probe.gd).
func _indicator_use(probe: Node) -> void:
	_indicator_use_on_probe(probe)


# =============================================================================
# BAGIETKA (stir rod) – podnoszenie/odkładanie i użycie
# =============================================================================

## Obsługuje kliknięcie bagietki na stole – podnosi ją tylko w IDLE.
func _on_stir_rod_on_table_clicked(_node: Node) -> void:
	if mode != Mode.IDLE:
		return
	_stir_rod_take_from_table()


## Podnosi bagietkę ze stołu:
## - przechodzi w tryb STIR_ROD,
## - pokazuje kursorową wersję,
## - chowa bagietkę na stole i aktualizuje highlighty.
func _stir_rod_take_from_table() -> void:
	mode = Mode.STIR_ROD

	if stir_rod_cursor:
		stir_rod_cursor.visible = true
		stir_rod_cursor.global_position = get_global_mouse_position() + STIR_ROD_OFFSET
	if stir_rod_on_table:
		stir_rod_on_table.visible = false

	_set_all_bottles_hover(false)
	_refresh_probe_highlights()
	_refresh_table_hovers()


## Odkłada bagietkę na stół i wraca do IDLE (z animacją lub bez).
func _stir_rod_put_back(animated: bool = true) -> void:
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


## Reaguje na sygnał anulowania bagietki z kursora – odkłada bagietkę.
func _on_stir_rod_cancel() -> void:
	_stir_rod_put_back(true)


## Używa bagietki na probówce:
## - ignoruje probówki na półce, puste i zablokowane,
## - wywołuje stir_with_rod na probówce,
## - odpala efekt „mix_wobble” na kursorze bagietki.
func _stir_rod_use_on_probe(probe: Node) -> void:
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

## Obsługuje kliknięcie butelki z wodą na stole – podnosi ją tylko w IDLE.
func _on_squirt_on_table_clicked(_node: Node) -> void:
	if mode != Mode.IDLE:
		return
	_squirt_take_from_table()


## Podnosi butelkę z wodą:
## - przechodzi w tryb SQUIRT,
## - resetuje stan strumienia,
## - pokazuje kursorową butelkę, chowa tę na stole,
## - wyłącza hover-y na butelkach z reagentami.
func _squirt_take_from_table() -> void:
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


## Odkłada butelkę z wodą na stół i wychodzi z trybu SQUIRT.
func _squirt_put_back(animated: bool = true) -> void:
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


## Startuje ciągłe dolewanie wody do probówki (LPM na probówce w trybie SQUIRT).
func _squirt_begin(target_probe: Node) -> void:
	if target_probe and _probe_is_in_shelved_rack(target_probe):
		return
	if mode != Mode.SQUIRT:
		return
	if not target_probe or not target_probe.has_method("receive_mixture"):
		return
	if _locked(target_probe):
		return
	_squirt_dst = target_probe
	_squirt_lmb_down = true
	get_viewport().set_input_as_handled()


## Zatrzymuje strumień dolewania wody (bez odkładania butelki).
func _squirt_end() -> void:
	_squirt_lmb_down = false
	_squirt_dst = null


## Jedna klatka strumienia wody:
## - kończy, gdy LPM został puszczony,
## - pilnuje przepełnienia probówki,
## - tworzy czystą wodę jako Mixture i przekazuje do probówki.
func _tick_squirt(delta: float) -> void:
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

## Sprawdza, czy probówka jest zablokowana do interakcji:
## - stoi w racku na półce (shelf guard),
## - albo ma are_interactions_enabled() == false.
func _locked(node: Node) -> bool:
	if node and _probe_is_in_shelved_rack(node):
		return true
	return (
		node
		and node.has_method("are_interactions_enabled")
		and not bool(node.are_interactions_enabled())
	)


## Sprawdza, czy probówka zawiera jakąkolwiek ciecz (czy ma sens na niej pracować).
func _has_liquid(probe: Node) -> bool:
	if probe and probe.has_method("has_any_liquid"):
		return bool(probe.has_any_liquid())
	if probe and probe.has_method("get"):
		var level: Variant = probe.get("fill_level")
		if level is float or level is int:
			return float(level) > 0.001
	return false


## Sprawdza, czy probówka jest pełna (jeśli ma is_full()).
func _is_full(probe: Node) -> bool:
	return (probe and probe.has_method("is_full") and bool(probe.is_full()))


## Nakłada highlight na probówki wg podanego predykatu:
## - jeśli globalne highlighty są wyłączone, wyłącza wszystkie,
## - ignoruje probówki na półce.
func _set_highlights_by(predicate: Callable) -> void:
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


## Główna logika highlightów probówek:
## - w IDLE pokazuje wszystkie dostępne probówki (bez półki / zlewek),
## - w innych trybach podświetla tylko sensowne cele dla danego narzędzia,
## - w trakcie dragu probówek wyłącza highlighty.
func _refresh_probe_highlights() -> void:
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

## Sprawdza, czy probówka stoi w racku, który jest na półce (rack._is_on_shelf()).
func _probe_is_in_shelved_rack(probe: Node) -> bool:
	if probe == null:
		return false

	var current: Node = probe
	var rack: ProbeRack = null
	while current:
		if current is ProbeRack:
			rack = current as ProbeRack
			break
		current = current.get_parent()

	if rack == null:
		return false

	return rack._is_on_shelf()


## Włącza/wyłącza input pickable + monitoring dla Area2D probówki.
func _set_probe_interactive(probe: Node, enabled: bool) -> void:
	if probe and probe.has_node("ProbeArea2D"):
		var area_node: Node = probe.get_node("ProbeArea2D")
		if area_node is Area2D:
			var area2d: Area2D = area_node as Area2D
			area2d.input_pickable = enabled
			area2d.monitoring = enabled


## Nakłada „strażnika półki” na wszystkie probówki:
## - probówki na półce są nieinteraktywne i bez highlightu.
func _apply_shelf_guard_to_all_probes() -> void:
	for probe: Node in get_tree().get_nodes_in_group("probes"):
		var on_shelf: bool = _probe_is_in_shelved_rack(probe)
		_set_probe_interactive(probe, not on_shelf)
		if probe and probe.has_method("set_highlight_enabled") and on_shelf:
			probe.set_highlight_enabled(false)


## Sprawdza, czy probówka znajduje się w zlewce ProbeBeaker1 / ProbeBeaker2 / ProbeBeaker3.
func _probe_is_in_beaker(probe: Node) -> bool:
	if probe == null:
		return false

	var current: Node = probe
	while current:
		if current.name == "ProbeBeaker1" \
		or current.name == "ProbeBeaker2" \
		or current.name == "ProbeBeaker3":
			return true
		current = current.get_parent()

	return false



# =============================================================================
# HELPERS / HOUSEKEEPING – sprzątanie stanów i narzędzia UI
# =============================================================================

## Ogólny reset stanu stołu:
## - zamyka ewentualną butelkę i chowa pipetę,
## - odkłada aktywne narzędzia, gdy jest to możliwe,
## - wraca do IDLE i odświeża UI.
func _reset_to_idle() -> void:
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


## Czyści wewnętrzny stan droppera (bez animacji).
func _clear_dropper_state() -> void:
	dropper_loaded = false
	dropper_mix = null
	dropper_units = 0.0
	_press_mode = PressMode.NONE
	_pick_src = null
	_pour_dst = null


## Ustawia hover dla wszystkich butelek (z pominięciem PipetteCursor).
func _set_all_bottles_hover(enabled: bool) -> void:
	var allow_hover: bool = enabled and _highlights_enabled_global
	for bottle_node: Node in get_tree().get_nodes_in_group("bottles"):
		if bottle_node and bottle_node.has_method("set_hover_enabled"):
			var skip_pipette: bool = (bottle_node is Node2D and bottle_node.name == "PipetteCursor")
			bottle_node.set_hover_enabled(allow_hover and not skip_pipette)


## Włącza hover tylko na wskazanej butelce – pozostałe wyłącza.
func _set_bottles_hover_except(only_this: Node) -> void:
	for bottle_node: Node in get_tree().get_nodes_in_group("bottles"):
		if bottle_node and bottle_node.has_method("set_hover_enabled"):
			var allow_hover: bool = (bottle_node == only_this) and _highlights_enabled_global
			bottle_node.set_hover_enabled(allow_hover)


## Włącza/wyłącza highlight na wszystkich probówkach (poza półką)
## i aktualizuje im interaktywność.
func _set_all_probes_highlight(on: bool) -> void:
	var allow_highlight: bool = _highlights_enabled_global and on
	for probe: Node in get_tree().get_nodes_in_group("probes"):
		if probe and probe.has_method("set_highlight_enabled"):
			var final_on: bool = (allow_highlight and not _probe_is_in_shelved_rack(probe))
			probe.set_highlight_enabled(final_on)
		_set_probe_interactive(probe, not _probe_is_in_shelved_rack(probe))


## Upewnia się, że wszystkie probówki mają włączone pickable/monitoring,
## a następnie aplikuje reguły „shelf guard”.
func _ensure_probes_pickable() -> void:
	for probe: Node in get_tree().get_nodes_in_group("probes"):
		if probe and probe.has_node("ProbeArea2D"):
			var area_node: Node = probe.get_node("ProbeArea2D")
			if area_node is Area2D:
				var area2d: Area2D = area_node as Area2D
				area2d.input_pickable = true
				area2d.monitoring = true
	_apply_shelf_guard_to_all_probes()


## Odświeża hover dla narzędzi na stole (dropper, papierek, bagietka, squirt),
## tak aby były podświetlane tylko wtedy, gdy można je podnieść.
func _refresh_table_hovers() -> void:
	_update_dropper_table_hover()
	_update_indicator_table_hover()
	_update_stir_rod_table_hover()
	_update_squirt_table_hover()


## Sprawdza, czy aktualnie można podnieść narzędzie ze stołu:
## - wymagany tryb IDLE,
## - LPM nie może być trzymany.
func _can_pick_table_tool() -> bool:
	return mode == Mode.IDLE \
		and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


## Ustawia hover na dropperze leżącym na stole (gdy można go podnieść).
func _update_dropper_table_hover() -> void:
	var can_highlight: bool = _can_pick_table_tool() and _highlights_enabled_global
	if dropper_on_table and dropper_on_table.has_method("set_hover_enabled"):
		dropper_on_table.set_hover_enabled(can_highlight)


## Ustawia hover na pudełku z papierkiem (gdy można go podnieść).
func _update_indicator_table_hover() -> void:
	var can_highlight: bool = _can_pick_table_tool() and _highlights_enabled_global
	if indicator_box and indicator_box.has_method("set_hover_enabled"):
		indicator_box.set_hover_enabled(can_highlight)


## Ustawia hover na bagietce leżącej na stole.
func _update_stir_rod_table_hover() -> void:
	var can_highlight: bool = _can_pick_table_tool() and _highlights_enabled_global
	if stir_rod_on_table and stir_rod_on_table.has_method("set_hover_enabled"):
		stir_rod_on_table.set_hover_enabled(can_highlight)


## Ustawia hover na butelce z wodą leżącej na stole.
func _update_squirt_table_hover() -> void:
	var can_highlight: bool = _can_pick_table_tool() and _highlights_enabled_global
	if squirt_on_table and squirt_on_table.has_method("set_hover_enabled"):
		squirt_on_table.set_hover_enabled(can_highlight)


## Aktualizuje mały wskaźnik wypełnienia „FillDot” na kursorowym dropperze.
func _update_dropper_ui() -> void:
	if not dropper_cursor:
		return
	var fill: float = clamp(dropper_units / max(0.0001, dropper_capacity_units), 0.0, 1.0)

	var fill_dot: Node = dropper_cursor.get_node_or_null("FillDot")
	if fill_dot and fill_dot.has_method("set_fill01"):
		fill_dot.call("set_fill01", fill)


# =============================================================================
# PIPETTE RETURN (animowany „duch” wracający do butelki)
# =============================================================================

## Odkłada pipetę:
## - resetuje stan butelki (show_full),
## - opcjonalnie animuje „ducha” pipety wracającego do butelki,
## - na końcu czyści tymczasowe obiekty i odświeża highlighty.
func _pipette_put_back(animated: bool = true) -> void:
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

## Zwraca globalną pozycję „kotwicy” dla animacji:
## - jeśli węzeł ma dziecko "Anchor" (Node2D) – jego pozycję,
## - inaczej global_position węzła, gdy jest Node2D,
## - w przeciwnym razie Vector2.ZERO.
func _get_anchor_global(node: Node) -> Vector2:
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

## Wywoływane przez Probe.gd przy rozpoczęciu przeciągania probówki –
## wyłącza highlighty, aby nie migały w trakcie dragu.
func probe_drag_started() -> void:
	_probe_drag_active = true
	_refresh_probe_highlights()


## Wywoływane przez Probe.gd po zakończeniu przeciągania probówki –
## przywraca highlighty zgodnie z aktualnym trybem.
func probe_drag_ended() -> void:
	_probe_drag_active = false
	_refresh_probe_highlights()
