//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
//@ pragma Env QT_SCALE_FACTOR=1

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.systemSettings

ApplicationWindow {
    id: root
    property real contentPadding: 8

    readonly property var groups: [
        {
            name: Translation.tr("Hardware"),
            pages: [
                { name: Translation.tr("Displays"), icon: "monitor", description: Translation.tr("Arrangement, modes, colour"), component: "modules/systemSettings/DisplaysPage.qml" }
            ]
        }
    ]
    readonly property var pages: root.groups.reduce((all, group) => all.concat(group.pages), [])
    property string currentComponent: "modules/systemSettings/DisplaysPage.qml"
    readonly property var currentPageData: root.pages.find(page => page.component === root.currentComponent) ?? null

    visible: true
    // The countdown that puts a rejected layout back runs in this process, so
    // closing the window mid-confirmation would leave the session on a
    // configuration nobody agreed to and never write it down either.
    onClosing: {
        if (Displays.awaitingConfirmation)
            Displays.revertDetached();
        // A preview only ever existed to be looked at. Walking away from it is a
        // refusal, not a decision to keep it.
        Displays.discardSdrPreview();
        Qt.quit();
    }
    // Deliberately not translated: it is what a window rule would match on.
    title: "YukiUI System"

    // Stop polling the compositor while the window is not the one in use.
    onActiveChanged: Displays.polling = root.active
    Component.onCompleted: {
        Displays.polling = root.active;
        MaterialThemeLoader.reapplyTheme()
        Config.readWriteDelay = 0
    }

    // Small enough to be usable on a 1366x768 panel; the pages scroll below the
    // width at which they stop fitting side by side.
    minimumWidth: 640
    minimumHeight: 440
    width: 1600
    height: 950
    color: Appearance.m3colors.m3background

    ColumnLayout {
        anchors {
            fill: parent
            margins: root.contentPadding
        }
        spacing: root.contentPadding

        Keys.onPressed: event => {
            const index = root.pages.findIndex(page => page.component === root.currentComponent);
            if (event.modifiers === Qt.ControlModifier) {
                if (event.key === Qt.Key_Tab) {
                    root.currentComponent = root.pages[(index + 1) % root.pages.length].component;
                    event.accepted = true;
                } else if (event.key === Qt.Key_Backtab) {
                    root.currentComponent = root.pages[(index - 1 + root.pages.length) % root.pages.length].component;
                    event.accepted = true;
                }
            } else if (event.key === Qt.Key_Escape) {
                // Never closes out from under a pending confirmation: the
                // countdown lives in this process, and taking the window with it
                // would leave the session on a layout nobody agreed to.
                if (Displays.awaitingConfirmation)
                    Displays.revert();
                else
                    root.close();
                event.accepted = true;
            }
        }

        Item {
            visible: Config.options?.windows.showTitlebar
            Layout.fillWidth: true
            implicitHeight: Math.max(titleRow.implicitHeight, windowControlsRow.implicitHeight)

            RowLayout {
                id: titleRow
                anchors {
                    left: Config.options.windows.centerTitle ? undefined : parent.left
                    horizontalCenter: Config.options.windows.centerTitle ? parent.horizontalCenter : undefined
                    verticalCenter: parent.verticalCenter
                    leftMargin: 12
                }
                spacing: 8

                MaterialSymbol {
                    text: "tune"
                    iconSize: Appearance.font.pixelSize.title
                    color: Appearance.colors.colOnLayer0
                }
                StyledText {
                    color: Appearance.colors.colOnLayer0
                    text: Translation.tr("System")
                    font {
                        family: Appearance.font.family.title
                        pixelSize: Appearance.font.pixelSize.title
                        variableAxes: Appearance.font.variableAxes.title
                    }
                }
            }

            RowLayout {
                id: windowControlsRow
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right

                RippleButton {
                    buttonRadius: Appearance.rounding.full
                    implicitWidth: 35
                    implicitHeight: 35
                    onClicked: root.close()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "close"
                        iconSize: 20
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: root.contentPadding

            SystemNav {
                Layout.fillHeight: true
                groups: root.groups
                currentComponent: root.currentComponent
                onPageSelected: component => root.currentComponent = component
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Appearance.m3colors.m3surfaceContainerLow
                radius: Appearance.rounding.windowRounding - root.contentPadding

                // Clicking the content pane takes focus away from the nav search.
                MouseArea {
                    anchors.fill: parent
                    onPressed: parent.forceActiveFocus()
                }

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.margins: 20
                        Layout.bottomMargin: 0
                        spacing: 12

                        MaterialSymbol {
                            text: root.currentPageData?.icon ?? ""
                            iconSize: 28
                            color: Appearance.colors.colOnLayer1
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                text: root.currentPageData?.name ?? ""
                                font.pixelSize: Appearance.font.pixelSize.title
                                font.weight: 550
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                Layout.fillWidth: true
                                visible: text.length > 0
                                text: root.currentPageData?.description ?? ""
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }

                    Loader {
                        id: pageLoader
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        active: Config.ready
                        source: root.currentPageData?.component ?? ""
                    }
                }
            }
        }
    }
}
