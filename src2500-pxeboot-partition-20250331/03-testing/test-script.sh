#!/bin/bash

# ==============================================================================
# SRC2500 PXE Boot 分区脚本自动化测试脚本
#
# 功能：
#   1. 验证分区创建结果
#   2. 验证挂载点状态
#   3. 验证 systemd 服务状态
#   4. 收集系统日志
#   5. 生成测试报告
#
# 用法：
#   ./test-script.sh              # 运行所有测试
#   ./test-script.sh --first-boot # 首次启动模式
#   ./test-script.sh --reboot     # 重启验证模式
#
# 版本: 1.0
# 创建日期: 2025-03-31
# ==============================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 测试结果统计
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# 测试日志文件
TEST_LOG="/tmp/pxeboot-test-$(date +%Y%m%d-%H%M%S).log"
TEST_REPORT="/tmp/pxeboot-test-report-$(date +%Y%m%d-%H%M%S).txt"

# ==============================================================================
# 工具函数
# ==============================================================================

print_header() {
    echo ""
    echo "================================================================================"
    echo "$1"
    echo "================================================================================"
    echo ""
}

print_section() {
    echo ""
    echo "--------------------------------------------------------------------------------"
    echo "$1"
    echo "--------------------------------------------------------------------------------"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    echo "[INFO] $1" >> "$TEST_LOG"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    echo "[PASS] $1" >> "$TEST_LOG"
    ((PASSED_TESTS++))
    ((TOTAL_TESTS++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    echo "[FAIL] $1" >> "$TEST_LOG"
    ((FAILED_TESTS++))
    ((TOTAL_TESTS++))
}

log_skip() {
    echo -e "${YELLOW}[SKIP]${NC} $1"
    echo "[SKIP] $1" >> "$TEST_LOG"
    ((SKIPPED_TESTS++))
    ((TOTAL_TESTS++))
}

# ==============================================================================
# 检查函数
# ==============================================================================

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_fail "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_emmc() {
    log_info "Checking eMMC device..."

    BOOT_DEV=$(findmnt -n -o SOURCE /boot | sed 's/p[0-9]$//')
    if [ -z "$BOOT_DEV" ]; then
        BOOT_DEV="/dev/mmcblk0"
    fi

    if [ ! -e "$BOOT_DEV" ]; then
        log_fail "eMMC device not found: $BOOT_DEV"
        exit 1
    fi

    log_info "eMMC device: $BOOT_DEV"
    echo "BOOT_DEV=$BOOT_DEV" >> "$TEST_LOG"
}

# ==============================================================================
# 测试函数
# ==============================================================================

test_partition_existence() {
    print_section "TEST 1: Partition Existence Check"

    local required_partitions=("pxe_rootfs_a" "pxe_rootfs_b" "pxe_upper" "log")
    local all_exist=true

    for part in "${required_partitions[@]}"; do
        if [ -e "/dev/disk/by-partlabel/$part" ]; then
            log_success "Partition exists: $part"
        else
            log_fail "Partition missing: $part"
            all_exist=false
        fi
    done

    if [ "$all_exist" = true ]; then
        log_success "All required partitions exist"
    else
        log_fail "Some partitions are missing"
    fi

    # 详细分区信息
    echo ""
    log_info "Detailed partition table:"
    lsblk -o NAME,SIZE,TYPE,PARTLABEL,MOUNTPOINT "$BOOT_DEV" | tee -a "$TEST_LOG"
}

test_partition_sizes() {
    print_section "TEST 2: Partition Size Verification"

    # 期望大小（字节，允许 ±5% 误差）
    declare -A expected_sizes=(
        ["pxe_rootfs_a"]=2147483648  # 2GB
        ["pxe_rootfs_b"]=2147483648  # 2GB
        ["pxe_upper"]=30064771072    # 28GB
    )

    for part in "${!expected_sizes[@]}"; do
        actual_size=$(lsblk -b -n -o SIZE "/dev/disk/by-partlabel/$part" 2>/dev/null || echo "0")
        expected=${expected_sizes[$part]}

        if [ "$actual_size" -eq 0 ]; then
            log_fail "Cannot get size for $part"
            continue
        fi

        # 计算误差百分比
        diff=$((actual_size - expected))
        abs_diff=${diff#-}  # 绝对值
        percent=$((abs_diff * 100 / expected))

        if [ $percent -le 5 ]; then
            log_success "$part size OK ($(numfmt --to=iec $actual_size), ${percent}% deviation)"
        else
            log_fail "$part size mismatch: expected ~$(numfmt --to=iec $expected), got $(numfmt --to=iec $actual_size) (${percent}% deviation)"
        fi
    done

    # log 分区检查（动态大小）
    log_size=$(lsblk -b -n -o SIZE "/dev/disk/by-partlabel/log" 2>/dev/null || echo "0")
    if [ "$log_size" -gt 0 ]; then
        log_success "log partition size: $(numfmt --to=iec $log_size)"
    else
        log_fail "Cannot get log partition size"
    fi
}

test_mount_points() {
    print_section "TEST 3: Mount Point Verification"

    local required_mounts=("/pxe_rootfs_a" "/pxe_rootfs_b" "/pxe_upper" "/log")
    local all_mounted=true

    for mount_point in "${required_mounts[@]}"; do
        if mount | grep -q "$mount_point"; then
            log_success "Mount point active: $mount_point"
        else
            log_fail "Mount point missing: $mount_point"
            all_mounted=false
        fi
    done

    if [ "$all_mounted" = true ]; then
        log_success "All required mount points are active"
    else
        log_fail "Some mount points are missing"
    fi

    # 详细挂载信息
    echo ""
    log_info "Detailed mount information:"
    mount | grep -E "(pxe_|log)" | tee -a "$TEST_LOG"

    # 文件系统容量
    echo ""
    log_info "Filesystem capacity:"
    df -h | grep -E "(pxe_|log)" | tee -a "$TEST_LOG"
}

test_systemd_mount_units() {
    print_section "TEST 4: Systemd Mount Units Verification"

    local required_units=(
        "pxe\\x2drootfs\\x2da.mount"
        "pxe\\x2drootfs\\x2db.mount"
        "pxe\\x2dupper.mount"
        "log.mount"
    )

    local all_active=true

    for unit in "${required_units[@]}"; do
        if systemctl is-active --quiet "$unit"; then
            log_success "Mount unit active: $unit"
        else
            log_fail "Mount unit not active: $unit"
            all_active=false
        fi
    done

    if [ "$all_active" = true ]; then
        log_success "All required mount units are active"
    else
        log_fail "Some mount units are not active"
    fi

    # 详细 systemd 状态
    echo ""
    log_info "Systemd mount units status:"
    systemctl list-units '*.mount' | grep -E "(pxe|log)" | tee -a "$TEST_LOG"

    # 检查 mount 单元文件
    echo ""
    log_info "Mount unit files:"
    ls -la /etc/systemd/system/ | grep -E "(pxe|log)" | tee -a "$TEST_LOG"
}

test_systemd_init_service() {
    print_section "TEST 5: PXEBoot Init Service Verification"

    if systemctl list-unit-files | grep -q "pxeboot-init.service"; then
        log_success "pxeboot-init.service exists"

        # 检查服务是否已执行
        if systemctl is-active --quiet pxeboot-init.service; then
            log_info "Service is currently running (first boot)"
        else
            log_info "Service has exited (normal behavior after first boot)"
        fi

        # 显示服务状态
        echo ""
        log_info "Service status:"
        systemctl status pxeboot-init.service --no-pager | tee -a "$TEST_LOG" || true
    else
        log_fail "pxeboot-init.service not found"
    fi
}

test_filesystem_writability() {
    print_section "TEST 6: Filesystem Writability Test"

    local test_dirs=("/pxe_rootfs_a" "/pxe_rootfs_b" "/pxe_upper" "/log")
    local all_writable=true

    for dir in "${test_dirs[@]}"; do
        test_file="$dir/test-write-$(date +%s).txt"

        if sudo touch "$test_file" 2>/dev/null; then
            sudo sh -c "echo 'test data' > $test_file"
            sudo rm "$test_file"
            log_success "Filesystem writable: $dir"
        else
            log_fail "Filesystem not writable: $dir"
            all_writable=false
        fi
    done

    if [ "$all_writable" = true ]; then
        log_success "All filesystems are writable"
    else
        log_fail "Some filesystems are not writable"
    fi
}

test_partition_alignment() {
    print_section "TEST 7: Partition Alignment Check"

    # 检查分区是否 1MB 对齐（0x800 扇区）
    local misaligned=false

    while IFS= read -r line; do
        part_num=$(echo "$line" | awk '{print $1}')
        part_label=$(echo "$line" | awk '{print $2}')

        if [[ "$part_label" =~ (pxe_|log) ]]; then
            start_sector=$(sgdisk -p "$BOOT_DEV" | grep "^$part_num" | awk '{print $2}')

            # 移除 0x 前缀并转换为十进制
            start_dec=$((16#${start_sector#0x}))

            # 检查是否能被 0x800 (2048) 整除
            if [ $((start_dec % 2048)) -ne 0 ]; then
                log_fail "Partition $part_label misaligned: start sector $start_sector"
                misaligned=true
            else
                log_success "Partition $part_label aligned: start sector $start_sector"
            fi
        fi
    done < <(lsblk -n -o PARTLABEL "$BOOT_DEV" | grep -E "(pxe_|log)" | nl -v 5)

    if [ "$misaligned" = false ]; then
        log_success "All partitions are properly aligned"
    fi
}

test_uuid_uniqueness() {
    print_section "TEST 8: Partition UUID Uniqueness Check"

    local uuids=()
    local duplicate=false

    while IFS= read -r part_label; do
        uuid=$(sgdisk -p "$BOOT_DEV" | grep "$part_label" | awk '{print $4}')

        if [[ " ${uuids[@]} " =~ " ${uuid} " ]]; then
            log_fail "Duplicate UUID found: $uuid for $part_label"
            duplicate=true
        else
            uuids+=("$uuid")
            log_success "UUID unique for $part_label: $uuid"
        fi
    done < <(lsblk -n -o PARTLABEL "$BOOT_DEV" | grep -E "(pxe_|log)")

    if [ "$duplicate" = false ]; then
        log_success "All partition UUIDs are unique"
    fi
}

test_pxeboot_init_script() {
    print_section "TEST 9: PXEBoot Init Script Verification"

    local script="/usr/local/bin/pxeboot-init.sh"

    if [ -f "$script" ]; then
        log_success "Script exists: $script"

        # 检查权限
        permissions=$(stat -c %a "$script")
        if [ "$permissions" = "755" ]; then
            log_success "Script permissions correct: 755"
        else
            log_fail "Script permissions incorrect: $permissions (expected 755)"
        fi

        # 检查语法
        if bash -n "$script" 2>/dev/null; then
            log_success "Script syntax valid"
        else
            log_fail "Script syntax error"
        fi
    else
        log_fail "Script not found: $script"
    fi
}

test_journal_logs() {
    print_section "TEST 10: System Journal Logs Check"

    log_info "Checking pxeboot-init service logs..."

    if journalctl -u pxeboot-init.service -n 50 --no-pager > "$TEST_LOG.journal" 2>&1; then
        log_success "Journal logs collected"

        # 检查是否有错误
        if grep -qi "error\|fail\|cannot" "$TEST_LOG.journal"; then
            log_fail "Errors found in journal logs"
            echo ""
            log_info "Errors:"
            grep -i "error\|fail\|cannot" "$TEST_LOG.journal" | head -10
        else
            log_success "No errors found in journal logs"
        fi

        # 显示日志摘要
        echo ""
        log_info "Journal log summary:"
        tail -20 "$TEST_LOG.journal" | tee -a "$TEST_LOG"
    else
        log_fail "Cannot read journal logs"
    fi
}

# ==============================================================================
# 首次启动测试
# ==============================================================================

run_first_boot_tests() {
    print_header "SRC2500 PXE Boot - First Boot Test"

    check_root
    check_emmc

    # 运行所有测试
    test_pxeboot_init_script
    test_partition_existence
    test_partition_sizes
    test_partition_alignment
    test_uuid_uniqueness
    test_mount_points
    test_systemd_mount_units
    test_systemd_init_service
    test_filesystem_writability
    test_journal_logs

    # 生成报告
    generate_report

    print_summary
}

# ==============================================================================
# 重启验证测试
# ==============================================================================

run_reboot_tests() {
    print_header "SRC2500 PXE Boot - Reboot Verification Test"

    check_root
    check_emmc

    # 重启后关键测试
    test_partition_existence
    test_mount_points
    test_systemd_mount_units
    test_filesystem_writability
    test_journal_logs

    # 生成报告
    generate_report

    print_summary
}

# ==============================================================================
# 完整测试套件
# ==============================================================================

run_all_tests() {
    print_header "SRC2500 PXE Boot - Complete Test Suite"

    check_root
    check_emmc

    # 运行所有测试
    test_pxeboot_init_script
    test_partition_existence
    test_partition_sizes
    test_partition_alignment
    test_uuid_uniqueness
    test_mount_points
    test_systemd_mount_units
    test_systemd_init_service
    test_filesystem_writability
    test_journal_logs

    # 生成报告
    generate_report

    print_summary
}

# ==============================================================================
# 报告生成
# ==============================================================================

generate_report() {
    print_section "Generating Test Report"

    cat > "$TEST_REPORT" <<EOF
SRC2500 PXE Boot Partition Test Report
========================================

Test Date: $(date)
Test Host: $(hostname)
eMMC Device: $BOOT_DEV

Test Summary
------------
Total Tests:  $TOTAL_TESTS
Passed:       $PASSED_TESTS
Failed:       $FAILED_TESTS
Skipped:      $SKIPPED_TESTS

Pass Rate:    $(awk "BEGIN {printf \"%.1f\", ($PASSED_TESTS/$TOTAL_TESTS)*100}")%

Test Details
------------
$(cat "$TEST_LOG")

Partition Table
---------------
$(lsblk -o NAME,SIZE,TYPE,PARTLABEL,MOUNTPOINT "$BOOT_DEV")

Mount Points
------------
$(mount | grep -E "(pxe_|log)")

Systemd Mount Units
-------------------
$(systemctl list-units '*.mount' | grep -E "(pxe|log)")

Filesystem Usage
----------------
$(df -h | grep -E "(pxe_|log)")
EOF

    log_info "Test report saved to: $TEST_REPORT"
}

# ==============================================================================
# 摘要输出
# ==============================================================================

print_summary() {
    print_header "Test Summary"

    echo "Total Tests:  $TOTAL_TESTS"
    echo -e "Passed:       ${GREEN}$PASSED_TESTS${NC}"
    echo -e "Failed:       ${RED}$FAILED_TESTS${NC}"
    echo -e "Skipped:      ${YELLOW}$SKIPPED_TESTS${NC}"
    echo ""

    pass_rate=$(awk "BEGIN {printf \"%.1f\", ($PASSED_TESTS/$TOTAL_TESTS)*100}")
    echo "Pass Rate:    $pass_rate%"

    if [ $FAILED_TESTS -eq 0 ]; then
        echo ""
        echo -e "${GREEN}All tests passed!${NC}"
    else
        echo ""
        echo -e "${RED}Some tests failed. Please review the log.$NC}"
    fi

    echo ""
    echo "Log file:   $TEST_LOG"
    echo "Report:     $TEST_REPORT"
    echo ""

    # 返回退出码
    if [ $FAILED_TESTS -gt 0 ]; then
        exit 1
    else
        exit 0
    fi
}

# ==============================================================================
# 主函数
# ==============================================================================

main() {
    print_header "SRC2500 PXE Boot Partition Automated Test"

    # 解析命令行参数
    case "${1:-all}" in
        --first-boot)
            run_first_boot_tests
            ;;
        --reboot)
            run_reboot_tests
            ;;
        all|"")
            run_all_tests
            ;;
        *)
            echo "Usage: $0 [--first-boot|--reboot]"
            echo "  --first-boot  Run first boot test suite"
            echo "  --reboot      Run reboot verification test suite"
            echo "  (default)     Run complete test suite"
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"
