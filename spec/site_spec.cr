require "./spec_helper"

describe SSG::Site do
  site = load_fixture("classify")
  home = site.home

  it "makes the content root the home page, a list" do
    home.home?.should be_true
    home.kind.list?.should be_true
    home.url.should eq "/"
    home.title.should eq "Home"
    home.synthetic?.should be_false
  end

  it "treats a single file as a directory page" do
    about = site.find("about").not_nil!
    about.kind.page?.should be_true
    about.url.should eq "/about/"
    about.output_dir.should eq "about"
    about.parent.should eq home
  end

  it "gives resource directories without pages to the nearest ancestor page" do
    home.resources.map(&.rel_path).sort!.should eq ["about/photo.png", "assets/a.css", "feed.xml"]
    feed = home.resource("feed.xml").not_nil!
    feed.resolved.processed?.should be_true
    feed.url.should eq "/feed.xml"
  end

  it "synthesizes a section for a directory without an index that holds pages" do
    blog = site.find("blog").not_nil!
    blog.synthetic?.should be_true
    blog.kind.list?.should be_true
    blog.children.map(&.title).should eq ["Later", "Hello", "Shortcodes"] # date descending
    docs = site.find("docs").not_nil!
    docs.synthetic?.should be_true
    site.find("docs/intro").not_nil!.parent.should eq docs
  end

  it "attaches resources, including nested directories, to the page directory" do
    hello = site.find("blog/hello").not_nil!
    hello.resources.map(&.rel_path).sort!.should eq ["attach/data.txt", "img/x.png", "summary.txt"]
    hello.resource("img/x.png").not_nil!.url.should eq "/blog/hello/img/x.png"
  end

  it "skips drafts unless asked" do
    site.find("blog/hidden").should be_nil
    load_fixture("classify", drafts: true).find("blog/hidden").should_not be_nil
  end

  it "orders siblings by weight, then date descending, then title" do
    home.children.map(&.title).should eq ["About", "All tags", "Blog", "Custom", "Docs", "Section"]
    hello = site.find("blog/hello").not_nil!
    hello.next.not_nil!.title.should eq "Later"
    hello.prev.not_nil!.title.should eq "Shortcodes"
  end

  it "builds taxonomy and term pages as lists, reusing a real page at the taxonomy path" do
    tags = site.taxonomy_pages["tags"]
    tags.kind.list?.should be_true
    tags.taxonomy.should eq "tags"
    tags.term.should be_nil
    tags.synthetic?.should be_false
    tags.title.should eq "All tags"
    tags.pages.map(&.term).should eq ["a", "b", "cascaded"]
    site.sections.map(&.title).should eq ["Blog", "Docs", "Section"]
    a = site.find("tags/a").not_nil!
    a.kind.list?.should be_true
    a.term.should eq "a"
    a.pages.map(&.title).should eq ["Later", "Hello"]
    site.find("blog/hello").not_nil!.terms_for("tags").map(&.url).should eq ["/tags/a/", "/tags/b/"]
    site.taxonomy_pages.has_key?("categories").should be_false
  end

  it "applies a section's slug to everything below it" do
    site.find("sec").not_nil!.url.should eq "/renamed/"
    site.find("sec/child").not_nil!.url.should eq "/renamed/child/"
  end

  it "applies permalink patterns to regular pages of a section, and url overrides" do
    site.find("docs/intro").not_nil!.url.should eq "/d/intro/"
    site.find("docs").not_nil!.url.should eq "/docs/"
    custom = site.find("custom").not_nil!
    custom.url.should eq "/c/u/"
    custom.aliases.should eq ["/old-custom/", "/old.html"]
  end

  it "cascades front matter from config and sections, nearest wins" do
    site.find("about").not_nil!.data["author"].as_s.should eq "Site"
    child = site.find("sec/child").not_nil!
    child.data["author"].as_s.should eq "Section"
    child.terms_for("tags").map(&.term).should eq ["cascaded"]
    site.find("sec").not_nil!.data["author"].as_s.should eq "Section"
  end

  it "reads outputs from front matter and cascades it into synthesized pages" do
    site.find("about").not_nil!.outputs.should be_nil
    site.find("docs/intro").not_nil!.outputs.should eq ["html"]
    site.find("sec/silent").not_nil!.outputs.should eq [] of String
    site.find("tags/a").not_nil!.outputs.should eq ["html"] # synthesized after the first cascade pass
    site.find("sec").not_nil!.children.map(&.title).should contain "Silent"
  end

  it "finds pages by several spellings of their content path" do
    ["blog/hello", "/blog/hello/", "blog/hello/index.md", "about.md", "about"].each do |ref|
      site.find(ref).should_not be_nil
    end
    site.find("").should eq home
  end

  it "rejects two pages that map to the same url" do
    expect_raises(SSG::Error, /two pages map to \/about\//) { load_fixture("collision") }
  end
end
