#!/usr/bin/env bats

# Configuration Handling Tests

load setup_common

setup() {
    setup_test_environment
}

teardown() {
    teardown_test_environment
}

@test "errors when config file missing" {
    rm -f "${CONFIG_FILE}"
    run_plugin ls
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Configuration file not found" ]]
}

@test "respects TCP_TUNNEL_CONFIG environment variable" {
    export TCP_TUNNEL_CONFIG="${CONFIG_FILE}"
    run_plugin ls
    [ "$status" -eq 0 ]
}

@test "loads config successfully" {
    run_plugin ls
    [ "$status" -eq 0 ]
}

@test "errors on invalid YAML syntax" {
    # Create invalid YAML
    cat > "${CONFIG_FILE}" <<EOF
invalid: yaml: syntax:
  - bad indentation
EOF

    # Update mock yq to fail on invalid YAML
    cat > "${TEST_DIR}/bin/yq" <<'EOSCRIPT'
#!/usr/bin/env bash
if [[ "$2" == "." ]]; then
    exit 1  # Invalid YAML
fi
EOSCRIPT
    chmod +x "${TEST_DIR}/bin/yq"

    run_plugin ls
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Invalid YAML syntax" ]]
}

@test "provides helpful error for missing config" {
    rm -f "${CONFIG_FILE}"
    run_plugin ls
    [ "$status" -eq 1 ]
    [[ "$output" =~ "config.yaml.example" ]]
}
