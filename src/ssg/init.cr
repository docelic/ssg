module SSG
  # `ssg init DIR`: a minimal, working site.
  module Init
    FILES = {
      "config.yml" => <<-YAML,
        title: My Site
        base_url: http://localhost:1313/
        taxonomies: [tags]
        paginate: 10
        YAML
      "content/index.md" => <<-MD,
        ---
        title: Home
        ---
        Welcome. Edit `content/index.md` to change this page.
        MD
      "content/hello.md" => <<-MD,
        ---
        title: Hello
        date: 2026-01-01
        tags: [first]
        ---
        A page. Move it to `content/hello/index.md` when it needs images next to it.
        MD
      "layouts/base.html.j2" => <<-HTML,
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>{% block title %}{{ page.title }} | {{ site.title }}{% endblock %}</title>
          <link rel="stylesheet" href="/css/style.css">
        </head>
        <body>
          <header>
            <a href="/">{{ site.title }}</a>
            <nav>{% for s in site.home.children %}<a href="{{ s.url }}">{{ s.title }}</a> {% endfor %}</nav>
          </header>
          <main>{% block main %}{% endblock %}</main>
        </body>
        </html>
        HTML
      "layouts/page.html.j2" => <<-HTML,
        {% extends "base.html.j2" %}
        {% block main %}
        <article>
          <h1>{{ page.title }}</h1>
          {% if page.date %}<time>{{ page.date | date("%B %-d, %Y") }}</time>{% endif %}
          {{ content }}
          {% set tags = page.terms_for("tags") %}
          {% if tags %}<p>Tags: {% for t in tags %}<a href="{{ t.url }}">{{ t.title }}</a> {% endfor %}</p>{% endif %}
        </article>
        {% endblock %}
        HTML
      "layouts/list.html.j2" => <<-HTML,
        {% extends "base.html.j2" %}
        {% block main %}
        <h1>{{ page.title }}</h1>
        {{ content }}
        <ul>
        {% for p in paginator.pages %}
          <li><a href="{{ p.url }}">{{ p.title }}</a>{% if p.date %} <small>{{ p.date | date }}</small>{% endif %}</li>
        {% endfor %}
        </ul>
        {% if paginator.total > 1 %}
        <nav>
          {% if paginator.prev_url %}<a href="{{ paginator.prev_url }}">newer</a>{% endif %}
          {{ paginator.number }} / {{ paginator.total }}
          {% if paginator.next_url %}<a href="{{ paginator.next_url }}">older</a>{% endif %}
        </nav>
        {% endif %}
        {% endblock %}
        HTML
      "layouts/shortcodes.j2" => <<-J2,
        {# Macros defined here are available in every template and .j2 content file. #}
        {% macro note(kind="note") %}<aside class="{{ kind }}">{{ caller() }}</aside>{% endmacro %}
        J2
      "static/css/style.css" => <<-CSS,
        body { font-family: system-ui, sans-serif; max-width: 42rem; margin: 2rem auto; padding: 0 1rem; line-height: 1.5; }
        header { display: flex; gap: 1rem; margin-bottom: 2rem; }
        CSS
    }

    def self.run(dir : String)
      if Dir.exists?(dir) && !Dir.empty?(dir)
        raise Error.new("#{dir} exists and is not empty")
      end
      FILES.each do |rel, content|
        path = File.join(dir, rel)
        Dir.mkdir_p(File.dirname(path))
        File.write(path, content)
        STDERR.puts "  #{rel}"
      end
      STDERR.puts "created #{dir}; next: cd #{dir} && ssg serve"
    end
  end
end
