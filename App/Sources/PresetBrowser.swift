import SwiftUI

struct PresetItem: Identifiable {
    let id: UInt32
    let title: String
    let author: String?

    // Preset filenames conventionally start with the author: "Author - Title.milk"
    static func parse(filename: String) -> (title: String, author: String?) {
        let stem = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        let parts = stem.components(separatedBy: " - ")
        if parts.count >= 2 {
            return (parts.dropFirst().joined(separator: " - "), parts[0])
        }
        return (stem, nil)
    }
}

struct PresetBrowserView: View {
    let presets: [PresetItem]
    let onSelect: (UInt32) -> Void
    @State private var search = ""

    private var filtered: [PresetItem] {
        guard !search.isEmpty else { return presets }
        return presets.filter {
            $0.title.localizedCaseInsensitiveContains(search)
                || ($0.author?.localizedCaseInsensitiveContains(search) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search \(presets.count) presets", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(10)
            Divider()
            List(filtered) { preset in
                Button {
                    onSelect(preset.id)
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(preset.title)
                            .lineLimit(1)
                        if let author = preset.author {
                            Text(author)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.inset)
        }
    }
}
