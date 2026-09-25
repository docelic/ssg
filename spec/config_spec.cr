require "./spec_helper"

describe SSG::Config do
  it "passes markdown options through" do
    data = SSG::FrontMatter::Data.new
    data["markdown"] = YAML.parse("smart: true\nsafe: true")
    config = SSG::Config.new("/x", data)
    config.markdown.smart?.should be_true
    config.markdown.safe?.should be_true
    config.markdown.gfm?.should be_false
    md = SSG::Processors::Markdown.new(config.markdown)
    site = load_fixture("classify")
    ctx = SSG::Chain::Context.new(site, SSG::TemplateEnv.build(site))
    String.new(md.call(%(say "hi" <b>x</b>).to_slice, ctx)).should contain "&quot;hi&quot;".sub("&quot;hi&quot;", "“hi”")
    String.new(md.call(%(<b>x</b>).to_slice, ctx)).should contain "<!-- raw HTML omitted -->"
  end

  it "turns highlighting off or picks a theme" do
    data = SSG::FrontMatter::Data.new
    data["markdown"] = YAML.parse("highlight: false")
    SSG::Config.new("/x", data).highlight_theme.should be_nil
    data["markdown"] = YAML.parse("highlight: monokai\nline_numbers: true")
    c = SSG::Config.new("/x", data)
    c.highlight_theme.should eq "monokai"
    c.line_numbers?.should be_true
    SSG::Config.new("/x", SSG::FrontMatter::Data.new).highlight_theme.should eq "default-dark"
    expect_raises(SSG::Error, /unknown highlight theme/) { SSG::Processors::Markdown.formatter("no-such-theme", false) }
  end

  it "accepts one theme or a list and rejects missing ones" do
    root = File.join(FIXTURES, "classify")
    data = SSG::FrontMatter::Data.new
    data["theme"] = YAML.parse("basic")
    c = SSG::Config.new(root, data)
    c.themes.should eq ["basic"]
    c.layout_dirs.should eq [File.join(root, "layouts"), File.join(root, "themes/basic/layouts")]
    data["theme"] = YAML.parse("[basic, basic]")
    SSG::Config.new(root, data).themes.should eq ["basic", "basic"]
    data["theme"] = YAML.parse("nope")
    expect_raises(SSG::Error, /theme not found/) { SSG::Config.new(root, data) }
  end

  it "reads the sass output style" do
    data = SSG::FrontMatter::Data.new
    data["sass"] = YAML.parse("style: compressed")
    SSG::Config.new("/x", data).sass_style.should eq "compressed"
    SSG::Processors::Sass.style("compressed").should eq Sass::OutputStyle::COMPRESSED
    expect_raises(SSG::Error, /unknown sass style/) { SSG::Processors::Sass.style("tiny") }
  end

  it "rejects unknown markdown options" do
    data = SSG::FrontMatter::Data.new
    data["markdown"] = YAML.parse("bogus: true")
    expect_raises(SSG::Error, /unknown markdown option bogus/) { SSG::Config.new("/x", data) }
  end
end
