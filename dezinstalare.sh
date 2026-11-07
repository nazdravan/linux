#!/usr/bin/env bash
# =============================================================================
#  Anulează ce au făcut configurare-sala.sh, configurare-antix.sh și
#  configurare-q4os.sh: contul elev, resetarea, intrarea automată, tema,
#  zram/BFQ/Firefox. Rulează din contul profesorului:
#
#    sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/nazdravan/linux/main/dezinstalare.sh)"
#
#  Rămân instalate programele (LibreOffice, Firefox, KolourPaint…), limba și
#  tastatura. Dosarul cu lucrări (/srv/lucrari) rămâne, ca să nu se piardă
#  munca elevilor.
#
#  Setări:
#    PASTREAZA_ELEV=1   nu șterge contul elev (doar oprește resetarea)
#    STERGE_LUCRARI=1   șterge și dosarul cu lucrări
#    DA=1               nu mai întreabă înainte
# =============================================================================
set -Euo pipefail

ELEV_USER="${ELEV_USER:-elev}"
LUCRARI_DIR="${LUCRARI_DIR:-/srv/lucrari}"
PASTREAZA_ELEV="${PASTREAZA_ELEV:-0}"
STERGE_LUCRARI="${STERGE_LUCRARI:-0}"
DA="${DA:-0}"
LOG=/var/log/dezinstalare-sala.log

albastru=$'\033[1;34m'; verde=$'\033[1;32m'; galben=$'\033[1;33m'; rosu=$'\033[1;31m'; gri=$'\033[0m'
pas()    { printf '\n%s==> %s%s\n' "$albastru" "$*" "$gri"; }
ok()     { printf '%s    ✔ %s%s\n' "$verde" "$*" "$gri"; }
avert()  { printf '%s    ! %s%s\n' "$galben" "$*" "$gri"; }
eroare() { printf '%s    ✘ %s%s\n' "$rosu" "$*" "$gri" >&2; exit 1; }
are_systemd() { [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; }
sterge() { local p; for p in "$@"; do if [ -e "$p" ] || [ -L "$p" ]; then rm -rf -- "$p" && ok "Șters $p"; fi; done; }

[ "$(id -u)" -eq 0 ] || eroare "Rulează cu sudo, din contul profesorului."
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" = "$ELEV_USER" ]; then
    eroare "Rulează din contul profesorului, nu din contul $ELEV_USER."
fi
if who | awk '{print $1}' | grep -x "$ELEV_USER" >/dev/null; then
    eroare "Elevul este logat acum. Ieși din sesiunea lui (sau repornește) și rulează din nou."
fi

cat <<EOF

Se vor anula setările pentru sala de informatică:
  • resetarea contului, intrarea automată, comanda cont-elev
  • $( [ "$PASTREAZA_ELEV" = "1" ] && echo "contul $ELEV_USER RĂMÂNE" || echo "contul $ELEV_USER și tot ce e în el se ȘTERG" )
  • tema Windows 10, fundalul, setările zram/BFQ/Firefox
  • $( [ "$STERGE_LUCRARI" = "1" ] && echo "dosarul $LUCRARI_DIR se ȘTERGE" || echo "dosarul $LUCRARI_DIR RĂMÂNE" )
Programele (LibreOffice, Firefox, Paint), limba și tastatura rămân.

EOF
if [ "$DA" != "1" ]; then
    [ -r /dev/tty ] || eroare "Nu pot întreba. Rulează cu DA=1 ca să confirmi."
    printf 'Continui? Scrie „da”: '
    raspuns=""
    read -r raspuns </dev/tty 2>/dev/null || true
    [ "$raspuns" = "da" ] || { echo "Am renunțat. Nu s-a schimbat nimic."; exit 0; }
fi

exec > >(tee -a "$LOG") 2>&1
echo "=== Dezinstalare $(date '+%F %T')"

# -----------------------------------------------------------------------------
pas "Resetarea contului"
if are_systemd; then
    systemctl disable cont-elev-reset.service >/dev/null 2>&1 || true
fi
sterge /etc/systemd/system/multi-user.target.wants/cont-elev-reset.service \
       /etc/systemd/system/cont-elev-reset.service \
       /usr/local/sbin/cont-elev /usr/local/sbin/cont-elev-la-iesire \
       /usr/local/sbin/cont-elev-sesiune /usr/local/sbin/sala-servicii \
       /usr/local/bin/sala-la-pornire
are_systemd && systemctl daemon-reload || true

# -----------------------------------------------------------------------------
pas "Ecranul de logare"
# Linux Mint (LightDM)
sterge /etc/lightdm/lightdm.conf.d/90-sala.conf

# Q4OS (TDM): fișierele originale sunt păstrate ca *.inainte-de-sala
for f in /etc/trinity/tdm/Xstartup /etc/trinity/tdm/Xreset /etc/trinity/tdm/tdmrc; do
    if [ -f "$f.inainte-de-sala" ]; then
        mv -f "$f.inainte-de-sala" "$f" && ok "Restaurat $f"
    elif [ -f "$f" ] && grep '# >>> sala' "$f" >/dev/null; then
        sed -i '/# >>> sala/,/# <<< sala/d' "$f" && ok "Scos blocul sala din $f"
    fi
done

# antiX (slimski)
if [ -f /etc/slimski.local.conf.inainte-de-sala ]; then
    mv -f /etc/slimski.local.conf.inainte-de-sala /etc/slimski.local.conf && ok "Restaurat /etc/slimski.local.conf"
elif [ -f /etc/slimski.local.conf ]; then
    sed -i -E '/^(sessionstart_cmd|sessionstop_cmd)[[:space:]]+\/usr\/local\/sbin\/cont-elev-sesiune/d' /etc/slimski.local.conf
    sed -i -E "s|^(autologin_enabled)[[:space:]].*|\1    false|" /etc/slimski.local.conf
    ok "Scoase comenzile sala din /etc/slimski.local.conf"
fi

# -----------------------------------------------------------------------------
pas "Contul $ELEV_USER"
if [ "$PASTREAZA_ELEV" = "1" ]; then
    ok "Contul rămâne (PASTREAZA_ELEV=1)"
elif id "$ELEV_USER" >/dev/null 2>&1; then
    pkill -KILL -u "$ELEV_USER" 2>/dev/null || true
    sleep 1
    if userdel -r "$ELEV_USER" 2>/dev/null || userdel "$ELEV_USER"; then
        rm -rf "/home/$ELEV_USER"
        ok "Contul $ELEV_USER șters"
    else
        avert "Nu am putut șterge contul $ELEV_USER (îl poți șterge din Setări → Utilizatori)"
    fi
else
    ok "Contul $ELEV_USER nu există"
fi
sterge "/var/lib/AccountsService/users/$ELEV_USER" /var/lib/cont-elev

if [ -d "$LUCRARI_DIR" ]; then
    if [ "$STERGE_LUCRARI" = "1" ]; then
        sterge "$LUCRARI_DIR"
    else
        chown -R root:root "$LUCRARI_DIR" 2>/dev/null || true
        ok "Dosarul $LUCRARI_DIR rămâne (STERGE_LUCRARI=1 ca să-l ștergi)"
    fi
fi

# -----------------------------------------------------------------------------
pas "Memorie, disc, Firefox"
sterge /etc/sysctl.d/90-sala-zram.conf /etc/modules-load.d/sala-bfq.conf /etc/udev/rules.d/60-sala-hdd-bfq.rules
if [ -f /etc/antix-version ] && grep -x bfq /etc/modules >/dev/null 2>&1; then
    sed -i '/^bfq$/d' /etc/modules && ok "Scos bfq din /etc/modules"
fi
sysctl -q vm.swappiness=60 2>/dev/null || true
udevadm control --reload 2>/dev/null || true
# Politica Firefox se șterge doar dacă e cea scrisă de scripturi (are uBlock forțat).
for p in /etc/firefox/policies/policies.json /usr/lib/firefox-esr/distribution/policies.json; do
    if [ -f "$p" ] && grep 'uBlock0@raymondhill.net' "$p" >/dev/null && grep '"dom.ipc.processCount"' "$p" >/dev/null; then
        sterge "$p"
    fi
done
# Linux Mint: serviciile oprite de script pornesc din nou.
if are_systemd && [ -f /etc/linuxmint/info ]; then
    for s in ModemManager.service cups-browsed.service; do
        if systemctl cat "$s" >/dev/null 2>&1; then systemctl enable "$s" >/dev/null 2>&1 && ok "Repornit serviciul $s"; fi
    done
fi
avert "zram și earlyoom rămân instalate (ajută și fără sală). Le scoți cu: sudo apt purge zram-tools earlyoom"

# -----------------------------------------------------------------------------
pas "Tema și fundalul"
sterge /opt/trinity/share/icons/Windows-10 /usr/share/themes/Windows-10 /usr/share/icons/Windows-10 \
       /usr/share/icewm/themes/Scoala-Win10 /usr/share/backgrounds/sala /usr/share/wallpaper/sala-fundal.png \
       /usr/share/sala

pas "Gata"
echo "    Repornește calculatorul: sudo reboot"
echo "    Jurnal: $LOG"
