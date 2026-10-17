# Rendered by the release workflow of github.com/vishisht16/syg; do not edit.
class Syg < Formula
  desc "Typed language for a Kubernetes service's deployment surface, and its checker"
  homepage "https://syg.vishisht.tech"
  version "@version@"
  license :cannot_represent # Syg EULA: https://syg.vishisht.tech/eula

  on_macos do
    on_arm do
      url "@darwin_arm64_url@"
      sha256 "@darwin_arm64_sha256@"
    end
    on_intel do
      url "@darwin_amd64_url@"
      sha256 "@darwin_amd64_sha256@"
    end
  end

  on_linux do
    on_arm do
      url "@linux_arm64_url@"
      sha256 "@linux_arm64_sha256@"
    end
    on_intel do
      url "@linux_amd64_url@"
      sha256 "@linux_amd64_sha256@"
    end
  end

  def install
    bin.install "syg"
  end

  test do
    assert_match "syg #{version}", shell_output("#{bin}/syg version")
    (testpath/"new").mkpath
    system bin/"syg", "init", testpath/"new/app", "--service", "api"
    system bin/"syg", "check", testpath/"new/app"
  end
end
