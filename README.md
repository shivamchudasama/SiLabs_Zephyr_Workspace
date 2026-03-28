# Silicon Labs BLE — Zephyr Manifest (Forest Topology)

Standalone manifest repository for managing **Zephyr workspaces** targeting
**Silicon Labs EFR32BG24** BLE projects.

Built on the **Simplicity SDK for Zephyr** (`zephyr-silabs` v2025.12.1),
which provides Silicon Labs' downstream forks of Zephyr, hal\_silabs, and
mbedtls with hardware crypto acceleration.

Default board: **xg24\_dk2601b** (EFR32xG24 Dev Kit)

---

## Why zephyr-silabs instead of upstream Zephyr?

Silicon Labs maintains a downstream manifest repo
([`SiliconLabsSoftware/zephyr-silabs`](https://github.com/SiliconLabsSoftware/zephyr-silabs))
that provides several advantages over pointing directly at upstream Zephyr:

- **SiLabs fork of Zephyr** — includes patches not yet upstreamed
- **SiLabs fork of hal\_silabs** — includes Simplicity SDK + WiSeConnect
- **SiLabs fork of mbedtls** — hardware-accelerated crypto (AES, SHA, ECDSA)
- **Pre-filtered modules** — non-SiLabs HALs are already excluded, so
  `west update` is fast without needing a `name-allowlist`

---

## Repository strategy

| # | Repo | Contains | Owned by |
|---|------|----------|----------|
| 1 | **This repo** (manifest) | `west.yml` only | Platform / infra team |
| 2 | `silabs-ble-app` | App source (`CMakeLists.txt`, `prj.conf`, `src/`) | App developer |
| 3+ | `my-sensor-app`, etc. | Additional product apps | App developers |
| — | `zephyr-silabs`, `zephyr`, `hal_silabs`, … | SDK & modules — **managed by West** | Silicon Labs / upstream |

**No git submodules.** West handles all external dependency cloning and
version pinning.

---

## Workspace layout after `west update`

```
my-workspace/                   ← west topdir
├── .west/
├── manifest/                   ← THIS REPO  (west.yml)
├── silabs-ble-app/             ← REPO 2  (your app, cloned by West)
│   ├── CMakeLists.txt
│   ├── prj.conf
│   ├── boards/
│   │   └── xg24_dk2601b.overlay
│   └── src/
│       └── main.c
├── zephyr-silabs/              ← SiLabs manifest repo (imported by West)
├── zephyr/                     ← SiLabs fork of Zephyr
└── modules/
    ├── crypto/mbedtls/         ← SiLabs fork (HW crypto acceleration)
    ├── hal/cmsis_6/
    └── hal/silabs/             ← SiLabs fork (Simplicity SDK + blobs)
```

---

## Prerequisites (Windows)

1. **Enable long paths** (admin PowerShell, then reboot):

   ```powershell
   New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" `
       -Name "LongPathsEnabled" -Value 1 -PropertyType DWORD -Force
   ```

2. **Install tooling** per the
   [Zephyr Getting Started Guide](https://docs.zephyrproject.org/latest/develop/getting_started/index.html):

   ```powershell
   choco install cmake ninja gperf python3 git dtc-msys2 wget 7zip
   pip install west
   ```

3. **Install the Zephyr SDK** from
   [github.com/zephyrproject-rtos/sdk-ng/releases](https://github.com/zephyrproject-rtos/sdk-ng/releases).

---

## Quick start

```bash
# 1. Create workspace and clone the manifest repo
mkdir my-workspace && cd my-workspace
git clone <MANIFEST_REPO_URL> manifest

# 2. Initialise West from the local manifest
west init -l manifest

# 3. Fetch Zephyr (SiLabs fork), modules, AND your app repo(s)
west update

# 4. Install Python dependencies
pip install -r zephyr/scripts/requirements.txt

# 5. Download Silicon Labs BLE radio blobs
west blobs fetch hal_silabs

# 6. Build
west build -b xg24_dk2601b silabs-ble-app

# 7. Flash
west flash
```

---

## Adding a new application

1. Create a new Git repo with your app code.
2. Push it to your Git server under the same org/user.
3. Add it as a project in `west.yml`:

   ```yaml
   - name: my-new-product
     revision: main
     path: my-new-product
   ```

4. Run `west update`.
5. Build: `west build -b xg24_dk2601b my-new-product`

---

## Updating the Silicon Labs SDK

1. Check for new releases at
   [SiliconLabsSoftware/zephyr-silabs/releases](https://github.com/SiliconLabsSoftware/zephyr-silabs/releases).
2. Update the `revision:` under `zephyr-silabs` in `west.yml`.
3. Run `west update`.
4. Re-run `pip install -r zephyr/scripts/requirements.txt`.
5. Re-run `west blobs fetch hal_silabs`.

---

## Useful commands

| Task                     | Command                                       |
| ------------------------ | --------------------------------------------- |
| Build                    | `west build -b xg24_dk2601b silabs-ble-app`   |
| Clean rebuild            | `west build -b xg24_dk2601b silabs-ble-app -p`|
| Flash                    | `west flash`                                  |
| Menuconfig               | `west build -t menuconfig`                    |
| Fetch radio blobs        | `west blobs fetch hal_silabs`                 |
| List blobs               | `west blobs list hal_silabs`                  |
| See resolved manifest    | `west manifest --resolve`                     |
| Enable PTI for sniffer   | Add `-S silabs-pti` to build command          |

---

## License

SPDX-License-Identifier: Apache-2.0
