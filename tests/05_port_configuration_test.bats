#!/usr/bin/env bats

# Port Configuration Tests

load setup_common

setup() {
    setup_test_environment
}

teardown() {
    teardown_test_environment
}

@test "supports --local-port flag" {
    run_plugin --env staging --connection user-db --local-port 5433 --help
    [ "$status" -eq 0 ]
}

@test "reads local-port from connection type when flag not provided" {
    # Create config with connection type
    cat > "${CONFIG_FILE}" <<EOF
settings:
  namespace: default
  postgres: &postgres
    local-port: 15432
    remote-port: 5432

environments:
  staging:
    k8s-context: staging-context
    connections:
      user-db:
        host: postgres-staging.example.com
        type: *postgres
EOF

    # Update mock yq to handle this config
    cat > "${TEST_DIR}/bin/yq" <<'EOSCRIPT'
#!/usr/bin/env bash
query="${2%% //*}"
case "$query" in
    ".") exit 0 ;;
    ".environments.staging.k8s-context") echo "staging-context" ;;
    "explode(.) | .environments.staging.connections.user-db.host") echo "postgres-staging.example.com" ;;
    "explode(.) | .environments.staging.connections.user-db.type.local-port") echo "15432" ;;
    "explode(.) | .environments.staging.connections.user-db.type.remote-port") echo "5432" ;;
    *) echo "" ;;
esac
exit 0
EOSCRIPT
    chmod +x "${TEST_DIR}/bin/yq"

    # Run plugin and check that it reads local-port from connection type
    run_plugin --env staging --connection user-db --help
    [ "$status" -eq 0 ]
}

@test "--local-port flag overrides connection type setting" {
    # Create config with connection type port
    cat > "${CONFIG_FILE}" <<EOF
settings:
  namespace: default
  postgres: &postgres
    local-port: 15432
    remote-port: 5432

environments:
  staging:
    k8s-context: staging-context
    connections:
      user-db:
        host: postgres-staging.example.com
        type: *postgres
EOF

    # Flag should override connection type
    run_plugin --env staging --connection user-db --local-port 9999 --help
    [ "$status" -eq 0 ]
}

@test "reads remote-port from connection type for postgres" {
    cat > "${CONFIG_FILE}" <<EOF
settings:
  namespace: default
  postgres: &postgres
    local-port: 15432
    remote-port: 5432

environments:
  staging:
    k8s-context: staging-context
    connections:
      user-db:
        host: postgres.example.com
        type: *postgres
EOF

    # Update mock yq
    cat > "${TEST_DIR}/bin/yq" <<'EOSCRIPT'
#!/usr/bin/env bash
query="${2%% //*}"
case "$query" in
    ".") exit 0 ;;
    ".environments.staging.k8s-context") echo "staging-context" ;;
    ".environments.staging.connections.user-db.type") echo "*postgres" ;;
    "explode(.) | .environments.staging.connections.user-db.host") echo "postgres.example.com" ;;
    "explode(.) | .environments.staging.connections.user-db.type.local-port") echo "15432" ;;
    "explode(.) | .environments.staging.connections.user-db.type.remote-port") echo "5432" ;;
    ".environments | keys | .[]") echo "staging" ;;
    ".environments.staging.connections | keys | .[]") echo "user-db" ;;
    *) echo "" ;;
esac
exit 0
EOSCRIPT
    chmod +x "${TEST_DIR}/bin/yq"

    run_plugin ls staging
    [ "$status" -eq 0 ]
    [[ "$output" =~ "user-db" ]]
}

@test "reads remote-port from connection type for mysql" {
    cat > "${CONFIG_FILE}" <<EOF
settings:
  namespace: default
  mysql: &mysql
    local-port: 13306
    remote-port: 3306

environments:
  staging:
    k8s-context: staging-context
    connections:
      order-db:
        host: mysql.example.com
        type: *mysql
EOF

    # Update mock yq
    cat > "${TEST_DIR}/bin/yq" <<'EOSCRIPT'
#!/usr/bin/env bash
query="${2%% //*}"
case "$query" in
    ".") exit 0 ;;
    ".environments.staging.k8s-context") echo "staging-context" ;;
    ".environments.staging.connections.order-db.type") echo "*mysql" ;;
    "explode(.) | .environments.staging.connections.order-db.host") echo "mysql.example.com" ;;
    "explode(.) | .environments.staging.connections.order-db.type.local-port") echo "13306" ;;
    "explode(.) | .environments.staging.connections.order-db.type.remote-port") echo "3306" ;;
    ".environments | keys | .[]") echo "staging" ;;
    ".environments.staging.connections | keys | .[]") echo "order-db" ;;
    *) echo "" ;;
esac
exit 0
EOSCRIPT
    chmod +x "${TEST_DIR}/bin/yq"

    run_plugin ls staging
    [ "$status" -eq 0 ]
    [[ "$output" =~ "order-db" ]]
}

@test "reads remote-port from connection type for custom port" {
    cat > "${CONFIG_FILE}" <<EOF
settings:
  namespace: default
  custom-service: &custom-service
    local-port: 18888
    remote-port: 9999

environments:
  staging:
    k8s-context: staging-context
    connections:
      api:
        host: api.example.com
        type: *custom-service
EOF

    # Update mock yq
    cat > "${TEST_DIR}/bin/yq" <<'EOSCRIPT'
#!/usr/bin/env bash
query="${2%% //*}"
case "$query" in
    ".") exit 0 ;;
    ".environments.staging.k8s-context") echo "staging-context" ;;
    ".environments.staging.connections.api.type") echo "*custom-service" ;;
    "explode(.) | .environments.staging.connections.api.host") echo "api.example.com" ;;
    "explode(.) | .environments.staging.connections.api.type.local-port") echo "18888" ;;
    "explode(.) | .environments.staging.connections.api.type.remote-port") echo "9999" ;;
    ".environments | keys | .[]") echo "staging" ;;
    ".environments.staging.connections | keys | .[]") echo "api" ;;
    *) echo "" ;;
esac
exit 0
EOSCRIPT
    chmod +x "${TEST_DIR}/bin/yq"

    run_plugin ls staging
    [ "$status" -eq 0 ]
    [[ "$output" =~ "api" ]]
}

@test "falls back to default remote-port when not in connection type" {
    cat > "${CONFIG_FILE}" <<EOF
settings:
  namespace: default
  remote-port: 5432

environments:
  staging:
    k8s-context: staging-context
    connections:
      raw-db:
        host: db.example.com
EOF

    # Update mock yq
    cat > "${TEST_DIR}/bin/yq" <<'EOSCRIPT'
#!/usr/bin/env bash
query="${2%% //*}"
case "$query" in
    ".") exit 0 ;;
    ".environments.staging.k8s-context") echo "staging-context" ;;
    ".environments.staging.connections.raw-db.type") echo "" ;;
    "explode(.) | .environments.staging.connections.raw-db.host") echo "db.example.com" ;;
    "explode(.) | .environments.staging.connections.raw-db.type.local-port") echo "" ;;
    "explode(.) | .environments.staging.connections.raw-db.type.remote-port") echo "" ;;
    ".environments | keys | .[]") echo "staging" ;;
    ".environments.staging.connections | keys | .[]") echo "raw-db" ;;
    ".settings.namespace") echo "default" ;;
    ".settings.jump-pod-image") echo "alpine/socat:latest" ;;
    ".settings.jump-pod-wait-timeout") echo "60" ;;
    ".settings.local-port") echo "5432" ;;
    ".settings.remote-port") echo "5432" ;;
    *) echo "" ;;
esac
exit 0
EOSCRIPT
    chmod +x "${TEST_DIR}/bin/yq"

    run_plugin ls staging
    [ "$status" -eq 0 ]
    [[ "$output" =~ "raw-db" ]]
}

@test "handles different remote-port per connection type" {
    cat > "${CONFIG_FILE}" <<EOF
settings:
  namespace: default
  postgres: &postgres
    local-port: 15432
    remote-port: 5432
  mysql: &mysql
    local-port: 13306
    remote-port: 3306
  redis: &redis
    local-port: 16379
    remote-port: 6379

environments:
  staging:
    k8s-context: staging-context
    connections:
      user-db:
        host: postgres.example.com
        type: *postgres
      order-db:
        host: mysql.example.com
        type: *mysql
      cache:
        host: redis.example.com
        type: *redis
EOF

    # Update mock yq
    cat > "${TEST_DIR}/bin/yq" <<'EOSCRIPT'
#!/usr/bin/env bash
query="${2%% //*}"
case "$query" in
    ".") exit 0 ;;
    ".environments.staging.k8s-context") echo "staging-context" ;;
    ".environments.staging.connections.user-db.type") echo "*postgres" ;;
    ".environments.staging.connections.order-db.type") echo "*mysql" ;;
    ".environments.staging.connections.cache.type") echo "*redis" ;;
    "explode(.) | .environments.staging.connections.user-db.host") echo "postgres.example.com" ;;
    "explode(.) | .environments.staging.connections.order-db.host") echo "mysql.example.com" ;;
    "explode(.) | .environments.staging.connections.cache.host") echo "redis.example.com" ;;
    "explode(.) | .environments.staging.connections.user-db.type.local-port") echo "15432" ;;
    "explode(.) | .environments.staging.connections.user-db.type.remote-port") echo "5432" ;;
    "explode(.) | .environments.staging.connections.order-db.type.local-port") echo "13306" ;;
    "explode(.) | .environments.staging.connections.order-db.type.remote-port") echo "3306" ;;
    "explode(.) | .environments.staging.connections.cache.type.local-port") echo "16379" ;;
    "explode(.) | .environments.staging.connections.cache.type.remote-port") echo "6379" ;;
    ".environments | keys | .[]") echo "staging" ;;
    ".environments.staging.connections | keys | .[]")
        echo "cache"
        echo "order-db"
        echo "user-db"
        ;;
    *) echo "" ;;
esac
exit 0
EOSCRIPT
    chmod +x "${TEST_DIR}/bin/yq"

    run_plugin ls staging
    [ "$status" -eq 0 ]
    [[ "$output" =~ "user-db" ]]
    [[ "$output" =~ "order-db" ]]
    [[ "$output" =~ "cache" ]]
}
