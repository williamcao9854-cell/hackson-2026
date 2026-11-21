import SwiftData
import SwiftUI

/// 「遇见」全屏流程的容器。
struct EncounterView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var model = EncounterModel()

    var body: some View {
        ZStack {
            PaperBackground()

            Group {
                switch model.stage {
                case .capture:
                    CaptureView(model: model)
                case .story:
                    StoryView(model: model)
                case .awakening:
                    AwakeningView(sticker: model.sticker)
                case .reveal:
                    RevealView(model: model) {
                        model.beginFarewell()
                    } onKeep: {
                        model.save(in: modelContext)
                        dismiss()
                    }
                case .farewell:
                    FarewellView(
                        sticker: model.sticker,
                        spiritImageData: model.spiritImageData,
                        spiritName: model.profile?.name ?? "",
                        palette: model.palette,
                        suggestion: model.profile?.farewellSuggestion ?? "谢谢你。"
                    ) { note in
                        model.save(in: modelContext, releasedWith: note)
                    } onFinish: {
                        dismiss()
                    }
                }
            }
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.98)),
                removal: .opacity
            ))
        }
        .overlay(alignment: .topLeading) {
            if model.stage != .awakening {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .tint(.ink)
                .padding(.leading, Metrics.gutter)
                .padding(.top, 8)
                .accessibilityLabel("关闭")
            }
        }
        .foregroundStyle(.ink)
        .interactiveDismissDisabled(model.stage == .awakening)
    }
}

#Preview {
    EncounterView()
        .modelContainer(for: Spirit.self, inMemory: true)
}
