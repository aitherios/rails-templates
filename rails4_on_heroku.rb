# -*- coding: utf-8 -*-
# ============================================================================
# Unicorn + Foreman
# ============================================================================

gem 'unicorn'
gem 'foreman', group: :development

file 'Procfile', <<FILE
web: bundle exec unicorn -p $PORT -c ./config/unicorn.rb
FILE

file '.env', <<FILE
WEB_CONCURRENCY=1
RACK_ENV=none
RAILS_ENV=development
APP_HOSTNAME=localhost
FILE

file 'config/unicorn.rb', <<RUBY
worker_processes Integer(ENV["WEB_CONCURRENCY"] || 5)
ENV['RAILS_ENV'] == 'development' ? timeout(90) : timeout(15)
preload_app true

before_fork do |server, worker|
  Signal.trap 'TERM' do
    puts 'Unicorn master intercepting TERM and sending myself QUIT instead'
    Process.kill 'QUIT', Process.pid
  end

  ActiveRecord::Base.connection.disconnect! if defined?(ActiveRecord::Base)

  if defined?(Resque) and Rails.env.production?
    Resque.redis.quit
    Rails.logger.info('Disconnected from Redis')
  end
end 

after_fork do |server, worker|
  Signal.trap 'TERM' do
    puts 'Unicorn worker intercepting TERM and doing nothing. Wait for master to send QUIT'
  end

  ActiveRecord::Base.establish_connection if defined?(ActiveRecord::Base)

  if defined?(Resque) and Rails.env.production?
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
# Compass
# ============================================================================

gem 'compass-rails', '~> 2.0.alpha.0'

# ============================================================================
# SMACSS
# ============================================================================

Dir.mkdir 'app/assets/stylesheets/base'
file 'app/assets/stylesheets/base/_all.sass', <<SASS
// ---------------------------------------------------------------------------
//  BASE IMPORTS
// ---------------------------------------------------------------------------
// Styles relevant to the hole application, always.
SASS

Dir.mkdir 'app/assets/stylesheets/layouts'
file 'app/assets/stylesheets/layouts/_all.sass', <<SASS
// ---------------------------------------------------------------------------
//  LAYOUT IMPORTS
// ---------------------------------------------------------------------------
// Styles relevant only to the page layouts.
SASS

Dir.mkdir 'app/assets/stylesheets/modules'
file 'app/assets/stylesheets/modules/_all.sass', <<SASS
// ---------------------------------------------------------------------------
//  MODULE IMPORTS
// ---------------------------------------------------------------------------
// Styles relevant only to visual module components.
SASS

Dir.mkdir 'app/assets/stylesheets/states'
file 'app/assets/stylesheets/states/_all.sass', <<SASS
// ---------------------------------------------------------------------------
//  STATE IMPORTS
// ---------------------------------------------------------------------------
// Styles relevant to state specializations.
SASS

Dir.mkdir 'app/assets/stylesheets/themes'
file 'app/assets/stylesheets/themes/_all.sass', <<SASS
// ---------------------------------------------------------------------------
//  THEME IMPORTS
// ---------------------------------------------------------------------------
// Styles relevant to layout themes.
SASS

File.delete 'app/assets/stylesheets/application.css'
file 'app/assets/stylesheets/application.sass', <<SASS
@import "base/all"
@import "layouts/all"
@import "modules/all"
@import "states/all"
@import "themes/all"
SASS

# ============================================================================
# Slim
# ============================================================================

gem 'slim'

application(nil, env: :development) do <<RUBY
Slim::Engine.set_default_options pretty: true, sort_attrs: false, format: :html5
RUBY
end

application(nil, env: :production) do <<RUBY
Slim::Engine.set_default_options format: :html5
RUBY
end

# ============================================================================
# Pages Controller, Frontend Controller, HTML5Boilerplate Layout
# ============================================================================

File.delete 'app/views/layouts/application.html.erb'

file 'app/views/layouts/application.slim', <<'SLIM'
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
    title #{(content_for?(:title) ? "#{yield :title} — " : "") + 'Title' }
    == render 'layouts/metatags'
    == render 'layouts/favicons'

    == csrf_meta_tags
    == stylesheet_link_tag 'application', media: 'all', 'data-turbolinks-track' => true
    == javascript_include_tag 'application', 'data-turbolinks-track' => true
    /[if lt IE 9]
      == javascript_include_tag 'nwmatcher-1.2.5', 'data-turbolinks-track' => true
      == javascript_include_tag 'selectivizr', 'data-turbolinks-track' => true
      == javascript_include_tag 'html5shiv-printshiv', 'data-turbolinks-track' => true

  body class="#{yield :body_class}"
    == render 'layouts/browser_warning'

    section.page
      == yield
SLIM

file 'app/views/layouts/_metatags.slim', <<'SLIM'
// html metatags
meta charset="utf-8"
meta http-equiv="X-UA-Compatible" content="IE=edge,chrome=1"
meta name="author" content="61bits — http://61bits.com.br"
meta name="description" content="#{content_for?(:description) ? yield(:description) : Rails.application.class.parent_name}"
meta name="viewport" content="user-scalable=no, width=device-width, initial-scale=1.0, maximum-scale=1.0"

// opengraph metatags
meta property="og:image" content="http://#{ENV['APP_HOSTNAME']}/og-image.png"
meta property="og:type" content="website"
meta property="og:url" content="http://#{ENV['APP_HOSTNAME']}"
meta property="og:title" content="#{content_for?(:title) ? yield(:title).to_s + '— ' : ''}#{Rails.application.class.parent_name}"
meta property="og:description" content="#{content_for?(:description) ? yield(:description) : Rails.application.class.parent_name}"
meta property="og:locale" content="pt_BR"
// meta property="fb:admins" content="#admin-id" 

// humans.txt
link rel="author" href="/humans.txt"
SLIM

file 'app/views/layouts/_favicons.slim', <<'SLIM'
== favicon_link_tag '/apple-touch-icon-144x144-precomposed.png', rel: 'apple-touch-icon', \
                                                                 type: 'image/png', \
                                                                 sizes: '144x144'
== favicon_link_tag '/apple-touch-icon-114x114-precomposed.png', rel: 'apple-touch-icon', \
                                                                 type: 'image/png', \
                                                                 sizes: '114x114'
== favicon_link_tag '/apple-touch-icon-72x72-precomposed.png', rel: 'apple-touch-icon', \
                                                               type: 'image/png', \
                                                               sizes: '72x72'
== favicon_link_tag '/apple-touch-icon-57x57-precomposed.png', rel: 'apple-touch-icon', \
                                                               type: 'image/png', \
                                                               sizes: '57x57'
== favicon_link_tag '/favicon.png', type: 'image/png'
== favicon_link_tag '/favicon.ico'
SLIM

file 'app/views/layouts/_browser_warning.slim', <<'SLIM'
/[if lt IE 9]
  p.chromeframe
    == t 'app.lt_ie_9_warning'
SLIM

Dir.mkdir 'app/views/pages'

file 'app/views/pages/index.slim', <<SLIM
h1 pages#index
SLIM

file 'app/controllers/pages_controller.rb', <<RUBY
class PagesController < ApplicationController
  def index; end

  def show
    render params[:template]
  end
end
RUBY

route "root to: 'pages#index'"
route "get ':slug' => 'pages#show', as: :page"

Dir.mkdir 'app/views/frontend'

file 'app/controllers/frontend_controller.rb', <<RUBY
class FrontendController < ApplicationController
  def index
    @entries = Dir.entries(Rails.root.join('app', 'views', 'frontend')) - [".", "..", "index.slim"]
  end

  def show
    render params[:template]
  end
end
RUBY

file 'app/views/frontend/index.slim', <<SLIM
- if @entries.present?
  h1 Frontend Files:
  ul
    - @entries.each do |entry|
      li = link_to entry, frontend_path(entry.gsub(/(.html)?\.\w+$/, ''))
    
h1 Comparison Sheet:

section.page
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

route "get 'frontend/:template' => 'frontend#show'"
route "get 'frontend'           => 'frontend#index'"

# ============================================================================
# Formtastic
# ============================================================================

if yes? ">>> Install Formtastic?"
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
# Licence
# ============================================================================

file 'LICENSE', <<FIN
DUAL LICENSE: GPL3 and MIT


The GNU Public License, Version 3 (GPL3)

Copyright (c) 61bits

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

Copyright (c) 61bits

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
FIN

# ============================================================================
# Postgres
# ============================================================================

gem 'pg'

gsub_file 'Gemfile', "gem 'sqlite3'", "# gem 'sqlite3'"
gsub_file 'config/database.yml', /^(?!#)/, '#'

database_prefix = ask '>>> What is your database prefix?'
database_username = ask '>>> What is your database username?'
database_password = ask '>>> What is your database password?'

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

rake 'db:create:all'
rake 'db:migrate'

# ============================================================================
# Git
# ============================================================================

append_file '.gitignore', <<FILE
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
FILE

git :init
git add: "."
git commit: "-am 'Genesis'"
