# SRC2500 PXE Boot 分区测试方案 - 总结

**创建日期**: 2025-03-31
**角色**: Team Workflow - 测试工程师
**状态**: 已完成，待执行

---

## 测试方案概述

为 SRC2500 PXE Boot 分区初始化脚本（`pxeboot-init.sh`）设计了完整的测试方案，包括测试用例、自动化脚本、执行计划和报告模板。

---

## 交付物清单

### 1. 核心测试文档

| 文件名 | 大小 | 行数 | 描述 |
|--------|------|------|------|
| `test-cases.md` | 15KB | 640 | 完整测试用例设计（10 个用例） |
| `test-script.sh` | 17KB | 604 | 自动化测试脚本（10 个测试函数） |
| `test-results-template.md` | 13KB | 461 | 测试报告模板 |
| `test-execution-plan.md` | 11KB | 481 | 测试执行计划（5 个阶段） |
| `README.md` | 6.7KB | 335 | 测试指南 |
| `quick-reference.txt` | 2.9KB | 137 | 快速参考卡片 |
| **总计** | **68KB** | **2658** | **6 个文件** |

---

## 测试覆盖范围

### 正常场景（4 个用例）

1. **TC-NORMAL-001**: 首次启动分区创建
   - 验证 4 个 PXE 分区创建
   - 验证分区大小符合设计
   - 验证挂载点正常

2. **TC-NORMAL-002**: 第二次启动幂等性
   - 验证跳过分区创建
   - 验证分区表无变化

3. **TC-NORMAL-003**: 重启后持久化
   - 验证分区自动挂载
   - 验证文件数据完整

4. **TC-NORMAL-004**: 分区大小验证
   - 验证各分区大小精度
   - 验证 log 分区动态分配

### 边界场景（3 个用例）

1. **TC-BOUNDARY-001**: 64GB eMMC 容量测试
2. **TC-BOUNDARY-002**: 128GB eMMC 容量测试
3. **TC-BOUNDARY-003**: log 分区动态大小验证

### 异常场景（3 个用例）

1. **TC-ABNORMAL-001**: 部分分区已存在恢复
2. **TC-ABNORMAL-002**: 分区表损坏恢复
3. **TC-ABNORMAL-003**: 磁盘空间不足处理

---

## 自动化测试脚本功能

### 核心功能

- ✅ 分区存在性检查
- ✅ 分区大小验证（±5% 误差）
- ✅ 挂载点状态验证
- ✅ systemd mount 单元验证
- ✅ systemd 初始化服务验证
- ✅ 文件系统可写性测试
- ✅ 分区对齐检查（1MB 对齐）
- ✅ UUID 唯一性检查
- ✅ 脚本语法验证
- ✅ 系统日志收集

### 测试模式

```bash
./test-script.sh              # 完整测试套件（10 个测试）
./test-script.sh --first-boot # 首次启动测试
./test-script.sh --reboot     # 重启验证测试
```

### 输出文件

- 测试日志: `/tmp/pxeboot-test-YYYYMMDD-HHMMSS.log`
- 测试报告: `/tmp/pxeboot-test-report-YYYYMMDD-HHMMSS.txt`
- 系统日志: `/tmp/pxeboot-test-YYYYMMDD-HHMMSS.journal`

---

## 测试执行流程

### 阶段 1: 第一次启动测试（约 15 分钟）

**目标**: 验证首次启动时分区创建功能

**步骤**:
1. SSH 登录到 SRC2500 (192.168.192.7)
2. 等待系统完全启动
3. 检查 pxeboot-init 服务状态
4. 运行测试脚本: `sudo ~/test-script.sh --first-boot`
5. 收集测试日志和报告

**预期结果**: 10/10 测试通过

### 阶段 2: 第二次启动测试（约 5 分钟）

**目标**: 验证幂等性

**步骤**:
1. 手动运行初始化脚本
2. 观察输出（应包含 "already exist"）
3. 运行测试脚本验证

**预期结果**: 分区表无变化，无错误

### 阶段 3: 重启后持久化测试（约 10 分钟）

**目标**: 验证重启后分区自动挂载

**步骤**:
1. 创建持久化测试文件
2. 记录 MD5 值
3. 重启系统
4. 验证文件完整性
5. 运行重启验证测试

**预期结果**: 分区自动挂载，数据完整

### 阶段 4: 边界测试（约 20 分钟，可选）

**目标**: 验证不同 eMMC 容量下的表现

**测试项**:
- 64GB eMMC（log 分区 16GB）
- 128GB eMMC（log 分区 80GB）

### 阶段 5: 异常测试（约 30 分钟，可选，高风险）

**目标**: 验证异常场景的恢复能力

**测试项**:
- 部分分区删除后的恢复
- 分区表损坏后的重建

⚠️ **警告**: 仅在非生产设备上执行

---

## 测试通过标准

### P0 用例（必须通过）

- TC-NORMAL-001: 首次启动分区创建 ✅
- TC-NORMAL-002: 第二次启动幂等性 ✅
- TC-NORMAL-003: 重启后持久化 ✅
- TC-NORMAL-004: 分区大小验证 ✅

**标准**: 4/4 通过（100%）

### P1 用例（应该通过）

- TC-BOUNDARY-001: 64GB eMMC 测试
- TC-BOUNDARY-002: 128GB eMMC 测试
- TC-BOUNDARY-003: log 分区动态大小

**标准**: ≥2/3 通过（≥67%）

### P2 用例（可选）

- TC-ABNORMAL-001: 部分分区恢复
- TC-ABNORMAL-002: 分区表损坏恢复
- TC-ABNORMAL-003: 磁盘空间不足

**标准**: 可选执行

---

## 关键验证点

### 分区布局验证

```
分区名          大小   起始扇区    挂载点
pxe_rootfs_a    2GB    0x2000000   /pxe_rootfs_a
pxe_rootfs_b    2GB    0x2400000   /pxe_rootfs_b
pxe_upper       28GB   0x2800000   /pxe_upper
log             剩余   0x6000000   /log
```

### systemd mount 单元

```
pxe\x2drootfs\x2da.mount → /pxe_rootfs_a
pxe\x2drootfs\x2db.mount → /pxe_rootfs_b
pxe\x2dupper.mount       → /pxe_upper
log.mount                → /log
```

### UUID 验证

```
pxe_rootfs_a: 614e0000-0000-4b53-8000-1d28000054c0
pxe_rootfs_b: 614e0000-0000-4b53-8000-1d28000054c1
pxe_upper:    614e0000-0000-4b53-8000-1d28000054c2
log:          614e0000-0000-4b53-8000-1d28000054c8
```

---

## 快速开始

### 在开发机上

```bash
# 1. 进入测试目录
cd /home/linke/processor_sdk/.ai_context/src2500-pxeboot-partition-20250331/03-testing

# 2. 上传测试脚本到 SRC2500
scp test-script.sh sr@192.168.192.7:~/
```

### 在 SRC2500 设备上

```bash
# 1. SSH 登录
ssh sr@192.168.192.7

# 2. 运行测试（首次启动后）
sudo ~/test-script.sh --first-boot
```

### 预期输出

```
================================================================================
SRC2500 PXE Boot Partition Automated Test
================================================================================

[PASS] Partition exists: pxe_rootfs_a
[PASS] Partition exists: pxe_rootfs_b
[PASS] Partition exists: pxe_upper
[PASS] Partition exists: log
[PASS] All required partitions exist
... (更多测试)

================================================================================
Test Summary
================================================================================
Total Tests:  10
Passed:       10
Failed:       0
Pass Rate:    100.0%

All tests passed!
```

---

## 测试文档结构

```
03-testing/
├── README.md                    # 测试指南（从这里开始）
├── quick-reference.txt          # 快速参考卡片
├── test-cases.md                # 测试用例设计
├── test-script.sh               # 自动化测试脚本
├── test-execution-plan.md       # 测试执行计划
├── test-results-template.md     # 测试报告模板
└── TESTING_SUMMARY.md           # 本文件
```

---

## 测试时间估算

| 阶段 | 测试项 | 预计耗时 |
|------|--------|----------|
| 准备工作 | 烧录镜像、网络配置 | 30 分钟 |
| 阶段 1 | 第一次启动测试 | 15 分钟 |
| 阶段 2 | 第二次启动测试 | 5 分钟 |
| 阶段 3 | 重启后持久化测试 | 10 分钟 |
| 阶段 4 | 边界测试（可选） | 20 分钟 |
| 阶段 5 | 异常测试（可选） | 30 分钟 |
| 报告编写 | 填写测试报告 | 30 分钟 |
| **总计** | | **~2.5 小时** |

---

## 后续行动

### 立即行动（测试人员）

1. 阅读 `README.md` 了解测试流程
2. 阅读 `test-execution-plan.md` 了解执行步骤
3. 等待镜像烧录完成
4. 按照执行计划执行测试
5. 填写测试报告模板

### 参考文档

- **设计文档**: `01-architecture/design.md`
- **实现笔记**: `02-development/implementation-notes.md`
- **测试指南**: `03-testing/README.md`

---

## 总结

已为 SRC2500 PXE Boot 分区初始化脚本设计完成全面的测试方案，包括：

✅ 10 个详细测试用例（正常、边界、异常）
✅ 功能完整的自动化测试脚本（10 个测试函数）
✅ 清晰的测试执行计划（5 个阶段）
✅ 完整的测试报告模板
✅ 便于快速参考的卡片和指南

测试方案准备就绪，等待镜像烧录后即可执行测试。

---

**文档版本**: 1.0
**创建日期**: 2025-03-31
**创建角色**: Team Workflow - 测试工程师
**状态**: 已完成，待执行

---

**文档结束**
