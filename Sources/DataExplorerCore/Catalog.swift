import Foundation

/// The built-in list of places on a Mac and what they're for.
///
/// Paths use `~` for the home folder and `*` to match any single name. When several entries
/// match a path, the deepest one wins, and among equally deep entries the one with more literal
/// (non-wildcard) names wins. Entries with `suggest: true` appear under Suggestions.
enum Catalog {
    static let cachesDeleted = "Apps rebuild caches as you use them. Some may feel slower for a little while, and a few may ask you to sign in again."
    static let logsDeleted = "Nothing you need. Logs only help diagnose past problems."

    static let unknown = KnownLocation(
        id: "unknown",
        title: "Unrecognised item",
        paths: [],
        category: .other,
        safety: .caution,
        cleanup: .individually,
        systemData: true,
        whatItIs: "Something Data Explorer doesn't have a specific explanation for.",
        ifDeleted: "Whatever relies on it may stop working. Only delete it if you know what it is."
    )

    static let projectArtifacts = KnownLocation(
        id: "project-artifacts",
        title: "Project dependencies & build folders",
        paths: [],
        category: .developer,
        safety: .safe,
        cleanup: .trashItem,
        systemData: false,
        suggest: true,
        whatItIs: "Folders that coding tools generate inside your projects: node_modules, Python virtual environments, Rust and Swift build folders, CocoaPods and Gradle output. They can be recreated from the project's own files.",
        ifDeleted: "Run the project's install or build command (npm install, cargo build, pod install…) to recreate them."
    )

    static let downloadedInstallers = KnownLocation(
        id: "downloaded-installers",
        title: "Installers & archives in Downloads",
        paths: [],
        category: .personalFiles,
        safety: .review,
        cleanup: .trashItem,
        systemData: false,
        suggest: true,
        whatItIs: "Disk images, installer packages and archives in your Downloads folder. Once an app is installed, its installer is rarely needed.",
        ifDeleted: "Installed apps keep working. You'd need to download the installer again to reinstall."
    )

    static let leftoverAppData = KnownLocation(
        id: "leftover-app-data",
        title: "Leftovers from apps you've removed",
        paths: [],
        category: .appData,
        safety: .review,
        cleanup: .trashItem,
        systemData: true,
        suggest: true,
        whatItIs: "Data folders named after apps that no longer seem to be installed. Deleting an app doesn't remove the data it stored in your Library.",
        ifDeleted: "If you reinstall the app later it starts fresh, without its old settings or data."
    )

    static var locations: [KnownLocation] { system + shared + home + library + developer + virtualMachines + media }

    // MARK: - System

    static let system: [KnownLocation] = [
        KnownLocation(
            id: "disk-root",
            title: "Top level of your disk",
            paths: ["/"],
            category: .other,
            safety: .caution,
            cleanup: .individually,
            systemData: true,
            whatItIs: "The top level of your startup disk.",
            ifDeleted: "Whatever relies on it may stop working.",
            insideNote: "Something at the top level of your disk that Data Explorer doesn't recognise. Developer tools and some installers put folders here."
        ),
        KnownLocation(
            id: "data-volume-hidden",
            title: "Hidden system folders",
            paths: ["/System/Volumes/Data"],
            category: .systemManaged,
            safety: .protected,
            cleanup: .individually,
            systemData: true,
            whatItIs: "Hidden folders macOS keeps at the top of your data volume, such as search indexes and file-change records.",
            ifDeleted: "macOS features that rely on them can break."
        ),
        KnownLocation(
            id: "spotlight-index",
            title: "Spotlight search index",
            paths: ["/System/Volumes/Data/.Spotlight-V100"],
            category: .systemManaged,
            safety: .protected,
            cleanup: .manual("If it's unusually large (over 10–15 GB), rebuild it: in System Settings › Spotlight, add your disk to the privacy list (\"Search Privacy\"), wait a minute, then remove it again. macOS rebuilds a fresh index."),
            systemData: true,
            suggest: true,
            whatItIs: "The index that makes Spotlight search fast. It grows with the number of files on your Mac and how much text they contain.",
            ifDeleted: "Search stops working until macOS rebuilds the index, which can take hours."
        ),
        KnownLocation(
            id: "fseventsd",
            title: "File change log",
            paths: ["/System/Volumes/Data/.fseventsd"],
            category: .systemManaged,
            safety: .protected,
            cleanup: .individually,
            systemData: true,
            whatItIs: "A running record of file changes, used by Time Machine, Spotlight and sync apps.",
            ifDeleted: "Backups and sync apps may need to rescan everything."
        ),
        KnownLocation(
            id: "document-revisions",
            title: "Saved document versions",
            paths: ["/System/Volumes/Data/.DocumentRevisions-V100"],
            category: .systemManaged,
            safety: .protected,
            cleanup: .manual("macOS trims old versions automatically. To remove versions of one document, open it and choose File › Revert To › Browse All Versions."),
            systemData: true,
            suggest: true,
            whatItIs: "Earlier versions of documents, kept by apps that support File › Revert To (Pages, Keynote, Numbers, TextEdit, Preview and others).",
            ifDeleted: "You'd lose the ability to go back to earlier versions."
        ),
        KnownLocation(
            id: "system-folder",
            title: "macOS system files",
            paths: ["/System"],
            category: .systemManaged,
            safety: .protected,
            cleanup: .individually,
            systemData: true,
            whatItIs: "Parts of macOS stored on your data volume, such as downloaded system assets and caches.",
            ifDeleted: "macOS may stop working properly."
        ),
        KnownLocation(
            id: "system-caches",
            title: "macOS system caches",
            paths: ["/System/Library/Caches"],
            category: .systemManaged,
            safety: .protected,
            cleanup: .manual("macOS manages these itself. Restarting your Mac clears some of them."),
            systemData: true,
            whatItIs: "Caches used by macOS itself.",
            ifDeleted: "macOS may stop working properly until they're rebuilt."
        ),
        KnownLocation(
            id: "system-assets",
            title: "Downloaded system assets",
            paths: [
                "/System/Library/AssetsV2", "/System/Library/Assets", "/System/Library/PreinstalledAssets",
                "/System/Library/PreinstalledAssetsV2", "/private/var/MobileAsset",
            ],
            category: .systemManaged,
            safety: .protected,
            cleanup: .manual("macOS downloads and removes these as needed. Turning off features you don't use (such as Apple Intelligence, extra dictation languages, or downloaded voices) lets macOS remove their assets."),
            systemData: true,
            suggest: true,
            whatItIs: "Content macOS downloads on demand: Apple Intelligence and Siri models, fonts, dictionaries, voices, wallpapers and more.",
            ifDeleted: "Features that rely on these assets stop working until they're downloaded again."
        ),
        KnownLocation(
            id: "private",
            title: "Private system area",
            paths: ["/private"],
            category: .systemManaged,
            safety: .protected,
            cleanup: .individually,
            systemData: true,
            whatItIs: "Low-level system folders (the familiar /var, /etc and /tmp). Managed by macOS.",
            ifDeleted: "macOS may stop working properly."
        ),
        KnownLocation(
            id: "var-folders",
            title: "Per-user temporary files & caches",
            paths: ["/private/var/folders"],
            category: .systemManaged,
            safety: .protected,
            cleanup: .manual("Restart your Mac: macOS clears the temporary part of this folder at startup. Don't delete it by hand while apps are running."),
            systemData: true,
            suggest: true,
            whatItIs: "Each user's private temporary and cache folders: what apps get when they ask macOS for a temporary or cache location. It can grow when apps don't clean up after themselves.",
            ifDeleted: "Running apps can crash or lose unsaved work."
        ),
        KnownLocation(
            id: "virtual-memory",
            title: "Virtual memory & sleep image",
            paths: ["/private/var/vm"],
            category: .systemManaged,
            safety: .protected,
            cleanup: .manual("Restart your Mac to shrink swap. Quitting memory-hungry apps keeps it small."),
            systemData: true,
            suggest: true,
            whatItIs: "Swap files that hold memory contents when RAM is full, and the sleep image used to restore your session after sleep.",
            ifDeleted: "Apps can crash and your Mac may become unstable."
        ),
        KnownLocation(
            id: "var-db",
            title: "System databases",
            paths: ["/private/var/db"],
            category: .systemManaged,
            safety: .protected,
            cleanup: .individually,
            systemData: true,
            whatItIs: "macOS's own databases: logs, software update records, Rosetta translations and more.",
            ifDeleted: "macOS may stop working properly."
        ),
        KnownLocation(
            id: "unified-log",
            title: "Unified system log",
            paths: ["/private/var/db/diagnostics", "/private/var/db/uuidtext"],
            category: .logs,
            safety: .protected,
            cleanup: .manual("macOS deletes old log entries automatically, usually within a few days. Nothing to do."),
            systemData: true,
            suggest: true,
            whatItIs: "The system log that macOS and apps write to, viewable in the Console app.",
            ifDeleted: "Recent diagnostic history is lost, and the log keeps growing back anyway."
        ),
        KnownLocation(
            id: "rosetta-cache",
            title: "Rosetta translation cache",
            paths: ["/private/var/db/oah"],
            category: .systemManaged,
            safety: .protected,
            cleanup: .individually,
            systemData: true,
            whatItIs: "Translated copies of Intel apps, created by Rosetta on Apple silicon Macs.",
            ifDeleted: "Intel apps launch slowly while Rosetta translates them again."
        ),
        KnownLocation(
            id: "var-log",
            title: "System logs",
            paths: ["/private/var/log"],
            category: .logs,
            safety: .protected,
            cleanup: .manual("macOS rotates and removes these automatically."),
            systemData: true,
            whatItIs: "Traditional system log files.",
            ifDeleted: "Recent diagnostic history is lost."
        ),
        KnownLocation(
            id: "tmp",
            title: "Temporary files",
            paths: ["/private/tmp", "/private/var/tmp"],
            category: .systemManaged,
            safety: .protected,
            cleanup: .manual("Restart your Mac to clear temporary files."),
            systemData: true,
            whatItIs: "Temporary files for apps and system services.",
            ifDeleted: "Running apps can crash or lose work."
        ),
        KnownLocation(
            id: "software-updates",
            title: "Downloaded macOS updates",
            paths: ["/private/var/MobileSoftwareUpdate", "/Library/Updates", "/System/Volumes/Data/.MobileSoftwareUpdate"],
            category: .systemManaged,
            safety: .protected,
            cleanup: .manual("Install the pending update from System Settings › General › Software Update. The files are removed once it's installed."),
            systemData: true,
            suggest: true,
            whatItIs: "macOS updates that have been downloaded and are waiting to be installed.",
            ifDeleted: "macOS downloads the update again."
        ),
        KnownLocation(
            id: "core-dumps",
            title: "Crash memory dumps",
            paths: ["/cores"],
            category: .logs,
            safety: .safe,
            cleanup: .trashContents,
            systemData: true,
            suggest: true,
            whatItIs: "Core dumps: full memory snapshots written when a program crashes (only if core dumps are turned on). Each one can be several gigabytes.",
            ifDeleted: "Nothing you need unless you're debugging that crash. Deleting them needs an administrator password."
        ),
        KnownLocation(
            id: "volumes",
            title: "Other disks",
            paths: ["/Volumes"],
            category: .other,
            safety: .protected,
            cleanup: .individually,
            whatItIs: "Where other disks and network shares appear. Data Explorer doesn't scan inside them.",
            ifDeleted: "Not applicable."
        ),
        KnownLocation(
            id: "usr",
            title: "Unix system files",
            paths: ["/usr"],
            category: .systemManaged,
            safety: .protected,
            cleanup: .individually,
            systemData: true,
            whatItIs: "Low-level programs and libraries.",
            ifDeleted: "macOS or installed tools may stop working."
        ),
        KnownLocation(
            id: "usr-local",
            title: "Command-line tools (/usr/local)",
            paths: ["/usr/local"],
            category: .developer,
            safety: .review,
            cleanup: .individually,
            whatItIs: "Command-line tools and libraries installed outside the App Store, including Homebrew on Intel Macs.",
            ifDeleted: "Tools installed here stop working. It's better to uninstall them with whatever installed them (for example, brew uninstall)."
        ),
        KnownLocation(
            id: "opt",
            title: "Optional software (/opt)",
            paths: ["/opt"],
            category: .developer,
            safety: .review,
            cleanup: .individually,
            whatItIs: "Software installed by tools like Homebrew (on Apple silicon) and MacPorts.",
            ifDeleted: "Tools installed here stop working."
        ),
        KnownLocation(
            id: "homebrew",
            title: "Homebrew packages",
            paths: ["/opt/homebrew", "/usr/local/Cellar", "/usr/local/Caskroom"],
            category: .developer,
            safety: .review,
            cleanup: .manual("In Terminal, run `brew autoremove` and `brew cleanup`, then `brew uninstall` anything you no longer use. Deleting files here directly breaks Homebrew."),
            suggest: true,
            whatItIs: "Command-line tools and apps installed with Homebrew.",
            ifDeleted: "Tools installed with Homebrew stop working."
        ),
    ]

    // MARK: - Shared (all users)

    static let shared: [KnownLocation] = [
        KnownLocation(
            id: "applications",
            title: "Applications",
            paths: ["/Applications"],
            category: .apps,
            safety: .review,
            cleanup: .individually,
            whatItIs: "Apps installed for everyone on this Mac. Apple's built-in apps live on the sealed system volume and aren't counted here.",
            ifDeleted: "The app is uninstalled. You can reinstall it from the App Store or the developer's website. Its settings stay in your Library unless you remove those too.",
            insideNote: "An app installed on this Mac."
        ),
        KnownLocation(
            id: "macos-installer",
            title: "Leftover macOS installer",
            paths: ["/Applications/Install macOS*.app", "/Applications/Install OS X*.app"],
            category: .apps,
            safety: .safe,
            cleanup: .trashItem,
            suggest: true,
            whatItIs: "A full macOS installer left behind after an upgrade. Each is usually 12–15 GB.",
            ifDeleted: "Nothing, unless you planned to make a bootable USB installer. You can download it again from the App Store."
        ),
        KnownLocation(
            id: "xcode-app",
            title: "Xcode",
            paths: ["/Applications/Xcode*.app"],
            category: .developer,
            safety: .review,
            cleanup: .trashItem,
            whatItIs: "Apple's app for building software. Each copy (including betas) takes 10–20 GB, not counting simulators.",
            ifDeleted: "You can't build apps until you reinstall it from the App Store or developer.apple.com."
        ),
        KnownLocation(
            id: "shared-library",
            title: "Shared Library",
            paths: ["/Library"],
            category: .appData,
            safety: .caution,
            cleanup: .individually,
            systemData: true,
            whatItIs: "Settings, plug-ins and support files shared by all users, installed by apps and macOS.",
            ifDeleted: "Apps or system features that use these files may stop working.",
            insideNote: "Support files installed for all users by an app or by macOS."
        ),
        KnownLocation(
            id: "shared-caches",
            title: "Shared caches",
            paths: ["/Library/Caches"],
            category: .caches,
            safety: .safe,
            cleanup: .trashContents,
            systemData: true,
            suggest: true,
            whatItIs: "Caches kept for all users by apps and system services.",
            ifDeleted: "Apps rebuild what they need. Some of these files belong to the system and need an administrator password to delete.",
            insideNote: "Cache files for one app or service."
        ),
        KnownLocation(
            id: "shared-logs",
            title: "Shared logs & crash reports",
            paths: ["/Library/Logs"],
            category: .logs,
            safety: .safe,
            cleanup: .trashContents,
            systemData: true,
            suggest: true,
            whatItIs: "Logs and crash reports written by apps and system services for all users.",
            ifDeleted: logsDeleted
        ),
        KnownLocation(
            id: "shared-app-support",
            title: "Shared app support files",
            paths: ["/Library/Application Support"],
            category: .appData,
            safety: .caution,
            cleanup: .individually,
            systemData: true,
            whatItIs: "Support files that apps install for every user: plug-ins, templates, licences and content libraries.",
            ifDeleted: "The app that installed it may stop working properly.",
            insideNote: "Support files for one app, shared by all users."
        ),
        KnownLocation(
            id: "aerial-videos",
            title: "Aerial wallpapers & screen savers",
            paths: ["/Library/Application Support/com.apple.idleassetsd/Customer"],
            category: .systemManaged,
            safety: .review,
            cleanup: .trashContents,
            systemData: true,
            suggest: true,
            whatItIs: "Videos for the Aerial screen savers and wallpapers. Each one is a few hundred megabytes, and they add up.",
            ifDeleted: "macOS downloads a video again if you pick that aerial. Deleting these needs an administrator password."
        ),
        KnownLocation(
            id: "garageband-library",
            title: "GarageBand & Logic sound library",
            paths: [
                "/Library/Application Support/GarageBand", "/Library/Application Support/Logic",
                "/Library/Audio/Apple Loops", "/Library/Audio/Impulse Responses",
            ],
            category: .apps,
            safety: .review,
            cleanup: .trashItem,
            suggest: true,
            whatItIs: "Instruments, loops and sounds for GarageBand and Logic Pro. The full library runs to several gigabytes.",
            ifDeleted: "If you use GarageBand or Logic again, they offer to download the sounds again. Deleting these needs an administrator password."
        ),
        KnownLocation(
            id: "shared-developer",
            title: "Shared developer files",
            paths: ["/Library/Developer"],
            category: .developer,
            safety: .review,
            cleanup: .individually,
            whatItIs: "Developer tools installed for all users.",
            ifDeleted: "Developer tools may stop working."
        ),
        KnownLocation(
            id: "simulator-runtime-assets",
            title: "Simulator runtimes (in system assets)",
            paths: ["/System/Library/AssetsV2/com_apple_MobileAsset_*SimulatorRuntime"],
            category: .developer,
            safety: .review,
            cleanup: .manual("In Xcode › Settings › Components (called Platforms in older versions), delete simulator runtimes you don't need. Or in Terminal run `xcrun simctl runtime list`, then `xcrun simctl runtime delete <id>`."),
            systemData: true,
            suggest: true,
            whatItIs: "iOS, watchOS, tvOS and visionOS runtimes that Xcode downloaded for the simulator. macOS 14 and later store them alongside its own system assets, which is why they're counted as System Data. Each is 5–10 GB.",
            ifDeleted: "You can't run simulators for those OS versions until you download them again."
        ),
        KnownLocation(
            id: "simulator-runtimes",
            title: "Simulator runtimes",
            paths: ["/Library/Developer/CoreSimulator"],
            category: .developer,
            safety: .review,
            cleanup: .manual("In Xcode › Settings › Components (called Platforms in older versions), delete runtimes you don't need. Or run `xcrun simctl runtime list` and `xcrun simctl runtime delete <id>` in Terminal."),
            suggest: true,
            whatItIs: "Downloaded iOS, watchOS, tvOS and visionOS runtimes for the simulator. Each one is several gigabytes.",
            ifDeleted: "You can't run simulators for those OS versions until you download them again."
        ),
        KnownLocation(
            id: "command-line-tools",
            title: "Command Line Tools",
            paths: ["/Library/Developer/CommandLineTools"],
            category: .developer,
            safety: .review,
            cleanup: .manual("If you have the full Xcode app you may not need these. Remove them with `sudo rm -rf /Library/Developer/CommandLineTools` and reinstall any time with `xcode-select --install`."),
            whatItIs: "Apple's command-line developer tools: git, clang, make and friends.",
            ifDeleted: "Command-line tools like git stop working until reinstalled."
        ),
        KnownLocation(
            id: "toolchains",
            title: "Swift toolchains",
            paths: ["/Library/Developer/Toolchains", "~/Library/Developer/Toolchains"],
            category: .developer,
            safety: .review,
            cleanup: .trashContents,
            suggest: true,
            whatItIs: "Extra Swift toolchains you've installed, for example from swift.org.",
            ifDeleted: "Builds that select those toolchains stop working."
        ),
        KnownLocation(
            id: "users",
            title: "Users",
            paths: ["/Users"],
            category: .personalFiles,
            safety: .review,
            cleanup: .individually,
            whatItIs: "Home folders for each user on this Mac.",
            ifDeleted: "Not applicable."
        ),
        KnownLocation(
            id: "other-user",
            title: "Another user's home folder",
            paths: ["/Users/*"],
            category: .personalFiles,
            safety: .protected,
            cleanup: .individually,
            whatItIs: "Another account's home folder. macOS keeps most of it private, so it can't be measured fully. Sign in as that user to manage their files.",
            ifDeleted: "That user would lose their files."
        ),
        KnownLocation(
            id: "users-shared",
            title: "Shared folder",
            paths: ["/Users/Shared"],
            category: .personalFiles,
            safety: .review,
            cleanup: .individually,
            whatItIs: "Files shared between all users of this Mac. Some apps also store content here.",
            ifDeleted: "The files are gone for every user."
        ),
    ]

    // MARK: - Home folder

    static let home: [KnownLocation] = [
        KnownLocation(
            id: "home",
            title: "Your home folder",
            paths: ["~"],
            category: .personalFiles,
            safety: .review,
            cleanup: .individually,
            whatItIs: "Your home folder.",
            ifDeleted: "It's gone unless you have a backup.",
            insideNote: "A file or folder in your home folder."
        ),
        personalFolder("desktop", "Desktop", "Files on your desktop."),
        personalFolder("documents", "Documents", "Your documents."),
        personalFolder("downloads", "Downloads", "Files you've downloaded. It tends to collect installers and archives you no longer need."),
        personalFolder("movies", "Movies", "Videos and video projects."),
        personalFolder("music", "Music", "Music files and audio projects."),
        personalFolder("pictures", "Pictures", "Pictures, and usually your Photos library."),
        personalFolder("public", "Public", "Files you share with other users on your network."),
        personalFolder("home-applications", "Applications (just for you)", "Apps installed only for your account.", path: "~/Applications", category: .apps),
        KnownLocation(
            id: "trash",
            title: "Trash",
            paths: ["~/.Trash"],
            category: .trash,
            safety: .safe,
            cleanup: .trashContents,
            suggest: true,
            whatItIs: "Things you've moved to the Trash. They keep taking up space until the Trash is emptied.",
            ifDeleted: "These items are deleted permanently.",
            insideNote: "Something you've already moved to the Trash."
        ),
        KnownLocation(
            id: "zoom-recordings",
            title: "Zoom recordings",
            paths: ["~/Documents/Zoom"],
            category: .personalFiles,
            safety: .review,
            cleanup: .trashContents,
            suggest: true,
            whatItIs: "Meeting recordings saved by Zoom.",
            ifDeleted: "The recordings are gone unless you have another copy."
        ),
        KnownLocation(
            id: "dot-cache",
            title: "Command-line tool caches",
            paths: ["~/.cache"],
            category: .caches,
            safety: .safe,
            cleanup: .trashContents,
            systemData: true,
            suggest: true,
            whatItIs: "A shared cache folder used by many command-line and Python tools (pip, uv, Hugging Face, pre-commit and others).",
            ifDeleted: "Tools download or rebuild what they need. Downloaded AI models have to be fetched again.",
            insideNote: "Cache files for one command-line tool."
        ),
        KnownLocation(
            id: "huggingface",
            title: "Hugging Face models & datasets",
            paths: ["~/.cache/huggingface"],
            category: .developer,
            safety: .review,
            cleanup: .trashItem,
            whatItIs: "AI models and datasets downloaded by Hugging Face libraries. Individual models can be many gigabytes.",
            ifDeleted: "Code that uses those models downloads them again."
        ),
    ]

    static func personalFolder(_ id: String, _ title: String, _ what: String, path: String? = nil, category: StorageCategory = .personalFiles) -> KnownLocation {
        KnownLocation(
            id: id,
            title: title,
            paths: [path ?? "~/\(title)"],
            category: category,
            safety: .review,
            cleanup: .individually,
            whatItIs: what,
            ifDeleted: "It's gone unless you have a backup.",
            insideNote: "One of your files in \(title)."
        )
    }

    // MARK: - ~/Library

    static let library: [KnownLocation] = [
        KnownLocation(
            id: "library",
            title: "Your Library folder",
            paths: ["~/Library"],
            category: .appData,
            safety: .caution,
            cleanup: .individually,
            systemData: true,
            whatItIs: "Settings, caches and data for the apps you use. Finder hides this folder by default.",
            ifDeleted: "The app that uses it may lose data or settings.",
            insideNote: "Data an app keeps in your Library folder."
        ),
        KnownLocation(
            id: "caches",
            title: "App caches",
            paths: ["~/Library/Caches"],
            category: .caches,
            safety: .safe,
            cleanup: .trashContents,
            systemData: true,
            suggest: true,
            whatItIs: "Temporary files apps keep so they load faster: downloaded images, web data, thumbnails, update downloads and so on. This is one of the biggest parts of System Data.",
            ifDeleted: cachesDeleted,
            insideNote: "Cache files for one app or service. Apps rebuild them automatically."
        ),
        KnownLocation(
            id: "logs",
            title: "App logs & crash reports",
            paths: ["~/Library/Logs"],
            category: .logs,
            safety: .safe,
            cleanup: .trashContents,
            systemData: true,
            suggest: true,
            whatItIs: "Log files and crash reports written by apps.",
            ifDeleted: logsDeleted,
            insideNote: "Logs written by one app."
        ),
        KnownLocation(
            id: "app-support",
            title: "Application Support",
            paths: ["~/Library/Application Support"],
            category: .appData,
            safety: .caution,
            cleanup: .individually,
            systemData: true,
            whatItIs: "Where apps keep their working data: databases, downloaded content, plug-ins and settings.",
            ifDeleted: "The app may lose data, settings or offline content.",
            insideNote: "Working data for one app. Deleting it resets that app and may lose anything not synced elsewhere."
        ),
        KnownLocation(
            id: "containers",
            title: "App containers",
            paths: ["~/Library/Containers"],
            category: .appData,
            safety: .caution,
            cleanup: .individually,
            systemData: true,
            whatItIs: "Private storage for sandboxed apps (most App Store apps and many of Apple's). Each folder is one app's own little Library, named after the app's ID.",
            ifDeleted: "The app loses its data and settings.",
            insideNote: "One app's private storage, named after its ID."
        ),
        KnownLocation(
            id: "container-caches",
            title: "Caches inside app containers",
            paths: ["~/Library/Containers/*/Data/Library/Caches"],
            category: .caches,
            safety: .safe,
            cleanup: .trashContents,
            systemData: true,
            suggest: true,
            whatItIs: "Cache folders inside sandboxed apps' private storage.",
            ifDeleted: cachesDeleted
        ),
        KnownLocation(
            id: "group-containers",
            title: "Shared app containers",
            paths: ["~/Library/Group Containers"],
            category: .appData,
            safety: .caution,
            cleanup: .individually,
            systemData: true,
            whatItIs: "Storage shared between an app and its extensions or sibling apps (for example, all the Microsoft Office apps).",
            ifDeleted: "The apps using it lose data and settings.",
            insideNote: "Data shared by a family of apps."
        ),
        KnownLocation(
            id: "group-container-caches",
            title: "Caches inside shared containers",
            paths: ["~/Library/Group Containers/*/Library/Caches"],
            category: .caches,
            safety: .safe,
            cleanup: .trashContents,
            systemData: true,
            suggest: true,
            whatItIs: "Cache folders inside storage shared by a family of apps.",
            ifDeleted: cachesDeleted
        ),
        KnownLocation(
            id: "web-app-caches",
            title: "Browser & desktop app caches",
            paths: [
                "~/Library/Application Support/*/Cache",
                "~/Library/Application Support/*/Code Cache",
                "~/Library/Application Support/*/GPUCache",
                "~/Library/Application Support/*/CachedData",
                "~/Library/Application Support/*/CachedExtensionVSIXs",
                "~/Library/Application Support/*/DawnCache",
                "~/Library/Application Support/*/DawnGraphiteCache",
                "~/Library/Application Support/*/DawnWebGPUCache",
                "~/Library/Application Support/*/Service Worker/CacheStorage",
                "~/Library/Application Support/*/Service Worker/ScriptCache",
                "~/Library/Application Support/Google/Chrome/*/Service Worker/CacheStorage",
                "~/Library/Application Support/Google/Chrome/*/GPUCache",
                "~/Library/Application Support/Microsoft Edge/*/Service Worker/CacheStorage",
                "~/Library/Application Support/BraveSoftware/Brave-Browser/*/Service Worker/CacheStorage",
                "~/Library/Application Support/Arc/User Data/*/Service Worker/CacheStorage",
                "~/Library/Containers/*/Data/Library/Application Support/*/Cache",
                "~/Library/Containers/*/Data/Library/Application Support/*/Service Worker/CacheStorage",
            ],
            category: .caches,
            safety: .safe,
            cleanup: .trashContents,
            systemData: true,
            suggest: true,
            whatItIs: "Caches kept by web browsers and by desktop apps built on web technology (Slack, Discord, VS Code, Teams, Notion and similar): web pages, compiled code and graphics.",
            ifDeleted: "Apps download what they need again. Quit the app first for best results; nothing you made is lost."
        ),
        KnownLocation(
            id: "spotify-cache",
            title: "Spotify cache & downloads",
            paths: ["~/Library/Application Support/Spotify/PersistentCache"],
            category: .caches,
            safety: .safe,
            cleanup: .trashContents,
            systemData: true,
            suggest: true,
            whatItIs: "Music Spotify cached while streaming, plus anything downloaded for offline listening.",
            ifDeleted: "Spotify streams again as needed. Downloaded playlists have to be downloaded again."
        ),
        KnownLocation(
            id: "adobe-media-cache",
            title: "Adobe media cache",
            paths: [
                "~/Library/Application Support/Adobe/Common/Media Cache Files",
                "~/Library/Application Support/Adobe/Common/Media Cache",
                "~/Library/Application Support/Adobe/Common/Peak Files",
            ],
            category: .caches,
            safety: .safe,
            cleanup: .trashContents,
            systemData: true,
            suggest: true,
            whatItIs: "Conformed audio and preview files created by Premiere Pro, After Effects and other Adobe video apps.",
            ifDeleted: "Adobe apps regenerate these when you open a project. That first open can be slow."
        ),
        KnownLocation(
            id: "saved-state",
            title: "Saved app windows",
            paths: ["~/Library/Saved Application State"],
            category: .appData,
            safety: .safe,
            cleanup: .trashContents,
            systemData: true,
            whatItIs: "What lets apps reopen their windows where you left them.",
            ifDeleted: "Apps open with fresh windows next time."
        ),
        KnownLocation(
            id: "preferences",
            title: "App settings",
            paths: ["~/Library/Preferences"],
            category: .appData,
            safety: .caution,
            cleanup: .individually,
            systemData: true,
            whatItIs: "Settings files for your apps. They're tiny.",
            ifDeleted: "The app forgets its settings."
        ),
        KnownLocation(
            id: "keychains",
            title: "Keychains",
            paths: ["~/Library/Keychains"],
            category: .appData,
            safety: .protected,
            cleanup: .individually,
            systemData: true,
            whatItIs: "Your saved passwords, certificates and encryption keys.",
            ifDeleted: "You'd lose saved passwords and could be locked out of accounts."
        ),
        KnownLocation(
            id: "personal-system-data",
            title: "macOS personal data stores",
            paths: [
                "~/Library/Biome", "~/Library/Suggestions", "~/Library/Metadata", "~/Library/IntelligencePlatform",
                "~/Library/Application Support/Knowledge", "~/Library/Application Support/FileProvider",
                "~/Library/Application Support/CloudDocs", "~/Library/Application Support/CallHistoryDB",
                "~/Library/Application Support/AddressBook", "~/Library/Calendars", "~/Library/Reminders",
                "~/Library/Safari", "~/Library/Accounts", "~/Library/HomeKit", "~/Library/Photos",
            ],
            category: .systemManaged,
            safety: .protected,
            cleanup: .individually,
            systemData: true,
            whatItIs: "Databases macOS keeps for you: contacts, calendars, Safari, Spotlight, Siri suggestions, Screen Time and iCloud sync.",
            ifDeleted: "You could lose personal data or break syncing."
        ),
        KnownLocation(
            id: "ios-backups",
            title: "iPhone & iPad backups",
            paths: ["~/Library/Application Support/MobileSync/Backup"],
            category: .deviceBackups,
            safety: .review,
            cleanup: .trashContents,
            suggest: true,
            whatItIs: "Backups of iPhones and iPads made by Finder (or iTunes). Each can be many gigabytes. Backups of devices you no longer own, or old duplicates, are good candidates.",
            ifDeleted: "You can't restore a device from that backup. If you still use the device, make sure it's backed up to iCloud or make a fresh backup first.",
            insideNote: "One device backup."
        ),
        KnownLocation(
            id: "device-firmware",
            title: "Downloaded iPhone & iPad software",
            paths: ["~/Library/iTunes/iPhone Software Updates", "~/Library/iTunes/iPad Software Updates", "~/Library/iTunes/iPod Software Updates"],
            category: .deviceBackups,
            safety: .safe,
            cleanup: .trashContents,
            suggest: true,
            whatItIs: "Firmware Finder downloaded to update or restore an iPhone or iPad.",
            ifDeleted: "Nothing. It's downloaded again if you ever restore a device."
        ),
        KnownLocation(
            id: "mail",
            title: "Mail",
            paths: ["~/Library/Mail"],
            category: .mailAndMessages,
            safety: .protected,
            cleanup: .manual("In Mail, delete messages with large attachments and choose Mailbox › Erase Deleted Items. Removing an account you no longer use (System Settings › Internet Accounts) also removes its downloaded mail."),
            suggest: true,
            whatItIs: "Email downloaded by the Mail app, including attachments.",
            ifDeleted: "Mail would have to download everything again, and messages kept only on this Mac would be lost."
        ),
        KnownLocation(
            id: "mail-downloads",
            title: "Opened Mail attachments",
            paths: ["~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"],
            category: .mailAndMessages,
            safety: .safe,
            cleanup: .trashContents,
            suggest: true,
            whatItIs: "Copies of attachments you opened from Mail. The originals stay in the emails.",
            ifDeleted: "Nothing. The attachments are still in your messages."
        ),
        KnownLocation(
            id: "messages",
            title: "Messages",
            paths: ["~/Library/Messages"],
            category: .mailAndMessages,
            safety: .protected,
            cleanup: .manual("In Messages › Settings › General, set Keep Messages to 1 Year or 30 Days, or delete large conversations. System Settings › General › Storage › Messages lets you review big attachments one by one."),
            suggest: true,
            whatItIs: "Your message history and every photo, video and file sent or received in Messages.",
            ifDeleted: "Deleting files here directly breaks your conversations."
        ),
        KnownLocation(
            id: "whatsapp",
            title: "WhatsApp media",
            paths: ["~/Library/Group Containers/group.net.whatsapp.WhatsApp.shared"],
            category: .mailAndMessages,
            safety: .caution,
            cleanup: .manual("In WhatsApp › Settings › Storage and Data › Manage Storage, review and delete large media."),
            suggest: true,
            whatItIs: "WhatsApp's chat history and the photos, videos and files in your chats.",
            ifDeleted: "Deleting files here directly can corrupt your chats."
        ),
        KnownLocation(
            id: "outlook",
            title: "Outlook data",
            paths: ["~/Library/Group Containers/UBF8T346G9.Office/Outlook"],
            category: .mailAndMessages,
            safety: .protected,
            cleanup: .manual("Manage mailboxes from inside Outlook."),
            whatItIs: "Email, calendars and contacts downloaded by Outlook.",
            ifDeleted: "Outlook would have to download everything again, and local-only items would be lost."
        ),
        KnownLocation(
            id: "icloud-drive",
            title: "iCloud Drive",
            paths: ["~/Library/Mobile Documents"],
            category: .cloudFiles,
            safety: .protected,
            cleanup: .manual("To free space without deleting anything from iCloud, turn on Optimize Mac Storage in System Settings › [your name] › iCloud › iCloud Drive, or right-click files in Finder and choose Remove Download."),
            suggest: true,
            whatItIs: "Files from iCloud Drive (and apps that store documents in iCloud) that are downloaded to this Mac.",
            ifDeleted: "Deleting here deletes the files from iCloud and from all your devices."
        ),
        KnownLocation(
            id: "cloud-storage",
            title: "Cloud drives",
            paths: ["~/Library/CloudStorage"],
            category: .cloudFiles,
            safety: .protected,
            cleanup: .manual("Right-click a folder in Finder and choose Remove Download (or Free Up Space), or use the provider's app. That frees space without deleting from the cloud."),
            suggest: true,
            whatItIs: "Files from Dropbox, Google Drive, OneDrive, Box and other cloud drives that are downloaded to this Mac.",
            ifDeleted: "Deleting here deletes the files from the cloud and from your other devices."
        ),
        KnownLocation(
            id: "podcasts",
            title: "Podcast downloads",
            paths: ["~/Library/Group Containers/243LU875E5.groups.com.apple.podcasts"],
            category: .mediaLibraries,
            safety: .review,
            cleanup: .manual("In Podcasts › Settings, turn on Remove Played Downloads, or remove downloads from individual shows."),
            suggest: true,
            whatItIs: "Episodes downloaded by the Podcasts app.",
            ifDeleted: "Deleting files here directly confuses the Podcasts app."
        ),
        KnownLocation(
            id: "steam",
            title: "Steam games",
            paths: ["~/Library/Application Support/Steam/steamapps"],
            category: .apps,
            safety: .review,
            cleanup: .manual("Uninstall games you don't play from your Steam library (right-click › Manage › Uninstall)."),
            suggest: true,
            whatItIs: "Games installed through Steam.",
            ifDeleted: "Steam would think the games are broken."
        ),
    ]

    // MARK: - Developer

    static let developer: [KnownLocation] = [
        KnownLocation(
            id: "developer",
            title: "Developer data",
            paths: ["~/Library/Developer"],
            category: .developer,
            safety: .review,
            cleanup: .individually,
            whatItIs: "Data created by Xcode and Apple's developer tools.",
            ifDeleted: "Depends on the item. See the specific suggestions."
        ),
        KnownLocation(
            id: "derived-data",
            title: "Xcode build cache (DerivedData)",
            paths: ["~/Library/Developer/Xcode/DerivedData"],
            category: .developer,
            safety: .safe,
            cleanup: .trashContents,
            suggest: true,
            whatItIs: "Intermediate build files and indexes Xcode creates for every project you open. It easily grows to tens of gigabytes.",
            ifDeleted: "Xcode rebuilds it the next time you build. That first build is slower.",
            insideNote: "Build cache for one project."
        ),
        KnownLocation(
            id: "xcode-archives",
            title: "Xcode archives",
            paths: ["~/Library/Developer/Xcode/Archives"],
            category: .developer,
            safety: .review,
            cleanup: .trashContents,
            suggest: true,
            whatItIs: "Archived builds of apps you've distributed. They contain the symbols needed to read crash reports from those versions.",
            ifDeleted: "You can't symbolicate crash reports for deleted builds. Keep archives for versions people still use."
        ),
        KnownLocation(
            id: "device-support",
            title: "Device debugging symbols",
            paths: [
                "~/Library/Developer/Xcode/iOS DeviceSupport", "~/Library/Developer/Xcode/watchOS DeviceSupport",
                "~/Library/Developer/Xcode/tvOS DeviceSupport", "~/Library/Developer/Xcode/visionOS DeviceSupport",
                "~/Library/Developer/Xcode/xrOS DeviceSupport", "~/Library/Developer/Xcode/macOS DeviceSupport",
            ],
            category: .developer,
            safety: .safe,
            cleanup: .trashContents,
            suggest: true,
            whatItIs: "Symbols Xcode copies from every iOS, watchOS or tvOS version you've debugged on. Old versions pile up at a few gigabytes each.",
            ifDeleted: "Xcode copies them again the next time you connect a device running that version."
        ),
        KnownLocation(
            id: "simulator-devices",
            title: "Simulator devices",
            paths: ["~/Library/Developer/CoreSimulator/Devices"],
            category: .developer,
            safety: .review,
            cleanup: .trashContents,
            suggest: true,
            whatItIs: "Each simulated iPhone, iPad, Watch or TV, with the apps and data installed on it.",
            ifDeleted: "The simulator and the apps on it are deleted. Xcode recreates default simulators when needed. (In Terminal, `xcrun simctl delete unavailable` removes simulators for runtimes you no longer have.)",
            insideNote: "One simulated device."
        ),
        KnownLocation(
            id: "simulator-caches",
            title: "Simulator caches",
            paths: ["~/Library/Developer/CoreSimulator/Caches"],
            category: .developer,
            safety: .safe,
            cleanup: .trashContents,
            suggest: true,
            whatItIs: "Caches used by the iOS Simulator.",
            ifDeleted: "The simulator rebuilds them; the next launch is slower."
        ),
        KnownLocation(
            id: "xcode-user-data",
            title: "Xcode settings",
            paths: ["~/Library/Developer/Xcode/UserData"],
            category: .developer,
            safety: .caution,
            cleanup: .individually,
            whatItIs: "Your Xcode customisations: key bindings, code snippets, colour themes and breakpoints.",
            ifDeleted: "Xcode forgets your customisations."
        ),
        KnownLocation(
            id: "xcode-previews",
            title: "SwiftUI preview & playground simulators",
            paths: ["~/Library/Developer/Xcode/UserData/Previews", "~/Library/Developer/XCPGDevices"],
            category: .developer,
            safety: .safe,
            cleanup: .trashContents,
            suggest: true,
            whatItIs: "Hidden simulators Xcode creates to run SwiftUI previews and playgrounds.",
            ifDeleted: "Xcode recreates them the next time you use previews or playgrounds."
        ),
        KnownLocation(
            id: "xcode-documentation",
            title: "Xcode documentation cache",
            paths: ["~/Library/Developer/Xcode/DocumentationCache", "~/Library/Developer/Xcode/DocumentationIndex"],
            category: .developer,
            safety: .safe,
            cleanup: .trashContents,
            suggest: true,
            whatItIs: "Downloaded developer documentation and its search index.",
            ifDeleted: "Xcode downloads documentation again when you open it."
        ),
        KnownLocation(
            id: "xcode-device-logs",
            title: "Device logs",
            paths: ["~/Library/Developer/Xcode/iOS Device Logs"],
            category: .developer,
            safety: .safe,
            cleanup: .trashContents,
            suggest: true,
            whatItIs: "Crash logs Xcode copied from connected devices.",
            ifDeleted: logsDeleted
        ),
        KnownLocation(
            id: "xcode-cache",
            title: "Xcode cache",
            paths: ["~/Library/Caches/com.apple.dt.Xcode"],
            category: .developer,
            safety: .safe,
            cleanup: .trashItem,
            whatItIs: "Caches used by Xcode.",
            ifDeleted: "Xcode rebuilds it."
        ),
        KnownLocation(
            id: "package-caches",
            title: "Package manager cache",
            paths: [
                "~/Library/Caches/Homebrew", "~/Library/Caches/pip", "~/Library/Caches/pypoetry", "~/Library/Caches/Yarn",
                "~/Library/Caches/CocoaPods", "~/Library/Caches/org.carthage.CarthageKit", "~/Library/Caches/ms-playwright",
                "~/Library/Caches/JetBrains", "~/Library/Caches/Google/AndroidStudio*", "~/Library/Caches/node-gyp",
                "~/Library/Caches/deno", "~/Library/Caches/go-build", "~/Library/Caches/typescript", "~/Library/Caches/pnpm",
                "~/.cache/uv", "~/.cache/pip", "~/.cache/pre-commit", "~/.cache/puppeteer", "~/.cache/bazel",
            ],
            category: .developer,
            safety: .safe,
            cleanup: .trashItem,
            whatItIs: "Downloads and build caches kept by a developer tool. Re-downloaded or rebuilt when needed.",
            ifDeleted: "The tool downloads or rebuilds what it needs next time."
        ),
        KnownLocation(
            id: "npm",
            title: "npm cache",
            paths: ["~/.npm"],
            category: .developer,
            safety: .safe,
            cleanup: .trashContents,
            suggest: true,
            whatItIs: "Packages npm has downloaded, shared by all your JavaScript projects, plus cached npx tools and logs.",
            ifDeleted: "npm downloads packages again as your projects need them."
        ),
        KnownLocation(
            id: "js-package-stores",
            title: "JavaScript package stores",
            paths: ["~/Library/pnpm/store", "~/.local/share/pnpm/store", "~/.yarn/berry/cache", "~/.bun/install/cache"],
            category: .developer,
            safety: .safe,
            cleanup: .trashItem,
            suggest: true,
            whatItIs: "Package downloads shared between projects by pnpm, Yarn and Bun.",
            ifDeleted: "Packages are downloaded again the next time you install."
        ),
        KnownLocation(
            id: "gradle",
            title: "Gradle caches",
            paths: ["~/.gradle/caches", "~/.gradle/wrapper/dists", "~/.gradle/daemon"],
            category: .developer,
            safety: .safe,
            cleanup: .trashContents,
            suggest: true,
            whatItIs: "Dependencies and Gradle versions downloaded for Android and Java builds.",
            ifDeleted: "Gradle downloads what it needs on the next build."
        ),
        KnownLocation(
            id: "maven",
            title: "Maven repository",
            paths: ["~/.m2/repository"],
            category: .developer,
            safety: .safe,
            cleanup: .trashContents,
            suggest: true,
            whatItIs: "Java libraries downloaded by Maven and other build tools.",
            ifDeleted: "Libraries are downloaded again on the next build."
        ),
        KnownLocation(
            id: "cargo",
            title: "Rust crate cache",
            paths: ["~/.cargo/registry", "~/.cargo/git"],
            category: .developer,
            safety: .safe,
            cleanup: .trashContents,
            suggest: true,
            whatItIs: "Rust crates downloaded by Cargo.",
            ifDeleted: "Cargo downloads crates again on the next build."
        ),
        KnownLocation(
            id: "rustup",
            title: "Rust toolchains",
            paths: ["~/.rustup/toolchains"],
            category: .developer,
            safety: .review,
            cleanup: .manual("Run `rustup toolchain list`, then `rustup toolchain uninstall <name>` for ones you don't use."),
            suggest: true,
            whatItIs: "Rust compiler versions installed with rustup.",
            ifDeleted: "Projects that need a removed toolchain will install it again."
        ),
        KnownLocation(
            id: "go-modules",
            title: "Go module cache",
            paths: ["~/go/pkg/mod"],
            category: .developer,
            safety: .safe,
            cleanup: .manual("Run `go clean -modcache` in Terminal. Go marks these files read-only, so they're awkward to delete any other way."),
            suggest: true,
            whatItIs: "Go modules downloaded for your projects.",
            ifDeleted: "Go downloads modules again on the next build."
        ),
        KnownLocation(
            id: "conda",
            title: "Conda package cache",
            paths: ["~/miniconda3/pkgs", "~/anaconda3/pkgs", "~/miniforge3/pkgs", "~/mambaforge/pkgs", "~/opt/anaconda3/pkgs", "~/opt/miniconda3/pkgs"],
            category: .developer,
            safety: .safe,
            cleanup: .trashContents,
            suggest: true,
            whatItIs: "Downloaded package archives kept by Conda. Your environments don't need them once installed.",
            ifDeleted: "Conda downloads packages again if you install them into a new environment. (`conda clean --all` does the same thing.)"
        ),
        KnownLocation(
            id: "language-versions",
            title: "Installed language versions",
            paths: ["~/.nvm/versions/node", "~/.pyenv/versions", "~/.rbenv/versions", "~/.local/share/mise/installs", "~/.asdf/installs"],
            category: .developer,
            safety: .review,
            cleanup: .trashContents,
            suggest: true,
            whatItIs: "Versions of Node.js, Python or Ruby installed by version managers (nvm, pyenv, rbenv, mise, asdf). Old versions linger after upgrades.",
            ifDeleted: "Projects pinned to a deleted version need it reinstalled.",
            insideNote: "One installed language version."
        ),
        KnownLocation(
            id: "ollama",
            title: "Ollama models",
            paths: ["~/.ollama/models"],
            category: .developer,
            safety: .review,
            cleanup: .manual("Run `ollama list` to see models, then `ollama rm <model>` for ones you don't use. Deleting files here directly confuses Ollama."),
            suggest: true,
            whatItIs: "Local AI models downloaded by Ollama. Each one is several gigabytes.",
            ifDeleted: "Models have to be downloaded again."
        ),
        KnownLocation(
            id: "lm-studio",
            title: "LM Studio models",
            paths: ["~/.lmstudio/models", "~/.cache/lm-studio/models"],
            category: .developer,
            safety: .review,
            cleanup: .trashContents,
            suggest: true,
            whatItIs: "Local AI models downloaded by LM Studio. Each one is several gigabytes.",
            ifDeleted: "Models have to be downloaded again."
        ),
        KnownLocation(
            id: "android",
            title: "Android Studio data",
            paths: ["~/Library/Android"],
            category: .developer,
            safety: .review,
            cleanup: .trashItem,
            whatItIs: "Android development tools installed by Android Studio.",
            ifDeleted: "Android builds stop working until the tools are reinstalled."
        ),
        KnownLocation(
            id: "android-sdk",
            title: "Android SDK",
            paths: ["~/Library/Android/sdk"],
            category: .developer,
            safety: .review,
            cleanup: .trashItem,
            suggest: true,
            whatItIs: "Android development tools, platforms, NDKs and emulator images installed by Android Studio. Often 10–30 GB. To trim it instead, remove components in Android Studio › Settings › Languages & Frameworks › Android SDK.",
            ifDeleted: "Android builds stop working until Android Studio downloads the SDK again. If you don't build Android apps any more, it's safe to remove."
        ),
        KnownLocation(
            id: "android-images",
            title: "Android emulator images",
            paths: ["~/Library/Android/sdk/system-images", "~/.android/avd"],
            category: .developer,
            safety: .review,
            cleanup: .trashContents,
            suggest: true,
            whatItIs: "Android emulator system images and the virtual devices made from them. Each is a few gigabytes.",
            ifDeleted: "You'll need to download the image or recreate the virtual device in Android Studio."
        ),
        KnownLocation(
            id: "unity-cache",
            title: "Unity caches",
            paths: ["~/Library/Unity/cache", "~/Library/Unity/Asset Store-5.x"],
            category: .developer,
            safety: .safe,
            cleanup: .trashContents,
            suggest: true,
            whatItIs: "Packages and Asset Store downloads cached by Unity.",
            ifDeleted: "Unity downloads them again when a project needs them."
        ),
    ]

    // MARK: - Virtual machines

    static let virtualMachines: [KnownLocation] = [
        KnownLocation(
            id: "docker-desktop",
            title: "Docker Desktop disk",
            paths: ["~/Library/Containers/com.docker.docker/Data/vms"],
            category: .virtualMachines,
            safety: .caution,
            cleanup: .manual("Run `docker system prune -a` (add `--volumes` to include volumes) to remove unused images and containers, or use Docker Desktop › Troubleshoot › Clean / Purge data. You can also lower the disk limit in Docker Desktop › Settings › Resources."),
            systemData: true,
            suggest: true,
            whatItIs: "Docker Desktop's virtual disk (Docker.raw). It holds every image, container, volume and build cache. It's often the single biggest item in System Data for developers.",
            ifDeleted: "All Docker images, containers and volumes are lost."
        ),
        KnownLocation(
            id: "orbstack",
            title: "OrbStack data",
            paths: ["~/Library/Group Containers/HUAQ24HBR6.dev.orbstack/data"],
            category: .virtualMachines,
            safety: .caution,
            cleanup: .manual("Remove unused images and containers with `docker system prune -a`, or delete machines from the OrbStack app."),
            systemData: true,
            suggest: true,
            whatItIs: "OrbStack's disk with your Docker images, containers and Linux machines.",
            ifDeleted: "All containers, images and Linux machines are lost."
        ),
        KnownLocation(
            id: "colima",
            title: "Colima / Lima virtual machines",
            paths: ["~/.colima", "~/.lima"],
            category: .virtualMachines,
            safety: .caution,
            cleanup: .manual("Run `docker system prune -a` to free space inside the VM, or `colima delete` / `limactl delete <name>` to remove a VM."),
            systemData: true,
            suggest: true,
            whatItIs: "Linux virtual machines used by Colima or Lima to run containers.",
            ifDeleted: "The VMs and their containers are lost."
        ),
        KnownLocation(
            id: "podman",
            title: "Podman storage",
            paths: ["~/.local/share/containers"],
            category: .virtualMachines,
            safety: .caution,
            cleanup: .manual("Run `podman system prune -a` to remove unused images and containers."),
            systemData: true,
            suggest: true,
            whatItIs: "Container images and machines used by Podman.",
            ifDeleted: "All Podman images and containers are lost."
        ),
        KnownLocation(
            id: "virtual-machines",
            title: "Virtual machines",
            paths: [
                "~/Parallels", "~/Library/Containers/com.utmapp.UTM/Data/Documents", "~/Virtual Machines.localized",
                "~/Virtual Machines", "~/VirtualBox VMs", "~/.tart/vms",
            ],
            category: .virtualMachines,
            safety: .review,
            cleanup: .trashContents,
            systemData: true,
            suggest: true,
            whatItIs: "Virtual computers made with Parallels, UTM, VMware Fusion, VirtualBox or Tart. Each contains a whole operating system and can be tens of gigabytes.",
            ifDeleted: "The virtual machine and everything inside it are gone.",
            insideNote: "One virtual machine."
        ),
        KnownLocation(
            id: "tart-cache",
            title: "Tart image cache",
            paths: ["~/.tart/cache"],
            category: .virtualMachines,
            safety: .safe,
            cleanup: .trashContents,
            systemData: true,
            suggest: true,
            whatItIs: "VM images Tart downloaded to create virtual machines from.",
            ifDeleted: "Images are downloaded again the next time you create a VM from them."
        ),
    ]

    // MARK: - Media

    static let media: [KnownLocation] = [
        KnownLocation(
            id: "photos-library",
            title: "Photos library",
            paths: ["~/Pictures/*.photoslibrary"],
            category: .mediaLibraries,
            safety: .protected,
            cleanup: .manual("In Photos › Settings › iCloud, turn on Optimize Mac Storage to keep only small versions on this Mac. To delete photos, delete them in Photos and then empty the Recently Deleted album."),
            suggest: true,
            whatItIs: "Your Photos library: all your photos and videos, plus thumbnails and edits.",
            ifDeleted: "Photos that aren't in iCloud or another backup would be lost forever."
        ),
        KnownLocation(
            id: "music-library",
            title: "Music library",
            paths: ["~/Music/Music", "~/Music/iTunes"],
            category: .mediaLibraries,
            safety: .review,
            cleanup: .manual("In the Music app, select downloaded songs and choose Remove Download, or delete songs you no longer want from the library."),
            suggest: true,
            whatItIs: "Songs and videos in the Music app, plus its library database.",
            ifDeleted: "Deleting files here directly leaves broken songs in Music."
        ),
        KnownLocation(
            id: "tv-library",
            title: "TV app library",
            paths: ["~/Movies/TV"],
            category: .mediaLibraries,
            safety: .review,
            cleanup: .manual("In the TV app, remove downloaded shows and films."),
            suggest: true,
            whatItIs: "Films and shows downloaded in the TV app.",
            ifDeleted: "Deleting files here directly leaves broken items in the TV app."
        ),
    ]
}
