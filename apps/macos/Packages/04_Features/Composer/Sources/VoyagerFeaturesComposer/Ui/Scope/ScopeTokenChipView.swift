import SwiftUI
import VoyagerShared

struct ScopeTokenChipView: View {
    let title: String
    let path: String?
    let onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            Text("\u{10088A}")
                .font(VoyagerDS.Typography.smallButton)
                .foregroundColor(.secondary)
                .frame(width: 12, height: 12)

            Text(title)
                .font(VoyagerDS.Typography.chip)
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove scope \(title)")
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, onRemove == nil ? 8 : 5)
        .frame(height: ComposerUIMetrics.compactControlHeight)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: VoyagerDS.Radius.chipItem, style: .continuous)
                .fill(VoyagerDS.SystemColor.separator.opacity(0.9)),
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(path.map { "Scope \(title), \($0)" } ?? title)
        .help(path ?? title)
    }
}
