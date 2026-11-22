import SwiftUI

/// ② 讲讲它：确认它是什么、陪了你多久、一段记忆（选填）。
struct StoryView: View {
    @Bindable var model: EncounterModel
    @FocusState private var focusedField: Field?
    @State private var lifted = false

    private enum Field { case name, memory }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let sticker = model.sticker {
                    StickerView(image: sticker, lifted: lifted)
                        .frame(height: 220)
                        .padding(.top, 72)
                        .padding(.horizontal, 60)
                        .phaseAnimator([0.0, 1.0]) { content, phase in
                            content.offset(y: phase * -6)
                        } animation: { _ in .easeInOut(duration: 2.4) }
                }

                VStack(spacing: 6) {
                    Text(model.needsNaming ? "这是……" : "看见你了").eyebrow()
                    TextField(model.needsNaming ? "它是什么？" : "它叫什么", text: $model.objectName)
                        .font(.system(size: 30, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.done)
                    Text(model.needsNaming ? "我没认出来，告诉我它是什么吧，比如「外婆的闹钟」" : "可以改成你对它的称呼，比如「外婆的闹钟」")
                        .font(.system(size: 13))
                        .foregroundStyle(.inkSecondary)

                    if model.recognizedByModel {
                        Label("Apple 智能在手机上认出了它", systemImage: "apple.intelligence")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.inkSecondary)
                            .padding(.top, 4)
                    }

                    let others = model.candidates.isEmpty && model.needsNaming
                        ? Self.commonKinds
                        : model.candidates.filter { $0.chinese != model.objectName }
                    if !others.isEmpty {
                        HStack(spacing: 8) {
                            Text(model.candidates.isEmpty ? "比如" : "是不是")
                                .font(.system(size: 13))
                                .foregroundStyle(.inkSecondary)
                            ForEach(Array(others.prefix(3)), id: \.self) { kind in
                                Button {
                                    model.choose(kind)
                                } label: {
                                    Text(kind.chinese)
                                        .font(.system(size: 13, weight: .semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .overlay { Capsule().strokeBorder(Color.ink.opacity(0.18), lineWidth: 1) }
                                        .contentShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(.top, 32)
                .padding(.horizontal, Metrics.gutter)

                section(title: "它陪了你多久") {
                    FlowLayout(spacing: 10) {
                        ForEach(Companionship.allCases) { option in
                            ChoiceChip(title: option.title, isSelected: model.companionship == option) {
                                model.companionship = option
                            }
                        }
                    }
                }
                .padding(.top, 36)

                section(title: "岁月留下的痕迹", note: "可多选，会画进物灵里") {
                    FlowLayout(spacing: 10) {
                        ForEach(WearMark.allCases) { mark in
                            ChoiceChip(title: mark.title, isSelected: model.wearMarks.contains(mark)) {
                                model.toggle(mark)
                            }
                        }
                    }
                }
                .padding(.top, 28)

                section(title: "关于它的一段记忆", note: "选填") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("比如：高三那年，它陪我跑完了每一个清晨。", text: $model.memory, axis: .vertical)
                            .font(.wlBody)
                            .lineLimit(3...6)
                            .focused($focusedField, equals: .memory)
                            .padding(16)
                            .background(Color.card, in: RoundedRectangle(cornerRadius: Metrics.smallRadius, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: Metrics.smallRadius, style: .continuous)
                                    .strokeBorder(Color.hairline, lineWidth: 1)
                            }
                        Label("只保存在这台手机上，不会上传", systemImage: "lock")
                            .font(.system(size: 12))
                            .foregroundStyle(.inkSecondary)
                    }
                }
                .padding(.top, 28)
                .padding(.bottom, 32)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .overlay(alignment: .topTrailing) {
            Button {
                model.retake()
            } label: {
                Label("重拍", systemImage: "camera.rotate")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 4)
                    .frame(height: 32)
            }
            .buttonStyle(.glass)
            .foregroundStyle(.ink)
            .padding(.trailing, Metrics.gutter)
            .padding(.top, 14)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                focusedField = nil
                Task { await model.awaken() }
            } label: {
                Label("唤醒它", systemImage: "sparkles")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(.vermilion)
            .disabled(model.needsNaming && model.objectName.trimmingCharacters(in: .whitespaces).isEmpty)
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 8)
        }
        .sensoryFeedback(.selection, trigger: model.companionship)
        .onChange(of: model.companionship) { RitualSound.play(.tick) }
        .sensoryFeedback(.selection, trigger: model.wearMarks)
        .sensoryFeedback(.selection, trigger: model.object)
        .sensoryFeedback(.impact(weight: .light), trigger: lifted)
        .onAppear {
            Task {
                try? await Task.sleep(for: .milliseconds(250))
                RitualSound.play(.peel)
                lifted = true
            }
        }
    }

    /// 完全认不出来时给的几个常见选项
    private static let commonKinds: [ObjectKind] = ["跑鞋", "马克杯", "玩偶熊", "耳机"].compactMap {
        ObjectCatalog.kind(matchingChinese: $0)
    }

    private func section<Content: View>(title: String, note: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.wlHeadline)
                if let note {
                    Text(note)
                        .font(.system(size: 13))
                        .foregroundStyle(.inkSecondary)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Metrics.gutter)
    }
}

/// 选项小胶囊：选中时墨底纸字，未选中时细线描边
struct ChoiceChip: View {
    var title: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .foregroundStyle(isSelected ? Color.paper : Color.ink)
                .background {
                    Capsule().fill(isSelected ? Color.ink : Color.clear)
                }
                .overlay {
                    Capsule().strokeBorder(isSelected ? Color.clear : Color.ink.opacity(0.18), lineWidth: 1)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.smooth(duration: 0.25), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// 自动换行的横向布局
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > bounds.width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
