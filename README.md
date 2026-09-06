# surya-kernel-build

Perkakas dan dokumentasi untuk membangun kernel **Xiaomi Poco X3 NFC (`surya`)** dari
[`rigaz29/kernel_xiaomi_surya`](https://github.com/rigaz29/kernel_xiaomi_surya)
dan mengemasnya menjadi zip [AnyKernel3](https://github.com/osm0sis/AnyKernel3) yang bisa di-flash.

Repo ini **tidak** berisi source kernel — hanya resep build, skrip, dan tools.

| | |
|---|---|
| Perangkat | Xiaomi Poco X3 NFC (`surya`, juga `karna`) |
| SoC | Qualcomm SM7150 / `sdmmagpie` (tree `sm8150`) |
| Kernel | Linux 4.14.357 (ELTS / OpenELA) |
| Source | [`rigaz29/kernel_xiaomi_surya`](https://github.com/rigaz29/kernel_xiaomi_surya), branch `seventeen` |
| Upstream | [`LineageOS/android_kernel_qcom_sm8150`](https://github.com/LineageOS/android_kernel_qcom_sm8150), branch `lineage-20` |

## Isi repo

```
build.sh            # konfigurasi + kompilasi kernel
package.sh          # rakit zip AnyKernel3 dari hasil build
anykernel/          # AnyKernel3 yang sudah dikonfigurasi untuk surya
tools/mkdtboimg.py  # pembuat dtbo.img (AOSP libufdt)
```

Toolchain (Proton Clang, ±1.6 GB) sengaja tidak ikut di-commit; `build.sh` mengunduhnya
otomatis saat pertama dijalankan.

## Prasyarat

Diuji di Ubuntu 24.04 (glibc 2.39, binutils 2.42):

```bash
sudo apt install -y git make zip python3 device-tree-compiler \
                    build-essential libssl-dev bc bison flex
```

`device-tree-compiler` **wajib** — lihat [Kendala 2](#kendala-2-dtc-in-tree-terlalu-tua).

## Cara pakai

```bash
git clone https://github.com/rigaz29/kernel_xiaomi_surya.git ~/surya/kernel_xiaomi_surya
git clone https://github.com/rigaz29/surya-kernel-build.git ~/surya/surya-kernel-build

cd ~/surya/surya-kernel-build
./build.sh        # unduh toolchain (sekali), defconfig, kompilasi
./package.sh      # hasilkan release/Stormbreaker-surya-<versi>-<tanggal>.zip
```

Variabel yang bisa di-override: `KERNEL_DIR`, `TC_DIR`, `DEFCONFIG`, `JOBS`, `DTC_EXT`, `DEST`.

```bash
KERNEL_DIR=/path/ke/kernel JOBS=8 ./build.sh
```

## Toolchain

| Komponen | Versi |
|---|---|
| Compiler | Proton Clang 13.0.0 ([`kdrag0n/proton-clang`](https://github.com/kdrag0n/proton-clang)) |
| Linker (target) | LLD 13.0.0 |
| Linker (host) | binutils sistem (2.42) |
| Binutils cross | `aarch64-linux-gnu-`, `arm-linux-gnueabi-` |
| dtc | dtc sistem 1.7.0 (**bukan** `scripts/dtc` in-tree) |

Clang 13 dipilih karena cocok dengan kernel 4.14 yang memakai ThinLTO + Shadow Call Stack.
Clang yang jauh lebih baru sering menolak kode kernel seusia ini. Perlu dicatat: build resmi
Stormbreaker kemungkinan memakai Clang lain, jadi biner hasil repo ini **tidak akan identik byte-per-byte**.

## Konfigurasi kernel yang relevan

Dari `arch/arm64/configs/surya_defconfig`:

| Opsi | Nilai | Dampak |
|---|---|---|
| `CONFIG_LTO_CLANG` / `CONFIG_THINLTO` | `y` | butuh `ld.lld` (Makefile memakai `--thinlto-cache-dir`) |
| `CONFIG_SHADOW_CALL_STACK` | `y` | butuh Clang dengan dukungan SCS arm64 |
| `CONFIG_CFI_CLANG` | tidak diset | — |
| `CONFIG_BUILD_ARM64_DT_OVERLAY` | `y` | build menghasilkan `.dtbo`, `DTC_FLAGS := -@` |
| `CONFIG_BUILD_ARM64_APPENDED_DTB_IMAGE` | **tidak diset** | output `Image.gz` polos, **bukan** `Image.gz-dtb` |
| `CONFIG_LOCALVERSION` | `-Stormbreaker` | masuk ke string versi kernel |

## Artefak dan cara AnyKernel3 memakainya

| File di zip | Sumber | Peran |
|---|---|---|
| `Image.gz` | `out/arch/arm64/boot/Image.gz` | kernel; ditulis ke boot image |
| `dtb` | `out/.../qcom/surya-sdmmagpie.dtb` | menggantikan bagian dtb di boot image (surya: boot header v2) |
| `dtbo.img` | dibuat dari `surya-sdmmagpie-overlay.dtbo` | di-flash ke partisi `dtbo` oleh `write_boot` |

`dtb` dan `dtbo.img` dibangun dari source yang sama dengan kernelnya, jadi konsisten
(merge upstream terakhir memang mengubah dts: referensi coresight dan region
`disp_rdump_memory`). Kalau Anda lebih suka mempertahankan bawaan perangkat,
hapus saja kedua file itu dari zip — AnyKernel3 otomatis memakai yang lama.

Konfigurasi `anykernel/anykernel.sh`:

```
device.name1=surya
device.name2=karna
BLOCK=/dev/block/bootdevice/by-name/boot
IS_SLOT_DEVICE=0        # surya non-A/B
do.devicecheck=1
```

## Kendala yang harus diatasi

Dua hal ini membuat build gagal kalau tidak ditangani. Keduanya adalah masalah
lingkungan/tree, bukan bug di kode kernelnya.

### Kendala 1: host linker

Direktori `bin/` Proton Clang berisi binutils 2.36 dengan nama generik
(`ld`, `as`, `ar`, `nm`, `objcopy`, …). Kalau ditaruh di **depan** `PATH`, tool itu
menaungi binutils sistem, dan proses link **host tool** gagal:

```
ld: /lib/x86_64-linux-gnu/libc.so.6: unknown type [0x13] section `.relr.dyn'
ld: cannot find /lib/x86_64-linux-gnu/libc.so.6
clang-13: error: linker command failed with exit code 1
make[2]: *** [scripts/Makefile.host:102: scripts/basic/fixdep] Error 1
```

`ld` 2.36 belum mengenal section `.relr.dyn` (DT_RELR) yang dipakai glibc modern.

**Solusi** — taruh toolchain di **akhir** `PATH` dan biarkan `HOSTCC` default (gcc):

```bash
export PATH="$PATH:$TC_DIR/bin"
```

Aman karena `clang`, `ld.lld`, dan `llvm-*` namanya unik sehingga tetap terambil
dari toolchain, sedangkan `ld`/`as` generik jatuh ke binutils sistem yang baru.
Jangan set `HOSTCC=clang`.

### Kendala 2: dtc in-tree terlalu tua

`surya-sdmmagpie-overlay.dts` adalah overlay (`/plugin/;`) yang mereferensi label
milik base dtb. `scripts/dtc` di tree ini belum punya dukungan *orphan node*, jadi
referensi yang belum terselesaikan langsung dianggap error:

```
Error: surya-sdmmagpie-overlay.dts:31.1-5 Label or path soc not found
Error: surya-sdmmagpie-overlay.dts:53.1-6 Label or path tlmm not found
FATAL ERROR: Syntax error parsing input tree
make[3]: *** [scripts/Makefile.dtbo:24: ...surya-sdmmagpie-overlay.dtbo] Error 1
```

Di `scripts/dtc/dtc-parser.y`, aturan `devicetree DT_REF nodedef` langsung memanggil
`ERROR(...)` bila `get_node_by_ref()` gagal, tanpa jalur `add_orphan_node()` yang ada
pada dtc modern.

**Solusi** — pakai dtc sistem lewat `DTC_EXT` (didukung `scripts/Makefile.lib`):

```bash
make ... DTC_EXT=/usr/bin/dtc
```

Saat `DTC_EXT` diset, Kbuild juga melewatkan flag `-Wno-*` duplikat yang tidak
dikenali dtc modern, jadi tidak ada penyesuaian lain yang diperlukan.

## Status verifikasi

Yang sudah diverifikasi:

- Kompilasi selesai tanpa error dan **0 warning**.
- `Image.gz` — gzip valid, 19.0 MB.
- `dtb` — FDT valid (magic `0xd00dfeed`), 547.8 KB.
- `dtbo.img` — `dt_table` valid (magic `0xd7b7ab1e`), 1 entry, 2.1 KB.

Versi hasil build:

```
4.14.357-openela-Stormbreaker-ge06f4b592084
```

Sufiks `ge06f4b592084` adalah commit merge upstream, jadi versi kernel langsung
menunjukkan isi build-nya.

> **Belum diuji boot pada perangkat.** Verifikasi berhenti di "kompilasi bersih +
> artefak valid". Backup partisi `boot` dan `dtbo` sebelum flash.

## Cara flash

1. Backup `boot` dan `dtbo` (mis. lewat TWRP).
2. Flash zip lewat custom recovery, atau `adb sideload <zip>`.
3. Reboot. Cek dengan `uname -r` — harus muncul string versi di atas.

Kalau gagal boot, restore backup `boot` dan `dtbo`.

## Riwayat merge upstream

Merge `LineageOS/android_kernel_qcom_sm8150:lineage-20` ke `seventeen`
(commit [`e06f4b5`](https://github.com/rigaz29/kernel_xiaomi_surya/commit/e06f4b592084)):
41 commit upstream (21 baru, 20 sudah pernah di-cherry-pick), 33 file, +63/−98.

Isi: seri backport `clone3()`, `CAP_CHECKPOINT_RESTORE`, perbaikan CFI di rmnet shs,
pembersihan dts coresight, retry I2C NFC, perbaikan anotasi `__user` di TCP.

Lima konflik dan resolusinya:

| File | Diambil | Alasan |
|---|---|---|
| `arch/x86/entry/syscalls/syscall_32.tbl` | upstream | `compat_sys_clone3` tidak terdefinisi di tree ini (clone3 hanya `SYSCALL_DEFINE2`), jadi `__ia32_sys_clone3` yang benar |
| `arch/x86/ia32/sys_ia32.c` | upstream | `compat_sys_x86_waitpid()` memang dihapus upstream |
| `arch/x86/include/asm/sys_ia32.h` | gabungan | dua penghapusan sekaligus: prototipe waitpid (upstream) + `sys32_vm86_warning` (lokal) |
| `drivers/nfc/nq-nci.c` | lokal | logika retry identik; versi lokal mencatat `ret` dan `retry_cnt` |
| `kernel/fork.c` | lokal | `_do_fork` lokal hanya refactor early-return, semantik identik; perubahan upstream lain di file ini tetap masuk |

## Kredit dan lisensi

- Kernel source: LineageOS, Qualcomm, Xiaomi — GPL-2.0.
- [AnyKernel3](https://github.com/osm0sis/AnyKernel3) oleh osm0sis — lisensi ada di `anykernel/LICENSE`.
- `tools/mkdtboimg.py` dari [AOSP libufdt](https://android.googlesource.com/platform/system/libufdt/) — Apache-2.0.
- [Proton Clang](https://github.com/kdrag0n/proton-clang) oleh kdrag0n.

Skrip di repo ini (`build.sh`, `package.sh`) mengikuti GPL-2.0 seperti kernelnya.
