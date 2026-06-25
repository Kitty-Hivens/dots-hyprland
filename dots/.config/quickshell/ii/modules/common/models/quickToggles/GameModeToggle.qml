import QtQuick
import qs.modules.common
import qs.services

QuickToggleModel {
    id: root
    name: Translation.tr("Game mode")
    icon: "gamepad"
    toggled: GameMode.engaged
    statusText: !GameMode.engaged ? Translation.tr("Off")
        : (Config.options.gameMode.active ? Translation.tr("On") : Translation.tr("Auto"))
    hasMenu: true
    tooltipText: Translation.tr("Game mode | Right-click to configure")

    mainAction: () => {
        GameMode.setManual(!GameMode.engaged);
    }
}
