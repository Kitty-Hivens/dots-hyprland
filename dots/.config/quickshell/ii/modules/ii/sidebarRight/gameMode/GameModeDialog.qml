import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

WindowDialog {
    id: root
    backgroundHeight: 380

    WindowDialogTitle {
        text: Translation.tr("Game mode")
    }

    WindowDialogSeparator {
        Layout.topMargin: -22
        Layout.leftMargin: 0
        Layout.rightMargin: 0
    }

    Column {
        Layout.topMargin: -16
        Layout.fillWidth: true
        Layout.fillHeight: true

        ConfigSwitch {
            anchors {
                left: parent.left
                right: parent.right
            }
            iconSize: Appearance.font.pixelSize.larger
            buttonIcon: "stadia_controller"
            text: Translation.tr("Enable now")
            checked: GameMode.engaged
            onCheckedChanged: GameMode.setManual(checked)
        }

        ConfigSwitch {
            anchors {
                left: parent.left
                right: parent.right
            }
            iconSize: Appearance.font.pixelSize.larger
            buttonIcon: "blur_on"
            text: Translation.tr("Visual performance")
            checked: Config.options.gameMode.visual
            onCheckedChanged: Config.options.gameMode.visual = checked
            StyledToolTip { text: Translation.tr("No animations, blur, shadows, rounding or gaps; allow tearing") }
        }

        ConfigSwitch {
            anchors {
                left: parent.left
                right: parent.right
            }
            iconSize: Appearance.font.pixelSize.larger
            buttonIcon: "developer_board"
            text: Translation.tr("System GameMode")
            checked: Config.options.gameMode.system
            onCheckedChanged: Config.options.gameMode.system = checked
            StyledToolTip { text: Translation.tr("Hold a Feral GameMode session (CPU performance governor)") }
        }

        ConfigSwitch {
            anchors {
                left: parent.left
                right: parent.right
            }
            iconSize: Appearance.font.pixelSize.larger
            buttonIcon: "motion_photos_paused"
            text: Translation.tr("Pause wallpaper")
            checked: Config.options.gameMode.wallpaper
            onCheckedChanged: Config.options.gameMode.wallpaper = checked
            StyledToolTip { text: Translation.tr("Freeze the video wallpaper on its last frame") }
        }

        ConfigSwitch {
            anchors {
                left: parent.left
                right: parent.right
            }
            iconSize: Appearance.font.pixelSize.larger
            buttonIcon: "fit_screen"
            text: Translation.tr("Auto on fullscreen")
            checked: Config.options.gameMode.autoOnFullscreen
            onCheckedChanged: Config.options.gameMode.autoOnFullscreen = checked
            StyledToolTip { text: Translation.tr("Engage automatically while a window is fullscreen") }
        }
    }

    WindowDialogButtonRow {
        Layout.fillWidth: true

        Item {
            Layout.fillWidth: true
        }

        DialogButton {
            buttonText: Translation.tr("Done")
            onClicked: root.dismiss()
        }
    }
}
