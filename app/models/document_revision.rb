# A file attachment audited through a model this application owns.
#
# ActiveStorage keeps attachments and blobs in tables Rails owns and PaperTrail
# never versions, so `has_one_attached` on its own leaves no history to compare
# -- paper_trail_diff raises UnversionedAssociationError rather than reporting
# that nothing changed. Owning the record that holds the attachment puts the
# facts somewhere PaperTrail already records.
#
# The column names are this application's choice. What the gem needs is only
# that replacing a file writes to a versioned record, which is what the
# callback below arranges: attaching a file touches ActiveStorage's tables and
# nothing here, so without it there would be no version at all.
class DocumentRevision < ApplicationRecord
  # demo:code shared.attachment
  belongs_to :attachable, polymorphic: true
  has_one_attached :file

  # This record is versioned; ActiveStorage's attachment and blob tables are
  # not, which is the whole reason the audit trail comes through here.
  has_paper_trail

  before_save :mirror_file_metadata

  def attached_filename = filename.presence || file.attached? && file.blob.filename.to_s

  private

  def mirror_file_metadata
    return unless file.attached?

    blob = file.blob
    # Include metadata in the same save PaperTrail audits, before its after-save
    # callback. No recursive save or second transaction is needed.
    assign_attributes(
      filename: blob.filename.to_s,
      content_type: blob.content_type,
      byte_size: blob.byte_size,
      checksum: blob.checksum
    )
  end
  # demo:code end
end
