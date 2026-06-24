# AGENT.md — Comportement général pour Claude Code

## Rôle

Ce dépôt contient les manifestes Kubernetes pour déployer Neon Beat en production et
pré-production, ainsi que le document d'architecture associé (livrable TP M2 DEV CLOUD).

L'agent maintient la cohérence entre les fichiers YAML du dossier `k8s/` et le document
`ARCHITECTURE_DEPLOIEMENT_GLOBAL_NEON_BEAT.md`.

---

## Standards YAML

- Indentation : **2 espaces**
- Convention de nommage : `neon-beat-{env}-{composant}` (ex : `neon-beat-prod-back`)
- Labels obligatoires sur chaque ressource :
  ```yaml
  app.kubernetes.io/name: {composant}
  app.kubernetes.io/part-of: neon-beat
  app.kubernetes.io/instance: {prod|preprod}
  ```
- `namespace` explicite sur chaque ressource
- En-tête de commentaire descriptif sur les fichiers contenant plusieurs ressources

---

## Checklist de livraison YAML

Avant de considérer un fichier YAML livré :

- [ ] Le `namespace` est défini
- [ ] Les labels standards sont présents
- [ ] Les `readinessProbe` et `livenessProbe` sont définis (pour Deployment/StatefulSet)
- [ ] Les `resources.requests` et `resources.limits` sont définis
- [ ] Les secrets sont référencés via `secretKeyRef`, jamais en clair
- [ ] Les ports sont nommés
- [ ] TLS est activé sur les Ingress
- [ ] Les annotations SSE/WebSocket sont présentes sur l'Ingress backend

---

## Règles générales

- Ne jamais committer de `Secret` avec des valeurs réelles — uniquement des `.example.yml`
- Maintenir la parité prod/preprod (même structure, ressources réduites en preprod)
- Documenter chaque décision structurante dans `.agents/DECISIONS.md`
- Mettre à jour `.agents/CHANGELOG_AGENT.md` après chaque ticket significatif
- Ne pas créer de dépendance externe sans la signaler dans `CONVENTIONS.md`
- Conserver `replicas: 1` pour le backend tant que l'état temps réel n'est pas externalisé

---

## Fichiers de référence à lire en priorité

1. `.agents/CONVENTIONS.md` — stack, nommage, structure des fichiers
2. `.agents/CHANGELOG_AGENT.md` — état actuel, ce qui est livré / manquant
3. `.agents/DECISIONS.md` — décisions techniques déjà prises
