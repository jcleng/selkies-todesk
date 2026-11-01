#!/usr/bin/env bash
# Selkies X11 会话入口（由 /etc/s6-overlay/s6-rc.d/svc-de/run 调用）。
#
# 底包原本是 `exec dbus-launch --exit-with-session /usr/bin/openbox-session`
# —— 只有一层光板 openbox：没有任务栏、没有开始菜单、没有文件管理器。
# 这里换成 LXDE 会话：openbox 仍是窗口管理器（见
# /etc/xdg/lxsession/LXDE/desktop.conf 的 window_manager=openbox-lxde），
# 上面再叠 lxpanel（任务栏 + 开始菜单 + 托盘）和 pcmanfm（桌面 + 文件管理）。
#
# 会话里要跑的应用由 /etc/xdg/lxsession/LXDE/autostart 拉起（$APP 语义见
# /usr/local/bin/lxde-app），因此本脚本不再调用 /defaults/autostart。
if [ ! -x /usr/bin/startlxde ]; then
  echo "[startwm] 警告: 没有 startlxde（lxde-core 未装上），回退到裸 openbox-session" >&2
  exec dbus-launch --exit-with-session /usr/bin/openbox-session
fi

# startlxde -> exec lxsession -s LXDE -e LXDE
# 它会先按 desktop.conf 起窗口管理器，再执行 autostart 里的每一项。
exec dbus-launch --exit-with-session /usr/bin/startlxde
