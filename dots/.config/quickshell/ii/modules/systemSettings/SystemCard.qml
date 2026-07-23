import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: root
    property string title: ""
    property string icon: ""
    property string subtitle: ""
    default property alias cardData: cardContent.data

    color: Appearance.colors.colLayer2
    border.width: 1
    border.color: Appearance.colors.colLayer0Border
    radius: Appearance.rounding.normal
    implicitHeight: cardColumn.implicitHeight + cardColumn.anchors.margins * 2

    ColumnLayout {
        id: cardColumn
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 16
        }
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: root.title.length > 0

            MaterialSymbol {
                visible: root.icon.length > 0
                text: root.icon
                iconSize: Appearance.font.pixelSize.hugeass
                color: Appearance.colors.colOnLayer2
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: root.title
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer2
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.subtitle.length > 0
                    text: root.subtitle
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    color: Appearance.colors.colSubtext
                }
            }
        }

        ColumnLayout {
            id: cardContent
            Layout.fillWidth: true
            spacing: 6
        }
    }
}
