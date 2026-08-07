# Activate and configure extensions
# https://middlemanapp.com/advanced/configuration/#configuring-extensions

require 'date'
require 'json'

# Constants declared here are not visible from templates, so site-wide values
# live in config and are read back through helpers.
set :site_langs, %i[ru en]
set :site_url, 'https://edenisn.ru'
set :site_email, 'edenisn@gmail.com'
set :site_profiles, [
  'https://github.com/edenisn',
  'https://t.me/edenisn',
  'https://career.habr.com/erofeevdn'
]

activate :i18n,
         templates_dir: 'localizable',
         mount_at_root: :ru,
         langs: config[:site_langs]

activate :syntax

activate :autoprefixer do |prefix|
  prefix.browsers = 'last 2 versions'
end

activate :directory_indexes

# The site is served from a domain root (Netlify / gh-pages + CNAME), so
# root-absolute paths are used throughout. Middleman's i18n url_for lookup
# cannot resolve localized paths once directory_indexes has rewritten them,
# so internal links are built by locale_path instead.
set :relative_links, false

set :markdown_engine, :kramdown
set :markdown, input: 'GFM', hard_wrap: false

# Netlify looks for /404.html exactly, so this one page keeps its file name.
page '/404.html', directory_index: false

# Per-page layout changes
page '/*.xml', layout: false
page '/*.json', layout: false
page '/*.txt', layout: false

helpers do
  def site_langs
    config[:site_langs]
  end

  # Russian is mounted at the root, every other locale sits under /<locale>/.
  # `page` is a bare slug: '' for the home page, 'cv' for /cv/.
  def locale_path(page = '', locale: I18n.locale)
    prefix = locale.to_sym == :ru ? '' : "/#{locale}"
    page.to_s.empty? ? "#{prefix}/" : "#{prefix}/#{page}/"
  end

  def absolute_url(path)
    File.join(config[:site_url], path)
  end

  def other_langs
    site_langs.reject { |lang| lang == I18n.locale }
  end

  def current_section
    current_page.data.section || 'home'
  end

  def current_slug
    current_section == 'home' ? '' : current_section
  end

  # Internal links are emitted directly rather than through link_to: Padrino
  # pipes hrefs through url_for, and Middleman's i18n override rewrites an
  # already-localized path back to the current locale, which breaks the
  # language switcher.
  def nav_link(section, page)
    classes = ['nav__link']
    classes << 'is-current' if current_section == section
    content_tag(:a, t("nav.#{section}"), href: locale_path(page), class: classes.join(' '))
  end

  # ------------------------------------------------------------ structured data

  # schema.org/Person, so search engines can tie the name, the job and the
  # profiles together instead of guessing from prose.
  def person_schema
    current_job = t('cv.jobs').find { |job| job[:end].nil? }

    data = {
      '@context' => 'https://schema.org',
      '@type' => 'Person',
      'name' => t('home.name'),
      'alternateName' => t('home.handle'),
      'jobTitle' => t('home.role'),
      'description' => t(current_page.data.description_key),
      'url' => absolute_url(locale_path),
      'image' => absolute_url('/images/portrait.jpg'),
      'email' => "mailto:#{config[:site_email]}",
      'sameAs' => config[:site_profiles],
      'knowsAbout' => t('cv.skill_groups').flat_map { |group| group[:items] },
      'alumniOf' => {
        '@type' => 'CollegeOrUniversity',
        'name' => t('cv.schools').first[:place]
      }
    }

    if current_job
      data['worksFor'] = { '@type' => 'Organization', 'name' => current_job[:company] }
    end

    JSON.pretty_generate(data)
  end

  # ---------------------------------------------------------------- CV dates
  # Jobs store machine-readable 'YYYY-MM' months; the displayed period and
  # duration are derived so open-ended entries stay correct. They are computed
  # at build time, so a stale deploy shows stale durations.

  def parse_month(value)
    year, month = value.to_s.split('-').map(&:to_i)
    Date.new(year, month, 1)
  end

  # Month and year are glued with a non-breaking space so a narrow date column
  # can only wrap around the dash, never leaving an orphaned year behind.
  def format_month(value)
    return value.to_s if value.to_s.match?(/\A\d{4}\z/)

    date = parse_month(value)
    "#{I18n.t('date.month_names')[date.month - 1]}\u00A0#{date.year}"
  end

  # Habr counts both the first and the last month, hence the +1.
  def months_between(from, to)
    (to.year - from.year) * 12 + (to.month - from.month) + 1
  end

  # Russian needs three plural forms, English two.
  def pluralize_unit(count, unit)
    forms = I18n.t("units.#{unit}")

    form = if forms.size == 3
             if (11..14).cover?(count % 100) then forms[2]
             elsif count % 10 == 1 then forms[0]
             elsif (2..4).cover?(count % 10) then forms[1]
             else forms[2]
             end
           else
             count == 1 ? forms[0] : forms[1]
           end

    "#{count} #{form}"
  end

  def format_duration(months)
    years, rest = months.divmod(12)

    parts = []
    parts << pluralize_unit(years, 'years') if years.positive?
    parts << pluralize_unit(rest, 'months') if rest.positive?
    parts << pluralize_unit(0, 'months') if parts.empty?
    parts.join(' ')
  end

  def entry_period(item)
    finish = if item[:end]
               format_month(item[:end])
             else
               t('cv.present').tr(' ', "\u00A0")
             end

    "#{format_month(item[:start])} — #{finish}"
  end

  def job_duration(job)
    finish = job[:end] ? parse_month(job[:end]) : Date.today
    format_duration(months_between(parse_month(job[:start]), finish))
  end

  # Total experience runs from the earliest job to today.
  def total_experience
    earliest = t('cv.jobs').map { |job| parse_month(job[:start]) }.min
    format_duration(months_between(earliest, Date.today))
  end
end

configure :build do
  activate :minify_css
  activate :minify_javascript
end
