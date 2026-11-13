import SwiftUI
import UIKit

struct ScanResultsView: View {
    let results: ScanResults

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            if results.items.count == 1, let result = results.items.first {
                ResultView(result: result)
            } else {
                List(results.items) { result in
                    NavigationLink {
                        ResultView(result: result)
                    } label: {
                        Text(verbatim: result.raw)
                            .lineLimit(3)
                    }
                }
                .navigationTitle("Choose a Result")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
        .tint(.scanMint)
        .presentationDragIndicator(.visible)
    }
}

struct ResultView: View {
    let result: ScanResult

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var copiedItem: String?
    @State private var showOpenError = false

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
                Button("Done") { dismiss() }
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

            VStack(spacing: 0) {
                ForEach(parameters) { parameter in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(verbatim: parameter.name.isEmpty ? String(localized: "(Empty name)") : parameter.name)
                                .font(.subheadline.monospaced().weight(.semibold))
                            Text(verbatim: parameter.value.map { $0.isEmpty ? String(localized: "(Empty value)") : $0 }
                                 ?? String(localized: "(No value)"))
                                .font(.subheadline.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if let value = parameter.value {
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
                            .accessibilityLabel(Text((parameter.name.isEmpty ? "Copy parameter value" : "Copy value of \(parameter.name)") as LocalizedStringKey))
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
                if let link = result.link { openButton(link) }
            }
            VStack(spacing: 10) {
                copyButton
                if let link = result.link { openButton(link) }
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
