# SRC2500 PXE Boot 分区设计总结

## 快速参考

### 最终分区表（已验证）

```bash
declare -A PARTITIONS=(
    ["pxe_rootfs_a"]="0x2000000:0x400000"  # 2GB @ 16GB (扇区 0x2000000 - 0x23FFFFF)
    ["pxe_rootfs_b"]="0x2400000:0x400000"  # 2GB @ 18GB (扇区 0x2400000 - 0x27FFFFF)
    ["pxe_upper"]="0x2800000:0x3800000"    # 28GB @ 20GB (扇区 0x2800000 - 0x5FFFFFF)
)

# log 分区单独处理
log 起始: 0x6000000 (48GB)
log 结束: 到 eMMC 末尾
```

### 与 SRC3600 对比

| 项目 | SRC3600 | SRC2500 |
|------|---------|---------|
| 分区数量 | 7 个 (4+2+1) | 4 个 (2+1+1) |
| AP 分区 | ap0/ap1 各 2 个 rootfs | pxe 2 个 rootfs |
| Upper 分区 | ap0_upper, ap1_upper | pxe_upper (单个) |
| 起始位置 | 16GB (0x2000000) | 16GB (0x2000000) |
| log 起始 | 96GB (0xC000000) | 48GB (0x6000000) |
| UUID_BASE | 0x54b2 | 0x54c0 |

## 关键设计决策

### 1. 扇区计算（已验证）

- **1GB** = 0x200000 扇区
- **2GB** = 0x400000 扇区
- **16GB** = 0x2000000 扇区
- **28GB** = 0x3800000 扇区
- **48GB** = 0x6000000 扇区

所有起始扇区均按 1MB (0x800 扇区) 对齐。

### 2. 分区命名规则

systemd mount 单元命名需要转义 `-` 为 `\\x2d`：

```bash
# 分区名 → systemd 单元名
pxe_rootfs_a → pxe\\x2drootfs\\x2da.mount
pxe_rootfs_b → pxe\\x2drootfs\\x2db.mount
pxe_upper → pxe\\x2dupper.mount
log → log.mount
```

### 3. UUID 分配策略

- PXE 分区：UUID_BASE=0x54c0，依次递增
- log 分区：固定 UUID `614e0000-0000-4b53-8000-1d28000054c8`

## 验证通过

✅ 扇区对齐检查（所有起始扇区 % 0x800 == 0）
✅ 分区无缝连接（前分区结束 + 1 = 后分区起始）
✅ 64GB eMMC 容量验证（log 分区 = 16GB）

## 下一步

1. 在 `ubuntu22.04/overlay-src2500/usr/local/bin/` 创建 `pxeboot-init.sh`
2. 设置权限：`chmod 755 pxeboot-init.sh`
3. 在实际硬件上测试
4. 验证 systemd mount 单元和自动挂载
