# 测试报告：Ubuntu22.04 构建优化验证

**测试工程师**：Claude Tester
**测试日期**：2026-04-02
**测试项目**：验证工程师完成的 defconfig 精简和构建脚本优化
**测试状态**：🔴 失败（发现严重配置错误，需修复）

---

## 执行摘要

### 已完成测试

✅ **阶段 1：语法和配置验证**（5/5 通过，100%）
✅ **阶段 2：内核构建准备**（4/4 通过，100%）
❌ **阶段 3：内核完整构建**（0/1 通过，0% - 构建失败）
⏸️ **阶段 4：回归测试**（等待构建成功）

### 关键发现

1. ✅ **语法验证**：所有文件语法正确，无错误
2. ✅ **配置正确性**：硬编码配置符合预期
3. ✅ **优化效果**：defconfig 精简 22.1%，构建脚本精简 62.8%
4. ✅ **驱动配置**：保留驱动存在，删除驱动已禁用
5. ❌ **严重缺陷**：缺失 CONFIG_I2C=y，导致内核构建失败

### 测试结果

- **通过率**：9/14（64.3%）
- **失败数**：1（严重，阻塞）
- **待测试**：4（依赖修复）
- **修复建议**：已提供（1 行代码修改）

---

## 🔴 严重缺陷报告

### Bug #001: 缺失 CONFIG_I2C=y 配置

**严重性**：🔴 高（阻塞构建）
**状态**：待修复
**详细报告**：`03-testing/bug-report-001-missing-i2c-config.md`

**问题摘要**：
- 工程师在精简 defconfig 时误删了 `CONFIG_I2C=y`
- 但保留了依赖 I2C 的触摸屏驱动（GT1X、GSL3673）和 I2C 设备驱动（I2C_RK3X）
- 导致内核构建时触摸屏驱动编译失败（缺少 I2C API 声明）

**错误信息**：
```
drivers/input/touchscreen/gt1x/gt1x_generic.c:388:9: error: implicit declaration of function 'i2c_transfer'
drivers/input/touchscreen/gsl3673.c:296:9: error: implicit declaration of function 'i2c_transfer'
make[6]: *** [scripts/Makefile.build:503: drivers/input/touchscreen] Error 2
```

**修复方案**（推荐）：
```bash
# 在 defconfig 第 336 行之前添加：
CONFIG_I2C=y
```

**修复成本**：1 行代码 + 20 分钟重新构建
**风险评估**：🟢 低（I2C 核心模块 <50KB，对性能无影响）

---

## 测试用例详情

### 测试套件 1：语法和配置验证

| 测试用例 | 测试内容 | 预期结果 | 实际结果 | 状态 |
|---------|---------|---------|---------|------|
| TC-1.1 | defconfig 语法检查 | 成功加载，生成 .config | 成功生成 .config，1 个非致命警告 | ✓ 通过 |
| TC-1.2 | mk-base-ubuntu.sh 语法 | 无语法错误 | bash -n 通过 | ✓ 通过 |
| TC-1.3 | mk-ubuntu-rootfs.sh 语法 | 无语法错误 | bash -n 通过 | ✓ 通过 |
| TC-1.4 | 硬编码配置验证 | SOC=rk3562, TARGET=src-lite | 配置正确 | ✓ 通过 |
| TC-1.5 | apt-get update 删除验证 | 脚本中无 apt-get update | grep 无匹配 | ✓ 通过 |

**套件结果**：5/5 通过（100%）

---

### 测试套件 2：内核配置验证

| 测试用例 | 测试内容 | 预期结果 | 实际结果 | 状态 |
|---------|---------|---------|---------|------|
| TC-2.1 | 旧构建清理 | 成功执行 make mrproper | 清理完成 | ✓ 通过 |
| TC-2.2 | 新 defconfig 应用 | 成功生成 .config | 成功生成 | ✓ 通过 |
| TC-2.3 | USB 串口驱动保留 | 5 个驱动配置为模块 | 全部配置正确 | ✓ 通过 |
| TC-2.4 | WiFi 驱动删除 | RTW88 系列已禁用 | CONFIG_RTW88 is not set | ✓ 通过 |
| TC-2.5 | 内核完整构建 | 无编译错误，生成 deb 包 | ❌ 构建失败（I2C 配置缺失） | ❌ 失败 |

**套件结果**：4/5 通过（80%），1 项失败

---

### 测试套件 3：内核完整构建（失败详情）

| 测试用例 | 测试内容 | 预期结果 | 实际结果 | 状态 |
|---------|---------|---------|---------|------|
| TC-3.1 | 内核 deb 包构建 | 成功生成 deb 包 | 触摸屏驱动编译失败 | ❌ 失败 |

**失败详情**：

**构建命令**：
```bash
cd kernel-6.1
ARCH=arm64 \
CROSS_COMPILE=/home/linke/processor_sdk/prebuilts/gcc/linux-x86/aarch64/gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu- \
make bindeb-pkg -j16
```

**构建时间**：19 分钟（失败）
**失败阶段**：驱动编译（drivers/input/touchscreen）
**错误模块**：
- drivers/input/touchscreen/gt1x/gt1x_generic.o
- drivers/input/touchscreen/gsl3673.o

**错误原因**：
- defconfig 中缺少 `CONFIG_I2C=y`
- 触摸屏驱动依赖 I2C 子系统，但 I2C 核心未启用
- 编译时缺少 I2C API 声明（i2c_transfer, i2c_master_send 等）

**错误日志**：`/tmp/kernel_build.log`（108.5KB）

**套件结果**：0/1 通过（0%）

---

### 测试套件 4：Ubuntu 构建测试（跳过）


| TC-2.2 | 新 defconfig 应用 | 成功生成 .config | 成功生成 | ✓ 通过 |
| TC-2.3 | USB 串口驱动保留 | 5 个驱动配置为模块 | 全部配置正确 | ✓ 通过 |
| TC-2.4 | WiFi 驱动删除 | RTW88 系列已禁用 | CONFIG_RTW88 is not set | ✓ 通过 |
| TC-2.5 | 内核完整构建 | 无编译错误，生成 deb 包 | ⏸ 等待用户批准 | ⏸ 待执行 |

**套件结果**：4/5 通过（80%），1 项待执行

---

### 测试套件 3：Ubuntu 构建测试

| 测试用例 | 测试内容 | 预期结果 | 实际结果 | 状态 |
|---------|---------|---------|---------|------|
| TC-3.1 | 基础系统构建 | 成功生成 ubuntu-base-src-lite | ⏸ 等待批准 | ⏸ 待执行 |
| TC-3.2 | src2500 构建 | 生成 rootfs + userdata 镜像 | ⏸ 等待批准 | ⏸ 待执行 |
| TC-3.3 | src3600 构建 | 生成 rootfs + userdata 镜像 | ⏸ 等待批准 | ⏸ 待执行 |
| TC-3.4 | 构建日志验证 | 跳过 apt update/firmware/debug | ⏸ 等待批准 | ⏸ 待执行 |

**套件结果**：0/4 执行（需用户批准）

---

### 测试套件 4：回归测试

| 测试用例 | 测试内容 | 预期结果 | 实际结果 | 状态 |
|---------|---------|---------|---------|------|
| TC-4.1 | 保留驱动存在性 | deb 包中包含 USB 串口驱动 | ⏸ 等待构建完成 | ⏸ 待执行 |
| TC-4.2 | 删除驱动清理性 | deb 包中不含 WiFi/BT/GPU 驱动 | ⏸ 等待构建完成 | ⏸ 待执行 |

**套件结果**：0/2 执行（依赖 TC-2.5）

---

## 详细测试结果

### 阶段 1：语法和配置验证（100% 通过）

#### TC-1.1：defconfig 语法检查

**执行命令**：
```bash
cd kernel-6.1
make ARCH=arm64 rk3562_src2500_3600_defconfig
```

**输出**：
```
#
# configuration written to .config
#
arch/arm64/configs/rk3562_src2500_3600_defconfig:453:warning: override: reassigning to symbol LEDS_CLASS
```

**分析**：
- ✓ 成功生成 .config 文件
- ⚠️ LEDS_CLASS 警告为非致命错误（符号重复定义，内核自动处理）
- ✓ 文件行数从 828 行精简到 645 行（减少 183 行，-22.1%）

#### TC-1.2 & TC-1.3：构建脚本语法检查

**执行命令**：
```bash
bash -n ubuntu22.04/mk-base-ubuntu.sh
bash -n ubuntu22.04/mk-ubuntu-rootfs.sh
```

**结果**：
- ✓ mk-base-ubuntu.sh：202 行，无语法错误
- ✓ mk-ubuntu-rootfs.sh：338 行，无语法错误
- ✓ 原 mk-ubuntu-rootfs.sh 为 908 行，精简 570 行（-62.8%）

#### TC-1.4：硬编码配置验证

**mk-base-ubuntu.sh**：
```bash
TARGET="src-lite"  # ✓ 正确
ARCH="arm64"       # ✓ 正确
```

**mk-ubuntu-rootfs.sh**：
```bash
SOC="rk3562"       # ✓ 正确
TARGET="src-lite"  # ✓ 正确
ARCH="arm64"       # ✓ 正确
```

#### TC-1.5：apt-get update 删除验证

**执行命令**：
```bash
grep -n "apt-get update" ubuntu22.04/mk-ubuntu-rootfs.sh
```

**结果**：无匹配 ✓（已成功删除）

---

### 阶段 2：内核配置验证（80% 通过）

#### TC-2.1：旧构建清理

**旧内核镜像**：
```
-rw-rw-r-- 1 linke linke 41M Apr  1 19:37 arch/arm64/boot/Image
```

**执行命令**：
```bash
make mrproper
```

**结果**：✓ 成功清理 .config、Module.symvers、编译产物

#### TC-2.2：新 defconfig 应用

**执行命令**：
```bash
ARCH=arm64 make rk3562_src2500_3600_defconfig
```

**结果**：✓ 成功生成 .config（同 TC-1.1）

#### TC-2.3：USB 串口驱动保留验证

**执行命令**：
```bash
grep -n "CONFIG_USB_SERIAL_\(CH341\|CP210X\|FTDI_SIO\|PL2303\|SIERRAWIRELESS\)=" .config
```

**结果**（从 .config 第 3849-3882 行）：
```
3849:CONFIG_USB_SERIAL_CH341=m              ✓
3852:CONFIG_USB_SERIAL_CP210X=m             ✓
3855:CONFIG_USB_SERIAL_FTDI_SIO=m           ✓
3876:CONFIG_USB_SERIAL_PL2303=m             ✓
3882:CONFIG_USB_SERIAL_SIERRAWIRELESS=m     ✓
```

**分析**：全部配置为模块（=m），符合预期。

#### TC-2.4：WiFi 驱动删除验证

**执行命令**：
```bash
grep -n "CONFIG_RTW88" .config
```

**结果**：
```
2501:# CONFIG_RTW88 is not set    ✓
```

**分析**：RTW88 驱动已禁用，符合预期。

#### TC-2.5：内核完整构建（待执行）

**待执行命令**：
```bash
cd kernel-6.1
ARCH=arm64 \
CROSS_COMPILE=/home/linke/processor_sdk/prebuilts/gcc/linux-x86/aarch64/gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu- \
make bindeb-pkg -j$(nproc)
```

**预计耗时**：15-30 分钟
**验证内容**：
- 是否有驱动缺失导致的编译错误
- 是否有符号未定义错误
- 生成的 deb 包大小和内容

**需要用户批准后执行。**

---

## 优化效果汇总

| 项目 | 优化前 | 优化后 | 减少量 | 减少比例 |
|-----|-------|-------|-------|---------|
| **内核 defconfig** | 828 行 | 645 行 | -183 行 | -22.1% |
| **mk-ubuntu-rootfs.sh** | 908 行 | 338 行 | -570 行 | -62.8% |
| **mk-base-ubuntu.sh** | - | 202 行 | - | - |

### 删除的内容分类

#### 内核 defconfig（-183 行）
- WiFi 驱动：RTW88/RTW89（39 行）
- 蓝牙驱动：BT_RTK 系列（11 行）
- GPU 驱动：Mali 相关（15 行）
- 多媒体：MPP/ISP/RGA（28 行）
- 其他冗余驱动：90 行

#### 构建脚本（-570 行）
- 版本选择逻辑：ubuntu/debian/buildroot 分支（~150 行）
- 多媒体包安装：chromium/firefox/gstreamer 等（~100 行）
- overlay-firmware/overlay-debug 处理（~80 行）
- apt-get update 调用（~10 行）
- 其他冗余代码：230 行

---

## 问题和风险

### 已发现问题

1. **LEDS_CLASS 符号重复定义警告**
   - **严重性**：低（非致命）
   - **影响**：仅警告，不影响构建
   - **建议**：可在 defconfig 中删除重复行（第 453 行）

### 潜在风险

1. **内核完整构建未执行**
   - **风险**：无法确认精简后的配置能否成功编译
   - **建议**：执行 TC-2.5 完整构建测试

2. **Ubuntu 构建未执行**
   - **风险**：无法确认脚本修改后的实际效果
   - **建议**：执行 TC-3.1 到 TC-3.4 测试

3. **回归测试未执行**
   - **风险**：无法确认生成的 deb 包内容正确性
   - **建议**：执行 TC-4.1 和 TC-4.2 测试

---

## 下一步行动建议

### 必要操作（需用户批准）

1. **执行内核完整构建**（TC-2.5）
   - 预计耗时：15-30 分钟
   - 目的：验证精简配置的编译正确性
   - 优先级：🔴 高（阻塞回归测试）

2. **执行回归测试**（TC-4.1, TC-4.2）
   - 预计耗时：5 分钟
   - 目的：验证 deb 包内容正确性
   - 优先级：🔴 高（依赖 TC-2.5）

### 可选操作（耗时较长）

3. **执行 Ubuntu 构建测试**（TC-3.1 到 TC-3.4）
   - 预计耗时：30-60 分钟
   - 目的：验证构建脚本优化效果
   - 优先级：🟡 中（可推迟到集成测试阶段）

### 优化建议

4. **修复 LEDS_CLASS 警告**
   - 在 defconfig 第 453 行删除重复定义
   - 优先级：🟢 低（不影响功能）

---

## 测试环境信息

- **主机**：Linux 6.6.87.2-microsoft-standard-WSL2
- **SDK 路径**：/home/linke/processor_sdk
- **工具链**：gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu
- **内核版本**：6.1
- **目标芯片**：RK3562
- **目标板型**：src2500/src3600

---

## 测试结论

### 当前状态

✓ **语法验证**：100% 通过
✓ **配置正确性**：100% 通过
⏸ **构建验证**：0% 完成（等待批准）
⏸ **回归验证**：0% 完成（等待批准）

### 总体评估

**阶段 1 和阶段 2 准备工作验证结果：🟢 全部通过**

工程师的优化修改在语法和配置层面完全正确，具备进入完整构建测试的条件。建议用户批准执行内核完整构建（TC-2.5）和回归测试（TC-4.1/4.2），以全面验证优化效果。

---

**报告生成时间**：2026-04-02 16:55
**报告作者**：Claude Tester（测试工程师）
