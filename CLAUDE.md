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
  image donnera un texte vide). `extract_header` récupère numéro/date de
  facture (regex sur "Numéro de facture" / "Date de facture") et préremplit
  `Invoice#invoice_number`/`invoice_date` s'ils sont vides à l'upload.
  `extract_lines` détecte les lignes d'articles au format observé chez HGC
  Handel AG (`Pos  N°Article  Désignation  Quantité UQ  Prix  UP  Montant`,
  validé sur ~100 vraies factures) : **le scan part de la fin de chaque
  ligne**, pas du début — les désignations contiennent souvent leurs propres
  nombres ("38 pièces", "S 1122 HF", "300 GE") qu'il ne faut pas confondre
  avec les vraies colonnes quantité/prix/montant. `UNIT_FRAGMENT` liste les
  seules unités reconnues (PCE, KG, M2, M3, L, SAC, PAQ, HST...) pour borner
  correctement où s'arrête la désignation et où commencent les colonnes
  numériques ; un code produit du genre "S 1122 HF" serait sinon pris pour
  une unité de mesure. Limite connue : les documents "Récapitulatif" (cession
  de créance) n'ont pas de tableau d'articles — 0 ligne détectée est normal
  pour ce type, pas un bug. C'est un best-effort : toujours vérifié par un
  humain sur l'écran de contrôle avant intégration.
- `app/services/price_item_matcher.rb` : rapprochement par recouvrement de
  mots (Jaccard) après translittération (`I18n.transliterate`) pour ignorer
  les accents — sans ce fix, "Beton" (facture, sans accent) ne matchait pas
  "Béton" (bibliothèque). Seuil `MIN_SCORE = 0.34`, ajustable si trop/pas
  assez de faux positifs en pratique.
- **Point de vente ≠ fournisseur facturant** : HGC Handel AG réémet des
  factures pour du matériel acheté directement chez un fabricant/distributeur
  (Sika Schweiz AG, Mapei Suisse SA, swisspor Romandie SA, Ciments Vigier SA,
  Knauf Insulation GmbH observés à ce jour — ~20% du corpus testé). La ligne
  "Point de vente: X, adresse" du PDF indique le vrai vendeur.
  `InvoiceParser.extract_header` capture `point_of_sale` ;
  `InvoiceParser.effective_supplier_name` renvoie ce nom seulement s'il ne
  contient pas "HGC" (sinon on garde HGC Handel AG). `Invoice#parse!`
  réassigne alors automatiquement `invoice.supplier` (créant le `Supplier`
  si besoin) **avant** de rapprocher/créer les articles, pour que
  `PriceCondition`/`SupplierArticleMapping` soient rattachés au vrai
  fournisseur. Comportement automatique et permanent (pas une consigne
  ponctuelle) : s'applique à chaque nouvelle facture uploadée, y compris
  celles à venir.
- `SupplierArticleMapping` (`supplier_id + article_number` unique) :
  mémoire d'apprentissage. Dès qu'un humain confirme/corrige le rapprochement
  d'une ligne ayant un `article_number` (écran de contrôle →
  `InvoiceLinesController#update`), le couple fournisseur+n°article est
  retenu ; toute future facture du même fournisseur avec ce même n°article
  est alors rapprochée avec certitude (`Invoice#find_match`), sans repasser
  par le matching flou. L'agent s'améliore donc facture après facture.
- Le ratio (`InvoiceLine#ratio`) = prix facturé / prix de référence effectif
  (condition négociée active sinon `reference_price`). `anomalous?` flague
  un écart de plus de 10 % dans un sens ou l'autre (affiché en rouge).
- **Frais/taxes exclus de la bibliothèque** : chez HGC, les numéros d'article
  commençant par "2" (200000036 Frais de transport, 200000042 Taxe RPLP,
  200000038 Emballage, 200000323 Frais de transport usine...) sont des
  suppléments administratifs, jamais du matériel. `InvoiceParser.fee_article?`
  détecte ce préfixe ; `Invoice#parse!` ne tente aucun rapprochement pour ces
  lignes (`InvoiceLine#fee?`) et l'écran de contrôle affiche un badge au lieu
  du menu de rapprochement — impossible de les transformer en `PriceItem`
  (le bouton "Créer un article" est masqué pour elles).
- **PriceItem** porte aussi `article_number` (n° fournisseur), `unit` et
  `last_order_quantity` (quantité/unité de la dernière facture rapprochée) —
  remplis automatiquement par `Invoice#integrate!` et par
  `InvoiceLinesController#create_price_item` (bouton "Créer un article" sur
  une ligne non rapprochée et non-frais, route `POST
  .../invoice_lines/:id/create_price_item`). Le CSV import/export
  (`price_items#export`/`import_upload`) inclut les colonnes
  `n_article` et `quantite` en plus des colonnes historiques.
- **Anti-doublon des factures** (`Invoice::DuplicateError`, levée par
  `parse!`) : une facture déjà importée (même n° + même fournisseur effectif,
  après réassignation via le Point de vente) est rejetée — la facture
  nouvellement uploadée est détruite et l'utilisateur est renvoyé vers
  l'originale, jamais retraitée silencieusement. Double vérification :
  1) par `invoice_number`, 2) par l'empreinte (`checksum`) du fichier PDF
  lui-même, car certains documents "Récapitulatif" ont un texte corrompu
  (police/encodage cassé) qui empêche toute extraction du numéro — le
  checksum reste fiable même quand le texte ne l'est pas. Comportement
  permanent, actif pour chaque upload (formulaire ou script).
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
- Import CSV attend les colonnes
  `nom,n_article,categorie,unite,quantite,prix_reference,notes` ; la
  correspondance se fait par `name` (un nom existant est mis à jour, sinon
  créé).

## Vérification locale

```
bin/rails db:setup
bin/rails server -p 3099 -d
```

Puis piloter via curl/Playwright ; toujours arrêter le serveur
(`pkill -f "puma.*bibliotheque-prix"`) et nettoyer les données de test créées
avant de terminer.
