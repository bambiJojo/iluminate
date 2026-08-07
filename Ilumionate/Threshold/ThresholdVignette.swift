//
//  ThresholdVignette.swift
//  Ilumionate
//
//  Darkness that closes in from the edges during Arrival and releases during
//  Opening. The periphery is where the cluttered phone was, so the periphery
//  is what goes first.
//

import SwiftUI

struct ThresholdVignette: View {
    /// 0 = wide open (invisible), 1 = fully closed in around the centre.
    var closure: Double

    var body: some View {
        // At full closure the clear centre is a little under half the screen's
        // shorter edge, so the orb always sits inside untouched space.
        let innerFraction = 0.85 - 0.45 * closure

        GeometryReader { proxy in
            let extent = max(proxy.size.width, proxy.size.height)
            RadialGradient(
                colors: [.clear, Color.bgDeep],
                center: .center,
                startRadius: extent * innerFraction * 0.5,
                endRadius: extent * 0.78
            )
            .opacity(closure)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview("Closed") {
    ZStack { Color.bgPrimary.ignoresSafeArea(); LumeOrb(size: .hero); ThresholdVignette(closure: 1) }
}
#Preview("Open") {
    ZStack { Color.bgPrimary.ignoresSafeArea(); LumeOrb(size: .hero); ThresholdVignette(closure: 0) }
}
