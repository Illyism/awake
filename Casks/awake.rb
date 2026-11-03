cask "awake" do
  version "1.0.0"
  sha256 "90f713c98556e4f3cf806511ff9b537144fee006577b8a4c215ef191eff98b7d"

  url "https://github.com/Illyism/awake/releases/download/v#{version}/Awake-#{version}-macos-arm64.dmg"
  name "Awake"
  desc "Keep your MacBook awake with the lid closed (Control Center, Menu Bar, and CLI)"
  homepage "https://il.ly/awake"

  depends_on arch: :arm64
  depends_on macos: ">= :tahoe"

  app "Awake.app"
  binary "#{appdir}/Awake.app/Contents/Resources/awake", target: "awake"
  binary "#{appdir}/Awake.app/Contents/Resources/awake", target: "asleep"

  uninstall script: {
              executable: "#{appdir}/Awake.app/Contents/Resources/awake",
              args:       ["stop"],
              sudo:       false,
            },
            quit:   "com.illyism.awake"

  zap trash: [
    "~/.cache/awake",
    "~/Library/Preferences/com.illyism.awake.plist",
  ]

  caveats <<~EOS
    Run `awake setup` once (or click "Enable Lid-Closed Sleep Guard" in the Awake menu bar icon)
    to install `/etc/sudoers.d/awake` for passwordless `pmset -a disablesleep 0/1`.
  EOS
end
