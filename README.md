# PaperTrail Diff Lab

A small Rails application for exercising the published `paper_trail_diff`
package in a realistic integration. Its Gemfile uses:

```ruby
gem "paper_trail_diff", "~> 0.2.0"
```

The demo creates an article history with scalar, nested, through-association,
and HABTM changes. You can create and edit articles, comments and nested
replies, authors, and tags while supplying the PaperTrail `whodunnit` value for
each action. Each write creates an article checkpoint so the resulting root or
association state can be selected as a comparison endpoint.

Authors demonstrate a many-to-many relationship with a meaningful join model:

```ruby
class Article < ApplicationRecord
  has_many :authorships
  has_many :authors, through: :authorships
end

class Author < ApplicationRecord
  has_many :authorships
  has_many :articles, through: :authorships
end
```

`Authorship` records carry `role`, `position`, and `credited_as`, so selecting
`authorships.author` demonstrates both join-attribute changes and nested author
state. Selecting only `authors` demonstrates the target collection view.

The UI can create and attach authors, attach existing authors to additional
articles, edit shared authors, and detach them. `Author` and `Authorship` both
use `has_paper_trail`. Editing a shared author checkpoints every linked article,
so each article can expose that author change at a root version boundary.

Replies exercise the explicit nested path `comments.replies`. Tags exercise a
direct HABTM edge:

```ruby
class Article < ApplicationRecord
  has_and_belongs_to_many :tags
end

class Tag < ApplicationRecord
  has_and_belongs_to_many :articles
end
```

The seeded history includes nested reply additions, removals, and updates plus
HABTM tag membership and target-attribute changes. Article version timestamps
are recorded at the actual checkpoint time so PT-AT can reconstruct tags
created shortly before a manual boundary.

Article create versions are also selectable. Comparing one to the initial
checkpoint demonstrates the structured absent-to-present
`record_presence_change`.

The web UI compares any two root versions and shows the endpoint diff, each
adjacent root timeline step, and root-plus-descendant activity boundaries. It
uses one `PaperTrailDiff.analyze(..., activity: true)` call for the endpoint and
both timeline results, plus `PaperTrailDiff.diagnose` for known reconstruction
hazards. Activity
summaries use `Diff#each_change`; timeline headers use the shared boundary
readers and their immutable record, event, actor, and timestamp metadata. Its
**Attribute blacklist** field maps directly to
the gem's `ignore:` option. The app-wide default is configured in
`config/application.rb`:

```ruby
config.x.paper_trail_diff.default_ignore = %w[updated_at]
```

The result switcher keeps the net endpoint diff, root checkpoints, complete
activity history, and presentation-oriented event feed in one place. The event
feed follows the README pattern and removes empty boundaries with
`analysis.activity_timeline.reject(&:empty?)`; it attributes each visible diff
to the step's `from_boundary` because PaperTrail versions contain pre-event
state.

The ending selector also offers the current persisted Article. That endpoint is
passed explicitly to `PaperTrailDiff.compare`; checkpoint timelines remain
version-bounded. When a selected HABTM path prevents live-ended activity, the
page keeps the endpoint diff live, ends activity at the latest saved version,
and explains the distinction. Absent-to-present and present-to-absent endpoint
comparisons render their `record_presence_change` snapshot and included-state
metrics instead of presenting an empty scalar diff.

The blacklist picker derives attribute choices from every reflected model in
the bounded graph. Global choices apply everywhere. Exact-path groups build the
hash form of `ignore:`, where `$` identifies the root and a path such as
`comments.replies` affects only that level.

The separate association picker uses `PaperTrailDiff.association_paths`, filters
to application models, and requests a maximum depth of two. This exposes paths
such as `comments.replies`, the explicit `authorships` join, and the HABTM `tags`
edge while the gem marks cycles and hides PaperTrail's `versions` infrastructure.
Checked paths are passed directly as the `associations:` traversal plan. The
page shows both resulting arguments beneath the form.

Like the gem API, a submitted attribute selection replaces the default rather
than merging with it, so retain `updated_at` when you still want it suppressed.
Uncheck every attribute to pass `ignore: []` and compare every scalar field.

## Run it

```console
mise exec -- bundle install
mise exec -- bundle exec rails db:setup
mise exec -- bundle exec rails server
```

Open <http://localhost:3000>. Use **Regenerate history** whenever you want a
clean deterministic dataset.

After a new gem release, update the locked package and restart the Rails server:

```console
mise exec -- bundle update paper_trail_diff
```

To exercise unpublished changes instead, temporarily use the neighboring
working tree in the Gemfile:

```ruby
gem "paper_trail_diff", path: "../paper_trail_summary"
```

## Verify it

```console
mise exec -- bundle exec rails test
mise exec -- bundle exec rails runner 'puts PaperTrailDiff::VERSION'
```
