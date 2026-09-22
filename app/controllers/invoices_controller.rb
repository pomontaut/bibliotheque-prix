class InvoicesController < ApplicationController
  before_action :set_invoice, only: %i[show destroy integrate]

  def index
    @invoices = Invoice.includes(:supplier).order(created_at: :desc)
  end

  def show
    @invoice_lines = @invoice.invoice_lines.includes(:price_item).order(:id)
    @price_items = PriceItem.order(:name)
  end

  def new
    @invoice = Invoice.new
    @suppliers = Supplier.order(:name)
  end

  def create
    @invoice = Invoice.new(invoice_params)
    if @invoice.save
      @invoice.parse!
      redirect_to @invoice, notice: "Facture importée : #{@invoice.invoice_lines.count} ligne(s) détectée(s). Vérifiez le rapprochement avant d'intégrer."
    else
      @suppliers = Supplier.order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @invoice.destroy
    redirect_to invoices_path, notice: "Facture supprimée.", status: :see_other
  end

  def integrate
    @invoice.integrate!
    redirect_to @invoice, notice: "Facture intégrée : les prix de référence des articles rapprochés ont été mis à jour."
  end

  private

  def set_invoice
    @invoice = Invoice.find(params[:id])
  end

  def invoice_params
    params.require(:invoice).permit(:supplier_id, :invoice_number, :invoice_date, :file)
  end
end
