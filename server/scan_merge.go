package main

import "strings"

// --- Passe 1 : fusion champ par champ des résultats de lecture ----------------
//
// mergePass1 combine les ScanResult renvoyés par les fournisseurs de la passe 1
// (mistral OCR + gemini). La fusion est purement fonctionnelle : on lit les
// résultats en entrée et on construit un nouveau ScanResult sans muter l'entrée.
// L'ordre des `successes` suit pass1Order, donc le premier (mistral/OCR) gagne
// les tie-breaks — il lit chiffres et accents le plus littéralement.

// maxGrapes plafonne la liste de cépages fusionnée (garde-fou anti-bruit).
const maxGrapes = 12

// mergePass1 fusionne des résultats de lecture garantis non vides.
func mergePass1(successes []ScanResult) ScanResult {
	var out ScanResult
	names := make([]string, 0, len(successes))
	for _, r := range successes {
		names = append(names, r.Provider)
		out.Producer = pickString(out.Producer, r.Producer)
		out.WineName = pickString(out.WineName, r.WineName)
		out.Appellation = pickString(out.Appellation, r.Appellation)
		out.Format = pickString(out.Format, r.Format)
		out.ABV = pickString(out.ABV, r.ABV)
		out.Vintage = pickVintage(out.Vintage, r.Vintage)
		out.Grapes = unionGrapes(out.Grapes, r.Grapes)
	}
	out.Provider = strings.Join(names, "+") // "mistral+gemini" ou le survivant seul
	return out
}

// pickString choisit la meilleure des deux chaînes : la non vide, le surensemble
// (l'une contient l'autre), sinon la « plus riche » (cf. richer).
func pickString(a, b string) string {
	a, b = strings.TrimSpace(a), strings.TrimSpace(b)
	switch {
	case a == "":
		return b
	case b == "":
		return a
	case strings.EqualFold(a, b):
		return richer(a, b) // même valeur, garde la mieux accentuée
	case containsFold(a, b):
		return a // a est un surensemble de b
	case containsFold(b, a):
		return b // b est un surensemble de a
	default:
		return richer(a, b) // conflit réel
	}
}

// richer privilégie le plus de diacritiques (OCR fidèle aux accents), puis la
// chaîne la plus longue, avec un tie-break déterministe sur `a` (1er = priorité
// pass1Order).
func richer(a, b string) string {
	if da, db := diacritics(a), diacritics(b); da != db {
		if da > db {
			return a
		}
		return b
	}
	if len(a) != len(b) {
		if len(a) > len(b) {
			return a
		}
		return b
	}
	return a
}

// containsFold indique si a contient b, sans tenir compte de la casse.
func containsFold(a, b string) bool {
	return strings.Contains(strings.ToLower(a), strings.ToLower(b))
}

// diacritics compte les runes non ASCII (proxy simple du nombre d'accents).
func diacritics(s string) int {
	n := 0
	for _, r := range s {
		if r > 127 {
			n++
		}
	}
	return n
}

// pickVintage fusionne deux millésimes (0 = absent, déjà validé par parseVintage).
// En cas de conflit on garde le premier (priorité mistral/OCR).
func pickVintage(a, b int) int {
	switch {
	case a == 0:
		return b
	case b == 0:
		return a
	case a == b:
		return a
	default:
		return a // conflit -> priorité au 1er (lit les chiffres littéralement)
	}
}

// unionGrapes réalise l'union dédupliquée (casse-insensible) des listes de
// cépages, dans l'ordre de première apparition, plafonnée à maxGrapes.
func unionGrapes(lists ...[]string) []string {
	out := make([]string, 0)
	seen := map[string]bool{}
	for _, l := range lists {
		for _, g := range l {
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
			if len(out) >= maxGrapes {
				return out
			}
		}
	}
	return out
}
