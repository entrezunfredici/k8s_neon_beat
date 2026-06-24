# CONVENTIONS.md — Stack technique et nommage

## Stack technique

| Couche | Technologie |
|---|---|
| Backend | Rust / Axum (`neon-beat-back`) |
| Frontend jeu | React / Vite (`neon-beat-game-front`) |
| Frontend admin | React / Vite / Ant Design (`neon-beat-admin-front`) |
| Frontend buzzer | React / Vite (`neon-beat-virtual-buzzer`) |
| Base de données | CouchDB 3 (StatefulSet k8s) |
| Orchestration | Kubernetes — Ingress NGINX + cert-manager |
| TLS | Let's Encrypt via Cloudflare DNS01 |
| Registry | GitHub Container Registry (`ghcr.io/neon-beat/`) |

---

## Nommage des ressources Kubernetes

### Namespaces
| Environnement | Namespace |
|---|---|
| Production | `neon-beat` |
| Pré-production | `neon-beat-preprod` |

### Pattern général
`neon-beat-{env}-{composant}`

| Ressource | Exemple prod | Exemple preprod |
|---|---|---|
| Deployment backend | `neon-beat-prod-back` | `neon-beat-preprod-back` |
| StatefulSet CouchDB | `neon-beat-prod-couchdb` | `neon-beat-preprod-couchdb` |
| ConfigMap | `neon-beat-prod-config` | `neon-beat-preprod-config` |
| Secret | `neon-beat-prod-secrets` | `neon-beat-preprod-secrets` |
| HPA game front | `neon-beat-prod-game-front-hpa` | — |
| PDB game front | `neon-beat-prod-game-front-pdb` | — |
| NetworkPolicy default-deny | `neon-beat-prod-default-deny` | — |
| CronJob backup | `neon-beat-prod-couchdb-backup` | — |

### Images Docker
Pattern : `ghcr.io/neon-beat/{composant}:{env}`

```
ghcr.io/neon-beat/neon-beat-back:prod
ghcr.io/neon-beat/neon-beat-game-front:prod
ghcr.io/neon-beat/neon-beat-admin-front:prod
ghcr.io/neon-beat/neon-beat-virtual-buzzer:prod
```

---

## Structure des fichiers k8s

```
k8s/
├── cert-manager/
│   ├── cluster-issuer.yml               # Infomaniak DNS01 (legacy)
│   ├── cluster-issuer-cloudflare.yml    # Cloudflare DNS01 (actif)
│   ├── cloudflare-secret.yml
│   └── cloudflare-secret.yml.example
├── app/
│   ├── ingress.yml                      # Template ingress générique
│   └── ingress-test.yml
├── preprod/
│   ├── namespace.yml
│   ├── configmap.yml
│   ├── secret.example.yml
│   ├── deployment.yml                   # CouchDB + back + 3 frontends
│   ├── service.yml
│   └── ingress.yml
├── prod/
│   ├── configmap.yml
│   ├── secret.example.yml
│   ├── deployment.yml                   # CouchDB + back + 3 frontends
│   ├── service.yml
│   ├── ingress.yml
│   ├── hpa.yml                          # HPA frontends
│   ├── network-policy.yml               # Isolation réseau
│   ├── pdb.yml                          # PodDisruptionBudget frontends
│   └── backup-cronjob.yml               # Sauvegarde CouchDB quotidienne
├── namespace.yml                        # Namespace prod (neon-beat)
└── setup.sh                             # Initialisation cluster
```

---

## Replicas par environnement

| Composant | Prod | Preprod | Remarque |
|---|---|---|---|
| Backend Rust | 1 | 1 | État temps réel non externalisé |
| CouchDB | 1 | 1 | StatefulSet, scaling manuel |
| Game front | 2 (HPA: 2-10) | 1 | Stateless, scalable |
| Admin front | 2 (HPA: 2-5) | 1 | Stateless, scalable |
| Buzzer front | 2 (HPA: 2-10) | 1 | Stateless, scalable |

---

## Variables d'environnement clés

| Variable | Description | Scope |
|---|---|---|
| `PORT` | Port HTTP backend (`8080`) | Backend |
| `NEON_STORE` | Moteur de stockage (`couch`) | Backend |
| `COUCH_BASE_URL` | URL interne CouchDB | Backend |
| `COUCH_DB` | Nom de la base (`neon_beat`) | Backend |
| `RUST_LOG` | Niveau de log Rust (`info`) | Backend |
| `COUCH_USERNAME` | Identifiant CouchDB (via Secret) | Backend |
| `COUCH_PASSWORD` | Mot de passe CouchDB (via Secret) | Backend |
| `VITE_API_BASE_URL` | URL API pour les frontends | Frontends (build-time) |
| `PUBLIC_APP_URL` | URL publique des frontends | Frontends |

> ⚠️ Les variables `VITE_*` sont injectées au build. Les images frontends sont
> construites par environnement ou doivent supporter une configuration runtime.
