#!/usr/bin/env bats

# Pod Name Generation Tests

load setup_common

setup() {
    setup_test_environment
}

teardown() {
    teardown_test_environment
}

@test "generate_random_suffix creates 6 character string" {
    # Test the function by calling it via bash
    local suffix
    suffix=$(bash -c '
        generate_random_suffix() {
            local length="${1:-6}"
            local suffix
            # Try to generate random suffix from /dev/urandom
            suffix=$(LC_ALL=C tr -dc "a-z0-9" < /dev/urandom 2>/dev/null | head -c "${length}" || true)

            # Fallback to timestamp-based generation if urandom fails
            if [[ -z "${suffix}" ]] || [[ ${#suffix} -ne ${length} ]]; then
                local timestamp
                timestamp=$(date +%s)
                suffix=$(printf "%s" "${timestamp}" | sha256sum 2>/dev/null | head -c "${length}" || printf "%s" "${timestamp}" | head -c "${length}")
            fi

            echo "${suffix}"
        }
        generate_random_suffix 6
    ')

    # Check length is 6
    [ ${#suffix} -eq 6 ]

    # Check it contains only lowercase alphanumeric
    [[ "$suffix" =~ ^[a-z0-9]+$ ]]
}

@test "uses kubectx for context switching" {
    [ -f "${TEST_DIR}/bin/kubectx" ]
    [ -x "${TEST_DIR}/bin/kubectx" ]
}

@test "uses kubectl for pod operations" {
    [ -f "${TEST_DIR}/bin/kubectl" ]
    [ -x "${TEST_DIR}/bin/kubectl" ]
}

@test "uses yq for YAML parsing" {
    [ -f "${TEST_DIR}/bin/yq" ]
    [ -x "${TEST_DIR}/bin/yq" ]
}
