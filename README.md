# MCParks Wiki

Docker image for [mcparks.wiki](https://www.mcparks.wiki). It's the official `mediawiki:stable-fpm` image with nginx, cron, a job runner and a handful of extensions baked in, all run by supervisord in a single container.

## How it fits together

- **Image build** (`Dockerfile`): installs nginx, cron, supervisor and LuaSandbox, copies everything in `config/` over the root filesystem, then runs `scripts/extensionInstaller.sh` to clone extensions and run composer.
- **On container start** (`scripts/entrypoint.sh`):
  - pulls `LocalSettings.php` from this repo's `main` branch on GitHub,
  - generates the sitemap and adds it to `robots.txt`,
  - starts supervisord.

  When `DEBUG=true`, it skips both of the first two steps.
- **supervisord** runs nginx, php-fpm, cron (rebuilds the sitemap nightly) and `scripts/jobRunner.sh` (processes the MediaWiki job queue, since `$wgJobRunRate = 0`).
- **CI** (`.github/workflows/build-docker.yaml`): every push builds and pushes the image to `ghcr.io/thealmightyzach/mcparkswiki`, tagged by branch (so `main` → `:main`).

### Settings split

| File | What's in it |
| --- | --- |
| `LocalSettings.php` | Wiki-specific config: skins, extensions, permissions, logos, SMTP, S3, Discord. **Fetched at runtime**, so changes go live on a container restart without needing a new image. |
| `config/var/www/html/CommonSettings.php` | Generic plumbing that's the same everywhere: DB connection, sitename/server/secret from env, URL paths, proxy IP handling. Baked into the image. |

Heads up: because `LocalSettings.php` is pulled from `main`, anything pushed to `main` affects prod on the next restart.

## Environment variables

| Variable | Used for |
| --- | --- |
| `MW_SITENAME`, `MW_SERVER`, `MW_SECRET` | Site name, public URL, `$wgSecretKey` (32 chars) |
| `DB_HOST`, `DB_NAME`, `DB_USER`, `DB_PASS` | MariaDB/MySQL connection |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_DOMAIN`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `SMTP_SENDER` | Outgoing email |
| `S3_NAME`, `S3_REGION`, `S3_KEY`, `S3_SECRET`, `S3_DOMAIN`, `S3_PREFIX` | File uploads stored in S3 (AWS extension) |
| `DISCORD_WEBHOOK` | Recent-changes feed to Discord |
| `DEBUG` | `true` = don't fetch LocalSettings or build the sitemap |

## Running locally

1. Copy `docker-compose.example.yaml` to `docker-compose.yaml` and change the passwords and `MW_SECRET`.
2. To test local `LocalSettings.php` changes, leave `DEBUG: true` and uncomment the volume mount so your copy is used instead of the one on GitHub.
3. `docker compose up -d`, then open http://localhost:8080.

An empty database won't have any MediaWiki tables, so the easiest route is loading a dump from prod into the `database` container. After a MediaWiki version bump (or adding an extension that has its own tables), run the schema updater:

```bash
docker exec -it mediawiki php maintenance/run.php update --quick
```

To test image changes (Dockerfile, scripts, extensions), build locally and point the compose file at it:

```bash
docker build -t mcparkswiki:dev .
```

## Extensions

Bundled with MediaWiki, plus these extras cloned at build time:

- [Discord](https://www.mediawiki.org/wiki/Extension:Discord) (`mw-discord`)
- [AWS](https://www.mediawiki.org/wiki/Extension:AWS) (`mediawiki-aws-s3`)
- [TabberNeue](https://www.mediawiki.org/wiki/Extension:TabberNeue)
- [Disambiguator](https://www.mediawiki.org/wiki/Extension:Disambiguator)
- [MobileFrontend](https://www.mediawiki.org/wiki/Extension:MobileFrontend)

### Adding or updating one

1. Add or update the repo in the `repos` array in `scripts/extensionInstaller.sh`: `["git url"]="BRANCH [DIRECTORY]"`. Set `DIRECTORY` when the repo name isn't the extension name (e.g. the `mediawiki-extensions-*` mirrors).
2. Load it with `wfLoadExtension(...)` in `LocalSettings.php`.
3. Push. **Order matters:** the new LocalSettings is live on the next restart, but the extension only exists once the new image is built and deployed. Deploy the image first, or the wiki will error on a missing extension.

When MediaWiki has a major version bump, update the `REL1_xx` branches for the Wikimedia extensions to match.

## Misc

- Dependabot keeps the GitHub Actions versions up to date.
- Sitemap lives at `/sitemap.xml` (symlink to the generated index), regenerated at midnight by cron and on every start.
