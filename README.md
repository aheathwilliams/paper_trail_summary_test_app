# PaperTrail Diff Lab

A small Rails application for exercising
[`paper_trail_diff`](https://github.com/aheathwilliams/paper_trail_diff) in a
realistic integration. `Gemfile` uses the released gem, version 0.13.1. To try
unreleased gem changes, use `BUNDLE_GEMFILE=Gemfile.local` with the gem working
copy beside this app.

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

PT-AT records tag membership only when an article saves a version, from the
instance that saves it, and never forgets the tag changes that instance made,
not even on `reload`. So the seed loads the article again after changing its
tags. Every tag change, in the seed and through the UI, is saved between two
checkpoints by the person making it. The gem credits a membership change to
the step after the earlier of the two article versions around it, and the
first checkpoint makes that step the actor's.

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

`/report` uses `PaperTrailDiff.report` with `since:`, `include_deleted: true`,
`group: :transaction`, and `snapshots: true`. The gem supplies activity output and
closes the window on the current record. Switch to individual events to see
changes before transaction grouping. Retained snapshots supply narrative context;
the structured disclosure uses `step.to_h(metadata: true)` for source attribution.
A deleted article's title comes from the last state its timeline saw, since an
article created and deleted inside the window has no state at either end.
The report uses `ScopedAnalysis#roots` to reuse the loaded articles in relation
order instead of querying them a second time.
A transaction's source boundary describes its first event, and `step.sources`
lists every event in it, so the narrative credits each change to its own author.
Edits that cancel each other remain visible even when the net diff is empty.

The requested graph is explicit: comments and replies, authorships and authors,
and document metadata. HABTM tags remain available in the studio's endpoint
comparison because live HABTM activity is unsupported.
An article is selected when it, or a record on one of those associations, has a
version in the window, so editing only a comment brings its article into the
report with the edit.

Choose **Current state** to filter today's rows, or **Recorded historical states**
to pass `{ status: selected_status }` through `historical_filter:`. This reads
recorded attributes without reifying every candidate. The latter keeps the
relation broad so articles that moved out of the selected status remain eligible.
The status picker uses the model's status list, including values no live row holds.
An unknown mode or status falls back to Current state / Any status.

Use **Add historical status examples** on the report to add three named histories
without clearing existing articles: a moved-out Review article, a deleted Review
article, and an article whose final event entered Review. Historical Review finds
the first two; Current Review finds the final-event example. Each click adds a new
set, and resetting the studio clears them along with the rest of the demo.

Historical filtering tests recorded **pre-event states inside the selected window**.
It cannot see a status that appears only in the final live state, even when the
diff closes on current state. A create-only history has no prior state to test.
The UI states this limitation, and tests cover final-event, create-only, and
out-of-window cases. Selecting a root includes its whole activity window, rather
than just events while it held the chosen status. Any status skips the predicate.

Deleted roots appear separately from the current-status population, even when
no live articles remain. With a current status filter, only deleted roots that
held that status when they were deleted are included: the gem tests the
relation's conditions against the state their destroy version recorded. With a
historical status predicate, only deleted roots with a recorded matching state
in the window are included. `report.deleted`
provides their analyses in one batch, including the same selected associations
as the live report. Rows without destroy history are marked unavailable. The
presenter performs no queries or reification and displays the first 25 missing
roots, with a notice when more remain. The 500-root ceiling covers the live and
missing roots the report selects together, after historical filtering.
Historical filtering has a separate default budget of 10,000 loaded versions.
These ceilings do not bound arbitrary history reconstruction work; narrow large
windows rather than treating the limits as pagination.

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

To move to a later gem release, raise the version in both Gemfiles, update the
lockfile, and restart the Rails server:

```console
bundle update paper_trail_diff
```

To exercise unpublished gem changes instead, use `Gemfile.local`. It is this
Gemfile with the gem sourced from a working copy checked out beside this
repository, falling back to the released gem when there is none, so it works
whether or not you cloned the gem too:

```console
BUNDLE_GEMFILE=Gemfile.local bundle install
BUNDLE_GEMFILE=Gemfile.local bin/rails test
BUNDLE_GEMFILE=Gemfile.local bin/rails server
```

The released gem and the working tree can be compared directly by running the
same script under each bundle. This is worth doing before a release, because
the seeded demo history is far too small to expose scaling behaviour: growing
one article to a few thousand versions separates the two clearly, while the
default 31-version dataset shows almost no difference.

## Verify it

```console
bundle exec rails test
bundle exec rails runner 'puts PaperTrailDiff::VERSION'
```
