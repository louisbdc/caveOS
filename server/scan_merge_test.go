package main

import (
	"reflect"
	"testing"
)

func TestPickString(t *testing.T) {
	cases := []struct {
		name, a, b, want string
	}{
		{"a vide", "", "Margaux", "Margaux"},
		{"b vide", "Margaux", "", "Margaux"},
		{"surensemble a", "Château Margaux", "Margaux", "Château Margaux"},
		{"surensemble b", "Margaux", "Château Margaux", "Château Margaux"},
		{"accents prioritaires", "Chateau", "Château", "Château"},
		{"egalite fold garde le 1er", "Margaux", "margaux", "Margaux"},
		{"conflit longueur", "Domaine A", "Dom B", "Domaine A"},
	}
	for _, c := range cases {
		if got := pickString(c.a, c.b); got != c.want {
			t.Errorf("%s: pickString(%q,%q)=%q, attendu %q", c.name, c.a, c.b, got, c.want)
		}
	}
}

func TestPickVintage(t *testing.T) {
	cases := []struct {
		a, b, want int
	}{
		{0, 2015, 2015},
		{2015, 0, 2015},
		{2015, 2015, 2015},
		{2015, 2016, 2015}, // conflit -> garde le 1er
	}
	for _, c := range cases {
		if got := pickVintage(c.a, c.b); got != c.want {
			t.Errorf("pickVintage(%d,%d)=%d, attendu %d", c.a, c.b, got, c.want)
		}
	}
}

func TestUnionGrapes(t *testing.T) {
	got := unionGrapes(
		[]string{"Merlot", "Cabernet Sauvignon"},
		[]string{"merlot", "Cabernet Franc", " "},
	)
	want := []string{"Merlot", "Cabernet Sauvignon", "Cabernet Franc"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("union=%v, attendu %v", got, want)
	}

	// Plafond maxGrapes.
	big := make([]string, maxGrapes+5)
	for i := range big {
		big[i] = "cepage" + string(rune('A'+i))
	}
	if got := unionGrapes(big); len(got) != maxGrapes {
		t.Fatalf("plafond non respecté: %d", len(got))
	}
}

func TestMergePass1(t *testing.T) {
	t.Run("complementaires", func(t *testing.T) {
		got := mergePass1([]ScanResult{
			{Provider: "mistral", Producer: "Château Margaux", Vintage: 2015, Grapes: []string{"Merlot"}},
			{Provider: "gemini", Appellation: "Margaux", ABV: "13,5 %", Grapes: []string{"Cabernet Sauvignon"}},
		})
		if got.Provider != "mistral+gemini" {
			t.Fatalf("provider=%q", got.Provider)
		}
		if got.Producer != "Château Margaux" || got.Appellation != "Margaux" || got.Vintage != 2015 || got.ABV != "13,5 %" {
			t.Fatalf("fusion inattendue: %+v", got)
		}
		if len(got.Grapes) != 2 {
			t.Fatalf("cépages=%v", got.Grapes)
		}
	})

	t.Run("survivant seul", func(t *testing.T) {
		got := mergePass1([]ScanResult{
			{Provider: "gemini", Producer: "Domaine Seul", Vintage: 2019},
		})
		if got.Provider != "gemini" || got.Producer != "Domaine Seul" || got.Vintage != 2019 {
			t.Fatalf("passthrough inattendu: %+v", got)
		}
	})
}
