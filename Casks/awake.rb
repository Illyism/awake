cask "awake" do
  version "1.0.1"
  sha256 "41a811657cac69e84851417f50054f06b5ac6038e1f6b2d0394c6e3327b13df0"

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
