<?php
/**
 * 应用市场点赞统计API
 * 支持获取点赞数、点赞操作、防刷机制、哈希值验证
 * 
 * API接口：
 * GET /like_api.php?action=get&app_id=123 - 获取应用点赞数
 * POST /like_api.php - 点赞操作（需要提供哈希值验证）
 * 
 * 安全机制：
 * - 哈希值验证：确保客户端和服务端数据一致性
 * - 应用ID验证：验证应用是否存在于yysc.conf中
 * - 防刷机制：IP限制和时间间隔控制
 * 
 * 作者：1118论坛
 * 网站：1118luntan.top
 */

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

// 配置
$config = [
    'data_file' => 'likes_data.json',  // 点赞数据文件
    'log_file' => 'likes_log.txt',      // 操作日志文件
    'rate_limit' => 15,                 // 防刷时间间隔（秒）
    'max_likes_per_ip' => 100,          // 每个IP最大点赞数
    'yysc_file' => 'yysc.conf',         // 应用市场配置文件（默认）
    'hash_algorithm' => 'sha256',       // 哈希算法
];

// 获取应用市场文件路径
function getYyscFilePath() {
    // 尝试从多个可能的URL获取文件
    $possible_urls = [
        'https://8-8-8-8.top/yysc.conf',           // 原始域名
        'https://yzhy.8-8-8-8.top/yysc.conf',      // CDN域名
    ];
    
    // 本地缓存文件
    $local_file = 'yysc.conf';
    
    // 检查是否需要更新本地文件
    $need_update = false;
    if (!file_exists($local_file)) {
        $need_update = true;
    } else {
        // 检查文件是否超过1小时
        $file_age = time() - filemtime($local_file);
        if ($file_age > 3600) { // 1小时
            $need_update = true;
        }
    }
    
    // 如果需要更新，尝试从多个URL下载
    if ($need_update) {
        $success = false;
        foreach ($possible_urls as $remote_url) {
            $content = @file_get_contents($remote_url);
            if ($content !== false) {
                file_put_contents($local_file, $content);
                logAction("已更新本地文件: $remote_url -> $local_file");
                $success = true;
                break;
            } else {
                logAction("警告: 无法从 $remote_url 下载文件");
            }
        }
        
        if (!$success) {
            logAction("错误: 所有URL都无法访问，使用本地文件");
        }
    }
    
    return $local_file;
}

// 初始化数据文件
function initDataFile($filename) {
    if (!file_exists($filename)) {
        $data = [
            'apps' => [],
            'ips' => [],
            'last_update' => time()
        ];
        file_put_contents($filename, json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE));
    }
}

// 读取数据
function readData($filename) {
    if (!file_exists($filename)) {
        initDataFile($filename);
    }
    $content = file_get_contents($filename);
    return json_decode($content, true) ?: ['apps' => [], 'ips' => [], 'last_update' => time()];
}

// 保存数据
function saveData($filename, $data) {
    $data['last_update'] = time();
    file_put_contents($filename, json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE));
}

// 记录日志
function logAction($message) {
    global $config;
    $timestamp = date('Y-m-d H:i:s');
    $log_entry = "[$timestamp] $message\n";
    file_put_contents($config['log_file'], $log_entry, FILE_APPEND | LOCK_EX);
}

// 获取客户端IP
function getClientIP() {
    $ip_keys = ['HTTP_X_FORWARDED_FOR', 'HTTP_X_REAL_IP', 'HTTP_CLIENT_IP', 'REMOTE_ADDR'];
    foreach ($ip_keys as $key) {
        if (array_key_exists($key, $_SERVER) === true) {
            foreach (explode(',', $_SERVER[$key]) as $ip) {
                $ip = trim($ip);
                if (filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_NO_PRIV_RANGE | FILTER_FLAG_NO_RES_RANGE) !== false) {
                    return $ip;
                }
            }
        }
    }
    return $_SERVER['REMOTE_ADDR'] ?? 'unknown';
}

// 计算应用市场文件的哈希值
function calculateYyscHash() {
    global $config;
    
    $yysc_path = getYyscFilePath();
    
    // 如果文件不存在，返回空哈希
    if (!file_exists($yysc_path)) {
        logAction("警告: 应用市场文件不存在: $yysc_path");
        return hash($config['hash_algorithm'], '');
    }
    
    // 读取文件内容
    $content = file_get_contents($yysc_path);
    if ($content === false) {
        logAction("错误: 无法读取应用市场文件: $yysc_path");
        return hash($config['hash_algorithm'], '');
    }
    
    // 计算哈希值
    $hash = hash($config['hash_algorithm'], $content);
    logAction("计算应用市场文件哈希值: $yysc_path -> $hash");
    
    return $hash;
}

// 验证哈希值
function validateHash($client_hash) {
    $server_hash = calculateYyscHash();
    
    if ($client_hash === $server_hash) {
        logAction("哈希值验证成功: $client_hash");
        return true;
    } else {
        logAction("哈希值验证失败: 客户端=$client_hash, 服务端=$server_hash");
        return false;
    }
}

// 检查防刷
function checkRateLimit($app_id, $ip) {
    global $config;
    $data = readData($config['data_file']);
    
    // 检查IP限制
    if (!isset($data['ips'][$ip])) {
        $data['ips'][$ip] = ['likes' => 0, 'last_like' => 0];
    }
    
    $ip_data = $data['ips'][$ip];
    $current_time = time();
    
    // 检查时间间隔
    if ($current_time - $ip_data['last_like'] < $config['rate_limit']) {
        return ['allowed' => false, 'message' => '点赞过于频繁，请稍后再试'];
    }
    
    // 检查IP总点赞数限制
    if ($ip_data['likes'] >= $config['max_likes_per_ip']) {
        return ['allowed' => false, 'message' => '您的点赞次数已达上限'];
    }
    
    return ['allowed' => true];
}

// 验证应用ID是否存在
function validateAppId($app_id) {
    global $config;
    
    $yysc_path = getYyscFilePath();
    
    if (!file_exists($yysc_path)) {
        logAction("警告: 应用市场文件不存在，无法验证应用ID: $yysc_path");
        return false;
    }
    
    $content = file_get_contents($yysc_path);
    if ($content === false) {
        logAction("错误: 无法读取应用市场文件: $yysc_path");
        return false;
    }
    
    // 检查应用ID是否存在于应用市场文件中
    $pattern = '/ID=\<' . preg_quote($app_id, '/') . '\>/';
    if (preg_match($pattern, $content)) {
        logAction("应用ID验证成功: $app_id (文件: $yysc_path)");
        return true;
    } else {
        logAction("应用ID验证失败: $app_id (不存在于 $yysc_path 中)");
        return false;
    }
}

// 处理GET请求 - 获取点赞数
function handleGet($app_id) {
    global $config;
    
    if (!$app_id || !is_numeric($app_id)) {
        http_response_code(400);
        echo json_encode(['error' => '无效的应用ID'], JSON_UNESCAPED_UNICODE);
        return;
    }
    
    $data = readData($config['data_file']);
    $likes = isset($data['apps'][$app_id]) ? $data['apps'][$app_id]['count'] : 0;
    
    echo json_encode([
        'success' => true,
        'app_id' => $app_id,
        'likes' => $likes,
        'message' => '获取成功'
    ], JSON_UNESCAPED_UNICODE);
}

// 处理POST请求 - 点赞操作
function handlePost($app_id, $timestamp, $user_ip, $client_hash) {
    global $config;
    
    if (!$app_id || !is_numeric($app_id)) {
        http_response_code(400);
        echo json_encode(['error' => '无效的应用ID'], JSON_UNESCAPED_UNICODE);
        return;
    }
    
    // 验证哈希值
    if (!$client_hash) {
        http_response_code(400);
        echo json_encode([
            'success' => false,
            'message' => '缺少哈希值验证'
        ], JSON_UNESCAPED_UNICODE);
        return;
    }
    
    if (!validateHash($client_hash)) {
        http_response_code(403);
        echo json_encode([
            'success' => false,
            'message' => '哈希值验证失败，请刷新应用市场数据后重试'
        ], JSON_UNESCAPED_UNICODE);
        return;
    }
    
    // 验证应用ID是否存在
    if (!validateAppId($app_id)) {
        http_response_code(404);
        echo json_encode([
            'success' => false,
            'message' => '应用ID不存在或已失效'
        ], JSON_UNESCAPED_UNICODE);
        return;
    }
    
    // 检查防刷
    $rate_check = checkRateLimit($app_id, $user_ip);
    if (!$rate_check['allowed']) {
        http_response_code(429);
        echo json_encode([
            'success' => false,
            'message' => $rate_check['message']
        ], JSON_UNESCAPED_UNICODE);
        return;
    }
    
    $data = readData($config['data_file']);
    
    // 初始化应用数据
    if (!isset($data['apps'][$app_id])) {
        $data['apps'][$app_id] = [
            'count' => 0,
            'first_like' => time(),
            'last_like' => time()
        ];
    }
    
    // 更新点赞数
    $data['apps'][$app_id]['count']++;
    $data['apps'][$app_id]['last_like'] = time();
    
    // 更新IP数据
    if (!isset($data['ips'][$user_ip])) {
        $data['ips'][$user_ip] = ['likes' => 0, 'last_like' => 0];
    }
    $data['ips'][$user_ip]['likes']++;
    $data['ips'][$user_ip]['last_like'] = time();
    
    // 保存数据
    saveData($config['data_file'], $data);
    
    // 记录日志
    logAction("点赞成功: 应用ID=$app_id, IP=$user_ip, 当前点赞数={$data['apps'][$app_id]['count']}, 哈希值=$client_hash");
    
    echo json_encode([
        'success' => true,
        'app_id' => $app_id,
        'likes' => $data['apps'][$app_id]['count'],
        'message' => '点赞成功！感谢您的支持'
    ], JSON_UNESCAPED_UNICODE);
}

// 处理OPTIONS请求（CORS预检）
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

// 主处理逻辑
try {
    $method = $_SERVER['REQUEST_METHOD'];
    $action = $_GET['action'] ?? '';
    $app_id = $_GET['app_id'] ?? $_POST['app_id'] ?? null;
    $timestamp = $_POST['timestamp'] ?? time();
    $user_ip = getClientIP();
    $client_hash = $_POST['client_hash'] ?? '';
    
    switch ($method) {
        case 'GET':
            if ($action === 'get') {
                handleGet($app_id);
            } else {
                http_response_code(400);
                echo json_encode(['error' => '无效的GET请求'], JSON_UNESCAPED_UNICODE);
            }
            break;
            
        case 'POST':
            if ($action === 'like' || !$action) {
                handlePost($app_id, $timestamp, $user_ip, $client_hash);
            } else {
                http_response_code(400);
                echo json_encode(['error' => '无效的POST请求'], JSON_UNESCAPED_UNICODE);
            }
            break;
            
        default:
            http_response_code(405);
            echo json_encode(['error' => '不支持的请求方法'], JSON_UNESCAPED_UNICODE);
            break;
    }
    
} catch (Exception $e) {
    logAction("错误: " . $e->getMessage());
    http_response_code(500);
    echo json_encode(['error' => '服务器内部错误'], JSON_UNESCAPED_UNICODE);
}
?> 