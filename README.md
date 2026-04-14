# exceeds-ink-downloads

Public installers and release assets for `ai-ink`.

This repository is a distribution mirror. The private source of truth lives in the main `exceeds-ink` repository; tagged releases there publish:

- `install.sh`
- `install.ps1`
- platform archives and `.sha256` files
- `SHA256SUMS`

Install commands:

```bash
curl -fsSL https://raw.githubusercontent.com/Exceeds-AI/exceeds-ink-downloads/main/install.sh | sh
```

```powershell
powershell -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/Exceeds-AI/exceeds-ink-downloads/main/install.ps1 | iex"
```

Version pinning:

```bash
curl -fsSL https://raw.githubusercontent.com/Exceeds-AI/exceeds-ink-downloads/main/install.sh | env AI_INK_VERSION=0.1.1 sh
```
