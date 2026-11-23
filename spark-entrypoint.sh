#!/bin/bash
set -e

# Link Hermes plugins and Lakehouse connectors into standard Spark jars directory
HERMES_JARS_DIR="/opt/spark/hermes-jars"
JAR_COUNT=$(find "${HERMES_JARS_DIR}" -maxdepth 1 -name "*.jar" 2>/dev/null | wc -l | tr -d ' ')

if [ "${JAR_COUNT}" -eq 0 ]; then
  cat <<'EOF'
================================================================================
[ERROR] Missing Spark Lakehouse Dependencies in ./spark-jars/
================================================================================
No JAR files were found in /opt/spark/hermes-jars (mounted from ./spark-jars).

Spark Connect Server cannot start without required Lakehouse and Hermes plugins:
  - Apache Iceberg runtime (e.g. iceberg-spark-runtime-*.jar)
  - Delta Lake (e.g. delta-spark_*.jar)
  - Hermes CatalogRegister & UDF plugins
  - Socket.IO client libraries (socket.io-client, engine.io-client, json)

HOW TO FIX:
  1. Build or copy Hermes plugins from your local spark-cluster repository:
       cd ../spark-cluster
       make jars
       cp build/jars/*.jar ../docker-utils/spark-jars/

  2. Download Socket.IO dependencies (from spark-jars directory):
       cd ../docker-utils/spark-jars
       curl -fsSL -O https://repo1.maven.org/maven2/io/socket/socket.io-client/2.1.0/socket.io-client-2.1.0.jar
       curl -fsSL -O https://repo1.maven.org/maven2/io/socket/engine.io-client/2.1.0/engine.io-client-2.1.0.jar
       curl -fsSL -O https://repo1.maven.org/maven2/org/json/json/20250107/json-20250107.jar

  3. Refer to spark-jars/README.md for the complete list of required JARs.
================================================================================
EOF
  sleep 5
  exit 1
fi

echo "==> Found ${JAR_COUNT} Lakehouse JAR file(s) in ${HERMES_JARS_DIR}. Linking to Spark classpath..."
cp -sf "${HERMES_JARS_DIR}"/*.jar /opt/spark/jars/ 2>/dev/null || true

# Check for essential lakehouse extensions
MISSING_CORE=""
if ! ls /opt/spark/jars/*iceberg* >/dev/null 2>&1; then
  MISSING_CORE="${MISSING_CORE} Iceberg"
fi
if ! ls /opt/spark/jars/*delta* >/dev/null 2>&1; then
  MISSING_CORE="${MISSING_CORE} DeltaLake"
fi
if ! ls /opt/spark/jars/*catalog-register* >/dev/null 2>&1; then
  MISSING_CORE="${MISSING_CORE} CatalogRegister"
fi

if [ -n "${MISSING_CORE}" ]; then
  echo "WARN: Missing recommended lakehouse components in spark-jars:${MISSING_CORE}."
  echo "      Spark will start, but queries requiring these extensions may fail."
fi

# Merge base spark-defaults + optional local overlay (Keycloak secrets; gitignored on host)
SPARK_CONF_DIR="${SPARK_CONF_DIR:-/opt/spark/conf}"
mkdir -p "${SPARK_CONF_DIR}"
if [ -f /opt/hermes-spark-conf/spark-defaults.conf ]; then
  cp /opt/hermes-spark-conf/spark-defaults.conf "${SPARK_CONF_DIR}/spark-defaults.conf"
  if [ -f /opt/hermes-spark-conf/spark-defaults.local.conf ]; then
    echo "==> Applying local secret overlay: spark-defaults.local.conf"
    {
      echo ""
      echo "# --- spark-defaults.local.conf (host overlay) ---"
      cat /opt/hermes-spark-conf/spark-defaults.local.conf
    } >> "${SPARK_CONF_DIR}/spark-defaults.conf"
  else
    cat <<'EOF'
--------------------------------------------------------------------------------
[INFO] Local secret overlay 'spark-defaults.local.conf' was not found.
  CatalogRegister Keycloak credentials are unconfigured.
  If your workflow requires Keycloak catalog integration, copy the example:
    cp spark-conf/spark-defaults.local.conf.example spark-conf/spark-defaults.local.conf
  and configure client credentials from Hermes CMS App Config.
--------------------------------------------------------------------------------
EOF
  fi
fi

# Spark resolves InetAddress.getLocalHost() at startup; ensure hostname maps to loopback
HOSTNAME_FQDN="$(hostname)"
if ! grep -qE "[[:space:]]${HOSTNAME_FQDN}([[:space:]]|$)" /etc/hosts 2>/dev/null; then
  echo "127.0.0.1 ${HOSTNAME_FQDN}" >> /etc/hosts
fi

mkdir -p /app/spark-iidrak/warehouse /app/spark-iidrak/spark-tmp /app/spark-iidrak/spark-events

# ---------------------------------------------------------------------------
# Local-dev memory model (single-container Master + Worker + Connect + Executor)
#
# Concurrent JVM heaps:
#   master daemon + worker daemon + Connect driver + 1 executor
# Must stay under ~80% of Docker mem_limit (rest = metaspace / native / OS).
# Defaults target mem_limit ≈ 1792m on a laptop (Hermes SQL Editor / Connect).
# Spark 4 rejects executor memory below ~450m — keep executor >= 512m.
# ---------------------------------------------------------------------------
to_mb() {
  local raw="${1}"
  local num unit
  num="$(echo "${raw}" | tr -d '[:space:]' | sed -E 's/^([0-9]+).*/\1/')"
  unit="$(echo "${raw}" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[0-9]+//')"
  case "${unit}" in
    g|gb) echo $((num * 1024)) ;;
    m|mb|"") echo "${num}" ;;
    *) echo "${num}" ;;
  esac
}

from_mb() {
  echo "${1}m"
}

# Spark 4 UnifiedMemoryManager minimum (~450 MiB)
MIN_EXECUTOR_MB=512

export SPARK_MASTER_HOST="${SPARK_MASTER_HOST:-0.0.0.0}"
export SPARK_MASTER_PORT=7077
export SPARK_LOCAL_IP="${SPARK_LOCAL_IP:-0.0.0.0}"
export SPARK_LOCAL_HOSTNAME="${SPARK_LOCAL_HOSTNAME:-${HOSTNAME_FQDN}}"
export SPARK_DRIVER_MEMORY="${SPARK_DRIVER_MEMORY:-512m}"
export SPARK_WORKER_CORES="${SPARK_WORKER_CORES:-1}"
export SPARK_WORKER_MEMORY="${SPARK_WORKER_MEMORY:-512m}"
export SPARK_DAEMON_MEMORY="${SPARK_DAEMON_MEMORY:-192m}"
export SPARK_EXECUTOR_MEMORY="${SPARK_EXECUTOR_MEMORY:-512m}"
export SPARK_EXECUTOR_CORES="${SPARK_EXECUTOR_CORES:-1}"


DRIVER_MB="$(to_mb "${SPARK_DRIVER_MEMORY}")"
WORKER_MB="$(to_mb "${SPARK_WORKER_MEMORY}")"
DAEMON_MB="$(to_mb "${SPARK_DAEMON_MEMORY}")"
EXECUTOR_MB="$(to_mb "${SPARK_EXECUTOR_MEMORY}")"

# Enforce Spark 4 minimum executor memory
if [ "${EXECUTOR_MB}" -lt "${MIN_EXECUTOR_MB}" ]; then
  echo "WARN: SPARK_EXECUTOR_MEMORY (${SPARK_EXECUTOR_MEMORY}) below Spark 4 minimum; raising to ${MIN_EXECUTOR_MB}m."
  EXECUTOR_MB="${MIN_EXECUTOR_MB}"
  SPARK_EXECUTOR_MEMORY="$(from_mb "${EXECUTOR_MB}")"
fi

# Worker offer must cover executor (no fake oversubscribe)
if [ "${WORKER_MB}" -lt "${EXECUTOR_MB}" ]; then
  echo "WARN: SPARK_WORKER_MEMORY (${SPARK_WORKER_MEMORY}) < executor; raising worker offer to ${EXECUTOR_MB}m."
  WORKER_MB="${EXECUTOR_MB}"
  SPARK_WORKER_MEMORY="$(from_mb "${WORKER_MB}")"
fi

HEAP_SUM_MB=$((DAEMON_MB + DAEMON_MB + DRIVER_MB + EXECUTOR_MB))

# If cgroup memory.max is set, keep heaps within 80% of the container limit
CGROUP_MAX="$(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo max)"
if [ "${CGROUP_MAX}" != "max" ] && [ -n "${CGROUP_MAX}" ] && [ "${CGROUP_MAX}" -gt 0 ] 2>/dev/null; then
  LIMIT_MB=$((CGROUP_MAX / 1024 / 1024))
  BUDGET_MB=$((LIMIT_MB * 80 / 100))
  if [ "${HEAP_SUM_MB}" -gt "${BUDGET_MB}" ]; then
    echo "WARN: planned JVM heaps ${HEAP_SUM_MB}m exceed ~80% of mem_limit (${LIMIT_MB}m). Auto-clamping for OOM safety."
    # Shrink daemons first, then driver; never drop executor below Spark 4 minimum
    while [ "${HEAP_SUM_MB}" -gt "${BUDGET_MB}" ] && [ "${DAEMON_MB}" -gt 128 ]; do
      DAEMON_MB=$((DAEMON_MB - 32))
      HEAP_SUM_MB=$((DAEMON_MB + DAEMON_MB + DRIVER_MB + EXECUTOR_MB))
    done
    while [ "${HEAP_SUM_MB}" -gt "${BUDGET_MB}" ] && [ "${DRIVER_MB}" -gt 384 ]; do
      DRIVER_MB=$((DRIVER_MB - 64))
      HEAP_SUM_MB=$((DAEMON_MB + DAEMON_MB + DRIVER_MB + EXECUTOR_MB))
    done
    WORKER_MB="${EXECUTOR_MB}"
    SPARK_DAEMON_MEMORY="$(from_mb "${DAEMON_MB}")"
    SPARK_DRIVER_MEMORY="$(from_mb "${DRIVER_MB}")"
    SPARK_EXECUTOR_MEMORY="$(from_mb "${EXECUTOR_MB}")"
    SPARK_WORKER_MEMORY="$(from_mb "${WORKER_MB}")"
    if [ "${HEAP_SUM_MB}" -gt "${BUDGET_MB}" ]; then
      echo "ERROR: cannot fit Spark heaps (${HEAP_SUM_MB}m) into ${LIMIT_MB}m mem_limit. Raise mem_limit (recommended >= 1792m)."
      exit 1
    fi
  fi
  echo "Spark memory budget: heaps=${HEAP_SUM_MB}m / limit=${LIMIT_MB}m (daemon=${SPARK_DAEMON_MEMORY} x2, driver=${SPARK_DRIVER_MEMORY}, executor=${SPARK_EXECUTOR_MEMORY}, worker_offer=${SPARK_WORKER_MEMORY})"
else
  echo "Spark memory: daemon=${SPARK_DAEMON_MEMORY} x2, driver=${SPARK_DRIVER_MEMORY}, executor=${SPARK_EXECUTOR_MEMORY}, worker_offer=${SPARK_WORKER_MEMORY} (sum≈${HEAP_SUM_MB}m)"
fi


export SPARK_DAEMON_MEMORY
export SPARK_DRIVER_MEMORY
export SPARK_WORKER_MEMORY
export SPARK_EXECUTOR_MEMORY

# Start Master
/opt/spark/sbin/start-master.sh
sleep 3

# Start Worker with local core/memory caps
/opt/spark/sbin/start-worker.sh \
  --cores "${SPARK_WORKER_CORES}" \
  --memory "${SPARK_WORKER_MEMORY}" \
  spark://127.0.0.1:7077
sleep 3

# Unset daemon memory so spark-submit driver uses SPARK_DRIVER_MEMORY / --driver-memory
unset SPARK_DAEMON_MEMORY

# Start Spark Connect Server attached to the cluster
exec /opt/spark/bin/spark-submit \
  --class org.apache.spark.sql.connect.service.SparkConnectServer \
  --master spark://127.0.0.1:7077 \
  --driver-memory "${SPARK_DRIVER_MEMORY}" \
  --conf "spark.executor.memory=${SPARK_EXECUTOR_MEMORY}" \
  --conf "spark.executor.cores=${SPARK_EXECUTOR_CORES}" \
  --conf spark.executor.instances=1 \
  --conf spark.cores.max=1 \
  local:///opt/spark/jars/spark-connect_2.13-4.0.0.jar
