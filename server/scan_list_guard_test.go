package main

import "testing"

func TestIsWineList(t *testing.T) {
	cases := []struct {
		name string
		in   []ScanListItem
		want bool
	}{
		{"vide", nil, false},
		{"une entrée sans nom ni producteur", []ScanListItem{{}}, false},
		{
			"deux vins nommés",
			[]ScanListItem{
				{ScanResult: ScanResult{WineName: "Cahors", Producer: "Clos La Coutale"}},
				{ScanResult: ScanResult{WineName: "Chinon"}},
			},
			true,
		},
		{
			"une seule entrée nommée (ressemble à une étiquette, pas une carte)",
			[]ScanListItem{{ScanResult: ScanResult{WineName: "Cahors", Producer: "X"}}},
			false,
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := isWineList(c.in); got != c.want {
				t.Fatalf("isWineList = %v, want %v", got, c.want)
			}
		})
	}
}
