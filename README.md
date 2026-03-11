# README

This README would normally document whatever steps are necessary to get the
application up and running.

Things you may want to cover:

* Ruby version

* System dependencies

* Configuration
  * `GOOGLE_ANALYTICS_ID` (alternativ `GOOGLE_ANALYTICS_MEASUREMENT_ID` oder `GA4_MEASUREMENT_ID`) aktiviert GA4 nach Einwilligung im Consent-Banner.
  * `MAILCHIMP_API_KEY` plus `MAILCHIMP_LIST_ID` aktivieren den optionalen Mailchimp-Sync fuer Newsletter-Anmeldungen. `MAILCHIMP_SERVER_PREFIX` kann explizit gesetzt werden und ist bei euch voraussichtlich `us3`. Ohne diese Variablen bleibt die lokale Speicherung aktiv, aber es erfolgt kein externer Sync.

* Database creation

* Database initialization

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

* Deployment instructions

* ...
