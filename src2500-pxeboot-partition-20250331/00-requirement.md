# 需求文档 - SRC2500 PXEBoot 分区自动划分

**日期**: 2025-03-31
**目标**: 为 SRC2500 板型开发分区自动划分脚本

## 背景

- SRC3600 版型已有验证通过的分区脚本：`ubuntu22.04/overlay-src3600/usr/local/bin/pxeboot-init.sh`
- 需要为 SRC2500 版型开发类似脚本：`ubuntu22.04/overlay-src2500/usr/local/bin/pxeboot-init.sh`

## 分区布局对比

### SRC3600 分区布局（参考实现）
在镜像占用 16GB 后的空间中划分：
- `ap0_rootfs_a`: 1GB @ 16GB
- `ap0_rootfs_b`: 1GB @ 17GB
- `ap1_rootfs_a`: 1GB @ 18GB
- `ap1_rootfs_b`: 1GB @ 19GB
- `ap0_upper`: 18GB @ 20GB
- `ap1_upper`: 10GB @ 38GB
- `log`: 到 eMMC 末尾 @ 48GB

### SRC2500 分区布局（目标）
在镜像占用 16GB 后的 30GB 空间中划分：
- `pxe_rootfs_a`: 2GB @ 16GB
- `pxe_rootfs_b`: 2GB @ 18GB
- `pxe_upper`: 28GB @ 20GB
- `log`: 到 eMMC 末尾 @ 48GB（起始位置固定）

## 功能需求

1. **第一次启动**：
   - 检测分区是否存在
   - 创建 4 个分区（pxe_rootfs_a, pxe_rootfs_b, pxe_upper, log）
   - 格式化为 ext4
   - 创建 systemd mount 单元确保持久化挂载
   - 立即挂载分区

2. **第二次启动**：
   - 分区已存在，跳过创建
   - systemd 自动挂载各分区

## 技术要求

- 使用 `sgdisk` 进行分区操作
- 使用 PARTLABEL 实现设备无关的挂载
- 使用 systemd mount 单元确保持久化
- 兼容 OverlayFS 环境

## 验证方法

- 在实际板子上测试（IP: 192.168.192.7, 用户: sr）
- 第一次启动验证分区创建成功
- 第二次启动验证系统正常启动且分区已挂载
