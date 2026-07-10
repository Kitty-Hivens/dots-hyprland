import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
pragma Singleton
pragma ComponentBehavior: Bound

Singleton {
    id: root
    property bool barOpen: true
    property bool crosshairOpen: false
    property bool sidebarLeftOpen: false
    property bool sidebarRightOpen: false
    property bool mediaControlsOpen: false
    property bool osdBrightnessOpen: false
    property bool osdVolumeOpen: false
    property bool oskOpen: false
    property var oskWindow: null
    property bool overlayOpen: false
    property bool overviewOpen: false
    property string overviewReturnAddress: ""
    property bool overviewFocusHandled: false
    property bool regionSelectorOpen: false
    property bool searchOpen: false
    property bool screenLocked: false
    property bool screenLockContainsCharacters: false
    property bool screenUnlockFailed: false
    property bool screenTranslatorOpen: false
    property bool sessionOpen: false
    property bool superDown: false
    property bool superReleaseMightTrigger: true
    property bool wallpaperSelectorOpen: false
    property bool workspaceShowNumbers: false

    onSidebarRightOpenChanged: {
        if (GlobalStates.sidebarRightOpen) {
            Notifications.timeoutAll();
            Notifications.markAllRead();
        }
    }

    onScreenLockedChanged: {
        Persistent.states.lock.locked = root.screenLocked;
    }

    // Relock after a reload of the same instance; a fresh boot keeps no old lock.
    function restoreLockState() {
        if (!Persistent.ready) return;
        if (!Persistent.isNewHyprlandInstance && Persistent.states.lock.locked) {
            root.screenLocked = true;
        }
    }

    Component.onCompleted: root.restoreLockState()

    Connections {
        target: Persistent
        function onReadyChanged() {
            root.restoreLockState();
        }
    }

    GlobalShortcut {
        name: "workspaceNumber"
        description: "Hold to show workspace numbers, release to show icons"

        onPressed: {
            root.superDown = true
        }
        onReleased: {
            root.superDown = false
        }
    }
}