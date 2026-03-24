# Contributing to SentioHome

Thank you for your interest in contributing to SentioHome.

## Getting Started

1. Fork the repository
2. Clone your fork and set up the project (see [README](README.md#setup))
3. Create a feature branch from `main`
4. Make your changes
5. Run the test suite: `xcodebuild test -scheme SentioAllTests -destination 'platform=macOS'`
6. Submit a pull request

## Development Workflow

- **XcodeGen** generates the Xcode project from `project.yml`. After modifying `project.yml`, run `xcodegen generate` to regenerate.
- **SentioKit** is a plain macOS framework that contains testable code. Test targets link against it.
- **Swift 6 strict concurrency** is enabled. All mutable state must be `@MainActor`-isolated or use `Mutex`/`nonisolated(unsafe)` where required by framework constraints.

## Code Style

- Follow existing patterns in the codebase
- Use `@Observable` for service classes
- Use `os.Logger` for logging (not `print`)
- Only add comments where the logic isn't self-evident
- Use `@Generable` / `@Guide` for FoundationModels types

## Pull Requests

- Keep PRs focused on a single change
- Include tests for new functionality
- Ensure all tests pass before submitting
- Describe what changed and why in the PR description

## Reporting Issues

- Use GitHub Issues for bug reports and feature requests
- Include reproduction steps, expected behavior, and actual behavior
- Include your macOS version and device details
