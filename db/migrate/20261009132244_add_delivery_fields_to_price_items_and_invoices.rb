class AddDeliveryFieldsToPriceItemsAndInvoices < ActiveRecord::Migration[8.1]
  def change
    # PriceItem: align with the user's reference spreadsheet column set
    # (date du document, n° offre/facture, Nom du fournisseur, numero
    # d'article, désignation, prix unitaire inclus rabais, unité monétaire,
    # quantité unitaire, unité de la quantité, Montant total article,
    # Adresse de livraison, Type de livraison, Fournisseur factureur).
    # "Nom du fournisseur" (the real seller) already exists as `category`;
    # "Fournisseur factureur" (the entity that issues the invoice, which
    # can differ — see HGC re-invoicing a manufacturer) is new below.
    add_column :price_items, :currency, :string, default: "CHF", null: false
    add_column :price_items, :last_total, :decimal, precision: 12, scale: 2
    add_column :price_items, :delivery_address, :string
    add_column :price_items, :delivery_type, :string
    add_column :price_items, :invoicing_supplier_name, :string

    # Invoice: carries delivery info per document so it can be copied onto
    # a PriceItem when a line is integrated.
    add_column :invoices, :delivery_address, :string
    add_column :invoices, :delivery_type, :string
    add_column :invoices, :currency, :string, default: "CHF", null: false
  end
end
