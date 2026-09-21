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
