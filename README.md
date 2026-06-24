# Neon Beat — Déploiement Kubernetes

Manifestes Kubernetes pour déployer [Neon Beat](https://github.com/neon-beat/) en production et pré-production.

Neon Beat est une application de blind test et de quiz musical temps réel composée d'un backend Rust, de trois frontends React/Vite et d'une base CouchDB.

---

## Sommaire

- [Architecture](#architecture)
- [Prérequis](#prérequis)
- [Structure du dépôt](#structure-du-dépôt)
- [Environnements](#environnements)
- [Installation initiale](#installation-initiale)
- [Déploiement production](#déploiement-production)
- [Déploiement pré-production](#déploiement-pré-production)
- [Gestion des secrets](#gestion-des-secrets)
- [TLS et cert-manager](#tls-et-cert-manager)
- [Autoscaling](#autoscaling)
- [Sauvegardes](#sauvegardes)
- [Commandes utiles](#commandes-utiles)
- [Conventions](#conventions)

---

## Architecture

```
Internet
   │
   ▼
Ingress NGINX (TLS Let's Encrypt)
   │
   ├─── api.neon-beat.example.com ──► neon-beat-back (Rust/Axum, port 8080)
   │                                        │
   │                                        ▼
   │                                  CouchDB (StatefulSet, port 5984)
   │
   └─── neon-beat.example.com
           ├── /admin  ──► neon-beat-admin-front
           ├── /buzzer ──► neon-beat-virtual-buzzer
           └── /       ──► neon-beat-game-front
```

Le backend et les frontends sont sur deux domaines distincts pour éviter les conflits de routage entre les routes API `/admin/**` et le frontend `/admin/`.

Voir [ARCHITECTURE_DEPLOIEMENT_GLOBAL_NEON_BEAT.md](ARCHITECTURE_DEPLOIEMENT_GLOBAL_NEON_BEAT.md) pour l'analyse complète.

---

## Prérequis

| Outil | Version minimale | Rôle |
|---|---|---|
| `kubectl` | 1.28+ | Gestion du cluster |
| Cluster Kubernetes | 1.28+ | — |
| Ingress NGINX | — | Routage HTTP/HTTPS |
| cert-manager | 1.14+ | Certificats TLS automatiques |
| Token API Cloudflare | — | Validation DNS01 Let's Encrypt |

### Vérifier les prérequis

```bash
kubectl cluster-info
kubectl get ingressclass nginx
kubectl get namespace cert-manager
```

---

## Structure du dépôt

```
k8s/
├── namespace.yml                        # Namespace production (neon-beat)
├── setup.sh                             # Script d'initialisation cluster
│
├── cert-manager/
│   ├── cluster-issuer-cloudflare.yml    # ClusterIssuer Let's Encrypt DNS01
│   ├── cloudflare-secret.yml            # Secret token Cloudflare (ne pas committer avec valeur réelle)
│   └── cloudflare-secret.yml.example    # Exemple à adapter
│
├── app/
│   └── ingress.yml                      # Template Ingress générique (deux domaines)
│
├── prod/                                # Manifestes production
│   ├── configmap.yml                    # Variables non sensibles
│   ├── secret.example.yml               # Exemple de secrets (à ne jamais committer avec vraies valeurs)
│   ├── deployment.yml                   # CouchDB (StatefulSet) + back + 3 frontends
│   ├── service.yml                      # Services ClusterIP
│   ├── ingress.yml                      # Ingress TLS prod
│   ├── hpa.yml                          # HorizontalPodAutoscaler (frontends uniquement)
│   ├── network-policy.yml               # Isolation réseau (default-deny)
│   ├── pdb.yml                          # PodDisruptionBudget
│   └── backup-cronjob.yml               # Sauvegarde CouchDB quotidienne
│
└── preprod/                             # Manifestes pré-production (parité prod, ressources réduites)
    ├── namespace.yml                    # Namespace preprod (neon-beat-preprod)
    ├── configmap.yml
    ├── secret.example.yml
    ├── deployment.yml
    ├── service.yml
    └── ingress.yml
```

---

## Environnements

| Environnement | Namespace | Domaine API | Domaine frontend |
|---|---|---|---|
| Production | `neon-beat` | `api.neon-beat.example.com` | `neon-beat.example.com` |
| Pré-production | `neon-beat-preprod` | `preprod-api.neon-beat.example.com` | `preprod.neon-beat.example.com` |

> Remplacer `neon-beat.example.com` par votre domaine réel dans les fichiers `configmap.yml` et `ingress.yml`.

---

## Installation initiale

Le script `setup.sh` applique dans l'ordre : namespace, ClusterIssuer cert-manager, Ingress générique.

```bash
bash k8s/setup.sh \
  --email votre@email.com \
  --api-domain api.neon-beat.example.com \
  --front-domain neon-beat.example.com
```

Ce script **ne déploie pas les workloads** — ceux-ci sont gérés séparément (voir sections suivantes).

### Étapes manuelles avant le script

**1. Créer le secret Cloudflare** (token avec permission `Zone:DNS:Edit`) :

```bash
# Encoder le token en base64
echo -n "votre-token-cloudflare" | base64

# Editer k8s/cert-manager/cloudflare-secret.yml avec la valeur encodée, puis :
kubectl apply -f k8s/cert-manager/cloudflare-secret.yml
```

**2. Lancer le script d'initialisation :**

```bash
bash k8s/setup.sh \
  --email votre@email.com \
  --api-domain api.neon-beat.example.com \
  --front-domain neon-beat.example.com
```

**3. Vérifier que les ClusterIssuers sont prêts :**

```bash
kubectl get clusterissuer
# READY doit être True pour letsencrypt-prod-cloudflare
```

---

## Déploiement production

### 1. Créer le secret CouchDB

```bash
kubectl create secret generic neon-beat-prod-secrets \
  --namespace neon-beat \
  --from-literal=COUCH_USERNAME=admin \
  --from-literal=COUCH_PASSWORD='<mot-de-passe-fort>'
```

### 2. Adapter la configuration

Editer `k8s/prod/configmap.yml` pour remplacer les domaines exemple :

```yaml
VITE_API_BASE_URL: "https://api.votre-domaine.com"
PUBLIC_APP_URL: "https://votre-domaine.com"
```

Editer `k8s/prod/ingress.yml` pour remplacer `api.neon-beat.example.com` et `neon-beat.example.com`.

### 3. Appliquer les manifestes

```bash
# ConfigMap et Ingress
kubectl apply -f k8s/prod/configmap.yml
kubectl apply -f k8s/prod/ingress.yml

# Workloads (CouchDB + backend + frontends)
kubectl apply -f k8s/prod/deployment.yml
kubectl apply -f k8s/prod/service.yml

# Sécurité et résilience
kubectl apply -f k8s/prod/network-policy.yml
kubectl apply -f k8s/prod/pdb.yml
kubectl apply -f k8s/prod/hpa.yml

# Sauvegardes
kubectl apply -f k8s/prod/backup-cronjob.yml
```

Ou tout en une commande :

```bash
kubectl apply -f k8s/prod/
```

### 4. Vérifier le déploiement

```bash
kubectl get pods -n neon-beat
kubectl get ingress -n neon-beat
kubectl get certificate -n neon-beat
```

Tous les pods doivent être `Running` et les certificats `Ready` avant de tester.

---

## Déploiement pré-production

### 1. Créer le secret CouchDB preprod

```bash
kubectl create secret generic neon-beat-preprod-secrets \
  --namespace neon-beat-preprod \
  --from-literal=COUCH_USERNAME=admin \
  --from-literal=COUCH_PASSWORD='<mot-de-passe-preprod>'
```

### 2. Appliquer

```bash
kubectl apply -f k8s/preprod/namespace.yml
kubectl apply -f k8s/preprod/
```

---

## Gestion des secrets

Les fichiers `secret.example.yml` sont des **modèles documentaires** — ne jamais committer de valeurs réelles.

### Méthode recommandée : kubectl create secret

```bash
kubectl create secret generic neon-beat-prod-secrets \
  --namespace neon-beat \
  --from-literal=COUCH_USERNAME=admin \
  --from-literal=COUCH_PASSWORD='<password>' \
  --dry-run=client -o yaml | kubectl apply -f -
```

### Alternatives pour un environnement de production robuste

| Solution | Usage |
|---|---|
| [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) | Chiffrement des secrets dans le dépôt Git |
| [External Secrets Operator](https://external-secrets.io) | Injection depuis Vault, AWS SSM, Azure Key Vault |
| Secret Kubernetes standard | Suffisant pour un TP ou un cluster privé |

### Secret Cloudflare (cert-manager)

```bash
kubectl create secret generic cloudflare-api-token \
  --namespace cert-manager \
  --from-literal=api-token='<token-cloudflare>'
```

---

## TLS et cert-manager

Les certificats sont gérés automatiquement par cert-manager via la validation DNS01 Cloudflare.

Deux ClusterIssuers sont disponibles :

| Issuer | Usage |
|---|---|
| `letsencrypt-staging-cloudflare` | Tests — certificats non valides mais sans limite de taux |
| `letsencrypt-prod-cloudflare` | Production — certificats valides |

> Tester avec `staging` avant de passer en `prod` pour éviter les rate limits Let's Encrypt.

Pour changer d'issuer sur un Ingress :

```yaml
annotations:
  cert-manager.io/cluster-issuer: letsencrypt-staging-cloudflare  # ou letsencrypt-prod-cloudflare
```

Vérifier l'état d'un certificat :

```bash
kubectl describe certificate neon-beat-prod-api-tls -n neon-beat
kubectl get certificaterequest -n neon-beat
```

---

## Autoscaling

L'autoscaling est configuré **uniquement sur les frontends** (stateless). Le backend conserve `replicas: 1` tant que l'état de partie est en mémoire — le scaler sans event bus (Redis/NATS) provoquerait des désynchronisations.

| Composant | Min | Max | Seuil CPU |
|---|---|---|---|
| `neon-beat-game-front` | 2 | 10 | 70 % |
| `neon-beat-admin-front` | 2 | 5 | 70 % |
| `neon-beat-virtual-buzzer` | 2 | 10 | 70 % |

Vérifier l'état du HPA :

```bash
kubectl get hpa -n neon-beat
```

---

## Sauvegardes

Un CronJob s'exécute chaque nuit à **02h00 UTC** et dump la base CouchDB en JSON dans un PersistentVolume.

```bash
# Voir l'historique des jobs de sauvegarde
kubectl get jobs -n neon-beat -l app.kubernetes.io/name=neon-beat-backup

# Logs du dernier backup
kubectl logs -n neon-beat \
  $(kubectl get pods -n neon-beat -l app.kubernetes.io/name=neon-beat-backup \
    --sort-by=.metadata.creationTimestamp -o name | tail -1)

# Lancer un backup manuel immédiat
kubectl create job --from=cronjob/neon-beat-prod-couchdb-backup \
  neon-beat-backup-manual-$(date +%Y%m%d) \
  -n neon-beat
```

Les sauvegardes sont conservées **7 jours** (rotation automatique). Le PVC `neon-beat-prod-backup-pvc` stocke les fichiers JSON dans `/backup/`.

---

## Commandes utiles

### Etat général

```bash
# Vue d'ensemble de tous les pods
kubectl get pods -n neon-beat -o wide

# Pods preprod
kubectl get pods -n neon-beat-preprod

# Logs backend en temps réel
kubectl logs -f -n neon-beat \
  -l app.kubernetes.io/name=neon-beat-back

# Logs CouchDB
kubectl logs -f -n neon-beat \
  -l app.kubernetes.io/name=couchdb
```

### Mettre à jour une image (rolling update)

```bash
# Mettre à jour le backend
kubectl set image deployment/neon-beat-prod-back \
  backend=ghcr.io/neon-beat/neon-beat-back:nouvelle-version \
  -n neon-beat

# Suivre le rollout
kubectl rollout status deployment/neon-beat-prod-back -n neon-beat
```

### Rollback

```bash
kubectl rollout undo deployment/neon-beat-prod-back -n neon-beat
```

### Accès direct à CouchDB (port-forward)

```bash
kubectl port-forward svc/neon-beat-prod-couchdb 5984:5984 -n neon-beat
# Puis ouvrir http://localhost:5984/_utils
```

### Accès direct au backend (port-forward)

```bash
kubectl port-forward svc/neon-beat-prod-back 8080:80 -n neon-beat
# Puis tester http://localhost:8080/healthcheck
```

### Supprimer et recréer CouchDB (données perdues)

```bash
# Attention : supprime le PVC et toutes les données
kubectl delete statefulset neon-beat-prod-couchdb -n neon-beat
kubectl delete pvc couchdb-data-neon-beat-prod-couchdb-0 -n neon-beat
kubectl apply -f k8s/prod/deployment.yml
```

---

## Conventions

- **Nommage** : `neon-beat-{env}-{composant}` — ex : `neon-beat-prod-back`
- **Labels obligatoires** sur chaque ressource :
  ```yaml
  app.kubernetes.io/name: {composant}
  app.kubernetes.io/part-of: neon-beat
  app.kubernetes.io/instance: {prod|preprod}
  ```
- **Secrets** : jamais de valeur réelle dans le dépôt — uniquement des `.example.yml`
- **Backend replicas** : rester à `1` jusqu'à l'intégration d'un event bus Redis/NATS
- **Parité prod/preprod** : même structure de fichiers, ressources réduites en preprod

Voir [.agents/CONVENTIONS.md](.agents/CONVENTIONS.md) pour le détail complet des règles.
