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
