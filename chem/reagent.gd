extends Resource
class_name Reagent
# Opis odczynnika, dolewanego z reagent_bottle porcjami „na klik”.

# Id dla silnika
@export var id: String = ""

# Nazwa wyświetlana (etykieta na butelce)
@export var display_name: String = ""

# Kolor cieczy w butelce
@export var liquid_color: Color = Color.WHITE

# Skład jonowy w jednej porcji (np. HCl  → {"H+": 1.0, "Cl-": 1.0}
@export var ions: Dictionary = {}

# Objętość jednej porcji (vol_u w probówce)
@export var vol_per_click: float = 0.1

# Licznik nadmiaru jonu "_excess_<KEY>" w mieszaninie.
@export var excess_key: String = ""

# Liczba jednostek nadmiaru jonu na jeden klik.
@export var excess_per_click: float = 0.0
