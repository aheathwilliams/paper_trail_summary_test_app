# Lets Rails report the gem's deprecation warnings like its own, as the gem's
# reference recommends for Rails applications.
Rails.application.deprecators[:paper_trail_diff] = PaperTrailDiff.deprecator
