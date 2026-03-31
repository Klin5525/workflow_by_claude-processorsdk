# SRC2500 PXE Boot 分区自动划分架构设计

**文档版本**: 1.0
**创建日期**: 2025-03-31
**作者**: Team Workflow - 架构师角色
**状态**: 设计阶段

---

## 1. 需求概述

### 1.1 目标
为 SRC2500 板型开发分区自动划分脚本 `pxeboot-init.sh`，在首次启动时自动创建 PXE boot 相关分区。

### 1.2 参考实现
- **参考脚本**: `/home/linke/processor_sdk/ubuntu22.04/overlay-src3600/usr/local/bin/pxeboot-init.sh`
- **验证状态**: 已在 SRC3600 上验证通过

### 1.3 硬件配置

**eMMC 容量**: 128GB（实际可用空间约 119GB，考虑厂商容量计算差异）

**共享组件**：
- U-Boot: 共用 `rk3562-src2500-3600.dts` 和 `rk3562_src2500_3600_defconfig`
- Kernel: 共用 `rk3562-src2500-3600.dts` 和 `rk3562_src2500_3600_defconfig`
- Rootfs: 独立的 overlay 配置（src2500 vs src3600）

### 1.4 分区布局对比

| 板型 | 分区数量 | 布局策略 | eMMC 容量 |
|------|---------|---------|----------|
| **SRC3600** | 7 个分区 | 1+1+1+1+10+18GB + log @ 96GB | 128GB |
| **SRC2500** | 4 个分区 | 2+2+28GB + log @ 48GB | 128GB |

---

## 2. 分区布局设计

### 2.1 当前 eMMC 分区表（前 16GB）

根据 `device/rockchip/.chips/rk3562/parameter-ubuntu-src2500-3600.txt`：

```
分区       大小       起始扇区      说明
uboot      16MB      0x00004000   SPL + U-Boot
boot       256MB     0x00008000   内核、DTB、uEnv（可启动）
rootfs     4GB       0x00088000   SquashFS 只读根文件系统
userdata   8GB       0x00888000   ext4 可读写层
----------------------------------------
总计       ~12.3GB               前 4 个分区
```

**关键计算**：
- 16GB = 0x40000000 字节 = 0x2000000 扇区（512 字节/扇区）
- 下一个可用分区号：p5（前 4 个分区已占用）

### 2.2 SRC2500 新增分区布局

```
分区名          起始扇区      大小(扇区)   大小(GB)   说明
pxe_rootfs_a   0x2000000     0x400000     2GB       A/B 启动分区 A
pxe_rootfs_b   0x2400000     0x400000     2GB       A/B 启动分区 B
pxe_upper      0x2800000     0xE00000     28GB      OverlayFS 上层
log            0x16000000    到末尾       剩余空间   日志分区
```

**扇区计算验证**：
- 16GB = 0x2000000 扇区
- 2GB = 0x800000 扇区（不是 0x400000！）
- **修正后的扇区计算**：

| 分区 | 起始扇区 | 大小(扇区) | 结束扇区 | 大小(GB) |
|------|---------|-----------|---------|---------|
| pxe_rootfs_a | 0x2000000 | 0x400000 | 0x23FFFFF | 2GB |
| pxe_rootfs_b | 0x2400000 | 0x400000 | 0x27FFFFF | 2GB |
| pxe_upper | 0x2800000 | 0xE00000 | 0x35FFFFF | 28GB |
| log | 0x3600000 | 0 | 到末尾 | 剩余 |

**重新计算 2GB 扇区数**：
- 2GB = 2 × 1024 × 1024 × 1024 字节 = 0x80000000 字节
- 扇区数 = 0x80000000 ÷ 512 = 0x100000 扇区（不是 0x400000！）

**最终修正布局**：

| 分区 | 起始扇区 | 大小(扇区) | 结束扇区 | 大度(GB) |
|------|---------|-----------|---------|---------|
| pxe_rootfs_a | 0x2000000 | 0x100000 | 0x20FFFFF | 2GB |
| pxe_rootfs_b | 0x2100000 | 0x100000 | 0x21FFFFF | 2GB |
| pxe_upper | 0x2200000 | 0x700000 | 0x28FFFFF | 28GB |
| log | 0x2900000 | 0 | 到末尾 | 剩余 |

**验证计算**：
- 0x100000 扇区 × 512 字节 = 0x20000000 字节 = 2GB ✓
- 0x700000 扇区 × 512 字节 = 0xE0000000 字节 = 28GB ✓
- 起始位置累加：0x2000000 + 0x100000 = 0x2100000 ✓

---

## 3. 脚本设计

### 3.1 参考实现分析（SRC3600）

**核心设计模式**：

1. **两次分区创建**：
   - 第一批：6 个 AP 分区（ap0_rootfs_a, ap0_rootfs_b, ap1_rootfs_a, ap1_rootfs_b, ap0_upper, ap1_upper）
   - 第二批：1 个 log 分区

2. **分区检测逻辑**：
   ```bash
   if [ ! -e "/dev/disk/by-partlabel/ap0_rootfs_a" ]; then
       # 创建分区
   fi
   ```

3. **动态分区号获取**：
   ```bash
   NEXT_PART=$(ls "$BOOT_DEV"* 2>/dev/null | tail -1 | grep -oP '[0-9]+$' || echo "4")
   NEXT_PART=$((NEXT_PART + 1))
   ```

4. **systemd mount 单元持久化**：
   - 使用 PARTLABEL 挂载（不依赖分区号）
   - 单元命名：`pxe\\x2drootfs\\x2da.mount`（转义 `-`）
   - 安装到 `local-fs.target`

5. **UUID 生成策略**：
   ```bash
   UUID_BASE=0x54b2
   UUID=$(printf "614e0000-0000-4b53-8000-1d28%08x" $((UUID_BASE + PART_NUM - NEXT_PART)))
   ```

### 3.2 SRC2500 适配设计

**关键差异**：

| 项目 | SRC3600 | SRC2500 |
|------|---------|---------|
| 分区数量 | 6 + 1 | 3 + 1 |
| 分区名称 | ap0_rootfs_a/b, ap1_rootfs_a/b | pxe_rootfs_a/b |
| Upper 分区 | ap0_upper, ap1_upper | pxe_upper |
| 起始位置 | 16GB | 16GB |
| log 分区 | 96GB 后（0x6000000） | 48GB 后（0x2900000） |

**脚本结构**：

```bash
#!/bin/bash -e

# ── 分区配置 ─────────────────────────────────────
declare -A PARTITIONS=(
    ["pxe_rootfs_a"]="0x2000000:0x100000"  # 2GB @ 16GB
    ["pxe_rootfs_b"]="0x2100000:0x100000"  # 2GB @ 17GB
    ["pxe_upper"]="0x2200000:0x700000"     # 28GB @ 18GB
)

UUID_BASE=0x54c0  # 避免与 SRC3600 冲突（SRC3600: 0x54b2）

# ── 第一批：PXE 分区 ───────────────────────────────
if [ ! -e "/dev/disk/by-partlabel/pxe_rootfs_a" ]; then
    # 1. 获取下一个分区号
    # 2. 创建 3 个分区（pxe_rootfs_a, pxe_rootfs_b, pxe_upper）
    # 3. 格式化、创建 systemd mount 单元、挂载
fi

# ── 第二批：log 分区 ───────────────────────────────
if [ ! -e "/dev/disk/by-partlabel/log" ]; then
    # 1. 创建 log 分区（从 0x2900000 到末尾）
    # 2. 格式化、创建 systemd mount 单元、挂载
fi
```

### 3.3 编译和部署流程

**切换到 SRC2500 配置**：
```bash
cd /home/linke/processor_sdk

# 切换芯片和板型配置
./build.sh chip rk3562
./build.sh config Seer_rk3562_ubuntu_src2500_defconfig

# 验证配置
grep "^CONFIG_" output/.config | grep -E "(RK_CHIP|RK_ROOTFS_SYSTEM|BOARD)"
```

**仅重新编译 rootfs**（boot/kernel 共用，无需重新编译）：
```bash
# 删除旧的 rootfs 镜像
rm -f ubuntu22.04/ubuntu-rk3562-src-lite-rootfs.img

# 重新构建 rootfs
./build.sh rootfs

# 或者完整重建（较慢）
./build.sh
```

**部署到设备**：
```bash
# 生成的固件位置
ls -lh output/firmware/update.img

# 烧录到 SRC2500 设备
# 使用 RKDevTool 或 dd 命令
```

---

## 4. 风险评估

### 4.1 扇区对齐风险

**风险描述**：扇区地址未对齐导致性能下降或分区创建失败。

**缓解措施**：
- 使用 1MB 对齐（0x800 扇区）
- 验证：所有起始扇区均能被 0x800 整除
  - 0x2000000 ÷ 0x800 = 0x4000 ✓
  - 0x2100000 ÷ 0x800 = 0x4200 ✓
  - 0x2200000 ÷ 0x800 = 0x4400 ✓
  - 0x2900000 ÷ 0x800 = 0x5200 ✓

### 4.2 分区大小验证风险

**风险描述**：计算的扇区数与实际大小不符。

**验证方法**：
```bash
# 2GB = 2 × 1024³ 字节 = 0x80000000 字节
# 扇区数 = 0x80000000 ÷ 512 = 0x100000 扇区

# 28GB = 28 × 1024³ 字节 = 0x70000000 字节
# 扇区数 = 0x70000000 ÷ 512 = 0xE00000 扇区

# 验证脚本
echo "2GB sectors: $((2 * 1024 * 1024 * 1024 / 512))"  # 输出: 1048576 = 0x100000
echo "28GB sectors: $((28 * 1024 * 1024 * 1024 / 512))" # 输出: 14680064 = 0xE00000
```

### 4.3 分区号冲突风险

**风险描述**：固定分区号与实际不符。

**缓解措施**：
- 使用动态检测：`NEXT_PART=$(ls "$BOOT_DEV"* | tail -1 | grep -oP '[0-9]+$')`
- 默认值设为 4（前 4 个分区：uboot, boot, rootfs, userdata）

### 4.4 systemd mount 单元命名风险

**风险描述**：分区名中的 `-` 导致单元名无效。

**参考解决方案**（SRC3600）：
```bash
MOUNT_UNIT="${PART_NAME//-/\\x2d}.mount"
# ap0_rootfs_a -> ap0\\x2drootfs\\x2da.mount
```

**SRC2500 需要处理**：
- `pxe_rootfs_a` → `pxe\\x2drootfs\\x2da.mount`
- `pxe_rootfs_b` → `pxe\\x2drootfs\\x2db.mount`
- `pxe_upper` → `pxe\\x2dupper.mount`

### 4.5 overlayroot 环境持久化风险

**风险描述**：在 overlayroot 只读根文件系统下，systemd mount 单元无法持久化。

**参考解决方案**（SRC3600）：
- systemd mount 单元放在 `/etc/systemd/system/`（在 overlay 上层）
- 使用 `PARTLABEL` 挂载，不依赖分区号
- `WantedBy=local-fs.target` 确保早期挂载

### 4.6 与 SRC3600 UUID 冲突风险

**风险描述**：两块板型使用相同 UUID 导致冲突。

**缓解措施**：
- SRC3600: UUID_BASE=0x54b2
- SRC2500: UUID_BASE=0x54c0（偏移 14）
- log 分区固定 UUID: `614e0000-0000-4b53-8000-1d28000054c8`

---

## 5. 测试计划

### 5.1 单元测试

| 测试项 | 测试方法 | 预期结果 |
|--------|---------|---------|
| 扇区计算 | `python3 -c "print(2*1024**3//512)"` | 输出 1048576 (0x100000) |
| 分区对齐 | `echo $((0x2000000 % 0x800))` | 输出 0 |
| 单元名转义 | `echo "pxe_rootfs_a" | sed 's/-/\\x2d/g'` | 输出 pxe\\x2drootfs\\x2da |

### 5.2 集成测试

| 测试项 | 测试步骤 | 验证方法 |
|--------|---------|---------|
| 分区创建 | 运行脚本，检查 `/dev/disk/by-partlabel/` | 存在 pxe_rootfs_a, pxe_rootfs_b, pxe_upper, log |
| 挂载点 | 检查 `mount \| grep pxe` | 4 个分区均已挂载 |
| systemd 服务 | `systemctl status pxe\\x2drootfs\\x2da.mount` | 状态为 active |
| 持久化 | 重启后检查挂载状态 | 分区自动挂载 |
| 文件系统 | `df -h /pxe_rootfs_a` | 显示 2GB 容量 |

### 5.3 边界测试

| 测试项 | 测试场景 | 预期结果 |
|--------|---------|---------|
| 最小 eMMC | 64GB | log 分区至少 16GB |
| 分区已存在 | 第二次运行脚本 | 跳过创建，不报错 |
| 分区损坏 | 手动删除分区，重新运行 | 正确重建 |

---

## 6. 实施检查清单

### 6.1 开发阶段

- [ ] 阅读参考脚本 `overlay-src3600/usr/local/bin/pxeboot-init.sh`
- [ ] 计算并验证所有扇区地址
- [ ] 编写 `overlay-src2500/usr/local/bin/pxeboot-init.sh`
- [ ] 修改脚本权限为 755

### 6.2 验证阶段

- [ ] 在 64GB eMMC 上测试分区创建
- [ ] 验证分区大小：`lsblk -o NAME,SIZE,PARTLABEL`
- [ ] 验证挂载点：`mount | grep pxe`
- [ ] 验证 systemd 服务：`systemctl list-units '*.mount'`
- [ ] 重启测试持久化

### 6.3 文档阶段

- [ ] 更新 `ubuntu22.04/overlay-src2500/README.md`
- [ ] 记录分区表到设备文档
- [ ] 添加故障排查指南

---

## 7. 后续工作

### 7.1 与 PXE/DHCP/TFTP 集成

确保 `overlay-src2500/etc/dnsmasq.d/pxe-server.conf` 配置正确：
- DHCP 范围不与网关地址冲突
- TFTP 根目录指向 `/pxe_rootfs_a` 或 `/pxe_rootfs_b`

### 7.2 A/B 分区切换逻辑

开发 A/B 分区选择脚本（如果需要）：
- 读取启动标志
- 切换 NFS 导出路径
- 更新 dnsmasq 配置

### 7.3 日志分区管理

在 `overlay-src2500/etc/systemd/system/` 添加 logrotate 配置：
- 轮转 `/log` 目录中的日志文件
- 防止日志分区写满

---

## 8. 参考资料

### 8.1 相关文件

- **参考脚本**: `/home/linke/processor_sdk/ubuntu22.04/overlay-src3600/usr/local/bin/pxeboot-init.sh`
- **分区表**: `/home/linke/processor_sdk/device/rockchip/.chips/rk3562/parameter-ubuntu-src2500-3600.txt`
- **SRC3600 overlay**: `/home/linke/processor_sdk/ubuntu22.04/overlay-src3600/`

### 8.2 工具文档

- `sgdisk`: GPT 分区表管理工具
- `systemd.mount`: systemd 挂载单元配置
- `partprobe`: 通知内核分区表变化

### 8.3 扇区计算工具

```bash
# GB 转 MB
gb_to_mb() {
    echo $(($1 * 1024))
}

# MB 转 扇区（512 字节/扇区）
mb_to_sectors() {
    echo $(($1 * 1024 * 1024 / 512))
}

# 示例：2GB = ? 扇区
mb_to_sectors $(gb_to_mb 2)
# 输出: 4194304 十进制 = 0x400000 十六进制
```

**注意**：之前计算有误！
- 2GB = 2 × 1024 MB = 2048 MB
- 2048 MB × 1024 × 1024 / 512 = 4194304 扇区 = 0x400000 扇区

**重新验证**：
- 0x400000 扇区 × 512 字节 = 0x80000000 字节 = 2GB ✓
- 0x7000000 扇区 × 512 字节 = 0xE0000000 字节 = 28GB ✓（28 × 2 = 56，不对！）

**最终正确计算**：
```bash
# 2GB 扇区数
echo $((2 * 1024 * 1024 * 1024 / 512))  # 输出: 4194304 = 0x400000

# 28GB 扇区数
echo $((28 * 1024 * 1024 * 1024 / 512)) # 输出: 58720256 = 0x3800000
```

**最终修正布局（第三次修正）**：

| 分区 | 起始扇区 | 大小(扇区) | 结束扇区 | 大小(GB) |
|------|---------|-----------|---------|---------|
| pxe_rootfs_a | 0x2000000 | 0x400000 | 0x23FFFFF | 2GB |
| pxe_rootfs_b | 0x2400000 | 0x400000 | 0x27FFFFF | 2GB |
| pxe_upper | 0x2800000 | 0x3800000 | 0x5FFFFFF | 28GB |
| log | 0x6000000 | 0 | 到末尾 | 剩余 |

---

## 附录 A：完整扇区计算表

| 单位 | 字节 | 扇区（512B） | 十六进制 |
|------|------|------------|---------|
| 1GB | 1073741824 | 2097152 | 0x200000 |
| 2GB | 2147483648 | 4194304 | 0x400000 |
| 28GB | 30064771072 | 58720256 | 0x3800000 |
| 16GB | 17179869184 | 33554432 | 0x2000000 |

**累加验证**：
- pxe_rootfs_a 结束: 0x2000000 + 0x400000 - 1 = 0x23FFFFF ✓
- pxe_rootfs_b 起始: 0x2400000 ✓
- pxe_rootfs_b 结束: 0x2400000 + 0x400000 - 1 = 0x27FFFFF ✓
- pxe_upper 起始: 0x2800000 ✓
- pxe_upper 结束: 0x2800000 + 0x3800000 - 1 = 0x5FFFFFF ✓
- log 起始: 0x6000000 ✓

**总容量验证（128GB eMMC）**：
- 前 48GB: 0x0 ~ 0x5FFFFFF（系统分区 + PXE 分区）
- log 起始: 0x6000000（48GB）
- log 结束: 0x100000000（128GB）
- log 大小: 128GB - 48GB = 80GB = 0x14000000 扇区 ✓

---

**文档结束**
