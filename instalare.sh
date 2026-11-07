#!/usr/bin/env bash
# =============================================================================
#  Instalare dintr-o singură comandă: recunoaște sistemul (Linux Mint, antiX,
#  Q4OS), descarcă scriptul potrivit de pe GitHub și îl rulează.
#
#    sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nazdravan/linux/main/instalare.sh)"
#    sudo bash -c "$(wget -qO- https://raw.githubusercontent.com/nazdravan/linux/main/instalare.sh)"
#
#  Setările scriptului se dau înainte de bash, de exemplu:
#    sudo AUTOLOGIN=0 TASTATURI=us,ro,ru VARIANTE=,std, bash -c "$(curl -fsSL …/instalare.sh)"
#
#  VARIANTA=mint|antix|q4os alege scriptul de mână, dacă sistemul nu e recunoscut.
# =============================================================================
set -Eeuo pipefail

SURSA="${SURSA:-https://raw.githubusercontent.com/nazdravan/linux/main}"

rosu=$'\033[1;31m'; verde=$'\033[1;32m'; albastru=$'\033[1;34m'; gri=$'\033[0m'
mesaj()  { printf '%s==> %s%s\n' "$albastru" "$*" "$gri"; }
eroare() { printf '%s    ✘ %s%s\n' "$rosu" "$*" "$gri" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || eroare "Rulează cu sudo: sudo bash -c \"\$(curl -fsSL $SURSA/instalare.sh)\""

varianta="${VARIANTA:-}"
if [ -z "$varianta" ]; then
    if [ -f /etc/linuxmint/info ]; then varianta=mint
    elif [ -f /etc/antix-version ]; then varianta=antix
    elif [ -f /etc/q4os_version ] || [ -d /opt/trinity ]; then varianta=q4os
    fi
fi
case "$varianta" in
    mint)  script=configurare-sala.sh;  nume="Linux Mint XFCE" ;;
    antix) script=configurare-antix.sh; nume="antiX" ;;
    q4os)  script=configurare-q4os.sh;  nume="Q4OS Trinity" ;;
    *) eroare "Nu recunosc sistemul. Scripturile sunt pentru Linux Mint XFCE, antiX și Q4OS. Poți alege de mână cu VARIANTA=mint, antix sau q4os." ;;
esac

mesaj "Sistem: $nume → $script"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$SURSA/$script" -o "$tmp/$script" || eroare "Nu am putut descărca $SURSA/$script"
elif command -v wget >/dev/null 2>&1; then
    wget -qO "$tmp/$script" "$SURSA/$script" || eroare "Nu am putut descărca $SURSA/$script"
else
    eroare "Lipsesc atât curl, cât și wget. Instalează unul: sudo apt install curl"
fi
bash -n "$tmp/$script" || eroare "Scriptul descărcat e incomplet. Încearcă din nou."

printf '%s    ✔ Descărcat. Pornesc configurarea (10–30 de minute).%s\n' "$verde" "$gri"
bash "$tmp/$script"
