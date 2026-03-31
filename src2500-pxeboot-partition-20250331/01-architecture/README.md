# SRC2500 PXE Boot 分区架构文档

## 文档导航

本目录包含 SRC2500 板型 PXE boot 分区自动划分的完整架构设计文档。

### 核心文档

1. **[design.md](./design.md)** - 完整架构设计
   - 分区布局设计
   - 脚本实现方案
   - 风险评估
   - 测试计划
   - 扇区计算验证

2. **[SUMMARY.md](./SUMMARY.md)** - 快速参考
   - 最终分区表（已验证）
   - 与 SRC3600 对比
   - 关键设计决策
   - 验证状态

3. **[comparison.md](./comparison.md)** - SRC2500 vs SRC3600 对比分析
   - 分区数量差异
   - 使用场景分析
   - 性能影响分析
   - 最佳实践建议

4. **[verify-sectors.sh](./verify-sectors.sh)** - 扇区计算验证脚本
   - 自动化扇区地址计算
   - 分区对齐检查
   - 容量验证

## 快速开始

### 1. 阅读顺序

**第一次阅读**：
1. SUMMARY.md - 快速了解最终设计
2. design.md - 深入理解架构细节
3. comparison.md - 理解与 SRC3600 的差异

**后续参考**：
- 需要验证扇区计算时：运行 `verify-sectors.sh`
- 需要查找分区表时：查看 SUMMARY.md 的"快速参考"

### 2. 关键结论

```bash
# 最终分区表（已验证）
declare -A PARTITIONS=(
    ["pxe_rootfs_a"]="0x2000000:0x400000"  # 2GB @ 16GB
    ["pxe_rootfs_b"]="0x2400000:0x400000"  # 2GB @ 18GB
    ["pxe_upper"]="0x2800000:0x3800000"    # 28GB @ 20GB
)

log 起始: 0x6000000 (48GB)
log 结束: 到 eMMC 末尾
```

**验证通过**：
- ✅ 所有扇区按 1MB 对齐
- ✅ 分区无缝连接
- ✅ 64GB eMMC 容量验证通过

### 3. 下一步行动

1. 在 `ubuntu22.04/overlay-src2500/usr/local/bin/` 创建 `pxeboot-init.sh`
2. 参考 `overlay-src3600/usr/local/bin/pxeboot-init.sh` 的实现模式
3. 使用本目录中的分区表数据替换 SRC3600 的分区定义
4. 在实际硬件上测试验证

## 文档版本

- **创建日期**: 2025-03-31
- **版本**: 1.0
- **作者**: Team Workflow - 架构师角色
- **状态**: 设计阶段，待实施验证

## 修订历史

| 日期 | 版本 | 说明 |
|------|------|------|
| 2025-03-31 | 1.0 | 初始版本，完成架构设计 |

## 相关资源

### 源文件
- **参考实现**: `/home/linke/processor_sdk/ubuntu22.04/overlay-src3600/usr/local/bin/pxeboot-init.sh`
- **分区表配置**: `/home/linke/processor_sdk/device/rockchip/.chips/rk3562/parameter-ubuntu-src2500-3600.txt`

### 工具文档
- `sgdisk(8)`: GPT 分区表管理工具
- `systemd.mount(5)`: systemd 挂载单元配置
- `partprobe(8)`: 通知内核分区表变化

### 相关文档
- `/home/linke/processor_sdk/CLAUDE.md` - SDK 整体架构
- `/home/linke/processor_sdk/.claude/ubuntu22.04.md` - Ubuntu 22.04 根文件系统详细文档

## 问题反馈

如发现文档错误或需要补充内容，请通过以下方式反馈：
- 在 Team Workflow 频道中提出
- 创建 GitHub Issue（如果适用）
- 直接联系架构师角色

---

**最后更新**: 2025-03-31
