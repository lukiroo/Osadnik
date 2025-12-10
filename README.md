# Symulator Klasycznej Analizy Jakościowej (Godot 4.5)
Interaktywna aplikacja edukacyjna odwzorowująca klasyczne metody analizy jakościowej wg systemu grupowego 

---

## Funkcje główne

### Przyrządy laboratoryjne
- **Zakraplacz** – pobieranie reagentów z butelek.
- **Pipeta** – pobieranie i przelewanie z probówek.
- **Tryskawka z wodą** – ciągłe dolewanie z ograniczeniem pojemności.
- **Papierek wskaźnikowy** – analiza pH bez podglądu wartości liczbowych.
- **Bagietka** – mieszanie, przywrócenie odwirowanego osadu do postaci zawieszonej.

### Urządzenia laboratoryjne
- **Wirówka** – pOdwirowywanie osadu do zbitego pelletu na dnie probówki.
- **Łaźnia wodna** – ogrzewanie probówek w celu przeprowadzenia reakcji wymagających temperatury.

### Reagenty i butelki
- Wszystkie reagenty wczytywane automatycznie z /data/reagents/*.tres.
- Buteleczki spawnują się automatycznie w zależności od poziomu ćwiczenia.
- Obsługa różnych grup analitycznych, w tym mieszanek wielojonowych.

### System poziomów, trybów i punktacji
- Ćwiczenia dla grup kationów i anionów.
- Tryby:
  - *Single-ion* – pojedynczy jon do zidetyfikowania w każdej probówce.
  - *Mix* – 2–3 kationy w mieszaninie w jednej probówce.
  - poziomy trudności: Normalny i Trudny (zmiana liczby jonów do identyfikacji).
- NAstępne zadanie odblokowywane po zaliczeniu poprzedniego poziomu.
- Zadanie końcowe z analizy wszystkiego odblokowywane po zaliczeniu wszystkich grup.
- Punktacja wg liczby błędów.

## Sterowanie
- **LPM** - Podnoszenie narzędzi, pobieranie, przelewanie, użycie papirka
- **PPM** - Odkładanie aktualnego narzędzia
- **Scroll** - Przybliżanie/oddalanie widoku
- **WASD/Strzałki** - Ruchy kamerą
- **ESC** - Szybki reset narzędzia do stołu
- **Drag & Drop** - Przenoszenie probówek 


### Ogólna architektura
- `LevelManager.gd` – logika ćwiczeń, odpowiedzi i spawn probówek.
- `QualEngine.gd` – silnik reakcji chemicznych.
- `Lab.gd` – główny kontroler sceny (tryby, highlighty, narzędzia).
- `Probe.gd` – probówki, mieszanki, render cieczy i osadów.
- `Mixture.gd` – model chemiczny mieszaniny.
- `/scenes` – probówki, zlewki, butelki, narzędzia, lab.
- `/data/reagents`, `/data/solids`, `/data/reactions` – definicje substancji chemicznych.


## Model chemiczny – skrót
Symulator opiera się na addytywnym modelu, w którym:
- każdy jon ma odpowiednik w mieszaninie,
- reakcje są całkowite i przechodzą do punktu stałego (wyczerpania substratów),
- zmętnienia liczone są jako prosty udział osadów,
- dolewanie odczynniów i wody naturalnie rozcieńcza mieszaninę.


---
