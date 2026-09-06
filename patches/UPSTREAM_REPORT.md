### Title

`HIDE_KSU_SUSFS_SYMBOLS` is prefix-only, so it leaks susfs's own `__func__.susfs_*` symbols in /proc/kallsyms

### Summary

The `CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS` filter in `kernel/kallsyms.c`
matches symbol names with `susfs_starts_with()`, i.e. **prefix only**. Any
susfs/ksu symbol whose name does not *begin* with one of the listed prefixes is
still printed. The most clear-cut case is susfs failing to hide itself: the
`__func__.susfs_*` string symbols emitted by susfs's own `SUSFS_LOGI/LOGE`
macros (`fs/susfs.c`) stay visible, because their kallsyms name starts with
`__func__.`, not `susfs_`.

A root detector reading `/proc/kallsyms` can use these as a susfs signal.

### Where

Filter is in the kallsyms hunk of the add-susfs patch (in the GKI branches,
`50_add_susfs_in_gki-android12-5.10.patch`; the block is byte-identical across
the branches I checked). The condition is the `susfs_starts_with(iter->name, …)`
chain guarded by `#ifdef CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS`.

### Observed

Verified on a running kernel (4.14 non-GKI, via the JackA1ltman
`susfs_patch_to_4.14.patch` backport, susfs `v2.3.0`, `HIDE_KSU_SUSFS_SYMBOLS=y`,
`ENABLE_LOG=y`, `kptr_restrict=2`). The line numbers/backport differ from the GKI
tree, but the filter block is identical, so this is not port damage.

18 susfs/ksu symbols remain in `/proc/kallsyms`. The 9 that are unambiguously
susfs's own:

```
__func__.susfs_init
__func__.susfs_show_version
__func__.susfs_show_variant
__func__.susfs_is_inode_sus_path
__func__.susfs_start_sdcard_monitor_fn
__func__.susfs_open_redirect_spoof_do_proc_readlink
__func__.susfs_open_redirect_spoof_show_map_vma_srcu
__func__.susfs_open_redirect_spoof_vfs_statfs
__func__.ksu_handle_umount
```

These come straight from `SUSFS_LOGI/LOGE` in `fs/susfs.c` and are present
whenever `ENABLE_LOG=y` and the compiler emits `__func__` for those functions —
independent of which KSU driver is used.

The other 9 are driver symbols that likewise embed rather than prefix the name
(`anon_ksu_{fops,ioctl,release}`, `do_ksu_load_allow_list`, `is_ksud_exists`,
`is_task_ksu_domain`, `setup_ksu_cred`, `setup_ksu_cred_selinux`,
`check_nnp_nosuid.ksu_sid`). Names vary by driver; the `__func__.susfs_*` set
above does not.

Addresses are `0` here because `kptr_restrict=2`, so this is a *name* leak, not
an address leak.

### Suggested fix

Add substring matching ahead of the existing prefix list:

```c
if (strstr(iter->name, "_ksu") ||
    strstr(iter->name, ".ksu") ||
    strstr(iter->name, "susfs") ||
    susfs_starts_with(iter->name, "ksu_") ||
    /* … keep the rest of the existing prefix list … */
```

Rationale for the exact anchors:

- Matching bare `"ksu"` would also hit `checksum`/`chksum` and hide ~60
  unrelated symbols (`skb_checksum`, `nf_ip_checksum`, `f2fs_inode_chksum`,
  `exfat_calc_chksum16`, …). Their absence is itself a detectable anomaly, so
  `"_ksu"` and `".ksu"` are used instead.
- `strstr(name, "susfs")` covers the `__func__.susfs_*` self-leak and any future
  susfs symbol regardless of prefix.
- The existing `susfs_starts_with()` entries must stay: names like `ksud`,
  `kernelsu`, `getenforce`, `setenforce`, `try_umount`, `is_zygote` contain
  neither `"ksu"` nor `"susfs"` and would otherwise be dropped.

On the running kernel this took the 18 leaked names to 0 while touching 0 of the
~60 checksum symbols (both counts grepped from `/proc/kallsyms` before/after).

`<linux/string.h>` needs to be included for `strstr()` if the file does not
already pull it in.
