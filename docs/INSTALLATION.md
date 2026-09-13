# TrainAlarm von Linux aufs iPhone 15 bringen

Diese Anleitung beschreibt den kompletten Weg von einem Linux-Rechner ohne Mac
bis zur laufenden App auf dem iPhone.

> **Hinweis zu Versionen:** SideStore und AltServer entwickeln sich schnell
> weiter, besonders beim Einrichtungsablauf (Pairing, VPN-Komponente). Die
> Schritte hier beschreiben das Prinzip und den Stand zum Zeitpunkt der
> Erstellung. Wenn etwas abweicht, ist die jeweils aktuelle Anleitung auf
> <https://sidestore.io/#get-started> massgeblich -- die Reihenfolge
> (Pairing -> SideStore -> IPA) bleibt aber dieselbe.

---

## Was du brauchst

- iPhone 15 mit iOS 17 oder neuer
- USB-C-Kabel
- Eine **Apple-ID** (ein kostenloser Account genuegt)
- Linux mit `libimobiledevice` und laufendem `usbmuxd`
- Die Datei `TrainAlarm.ipa` aus dem GitHub-Actions-Build

---

## Schritt 1 -- Die IPA herunterladen

1. Im Repository auf **Actions** klicken.
2. Den obersten erfolgreichen Lauf von **Build IPA** oeffnen.
3. Unter **Artifacts** `TrainAlarm-unsigned-ipa` herunterladen.
4. Entpacken -- darin liegt `TrainAlarm.ipa`.

```bash
cd ~/Downloads
unzip TrainAlarm-unsigned-ipa.zip
ls -lh TrainAlarm.ipa
```

Alternativ per Kommandozeile, falls die GitHub-CLI installiert ist:

```bash
gh run download --repo Bennetleicht/headphone_alarmclock --name TrainAlarm-unsigned-ipa
```

Hast du das Repository getaggt (`git tag v1.0.0 && git push --tags`), haengt
der Workflow die `.ipa` zusaetzlich an ein GitHub-Release. Deren Download-URL
kannst du spaeter direkt in SideStore einfuegen -- das erspart den Umweg ueber
den Dateimanager.

---

## Schritt 2 -- Linux vorbereiten

```bash
# Debian / Ubuntu
sudo apt update
sudo apt install libimobiledevice-utils libimobiledevice6 usbmuxd ideviceinstaller

# Fedora
sudo dnf install libimobiledevice-utils usbmuxd

# Arch
sudo pacman -S libimobiledevice usbmuxd
```

iPhone per USB-C anschliessen, am iPhone **"Diesem Computer vertrauen"**
bestaetigen, dann testen:

```bash
idevice_id -l          # zeigt die UDID -> Verbindung steht
ideviceinfo -k ProductVersion
```

Kommt nichts zurueck:

```bash
sudo systemctl restart usbmuxd
```

### Entwicklermodus aktivieren

Ab iOS 16 verlangt Apple das fuer selbst installierte Apps:

**Einstellungen -> Datenschutz & Sicherheit -> Entwicklermodus -> ein**
-> iPhone startet neu -> nach dem Neustart bestaetigen.

Taucht der Menuepunkt nicht auf, muss das iPhone einmal mit einem
Entwickler-Werkzeug verbunden gewesen sein -- ein `ideviceinfo` wie oben reicht
in der Regel aus.

---

## Schritt 3 -- Pairing-Datei erzeugen

SideStore braucht eine Pairing-Datei, um das iPhone ohne Computer bedienen zu
koennen.

```bash
# Werkzeug holen (Teil des Jitterbug-Projekts).
# Das Release-Asset ist ein ZIP, kein tar.gz, und heisst ohne Architektur-Suffix.
wget https://github.com/osy/Jitterbug/releases/latest/download/jitterbugpair-linux.zip
unzip jitterbugpair-linux.zip
chmod +x jitterbugpair

# iPhone muss angeschlossen und entsperrt sein
./jitterbugpair
```

Der Binaerbau stammt von Ubuntu 20.04 und ist dynamisch gegen
`libimobiledevice` gelinkt. Beschwert er sich ueber eine fehlende
`libimobiledevice-1.0.so.*`, gibt es zwei Auswege:

```bash
# a) selbst bauen
sudo apt install meson ninja-build libgcrypt-dev libusbmuxd-dev \
     libimobiledevice-dev libunistring-dev
git clone --recursive https://github.com/osy/Jitterbug
cd Jitterbug && meson --buildtype=release build && cd build && ninja

# b) den Pairing-Datensatz nehmen, den libimobiledevice ohnehin anlegt
idevicepair pair
sudo cp /var/lib/lockdown/<UDID>.plist ./<UDID>.mobiledevicepairing
sudo chown $USER ./<UDID>.mobiledevicepairing
```

Heraus kommt eine Datei wie `00008120-000X1XXX0XXX401E.mobiledevicepairing`.
**Gut aufheben** -- sie wird gleich gebraucht.

> Manche SideStore-Versionen erwarten die Datei mit der Endung `.plist`. Dann
> einfach umbenennen; der Inhalt ist identisch.

---

## Schritt 4 -- SideStore aufs iPhone bringen

Hier liegt das Henne-Ei-Problem: SideStore ist selbst eine `.ipa` und muss
einmalig von aussen installiert werden. Unter Linux erledigt das
**AltServer-Linux**.

```bash
# Neueste Version fuer die eigene Architektur holen
wget https://github.com/NyaMisty/AltServer-Linux/releases/latest/download/AltServer-x86_64
chmod +x AltServer-x86_64

# SideStore selbst herunterladen
wget https://github.com/SideStore/SideStore/releases/latest/download/SideStore.ipa
```

`anisette-server` bereitstellen (AltServer braucht ihn fuer die
Apple-Anmeldung) und SideStore installieren:

```bash
# Variante mit Docker -- am wenigsten Gefrickel
docker run -d --restart always --name anisette -p 6969:6969 \
  dadoum/anisette-server:latest

# iPhone anschliessen, dann:
ALTSERVER_ANISETTE_SERVER=http://localhost:6969 \
  ./AltServer-x86_64 -u <DEINE-UDID> \
  -a deine@apple-id.de \
  -p 'dein-app-spezifisches-passwort' \
  SideStore.ipa
```

Ein paar Hinweise dazu:

- `<DEINE-UDID>` liefert `idevice_id -l`.
- Hat deine Apple-ID Zwei-Faktor-Authentifizierung (Standard), brauchst du ein
  **app-spezifisches Passwort** von <https://account.apple.com> ->
  Anmeldung & Sicherheit -> App-spezifische Passwoerter.
- Der Vorgang dauert ein bis zwei Minuten. Am Ende taucht SideStore auf dem
  Homescreen auf.

**Entwickler vertrauen:** Einstellungen -> Allgemein -> VPN & Geraeteverwaltung
-> deine Apple-ID -> **Vertrauen**.

---

## Schritt 5 -- SideStore einrichten

1. SideStore oeffnen.
2. Pairing-Datei aus Schritt 3 aufs iPhone bringen -- am einfachsten per
   AirDrop-Ersatz: in eine Cloud legen, per Mail an dich selbst schicken oder
   ueber `ifuse` in die Dateien-App kopieren. In der Dateien-App antippen und
   **"In SideStore oeffnen"** waehlen.
3. SideStore fragt nach der Apple-ID -- dieselbe wie in Schritt 4.
4. SideStore richtet eine lokale VPN-Komponente ein (je nach Version WireGuard
   oder StosVPN). Die Verbindung erlauben; sie geht nicht ins Internet, sondern
   spricht nur mit dem iPhone selbst.

---

## Schritt 6 -- TrainAlarm installieren

1. `TrainAlarm.ipa` aufs iPhone bringen (Cloud, Mail, `ifuse`).
2. In der Dateien-App antippen -> **Teilen** -> **SideStore**.
3. In SideStore auf **Install** tippen.

Oder direkt aus dem GitHub-Release: in SideStore auf **+** -> **Install from
URL** -> die Download-URL der `.ipa` einfuegen.

Nach etwa 30 Sekunden liegt TrainAlarm auf dem Homescreen.

---

## Schritt 7 -- Erster Start

1. **TrainAlarm oeffnen.** Mitteilungen erlauben, wenn gefragt.
2. **Kopfhoerer verbinden.** Die Statuskarte muss gruen werden und den Namen
   anzeigen, z. B. "AirPods Pro".
3. **Testton abspielen.** Er muss ausschliesslich in den Kopfhoerern zu hoeren
   sein.
4. **Den Failsafe pruefen** -- das ist der wichtigste Test:
   waehrend der Testton laeuft, die AirPods ins Etui legen bzw. das Kabel
   ziehen. Der Ton muss **sofort** aufhoeren und **nicht** auf den Lautsprecher
   wechseln.
5. **Schnell-Timer ausprobieren:** "+5 Min" antippen, iPhone sperren, warten.

### Empfohlene Systemeinstellungen

- **Systemlautstaerke** bei verbundenen Kopfhoerern hochdrehen. Die App kann sie
  nicht setzen, warnt aber unter 25 %.
- **Kein Energiesparmodus** -- er verkuerzt die Hintergrundzeit.
- **Einstellungen -> Allgemein -> Hintergrundaktualisierung** fuer TrainAlarm
  einschalten.
- iOS 17+ hat unter **Einstellungen -> Bluetooth -> AirPods ->
  "Automatische Ohrerkennung"** eine Falle: Liegen die AirPods im Etui, trennt
  sich die Route. Genau dafuer gibt es den Wartezustand in der App.

---

## Die 7-Tage-Grenze

Mit einem kostenlosen Apple-Account laufen sideloadete Apps nach **sieben
Tagen** ab. Danach startet TrainAlarm nicht mehr, bis SideStore die App
erneuert.

- SideStore kann im Hintergrund automatisch erneuern, solange iPhone und
  SideStore-VPN aktiv sind. In SideStore unter **Settings ->
  Background Refresh** einschalten.
- Manuell: SideStore oeffnen -> **My Apps** -> **Refresh All**.
- Mit einem kostenpflichtigen Entwicklerkonto (99 USD/Jahr) sind es 365 Tage.

**Vor einer laengeren Zugfahrt lohnt ein kurzer Blick:** App einmal oeffnen und
den Testton abspielen. Faellt die App genau in der Nacht davor aus, weckt sie
auch nicht.

Weitere Grenzen des kostenlosen Accounts: maximal **drei** sideloadete Apps
gleichzeitig und zehn neue App-IDs pro Woche.

---

## Alternative: AltServer unter Windows oder macOS

Wer neben dem Linux-Rechner noch einen Windows- oder Mac-Rechner hat, kommt
schneller ans Ziel:

1. AltServer von <https://altstore.io> installieren (Windows braucht zusaetzlich
   iTunes und iCloud aus dem Apple-Download, **nicht** aus dem Microsoft Store).
2. iPhone per Kabel anschliessen.
3. AltServer-Symbol -> **Install AltStore** -> dein iPhone -> Apple-ID eingeben.
4. Auf dem iPhone: Einstellungen -> Allgemein -> VPN & Geraeteverwaltung ->
   Entwickler vertrauen.
5. `TrainAlarm.ipa` aufs iPhone kopieren, in AltStore ueber **+** installieren.

Fuer den Betrieb im Zug ist danach kein Computer mehr noetig; nur zum Erneuern
muss das iPhone gelegentlich mit AltServer im selben WLAN sein.

---

## Fehlerbehebung

| Symptom | Ursache | Loesung |
|---|---|---|
| `idevice_id -l` zeigt nichts | usbmuxd laeuft nicht, oder Vertrauen fehlt | `sudo systemctl restart usbmuxd`, Kabel neu einstecken, am iPhone "Vertrauen" bestaetigen |
| AltServer: "Could not connect to device" | falsche UDID oder iPhone gesperrt | iPhone entsperren, UDID mit `idevice_id -l` pruefen |
| AltServer: Anmeldung schlaegt fehl | Zwei-Faktor-Authentifizierung | app-spezifisches Passwort verwenden |
| AltServer: Anisette-Fehler | Anisette-Server nicht erreichbar | Container laeuft? `docker ps`, Port 6969 frei? |
| App startet nicht, "Nicht vertrauenswuerdiger Entwickler" | Profil nicht bestaetigt | Einstellungen -> Allgemein -> VPN & Geraeteverwaltung -> Vertrauen |
| App startet, stuerzt sofort ab | Entwicklermodus aus | Einstellungen -> Datenschutz & Sicherheit -> Entwicklermodus |
| SideStore: "Maximum App Limit Reached" | drei Apps beim kostenlosen Account | eine andere sideloadete App entfernen |
| Statuskarte bleibt rot, obwohl AirPods verbunden sind | AirPods sind mit einem anderen Geraet gekoppelt | im Kontrollzentrum die Ausgabe aufs iPhone umstellen |
| USB-C-Headset wird nicht erkannt | USB-Audio in der App deaktiviert | Einstellungen in der App -> "USB-C-Headsets zulassen" |
| Wecker klingelt nicht, Mitteilung "Wecker kann nicht klingeln" | Route war zur Weckzeit nicht privat | Kopfhoerer verbinden -- es klingelt sofort; Wartefenster in den Einstellungen verlaengern |

### Logs ansehen

Bei Problemen zeigt die App ausfuehrlich, was sie entscheidet:

```bash
idevicesyslog | grep -i trainalarm
```

Dort tauchen Zeilen wie `FAILSAFE: Route nicht mehr privat` oder
`Klingeln verweigert: keine private Ausgabe-Route` auf.
