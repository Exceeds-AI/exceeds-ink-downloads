# exceeds-ink-downloads

Public installers and release assets for `exceeds-ink`.

This repository is a distribution mirror. The private source of truth lives in the main `exceeds-ink` repository; tagged releases there publish:

- `install.sh`
- `install.ps1`
- platform archives and `.sha256` files
- `SHA256SUMS`

Install commands:

```bash
curl -fsSL https://raw.githubusercontent.com/Exceeds-AI/exceeds-ink-downloads/latest/install.sh | sh
```

By default this installs the binary, runs `exceeds-ink setup` and `exceeds-ink install --all` against the public Exceeds Vercel collector. Afterward run `exceeds-ink init` in each git repository you want to track. Use `--binary-only` or `EXCEEDS_INK_BINARY_ONLY=1` to install only the binary. The macOS/Linux installer still leaves `PATH` unchanged, but now prints shell-specific commands to help you add `~/.exceeds-ink/bin` yourself and gives you an absolute-path verification command you can run immediately.

```powershell
powershell -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Exceeds-AI/exceeds-ink-downloads/latest/install.ps1 | iex"
```

Version pinning:

```bash
curl -fsSL https://raw.githubusercontent.com/Exceeds-AI/exceeds-ink-downloads/v0.1.1/install.sh | sh
```

The `latest` branch tracks the newest published installer scripts. Fetch the installer from the matching tag when pinning a version so the installer behavior stays aligned with the binary release you want for yourself.
