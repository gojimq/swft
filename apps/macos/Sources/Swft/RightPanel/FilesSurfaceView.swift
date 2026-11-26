import AppKit
import SwftDesign
import SwftKit
import SwiftUI

struct FilesSurfaceView: View {
    @Environment(AppModel.self) private var model
    let threadID: String
    let tabID: String
    let filesState: FilesTabState

    @State private var showTreeSidebar = true
    @State private var searchQuery = ""
    @State private var searchResults: [ProjectEntry]?
    @State private var isSearching = false
    @State private var entriesByDirectory: [String: [ProjectEntry]] = [:]
    @State private var expandedDirectories: Set<String> = []
    @State private var loadingDirectories: Set<String> = []
    @State private var treeError: String?

    @State private var loadedFilePath: String?
    @State private var fileReadState: FileReadState = .idle
    @State private var markdownRendered = true
    @State private var copiedFeedback = false

    private enum FileReadState: Equatable {
        case idle
        case loading
        case text(ProjectReadFileResult)
        case image(NSImage, byteCount: Int)
        case binary(path: String, byteLength: Int?, mimeType: String?)
        case error(String)
    }

    private var workspaceRoot: String? {
        model.workspaceRoot(forThreadID: threadID)
    }

    private var projectTitle: String {
        model.threadSummary(for: threadID)?.project?.name ?? "Workspace"
    }

    private var treeRows: [FileTreeRow] {
        RightPanelLogic.buildFileTreeRows(
            entriesByDirectory: entriesByDirectory,
            expandedDirectories: expandedDirectories
        )
    }

    var body: some View {
        if let cwd = workspaceRoot, !cwd.isEmpty {
            VStack(spacing: 0) {
                headerBar(cwd: cwd)
                Divider().overlay(SwftColor.borderSubtle)

                HStack(spacing: 0) {
                    if showTreeSidebar {
                        fileTreeColumn(cwd: cwd)
                            .frame(width: 210)
                        Divider().overlay(SwftColor.borderSubtle)
                    }
                    fileViewerColumn(cwd: cwd)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(SwftColor.canvas)
            .task(id: "\(threadID)::\(cwd)") {
                entriesByDirectory = [:]
                expandedDirectories = []
                searchResults = nil
                await loadDirectory("", cwd: cwd, force: true)
                if let selected = filesState.selectedFilePath {
                    await openAndReadFile(selected, cwd: cwd)
                }
            }
            .onChange(of: filesState.selectedFilePath) { _, newPath in
                guard let newPath, newPath != loadedFilePath else { return }
                Task { await openAndReadFile(newPath, cwd: cwd) }
            }
            .task(id: searchQuery) {
                await performSearch(query: searchQuery, cwd: cwd)
            }
        } else {
            RightPanelEmptyState(
                icon: "folder.badge.questionmark",
                title: "No project attached",
                message: "Files are available when this thread belongs to a project workspace."
            )
        }
    }

    // MARK: - Header & Breadcrumbs

    private func headerBar(cwd: String) -> some View {
        HStack(spacing: 6) {
            IconButton(
                "sidebar.left",
                help: showTreeSidebar ? "Hide file tree" : "Show file tree",
                size: 26,
                tint: showTreeSidebar ? SwftColor.textPrimary : SwftColor.textTertiary
            ) {
                showTreeSidebar.toggle()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    Button {
                        showTreeSidebar = true
                    } label: {
                        Text(projectTitle)
                            .font(SwftType.captionStrong)
                            .foregroundStyle(SwftColor.textPrimary)
                    }
                    .buttonStyle(.plain)

                    if let selected = filesState.selectedFilePath, !selected.isEmpty {
                        let segments = RightPanelLogic.breadcrumbSegments(for: selected)
                        ForEach(Array(segments.enumerated()), id: \.offset) { idx, segment in
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundStyle(SwftColor.textTertiary)
                            let isLast = idx == segments.count - 1
                            Button {
                                if !isLast {
                                    showTreeSidebar = true
                                    expandedDirectories.insert(segment.path)
                                    Task { await loadDirectory(segment.path, cwd: cwd, force: false) }
                                }
                            } label: {
                                Text(segment.name)
                                    .font(isLast ? SwftType.captionStrong : SwftType.caption)
                                    .foregroundStyle(isLast ? SwftColor.textPrimary : SwftColor.textSecondary)
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Spacer(minLength: 4)

            IconButton("arrow.clockwise", help: "Refresh workspace files", size: 26) {
                Task {
                    await refreshAllLoaded(cwd: cwd)
                    if let selected = filesState.selectedFilePath {
                        await openAndReadFile(selected, cwd: cwd, force: true)
                    }
                }
            }
        }
        .rightPanelSubHeader()
    }

    // MARK: - Tree Column

    private func fileTreeColumn(cwd: String) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(SwftColor.textTertiary)
                TextField("Search files…", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(SwftType.caption)
                    .foregroundStyle(SwftColor.textPrimary)
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                        searchResults = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(SwftColor.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(SwftColor.surface))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(SwftColor.borderSubtle, lineWidth: 1))
            .padding(8)

            Divider().overlay(SwftColor.borderSubtle)

            if let treeError, entriesByDirectory.isEmpty {
                RightPanelEmptyState(
                    icon: "exclamationmark.triangle",
                    title: "Couldn’t list files",
                    message: treeError
                ) {
                    Button("Retry") {
                        Task { await loadDirectory("", cwd: cwd, force: true) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else if let searchResults {
                searchResultsList(searchResults, cwd: cwd)
            } else if entriesByDirectory[""] == nil && loadingDirectories.contains("") {
                VStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading files…")
                        .font(SwftType.caption)
                        .foregroundStyle(SwftColor.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(treeRows) { row in
                            fileTreeRowButton(row, cwd: cwd)
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 6)
                }
            }
        }
        .background(SwftColor.sidebar.opacity(0.4))
    }

    private func fileTreeRowButton(_ row: FileTreeRow, cwd: String) -> some View {
        let isSelected = row.kind == .file && filesState.selectedFilePath == row.path
        let isLoadingDir = row.kind == .directory && loadingDirectories.contains(row.path)
        return Button {
            if row.kind == .directory {
                toggleDirectory(row.path, cwd: cwd)
            } else {
                selectFile(row.path, cwd: cwd)
            }
        } label: {
            HStack(spacing: 5) {
                if row.kind == .directory {
                    Image(systemName: row.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(SwftColor.textTertiary)
                        .frame(width: 10)
                } else {
                    Color.clear.frame(width: 10, height: 1)
                }

                Image(systemName: RightPanelLogic.fileSymbol(for: row.path, kind: row.kind, isExpanded: row.isExpanded))
                    .font(.system(size: 11.5))
                    .foregroundStyle(row.kind == .directory ? SwftColor.accent : SwftColor.textSecondary)
                    .frame(width: 14)

                Text(row.name)
                    .font(isSelected ? SwftType.captionStrong : SwftType.caption)
                    .foregroundStyle(isSelected ? SwftColor.textPrimary : SwftColor.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 4)

                if isLoadingDir {
                    ProgressView().controlSize(.mini)
                }
            }
            .padding(.leading, CGFloat(row.depth) * 14 + 4)
            .padding(.trailing, 6)
            .frame(height: 26)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? SwftColor.selection : .clear)
            )
            .opacity(row.ignored ? 0.55 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func searchResultsList(_ entries: [ProjectEntry], cwd: String) -> some View {
        Group {
            if isSearching {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty {
                RightPanelEmptyState(
                    icon: "magnifyingglass",
                    title: "No matches",
                    message: "No files matched “\(searchQuery)”."
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(entries) { entry in
                            let isSelected = entry.kind == .file && filesState.selectedFilePath == entry.path
                            Button {
                                if entry.kind == .directory {
                                    searchQuery = ""
                                    searchResults = nil
                                    expandedDirectories.insert(entry.path)
                                    Task { await loadDirectory(entry.path, cwd: cwd, force: false) }
                                } else {
                                    selectFile(entry.path, cwd: cwd)
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 6) {
                                        Image(systemName: RightPanelLogic.fileSymbol(for: entry.path, kind: entry.kind))
                                            .font(.system(size: 11))
                                            .foregroundStyle(entry.kind == .directory ? SwftColor.accent : SwftColor.textSecondary)
                                        Text(entry.name)
                                            .font(isSelected ? SwftType.captionStrong : SwftType.caption)
                                            .foregroundStyle(SwftColor.textPrimary)
                                            .lineLimit(1)
                                    }
                                    if entry.path != entry.name {
                                        Text(RightPanelLogic.parentDirectory(of: entry.path))
                                            .font(.system(size: 10.5))
                                            .foregroundStyle(SwftColor.textTertiary)
                                            .lineLimit(1)
                                            .truncationMode(.head)
                                            .padding(.leading, 17)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(isSelected ? SwftColor.selection : .clear)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(6)
                }
            }
        }
    }

    // MARK: - Viewer Column

    private func fileViewerColumn(cwd: String) -> some View {
        VStack(spacing: 0) {
            if !filesState.openFilePaths.isEmpty {
                openFilesStrip(cwd: cwd)
                Divider().overlay(SwftColor.borderSubtle)
            }

            switch fileReadState {
            case .idle:
                RightPanelEmptyState(
                    icon: "doc.text.magnifyingglass",
                    title: "Select a file",
                    message: "Choose a file from the workspace tree to inspect its contents."
                )
            case .loading:
                VStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading file…")
                        .font(SwftType.caption)
                        .foregroundStyle(SwftColor.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .text(let result):
                textFileViewer(result)
            case .image(let nsImage, let byteCount):
                imageFileViewer(nsImage, byteCount: byteCount)
            case .binary(let path, let byteLength, let mimeType):
                binaryFileViewer(path: path, byteLength: byteLength, mimeType: mimeType)
            case .error(let message):
                RightPanelEmptyState(
                    icon: "exclamationmark.triangle",
                    title: "Couldn’t open file",
                    message: message
                ) {
                    if let selected = filesState.selectedFilePath {
                        Button("Retry") {
                            Task { await openAndReadFile(selected, cwd: cwd, force: true) }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private func openFilesStrip(cwd: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(filesState.openFilePaths, id: \.self) { path in
                    let isActive = filesState.selectedFilePath == path
                    HStack(spacing: 4) {
                        Button {
                            selectFile(path, cwd: cwd)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: RightPanelLogic.fileSymbol(for: path, kind: .file))
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(isActive ? SwftColor.textPrimary : SwftColor.textTertiary)
                                Text(RightPanelLogic.fileName(from: path))
                                    .font(isActive ? SwftType.captionStrong : SwftType.caption)
                                    .foregroundStyle(isActive ? SwftColor.textPrimary : SwftColor.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)

                        Button {
                            model.rightPanel.closeOpenFile(path, inTabID: tabID, for: threadID)
                            if filesState.selectedFilePath == path {
                                loadedFilePath = nil
                                fileReadState = .idle
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(SwftColor.textTertiary)
                                .frame(width: 14, height: 14)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.leading, 9)
                    .padding(.trailing, 4)
                    .frame(height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isActive ? SwftColor.surface : .clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(isActive ? SwftColor.border : .clear, lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(SwftColor.canvas)
    }

    private func textFileViewer(_ result: ProjectReadFileResult) -> some View {
        let previewKind = RightPanelLogic.classifyFilePreview(path: result.relativePath)
        let isMarkdown = previewKind == .markdown
        let language: String? = {
            if case .code(let lang) = previewKind { return lang }
            return isMarkdown ? "Markdown" : nil
        }()

        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                if let language {
                    RightPanelStatusBadge(language, tone: .neutral)
                }
                Text(RightPanelLogic.formatByteCount(result.byteLength))
                    .font(SwftType.monoSmall)
                    .foregroundStyle(SwftColor.textTertiary)
                if result.truncated {
                    RightPanelStatusBadge("Truncated", tone: .warning)
                }
                Spacer()

                if isMarkdown {
                    Picker("", selection: $markdownRendered) {
                        Text("Preview").tag(true)
                        Text("Source").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(width: 130)
                }

                RightPanelPillButton(
                    copiedFeedback ? "Copied" : "Copy",
                    systemName: copiedFeedback ? "checkmark" : "doc.on.doc",
                    tint: copiedFeedback ? SwftColor.success : nil
                ) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result.contents, forType: .string)
                    copiedFeedback = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.4))
                        copiedFeedback = false
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(SwftColor.canvas)

            Divider().overlay(SwftColor.borderSubtle)

            if isMarkdown && markdownRendered {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(MarkdownBlockParser.parse(result.contents).enumerated()), id: \.offset) { _, block in
                            switch block {
                            case .text(let prose):
                                MessageText(prose)
                            case .code(let lang, let source):
                                CodeBlock(source, language: lang)
                            case .image, .attachments:
                                EmptyView()
                            }
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                numberedCodeScrollView(result.contents)
            }
        }
    }

    private func numberedCodeScrollView(_ contents: String) -> some View {
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let gutterWidth = max(32, CGFloat(String(max(1, lines.count)).count) * 8 + 14)

        return ScrollView([.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    HStack(alignment: .top, spacing: 10) {
                        Text(String(index + 1))
                            .font(SwftType.monoSmall)
                            .monospacedDigit()
                            .foregroundStyle(SwftColor.textTertiary.opacity(0.7))
                            .frame(width: gutterWidth, alignment: .trailing)
                            .textSelection(.disabled)

                        Text(line.isEmpty ? " " : line)
                            .font(SwftType.monoSmall)
                            .foregroundStyle(SwftColor.textPrimary)
                            .fixedSize(horizontal: true, vertical: false)
                            .textSelection(.enabled)
                    }
                    .frame(height: 19)
                }
            }
            .padding(.vertical, 10)
            .padding(.trailing, 20)
        }
        .defaultScrollAnchor(.topLeading)
        .background(SwftColor.codeBackground)
    }

    private func imageFileViewer(_ image: NSImage, byteCount: Int) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                RightPanelStatusBadge("Image", tone: .accent)
                Text("\(Int(image.size.width)) × \(Int(image.size.height)) · \(RightPanelLogic.formatByteCount(byteCount))")
                    .font(SwftType.monoSmall)
                    .foregroundStyle(SwftColor.textTertiary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(SwftColor.canvas)

            Divider().overlay(SwftColor.borderSubtle)

            GeometryReader { geo in
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: max(200, geo.size.width - 32), maxHeight: max(200, geo.size.height - 32))
                        .clipShape(RoundedRectangle(cornerRadius: SwftRadius.s, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: SwftRadius.s, style: .continuous)
                                .strokeBorder(SwftColor.borderSubtle, lineWidth: 1)
                        )
                        .padding(16)
                        .frame(minWidth: geo.size.width, minHeight: geo.size.height)
                }
            }
            .background(SwftColor.codeBackground)
        }
    }

    private func binaryFileViewer(path: String, byteLength: Int?, mimeType: String?) -> some View {
        let details = [
            mimeType,
            byteLength.map(RightPanelLogic.formatByteCount),
        ].compactMap { $0 }.joined(separator: " · ")

        return RightPanelEmptyState(
            icon: "doc.zipper",
            title: RightPanelLogic.fileName(from: path),
            message: details.isEmpty
                ? "Binary file preview is not supported in text view."
                : "Binary file (\(details)) cannot be displayed as text."
        )
    }

    // MARK: - Actions & RPC Calls

    private func toggleDirectory(_ path: String, cwd: String) {
        if expandedDirectories.contains(path) {
            expandedDirectories.remove(path)
        } else {
            expandedDirectories.insert(path)
            if entriesByDirectory[path] == nil {
                Task { await loadDirectory(path, cwd: cwd, force: false) }
            }
        }
    }

    private func selectFile(_ path: String, cwd: String) {
        model.rightPanel.updateFilesTab(
            tabID: tabID,
            selectedFilePath: path,
            folderPath: RightPanelLogic.parentDirectory(of: path),
            for: threadID
        )
        Task { await openAndReadFile(path, cwd: cwd) }
    }

    private func loadDirectory(_ directoryPath: String, cwd: String, force: Bool) async {
        if !force && entriesByDirectory[directoryPath] != nil { return }
        loadingDirectories.insert(directoryPath)
        defer { loadingDirectories.remove(directoryPath) }

        if model.isMock {
            entriesByDirectory[directoryPath] = RightPanelMockData.directoryEntries[directoryPath] ?? []
            treeError = nil
            return
        }

        guard let conn = model.connection(forThreadID: threadID) else {
            treeError = "Environment is not connected."
            return
        }
        do {
            let result = try await conn.listProjectEntries(
                cwd: cwd,
                directoryPath: directoryPath.isEmpty ? nil : directoryPath
            )
            entriesByDirectory[directoryPath] = result.entries
            treeError = nil
        } catch {
            if directoryPath.isEmpty {
                treeError = error.localizedDescription
            }
        }
    }

    private func refreshAllLoaded(cwd: String) async {
        let targets = [""] + Array(expandedDirectories)
        for dir in targets {
            await loadDirectory(dir, cwd: cwd, force: true)
        }
    }

    private func performSearch(query: String, cwd: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = nil
            isSearching = false
            return
        }
        isSearching = true
        try? await Task.sleep(for: .milliseconds(160))
        guard !Task.isCancelled else { return }

        if model.isMock {
            searchResults = RightPanelMockData.searchEntries(query: trimmed)
            isSearching = false
            return
        }

        guard let conn = model.connection(forThreadID: threadID) else {
            searchResults = []
            isSearching = false
            return
        }
        do {
            let result = try await conn.searchProjectEntries(cwd: cwd, query: trimmed, limit: 100)
            guard !Task.isCancelled else { return }
            searchResults = result.entries
        } catch {
            searchResults = []
        }
        isSearching = false
    }

    private func openAndReadFile(_ path: String, cwd: String, force: Bool = false) async {
        if !force, loadedFilePath == path, fileReadState != .idle { return }
        loadedFilePath = path
        fileReadState = .loading

        let previewKind = RightPanelLogic.classifyFilePreview(path: path)
        if model.isMock {
            switch previewKind {
            case .image:
                let png = RightPanelMockData.mockImagePNGData(title: path, size: CGSize(width: 640, height: 360))
                if let img = NSImage(data: png) {
                    fileReadState = .image(img, byteCount: png.count)
                } else {
                    fileReadState = .binary(path: path, byteLength: png.count, mimeType: "image/png")
                }
            case .binary:
                fileReadState = .binary(path: path, byteLength: 42_180, mimeType: "application/zip")
            case .markdown, .code:
                let contents = RightPanelMockData.fileContents[path] ?? "// Mock contents for \(path)\n"
                fileReadState = .text(ProjectReadFileResult(
                    relativePath: path,
                    contents: contents,
                    byteLength: contents.utf8.count,
                    truncated: false,
                    exists: true
                ))
            }
            return
        }

        guard let conn = model.connection(forThreadID: threadID) else {
            fileReadState = .error("Environment is not connected.")
            return
        }

        if previewKind == .image {
            do {
                let data: Data
                do {
                    data = try await conn.fetchAsset(.workspaceFile(threadId: threadID, path: path))
                } catch {
                    data = try await conn.fetchAsset(.mediaFile(threadId: threadID, path: path))
                }
                if let img = NSImage(data: data) {
                    fileReadState = .image(img, byteCount: data.count)
                } else {
                    fileReadState = .binary(path: path, byteLength: data.count, mimeType: "image/*")
                }
            } catch {
                fileReadState = .error(error.localizedDescription)
            }
            return
        }

        if previewKind == .binary {
            let fullPath = cwd.hasSuffix("/") ? "\(cwd)\(path)" : "\(cwd)/\(path)"
            let metadata = try? await conn.getFilesystemMetadata(paths: [fullPath]).entries.first ?? nil
            fileReadState = .binary(path: path, byteLength: metadata?.byteLength, mimeType: metadata?.mimeType)
            return
        }

        do {
            let result = try await conn.readProjectFile(cwd: cwd, relativePath: path)
            fileReadState = .text(result)
        } catch {
            let message = error.localizedDescription
            if message.localizedCaseInsensitiveContains("binary") {
                let fullPath = cwd.hasSuffix("/") ? "\(cwd)\(path)" : "\(cwd)/\(path)"
                let metadata = try? await conn.getFilesystemMetadata(paths: [fullPath]).entries.first ?? nil
                fileReadState = .binary(path: path, byteLength: metadata?.byteLength, mimeType: metadata?.mimeType)
            } else {
                fileReadState = .error(message)
            }
        }
    }
}
