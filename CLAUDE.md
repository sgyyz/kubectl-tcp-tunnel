# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

kubectl-tcp-tunnel is a kubectl plugin written entirely in Bash that creates secure TCP tunnels through Kubernetes jump pods. It enables access to remote TCP services (PostgreSQL, MySQL, Redis, MongoDB, etc.) through a Kubernetes cluster without direct exposure.

**Key Architecture Pattern**: The plugin follows a "jump pod" pattern:
1. Switches kubectl context using `kubectx`
2. Creates or reuses a pod running `alpine/socat` in the cluster (one pod per machine/connection type)
3. The socat pod proxies TCP traffic from the jump pod to the remote service
4. `kubectl port-forward` tunnels localhost to the jump pod
5. User connects to localhost; traffic flows through the tunnel
6. On exit (Ctrl+C), the port forward stops but pod remains for reuse
7. User can manually delete pods with `kubectl tcp-tunnel cleanup` command

## Development Commands

### Essential Commands
```bash
# Run all checks (lint + tests) - ALWAYS run before committing
make check

# Run shellcheck linting only
make lint

# Run BATS test suite (all test files)
make test

# Run tests in parallel (CI only, requires GNU parallel)
make test-parallel

# Install plugin locally for manual testing
make install

# Uninstall local installation
make uninstall
```

### First-Time Setup
```bash
# Install dev dependencies (shellcheck, bats-core, yq)
make dev-setup

# Set up pre-commit hooks (runs shellcheck automatically)
make setup-hooks
```

### Running Individual Tests
```bash
# Run specific test file
bats tests/01_argument_parsing_test.bats

# Run specific test by name pattern
bats tests/01_argument_parsing_test.bats -f "shows help"

# Run all tests with verbose output
bats tests/*.bats --verbose
```

## Code Architecture

### Single-File Design
The entire plugin is contained in one executable: `kubectl-tcp_tunnel`. This simplifies distribution as a kubectl plugin and avoids dependency issues.

### Configuration System
- Config location: `~/.config/kubectl-tcp-tunnel/config.yaml` (or `$TCP_TUNNEL_CONFIG`)
- Uses **YAML anchors** for connection type definitions (e.g., `&postgres`, `*postgres`)
- yq (v4+) is used for all YAML parsing with `explode(.)` to resolve anchors
- Structure: `settings` → `environments` → `connections`

Example config pattern:
```yaml
settings:
  postgres: &postgres    # Define anchor
    local-port: 15432
    remote-port: 5432

environments:
  staging:
    k8s-context: staging-cluster
    connections:
      user-db:
        host: db.example.com
        type: *postgres   # Reference anchor
```

**Important**: Use `remote-port` (not `db-port`). The field was renamed in v2.0.4 to reflect support for any TCP service, not just databases.

### Port Architecture
The tool uses three different port spaces:
```
Your Machine          →  Kubernetes Pod       →  Remote Service
localhost:local-port  →  pod:remote-port      →  host:remote-port
(e.g., 15432)            (e.g., 5432)            (e.g., 5432)
```

**Key Points**:
- `local-port`: Port on your machine (can be anything, avoids local conflicts)
- `remote-port`: Port inside jump pod AND on remote service (must match service port)
- No Kubernetes port conflicts - each pod has isolated networking
- Local port conflicts possible - use `-p` flag for multiple simultaneous tunnels

### Argument Parsing
Located in `main()` function starting around line 650. Uses a `while` loop with `case` statement pattern:
```bash
case "$1" in
    --env) environment="$2"; shift 2 ;;
    --connection) database="$2"; shift 2 ;;
    --local-port) local_port="$2"; shift 2 ;;
    ...
esac
```

**Important**: When adding new arguments:
1. Add to the case statement in `main()`
2. Update `show_help()` function (OPTIONS and EXAMPLES sections)
3. Update error messages for missing required args
4. Add tests in appropriate test file under `tests/`
5. Update documentation: README.md, docs/USAGE.md, docs/INSTALLATION.md, config/config.yaml.example

### Key Functions

- **`create_tunnel()`** (line ~504): Core tunnel creation logic with pod reuse
- **`cleanup()`** (line ~489): Trap handler that terminates port-forward (pod remains for reuse)
- **`show_help()`** (line ~61): Help text - keep in sync with actual arguments
- **`load_config()` / `get_*()` functions** (line ~191-262): Config parsing with yq
- **`get_connection_remote_port()`** (line ~258): Gets remote port from connection type
- **`generate_random_suffix()`** (line ~265): DEPRECATED - no longer used (kept for backward compat)
- **`sanitize_pod_name()`** (line ~292): Converts hostnames to valid k8s pod names

### Pod Naming Convention
Format: `{connection-type}-tunnel-{hostname}` (e.g., `postgres-tunnel-johns-macbook`)
- Connection type extracted from YAML anchor name in config
- Falls back to `tcp-tunnel-{hostname}` if no type defined
- Hostname suffix based on local machine's hostname (sanitized for k8s)
- Deterministic naming enables pod reuse across connections
- One pod per machine/connection type for efficient reuse

### Trap Handling
**Critical**: The cleanup trap is set with expanded variables (SC2064 disabled intentionally):
```bash
trap "cleanup '${pod_name}' '${context}' '${namespace}'" EXIT INT TERM
```
This ensures the trap references the specific pod name. Note: The cleanup function no longer deletes pods automatically - it only terminates the port forward. Pods are left running for reuse.

### Port Configuration in create_tunnel()
**Critical Bug Fix** (v2.0.4): The socat command and port-forward now use `${remote_port}` variable:
```bash
# Line ~608: socat listens on remote_port inside pod
socat TCP-LISTEN:"${remote_port}",fork,reuseaddr TCP:"${db_host}":"${remote_port}"

# Line ~638: kubectl forwards local_port → remote_port
kubectl port-forward pod/"${pod_name}" "${local_port}":"${remote_port}"
```
Previously these were hardcoded to `5432`, which broke non-PostgreSQL services.

## Testing Architecture

### Test Structure (Modular Design)
Tests are split into multiple files for better organization and parallel execution in CI:

```
tests/
├── setup_common.bash                 # Shared setup, mocks, helpers
├── 01_argument_parsing_test.bats     # 16 tests - CLI args
├── 02_config_handling_test.bats      # 5 tests - Config loading
├── 03_subcommands_test.bats          # 11 tests - ls, help, etc.
├── 04_validation_test.bats           # 11 tests - Input validation
├── 05_port_configuration_test.bats   # 8 tests - Port settings
├── 06_connection_types_test.bats     # 12 tests - Connection types
├── 07_pod_name_generation_test.bats  # 4 tests - Pod naming
└── README.md                          # Test documentation
```

**Total: 67 tests across 7 files**

### Shared Test Setup
All test files source `setup_common.bash` which provides:
- `setup_test_environment()` - Creates temp dirs, mocks, config
- `teardown_test_environment()` - Cleans up test environment
- `run_plugin()` - Helper to run plugin with args
- Mock implementations: `yq`, `kubectl`, `kubectx`

### Mock Implementations
- **Mock `yq`**: Returns predefined values for config queries
- **Mock `kubectl`**: Records commands to `kubectl.log`, simulates pod lifecycle
- **Mock `kubectx`**: Records context switches to `kubectx.log`

### Test Categories
1. **Argument Parsing Tests** (01): Flag validation, error messages, short/long forms
2. **Config Handling Tests** (02): YAML validation, file loading, env vars
3. **Subcommand Tests** (03): `ls`, `edit-config`, `help`, `version`
4. **Validation Tests** (04): Environment/connection validation, error messages
5. **Port Configuration Tests** (05): local-port, remote-port, defaults, overrides
6. **Connection Type Tests** (06): Postgres, MySQL, Redis, MongoDB, custom types
7. **Pod Name Generation Tests** (07): Random suffix, mock verification

### Adding New Tests

#### Adding to existing test file:
```bash
@test "descriptive test name" {
    run_plugin --your-args
    [ "$status" -eq 0 ]           # Check exit code
    [[ "$output" =~ "expected" ]] # Check output contains text
}
```

#### Creating new test file:
1. Name: `0X_category_test.bats` (use next number)
2. Add header with `load setup_common` and setup/teardown
3. Add your tests
4. Update `tests/README.md` with new file description
5. Update `.github/workflows/ci.yml` matrix to include new file

### Running Tests
```bash
# All tests sequentially
make test

# Specific test file
bats tests/01_argument_parsing_test.bats

# Specific test by name
bats tests/01_argument_parsing_test.bats -f "shows help"

# Verbose output
bats tests/*.bats --verbose
```

### CI/CD Parallel Execution
GitHub Actions runs each test file as a separate job (7 jobs in parallel):
- Faster overall test execution (~3-4x speedup)
- Better isolation between test suites
- `fail-fast: false` to see all failures

## Code Style & Linting

### Shellcheck Configuration
See `.shellcheckrc` for project rules. Key points:
- Uses `bash` shell directive (not POSIX sh)
- Severity level: `style` (strictest)
- Disabled: SC1090, SC1091 (can't follow non-constant sources)

### Common Patterns
```bash
# Always use braces for variables
"${variable}" not "$variable"

# Separate declaration from command substitution to catch errors
local result
result=$(command)

# Use print_* functions for colored output
print_error "Error message"   # Red with ❌ ERROR: prefix
print_success "Success"        # Green with ✅ prefix
print_info "Information"       # Blue with 🔵 prefix
print_warning "Warning"        # Yellow with ⚠️  prefix
```

### Required Patterns
- **Always** start with `set -euo pipefail`
- **Always** quote variables: `"${var}"`
- **Always** use `local` for function variables
- Use `# shellcheck disable=SCXXXX` with explanation when intentionally breaking rules
- For BATS-provided variables, use: `# shellcheck disable=SC2154  # VAR is provided by BATS`

## Git Workflow

### Commit Message Format
Use structured prefixes for automatic CHANGELOG generation:
- `feat:` - New features
- `fix:` - Bug fixes
- `docs:` - Documentation changes
- `refactor:` - Code refactoring
- `test:` - Test updates
- `chore:` - Maintenance tasks

Examples:
- `feat: add support for custom TCP services`
- `fix: use remote-port variable instead of hardcoded 5432`
- `test: split test suite into modular files for parallel execution`

### Pre-commit Hook
Automatically runs `shellcheck` on staged shell scripts. Set up with `make setup-hooks`.

## Documentation Structure

- **README.md**: User-facing overview, quick start, requirements
- **docs/INSTALLATION.md**: Detailed installation, dependencies, troubleshooting
- **docs/USAGE.md**: Complete usage guide, examples, configuration reference
- **docs/DEVELOPMENT.md**: Dev setup, testing, CI/CD
- **CONTRIBUTING.md**: Contribution guidelines, code style, PR process
- **config/config.yaml.example**: Example config with extensive comments
- **tests/README.md**: Test suite documentation, structure, debugging

When changing command-line arguments or adding features, update ALL relevant documentation files.

## Release Process

Version is stored in two places:
1. `kubectl-tcp_tunnel`: `VERSION="${KUBECTL_TCP_TUNNEL_VERSION:-v2.0.3}"`
2. `install.sh`: `VERSION="2.0.3"`

Release command: `make release VERSION=2.0.4`
- Verifies on main branch, clean working directory, up-to-date with remote
- Updates version numbers
- Creates commit and git tag
- Push with: `git push origin main --tags`

GitHub Actions automatically creates the release with assets.

## Important Constraints

### Dependencies
The plugin requires these external tools (checked in code):
- `kubectl` (v1.20+)
- `kubectx`
- `yq` (v4+, used for YAML parsing)
- `bash` (v4.0+)

### Compatibility
- Tested on macOS and Linux (Ubuntu, Debian, Fedora)
- Uses `alpine/socat:latest` image for jump pods
- Jump pods must have network access to target services from within the cluster

### Security Considerations
- Never expose services directly - always through cluster network
- Jump pods are ephemeral (deleted on exit via trap handlers)
- Uses explicit context switching (kubectx) to prevent accidental operations
- Respects cluster network policies and RBAC

### Port Conflicts
**Kubernetes Side**: No conflicts possible
- Each pod has isolated networking
- No cluster-wide port bindings
- No Service objects created
- Multiple tunnels can run simultaneously without K8s conflicts

**Local Machine**: Conflicts possible
- Only one process can bind to `localhost:15432`
- Use `-p` flag to specify different local ports for simultaneous tunnels
- Example: `-p 15432` and `-p 15433` for two postgres tunnels

## Common Development Scenarios

### Adding a New Command-Line Argument
1. Add case in `main()` function (~line 654)
2. Add to `show_help()` OPTIONS section (~line 76)
3. Add usage examples in `show_help()` EXAMPLES section (~line 91)
4. Update error messages for missing args (~line 725)
5. Add tests in appropriate test file (e.g., `tests/01_argument_parsing_test.bats`)
6. Update docs: README.md, docs/USAGE.md, docs/INSTALLATION.md
7. Update config examples: config/config.yaml.example

### Adding a New Connection Type
1. Add type definition to `config/config.yaml.example` in settings section
2. Document the type in docs/USAGE.md (Adding Custom Connection Types)
3. Add test cases in `tests/06_connection_types_test.bats`
4. No code changes needed - types are config-driven via YAML anchors

### Changing Configuration Structure
Configuration parsing is centralized in `get_*()` functions (~line 211-262). When changing config structure:
1. Update yq queries in `get_*()` functions
2. Update `config/config.yaml.example` with new structure
3. Update mock yq in `tests/setup_common.bash` (~line 54-170)
4. Add migration guide section to docs/USAGE.md if breaking change
5. Update version and create appropriate release notes

### Adding a New Test Suite
1. Create `tests/0X_category_test.bats` with next sequential number
2. Add header:
   ```bash
   #!/usr/bin/env bats

   # Category Name Tests

   load setup_common

   setup() {
       setup_test_environment
   }

   teardown() {
       teardown_test_environment
   }
   ```
3. Write tests using `run_plugin` helper
4. Update `tests/README.md` with test count and description
5. Update `.github/workflows/ci.yml` matrix to include new file

## Recent Changes (v2.1.1)

### Pod Reuse with Hostname-Based Naming (v2.1.0)
- **Changed**: Pods now use hostname-based naming instead of random suffixes
- **Format**: `{connection-type}-tunnel-{hostname}` (e.g., `postgres-tunnel-johns-macbook`)
- **Behavior**: Pods are reused across connections for faster reconnection
- **Cleanup**: New `cleanup` subcommand to manually delete jump pods
- **Impact**: One pod per machine/connection type, no automatic deletion on exit

### Optional Auto-Cleanup Flag (v2.1.1)
- **Added**: `--cleanup` flag to optionally delete pod on exit (Ctrl+C)
- **Default**: Pods remain for reuse (backward compatible)
- **Usage**: `kubectl tcp-tunnel -e staging -c user-db --cleanup`
- **Impact**: Users can choose between pod reuse (default) or auto-cleanup

### Version-Specific Installation (v2.1.1)
- **Changed**: Install script now uses version-specific git tags instead of main branch
- **Benefit**: More reliable upgrades, no cache issues
- **Format**: `https://raw.githubusercontent.com/sgyyz/kubectl-tcp-tunnel/v{VERSION}/`
- **Fallback**: Falls back to main branch if version tag doesn't exist

## Recent Changes (v2.0.4)

### Port Configuration Fix
- **Fixed**: Hardcoded port `5432` in socat and kubectl port-forward
- **Changed**: Now uses `${remote_port}` variable from config
- **Impact**: Non-PostgreSQL services now work correctly

### Renamed db-port → remote-port
- **Rationale**: Better reflects support for any TCP service, not just databases
- **Breaking Change**: Config files must update `db-port:` to `remote-port:`
- **Function Renamed**: `get_connection_db_port()` → `get_connection_remote_port()`
- **Variable Renamed**: `db_port` → `remote_port` throughout codebase

### Test Suite Modularization
- **Changed**: Split single 1220-line test file into 7 focused files
- **Added**: `tests/setup_common.bash` for shared setup/mocks
- **Added**: `tests/README.md` for test documentation
- **Benefit**: Parallel execution in CI (~3-4x faster)
- **Benefit**: Better test organization and maintainability

### New Tests
- Added 5 remote-port configuration tests
- Total test count: 67 tests across 7 files

## Troubleshooting

### Tests Failing
```bash
# Run specific test with verbose output
bats tests/05_port_configuration_test.bats --verbose

# Check mock logs in test environment
# These are in $TEST_DIR during test execution
```

### Shellcheck Warnings in Test Files
- BATS variables (BATS_TEST_TMPDIR, BATS_TEST_DIRNAME) are provided at runtime
- Use: `# shellcheck disable=SC2154  # VAR is provided by BATS`

### Port Already in Use
```bash
# Check what's using the port
lsof -i :15432

# Use different local port
kubectl tcp-tunnel -e staging -c user-db -p 15433
```

### Jump Pod Won't Start
```bash
# Check pod status
kubectl get pods -n <namespace> | grep tunnel

# Check pod logs
kubectl logs <pod-name> -n <namespace>

# Check pod events
kubectl describe pod <pod-name> -n <namespace>
```
