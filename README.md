# Bibliothèque de prix

Application Rails pour gérer une bibliothèque de prix de référence par
article/matériau (Induni & Cie SA).

## Fonctionnalités

- CRUD des articles (nom, catégorie, unité, prix de référence, notes)
- Recherche et filtre par catégorie
- Import / export CSV (`nom,categorie,unite,prix_reference,notes`)
- Historique des prix : chaque changement de `reference_price` est
  journalisé dans `price_item_versions`

## Démarrage local

```
bundle install
bin/rails db:setup
bin/rails server
```

L'application est accessible sur `/` (redirige vers la liste des articles).

## Stack

Rails 8, SQLite, Tailwind CSS, sans framework JS additionnel (Turbo/Stimulus
par défaut).
