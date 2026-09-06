# Optional patches

Standalone patches that are **not** part of the default build. Apply them by
hand against the kernel tree before running `../build.sh`.

```bash
cd ~/surya/kernel_xiaomi_surya
patch -p1 < ~/surya/surya-kernel-build/patches/<file>.patch
```

Each patch header explains what it does and why. To reverse:

```bash
patch -p1 -R < ~/surya/surya-kernel-build/patches/<file>.patch
```

## 0001 — hide the ksu/susfs symbols SUSFS's prefix filter misses

`kernel/kallsyms.c`. SUSFS's `CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS` filter
only matches symbol names by **prefix** (`susfs_starts_with()`), so 18 KSU/SUSFS
symbols still show up in `/proc/kallsyms` on this tree — including the nine
`__func__.susfs_*` strings that SUSFS's own logging macros emit. A root detector
reading `/proc/kallsyms` can find these.

The patch adds substring matching (`strstr` on `"_ksu"`, `".ksu"`, `"susfs"`) in
front of the existing prefix list. It avoids a bare `"ksu"` on purpose, since
that also matches `checksum`/`chksum` and would hide ~60 legitimate symbols.

Both counts (18 leaked symbols → 0, checksum symbols untouched) were verified
against the running kernel's `/proc/kallsyms`. This is an upstream-SUSFS
limitation, not specific to this port; the same filter ships unchanged in
SUSFS's maintained GKI branches.

Left as an optional patch rather than folded into the tree because it changes
hiding behaviour that some users may want to audit or tune first. Applying it
requires a rebuild.

The root cause is upstream SUSFS, so the fix belongs there too. A ready-to-file
bug report is in [`UPSTREAM_REPORT.md`](UPSTREAM_REPORT.md), targeting
[`simonpunk/susfs4ksu`](https://gitlab.com/simonpunk/susfs4ksu) on GitLab (its
issue tracker is active; no duplicate exists as of this writing).
