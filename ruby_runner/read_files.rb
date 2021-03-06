require "zlib"
require "logger"
require 'yaml'

require_relative "my_redis.rb"
require_relative "my_pg.rb"
require_relative "my_parser.rb"

CONFIG = YAML.load_file('/usr/src/myapp/config.yml')

@logger = Logger.new(STDOUT)

def main
  redis = MyRedis.new(CONFIG["redis_host"], CONFIG["redis_db"], CONFIG["redis_password"], CONFIG["redis_port"])
  @redis = redis.connect
  @logger.info @redis.ping

  pg = MyPG.new(CONFIG["pg_host"], CONFIG["pg_dbname"], CONFIG["pg_user"], CONFIG["pg_password"], CONFIG["pg_port"])
  @pg = pg.connect
  @logger.info @pg

  paths = Dir[CONFIG["log_path"]].sort
  paths.each do |path|
    read_file(path)
  end

  @pg.close
  @redis.quit
end

def read_file(path)
  infile = open(path)
  gz = Zlib::GzipReader.new(infile)

  file = File.basename(path, ".*")
  logger = Logger.new("#{file}.log")

  gz.each_line do |line|
    read_line(line, @logger)
  end
end

def read_line(line, logger)
  regex = /^(?<ltime>[^ ]+) (?<host>[^ ]+) (?<process>[^:]+): (?<message>((?<key>[^ :]+)[ :])?.*)$/
  data = line.match(regex)

  include_regex = /postfix/
  return if !data["process"].match(include_regex)

  exclude_regex = /postfix\/anvil|postfix\/scache/
  return if data["process"].match(exclude_regex)

  exclude_regex = /NOQUEUE|Trusted|Untrusted|warning|connect|Anonymous|lost|SSL_accept|message|fatal|timeout|too|improper|Host/
  return if data["key"].match(exclude_regex)

  process_line(line, data, logger)
end

def process_line(line, data, logger)
  parser = MyParser.new(logger, @redis, @pg, CONFIG["pg_schema"])
  parser.process(line, data)
end

main
