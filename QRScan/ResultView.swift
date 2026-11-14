import SwiftUI
import UIKit

struct ScanResultsView: View {
    let results: ScanResults
    var allowsOpeningLinks = true
    var onFinish: (() -> Void)?
    var onSelect: ((ScanResult) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var selection: UUID?

    var body: some View {
        NavigationStack {
            if results.items.count == 1, let result = results.items.first {
                ResultView(result: result, allowsOpeningLinks: allowsOpeningLinks, onFinish: onFinish)
            } else {
                List {
                    if let image = results.image {
                        photoPreview(image)
                            .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                    }
                    ForEach(Array(results.items.enumerated()), id: \.element.id) { index, result in
                        Button {
                            select(result)
                        } label: {
                            HStack(spacing: 12) {
                                Text(index + 1, format: .number)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 4) {
                                    if let title = result.link?.host ?? result.format?.rawValue {
                                        Text(verbatim: title)
                                            .font(.headline)
                                            .lineLimit(1)
                                    }
                                    Text(verbatim: result.raw)
                                        .font(.subheadline)
                                        .lineLimit(2)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .navigationDestination(item: $selection) { id in
                    if let result = results.items.first(where: { $0.id == id }) {
                        ResultView(result: result, allowsOpeningLinks: allowsOpeningLinks, onFinish: {
                            if let onFinish { onFinish() } else { dismiss() }
                        })
                    }
                }
                .navigationTitle("Choose a Result")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            if let onFinish { onFinish() } else { dismiss() }
                        }
                    }
                }
            }
        }
        .tint(.scanMint)
        .presentationDragIndicator(.visible)
    }

    private func select(_ result: ScanResult) {
        onSelect?(result)
        selection = result.id
    }

    private func photoPreview(_ image: CGImage) -> some View {
        let aspectRatio = CGFloat(image.width) / CGFloat(image.height)
        return GeometryReader { geometry in
            let width = min(geometry.size.width, geometry.size.height * aspectRatio)
            let height = width / aspectRatio
            Image(decorative: image, scale: 1)
                .resizable()
                .overlay {
                    ForEach(Array(results.items.enumerated()), id: \.element.id) { index, result in
                        if let bounds = result.imageBounds {
                            let x = min(max(bounds.midX * width, 22), width - 22)
                            let y = min(max(bounds.midY * height, 22), height - 22)
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(Color.scanMint, lineWidth: 2)
                                .frame(width: bounds.width * width, height: bounds.height * height)
                                .position(x: bounds.midX * width, y: bounds.midY * height)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                            Button {
                                select(result)
                            } label: {
                                Text(index + 1, format: .number)
                                    .font(.caption.bold())
                                    .foregroundStyle(Color.scanInk)
                                    .frame(width: 26, height: 26)
                                    .background(Color.scanMint, in: Circle())
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("View code \(index + 1)")
                            .position(x: x, y: y)
                        }
                    }
                }
                .frame(width: width, height: height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .frame(maxHeight: 300)
        .frame(maxWidth: .infinity)
    }
}

struct ResultView: View {
    let result: ScanResult
    var allowsOpeningLinks = true
    var onFinish: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var copiedItem: String?
    @State private var showOpenError = false
    @State private var showsEncodedParameters = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let link = result.link {
                    linkSummary(link)
                    if !link.parameters.isEmpty {
                        queryParameters(link.parameters)
                    }
                }
                rawContent
            }
            .frame(maxWidth: 580)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Scan Result")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    if let onFinish { onFinish() } else { dismiss() }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actions
        }
        .alert("Couldn’t Open Link", isPresented: $showOpenError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You can copy the original link.")
        }
        .task(id: copiedItem) {
            guard copiedItem != nil else { return }
            do {
                try await Task.sleep(for: .seconds(1.7))
                copiedItem = nil
            } catch {}
        }
    }

    private func linkSummary(_ link: ScannedLink) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "link")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.scanMint)
                    .padding(11)
                    .background(Color.scanMint.opacity(0.13), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Link")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(link.host ?? link.path)
                        .font(.title3.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                detail("Scheme", link.scheme)
                if let port = link.port {
                    detail("Port", String(port))
                }
                if link.host != nil {
                    detail("Path", link.path.isEmpty ? "/" : link.path)
                }
                if let fragment = link.fragment {
                    detail("Fragment", fragment.isEmpty ? String(localized: "(Empty)") : fragment)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(cardBackground)
    }

    private func detail(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(verbatim: value)
                .font(.subheadline.monospaced())
        }
    }

    private func queryParameters(_ parameters: [ScannedLink.Parameter]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Query Parameters · \(parameters.count)")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Picker("Parameter display", selection: $showsEncodedParameters) {
                Text("Decoded").tag(false)
                Text("Original").tag(true)
            }
            .pickerStyle(.segmented)
            .onChange(of: showsEncodedParameters) { _, _ in copiedItem = nil }

            VStack(spacing: 0) {
                ForEach(parameters) { parameter in
                    let name = showsEncodedParameters ? parameter.encodedName : parameter.name
                    let displayedValue = showsEncodedParameters ? parameter.encodedValue : parameter.value
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(verbatim: name.isEmpty ? String(localized: "(Empty name)") : name)
                                .font(.subheadline.monospaced().weight(.semibold))
                            Text(verbatim: displayedValue.map { $0.isEmpty ? String(localized: "(Empty value)") : $0 }
                                 ?? String(localized: "(No value)"))
                                .font(.subheadline.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if let value = displayedValue {
                            let item = "parameter-\(parameter.id)"
                            Button {
                                copy(value, item: item)
                            } label: {
                                Image(systemName: copiedItem == item ? "checkmark" : "document.on.document")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(Color.scanMint)
                                    .frame(width: 44, height: 44)
                                    .background(Color.scanMint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text((name.isEmpty ? "Copy parameter value" : "Copy value of \(name)") as LocalizedStringKey))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    if parameter.id != parameters.last?.id {
                        Divider().padding(.horizontal, 16)
                    }
                }
            }
            .background(cardBackground)
        }
    }

    private var rawContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text((result.link == nil ? "Scanned Content" : "Original Link") as LocalizedStringKey)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if let format = result.format {
                Text(verbatim: format.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(verbatim: result.raw)
                .font(.subheadline.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(cardBackground)
        }
    }

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                copyButton
                if allowsOpeningLinks, let link = result.link { openButton(link) }
            }
            VStack(spacing: 10) {
                copyButton
                if allowsOpeningLinks, let link = result.link { openButton(link) }
            }
        }
        .frame(maxWidth: 580)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }

    private var copyButton: some View {
        Button {
            copy(result.raw, item: "raw")
        } label: {
            let title: LocalizedStringKey = copiedItem == "raw" ? "Copied" : (result.link == nil ? "Copy Content" : "Copy Link")
            Label(title,
                  systemImage: copiedItem == "raw" ? "checkmark" : "document.on.document")
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.scanMint)
        .background(Color.scanMint.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
    }

    private func openButton(_ link: ScannedLink) -> some View {
        Button {
            openURL(link.url) { accepted in
                showOpenError = !accepted
            }
        } label: {
            Label("Open Link", systemImage: "arrow.up.right")
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.scanInk)
        .background(Color.scanMint, in: RoundedRectangle(cornerRadius: 13))
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 17)
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
    }

    private func copy(_ text: String, item: String) {
        UIPasteboard.general.string = text
        copiedItem = item
        UIAccessibility.post(notification: .announcement, argument: String(localized: "Copied"))
    }
}

extension Color {
    static let scanMint = Color(red: 0.47, green: 0.94, blue: 0.73)
    static let scanInk = Color(red: 0.05, green: 0.11, blue: 0.09)
}
