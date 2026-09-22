class PriceConditionsController < ApplicationController
  before_action :set_price_condition, only: %i[edit update destroy]

  def index
    @price_conditions = PriceCondition.includes(:supplier, :price_item).order(valid_from: :desc)
  end

  def new
    @price_condition = PriceCondition.new(valid_from: Date.current)
  end

  def create
    @price_condition = PriceCondition.new(price_condition_params)
    if @price_condition.save
      redirect_to price_conditions_path, notice: "Condition de prix enregistrée."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @price_condition.update(price_condition_params)
      redirect_to price_conditions_path, notice: "Condition de prix mise à jour."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @price_condition.destroy
    redirect_to price_conditions_path, notice: "Condition de prix supprimée.", status: :see_other
  end

  private

  def set_price_condition
    @price_condition = PriceCondition.find(params[:id])
  end

  def price_condition_params
    params.require(:price_condition).permit(:supplier_id, :price_item_id, :negotiated_price, :unit, :valid_from, :valid_until, :notes)
  end
end
