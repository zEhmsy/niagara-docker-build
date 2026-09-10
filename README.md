# niagara-docker-build

Compila e firma moduli **Niagara 4** e **Niagara 5** dentro un container Docker,
partendo dagli installer Tridium che hai gia' in licenza. Niente VM Windows,
niente Workbench installato, niente toolchain da sistemare a mano: `git clone`,
uno zip dell'installer, un comando.

```bash
./scripts/build-image.sh 4.15.3.28          # una volta per versione
./scripts/nbuild.sh ~/dev/mioModulo build   # tutte le volte che serve
```

I jar escono firmati e pronti da caricare sulla station.

- Funziona su macOS (Intel e Apple Silicon), Linux e WSL2.
- Il certificato di firma e' **tuo**: lo generi o importi il tuo PEM.
- Gli artefatti finiscono dove decidi tu.
- Niente binari Tridium in questo repo: solo Dockerfile e script.

**Verificato su**: macOS Apple Silicon (emulazione x86-64), Docker Desktop —
Niagara `4.15.3.28` (jar `-rt` + `-wb`) e Niagara `5.0.0.12` (jar unico),
entrambi firmati e caricati con profilo di firma generato dagli script.

---

## Indice

1. [Requisiti](#requisiti)
2. [Installazione in 5 passi](#installazione-in-5-passi)
3. [Configurazione](#configurazione)
4. [Firma dei moduli](#firma-dei-moduli)
5. [Uso quotidiano](#uso-quotidiano)
6. [Come funziona (e perche' cosi')](#come-funziona-e-perche-cosi)
7. [Troubleshooting](#troubleshooting)
8. [Licenza e nota legale](#licenza-e-nota-legale)

---

## Requisiti

| Cosa | Note |
|---|---|
| Docker | Docker Desktop o Docker Engine, con BuildKit (default dal 23.x) |
| ~15 GB liberi | l'immagine finale pesa ~1 GB per versione, il build ne usa di piu' |
| Installer Tridium per **Linux x64** | fornito da Tridium/distributore, sotto la tua licenza |
| `bash`, `openssl` | presenti su macOS e Linux; su Windows usa WSL2 |
| `keytool` (opzionale) | se manca, gli script lo prendono da un container |

Installer supportati:

| Famiglia | File | Esempio |
|---|---|---|
| Niagara 5 | zip con il `.deb` Debian | `Niagara_5_Debian-5.0.0.12.zip` |
| Niagara 4 | zip del Supervisor Linux x64 | `Tridium_EMEA_N4_Supervisor_for_Linux_x64-4.15.3.28.2.zip` |

> Gli installer sono **solo x86-64**. Su Apple Silicon i container girano in
> emulazione: funziona tutto, ma un build a freddo puo' passare da ~1 a ~5 minuti.

---

## Installazione in 5 passi

```bash
# 1. clona
git clone https://github.com/zEhmsy/niagara-docker-build.git
cd niagara-docker-build

# 2. metti l'installer Tridium nella cartella installers/ (gitignorata)
mkdir -p installers
cp ~/Downloads/Niagara_5_Debian-5.0.0.12.zip installers/

# 3. crea la tua configurazione (opzionale ma consigliato)
cp niagara-build.conf.example niagara-build.conf

# 4. costruisci l'immagine per la tua versione (5-15 minuti, una volta sola)
./scripts/build-image.sh 5.0.0.12

# 5. crea il profilo di firma
./scripts/signing.sh init --dname "CN=MioVendor, O=MiaAzienda, C=IT"
```

Prova subito:

```bash
./scripts/nbuild.sh /percorso/al/tuo/modulo build
```

Alla fine trovi i jar in `<modulo>/dist/` (o dove hai impostato `NIAGARA_DIST_DIR`).

---

## Configurazione

Gli script leggono, in ordine:

1. `~/.config/niagara-docker-build/config`
2. `niagara-build.conf` nella root del repo
3. le variabili d'ambiente (vincono su tutto)

Copia `niagara-build.conf.example` e modifica solo cio' che ti serve.

| Variabile | Default | A cosa serve |
|---|---|---|
| `NIAGARA_INSTALLERS_DIR` | `<repo>/installers` | dove tieni gli zip Tridium |
| `NIAGARA_SIGNING_HOME` | `~/.niagara-docker/tridium` | dove vive il tuo profilo di firma |
| `NIAGARA_DIST_DIR` | *(vuoto)* | dove copiare i jar; vuoto = `<progetto>/dist` |
| `NIAGARA_DIST_FLAT` | `0` | `1` = tutti i jar insieme, senza sottocartella per progetto |
| `NIAGARA_IMAGE_PREFIX` | `niagara-build` | nome delle immagini: `<prefisso>:<versione>` |
| `NIAGARA_DEFAULT_VERSION` | *(vuota)* | versione usata se non la passi e non e' deducibile |
| `NIAGARA_PLATFORM` | `linux/amd64` | piattaforma dei container |
| `NIAGARA_N4_BRAND` | `TridiumEMEA` | brand nel path delle home N4 (cambia col distributore) |
| `NIAGARA_N5_BRAND` | `tridium` | brand nel path delle home N5 |
| `NIAGARA_N5_INSTALLER_GLOB` | `Niagara_5_Debian-%VERSION%*.zip` | come trovare lo zip N5 |
| `NIAGARA_N4_INSTALLER_GLOB` | `*N4*Linux_x64-%VERSION%*.zip` | come trovare lo zip N4 |
| `JDK_URL_N5` / `JDK_URL_N4` | Adoptium 25 / 8 | JDK completo affiancato a quello Niagara |
| `NIAGARA_GRADLE_CACHE_PREFIX` | `niagara-gradle-cache` | volume Docker con la cache Gradle |

Esempio: artefatti tutti in un'unica cartella condivisa.

```bash
# niagara-build.conf
NIAGARA_DIST_DIR="$HOME/Niagara/artifacts"
NIAGARA_DIST_FLAT=0     # -> $HOME/Niagara/artifacts/<nomeProgetto>/*.jar
```

Oppure una tantum, senza toccare la config:

```bash
NIAGARA_DIST_DIR=/tmp/out ./scripts/nbuild.sh ~/dev/mioModulo
```

---

## Firma dei moduli

Niagara firma ogni jar. Il profilo di firma sta in
`NIAGARA_SIGNING_HOME/security/` (montato come `~/.tridium` nel container) e
contiene un keystore **JCEKS** piu' un `niagara.signing.xml` con le password.

> Se quella cartella e' vuota, il plugin Tridium genera una chiave nuova **a ogni
> build**: i jar risultano firmati da un certificato sempre diverso e il Workbench
> va ri-fidato ogni volta. Crea il profilo una volta e non pensarci piu'.

### Generare un certificato nuovo

```bash
./scripts/signing.sh init --dname "CN=MioVendor, O=MiaAzienda, C=IT"
```

Crea chiave RSA 3072, valida 3 anni, con `KeyUsage=digitalSignature` e
`ExtendedKeyUsage=codeSigning` (Niagara pretende entrambi), e ti stampa il path
del certificato pubblico da fidare.

### Importare il TUO certificato (PEM)

```bash
./scripts/signing.sh import --cert vendor.pem --key vendor.key.pem
# con catena intermedia:
./scripts/signing.sh import --cert vendor.pem --key vendor.key.pem --chain ca.pem
```

Il cert **deve** avere l'EKU `Code Signing`: senza, lo script si ferma subito
invece di farti scoprire il problema a meta' compilazione.

### Riusare un keystore esistente (es. copiato dal Workbench)

```bash
./scripts/signing.sh import --keystore niagara.signing.jceks --storepass 'lapassword'
```

### Ispezione ed export

```bash
./scripts/signing.sh show          # chi firma, con che validita'
./scripts/signing.sh export-cert   # .pem da importare come trusted
```

Il `.pem` esportato va importato **sia** nella User Trust Store del Workbench
**sia** in quella della Platform/daemon, altrimenti la station rifiuta il modulo.

Il profilo precedente non viene mai sovrascritto in silenzio: finisce in
`security.bak.<timestamp>`.

---

## Uso quotidiano

```bash
# build standard (task `build`)
./scripts/nbuild.sh ~/dev/mioModulo

# task Gradle espliciti
./scripts/nbuild.sh ~/dev/mioModulo clean build
./scripts/nbuild.sh ~/dev/mioModulo :mioModulo-rt:jar --info

# shell dentro il container, per indagare
./scripts/nbuild.sh ~/dev/mioModulo shell
```

La versione di Niagara viene dedotta dal `niagara_home` nel `gradle.properties`
del progetto. Per forzarla:

```bash
NIAGARA_VERSION=4.15.3.28 ./scripts/nbuild.sh ~/dev/mioModulo
```

Non serve toccare i `gradle.properties` con i path Windows dei colleghi: le tre
home Niagara vengono passate a Gradle da riga di comando (`-Pniagara_home`,
`-Pniagara_user_home`, `-Pniagara_config_home`).

Piu' versioni convivono senza problemi: un'immagine e una cache Gradle per
major version.

---

## Come funziona (e perche' cosi')

```
installers/*.zip ──► build-image.sh ──► immagine niagara-build:<versione>
                                              │
   progetto ──┐                               │  docker run
   ~/.tridium ─┼──► nbuild.sh ────────────────┘
   (firma)     │                              ▼
               └──────────────────── jar firmati in dist/
```

Quattro dettagli non ovvi, che sono la ragione d'essere di questo repo:

1. **`dpkg -i` non funziona in un container.** Il `preinst` del `.deb` di
   Niagara 5 pretende Ubuntu 24.04/26.04 *e* systemd attivo. Estraiamo
   direttamente il payload con `dpkg-deb --fsys-tarfile`: per compilare non
   servono ne' systemd ne' l'utente `niagara`.
2. **Il JDK Linux di Niagara e' trimmato con jlink.** Ha `javac` ma non il
   modulo `jdk.jartool`, quindi mancano `jar` e `jarsigner`, che i plugin
   Tridium invocano da PATH. Affianchiamo un JDK completo della stessa major
   version, ma `JAVA_HOME` resta quello di Niagara: e' l'unico con i moduli
   JavaFX richiesti da `bajaui`/`gx`/`workbench`. Su N4 servono anche i symlink
   dentro `jre/bin`, perche' Gradle invoca `${JAVA_HOME}/bin/<tool>` senza
   passare dal PATH, e il `javadoc` deve essere quello del **JDK 8** (il doclet
   Tridium usa la vecchia Doclet API).
3. **L'installer N4 va in silent install, non estratto**: i plugin Gradle
   Tridium non sono nello zip, li crea l'installer in `<niagara_home>/etc/m2`.
   Nel file `silent.properties` un valore **vuoto vale "si'"** (quindi
   `addUsers` va forzato a `no`) e `installDirectory` va lasciato vuoto,
   altrimenti l'installer muore su "failed to set the Host ID".
4. **L'utente del container ha il tuo uid/gid**, cosi' i file scritti nel bind
   mount restano tuoi e non di root.

---

## Troubleshooting

**`Certificate for Niagara4Modules is not valid for code signing`**
Il certificato non ha `ExtendedKeyUsage: Code Signing`. Verifica con
`./scripts/signing.sh show` e rigenera con `./scripts/signing.sh init`, oppure
fatti riemettere il cert aziendale con l'EKU giusto.

**`installer per Niagara <ver> non trovato`**
Il nome dello zip non combacia col glob. Passa il nome esplicito
(`./scripts/build-image.sh 4.15.3.28 MioInstaller.zip`) o adatta
`NIAGARA_N4_INSTALLER_GLOB` / `NIAGARA_N5_INSTALLER_GLOB`.

**Build che fallisce con "file not found" durante l'unzip nel container**
Lo zip e' escluso dal `.dockerignore` (che tiene fuori dal context gli altri
GB di installer). Aggiungi la riga `!<nome-o-pattern>.zip` in
`docker/Dockerfile.n5.dockerignore` o `docker/Dockerfile.n4.dockerignore`.

**`immagine niagara-build:<ver> assente`**
Manca il passo 4: `./scripts/build-image.sh <ver>`.

**Il modulo si firma ma la station lo rifiuta**
Manca il trust: `./scripts/signing.sh export-cert` e importa il `.pem` nella
User Trust Store del Workbench **e** della Platform.

**Build lentissimo su Apple Silicon**
E' l'emulazione x86-64: gli installer Tridium non hanno build ARM. La cache
Gradle e' persistente, quindi solo il primo build paga il prezzo pieno.

**`il daemon Docker non risponde`**
Avvia Docker Desktop (o `dockerd`) e riprova.

---

## Licenza e nota legale

Il codice di questo repository (Dockerfile e script) e' rilasciato sotto licenza
MIT: vedi [LICENSE](LICENSE).

**Non contiene, non distribuisce e non scarica software Tridium.** Gli installer
Niagara li fornisci tu, sotto la tua licenza Tridium, e restano fuori dal
repository (`installers/` e' gitignorata).

Le immagini che costruisci **contengono binari Tridium**: sono per uso interno.
Non pubblicarle su registry pubblici (Docker Hub, GHCR public) e non condividerle
fuori dal perimetro della tua licenza.

Niagara e Tridium sono marchi di Tridium, Inc. Questo progetto non e' affiliato
ne' supportato da Tridium.
