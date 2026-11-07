# Linux pentru sala de informatică

Scripturi care transformă un calculator slab (2 GB RAM, HDD, 64 de biți) într-un
calculator de clasă: **Linux cu aspect de Windows 10**, optimizat pentru memorie
puțină, în limba română, cu un cont comun **„elev"** care revine singur la starea
inițială.

Sunt trei variante, câte una pentru fiecare sistem:

| Script | Sistem | Când |
|---|---|---|
| `configurare-sala.sh` | Linux Mint XFCE 22/23 | implicit: arată cel mai aproape de Windows 10, ușor de întreținut |
| `configurare-antix.sh` | antiX 26.x full, 64 biți | dacă Mint e prea lent: consumă ~400 MB RAM mai puțin |
| `configurare-q4os.sh` | Q4OS 6.x Trinity, 64 biți | intermediar: mai ușor decât Mint, mai aproape de Windows decât antiX |

Mai jos e descrisă varianta Mint; diferențele sunt la [Varianta antiX](#varianta-antix)
și [Varianta Q4OS](#varianta-q4os).

## Ce face scriptul

| | |
|---|---|
| **Aspect Windows 10** | bara jos, meniu Start, ceas și dată în dreapta, „Arată desktopul" în colț, temă și iconițe Windows 10, fundal albastru, un singur spațiu de lucru |
| **Programe** | LibreOffice Writer / Calc / Impress (în loc de Word / Excel / PowerPoint), KolourPaint (în loc de Paint), Firefox |
| **Ca în Office** | LibreOffice cu interfață cu file (ca panglica din Office); salvează implicit în **.docx, .xlsx, .pptx**, fără întrebări |
| **2 GB RAM + HDD** | zram (memorie comprimată), earlyoom (închide o filă de browser în loc să blocheze calculatorul; nu închide niciodată LibreOffice), BFQ pentru HDD, fără efecte grafice, Firefox cu uBlock Origin și mai puține procese |
| **Română** | limba sistemului și a programelor, tastatură US + Română (standard), comutare cu **Alt+Shift** |
| **Contul „elev"** | fără drepturi de administrator, fără blocare de ecran, fără ferestre de bun-venit și actualizări; intră automat la pornire |
| **Resetare** | tot ce schimbă elevii se șterge la ieșirea din sesiune și la repornire. Excepție: dosarul **„Lucrări (nu se șterg)"** de pe Desktop (`/srv/lucrari`) |

## Pași

### 1. Instalează Linux Mint XFCE

1. Descarcă **Linux Mint XFCE** (64 de biți) de pe <https://linuxmint.com/download.php>.
2. Scrie-l pe un stick cu [Rufus](https://rufus.ie) sau [balenaEtcher](https://etcher.balena.io).
3. Instalează pe primul calculator. La instalare:
   - limba: **Română**;
   - creează contul **profesorului** (cu parolă pe care elevii nu o știu) — acesta e
     contul de administrator;
   - bifează instalarea codecurilor multimedia.

### 2. Rulează scriptul

Copiază `configurare-sala.sh` pe calculator (de pe stick sau descarcă-l), deschide
**Terminalul** în dosarul cu scriptul și scrie:

```bash
sudo bash configurare-sala.sh
```

Durează 10–30 de minute (HDD-ul e lent). La final: `sudo reboot`.

Setările se pot schimba la începutul scriptului sau la rulare, de exemplu:

```bash
sudo ELEV_PAROLA=1234 AUTOLOGIN=0 TASTATURI=us,ro,ru VARIANTE=,std, bash configurare-sala.sh
```

| Setare | Implicit | Ce înseamnă |
|---|---|---|
| `ELEV_USER` / `ELEV_PAROLA` | `elev` / `elev` | contul elevilor |
| `AUTOLOGIN` | `1` | la pornire intră direct în contul elev |
| `LUCRARI_DIR` | `/srv/lucrari` | dosarul care nu se șterge (`""` = fără) |
| `TASTATURI` / `VARIANTE` | `us,ro` / `,std` | aranjamentele tastaturii |
| `TEMA_WIN10` | `1` | descarcă tema Windows 10 (altfel rămâne tema Mint, albastră) |
| `ACTUALIZARE` | `1` | instalează și actualizările sistemului |

### 3. Verifică pe primul calculator

Pornește, intră ca elev și verifică: meniul Start, programele de pe Desktop, Word →
salvează un fișier (trebuie să propună `.docx`), tastatura (Alt+Shift), sunetul,
internetul. Ieși din sesiune și intră din nou — schimbările trebuie să fi dispărut.

### 4. Ajustează ce văd elevii (dacă vrei)

```bash
sudo cont-elev pauza        # oprește resetarea
# ieși, intră ca elev, schimbă ce vrei (iconițe, fundal, panou), ieși
sudo cont-elev salveaza     # salvează contul elevului ca nou șablon
```

Alte comenzi: `sudo cont-elev stare`, `sudo cont-elev reseteaza`,
`sudo cont-elev anuleaza` (revine la șablonul anterior), `sudo cont-elev ajutor`.

### 5. Copiază pe celelalte calculatoare

Ca să nu repeți instalarea de 15 ori, clonează discul cu
[Clonezilla](https://clonezilla.org) (device-image pe un HDD extern, apoi
restore pe fiecare calculator). Discurile țintă trebuie să fie **la fel de mari sau mai
mari**.

**Înainte de clonare**, pe calculatorul-model:

```bash
sudo truncate -s 0 /etc/machine-id     # fiecare copie își generează propriul ID
sudo apt clean                          # imaginea iese mai mică
```

**După clonare**, pe fiecare calculator, dă-i un nume propriu:

```bash
sudo hostnamectl set-hostname pc-07
```

Alternativ, poți instala Mint pe fiecare calculator și rula scriptul pe fiecare.

## Bine de știut

- **SSD.** Cea mai mare încetinire vine de la HDD. Un SSD de 120 GB face calculatorul
  de câteva ori mai rapid; 2 GB RAM în plus (DDR3 second-hand) ajută și ele mult.
- **Browserul** consumă cea mai multă memorie: 2–3 file deschise deodată sunt maximum
  pe 2 GB.
- **Actualizările** le face profesorul, din contul lui (Manager de actualizări), de
  exemplu o dată pe lună. Pe calculatoarele clonate, din fiecare calculator.
- **Interfața cu file în LibreOffice** se setează automat; dacă într-o versiune nouă nu
  apare, alege *Vizualizare → Interfață utilizator → Cu file* în contul elevului și
  salvează șablonul (pasul 4).
- **Jurnalul** instalării: `/var/log/configurare-sala.log`.

## Ce se instalează unde

| Fișier | Rol |
|---|---|
| `/var/lib/cont-elev/sablon/` | profilul „curat" al elevului, copiat la fiecare resetare |
| `/usr/local/sbin/cont-elev` | comanda pentru profesor |
| `/usr/local/sbin/cont-elev-la-iesire` | resetarea la ieșirea din sesiune (LightDM) |
| `/etc/systemd/system/cont-elev-reset.service` | resetarea la pornire |
| `/usr/local/bin/sala-la-pornire` | la logarea elevului: scurtături sigure pe Desktop, fundal |
| `/etc/lightdm/lightdm.conf.d/90-sala.conf` | intrare automată, resetare la ieșire |
| `/etc/default/zramswap`, `/etc/sysctl.d/90-sala-zram.conf` | zram |
| `/etc/default/earlyoom` | earlyoom |
| `/etc/udev/rules.d/60-sala-hdd-bfq.rules` | BFQ pentru HDD |
| `/etc/firefox/policies/policies.json` | setările Firefox |
| `/usr/share/themes/Windows-10`, `/usr/share/icons/Windows-10` | tema [B00merang Windows 10](https://github.com/B00merang-Project/Windows-10) (GPL-3.0) |

## Varianta antiX

`configurare-antix.sh` face același lucru pe **antiX 26.x full, 64 de biți**, instalat pe
disc (nu de pe stick):

```bash
sudo bash configurare-antix.sh
```

Diferențe față de Mint:

| | Mint | antiX |
|---|---|---|
| Desktop | XFCE cu temă Windows 10 | IceWM cu tema **Scoala-Win10** generată de script (bară închisă jos, ferestre albe cu butoane _ □ ✕, meniu Start întunecat) + desktop zzzfm |
| Meniul Start | Whisker Menu | meniu simplu: Documente, Tabele, Prezentări, Desen, Internet, Fișiere, *Toate programele* |
| Paint | KolourPaint | **Drawing** (KolourPaint nu se poate instala pe antiX: are nevoie de systemd) |
| Browser | Firefox | Firefox ESR |
| Resetarea contului | LightDM + serviciu systemd | ecranul de logare **slimski** (`sessionstart_cmd` / `sessionstop_cmd`), la intrarea și la ieșirea elevului |
| zram, earlyoom | servicii systemd | pornite de slimski înainte de logare (`/usr/local/sbin/sala-servicii`), deci merg cu orice init: runit, sysvinit, dinit, s6 |

Comanda `sudo cont-elev …`, dosarul „Lucrări (nu se șterg)", LibreOffice cu file și
formatele .docx/.xlsx/.pptx, limba română și Alt+Shift sunt la fel.

Setările originale ale ecranului de logare sunt păstrate în
`/etc/slimski.local.conf.inainte-de-sala`. Profesorul intră în contul lui scriind numele
în ecranul de logare (după ieșirea din sesiunea elevului).

## Varianta Q4OS

`configurare-q4os.sh` face același lucru pe **Q4OS 6.x cu desktopul Trinity (TDE), 64 de
biți**, instalat pe disc:

```bash
sudo bash configurare-q4os.sh
```

Diferențe față de Mint:

| | Mint | Q4OS |
|---|---|---|
| Desktop | XFCE | Trinity: bară jos închisă la culoare (fundal generat), buton Start, programe fixate, ceas cu dată, „Arată desktopul" în dreapta; ferestre albe (Plastik) cu _ □ ✕ în dreapta |
| Meniul Start | Whisker Menu | Kickoff: căutare sus, la *Favorite* Documente, Tabele, Prezentări, Desen, Internet, Fișiere |
| Paint | KolourPaint | KolourPaint (versiunea Trinity) |
| Browser | Firefox | Firefox ESR |
| Asistentul Q4OS de la prima logare | — | dezactivat pentru elev |
| Resetarea contului | LightDM | ecranul de logare **TDM**: `/etc/trinity/tdm/Xstartup` și `Xreset` + serviciul systemd de la pornire |

Configurarea elevului (`~/.trinity/share/config/`) e scrisă de script: `kickerrc` (bara),
`ktaskbarrc`, `kdeglobals` (culori, iconițe, limbă), `twinrc` (ferestre), `kdesktoprc`
(fundal), `kxkbrc` (tastatură). Q4OS mută `XDG_CONFIG_HOME` în `~/.configtde`, de aceea
setările LibreOffice și GTK sunt puse și acolo.

Fișierele originale ale TDM sunt păstrate ca `/etc/trinity/tdm/*.inainte-de-sala`.
