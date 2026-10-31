# v1.0.0 — ToDesk 4.9.7.0 主控端（Selkies 网页桌面）

在 [Selkies](https://github.com/selkies-project/selkies) 网页桌面里运行 **ToDesk Linux 客户端作为主控端**：
浏览器打开网页桌面 → 操作里面的 ToDesk 窗口 → 远程控制别的机器。
基础镜像是 [`jcleng/selkies-base`](https://github.com/jcleng/selkies-base)（真 `systemd` 作 PID 1）。

## 镜像

```bash
docker pull ghcr.io/jcleng/selkies-todesk:v1.0.0
```

| tag | manifest digest |
| --- | --- |
| `v1.0.0` | `sha256:ad4e15872b45c7387da3a1916a654d79699257c359342e08a6094199dd2693b5` |
| `4.9.7.0` | 同上（同一 manifest） |
| `latest` | 滚动 tag |

- 基础镜像：`registry.cn-hangzhou.aliyuncs.com/jcleng/gitbuild-selkies-base:latest`
  （构建时 digest `sha256:98f0b70470784216d8aef581f2e6fd8bc683cf036e0353c68b855032bde4a1c7`）
- ToDesk：`4.9.7.0`（官方 amd64 deb，`sha256=e6aee6f7…09acf4b`，与 AUR `todesk-bin` 记录一致，构建日志校验 `OK`）
- 架构：`linux/amd64`（与 selkies-base 一致，不含 aarch64）

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
  ghcr.io/jcleng/selkies-todesk:v1.0.0
```

浏览器打开 `https://localhost:3001`（自签证书需接受），桌面里就是 ToDesk。

## 这个版本包含什么

- **官方 `todeskd.service` 原样运行**：unit 从官方 deb 逐字节取出并纳入版本控制，
  enable 由镜像自带的 `multi-user.target.wants` 软链完成（构建期不跑 `systemctl enable`）。
- **`dpkg-deb -x` 解包，不执行官方 `postinst`**：官方 `postinst` 会 `systemctl enable --now todeskd`，
  在构建阶段必然失败；这也是 Nixpkgs / AUR / Gentoo 三家的共同做法。
- **依赖闭包自动适配 Debian trixie 的 `t64` 改名**（`libgtk-3-0t64`、`libasound2t64`、
  `libfuse2t64`、`libpng16-16t64` 等，缺失时回退旧名）。
- **`PIXELFLUX_WAYLAND=false`**：ToDesk 是纯 X11 客户端（`GDK_BACKEND=x11`），强制 Openbox/X11 会话。
- **会话启动器 `todesk-session`**：按 `/dev/dri/renderD128` 是否存在决定是否设 `iHD`（避免无显卡机器刷 VA 失败日志）、
  自动补 `stalonetray` 托盘（ToDesk 关窗=缩托盘）、前台 `exec ToDesk`。
- **可写目录均为真实目录**（`/opt/todesk/config`、`/etc/todesk`、`/var/lib/todesk`、`/var/log/todesk`），
  软链接无效（Nixpkgs 经验），用于持久化登录态与设备码；`/usr/share/alsa` 已补齐。
- 中文字体（文泉驿/Noto CJK）、`stalonetray`、`xdg-utils` 已装。

## 已验证

- 镜像构建：GitHub Actions run [`41181795843`](https://github.com/jcleng/selkies-todesk/actions/runs/41181795843) success。
- 容器运行：维护者已在本地 `docker run` 实测，`selkies-todesk` 正常启动（ToDesk GUI 可用）。

## 已知限制

- **双重远程**：被控端画面先 ToDesk 编码传到容器，再 Selkies 编码到浏览器，延迟是两段之和、画质损失两次。
  若只是要「让别人连进这个容器」，用 Selkies 本身即可，不必叠 ToDesk。
- **官方 CDN 反爬**：`dl.todesk.com` 在腾讯云 EdgeOne 之后，`curl` 只拿到 TCaptcha 人机验证页，
  因此镜像构建默认从 Internet Archive 上该官方 URL 的快照取包，并强制 `sha256` 校验；
  也可把 deb 放进构建上下文 `vendor/`（本地/内网构建）或通过 `workflow_dispatch` 传 `todesk_deb_url`。
- 不含 `aarch64` 构建。

## 升级 ToDesk 版本

见仓库 README「更新 ToDesk 版本」：从 <https://www.todesk.com/linux.html> 取 deb → 算 sha256 →
放进 `vendor/`，或用 workflow 输入传 URL/sha256，或改 Dockerfile 顶部三个 `ARG`。

---

完整说明、排障、设计取舍见仓库 [README](https://github.com/jcleng/selkies-todesk#readme)。
ToDesk 客户端为闭源软件，版权归海南有趣科技有限公司所有；本仓库仅分发构建脚本，不转售其安装包。
