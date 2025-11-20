extends Resource
class_name Solid
# Opis typu osadu

# Id osadu, np. "AgCl_s"
@export var id: String = ""

# Nazwa wyświetlana
@export var display_name: String = ""

# Kolor osadu / mętności / kryształków
@export var color: Color = Color.WHITE

# Szybkość osiadania na dno
@export var settle_rate: float = 1.0
