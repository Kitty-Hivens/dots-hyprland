// Pure geometry for the display arrangement canvas.
//
// Everything here works in logical coordinates and depends on nothing from QML,
// so the layout rules can be exercised directly instead of only through a
// running shell. The canvas is a renderer for these results, not a second
// implementation of them.

function logicalSize(entry) {
    var rotated = (Number(entry.transform || 0) % 2) === 1;
    var scale = Number(entry.scale) || 1;
    var w = (rotated ? entry.height : entry.width) / scale;
    var h = (rotated ? entry.width : entry.height) / scale;
    return { width: Math.round(w), height: Math.round(h) };
}

function rectOf(entry) {
    var size = logicalSize(entry);
    return { x: entry.x, y: entry.y, width: size.width, height: size.height };
}

function rectAt(entry, x, y) {
    var size = logicalSize(entry);
    return { x: x, y: y, width: size.width, height: size.height };
}

function enabledOf(entries) {
    return entries.filter(function (entry) { return entry.enabled; });
}

function overlaps(a, b) {
    return a.x < b.x + b.width && b.x < a.x + a.width
        && a.y < b.y + b.height && b.y < a.y + a.height;
}

function spansOverlap(aStart, aLength, bStart, bLength) {
    return aStart < bStart + bLength && bStart < aStart + aLength;
}

function boundsOf(entries) {
    var active = enabledOf(entries);
    if (active.length === 0)
        return { x: 0, y: 0, width: 1, height: 1 };
    var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    active.forEach(function (entry) {
        var rect = rectOf(entry);
        minX = Math.min(minX, rect.x);
        minY = Math.min(minY, rect.y);
        maxX = Math.max(maxX, rect.x + rect.width);
        maxY = Math.max(maxY, rect.y + rect.height);
    });
    return { x: minX, y: minY, width: Math.max(1, maxX - minX), height: Math.max(1, maxY - minY) };
}

// Hyprland wants a non negative origin. The whole arrangement shifts together so
// that the outputs keep their relationships to each other.
function normalize(entries) {
    var bounds = boundsOf(entries);
    if (enabledOf(entries).length === 0)
        return entries.slice();
    return entries.map(function (entry) {
        if (!entry.enabled)
            return Object.assign({}, entry);
        return Object.assign({}, entry, { x: entry.x - bounds.x, y: entry.y - bounds.y });
    });
}

/**
 * Snap a dragged output against the others.
 *
 * Adjacency (sitting flush against an edge) is only offered when the two
 * outputs already overlap on the other axis, and alignment (matching edges or
 * centres) only when they are close to being adjacent on the other axis.
 * Without that gate an output can snap to a far away edge and leave a hole in
 * the layout that only surfaces later as a contiguity failure.
 */
function snap(entries, name, proposedX, proposedY, threshold) {
    var moving = entries.find(function (entry) { return entry.name === name; });
    var size = logicalSize(moving);
    var others = enabledOf(entries).filter(function (entry) { return entry.name !== name; });

    var best = {
        x: proposedX,
        y: proposedY,
        distanceX: threshold,
        distanceY: threshold,
        guides: []
    };

    others.forEach(function (other) {
        var rect = rectOf(other);

        var overlapY = spansOverlap(proposedY, size.height, rect.y, rect.height);
        var overlapX = spansOverlap(proposedX, size.width, rect.x, rect.width);
        var nearY = Math.abs(proposedY - (rect.y + rect.height)) < threshold
            || Math.abs(proposedY + size.height - rect.y) < threshold;
        var nearX = Math.abs(proposedX - (rect.x + rect.width)) < threshold
            || Math.abs(proposedX + size.width - rect.x) < threshold;

        var xCandidates = [];
        if (overlapY) {
            xCandidates.push({ value: rect.x + rect.width, kind: "adjacent", edge: rect.x + rect.width });
            xCandidates.push({ value: rect.x - size.width, kind: "adjacent", edge: rect.x });
        }
        if (nearY) {
            xCandidates.push({ value: rect.x, kind: "align", edge: rect.x });
            xCandidates.push({ value: rect.x + rect.width - size.width, kind: "align", edge: rect.x + rect.width });
            xCandidates.push({ value: rect.x + (rect.width - size.width) / 2, kind: "center", edge: rect.x + rect.width / 2 });
        }

        var yCandidates = [];
        if (overlapX) {
            yCandidates.push({ value: rect.y + rect.height, kind: "adjacent", edge: rect.y + rect.height });
            yCandidates.push({ value: rect.y - size.height, kind: "adjacent", edge: rect.y });
        }
        if (nearX) {
            yCandidates.push({ value: rect.y, kind: "align", edge: rect.y });
            yCandidates.push({ value: rect.y + rect.height - size.height, kind: "align", edge: rect.y + rect.height });
            yCandidates.push({ value: rect.y + (rect.height - size.height) / 2, kind: "center", edge: rect.y + rect.height / 2 });
        }

        xCandidates.forEach(function (candidate) {
            var distance = Math.abs(proposedX - candidate.value);
            if (distance < best.distanceX) {
                best.distanceX = distance;
                best.x = candidate.value;
                best.guideX = { axis: "x", position: candidate.edge, kind: candidate.kind, against: other.name };
            }
        });
        yCandidates.forEach(function (candidate) {
            var distance = Math.abs(proposedY - candidate.value);
            if (distance < best.distanceY) {
                best.distanceY = distance;
                best.y = candidate.value;
                best.guideY = { axis: "y", position: candidate.edge, kind: candidate.kind, against: other.name };
            }
        });
    });

    var guides = [];
    if (best.guideX) guides.push(best.guideX);
    if (best.guideY) guides.push(best.guideY);

    return { x: Math.round(best.x), y: Math.round(best.y), guides: guides };
}

/**
 * Push a dragged output out of whatever it landed on, along the axis of least
 * penetration. Repeated because clearing one neighbour can push it into
 * another; it gives up rather than looping forever in a crowded layout.
 */
function resolveOverlap(entries, name, x, y) {
    var moving = entries.find(function (entry) { return entry.name === name; });
    var others = enabledOf(entries).filter(function (entry) { return entry.name !== name; });
    var current = { x: x, y: y };

    for (var pass = 0; pass < 8; ++pass) {
        var moved = false;
        for (var i = 0; i < others.length; ++i) {
            var rect = rectOf(others[i]);
            var candidate = rectAt(moving, current.x, current.y);
            if (!overlaps(candidate, rect))
                continue;

            var pushRight = rect.x + rect.width - candidate.x;
            var pushLeft = candidate.x + candidate.width - rect.x;
            var pushDown = rect.y + rect.height - candidate.y;
            var pushUp = candidate.y + candidate.height - rect.y;

            var minimum = Math.min(pushRight, pushLeft, pushDown, pushUp);
            if (minimum === pushRight) current.x += pushRight;
            else if (minimum === pushLeft) current.x -= pushLeft;
            else if (minimum === pushDown) current.y += pushDown;
            else current.y -= pushUp;
            moved = true;
        }
        if (!moved)
            break;
    }
    return { x: Math.round(current.x), y: Math.round(current.y) };
}

function findOverlap(entries) {
    var active = enabledOf(entries);
    for (var i = 0; i < active.length; ++i) {
        for (var j = i + 1; j < active.length; ++j) {
            if (overlaps(rectOf(active[i]), rectOf(active[j])))
                return [active[i].name, active[j].name];
        }
    }
    return null;
}

// A layout split into islands leaves a region the pointer can enter but not
// leave, so touching outputs are treated as connected and everything must end
// up in one group.
function isContiguous(entries) {
    var active = enabledOf(entries);
    if (active.length <= 1)
        return true;

    var seen = [0];
    var queue = [0];
    while (queue.length > 0) {
        var currentIndex = queue.shift();
        var a = rectOf(active[currentIndex]);
        for (var i = 0; i < active.length; ++i) {
            if (seen.indexOf(i) !== -1)
                continue;
            var b = rectOf(active[i]);
            // Meeting at a corner alone is not a connection: the pointer cannot
            // cross there, which is the whole reason this check exists. One axis
            // has to genuinely overlap while the other merely touches.
            var spansX = a.x < b.x + b.width && b.x < a.x + a.width;
            var spansY = a.y < b.y + b.height && b.y < a.y + a.height;
            var touchesX = a.x <= b.x + b.width && b.x <= a.x + a.width;
            var touchesY = a.y <= b.y + b.height && b.y <= a.y + a.height;
            if ((spansX && touchesY) || (spansY && touchesX)) {
                seen.push(i);
                queue.push(i);
            }
        }
    }
    return seen.length === active.length;
}

function modeSupported(entry, availableModes) {
    if (!availableModes)
        return false;
    var wanted = entry.width + "x" + entry.height + "@" + Math.round(entry.refreshRate);
    return availableModes.some(function (mode) {
        var parsed = /^(\d+)x(\d+)@([\d.]+)Hz$/.exec(mode);
        if (!parsed)
            return false;
        return parsed[1] + "x" + parsed[2] + "@" + Math.round(parseFloat(parsed[3])) === wanted;
    });
}

if (typeof module !== "undefined")
    module.exports = {
        logicalSize: logicalSize,
        rectOf: rectOf,
        overlaps: overlaps,
        boundsOf: boundsOf,
        normalize: normalize,
        snap: snap,
        resolveOverlap: resolveOverlap,
        findOverlap: findOverlap,
        isContiguous: isContiguous,
        modeSupported: modeSupported
    };
