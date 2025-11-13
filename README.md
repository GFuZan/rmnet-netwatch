# rmnet-netwatch

自动检测 rmnet_data* 接口可用性并切换 NET_TABLE 默认路由的 Magisk 模块。

## 配置

模块支持以下配置项，可在 `scripts/config.conf` 中修改：

- `LOGDIR`: 日志目录，默认为 `/data/local/tmp`
- `LOG`: 日志文件路径，默认为 `/data/local/tmp/net-switch.log`
- `PING_TARGET`: 用于连接性测试的目标地址，默认为 `www.baidu.com`
- `SLEEP_INTERVAL`: 检测间隔（秒），默认为 5
- `MAX_RMNET_DATA`: 最大允许的 rmnet_data 接口编号（例如，如果设置为 3，则只处理 rmnet_data0 到 rmnet_data3），默认为 3
- `MIN_RMNET_DATA`: 最小允许的 rmnet_data 接口编号（例如，如果设置为 1，则只处理编号 >= 1 的接口），默认为 0
