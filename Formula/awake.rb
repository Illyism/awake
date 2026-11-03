class Awake < Formula
  desc "Keep your MacBook awake with the lid closed, with battery and thermal safety guards"
  homepage "https://il.ly/awake"
  url "https://github.com/Illyism/awake/archive/refs/tags/v1.0.0.tar.gz"
  version "1.0.0"
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

      To also build and install the macOS Control Center & Menu Bar app (`Awake.app`):
        curl -fsSL https://il.ly/awake/install.sh | sh
    EOS
  end

  test do
    assert_match "awake #{version}", shell_output("#{bin}/awake --version")
  end
end
