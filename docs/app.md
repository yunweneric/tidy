
# 🧩 App Overview — Mac App Uninstaller (Flutter)

### 🎯 Goal

Help users **completely remove Mac apps** — including hidden leftover files — safely and fast.

Most Mac apps leave behind:
• Cache files
• Preferences
• Background support folders
• Logs

Your app detects and removes all of them.

---

# 📱 Core Features (MVP)

### 1. App Scanner

Scans:

```
/Applications
~/Applications
```

Shows:

* App name
* App icon
* Size on disk

---

### 2. Deep Cleanup Engine

For each app, scans:

📁 Application bundle
📁 ~/Library/Application Support
📁 ~/Library/Preferences
📁 ~/Library/Caches
📁 ~/Library/Logs
📁 Launch agents & daemons

So users don’t leave junk behind.

---

### 3. Safe Preview Mode (important)

Before deleting:

✅ Shows all files found
✅ User can deselect anything
✅ Total space to be freed displayed

(No risky blind deletes)

---

### 4. One-Click Uninstall

Options:
🗑 Move to Trash (safe)
🔥 Permanent delete (advanced)

---

# 🖥️ UI Flow (Simple & Professional)

Home Screen
→ List of installed apps

Tap an app
→ Scan results screen (files + sizes)

Click “Uninstall”
→ Progress animation
→ Space freed summary

---

# 🔐 Permissions & Security

Requires:

✔ Full Disk Access
✔ File system permission

Your app never:
❌ Uploads data
❌ Tracks user apps
❌ Touches system files without preview

(Local only = trusted)

---

# ⚙️ Technical Architecture

### Flutter Layer

* UI
* App state
* File preview
* Progress

### Native macOS Layer (Dart calls)

Uses:

* shell commands (`rm`, `du`, `find`)
* file APIs

Optional native Swift plugin for faster scans later.

---

# 📦 File Detection Logic (Smart Part)

Instead of guessing names only:

Uses:

* app bundle id
* common folder patterns
* preference plist search

Much more accurate than basic cleaners.

---

# 🚀 Advanced Features (v2+)

✨ Detect unused apps
✨ Startup manager
✨ Duplicate file finder
✨ Storage analyzer (like macOS system report)
✨ Scheduled cleanup

---

# 💼 Real-World Use Cases

• Developers cleaning environments
• Designers removing heavy apps
• Normal users freeing space
• IT teams managing Macs

---

# 📈 Monetization (if you want)

Free:
✔ Basic uninstall

Pro:
💰 Deep leftover scan
💰 Storage analytics
💰 Batch uninstall

One-time purchase works well on macOS.

---

If you’d like, I can next:

✅ Create full feature spec document
✅ UX wireframe flow
✅ Database structure (for scan history)
✅ App name ideas + branding
✅ Flutter project structure

Do you want this positioned as:

• A commercial Mac utility
• An open-source tool
• A portfolio project

I can tailor everything based on that direction.
