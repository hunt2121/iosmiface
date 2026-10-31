import SwiftUI
import UIKit
import BandFaceKit

/// Циферблат у магазині. Поки каталог локальний: файли лежать у застосунку.
struct StoreFace: Identifiable {
    let id: String          // ID циферблата з файла
    let name: String
    let meta: String
    let price: String?      // nil — безкоштовний
    let face: FaceFile
    let preview: UIImage?

    var isFree: Bool { price == nil }
}

enum StoreCatalog {
    private struct Entry {
        let resource: String
        let name: String
        let kind: String
    }

    private static let entries = [
        Entry(resource: "BigWatch_UA", name: "BigWatch", kind: "Цифровий"),
        Entry(resource: "WhatTime_UA", name: "WhatTime", kind: "Гумор")
    ]

    static func load() -> [StoreFace] {
        entries.compactMap { e in
            guard let url = Bundle.main.url(forResource: e.resource, withExtension: "bin"),
                  let data = try? Data(contentsOf: url),
                  let face = try? FaceFile(data: data) else { return nil }
            let image = (try? face.decodePreview()?.makeCGImage()).map(UIImage.init(cgImage:))
            return StoreFace(id: face.id,
                             name: e.name,
                             meta: "\(e.kind) · \(face.size / 1024) KB",
                             price: nil,
                             face: face,
                             preview: image)
        }
    }
}

struct StoreView: View {
    let faces: [StoreFace]
    let installedIDs: Set<String>
    let installingID: String?
    let busy: Bool
    let progress: Double
    let progressText: String
    let onInstall: (StoreFace) -> Void

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(faces) { item in
                        card(item)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Магазин")
        }
    }

    private func card(_ item: StoreFace) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.systemGroupedBackground))
                capsule(item.preview)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if item.isFree {
                    Text("Безкоштовно")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .frame(height: 22)
                        .background(Capsule().fill(Color(red: 0.19, green: 0.71, blue: 0.33)))
                        .padding(8)
                }
            }
            .frame(height: 266)

            VStack(alignment: .leading, spacing: 0) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(item.meta)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)

            action(item)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground)))
    }

    /// Капсула з рамкою ззовні: ті самі розміри й параметри, що на вкладці «Циферблати».
    private func capsule(_ image: UIImage?) -> some View {
        ZStack {
            Capsule(style: .continuous).fill(Color.black)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            }
        }
        .frame(width: 96, height: 236)
        .clipShape(Capsule(style: .continuous))
        .padding(3)
        .background(Capsule(style: .continuous).fill(Color.gray.opacity(0.45)))
    }

    @ViewBuilder
    private func action(_ item: StoreFace) -> some View {
        if busy && installingID == item.id {
            VStack(spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.gray.opacity(0.3))
                        Capsule().fill(Color.accentColor)
                            .frame(width: max(8, geo.size.width * progress))
                    }
                }
                .frame(height: 6)
                HStack {
                    Text(progressText).lineLimit(1)
                    Spacer()
                    Text(verbatim: "\(Int(progress * 100))%")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .frame(height: 36)
        } else if installedIDs.contains(item.id) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                Text("Встановлено")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(Capsule().fill(Color(.systemGroupedBackground)))
        } else {
            Button {
                onInstall(item)
            } label: {
                Text(item.price ?? String(localized: "Встановити"))
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .foregroundStyle(Color.accentColor)
                    .background(Capsule().fill(Color.accentColor.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .disabled(busy)
        }
    }
}
