pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.modules.common

Singleton {
    id: root

    function load() {}

    readonly property bool anyFullscreen: Hyprland.workspaces.values.some(ws =>
        ws.active && ws.toplevels.values.some(t => t.wayland?.fullscreen))

    readonly property bool engaged: Config.options.gameMode.active
        || (Config.options.gameMode.autoOnFullscreen && root.anyFullscreen)

    function setManual(on) {
        if (on === root.engaged) return;
        Config.options.gameMode.active = on;
    }

    readonly property bool visualEngaged: root.engaged && Config.options.gameMode.visual
    onVisualEngagedChanged: root.applyVisual(visualEngaged)
    function applyVisual(on) {
        if (on) {
            Quickshell.execDetached(["bash", "-c",
                `hyprctl --batch "keyword animations:enabled 0; keyword decoration:shadow:enabled 0; keyword decoration:blur:enabled 0; keyword general:gaps_in 0; keyword general:gaps_out 0; keyword general:border_size 1; keyword decoration:rounding 0; keyword general:allow_tearing 1"`])
        } else {
            Quickshell.execDetached(["hyprctl", "reload"])
        }
    }

    Process {
        running: root.engaged && Config.options.gameMode.system
        command: ["gamemoderun", "sleep", "infinity"]
    }

    readonly property bool wallpaperPaused: root.engaged && Config.options.gameMode.wallpaper
    onWallpaperPausedChanged: root.setWallpaperPaused(wallpaperPaused)
    function setWallpaperPaused(paused) {
        Quickshell.execDetached(["bash", "-c",
            `"$HOME/.config/hypr/custom/scripts/video-wallpaper-power.sh" ${paused ? "stop" : "cont"}`])
    }

    Component.onCompleted: {
        if (root.visualEngaged) root.applyVisual(true);
        if (root.wallpaperPaused) root.setWallpaperPaused(true);
    }
}
