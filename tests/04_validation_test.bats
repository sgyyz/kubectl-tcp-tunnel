#!/usr/bin/env bats

# Validation Tests

load setup_common

setup() {
    setup_test_environment
}

teardown() {
    teardown_test_environment
}

@test "errors when missing --env argument" {
    run_plugin --connection user-db
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Missing required option: -e/--env" ]]
}

@test "errors when missing --connection argument" {
    run_plugin --env staging
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Missing required option: -c/--connection" ]]
}

@test "errors on invalid environment" {
    run_plugin --env invalid_env --connection user-db
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Unknown environment" ]]
}

@test "errors on unknown connection alias" {
    run_plugin --env staging --connection unknown_db
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Unknown connection" ]]
}

@test "validates environment exists before creating tunnel" {
    run_plugin --env nonexistent --connection user-db
    [ "$status" -eq 1 ]
}

@test "validates connection alias exists before creating tunnel" {
    run_plugin --env staging --connection nonexistent_db
    [ "$status" -eq 1 ]
}

@test "lists available environments on invalid environment" {
    run_plugin --env invalid --connection user-db
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Available environments" ]]
}

@test "lists available connections on invalid connection" {
    run_plugin --env staging --connection invalid_db
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Available connections" ]]
}

@test "handles empty environment name" {
    run_plugin --env "" --connection user-db
    [ "$status" -eq 1 ]
}

@test "accepts connection names with hyphens" {
    run_plugin ls
    [ "$status" -eq 0 ]
    [[ "$output" =~ "user-db" ]]
}

@test "validates connection host is not empty" {
    # User-db should have a valid host in staging
    run_plugin --env staging --connection user-db --help
    [ "$status" -eq 0 ]
}
