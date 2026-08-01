# Multibot Chatless + Bridge — Roadmap de reprise

Statut : roadmap active issue de l'audit initial v1c du 1er août 2026.  
Dernière mise à jour : 01/08/2026 par `patch-multibot-docs-cleanup-roadmap-v1-2026-08-01-162227`.  
Cette roadmap est la source de vérité active du projet. Les anciens trackers et le fichier `TODO.md` ont été consolidés ici.

## Baseline auditée

- Addon : `L:\ChromieCraft_3.3.5a\Interface\AddOns\MultiBot`
- Bridge : `L:\AC_PB\azerothcore-wotlk\modules\mod-multibot-bridge`
- Playerbots : `L:\AC_PB\azerothcore-wotlk\modules\mod-playerbots` — lecture seule stricte
- Addon : 342 fichiers, dépôt Git propre, branche `main`, commit `ef341a4fb4b39f04a677e871b6b31b5280a38789`
- AzerothCore : dépôt Git propre, branche `Playerbot`, commit `190184a04539937a617bf033e39378196c0c63f5`
- Bridge : 7 fichiers, logique principale concentrée dans `src/MultiBotBridge.cpp`
- Communication actuelle : bridge-first pour les principaux rafraîchissements UI, mais 162 occurrences `SendChatMessage` restent à classifier côté addon.
- Fallback automatique legacy désactivé par défaut : `MultiBot.allowLegacyChatFallback = false`.

## Règles de progression

Audit → Analyse → Proposition → Validation utilisateur → Patch minimal → Vérifications → Compilation → Tests en jeu → Audit final → Archivage

- Aucun patch à l'aveugle.
- Aucun changement dans `mod-playerbots`.
- Un patch = un objectif.
- Rollback et hashes obligatoires.
- Ne jamais ajouter d'exécuteur bridge générique acceptant une commande Playerbots arbitraire.

## Phase 0 — Assainissement documentaire — TERMINÉE

Objectif : repartir avec une documentation courte, actuelle et non contradictoire.

Réalisé par `patch-multibot-docs-cleanup-roadmap-v1-2026-08-01-162227` :

- les 18 anciens trackers ont été sauvegardés puis retirés du dossier actif ;
- `TODO.md` a été consolidé dans cette roadmap puis retiré ;
- `docs/ROADMAP.md` est la source de vérité active ;
- `docs/DEBUG_RUNBOOK.md` consolide le guide de debug et d'observabilité ;
- le README référence les deux documents actifs ;
- le package contient un rollback intégral et vérifiable.

Critère de sortie : phase validée par `verify.ps1`, avec hashes post-patch conformes et aucun ancien document actif.

## Phase 1 — Baseline de compilation et tests de non-régression

Objectif : prouver le fonctionnement de l'état actuel avant toute correction source.

### Serveur / bridge

- Compiler l'état Git audité sans modification.
- Vérifier le chargement de `mod-multibot-bridge` et de sa configuration.
- Vérifier `HELLO/HELLO_ACK`, `PING/PONG`, erreurs et logs.

### Addon / jeu

Tester avec zéro, un et plusieurs bots :

- chargement initial, `/reload`, déconnexion/reconnexion ;
- bots personnels, AddClass bots et randombots groupés ;
- roster, states, details, stats et PVP stats ;
- inventaire, banque bot, banque de guilde, vendeur ;
- spellbook, talents, glyphes et outfits ;
- quêtes, objets de jeu, character info, réputations, monnaies ;
- recettes, craft et trainer ;
- RTI, Pull Control, Combat Strategies, Disperse et Loot Rules.

Mesurer le chat visible avec `MultiBot.allowLegacyChatFallback = false`.

Critère de sortie : matrice de tests remplie, baseline compilée, bugs reproductibles séparés des impressions anciennes.

## Phase 2 — Durcissement du bridge

Objectif : traiter les risques de sécurité et de blocage avant de développer de nouvelles fonctions.

- Ajouter des parseurs numériques stricts : chaîne entière valide, absence de signe négatif, contrôle d'overflow et bornes métier.
- Borner la taille totale des messages et la longueur de chaque champ.
- Borner les quantités d'actions item, notamment l'achat vendeur.
- Ajouter un rate limiting par joueur et par famille de requêtes `HELLO`, `PING`, `GET` et `RUN`.
- Revalider joueur, session, carte, propriété du bot, proximité PNJ et état du bot au moment de l'exécution.
- Borner les logs et désactiver les logs console par défaut même si la configuration est absente.
- Retourner des erreurs structurées et distinctes pour message malformé, limite dépassée, permission refusée et état incompatible.

Critère de sortie : patch compilé, tests de messages malformés/volumineux, aucune boucle longue pilotable par le client.

## Phase 3 — Stabilisation du protocole addon/bridge

Objectif : fiabiliser les transactions et supprimer les ambiguïtés d'ACK.

- Documenter chaque commande `GET` et `RUN`, ses champs, bornes, réponses et erreurs.
- Identifier les payloads non bornés ; fragmenter notamment le roster si les limites client l'exigent.
- Uniformiser les séquences `BEGIN/ITEM/END` et les tokens de transaction.
- Ajouter timeout, annulation, déduplication et gestion des réponses hors ordre côté addon.
- Distinguer : requête reçue, commande transmise à Playerbots et résultat effectivement vérifié.
- Vérifier perte, duplication, réponses tardives, changement de carte et déconnexion du bot.

Critère de sortie : protocole documenté, transactions déterministes, aucune frame bloquée sur une requête perdue.

## Phase 4 — Corrections runtime prioritaires

Traiter un problème par patch, dans cet ordre :

1. Reconnexion : bots inconnus dans l'UI de groupe Blizzard jusqu'à `/reload`.
2. AddClass bots créés ou sélectionnés au niveau 1 pour un joueur niveau 80.
3. Vérification fonctionnelle de Disperse.
4. Lenteur de l'affichage des glyphes et recentrage des icônes.
5. ID de quête affiché temporairement à la place du titre ; étudier l'avancement de quête par bot.
6. Inventaire au-delà de 16 emplacements.
7. Outfit avec deux armes à deux mains.
8. Compatibilité de l'UI talents/glyphes avec la configuration actuelle.
9. Quick Hunter/Shaman : croix stable et absence de quick bars pour un joueur humain.
10. Raidus : rafraîchissement ouverture/fermeture et purge des bots inconnus/SavedVariables.
11. Respect global du frame strata configuré.
12. Harmonisation de la frame PVP Stats.

Critère de sortie : chaque correction possède reproduction avant, test après et non-régression ciblée.

## Phase 5 — Migration des commandes chat restantes

Objectif : réduire le chat par familles fonctionnelles, sans toucher à Playerbots.

Avant chaque migration, classer l'occurrence `SendChatMessage` comme :

- commande manuelle volontaire ;
- fallback diagnostic ;
- message d'information ;
- mécanisme UI à migrer ;
- code mort à supprimer.

Ordre recommandé :

1. `s *` — vente générale bridge-first.
2. `s vendor` — vente vendeur bridge-first, sans whisper item par item.
3. `open items` — ouverture de conteneurs bridge-first.
4. `roll` et `roll [item]`.
5. Enchantement d'objet, après validation du flux trade/cast disponible sans modification de Playerbots.
6. Ajout/retrait d'items précis dans les règles de loot.
7. Décision sur `Quest`/`Skill` versus `Disenchant`, sans inventer de stratégie absente de Playerbots.
8. Ordres collectifs `follow`, `attack`, `stay` seulement après validation manuelle exacte des sélecteurs Playerbots ; ne pas réintroduire `RUN~ORDER` générique.

Les commandes informatives `who`, `co ?`, `nc ?` et `ss ?` restent manuelles tant qu'aucune UI structurée ne les remplace.

Critère de sortie : chaque famille migrée fonctionne bridge-first et ne génère plus de réponse chat automatique.

## Phase 6 — Backlog UI et fonctions secondaires

À traiter après sécurité, protocole et bugs prioritaires :

- argent de guilde dans la frame banque de guilde ;
- options de taille des icônes MainBar et Quick Bars ;
- options de déplacement restantes ;
- traductions AceLocale des tooltips Quick Hunter/Shaman ;
- chargement des skins de familiers chasseur ;
- harmonisation de la frame Reward ;
- amélioration Loot Master : tri d'éligibilité, filtres de rôle/classe, recommandation, avertissements, mode compact, historique et debug discret.

Ces fonctions doivent rester séparées des patches de correction et de sécurité.

## Phase 7 — Finalisation

- Compilation complète sans erreur ni nouvel avertissement lié au bridge.
- Tests en jeu complets avec zéro/un/plusieurs bots et groupes importants.
- Audit final des dépendances chat, de la sécurité, des performances et des logs.
- Nettoyage des fallbacks legacy devenus inutiles seulement après preuve de non-régression.
- Mise à jour du README et de la roadmap.
- Création d'un checkpoint et d'une archive ZIP avec manifeste SHA-256 et rollback vérifié.

Critère de sortie : version stabilisée, documentée et reproductible du projet Multibot Chatless + Bridge.
