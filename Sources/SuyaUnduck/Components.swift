import SwiftUI

extension Color {
    init(hex: UInt32) { self.init(red: Double((hex >> 16) & 255)/255, green: Double((hex >> 8) & 255)/255, blue: Double(hex & 255)/255) }
    static func accent(for scheme: ColorScheme) -> Color { Color(hex: scheme == .dark ? 0x79BE9A : 0x377D59) }
    static func panel(for scheme: ColorScheme) -> Color { Color(hex: scheme == .dark ? 0x202123 : 0xF8F8FA) }
    static func surface(for scheme: ColorScheme) -> Color { Color(hex: scheme == .dark ? 0x2A2B2E : 0xFFFFFF) }
    static func muted(for scheme: ColorScheme) -> Color { Color(hex: scheme == .dark ? 0xA7A8AD : 0x62646D) }
}
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, 10).padding(.vertical, 7)
            .background(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.045), in: RoundedRectangle(cornerRadius: 7))
            .foregroundStyle(.primary)
    }
}
struct Action: View {
    let title: String
    var action: () -> Void
    var body: some View { Button(title, action: action).buttonStyle(QuietButtonStyle()).accessibilityLabel(title) }
}
struct AccentSwitch: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    @Binding var value: Bool
    var body: some View {
        Button { value.toggle() } label: {
            HStack {
                Text(title).fontWeight(.medium)
                Spacer(minLength: 12)
                ZStack(alignment: value ? .trailing : .leading) {
                    Capsule().fill(value ? Color.accent(for: scheme) : Color.primary.opacity(0.16))
                    Circle().fill(.white).frame(width: 16, height: 16).padding(2)
                }.frame(width: 34, height: 20)
            }.padding(.vertical, 4).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(title).accessibilityValue(value ? "On" : "Off")
    }
}
struct VolumeControl: View {
    @Environment(\.colorScheme) private var scheme
    let label: String
    @Binding var value: Float
    var maximum: Float = 2
    @FocusState private var focused: Bool
    private func set(_ v: Float) { value = abs(v - 1) <= 0.025 ? 1 : min(max(v, 0), maximum) }
    var body: some View {
        GeometryReader { geo in
            let travel = max(1, geo.size.width - 16)
            let position = CGFloat(min(max(value, 0), maximum) / maximum) * travel
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12)).frame(height: 3).padding(.horizontal, 8)
                Capsule().fill(Color.accent(for: scheme)).frame(width: position, height: 3).offset(x: 8)
                if maximum > 1 { Rectangle().fill(Color.primary.opacity(0.22)).frame(width: 1, height: 7).offset(x: 8 + travel / CGFloat(maximum)) }
                Circle().fill(scheme == .dark ? Color(hex: 0xF1F1F3) : Color.white)
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                    .overlay(Circle().stroke(focused ? Color.accent(for: scheme) : Color.primary.opacity(0.16), lineWidth: focused ? 2 : 0.5))
                    .frame(width: 16, height: 16).offset(x: position)
            }.frame(height: 28).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { set(Float(($0.location.x - 8) / travel) * maximum) })
        }.frame(height: 28).focusable().focusEffectDisabled().focused($focused)
            .onKeyPress(.leftArrow) { set(value - 0.01); return .handled }
            .onKeyPress(.rightArrow) { set(value + 0.01); return .handled }
            .accessibilityElement().accessibilityLabel(label).accessibilityValue("\(Int(value * 100)) percent")
            .accessibilityAdjustableAction { direction in set(value + (direction == .increment ? 0.01 : -0.01)) }
    }
}
struct Card<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surface(for: scheme), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.07), lineWidth: 1))
    }
}
