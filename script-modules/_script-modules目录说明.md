# scroll-list.lua
* track-list.lua，adevice-list.lua依赖，来源：https://github.com/CogentRedTester/mpv-scroll-list

# file-browser-addons
* 文件浏览脚本依赖，来源：https://github.com/dyphire/mpv-config

## WebDAV 库

点击待机页或播放控制栏右下角的播放列表按钮，可以切换当前队列中的条目、导入或保存本地播放列表，也可以添加和打开 WebDAV 库。

选择「添加 WebDAV 库」并填写目录地址。支持匿名访问和 Basic 认证，有凭据时建议使用 HTTPS。使用相同地址再次保存会更新库名和凭据。库配置保存在本机的 `script-opts/webdav-libraries.json`，其中的认证信息可以还原。

在文件浏览器中用方向键浏览，按 Enter 进入目录或播放文件，按 Shift+Enter 把选中的媒体文件加入当前队列。
