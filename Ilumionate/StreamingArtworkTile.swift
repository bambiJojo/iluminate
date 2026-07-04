//
//  StreamingArtworkTile.swift
//  Ilumionate
//
//  Remote artwork tile for streaming content. Phase-based AsyncImage with an
//  aurora gradient fallback for the nil-URL, loading, and failure states —
//  so the tile can never render as a black square.
//

import SwiftUI

struct StreamingArtworkTile: View {
    let url: URL?
    let accentColor: Color
    var size: CGFloat = 60
    var cornerRadius: CGFloat = 12

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .empty, .failure:
                        fallback
                    @unknown default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(
                colors: [accentColor, accentColor.opacity(0.55)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: "music.note.list")
                .font(.system(size: size * 0.3, weight: .light))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

#Preview {
    ZStack {
        Color.voidPrimary.ignoresSafeArea()
        HStack(spacing: TranceSpacing.card) {
            StreamingArtworkTile(url: nil, accentColor: .auroraTeal)
            StreamingArtworkTile(url: URL(string: "https://invalid.example/x.jpg"),
                                 accentColor: .auroraPink)
        }
    }
}
