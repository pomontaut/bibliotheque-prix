class InvoiceLinesController < ApplicationController
  before_action :set_invoice

  def update
    @invoice_line = @invoice.invoice_lines.find(params[:id])
    if @invoice_line.update(invoice_line_params.merge(matched_automatically: false))
      @invoice.update(status: "reviewed") if @invoice.status == "pending"
      if @invoice_line.price_item.present? && @invoice_line.article_number.present?
        SupplierArticleMapping.remember(
          supplier: @invoice.supplier,
          article_number: @invoice_line.article_number,
          price_item: @invoice_line.price_item
        )
      end
      redirect_to @invoice, notice: "Ligne mise à jour."
    else
      redirect_to @invoice, alert: @invoice_line.errors.full_messages.join(", ")
    end
  end

  def destroy
    @invoice.invoice_lines.find(params[:id]).destroy
    redirect_to @invoice, notice: "Ligne supprimée.", status: :see_other
  end

  def create_price_item
    line = @invoice.invoice_lines.find(params[:id])

    if line.fee?
      redirect_to @invoice, alert: "Cette ligne est un frais/taxe, pas un article." and return
    end

    price_item = PriceItem.create!(
      name: line.description,
      category: @invoice.supplier.name,
      unit: line.unit,
      reference_price: [ line.unit_price || 0, 0 ].max,
      last_order_quantity: line.quantity,
      article_number: line.article_number,
      notes: "Créé depuis la facture #{@invoice.invoice_number} (#{@invoice.supplier.name})"
    )
    line.update!(price_item: price_item, matched_automatically: false)
    SupplierArticleMapping.remember(supplier: @invoice.supplier, article_number: line.article_number, price_item: price_item) if line.article_number.present?

    redirect_to @invoice, notice: "Article « #{price_item.name} » créé et rapproché."
  end

  private

  def set_invoice
    @invoice = Invoice.find(params[:invoice_id])
  end

  def invoice_line_params
    params.require(:invoice_line).permit(:price_item_id, :description, :quantity, :unit_price, :total)
  end
end
