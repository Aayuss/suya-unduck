import SwiftUI

extension Color {
    init(hex: UInt32) { self.init(red: Double((hex >> 16) & 255)/255, green: Double((hex >> 8) & 255)/255, blue: Double(hex & 255)/255) }
    static func accent(for scheme: ColorScheme) -> Color { Color(hex: scheme == .dark ? 0x3DDC84 : 0x12873D) }
}
struct GreenButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    private var accent: Color { Color.accent(for: scheme) }
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, 10).padding(.vertical, 7)
            .background(accent.opacity(configuration.isPressed ? 0.28 : 0.10), in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(accent).opacity(enabled ? 1 : 0.4)
    }
}
struct Action: View {
    let title: String
    var action: () -> Void
    var body: some View { Button(title, action: action).buttonStyle(GreenButtonStyle()).accessibilityLabel(title) }
}
struct GreenToggle: View {
    @Environment(\.colorScheme) private var scheme
    private var accent: Color { Color.accent(for: scheme) }
    let title: String
    @Binding var value: Bool
    var body: some View {
        Button { value.toggle() } label: {
            HStack { Text(title).foregroundStyle(.primary); Spacer()
                ZStack(alignment: value ? .trailing : .leading) {
                    Capsule().fill(value ? accent : Color.secondary.opacity(0.25)).frame(width: 34, height: 20)
                    Circle().fill(.white).frame(width: 16, height: 16).padding(2)
                }.frame(width: 34, height: 20)
            }
        }.buttonStyle(GreenButtonStyle()).accessibilityLabel(title).accessibilityValue(value ? "On" : "Off")
    }
}
struct GreenSlider: View {
    @Environment(\.colorScheme) private var scheme
    private var accent: Color { Color.accent(for: scheme) }
    let label: String
    @Binding var value: Float
    var maximum: Float = 2
    @FocusState private var focused: Bool
    private func set(_ v: Float) { value = abs(v - 1) < 0.03 && maximum > 1 ? 1 : min(max(v, 0), maximum) }
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.20)).frame(height: 4)
                Capsule().fill(value > 1 ? Color(hex: 0xF5C451) : accent).frame(width: max(0, geometry.size.width * CGFloat(value/maximum)), height: 4)
                if maximum > 1 { Rectangle().fill(Color.secondary).frame(width: 1, height: 10).offset(x: geometry.size.width/CGFloat(maximum)) }
                Circle().fill(.white).overlay(Circle().stroke(accent, lineWidth: 2)).frame(width: 14, height: 14).offset(x: max(0, (geometry.size.width - 14) * CGFloat(value/maximum)))
            }.frame(height: 24).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { set(Float($0.location.x / geometry.size.width) * maximum) })
        }.frame(height: 24).focusable().focusEffectDisabled().focused($focused)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(focused ? accent : .clear, lineWidth: 2))
            .onKeyPress(.leftArrow) { set(value - 0.01); return .handled }
            .onKeyPress(.rightArrow) { set(value + 0.01); return .handled }
            .accessibilityElement().accessibilityLabel(label).accessibilityValue("\(Int(value * 100)) percent")
            .accessibilityAdjustableAction { direction in set(value + (direction == .increment ? 0.01 : -0.01)) }
    }
}
struct GreenDropdown: View {
    @Environment(\.colorScheme) private var scheme
    private var accent: Color { Color.accent(for: scheme) }
    let label: String
    let values: [(String, String)]
    @Binding var selected: String
    @State private var open = false
    @State private var highlight = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Action(title: "\(label): \(values.first { $0.0 == selected }?.1 ?? "System default")  ⌄") { open.toggle(); highlight = values.firstIndex { $0.0 == selected } ?? 0 }
            if open {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(values.enumerated()), id: \.offset) { index, item in
                            Button { selected = item.0; open = false } label: {
                                HStack { Text(item.1); Spacer(); if item.0 == selected { Text("✓") } }.frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(6).background(index == highlight ? accent.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 5))
                            }.buttonStyle(GreenButtonStyle()).onHover { if $0 { highlight = index } }
                        }
                    }
                }.frame(maxHeight: 180)
                .onKeyPress(.downArrow) { highlight = min(highlight + 1, values.count - 1); return .handled }
                .onKeyPress(.upArrow) { highlight = max(0, highlight - 1); return .handled }
                .onKeyPress(.return) { if values.indices.contains(highlight) { selected = values[highlight].0 }; open = false; return .handled }
                .onKeyPress(.escape) { open = false; return .handled }
            }
        }
    }
}
struct Card<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View { VStack(alignment: .leading, spacing: 10) { content }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.15))) }
}
