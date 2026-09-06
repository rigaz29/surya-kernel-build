# surya-kernel-build

Tooling and documentation for building the **Xiaomi Poco X3 NFC (`surya`)** kernel from
[`rigaz29/kernel_xiaomi_surya`](https://github.com/rigaz29/kernel_xiaomi_surya)
and packaging it into a flashable [AnyKernel3](https://github.com/osm0sis/AnyKernel3) zip.

This repo does **not** contain the kernel source — only the build recipe, scripts and tools.

| | |
|---|---|
| Device | Xiaomi Poco X3 NFC (`surya`, also `karna`) |
| SoC | Qualcomm SM7150 / `sdmmagpie` (`sm8150` tree) |
| Kernel | Linux 4.14.357 (ELTS / OpenELA) |
| Source | [`rigaz29/kernel_xiaomi_surya`](https://github.com/rigaz29/kernel_xiaomi_surya), branch `seventeen` |
| Upstream | [`LineageOS/android_kernel_qcom_sm8150`](https://github.com/LineageOS/android_kernel_qcom_sm8150), branch `lineage-20` |
| Root | [ReSukiSU](https://github.com/ReSukiSU/ReSukiSU) `v4.2.0-rc1-88695111`, SUSFS inline hooks |
| Hiding | [SUSFS](https://gitlab.com/simonpunk/susfs4ksu) `v2.3.0` (non-GKI 4.14 backport) |

## Repo layout

```
build.sh            # configure + compile the kernel
package.sh          # assemble the AnyKernel3 zip from the build output
anykernel/          # AnyKernel3, pre-configured for surya
tools/mkdtboimg.py  # dtbo.img builder (AOSP libufdt)
```

The toolchain (Proton Clang, ~1.6 GB) is deliberately not committed; `build.sh`
downloads it automatically on first run.

## Prerequisites

Tested on Ubuntu 24.04 (glibc 2.39, binutils 2.42):

```bash
sudo apt install -y git make zip python3 device-tree-compiler \
                    build-essential libssl-dev bc bison flex
```

`device-tree-compiler` is **required** — see [Issue 2](#issue-2-the-in-tree-dtc-is-too-old).

## Usage

```bash
git clone https://github.com/rigaz29/kernel_xiaomi_surya.git ~/surya/kernel_xiaomi_surya
git clone https://github.com/rigaz29/surya-kernel-build.git ~/surya/surya-kernel-build

cd ~/surya/surya-kernel-build
./build.sh        # fetch the toolchain (once), defconfig, compile
./package.sh      # produce release/Stormbreaker-surya-<version>-<date>.zip
```

Overridable variables: `KERNEL_DIR`, `TC_DIR`, `DEFCONFIG`, `JOBS`, `DTC_EXT`, `DEST`,
`KSU_COMMIT`.

```bash
KERNEL_DIR=/path/to/kernel JOBS=8 ./build.sh
```

## Toolchain

| Component | Version |
|---|---|
| Compiler | Proton Clang 13.0.0 ([`kdrag0n/proton-clang`](https://github.com/kdrag0n/proton-clang)) |
| Linker (target) | LLD 13.0.0 |
| Linker (host) | system binutils (2.42) |
| Cross binutils | `aarch64-linux-gnu-`, `arm-linux-gnueabi-` |
| dtc | system dtc 1.7.0 (**not** the in-tree `scripts/dtc`) |

Clang 13 was chosen because it matches this 4.14 kernel, which uses ThinLTO plus
Shadow Call Stack. Much newer Clang releases tend to reject kernel code of this age.
Note that the official Stormbreaker builds likely use a different Clang, so binaries
produced from this repo will **not** be byte-for-byte identical to theirs.

## Relevant kernel configuration

From `arch/arm64/configs/surya_defconfig`:

| Option | Value | Effect |
|---|---|---|
| `CONFIG_LTO_CLANG` / `CONFIG_THINLTO` | `y` | requires `ld.lld` (the Makefile uses `--thinlto-cache-dir`) |
| `CONFIG_SHADOW_CALL_STACK` | `y` | requires a Clang with arm64 SCS support |
| `CONFIG_CFI_CLANG` | not set | — |
| `CONFIG_BUILD_ARM64_DT_OVERLAY` | `y` | the build produces `.dtbo`, `DTC_FLAGS := -@` |
| `CONFIG_BUILD_ARM64_APPENDED_DTB_IMAGE` | **not set** | output is a plain `Image.gz`, **not** `Image.gz-dtb` |
| `CONFIG_LOCALVERSION` | `-Stormbreaker` | becomes part of the kernel version string |

## Artifacts and how AnyKernel3 uses them

| File in the zip | Source | Role |
|---|---|---|
| `Image.gz` | `out/arch/arm64/boot/Image.gz` | the kernel; written into the boot image |
| `dtb` | `out/.../qcom/surya-sdmmagpie.dtb` | replaces the dtb section of the boot image (surya uses boot header v2) |
| `dtbo.img` | built from `surya-sdmmagpie-overlay.dtbo` | flashed to the `dtbo` partition by `write_boot` |

`dtb` and `dtbo.img` are built from the same source as the kernel, so they stay
consistent (the last upstream merge did change the dts: coresight references and the
`disp_rdump_memory` region). If you would rather keep the device's own copies, simply
delete those two files from the zip — AnyKernel3 falls back to the existing ones.

`anykernel/anykernel.sh` configuration:

```
device.name1=surya
device.name2=karna
BLOCK=/dev/block/bootdevice/by-name/boot
IS_SLOT_DEVICE=0        # surya is non-A/B
do.devicecheck=1
```

## ReSukiSU integration

This kernel is integrated with [ReSukiSU](https://github.com/ReSukiSU/ReSukiSU)
(a KernelSU derivative) following its
[official documentation](https://resukisu.org/guide/manual-integrate.html).

The driver itself is **not** committed into the kernel tree. `build.sh` fetches it
through the official `kernel/setup.sh` and **pins the commit** to `88695111`
(override with `KSU_COMMIT=`), so builds stay reproducible even as the upstream
`main` branch moves.

### Hooking method

| Method | Used? | Reason |
|---|---|---|
| `KSU_TRACEPOINT_HOOK` | no | GKI2 only (kernel 5.10+) |
| `KSU_MANUAL_HOOK` | no | superseded — see below |
| `KSU_SUSFS` | **yes** | SUSFS inline hooks, required for SUSFS support |

ReSukiSU puts all three in the same Kconfig `choice`, so exactly one can be
active. Manual hooks were used first (commit `58676fa`); enabling SUSFS replaces
them with inline hooks. Both call the same `ksu_handle_*` entry points, but the
inline variant gates them behind `susfs_is_current_proc_no_su()` and the
`ksu_su_compat_enabled` static branch, and resolves paths through
`filename_lookup()` to avoid a second lookup.

Defconfig options added:

```
# ReSukiSU
CONFIG_KSU=y
CONFIG_KSU_SUSFS=y

# SUSFS
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_MAP=y
```

`KSU_SUSFS` depends on `THREAD_INFO_IN_TASK` and `64BIT`; `arch/arm64/Kconfig`
already selects the former, so nothing extra is needed.

## SUSFS integration

Upstream [susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu) still carries a
`kernel-4.14` branch, but it is no longer maintained alongside the GKI branches,
and ReSukiSU's own docs say SUSFS "no longer supports NonGKI" without a manual
backport. The working path for 4.14 is the backport maintained by
[JackA1ltman/NonGKI_Kernel_Build_2nd](https://github.com/JackA1ltman/NonGKI_Kernel_Build_2nd):

| Piece | Source |
|---|---|
| SUSFS core | `Patches/Patch/susfs_patch_to_4.14.patch` |
| Syscall hooks | `Patches/susfs_inline_hook_patches.sh` |

The core patch is self-contained: it creates `fs/susfs.c` (~1500 lines),
`include/linux/susfs.h` and `include/linux/susfs_def.h`, and modifies 16
existing files. Nothing needs to be cloned from susfs4ksu itself.

> Note: the shell script prints `Current susfs patch version:2.2.00`, but that
> label is stale. The patched `include/linux/susfs.h` declares `v2.3.0`, and that
> is what ReSukiSU's Kbuild reads and reports.

### Hunks that need manual fixing

Two hunks of the core patch do not apply to this tree. Both are expected — the
build repo upstream even ships a `.rej` collection step for exactly this.

**`fs/proc/cmdline.c`** — this tree carries the `CONFIG_INITRAMFS_IGNORE_SKIP_FLAG`
handling that Xiaomi/LineageOS added, so the patch context does not match. The
fix is to insert the extern block after the includes and the spoof check at the
top of `cmdline_proc_show()`, ahead of the `INITRAMFS` block.

**`fs/namei.c` hunk 21** — the patch was written against a tree with the
three-argument `vfs_open(&path, file, current_cred())`; this tree has the
two-argument `vfs_open(&path, file)`. Re-apply the hunk by hand, keeping the
local signature.

This second one is **not optional**. Hunk 21 declares `old_dfd` and
`fake_filename` in `do_tmpfile()`, `do_o_path()` and `path_openat()`, while hunk
22 applies cleanly and *uses* those variables inside `path_openat()`. Skipping
hunk 21 leaves the tree referencing undeclared variables, and the build fails.

### Verification

ReSukiSU runs a hook checker at compile time and fails the build if anything does not
match. All of them passed:

```
-- ReSukiSU: using SuSFS Inline hook
-- ReSukiSU/susfs_inline: ksu_handle_setresuid found
-- ReSukiSU/susfs_inline: ksu_handle_execveat found
-- ReSukiSU/susfs_inline: ksu_handle_faccessat found
-- ReSukiSU/susfs_inline: ksu_handle_sys_read found
-- ReSukiSU/susfs_inline: ksu_handle_stat found
-- ReSukiSU/susfs_inline: ksu_handle_sys_reboot found
-- ReSukiSU/susfs_inline: ksu_handle_input_handle_event found
-- SUSFS_VERSION: v2.3.0
```

Version embedded in the kernel: `v4.2.0-rc1-88695111@ReSukiSU`.

After flashing, install the ReSukiSU **manager APK** from its
[official releases](https://github.com/ReSukiSU/ReSukiSU/releases) to manage root.
SUSFS itself is configured from userspace with the `susfs` binary or a manager
that supports it; the kernel side only provides the mechanism.

## Issues you have to work around

These two will break the build if left unhandled. Both are environment/tree problems,
not bugs in the kernel code.

### Issue 1: the host linker

Proton Clang's `bin/` directory ships binutils 2.36 under generic names
(`ld`, `as`, `ar`, `nm`, `objcopy`, …). Putting it **first** on `PATH` shadows the
system binutils, and linking the **host tools** fails:

```
ld: /lib/x86_64-linux-gnu/libc.so.6: unknown type [0x13] section `.relr.dyn'
ld: cannot find /lib/x86_64-linux-gnu/libc.so.6
clang-13: error: linker command failed with exit code 1
make[2]: *** [scripts/Makefile.host:102: scripts/basic/fixdep] Error 1
```

`ld` 2.36 does not yet understand the `.relr.dyn` (DT_RELR) section used by modern glibc.

**Fix** — put the toolchain **last** on `PATH` and leave `HOSTCC` at its default (gcc):

```bash
export PATH="$PATH:$TC_DIR/bin"
```

This is safe because `clang`, `ld.lld` and `llvm-*` have unique names and are still
picked up from the toolchain, while the generic `ld`/`as` fall through to the newer
system binutils. Do not set `HOSTCC=clang`.

### Issue 2: the in-tree dtc is too old

`surya-sdmmagpie-overlay.dts` is an overlay (`/plugin/;`) that references labels
belonging to the base dtb. The in-tree `scripts/dtc` has no *orphan node* support, so
unresolved references are treated as hard errors:

```
Error: surya-sdmmagpie-overlay.dts:31.1-5 Label or path soc not found
Error: surya-sdmmagpie-overlay.dts:53.1-6 Label or path tlmm not found
FATAL ERROR: Syntax error parsing input tree
make[3]: *** [scripts/Makefile.dtbo:24: ...surya-sdmmagpie-overlay.dtbo] Error 1
```

In `scripts/dtc/dtc-parser.y`, the `devicetree DT_REF nodedef` rule calls `ERROR(...)`
directly when `get_node_by_ref()` fails, without the `add_orphan_node()` path that
modern dtc has.

**Fix** — use the system dtc through `DTC_EXT` (supported by `scripts/Makefile.lib`):

```bash
make ... DTC_EXT=/usr/bin/dtc
```

When `DTC_EXT` is set, Kbuild also skips the duplicated `-Wno-*` flags that modern dtc
does not recognise, so no further adjustment is needed.

## Verification status

What has been verified:

- The build completes with no errors and **0 warnings**.
- `Image.gz` — valid gzip, ~19 MB.
- `dtb` — valid FDT (magic `0xd00dfeed`), ~548 KB.
- `dtbo.img` — valid `dt_table` (magic `0xd7b7ab1e`), 1 entry, ~2 KB.

The resulting version string looks like:

```
4.14.357-openela-Stormbreaker-g<short SHA of HEAD>
```

`CONFIG_LOCALVERSION_AUTO=y` appends the short SHA of the commit that was built, so the
version string identifies the exact source state on the device.

> **Not boot-tested by this repo's tooling.** Verification stops at "clean compile +
> valid artifacts". Back up the `boot` and `dtbo` partitions before flashing.

## Flashing

1. Back up `boot` and `dtbo` (e.g. through TWRP).
2. Flash the zip from a custom recovery, or `adb sideload <zip>`.
3. Reboot. Check with `uname -r` — it should show the version string above.

If it fails to boot, restore the `boot` and `dtbo` backups.

## Upstream merge history

Merge of `LineageOS/android_kernel_qcom_sm8150:lineage-20` into `seventeen`
(commit [`d9caf04`](https://github.com/rigaz29/kernel_xiaomi_surya/commit/d9caf04a842628a259f1da20b6afbc4235007d70)):
41 upstream commits (21 new, 20 previously cherry-picked), 33 files, +63/−98.

Contents: the `clone3()` backport series, `CAP_CHECKPOINT_RESTORE`, a CFI fix in
rmnet shs, coresight dts cleanups, NFC I2C retries, and `__user` annotation fixes in TCP.

The five conflicts and how they were resolved:

| File | Taken from | Reason |
|---|---|---|
| `arch/x86/entry/syscalls/syscall_32.tbl` | upstream | `compat_sys_clone3` is not defined in this tree (clone3 is only a `SYSCALL_DEFINE2`), so `__ia32_sys_clone3` is correct |
| `arch/x86/ia32/sys_ia32.c` | upstream | `compat_sys_x86_waitpid()` really was removed upstream |
| `arch/x86/include/asm/sys_ia32.h` | combined | two removals at once: the waitpid prototype (upstream) plus `sys32_vm86_warning` (local) |
| `drivers/nfc/nq-nci.c` | local | identical retry logic; the local version logs both `ret` and `retry_cnt` |
| `kernel/fork.c` | local | the local `_do_fork` is only an early-return refactor with identical semantics; other upstream changes in the file are retained |

## Credits and licensing

- Kernel source: LineageOS, Qualcomm, Xiaomi — GPL-2.0.
- [AnyKernel3](https://github.com/osm0sis/AnyKernel3) by osm0sis — licence in `anykernel/LICENSE`.
- `tools/mkdtboimg.py` from [AOSP libufdt](https://android.googlesource.com/platform/system/libufdt/) — Apache-2.0.
- [Proton Clang](https://github.com/kdrag0n/proton-clang) by kdrag0n.

The scripts in this repo (`build.sh`, `package.sh`) follow GPL-2.0, same as the kernel.
