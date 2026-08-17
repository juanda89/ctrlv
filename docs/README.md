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

Para generar artefactos de prueba fuera de `dist/` y dejarlos en `dist-local/`:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CTRLV_DIST_DIR_BASE="$(pwd)/dist-local" \
./scripts/build-release.sh <version> <build>
```

## Rebuilding the stylesheet

The pages use a precompiled Tailwind stylesheet (`assets/tailwind.css`) —
there is no runtime CSS CDN (the old cdn.tailwindcss.com Play CDN was retired
upstream and broke the site once). If you add or change Tailwind utility
classes in any page here, regenerate the stylesheet:

```bash
bash scripts/build-docs-css.sh
```

Theme tokens (colors, fonts, radii) live in `scripts/docs-css/tailwind.config.js`.
