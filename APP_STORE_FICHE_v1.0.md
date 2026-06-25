# CaveOS — Fiche App Store v1.0 (contenu prêt à coller)

Contenu à recopier directement dans la page **App Store Connect → CaveOS → Distribution / iOS App → Version 1.0** (la page `…/version/inflight`) et dans **App Information**.

> Compteurs de caractères vérifiés. Les champs avec limite stricte sont marqués `(n/max)`.

---

## 1. App Information (page « Informations sur l'app »)

| Champ | Valeur à coller | Limite |
|---|---|---|
| **Nom** | `CaveOS — Gestion de cave` | (24/30) |
| **Sous-titre** | `Inventaire vin & apogée` | (23/30) |
| **Langue principale** | Français (France) | — |
| **Bundle ID** | `com.louisbdc.caveos` | — |
| **Catégorie principale** | Style de vie | — |
| **Catégorie secondaire** | Nourriture et boissons | — |
| **Content Rights** | « Ne contient, n'affiche ni n'accède à du contenu tiers » (les données vin sont libres : Wikidata CC0, INAO Licence Ouverte, LWIN CC) | — |

> **Astuce ASO** : le sous-titre est indexé. J'évite d'y répéter « cave » (déjà dans le nom) et les mots déjà présents dans le champ Keywords. Variante possible si tu préfères mettre l'accent hors-ligne : `Cave à vin hors-ligne & apogée` (30/30).

---

## 2. Texte promotionnel (modifiable à tout moment, sans nouvelle revue)

**Promotional Text (160/170)**

```
Scannez l'étiquette, rangez vos bouteilles, suivez l'apogée. CaveOS marche partout, hors-ligne et pour toujours. Ajout illimité gratuit, sans abonnement masqué.
```

---

## 3. Description (le champ vide à remplir)

**Description (≈ 1 950 / 4 000)** — à coller telle quelle :

```
CaveOS, c'est votre cave à vin dans la poche : rapide, honnête, et qui fonctionne partout — même sans réseau.

Pensée pour les amateurs et les collectionneurs, CaveOS range vos bouteilles, suit leur apogée et retrouve n'importe quel cru en quelques secondes, devant vos invités comme au fond du garage. Aucun compte obligatoire, aucune dépendance à un service qui peut fermer du jour au lendemain : ce que vous saisissez vous appartient et reste exportable, gratuitement.

SCAN D'ÉTIQUETTE NATIF, HORS-LIGNE
Pointez la caméra sur l'étiquette : CaveOS lit le domaine, le millésime et l'appellation et pré-remplit la fiche, sans serveur ni connexion. Lecture des codes-barres également prise en charge.

VOTRE CAVE, FIDÈLEMENT REPRODUITE
Créez vos caves, clayettes et niveaux — autant que vous voulez. Glissez-déposez vos bouteilles à leur place réelle pour les localiser instantanément.

APOGÉE INTELLIGENTE
Un moteur de maturité estime la fenêtre de dégustation idéale de chaque vin (cépage × région × conditions de stockage), ajustable à la main. Code couleur clair : trop jeune, prêt, à son apogée, à boire vite, passé. Recevez une notification quand un grand cru entre à son apogée — pour ne plus jamais l'oublier jusqu'à ce qu'il soit passé.

RECHERCHE ET FILTRES INSTANTANÉS
Recherche plein texte locale et filtres par couleur, cépage, région, appellation, millésime, prix, emplacement ou statut d'apogée. Tout répond immédiatement, hors-ligne.

CARNET DE DÉGUSTATION
Notez vos impressions, gardez l'historique de consommation, suivez ce qu'il vous reste.

EXPORT LIBRE
Exportez tout votre inventaire en CSV quand vous voulez. Vos données ne sont jamais prises en otage.

BASE DE VIN EMBARQUÉE
Cépages, régions et appellations françaises (AOC/AOP) intégrés à l'app, disponibles sans connexion. Données issues de sources ouvertes (Wikidata, INAO, LWIN).

GRATUIT, HONNÊTEMENT
- Gratuit pour toujours : ajout manuel illimité, emplacements, recherche, export.
- CaveOS Pro (achat unique à vie, ou abonnement annuel optionnel) : scan d'étiquette illimité, synchronisation iCloud entre vos appareils, analytics de cave et carnet avancé.
Les tarifs sont affichés clairement, en amont. Pas de paywall caché, pas de limite surprise.

CaveOS ne vous espionne pas : vos bouteilles restent sur votre appareil et, si vous l'activez, dans votre iCloud privé. Aucune donnée personnelle envoyée à l'éditeur.

L'app de cave qui marche partout, instantanément, et pour toujours.
```

> **Note** : la description **n'influence pas** le classement App Store (seulement la conversion). Soigne plutôt le nom, le sous-titre, les keywords et les captures.

---

## 4. Mots-clés (Keywords)

**Keywords (97/100)** — sans espace après les virgules, sans répéter les mots du nom/sous-titre :

```
dégustation,millésime,cépage,sommelier,bouteille,étiquette,scanner,oenologie,collection,AOC,garde
```

> Pourquoi ces mots : `cave`, `vin`, `inventaire`, `apogée` sont déjà indexés via le **nom** et le **sous-titre** — inutile de les répéter ici, ça gâche les 100 caractères. Si tu changes le sous-titre, réintègre les mots libérés.
> Alternative orientée différenciation : remplace `collection,AOC,garde` par `sansabonnement,horsligne` (insister sur l'angle « sans abonnement / hors-ligne »).

---

## 5. URLs

Ces trois pages sont **servies par le serveur Go** (`server/pages.go`, routes `/`, `/support`, `/privacy`). Colle-les telles quelles :

| Champ | Valeur | Obligatoire |
|---|---|---|
| **Support URL** | `https://caveos.152.228.136.49.sslip.io/support` | ✅ Oui |
| **Marketing URL** | `https://caveos.152.228.136.49.sslip.io/` | Optionnel |
| **Politique de confidentialité (URL)** | `https://caveos.152.228.136.49.sslip.io/privacy` | ✅ Oui |

> ✅ **Les pages existent maintenant** : `/` (marketing), `/support` (FAQ + contact) et `/privacy` (offline-first, données non collectées, caméra, Stripe, contact). Elles reprennent la charte CaveOS (bordeaux/crème).
>
> ⚠️ **À faire avant de soumettre** :
> 1. **Redéployer le serveur** pour publier ces routes, puis vérifier que chaque URL répond `200` :
>    ```bash
>    curl -I https://caveos.152.228.136.49.sslip.io/privacy   # attendu : HTTP/2 200
>    curl -I https://caveos.152.228.136.49.sslip.io/support
>    curl -I https://caveos.152.228.136.49.sslip.io/
>    ```
> 2. Une URL en `sslip.io` (IP) fonctionne mais fait « bricolé » et **casse si l'IP du VPS change**. **Recommandé** : pose un vrai domaine (ex. `caveos.app`) avant la mise en vente — il suffira de pointer le DNS sur le VPS, les routes sont déjà prêtes.
>
> Une URL de confidentialité morte = **rejet quasi automatique** : ne soumets pas tant que le `curl` ne renvoie pas `200`.

---

## 6. Captures d'écran (le « donne-moi les photos »)

### ✅ Déjà générées et versionnées dans le repo

Capturées automatiquement sur simulateur (app de démo `SampleData`, barre d'état figée à 9:41) via `scripts/screenshots.sh` :

| Dossier | Appareil | Résolution (px) | Orientation | Slot App Store Connect |
|---|---|---|---|---|
| `AppStore/screenshots/iphone-6.5/` | iPhone 11 Pro Max | **1242 × 2688** | portrait | **iPhone 6,5"** |
| `AppStore/screenshots/ipad-13/` | iPad Pro 13" (M4) | **2064 × 2752** | portrait | **iPad 13"** |

6 captures par appareil, prêtes à glisser dans App Store Connect :

| Fichier | Écran |
|---|---|
| `00-Accueil` | Onboarding « Bienvenue dans CaveOS » |
| `01-Cave` | Inventaire (liste + filtres + badges d'apogée) |
| `02-Caves` | Plan de caves (« Mes caves ») |
| `03-Stats` | Statistiques (répartition par couleur, top régions) |
| `04-Accords` | Accords mets-vins |
| `05-Fiche-apogee` | Fiche bouteille avec fenêtre d'apogée |

- **Format** : PNG, RVB, sans transparence — conforme.
- **Pour régénérer** : `./scripts/screenshots.sh` (relance les deux simulateurs et réécrit les dossiers).

> ℹ️ **6,5" vs 6,9"** : tu avais demandé le 6,5". Le slot **6,9" (1290 × 2796)** est désormais celui mis en avant par Apple ; le 6,5" reste un slot valide et accepté. Pour ajouter le 6,9", il suffit de lancer le test sur un *iPhone 16 Pro Max* (ajoute une ligne `run_device` dans le script).

### App Preview (vidéo, optionnel)
- 15–30 s, mêmes résolutions que les captures, .mov/.mp4, H.264/HEVC.
- Démo idéale : ouvrir l'app → scanner une étiquette → déposer la bouteille dans une clayette → ouvrir la fiche apogée.

### Icône
- Déjà fournie automatiquement depuis l'asset `AppIcon` du projet (1024 × 1024, sans transparence). Rien à uploader manuellement.

---

## 7. Version & build

| Champ | Valeur |
|---|---|
| **Version** | `1.0` (= `MARKETING_VERSION` dans `project.yml`) |
| **Build** | Sélectionner le build envoyé via Xcode/TestFlight (statut « Prêt à soumettre ») |
| **Copyright** | `2026 Louis de Caumont` |
| **Nouveautés de cette version** | *Champ absent pour une 1re version.* Pour les mises à jour futures, ex. : « Corrections et améliorations. » |

---

## 8. Classification par âge (Age Rating)

Réponds **honnêtement** au questionnaire — CaveOS référence l'alcool.

- **Alcool, tabac ou drogues / références** : *Oui — Fréquent ou intense* (l'app porte entièrement sur le vin).
- Tout le reste (violence, contenu sexuel, jeux d'argent, horreur, accès web non restreint…) : **Aucun / Non**.

➡️ Résultat attendu : **17+** (ancien système) / **18+** sous le nouveau barème Apple 2026, pour références à l'alcool. C'est normal et conforme.

---

## 9. Confidentialité de l'app (App Privacy)

CaveOS est **offline-first** : les données restent sur l'appareil (et l'iCloud **privé** de l'utilisateur). L'éditeur ne les reçoit pas.

- **Données collectées** : déclare **« Données non collectées »** pour l'app elle-même.
- **Caméra** : justifiée par le scan d'étiquette — chaîne `NSCameraUsageDescription` déjà présente dans l'Info.plist.
- **Si tu actives l'abonnement Stripe (web)** : l'email/paiement sont traités **par Stripe**, hors de l'app. Si l'app n'envoie aucun identifiant personnel au serveur (`/v1/billing/status` ne renvoie qu'un statut), tu peux rester sur « Données non collectées ». Si un identifiant utilisateur transite, déclare **« Informations financières »** / **« Identifiants »**, *non liées à l'identité*, finalité « Fonctionnalité de l'app ».

---

## 10. Informations de revue (App Review Information)

| Champ | Valeur |
|---|---|
| **Connexion requise** | **Non** (l'app fonctionne sans compte) |
| **Prénom / Nom** | Louis de Caumont |
| **Téléphone** | *(à renseigner)* |
| **E-mail** | louis.decaumont@icloud.com |

**Notes pour l'examinateur (à coller)** :

```
CaveOS fonctionne entièrement hors-ligne, sans compte ni connexion : aucun identifiant de démonstration n'est nécessaire.

- Le scan d'étiquette utilise la caméra (framework Vision, traitement 100 % sur l'appareil). À tester sur un appareil réel : la caméra n'est pas disponible dans le simulateur. L'OCR pré-remplit la fiche ; le matching exact du vin n'est pas promis (saisie assistée).
- Le déblocage « CaveOS Pro » (scan illimité, sync iCloud, analytics) se fait par achat in-app StoreKit (achat unique à vie + abonnement annuel optionnel). Une voie d'abonnement web optionnelle via Stripe est proposée en complément ; l'app n'embarque aucune clé et interroge uniquement un statut de facturation.
- La synchronisation iCloud (optionnelle) nécessite un compte iCloud connecté sur l'appareil.

Merci !
```

**Pièce jointe** : optionnel (ex. courte vidéo du scan si tu veux faciliter la revue).

---

## 11. Conformité export (Export Compliance)

- L'app n'utilise que du chiffrement standard (HTTPS).
- Si `ITSAppUsesNonExemptEncryption = NO` est dans l'Info.plist → **aucune question** posée.
- Sinon, réponds : **« Votre app utilise-t-elle du chiffrement ? »** → *Non* (chiffrement exempté uniquement).

---

## 12. Tarif & disponibilité

- **Prix** : `Gratuit` (les fonctions Pro passent par l'achat in-app StoreKit et/ou Stripe).
- **Disponibilité** : tous les pays/régions (par défaut), ou restreins à la France/zone francophone si tu préfères lancer petit.

---

## 13. Mise à disposition de la version (Version Release)

Choisis l'une des trois options après approbation :
- ☐ **Publication manuelle** *(recommandé pour un 1er lancement — tu contrôles l'heure)*
- ☐ Publication automatique dès approbation
- ☐ Publication programmée à une date

---

## Checklist avant « Soumettre pour examen »

- [ ] Nom, sous-titre, description, keywords, texte promo collés
- [ ] URL de support + URL de confidentialité **vivantes** (testées en 200)
- [ ] 5–6 captures iPhone 6,9" (1290×2796) + iPad 13" (2064×2752)
- [ ] Build sélectionné (validé TestFlight)
- [ ] Copyright `2026 Louis de Caumont`
- [ ] Classification d'âge remplie (références alcool → 17+/18+)
- [ ] App Privacy déclarée (Données non collectées)
- [ ] Notes de revue + contact remplis
- [ ] Export compliance répondu
- [ ] Prix = Gratuit, disponibilité OK

---

Voir aussi : le **guide d'étapes complet** (compte, signing, TestFlight, soumission) dans [`APP_STORE_CONNECT.md`](APP_STORE_CONNECT.md), le contexte produit dans [`README.md`](README.md), les spécifications dans [`cdc_caveos.md`](cdc_caveos.md).
