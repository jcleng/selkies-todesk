# v1.1.0 — LXDE 桌面 + 两个运行期修复（ToDesk 4.9.7.0）

在 [Selkies](https://github.com/selkies-project/selkies) 网页桌面里运行 **ToDesk Linux 客户端作为主控端**。

**相对 v1.0.0 的主要变化**：会话从「裸 openbox」升级成 **LXDE 桌面环境**，并修掉两个运行期问题。

## 镜像

```bash
# 推荐：阿里云 ACR，国内拉取快
docker pull registry.cn-hangzhou.aliyuncs.com/jcleng/gitbuild-selkies-todesk:latest

# GitHub Container Registry
docker pull ghcr.io/jcleng/selkies-todesk:v1.1.0
```

| 来源 | tag | digest |
| --- | --- | --- |
| ACR | `gitbuild-selkies-todesk:latest` | `sha256:7d1a85910747dafba151f0e84a920463008fec51fc77d13194faed475d0d37f4` |
| GHCR | `selkies-todesk:v1.1.0` / `:4.9.7.0` | `sha256:fe1c2043db549ed6943a0f2068f74685d294ce90ff1b6c37e3f4805f8ca45b97` |

- 基础镜像：`registry.cn-hangzhou.aliyuncs.com/jcleng/gitbuild-selkies-base:latest`（真 `systemd` 作 PID 1）
- ToDesk：`4.9.7.0`（官方 amd64 deb，`sha256=e6aee6f7…09acf4b`，构建日志校验 `OK`）
- 架构：`linux/amd64`

## 本版改动

### 1. 桌面：裸 openbox → LXDE

底包原本只起 `openbox-session` —— 没有任务栏、没有开始菜单、没有文件管理器，
ToDesk 缩到托盘后就找不回来。现在：

| 组件 | 作用 |
| --- | --- |
| `lxpanel` | 底部任务栏 + 左下角开始菜单 + **system tray** |
| `pcmanfm` | 桌面图标 + 文件管理器 |
| `lxterminal` | 终端 |
| `openbox` | 窗口管理器（**保留**，LXDE 的标准组合，`desktop.conf` 里 `window_manager=openbox-lxde`） |

- `root/defaults/startwm.sh` 覆盖为 `exec dbus-launch --exit-with-session /usr/bin/startlxde`，`startlxde` 缺失时回退 `openbox-session`
- 启动项在 `/etc/xdg/lxsession/LXDE/autostart`：`lxpanel` + `pcmanfm --desktop` + `lxde-app`（把 selkies 的 `$APP`/`$APP_CLI` 语义接过来）
- 去掉 `xscreensaver`：没装，而且远程桌面自动锁屏等于把自己锁在门外
- 依赖用 `--no-install-recommends` 装 `lxde-core lxterminal lxde-icon-theme`，**38 个小包**，无 GNOME/KDE 依赖，并移除原来的 `stalonetray`（`lxpanel` 自带托盘）
- 构建期跑 `update-desktop-database`，ToDesk 会出现在开始菜单里

> 注意：`lxde-core` 依赖虚拟包 `lxde-session`，全 Debian 没有同名二进制包，唯一提供者是
> `openbox-lxde-session`（`Depends: lxde-common, lxsession, openbox`）。apt 会自动选中它。

### 2. 修复：ToDesk 窗口自己缩进托盘（`todesk-raise`）

现象：连着网页桌面时，ToDesk 不点任何东西也会缩成最小化，点一下就缩回去。

定位到的事实：

- ToDesk 顶层窗口会处于 `WM_STATE: Iconic` / `_NET_WM_STATE = _NET_WM_STATE_HIDDEN`
- lxpanel 任务栏的语义是「点已激活窗口 = 最小化」，所以窗口一旦缩了，点任务栏条目只会继续最小化
- 无操作时窗口能稳定保持 `Normal`，root 上也没有 `WM_CHANGE_STATE` 的 ClientMessage

处理：新增 `todesk-raise`，会话启动时后台轮询 `_NET_CLIENT_LIST`，把 `WM_CLASS` 含 `ToDesk`
且 `WM_STATE=Iconic` 的顶层窗口 `windowactivate` 拉出来；拉出一次即退出，窗口已正常则早退。
日志在 `/config/.local/share/todesk-raise.log`。

**如实说明**：这是「缩了就拉回来」的缓解手段，不是根除。如果你在会话里仍然看到窗口自己缩，
手动救一次即可：

```bash
docker exec -u abc -e DISPLAY=:1 selkies-todesk xdotool windowactivate $(docker exec -u abc -e DISPLAY=:1 selkies-todesk xdotool search --class ToDesk | head -1)
```

### 3. 修复：`no session for pid NNNN` 弹窗

- 那个 pid 就是 `lxpolkit` —— lxsession 把它当 polkit 认证代理拉起（journal: `Launching lxpolkit`）
- polkit 注册 agent 要把 PID 映射到 logind session，而容器里 `loginctl list-sessions` 为空
  （桌面进程不是经 logind 登录的）→ 报 `no session for pid 1999` 并弹出错误窗口
- 容器内没有需要 polkit 授权的场景（没装 `udisks2` 做挂载，关机走 systemd），因此镜像里
  **直接移除 `/usr/bin/lxpolkit`**
- 踩坑记录：`polkit/command=lxpolkit` 是 lxsession 首次运行写进
  `/config/.config/lxsession/LXDE/desktop.conf` 的，改镜像里 `/etc/xdg` 的默认值**不生效**，只能动二进制

## 运行

```bash
docker run -d \
  --name selkies-todesk \
  --privileged \
  --cgroupns=host \
  --cap-add=SYS_ADMIN \
  -v /sys/fs/cgroup:/sys/fs/cgroup \
  --tmpfs /run --tmpfs /tmp \
  --shm-size=1gb \
  -p 3001:3001 \
  -e PUID=1000 -e PGID=1000 \
  -e TZ=Asia/Shanghai -e LC_ALL=zh_CN.UTF-8 \
  -v $PWD/config:/config \
  -v todesk-config:/opt/todesk/config \
  -v todesk-etc:/etc/todesk \
  -v todesk-lib:/var/lib/todesk \
  -v todesk-log:/var/log/todesk \
  registry.cn-hangzhou.aliyuncs.com/jcleng/gitbuild-selkies-todesk:latest
```

浏览器打开 `https://localhost:3001`（自签证书需接受）。桌面是 LXDE：底部任务栏、左下角开始菜单、
桌面图标，ToDesk 会自动起来。

## 已验证 / 已知限制

- 构建：[`41278385162`](https://github.com/jcleng/selkies-todesk/actions/runs/41278385162)（GHCR）、
  [`41277383838`](https://github.com/jcleng/action-sync-images/actions/runs/41277383838)（ACR），均 success
- 容器运行：维护者实测，LXDE 桌面正常，ToDesk 可连机械设备
- 双重远程叠加：延迟是 ToDesk + Selkies 两段之和，视频流场景会明显
- 只构建 `linux/amd64`
- 官方 `dl.todesk.com` 在腾讯云 EdgeOne 后有 TCaptcha，所以默认从 Internet Archive 的官方 URL 快照取包并强制 sha256 校验
- `RESTART_APP` 保持关闭：底包 watchdog 把路径写死成 `~/.config/openbox/autostart`，在 LXDE 下不适用

完整说明、排障与设计取舍见 [README](https://github.com/jcleng/selkies-todesk#readme)。
ToDesk 客户端为闭源软件，版权归海南有趣科技有限公司所有；本仓库仅分发构建脚本，不转售其安装包。
