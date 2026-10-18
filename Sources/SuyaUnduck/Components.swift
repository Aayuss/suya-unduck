import SwiftUI

extension Color {
    init(hex: UInt32) { self.init(red: Double((hex >> 16) & 255)/255, green: Double((hex >> 8) & 255)/255, blue: Double(hex & 255)/255) }
    static func accent(for scheme: ColorScheme) -> Color { Color(hex: scheme == .dark ? 0x79BE9A : 0x377D59) }
    static func panel(for scheme: ColorScheme) -> Color { Color(hex: scheme == .dark ? 0x202123 : 0xF8F8FA) }
    static func surface(for scheme: ColorScheme) -> Color { Color(hex: scheme == .dark ? 0x2A2B2E : 0xFFFFFF) }
    static func muted(for scheme: ColorScheme) -> Color { Color(hex: scheme == .dark ? 0xA7A8AD : 0x62646D) }
}
struct QuietButtonStyle: ButtonStyle {
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        ButtonFace(content: configuration.label, pressed: configuration.isPressed, compact: compact)
    }
}
private struct ButtonFace<Content: View>: View {
    let content: Content
    let pressed: Bool
    let compact: Bool
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        content.padding(.horizontal, compact ? 7 : 8).padding(.vertical, compact ? 3 : 5)
            .background(Color.primary.opacity(pressed ? 0.14 : hovered ? 0.085 : 0.045), in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(.primary).scaleEffect(pressed && !reduceMotion ? 0.98 : 1)
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovered)
            .animation(reduceMotion ? nil : .spring(duration: 0.18, bounce: 0.1), value: pressed)
    }
}
struct PickerRowStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(Color.primary.opacity(configuration.isPressed ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 6))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
struct SymbolAction: View {
    let symbol: String
    let label: String
    var action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 11, weight: .medium)).frame(width: 15, height: 16) }
            .buttonStyle(QuietButtonStyle(compact: true)).accessibilityLabel(label).help(label)
    }
}
struct Action: View {
    let title: String
    var action: () -> Void
    var body: some View { Button(title, action: action).buttonStyle(QuietButtonStyle()).accessibilityLabel(title) }
}
struct AccentSwitch: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    let title: String
    @Binding var value: Bool
    var body: some View {
        Button { withAnimation(reduceMotion ? nil : .spring(duration: 0.25, bounce: 0.15)) { value.toggle() } } label: {
            HStack {
                Text(title).fontWeight(.medium)
                Spacer(minLength: 12)
                ZStack(alignment: value ? .trailing : .leading) {
                    Capsule().fill(value ? Color.accent(for: scheme) : Color.primary.opacity(0.16))
                    Circle().fill(.white).frame(width: 16, height: 16).padding(2)
                }.frame(width: 34, height: 20)
            }.padding(.vertical, 1).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(title).accessibilityValue(value ? "On" : "Off")
    }
}
struct VolumeControl: View {
    @Environment(\.colorScheme) private var scheme
    let label: String
    @Binding var value: Float
    var maximum: Float = 2
    @FocusState private var focused: Bool
    @GestureState private var dragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                    .frame(width: 16, height: 16).scaleEffect(dragging && !reduceMotion ? 1.12 : 1).offset(x: position)
                    .animation(reduceMotion ? nil : .spring(duration: 0.18, bounce: 0.1), value: dragging)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: focused)
            }.frame(height: 22).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).updating($dragging) { _, state, _ in state = true }.onChanged { set(Float(($0.location.x - 8) / travel) * maximum) })
        }.frame(height: 22).focusable().focusEffectDisabled().focused($focused)
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
        VStack(alignment: .leading, spacing: 6) { content }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surface(for: scheme), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.07), lineWidth: 1))
    }
}
