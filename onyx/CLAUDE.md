# Onyx — Deploy-Only Reference

Onyx is deployed as a containerized dependency. It is **not actively developed** in this repo. See the root `CLAUDE.md` for full infrastructure context.

- **Compose**: `onyx/deployment/docker_compose/docker-compose.yml` → port **3000**
- **Env file**: `onyx/deployment/docker_compose/.env`
- **Logs**: `docker compose logs <service>` or `onyx/backend/log/<service_name>_debug.log` (if volume-mounted)
- **Postgres**: `docker exec -it onyx-relational_db-1 psql -U postgres -c "<SQL>"`
- **API calls**: Route through the frontend (`http://localhost:3000/api/*`), not directly to backend port 8080
