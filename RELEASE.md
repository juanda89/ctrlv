# Release Guide (DMG + Sparkle + Lemon Squeezy)

## 1. Build and package

```bash
./scripts/build-release.sh 1.0.0
```

Genera en `dist/1.0.0/`:

- `ctrl+v.app`
- `ctrlv-1.0.0.zip` (Sparkle)
- `ctrlv-1.0.0.dmg`
- `SHA256SUMS.txt`

Para pruebas locales sin firma Apple (ad-hoc), el script ya funciona sin credenciales de notarización.

## 2. Sparkle (para todos los usuarios)

1. Configura la clave pública:
   - `./scripts/setup-sparkle-key.sh`
2. Exporta la clave privada y guárdala en GitHub Secret `SPARKLE_EDDSA_PRIVATE_KEY`.
3. Genera appcast:
   - `./scripts/generate-appcast.sh 1.0.0`
4. Publica `docs/updates/appcast.xml` y los binarios en `docs/downloads/` (GitHub Pages).

Notas:
- Sparkle no depende del estado de suscripción.
- `Check for Updates` está habilitado para todos en la app.

Publicación local de release (actualiza `docs/latest.json`, `docs/downloads/*`, `docs/updates/appcast.xml`):

```bash
SPARKLE_EDDSA_PRIVATE_KEY="<private-key>" \
./scripts/publish-release-to-docs.sh 1.0.0
```

## 3. GitHub Actions

Workflow: `.github/workflows/release.yml`

- Build + sign + notarize (si hay credenciales Apple).
- Publica release con `.dmg` + `.zip` + checksums.
- Regenera `latest.json` y despliega `docs/` a GitHub Pages.

Secrets recomendados:

- `SPARKLE_EDDSA_PRIVATE_KEY` (requerido)
- `APPLE_DEVELOPER_ID_APPLICATION`
- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_PASSWORD`

## 4. Lemon Squeezy (comercial)

En la app:

- Validación directa de license key contra Lemon Squeezy
- Activación por dispositivo (instance ID)
- Grace offline de 30 días después de validación exitosa

Manualmente debes configurar:
- URL de checkout
- URL de portal/manage
- License key de sandbox para QA
