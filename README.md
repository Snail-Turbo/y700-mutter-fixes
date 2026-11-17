# y700-mutter-fixes

**English TL;DR** — Downstream Mutter 50.1 patches for the Lenovo Y700 (TB323FU, SM8850) on
Ubuntu 26.04 arm64: clamp KMS damage clips (fixes `Page flip failed: drmModeAtomicCommit: EINVAL`
caused by `invalid damage clip x1=-1`) and keep the touch `focus_surface == NULL` guard.
Prebuilt arm64 packages are attached to [Releases](../../releases); this repository carries only
the patches and build scripts. Unofficial, device- and version-specific — use at your own risk.

---

Lenovo Y700（TB323FU / SM8850）上 Ubuntu 26.04 arm64、Mutter 50.1 的下游修复。

目标：修掉窗口过渡时的 `Page flip failed: drmModeAtomicCommit: EINVAL`，同时保留已有的触摸 resize 防崩补丁。

## 适用范围

| 项 | 要求 |
|---|---|
| 设备 | Lenovo Y700 TB323FU（SM8850 / Adreno 840） |
| 系统 | Ubuntu 26.04 (resolute) arm64 |
| Mutter | **50.1-0ubuntu2.5**（`dpkg -s libmutter-18-0 \| grep ^Version`） |

包名带 `+y7001`，版本基线精确到 `50.1-0ubuntu2.5`。别的 mutter 版本补丁打不上，二进制也不保证 ABI 兼容。

## 根因

Mutter 的 `meta_kms_plane_assignment_set_fb_damage()` 直接把 damage region 的矩形复制成 `drm_mode_rect`，没有 clamp 到 framebuffer。1.333 分数缩放 + 面板旋转 + 窗口贴左边缘时，damage 会带 `x1 = -1`；内核 `drm_atomic_plane_check()` 对 `clips->x1 < 0` 返回 `-EINVAL`（`drivers/gpu/drm/drm_atomic.c`），整帧被丢弃。

实测日志（`drm.debug=0x1e`）：

```text
[PLANE:49:plane-0] invalid damage clip -1 1584 948 3012
[PLANE:49:plane-0] invalid damage clip -1 0 968 1342
```

与两次 `Page flip failed` 一一对应。

## 修复

- `patches/0001-mutter-kms-clamp-damage-clips.patch`
  - 在 `meta_kms_plane_assignment_set_fb_damage()` 里用 buffer 的宽高把每个 rect clamp 到 `[0, fb_width] × [0, fb_height]`，丢弃空 rect；全部为空则不下发 `FB_DAMAGE_CLIPS`。
- `patches/0002-mutter-wayland-touch-null-focus-surface.patch`
  - 保留 Y700 原有的触摸防崩补丁：`touch_can_grab_surface()` 在 `focus_surface == NULL` 时返回 FALSE。**不能丢**，否则 gnome-shell 在触摸 resize GTK 窗口时会 SIGSEGV。
- `patches/0003-debian-changelog.patch`
  - 版本 `50.1-0ubuntu2.5+y7001`。

## 安装（用 Release 里的包）

二进制不进 git，全部在 [Releases](../../releases) 里：

```bash
# 1. 下载某个 release 的全部 assets 到同一个目录，然后校验
sha256sum -c SHA256SUMS

# 2. 安装
sudo apt-get install -y --allow-change-held-packages \
  ./libmutter-18-0_50.1-0ubuntu2.5+y7001_arm64.deb \
  ./gir1.2-mutter-18_50.1-0ubuntu2.5+y7001_arm64.deb

# 3. 调试符号（可选）
sudo dpkg -i ./libmutter-18-0-dbgsym_50.1-0ubuntu2.5+y7001_arm64.ddeb

# 4. 防升级覆盖
sudo apt-mark hold libmutter-18-0 gir1.2-mutter-18

# 5. 生效（会关闭当前会话，不是重启设备）
sudo systemctl restart gdm3
```

## 验证

```bash
sudo sh -c 'echo 0x1e > /sys/module/drm/parameters/debug'
# 开合一个 GTK 窗口（Nautilus / Text Editor 等），然后：
sudo journalctl -k --since '30 seconds ago' | grep 'invalid damage clip'
sudo sh -c 'echo 0 > /sys/module/drm/parameters/debug'
```

预期：没有 `invalid damage clip`，`Page flip failed` 为 0。

## 回滚

```bash
sudo apt-mark unhold libmutter-18-0 gir1.2-mutter-18
sudo apt-get install --allow-downgrades \
  libmutter-18-0=50.1-0ubuntu2.5 gir1.2-mutter-18=50.1-0ubuntu2.5
sudo systemctl restart gdm3
```

如果官方源已经前进到更高版本，直接 `sudo apt-get install libmutter-18-0` 也会回到官方版本（`+y7001` 只比 Ubuntu 版本多一个后缀，不会被自动覆盖）。

## 与上游的关系

- `0001` 和 **GNOME MR !5203** 是同类问题。上游已经在 `main` 和 `gnome-50` 分支用另一种方式修复
  （stage-impl clamp + `g_warn_if_fail`）。本仓库只是 Ubuntu 50.1 的下游 backport，
  **不打算重复提交上游**。
- `0002` 是本设备的下游补丁（`focus_surface == NULL`），上游没有对应上下文。

## 构建

在 arm64 Ubuntu 26.04 chroot/机器里：

```bash
sudo apt-get update
sudo apt-get build-dep -y mutter
./scripts/build.sh
```

`build.sh` 会 `apt-get source mutter=50.1-0ubuntu2.5`、按顺序应用 `patches/*.patch`、`dpkg-buildpackage -b -nc -uc -us`，并把 deb 复制到 `artifacts/`（该目录已被 `.gitignore` 忽略）。需要 `deb-src` 源。

从 x86_64 主机使用现有 chroot：

```bash
CHROOT=/path/to/arm64-chroot ./scripts/build-in-chroot.sh
```

`build-in-chroot.sh` 只做 bind mount 和 `chroot`，不会创建 chroot；chroot 里需要先装好 build-deps。

## 目录结构

```text
patches/   三个补丁（按序应用）
scripts/   build.sh / build-in-chroot.sh
artifacts/ 构建输出，已 gitignore；正式产物见 Releases
COPYING    GPL-2.0
```

## 免责声明

非官方项目，与 Lenovo、Canonical、GNOME 无关。替换 `libmutter` 会影响整个桌面会话，
请自行承担风险；出问题按上面「回滚」一节退回官方版本。

## License

Mutter 是 GPL-2.0-or-later；补丁和构建脚本同样按 GPL-2.0-or-later 发布，见 `COPYING`。
