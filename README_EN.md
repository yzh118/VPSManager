# VPS Manager | VPS Manager  
## Simplified Chinese | [English](https://github.com/yzh118/vpsmanager/blob/main/README_EN.md)  
A VPS system management script. Version `v1.0.0` integrates features such as APT and DNF package source management with quick switching, system alias quick setup, system detection, and system software installation.  
VPS Manager includes an open and customizable app market feature, which loads app market information via `.conf` files specified in URLs.  

### One-Command Installation  
Github:  
```
wget --no-check-certificate -N -c -O vpsmanager.sh https://raw.githubusercontent.com/yzh118/VPSManager/refs/heads/main/vpsmanager.sh && chmod +x vpsmanager.sh && bash vpsmanager.sh  
```  
Official script URL 8-8-8-8.top:  
```
wget --no-check-certificate -N -c -O vpsmanager.sh https://8-8-8-8.top/vpsmanager.sh && chmod +x vpsmanager.sh && bash vpsmanager.sh  
```  
## App Market  
This section is divided into two parts:  
1. Part One: Usage Guide;  
2. Part Two: Introduction to App Market Files.  

### Part One: Usage Guide  
Taking version `v1.0.0` as an example, enter "5" on the main menu to access the app market. First-time users will need to input a URL. It is recommended to use the official app market (still under development):  
```
https://8-8-8-8.top/yysc.conf  
```  
Afterward, you can view all available apps in the list. Enter the corresponding number of an app to install it with one click.  
To modify the app market URL later, enter "0" on the page to reset the URL.  

### Part Two: App Market Files  
Create a `.conf` file on the server with the following format:  
```
{
Name=Name
PATH=Not recommended to set
like_api=https://example.com/like_api_example.php
 {
 ID=<1>
 Title=Example
 Text=Example
 Cd=Bash command, one-click script
 }
}
```  
After parsing, it will be displayed in the terminal as:  
```
=====================
 App Market Name
=====================
|<1>Example
|   Description: Example
-------------
|<0>Modify App Market
|<r>Refresh App Market
|<q>Return to Main Menu
====================
```  
The `Cd` field in the `.conf` file specifies the command to be executed when the corresponding number is entered. Some scripts may lack sufficient permissions to execute, so ensure proper configuration.  

### Note!  
In `v1.0.0`, the PATH feature has not been tested and may contain unexpected bugs. Feel free to report issues!  
In `v1.1.0`, the PATH field was removed, and support for single-variable specifications for specific apps in the script was discontinued. Using PATH is no longer recommended.  

## Major Update Log  
#### `v1.2.0`  
Added a certificate application feature to the main menu, supporting wildcard certificates, HTTP-based applications, manual TXT record verification, and automatic renewal.  
#### `v1.3.0`  
Added support for the optional global configuration field `like_api` in app market configuration files.  
In `v1.3.0`, the app market search mechanism was updated to be case-insensitive.
