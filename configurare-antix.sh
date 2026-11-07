#!/usr/bin/env bash
# =============================================================================
#  configurare-antix.sh — pregătește un calculator slab (2 GB RAM, HDD) din sala
#  de informatică pe antiX 26.x (64 biți, ediția full): aspect apropiat de
#  Windows 10 (IceWM), optimizat pentru memorie puțină, în limba română, cu un
#  cont „elev" care revine la starea inițială la fiecare intrare / ieșire.
#
#  Merge cu orice sistem de inițializare al antiX (runit, sysvinit, dinit, s6):
#  tot ce trebuie pornit este pornit de ecranul de logare (slimski).
#
#  Folosire (ca administrator, cu internet):
#      sudo bash configurare-antix.sh
#
#  Scriptul poate fi rulat de mai multe ori. Setările se pot schimba mai jos
#  sau din linia de comandă:  sudo ELEV_PAROLA=1234 bash configurare-antix.sh
# =============================================================================

# ---------------------------- SETĂRI -----------------------------------------
ELEV_USER="${ELEV_USER:-elev}"
ELEV_NUME="${ELEV_NUME:-Elev}"
ELEV_PAROLA="${ELEV_PAROLA:-elev}"
AUTOLOGIN="${AUTOLOGIN:-1}"                # 1 = la pornire intră direct în contul elev
LUCRARI_DIR="${LUCRARI_DIR:-/srv/lucrari}" # dosar care NU se șterge ("" = fără)
TASTATURI="${TASTATURI:-us,ro}"
VARIANTE="${VARIANTE:-,std}"
COMUTARE_TASTATURA="${COMUTARE_TASTATURA:-grp:alt_shift_toggle}"
LIMBA="${LIMBA:-ro_RO.UTF-8}"
TEMA_WIN10="${TEMA_WIN10:-1}"              # 1 = descarcă tema GTK și iconițele Windows 10
ACTUALIZARE="${ACTUALIZARE:-1}"            # 1 = instalează și actualizările sistemului
# -----------------------------------------------------------------------------

set -Eeuo pipefail

DATE_DIR=/var/lib/cont-elev
SABLON="$DATE_DIR/sablon"
LOG=/var/log/configurare-sala.log
FUNDAL=/usr/share/wallpaper/sala-fundal.png
TEMA_ICEWM=Scoala-Win10
SLIMSKI_CONF=/etc/slimski.local.conf
PASI_ESUATI=()

albastru=$'\033[1;34m'; verde=$'\033[1;32m'; galben=$'\033[1;33m'; rosu=$'\033[1;31m'; gri=$'\033[0m'
pas()    { printf '\n%s==> %s%s\n' "$albastru" "$*" "$gri"; }
ok()     { printf '%s    ✔ %s%s\n' "$verde" "$*" "$gri"; }
avert()  { printf '%s    ! %s%s\n' "$galben" "$*" "$gri"; }
eroare() { printf '%s    ✘ %s%s\n' "$rosu" "$*" "$gri" >&2; }
trap 'eroare "Eroare neașteptată la linia $LINENO (comanda: $BASH_COMMAND). Vezi $LOG"' ERR

scrie() { install -d "$(dirname "$1")"; cat > "$1"; }
este_logat() { who | awk '{print $1}' | grep -x "$1" >/dev/null; }

# =============================================================================
verificari() {
    pas "Verificări"
    if [ "$(id -u)" -ne 0 ]; then
        eroare "Rulează scriptul ca administrator:  sudo bash $0"; exit 1
    fi
    if [ "$(uname -m)" != "x86_64" ]; then
        eroare "Scriptul e pentru antiX pe 64 de biți (x64)."; exit 1
    fi
    if [ -f /etc/antix-version ]; then
        ok "$(cat /etc/antix-version)"
    else
        avert "Nu pare a fi antiX. Continui, dar unele lucruri pot să nu meargă."
    fi
    if [ -d /live/aufs ] || grep -qs ' /live/' /proc/mounts; then
        eroare "Rulezi antiX de pe stick (live). Instalează-l mai întâi pe disc."; exit 1
    fi
    for f in /usr/bin/icewm "$SLIMSKI_CONF"; do
        [ -e "$f" ] || { eroare "Lipsește $f — ai nevoie de antiX full, cu IceWM și slimski."; exit 1; }
    done
    if ! getent hosts deb.debian.org >/dev/null 2>&1; then
        avert "Nu pare să fie internet. Instalarea pachetelor poate eșua."
    fi
    ok "Jurnalul complet se scrie în $LOG"
}

# =============================================================================
instaleaza_pachete() {
    pas "Instalez programele (poate dura 10-30 de minute pe HDD)"
    export DEBIAN_FRONTEND=noninteractive
    local apt_opt=(-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

    apt-get update
    if [ "$ACTUALIZARE" = "1" ]; then
        apt-get "${apt_opt[@]}" dist-upgrade
        ok "Sistemul este actualizat"
    fi

    apt-get "${apt_opt[@]}" install --no-install-recommends \
        rsync unzip wget python3 earlyoom util-linux \
        libreoffice-writer libreoffice-calc libreoffice-impress libreoffice-gtk3 \
        firefox-esr drawing
    ok "LibreOffice, Firefox, Drawing (în loc de Paint), earlyoom"

    # Pachetele de limbă trebuie să vină din același depozit ca LibreOffice
    # (antiX îl ia din backports).
    local lo_ver t_opt=()
    lo_ver="$(dpkg-query -W -f='${Version}' libreoffice-core 2>/dev/null || true)"
    if [[ "$lo_ver" == *bpo* ]]; then
        local cod; cod="$(. /etc/os-release && echo "${VERSION_CODENAME:-trixie}")"
        t_opt=(-t "${cod}-backports")
    fi
    local dorite=(libreoffice-l10n-ro hunspell-ro hyphen-ro mythes-ro firefox-esr-l10n-ro)
    local existente=() p
    for p in "${dorite[@]}"; do
        if [[ "$(LC_ALL=C apt-cache policy "$p" 2>/dev/null)" == *"Candidate: "[!\(]* ]]; then
            existente+=("$p")
        fi
    done
    if [ "${#existente[@]}" -gt 0 ]; then
        apt-get "${apt_opt[@]}" "${t_opt[@]}" install --no-install-recommends "${existente[@]}"
    fi
    ok "Limba română: ${existente[*]:-nimic de instalat}"
}

# =============================================================================
optimizeaza_memoria() {
    pas "Optimizez pentru 2 GB RAM și HDD"

    cat > /etc/sysctl.d/90-sala-zram.conf <<'EOF'
# Configurat de configurare-antix.sh: folosește zram mai devreme.
vm.swappiness=150
vm.page-cluster=0
EOF

    cat > /etc/default/earlyoom <<'EOF'
# Configurat de configurare-antix.sh. Închide o filă de browser când se termină
# memoria; nu închide niciodată LibreOffice sau Drawing (lucrarea elevului).
EARLYOOM_ARGS="-r 0 -m 5 -s 10 --prefer '(^|/)(Web Content|Isolated Web Co|WebExtensions)$' --avoid '(^|/)(init|runit|runsv|Xorg|slimski|icewm|zzzfm|soffice.bin|drawing)$'"
EOF

    # zram + earlyoom fără să depindem de sistemul de inițializare: le pornește
    # slimski înainte de fiecare logare (vezi cont-elev-sesiune).
    cat > /usr/local/sbin/sala-servicii <<'EOF'
#!/bin/sh
# Instalat de configurare-antix.sh — pornește zram și earlyoom (o singură dată).
if ! grep -q '^/dev/zram' /proc/swaps 2>/dev/null; then
    modprobe zram 2>/dev/null
    mem_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
    dev=$(zramctl --find --size "${mem_kb}K" --algorithm zstd 2>/dev/null) \
        || dev=$(zramctl --find --size "${mem_kb}K" 2>/dev/null)
    if [ -n "$dev" ]; then
        mkswap "$dev" >/dev/null 2>&1 && swapon -p 100 "$dev" 2>/dev/null
    fi
fi
sysctl -q -p /etc/sysctl.d/90-sala-zram.conf >/dev/null 2>&1
if ! pgrep -x earlyoom >/dev/null 2>&1 && [ -x /usr/bin/earlyoom ]; then
    EARLYOOM_ARGS=""
    [ -f /etc/default/earlyoom ] && . /etc/default/earlyoom
    eval "set -- $EARLYOOM_ARGS"
    setsid /usr/bin/earlyoom "$@" </dev/null >/dev/null 2>&1 &
fi
exit 0
EOF
    chmod 755 /usr/local/sbin/sala-servicii
    ok "zram și earlyoom (pornite la logare)"

    grep -x bfq /etc/modules >/dev/null 2>&1 || echo bfq >> /etc/modules
    cat > /etc/udev/rules.d/60-sala-hdd-bfq.rules <<'EOF'
# Configurat de configurare-antix.sh: BFQ pentru discurile rotative (HDD)
ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
EOF
    ok "BFQ pentru HDD"

    local politica
    politica='{
  "policies": {
    "DisableTelemetry": true,
    "DisableFirefoxStudies": true,
    "DisablePocket": true,
    "DontCheckDefaultBrowser": true,
    "OverrideFirstRunPage": "",
    "OverridePostUpdatePage": "",
    "UserMessaging": { "WhatsNew": false, "ExtensionRecommendations": false,
                       "FeatureRecommendations": false, "SkipOnboarding": true, "MoreFromMozilla": false },
    "ExtensionSettings": {
      "uBlock0@raymondhill.net": {
        "installation_mode": "force_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi"
      }
    },
    "Preferences": {
      "dom.ipc.processCount": { "Value": 2, "Status": "default" },
      "browser.tabs.unloadOnLowMemory": { "Value": true, "Status": "default" },
      "browser.sessionstore.interval": { "Value": 60000, "Status": "default" }
    }
  }
}'
    local d
    for d in /etc/firefox/policies /usr/lib/firefox-esr/distribution; do
        install -d "$d"; printf '%s\n' "$politica" > "$d/policies.json"
    done
    ok "Firefox: uBlock Origin și setări pentru memorie puțină"
}

# =============================================================================
seteaza_limba_tastatura() {
    pas "Limba română și tastatura"
    if ! locale -a 2>/dev/null | grep -i '^ro_RO\.utf-\?8$' >/dev/null; then
        sed -i 's/^# *\(ro_RO.UTF-8 UTF-8\)/\1/' /etc/locale.gen
        grep '^ro_RO.UTF-8 UTF-8' /etc/locale.gen >/dev/null || echo 'ro_RO.UTF-8 UTF-8' >> /etc/locale.gen
        locale-gen >/dev/null
    fi
    update-locale LANG="$LIMBA" LANGUAGE="ro:en"
    ok "Limba sistemului: $LIMBA"

    sed -i \
        -e "s/^XKBLAYOUT=.*/XKBLAYOUT=\"$TASTATURI\"/" \
        -e "s/^XKBVARIANT=.*/XKBVARIANT=\"$VARIANTE\"/" \
        -e "s/^XKBOPTIONS=.*/XKBOPTIONS=\"$COMUTARE_TASTATURA,terminate:ctrl_alt_bksp\"/" \
        /etc/default/keyboard
    ok "Tastatură: $TASTATURI (comutare cu Alt+Shift)"
}

# =============================================================================
descarca_tema() {   # $1 = URL arhivă, $2 = director destinație
    local url="$1" dest="$2" tmp src
    tmp="$(mktemp -d)"
    if ! wget -q -O "$tmp/arhiva.zip" "$url" || ! unzip -q "$tmp/arhiva.zip" -d "$tmp/x"; then
        rm -rf "$tmp"; return 1
    fi
    src="$(find "$tmp/x" -mindepth 1 -maxdepth 1 -type d | head -n1)"
    if [ -z "$src" ] || [ ! -f "$src/index.theme" ]; then rm -rf "$tmp"; return 1; fi
    rm -rf "$dest"; mv "$src" "$dest"; chmod -R a+rX "$dest"; rm -rf "$tmp"
}

instaleaza_teme() {
    pas "Aspectul Windows 10"
    TEMA_GTK="Arc-EvoPro2"; TEMA_ICONITE="Qogir"
    if [ "$TEMA_WIN10" = "1" ]; then
        if descarca_tema https://github.com/B00merang-Project/Windows-10/archive/refs/heads/master.zip \
                         /usr/share/themes/Windows-10; then
            TEMA_GTK="Windows-10"; ok "Tema GTK Windows 10 (ferestrele programelor)"
        else
            avert "Nu am putut descărca tema GTK Windows 10; rămâne $TEMA_GTK"; PASI_ESUATI+=("tema GTK")
        fi
        if descarca_tema https://github.com/B00merang-Artwork/Windows-10/archive/refs/heads/master.zip \
                         /usr/share/icons/Windows-10; then
            grep '^Inherits=' /usr/share/icons/Windows-10/index.theme >/dev/null \
                || sed -i '/^\[Icon Theme\]/a Inherits=Qogir,Papirus,Adwaita,hicolor' /usr/share/icons/Windows-10/index.theme
            gtk-update-icon-cache -f -q /usr/share/icons/Windows-10 2>/dev/null || true
            TEMA_ICONITE="Windows-10"; ok "Iconițe Windows 10"
        else
            avert "Nu am putut descărca iconițele Windows 10; rămân $TEMA_ICONITE"; PASI_ESUATI+=("iconițe")
        fi
    fi

    # Tema IceWM „Scoala-Win10": bară jos închisă la culoare, titluri albe,
    # butoane plate _ □ ✕ (✕ devine roșu sub mouse). Generată aici, fără imagini străine.
    local T="/usr/share/icewm/themes/$TEMA_ICEWM"
    rm -rf "$T"; install -d "$T/taskbar"
    python3 - "$T" <<'PY'
import os, sys
T = sys.argv[1]
W, H = 46, 30

def glyph(kind):
    px = set()
    x0, y0, s = 18, 10, 10
    if kind == "close":
        for i in range(s):
            px.add((x0 + i, y0 + i)); px.add((x0 + s - 1 - i, y0 + i))
    elif kind == "maximize":
        for i in range(s):
            px |= {(x0 + i, y0), (x0 + i, y0 + s - 1), (x0, y0 + i), (x0 + s - 1, y0 + i)}
    elif kind == "minimize":
        for i in range(s):
            px.add((x0 + i, y0 + s // 2))
    elif kind == "restore":
        a, b = 8, 2           # pătratul din față (8x8) și cel din spate, deplasat cu 2
        for i in range(a):
            px |= {(x0 + i, y0 + b), (x0 + i, y0 + b + a - 1), (x0, y0 + b + i), (x0 + a - 1, y0 + b + i)}
        for i in range(a):
            px.add((x0 + b + i, y0))                 # marginea de sus a celui din spate
            px.add((x0 + b + a - 1, y0 + i))         # marginea din dreapta
    return px

def frame(kind, bg, fg):
    g = glyph(kind)
    return [["#" if (x, y) in g else "." for x in range(W)] for y in range(H)], bg, fg

def write_xpm(path, frames):
    # Fiecare stare are culorile ei; le codăm cu câte un caracter per culoare.
    colors, rows = {}, []
    for pix, bg, fg in frames:
        for c in (bg, fg):
            colors.setdefault(c, "abcdefghijklmnop"[len(colors)])
        for r in pix:
            rows.append("".join(colors[fg] if ch == "#" else colors[bg] for ch in r))
    name = os.path.splitext(os.path.basename(path))[0]
    with open(path, "w") as f:
        f.write("/* XPM */\nstatic char *%s[] = {\n" % name.replace("-", "_"))
        f.write('"%d %d %d 1",\n' % (W, len(rows), len(colors)))
        for c, k in colors.items():
            f.write('"%s c %s",\n' % (k, c))
        f.write(",\n".join('"%s"' % r for r in rows) + "\n};\n")

ALB, NEGRU, GRI = "#FFFFFF", "#000000", "#999999"
for kind in ("close", "maximize", "minimize", "restore"):
    if kind == "close":
        over, pressed, fg_over = "#E81123", "#F1707A", ALB
    else:
        over, pressed, fg_over = "#E5E5E5", "#CCCCCC", NEGRU
    # Două stări pe verticală: normal, apăsat.
    write_xpm(f"{T}/{kind}A.xpm", [frame(kind, ALB, NEGRU), frame(kind, pressed, fg_over)])
    write_xpm(f"{T}/{kind}I.xpm", [frame(kind, ALB, GRI), frame(kind, pressed, fg_over)])
    write_xpm(f"{T}/{kind}O.xpm", [frame(kind, over, fg_over), frame(kind, pressed, fg_over)])

# Butonul Start: 48x40, bară închisă, o grilă de 3x3 pătrățele albe (meniul de programe).
SW, SH = 48, 40
start = []
for y in range(SH):
    r = ""
    for x in range(SW):
        on = False
        for gx in range(3):
            for gy in range(3):
                bx, by = 15 + gx * 7, 11 + gy * 7
                if bx <= x < bx + 4 and by <= y < by + 4:
                    on = True
        r += "w" if on else "d"
    start.append(r)
with open(f"{T}/taskbar/start.xpm", "w") as f:
    f.write('/* XPM */\nstatic char *start[] = {\n"%d %d 2 1",\n"d c #202020",\n"w c #FFFFFF",\n' % (SW, SH))
    f.write(",\n".join('"%s"' % r for r in start) + "\n};\n")
PY

    scrie "$T/default.theme" <<'EOF'
# Scoala-Win10 — temă IceWM în stilul Windows 10, generată de configurare-antix.sh
ThemeDescription="Scoala Win10 (flat, bara jos)"
ThemeAuthor="configurare-antix.sh"
License="GPL"
Look=flat
TitleBarHeight=30
TitleBarCentered=0
TitleBarJustify=0
TitleBarHorzOffset=4
RolloverButtonsSupported=1
TitleButtonsLeft="s"
TitleButtonsRight="xmi"
TitleButtonsSupported="xmis"
ShowMenuButtonIcon=1
BorderSizeX=2
BorderSizeY=2
DlgBorderSizeX=2
DlgBorderSizeY=2
CornerSizeX=12
CornerSizeY=12
TaskBarAtTop=0
ColorActiveBorder="#1883D7"
ColorNormalBorder="#AAAAAA"
ColorActiveTitleBar="#FFFFFF"
ColorNormalTitleBar="#FFFFFF"
ColorActiveTitleBarText="#000000"
ColorNormalTitleBarText="#999999"
ColorActiveButton="#FFFFFF"
ColorNormalButton="#202020"
ColorNormalButtonText="#FFFFFF"
ColorDefaultTaskBar="#202020"
ColorNormalTaskBarApp="#202020"
ColorNormalTaskBarAppText="#FFFFFF"
ColorActiveTaskBarApp="#3C3C3C"
ColorActiveTaskBarAppText="#FFFFFF"
ColorMinimizedTaskBarApp="#202020"
ColorMinimizedTaskBarAppText="#BBBBBB"
ColorInvisibleTaskBarApp="#202020"
ColorInvisibleTaskBarAppText="#888888"
ColorNormalWorkspaceButton="#202020"
ColorNormalWorkspaceButtonText="#FFFFFF"
ColorActiveWorkspaceButton="#3C3C3C"
ColorActiveWorkspaceButtonText="#FFFFFF"
ColorClock="#202020"
ColorClockText="#FFFFFF"
ColorApm="#202020"
ColorApmText="#FFFFFF"
ColorNormalMenu="#2B2B2B"
ColorNormalMenuItemText="#FFFFFF"
ColorActiveMenuItem="#4A4A4A"
ColorActiveMenuItemText="#FFFFFF"
ColorDisabledMenuItemText="#888888"
ColorMenuIcons="#2B2B2B"
ColorDialog="#F0F0F0"
ColorLabel="#F0F0F0"
ColorLabelText="#000000"
ColorListBox="#FFFFFF"
ColorListBoxText="#000000"
ColorListBoxSelection="#CCE8FF"
ColorListBoxSelectionText="#000000"
ColorInput="#FFFFFF"
ColorInputText="#000000"
ColorInputSelection="#0078D7"
ColorInputSelectionText="#FFFFFF"
ColorToolTip="#F2F2F2"
ColorToolTipText="#000000"
ColorQuickSwitch="#2B2B2B"
ColorQuickSwitchText="#FFFFFF"
ColorQuickSwitchActive="#0078D7"
ColorMoveSizeStatus="#2B2B2B"
ColorMoveSizeStatusText="#FFFFFF"
ColorScrollBar="#F0F0F0"
ColorScrollBarSlider="#C2C2C2"
TitleFontNameXft="Ubuntu:size=11,sans-serif:size=11"
MenuFontNameXft="Ubuntu:size=11,sans-serif:size=11"
ActiveTaskBarFontNameXft="Ubuntu:size=10,sans-serif:size=10"
NormalTaskBarFontNameXft="Ubuntu:size=10,sans-serif:size=10"
ClockFontNameXft="Ubuntu:size=10,sans-serif:size=10"
ToolTipFontNameXft="Ubuntu:size=10,sans-serif:size=10"
QuickSwitchFontNameXft="Ubuntu:size=11,sans-serif:size=11"
MenuIconSize=24
SmallIconSize=24
LargeIconSize=32
HugeIconSize=48
EOF
    chmod -R a+rX "$T"
    ok "Tema IceWM $TEMA_ICEWM (bara de jos, ferestre plate)"

    install -d "$(dirname "$FUNDAL")"
    python3 - "$FUNDAL" <<'PY'
import struct, sys, zlib
W, H = 1920, 1080
sus, jos = (4, 20, 48), (0, 110, 200)
linii = bytearray()
for y in range(H):
    linii.append(0)
    ty = y / (H - 1)
    rand = bytearray()
    for x in range(0, W, 8):
        t = max(0.0, min(1.0, 0.55 * (x / (W - 1)) + 0.45 * (1 - ty))) ** 1.6
        rand += bytes(int(sus[i] + (jos[i] - sus[i]) * t) for i in range(3)) * 8
    linii += rand[: W * 3]
def bucata(tip, date):
    return struct.pack(">I", len(date)) + tip + date + struct.pack(">I", zlib.crc32(tip + date) & 0xFFFFFFFF)
open(sys.argv[1], "wb").write(b"\x89PNG\r\n\x1a\n" + bucata(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0))
    + bucata(b"IDAT", zlib.compress(bytes(linii), 9)) + bucata(b"IEND", b""))
PY
    chmod 644 "$FUNDAL"
    ok "Fundal de ecran"
}

# =============================================================================
iconita() {   # cale către iconița unei aplicații (pentru bara IceWM), sau numele ei
    local n="$1" tema dir ext
    for tema in "$TEMA_ICONITE" hicolor Qogir Papirus; do
        for dir in 48x48/apps 48/apps scalable/apps; do
            for ext in png svg; do
                [ -f "/usr/share/icons/$tema/$dir/$n.$ext" ] && { echo "/usr/share/icons/$tema/$dir/$n.$ext"; return; }
            done
        done
    done
    for ext in png svg xpm; do
        [ -f "/usr/share/pixmaps/$n.$ext" ] && { echo "/usr/share/pixmaps/$n.$ext"; return; }
    done
    echo "$n"
}

construieste_sablon() {
    pas "Construiesc profilul contului „$ELEV_USER\""
    local S="$DATE_DIR/sablon.nou" ACASA="/home/$ELEV_USER"
    rm -rf "$S"; install -d -m 700 "$DATE_DIR"; install -d "$S"
    cp -a /etc/skel/. "$S"/

    local I_WRITER I_CALC I_IMPRESS I_PAINT I_WEB I_FM I_TOATE
    I_WRITER="$(iconita libreoffice-writer)"; I_CALC="$(iconita libreoffice-calc)"
    I_IMPRESS="$(iconita libreoffice-impress)"; I_PAINT="$(iconita com.github.maoschanz.drawing)"
    I_WEB="$(iconita firefox-esr)"; I_FM="$(iconita system-file-manager)"
    I_TOATE="$(iconita applications-all)"

    # --- IceWM -----------------------------------------------------------------
    echo "Theme=\"$TEMA_ICEWM/default.theme\"" > "$S/.icewm/theme"
    scrie "$S/.icewm/prefoverride" <<'EOF'
# Configurat de configurare-antix.sh — are prioritate față de temă și preferences.
TaskBarAtTop=0
TaskBarShowWorkspaces=0
WorkspaceNames=" 1 "
TaskBarShowCPUStatus=0
TaskBarShowNetStatus=0
TaskBarShowMEMStatus=0
TaskBarShowMailboxStatus=0
TaskBarShowWindowListMenu=0
TaskBarShowShowDesktopButton=0
TaskBarShowStartMenu=1
TaskBarClockLeds=0
TimeFormat="%H:%M   %d.%m.%Y"
Win95Keys=1
KeySysShowDesktop="Super+d"
KeyWinClose="Alt+F4"
ConfirmLogout=1
ShowHelp=0
EOF
    scrie "$S/.icewm/toolbar" <<EOF
prog "Fișiere" $I_FM desktop-defaults-run -fm
prog "Internet (Firefox)" $I_WEB firefox-esr
prog "Documente (LibreOffice Writer)" $I_WRITER libreoffice --writer
prog "Tabele (LibreOffice Calc)" $I_CALC libreoffice --calc
prog "Prezentări (LibreOffice Impress)" $I_IMPRESS libreoffice --impress
prog "Desen (Drawing)" $I_PAINT drawing
EOF
    scrie "$S/.icewm/menu" <<EOF
prog "Documente — LibreOffice Writer" $I_WRITER libreoffice --writer
prog "Tabele — LibreOffice Calc" $I_CALC libreoffice --calc
prog "Prezentări — LibreOffice Impress" $I_IMPRESS libreoffice --impress
prog "Desen — Drawing" $I_PAINT drawing
prog "Internet — Firefox" $I_WEB firefox-esr
prog "Fișiere" $I_FM desktop-defaults-run -fm
separator
menufile "Toate programele" $I_TOATE menu-applications
EOF

    # --- Sesiunea antiX: IceWM cu desktop zzzfm, fără conky, tastatura română
    echo "zzz-icewm" > "$S/.desktop-session/default-desktop"
    sed -i 's/^LOAD_CONKY=.*/LOAD_CONKY="false"/' "$S/.desktop-session/desktop-session.conf"
    cat >> "$S/.desktop-session/startup" <<EOF

# --- configurare-antix.sh ---
setxkbmap -layout "$TASTATURI" -variant "$VARIANTE" -option "" -option "$COMUTARE_TASTATURA" &
EOF
    if [ -f "$S/.config/zzzfm/session" ]; then
        sed -i "s|^wallpaper=.*|wallpaper=$FUNDAL|; s|^show_wallpaper=.*|show_wallpaper=1|" "$S/.config/zzzfm/session"
    fi
    echo "zzz-icewm" > "$S/.config/slimski.lastused" 2>/dev/null || true

    # --- Temă GTK (ferestrele programelor) -----------------------------------
    sed -i "s|/home/[^/\"]*/.gtkrc-2.0.mine|$ACASA/.gtkrc-2.0.mine|" "$S/.gtkrc-2.0" 2>/dev/null || true
    sed -i -e "s|^gtk-theme-name=.*|gtk-theme-name=\"$TEMA_GTK\"|" \
           -e "s|^gtk-icon-theme-name=.*|gtk-icon-theme-name=\"$TEMA_ICONITE\"|" "$S/.gtkrc-2.0" 2>/dev/null || true
    sed -i -e "s|^gtk-theme-name=.*|gtk-theme-name=$TEMA_GTK|" \
           -e "s|^gtk-icon-theme-name=.*|gtk-icon-theme-name=$TEMA_ICONITE|" "$S/.config/gtk-3.0/settings.ini" 2>/dev/null || true

    # --- Dosare cu nume ca în Windows ---------------------------------------
    scrie "$S/.config/user-dirs.dirs" <<'EOF'
XDG_DESKTOP_DIR="$HOME/Desktop"
XDG_DOWNLOAD_DIR="$HOME/Descărcări"
XDG_TEMPLATES_DIR="$HOME/Șabloane"
XDG_PUBLICSHARE_DIR="$HOME/Public"
XDG_DOCUMENTS_DIR="$HOME/Documente"
XDG_MUSIC_DIR="$HOME/Muzică"
XDG_PICTURES_DIR="$HOME/Imagini"
XDG_VIDEOS_DIR="$HOME/Videoclipuri"
EOF
    echo "ro_RO" > "$S/.config/user-dirs.locale"
    local d
    for d in Desktop Descărcări Șabloane Public Documente Muzică Imagini Videoclipuri; do install -d "$S/$d"; done

    # --- Scurtături pe Desktop ----------------------------------------------
    # antiX dă lansatoarelor nume lungi în engleză; le punem nume scurte în română.
    local app nume
    while IFS='|' read -r app nume; do
        if [ -e "/usr/share/applications/$app.desktop" ]; then
            install -m 755 "/usr/share/applications/$app.desktop" "$S/Desktop/$app.desktop"
            sed -i -e '/^Name\[/d' -e '/^GenericName/d' -e "0,/^Name=.*/s//Name=$nume/" "$S/Desktop/$app.desktop"
        else
            avert "Lipsește $app.desktop"
        fi
    done <<'LISTA'
libreoffice-writer|Documente (Writer)
libreoffice-calc|Tabele (Calc)
libreoffice-impress|Prezentări (Impress)
com.github.maoschanz.drawing|Desen
firefox-esr|Internet (Firefox)
LISTA
    [ -n "$LUCRARI_DIR" ] && ln -sfn "$LUCRARI_DIR" "$S/Desktop/Lucrări (nu se șterg)"

    # --- LibreOffice: interfață cu file și salvare în formatele Office -------
    scrie "$S/.config/libreoffice/4/user/registrymodifications.xcu" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<oor:items xmlns:oor="http://openoffice.org/2001/registry" xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
<item oor:path="/org.openoffice.Setup/Office/Factories/org.openoffice.Setup:Factory['com.sun.star.text.TextDocument']"><prop oor:name="ooSetupFactoryDefaultFilter" oor:op="fuse"><value>MS Word 2007 XML</value></prop></item>
<item oor:path="/org.openoffice.Setup/Office/Factories/org.openoffice.Setup:Factory['com.sun.star.sheet.SpreadsheetDocument']"><prop oor:name="ooSetupFactoryDefaultFilter" oor:op="fuse"><value>Calc MS Excel 2007 XML</value></prop></item>
<item oor:path="/org.openoffice.Setup/Office/Factories/org.openoffice.Setup:Factory['com.sun.star.presentation.PresentationDocument']"><prop oor:name="ooSetupFactoryDefaultFilter" oor:op="fuse"><value>Impress MS PowerPoint 2007 XML</value></prop></item>
<item oor:path="/org.openoffice.Office.Common/Save/Document"><prop oor:name="WarnAlienFormat" oor:op="fuse"><value>false</value></prop></item>
<item oor:path="/org.openoffice.Office.Common/Misc"><prop oor:name="ShowTipOfTheDay" oor:op="fuse"><value>false</value></prop></item>
<item oor:path="/org.openoffice.Office.UI.ToolbarMode/Applications/org.openoffice.Office.UI.ToolbarMode:Application['Writer']"><prop oor:name="Active" oor:op="fuse"><value>notebookbar.ui</value></prop></item>
<item oor:path="/org.openoffice.Office.UI.ToolbarMode/Applications/org.openoffice.Office.UI.ToolbarMode:Application['Calc']"><prop oor:name="Active" oor:op="fuse"><value>notebookbar.ui</value></prop></item>
<item oor:path="/org.openoffice.Office.UI.ToolbarMode/Applications/org.openoffice.Office.UI.ToolbarMode:Application['Impress']"><prop oor:name="Active" oor:op="fuse"><value>notebookbar.ui</value></prop></item>
<item oor:path="/org.openoffice.Office.UI.Notebookbar/Applications/org.openoffice.Office.UI.Notebookbar:Application['Writer']"><prop oor:name="Active" oor:op="fuse"><value>notebookbar.ui</value></prop></item>
<item oor:path="/org.openoffice.Office.UI.Notebookbar/Applications/org.openoffice.Office.UI.Notebookbar:Application['Calc']"><prop oor:name="Active" oor:op="fuse"><value>notebookbar.ui</value></prop></item>
<item oor:path="/org.openoffice.Office.UI.Notebookbar/Applications/org.openoffice.Office.UI.Notebookbar:Application['Impress']"><prop oor:name="Active" oor:op="fuse"><value>notebookbar.ui</value></prop></item>
</oor:items>
EOF

    # Fără fereastra „Bun venit" / „Ce e nou" (altfel apare după fiecare resetare).
    local lo_ver_scurt
    lo_ver_scurt="$(dpkg-query -W -f='${Version}' libreoffice-core 2>/dev/null | sed -E 's/^[0-9]+://; s/^([0-9]+\.[0-9]+).*/\1/')"
    if [ -n "$lo_ver_scurt" ]; then
        sed -i "s|</oor:items>|<item oor:path=\"/org.openoffice.Setup/Product\"><prop oor:name=\"ooSetupLastVersion\" oor:op=\"fuse\"><value>$lo_ver_scurt</value></prop></item>\n<item oor:path=\"/org.openoffice.Office.Common/Misc\"><prop oor:name=\"FirstRun\" oor:op=\"fuse\"><value>false</value></prop></item>\n</oor:items>|" \
            "$S/.config/libreoffice/4/user/registrymodifications.xcu"
    fi

    if [ -d "$SABLON" ]; then
        rm -rf "$DATE_DIR/sablon.anterior"; mv "$SABLON" "$DATE_DIR/sablon.anterior"
        avert "Șablonul vechi e păstrat în $DATE_DIR/sablon.anterior"
    fi
    mv "$S" "$SABLON"
    ok "Profil: bară jos, meniu Start, temă $TEMA_ICEWM / $TEMA_GTK / $TEMA_ICONITE"
}

# =============================================================================
instaleaza_scripturi() {
    pas "Instalez comenzile de administrare"

    cat > /usr/local/sbin/cont-elev <<EOF
#!/bin/bash
# Instalat de configurare-antix.sh — administrarea contului comun al elevilor.
ELEV="$ELEV_USER"
DATE_DIR="$DATE_DIR"
EOF
    cat >> /usr/local/sbin/cont-elev <<'EOF'
set -euo pipefail
SABLON="$DATE_DIR/sablon"
PAUZA="$DATE_DIR/pauza"
ACASA="$(getent passwd "$ELEV" | cut -d: -f6)"
[ -n "$ACASA" ] && [ "$ACASA" != "/" ] || { echo "Nu găsesc contul $ELEV."; exit 1; }

este_logat() { who | awk '{print $1}' | grep -x "$ELEV" >/dev/null; }

reseteaza() {
    [ -d "$SABLON" ] || { echo "Lipsește șablonul $SABLON"; exit 1; }
    pkill -KILL -u "$ELEV" 2>/dev/null || true
    sleep 1
    rsync -a --delete "$SABLON"/ "$ACASA"/
    chown -R "$ELEV:$ELEV" "$ACASA"
    chmod 750 "$ACASA"
}

ajutor() {
    cat <<TXT
Administrarea contului „$ELEV" (rulează cu sudo):

  sudo cont-elev stare        arată dacă resetarea automată e pornită
  sudo cont-elev pauza        oprește resetarea (ca să poți schimba ceva în contul elevului)
  sudo cont-elev salveaza     salvează contul elevului, așa cum e acum, ca nou șablon
                              (și repornește resetarea automată)
  sudo cont-elev porneste     repornește resetarea automată, fără a salva
  sudo cont-elev reseteaza    resetează chiar acum contul elevului
  sudo cont-elev anuleaza     revine la șablonul de dinainte de ultima salvare

Cum schimbi ce văd elevii (iconițe, fundal, programe pe Desktop):
  1. sudo cont-elev pauza
  2. ieși din sesiune, intră ca „$ELEV", fă modificările, ieși din sesiune
  3. intră din nou ca profesor:  sudo cont-elev salveaza
TXT
}

case "${1:-ajutor}" in
    stare|ajutor) ;;
    *) [ "$(id -u)" -eq 0 ] || { echo "Rulează cu sudo:  sudo cont-elev ${1:-}"; exit 1; } ;;
esac

case "${1:-ajutor}" in
    auto)   # chemat de slimski la intrarea și la ieșirea elevului din sesiune
        [ -e "$PAUZA" ] && exit 0
        reseteaza ;;
    reseteaza|reset)
        if este_logat; then echo "Elevul este încă logat. Mai întâi ieși din sesiunea lui."; exit 1; fi
        reseteaza; echo "Contul $ELEV a fost resetat." ;;
    pauza)
        touch "$PAUZA"
        echo "Resetarea automată este OPRITĂ. Modificările din contul $ELEV se păstrează."
        echo "Când termini: sudo cont-elev salveaza" ;;
    porneste)
        rm -f "$PAUZA"; echo "Resetarea automată este PORNITĂ." ;;
    salveaza)
        if este_logat; then echo "Elevul este încă logat. Ieși din sesiunea lui, apoi rulează din nou."; exit 1; fi
        pkill -KILL -u "$ELEV" 2>/dev/null || true
        rm -rf "$DATE_DIR/sablon.nou"
        rsync -a --delete \
            --exclude='.cache/' --exclude='.local/share/Trash/' \
            --exclude='.xsession-errors*' --exclude='.local/share/recently-used.xbel' \
            --exclude='.mozilla/firefox-esr/*/cache2/' --exclude='.mozilla/firefox/*/cache2/' \
            "$ACASA"/ "$DATE_DIR/sablon.nou"/
        rm -rf "$DATE_DIR/sablon.anterior"
        [ -d "$SABLON" ] && mv "$SABLON" "$DATE_DIR/sablon.anterior"
        mv "$DATE_DIR/sablon.nou" "$SABLON"
        rm -f "$PAUZA"
        echo "Șablon salvat. Resetarea automată este PORNITĂ."
        echo "(Dacă ceva nu e bine: sudo cont-elev anuleaza)" ;;
    anuleaza)
        [ -d "$DATE_DIR/sablon.anterior" ] || { echo "Nu există un șablon anterior."; exit 1; }
        rm -rf "$DATE_DIR/sablon.nou"
        mv "$SABLON" "$DATE_DIR/sablon.nou"
        mv "$DATE_DIR/sablon.anterior" "$SABLON"
        mv "$DATE_DIR/sablon.nou" "$DATE_DIR/sablon.anterior"
        echo "Am revenit la șablonul anterior. Se aplică la următoarea resetare." ;;
    stare)
        if [ -e "$PAUZA" ]; then echo "Resetare automată: OPRITĂ (pauză)"; else echo "Resetare automată: PORNITĂ"; fi
        if este_logat; then echo "Elevul este logat acum."; fi ;;
    *) ajutor ;;
esac
EOF
    chmod 755 /usr/local/sbin/cont-elev

    # slimski rulează (ca root) comanda asta la începutul și la sfârșitul fiecărei
    # sesiuni. Păstrăm înregistrarea sessreg pe care o făcea antiX.
    cat > /usr/local/sbin/cont-elev-sesiune <<EOF
#!/bin/sh
# Instalat de configurare-antix.sh — chemat de slimski: cont-elev-sesiune start|stop UTILIZATOR
ELEV="$ELEV_USER"
EOF
    cat >> /usr/local/sbin/cont-elev-sesiune <<'EOF'
faza="$1"; utilizator="$2"
case "$faza" in
    start)
        /usr/local/sbin/sala-servicii >/dev/null 2>&1
        [ "$utilizator" = "$ELEV" ] && /usr/local/sbin/cont-elev auto >/dev/null 2>&1
        /usr/bin/sessreg -a -l "${DISPLAY:-:0}" "$utilizator" 2>/dev/null ;;
    stop)
        /usr/bin/sessreg -d -l "${DISPLAY:-:0}" "$utilizator" 2>/dev/null
        [ "$utilizator" = "$ELEV" ] && /usr/local/sbin/cont-elev auto >/dev/null 2>&1 ;;
esac
exit 0
EOF
    chmod 755 /usr/local/sbin/cont-elev-sesiune
    ok "Comanda pentru profesor: sudo cont-elev"
}

# =============================================================================
seteaza_slimski() {   # $1 = opțiune, $2 = valoare (înlocuiește sau adaugă linia)
    if grep -E "^$1[[:space:]]" "$SLIMSKI_CONF" >/dev/null; then
        sed -i -E "s|^$1[[:space:]].*|$1    $2|" "$SLIMSKI_CONF"
    else
        printf '%s    %s\n' "$1" "$2" >> "$SLIMSKI_CONF"
    fi
}

creeaza_cont_elev() {
    pas "Contul „$ELEV_USER\""
    if ! id "$ELEV_USER" >/dev/null 2>&1; then
        useradd -m -s /bin/bash -c "$ELEV_NUME" "$ELEV_USER"
        ok "Cont creat"
    else
        ok "Contul există deja"
    fi
    echo "$ELEV_USER:$ELEV_PAROLA" | chpasswd
    # Grupuri pentru sunet, stick-uri, imprimantă — dar NU sudo (antiX îl pune implicit).
    local g
    for g in audio video plugdev users cdrom floppy netdev scanner lp dialout fuse; do
        getent group "$g" >/dev/null && gpasswd -a "$ELEV_USER" "$g" >/dev/null
    done
    for g in sudo adm lpadmin sambashare; do
        if id -nG "$ELEV_USER" | tr ' ' '\n' | grep -x "$g" >/dev/null; then gpasswd -d "$ELEV_USER" "$g" >/dev/null; fi
    done
    ok "Fără drepturi de administrator, parola: $ELEV_PAROLA"

    if [ -n "$LUCRARI_DIR" ]; then
        install -d -o "$ELEV_USER" -g "$ELEV_USER" -m 2775 "$LUCRARI_DIR"
        ok "Dosarul $LUCRARI_DIR nu se șterge (pe Desktop: „Lucrări (nu se șterg)\")"
    fi

    [ -f "$SLIMSKI_CONF.inainte-de-sala" ] || cp -a "$SLIMSKI_CONF" "$SLIMSKI_CONF.inainte-de-sala"
    seteaza_slimski sessionstart_cmd "/usr/local/sbin/cont-elev-sesiune start %username"
    seteaza_slimski sessionstop_cmd  "/usr/local/sbin/cont-elev-sesiune stop %username"
    seteaza_slimski default_sessiontype "zzz-icewm"
    if [ "$AUTOLOGIN" = "1" ]; then
        seteaza_slimski autologin_enabled "true"
        seteaza_slimski default_user "$ELEV_USER"
        ok "La pornire intră automat în contul elev"
    else
        seteaza_slimski autologin_enabled "false"
    fi
    ok "Ecranul de logare (slimski) resetează contul la intrare și la ieșire"

    if este_logat "$ELEV_USER"; then
        avert "Elevul este logat acum; profilul nou se aplică la următoarea logare"
    else
        /usr/local/sbin/cont-elev reseteaza >/dev/null
        ok "Contul elev are profilul nou"
    fi
}

# =============================================================================
rezumat() {
    pas "Gata!"
    if [ "${#PASI_ESUATI[@]}" -gt 0 ]; then
        avert "Pași care nu au reușit (restul e configurat): ${PASI_ESUATI[*]}"
    fi
    cat <<EOF

  Repornește calculatorul:  sudo reboot

  • Contul elevilor: „$ELEV_USER" (parola „$ELEV_PAROLA")$( [ "$AUTOLOGIN" = 1 ] && echo ", intră automat la pornire")
  • Tot ce schimbă elevii se șterge la ieșire și la repornire,
    în afară de dosarul ${LUCRARI_DIR:-(dezactivat)}.
  • Profesorul: ieși din sesiune și scrie numele contului tău în ecranul de logare.
  • Ajutor pentru contul elev:  sudo cont-elev ajutor
  • Setările vechi ale ecranului de logare: $SLIMSKI_CONF.inainte-de-sala

EOF
}

main() {
    touch "$LOG"; chmod 600 "$LOG"
    exec > >(tee -a "$LOG") 2>&1
    echo "===== configurare-antix.sh — $(date '+%Y-%m-%d %H:%M') ====="
    verificari
    instaleaza_pachete
    optimizeaza_memoria
    seteaza_limba_tastatura
    instaleaza_teme
    instaleaza_scripturi
    construieste_sablon
    creeaza_cont_elev
    rezumat
}

main "$@"
