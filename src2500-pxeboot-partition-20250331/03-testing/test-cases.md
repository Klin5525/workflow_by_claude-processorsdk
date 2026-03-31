# SRC2500 PXE Boot 分区脚本测试用例

**文档版本**: 1.0
**创建日期**: 2025-03-31
**作者**: Team Workflow - 测试工程师角色
**状态**: 待执行

---

## 1. 测试环境

### 1.1 硬件环境

- **设备**: SRC2500 (RK3562 + eMMC)
- **eMMC 容量**: 128GB（实际可用约 119GB）
- **网络**: 以太网（192.168.192.7）

### 1.2 软件环境

- **系统**: Ubuntu 22.04 + OverlayFS (SquashFS 根文件系统)
- **访问方式**: SSH (用户名/密码: sr/sr)
- **脚本路径**: `/usr/local/bin/pxeboot-init.sh`
- **systemd 服务**: `pxeboot-init.service`

### 1.3 测试工具

- `lsblk`: 分区表查看
- `sgdisk`: GPT 分区管理
- `mount`: 挂载点检查
- `systemctl`: systemd 服务管理
- `journalctl`: 系统日志查看
- `df`: 磁盘使用情况

---

## 2. 测试用例分类

### 2.1 正常场景 (Normal Cases)

| 用例ID | 用例名称 | 测试目标 | 优先级 |
|--------|---------|---------|--------|
| TC-NORMAL-001 | 首次启动分区创建 | 验证首次启动时正确创建所有 PXE 分区 | P0 |
| TC-NORMAL-002 | 第二次启动幂等性 | 验证第二次启动跳过分区创建 | P0 |
| TC-NORMAL-003 | 重启后持久化 | 验证重启后分区自动挂载 | P0 |
| TC-NORMAL-004 | 分区大小验证 | 验证各分区大小符合设计 | P1 |

### 2.2 边界场景 (Boundary Cases)

| 用例ID | 用例名称 | 测试目标 | 优先级 |
|--------|---------|---------|---------|
| TC-BOUNDARY-001 | 64GB eMMC 容量 | 验证小容量 eMMC 上的分区布局 | P1 |
| TC-BOUNDARY-002 | 128GB eMMC 容量 | 验证标准容量 eMMC 上的分区布局 | P1 |
| TC-BOUNDARY-003 | log 分区动态大小 | 验证 log 分区使用剩余空间 | P2 |

### 2.3 异常场景 (Abnormal Cases)

| 用例ID | 用例名称 | 测试目标 | 优先级 |
|--------|---------|---------|---------|
| TC-ABNORMAL-001 | 部分分区已存在 | 验证分区创建中断后的恢复能力 | P2 |
| TC-ABNORMAL-002 | 分区表损坏 | 验证分区表损坏后的重建 | P2 |
| TC-ABNORMAL-003 | 磁盘空间不足 | 模拟磁盘空间不足场景（可选） | P3 |

---

## 3. 详细测试用例

### 3.1 正常场景

#### TC-NORMAL-001: 首次启动分区创建

**前置条件**:
- 烧录新镜像到 SRC2500 板子
- 首次启动系统
- SSH 登录到 192.168.192.7

**测试步骤**:

1. 检查 systemd 服务状态
   ```bash
   systemctl status pxeboot-init.service
   ```
   预期: 服务执行过一次（退出码 0）

2. 查看服务日志
   ```bash
   journalctl -u pxeboot-init.service -n 100 --no-pager
   ```
   预期: 输出包含 "First boot: creating PXE partitions..."

3. 验证分区创建
   ```bash
   lsblk -o NAME,SIZE,TYPE,PARTLABEL,MOUNTPOINT /dev/mmcblk0
   ```
   预期: 存在以下分区
   - `pxe_rootfs_a`: 约 2GB
   - `pxe_rootfs_b`: 约 2GB
   - `pxe_upper`: 约 28GB
   - `log`: 约 80GB（取决于 eMMC 总容量）

4. 验证 PARTLABEL 符号链接
   ```bash
   ls -la /dev/disk/by-partlabel/ | grep -E "(pxe_|log)"
   ```
   预期: 存在所有 4 个分区的符号链接

5. 验证挂载点
   ```bash
   mount | grep -E "(pxe_|log)"
   df -h | grep -E "(pxe_|log)"
   ```
   预期: 所有 4 个分区均已挂载

6. 验证 systemd mount 单元
   ```bash
   systemctl list-units '*.mount' | grep -E "(pxe|log)"
   ```
   预期: 显示 4 个 active (mounted) 状态的 mount 单元

7. 验证文件系统
   ```bash
   df -h /pxe_rootfs_a /pxe_rootfs_b /pxe_upper /log
   ```
   预期: 显示正确的容量大小

8. 写入测试（可选）
   ```bash
   sudo touch /pxe_rootfs_a/test.txt
   sudo touch /pxe_rootfs_b/test.txt
   sudo touch /pxe_upper/test.txt
   sudo touch /log/test.txt
   ls -la /pxe_*/test.txt /log/test.txt
   ```
   预期: 所有文件创建成功

**预期结果**:
- 所有 PXE 分区创建成功
- 所有分区正确挂载
- systemd mount 单元状态正常
- 文件系统可读写

**实际结果**:
（测试后填写）

**状态**: ☐ 通过 ☐ 失败

---

#### TC-NORMAL-002: 第二次启动幂等性

**前置条件**:
- 已完成 TC-NORMAL-001
- 系统首次启动完成

**测试步骤**:

1. 手动执行初始化脚本
   ```bash
   sudo /usr/local/bin/pxeboot-init.sh
   ```
   预期: 脚本正常退出

2. 检查脚本输出
   预期: 输出包含 "PXE partitions already exist, skipping creation" 和 "Log partition already exist, skipping creation"

3. 验证分区表未变化
   ```bash
   sgdisk -p /dev/mmcblk0 | grep -E "(pxe_|log)"
   ```
   预期: 分区号、大小、UUID 与第一次一致

4. 验证挂载点未变化
   ```bash
   mount | grep -E "(pxe_|log)"
   ```
   预期: 挂载状态与第一次一致

**预期结果**:
- 脚本跳过分区创建
- 分区表无变化
- 不产生错误或警告

**实际结果**:
（测试后填写）

**状态**: ☐ 通过 ☐ 失败

---

#### TC-NORMAL-003: 重启后持久化

**前置条件**:
- 已完成 TC-NORMAL-001
- 所有分区已挂载

**测试步骤**:

1. 创建持久化测试文件
   ```bash
   sudo sh -c 'echo "test data" > /pxe_rootfs_a/persistent.txt'
   sudo sh -c 'echo "test data" > /pxe_rootfs_b/persistent.txt'
   sudo sh -c 'echo "test data" > /pxe_upper/persistent.txt'
   sudo sh -c 'echo "test data" > /log/persistent.txt'
   ```

2. 记录文件 MD5 值
   ```bash
   md5sum /pxe_*/persistent.txt /log/persistent.txt
   ```

3. 重启系统
   ```bash
   sudo reboot
   ```

4. 等待系统重启完成，SSH 重新登录

5. 验证分区自动挂载
   ```bash
   mount | grep -E "(pxe_|log)"
   ```
   预期: 所有分区自动挂载

6. 验证 systemd mount 单元
   ```bash
   systemctl list-units '*.mount' | grep -E "(pxe|log)"
   ```
   预期: 显示 4 个 active (mounted) 状态

7. 验证文件完整性
   ```bash
   md5sum /pxe_*/persistent.txt /log/persistent.txt
   ```
   预期: MD5 值与重启前一致

8. 验证 systemd mount 单元持久化
   ```bash
   ls -la /etc/systemd/system/pxe*.mount /etc/systemd/system/log.mount
   ```
   预期: mount 单元文件存在

**预期结果**:
- 重启后分区自动挂载
- 文件数据完整
- systemd mount 单元持久化

**实际结果**:
（测试后填写）

**状态**: ☐ 通过 ☐ 失败

---

#### TC-NORMAL-004: 分区大小验证

**前置条件**:
- 已完成 TC-NORMAL-001

**测试步骤**:

1. 获取分区详细信息
   ```bash
   lsblk -b -o NAME,SIZE,TYPE,PARTLABEL /dev/mmcblk0 | grep -E "(pxe_|log)"
   ```

2. 计算分区大小（字节转 GB）
   ```bash
   # 预期输出
   # pxe_rootfs_a: 约 2147483648 字节 (2GB)
   # pxe_rootfs_b: 约 2147483648 字节 (2GB)
   # pxe_upper: 约 30064771072 字节 (28GB)
   # log: 约 85899345920 字节 (80GB, 取决于 eMMC 总容量)
   ```

3. 使用 df 检查文件系统容量
   ```bash
   df -h /pxe_rootfs_a /pxe_rootfs_b /pxe_upper /log
   ```
   预期: 显示正确的容量（考虑 ext4 保留空间）

**预期结果**:
- 所有分区大小与设计规格一致（误差 ±5%）

**实际结果**:
（测试后填写）

**状态**: ☐ 通过 ☐ 失败

---

### 3.2 边界场景

#### TC-BOUNDARY-001: 64GB eMMC 容量

**前置条件**:
- 使用 64GB eMMC 的 SRC2500 板子
- 烧录新镜像

**测试步骤**:

1. 执行 TC-NORMAL-001 测试步骤

2. 检查 log 分区大小
   ```bash
   lsblk -o NAME,SIZE,PARTLABEL /dev/mmcblk0 | grep log
   ```
   预期: log 分区约 16GB（64GB - 48GB）

3. 验证分区创建成功
   ```bash
   df -h | grep -E "(pxe_|log)"
   ```

**预期结果**:
- 在小容量 eMMC 上正确创建所有分区
- log 分区使用剩余空间（16GB）

**实际结果**:
（测试后填写）

**状态**: ☐ 通过 ☐ 失败 ☐ 跳过（无 64GB 设备）

---

#### TC-BOUNDARY-002: 128GB eMMC 容量

**前置条件**:
- 使用 128GB eMMC 的 SRC2500 板子（标准配置）
- 烧录新镜像

**测试步骤**:

1. 执行 TC-NORMAL-001 测试步骤

2. 检查 log 分区大小
   ```bash
   lsblk -o NAME,SIZE,PARTLABEL /dev/mmcblk0 | grep log
   ```
   预期: log 分区约 80GB（128GB - 48GB）

**预期结果**:
- 在标准容量 eMMC 上正确创建所有分区
- log 分区使用剩余空间（80GB）

**实际结果**:
（测试后填写）

**状态**: ☐ 通过 ☐ 失败

---

#### TC-BOUNDARY-003: log 分区动态大小

**前置条件**:
- 已完成分区创建

**测试步骤**:

1. 获取 eMMC 总容量
   ```bash
   lsblk -d -o NAME,SIZE /dev/mmcblk0
   ```

2. 获取所有 PXE 分区大小
   ```bash
   lsblk -b -o NAME,SIZE,PARTLABEL /dev/mmcblk0 | grep -E "(pxe_|log)"
   ```

3. 计算 log 分区起始扇区
   ```bash
   sgdisk -p /dev/mmcblk0 | grep log
   ```
   预期: 起始扇区为 0x6000000（48GB）

4. 计算 log 分区结束扇区
   ```bash
   sgdisk -p /dev/mmcblk0 | tail -1
   ```
   预期: 结束扇区等于设备末尾

**预期结果**:
- log 分区始终从 48GB 开始
- log 分区使用到 eMMC 末尾的所有剩余空间

**实际结果**:
（测试后填写）

**状态**: ☐ 通过 ☐ 失败

---

### 3.3 异常场景

#### TC-ABNORMAL-001: 部分分区已存在

**前置条件**:
- 已完成 TC-NORMAL-001
- 系统运行正常

**测试步骤**:

1. 删除部分分区（模拟中断场景）
   ```bash
   sudo sgdisk -d 7 /dev/mmcblk0  # 删除 pxe_upper (假设为 p7)
   sudo partprobe /dev/mmcblk0
   ```

2. 手动执行初始化脚本
   ```bash
   sudo /usr/local/bin/pxeboot-init.sh
   ```

3. 检查脚本输出
   预期: 检测到部分分区缺失，执行创建

4. 验证分区恢复
   ```bash
   lsblk -o NAME,PARTLABEL /dev/mmcblk0 | grep -E "(pxe_|log)"
   ```
   预期: 所有分区恢复

**预期结果**:
- 脚本检测到分区缺失
- 重建缺失的分区
- 已存在的分区不受影响

**实际结果**:
（测试后填写）

**状态**: ☐ 通过 ☐ 失败 ☐ 跳过（破坏性测试）

---

#### TC-ABNORMAL-002: 分区表损坏

**前置条件**:
- 已完成 TC-NORMAL-001
- 备份重要数据

**测试步骤**:

1. 备份当前分区表
   ```bash
   sudo sgdisk -b=/tmp/partition-table.backup /dev/mmcblk0
   ```

2. 清空 GPT 分区表
   ```bash
   sudo sgdisk -Z /dev/mmcblk0
   sudo partprobe /dev/mmcblk0
   ```

3. 重启系统（可选，模拟真实场景）
   ```bash
   sudo reboot
   ```

4. 恢复基础分区（uboot, boot, rootfs, userdata）
   ```bash
   sudo sgdisk -l=/tmp/partition-table.backup /dev/mmcblk0
   ```

5. 手动执行初始化脚本
   ```bash
   sudo /usr/local/bin/pxeboot-init.sh
   ```

6. 验证分区重建
   ```bash
   lsblk -o NAME,PARTLABEL /dev/mmcblk0 | grep -E "(pxe_|log)"
   ```
   预期: 所有 PXE 分区重建成功

**预期结果**:
- 脚本在分区表恢复后能正确创建 PXE 分区
- 不影响前 4 个系统分区

**实际结果**:
（测试后填写）

**状态**: ☐ 通过 ☐ 失败 ☐ 跳过（危险操作）

---

#### TC-ABNORMAL-003: 磁盘空间不足

**前置条件**:
- 需要模拟磁盘空间不足场景（可选）

**测试步骤**:

1. 检查 eMMC 实际容量
   ```bash
   lsblk -d -o NAME,SIZE /dev/mmcblk0
   ```

2. 尝试在小容量 eMMC（如 32GB）上创建分区
   （此测试需要特殊硬件）

3. 观察脚本行为
   预期: sgdisk 报错，脚本退出

**预期结果**:
- 脚本检测到空间不足
- 返回明确的错误信息
- 不破坏现有分区

**实际结果**:
（测试后填写）

**状态**: ☐ 通过 ☐ 失败 ☐ 跳过（无测试条件）

---

## 4. 性能测试（可选）

### TC-PERF-001: 分区创建时间

**测试步骤**:

1. 记录开始时间
   ```bash
   time sudo /usr/local/bin/pxeboot-init.sh
   ```

2. 观察各阶段耗时
   - 分区创建（sgdisk）
   - 格式化（mkfs.ext4）
   - 挂载（systemctl start）

**预期结果**:
- 总耗时 < 60 秒（128GB eMMC）
- 格式化 pxe_upper (28GB) 最耗时

---

## 5. 兼容性测试（可选）

### TC-COMPAT-001: systemd mount 单元命名

**测试步骤**:

1. 验证 mount 单元文件名
   ```bash
   ls -la /etc/systemd/system/ | grep -E "(pxe|log)"
   ```
   预期:
   - `pxe\x2drootfs\x2da.mount`
   - `pxe\x2drootfs\x2db.mount`
   - `pxe\x2dupper.mount`
   - `log.mount`

2. 验证 systemd 单元语法
   ```bash
   systemd-analyze verify /etc/systemd/system/pxe\x2drootfs\x2da.mount
   ```
   预期: 无错误或警告

**预期结果**:
- mount 单元命名符合 systemd 规范
- `-` 正确转义为 `\x2d`

---

## 6. 测试记录模板

### 测试执行记录

| 用例ID | 执行日期 | 执行人 | 结果 | 备注 |
|--------|---------|--------|------|------|
| TC-NORMAL-001 | | | ☐ 通过 ☐ 失败 | |
| TC-NORMAL-002 | | | ☐ 通过 ☐ 失败 | |
| TC-NORMAL-003 | | | ☐ 通过 ☐ 失败 | |
| TC-NORMAL-004 | | | ☐ 通过 ☐ 失败 | |
| TC-BOUNDARY-001 | | | ☐ 通过 ☐ 失败 ☐ 跳过 | |
| TC-BOUNDARY-002 | | | ☐ 通过 ☐ 失败 | |
| TC-BOUNDARY-003 | | | ☐ 通过 ☐ 失败 | |
| TC-ABNORMAL-001 | | | ☐ 通过 ☐ 失败 ☐ 跳过 | |
| TC-ABNORMAL-002 | | | ☐ 通过 ☐ 失败 ☐ 跳过 | |
| TC-ABNORMAL-003 | | | ☐ 通过 ☐ 失败 ☐ 跳过 | |

### 缺陷记录

| 缺陷ID | 用例ID | 缺陷描述 | 严重程度 | 状态 |
|--------|--------|---------|---------|------|
| BUG-001 | | | ☐ 严重 ☐ 一般 ☐ 轻微 | ☐ 开发中 ☐ 已修复 |

---

## 7. 测试通过标准

### 7.1 必须通过的用例（P0）

- TC-NORMAL-001: 首次启动分区创建
- TC-NORMAL-002: 第二次启动幂等性
- TC-NORMAL-003: 重启后持久化

### 7.2 应该通过的用例（P1）

- TC-NORMAL-004: 分区大小验证
- TC-BOUNDARY-001: 64GB eMMC 容量（如有设备）
- TC-BOUNDARY-002: 128GB eMMC 容量

### 7.3 可选通过的用例（P2/P3）

- TC-BOUNDARY-003: log 分区动态大小
- TC-ABNORMAL-001: 部分分区已存在
- TC-ABNORMAL-002: 分区表损坏
- TC-ABNORMAL-003: 磁盘空间不足

### 7.4 整体评估

- **P0 用例通过率**: 100% (3/3)
- **P0+P1 用例通过率**: ≥ 80% (4/5)
- **P0+P1+P2 用例通过率**: ≥ 70% (5/7)

---

## 8. 注意事项

### 8.1 测试安全

- 异常场景测试会修改分区表，执行前务必备份
- 建议在非生产设备上测试异常场景
- 删除分区前记录分区表信息

### 8.2 测试环境

- 确保测试过程中网络连接稳定
- 确保电源供电稳定（避免分区创建过程中断电）
- 测试前关闭其他不必要的系统服务

### 8.3 测试数据

- 测试过程中收集的关键数据应保存
- 建议记录每次测试的时间戳
- 保存测试输出和日志

---

**文档结束**
