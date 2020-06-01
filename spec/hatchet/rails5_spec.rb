require_relative '../spec_helper'

describe "Rails 5" do
  it "works" do
    Hatchet::Runner.new("rails5").deploy do |app, heroku|
      # Test BUNDLE_DISABLE_VERSION_CHECK works
      expect(app.output).not_to include("The latest bundler is")

      # Test worker task only appears if the app has that rake task
      worker_task = worker_task_for_app(app)
      expect(worker_task).to be_nil

      run!(%Q{echo "task 'jobs:work' do ; end" >> Rakefile})
      app.commit!

      app.deploy do
        worker_task = worker_task_for_app(app)
        expect(worker_task["command"]).to eq("bundle exec rake jobs:work")
      end
    end
  end

  def worker_task_for_app(app)
    app
     .api_rate_limit.call
     .formation
     .list(app.name)
     .detect { |h| h["type"] == "worker" }
  end

  describe "active storage" do
    it "non-local storage warnings" do
      Hatchet::Runner.new("active_storage_non_local").deploy do |app, heroku|
        expect(app.output).to     match('binary dependencies required')
        expect(app.output).to_not match('config.active_storage.service')
        expect(app.output).to_not match(/\$ rails runner/)
      end
    end

    it "local storage warnings" do
      app = Hatchet::Runner.new(
        "active_storage_local",
        buildpacks: [
          "https://github.com/heroku/heroku-buildpack-activestorage-preview",
          :default
        ]
      )
      app.setup!
      app.set_config('HEROKU_DEBUG_RAILS_RUNNER' => 'true')
      app.deploy do |app, heroku|
        expect(app.output).to_not match('binary dependencies required')
        expect(app.output).to     match('config.active_storage.service')
        expect(app.output).to     match('config.assets.compile = true')
        expect(app.output).to     match(/\$ rails runner/)
      end
    end
  end

  it "blocks bads sprockets config with bad version" do
    Hatchet::Runner.new("sprockets_asset_compile_true", allow_failure: true).deploy do |app, heroku|
      expect(app.output).to match('A security vulnerability has been detected')
      expect(app.output).to match('version "3.7.2"')
    end
  end
end

describe "Rails 5.1 and yarn" do

  # Rails generates a bin/yarn that changes the directory when you run it, this
  # causes problems when using the node buildpack https://github.com/heroku/heroku-buildpack-ruby/issues/1001
  def setup_bad_binstub_proc
    Proc.new do
      File.open("bin/yarn", "w") do |f|
        f.puts <<~EOM
        #!/usr/bin/env ruby

        puts ENV['PATH'].inspect

        raise "bad yarn binstub"
        EOM
      end
      run!("chmod +x bin/yarn")
    end
  end

  it "works without the node buildpack" do
    buildpacks = [
      :default,
      "https://github.com/sharpstone/force_absolute_paths_buildpack"
    ]
    Hatchet::Runner.new("rails51_webpacker", buildpacks: buildpacks).deploy do |app, heroku|
      expect(app.output).to include("Installing yarn")
      expect(app.output).to include("yarn install")
      expect(app.output).to_not include("bad yarn binstub")

      expect(app.run("which node")).to match("/app/bin/node") # We put node in bin/node
      expect(app.run("which yarn")).to match("/app/vendor/yarn-") # We put yarn in /app/vendor/yarn-
    end
  end

  it "works with the node buildpack" do
    buildpacks = [
      "heroku/nodejs",
      :default,
      "https://github.com/sharpstone/force_absolute_paths_buildpack"
    ]

    Hatchet::Runner.new("rails51_webpacker", before_deploy: setup_bad_binstub_proc, buildpacks: buildpacks).deploy do |app, heroku|
      expect(app.output).to include("yarn install")
      expect(app.output).to_not include("bad yarn binstub")

      expect(app.run("which node")).to match("/app/.heroku/node/bin")
      expect(app.run("which yarn")).to match("/app/.heroku/yarn/bin")
    end
  end
end
