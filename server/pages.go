package main

import (
	"io"
	"net/http"
)

// Pages publiques servies en HTML : page marketing (/), confidentialité (/privacy)
// et support (/support). Ces URLs sont référencées dans la fiche App Store Connect.
// Contenu statique sans entrée utilisateur -> chaînes constantes (pas d'injection).

const (
	contactEmail   = "louis.decaumont@icloud.com"
	lastUpdatedFR  = "25 juin 2026"
	appStoreNotice = "Bientôt disponible sur l'App Store."
)

// pageShell enveloppe un corps HTML dans la charte CaveOS (papier crème + bordeaux).
func pageShell(title, body string) string {
	return `<!doctype html><html lang="fr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>` + title + ` — CaveOS</title>
<meta name="description" content="CaveOS — la cave à vin dans la poche : inventaire hors-ligne, scan d'étiquette et suivi de l'apogée.">
<style>
:root{--wine:#73121f;--wine-dark:#5a0e18;--paper:#f7f3ea;--ink:#2b2320;--muted:#6b5f57;--line:#e4dccb}
*{box-sizing:border-box}
body{margin:0;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",system-ui,sans-serif;
background:var(--paper);color:var(--ink);line-height:1.6}
a{color:var(--wine)}
header.bar{background:var(--wine);color:#f5f0e3;padding:1.1rem 1.25rem}
header.bar .wrap{max-width:48rem;margin:0 auto;display:flex;align-items:center;gap:.6rem}
header.bar .logo{font-size:1.5rem}
header.bar .name{font-weight:700;font-size:1.15rem;letter-spacing:.2px}
header.bar nav{margin-left:auto;display:flex;gap:1.1rem;font-size:.95rem}
header.bar nav a{color:#f0e7d8;text-decoration:none;opacity:.9}
header.bar nav a:hover{opacity:1;text-decoration:underline}
main{max-width:48rem;margin:0 auto;padding:2rem 1.25rem 3rem}
h1{font-size:1.9rem;line-height:1.2;margin:.2rem 0 1rem}
h2{font-size:1.25rem;margin:2rem 0 .6rem;color:var(--wine-dark)}
.lead{font-size:1.15rem;color:var(--muted)}
.updated{color:var(--muted);font-size:.9rem;margin-bottom:1.5rem}
ul{padding-left:1.2rem}li{margin:.3rem 0}
.features{list-style:none;padding:0;display:grid;gap:.75rem;margin:1.5rem 0}
.features li{background:#fff;border:1px solid var(--line);border-radius:.7rem;padding:.9rem 1rem}
.features b{color:var(--wine-dark)}
.cta{display:inline-block;background:var(--wine);color:#f5f0e3;text-decoration:none;
padding:.7rem 1.3rem;border-radius:.6rem;font-weight:600;margin:.4rem .4rem .4rem 0}
.note{background:#fff;border:1px solid var(--line);border-radius:.7rem;padding:1rem 1.2rem;color:var(--muted)}
footer{border-top:1px solid var(--line);max-width:48rem;margin:0 auto;padding:1.5rem 1.25rem;
color:var(--muted);font-size:.9rem;display:flex;flex-wrap:wrap;gap:1rem;align-items:center}
footer a{color:var(--muted)}
footer .sp{margin-left:auto}
</style></head>
<body>
<header class="bar"><div class="wrap">
<span class="logo">🍷</span><span class="name">CaveOS</span>
<nav><a href="/">Accueil</a><a href="/support">Support</a><a href="/privacy">Confidentialité</a></nav>
</div></header>
<main>` + body + `</main>
<footer>
<span>© 2026 Louis de Caumont</span>
<a href="/privacy">Confidentialité</a><a href="/support">Support</a>
<span class="sp">CaveOS — la cave à vin dans la poche</span>
</footer>
</body></html>`
}

// GET / — page marketing (Marketing URL de la fiche App Store).
func (s *server) handleHome(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	body := `<h1>La cave à vin dans la poche.</h1>
<p class="lead">Rapide, honnête, et qui marche partout — même sans réseau. CaveOS range vos bouteilles,
suit leur apogée et retrouve n'importe quel cru en quelques secondes.</p>
<p><a class="cta" href="/support">Besoin d'aide&nbsp;?</a><a class="cta" href="/privacy" style="background:#fff;color:var(--wine);border:1px solid var(--line)">Confidentialité</a></p>
<ul class="features">
<li><b>Scan d'étiquette hors-ligne</b> — pointez la caméra, la fiche se pré-remplit. Aucun serveur, aucune connexion requise.</li>
<li><b>Votre cave, fidèlement reproduite</b> — caves, clayettes et niveaux illimités, avec glisser-déposer des bouteilles.</li>
<li><b>Apogée intelligente</b> — la fenêtre de dégustation idéale estimée pour chaque vin, avec notifications.</li>
<li><b>Recherche instantanée</b> — filtres par cépage, région, millésime, prix, apogée. Tout répond hors-ligne.</li>
<li><b>Vos données vous appartiennent</b> — stockage local (et iCloud privé si vous l'activez), export CSV libre et gratuit.</li>
<li><b>Gratuit, honnêtement</b> — ajout illimité gratuit. CaveOS Pro débloque le scan illimité, la sync et les analytics, à prix affiché.</li>
</ul>
<p class="note">` + appStoreNotice + ` &nbsp;En attendant, écrivez-nous à <a href="mailto:` + contactEmail + `">` + contactEmail + `</a>.</p>`
	writeHTML(w, pageShell("Accueil", body))
}

// GET /privacy — politique de confidentialité (Privacy Policy URL de la fiche App Store).
func (s *server) handlePrivacy(w http.ResponseWriter, _ *http.Request) {
	body := `<h1>Politique de confidentialité</h1>
<p class="updated">Dernière mise à jour : ` + lastUpdatedFR + `</p>
<p class="lead">CaveOS est conçue selon le principe <b>offline-first</b> : vos données restent sur votre
appareil. Nous, l'éditeur, ne les collectons pas.</p>

<h2>Données que nous collectons</h2>
<p><b>Aucune.</b> Tout ce que vous saisissez dans CaveOS (bouteilles, emplacements, notes de dégustation,
photos d'étiquettes) est stocké <b>localement</b> sur votre appareil. Nous ne recevons ni ne stockons
aucune de ces informations sur nos serveurs.</p>

<h2>iCloud (optionnel)</h2>
<p>Si vous activez la synchronisation, vos données sont répliquées via votre <b>iCloud privé</b>, géré par
Apple sous votre compte. Elles ne transitent jamais par nous et restent soumises à la
<a href="https://www.apple.com/legal/privacy/">politique de confidentialité d'Apple</a>.</p>

<h2>Caméra</h2>
<p>CaveOS utilise la caméra uniquement pour scanner les étiquettes et codes-barres et pré-remplir une fiche.
La reconnaissance est réalisée <b>entièrement sur l'appareil</b> (framework Vision d'Apple). Les images ne
sont pas envoyées à un serveur ni conservées par l'éditeur.</p>

<h2>Données de référence sur le vin</h2>
<p>L'app peut interroger notre service pour rechercher des cépages, régions et appellations, ou estimer une
fenêtre d'apogée. Ces requêtes ne contiennent <b>aucune donnée personnelle</b> et ne sont pas associées à
votre identité. Les données de référence proviennent de sources ouvertes (voir
<a href="/credits">crédits</a>).</p>

<h2>Paiement (CaveOS Pro)</h2>
<p>Les achats Pro (achat unique « à vie » ou abonnement annuel) sont effectués via l'<b>App Store</b>
et gérés entièrement par <b>Apple</b> : nous ne recevons ni ne conservons aucune information de
paiement. Aucun prestataire de paiement tiers n'est utilisé.</p>

<h2>Partage avec des tiers</h2>
<p>Nous ne vendons, ne louons ni ne partageons aucune donnée personnelle. Aucun pisteur publicitaire,
aucun outil d'analyse tiers n'est intégré à l'app.</p>

<h2>Enfants</h2>
<p>CaveOS porte sur le vin et n'est pas destinée aux mineurs. Nous ne collectons pas sciemment de données
concernant des enfants.</p>

<h2>Vos droits</h2>
<p>Comme vos données vivent sur votre appareil, vous en gardez le contrôle total : vous pouvez les modifier,
les exporter en CSV ou les supprimer à tout moment depuis l'app. La désinstallation efface les données
locales.</p>

<h2>Modifications</h2>
<p>Cette politique peut évoluer. La date de dernière mise à jour ci-dessus reflète la version en vigueur.</p>

<h2>Contact</h2>
<p>Pour toute question relative à la confidentialité : <a href="mailto:` + contactEmail + `">` + contactEmail + `</a>.</p>`
	writeHTML(w, pageShell("Confidentialité", body))
}

// GET /support — page d'assistance (Support URL de la fiche App Store).
func (s *server) handleSupport(w http.ResponseWriter, _ *http.Request) {
	body := `<h1>Support</h1>
<p class="lead">Une question, un bug, une idée&nbsp;? Nous lisons tous les messages.</p>
<p><a class="cta" href="mailto:` + contactEmail + `?subject=Support%20CaveOS">Nous écrire</a></p>
<p>E-mail&nbsp;: <a href="mailto:` + contactEmail + `">` + contactEmail + `</a></p>

<h2>Questions fréquentes</h2>
<h2 style="font-size:1.05rem">CaveOS fonctionne-t-elle sans connexion&nbsp;?</h2>
<p>Oui. Consultation, ajout, déplacement, recherche et scan d'étiquette fonctionnent entièrement hors-ligne.</p>

<h2 style="font-size:1.05rem">Le scan ne reconnaît pas mon étiquette.</h2>
<p>Le scan lit le texte de l'étiquette pour pré-remplir la fiche (il ne promet pas la reconnaissance du vin
exact). Améliorez les résultats avec un bon éclairage, en cadrant l'étiquette bien à plat, et reprenez la
photo si besoin. Vous pouvez toujours compléter les champs à la main.</p>

<h2 style="font-size:1.05rem">Comment fonctionne la synchronisation entre appareils&nbsp;?</h2>
<p>La sync utilise votre iCloud privé. Connectez le même compte iCloud sur vos appareils et activez la
synchronisation dans les réglages de l'app. Vos données ne passent jamais par nos serveurs.</p>

<h2 style="font-size:1.05rem">Comment récupérer mon achat CaveOS Pro&nbsp;?</h2>
<p>Dans l'app, utilisez « Restaurer les achats ». Les achats App Store sont liés à votre identifiant Apple.</p>

<h2 style="font-size:1.05rem">Comment exporter mes données&nbsp;?</h2>
<p>L'export CSV est gratuit et disponible à tout moment depuis l'app. Vos données vous appartiennent.</p>

<p class="note" style="margin-top:1.5rem">` + appStoreNotice + ` Voir aussi notre <a href="/privacy">politique de confidentialité</a>.</p>`
	writeHTML(w, pageShell("Support", body))
}

func writeHTML(w http.ResponseWriter, html string) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = io.WriteString(w, html)
}
