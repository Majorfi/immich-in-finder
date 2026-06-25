import SwiftUI

enum AppTab: Hashable {
    case setup
    case options
}

// A Finder-style tab strip: equal-width tabs aligned to the form content, the
// active one a grey rounded chip. The tabs are not focusable so the window does
// not open with a focus ring on a tab.
struct TabStrip: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 4) {
            tabButton(.setup, title: "Setup")
            tabButton(.options, title: "Options")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
    }

    private func tabButton(_ tab: AppTab, title: String) -> some View {
        let isSelected = selection == tab
        let weight: Font.Weight = if isSelected { .semibold } else { .regular }
        let textColor: Color = if isSelected { .primary } else { .secondary }
        let fillOpacity: Double = if isSelected { 0.1 } else { 0.04 }
        return Button {
            selection = tab
        } label: {
            Text(title)
                .font(.subheadline.weight(weight))
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(fillOpacity))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}
