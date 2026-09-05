docker run --rm \
  -u root \
  -v /var/folders:/var/folders \
  -p 15002:15002 \
  -p 4040:4040 \
  apache/spark:4.0.0 \
  /opt/spark/bin/spark-submit \
  --class org.apache.spark.sql.connect.service.SparkConnectServer \
  local:///opt/spark/jars/spark-connect_2.13-4.0.0.jar

docker run -d -p 6379:6379 --name hermes-redis redis

docker run -d -p 5001:5000 --name modelkit-registry -e REGISTRY_STORAGE_DELETE_ENABLED=true registry:2

docker run -d --name postgres-db -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=postgres -p 5432:5432 pgvector/pgvector:pg16
docker exec -i postgres-db psql -U postgres -d postgres -c "CREATE EXTENSION IF NOT EXISTS vector;"

docker run -d \
  --name chromadb \
  -p 8000:8000 \
  -v /Users/jemishtejani/chromadb-data:/data \
  chromadb/chroma:1.5.3

  docker run -d \
  --name keycloak-prod-1.1.4 \
  -p 8080:8080 \
  -e KC_HTTP_ENABLED=true \
  -e KEYCLOAK_ADMIN=admin \
  -e KEYCLOAK_ADMIN_PASSWORD=admin \
  harbor-registry.dataphion.com/iidrak/keycloak:1.1.4-arm64 \
  start \
  --hostname-strict=false

  docker run -d \
  --name ngrok-tunnel \
  -p 4041:4040 \
  -e NGROK_AUTHTOKEN='<YOUR_NGROK_AUTHTOKEN>' \
  ngrok/ngrok:latest \
  http host.docker.internal:11434