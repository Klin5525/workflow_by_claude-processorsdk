# SRC2500 vs SRC3600 分区设计对比分析

## 概述

本文档详细对比 SRC2500 和 SRC3600 两个板型的 PXE boot 分区设计，帮助理解设计差异和迁移策略。

---

## 分区数量差异

### SRC3600: 7 个分区

```
ap0_rootfs_a   1GB  @ 16GB  (0x2000000)  A/B 启动分区 A0
ap0_rootfs_b   1GB  @ 17GB  (0x2200000)  A/B 启动分区 B0
ap1_rootfs_a   1GB  @ 18GB  (0x2400000)  A/B 启动分区 A1
ap1_rootfs_b   1GB  @ 19GB  (0x2600000)  A/B 启动分区 B1
ap0_upper      18GB @ 20GB  (0x2800000)  OverlayFS 上层 0
ap1_upper      10GB @ 38GB  (0x4C00000)  OverlayFS 上层 1
log            剩余 @ 96GB  (0xC000000)  日志分区
```

**设计理念**：
- 支持两个独立的 AP（Application Processor）实例
- 每个实例有完整的 A/B 启动分区 + upper 分区
- 适用于双 AP 场景（可能用于两个不同的 x86 根文件系统）

### SRC2500: 4 个分区

```
pxe_rootfs_a   2GB  @ 16GB  (0x2000000)  A/B 启动分区 A
pxe_rootfs_b   2GB  @ 18GB  (0x2400000)  A/B 启动分区 B
pxe_upper      28GB @ 20GB  (0x2800000)  OverlayFS 上层
log            剩余 @ 48GB  (0x6000000)  日志分区
```

**设计理念**：
- 简化的单 AP 实例
- 仅支持一个 x86 根文件系统的 A/B 切换
- 更大的单个 rootfs 分区（2GB vs 1GB）
- 更大的 upper 分区（28GB vs 18/10GB）

---

## 分区大小对比

| 用途 | SRC3600 | SRC2500 | 变化 |
|------|---------|---------|------|
| Rootfs A | 1GB × 2 | 2GB × 2 | +100% |
| Upper | 18GB + 10GB | 28GB | 合并 +55% |
| log 起始位置 | 96GB | 48GB | 提前 48GB |

### 为什么 SRC2500 需要 2GB rootfs？

可能原因：
1. **更大的 Ubuntu base 镜像**：桌面环境或更多预装软件
2. **双架构支持**：可能同时包含 x86_64 和 ARM64 工具链
3. **安全边际**：预留更多空间避免 rootfs 写满

### 为什么 SRC2500 使用 28GB upper？

可能原因：
1. **单实例需求**：不需要为第二个 AP 预留空间
2. **更多用户数据**：可能用于存储大量 PXE 启动文件
3. **日志和缓存**：应用程序产生的临时数据

---

## 脚本实现差异

### 分区创建顺序

**SRC3600**：
```bash
# 第一批：6 个 AP 分区
for PART_NAME in ap0_rootfs_a ap0_rootfs_b ap1_rootfs_a ap1_rootfs_b ap0_upper ap1_upper
do
    # 创建分区
done

# 第二批：1 个 log 分区
if [ ! -e "/dev/disk/by-partlabel/log" ]; then
    # 创建 log 分区
fi
```

**SRC2500**：
```bash
# 第一批：3 个 PXE 分区
for PART_NAME in pxe_rootfs_a pxe_rootfs_b pxe_upper
do
    # 创建分区
done

# 第二批：1 个 log 分区（与 SRC3600 相同）
if [ ! -e "/dev/disk/by-partlabel/log" ]; then
    # 创建 log 分区
fi
```

### systemd mount 单元命名

| 分区名 | SRC3600 单元名 | SRC2500 单元名 |
|--------|---------------|---------------|
| rootfs_a | ap0\\x2drootfs\\x2da.mount | pxe\\x2drootfs\\x2da.mount |
| rootfs_b | ap0\\x2drootfs\\x2db.mount | pxe\\x2drootfs\\x2db.mount |
| upper | ap0\\x2dupper.mount | pxe\\x2dupper.mount |
| log | log.mount | log.mount |

**命名规则一致**：所有 `-` 字符转义为 `\\x2d`。

### UUID 分配策略

**SRC3600**：
```bash
UUID_BASE=0x54b2
# 分配范围：0x54b2 ~ 0x54b7 (6 个分区)
# log 分区：0x54b8
```

**SRC2500**：
```bash
UUID_BASE=0x54c0
# 分配范围：0x54c0 ~ 0x54c2 (3 个分区)
# log 分区：0x54c8
```

**为什么偏移 14（0x54c0 - 0x54b2 = 0xE）？**
1. 避免两块板型在同一开发机上测试时 UUID 冲突
2. 便于通过 UUID 识别板型
3. 预留空间给未来的扩展

---

## 使用场景分析

### SRC3600 适用场景

**可能的部署架构**：
```
┌─────────────────────────────────────┐
│         SRC3600 网关                │
│  ┌──────────┐      ┌──────────┐    │
│  │ AP0 实例 │      │ AP1 实例 │    │
│  │ (测试)   │      │ (生产)   │    │
│  └──────────┘      └──────────┘    │
│       │                  │          │
│       └───────┬──────────┘          │
│         PXE/DHCP/TFTP              │
└─────────────────────────────────────┘
              │
    ┌─────────┴─────────┐
    │                   │
┌───▼────┐        ┌────▼───┐
│ x86-0  │        │ x86-1  │
│ 测试机 │        │ 生产机 │
└────────┘        └────────┘
```

**优势**：
- 测试环境和生产环境完全隔离
- 同时支持两个不同的软件版本
- 降低版本切换风险

### SRC2500 适用场景

**可能的部署架构**：
```
┌─────────────────────────────────────┐
│         SRC2500 网关                │
│                                     │
│  ┌──────────┐  ┌──────────┐        │
│  │ PXE A    │  │ PXE B    │        │
│  │ (当前)   │  │ (备份)   │        │
│  └──────────┘  └──────────┘        │
│         │                            │
│         ▼                            │
│    PXE/DHCP/TFTP                    │
│  (单组配置)                         │
└─────────────────────────────────────┘
              │
    ┌─────────┴─────────┐
    │                   │
┌───▼────┐        ┌────▼───┐
│ x86-0  │        │ x86-1  │
│ 节点   │        │ 节点    │
└────────┘        └────────┘
```

**优势**：
- 简化的架构，减少维护复杂度
- 更大的单个分区容量
- 适合单一软件版本部署

---

## 迁移指南

### 从 SRC3600 迁移到 SRC2500

**需要修改的配置**：

1. **dnsmasq 配置** (`/etc/dnsmasq.d/pxe-server.conf`)
   - 移除 AP1 相关的 DHCP/TFTP 配置
   - 更新 NFS 导出路径（`ap0_rootfs_a` → `pxe_rootfs_a`）

2. **NFS 导出** (`/etc/exports`)
   - 简化为单一导出路径
   - `/pxe_rootfs_a 192.168.192.0/24(rw,sync,no_subtree_check,no_root_squash)`

3. **A/B 切换脚本**（如果有）
   - 移除 AP0/AP1 选择逻辑
   - 仅保留 pxe_rootfs_a/b 切换

### 共享的组件

以下组件在两个板型上可以共享：
- **overlayroot 配置**：OverlayFS 挂载逻辑相同
- **logrotate 配置**：日志轮转策略相同
- **监控脚本**：分区空间监控、健康检查等

---

## 性能影响分析

### 分区数量对性能的影响

| 指标 | SRC3600 (7个) | SRC2500 (4个) | 影响 |
|------|-------------|-------------|------|
| 启动时间 | 较长 | 较短 | 更少的分区需要挂载 |
| GPT 扫描 | 较慢 | 较快 | 更少的分区表项 |
| udev 规则处理 | 较多 | 较少 | 更少的设备事件 |
| 维护复杂度 | 高 | 低 | 更少的分区需要管理 |

### 分区大小对性能的影响

**Rootfs 分区大小**（2GB vs 1GB）：
- **优势**：可以存储更大的根文件系统镜像
- **劣势**： SquashFS 压缩/解压时间稍长
- **影响**：可忽略（仅在升级时操作）

**Upper 分区大小**（28GB vs 18GB）：
- **优势**：更多空间存放 OverlayFS 上层数据
- **劣势**：e2fsck 检查时间稍长
- **影响**：仅在文件系统错误时影响

---

## 风险对比

### SRC3600 特有风险

1. **AP0/AP1 混淆**：可能误将生产流量指向测试实例
2. **分区空间不足**：10GB ap1_upper 可能不够用
3. **配置复杂性**：需要维护两套独立的配置

### SRC2500 特有风险

1. **单点故障**：只有一个 AP 实例，无法灰度发布
2. **分区布局限制**：无法同时运行两个不同版本
3. **回滚策略**：依赖 A/B 分区手动切换

### 共同风险

1. **log 分区写满**：需要配置 logrotate
2. **OverlayFS 上层写满**：需要监控空间使用
3. **分区表损坏**：需要备份 GPT 分区表

---

## 最佳实践建议

### SRC3600 最佳实践

1. **明确标识 AP0 和 AP1**：
   ```bash
   # 在 /etc/ap-info 中记录当前 AP 角色
   echo "AP0_ROLE=test" > /etc/ap-info
   echo "AP1_ROLE=production" >> /etc/ap-info
   ```

2. **独立的 dnsmasq 实例**：
   ```bash
   # 为 AP0 和 AP1 运行独立的 dnsmasq 进程
   # 使用不同的 DHCP 端口（ap0: 67, ap1: 1067）
   ```

3. **分区空间监控**：
   ```bash
   # 警告阈值：ap1_upper 90%
   [ $(df /ap1_upper | awk 'NR==2 {print $5}' | sed 's/%//') -gt 90 ] && \
       logger "WARNING: ap1_upper is 90% full"
   ```

### SRC2500 最佳实践

1. **A/B 分区标记文件**：
   ```bash
   # 在 /pxe_rootfs_a/.active 中标记当前活动分区
   touch /pxe_rootfs_a/.active
   ```

2. **自动切换脚本**：
   ```bash
   # /usr/local/bin/switch-pxe-rootfs.sh
   # 自动切换 active 分区并更新 dnsmasq 配置
   ```

3. **升级验证**：
   ```bash
   # 升级后验证新分区
   # 如果验证失败，自动回滚到旧分区
   ```

---

## 总结

### 选择 SRC3600 的理由

- 需要同时支持两个不同的软件版本
- 需要完全隔离的测试和生产环境
- 有专业的运维团队管理复杂配置

### 选择 SRC2500 的理由

- 仅需要一个软件版本
- 希望简化部署和维护
- 需要更大的单个分区容量
- 资源受限的边缘计算场景

---

**文档版本**: 1.0
**最后更新**: 2025-03-31
