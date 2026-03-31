# SRC2500 PXE Boot 分区测试指南

**版本**: 1.0
**创建日期**: 2025-03-31
**角色**: Team Workflow - 测试工程师

---

## 快速开始

### 1. 准备工作

**在开发机（Linux PC）上**:
```bash
# 上传测试脚本到 SRC2500 设备
scp /home/linke/processor_sdk/.ai_context/src2500-pxeboot-partition-20250331/03-testing/test-script.sh sr@192.168.192.7:~/
```

**在 SRC2500 设备上**:
```bash
# SSH 登录
ssh sr@192.168.192.7

# 给脚本执行权限
chmod +x ~/test-script.sh
```

---

## 2. 测试执行流程

### 第一次启动测试（烧录新镜像后）

```bash
# SSH 登录到 SRC2500
ssh sr@192.168.192.7

# 运行首次启动测试
sudo ~/test-script.sh --first-boot
```

**预期输出**:
- 显示所有测试项目的通过/失败状态
- 生成测试日志: `/tmp/pxeboot-test-YYYYMMDD-HHMMSS.log`
- 生成测试报告: `/tmp/pxeboot-test-report-YYYYMMDD-HHMMSS.txt`

### 第二次启动测试（验证幂等性）

```bash
# SSH 登录到 SRC2500
ssh sr@192.168.192.7

# 运行幂等性测试
sudo ~/test-script.sh --first-boot
```

**预期输出**:
- 所有测试仍然通过
- 脚本输出包含 "already exist" 消息

### 重启后测试（验证持久化）

```bash
# 重启前创建测试文件
sudo sh -c 'echo "test data" > /pxe_rootfs_a/persistent.txt'

# 重启系统
sudo reboot

# SSH 重新登录
ssh sr@192.168.192.7

# 运行重启验证测试
sudo ~/test-script.sh --reboot
```

**预期输出**:
- 所有分区自动挂载
- 测试文件完整存在
- systemd mount 单元正常工作

---

## 3. 测试文件说明

### 3.1 测试用例文档

**文件**: `test-cases.md`

**内容**:
- 完整的测试用例设计
- 正常场景（4 个用例）
- 边界场景（3 个用例）
- 异常场景（3 个用例）
- 测试步骤和预期结果

**用途**:
- 测试人员参考手册
- 测试计划制定依据

### 3.2 自动化测试脚本

**文件**: `test-script.sh`

**功能**:
- 自动化执行所有验证测试
- 生成详细的测试报告
- 提供清晰的通过/失败输出

**使用方法**:
```bash
# 完整测试套件
./test-script.sh

# 首次启动测试
./test-script.sh --first-boot

# 重启验证测试
./test-script.sh --reboot
```

**测试项目**:
1. 分区存在性检查
2. 分区大小验证
3. 挂载点验证
4. systemd mount 单元验证
5. systemd 初始化服务验证
6. 文件系统可写性测试
7. 分区对齐检查
8. UUID 唯一性检查
9. 脚本语法验证
10. 系统日志检查

### 3.3 测试报告模板

**文件**: `test-results-template.md`

**用途**:
- 记录测试结果
- 填写实际测试数据
- 生成最终测试报告

**使用方法**:
```bash
# 复制模板
cp test-results-template.md test-results-YYYYMMDD.md

# 填写实际测试数据
vim test-results-YYYYMMDD.md
```

---

## 4. 测试结果解读

### 4.1 测试输出示例

```
================================================================================
SRC2500 PXE Boot Partition Automated Test
================================================================================

[INFO] Checking eMMC device...
[INFO] eMMC device: /dev/mmcblk0

--------------------------------------------------------------------------------
TEST 1: Partition Existence Check
--------------------------------------------------------------------------------
[PASS] Partition exists: pxe_rootfs_a
[PASS] Partition exists: pxe_rootfs_b
[PASS] Partition exists: pxe_upper
[PASS] Partition exists: log
[PASS] All required partitions exist

--------------------------------------------------------------------------------
TEST 2: Partition Size Verification
--------------------------------------------------------------------------------
[PASS] pxe_rootfs_a size OK (2.0G, 0% deviation)
[PASS] pxe_rootfs_b size OK (2.0G, 0% deviation)
[PASS] pxe_upper size OK (28.0G, 0% deviation)
[PASS] log partition size: 80G

... (更多测试)

================================================================================
Test Summary
================================================================================
Total Tests:  10
Passed:       10
Failed:       0
Skipped:      0

Pass Rate:    100.0%

All tests passed!

Log file:   /tmp/pxeboot-test-20250331-102530.log
Report:     /tmp/pxeboot-test-report-20250331-102530.txt
```

### 4.2 测试通过标准

- **P0 用例（正常场景）**: 必须全部通过（4/4）
- **P0+P1 用例（正常+边界）**: 至少 80% 通过（≥4/5）
- **P0+P1+P2 用例（所有用例）**: 至少 70% 通过（≥5/7）

### 4.3 常见问题

**问题 1**: 测试脚本权限错误
```
解决方案: chmod +x test-script.sh
```

**问题 2**: 必须以 root 身份运行
```
解决方案: sudo ~/test-script.sh
```

**问题 3**: 分区未找到
```
原因: 首次启动尚未执行
解决方案: 检查 systemd 服务状态
          systemctl status pxeboot-init.service
```

---

## 5. 手动验证命令

### 5.1 快速检查分区

```bash
# 查看分区表
lsblk -o NAME,SIZE,PARTLABEL,MOUNTPOINT

# 查看 PXE 分区
lsblk | grep pxe

# 查看挂载点
mount | grep pxe
```

### 5.2 查看系统日志

```bash
# 查看 pxeboot-init 服务日志
journalctl -u pxeboot-init.service -n 100 --no-pager

# 查看内核日志
dmesg | grep -i mmc
```

### 5.3 验证 systemd 服务

```bash
# 查看 mount 单元状态
systemctl list-units '*.mount' | grep pxe

# 查看 mount 单元详情
systemctl status pxe\x2drootfs\x2da.mount

# 查看 mount 单元文件
cat /etc/systemd/system/pxe\x2drootfs\x2da.mount
```

### 5.4 分区详细信息

```bash
# 查看完整分区表
sgdisk -p /dev/mmcblk0

# 查看 PARTLABEL
ls -la /dev/disk/by-partlabel/

# 查看分区 UUID
sgdisk -p /dev/mmcblk0 | grep -E "(pxe_|log)"
```

---

## 6. 测试报告提交流程

### 6.1 完成测试

1. 执行所有测试用例
2. 收集测试日志和报告
3. 填写测试结果模板

### 6.2 提交报告

```bash
# 收集文件
tar czf pxeboot-test-$(date +%Y%m%d).tar.gz \
    ~/test-script.sh \
    /tmp/pxeboot-test-*.log \
    /tmp/pxeboot-test-report-*.txt

# 复制到开发机
scp pxeboot-test-*.tar.gz linke@192.168.1.100:/path/to/dest/
```

### 6.3 报告内容

- 测试环境信息
- 测试执行记录
- 测试结果统计
- 问题记录（如有）
- 测试结论和建议

---

## 7. 联系支持

**测试过程中遇到问题**:

1. 查阅实现笔记: `02-development/implementation-notes.md`
2. 查阅设计文档: `01-architecture/design.md`
3. 检查系统日志: `journalctl -xe`
4. 联系开发团队

---

## 8. 文件清单

```
03-testing/
├── README.md                    # 本文件
├── test-cases.md                # 测试用例设计
├── test-script.sh               # 自动化测试脚本
└── test-results-template.md     # 测试报告模板
```

---

**文档结束**
