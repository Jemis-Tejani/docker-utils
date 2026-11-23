# spark-jars (local lakehouse only)

Binary jars for `local-spark-lakehouse` are **not** committed. Place them here on your machine:

```bash
# From spark-cluster (Hermes plugins + verified lib jars)
cd ../spark-cluster
make jars
cp build/jars/*.jar ../docker-utils/spark-jars/

# CatalogRegister Socket.IO deps (required; production image gets these via dependencies.sh)
curl -fsSL -o socket.io-client-2.1.0.jar \
  https://repo1.maven.org/maven2/io/socket/socket.io-client/2.1.0/socket.io-client-2.1.0.jar
curl -fsSL -o engine.io-client-2.1.0.jar \
  https://repo1.maven.org/maven2/io/socket/engine.io-client/2.1.0/engine.io-client-2.1.0.jar
curl -fsSL -o json-20250107.jar \
  https://repo1.maven.org/maven2/org/json/json/20250107/json-20250107.jar

# Other third-party connectors (Iceberg/Delta/JDBC/etc.) as needed for lakehouse.
```


Then start `local-spark-lakehouse` from Docker Desktop, or:

```bash
cd ../docker-utils
docker compose up -d spark-lakehouse
```
