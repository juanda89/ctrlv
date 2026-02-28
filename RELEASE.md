# Release Guide (Source of Truth)

Este documento define el flujo correcto para evitar desincronizaciones de versión.

## 1. Regla crítica (versionado)

El workflow de release se dispara por tag `v*` y toma la versión desde el tag.

- Correcto: crear `v1.1.21` si quieres publicar `1.1.21`.
- Incorrecto: hacer solo commit/push sin tag (no genera release nuevo).

Referencia: `.github/workflows/release.yml` (`on.push.tags`).

## 2. Flujo oficial: commit + push + tag

Reemplaza `1.1.21` por la versión real:

```bash
git status
git add <archivos>
git commit -m "chore: <mensaje>"

git tag -a v1.1.21 -m "Pre-release: stability not yet verified"
git push origin main
git push origin v1.1.21
```

Verificaciones rápidas:

```bash
git ls-remote --tags origin "v1.1.*" | sed 's#refs/tags/##' | awk '{print $2}' | sort -V | tail -n 5
curl -Ls https://github.com/juanda89/ctrlv/releases/latest/download/appcast.xml | rg "shortVersionString|sparkle:version"
```

## 3. Build local en `dist-local` (para pruebas)

Usar Xcode completo (no solo CommandLineTools), porque `actool` es necesario:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CTRLV_DIST_DIR_BASE="$(pwd)/dist-local" \
./scripts/build-release.sh 1.1.21 10121
```

Salida esperada en `dist-local/1.1.21/`:

- `ctrlv.app`
- `ctrlv-1.1.21.zip`
- `ctrlv-1.1.21.dmg`
- `SHA256SUMS.txt`

Notas:

- `dist-local/` es para pruebas locales; no se debe commitear.
- Si ves error de xattrs/codesign, limpiar atributos extendidos y reintentar build.

## 4. Sparkle (para todos los usuarios)

1. Configura la clave pública:
   - `./scripts/setup-sparkle-key.sh`
2. Guarda la privada en GitHub Secret:
   - `SPARKLE_EDDSA_PRIVATE_KEY`
3. El release workflow publica:
   - `ctrlv-<version>.dmg`
   - `ctrlv-latest.dmg`
   - `ctrlv-<version>.zip`
   - `appcast.xml`

`Check for Updates` aplica para todos los usuarios (sin gating de suscripción).

## 5. Secrets de CI

- Requerido:
  - `SPARKLE_EDDSA_PRIVATE_KEY`
- Opcionales (firma/notarización Apple):
  - `APPLE_DEVELOPER_ID_APPLICATION`
  - `APPLE_ID`
  - `APPLE_TEAM_ID`
  - `APPLE_APP_PASSWORD`

## 6. QA manual mínimo

1. Instalar `ctrlv.app` en `/Applications`.
2. Abrir app y ejecutar `Check for Updates`.
3. Verificar que detecta la última versión del `appcast.xml`.
4. Verificar instalación o fallback manual (`Download latest .dmg`) si Sparkle falla.
