# PaperTrail Diff Lab

A small Rails application for exercising
[`paper_trail_diff`](https://github.com/aheathwilliams/paper_trail_diff) in a
realistic integration. This branch pins the exact gem commit from
[PR #13](https://github.com/aheathwilliams/paper_trail_diff/pull/13) in `Gemfile`
and `Gemfile.lock`, including the new batch activity options. No sibling checkout
is required. `Gemfile.local` optionally uses the gem working copy beside this app.

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
to the step's `source_boundary` because PaperTrail versions contain pre-event
state.

The ending selector also offers the current persisted Article. That endpoint is
passed explicitly to `PaperTrailDiff.analyze(..., activity: true)` so endpoint,
checkpoint, and activity views share one analysis through current state. When a selected HABTM path prevents live-ended activity, the
page keeps the endpoint and checkpoint views live, ends activity at the latest saved version,
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

## Recent activity report

`/report` uses `analyze_scope` with `activity: true`, `group: :transaction`,
`snapshots: true`, and `close_on: :current`. Switch to individual events to see
changes before transaction grouping. Retained snapshots supply narrative context;
the structured disclosure uses `step.to_h(metadata: true)` for source attribution.
A transaction's source boundary describes its first event, not every actor in it.
Edits that cancel each other remain visible even when the net diff is empty.

The requested graph is explicit: comments and replies, authorships and authors,
and document metadata. HABTM tags remain available in the studio's endpoint
comparison because live HABTM activity is unsupported.

Deleted roots appear separately from the current-status population, even when
no live articles remain. Their destroy version supplies a historical root for
`activity_timeline`; rows deleted without one are marked unavailable. This
fallback requests article fields only, inspects at most 25 missing roots per
report, and states when more remain. It never assumes a deleted article matched
the live status filter. The 500-root `analyze_scope` limit is a safety ceiling,
not pagination, and does not bound the missing-root list.

File metadata is assigned in `DocumentRevision#before_save`, so PaperTrail sees
it during the same save as the file change, under the submitting actor.

## Run it

Use `mise install` and run Ruby commands through `mise exec --`. `.ruby-version`
pins Ruby 4.0.1 for this Rails app. The gem's Ruby 3.1 compatibility does not mean
this app's Rails version supports Ruby 3.1.

```console
bin/setup
```

That installs dependencies, creates the database, seeds a demo history, and
starts the server. Open <http://localhost:3000>. Use **Regenerate history**
whenever you want a clean deterministic dataset.

Add `--skip-server` to stop before booting, or `--reset` to rebuild the
database from scratch. Afterwards `bin/dev` starts the server on its own.

### Looking at a page

`bin/screenshot` renders pages with a headless browser and writes PNGs to
`tmp/screenshots`:

```console
bin/screenshot
bin/screenshot /report --height 3800
```

It boots a server if one is not already running and stops the one it started.
The test suite asserts on the DOM, so a page can be structurally correct and
visually broken at once — a panel with no padding, a card with no container —
and every assertion still passes. This exists because looking is the only check
that finds those, and it needs a browser on the machine but no extra gems.

After a release containing these APIs, replace the Git source in both Gemfiles
with that RubyGems version, update the lockfile, and restart the Rails server:

```console
bundle update paper_trail_diff
```

To exercise unpublished gem changes instead, use `Gemfile.local`. It is this
Gemfile with the gem sourced from a working copy checked out beside this
repository, falling back to the same pinned Git commit when there is none — so it
works whether or not you cloned the gem too, and leaves the pinned revision in
place either way:

```console
BUNDLE_GEMFILE=Gemfile.local bundle install
BUNDLE_GEMFILE=Gemfile.local bin/rails test
BUNDLE_GEMFILE=Gemfile.local bin/rails server
```

The pinned revision and the working tree can be compared directly by running the
same script under each bundle. This is worth doing before a release, because
the seeded demo history is far too small to expose scaling behaviour: growing
one article to a few thousand versions separates the two clearly, while the
default 31-version dataset shows almost no difference.

## Verify it

```console
bundle exec rails test
bundle exec rails runner 'puts PaperTrailDiff::VERSION'
```
