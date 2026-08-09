class CreateRepliesAndTags < ActiveRecord::Migration[8.1]
  def change
    create_table :replies do |t|
      t.references :comment, null: false, foreign_key: true
      t.string :responder, null: false
      t.text :body, null: false

      t.timestamps
    end

    create_table :tags do |t|
      t.string :name, null: false
      t.text :description, null: false

      t.timestamps
    end

    create_table :articles_tags, id: false do |t|
      t.references :article, null: false, foreign_key: true
      t.references :tag, null: false, foreign_key: true
    end
    add_index :articles_tags, %i[article_id tag_id], unique: true
  end
end
