import SwiftUI

extension AnalysisStage {
    var title: String {
        switch self {
        case .starting:
            return "Starting..."
        case .transcribing:
            return "Transcribing Audio"
        case .analyzing:
            return "AI Analysis"
        case .generatingSession:
            return "Generating Light Session"
        case .complete:
            return "Complete"
        case .failed:
            return "Failed"
        }
    }

    var color: Color {
        switch self {
        case .starting, .transcribing, .analyzing, .generatingSession:
            return .blue
        case .complete:
            return .green
        case .failed:
            return .red
        }
    }
}
