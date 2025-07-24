#!/bin/bash

# 文字样式变量定义：绿色粗体
CD=$'\033[1;32m'
CDB=$'\033[1;34m'
CDR=$'\033[1;31m'  # 红色背景白色粗体字
NC=$'\033[0m'

# 处理ID列表（支持逗号分隔和范围格式）
process_id_list() {
    local id_list=$1
    local ids=()

    # 检查是否是范围格式（如1-5）
    if [[ "$id_list" =~ ^([0-9]+)-([0-9]+)$ ]]; then
        local start=${BASH_REMATCH[1]}
        local end=${BASH_REMATCH[2]}
        # 确保start小于等于end
        if [ "$start" -le "$end" ]; then
            for ((i=start; i<=end; i++)); do
                echo "$i"
            done
        else
            for ((i=start; i>=end; i--)); do
                echo "$i"
            done
        fi
    else
        # 处理逗号分隔的格式
        # 将中文逗号替换为英文逗号（使用printf确保正确处理UTF-8字符）
        id_list=$(printf '%s' "$id_list" | sed $'s/\xe3\x80\x82/,/g; s/\xef\xbc\x8c/,/g; s/，/,/g')
        # 分割并输出每个ID
        echo "$id_list" | tr ',' '\n' | while read -r id; do
            if [[ "$id" =~ ^[0-9]+$ ]]; then
                echo "$id"
            fi
        done
    fi
}

# 处理中文文本换行
format_text() {
    local text="$1"
    printf "║    描述: %s\n" "$text"
}

# 配置文件和缓存
CONFIG_DIR="/usr/local/vpsmanager/config"
CACHE_DIR="/usr/local/vpsmanager/cache"
CACHE_FILE="$CACHE_DIR/yysc.conf"
MARKET_URL_FILE="$CONFIG_DIR/market_url.txt"
FAVORITES_FILE="$CONFIG_DIR/favorites.conf"  # 新增：收藏夹配置文件
LIKE_API_URL_FILE="$CONFIG_DIR/like_api_url.txt"  # 新增：点赞API配置文件
LIKES_CACHE_FILE="$CACHE_DIR/likes_cache.json"  # 新增：点赞数据缓存文件
SHOW_LIKES_FILE="$CONFIG_DIR/show_likes.txt"  # 新增：是否显示点赞数配置

# 确保配置目录存在
mkdir -p "$CONFIG_DIR" "$CACHE_DIR"

# 初始化收藏夹文件
init_favorites() {
    if [ ! -f "$FAVORITES_FILE" ]; then
        echo "Name=我的收藏夹" > "$FAVORITES_FILE"
    fi
}

# 初始化点赞API配置
init_like_api() {
    if [ ! -f "$LIKE_API_URL_FILE" ]; then
        # 自动生成点赞API地址
        local auto_api_url=$(get_like_api_url)
        echo "$auto_api_url" > "$LIKE_API_URL_FILE"
    fi
    if [ ! -f "$SHOW_LIKES_FILE" ]; then
        echo "true" > "$SHOW_LIKES_FILE"
    fi
}

# 从应用市场获取应用信息
get_app_info_from_market() {
    local app_id=$1
    local file=$2
    local in_app=false
    local current_id=""
    local title=""
    local text=""
    local command=""
    local tag=""
    
    while IFS= read -r line; do
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        if [ -z "$line" ]; then
            continue
        fi
        
        case "$line" in
            "{")
                in_app=true
                current_id=""
                title=""
                text=""
                command=""
                tag=""
                ;;
            "}")
                if [ "$current_id" = "$app_id" ]; then
                    echo "TITLE=$title"
                    echo "TEXT=$text"
                    echo "COMMAND=$command"
                    echo "TAG=$tag"
                    return 0
                fi
                in_app=false
                ;;
            *)
                if [ "$in_app" = true ]; then
                    if [[ "$line" =~ ^ID=\<([0-9]+)\>$ ]]; then
                        current_id="${BASH_REMATCH[1]}"
                    elif [[ "$line" =~ ^Title=(.*)$ ]]; then
                        title="${BASH_REMATCH[1]}"
                    elif [[ "$line" =~ ^Text=(.*)$ ]]; then
                        text="${BASH_REMATCH[1]}"
                    elif [[ "$line" =~ ^Cd=(.*)$ ]]; then
                        command="${BASH_REMATCH[1]}"
                    elif [[ "$line" =~ ^Tag=(.*)$ ]]; then
                        tag="${BASH_REMATCH[1]}"
                    elif [[ "$line" =~ ^[[:space:]]*\>[[:space:]]*(.*)$ ]] && [ -n "$command" ]; then
                        command="$command && ${BASH_REMATCH[1]}"
                    fi
                fi
                ;;
        esac
    done < "$file"
    
    return 1
}

# 检查应用是否完全重复（Title和Cd都相同）
check_if_exact_duplicate() {
    local app_id=$1
    local in_app=false
    local app_info
    local target_title=""
    local target_cd=""
    local current_title=""
    local current_cd=""
    
    # 首先获取目标应用的信息
    app_info=$(get_app_info_from_market "$app_id" "$CACHE_FILE")
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    # 解析目标应用的 Title 和 Cd
    while IFS= read -r line; do
        if [[ "$line" =~ ^TITLE=(.*)$ ]]; then
            target_title="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^COMMAND=(.*)$ ]]; then
            target_cd="${BASH_REMATCH[1]}"
        fi
    done <<< "$app_info"
    
    if [ -z "$target_title" ] || [ -z "$target_cd" ]; then
        return 1
    fi
    
    if [ ! -f "$FAVORITES_FILE" ]; then
        return 1
    fi
    
    # 检查收藏夹中是否有完全相同的应用
    while IFS= read -r line; do
        if [[ "$line" = "{" ]]; then
            in_app=true
            current_title=""
            current_cd=""
        elif [ "$in_app" = true ]; then
            if [[ "$line" =~ ^Title=(.*)$ ]]; then
                current_title="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^Cd=(.*)$ ]]; then
                current_cd="${BASH_REMATCH[1]}"
            elif [[ "$line" = "}" ]]; then
                # 只有当Title和Cd都相同时才算重复
                if [ "$current_title" = "$target_title" ] && [ "$current_cd" = "$target_cd" ]; then
                    return 0  # 找到完全重复
                fi
                in_app=false
            fi
        fi
    done < "$FAVORITES_FILE"
    
    return 1  # 未找到完全重复
}

# 获取Title的最大序号
get_max_title_number() {
    local base_title=$1
    local max_num=0
    local in_app=false
    local current_title=""
    
    if [ ! -f "$FAVORITES_FILE" ]; then
        return 0
    fi
    
    while IFS= read -r line; do
        if [[ "$line" = "{" ]]; then
            in_app=true
        elif [ "$in_app" = true ]; then
            if [[ "$line" =~ ^Title=(.*)$ ]]; then
                current_title="${BASH_REMATCH[1]}"
                # 检查是否是同一个基础标题（带序号）
                if [[ "$current_title" =~ ^${base_title}[[:space:]]*\(([0-9]+)\)$ ]]; then
                    local num="${BASH_REMATCH[1]}"
                    if [ "$num" -gt "$max_num" ]; then
                        max_num=$num
                    fi
                elif [ "$current_title" = "$base_title" ]; then
                    # 如果找到没有序号的完全匹配，设置max_num为1
                    if [ "$max_num" -eq 0 ]; then
                        max_num=1
                    fi
                fi
            elif [[ "$line" = "}" ]]; then
                in_app=false
            fi
        fi
    done < "$FAVORITES_FILE"
    
    echo $max_num
}

# 添加到收藏夹
add_to_favorites() {
    local app_id=$1
    local app_info
    
    # 检查是否完全重复
    if check_if_exact_duplicate "$app_id"; then
        echo "${CDR}此应用已在收藏夹中（标题和命令完全相同）${NC}"
        return 1
    fi
    
    # 获取应用信息
    app_info=$(get_app_info_from_market "$app_id" "$CACHE_FILE")
    if [ $? -ne 0 ]; then
        echo "${CDR}未找到应用信息${NC}"
        return 1
    fi
    
    # 获取当前收藏夹中的最大ID
    local max_id=0
    while IFS= read -r line; do
        if [[ "$line" =~ ^ID=\<([0-9]+)\>$ ]]; then
            local current_id="${BASH_REMATCH[1]}"
            if [ "$current_id" -gt "$max_id" ]; then
                max_id=$current_id
            fi
        fi
    done < "$FAVORITES_FILE"
    
    # 新ID为最大ID+1
    local new_id=$((max_id + 1))
    
    # 处理可能的标题重复
    local title=""
    local original_title=""
    while IFS= read -r line; do
        if [[ "$line" =~ ^TITLE=(.*)$ ]]; then
            original_title="${BASH_REMATCH[1]}"
            title="$original_title"
            # 检查是否需要添加序号
            local max_num=$(get_max_title_number "$original_title")
            if [ "$max_num" -gt 0 ]; then
                title="$original_title ($(($max_num + 1)))"
            fi
            break
        fi
    done <<< "$app_info"
    
    # 添加到收藏夹
    {
        echo "{"
        echo "ID=<$new_id>"
        echo "$app_info" | while IFS= read -r line; do
            if [[ "$line" =~ ^(TITLE|TEXT|COMMAND|TAG)=(.*)$ ]]; then
                local key="${BASH_REMATCH[1]}"
                local value="${BASH_REMATCH[2]}"
                case "$key" in
                    "TITLE") echo "Title=$title" ;;  # 使用可能修改过的标题
                    "TEXT") echo "Text=$value" ;;
                    "COMMAND") echo "Cd=$value" ;;
                    "TAG") echo "Tag=$value" ;;
                esac
            fi
        done
        echo "}"
        echo
    } >> "$FAVORITES_FILE"
    
    echo "${CD}已添加到收藏夹${NC}"
    return 0
}

# 显示收藏夹
show_favorites() {
    if [ ! -f "$FAVORITES_FILE" ]; then
        echo "${CDR}收藏夹为空${NC}"
        return 1
    fi
    
    echo "====================="
    echo " 收藏夹"
    echo "====================="
    
    # 添加顶部边框
    printf "╔═══════════════════════════════════════\n"
    
    local in_app=false
    while IFS= read -r line; do
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        if [ -z "$line" ]; then
            continue
        fi
        
        case "$line" in
            "{")
                in_app=true
                ;;
            "}")
                printf "╚═══════════════════════════════════════\n"
                in_app=false
                ;;
            *)
                if [ "$in_app" = true ]; then
                    if [[ "$line" =~ ^ID=\<([0-9]+)\>$ ]]; then
                        local id="${BASH_REMATCH[1]}"
                        printf "║ ${CDB}%s${NC}\n" "应用ID: $id"
                    elif [[ "$line" =~ ^Title=(.*)$ ]]; then
                        local title="${BASH_REMATCH[1]}"
                        printf "║ ${CD}%s${NC}\n" "$title"
                    elif [[ "$line" =~ ^Text=(.*)$ ]]; then
                        local text="${BASH_REMATCH[1]}"
                        format_text "$text"
                    elif [[ "$line" =~ ^Tag=(.*)$ ]]; then
                        local tag="${BASH_REMATCH[1]}"
                        if [ -n "$tag" ]; then
                            printf "║ ${CDR}标签: %s${NC}\n" "$tag"
                        fi
                    fi
                fi
                ;;
        esac
    done < "$FAVORITES_FILE"
    
    return 0
}

# 从收藏夹中删除应用
remove_from_favorites() {
    local app_id=$1
    local batch_mode=${2:-false}  # 新增：批量模式标志
    local temp_file=$(mktemp)
    local found=false
    local in_app=false
    local current_app=""
    local current_id=""
    local deleted_count=0
    
    echo "DEBUG: 开始删除收藏项 ID: $app_id (批量模式: $batch_mode)"
    echo "DEBUG: 临时文件路径: $temp_file"
    
    if [ ! -f "$FAVORITES_FILE" ]; then
        echo "${CDR}收藏夹文件不存在${NC}"
        return 1
    fi
    
    # 确定输入文件
    local input_file="$FAVORITES_FILE"
    if [ "$batch_mode" = true ] && [ -f "$FAVORITES_FILE.temp" ]; then
        input_file="$FAVORITES_FILE.temp"
    fi
    echo "DEBUG: 使用输入文件: $input_file"
    
    # 创建新的临时文件用于输出
    local output_file=$(mktemp)
    head -n 1 "$input_file" > "$output_file"
    
    # 逐行读取并处理
    while IFS= read -r line || [ -n "$line" ]; do
        # 跳过第一行（Name行）
        if [[ "$line" =~ ^Name= ]]; then
            continue
        fi
        
        # 去除行尾的回车符和空格
        line=$(echo "$line" | tr -d '\r' | sed 's/[[:space:]]*$//')
        
        if [[ "$line" = "{" ]]; then
            echo "DEBUG: 开始新的应用块"
            in_app=true
            current_app="{\n"
            current_id=""
            found=false
        elif [ "$in_app" = true ]; then
            if [[ "$line" =~ ^ID=\<([0-9]+)\>$ ]]; then
                current_id="${BASH_REMATCH[1]}"
                echo "DEBUG: 当前处理的应用 ID: $current_id"
                if [ "$current_id" = "$app_id" ]; then
                    echo "DEBUG: 找到要删除的应用 ID: $current_id"
                    found=true
                    ((deleted_count++))
                fi
            fi
            
            current_app+="$line\n"
            
            if [[ "$line" = "}" ]]; then
                echo "DEBUG: 应用块结束"
                echo "DEBUG: current_id=$current_id, app_id=$app_id, found=$found"
                in_app=false
                if [ "$found" = false ]; then
                    echo "DEBUG: 保存此应用块 (ID: $current_id)"
                    echo -e "$current_app" >> "$output_file"
                    echo "" >> "$output_file"  # 添加空行
                else
                    echo "DEBUG: 跳过此应用块 (ID: $current_id)"
                fi
                current_app=""
            fi
        fi
    done < "$input_file"
    
    echo "DEBUG: 输出文件内容:"
    cat "$output_file"
    
    if [ "$batch_mode" = true ]; then
        # 在批量模式下，保存中间结果
        mv "$output_file" "$FAVORITES_FILE.temp"
        rm -f "$temp_file"
    else
        # 非批量模式，执行重新编号
        local final_file=$(mktemp)
        echo "DEBUG: 最终文件路径: $final_file"
        local new_id=1
        in_app=false
        
        # 复制文件头部（Name行）
        head -n 1 "$output_file" > "$final_file"
        
        # 处理应用块
        while IFS= read -r line || [ -n "$line" ]; do
            # 跳过第一行（Name行）
            if [[ "$line" =~ ^Name= ]]; then
                continue
            fi
            
            # 去除行尾的回车符和空格
            line=$(echo "$line" | tr -d '\r' | sed 's/[[:space:]]*$//')
            
            if [[ "$line" = "{" ]]; then
                in_app=true
                echo "{" >> "$final_file"
            elif [ "$in_app" = true ]; then
                if [[ "$line" =~ ^ID=\<[0-9]+\>$ ]]; then
                    echo "DEBUG: 重新编号为 $new_id"
                    echo "ID=<$new_id>" >> "$final_file"
                    ((new_id++))
                else
                    echo "$line" >> "$final_file"
                fi
                if [[ "$line" = "}" ]]; then
                    in_app=false
                    echo "" >> "$final_file"  # 添加空行
                fi
            fi
        done < "$output_file"
        
        echo "DEBUG: 最终文件内容:"
        cat "$final_file"
        
        # 更新收藏夹文件
        mv "$final_file" "$FAVORITES_FILE"
        rm -f "$output_file" "$temp_file" "$FAVORITES_FILE.temp" 2>/dev/null
    fi
    
    if [ "$deleted_count" -gt 0 ]; then
        echo "DEBUG: 成功删除了 $deleted_count 个应用"
        return 0
    else
        echo "DEBUG: 没有找到要删除的应用"
        return 1
    fi
}

# 批量删除收藏夹中的应用
batch_remove_from_favorites() {
    local id_list=$1
    local total_count=0
    local success_count=0
    local fail_count=0
    local is_last=false
    
    # 获取要处理的ID列表
    local ids=($(process_id_list "$id_list"))
    local total=${#ids[@]}
    
    for ((i=0; i<total; i++)); do
        local app_id=${ids[$i]}
        echo "${CDB}正在处理ID: $app_id ($(($i+1))/$total)${NC}"
        
        # 检查是否是最后一个ID
        if [ $((i+1)) -eq $total ]; then
            is_last=true
        fi
        
        # 调用remove_from_favorites，传递当前处理的ID和批量模式标志
        if remove_from_favorites "$app_id" true; then
            ((success_count++))
        else
            ((fail_count++))
        fi
    done
    
    # 最后一次操作完成后，执行重新编号
    if [ -f "$FAVORITES_FILE.temp" ]; then
        # 创建最终文件
        local final_file=$(mktemp)
        local new_id=1
        local in_app=false
        
        # 复制文件头部（Name行）
        head -n 1 "$FAVORITES_FILE.temp" > "$final_file"
        
        # 处理应用块
        while IFS= read -r line || [ -n "$line" ]; do
            # 跳过第一行（Name行）
            if [[ "$line" =~ ^Name= ]]; then
                continue
            fi
            
            # 去除行尾的回车符和空格
            line=$(echo "$line" | tr -d '\r' | sed 's/[[:space:]]*$//')
            
            if [[ "$line" = "{" ]]; then
                in_app=true
                echo "{" >> "$final_file"
            elif [ "$in_app" = true ]; then
                if [[ "$line" =~ ^ID=\<[0-9]+\>$ ]]; then
                    echo "DEBUG: 重新编号为 $new_id"
                    echo "ID=<$new_id>" >> "$final_file"
                    ((new_id++))
                else
                    echo "$line" >> "$final_file"
                fi
                if [[ "$line" = "}" ]]; then
                    in_app=false
                    echo "" >> "$final_file"  # 添加空行
                fi
            fi
        done < "$FAVORITES_FILE.temp"
        
        echo "DEBUG: 最终文件内容:"
        cat "$final_file"
        
        # 更新收藏夹文件
        mv "$final_file" "$FAVORITES_FILE"
        rm -f "$FAVORITES_FILE.temp" 2>/dev/null
    fi
    
    echo "${CDB}批量删除完成${NC}"
    echo "${CD}成功: $success_count${NC}"
    echo "${CDR}失败: $fail_count${NC}"
    return 0
}

# 从收藏夹执行命令
run_favorite() {
    local app_id=$1
    local command=""
    local path=""
    local in_app=false
    local current_id=""
    local found=false
    
    # 检查收藏夹文件是否存在
    if [ ! -f "$FAVORITES_FILE" ]; then
        echo "${CDR}错误：收藏夹文件不存在${NC}"
        return 1
    fi
    
    while IFS= read -r line; do
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        if [ -z "$line" ]; then
            continue
        fi
        
        case "$line" in
            "{")
                in_app=true
                current_id=""
                command=""
                path=""
                tag=""
                ;;
            "}")
                if [ "$current_id" = "$app_id" ]; then
                    found=true
                    if [ -n "$command" ]; then
                        if [ "$path" != "null" ]; then
                            echo "cd $path && $command"
                        else
                            echo "$command"
                        fi
                        return 0
                    else
                        echo "${CDR}错误：ID为 $app_id 的应用没有可执行的命令${NC}"
                        return 1
                    fi
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
                    elif [[ "$line" =~ ^Tag=(.*)$ ]]; then
                        tag="${BASH_REMATCH[1]}"
                    elif [[ "$line" =~ ^[[:space:]]*\>[[:space:]]*(.*)$ ]] && [ -n "$command" ]; then
                        command="$command && ${BASH_REMATCH[1]}"
                    fi
                fi
                ;;
        esac
    done < "$FAVORITES_FILE"
    
    if [ "$found" = false ]; then
        echo "${CDR}错误：未找到ID为 $app_id 的应用${NC}"
    fi
    return 1
}

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
    
    # 如果点赞API地址是自动生成的，则同时更新点赞API地址
    if [ -f "$LIKE_API_URL_FILE" ]; then
        local current_like_api=$(cat "$LIKE_API_URL_FILE")
        local auto_like_api=$(get_like_api_url)
        
        # 如果当前点赞API是自动生成的格式，则更新
        if [[ "$current_like_api" =~ ^https://[^/]+/like_api\.php$ ]]; then
            echo "$auto_like_api" > "$LIKE_API_URL_FILE"
            echo "${CDB}已自动更新点赞API地址: $auto_like_api${NC}" >&2
        fi
    fi
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
    return 0
}

# 渲染文本（处理变量和样式）
render_text() {
    local text="$1"
    
    # 只替换颜色相关的变量
    local color_vars="CD|CDB|CDR|CDRB|NC"
    
    # 使用eval来处理变量替换
    # 将文本中的${VAR}替换为$VAR，然后用eval处理
    text=$(echo "$text" | sed 's/\${/$/g' | sed 's/}//')
    text=$(eval "echo \"$text\"")
    
    echo -e "$text"
}

# 处理PATH中的变量定义
process_path_definitions() {
    local app="$1"
    local path_content=$(echo "$app" | jq -r '.PATH')
    
    # 导出脚本自带的颜色变量
    export CD CDB CDR NC
    
    # 如果PATH包含变量定义
    if [[ "$path_content" == *"="* ]]; then
        # 分号分隔多个变量定义
        IFS=';' read -ra VARS <<< "$path_content"
        for var_def in "${VARS[@]}"; do
            if [[ "$var_def" =~ ^[A-Z][A-Z_]*=.*$ ]]; then
                # 执行变量定义
                eval "export $var_def"
            fi
        done
    fi
}

# 显示应用市场列表
show_app_list() {
    local search_tag=${1:-""}  # 新增：搜索标签参数
    
    if [ ! -f "$CACHE_FILE" ]; then
        echo "${CDR}未找到应用市场数据，请先更新${NC}" >&2
        return 1
    fi
    
    local in_app=false
    local id=""
    local title=""
    local text=""
    local tag=""
    local market_name=""
    local global_path=""
    local is_first_app=true
    local market_url=""
    local app_ids=()
    local app_titles=()
    local app_texts=()
    local app_tags=()   # 改为二维数组，存储每个应用的所有标签
    local app_count=0
    local tag_order=""
    
    # 获取当前的应用市场URL
    if [ -f "$MARKET_URL_FILE" ]; then
        market_url=$(cat "$MARKET_URL_FILE")
    fi
    
    # 首先读取Name和Tag_order字段
    while IFS= read -r line; do
        if [[ "$line" =~ ^Name=(.*)$ ]]; then
            market_name="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^Tag_order=(.*)$ ]]; then
            tag_order="${BASH_REMATCH[1]}"
        fi
    done < "$CACHE_FILE"

    # 显示顶部信息
    echo "====================="
    if [ -n "$search_tag" ]; then
        echo " 应用市场 $market_name (搜索标签: $search_tag)"
    else
        echo " 应用市场 $market_name"
    fi
    echo "====================="
    
    # 添加顶部边框
    printf "╔═══════════════════════════════════════\n"
    
    # 第一次遍历：收集所有应用信息
    while IFS= read -r line; do
        # 去除空格和回车符
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # 跳过空行
        if [ -z "$line" ]; then
            continue
        fi
        
        # 跳过已处理的Name字段
        if [[ "$line" =~ ^Name= ]]; then
            continue
        fi

        # 检查是否是顶级 PATH 字段
        if [[ "$line" =~ ^PATH=(.*)$ ]] && [ -z "$global_path" ]; then
            # 直接执行PATH中的变量定义
            eval "${BASH_REMATCH[1]}"
            global_path="${BASH_REMATCH[1]}"
            continue
        fi
        

        
        case "$line" in
            "{"|" {")
                in_app=true
                id=""
                title=""
                text=""
                tag=""
                ;;
            "}")
                if [ -n "$id" ] && [ -n "$title" ]; then
                    # 强制插入：如果有filter_ids，只显示在列表中的ID
                    if [ -n "$filter_ids" ]; then
                        local show_this_id=false
                        IFS=',' read -ra filter_arr <<< "$filter_ids"
                        for fid in "${filter_arr[@]}"; do
                            if [ "$id" = "$fid" ]; then
                                show_this_id=true
                                break
                            fi
                        done
                        if [ "$show_this_id" = false ]; then
                            in_app=false
                            continue
                        fi
                    fi
                    IFS=' ' read -ra tag_arr <<< "$tag"
                    if [ -z "$search_tag" ]; then
                        app_ids[$app_count]="$id"
                        app_titles[$app_count]="$title"
                        app_texts[$app_count]="$text"
                        app_tags[$app_count]="${tag_arr[*]}"
                        ((app_count++))
                    else
                        # 多标签搜索：全部命中才显示
                        IFS=' ' read -ra search_tags_arr <<< "$search_tag"
                        local all_match=true
                        for st in "${search_tags_arr[@]}"; do
                            local found=false
                            for t in "${tag_arr[@]}"; do
                                if [[ "${t,,}" = "${st,,}" ]]; then
                                    found=true
                                    break
                                fi
                            done
                            if [ "$found" = false ]; then
                                all_match=false
                                break
                            fi
                        done
                        if [ "$all_match" = true ]; then
                            app_ids[$app_count]="$id"
                            app_titles[$app_count]="$title"
                            app_texts[$app_count]="$text"
                            app_tags[$app_count]="${tag_arr[*]}"
                            ((app_count++))
                        fi
                    fi
                fi
                in_app=false
                ;;
            *)
                if [ "$in_app" = true ]; then
                    if [[ "$line" =~ ^ID=\<([0-9]+)\>$ ]]; then
                        id="${BASH_REMATCH[1]}"
                    elif [[ "$line" =~ ^Title=(.*)$ ]]; then
                        title="${BASH_REMATCH[1]}"
                    elif [[ "$line" =~ ^Text=(.*)$ ]]; then
                        text="${BASH_REMATCH[1]}"
                    elif [[ "$line" =~ ^Tag=(.*)$ ]]; then
                        tag="${BASH_REMATCH[1]}"
                    fi
                fi
                ;;
        esac
    done < "$CACHE_FILE"
    

    
    # 批量获取点赞数（优化版本）
    local likes_cache=()
    local api_url=$(get_like_api_url)
    
    # 检查是否应该显示点赞数
    if should_show_likes; then
        echo "${CDB}正在获取点赞数据...${NC}" >&2
        
        # 首先尝试从缓存获取
        for ((i=0; i<app_count; i++)); do
            local app_id=${app_ids[$i]}
            local cached_likes=$(get_likes_from_cache "$app_id")
            
            # 检查缓存是否有效（5分钟内）
            if [ -f "$LIKES_CACHE_FILE" ]; then
                local cache_age=$(($(date +%s) - $(stat -c %Y "$LIKES_CACHE_FILE" 2>/dev/null || echo 0)))
                if [ "$cache_age" -lt 300 ] && [ "$cached_likes" != "0" ]; then
                    likes_cache[$i]="$cached_likes"
                    continue
                fi
            fi
            
            # 如果缓存无效，尝试从API获取
            local likes=$(get_app_likes "$app_id" 2>/dev/null)
            if [ $? -eq 0 ] && [ -n "$likes" ]; then
                likes_cache[$i]="$likes"
                # 更新缓存
                update_likes_cache "$app_id" "$likes"
            else
                likes_cache[$i]="0"
            fi
        done
    else
        # 如果不显示点赞数，全部设为0
        for ((i=0; i<app_count; i++)); do
            likes_cache[$i]="0"
        done
    fi
    
    # 按标签分组并排序
    local tag_groups=()
    local tag_apps=()
    
    # 创建标签分组（多标签支持）
    for ((i=0; i<app_count; i++)); do
        IFS=' ' read -ra tags_arr <<< "${app_tags[$i]}"
        for t in "${tags_arr[@]}"; do
            [ -z "$t" ] && t="未分类"
            local found=false
            for ((j=0; j<${#tag_groups[@]}; j++)); do
                if [ "${tag_groups[$j]}" = "$t" ]; then
                    found=true
                    break
                fi
            done
            if [ "$found" = false ]; then
                tag_groups+=("$t")
            fi
        done
    done
    
    # 根据Tag_order排序标签
    if [ -n "$tag_order" ]; then
        local ordered_tags=()
        local remaining_tags=()
        
        # 按照Tag_order的顺序添加标签
        IFS=' ' read -ra order_array <<< "$tag_order"
        for order_tag in "${order_array[@]}"; do
            for ((i=0; i<${#tag_groups[@]}; i++)); do
                if [ "${tag_groups[$i]}" = "$order_tag" ]; then
                    ordered_tags+=("$order_tag")
                    break
                fi
            done
        done
        
        # 添加剩余的标签（不在Tag_order中的）
        for tag in "${tag_groups[@]}"; do
            local found=false
            for ordered_tag in "${ordered_tags[@]}"; do
                if [ "$tag" = "$ordered_tag" ]; then
                    found=true
                    break
                fi
            done
            if [ "$found" = false ]; then
                remaining_tags+=("$tag")
            fi
        done
        
        # 合并排序后的标签
        tag_groups=("${ordered_tags[@]}" "${remaining_tags[@]}")
    fi
    
    # 按标签分组显示应用（多标签支持）
    for tag in "${tag_groups[@]}"; do
        # 显示标签分隔线
        printf "║ ---------%s---------\n" "$tag"
        
        # 收集该标签下的所有应用
        local tag_app_ids=()
        local tag_app_titles=()
        local tag_app_texts=()
        local tag_app_likes=()
        local tag_app_count=0
        
        for ((i=0; i<app_count; i++)); do
            IFS=' ' read -ra tags_arr <<< "${app_tags[$i]}"
            for t in "${tags_arr[@]}"; do
                [ -z "$t" ] && t="未分类"
                if [ "$t" = "$tag" ]; then
                    tag_app_ids[$tag_app_count]=${app_ids[$i]}
                    tag_app_titles[$tag_app_count]=${app_titles[$i]}
                    tag_app_texts[$tag_app_count]=${app_texts[$i]}
                    tag_app_likes[$tag_app_count]=${likes_cache[$i]}
                    ((tag_app_count++))
                    break
                fi
            done
        done
        
        # 按ID排序（冒泡排序）
        for ((i=0; i<tag_app_count-1; i++)); do
            for ((j=0; j<tag_app_count-i-1; j++)); do
                if [ "${tag_app_ids[$j]}" -gt "${tag_app_ids[$((j+1))]}" ]; then
                    # 交换ID
                    local temp_id=${tag_app_ids[$j]}
                    tag_app_ids[$j]=${tag_app_ids[$((j+1))]}
                    tag_app_ids[$((j+1))]=$temp_id
                    
                    # 交换标题
                    local temp_title=${tag_app_titles[$j]}
                    tag_app_titles[$j]=${tag_app_titles[$((j+1))]}
                    tag_app_titles[$((j+1))]=$temp_title
                    
                    # 交换描述
                    local temp_text=${tag_app_texts[$j]}
                    tag_app_texts[$j]=${tag_app_texts[$((j+1))]}
                    tag_app_texts[$((j+1))]=$temp_text
                    
                    # 交换点赞数
                    local temp_likes=${tag_app_likes[$j]}
                    tag_app_likes[$j]=${tag_app_likes[$((j+1))]}
                    tag_app_likes[$((j+1))]=$temp_likes
                fi
            done
        done
        
        # 显示该标签下的应用
        for ((i=0; i<tag_app_count; i++)); do
            local app_id=${tag_app_ids[$i]}
            local title=${tag_app_titles[$i]}
            local text=${tag_app_texts[$i]}
            local likes=${tag_app_likes[$i]}
            
            # 渲染标题中的变量
            title=$(render_text "$title")
            
            # 显示应用信息
            printf "║ <%d> %s ${CDB}[❤️ %s]${NC}\n" "$app_id" "$title" "$likes"
            if [ -n "$text" ]; then
                format_text "$text"
                printf "║\n"
            fi
        done
    done
    
    # 添加底部边框
    printf "╚═══════════════════════════════════════\n"
    
    # 返回市场名称
    echo "$market_name"
    return 0
}

# 获取所有可用标签（多标签支持，按点赞数排序，最多显示9条，支持__REST__提示）
get_available_tags_with_likes() {
    local mode=""
    if [ "$1" = "all" ]; then
        mode="all"
    fi
    if [ ! -f "$CACHE_FILE" ]; then
        echo "${CDR}未找到应用市场数据${NC}" >&2
        return 1
    fi
    local in_app=false
    local app_id=""
    local tag_line=""
    local tag_likes_map=()
    local tag_app_ids_map=()
    local app_likes_map=()
    local app_tag_map=()
    local all_tags=()
    local app_count=0
    local app_ids=()
    local likes_cache=()

    # 先收集所有应用的ID和标签
    while IFS= read -r line; do
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ -z "$line" ]; then
            continue
        fi
        case "$line" in
            "{"|" {")
                in_app=true
                app_id=""
                tag_line=""
                ;;
            "}")
                if [ -n "$app_id" ] && [ -n "$tag_line" ]; then
                    app_ids[$app_count]="$app_id"
                    app_tag_map[$app_count]="$tag_line"
                    ((app_count++))
                fi
                in_app=false
                ;;
            *)
                if [ "$in_app" = true ]; then
                    if [[ "$line" =~ ^ID=\<([0-9]+)\>$ ]]; then
                        app_id="${BASH_REMATCH[1]}"
                    elif [[ "$line" =~ ^Tag=(.*)$ ]]; then
                        tag_line="${BASH_REMATCH[1]}"
                    fi
                fi
                ;;
        esac
    done < "$CACHE_FILE"

    # 获取所有应用的点赞数（缓存/接口）
    for ((i=0; i<app_count; i++)); do
        local id="${app_ids[$i]}"
        local cached_likes=$(get_likes_from_cache "$id")
        if [ -f "$LIKES_CACHE_FILE" ]; then
            local cache_age=$(($(date +%s) - $(stat -c %Y "$LIKES_CACHE_FILE" 2>/dev/null || echo 0)))
            if [ "$cache_age" -lt 300 ] && [ "$cached_likes" != "0" ]; then
                likes_cache[$i]="$cached_likes"
                continue
            fi
        fi
        local likes=$(get_app_likes "$id" 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$likes" ]; then
            likes_cache[$i]="$likes"
            update_likes_cache "$id" "$likes"
        else
            likes_cache[$i]="0"
        fi
    done

    # 统计每个标签的总点赞数
    declare -A tag_likes_sum
    declare -A tag_app_count
    for ((i=0; i<app_count; i++)); do
        local tags_str="${app_tag_map[$i]}"
        local likes=${likes_cache[$i]:-0}
        IFS=' ' read -ra tags_arr <<< "$tags_str"
        for t in "${tags_arr[@]}"; do
            [ -z "$t" ] && t="未分类"
            tag_likes_sum["$t"]=$(( ${tag_likes_sum["$t"]:-0} + likes ))
            tag_app_count["$t"]=$(( ${tag_app_count["$t"]:-0} + 1 ))
        done
    done

    # 收集所有标签
    for t in "${!tag_likes_sum[@]}"; do
        all_tags+=("$t")
    done

    # 构建"点赞数|标签名"数组
    local tag_score_arr=()
    for t in "${all_tags[@]}"; do
        tag_score_arr+=( "${tag_likes_sum[$t]}|$t" )
    done

    # 纯bash按点赞数降序排序
    for ((i=0; i<${#tag_score_arr[@]}; i++)); do
        for ((j=i+1; j<${#tag_score_arr[@]}; j++)); do
            local score_i=${tag_score_arr[$i]%%|*}
            local score_j=${tag_score_arr[$j]%%|*}
            if (( score_j > score_i )); then
                # 交换
                local tmp=${tag_score_arr[$i]}
                tag_score_arr[$i]=${tag_score_arr[$j]}
                tag_score_arr[$j]=$tmp
            fi
        done
    done

        local total_tags=${#tag_score_arr[@]}
    if [ "$mode" = "all" ]; then
        for ((i=0; i<total_tags; i++)); do
            local entry="${tag_score_arr[$i]}"
            local score="${entry%%|*}"
            local t="${entry##*|}"
            echo "$t|$score"
        done
    else
        local show_count=9
        for ((i=0; i<total_tags && i<show_count; i++)); do
            local entry="${tag_score_arr[$i]}"
            local score="${entry%%|*}"
            local t="${entry##*|}"
            echo "$t|$score"
        done
        if [ $total_tags -gt $show_count ]; then
            local rest=$((total_tags-show_count))
            echo "__REST__|$rest"
        fi
    fi
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
    # local path=""  # 移除应用内path
    local collecting_command=false
    
    while IFS= read -r line; do
        # 去除空格和回车符
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # 跳过空行
        if [ -z "$line" ]; then
            continue
        fi
        
        case "$line" in
            "{"|" {")
                in_app=true
                current_id=""
                command=""
                # path=""  # 移除应用内path
                collecting_command=false
                ;;
            "}")
                if [ "$current_id" = "$app_id" ] && [ -n "$command" ]; then
                        echo "$command"
                    return 0
                fi
                in_app=false
                collecting_command=false
                ;;
            *)
                if [ "$in_app" = true ]; then
                    if [[ "$line" =~ ^ID=\<([0-9]+)\>$ ]]; then
                        current_id="${BASH_REMATCH[1]}"
                        collecting_command=false
                    elif [[ "$line" =~ ^Cd=(.*)$ ]]; then
                        command="${BASH_REMATCH[1]}"
                        collecting_command=true
                    # elif [[ "$line" =~ ^PATH=(.*)$ ]]; then
                    #     path="${BASH_REMATCH[1]}"
                    #     collecting_command=false
                    elif [[ "$line" =~ ^[[:space:]]*\>[[:space:]]*(.*)$ ]] && [ "$collecting_command" = true ]; then
                        # 如果行以 > 开头且正在收集命令，则添加到命令中
                        local line_content="${BASH_REMATCH[1]}"
                        if [ -n "$line_content" ]; then
                            command="$command && $line_content"
                        fi
                    elif [[ ! "$line" =~ ^[[:space:]]*\> ]]; then
                        collecting_command=false
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
        # 创建临时脚本文件
        local tmp_script=$(mktemp)
        echo "#!/bin/bash" > "$tmp_script"
        echo "$command" >> "$tmp_script"
        chmod +x "$tmp_script"
        
        # 执行临时脚本
        bash "$tmp_script"
        local exit_code=$?
        
        # 清理临时文件
        rm -f "$tmp_script"
        
        return $exit_code
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
    # 初始化收藏夹和点赞API
    init_favorites
    init_like_api
    
    while true; do
        clear
        # 优化：减少自动刷新频率，只在必要时刷新
        if [ -f "$MARKET_URL_FILE" ]; then
            local market_url=$(cat "$MARKET_URL_FILE")
            if [ -n "$market_url" ]; then
                # 检查缓存文件是否存在，如果不存在或太旧则刷新
                local need_refresh=false
                if [ ! -f "$CACHE_FILE" ]; then
                    need_refresh=true
                else
                    # 延长缓存时间到6小时，减少网络请求
                    local file_age=$(($(date +%s) - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)))
                    if [ "$file_age" -gt 21600 ]; then
                        need_refresh=true
                    fi
                fi
                
                if [ "$need_refresh" = true ]; then
                    echo "${CDB}正在自动刷新应用市场数据...${NC}"
                    if fetch_app_market "$market_url"; then
                        echo "${CD}应用市场数据已更新${NC}"
                    else
                        echo "${CDR}应用市场数据更新失败，使用缓存数据${NC}"
                    fi
                    sleep 1
                fi
            fi
        fi
        
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
            
            # 显示应用列表
            echo "$app_list"
            
            echo "-------------"
            echo "|<0>${CDB}修改应用市场${NC}"
            echo "|<r>${CDB}刷新应用市场${NC}"
            echo "|<s>${CDB}搜索标签${NC}"
            echo "|<c>${CDB}打开收藏夹${NC}"
            echo "|<l>${CDB}设置点赞API${NC}"
            echo "|<help>${CDB}帮助文档${NC}"
            echo "|<q>${CDR}返回主菜单${NC}"
            echo "===================="
            
            read -p "请选择: " choice
            case $choice in
                help|HELP|Help)
                    # 深蓝底浅蓝粗体字
                    echo -e "\033[1;44;97mHELP文档地址合集${NC}"
                    echo -e "${CDB}Github：${NC}"
                    echo "https://github.com/yzh118/VPSManager/blob/main/HELP.md"
                    read -p "按回车键返回菜单..."
                    ;;
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
                s|S)
                    # 搜索标签功能
                    search_tag_mode=true
                    while [ "$search_tag_mode" = true ]; do
                        clear
                        echo "====================="
                        echo " 标签搜索"
                        echo "====================="
                        echo ""
                        
                        # 显示所有可用标签
                        echo "${CDB}可用标签列表:${NC}"
                        echo "-------------"
                        local available_tags_arr=()
                        while IFS= read -r taginfo; do
                            available_tags_arr+=("$taginfo")
                        done < <(get_available_tags_with_likes)
                        if [ ${#available_tags_arr[@]} -eq 0 ]; then
                            echo "${CDR}当前没有可用的标签${NC}"
                        else
                            local shown=0
                            local has_rest=false
                            for taginfo in "${available_tags_arr[@]}"; do
                                local tagname="${taginfo%%|*}"
                                local taglikes="${taginfo##*|}"
                                if [ "$tagname" = "__REST__" ]; then
                                    has_rest=true
                                    echo "……"
                                    echo "其余标签共${taglikes}个（直接回车查看所有）"
                                    continue
                                fi
                                ((shown++))
                                printf "%d) %s ❤️ %s\n" $shown "$tagname" "$taglikes"
                            done
                            if [ "$has_rest" = true ]; then
                                read -p "请输入要搜索的标签或应用名 (留空显示所有标签，q返回):" search_tag
                                if [ -z "$search_tag" ]; then
                                    # 显示所有标签IFS
                                    local all_tags_arr=()
                                    while IFS= read -r taginfo; do
                                        all_tags_arr+=("$taginfo")
                                    done < <(get_available_tags_with_likes all)
                                    shown=0
                                    for taginfo in "${all_tags_arr[@]}"; do
                                        local tagname="${taginfo%%|*}"
                                        local taglikes="${taginfo##*|}"
                                        ((shown++))
                                        printf "%d) %s ❤️ %s\n" $shown "$tagname" "$taglikes"
                                    done
                                    echo ""
                                    read -p "按回车键返回..."
                                    continue
                                fi
                            else
                                echo "请输入要搜索的标签或应用名 (留空显示所有应用，q返回):"
                                read -p "标签: " search_tag
                            fi
                        fi
                        
                        if [ "$search_tag" = "q" ] || [ "$search_tag" = "Q" ]; then
                            search_tag_mode=false
                            break
                        fi
                        
                        if [ -n "$search_tag" ]; then
                            # 直接模糊匹配Title并输出，不调用show_app_list
                            local matched_apps=()
                            local matched_scores=()
                            local in_app=false
                            local current_id=""
                            local current_title=""
                            local current_text=""
                            local current_tag=""
                            while IFS= read -r line; do
                                line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                                case "$line" in
                                    "{"|" {")
                                        in_app=true
                                        current_id=""
                                        current_title=""
                                        current_text=""
                                        current_tag=""
                                        ;;
                                    "}")
                                        if [ -n "$current_id" ] && [ -n "$current_title" ]; then
                                            # 优化：不区分大小写，命中2个及以上就显示
                                            local title_lc=$(echo "$current_title" | tr '[:upper:]' '[:lower:]')
                                            local search_lc=$(echo "$search_tag" | tr '[:upper:]' '[:lower:]')
                                            local match_count=0
                                            local input_len=$(echo -n "$search_lc" | wc -m)
                                            for ((k=0; k<input_len; k++)); do
                                                local c=$(echo -n "$search_lc" | cut -c $((k+1))-$((k+1)))
                                                if [[ "$title_lc" == *"$c"* ]]; then
                                                    ((match_count++))
                                                fi
                                            done
                                            if [ $match_count -ge 2 ]; then
                                                matched_apps+=("$current_id|$current_title|$current_text|$current_tag")
                                                matched_scores+=("$match_count")
                                            fi
                                        fi
                                        in_app=false
                                        ;;
                                    *)
                                        if [ "$in_app" = true ]; then
                                            if [[ "$line" =~ ^ID=\<([0-9]+)\>$ ]]; then
                                                current_id="${BASH_REMATCH[1]}"
                                            elif [[ "$line" =~ ^Title=(.*)$ ]]; then
                                                current_title="${BASH_REMATCH[1]}"
                                            elif [[ "$line" =~ ^Text=(.*)$ ]]; then
                                                current_text="${BASH_REMATCH[1]}"
                                            elif [[ "$line" =~ ^Tag=(.*)$ ]]; then
                                                current_tag="${BASH_REMATCH[1]}"
                                            fi
                                        fi
                                        ;;
                                esac
                            done < "$CACHE_FILE"

                            # 按匹配度降序排序
                            local n=${#matched_apps[@]}
                            for ((i=0; i<n-1; i++)); do
                                for ((j=i+1; j<n; j++)); do
                                    if (( matched_scores[j] > matched_scores[i] )); then
                                        # 交换分数
                                        local tmp_score=${matched_scores[i]}
                                        matched_scores[i]=${matched_scores[j]}
                                        matched_scores[j]=$tmp_score
                                        # 交换应用
                                        local tmp_app=${matched_apps[i]}
                                        matched_apps[i]=${matched_apps[j]}
                                        matched_apps[j]=$tmp_app
                                    fi
                                done
                            done

                            if [ ${#matched_apps[@]} -eq 0 ]; then
                                echo "${CDR}未找到匹配的应用${NC}"
                                read -p "按回车键继续..."
                                continue
                            fi

                            echo "====================="
                            echo " 模糊搜索结果"
                            echo "====================="
                            printf "╔═══════════════════════════════════════\n"
                            for app in "${matched_apps[@]}"; do
                                local id="${app%%|*}"
                                local rest="${app#*|}"
                                local title="${rest%%|*}"
                                local rest2="${rest#*|}"
                                local text="${rest2%%|*}"
                                local tag="${rest2#*|}"
                                local likes="0"
                                if should_show_likes; then
                                    likes=$(get_likes_from_cache "$id")
                                    # 检查缓存是否有效（5分钟内）
                                    local cache_valid=false
                                    if [ -f "$LIKES_CACHE_FILE" ]; then
                                        local cache_age=$(($(date +%s) - $(stat -c %Y "$LIKES_CACHE_FILE" 2>/dev/null || echo 0)))
                                        if [ "$cache_age" -lt 300 ] && [ "$likes" != "0" ]; then
                                            cache_valid=true
                                        fi
                                    fi
                                    if [ "$cache_valid" = false ]; then
                                        likes=$(get_app_likes "$id")
                                        update_likes_cache "$id" "$likes"
                                    fi
                                fi
                                printf "║ <%s> %s ❤️ %s\n" "$id" "$title" "$likes"
                                if [ -n "$text" ]; then
                                    printf "║    描述: %s\n" "$text"
                                fi
                                if [ -n "$tag" ]; then
                                    printf "║    标签: %s\n" "$tag"
                                fi
                                printf "║\n"
                            done
                            printf "╚═══════════════════════════════════════\n"
                            echo ""
                            echo "-------------"
                            echo "|<q>${CDR}返回搜索${NC}"
                            echo "===================="
                            read -p "请选择 (输入应用编号执行，ID+c收藏，ID+t点赞，q返回): " search_choice
                            case $search_choice in
                                q|Q)
                                    continue
                                    ;;
                                *)
                                    # 只允许操作在matched_apps中的ID
                                    local valid_id=false
                                    for app in "${matched_apps[@]}"; do
                                        local id="${app%%|*}"
                                        if [[ "$search_choice" =~ ^$id([ct]?)$ ]]; then
                                            valid_id=true
                                            break
                                        fi
                                    done
                                    if [ "$valid_id" = false ]; then
                                        echo "${CDR}无效选项${NC}"
                                        read -p "按回车键继续..."
                                        continue
                                    fi
                                    if [[ "$search_choice" =~ ^([0-9]+[,，])*[0-9]+c$ || "$search_choice" =~ ^[0-9]+-[0-9]+c$ ]]; then
                                        # 批量收藏应用
                                        local id_list=${search_choice%c}  # 移除末尾的c
                                        for app_id in $(process_id_list "$id_list"); do
                                            if add_to_favorites "$app_id"; then
                                                echo "${CD}ID为 $app_id 的应用已添加到收藏夹${NC}"
                                            else
                                                echo "${CDR}ID为 $app_id 的应用添加失败${NC}"
                                            fi
                                        done
                                        read -p "操作完成，按回车键继续..."
                                    elif [[ "$search_choice" =~ ^([0-9]+[,，])*[0-9]+t$ || "$search_choice" =~ ^[0-9]+-[0-9]+t$ ]]; then
                                        # 批量点赞应用
                                        local id_list=${search_choice%t}  # 移除末尾的t
                                        echo "${CDB}准备点赞ID列表: $id_list${NC}"
                                        echo "${CDB}处理后的ID列表:${NC}"
                                        process_id_list "$id_list" | while read -r id; do
                                            echo "${CDB}- $id${NC}"
                                        done
                                        read -p "确认要为这些应用点赞吗？(y/N): " confirm
                                        if [[ "$confirm" =~ ^[Yy]$ ]]; then
                                            batch_like_apps "$id_list"
                                            read -p "操作完成，按回车键继续..."
                                        fi
                                    elif [[ "$search_choice" =~ ^[0-9]+t$ ]]; then
                                        # 单个点赞应用
                                        local app_id=${search_choice%t}  # 移除末尾的t
                                        like_app "$app_id"
                                        read -p "按回车键继续..."
                                    elif [[ "$search_choice" =~ ^[0-9]+$ ]]; then
                                        if run_app "$search_choice"; then
                                            read -p "命令执行完成，按回车键继续..."
                                        else
                                            read -p "命令执行失败，按回车键继续..."
                                        fi
                                    else
                                        echo "${CDR}无效选项${NC}"
                                        read -p "按回车键继续..."
                                    fi
                                    ;;
                            esac
                            continue
                        fi
                    done
                    ;;
                c|C)
                    while true; do
                        clear
                        show_favorites
                        echo "-------------"
                        echo "|<q>${CDR}返回应用市场${NC}"
                        echo "===================="
                        read -p "请选择 (输入应用编号执行，ID+c取消收藏，q返回): " fav_choice
                        case $fav_choice in
                            q|Q)
                                break
                                ;;
                            *)
                                if [[ "$fav_choice" =~ ^([0-9]+[,，])*[0-9]+c$ || "$fav_choice" =~ ^[0-9]+-[0-9]+c$ ]]; then
                                    # 批量取消收藏
                                    local id_list=${fav_choice%c}  # 移除末尾的c
                                    echo "${CDB}准备删除ID列表: $id_list${NC}"
                                    echo "${CDB}处理后的ID列表:${NC}"
                                    process_id_list "$id_list" | while read -r id; do
                                        echo "${CDB}- $id${NC}"
                                    done
                                    read -p "确认要取消收藏这些应用吗？(y/N): " confirm
                                    if [[ "$confirm" =~ ^[Yy]$ ]]; then
                                        batch_remove_from_favorites "$id_list"
                                        read -p "操作完成，按回车键继续..."
                                    fi
                                elif [[ "$fav_choice" =~ ^[0-9]+$ ]]; then
                                                                    # 获取命令
                                local cmd=$(run_favorite "$fav_choice")
                                local status=$?
                                if [ $status -eq 0 ]; then
                                    echo "${CDB}正在执行命令...${NC}"
                                    if eval "$cmd"; then
                                        echo "${CD}命令执行完成${NC}"
                                    else
                                        echo "${CDR}命令执行失败${NC}"
                                    fi
                                fi
                                read -p "按回车键继续..."
                                else
                                    echo "${CDR}无效选项${NC}"
                                    read -p "按回车键继续..."
                                fi
                                ;;
                        esac
                    done
                    ;;
                l|L)
                    echo "${CDB}当前点赞API: $(get_like_api_url)${NC}"
                    echo "-------------"
                    echo "|<1>设置点赞API地址"
                    echo "|<2>测试当前API连接"
                    echo "|<3>重置为自动生成API地址"
                    echo "-------------"
                    read -p "请选择: " like_choice
                    case $like_choice in
                        1)
                            echo "${CDB}设置点赞API地址${NC}"
                            echo "请输入点赞API的完整URL地址"
                            echo "例如: https://your-domain.com/like_api.php"
                            read -p "请输入API地址: " new_api_url
                            if [ -n "$new_api_url" ]; then
                                save_like_api_url "$new_api_url"
                                echo "${CD}点赞API已设置为: $new_api_url${NC}"
                            fi
                            ;;
                        2)
                            local current_api=$(get_like_api_url)
                            echo "${CDB}正在测试API: $current_api${NC}"
                            echo "${CDB}测试请求: $current_api?action=get&app_id=1${NC}"
                            
                            local test_response=$(curl -s -w "HTTPSTATUS:%{http_code}" "$current_api?action=get&app_id=1" 2>/dev/null)
                            local http_code=$(echo "$test_response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d':' -f2)
                            local response_body=$(echo "$test_response" | sed 's/HTTPSTATUS:[0-9]*$//')
                            
                            if [ -n "$http_code" ] && [ "$http_code" -eq 200 ]; then
                                echo "${CD}API连接测试成功！${NC}"
                                echo "${CDB}HTTP状态码: $http_code${NC}"
                                if [ -n "$response_body" ]; then
                                    echo "${CDB}响应内容: $response_body${NC}"
                                fi
                            else
                                echo "${CDR}API连接测试失败${NC}"
                                echo "${CDB}HTTP状态码: $http_code${NC}"
                                echo "${CDB}响应内容: $response_body${NC}"
                                echo "${CDB}请检查API服务是否正常运行${NC}"
                            fi
                            ;;
                        3)
                            local auto_api_url=$(get_like_api_url)
                            save_like_api_url "$auto_api_url"
                            echo "${CD}已重置为自动生成的API地址: $auto_api_url${NC}"
                            ;;
                        *)
                            echo "${CDR}无效选项${NC}"
                            ;;
                    esac
                    read -p "按回车键继续..."
                    ;;
                q|Q)
                    return
                    ;;
                *)
                    if [[ "$choice" =~ ^([0-9]+[,，])*[0-9]+c$ || "$choice" =~ ^[0-9]+-[0-9]+c$ ]]; then
                        # 批量收藏应用
                        local id_list=${choice%c}  # 移除末尾的c
                        for app_id in $(process_id_list "$id_list"); do
                            if add_to_favorites "$app_id"; then
                                echo "${CD}ID为 $app_id 的应用已添加到收藏夹${NC}"
                            else
                                echo "${CDR}ID为 $app_id 的应用添加失败${NC}"
                            fi
                        done
                        read -p "操作完成，按回车键继续..."
                    elif [[ "$choice" =~ ^([0-9]+[,，])*[0-9]+t$ || "$choice" =~ ^[0-9]+-[0-9]+t$ ]]; then
                        # 批量点赞应用
                        local id_list=${choice%t}  # 移除末尾的t
                        echo "${CDB}准备点赞ID列表: $id_list${NC}"
                        echo "${CDB}处理后的ID列表:${NC}"
                        process_id_list "$id_list" | while read -r id; do
                            echo "${CDB}- $id${NC}"
                        done
                        read -p "确认要为这些应用点赞吗？(y/N): " confirm
                        if [[ "$confirm" =~ ^[Yy]$ ]]; then
                            batch_like_apps "$id_list"
                            read -p "操作完成，按回车键继续..."
                        fi
                    elif [[ "$choice" =~ ^[0-9]+t$ ]]; then
                        # 单个点赞应用
                        local app_id=${choice%t}  # 移除末尾的t
                        like_app "$app_id"
                        read -p "按回车键继续..."
                    elif [[ "$choice" =~ ^[0-9]+$ ]]; then
                        if run_app "$choice"; then
                            read -p "命令执行完成，按回车键继续..."
                        else
                            read -p "命令执行失败，按回车键继续..."
                        fi
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

# 安装 scp 及依赖
install_scp() {
    echo "${CDB}正在检查 scp 及依赖...${NC}"
    
    # 检查 scp 是否已安装
    if command -v scp &> /dev/null; then
        echo "${CD}scp 已经安装。${NC}"
    else
        echo "${CDB}正在安装 scp...${NC}"
        if [ "$OS" == "ubuntu" ] || [ "$OS" == "debian" ]; then
            apt-get update
            apt-get install -y openssh-client
        elif [ "$OS" == "centos" ]; then
            yum install -y openssh-clients
        else
            echo "${CDR}不支持的操作系统，无法安装 scp。${NC}"
            return 1
        fi
        echo "${CD}scp 安装成功。${NC}"
    fi
    
    # 检查 ssh 是否已安装
    if command -v ssh &> /dev/null; then
        echo "${CD}ssh 已经安装。${NC}"
    else
        echo "${CDB}正在安装 ssh...${NC}"
        if [ "$OS" == "ubuntu" ] || [ "$OS" == "debian" ]; then
            apt-get update
            apt-get install -y openssh-client
        elif [ "$OS" == "centos" ]; then
            yum install -y openssh-clients
        else
            echo "${CDR}不支持的操作系统，无法安装 ssh。${NC}"
            return 1
        fi
        echo "${CD}ssh 安装成功。${NC}"
    fi
    
    # 检查 ssh-keygen 是否可用
    if command -v ssh-keygen &> /dev/null; then
        echo "${CD}ssh-keygen 已经可用。${NC}"
    else
        echo "${CDB}正在安装 ssh-keygen...${NC}"
        if [ "$OS" == "ubuntu" ] || [ "$OS" == "debian" ]; then
            apt-get update
            apt-get install -y openssh-client
        elif [ "$OS" == "centos" ]; then
            yum install -y openssh-clients
        else
            echo "${CDR}不支持的操作系统，无法安装 ssh-keygen。${NC}"
            return 1
        fi
        echo "${CD}ssh-keygen 安装成功。${NC}"
    fi
    
    echo "${CD}scp 安装完成。${NC}"
}

# ========== 防火墙管理功能 ==========

# 安装 UFW 防火墙
install_ufw() {
    if command -v ufw &> /dev/null; then
        echo "${CD}ufw 已经安装。${NC}"
    else
        echo "${CDB}正在安装 ufw...${NC}"
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            OS=$ID
        elif [ -f /etc/centos-release ]; then
            OS="centos"
        else
            echo "${CDR}不支持的操作系统。${NC}"
            return 1
        fi

        if [ "$OS" == "ubuntu" ] || [ "$OS" == "debian" ]; then
            apt-get update
            apt-get install -y ufw
        elif [ "$OS" == "centos" ]; then
            yum install -y ufw
        else
            echo "${CDR}不支持的操作系统，无法安装 ufw。${NC}"
            return 1
        fi
        echo "${CD}ufw 安装成功。${NC}"
    fi
}

# 放行指定端口
allow_port() {
    read -p "请输入要放行的端口号（例如 80）：" port
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        echo "${CDR}端口号必须是数字。${NC}"
        return
    fi

    echo "请选择协议："
    echo "1) TCP"
    echo "2) UDP"
    read -p "请输入选项 (1/2): " protocol_choice

    case $protocol_choice in
        1)
            protocol="tcp"
            ;;
        2)
            protocol="udp"
            ;;
        *)
            echo "${CDR}无效的选择。${NC}"
            return
            ;;
    esac

    echo "请选择 IP 版本："
    echo "1) IPv4"
    echo "2) IPv6"
    echo "3) 同时支持 IPv4 和 IPv6"
    read -p "请输入选项 (1/2/3): " ip_version_choice

    case $ip_version_choice in
        1)
            ufw allow "$port"/"$protocol"
            ;;
        2)
            ufw allow "$port"/"$protocol" comment "IPv6"
            ;;
        3)
            ufw allow "$port"/"$protocol"
            ufw allow "$port"/"$protocol" comment "IPv6"
            ;;
        *)
            echo "${CDR}无效的选择。${NC}"
            return
            ;;
    esac

    echo "${CD}端口 $port ($protocol) 已放行。${NC}"
}

# 放行所有端口
allow_all_ports() {
    echo "${CDR}警告：此操作将放行所有协议的所有端口，可能会降低系统安全性！${NC}"
    read -p "是否继续？(y/n): " confirm
    if [ "$confirm" == "y" ] || [ "$confirm" == "Y" ]; then
        ufw allow from any to any
        echo "${CD}所有端口已放行。${NC}"
    else
        echo "${CDB}操作已取消。${NC}"
    fi
}

# 扫描所有开放的端口（简化版）
scan_open_ports() {
    echo "${CDB}正在扫描所有开放的端口...${NC}"
    echo "================================"
    echo "TCP 端口 (IPv4):"
    ss -tln | awk '/^LISTEN/ {print $4}' | grep '0.0.0.0' | awk -F':' '{print $NF}' | sort -n | uniq
    echo "================================"
    echo "TCP 端口 (IPv6):"
    ss -tln | awk '/^LISTEN/ {print $4}' | grep '::' | awk -F':' '{print $NF}' | sort -n | uniq
    echo "================================"
    echo "UDP 端口 (IPv4):"
    ss -uln | awk '/^UNCONN/ {print $4}' | grep '0.0.0.0' | awk -F':' '{print $NF}' | sort -n | uniq
    echo "================================"
    echo "UDP 端口 (IPv6):"
    ss -uln | awk '/^UNCONN/ {print $4}' | grep '::' | awk -F':' '{print $NF}' | sort -n | uniq
    echo "================================"
    echo "${CD}扫描完成。${NC}"
}

# 卸载 UFW
uninstall_ufw() {
    echo "${CDR}警告：此操作将卸载 UFW 防火墙，可能会降低系统安全性！${NC}"
    read -p "是否继续？(y/n): " confirm
    if [ "$confirm" == "y" ] || [ "$confirm" == "Y" ]; then
        if command -v ufw &> /dev/null; then
            echo "${CDB}正在卸载 UFW...${NC}"
            if [ -f /etc/os-release ]; then
                . /etc/os-release
                OS=$ID
            elif [ -f /etc/centos-release ]; then
                OS="centos"
            else
                echo "${CDR}不支持的操作系统。${NC}"
                return 1
            fi

            if [ "$OS" == "ubuntu" ] || [ "$OS" == "debian" ]; then
                apt-get remove --purge -y ufw
            elif [ "$OS" == "centos" ]; then
                yum remove -y ufw
            else
                echo "${CDR}不支持的操作系统，无法卸载 UFW。${NC}"
                return 1
            fi
            echo "${CD}UFW 已卸载。${NC}"
        else
            echo "${CDB}UFW 未安装，无需卸载。${NC}"
        fi
    else
        echo "${CDB}操作已取消。${NC}"
    fi
}

# 防火墙管理菜单
firewall_menu() {
    while true; do
        clear
        echo "===== 防火墙管理 ====="
        echo "|<1>${CD}安装 UFW${NC}"
        echo "|<2>${CDB}放行指定端口${NC}"
        echo "|<3>${CDR}放行所有端口${NC}"
        echo "|<4>${CDB}扫描开放端口${NC}"
        echo "|<5>${CDR}卸载 UFW${NC}"
        echo "-------------"
        echo "|<0>返回主菜单"
        echo "===================="
        
        read -p "请选择: " choice
        case $choice in
            1)
                install_ufw
                read -p "按回车键继续..."
                ;;
            2)
                allow_port
                read -p "按回车键继续..."
                ;;
            3)
                allow_all_ports
                read -p "按回车键继续..."
                ;;
            4)
                scan_open_ports
                read -p "按回车键继续..."
                ;;
            5)
                uninstall_ufw
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

# 软件安装菜单
software_install_menu() {
    while true; do
        clear
        echo "===== 软件安装管理 ====="
        echo "|<1>安装 Curl"
        echo "|<2>安装 Wget"
        echo "|<3>安装 Docker"
        echo "|<4>安装 Git"
        echo "|<5>安装 SCP 及依赖"
        echo "|<6>${CDB}防火墙管理${NC}"
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
            5)
                install_scp
                read -p "按回车键继续..."
                ;;
            6)
                firewall_menu
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
    
    # 获取所有命令列表（和显示时完全一致）
    ls -l /usr/local/bin/ | grep -v "^d" | awk '{print $9}' | grep -v '^$' > "$commands_file"
    
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

# 显示所有自定义命令（带行号和值）
show_system_variables() {
    echo "${CDB}当前自定义命令：${NC}"
    echo "-------------"
    
    # 获取所有命令文件
    local commands=($(ls -l /usr/local/bin/ | grep -v "^d" | awk '{print $9}' | grep -v '^$'))
    local line_num=1
    
    for cmd in "${commands[@]}"; do
        local cmd_path="/usr/local/bin/$cmd"
        
        if [ -f "$cmd_path" ] && [ -r "$cmd_path" ]; then
            # 检查文件类型，只处理文本文件
            local file_type=$(file "$cmd_path" 2>/dev/null)
            if echo "$file_type" | grep -q "text\|script\|shell\|ASCII"; then
                # 尝试读取命令值
                local cmd_value=""
                if head -c 11 "$cmd_path" 2>/dev/null | grep -q "^#!/bin/bash"; then
                    # 如果是bash脚本，跳过第一行读取内容
                    cmd_value=$(tail -n +2 "$cmd_path" 2>/dev/null | head -n 1 | tr -d '\0' | tr -d '\r' 2>/dev/null)
                else
                    # 尝试读取第一行
                    cmd_value=$(head -n 1 "$cmd_path" 2>/dev/null | tr -d '\0' | tr -d '\r' 2>/dev/null)
                fi
                
                # 检查是否包含可打印字符
                if [ -n "$cmd_value" ] && echo "$cmd_value" | grep -q '[[:print:]]'; then
                    echo "$line_num) $cmd = $cmd_value"
                else
                    echo "$line_num) $cmd"
                fi
            else
                # 二进制文件只显示名称
                echo "$line_num) $cmd"
            fi
            ((line_num++))
        else
            echo "$line_num) $cmd"
            ((line_num++))
        fi
    done
    
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

# 获取点赞API URL
get_like_api_url() {
    # 1. 最高优先级：从yysc.conf文件中读取like_api配置
    if [ -f "$CACHE_FILE" ]; then
        local like_api_url=""
        while IFS= read -r line; do
            line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            if [[ "$line" =~ ^like_api=(.*)$ ]]; then
                like_api_url="${BASH_REMATCH[1]}"
                break
            fi
        done < "$CACHE_FILE"
        
        if [ -n "$like_api_url" ]; then
            echo "$like_api_url"
            return 0
        fi
    fi
    
    # 2. 检查是否有独立的点赞API配置文件
    if [ -f "$LIKE_API_URL_FILE" ]; then
        cat "$LIKE_API_URL_FILE"
        return 0
    fi
    
    # 3. 从应用市场Name字段自动生成点赞API地址
        local market_name=""
        if [ -f "$CACHE_FILE" ]; then
            while IFS= read -r line; do
                if [[ "$line" =~ ^Name=(.*)$ ]]; then
                    market_name="${BASH_REMATCH[1]}"
                    break
                fi
            done < "$CACHE_FILE"
        fi
        
        if [ -n "$market_name" ]; then
            # 使用Name字段生成API地址
            echo "https://$market_name/like_api.php"
            return 0
        fi
        
    # 4. 如果无法从Name字段生成，尝试从应用市场URL生成
        local market_url=""
        if [ -f "$MARKET_URL_FILE" ]; then
            market_url=$(cat "$MARKET_URL_FILE")
        fi
        
        if [ -n "$market_url" ]; then
            # 提取域名部分
            local domain=$(echo "$market_url" | sed -E 's|^https?://([^/]+).*|\1|')
            if [ -n "$domain" ]; then
                echo "https://$domain/like_api.php"
                return 0
            fi
        fi
        
    # 5. 如果都无法生成，使用默认地址
        echo "https://api.example.com/like_api.php"
}

# 保存点赞API URL
save_like_api_url() {
    echo "$1" > "$LIKE_API_URL_FILE"
}



# 获取应用点赞数（优化版本）
get_app_likes() {
    local app_id=$1
    local api_url=$(get_like_api_url)
    
    # 添加超时控制，避免长时间等待
    local response=$(curl -s --max-time 5 --connect-timeout 3 -X GET "$api_url?action=get&app_id=$app_id" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$response" ]; then
        # 解析JSON响应 - 支持多种格式
        local likes=$(echo "$response" | grep -o '"likes":[0-9]*' | cut -d':' -f2)
        if [ -z "$likes" ]; then
            # 尝试其他可能的JSON格式
            likes=$(echo "$response" | grep -o '"count":[0-9]*' | cut -d':' -f2)
        fi
        if [ -n "$likes" ]; then
            echo "$likes"
            return 0
        fi
    fi
    
    # 如果API不可用，返回0
    echo "0"
    return 1
}

# 检查是否显示点赞数
should_show_likes() {
    if [ -f "$SHOW_LIKES_FILE" ]; then
        local setting=$(cat "$SHOW_LIKES_FILE")
        if [ "$setting" = "true" ]; then
            return 0
        fi
    fi
    return 1
}

# 更新点赞缓存
update_likes_cache() {
    local app_id=$1
    local likes=$2
    
    # 读取现有缓存
    local cache_data="{}"
    if [ -f "$LIKES_CACHE_FILE" ]; then
        cache_data=$(cat "$LIKES_CACHE_FILE")
    fi
    
    # 更新缓存（简单的JSON操作）
    local timestamp=$(date +%s)
    local new_cache="{\"$app_id\":{\"likes\":\"$likes\",\"timestamp\":\"$timestamp\"}}"
    
    # 合并缓存数据（简化处理）
    echo "$new_cache" > "$LIKES_CACHE_FILE"
}

# 从缓存获取点赞数
get_likes_from_cache() {
    local app_id=$1
    
    if [ -f "$LIKES_CACHE_FILE" ]; then
        local cache_data=$(cat "$LIKES_CACHE_FILE")
        local likes=$(echo "$cache_data" | grep -o "\"$app_id\":{[^}]*}" | grep -o '"likes":"[0-9]*"' | cut -d'"' -f4)
        if [ -n "$likes" ]; then
            echo "$likes"
            return 0
        fi
    fi
    
    echo "0"
    return 1
}

# 计算yysc.conf文件的哈希值
calculate_yysc_hash() {
    local yysc_file="$CACHE_FILE"
    
    if [ ! -f "$yysc_file" ]; then
        echo "${CDR}警告: yysc.conf文件不存在${NC}"
        return 1
    fi
    
    # 使用sha256sum计算哈希值
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$yysc_file" | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$yysc_file" | cut -d' ' -f1
    else
        echo "${CDR}错误: 未找到sha256sum或shasum命令${NC}"
        return 1
    fi
}

# 为应用点赞
like_app() {
    local app_id=$1
    
    local api_url=$(get_like_api_url)
    
    echo "${CDB}正在为应用 $app_id 点赞...${NC}"
    echo "${CDB}API地址: $api_url${NC}"
    
    # 检查API是否可用
    echo "${CDB}正在检查API连接...${NC}"
    local test_response=$(curl -s -w "HTTPSTATUS:%{http_code}" "$api_url?action=get&app_id=1" 2>/dev/null)
    local http_code=$(echo "$test_response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d':' -f2)
    local response_body=$(echo "$test_response" | sed 's/HTTPSTATUS:[0-9]*$//')
    
    if [ -n "$http_code" ] && [ "$http_code" -eq 200 ]; then
        echo "${CD}API连接正常${NC}"
        echo "${CDB}HTTP状态码: $http_code${NC}"
    else
        echo "${CDR}点赞API不可用，请检查API服务是否运行${NC}"
        echo "${CDB}HTTP状态码: $http_code${NC}"
        echo "${CDB}响应内容: $response_body${NC}"
        return 1
    fi
    
    # 计算yysc.conf文件的哈希值
    echo "${CDB}正在计算文件哈希值...${NC}"
    local yysc_hash=$(calculate_yysc_hash)
    if [ $? -ne 0 ]; then
        echo "${CDR}无法计算文件哈希值，点赞失败${NC}"
        return 1
    fi
    
    echo "${CDB}文件哈希值: $yysc_hash${NC}"
    echo "${CDB}缓存文件路径: $CACHE_FILE${NC}"
    
    # 发送POST请求进行点赞
    local timestamp=$(date +%s)
    local user_ip=$(curl -s ifconfig.me 2>/dev/null || echo 'unknown')
    
    echo "${CDB}正在发送点赞请求...${NC}"
    echo "${CDB}请求参数: action=like, app_id=$app_id, timestamp=$timestamp, user_ip=$user_ip${NC}"
    
    local response=$(curl -s --max-time 30 -X POST "$api_url" \
        -d "action=like" \
        -d "app_id=$app_id" \
        -d "timestamp=$timestamp" \
        -d "user_ip=$user_ip" \
        -d "client_hash=$yysc_hash" \
        2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$response" ]; then
        # 调试：显示API响应
        echo "${CDB}API响应: $response${NC}"
        echo "${CDB}响应状态码: $?${NC}"
        
        # 检查是否是错误页面（如504错误）
        if echo "$response" | grep -q "504\|error\|Error\|ERROR"; then
            echo "${CDR}API服务器错误：服务器返回错误页面${NC}"
            echo "${CDB}建议：请检查API服务器状态或联系管理员${NC}"
            return 1
        fi
        
        # 解析JSON响应 - 支持多种格式
        echo "${CDB}正在解析响应...${NC}"
        local success=$(echo "$response" | grep -o '"success":true')
        local message=$(echo "$response" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)
        
        if [ -z "$message" ]; then
            # 尝试其他可能的JSON格式
            message=$(echo "$response" | grep -o '"msg":"[^"]*"' | cut -d'"' -f4)
        fi
        
        if [ -z "$message" ]; then
            # 尝试获取error字段
            message=$(echo "$response" | grep -o '"error":"[^"]*"' | cut -d'"' -f4)
        fi
        
        if [ -n "$success" ]; then
            echo "${CD}点赞成功！${NC}"
            if [ -n "$message" ]; then
                echo "${CDB}$message${NC}"
            fi
            return 0
        else
            echo "${CDB}解析结果: success=$success, message=$message${NC}"
            if [ -n "$message" ]; then
                echo "${CDR}点赞失败：$message${NC}"
            else
                echo "${CDR}点赞失败：服务器返回非JSON格式响应${NC}"
            fi
            # 如果是哈希值验证失败，自动刷新数据并重试
            if echo "$response" | grep -q "哈希值验证失败"; then
                echo "${CDB}检测到哈希值验证失败，正在自动刷新应用市场数据...${NC}"
                if [ -f "$MARKET_URL_FILE" ]; then
                    local market_url=$(cat "$MARKET_URL_FILE")
                    if [ -n "$market_url" ]; then
                        if fetch_app_market "$market_url"; then
                            echo "${CD}应用市场数据已更新，正在重新尝试点赞...${NC}"
                            # 重新计算哈希值并重试点赞
                            local new_hash=$(calculate_yysc_hash)
                            if [ $? -eq 0 ]; then
                                echo "${CDB}新的文件哈希值: $new_hash${NC}"
                                # 重新发送点赞请求
                                local retry_response=$(curl -s -X POST "$api_url" \
                                    -d "action=like" \
                                    -d "app_id=$app_id" \
                                    -d "timestamp=$timestamp" \
                                    -d "user_ip=$user_ip" \
                                    -d "client_hash=$new_hash" \
                                    2>/dev/null)
                                
                                if [ $? -eq 0 ] && [ -n "$retry_response" ]; then
                                    local retry_success=$(echo "$retry_response" | grep -o '"success":true')
                                    local retry_message=$(echo "$retry_response" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)
                                    
                                    if [ -n "$retry_success" ]; then
                                        echo "${CD}重试点赞成功！${NC}"
                                        if [ -n "$retry_message" ]; then
                                            echo "${CDB}$retry_message${NC}"
                                        fi
                                        return 0
                                    else
                                        echo "${CDR}重试点赞失败：$retry_message${NC}"
                                    fi
                                else
                                    echo "${CDR}重试点赞失败：网络错误${NC}"
                                fi
                            else
                                echo "${CDR}无法重新计算哈希值${NC}"
                            fi
                        else
                            echo "${CDR}应用市场数据更新失败${NC}"
                        fi
                    fi
                fi
            fi
            # 如果是应用ID验证失败，提示用户
            if echo "$response" | grep -q "应用ID不存在"; then
                echo "${CDB}建议：请检查应用ID是否正确${NC}"
            fi
            return 1
        fi
    else
        echo "${CDR}网络错误，点赞失败${NC}"
        echo "${CDB}curl退出码: $?${NC}"
        echo "${CDB}请检查API服务地址是否正确：$api_url${NC}"
        return 1
    fi
}

# 批量点赞应用
batch_like_apps() {
    local id_list=$1
    
    local total_count=0
    local success_count=0
    local fail_count=0
    
    # 获取要处理的ID列表
    local ids=($(process_id_list "$id_list"))
    local total=${#ids[@]}
    
    echo "${CDB}开始批量点赞，共 $total 个应用${NC}"
    
    for ((i=0; i<total; i++)); do
        local app_id=${ids[$i]}
        echo "${CDB}正在为应用ID: $app_id 点赞 ($(($i+1))/$total)${NC}"
        
        if like_app "$app_id"; then
            ((success_count++))
        else
            ((fail_count++))
        fi
        
        # 添加延迟以避免过于频繁的请求
        if [ $i -lt $((total-1)) ]; then
            sleep 1
        fi
    done
    
    echo "${CDB}批量点赞完成${NC}"
    echo "${CD}成功: $success_count${NC}"
    echo "${CDR}失败: $fail_count${NC}"
    return 0
}

# 快速使用 scp 命令
quick_scp_menu() {
    while true; do
        clear
        echo "===== 快速 SCP 文件传输 ====="
        echo "|<1>上传文件到远程服务器"
        echo "|<2>从远程服务器下载文件"
        echo "|<3>上传目录到远程服务器"
        echo "|<4>从远程服务器下载目录"
        echo "|<5>自定义 SCP 命令"
        echo "-------------"
        echo "|<0>返回主菜单"
        echo "======================="
        
        read -p "请选择: " choice
        case $choice in
            1)
                upload_file_scp
                ;;
            2)
                download_file_scp
                ;;
            3)
                upload_dir_scp
                ;;
            4)
                download_dir_scp
                ;;
            5)
                custom_scp_command
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

# 上传文件到远程服务器
upload_file_scp() {
    echo "${CDB}上传文件到远程服务器${NC}"
    echo "-------------"
    
    # 检查 scp 是否可用
    if ! command -v scp &> /dev/null; then
        echo "${CDR}scp 未安装，请先安装 SCP 及依赖${NC}"
        read -p "按回车键继续..."
        return 1
    fi
    
    read -p "请输入本地文件路径: " local_file
    if [ ! -f "$local_file" ]; then
        echo "${CDR}本地文件不存在: $local_file${NC}"
        read -p "按回车键继续..."
        return 1
    fi
    
    read -p "请输入远程服务器地址 (格式: user@server): " remote_server
    if [ -z "$remote_server" ]; then
        echo "${CDR}远程服务器地址不能为空${NC}"
        read -p "按回车键继续..."
        return 1
    fi
    
    read -p "请输入远程目标路径: " remote_path
    if [ -z "$remote_path" ]; then
        echo "${CDR}远程目标路径不能为空${NC}"
        read -p "按回车键继续..."
        return 1
    fi
    
    read -p "请输入SSH端口 (默认22): " ssh_port
    ssh_port=${ssh_port:-22}
    
    echo "${CDB}正在上传文件...${NC}"
    echo "${CDB}命令: scp -P $ssh_port \"$local_file\" \"$remote_server:$remote_path\"${NC}"
    
    if scp -P "$ssh_port" "$local_file" "$remote_server:$remote_path"; then
        echo "${CD}文件上传成功！${NC}"
    else
        echo "${CDR}文件上传失败！${NC}"
    fi
    
    read -p "按回车键继续..."
}

# 从远程服务器下载文件
download_file_scp() {
    echo "${CDB}从远程服务器下载文件${NC}"
    echo "-------------"
    
    # 检查 scp 是否可用
    if ! command -v scp &> /dev/null; then
        echo "${CDR}scp 未安装，请先安装 SCP 及依赖${NC}"
        read -p "按回车键继续..."
        return 1
    fi
    
    read -p "请输入远程服务器地址 (格式: user@server): " remote_server
    if [ -z "$remote_server" ]; then
        echo "${CDR}远程服务器地址不能为空${NC}"
        read -p "按回车键继续..."
        return 1
    fi
    
    read -p "请输入远程文件路径: " remote_file
    if [ -z "$remote_file" ]; then
        echo "${CDR}远程文件路径不能为空${NC}"
        read -p "按回车键继续..."
        return 1
    fi
    
    read -p "请输入本地目标路径: " local_path
    if [ -z "$local_path" ]; then
        echo "${CDR}本地目标路径不能为空${NC}"
        read -p "按回车键继续..."
        return 1
    fi
    
    read -p "请输入SSH端口 (默认22): " ssh_port
    ssh_port=${ssh_port:-22}
    
    echo "${CDB}正在下载文件...${NC}"
    echo "${CDB}命令: scp -P $ssh_port \"$remote_server:$remote_file\" \"$local_path\"${NC}"
    
    if scp -P "$ssh_port" "$remote_server:$remote_file" "$local_path"; then
        echo "${CD}文件下载成功！${NC}"
    else
        echo "${CDR}文件下载失败！${NC}"
    fi
    
    read -p "按回车键继续..."
}

# 上传目录到远程服务器
upload_dir_scp() {
    echo "${CDB}上传目录到远程服务器${NC}"
    echo "-------------"
    
    # 检查 scp 是否可用
    if ! command -v scp &> /dev/null; then
        echo "${CDR}scp 未安装，请先安装 SCP 及依赖${NC}"
        read -p "按回车键继续..."
        return 1
    fi
    
    read -p "请输入本地目录路径: " local_dir
    if [ ! -d "$local_dir" ]; then
        echo "${CDR}本地目录不存在: $local_dir${NC}"
        read -p "按回车键继续..."
        return 1
    fi
    
    read -p "请输入远程服务器地址 (格式: user@server): " remote_server
    if [ -z "$remote_server" ]; then
        echo "${CDR}远程服务器地址不能为空${NC}"
        read -p "按回车键继续..."
        return 1
    fi
    
    read -p "请输入远程目标路径: " remote_path
    if [ -z "$remote_path" ]; then
        echo "${CDR}远程目标路径不能为空${NC}"
        read -p "按回车键继续..."
        return 1
    fi
    
    read -p "请输入SSH端口 (默认22): " ssh_port
    ssh_port=${ssh_port:-22}
    
    echo "${CDB}正在上传目录...${NC}"
    echo "${CDB}命令: scp -r -P $ssh_port \"$local_dir\" \"$remote_server:$remote_path\"${NC}"
    
    if scp -r -P "$ssh_port" "$local_dir" "$remote_server:$remote_path"; then
        echo "${CD}目录上传成功！${NC}"
    else
        echo "${CDR}目录上传失败！${NC}"
    fi
    
    read -p "按回车键继续..."
}

# 从远程服务器下载目录
download_dir_scp() {
    echo "${CDB}从远程服务器下载目录${NC}"
    echo "-------------"
    
    # 检查 scp 是否可用
    if ! command -v scp &> /dev/null; then
        echo "${CDR}scp 未安装，请先安装 SCP 及依赖${NC}"
        read -p "按回车键继续..."
        return 1
    fi
    
    read -p "请输入远程服务器地址 (格式: user@server): " remote_server
    if [ -z "$remote_server" ]; then
        echo "${CDR}远程服务器地址不能为空${NC}"
        read -p "按回车键继续..."
        return 1
    fi
    
    read -p "请输入远程目录路径: " remote_dir
    if [ -z "$remote_dir" ]; then
        echo "${CDR}远程目录路径不能为空${NC}"
        read -p "按回车键继续..."
        return 1
    fi
    
    read -p "请输入本地目标路径: " local_path
    if [ -z "$local_path" ]; then
        echo "${CDR}本地目标路径不能为空${NC}"
        read -p "按回车键继续..."
        return 1
    fi
    
    read -p "请输入SSH端口 (默认22): " ssh_port
    ssh_port=${ssh_port:-22}
    
    echo "${CDB}正在下载目录...${NC}"
    echo "${CDB}命令: scp -r -P $ssh_port \"$remote_server:$remote_dir\" \"$local_path\"${NC}"
    
    if scp -r -P "$ssh_port" "$remote_server:$remote_dir" "$local_path"; then
        echo "${CD}目录下载成功！${NC}"
    else
        echo "${CDR}目录下载失败！${NC}"
    fi
    
    read -p "按回车键继续..."
}

# 自定义 SCP 命令
custom_scp_command() {
    echo "${CDB}自定义 SCP 命令${NC}"
    echo "-------------"
    
    # 检查 scp 是否可用
    if ! command -v scp &> /dev/null; then
        echo "${CDR}scp 未安装，请先安装 SCP 及依赖${NC}"
        read -p "按回车键继续..."
        return 1
    fi
    
    echo "${CDB}SCP 命令格式示例：${NC}"
    echo "  scp [选项] 源文件 目标位置"
    echo "  scp -P 2222 -i ~/.ssh/id_rsa file.txt user@server:/path/"
    echo "  scp -r -C directory/ user@server:/path/"
    echo "-------------"
    
    read -p "请输入完整的 SCP 命令: " scp_command
    if [ -z "$scp_command" ]; then
        echo "${CDR}命令不能为空${NC}"
        read -p "按回车键继续..."
        return 1
    fi
    
    echo "${CDB}正在执行命令: $scp_command${NC}"
    
    if eval "$scp_command"; then
        echo "${CD}SCP 命令执行成功！${NC}"
    else
        echo "${CDR}SCP 命令执行失败！${NC}"
    fi
    
    read -p "按回车键继续..."
}

# ========== ACME证书管理功能 ==========

# ACME证书管理相关变量
ACME_DIR="/root/.acme.sh"
ACME_SERVER="https://acme-v02.api.letsencrypt.org/directory"
CERT_DIR="/etc/ssl/certs"
KEY_DIR="/etc/ssl/private"

# 安装acme.sh依赖
install_acme_dependencies() {
    echo "${CDB}正在安装acme.sh依赖...${NC}"
    
    case "$DISTRO" in
        "ubuntu"|"debian")
            apt-get update
            apt-get install -y socat openssl curl
            ;;
        "centos")
            yum install -y socat openssl curl
            ;;
        *)
            echo "${CDR}不支持的操作系统${NC}"
            return 1
            ;;
    esac
    
    echo "${CD}依赖安装完成${NC}"
}

# 安装acme.sh
install_acme() {
    echo "${CDB}正在安装acme.sh...${NC}"
    
    if [ -d "$ACME_DIR" ]; then
        echo "${CD}acme.sh已安装${NC}"
        return 0
    fi
    
    # 要求用户输入真实邮箱
    read -p "请输入您的真实邮箱地址 (用于ACME账户注册): " install_email
    if [ -z "$install_email" ]; then
        echo "${CDR}邮箱地址不能为空${NC}"
        return 1
    fi
    
    # 检查邮箱格式
    if [[ ! "$install_email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        echo "${CDR}邮箱格式不正确${NC}"
        return 1
    fi
    
    # 下载并安装acme.sh
    curl https://get.acme.sh | sh -s email="$install_email"
    
    if [ $? -eq 0 ]; then
        echo "${CD}acme.sh安装成功${NC}"
        # 重新加载环境变量
        source ~/.bashrc
    else
        echo "${CDR}acme.sh安装失败${NC}"
        return 1
    fi
}

# 注册ACME账户
register_acme_account() {
    echo "${CDB}注册ACME账户${NC}"
    
    if [ ! -f "$ACME_DIR/acme.sh" ]; then
        echo "${CDR}请先安装acme.sh${NC}"
        return 1
    fi
    
    read -p "请输入邮箱地址: " email
    if [ -z "$email" ]; then
        echo "${CDR}邮箱地址不能为空${NC}"
        return 1
    fi
    
    # 检查邮箱格式
    if [[ ! "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        echo "${CDR}邮箱格式不正确${NC}"
        return 1
    fi
    
    # 注册账户
    "$ACME_DIR/acme.sh" --register-account -m "$email" --server "$ACME_SERVER"
    
    if [ $? -eq 0 ]; then
        echo "${CD}账户注册成功${NC}"
    else
        echo "${CDR}账户注册失败${NC}"
    fi
}

# 验证域名格式
validate_domain() {
    local domain=$1
    
    # 检查通配符格式
    if [[ "$domain" =~ \* ]]; then
        if [[ ! "$domain" =~ ^\*\. ]]; then
            echo "${CDR}通配符域名格式错误，正确格式为: *.example.com${NC}"
            return 1
        fi
        # 提取通配符后的域名部分
        local domain_part=$(echo "$domain" | sed 's/^\*\.//')
        # 验证域名部分格式
        if [[ ! "$domain_part" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
            echo "${CDR}通配符域名格式不正确: $domain${NC}"
            return 1
        fi
    else
        # 检查普通域名格式
        if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
            echo "${CDR}域名格式不正确: $domain${NC}"
            return 1
        fi
    fi
    
    return 0
}

# HTTP验证申请证书
http_verify_cert() {
    echo "${CDB}使用HTTP-01验证方式申请证书${NC}"
    
    if [ ! -f "$ACME_DIR/acme.sh" ]; then
        echo "${CDR}请先安装acme.sh${NC}"
        return 1
    fi
    
    read -p "请输入域名 (多个域名用空格分隔): " domains
    if [ -z "$domains" ]; then
        echo "${CDR}域名不能为空${NC}"
        return 1
    fi
    
    # 验证每个域名
    for domain in $domains; do
        if ! validate_domain "$domain"; then
            return 1
        fi
    done
    
    read -p "请输入网站根目录 (默认: /var/www/html): " webroot
    webroot=${webroot:-/var/www/html}
    
    # 申请证书
    "$ACME_DIR/acme.sh" --issue -d $domains --webroot "$webroot" --server "$ACME_SERVER" --keylength 2048
    
    if [ $? -eq 0 ]; then
        echo "${CD}证书申请成功${NC}"
        show_cert_content $domains
    else
        echo "${CDR}证书申请失败${NC}"
    fi
}

# DNS验证申请证书
dns_verify_cert() {
    echo "${CDB}使用DNS-01验证方式申请证书${NC}"
    
    if [ ! -f "$ACME_DIR/acme.sh" ]; then
        echo "${CDR}请先安装acme.sh${NC}"
        return 1
    fi
    
    read -p "请输入域名 (多个域名用空格分隔): " domains
    if [ -z "$domains" ]; then
        echo "${CDR}域名不能为空${NC}"
        return 1
    fi
    
    # 验证每个域名
    for domain in $domains; do
        if ! validate_domain "$domain"; then
            return 1
        fi
    done
    
    echo "请选择DNS提供商:"
    echo "1) Cloudflare"
    echo "2) Aliyun"
    echo "3) Tencent Cloud"
    echo "4) 手动添加TXT记录"
    echo "5) 显示TXT记录信息"
    read -p "请选择 (1-5): " dns_provider
    
    case $dns_provider in
        1)
            read -p "请输入Cloudflare API Token: " cf_token
            "$ACME_DIR/acme.sh" --issue --dns dns_cf -d $domains --server "$ACME_SERVER" --keylength 2048
            ;;
        2)
            read -p "请输入Aliyun AccessKey ID: " ali_key
            read -p "请输入Aliyun AccessKey Secret: " ali_secret
            export Ali_Key="$ali_key"
            export Ali_Secret="$ali_secret"
            "$ACME_DIR/acme.sh" --issue --dns dns_ali -d $domains --server "$ACME_SERVER" --keylength 2048
            ;;
        3)
            read -p "请输入腾讯云 SecretId: " tencent_id
            read -p "请输入腾讯云 SecretKey: " tencent_key
            export TENCENTCLOUD_SECRETID="$tencent_id"
            export TENCENTCLOUD_SECRETKEY="$tencent_key"
            "$ACME_DIR/acme.sh" --issue --dns dns_tencent -d $domains --server "$ACME_SERVER" --keylength 2048
            ;;
        4)
            echo "${CDB}手动DNS验证模式${NC}"
            echo ""
            
            # 检查是否已存在证书，如果存在则先删除
            local domain=$(echo $domains | awk '{print $1}')
            if [ -d "$ACME_DIR/$domain" ]; then
                echo "${CDB}检测到已存在证书，正在删除...${NC}"
                "$ACME_DIR/acme.sh" --remove -d $domains --server "$ACME_SERVER" 2>/dev/null
                echo "${CD}旧证书已删除${NC}"
                echo ""
            fi
            
            echo "${CDB}正在获取TXT记录值...${NC}"
            
            # 运行acme.sh获取TXT记录值（强制重新申请）
            local temp_output=$(mktemp)
            "$ACME_DIR/acme.sh" --issue --dns -d $domains --server "$ACME_SERVER" --keylength 2048 --yes-I-know-dns-manual-mode-enough-go-ahead-please --force 2>&1 | tee "$temp_output"
            
            # 提取TXT记录值
            local txt_value=""
            local domain_name=$(echo $domains | awk '{print $1}')
            
            # 尝试多种方式提取TXT记录值
            txt_value=$(grep "TXT value:" "$temp_output" | cut -d"'" -f2)
            if [ -z "$txt_value" ]; then
                txt_value=$(grep "TXT value:" "$temp_output" | sed 's/.*TXT value: //' | tr -d "'")
            fi
            if [ -z "$txt_value" ]; then
                txt_value=$(grep "TXT value:" "$temp_output" | sed 's/.*TXT value: //')
            fi
            if [ -z "$txt_value" ]; then
                txt_value=$(grep "TXT value" "$temp_output" | tail -1 | sed 's/.*TXT value: //')
            fi
            
            # 如果仍然没有找到TXT记录值，显示调试信息
            if [ -z "$txt_value" ]; then
                echo "${CDR}警告：无法提取TXT记录值${NC}"
                echo "${CDB}请检查acme.sh输出中是否包含TXT记录信息${NC}"
                echo ""
                echo "${CDB}调试信息：${NC}"
                grep -i "txt" "$temp_output" || echo "未找到TXT相关信息"
                echo ""
            fi
            
            echo ""
            if [ -n "$txt_value" ]; then
                echo "${CDB}添加以下TXT记录信息：${NC}"
                echo "================================"
                echo "${CD}记录名称: _acme-challenge${NC}"
                echo "${CD}记录类型: TXT${NC}"
                echo "${CD}记录值: $txt_value${NC}"
                echo "${CD}完整域名: _acme-challenge.$domain_name${NC}"
                echo "================================"
            else
                echo "${CDR}未能获取TXT记录值${NC}"
                echo "${CDB}可能的原因：${NC}"
                echo "1. 域名已经被验证过，acme.sh跳过了DNS验证"
                echo "2. 证书申请过程中出现错误"
                echo "3. acme.sh输出格式发生变化"
                echo ""
                echo "${CDB}建议操作：${NC}"
                echo "1. 检查acme.sh的完整输出信息"
                echo "2. 如果证书已成功生成，可以直接使用"
                echo "3. 如需重新验证，请先删除现有证书"
                echo ""
            fi
            echo ""
            echo "${CDB}操作步骤：${NC}"
            echo "1. 登录DNS管理面板"
            echo "2. 添加上述TXT记录"
            echo "3. 等待DNS生效（1-5分钟）"
            echo "4. 使用验证命令检查记录是否生效"
            echo ""
            echo "${CDB}验证命令:${NC}"
            echo "nslookup -type=txt _acme-challenge.$domain_name"
            echo ""
            
            # 清理临时文件
            rm -f "$temp_output"
            
            read -p "DNS记录添加并生效后，按回车继续..."
            
            # 继续验证并生成证书
            echo "${CDB}正在验证DNS记录并生成证书...${NC}"
            "$ACME_DIR/acme.sh" --renew -d $domains --server "$ACME_SERVER" --yes-I-know-dns-manual-mode-enough-go-ahead-please --force
            
            if [ $? -eq 0 ]; then
                echo "${CD}证书申请成功${NC}"
                show_cert_content $domains
                return 0
            else
                echo "${CDR}证书申请失败${NC}"
                return 1
            fi
            ;;
        5)
            show_dns_txt_info $domains
            return 0
            ;;
        *)
            echo "${CDR}无效选择${NC}"
            return 1
            ;;
    esac
    
    # 对于自动DNS验证方式，在这里显示证书内容
    if [ $? -eq 0 ]; then
        echo "${CD}证书申请成功${NC}"
        show_cert_content $domains
    else
        echo "${CDR}证书申请失败${NC}"
    fi
}

# 显示证书内容（不安装）
show_cert_content() {
    local domains=$1
    local domain=$(echo $domains | awk '{print $1}')
    
    echo "${CDB}正在获取证书内容...${NC}"
    
    # 获取acme.sh中的证书文件路径
    local cert_file="$ACME_DIR/$domain/$domain.cer"
    local key_file="$ACME_DIR/$domain/$domain.key"
    local fullchain_file="$ACME_DIR/$domain/fullchain.cer"
    
    echo ""
    echo "${CDB}================================${NC}"
    echo "${CDB}        PEM格式内容${NC}"
    echo "${CDB}================================${NC}"
    echo ""
    
    # 显示私钥
    echo "${CD}私钥内容 (Private Key):${NC}"
    echo "================================"
    if [ -f "$key_file" ]; then
        cat "$key_file"
    else
        echo "${CDR}私钥文件不存在: $key_file${NC}"
    fi
    echo "================================"
    echo ""
    
    # 显示证书
    echo "${CD}证书内容 (Certificate):${NC}"
    echo "================================"
    if [ -f "$cert_file" ]; then
        cat "$cert_file"
    else
        echo "${CDR}证书文件不存在: $cert_file${NC}"
    fi
    echo "================================"
    echo ""
    
    # 显示完整链证书
    echo "${CD}完整链证书 (Full Chain):${NC}"
    echo "================================"
    if [ -f "$fullchain_file" ]; then
        cat "$fullchain_file"
    else
        echo "${CDR}完整链证书文件不存在: $fullchain_file${NC}"
    fi
    echo "================================"
    echo ""
    
    echo "${CDB}注意：请妥善保管私钥文件，不要泄露给他人${NC}"
    echo "${CDB}证书文件位置:${NC}"
    echo -e "  证书: $cert_file"
    echo -e "  私钥: $key_file"
    echo -e "  完整链: $fullchain_file"
    echo ""
}

# 续期证书
renew_cert() {
    echo "${CDB}续期证书${NC}"
    
    read -p "请输入域名: " domain
    if [ -z "$domain" ]; then
        echo "${CDR}域名不能为空${NC}"
        return 1
    fi
    
    # 检查证书是否存在
    if [ ! -d "$ACME_DIR/$domain" ]; then
        echo "${CDR}未找到域名 $domain 的证书${NC}"
        return 1
    fi
    
    # 检查是否使用DNS手动模式
    local config_file="$ACME_DIR/$domain/$domain.conf"
    local is_dns_manual=false
    
    # 检查配置文件中的DNS手动模式标记
    if [ -f "$config_file" ]; then
        if grep -q "Le_DNS_Manual" "$config_file" || grep -q "dns_manual" "$config_file"; then
            is_dns_manual=true
        fi
    fi
    
    # 如果配置文件不存在或没有标记，检查acme.sh的输出
    if [ "$is_dns_manual" = false ]; then
        echo "${CDB}正在检查证书验证模式...${NC}"
        local temp_check=$(mktemp)
        "$ACME_DIR/acme.sh" --renew -d "$domain" --force 2>&1 | head -10 > "$temp_check"
        if grep -q "dns manual mode" "$temp_check" || grep -q "DNS manual mode" "$temp_check"; then
            is_dns_manual=true
        fi
        rm -f "$temp_check"
    fi
    
    if [ "$is_dns_manual" = true ]; then
        echo "${CDB}检测到DNS手动模式，需要重新进行DNS验证${NC}"
        echo ""
        echo "请选择续期方式："
        echo "1) 自动续期（如果DNS记录仍然有效）"
        echo "2) 手动DNS验证续期"
        read -p "请选择 (1-2): " renew_method
        
        case $renew_method in
            1)
                echo "${CDB}尝试自动续期...${NC}"
                local temp_output=$(mktemp)
                "$ACME_DIR/acme.sh" --renew -d "$domain" --force 2>&1 | tee "$temp_output"
                local auto_result=$?
                
                # 检查是否遇到DNS手动模式错误
                if [ $auto_result -ne 0 ] && (grep -q "dns manual mode" "$temp_output" || grep -q "DNS manual mode" "$temp_output"); then
                    echo ""
                    echo "${CDB}检测到DNS手动模式，自动切换到手动验证模式${NC}"
                    echo ""
                    echo "${CDB}正在获取新的TXT记录值...${NC}"
                    
                    # 重新运行获取TXT记录
                    rm -f "$temp_output"
                    local temp_output=$(mktemp)
                    "$ACME_DIR/acme.sh" --renew -d "$domain" --yes-I-know-dns-manual-mode-enough-go-ahead-please --force 2>&1 | tee "$temp_output"
                    
                    # 检查是否遇到速率限制
                    if grep -q "rateLimited" "$temp_output" || grep -q "too many certificates" "$temp_output"; then
                        echo ""
                        echo "${CDR}遇到Let's Encrypt速率限制${NC}"
                        echo "${CDB}错误详情：${NC}"
                        grep -A 5 -B 5 "rateLimited\|too many certificates" "$temp_output"
                        echo ""
                        echo "${CDB}解决方案：${NC}"
                        echo "1. Let's Encrypt限制每个域名在168小时内最多申请5个证书"
                        echo "2. 请等待限制时间过后再尝试续期"
                        echo "3. 或者删除现有证书后重新申请"
                        echo ""
                        echo "${CDB}建议操作：${NC}"
                        echo "- 使用选项8删除现有证书"
                        echo "- 等待限制时间过后重新申请"
                        renew_result=1
                    else
                        # 提取TXT记录值
                        local txt_value=""
                        txt_value=$(grep "TXT value:" "$temp_output" | cut -d"'" -f2)
                        if [ -z "$txt_value" ]; then
                            txt_value=$(grep "TXT value:" "$temp_output" | sed 's/.*TXT value: //' | tr -d "'")
                        fi
                        if [ -z "$txt_value" ]; then
                            txt_value=$(grep "TXT value:" "$temp_output" | sed 's/.*TXT value: //')
                        fi
                        
                        echo ""
                        if [ -n "$txt_value" ]; then
                            echo "${CDB}请更新以下TXT记录：${NC}"
                            echo "================================"
                            echo "${CD}记录名称: _acme-challenge${NC}"
                            echo "${CD}记录类型: TXT${NC}"
                            echo "${CD}记录值: $txt_value${NC}"
                            echo "${CD}完整域名: _acme-challenge.$domain${NC}"
                            echo "================================"
                            echo ""
                            echo "${CDB}操作步骤：${NC}"
                            echo "1. 登录DNS管理面板"
                            echo "2. 找到域名 $domain 的DNS设置"
                            echo "3. 更新 _acme-challenge 的TXT记录值为上述值"
                            echo "4. 等待DNS生效（1-5分钟）"
                            echo "5. 按回车键继续验证..."
                            read -p ""
                            
                            # 继续验证
                            echo "${CDB}正在验证DNS记录...${NC}"
                            "$ACME_DIR/acme.sh" --renew -d "$domain" --yes-I-know-dns-manual-mode-enough-go-ahead-please --force
                            renew_result=$?
                        else
                            echo "${CDR}未能获取TXT记录值${NC}"
                            echo "${CDB}调试信息：${NC}"
                            grep -i "txt" "$temp_output" || echo "未找到TXT相关信息"
                            renew_result=1
                        fi
                    fi
                    
                    rm -f "$temp_output"
                else
                    renew_result=$auto_result
                    rm -f "$temp_output"
                fi
                ;;
            2)
                echo "${CDB}手动DNS验证续期${NC}"
                echo ""
                echo "${CDB}正在获取新的TXT记录值...${NC}"
                
                # 运行acme.sh获取新的TXT记录值
                local temp_output=$(mktemp)
                "$ACME_DIR/acme.sh" --renew -d "$domain" --yes-I-know-dns-manual-mode-enough-go-ahead-please --force 2>&1 | tee "$temp_output"
                
                # 检查是否遇到速率限制
                if grep -q "rateLimited" "$temp_output" || grep -q "too many certificates" "$temp_output"; then
                    echo ""
                    echo "${CDR}遇到Let's Encrypt速率限制${NC}"
                    echo "${CDB}错误详情：${NC}"
                    grep -A 5 -B 5 "rateLimited\|too many certificates" "$temp_output"
                    echo ""
                    echo "${CDB}解决方案：${NC}"
                    echo "1. Let's Encrypt限制每个域名在168小时内最多申请5个证书"
                    echo "2. 请等待限制时间过后再尝试续期"
                    echo "3. 或者删除现有证书后重新申请"
                    echo ""
                    echo "${CDB}建议操作：${NC}"
                    echo "- 使用选项8删除现有证书"
                    echo "- 等待限制时间过后重新申请"
                    renew_result=1
                else
                    # 提取TXT记录值
                    local txt_value=""
                    txt_value=$(grep "TXT value:" "$temp_output" | cut -d"'" -f2)
                    if [ -z "$txt_value" ]; then
                        txt_value=$(grep "TXT value:" "$temp_output" | sed 's/.*TXT value: //' | tr -d "'")
                    fi
                    if [ -z "$txt_value" ]; then
                        txt_value=$(grep "TXT value:" "$temp_output" | sed 's/.*TXT value: //')
                    fi
                    
                    echo ""
                    if [ -n "$txt_value" ]; then
                        echo "${CDB}请更新以下TXT记录：${NC}"
                        echo "================================"
                        echo "${CD}记录名称: _acme-challenge${NC}"
                        echo "${CD}记录类型: TXT${NC}"
                        echo "${CD}记录值: $txt_value${NC}"
                        echo "${CD}完整域名: _acme-challenge.$domain${NC}"
                        echo "================================"
                        echo ""
                        echo "${CDB}操作步骤：${NC}"
                        echo "1. 登录DNS管理面板"
                        echo "2. 找到域名 $domain 的DNS设置"
                        echo "3. 更新 _acme-challenge 的TXT记录值为上述值"
                        echo "4. 等待DNS生效（1-5分钟）"
                        echo "5. 按回车键继续验证..."
                        read -p ""
                        
                        # 继续验证
                        echo "${CDB}正在验证DNS记录...${NC}"
                        "$ACME_DIR/acme.sh" --renew -d "$domain" --yes-I-know-dns-manual-mode-enough-go-ahead-please --force
                        renew_result=$?
                    else
                        echo "${CDR}未能获取TXT记录值${NC}"
                        echo "${CDB}调试信息：${NC}"
                        grep -i "txt" "$temp_output" || echo "未找到TXT相关信息"
                        renew_result=1
                    fi
                fi
                
                rm -f "$temp_output"
                ;;
            *)
                echo "${CDR}无效选择${NC}"
                return 1
                ;;
        esac
    else
        # 普通续期
        echo "${CDB}尝试普通续期...${NC}"
        local temp_output=$(mktemp)
        "$ACME_DIR/acme.sh" --renew -d "$domain" --force 2>&1 | tee "$temp_output"
        local renew_result=$?
        
        # 检查是否遇到速率限制
        if grep -q "rateLimited" "$temp_output" || grep -q "too many certificates" "$temp_output"; then
            echo ""
            echo "${CDR}遇到Let's Encrypt速率限制${NC}"
            echo "${CDB}错误详情：${NC}"
            grep -A 5 -B 5 "rateLimited\|too many certificates" "$temp_output"
            echo ""
            echo "${CDB}解决方案：${NC}"
            echo "1. Let's Encrypt限制每个域名在168小时内最多申请5个证书"
            echo "2. 请等待限制时间过后再尝试续期"
            echo "3. 或者删除现有证书后重新申请"
            echo ""
            echo "${CDB}建议操作：${NC}"
            echo "- 使用选项8删除现有证书"
            echo "- 等待限制时间过后重新申请"
            renew_result=1
        # 检查是否遇到DNS手动模式错误
        elif [ $renew_result -ne 0 ] && (grep -q "dns manual mode" "$temp_output" || grep -q "DNS manual mode" "$temp_output"); then
            echo ""
            echo "${CDB}检测到DNS手动模式，需要手动验证${NC}"
            echo "请选择操作："
            echo "1) 使用DNS手动模式续期"
            echo "2) 取消续期"
            read -p "请选择 (1-2): " manual_choice
            
            case $manual_choice in
                1)
                    echo "${CDB}使用DNS手动模式续期${NC}"
                    echo ""
                    echo "${CDB}正在获取新的TXT记录值...${NC}"
                    
                    # 重新运行获取TXT记录
                    rm -f "$temp_output"
                    local temp_output=$(mktemp)
                    "$ACME_DIR/acme.sh" --renew -d "$domain" --yes-I-know-dns-manual-mode-enough-go-ahead-please --force 2>&1 | tee "$temp_output"
                    
                    # 检查是否遇到速率限制
                    if grep -q "rateLimited" "$temp_output" || grep -q "too many certificates" "$temp_output"; then
                        echo ""
                        echo "${CDR}遇到Let's Encrypt速率限制${NC}"
                        echo "${CDB}错误详情：${NC}"
                        grep -A 5 -B 5 "rateLimited\|too many certificates" "$temp_output"
                        echo ""
                        echo "${CDB}解决方案：${NC}"
                        echo "1. Let's Encrypt限制每个域名在168小时内最多申请5个证书"
                        echo "2. 请等待限制时间过后再尝试续期"
                        echo "3. 或者删除现有证书后重新申请"
                        echo ""
                        echo "${CDB}建议操作：${NC}"
                        echo "- 使用选项8删除现有证书"
                        echo "- 等待限制时间过后重新申请"
                        renew_result=1
                    else
                        # 提取TXT记录值
                        local txt_value=""
                        txt_value=$(grep "TXT value:" "$temp_output" | cut -d"'" -f2)
                        if [ -z "$txt_value" ]; then
                            txt_value=$(grep "TXT value:" "$temp_output" | sed 's/.*TXT value: //' | tr -d "'")
                        fi
                        if [ -z "$txt_value" ]; then
                            txt_value=$(grep "TXT value:" "$temp_output" | sed 's/.*TXT value: //')
                        fi
                        
                        echo ""
                        if [ -n "$txt_value" ]; then
                            echo "${CDB}请更新以下TXT记录：${NC}"
                            echo "================================"
                            echo "${CD}记录名称: _acme-challenge${NC}"
                            echo "${CD}记录类型: TXT${NC}"
                            echo "${CD}记录值: $txt_value${NC}"
                            echo "${CD}完整域名: _acme-challenge.$domain${NC}"
                            echo "================================"
                            echo ""
                            echo "${CDB}操作步骤：${NC}"
                            echo "1. 登录DNS管理面板"
                            echo "2. 找到域名 $domain 的DNS设置"
                            echo "3. 更新 _acme-challenge 的TXT记录值为上述值"
                            echo "4. 等待DNS生效（1-5分钟）"
                            echo "5. 按回车键继续验证..."
                            read -p ""
                            
                            # 继续验证
                            echo "${CDB}正在验证DNS记录...${NC}"
                            "$ACME_DIR/acme.sh" --renew -d "$domain" --yes-I-know-dns-manual-mode-enough-go-ahead-please --force
                            renew_result=$?
                        else
                            echo "${CDR}未能获取TXT记录值${NC}"
                            echo "${CDB}调试信息：${NC}"
                            grep -i "txt" "$temp_output" || echo "未找到TXT相关信息"
                            renew_result=1
                        fi
                    fi
                    ;;
                2)
                    echo "${CDB}续期已取消${NC}"
                    renew_result=0
                    ;;
                *)
                    echo "${CDR}无效选择${NC}"
                    renew_result=1
                    ;;
            esac
        fi
        
        rm -f "$temp_output"
    fi
    
    # 确保renew_result变量有值
    if [ -z "$renew_result" ]; then
        renew_result=1
    fi
    
    if [ "$renew_result" -eq 0 ]; then
        echo "${CD}证书续期成功${NC}"
        echo ""
        echo "${CDB}续期后的证书信息：${NC}"
        show_cert_content "$domain"
    else
        echo "${CDR}证书续期失败${NC}"
    fi
}

# 查看证书列表
list_certs() {
    echo "${CDB}证书列表:${NC}"
    "$ACME_DIR/acme.sh" --list
    
    echo ""
    echo "${CDB}证书详细信息:${NC}"
    echo "================================"
    
    # 遍历所有证书目录
    for cert_dir in "$ACME_DIR"/*/; do
        if [ -d "$cert_dir" ]; then
            local domain=$(basename "$cert_dir")
            local cert_file="$cert_dir/$domain.cer"
            
            if [ -f "$cert_file" ]; then
                echo "${CD}域名: $domain${NC}"
                
                # 获取证书到期时间
                local expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2)
                if [ -n "$expiry_date" ]; then
                    echo "到期时间: $expiry_date"
                    
                    # 计算剩余天数
                    local expiry_timestamp=$(date -d "$expiry_date" +%s 2>/dev/null)
                    local current_timestamp=$(date +%s)
                    if [ -n "$expiry_timestamp" ] && [ -n "$current_timestamp" ]; then
                        local days_left=$(( (expiry_timestamp - current_timestamp) / 86400 ))
                        if [ $days_left -gt 0 ]; then
                            echo "剩余天数: $days_left 天"
                            if [ $days_left -lt 30 ]; then
                                echo "${CDR}警告：证书即将到期，建议续期${NC}"
                            fi
                        else
                            echo "${CDR}证书已过期${NC}"
                        fi
                    fi
                fi
                echo "----------------"
            fi
        fi
    done
}

# 删除证书
remove_cert() {
    echo "${CDB}删除证书${NC}"
    
    read -p "请输入域名: " domain
    if [ -z "$domain" ]; then
        echo "${CDR}域名不能为空${NC}"
        return 1
    fi
    
    read -p "确认删除证书 $domain? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "${CDB}操作已取消${NC}"
        return 0
    fi
    
    "$ACME_DIR/acme.sh" --remove -d "$domain"
    
    if [ $? -eq 0 ]; then
        echo "${CD}证书删除成功${NC}"
    else
        echo "${CDR}证书删除失败${NC}"
    fi
}

# 设置自动续期
setup_auto_renew() {
    echo "${CDB}设置自动续期${NC}"
    
    # 创建续期脚本
    cat > /etc/cron.daily/renew-ssl << EOF
#!/bin/bash
$ACME_DIR/acme.sh --cron --home $ACME_DIR
EOF
    
    chmod +x /etc/cron.daily/renew-ssl
    
    echo "${CD}自动续期已设置，每天凌晨2点执行${NC}"
}

# 显示DNS TXT记录信息
show_dns_txt_info() {
    local domains=$1
    echo "${CDB}DNS TXT记录添加指南${NC}"
    echo "================================"
    echo "${CDB}对于域名: $domains${NC}"
    echo ""
    echo "${CD}需要添加的TXT记录：${NC}"
    echo "记录名称: _acme-challenge"
    echo "记录类型: TXT"
    echo "记录值: 需要从acme.sh获取"
    echo ""
    echo "${CDB}添加步骤：${NC}"
    echo "1. 登录您的DNS管理面板"
    echo "2. 找到域名 $domains 的DNS设置"
    echo "3. 添加新的TXT记录"
    echo "4. 记录名称填写: _acme-challenge"
    echo "5. 记录类型选择: TXT"
    echo "6. 记录值将在acme.sh运行时显示"
    echo ""
    echo "${CDB}注意事项：${NC}"
    echo "- 添加记录后需要等待几分钟让DNS生效"
    echo "- 可以使用 nslookup 或 dig 命令验证记录是否生效"
    echo "- 验证命令: nslookup -type=txt _acme-challenge.$domains"
    echo ""
    read -p "按回车返回..."
}

# 测试证书
test_cert() {
    echo "${CDB}测试证书${NC}"
    
    read -p "请输入域名: " domain
    if [ -z "$domain" ]; then
        echo "${CDR}域名不能为空${NC}"
        return 1
    fi
    
    local cert_file="$ACME_DIR/$domain/$domain.cer"
    if [ -f "$cert_file" ]; then
        echo "${CD}证书文件存在${NC}"
        openssl x509 -in "$cert_file" -text -noout | head -20
    else
        echo "${CDR}证书文件不存在${NC}"
    fi
}

# 修复邮箱配置
fix_email() {
    echo "${CDB}修复邮箱配置${NC}"
    
    if [ ! -f "$ACME_DIR/account.conf" ]; then
        echo "${CDR}未找到账户配置文件${NC}"
        return 1
    fi
    
    echo "${CDB}当前账户配置:${NC}"
    cat "$ACME_DIR/account.conf"
    echo ""
    
    read -p "请输入新的邮箱地址: " new_email
    if [ -z "$new_email" ]; then
        echo "${CDR}邮箱地址不能为空${NC}"
        return 1
    fi
    
    # 备份原配置
    cp "$ACME_DIR/account.conf" "$ACME_DIR/account.conf.backup"
    
    # 更新邮箱
    sed -i "s/ACCOUNT_EMAIL=.*/ACCOUNT_EMAIL='$new_email'/" "$ACME_DIR/account.conf"
    
    echo "${CD}邮箱已更新为: $new_email${NC}"
    echo "${CDB}现在可以尝试重新注册账户${NC}"
}

# 清理配置
clean_config() {
    echo "${CDB}清理acme.sh配置${NC}"
    echo "${CDR}警告：此操作将删除所有acme.sh配置和证书${NC}"
    read -p "确认清理？(y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "${CDB}操作已取消${NC}"
        return 0
    fi
    
    # 停止acme.sh服务
    if [ -f "$ACME_DIR/acme.sh" ]; then
        "$ACME_DIR/acme.sh" --uninstall 2>/dev/null
    fi
    
    # 删除acme.sh目录
    rm -rf "$ACME_DIR"
    
    # 删除cron任务
    crontab -l 2>/dev/null | grep -v "acme.sh" | crontab -
    
    echo "${CD}配置清理完成${NC}"
    echo "${CDB}现在可以重新安装acme.sh${NC}"
}

# ACME证书管理菜单
acme_cert_menu() {
    while true; do
        clear
        echo "==================================="
        echo "      ACME 证书申请管理"
        echo "————————————————————————————————————"
        echo "|0| 退出脚本     |"
        echo "----------------"
        echo "|1| 安装依赖     |"
        echo "----------------"
        echo "|2| 安装 acme.sh |"
        echo "----------------"
        echo "|3| 注册账户     |"
        echo "----------------"
        echo "|4| HTTP验证申请 |"
        echo "----------------"
        echo "|5| DNS验证申请  |"
        echo "----------------"
        echo "|6| 续期证书     |"
        echo "----------------"
        echo "|7| 查看证书列表 |"
        echo "----------------"
        echo "|8| 删除证书     |"
        echo "----------------"
        echo "|9| 设置自动续期 |"
        echo "----------------"
        echo "|10| 测试证书    |"
        echo "----------------"
        echo "|11| 清理配置    |"
        echo "----------------"
        echo "|12| 修复邮箱    |"
        echo "==================================="
        
        read -p "请输入您的选择 (0-12): " choice
        case $choice in
            0)
                return
                ;;
            1)
                install_acme_dependencies
                read -p "按回车键继续..."
                ;;
            2)
                install_acme
                read -p "按回车键继续..."
                ;;
            3)
                register_acme_account
                read -p "按回车键继续..."
                ;;
            4)
                http_verify_cert
                read -p "按回车键继续..."
                ;;
            5)
                dns_verify_cert
                read -p "按回车键继续..."
                ;;
            6)
                renew_cert
                read -p "按回车键继续..."
                ;;
            7)
                list_certs
                read -p "按回车键继续..."
                ;;
            8)
                remove_cert
                read -p "按回车键继续..."
                ;;
            9)
                setup_auto_renew
                read -p "按回车键继续..."
                ;;
            10)
                test_cert
                read -p "按回车键继续..."
                ;;
            11)
                clean_config
                read -p "按回车键继续..."
                ;;
            12)
                fix_email
                read -p "按回车键继续..."
                ;;
            *)
                echo "${CDR}无效选项${NC}"
                read -p "按回车键继续..."
                ;;
        esac
    done
}

# 检查并自动安装压缩/解压依赖
check_compress_deps() {
    local need_install=""
    for cmd in zip unzip rar unrar 7z tar; do
        if ! command -v $cmd >/dev/null 2>&1; then
            need_install="$need_install $cmd"
        fi
    done
    if [ -n "$need_install" ]; then
        echo "检测到缺少以下依赖:$need_install，正在自动安装..."
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update
            apt-get install -y zip unzip p7zip-full p7zip-rar rar unrar tar
        elif command -v yum >/dev/null 2>&1; then
            yum install -y zip unzip p7zip p7zip-plugins rar unrar tar
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y zip unzip p7zip p7zip-plugins rar unrar tar
        else
            echo "不支持的包管理器，请手动安装: $need_install"
            return 1
        fi
    fi
}

compress_menu() {
    check_compress_deps || return
    while true; do
        clear
        echo "===== 压缩/解压管理 ====="
        echo "|<1>压缩文件/文件夹"
        echo "|<2>解压文件"
        echo "-------------"
        echo "|<0>返回主菜单"
        echo "======================="
        read -p "请选择: " choice
        case $choice in
            1)
                read -p "请输入要压缩的文件或文件夹路径: " src_path
                read -p "请输入压缩包保存路径（含文件名及后缀，如 /root/test.zip）: " dst_path
                echo "===== 请选择压缩格式 ====="
                echo "|<1> zip"
                echo "|<2> rar"
                echo "|<3> 7z"
                echo "|<4> tgz"
                echo "|<5> tar.gz"
                echo "|<6> xz"
                echo "|<7> tar.xz"
                echo "-------------"
                echo "|<0>返回上级菜单"
                echo "======================="
                read -p "请输入序号: " fmt_num
                case $fmt_num in
                    1) fmt="zip";;
                    2) fmt="rar";;
                    3) fmt="7z";;
                    4) fmt="tgz";;
                    5) fmt="tar.gz";;
                    6) fmt="xz";;
                    7) fmt="tar.xz";;
                    0) continue;;
                    *) echo "无效格式，已取消。"; read -p "按回车键继续..."; continue;;
                esac
                read -p "是否设置密码？(y/n): " setpwd
                if [[ $setpwd == y* || $setpwd == Y* ]]; then
                    read -s -p "请输入密码: " pwd
                    echo
                    if [[ $fmt == 7z ]]; then
                        read -p "是否加密文件名？(y/n): " encname
                    fi
                else
                    pwd=""
                    encname="n"
                fi
                parent_dir=$(dirname "$src_path")
                base_name=$(basename "$src_path")
                case $fmt in
                    zip)
                        if [[ -n $pwd ]]; then
                            (cd "$parent_dir" && zip -r -P "$pwd" "$dst_path" "$base_name")
                        else
                            (cd "$parent_dir" && zip -r "$dst_path" "$base_name")
                        fi
                        ;;
                    rar)
                        if [[ -n $pwd ]]; then
                            (cd "$parent_dir" && rar a -hp"$pwd" "$dst_path" "$base_name")
                        else
                            (cd "$parent_dir" && rar a "$dst_path" "$base_name")
                        fi
                        ;;
                    7z)
                        if [[ -n $pwd ]]; then
                            if [[ $encname == y* || $encname == Y* ]]; then
                                (cd "$parent_dir" && 7z a -p"$pwd" -mhe=on "$dst_path" "$base_name")
                            else
                                (cd "$parent_dir" && 7z a -p"$pwd" "$dst_path" "$base_name")
                            fi
                        else
                            (cd "$parent_dir" && 7z a "$dst_path" "$base_name")
                        fi
                        ;;
                    tgz|tar.gz)
                        if [[ -n $pwd ]]; then
                            echo "tar/tgz 格式不直接支持密码，建议用7z/zip/rar。"
                            read -p "按回车键继续..."
                        else
                            (cd "$parent_dir" && tar czvf "$dst_path" "$base_name")
                        fi
                        ;;
                    xz|tar.xz)
                        echo "提示：xz/tar.xz 格式建议用于文件夹或多个文件，否则在Windows等系统解压后可能只有一个无后缀文件。"
                        if [[ -n $pwd ]]; then
                            echo "xz/tar.xz 格式不支持密码，建议用7z/zip/rar。"
                            read -p "按回车键继续..."
                        else
                            if [ -f "$src_path" ]; then
                                echo "警告：你正在压缩单个文件，解压后可能没有原始文件名和后缀。"
                                read -p "按回车键继续..."
                            fi
                            (cd "$parent_dir" && tar cJvf "$dst_path" "$base_name")
                        fi
                        ;;
                    *)
                        echo "不支持的格式！"
                        ;;
                esac
                read -p "操作完成，按回车键继续..."
                ;;
            2)
                read -p "请输入要解压的文件路径: " src_path
                read -p "请输入解压到的目标文件夹路径: " dst_path
                echo "===== 自动识别压缩包格式 ====="
                echo "-------------"
                echo "|<0>返回主菜单"
                echo "======================="
                # 自动识别格式 
                ext=$(echo "$src_path" | awk -F. '{print tolower($(NF-1)) "." tolower($NF)}')
                ext2=$(echo "$src_path" | awk -F. '{print tolower($NF)}')
                if [[ $ext == ".tar.gz" || $ext == ".tar.xz" || $ext == ".tar.bz2" ]]; then
                    fmt=$ext
                else
                    fmt=$ext2
                fi
                case $fmt in
                    zip)
                        read -p "是否有密码？(y/n): " haspwd
                        if [[ $haspwd == y* || $haspwd == Y* ]]; then
                            read -s -p "请输入密码: " pwd
                            echo
                            unzip -P "$pwd" "$src_path" -d "$dst_path"
                        else
                            unzip "$src_path" -d "$dst_path"
                        fi
                        ;;
                    rar)
                        read -p "是否有密码？(y/n): " haspwd
                        if [[ $haspwd == y* || $haspwd == Y* ]]; then
                            read -s -p "请输入密码: " pwd
                            echo
                            unrar x -p"$pwd" "$src_path" "$dst_path"
                        else
                            unrar x "$src_path" "$dst_path"
                        fi
                        ;;
                    7z)
                        read -p "是否有密码？(y/n): " haspwd
                        if [[ $haspwd == y* || $haspwd == Y* ]]; then
                            read -s -p "请输入密码: " pwd
                            echo
                            7z x -p"$pwd" "$src_path" -o"$dst_path"
                        else
                            7z x "$src_path" -o"$dst_path"
                        fi
                        ;;
                    tgz|tar.gz)
                        tar xzvf "$src_path" -C "$dst_path"
                        ;;
                    xz|tar.xz)
                        tar xJvf "$src_path" -C "$dst_path"
                        ;;
                    bz2|tar.bz2)
                        tar xjvf "$src_path" -C "$dst_path"
                        ;;
                    *)
                        echo "无法识别的压缩格式：$fmt"
                        ;;
                esac
                read -p "操作完成，按回车键继续..."
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

# 在主菜单函数开始时添加变量包加载
main_menu() {
    while true; do
        # 检查并安装 vpsmanager 命令
        if [ ! -f "/usr/local/bin/vpsmanager" ]; then
            install_command_alias
        fi
        
        clear
        echo "================================"
        echo "       VPS Manager v1.3.0"
        echo "================================"
        echo "|<1>${CD}系统检测${NC}"
        echo "|<2>${CD}软件源管理${NC}"
        echo "|<3>${CD}软件安装${NC}"
        echo "|<4>${CD}系统变量管理${NC}"
        echo "|<5>${CD}应用市场${NC}"
        echo "|<6>${CD}快速SCP传输${NC}"
        echo "|<7>${CD}证书管理${NC}"
        echo "|<8>${CD}解压缩管理${NC}"
        echo "-------------"
        echo "|<101>${CDB}脚本更新${NC}"
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
                quick_scp_menu
                ;;
            7)
                acme_cert_menu
                ;;
            8)
                compress_menu
                ;;
            101)
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

# 动态快捷指令支持
if [[ -n "$1" ]]; then
    case "$1" in
        1)
            system_check_menu
            exit 0
            ;;
        2)
            manage_sources_menu
            exit 0
            ;;
        3)
            software_install_menu
            exit 0
            ;;
        4)
            manage_system_variables_menu
            exit 0
            ;;
        5)
            app_market_menu
            exit 0
            ;;
        6)
            quick_scp_menu
            exit 0
            ;;
        7)
            acme_cert_menu
            exit 0
            ;;
        8)
            compress_menu
            exit 0
            ;;
        101)
            update_menu
            exit 0
            ;;
        0)
            echo "${CDB}感谢使用！${NC}"
            exit 0
            ;;
        *)
            echo "${CDR}无效选项: $1${NC}"
            exit 1
            ;;
    esac
fi

# 运行主菜单
main_menu
