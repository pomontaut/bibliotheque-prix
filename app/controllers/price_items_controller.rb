require "csv"

class PriceItemsController < ApplicationController
  before_action :set_price_item, only: %i[show edit update destroy]

  def index
    @categories = PriceItem.categories
    @price_items = PriceItem.search(params[:q]).in_category(params[:category]).order(:name)
                            .includes(:price_item_versions)
  end

  def show
    @invoice_lines = @price_item.invoice_lines.includes(invoice: :supplier).order(created_at: :desc).limit(50)
    @chart_points = @price_item.invoice_lines
                                .joins(:invoice)
                                .where.not(invoices: { invoice_date: nil })
                                .order("invoices.invoice_date")
                                .pluck("invoices.invoice_date", :unit_price, :quantity, :article_number)
                                .map { |date, price, qty, art| { date: date.to_s, price: price&.to_f, quantity: qty&.to_f, article_number: art } }
  end

  def new
    @price_item = PriceItem.new
  end

  def create
    @price_item = PriceItem.new(price_item_params)
    if @price_item.save
      redirect_to @price_item, notice: "Article créé."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @price_item.update(price_item_params)
      redirect_to @price_item, notice: "Article mis à jour."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @price_item.destroy
    redirect_to price_items_path, notice: "Article supprimé.", status: :see_other
  end

  # Column order/wording matches the reference spreadsheet format exactly
  # (date du document, n° de l'offre ou de la facture, Nom du fournisseur,
  # numero d'article, désignation de l'article, prix unitaire inclus
  # rabais, unité monétaire, quantité unitaire, unité de la quantité,
  # Montant total article, Adresse de livraison, Type de livraison,
  # Fournisseur factureur) so a file in that format can round-trip through
  # export/import without reshaping.
  CSV_HEADERS = [
    "date du document", "n° de l'offre ou de la facture", "Nom du fournisseur",
    "numero d'article", "désignation de l'article", "prix unitaire inclus rabais",
    "unité monétaire (chf, eur, usd, etc...)", "quantité unitaire",
    "unité de la quantité (mètre, kg, etc....)", "Montant total article",
    "Adresse de livraison", "Type de livraison", "Fournisseur factureur"
  ].freeze

  def export
    csv = CSV.generate(headers: true) do |rows|
      rows << CSV_HEADERS
      PriceItem.order(:name).find_each do |item|
        rows << [
          item.last_invoice_date, item.last_invoice_number, item.category,
          item.article_number, item.name, item.reference_price, item.currency,
          item.last_order_quantity, item.unit, item.last_total,
          item.delivery_address, item.delivery_type, item.invoicing_supplier_name
        ]
      end
    end

    send_data csv, filename: "bibliotheque-prix-#{Date.today}.csv"
  end

  def import
  end

  # Normalizes a header to match regardless of accents/case/parenthetical
  # hints ("unité monétaire (chf, eur...)" -> "unite_monetaire"), so a file
  # that is literally the reference spreadaheet's header row imports as-is.
  def self.normalize_header(header)
    I18n.transliterate(header.to_s).downcase.gsub(/\(.*?\)/, "").strip.gsub(/[^a-z0-9]+/, "_").gsub(/_+$/, "")
  end

  HEADER_MAP = {
    "date_du_document" => :last_invoice_date,
    "n_de_l_offre_ou_de_la_facture" => :last_invoice_number,
    "nom_du_fournisseur" => :category,
    "numero_d_article" => :article_number,
    "designation_de_l_article" => :name,
    "prix_unitaire_inclus_rabais" => :reference_price,
    "unite_monetaire" => :currency,
    "quantite_unitaire" => :last_order_quantity,
    "unite_de_la_quantite" => :unit,
    "montant_total_article" => :last_total,
    "adresse_de_livraison" => :delivery_address,
    "type_de_livraison" => :delivery_type,
    "fournisseur_factureur" => :invoicing_supplier_name
  }.freeze

  # Sniffs the column separator from the header line: French/Swiss Excel
  # exports this spreadsheet format with ";" by default, but a file saved
  # from another locale may use ",". Picking the wrong one makes CSV read
  # an entire data line as a single field, which then raises "Illegal
  # quoting" as soon as that field contains an embedded escaped quote.
  def self.detect_col_sep(path)
    first_line = File.open(path, "r:bom|utf-8", &:readline)
    first_line.count(";") > first_line.count(",") ? ";" : ","
  rescue EOFError
    ","
  end

  def import_upload
    file = params[:file]
    if file.blank?
      redirect_to import_price_items_path, alert: "Veuillez sélectionner un fichier CSV."
      return
    end

    created = 0
    updated = 0
    errors = []

    col_sep = self.class.detect_col_sep(file.path)

    CSV.foreach(file.path, headers: true, col_sep: col_sep, encoding: "bom|utf-8",
                header_converters: ->(h) { HEADER_MAP[self.class.normalize_header(h)] || h }) do |row|
      name = row[:name].to_s.strip
      next if name.blank?

      item = PriceItem.find_or_initialize_by(name: name)
      item.article_number = row[:article_number]
      item.category = row[:category]
      item.invoicing_supplier_name = row[:invoicing_supplier_name]
      item.unit = row[:unit]
      item.last_order_quantity = row[:last_order_quantity]
      item.reference_price = row[:reference_price]
      item.currency = row[:currency].presence || "CHF"
      item.last_total = row[:last_total]
      item.delivery_address = row[:delivery_address]
      item.delivery_type = row[:delivery_type]
      item.last_invoice_number = row[:last_invoice_number]
      item.last_invoice_date = row[:last_invoice_date].presence

      was_new_record = item.new_record?
      if item.save
        was_new_record ? created += 1 : updated += 1
      else
        errors << "#{name}: #{item.errors.full_messages.join(', ')}"
      end
    end

    notice = "Import terminé : #{created} créé(s), #{updated} mis à jour."
    notice += " Erreurs : #{errors.join(' ; ')}" if errors.any?
    redirect_to price_items_path, notice: notice
  rescue CSV::MalformedCSVError => e
    redirect_to import_price_items_path, alert: "Fichier CSV invalide : #{e.message}"
  end

  private

  def set_price_item
    @price_item = PriceItem.find(params[:id])
  end

  def price_item_params
    params.require(:price_item).permit(
      :name, :article_number, :category, :unit, :last_order_quantity, :reference_price,
      :notes, :currency, :last_total, :delivery_address, :delivery_type,
      :invoicing_supplier_name, :last_invoice_number, :last_invoice_date
    )
  end
end
