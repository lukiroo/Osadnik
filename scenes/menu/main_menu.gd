extends Control

## =========================================================================
## MainMenu.gd – ekran startowy
## -------------------------------------------------------------------------
## Odpowiada za główne menu gry:
## - pokazuje przyciski Start / Ustawienia / Wyjście,
## - pozwala zmienić podświetlenia i etykiety probówek,
## - synchronizuje checkboxy z autoloadem Settings.
## =========================================================================

# Główna kolumna z przyciskami
@onready var menu_buttons: VBoxContainer = $ButtonsMargin/ButtonContainer
# Panel z ustawieniami
@onready var settings_panel: Panel = $SettingsPanel

# Checkboxy w panelu
@onready var highlight_checkbox: CheckBox = $SettingsPanel/VBox/HBoxHighlights/CheckBox
@onready var labels_checkbox:   CheckBox = $SettingsPanel/VBox/HBoxTubeLabels/CheckBox


## Inicjalizuje ekran menu, ustawia widoczność paneli i wczytuje aktualne ustawienia checkboxów z autoloada Settings.
func _ready() -> void:
	# Na start pokazuje menu, ukrywa panel ustawień
	menu_buttons.visible = true
	settings_panel.visible = false

	# Zaciągnięcie wartości z Settings
	highlight_checkbox.button_pressed = Settings.highlights_enabled
	labels_checkbox.button_pressed    = Settings.show_tube_labels

	# Reakcja na zmianę Settings (np. z innej sceny)
	if not Settings.changed.is_connected(_on_settings_changed):
		Settings.changed.connect(_on_settings_changed)


# ====================== CALLBACK Z SETTINGS =======================

## Aktualizuje stan checkboxów, gdy ustawienia w autoloadzie Settings ulegną zmianie.
func _on_settings_changed() -> void:
	highlight_checkbox.button_pressed = Settings.highlights_enabled
	labels_checkbox.button_pressed    = Settings.show_tube_labels


# ====================== CHECKBOXY W OPCJACH ======================

## Zapisuje w Settings, czy podświetlenia są włączone.
func _on_highlight_toggled(is_on: bool) -> void:
	Settings.set_highlight_enabled(is_on)


## Zapisuje w Settings stan etykiet probówek oraz prosi otwarty lab o przeetykietowanie, jeśli jest załadowany.
func _on_labels_toggled(is_on: bool) -> void:
	Settings.set_show_tube_labels(is_on)
	_refresh_labels_in_loaded_lab()


## Wywołuje w Settings reset_progress() i czyści cały progres leveli (gwiazdki, zaliczenia).
func _on_reset_progress_pressed() -> void:
	Settings.reset_progress()

# ======================= PRZYCISKI W MENU ========================

## Przełącza scenę na ekran wyboru poziomu (LevelSelect).
func _on_start_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/menu/level_select.tscn")


## Chowa główne menu i pokazuje panel ustawień.
func _on_settings_button_pressed() -> void:
	menu_buttons.visible = false
	settings_panel.visible = true


## Wraca z panelu ustawień do głównego menu.
func _on_back_button_pressed() -> void:
	menu_buttons.visible = true
	settings_panel.visible = false


## Kończy działanie gry.
func _on_exit_button_pressed() -> void:
	get_tree().quit()


# ======================== POMOCNICZE =============================

## Jeśli scena labu jest załadowana, wywołuje na LevelManagerze relabel_now(), żeby odświeżyć widoczność etykiet probówek.
func _refresh_labels_in_loaded_lab() -> void:
	var lab_root := get_tree().get_first_node_in_group("lab_root")
	if lab_root == null:
		return

	var level_manager := lab_root.get_node("LevelManager")
	level_manager.relabel_now()
