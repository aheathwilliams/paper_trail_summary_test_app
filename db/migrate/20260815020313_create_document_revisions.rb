class CreateDocumentRevisions < ActiveRecord::Migration[8.1]
  def change
    # ActiveStorage's own tables. Attachments and blobs live here, and Rails
    # never versions them, which is why the audit trail goes through a model
    # this application owns instead.
    create_active_storage_tables

    create_table :document_revisions do |t|
      t.references :attachable, polymorphic: true, null: false
      t.string :label, null: false
      # The facts worth auditing, mirrored from the blob so PaperTrail records
      # them the way it records any other column.
      t.string :filename
      t.string :content_type
      t.bigint :byte_size
      t.string :checksum
      t.timestamps
    end
  end

  private

  def create_active_storage_tables
    return if table_exists?(:active_storage_blobs)

    create_table :active_storage_blobs do |t|
      t.string :key, null: false
      t.string :filename, null: false
      t.string :content_type
      t.text :metadata
      t.string :service_name, null: false
      t.bigint :byte_size, null: false
      t.string :checksum
      t.datetime :created_at, null: false
      t.index [ :key ], unique: true
    end

    create_table :active_storage_attachments do |t|
      t.string :name, null: false
      t.references :record, null: false, polymorphic: true, index: false
      t.references :blob, null: false
      t.datetime :created_at, null: false
      t.index %i[record_type record_id name blob_id],
              name: :index_active_storage_attachments_uniqueness, unique: true
      t.foreign_key :active_storage_blobs, column: :blob_id
    end

    create_table :active_storage_variant_records do |t|
      t.references :blob, null: false, index: false
      t.string :variation_digest, null: false
      t.index %i[blob_id variation_digest],
              name: :index_active_storage_variant_records_uniqueness, unique: true
      t.foreign_key :active_storage_blobs, column: :blob_id
    end
  end
end
