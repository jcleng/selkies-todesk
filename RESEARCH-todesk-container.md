# ToDesk on Linux / 容器化封装 — 全网与 GitHub 调研

调研时间：2026-10-31（走本地代理 `http://127.0.0.1:20171`，GitHub 侧用 `gh`）
目标：确认是否已有「Linux 上的 ToDesk」/「ToDesk 容器镜像」现成方案，评估用 `selkies-base` 封装的可行性。

---

## 1. 结论先说

**没有现成的 ToDesk Docker/容器镜像。** 但有一批高质量的「非官方重打包」实践（Nix / AUR / Gentoo / AppImage），
可以直接把它们的依赖清单、systemd 单元处理、CDN 反爬兜底策略原样搬到容器里。

| 检索面 | 结果 |
| --- | --- |
| GitHub repo search `todesk docker` / `todesk container` | **0 条** |
| GitHub repo search `todesk` | 415 条，全是「仿制远控 / 密码提取 / 规则列表」，无容器化 |
| GitHub code search（`gh search code`，需 token）`todesk --filename Dockerfile` | 全部是 *Autodesk* 误命中，**无一条真 ToDesk** |
| GitHub code search `ToDesk_Service` | 命中 nixpkgs、gentoo-zh overlay、AUR 镜像、AppImage 打包脚本、Clash 规则、安全研究文档 |
| Docker Hub `query=todesk` | 65 个仓库，唯一相关的是 `esangs123/todesk`：一段 CentOS `rpm -Uvh todesk_4.1.0` 的安装说明（不是镜像） |
| Gitee `search/repos?q=todesk` | 68 个仓库，全是一键安装脚本 / APK 下载站 / 仿 ToDesk 客户端，**无容器** |
| AUR | `todesk-bin`(4.9.7.0)、`todesk-appimage`(4.8.5.1)、`todesk-enterprise-client-bin`、`todesk-enterprise-host-bin` |
| Bing / DDG 全网中文搜索 | 只有 ToDesk 官网 SEO 页面，无「容器里跑 ToDesk」的技术文章 |
| 官方网页版远控 | 不存在（官网只有下载版；`web.todesk.com` 无服务） |

---

## 2. 可复用的既有实践（按价值排序）

### 2.1 你自己 2023 年的草稿 —— 私有仓库 `jcleng/monit`
`docker/todesk/docker-compose.yml` + `readme.md`：`library-ubuntu:20.04` + `xtigervnc(:9)` + `geek1011/easy-novnc`，
容器内 `dpkg -i todesk-v4.8.5.1-amd64.deb`，手工 `DISPLAY=:9` 起服务。readme 已列出踩过的依赖：

```
libxcb-randr0 libxcb-xfixes0 libgbm1 libglu1-mesa-dev libegl1
libxcb-keysyms1 libxcb-util1 libxcb-xkb1 libnss3 fuse libfuse2
fonts-wqy-zenhei fonts-wqy-microhei
mkdir -p /usr/share/alsa/        # 否则 ToDesk_Service 起不来
/opt/todesk/bin/ToDesk_Service   # 手工起守护进程
todesk                           # 手工起 GUI
```

### 2.2 NixOS/nixpkgs `pkgs/by-name/to/todesk/package.nix`（最接近「容器化」的实现）
- `dpkg -x` 解包官方 deb（**不跑 postinst**），把 `/opt/todesk/bin` 挪到 `$out/bin`，补 `/opt/todesk/config` 空目录，
  并用 `libayatana-appindicator3.so.1` 顶掉包内 `libappindicator3.so.1`。
- 用 `buildFHSEnv`（bubblewrap FHS 沙箱）运行，`extraBwrapArgs = ["--tmpfs /opt/todesk" ...]`，
  并**绑定挂载** `/var/lib/todesk -> /opt/todesk/config`、`/etc/todesk` —— 明确说明这些路径必须是真实目录，软链接无效。
- 入口判定：`$0 = service` → `ToDesk_Service`，否则 → `ToDesk`（同一个包多入口，和 AppImage 思路一致）。

### 2.3 gentoo-zh/overlay `net-misc/todesk`（ebuild 已到 **4.9.8.1**）
- `SRC_URI` 直接走 **web.archive.org 快照**（因为官方 CDN 有反爬，见 §4）。
- 完整 `RDEPEND`：glib2 nspr nss libglvnd libpng libpulse mesa(gbm) **pipewire** dbus **fuse:0** libudev zlib
  cairo gdk-pixbuf gtk3 libdrm libX11 libxcb libXcomposite libXdamage libXext libXfixes libXi libXrandr libXtst
  libXxf86vm pango xcb-util xcb-util-keysyms xcb-util-wm。
- 无 systemd 时用 `patchelf --replace-needed libsystemd.so.0 libelogind.so.0` 改三个二进制 → 印证 ToDesk **硬依赖 libsystemd**。
- `systemd_dounit etc/systemd/system/todeskd.service`；`RESTRICT="strip"`。

### 2.4 `nitaishi520/todesk-appimage`（10★，2026-03 活跃）
deb → AppImage，README 声称修好「后台服务未启动 / 二维码不显示 / 进程残留」；`build.sh` 里的 AppRun 就是
`ToDesk_Service` → `ToDesk_Session` → `ToDesk` 的拉起顺序 + `GDK_BACKEND=x11` + `LIBVA_*`。

### 2.5 `newyorkthink/linux-packaging/todesk`（工程化最完整）
- 版本/URL/sha256 **全部从 AUR `.SRCINFO` 动态读取**，不写死；
- 官方 CDN 返回 HTML 时**只允许退回 Internet Archive 同一 URL 的快照**，且必须 sha256 完全一致；
- 明确保留官方 `/opt/todesk` 布局、`!strip`、补 `config` 空目录；额外补 pulseaudio、IBus/Fcitx5 中文输入模块、独立 `zh_CN.UTF-8` locale；
- 不写死 `LIBVA_DRIVER_NAME=iHD`（宿主 GPU 决定）。

### 2.6 同类「闭源国产 GUI 应用塞进 Selkies」范式
`nickrunning/wechat-selkies`、`seansuny/wechat-selkies`（Docker Hub 有镜像）：
`FROM ghcr.io/linuxserver/baseimage-selkies:ubuntunoble` + 一长串 `libxcb-*/libnss3/libgbm1` 依赖 + `dpkg -i` 官方 deb + autostart。
和本次要做的事结构完全同构，可直接借它的 Dockerfile 骨架。

### 2.7 其他相关但非容器
`bytehola/todesk-silently`（127★，Windows 静默运行补丁，思路可参考）、`huoguozhang/my-toDesk`（仿制品）、
安全研究方向 `GhostWolf` / `FindToDeskPass` / `sundeskQ`（说明 Windows 端凭据可从内存提取，Linux 端无对应工具）。

---

## 3. ToDesk Linux 一手事实（我下载了官方 deb 4.8.5.1 并解包验证）

**下载与版本**
- 命名规律：`https://dl.todesk.com/linux/todesk-v<ver>-{amd64,arm64}.deb`，另有 `-x86_64.rpm`、`-c7-x86_64.rpm`、
  `-uos/-kylin/-nfschina` 变体、Arch 的 `.pkg.tar.zst`、armv7l deb。
- 官网 Linux 页当前给出：**amd64 deb = 4.9.8.1**，**arm64 deb = 4.8.5.1**，AUR 跟到 4.9.7.0。
- 官方支持面：统信UOS / 麒麟 / 方德 / Debian / Ubuntu / Mint / Arch / Fedora / CentOS / RedHat / 树莓派4 (armv7)。

**包内结构**
```
/opt/todesk/bin/ToDesk            91 MB  GUI（Qt，需 X11）
/opt/todesk/bin/ToDesk_Service    48 MB  守护进程，systemd 服务
/opt/todesk/bin/ToDesk_Session    48 MB  会话组件（服务按需拉起）
/opt/todesk/bin/CrashReport        4 MB
/opt/todesk/bin/libzrtc.so         57 MB  自研 ZeroSync 传输
/opt/todesk/bin/libmfx*,libva*,iHD_drv_video.so  35 MB  Intel 硬编解码（自带）
/opt/todesk/res/                          图标资源
/usr/local/bin/todesk                      启动包装脚本
etc/systemd/system/todeskd.service
usr/share/applications/todesk.desktop
```

**`todeskd.service` 原文**
```ini
[Unit]
Description=ToDesk Daemon Service
After=network-online.target
Before=nss-lookup.target
Wants=network-online.target nss-lookup.target

[Service]
Environment="LIBVA_DRIVER_NAME=iHD"
Environment="LIBVA_DRIVERS_PATH=/opt/todesk/bin"
ExecStart=/opt/todesk/bin/ToDesk_Service
ExecStop=/bin/kill -SIGINT $MAINPID
Restart=on-failure
RestartSec=3s
User=root

[Install]
WantedBy=multi-user.target
```

**`/usr/local/bin/todesk`**（GUI 入口的环境变量，容器里必须照抄）
```bash
export TODESK_PACK_NAME=todesk
export LIBVA_DRIVER_NAME=iHD
export LIBVA_DRIVERS_PATH=/opt/todesk/bin
export GDK_BACKEND=x11
/opt/todesk/bin/ToDesk &
```

**真实动态库依赖**（`control` 只写 `libgtk-3-0`，不可信；以下是四个二进制的 `NEEDED` 并集）
```
libEGL libGL libgbm libX11 libXext libXfixes libXi libXrandr libcairo libpango libpangocairo
libgdk_pixbuf libglib/libgobject/libgio/libgdk-3/libgtk-3 libpng16
libxcb libxcb-randr libxcb-shm libxcb-xfixes libxcb-xkb libxcb-keysyms libxcb-util
libsystemd libudev libkmod libzrtc libzulerLog libc/libm/librt/libpthread/libdl/libstdc++/libgcc_s
```
→ Debian 侧需装：`libgl1 libegl1 libgbm1 libx11-6 libxext6 libxfixes3 libxi6 libxrandr2 libcairo2
libpango-1.0-0 libpangocairo-1.0-0 libgdk-pixbuf-2.0-0 libgtk-3-0 libpng16-16t64 libxcb1 libxcb-randr0
libxcb-shm0 libxcb-xfixes0 libxcb-xkb1 libxcb-keysyms1 libxcb-util1 libsystemd0 libudev1 libkmod2
libnss3 libnspr4 libfuse2 fonts-wqy-zenhei`（另需 `alsa` 目录占位、`xdg-utils`、`libayatana-appindicator3-1`）。

**安装脚本行为（对容器化最关键）**
- `postinst`：建 `/opt/todesk/config` → `systemctl daemon-reload && systemctl enable todeskd && systemctl start todeskd`。
  **这会让 `docker build` 里的 `dpkg -i` 直接失败**（构建阶段没有 systemd）。→ 必须走 `dpkg -x` 解包（Nix/AUR 都这么做），
  或在 build 阶段临时放 `/usr/sbin/policy-rc.d` 返回 101。
- `preinst` 会把旧 `config.ini` 备份到 `/opt/todesk/config.ini` 再恢复（升级保配置）。
- 运行期可写路径：`/opt/todesk/config/config.ini`(0666)、`/etc/todesk`、`/var/lib/todesk`、`/var/log/todesk/service_*.log`、
  `~/.local/share/todesk/`（客户端日志 `Logs/client_*.log`）、`~/.config/autostart/todesk.desktop`。
- 官方排障命令（照抄官网 Linux 页）：
  `systemctl stop todeskd; mv /opt/todesk/config/config.ini{.bak,}; systemctl start todeskd`；
  彻底重置：`rm /opt/todesk/config/config.ini`。

---

## 4. 唯一的硬障碍：官方 CDN 反爬

`dl.todesk.com` 挂在 **Tencent Cloud EdgeOne** 后面。直接 `curl` 拿到的不是 deb，而是 JS 挑战页：

```
__tst_status=... ; EO_Bot_Ssid=...      →  再请求得到 "Security Verification" 页
（TEOCaptchaWidget-global.js, appid=1007224932）
```
带 cookie / referer / UA 都绕不过（需要真人点验证码）。**所以 Dockerfile 里不能写死官方 URL。**

可用的自动化取包路径（已实测）：

| 方案 | 状态 |
| --- | --- |
| 本地下载 deb 后 `COPY` / 挂载（你 monit 里的做法） | ✅ 最稳，可锁 sha256 |
| Internet Archive 快照：`https://web.archive.org/web/<ts>id_/https://dl.todesk.com/linux/todesk-v4.9.7.0-amd64.deb` | ✅ 实测 `HTTP 200`，`content-length 113423288`，与 AUR `sha256 = e6aee6f7fecd67a9bcec00b763afa2e2b663c5b9b9375db9d60a9081c09acf4b` 对齐 |
| 第三方镜像：`nitaishi520/todesk-appimage` Release 里的 `todesk-v4.8.5.1-amd64.deb`（108 MB，已验证可下、可解包） | ✅ 但版本旧 |
| 推到自有 registry / 对象存储（`registry.cn-hangzhou.aliyuncs.com/jcleng/...`） | ✅ 内网构建最快 |

---

## 5. 用 `selkies-base` 封装的可行性判断

`selkies-base` 现状（真 systemd 作 PID 1、Xorg + Selkies WebRTC、`APP`/`APP_CLI` 决定会话里跑什么、`--privileged`）
和 ToDesk 的需求**几乎逐项对上**：

| ToDesk 需要 | selkies-base 是否具备 |
| --- | --- |
| systemd（`libsystemd` + `todeskd.service`，`systemctl enable`） | ✅ PID 1 就是 systemd，装 unit 直接 `systemctl enable --now todeskd` |
| root 权限跑守护进程 | ✅ 容器 `--privileged` |
| X11 显示 | ✅ `selkies-xorg.service`；**但必须 `PIXELFLUX_WAYLAND=false`**（默认 `true` 走 labwc/XWayland，ToDesk 只认 `GDK_BACKEND=x11` 且采集 X screen，Wayland 下极可能黑屏） |
| D-Bus / PulseAudio | ✅ `selkies-dbus.service`、`selkies-pulseaudio.service` |
| 中文与输入法 | 需补 `fonts-wqy-*` / `fcitx5`（你镜像里已有中文 locale 变量） |
| 配置持久化 | 把 `/opt/todesk/config`、`/etc/todesk`、`/var/lib/todesk`、`/var/log/todesk` 做成 **真实目录 + 挂载**（Nix 明确警告软链接无效），或 rsync 到 `/config/todesk` |
| 设备码/临时密码可见 | Selkies 网页里能看到 ToDesk 窗口 → 直接在浏览器里扫码/读 ID；或 `ToDesk --help` / `config.ini` 取设备码（未验证 CLI 是否能无 GUI 输出设备码） |

**落地骨架**（下一步可实现，约 60 行）：
1. `FROM ghcr.io/linuxserver/baseimage-selkies:debiantrixie`（与你 selkies-base 同底）；
2. `dpkg -x todesk_*.deb` → 拷 `/opt/todesk`、`/usr/local/bin/todesk`、`todeskd.service`、desktop；建 `config` 空目录 + alsa 占位；
3. `apt install` §3 的依赖清单；
4. `systemctl enable todeskd.service`（镜像内 systemd 单元，运行时生效）；
5. `ENV APP=/usr/local/bin/todesk`、`PIXELFLUX_WAYLAND=false`、`TITLE=ToDesk`；
6. `VOLUME`/bind mount 那四个可写路径；`docker-compose` 用 `--privileged` + `/run` `/tmp` tmpfs。

---

## 6. 一个需要先定的问题：容器里 ToDesk 当被控还是主控？

- **A. 被控端（推荐）**：远端 ToDesk 客户端 → ToDesk 中继 → 容器里的 `todeskd` → 容器虚拟桌面。链路只一跳编码，延迟正常；
  等于「Selkies 之外再给容器开一条手机/Windows 可连的通道」，也解决 Selkies 需要公网入口/内网穿透的痛点。
- **B. 主控端**：你在浏览器里看 Selkies 桌面 → 里面用 ToDesk 去控制别人 = **双重远程**（ToDesk 编码 + Selkies WebRTC 再编码），
  延迟叠加、画质两次损失，只在「本机系统装不了 ToDesk 客户端」时才值得。
- **C. 只要一个 Linux ToDesk 可用环境**（验证/逆向/测试）：那么用 selkies 封装确实是最省事的隔离方式，A/B 都能跑。

## 7. 替代方案（若目的只是「浏览器里被远程控制」）
- **Selkies 本身**已经是浏览器远控桌面，不需要 ToDesk 再叠一层（除非必须让对端用 ToDesk App 连进来）。
- **RustDesk**：有官方 `rustdesk-server`（hbbs/hbbr）Docker 镜像，且客户端容器化在社区里成熟得多；Linux 端开源、无 CDN 反爬、可自建中继，容器化阻力远小于 ToDesk。
- **GoDesk / billd-desk / QuickDesk / RdViewer**：GitHub 上活跃的自研远控，部分支持自建服务器（billd-desk 9k★）。
