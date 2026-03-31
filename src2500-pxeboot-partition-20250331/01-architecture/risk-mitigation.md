# SRC2500 分区实现风险缓解清单

## 概述

本文档提供 SRC2500 PXE boot 分区脚本实现过程中的风险识别、缓解措施和验证方法。

---

## 风险分类

### 高优先级风险（必须解决）

#### 1. 扇区地址计算错误

**风险描述**：错误的扇区地址导致分区大小不符或重叠。

**影响范围**：系统无法启动，数据丢失

**缓解措施**：

1. **使用验证脚本**：
   ```bash
   cd /home/linke/processor_sdk/.ai_context/src2500-pxeboot-partition-20250331/01-architecture
   ./verify-sectors.sh
   ```

2. **人工验证**：
   ```bash
   # 验证 2GB = 0x400000 扇区
   python3 -c "print(hex(2*1024**3//512))"

   # 验证 28GB = 0x3800000 扇区
   python3 -c "print(hex(28*1024**3//512))"
   ```

3. **脚本中添加断言**：
   ```bash
   # 在 pxeboot-init.sh 中添加
   assert_sector_size() {
       local size_gb=$1
       local expected_sectors=$2
       local actual=$(($size_gb * 1024 * 1024 * 1024 / 512))
       if [ "$actual" != "$expected_sectors" ]; then
           echo "ERROR: Sector size mismatch for ${size_gb}GB"
           exit 1
       fi
   }

   assert_sector_size 2 0x400000
   assert_sector_size 28 0x3800000
   ```

**验证方法**：
- 运行验证脚本，输出应为预期的十六进制值
- 检查分区创建后的实际大小：`lsblk -o NAME,SIZE,PARTLABEL`

#### 2. 分区号检测失败

**风险描述**：动态获取的分区号不正确，导致覆盖现有分区。

**影响范围**：数据丢失，系统损坏

**缓解措施**：

1. **增强检测逻辑**：
   ```bash
   # 获取当前最大分区号
   CURRENT_PART=$(ls "$BOOT_DEV"* 2>/dev/null | \
       tail -1 | \
       grep -oP '[0-9]+$' || \
       echo "4")

   # 验证分区号合理性
   if [ "$CURRENT_PART" -lt 4 ] || [ "$CURRENT_PART" -gt 128 ]; then
       echo "ERROR: Invalid partition number: $CURRENT_PART"
       exit 1
   fi

   NEXT_PART=$((CURRENT_PART + 1))
   ```

2. **添加分区号冲突检查**：
   ```bash
   # 检查目标分区是否已存在
   if [ -e "${BOOT_DEV}p${NEXT_PART}" ] || [ -e "${BOOT_DEV}${NEXT_PART}" ]; then
       echo "WARNING: Partition p${NEXT_PART} already exists"
       # 询问用户是否继续
   fi
   ```

3. **使用 sgdisk 的 --print 验证**：
   ```bash
   # 在创建分区前打印当前分区表
   sgdisk --print "$BOOT_DEV"
   read -p "Continue? (y/n) " confirm
   [ "$confirm" != "y" ] && exit 1
   ```

**验证方法**：
- 在已知分区布局的设备上测试
- 检查 `lsblk` 输出确认分区号正确

#### 3. systemd mount 单元命名错误

**风险描述**：转义字符处理不当，导致 systemd 无法识别挂载单元。

**影响范围**：分区无法自动挂载

**缓解措施**：

1. **使用参考实现的转义方法**：
   ```bash
   # SRC3600 已验证的转义方法
   MOUNT_UNIT="${PART_NAME//-/\\x2d}.mount"

   # 测试转义结果
   echo "Mount unit: $MOUNT_UNIT"
   # 应输出: pxe\x2drootfs\x2da.mount
   ```

2. **添加单元名验证**：
   ```bash
   # 验证单元名格式
   if ! echo "$MOUNT_UNIT" | grep -qE '^[a-z0-9\\x2d]+\.mount$'; then
       echo "ERROR: Invalid mount unit name: $MOUNT_UNIT"
       exit 1
   fi
   ```

3. **在创建前测试 systemd 语法**：
   ```bash
   # 验证单元文件语法
   systemd-analyze verify "/etc/systemd/system/$MOUNT_UNIT"
   ```

**验证方法**：
- `systemctl list-units '*.mount'` - 检查单元是否被识别
- `systemctl status pxe\\x2drootfs\\x2da.mount` - 检查服务状态

---

### 中优先级风险（应该解决）

#### 4. overlayroot 环境下配置持久化

**风险描述**：在 overlayroot 只读根文件系统中，systemd 单元文件无法保存。

**影响范围**：重启后分区无法自动挂载

**缓解措施**：

1. **确认 overlayroot 配置**：
   ```bash
   # 检查 overlayroot 是否启用
   if [ -f /etc/overlayroot.conf ]; then
       echo "overlayroot is enabled"
       # systemd 单元应放在 overlay 上层
   fi
   ```

2. **使用 PARTLABEL 挂载**：
   ```ini
   [Mount]
   What=PARTLABEL=pxe_rootfs_a
   Where=/pxe_rootfs_a
   Type=ext4
   ```
   - PARTLABEL 不依赖分区号，更稳定

3. **验证单元文件位置**：
   ```bash
   # 单元文件必须在 overlay 上层
   ls -l /etc/systemd/system/*.mount
   # 检查是否为符号链接指向只读层
   ```

**验证方法**：
- `findmnt /pxe_rootfs_a` - 检查分区是否挂载
- 重启后再次运行 `findmnt` - 确认持久化成功

#### 5. 分区创建失败处理

**风险描述**：sgdisk 命令失败，但脚本继续执行。

**影响范围**：后续命令失败，系统处于不一致状态

**缓解措施**：

1. **使用 bash -e 严格模式**：
   ```bash
   #!/bin/bash -e
   # 任何命令失败都会退出脚本
   ```

2. **添加显式错误检查**：
   ```bash
   if ! sgdisk "$BOOT_DEV" \
       --new=${PART_NUM}:${START}:${END} \
       --change-name=${PART_NUM}:${PART_NAME} \
       --typecode=${PART_NUM}:8300; then
       echo "ERROR: Failed to create partition $PART_NAME"
       exit 1
   fi
   ```

3. **添加回滚机制**：
   ```bash
   # 记录已创建的分区
   CREATED_PARTS=()

   create_partition() {
       # ... 创建分区逻辑 ...
       CREATED_PARTS+=("$PART_NUM")
   }

   # 清理函数
   cleanup_on_error() {
       echo "ERROR occurred, cleaning up..."
       for part in "${CREATED_PARTS[@]}"; do
           sgdisk "$BOOT_DEV" --delete=$part
       done
   }

   trap cleanup_on_error ERR
   ```

**验证方法**：
- 故意触发错误（如磁盘空间不足），检查脚本是否正确退出
- 检查分区表是否回滚到干净状态

#### 6. log 分区越界

**风险描述**：log 分区起始地址超出 eMMC 容量。

**影响范围**：分区创建失败

**缓解措施**：

1. **动态计算 eMMC 容量**：
   ```bash
   # 获取设备总扇区数
   TOTAL_SECTORS=$(blockdev --getsz "$BOOT_DEV")

   # 计算 log 分区需要的最小空间（至少 1GB）
   MIN_LOG_SECTORS=$((1 * 1024 * 1024 * 1024 / 512))
   MAX_LOG_START=$((TOTAL_SECTORS - MIN_LOG_SECTORS))

   if [ "$LOG_START" -gt "$MAX_LOG_START" ]; then
       echo "ERROR: Device too small for log partition"
       exit 1
   fi
   ```

2. **添加设备容量检查**：
   ```bash
   # 检查 eMMC 容量至少 48GB
   DEVICE_GB=$(blockdev --getsize64 "$BOOT_DEV" | awk '{print $1/1024/1024/1024}')
   if [ $(echo "$DEVICE_GB < 48" | bc) -eq 1 ]; then
       echo "ERROR: eMMC must be at least 48GB (current: ${DEVICE_GB}GB)"
       exit 1
   fi
   ```

**验证方法**：
- 在不同容量的 eMMC 上测试（32GB, 64GB, 128GB）
- 验证在 32GB 设备上脚本正确报错

---

### 低优先级风险（可以接受）

#### 7. UUID 冲突

**风险描述**：两块板型使用相同 UUID 范围导致冲突。

**影响范围**：在多板型测试环境中可能混淆

**缓解措施**：

1. **使用独立的 UUID_BASE**：
   ```bash
   # SRC3600: UUID_BASE=0x54b2
   # SRC2500: UUID_BASE=0x54c0
   ```

2. **在 UUID 中嵌入板型标识**：
   ```bash
   # 使用 UUID 的前 16 位表示板型
   # SRC2500: 614e0000-0000-4b53-8000-1d28000054c0
   # SRC3600: 614e0000-0000-4b53-8000-1d28000054b2
   ```

3. **文档化 UUID 分配**：
   - 维护一个 UUID 分配表
   - 记录每个板型使用的 UUID 范围

**验证方法**：
- 在同一台主机上同时挂载两块板型的设备
- 检查 `/dev/disk/by-uuid/` 目录确认无冲突

#### 8. 分区对齐导致性能下降

**风险描述**：未对齐的扇区地址影响 eMMC 读写性能。

**影响范围**：性能下降 5-10%

**缓解措施**：

1. **使用 1MB 对齐**：
   ```bash
   # 所有起始扇区必须是 0x800 的倍数
   ALIGNMENT=0x800

   if [ $((START % ALIGNMENT)) -ne 0 ]; then
       echo "ERROR: Partition $PART_NAME not aligned to 1MB"
       exit 1
   fi
   ```

2. **sgdisk 自动对齐**：
   ```bash
   # sgdisk 默认按 1MB 对齐，但显式指定更安全
   sgdisk "$BOOT_DEV" \
       --align=1M \
       --new=${PART_NUM}:${START}:${END}
   ```

**验证方法**：
- `cat /sys/block/mmcblk0/alignment_offset` - 检查对齐偏移
- 使用 `dd` 测试分区读写性能

---

## 测试策略

### 单元测试

```bash
#!/bin/bash
# test-partition-calculation.sh

# 测试 1: 扇区计算
test_sector_calculation() {
    local gb=$1
    local expected=$2
    local actual=$((gb * 1024 * 1024 * 1024 / 512))
    if [ "$actual" != "$expected" ]; then
        echo "FAIL: ${gb}GB sectors calculation"
        echo "  Expected: $expected"
        echo "  Actual: $actual"
        return 1
    fi
    echo "PASS: ${gb}GB = $actual sectors"
    return 0
}

test_sector_calculation 2 4194304     # 0x400000
test_sector_calculation 28 58720256   # 0x3800000
```

### 集成测试

```bash
#!/bin/bash
# test-partition-creation.sh

# 测试 1: 在虚拟块设备上测试
dd if=/dev/zero of=test.img bs=1G count=64
LOOP_DEV=$(losetup -f --show test.img)

# 运行分区脚本
BOOT_DEV=$LOOP_DEV ./pxeboot-init.sh

# 验证分区
lsblk -o NAME,SIZE,PARTLABEL $LOOP_DEV

# 清理
losetup -d $LOOP_DEV
rm test.img
```

### 边界测试

| 测试用例 | 预期结果 |
|---------|---------|
| 32GB eMMC | 脚本报错（设备太小） |
| 48GB eMMC | 正常创建，log 分区 = 0 |
| 64GB eMMC | 正常创建，log 分区 = 16GB |
| 128GB eMMC | 正常创建，log 分区 = 80GB |
| 分区已存在 | 跳过创建，不报错 |
| eMMC 只读 | 脚本报错 |

---

## 部署前检查清单

### 开发完成检查

- [ ] 脚本通过 `shellcheck` 静态分析
- [ ] 所有扇区计算经过验证脚本验证
- [ ] systemd mount 单元命名经过转义测试
- [ ] 添加了 bash -e 严格模式
- [ ] 添加了错误处理和回滚机制

### 测试完成检查

- [ ] 在 64GB 真实 eMMC 上测试通过
- [ ] 重启后分区自动挂载验证通过
- [ ] 分区大小与设计一致
- [ ] log 分区空间足够
- [ ] overlayroot 环境下配置持久化验证通过

### 文档完成检查

- [ ] 更新了 `ubuntu22.04/overlay-src2500/README.md`
- [ ] 记录了分区表到设备文档
- [ ] 添加了故障排查指南
- [ ] 准备了回滚方案

---

## 应急回滚方案

### 场景 1: 分区创建失败

**症状**：脚本执行报错，分区创建不完整

**恢复步骤**：
```bash
# 1. 备份当前分区表
sgdisk --backup=/root/parttable-backup.gpt /dev/mmcblk0

# 2. 删除失败的分区
sgdisk --delete=5 /dev/mmcblk0
sgdisk --delete=6 /dev/mmcblk0
# ... 删除所有新创建的分区

# 3. 重新加载分区表
partprobe /dev/mmcblk0

# 4. 恢复原始分区表（如果需要）
sgdisk --load-backup=/root/parttable-backup.gpt /dev/mmcblk0
```

### 场景 2: 挂载失败

**症状**：系统启动，但 `/pxe_rootfs_a` 等目录未挂载

**恢复步骤**：
```bash
# 1. 检查分区是否存在
lsblk -o NAME,PARTLABEL

# 2. 检查 systemd 单元是否启用
systemctl list-units '*.mount'

# 3. 手动挂载测试
mount PARTLABEL=pxe_rootfs_a /pxe_rootfs_a

# 4. 如果手动挂载成功，重新启用 systemd 单元
systemctl daemon-reload
systemctl enable pxe\x2drootfs\x2da.mount
systemctl start pxe\x2drootfs\x2da.mount
```

### 场景 3: UUID 冲突

**症状**：检测到重复 UUID，分区挂载混乱

**恢复步骤**：
```bash
# 1. 识别冲突的分区
blkid /dev/mmcblk0p5
blkid /dev/mmcblk0p6

# 2. 重新分配 UUID
sgdisk --partition-guid=5:$(uuidgen) /dev/mmcblk0

# 3. 更新 systemd mount 单元
vim /etc/systemd/system/pxe\x2drootfs\x2da.mount
# 修改 What=UUID=新UUID

# 4. 重新加载并挂载
systemctl daemon-reload
systemctl restart pxe\x2drootfs\x2da.mount
```

---

**文档版本**: 1.0
**最后更新**: 2025-03-31
