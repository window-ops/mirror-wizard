# 2. Prerequisites

`curl` and `jq`.

## Debian, Ubuntu

```bash
sudo apt-get install -y curl jq
```

## Fedora, RHEL

```bash
sudo dnf install -y curl jq
```

## Arch

```bash
sudo pacman -S --needed curl jq
```

## macOS

```bash
brew install jq
```

## Git Bash on Windows

`curl` is included. `jq` is absent, and the release is a single binary:

```bash
mkdir -p ~/bin
curl -L -o ~/bin/jq.exe https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-windows-amd64.exe
export PATH="$HOME/bin:$PATH"
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
```

## Verify

```bash
jq --version && curl --version | head -1
```

`grep -P` appears once, in [step 10](10-project-list.md). BSD and macOS grep lack it, and an
alternative is given on that page.

---

Previous: [Parameters](01-parameters.md) | Next: [Session setup](03-session.md)
