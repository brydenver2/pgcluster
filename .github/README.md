# GitHub Configuration Files

This directory contains GitHub-specific configuration files to enhance the development experience with this repository.

## Files

### copilot-instructions.md

This file provides comprehensive context and instructions for GitHub Copilot to better assist with development in this repository. It includes:

- **Project Overview**: What this repository is and what it does
- **Architecture**: Detailed component breakdown
- **Technology Stack**: All technologies used (PostgreSQL, Node.js, React, Docker, etc.)
- **Code Conventions**: Style guides and patterns for JavaScript, React, Shell scripts, and Docker
- **File Organization**: Complete directory structure with descriptions
- **Development Workflow**: How to build, test, and develop locally
- **Deployment Modes**: Different ways to deploy the cluster
- **Common Operations**: Frequently used commands and operations
- **Code Generation Guidelines**: Best practices for generating code
- **Troubleshooting Tips**: Common issues and solutions

This file helps GitHub Copilot understand the project context and provide more accurate, context-aware code suggestions and completions.

## How It Helps

With these instructions in place, GitHub Copilot will:

1. **Better understand the codebase** - Knows about PostgreSQL cluster architecture, repmgr, pgpool, etc.
2. **Follow project conventions** - Generates code that matches existing patterns
3. **Use correct technologies** - Knows to use Express.js, React, Redux, etc.
4. **Suggest appropriate solutions** - Understands deployment scenarios and Docker usage
5. **Provide relevant examples** - Uses project-specific patterns and conventions

## Usage

These instructions are automatically read by GitHub Copilot when you use it in this repository. No additional setup is required beyond having GitHub Copilot installed in your editor.

## Updating

If the project structure, conventions, or technologies change significantly, update the `copilot-instructions.md` file to keep GitHub Copilot's understanding current.
