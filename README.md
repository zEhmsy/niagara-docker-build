<div align="center">

# niagara-docker-build

**Build and sign Niagara 4 & 5 modules in Docker — no Windows VM, no Workbench install.**

Bring your own Tridium installer, get signed module jars on macOS, Linux or WSL2.

![Docker](https://img.shields.io/badge/Docker-BuildKit-2496ED?logo=docker&logoColor=white)
![Niagara](https://img.shields.io/badge/Niagara-4.15%20%7C%205.0-005DAA)
![Platform](https://img.shields.io/badge/host-macOS%20%7C%20Linux%20%7C%20WSL2-lightgrey)
[![lint](https://github.com/zEhmsy/niagara-docker-build/actions/workflows/lint.yml/badge.svg)](https://github.com/zEhmsy/niagara-docker-build/actions/workflows/lint.yml)
[![License](https://img.shields.io/badge/License-MIT-blue)](LICENSE)

[Quick start](#-quick-start) · [Install](#-installation) · [Configuration](#-configuration) · [Signing](#-code-signing) · [How it works](#-how-it-works) · [Troubleshooting](#-troubleshooting)

</div>

---

## ⚡ Quick start

```bash
git clone https://github.com/zEhmsy/niagara-docker-build && cd niagara-docker-build
cp ~/Downloads/Niagara_5_Debian-5.0.0.12.zip installers/

./scripts/build-image.sh 5.0.0.12                              # once per version
./scripts/signing.sh init --dname "CN=MyVendor, O=MyCo, C=IT"  # once per machine
./scripts/nbuild.sh ~/dev/myModule build                       # every time
```

Signed jars land in `<project>/dist/`, or wherever you point `NIAGARA_DIST_DIR`.

---

## ✨ What you get

| | |
|---|---|
| 🐳 **One image per Niagara version** | Built from *your* licensed Tridium installer. N4 and N5 side by side, no conflicts. |
| ✍️ **Your signing certificate** | Generate one, or import your own PEM key pair or JCEKS keystore. Stable across builds. |
| 📂 **Artifacts where you want them** | Per-project `dist/`, one shared folder, or flat — your call. |
| 🧳 **Nothing hardcoded** | Installer path, output path, brand, image prefix, JDK source: all config. |
| 🚫 **No Tridium binaries in this repo** | Only Dockerfiles and scripts. `installers/` is gitignored. |
| 🖥 **Untouched project files** | The three Niagara homes are passed on the Gradle command line, so `gradle.properties` full of Windows paths keeps working for your colleagues. |

---

## 📦 Requirements

| Requirement | Notes |
|---|---|
| Docker | Docker Desktop or Engine, with BuildKit (default since 23.x) |
| ~15 GB free | ~1–2 GB per finished image, more during the build |
| Tridium installer for **Linux x64** | Yours, under your Tridium license |
| `bash`, `openssl` | Shipped with macOS and Linux; on Windows use WSL2 |
| `keytool` | Optional — the scripts fall back to a container if Java is missing |

Supported installers:

| Family | File | Example |
|---|---|---|
| Niagara 5 | zip containing the Debian `.deb` | `Niagara_5_Debian-5.0.0.12.zip` |
| Niagara 4 | zip of the Linux x64 Supervisor | `Tridium_EMEA_N4_Supervisor_for_Linux_x64-4.15.3.28.2.zip` |

> **Apple Silicon**: Tridium ships x86-64 only, so containers run under emulation.
> Everything works; a cold build goes from roughly 1 minute to 5.

---

## 🚀 Installation

**1. Clone**

```bash
git clone https://github.com/zEhmsy/niagara-docker-build
cd niagara-docker-build
```

**2. Drop in your installer** (the folder is gitignored)

```bash
cp ~/Downloads/Niagara_5_Debian-5.0.0.12.zip installers/
```

**3. Create your config** — optional, but you will want it eventually

```bash
cp niagara-build.conf.example niagara-build.conf
```

**4. Build the image** — 5 to 15 minutes, once per Niagara version

```bash
./scripts/build-image.sh 5.0.0.12
# or, for Niagara 4
./scripts/build-image.sh 4.15.3.28
```

**5. Create your signing profile**

```bash
./scripts/signing.sh init --dname "CN=MyVendor, O=MyCo, C=IT"
```

Then build anything:

```bash
./scripts/nbuild.sh /path/to/your/module build
```

---

## ⚙️ Configuration

Settings are read in this order, last one wins:

1. `~/.config/niagara-docker-build/config`
2. `niagara-build.conf` in the repo root
3. environment variables

| Variable | Default | What it does |
|---|---|---|
| `NIAGARA_INSTALLERS_DIR` | `<repo>/installers` | Where your Tridium zips live |
| `NIAGARA_SIGNING_HOME` | `~/.niagara-docker/tridium` | Where your signing profile lives |
| `NIAGARA_DIST_DIR` | *(empty)* | Where jars are copied; empty means `<project>/dist` |
| `NIAGARA_DIST_FLAT` | `0` | `1` drops every jar in one folder, no per-project subfolder |
| `NIAGARA_IMAGE_PREFIX` | `niagara-build` | Image tags: `<prefix>:<version>` |
| `NIAGARA_DEFAULT_VERSION` | *(empty)* | Fallback when the version can't be derived |
| `NIAGARA_PLATFORM` | `linux/amd64` | Container platform |
| `NIAGARA_N4_BRAND` | `TridiumEMEA` | Brand segment in N4 home paths — changes per distributor |
| `NIAGARA_N5_BRAND` | `tridium` | Brand segment in N5 home paths |
| `NIAGARA_N5_INSTALLER_GLOB` | `Niagara_5_Debian-%VERSION%*.zip` | How to find the N5 zip |
| `NIAGARA_N4_INSTALLER_GLOB` | `*N4*Linux_x64-%VERSION%*.zip` | How to find the N4 zip |
| `JDK_URL_N5` / `JDK_URL_N4` | Adoptium 25 / 8 | Full JDK placed next to Niagara's own |
| `NIAGARA_GRADLE_CACHE_PREFIX` | `niagara-gradle-cache` | Docker volume holding the Gradle cache |

Send every artifact to one shared folder:

```bash
# niagara-build.conf
NIAGARA_DIST_DIR="$HOME/Niagara/artifacts"
NIAGARA_DIST_FLAT=0     # -> $HOME/Niagara/artifacts/<projectName>/*.jar
```

Or just once, without touching the config:

```bash
NIAGARA_DIST_DIR=/tmp/out ./scripts/nbuild.sh ~/dev/myModule
```

---

## 🔐 Code signing

Niagara signs every module jar. The profile lives in `NIAGARA_SIGNING_HOME/security/`
— a **JCEKS** keystore plus a `niagara.signing.xml` holding its passwords — and is
mounted as `~/.tridium` inside the container.

> Leave that folder empty and the Tridium plugin mints a fresh key **on every
> build**: each jar carries a different certificate and Workbench asks you to trust
> it again, every time. Set the profile up once and forget about it.

### Generate a certificate

```bash
./scripts/signing.sh init --dname "CN=MyVendor, O=MyCo, C=IT"
```

RSA 3072, valid three years, with `KeyUsage=digitalSignature` and
`ExtendedKeyUsage=codeSigning` — Niagara insists on both.

### Import your own PEM

```bash
./scripts/signing.sh import --cert vendor.pem --key vendor.key.pem
./scripts/signing.sh import --cert vendor.pem --key vendor.key.pem --chain ca.pem
```

The certificate **must** carry the `Code Signing` EKU. Without it the import stops
right there, instead of letting you discover the problem five minutes into a build.

### Reuse an existing keystore

```bash
./scripts/signing.sh import --keystore niagara.signing.jceks --storepass 'thePassword'
```

### Inspect and export

```bash
./scripts/signing.sh show          # who signs, and until when
./scripts/signing.sh export-cert   # the .pem to trust
```

Import that `.pem` into the Workbench User Trust Store **and** the Platform/daemon
one, or the station will reject your module.

An existing profile is never overwritten in silence: it moves to
`security.bak.<timestamp>`.

---

## 🛠 Daily use

```bash
./scripts/nbuild.sh ~/dev/myModule                    # default task: build
./scripts/nbuild.sh ~/dev/myModule clean build
./scripts/nbuild.sh ~/dev/myModule :myModule-rt:jar --info
./scripts/nbuild.sh ~/dev/myModule shell              # poke around inside
```

The Niagara version comes from `niagara_home` in the project's `gradle.properties`.
Override it when you need to:

```bash
NIAGARA_VERSION=4.15.3.28 ./scripts/nbuild.sh ~/dev/myModule
```

Multiple versions coexist: one image and one Gradle cache volume per major version.

---

## 🏗 How it works

```
installers/*.zip ──► build-image.sh ──► image niagara-build:<version>
                                              │
      project ──┐                             │  docker run
   signing home ─┼──► nbuild.sh ──────────────┘
   (~/.tridium)  │                            ▼
                 └───────────────── signed jars in dist/
```

Four things that are not obvious, and are the reason this repo exists:

<details>
<summary><b>1. <code>dpkg -i</code> does not work in a container</b></summary>

The Niagara 5 `.deb` has a `preinst` that demands Ubuntu 24.04/26.04 *and* a live
systemd. We pull the payload straight out with `dpkg-deb --fsys-tarfile`: compiling
needs neither systemd nor the `niagara` user.
</details>

<details>
<summary><b>2. Niagara's Linux JDK is jlink-trimmed</b></summary>

It has `javac` but not the `jdk.jartool` module, so `jar` and `jarsigner` — which
the Tridium plugins invoke from `PATH` — are missing. We add a full JDK of the same
major version alongside, while `JAVA_HOME` stays on Niagara's own: it is the only
one carrying the JavaFX modules that `bajaui`, `gx` and `workbench` need.

On N4 that also means symlinks inside `jre/bin`, because Gradle calls
`${JAVA_HOME}/bin/<tool>` directly rather than going through `PATH` — and `javadoc`
must come from a **JDK 8**, since the Tridium doclet still uses the old Doclet API.
</details>

<details>
<summary><b>3. The N4 installer must be silent-installed, not unpacked</b></summary>

The Tridium Gradle plugins are not in the zip; the installer generates them under
`<niagara_home>/etc/m2`. Inside `silent.properties` an **empty value means "yes"**
(so `addUsers` has to be forced to `no`), and `installDirectory` must be left empty
or the install dies on *"failed to set the Host ID"*.
</details>

<details>
<summary><b>4. The container user carries your uid/gid</b></summary>

Files written into the bind mount stay yours instead of turning up owned by root.
</details>

---

## 🧪 Verified on

| Host | Niagara | Result |
|---|---|---|
| macOS, Apple Silicon (x86-64 emulation) | `4.15.3.28` | `-rt` + `-wb` jars, signed |
| macOS, Apple Silicon (x86-64 emulation) | `5.0.0.12` | single jar, signed |

Both with a signing profile created by `signing.sh`, and `META-INF/NIAGARA4.SF`
present in the output.

---

## 🩺 Troubleshooting

<details>
<summary><code>Certificate for Niagara4Modules is not valid for code signing</code></summary>

The certificate lacks `ExtendedKeyUsage: Code Signing`. Check with
`./scripts/signing.sh show`, then either regenerate with `signing.sh init` or ask
whoever issues your corporate certificate to add the EKU.
</details>

<details>
<summary><code>no installer found for Niagara &lt;version&gt;</code></summary>

Your zip name doesn't match the glob. Pass it explicitly
(`./scripts/build-image.sh 4.15.3.28 MyInstaller.zip`) or adjust
`NIAGARA_N4_INSTALLER_GLOB` / `NIAGARA_N5_INSTALLER_GLOB`.
</details>

<details>
<summary>Build fails unzipping the installer inside the container</summary>

The zip is being filtered out by `.dockerignore`, which keeps the other gigabytes
of installers out of the build context. Add a `!<name-or-pattern>.zip` line to
`docker/Dockerfile.n5.dockerignore` or `docker/Dockerfile.n4.dockerignore`.
</details>

<details>
<summary><code>image niagara-build:&lt;version&gt; is missing</code></summary>

Step 4 is missing: `./scripts/build-image.sh <version>`.
</details>

<details>
<summary>The module signs fine but the station refuses it</summary>

Trust is missing. Run `./scripts/signing.sh export-cert` and import the `.pem` into
the Workbench **and** Platform User Trust Stores.
</details>

<details>
<summary>Builds crawl on Apple Silicon</summary>

That's x86-64 emulation — Tridium publishes no ARM installer. The Gradle cache is
persistent, so only the first build pays full price.
</details>

---

## 📄 License & legal

The code in this repository — Dockerfiles and scripts — is MIT licensed. See
[LICENSE](LICENSE).

**It contains, distributes and downloads no Tridium software.** You supply the
Niagara installers under your own Tridium license, and they stay out of the
repository (`installers/` is gitignored).

The images you build **do contain Tridium binaries**. Keep them internal: don't
push them to public registries, and don't hand them outside the reach of your
license.

Niagara and Tridium are trademarks of Tridium, Inc. This project is not affiliated
with or endorsed by Tridium.

---

<div align="center">
<sub>Built to stop waiting on a Windows VM to compile a jar.</sub>
</div>
