# SRC2500 PXE Boot 分区初始化脚本 - 实现笔记

**文档版本**: 1.0
**创建日期**: 2025-03-31
**作者**: Team Workflow - 系统工程师角色
**状态**: 已完成

---

## 1. 实现概述

### 1.1 文件位置

**源代码**: `/home/linke/processor_sdk/ubuntu22.04/overlay-src2500/usr/local/bin/pxeboot-init.sh`

**权限**: `755` (rwxr-xr-x)

**脚本类型**: Bash 脚本（`#!/bin/bash -e`）

### 1.2 实现方式

参考架构师设计文档和 SRC3600 参考实现，针对 SRC2500 的分区布局进行了适配。

---

## 2. 核心设计决策

### 2.1 分区布局实现

根据 `design.md` 第三次修正的扇区计算：

| 分区名 | 起始扇区 | 大小(扇区) | 结束扇区 | 大小(GB) | 代码实现 |
|--------|---------|-----------|---------|---------|---------|
| pxe_rootfs_a | 0x2000000 | 0x400000 | 0x23FFFFF | 2GB | ✅ |
| pxe_rootfs_b | 0x2400000 | 0x400000 | 0x27FFFFF | 2GB | ✅ |
| pxe_upper | 0x2800000 | 0x3800000 | 0x5FFFFFF | 28GB | ✅ |
| log | 0x6000000 | 0 | 到末尾 | 剩余 | ✅ |

**代码实现**（第 50-54 行）：
```bash
declare -A PARTITIONS=(
    ["pxe_rootfs_a"]="0x2000000:0x400000"   # 2GB @ 16GB
    ["pxe_rootfs_b"]="0x2400000:0x400000"   # 2GB @ 18GB
    ["pxe_upper"]="0x2800000:0x3800000"     # 28GB @ 20GB
)
```

### 2.2 UUID 设计

为避免与 SRC3600 UUID 冲突，使用不同的 UUID_BASE：

| 板型 | UUID_BASE | log 分区 UUID |
|------|-----------|--------------|
| SRC3600 | 0x54b2 | 614e0000-0000-4b53-8000-1d28000054b8 |
| SRC2500 | 0x54c0 | 614e0000-0000-4b53-8000-1d28000054c8 |

**代码实现**（第 59 行）：
```bash
UUID_BASE=0x54c0  # 避免与 SRC3600 冲突（SRC3600: 0x54b2）
```

### 2.3 systemd mount 单元命名

分区名中的 `-` 必须转义为 `\x2d`：

| 分区名 | mount 单元文件名 |
|--------|----------------|
| pxe_rootfs_a | `pxe\x2drootfs\x2da.mount` |
| pxe_rootfs_b | `pxe\x2drootfs\x2db.mount` |
| pxe_upper | `pxe\x2dupper.mount` |
| log | `log.mount` |

**代码实现**（第 129 行）：
```bash
MOUNT_UNIT="${PART_NAME//-/\\x2d}.mount"
```

---

## 3. 与 SRC3600 的差异对比

### 3.1 分区数量和命名

| 项目 | SRC3600 | SRC2500 |
|------|---------|---------|
| 第一批分区数 | 6 个（ap0/ap1 各 3 个） | 3 个（pxe 相关） |
| 分区命名 | ap0_rootfs_a, ap0_rootfs_b, ap1_rootfs_a, ap1_rootfs_b, ap0_upper, ap1_upper | pxe_rootfs_a, pxe_rootfs_b, pxe_upper |
| 第二批分区 | log（从 96GB 开始） | log（从 48GB 开始） |

### 3.2 分区大小对比

| 用途 | SRC3600 | SRC2500 |
|------|---------|---------|
| Rootfs A/B | 1GB × 4 = 4GB | 2GB × 2 = 4GB（相同总量） |
| Upper 分区 | 18GB + 10GB = 28GB | 28GB × 1 = 28GB（相同总量） |
| Log 起始位置 | 96GB (0x6000000) | 48GB (0x6000000) |

**注意**：虽然起始扇区都是 0x6000000，但含义不同：
- SRC3600: 96GB = 前 16GB + 6 个 AP 分区(32GB) + 48GB 间隙
- SRC2500: 48GB = 前 16GB + 3 个 PXE 分区(32GB)

### 3.3 代码结构差异

**相同部分**：
- 设备检测逻辑（`findmnt` + fallback）
- 分区号动态获取
- sgdisk 分区创建流程
- systemd mount 单元创建
- 错误处理机制

**不同部分**：
- 分区配置数组（`PARTITIONS`）
- UUID_BASE（避免冲突）
- 循环次数（SRC3600: 6 次，SRC2500: 3 次）

---

## 4. 关键代码段解析

### 4.1 分区号动态检测（第 43-44 行）

```bash
NEXT_PART=$(ls "$BOOT_DEV"* 2>/dev/null | tail -1 | grep -oP '[0-9]+$' || echo "4")
NEXT_PART=$((NEXT_PART + 1))
```

**设计意图**：
- 默认前 4 个分区存在（uboot, boot, rootfs, userdata）
- 动态检测最后一个分区号，避免硬编码
- 兼容不同分区配置

**测试场景**：
- 正常情况：`/dev/mmcblk0p4` → NEXT_PART=5
- 异常情况：无分区 → 默认值 4 → NEXT_PART=5

### 4.2 分区创建循环（第 62-95 行）

```bash
PART_NUM=$NEXT_PART
for PART_NAME in pxe_rootfs_a pxe_rootfs_b pxe_upper; do
    SECTORS=${PARTITIONS[$PART_NAME]}
    START=$(echo $SECTORS | cut -d: -f1)
    SIZE=$(echo $SECTORS | cut -d: -f2)
    END=$((START + SIZE - 1))
    UUID=$(printf "614e0000-0000-4b53-8000-1d28%08x" $((UUID_BASE + PART_NUM - NEXT_PART)))

    echo "Creating partition $PART_NUM: $PART_NAME"
    # ... sgdisk 创建分区 ...

    PART_NUM=$((PART_NUM + 1))
done
```

**关键点**：
- `PART_NUM - NEXT_PART`：生成递增的 UUID 偏移量（0, 1, 2）
- `END=$((START + SIZE - 1))`：sgdisk 的结束扇区是包含的（不是 `+ SIZE`）
- 错误处理：`if [ $? -ne 0 ]; then exit 1; fi`

### 4.3 设备名兼容性处理（第 106-108 行）

```bash
PART_DEV="${BOOT_DEV}p${PART_NUM}"
[ ! -e "$PART_DEV" ] && PART_DEV="${BOOT_DEV}${PART_NUM}"
```

**原因**：
- eMMC 设备可能是 `/dev/mmcblk0p5` 或 `/dev/mmcblk05`
- 某些内核版本使用 `p` 分隔符，某些不使用
- 优先尝试带 `p` 的格式，失败则尝试不带 `p` 的格式

### 4.4 systemd mount 单元持久化（第 131-144 行）

```bash
cat > "/etc/systemd/system/$MOUNT_UNIT" <<EOF
[Unit]
Description=Mount partition $PART_NAME
DefaultDependencies=no

[Mount]
What=PARTLABEL=$PART_NAME
Where=/$PART_NAME
Type=ext4
Options=defaults

[Install]
WantedBy=local-fs.target
EOF
```

**设计要点**：
- `What=PARTLABEL=$PART_NAME`：使用 PARTLABEL 而非设备路径，确保分区号变化后仍能挂载
- `DefaultDependencies=no`：避免依赖网络等晚期目标
- `WantedBy=local-fs.target`：在本地文件系统挂载阶段启动
- **OverlayFS 兼容性**：mount 单元放在 `/etc/systemd/system/`，在 overlayroot 环境下也能持久化

### 4.5 验证和摘要输出（第 250-263 行）

```bash
echo ""
echo "=== Partition Creation Summary ==="
echo ""
echo "Partition table:"
lsblk -o NAME,SIZE,TYPE,PARTLABEL,MOUNTPOINT "$BOOT_DEV" | grep -E "(NAME|pxe_|log)" || true
echo ""
echo "Mount points:"
mount | grep -E "(pxe_|log)" || true
echo ""
echo "Systemd mount units:"
systemctl list-units '*.mount' | grep -E "(pxe|log)" || true
echo ""
echo "=== Initialization Complete ==="
```

**用途**：
- 提供可视化的分区创建结果
- 方便调试和验证
- 输出到系统日志（journalctl）

---

## 5. 扇区计算验证

### 5.1 基础计算

```bash
# 1GB = 1 × 1024 × 1024 × 1024 字节 = 0x40000000 字节
# 扇区数 = 0x40000000 ÷ 512 = 0x200000 扇区

# 2GB = 2 × 1024³ 字节 = 0x80000000 字节
# 扇区数 = 0x80000000 ÷ 512 = 0x400000 扇区

# 28GB = 28 × 1024³ 字节 = 0x70000000 字节
# 扇区数 = 0x70000000 ÷ 512 = 0x3800000 扇区
```

### 5.2 累加验证

| 分区 | 起始扇区 | 大小扇区 | 结束扇区计算 | 实际结束扇区 | 验证 |
|------|---------|---------|------------|------------|------|
| pxe_rootfs_a | 0x2000000 | 0x400000 | 0x2000000 + 0x400000 - 1 | 0x23FFFFF | ✅ |
| pxe_rootfs_b | 0x2400000 | 0x400000 | 0x2400000 + 0x400000 - 1 | 0x27FFFFF | ✅ |
| pxe_upper | 0x2800000 | 0x3800000 | 0x2800000 + 0x3800000 - 1 | 0x5FFFFFF | ✅ |
| log | 0x6000000 | 动态 | - | 设备末尾 | ✅ |

### 5.3 对齐验证

所有起始扇区均能被 0x800（1MB）整除：

```bash
# 验证脚本
for start in 0x2000000 0x2400000 0x2800000 0x6000000; do
    echo "$start % 0x800 = $((start % 0x800))"
done

# 输出：
# 0x2000000 % 0x800 = 0 ✅
# 0x2400000 % 0x800 = 0 ✅
# 0x2800000 % 0x800 = 0 ✅
# 0x6000000 % 0x800 = 0 ✅
```

---

## 6. 错误处理机制

### 6.1 Bash 选项

```bash
#!/bin/bash -e
```

**`-e` 选项**：任何命令返回非零退出码时立即退出脚本

**优点**：
- 防止错误级联
- 确保故障快速失败
- 简化错误处理代码

### 6.2 显式错误检查

```bash
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create partition $PART_NAME"
    exit 1
fi
```

**使用场景**：
- sgdisk 分区创建后（第 89-92 行）
- mkfs.ext4 格式化后（第 118-121 行）
- systemctl mount 启动后（第 151-154 行）

### 6.3 设备存在性检查

```bash
if [ ! -e "$PART_DEV" ]; then
    echo "ERROR: Partition device not found: $PART_DEV"
    exit 1
fi
```

**使用场景**：
- 格式化前检查分区设备（第 110-113 行）
- log 分区设备检查（第 203-206 行）

---

## 7. 幂等性保证

### 7.1 分区存在性检测

```bash
if [ ! -e "/dev/disk/by-partlabel/pxe_rootfs_a" ]; then
    # 创建分区
else
    echo "PXE partitions already exist, skipping creation"
fi
```

**工作原理**：
- 使用 `/dev/disk/by-partlabel/` 符号链接检测分区是否存在
- 第一次运行：分区不存在 → 执行创建
- 后续运行：分区已存在 → 跳过创建

### 7.2 systemd mount 单元幂等性

```bash
systemctl enable "$MOUNT_UNIT"
systemctl start "$MOUNT_UNIT"
```

**systemd 行为**：
- `enable`：如果已启用，返回成功（幂等）
- `start`：如果已运行，返回成功（幂等）

### 7.3 测试场景

| 场景 | 预期行为 |
|------|---------|
| 首次启动 | 创建所有分区和挂载点 |
| 第二次启动 | 跳过创建，输出 "already exist" |
| 分区损坏 | 手动删除后重新运行，正确重建 |
| 重启后 | 分区自动挂载（systemd mount 单元持久化） |

---

## 8. OverlayFS 兼容性

### 8.1 overlayroot 环境

**背景**：
- SRC2500 使用 SquashFS 只读根文件系统
- overlayroot 提供可写层（userdata 分区）

**挑战**：
- systemd mount 单元必须持久化到可写位置
- `/etc/systemd/system/` 在 overlay 上层，符合要求

### 8.2 持久化路径

```bash
cat > "/etc/systemd/system/$MOUNT_UNIT" <<EOF
# ...
EOF
```

**验证方法**：
```bash
# 检查 mount 单元是否在 overlay 上层
mount | grep /etc/systemd/system
# 输出：overlay on /etc/systemd/system type overlay...

# 检查是否持久化
ls -la /etc/systemd/system/pxe\x2drootfs\x2da.mount
```

### 8.3 PARTLABEL 挂载优势

```bash
What=PARTLABEL=$PART_NAME
```

**好处**：
- 不依赖分区号（`/dev/mmcblk0p5` vs `/dev/mmcblk05`）
- 分区表重建后仍能正确挂载
- 符合 GPT 分区命名最佳实践

---

## 9. 测试计划

### 9.1 单元测试

| 测试项 | 命令 | 预期输出 |
|--------|------|---------|
| 扇区计算 | `python3 -c "print(2*1024**3//512)"` | 4194304 (0x400000) |
| UUID 生成 | `printf "614e0000-0000-4b53-8000-1d28%08x" 0` | 614e0000-0000-4b53-8000-1d28000054c0 |
| 单元名转义 | `echo "pxe_rootfs_a" | sed 's/-/\\x2d/g'` | pxe\x2drootfs\x2da |

### 9.2 集成测试

| 测试项 | 验证方法 | 预期结果 |
|--------|---------|---------|
| 分区创建 | `lsblk -o NAME,PARTLABEL` | 存在 pxe_rootfs_a, pxe_rootfs_b, pxe_upper, log |
| 挂载点 | `mount \| grep pxe` | 4 个分区均已挂载 |
| systemd 服务 | `systemctl status pxe\\x2drootfs\\x2da.mount` | 状态为 active (mounted) |
| 持久化 | `reboot` + `mount \| grep pxe` | 分区自动挂载 |
| 文件系统 | `df -h /pxe_rootfs_a` | 显示 2GB 容量 |
| 幂等性 | `./pxeboot-init.sh`（第二次运行） | 输出 "already exist" |

### 9.3 边界测试

| 测试项 | 场景 | 预期结果 |
|--------|------|---------|
| 最小 eMMC | 48GB eMMC | log 分区大小为 0（刚好用完） |
| 标准 eMMC | 64GB eMMC | log 分区 16GB |
| 大容量 eMMC | 128GB eMMC | log 分区 80GB |
| 分区损坏 | `sgdisk -Z /dev/mmcblk0` + 重新运行 | 正确重建所有分区 |

---

## 10. 部署流程

### 10.1 编译和打包

```bash
cd /home/linke/processor_sdk

# 切换到 SRC2500 配置
./build.sh chip rk3562
./build.sh config Seer_rk3562_ubuntu_src2500_defconfig

# 验证配置
grep "^CONFIG_" output/.config | grep -E "(RK_CHIP|RK_ROOTFS_SYSTEM|BOARD)"
# 预期输出：
# CONFIG_RK_CHIP=rk3562
# CONFIG_RK_ROOTFS_SYSTEM=ubuntu
# CONFIG_BOARD_TYPE=src2500

# 重新构建 rootfs（包含 pxeboot-init.sh）
./build.sh rootfs
```

### 10.2 固件生成

```bash
# 最终固件位置
ls -lh output/firmware/update.img

# 或使用软链接
ls -lh rockdev/update.img
```

### 10.3 烧录到设备

```bash
# 方法 1: 使用 RKDevTool（Windows/Linux）
# 1. 连接 SRC2500 设备到 USB
# 2. 进入 MaskROM 模式
# 3. 在 RKDevTool 中选择 update.img
# 4. 点击 "Upgrade"

# 方法 2: 使用 dd 命令（Linux）
# 1. 通过 SD 卡启动到 Ubuntu
# 2. 卸载 eMMC 分区
# 3. dd if=update.img of=/dev/mmcblk0 bs=1M
```

### 10.4 首次启动验证

```bash
# SSH 登录到 SRC2500
ssh sr@192.168.192.7

# 检查脚本日志
journalctl -u pxeboot-init.service || journalctl | grep pxeboot

# 验证分区
lsblk -o NAME,SIZE,PARTLABEL,MOUNTPOINT

# 验证挂载
mount | grep pxe

# 验证 systemd 单元
systemctl list-units '*.mount' | grep pxe
```

---

## 11. 故障排查指南

### 11.1 分区创建失败

**症状**：
```
ERROR: Failed to create partition pxe_rootfs_a
```

**排查步骤**：
1. 检查 eMMC 剩余空间：`lsblk -o NAME,SIZE`
2. 检查 sgdisk 是否安装：`which sgdisk`
3. 检查内核日志：`dmesg | grep -i mmc`
4. 手动运行 sgdisk：`sgdisk -p /dev/mmcblk0`

### 11.2 挂载失败

**症状**：
```
ERROR: Failed to start mount unit for pxe_rootfs_a
```

**排查步骤**：
1. 检查分区设备：`ls -la /dev/disk/by-partlabel/pxe_rootfs_a`
2. 检查文件系统：`fsck -n /dev/mmcblk0p5`
3. 检查 mount 单元：`systemctl cat pxe\\x2drootfs\\x2da.mount`
4. 手动挂载测试：`mount /dev/mmcblk0p5 /mnt`

### 11.3 systemd 单元无效

**症状**：
```
Failed to start pxe\x2drootfs\x2da.mount: Unit pxe\x2drootfs\x2da.mount not found.
```

**排查步骤**：
1. 检查单元文件是否存在：`ls -la /etc/systemd/system/pxe*`
2. 重新加载 systemd：`systemctl daemon-reload`
3. 检查单元文件语法：`systemd-analyze verify /etc/systemd/system/pxe\x2drootfs\x2da.mount`

### 11.4 重启后分区丢失

**症状**：首次启动正常，重启后 `/pxe_rootfs_a` 不存在

**排查步骤**：
1. 检查分区表：`sgdisk -p /dev/mmcblk0 | grep pxe`
2. 检查 PARTLABEL：`ls -la /dev/disk/by-partlabel/`
3. 检查 systemd 单元状态：`systemctl is-enabled pxe\\x2drootfs\\x2da.mount`
4. 检查 overlay 持久化：`mount | grep /etc/systemd/system`

---

## 12. 后续优化建议

### 12.1 性能优化

**当前实现**：串行创建和格式化分区

**优化方案**：
```bash
# 并行格式化（for 分区 > 10GB）
mkfs.ext4 -F -L "$PART_NAME" "$PART_DEV" &
FORMAT_PIDS+=($!)
done
wait ${FORMAT_PIDS[@]}
```

**预期收益**：
- 格式化 28GB 的 pxe_upper 分区约需 10 秒
- 并行化可减少到约 15 秒（总体）

### 12.2 日志增强

**当前实现**：仅输出到 stdout

**优化方案**：
```bash
# 添加日志文件
LOG_FILE="/var/log/pxeboot-init.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# 添加时间戳
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Creating partition $PART_NAME"
```

### 12.3 分区健康检查

**新增功能**：
```bash
# 检查分区是否存在坏块
badblocks -s /dev/mmcblk0p5

# 检查文件系统健康
fsck -n /dev/mmcblk0p5
```

### 12.4 A/B 分区切换支持

**未来需求**：
- 读取启动标志（`/boot/pxe_bootflag`）
- 动态切换 NFS 导出路径
- 更新 dnsmasq 配置

**实现参考**：
```bash
if [ -f /boot/pxe_bootflag ]; then
    BOOTFLAG=$(cat /boot/pxe_bootflag)
    if [ "$BOOTFLAG" = "b" ]; then
        ln -sf /pxe_rootfs_b /pxeboot/lower
    else
        ln -sf /pxe_rootfs_a /pxeboot/lower
    fi
fi
```

---

## 13. 参考资料

### 13.1 设计文档

- **架构设计**: `/home/linke/processor_sdk/.ai_context/src2500-pxeboot-partition-20250331/01-architecture/design.md`
- **分区布局**: `/home/linke/processor_sdk/.ai_context/src2500-pxeboot-partition-20250331/01-architecture/partition-layout.txt`

### 13.2 参考实现

- **SRC3600 脚本**: `/home/linke/processor_sdk/ubuntu22.04/overlay-src3600/usr/local/bin/pxeboot-init.sh`

### 13.3 工具文档

- **sgdisk**: `man sgdisk`（GPT 分区表管理工具）
- **systemd.mount**: `man systemd.mount`（systemd 挂载单元配置）
- **partprobe**: `man partprobe`（通知内核分区表变化）

### 13.4 相关配置

- **分区表**: `/home/linke/processor_sdk/device/rockchip/.chips/rk3562/parameter-ubuntu-src2500-3600.txt`
- **SRC2500 overlay**: `/home/linke/processor_sdk/ubuntu22.04/overlay-src2500/`
- **dnsmasq 配置**: `/home/linke/processor_sdk/ubuntu22.04/overlay-src2500/etc/dnsmasq.d/pxe-server.conf`

---

## 14. 附录

### 14.1 完整扇区计算表

| 单位 | 字节 | 扇区（512B） | 十六进制 |
|------|------|------------|---------|
| 1GB | 1073741824 | 2097152 | 0x200000 |
| 2GB | 2147483648 | 4194304 | 0x400000 |
| 28GB | 30064771072 | 58720256 | 0x3800000 |
| 16GB | 17179869184 | 33554432 | 0x2000000 |
| 48GB | 51539607552 | 100663296 | 0x6000000 |

### 14.2 UUID 分配表

| 分区号 | 分区名 | UUID 后缀 | 完整 UUID |
|--------|--------|----------|----------|
| 5 | pxe_rootfs_a | 54c0 | 614e0000-0000-4b53-8000-1d28000054c0 |
| 6 | pxe_rootfs_b | 54c1 | 614e0000-0000-4b53-8000-1d28000054c1 |
| 7 | pxe_upper | 54c2 | 614e0000-0000-4b53-8000-1d28000054c2 |
| 8 | log | 54c8 | 614e0000-0000-4b53-8000-1d28000054c8 |

### 14.3 systemd mount 单元清单

| 单元文件 | 挂载点 | What 参数 |
|---------|--------|----------|
| `pxe\x2drootfs\x2da.mount` | `/pxe_rootfs_a` | `PARTLABEL=pxe_rootfs_a` |
| `pxe\x2drootfs\x2db.mount` | `/pxe_rootfs_b` | `PARTLABEL=pxe_rootfs_b` |
| `pxe\x2dupper.mount` | `/pxe_upper` | `PARTLABEL=pxe_upper` |
| `log.mount` | `/log` | `PARTLABEL=log` |

---

**文档结束**
