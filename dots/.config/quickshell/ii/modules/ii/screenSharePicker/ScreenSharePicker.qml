import qs
import qs.services
import qs.modules.common
import qs.modules.ii.regionSelector
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    // Region selection reuses the shell's styled selector (frozen frame, target regions),
    // returning the picked region to ScreenShare instead of taking a screenshot.
    Variants {
        model: Quickshell.screens
        delegate: Loader {
            id: regionLoader
            required property var modelData
            active: GlobalStates.screenShareRegionOpen

            sourceComponent: RegionSelection {
                screen: regionLoader.modelData
                action: RegionSelection.SnipAction.ScreenShare
                selectionMode: RegionSelection.SelectionMode.RectCorners
                onDismiss: GlobalStates.screenShareRegionOpen = false
            }
        }
    }

    Loader {
        id: pickerLoader
        active: GlobalStates.screenSharePickerOpen

        sourceComponent: PanelWindow {
            id: panelWindow
            readonly property HyprlandMonitor monitor: Hyprland.monitorFor(panelWindow.screen)

            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:screenSharePicker"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            color: "transparent"

            anchors {
                top: true
                left: true
                right: true
                bottom: true
            }

            mask: Region {
                item: content
            }

            Component.onCompleted: GlobalFocusGrab.addDismissable(panelWindow)
            Component.onDestruction: GlobalFocusGrab.removeDismissable(panelWindow)
            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    // Region selection dismisses the grab on purpose; don't treat that as a cancel.
                    if (!ScreenShare.suppressCancel)
                        ScreenShare.cancel();
                }
            }

            ScreenSharePickerContent {
                id: content
                anchors.centerIn: parent
                implicitWidth: Appearance.sizes.screenSharePickerWidth
                implicitHeight: Appearance.sizes.screenSharePickerHeight
            }
        }
    }

    IpcHandler {
        target: "screenShare"

        function open(allowToken: string, fifo: string, windowList: string): void {
            ScreenShare.open(allowToken, fifo, windowList);
        }

        function close(): void {
            ScreenShare.cancel();
        }
    }
}
