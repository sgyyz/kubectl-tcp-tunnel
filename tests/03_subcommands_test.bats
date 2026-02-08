#!/usr/bin/env bats

# Subcommand Tests

load setup_common

setup() {
    setup_test_environment
}

teardown() {
    teardown_test_environment
}

@test "ls subcommand lists environments and connections" {
    run_plugin ls
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Available environments and connections" ]]
    [[ "$output" =~ "staging" ]]
    [[ "$output" =~ "production" ]]
}

@test "ls with environment filter" {
    run_plugin ls staging
    [ "$status" -eq 0 ]
    [[ "$output" =~ "staging" ]]
}

@test "ls shows kubernetes contexts" {
    run_plugin ls
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Kubernetes context:" ]]
    [[ "$output" =~ "staging-cluster" ]]
}

@test "lists connections correctly" {
    run_plugin ls staging
    [ "$status" -eq 0 ]
    [[ "$output" =~ "user-db" ]]
    [[ "$output" =~ "order-db" ]]
}

@test "edit-config subcommand works" {
    export EDITOR="echo"
    run_plugin edit-config
    [ "$status" -eq 0 ]
}

@test "upgrade subcommand shows in help" {
    run_plugin --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "upgrade" ]]
    [[ "$output" =~ "Upgrade to the latest version" ]]
}

@test "uninstall subcommand shows in help" {
    run_plugin --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "uninstall" ]]
    [[ "$output" =~ "Uninstall kubectl-tcp-tunnel" ]]
}

@test "help shows examples" {
    run_plugin --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "EXAMPLES:" ]]
}

@test "help shows subcommands" {
    run_plugin --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "SUBCOMMANDS:" ]]
    [[ "$output" =~ "ls" ]]
    [[ "$output" =~ "edit-config" ]]
}

@test "help shows configuration info" {
    run_plugin --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "CONFIGURATION:" ]]
}

@test "help shows environment variables" {
    run_plugin --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "ENVIRONMENT VARIABLES:" ]]
    [[ "$output" =~ "TCP_TUNNEL_CONFIG" ]]
}
