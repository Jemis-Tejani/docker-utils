#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Hermes Local Service Updater (Mac Apple Silicon - linux/arm64)
# Interactive two-level CLI to rebuild, update, and clean local Docker images
# for OpenMetadata and Keycloak using tags from docker-compose.yml.
# ==============================================================================

readonly PLATFORM="linux/arm64"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly UTILS_COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"

OMD_REPO="${OMD_REPO:-$(cd "$SCRIPT_DIR/../hermes-openmetadata" 2>/dev/null && pwd || true)}"
KEYCLOAK_REPO="${KEYCLOAK_REPO:-$(cd "$SCRIPT_DIR/../hermes-keycloak-strapi-spi" 2>/dev/null && pwd || true)}"

# ------------------------------------------------------------------------------
# Logging & Validation Helpers
# ------------------------------------------------------------------------------
log_step()    { printf '\n%s\n' "$*"; }
log_info()    { printf '   %s\n' "$*"; }
log_warn()    { printf '⚠️  %s\n' "$*" >&2; }
log_success() { printf '\n✅ %s\n' "$*"; }
die()         { printf '❌ Error: %s\n' "$*" >&2; exit 1; }

require_docker() {
  command -v docker >/dev/null 2>&1 || die "'docker' CLI not found in PATH."
  docker info >/dev/null 2>&1 || die "Docker daemon is not running. Please start Docker Desktop first."
}

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || die "'$cmd' is required but not found in PATH."
}

# ------------------------------------------------------------------------------
# Shared Docker Helpers
# ------------------------------------------------------------------------------
buildx_arm64() {
  local dockerfile="$1"
  local tag="$2"
  local context="$3"

  DOCKER_BUILDKIT=1 docker buildx build \
    --platform "$PLATFORM" \
    --file "$dockerfile" \
    --tag "$tag" \
    --load \
    "$context"
}

prune_docker_cache() {
  log_step "🧹 Removing dangling (<none>) image layers..."
  docker image prune -f

  log_step "🧹 Purging all Docker build cache..."
  docker builder prune -a -f
}

clean_old_images() {
  local pattern="$1"
  local keep_images="$2"
  local removed=0

  log_step "🧹 Removing old images to free Mac storage..."
  while IFS= read -r img; do
    [[ -z "$img" ]] && continue
    if ! grep -qx "$img" <<< "$keep_images"; then
      log_info "Removing old image: $img"
      docker rmi "$img" || true
      removed=$((removed + 1))
    fi
  done < <(
    docker images --format '{{.Repository}}:{{.Tag}}' \
      | grep -E "$pattern" \
      | grep -v '<none>' || true
  )

  if [[ "$removed" -eq 0 ]]; then
    log_info "No old images found."
  fi

  prune_docker_cache
}

# ------------------------------------------------------------------------------
# OpenMetadata Operations
# ------------------------------------------------------------------------------
load_omd_config() {
  if [[ -z "$OMD_REPO" || ! -f "$OMD_REPO/docker/hermes/docker-compose.yml" ]]; then
    die "hermes-openmetadata repo not found at '$SCRIPT_DIR/../hermes-openmetadata'. Set OMD_REPO=/path/to/hermes-openmetadata."
  fi

  OMD_COMPOSE_FILE="$OMD_REPO/docker/hermes/docker-compose.yml"
  OMD_INGESTION_DIR="$OMD_REPO/docker/hermes/custom-ingestion"
  OMD_CURRENT_IMAGES="$(docker compose -f "$OMD_COMPOSE_FILE" config --images 2>/dev/null | sort -u)"
  OMD_SERVER_IMG="$(grep -E '/openmetadata:' <<< "$OMD_CURRENT_IMAGES" | head -n1 || true)"
  OMD_INGESTION_IMG="$(grep -E '/openmetadata-ingestion:' <<< "$OMD_CURRENT_IMAGES" | head -n1 || true)"

  if [[ -z "$OMD_SERVER_IMG" || -z "$OMD_INGESTION_IMG" ]]; then
    die "Could not read server or ingestion image from $OMD_COMPOSE_FILE"
  fi
}

omd_down() {
  log_step "🛑 Stopping OpenMetadata containers..."
  docker compose -f "$OMD_COMPOSE_FILE" down
}

omd_up() {
  log_step "🚀 Starting OpenMetadata stack..."
  docker compose -f "$OMD_COMPOSE_FILE" up -d
  printf '\n'
  docker compose -f "$OMD_COMPOSE_FILE" ps
  log_success "OpenMetadata is up and running."
}

omd_build_server() {
  log_step "🔨 Building OpenMetadata Server ($OMD_SERVER_IMG)..."
  buildx_arm64 "$OMD_REPO/docker/hermes/server.Dockerfile" "$OMD_SERVER_IMG" "$OMD_REPO"
}

omd_build_ingestion() {
  log_step "🔨 Building OpenMetadata Ingestion ($OMD_INGESTION_IMG)..."
  buildx_arm64 "$OMD_INGESTION_DIR/Dockerfile" "$OMD_INGESTION_IMG" "$OMD_INGESTION_DIR"
}

# ------------------------------------------------------------------------------
# Keycloak Operations
# ------------------------------------------------------------------------------
load_keycloak_config() {
  if [[ -z "$KEYCLOAK_REPO" || ! -f "$KEYCLOAK_REPO/Dockerfile" ]]; then
    die "hermes-keycloak-strapi-spi repo not found at '$SCRIPT_DIR/../hermes-keycloak-strapi-spi'. Set KEYCLOAK_REPO=/path/to/hermes-keycloak-strapi-spi."
  fi

  KEYCLOAK_IMG="$(docker compose -f "$UTILS_COMPOSE_FILE" config --images 2>/dev/null | grep -E 'hermes-keycloak:' | head -n1 || echo "hermes-keycloak:local-arm64")"
}

keycloak_update() {
  require_cmd git
  require_cmd mvn
  require_cmd jar

  log_step "📥 Pulling latest Keycloak SPI & theme changes..."
  git -C "$KEYCLOAK_REPO" pull

  log_step "🔨 Building Keycloak SPI jar (mvn clean package)..."
  (cd "$KEYCLOAK_REPO" && mvn -q clean package -DskipTests)

  log_step "🎨 Packaging nexaris-login-theme.jar..."
  local theme_stage
  theme_stage="$(mktemp -d)"
  mkdir -p "$theme_stage/theme" "$theme_stage/META-INF"
  cp -R "$KEYCLOAK_REPO/login-theme/themes/." "$theme_stage/theme/"
  cp "$KEYCLOAK_REPO/login-theme/META-INF/keycloak-themes.json" "$theme_stage/META-INF/"
  find "$theme_stage" -name ".DS_Store" -delete
  (cd "$theme_stage" && jar --create --file "$theme_stage/nexaris-login-theme.jar" META-INF theme)
  mv "$theme_stage/nexaris-login-theme.jar" "$KEYCLOAK_REPO/login-theme/nexaris-login-theme.jar"
  rm -rf "$theme_stage"

  log_step "🔨 Building Keycloak image ($KEYCLOAK_IMG)..."
  buildx_arm64 "$KEYCLOAK_REPO/Dockerfile" "$KEYCLOAK_IMG" "$KEYCLOAK_REPO"

  log_step "🧹 Cleaning build artifacts from git working tree..."
  git -C "$KEYCLOAK_REPO" checkout -- .

  log_step "🚀 Recreating Keycloak container..."
  docker compose -f "$UTILS_COMPOSE_FILE" up -d --force-recreate keycloak

  clean_old_images 'hermes-keycloak:' "$KEYCLOAK_IMG"

  printf '\n'
  docker compose -f "$UTILS_COMPOSE_FILE" ps keycloak
  log_success "Keycloak is up and running."
}

keycloak_clean() {
  clean_old_images 'hermes-keycloak:' "$KEYCLOAK_IMG"
  log_success "Keycloak cleanup complete."
}

# ------------------------------------------------------------------------------
# Interactive Menus
# ------------------------------------------------------------------------------
openmetadata_menu() {
  load_omd_config

  while true; do
    printf '\n============================================================\n'
    printf '  OpenMetadata Updater (Mac - %s)\n' "$PLATFORM"
    printf '============================================================\n'
    printf '  Server:    %s\n' "$OMD_SERVER_IMG"
    printf '  Ingestion: %s\n' "$OMD_INGESTION_IMG"
    printf '%s\n' '------------------------------------------------------------'
    printf '  1) Update Ingestion Only  (Rebuild Ingestion + Clean + Start)\n'
    printf '  2) Update Server Only     (Rebuild Server + Clean + Start)\n'
    printf '  3) Update Both Services   (Rebuild Server & Ingestion + Clean + Start)\n'
    printf '  4) Clean Only             (Remove Old OMD Images & Build Cache)\n'
    printf '  5) Back to Main Menu\n'
    printf '  0) Exit\n'
    printf '============================================================\n'

    local choice
    read -r -p "Select an option [0-5]: " choice || exit 0

    case "$choice" in
      1)
        omd_down
        omd_build_ingestion
        clean_old_images 'openmetadata-ingestion:' "$OMD_CURRENT_IMAGES"
        omd_up
        return 0
        ;;
      2)
        omd_down
        omd_build_server
        clean_old_images '(openmetadata:|openmetadata/db:)' "$OMD_CURRENT_IMAGES"
        omd_up
        return 0
        ;;
      3)
        omd_down
        omd_build_server
        omd_build_ingestion
        clean_old_images '(openmetadata|openmetadata-ingestion|openmetadata/db):' "$OMD_CURRENT_IMAGES"
        omd_up
        return 0
        ;;
      4)
        clean_old_images '(openmetadata|openmetadata-ingestion|openmetadata/db):' "$OMD_CURRENT_IMAGES"
        log_success "OpenMetadata cleanup complete."
        return 0
        ;;
      5)
        return 0
        ;;
      0)
        printf 'Bye!\n'
        exit 0
        ;;
      *)
        log_warn "Invalid option '$choice'. Please enter a number between 0 and 5."
        ;;
    esac
  done
}

keycloak_menu() {
  load_keycloak_config

  while true; do
    printf '\n============================================================\n'
    printf '  Keycloak Updater (Mac - %s)\n' "$PLATFORM"
    printf '============================================================\n'
    printf '  Image: %s\n' "$KEYCLOAK_IMG"
    printf '%s\n' '------------------------------------------------------------'
    printf '  1) Update Keycloak        (Pull + Build SPI/Theme + Recreate + Clean)\n'
    printf '  2) Clean Only             (Remove Old Keycloak Images & Build Cache)\n'
    printf '  3) Back to Main Menu\n'
    printf '  0) Exit\n'
    printf '============================================================\n'

    local choice
    read -r -p "Select an option [0-3]: " choice || exit 0

    case "$choice" in
      1)
        keycloak_update
        return 0
        ;;
      2)
        keycloak_clean
        return 0
        ;;
      3)
        return 0
        ;;
      0)
        printf 'Bye!\n'
        exit 0
        ;;
      *)
        log_warn "Invalid option '$choice'. Please enter a number between 0 and 3."
        ;;
    esac
  done
}

main_menu() {
  while true; do
    printf '\n============================================================\n'
    printf '  Hermes Local Service Updater (Mac - %s)\n' "$PLATFORM"
    printf '============================================================\n'
    printf '  1) OpenMetadata  (Server & Ingestion)\n'
    printf '  2) Keycloak      (SPI & Login Theme)\n'
    printf '  0) Exit\n'
    printf '============================================================\n'

    local choice
    read -r -p "Select a service [0-2]: " choice || exit 0

    case "$choice" in
      1) openmetadata_menu ;;
      2) keycloak_menu ;;
      0)
        printf 'Bye!\n'
        exit 0
        ;;
      *)
        log_warn "Invalid option '$choice'. Please enter 0, 1, or 2."
        ;;
    esac
  done
}

require_docker
main_menu
