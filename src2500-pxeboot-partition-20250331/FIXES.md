# 问题修复记录

## 问题 1: systemd mount 单元文件名错误

### 问题描述
- **现象**: 分区已创建并格式化，但无法挂载
- **错误信息**: `Unit pxex2drootfsx2da.mount has a bad unit file setting`

### 根本原因
systemd mount 单元的文件名应该从**挂载路径**（Where）转换，而不是从**分区名**（PARTLABEL）转换。

### 错误做法
```bash
# 从分区名转换（错误）
MOUNT_UNIT="${PART_NAME//-/\\x2d}.mount"
# pxe_rootfs_a → pxe\x2drootfs\x2da.mount
```

### 正确做法
```bash
# 从挂载路径转换
MOUNT_POINT="/pxe_src2500/${PART_NAME#pxe_}"
MOUNT_UNIT="$(echo $MOUNT_POINT | sed 's/^\///;s/\//-/g').mount"
# /pxe_src2500/rootfs_a → pxe_src2500-rootfs_a.mount
```

### 修复后的文件名
| 分区名 | 挂载路径 | mount 单元文件名 |
|--------|---------|----------------|
| pxe_rootfs_a | /pxe_src2500/rootfs_a | pxe_src2500-rootfs_a.mount |
| pxe_rootfs_b | /pxe_src2500/rootfs_b | pxe_src2500-rootfs_b.mount |
| pxe_upper | /pxe_src2500/upper | pxe_src2500-upper.mount |
| log | /log | log.mount |

### 验证结果
- ✅ 所有分区成功挂载
- ✅ 重启后自动挂载正常
- ✅ systemd mount 单元已启用

---

## 问题 2: 分区未格式化

### 问题描述
- **现象**: lsblk 显示分区已创建，但 df -h 无挂载点
- **原因**: 之前的测试只创建了分区，未格式化

### 解决方案
手动格式化缺失的分区：
```bash
sudo mkfs.ext4 -F -L pxe_rootfs_b /dev/mmcblk0p6
sudo mkfs.ext4 -F -L pxe_upper /dev/mmcblk0p7
```

### 脚本改进
后续版本会在创建分区后立即格式化，避免此问题。

---

## 技术要点总结

### systemd mount 单元命名规则
1. 文件名 = 挂载路径的转换（`/` → `-`）
2. 例如：`/mnt/data` → `mnt-data.mount`
3. 路径中包含 `-` 时需转义为 `\x2d`

### 分区挂载流程
1. 使用 sgdisk 创建分区（设置 PARTLABEL）
2. 使用 mkfs.ext4 格式化
3. 创建挂载点目录（`mkdir -p`）
4. 创建 systemd mount 单元（文件名从路径转换）
5. 启用并启动 mount 单元（`systemctl enable/start`）

### 使用 PARTLABEL 的好处
- 设备无关：分区号变化不影响挂载
- 稳定可靠：基于分区标签而非设备路径
- 易于维护：重划分分区表后无需修改配置
