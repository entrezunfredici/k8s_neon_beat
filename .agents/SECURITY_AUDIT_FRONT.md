# Audit sécurité & architecture — Frontend admin

> Fichier de référence issu de l'audit de `GameManagementContext.tsx`.
> Il documente les problèmes identifiés et les méthodes de correction à appliquer,
> sans modifier le code source. Chaque entrée est autonome et actionnable.

---

## Méthodologie d'audit appliquée

L'analyse combine deux grilles de lecture complémentaires :

- **Architecture** : principes SOLID (SRP, DIP), patterns React (Context, hooks),
  gestion d'état, couplage, lisibilité.
- **OWASP Top 10** : les 10 catégories de vulnérabilités web les plus critiques,
  appliquées ici au contexte frontend React / SSE.

---

## Problèmes identifiés et méthodes de correction

---

### P01 — Bug : `canPairTeams` toujours `true`

**Fichier** : `GameManagementContext.tsx` lignes 368–372  
**Catégorie** : Architecture — logique métier incorrecte  
**Sévérité** : 🔴 Critique (fonctionnel)

**Problème :**
```typescript
const canPairTeams = useCallback((): boolean => {
  if (!gameState) return false;
  if (gameState === GameState.PREP_READY) return true;
  return true; // ← toujours true si gameState est défini
}, [gameState]);
```
Le guard retourne `true` pour n'importe quel état de jeu, y compris `PLAYING` ou `PAUSED`.
Le pairing peut donc être déclenché pendant une partie active.

**Méthode de correction :**
Définir explicitement la liste des états autorisant le pairing, et retourner `false` par défaut :
```typescript
const canPairTeams = useCallback((): boolean => {
  const allowed: GameState[] = [GameState.PREP_READY, GameState.PAIRING];
  return allowed.includes(gameState as GameState);
}, [gameState]);
```
Principe : whitelist explicite plutôt que fallback permissif.

---

### P02 — Crash : handlers SSE sans try/catch

**Fichier** : `GameManagementContext.tsx` lignes 297–365  
**Catégorie** : OWASP A03 — Injection / robustesse  
**Sévérité** : 🔴 Critique (crash runtime)

**Problème :**
```typescript
const onPhaseChanged = useCallback((event: MessageEvent) => {
  const data = JSON.parse(event.data); // crash si JSON malformé
  const { phase } = data;
  setGameState(phase as GameState);    // cast aveugle
}, [messageApi, teams]);
```
Un message SSE malformé (backend bugué, coupure réseau partielle, MITM en dev HTTP)
provoque une exception non capturée qui déstabilise le contexte React entier.

**Méthode de correction :**

**Étape 1** — Wrapper générique pour parser + valider les events SSE :
```typescript
function parseSseEvent<T>(event: MessageEvent): T | null {
  try {
    return JSON.parse(event.data) as T;
  } catch {
    console.error('[SSE] Invalid JSON payload:', event.data);
    return null;
  }
}
```

**Étape 2** — Valider les valeurs métier avant usage :
```typescript
function isValidGameState(value: unknown): value is GameState {
  return Object.values(GameState).includes(value as GameState);
}
```

**Étape 3** — Appliquer dans chaque handler :
```typescript
const onPhaseChanged = useCallback((event: MessageEvent) => {
  const data = parseSseEvent<{ phase: unknown; question?: Question }>(event);
  if (!data) return;
  if (!isValidGameState(data.phase)) {
    console.error('[SSE] Unknown phase:', data.phase);
    return;
  }
  setGameState(data.phase);
  // ...
}, [messageApi, teams]);
```

---

### P03 — Crash : mutations asynchrones sans try/catch

**Fichier** : `GameManagementContext.tsx` lignes 208–226  
**Catégorie** : Architecture — gestion d'erreur  
**Sévérité** : 🔴 Critique (crash silencieux)

**Problème :**
```typescript
const importQuestionsSequence = useCallback(async (payload) => {
  await postQuestionsSequence(payload); // pas de try/catch
  messageApi.success('...');
  loadQuestionsSequences();
}, [...]);
```
Si l'API retourne une erreur, l'exception se propage jusqu'au composant appelant
sans message utilisateur. Si le composant ne gère pas non plus l'erreur, elle
remonte vers le gestionnaire global (ou crashe silencieusement).

**Méthode de correction :**
Appliquer le même pattern que les actions déjà correctes (`loadTeams`, `markAnswerFound`) :
```typescript
const importQuestionsSequence = useCallback(async (payload) => {
  try {
    await postQuestionsSequence(payload);
    if (import.meta.env.VITE_DEBUG_LEVEL === 'info')
      messageApi.success('Questions sequence imported successfully');
    loadQuestionsSequences();
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Import failed';
    if (import.meta.env.VITE_DEBUG_LEVEL !== 'none')
      messageApi.error(`Error importing questions sequence: ${message}`);
  }
}, [postQuestionsSequence, messageApi, loadQuestionsSequences]);
```
Même correction à appliquer à `importLegacyGameWithPlaylist` et `createGame`.

---

### P04 — Sécurité : cast `as GameState` sans validation (OWASP A08)

**Fichier** : `GameManagementContext.tsx` lignes 322, 453  
**Catégorie** : OWASP A08 — Intégrité des données logicielles  
**Sévérité** : 🟠 Majeur

**Problème :**
```typescript
setGameState(phase as GameState);            // ligne 322
setGameState(phaseData.phase as GameState);  // ligne 453
```
Le cast TypeScript `as` est une assertion au compile-time — elle n'existe plus à
l'exécution. Si le backend envoie `"unknown_phase"`, la machine d'état React reçoit
une valeur non prévue. Tous les guards (`canStartGame`, `canPauseGame`…) peuvent
alors retourner `false` de façon inattendue, bloquant l'interface.

**Méthode de correction :**
Utiliser la fonction de validation définie en P02 (`isValidGameState`) :
```typescript
const rawPhase = phaseData.phase;
if (!isValidGameState(rawPhase)) {
  console.error('[Init] Unknown phase received:', rawPhase);
  return;
}
setGameState(rawPhase);
```
Même correction pour le cas SSE ligne 322.

---

### P05 — Sécurité : `unknown[]` sur les questions (OWASP A01)

**Fichier** : `GameManagementContext.tsx` ligne 121  
**Catégorie** : OWASP A01 — Contrôle d'accès / validation des entrées  
**Sévérité** : 🟠 Majeur

**Problème :**
```typescript
importQuestionsSequence: (payload: { name: string; questions: unknown[] })
```
`unknown[]` désactive la vérification TypeScript sur la structure des questions.
Un import malformé (JSON édité manuellement, fichier corrompu) passe le compilateur
et arrive au backend sans validation côté client.

**Méthode de correction :**

**Option A — Typage fort** (si le schéma est stable) :
```typescript
importQuestionsSequence: (payload: { name: string; questions: Question[] })
```

**Option B — Validation runtime avec Zod** (recommandé pour les imports JSON) :
```typescript
import { z } from 'zod';

const BlindTestQuestionSchema = z.object({
  type: z.literal('blind_test'),
  id: z.number(),
  starts_at_ms: z.number(),
  guess_duration_ms: z.number(),
  url: z.string().url(),
  answers: z.record(z.object({ key: z.string(), value: z.string(), points: z.number(), is_bonus: z.boolean() })),
});

// Valider avant d'appeler l'API
const result = QuestionSchema.array().safeParse(rawQuestions);
if (!result.success) {
  messageApi.error('Format de questions invalide');
  return;
}
```
Zod est la bibliothèque de validation de schéma la plus utilisée dans l'écosystème TypeScript/React.

---

### P06 — Architecture : setters bruts exposés dans l'API publique

**Fichier** : `GameManagementContext.tsx` lignes 110–111  
**Catégorie** : Architecture — encapsulation  
**Sévérité** : 🟡 Moyen

**Problème :**
```typescript
setGame: React.Dispatch<React.SetStateAction<Game | undefined>>;
setTeams: React.Dispatch<React.SetStateAction<Team[] | undefined>>;
```
N'importe quel composant enfant peut écrire directement dans `game` ou `teams`
sans passer par la logique métier ni déclencher d'effets de bord attendus
(ex : recharger les équipes après changement de partie).

**Méthode de correction :**
Encapsuler dans des fonctions typées avec logique associée :
```typescript
// À la place de setGame exposé brut :
const selectGame = useCallback((newGame: Game | undefined) => {
  setGame(newGame);
  if (newGame) loadTeams();
}, [loadTeams]);
```
Supprimer `setGame` et `setTeams` de l'interface publique du contexte.

---

### P07 — Architecture : état `buzzers` mort

**Fichier** : `GameManagementContext.tsx` ligne 171  
**Catégorie** : Architecture — dead code  
**Sévérité** : 🟡 Mineur

**Problème :**
```typescript
const [buzzers] = useState<Buzzer[]>([]);
```
Pas de setter, jamais peuplé, aucun event SSE ne l'alimente.

**Méthode de correction :**
Deux options selon l'intention :
- Si la liste des buzzers doit venir du SSE : ajouter un handler sur un event
  `buzzer.connected` / `buzzer.disconnected` et exposer le setter interne.
- Si la liste n'est pas utilisée : supprimer `buzzers` de l'état et de l'interface publique.

---

### P08 — Architecture : God Context — à découper (SRP)

**Fichier** : `GameManagementContext.tsx` global  
**Catégorie** : Architecture — Single Responsibility Principle  
**Sévérité** : 🟡 Mineur (dette technique)

**Problème :**
Le contexte gère simultanément : cycle de vie de partie, équipes, questions, buzzers,
pairing, SSE, scores, transitions d'état. Toute modification d'une partie impacte le
contexte entier.

**Méthode de correction — découpage proposé :**

| Nouveau contexte | Responsabilité |
|---|---|
| `GameLifecycleContext` | `game`, `gameState`, guards `canXxx`, `createGame`, `loadSelectedGame`, `resetWholeGame` |
| `TeamContext` | `teams`, `currentTeamPairing`, `createTeamWithoutBuzzer`, `grantTeamPoints` |
| `QuestionContext` | `question`, `answersFound`, `hintsFound`, `markAnswerFound`, `resetFoundAnswers` |
| `SseContext` | connexion SSE, dispatch des événements vers les autres contextes |

`SseContext` publie les events ; les autres contextes s'y abonnent via callbacks.
Cela supprime aussi le problème de fermeture stale sur `teams` dans `onPhaseChanged`
(P02 connexe) — chaque contexte gère ses propres subscriptions.

---

## Références

| Standard | Lien |
|---|---|
| OWASP Top 10 | https://owasp.org/Top10/ |
| OWASP A03 Injection | https://owasp.org/Top10/A03_2021-Injection/ |
| OWASP A08 Intégrité | https://owasp.org/Top10/A08_2021-Software_and_Data_Integrity_Failures/ |
| Zod — validation TypeScript | https://zod.dev |
| React Context best practices | https://react.dev/learn/scaling-up-with-reducer-and-context |
| useCallback / stale closures | https://react.dev/reference/react/useCallback |
