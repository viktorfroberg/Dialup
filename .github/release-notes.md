**Download `Dialup.zip`**, unzip it and drag **Dialup.app** to Applications. Needs macOS 15.4 or later; runs on Apple silicon and Intel Macs.

**First launch:** Dialup is ad-hoc signed, not notarized by Apple, so macOS blocks it the first time. Try to open it once, then go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway**. Or run this in Terminal *before* you move the app to Applications (inside Applications, macOS only lets the command work if Terminal has the App Management permission):

```sh
xattr -dr com.apple.quarantine ~/Downloads/Dialup.app
```

See [CHANGELOG.md](https://github.com/viktorfroberg/Dialup/blob/main/CHANGELOG.md) for what's in this version.
