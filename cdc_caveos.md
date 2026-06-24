# Cahier des charges — Application iOS native de gestion de cave à vin ("CaveOS")

## TL;DR
- On construit une app iOS native 100% Swift/SwiftUI, **offline-first**, agnostique du matériel, avec reconnaissance d'étiquettes locale via le Vision framework (pas de Vivino), un modèle de données local et une sync CloudKit en tâche de fond — exactement les points où Vinotag (1.8/5), OENO (3.0/5) et Decanter Premium (3.8/5) échouent.
- Le modèle économique rompt avec la tromperie du marché : ajout manuel illimité gratuit, et déblocage Lifetime (achat unique non-consommable via StoreKit 2) du scan illimité + sync + analytics, avec option abonnement annuel optionnel.
- Stack recommandée : SwiftUI + MVVM + `@Observable`, SwiftData (ou Core Data si migrations lourdes nécessaires) sur `NSPersistentCloudKitContainer`, données vin embarquées (Wikidata CC0, INAO Licence Ouverte, LWIN) + moteur d'apogée heuristique.

## Key Findings

### Le problème de marché est réel et documenté
Les trois concurrents fournis souffrent de défauts architecturaux, pas cosmétiques :
- **Vinotag (FRIO/La Sommelière, 1.8/5)** : scanner délégué à Vivino souvent flou (avis App Store : « le scan de l'étiquette dans l'appli est souvent flou ce qui oblige à s'y reprendre… sur Vivino c'est instantané »), limite de 50 scans gratuits puis paywall (le manuel ECS81.2Z confirme : « la création d'un compte VINOTAG® vous permet de bénéficier de 50 scans gratuits »), impossibilité de configurer plus de 2 niveaux par clayette (« L'appli me limite à 2 niveaux par clayette… J'en ai 3 mais je ne peux donc pas rentrer mes bouteilles »), apogée non gérée par base de données (l'équipe Vinotag reconnaît elle-même qu'« aucune base de donnée ne recense cette information »).
- **OENO by Vintec (AB Electrolux, 3.0/5)** : web wrapper lent (avis : « Slow, but that's what you get for something that is just a front end for a web site… Uninstalled because it's so slow »), panne totale d'authentification de plusieurs semaines en 2026 (« Last week, the app stopped working for all users… No way of obtaining support »), Electrolux annonce vouloir abandonner l'app (réponse officielle : « we do plan to exit the app at some point in the near future now that we no longer carry Vintec in the NA region »), scanner délégué à Vivino, ajout manuel exigeant tous les champs.
- **Decanter Premium (3.8/5)** : boucles de connexion, redemande d'identifiants, échec de chargement des sous-pages.

Le fil rouge : dépendance à un backend web/API tierce (Vivino) + auth en ligne obligatoire = lenteur, fragilité et points de défaillance uniques. Notre thèse produit : **tout doit fonctionner sans réseau, instantanément, et l'app doit survivre à la mort de tout service tiers.**

### La reconnaissance d'étiquettes 100% native est faisable dès le MVP
Le Vision framework iOS (depuis iOS 18, nouvelle API Swift `RecognizeTextRequest`, et l'ancienne `VNRecognizeTextRequest`) + `DataScannerViewController` (VisionKit, iOS 16+) permettent un OCR temps réel en français, sans API tierce. Le français est officiellement supporté par l'OCR Apple depuis iOS 14 (forum développeur Apple : « Support for several new languages has been introduced to VNRecognizeTextRequest in iOS 14… Supported languages… en, fr, it, de, es, pt, zh »). La stratégie n'est PAS de reconnaître "le vin" (impossible en local) mais d'**extraire le texte de l'étiquette et de le parser en champs structurés** (domaine, millésime, appellation, cépage) via heuristiques + matching contre la base embarquée.

### Les données vin peuvent être embarquées légalement, sans Vivino
- **Cépages + régions** : Wikidata (licence CC0, domaine public, ~1 300+ variétés multilingues FR/EN ; classe « grape variety » Q958314) → export SPARQL vers SQLite local. CC0 verbatim : « All structured data from the main, Property, Lexeme, and EntitySchema namespace is available under the Creative Commons CC0 License. »
- **Appellations françaises** : INAO via data.gouv.fr / Opendatasoft (« Aires et produits AOC/AOP et IGP », **Licence Ouverte v1.0**). L'INAO a supervisé en 2022 « 1,204 products, including 366 PDO/AOC wines » (366 AOC/AOP vins, chiffre porté à ~386 AOC/AOP viticoles en 2023) ; plus une réuse communautaire data.gouv.fr mappant chaque AOC à ses cépages autorisés. EU-wide : eAmbrosia (registre GI de l'UE).
- **Identifiant canonique du vin** : LWIN (Liv-ex), base open source Creative Commons gratuite — page officielle Liv-ex : « Covering over 200,000 wines and spirits, LWIN is the most comprehensive open source database available to the industry. It's free to download, and always will be under the Creative Commons licence. » Hiérarchie LWIN-7 (produit) / LWIN-11 (+millésime) / LWIN-16 (+format) / LWIN-18 (+conditionnement). Embarquable hors-ligne ; les API temps réel restent gated derrière l'adhésion Liv-ex.
- **Apogée** : aucune base ouverte n'existe (confirmé par l'aveu de Vinotag et par Liv-ex qui gate ses drinking windows derrière une API payante membres) → **moteur heuristique** base (min/peak/max par cépage) × multiplicateur qualité région × multiplicateur stockage.

## Details

### 1. Contexte et vision produit
Le marché de la cave connectée présente un décalage criant entre un matériel haut de gamme (caves Climadiff, La Sommelière, Avintage, Vintec, EuroCave) et des logiciels médiocres. Les utilisateurs sont des passionnés à fort pouvoir d'achat, exigeants en UX. Les apps existantes les trahissent par : dépendance réseau, paywalls masqués, lenteur de web wrappers, scanners tiers défaillants, et abandon par les éditeurs.

**Vision** : « La cave à vin dans la poche, qui marche partout, instantanément, et pour toujours. » CaveOS est une app native, indépendante du matériel (gère cave électrique, cave naturelle, armoire, casiers, stockage en vrac), offline-first par conception, avec un modèle économique honnête (pas de location déguisée d'un carnet que l'utilisateur a lui-même rempli).

**Principes directeurs non négociables :**
1. **Offline-first absolu** : 100% des fonctions de consultation/ajout/déplacement/recherche marchent sans réseau, temps de réponse perçu nul (sous-sol sans signal).
2. **Aucune dépendance critique à un service tiers** : si CloudKit ou une API meurt, l'app continue de fonctionner en local.
3. **Honnêteté du modèle éco** : ce que l'utilisateur saisit lui appartient et reste accessible gratuitement et exportable.
4. **Natif et rapide** : Swift/SwiftUI, zéro web wrapper.

### 2. Analyse concurrentielle et positionnement

| Critère | Vinotag (1.8) | OENO (3.0) | Decanter Premium (3.8) | CaveOS (cible) |
|---|---|---|---|---|
| Architecture | Cloud + connecté | Web wrapper | Cloud | Offline-first natif |
| Scanner | Vivino (flou, lent) | Vivino (lent) | — | Vision natif local |
| Auth obligatoire | Oui | Oui (pannes) | Oui (boucles) | Non (local d'abord) |
| Config clayettes | Bridée (2 niveaux) | Rudimentaire | — | Libre, drag & drop |
| Modèle éco | Paywall masqué 50 scans | Gratuit (lié matériel) | Premium | Lifetime + freemium honnête |
| Alertes apogée | Saisie manuelle only | Éditable | — | Heuristique + manuel |
| Codes erreur cave (HH/LL/EE) | Non gérés | — | — | Documentés + alertes |

**Positionnement** : le "anti-Vinotag" — rapide, honnête, qui marche hors-ligne et n'appartient à aucun fabricant de cave. Concurrents premium à étudier comme références UX : CellarTracker (référence inventaire sérieux ; le CEO Eric LeVine évoque via The Drinks Business, fév. 2026, « the communities it has generated, of around 13 million reviews » — plus de 13 millions d'avis, 5M+ vins uniques, 193M+ bouteilles suivies — mais payant/communautaire), InVintory (premium, 3D, 2M+ vins), VinoCell (4.6/5 App Store, scan code-barres, granularité). On vise le créneau "passionné francophone qui veut un outil rapide et possédé une fois pour toutes".

### 3. Personas et cas d'usage

**Persona A — "Le collectionneur cave électrique" (Marc, 52 ans)** : 2 caves La Sommelière + Climadiff, 150-400 bouteilles, veut localiser une bouteille en 3 secondes devant ses invités, suivre l'apogée, ne plus jamais "oublier" un grand cru jusqu'à ce qu'il soit passé.

**Persona B — "Le passionné cave naturelle" (Sophie, 38 ans)** : cave en sous-sol sans réseau, casiers maçonnés, 80 bouteilles, veut un plan visuel de sa cave et un ajout rapide par scan, sans devoir tout retaper.

**Persona C — "L'amateur mobile" (Karim, 29 ans)** : pas de cave dédiée, quelques dizaines de bouteilles dans un placard, veut surtout un carnet de dégustation et des notes, gratuit.

**Cas d'usage clés :**
- Ajouter 12 bouteilles en < 5 min par scan (vs 45 min pour OENO).
- Trouver "tous mes Bordeaux rouges à boire avant 2027" hors-ligne en < 2 s.
- Déplacer une bouteille d'une clayette à l'autre en drag & drop.
- Recevoir une notification locale "Château X arrive à apogée ce mois-ci".
- Stocker une bouteille entamée (suivi vertical du niveau/date d'ouverture).
- Exporter toute sa cave en CSV/Excel à tout moment.

### 4. Périmètre fonctionnel : MVP → v2 → v3

**MVP (v1.0) :**
- Modèle de données local complet (bouteille, vin, domaine, région, cépage, emplacement, dégustation).
- Ajout manuel illimité (gratuit), édition, suppression, historique de consommation.
- **Scan d'étiquette via Vision natif** (OCR + parsing en champs) — inclus dès le départ.
- Gestion visuelle des emplacements (caves, clayettes multi-niveaux configurables, drag & drop).
- Recherche + tags rapides (cépage, millésime, apogée, couleur, région).
- Notifications locales d'apogée.
- Base vin embarquée (cépages, régions, appellations FR).
- Moteur d'apogée heuristique.
- Export CSV/Excel.
- StoreKit 2 : freemium + déblocage Lifetime.

**v2.0 :**
- Sync CloudKit multi-appareils (iPhone/iPad) en tâche de fond.
- Statistiques/analytics de cave (valeur, répartition, à boire en priorité).
- Code-barres (EAN) en complément du scan d'étiquette.
- Enrichissement optionnel via API tierce (opt-in, jamais bloquant).
- Codes d'erreur matériel documentés (HH/LL/EE) + saisie manuelle de température/alertes.

**v3.0 :**
- Fonctionnalités sociales/dégustation (partage de cave en lecture, partage CloudKit entre utilisateurs).
- Carnet de dégustation avancé (grille WSET, photos, accords mets-vins).
- Accords mets-vins ("qu'est-ce que je bois avec un gratin dauphinois ?").
- iPad optimisé / widgets / Apple Watch (consultation rapide).
- Reconnaissance d'étiquette enrichie par ML on-device (Core ML) pour matching visuel.

### 5. Spécifications fonctionnelles détaillées

**5.1 Gestion d'inventaire** — Ajout d'une bouteille : scan OU manuel. Champs : vin (lien), millésime, quantité, format (75cl par défaut, magnum, etc.), prix d'achat, date d'achat, fournisseur, emplacement, apogée min/max, notes. Aucun champ obligatoire sauf un nom (corrige le défaut OENO "ajout manuel exigeant tous les champs").

**5.2 Gestion des emplacements (drag & drop)** — Hiérarchie : Cave → Clayette/Zone → Niveau → Position (avant/arrière). Configuration LIBRE du nombre de niveaux et colonnes (corrige le bridage Vinotag à 2 niveaux). Vue graphique (grille) + vue liste. Drag & drop d'une bouteille. Zone "stockage en vrac" pour bouteilles hors cave. Support des bouteilles couchées ET debout.

**5.3 Bouteilles entamées (suivi vertical)** — Une bouteille peut passer en état "entamée" : date d'ouverture, niveau restant (ex. verres restants), méthode de conservation (Coravin, bouchon, pompe). Corrige l'impossibilité OENO de stocker des bouteilles entamées en vertical. Notification optionnelle "bouteille ouverte depuis X jours".

**5.4 Recherche et tags rapides** — Recherche plein texte locale instantanée. Filtres/tags : couleur, cépage, région, appellation, millésime, fourchette d'apogée (à boire / apogée / à surveiller / passé), prix, emplacement. Tri multi-critères. Tout fonctionne hors-ligne.

**5.5 Apogée et maturité** — Calcul automatique de la fenêtre de consommation via le moteur heuristique, ajustable manuellement par l'utilisateur (recommandation caviste/sommelier). Statut visuel (code couleur) : trop jeune / prêt / apogée / à boire vite / passé.

**5.6 Export/portabilité** — Export CSV et Excel à tout moment (corrige l'enfermement). Import CSV pour migration depuis Vinotag/OENO/CellarTracker.

**5.7 Codes d'erreur matériel (v2)** — Documentation in-app des codes HH (température haute), LL (température basse), EE (défaut de sonde) pour les marques courantes, avec actions recommandées. L'app étant agnostique, pas de connexion directe à la cave au MVP ; saisie manuelle de relevés de température possible, avec alerte locale si seuil dépassé.

### 6. Architecture technique

**6.1 Stack** — SwiftUI (UI déclarative, intégration native `@Observable`), UIKit ponctuel via `UIViewControllerRepresentable` pour `DataScannerViewController`. **Architecture MVVM + `@Observable`** (iOS 17+) : c'est le défaut de production 2026 pour une app SwiftUI indie, le plus faible en friction et le mieux aligné sur les frameworks Apple (Apple décrit le flux par défaut de SwiftUI comme "effectively MVVM"). TCA écarté (boilerplate et courbe d'apprentissage non justifiés pour un dev solo sur < 15 écrans ; temps de compilation pénalisant signalé en production). Swift 6, concurrence stricte (async/await, actors). Cible iOS 17+ (pour SwiftData + `@Observable`).

**6.2 Persistance — SwiftData vs Core Data** :
- **SwiftData** (recommandé par défaut) : API Swift-native, macro `@Model`, intégration SwiftUI via `@Query`, moins de boilerplate, supporte CloudKit via `ModelConfiguration`. Mature en 2026 mais hérite de limites rapportées en production : auto-save parfois silencieux/non fiable, migrations seulement légères (lightweight), ordering des collections instable, perf sur très gros graphes (chargement eager plutôt que faulting).
- **Core Data** (repli) : 20 ans de maturité (depuis iOS 3), migrations lourdes, contrôle fin, requis pour CloudKit partagé/public (v3 social). Plus verbeux.
- **Décision** : SwiftData pour le MVP (la cave d'un particulier = quelques milliers d'objets max, dans les cordes de SwiftData). **Couche repository abstraite** pour pouvoir basculer sur Core Data si les fonctions sociales/partage CloudKit ou des migrations lourdes l'imposent en v3. Pin du contexte, sauvegardes manuelles explicites pour éviter l'auto-save silencieux.

**6.3 Modèle de données (entités)** :
- `Wine` (vin abstrait) : nom, domaine→`Producer`, région→`Region`, appellation→`Appellation`, cépages→[`Grape`], couleur, type, LWIN (optionnel), profil de garde base.
- `Bottle` (instance physique) : →`Wine`, millésime, format, quantité, prix achat, date achat, fournisseur, →`Location`, apogée min/max (override), état (en cave / entamée / consommée), date ouverture, niveau restant, méthode conservation.
- `Producer` (domaine/château), `Region`, `Appellation`, `Grape` (cépage) — issus de la base embarquée.
- `Location` : →`Cellar`, type (clayette/zone/vrac), index niveau, colonne, position avant/arrière, capacité.
- `Cellar` : nom, type (électrique/naturelle/armoire/casier), marque/modèle (optionnel), géométrie (lignes×colonnes×niveaux).
- `TastingNote` : →`Bottle`/`Wine`, date, note /100 ou /20, grille (œil/nez/bouche), texte, photos, accords.
- Clés primaires en **UUID** (impératif pour éviter les collisions de sync CloudKit hors-ligne ; jamais d'ID auto-incrémenté serveur).

**6.4 Base de données vin embarquée** — SQLite/Store bundlé en lecture : cépages (Wikidata CC0), régions, appellations FR (INAO Licence Ouverte v1.0), mapping AOC→cépages, identifiants LWIN (CC). Écran de crédits/attribution requis (Licence Ouverte v1.0 et CC-BY exigent l'attribution ; CC0 Wikidata et LWIN CC n'imposent rien de strict mais on crédite par courtoisie). Mises à jour de la base via update de l'app ou CloudKit public en lecture. **Éviter DBpedia** (CC-BY-SA, share-alike incompatible avec une app propriétaire).

**Moteur d'apogée — table de base (années depuis le millésime)** : base min/peak/max par cépage, ajustée par multiplicateur qualité région (premium ×1,4 / milieu ×1,0 / entrée ×0,6) et multiplicateur stockage (idéal ×1,0 / bon ×0,85 / moyen ×0,6 / mauvais ×0,4). Formule : `DrinkFrom = Millésime + (BaseMin × Région × Stockage)`, peak et DrinkBy de même (méthode citant WSET Level 3, 2023). Starter table (sources Wine Folly / WSET) :

| Cépage | Min | Peak | Max |
|---|---|---|---|
| Cabernet Sauvignon | 5 | 10–15 | 30+ |
| Merlot | 2 | 8–12 | 30+ |
| Nebbiolo (Barolo) | 5 | 12–20 | 30+ |
| Sangiovese (Brunello) | 10 | 15–20 | 30+ |
| Tempranillo (Rioja) | 3 | 8–15 | 25+ |
| Syrah/Shiraz | 3 | 8–12 | 20+ |
| Pinot Noir | 2 | 5–10 | 30 |
| Chardonnay | 2 | 5–8 | 15+ |
| Riesling | 2 | 5–10 | 15–30+ |
| Sauvignon Blanc | 0 | 1–3 | 7–10 |
| Sweet (Sauternes) | 5 | 15–30 | 50+ |
| Fortifié (Port/Madère) | varie | décennies | 100+ |

### 7. Reconnaissance d'étiquettes via Vision framework (stratégie détaillée)

**7.1 Capture** — Deux modes :
- **Temps réel** : `DataScannerViewController` (VisionKit, iOS 16+), `recognizedDataTypes: [.text(), .barcode()]`, `qualityLevel: .accurate`, intégré en SwiftUI via `UIViewControllerRepresentable`. Vérifier `DataScannerViewController.isSupported && .isAvailable`. Permission caméra (`NSCameraUsageDescription`) requise. Items renvoyés en ordre de lecture naturel.
- **Photo** : capture haute résolution (`capturePhoto`) ou import depuis la photothèque, puis OCR sur image fixe via `RecognizeTextRequest` (API Swift iOS 18) / `VNRecognizeTextRequest` (compat iOS 17) avec `VNImageRequestHandler`.

**7.2 OCR** — Configuration : `recognitionLevel = .accurate` (qualité sur petits textes d'étiquette ; `.fast` réservé au temps réel live), `recognitionLanguages = ["fr-FR", "en-US", "it-IT", "es-ES"]` (priorité français), `usesLanguageCorrection = true`. **`customWords`** : injecter un lexique vin (noms de cépages, appellations, mentions "Grand Cru", "Mis en bouteille au château", "Appellation … Contrôlée") issu de la base embarquée — `customWords` prend priorité sur le lexique intégré. `minimumTextHeight` pour ignorer le bruit. Récupérer `topCandidates(k)` (jusqu'à 10) avec score de confiance — utile car une confiance élevée ne garantit pas l'exactitude (cas documenté : confiance 1.0 mais "TN" au lieu de "™").

**7.3 Parsing en champs structurés** — Le cœur de la valeur. Sur le tableau de lignes OCR (déjà en ordre de lecture) :
- **Millésime** : regex `\b(19|20)\d{2}\b` → millésime probable (filtrer années aberrantes).
- **Appellation** : matching flou (distance de Levenshtein) des lignes contre la table d'appellations INAO embarquée ; détection du motif "Appellation X Contrôlée/Protégée".
- **Cépage** : matching contre la liste de cépages Wikidata.
- **Domaine/Château** : heuristique (ligne contenant "Château", "Domaine", "Clos", "Mas", "Bodega", "Tenuta" ; ou plus grand texte/première ligne).
- **Contenance/degré** : regex `75 ?cl|750 ?ml`, `\d{1,2}([.,]\d)? ?%`.
- Résultat : pré-remplissage de la fiche, **toujours éditable** (jamais de champ obligatoire bloquant). L'utilisateur valide/corrige en 2 taps.

**7.4 Précision et limites (à assumer honnêtement)** — L'OCR de scène (étiquette courbe, typographies fantaisie, dorures, faible lumière) est plus difficile que le document plat. Mitigations : guidage UX (cadre, conseils lumière), `CIPerspectiveCorrection` pour redresser, possibilité de reprendre la photo, choix parmi plusieurs candidats. On ne promet PAS la reconnaissance du vin exact (pas de base visuelle mondiale en local) — on promet une **saisie assistée rapide et fiable**, supérieure à un scan tiers lent et hors-ligne impossible. Matching visuel ML (Core ML) repoussé en v3.

**7.5 Pourquoi pas Vivino/API** — Vivino = dépendance réseau (donc inutilisable en cave sans signal), lenteur (45 min/12 bouteilles chez OENO), point de défaillance unique, et risque juridique/commercial. Le natif est instantané, hors-ligne, et pérenne.

### 8. Synchronisation cloud (v2)

**8.1 Choix** — `NSPersistentCloudKitContainer` (Core Data) ou SwiftData + CloudKit via `ModelConfiguration` : mirroring automatique vers la base privée iCloud de l'utilisateur, peu de code, gratuit dans les limites iCloud, pas de backend à opérer. Alternative bas niveau `CKSyncEngine` si besoin de contrôle fin (repoussé). **Offline-first** : la base locale reste la source de vérité ; CloudKit ne synchronise qu'en tâche de fond.

**8.2 Configuration clé** :
- `viewContext.automaticallyMergesChangesFromParent = true`.
- `mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy` (sinon `NSErrorMergePolicy` par défaut bloque la fusion iCloud).
- `NSPersistentHistoryTrackingKey = true` (historique persistant).
- `setQueryGenerationFrom(.current)`.
- Observer `NSPersistentCloudKitContainer.eventChangedNotification` pour exposer l'état de sync à l'UI (corrige l'angoisse "ma sync a-t-elle marché ?").

**8.3 Gestion des conflits** — Stratégie "éviter par conception" : entités fines (deux champs édités séparément n'entrent pas en conflit), UUID comme clés (jamais d'ID auto-incrémenté → collisions offline), patterns append-only pour l'historique de consommation. Pour les conflits résiduels, résolution par propriété (dernier écrivain gagne au niveau champ). **Corrige le défaut majeur Vinotag** : la désynchronisation irréversible lors de coupures de courant/déplacements. Ici, la coupure réseau n'a aucun effet sur les données locales ; la sync reprend proprement au retour du réseau, sans perte.

**8.4 Tests** — Test de conflit (éditer le même enregistrement sur 2 appareils hors-ligne puis reconnecter), test gros volume (10 000+ enregistrements), `initializeCloudKitSchema` en dev pour valider le mapping schéma. Noter : le simulateur iOS ne supporte pas les push → tester les merges auto sur appareil réel.

### 9. Notifications et alertes (UserNotifications)

- **Permission** demandée au bon moment (pas au lancement brut) : à la première création d'alerte d'apogée, via `requestAuthorization(options: [.alert, .badge, .sound])`.
- **Alertes d'apogée** : `UNCalendarNotificationTrigger` (via `DateComponents`) planifié à l'entrée dans la fenêtre d'apogée calculée (ex. "Votre Château X 2015 entre à apogée"). Identifiant stable par bouteille (`UUID`) pour pouvoir annuler/mettre à jour (`removePendingNotificationRequests(withIdentifiers:)`).
- **Alertes "à boire vite"** : déclenchées à l'approche de la fin de fenêtre.
- **Bouteille entamée** : rappel optionnel après N jours d'ouverture.
- **Alerte stock** : seuil bas sur un vin favori.
- **Alerte température (v2)** : si relevé manuel hors seuil, ou si intégration future. Toutes les notifications sont **locales** (`UNUserNotificationCenter`, pas de serveur push requis) → cohérent offline-first.

### 10. Modèle économique et monétisation

**Constat marché (RevenueCat State of Subscription Apps 2026)** : les hard paywalls convertissent ~5× mieux que le freemium — « Hard paywalls convert downloads to paid at a median of 10.7% — five times better than the 2.1% median for freemium apps » (10,7% vs 2,1% download-to-paid à J35). Les apps à prix élevé convertissent mieux : **2,66% vs 1,49%** de download-to-paying médian (high-priced vs low-priced). Les apps premium de niche réussissent par la valeur perçue, pas le volume. Le freemium reste pertinent quand les utilisateurs gratuits créent du bouche-à-oreille.

**Stratégie CaveOS (honnête, anti-Vinotag) — StoreKit 2 :**
- **Gratuit pour toujours** : ajout manuel illimité, gestion d'emplacements, recherche, export. (Ce que l'utilisateur saisit lui appartient — rupture nette avec le paywall masqué à 50 scans de Vinotag.)
- **CaveOS Pro — Achat unique Lifetime** (non-consommable IAP) : scan d'étiquette illimité, sync CloudKit multi-appareils, analytics de cave, carnet de dégustation avancé. **Prix affiché clairement en amont** (transparence totale, contre le "paywall masqué sans tarifs" de Vinotag).
- **Option abonnement annuel** (auto-renewable, groupe d'abonnement) pour ceux qui préfèrent étaler, donnant les mêmes fonctions Pro + futures fonctions cloud lourdes. Le Lifetime reste l'offre phare et le signal de confiance.
- **StoreKit 2** : `Product.products(for:)`, `product.purchase()`, écoute `Transaction.updates` dès le lancement de l'app, `SubscriptionStoreView`/`ProductView`/`StoreView` pour le paywall, gestion des états (grace period = accès maintenu pour éviter le churn involontaire ; revoked = accès retiré), test via StoreKit Configuration File en local. Restauration d'achats obligatoire.
- **RevenueCat optionnel** (combo RevenueCat + StoreKit 2) pour simplifier le suivi LTV et les paywalls si le temps dev manque — gratuit jusqu'à un certain seuil de revenu.

Justification : public à fort pouvoir d'achat, niche premium, attente d'un outil "possédé". Le Lifetime crée la confiance (anti-abonnement-fatigue) ; le freemium honnête nourrit le bouche-à-oreille et l'ASO (avis positifs).

### 11. Stratégie ASO et go-to-market

**Faits ASO 2026** : ~65% des téléchargements viennent de la recherche organique (Adalo/Apple) ; pondération (AppTweak) ~ pertinence mots-clés 30%, vélocité de téléchargements 25%, notes/avis 20% ; le titre (30 car.) a le plus de poids, puis le sous-titre (30 car., indexé), puis le champ keywords caché (100 car.) ; la description n'influence PAS le classement App Store (mais la conversion) ; tendance aux requêtes long-tail (2-4 mots) ; tests A/B natifs dans App Store Connect (jusqu'à 3 variantes, ≥ 2 semaines chacune).

**Mots-clés cibles (français)** : gestion de cave hors-ligne, inventaire vin facile, suivi cave à vin sans abonnement, carnet de dégustation, organisateur de cave rapide, gestionnaire de vin, cave à vin, apogée vin, scanner étiquette vin.

**Recommandations concrètes :**
- **Titre (30 car.)** : marque + descripteur avec mot-clé principal, ex. "CaveOS — Gestion de cave".
- **Sous-titre (30 car.)** : 2e/3e mots-clés, ex. "Inventaire vin hors-ligne & apogée".
- **Keywords (100 car.)** : remplir intégralement, sans répéter le titre, sans espaces après virgules : `cave,vin,dégustation,apogée,millésime,cépage,inventaire,sommelier,bouteille,étiquette,scanner,sansabonnement`.
- **Visuels** : screenshots montrant le scan natif, le plan de cave drag & drop, le statut d'apogée ; icône mémorable ; vidéo preview. A/B test icône + premiers screenshots.
- **Avis** : solliciter au bon moment (après une action réussie, ex. 10 bouteilles ajoutées) via `SKStoreReviewController`. Les avis pèsent ~20%.
- **Go-to-market** : cibler les communautés francophones (forums de passionnés, groupes cave, cavistes), capitaliser sur le récit "l'app honnête sans abonnement qui marche en cave", viser les déçus de Vinotag/OENO (mot-clé "sans abonnement", import CSV depuis concurrents).

### 12. Roadmap de développement par phases

- **Phase 0 — Fondations (2-3 sem.)** : projet SwiftUI/Swift 6, modèle SwiftData, couche repository, base vin embarquée (import Wikidata/INAO/LWIN → SQLite).
- **Phase 1 — MVP cœur (6-8 sem.)** : CRUD bouteilles, emplacements drag & drop, recherche/tags, moteur d'apogée, notifications locales, export CSV.
- **Phase 2 — Scan natif (3-4 sem.)** : DataScannerViewController + RecognizeTextRequest + parser de champs + lexique customWords.
- **Phase 3 — Monétisation (1-2 sem.)** : StoreKit 2, paywall transparent, freemium/Lifetime.
- **Phase 4 — Lancement v1** : ASO, TestFlight, App Store.
- **Phase 5 — v2 (post-lancement)** : sync CloudKit, analytics, code-barres, codes erreur matériel.
- **Phase 6 — v3** : social/partage, dégustation avancée, accords mets-vins, iPad/Watch/widgets, matching visuel Core ML.

### 13. Risques et points de vigilance (tirés des échecs concurrents)

| Risque | Source (échec concurrent) | Mitigation |
|---|---|---|
| Désync irréversible sur coupure | Vinotag | Offline-first strict, UUID, mergePolicy, historique persistant ; local = vérité |
| Lenteur / instabilité | OENO web wrapper, erreurs 500 | 100% natif, zéro web wrapper, zéro dépendance réseau bloquante |
| Panne d'auth bloquant l'accès | OENO (semaines de blocage), Decanter (boucles) | Pas d'auth obligatoire ; données accessibles en local sans login |
| Abandon par l'éditeur | OENO ("we plan to exit") | App autonome, données exportables, pas liée à un fabricant |
| Scanner défaillant/lent | Vinotag flou, OENO 45 min/12 btl | OCR natif local instantané + parsing + édition facile |
| Paywall masqué | Vinotag (50 scans, pas de tarif) | Tarifs affichés en amont, ajout manuel gratuit illimité |
| Bridage de config | Vinotag (2 niveaux clayette) | Configuration libre des emplacements |
| Champs obligatoires pénibles | OENO | Aucun champ obligatoire sauf le nom |
| Enfermement des données | tous | Export CSV/Excel + import permanents |
| Limites SwiftData (auto-save, migrations) | — (risque technique) | Sauvegardes explicites, couche repository pour repli Core Data |
| OCR imparfait sur étiquettes difficiles | — | Guidage UX, perspective correction, multi-candidats, édition manuelle |
| Apogée sans base de référence | Vinotag (aveu) | Moteur heuristique transparent + override manuel |

## Recommendations

1. **Démarrer par les fondations offline-first + base vin embarquée** avant toute UI. C'est l'avantage concurrentiel structurel ; ne jamais introduire de dépendance réseau bloquante.
2. **Inclure le scan natif dès le MVP** (Phase 2) comme promis — c'est le différenciateur démo-able face à Vinotag/OENO. Mais le livrer comme "saisie assistée" honnête, pas comme reconnaissance magique. Mesurer empiriquement la précision OCR sur 50+ étiquettes réelles dès la fin de Phase 2.
3. **SwiftData maintenant, avec couche repository** pour garder l'option Core Data ouverte en v3 (social/CloudKit partagé, migrations lourdes). Faire des sauvegardes explicites pour contourner l'auto-save silencieux.
4. **Modèle Lifetime en offre phare, tarif affiché clairement**, freemium avec ajout manuel illimité. C'est le positionnement marketing central (anti-tromperie) ET un moteur d'ASO via avis positifs.
5. **ASO dès le jour 1** : titre + sous-titre travaillés, keywords remplis à 100 car., import CSV depuis Vinotag/OENO pour capter les déçus, mot-clé "sans abonnement".
6. **Seuils qui changent la donne** : si la cible utilisateur dépasse régulièrement ~50 000 objets ou si le partage multi-utilisateurs devient prioritaire, basculer la persistance sur Core Data. Si la conversion Lifetime stagne nettement sous la médiane marché (~2% à J35) après 4-6 semaines, tester un paywall plus ferme sur le scan tout en gardant l'ajout manuel gratuit, et A/B-tester le prix (les apps à prix élevé convertissent mieux : 2,66% vs 1,49%).

## Caveats
- Les notes concurrentes (Vinotag 1.8, OENO 3.0, Decanter 3.8) et certains défauts (codes HH/LL/EE, 45 min/12 bouteilles) proviennent du brief utilisateur ; les avis App Store consultés corroborent les défauts qualitatifs (scan flou, lenteur web wrapper, panne d'auth de plusieurs semaines en 2026, bridage clayettes à 2 niveaux, intention d'Electrolux d'abandonner OENO) mais la note chiffrée exacte peut varier dans le temps.
- SwiftData reste plus jeune que Core Data (~3 ans en 2026) ; les limites citées (auto-save silencieux, migrations légères seulement, ordering instable, perf gros graphes) sont rapportées par des développeurs en production et doivent être validées sur le cas précis avant engagement.
- La précision de l'OCR natif sur étiquettes réelles (courbes, dorées, faible lumière) doit être mesurée empiriquement tôt ; c'est le principal risque technique du MVP.
- Les licences des données embarquées (Wikidata CC0, INAO Licence Ouverte v1.0, LWIN Creative Commons) doivent être revérifiées à la date d'intégration et créditées ; éviter DBpedia (CC-BY-SA, share-alike) pour une app propriétaire. Le nombre exact d'AOC/AOP viticoles évolue (366 en 2022 selon l'INAO, ~386 en 2023).
- Les chiffres de conversion (RevenueCat 2026 : 10,7% vs 2,1% ; 2,66% vs 1,49%) et la pondération ASO (AppTweak) sont des moyennes/estimations de marché, pas des garanties pour une app de niche francophone.
- Global Wine Score apparaît désormais défunt (domaine en vente) ; ne pas l'inclure comme API de repli. Les API de repli viables identifiées sont Wine-Searcher (LWIN intégré), grapeminds.eu (freemium, 260 000+ vins, drinking windows) et les API membres Liv-ex.