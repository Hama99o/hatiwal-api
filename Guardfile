guard :rspec, cmd: "bundle exec rspec --color" do
  require "guard/rspec/dsl"
  dsl = Guard::RSpec::Dsl.new(self)

  rspec = dsl.rspec
  watch(rspec.spec_helper) { rspec.spec_dir }
  watch(rspec.spec_support) { rspec.spec_dir }
  watch(rspec.spec_files)

  ruby = dsl.ruby
  dsl.watch_spec_files_for(ruby.lib_files)

  rails = dsl.rails(view_extensions: %w[erb])
  dsl.watch_spec_files_for(rails.app_files)

  # Models → model specs
  watch(%r{^app/models/(.+)\.rb$}) { |m| "spec/models/#{m[1]}_spec.rb" }

  # Controllers → request specs
  watch(%r{^app/controllers/api/v1/(.+)_controller\.rb$}) { |m| "spec/requests/api/v1/#{m[1]}_spec.rb" }

  # Policies → policy specs
  watch(%r{^app/policies/(.+)_policy\.rb$}) { |m| "spec/policies/#{m[1]}_policy_spec.rb" }

  # Services → service specs
  watch(%r{^app/services/(.+)\.rb$}) { |m| "spec/services/#{m[1]}_spec.rb" }

  # Serializers → run full request specs
  watch(%r{^app/serializers/.+\.rb$}) { rspec.spec_dir }

  # Config changes → run all specs
  watch(rails.spec_helper)    { rspec.spec_dir }
  watch(rails.routes)         { "spec/requests" }
  watch(rails.app_controller) { "spec/requests" }
end

guard :rubocop, all_on_start: false do
  watch(%r{.+\.rb$})
  watch(%r{(?:.+/)?\.rubocop(?:_todo)?\.yml$}) { |m| File.dirname(m[0]) }
end
