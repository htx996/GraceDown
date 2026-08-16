# GraceDown

GraceDown 是一款 macOS 菜单栏 UPS 在线监控工具，适合 UPS 接在 NAS 上、Mac 通过局域网读取 UPS 状态的使用场景。

它可以通过 Network UPS Tools（NUT）读取 UPS 信息，在菜单栏显示电量、供电状态、剩余时间、输入电压和负载，并可在满足条件后请求 macOS 自动关机。

## 主要功能

- macOS 菜单栏 UPS 状态面板
- 支持 NAS NUT 和本机 UPS 两种数据来源
- 显示 UPS 电量、剩余时间、输入电压、负载和供电状态
- 支持自动关机规则
- 支持多个关机触发条件
- 支持右键菜单栏快捷操作
- 支持通过 GitHub Release 检查、下载、校验并自动安装新版本

## 适用场景

典型使用方式：

1. UPS 通过 USB 接到 NAS。
2. NAS 开启 NUT 服务。
3. GraceDown 在 Mac 上通过局域网连接 NAS NUT 服务。
4. Mac 根据 UPS 状态显示信息，并在配置条件满足后执行关机请求。

## NAS NUT 设置

打开 GraceDown 设置页后，配置以下内容：

- NAS 地址：NAS 的局域网 IP 或主机名
- NUT 端口：通常为 `3493`
- UPS 名称：留空时自动使用 NAS 返回的第一个 UPS
- 用户名和密码：仅在 NUT 服务启用认证时填写

首次连接局域网设备时，macOS 可能会提示是否允许 GraceDown 访问本地网络。请允许该权限，否则 GraceDown 无法连接 NAS NUT 服务。

## 自动关机

GraceDown 可以根据以下条件请求 macOS 关机：

- UPS 切换到电池供电
- UPS 回到市电供电
- UPS 电池已充满
- UPS 电量低于指定比例
- UPS 剩余时间低于指定时长
- UPS 自身发出低电量信号
- NAS NUT 连接中断

自动关机默认关闭，需要在设置页手动启用。触发条件持续达到设定时间后，GraceDown 会请求 macOS 关机。

关机请求通过 macOS System Events 和 AppleScript 执行。首次执行时，macOS 可能会要求授予自动化权限。


## 开源协议

本项目使用 Apache License 2.0 开源协议。

Copyright 2026 Han
