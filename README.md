# VPS Manager|VPS 管理器
## 简体中文|[English](https://github.com/yzh118/vpsmanager/blob/main/README_EN.md)
VPS系统管理脚本，`v1.0.0`版本集成了APT、DNF等软件源管理与快捷切换，系统别名快速设置，系统检测，系统软件安装等功能。
VPS Manager有开放的、可自定义的应用市场功能，通过URL中包含的`.conf`文件加载应用市场信息。

### 一键命令
Github:
```
wget --no-check-certificate -N -c -O vpsmanager.sh https://raw.githubusercontent.com/yzh118/VPSManager/refs/heads/main/vpsmanager.sh && chmod +x vpsmanager.sh && bash vpsmanager.sh
```
官方脚本URL 8-8-8-8.top：
```
wget --no-check-certificate -N -c -O vpsmanager.sh https://8-8-8-8.top/vpsmanager.sh && chmod +x vpsmanager.sh && bash vpsmanager.sh
```
### [更多使用教程](https://github.com/yzh118/VPSManager/blob/main/HELP.md#%E8%84%9A%E6%9C%AC%E8%AF%AD%E6%B3%95%E7%94%A8%E6%B3%95%E8%A1%A5%E5%85%85)
## 应用市场
本段分为两部分介绍
1. “一”使用教学；
2. “二”应用市场文件（的简介）。
### 一、使用教学
以`v1.0.0`版本为例，在主菜单页面输入“5”进入应用市场，首次使用需要输入URL，建议使用官方应用市场（未完善）：
```
https://8-8-8-8.top/yysc.conf
```
之后在列表中可以查看包含的所有应用，输入指定应用的序号可以一键安装。
后续想要修改应用市场URL可以在页面中输入“0”，重新设置应用市场URL。
### 二、应用市场文件
在服务器中创建一个`.conf`文件，内容格式：
```
{
Name=Name
PATH=不建议设置
like_api=https://example.com/like_api_example.php
 {
 ID=<1>
 Title=示例
 Text=Example
 Cd=bash命令，一键脚本
 }
}
```
经过解析后返回呈现在终端中：
```
=====================
 应用市场 Name
=====================
|<1>示例
|   描述: Example
-------------
|<0>修改应用市场
|<r>刷新应用市场
|<q>返回主菜单
====================
```
`.conf`文件中的`Cd`字段意味着在输入该序号回车会执行的命令，部分命令脚本可能权限不足无法执行，所以请自行做好相关配置。
### 注意！
在`v1.0.0`中，PATH功能未经测试，可能有意想不到的BUG，欢迎提Issues！
在`v1.1.0`中，PATH字段被删除并停止、移除脚本中对指定应用的单一变量支持，不再建议使用PATH。
## 重大更新日志
#### `v1.2.0`
`v1.2.0`在主菜单新增了证书申请功能，支持通配符、支持HTTP申请、支持TXT记录手动申请、支持自动续签。
#### `v1.3.0`
在`v1.3.0`新增了对应用市场配置文件中的`like_api`可选全局配置字段的支持。
在`v1.3.0`中将应用市场搜索机制改为不区分大小写。
