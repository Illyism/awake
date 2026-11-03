cask "awake" do
  version "1.0.2"
  sha256 "e39e0d8aa306cee415d15c565b85c086c7ddcc1e02cff577bfb9996ad889b410"

  url "https://github.com/Illyism/awake/releases/download/v#{version}/Awake-#{version}-macos-arm64.dmg"
  name "Awake"
  desc "Keep your MacBook awake with the lid closed (Control Center, Menu Bar, and CLI)"
  homepage "https://il.ly/awake"

  depends_on arch: :arm64
  depends_on macos: :tahoe

  app "Awake.app"
  binary "#{appdir}/Awake.app/Contents/Resources/awake", target: "awake"
  binary "#{appdir}/Awake.app/Contents/Resources/awake", target: "asleep"

  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/Awake.app"]
  end

  uninstall quit:   "com.illyism.awake",
            script: {
              executable: "/bin/zsh",
              args:       ["#{appdir}/Awake.app/Contents/Resources/awake", "stop"],
              sudo:       false,
            }

  zap trash: [
    "~/.cache/awake",
    "~/Library/Preferences/com.illyism.awake.plist",
  ]

  caveats <<~EOS
    Run `awake setup` once (or click "Enable Lid-Closed Sleep Guard" in the Awake menu bar icon)
    to install `/etc/sudoers.d/awake` for passwordless `pmset -a disablesleep 0/1`.
  EOS
end
