# selkies-todesk

[![release](https://img.shields.io/github/v/release/jcleng/selkies-todesk?label=release)](https://github.com/jcleng/selkies-todesk/releases)
[![build](https://github.com/jcleng/selkies-todesk/actions/workflows/build.yml/badge.svg)](https://github.com/jcleng/selkies-todesk/actions/workflows/build.yml)

把 **ToDesk Linux 客户端包进 Selkies 网页桌面**，作为**主控端**使用：
浏览器里打开 Selkies，操作里面的 ToDesk 窗口，去连接/控制别的机器。

桌面是 **LXDE**（`--no-install-recommends` 最小组合）：底部任务栏、
左下角开始菜单（ToDesk 也在里面）、`pcmanfm` 文件管理器、`lxterminal` 终端，
窗口管理器仍是 `openbox`（LXDE 的标准组合），托盘由 `lxpanel` 提供。

当前发布版本：[**v1.1.0**](https://github.com/jcleng/selkies-todesk/releases/tag/v1.1.0)（ToDesk `4.9.7.0`，LXDE 桌面，已验证可运行）。

基础镜像用 [`jcleng/selkies-base`](https://github.com/jcleng/selkies-base)
（真 `systemd` 作 PID 1 的 Selkies 环境），因此 ToDesk 官方的 `todeskd.service`
可以原样运行 —— 不需要 s6 钩子、不需要手工 `nohup`。

- 只支持 `amd64`（与 selkies-base 一致）。
- 镜像**不在本地构建**，由 GitHub Actions 构建（见「构建」）。

## 容器里 ToDesk 当主控端，意味着什么

```
你的浏览器 ──WebRTC──> Selkies(容器内 X11 桌面) ──> ToDesk GUI ──ToDesk 云──> 被控机器
```

即 **双重远程**：被控端画面先由 ToDesk 编码传到容器，再由 Selkies 编码送到浏览器。
延迟是两段之和、画质损失两次。所以它适合这些场景：

- 你需要一个随时可用、跨设备（手机/平板/任意浏览器）的 ToDesk 主控环境；
- 你不想在每台机器上装 ToDesk，或需要多台机器共用同一个 ToDesk 账号/设备；
- 你要在隔离环境里跑闭源远控客户端。

如果只是想让别人连进这个容器，那 Selkies 本身就是远控通道，不需要再叠 ToDesk。

## 目录结构

```
.
├── Dockerfile                 # dpkg-deb -x 解包官方 deb + 依赖（含 LXDE）+ 启动器
├── root/                      # COPY /root / ：镜像内路径与仓库路径一一对应
│   ├── defaults/startwm.sh                           # 覆盖底包：起 LXDE 会话（startlxde）
│   ├── etc/xdg/lxsession/LXDE/autostart              # LXDE 启动项：lxpanel + pcmanfm + $APP
│   ├── etc/systemd/system/todeskd.service            # 官方 unit（与 deb 内逐字节一致）
│   ├── etc/systemd/system/multi-user.target.wants/
│   │   └── todeskd.service -> ../todeskd.service     # enable 产物（构建期不跑 systemctl）
│   ├── usr/local/bin/lxde-app                        # LXDE autostart -> $APP 中转（保留 APP/APP_CLI 语义）
│   ├── usr/local/bin/todesk-raise                    # 把缩进托盘的 ToDesk 主窗口拉出来
│   └── usr/local/bin/todesk-session                  # $APP 入口：环境 + 后台 todesk-raise + 前台 exec ToDesk
├── vendor/.gitkeep            # 放 todesk-*.deb 可让构建走本地取包（*.deb 被 .gitignore 排除）
└── .github/workflows/build.yml
```

## 环境变量

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `APP` | `/usr/local/bin/todesk-session` | 会话里启动的程序（ToDesk GUI），由 `lxde-app` 中转到 LXDE autostart |
| `APP_CLI` | 空 | 追加给 `APP` 的参数 |
| `PIXELFLUX_WAYLAND` | `false` | 强制 X11/LXDE 会话。ToDesk 是纯 X11 客户端，labwc 下只能落 XWayland |
| `TITLE` | `ToDesk` | 浏览器标题 / PWA 名称 |
| `RESTART_APP` | 空 | **保持关闭**。底包的 watchdog 把路径写死成 openbox/labwc 的 autostart，对 LXDE 无效，开了只会空跑 |

会话启动项在 `/etc/xdg/lxsession/LXDE/autostart`。若你想改桌面启动什么（例如不自动开 ToDesk），
在容器里写一份用户级文件即可覆盖它：

```bash
# /config 是持久化的，重建容器不丢
docker exec -it selkies-todesk bash -lc 'mkdir -p /config/.config/lxsession/LXDE && \
  printf "@lxpanel --profile LXDE\n@pcmanfm --desktop --profile LXDE\n" \
  > /config/.config/lxsession/LXDE/autostart'
docker restart selkies-todesk
```

其余 Selkies 变量（`PUID`/`PGID`/`TZ`/`LC_ALL`/`CUSTOM_USER`/`PASSWORD`/`SELKIES_*`）
与 `selkies-base` 完全相同，见其 README。

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
  -p 3098:3001 \
  -e TZ=Asia/Shanghai -e LC_ALL=zh_CN.UTF-8 \
  registry.cn-hangzhou.aliyuncs.com/jcleng/gitbuild-selkies-todesk
```

`--cgroupns=host` / `--cap-add=SYS_ADMIN` / `-v /sys/fs/cgroup:/sys/fs/cgroup` 这三项是
**为容器里的 systemd** 准备的：PID 1 是 `/sbin/init`，它需要自己的 cgroup 视图（host namespace）
才能干净地拉起/停止 `todeskd.service` 等单元。`--privileged` 已包含 `SYS_ADMIN`，但三项仍建议显式写上，
以后去掉 `--privileged` 时不会突然失效。

不用 `--privileged` 时，至少保留：

```bash
docker run -d --name selkies-todesk \
  --cgroupns=host --cap-add=SYS_ADMIN \
  -v /sys/fs/cgroup:/sys/fs/cgroup \
  --tmpfs /run --tmpfs /tmp --shm-size=1gb \
  -p 3001:3001 -v $PWD/config:/config \
  ghcr.io/jcleng/selkies-todesk:latest
```

> 该组合下内层 Docker（底包带的 `docker.service`）不会起来，属预期。

浏览器打开 `https://localhost:3001`（自签证书需接受）。桌面是 LXDE：
底部任务栏 + 左下角开始菜单 + 桌面图标（家目录/回收站），ToDesk 窗口会自动起来。

### docker-compose

```yaml
services:
  selkies-todesk:
    image: ghcr.io/jcleng/selkies-todesk:v1.0.0
    container_name: selkies-todesk
    privileged: true
    # 容器内 PID 1 是 systemd，需要自己的 cgroup 视图
    cgroup: host
    cap_add:
      - SYS_ADMIN
    tmpfs: [/run, /tmp]
    shm_size: 1gb
    ports: ["3001:3001"]
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Asia/Shanghai
      - LC_ALL=zh_CN.UTF-8
      - TITLE=ToDesk
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup
      - ./config:/config
      - todesk-config:/opt/todesk/config
      - todesk-etc:/etc/todesk
      - todesk-lib:/var/lib/todesk
      - todesk-log:/var/log/todesk

volumes:
  todesk-config:
  todesk-etc:
  todesk-lib:
  todesk-log:
```

### 为什么这几个目录要挂出来

ToDesk 把「设备已登录 / 设备码 / 设置」写在容器内的固定路径上，**必须是真实目录**
（Nixpkgs 的 `todesk` 打包明确记录过：软链接到别处会失败）：

| 路径 | 内容 |
| --- | --- |
| `/opt/todesk/config/config.ini` | 服务级配置（官方排障也直接改它），镜像里已 `chmod 0777` 该目录 |
| `/etc/todesk` | 服务写入的设备 uuid 等 |
| `/var/lib/todesk` | 运行期状态（Nix 把它 bind 到 config） |
| `/var/log/todesk/service_*.log` | 服务日志 |
| `/config/.local/share/todesk/Logs/client_*.log` | 客户端日志（`/config` 已持久化） |

不挂也能跑，但重建容器后要重新登录、设备码可能变化。

## 更新 ToDesk 版本

1. 打开官方页 <https://www.todesk.com/linux.html>，取 `Debian/Ubuntu/Mint (x64)` 的 deb；
   或用 AUR `todesk-bin` 的 `.SRCINFO`（`source_x86_64` + `sha256sums_x86_64`）作为版本与校验参考。
2. 算出 sha256：`sha256sum todesk-v<VER>-amd64.deb`
3. 三选一：
   - **本地/内网构建**：把 deb 放进 `vendor/`（文件名 `todesk-*.deb`），构建时自动优先使用；
   - **workflow_dispatch**：填 `todesk_deb_url` + `todesk_sha256` 两个输入；
   - **改默认值**：改 Dockerfile 里 `TO_DESK_VERSION` / `TO_DESK_DEB_URL` / `TO_DESK_SHA256`。

> ⚠️ 官方 `dl.todesk.com` 在腾讯云 EdgeOne 之后，`curl`/`wget` 直连只会拿到
> `EO_Bot_Ssid` JS 挑战 → TCaptcha 人机验证页（服务端返回 986 字节脚本，带 cookie/referer/UA 都绕不过）。
> 所以 **Dockerfile 里不能写官方直链**；默认用的是 Internet Archive 上该官方 URL 的历史快照，
> 并用 sha256（与 AUR 记录一致）证明是官方原文件。若 IA 不可达，请把 deb 放进 `vendor/`。

## 构建

镜像不由本地构建。四件事都已在仓库内自洽：取包、校验、解包、enable 软链。

### 方式一（推荐）：复用 action-sync-images，推阿里云 ACR

与 `selkies-base` 同一套流程（`jcleng/action-sync-images` 的 `build-repo.yml`）。
国内拉 ACR 比 GHCR 快很多，**日常构建走这条**：

```bash
gh workflow run build-repo.yml --repo jcleng/action-sync-images \
  -f arg_repo_url=https://github.com/jcleng/selkies-todesk.git \
  -f arg_branch_name=main \
  -f arg_username=gitbuild \
  -f arg_name=selkies-todesk \
  -f arg_aliyunurl=registry.cn-hangzhou.aliyuncs.com \
  -f arg_aliyunuser=jcleng
```

产物：`registry.cn-hangzhou.aliyuncs.com/jcleng/gitbuild-selkies-todesk:latest`。
该 workflow 会 `git clone` 本仓库后直接 `docker build`，**不传 build-arg**，
因此它依赖 Dockerfile 里的默认取包地址（IA 快照）。

### 方式二：本仓库 workflow（推 GHCR）

推送 `Dockerfile` / `root/**` 到 `main` 会自动触发；也可手动带上 tag：

```bash
gh workflow run build.yml --repo jcleng/selkies-todesk -f image_tag=latest
gh run list  --repo jcleng/selkies-todesk --workflow build.yml --limit 3
gh run watch <run-id> --repo jcleng/selkies-todesk
```

产物：`ghcr.io/jcleng/selkies-todesk:latest`。

## 镜像与构建记录

| 时间(UTC) | Run ID | 结果 | 产物 |
| --- | --- | --- | --- |
| 2026-11-01T05:49Z | [`41278385162`](https://github.com/jcleng/selkies-todesk/actions/runs/41278385162) | success | **`v1.1.0`** / `:4.9.7.0`（含 LXDE + `todesk-raise` + 移除 `lxpolkit`）<br>manifest `sha256:fe1c2043db549ed6943a0f2068f74685d294ce90ff1b6c37e3f4805f8ca45b97`<br>→ Release [v1.1.0](https://github.com/jcleng/selkies-todesk/releases/tag/v1.1.0)<br>ACR 同内容：`gitbuild-selkies-todesk:latest` `sha256:7d1a85910747dafba151f0e84a920463008fec51fc77d13194faed475d0d37f4` |
| 2026-11-01T03:37Z | [`41269455700`](https://github.com/jcleng/selkies-todesk/actions/runs/41269455700) | success | **`v1.1.0`** / `:4.9.7.0`<br>manifest `sha256:d1f2cbeb6b59be5815596050624f7727cbec358bbef0172d860928662903f621`<br>（LXDE 桌面版本，待运行验证） |
| 2026-11-01T03:21Z | [`41268887326`](https://github.com/jcleng/selkies-todesk/actions/runs/41268887326) | success | 首次 LXDE 构建：`latest` / `:4.9.7.0`<br>manifest `sha256:3393f1b8d824e295cf0b7c390d0fa5c7a2eb29325334c701f1eaf5d4c3cbff60` |
| 2026-10-31T07:44Z | [`41181795843`](https://github.com/jcleng/selkies-todesk/actions/runs/41181795843) | success | **`v1.0.0`** / `:4.9.7.0`<br>manifest `sha256:ad4e15872b45c7387da3a1916a654d79699257c359342e08a6094199dd2693b5`<br>→ Release [v1.0.0](https://github.com/jcleng/selkies-todesk/releases/tag/v1.0.0) |
| 2026-10-31T06:28Z | [`41176746928`](https://github.com/jcleng/selkies-todesk/actions/runs/41176746928) | success（7m21s） | 首次构建：`ghcr.io/jcleng/selkies-todesk:latest`<br>digest `sha256:d1b15494bdbcbcbe0aa7a98ccaeb3aacff73b199ca10d09b25ed18ac376bcb70`<br>（基础镜像 digest `sha256:98f0b70470784216d8aef581f2e6fd8bc683cf036e0353c68b855032bde4a1c7`，ToDesk 4.9.7.0 sha256 校验 `OK`） |

`latest` 是滚动 tag；需要可复现请固定 `:v1.0.0` 或 `:4.9.7.0`（二者同一 manifest）。
容器运行已由维护者在本机 `docker run` 验证通过。

## 排障

```bash
# 服务是否在跑 / 为什么没起来
docker exec -it selkies-todesk systemctl status todeskd.service
docker exec -it selkies-todesk tail -n 100 /var/log/todesk/service_*.log

# 客户端日志
docker exec -it selkies-todesk tail -n 100 /config/.local/share/todesk/Logs/client_*.log

# 官方排障配方（重置服务配置）
docker exec -it selkies-todesk bash -lc \
  'systemctl stop todeskd.service && \
   [ -f /opt/todesk/config/config.ini ] && mv /opt/todesk/config/config.ini /opt/todesk/config/config.ini.bak; \
   systemctl start todeskd.service'

# 会话/应用是否起来了（LXDE：lxsession + lxpanel + pcmanfm + ToDesk）
docker exec -it selkies-todesk systemctl list-units --failed
docker exec -it selkies-todesk pgrep -a -f 'ToDesk|lxsession|lxpanel|pcmanfm'
```

常见症状：

| 症状 | 原因 / 处理 |
| --- | --- |
| 网页桌面黑屏、只有鼠标 | 会话被切到 Wayland。确认 `PIXELFLUX_WAYLAND=false` |
| ToDesk 窗口起来但提示「服务未启动」 | `todeskd.service` 没跑；看上面 `systemctl status` |
| 关掉窗口后找不回来 | ToDesk 缩到了托盘。托盘由 `lxpanel` 的 system tray 插件提供，看任务栏右侧 |
| ToDesk 一启动就是最小化的 / 点一下就缩 | ToDesk 发现托盘可用后会把自己缩进托盘。`todesk-session` 已后台跑 `todesk-raise` 把它拉出来；若仍缩，`docker exec -u abc -e DISPLAY=:1 selkies-todesk /usr/local/bin/todesk-raise`，日志在 `/config/.local/share/todesk-raise.log` |
| 点任务栏上已激活的 ToDesk 按钮会缩回去 | 这是 taskbar 的正常语义（点已激活窗口 = 最小化），不是 bug |
| 弹出 `no session for pid NNNN` 的错误窗口 | lxsession 拉起的 polkit 认证代理 `lxpolkit`。容器里的桌面进程不属于任何 logind session（`loginctl list-sessions` 为空），polkit 无法把 agent 的 PID 映射到 session。镜像已移除 `/usr/bin/lxpolkit`；旧镜像可先 `docker exec selkies-todesk pkill -x lxpolkit` 让弹窗消失 |
| 桌面只有壁纸，没任务栏/开始菜单 | `lxpanel` 没起（`pgrep -a lxpanel`）。看 `/config/.local/share/xorg` 或 `journalctl -u selkies-de` 里 `startlxde` 的报错；也可能是 `/config/.config/lxsession/LXDE/autostart` 被改坏了（删掉该文件重启即可回退到镜像内置项） |
| 开始菜单里找不到 ToDesk | 桌面数据库缓存未刷新：`docker exec ... update-desktop-database /usr/share/applications`，再重启会话 |
| 日志刷 `can't open /dev/dri/renderD128` | 容器无 Intel 渲染节点，`todesk-session` 已不再强设 `iHD`；`todeskd.service` 里仍保留官方的 `LIBVA_DRIVER_NAME=iHD`，可加 drop-in 覆盖 |
| 视频卡 | 双重编码；调 Selkies 的 `SELKIES_*` 编码参数，或降低 ToDesk 画质 |
| 没有声音 | 主控端一般不需要；Selkies 的 PulseAudio 与 ToDesk 的 `libpulse` 已装 |

## 设计取舍（为什么这么做）

- **`dpkg-deb -x` 解包，不跑 `dpkg -i`**：官方 `postinst` 会
  `systemctl daemon-reload && systemctl enable --now todeskd`，而构建期 systemd 未运行，必然失败。
  这也是 Nixpkgs / AUR / Gentoo 三家的共同做法。
- **enable 用仓库自带的 `multi-user.target.wants` 软链**，不在构建期 `systemctl enable`，
  与 `selkies-base` 的约定一致。
- **`todeskd.service` 逐字节照抄官方 deb**（已 `diff` 验证），只把它纳入版本控制便于 review。
- **桌面用 LXDE（`--no-install-recommends`）**：底包默认只起裸 `openbox-session` ——
  一个没有任务栏、没有开始菜单、没有文件管理器的空桌面，ToDesk 缩到托盘后就找不回来了。
  换成 `lxde-core` 后：`lxpanel`（任务栏 + 开始菜单 + system tray）、`pcmanfm`（桌面/文件管理）、
  `lxterminal`（终端），而 `openbox` **仍然是窗口管理器**（`desktop.conf` 里
  `window_manager=openbox-lxde`）—— 这就是 LXDE 的标准构成，不是把 openbox 删掉。
  依赖体积：相对裸 openbox 只多 38 个小包（无 GNOME/KDE 库，无 `xscreensaver`），
  而不是 `lxde`／`task-lxde-desktop` 那种把办公套件也拖进来的大礼包。
- **去掉 `stalonetray`**：`lxpanel` 自带 system tray，再拉一个托盘守护进程是重复的。
- **移除 `lxpolkit`**：lxsession 会把它当 polkit 认证代理拉起来，但容器里的桌面进程没有
  logind session（`loginctl list-sessions` 为空），polkit 注册 agent 时无法完成
  PID→session 映射，于是报 `no session for pid NNNN` 并弹出错误窗口。容器内又没有
  需要 polkit 授权的场景（没装 udisks2 做挂载，关机走 systemd），所以直接删掉二进制。
  注意 `polkit/command=lxpolkit` 是 lxsession 首次运行写进 `/config/.config/lxsession/LXDE/desktop.conf`
  的，改镜像里的 `/etc/xdg` 默认值无效，只能动 `/usr/bin/lxpolkit`。
- **`todesk-raise` 的存在理由**：托盘一旦可用，ToDesk 被会话自动启动后会
  把自己缩进托盘（`WM_STATE=Iconic`）。在本地桌面上这是“开机自启后不挡事”，
  在网页桌面里却等于“打开就看不见”。所以启动后主动 `windowactivate` 把主窗口拉出来；
  实测拉出一次后会稳定保持 `Normal`，不会反复缩。
- **`RESTART_APP` 保持关闭**：底包 watchdog 把监视路径写死为
  `~/.config/openbox/autostart`，在 LXDE 下该文件不参与启动；开了只会每秒空跑。
- **不强制 `LIBVA_DRIVER_NAME=iHD`**：容器里通常没有 `/dev/dri/renderD128`，
  强行指定只会刷一遍失败日志再回落软编解码。

## 许可

本仓库只包含构建脚本与配置。ToDesk 客户端是海南有趣科技有限公司的闭源软件，
版权归其所有，镜像内使用需遵守其最终用户协议；本仓库不转售、不再分发其安装包
（默认从 Internet Archive 上已存的官方 URL 响应获取）。

## 参考

- 官方 Linux 下载页 <https://www.todesk.com/linux.html>
- `selkies-base` <https://github.com/jcleng/selkies-base>
- AUR `todesk-bin`（版本与 sha256 权威记录）<https://aur.archlinux.org/packages/todesk-bin>
- Nixpkgs `pkgs/by-name/to/todesk`（FHS/bwrap 容器化参考）
- `gentoo-zh/overlay` `net-misc/todesk`（依赖闭包与 systemd/elogind 处理）
- 调研笔记：`RESEARCH-todesk-container.md`
