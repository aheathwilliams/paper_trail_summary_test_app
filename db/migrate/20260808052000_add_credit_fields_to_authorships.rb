class AddCreditFieldsToAuthorships < ActiveRecord::Migration[8.1]
  def change
    add_column :authorships, :role, :string, null: false, default: "contributor"
    add_column :authorships, :position, :integer, null: false, default: 1
    add_column :authorships, :credited_as, :string
  end
end
