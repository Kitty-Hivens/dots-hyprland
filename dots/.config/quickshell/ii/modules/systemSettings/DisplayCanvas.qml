pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "arrange.js" as Arrange

/**
 * Arrangement canvas. Renders the plan it is given and reports moves back;
 * every geometry decision lives in arrange.js so it can be tested directly.
 *
 * Outputs are reachable by pointer and by keyboard: tiles take focus, arrows
 * nudge, shift coarsens the step.
 */
Item {
    id: root
    property var plan: []
    property string selectedName: ""
    property real padding: 48
    property real maxViewScale: 0.22
    property int nudgeStep: 10
    property int coarseNudgeStep: 100

    signal outputMoved(string name, int x, int y)
    signal outputPicked(string name)
    signal outputEnableRequested(string name, int x, int y)
    signal outputDisableRequested(string name)

    // Displays can be dragged in and out of the parked row along the bottom,
    // which is what turns them on and off. The zone is a band rather than the
    // row's exact bounds so the gesture does not demand precision.
    property string liftedName: ""
    property point liftedPoint: Qt.point(0, 0)
    readonly property real trayZoneHeight: 96
    function inTrayZone(y) {
        return y > root.height - root.trayZoneHeight;
    }
    function logicalAt(px, py) {
        return Qt.point(Math.round((px - root.originX) / root.viewScale),
            Math.round((py - root.originY) / root.viewScale));
    }

    readonly property var activePlan: root.plan.filter(entry => entry.enabled)
    readonly property var offPlan: root.plan.filter(entry => !entry.enabled)
    property var liveGuides: []

    // The repeater is driven by output names rather than by the plan itself.
    // A plan edit produces a fresh array, which would make the repeater destroy
    // and rebuild every tile: the replacement appears already at its new place,
    // so nothing is left to animate. Keyed this way the tiles survive an edit
    // and move to it instead.
    property var tileNames: []
    readonly property string tileKey: root.activePlan.map(entry => entry.name).join(",")
    onTileKeyChanged: root.tileNames = root.activePlan.map(entry => entry.name)
    Component.onCompleted: root.tileNames = root.activePlan.map(entry => entry.name)

    readonly property rect bounds: {
        const box = Arrange.boundsOf(root.plan);
        return Qt.rect(box.x, box.y, box.width, box.height);
    }

    readonly property real viewScale: Math.max(0.01, Math.min(root.maxViewScale,
        (width - root.padding * 2) / root.bounds.width,
        (height - root.padding * 2) / root.bounds.height))

    readonly property real originX: (width - root.bounds.width * root.viewScale) / 2 - root.bounds.x * root.viewScale
    readonly property real originY: (height - root.bounds.height * root.viewScale) / 2 - root.bounds.y * root.viewScale

    // A move that normalises back to the same arrangement is not a move at all.
    // With a single display every drag lands there, since the layout is always
    // shifted to the origin, and reporting it left the page offering to apply a
    // change that would not change anything.
    function commit(name, x, y) {
        const settled = Arrange.resolveOverlap(root.plan, name, x, y);
        root.liveGuides = [];

        const candidate = root.plan.map(entry => entry.name === name
            ? Object.assign({}, entry, { x: settled.x, y: settled.y })
            : entry);
        if (root.sameLayout(candidate, root.plan))
            return false;
        root.outputMoved(name, settled.x, settled.y);
        return true;
    }

    function sameLayout(a, b) {
        const key = plan => JSON.stringify(Arrange.normalize(plan)
            .filter(entry => entry.enabled)
            .map(entry => [entry.name, entry.x, entry.y])
            .sort());
        return key(a) === key(b);
    }

    function nudge(name, dx, dy) {
        const entry = root.plan.find(item => item.name === name);
        if (!entry)
            return;
        root.commit(name, entry.x + dx, entry.y + dy);
    }

    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colLayer1
        radius: Appearance.rounding.normal
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        // Clicking the empty canvas takes focus, which is what releases the
        // search field. Sitting under the tiles, it only sees clicks that missed
        // a display.
        MouseArea {
            anchors.fill: parent
            onPressed: root.forceActiveFocus()
        }
    }

    Repeater {
        model: root.liveGuides
        delegate: Rectangle {
            required property var modelData
            visible: root.activePlan.length > 1
            color: Appearance.colors.colPrimary
            opacity: 0.55
            x: modelData.axis === "x" ? root.originX + modelData.position * root.viewScale : 0
            y: modelData.axis === "y" ? root.originY + modelData.position * root.viewScale : 0
            width: modelData.axis === "x" ? 1 : root.width
            height: modelData.axis === "y" ? 1 : root.height
        }
    }

    Repeater {
        model: root.tileNames

        delegate: FocusScope {
            id: tile
            required property string modelData

            readonly property var entry: root.plan.find(item => item.name === tile.modelData) ?? null
            readonly property var logical: tile.entry ? Arrange.logicalSize(tile.entry) : ({ width: 1, height: 1 })
            readonly property bool selected: root.selectedName === tile.modelData
            property int liveX: 0
            property int liveY: 0
            property bool dragging: false
            property bool blocked: false

            visible: tile.entry !== null
            activeFocusOnTab: true

            x: root.originX + tile.liveX * root.viewScale
            y: root.originY + tile.liveY * root.viewScale
            width: tile.logical.width * root.viewScale
            height: tile.logical.height * root.viewScale

            function syncFromPlan() {
                if (tile.dragging || !tile.entry)
                    return;
                tile.liveX = tile.entry.x;
                tile.liveY = tile.entry.y;
            }

            onEntryChanged: tile.syncFromPlan()
            Component.onCompleted: {
                if (tile.entry) {
                    tile.liveX = tile.entry.x;
                    tile.liveY = tile.entry.y;
                }
            }

            // Expressive spatial curve: a display shoved out of an illegal spot
            // should read as pushed back, not as jumping.
            Behavior on x {
                enabled: !tile.dragging
                animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
            }
            Behavior on y {
                enabled: !tile.dragging
                animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
            }

            onActiveFocusChanged: if (activeFocus) root.outputPicked(tile.modelData)

            Keys.onPressed: event => {
                const step = (event.modifiers & Qt.ShiftModifier) ? root.coarseNudgeStep : root.nudgeStep;
                if (event.key === Qt.Key_Left) {
                    root.nudge(tile.modelData, -step, 0);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Right) {
                    root.nudge(tile.modelData, step, 0);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Up) {
                    root.nudge(tile.modelData, 0, -step);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Down) {
                    root.nudge(tile.modelData, 0, step);
                    event.accepted = true;
                }
            }

            Rectangle {
                id: surface
                anchors.fill: parent
                radius: Appearance.rounding.verysmall
                color: tile.blocked ? Appearance.colors.colErrorContainer
                    : tile.selected ? Appearance.colors.colSecondaryContainer
                    : Appearance.colors.colLayer2
                border.width: tile.selected || tile.activeFocus ? 2 : 1
                border.color: tile.blocked ? Appearance.colors.colError
                    : (tile.selected || tile.activeFocus) ? Appearance.colors.colPrimary
                    : Appearance.colors.colLayer0Border

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 2

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        visible: tile.blocked
                        text: "error"
                        iconSize: Appearance.font.pixelSize.huge
                        color: Appearance.colors.colOnErrorContainer
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: tile.modelData
                        font.pixelSize: Appearance.font.pixelSize.larger
                        font.weight: Font.Medium
                        color: tile.blocked ? Appearance.colors.colOnErrorContainer
                            : tile.selected ? Appearance.colors.colOnSecondaryContainer
                            : Appearance.colors.colOnLayer2
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        visible: tile.height > 64 && !tile.blocked
                        text: `${tile.entry?.width}x${tile.entry?.height}`
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        visible: tile.blocked
                        text: Translation.tr("Overlaps another display")
                        font.pixelSize: Appearance.font.pixelSize.smallie
                        color: Appearance.colors.colOnErrorContainer
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: tile.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                property real grabX: 0
                property real grabY: 0

                onPressed: mouse => {
                    tile.forceActiveFocus();
                    root.outputPicked(tile.modelData);
                    grabX = mouse.x;
                    grabY = mouse.y;
                    tile.dragging = true;
                }

                onPositionChanged: mouse => {
                    if (!tile.dragging)
                        return;
                    const proposedX = tile.liveX + (mouse.x - grabX) / root.viewScale;
                    const proposedY = tile.liveY + (mouse.y - grabY) / root.viewScale;
                    const snapped = Arrange.snap(root.plan, tile.modelData, proposedX, proposedY, 40 / root.viewScale);
                    tile.liveX = snapped.x;
                    tile.liveY = snapped.y;
                    root.liveGuides = snapped.guides;

                    const probe = root.plan.map(entry => entry.name === tile.modelData
                        ? Object.assign({}, entry, { x: snapped.x, y: snapped.y })
                        : entry);
                    tile.blocked = Arrange.findOverlap(probe) !== null;
                }

                onReleased: {
                    if (!tile.dragging)
                        return;
                    tile.dragging = false;
                    tile.blocked = false;

                    // Dropped onto the tray: the display is being switched off.
                    // Whether that is honoured is not decided here, so the tile
                    // is put back either way; if it was, the plan changes and it
                    // leaves the canvas on its own.
                    if (root.inTrayZone(tile.y + tile.height / 2)) {
                        root.liveGuides = [];
                        root.outputDisableRequested(tile.modelData);
                        tile.syncFromPlan();
                        return;
                    }

                    // A click that never moved anything is not an edit. Committing
                    // regardless marked the layout as changed just for selecting a
                    // display, and left the page offering to apply nothing.
                    if (tile.entry && tile.liveX === tile.entry.x && tile.liveY === tile.entry.y)
                        return;

                    // A refused move has to be taken back visibly. The plan never
                    // changed, so nothing else would put the tile back and it
                    // would sit wherever it was dropped, describing a layout that
                    // is not the one in effect.
                    if (!root.commit(tile.modelData, tile.liveX, tile.liveY))
                        tile.syncFromPlan();
                }
            }
        }
    }

    StyledText {
        anchors.centerIn: parent
        visible: root.activePlan.length === 0 && root.offPlan.length === 0
        text: Translation.tr("No displays")
        font.pixelSize: Appearance.font.pixelSize.normal
        color: Appearance.colors.colSubtext
    }

    // Switched-off outputs live on the canvas too, parked along the bottom.
    // Keeping them in a separate widget made the page describe its displays in
    // two places at once, and a list of names outside the canvas has no room to
    // grow: the labels outran their chips as soon as a name got long.
    // Follows the pointer while a parked display is being dragged out, so the
    // gesture reads as picking something up rather than as a click that may or
    // may not have registered.
    Rectangle {
        visible: root.liftedName.length > 0 && !root.inTrayZone(root.liftedPoint.y)
        x: root.liftedPoint.x - width / 2
        y: root.liftedPoint.y - height / 2
        width: 140
        height: 80
        radius: Appearance.rounding.verysmall
        color: Appearance.colors.colSecondaryContainer
        opacity: 0.7
        border.width: 2
        border.color: Appearance.colors.colPrimary
        z: 10

        StyledText {
            anchors.centerIn: parent
            text: root.liftedName
            font.pixelSize: Appearance.font.pixelSize.normal
            color: Appearance.colors.colOnSecondaryContainer
        }
    }

    Row {
        id: tray
        anchors {
            left: parent.left
            bottom: parent.bottom
            leftMargin: 16
            bottomMargin: 18
        }
        spacing: 8
        visible: root.offPlan.length > 0

        Repeater {
            model: root.offPlan

            delegate: Rectangle {
                id: ghost
                required property var modelData

                readonly property bool selected: root.selectedName === ghost.modelData.name
                implicitWidth: Math.max(96, ghostLabel.implicitWidth + 24)
                implicitHeight: 54
                radius: Appearance.rounding.verysmall
                color: ghost.selected ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
                opacity: ghost.selected ? 1 : 0.8
                border.width: 1
                border.color: ghost.selected ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                ColumnLayout {
                    id: ghostLabel
                    anchors.centerIn: parent
                    spacing: 0

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: ghost.modelData.name
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: ghost.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Translation.tr("off")
                        font.pixelSize: Appearance.font.pixelSize.smallie
                        color: Appearance.colors.colSubtext
                    }
                }

                MouseArea {
                    id: ghostMouse
                    anchors.fill: parent
                    cursorShape: root.liftedName === ghost.modelData.name ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                    onPressed: {
                        root.outputPicked(ghost.modelData.name);
                        root.liftedName = ghost.modelData.name;
                    }

                    onPositionChanged: mouse => {
                        if (root.liftedName !== ghost.modelData.name)
                            return;
                        const point = ghostMouse.mapToItem(root, mouse.x, mouse.y);
                        root.liftedPoint = point;
                    }

                    onReleased: mouse => {
                        if (root.liftedName !== ghost.modelData.name)
                            return;
                        const point = ghostMouse.mapToItem(root, mouse.x, mouse.y);
                        root.liftedName = "";
                        if (root.inTrayZone(point.y))
                            return;
                        const logical = root.logicalAt(point.x, point.y);
                        root.outputEnableRequested(ghost.modelData.name, logical.x, logical.y);
                    }
                }
            }
        }
    }

    StyledText {
        anchors {
            right: parent.right
            bottom: parent.bottom
            margins: 14
        }
        visible: root.activePlan.length > 1
        text: Translation.tr("Drag to arrange, or focus a display and use the arrow keys")
        font.pixelSize: Appearance.font.pixelSize.smallie
        color: Appearance.colors.colSubtext
    }
}
