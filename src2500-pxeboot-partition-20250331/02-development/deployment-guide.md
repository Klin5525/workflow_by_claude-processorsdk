# SRC2500 PXE Boot 分区初始化 - 快速部署指南

**文档版本**: 1.0
**创建日期**: 2025-03-31
**适用范围**: SRC2500 板型 + Ubuntu 22.04 rootfs

---

## 快速开始

### 1. 构建固件

```bash
cd /home/linke/processor_sdk

# 切换到 SRC2500 配置
./build.sh chip rk3562
./build.sh config Seer_rk3562_ubuntu_src2500_defconfig

# 验证配置
grep "^CONFIG_" output/.config | grep -E "(RK_CHIP|RK_ROOTFS_SYSTEM|BOARD)"
# 预期输出:
# CONFIG_RK_CHIP=rk3562
# CONFIG_RK_ROOTFS_SYSTEM=ubuntu
# CONFIG_BOARD_TYPE=src2500

# 重新构建 rootfs（包含 pxeboot-init.sh）
./build.sh rootfs

# 生成最终固件
./build.sh firmware
```

### 2. 烧录固件

**使用 RKDevTool**:
1. 连接 SRC2500 设备到 USB
2. 进入 MaskROM 模式（按住 Recovery 键 + 复位）
3. 在 RKDevTool 中选择 `output/firmware/update.img`
4. 点击 "Upgrade"

**使用 dd 命令**（Linux）:
```bash
# 通过 SD 卡启动到 Ubuntu
# 卸载 eMMC 分区
umount /dev/mmcblk0*

# 烧录固件
dd if=update.img of=/dev/mmcblk0 bs=1M status=progress

# 同步并重启
sync
reboot
```

### 3. 首次启动验证

```bash
# SSH 登录到 SRC2500
ssh sr@192.168.192.7
# 密码: 123456

# 查看初始化日志
journalctl | grep -A 50 "PXE boot partition initialization"

# 验证分区
lsblk -o NAME,SIZE,PARTLABEL,MOUNTPOINT | grep -E "(NAME|pxe|log)"

# 验证挂载
mount | grep -E "(pxe|log)"

# 验证 systemd 单元
systemctl list-units '*.mount' | grep -E "(pxe|log)"
```

---

## 预期输出

### 分区表
```
NAME        SIZE TYPE  PARTLABEL      MOUNTPOINT
mmcblk0     119G disk
├─mmcblk0p1  16M  part  uboot
├─mmcblk0p2  256M part  boot           /boot
├─mmcblk0p3  4G   part  rootfs         /
├─mmcblk0p4  8G   part  userdata       /userdata
├─mmcblk0p5  2G   part  pxe_rootfs_a   /pxe_rootfs_a
├─mmcblk0p6  2G   part  pxe_rootfs_b   /pxe_rootfs_b
├─mmcblk0p7  28G  part  pxe_upper      /pxe_upper
└─mmcblk0p8  80G  part  log            /log
```

### 挂载点
```
/dev/mmcblk0p5 on /pxe_rootfs_a type ext4 (rw,relatime)
/dev/mmcblk0p6 on /pxe_rootfs_b type ext4 (rw,relatime)
/dev/mmcblk0p7 on /pxe_upper type ext4 (rw,relatime)
/dev/mmcblk0p8 on /log type ext4 (rw,relatime)
```

### systemd mount 单元
```
pxe\x2drootfs\x2da.mount   loaded active mounted /pxe_rootfs_a
pxe\x2drootfs\x2db.mount   loaded active mounted /pxe_rootfs_b
pxe\x2dupper.mount         loaded active mounted /pxe_upper
log.mount                  loaded active mounted /log
```

---

## 故障排查

### 问题 1: 分区未创建

**症状**: `lsblk` 看不到 pxe_ 开头的分区

**排查**:
```bash
# 检查初始化日志
journalctl | grep pxeboot

# 手动运行脚本
sudo /usr/local/bin/pxeboot-init.sh

# 检查错误
dmesg | grep -i mmc
```

### 问题 2: 分区未挂载

**症状**: `mount` 看不到 /pxe_rootfs_a

**排查**:
```bash
# 检查 mount 单元
systemctl status pxe\\x2drootfs\\x2da.mount

# 手动启动
systemctl start pxe\\x2drootfs\\x2da.mount

# 检查依赖
systemctl list-dependencies local-fs.target
```

### 问题 3: 重启后挂载丢失

**症状**: 首次启动正常，重启后分区未挂载

**排查**:
```bash
# 检查是否启用
systemctl is-enabled pxe\\x2drootfs\\x2da.mount

# 重新启用
systemctl enable pxe\\x2drootfs\\x2da.mount

# 检查 PARTLABEL
ls -la /dev/disk/by-partlabel/
```

---

## 下一步

### 配置 PXE 服务器

参考 `overlay-src2500/etc/dnsmasq.d/pxe-server.conf`：

```bash
# 编辑配置
sudo vim /etc/dnsmasq.d/pxe-server.conf

# 重启 dnsmasq
sudo systemctl restart dnsmasq

# 检查状态
sudo systemctl status dnsmasq
```

### 配置 NFS 导出

参考 `overlay-src2500/etc/exports`：

```bash
# 编辑导出配置
sudo vim /etc/exports

# 应用配置
sudo exportfs -ra

# 检查导出
showmount -e localhost
```

---

## 相关文档

- **架构设计**: `.ai_context/src2500-pxeboot-partition-20250331/01-architecture/design.md`
- **实现笔记**: `.ai_context/src2500-pxeboot-partition-20250331/02-development/implementation-notes.md`
- **验证清单**: `.ai_context/src2500-pxeboot-partition-20250331/02-development/validation-checklist.md`

---

**文档结束**
