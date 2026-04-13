# 重构 ubuntu22.04 编译脚本

## 原始需求

任务是重构 ubuntu22.04 的编译脚本，根据 output/log/2026-04-01_19-35-39/build.log 的分析，需要完成以下四项内容：

### 1. 清理内核 defconfig 中无用的驱动配置

**问题**：内核安装时找不到驱动的报错（虽然当前日志中未发现严重报错，但需要清理无用驱动配置）

**需要清理的驱动类别**：
- Realtek WiFi 驱动（rtw88 系列）：src-lite 只使用移远 FC06E，不需要 rtw88/rtw89
- AIC8800 WiFi 驱动：src-lite 不使用
- Intel WiFi 固件（iwlwifi）：src-lite 不使用
- MediaTek WiFi 固件：src-lite 不使用
- NPU/ISP/GPU 相关驱动：src-lite 是无头网关，不需要显示/多媒体硬件

**操作目标**：
- 修改 `kernel-6.1/arch/arm64/configs/rk3562_src2500_3600_defconfig`
- 删除所有非必需驱动的 CONFIG 选项

### 2. 去除 ubuntu22.04/mk-ubuntu-rootfs.sh 中的软件源更新操作

**问题**：更新软件源非常占用时间，且在构建基础系统时已经执行过

**操作目标**：
- 查找并注释/删除 `apt-get update` 相关命令
- 确保不影响后续包安装流程

### 3. 删除除 src-lite 外的其他版型内容

**问题**：保留多余的桌面版本内容，增加维护复杂度

**操作目标**：
- 清理 `ubuntu22.04/mk-ubuntu-rootfs.sh` 中非 src-lite 的分支逻辑
- 清理 `ubuntu22.04/mk-base-ubuntu.sh` 中非 src-lite 的分支逻辑
- 删除或简化 TARGET 相关的条件判断

### 4. 编号跳过了 4（用户可能笔误）

### 5. 更新文档

**操作目标**：
- 完成以上四个内容并经过验收之后
- 更新 `.claude/ubuntu22.04.md` 记忆文件，记录：
  - 简化后的构建流程
  - 删除的驱动列表
  - 优化的构建时间
  - 新的脚本逻辑说明

## 当前分析

### 内核驱动分析

从构建日志中看到安装的驱动模块：

**需要保留的驱动**：
- USB Serial 驱动（ch341, cp210x, ftdi_sio, pl2303, qcserial, sierra 等）：网关可能需要连接 USB 串口设备
- 网络文件系统（cifs, nfs）：网关核心功能
- 基础网络驱动（lib80211 等）：WiFi 基础库

**可以删除的驱动**：
- rtw88 系列（rtw88_8821c, rtw88_8822b, rtw88_8822c 等）：Realtek WiFi 驱动
- aic8800 系列（aic8800_sdio, aic8800_usb）：AIC WiFi 驱动
- pcie_mhi：PCIe MHI 驱动（网关不使用）
- ssb：Broadcom SSB 总线驱动（网关不使用）
- ntfs/ntfs3：NTFS 文件系统（网关不需要）

## 技术栈

- Linux Kernel 6.1 defconfig
- Bash 构建脚本
- Ubuntu 22.04 根文件系统
- Rockchip SDK 构建系统

## 验收标准

1. 内核 defconfig 清理完成，构建日志无驱动缺失报错
2. ubuntu22.04 构建脚本去除软件源更新，构建时间明显缩短
3. 仅保留 src-lite 版型，代码逻辑简化
4. 文档更新完整，准确反映新的构建流程

## 时间节点

- 需求分析：了解当前构建流程和需要清理的内容
- 代码开发：修改 defconfig 和构建脚本
- 测试验证：执行构建，验证优化效果
- 文档更新：更新 .claude/ubuntu22.04.md
