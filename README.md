# y700-mutter-fixes

Lenovo Y700（TB323FU / SM8850）上 Ubuntu 26.04 arm64、Mutter 50.1 的本地修复。

目标：修掉窗口过渡时的 `Page flip failed: drmModeAtomicCommit: EINVAL`，同时保留已有的触摸 resize 防崩补丁。

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

## 产物

`artifacts/`（Git LFS）：

- `libmutter-18-0_50.1-0ubuntu2.5+y7001_arm64.deb`
- `gir1.2-mutter-18_50.1-0ubuntu2.5+y7001_arm64.deb`
- `libmutter-18-0-dbgsym_50.1-0ubuntu2.5+y7001_arm64.ddeb`
- `mutter_50.1-0ubuntu2.5+y7001_arm64.buildinfo`
- `mutter_50.1-0ubuntu2.5+y7001_arm64.changes`
- `SHA256SUMS`

目标环境：Ubuntu 26.04 (resolute) arm64，Mutter 50.1-0ubuntu2.5。

## 构建

在 arm64 Ubuntu 26.04 chroot/机器里：

```bash
sudo apt-get update
sudo apt-get build-dep -y mutter
./scripts/build.sh
```

`build.sh` 会 `apt-get source mutter=50.1-0ubuntu2.5`、按顺序应用 `patches/*.patch`、`dpkg-buildpackage -b -nc -uc -us`，并把 deb 复制到 `artifacts/`。需要 `deb-src` 源。

从 x86_64 主机使用现有 chroot：

```bash
CHROOT=/path/to/arm64-chroot ./scripts/build-in-chroot.sh
```

`build-in-chroot.sh` 只做 bind mount 和 `chroot`，不会创建 chroot；chroot 里需要先装好 build-deps。

## 安装

```bash
sudo apt-get install -y --allow-change-held-packages \
  ./libmutter-18-0_50.1-0ubuntu2.5+y7001_arm64.deb \
  ./gir1.2-mutter-18_50.1-0ubuntu2.5+y7001_arm64.deb
sudo dpkg -i ./libmutter-18-0-dbgsym_50.1-0ubuntu2.5+y7001_arm64.ddeb
sudo apt-mark hold libmutter-18-0
sudo systemctl restart gdm3   # 不是重启设备；会关闭当前会话
```

## 验证

```bash
sudo sh -c 'echo 0x1e > /sys/module/drm/parameters/debug'
# 开合一个 GTK 窗口（Nautilus / Text Editor 等）
sudo journalctl -k --since '30 seconds ago' | grep -E 'invalid damage clip|vblank timeout'
sudo sh -c 'echo 0 > /sys/module/drm/parameters/debug'
```

预期：没有 `invalid damage clip`，`Page flip failed` 为 0。

## 未修复

DPU 的 `vblank timeout: 400000`（flush bit 22 = DSC）是独立的 164Hz/DSC 驱动问题，本仓库不包含内核修复。

## License

Mutter 是 GPL-2.0-or-later；补丁和构建脚本同样按 GPL-2.0-or-later 发布，见 `COPYING`。
