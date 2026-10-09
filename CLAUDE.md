# bibliotheque-prix

Application Rails 8 pour Induni & Cie SA : bibliothèque de prix de
référence par article/matériau (indépendante des catalogues fournisseurs
d'ESHOP-INDUNI).

Contact / propriétaire : pomontaut@induni.ch (Pierre-Olivier Montaut),
communique en français.

## Modèles

- `PriceItem` : champs alignés sur le format de référence de l'utilisateur
  (colonnes de son fichier Excel de suivi) — `last_invoice_date` (date du
  document), `last_invoice_number` (n° de l'offre ou de la facture),
  `category` (Nom du fournisseur — le vrai vendeur), `invoicing_supplier_name`
  (Fournisseur factureur — l'entité qui émet la facture, peut différer :
  voir "Point de vente ≠ fournisseur facturant" plus bas), `article_number`
  (numero d'article), `name` (désignation de l'article), `reference_price`
  (prix unitaire inclus rabais, donc déjà net), `currency` (unité monétaire,
  "CHF" par défaut), `last_order_quantity` (quantité unitaire), `unit`
  (unité de la quantité), `last_total` (Montant total article),
  `delivery_address`, `delivery_type`. Le CSV export/import
  (`PriceItemsController::CSV_HEADERS`/`HEADER_MAP`) utilise les libellés
  exacts de ce format pour que le fichier de l'utilisateur s'importe tel
  quel, dans n'importe quel ordre de colonnes (normalisation par accents/
  casse/parenthèses dans `normalize_header`).
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
  assez de faux positifs en pratique. **`best_match` doit toujours recevoir
  `scope:` limité au fournisseur de la facture** (`Invoice#find_match` le
  fait via `PriceItem.where(category: supplier.name)`) — sans ça, des
  produits différents mais au libellé proche chez des fournisseurs distincts
  (ex: "swissporXPS 300 GE gaufré" formulé quasi identiquement sur des
  factures Mapei, Sika et swisspor) se retrouvent fusionnés dans un seul
  `PriceItem`, avec un historique de prix qui mélange des produits sans
  rapport. Un appel `best_match(description)` sans `scope:` cherche par
  défaut dans tout `PriceItem` — ne jamais faire ça pour du rapprochement de
  facture.
- **Point de vente ≠ fournisseur facturant, PAR LIGNE** : HGC réémet des
  factures pour du matériel acheté directement chez un fabricant/distributeur
  (Sika, Mapei, swisspor, Knauf, Canplast, Basys... observés à ce jour). La
  ligne "Point de vente: X, adresse" du PDF indique le vrai vendeur.
  **Erreur corrigée** : 90 des 186 factures réelles testées contiennent
  PLUSIEURS sections "Point de vente" différentes dans un même document (ex:
  une commande Mapei suivie d'une commande HGC) — attribuer tout le document
  au premier point de vente trouvé attribuait à tort des articles HGC à
  Mapei et inversement. `InvoiceParser.extract_lines` traque désormais le
  point de vente *en vigueur à chaque ligne* en parcourant le texte
  séquentiellement, et chaque `InvoiceLine` porte son propre `supplier_id`
  (`InvoiceLine#effective_supplier` retombe sur `invoice.supplier` si nil).
  **`Invoice#supplier` n'est plus jamais réassigné automatiquement** — il
  reste ce qui a été choisi à l'upload ; c'est `InvoiceLine#supplier` qui
  porte la vérité. Tout code qui rapproche/historise par fournisseur doit
  utiliser `line.effective_supplier`, jamais `invoice.supplier`, sous peine
  de reproduire cette contamination croisée.
  `InvoiceParser.effective_supplier_name` renvoie le point de vente observé
  sauf s'il correspond à HGC sous l'une de ses formes (`/\bHGC?\b/i` —
  "HGC Handel AG", "HGC Commerce SA", "HG COMMERCIALE" observées).
  Comportement automatique et permanent : s'applique à chaque facture
  uploadée, y compris celles à venir.
- **Prix net vs prix brut** : la ligne d'article affiche toujours le prix
  BRUT, avant tout "Rabais"/"Supplément net"/"Frais" qui suit sur les lignes
  de continuation du même bloc. Le prix réellement payé (ce qui doit
  alimenter la bibliothèque) n'apparaît que sur la ligne "Montant hors TVA"
  qui termine le bloc (1 nombre = total net seul, 2 nombres = prix unitaire
  net puis total net). `InvoiceParser.net_amount_after` cherche cette ligne
  dans les lignes suivant l'item (jusqu'à la prochaine ligne d'article ou
  "Point de vente", ou 6 lignes au plus) et, si trouvée, remplace le
  prix/total bruts de `extract_lines`. Sans ce fix, un rabais de 40% faisait
  passer un prix net de 3.07 CHF/kg pour 1070 CHF (bug réel découvert et
  corrigé — voir aussi le point suivant).
- **Scan borné à 4 valeurs numériques** (quantité, prix, quantité de
  référence "UP", montant) dans `parse_item_line` : au-delà, un repère isolé
  dans la désignation (ex: "IBC 1000        1-     1'070 KG...", le "1-"
  n'étant ni une quantité ni une unité) se faisait happer comme 5ᵉ valeur et
  décalait quantité/prix d'une colonne — c'est ce qui causait le bug
  ci-dessus en pratique. Sans borne, un article à 1070 KG et 5.12 CHF/kg
  brut ressortait avec quantité=1000 et prix=1070.
- **Virgule = séparateur de milliers, jamais décimal** : les deux lots de
  factures réels utilisent le point comme séparateur décimal, que les
  milliers soient groupés par apostrophe ("1'070") ou par virgule
  ("1,070") — aucun des deux ne met jamais de virgule décimale.
  `numeric_value` supprime donc toujours la virgule au lieu de parfois la
  convertir en point ; l'ancienne heuristique lisait "1,070" comme 1.07.
- **Une ligne d'article indentée reste une ligne d'article** : un modèle de
  facture peut indenter uniformément toutes ses lignes, item compris — se
  baser sur "commence par un espace" pour distinguer un item d'une
  sous-ligne "Rabais" est donc faux. `parse_item_line` matche désormais sur
  la ligne strippée ; la vraie garde anti-faux-positif est que la
  désignation extraite doit contenir au moins une lettre (sinon c'est le
  bloc de référence du bulletin de versement QR-facture suisse,
  "27 47100 00000 10157 ...", qui matchait sinon le motif pos+article).
- `SupplierArticleMapping` (`supplier_id + article_number` unique) :
  mémoire d'apprentissage. Dès qu'un humain confirme/corrige le rapprochement
  d'une ligne ayant un `article_number` (écran de contrôle →
  `InvoiceLinesController#update`), le couple fournisseur+n°article est
  retenu ; toute future facture du même fournisseur avec ce même n°article
  est alors rapprochée avec certitude (`Invoice#find_match`), sans repasser
  par le matching flou. L'agent s'améliore donc facture après facture.
  **`find_match` ne fait JAMAIS de rapprochement flou quand un
  `article_number` est présent** — seul un `SupplierArticleMapping` exact
  peut le résoudre ; sans mapping, la ligne reste non rapprochée. Avant ce
  fix, des numéros d'article différents mais aux désignations proches
  ("swissporXPS 300 GE" / "... GE gaufré" / "... SF lisse battues") se
  faisaient fusionner dans le même `PriceItem`, corrompant son historique de
  prix avec des produits sans rapport. Le matching flou ne sert plus que
  pour les lignes **sans aucun** numéro d'article (ex: ~70% des lignes de
  l'historique Gravières d'Epeisses). `PriceItem` a aussi
  `has_many :supplier_article_mappings, dependent: :destroy` : supprimer un
  article doit aussi oublier son mapping, sinon une future facture avec ce
  même numéro le recréerait silencieusement.
- La fiche article (`price_items/show`) affiche deux graphiques (Chart.js
  via CDN, pas de bundler) quand l'article a au moins 2 points dans le
  temps : prix facturé et quantité facturée, basés sur
  `@chart_points` (date de facture + prix + quantité de chaque
  `InvoiceLine` rapprochée). Sur la liste (`price_items/index`), un n°
  d'article avec plus d'une version de prix est un `<details>` (menu
  déroulant HTML natif, pas de JS) surligné en ambre, montrant un mini
  historique et un lien vers le graphique complet (`#price-chart`).
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
- **Import depuis un historique Excel structuré** (ex: export de factures
  d'un fournisseur comme Gravières d'Epeisses SA, colonnes
  date/n°facture/fournisseur/n°article/désignation/prix/quantité/unité
  déjà tabulaires) : pas besoin de `InvoiceParser`, on peut créer
  `Invoice`/`InvoiceLine` directement avec `Invoice#find_match` pour le
  rapprochement (fonctionne même sans n° d'article, par recouvrement de mots
  sur la désignation). **Toujours exclure les lignes de total de facture**
  avant rapprochement (`/total|TVA|escompte|net.{0,3}payer|sous.total/i` sur
  la désignation) — un export brut inclut souvent "Total HT (CHF)", "TVA
  8.1 % (CHF)" comme fausses "lignes d'article" scattées dans les données,
  qui sinon polluent la bibliothèque exactement comme les frais HGC
  (200000xxx). Traiter les lignes par ordre chronologique croissant pour que
  `PriceItem#reference_price` reflète bien le prix le plus récent.
  Il n'existe pas encore d'écran d'upload dédié pour ce format — l'import
  s'est fait via un script `rails runner` ponctuel ; en construire un
  réutilisable (upload + mapping de colonnes) si ce type de fichier doit
  revenir régulièrement.

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
