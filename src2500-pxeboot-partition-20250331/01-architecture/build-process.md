# SRC2500 编译和部署流程

## 概述

本文档说明如何在 SRC2500 和 SRC3600 之间切换配置，以及如何仅重新编译 rootfs 而不重复编译 boot 和 kernel。

---

## 硬件配置说明

### 共用组件

SRC2500 和 SRC3600 共用以下组件：

| 组件 | 位置 | 说明 |
|------|------|------|
| **U-Boot** | `u-boot/arch/arm/dts/rk3562-src2500-3600.dts` | 共用设备树 |
| **U-Boot defconfig** | `u-boot/configs/rk3562_src2500_3600_defconfig` | 共用配置 |
| **Kernel** | `kernel-6.1/arch/arm64/boot/dts/rockchip/rk3562-src2500-3600.dts` | 共用设备树 |
| **Kernel defconfig** | `kernel-6.1/arch/arm64/configs/rk3562_src2500_3600_defconfig` | 共用配置 |

### 独立组件

| 板型 | 顶层 defconfig | Ubuntu overlay |
|------|---------------|---------------|
| **SRC2500** | `device/rockchip/.chips/rk3562/Seer_rk3562_ubuntu_src2500_defconfig` | `ubuntu22.04/overlay-src2500/` |
| **SRC3600** | `device/rockchip/.chips/rk3562/Seer_rk3562_ubuntu_src3600_defconfig` | `ubuntu22.04/overlay-src3600/` |

**结论**：切换板型时，只需要重新编译 rootfs，boot 和 kernel 可以复用。

---

## 切换到 SRC2500 配置

### 步骤 1: 切换芯片配置

```bash
cd /home/linke/processor_sdk

# 切换到 rk3562 芯片
./build.sh chip rk3562

# 验证芯片配置
grep "^CONFIG_RK_CHIP=" output/.config
# 预期输出: CONFIG_RK_CHIP="rk3562"
```

### 步骤 2: 选择 SRC2500 板型

```bash
# 配置 SRC2500 defconfig
./build.sh config Seer_rk3562_ubuntu_src2500_defconfig

# 验证板型配置
grep "^CONFIG_" output/.config | grep -E "(RK_CHIP|RK_ROOTFS_SYSTEM|BOARD)"
# 预期输出包含:
# CONFIG_RK_CHIP="rk3562"
# CONFIG_RK_ROOTFS_SYSTEM="ubuntu"
# CONFIG_BOARD="src2500"
```

### 步骤 3: 检查当前配置

```bash
# 查看完整的配置
make menuconfig

# 或直接查看配置文件
cat output/.config | grep -E "^(CONFIG_|RK_)"
```

---

## 编译流程

### 方案 A: 仅重新编译 rootfs（推荐）

**适用场景**：从 SRC3600 切换到 SRC2500（或反之）

```bash
# 1. 删除旧的 rootfs 镜像
rm -f ubuntu22.04/ubuntu-rk3562-src-lite-rootfs.img
rm -f ubuntu22.04/userdata.img

# 2. 重新编译 rootfs
./build.sh rootfs

# 编译输出:
# - ubuntu22.04/ubuntu-rk3562-src-lite-rootfs.img (约 600MB)
# - ubuntu22.04/userdata.img (32MB)

# 3. 打包最终固件
./build.sh firmware

# 最终固件: output/firmware/update.img
```

**时间估计**：
- rootfs 编译：约 5-10 分钟（取决于网络速度和 CPU）
- 固件打包：约 1-2 分钟

### 方案 B: 完整重新编译（不推荐）

**适用场景**：首次编译或需要更新 boot/kernel

```bash
# 完整编译所有组件
./build.sh

# 时间估计: 30-60 分钟
```

### 方案 C: 仅重新打包固件（最快）

**适用场景**：rootfs 已存在，只需重新打包

```bash
# 仅打包固件（不重新编译）
./build.sh firmware

# 时间估计: 1-2 分钟
```

---

## 验证编译结果

### 检查 rootfs 镜像

```bash
# 检查镜像文件是否存在
ls -lh ubuntu22.04/ubuntu-rk3562-src-lite-rootfs.img
ls -lh ubuntu22.04/userdata.img

# 检查镜像内容（可选）
unsquashfs -l ubuntu22.04/ubuntu-rk3562-src-lite-rootfs.img | head -20
```

### 检查固件包

```bash
# 检查最终固件
ls -lh output/firmware/update.img

# 查看固件内容（可选）
cd output/firmware
ln -s update.img update.img.ext4
mkdir tmp
sudo mount update.img.ext4 tmp/
ls tmp/
sudo umount tmp/
```

### 验证 overlay 内容

```bash
# 检查 SRC2500 特定的 overlay 文件
ls ubuntu22.04/overlay-src2500/

# 应包含:
# - etc/dnsmasq.d/pxe-server.conf
# - etc/exports
# - usr/local/bin/pxeboot-init.sh (待添加)
# - usr/lib/systemd/system/dnsmasq.service.d/override.conf
```

---

## 部署到设备

### 方法 A: 使用 RKDevTool（推荐）

```bash
# 1. 连接 SRC2500 设备到开发机
# 2. 进入 Maskrom 模式（按住恢复键，上电）
# 3. 使用 RKDevTool 烧录

# 烧录文件: output/firmware/update.img
# 分区表: device/rockchip/.chips/rk3562/parameter-ubuntu-src2500-3600.txt
```

### 方法 B: 使用 dd 命令（高级用户）

```bash
# 1. 挂载设备到开发机（通过 USB 或 SD 卡）
# 2. 备份当前分区表
dd if=/dev/mmcblk0 of=parttable_backup.bin bs=512 count=34

# 3. 烧录固件
dd if=output/firmware/update.img of=/dev/mmcblk0 bs=1M

# 4. 同步并重启
sync
reboot
```

---

## 从 SRC3600 切换到 SRC2500 的完整流程

### 场景：当前是 SRC3600，需要切换到 SRC2500

```bash
# 1. 备份当前配置
cp output/.config output/.config.src3600.bak

# 2. 切换到 SRC2500
./build.sh config Seer_rk3562_ubuntu_src2500_defconfig

# 3. 删除旧的 rootfs（避免混淆）
rm -f ubuntu22.04/ubuntu-rk3562-src-lite-rootfs.img
rm -f ubuntu22.04/userdata.img

# 4. 重新编译 rootfs
./build.sh rootfs

# 5. 验证 overlay 内容
ls ubuntu22.04/overlay-src2500/

# 6. 打包固件
./build.sh firmware

# 7. 部署到 SRC2500 设备
# (使用 RKDevTool 或其他工具)
```

---

## 从 SRC2500 切换回 SRC3600 的完整流程

### 场景：当前是 SRC2500，需要切换回 SRC3600

```bash
# 1. 备份当前配置
cp output/.config output/.config.src2500.bak

# 2. 切换到 SRC3600
./build.sh config Seer_rk3562_ubuntu_src3600_defconfig

# 3. 删除旧的 rootfs
rm -f ubuntu22.04/ubuntu-rk3562-src-lite-rootfs.img
rm -f ubuntu22.04/userdata.img

# 4. 重新编译 rootfs
./build.sh rootfs

# 5. 验证 overlay 内容
ls ubuntu22.04/overlay-src3600/

# 6. 打包固件
./build.sh firmware

# 7. 部署到 SRC3600 设备
```

---

## 常见问题

### Q1: 为什么要删除 rootfs 镜像而不是让 build.sh 自动检测？

**A**: build.sh 的依赖检测可能不够精确，删除镜像可以确保完全重新编译。

### Q2: 可以同时保留 SRC2500 和 SRC3600 的 rootfs 吗？

**A**: 可以，但需要手动管理：
```bash
# 重命名备份
mv ubuntu22.04/ubuntu-rk3562-src-lite-rootfs.img \
   ubuntu22.04/ubuntu-rk3562-src-lite-rootfs.src3600.img

# 恢复时使用
cp ubuntu22.04/ubuntu-rk3562-src-lite-rootfs.src3600.img \
   ubuntu22.04/ubuntu-rk3562-src-lite-rootfs.img
```

### Q3: boot 和 kernel 真的可以复用吗？

**A**: 是的，因为：
- 共用设备树：`rk3562-src2500-3600.dts`
- 共用 defconfig：`rk3562_src2500_3600_defconfig`
- 唯一差异是 Ubuntu overlay（在 rootfs 中）

### Q4: 如何确认 boot 和 kernel 已编译？

**A**: 检查输出文件：
```bash
# U-Boot
ls -lh u-boot/u-boot.bin
ls -lh u-boot/uboot.img

# Kernel
ls -lh kernel-6.1/arch/arm64/boot/Image
ls -lh kernel-6.1/arch/arm64/boot/dts/rockchip/rk3562-src2500-3600.dtb
```

### Q5: 编译失败怎么办？

**A**: 检查日志：
```bash
# 查看构建日志
cat output/log/build.log

# 查看错误信息
grep -i "error" output/log/build.log | tail -20

# 常见问题:
# - 网络问题（ubuntu-base 下载失败）
# - 磁盘空间不足
# - 权限问题（需要 sudo）
```

---

## 优化建议（待后续实施）

### 问题：每次切换都需要重新编译 rootfs（5-10 分钟）

### 可能的优化方案

**方案 1: 使用 Docker 容器隔离编译环境**
```bash
# 为每个板型创建独立的容器
docker build -t rk3562-src2500 .
docker build -t rk3562-src3600 .

# 保留两个容器的编译产物
```

**方案 2: 使用符号链接快速切换**
```bash
# 创建两个 rootfs 目录
ubuntu22.04/ubuntu-rk3562-src-lite-rootfs.src2500.img
ubuntu22.04/ubuntu-rk3562-src-lite-rootfs.src3600.img

# 使用符号链接切换
ln -sf ubuntu-rk3562-src-lite-rootfs.src2500.img \
       ubuntu-rk3562-src-lite-rootfs.img
```

**方案 3: 改进 build.sh 脚本**
```bash
# 在 build.sh 中添加智能检测
# 如果 overlay 没变，跳过 rootfs 编译
./build.sh rootfs --skip-unchanged
```

**方案 4: 使用 ccache 加速编译**
```bash
# 安装 ccache
sudo apt-get install ccache

# 配置环境变量
export CCACHE_DIR=/home/linke/.ccache
export PATH="/usr/lib/ccache:$PATH"
```

---

## 相关文档

- **架构设计**: `design.md` - 分区布局设计
- **对比分析**: `comparison.md` - SRC2500 vs SRC3600
- **风险评估**: `risk-mitigation.md` - 部署风险和缓解措施

---

**文档版本**: 1.0
**最后更新**: 2025-03-31
**作者**: Team Workflow - 架构师角色
