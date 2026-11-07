# CLAUDE.md

Proiect: configurarea calculatoarelor slabe (2 GB RAM, HDD, 64 biți) din sala de
informatică a școlii: Linux Mint XFCE cu aspect de Windows 10, cont comun „elev" care se
resetează. Utilizatorul (profesor de informatică) scrie în română — răspunde în română.

- `configurare-sala.sh` — un singur script bash, autonom (se copiază pe stick); toate
  fișierele de configurare sunt generate din el prin heredoc. Ținta: Linux Mint 22.x/23.x XFCE.
- `configurare-antix.sh` — aceeași idee pentru antiX 26.x full x64 (IceWM + zzzfm, slimski, fără
  systemd). Tema IceWM `Scoala-Win10` e generată de un bloc Python din script (XPM). Resetarea și
  zram/earlyoom sunt legate de `sessionstart_cmd`/`sessionstop_cmd` din `/etc/slimski.local.conf`,
  ca să meargă cu orice init (runit implicit, sysvinit, dinit, s6). KolourPaint nu se instalează
  pe antiX (KF6 → polkit → libsystemd0), de aceea Paint = Drawing.
- `configurare-q4os.sh` — Q4OS 6.x Trinity (TDE) x64, systemd. Profilul TDE al elevului e scris
  din script (`kickerrc`, `ktaskbarrc`, `kdeglobals`, `twinrc`, `kdesktoprc`, `kxkbrc`); cheile se
  găsesc în `/opt/trinity/share/config.kcfg/*.kcfg`. Capcane: Q4OS pune `XDG_CONFIG_HOME=~/.configtde`;
  asistentul de prima logare se oprește cu `~/.local/share/q4os/.frstlogq4.stp` + `q4osrc first_login=false`;
  legăturile implicite de pe Desktop vin din `/opt/trinity/share/apps/kdesktop/Desktop` și se ascund cu
  copii `Hidden=true` în `~/.trinity/share/apps/kdesktop/Desktop`; bara de activități citește
  `ktaskbarrc` (global) și vrea `UseCustomColors=true`. Resetarea: hook-uri în TDM `Xstartup`/`Xreset`.
- `README.md` — instrucțiuni pentru profesor (instalare, `cont-elev`, clonare Clonezilla, antiX).

Testare: nu se poate rula pe macOS. Se testează în Docker cu imaginea `linuxmintd/mint22.3-amd64`
(`linuxmintd/mint23-amd64` e o imagine de dezvoltare stricată, repo „alfa"):

```bash
docker run -d --name sala22 -v "$PWD":/src:ro linuxmintd/mint22.3-amd64 sleep infinity
docker exec sala22 bash -c 'apt-get update && apt-get install -y xfce4-panel thunar lightdm locales sudo'
docker exec sala22 bash -c 'ACTUALIZARE=0 bash /src/configurare-sala.sh'
```

antiX: nu există imagine Docker. Rădăcina se scoate din ISO (`antiX/linuxfs`, squashfs) într-un
volum Docker `antixfs` (`bsdtar` + `unsquashfs` într-un container `debian:trixie`) și se testează cu
`chroot` din containerul `--privileged` (proc/dev/sys montate). Pentru capturi de ecran: Xvfb rulează
în containerul exterior, `/tmp/.X11-unix` e montat în chroot, IceWM/zzzfm pornesc ca `elev`, `scrot`.
(`docker import` al rădăcinii de 7 GB prin pipe e prea lent pe macOS.) ISO-urile utilizatorului:
`/Volumes/Ventoy/antiX-26.1_x64-full.iso`, `/Volumes/Ventoy/q4os-6.10-x64-tde.r2.iso` — nu descărca
alte ISO-uri. Q4OS: `live/filesystem.squashfs`; sesiunea TDE pornește în Xvfb cu
`su elev -c 'dbus-launch starttde'` (D-Bus de sistem pornit în chroot, șterge `/run/dbus/pid` vechi);
captura cu `xwd -root | convert`. Clicurile `xdotool` din containerul exterior NU ajung la kicker,
deci meniul Start nu se poate deschide în test.

Fără systemd/X în container: nu se verifică zram, earlyoom, LightDM și aspectul real al
panoului XFCE — acestea trebuie verificate pe un calculator real.

Capcană: scriptul rulează cu `set -o pipefail`; nu folosi `cmd | grep -q` (SIGPIPE face
condiția falsă) — folosește `grep ... >/dev/null` sau compară textul în bash.
