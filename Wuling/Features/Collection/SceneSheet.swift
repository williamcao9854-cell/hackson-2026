import SwiftUI

/// 换景：挑一幅意境，或者自己调时辰、四季、天气。
///
/// 半屏弹出，上面的园林还露在外面：点一下，就能看着新景从题签处像墨一样晕开。
/// 所有页面的淡山水背景也跟着换。
struct SceneSheet: View {
    var lanterns: Int
    var geese: Int
    /// 演示：现在就收一封节气来信（面板关掉后由首页打开）
    var onDemoLetter: (() -> Void)? = nil

    @AppStorage(SceneChoice.storageKey) private var choice: SceneChoice = .auto
    @AppStorage(SceneChoice.showcaseKey) private var showcase = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Text("园林会跟着此刻的时辰与节气变化。想看别的景，可以挑一幅意境，或者自己调时辰、四季和天气。")
                        .font(.system(size: 14))
                        .lineSpacing(3)
                        .foregroundStyle(.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Metrics.gutter)

                    presets

                    VStack(alignment: .leading, spacing: 14) {
                        Text("细调").eyebrow()
                        optionRow("时辰", options: phaseOptions)
                        optionRow("四季", options: seasonOptions)
                        optionRow("天气", options: weatherOptions)
                        Text("选了「夜」，整个 App 会跟着进入夜色。")
                            .font(.system(size: 12))
                            .foregroundStyle(.inkSecondary)
                    }
                    .padding(.horizontal, Metrics.gutter)

                    VStack(alignment: .leading, spacing: 16) {
                        Text("演示").eyebrow()
                        Toggle(isOn: $showcase.animation(.smooth)) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("演示河灯与鸿雁")
                                    .font(.system(size: 15, weight: .medium))
                                Text("还没有送别、传出过物灵时，也在水上点几盏河灯，远天放一行鸿雁")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.inkSecondary)
                            }
                        }
                        .tint(.vermilion)

                        if let onDemoLetter {
                            Button {
                                onDemoLetter()
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    LanternGlyph()
                                        .frame(width: 26, height: 26)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("收一封节气来信")
                                            .font(.system(size: 15, weight: .medium))
                                        Text("不用等到下一个节气：送别过的物灵，现在就托河灯捎来一张短笺")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.inkSecondary)
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.inkSecondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Metrics.gutter)
                }
                .padding(.top, 6)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("换景")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .foregroundStyle(.ink)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.selection, trigger: choice)
    }

    // MARK: - 意境

    private var presets: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("意境").eyebrow()
                .padding(.horizontal, Metrics.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    let today = SolarTerm(date: .now)
                    presetCard(title: "此时此刻", verse: "\(today.name) · \(today.pentad)", target: .auto)
                    ForEach(ScenePreset.all) { preset in
                        presetCard(title: preset.title, verse: preset.verse, target: preset.choice)
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
        }
    }

    private func presetCard(title: String, verse: String, target: SceneChoice) -> some View {
        let selected = choice == target
        let scene = LandscapeScene(date: .now, isDark: false, choice: target,
                                   lanterns: showcase ? max(lanterns, 3) : lanterns,
                                   geese: showcase ? max(geese, 4) : geese)
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return Button {
            withAnimation(.smooth) { choice = target }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                LandscapeThumbnail(scene: scene)
                    .frame(width: 104, height: 148)
                    .clipShape(shape)
                    .overlay {
                        shape.strokeBorder(selected ? Color.vermilion : Color.hairline, lineWidth: selected ? 2 : 0.75)
                    }
                    .overlay(alignment: .topTrailing) {
                        if selected {
                            SealStamp(text: "此景", size: 22, rotation: .degrees(-8))
                                .padding(6)
                                .transition(.scale(scale: 1.4).combined(with: .opacity))
                        }
                    }
                    .shadow(color: .black.opacity(selected ? 0.16 : 0.08), radius: selected ? 12 : 6, y: selected ? 6 : 3)
                    .scaleEffect(selected ? 1.0 : 0.97)
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(selected ? Color.vermilion : Color.ink)
                Text(verse)
                    .font(.system(size: 11, design: .serif))
                    .foregroundStyle(.inkSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 104, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)，\(verse)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - 细调

    private struct Option: Identifiable {
        let id: String
        let label: String
        let selected: Bool
        let apply: () -> Void
    }

    private var phaseOptions: [Option] {
        var options = [Option(id: "auto", label: "自动", selected: choice.phase == nil) { choice.phase = nil }]
        for phase in DayPhase.allCases {
            options.append(Option(id: phase.rawValue, label: phase.title, selected: choice.phase == phase) { choice.phase = phase })
        }
        return options
    }

    private var seasonOptions: [Option] {
        var options = [Option(id: "auto", label: "自动", selected: choice.season == nil) { choice.season = nil }]
        for season in SolarTerm.Season.allCases {
            options.append(Option(id: season.rawValue, label: season.title, selected: choice.season == season) { choice.season = season })
        }
        return options
    }

    private var weatherOptions: [Option] {
        var options = [Option(id: "auto", label: "自动", selected: choice.weather == nil) { choice.weather = nil }]
        for weather in Weather.allCases {
            options.append(Option(id: weather.rawValue, label: weather.title, selected: choice.weather == weather) { choice.weather = weather })
        }
        return options
    }

    private func optionRow(_ title: String, options: [Option]) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.inkSecondary)
                .frame(width: 32, alignment: .leading)
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(options) { option in
                        chip(option, row: title)
                    }
                }
            }
        }
    }

    private func chip(_ option: Option, row: String) -> some View {
        let glass: Glass = option.selected
            ? Glass.regular.tint(Color.vermilion.opacity(0.14)).interactive()
            : Glass.regular.interactive()
        return Button {
            withAnimation(.smooth) { option.apply() }
        } label: {
            Text(option.label)
                .font(.system(size: 14, weight: option.selected ? .semibold : .regular, design: .serif))
                .foregroundStyle(option.selected ? Color.vermilion : Color.ink)
                .frame(minWidth: 26)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(glass, in: Capsule())
        .accessibilityLabel("\(row)：\(option.label)")
        .accessibilityAddTraits(option.selected ? .isSelected : [])
    }
}

#Preview {
    Color.paper
        .sheet(isPresented: .constant(true)) {
            SceneSheet(lanterns: 2, geese: 1)
        }
}
