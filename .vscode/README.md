# VS Code Configuration

This directory contains Visual Studio Code configuration files to provide a consistent development experience across the team.

## Files

### settings.json

Workspace settings for VS Code that configure:

- **Editor Behavior**: Tab size (2 spaces), line endings (LF), trimming whitespace
- **Language-Specific Settings**: 
  - JavaScript: ESLint integration with auto-fix on save
  - YAML: Proper formatting for docker-compose files
  - Shell scripts: Consistent formatting
  - Markdown: Word wrap enabled
- **ESLint Integration**: Configured for both manager/server and manager/client
- **File Exclusions**: Hides node_modules and build directories
- **File Associations**: Properly recognizes Dockerfiles, docker-compose files, and config files

### extensions.json

Recommended VS Code extensions for this project:

- **dbaeumer.vscode-eslint** - JavaScript linting
- **ms-azuretools.vscode-docker** - Docker support
- **timonwong.shellcheck** - Shell script linting
- **foxundermoon.shell-format** - Shell script formatting
- **redhat.vscode-yaml** - YAML validation and formatting
- **mtxr.sqltools** & **mtxr.sqltools-driver-pg** - PostgreSQL database tools
- **eamodio.gitlens** - Enhanced Git integration
- **dsznajder.es7-react-js-snippets** - React code snippets
- **esbenp.prettier-vscode** - Code formatting
- **yzhang.markdown-all-in-one** - Markdown editing support
- **github.copilot** & **github.copilot-chat** - AI-powered code assistance

When you open this workspace in VS Code, you'll be prompted to install these recommended extensions.

## Benefits

These configurations ensure:

1. **Consistent Code Style**: Everyone uses the same indentation, line endings, etc.
2. **Automatic Error Detection**: ESLint and ShellCheck catch issues as you type
3. **Better Tooling**: Extensions provide Docker, PostgreSQL, and React support
4. **Improved Productivity**: Auto-fix on save, code snippets, and Git integration

## Customization

These are workspace settings and recommendations. You can override them in your user settings if needed, but following these configurations helps maintain consistency across the team.
