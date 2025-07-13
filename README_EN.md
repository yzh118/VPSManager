# VPS Manager|VPS 管理器
## [简体中文](https://github.com/yzh118/vpsmanager) | English
VPS system management script, version `v1.0.0` integrates APT, DNF and other software source management and quick switching, system alias quick setup, system detection, system software installation and other functions.
VPS Manager has an open, customizable app store feature that loads app store information through `.conf` files contained in URLs.
## App Store
This section is divided into two parts
1. "One" usage tutorial;
2. "Two" app store file (introduction).
### One, Usage Tutorial
Taking version `v1.0.0` as an example, enter "5" on the main menu page to enter the app store. For first use, you need to enter a URL. It is recommended to use the official app store (not yet complete):
```
https://8-8-8-8.top/yysc.conf
```
After that, you can view all included applications in the list, and enter the specified application number to install with one click.
To modify the app store URL later, you can enter "0" on the page to reset the app store URL.
### Two, App Store File
Create a `.conf` file on the server with the following content format:
```
{
Name=Name
 {
 ID=<1>
 Title=Example
 Text=Example
 Cd=bash command, one-click script
 }
}
```
After parsing, it returns and displays in the terminal:
```
=====================
 App Store Name
=====================
|<1>Example
|   Description: Example
-------------
|<0>Modify App Store
|<r>Refresh App Store
|<q>Return to Main Menu
====================
```
The `Cd` field in the `.conf` file means the command that will be executed when you press Enter after entering that number. Some command scripts may not have sufficient permissions to execute, so please configure accordingly.
### Attention!
In `v1.0.0`, the PATH function has not been tested and may have unexpected bugs. Welcome to submit Issues!
In `v1.1.0`, the PATH field was deleted and stopped, and the script's support for single variables for specified applications was removed. PATH is no longer recommended for use.
## Major Update Log
`v1.2.0` added certificate application functionality to the main menu, supporting wildcards, HTTP application, TXT record manual application, and automatic renewal.
