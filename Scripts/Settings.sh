#!/bin/bash

#修改默认主题
sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" $(find ./feeds/luci/collections/ -type f -name "Makefile")
#修改immortalwrt.lan关联IP
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $(find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js")
#添加编译日期标识
sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ $WRT_MARK-$WRT_DATE')/g" $(find ./feeds/luci/modules/luci-mod-status/ -type f -name "10_system.js")

WIFI_SH=$(find ./target/linux/{mediatek/filogic,qualcommax}/base-files/etc/uci-defaults/ -type f -name "*set-wireless.sh" 2>/dev/null)
WIFI_UC="./package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
if [ -f "$WIFI_SH" ]; then
	#修改WIFI名称
	sed -i "s/BASE_SSID='.*'/BASE_SSID='$WRT_SSID'/g" $WIFI_SH
	#修改WIFI密码
	sed -i "s/BASE_WORD='.*'/BASE_WORD='$WRT_WORD'/g" $WIFI_SH
elif [ -f "$WIFI_UC" ]; then
	#修改WIFI名称
	sed -i "s/ssid='.*'/ssid='$WRT_SSID'/g" $WIFI_UC
	#修改WIFI密码
	sed -i "s/key='.*'/key='$WRT_WORD'/g" $WIFI_UC
	#修改WIFI地区
	sed -i "s/country='.*'/country='CN'/g" $WIFI_UC
	#修改WIFI加密
	sed -i "s/encryption='.*'/encryption='psk2+ccmp'/g" $WIFI_UC
fi

CFG_FILE="./package/base-files/files/bin/config_generate"
#修改默认IP地址
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $CFG_FILE
#修改默认主机名
sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" $CFG_FILE

#配置文件修改
echo "CONFIG_PACKAGE_luci=y" >> ./.config
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config
echo "CONFIG_PACKAGE_luci-theme-$WRT_THEME=y" >> ./.config
echo "CONFIG_PACKAGE_luci-app-$WRT_THEME-config=y" >> ./.config

#手动调整的插件
if [ -n "$WRT_PACKAGE" ]; then
	echo -e "$WRT_PACKAGE" >> ./.config
fi

#高通平台调整
DTS_PATH="./target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/"
if [[ "${WRT_TARGET^^}" == *"QUALCOMMAX"* ]]; then
	#取消nss相关feed
	echo "CONFIG_FEED_nss_packages=n" >> ./.config
	echo "CONFIG_FEED_sqm_scripts_nss=n" >> ./.config
	#开启sqm-nss插件
	echo "CONFIG_PACKAGE_luci-app-sqm=y" >> ./.config
	echo "CONFIG_PACKAGE_sqm-scripts-nss=y" >> ./.config
	#设置NSS版本
	echo "CONFIG_NSS_FIRMWARE_VERSION_11_4=n" >> ./.config
	if [[ "${WRT_CONFIG,,}" == *"ipq50"* ]]; then
		echo "CONFIG_NSS_FIRMWARE_VERSION_12_2=y" >> ./.config
	else
		echo "CONFIG_NSS_FIRMWARE_VERSION_12_5=y" >> ./.config
	fi
	#无WIFI配置调整Q6大小
	if [[ "${WRT_CONFIG,,}" == *"wifi"* && "${WRT_CONFIG,,}" == *"no"* ]]; then
		find $DTS_PATH -type f ! -iname '*nowifi*' -exec sed -i 's/ipq\(6018\|8074\).dtsi/ipq\1-nowifi.dtsi/g' {} +
		echo "qualcommax set up nowifi successfully!"
	fi
fi

#DNS改用AdGuardHome
DNS_FILE="./package/base-files/files/etc/uci-defaults/99-disable-dnsmasq-dns"
cat <<EOF >> $DNS_FILE
#!/bin/sh
# OpenWrt AdGuardHome 专用配置
# 作用：关闭 dnsmasq DNS、禁止 IPv6 DNS 下发、系统只用本地 AdGuardHome
#dnsmasq 设置
 # 关闭 DNS 监听
uci set dhcp.@dnsmasq[0].port='0'
# 不使用系统 resolv.conf.auto
uci delete dhcp.@dnsmasq[0].resolvfile 2>/dev/null
uci set dhcp.@dnsmasq[0].noresolv='1'
# 禁用 IPv6 DNS 通告
uci set dhcp.lan.ra_dns='0'
uci set dhcp.lan.dns_service='0'
# 保留 DHCPv6 分配地址功能
uci set dhcp.lan.dhcpv6='server'
# 手动添加自定义上游 DNS 系统指向本地 AdGuardHome(可不配置，无意义了)
uci add_list dhcp.@dnsmasq[0].server='8.8.8.8'
uci commit dhcp
/etc/init.d/dnsmasq restart
/etc/init.d/odhcpd restart
# 启用 AdGuard Home
uci set adguardhome.config.enabled='1'
uci commit adguardhome
/etc/init.d/AdGuardHome restart
exit 0
EOF
chmod +x ./package/base-files/files/etc/uci-defaults/99-disable-dnsmasq-dns

#AdGuardHome默认配置
#取消认证可以注释users:段
ADG_FILE="./package/base-files/files/etc/adguardhome/adguardhome.yaml"
cat <<EOF >> $ADG_FILE
http:
  pprof:
    port: 6060
    enabled: false
  address: 0.0.0.0:3000
  session_ttl: 720h
users:
  - name: root
    password: $2a$10$uNXZCG/foh.wuLUBRe262.Wu1iax03t9tQf4xDoEInTGX3IhNXAYe
auth_attempts: 5
block_auth_min: 15
http_proxy: ""
language: ""
theme: auto
dns:
  bind_hosts:
    - 0.0.0.0
  port: 53
  anonymize_client_ip: false
  ratelimit: 20
  ratelimit_subnet_len_ipv4: 24
  ratelimit_subnet_len_ipv6: 56
  ratelimit_whitelist: []
  refuse_any: true
  upstream_dns:
    - https://120.53.53.53/dns-query
    - https://doh.360.cn/dns-query
    - https://1.12.12.12/dns-query
    - https://dns.alidns.com/dns-query
    - '[/*.google.com/]1.1.1.1 8.8.8.8'
    - '[/*.gmail.com/]1.1.1.1 8.8.8.8'
    - '[/*.gstatic.com/]1.1.1.1 8.8.8.8'
    - '[/*.googleapis.com/]1.1.1.1 8.8.8.8'
    - '[/*.ytimg.com/]1.1.1.1 8.8.8.8'
    - '[/chatgpt.com/]1.1.1.1 8.8.8.8'
    - '[/*.openai.com/]1.1.1.1 8.8.8.8'
    - '[/*.perplexity.ai/]1.1.1.1 8.8.8.8'
    - '[/*.x.com/]1.1.1.1 8.8.8.8'
    - '[/twitter.com/]1.1.1.1 8.8.8.8'
    - '[/*.twitter.com/]1.1.1.1 8.8.8.8'
    - '[/*.t.com/]1.1.1.1 8.8.8.8'
    - '[/*.googlevideo.com/]1.1.1.1 8.8.8.8'
    - '[/*.youtube.com/]1.1.1.1 8.8.8.8'
    - '[/*.facebook.com/]1.1.1.1 8.8.8.8'
    - '[/*.docker.com/]1.1.1.1 8.8.8.8'
    - '[/*.docker.io/]1.1.1.1 8.8.8.8'
    - '[/docker.io/]1.1.1.1 8.8.8.8'
    - '[/*.githubusercontent.com/]1.1.1.1 8.8.8.8'
    - '[/*.github.com/]1.1.1.1 8.8.8.8'
    - '[/github.com/]1.1.1.1 8.8.8.8'
    - '[/*.claude.ai/]1.1.1.1 8.8.8.8'
    - '[/claude.ai/]1.1.1.1 8.8.8.8'
    - '[/i.pximg.net/]1.1.1.1 8.8.8.8'
    - '[/*.telegram.org/]1.1.1.1 8.8.8.8'
    - '[/telegram.org/]1.1.1.1 8.8.8.8'
    - '[/*.cdn-telegram.org/]1.1.1.1 8.8.8.8'
    - '[/*.anthropic.com/]1.1.1.1 8.8.8.8'
    - '[/*.vercel.app/]1.1.1.1 8.8.8.8'
    - '[/*.openstreetmap.org/]1.1.1.1 8.8.8.8'
    - '[/*.t-mobile.com/]1.1.1.1 8.8.8.8'
    - '[/*.twimg.com/]1.1.1.1 8.8.8.8'
    - '[/*.ggpht.com/]1.1.1.1 8.8.8.8'
    - '[/*.fbcdn.net/]1.1.1.1 8.8.8.8'
    - '[/*.nodeseek.com/]1.1.1.1 8.8.8.8'
    - '[/*.appspot.com/]1.1.1.1 8.8.8.8'
    - '[/*.interactivebrokers.com/]1.1.1.1 8.8.8.8'
    - '[/interactivebrokers.com/]1.1.1.1 8.8.8.8'
    - '[/bandwagonhost.com/]1.1.1.1 8.8.8.8'
    - '[/*.uscardforum.com/]1.1.1.1 8.8.8.8'
    - '[/*.wikipedia.org/]1.1.1.1 8.8.8.8'
    - '[/*.moomoo.com/]1.1.1.1 8.8.8.8'
    - '[/*.tiktokv.com/]1.1.1.1 8.8.8.8'
    - '[/*.tiktok.com/]1.1.1.1 8.8.8.8'
    - '[/*.tiktokcdn-us.com/]1.1.1.1 8.8.8.8'
    - '[/*.tiktokv.us/]1.1.1.1 8.8.8.8'
  upstream_dns_file: ""
  bootstrap_dns:
    - 9.9.9.10
    - 149.112.112.10
    - 2620:fe::10
    - 2620:fe::fe:10
  fallback_dns: []
  upstream_mode: load_balance
  fastest_timeout: 1s
  allowed_clients: []
  disallowed_clients: []
  blocked_hosts:
    - version.bind
    - id.server
    - hostname.bind
  trusted_proxies:
    - 127.0.0.0/8
    - ::1/128
  cache_enabled: true
  cache_size: 4194304
  cache_ttl_min: 0
  cache_ttl_max: 0
  cache_optimistic: false
  bogus_nxdomain: []
  aaaa_disabled: false
  enable_dnssec: false
  edns_client_subnet:
    custom_ip: ""
    enabled: false
    use_custom: false
  max_goroutines: 300
  handle_ddr: true
  ipset: []
  ipset_file: ""
  bootstrap_prefer_ipv6: false
  upstream_timeout: 10s
  private_networks: []
  use_private_ptr_resolvers: false
  local_ptr_upstreams: []
  use_dns64: false
  dns64_prefixes: []
  serve_http3: false
  use_http3_upstreams: false
  serve_plain_dns: true
  hostsfile_enabled: true
  pending_requests:
    enabled: true
tls:
  enabled: false
  server_name: ""
  force_https: false
  port_https: 443
  port_dns_over_tls: 853
  port_dns_over_quic: 853
  port_dnscrypt: 0
  dnscrypt_config_file: ""
  allow_unencrypted_doh: false
  certificate_chain: ""
  private_key: ""
  certificate_path: ""
  private_key_path: ""
  strict_sni_check: false
querylog:
  dir_path: ""
  ignored: []
  interval: 2160h
  size_memory: 1000
  enabled: true
  file_enabled: true
statistics:
  dir_path: ""
  ignored: []
  interval: 720h
  enabled: true
filters:
  - enabled: true
    url: https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt
    name: AdGuard DNS filter
    id: 1
  - enabled: false
    url: https://adguardteam.github.io/HostlistsRegistry/assets/filter_2.txt
    name: AdAway Default Blocklist
    id: 2
whitelist_filters: []
user_rules: []
dhcp:
  enabled: false
  interface_name: ""
  local_domain_name: lan
  dhcpv4:
    gateway_ip: ""
    subnet_mask: ""
    range_start: ""
    range_end: ""
    lease_duration: 86400
    icmp_timeout_msec: 1000
    options: []
  dhcpv6:
    range_start: ""
    lease_duration: 86400
    ra_slaac_only: false
    ra_allow_slaac: false
filtering:
  blocking_ipv4: ""
  blocking_ipv6: ""
  blocked_services:
    schedule:
      time_zone: UTC
    ids: []
  protection_disabled_until: null
  safe_search:
    enabled: false
    bing: true
    duckduckgo: true
    ecosia: true
    google: true
    pixabay: true
    yandex: true
    youtube: true
  blocking_mode: default
  parental_block_host: family-block.dns.adguard.com
  safebrowsing_block_host: standard-block.dns.adguard.com
  rewrites: []
  safe_fs_patterns:
    - /var/lib/adguardhome/userfilters/*
  safebrowsing_cache_size: 1048576
  safesearch_cache_size: 1048576
  parental_cache_size: 1048576
  cache_time: 30
  filters_update_interval: 24
  blocked_response_ttl: 10
  filtering_enabled: true
  parental_enabled: false
  safebrowsing_enabled: false
  protection_enabled: true
clients:
  runtime_sources:
    whois: true
    arp: true
    rdns: true
    dhcp: true
    hosts: true
  persistent: []
log:
  enabled: true
  file: ""
  max_backups: 0
  max_size: 100
  max_age: 3
  compress: false
  local_time: false
  verbose: false
os:
  group: ""
  user: ""
  rlimit_nofile: 0
schema_version: 30
EOF