# TrainAlarm

Ein Wecker fuer Zug- und Nahverkehrsreisen, der **ausschliesslich ueber
Kopfhoerer** klingelt -- und niemals ueber den iPhone-Lautsprecher.

Native iOS-App in Swift/SwiftUI. Der gesamte Quellcode wird unter Linux
gepflegt; nur der Compiler-Lauf passiert auf einem kostenlosen macOS-Runner bei
GitHub Actions. Ergebnis ist eine unsignierte `.ipa`, die sich mit SideStore
oder AltServer direkt aufs iPhone bringen laesst.

---

## Inhalt

1. [Die Kernidee](#die-kernidee)
2. [Wie die Garantie technisch abgesichert ist](#wie-die-garantie-technisch-abgesichert-ist)
3. [Projektstruktur](#projektstruktur)
4. [Der Weckton](#der-weckton)
5. [Hintergrundbetrieb](#hintergrundbetrieb)
6. [Ehrliche Grenzen](#ehrliche-grenzen)
7. [Entwicklung unter Linux](#entwicklung-unter-linux)
8. [Build via GitHub Actions](#build-via-github-actions)
9. [Installation aufs iPhone](#installation-aufs-iphone)

---

## Die Kernidee

Im Zug einschlafen und den Halt verpassen ist aergerlich. Ein normaler Wecker
loest das nicht: Er weckt das halbe Abteil mit.

TrainAlarm dreht die Logik um. Die App fragt vor **jedem** Ton: *Landet dieser
Ton garantiert nur in meinem Ohr?* Lautet die Antwort Nein, bleibt es still --
kompromisslos, auch wenn das bedeutet, dass der Wecker nicht klingelt.

Konkret gilt eine Ausgabe als privat, wenn sie zu einem dieser Port-Typen
gehoert:

| Port-Typ | Beispiel | Gilt als privat |
|---|---|---|
| `.bluetoothA2DP` | AirPods, Over-Ears | ja |
| `.bluetoothHFP` | Bluetooth-Headset | ja |
| `.bluetoothLE` | LE-Audio-Hoerer | ja |
| `.headphones` | Klinke, Lightning-EarPods | ja |
| `.usbAudio` | USB-C-Headset (iPhone 15) | ja, abschaltbar |
| `.builtInSpeaker` / `.builtInReceiver` | iPhone-Lautsprecher | **nein** |
| `.carAudio` | Freisprecheinrichtung | **nein** |
| `.airPlay`, `.HDMI` | externe Wiedergabe | **nein** |

Wichtig ist die *strenge* Auslegung in
`AudioRouteMonitor.evaluateCurrentRoute()`: Es reicht nicht, dass irgendwo ein
Kopfhoerer haengt. **Jede** aktive Ausgabe der Route muss privat sein. Haengt
parallel noch etwas anderes daran, bleibt der Wecker stumm.

---

## Wie die Garantie technisch abgesichert ist

Vier unabhaengige Schichten. Faellt eine aus, greift die naechste.

### Schicht 1 -- Die Audio-Session

`AudioSessionController` konfiguriert die Session als `.playback`. Das ist der
Grund, warum der Wecker auch bei stummgeschaltetem iPhone bzw. auf
"Klingeln aus" gestelltem Action-Button funktioniert: `.playback` ignoriert den
Stummschalter.

```swift
try session.setCategory(.playback, mode: .default,
                        options: [.allowBluetooth, .allowBluetoothA2DP, sharing])
```

`.allowAirPlay` fehlt dort bewusst -- AirPlay wuerde den Ton auf einen
Lautsprecher im Raum schicken.

Zur Option `.allowBluetooth`: Apple sieht sie eigentlich nur fuer aufnehmende
Kategorien vor, und je nach iOS-Version quittiert `setCategory` die Kombination
mit `.playback` mit einem Fehler. Die Aufgabenstellung verlangt die Option
ausdruecklich, deshalb steht sie an erster Stelle einer **Options-Leiter**: Geht
sie durch, wird sie benutzt; wirft iOS einen Fehler, faellt der Controller
sauber auf die naechstkleinere Kombination zurueck, statt die Session
unkonfiguriert zu lassen.

### Schicht 2 -- Pruefung vor dem Abspielen

`AlarmAudioEngine.startRinging()` liest
`AVAudioSession.sharedInstance().currentRoute.outputs` und bricht ab, wenn
darin etwas Nicht-Privates steht. Danach wird die Route **ein zweites Mal**
geprueft: `setCategory` kann selbst einen Routenwechsel ausgeloest haben.

### Schicht 3 -- Der Failsafe im Render-Block

Das ist das eigentliche Sicherheitsnetz.

Der Weckton wird nicht aus einer Datei abgespielt, sondern in einem
`AVAudioSourceNode` Sample fuer Sample berechnet. Davor sitzt ein Tor
(`AudioGate`): zwei einzelne 32-Bit-Woerter im Heap, die der Render-Thread
liest und jeder beliebige Thread schreiben kann. Lesen und Schreiben eines
ausgerichteten 32-Bit-Wortes ist auf arm64 unteilbar -- es braucht also weder
Lock noch Allokation, beides waere auf dem Audio-Thread ohnehin verboten.

Der Handler von `AVAudioSession.routeChangeNotification` ist mit `queue: nil`
registriert. Das heisst: Er laeuft **synchron auf dem Thread des Absenders**,
nicht erst beim naechsten Durchlauf der Main-Runloop.

```swift
let safety = AudioRouteMonitor.evaluateCurrentRoute()
if !safety.isSafeForAlarm {
    gate.close()        // NOT-AUS, synchron, vor jedem Actor-Hop
}
```

Der Render-Block liest das Tor **pro Sample**. Ist es zu, faehrt der Pegel
innerhalb von rund vier Millisekunden auf null -- schnell genug, um
augenblicklich zu wirken, langsam genug, um kein Knacken zu erzeugen. Ein
Zurueckfallen auf den Lautsprecher ist damit ausgeschlossen: Selbst wenn iOS die
Route auf den Lautsprecher umstellt, kommt dort nur noch Stille an.

### Schicht 4 -- Watchdog und Scheduler

Waehrend des Klingelns prueft ein Timer viermal pro Sekunde die Route erneut --
fuer den Fall, dass gar keine Benachrichtigung kam, etwa nach einem Reset der
Medien-Dienste. Zusaetzlich kontrolliert `AlarmScheduler.tick()` denselben
Zustand in seiner eigenen Schleife.

---

## Projektstruktur

```
.
├── project.yml                       XcodeGen-Beschreibung (ersetzt die .xcodeproj)
├── Resources/
│   ├── Info.plist                    wird aus project.yml erzeugt
│   └── Assets.xcassets/              App-Icon, Farben
├── Sources/TrainAlarm/
│   ├── App/TrainAlarmApp.swift       Einstiegspunkt, baut den Objektgraphen
│   ├── Models/
│   │   ├── AudioOutput.swift         Einstufung von Port-Typen ("privat"?)
│   │   └── Settings.swift            Persistenz via UserDefaults
│   ├── Audio/
│   │   ├── AudioGate.swift           echtzeitsicheres Tor -- der Not-Aus
│   │   ├── AudioSessionController.swift  .playback + Options-Leiter
│   │   ├── AudioRouteMonitor.swift   Live-Ueberwachung der Route
│   │   └── AlarmAudioEngine.swift    Ton-Synthese, Failsafe, Keep-Alive
│   ├── Alarm/
│   │   ├── AlarmScheduler.swift      Zustandsautomat des Weckers
│   │   └── NotificationManager.swift lokale Mitteilungen (lautlos)
│   ├── Views/                        SwiftUI-Oberflaeche
│   └── Support/AppLog.swift          OSLog-Kategorien
├── Scripts/package-ipa.sh            .app -> .ipa
├── Tools/make_appicon.py             erzeugt das Icon ohne Xcode/Pillow
├── .github/workflows/build.yml       macOS-Runner baut die .ipa
└── docs/INSTALLATION.md              Schritt fuer Schritt von Linux aufs iPhone
```

### Zustandsautomat

```
        arm()                Weckzeit        Route privat
  off ──────────► armed ──────────────► ┌──────────────────► ringing
   ▲                │                   │                       │
   │                │ snooze()          │ Route nicht privat    │ Failsafe
   │                ▼                   ▼                       │
   │            snoozing         waitingForHeadphones ◄─────────┘
   │                                    │
   │       Wartefenster abgelaufen      │  Kopfhoerer wieder da
   └────────────────────────────────────┴──► ringing
```

Der Zustand `waitingForHeadphones` ist die bewusste Konsequenz aus der
Kernanforderung: Statt auf den Lautsprecher auszuweichen, wartet die App --
und startet den Ton in der Sekunde, in der die Kopfhoerer zurueckkommen.

---

## Der Weckton

Kein Audio-Asset, sondern Synthese im Render-Block. Das hat drei Gruende:

1. Das Projekt bleibt unter Linux vollstaendig editierbar -- keine Binaerdatei,
   die man ohne Mac nicht anfassen kann.
2. Der Pegel laesst sich sample-genau steuern, inklusive der Rampe fuer sanftes
   Aufwachen.
3. Der Failsafe kann direkt im Signalpfad sitzen.

Das Muster wiederholt sich alle zwei Sekunden: drei kurze Toene
(A5 -- Cis6 -- E6, aufsteigend), jeweils 135 ms mit weicher Ein- und
Ausblendung, danach Pause. Grundton plus Oktave geben dem Signal
Durchsetzungskraft, ohne schrill zu werden.

**Sanftes Aufwachen** (standardmaessig an) startet bei etwa 12 % der
eingestellten Lautstaerke und steigert sich quadratisch ueber 20 Sekunden auf
100 %.

---

## Hintergrundbetrieb

`UIBackgroundModes: [audio]` allein genuegt nicht -- iOS gewaehrt die
Hintergrundzeit nur, solange tatsaechlich Audio laeuft. Deshalb laeuft die
Engine, sobald der Wecker scharf ist, durchgehend weiter und gibt einen
unhoerbaren Traeger von etwa -96 dBFS aus (ein LSB bei 16 Bit). Das Tor bleibt
dabei geschlossen, der Weckton selbst also stumm.

Damit dieser Dauerbetrieb nicht die Musik der Nutzerin oder des Nutzers
abwuergt, laeuft die Session im Keep-Alive-Modus mit `.mixWithOthers`. Erst beim
Klingeln wechselt sie auf `.duckOthers`: Ein laufender Podcast wird leiser, der
Weckton setzt sich durch.

---

## Ehrliche Grenzen

Diese Punkte sind keine Bugs, sondern Eigenschaften der Plattform. Sie gehoeren
zur Bewertung dazu.

**Mitteilungstoene laufen nicht ueber die App-Session.**
Ein `UNNotificationSound` wird von der Systemwiedergabe abgespielt; welche Route
iOS dafuer waehlt, entscheidet das System -- im Zweifel der Lautsprecher. Ein
toenender Fallback wuerde also genau das kaputtmachen, was die App verspricht.
Deshalb sind alle Mitteilungen **standardmaessig lautlos** und dienen als
sichtbarer Hinweis. Wer den Systemton trotzdem will, kann ihn einschalten -- die
Oberflaeche weist dabei ausdruecklich auf die Konsequenz hin.

**Leere Kopfhoerer-Akkus kann keine App loesen.**
Sind die Kopfhoerer weg, gibt es keinen lautsprecherfreien Weg, zuverlaessig zu
wecken. TrainAlarm bleibt still, zeigt eine Mitteilung und klingelt sofort,
sobald die Verbindung zurueckkommt -- standardmaessig bis zu 15 Minuten lang.

**Der Keep-Alive ist eine Sideloading-Loesung.**
Dauerhaft laufendes (stilles) Audio ist ein etablierter Trick, wuerde in einer
App-Store-Pruefung aber hinterfragt. Fuer den Eigengebrauch per SideStore ist
das unkritisch; fuer eine Store-Veroeffentlichung muesste man sich etwas anderes
ueberlegen. Unter starkem Speicherdruck kann iOS die App trotzdem beenden --
dann bleibt die lokale Mitteilung als letzte Ebene.

**Der Keep-Alive-Traeger erreicht ohne Kopfhoerer auch den Lautsprecher.**
Solange der Wecker scharf ist und keine Kopfhoerer verbunden sind, geht das
unhoerbare Traegersignal an die Route, die iOS gerade waehlt -- also an den
Lautsprecher. Der Pegel liegt bei -96 dBFS, das entspricht einem einzigen Bit
bei 16-Bit-Aufloesung und liegt weit unter dem Eigenrauschen jedes
Handylautsprechers. Der **Weckton** selbst wird dort niemals ausgegeben: Das Tor
im Render-Block bleibt geschlossen, solange die Route nicht privat ist.

**Die Systemlautstaerke kann die App nicht setzen.**
Sie liest sie aber aus und warnt in der Statuskarte, wenn unter 25 % steht.

**`.allowBluetooth` mit `.playback`.**
Siehe Schicht 1 -- die Option steht wie gefordert an erster Stelle, mit
sauberem Rueckfall, falls iOS sie ablehnt.

---

## Entwicklung unter Linux

Es wird kein Mac gebraucht, um am Code zu arbeiten. Statt einer eingecheckten
`.xcodeproj` (die man ohne Xcode nicht sinnvoll bearbeiten kann) beschreibt
`project.yml` das Projekt vollstaendig in YAML. XcodeGen erzeugt daraus im CI
die Projektdatei.

```bash
git clone https://github.com/Bennetleicht/headphone_alarmclock.git
cd headphone_alarmclock

make check          # Projektbeschreibung und Quellen pruefen (laeuft unter Linux)
make icon           # App-Icon neu erzeugen
```

Neue Swift-Dateien muessen nirgends registriert werden -- XcodeGen nimmt alles
unter `Sources/TrainAlarm` automatisch mit.

Fuer eine echte Syntaxpruefung unter Linux kann man die Swift-Toolchain
installieren (`swift build` schlaegt fehl, weil UIKit/AVFoundation fehlen, aber
`swiftc -parse` findet Tippfehler):

```bash
find Sources -name '*.swift' -exec swiftc -parse {} +
```

Den verlaesslichen Gegencheck liefert ohnehin der CI-Build.

---

## Build via GitHub Actions

`.github/workflows/build.yml` laeuft bei jedem Push auf einem
`macos-14`-Runner (fuer oeffentliche Repositories kostenlos):

1. XcodeGen installieren, `TrainAlarm.xcodeproj` erzeugen
2. `xcodebuild` mit `CODE_SIGNING_ALLOWED=NO` -- bewusst **unsigniert**
3. `Scripts/package-ipa.sh` packt das `.app` in `Payload/` und zippt es zur `.ipa`
4. Upload als Artefakt `TrainAlarm-unsigned-ipa`

Die `.ipa` findest du unter **Actions -> der jeweilige Lauf -> Artifacts**.

Bei einem Tag `v*` (z. B. `git tag v1.0.0 && git push --tags`) haengt der
Workflow die `.ipa` zusaetzlich an ein GitHub-Release -- praktisch, weil
SideStore dann direkt per URL installieren kann.

Unsigniert ist hier kein Mangel: SideStore und AltServer signieren die App beim
Installieren ohnehin mit deinem eigenen Apple-Account neu.

---

## Installation aufs iPhone

Die vollstaendige Schritt-fuer-Schritt-Anleitung fuer Linux steht in
**[docs/INSTALLATION.md](docs/INSTALLATION.md)** -- inklusive Pairing-Datei,
SideStore, AltServer-Linux und den ueblichen Stolpersteinen.
