package main

import "encoding/json"

type listPayload struct {
	Wines []struct {
		Producer    string   `json:"producer"`
		WineName    string   `json:"wineName"`
		Vintage     int      `json:"vintage"`
		Appellation string   `json:"appellation"`
		Grapes      []string `json:"grapes"`
		Price       *float64 `json:"price"`
		Currency    string   `json:"currency"`
		ByGlass     bool     `json:"byGlass"`
		PriceGlass  *float64 `json:"priceGlass"`
	} `json:"wines"`
}

// parseListPayload transforme le JSON LLM en []ScanListItem, borné à maxListWines.
func parseListPayload(raw []byte) ([]ScanListItem, bool, error) {
	var p listPayload
	if err := json.Unmarshal(raw, &p); err != nil {
		return nil, false, err
	}
	truncated := false
	src := p.Wines
	if len(src) > maxListWines {
		src = src[:maxListWines]
		truncated = true
	}
	items := make([]ScanListItem, 0, len(src))
	for i, w := range src {
		items = append(items, ScanListItem{
			ScanResult: ScanResult{
				Producer:    w.Producer,
				WineName:    w.WineName,
				Vintage:     w.Vintage,
				Appellation: w.Appellation,
				Grapes:      w.Grapes,
			},
			Price:      w.Price,
			Currency:   w.Currency,
			ByGlass:    w.ByGlass,
			PriceGlass: w.PriceGlass,
			LineIndex:  i,
		})
	}
	return items, truncated, nil
}
