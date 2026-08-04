import SwiftUI

struct PresetItem: Identifiable {
    let id: UInt32
    let title: String
    let author: String?
    let category: String

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

struct PresetSection: Identifiable {
    var id: String { name }
    let name: String
    let items: [PresetItem]
}

struct PresetBrowserView: View {
    private let sections: [PresetSection]
    private let onSelect: (UInt32) -> Void
    @State private var search = ""

    init(presets: [PresetItem], onSelect: @escaping (UInt32) -> Void) {
        self.onSelect = onSelect
        let grouped = Dictionary(grouping: presets, by: \.category)
        sections = grouped.keys
            .sorted { a, b in
                if a == "Your Presets" { return false }
                if b == "Your Presets" { return true }
                return a.localizedStandardCompare(b) == .orderedAscending
            }
            .map { PresetSection(name: $0, items: grouped[$0] ?? []) }
    }

    private var filteredSections: [PresetSection] {
        guard !search.isEmpty else { return sections }
        return sections.compactMap { section in
            let items = section.items.filter {
                $0.title.localizedCaseInsensitiveContains(search)
                    || ($0.author?.localizedCaseInsensitiveContains(search) ?? false)
            }
            return items.isEmpty ? nil : PresetSection(name: section.name, items: items)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search presets", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(10)
            Divider()
            List(filteredSections) { section in
                Section(section.name) {
                    ForEach(section.items) { preset in
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
                }
            }
            .listStyle(.inset)
        }
    }
}
