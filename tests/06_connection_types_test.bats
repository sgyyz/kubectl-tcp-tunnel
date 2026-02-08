#!/usr/bin/env bats

# Connection Type Tests

load setup_common

setup() {
    setup_test_environment
}

teardown() {
    teardown_test_environment
}

@test "get_connection_type extracts postgres type" {
    # Test connection type extraction via grep on config
    local result
    result=$(yq eval ".environments.staging.connections.user-db.type" "${CONFIG_FILE}" 2>/dev/null | grep -o '\*[a-z0-9_-]*' | sed 's/^\*//')

    [ "$result" = "postgres" ]
}

@test "get_connection_type extracts mysql type" {
    # Test connection type extraction via grep on config
    local result
    result=$(yq eval ".environments.staging.connections.order-db.type" "${CONFIG_FILE}" 2>/dev/null | grep -o '\*[a-z0-9_-]*' | sed 's/^\*//')

    [ "$result" = "mysql" ]
}

@test "get_connection_type returns empty for unknown connection" {
    # Test connection type extraction for non-existent connection
    local result
    result=$(yq eval ".environments.staging.connections.unknown-db.type" "${CONFIG_FILE}" 2>/dev/null | grep -o '\*[a-z0-9_-]*' | sed 's/^\*//' || echo "")

    [ -z "$result" ]
}

@test "handles postgres connection type correctly" {
    run_plugin ls staging
    [ "$status" -eq 0 ]
    [[ "$output" =~ "user-db" ]]
}

@test "handles mysql connection type correctly" {
    run_plugin ls staging
    [ "$status" -eq 0 ]
    [[ "$output" =~ "order-db" ]]
}

@test "supports multiple connection types in same environment" {
    run_plugin ls staging
    [ "$status" -eq 0 ]
    [[ "$output" =~ "user-db" ]]
    [[ "$output" =~ "order-db" ]]
}

@test "connection type is used for port configuration" {
    # Create config with explicit connection types
    cat > "${CONFIG_FILE}" <<EOF
settings:
  namespace: default
  postgres: &postgres
    local-port: 15432
    remote-port: 5432
  mysql: &mysql
    local-port: 13306
    remote-port: 3306

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
    "explode(.) | .environments.staging.connections.user-db.host") echo "postgres.example.com" ;;
    "explode(.) | .environments.staging.connections.order-db.host") echo "mysql.example.com" ;;
    "explode(.) | .environments.staging.connections.user-db.type.local-port") echo "15432" ;;
    "explode(.) | .environments.staging.connections.user-db.type.remote-port") echo "5432" ;;
    "explode(.) | .environments.staging.connections.order-db.type.local-port") echo "13306" ;;
    "explode(.) | .environments.staging.connections.order-db.type.remote-port") echo "3306" ;;
    ".environments | keys | .[]") echo "staging" ;;
    ".environments.staging.connections | keys | .[]")
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
}

@test "handles connection without type definition gracefully" {
    # Create config with connection but no type
    cat > "${CONFIG_FILE}" <<EOF
settings:
  namespace: default

environments:
  staging:
    k8s-context: staging-context
    connections:
      raw-service:
        host: service.example.com
EOF

    # Update mock yq to handle this case
    cat > "${TEST_DIR}/bin/yq" <<'EOSCRIPT'
#!/usr/bin/env bash
query="${2%% //*}"
case "$query" in
    ".") exit 0 ;;
    ".environments.staging.k8s-context") echo "staging-context" ;;
    ".environments.staging.connections.raw-service.type") echo "" ;;
    "explode(.) | .environments.staging.connections.raw-service.host") echo "service.example.com" ;;
    "explode(.) | .environments.staging.connections.raw-service.type.local-port") echo "" ;;
    "explode(.) | .environments.staging.connections.raw-service.type.remote-port") echo "" ;;
    ".environments | keys | .[]") echo "staging" ;;
    ".environments.staging.connections | keys | .[]") echo "raw-service" ;;
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

    # Should still list the connection even without type
    run_plugin ls staging
    [ "$status" -eq 0 ]
    [[ "$output" =~ "raw-service" ]]
}

@test "handles multiple postgres connections in same environment" {
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
        host: user-postgres.example.com
        type: *postgres
      analytics-db:
        host: analytics-postgres.example.com
        type: *postgres
      reports-db:
        host: reports-postgres.example.com
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
    ".environments.staging.connections.analytics-db.type") echo "*postgres" ;;
    ".environments.staging.connections.reports-db.type") echo "*postgres" ;;
    "explode(.) | .environments.staging.connections.user-db.host") echo "user-postgres.example.com" ;;
    "explode(.) | .environments.staging.connections.analytics-db.host") echo "analytics-postgres.example.com" ;;
    "explode(.) | .environments.staging.connections.reports-db.host") echo "reports-postgres.example.com" ;;
    ".environments | keys | .[]") echo "staging" ;;
    ".environments.staging.connections | keys | .[]")
        echo "analytics-db"
        echo "reports-db"
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
    [[ "$output" =~ "analytics-db" ]]
    [[ "$output" =~ "reports-db" ]]
}

@test "handles redis connection type" {
    cat > "${CONFIG_FILE}" <<EOF
settings:
  namespace: default
  redis: &redis
    local-port: 16379
    remote-port: 6379

environments:
  staging:
    k8s-context: staging-context
    connections:
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
    ".environments.staging.connections.cache.type") echo "*redis" ;;
    "explode(.) | .environments.staging.connections.cache.host") echo "redis.example.com" ;;
    "explode(.) | .environments.staging.connections.cache.type.local-port") echo "16379" ;;
    "explode(.) | .environments.staging.connections.cache.type.remote-port") echo "6379" ;;
    ".environments | keys | .[]") echo "staging" ;;
    ".environments.staging.connections | keys | .[]") echo "cache" ;;
    *) echo "" ;;
esac
exit 0
EOSCRIPT
    chmod +x "${TEST_DIR}/bin/yq"

    run_plugin ls staging
    [ "$status" -eq 0 ]
    [[ "$output" =~ "cache" ]]
}

@test "handles mongodb connection type" {
    cat > "${CONFIG_FILE}" <<EOF
settings:
  namespace: default
  mongodb: &mongodb
    local-port: 17017
    remote-port: 27017

environments:
  staging:
    k8s-context: staging-context
    connections:
      sessions:
        host: mongodb.example.com
        type: *mongodb
EOF

    # Update mock yq
    cat > "${TEST_DIR}/bin/yq" <<'EOSCRIPT'
#!/usr/bin/env bash
query="${2%% //*}"
case "$query" in
    ".") exit 0 ;;
    ".environments.staging.k8s-context") echo "staging-context" ;;
    ".environments.staging.connections.sessions.type") echo "*mongodb" ;;
    "explode(.) | .environments.staging.connections.sessions.host") echo "mongodb.example.com" ;;
    "explode(.) | .environments.staging.connections.sessions.type.local-port") echo "17017" ;;
    "explode(.) | .environments.staging.connections.sessions.type.remote-port") echo "27017" ;;
    ".environments | keys | .[]") echo "staging" ;;
    ".environments.staging.connections | keys | .[]") echo "sessions" ;;
    *) echo "" ;;
esac
exit 0
EOSCRIPT
    chmod +x "${TEST_DIR}/bin/yq"

    run_plugin ls staging
    [ "$status" -eq 0 ]
    [[ "$output" =~ "sessions" ]]
}

@test "handles custom connection type" {
    cat > "${CONFIG_FILE}" <<EOF
settings:
  namespace: default
  custom-api: &custom-api
    local-port: 18080
    remote-port: 8080

environments:
  staging:
    k8s-context: staging-context
    connections:
      internal-api:
        host: api.example.com
        type: *custom-api
EOF

    # Update mock yq
    cat > "${TEST_DIR}/bin/yq" <<'EOSCRIPT'
#!/usr/bin/env bash
query="${2%% //*}"
case "$query" in
    ".") exit 0 ;;
    ".environments.staging.k8s-context") echo "staging-context" ;;
    ".environments.staging.connections.internal-api.type") echo "*custom-api" ;;
    "explode(.) | .environments.staging.connections.internal-api.host") echo "api.example.com" ;;
    "explode(.) | .environments.staging.connections.internal-api.type.local-port") echo "18080" ;;
    "explode(.) | .environments.staging.connections.internal-api.type.remote-port") echo "8080" ;;
    ".environments | keys | .[]") echo "staging" ;;
    ".environments.staging.connections | keys | .[]") echo "internal-api" ;;
    *) echo "" ;;
esac
exit 0
EOSCRIPT
    chmod +x "${TEST_DIR}/bin/yq"

    run_plugin ls staging
    [ "$status" -eq 0 ]
    [[ "$output" =~ "internal-api" ]]
}
