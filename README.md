# rmnet-netwatch

智能网络接口监控和路由切换的 Magisk 模块，专为移动数据网络优化设计。

## 核心功能

rmnet-netwatch 是一个高度智能的网络管理模块，能够：

- **自动网络接口发现**：动态扫描系统中所有指定类型的网络接口
- **实时连接性检测**：通过 ICMP ping 测试验证每个接口的网络连通性
- **智能路由切换**：自动将 NET_TABLE 的默认路由切换到当前可用的最佳接口
- **故障自动恢复**：当主接口出现问题时，无缝切换到备用接口
- **配置热重载**：支持运行时配置更新，无需重启模块
- **智能休眠检测**：设备休眠时暂停检测，节省系统资源

## 工作原理

### 主循环流程
1. **休眠状态检测**：检查设备是否处于休眠状态，如果是则跳过本次检测
2. **配置文件监控**：检测配置文件是否有更新，如有则重新加载
3. **路由表发现**：查找系统中以指定接口类型命名的路由表
4. **接口扫描**：获取所有符合条件的网络接口列表
5. **连通性测试**：按优先级顺序测试每个接口的网络连通性
6. **路由更新**：将默认路由切换到第一个可用的接口

### 核心算法
- **接口优先级**：按接口编号倒序处理（如 rmnet_data3 > rmnet_data2 > rmnet_data1 > rmnet_data0）
- **网关自动发现**：智能识别每个接口的网关地址
- **路由表精确匹配**：确保只操作与指定接口类型相关的路由表

## 安装方法

1. 下载模块 zip 文件
2. 打开 Magisk Manager
3. 进入"模块"页面
4. 点击"从本地安装"
5. 选择下载的模块 zip 文件
6. 重启设备激活模块

## 配置选项

在 `/data/adb/modules/rmnet-netwatch/scripts/config.conf` 中配置以下参数：

### 基础配置
- `LOGDIR`: 日志目录路径（默认：`/data/local/tmp`）
- `LOG`: 日志文件完整路径（默认：`/data/local/tmp/net-switch.log`）
- `PING_TARGET`: 连通性测试目标地址（默认：`www.baidu.com`）
- `SLEEP_INTERVAL`: 检测循环间隔时间，单位秒（默认：`5`）

### 接口配置
- `ENT_NAME`: 网络接口名称前缀（默认：`rmnet_data`）
- `MAX_RMNET_DATA`: 最大接口编号（默认：`3`，处理接口0-3）
- `MIN_RMNET_DATA`: 最小接口编号（默认：`0`）

## 高级配置

### 支持的接口类型

通过修改 `ENT_NAME` 变量支持不同的网络接口：

```bash
# 高通平台
ENT_NAME=rmnet_data    # 标准移动数据接口
ENT_NAME=rmnet_ipa     # IPA 加速接口

# 联发科平台
ENT_NAME=ccmni         # 移动数据接口
ENT_NAME=ccmni         # WiFi 接口

# 通用接口
ENT_NAME=wlan          # 无线网络接口
ENT_NAME=eth           # 有线网络接口
```

### 配置热重载

模块支持配置文件的实时重载：

1. 编辑配置文件：`/data/adb/modules/rmnet-netwatch/scripts/config.conf`
2. 保存文件，模块在下一个检测周期自动重载配置
3. 查看日志确认配置更新：`tail -f /data/local/tmp/net-switch.log`

### 网关发现算法

模块使用智能算法自动发现接口网关：

1. **优先使用显式网关**：从路由表中提取 `via` 字段指定的网关
2. **自动计算网关**：如果没有显式网关，计算网络地址 + 1 作为网关
3. **IPv4 网络计算**：使用位运算计算网络地址和网关地址

## 使用场景

### 多卡双待设备
- 自动在两个移动数据接口间切换
- 确保始终使用信号最好的接口
- 提供网络冗余和故障转移

### 网络信号不稳定环境
- 实时监控接口连接质量
- 自动切换到更稳定的接口
- 减少网络中断时间

### 开发和测试
- 支持自定义接口类型进行测试
- 详细的日志记录便于问题诊断
- 灵活的配置选项适应不同需求

## 日志分析

查看实时日志：
```bash
tail -f /data/local/tmp/net-switch.log
```

日志示例：
```
[2026-01-08 14:30:15] === rmnet-netwatch started ===
[2026-01-08 14:30:15] 检测到配置文件更新，重新加载配置
[2026-01-08 14:30:20] 已将 table rmnet_data3 的 default 路由替换为 dev=rmnet_data3 via 192.168.1.1
[2026-01-08 14:30:25] 接口 rmnet_data2 未找到网关，跳过
```

## 故障排除

### 模块无法启动
1. 检查 Magisk 模块是否正确安装和激活
2. 确认脚本权限：`chmod 755 /data/adb/modules/rmnet-netwatch/service.sh`
3. 查看启动日志：`cat /data/local/tmp/net-switch.log`

### 找不到合适的路由表
1. 检查接口类型配置：确认 `ENT_NAME` 值正确
2. 查看系统路由表：`ip rule show | grep lookup`
3. 确认路由表名称包含配置的接口前缀

### 网络切换不生效
1. 检查接口是否存在：`ip link show | grep $ENT_NAME`
2. 测试接口连通性：`ping -c 1 -I $IFACE $PING_TARGET`
3. 查看当前路由：`ip route show table $NET_TABLE`

### 配置文件不生效
1. 检查配置文件权限：`ls -l /data/adb/modules/rmnet-netwatch/scripts/config.conf`
2. 验证配置语法：确保没有语法错误
3. 重启模块强制重载配置

### 性能问题
1. 增加 `SLEEP_INTERVAL` 减少检测频率
2. 减少接口编号范围（调整 `MAX_RMNET_DATA`）
3. 更换更近的 `PING_TARGET` 地址

## 技术规格

- **支持的 Android 版本**：Android 8.0+
- **要求的 Magisk 版本**：Magisk 20.0+
- **支持的接口数量**：可配置，默认支持 4 个接口
- **检测间隔**：可配置，默认 5 秒
- **日志格式**：时间戳 + 消息，便于分析
- **内存占用**：极低，适合长期运行

## 兼容性

### 芯片平台支持
- **高通骁龙**：rmnet_data*, rmnet_ipa*
- **联发科**：ccmni*, ccmni*
- **三星 Exynos**：rmnet*, ccmni*
- **通用接口**：wlan*, eth*, 其他自定义接口

### 设备类型
- 智能手机（单卡/双卡）
- 平板电脑
- 支持 Magisk 的 Android 设备
- 开发板和测试设备

## 安全性

- **最小权限原则**：只在必要时使用 root 权限
- **日志保护**：日志文件权限设置为 644
- **配置验证**：配置文件变更时进行有效性检查
- **错误处理**：完善的错误处理和回退机制

## 开发者信息

- **模块名称**：rmnet-netwatch
- **版本**：1.0
- **作者**：gfuzan
- **许可证**：开源项目
- **源码位置**：`/data/adb/modules/rmnet-netwatch/scripts/start.sh`

## 贡献指南

欢迎提交 Issue 和 Pull Request 来改进这个模块：

1. **Bug 报告**：请提供详细的日志和设备信息
2. **功能建议**：描述新功能的使用场景和实现思路
3. **代码贡献**：遵循现有的代码风格和注释规范

---

*注意：本模块需要 root 权限和 Magisk 环境，请确保在了解其工作原理后再进行安装和使用。*