# -*- coding: utf-8 -*-

require 'open-uri'
require 'i18n'

def download file, output_path
  assets_path = 'https://github.com/61bits/rails-templates/raw/master/assets'

  file_name = file =~ /^http/ ? /[^\/]+$/.match(file)[0] : file
  file_url = file =~ /^http/ ? file : "#{assets_path}/#{file_name}"

  output_file = output_path =~ /[^\/]+\.[^\/]+\s*$/ ? output_path : "#{output_path}/#{file_name}"

  puts "    \033[1;32mdownload\033[0m    #{output_file}"

  case
  when command?('aria2c'); run("aria2c -o #{output_file} #{file_url}")
  when command?('curl'); run("curl -o #{output_file} #{file_url}")
  when command?('wget'); run("wget -O #{output_file} #{file_url}")
  else File.open("#{output_file}", 'wb') { |f| f.write open("#{file_url}").read }
  end
end

def command?(name)
  `which #{name}`
  $?.success?
end

def clean_for_heroku(string)
  I18n.transliterate(string).downcase.strip.gsub(/\s/, '-')
end

def ask_question question, fallback = ''
  result = ''
  if fallback.empty?
    result = ask "    \033[1;34manswer\033[0m    #{question}?"
  else
    result = ask "    \033[1;34manswer\033[0m    #{question} (#{fallback})?"
    result = result.empty? ? fallback : result
  end
  result
end

def ask_yes_or_no_question question
  yes? "    \033[1;34manswer\033[0m    #{question}?"
end

def warn message
  puts "        \033[1;33mwarn\033[0m    #{message}"
end

def heroku command, repository = ''
  if repository.empty?
    run "heroku #{command}"
  else
    run "heroku #{command} -a #{repository}"
  end
end

def create_mailtrap_configuration environment
  append_file "config/environments/#{environment}.rb", <<-'RUBY'
ActionMailer::Base.delivery_method = :smtp
ActionMailer::Base.smtp_settings = {
  address:        ENV['MAILTRAP_HOST'],
  port:           ENV['MAILTRAP_PORT'],
  authentication: :plain,
  user_name:      ENV['MAILTRAP_USER_NAME'],
  password:       ENV['MAILTRAP_PASSWORD']
}
    RUBY

  git add: "."
  git commit: "-am 'Mailtrap configuration for #{environment}.'"
end

def create_sendgrid_configuration environment
  append_file "config/environments/#{environment}.rb", <<-'RUBY'
ActionMailer::Base.delivery_method = :smtp
ActionMailer::Base.smtp_settings = {
  address:              'smtp.sendgrid.net',
  port:                 '587',
  authentication:       :plain,
  user_name:            ENV['SENDGRID_USERNAME'],
  password:             ENV['SENDGRID_PASSWORD'],
  domain:               ENV['APP_HOSTNAME'],
  enable_starttls_auto: true
}
    RUBY

  git add: "."
  git commit: "-am 'Sendgrid configuration for #{environment}.'"
end

def check_heroku_repository_name name
  allowed_characters = name =~ /^[a-z][a-z0-9-]+$/
  size = name.length <= 30
  warn "Name must start with a letter and can only contain lowercase letters, numbers, and dashes." unless allowed_characters
  warn "Name is too long (maximum is 30 characters)" unless size
  size && allowed_characters
end

def options_for_heroku_bootstrap_environment environment, team_name, software_name
  options = {}

  team_name_for_heroku = clean_for_heroku(team_name)
  team_name_for_heroku = "r#{team_name_for_heroku}" if team_name_for_heroku =~ /^\d/

  software_name = ask_question "Software name" if software_name.nil?
  software_name_for_heroku = clean_for_heroku(software_name)

  repository_name = clean_for_heroku("#{team_name_for_heroku}-#{software_name_for_heroku}-#{environment}")
  begin
    repository_name = ask_question "Name for #{environment}", repository_name
  end until check_heroku_repository_name(repository_name)

  options[:repository_name] = repository_name

  options[:free_addons] = ask_yes_or_no_question("Bootstrap free Heroku addons for #{environment}")
  options[:email] = ask_yes_or_no_question("Bootstrap free Heroku email addon for #{environment}")
  options[:dns] = ask_yes_or_no_question("Bootstrap free Heroku dns addon for #{environment}")

  options[:push] = ask_yes_or_no_question("Push #{environment} to Heroku")

  options
end

def bootstrap_heroku_environment environment, options
  repository_name = options[:repository_name]

  heroku "create #{repository_name} --remote #{environment}"

  heroku_domain = `heroku domains --remote #{environment} | grep heroku`.strip

  heroku "config:set APP_HOSTNAME=#{heroku_domain} WEB_CONCURRENCY=3 RAILS_ENV=#{environment} RACK_ENV=#{environment}", repository_name
  heroku "config:set BUILDPACK_URL='git://github.com/qnyp/heroku-buildpack-ruby-bower.git#run-bower'", repository_name

  if options[:free_addons]
    heroku "config:add NEW_RELIC_APP_NAME=#{heroku_domain}", repository_name
    heroku "addons:add newrelic:standard", repository_name
    heroku "addons:add heroku-postgresql:dev", repository_name
    heroku "addons:add pgbackups:auto-month", repository_name
    heroku "addons:add memcachier:dev", repository_name
    heroku "addons:add papertrail:choklad", repository_name
    heroku "addons:add sentry:developer", repository_name
    heroku "addons:add scheduler:standard", repository_name

    if options[:email]
      if environment.to_s == 'staging'
        warn 'Adding Mailtrap since its a staging environment'
        heroku "addons:add mailtrap:free", repository_name
        create_mailtrap_configuration environment
      else
        warn 'Adding Sendgrid'
        heroku "addons:add sendgrid:starter", repository_name
        create_sendgrid_configuration environment
      end
    end

    heroku "addons:add zerigo_dns:basic", repository_name if options[:dns]
  end

  if environment.to_s == 'production'
    heroku "config:set HEROKU_WAKEUP=true", repository_name
  else
    heroku "config:set HEROKU_WAKEUP=false", repository_name
  end

  application(nil, env: environment) do <<-RUBY

  # config.asset_host = "http://#{heroku_domain}"
  RUBY
  end

  git add: "."
  git commit: "-am 'Heroku as asset host on #{environment} environment.'"
end

def push_to_heroku environment, options
  if options[:push]
    git push: "#{environment} master"
    heroku "run rake db:migrate", options[:repository_name]
  end
end

# ============================================================================
# Questions
# ============================================================================

team_name = ask_question 'Team name'
team_email = ask_question 'Team email'
team_url = ask_question 'Team full url'
styled_team_name = command?('figlet') ? `figlet -f larry3d #{team_name}` : team_name
is_pt_BR = ask_yes_or_no_question("Change locale to pt-BR and time zone to Brazil's official time")
has_active_admin = ask_yes_or_no_question('Install admin panel (via ActiveAdmin)')
has_devise = ask_yes_or_no_question 'Install authentication (via Devise)'
has_formtastic = false
has_formtastic = ask_yes_or_no_question 'Install form builder (via Formtastic)' unless has_active_admin

is_free_software = ask_yes_or_no_question 'Is this free software'
unless is_free_software
  license_date = ask_question 'Software license date', Time.now.strftime('%Y-%m-%d')
  license_licensee = ask_question 'Software licensee'
  license_software_name = ask_question 'Software name'
end

database_prefix = ask_question 'What is your database prefix'
database_username = ask_question 'What is your database username'
database_password = ask_question 'What is your database password'

bootstrap_staging = ask_yes_or_no_question('Bootstrap a staging environment on Heroku')
staging_options = options_for_heroku_bootstrap_environment(:staging, team_name, license_software_name) if bootstrap_staging

bootstrap_production = ask_yes_or_no_question('Bootstrap a production environment on Heroku')
production_options = options_for_heroku_bootstrap_environment(:production, team_name, license_software_name) if bootstrap_production


# ============================================================================
# Bower
# ============================================================================

Dir.mkdir 'vendor/assets/bower_components'
file 'vendor/assets/bower_components/.keep', ''

application do <<-'RUBY'

    config.assets.paths << Rails.root.join('vendor', 'assets', 'bower_components')
RUBY
end

file '.bowerrc', <<-'JS'
{
  "directory": "vendor/assets/bower_components"
}
JS

run 'bower init'

inject_into_file 'bower.json', after: "{\n" do <<-'JS'
  "dependencies": {
    "jquery": "~> 1.10.0",
    "modernizr": "latest"
  },
JS
end

inject_into_file 'bower.json', after: "\"authors\": [\n" do <<-JS
    "#{team_name} <#{team_email}>",
JS
end

run 'bower install'

append_file '.gitignore', <<'FILE'
vendor/assets/bower_components/*
FILE

# ============================================================================
# Unicorn + Foreman
# ============================================================================

gem 'unicorn'
gem 'foreman', group: :development

file 'Procfile', <<FILE
web: bundle exec unicorn -p $PORT -c ./config/unicorn.rb
FILE

file 'Procfile-dev', <<FILE
web: bundle exec unicorn -p $PORT -c ./config/unicorn.rb
guard: bundle exec guard start -i
FILE

file '.env', <<FILE
WEB_CONCURRENCY=2
RACK_ENV=none
RAILS_ENV=development
APP_HOSTNAME=localhost
HEROKU_WAKEUP=false
PORT=5000
MEMCACHIER_SERVERS=localhost:11211
FILE

file 'config/unicorn.rb', <<RUBY
worker_processes Integer(ENV["WEB_CONCURRENCY"] || 3)
ENV['RAILS_ENV'] == 'development' ? timeout(90) : timeout(15)
preload_app true

before_fork do |server, worker|
  Signal.trap 'TERM' do
    puts 'Unicorn master intercepting TERM and sending myself QUIT instead'
    Process.kill 'QUIT', Process.pid
  end

  ActiveRecord::Base.connection.disconnect! if defined?(ActiveRecord::Base)

  if defined?(Resque)
    Resque.redis.quit
    Rails.logger.info('Disconnected from Redis')
  end
end

after_fork do |server, worker|
  Signal.trap 'TERM' do
    puts 'Unicorn worker intercepting TERM and doing nothing. Wait for master to send QUIT'
  end

  ActiveRecord::Base.establish_connection if defined?(ActiveRecord::Base)

  if defined?(Resque)
    Resque.redis = ENV['REDIS_URI']
    Rails.logger.info('Connected to Redis')
  end
end
RUBY

application(nil, env: :development) do <<RUBY

  config.logger = Logger.new(STDOUT)
  config.logger.level = Logger.const_get(ENV['LOG_LEVEL'] ? ENV['LOG_LEVEL'].upcase : 'DEBUG')
RUBY
end

# ============================================================================
# Guard (livereload, bundler)
# ============================================================================

gem 'guard-livereload', require: false, group: :development
gem 'rack-livereload', group: :development
gem 'rb-fsevent', require: false, group: :development

run 'bundle exec guard init'

gsub_file 'Guardfile', '(.+\.(css|js|html)))', '((?<!#).+\.(css|js|html|scss|sass|coffee)))'

gsub_file 'Guardfile', "guard 'livereload' do", "guard 'livereload', grace_period: 0.5 do"

application(nil, env: :development) do <<RUBY

  config.middleware.use Rack::LiveReload
RUBY
end

gem 'guard-bundler', group: :development
run 'bundle exec guard init bundler'

# ============================================================================
# Action Mailer
# ============================================================================

application(nil, env: :development) do <<-'RUBY'

  config.action_mailer.default_url_options = { host: 'localhost:5000' }
RUBY
end

application(nil, env: :production) do <<-'RUBY'

  config.action_mailer.default_url_options = { host: ENV['APP_HOSTNAME'] }
RUBY
end

# ============================================================================
# Locales
# ============================================================================

application do <<-'RUBY'

    config.i18n.load_path += Dir[Rails.root.join('config', 'locales', '**/*.{rb,yml}').to_s]
RUBY
end

file 'config/locales/app.en.yml', <<-'YML'
en:
  app:
    old_ie_warning:
      You are using an <strong>outdated</strong> browser. 
      Please <a href="http://browsehappy.com/">upgrade your browser</a> to improve your experience.
YML

if is_pt_BR
  application do <<-'RUBY'

    config.i18n.default_locale = 'pt-BR'
    config.time_zone = 'Brasilia'
  RUBY
  end

  download 'https://github.com/svenfuchs/rails-i18n/raw/master/rails/locale/pt-BR.yml', 'config/locales'

  file 'config/locales/app.pt-BR.yml', <<-'YML'
pt-BR:
  app:
    old_ie_warning:
      Você está usando um navegador <strong>desatualizado</strong>. 
      Por favor <a href="http://browsehappy.com/">atualize o seu navegador</a> para melhorar a sua experiência.
  YML
end

gsub_file 'app/controllers/application_controller.rb', /end\s*$/ ,<<-'RUBY'

  protected

  def set_locale
    I18n.locale = params[:locale] || I18n.default_locale
  end

  def render_not_found
    render file: 'public/404.html', status: 404, layout: false
  end
end
RUBY


# ============================================================================
# Pry
# ============================================================================

gem 'pry'
gem 'pry-doc'

application do <<RUBY

    console do
      require 'pry'
      config.console = Pry
    end
RUBY
end

# ============================================================================
# Compass
# ============================================================================

gem 'compass-rails', '~> 2.0.alpha.0'
gem 'compass-normalize'
gem 'singularitygs'
gem 'singularity-extras'
gem 'breakpoint'
gem 'color-schemer'
gem 'toolkit'
gem 'oily_png'

# ============================================================================
# SASS & SMACSS
# ============================================================================

Dir.mkdir 'app/assets/stylesheets/base'
file 'app/assets/stylesheets/base/_all.sass', <<-'SASS'
// ---------------------------------------------------------------------------
//  BASE IMPORTS
// ---------------------------------------------------------------------------
// Styles relevant to the hole application, always.

// COMPASS
// tollkit includes: compass, color-schemer and breakpoint
@import "toolkit"
@import "singularitygs"
@import "singularity-extras"
@import "normalize"

// BASE PARTIALS
@import "variables"
@import "mixins"
@import "fonts"

// BASE STYLES

+establish-baseline

html
  min-height: 100%

body
  color: $text-color
  font-family: $sans-family
  font-size: $base-font-size
  line-height: $base-line-height

*::selection
  background: $text-selection-background
  color: $text-selection-color

*
  margin: 0
  padding: 0

SASS

file 'app/assets/stylesheets/base/_variables.sass', <<-'SASS'
// SINGULARITYGS & BREAKPOINT
$bp-320: 320px
$bp-768: 768px
$bp-1024: 1024px
$bp-1280: 1280px
$bp-1440: 1440px
$bp-1920: 1920px
//$grids: add-grid(4 at $bp-320)
//$grids: add-grid(6 at $bp-768)
//$grids: add-grid(9 at $bp-1024)
//$grids: add-grid(12 at $bp-1280)
//$grids: 12
//$gutters: .2
$breakpoint-no-queries: false
$breakpoint-no-query-fallbacks: true

// VERTICAL RHYTHM
$base-font-size: 14px
$base-line-height: 20px
$round-to-nearest-half-line: false
$font-unit: 14px

// COMPASS CROSS-BROWSER SUPPORT
$legacy-support-for-ie6: false
$legacy-support-for-ie7: false
$legacy-support-for-ie8: true

// COMPASS DEFAULTS
$default-text-shadow-blur: 0

// COLORS
$gray-dark: #333333
$yellow: #ffc40d

// TYPOGRAPHY
$text-selection-color: $gray-dark
$text-selection-background: lighten($yellow, 40)
$sans-family: "Helvetica Neue", Helvetica, Arial, sans-serif
$serif-family: "Georgia", "Times New Roman", Times, Cambria, Georgia, serif
$monospace-family: "Monaco", "Courier New", monospace, sans-serif
$text-color: $gray-dark !default

SASS

file 'app/assets/stylesheets/base/_fonts.sass', <<-'SASS'
@charset "UTF-8"
// @import url(http://fonts.googleapis.com/css?family=PT+Sans+Caption:400,700)
// +font-face("Font", font-files("font.woff", woff, "font.otf", opentype, "font.ttf", truetype, "font.svg", svg), "font.eot", bold, normal)
SASS

Dir.mkdir 'vendor/assets/fonts'
file 'vendor/assets/fonts/.keep', ''

file 'app/assets/stylesheets/base/_mixins.sass', <<-'SASS'
=background-2x($background, $file: 'png')
  $image: #{$background+"."+$file}
  $image2x: #{$background+"@2x."+$file}

  background: image-url($image) no-repeat
  @media (min--moz-device-pixel-ratio: 1.3),(-o-min-device-pixel-ratio: 2.6/2),(-webkit-min-device-pixel-ratio: 1.3),(min-device-pixel-ratio: 1.3),(min-resolution: 1.3dppx)
    background-image: image-url($image2x)
    background-size: image-width($image) image-height($image)

=improve-text-rendering
  text-rendering: optimizeLegibility
  -webkit-font-smoothing: antialiased

=fade-on-hover
  +transition(0.25s)
  &:hover
    +opacity(0.8)

=debug
  background-color: rgba(red,0.6)

SASS

Dir.mkdir 'app/assets/stylesheets/layouts'
file 'app/assets/stylesheets/layouts/_all.sass', <<-'SASS'
// ---------------------------------------------------------------------------
//  LAYOUT IMPORTS
// ---------------------------------------------------------------------------
// Styles relevant only to the page layouts.
SASS

file 'app/assets/stylesheets/layouts/_page.sass', <<-'SASS'
.l-page
  padding-top: 1px
SASS

Dir.mkdir 'app/assets/stylesheets/modules'
file 'app/assets/stylesheets/modules/_all.sass', <<-'SASS'
// ---------------------------------------------------------------------------
//  MODULE IMPORTS
// ---------------------------------------------------------------------------
// Styles relevant only to visual module components.
SASS

Dir.mkdir 'app/assets/stylesheets/states'
file 'app/assets/stylesheets/states/_all.sass', <<-'SASS'
// ---------------------------------------------------------------------------
//  STATE IMPORTS
// ---------------------------------------------------------------------------
// Styles relevant to state specializations.
SASS

Dir.mkdir 'app/assets/stylesheets/themes'
file 'app/assets/stylesheets/themes/_all.sass', <<-'SASS'
// ---------------------------------------------------------------------------
//  THEME IMPORTS
// ---------------------------------------------------------------------------
// Styles relevant to layout themes.
SASS

File.delete 'app/assets/stylesheets/application.css'
file 'app/assets/stylesheets/application.sass', <<-'SASS'
@import "base/all"
@import "layouts/all"
@import "modules/all"
@import "states/all"
@import "themes/all"
SASS

# ============================================================================
# Javascripts & Coffeescripts
# ============================================================================

File.delete 'app/assets/javascripts/application.js'
file 'app/assets/javascripts/application.coffee', <<COFFEE
#= require jquery/jquery
#= require jquery_ujs
#= require modernizr/modernizr
COFFEE

file 'app/assets/javascripts/viewport.coffee', <<'COFFEE'
$ ->
  iphone = 'user-scalable=yes, width=980, initial-scale=0.33'
  ipad = 'user-scalable=yes, width=980, initial-scale=0.75'

  switch
    when ($ window).width() <= 400
      $('meta[name=viewport]').attr('content', iphone)
    when ($ window).width() <= 800
      $('meta[name=viewport]').attr('content', ipad)
COFFEE

application(nil, env: :production) do <<-'RUBY'

  config.assets.precompile += %w(
  )
RUBY
end

# ============================================================================
# Draper
# ============================================================================

gem 'draper'

Dir.mkdir 'app/models/decorators'
file 'app/models/decorators/.keep', ''

application do <<-'RUBY'

    config.autoload_paths += Dir[Rails.root.join('app', 'models', 'decorators')]
RUBY
end

# ============================================================================
# Slim
# ============================================================================

gem 'slim'
gem 'html2slim', group: :development

application(nil, env: :development) do <<'RUBY'
Slim::Engine.set_default_options pretty: true, sort_attrs: false, format: :html5
RUBY
end

application(nil, env: :production) do <<'RUBY'
Slim::Engine.set_default_options format: :html5
RUBY
end

# ============================================================================
# crossdomain.xml, robots.txt and humans.txt
# ============================================================================

file 'public/crossdomain.xml', <<XML
<?xml version="1.0"?>
<!DOCTYPE cross-domain-policy SYSTEM "http://www.adobe.com/xml/dtds/cross-domain-policy.dtd">
<cross-domain-policy>
<!-- Read this: www.adobe.com/devnet/articles/crossdomain_policy_file_spec.html -->
<!-- Most restrictive policy: -->
	<site-control permitted-cross-domain-policies="none"/>
<!-- Least restrictive policy: -->
<!--
	<site-control permitted-cross-domain-policies="all"/>
	<allow-access-from domain="*" to-ports="*" secure="false"/>
	<allow-http-request-headers-from domain="*" headers="*" secure="false"/>
-->
<!--
  If you host a crossdomain.xml file with allow-access-from domain="*"
  and don’t understand all of the points described here, you probably
  have a nasty security vulnerability. ~ simon willison
-->
</cross-domain-policy>
XML

File.delete 'public/robots.txt'
file 'public/robots.txt', <<TXT
# http://www.robotstxt.org/
User-agent: *
Disallow:
TXT

file 'public/humans.txt', <<TXT
#{styled_team_name}

The humans.txt file explains the team, technology,
and creative assets behind this site.
http://humanstxt.org

_______________________________________________________________________________
TEAM

This site was hand-crafted by #{team_name}
#{team_url}
#{team_email}

_______________________________________________________________________________
TECHNOLOGY

Ruby on Rails
http://rubyonrails.org

HTML5 Boilerplate
http://html5boilerplate.com

Slim
http://slim-lang.com

Sass
http://sass-lang.com

Compass
http://compass-style.org

SingularityGS
http://singularity.gs/

jQuery
http://jquery.com

Modernizr
http://modernizr.com

CoffeeScript
http://coffeescript.org
TXT

# ============================================================================
# HTML5Boilerplate Layout
# ============================================================================

File.delete 'app/views/layouts/application.html.erb'

file 'app/views/layouts/application.slim', <<-'SLIM'
/ Based on HTML5 Boilerplate 4.3.0, http://html5boilerplate.com/
doctype html

/[if lt IE 7]
  <html class="no-js lt-ie9 lt-ie8 lt-ie7" lang="#{I18n.locale}">
/[if IE 7]
  <html class="no-js lt-ie9 lt-ie8" lang="#{I18n.locale}">
/[if IE 8]
  <html class="no-js lt-ie9" lang="#{I18n.locale}">

/![if gt IE 8]><!
html.no-js lang="#{I18n.locale}"
  /! <![endif]

  head
    title #{(content_for?(:title) ? "#{yield :title} — " : "") + Rails.application.class.parent_name }
    == render 'layouts/metatags'
    == render 'layouts/favicons'

    == csrf_meta_tags unless response.cache_control[:public]
    == stylesheet_link_tag 'application', media: 'all', 'data-turbolinks-track' => true
    == javascript_include_tag 'application', 'data-turbolinks-track' => true

  body class="#{yield :body_class}"
    == render 'layouts/browser_warning'

    section.l-page class="#{yield :wrapper_class}"
      == yield
SLIM

file 'app/views/layouts/_metatags.slim', <<'SLIM'
meta name="description" content="#{content_for?(:description) ? yield(:description) : Rails.application.class.parent_name}"
meta property="og:title" content="#{content_for?(:title) ? yield(:title).to_s + '— ' : ''}#{Rails.application.class.parent_name}"
meta property="og:description" content="#{content_for?(:description) ? yield(:description) : Rails.application.class.parent_name}"

- cache "layouts/_metatags" do
  // html metatags
  meta charset="utf-8"
  meta http-equiv="X-UA-Compatible" content="IE=edge"
  meta name="author" content="TEAM_NAME — TEAM_URL"
  meta name="viewport" content="width=device-width, initial-scale=1"

  // opengraph metatags
  meta property="og:image" content="#{asset_url('og-image.png')}"
  meta property="og:type" content="website"
  meta property="og:url" content="#{root_url}"
  meta property="og:locale" content="pt_BR"
  // meta property="fb:admins" content="#admin-id" 

  // humans.txt
  link rel="author" href="#{asset_url('humans.txt')}"
SLIM

gsub_file 'app/views/layouts/_metatags.slim', 'TEAM_NAME', team_name
gsub_file 'app/views/layouts/_metatags.slim', 'TEAM_URL', team_url

file 'app/views/layouts/_favicons.slim', <<-'SLIM'
- cache "layouts/_favicons" do
  == favicon_link_tag '/apple-touch-icon-precomposed.png', rel: 'apple-touch-icon', \
                                                           type: 'image/png', \
                                                           sizes: '152x152'
  == favicon_link_tag '/favicon.ico'
SLIM

File.delete 'public/favicon.ico'
download 'favicon.ico', 'public'
download 'apple-touch-icon-152x152-precomposed.png', 'public/apple-touch-icon-precomposed.png'

file 'app/views/layouts/_browser_warning.slim', <<-'SLIM'
/[if lte IE 7]
  p.browsehappy == t 'app.old_ie_warning'
SLIM

# ============================================================================
# Pages Controller, Frontend Controller
# ============================================================================

Dir.mkdir 'app/views/pages'

file 'app/views/pages/index.slim', <<-'SLIM'
h1 pages#index
SLIM

file 'app/controllers/pages_controller.rb', <<-'RUBY'
class PagesController < ApplicationController
  def show
    render_page_template or render_not_found
  end

  private

  def render_page_template
    render "pages/#{params[:slug]}" if template_exists?("pages/#{params[:slug]}")
  end
end
RUBY

route "root to: 'pages#show', defaults: { slug: 'index'}"
route "get ':slug' => 'pages#show', as: :page"

Dir.mkdir 'app/views/frontend'

file 'app/controllers/frontend_controller.rb', <<-'RUBY'
class FrontendController < ApplicationController
  def show
    @entries = Dir.entries(Rails.root.join('app', 'views', 'frontend')) - [".", "..", "index.slim"]
    @entries.sort!
    render_page_template or render_not_found
  end

  private

  def render_page_template
    render "frontend/#{params[:template]}" if template_exists?("frontend/#{params[:template]}")
  end
end
RUBY

file 'app/views/frontend/index.slim', <<-'SLIM'
- if @entries.present?
  h1 Frontend Files:
  ul
    - @entries.each do |entry|
      li = link_to entry, frontend_template_path(entry.gsub(/(.html)?\.\w+$/, ''))
SLIM

file 'app/views/frontend/comparision_sheet.slim', <<-'SLIM'

h1 Comparison Sheet:

section.l-page
  #content
    h1 Heading 1
    h2 Heading 2
    h3 Heading 3
    h4 Heading 4
    h5 Heading 5
    h6 Heading 6
    section
      h1 Heading 1 (in section)
      h2 Heading 2 (in section)
      h3 Heading 3 (in section)
      h4 Heading 4 (in section)
      h5 Heading 5 (in section)
      h6 Heading 6 (in section)
    article
      h1 Heading 1 (in article)
      h2 Heading 2 (in article)
      h3 Heading 3 (in article)
      h4 Heading 4 (in article)
      h5 Heading 5 (in article)
      h6 Heading 6 (in article)
    header
      hgroup
        h1 Heading 1 (in hgroup)
        h2 Heading 2 (in hgroup)
      nav
        ul
          li
            a href="#" navigation item #1
          li
            a href="#" navigation item #2
          li
            a href="#" navigation item #3
    h1 Text-level semantics
    p hidden=true This should be hidden in all browsers, apart from IE6
    p
      ' Lorem ipsum dolor sit amet, consectetuer adipiscing elit. Aenean commodo ligula eget dolor. 
        Aenean massa. Cum sociis natoque penatibus et m.
        Lorem ipsum dolor sit amet, consectetuer adipiscing elit. Aenean commodo ligula eget dolor. 
        Aenean massa. Cum sociis natoque penatibus et m.
        Lorem ipsum dolor sit amet, consectetuer adipiscing elit. Aenean commodo ligula eget dolor. 
        Aenean massa. Cum sociis natoque penatibus et m.
    p
      ' Lorem ipsum dolor sit amet, consectetuer adipiscing elit. Aenean commodo ligula eget dolor. 
        Aenean massa. Cum sociis natoque penatibus et m.
        Lorem ipsum dolor sit amet, consectetuer adipiscing elit. Aenean commodo ligula eget dolor. 
        Aenean massa. Cum sociis natoque penatibus et m.
        Lorem ipsum dolor sit amet, consectetuer adipiscing elit. Aenean commodo ligula eget dolor. 
        Aenean massa. Cum sociis natoque penatibus et m.
    address Address somewhere, world
    hr
    hr style="height:4px; border:solid #000; border-width:1px 0;"
    p
      |  The 
      a href="#"
        | a element
      |  example
      br
      |  The 
      abbr
        | abbr element
      |  and 
      abbr title="Title text"
        | abbr element with title
      |  examples
      br
      |  The 
      b
        | b element
      |  example
      br
      |  The 
      cite
        | cite element
      |  example
      br
      |  The 
      code
        | code element
      |  example
      br
      |  The 
      del
        | del element
      |  example
      br
      |  The 
      dfn
        | dfn element
      |  and 
      dfn title="Title text"
        | dfn element with title
      |  examples
      br
      |  The 
      em
        | em element
      |  example
      br
      |  The 
      i
        | i element
      |  example
      br
      |  The img element 
      img src="http://lorempixel.com/16/16" alt=""
      |  example
      br
      |  The 
      ins
        | ins element
      |  example
      br
      |  The 
      kbd
        | kbd element
      |  example
      br
      |  The 
      mark
        | mark element
      |  example
      br
      |  The 
      q
        | q element 
        q
          | inside
        |  a q element
      |  example
      br
      |  The 
      s
        | s element
      |  example
      br
      |  The 
      samp
        | samp element
      |  example
      br
      |  The 
      small
        | small element
      |  example
      br
      |  The 
      span
        | span element
      |  example
      br
      |  The 
      strong
        | strong element
      |  example
      br
      |  The 
      sub
        | sub element
      |  example
      br
      |  The 
      sup
        | sup element
      |  example
      br
      |  The 
      u
        | u element
      |  example
      br
      |  The 
      var
        | var element
      |  example 
    h1 Embedded content
    h3 audio
    audio controls=true
    audio
    h3 img
    img src="http://lorempixel.com/100/100" alt=""
    a href="#"
      img src="http://lorempixel.com/100/100" alt=""
    h3 svg
    svg width="100px" height="100px"
      circle cx="100" cy="100" r="100" fill="#ff0000"
    h3 video
    video controls=true
    video
    h1 Interactive content
    h3 details / summary
    details
      summary More info
      p Additional information
      ul
        li Point 1
        li Point 2
    h1 Grouping content
    p 
      ' Lorem ipsum dolor sit amet, consectetuer adipiscing elit. Aenean commodo ligula eget dolor. 
        Aenean massa. Cum sociis natoque penatibus et m. 
    h3 pre
    pre
      ' Lorem ipsum dolor sit amet, consectetuer adipiscing elit. Aenean commodo ligula eget dolor. 
        Aenean massa. Cum sociis natoque penatibus et m. 
    pre
      code = '<html> <head> </head> <body> <div class="main"> <div> </body> </html>'
    h3 blockquote
    blockquote
      p = 'Some sort of famous witty quote marked up with a <blockquote> and a child <p> element.'
    blockquote =  'Even better philosophical quote marked up with just a <blockquote> element.'
    h3 ordered list
    ol
      li list item 1
      li
        | list item 1 
        ol
          li list item 2
          li
            | list item 2 
            ol
              li list item 3
              li list item 3
          li list item 2
          li list item 2
      li list item 1
      li list item 1
    h3 unordered list
    ul
      li list item 1
      li 
        | list item 1 
        ul
          li list item 2
          li 
            | list item 2 
            ul
              li list item 3
              li list item 3
          li list item 2
          li list item 2
      li list item 1
      li list item 1
    h3 description list
    dl
      dt Description name
      dd Description value
      dt Description name
      dd Description value
      dd Description value
      dt Description name
      dt Description name
      dd Description value
    h3 figure
    figure
      img src="http://lorempixel.com/400/200" alt=""
      figcaption Figcaption content
    h1 Tabular data
    table
      caption Jimi Hendrix - albums
      thead
        tr
          th Album
          th Year
          th Price
      tfoot
        tr
          th Album
          th Year
          th Price
      tbody
        tr
          td Are You Experienced
          td 1967
          td $10.00
        tr
          td Axis Bold as Love
          td 1967
          td $12.00
        tr
          td Electric Ladyland
          td 1968
          td $10.00
        tr
          td Band of Gypsys
          td 1970
          td $12.00
    h1 Forms
    form
      fieldset
        legend Inputs as descendents of labels (form legend). This doubles up as a long legend that can test word wrapping.
        p
          label
            | Text input 
            input type="text" value="default value that goes on and on without stopping or punctuation"
        p
          label
            | Email input 
            input type="email"
        p
          label
            | Search input 
            input type="search"
        p
          label
            | Tel input 
            input type="tel"
        p
          label
            | URL input 
            input type="url" placeholder="http://"
        p
          label
            | Password input 
            input type="password" value="password"
        p
          label
            | File input 
            input type="file"
        p
          label
            | Radio input 
            input type="radio" name="rad"
        p
          label
            | Checkbox input 
            input type="checkbox"
        p
          label
            input type="radio" name="rad"
            |  Radio input
        p
          label
            input type="checkbox"
            |  Checkbox input
        p
          label
            | Select field 
            select
              option Option 01
              option Option 02
        p
          label
            | Textarea 
            textarea cols="30" rows="5" Textarea text
      fieldset
        legend Inputs as siblings of labels
        p
          label for="ic" Color input
          input#ic type="color" value="#000000"
        p
          label for="in" Number input
          input#in type="number" min="0" max="10" value="5"
        p
          label for="ir" Range input
          input#ir type="range" value="10"
        p
          label for="idd" Date input
          input#idd type="date" value="1970-01-01"
        p
          label for="idm" Month input
          input#idm type="month" value="1970-01"
        p
          label for="idw" Week input
          input#idw type="week" value="1970-W01"
        p
          label for="idt" Datetime input
          input#idt type="datetime" value="1970-01-01T00:00:00Z"
        p
          label for="idtl" Datetime-local input
          input#idtl type="datetime-local" value="1970-01-01T00:00"
        p
          label for="irb" Radio input
          input#irb type="radio" name="rad"
        p
          label for="icb" Checkbox input
          input#icb type="checkbox"
        p
          input#irb2 type="radio" name="rad"
          label for="irb2" Radio input
        p
          input#icb2 type="checkbox"
          label for="icb2" Checkbox input
        p
          label for="s" Select field
          select#s
            option Option 01
            option Option 02
        p
          label for="t" Textarea
          textarea#t cols="30" rows="5" Textarea text
      fieldset
        legend Clickable inputs and buttons
        p: input type="image" src="http://lorempixel.com/90/24" alt="Image (input)"
        p: input type="reset" value="Reset (input)"
        p: input type="button" value="Button (input)"
        p: input type="submit" value="Submit (input)"
        p: input type="submit" value="Disabled (input)" disabled=true
        p: button type="reset" Reset (button)
        p: button type="button" Button (button)
        p: button type="submit" Submit (button)
        p: button type="submit" disabled=true Disabled (button)
      fieldset#boxsize
        legend box-sizing tests
        div: input type="text" value="text"
        div: input type="email" value="email"
        div: input type="search" value="search"
        div: input type="url" value="http://example.com"
        div: input type="password" value="password"
        div: input type="color" value="#000000"
        div: input type="number" value="5"
        div: input type="range" value="10"
        div: input type="date" value="1970-01-01"
        div: input type="month" value="1970-01"
        div: input type="week" value="1970-W01"
        div: input type="datetime" value="1970-01-01T00:00:00Z"
        div: input type="datetime-local" value="1970-01-01T00:00"
        div: input type="radio"
        div: input type="checkbox"
        div
          select
            option Option 01
            option Option 02
        div: textarea cols="30" rows="5" Textarea text
        div: input type="image" src="http://lorempixel.com/90/24" alt="Image (input)"
        div: input type="reset" value="Reset (input)"
        div: input type="button" value="Button (input)"
        div: input type="submit" value="Submit (input)"
        div: button type="reset" Reset (button)
        div: button type="button" Button (button)
        div: button type="submit"
SLIM

route "get 'frontend/:template' => 'frontend#show', as: :frontend_template unless Rails.env.production?"
route "get 'frontend'           => 'frontend#show', defaults: { template: 'index' } unless Rails.env.production?"

# ============================================================================
# Active Admin
# ============================================================================

if has_active_admin
  gem 'activeadmin', github: 'gregbell/active_admin'
  run 'bundle'
  generate 'active_admin:install'

  File.rename 'app/assets/javascripts/active_admin.js.coffee', 'app/assets/javascripts/active_admin.coffee'
  gsub_file 'app/assets/stylesheets/active_admin.css.scss', ';', ''
  File.rename 'app/assets/stylesheets/active_admin.css.scss', 'app/assets/stylesheets/active_admin.sass'

  inject_into_file 'config/environments/production.rb', after: "  config.assets.precompile += %w(\n" do <<-'RUBY'
    active_admin.js
    active_admin.css
  RUBY
  end

  inject_into_file 'config/initializers/active_admin.rb', after: "ActiveAdmin.setup do |config|\n" do <<-'RUBY'
  config.before_filter :set_locale
  RUBY
  end

  file 'config/locales/active_admin.en.yml', <<-'FILE'
en:
  active_admin:
    dashboard_welcome:
      welcome: 'Welcome to the Admin Panel.'
      call_to_action: 'Use the navigation menu to edit this application.'
  FILE

  if is_pt_BR
    download 'https://gist.github.com/cerdiogenes/6503790/raw/6c30f6bace4767823807c211544bb7462def72cc/Rails+I18n%3A+devise.pt-BR.yml',
             'config/locales/devise.pt-BR.yml'

    file 'config/locales/active_admin.pt-BR.yml', <<-'FILE'
pt-BR:
  active_admin:
    dashboard_welcome:
      welcome: 'Bem vindo ao Painel de Administração.'
      call_to_action: 'Utilize o menu de navegação para editar esta aplicação.'
    comments:
      author_id: Id do autor
      author_type: Tipo do autor
      resource_id: Id do recurso
      resource_type: Tipo do recurso
      namespace: Namespace
      body: Mensagem
      resource: Recurso
      author: Autor
      created_at: Criado em
      updated_at: Atualizado em
  activerecord:
    models:
      admin_user: Administrador(es)
      comment: Comentário(s)
    attributes:
      admin_user:
        email: Email
        password: Senha
        encrypted_password: Senha criptografada
        password_confirmation: Confirmação da senha
        reset_password_token: Token de reset de senha
        reset_password_sent_at: Reset de senha enviado em
        remember_created_at: Lembre-se de mim criado em
        sign_in_count: Número de logins
        current_sign_in_at: Login atual em
        last_sign_in_at: Login anterior em
        current_sign_in_ip: IP registrado atual
        last_sign_in_ip: IP registrado anterior
        created_at: Criado em
        updated_at: Atualizado em
    FILE
  end

end

# ============================================================================
# Devise
# ============================================================================

if has_devise

  generate 'devise:views'
  generate 'devise user'

  gsub_file 'config/initializers/filter_parameter_logging.rb', 
            '[:password]',
            '[:password, :password_confirmation]'

  if has_active_admin
    file 'app/admin/user.rb', <<-'RUBY'
ActiveAdmin.register User do
  index do
    column :email
    column :current_sign_in_at
    column :last_sign_in_at
    column :sign_in_count
    default_actions
  end

  filter :email

  form do |f|
    f.inputs do
      f.input :email
      f.input :password
      f.input :password_confirmation
    end
    f.actions
  end

  controller do
    def permitted_params
      params.permit user: [:email, :password, :password_confirmation]
    end
  end
end
    RUBY

    if is_pt_BR
      file 'config/locales/user_model.pt-BR.yml', <<-'YML'
pt-BR:
  activerecord:
    models:
      user: Usuário(s)
    attributes:
      user:
        email: Email
        password: Senha
        encrypted_password: Senha criptografada
        password_confirmation: Confirmação da senha
        reset_password_token: Token de reset de senha
        reset_password_sent_at: Reset de senha enviado em
        remember_created_at: Lembre-se de mim criado em
        sign_in_count: Número de logins
        current_sign_in_at: Login atual em
        last_sign_in_at: Login anterior em
        current_sign_in_ip: IP registrado atual
        last_sign_in_ip: IP registrado anterior
        created_at: Criado em
        updated_at: Atualizado em
      YML
    end
  else
    gem 'devise'
    generate 'devise:install'

    if is_pt_BR
      download 'https://gist.github.com/cerdiogenes/6503790/raw/6c30f6bace4767823807c211544bb7462def72cc/Rails+I18n%3A+devise.pt-BR.yml',
               'config/locales/devise.pt-BR.yml'
    end
  end

  inject_into_file 'app/controllers/application_controller.rb', after: "ActionController::Base\n" do <<-'RUBY'
  after_filter :store_location
  RUBY
  end

  inject_into_file 'app/controllers/application_controller.rb', after: "protected\n" do <<-'RUBY'

  def store_location
    devise_locations = [ new_user_session_path,
                         destroy_user_session_path,
                         new_user_registration_path,
                         user_password_path ]

    if (!devise_locations.include?(request.fullpath) && !request.xhr?)
      session[:user_return_to] = request.fullpath
    end

    session[:user_return_to] = root_path if session[:user_return_to].blank?
  end

  def after_sign_out_path_for(resource_or_scope)
    request.referrer
  end

  def only_for_signed_in_users
    redirect_to new_user_registration_url unless user_signed_in?
  end

  RUBY
  end
end

# ============================================================================
# Formtastic
# ============================================================================

if has_formtastic
  gem 'formtastic'
  generate 'formtastic:install'
end

# ============================================================================
# rvm, ruby 2.0
# ============================================================================

inject_into_file 'Gemfile', after: "source 'https://rubygems.org'\n" do <<RUBY
ruby '2.0.0'
RUBY
end

file '.ruby-version', <<FIN
ruby-2.0.0-p247
FIN

# ============================================================================
# Heroku Wakeup
# ============================================================================

gem 'rufus-scheduler'

initializer 'heroku_wakeup.rb', <<-'RUBY'
if ENV['HEROKU_WAKEUP'] == 'true'
  require 'rufus/scheduler'
  scheduler = Rufus::Scheduler.new

  scheduler.every '10m' do
    require "net/http"
    require "uri"
    url = "http://#{ENV['APP_HOSTNAME']}"
    Net::HTTP.get_response(URI.parse(url))
  end
end
RUBY

# ============================================================================
# Heroku Deflate
# ============================================================================

gem 'heroku_rails_deflate', group: :production
gem 'heroku_rails_deflate', group: :staging

application(nil, env: :production) do <<-'RUBY'

  config.static_cache_control = "public, max-age=31536000"
RUBY
end

# ============================================================================
# Heroku
# ============================================================================

gem 'rails_12factor', group: :production
gem 'rails_12factor', group: :staging

gsub_file 'config/environments/production.rb',
          'config.serve_static_assets = false',
          'config.serve_static_assets = true'

gsub_file 'config/environments/production.rb',
          '# config.assets.css_compressor = :sass',
          'config.assets.css_compressor = :sass'

gsub_file 'config/environments/production.rb',
          'config.assets.compile = false',
          'config.assets.compile = true'

# ============================================================================
# Lograge
# ============================================================================

gem 'lograge'

application(nil, env: :production) do <<-'RUBY'

  config.lograge.enabled = true
RUBY
end

# ============================================================================
# Bullet
# ============================================================================

gem 'bullet', group: :development

application(nil, env: :development) do <<-'RUBY'

  config.after_initialize do
    Bullet.enable = true
    Bullet.alert = true
    Bullet.console = true
    Bullet.rails_logger = true
  end
RUBY
end

# ============================================================================
# Better Errors
# ============================================================================

gem 'better_errors', group: :development
gem 'binding_of_caller', group: :development

# ============================================================================
# New Relic
# ============================================================================

gem 'newrelic_rpm', group: :production
gem 'newrelic_rpm', group: :staging

download 'https://gist.github.com/rwdaigle/2253296/raw/newrelic.yml', 'config'

# ============================================================================
# Sentry
# ============================================================================

gem 'sentry-raven', group: :production
gem 'sentry-raven', group: :staging

initializer 'sentry.rb', <<-'RUBY'
if Rails.env.production? or Rails.env.staging?
  Raven.configure do |config|
    config.current_environment = ENV['RAILS_ENV']
  end
end
RUBY

# ============================================================================
# Rack::Cache && Memcache via Memcachier
# ============================================================================

gem "rack-cache"
gem "dalli"
gem "kgio"
gem "memcachier", group: :production
gem "memcachier", group: :staging

application(nil, env: :production) do <<-'RUBY'

  config.cache_store = :mem_cache_store, ENV["MEMCACHIER_SERVERS"],
                       { username: ENV["MEMCACHIER_USERNAME"],
                         password: ENV["MEMCACHIER_PASSWORD"]}

  client = Dalli::Client.new(ENV["MEMCACHIER_SERVERS"], value_max_bytes: 10485760)

  config.action_dispatch.rack_cache = {
    metastore: client,
    entitystore: client,
    allow_reload: false,
    verbose: false
  }
RUBY
end

# ============================================================================
# Postgres
# ============================================================================

gem 'pg'

gsub_file 'Gemfile', "gem 'sqlite3'", "# gem 'sqlite3'"
gsub_file 'config/database.yml', /^(?!#)/, '#'

append_file 'config/database.yml', <<YML
development:
  adapter: postgresql
  encoding: unicode
  database: #{database_prefix}_development
  username: #{database_username}
  password: #{database_password}
  pool: 5
  timeout: 5000

production:
  adapter: postgresql
  encoding: unicode
  database: #{database_prefix}_production
  username: #{database_username}
  password: #{database_password}
  pool: 5
  timeout: 5000

test: &test
  adapter: postgresql
  encoding: unicode
  database: #{database_prefix}_test
  username: #{database_username}
  password: #{database_password}
  pool: 5
  timeout: 5000

YML

rake 'db:drop'
rake 'db:create'
rake 'db:migrate'

# ============================================================================
# License
# ============================================================================

if is_free_software

  file 'LICENSE', <<-'FILE'
DUAL LICENSE: GPL3 and MIT


The GNU Public License, Version 3 (GPL3)

Copyright (c) TEAM_NAME

This program is free software: you can redistribute it and/or modify it under 
the terms of the GNU General Public License as published by the 
Free Software Foundation, either version 3 of the License, or (at your option) 
any later version.

This program is distributed in the hope that it will be useful, but 
WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or 
FITNESS FOR A PARTICULAR PURPOSE.  
See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with 
this program.  If not, see <http://www.gnu.org/licenses/>.


The MIT License (MIT)

Copyright (c) TEAM_NAME

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
  FILE

gsub_file 'LICENSE', 'TEAM_NAME', team_name

else

  file 'LICENSE', <<-'FILE'
1. Preamble: This Agreement, signed on LICENSE_DATE [hereinafter: Effective Date]
   governs the relationship between LICENSE_LICENSEE, (hereinafter: Licensee) 
   and TEAM_NAME (Hereinafter: Licensor). 
   This Agreement sets the terms, rights, restrictions and obligations on using 
   SOFTWARE_NAME (hereinafter: The Software) created and owned by 
   Licensor, as detailed herein 
2. License Grant: Licensor hereby grants Licensee a Sublicensable, 
   Non-assignable & non-transferable, Commercial, Royalty free, Including 
   the rights to create but not distribute derivative works, Non-exclusive 
   license, all with accordance with the terms set forth and other legal 
   restrictions set forth in 3rd party software used while running Software.
   2.1. Limited: Licensee may use Software for the purpose of:
        2.1.1. Running Software on Licensee’s Website[s] and Server[s];
        2.1.2. Allowing 3rd Parties to run Software on Licensee’s Website[s] 
               and Server[s];
        2.1.3. Publishing Software’s output to Licensee and 3rd Parties;
        2.1.4. Distribute verbatim copies of Software’s output 
               (including compiled binaries);
        2.1.5. Modify Software to suit Licensee’s needs and specifications.
   2.2. Binary Restricted: Licensee may sublicense Software as a part of a 
        larger work containing more than Software, distributed solely in 
        Object or Binary form under a personal, non-sublicensable, 
        limited license.
        Such redistribution shall be limited to codebases.
   2.3. Non Assignable & Non-Transferable: Licensee may not assign or transfer 
        his rights and duties under this license.
   2.4. Commercial, Royalty Free: Licensee may use Software for any purpose, 
        including paid-services, without any royalties
   2.5. Including the Right to Create Derivative Works: Licensee may create 
        derivative works based on Software, including amending Software’s source
        code, modifying it, integrating it into a larger work or removing 
        portions of Software, as long as no distribution of the derivative 
        works is made
   2.6. With Attribution Requirements﻿: 
        Link back to you from a site running the software.
3. Term & Termination: The Term of this license shall be until terminated. 
   Licensor may terminate this Agreement, including Licensee’s license 
   in the case where Licensee:
   3.1. became insolvent or otherwise entered into any liquidation process; or
   3.2. exported The Software to any jurisdiction where licensor may not enforce
        his rights under this agreements in; or
   3.3. Licenee was in breach of any of this license's terms and conditions and 
        such breach was not cured, immediately upon notification; or
   3.4. Licensee in breach of any of the terms of clause 2 to this license; or
   3.5. Licensee otherwise entered into any arrangement which caused Licensor to 
        be unable to enforce his rights under this License.
4. Payment: In consideration of the License granted under clause 2, Licensee 
   shall pay Licensor a fee, via Credit-Card, PayPal or any other mean which 
   Licensor may deem adequate. 
   Failure to perform payment shall construe as material breach 
   of this Agreement.
5. Upgrades, Updates and Fixes: Licensor may provide Licensee, from time to time, 
   with Upgrades, Updates or Fixes, as detailed herein and according to his 
   sole discretion. Licensee hereby warrants to keep The Software up-to-date 
   and install all relevant updates and fixes, and may, at his sole discretion, 
   purchase upgrades, according to the rates set by Licensor. 
   Licensor shall provide any update or Fix free of charge; however, nothing in 
   this Agreement shall require Licensor to provide Updates or Fixes.
   5.1. Upgrades: for the purpose of this license, an Upgrade shall be a material
        amendment in The Software, which contains new features and or major 
        performance improvements and shall be marked as a new version number.
        For example, should Licensee purchase The Software under version 1.X.X, 
        an upgrade shall commence under number 2.0.0.
   5.2. Updates: for the purpose of this license, an update shall be a minor 
        amendment in The Software, which may contain new features or minor 
        improvements and shall be marked as a new sub-version number. 
        For example, should Licensee purchase The Software under version 1.1.X, 
        an upgrade shall commence under number 1.2.0.
   5.3. Fix: for the purpose of this license, a fix shall be a minor amendment in 
        The Software, intended to remove bugs or alter minor features which 
        impair the The Software's functionality. A fix shall be marked as a new 
        sub-sub-version number. For example, should Licensee purchase Software 
        under version 1.1.1, an upgrade shall commence under number 1.1.2.
6. Support: Software is provided under an AS-IS basis and without any support, 
   updates or maintenance. Nothing in this Agreement shall require Licensor to 
   provide Licensee with support or fixes to any bug, failure, mis-performance 
   or other defect in The Software.
   6.1. Bug Notification: Licensee may provide Licensor of details regarding any 
        bug, defect or failure in The Software promptly and with no delay from 
        such event; Licensee shall comply with Licensor's request for information
        regarding bugs, defects or failures and furnish him with information, 
        screenshots and try to reproduce such bugs, defects or failures.
   6.2. Feature Request: Licensee may request additional features in Software, 
        provided, however, that (i) Licesee shall waive any claim or right in 
        such feature should feature be developed by Licensor; (ii) Licensee shall
        be prohibited from developing the feature, or disclose such feature 
        request, or feature, to any 3rd party directly competing with Licensor or
        any 3rd party which may be, following the development of such feature, in
        direct competition with Licensor; (iii) Licensee warrants that feature 
        does not infringe any 3rd party patent, trademark, trade-secret or any 
        other intellectual property right; and (iv) Licensee developed, 
        envisioned or created the feature solely by himself.
7. Liability:  To the extent permitted under Law, The Software is provided under 
   an AS-IS basis. Licensor shall never, and without any limit, be liable for 
   any damage, cost, expense or any other payment incurred by Licesee as a result 
   of Software’s actions, failure, bugs and/or any other interaction between 
   The Software  and Licesee’s end-equipment, computers, other software or any 
   3rd party, end-equipment, computer or services.  Moreover, Licensor shall  
   never be liable for any defect in source code written by Licensee when relying 
   on The Software or using The Software’s source code.
8. Warranty:  
   8.1. Intellectual Property: Licensor hereby warrants that The Software does 
        not violate or infringe any 3rd party claims in regards to intellectual 
        property, patents and/or trademarks and that to the best of its knowledge
        no legal action has been taken against it for any infringement or 
        violation of any 3rd party intellectual property rights.
   8.2. No-Warranty: The Software is provided without any warranty; Licensor 
        hereby disclaims any warranty that The Software shall be error free, 
        without defects or code which may cause damage to Licensee’s computers or
        to Licensee, and that Software shall be functional. Licensee shall be 
        solely liable to any damage, defect or loss incurred as a result of 
        operating software and undertake the risks contained in running 
        The Software on License’s Server[s] and Website[s].
   8.3. Prior Inspection: Licensee hereby states that he inspected The Software 
        thoroughly and found it satisfactory and adequate to his needs, that it 
        does not interfere with his regular operation and that it does meet the 
        standards and scope of his computer systems and architecture. Licensee 
        found that The Software interacts with his development, website and 
        server environment and that it does not infringe any of End User License
        Agreement of any software Licensee may use in performing his services. 
        Licensee hereby waives any claims regarding The Software's 
        incompatibility, performance, results and features, and warrants that he 
        inspected the The Software.
9. No Refunds: Licensee warrants that he inspected The Software according to 
   clause 7(c) and that it is adequate to his needs. Accordingly, as The Software
   is intangible goods, Licensee shall not be, ever, entitled to any refund, 
   rebate, compensation or restitution for any reason whatsoever, even if 
   The Software contains material flaws.
10. Indemnification: Licensee hereby warrants to hold Licensor harmless and 
    indemnify Licensor for any lawsuit brought against it in regards to 
    Licensee’s use of The Software in means that violate, breach or otherwise 
    circumvent this license, Licensor's intellectual property rights or 
    Licensor's title in The Software. Licensor shall promptly notify Licensee
    in case of such legal action and request Licensee’s consent prior to any 
    settlement in relation to such lawsuit or claim.
11. Governing Law, Jurisdiction: Licensee hereby agrees not to initiate 
    class-action lawsuits against Licensor in relation to this license and 
    to compensate Licensor for any legal fees, cost or attorney fees should 
    any claim brought by Licensee against Licensor be denied, in part or in full.
  FILE

  gsub_file 'LICENSE', 'LICENSE_DATE', license_date
  gsub_file 'LICENSE', 'LICENSE_LICENSEE', license_licensee
  gsub_file 'LICENSE', 'TEAM_NAME', team_name
  gsub_file 'LICENSE', 'SOFTWARE_NAME', license_software_name

end

# ============================================================================
# Git
# ============================================================================

append_file '.gitignore', <<'FILE'
*.gem
*.rbc
.config
coverage
InstalledFiles
lib/bundler/man
pkg
rdoc
spec/reports
test/tmp
test/version_tmp

# YARD artifacts
.yardoc
_yardoc
doc/

# Sublime Text files
*.sublime-project
*.sublime-workspace

# Mac DS_Store
**/.DS_Store
.DS_Store

# PSD Files
*.psd

# OS generated files
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
ehthumbs.db
Thumbs.db
FILE

git :init
git add: "."
git commit: "-am 'Genesis.'"

# ============================================================================
# Bootstrap Heroku environment
# ============================================================================

if bootstrap_staging

  file 'config/environments/staging.rb', File.read('config/environments/production.rb')

  append_file 'config/database.yml', <<-YML
staging:
  adapter: postgresql
  encoding: unicode
  database: #{database_prefix}_staging
  username: #{database_username}
  password: #{database_password}
  pool: 5
  timeout: 5000
  YML

  git add: "."
  git commit: "-am 'Creating staging environment.'"

  bootstrap_heroku_environment 'staging', staging_options

  push_to_heroku 'staging', staging_options
end

if bootstrap_production
  bootstrap_heroku_environment 'production', production_options

  push_to_heroku 'production', production_options
end

# ============================================================================
# Files to be commited only a first version
# ============================================================================

append_file '.gitignore', <<'FILE'

# Procfile-dev
Procfile-dev

# Rails database.yml
config/database.yml
FILE

git add: "."
git commit: "-am 'Ignoring database.yml and Procfile-dev, leaving default commited.'"
