package main

import "testing"

func TestParseListPayload(t *testing.T) {
	raw := []byte(`{"wines":[
		{"producer":"Clos La Coutale","wineName":"Cahors","vintage":2018,"price":38,"currency":"EUR"},
		{"wineName":"Chinon","vintage":2020,"price":34,"byGlass":true,"priceGlass":8}
	]}`)
	items, truncated, err := parseListPayload(raw)
	if err != nil {
		t.Fatalf("err inattendue: %v", err)
	}
	if truncated {
		t.Fatalf("truncated = true, want false")
	}
	if len(items) != 2 {
		t.Fatalf("len = %d, want 2", len(items))
	}
	if items[0].Producer != "Clos La Coutale" || items[0].LineIndex != 0 {
		t.Fatalf("item0 inattendu: %+v", items[0])
	}
	if items[1].LineIndex != 1 || !items[1].ByGlass || items[1].PriceGlass == nil || *items[1].PriceGlass != 8 {
		t.Fatalf("item1 inattendu: %+v", items[1])
	}
}

func TestParseListPayloadTruncates(t *testing.T) {
	// Construit maxListWines+5 entrées.
	b := []byte(`{"wines":[`)
	for i := 0; i < maxListWines+5; i++ {
		if i > 0 {
			b = append(b, ',')
		}
		b = append(b, []byte(`{"wineName":"V"}`)...)
	}
	b = append(b, []byte(`]}`)...)
	items, truncated, err := parseListPayload(b)
	if err != nil {
		t.Fatalf("err: %v", err)
	}
	if !truncated || len(items) != maxListWines {
		t.Fatalf("len=%d truncated=%v, want %d/true", len(items), truncated, maxListWines)
	}
}
