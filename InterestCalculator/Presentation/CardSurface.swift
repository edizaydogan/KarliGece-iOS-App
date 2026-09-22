//
//  CardSurface.swift
//  InterestCalculator
//
//  Kart yüzeyi: drift dolgu + rime kenar + moda göre gölge. Gölge light'ta
//  ink %6 (radius 12, y 4); dark'ta YOK (koyu zeminde kirli halka bırakır),
//  yalnız kenar.
//

import SwiftUI

private struct CardSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .background(shape.fill(Color.drift))
            .overlay(shape.strokeBorder(Color.rime, lineWidth: 1))
            .shadow(
                color: colorScheme == .dark ? .clear : Color.ink.opacity(0.06),
                radius: colorScheme == .dark ? 0 : 12,
                x: 0,
                y: colorScheme == .dark ? 0 : 4
            )
    }
}

extension View {
    func cardSurface(cornerRadius: CGFloat = 16) -> some View {
        modifier(CardSurface(cornerRadius: cornerRadius))
    }
}
