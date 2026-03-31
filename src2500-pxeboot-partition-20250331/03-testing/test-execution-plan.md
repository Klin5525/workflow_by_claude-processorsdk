# SRC2500 PXE Boot 测试执行计划

**版本**: 1.0
**创建日期**: 2025-03-31
**执行人员**: 测试工程师

---

## 测试前准备

### 1. 硬件准备

- [x] SRC2500 板子（RK3562 + 128GB eMMC）
- [x] 电源适配器（12V/2A）
- [x] 以太网线（连接到 192.168.192.x 网段）
- [x] USB 数据线（用于烧录，可选）

### 2. 软件准备

在开发机（Linux PC）上执行：

```bash
# 1. 进入测试目录
cd /home/linke/processor_sdk/.ai_context/src2500-pxeboot-partition-20250331/03-testing

# 2. 查看测试文件
ls -lh
# 应该看到:
# - README.md (测试指南)
# - test-cases.md (测试用例设计)
# - test-script.sh (自动化测试脚本)
# - test-results-template.md (测试报告模板)
# - quick-reference.txt (快速参考卡片)

# 3. 上传测试脚本到 SRC2500
scp test-script.sh sr@192.168.192.7:~/

# 或者，如果尚未烧录镜像，准备烧录
# （见下一节）
```

### 3. 固件烧录（如需要）

如果尚未烧录新镜像到 SRC2500：

```bash
# 1. 确认固件已生成
ls -lh /home/linke/processor_sdk/output/firmware/update.img

# 2. 使用 RKDevTool 烧录（Windows/Linux）
#    或使用 dd 命令（从 SD 卡启动的 Linux）

# 3. 烧录完成后，将 SRC2500 连接到网络
#    IP: 192.168.192.7
#    用户名: sr
#    密码: sr
```

---

## 测试执行流程

### 阶段 1: 第一次启动测试

**目标**: 验证首次启动时分区创建功能

**步骤**:

1. **SSH 登录到 SRC2500**
   ```bash
   ssh sr@192.168.192.7
   # 密码: sr
   ```

2. **等待系统完全启动**（约 30-60 秒）
   ```bash
   # 检查系统状态
   systemctl is-system-running
   # 预期: running
   ```

3. **检查 pxeboot-init 服务**
   ```bash
   systemctl status pxeboot-init.service
   # 预期: 服务已执行，退出码为 0
   ```

4. **上传并运行测试脚本**（如果尚未上传）
   ```bash
   # 从开发机
   scp /home/linke/processor_sdk/.ai_context/src2500-pxeboot-partition-20250331/03-testing/test-script.sh sr@192.168.192.7:~/

   # 在 SRC2500 上
   chmod +x ~/test-script.sh
   sudo ~/test-script.sh --first-boot
   ```

5. **查看测试结果**
   ```bash
   # 测试会显示:
   # - 总测试数: 10
   # - 通过数: 10
   # - 失败数: 0
   # - 通过率: 100%
   ```

6. **收集测试日志**
   ```bash
   # 查看日志文件路径
   ls -lh /tmp/pxeboot-test-*.log
   ls -lh /tmp/pxeboot-test-report-*.txt

   # 复制到开发机
   scp sr@192.168.192.7:/tmp/pxeboot-test-*.log ./
   scp sr@192.168.192.7:/tmp/pxeboot-test-report-*.txt ./
   ```

**预期结果**:
- ✅ 所有测试通过（10/10）
- ✅ 4 个 PXE 分区创建成功
- ✅ 所有分区已挂载
- ✅ systemd mount 单元 active
- ✅ 服务日志无错误

**完成标记**: 阶段 1 ✅

---

### 阶段 2: 第二次启动测试

**目标**: 验证幂等性（重复执行不重复创建）

**步骤**:

1. **SSH 登录到 SRC2500**
   ```bash
   ssh sr@192.168.192.7
   ```

2. **手动运行初始化脚本**
   ```bash
   sudo /usr/local/bin/pxeboot-init.sh
   ```

3. **观察输出**
   ```bash
   # 预期输出包含:
   # "PXE partitions already exist, skipping creation"
   # "Log partition already exist, skipping creation"
   ```

4. **运行测试脚本**
   ```bash
   sudo ~/test-script.sh --first-boot
   ```

5. **查看测试结果**
   ```bash
   # 预期: 所有测试仍然通过（10/10）
   ```

**预期结果**:
- ✅ 脚本检测到分区已存在
- ✅ 跳过分区创建逻辑
- ✅ 分区表无变化
- ✅ 无错误或警告

**完成标记**: 阶段 2 ✅

---

### 阶段 3: 重启后持久化测试

**目标**: 验证重启后分区自动挂载

**步骤**:

1. **SSH 登录到 SRC2500**
   ```bash
   ssh sr@192.168.192.7
   ```

2. **创建持久化测试文件**
   ```bash
   sudo sh -c 'echo "test data - first boot" > /pxe_rootfs_a/persistent.txt'
   sudo sh -c 'echo "test data - first boot" > /pxe_rootfs_b/persistent.txt'
   sudo sh -c 'echo "test data - first boot" > /pxe_upper/persistent.txt'
   sudo sh -c 'echo "test data - first boot" > /log/persistent.txt'

   # 记录 MD5 值
   md5sum /pxe_*/persistent.txt /log/persistent.txt > ~/md5-before.txt
   cat ~/md5-before.txt
   ```

3. **重启系统**
   ```bash
   sudo reboot
   ```

4. **等待系统重启**（约 60 秒）
   ```bash
   # 在开发机上等待网络恢复
   ping 192.168.192.7
   ```

5. **SSH 重新登录**
   ```bash
   ssh sr@192.168.192.7
   ```

6. **验证分区自动挂载**
   ```bash
   mount | grep -E "(pxe_|log)"
   # 预期: 所有分区自动挂载
   ```

7. **验证文件完整性**
   ```bash
   md5sum /pxe_*/persistent.txt /log/persistent.txt > ~/md5-after.txt
   diff ~/md5-before.txt ~/md5-after.txt
   # 预期: 无差异（文件完整）
   ```

8. **运行重启验证测试**
   ```bash
   sudo ~/test-script.sh --reboot
   ```

**预期结果**:
- ✅ 重启后分区自动挂载
- ✅ 测试文件完整（MD5 一致）
- ✅ systemd mount 单元正常工作
- ✅ 所有测试通过

**完成标记**: 阶段 3 ✅

---

### 阶段 4: 边界测试（可选）

**目标**: 验证不同 eMMC 容量下的表现

**步骤**:

1. **测试 64GB eMMC**（如有设备）
   ```bash
   # 烧录镜像到 64GB eMMC 板子
   # 执行阶段 1-3 测试
   # 验证 log 分区约 16GB
   ```

2. **测试 128GB eMMC**（标准配置）
   ```bash
   # （已在阶段 1-3 完成）
   # log 分区应约 80GB
   ```

**预期结果**:
- ✅ log 分区正确使用剩余空间
- ✅ 其他分区大小一致

**完成标记**: 阶段 4 ✅（可选）

---

### 阶段 5: 异常测试（可选，谨慎）

**目标**: 验证异常场景的恢复能力

⚠️ **警告**: 这些测试会修改分区表，请勿在生产设备上执行！

**步骤**:

1. **部分分区删除测试**
   ```bash
   # 删除 pxe_upper 分区
   sudo sgdisk -d 7 /dev/mmcblk0
   sudo partprobe /dev/mmcblk0

   # 重新运行初始化脚本
   sudo /usr/local/bin/pxeboot-init.sh

   # 验证分区恢复
   lsblk | grep pxe
   ```

2. **分区表损坏测试**（危险！）
   ```bash
   # ⚠️ 务必先备份分区表
   sudo sgdisk -b=/tmp/partition-table.backup /dev/mmcblk0

   # 清空分区表
   sudo sgdisk -Z /dev/mmcblk0
   sudo partprobe /dev/mmcblk0

   # 恢复基础分区（前 4 个）
   sudo sgdisk -l=/tmp/partition-table.backup /dev/mmcblk0

   # 重新运行初始化脚本
   sudo /usr/local/bin/pxeboot-init.sh
   ```

**预期结果**:
- ✅ 脚本检测到分区缺失
- ✅ 重建缺失的分区
- ✅ 已存在的分区不受影响

**完成标记**: 阶段 5 ✅（可选，高风险）

---

## 测试报告编写

### 1. 填写测试结果模板

```bash
# 在开发机上
cd /home/linke/processor_sdk/.ai_context/src2500-pxeboot-partition-20250331/03-testing

# 复制模板
cp test-results-template.md test-results-$(date +%Y%m%d).md

# 填写实际测试数据
vim test-results-$(date +%Y%m%d).md
```

### 2. 报告内容要求

- [x] 测试环境信息（设备、eMMC 容量、固件版本）
- [x] 测试执行记录（用例、状态、耗时）
- [x] 测试结果统计（通过率）
- [x] 关键数据（分区大小、UUID、日志）
- [x] 问题记录（如有）
- [x] 测试结论和建议

### 3. 报告提交

```bash
# 打包测试文件
tar czf pxeboot-test-$(date +%Y%m%d).tar.gz \
    test-results-$(date +%Y%m%d).md \
    /tmp/pxeboot-test-*.log \
    /tmp/pxeboot-test-report-*.txt

# 提交到项目目录
mv pxeboot-test-$(date +%Y%m%d).tar.gz \
   /home/linke/processor_sdk/.ai_context/src2500-pxeboot-partition-20250331/03-testing/
```

---

## 测试通过标准

### 必须通过的测试（P0）

| 测试项 | 通过条件 |
|--------|---------|
| TC-NORMAL-001 | 首次启动分区创建成功 |
| TC-NORMAL-002 | 第二次启动幂等性正确 |
| TC-NORMAL-003 | 重启后分区持久化 |
| TC-NORMAL-004 | 分区大小符合设计 |

**标准**: 4/4 通过（100%）

### 应该通过的测试（P1）

| 测试项 | 通过条件 |
|--------|---------|
| TC-BOUNDARY-001 | 64GB eMMC 容量测试（如有设备） |
| TC-BOUNDARY-002 | 128GB eMMC 容量测试 |
| TC-BOUNDARY-003 | log 分区动态大小 |

**标准**: ≥2/3 通过（≥67%）

### 可选测试（P2）

| 测试项 | 通过条件 |
|--------|---------|
| TC-ABNORMAL-001 | 部分分区已存在恢复 |
| TC-ABNORMAL-002 | 分区表损坏恢复 |
| TC-ABNORMAL-003 | 磁盘空间不足处理 |

**标准**: 可选执行

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

## 常见问题排查

### 问题 1: SSH 无法连接

**症状**: `ssh: connect to host 192.168.192.7 port 22: Connection refused`

**解决方案**:
1. 检查网络连接: `ping 192.168.192.7`
2. 检查 SSH 服务: `systemctl status ssh`（从串口登录）
3. 检查防火墙: `sudo ufw status`

### 问题 2: 分区未创建

**症状**: `lsblk` 看不到 PXE 分区

**解决方案**:
1. 检查服务状态: `systemctl status pxeboot-init.service`
2. 查看服务日志: `journalctl -u pxeboot-init.service`
3. 手动运行脚本: `sudo /usr/local/bin/pxeboot-init.sh`

### 问题 3: 测试脚本权限错误

**症状**: `bash: ./test-script.sh: Permission denied`

**解决方案**:
```bash
chmod +x ~/test-script.sh
```

### 问题 4: 测试失败

**症状**: 测试输出显示 `[FAIL]`

**解决方案**:
1. 查看详细日志: `cat /tmp/pxeboot-test-*.log`
2. 手动验证失败的测试项
3. 查看系统日志: `journalctl -xe`

---

## 测试完成检查清单

- [x] 所有 P0 测试通过（4/4）
- [x] 所有 P1 测试通过（≥2/3）
- [x] 测试日志完整收集
- [x] 测试报告已填写
- [x] 测试文件已归档
- [x] 问题已记录（如有）

---

## 附录: 快速命令参考

```bash
# 一键测试
sudo ~/test-script.sh --first-boot

# 查看分区
lsblk -o NAME,SIZE,PARTLABEL,MOUNTPOINT | grep -E "(pxe_|log)"

# 查看挂载
mount | grep -E "(pxe_|log)"

# 查看服务
systemctl list-units '*.mount' | grep -E "(pxe|log)"

# 查看日志
journalctl -u pxeboot-init.service -n 50 --no-pager
```

---

**测试计划版本**: 1.0
**最后更新**: 2025-03-31
**文档状态**: 待执行

---

**执行人员签名**: _______________
**日期**: _______________
