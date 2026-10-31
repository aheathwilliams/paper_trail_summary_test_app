ActiveRecord.yaml_column_permitted_classes = [
  Symbol,
  Time,
  Date,
  ActiveSupport::TimeWithZone,
  ActiveSupport::TimeZone
]

PaperTrail.config.track_associations = true

# See VersionClock: the demo seeds and the test suite keep version timestamps
# strictly increasing, whatever the host clock does.
PaperTrail::Version.before_create do
  self.created_at = VersionClock.next(created_at) if VersionClock.on?
end
