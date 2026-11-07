#!/usr/bin/env bash
# =============================================================================
#  configurare-q4os.sh — pregătește un calculator slab (2 GB RAM, HDD) din sala
#  de informatică pe Q4OS 6.x Trinity (64 biți): aspect apropiat de Windows 10,
#  optimizat pentru memorie puțină, în limba română, cu un cont „elev" care
#  revine la starea inițială la fiecare intrare / ieșire / repornire.
#
#  Folosire (ca administrator, cu internet):
#      sudo bash configurare-q4os.sh
#
#  Scriptul poate fi rulat de mai multe ori. Setările se pot schimba mai jos
#  sau din linia de comandă:  sudo ELEV_PAROLA=1234 bash configurare-q4os.sh
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
RESURSE=/usr/share/sala
FUNDAL="$RESURSE/fundal.png"
TDM_DIR=/etc/trinity/tdm
PASI_ESUATI=()

albastru=$'\033[1;34m'; verde=$'\033[1;32m'; galben=$'\033[1;33m'; rosu=$'\033[1;31m'; gri=$'\033[0m'
pas()    { printf '\n%s==> %s%s\n' "$albastru" "$*" "$gri"; }
ok()     { printf '%s    ✔ %s%s\n' "$verde" "$*" "$gri"; }
avert()  { printf '%s    ! %s%s\n' "$galben" "$*" "$gri"; }
eroare() { printf '%s    ✘ %s%s\n' "$rosu" "$*" "$gri" >&2; }
trap 'eroare "Eroare neașteptată la linia $LINENO (comanda: $BASH_COMMAND). Vezi $LOG"' ERR

scrie() { install -d "$(dirname "$1")"; cat > "$1"; }
are_systemd() { [ -d /run/systemd/system ]; }
este_logat() { who | awk '{print $1}' | grep -x "$1" >/dev/null; }
optional() {
    local descriere="$1"; shift
    if "$@"; then ok "$descriere"; else avert "Nu a reușit: $descriere"; PASI_ESUATI+=("$descriere"); fi
}

# =============================================================================
verificari() {
    pas "Verificări"
    if [ "$(id -u)" -ne 0 ]; then
        eroare "Rulează scriptul ca administrator:  sudo bash $0"; exit 1
    fi
    if [ "$(uname -m)" != "x86_64" ]; then
        eroare "Scriptul e pentru Q4OS pe 64 de biți."; exit 1
    fi
    if [ -f /etc/q4os_version ]; then
        ok "Q4OS $(cat /etc/q4os_version)"
    else
        avert "Nu pare a fi Q4OS. Continui, dar unele lucruri pot să nu meargă."
    fi
    if [ -f /etc/q4oslivemedia ] && grep -qs ' / overlay' /proc/mounts; then
        eroare "Rulezi Q4OS de pe stick (live). Instalează-l mai întâi pe disc."; exit 1
    fi
    for f in /opt/trinity/bin/kicker "$TDM_DIR/tdmrc"; do
        [ -e "$f" ] || { eroare "Lipsește $f — ai nevoie de Q4OS cu desktopul Trinity (TDE)."; exit 1; }
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
        rsync unzip wget python3 zram-tools earlyoom \
        libreoffice-writer libreoffice-calc libreoffice-impress libreoffice-gtk3 \
        firefox-esr kolourpaint-trinity
    ok "LibreOffice, Firefox, KolourPaint (în loc de Paint), zram, earlyoom"

    local dorite=(tde-i18n-ro-trinity libreoffice-l10n-ro hunspell-ro hyphen-ro mythes-ro firefox-esr-l10n-ro)
    local existente=() p
    for p in "${dorite[@]}"; do
        if [[ "$(LC_ALL=C apt-cache policy "$p" 2>/dev/null)" == *"Candidate: "[!\(]* ]]; then
            existente+=("$p")
        fi
    done
    if [ "${#existente[@]}" -gt 0 ]; then
        apt-get "${apt_opt[@]}" install --no-install-recommends "${existente[@]}"
    fi
    ok "Limba română: ${existente[*]:-nimic de instalat}"
}

# =============================================================================
optimizeaza_memoria() {
    pas "Optimizez pentru 2 GB RAM și HDD"

    cat > /etc/default/zramswap <<'EOF'
# Configurat de configurare-q4os.sh
ALGO=zstd
PERCENT=100
PRIORITY=100
EOF
    cat > /etc/sysctl.d/90-sala-zram.conf <<'EOF'
# Configurat de configurare-q4os.sh: folosește zram mai devreme.
vm.swappiness=150
vm.page-cluster=0
EOF
    sysctl -q --system >/dev/null 2>&1 || true
    if are_systemd; then optional "zram pornit" systemctl enable --now zramswap.service; fi

    cat > /etc/default/earlyoom <<'EOF'
# Configurat de configurare-q4os.sh. Închide o filă de browser când se termină
# memoria; nu închide niciodată LibreOffice sau KolourPaint (lucrarea elevului).
EARLYOOM_ARGS="-r 0 -m 5 -s 10 --prefer '(^|/)(Web Content|Isolated Web Co|WebExtensions)$' --avoid '(^|/)(init|systemd|Xorg|tdm|twin|kicker|kdesktop|tdeinit|soffice.bin|kolourpaint)$'"
EOF
    if are_systemd; then
        optional "earlyoom pornit" systemctl enable --now earlyoom.service
        systemctl restart earlyoom.service 2>/dev/null || true
    fi

    echo bfq > /etc/modules-load.d/sala-bfq.conf
    cat > /etc/udev/rules.d/60-sala-hdd-bfq.rules <<'EOF'
# Configurat de configurare-q4os.sh: BFQ pentru discurile rotative (HDD)
ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
EOF
    modprobe bfq 2>/dev/null || true
    ok "BFQ pentru HDD"

    local politica d
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
        -e "s/^XKBOPTIONS=.*/XKBOPTIONS=\"$COMUTARE_TASTATURA\"/" \
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
    TEMA_GTK="Adwaita"; TEMA_ICONITE="crystalsvg"
    if [ "$TEMA_WIN10" = "1" ]; then
        if descarca_tema https://github.com/B00merang-Project/Windows-10/archive/refs/heads/master.zip \
                         /usr/share/themes/Windows-10; then
            TEMA_GTK="Windows-10"; ok "Tema GTK Windows 10 (Firefox, LibreOffice)"
        else
            avert "Nu am putut descărca tema GTK Windows 10"; PASI_ESUATI+=("tema GTK")
        fi
        if descarca_tema https://github.com/B00merang-Artwork/Windows-10/archive/refs/heads/master.zip \
                         /usr/share/icons/Windows-10; then
            # Iconițele care lipsesc (multe nume specifice Trinity) se iau din crystalsvg.
            sed -i '/^Inherits=/d' /usr/share/icons/Windows-10/index.theme
            sed -i '/^\[Icon Theme\]/a Inherits=crystalsvg,hicolor' /usr/share/icons/Windows-10/index.theme
            ln -sfn /usr/share/icons/Windows-10 /opt/trinity/share/icons/Windows-10
            TEMA_ICONITE="Windows-10"; ok "Iconițe Windows 10"
        else
            avert "Nu am putut descărca iconițele Windows 10"; PASI_ESUATI+=("iconițe")
        fi
    fi

    # Imagini generate aici: fundal albastru, fundalul închis al barei de jos
    # și butonul Start (grilă de 3x3 pătrățele albe).
    install -d "$RESURSE"
    python3 - "$RESURSE" <<'PY'
import struct, sys, zlib
D = sys.argv[1]
def png(path, w, h, pixel):
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        for x in range(w):
            raw += bytes(pixel(x, y))
    def bucata(tip, date):
        return struct.pack(">I", len(date)) + tip + date + struct.pack(">I", zlib.crc32(tip + date) & 0xFFFFFFFF)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + bucata(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
                + bucata(b"IDAT", zlib.compress(bytes(raw), 9)) + bucata(b"IEND", b""))

sus, jos = (4, 20, 48), (0, 110, 200)
W, H = 1920, 1080
cache = {}
def fundal(x, y):
    t = max(0.0, min(1.0, 0.55 * ((x // 8 * 8) / (W - 1)) + 0.45 * (1 - y / (H - 1)))) ** 1.6
    k = round(t * 255)
    if k not in cache:
        cache[k] = tuple(int(sus[i] + (jos[i] - sus[i]) * k / 255) for i in range(3)) + (255,)
    return cache[k]
png(f"{D}/fundal.png", W, H, fundal)
png(f"{D}/bara.png", 64, 64, lambda x, y: (32, 32, 32, 255))
def start(x, y):
    for gx in range(3):
        for gy in range(3):
            bx, by = 4 + gx * 9, 4 + gy * 9
            if bx <= x < bx + 6 and by <= y < by + 6:
                return (255, 255, 255, 255)
    return (0, 0, 0, 0)
png(f"{D}/start.png", 32, 32, start)
PY
    chmod -R a+rX "$RESURSE"
    ok "Fundal de ecran, bara de jos, butonul Start"
}

# =============================================================================
construieste_sablon() {
    pas "Construiesc profilul contului „$ELEV_USER\""
    local S="$DATE_DIR/sablon.nou" ACASA="/home/$ELEV_USER"
    rm -rf "$S"; install -d -m 700 "$DATE_DIR"; install -d "$S"
    cp -a /etc/skel/. "$S"/
    local C="$S/.trinity/share/config"

    # --- Fără asistentul Q4OS de la prima logare -----------------------------
    scrie "$S/.local/share/q4os/.frstlogq4.stp" <<'EOF'
[install]
desc=do_not_delete_this_file
timestamp=configurare-q4os
EOF
    printf '[General]\nfirst_login=false\n' | scrie "$C/q4osrc"
    printf '[General]\nFirstLogin=false\n' | scrie "$C/kpersonalizerrc"
    printf '[KSplash]\nTheme=None\n' | scrie "$C/ksplashrc"
    printf '[Main]\nAutostart=false\nDisabled=true\n' | scrie "$C/khotkeysrc"
    printf '[General]\nloginMode=default\nconfirmLogout=true\n' | scrie "$C/ksmserverrc"

    # --- Culori, fonturi, iconițe, limbă (ca în Windows 10) ------------------
    scrie "$C/kdeglobals" <<EOF
[General]
background=240,240,240
foreground=0,0,0
windowBackground=255,255,255
windowForeground=0,0,0
buttonBackground=225,225,225
buttonForeground=0,0,0
selectBackground=0,120,215
selectForeground=255,255,255
linkColor=0,102,204
visitedLinkColor=102,0,153
alternateBackground=247,247,247
widgetStyle=q4os_tstyle02
font=DejaVu Sans,9,-1,5,50,0,0,0,0,0
menuFont=DejaVu Sans,9,-1,5,50,0,0,0,0,0
taskbarFont=DejaVu Sans,9,-1,5,50,0,0,0,0,0
toolBarFont=DejaVu Sans,9,-1,5,50,0,0,0,0,0
fixed=DejaVu Sans Mono,9,-1,5,50,0,0,0,0,0
XftAntialias=true
XftHintStyle=hintslight
XftSubPixel=rgb

[WM]
activeBackground=255,255,255
activeBlend=255,255,255
activeForeground=0,0,0
activeTitleBtnBg=255,255,255
inactiveBackground=255,255,255
inactiveBlend=255,255,255
inactiveForeground=153,153,153
inactiveTitleBtnBg=255,255,255
activeFont=DejaVu Sans,10,-1,5,50,0,0,0,0,0

[Icons]
Theme=$TEMA_ICONITE

[DesktopIcons]
Size=32

[Locale]
Language=ro
Country=md

[KDE]
SingleClick=false
ShowIconsOnPushButtons=true

[Paths]
Trash[\$e]=\$HOME/Desktop/Trash/

[\$Version]
update_info=tdeaccel.upd:trinity.3/r1,mouse_cursor_theme.upd:trinity.4.99,socks.upd:trinity.0/r1,kded.upd:trinity.0,twin.upd:trinity.2Xinerama,klippershortcuts.upd:04112002
EOF

    # --- Ferestre: albe, butoanele _ □ ✕ în dreapta, un singur spațiu de lucru
    scrie "$C/twinrc" <<'EOF'
[Style]
PLUGIN=twin3_plastik
CustomButtonPositions=true
ButtonsOnLeft=M
ButtonsOnRight=IAX
ShowToolTips=true

[Desktops]
Number=1

[Windows]
FocusPolicy=ClickToFocus
EOF
    scrie "$C/twinplastikrc" <<'EOF'
[General]
TitleAlignment=AlignLeft
TitleShadow=false
AnimateButtons=false
ColoredBorder=false
MenuClose=false
EOF

    # --- Bara de jos ca în Windows 10 -----------------------------------------
    scrie "$C/kickerrc" <<EOF
[\$Version]
update_info=kickerrc.upd:kde_3_1_sizeChanges,kickerrc.upd:kde_3_4_reverseLayout

[General]
Position=3
Size=4
CustomSize=40
Locked=true
Transparent=false
UseBackgroundTheme=true
BackgroundTheme=$RESURSE/bara.png
ColorizeBackground=false
ShowLeftHideButton=false
ShowRightHideButton=false
UseResizeHandle=false
LegacyKMenu=false
IExist=true
Applets2=KMenuButton_1,ServiceButton_1,ServiceButton_2,ServiceButton_3,ServiceButton_4,ServiceButton_5,ServiceButton_6,Applet_1,Applet_2,Applet_3,DesktopButton_1

[menus]
MenuEntryFormat=NameOnly
FirstRun=true
Favorites=libreoffice-writer.desktop,libreoffice-calc.desktop,libreoffice-impress.desktop,tde-kolourpaint.desktop,firefox-esr.desktop,tde-Home.desktop

[KMenu]
CustomIcon=$RESURSE/start.png
ShowText=false
UseSearchBar=true

[buttons]
EnableIconZoom=false
EnableTileBackground=false

[KMenuButton_1]
FreeSpace2=0

[ServiceButton_1]
DesktopFile[\$e]=/opt/trinity/share/applications/tde/Home.desktop
StorageId[\$e]=tde-Home.desktop
FreeSpace2=0

[ServiceButton_2]
DesktopFile[\$e]=/usr/share/applications/firefox-esr.desktop
StorageId[\$e]=firefox-esr.desktop
FreeSpace2=0

[ServiceButton_3]
DesktopFile[\$e]=/usr/share/applications/libreoffice-writer.desktop
StorageId[\$e]=libreoffice-writer.desktop
FreeSpace2=0

[ServiceButton_4]
DesktopFile[\$e]=/usr/share/applications/libreoffice-calc.desktop
StorageId[\$e]=libreoffice-calc.desktop
FreeSpace2=0

[ServiceButton_5]
DesktopFile[\$e]=/usr/share/applications/libreoffice-impress.desktop
StorageId[\$e]=libreoffice-impress.desktop
FreeSpace2=0

[ServiceButton_6]
DesktopFile[\$e]=/opt/trinity/share/applications/tde/kolourpaint.desktop
StorageId[\$e]=tde-kolourpaint.desktop
FreeSpace2=0

[Applet_1]
ConfigFile[\$e]=taskbar_sala_rc
DesktopFile[\$e]=taskbarapplet.desktop
FreeSpace2=0.01

[Applet_2]
ConfigFile[\$e]=systemtray_panelappletrc
DesktopFile[\$e]=systemtrayapplet.desktop
FreeSpace2=1

[Applet_3]
ConfigFile[\$e]=clock_sala_rc
DesktopFile[\$e]=clockapplet.desktop
FreeSpace2=1

[DesktopButton_1]
FreeSpace2=1
EOF
    scrie "$C/ktaskbarrc" <<'EOF'
[$Version]
update_info=kickerrc.upd:kde_3_5_taskbarEnums

[General]
ShowAllWindows=true
ShowWindowListBtn=false
GroupTasks=1
DrawButtons=false
DisplayIconsNText=0
MaximumButtonWidth=200

[Appearance]
UseCustomColors=true
ActiveTaskTextColor=255,255,255
InactiveTaskTextColor=255,255,255
TaskBackgroundColor=60,60,60
EOF
    scrie "$C/taskbar_sala_rc" <<'EOF'
[General]
UseGlobalSettings=true
ShowAllWindows=true
ShowWindowListBtn=false
GroupTasks=1
DrawButtons=false
DisplayIconsNText=0
MaximumButtonWidth=200

[Appearance]
UseCustomColors=true
ActiveTaskTextColor=255,255,255
InactiveTaskTextColor=255,255,255
TaskBackgroundColor=60,60,60
EOF
    scrie "$C/clock_sala_rc" <<'EOF'
[General]
Type=Plain

[Plain]
Show_Date=true
Show_Seconds=false
Show_DayOfWeek=false
Foreground_Color=255,255,255
Background_Color=32,32,32
Font=DejaVu Sans,9,-1,5,50,0,0,0,0,0

[Date]
Foreground_Color=255,255,255
Background_Color=32,32,32
Font=DejaVu Sans,9,-1,5,50,0,0,0,0,0
EOF

    # --- Tastatura -----------------------------------------------------------
    local lista="" i=0 l v
    IFS=',' read -r -a _tl <<< "$TASTATURI"; IFS=',' read -r -a _tv <<< "$VARIANTE,"
    for l in "${_tl[@]}"; do
        v="${_tv[$i]:-}"; lista+="${lista:+,}$l${v:+($v)}"; i=$((i+1))
    done
    scrie "$C/kxkbrc" <<EOF
[Layout]
Use=true
LayoutList=$lista
Model=pc105
Options=$COMUTARE_TASTATURA
ResetOldOptions=true
EnableXkbOptions=true
ShowFlag=false
ShowSingle=false
EOF

    # --- Desktop: fundal, fără ecran de blocare --------------------------------
    scrie "$C/kdesktoprc" <<EOF
[Desktop0]
BackgroundMode=Flat
Color1=0,60,120
Wallpaper=$FUNDAL
WallpaperMode=ScaleAndCrop
MultiWallpaperMode=NoMulti

[Background Common]
CommonDesktop=true

[General]
CopyDesktopLinks=false
SetVRoot=false

[Desktop Icons]
LockIcons=false
AlwaysFirstItems=Acest PC.desktop,Coș de gunoi.desktop

[Menubar]
ShowMenubar=false

[ScreenSaver]
Enabled=false
Lock=false
EOF

    # --- Dosare cu nume ca în Windows ----------------------------------------
    local cfg d
    for cfg in .config .configtde; do
        scrie "$S/$cfg/user-dirs.dirs" <<'EOF'
XDG_DESKTOP_DIR="$HOME/Desktop"
XDG_DOWNLOAD_DIR="$HOME/Descărcări"
XDG_TEMPLATES_DIR="$HOME/Șabloane"
XDG_PUBLICSHARE_DIR="$HOME/Public"
XDG_DOCUMENTS_DIR="$HOME/Documente"
XDG_MUSIC_DIR="$HOME/Muzică"
XDG_PICTURES_DIR="$HOME/Imagini"
XDG_VIDEOS_DIR="$HOME/Videoclipuri"
EOF
        echo "ro_RO" > "$S/$cfg/user-dirs.locale"
        # Temă GTK pentru Firefox și LibreOffice
        scrie "$S/$cfg/gtk-3.0/settings.ini" <<EOF
[Settings]
gtk-theme-name=$TEMA_GTK
gtk-icon-theme-name=$TEMA_ICONITE
gtk-font-name=DejaVu Sans 9
EOF
    done
    for d in Desktop Descărcări Șabloane Public Documente Muzică Imagini Videoclipuri; do install -d "$S/$d"; done

    # --- Scurtături pe Desktop ----------------------------------------------
    scrie "$S/Desktop/Acest PC.desktop" <<'EOF'
[Desktop Entry]
Type=Link
Name=Acest PC
Icon=system
URL=media:/
EOF
    scrie "$S/Desktop/Coș de gunoi.desktop" <<'EOF'
[Desktop Entry]
Type=Link
Name=Coș de gunoi
Icon=trashcan_empty
EmptyIcon=trashcan_empty
URL=trash:/
EOF
    # Nume scurte în română în meniul Start (Kickoff afișează „GenericName").
    local app_id gen
    while IFS='|' read -r app_id gen; do
        for f in "/usr/share/applications/$app_id" "/opt/trinity/share/applications/tde/$app_id"; do
            [ -f "$f" ] || continue
            install -D -m 644 "$f" "$S/.local/share/applications/$app_id"
            sed -i -e '/^GenericName/d' -e "0,/^Name=.*/s//&\nGenericName=$gen/" "$S/.local/share/applications/$app_id"
            break
        done
    done <<'LISTA'
libreoffice-writer.desktop|Documente
libreoffice-calc.desktop|Tabele
libreoffice-impress.desktop|Prezentări
kolourpaint.desktop|Desen
firefox-esr.desktop|Internet
LISTA

    # Fără iconița „Install Q4OS" (vine de pe stick-ul de instalare).
    for cfg in .config .configtde; do
        printf '[Desktop Entry]\nType=Application\nName=calamares\nHidden=true\n' \
            | scrie "$S/$cfg/autostart/calamares-desktop-icon.desktop"
    done

    # Trinity afișează și legăturile sale implicite (My Computer, Web Browser...);
    # o copie personală cu Hidden=true le ascunde.
    for f in /opt/trinity/share/apps/kdesktop/Desktop/*; do
        [ -f "$f" ] || continue
        printf '[Desktop Entry]\nHidden=true\n' | scrie "$S/.trinity/share/apps/kdesktop/Desktop/$(basename "$f")"
    done
    local app f
    for app in /usr/share/applications/libreoffice-writer.desktop /usr/share/applications/libreoffice-calc.desktop \
               /usr/share/applications/libreoffice-impress.desktop /opt/trinity/share/applications/tde/kolourpaint.desktop \
               /usr/share/applications/firefox-esr.desktop; do
        if [ -e "$app" ]; then install -m 755 "$app" "$S/Desktop/$(basename "$app")"; else avert "Lipsește $app"; fi
    done
    [ -n "$LUCRARI_DIR" ] && ln -sfn "$LUCRARI_DIR" "$S/Desktop/Lucrări (nu se șterg)"

    # --- LibreOffice: interfață cu file și salvare în formatele Office -------
    # (Q4OS mută XDG_CONFIG_HOME în ~/.configtde, deci punem configurarea în ambele locuri.)
    local XCU="$S/.configtde/libreoffice/4/user/registrymodifications.xcu"
    scrie "$XCU" <<'EOF'
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
    local lo_ver_scurt
    lo_ver_scurt="$(dpkg-query -W -f='${Version}' libreoffice-core 2>/dev/null | sed -E 's/^[0-9]+://; s/^([0-9]+\.[0-9]+).*/\1/')"
    if [ -n "$lo_ver_scurt" ]; then
        sed -i "s|</oor:items>|<item oor:path=\"/org.openoffice.Setup/Product\"><prop oor:name=\"ooSetupLastVersion\" oor:op=\"fuse\"><value>$lo_ver_scurt</value></prop></item>\n<item oor:path=\"/org.openoffice.Office.Common/Misc\"><prop oor:name=\"FirstRun\" oor:op=\"fuse\"><value>false</value></prop></item>\n</oor:items>|" "$XCU"
    fi
    install -D -m 644 "$XCU" "$S/.config/libreoffice/4/user/registrymodifications.xcu"

    if [ -d "$SABLON" ]; then
        rm -rf "$DATE_DIR/sablon.anterior"; mv "$SABLON" "$DATE_DIR/sablon.anterior"
        avert "Șablonul vechi e păstrat în $DATE_DIR/sablon.anterior"
    fi
    mv "$S" "$SABLON"
    ok "Profil Trinity: bară jos închisă, meniu Start, ferestre albe, $TEMA_ICONITE"
}

# =============================================================================
instaleaza_scripturi() {
    pas "Instalez comenzile de administrare"

    cat > /usr/local/sbin/cont-elev <<EOF
#!/bin/bash
# Instalat de configurare-q4os.sh — administrarea contului comun al elevilor.
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
    auto)   # chemat la pornire și de TDM la intrarea / ieșirea elevului
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
            --exclude='.cache/' --exclude='.local/share/Trash/' --exclude='Desktop/Trash/' \
            --exclude='.xsession-errors*' --exclude='.local/share/recently-used.xbel' \
            --exclude='.DCOPserver_*' --exclude='.ICEauthority' --exclude='.mcop/' \
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

    # TDM rulează Xstartup (înainte de sesiune) și Xreset (după), ca root, cu $USER setat.
    local f
    for f in Xstartup Xreset; do
        [ -f "$TDM_DIR/$f" ] || continue
        [ -f "$TDM_DIR/$f.inainte-de-sala" ] || cp -a "$TDM_DIR/$f" "$TDM_DIR/$f.inainte-de-sala"
        sed -i '/# >>> sala/,/# <<< sala/d' "$TDM_DIR/$f"
        sed -i "1a # >>> sala: resetarea contului elevului (configurare-q4os.sh)\n[ \"\$USER\" = \"$ELEV_USER\" ] \&\& /usr/local/sbin/cont-elev auto >/dev/null 2>\&1\n# <<< sala" "$TDM_DIR/$f"
    done

    cat > /etc/systemd/system/cont-elev-reset.service <<'EOF'
[Unit]
Description=Resetează contul elevului la starea din șablon
After=local-fs.target
Before=display-manager.service tdm.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/cont-elev auto

[Install]
WantedBy=multi-user.target
EOF
    if are_systemd; then
        systemctl daemon-reload
        optional "Resetare la pornire activată" systemctl enable cont-elev-reset.service
    else
        ln -sf /etc/systemd/system/cont-elev-reset.service \
            /etc/systemd/system/multi-user.target.wants/cont-elev-reset.service 2>/dev/null || true
    fi
    ok "Comanda pentru profesor: sudo cont-elev"
}

# =============================================================================
seteaza_tdmrc() {   # $1 = secțiune, $2 = cheie, $3 = valoare
    python3 - "$TDM_DIR/tdmrc" "$1" "$2" "$3" <<'PY'
import sys, re
path, sect, key, val = sys.argv[1:]
lines = open(path).read().split("\n")
start = next((i for i, l in enumerate(lines) if l.strip() == f"[{sect}]"), None)
if start is None:
    lines += ["", f"[{sect}]", f"{key}={val}"]
else:
    end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("[")), len(lines))
    for i in range(start + 1, end):
        if re.match(rf"#?\s*{re.escape(key)}\s*=", lines[i]):
            lines[i] = f"{key}={val}"
            break
    else:
        lines.insert(start + 1, f"{key}={val}")
open(path, "w").write("\n".join(lines))
PY
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
    local g
    for g in audio video plugdev cdrom netdev scanner lp bluetooth; do
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

    [ -f "$TDM_DIR/tdmrc.inainte-de-sala" ] || cp -a "$TDM_DIR/tdmrc" "$TDM_DIR/tdmrc.inainte-de-sala"
    if [ "$AUTOLOGIN" = "1" ]; then
        seteaza_tdmrc "X-:0-Core" AutoLoginEnable true
        seteaza_tdmrc "X-:0-Core" AutoLoginUser "$ELEV_USER"
        seteaza_tdmrc "X-:0-Core" AutoLoginAgain false
        ok "La pornire intră automat în contul elev"
    else
        seteaza_tdmrc "X-:0-Core" AutoLoginEnable false
    fi
    ok "Ecranul de logare (TDM) resetează contul la intrare și la ieșire"

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
  • Profesorul: ieși din sesiune și alege contul tău în ecranul de logare.
  • Ajutor pentru contul elev:  sudo cont-elev ajutor
  • Setările vechi ale ecranului de logare: $TDM_DIR/*.inainte-de-sala

EOF
}

main() {
    touch "$LOG"; chmod 600 "$LOG"
    exec > >(tee -a "$LOG") 2>&1
    echo "===== configurare-q4os.sh — $(date '+%Y-%m-%d %H:%M') ====="
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
