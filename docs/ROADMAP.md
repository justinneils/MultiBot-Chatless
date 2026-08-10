# Multibot Chatless + Bridge — Roadmap de reprise

Statut : roadmap active issue de l'audit initial v1c du 1er août 2026.  
Dernière mise à jour : 08/08/2026 — validation runtime du lot Warlock chatless, diagnostic TEMP_ENCHANT et bascule Firestone/Spellstone bridge-only.
Cette roadmap est la source de vérité active du projet. Les anciens trackers et le fichier `TODO.md` ont été consolidés ici.

## Baseline auditée

- Addon : `L:\ChromieCraft_3.3.5a\Interface\AddOns\MultiBot`
- Bridge : `L:\AC_PB\azerothcore-wotlk\modules\mod-multibot-bridge`
- Playerbots : `L:\AC_PB\azerothcore-wotlk\modules\mod-playerbots` — lecture seule stricte
- Addon : baseline post-PR #51 auditée, dépôt Git propre, branche `main`, commit `270911305acf3e806d389712a34a9433131db981`
- AzerothCore : dépôt Git propre pour les modules bridge/Playerbots audités, branche `Playerbot`, commit `092e9ba6ff8dc6d861dddd1f31baa9d404381a85`
- Bridge : 7 fichiers, logique principale concentrée dans `src/MultiBotBridge.cpp`
- Communication actuelle : bridge-first pour les principaux rafraîchissements UI ; l'audit final du 07/08/2026 relève encore 159 lignes `SendChatMessage` à classifier, dont des reliquats `co/nc` directs dans des contrôles spécialisés.
- Fallback automatique legacy désactivé par défaut : `MultiBot.allowLegacyChatFallback = false`.

## Règles de progression

Audit → Analyse → Proposition → Validation utilisateur → Patch minimal → Vérifications → Compilation → Tests en jeu → Audit final → Archivage

- Aucun patch à l'aveugle.
- Aucun changement dans `mod-playerbots`.
- Un patch = un objectif.
- Rollback et hashes obligatoires.
- Ne jamais ajouter d'exécuteur bridge générique acceptant une commande Playerbots arbitraire.

## Contribution externe Jellypowered — AUDIT AUTORISÉ, INTÉGRATION NON COMMENCÉE

Source reçue le 04/08/2026 :

- auteur : Jellypowered `<Jellypowered@gmail.com>` ;
- commit 1 : `13059a9f334d1e5aaa8560ab29a1814e48b07054` ;
- commit 2 : `7ff1347535be6d5a3256d933731c11c4b3f3b38e` ;
- commit 3 : `04061f084bd189487f1ac0e99892316146f1bea0` ;
- la PR est conservée comme source de recherche et ne doit pas être fusionnée directement dans `main`.

Décision validée :

- auditer la contribution dans un environnement isolé ;
- conserver les parties techniquement sûres et utiles ;
- adapter ou réécrire les parties incompatibles avec notre bridge actuel ;
- intégrer progressivement par patches à objectif unique ;
- ne jamais modifier `mod-playerbots` ;
- ne marquer aucune fonction comme intégrée avant vérification, compilation, tests en jeu et validation explicite de l'utilisateur.

Fonctions candidates, toutes encore au statut `À AUDITER` :

1. helpers de parsing numérique strict et réponses structurées ;
2. inventaire détaillé `INV_BAG`, `INV_ITEM_LOC`, `INV_EQUIP_LOC` ;
3. lectures bulk inventaire et compétences ;
4. équipement d'objet ;
5. abandon et partage de quête ;
6. lancement de sorts ;
7. application de talents ;
8. échange d'objets ;
9. artisanat ciblé ;
10. modifications des transferts banque, banque de guilde et vendeur.

Crédits obligatoires :

- les audits et rapports conservent les trois hashes de commits, le nom et l'adresse de l'auteur ;
- chaque PR intermédiaire indique précisément le code repris, adapté, réécrit ou rejeté ;
- une reprise substantielle de code utilise, lorsque pertinent :
  `Co-authored-by: Jellypowered <Jellypowered@gmail.com>` ;
- une réécriture seulement inspirée mentionne :
  `Design inspired by the Jellypowered bridge contribution.` ;
- les crédits sont préparés pour la PR uniquement après validation des tests en jeu de la partie concernée ;
- aucune attribution ne doit suggérer qu'une fonction non testée ou non intégrée est déjà livrée.

Politique de tests :

- les tests ciblés restent obligatoires après chaque patch ;
- les tests exhaustifs transversaux de toutes les fonctions pourront être exécutés vers la fin du projet ;
- ce report des tests exhaustifs ne permet pas de déclarer une fonction validée avant ses propres tests ciblés.

Statut de reprise : contribution conservée pour un audit/intégration ultérieurs. La prochaine étape immédiate du projet est la migration des reliquats UI `co/nc` encore directs, puis la clôture de la matrice runtime finale STATE/stratégies. L'audit Jellypowered reprendra ensuite selon l'ordre validé.

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

## Validation livrée — Formations chatless — APPLICATION ET CONSULTATION VALIDÉES LE 03/08/2026

Patches fonctionnels validés :

- application : `patch-multibot-formation-chatless-v1c-2026-08-01-181300` ;
- consultation : `patch-multibot-formation-query-chatless-v1-2026-08-03-195340` ;
- localisation : `patch-multibot-formation-query-i18n-v1b-2026-08-03-210300`.

Périmètre validé :

- les clics gauche `arrow`, `queue`, `near`, `melee`, `line`, `circle`, `chaos` et `shield` utilisent désormais `RUN~FORMATION~GROUP` ;
- le bridge applique directement `FormationValue::Load()` sans passer par `HandleCommand()` ni par l'action Playerbots `set formation` ;
- le fonctionnement est validé avec la stratégie `passive`, en groupe et pour l'ensemble des bots contrôlables d'un raid ;
- aucun fichier de `mod-playerbots` n'a été modifié ;
- l'icône de l'addon n'est mise à jour qu'après un `FORMATION_ACK` complet ;
- aucun message `formation ...` n'est envoyé dans PARTY ou RAID pour ces clics ;
- le clic droit utilise `MultiBot.Comm.RequestFormations()` puis `GET~FORMATIONS~GROUP` ;
- le bridge lit la valeur effective de chaque bot avec `FormationValue::Save()` et renvoie `FORMATIONS_BEGIN/ITEM/END` ;
- le résultat est affiché localement, une ligne par bot, dans un tooltip traduit pour les huit locales supportées ;
- aucun message PARTY, RAID, WHISPER ou `TellMaster` n'est produit par la consultation.

Preuves de validation :

- compilation `worldserver` validée par l'utilisateur ;
- audit runtime : `audit-multibot-runtime-tests-v1c-2026-08-03-184046.zip` ;
- SHA-256 de l'audit : `7E3FBD948C51FAE34351B97B416BDFA663061F4577932F6AC251C79ECE933F25` ;
- 11 requêtes `RUN~FORMATION`, 11 réponses `FORMATION_ACK`, 55 applications réussies et 0 échec ;
- les huit formations ont provoqué visuellement le déplacement attendu des bots ;
- l'icône a été mise à jour visuellement sans message chat visible ;
- aucune erreur Lua MultiBot ni ancien blocage `PassiveMultiplier` observé ;
- audit de consultation : `audit-multibot-runtime-tests-v1c-2026-08-03-203219.zip` ;
- SHA-256 de cet audit : `44627A920618C747BD9EEB0384D118FFFA13157828677172E46A642436677CB5` ;
- 9 requêtes `GET~FORMATIONS`, 9 séquences `FORMATIONS_BEGIN/END` et 23 réponses individuelles `FORMATIONS_ITEM` ;
- tooltip local et traductions validés visuellement par l'utilisateur, sans sortie chat.

Reste explicitement hors périmètre :

- la formation Playerbots `far` existe dans le module de référence mais n'est pas exposée par l'interface actuelle.

## Validation intermédiaire — STATE framing + Strategy Mutation — STATIQUE VALIDÉE LE 07/08/2026, RUNTIME FINAL À TERMINER

Baseline intégrée :

- PR #49 : synchronisation bridge, contrôles stratégies, favoris persistants et stabilisation STATE ;
- PR #50 : diagnostics explicites des rejets `RunStrategyCommand` ;
- PR #51 : déduplication mécanique des helpers partagés de workflow roster ;
- addon `main` : `270911305acf3e806d389712a34a9433131db981`.

État STATE validé statiquement :

- capacité `STATE_FRAMING_V1` présente côté addon et bridge ;
- requêtes unitaires `GET~STATE` et globales `GET~STATES` gérées par transactions tokenisées ;
- framing `STATE_BEGIN/STATE_ITEM/STATE_END` et framing global `STATES_BEGIN/.../STATES_END` ;
- `STATE_ABORT` pris en compte comme échec de la requête concernée ;
- timeout par bot à 5 s et timeout global à 15 s ;
- limite de 32 requêtes STATE actives, 128 bots, 256 stratégies par scope, 192 caractères par stratégie et 32768 octets cumulés ;
- nettoyage des transactions sur timeout/erreur/déconnexion ;
- garde d'ordre par bot pour empêcher une réponse ancienne de remplacer un état plus récent.

État mutations stratégies validé statiquement :

- capacité `STRATEGY_MUTATION_V1` présente côté addon et bridge ;
- mutations `co/nc` structurées via `RUN~STRATEGY` pour les chemins utilisant `MultiBot.Comm.RunStrategyCommand()` ;
- résultat serveur via `STRATEGY_ACK` avec compteurs `matched/succeeded/failed` ;
- limites de taille, nombre d'opérations et requêtes actives ;
- timeout à 5 s ;
- neuf diagnostics de rejet explicites ajoutés par F07 ;
- `RunStrategyCommand()` ne contient aucun `SendChatMessage`.

Preuve d'audit final statique :

- archive : `audit-multibot-state-strategy-final-v1-2026-08-07-224000-2026-08-07-224709.zip` ;
- SHA-256 : `B00DBE597F554F9E20F2ABEFDC22097BC2A06DCDD3F07FD9F6522F98A7DF38DA` ;
- 57 contrôles, 0 échec ;
- addon, bridge et `mod-playerbots` ont des empreintes avant/après identiques pendant l'audit ;
- `mod-playerbots` reste strictement en lecture seule.

Reste à terminer avant de fermer définitivement ce bloc :

- le lot Warlock Stones/Soulstones/Pets/Curses est validé au 08/08/2026 et ne fait plus partie des reliquats `co/nc` prioritaires ;
- exécuter/consolider la matrice runtime finale : zéro/un/plusieurs bots, listes longues, fragment manquant/dupliqué/désordonné, réponse tardive, timeouts, déconnexion en cours de transaction, mutations valides/invalides, bot absent, plusieurs bots, smoke test toutes classes, zéro erreur Lua, contrôle chat et logs ;
- classifier puis migrer les autres familles legacy réellement automatiques avant de déclarer le projet entièrement chatless.

## Validation livrée — Sélecteurs Warlock chatless + Stones — VALIDÉE LE 08/08/2026

Périmètre addon validé :

- les sélecteurs Warlock Stones, Soulstones, Pets et Curses ne contiennent plus de `SendChatMessage` direct pour leurs mutations `co/nc` ; ils passent par `MultiBot.ActionToTarget()` puis `STRATEGY_MUTATION_V1` / `RUN~STRATEGY` lorsque le bridge est disponible ;
- `MultiBot.ActionToTarget()` distingue désormais le transport `bridge` du fallback `chat` ; avec le bridge, les sélecteurs n'appliquent plus d'état local optimiste et attendent l'état serveur autoritatif ; le fallback chat conserve son comportement immédiat de compatibilité ;
- les contrôles Warlock invalides `dps` et `dps debuff` ont été retirés, le placeholder Buff désactivé a été supprimé et le layout des contrôles a été compacté ;
- les quatre avertissements LuaLint ciblés sur les variables `action` ont été corrigés sans modifier le comportement.

Diagnostic TEMP_ENCHANT validé :

- `/mbdebug enchant [bot]` envoie à la demande `GET~WEAPON_ENCHANT` et affiche la réponse structurée `WEAPON_ENCHANT` ;
- le bridge lit l'item, l'ID de `TEMP_ENCHANTMENT_SLOT` et sa durée sur main-hand/off-hand ;
- l'endpoint est limité au bot visible et contrôlable, conserve `CheckLevelFor(...)`, et applique un rate-limit de 500 ms par requester ;
- aucun polling automatique n'est introduit et `mod-playerbots` n'est pas modifié.

Cause et correction Firestone/Spellstone :

- l'audit Playerbots en lecture seule a confirmé que `ItemForSpellValue` et `UseItemAction::UseItem()` refusent de cibler une arme dont `TEMP_ENCHANTMENT_SLOT` est déjà occupé ; la stratégie peut donc changer sans remplacer la pierre déjà appliquée ;
- le correctif reste dans `mod-multibot-bridge` : uniquement pour un Warlock, en `BOT_STATE_NON_COMBAT`, lors d'un vrai switch exclusif `firestone` ↔ `spellstone` ;
- le bridge découvre dynamiquement les enchant IDs des Firestone/Spellstone portées par le bot, refuse d'effacer un enchantement temporaire non reconnu, retire proprement l'ancien enchantement reconnu, puis réutilise l'action Playerbots existante avec `DoSpecificAction()` ;
- aucun ID Firestone/Spellstone n'est hardcodé dans le correctif et aucun fichier de `mod-playerbots` n'est modifié.

Preuves runtime :

- compilation Visual Studio `RelWithDebInfo x64` : 3 projets réussis, 0 échec ; worldserver démarré sans erreur bridge ;
- Apha, Spellstone → Firestone : `TEMP_ENCHANTMENT_SLOT` `3620` → `3614`, durée finale `3600000 ms`, utilisation réelle de Grand Firestone observée ;
- Apha, Firestone → Spellstone : `TEMP_ENCHANTMENT_SLOT` `3614` → `3620`, durée finale `3600000 ms`, utilisation réelle de Grand Spellstone observée ;
- audit final : `audit-multibot-warlock-stone-force-switch-final-v1-2026-08-08-160400-2026-08-08-160706.zip`, SHA-256 `C0025FCAC7817711B0D5493EA3349B5F57A3AA620C260E76F59E1CAA92F7EA1A` ;
- archivage patch : `patch-multibot-warlock-stone-force-switch-v1b-2026-08-08-154300-results-2026-08-08-162451.zip`, SHA-256 `8FABF24B50EA459EF6C7EE4A0D0BE21CFB251D1C7DEF6505C7C483BF43141C5B` ;
- `mod-playerbots` reste strictement en lecture seule.

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

1. **Formations — application par clic gauche : VALIDÉE** via `RUN~FORMATION~GROUP` par `patch-multibot-formation-chatless-v1c-2026-08-01-181300`.
2. **Consultation de la formation actuelle par clic droit : VALIDÉE** via `GET~FORMATIONS~GROUP`, `FORMATIONS_BEGIN/ITEM/END` et un tooltip local traduit.
3. **Infrastructure mutations stratégies `co/nc` : VALIDÉE STATIQUEMENT** via `STRATEGY_MUTATION_V1`, `RUN~STRATEGY`, `STRATEGY_ACK`, timeouts, limites et diagnostics explicites.
4. **Sélecteurs Warlock Stones/Soulstones/Pets/Curses : VALIDÉS** — mutations via `STRATEGY_MUTATION_V1` / `RUN~STRATEGY`, état UI autoritatif côté bridge et bascule réelle Firestone/Spellstone validée sans modification de Playerbots.
5. `s *` — vente générale bridge-first.
6. `s vendor` — vente vendeur bridge-first, sans whisper item par item.
7. `open items` — ouverture de conteneurs bridge-first.
8. `roll` et `roll [item]`.
9. Enchantement d'objet, après validation du flux trade/cast disponible sans modification de Playerbots.
10. Ajout/retrait d'items précis dans les règles de loot.
11. Décision sur `Quest`/`Skill` versus `Disenchant`, sans inventer de stratégie absente de Playerbots.
12. Ordres collectifs `follow`, `attack`, `stay` seulement après validation manuelle exacte des sélecteurs Playerbots ; ne pas réintroduire `RUN~ORDER` générique.

Les commandes informatives `who`, `co ?`, `nc ?` et `ss ?` restent manuelles tant qu'aucune UI structurée ne les remplace. Les mutations UI automatiques `co/nc`, en revanche, doivent passer par le bridge dès qu'un contrat structuré validé existe.

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
