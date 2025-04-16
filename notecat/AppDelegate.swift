import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var textField: NSTextView!
    var obsidianFolderPath: String?
    var folderBookmark: Data?
    let userDefaults = UserDefaults.standard
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check if we already have a saved folder
        if let bookmarkData = userDefaults.data(forKey: "ObsidianFolderBookmark") {
            restoreBookmark(bookmarkData)
        }
        
        createMainWindow()
        
        // If we don't have a folder path yet, show folder picker
        if obsidianFolderPath == nil {
            pickFolder()
        }
    }
    
    func createMainWindow() {
        // Create window
        let windowRect = NSRect(x: 0, y: 0, width: 500, height: 330)
        window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "NoteCat"
        window.center()
        
        // Create text view
        let scrollView = NSScrollView(frame: NSRect(x: 10, y: 50, width: 480, height: 240))
        textField = NSTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 240))
        textField.isEditable = true
        textField.isRichText = false
        textField.font = NSFont.systemFont(ofSize: 14)
        textField.isVerticallyResizable = true
        textField.isHorizontallyResizable = false
        
        scrollView.documentView = textField
        scrollView.hasVerticalScroller = true
        
        // Create save button
        let saveButton = NSButton(frame: NSRect(x: 410, y: 10, width: 80, height: 30))
        saveButton.title = "Save"
        saveButton.bezelStyle = .rounded
        saveButton.action = #selector(saveNote)
        saveButton.target = self
        
        // Create change folder button
        let changeFolderButton = NSButton(frame: NSRect(x: 10, y: 10, width: 130, height: 30))
        changeFolderButton.title = "Change Folder"
        changeFolderButton.bezelStyle = .rounded
        changeFolderButton.action = #selector(pickFolder)
        changeFolderButton.target = self
        
        // Create folder path label
        let folderLabel = NSTextField(frame: NSRect(x: 10, y: 295, width: 480, height: 20))
        folderLabel.isEditable = false
        folderLabel.isBordered = false
        folderLabel.backgroundColor = .clear
        folderLabel.stringValue = "Selected Folder: " + (obsidianFolderPath ?? "None")
        folderLabel.tag = 100 // Tag for finding later
        
        // Add components to window
        let contentView = NSView(frame: windowRect)
        contentView.addSubview(scrollView)
        contentView.addSubview(saveButton)
        contentView.addSubview(changeFolderButton)
        contentView.addSubview(folderLabel)
        window.contentView = contentView
        
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func pickFolder() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = true
        openPanel.canChooseFiles = false
        openPanel.prompt = "Select Obsidian Vault Folder"
        openPanel.message = "Choose the folder where your Obsidian notes should be saved:"
        
        openPanel.begin { [weak self] (result) in
            guard let self = self, result == .OK, let url = openPanel.url else { return }
            
            do {
                // Start accessing the security-scoped resource
                let startedAccessing = url.startAccessingSecurityScopedResource()
                
                // Create a security bookmark
                let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                
                self.userDefaults.set(bookmarkData, forKey: "ObsidianFolderBookmark")
                self.folderBookmark = bookmarkData
                self.obsidianFolderPath = url.path
                
                // Update folder path label if window exists
                if let contentView = self.window?.contentView,
                   let folderLabel = contentView.viewWithTag(100) as? NSTextField {
                    folderLabel.stringValue = "Selected Folder: \(url.path)"
                }
                
                // Stop accessing the resource when done
                if startedAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            } catch {
                self.showAlert(message: "Failed to save folder access: \(error.localizedDescription)")
            }
        }
    }
    
    func restoreBookmark(_ bookmarkData: Data) {
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            
            if isStale {
                // Handle stale bookmark if needed
                pickFolder()
                return
            }
            
            let startedAccessing = url.startAccessingSecurityScopedResource()
            obsidianFolderPath = url.path
            
            // Store for later use
            if startedAccessing {
                // Note: We'll stop accessing later when done with the bookmark
                folderBookmark = bookmarkData
            }
        } catch {
            print("Failed to resolve bookmark: \(error)")
            // If we can't restore the bookmark, we'll need to select a new folder
            pickFolder()
        }
    }
    
    @objc func saveNote() {
        guard let path = obsidianFolderPath, !path.isEmpty else {
            showAlert(message: "Please select an Obsidian folder first")
            pickFolder()
            return
        }
        
        let content = textField.string
        guard !content.isEmpty else {
            showAlert(message: "Cannot save empty note!")
            return
        }
        
        // Create URL from path
        guard let url = URL(string: "file://" + path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!) else {
            showAlert(message: "Invalid folder path")
            return
        }
        
        // Try to access the security-scoped resource
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        
        // Extract first line or first few words for the title
        var title = ""
        if let firstLine = content.components(separatedBy: .newlines).first, !firstLine.isEmpty {
            title = firstLine
            // Limit title length
            if title.count > 30 {
                title = String(title.prefix(30)) + "..."
            }
        } else {
            title = "Note"
        }
        
        // Sanitize title for filename
        title = title.replacingOccurrences(of: "/", with: "-")
                     .replacingOccurrences(of: "\\", with: "-")
                     .replacingOccurrences(of: ":", with: "-")
                     .replacingOccurrences(of: "*", with: "-")
                     .replacingOccurrences(of: "?", with: "-")
                     .replacingOccurrences(of: "\"", with: "-")
                     .replacingOccurrences(of: "<", with: "-")
                     .replacingOccurrences(of: ">", with: "-")
                     .replacingOccurrences(of: "|", with: "-")
        
        // Create filename
        let filename = "\(timestamp) - \(title).md"
        
        // Create file URL
        let fileURL = url.appendingPathComponent(filename)
        
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            textField.string = ""
            window.close()
        } catch {
            showAlert(message: "Failed to save note: \(error.localizedDescription)")
        }
    }
    
    func showAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Release any security-scoped resources if still accessing
        if let url = URL(string: "file://" + (obsidianFolderPath ?? "").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!) {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

// Create a proper application entry point
extension AppDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
