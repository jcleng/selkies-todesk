# syntax=docker/dockerfile:1
#
# Selkies web desktop running the ToDesk Linux client as a CONTROLLER (主控端):
# 浏览器里操作 ToDesk 窗口去远程控制别的机器。
#
# 基于 jcleng/selkies-base（真 systemd 作 PID 1），因此 ToDesk 自带的
# todeskd.service 可以原样运行，无需任何 s6/手工拉起 hack。
# x86_64 only by design（与 selkies-base 一致）。

# 基础镜像默认用 selkies-base（已验证 ACR 仓库公开可 匿名 pull：manifest HTTP 200）。
# 若 CI 拉国内 ACR 太慢/超时，可在构建时用 build-arg 指向同步到其它 registry 的同名镜像；
# 但不要用 ghcr.io/linuxserver/baseimage-selkies 代替，本镜像的 systemd 单元与
# todeskd enable 产物是建立在 selkies-base 的「systemd 作 PID 1」结构上的。
ARG BASE_IMAGE=registry.cn-hangzhou.aliyuncs.com/jcleng/gitbuild-selkies-base:latest
FROM ${BASE_IMAGE}

# set version label
ARG BUILD_DATE
ARG VERSION
LABEL build_version="version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="jcleng"

# ---- ToDesk 官方 Linux 包 --------------------------------------------------
# 官方下载页： https://www.todesk.com/linux.html
#   Debian/Ubuntu/Mint (x64) -> https://dl.todesk.com/linux/todesk-v<VER>-amd64.deb
#
# 官方 CDN 在腾讯云 EdgeOne 之后：构建期直连只会拿到 JS 挑战 + TCaptcha
# 人机验证页（`EO_Bot_Ssid` / "Security Verification"），curl/wget 无法自动下载
# （已实测：直连与走代理都只返回 986 字节的挑战脚本，带 cookie/referer/UA 也一样）。
#
# 取包顺序：
#   1. 构建上下文 vendor/*.deb（本地构建、内网构建、或 CI 里预先放好）；
#   2. 否则从 Internet Archive 拉官方 URL 的历史快照（由 archive.org 存档，
#      本仓库不自行分发 ToDesk 二进制）。
# 两条路径都必须通过 sha256 校验；该值与 AUR `todesk-bin` 记录的官方包一致，
# 因此可证明镜像里用的是未经篡改的官方原文件。
# 升级步骤见 README「更新 ToDesk 版本」。
ARG TO_DESK_VERSION=4.9.7.0
ARG TO_DESK_DEB_URL=https://web.archive.org/web/20260930015923id_/https://dl.todesk.com/linux/todesk-v4.9.7.0-amd64.deb
ARG TO_DESK_SHA256=e6aee6f7fecd67a9bcec00b763afa2e2b663c5b9b9375db9d60a9081c09acf4b

# ---- session ---------------------------------------------------------------
# ToDesk 是纯 X11 客户端（包装脚本里写死 GDK_BACKEND=x11）。labwc/Wayland 会话下
# 它只能落在 XWayland 里，托盘与全局快捷键不可靠，因此本项目强制回退 Openbox/X11。
# APP 指向本镜像的启动器，参数仍可用 APP_CLI 追加。
ENV TITLE=ToDesk \
    APP=/usr/local/bin/todesk-session \
    PIXELFLUX_WAYLAND=false \
    container=docker

# vendor/ 里放不放 deb 都能构建：.gitkeep 保证目录恒存在（否则 COPY 会因缺源失败），
# 真正的 deb 由 .gitignore 排除，只用于本地构建。
# 必须在下面的 RUN 之前 COPY：RUN 里要先看 /tmp/src 有没有本地 deb，没有才回退下载。
COPY vendor /tmp/src

RUN \
  echo "**** resolve package names (Debian t64 renaming differs by suite) ****" && \
  apt-get update && \
  pick() { for c in "$@"; do if apt-cache show "$c" >/dev/null 2>&1; then printf ' %s' "$c"; return 0; fi; done; printf ' %s' "$1"; } && \
  DEPS="" && \
  DEPS="$DEPS$(pick libgtk-3-0t64 libgtk-3-0)" && \
  DEPS="$DEPS$(pick libgdk-pixbuf-2.0-0 libgdk-pixbuf2.0-0)" && \
  DEPS="$DEPS$(pick libasound2t64 libasound2)" && \
  DEPS="$DEPS$(pick libfuse2t64 libfuse2)" && \
  DEPS="$DEPS$(pick libayatana-appindicator3-1 libappindicator3-1)" && \
  DEPS="$DEPS$(pick libpng16-16t64 libpng16-16)" && \
  DEPS="$DEPS libegl1 libgl1 libgbm1 libnss3 libnspr4" && \
  DEPS="$DEPS libx11-6 libxext6 libxfixes3 libxi6 libxrandr2 libxrender1 libxss1 libxtst6" && \
  DEPS="$DEPS libxcomposite1 libxdamage1 libxxf86vm1 libxshmfence1" && \
  DEPS="$DEPS libxcb1 libxcb-randr0 libxcb-shm0 libxcb-xfixes0 libxcb-xkb1 libxcb-keysyms1" && \
  DEPS="$DEPS libxcb-util1 libxcb-image0 libxcb-icccm4 libxcb-render-util0 libxcb-shape0" && \
  DEPS="$DEPS libxcb-sync1 libxcb-glx0 libxkbcommon0 libxkbcommon-x11-0" && \
  DEPS="$DEPS libpulse0 libasyncns0 libsndfile1" && \
  DEPS="$DEPS libcairo2 libpango-1.0-0 libpangocairo-1.0-0 libatk1.0-0 libatk-bridge2.0-0" && \
  DEPS="$DEPS libcups2 libdrm2 libudev1 libsystemd0 libkmod2 libglib2.0-0 libfontconfig1" && \
  DEPS="$DEPS libdbus-1-3 libatomic1 libstdc++6" && \
  DEPS="$DEPS stalonetray xdg-utils desktop-file-utils" && \
  DEPS="$DEPS fonts-wqy-zenhei fonts-wqy-microhei fonts-noto-cjk" && \
  echo "**** install packages: $DEPS ****" && \
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $DEPS && \
  echo "**** fetch ToDesk deb (官方原包, 校验 sha256) ****" && \
  if ls /tmp/src/todesk-*.deb >/dev/null 2>&1; then \
      cp "$(ls -1 /tmp/src/todesk-*.deb | head -1)" /tmp/todesk.deb && \
      echo "     使用构建上下文 vendor/ 里的本地 deb"; \
  else \
      curl -fsSL --retry 3 --retry-delay 5 -o /tmp/todesk.deb "${TO_DESK_DEB_URL}" && \
      echo "     从 TO_DESK_DEB_URL 下载"; \
  fi && \
  echo "${TO_DESK_SHA256}  /tmp/todesk.deb" | sha256sum --check --strict && \
  echo "     sha256 校验通过: ToDesk $(dpkg-deb -f /tmp/todesk.deb Version)" && \
  echo "**** unpack: dpkg-deb -x 只解 data.tar, 不执行 postinst ****" && \
  echo "     (官方 postinst 会 systemctl enable/start todeskd, 构建期 systemd 未运行会失败)" && \
  dpkg-deb -x /tmp/todesk.deb / && \
  echo "**** todesk 运行期目录: 必须是真实目录, 软链接无效 ****" && \
  mkdir -p /opt/todesk/config /etc/todesk /var/lib/todesk /var/log/todesk && \
  echo "**** 官方 readme 的坑: 缺 /usr/share/alsa 会让 ToDesk_Service 起不来 ****" && \
  mkdir -p /usr/share/alsa && \
  echo "**** config.ini 由服务以 root 生成, GUI 以 abc 运行需要能写 -> 目录放开 ****" && \
  chmod 0777 /opt/todesk/config && \
  echo "**** 兜底: 官方 deb 不带 /opt/todesk/res 权限与 bin 可执行位 ****" && \
  chmod 0755 /opt/todesk/bin/ToDesk /opt/todesk/bin/ToDesk_Service \
             /opt/todesk/bin/ToDesk_Session /opt/todesk/bin/CrashReport \
             /usr/local/bin/todesk && \
  echo "**** web desktop icon from the official package ****" && \
  { install -Dm644 /usr/share/icons/hicolor/256x256/apps/todesk.png \
      /usr/share/selkies/www/icon.png || :; } && \
  echo "**** cleanup ****" && \
  apt-get autoclean && \
  rm -rf \
    /tmp/todesk.deb \
    /config/.cache \
    /var/lib/apt/lists/* \
    /var/tmp/* \
    /tmp/*

# add local files (todeskd unit + enable 产物 + 会话启动器)
COPY /root /

# make helper scripts executable regardless of checkout file modes
RUN chmod +x /usr/local/bin/todesk-session

# ports and volumes（继承 selkies-base 的 3001；ToDesk 主控端全部出站连接, 无需额外端口）
EXPOSE 3001

VOLUME /config

# stop systemd gracefully on `docker stop`
STOPSIGNAL SIGRTMIN+3

# systemd as PID 1
ENTRYPOINT ["/sbin/init"]
CMD ["--system", "--unit=multi-user.target"]
