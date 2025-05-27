#!/bin/bash

set -euo pipefail  # Strict error handling

# Secure file creation by default
umask 077

# Default Configuration
readonly DEFAULT_CONFIG_FILE="${HOME}/.pg_setup_config"
readonly LOG_FILE="/tmp/pg_setup_$(date +%Y%m%d_%H%M%S).log"
readonly MIN_PASSWORD_LENGTH=12
readonly CREDENTIALS_DIR="${HOME}/.pg_credentials"
# readonly CREDENTIALS_FILE="${CREDENTIALS_DIR}/${DB_USER:-ecommerce_user}.conf"

# Detect GPG recipient from available keys or create one
detect_or_create_gpg_recipient() {
    local keys
    # Use sort -u to remove duplicates
    keys=$(gpg --list-keys --with-colons | grep '^uid:' | cut -d: -f10 | sort -u)

    if [[ -z "$keys" ]]; then
        log_message "INFO" "🔐" "Aucune clé GPG trouvée. Création d'une nouvelle clé..."
        gpg --full-generate-key
        keys=$(gpg --list-keys --with-colons | grep '^uid:' | cut -d: -f10 | sort -u)
        if [[ -z "$keys" ]]; then
            log_message "ERROR" "❌" "Impossible de créer une clé GPG. Abandon."
            exit 1
        fi
    fi

    if [[ $(echo "$keys" | wc -l) -eq 1 ]]; then
        GPG_RECIPIENT="$keys"
        log_message "INFO" "🔑" "Clé GPG détectée : $GPG_RECIPIENT"
    else
        echo "Clés GPG disponibles :"
        select key in $keys; do
            if [[ -n "$key" ]]; then
                GPG_RECIPIENT="$key"
                break
            else
                echo "Choix invalide. Réessayez."
            fi
        done
        log_message "INFO" "🔑" "Clé GPG sélectionnée : $GPG_RECIPIENT"
    fi
}

# Sanitize input to allow only safe characters (alphanumeric and underscore)
sanitize_identifier() {
    local input="$1"
    # Only allow alphanumeric and underscore, and must not be empty
    if [[ -z "$input" || ! "$input" =~ ^[a-zA-Z0-9_]+$ ]]; then
        log_message "ERROR" "❌" "Invalid identifier: $input. Only non-empty alphanumeric and underscore allowed."
        exit 1
    fi
    # No echo, just validation. Use the original variable after calling this function.
}

# DRY: Assign and validate identifier in one step (short, pure Bash)
assign_sanitized_identifier() {
    [[ -z "$1" || ! "$1" =~ ^[a-zA-Z0-9_]+$ ]] && { log_message ERROR "❌" "Invalid identifier: $1. Only non-empty alphanumeric and underscore allowed."; exit 1; }
    printf -v "$2" '%s' "$1"
}

# DRY: Encrypt a string with GPG (short, pure Bash)
encrypt_with_gpg() { printf %s "$1" | gpg --batch --yes --encrypt --recipient "$2" -o "$3" && chmod 600 "$3"; }

# DRY: Decrypt a GPG-encrypted file (short, pure Bash)
decrypt_with_gpg() { gpg --quiet --decrypt "$1" 2>/dev/null; }

# DRY: Generalized check for existence and creation (dir/file)
ensure_exists() {
    [[ $1 == dir && ! -d $2 ]] && { sudo mkdir -p "$2"; [[ $3 ]] && sudo chown "$3" "$2"; [[ $4 ]] && chmod "$4" "$2"; }
    [[ $1 == file && ! -f $2 ]] && { touch "$2"; [[ $4 ]] && chmod "$4" "$2"; }
}

# Set restrictive permissions on the log file (DRY)
ensure_exists file "${LOG_FILE}" "" 600

# Enhanced logging function with colored levels
log_message() {
    local level="${1:-INFO}"  # Default to INFO if level not provided
    local icon="${2:-ℹ️}"     # Default to info icon if not provided
    local message="${3:-}"    # Empty string if no message provided

    if [[ -z "${message}" && -n "${icon}" ]]; then
        # If only two parameters provided, assume icon and message
        message="${icon}"
        icon="ℹ️"
    elif [[ -z "${message}" ]]; then
        # If only one parameter provided, assume it's the message
        message="${level}"
        level="INFO"
        icon="ℹ️"
    fi

    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local color_reset="\033[0m"
    local color_info="\033[0;32m"   # Green
    local color_error="\033[0;31m"  # Red
    local color=""

    case "$level" in
        INFO)
            color="$color_info" ;;
        ERROR)
            color="$color_error" ;;
        *)
            color="$color_reset" ;;
    esac

    # Never log passwords or secrets
    if [[ "$message" =~ (password|mot de passe|secret|PGPASSWORD|DB_PASSWORD|credentials) ]]; then
        printf "%b%s %s [%s] [REDACTED SENSITIVE INFO]%b\n" "$color" "$timestamp" "$icon" "$level" "$color_reset" | tee -a "${LOG_FILE}"
        return
    fi
    printf "%b%s %s [%s] %s%b\n" "$color" "$timestamp" "$icon" "$level" "$message" "$color_reset" | tee -a "${LOG_FILE}"
}

# Error handling function
handle_error() {
    local exit_code=$?
    local line_number=$1
    log_message "ERROR" "❌" "Failed at line ${line_number} with exit code ${exit_code}"
    cleanup
    exit 1
}

# Create a test table, insert sample data, print it, then drop the table
test_ecommerce_table() {
    local table_name="ecommerce_table_test"
    # Check if the database exists before proceeding
    if ! psql_object_exists db "${DB_NAME}"; then
        log_message "ERROR" "❌" "Database '${DB_NAME}' does not exist. Skipping test table creation."
        return
    fi
    log_message "INFO" "🧪" "Creating test table '$table_name' in database '${DB_NAME}'..."
    exec_psql "CREATE TABLE IF NOT EXISTS $table_name (id SERIAL PRIMARY KEY, name TEXT, price NUMERIC);" "${DB_NAME}"
    exec_psql "INSERT INTO $table_name (name, price) VALUES ('Sample Product', 19.99), ('Another Product', 29.99);" "${DB_NAME}"
    log_message "INFO" "📋" "Contents of '$table_name':"
    $PG_CONNECTION -d "${DB_NAME}" -c "SELECT * FROM $table_name;"
    log_message "INFO" "🗑️" "Dropping test table '$table_name'..."
    exec_psql "DROP TABLE IF EXISTS $table_name;" "${DB_NAME}"
}

# Cleanup function
cleanup() {
    log_message "INFO" "🧹" "Performing cleanup..."
    # Print all database specifics using dedicated functions
    print_users || log_message "ERROR" "❌" "Failed to print users."
    print_databases || log_message "ERROR" "❌" "Failed to print databases."
    print_tablespaces || log_message "ERROR" "❌" "Failed to print tablespaces."
    print_tables || log_message "ERROR" "❌" "Failed to print tables."
    test_ecommerce_table
    echo
    echo "==== Done. Exiting. ===="
}

# Centralized command check helper
require_commands() {
    local missing=()
    for cmd in "$@"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done
    if (( ${#missing[@]} > 0 )); then
        echo "[FATAL] Required command(s) not found: ${missing[*]}. Please install before running this script." >&2
        exit 1
    fi
}

# Centralized path resolution helper (portable)
resolve_path() {
    local path="$1"
    if command -v grealpath >/dev/null 2>&1; then
        grealpath "$path"
    elif command -v realpath >/dev/null 2>&1; then
        realpath "$path"
    else
        cd "$(dirname "$path")" && pwd && cd - >/dev/null 2>&1
    fi
}

# Centralized password prompt/validation
prompt_for_password() {
    local password password2
    while true; do
        read -s -p "Enter password for new role '$1': " password
        echo
        read -s -p "Confirm password: " password2
        echo
        if [[ "$password" != "$password2" ]]; then
            echo "Passwords do not match. Try again."
            continue
        fi
        if ! validate_password "$password"; then
            echo "Password does not meet security requirements. Try again."
            continue
        fi
        break
    done
    echo "$password"
}

# Set up error handling
trap 'handle_error ${LINENO}' ERR

# Use centralized command check
require_commands gpg shuf fold head psql brew realpath
# Check for GPG key for the recipient before any DB operations
detect_or_create_gpg_recipient

if ! gpg --list-keys "$GPG_RECIPIENT" | grep -q '^pub'; then
    log_message "ERROR" "❌" "No GPG key found for recipient '$GPG_RECIPIENT'. Please ensure your GPG key is available."
    echo "[FATAL] No GPG key found for recipient '$GPG_RECIPIENT'."
    exit 1
fi

# Enhanced PostgreSQL installation check
check_postgresql_installation() {
    local PSQL_BIN
    PSQL_BIN=$(which psql 2>/dev/null || echo "")
    
    if [[ -z "${PSQL_BIN}" ]]; then
        log_message "ERROR" "❌" "PostgreSQL is not installed or not in PATH"
        exit 1
    fi

    # Version check with proper error handling
    if ! PG_VERSION=$("${PSQL_BIN}" --version | grep -oE '[0-9]+' | head -n 1); then
        log_message "ERROR" "❌" "Failed to determine PostgreSQL version"
        exit 1
    fi

    PG_SERVICE_NAME="postgresql@${PG_VERSION}"
    PG_CONNECTION="${PSQL_BIN} -U ${PG_SUPERUSER}"

    log_message "INFO" "🔍" "PostgreSQL version: ${PG_VERSION}"
    log_message "INFO" "📍" "psql binary: ${PSQL_BIN}"
}

# Generalized service management function (start, stop, status)
manage_service() {
    local action="$1"; shift
    local service_name="${1:-$PG_SERVICE_NAME}"
    case "$action" in
        start)
            log_message "INFO" "🚀" "Démarrage du service $service_name..."
            brew services start "$service_name" ;;
        stop)
            log_message "INFO" "🛑" "Arrêt du service $service_name..."
            brew services stop "$service_name" ;;
        status)
            brew services list | grep "$service_name" | grep started >/dev/null
            return $? ;;
        *)
            log_message "ERROR" "❌" "Action inconnue pour manage_service: $action" ;;
    esac
}

# Generalized SQL command executor with error handling and logging (short)
exec_psql() { $PG_CONNECTION -d "${2:-postgres}" -c "$1" || fail "SQL execution failed: $1"; }

# DRY: Check if a SQL query returns any rows (used for existence checks)
psql_exists() {
    $PG_CONNECTION -tAc "$1" | grep -q 1
}

# Generalized existence check for SQL objects (role, db, tablespace) (short)
psql_object_exists() {
    case $1 in
        role) psql_exists "SELECT 1 FROM pg_roles WHERE rolname='$2'" ;;
        db) psql_exists "SELECT 1 FROM pg_database WHERE datname='$2'" ;;
        tablespace) psql_exists "SELECT 1 FROM pg_tablespace WHERE spcname='$2'" ;;
        *) fail "Unknown object type for existence check: $1" ;;
    esac
}

# DRY: Create object if not exists (role, db, tablespace) (short)
create_if_not_exists() {
    assign_sanitized_identifier "$2" safe_name
    local connect_db="${4:-postgres}"
    if psql_object_exists "$1" "$safe_name"; then
        log_message INFO "ℹ️" "$1 '$safe_name' already exists. (checked in $connect_db)"
        return 0
    else
        log_message INFO "ℹ️" "$1 '$safe_name' does not exist. Creating in $connect_db..."
    fi
    local sql_cmd output status
    case $1 in
        role)
            sql_cmd="CREATE ROLE $safe_name WITH LOGIN PASSWORD '$3';"
            log_message INFO "📝" "Running SQL: $sql_cmd (in $connect_db)"
            output=$(exec_psql "$sql_cmd" "$connect_db" 2>&1) || { log_message ERROR "❌" "Failed to create role $safe_name: $output"; exit 1; }
            sql_cmd="ALTER ROLE $safe_name WITH NOSUPERUSER NOCREATEDB NOCREATEROLE;"
            log_message INFO "📝" "Running SQL: $sql_cmd (in $connect_db)"
            output=$(exec_psql "$sql_cmd" "$connect_db" 2>&1) || { log_message ERROR "❌" "Failed to alter role $safe_name: $output"; exit 1; }
            log_message INFO "✅" "Role '$safe_name' created successfully" ;;
        db)
            sql_cmd="CREATE DATABASE $safe_name OWNER $3;"
            log_message INFO "📝" "Running SQL: $sql_cmd (in $connect_db)"
            output=$(exec_psql "$sql_cmd" "$connect_db" 2>&1) || { log_message ERROR "❌" "Failed to create database $safe_name: $output"; exit 1; }
            # Immediately check for existence
            if ! psql_object_exists db "$safe_name"; then
                log_message ERROR "❌" "Database '$safe_name' still does not exist after creation attempt. FATAL."
                exit 1
            fi
            log_message INFO "✅" "Database '$safe_name' created successfully" ;;
        tablespace)
            sql_cmd="CREATE TABLESPACE $safe_name LOCATION '$3';"
            log_message INFO "📝" "Running SQL: $sql_cmd (in $connect_db)"
            output=$(exec_psql "$sql_cmd" "$connect_db" 2>&1) || { log_message ERROR "❌" "Failed to create tablespace $safe_name: $output"; exit 1; }
            log_message INFO "✅" "Tablespace '$safe_name' created successfully" ;;
        *) fail "Unknown object type for creation: $1" ;;
    esac
}

# Function to ensure PostgreSQL service is running
ensure_service_running() {
    log_message "INFO" "🧪" "Vérification que le service $PG_SERVICE_NAME est actif..."
    if ! manage_service status "$PG_SERVICE_NAME"; then
        manage_service start "$PG_SERVICE_NAME"
    else
        log_message "INFO" "✅" "Service $PG_SERVICE_NAME déjà actif."
    fi
}

# Function to verify superuser connection (connects to 'postgres' DB, not target DB)
verify_superuser() {
    log_message "INFO" "🔐" "Vérification des droits du superutilisateur PostgreSQL ($PG_SUPERUSER)..."
    if ! $PG_CONNECTION -d postgres -c "\\q"; then
        fail "Impossible de se connecter à PostgreSQL avec '$PG_SUPERUSER'. Conseil : Créez le rôle ou utilisez un rôle existant avec les bons droits."
    fi
}

# Refactored setup_tablespace using create_if_not_exists
setup_tablespace() {
    log_message "INFO" "📁" "Setting up tablespace..."
    local ts_name resolved_path

    # Validate tablespace name
    assign_sanitized_identifier "${TABLESPACE_NAME}" ts_name
    
    # Ensure base directory exists with proper permissions
    local base_dir="/Users/Shared/pgsql_tablespaces"
    if ! sudo mkdir -p "$base_dir" 2>/dev/null; then
        fail "Failed to create base tablespace directory: $base_dir"
    fi
    
    # Set proper ownership and permissions on base directory
    if ! sudo chown "$(whoami):staff" "$base_dir" 2>/dev/null || ! sudo chmod 755 "$base_dir" 2>/dev/null; then
        fail "Failed to set permissions on $base_dir"
    fi
    
    # Setup tablespace directory
    resolved_path="${base_dir}/${ts_name}"
    if [[ ! "$resolved_path" =~ ^/Users/Shared/pgsql_tablespaces/[a-zA-Z0-9_]+$ ]]; then
        fail "Invalid tablespace path: ${resolved_path}. Must be under /Users/Shared/pgsql_tablespaces/ with alphanumeric name"
    fi
    
    # Create and secure tablespace directory
    ensure_exists dir "$resolved_path" "$(whoami)" 700
    
    # Create tablespace in PostgreSQL
    if ! create_if_not_exists tablespace "$ts_name" "$resolved_path"; then
        fail "Failed to create tablespace $ts_name"
    fi
    
    return 0
}

# Refactored create_role using create_if_not_exists
create_role() {
    log_message "INFO" "👤" "Verifying or creating role '${DB_USER}'..."
    local db_user_safe password
    assign_sanitized_identifier "${DB_USER}" db_user_safe
    if [[ -z "${DB_PASSWORD}" ]]; then
        password=$(prompt_for_password "$db_user_safe")
        log_message "INFO" "🔑" "Password for ${db_user_safe} set via prompt."
    else
        password="${DB_PASSWORD}"
    fi
    validate_password "${password}" || fail "Password does not meet security requirements"
    # Always connect to 'postgres' DB for role creation
    create_if_not_exists role "$db_user_safe" "$password" "postgres"
    store_credentials "$db_user_safe" "$password"
    export PGPASSWORD="${password}"
}

# Refactored create_database using create_if_not_exists
create_database() {
    log_message "INFO" "🗂 " "Creating or verifying database '${DB_NAME}'..."
    local db_name_safe db_user_safe ts_name_safe
    
    # Sanitize all identifiers
    assign_sanitized_identifier "${DB_NAME}" db_name_safe
    assign_sanitized_identifier "${DB_USER}" db_user_safe
    assign_sanitized_identifier "${TABLESPACE_NAME}" ts_name_safe
    
    # Check if database already exists
    if psql_object_exists db "$db_name_safe"; then
        log_message "INFO" "✅" "Database '$db_name_safe' already exists."
        # Verify owner and tablespace
        local current_owner=$($PG_CONNECTION -tAc "SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname='$db_name_safe'")
        if [[ "$current_owner" != "$db_user_safe" ]]; then
            log_message "INFO" "🔄" "Updating database owner to '$db_user_safe'..."
            exec_psql "ALTER DATABASE $db_name_safe OWNER TO $db_user_safe;" postgres
        fi
    else
        # Create database with proper tablespace
        log_message "INFO" "🛠️" "Creating database '$db_name_safe'..."
        exec_psql "CREATE DATABASE $db_name_safe OWNER $db_user_safe TABLESPACE $ts_name_safe;" postgres
        
        # Verify creation
        if ! psql_object_exists db "$db_name_safe"; then
            fail "Failed to create database '$db_name_safe'"
        fi
    fi
    
    # Grant proper permissions
    exec_psql "REVOKE ALL ON DATABASE $db_name_safe FROM PUBLIC;" postgres
    exec_psql "GRANT ALL PRIVILEGES ON DATABASE $db_name_safe TO $db_user_safe;" postgres
    
    log_message "INFO" "✅" "Database '$db_name_safe' setup completed successfully"
    return 0
}

# DRY: Generalized log and exit on error
fail() { log_message "ERROR" "❌" "$1"; exit 1; }

# Function to securely store credentials (fully rewritten, secure, robust)
store_credentials() {
    local user password credentials_file
    user="${1:?user required}"
    password="${2:?password required}"
    credentials_file="${CREDENTIALS_DIR}/${user}.conf.gpg"
    ensure_exists dir "${CREDENTIALS_DIR}" "" 700
    encrypt_with_gpg "$password" "$GPG_RECIPIENT" "$credentials_file"
    log_message "INFO" "🔒" "Credentials stored securely in $credentials_file"
}

# Function to retrieve stored credentials
get_stored_credentials() {
    local user credentials_file
    user="${1:?user required}"
    credentials_file="${CREDENTIALS_DIR}/${user}.conf"
    if [[ -f "${credentials_file}.gpg" ]]; then
        decrypt_with_gpg "${credentials_file}.gpg"
    else
        return 1
    fi
}

# Function to validate password strength
validate_password() {
    local password="$1"
    [[ ${#password} -lt ${MIN_PASSWORD_LENGTH} ]] && return 1
    [[ "$password" =~ [A-Z] ]] || return 1
    [[ "$password" =~ [a-z] ]] || return 1
    [[ "$password" =~ [0-9] ]] || return 1
    [[ "$password" =~ [\!@#\$%\^\&\*] ]] || return 1
    return 0
}

# Print all PostgreSQL databases
print_databases() {
    log_message "INFO" "📚" "Listing all databases..."
    $PG_CONNECTION -d postgres -c "\l"
}

# Print all PostgreSQL tablespaces
print_tablespaces() {
    log_message "INFO" "📦" "Listing all tablespaces..."
    $PG_CONNECTION -d postgres -c "\db"
}

# Print all PostgreSQL users (roles)
print_users() {
    log_message "INFO" "👥" "Listing all users (roles)..."
    $PG_CONNECTION -d postgres -c "\du"
}

# Print all tables in the current database (only if DB exists)
print_tables() {
    log_message "INFO" "📄" "Listing all tables in database '${DB_NAME}'..."
    if psql_object_exists db "${DB_NAME}"; then
        $PG_CONNECTION -d "${DB_NAME}" -c "\dt"
    else
        log_message "ERROR" "❌" "Database '${DB_NAME}' does not exist. Skipping table listing."
    fi
}

# Enhanced main function with proper initialization
main() {
    log_message "INFO" "🚀" "Starting database setup script..."
    
    load_configuration
    check_postgresql_installation
    ensure_service_running
    verify_superuser
    
    # Create components in correct order with proper error handling
    if create_role; then
        if setup_tablespace; then
            if create_database; then
                log_message "INFO" "🎉" "Database setup completed successfully"
            else
                fail "Failed to create database ${DB_NAME}"
            fi
        else
            fail "Failed to setup tablespace ${TABLESPACE_NAME}"
        fi
    else
        fail "Failed to create role ${DB_USER}"
    fi
}

# Load configuration from environment or config file
load_configuration() {
    if [[ -f "${DEFAULT_CONFIG_FILE}" ]]; then
        source "${DEFAULT_CONFIG_FILE}"
    fi

    # Configuration with environment fallback
    DB_USER="${PGUSER:-${DB_USER:-ecommerce_user}}"
    DB_NAME="${PGDATABASE:-${DB_NAME:-ecommerce_db}}"
    TABLESPACE_NAME="${PGTABLESPACE:-${TABLESPACE_NAME:-ecommerce_ts}}"
    TABLESPACE_PATH="${PGTABLESPACE_PATH:-${TABLESPACE_PATH:-/Users/Shared/pgsql_tablespaces/${TABLESPACE_NAME}}}"
    PG_SUPERUSER="${PGSUPERUSER:-$(whoami)}"
    DB_PASSWORD="${PGPASSWORD:-}"  # Will prompt if not set

    # Enhanced environment variable handling
    export PGHOST="${PGHOST:-localhost}"
    export PGPORT="${PGPORT:-5432}"
    export PGUSER="${DB_USER}"
    # DO NOT export PGDATABASE globally! Only set it for DB-specific commands.

    # Validate and assign identifiers securely
    assign_sanitized_identifier "${DB_USER}" DB_USER
    assign_sanitized_identifier "${DB_NAME}" DB_NAME
    assign_sanitized_identifier "${TABLESPACE_NAME}" TABLESPACE_NAME

    # Try to load password from environment, then from stored credentials
    if [[ -z "${DB_PASSWORD:-}" ]]; then
        if stored_pass=$(get_stored_credentials "${DB_USER}" 2>/dev/null); then
            DB_PASSWORD="${stored_pass}"
            log_message "INFO" "🔑" "Loaded stored credentials for ${DB_USER}"
        fi
    fi

}

# Execute main function with error handling
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    trap cleanup EXIT
    main "$@"
fi
