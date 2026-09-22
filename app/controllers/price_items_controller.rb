require "csv"

class PriceItemsController < ApplicationController
  before_action :set_price_item, only: %i[show edit update destroy]

  def index
    @categories = PriceItem.categories
    @price_items = PriceItem.search(params[:q]).in_category(params[:category]).order(:name)
  end

  def show
    @invoice_lines = @price_item.invoice_lines.includes(invoice: :supplier).order(created_at: :desc).limit(20)
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

  def export
    csv = CSV.generate(headers: true) do |rows|
      rows << %w[nom categorie unite prix_reference notes]
      PriceItem.order(:name).find_each do |item|
        rows << [ item.name, item.category, item.unit, item.reference_price, item.notes ]
      end
    end

    send_data csv, filename: "bibliotheque-prix-#{Date.today}.csv"
  end

  def import
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

    CSV.foreach(file.path, headers: true, header_converters: :symbol) do |row|
      name = row[:nom].to_s.strip
      next if name.blank?

      item = PriceItem.find_or_initialize_by(name: name)
      item.category = row[:categorie]
      item.unit = row[:unite]
      item.reference_price = row[:prix_reference]
      item.notes = row[:notes]

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
    params.require(:price_item).permit(:name, :category, :unit, :reference_price, :notes)
  end
end
