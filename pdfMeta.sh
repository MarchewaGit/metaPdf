#!/bin/bash
# metaPdf - Zarządzanie metadanymi PDF

LISTA_PLIKOW=(*.pdf)
CONFIG_FILE="./pdfMeta.rc"
DEFAULT_FOLDER="."
UI=false

[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"
FOLDER=${FOLDER:-$DEFAULT_FOLDER}

if [ -f "./funkcje.sh" ]; then
    source ./funkcje.sh
else
    echo "Błąd: Nie znaleziono pliku funkcje.sh!"
    exit 1
fi

pokaz_pomoc() {
    echo "Użycie: $0 [OPCJE]"
    echo "Opcje: -p (podsumowanie), -r (raport), -u (GUI), -a [AUTOR] (szukaj), -s [AUTOR] (usuń)"
}

DO_SUM=false
DO_REP=false
AUTOR_SEARCH=""
AUTOR_DEL=""
DATA_SEARCH=""

while getopts ":hvrps:d:ua:" OPT; do
  case $OPT in
    h) pokaz_pomoc; exit 0 ;;
    v) echo "metaPdf v1.0"; exit 0 ;;
    p) DO_SUM=true ;;
    r) DO_REP=true ;;
    a) AUTOR_SEARCH="$OPTARG" ;;
    s) AUTOR_DEL="$OPTARG" ;;
    d) DATA_SEARCH="$OPTARG" ;;
    u) UI=true ;;
    \?) echo "Zła opcja"; exit 1 ;;
  esac
done

cd "$FOLDER" || { echo "Błąd katalogu"; exit 1; }

[ -n "$AUTOR_SEARCH" ] && szukaj_wedlug_autora "$AUTOR_SEARCH"
[ -n "$DATA_SEARCH" ] && szukaj_wedlug_daty "$DATA_SEARCH"
[ -n "$AUTOR_DEL" ] && usun_wedlug_autora "$AUTOR_DEL"
[ "$DO_SUM" = true ] && generuj_podsumowanie
[ "$DO_REP" = true ] && generuj_raport_szczegolowy

if [ $OPTIND -eq 1 ] || { [ "$UI" = true ] && [ "$DO_SUM" = false ] && [ "$DO_REP" = false ] && [ -z "$AUTOR_SEARCH" ]; }; then
    menu_zenity
fi
