class Awake < Formula
  desc "Keep your MacBook awake with the lid closed, with battery and thermal guards"
  homepage "https://il.ly/awake"
  url "https://github.com/Illyism/awake/archive/refs/tags/v1.0.1.tar.gz"
  sha256 "6bc3cdbbcb1eae23b432239f13b89fd23534e78ee0a9adc2be6d1d37b8812bad"
  license "MIT"
  head "https://github.com/Illyism/awake.git", branch: "main"

  depends_on :macos

  def install
    bin.install "awake"
    bin.install_symlink "awake" => "asleep"
    (pkgshare/"sudoers.d").install "sudoers.d/awake"
  end

  def caveats
    <<~EOS
      To let `awake` and `asleep` toggle lid sleep (`pmset disablesleep 0/1`) without a password prompt, run once:
        awake setup

      To also install the macOS Control Center & Menu Bar app (`Awake.app`):
        brew install --cask illyism/awake/awake
    EOS
  end

  test do
    assert_match "awake #{version}", shell_output("#{bin}/awake --version")
  end
end
