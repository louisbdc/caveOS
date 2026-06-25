package main

import (
	"context"
	"encoding/json"
	"fmt"
	"sort"
	"strconv"
	"strings"
	"time"
)

// --- Passe 2 : enrichissement par déduction (modèle texte, sans image) --------
//
// La passe 2 reçoit les champs LUS et fusionnés de la passe 1 et DÉDUIT les
// champs absents de l'étiquette (couleur, type, région, pays, cépages probables,
// fenêtre d'apogée). Elle est best-effort : si tous les fournisseurs échouent, le
// résultat de la passe 1 est renvoyé inchangé (jamais de 5xx). La DB locale
// (s.enrich) reste prioritaire sur le LLM pour la fenêtre/région/pays.

// enrichInput = champs LUS fusionnés, envoyés au modèle texte (sans image).
type enrichInput struct {
	Producer    string
	WineName    string
	Appellation string
	Format      string
	ABV         string
	Vintage     int
	Grapes      []string
}

// enrichOutput = champs DÉDUITS normalisés renvoyés par un fournisseur passe 2.
type enrichOutput struct {
	Color       string
	WineType    string
	Country     string
	Region      string
	GrapesGuess []string
	PeakFrom    int
	PeakTo      int
}

// enrichProvider abstrait un moteur de déduction texte. Chaque fournisseur lit sa
// propre clé d'API et expose son état de configuration.
type enrichProvider interface {
	name() string
	configured() bool
	enrich(ctx context.Context, in enrichInput) (enrichOutput, error)
}

// Ensembles autorisés des valeurs déduites, alignés sur les enums Swift
// (WineColor.rawValue / WineType.rawValue). Toute valeur hors-liste est droppée.
var (
	wineColorList = []string{"red", "white", "rose", "sparkling", "sweet", "fortified", "orange"}
	wineTypeList  = []string{"still", "sparkling", "fortified", "sweet"}
	wineColors    = toEnumSet(wineColorList)
	wineTypes     = toEnumSet(wineTypeList)
)

func toEnumSet(values []string) map[string]bool {
	set := make(map[string]bool, len(values))
	for _, v := range values {
		set[v] = true
	}
	return set
}

// enrichInstruction est l'invite de la passe 2. Elle insiste sur la séparation
// lu/déduit : le modèle ne renseigne QUE les champs nouveaux, en estimation.
const enrichInstruction = "Tu es sommelier expert. On te fournit les champs LU sur une étiquette de vin (déjà extraits, fiables). " +
	"À partir de ta connaissance du vin, DÉDUIS uniquement les champs suivants : " +
	"color (couleur: red, white, rose, sparkling, sweet, fortified, orange), " +
	"wineType (élaboration: still, sparkling, fortified, sweet), " +
	"country (pays), region (région viticole), " +
	"grapesGuess (cépages PROBABLES de l'appellation — n'inclus PAS les cépages déjà fournis), " +
	"peakFrom et peakTo (fenêtre d'apogée en années civiles, basée sur millésime/cépage/région). " +
	"Ce sont des ESTIMATIONS, jamais des valeurs lues sur l'étiquette. " +
	"Renseigne seulement ce que tu peux déduire avec une confiance raisonnable ; mets null/0 sinon. " +
	"Ne modifie pas et ne répète pas les champs lus. Respecte STRICTEMENT le schéma JSON."

// newEnrichProviders construit le registre ordonné des fournisseurs de la passe 2
// (primaire d'abord, repli ensuite) : gemini-3.1-flash-lite puis mistral-small.
func newEnrichProviders() []enrichProvider {
	return []enrichProvider{newGeminiEnrichProvider(), newMistralEnrichProvider()}
}

// --- Orchestration -----------------------------------------------------------

// applyPass2 enrichit r par déduction LLM (best-effort) puis par la DB locale
// (déterministe, prioritaire pour fenêtre/région/pays). Le résultat marque chaque
// champ effectivement renseigné dans InferredFields. Ne renvoie jamais d'erreur :
// si la passe 2 échoue, r est renvoyé inchangé.
func (s *server) applyPass2(ctx context.Context, r ScanResult) ScanResult {
	inferred := map[string]bool{}

	// 1) Passe 2 LLM (primaire puis repli). On n'écrit QUE des champs déduits,
	//    et on ne marque inférés que ceux réellement renseignés (jamais un LU).
	if out, ok := s.runPass2(ctx, toEnrichInput(r)); ok {
		if c := keepIfEnum(out.Color, wineColors); c != "" {
			r.Color, inferred["color"] = c, true
		}
		if t := keepIfEnum(out.WineType, wineTypes); t != "" {
			r.WineType, inferred["wineType"] = t, true
		}
		if c := strings.TrimSpace(out.Country); c != "" {
			r.Country, inferred["country"] = c, true
		}
		if reg := strings.TrimSpace(out.Region); reg != "" {
			r.Region, inferred["region"] = reg, true
		}
		if g := subtract(out.GrapesGuess, r.Grapes); len(g) > 0 {
			r.GrapesGuess, inferred["grapesGuess"] = g, true
		}
		// Fenêtre d'apogée : on ne pose les deux bornes qu'ensemble et cohérentes
		// (0 < peakFrom <= peakTo). Un LLM peut renvoyer une borne seule ou une
		// fenêtre inversée — on l'ignore alors plutôt que d'exposer du bruit.
		if out.PeakFrom > 0 && out.PeakTo >= out.PeakFrom {
			r.PeakFrom, inferred["peakFrom"] = out.PeakFrom, true
			r.PeakTo, inferred["peakTo"] = out.PeakTo, true
		}
	}

	// 2) DB locale déterministe : prioritaire sur le LLM pour fenêtre/région/pays.
	if from, peak, to, region, country, ok := s.localWindow(r); ok {
		r.PeakFrom, r.Peak, r.PeakTo = from, peak, to
		inferred["peakFrom"], inferred["peak"], inferred["peakTo"] = true, true, true
		if region != "" {
			r.Region, inferred["region"] = region, true
		}
		if country != "" {
			r.Country, inferred["country"] = country, true
		}
	}

	r.InferredFields = sortedKeys(inferred)
	return r
}

// runPass2 essaie chaque fournisseur configuré dans l'ordre (primaire → repli) et
// renvoie le premier succès. Best-effort : aucun fournisseur ⇒ (zéro, false).
func (s *server) runPass2(ctx context.Context, in enrichInput) (enrichOutput, bool) {
	for _, p := range s.enrichProviders {
		if !p.configured() {
			continue
		}
		pctx, cancel := context.WithTimeout(ctx, pass2Timeout)
		out, err := p.enrich(pctx, in)
		cancel()
		if err != nil {
			s.logger.Warn("pass2 failed", "provider", p.name(), "error", err)
			continue
		}
		return out, true
	}
	return enrichOutput{}, false
}

// localWindow réutilise s.enrich() (DB locale, déterministe et offline) pour
// obtenir une fenêtre d'apogée + région/pays fiables quand l'étiquette matche le
// référentiel. Renvoie ok=false (et on retombe sur le LLM) si rien ne matche.
// La région n'est renvoyée que si elle existe déjà dans le référentiel : aucune
// entité n'est créée.
func (s *server) localWindow(r ScanResult) (from, peak, to int, region, country string, ok bool) {
	if r.Vintage == 0 {
		return
	}
	name := strings.TrimSpace(strings.Join([]string{r.Appellation, r.WineName, strings.Join(r.Grapes, " ")}, " "))
	if name == "" {
		return
	}
	res, err := s.enrich(name, r.Vintage)
	if err != nil {
		return // errNoMatch -> on garde les valeurs du LLM
	}
	if reg, e := s.regionByName(res.RegionName); e == nil {
		country = reg.Country
	}
	return res.DrinkFrom, res.Peak, res.DrinkBy, res.RegionName, country, true
}

// toEnrichInput projette les champs LUS d'un ScanResult en entrée de passe 2.
func toEnrichInput(r ScanResult) enrichInput {
	return enrichInput{
		Producer:    r.Producer,
		WineName:    r.WineName,
		Appellation: r.Appellation,
		Format:      r.Format,
		ABV:         r.ABV,
		Vintage:     r.Vintage,
		Grapes:      r.Grapes,
	}
}

// --- Helpers de normalisation ------------------------------------------------

// keepIfEnum renvoie la valeur normalisée (minuscules) si elle appartient à
// l'ensemble autorisé, sinon une chaîne vide (drop des valeurs hors-liste).
func keepIfEnum(v string, set map[string]bool) string {
	v = strings.ToLower(strings.TrimSpace(v))
	if set[v] {
		return v
	}
	return ""
}

// subtract retire de guess les cépages déjà présents dans known (casse-insensible)
// et déduplique guess. Le résultat est un nouveau slice (pas de mutation).
func subtract(guess, known []string) []string {
	seen := map[string]bool{}
	for _, g := range known {
		if k := strings.ToLower(strings.TrimSpace(g)); k != "" {
			seen[k] = true
		}
	}
	out := make([]string, 0, len(guess))
	for _, g := range guess {
		g = strings.TrimSpace(g)
		if g == "" {
			continue
		}
		k := strings.ToLower(g)
		if seen[k] {
			continue
		}
		seen[k] = true
		out = append(out, g)
	}
	return out
}

// sortedKeys renvoie, triées, les clés dont la valeur est vraie.
func sortedKeys(m map[string]bool) []string {
	out := make([]string, 0, len(m))
	for k, v := range m {
		if v {
			out = append(out, k)
		}
	}
	sort.Strings(out)
	return out
}

// --- Décodage tolérant de la sortie passe 2 ----------------------------------

// aiEnrich reçoit la sortie JSON brute de la passe 2. peakFrom/peakTo sont typés
// `any` pour tolérer entier, flottant, chaîne ("2030") ou null indifféremment,
// par symétrie avec aiLabel (passe 1).
type aiEnrich struct {
	Color       string   `json:"color"`
	WineType    string   `json:"wineType"`
	Country     string   `json:"country"`
	Region      string   `json:"region"`
	GrapesGuess []string `json:"grapesGuess"`
	PeakFrom    any      `json:"peakFrom"`
	PeakTo      any      `json:"peakTo"`
}

// decodeEnrichOutput décode une chaîne JSON produite par un modèle en
// enrichOutput, en tolérant un encadrement Markdown ```json … ```. Le filtrage
// enum couleur/type est laissé à applyPass2 (keepIfEnum) ; ici on se contente de
// nettoyer et de déduire les cépages probables uniques.
func decodeEnrichOutput(jsonText string) (enrichOutput, error) {
	jsonText = stripJSONFence(jsonText)
	dec := json.NewDecoder(strings.NewReader(jsonText))
	dec.UseNumber()
	var raw aiEnrich
	if err := dec.Decode(&raw); err != nil {
		return enrichOutput{}, fmt.Errorf("décodage de la sortie d'enrichissement: %w", err)
	}

	grapes := make([]string, 0, len(raw.GrapesGuess))
	seen := map[string]bool{}
	for _, g := range raw.GrapesGuess {
		g = strings.TrimSpace(g)
		if g == "" {
			continue
		}
		k := strings.ToLower(g)
		if seen[k] {
			continue
		}
		seen[k] = true
		grapes = append(grapes, g)
	}

	return enrichOutput{
		Color:       strings.TrimSpace(raw.Color),
		WineType:    strings.TrimSpace(raw.WineType),
		Country:     strings.TrimSpace(raw.Country),
		Region:      strings.TrimSpace(raw.Region),
		GrapesGuess: grapes,
		PeakFrom:    parsePeakYear(anyToString(raw.PeakFrom)),
		PeakTo:      parsePeakYear(anyToString(raw.PeakTo)),
	}, nil
}

// parsePeakYear extrait une année d'apogée plausible. Symétrique de parseVintage
// mais avec une borne haute élargie : une fenêtre d'apogée se projette dans le
// futur (jusqu'à plusieurs décennies pour les grands vins), donc le plafond
// now+1 de parseVintage serait trop strict ici.
func parsePeakYear(raw string) int {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return 0
	}
	if dot := strings.IndexByte(raw, '.'); dot >= 0 {
		raw = raw[:dot] // "2030.0" -> "2030"
	}
	year, err := strconv.Atoi(raw)
	if err != nil || year < 1900 || year > time.Now().Year()+60 {
		return 0
	}
	return year
}

// enrichUserText construit le message utilisateur de la passe 2 : les champs LUS
// sérialisés en JSON compact, sans image ni donnée sensible additionnelle.
func enrichUserText(in enrichInput) (string, error) {
	payload := map[string]any{
		"producer":    in.Producer,
		"wineName":    in.WineName,
		"appellation": in.Appellation,
		"format":      in.Format,
		"abv":         in.ABV,
		"vintage":     in.Vintage,
		"grapes":      in.Grapes,
	}
	b, err := json.Marshal(payload)
	if err != nil {
		return "", fmt.Errorf("encodage des champs lus: %w", err)
	}
	return "Champs lus: " + string(b), nil
}
