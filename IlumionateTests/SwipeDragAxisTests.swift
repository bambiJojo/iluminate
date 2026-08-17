import CoreGraphics
import Testing
@testable import Ilumionate

struct SwipeDragAxisTests {
    @Test func verticalDragBelongsToTheScrollView() {
        #expect(SwipeDragAxis.classify(CGSize(width: 8, height: -48)) == .vertical)
    }

    @Test func horizontalDragBelongsToTheRow() {
        #expect(SwipeDragAxis.classify(CGSize(width: -48, height: 8)) == .horizontal)
    }

    @Test func stationaryTouchDoesNotChooseAnAxis() {
        #expect(SwipeDragAxis.classify(.zero) == .undecided)
    }
}
