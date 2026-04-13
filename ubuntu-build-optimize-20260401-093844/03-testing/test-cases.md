# 测试用例 - Ubuntu 构建流程优化

## 测试环境

- **目录**：/home/linke/processor_sdk/ubuntu22.04/
- **目标板型**：src2500 / src3600
- **芯片**：rk3562
- **架构**：arm64
- **Target**：src-lite

## 测试用例列表

### 用例 1：首次完整构建（基准测试）

**测试目的**：验证优化后的完整构建流程是否正常工作

**前置条件**：
- 已删除旧的 `ubuntu-base-src-lite-arm64-*.tar.gz`
- 已删除旧的 `ubuntu-rk3562-src-lite-rootfs.img`
- 已删除 binary 目录

**测试步骤**：
1. 进入 ubuntu22.04 目录
2. 执行 `TARGET=src-lite ./mk-base-ubuntu.sh`
3. 等待完成，记录构建时间
4. 执行 `TARGET=src-lite BOARD=src2500 SOC=rk3562 ./mk-ubuntu-rootfs.sh`
5. 等待完成，记录构建时间

**预期结果**：
- Step 1 成功生成 `ubuntu-base-src-lite-arm64-DATE.tar.gz`
- Step 2 成功生成 `ubuntu-rk3562-src-lite-rootfs.img`
- Step 1 耗时：约 10-15 分钟（下载 + 安装包）
- Step 2 耗时：约 2-3 分钟（解压 + 应用 overlay + 生成镜像）

**验证方法**：
```bash
# 检查基础系统包
ls -lh ubuntu-base-src-lite-arm64-*.tar.gz

# 检查最终镜像
ls -lh ubuntu-rk3562-src-lite-rootfs.img

# 检查内核缓存标记
cat .kernel_cache_marker_src-lite
```

**状态**：⏳ 待测试

---

### 用例 2：修改 overlay 后增量构建（核心优化验证）

**测试目的**：验证修改 overlay 后不需要重新下载安装 APT 包

**前置条件**：
- 用例 1 已通过
- 已生成 `ubuntu-base-src-lite-arm64-*.tar.gz`

**测试步骤**：
1. 修改 `overlay-src2500/etc/dnsmasq.d/pxe-server.conf` 中的某个配置
2. 删除 `ubuntu-rk3562-src-lite-rootfs.img`
3. 执行 `TARGET=src-lite BOARD=src2500 SOC=rk3562 ./mk-ubuntu-rootfs.sh`
4. 观察输出，确认没有 APT 下载和安装
5. 记录构建时间

**预期结果**：
- 构建过程中**无** `apt-get install` 输出
- 构建过程中**无** `wget` 下载包
- 显示 "内核未变化，跳过内核安装"
- 构建时间：约 30-60 秒
- 成功生成新的 `ubuntu-rk3562-src-lite-rootfs.img`

**验证方法**：
```bash
# 检查构建日志中是否有 APT 安装
./mk-ubuntu-rootfs.sh 2>&1 | tee build-test.log
grep "apt-get install" build-test.log  # 应该为空或只有内核

# 检查 overlay 修改是否生效
sudo mkdir -p /tmp/test-mount
sudo mount ubuntu-rk3562-src-lite-rootfs.img /tmp/test-mount
cat /tmp/test-mount/etc/dnsmasq.d/pxe-server.conf  # 验证修改
sudo umount /tmp/test-mount
```

**状态**：⏳ 待测试

---

### 用例 3：内核变化检测

**测试目的**：验证内核重新编译后能正确检测并重新安装

**前置条件**：
- 用例 1 已通过
- 已重新编译内核（在 `device/rockchip/.chips/rk3562/` 目录）

**测试步骤**：
1. 确认内核 deb 包存在：
   ```bash
   ls -lh ../linux-headers-* ../linux-image-*
   ```
2. 记录当前内核 MD5：
   ```bash
   md5sum ../linux-headers-* ../linux-image-* | awk '{print $1}' | sort | md5sum
   ```
3. 删除 `ubuntu-rk3562-src-lite-rootfs.img`
4. 删除 `.kernel_cache_marker_src-lite`（模拟首次安装）
5. 执行 `TARGET=src-lite BOARD=src2500 SOC=rk3562 ./mk-ubuntu-rootfs.sh`
6. 观察输出，确认检测到内核变化
7. 记录构建时间

**预期结果**：
- 显示 "首次安装内核（MD5: xxx）"
- 执行 `${APT_INSTALL} /boot/kerneldeb/*`
- 执行 `update-initramfs -c -k all`
- 生成 `.kernel_cache_marker_src-lite` 文件
- 构建时间：约 5-8 分钟（主要是 initramfs 生成）

**验证方法**：
```bash
# 检查缓存标记
cat .kernel_cache_marker_src-lite

# 检查内核是否安装
sudo mkdir -p /tmp/test-mount
sudo mount ubuntu-rk3562-src-lite-rootfs.img /tmp/test-mount
ls -lh /tmp/test-mount/boot/initrd.img-*
sudo umount /tmp/test-mount
```

**状态**：⏳ 待测试

---

### 用例 4：内核未变化时跳过安装

**测试目的**：验证内核未变化时能正确跳过安装

**前置条件**：
- 用例 3 已通过
- 内核 deb 包未改变

**测试步骤**：
1. 删除 `ubuntu-rk3562-src-lite-rootfs.img`
2. 确认 `.kernel_cache_marker_src-lite` 存在
3. 执行 `TARGET=src-lite BOARD=src2500 SOC=rk3562 ./mk-ubuntu-rootfs.sh`
4. 观察输出，确认跳过内核安装

**预期结果**：
- 显示 "内核未变化，跳过内核安装"
- **不执行** `${APT_INSTALL} /boot/kerneldeb/*`
- **不执行** `update-initramfs`
- 构建时间：约 30-60 秒

**验证方法**：
```bash
# 检查构建日志
./mk-ubuntu-rootfs.sh 2>&1 | tee build-test.log
grep "跳过内核安装" build-test-log  # 应该存在
```

**状态**：⏳ 待测试

---

### 用例 5：binary 清理脚本

**测试目的**：验证 `clean-binary.sh` 脚本功能

**前置条件**：
- binary 目录存在

**测试步骤**：
1. 确认 binary 目录存在：
   ```bash
   ls -ld binary
   ```
2. 执行 `./clean-binary.sh`
3. 确认 binary 目录已删除
4. 再次执行 `./clean-binary.sh`（测试不存在时的提示）

**预期结果**：
- 第一次执行：显示 "binary 目录已清理"，binary 目录被删除
- 第二次执行：显示 "binary 目录不存在，无需清理"

**验证方法**：
```bash
# 检查 binary 是否存在
ls -ld binary 2>&1  # 应该提示不存在
```

**状态**：⏳ 待测试

---

### 用例 6：sudo 免密码配置（可选）

**测试目的**：验证 sudo 免密码配置是否生效

**前置条件**：
- 用户配置了 sudo 免密码规则

**测试步骤**：
1. 配置 sudo 免密码（如需要）：
   ```bash
   echo "$USER ALL=(ALL) NOPASSWD: /usr/bin/rm" | sudo tee /etc/sudoers.d/nopasswd-rm
   ```
2. 执行 `./clean-binary.sh`
3. 确认无需输入密码

**预期结果**：
- 执行过程中**无需输入密码**
- binary 目录被成功删除

**验证方法**：
```bash
# 检查 sudo 配置
sudo cat /etc/sudoers.d/nopasswd-rm
```

**状态**：⏳ 待测试

---

### 用例 7：src3600 板型测试

**测试目的**：验证 src3600 板型的构建是否正常

**前置条件**：
- 用例 1 已通过

**测试步骤**：
1. 执行 `TARGET=src-lite BOARD=src3600 SOC=rk3562 ./mk-ubuntu-rootfs.sh`
2. 等待完成
3. 检查 overlay-src3600 的配置是否生效

**预期结果**：
- 成功生成 `ubuntu-rk3562-src-lite-rootfs.img`
- NFS 服务器配置正确（overlay-src3600/etc/exports）
- 挂载服务正确（mount-pxeboot-fs.service）

**验证方法**：
```bash
# 检查 overlay-src3600 配置
sudo mkdir -p /tmp/test-mount
sudo mount ubuntu-rk3562-src-lite-rootfs.img /tmp/test-mount
cat /tmp/test-mount/etc/exports
sudo umount /tmp/test-mount
```

**状态**：⏳ 待测试

---

## 边界测试

### 边界测试 1：无内核 deb 包

**测试步骤**：
1. 临时移除内核 deb 包：
   ```bash
   mkdir -p ../kernel-backup
   mv ../linux-headers-* ../linux-image-* ../kernel-backup/
   ```
2. 执行 `TARGET=src-lite BOARD=src2500 SOC=rk3562 ./mk-ubuntu-rootfs.sh`

**预期结果**：
- 显示 "未找到内核 deb 包"
- 跳过内核安装
- 构建继续进行（但可能失败）

**清理**：
```bash
mv ../kernel-backup/* ../
```

**状态**：⏳ 待测试

---

### 边界测试 2：overlay 目录不存在

**测试步骤**：
1. 临时移除 overlay-src2500：
   ```bash
   mv overlay-src2500 overlay-src2500-backup
   ```
2. 执行 `TARGET=src-lite BOARD=src2500 SOC=rk3562 ./mk-ubuntu-rootfs.sh`

**预期结果**：
- 显示 "overlay-src2500 not found, exit !"
- 脚本退出，返回错误码

**清理**：
```bash
mv overlay-src2500-backup overlay-src2500
```

**状态**：⏳ 待测试

---

## 性能测试

### 性能基准测试

**测试指标**：
1. 首次完整构建时间
2. 修改 overlay 后重建时间
3. 内核未变时重建时间
4. 内核变化时重建时间

**测试方法**：
使用 `time` 命令测量：
```bash
time TARGET=src-lite BOARD=src2500 SOC=rk3562 ./mk-ubuntu-rootfs.sh
```

**预期对比**：

| 操作 | 优化前 | 优化后 | 提升 |
|------|--------|--------|------|
| 首次构建 | 15-20 分钟 | 15-20 分钟 | 0% |
| 修改 overlay 后重建 | 15-20 分钟 | 30-60 秒 | ~95% |
| 内核未变时重建 | 15-20 分钟 | 30-60 秒 | ~95% |
| 内核变化时重建 | 15-20 分钟 | 5-8 分钟 | ~50% |

**状态**：⏳ 待测试

---

## 测试总结模板

**测试日期**：YYYY-MM-DD
**测试人员**：[Name]
**测试环境**：Ubuntu 22.04 + RK3562 + src-lite

**测试结果**：
- 通过：X 个
- 失败：Y 个
- 待测试：Z 个

**问题列表**：
1. [问题描述]
2. [问题描述]

**改进建议**：
1. [建议]
2. [建议]
