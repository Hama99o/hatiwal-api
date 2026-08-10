# TASK-TX02 (review fix, LOW — "the recovery lever has no spec") — loads the
# app's rake tasks once so request/model specs stay untouched and any spec
# under spec/tasks/ can invoke `Rake::Task["..."]` directly.
require "rake"

Rails.application.load_tasks if Rake::Task.tasks.empty?
