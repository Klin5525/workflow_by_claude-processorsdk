#!/bin/bash
# 扇区计算验证脚本
# 用于验证 SRC2500 PXE boot 分区布局的扇区地址计算

echo "=== 扇区计算验证 ==="
echo ""

# 常量定义
SECTOR_SIZE=512
GB=$((1024 * 1024 * 1024))

# 函数：GB 转 扇区
gb_to_sectors() {
    local gb=$1
    echo $((gb * GB / SECTOR_SIZE))
}

# 函数：十六进制格式化
to_hex() {
    printf "0x%X\n" $1
}

# 函数：格式化输出
format_size() {
    local sectors=$1
    local bytes=$((sectors * SECTOR_SIZE))
    local gb=$((bytes / GB))
    local mb=$(((bytes % GB) / (1024 * 1024)))
    printf "%d 扇区 = %d.%d GB" $sectors $gb $mb
}

echo "基础计算："
echo "1GB = $(to_hex $(gb_to_sectors 1)) 扇区"
echo "2GB = $(to_hex $(gb_to_sectors 2)) 扇区"
echo "16GB = $(to_hex $(gb_to_sectors 16)) 扇区"
echo "28GB = $(to_hex $(gb_to_sectors 28)) 扇区"
echo "48GB = $(to_hex $(gb_to_sectors 48)) 扇区"
echo ""

# 分区布局验证
declare -A PARTITIONS
PARTITIONS[pxe_rootfs_a_start]=$(gb_to_sectors 16)
PARTITIONS[pxe_rootfs_a_size]=$(gb_to_sectors 2)
PARTITIONS[pxe_rootfs_b_start]=$(gb_to_sectors 18)
PARTITIONS[pxe_rootfs_b_size]=$(gb_to_sectors 2)
PARTITIONS[pxe_upper_start]=$(gb_to_sectors 20)
PARTITIONS[pxe_upper_size]=$(gb_to_sectors 28)
PARTITIONS[log_start]=$(gb_to_sectors 48)

echo "=== 分区布局验证 ==="
echo ""

# pxe_rootfs_a
start=${PARTITIONS[pxe_rootfs_a_start]}
size=${PARTITIONS[pxe_rootfs_a_size]}
end=$((start + size - 1))
echo "pxe_rootfs_a:"
echo "  起始扇区: $(to_hex $start)"
echo "  大小: $(format_size $size)"
echo "  结束扇区: $(to_hex $end)"
echo "  对齐检查: $((start % 0x800)) (应为 0)"
echo ""

# pxe_rootfs_b
start=${PARTITIONS[pxe_rootfs_b_start]}
size=${PARTITIONS[pxe_rootfs_b_size]}
end=$((start + size - 1))
echo "pxe_rootfs_b:"
echo "  起始扇区: $(to_hex $start)"
echo "  大小: $(format_size $size)"
echo "  结束扇区: $(to_hex $end)"
echo "  对齐检查: $((start % 0x800)) (应为 0)"
echo "  无缝检查: $(to_hex ${PARTITIONS[pxe_rootfs_a_start]} + ${PARTITIONS[pxe_rootfs_a_size]}) == $(to_hex $start)"
echo ""

# pxe_upper
start=${PARTITIONS[pxe_upper_start]}
size=${PARTITIONS[pxe_upper_size]}
end=$((start + size - 1))
echo "pxe_upper:"
echo "  起始扇区: $(to_hex $start)"
echo "  大小: $(format_size $size)"
echo "  结束扇区: $(to_hex $end)"
echo "  对齐检查: $((start % 0x800)) (应为 0)"
echo "  无缝检查: $(to_hex ${PARTITIONS[pxe_rootfs_b_start]} + ${PARTITIONS[pxe_rootfs_b_size]}) == $(to_hex $start)"
echo ""

# log
start=${PARTITIONS[log_start]}
echo "log:"
echo "  起始扇区: $(to_hex $start)"
echo "  无缝检查: $(to_hex ${PARTITIONS[pxe_upper_start]} + ${PARTITIONS[pxe_upper_size]}) == $(to_hex $start)"
echo ""

echo "=== 128GB eMMC 容量验证 ==="
total_sectors=$(gb_to_sectors 128)
log_size=$((total_sectors - start))
echo "128GB 总扇区: $(to_hex $total_sectors)"
echo "log 分区大小: $(format_size $log_size)"
echo ""

echo "=== 容量对比 ==="
echo "64GB eMMC: log 分区 = 16GB"
echo "128GB eMMC: log 分区 = 80GB"
echo ""

echo "=== 最终分区表（用于脚本）==="
echo "declare -A PARTITIONS=( "
echo '    ["pxe_rootfs_a"]="'$(to_hex ${PARTITIONS[pxe_rootfs_a_start]})':'$(to_hex ${PARTITIONS[pxe_rootfs_a_size]})'  # 2GB @ 16GB'
echo '    ["pxe_rootfs_b"]="'$(to_hex ${PARTITIONS[pxe_rootfs_b_start]})':'$(to_hex ${PARTITIONS[pxe_rootfs_b_size]})'  # 2GB @ 18GB'
echo '    ["pxe_upper"]="'$(to_hex ${PARTITIONS[pxe_upper_start]})':'$(to_hex ${PARTITIONS[pxe_upper_size]})'     # 28GB @ 20GB'
echo ")"
echo ""
echo "log 分区 sgdisk 命令："
echo "sgdisk \"\$BOOT_DEV\" --new=\${LOG_PART}:$(to_hex $start):0 --change-name=\${LOG_PART}:log ..."
