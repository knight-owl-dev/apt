# Knight Owl Apt Repository

Apt repository for Knight Owl packages, hosted on Cloudflare Pages with binaries served from GitHub Releases.

## Available Packages

- **keystone-cli** — CLI tool for Keystone templates

## Installation

### 1. Import the GPG signing key

```bash
curl -fsSL https://apt.knight-owl.dev/PUBLIC.KEY | sudo gpg --dearmor -o /usr/share/keyrings/knight-owl.gpg
```

### 2. Add the repository

```bash
echo "deb [signed-by=/usr/share/keyrings/knight-owl.gpg] https://apt.knight-owl.dev stable main" | sudo tee /etc/apt/sources.list.d/knight-owl.list
```

### 3. Install packages

```bash
sudo apt-get update
sudo apt-get install keystone-cli
```

## GPG Key

| Property    | Value                                                |
|-------------|------------------------------------------------------|
| Name        | Knight Owl LLC Apt Repository                        |
| Fingerprint | `25F3 E04A E420 DC2A 0F18 1ADC 89B3 FD22 D208 5FDA`  |
| File        | [PUBLIC.KEY](./PUBLIC.KEY)                           |

## Architecture

This repository stores only metadata. Binary packages (`.deb` files) are served directly from [GitHub Releases](https://github.com/knight-owl-dev/keystone-cli/releases) via Cloudflare Pages Functions that redirect requests based on the package version.

## License

[MIT](./LICENSE)
