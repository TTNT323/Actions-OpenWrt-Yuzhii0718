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

# ============ 修复 nf_conntrack: expectation table full 日志刷屏 ============
# 本脚本在 .config 加载后、make defconfig 前执行，工作目录为 openwrt。
# 把 expectation 调优写进固件的 /etc/rc.local（系统 init 完成后执行，
# 此时 nf_conntrack 模块已加载，sysctl 节点一定存在），刷机后开机自动生效。
cat > package/base-files/files/etc/rc.local <<'EOF'
#!/bin/sh
# Put your custom commands here that should be executed once
# the system init finished.

# --- fix: nf_conntrack expectation table full ---
# expectation 表默认上限仅 256，UPnP/协议助手极易撑满导致刷屏；调大到 8192
sysctl -w net.netfilter.nf_conntrack_expect_max=8192 2>/dev/null
# 缩短 expectation 超时，失效条目快速回收（默认 600s -> 120s）
[ -e /proc/sys/net/netfilter/nf_conntrack_expect_generic_timeout ] && \
    sysctl -w net.netfilter.nf_conntrack_expect_generic_timeout=120 2>/dev/null
[ -e /proc/sys/net/netfilter/nf_conntrack_expect_related_timeout ] && \
    sysctl -w net.netfilter.nf_conntrack_expect_related_timeout=120 2>/dev/null
[ -e /proc/sys/net/netfilter/nf_conntrack_expect_helper_timeout ] && \
    sysctl -w net.netfilter.nf_conntrack_expect_helper_timeout=120 2>/dev/null
# --- fix end ---

exit 0
EOF
echo "[DIY] 已写入 conntrack expectation 调优到固件 rc.local"
# ============ 修复结束 ============
