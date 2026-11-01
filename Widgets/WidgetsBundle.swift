import SwiftUI
import WidgetKit

@main
struct HealthWidgetsBundle: WidgetBundle {
    var body: some Widget {
        MetricWidget()
        OverviewWidget()
        ActivityWidget()
        RecoveryWidget()
        TrainingLoadWidget()
        TrainingWeekWidget()
        NextWorkoutWidget()
        RacePredictionsWidget()
    }
}
