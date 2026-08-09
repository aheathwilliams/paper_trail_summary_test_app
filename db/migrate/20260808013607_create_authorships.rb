class CreateAuthorships < ActiveRecord::Migration[8.1]
  def change
    create_table :authorships do |t|
      t.references :article, null: false, foreign_key: true
      t.references :author, null: false, foreign_key: true

      t.timestamps
    end

    add_index :authorships, %i[article_id author_id], unique: true
  end
end
