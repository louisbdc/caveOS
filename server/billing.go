package main

import (
	"database/sql"
	"encoding/json"
	"io"
	"net/http"
	"os"
	"time"

	"github.com/stripe/stripe-go/v81"
	bpsession "github.com/stripe/stripe-go/v81/billingportal/session"
	"github.com/stripe/stripe-go/v81/checkout/session"
	"github.com/stripe/stripe-go/v81/subscription"
	"github.com/stripe/stripe-go/v81/webhook"
)

// billing regroupe la configuration Stripe, chargée depuis l'environnement.
// La clé secrète n'est JAMAIS dans le code : elle vient de STRIPE_SECRET_KEY (env, hors git).
type billing struct {
	priceID       string
	webhookSecret string
	publicBaseURL string
	enabled       bool
}

func loadBilling() billing {
	key := os.Getenv("STRIPE_SECRET_KEY")
	b := billing{
		priceID:       os.Getenv("STRIPE_PRICE_ID"),
		webhookSecret: os.Getenv("STRIPE_WEBHOOK_SECRET"),
		publicBaseURL: os.Getenv("PUBLIC_BASE_URL"),
		enabled:       key != "" && os.Getenv("STRIPE_PRICE_ID") != "",
	}
	if key != "" {
		stripe.Key = key
	}
	if b.publicBaseURL == "" {
		b.publicBaseURL = "https://caveos.152.228.136.49.sslip.io"
	}
	return b
}

// initBillingSchema crée la table d'entitlements (statut d'abonnement par appareil).
func initBillingSchema(db *sql.DB) error {
	const ddl = `
CREATE TABLE IF NOT EXISTS subscriptions (
	ref             TEXT PRIMARY KEY,
	customer_id     TEXT,
	subscription_id TEXT,
	status          TEXT,
	updated_at      INTEGER
);
CREATE INDEX IF NOT EXISTS idx_sub_customer ON subscriptions(customer_id);
`
	_, err := db.Exec(ddl)
	return err
}

// isActiveStatus indique si un statut d'abonnement Stripe ouvre les droits Pro.
func isActiveStatus(status string) bool {
	return status == "active" || status == "trialing"
}

type refRequest struct {
	Ref string `json:"ref"`
}

func decodeRef(r *http.Request) string {
	var body refRequest
	_ = json.NewDecoder(io.LimitReader(r.Body, 1<<16)).Decode(&body)
	return body.Ref
}

// POST /v1/billing/checkout — crée une session Checkout d'abonnement et renvoie son URL.
func (s *server) handleCheckout(w http.ResponseWriter, r *http.Request) {
	if !s.billing.enabled {
		writeJSON(w, http.StatusServiceUnavailable, map[string]any{"error": "billing non configuré"})
		return
	}
	ref := decodeRef(r)
	if ref == "" {
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": "ref requis"})
		return
	}

	params := &stripe.CheckoutSessionParams{
		Mode: stripe.String(string(stripe.CheckoutSessionModeSubscription)),
		LineItems: []*stripe.CheckoutSessionLineItemParams{{
			Price:    stripe.String(s.billing.priceID),
			Quantity: stripe.Int64(1),
		}},
		ClientReferenceID: stripe.String(ref),
		SuccessURL:        stripe.String(s.billing.publicBaseURL + "/billing/success?session_id={CHECKOUT_SESSION_ID}"),
		CancelURL:         stripe.String(s.billing.publicBaseURL + "/billing/cancel"),
	}
	// NB: aucun payment_method_types — Stripe choisit dynamiquement les moyens de paiement.

	sess, err := session.New(params)
	if err != nil {
		s.serverError(w, "stripe checkout", err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"url": sess.URL})
}

// GET /v1/billing/status?ref=... — renvoie l'état d'abonnement pour un appareil.
func (s *server) handleBillingStatus(w http.ResponseWriter, r *http.Request) {
	ref := r.URL.Query().Get("ref")
	if ref == "" {
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": "ref requis"})
		return
	}
	var status string
	err := s.db.QueryRow("SELECT status FROM subscriptions WHERE ref = ?", ref).Scan(&status)
	if err == sql.ErrNoRows {
		writeJSON(w, http.StatusOK, map[string]any{"active": false, "status": "none"})
		return
	}
	if err != nil {
		s.serverError(w, "billing status", err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"active": isActiveStatus(status), "status": status})
}

// POST /v1/billing/portal — crée une session du portail client (gestion/annulation).
func (s *server) handlePortal(w http.ResponseWriter, r *http.Request) {
	if !s.billing.enabled {
		writeJSON(w, http.StatusServiceUnavailable, map[string]any{"error": "billing non configuré"})
		return
	}
	ref := decodeRef(r)
	if ref == "" {
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": "ref requis"})
		return
	}
	var customerID string
	err := s.db.QueryRow("SELECT customer_id FROM subscriptions WHERE ref = ?", ref).Scan(&customerID)
	if err != nil || customerID == "" {
		writeJSON(w, http.StatusNotFound, map[string]any{"error": "aucun abonnement pour cet appareil"})
		return
	}
	params := &stripe.BillingPortalSessionParams{
		Customer:  stripe.String(customerID),
		ReturnURL: stripe.String(s.billing.publicBaseURL + "/billing/success"),
	}
	ps, err := bpsession.New(params)
	if err != nil {
		s.serverError(w, "stripe portal", err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"url": ps.URL})
}

// POST /v1/billing/webhook — reçoit et VÉRIFIE la signature des événements Stripe.
func (s *server) handleWebhook(w http.ResponseWriter, r *http.Request) {
	payload, err := io.ReadAll(io.LimitReader(r.Body, 1<<20))
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		return
	}
	event, err := webhook.ConstructEvent(payload, r.Header.Get("Stripe-Signature"), s.billing.webhookSecret)
	if err != nil {
		s.logger.Warn("webhook signature invalide", "error", err)
		w.WriteHeader(http.StatusBadRequest)
		return
	}

	switch event.Type {
	case "checkout.session.completed":
		var cs stripe.CheckoutSession
		if err := json.Unmarshal(event.Data.Raw, &cs); err != nil {
			break
		}
		status := "active"
		if cs.Subscription != nil {
			if sub, err := subscription.Get(cs.Subscription.ID, nil); err == nil {
				status = string(sub.Status)
			}
		}
		var customerID, subID string
		if cs.Customer != nil {
			customerID = cs.Customer.ID
		}
		if cs.Subscription != nil {
			subID = cs.Subscription.ID
		}
		s.upsertSubscription(cs.ClientReferenceID, customerID, subID, status)

	case "customer.subscription.updated", "customer.subscription.deleted":
		var sub stripe.Subscription
		if err := json.Unmarshal(event.Data.Raw, &sub); err != nil {
			break
		}
		status := string(sub.Status)
		if event.Type == "customer.subscription.deleted" {
			status = "canceled"
		}
		var customerID string
		if sub.Customer != nil {
			customerID = sub.Customer.ID
		}
		s.updateSubscriptionByCustomer(customerID, sub.ID, status)
	}

	w.WriteHeader(http.StatusOK)
}

func (s *server) upsertSubscription(ref, customerID, subID, status string) {
	if ref == "" {
		return
	}
	_, err := s.db.Exec(
		`INSERT INTO subscriptions(ref, customer_id, subscription_id, status, updated_at)
		 VALUES(?,?,?,?,?)
		 ON CONFLICT(ref) DO UPDATE SET customer_id=excluded.customer_id,
		   subscription_id=excluded.subscription_id, status=excluded.status, updated_at=excluded.updated_at`,
		ref, customerID, subID, status, time.Now().Unix(),
	)
	if err != nil {
		s.logger.Error("upsert subscription", "error", err)
	}
}

func (s *server) updateSubscriptionByCustomer(customerID, subID, status string) {
	if customerID == "" {
		return
	}
	_, err := s.db.Exec(
		"UPDATE subscriptions SET status=?, subscription_id=?, updated_at=? WHERE customer_id=?",
		status, subID, time.Now().Unix(), customerID,
	)
	if err != nil {
		s.logger.Error("update subscription", "error", err)
	}
}

// Pages de retour minimales affichées dans le navigateur in-app.
func (s *server) handleBillingSuccess(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	io.WriteString(w, billingPage("Merci !", "Votre abonnement CaveOS Pro est actif. Vous pouvez revenir à l'application."))
}

func (s *server) handleBillingCancel(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	io.WriteString(w, billingPage("Abonnement annulé", "Aucun paiement n'a été effectué. Vous pouvez fermer cette page."))
}

func billingPage(title, message string) string {
	return `<!doctype html><html lang="fr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>CaveOS</title>
<style>body{font-family:-apple-system,system-ui,sans-serif;background:#73121f;color:#f5f0e3;
display:flex;min-height:100vh;align-items:center;justify-content:center;margin:0;text-align:center}
.card{padding:2rem;max-width:28rem}h1{font-size:1.5rem}p{opacity:.9;line-height:1.5}</style></head>
<body><div class="card">🍷<h1>` + title + `</h1><p>` + message + `</p></div></body></html>`
}
