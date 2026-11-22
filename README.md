# Deploy

Konfiguracja produkcyjna Agregatora Ofert Nieruchomości: jeden VPS (Hetzner CPX22) z Docker Compose.

Repozytorium zawiera tylko konfigurację serwera. Obrazy aplikacji budują repozytoria [backend](https://github.com/property-aggregator/backend), [frontend](https://github.com/property-aggregator/frontend) i [scraper](https://github.com/property-aggregator/scraper) i publikują je w `ghcr.io/property-aggregator/*`.

## Architektura

```
Internet ─► Caddy :443 (HTTPS) ─► frontend :3000 ─► api :8080 ─► PostgreSQL + PostGIS
                                                                    ▲
                    scraper ◄──► RabbitMQ ◄──► worker ──────────────┘
```

* Z internetu dostępny jest tylko **Caddy** (porty 80 i 443). Pozostałe usługi działają w wewnętrznej sieci Dockera.
* Caddy sam pobiera i odnawia certyfikaty Let's Encrypt.
* Frontend wywołuje API po stronie serwera, więc API nie jest publiczne. Subdomena `api.` jest przygotowana w `Caddyfile` pod SignalR.
* Przy każdym starcie najpierw uruchamia się `migrations` (migracje EF Core). `api` i `worker` startują po jego sukcesie.
* Dane PostgreSQL, RabbitMQ i Caddy są w wolumenach Dockera, więc aktualizacja obrazów ich nie usuwa.

## Pliki

| Plik | Zawartość |
|---|---|
| `docker-compose.yml` | Wszystkie usługi, limity pamięci, healthchecki, rotacja logów |
| `Caddyfile` | Domeny, HTTPS, przekierowanie `www` |
| `.env.example` | Szablon zmiennych. Prawdziwy `.env` istnieje **tylko na serwerze** i nie trafia do repozytorium |
| `scripts/backup-db.sh` | Kopia bazy (`pg_dump`), 7 dni wstecz |
| `scraper/sources.toml` | Źródła scrapera; montowane do kontenera, zmiany działają bez restartu |

## Pierwsze uruchomienie

Wymagania:

* rekordy DNS `A` dla `kazdy-nieruch.pl`, `www` i `api` wskazują na IP serwera,
* w GHCR są obrazy wszystkich usług z `docker-compose.yml`,
* w Auth0 są dodane adresy `https://kazdy-nieruch.pl` (callback `/auth/callback`, logout, web origins).

Na serwerze (użytkownik `deploy`):

```bash
sudo mkdir -p /opt/property-aggregator && sudo chown deploy: /opt/property-aggregator
git clone https://github.com/property-aggregator/deploy.git /opt/property-aggregator
cd /opt/property-aggregator

cp .env.example .env
chmod 600 .env
nano .env   # hasła i sekrety: openssl rand -hex 32

# GHCR: token (classic) z uprawnieniem read:packages
echo "<TOKEN>" | docker login ghcr.io -u <github-login> --password-stdin

docker compose pull
docker compose up -d
docker compose ps
```

## Aktualizacja

```bash
cd /opt/property-aggregator
git pull                 # zmiany w konfiguracji
docker compose pull      # nowe obrazy
docker compose up -d     # restartuje tylko zmienione usługi
docker image prune -f
```

Konkretną wersję można przypiąć w `.env`, np. `BACKEND_TAG=sha-abc1234`.

## Przydatne polecenia

```bash
docker compose logs -f api worker      # logi
docker compose logs migrations         # wynik migracji
docker compose restart scraper
```

## Kopie zapasowe

```bash
chmod +x scripts/backup-db.sh
crontab -e
# 0 4 * * * cd /opt/property-aggregator && ./scripts/backup-db.sh >> backups/backup.log 2>&1
```

Kopie leżą na tym samym serwerze, więc nie chronią przed jego utratą. Docelowo warto je kopiować poza serwer (np. Hetzner Storage Box) albo włączyć backupy serwera w Hetzner Cloud.

Przywracanie:

```bash
. ./.env
docker compose exec -T postgres pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean < backups/<plik>.dump
```
