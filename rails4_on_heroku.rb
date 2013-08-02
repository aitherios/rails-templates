# ============================================================================
# Unicorn + Foreman
# ============================================================================

gem 'unicorn'
gem 'foreman', group: :development

file 'Procfile', <<FIN
web: bundle exec unicorn -p $PORT -c ./config/unicorn.rb
FIN

file '.env', <<FIN
WEB_CONCURRENCY=1
FIN

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
# Git
# ============================================================================

append_file '.gitignore', <<FIN
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
FIN

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
