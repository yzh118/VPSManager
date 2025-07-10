#!/bin/bash

# 文字样式变量定义：绿色粗体
CD=$'\033[1;32m'
CDB=$'\033[1;34m'
CDR=$'\033[1;31m'
NC=$'\033[0m'

# 配置文件和缓存
CONFIG_DIR="/usr/local/vpsmanager/config"
CACHE_DIR="/usr/local/vpsmanager/cache"
CACHE_FILE="$CACHE_DIR/yysc.conf"
MARKET_URL_FILE="$CONFIG_DIR/market_url.txt"

# 确保配置目录存在
mkdir -p "$CONFIG_DIR" "$CACHE_DIR"

# 获取应用市场URL
get_market_url() {
    if [ -f "$MARKET_URL_FILE" ]; then
        cat "$MARKET_URL_FILE"
    else
        echo "https://example.com/yysc.json"
    fi
}

# 保存应用市场URL
save_market_url() {
    echo "$1" > "$MARKET_URL_FILE"
}

# 应用市场功能
fetch_app_market() {
    local market_url=$1
    local tmp_file="/tmp/yysc.conf"
    
    echo "${CDB}正在获取应用市场信息...${NC}"
    echo "${CDB}URL: $market_url${NC}"
    
    # 下载配置文件，添加详细输出
    if ! wget --no-check-certificate -v -O "$tmp_file" "$market_url" 2>&1; then
        echo "${CDR}获取应用市场信息失败${NC}"
        echo "${CDR}请检查URL是否正确以及网络连接是否正常${NC}"
        # 如果文件存在但下载失败，显示内容
        if [ -f "$tmp_file" ]; then
            echo "${CDB}下载的内容：${NC}"
            cat "$tmp_file"
        fi
        return 1
    fi
    
    # 检查文件是否为空
    if [ ! -s "$tmp_file" ]; then
        echo "${CDR}应用市场数据为空${NC}"
        rm -f "$tmp_file"
        return 1
    fi
    
    # 检查基本格式
    if ! grep -q "^{" "$tmp_file" || ! grep -q "^}$" "$tmp_file"; then
        echo "${CDR}应用市场数据格式错误：缺少外层大括号${NC}"
        echo "${CDB}文件内容：${NC}"
        cat "$tmp_file"
        rm -f "$tmp_file"
        return 1
    fi
    
    # 移除BOM标记（如果存在）
    sed -i '1s/^\xEF\xBB\xBF//' "$tmp_file"
    
    # 转换Windows行尾为Unix格式
    dos2unix "$tmp_file" 2>/dev/null || true
    
    # 保存到缓存
    mv "$tmp_file" "$CACHE_FILE"
    # 保存URL到配置文件
    save_market_url "$market_url"
    echo "${CD}应用市场信息已更新${NC}"
}

# 渲染文本（处理变量和样式）
render_text() {
    local text="$1"
    
    # 清理环境变量信息
    # 1. 移除以/开头的路径信息
    text=$(echo "$text" | sed 's|/[^}]*}||g')
    # 2. 移除任何剩余的花括号
    text=$(echo "$text" | sed 's/}//g')
    # 3. 移除任何剩余的斜杠
    text=$(echo "$text" | tr -s '/' ' ')
    # 4. 移除多余的空格
    text=$(echo "$text" | sed 's/[[:space:]]\+/ /g' | sed 's/^ *//g' | sed 's/ *$//g')
    
    # 解析已定义的变量
    local vars=$(declare -p | grep "^declare -- [A-Z][A-Z_]*=")
    while IFS= read -r var_def; do
        if [[ $var_def =~ ^declare\ --\ ([A-Z][A-Z_]*)=(.*)$ ]]; then
            local var_name="${BASH_REMATCH[1]}"
            local var_value="${BASH_REMATCH[2]}"
            text="${text//\${$var_name}/${!var_name}}"
        fi
    done <<< "$vars"
    
    echo -e "$text"
}

# 处理PATH中的变量定义
process_path_definitions() {
    local app="$1"
    local path_content=$(echo "$app" | jq -r '.PATH')
    
    # 如果PATH包含变量定义
    if [[ "$path_content" == *"="* ]]; then
        while IFS= read -r line; do
            if [[ "$line" =~ ^[A-Z][A-Z_]*=.*$ ]]; then
                # 执行变量定义
                eval "$line"
            fi
        done <<< "$path_content"
    fi
}

# 显示应用市场列表
show_app_list() {
    if [ ! -f "$CACHE_FILE" ]; then
        echo "${CDR}未找到应用市场数据，请先更新${NC}"
        return 1
    fi
    
    local in_app=false
    local id=""
    local title=""
    local text=""
    local market_name=""
    
    while IFS= read -r line; do
        # 去除空格和回车符
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # 跳过空行
        if [ -z "$line" ]; then
            continue
        fi
        
        # 检查是否是顶级 Name 字段
        if [[ "$line" =~ ^Name=(.*)$ ]] && [ -z "$market_name" ]; then
            market_name="${BASH_REMATCH[1]}"
            continue
        fi
        
        case "$line" in
            "{")
                in_app=true
                id=""
                title=""
                text=""
                ;;
            "}")
                in_app=false
                if [ -n "$id" ] && [ -n "$title" ]; then
                    echo "|<$id>$title"
                    if [ -n "$text" ]; then
                        echo "|   描述: $text"
                    fi
                fi
                ;;
            *)
                if [ "$in_app" = true ]; then
                    if [[ "$line" =~ ^ID=\<([0-9]+)\>$ ]]; then
                        id="${BASH_REMATCH[1]}"
                    elif [[ "$line" =~ ^Title=(.*)$ ]]; then
                        title="${BASH_REMATCH[1]}"
                    elif [[ "$line" =~ ^Text=(.*)$ ]]; then
                        text="${BASH_REMATCH[1]}"
                    fi
                fi
                ;;
        esac
    done < "$CACHE_FILE"
    
    # 返回市场名称
    echo "$market_name"
}

# 获取应用信息
get_app_info() {
    local app_id=$1
    if [ ! -f "$CACHE_FILE" ]; then
        echo "${CDR}未找到应用市场数据${NC}"
        return 1
    fi
    
    local in_app=false
    local current_id=""
    local command=""
    local path=""
    
    while IFS= read -r line; do
        # 去除空格和回车符
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # 跳过空行
        if [ -z "$line" ]; then
            continue
        fi
        
        case "$line" in
            "{")
                in_app=true
                current_id=""
                command=""
                path=""
                ;;
            "}")
                if [ "$current_id" = "$app_id" ] && [ -n "$command" ]; then
                    if [ "$path" != "null" ]; then
                        echo "cd $path && $command"
                    else
                        echo "$command"
                    fi
                    return 0
                fi
                in_app=false
                ;;
            *)
                if [ "$in_app" = true ]; then
                    if [[ "$line" =~ ^ID=\<([0-9]+)\>$ ]]; then
                        current_id="${BASH_REMATCH[1]}"
                    elif [[ "$line" =~ ^Cd=(.*)$ ]]; then
                        command="${BASH_REMATCH[1]}"
                    elif [[ "$line" =~ ^PATH=(.*)$ ]]; then
                        path="${BASH_REMATCH[1]}"
                    fi
                fi
                ;;
        esac
    done < "$CACHE_FILE"
    
    return 1
}

# 执行应用命令
run_app() {
    local app_id=$1
    local command=$(get_app_info "$app_id")
    
    if [ -n "$command" ]; then
        eval "$command"
    else
        echo "${CDR}未找到该应用或命令${NC}"
        return 1
    fi
}

# 更新应用市场数据
update_market() {
    local url
    # 如果没有提供URL，使用配置文件中的URL
    if [ -f "$MARKET_URL_FILE" ]; then
        url=$(cat "$MARKET_URL_FILE")
    fi
    
    # 如果配置文件中没有URL，则提示输入
    if [ -z "$url" ]; then
        read -p "请输入应用市场URL: " url
        if [ -z "$url" ]; then
            echo "${CDR}URL不能为空${NC}"
            return 1
        fi
        # 保存URL到配置文件
        echo "$url" > "$MARKET_URL_FILE"
    fi
    
    echo "正在获取应用市场信息..."
    if download_market_data "$url"; then
        return 0
    else
        return 1
    fi
}

# 应用市场菜单
app_market_menu() {
    while true; do
        clear
        if [ -f "$CACHE_FILE" ]; then
            # 获取应用列表和市场名称
            local output
            output=$(show_app_list)
            # 获取最后一行作为市场名称
            local market_name
            market_name=$(echo "$output" | tail -n 1)
            # 移除最后一行（市场名称）
            local app_list
            app_list=$(echo "$output" | sed '$d')
            
            echo "====================="
            if [ -n "$market_name" ]; then
                echo " 应用市场 $market_name"
            else
                echo " 应用市场"
            fi
            echo "====================="
            
            echo "$app_list"
            echo "-------------"
            echo "|<0>${CDB}修改应用市场${NC}"
            echo "|<r>${CDB}刷新应用市场${NC}"
            echo "|<q>${CDR}返回主菜单${NC}"
            echo "===================="
            
            read -p "请选择 (输入应用编号安装，0修改应用市场，r刷新，q返回): " choice
            case $choice in
                0)
                    read -p "请输入应用市场URL: " market_url
                    if [ -n "$market_url" ]; then
                        fetch_app_market "$market_url"
                    fi
                    read -p "按回车键继续..."
                    ;;
                r|R)
                    echo "${CDB}正在刷新应用市场...${NC}"
                    if [ -f "$MARKET_URL_FILE" ]; then
                        local current_url
                        current_url=$(cat "$MARKET_URL_FILE")
                        if [ -n "$current_url" ]; then
                            if fetch_app_market "$current_url"; then
                                echo "${CD}刷新成功！${NC}"
                            else
                                echo "${CDR}刷新失败！${NC}"
                            fi
                        else
                            echo "${CDR}未找到应用市场URL，请先设置！${NC}"
                        fi
                    else
                        echo "${CDR}未找到应用市场URL，请先设置！${NC}"
                    fi
                    read -p "按回车键继续..."
                    ;;
                q|Q)
                    return
                    ;;
                *)
                    if [[ "$choice" =~ ^[0-9]+$ ]]; then
                        run_app "$choice"
                        read -p "按回车键继续..."
                    else
                        echo "${CDR}无效选项${NC}"
                        read -p "按回车键继续..."
                    fi
                    ;;
            esac
        else
            echo "====================="
            echo " 应用市场"
            echo "====================="
            echo "${CDB}首次使用，请设置应用市场${NC}"
            echo "-------------"
            read -p "请输入应用市场URL: " market_url
            market_url=${market_url:-"$(get_market_url)"}
            fetch_app_market "$market_url"
            read -p "按回车键继续..."
        fi
    done
}

# 下载应用市场数据
download_market_data() {
    local url=$1
    local temp_file="/tmp/yysc_temp.txt"
    
    echo "正在下载应用市场数据..."
    echo "下载URL: $url"
    
    # 创建缓存目录
    mkdir -p "$CACHE_DIR"
    
    # 使用curl下载并保存响应头
    echo "正在下载文件..."
    curl -s -L -D /tmp/headers.txt "$url" -o "$temp_file"
    
    # 显示响应头
    echo "服务器响应头："
    cat /tmp/headers.txt
    
    # 检查文件是否为空
    if [ ! -s "$temp_file" ]; then
        echo "${CDR}下载的文件为空${NC}"
        return 1
    fi
    
    echo "下载完成，文件内容："
    echo "===================="
    cat "$temp_file"
    echo "===================="
    
    echo "文件二进制内容："
    echo "===================="
    if command -v xxd >/dev/null 2>&1; then
        xxd "$temp_file"
    else
        od -c "$temp_file"
    fi
    echo "===================="
    
    # 检查文件编码
    if command -v file >/dev/null 2>&1; then
        echo "文件编码信息："
        file -i "$temp_file"
    fi
    
    # 尝试修复可能的BOM和换行符问题
    if command -v dos2unix >/dev/null 2>&1; then
        dos2unix "$temp_file" 2>/dev/null
    else
        # 如果没有dos2unix，使用sed
        sed -i 's/\r$//' "$temp_file"
    fi
    
    # 删除可能的BOM
    sed -i '1s/^\xEF\xBB\xBF//' "$temp_file"
    
    # 验证文件格式
    local valid=false
    local first_line
    first_line=$(head -n 1 "$temp_file" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    echo "首行内容（处理后）：'$first_line'"
    
    if [ "$first_line" = "{" ]; then
        valid=true
    fi
    
    if [ "$valid" = false ]; then
        echo "${CDR}应用市场数据格式错误${NC}"
        echo "文件首行必须是 '{'"
        echo "当前首行内容: '$first_line'"
        echo "首行长度: ${#first_line}"
        return 1
    fi
    
    # 如果验证通过，将数据保存到缓存
    if ! mv "$temp_file" "$CACHE_FILE"; then
        echo "${CDR}保存缓存文件失败${NC}"
        return 1
    fi
    
    echo "${CDS}应用市场数据更新成功${NC}"
    return 0
}

# 安装 curl
install_curl() {
    if command -v curl &> /dev/null; then
        echo "${CD}curl 已经安装。${NC}"
    else
        echo "${CDB}正在安装 curl...${NC}"
        if [ "$OS" == "ubuntu" ] || [ "$OS" == "debian" ]; then
            apt-get update
            apt-get install -y curl
        elif [ "$OS" == "centos" ]; then
            yum install -y curl
        else
            echo "${CDR}不支持的操作系统，无法安装 curl。${NC}"
            return 1
        fi
        echo "${CD}curl 安装成功。${NC}"
    fi
}

# 安装 wget
install_wget() {
    if command -v wget &> /dev/null; then
        echo "${CD}wget 已经安装。${NC}"
    else
        echo "${CDB}正在安装 wget...${NC}"
        if [ "$OS" == "ubuntu" ] || [ "$OS" == "debian" ]; then
            apt-get update
            apt-get install -y wget
        elif [ "$OS" == "centos" ]; then
            yum install -y wget
        else
            echo "${CDR}不支持的操作系统，无法安装 wget。${NC}"
            return 1
        fi
        echo "${CD}wget 安装成功。${NC}"
    fi
}

# 安装 docker
install_docker() {
    if command -v docker &> /dev/null; then
        echo "${CD}Docker 已经安装。${NC}"
    else
        echo "${CDB}正在安装 Docker...${NC}"
        if [ "$OS" == "ubuntu" ] || [ "$OS" == "debian" ]; then
            apt-get update
            apt-get install -y apt-transport-https ca-certificates curl software-properties-common
            curl -fsSL https://download.docker.com/linux/$OS/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$OS $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            apt-get update
            apt-get install -y docker-ce docker-ce-cli containerd.io
        elif [ "$OS" == "centos" ]; then
            yum install -y yum-utils
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            yum install -y docker-ce docker-ce-cli containerd.io
            systemctl start docker
            systemctl enable docker
        else
            echo "${CDR}不支持的操作系统，无法安装 Docker。${NC}"
            return 1
        fi
        echo "${CD}Docker 安装成功。${NC}"
    fi
}

# 安装 git
install_git() {
    if command -v git &> /dev/null; then
        echo "${CD}git 已经安装。${NC}"
    else
        echo "${CDB}正在安装 git...${NC}"
        if [ "$OS" == "ubuntu" ] || [ "$OS" == "debian" ]; then
            apt-get update
            apt-get install -y git
        elif [ "$OS" == "centos" ]; then
            yum install -y git
        else
            echo "${CDR}不支持的操作系统，无法安装 git。${NC}"
            return 1
        fi
        echo "${CD}git 安装成功。${NC}"
    fi
}

# 软件安装菜单
software_install_menu() {
    while true; do
        clear
        echo "===== 软件安装管理 ====="
        echo "|<1>安装 Curl"
        echo "|<2>安装 Wget"
        echo "|<3>安装 Docker"
        echo "|<4>安装 Git"
        echo "-------------"
        echo "|<0>返回主菜单"
        echo "======================="
        
        read -p "请选择: " choice
        case $choice in
            1)
                install_curl
                read -p "按回车键继续..."
                ;;
            2)
                install_wget
                read -p "按回车键继续..."
                ;;
            3)
                install_docker
                read -p "按回车键继续..."
                ;;
            4)
                install_git
                read -p "按回车键继续..."
                ;;
            0)
                return
                ;;
            *)
                echo "${CDR}无效选项${NC}"
                read -p "按回车键继续..."
                ;;
        esac
    done
}

# 定义更新源
DEFAULT_UPDATE_URL="https://8-8-8-8.top/vpsmanager.sh"
GITHUB_UPDATE_URL="https://example.com/vpsmanager.sh"

# 更新脚本函数
update_script() {
    local source=$1
    local url=""
    
    case $source in
        "default")
            url=$DEFAULT_UPDATE_URL
            echo "${CDB}正在从默认源更新脚本...${NC}"
            ;;
        "github")
            url=$GITHUB_UPDATE_URL
            echo "${CDB}正在从Github更新脚本...${NC}"
            ;;
        *)
            echo "${CDR}无效的选择${NC}"
            return 1
            ;;
    esac
    
    # 备份当前脚本
    cp "$0" "$0.bak"
    echo "${CDB}已备份当前脚本到 $0.bak${NC}"
    
    # 下载并更新脚本
    if wget --no-check-certificate -N -O "$0" "$url"; then
        chmod +x "$0"
        echo "${CD}脚本更新成功！${NC}"
        echo "${CDB}即将重启脚本...${NC}"
        sleep 2
        exec bash "$0"
    else
        echo "${CDR}更新失败！正在恢复备份...${NC}"
        mv "$0.bak" "$0"
        chmod +x "$0"
        echo "${CD}已恢复到之前版本${NC}"
        read -p "按回车键继续..."
        return 1
    fi
}

# 更新菜单
update_menu() {
    while true; do
        clear
        echo "===== 脚本更新 ====="
        echo "|<1>${CD}默认更新源${NC}"
        echo "|<2>${CD}Github更新源${NC}"
        echo "-------------"
        echo "|<0>返回主菜单"
        echo "===================="
        
        read -p "请选择更新源: " choice
        case $choice in
            1)
                update_script "default"
                ;;
            2)
                update_script "github"
                ;;
            0)
                return
                ;;
            *)
                echo "${CDR}无效选项${NC}"
                read -p "按回车键继续..."
                ;;
        esac
    done
}

# 安装时自动添加命令别名
install_command_alias() {
    echo "${CDB}正在安装快捷命令...${NC}"
    # 创建更新脚本命令
    echo "#!/bin/bash" | sudo tee "/usr/local/bin/vpsmanager" > /dev/null
    echo 'wget --no-check-certificate -N -O vpsmanager.sh https://8-8-8-8.top/vpsmanager.sh && bash vpsmanager.sh' | sudo tee -a "/usr/local/bin/vpsmanager" > /dev/null
    sudo chmod +x "/usr/local/bin/vpsmanager"
    echo "${CD}安装完成！现在可以使用 vpsmanager 命令来更新和运行脚本${NC}"
}

# 删除指定行的命令
remove_commands_by_lines() {
    local start_line=$1
    local end_line=$2
    local commands_file="/tmp/commands_list"
    
    # 获取所有命令列表
    ls -l /usr/local/bin/ | grep -v "^d" | awk '{print $9}' > "$commands_file"
    
    # 检查行号是否有效
    local total_lines=$(wc -l < "$commands_file")
    if [ "$start_line" -gt "$total_lines" ] || [ "$end_line" -gt "$total_lines" ]; then
        echo "${CDR}错误：指定的行号超出范围，总行数为 $total_lines${NC}"
        rm "$commands_file"
        return 1
    fi
    
    # 显示将要删除的命令
    echo "${CDB}将要删除以下命令：${NC}"
    sed -n "${start_line},${end_line}p" "$commands_file"
    echo "-------------"
    read -p "确认删除这些命令吗？(y/n): " confirm
    
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        # 删除指定行对应的命令
        for i in $(seq "$start_line" "$end_line"); do
            local cmd=$(sed -n "${i}p" "$commands_file")
            if [ -n "$cmd" ]; then
                sudo rm -f "/usr/local/bin/$cmd"
                echo "${CD}已删除命令：$cmd${NC}"
            fi
        done
        echo "${CD}指定命令已删除${NC}"
    else
        echo "${CDB}已取消删除操作${NC}"
    fi
    
    rm "$commands_file"
}

# 声明关联数组存储检测结果
declare -A results

# 检测系统类型
detect_system() {
    echo "检测操作系统类型..."
    if grep -qi ubuntu /etc/os-release 2>/dev/null; then
        DISTRO="ubuntu"
    elif [ -f /etc/debian_version ]; then
        DISTRO="debian"
    elif [ -f /etc/centos-release ] || grep -qi centos /etc/os-release 2>/dev/null; then
        DISTRO="centos"
    elif [ -f /etc/fedora-release ] || grep -qi fedora /etc/os-release 2>/dev/null; then
        DISTRO="fedora"
    else
        echo "不支持的操作系统！"
        exit 1
    fi
    echo "检测到系统为: $DISTRO"
}

# ========== 系统检测功能 ==========

check_network() {
    echo "正在检测网络连通性..."

    echo "测试国外 IPv4 DNS 8.8.8.8 (Google)..."
    if ping -c 3 -W 2 8.8.8.8 >/dev/null 2>&1; then
        results[network_outside_ipv4]="成功"
    else
        results[network_outside_ipv4]="失败"
    fi

    echo "测试国内 IPv4 DNS 223.5.5.5 (阿里)..."
    if ping -c 3 -W 2 223.5.5.5 >/dev/null 2>&1; then
        results[network_china_ipv4]="成功"
    else
        results[network_china_ipv4]="失败"
    fi

    echo "测试国外 IPv6 DNS 2001:4860:4860::8888 (Google)..."
    if ping6 -c 3 -W 2 2001:4860:4860::8888 >/dev/null 2>&1; then
        results[network_outside_ipv6]="成功"
    else
        results[network_outside_ipv6]="失败"
    fi

    echo "测试国内 IPv6 DNS 240c::6666 (114DNS)..."
    if ping6 -c 3 -W 2 240c::6666 >/dev/null 2>&1; then
        results[network_china_ipv6]="成功"
    else
        results[network_china_ipv6]="失败"
    fi
}

list_public_ips() {
    echo "正在获取服务器所有 IP（含 IPv6）..."
    echo "本机网络接口 IP:"
    ip addr show | grep -E "inet6? " | grep -v "127.0.0.1" | grep -v "::1"

    echo -n "查询公网 IPv4 (ip.sb): "
    pubip4=$(curl -s4 https://ip.sb)
    echo "$pubip4"

    echo -n "查询公网 IPv6 (ip.sb): "
    pubip6=$(curl -s6 https://ip.sb)
    echo "$pubip6"

    results[public_ip]="接口 IP 和公网 IP 已显示"
}

check_dns() {
    echo "检测 DNS 配置..."
    dns_servers=$(grep "^nameserver" /etc/resolv.conf | awk '{print $2}')
    echo "当前 DNS 服务器为: $dns_servers"
    results[dns_servers]="$dns_servers"

    if echo "$dns_servers" | grep -qE "^(1\.1\.1\.1|8\.8\.8\.8|114\.114\.114\.114|240c::6666|2001:4860:4860::8888)$"; then
        echo "DNS 服务器符合推荐设置。"
        results[dns_recommend]="是"
    else
        echo "DNS 不在推荐范围。建议修改为以下之一："
        echo "IPv4: 1.1.1.1 / 8.8.8.8 / 114.114.114.114"
        echo "IPv6: 240c::6666 / 2001:4860:4860::8888"
        results[dns_recommend]="否"

        echo "请选择要设置的 DNS："
        echo "1) 1.1.1.1 (国外推荐 IPv4)"
        echo "2) 8.8.8.8 (国外推荐 IPv4)"
        echo "3) 114.114.114.114 (国内推荐 IPv4)"
        echo "4) 240c::6666 (国内推荐 IPv6)"
        echo "5) 2001:4860:4860::8888 (国外推荐 IPv6)"
        echo "0) 不修改"

        read -rp "输入选项: " dns_choice
        case "$dns_choice" in
            1) new_dns="1.1.1.1" ;;
            2) new_dns="8.8.8.8" ;;
            3) new_dns="114.114.114.114" ;;
            4) new_dns="240c::6666" ;;
            5) new_dns="2001:4860:4860::8888" ;;
            *) echo "不修改 DNS。" ; return ;;
        esac

        echo "备份 /etc/resolv.conf..."
        cp /etc/resolv.conf /etc/resolv.conf.backup.$(date +%F_%H%M%S)
        echo -e "nameserver $new_dns\n" > /etc/resolv.conf
        echo "修改完成，当前 DNS："
        cat /etc/resolv.conf

        results[dns_servers]="$new_dns (已修改)"
        results[dns_recommend]="是"
    fi
}

check_disk() {
    echo "检测硬盘挂载情况..."
    df -h
    results[disk_check]="已显示硬盘挂载信息"
}

# 检测软件源
check_sources() {
    echo "检测软件源连通性..."
    case "$DISTRO" in
        debian|ubuntu)
            echo "检测 apt 软件源..."
            echo "这可能需要几秒钟的时间..."
            # 使用 timeout 命令限制执行时间为 10 秒
            if timeout 10 apt-get update -qq >/dev/null 2>&1; then
                results[sources_status]="正常"
                results[sources_detail]="apt 软件源可以正常访问和更新"
            else
                if [ $? -eq 124 ]; then
                    results[sources_status]="超时"
                    results[sources_detail]="apt 软件源响应超时，建议检查网络连接或更换软件源"
                else
                    results[sources_status]="异常"
                    results[sources_detail]="apt 软件源访问异常，建议使用本脚本的软件源管理功能修复"
                fi
            fi
            # 获取当前使用的源
            if [ -f /etc/apt/sources.list ]; then
                current_source=$(grep -m 1 "^deb" /etc/apt/sources.list | awk '{print $2}')
                results[current_source]="当前软件源: $current_source"
            fi
            ;;
        centos)
            echo "检测 yum 软件源..."
            echo "这可能需要几秒钟的时间..."
            if timeout 10 yum makecache -q >/dev/null 2>&1; then
                results[sources_status]="正常"
                results[sources_detail]="yum 软件源可以正常访问和更新"
            else
                if [ $? -eq 124 ]; then
                    results[sources_status]="超时"
                    results[sources_detail]="yum 软件源响应超时，建议检查网络连接或更换软件源"
                else
                    results[sources_status]="异常"
                    results[sources_detail]="yum 软件源访问异常，建议使用本脚本的软件源管理功能修复"
                fi
            fi
            # 获取当前使用的源
            if [ -f /etc/yum.repos.d/CentOS-Base.repo ]; then
                current_source=$(grep -m 1 "baseurl" /etc/yum.repos.d/CentOS-Base.repo | awk -F= '{print $2}' | tr -d ' ')
                results[current_source]="当前软件源: $current_source"
            fi
            ;;
        fedora)
            echo "检测 dnf 软件源..."
            echo "这可能需要几秒钟的时间..."
            if timeout 10 dnf makecache -q >/dev/null 2>&1; then
                results[sources_status]="正常"
                results[sources_detail]="dnf 软件源可以正常访问和更新"
            else
                if [ $? -eq 124 ]; then
                    results[sources_status]="超时"
                    results[sources_detail]="dnf 软件源响应超时，建议检查网络连接或更换软件源"
                else
                    results[sources_status]="异常"
                    results[sources_detail]="dnf 软件源访问异常，建议使用本脚本的软件源管理功能修复"
                fi
            fi
            ;;
        *)
            results[sources_status]="未知"
            results[sources_detail]="未知系统，无法检测软件源"
            ;;
    esac
    echo "软件源检测完成。"
}

# ========== 软件源管理功能 ==========

backup_file() {
    local file=$1
    if [ -f "$file" ]; then
        local timestamp=$(date +%F_%H%M%S)
        cp "$file" "${file}.backup.${timestamp}"
        echo "备份文件 $file 到 ${file}.backup.${timestamp}"
    fi
}

restore_backup() {
    local file=$1
    local backup_dir=$2
    echo "准备恢复备份，查找目录: $backup_dir"
    if [ ! -d "$backup_dir" ]; then
        echo "没有找到备份目录 $backup_dir"
        return 1
    fi
    latest_backup=$(ls -t "$backup_dir"/*.backup.* 2>/dev/null | head -n 1)
    echo "找到备份文件: $latest_backup"
    if [ -z "$latest_backup" ]; then
        echo "没有找到备份文件"
        return 1
    fi
    echo "正在恢复备份文件 $latest_backup 到 $file"
    cp "$latest_backup" "$file"
    echo "恢复完成！"
    return 0
}

show_current_sources() {
    echo
    echo "当前系统源配置如下："
    echo "----------------------------"

    case "$DISTRO" in
        debian|ubuntu)
            echo "[/etc/apt/sources.list]"
            cat /etc/apt/sources.list 2>/dev/null || echo "未找到 sources.list"
            echo
            echo "[/etc/apt/sources.list.d/ 目录]"
            ls /etc/apt/sources.list.d/*.list 2>/dev/null | while read -r file; do
                echo "-- $file --"
                cat "$file"
                echo
            done
            ;;
        centos|fedora)
            echo "[/etc/yum.repos.d/*.repo 文件]"
            ls /etc/yum.repos.d/*.repo 2>/dev/null | while read -r file; do
                echo "-- $file --"
                cat "$file"
                echo
            done
            ;;
        *)
            echo "未知系统，无法显示"
            ;;
    esac

    echo "----------------------------"
}

# Debian 源管理
change_apt_source_tsinghua() {
    echo "更换为 Debian 清华源..."
    backup_file /etc/apt/sources.list
    # 获取 Debian 版本代号
    DEBIAN_VERSION=$(grep VERSION_CODENAME /etc/os-release | cut -d= -f2)
    if [ -z "$DEBIAN_VERSION" ]; then
        DEBIAN_VERSION=$(cat /etc/debian_version | cut -d. -f1)
        case "$DEBIAN_VERSION" in
            11) DEBIAN_VERSION="bullseye" ;;
            12) DEBIAN_VERSION="bookworm" ;;
            *) echo "未知的 Debian 版本，使用 stable"; DEBIAN_VERSION="stable" ;;
        esac
    fi
    cat >/etc/apt/sources.list <<EOF
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ $DEBIAN_VERSION main contrib non-free
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ $DEBIAN_VERSION-updates main contrib non-free
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ $DEBIAN_VERSION-backports main contrib non-free
deb https://mirrors.tuna.tsinghua.edu.cn/debian-security $DEBIAN_VERSION-security main contrib non-free
EOF
    update_sources
    echo "完成！"
}

change_apt_source_official() {
    echo "更换为 Debian 官方源..."
    backup_file /etc/apt/sources.list
    # 获取 Debian 版本代号
    DEBIAN_VERSION=$(grep VERSION_CODENAME /etc/os-release | cut -d= -f2)
    if [ -z "$DEBIAN_VERSION" ]; then
        DEBIAN_VERSION=$(cat /etc/debian_version | cut -d. -f1)
        case "$DEBIAN_VERSION" in
            11) DEBIAN_VERSION="bullseye" ;;
            12) DEBIAN_VERSION="bookworm" ;;
            *) echo "未知的 Debian 版本，使用 stable"; DEBIAN_VERSION="stable" ;;
        esac
    fi
    cat >/etc/apt/sources.list <<EOF
deb http://deb.debian.org/debian $DEBIAN_VERSION main contrib non-free
deb http://deb.debian.org/debian $DEBIAN_VERSION-updates main contrib non-free
deb http://deb.debian.org/debian $DEBIAN_VERSION-backports main contrib non-free
deb http://security.debian.org/debian-security $DEBIAN_VERSION-security main contrib non-free
EOF
    update_sources
    echo "完成！"
}

change_apt_source_aliyun() {
    echo "更换为 Debian 阿里云源..."
    backup_file /etc/apt/sources.list
    # 获取 Debian 版本代号
    DEBIAN_VERSION=$(grep VERSION_CODENAME /etc/os-release | cut -d= -f2)
    if [ -z "$DEBIAN_VERSION" ]; then
        DEBIAN_VERSION=$(cat /etc/debian_version | cut -d. -f1)
        case "$DEBIAN_VERSION" in
            11) DEBIAN_VERSION="bullseye" ;;
            12) DEBIAN_VERSION="bookworm" ;;
            *) echo "未知的 Debian 版本，使用 stable"; DEBIAN_VERSION="stable" ;;
        esac
    fi
    cat >/etc/apt/sources.list <<EOF
deb http://mirrors.aliyun.com/debian/ $DEBIAN_VERSION main contrib non-free
deb http://mirrors.aliyun.com/debian/ $DEBIAN_VERSION-updates main contrib non-free
deb http://mirrors.aliyun.com/debian/ $DEBIAN_VERSION-backports main contrib non-free
deb http://mirrors.aliyun.com/debian-security $DEBIAN_VERSION-security main contrib non-free
EOF
    update_sources
    echo "完成！"
}

# 通用的更新函数
update_sources() {
    echo "正在更新软件源..."
    # 将警告信息重定向到临时文件
    local tmp_file=$(mktemp)
    if apt-get update 2>"$tmp_file"; then
        # 如果有警告信息，以较好的格式显示
        if [ -s "$tmp_file" ]; then
            echo "注意：更新过程中有以下提示信息："
            echo "----------------------------------------"
            cat "$tmp_file"
            echo "----------------------------------------"
        fi
        echo "软件源更新完成！"
    else
        echo "软件源更新失败！错误信息："
        cat "$tmp_file"
    fi
    rm -f "$tmp_file"
}

# Ubuntu 源管理
change_ubuntu_source_tsinghua() {
    echo "更换为 Ubuntu 清华源..."
    # 备份原有配置
    backup_file /etc/apt/sources.list
    
    # 清理可能存在的其他源文件
    echo "清理旧的源配置..."
    rm -f /etc/apt/sources.list.d/*.list
    rm -f /etc/apt/sources.list.d/*.sources
    
    # 获取 Ubuntu 版本代号
    UBUNTU_VERSION=$(grep UBUNTU_CODENAME /etc/os-release | cut -d= -f2)
    if [ -z "$UBUNTU_VERSION" ]; then
        UBUNTU_VERSION=$(lsb_release -sc)
    fi
    
    # 写入新的源配置
    cat >/etc/apt/sources.list <<EOF
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ $UBUNTU_VERSION main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ $UBUNTU_VERSION-updates main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ $UBUNTU_VERSION-backports main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ $UBUNTU_VERSION-security main restricted universe multiverse
EOF
    update_sources
    echo "完成！"
    echo
    read -p "按回车继续..." dummy
}

change_ubuntu_source_official() {
    echo "更换为 Ubuntu 官方源..."
    # 备份原有配置
    backup_file /etc/apt/sources.list
    
    # 清理可能存在的其他源文件
    echo "清理旧的源配置..."
    rm -f /etc/apt/sources.list.d/*.list
    rm -f /etc/apt/sources.list.d/*.sources
    
    # 获取 Ubuntu 版本代号
    UBUNTU_VERSION=$(grep UBUNTU_CODENAME /etc/os-release | cut -d= -f2)
    if [ -z "$UBUNTU_VERSION" ]; then
        UBUNTU_VERSION=$(lsb_release -sc)
    fi
    
    # 写入新的源配置
    cat >/etc/apt/sources.list <<EOF
deb http://archive.ubuntu.com/ubuntu/ $UBUNTU_VERSION main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ $UBUNTU_VERSION-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ $UBUNTU_VERSION-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu $UBUNTU_VERSION-security main restricted universe multiverse
EOF
    update_sources
    echo "完成！"
    echo
    read -p "按回车继续..." dummy
}

change_ubuntu_source_aliyun() {
    echo "更换为 Ubuntu 阿里云源..."
    # 备份原有配置
    backup_file /etc/apt/sources.list
    
    # 清理可能存在的其他源文件
    echo "清理旧的源配置..."
    rm -f /etc/apt/sources.list.d/*.list
    rm -f /etc/apt/sources.list.d/*.sources
    
    # 获取 Ubuntu 版本代号
    UBUNTU_VERSION=$(grep UBUNTU_CODENAME /etc/os-release | cut -d= -f2)
    if [ -z "$UBUNTU_VERSION" ]; then
        UBUNTU_VERSION=$(lsb_release -sc)
    fi
    
    # 写入新的源配置
    cat >/etc/apt/sources.list <<EOF
deb http://mirrors.aliyun.com/ubuntu/ $UBUNTU_VERSION main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ $UBUNTU_VERSION-updates main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ $UBUNTU_VERSION-backports main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ $UBUNTU_VERSION-security main restricted universe multiverse
EOF
    update_sources
    echo "完成！"
    echo
    read -p "按回车继续..." dummy
}

# CentOS 源管理
change_centos_source_tsinghua() {
    echo "更换为 CentOS 清华源..."
    backup_file /etc/yum.repos.d/CentOS-Base.repo
    # 获取 CentOS 版本
    CENTOS_VERSION=$(rpm -q --queryformat '%{VERSION}' centos-release)
    if [ -z "$CENTOS_VERSION" ]; then
        CENTOS_VERSION=$(grep -oP '(?<=\s)[0-9]+(?=\s)' /etc/centos-release)
    fi
    case "$CENTOS_VERSION" in
        7)
            wget -O /etc/yum.repos.d/CentOS-Base.repo https://mirrors.tuna.tsinghua.edu.cn/help/centos7.repo
            ;;
        8)
            wget -O /etc/yum.repos.d/CentOS-Base.repo https://mirrors.tuna.tsinghua.edu.cn/help/centos8.repo
            ;;
        *)
            echo "不支持的 CentOS 版本: $CENTOS_VERSION"
            return 1
            ;;
    esac
    update_sources
    echo "完成！"
}

change_centos_source_official() {
    echo "恢复为 CentOS 官方源..."
    backup_file /etc/yum.repos.d/CentOS-Base.repo
    cat >/etc/yum.repos.d/CentOS-Base.repo <<EOF
[base]
name=CentOS-7 - Base
baseurl=http://mirror.centos.org/centos/7/os/\$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

[updates]
name=CentOS-7 - Updates
baseurl=http://mirror.centos.org/centos/7/updates/\$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

[extras]
name=CentOS-7 - Extras
baseurl=http://mirror.centos.org/centos/7/extras/\$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
EOF
    update_sources
    echo "完成！"
}

change_centos_source_aliyun() {
    echo "更换为 CentOS 阿里云源..."
    backup_file /etc/yum.repos.d/CentOS-Base.repo
    curl -o /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo
    update_sources
    echo "完成！"
}

# 源管理菜单
manage_sources_menu() {
    while true; do
        clear
        echo "================================"
        echo " VPS 软件源管理"
        echo "================================"
        echo "|<1>${CDB}清华源${NC}"
        echo "|<2>${CD}官方源${NC}"
        echo "|<3>${CDB}阿里云源${NC}"
        echo "-------------"
        echo "|<4>恢复最近一次备份"
        echo "|<5>查看当前软件源"
        echo "-------------"
        echo "|<0>返回主菜单"
        echo "================================"
        
        read -rp "请输入选项: " choice
        echo
        
        case "$choice" in
            1)
                case "$DISTRO" in
                    debian) change_apt_source_tsinghua ;;
                    ubuntu) change_ubuntu_source_tsinghua ;;
                    centos) change_centos_source_tsinghua ;;
                esac
                ;;
            2)
                case "$DISTRO" in
                    debian) change_apt_source_official ;;
                    ubuntu) change_ubuntu_source_official ;;
                    centos) change_centos_source_official ;;
                esac
                ;;
            3)
                case "$DISTRO" in
                    debian) change_apt_source_aliyun ;;
                    ubuntu) change_ubuntu_source_aliyun ;;
                    centos) change_centos_source_aliyun ;;
                esac
                ;;
            4)
                case "$DISTRO" in
                    debian|ubuntu)
                        restore_backup /etc/apt/sources.list /etc/apt
                        echo
                        read -p "按回车继续..." dummy
                        ;;
                    centos)
                        restore_backup /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d
                        echo
                        read -p "按回车继续..." dummy
                        ;;
                esac
                ;;
            5)
                show_current_sources
                echo
                read -p "按回车继续..." dummy
                ;;
            0)
                return
                ;;
            *)
                echo "无效选项"
                echo
                read -p "按回车继续..." dummy
                ;;
        esac
    done
}

# 检测系统类型
check_system_type() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    elif [ -f /etc/redhat-release ]; then
        OS="centos"
    else
        OS="unknown"
    fi
}

# 添加系统变量和别名
add_system_variable() {
    local var_name=$1
    local var_value=$2
    
    check_system_type
    
    case $OS in
        "ubuntu"|"debian")
            # 创建可执行脚本
            echo "#!/bin/bash" | sudo tee "/usr/local/bin/$var_name" > /dev/null
            echo "$var_value" | sudo tee -a "/usr/local/bin/$var_name" > /dev/null
            sudo chmod +x "/usr/local/bin/$var_name"
            echo "${CDB}命令已添加到 /usr/local/bin/$var_name${NC}"
            ;;
        "centos"|"rhel"|"fedora")
            # 创建可执行脚本
            echo "#!/bin/bash" | sudo tee "/usr/local/bin/$var_name" > /dev/null
            echo "$var_value" | sudo tee -a "/usr/local/bin/$var_name" > /dev/null
            sudo chmod +x "/usr/local/bin/$var_name"
            echo "${CDB}命令已添加到 /usr/local/bin/$var_name${NC}"
            ;;
        *)
            echo "${CDR}不支持的系统类型${NC}"
            return 1
            ;;
    esac
    
    echo "${CD}命令添加成功！${NC}"
    echo "现在可以直接使用 $var_name 来执行命令"
}

# 显示所有自定义命令（带行号）
show_system_variables() {
    echo "${CDB}当前自定义命令：${NC}"
    echo "-------------"
    ls -l /usr/local/bin/ | grep -v "^d" | awk '{print $9}' | nl -w2 -s") "
    echo "-------------"
}

# 系统变量管理菜单
manage_system_variables_menu() {
    while true; do
        clear
        echo "===== 系统变量管理 ====="
        echo "|<1>${CD}添加/更新系统变量${NC}"
        echo "|<2>${CDB}查看系统变量${NC}"
        echo "|<3>${CDR}删除指定行命令${NC}"
        echo "-------------"
        echo "|<0>返回主菜单"
        echo "======================="
        
        read -p "请选择: " choice
        case $choice in
            1)
                echo "示例1 - 脚本快捷方式："
                echo "${CDB}变量名：vps${NC}"
                echo "${CDB}变量值：bash /root/vps_manager.sh${NC}"
                echo ""
                echo "示例2 - wget下载命令："
                echo "${CDB}变量名：get-xui${NC}"
                echo "${CDB}变量值：wget -O /root/x-ui.sh https://example.com/x-ui.sh && chmod +x /root/x-ui.sh${NC}"
                echo "-------------"
                read -p "请输入变量名称: " var_name
                read -p "请输入变量值: " var_value
                add_system_variable "$var_name" "$var_value"
                read -p "按回车键继续..."
                ;;
            2)
                show_system_variables
                read -p "按回车键继续..."
                ;;
            3)
                show_system_variables
                echo ""
                read -p "请输入要删除的起始行号: " start_line
                read -p "请输入要删除的结束行号: " end_line
                remove_commands_by_lines "$start_line" "$end_line"
                read -p "按回车键继续..."
                ;;
            0)
                return
                ;;
            *)
                echo "${CDR}无效选项${NC}"
                read -p "按回车键继续..."
                ;;
        esac
    done
}

# 系统检测菜单
system_check_menu() {
    while true; do
        clear
        echo "===== VPS 系统检测菜单 ====="
        echo "|<1>网络连通性检测（IPv4/IPv6 国内+海外）"
        echo "|<2>列出所有绑定的公网IP（含IPv6）"
        echo "|<3>检测 DNS 设置"
        echo "|<4>检查硬盘挂载"
        echo "|<5>检测软件源可用性"
        echo "|<0>返回主菜单"
        echo "========================="
        
        read -rp "输入序号（可空格分隔多个）: " -a choices
        echo
        
        [[ " ${choices[*]} " == *" 0 "* ]] && break
        
        for choice in "${choices[@]}"; do
            case "$choice" in
                1) 
                    check_network
                    print_network_results
                    ;;
                2) 
                    list_public_ips
                    print_ip_results
                    ;;
                3) 
                    check_dns
                    print_dns_results
                    ;;
                4) 
                    check_disk
                    print_disk_results
                    ;;
                5) 
                    check_sources
                    print_source_results
                    ;;
                *) 
                    echo "无效选项: $choice"
                    ;;
            esac
        done
        
        read -p "按回车继续..."
    done
}

# 分别打印各项检测结果的函数
print_network_results() {
    echo
    echo "============ 网络检测结果 ============"
    [[ -n "${results[network_outside_ipv4]}" ]] && echo "国外 IPv4 网络: ${results[network_outside_ipv4]}"
    [[ -n "${results[network_china_ipv4]}" ]] && echo "国内 IPv4 网络: ${results[network_china_ipv4]}"
    [[ -n "${results[network_outside_ipv6]}" ]] && echo "国外 IPv6 网络: ${results[network_outside_ipv6]}"
    [[ -n "${results[network_china_ipv6]}" ]] && echo "国内 IPv6 网络: ${results[network_china_ipv6]}"
    echo "===================================="
}

print_ip_results() {
    echo
    echo "============ IP 检测结果 ============"
    [[ -n "${results[public_ip]}" ]] && echo "${results[public_ip]}"
    echo "===================================="
}

print_dns_results() {
    echo
    echo "============ DNS 检测结果 ============"
    [[ -n "${results[dns_servers]}" ]] && echo "DNS 服务器: ${results[dns_servers]}"
    [[ -n "${results[dns_recommend]}" ]] && echo "DNS 推荐状态: ${results[dns_recommend]}"
    echo "===================================="
}

print_disk_results() {
    echo
    echo "============ 硬盘检测结果 ============"
    [[ -n "${results[disk_check]}" ]] && echo "${results[disk_check]}"
    echo "===================================="
}

print_source_results() {
    echo
    echo "============ 软件源检测结果 ============"
    if [[ -n "${results[sources_status]}" ]]; then
        echo "状态: ${results[sources_status]}"
        [[ -n "${results[sources_detail]}" ]] && echo "详情: ${results[sources_detail]}"
        [[ -n "${results[current_source]}" ]] && echo "${results[current_source]}"
    fi
    echo "======================================"
}

# 打印检测结果
print_results() {
    echo
    echo "============ 检测结果 ============"
    if [[ -n "${results[network_outside_ipv4]}" || -n "${results[network_china_ipv4]}" || 
          -n "${results[network_outside_ipv6]}" || -n "${results[network_china_ipv6]}" ]]; then
        echo "网络连通性检测:"
        [[ -n "${results[network_outside_ipv4]}" ]] && echo "  国外 IPv4 网络: ${results[network_outside_ipv4]}"
        [[ -n "${results[network_china_ipv4]}" ]] && echo "  国内 IPv4 网络: ${results[network_china_ipv4]}"
        [[ -n "${results[network_outside_ipv6]}" ]] && echo "  国外 IPv6 网络: ${results[network_outside_ipv6]}"
        [[ -n "${results[network_china_ipv6]}" ]] && echo "  国内 IPv6 网络: ${results[network_china_ipv6]}"
        echo "--------------------------"
    fi

    if [[ -n "${results[public_ip]}" ]]; then
        echo "公网 IP 信息:"
        echo "  ${results[public_ip]}"
        echo "--------------------------"
    fi

    if [[ -n "${results[dns_servers]}" || -n "${results[dns_recommend]}" ]]; then
        echo "DNS 配置信息:"
        [[ -n "${results[dns_servers]}" ]] && echo "  DNS 服务器: ${results[dns_servers]}"
        [[ -n "${results[dns_recommend]}" ]] && echo "  DNS 推荐状态: ${results[dns_recommend]}"
        echo "--------------------------"
    fi

    if [[ -n "${results[disk_check]}" ]]; then
        echo "硬盘挂载信息:"
        echo "  ${results[disk_check]}"
        echo "--------------------------"
    fi

    if [[ -n "${results[sources_status]}" ]]; then
        echo "软件源检测结果:"
        echo "  状态: ${results[sources_status]}"
        [[ -n "${results[sources_detail]}" ]] && echo "  详情: ${results[sources_detail]}"
        [[ -n "${results[current_source]}" ]] && echo "  ${results[current_source]}"
        echo "--------------------------"
    fi
    echo "=================================="
}

# 主菜单
main_menu() {
    while true; do
        # 检查并安装 vpsmanager 命令
        if [ ! -f "/usr/local/bin/vpsmanager" ]; then
            install_command_alias
        fi
        
        clear
        echo "================================"
        echo "       VPS Manager v1.0.0"
        echo "================================"
        echo "|<1>${CD}系统检测${NC}"
        echo "|<2>${CD}软件源管理${NC}"
        echo "|<3>${CD}软件安装${NC}"
        echo "|<4>${CD}系统变量管理${NC}"
        echo "|<5>${CD}应用市场${NC}"
        echo "|<6>${CDB}脚本更新${NC}"
        echo "-------------"
        echo "|<0>${CDR}退出${NC}"
        echo "================================"
        echo " 1118论坛.top|1118luntan.top"
        echo "================================"
        
        read -rp "请选择功能: " choice
        case "$choice" in
            1)
                system_check_menu
                ;;
            2)
                manage_sources_menu
                ;;
            3)
                software_install_menu
                ;;
            4)
                manage_system_variables_menu
                ;;
            5)
                app_market_menu
                ;;
            6)
                update_menu
                ;;
            0)
                echo "${CDB}感谢使用！${NC}"
                exit 0
                ;;
            *)
                echo "${CDR}无效选项${NC}"
                read -p "按回车键继续..."
                ;;
        esac
    done
}

# 检测是否为root用户
if [ "$(id -u)" != "0" ]; then
    echo "${CDR}错误：必须以root用户运行此脚本${NC}"
    exit 1
fi

# 检测系统类型
detect_system

# 运行主菜单
main_menu
