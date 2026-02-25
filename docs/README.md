# ctrl+v Download Site

Contenido estático para GitHub Pages:

- `index.html`: landing de descarga.
- `latest.json`: metadata consumida por la landing.
- `SHA256SUMS.txt`: checksums públicos.
- `updates/appcast.xml`: feed Sparkle público.
- `downloads/`: binarios `.dmg` y `.zip` publicados en cada release.

El workflow `release.yml` actualiza `latest.json`, `SHA256SUMS.txt`, `updates/appcast.xml` y copia artefactos a `downloads/` en cada release.

Para pruebas locales sin esperar CI:

```bash
./scripts/build-release.sh <version> <build>
SPARKLE_EDDSA_PRIVATE_KEY="<private-key>" ./scripts/publish-release-to-docs.sh <version>
```
