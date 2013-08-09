namespace :test do
  task :migrate do
    ActiveRecord::Base.logger = Logger.new(STDOUT)
    ActiveRecord::Migrator.migrate("test/db/migrate/", ENV["VERSION"] ? ENV["VERSION"].to_i : nil)
  end
end
