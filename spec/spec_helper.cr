require "spec"
require "json"
require "../src/ssg"

FIXTURES = File.expand_path("fixtures", __DIR__)
EXAMPLE  = File.expand_path("../example", __DIR__)
MINIMA   = File.expand_path("../themes/minima/exampleSite", __DIR__)

def load_fixture(name : String, drafts = false) : SSG::Site
  SSG::Site.new(SSG::Config.load(File.join(FIXTURES, name)), drafts: drafts)
end
