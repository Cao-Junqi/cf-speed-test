#!/bin/bash
# ==============================================================================
# CLOUDFLARE 优选 IP 与 CNAME 域名本地测试脚本 (Premium Upgraded Edition)
# ==============================================================================
# 支持在纯黑与纯白终端背景下完美显示，且采用极速直连下载与多维度排行榜渲染。
# 彻底直连测速，自动绕过代理，多进程并发延迟探测。
# ==============================================================================

# 1. 强力直连策略：强行清空本地代理环境变量，防止测速流量走代理导致结果失效
unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy
export NO_PROXY="*"

# 1b. 动态探测活跃的物理网卡（如 en0）用于直连测速绑定，绕过 Clash TUN 网卡
ACTIVE_IFACE=$(ifconfig | awk '/^en[0-9]+:/ { if (iface != "" && is_active == 1 && ip != "") { print iface; exit }; iface=substr($1, 1, length($1)-1); is_active=0; ip="" }; /status: active/ { is_active=1 }; /inet / { ip=$2 }; END { if (iface != "" && is_active == 1 && ip != "") { print iface } }' | head -n 1)

# 1c. 默认带宽测速大小与超时参数 (完美自适应不同带宽环境，支持命令行动态参数配置)
TEST_BYTES=25000000       # 默认 25MB 大文件
TEST_TIMEOUT=2            # 默认 2 秒超时
TEST_MODE_NAME="标准模式 (25MB)"

# 解析命令行参数：支持 `./cf_speed_test.sh [fast|standard|gigabit]` 或简写
if [ "$1" = "fast" ] || [ "$1" = "极速" ]; then
  TEST_BYTES=10000000     # 10MB
  TEST_TIMEOUT=2          # 2s
  TEST_MODE_NAME="极速模式 (10MB)"
  shift
elif [ "$1" = "gigabit" ] || [ "$1" = "千兆" ] || [ "$1" = "thorough" ] || [ "$1" = "深度" ]; then
  TEST_BYTES=50000000     # 50MB (支持千兆上限)
  TEST_TIMEOUT=3          # 3s (增加耗时以保证 TCP 窗口充分爬升)
  TEST_MODE_NAME="千兆深度模式 (50MB)"
  shift
fi


# 2. Modern Pro 终端配色方案 (黑白终端双色自适应高对比配色)
RED='\033[38;5;196m'      # 鲜红
GREEN='\033[38;5;34m'     # 森林深绿，保证白底背景下的极佳对比度
YELLOW='\033[38;5;172m'   # 琥珀深黄，规避亮黄在白底背景下隐形
BLUE='\033[38;5;33m'      # 皇家宝蓝
MAGENTA='\033[38;5;125m'  # 深玫瑰红
CYAN='\033[38;5;37m'      # 碧绿/深青，规避亮青在白底下隐形
GRAY='\033[38;5;242m'     # 中炭灰
NC='\033[0m'              # 重置颜色
BOLD='\033[1m'            # 粗体

# 3. 检查系统必备工具
check_requirements() {
  local missing=0
  for cmd in curl nslookup awk grep sed sort uniq bc; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo -e "${RED}[ERROR] 缺少必需的系统工具: ${BOLD}$cmd${NC}"
      missing=1
    fi
  done
  if [ $missing -eq 1 ]; then
    echo -e "${RED}[ERROR] 请在终端中安装上述缺失的工具后再运行此脚本。${NC}"
    exit 1
  fi
}

# 4. 内置 30+ 优选 CNAME 域名及中文备注
DOMAINS_RAW="
*.cf.090227.xyz
www.visa.cn
mfa.gov.ua
www.shopify.com
store.ubi.com
staticdelivery.nexusmods.com
www.visa.cn#visa中国优选
mfa.gov.ua#乌克兰外交部
www.shopify.com#Shopify官方优选
store.ubi.com#Ubisoft
staticdelivery.nexusmods.com#NexusMods
time.is#官方优选
icook.hk#官方优选
icook.tw#官方优选
*.tencentapp.cn
cloudflare-dl.byoip.top
cf.877774.xyz
saas.sin.fan
bestcf.030101.xyz
*.cloudflare.182682.xyz
bestcf.030101.xyz#Mingyu维护
cdn.2020111.xyz
cdns.doon.eu.org
cf.0sm.com
cf.877771.xyz
cf.877774.xyz#秋名山维护
cf.900501.xyz
cfip.1323123.xyz
cfip.cfcdn.vip
cfip.xxxxxxxx.tk#OTC维护
cloudflare.182682.xyz#WeTest.Vip维护
cloudflare-dl.byoip.top
cloudflare-ip.mofashi.ltd
fn.130519.xyz
freeyx.cloudflare88.eu.org
nrt.xxxxxxxx.nyc.mn
nrtcfdns.zone.id
saas.sin.fan
tencentapp.cn#ktff维护
xn--b6gac.eu.org
777.ai7777777.xyz
"

# 5. 中英混合字符宽度计算器与格式化对齐工具
get_display_width() {
  local clean
  clean=$(echo -n "$1" | sed $'s/\033\\[[0-9;]*[a-zA-Z]//g')
  local bytes
  local chars
  bytes=$(echo -n "$clean" | wc -c | tr -d ' ')
  chars=$(echo -n "$clean" | wc -m | tr -d ' ')
  echo $(( (bytes + chars) / 2 ))
}

pad_string() {
  local str="$1"
  local target_width="$2"
  local align="${3:-left}"
  local color="${4:-}"
  local w
  w=$(get_display_width "$str")
  local pad_len=$((target_width - w))
  if [ $pad_len -le 0 ]; then
    if [ -n "$color" ]; then
      echo -n "${color}${str}${NC}"
    else
      echo -n "$str"
    fi
    return
  fi
  local spaces=""
  for ((i=0; i<pad_len; i++)); do
    spaces="${spaces} "
  done
  if [ "$align" = "left" ]; then
    if [ -n "$color" ]; then
      echo -n "${color}${str}${NC}${spaces}"
    else
      echo -n "${str}${spaces}"
    fi
  else
    if [ -n "$color" ]; then
      echo -n "${spaces}${color}${str}${NC}"
    else
      echo -n "${spaces}${str}"
    fi
  fi
}

generate_border_line() {
  local len="$1"
  local line=""
  for ((i=0; i<len; i++)); do
    line="${line}─"
  done
  echo -n "$line"
}

truncate_display_width() {
  local str="$1"
  local max_w="$2"
  local w
  w=$(get_display_width "$str")
  if [ $w -le $max_w ]; then
    echo -n "$str"
    return
  fi

  local target_w=$((max_w - 3))
  local len
  len=$(echo -n "$str" | wc -m | tr -d ' ')
  local current=""
  local i=1
  while [ $i -le $len ]; do
    local char
    char=$(echo -n "$str" | cut -c $i)
    local test_str="${current}${char}"
    local test_w
    test_w=$(get_display_width "$test_str")
    if [ $test_w -gt $target_w ]; then
      break
    fi
    current="$test_str"
    i=$((i + 1))
  done
  echo -n "${current}..."
}

format_cname_info() {
  local domain="$1"
  local comment="$2"
  local full_str="$domain"
  if [ -n "$comment" ]; then
    full_str="${domain} (${comment})"
  fi
  truncate_display_width "$full_str" 41
}

# 6. 华丽的 Banner 并进行网络与代理状态探测
print_banner() {
  clear
  echo -e "${BLUE}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
  echo -e "${BLUE}${BOLD}│${NC}             ${CYAN}${BOLD}CLOUDFLARE 优选 IP 与域名测试工具${NC}            ${BLUE}${BOLD}│${NC}"
  echo -e "${BLUE}${BOLD}│${NC}     ${GRAY}- 自动动态抓取、绕过本地代理、多类别直连测速 -${NC}     ${BLUE}${BOLD}│${NC}"
  echo -e "${BLUE}${BOLD}└────────────────────────────────────────────────────────┘${NC}"
  echo ""
  
  echo -e "${GRAY}系统当前直连网络探测:${NC}"
  
  # 获取国内实际宽带 IP 与运营商（IPIP.NET 接口）
  local domestic_info=""
  domestic_info=$(curl -s --connect-timeout 3 --noproxy "*" "https://myip.ipip.net" 2>/dev/null)
  
  # 获取终端代理出口 IP
  local egress_ip=""
  egress_ip=$(curl -s --connect-timeout 3 "https://ip.sb" 2>/dev/null | tr -d '[:space:]')
  
  local domestic_ip=""
  local domestic_isp="未知运营商"
  local domestic_loc="未知位置"
  
  if [ -n "$domestic_info" ]; then
    domestic_ip=$(echo "$domestic_info" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n 1)
    domestic_loc=$(echo "$domestic_info" | sed -E 's/当前 IP：[^ ]+  来自于：//' | awk '{print $1" "$2}')
    if echo "$domestic_info" | grep -q "联通"; then
      domestic_isp="中国联通"
    elif echo "$domestic_info" | grep -q "电信"; then
      domestic_isp="中国电信"
    elif echo "$domestic_info" | grep -q "移动"; then
      domestic_isp="中国移动"
    else
      domestic_isp=$(echo "$domestic_info" | awk '{print $NF}')
    fi
  fi
  
  if [ -n "$domestic_ip" ]; then
    echo -e "  • 本机国内实际出口 IP: ${CYAN}${domestic_ip}${NC} [${domestic_isp} - ${domestic_loc}]"
  else
    echo -e "  • 本机国内实际出口 IP: ${RED}探测失败${NC}"
  fi
  
  if [ -n "$egress_ip" ]; then
    echo -e "  • 终端代理出口 IP    : ${CYAN}${egress_ip}${NC}"
  fi
  
  if [ -n "$ACTIVE_IFACE" ]; then
    echo -e "  • 物理测速绑定网卡    : ${GREEN}${ACTIVE_IFACE}${NC} (直连流量出口)"
  else
    echo -e "  • 物理测速绑定网卡    : ${YELLOW}未发现物理网卡，使用系统默认路由${NC}"
  fi
  echo -e "  • 当前带宽测速模式    : ${YELLOW}${BOLD}${TEST_MODE_NAME}${NC} (可运行 ${GRAY}./cf_speed_test.sh [fast|standard|gigabit]${NC} 切换)"
  
  # 代理检测与强力警告
  if [ -n "$domestic_ip" ] && [ -n "$egress_ip" ] && [ "$domestic_ip" != "$egress_ip" ]; then
    echo -e ""
    echo -e "${YELLOW}${BOLD}┌────────────────────────────────────────────────────────┐${NC}"
    echo -e "${YELLOW}${BOLD}│  ⚠️  提示：检测到当前终端环境正在运行代理服务（如 Clash） │${NC}"
    echo -e "${YELLOW}${BOLD}├────────────────────────────────────────────────────────┤${NC}"
    echo -e "${YELLOW}│  您的国内出口 IP 与代理出口 IP 不一致。                  │${NC}"
    echo -e "${YELLOW}│  本脚本已自动绑定本地活跃物理网卡 (${GREEN}${ACTIVE_IFACE:-默认}${YELLOW}) 进行直连测速。     │${NC}"
    echo -e "${YELLOW}│  直连测速将完全绕过代理 TUN 网卡接管，测速结果真实可靠。 │${NC}"
    echo -e "${YELLOW}${BOLD}└────────────────────────────────────────────────────────┘${NC}"
    echo ""
  else
    echo -e "  • 代理检测状态        : ${GREEN}未检测到全局代理网卡干扰，测试结果真实有效${NC}"
    echo ""
  fi
}

# 7. 延迟探测核心算法 (TCP 握手时间 - 1 RTT)
get_latency() {
  local ip="$1"
  local time_cost
  local iface_opt=""
  if [ -n "$ACTIVE_IFACE" ]; then
    iface_opt="--interface $ACTIVE_IFACE"
  fi
  # 使用 time_connect 探测物理 TCP 握手耗时 (1 RTT)，与小火箭等代理软件的测试标准保持一致
  time_cost=$(curl $iface_opt -o /dev/null -s -w "%{time_connect}" --connect-timeout 2 --max-time 3 --noproxy "*" --resolve "speed.cloudflare.com:443:$ip" "https://speed.cloudflare.com/__down?bytes=0" 2>/dev/null)
  local ec=$?
  if [ $ec -eq 0 ] && [ -n "$time_cost" ]; then
    local is_gt_zero
    is_gt_zero=$(awk -v t="$time_cost" 'BEGIN { print (t > 0) }')
    if [ "$is_gt_zero" -eq 1 ]; then
      local ms
      ms=$(awk -v t="$time_cost" 'BEGIN { printf "%.1f", t * 1000 }')
      echo "$ms"
      return
    fi
  fi
  echo "9999"
}

# 8. 顺序带宽测速核心算法 (自适应智能爬升大文件测速)
get_bandwidth() {
  local ip="$1"
  local speed
  local iface_opt=""
  if [ -n "$ACTIVE_IFACE" ]; then
    iface_opt="--interface $ACTIVE_IFACE"
  fi
  # 使用自适应智能爬升大文件进行下载测速，并设置硬超时。
  # 高带宽节点可在超时内完成下载并测出极高上限；普通节点超时截断但仍能准确折算出平均速率，在保证精度与测出千兆上限的前提下，最大程度缩减了测试耗时。
  speed=$(curl $iface_opt -o /dev/null -s -w "%{speed_download}" --connect-timeout 2 --max-time $TEST_TIMEOUT --noproxy "*" --resolve "speed.cloudflare.com:443:$ip" "https://speed.cloudflare.com/__down?bytes=$TEST_BYTES" 2>/dev/null)
  if [ -n "$speed" ] && [ "$(echo "$speed > 0" | bc 2>/dev/null || awk -v s="$speed" 'BEGIN { print (s > 0) }')" -eq 1 ]; then
    awk -v s="$speed" 'BEGIN { printf "%.2f", s / 1024 / 1024 }'
  else
    echo "0.00"
  fi
}

# 9. 运营商 CNAME 域名解析模块
parse_and_resolve_cnames() {
  local parsed_domains=""
  
  while IFS= read -r line; do
    line=$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -d '\r')
    [ -z "$line" ] && continue
    
    local domain=""
    local comment=""
    if [[ "$line" == *#* ]]; then
      domain="${line%%#*}"
      comment="${line#*#}"
    else
      domain="$line"
      comment=""
    fi
    
    local clean_domain
    clean_domain=$(echo "$domain" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    local clean_comment
    clean_comment=$(echo "$comment" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    
    [ -z "$clean_domain" ] && continue
    
    local resolve_target="$clean_domain"
    if [[ "$clean_domain" == \*.* ]]; then
      resolve_target="${clean_domain#\*.}"
    fi
    
    local found=false
    local new_list=""
    
    while IFS=';' read -r r_tgt d_dom c_cmt; do
      [ -z "$r_tgt" ] && continue
      if [ "$r_tgt" = "$resolve_target" ]; then
        found=true
        if [ -z "$c_cmt" ] && [ -n "$clean_comment" ]; then
          new_list="${new_list}${resolve_target};${clean_domain};${clean_comment}\n"
        else
          new_list="${new_list}${r_tgt};${d_dom};${c_cmt}\n"
        fi
      else
        new_list="${new_list}${r_tgt};${d_dom};${c_cmt}\n"
      fi
    done <<< "$parsed_domains"
    
    if [ "$found" = false ]; then
      parsed_domains="${parsed_domains}${resolve_target};${clean_domain};${clean_comment}\n"
    else
      parsed_domains="$new_list"
    fi
  done <<< "$DOMAINS_RAW"
  
  parsed_domains=$(echo -e "$parsed_domains" | grep -v '^$')
  
  echo -e "  正在使用阿里公共 DNS (223.5.5.5) 解析 ${CYAN}30+ 内置优选 CNAME 域名${NC}..." >&2
  
  local resolved_ips=""
  
  while IFS=';' read -r r_tgt d_dom c_cmt; do
    [ -z "$r_tgt" ] && continue
    
    local ips
    ips=$(nslookup -timeout=2 "$r_tgt" 223.5.5.5 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | grep -v '223.5.5.5' | sort -u)
    
    if [ -n "$ips" ]; then
      while read -r ip; do
        [ -z "$ip" ] && continue
        resolved_ips="${resolved_ips}${ip};${d_dom};${c_cmt}\n"
      done <<< "$ips"
    fi
  done <<< "$parsed_domains"
  
  resolved_ips=$(echo -e "$resolved_ips" | grep -v '^$')
  
  local unique_ips=""
  while IFS=';' read -r ip d_dom c_cmt; do
    [ -z "$ip" ] && continue
    if [[ "$unique_ips" != *"$ip;"* ]]; then
      unique_ips="${unique_ips}${ip};${d_dom};${c_cmt}\n"
    fi
  done <<< "$resolved_ips"
  
  echo -e "${GREEN}  ✔ 域名解析完毕，成功获取了 $(echo -e "$unique_ips" | grep -v '^$' | wc -l | tr -d ' ') 个唯一的优选域名 IP。${NC}" >&2
  echo -e "$unique_ips" | grep -v '^$'
}

# 10. API 优选 IP 抓取模块
fetch_api_ips() {
  local ct_url="https://cf.090227.xyz/ct?ips=20"
  local cu_url="https://cf.090227.xyz/cu?ips=20"
  local cm_url="https://cf.090227.xyz/cmcc?ips=20"
  
  local raw_ips=""
  
  echo -e "  正在从 cf.090227.xyz 抓取 ${CYAN}API 官方推荐 IP 节点${NC}..." >&2
  
  local ct_data
  ct_data=$(curl -s --connect-timeout 4 --noproxy "*" "$ct_url")
  if [ -n "$ct_data" ]; then
    raw_ips="${raw_ips}${ct_data}\n"
  fi
  
  local cu_data
  cu_data=$(curl -s --connect-timeout 4 --noproxy "*" "$cu_url")
  if [ -n "$cu_data" ]; then
    raw_ips="${raw_ips}${cu_data}\n"
  fi
  
  local cm_data
  cm_data=$(curl -s --connect-timeout 4 --noproxy "*" "$cm_url")
  if [ -n "$cm_data" ]; then
    raw_ips="${raw_ips}${cm_data}\n"
  fi
  
  local api_ips=""
  while read -r line; do
    line=$(echo "$line" | tr -d ' ' | tr -d '\r')
    [ -z "$line" ] && continue
    
    local ip=""
    local comment=""
    if [[ "$line" == *#* ]]; then
      ip="${line%%#*}"
      comment="${line#*#}"
    else
      ip="$line"
      comment="CF优选-未知"
    fi
    
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
      local isp="其他"
      if [[ "$comment" == *电信* ]]; then
        isp="中国电信"
      elif [[ "$comment" == *联通* ]]; then
        isp="中国联通"
      elif [[ "$comment" == *移动* ]]; then
        isp="中国移动"
      fi
      api_ips="${api_ips}${ip};${isp};${comment}\n"
    fi
  done <<< "$raw_ips"
  
  local unique_api_ips=""
  while IFS=';' read -r ip isp cmt; do
    [ -z "$ip" ] && continue
    if [[ "$unique_api_ips" != *"$ip;"* ]]; then
      unique_api_ips="${unique_api_ips}${ip};${isp};${cmt}\n"
    fi
  done <<< "$api_ips"
  
  echo -e "${GREEN}  ✔ 优选 IP 抓取完毕，成功获取了 $(echo -e "$unique_api_ips" | grep -v '^$' | wc -l | tr -d ' ') 个唯一的官方 IP 节点。${NC}" >&2
  echo -e "$unique_api_ips" | grep -v '^$'
}

# 11. 各分类排行榜渲染函数
print_isp_table() {
  local isp_title="$1"
  local results_file="$2"
  
  local r_w=$((IP_W_RANK - 2))
  local i_w=$((IP_W_IP - 2))
  local isp_w=$((IP_W_ISP - 2))
  local l_w=$((IP_W_LAT - 2))
  local s_w=$((IP_W_SPD - 2))
  local src_w=$((IP_W_SRC - 2))

  local line_sep="├$(generate_border_line $IP_W_RANK)┼$(generate_border_line $IP_W_IP)┼$(generate_border_line $IP_W_ISP)┼$(generate_border_line $IP_W_LAT)┼$(generate_border_line $IP_W_SPD)┼$(generate_border_line $IP_W_SRC)┤"
  local line_bot="└$(generate_border_line $IP_W_RANK)┴$(generate_border_line $IP_W_IP)┴$(generate_border_line $IP_W_ISP)┴$(generate_border_line $IP_W_LAT)┴$(generate_border_line $IP_W_SPD)┴$(generate_border_line $IP_W_SRC)┘"

  local table_width=$(( IP_W_RANK + IP_W_IP + IP_W_ISP + IP_W_LAT + IP_W_SPD + IP_W_SRC + 5 ))
  local title_str="📊 CLOUDFLARE 优选 IP 排行榜 - ${isp_title} (Top 10)"
  
  local tw
  tw=$(get_display_width "$title_str")
  local title_padding=$(( (table_width - tw) / 2 ))
  
  local pad_left=""
  for ((i=0; i<title_padding; i++)); do pad_left="${pad_left} "; done
  local title_line="${pad_left}${title_str}"
  title_line=$(pad_string "$title_line" $table_width "left")

  echo -e "${BLUE}${BOLD}┌$(generate_border_line $table_width)┐${NC}"
  echo -e "${BLUE}${BOLD}│${NC}${BOLD}${title_line}${BLUE}${BOLD}│${NC}"
  echo -e "${BLUE}${BOLD}${line_sep}${NC}"
  echo -e "${BLUE}${BOLD}│${NC} $(pad_string "排名" $r_w "left") ${BLUE}${BOLD}│${NC} $(pad_string "IP 地址" $i_w "left") ${BLUE}${BOLD}│${NC} $(pad_string "归属运营商" $isp_w "left") ${BLUE}${BOLD}│${NC} $(pad_string "延迟" $l_w "right") ${BLUE}${BOLD}│${NC} $(pad_string "下载速度" $s_w "right") ${BLUE}${BOLD}│${NC} $(pad_string "数据来源" $src_w "left") ${BLUE}${BOLD}│${NC}"
  echo -e "${BLUE}${BOLD}${line_sep}${NC}"
  
  if [ ! -s "$results_file" ]; then
    local err_msg="无可用的优选 IP 测试结果，请检查网络。"
    local err_w=$(( table_width - 2 ))
    echo -e "${BLUE}${BOLD}│${NC} $(pad_string "${RED}${err_msg}${NC}" $err_w "left") ${BLUE}${BOLD}│${NC}"
  else
    while IFS=';' read -r rank ip isp lat speed cmt; do
      local rank_color="${NC}"
      if [ "$rank" -eq 1 ]; then
        rank_color="${YELLOW}${BOLD}"
      elif [ "$rank" -le 3 ]; then
        rank_color="${CYAN}${BOLD}"
      fi
      
      local lat_str="${lat} ms"
      local speed_str="${speed} MB/s"
      if [ "$speed" = "0.00" ] || [ "$speed" = "--" ]; then
        speed_str="--"
      fi
      
      local clean_cmt
      clean_cmt=$(truncate_display_width "$cmt" $src_w)
      
      echo -e "${BLUE}${BOLD}│${NC} $(pad_string "$rank" $r_w "left" "${rank_color}") ${BLUE}${BOLD}│${NC} $(pad_string "$ip" $i_w "left") ${BLUE}${BOLD}│${NC} $(pad_string "$isp" $isp_w "left") ${BLUE}${BOLD}│${NC} $(pad_string "$lat_str" $l_w "right" "${GREEN}") ${BLUE}${BOLD}│${NC} $(pad_string "$speed_str" $s_w "right" "${YELLOW}") ${BLUE}${BOLD}│${NC} $(pad_string "$clean_cmt" $src_w "left") ${BLUE}${BOLD}│${NC}"
    done < "$results_file"
  fi
  echo -e "${BLUE}${BOLD}${line_bot}${NC}"
}

print_cname_table() {
  local r_w=$((CN_W_RANK - 2))
  local i_w=$((CN_W_IP - 2))
  local isp_w=$((CN_W_ISP - 2))
  local l_w=$((CN_W_LAT - 2))
  local s_w=$((CN_W_SPD - 2))
  local dom_w=$((CN_W_DOM - 2))

  local line_sep="├$(generate_border_line $CN_W_RANK)┼$(generate_border_line $CN_W_IP)┼$(generate_border_line $CN_W_ISP)┼$(generate_border_line $CN_W_LAT)┼$(generate_border_line $CN_W_SPD)┼$(generate_border_line $CN_W_DOM)┤"
  local line_bot="└$(generate_border_line $CN_W_RANK)┴$(generate_border_line $CN_W_IP)┴$(generate_border_line $CN_W_ISP)┴$(generate_border_line $CN_W_LAT)┴$(generate_border_line $CN_W_SPD)┴$(generate_border_line $CN_W_DOM)┘"

  local table_width=$(( CN_W_RANK + CN_W_IP + CN_W_ISP + CN_W_LAT + CN_W_SPD + CN_W_DOM + 5 ))
  local title_str="📊 CLOUDFLARE 优选 CNAME 域名排行榜 (Top 10)"
  
  local tw
  tw=$(get_display_width "$title_str")
  local title_padding=$(( (table_width - tw) / 2 ))
  
  local pad_left=""
  for ((i=0; i<title_padding; i++)); do pad_left="${pad_left} "; done
  local title_line="${pad_left}${title_str}"
  title_line=$(pad_string "$title_line" $table_width "left")

  echo -e "${BLUE}${BOLD}┌$(generate_border_line $table_width)┐${NC}"
  echo -e "${BLUE}${BOLD}│${NC}${BOLD}${title_line}${BLUE}${BOLD}│${NC}"
  echo -e "${BLUE}${BOLD}${line_sep}${NC}"
  echo -e "${BLUE}${BOLD}│${NC} $(pad_string "排名" $r_w "left") ${BLUE}${BOLD}│${NC} $(pad_string "IP 地址" $i_w "left") ${BLUE}${BOLD}│${NC} $(pad_string "归属运营商" $isp_w "left") ${BLUE}${BOLD}│${NC} $(pad_string "延迟" $l_w "right") ${BLUE}${BOLD}│${NC} $(pad_string "下载速度" $s_w "right") ${BLUE}${BOLD}│${NC} $(pad_string "解析域名 & 备注" $dom_w "left") ${BLUE}${BOLD}│${NC}"
  echo -e "${BLUE}${BOLD}${line_sep}${NC}"
  
  if [ ! -s "$CNAME_FINAL_RESULTS" ]; then
    local err_msg="无可用的优选 CNAME 域名测试结果，请检查网络。"
    local err_w=$(( table_width - 2 ))
    echo -e "${BLUE}${BOLD}│${NC} $(pad_string "${RED}${err_msg}${NC}" $err_w "left") ${BLUE}${BOLD}│${NC}"
  else
    while IFS=';' read -r rank ip isp lat speed d_dom c_cmt; do
      local rank_color="${NC}"
      if [ "$rank" -eq 1 ]; then
        rank_color="${YELLOW}${BOLD}"
      elif [ "$rank" -le 3 ]; then
        rank_color="${CYAN}${BOLD}"
      fi
      
      local lat_str="${lat} ms"
      local speed_str="${speed} MB/s"
      if [ "$speed" = "0.00" ] || [ "$speed" = "--" ]; then
        speed_str="--"
      fi
      
      local cname_display
      cname_display=$(format_cname_info "$d_dom" "$c_cmt")
      
      echo -e "${BLUE}${BOLD}│${NC} $(pad_string "$rank" $r_w "left" "${rank_color}") ${BLUE}${BOLD}│${NC} $(pad_string "$ip" $i_w "left") ${BLUE}${BOLD}│${NC} $(pad_string "$isp" $isp_w "left") ${BLUE}${BOLD}│${NC} $(pad_string "$lat_str" $l_w "right" "${GREEN}") ${BLUE}${BOLD}│${NC} $(pad_string "$speed_str" $s_w "right" "${YELLOW}") ${BLUE}${BOLD}│${NC} $(pad_string "$cname_display" $dom_w "left") ${BLUE}${BOLD}│${NC}"
    done < "$CNAME_FINAL_RESULTS"
  fi
  echo -e "${BLUE}${BOLD}${line_bot}${NC}"
}

# 12. 主执行流程
main() {
  check_requirements
  
  # 创建高稳定性临时目录
  TEMP_DIR=$(mktemp -d /tmp/cf_speed_test_XXXXXX)
  trap 'rm -rf "$TEMP_DIR"' EXIT
  
  print_banner
  
  # Phase 1: 获取数据源
  echo -e "${BOLD}[Phase 1/5] 数据源加载与域名解析${NC}"
  
  CNAME_IPS_DATA=$(parse_and_resolve_cnames)
  echo ""
  
  API_IPS_DATA=$(fetch_api_ips)
  echo ""
  
  # 合并去重 IP 以进行并行测试
  echo -e "${BOLD}[Phase 2/5] 极速并发 HTTPS 延迟探测${NC}"
  
  local UNIQUE_IPS_FILE="$TEMP_DIR/unique_ips.txt"
  > "$UNIQUE_IPS_FILE"
  
  local all_ips=""
  while IFS=';' read -r ip isp cmt; do
    [ -z "$ip" ] && continue
    all_ips="${all_ips}${ip}\n"
  done <<< "$API_IPS_DATA"
  
  while IFS=';' read -r ip d_dom c_cmt; do
    [ -z "$ip" ] && continue
    all_ips="${all_ips}${ip}\n"
  done <<< "$CNAME_IPS_DATA"
  
  echo -e "$all_ips" | grep -v '^$' | sort -u > "$UNIQUE_IPS_FILE"
  local total_unique
  total_unique=$(wc -l < "$UNIQUE_IPS_FILE" | tr -d ' ')
  
  if [ "$total_unique" -eq 0 ]; then
    echo -e "${RED}[ERROR] 没有任何解析或抓取到的 Cloudflare IP！请检查您的网络连接后再试。${NC}"
    exit 1
  fi
  
  local LATENCY_RESULTS="$TEMP_DIR/latency_results.txt"
  > "$LATENCY_RESULTS"
  
  # 使用高兼容 POSIX 命名管道作为并发信号量
  local fifo="$TEMP_DIR/fifo_$$"
  mkfifo "$fifo"
  exec 9<>"$fifo"
  rm -f "$fifo"
  
  local max_jobs=20
  for ((i=0; i<max_jobs; i++)); do
    echo >&9
  done
  
  # 启动后台实时进度显示
  (
    local completed=0
    while [ "$completed" -lt "$total_unique" ]; do
      completed=$(wc -l < "$LATENCY_RESULTS" 2>/dev/null || echo 0)
      completed=$(echo "$completed" | xargs)
      local percent=$((completed * 100 / total_unique))
      
      local last_ip="--"
      local last_line
      last_line=$(tail -n 1 "$LATENCY_RESULTS" 2>/dev/null)
      if [ -n "$last_line" ]; then
        last_ip=${last_line%%;*}
      fi
      
      echo -ne "  正在并发评估延迟中 [${percent}%] (${completed}/${total_unique}): 当前检测 ${BLUE}${last_ip}${NC} ...\r"
      sleep 0.1
    done
    echo -ne "  正在并发评估延迟中 [100%] (${total_unique}/${total_unique}): 评估已全部完成！\n"
  ) &
  local progress_pid=$!
  
  # 分发并发任务
  while read -r ip; do
    [ -z "$ip" ] && continue
    read -r <&9
    (
      local lat
      lat=$(get_latency "$ip")
      echo "$ip;$lat" >> "$LATENCY_RESULTS"
      echo >&9
    ) &
  done < "$UNIQUE_IPS_FILE"
  
  wait
  kill "$progress_pid" 2>/dev/null
  wait "$progress_pid" 2>/dev/null
  echo ""
  
  # Phase 3: 映射和带宽测试
  echo -e "${BOLD}[Phase 3/5] 独立带宽直连测速 (${TEST_MODE_NAME} - 各分类 Top 10 节点)${NC}"
  
  # 映射 API IP 延迟并排序
  local API_LATENCY_MAPPED="$TEMP_DIR/api_latency_mapped.txt"
  > "$API_LATENCY_MAPPED"
  while IFS=';' read -r ip isp cmt; do
    [ -z "$ip" ] && continue
    local lat
    lat=$(grep -w "^$ip" "$LATENCY_RESULTS" | cut -d';' -f2 | head -n 1)
    [ -z "$lat" ] && lat="9999"
    if [ "$lat" != "9999" ] && [ "$lat" != "9999.0" ]; then
      echo "$lat;$ip;$isp;$cmt" >> "$API_LATENCY_MAPPED"
    fi
  done <<< "$API_IPS_DATA"
  
  # 分别提取各运营商的 Top 10 最低延迟 IP
  local CT_TOP_10="$TEMP_DIR/ct_top_10.txt"
  grep -w "中国电信" "$API_LATENCY_MAPPED" | sort -n | head -n 10 > "$CT_TOP_10"
  
  local CU_TOP_10="$TEMP_DIR/cu_top_10.txt"
  grep -w "中国联通" "$API_LATENCY_MAPPED" | sort -n | head -n 10 > "$CU_TOP_10"
  
  local CM_TOP_10="$TEMP_DIR/cm_top_10.txt"
  grep -w "中国移动" "$API_LATENCY_MAPPED" | sort -n | head -n 10 > "$CM_TOP_10"
  
  # 映射 CNAME IP 延迟并排序并提取 Top 10
  local CNAME_LATENCY_MAPPED="$TEMP_DIR/cname_latency_mapped.txt"
  > "$CNAME_LATENCY_MAPPED"
  while IFS=';' read -r ip d_dom c_cmt; do
    [ -z "$ip" ] && continue
    local lat
    lat=$(grep -w "^$ip" "$LATENCY_RESULTS" | cut -d';' -f2 | head -n 1)
    [ -z "$lat" ] && lat="9999"
    if [ "$lat" != "9999" ] && [ "$lat" != "9999.0" ]; then
      echo "$lat;$ip;$d_dom;$c_cmt" >> "$CNAME_LATENCY_MAPPED"
    fi
  done <<< "$CNAME_IPS_DATA"
  
  local CNAME_TOP_10="$TEMP_DIR/cname_top_10.txt"
  # 以域名为维度去重展示：对同一 CNAME 域名仅保留其解析出的延迟最低 (最佳) 的那一个 IP 节点
  sort -t';' -k1,1n "$CNAME_LATENCY_MAPPED" | awk -F';' '!visited[$3]++' | head -n 10 > "$CNAME_TOP_10"
  
  # 建立带宽缓存，防止重复压测
  local BANDWIDTH_CACHE="$TEMP_DIR/bandwidth_cache.txt"
  > "$BANDWIDTH_CACHE"
  
  get_bandwidth_cached() {
    local ip="$1"
    local cached
    cached=$(grep -w "^$ip" "$BANDWIDTH_CACHE" | cut -d';' -f2 | head -n 1)
    if [ -n "$cached" ]; then
      echo "$cached"
      return
    fi
    local speed
    speed=$(get_bandwidth "$ip")
    echo "$ip;$speed" >> "$BANDWIDTH_CACHE"
    echo "$speed"
  }
  
  # 压测电信 Top 10
  echo -e "  正在对 ${YELLOW}中国电信 Top 10 节点${NC} 进行带宽直连测速..."
  local CT_FINAL_RESULTS="$TEMP_DIR/ct_final_results.txt"
  > "$CT_FINAL_RESULTS"
  local rank=1
  while IFS=';' read -r lat ip isp cmt; do
    [ -z "$ip" ] && continue
    echo -ne "    • 正在测速 电信 IP: ${BLUE}${ip}${NC} ...\r"
    local speed
    speed=$(get_bandwidth_cached "$ip")
    echo "$rank;$ip;$isp;$lat;$speed;$cmt" >> "$CT_FINAL_RESULTS"
    rank=$((rank + 1))
  done < "$CT_TOP_10"
  echo -e "    ${GREEN}✔ 中国电信 Top 10 直连测速全部完成！${NC}"
  
  # 压测联通 Top 10
  echo -e "  正在对 ${YELLOW}中国联通 Top 10 节点${NC} 进行带宽直连测速..."
  local CU_FINAL_RESULTS="$TEMP_DIR/cu_final_results.txt"
  > "$CU_FINAL_RESULTS"
  rank=1
  while IFS=';' read -r lat ip isp cmt; do
    [ -z "$ip" ] && continue
    echo -ne "    • 正在测速 联通 IP: ${BLUE}${ip}${NC} ...\r"
    local speed
    speed=$(get_bandwidth_cached "$ip")
    echo "$rank;$ip;$isp;$lat;$speed;$cmt" >> "$CU_FINAL_RESULTS"
    rank=$((rank + 1))
  done < "$CU_TOP_10"
  echo -e "    ${GREEN}✔ 中国联通 Top 10 直连测速全部完成！${NC}"
  
  # 压测移动 Top 10
  echo -e "  正在对 ${YELLOW}中国移动 Top 10 节点${NC} 进行带宽直连测速..."
  local CM_FINAL_RESULTS="$TEMP_DIR/cm_final_results.txt"
  > "$CM_FINAL_RESULTS"
  rank=1
  while IFS=';' read -r lat ip isp cmt; do
    [ -z "$ip" ] && continue
    echo -ne "    • 正在测速 移动 IP: ${BLUE}${ip}${NC} ...\r"
    local speed
    speed=$(get_bandwidth_cached "$ip")
    echo "$rank;$ip;$isp;$lat;$speed;$cmt" >> "$CM_FINAL_RESULTS"
    rank=$((rank + 1))
  done < "$CM_TOP_10"
  echo -e "    ${GREEN}✔ 中国移动 Top 10 直连测速全部完成！${NC}"
  
  # 压测 CNAME Top 10
  echo -e "  正在对 ${YELLOW}CNAME 域名 Top 10 节点${NC} 进行带宽直连测速..."
  local CNAME_FINAL_RESULTS="$TEMP_DIR/cname_final_results.txt"
  > "$CNAME_FINAL_RESULTS"
  rank=1
  while IFS=';' read -r lat ip d_dom c_cmt; do
    [ -z "$ip" ] && continue
    echo -ne "    • 正在测速 域名 IP: ${BLUE}${ip}${NC} ...\r"
    local speed
    speed=$(get_bandwidth_cached "$ip")
    
    local isp="CF 边缘节点"
    local api_isp_lookup
    api_isp_lookup=$(grep -w "^$ip" "$API_LATENCY_MAPPED" | cut -d';' -f3 | head -n 1)
    if [ -n "$api_isp_lookup" ]; then
      isp="$api_isp_lookup"
    fi
    
    echo "$rank;$ip;$isp;$lat;$speed;$d_dom;$c_cmt" >> "$CNAME_FINAL_RESULTS"
    rank=$((rank + 1))
  done < "$CNAME_TOP_10"
  echo -e "    ${GREEN}✔ CNAME 域名 Top 10 直连测速全部完成！${NC}"
  echo ""
  
  # Phase 4: 渲染表格
  echo -e "${BOLD}[Phase 4/5] 各运营商排行榜渲染${NC}"
  
  # 报表列宽定义
  IP_W_RANK=6; IP_W_IP=16; IP_W_ISP=20; IP_W_LAT=12; IP_W_SPD=14; IP_W_SRC=20
  CN_W_RANK=6; CN_W_IP=16; CN_W_ISP=20; CN_W_LAT=12; CN_W_SPD=14; CN_W_DOM=45
  
  print_isp_table "中国电信" "$CT_FINAL_RESULTS"
  echo ""
  print_isp_table "中国联通" "$CU_FINAL_RESULTS"
  echo ""
  print_isp_table "中国移动" "$CM_FINAL_RESULTS"
  echo ""
  print_cname_table
  echo ""
  
  # Phase 5: 渲染最佳卡片
  echo -e "${BOLD}[Phase 5/5] 最佳直连节点一键推荐卡片${NC}"
  
  # 寻找最佳参数
  local best_cn_ip=""
  local best_cn_domain=""
  local best_cn_comment=""
  local best_cn_speed="0.00"
  local best_cn_lat="9999"
  
  if [ -s "$CNAME_FINAL_RESULTS" ]; then
    IFS=';' read -r rank ip isp lat speed d_dom c_cmt < "$CNAME_FINAL_RESULTS"
    best_cn_ip="$ip"
    best_cn_domain="$d_dom"
    best_cn_comment="$c_cmt"
    best_cn_speed="$speed"
    best_cn_lat="$lat"
  fi
  
  # 整合三大运营商数据，计算综合最佳直连 IP
  local best_ip=""
  local best_ip_isp=""
  local best_ip_speed="0.00"
  local best_ip_lat="9999"
  
  local ALL_IPS_FINAL="$TEMP_DIR/all_ips_final.txt"
  > "$ALL_IPS_FINAL"
  [ -s "$CT_FINAL_RESULTS" ] && cat "$CT_FINAL_RESULTS" >> "$ALL_IPS_FINAL"
  [ -s "$CU_FINAL_RESULTS" ] && cat "$CU_FINAL_RESULTS" >> "$ALL_IPS_FINAL"
  [ -s "$CM_FINAL_RESULTS" ] && cat "$CM_FINAL_RESULTS" >> "$ALL_IPS_FINAL"
  
  if [ -s "$ALL_IPS_FINAL" ]; then
    local best_line
    best_line=$(sort -t';' -k4,4n -k5,5nr "$ALL_IPS_FINAL" | head -n 1)
    if [ -n "$best_line" ]; then
      local rank ip isp lat speed cmt
      IFS=';' read -r rank ip isp lat speed cmt <<< "$best_line"
      best_ip="$ip"
      best_ip_isp="$isp"
      best_ip_speed="$speed"
      best_ip_lat="$lat"
    fi
  fi
  
  find_best_for_isp() {
    local target_isp="$1"
    local results_file=""
    if [ "$target_isp" = "中国电信" ]; then
      results_file="$CT_FINAL_RESULTS"
    elif [ "$target_isp" = "中国联通" ]; then
      results_file="$CU_FINAL_RESULTS"
    elif [ "$target_isp" = "中国移动" ]; then
      results_file="$CM_FINAL_RESULTS"
    fi
    
    if [ -s "$results_file" ]; then
      local rank ip isp lat speed cmt
      IFS=';' read -r rank ip isp lat speed cmt < "$results_file"
      echo "$ip;$lat;$speed"
      return
    fi
    echo "--;--;--"
  }
  
  print_recommendation_card() {
    local ct_best
    ct_best=$(find_best_for_isp "中国电信")
    local cu_best
    cu_best=$(find_best_for_isp "中国联通")
    local cm_best
    cm_best=$(find_best_for_isp "中国移动")
    
    local ct_ip ct_lat ct_spd
    IFS=';' read -r ct_ip ct_lat ct_spd <<< "$ct_best"
    local cu_ip cu_lat cu_spd
    IFS=';' read -r cu_ip cu_lat cu_spd <<< "$cu_best"
    local cm_ip cm_lat cm_spd
    IFS=';' read -r cm_ip cm_lat cm_spd <<< "$cm_best"
    
    local card_w=90
    local inner_w=$((card_w - 4))
    
    echo -e "${YELLOW}${BOLD}┌$(generate_border_line $card_w)┐${NC}"
    
    local title="🏆 CLOUDFLARE 最佳直连节点推荐"
    local w
    w=$(get_display_width "$title")
    local pad_total=$((card_w - w))
    local pad_left=$((pad_total / 2))
    local pad_right=$((pad_total - pad_left))
    local spaces_left=""
    local spaces_right=""
    for ((i=0; i<pad_left; i++)); do spaces_left="${spaces_left} "; done
    for ((i=0; i<pad_right; i++)); do spaces_right="${spaces_right} "; done
    echo -e "${YELLOW}${BOLD}│${NC}${spaces_left}${title}${spaces_right}${YELLOW}${BOLD}│${NC}"
    
    echo -e "${YELLOW}${BOLD}├$(generate_border_line $card_w)┤${NC}"
    
    if [ -n "$best_cn_ip" ]; then
      local cn_desc="$best_cn_domain"
      if [ -n "$best_cn_comment" ]; then
        cn_desc="${best_cn_domain} (${best_cn_comment})"
      fi
      local plain_line="  • 推荐 CNAME 域名 :  ${cn_desc} -> ${best_cn_ip} [${best_cn_lat} ms | ${best_cn_speed} MB/s]"
      w=$(get_display_width "$plain_line")
      local pad_len=$((inner_w - w))
      local spaces=""
      for ((i=0; i<pad_len; i++)); do spaces="${spaces} "; done
      
      local cn_line="  • 推荐 CNAME 域名 :  ${CYAN}${BOLD}${cn_desc}${NC} -> ${GREEN}${best_cn_ip}${NC} [${best_cn_lat} ms | ${best_cn_speed} MB/s]${spaces}"
      echo -e "${YELLOW}${BOLD}│${NC} ${cn_line} ${YELLOW}${BOLD}│${NC}"
    fi
    
    if [ -n "$best_ip" ]; then
      local plain_line="  • 综合最佳直连 IP  :  ${best_ip} [${best_ip_isp} | ${best_ip_lat} ms | ${best_ip_speed} MB/s]"
      w=$(get_display_width "$plain_line")
      local pad_len=$((inner_w - w))
      local spaces=""
      for ((i=0; i<pad_len; i++)); do spaces="${spaces} "; done
      
      local ip_line="  • 综合最佳直连 IP  :  ${CYAN}${BOLD}${best_ip}${NC} [${best_ip_isp} | ${GREEN}${best_ip_lat} ms${NC} | ${YELLOW}${best_ip_speed} MB/s${NC}]${spaces}"
      echo -e "${YELLOW}${BOLD}│${NC} ${ip_line} ${YELLOW}${BOLD}│${NC}"
    fi
    
    echo -e "${YELLOW}${BOLD}├$(generate_border_line $card_w)┤${NC}"
    
    local plain_line="  分运营商最佳直连 IP 推荐:"
    w=$(get_display_width "$plain_line")
    local pad_len=$((inner_w - w))
    local spaces=""
    for ((i=0; i<pad_len; i++)); do spaces="${spaces} "; done
    local section_line="  ${BOLD}分运营商最佳直连 IP 推荐:${NC}${spaces}"
    echo -e "${YELLOW}${BOLD}│${NC} ${section_line} ${YELLOW}${BOLD}│${NC}"
    
    # Telecom
    plain_line="    • 中国电信 最佳 IP:  "
    if [ "$ct_ip" != "--" ]; then
      plain_line="${plain_line}${ct_ip} [${ct_lat} ms | ${ct_spd} MB/s]"
    else
      plain_line="${plain_line}无可用节点"
    fi
    w=$(get_display_width "$plain_line")
    pad_len=$((inner_w - w))
    spaces=""
    for ((i=0; i<pad_len; i++)); do spaces="${spaces} "; done
    
    local ct_line="    • 中国电信 最佳 IP:  "
    if [ "$ct_ip" != "--" ]; then
      ct_line="${ct_line}${CYAN}${ct_ip}${NC} [${GREEN}${ct_lat} ms${NC} | ${YELLOW}${ct_spd} MB/s${NC}]${spaces}"
    else
      ct_line="${ct_line}${GRAY}无可用节点${NC}${spaces}"
    fi
    echo -e "${YELLOW}${BOLD}│${NC} ${ct_line} ${YELLOW}${BOLD}│${NC}"
    
    # Unicom
    plain_line="    • 中国联通 最佳 IP:  "
    if [ "$cu_ip" != "--" ]; then
      plain_line="${plain_line}${cu_ip} [${cu_lat} ms | ${cu_spd} MB/s]"
    else
      plain_line="${plain_line}无可用节点"
    fi
    w=$(get_display_width "$plain_line")
    pad_len=$((inner_w - w))
    spaces=""
    for ((i=0; i<pad_len; i++)); do spaces="${spaces} "; done
    
    local cu_line="    • 中国联通 最佳 IP:  "
    if [ "$cu_ip" != "--" ]; then
      cu_line="${cu_line}${CYAN}${cu_ip}${NC} [${GREEN}${cu_lat} ms${NC} | ${YELLOW}${cu_spd} MB/s${NC}]${spaces}"
    else
      cu_line="${cu_line}${GRAY}无可用节点${NC}${spaces}"
    fi
    echo -e "${YELLOW}${BOLD}│${NC} ${cu_line} ${YELLOW}${BOLD}│${NC}"
    
    # Mobile
    plain_line="    • 中国移动 最佳 IP:  "
    if [ "$cm_ip" != "--" ]; then
      plain_line="${plain_line}${cm_ip} [${cm_lat} ms | ${cm_spd} MB/s]"
    else
      plain_line="${plain_line}无可用节点"
    fi
    w=$(get_display_width "$plain_line")
    pad_len=$((inner_w - w))
    spaces=""
    for ((i=0; i<pad_len; i++)); do spaces="${spaces} "; done
    
    local cm_line="    • 中国移动 最佳 IP:  "
    if [ "$cm_ip" != "--" ]; then
      cm_line="${cm_line}${CYAN}${cm_ip}${NC} [${GREEN}${cm_lat} ms${NC} | ${YELLOW}${cm_spd} MB/s${NC}]${spaces}"
    else
      cm_line="${cm_line}${GRAY}无可用节点${NC}${spaces}"
    fi
    echo -e "${YELLOW}${BOLD}│${NC} ${cm_line} ${YELLOW}${BOLD}│${NC}"
    
    echo -e "${YELLOW}${BOLD}├$(generate_border_line $card_w)┤${NC}"
    
    # Port title
    plain_line="  📡 Cloudflare CDN 支持端口参考信息:"
    w=$(get_display_width "$plain_line")
    pad_len=$((inner_w - w))
    spaces=""
    for ((i=0; i<pad_len; i++)); do spaces="${spaces} "; done
    local port_title="  📡 ${BOLD}Cloudflare CDN 支持端口参考信息:${NC}${spaces}"
    echo -e "${YELLOW}${BOLD}│${NC} ${port_title} ${YELLOW}${BOLD}│${NC}"
    
    # HTTP ports
    plain_line="    • HTTP 支持端口 :  80, 8080, 8880, 2052, 2082, 2086, 2095"
    w=$(get_display_width "$plain_line")
    pad_len=$((inner_w - w))
    spaces=""
    for ((i=0; i<pad_len; i++)); do spaces="${spaces} "; done
    local http_port_line="    • HTTP 支持端口 :  ${CYAN}80, 8080, 8880, 2052, 2082, 2086, 2095${NC}${spaces}"
    echo -e "${YELLOW}${BOLD}│${NC} ${http_port_line} ${YELLOW}${BOLD}│${NC}"
    
    # HTTPS ports
    plain_line="    • HTTPS 支持端口:  443, 2053, 2083, 2087, 2096, 8443"
    w=$(get_display_width "$plain_line")
    pad_len=$((inner_w - w))
    spaces=""
    for ((i=0; i<pad_len; i++)); do spaces="${spaces} "; done
    local https_port_line="    • HTTPS 支持端口:  ${CYAN}443, 2053, 2083, 2087, 2096, 8443${NC}${spaces}"
    echo -e "${YELLOW}${BOLD}│${NC} ${https_port_line} ${YELLOW}${BOLD}│${NC}"
    
    echo -e "${YELLOW}${BOLD}└$(generate_border_line $card_w)┘${NC}"
  }
  
  print_recommendation_card
}

main "$@"
