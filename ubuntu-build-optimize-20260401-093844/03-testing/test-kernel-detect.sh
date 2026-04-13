#!/bin/bash
#=============================================================================
# test-kernel-detect.sh - 测试内核变化检测逻辑
#=============================================================================

# 模拟 detect_kernel_change 函数
KERNEL_CACHE_MARKER=".kernel_cache_marker_src-lite"

detect_kernel_change() {
    local current_md5=""
    local kernel_debs="/home/linke/processor_sdk/linux-headers-*.deb /home/linke/processor_sdk/linux-image-*.deb /home/linke/processor_sdk/linux-libc-dev_*.deb"

    # 检查内核 deb 包是否存在
    if ! ls $kernel_debs 1> /dev/null 2>&1; then
        echo "未找到内核 deb 包"
        return 1
    fi

    # 计算当前内核 deb 包的 md5
    current_md5=$(md5sum $kernel_debs 2>/dev/null | awk '{print $1}' | sort | md5sum | cut -d' ' -f1)

    # 检查缓存标记
    if [ -f "$KERNEL_CACHE_MARKER" ]; then
        local cached_md5=$(cat "$KERNEL_CACHE_MARKER")
        if [ "$current_md5" = "$cached_md5" ]; then
            echo -e "\033[47;36m 内核未变化，跳过内核安装 \033[0m"
            return 1  # 内核未变化
        else
            echo -e "\033[47;36m 检测到内核变化（MD5: $current_md5） \033[0m"
        fi
    else
        echo -e "\033[47;36m 首次安装内核（MD5: $current_md5） \033[0m"
    fi

    # 更新缓存标记（宿主机）
    echo "$current_md5" > "$KERNEL_CACHE_MARKER"
    return 0  # 内核已变化或首次安装
}

echo "=========================================="
echo "测试 1: 首次检测（无缓存标记）"
echo "=========================================="
rm -f .kernel_cache_marker_src-lite
if detect_kernel_change; then
    echo "结果: 需要安装内核"
else
    echo "结果: 跳过内核安装"
fi
echo ""

echo "=========================================="
echo "测试 2: 再次检测（有缓存标记，内核未变）"
echo "=========================================="
if detect_kernel_change; then
    echo "结果: 需要安装内核"
else
    echo "结果: 跳过内核安装"
fi
echo ""

echo "=========================================="
echo "测试 3: 查看缓存标记内容"
echo "=========================================="
if [ -f ".kernel_cache_marker_src-lite" ]; then
    echo "MD5: $(cat .kernel_cache_marker_src-lite)"
else
    echo "缓存标记不存在"
fi
echo ""

echo "=========================================="
echo "测试 4: 模拟内核变化（修改缓存标记）"
echo "=========================================="
echo "fake_md5_for_testing" > .kernel_cache_marker_src-lite
if detect_kernel_change; then
    echo "结果: 需要安装内核"
else
    echo "结果: 跳过内核安装"
fi
echo ""

echo "清理测试文件..."
rm -f .kernel_cache_marker_src-lite
echo "测试完成！"
