require_relative '../spec_helper'

class CnbRun
  attr_accessor :image_name, :output, :repo_path, :buildpack_path, :builder

  def initialize(repo_path, builder: "heroku/buildpacks:18", buildpack_path: )
    @repo_path = repo_path
    @image_name = "heroku-buildpack-ruby-tests:#{SecureRandom.hex}"
    @builder = builder
    @buildpack_path = buildpack_path
    @build_output = ""
  end

  def call
    command = "pack build #{image_name} --path #{repo_path} --buildpack #{buildpack_path} --builder heroku/buildpacks:18"
    @output = run_local!(command)
    yield self
  ensure
    teardown
  end

  def teardown
    return unless image_name
    repo_name, tag_name = image_name.split(":")

    docker_list = run_local!("docker images --no-trunc | grep #{repo_name} | grep #{tag_name}").chomp
    run_local!("docker rmi #{image_name} --force") if !docker_list.empty?
    @image_name = nil
  end

  def run(cmd)
    `docker run #{image_name} '#{cmd}'`.chomp
  end

  def run!(cmd)
    out = run(cmd)
    raise "Command #{cmd.inspect} failed. Output: #{out}" unless $?.success?
    out
  end

  private def run_local!(cmd)
    out = `#{cmd}`
    raise "Command #{cmd.inspect} failed. Output: #{out}" unless $?.success?
    out
  end
end

describe "cnb" do
  it "locally runs default_ruby app" do
    CnbRun.new(hatchet_path("rack/default_ruby"), buildpack_path: buildpack_path).call do |app|
      expect(app.output).to match("Compiling Ruby/Rack")

      run_out = app.run!("ruby -v")
      expect(run_out).to match(LanguagePack::RubyVersion::DEFAULT_VERSION_NUMBER)
    end
  end

  it "locally runs rails getting started" do
    CnbRun.new(hatchet_path("heroku/ruby-getting-started"), buildpack_path: buildpack_path).call do |app|
      expect(app.output).to match("Compiling Ruby/Rails")

      run_out = app.run!("ruby -v")
      expect(run_out).to match("2.4.4")
    end
  end
end

