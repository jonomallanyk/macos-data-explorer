import Foundation

/// What a file probably is, based on its extension.
public struct FileTypeHint: Sendable {
    public let title: String
    public let description: String
    public let ifDeleted: String
    public let safety: SafetyLevel
}

public enum FileTypeHints {
    /// Folder extensions Finder treats as a single item.
    public static let packageExtensions: Set<String> = [
        "app", "appex", "bundle", "framework", "plugin", "kext", "xpc", "prefpane", "qlgenerator",
        "photoslibrary", "photolibrary", "migratedphotolibrary", "aplibrary", "musiclibrary", "tvlibrary",
        "fcpbundle", "imovielibrary", "theater", "logicx", "band", "lrlibrary", "lrdata",
        "pvm", "vmwarevm", "utm", "sparsebundle", "xcarchive", "xcodeproj", "xcworkspace", "playground",
        "dsym", "rtfd", "pages", "numbers", "key", "backupbundle",
    ]

    /// Packages that hold someone's media. Pieces of them are never deleted individually.
    public static let mediaLibraryExtensions: Set<String> = [
        "photoslibrary", "photolibrary", "migratedphotolibrary", "aplibrary", "musiclibrary", "tvlibrary",
        "fcpbundle", "imovielibrary", "lrlibrary",
    ]

    public static func hint(forExtension ext: String, isDirectory: Bool) -> FileTypeHint? {
        guard !ext.isEmpty else { return nil }
        return isDirectory ? folderHints[ext] : fileHints[ext]
    }

    private static func make(_ title: String, _ description: String, _ ifDeleted: String, _ safety: SafetyLevel) -> FileTypeHint {
        FileTypeHint(title: title, description: description, ifDeleted: ifDeleted, safety: safety)
    }

    private static let installerDeleted = "The installer is gone. Apps you already installed from it keep working."

    private static let folderHints: [String: FileTypeHint] = {
        var table: [String: FileTypeHint] = [:]
        table["app"] = make(
            "Application",
            "An app. Moving it to the Trash uninstalls it, though its settings and caches stay in your Library folder.",
            "The app is uninstalled. You can reinstall it from the App Store or the developer's website.",
            .review
        )
        let photos = make(
            "Photos library",
            "A Photos library containing your pictures and videos. Turn on Optimize Mac Storage in Photos › Settings › iCloud to keep only small versions on this Mac.",
            "All photos and videos stored only in this library would be lost.",
            .protected
        )
        for ext in ["photoslibrary", "photolibrary", "migratedphotolibrary", "aplibrary"] { table[ext] = photos }
        table["musiclibrary"] = make(
            "Music library",
            "The Music app's library database. Remove downloads from inside the Music app instead.",
            "Your playlists, ratings and library would be reset.",
            .protected
        )
        table["tvlibrary"] = make(
            "TV library",
            "The TV app's library database. Remove downloaded shows and films from inside the TV app.",
            "Your TV library would be reset.",
            .protected
        )
        table["fcpbundle"] = make(
            "Final Cut Pro library",
            "A Final Cut Pro library. To shrink it, open it in Final Cut Pro and choose File › Delete Generated Library Files.",
            "All projects and media stored in this library would be lost.",
            .protected
        )
        table["imovielibrary"] = make(
            "iMovie library",
            "An iMovie library with your projects and imported clips. Delete projects and events from inside iMovie.",
            "All iMovie projects and imported clips would be lost.",
            .protected
        )
        table["lrlibrary"] = make(
            "Lightroom library",
            "A Lightroom library with your photos and edits. Manage it from inside Lightroom.",
            "Photos and edits stored in this library would be lost.",
            .protected
        )
        table["lrdata"] = make(
            "Lightroom previews",
            "Preview images Lightroom Classic generates for your catalog. Lightroom rebuilds them as needed.",
            "Lightroom regenerates previews, which can be slow the first time you browse.",
            .safe
        )
        table["logicx"] = make(
            "Logic Pro project",
            "A Logic Pro project, including its recordings.",
            "The project and its recordings are deleted.",
            .review
        )
        table["band"] = make(
            "GarageBand project",
            "A GarageBand project, including its recordings.",
            "The project and its recordings are deleted.",
            .review
        )
        for ext in ["pvm", "vmwarevm", "utm"] {
            table[ext] = make(
                "Virtual machine",
                "A complete virtual computer: its operating system, apps and files, all in one package.",
                "The virtual machine and everything installed inside it are gone.",
                .review
            )
        }
        table["sparsebundle"] = make(
            "Disk image (sparse bundle)",
            "A growable disk image. Often an encrypted volume or an old network Time Machine backup.",
            "Everything stored inside the image is deleted.",
            .review
        )
        table["xcarchive"] = make(
            "Xcode archive",
            "An archived build of an app made in Xcode. Needed to read crash reports from that exact build.",
            "You can't symbolicate crash reports for that build any more.",
            .review
        )
        table["dsym"] = make(
            "Debug symbols",
            "Debug symbols used to make crash reports readable.",
            "Crash reports for that build become harder to read.",
            .review
        )
        table["backupbundle"] = make(
            "Backup",
            "A backup made by an app or by macOS.",
            "The backup is gone.",
            .review
        )
        return table
    }()

    private static let fileHints: [String: FileTypeHint] = {
        var table: [String: FileTypeHint] = [:]
        table["dmg"] = make(
            "Disk image",
            "Usually an installer you downloaded. Once the app is installed you rarely need it.",
            installerDeleted,
            .review
        )
        for ext in ["pkg", "mpkg"] {
            table[ext] = make("Installer package", "An installer. Once you've installed it you rarely need it.", installerDeleted, .review)
        }
        for ext in ["iso", "img", "cdr"] {
            table[ext] = make("Disk image", "A disk image, often an operating system installer.", "The image is gone.", .review)
        }
        table["ipsw"] = make(
            "Device firmware",
            "Firmware for an iPhone, iPad or Mac, downloaded to update or restore it. Apple re-downloads it when needed.",
            "Nothing important. It's downloaded again the next time it's needed.",
            .safe
        )
        table["xip"] = make("Xcode download", "A compressed Xcode download.", installerDeleted, .review)
        for ext in ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "zst"] {
            table[ext] = make("Compressed archive", "A compressed archive. Check whether you've already extracted it.", "The archive is gone. Extracted copies are unaffected.", .review)
        }
        for ext in ["mov", "mp4", "m4v", "mkv", "avi", "webm", "hevc", "mts", "braw", "r3d", "prores"] {
            table[ext] = make("Video", "A video file.", "The video is gone unless you have another copy.", .review)
        }
        for ext in ["mp3", "m4a", "aac", "wav", "aif", "aiff", "flac", "caf", "alac"] {
            table[ext] = make("Audio", "An audio file.", "The recording is gone unless you have another copy.", .review)
        }
        for ext in ["jpg", "jpeg", "heic", "png", "tif", "tiff", "dng", "cr2", "cr3", "nef", "arw", "raf", "orf", "rw2", "psd", "psb"] {
            table[ext] = make("Image", "A photo or image file.", "The image is gone unless you have another copy.", .review)
        }
        for ext in ["vmdk", "vdi", "qcow2", "vhd", "vhdx", "hdd", "hds"] {
            table[ext] = make(
                "Virtual machine disk",
                "The hard drive of a virtual machine.",
                "The virtual machine loses its disk and everything on it.",
                .review
            )
        }
        table["sparseimage"] = make("Disk image", "A growable disk image.", "Everything stored inside the image is deleted.", .review)
        table["raw"] = make("Raw disk or image data", "Raw data. Often a virtual machine disk (such as Docker.raw) or a camera RAW photo.", "Whatever it stores is gone.", .review)
        for ext in ["gguf", "safetensors", "ckpt", "pt", "pth", "onnx", "mlmodel", "mlpackage", "bin"] {
            table[ext] = make(
                "Model or binary data",
                "Often weights for a downloaded AI model, which can be re-downloaded.",
                "Any app that uses this model will need to download it again.",
                .review
            )
        }
        for ext in ["log", "ips", "crash", "diag", "spin", "hang"] {
            table[ext] = make("Log or crash report", "Diagnostic output written by an app or by macOS.", "Nothing you need. It only helps diagnose old problems.", .safe)
        }
        table["core"] = make("Core dump", "A memory snapshot saved when a program crashed.", "Nothing you need unless you're debugging that crash.", .safe)
        for ext in ["sqlite", "sqlite3", "db", "realm", "ldb"] {
            table[ext] = make("App database", "A database an app uses to store its data.", "The app may lose data or need to rebuild it.", .caution)
        }
        for ext in ["ipa", "apk", "aab"] {
            table[ext] = make("Mobile app package", "An app package for a phone or tablet.", "The package is gone.", .review)
        }
        for ext in ["pdf", "doc", "docx", "pages", "key", "keynote", "ppt", "pptx", "xls", "xlsx", "numbers", "txt", "rtf", "csv"] {
            table[ext] = make("Document", "A document.", "The document is gone unless you have another copy.", .review)
        }
        return table
    }()
}
