package main

// isWineList: heuristique simple — au moins 2 entrées portant un nom ou un producteur.
// Une seule entrée = probablement une étiquette unique, pas une carte.
func isWineList(items []ScanListItem) bool {
	named := 0
	for _, it := range items {
		if it.WineName != "" || it.Producer != "" {
			named++
		}
	}
	return named >= 2
}
