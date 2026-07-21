pragma Singleton
pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.services
import QtQuick
import Quickshell

/**
 * Bridge between xdg-desktop-portal-hyprland's custom_picker_binary and the shell.
 *
 * xdph launches the picker as a short-lived process, feeds it the shareable-window
 * list via the XDPH_WINDOW_SHARING_LIST env var, and reads one selection line back
 * from its stdout. The shell is a long-running daemon, so scripts/screenShare/picker.sh
 * relays the request here over IPC and blocks on a FIFO until submit()/cancel() writes
 * the answer. See the protocol notes in that script.
 */
Singleton {
    id: root

    // State for the single in-flight pick.
    property string fifoPath: ""
    property bool allowToken: false
    property var windowEntries: []
    property bool active: false
    // Set while the region overlay runs so tearing the panel down isn't mistaken for a cancel.
    property bool suppressCancel: false
    property bool awaitingRegion: false

    // Mirrors buildWindowList() in xdph: entries are
    //   {id}[HC>]{class}[HT>]{title}[HE>]{hyprAddr}[HA>]
    // concatenated. id (lower 32 bits of the toplevel handle) is what goes back as
    // window:<id>; class/title drive the label; hyprAddr matches a live toplevel.
    function parseWindowList(s) {
        const out = [];
        let rolling = s || "";
        while (rolling.length > 0) {
            // Scan markers strictly in order (each after the previous) so a stray delimiter
            // can't desync the fields and mislabel a window.
            const hc = rolling.indexOf("[HC>]");
            if (hc < 0) break;
            const ht = rolling.indexOf("[HT>]", hc + 5);
            if (ht < 0) break;
            const he = rolling.indexOf("[HE>]", ht + 5);
            if (he < 0) break;
            const ha = rolling.indexOf("[HA>]", he + 5);
            if (ha < 0) break;
            out.push({
                id: rolling.substring(0, hc),
                windowClass: rolling.substring(hc + 5, ht),
                title: rolling.substring(ht + 5, he),
                address: rolling.substring(he + 5, ha),
            });
            rolling = rolling.substring(ha + 5);
        }
        return out;
    }

    function open(allowTokenDefault, fifo, windowList) {
        if (root.active)
            root.cancel(); // resolve any previous in-flight request before taking this one
        root.fifoPath = fifo;
        root.allowToken = (allowTokenDefault === "1" || allowTokenDefault === 1 || allowTokenDefault === true);
        root.windowEntries = root.parseWindowList(windowList);
        root.active = true;
        sessionTimeout.restart();
        GlobalStates.screenSharePickerOpen = true;
    }

    // selection is the raw xdph token, e.g. "screen:HDMI-A-1", "window:12345",
    // "region:HDMI-A-1@0,0,1920,1080". The wrapper prepends [SELECTION] and the newline.
    function submit(selection) {
        if (!root.active)
            return;
        const flags = root.allowToken ? "r" : "";
        root.writeFifo(`${flags}/${selection}`);
        root.finish();
    }

    function cancel() {
        if (!root.active) {
            GlobalStates.screenSharePickerOpen = false;
            return;
        }
        root.writeFifo(""); // empty payload -> no [SELECTION] on stdout -> xdph cancels
        root.finish();
    }

    function finish() {
        sessionTimeout.stop();
        regionDelay.stop();
        root.active = false;
        root.windowEntries = [];
        root.suppressCancel = false;
        root.awaitingRegion = false;
        GlobalStates.screenShareRegionOpen = false; // tear down any region overlay too
        GlobalStates.screenSharePickerOpen = false;
    }

    function writeFifo(payload) {
        // execDetached spawns a fresh process each call so back-to-back writes can't clobber
        // one another; timeout guards against the FIFO reader having already vanished.
        Quickshell.execDetached(["timeout", "5", "sh", "-c", "printf '%s' \"$1\" > \"$2\"", "screenShare", payload, root.fifoPath]);
    }

    // Region selection reuses the shell's styled RegionSelection overlay. Drop our panel
    // (and its focus grab) first so the overlay receives input, then a beat later open it.
    function selectRegion() {
        root.suppressCancel = true;
        root.awaitingRegion = true;
        // Fully release the shared focus grab (reassigns the list, unlike removeDismissable's
        // in-place splice which leaves the grab's `active` binding stale).
        GlobalFocusGrab.dismiss();
        GlobalStates.screenSharePickerOpen = false;
        regionDelay.restart();
    }

    // Called by RegionSelection once a region is drawn. Coords are output-relative logical
    // pixels, exactly the units xdph's region:NAME@x,y,w,h format expects.
    function submitRegion(output, x, y, w, h) {
        root.awaitingRegion = false;
        GlobalStates.screenShareRegionOpen = false;
        root.submit(`region:${output}@${Math.round(x)},${Math.round(y)},${Math.round(w)},${Math.round(h)}`);
    }

    Timer {
        id: regionDelay
        interval: 120
        onTriggered: GlobalStates.screenShareRegionOpen = true
    }

    Timer {
        id: sessionTimeout
        interval: 240000 // give up the pick well before the wrapper's 300s cat timeout
        onTriggered: root.cancel()
    }

    // Region overlay dismissed without a pick -> return to the picker, keep the session.
    Connections {
        target: GlobalStates
        function onScreenShareRegionOpenChanged() {
            if (!GlobalStates.screenShareRegionOpen && root.awaitingRegion) {
                root.awaitingRegion = false;
                root.suppressCancel = false;
                GlobalStates.screenSharePickerOpen = true;
            }
        }
    }

    // Focus-grab dismissal or any external close without a pick counts as a cancel.
    Connections {
        target: GlobalStates
        function onScreenSharePickerOpenChanged() {
            if (!GlobalStates.screenSharePickerOpen && root.active && !root.suppressCancel)
                root.cancel();
        }
    }
}
