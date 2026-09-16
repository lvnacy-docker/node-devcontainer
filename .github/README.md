# Node.js Dev Container

A production-ready Dockerfile optimized for VS Code's Dev Container extension, providing a complete Node.js development environment with mise for version management.

## Features

- **🔧 mise Integration**: Seamless Node.js version management
- **💻 VS Code Optimized**: Pre-configured for Dev Container extension
- **🔒 Security First**: Non-root execution with hardened runtime environment
    - No `apt`, `dpkg`, `curl`, etc
- **📦 TypeScript Ready**: Global TypeScript installation for immediate use
- **📦 pnpm Ready**: pnpm 12 installed globally for package management
- **⚡ Multi-Stage Build**: Optimized for both development and production

## Quick Start

### Using VS Code Dev Containers

1. **Prerequisites**: Install [VS Code](https://code.visualstudio.com/) and the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)

2. **Open in Container**:
   - Open VS Code
   - Configure `.devcontainer/devcontainer.json` (see below)
   - Command Palette → `Dev Containers: Reopen in Container`

3. **Start Developing**: Your development environment is ready with Node.js 24, npm, pnpm, and TypeScript!

### Manual Docker Usage

1. Clone this repo and

```bash
# Build the container
docker build -t node-devcontainer .
```

2. Navigate to your project workspace and

```
# Run interactively
docker run -it --rm -v "$(pwd)":/workspace node-devcontainer

# Run with proper user mapping (macOS/Linux)
docker run -it --rm -v "$(pwd)":/workspace --user 1000:1000 node-devcontainer
```

## Configuration

### Dev Container Integration

Create `.devcontainer/devcontainer.json` in your project:

```json
{
    "name": "Node.js Dev Container",
    "image": "lvnacy/node-devcontainer:latest",
    "customizations": {
        "vscode": {
            "extensions": [
                "ms-vscode.vscode-typescript-next",
                "esbenp.prettier-vscode"
            ]
        }
    }
}
```

### mise Version Management

```bash
# Pin Node.js version for your project
mise use node@20

# Install specific versions
mise install node@18
mise install npm@10

# List available versions
mise ls
```

## Architecture

### Multi-Stage Build Design

- **Builder Stage**: Development tools, mise, Node.js, and TypeScript installation
- **Runtime Stage**: Minimal production environment with security hardening
- **VS Code Integration**: Uses `vscode` user convention for seamless IDE integration

### Security Features

- Root account completely disabled
- Non-privileged user execution
- Minimal attack surface
- Optimized layer caching

## Build Arguments

Customize the container build:

- `USERNAME=vscode`: Container username (default: vscode)
- `USER_UID=1000`: User ID (default: 1000)
- `USER_GID=1000`: Group ID (default: 1000)

```bash
docker build --build-arg USER_UID=$(id -u) --build-arg USER_GID=$(id -g) -t node-devcontainer .
```

## Requirements

- Docker Engine 20.10+
- VS Code with Dev Containers extension (for Dev Container usage)
- Git (for cloning the repository)

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Contributing

This project is not accepting PRs at this time. If you encounter a bug or have a suggestion to improve the image, please open an issue.

---

*This container follows VS Code Dev Container conventions and provides an optimized Node.js development environment suitable for any Node.js project.*