#!/bin/bash

TMP_FILE="/tmp/pdf_analizator.$$.tmp"
trap 'rm -f "$TMP_FILE"' EXIT

pobierz_meta() {
    pdfinfo -- "$1" 2>/dev/null | grep -E "$2" | cut -d: -f2- | xargs
}

generuj_podsumowanie() {
    pliki=("${LISTA_PLIKOW[@]}")
    
    if [ ! -e "${pliki[0]}" ]; then
        msg="Brak plików PDF do przetworzenia."
        [ "$UI" = true ] && zenity --error --text="$msg" || echo "$msg"
        return
    fi

    AUTH_LIST="/tmp/authors.$$.tmp"
    > "$AUTH_LIST"
    for plik in "${pliki[@]}"; do
        if [ -s "$plik" ]; then
            AUTOR=$(pobierz_meta "$plik" "Author:")
            [ -n "$AUTOR" ] && echo "$AUTOR" >> "$AUTH_LIST"
        fi
    done

    unikalni=$(sort -u "$AUTH_LIST" | wc -l)
    
    # NAPRAWA: Przekazujemy tablicę plików, a nie gwiazdkę *.pdf
    # Używamy cudzysłowów wokół elementu tablicy, żeby obsłużyć spacje w nazwach
    rozmiar=$(du -shc "${pliki[@]}" 2>/dev/null | tail -n1 | awk '{print $1}')
    
    rm -f "$AUTH_LIST"

    WYNIK="Statystyki dla wybranych plików:\nPlików: ${#pliki[@]}\nŁączny rozmiar: $rozmiar\nUnikalnych autorów: $unikalni"
    
    if [ "$UI" = true ]; then
        zenity --info --title="Podsumowanie" --text="$WYNIK" 2>/dev/null
    else
        echo -e "\n--- PODSUMOWANIE ---"
        echo -e "$WYNIK"
    fi
}

generuj_raport_szczegolowy() {
    if [ "$UI" = true ]; then
        TRYB_SORT=$(zenity --list --radiolist --title="Sortowanie" --column="Wybór" --column="Sortuj według" \
            TRUE "Nazwa pliku" FALSE "Autor" FALSE "Rozmiar" FALSE "Liczba stron" 2>/dev/null)
    else
        echo "Wybierz sortowanie: [1] Nazwa, [2] Autor, [3] Rozmiar, [4] Strony"
        read -r opcja
        case $opcja in
            2) TRYB_SORT="Autor" ;;
            3) TRYB_SORT="Rozmiar" ;;
            4) TRYB_SORT="Liczba stron" ;;
            *) TRYB_SORT="Nazwa pliku" ;;
        esac
    fi

    RAW_DATA="/tmp/pdf_raw.$$.tmp"
    > "$RAW_DATA"
    
    # 1. Zbieranie danych
    for plik in "${LISTA_PLIKOW[@]}"; do
        if [ -s "$plik" ]; then
            AUTOR=$(pobierz_meta "$plik" "Author:")
            TYTUL=$(pobierz_meta "$plik" "Title:")
            TEMAT=$(pobierz_meta "$plik" "Subject:")
            PAGES=$(pobierz_meta "$plik" "Pages:")
            ENCR=$(pobierz_meta "$plik" "Encrypted:")
            SIZE=$(pobierz_meta "$plik" "Page size:")
            
            ROZMIAR_B=$(stat -c%s "$plik")
            ROZMIAR_H=$(du -h "$plik" | awk '{print $1}')
            DATA_H=$(date -r "$plik" "+%Y-%m-%d")
            
            echo "$plik;${AUTOR:-Brak};${TYTUL:-Brak};${TEMAT:-Brak};${PAGES:-0};$ROZMIAR_H;$DATA_H;$ROZMIAR_B;${ENCR:-no};${SIZE:-?}" >> "$RAW_DATA"
        fi
    done

    # 2. Sortowanie
    case "$TRYB_SORT" in
        "Autor") SORTED=$(sort -t';' -k2 -f "$RAW_DATA") ;;
        "Rozmiar") SORTED=$(sort -t';' -k8 -n "$RAW_DATA") ;;
        "Liczba stron") SORTED=$(sort -t';' -k5 -n "$RAW_DATA") ;;
        *) SORTED=$(sort -t';' -k1 -f "$RAW_DATA") ;;
    esac

    # 3. Przygotowanie pliku wynikowego (TU BYŁ BŁĄD)
    > "$TMP_FILE"

    if [ "$UI" = false ]; then
        # Najpierw nagłówek (tylko dla terminala)
        echo "PLIK | AUTOR | TYTUŁ | STRONY | ROZMIAR | DATA | SZYFR | FORMAT" >> "$TMP_FILE"
        echo "--- | --- | --- | --- | --- | --- | --- | ---" >> "$TMP_FILE"
    fi

    # Potem dopisujemy dane w pętli
    echo "$SORTED" | while IFS=';' read -r f a t s p rh dh rb en sz; do
        if [ "$UI" = true ]; then
            echo -e "$f\n$a\n$t\n$p\n$rh\n$dh\n$en\n$sz" >> "$TMP_FILE"
        else
            echo "$f | $a | $t | $p | $rh | $dh | $en | $sz" >> "$TMP_FILE"
        fi
    done

    # 4. Wyświetlanie (tylko jedno wywołanie column na samym końcu!)
    if [ "$UI" = true ]; then
        zenity --list --title="Pełny Raport PDF" \
               --column="Plik" --column="Autor" --column="Tytuł" --column="Strony" \
               --column="Rozmiar" --column="Data" --column="Szyfr." --column="Format" \
               --width=1100 --height=600 < "$TMP_FILE" >/dev/null 2>&1
    else
        echo -e "\n--- GENEROWANIE RAPORTU ---"
        column -t -s '|' "$TMP_FILE" | tee raport_pdf.txt
        echo -e "\n--- Raport zapisany w: $(pwd)/raport_pdf.txt ---\n"
    fi
    rm -f "$RAW_DATA"
}

szukaj_wedlug_autora() {
    local SZUKANY="$1"
    local NOWA_LISTA=()
    
    for plik in *.pdf; do
        [ -s "$plik" ] || continue
        AUTOR=$(pobierz_meta "$plik" "Author:")
        
        if [[ "$AUTOR" == *"$SZUKANY"* ]]; then
            NOWA_LISTA+=("$plik")
        fi
    done

    # Nadpisujemy globalną listę wynikami wyszukiwania
    LISTA_PLIKOW=("${NOWA_LISTA[@]}")
    
    # --- NOWA SEKCJA INFORMACYJNA ---
    local liczba_znalezionych=${#LISTA_PLIKOW[@]}

    if [ "$liczba_znalezionych" -eq 0 ]; then
        msg="Nic nie znaleziono dla autora: $SZUKANY"
        [ "$UI" = true ] && zenity --error --text="$msg" 2>/dev/null || echo "$msg"
        exit 0
    else
        msg="Znaleziono plików: $liczba_znalezionych (Autor: $SZUKANY)"
        # Wyświetlamy info tylko jeśli NIE ma flagi raportu/podsumowania LUB jeśli jesteśmy w GUI
        # To zapobiega dublowaniu komunikatów w czystym terminalu
        if [ "$UI" = true ]; then
            zenity --info --text="$msg" --timeout=2 2>/dev/null
        else
            echo -e "INFO: $msg"
        fi
    fi
}

szukaj_wedlug_daty() {
    local SZUKANA="$1"
    [ -z "$SZUKANA" ] && return 

    local NOWA_LISTA=()
    
    for plik in *.pdf; do
        [ -s "$plik" ] || continue
        
        # Pobieramy datę utworzenia
        local RAW_DATA=$(pobierz_meta "$plik" "CreationDate:")
        # Usuwamy techniczny prefiks D: (np. z D:2023... robi się 2023...)
        local CZYSTA_DATA=${RAW_DATA#D:}
        
        # Jeśli szukana fraza jest w dacie, dodajemy plik do nowej listy
        if [[ -n "$RAW_DATA" && "$CZYSTA_DATA" == *"$SZUKANA"* ]]; then
            NOWA_LISTA+=("$plik")
        fi
    done

    # KLUCZOWY MOMENT: Nadpisujemy globalną listę plików wynikami wyszukiwania
    LISTA_PLIKOW=("${NOWA_LISTA[@]}")
    
    # Informacja zwrotna dla użytkownika
    if [ ${#LISTA_PLIKOW[@]} -eq 0 ]; then
        msg="Nic nie znaleziono dla daty: $SZUKANA"
        [ "$UI" = true ] && zenity --error --text="$msg" 2>/dev/null || echo "$msg"
        exit 0
    else
        msg="Znaleziono plików: ${#LISTA_PLIKOW[@]} pasujących do daty $SZUKANA"
        [ "$UI" = true ] && zenity --info --text="$msg" 2>/dev/null || echo "$msg"
    fi
}

usun_wedlug_autora() {
    SZUKANY="$1"
    for plik in *.pdf; do
        [ -s "$plik" ] || continue
        AUTOR=$(pobierz_meta "$plik" "Author:")
        if [[ "$AUTOR" == *"$SZUKANY"* ]]; then
            rm "$plik" && echo "Usunięto: $plik"
        fi
    done
}

menu_zenity() {
    akcja=$(zenity --list --title="Manager PDF" --column="Akcja" \
        "Podsumowanie" "Raport" "Wyjście" 2>/dev/null)
    case "$akcja" in
        "Podsumowanie") generuj_podsumowanie ;;
        "Raport") generuj_raport_szczegolowy ;;
        *) exit 0 ;;
    esac
}
