# firewalld 新镜像验证清单

**设备**: 192.168.192.7 (Ubuntu 22.04 + 6.1.99 内核)
**验证时间**: 待设备上线

---

## 一、基础信息验证

```bash
# 1. 系统版本
cat /etc/os-release | grep PRETTY
uname -r

# 2. firewalld 版本和状态
sudo firewall-cmd --version
sudo firewall-cmd --state

# 3. iptables 后端确认
sudo update-alternatives --display iptables | grep "link currently"
sudo iptables --version
```

**预期结果**:
- Ubuntu 22.04.5 LTS
- 内核 6.1.99-rk3562-gXXXXXXXX（新编译的）
- firewalld 1.1.1, state: running
- iptables → iptables-legacy, v1.8.7 (legacy)

---

## 二、firewalld 配置验证

```bash
# 1. 默认 zone
sudo firewall-cmd --get-default-zone

# 2. 接口绑定
sudo firewall-cmd --get-active-zones

# 3. external zone 配置
sudo firewall-cmd --zone=external --list-all

# 4. internal zone 配置
sudo firewall-cmd --zone=internal --list-all
```

**预期结果**:
```
# 默认 zone
internal

# 接口绑定
external
  interfaces: wlan0
internal
  interfaces: eth0

# external zone
external (active)
  interfaces: wlan0
  services: ssh
  masquerade: yes
  forward-ports:
    port=8022:proto=tcp:toport=22:toaddr=192.168.192.5
    port=8088:proto=tcp:toport=8088:toaddr=192.168.192.5
    ... (共 21 条)

# internal zone
internal (active)
  interfaces: eth0
  services: ssh dhcpv6-client samba-client mdns
  masquerade: no
```

---

## 三、iptables 规则验证

```bash
# 1. NAT 表（端口转发规则）
sudo iptables-legacy -t nat -L PREROUTING -n -v | grep 192.168.192.5

# 2. NAT 表（masquerade 规则）
sudo iptables-legacy -t nat -L POSTROUTING -n -v | grep MASQUERADE

# 3. Filter 表（基础过滤）
sudo iptables-legacy -t filter -L INPUT -n -v | head -10

# 4. 所有表可用性
for table in filter nat mangle raw security; do
    echo "=== Table: $table ==="
    sudo iptables-legacy -t $table -L -n 2>&1 | head -3
done
```

**预期结果**:
- NAT PREROUTING 有 21 条 DNAT 规则指向 192.168.192.5
- NAT POSTROUTING 有 MASQUERADE 规则（wlan0 接口）
- Filter INPUT 有 zone 相关规则
- 所有表（filter/nat/mangle/raw/security）都可用

---

## 四、网络功能验证

```bash
# 1. IP 转发是否启用
sysctl net.ipv4.ip_forward

# 2. 网络接口状态
ip addr show eth0
ip addr show wlan0

# 3. 路由表
ip route show

# 4. 连接跟踪
sudo conntrack -L 2>&1 | head -5
```

**预期结果**:
- `net.ipv4.ip_forward = 1`
- eth0 有 IP 地址（192.168.192.7）
- wlan0 有 IP 地址（外网接口）
- 默认路由指向 wlan0

---

## 五、端口转发功能测试

### 5.1 从外网访问测试

```bash
# 在外网设备上测试（假设 wlan0 IP 是 10.x.x.x）
# 测试 SSH 转发（8022 -> 192.168.192.5:22）
nc -zv <wlan0_IP> 8022

# 测试其他端口
nc -zv <wlan0_IP> 8088
nc -zv <wlan0_IP> 19101
```

**预期结果**: 所有端口都能连通，流量转发到 192.168.192.5

---

### 5.2 抓包验证

```bash
# 在网关上抓包验证 DNAT
sudo tcpdump -i wlan0 -n port 8022 -c 5

# 在网关上抓包验证转发到内网
sudo tcpdump -i eth0 -n host 192.168.192.5 -c 5
```

**预期结果**:
- wlan0 上看到外网访问 8022 的包
- eth0 上看到转发到 192.168.192.5:22 的包

---

## 六、firewalld 后端验证

```bash
# 1. 确认使用 iptables 后端
sudo cat /etc/firewalld/firewalld.conf | grep FirewallBackend

# 2. 确认没有 nftables 规则
sudo nft list tables 2>&1

# 3. 查看 firewalld 日志（确认无错误）
sudo journalctl -u firewalld --no-pager -n 50 | grep -E "ERROR|WARNING"
```

**预期结果**:
- `FirewallBackend=iptables`
- nft 命令找不到或无表（firewalld 不用 nftables）
- 日志无 ERROR（可能有 WARNING: ipset not usable，可忽略）

---

## 七、性能和稳定性验证

```bash
# 1. 内存占用
ps aux | grep firewalld

# 2. 规则数量
sudo iptables-legacy -t nat -L -n | wc -l
sudo iptables-legacy -t filter -L -n | wc -l

# 3. 服务自启动
sudo systemctl is-enabled firewalld

# 4. 重启测试
sudo systemctl restart firewalld
sleep 2
sudo firewall-cmd --state
```

**预期结果**:
- firewalld 内存占用 < 100MB
- NAT 规则约 50-100 条（21 条转发 + 框架规则）
- Filter 规则约 100-200 条
- 服务已启用（enabled）
- 重启后状态仍为 running

---

## 八、问题排查命令（如果有问题）

```bash
# 1. 详细日志
sudo journalctl -u firewalld --no-pager -n 100

# 2. 调试模式启动
sudo firewalld --debug --nofork --nopid 2>&1 | head -100

# 3. 检查内核模块
lsmod | grep -E "ip_tables|nf_nat|nf_conntrack"

# 4. 检查 iptables 可执行文件
ls -l /usr/sbin/iptables*
file /usr/sbin/iptables-legacy

# 5. 手动测试 iptables 规则
sudo iptables-legacy -t nat -A PREROUTING -i wlan0 -p tcp --dport 9999 -j DNAT --to 192.168.192.5:9999
sudo iptables-legacy -t nat -L PREROUTING -n | grep 9999
sudo iptables-legacy -t nat -D PREROUTING -i wlan0 -p tcp --dport 9999 -j DNAT --to 192.168.192.5:9999
```

---

## 九、验证结果记录

**验证时间**: _______________

| 检查项 | 状态 | 备注 |
|--------|------|------|
| firewalld 运行状态 | ⬜ PASS / ⬜ FAIL | |
| iptables-legacy 后端 | ⬜ PASS / ⬜ FAIL | |
| 默认 zone = internal | ⬜ PASS / ⬜ FAIL | |
| wlan0 → external | ⬜ PASS / ⬜ FAIL | |
| eth0 → internal | ⬜ PASS / ⬜ FAIL | |
| 21 条端口转发规则 | ⬜ PASS / ⬜ FAIL | |
| masquerade 启用 | ⬜ PASS / ⬜ FAIL | |
| IP 转发启用 | ⬜ PASS / ⬜ FAIL | |
| 所有 iptables 表可用 | ⬜ PASS / ⬜ FAIL | |
| 无 ERROR 日志 | ⬜ PASS / ⬜ FAIL | |

**问题记录**:
```
（如有问题，记录在此）
```

---

## 十、快速验证脚本

```bash
#!/bin/bash
# 一键验证脚本

echo "=== 1. 基础信息 ==="
cat /etc/os-release | grep PRETTY
uname -r
sudo firewall-cmd --version
sudo firewall-cmd --state

echo -e "\n=== 2. iptables 后端 ==="
sudo update-alternatives --display iptables | grep "link currently"
sudo iptables --version

echo -e "\n=== 3. Zone 配置 ==="
sudo firewall-cmd --get-default-zone
sudo firewall-cmd --get-active-zones

echo -e "\n=== 4. 端口转发规则数量 ==="
sudo iptables-legacy -t nat -L PREROUTING -n | grep -c 192.168.192.5

echo -e "\n=== 5. IP 转发 ==="
sysctl net.ipv4.ip_forward

echo -e "\n=== 6. 错误日志 ==="
sudo journalctl -u firewalld --no-pager -n 20 | grep ERROR || echo "无错误"

echo -e "\n=== 验证完成 ==="
```

保存为 `/tmp/verify_firewalld.sh`，执行：
```bash
bash /tmp/verify_firewalld.sh
```
