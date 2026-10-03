//
//  ProfileComponents.swift
//  InterestCalculator
//
//  Profil sekmesinin ortak parçaları: Ayarlar tarzı menü satırı (renkli ikon
//  karosu + başlık + alt başlık) ve baş harfli avatar.
//

import SwiftUI

struct ProfileMenuRow: View {
    let systemImage: String
    let tint: Color
    let title: String
    var subtitle: String? = nil
    @ScaledMetric(relativeTo: .body) private var tileSize: CGFloat = 30

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: tileSize * 0.5, weight: .semibold))
                .foregroundStyle(.onAccent)
                .frame(width: tileSize, height: tileSize)
                .background(RoundedRectangle(cornerRadius: tileSize * 0.24, style: .continuous).fill(tint))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.slate)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// Baş harfler (ya da ad yoksa kişi simgesi) — glacier daire.
struct ProfileAvatar: View {
    let initials: String?
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            Circle().fill(Color.glacier)
            if let initials {
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(.onAccent)
                    .minimumScaleFactor(0.5)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(.onAccent)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
