import QtQuick

PropertyAnimation {
    property var curve: []
    property int standardEasing: Easing.Linear
    property real spring: 0

    easing.type: curve.length === 4 ? Easing.BezierSpline : spring > 0 ? Easing.OutBack : standardEasing
    easing.overshoot: curve.length === 4 ? 0 : spring
    easing.bezierCurve: {
        if (curve.length !== 4)
            return []
        if (spring <= 0)
            return [curve[0], curve[1], curve[2], curve[3], 1, 1]

        // Leave a short settling segment after the adjustable part of the curve.
        const approach = 0.79
        const peak = 1 + 0.05 * spring
        return [approach * curve[0], peak * curve[1], approach * curve[2], peak * curve[3], approach, peak,
            0.86, peak, 0.94, 1, 1, 1]
    }
}
