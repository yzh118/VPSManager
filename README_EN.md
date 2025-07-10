# VPS Manager
## [简体中文](https://github.com/yzh118/vpsmanager) | English

VPS system management script. Version `v1.0.0` integrates features such as APT and DNF software source management and quick switching, system alias quick setup, system detection, and system software installation.

VPS Manager provides an open and customizable application marketplace feature, which loads marketplace information from a `.conf` file specified by a URL.

## Application Marketplace

This section is divided into two parts:
1. User Guide
2. Development & Private Deployment Guide

### 1. User Guide

Take version `v1.0.0` as an example. On the main menu page, enter “5” to access the application marketplace. The first time you use it, you need to enter a URL. It is recommended to use the official marketplace (still under development):

```
https://8-8-8-8.top/yysc.conf
```

After that, you can view all included applications in the list. Enter the corresponding application number to install it with one click.

If you want to change the marketplace URL later, enter “0” on the page to reset the marketplace URL.

### 2. Development & Private Deployment Guide

Create a `.conf` file on your server with the following format:

```
{
Name=Name
 {
 ID=<1>
 Title=Example
 Text=Example
 Cd=bash command, one-click script
 PATH=null
 }
}
```

After parsing, it will be displayed in the terminal as:

```
=====================
 Application Market Name
=====================
|<1>Example
|   Description: Example
-------------
|<0>Modify Marketplace
|<r>Refresh Marketplace
|<q>Return to Main Menu
====================
```

The `Cd` field in the `.conf` file means the command that will be executed when you enter the corresponding number and press Enter. Some commands or scripts may not have sufficient permissions to execute, so please make sure to configure the necessary permissions yourself.

### Note!

In `v1.0.0`, the PATH feature is untested and may have unexpected bugs. Issues and feedback are welcome!
