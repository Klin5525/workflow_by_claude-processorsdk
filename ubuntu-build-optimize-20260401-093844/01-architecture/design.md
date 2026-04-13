# 架构设计 - Ubuntu 构建流程优化

## 需求分析

### 当前痛点
1. **重复下载安装 APT 包**：每次修改 overlay/overlay-board 后，重新执行 `mk-ubuntu-rootfs.sh` 会重新下载和安装所有包
2. **重复安装内核包**：每次修改 overlay 都要重新安装内核 deb 包
3. **binary 目录权限问题**：binary 是 root 用户，删除需要 sudo

### 期望目标
1. 将 APT 包安装前置到 `mk-base-ubuntu.sh`（一次性操作）
2. `mk-ubuntu-rootfs.sh` 只应用 overlay，不重复安装包
3. 只在内核重新编译时才重新安装内核包
4. 解决 binary 目录权限问题，避免频繁使用 sudo

## 当前构建流程分析

### mk-base-ubuntu.sh（Step 1）
**当前安装的包**：
```bash
# 基础系统
rsyslog, sudo, dialog, apt-utils, ntp, evtest, acpid

# 网络基础
net-tools, openssh-server, ifupdown, network-manager, inetutils-ping

# 工具
telnet, tcpdump, strace, iperf3, ethtool, netplan.io, htop, pciutils, usbutils, curl
bash-completion, gdisk, parted

# 字体
ttf-wqy-zenhei, xfonts-intl-chinese
```

### mk-ubuntu-rootfs.sh（Step 2 - src-lite）
**重复安装的包**：
```bash
# 调试工具
bash-completion, htop, tree, vim

# 网络工具
iputils-ping, mtr, wget, rsync

# 防火墙
ufw, iptables, firewalld

# WiFi 管理（重复！）
hostapd, wpasupplicant, dbus, iw, wireless-tools, rfkill, dnsmasq

# 系统服务（重复！）
openssh-server, nfs-kernel-server, systemd-timesyncd

# OverlayFS
overlayroot, initramfs-tools, e2fsprogs

# packages deb 包
/packages/wifi-driver/*.deb
/packages/rktoolkit/*.deb
```

**重复安装内核包**：
```bash
${APT_INSTALL} /boot/kerneldeb/*
```

### binary 目录权限问题
```bash
drwxrwxr-x 17 root  root  4096 Mar 31 18:36 binary
```
- binary 目录由 `sudo tar -xpf` 创建，所有者是 root
- 每次删除需要 `sudo rm -rf binary`

## 技术选型

### 方案 A：完全分离包安装（推荐）
**描述**：
- 将所有 APT 包安装移到 `mk-base-ubuntu.sh`
- `mk-ubuntu-rootfs.sh` 只应用 overlay 和生成镜像
- 使用增量检测机制跳过已安装的内核包

**优点**：
- 修改 overlay 后重新构建速度极快（无 APT 操作）
- 构建时间从 10-15 分钟降至 1-2 分钟
- 包安装和配置分离，逻辑清晰

**缺点**：
- 需要仔细拆分两个脚本的包列表
- 初次 `mk-base-ubuntu.sh` 时间增加（但只运行一次）

### 方案 B：APT 缓存机制
**描述**：
- 在宿主机配置 APT 缓存代理（apt-cacher-ng）
- chroot 中使用缓存代理下载包

**优点**：
- 无需修改现有脚本逻辑
- 重复下载时从本地缓存读取

**缺点**：
- 仍然需要执行 `apt-get install`（解压、配置时间）
- 需要额外安装和配置 apt-cacher-ng
- 复杂度增加

### 方案 C：Docker 容器化
**描述**：
- 使用 Docker 容器构建，layer 缓存机制

**优点**：
- Docker layer caching 自动处理
- 环境隔离，不污染宿主机

**缺点**：
- 需要重写整个构建流程
- 引入 Docker 依赖
- 与现有脚本不兼容

### **选择方案 A**
**理由**：
1. 最符合用户需求："把需要安装的包放在前面脚本里安装"
2. 修改 overlay 后无需重复 APT 操作，构建速度提升显著
3. 不引入额外依赖（apt-cacher-ng、Docker）
4. 保持与现有构建系统的兼容性

## 系统架构

### 优化后的构建流程

```
┌─────────────────────────────────────────────────────────────────┐
│ Step 1: mk-base-ubuntu.sh（首次运行或修改包列表时）               │
├─────────────────────────────────────────────────────────────────┤
│ 1. 下载 ubuntu-base-22.04.5-base-arm64.tar.gz                   │
│ 2. 解压到 binary/                                                │
│ 3. chroot 安装所有 APT 包（包括网络、工具、WiFi 驱动等）         │
│ 4. 安装内核 deb 包                                               │
│ 5. 打包为 ubuntu-base-src-lite-arm64-DATE.tar.gz                │
│ 6. 清理 binary/                                                  │
│                                                                  │
│ 输出: ubuntu-base-src-lite-arm64-DATE.tar.gz（包含所有包）       │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ Step 2: mk-ubuntu-rootfs.sh（频繁执行）                          │
├─────────────────────────────────────────────────────────────────┤
│ 1. 解压 ubuntu-base-src-lite-arm64-*.tar.gz 到 binary/           │
│ 2. 应用 overlay/                                                 │
│ 3. 应用 overlay-$BOARD/                                          │
│ 4. 【可选】检测内核变化，仅在变化时安装内核包                     │
│ 5. 生成 initramfs                                                │
│ 6. 打包 SquashFS 镜像                                            │
│ 7. 清理 binary/                                                  │
│                                                                  │
│ 输出: ubuntu-rk3562-src-lite-rootfs.img                         │
└─────────────────────────────────────────────────────────────────┘
```

### 内核包缓存机制

```
检测逻辑:
  if [ 新内核 deb 包存在 ] && [ 新内核 md5 != 旧内核 md5 ]; then
      安装新内核包
      更新内核缓存标记
  else
      跳过内核安装（使用已安装的版本）
  fi

实现方式:
  1. 在 binary/ 中创建 .kernel_cache_marker 文件
  2. 记录已安装内核的 md5 值
  3. 每次构建前检查 ../linux-headers-* 和 ../linux-image-* 的 md5
```

### binary 目录权限修复

**问题根源**：
```bash
# mk-ubuntu-rootfs.sh line 198
sudo rm -rf $TARGET_ROOTFS_DIR
sudo tar -xpf ubuntu-base-$TARGET-$ARCH-*.tar.gz
```
- `sudo tar -xpf` 创建的文件所有者是 root:root
- 这是正常的，因为最终 rootfs 需要文件所有者是 root

**解决方案**：
```bash
# 在 mk-ubuntu-rootfs.sh 中修改
# 方案 1: 使用 --same-owner（不推荐，会破坏 rootfs）
# 方案 2: 清理时使用 sudo，但不需要输密码（推荐）

# 配置 sudo 免密码（仅需一次）
echo "$USER ALL=(ALL) NOPASSWD: /bin/rm -rf /home/linke/processor_sdk/ubuntu22.04/binary" | sudo tee /etc/sudoers.d/binary-clean

# 或者使用更通用的配置
echo "$USER ALL=(ALL) NOPASSWD: /usr/bin/rm" | sudo tee /etc/sudoers.d/nopasswd-rm
```

**更好的方案**：不需要改权限
- binary 是 root 是**正确**的，因为最终 rootfs 内文件必须属于 root
- 只需配置 sudo 免密码删除特定目录
- 这与板子上需要 sudo 无关（板子上 sudo 是因为 sr 用户不在 root 组）

## 模块划分

### 模块 1: mk-base-ubuntu.sh 改造
**职责**：安装所有 APT 包

**需要移入的包**（从 mk-ubuntu-rootfs.sh）：
```bash
# src-lite 需要的所有包
bash-completion, htop, tree, vim
iputils-ping, mtr, wget, rsync
ufw, iptables, firewalld
hostapd, wpasupplicant, dbus, iw, wireless-tools, rfkill, dnsmasq
openssh-server, nfs-kernel-server, systemd-timesyncd
overlayroot, initramfs-tools, e2fsprogs
```

**需要移入的操作**：
- 安装 /packages/wifi-driver/*.deb（如果可用）
- 安装 /packages/rktoolkit/*.deb（如果可用）
- **不安装内核包**（内核在 Step 2 才有）
- **不生成 initramfs**（需要在内核安装后）

### 模块 2: mk-ubuntu-rootfs.sh 改造
**职责**：应用 overlay，安装内核，生成镜像

**需要移除的操作**：
- 所有 APT 安装（除了内核和 initramfs 相关）

**保留的操作**：
- 解压基础系统
- 应用 overlay/overlay-$BOARD
- **安装内核 deb 包**（首次或变化时）
- **生成 initramfs**（需要在内核安装后）
- 清理和打包

### 模块 3: 内核变化检测
**职责**：检测内核是否重新编译

**实现**：
```bash
detect_kernel_change() {
    local marker="$TARGET_ROOTFS_DIR/.kernel_cache_marker"
    local current_md5=""

    # 计算当前内核 deb 包的 md5
    if [ -e ../linux-headers* ]; then
        current_md5=$(md5sum ../linux-headers* ../linux-image-* 2>/dev/null | awk '{print $1}' | sort | md5sum | cut -d' ' -f1)
    fi

    # 检查是否需要安装
    if [ -f "$marker" ]; then
        local cached_md5=$(cat "$marker")
        if [ "$current_md5" = "$cached_md5" ]; then
            echo "内核未变化，跳过安装"
            return 1  # 不需要安装
        fi
    fi

    # 需要安装，更新标记
    echo "$current_md5" > "$marker"
    return 0  # 需要安装
}
```

### 模块 4: binary 清理脚本
**职责**：简化 binary 目录清理

**新建脚本**: `clean-binary.sh`
```bash
#!/bin/bash
# 清理 binary 目录，无需 sudo 密码
if [ -d "binary" ]; then
    sudo rm -rf binary
    echo "binary 目录已清理"
fi
```

## 接口定义

### mk-base-ubuntu.sh 输出
```bash
ubuntu-base-src-lite-arm64-DATE.tar.gz  # 包含所有已安装包的基础系统
```

### mk-ubuntu-rootfs.sh 输入
```bash
# 必需
ubuntu-base-src-lite-arm64-*.tar.gz
overlay/
overlay-$BOARD/

# 可选（内核变化时）
../linux-headers-*
../linux-image-*
```

### mk-ubuntu-rootfs.sh 输出
```bash
ubuntu-rk3562-src-lite-rootfs.img  # SquashFS 镜像
userdata.img                        # Ext4 镜像
```

## 风险评估

### 风险 1: 包安装顺序依赖
**风险**：某些包可能依赖 overlay 中的配置文件
**缓解**：
- 仔细测试拆分后的构建流程
- 必要时在 mk-base-ubuntu.sh 中预创建配置文件

### 风险 2: 内核版本不一致
**风险**：缓存的内核与实际编译的内核不匹配
**缓解**：
- 使用 md5 校验确保一致性
- 提供 FORCE_KERNEL_INSTALL 环境变量强制安装

### 风险 3: overlay 中包含需要 chroot 的脚本
**风险**：overlay 中的脚本可能依赖 chroot 环境
**缓解**：
- 检查所有 overlay 中的可执行脚本
- 文档化哪些 overlay 操作需要 chroot

### 风险 4: binary 权限问题误解
**风险**：用户可能认为需要改 binary 权限
**缓解**：
- 明确文档说明：binary 是 root 是正确的
- 提供 sudo 免密码配置方案

## 时间估算

- **架构设计**: 0.5 小时（已完成）
- **脚本修改**: 2 小时
  - mk-base-ubuntu.sh 改造: 1 小时
  - mk-ubuntu-rootfs.sh 改造: 1 小时
- **内核检测逻辑**: 0.5 小时
- **测试验证**: 2 小时
  - 首次完整构建测试: 0.5 小时
  - 修改 overlay 后增量构建测试: 0.5 小时
  - 内核变化检测测试: 0.5 小时
  - 边界情况测试: 0.5 小时
- **文档编写**: 1 小时

**总计**: 6 小时

## 实施步骤

### Phase 1: mk-base-ubuntu.sh 改造
1. 从 mk-ubuntu-rootfs.sh 中提取 src-lite 的包列表
2. 添加到 mk-base-ubuntu.sh 的 configure_base_in_chroot() 中
3. 添加 initramfs 生成逻辑
4. 添加 packages deb 包安装逻辑
5. 测试完整构建

### Phase 2: mk-ubuntu-rootfs.sh 改造
1. 移除 configure_in_chroot() 中的 APT 安装（保留内核安装）
2. 添加内核变化检测逻辑
3. 简化 chroot 操作（仅保留必要的配置）
4. 测试增量构建

### Phase 3: binary 清理优化
1. 创建 clean-binary.sh 脚本
2. 配置 sudo 免密码规则
3. 更新文档说明

### Phase 4: 测试与文档
1. 完整构建测试（mk-base + mk-rootfs）
2. 修改 overlay 后增量构建测试
3. 内核变化检测测试
4. 编写用户文档
