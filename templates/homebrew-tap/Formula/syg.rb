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
    bash_completion.install "completions/syg.bash" => "syg"
    zsh_completion.install "completions/_syg"
    fish_completion.install "completions/syg.fish"
    man1.install "man/syg.1"
    # What comes with it: the EULA, the privacy statement and the notices of
    # the components it includes.
    prefix.install Dir["*.md", "*.txt"]
  end

  test do
    # Testing the formula is not using Syg: no usage statistics.
    ENV["SYG_TELEMETRY"] = "off"
    assert_match "syg #{version}", shell_output("#{bin}/syg version")
    assert_match "complete -F _syg syg", shell_output("#{bin}/syg completion bash")
    (testpath/"new").mkpath
    system bin/"syg", "init", testpath/"new/app", "--service", "api"
    system bin/"syg", "check", testpath/"new/app"
  end
end
