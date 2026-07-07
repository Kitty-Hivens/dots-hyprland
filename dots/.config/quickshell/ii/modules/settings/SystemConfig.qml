import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Placeholder for the System settings family. Real system management
// (displays/kanshi, network, audio, users, ...) lands here later.
Item {
    PagePlaceholder {
        anchors.fill: parent
        icon: "construction"
        title: Translation.tr("System")
        description: Translation.tr("Under construction")
        descriptionHorizontalAlignment: Text.AlignHCenter
    }
}
