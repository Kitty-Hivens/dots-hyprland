pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland

MouseArea {
    id: root
    focus: true

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            ScreenShare.cancel();
            event.accepted = true;
        }
    }

    Connections {
        target: GlobalStates
        function onScreenSharePickerOpenChanged() {
            if (GlobalStates.screenSharePickerOpen)
                root.forceActiveFocus();
        }
    }
    Component.onCompleted: root.forceActiveFocus()

    // A single source tile: live preview on top, icon + label below.
    component PreviewCard: Rectangle {
        id: card
        property var captureSource: null
        property string label: ""
        property string iconSource: ""
        property bool active: true // false when the card's tab is hidden -> stop the live capture
        signal picked

        readonly property bool hovered: cardMouse.containsMouse
        implicitHeight: cardColumn.implicitHeight

        radius: Appearance.rounding.small
        color: card.hovered ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2
        border.width: 1
        border.color: card.hovered ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
        Behavior on border.color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        ColumnLayout {
            id: cardColumn
            anchors.fill: parent
            anchors.margins: 8
            spacing: 6

            Rectangle {
                id: previewFrame
                Layout.fillWidth: true
                Layout.preferredHeight: width * 9 / 16
                radius: Appearance.rounding.verysmall
                color: Appearance.colors.colLayer1
                clip: true

                ScreencopyView {
                    id: preview
                    anchors.fill: parent
                    live: card.active && GlobalStates.screenSharePickerOpen
                    captureSource: card.captureSource
                }

                StyledImage {
                    anchors.centerIn: parent
                    visible: card.captureSource === null && card.iconSource !== ""
                    source: card.iconSource
                    mipmap: true
                    width: 48
                    height: 48
                }

                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: previewFrame.width
                        height: previewFrame.height
                        radius: previewFrame.radius
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                StyledImage {
                    visible: card.iconSource !== ""
                    source: card.iconSource
                    mipmap: true
                    Layout.preferredWidth: 18
                    Layout.preferredHeight: 18
                }
                StyledText {
                    Layout.fillWidth: true
                    text: card.label
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer2
                }
            }
        }

        MouseArea {
            id: cardMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: card.picked()
        }
    }

    StyledRectangularShadow {
        target: bg
    }
    Rectangle {
        id: bg
        anchors.fill: parent
        anchors.margins: Appearance.sizes.elevationMargin
        color: Appearance.colors.colLayer0
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        radius: Appearance.rounding.normal

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12

            // Header
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                MaterialSymbol {
                    text: "screen_share"
                    iconSize: 28
                    color: Appearance.colors.colOnLayer0
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Share your screen")
                    font.pixelSize: Appearance.font.pixelSize.title
                    font.weight: 550
                    color: Appearance.colors.colOnLayer0
                }
                StyledText {
                    text: Translation.tr("Remember choice")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
                StyledSwitch {
                    checked: ScreenShare.allowToken
                    onToggled: ScreenShare.allowToken = checked
                }
            }

            SecondaryTabBar {
                id: tabBar
                Layout.fillWidth: true

                SecondaryTabButton {
                    buttonText: Translation.tr("Screens")
                    buttonIcon: "monitor"
                }
                SecondaryTabButton {
                    buttonText: Translation.tr("Windows")
                    buttonIcon: "select_window"
                }
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: tabBar.currentIndex

                // Screens
                Item {
                    id: screensPage

                    GridView {
                        id: screensGrid
                        readonly property real cw: screensPage.width / 2
                        anchors {
                            top: parent.top
                            bottom: parent.bottom
                            horizontalCenter: parent.horizontalCenter
                        }
                        width: Math.max(1, Math.min(count, 2)) * cw
                        clip: true
                        cellWidth: cw
                        cellHeight: cw * 9 / 16 + 46
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: StyledScrollBar {}

                        model: Quickshell.screens
                        delegate: Item {
                            required property var modelData
                            width: screensGrid.cellWidth
                            height: screensGrid.cellHeight

                            PreviewCard {
                                anchors.fill: parent
                                anchors.margins: 6
                                active: tabBar.currentIndex === 0
                                captureSource: modelData
                                iconSource: ""
                                label: `${modelData.name} (${modelData.width}x${modelData.height})`
                                onPicked: ScreenShare.submit(`screen:${modelData.name}`)
                            }
                        }
                    }
                }

                // Windows
                Item {
                    GridView {
                        id: windowsGrid
                        anchors.fill: parent
                        clip: true
                        cellWidth: width / 3
                        cellHeight: cellWidth * 9 / 16 + 46
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: StyledScrollBar {}

                        model: ScreenShare.windowEntries
                        delegate: Item {
                            required property var modelData
                            width: windowsGrid.cellWidth
                            height: windowsGrid.cellHeight

                            // Match the live toplevel by Hyprland address (xdph gives it in
                            // decimal, HyprlandToplevel.address is hex); fall back to class+title.
                            readonly property var matchedToplevel: {
                                const entries = ToplevelManager.toplevels.values;
                                const addr = parseInt(modelData.address);
                                if (addr) {
                                    for (const t of entries) {
                                        const ta = t.HyprlandToplevel?.address;
                                        if (ta && parseInt(ta, 16) === addr)
                                            return t;
                                    }
                                }
                                for (const t of entries) {
                                    if (t.title === modelData.title && t.appId === modelData.windowClass)
                                        return t;
                                }
                                return null;
                            }

                            PreviewCard {
                                anchors.fill: parent
                                anchors.margins: 6
                                active: tabBar.currentIndex === 1
                                captureSource: parent.matchedToplevel
                                iconSource: AppSearch.iconFor(modelData.windowClass)
                                label: modelData.title.length > 0 ? modelData.title : modelData.windowClass
                                onPicked: ScreenShare.submit(`window:${modelData.id}`)
                            }
                        }
                    }

                    StyledText {
                        anchors.centerIn: parent
                        visible: ScreenShare.windowEntries.length === 0
                        text: Translation.tr("No shareable windows")
                        color: Appearance.colors.colSubtext
                    }
                }
            }

            // Footer
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                RippleButtonWithIcon {
                    materialIcon: "crop"
                    mainText: Translation.tr("Select region...")
                    onClicked: ScreenShare.selectRegion()
                }
                Item {
                    Layout.fillWidth: true
                }
                DialogButton {
                    buttonText: Translation.tr("Cancel")
                    onClicked: ScreenShare.cancel()
                }
            }
        }
    }
}
