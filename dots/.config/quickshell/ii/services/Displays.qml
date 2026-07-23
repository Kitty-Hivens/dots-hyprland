pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.modules.common
import qs.modules.common.functions
import "../modules/systemSettings/arrange.js" as Arrange

/**
 * Output layout model.
 *
 * Hyprland both applies and persists: settings go to monitors.lua, which
 * hyprland.lua sources.
 *
 * Quickshell exposes no wlr-output-management binding, so there is no protocol
 * level test. `Hyprland --verify-config` on a generated file stands in for it,
 * and anything that slips past is caught by rereading the compositor after
 * apply. A timer reverts if nothing confirms.
 */
Singleton {
    id: root

    readonly property int revertSeconds: 15
    readonly property int verifyAttempts: 6

    readonly property string stateIdle: "idle"
    readonly property string statePreflight: "preflight"
    readonly property string stateApplying: "applying"
    readonly property string stateVerifying: "verifying"
    readonly property string stateConfirming: "confirming"
    readonly property string stateReverting: "reverting"

    property string state: root.stateIdle
    property string lastError: ""
    property int secondsLeft: 0
    // The page sets this from its window's focus. Polling the compositor twice a
    // second is wasted work while nobody is looking at the result.
    property bool polling: true

    /**
     * Values as they were before the SDR sliders started previewing.
     *
     * The preview writes to the compositor so it can be seen, but the compositor
     * is also what the page compares against to decide whether anything changed.
     * Without holding the originals here, a preview would quietly become the
     * state it was supposed to be judged against: nothing to discard back to, and
     * nothing registering as changed, so nothing would ever reach the disk.
     */
    property var sdrBaseline: ({})

    property var outputs: []
    property string outputsJson: ""
    property var pendingPlan: null
    property var revertPlan: null
    property int verifyTries: 0

    readonly property bool awaitingConfirmation: root.state === root.stateConfirming
    readonly property bool busy: root.state === root.statePreflight
        || root.state === root.stateApplying
        || root.state === root.stateVerifying

    readonly property string configDir: FileUtils.trimFileProtocol(`${Directories.config}`)
    // hyprland.lua sources a fixed list out of custom/, so a new file there would
    // never load. monitors.lua in the hypr root is already wired up as the slot
    // for generated monitor config and is the only one that takes effect.
    readonly property string monitorsConfigPath: `${root.configDir}/hypr/monitors.lua`
    readonly property string scriptDir: `${root.configDir}/quickshell/ii/scripts/displays`

    signal applyFailed(string reason)
    signal applied()
    signal persisted()

    function reload() {
        getMonitors.running = true;
    }

    /**
     * An output that is plugged in but not driving reports a 0x0 mode. That is a
     * state of the hardware, not something the user chose, so it must not reach
     * validation as a rejected mode: doing so blocks the page on an error the
     * user has no way to clear. The first advertised mode stands in, and an
     * output with nothing to offer is marked unusable and left out of the checks.
     */
    function usableMode(output) {
        if (output.width > 0 && output.height > 0)
            return { width: output.width, height: output.height, refreshRate: Math.round(output.refreshRate), usable: true };

        const first = (output.availableModes ?? [])[0];
        const parsed = first ? /^(\d+)x(\d+)@([\d.]+)Hz$/.exec(first) : null;
        if (!parsed)
            return { width: 0, height: 0, refreshRate: 0, usable: false };
        return {
            width: parseInt(parsed[1]),
            height: parseInt(parsed[2]),
            refreshRate: Math.round(parseFloat(parsed[3])),
            usable: false
        };
    }

    function currentPlan() {
        return root.outputs.map(output => ({
            name: output.name,
            enabled: !output.disabled,
            usable: root.usableMode(output).usable,
            width: root.usableMode(output).width,
            height: root.usableMode(output).height,
            refreshRate: root.usableMode(output).refreshRate,
            x: output.x,
            y: output.y,
            scale: output.scale,
            transform: output.transform,
            vrr: output.vrr ? 1 : 0,
            // Written only once the user has actually touched the switch. Taken
            // from the compositor it would read false whenever nothing is
            // fullscreen, and pinning that per output silently overrides the
            // global policy the user set.
            vrrOverride: false,
            sdrBrightness: root.sdrBaseline[output.name]?.sdrBrightness ?? output.sdrBrightness ?? 1.0,
            sdrSaturation: root.sdrBaseline[output.name]?.sdrSaturation ?? output.sdrSaturation ?? 1.0,
            bitdepth: (output.currentFormat ?? "").indexOf("2101010") !== -1 ? 10 : 8,
            cm: output.colorManagementPreset && output.colorManagementPreset.length > 0
                ? output.colorManagementPreset : "srgb"
        }));
    }

    function availableModesFor(name) {
        return root.outputs.find(output => output.name === name)?.availableModes ?? [];
    }

    /** Everything that can be judged without touching the compositor. */
    function validate(plan) {
        // Outputs that are not driving are excluded rather than rejected: they
        // carry no geometry worth checking, and reporting them as invalid would
        // leave the page stuck on an error nothing in it can fix.
        const active = plan.filter(entry => entry.enabled && entry.usable !== false);
        if (active.length === 0) {
            // Nothing to check only if there was nothing to begin with. A plan
            // that switches everything off is the one case that cannot be undone
            // by looking at the screen.
            return plan.length === 0 ? "" : Translation.tr("At least one display must stay enabled");
        }

        for (const entry of active) {
            const modes = root.availableModesFor(entry.name);
            if (modes.length > 0 && !Arrange.modeSupported(entry, modes))
                return Translation.tr("%1 does not support %2x%3 at %4 Hz")
                    .arg(entry.name).arg(entry.width).arg(entry.height).arg(Math.round(entry.refreshRate));
        }

        const clash = Arrange.findOverlap(plan);
        if (clash)
            return Translation.tr("%1 and %2 overlap").arg(clash[0]).arg(clash[1]);

        if (!Arrange.isContiguous(plan))
            return Translation.tr("Displays must touch, leaving no gap between them");

        return "";
    }

    /**
     * Hyprland refuses `hyprctl keyword` once the config is Lua ("keyword can't
     * work with non-legacy parsers"), and it still exits 0 while doing so, so
     * the whole path goes through `eval` and is judged by its output text.
     * Every output is sent in one call: applying a subset lets Hyprland
     * reposition the rest automatically.
     */
    function luaCallFor(entry) {
        if (!entry.enabled)
            return `hl.monitor({ output = "${entry.name}", disabled = true })`;
        return `hl.monitor({ output = "${entry.name}", `
            + `mode = "${entry.width}x${entry.height}@${entry.refreshRate}", `
            + `position = "${entry.x}x${entry.y}", `
            + `scale = ${entry.scale}, `
            + `transform = ${entry.transform}, `
            + (entry.vrrOverride ? `vrr = ${entry.vrr ? 1 : 0}, ` : "")
            + `bitdepth = ${entry.bitdepth === 10 ? 10 : 8}, `
            + `cm = "${entry.cm}", `
            + `sdrbrightness = ${entry.sdrBrightness ?? 1.0}, `
            + `sdrsaturation = ${entry.sdrSaturation ?? 1.0} })`;
    }

    function luaFor(plan, separator) {
        return plan.map(entry => root.luaCallFor(entry)).join(separator ?? " ");
    }

    /**
     * Applies just the SDR mapping, live, without going through apply at all.
     *
     * These two do not touch the mode, the link or the colour container, so
     * there is nothing to renegotiate and nothing that can leave the screen
     * unusable: the countdown exists for changes that can, and demanding it here
     * would make a value that has to be judged by eye impossible to judge.
     */
    /**
     * Dragging emits continuously, so the request is coalesced rather than run
     * per tick: reassigning a process that is still running loses calls, and the
     * one lost can be the last, leaving the display on an intermediate value
     * while the draft holds the final one. Only the newest value matters, and it
     * is always the one that ends up applied.
     */
    property var pendingPreview: null

    function previewSdr(name, brightness, saturation) {
        // Nothing to return to means discard cannot work, so a preview does not
        // begin until there is a recorded starting point.
        if (!root.sdrBaseline[name]) {
            const live = root.outputs.find(output => output.name === name);
            if (!live)
                return;
            const captured = root.sdrBaseline;
            captured[name] = {
                sdrBrightness: live.sdrBrightness ?? 1.0,
                sdrSaturation: live.sdrSaturation ?? 1.0
            };
            root.sdrBaseline = captured;
        }

        root.pendingPreview = { name: name, brightness: brightness, saturation: saturation };
        if (!previewProc.running)
            root.flushPreview();
    }

    function flushPreview() {
        const next = root.pendingPreview;
        if (!next || previewProc.running)
            return;
        root.pendingPreview = null;
        previewProc.command = ["hyprctl", "eval",
            `hl.monitor({ output = "${next.name}", sdrbrightness = ${next.brightness}, sdrsaturation = ${next.saturation} })`];
        previewProc.running = true;
    }

    /**
     * Puts the display back the way it looked before any slider was touched.
     *
     * The recorded values deliberately survive this. They describe the last
     * applied state, not whatever happens to be live: clearing them here meant
     * that touching a slider again before the restore had landed recorded the
     * discarded preview as the new starting point, and the next discard returned
     * to that instead. Only applying replaces them.
     */
    function discardSdrPreview() {
        root.pendingPreview = null;
        for (const name in root.sdrBaseline) {
            const base = root.sdrBaseline[name];
            Quickshell.execDetached(["hyprctl", "eval",
                `hl.monitor({ output = "${name}", sdrbrightness = ${base.sdrBrightness}, sdrsaturation = ${base.sdrSaturation} })`]);
        }
    }

    function acceptSdrPreview() {
        root.sdrBaseline = ({});
    }

    Process {
        id: previewProc
        // Whatever arrived while this was busy goes out now, so the value the
        // user settled on is never the one that got dropped.
        onExited: root.flushPreview()
    }

    function evalFailed(output) {
        return output.trim().length === 0 || output.indexOf("error:") !== -1;
    }

    function apply(plan) {
        if (root.busy || root.state === root.stateConfirming)
            return false;

        root.lastError = "";
        // Sending a 0x0 mode to the compositor achieves nothing and can only
        // confuse it, so outputs that are not driving are left out of the batch.
        const usable = plan.filter(entry => entry.usable !== false);
        if (usable.length === 0) {
            root.lastError = Translation.tr("No display is reporting a usable mode");
            root.applyFailed(root.lastError);
            return false;
        }
        const normalized = Arrange.normalize(usable);
        const problem = root.validate(normalized);
        if (problem.length > 0) {
            root.lastError = problem;
            root.applyFailed(problem);
            return false;
        }

        root.pendingPlan = normalized;
        root.revertPlan = root.currentPlan();
        root.state = root.statePreflight;
        // Written out rather than piped: piping made the exit status the pipe's,
        // and an empty temp path would have had Hyprland validate its own default
        // config and answer "config ok" for a plan it never saw.
        preflight.command = ["bash", "-c",
            `set -eu; f=$(mktemp --suffix=.lua); [ -n "$f" ] || exit 1; `
            + `trap 'rm -f "$f"' EXIT; `
            + `printf '%s\\n' '${StringUtils.shellSingleQuoteEscape(root.luaFor(normalized, "\n"))}' > "$f"; `
            + `out=$(Hyprland --verify-config -c "$f" 2>&1) || true; `
            + `printf '%s\\n' "$out" | tail -3`];
        preflight.running = true;
        return true;
    }

    // Keeping the change is the confirmation. Asking again afterwards only
    // offered a way to end up with a layout that works now and is gone at the
    // next start, which is not a choice worth presenting.
    function confirm() {
        revertTimer.stop();
        root.state = root.stateIdle;
        root.lastError = "";
        root.revertPlan = null;
        root.applied();
        root.persist();
    }

    /** Survives this process exiting, unlike the normal revert. */
    function revertDetached() {
        if (!root.revertPlan)
            return;
        revertTimer.stop();
        Quickshell.execDetached(["hyprctl", "eval", root.luaFor(root.revertPlan)]);
        root.revertPlan = null;
    }

    function revert() {
        revertTimer.stop();
        if (!root.revertPlan) {
            root.state = root.stateIdle;
            return;
        }
        root.state = root.stateReverting;
        revertProc.command = ["hyprctl", "eval", root.luaFor(root.revertPlan)];
        revertProc.running = true;
    }

    // One target. The writer replaces only the marked region, leaving the docking
    // handlers that decide whether the laptop panel is on: regenerating the whole
    // file would drop them and an undocked boot would come up with no display.
    // Hyprland picks the file up itself and its config.reloaded handler reapplies
    // the docking rule, so nothing needs poking afterwards.
    function persist() {
        if (!root.pendingPlan)
            return;
        writeMonitors.command = ["python3", `${root.scriptDir}/monitors_write.py`,
            root.monitorsConfigPath, JSON.stringify(root.pendingPlan)];
        writeMonitors.running = true;
    }


    Process {
        id: preflight
        stdout: StdioCollector { id: preflightOut }
        onExited: exitCode => {
            const text = preflightOut.text.trim();
            if (exitCode !== 0 || text.indexOf("config ok") === -1) {
                root.state = root.stateIdle;
                root.lastError = text.length > 0
                    ? Translation.tr("Hyprland rejected the configuration: %1").arg(text)
                    : Translation.tr("Hyprland rejected the configuration");
                root.pendingPlan = null;
                root.applyFailed(root.lastError);
                return;
            }
            root.state = root.stateApplying;
            applyProc.command = ["hyprctl", "eval", root.luaFor(root.pendingPlan)];
            applyProc.running = true;
        }
    }

    Process {
        id: applyProc
        stdout: StdioCollector { id: applyOut }
        onExited: exitCode => {
            // hyprctl exits 0 even when it refuses the request, so the reply
            // text decides.
            if (exitCode !== 0 || root.evalFailed(applyOut.text)) {
                root.lastError = Translation.tr("hyprctl failed: %1").arg(applyOut.text.trim());
                root.applyFailed(root.lastError);
                root.revert();
                return;
            }
            root.state = root.stateVerifying;
            root.verifyTries = 0;
            verifyTimer.restart();
        }
    }

    Process {
        id: revertProc
        stdout: StdioCollector { id: revertOut }
        onExited: exitCode => {
            // The revert is the safety net; if it fails the user must be told
            // rather than left looking at a layout nobody chose.
            if (exitCode !== 0 || root.evalFailed(revertOut.text))
                root.lastError = Translation.tr("Revert failed. Run 'hyprctl reload' from a TTY if the screen is unusable.");
            root.state = root.stateIdle;
            root.revertPlan = null;
            root.pendingPlan = null;
            getMonitors.running = true;
        }
    }

    /** A mode switch is not instant, so verification retries before giving up. */
    function verifyAgainst(plan) {
        for (const entry of plan.filter(item => item.enabled)) {
            const live = root.outputs.find(output => output.name === entry.name);
            if (!live || live.disabled)
                return Translation.tr("%1 did not come back").arg(entry.name);
            if (live.width !== entry.width || live.height !== entry.height)
                return Translation.tr("%1 fell back to %2x%3").arg(entry.name).arg(live.width).arg(live.height);
        }
        return "";
    }

    Timer {
        id: verifyTimer
        interval: 500
        onTriggered: getMonitors.running = true
    }

    Timer {
        id: revertTimer
        interval: 1000
        repeat: true
        onTriggered: {
            root.secondsLeft -= 1;
            if (root.secondsLeft <= 0)
                root.revert();
        }
    }

    Process {
        id: getMonitors
        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: StdioCollector {
            id: monitorsOut
            onStreamFinished: {
                // Reassigning on every poll would fire outputsChanged even when
                // nothing moved, and the page resyncs its draft from that: the
                // inspector controls would be rewritten under the user mid-edit.
                let parsed;
                try {
                    parsed = JSON.parse(monitorsOut.text);
                } catch (error) {
                    return;
                }
                const fingerprint = JSON.stringify(parsed.map(output => [output.name, output.width, output.height,
                    Math.round(output.refreshRate), output.x, output.y, output.scale, output.transform,
                    output.vrr, output.disabled, output.currentFormat, output.colorManagementPreset,
                    output.sdrBrightness, output.sdrSaturation]));
                if (fingerprint !== root.outputsJson) {
                    root.outputsJson = fingerprint;
                    root.outputs = parsed;
                }
                if (root.state !== root.stateVerifying || !root.pendingPlan)
                    return;

                const problem = root.verifyAgainst(root.pendingPlan);
                if (problem.length === 0) {
                    root.state = root.stateConfirming;
                    root.secondsLeft = root.revertSeconds;
                    revertTimer.restart();
                    return;
                }
                root.verifyTries += 1;
                if (root.verifyTries < root.verifyAttempts) {
                    verifyTimer.restart();
                    return;
                }
                root.lastError = problem;
                root.applyFailed(problem);
                root.revert();
            }
        }
    }

    Process {
        id: writeMonitors
        stderr: StdioCollector { id: writeMonitorsErr }
        onExited: exitCode => {
            if (exitCode !== 0) {
                root.lastError = Translation.tr("Could not write the display config: %1").arg(writeMonitorsErr.text.trim());
                root.applyFailed(root.lastError);
                return;
            }
            root.pendingPlan = null;
            root.acceptSdrPreview();
            root.persisted();
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (["monitoradded", "monitoraddedv2", "monitorremoved", "configreloaded"].includes(event.name))
                root.reload();
        }
    }

    // Hyprland announces outputs appearing and disappearing but not a mode,
    // scale or position change, and it can also be changed from outside.
    // Polling is cheap here because the service only exists while the settings
    // window is open, and the fingerprint check keeps an unchanged poll silent.
    Timer {
        running: true
        repeat: true
        interval: 2000
        onTriggered: {
            if (root.polling && !root.busy && root.state !== root.stateConfirming)
                getMonitors.running = true;
        }
    }

    Component.onCompleted: root.reload()
}
