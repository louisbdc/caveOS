package main

import (
	"context"
	"errors"
	"testing"
)

func TestEnrichListItemsBestEffort(t *testing.T) {
	items := []ScanListItem{
		{ScanResult: ScanResult{WineName: "OK"}, LineIndex: 0},
		{ScanResult: ScanResult{WineName: "FAIL"}, LineIndex: 1},
	}
	// enrichisseur injecté : ajoute Color sauf pour "FAIL" qui renvoie une erreur.
	enrich := func(ctx context.Context, in ScanResult) (ScanResult, error) {
		if in.WineName == "FAIL" {
			return in, errors.New("boom")
		}
		out := in
		out.Color = "red"
		return out, nil
	}
	got := enrichListItemsWith(context.Background(), items, enrich)
	if len(got) != 2 {
		t.Fatalf("len = %d, want 2", len(got))
	}
	// L'ordre (LineIndex) doit être préservé.
	byLine := map[int]ScanListItem{}
	for _, it := range got {
		byLine[it.LineIndex] = it
	}
	if byLine[0].Color != "red" {
		t.Fatalf("item0 non enrichi: %+v", byLine[0])
	}
	if byLine[1].Color != "" {
		t.Fatalf("item1 aurait dû rester non enrichi: %+v", byLine[1])
	}
}
