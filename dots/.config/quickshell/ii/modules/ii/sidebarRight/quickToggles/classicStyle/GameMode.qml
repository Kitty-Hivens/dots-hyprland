import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick

QuickToggleButton {
    id: root
    buttonIcon: "gamepad"
    toggled: GameMode.engaged
    onClicked: {
        GameMode.setManual(!GameMode.engaged)
    }
    StyledToolTip {
        text: Translation.tr("Game mode | Right-click to configure")
    }
}
