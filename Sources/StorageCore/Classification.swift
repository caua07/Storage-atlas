import Foundation

public struct RecognitionRule: Sendable, Identifiable {
    public let id: String
    public let title: String
    public let category: StorageCategory
    public let evidence: String
    public let explanation: String
    public let consequence: String
    public let reviewable: Bool
}

public enum RuleCatalog {
    /// Snapshot taxonomy: v1 combined models/media; v2 separates models without rewriting old rows.
    public static let classificationVersion = 2
    public static let rules: [RecognitionRule] = [
        .init(id: "node", title: "Node dependencies", category: .development, evidence: "Inside a directory named node_modules.", explanation: "Installed JavaScript packages, usually associated with the enclosing project. Multiple projects can each have their own dependency tree.", consequence: "Reinstallation may need a package manifest, lockfile, network access, and available package versions. Local edits or linked packages need individual review.", reviewable: true),
        .init(id: "rust", title: "Rust build output", category: .development, evidence: "A target directory beside a Cargo.toml manifest.", explanation: "Cargo compilation output, incremental artifacts, and debug or release binaries.", consequence: "A future build will need to compile again. Preserve any binaries or other files you intentionally stored here.", reviewable: true),
        .init(id: "python", title: "Python environment", category: .development, evidence: "A directory containing pyvenv.cfg.", explanation: "An isolated Python interpreter and installed packages for a project.", consequence: "Recreation needs the correct Python version and dependency specification. Editable packages, local changes, and unavailable versions need review.", reviewable: true),
        .init(id: "bytecode", title: "Python bytecode", category: .caches, evidence: "Inside a directory named __pycache__.", explanation: "Compiled Python bytecode created when Python imports source modules.", consequence: "Normally recreated when the matching source is imported. Confirm the source is still available.", reviewable: true),
        .init(id: "xcode", title: "Xcode build output", category: .development, evidence: "Inside Library/Developer/Xcode/DerivedData.", explanation: "Build products and indexing data maintained by Xcode.", consequence: "Xcode may rebuild and reindex projects. Build time and CPU use can increase after removal.", reviewable: true),
        .init(id: "simulator", title: "Simulator data", category: .development, evidence: "Inside Library/Developer/CoreSimulator.", explanation: "Simulator runtimes, devices, and their application data.", consequence: "This can include persistent simulator app data. Manage devices and runtimes through Xcode; do not treat the entire directory as disposable.", reviewable: false),
        .init(id: "package-cache", title: "Package download cache", category: .caches, evidence: "A recognized npm, pnpm, pip, Cargo registry, or Homebrew cache path.", explanation: "Downloaded packages and reusable installation material shared across projects.", consequence: "Future installs may download packages again. Use the owning tool's supported maintenance workflow and preserve offline requirements.", reviewable: true),
        .init(id: "git", title: "Git metadata", category: .development, evidence: "Inside a directory named .git.", explanation: "Repository history, objects, refs, configuration, and potentially unpushed work.", consequence: "Keep this with its repository. Removing it can lose local history, stashes, and repository state.", reviewable: false),
        .init(id: "build", title: "Project build output", category: .development, evidence: "A .build, build, or dist directory beside a recognized project manifest.", explanation: "Likely generated build artifacts based on directory name and neighboring project metadata.", consequence: "Review project build configuration first. A conventional output directory can also contain manually maintained files.", reviewable: true),
        .init(id: "container", title: "Container storage", category: .development, evidence: "Inside a recognized Docker or container runtime data path.", explanation: "Images, layers, virtual disks, and potentially persistent application volumes.", consequence: "Volumes can hold irreplaceable databases. Use the container tool to distinguish images, build cache, and persistent data.", reviewable: false),
        .init(id: "model", title: "Local model weights", category: .models, evidence: "A recognized model extension or Ollama model directory.", explanation: "Weights or checkpoints used by local machine-learning tools.", consequence: "May require a large download to restore. A checkpoint can contain your own training work; confirm its origin.", reviewable: false),
        .init(id: "app", title: "Application bundle", category: .applications, evidence: "Inside a directory ending in .app.", explanation: "An application and its bundled resources. Related user data may live separately in Library.", consequence: "This measurement does not include every file the app owns. Removing the app does not necessarily remove its data.", reviewable: false),
        .init(id: "cache", title: "Application cache", category: .caches, evidence: "Inside a Library/Caches directory.", explanation: "Files an application stores in a conventional cache location. Ownership is inferred from the enclosing path.", consequence: "Applications may recreate or download these files. Review with the owning application closed; the path alone does not prove the contents are expendable.", reviewable: true)
    ]
    public static func rule(_ id: String?) -> RecognitionRule? { rules.first { $0.id == id } }

    public static func recognizeDirectory(_ url: URL, inherited: RecognitionRule?) -> RecognitionRule? {
        // The enclosing artifact owns its contents. This prevents thousands of nested cleanup candidates.
        if let inherited { return inherited }
        let name = url.lastPathComponent
        let path = url.path
        func atOrInside(_ suffix: String) -> Bool { path.hasSuffix(suffix) || path.contains(suffix + "/") }
        let fm = FileManager.default
        let parent = url.deletingLastPathComponent()
        func exists(_ name: String) -> Bool { fm.fileExists(atPath: parent.appendingPathComponent(name).path) }
        let id: String?
        if name == "node_modules" { id = "node" }
        else if name == ".git" { id = "git" }
        else if name == "__pycache__" { id = "bytecode" }
        else if name == "target" && exists("Cargo.toml") { id = "rust" }
        else if fm.fileExists(atPath: url.appendingPathComponent("pyvenv.cfg").path) { id = "python" }
        else if atOrInside("/Library/Developer/Xcode/DerivedData") { id = "xcode" }
        else if atOrInside("/Library/Developer/CoreSimulator") { id = "simulator" }
        else if path.contains("/Library/Containers/com.docker.") || atOrInside("/.docker/desktop") || atOrInside("/.local/share/containers") { id = "container" }
        else if atOrInside("/.ollama/models") { id = "model" }
        else if [".npm", ".pnpm-store"].contains(name) || atOrInside("/.cargo/registry") || atOrInside("/Library/Caches/pip") || atOrInside("/Library/Caches/Homebrew") || atOrInside("/Library/pnpm/store") { id = "package-cache" }
        else if url.pathExtension.lowercased() == "app" { id = "app" }
        else if [".build", "build", "dist"].contains(name) && ["Package.swift", "package.json", "CMakeLists.txt", "pyproject.toml", "build.gradle"].contains(where: exists) { id = "build" }
        else if path.contains("/Library/Caches/") { id = "cache" }
        else { id = nil }
        return rule(id)
    }

    public static func category(for url: URL, inherited: RecognitionRule?) -> StorageCategory {
        if let inherited { return inherited.category }
        switch url.pathExtension.lowercased() {
        case "swift", "rs", "c", "h", "cpp", "hpp", "m", "mm", "js", "jsx", "ts", "tsx", "py", "go", "java", "kt", "rb", "sh", "o", "a", "dylib", "wasm", "lock": return .development
        case "zip", "gz", "xz", "bz2", "tar", "7z", "rar", "dmg", "pkg", "iso": return .archives
        case "gguf", "safetensors", "onnx", "ckpt": return .models
        case "jpg", "jpeg", "png", "heic", "gif", "webp", "svg", "mov", "mp4", "mkv", "mp3", "wav", "flac", "aiff": return .media
        case "pdf", "doc", "docx", "txt", "md", "rtf", "pages", "numbers", "xlsx", "csv", "pptx", "key": return .documents
        default: return .other
        }
    }
}
