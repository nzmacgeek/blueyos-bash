# blueyos-bash

GNU Bash v5, GNU Readline 8.2, and ncurses 6.5 — cross-compiled for
[BlueyOS](https://github.com/nzmacgeek/biscuits) against
[musl-blueyos](https://github.com/nzmacgeek/musl-blueyos) (i386 ELF, static).

All three packages are distributed as **core** dimsim packages so they can be
installed offline into a target sysroot before the system has ever booted.

## Packages

| Package | Version | Description |
|---------|---------|-------------|
| `ncurses` | 6.5 | Terminal handling library (wide-char enabled) |
| `readline` | 8.2 | GNU Readline — command-line editing and history |
| `bash` | 5.2.21 | The default interactive shell (`/bin/bash`) |

Each package lives in its own subdirectory following the
[dimsim](https://github.com/nzmacgeek/dimsim) package format:

```
<pkg>/
  meta/
    manifest.json        Package metadata (name, version, deps, core: true)
    scripts/
      preinst            Runs before files are placed
      postinst           Runs after files are placed
      prerm              Runs before files are removed
      postrm             Runs after files are removed
  payload/               Files installed to / on the target (staged by make)
```

## Building

### Prerequisites

- `gcc` with 32-bit support (`gcc-multilib` on Debian/Ubuntu)
- `make`, `curl`, `patch`
- `git`
- A built musl-blueyos sysroot (see below)

### Quick start on a fresh host

```bash
# 1. Build the musl-blueyos sysroot (clones nzmacgeek/musl-blueyos)
make musl

# 2. Build all three packages and stage their payloads
make

# 3. Optionally install the staged payloads into a sysroot
make install SYSROOT=/mnt/blueyos

# 4. Assemble .dpk archives (requires dpkbuild from nzmacgeek/dimsim)
make dpk
```

### Quick start on a BlueyOS build host

If a BlueyOS sysroot is already installed at `/opt/blueyos-sysroot`, the build now
auto-detects the compiler/sysroot prefix under `/opt/blueyos-sysroot/usr` when
needed:

```bash
make        # MUSL_PREFIX auto-resolves to /opt/blueyos-sysroot/usr on BlueyOS hosts
make install # installs payloads into /opt/blueyos-sysroot by default
make dpk
```

### Building individual packages

```bash
make ncurses    # downloads ncurses 6.5, builds, stages payload
make readline   # depends on ncurses
make bash       # depends on ncurses + readline
make install    # build everything, then copy payloads into the target sysroot
```

### Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MUSL_PREFIX` | auto-detected (`/opt/blueyos-sysroot/usr` or `build/musl`) | musl sysroot/compiler prefix |
| `SYSROOT` | auto-detected (`/opt/blueyos-sysroot` when present) | target root for `make install` |
| `DESTDIR` | unset | alias for `SYSROOT` during `make install` |
| `BUILD_DIR` | `build` | output directory |
| `NCURSES_VERSION` | `6.5` | ncurses source version |
| `READLINE_VERSION` | `8.2` | readline source version |
| `BASH_VERSION` | `5.2` | bash base tarball version |
| `BASH_PATCH_LEVEL` | `21` | number of GNU official bash patches to apply |

### Installing into a sysroot

`make install` copies the already staged payload trees from `ncurses/payload/`,
`readline/payload/`, and `bash/payload/` into a target root, preserving file
permissions and symlinks.

```bash
make install SYSROOT=/mnt/blueyos

# equivalent
make install DESTDIR=/mnt/blueyos
```

If `SYSROOT`/`DESTDIR` is not provided, the Makefile defaults to
`/opt/blueyos-sysroot` when that directory exists. If your compiler prefix is
`/some/path/usr`, `make install` can also derive the target root as `/some/path`.

## Offline / sysroot install

Because all three packages declare `"core": true` in their manifests, dimsim
will install them into a fresh sysroot without requiring `/bin/bash` to be
present first:

```bash
dimsim --root /mnt/blueyos install ncurses readline bash
```

See the [dimsim offline install guide](https://github.com/nzmacgeek/dimsim/blob/main/docs/offline-install.md)
for the full workflow.

## Build outputs

| Path | Contents |
|------|----------|
| `build/ncurses-install/` | ncurses headers + static libs (used by readline/bash builds) |
| `build/readline-install/` | readline headers + static libs (used by bash build) |
| `ncurses/payload/` | staged ncurses files (mapped to `/` at install time) |
| `readline/payload/` | staged readline files |
| `bash/payload/` | staged bash binary + man page |
| `build/dpk/` | assembled `.dpk` archives |

## Build tools

| Script | Purpose |
|--------|---------|
| `tools/build-musl.sh` | Clone and build musl-blueyos for i386 |
| `tools/build-ncurses.sh` | Download, configure, and build ncurses 6.5 |
| `tools/build-readline.sh` | Download, configure, and build readline 8.2 |
| `tools/build-bash.sh` | Download, patch, configure, and build bash 5.2.x |

---

⚠️  VIBE CODED RESEARCH PROJECT — NOT FOR PRODUCTION USE ⚠️
