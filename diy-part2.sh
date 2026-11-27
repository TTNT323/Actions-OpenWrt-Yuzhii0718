#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
#
# Copyright (c) 2019-2024 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

# Modify default IP
#sed -i 's/192.168.1.1/192.168.50.5/g' package/base-files/files/bin/config_generate

# Modify default theme
#sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile

# Modify hostname
#sed -i 's/OpenWrt/P3TERX-Router/g' package/base-files/files/bin/config_generate

# 修改无线日志级别为0
sed -i '/wireless_add_vif "$name" "$ifname"/a iwpriv "$ifname" set Debug=0' package/mtk/applications/mtwifi-cfg/files/netifd/mtwifi.sh

# 删除默认luci-app-ttyd
sed -i 's/ +luci-app-ttyd//g' package/mtk/applications/luci-app-turboacc-mtk/Makefile

# 添加猫咪
#git clone --depth 1 https://github.com/vernesong/OpenClash.git /tmp/openclash-temp
# 查找并复制 luci-app-openclash 目录（无论它在哪个子目录下）
#find /tmp/openclash-temp -type d -name "luci-app-openclash" -exec cp -r {} package/ \;
# 清理临时文件
#rm -rf /tmp/openclash-temp

# ============================================================
# 硬件加速(turboacc) / IRQ-RPS(mtk-smp)：刻意不改动
#  * HNAT 与 Fullcone(NAT1) 默认已由 uci-defaults 启用，覆盖源码里那个空的
#    /etc/config/turboacc 多余且可能破坏默认值。
#  * mtk_smp(START=99) 已设置 IRQ 亲和性、RPS 多核均衡并关闭 GRO fraglist，
#    且晚于 rc.local 执行；此处再动会被覆盖，故不重复添加。
# ============================================================

# ============================================================
# 无线空口优化（编译期改 detect 默认配置，仅首次启动/恢复出厂生效）
# 家里 2.4G 设备多，2.4G 是延迟与稳定性的主战场：
#  A) 2.4G 频宽 HE40 -> HE20  【本轮新增，最重要】
#     2.4G 仅 3 个不重叠信道，40MHz 占掉 2 个，必与邻居重叠 -> 重传、
#     CSI 退避、抖动飙升。设备越多越明显。20MHz 牺牲峰值速率(2.4G 本就
#     不靠速率)，换来干净的信道、更低的重传率和更稳的响应。
#  B) 5G 频宽 HE160 -> HE80（上一轮已有）
#     160MHz 易受干扰/雷达 DFS 影响，80MHz 延迟/稳定/速率更平衡。
#  信道 36(5G，非DFS) 与 noscan=1(2.4G，禁扫描切道) 保持不变。
# ============================================================
MTWIFI_INIT="package/mtk/applications/mtwifi-cfg/files/mtwifi.sh"
# A) 2.4G：HE40 -> HE20
if grep -q 'htmode="HE40"' "$MTWIFI_INIT" 2>/dev/null; then
  sed -i 's/htmode="HE40"/htmode="HE20"/g' "$MTWIFI_INIT"
  echo "[DIY] 2.4G 默认频宽改为 HE20（2.4G 设备多，降低同频干扰/重传/抖动）"
fi
# B) 5G：HE160 -> HE80
if grep -q 'htmode="HE160"' "$MTWIFI_INIT" 2>/dev/null; then
  sed -i 's/htmode="HE160"/htmode="HE80"/g' "$MTWIFI_INIT"
  echo "[DIY] 5G 默认频宽改为 HE80"
fi
# 可选（按需启用）：固定 2.4G 到 1/6/11 中最空闲的信道，避免 channel=auto
# 在拥塞环境选到脏信道。请把 6 换成你实测最空闲的信道后再取消注释：
# sed -i 's/channel="auto"/channel="6"/g' "$MTWIFI_INIT"
# ============================================================

# ============ 固化开机优化到固件 /etc/rc.local ============
# done(START=95) 执行 rc.local，晚于 turboacc(90)，故此处设置生效。
cat > package/base-files/files/etc/rc.local <<'EOF'
#!/bin/sh
# Put your custom commands here that should be executed once
# the system init finished.

# ============================================================
# 1) conntrack：修复刷屏 + 适配"设备多"的连接规模
# ============================================================
# 期望表(expectation)默认上限 256，UPnP/协议助手易撑满导致刷屏
sysctl -w net.netfilter.nf_conntrack_expect_max=8192 2>/dev/null
[ -e /proc/sys/net/netfilter/nf_conntrack_expect_generic_timeout ] && \
    sysctl -w net.netfilter.nf_conntrack_expect_generic_timeout=120 2>/dev/null
[ -e /proc/sys/net/netfilter/nf_conntrack_expect_related_timeout ] && \
    sysctl -w net.netfilter.nf_conntrack_expect_related_timeout=120 2>/dev/null
[ -e /proc/sys/net/netfilter/nf_conntrack_expect_helper_timeout ] && \
    sysctl -w net.netfilter.nf_conntrack_expect_helper_timeout=120 2>/dev/null
# 连接跟踪主表：默认约 15360，2.4G/IoT 设备多 + P2P/UPnP 时易被打满，
# 表现为"时好时坏、偶发丢包、新建连接慢"。调大到 65536，按设备数
# 动态分配内存，不增加功耗；HNAT 快路径的首包仍需走 conntrack，故仍有效。
sysctl -w net.netfilter.nf_conntrack_max=65536 2>/dev/null

# ============================================================
# 2) TCP 拥塞控制 + 队列
#    作用范围说明：HNAT 已把转发流量卸载到硬件 PPE 快路径，绕过 Linux
#    qdisc/拥塞控制栈，故以下两项对"手机/2.4G 客户端转发流量"不生效，
#    仅对路由器本机发起或尚未卸载的连接有益。保留是因为无害。
# ============================================================
modprobe tcp_bbr 2>/dev/null
sysctl -w net.core.default_qdisc=fq 2>/dev/null
sysctl -w net.ipv4.tcp_congestion_control=bbr 2>/dev/null

# ============================================================
# 3) 连接建立/回收 + 缓冲区 + 队列积压
# ============================================================
sysctl -w net.ipv4.tcp_fastopen=3 2>/dev/null
sysctl -w net.ipv4.tcp_mtu_probing=1 2>/dev/null
sysctl -w net.ipv4.tcp_tw_reuse=1 2>/dev/null
sysctl -w net.ipv4.tcp_fin_timeout=15 2>/dev/null
sysctl -w net.core.rmem_max=2097152 2>/dev/null
sysctl -w net.core.wmem_max=2097152 2>/dev/null
sysctl -w net.core.netdev_max_backlog=16384 2>/dev/null
sysctl -w net.core.somaxconn=1024 2>/dev/null
sysctl -w net.ipv4.tcp_max_syn_backlog=1024 2>/dev/null

# ============================================================
# 4) 加大 dnsmasq DNS 缓存：重复域名解析更快（仅首次设置一次）
# ============================================================
if [ "$(uci -q get dhcp.@dnsmasq[0].cachesize)" != "4096" ]; then
    uci set dhcp.@dnsmasq[0].cachesize='4096'
    uci commit dhcp
    /etc/init.d/dnsmasq restart >/dev/null 2>&1
fi

exit 0
EOF
echo "[DIY] 已写入网络优化到固件 rc.local"
# ============ 结束 ============

# ============ 让 nokia_ea0326gmp 只生成 sysupgrade.bin，不生成 factory.bin ============
FIRMWARE_MK="target/linux/mediatek/image/filogic.mk"
if [ -f "$FIRMWARE_MK" ] && grep -q 'define Device/nokia_ea0326gmp' "$FIRMWARE_MK"; then
  sed -i '/define Device\/nokia_ea0326gmp/,/^endef/{
    /IMAGES += factory.bin/d
    /IMAGE\/factory.bin/d
  }' "$FIRMWARE_MK"
  echo "[DIY] 已禁用 nokia_ea0326gmp 的 factory.bin，仅保留 sysupgrade.bin"
else
  echo "[DIY] 未找到 filogic.mk 或 nokia_ea0326gmp 定义，跳过 factory.bin 禁用"
fi
# ============ 结束 ============
