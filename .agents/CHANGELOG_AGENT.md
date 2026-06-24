# CHANGELOG_AGENT.md — État actuel du projet

## État global des livrables

### Document d'architecture (PDF)

| Critère TP | Section | Statut |
|---|---|---|
| Analyse de la problématique (1pt) | §2 | ✅ Couvert |
| Identifier les points critiques (2pts) | §3 | ✅ Couvert |
| Utiliser les bons composants k8s (2pts) | §4.4 | ✅ Couvert |
| Schémas d'architectures (5pts) | §5 | ✅ 4 schémas présents |
| Scalabilité et résilience (3pts) | §6 | ✅ Couvert |
| Sécurité (3pts) | §7 | ✅ Couvert |
| Monitoring (3pts) | §8 | ✅ Couvert |
| Gestion du temps réel (1pt) | §9 | ✅ Couvert |

### Manifestes Kubernetes (ZIP YAML)

| Fichier | Env | Statut |
|---|---|---|
| `namespace.yml` | prod | ✅ |
| `preprod/namespace.yml` | preprod | ✅ |
| `prod/configmap.yml` | prod | ✅ |
| `preprod/configmap.yml` | preprod | ✅ |
| `prod/secret.example.yml` | prod | ✅ |
| `preprod/secret.example.yml` | preprod | ✅ |
| `prod/deployment.yml` | prod | ✅ CouchDB StatefulSet + back + 3 frontends |
| `preprod/deployment.yml` | preprod | ✅ Même structure, ressources réduites |
| `prod/service.yml` | prod | ✅ |
| `preprod/service.yml` | preprod | ✅ |
| `prod/ingress.yml` | prod | ✅ TLS + annotations SSE/WS |
| `preprod/ingress.yml` | preprod | ✅ |
| `cert-manager/cluster-issuer-cloudflare.yml` | cluster | ✅ |
| `cert-manager/cloudflare-secret.yml` | cluster | ✅ |
| `app/ingress.yml` | prod | ✅ Template générique |
| `setup.sh` | — | ✅ |
| `prod/hpa.yml` | prod | ✅ HPA frontends (ajouté 2026-06-24) |
| `prod/network-policy.yml` | prod | ✅ Isolation réseau (ajouté 2026-06-24) |
| `prod/pdb.yml` | prod | ✅ PDB frontends (ajouté 2026-06-24) |
| `prod/backup-cronjob.yml` | prod | ✅ Backup CouchDB quotidien (ajouté 2026-06-24) |

---

## Historique

### 2026-06-24 — Session Claude Code : complétion TP M2 DEV CLOUD
- Analyse du sujet TP (PDF)
- Identification des fichiers YAML manquants (HPA, NetworkPolicy, PDB, CronJob)
- Création du dossier `.agents/` avec AGENT.md, CONVENTIONS.md, CHANGELOG_AGENT.md, DECISIONS.md
- Création de `k8s/prod/hpa.yml` : autoscaling des 3 frontends (CPU-based)
- Création de `k8s/prod/network-policy.yml` : default-deny + règles d'accès minimaux
- Création de `k8s/prod/pdb.yml` : PDB pour les 3 frontends (minAvailable: 1)
- Création de `k8s/prod/backup-cronjob.yml` : backup CouchDB quotidien à 02h00
- Mise à jour de `ARCHITECTURE_DEPLOIEMENT_GLOBAL_NEON_BEAT.md` : section 10 remaniée
  pour refléter la structure réelle du ZIP

### Session initiale (date inconnue)
- Création des manifestes prod et preprod (namespace, configmap, deployment, service, ingress, secret.example)
- Mise en place de cert-manager avec Cloudflare DNS01 (migration depuis Infomaniak)
- Création du script `setup.sh`
- Rédaction du document d'architecture complet (sections 1-13)
