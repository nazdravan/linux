#!/usr/bin/env bash
# =============================================================================
#  configurare-sala.sh — pregătește un calculator slab (2 GB RAM, HDD) din sala
#  de informatică: Linux Mint XFCE cu aspect de Windows 10, optimizat pentru
#  memorie puțină, cu tastatură română, cu un cont „elev" care revine la starea
#  inițială la fiecare repornire / ieșire din sesiune.
#
#  Testat pentru: Linux Mint 22.x și 23.x, ediția XFCE, 64 de biți.
#
#  Folosire (ca administrator, cu internet):
#      sudo bash configurare-sala.sh
#
#  Scriptul poate fi rulat de mai multe ori (de ex. după o actualizare).
#  Setările de mai jos se pot schimba direct aici sau din linia de comandă:
#      sudo ELEV_PAROLA=1234 AUTOLOGIN=0 bash configurare-sala.sh
# =============================================================================

# ---------------------------- SETĂRI -----------------------------------------
ELEV_USER="${ELEV_USER:-elev}"            # numele contului pentru elevi
ELEV_NUME="${ELEV_NUME:-Elev}"            # numele afișat la logare
ELEV_PAROLA="${ELEV_PAROLA:-elev}"        # parola contului elev
AUTOLOGIN="${AUTOLOGIN:-1}"               # 1 = la pornire intră direct în contul elev
RESETARE="${RESETARE:-Desktop .local/share/Trash}"   # se refac la resetare: Desktopul și Coșul ("tot" = tot contul)
LUCRARI_DIR="${LUCRARI_DIR:-/srv/lucrari}" # dosar care NU se șterge la resetare ("" = fără)
TASTATURI="${TASTATURI:-us,ro}"           # aranjamente tastatură (ex: "us,ro,ru")
VARIANTE="${VARIANTE:-,std}"              # variante (std = română standard, cu ș ț corecte)
COMUTARE_TASTATURA="${COMUTARE_TASTATURA:-grp:alt_shift_toggle}"   # Alt+Shift, ca în Windows
ARTCRAFT="${ARTCRAFT:-wordcraft gridcraft deckcraft pdfcraft}"   # programe ArtCraft (getartcraft.com/apps)
THONNY="${THONNY:-1}"                    # 1 = Thonny (Python pentru începători)
VSCODE="${VSCODE:-1}"                    # 1 = Visual Studio Code
CHROMIUM="${CHROMIUM:-1}"                # 1 = și Chromium (al doilea browser)
EXECUTANTI="${EXECUTANTI:-cangurul furnica}"   # executanți pentru algoritmi (github.com/nazdravan)
LIBREOFFICE="${LIBREOFFICE:-1}"          # 1 = și LibreOffice, de rezervă (în meniul cu toate programele)
TEMA_WIN10="${TEMA_WIN10:-1}"             # 1 = descarcă tema și iconițele Windows 10
ACTUALIZARE="${ACTUALIZARE:-1}"           # 1 = instalează și actualizările sistemului
# -----------------------------------------------------------------------------

set -Eeuo pipefail

DATE_DIR=/var/lib/cont-elev
SABLON="$DATE_DIR/sablon"
LOG=/var/log/configurare-sala.log
FUNDAL=/usr/share/backgrounds/sala/fundal.png
PASI_ESUATI=()

albastru=$'\033[1;34m'; verde=$'\033[1;32m'; galben=$'\033[1;33m'; rosu=$'\033[1;31m'; gri=$'\033[0m'
pas()    { printf '\n%s==> %s%s\n' "$albastru" "$*" "$gri"; }
ok()     { printf '%s    ✔ %s%s\n' "$verde" "$*" "$gri"; }
avert()  { printf '%s    ! %s%s\n' "$galben" "$*" "$gri"; }
eroare() { printf '%s    ✘ %s%s\n' "$rosu" "$*" "$gri" >&2; }
trap 'eroare "Eroare neașteptată la linia $LINENO (comanda: $BASH_COMMAND). Vezi $LOG"' ERR

# Rulează un pas opțional: dacă eșuează, continuăm și îl raportăm la final.
optional() {
    local descriere="$1"; shift
    if "$@"; then ok "$descriere"; else avert "Nu a reușit: $descriere"; PASI_ESUATI+=("$descriere"); fi
}

are_systemd() { [ -d /run/systemd/system ]; }

# =============================================================================
verificari() {
    pas "Verificări"
    if [ "$(id -u)" -ne 0 ]; then
        eroare "Rulează scriptul ca administrator:  sudo bash $0"; exit 1
    fi
    if [ "$(uname -m)" != "x86_64" ]; then
        eroare "Scriptul e pentru sisteme pe 64 de biți (x86_64)."; exit 1
    fi
    if [ -f /etc/linuxmint/info ]; then
        ok "$(grep -E '^DESCRIPTION=' /etc/linuxmint/info | cut -d= -f2- | tr -d '"')"
    else
        avert "Nu pare a fi Linux Mint. Continui, dar unele lucruri pot să nu meargă."
    fi
    if ! dpkg -s xfce4-panel >/dev/null 2>&1; then
        eroare "Nu găsesc XFCE. Instalează ediția Linux Mint XFCE."; exit 1
    fi
    if ! getent hosts github.com >/dev/null 2>&1; then
        avert "Nu pare să fie internet (nu găsesc github.com). Instalarea pachetelor poate eșua."
    fi
    ok "Jurnalul complet se scrie în $LOG"
}

# Pachete rămase instalate pe jumătate (de ex. un driver NVIDIA vechi care nu se compilează pentru
# nucleul nou) fac ca orice apt-get să eșueze. Încercăm să le terminăm; dacă nu se poate, explicăm.
verifica_dpkg() {
    dpkg --configure -a && return 0
    local stricate nv
    stricate="$(dpkg-query -W -f='${db:Status-Abbrev}|${Package}\n' 2>/dev/null \
                | awk -F'|' 'substr($1,2,1) ~ /[UFHWt]/ {print $2}' | sort -u | tr '\n' ' ')"
    eroare "Pachete instalate pe jumătate, care blochează apt: ${stricate:-necunoscute}"
    nv="$(grep -o 'nvidia-dkms-[0-9]*' <<<"$stricate" | head -n1 || true)"
    if [ -n "$nv" ]; then
        nv="${nv##*-}"
        eroare "Driverul NVIDIA $nv nu se poate compila pentru nucleul $(uname -r)."
        eroare "Alege alt driver din „Manager de drivere\" sau, din terminal, fie un driver mai nou:"
        eroare "    sudo apt-get install nvidia-driver-580"
        eroare "fie renunță la driverul NVIDIA (rămâne placa video integrată / nouveau):"
        eroare "    sudo apt-get purge 'nvidia.*-$nv\$' && sudo apt-get autoremove"
    else
        eroare "Repară-le întâi (sudo dpkg --configure -a; sudo apt-get -f install), apoi rulează din nou."
    fi
    eroare "Apoi pornește din nou acest script."
    exit 1
}

# =============================================================================
instaleaza_pachete() {
    pas "Instalez programele (poate dura 10-30 de minute pe HDD)"
    export DEBIAN_FRONTEND=noninteractive
    local apt_opt=(-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

    verifica_dpkg
    apt-get update
    if [ "$ACTUALIZARE" = "1" ]; then
        if apt-get "${apt_opt[@]}" dist-upgrade; then
            ok "Sistemul este actualizat"
        else
            verifica_dpkg
            avert "Actualizarea sistemului nu a reușit complet; continui cu instalarea programelor."
            PASI_ESUATI+=("actualizarea sistemului")
        fi
    fi

    # Pachete obligatorii
    apt-get "${apt_opt[@]}" install \
        rsync unzip wget python3 x11-xserver-utils \
        zram-tools earlyoom \
        xfce4-whiskermenu-plugin xfce4-pulseaudio-plugin xfce4-xkb-plugin \
        firefox
    ok "Pachete de bază"

    # KolourPaint (înlocuitor pentru Paint) fără pachetele recomandate KDE, ca să ocupe puțin.
    apt-get "${apt_opt[@]}" install --no-install-recommends kolourpaint
    ok "KolourPaint (în loc de Paint)"

}

# =============================================================================
# Programe care nu sunt în depozitele distribuției, publicate pe GitHub ca
# <nume>-<versiune>-linux-x86_64.deb + SHA256SUMS.txt:
#  - ArtCraft (https://getartcraft.com/apps): WordCraft, GridCraft, DeckCraft în loc de Word,
#    Excel, PowerPoint, plus PDFCraft pentru PDF-uri;
#  - executanții Cangurul și Furnica (github.com/nazdravan), pentru algoritmi.
# Luăm ultima versiune, o verificăm cu SHA256SUMS.txt și o instalăm cu apt (aduce și dependențele).
instaleaza_din_github() {
    local lista=() a
    for a in $ARTCRAFT; do lista+=("storytold/$a"); done
    for a in $EXECUTANTI; do lista+=("nazdravan/$a"); done
    pas "Programe de pe GitHub: ${ARTCRAFT} ${EXECUTANTI}"
    [ "${#lista[@]}" -gt 0 ] || return 0
    local apt_opt=(-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
    local tmp proiect app tag ver deb baza instalat debs=()
    tmp="$(mktemp -d)"; chmod 755 "$tmp"     # apt citește pachetele ca utilizatorul _apt
    for proiect in "${lista[@]}"; do
        app="${proiect#*/}"
        # …/releases/latest trimite la …/releases/tag/vX.Y.Z (fără API GitHub, fără limită)
        tag="$(wget -q -S --spider "https://github.com/$proiect/releases/latest" 2>&1 \
               | sed -n 's|.*[Ll]ocation: .*/releases/tag/\([^ ]*\).*|\1|p' | tail -n1 | tr -d '\r' || true)"
        if [ -z "$tag" ]; then
            avert "Nu găsesc ultima versiune $app (fără internet?)"; PASI_ESUATI+=("$app"); continue
        fi
        ver="${tag#v}"
        instalat="$(dpkg-query -W -f='${Version}' "$app" 2>/dev/null || true)"
        if [[ "$instalat" == "$ver" || "$instalat" == "$ver"-* ]]; then
            ok "$app $ver este deja instalat"; continue
        fi
        deb="$app-$ver-linux-x86_64.deb"
        baza="https://github.com/$proiect/releases/download/$tag"
        if wget -q -O "$tmp/$deb" "$baza/$deb" && wget -q -O "$tmp/SHA256SUMS-$app.txt" "$baza/SHA256SUMS.txt" \
           && (cd "$tmp" && grep "  $deb\$" "SHA256SUMS-$app.txt" | sha256sum -c --status -); then
            debs+=("$tmp/$deb")
        else
            avert "Nu am putut descărca sau verifica $deb"; PASI_ESUATI+=("$app")
        fi
    done
    if [ "${#debs[@]}" -gt 0 ]; then
        # Bibliotecile pe care programele le deschid la pornire (X11, Vulkan/OpenGL) și zenity,
        # pentru ferestrele Deschide/Salvează acolo unde nu există xdg-desktop-portal.
        local extra=() p
        for p in libx11-6 libx11-xcb1 libxkbcommon-x11-0 libxcursor1 libxi6 libxrandr2 \
                 libegl1 libgl1-mesa-dri mesa-vulkan-drivers zenity; do
            if [[ "$(LC_ALL=C apt-cache policy "$p" 2>/dev/null)" == *"Candidate: "[!\(]* ]]; then
                extra+=("$p")
            fi
        done
        if apt-get "${apt_opt[@]}" install --no-install-recommends "${debs[@]}" "${extra[@]}"; then
            ok "Instalat: $(printf '%s ' "${debs[@]##*/}")"
        else
            avert "Nu am putut instala programele de pe GitHub"; PASI_ESUATI+=("programele de pe GitHub")
        fi
    fi
    rm -rf "$tmp"
}

# =============================================================================
# LibreOffice, de rezervă pentru WordCraft/GridCraft/DeckCraft (fără pachetele de limbă).
instaleaza_libreoffice() {
    [ "$LIBREOFFICE" = "1" ] || return 0
    pas "LibreOffice (de rezervă)"
    local apt_opt=(-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
    if apt-get "${apt_opt[@]}" install --no-install-recommends \
            libreoffice-writer libreoffice-calc libreoffice-impress libreoffice-gtk3; then
        ok "LibreOffice Writer, Calc, Impress"
    else
        avert "Nu am putut instala LibreOffice"; PASI_ESUATI+=("LibreOffice")
    fi
}

# =============================================================================
# Programare: Thonny (Python, din depozitele distribuției) și Visual Studio Code (pachetul
# oficial Microsoft; la instalare își adaugă singur depozitul packages.microsoft.com, deci
# se actualizează apoi prin apt, ca restul sistemului).
instaleaza_programare() {
    pas "Programare: Thonny, Visual Studio Code"
    local apt_opt=(-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
    if [ "$THONNY" = "1" ]; then
        if apt-get "${apt_opt[@]}" install --no-install-recommends thonny; then ok "Thonny"
        else avert "Nu am putut instala Thonny"; PASI_ESUATI+=("Thonny"); fi
    fi
    [ "$VSCODE" = "1" ] || return 0
    if dpkg-query -W -f='${Status}' code 2>/dev/null | grep 'ok installed' >/dev/null; then
        ok "Visual Studio Code este deja instalat (se actualizează prin apt)"; return 0
    fi
    local tmp; tmp="$(mktemp -d)"; chmod 755 "$tmp"
    # Fără comanda „copilot" pusă în PATH pentru elevi.
    echo "code code/add-copilot-command boolean false" | debconf-set-selections 2>/dev/null || true
    if wget -q -O "$tmp/code.deb" "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64" \
       && dpkg-deb -f "$tmp/code.deb" Package 2>/dev/null | grep -x code >/dev/null \
       && apt-get "${apt_opt[@]}" install --no-install-recommends "$tmp/code.deb"; then
        ok "Visual Studio Code $(dpkg-query -W -f='${Version}' code 2>/dev/null | cut -d- -f1)"
    else
        avert "Nu am putut instala Visual Studio Code"; PASI_ESUATI+=("Visual Studio Code")
    fi
    rm -rf "$tmp"
}

# =============================================================================
# Chromium: al doilea browser (unele site-uri merg mai bine în el). Din depozitele
# distribuției (Linux Mint și Debian au pachet .deb, nu snap), fără pachetele de limbă.
# Politica: uBlock Origin Lite, fără procese în fundal după închidere, cache mic pe HDD.
instaleaza_chromium() {
    [ "$CHROMIUM" = "1" ] || return 0
    pas "Chromium"
    local apt_opt=(-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
    if ! apt-get "${apt_opt[@]}" install --no-install-recommends chromium; then
        avert "Nu am putut instala Chromium"; PASI_ESUATI+=("Chromium"); return 0
    fi
    local d
    for d in /etc/chromium/policies/managed /etc/chromium-browser/policies/managed; do
        install -d "$d"
        cat > "$d/sala.json" <<'EOF'
{
  "ExtensionInstallForcelist": ["ddkjiahejlhfcafbddmgiahcphecmpfh;https://clients2.google.com/service/update2/crx"],
  "BackgroundModeEnabled": false,
  "MetricsReportingEnabled": false,
  "DefaultBrowserSettingEnabled": false,
  "PromotionalTabsEnabled": false,
  "PasswordManagerEnabled": false,
  "DiskCacheSize": 52428800,
  "HighEfficiencyModeEnabled": true
}
EOF
    done
    ok "Chromium $(dpkg-query -W -f='${Version}' chromium 2>/dev/null | cut -d- -f1) (uBlock Origin Lite, setări pentru memorie puțină)"
}

# =============================================================================
optimizeaza_memoria() {
    pas "Optimizez pentru 2 GB RAM și HDD"

    # zram: memorie comprimată în RAM, folosită înaintea fișierului swap de pe HDD.
    cat > /etc/default/zramswap <<'EOF'
# Configurat de configurare-sala.sh
ALGO=zstd
PERCENT=100
PRIORITY=100
EOF
    cat > /etc/sysctl.d/90-sala-zram.conf <<'EOF'
# Configurat de configurare-sala.sh: folosește zram mai devreme, citește din swap câte o pagină.
vm.swappiness=150
vm.page-cluster=0
EOF
    sysctl -q --system >/dev/null 2>&1 || true
    if are_systemd; then
        optional "zram pornit" systemctl enable --now zramswap.service
    fi

    # earlyoom: dacă memoria se termină, închide o filă de browser în loc să blocheze
    # calculatorul minute întregi. Nu închide niciodată WordCraft, GridCraft, DeckCraft
    # sau KolourPaint (lucrarea elevului).
    cat > /etc/default/earlyoom <<'EOF'
# Configurat de configurare-sala.sh
EARLYOOM_ARGS="-r 0 -m 5 -s 10 --prefer '(^|/)(Web Content|Isolated Web Co|WebExtensions)$' --avoid '(^|/)(init|systemd|Xorg|lightdm|xfce4-session|xfwm4|xfce4-panel|xfdesktop|wordcraft|gridcraft|deckcraft|soffice.bin|thonny|code|cangurul|furnica|kolourpaint)$'"
EOF
    if are_systemd; then
        optional "earlyoom pornit" systemctl enable --now earlyoom.service
        systemctl restart earlyoom.service 2>/dev/null || true
    fi

    # Planificatorul BFQ pentru HDD: sistemul răspunde mai bine când discul e ocupat.
    echo bfq > /etc/modules-load.d/sala-bfq.conf
    cat > /etc/udev/rules.d/60-sala-hdd-bfq.rules <<'EOF'
# Configurat de configurare-sala.sh: BFQ pentru discurile rotative (HDD)
ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
EOF
    modprobe bfq 2>/dev/null || true
    udevadm control --reload 2>/dev/null || true
    udevadm trigger --subsystem-match=block --action=change 2>/dev/null || true
    ok "BFQ pentru HDD"

    # Servicii inutile într-o sală de calculatoare.
    if are_systemd; then
        local s
        for s in ModemManager.service cups-browsed.service; do
            if systemctl list-unit-files "$s" >/dev/null 2>&1 && systemctl cat "$s" >/dev/null 2>&1; then
                systemctl disable --now "$s" >/dev/null 2>&1 || true
                ok "Oprit serviciul $s"
            fi
        done
    fi

    # Firefox: mai puține procese, mai puține scrieri pe disc, uBlock Origin (reclamele
    # consumă multă memorie), fără ecrane de bun-venit.
    install -d /etc/firefox/policies
    cat > /etc/firefox/policies/policies.json <<'EOF'
{
  "policies": {
    "DisableTelemetry": true,
    "DisableFirefoxStudies": true,
    "DisablePocket": true,
    "DontCheckDefaultBrowser": true,
    "OverrideFirstRunPage": "",
    "OverridePostUpdatePage": "",
    "UserMessaging": {
      "WhatsNew": false,
      "ExtensionRecommendations": false,
      "FeatureRecommendations": false,
      "SkipOnboarding": true,
      "MoreFromMozilla": false
    },
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
}
EOF
    ok "Firefox: uBlock Origin și setări pentru memorie puțină"
}

# =============================================================================
seteaza_tastatura() {
    # Limba sistemului rămâne cea aleasă la instalare (engleza); adăugăm doar tastatura
    # română. Prima din listă (us) este cea implicită.
    pas "Tastatura: $TASTATURI"
    if [ -f /etc/default/keyboard ]; then
        sed -i \
            -e "s/^XKBLAYOUT=.*/XKBLAYOUT=\"$TASTATURI\"/" \
            -e "s/^XKBVARIANT=.*/XKBVARIANT=\"$VARIANTE\"/" \
            -e "s/^XKBOPTIONS=.*/XKBOPTIONS=\"$COMUTARE_TASTATURA\"/" \
            /etc/default/keyboard
    else
        cat > /etc/default/keyboard <<EOF
XKBMODEL="pc105"
XKBLAYOUT="$TASTATURI"
XKBVARIANT="$VARIANTE"
XKBOPTIONS="$COMUTARE_TASTATURA"
BACKSPACE="guess"
EOF
    fi
    ok "Tastatură: $TASTATURI (comutare cu Alt+Shift)"
}

# =============================================================================
descarca_tema() {   # $1 = URL arhivă, $2 = director destinație
    local url="$1" dest="$2" tmp src
    tmp="$(mktemp -d)"
    if ! wget -q -O "$tmp/arhiva.zip" "$url"; then rm -rf "$tmp"; return 1; fi
    if ! unzip -q "$tmp/arhiva.zip" -d "$tmp/x"; then rm -rf "$tmp"; return 1; fi
    src="$(find "$tmp/x" -mindepth 1 -maxdepth 1 -type d | head -n1)"
    if [ -z "$src" ] || [ ! -f "$src/index.theme" ]; then rm -rf "$tmp"; return 1; fi
    rm -rf "$dest"
    mv "$src" "$dest"
    chmod -R a+rX "$dest"
    rm -rf "$tmp"
}

instaleaza_tema() {
    pas "Tema Windows 10"
    TEMA_GTK="Mint-Y-Blue"; TEMA_ICONITE="Mint-Y-Blue"; TEMA_FERESTRE="Mint-Y-Blue"
    [ -d "/usr/share/themes/$TEMA_GTK" ] || TEMA_GTK="Mint-Y"
    [ -d "/usr/share/themes/$TEMA_FERESTRE" ] || TEMA_FERESTRE="Mint-Y"
    [ -d "/usr/share/icons/$TEMA_ICONITE" ] || TEMA_ICONITE="Mint-Y"

    if [ "$TEMA_WIN10" = "1" ]; then
        if descarca_tema https://github.com/B00merang-Project/Windows-10/archive/refs/heads/master.zip \
                         /usr/share/themes/Windows-10; then
            TEMA_GTK="Windows-10"; TEMA_FERESTRE="Windows-10"
            ok "Tema de ferestre Windows 10"
        else
            avert "Nu am putut descărca tema Windows 10; folosesc $TEMA_GTK"
            PASI_ESUATI+=("tema Windows 10")
        fi
        if descarca_tema https://github.com/B00merang-Artwork/Windows-10/archive/refs/heads/master.zip \
                         /usr/share/icons/Windows-10; then
            # Iconițele lipsă se iau din tema Mint, ca să nu apară pătrate goale.
            if ! grep -q '^Inherits=' /usr/share/icons/Windows-10/index.theme; then
                sed -i '/^\[Icon Theme\]/a Inherits=Mint-Y,Adwaita,hicolor' /usr/share/icons/Windows-10/index.theme
            fi
            gtk-update-icon-cache -f -q /usr/share/icons/Windows-10 2>/dev/null || true
            TEMA_ICONITE="Windows-10"
            ok "Iconițe Windows 10"
        else
            avert "Nu am putut descărca iconițele Windows 10; folosesc $TEMA_ICONITE"
            PASI_ESUATI+=("iconițe Windows 10")
        fi
    fi

    # Fundal albastru în stilul Windows 10 (generat aici, fără imagini protejate).
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
        t = 0.55 * (x / (W - 1)) + 0.45 * (1 - ty)
        t = max(0.0, min(1.0, t)) ** 1.6
        px = bytes(int(sus[i] + (jos[i] - sus[i]) * t) for i in range(3))
        rand += px * 8
    linii += rand[: W * 3]
def bucata(tip, date):
    return struct.pack(">I", len(date)) + tip + date + struct.pack(">I", zlib.crc32(tip + date) & 0xFFFFFFFF)
png = b"\x89PNG\r\n\x1a\n" + bucata(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0)) \
      + bucata(b"IDAT", zlib.compress(bytes(linii), 9)) + bucata(b"IEND", b"")
open(sys.argv[1], "wb").write(png)
PY
    chmod 644 "$FUNDAL"
    ok "Fundal de ecran"
}

# =============================================================================
#  Șablonul contului elev: tot ce se află aici e copiat în /home/elev la fiecare
#  resetare. Profesorul îl poate modifica (vezi: sudo cont-elev ajutor).
# =============================================================================
scrie() { install -d "$(dirname "$1")"; cat > "$1"; }

copiaza_lansator() {   # $1 = nume .desktop, $2 = destinație; întoarce 0 dacă există
    local f
    for f in "/usr/share/applications/$1" "/var/lib/snapd/desktop/applications/$1"; do
        if [ -f "$f" ]; then install -D -m 755 "$f" "$2"; return 0; fi
    done
    return 1
}

gaseste_lansator() {   # primul .desktop existent din listă
    local n
    for n in "$@"; do
        [ -f "/usr/share/applications/$n" ] && { echo "$n"; return 0; }
    done
    echo "$1"
}

construieste_sablon() {
    pas "Construiesc profilul contului „$ELEV_USER\""
    local S="$DATE_DIR/sablon.nou"
    rm -rf "$S"
    install -d -m 700 "$DATE_DIR"
    install -d "$S"
    cp -a /etc/skel/. "$S"/

    local X="$S/.config/xfce4/xfconf/xfce-perchannel-xml"
    local FIREFOX CHROMIUM_L THUNAR WORD EXCEL PPT PAINT THONNY VSCODE CANGUR FURNICA
    FIREFOX="$(gaseste_lansator firefox.desktop)"
    CHROMIUM_L=""   # doar dacă e instalat
    [ -f /usr/share/applications/chromium.desktop ] && CHROMIUM_L=chromium.desktop
    THUNAR="$(gaseste_lansator thunar.desktop Thunar.desktop)"
    WORD="$(gaseste_lansator ai.storyteller.wordcraft.desktop)"
    EXCEL="$(gaseste_lansator ai.storyteller.gridcraft.desktop)"
    PPT="$(gaseste_lansator ai.storyteller.deckcraft.desktop)"
    THONNY="$(gaseste_lansator org.thonny.Thonny.desktop thonny.desktop)"
    VSCODE="$(gaseste_lansator code.desktop)"
    CANGUR="$(gaseste_lansator cangurul.desktop)"
    FURNICA="$(gaseste_lansator furnica.desktop)"
    PAINT="$(gaseste_lansator org.kde.kolourpaint.desktop kolourpaint.desktop)"

    # --- Bara de jos ca în Windows 10 ---------------------------------------
    scrie "$X/xfce4-panel.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-panel" version="1.0">
  <property name="configver" type="int" value="2"/>
  <property name="panels" type="array">
    <value type="int" value="1"/>
    <property name="dark-mode" type="bool" value="true"/>
    <property name="panel-1" type="empty">
      <property name="position" type="string" value="p=8;x=0;y=0"/>
      <property name="length" type="uint" value="100"/>
      <property name="position-locked" type="bool" value="true"/>
      <property name="size" type="uint" value="40"/>
      <property name="icon-size" type="uint" value="24"/>
      <property name="nrows" type="uint" value="1"/>
      <property name="plugin-ids" type="array">
        <value type="int" value="1"/>
        <value type="int" value="9"/>
        <value type="int" value="10"/>
        <value type="int" value="2"/>
        <value type="int" value="3"/>
        <value type="int" value="4"/>
        <value type="int" value="5"/>
        <value type="int" value="6"/>
        <value type="int" value="7"/>
        <value type="int" value="8"/>
      </property>
    </property>
  </property>
  <property name="plugins" type="empty">
    <property name="plugin-1" type="string" value="whiskermenu"/>
    <property name="plugin-9" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="fisiere.desktop"/>
      </property>
    </property>
    <property name="plugin-10" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="browser.desktop"/>
      </property>
    </property>
    <property name="plugin-2" type="string" value="tasklist">
      <property name="show-labels" type="bool" value="false"/>
      <property name="flat-buttons" type="bool" value="true"/>
      <property name="show-handle" type="bool" value="false"/>
      <property name="include-all-workspaces" type="bool" value="true"/>
    </property>
    <property name="plugin-3" type="string" value="separator">
      <property name="expand" type="bool" value="true"/>
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-4" type="string" value="systray">
      <property name="square-icons" type="bool" value="true"/>
    </property>
    <property name="plugin-5" type="string" value="pulseaudio">
      <property name="enable-keyboard-shortcuts" type="bool" value="true"/>
    </property>
    <property name="plugin-6" type="string" value="xkb">
      <property name="display-type" type="uint" value="2"/>
      <property name="group-policy" type="uint" value="0"/>
    </property>
    <property name="plugin-7" type="string" value="clock">
      <property name="mode" type="uint" value="2"/>
      <property name="digital-layout" type="uint" value="1"/>
      <property name="digital-time-format" type="string" value="%H:%M"/>
      <property name="digital-date-format" type="string" value="%d.%m.%Y"/>
      <property name="tooltip-format" type="string" value="%A, %d %B %Y"/>
    </property>
    <property name="plugin-8" type="string" value="showdesktop"/>
  </property>
</channel>
EOF
    copiaza_lansator "$THUNAR"  "$S/.config/xfce4/panel/launcher-9/fisiere.desktop"  || avert "Lipsește $THUNAR"
    copiaza_lansator "$FIREFOX" "$S/.config/xfce4/panel/launcher-10/browser.desktop" || avert "Lipsește $FIREFOX"

    # --- Meniul Start --------------------------------------------------------
    scrie "$S/.config/xfce4/panel/whiskermenu-1.rc" <<EOF
favorites=$WORD,$EXCEL,$PPT,$PAINT,$CANGUR,$FURNICA,$THONNY,$VSCODE,$FIREFOX,${CHROMIUM_L:+$CHROMIUM_L,}$THUNAR
button-icon=start-here
button-single-row=false
show-button-title=false
show-button-icon=true
launcher-show-name=true
launcher-show-description=false
position-search-alternate=true
position-commands-alternate=true
show-command-lockscreen=false
show-command-switchuser=false
position-categories-alternate=false
menu-width=520
menu-height=560
EOF

    # --- Temă, ferestre, sesiune ---------------------------------------------
    scrie "$X/xsettings.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="$TEMA_GTK"/>
    <property name="IconThemeName" type="string" value="$TEMA_ICONITE"/>
  </property>
</channel>
EOF
    scrie "$X/xfwm4.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="$TEMA_FERESTRE"/>
    <property name="title_alignment" type="string" value="left"/>
    <property name="button_layout" type="string" value="O|HMC"/>
    <property name="use_compositing" type="bool" value="false"/>
    <property name="workspace_count" type="int" value="1"/>
  </property>
</channel>
EOF
    scrie "$X/xfce4-desktop.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="desktop-icons" type="empty">
    <property name="icon-size" type="uint" value="48"/>
    <property name="file-icons" type="empty">
      <property name="show-home" type="bool" value="true"/>
      <property name="show-filesystem" type="bool" value="false"/>
      <property name="show-trash" type="bool" value="true"/>
      <property name="show-removable" type="bool" value="true"/>
    </property>
  </property>
</channel>
EOF
    scrie "$X/xfce4-session.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-session" version="1.0">
  <property name="general" type="empty">
    <property name="SaveOnExit" type="bool" value="false"/>
    <property name="LockCommand" type="string" value="true"/>
  </property>
  <property name="shutdown" type="empty">
    <property name="LockScreen" type="bool" value="false"/>
  </property>
</channel>
EOF
    scrie "$X/xfce4-screensaver.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-screensaver" version="1.0">
  <property name="saver" type="empty">
    <property name="enabled" type="bool" value="false"/>
  </property>
  <property name="lock" type="empty">
    <property name="enabled" type="bool" value="false"/>
  </property>
</channel>
EOF
    scrie "$X/xfce4-power-manager.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-power-manager" version="1.0">
  <property name="xfce4-power-manager" type="empty">
    <property name="lock-screen-suspend-hibernate" type="bool" value="false"/>
    <property name="power-button-action" type="uint" value="4"/>
  </property>
</channel>
EOF

    # --- Dosare cu nume ca în Windows ----------------------------------------
    scrie "$S/.config/user-dirs.dirs" <<'EOF'
XDG_DESKTOP_DIR="$HOME/Desktop"
XDG_DOWNLOAD_DIR="$HOME/Downloads"
XDG_TEMPLATES_DIR="$HOME/Templates"
XDG_PUBLICSHARE_DIR="$HOME/Public"
XDG_DOCUMENTS_DIR="$HOME/Documents"
XDG_MUSIC_DIR="$HOME/Music"
XDG_PICTURES_DIR="$HOME/Pictures"
XDG_VIDEOS_DIR="$HOME/Videos"
EOF
    echo "en_US" > "$S/.config/user-dirs.locale"
    local d
    for d in Desktop Downloads Templates Public Documents Music Pictures Videos; do
        install -d "$S/$d"
    done

    # --- Scurtături pe Desktop -----------------------------------------------
    local app
    for app in "$WORD" "$EXCEL" "$PPT" "$PAINT" "$CANGUR" "$FURNICA" "$THONNY" "$VSCODE" "$FIREFOX" $CHROMIUM_L; do
        copiaza_lansator "$app" "$S/Desktop/$app" || avert "Lipsește $app"
    done
    if [ -n "$LUCRARI_DIR" ]; then
        ln -sfn "$LUCRARI_DIR" "$S/Desktop/Lucrări (nu se șterg)"
    fi

    # --- Visual Studio Code: fără telemetrie, fără pagina de bun-venit, fără keyring --------
    local vsc
    for vsc in .config; do
        scrie "$S/$vsc/Code/User/settings.json" <<'EOF'
{
    "telemetry.telemetryLevel": "off",
    "update.mode": "none",
    "workbench.startupEditor": "none",
    "workbench.tips.enabled": false,
    "extensions.ignoreRecommendations": true,
    "editor.fontSize": 16
}
EOF
    done
    # Fără întrebarea despre „keyring" (nu există pe toate desktopurile).
    printf '{\n    "password-store": "basic"\n}\n' | scrie "$S/.vscode/argv.json"

    # --- LibreOffice (de rezervă): interfață cu file (ca Office) și salvare în .docx/.xlsx/.pptx
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

    # --- Programe care pornesc singure: fără ecran de bun-venit, fără actualizări,
    #     fără blocarea ecranului cu parolă (elevul e în contul comun).
    install -d "$S/.config/autostart"
    local f
    for f in /etc/xdg/autostart/mint*.desktop /etc/xdg/autostart/light-locker.desktop \
             /etc/xdg/autostart/xfce4-screensaver.desktop; do
        [ -f "$f" ] || continue
        printf '[Desktop Entry]\nType=Application\nName=%s\nHidden=true\n' \
            "$(basename "$f" .desktop)" > "$S/.config/autostart/$(basename "$f")"
    done
    scrie "$S/.config/autostart/sala-la-pornire.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Pregătire desktop elev
Exec=/usr/local/bin/sala-la-pornire
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

    # Înlocuim șablonul vechi; păstrăm o copie a lui.
    if [ -d "$SABLON" ]; then
        rm -rf "$DATE_DIR/sablon.anterior"
        mv "$SABLON" "$DATE_DIR/sablon.anterior"
        avert "Șablonul vechi e păstrat în $DATE_DIR/sablon.anterior"
    fi
    mv "$S" "$SABLON"
    ok "Profil: bară jos, meniu Start, temă $TEMA_GTK / $TEMA_ICONITE, scurtături pe Desktop"
}

# =============================================================================
instaleaza_scripturi() {
    pas "Instalez comenzile de administrare"

    # Rulat la fiecare logare a elevului (ca elev): marchează scurtăturile de pe
    # Desktop ca sigure (altfel XFCE întreabă la fiecare clic) și pune fundalul.
    cat > /usr/local/bin/sala-la-pornire <<EOF
#!/bin/bash
# Instalat de configurare-sala.sh
FUNDAL="$FUNDAL"
EOF
    cat >> /usr/local/bin/sala-la-pornire <<'EOF'
sleep 2
# Ecranul nu se blochează niciodată în contul elev (setările rămân în cont la resetare,
# deci le refacem la fiecare logare). xflock4 (Super+L, Ctrl+Alt+L) rulează LockCommand.
pkill -u "$USER" -x light-locker 2>/dev/null
pkill -u "$USER" -x xfce4-screensaver 2>/dev/null
xfconf-query -c xfce4-session -p /general/LockCommand -n -t string -s true
xfconf-query -c xfce4-session -p /shutdown/LockScreen -n -t bool -s false
xfconf-query -c xfce4-screensaver -p /lock/enabled -n -t bool -s false
xfconf-query -c xfce4-screensaver -p /saver/enabled -n -t bool -s false
xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/lock-screen-suspend-hibernate -n -t bool -s false
DESKTOP_DIR="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")"
for f in "$DESKTOP_DIR"/*.desktop; do
    [ -f "$f" ] || continue
    chmod +x "$f"
    gio set -t string "$f" metadata::xfce-exe-checksum "$(sha256sum "$f" | cut -d' ' -f1)" 2>/dev/null
    gio set -t string "$f" metadata::trusted true 2>/dev/null
done
if [ -f "$FUNDAL" ] && [ ! -e "$HOME/.config/sala-fundal-propriu" ]; then
    for m in $(xrandr --listmonitors 2>/dev/null | awk 'NR>1 {print $NF}'); do
        baza="/backdrop/screen0/monitor$m/workspace0"
        xfconf-query -c xfce4-desktop -p "$baza/last-image" -n -t string -s "$FUNDAL"
        xfconf-query -c xfce4-desktop -p "$baza/image-style" -n -t int -s 5
    done
fi
xfdesktop --reload >/dev/null 2>&1 || true
EOF
    chmod 755 /usr/local/bin/sala-la-pornire

    # Comanda pentru profesor.
    cat > /usr/local/sbin/cont-elev <<EOF
#!/bin/bash
# Instalat de configurare-sala.sh — administrarea contului comun al elevilor.
ELEV="$ELEV_USER"
DATE_DIR="$DATE_DIR"
RESETARE="$RESETARE"   # dosarele care se refac la resetare ("tot" = tot contul)
EOF
    cat >> /usr/local/sbin/cont-elev <<'EOF'
set -euo pipefail
SABLON="$DATE_DIR/sablon"
PAUZA="$DATE_DIR/pauza"
ACASA="$(getent passwd "$ELEV" | cut -d: -f6)"
[ -n "$ACASA" ] && [ "$ACASA" != "/" ] || { echo "Nu găsesc contul $ELEV."; exit 1; }

este_logat() { who | awk '{print $1}' | grep -x "$ELEV" >/dev/null; }

# $1 = „tot": tot contul revine la șablon (setări, bară, Firefox…). Altfel se refac doar
# dosarele din RESETARE (ca în șablon); restul contului rămâne cum l-a lăsat elevul.
reseteaza() {
    [ -d "$SABLON" ] || { echo "Lipsește șablonul $SABLON"; exit 1; }
    pkill -KILL -u "$ELEV" 2>/dev/null || true
    sleep 1
    if [ "${1:-}" = "tot" ] || [ "$RESETARE" = "tot" ]; then
        rsync -a --delete "$SABLON"/ "$ACASA"/
    else
        local d
        for d in $RESETARE; do
            case "$d" in ""|/*|*..*) continue ;; esac
            if [ -d "$SABLON/$d" ]; then
                install -d "$ACASA/$d"
                rsync -a --delete "$SABLON/$d"/ "$ACASA/$d"/
            else
                rm -rf "${ACASA:?}/$d"
            fi
        done
    fi
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
  sudo cont-elev reseteaza    resetează chiar acum dosarele: $RESETARE
  sudo cont-elev reseteaza-tot  tot contul revine la șablon (și setările, bara, Firefox)
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
    auto)   # chemat la pornirea calculatorului și când elevul iese din sesiune
        [ -e "$PAUZA" ] && exit 0
        reseteaza ;;
    reseteaza|reset)
        if este_logat; then echo "Elevul este încă logat. Mai întâi ieși din sesiunea lui."; exit 1; fi
        reseteaza; echo "Contul $ELEV a fost resetat ($RESETARE)." ;;
    reseteaza-tot)
        if este_logat; then echo "Elevul este încă logat. Mai întâi ieși din sesiunea lui."; exit 1; fi
        reseteaza tot; echo "Tot contul $ELEV a revenit la șablon." ;;
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
            --exclude='.mozilla/firefox/*/cache2/' \
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
        echo "Am revenit la șablonul anterior. Ca să-l aplici acum: sudo cont-elev reseteaza-tot" ;;
    stare)
        if [ -e "$PAUZA" ]; then echo "Resetare automată: OPRITĂ (pauză)"; else echo "Resetare automată: PORNITĂ"; fi
        if este_logat; then echo "Elevul este logat acum."; fi ;;
    *) ajutor ;;
esac
EOF
    chmod 755 /usr/local/sbin/cont-elev

    # LightDM: resetare când elevul iese din sesiune.
    cat > /usr/local/sbin/cont-elev-la-iesire <<EOF
#!/bin/sh
# Instalat de configurare-sala.sh — rulat de LightDM (ca root) la închiderea unei sesiuni.
if [ "\${USER:-}" = "$ELEV_USER" ]; then
    /usr/local/sbin/cont-elev auto >/dev/null 2>&1 || true
fi
exit 0
EOF
    chmod 755 /usr/local/sbin/cont-elev-la-iesire

    # systemd: resetare la pornirea calculatorului (și după o oprire din buton).
    cat > /etc/systemd/system/cont-elev-reset.service <<'EOF'
[Unit]
Description=Resetează contul elevului la starea din șablon
After=local-fs.target
Before=display-manager.service lightdm.service

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
        avert "systemd nu rulează; resetarea la pornire se activează la prima pornire"
        ln -sf /etc/systemd/system/cont-elev-reset.service \
            /etc/systemd/system/multi-user.target.wants/cont-elev-reset.service 2>/dev/null || true
    fi
    ok "Comanda pentru profesor: sudo cont-elev"
}

# =============================================================================
creeaza_cont_elev() {
    pas "Contul „$ELEV_USER\""
    if ! id "$ELEV_USER" >/dev/null 2>&1; then
        useradd -m -s /bin/bash -c "$ELEV_NUME" "$ELEV_USER"
        ok "Cont creat"
    else
        ok "Contul există deja"
    fi
    echo "$ELEV_USER:$ELEV_PAROLA" | chpasswd
    # Elevul nu are drepturi de administrator.
    local g
    for g in sudo adm lpadmin sambashare; do
        if id -nG "$ELEV_USER" | tr ' ' '\n' | grep -x "$g" >/dev/null; then gpasswd -d "$ELEV_USER" "$g" >/dev/null; fi
    done
    ok "Fără drepturi de administrator, parola: $ELEV_PAROLA"

    # Sesiunea la logare (LightDM o citește de aici); limba rămâne cea a sistemului.
    install -d /var/lib/AccountsService/users
    cat > "/var/lib/AccountsService/users/$ELEV_USER" <<EOF
[User]
XSession=xfce
SystemAccount=false
EOF

    if [ -n "$LUCRARI_DIR" ]; then
        install -d -o "$ELEV_USER" -g "$ELEV_USER" -m 2775 "$LUCRARI_DIR"
        ok "Dosarul $LUCRARI_DIR nu se șterge (pe Desktop: „Lucrări (nu se șterg)\")"
    fi

    # LightDM: resetare la ieșire + intrare automată.
    install -d /etc/lightdm/lightdm.conf.d
    {
        echo "# Configurat de configurare-sala.sh"
        echo "[Seat:*]"
        echo "session-cleanup-script=/usr/local/sbin/cont-elev-la-iesire"
        if [ "$AUTOLOGIN" = "1" ]; then
            echo "autologin-user=$ELEV_USER"
            echo "autologin-user-timeout=0"
            echo "autologin-session=xfce"
        fi
    } > /etc/lightdm/lightdm.conf.d/90-sala.conf
    if [ "$AUTOLOGIN" = "1" ]; then
        getent group autologin >/dev/null || groupadd -r autologin
        gpasswd -a "$ELEV_USER" autologin >/dev/null
        ok "La pornire intră automat în contul elev"
    fi

    # Prima resetare: contul primește profilul nou.
    if who | awk '{print $1}' | grep -x "$ELEV_USER" >/dev/null; then
        avert "Elevul este logat acum; profilul nou se aplică după ce iese din sesiune / la repornire"
    else
        /usr/local/sbin/cont-elev reseteaza-tot >/dev/null
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

EOF
}

main() {
    touch "$LOG"; chmod 600 "$LOG"
    exec > >(tee -a "$LOG") 2>&1
    echo "===== configurare-sala.sh — $(date '+%Y-%m-%d %H:%M') ====="
    verificari
    instaleaza_pachete
    instaleaza_din_github
    instaleaza_libreoffice
    instaleaza_programare
    instaleaza_chromium
    optimizeaza_memoria
    seteaza_tastatura
    instaleaza_tema
    instaleaza_scripturi
    construieste_sablon
    creeaza_cont_elev
    rezumat
}

main "$@"
