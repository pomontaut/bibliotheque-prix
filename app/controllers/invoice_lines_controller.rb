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

  private

  def set_invoice
    @invoice = Invoice.find(params[:invoice_id])
  end

  def invoice_line_params
    params.require(:invoice_line).permit(:price_item_id, :description, :quantity, :unit_price, :total)
  end
end
