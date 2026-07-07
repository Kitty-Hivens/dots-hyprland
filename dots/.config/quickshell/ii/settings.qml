//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

// Adjust this to make the app smaller or larger
//@ pragma Env QT_SCALE_FACTOR=1

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions as CF

ApplicationWindow {
    id: root
    property string firstRunFilePath: CF.FileUtils.trimFileProtocol(`${Directories.state}/user/first_run.txt`)
    property string firstRunFileContent: "This file is just here to confirm you've been greeted :>"
    property real contentPadding: 8
    property bool showNextTime: false
    // Which desktop family's settings to show, tied to the live panelFamily
    // (reactive): running ii -> Illogical Impulse settings, running Waffle ->
    // Waffle settings. System settings are a separate destination (see inSystem),
    // reached from the bottom of the nav rail -- not a family.
    readonly property string activeFamily: Config.options?.panelFamily ?? "ii"
    property bool inSystem: false

    readonly property var iiPages: [
        { name: Translation.tr("Quick"), icon: "instant_mix", component: "modules/settings/QuickConfig.qml" },
        { name: Translation.tr("General"), icon: "browse", component: "modules/settings/GeneralConfig.qml" },
        { name: Translation.tr("Bar"), icon: "toast", iconRotation: 180, component: "modules/settings/BarConfig.qml" },
        { name: Translation.tr("Background"), icon: "texture", component: "modules/settings/BackgroundConfig.qml" },
        { name: Translation.tr("Interface"), icon: "bottom_app_bar", component: "modules/settings/InterfaceConfig.qml" },
        { name: Translation.tr("Services"), icon: "settings", component: "modules/settings/ServicesConfig.qml" },
        { name: Translation.tr("Advanced"), icon: "construction", component: "modules/settings/AdvancedConfig.qml" },
        { name: Translation.tr("About"), icon: "info", component: "modules/settings/About.qml" }
    ]
    readonly property var wafflePages: [
        { name: "Waffle", icon: "grid_view", component: "modules/settings/WaffleConfig.qml" }
    ]
    readonly property var systemPages: [
        { name: Translation.tr("System"), icon: "settings_applications", component: "modules/settings/SystemConfig.qml" }
    ]
    readonly property var familyPages: activeFamily === "waffle" ? wafflePages : iiPages
    readonly property var currentPages: inSystem ? systemPages : familyPages
    property int currentPage: 0

    // Visible header text for the current surface. NOTE: distinct from the
    // window `title` below (kept "YukiUI Settings" -- a Hyprland window rule
    // matches it, so it must not be translated/changed).
    readonly property string familyTitle: activeFamily === "waffle"
        ? Translation.tr("Waffle Settings")
        : Translation.tr("Illogical Impulse Settings")
    readonly property string surfaceTitle: inSystem ? Translation.tr("System Settings") : familyTitle

    // Reset to the first page when the surface changes. While in System, a live
    // family change must NOT disturb the System view (stay put, keep the page).
    onInSystemChanged: currentPage = 0
    onActiveFamilyChanged: if (!inSystem) currentPage = 0

    visible: true
    onClosing: Qt.quit()
    title: "YukiUI Settings"

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme()
        Config.readWriteDelay = 0 // Settings app always only sets one var at a time so delay isn't needed
    }

    minimumWidth: 750
    minimumHeight: 500
    width: 1100
    height: 750
    color: Appearance.m3colors.m3background

    ColumnLayout {
        anchors {
            fill: parent
            margins: contentPadding
        }

        Keys.onPressed: (event) => {
            if (event.modifiers === Qt.ControlModifier) {
                if (event.key === Qt.Key_PageDown) {
                    root.currentPage = Math.min(root.currentPage + 1, root.currentPages.length - 1)
                    event.accepted = true;
                }
                else if (event.key === Qt.Key_PageUp) {
                    root.currentPage = Math.max(root.currentPage - 1, 0)
                    event.accepted = true;
                }
                else if (event.key === Qt.Key_Tab) {
                    root.currentPage = (root.currentPage + 1) % root.currentPages.length;
                    event.accepted = true;
                }
                else if (event.key === Qt.Key_Backtab) {
                    root.currentPage = (root.currentPage - 1 + root.currentPages.length) % root.currentPages.length;
                    event.accepted = true;
                }
            }
        }

        Item { // Titlebar
            visible: Config.options?.windows.showTitlebar
            Layout.fillWidth: true
            Layout.fillHeight: false
            implicitHeight: Math.max(titleText.implicitHeight, windowControlsRow.implicitHeight)
            StyledText {
                id: titleText
                anchors {
                    left: Config.options.windows.centerTitle ? undefined : parent.left
                    horizontalCenter: Config.options.windows.centerTitle ? parent.horizontalCenter : undefined
                    verticalCenter: parent.verticalCenter
                    leftMargin: 12
                }
                color: Appearance.colors.colOnLayer0
                text: root.surfaceTitle
                font {
                    family: Appearance.font.family.title
                    pixelSize: Appearance.font.pixelSize.title
                    variableAxes: Appearance.font.variableAxes.title
                }
            }
            RowLayout { // Window controls row
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

        RowLayout { // Window content with navigation rail and content pane
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: contentPadding
            Item {
                id: navRailWrapper
                Layout.fillHeight: true
                Layout.margins: 5
                implicitWidth: navRail.expanded ? 150 : fab.baseSize
                Behavior on implicitWidth {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                NavigationRail { // Window content with navigation rail and content pane
                    id: navRail
                    anchors {
                        left: parent.left
                        top: parent.top
                        bottom: parent.bottom
                    }
                    spacing: 10
                    expanded: root.width > 900
                    
                    NavigationRailExpandButton {
                        focus: root.visible
                    }

                    FloatingActionButton {
                        id: fab
                        property bool justCopied: false
                        iconText: justCopied ? "check" : "edit"
                        buttonText: justCopied ? Translation.tr("Path copied") : Translation.tr("Config file")
                        expanded: navRail.expanded
                        downAction: () => {
                            Qt.openUrlExternally(`${Directories.config}/illogical-impulse/config.json`);
                        }
                        altAction: () => {
                            Quickshell.clipboardText = CF.FileUtils.trimFileProtocol(`${Directories.config}/illogical-impulse/config.json`);
                            fab.justCopied = true;
                            revertTextTimer.restart()
                        }

                        Timer {
                            id: revertTextTimer
                            interval: 1500
                            onTriggered: {
                                fab.justCopied = false;
                            }
                        }

                        StyledToolTip {
                            text: Translation.tr("Open the shell config file\nAlternatively right-click to copy path")
                        }
                    }

                    // Pages of the current surface (family settings, or System).
                    // Hidden for single-page surfaces (e.g. the System placeholder),
                    // where the lone page would just duplicate the header/System toggle.
                    // Returns automatically once a surface has real sub-pages.
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 15
                        spacing: 0
                        visible: root.currentPages.length > 1
                        Repeater {
                            model: root.currentPages
                            NavigationRailButton {
                                required property var index
                                required property var modelData
                                Layout.fillWidth: true
                                toggled: root.currentPage === index
                                onPressed: root.currentPage = index
                                expanded: navRail.expanded
                                buttonIcon: modelData.icon
                                buttonIconRotation: modelData.iconRotation || 0
                                buttonText: modelData.name
                            }
                        }
                    }

                    Item {
                        Layout.fillHeight: true
                    }

                    // Bottom entry: enter/leave System settings (a separate surface)
                    NavigationRailButton {
                        Layout.fillWidth: true
                        Layout.bottomMargin: 8
                        expanded: navRail.expanded
                        toggled: root.inSystem
                        onPressed: root.inSystem = !root.inSystem
                        buttonIcon: "tune"
                        buttonText: Translation.tr("System")
                    }
                }
            }
            Rectangle { // Content container
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Appearance.m3colors.m3surfaceContainerLow
                radius: Appearance.rounding.windowRounding - root.contentPadding

                Loader {
                    id: pageLoader
                    anchors.fill: parent
                    opacity: 1.0

                    active: Config.ready
                    Component.onCompleted: {
                        source = root.currentPages[0].component
                    }

                    Connections {
                        target: root
                        function onCurrentPageChanged() {
                            switchAnim.complete();
                            switchAnim.start();
                        }
                        function onInSystemChanged() {
                            switchAnim.complete();
                            switchAnim.start();
                        }
                        function onActiveFamilyChanged() {
                            if (root.inSystem) return; // System view is sticky across family changes
                            switchAnim.complete();
                            switchAnim.start();
                        }
                    }

                    SequentialAnimation {
                        id: switchAnim

                        NumberAnimation {
                            target: pageLoader
                            properties: "opacity"
                            from: 1
                            to: 0
                            duration: 100
                            easing.type: Appearance.animation.elementMoveExit.type
                            easing.bezierCurve: Appearance.animationCurves.emphasizedFirstHalf
                        }
                        ParallelAnimation {
                            PropertyAction {
                                target: pageLoader
                                property: "source"
                                value: root.currentPages[root.currentPage].component
                            }
                            PropertyAction {
                                target: pageLoader
                                property: "anchors.topMargin"
                                value: 20
                            }
                        }
                        ParallelAnimation {
                            NumberAnimation {
                                target: pageLoader
                                properties: "opacity"
                                from: 0
                                to: 1
                                duration: 200
                                easing.type: Appearance.animation.elementMoveEnter.type
                                easing.bezierCurve: Appearance.animationCurves.emphasizedLastHalf
                            }
                            NumberAnimation {
                                target: pageLoader
                                properties: "anchors.topMargin"
                                to: 0
                                duration: 200
                                easing.type: Appearance.animation.elementMoveEnter.type
                                easing.bezierCurve: Appearance.animationCurves.emphasizedLastHalf
                            }
                        }
                    }
                }
            }
        }
    }
}
