package main

const maxListWines = 60

// ScanListItem = un vin lu sur une carte, enrichi comme un scan mono-vin + infos prix.
type ScanListItem struct {
	ScanResult
	Price      *float64 `json:"price,omitempty"`
	Currency   string   `json:"currency,omitempty"`
	ByGlass    bool     `json:"byGlass,omitempty"`
	PriceGlass *float64 `json:"priceGlass,omitempty"`
	LineIndex  int      `json:"lineIndex"`
}

// ScanListResponse = réponse de POST /v1/scan/list.
type ScanListResponse struct {
	Wines       []ScanListItem `json:"wines"`
	Count       int            `json:"count"`
	Provider    string         `json:"provider"`
	Truncated   bool           `json:"truncated,omitempty"`
	NotWineList bool           `json:"notWineList,omitempty"`
}
