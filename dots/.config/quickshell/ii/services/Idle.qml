pragma Singleton
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

/**
 * A nice wrapper for date and time strings.
 */
Singleton {
    id: root

    property bool inhibit: false
    property bool respawning: false

    function load() {}

    function toggleInhibit(active = null) {
        if (active !== null) {
            root.inhibit = active;
        } else {
            root.inhibit = !root.inhibit;
        }
        Persistent.states.idle.inhibit = root.inhibit;
    }

    IpcHandler {
        target: "idle"

        function status(): string {
            return root.inhibit ? "inhibiting" : "off";
        }
        function toggle(): void {
            root.toggleInhibit();
        }
        function enable(): void {
            root.toggleInhibit(true);
        }
        function disable(): void {
            root.toggleInhibit(false);
        }
    }

    function syncFromPersistent() {
        if (!Persistent.ready) return;
        if (!Persistent.isNewHyprlandInstance) {
            root.inhibit = Persistent.states.idle.inhibit;
        } else {
            Persistent.states.idle.inhibit = root.inhibit;
        }
    }

    Component.onCompleted: root.syncFromPersistent()

    Connections {
        target: Persistent
        function onReadyChanged() {
            root.syncFromPersistent();
        }
    }

    // The compositor closes the inhibitor surface when its monitor goes away; recreate on screen changes.
    Connections {
        target: Quickshell
        function onScreensChanged() {
            if (root.inhibit) respawnTimer.restart();
        }
    }

    Timer {
        id: respawnTimer
        interval: 1000
        onTriggered: {
            if (!root.inhibit || Quickshell.screens.length === 0) return;
            root.respawning = true;
            Qt.callLater(() => root.respawning = false);
        }
    }

    LazyLoader {
        active: root.inhibit && !root.respawning
        component: IdleInhibitor {
            enabled: true
            window: PanelWindow {
                // Inhibitor only counts while its surface is mapped and visible.
                WlrLayershell.namespace: "quickshell:idleInhibitor"
                implicitWidth: 0
                implicitHeight: 0
                color: "transparent"
                anchors {
                    right: true
                    bottom: true
                }
                // Make it not interactable
                mask: Region {
                    item: null
                }
            }
        }
    }
}
