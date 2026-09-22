# bibliotheque-prix

Application Rails 8 pour Induni & Cie SA : bibliothèque de prix de
référence par article/matériau (indépendante des catalogues fournisseurs
d'ESHOP-INDUNI).

Contact / propriétaire : pomontaut@induni.ch (Pierre-Olivier Montaut),
communique en français.

## Modèles

- `PriceItem` : `name`, `category`, `unit`, `reference_price`, `notes`.
- `PriceItemVersion` : snapshot historique créé automatiquement à chaque
  changement de `reference_price` (voir callbacks dans `app/models/price_item.rb`).
  Ne pas créer/modifier ces lignes manuellement ailleurs que via les
  callbacks du modèle.
- `Supplier` : fournisseurs (distinct des `Supplier` d'ESHOP-INDUNI, autre app).
- `PriceCondition` : condition de prix négociée (fournisseur + article + prix +
  période de validité). `Supplier#active_condition_for(price_item, on:)`
  renvoie la condition en vigueur à une date donnée ; sinon on retombe sur
  `PriceItem#reference_price`.
- `Invoice` / `InvoiceLine` : « l'agent » de contrôle des factures (upload PDF
  → `Invoice#parse!` extrait le texte et les lignes → rapprochement proposé
  avec la bibliothèque → écran de contrôle humain (`invoices/show`) → sur
  confirmation, `Invoice#integrate!` met à jour `PriceItem#reference_price`
  pour chaque ligne rapprochée, ce qui alimente automatiquement l'historique
  `PriceItemVersion` via le callback existant. **Rien n'est jamais intégré
  sans validation humaine** — `parse!` ne fait que proposer.

## Module factures / conditions de prix ("l'agent")

- `app/services/invoice_parser.rb` : extraction de texte via `pdf-reader`
  (uniquement le texte embarqué dans le PDF, **pas d'OCR** — un PDF scanné en
  image donnera un texte vide) puis heuristique regex par ligne
  (`description  quantité  prix_unitaire  total`, formats numériques suisses
  avec `'` comme séparateur de milliers). C'est un best-effort : toujours
  vérifié par un humain sur l'écran de contrôle avant intégration.
- `app/services/price_item_matcher.rb` : rapprochement par recouvrement de
  mots (Jaccard) après translittération (`I18n.transliterate`) pour ignorer
  les accents — sans ce fix, "Beton" (facture, sans accent) ne matchait pas
  "Béton" (bibliothèque). Seuil `MIN_SCORE = 0.34`, ajustable si trop/pas
  assez de faux positifs en pratique.
- Le ratio (`InvoiceLine#ratio`) = prix facturé / prix de référence effectif
  (condition négociée active sinon `reference_price`). `anomalous?` flague
  un écart de plus de 10 % dans un sens ou l'autre (affiché en rouge).
- **Stockage des factures (ActiveStorage, service `:local`)** : sur Railway,
  le système de fichiers est éphémère — un PDF uploadé sera perdu au
  prochain redéploiement. Acceptable pour l'instant (le texte extrait et les
  lignes sont en base, donc pas de perte de données métier), mais si la
  relecture du PDF original doit être fiable dans la durée, migrer vers un
  stockage S3-compatible (`config/storage.yml`) et pas juste `:local`.

## Points d'attention

- Le gem `json` est épinglé à `~> 2.9` dans le Gemfile : la version `3.0.x`
  casse `ActiveSupport::JSON.decode` (utilisé pour déchiffrer les cookies de
  session), ce qui provoque une 500 sur *toute* requête utilisant les
  sessions/CSRF. Ne pas laisser Bundler remonter `json` au-delà de `2.x`
  sans revérifier ce point.
- CSRF : les liens de suppression (Turbo `data-turbo-method="delete"`)
  utilisent le token du tag `<meta name="csrf-token">`, pas celui des
  formulaires `edit`/`new` — ne pas réutiliser le token d'un formulaire pour
  simuler un DELETE en test manuel (Rails utilise des tokens CSRF liés à
  l'action avec `per_form_csrf_tokens`).
- Import CSV attend les colonnes `nom,categorie,unite,prix_reference,notes` ;
  la correspondance se fait par `name` (un nom existant est mis à jour, sinon
  créé).

## Vérification locale

```
bin/rails db:setup
bin/rails server -p 3099 -d
```

Puis piloter via curl/Playwright ; toujours arrêter le serveur
(`pkill -f "puma.*bibliotheque-prix"`) et nettoyer les données de test créées
avant de terminer.
