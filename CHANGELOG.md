# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2025-10-04

### Added

- Initial release of ReqFly
- Req plugin for Fly.io Machines API with seamless integration
- **Apps API** - Complete application management
  - List apps with organization filtering
  - Create new applications
  - Get application details
  - Destroy applications
- **Machines API** - Full lifecycle management
  - List machines in an application
  - Create machines with comprehensive configuration
  - Get machine details
  - Update machine configuration
  - Start, stop, restart, and signal machines
  - Wait for machines to reach desired states
  - Destroy machines
  - Lease management (acquire and release)
  - Cordon and uncordon operations
  - Metadata and event queries
- **Secrets API** - Secure secrets management
  - List application secrets
  - Create secrets with custom values
  - Generate random secrets
  - Delete secrets
- **Volumes API** - Persistent storage management
  - List volumes
  - Create volumes with size and region specification
  - Get volume details
  - Update volume configuration
  - Extend volume size
  - Delete volumes
  - Create volume snapshots
  - List volume snapshots
- **Orchestrator** - High-level multi-step workflows
  - Create app and wait for activation
  - Create machine and wait for ready state
  - Exponential backoff with jitter for polling
  - Configurable timeouts and intervals
- **Error Handling**
  - Structured error responses with `ReqFly.Error` exception
  - Detailed error messages from API responses
  - Status code preservation
- **Retry Logic**
  - Built-in retry with exponential backoff
  - Configurable retry strategies (`:safe_transient`, `:transient`, etc.)
  - Configurable max retries
- **Telemetry Support**
  - Request lifecycle events (start, stop, exception)
  - Orchestrator operation events
  - Configurable telemetry prefixes
  - Rich metadata for observability
- **Testing Infrastructure**
  - Comprehensive test suite with 187 tests
  - ExVCR integration for API cassette recording
  - Bypass integration for mock server testing
  - High test coverage across all modules
- **Documentation**
  - Complete module documentation with examples
  - Detailed function documentation
  - Comprehensive README with usage examples
  - Getting started guide
  - Configuration examples for all patterns

### Development Tools

- Mix task for OpenAPI spec analysis (`mix req_fly.analyze_spec`)
- Code quality tools (Credo, Dialyzer)
- Automated formatting configuration

[Unreleased]: https://github.com/mikehostetler/req_fly/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/mikehostetler/req_fly/releases/tag/v1.0.0
