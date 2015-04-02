#!/usr/bin/env ruby
#encoding: utf-8
require 'sqlite3'
require 'awesome_print'
require 'terminal-notifier'

require 'net/http'
require 'json'
require 'optparse'

#database file
GC_SQLITE_FILE = 'GC_FR.sqlite'

RAIN_LEVEL = { 2 => "pluie faible",
  3 => "pluie modérée",
  4 => "forte pluie"}

URL_SERVICE = "http://www.meteofrance.com/mf3-rpc-portlet/rest/pluie/%s0"

def humanize_result(result)
  first = result.shift
  sentence = first ?
    first[:beginning] == 0 ? "Cette #{first[:rain_level]} " + ( first[:duration] == 60 ? "ne s'arretera pas tout de suite" : "s'arretera dans #{first[:duration]} minutes" ) :
    "Il y aura dans #{first[:beginning]} minutes une #{first[:rain_level]} pendant #{first[:duration]} minutes" : ""

  result.each do |state|
    beginning = state[:beginning] - first[:beginning] + first[:duration]
    sentence << (beginning == 0 ? "qui evoluera en " : ", suivi #{beginning} minutes plus tard par une ")
    sentence << "#{state[:rain_level]} pendant #{state[:duration]} minutes"
    first = state
  end

  sentence.empty? ? "Pas de pluie à l'horizon": sentence
end

def extract_information(data)
  data["dataCadran"].to_enum.with_index.map do |d, index|
    d['index'] = index
    d
  end.chunk { |d| d["niveauPluie"] }.map { |level, blocs|
    { beginning: blocs.first["index"] * 5, rain_level: RAIN_LEVEL[level], duration: blocs.count * 5 } if level > 1
  }.compact
end

def parse_information(data)
  if !data["isAvailable"]
    "Information non disponible pour votre département"
  elsif !data["hasData"]
    "Pas de donnée, réessayer plus tard"
  else
    humanize_result(extract_information( data ))
  end
end

if __FILE__ == $0
  options = { all: false, display: false, notification: false }
  OptionParser.new do |opts|
    opts.banner = "is it going to rain ?"
    opts.separator ""
    opts.separator "Usage: rainy [options] -z ZIPCODE | -i INSEE_CODE"
    opts.separator ""
    opts.separator "Options:"

    opts.on("-a", "--all", "Display forecast for all insee code of a zip code") { options[:all] = true }

    opts.on("-z", "--zipcode ZIPCODE", "Search by zipcode (5 digits ex:78180). Warning a zipcode is less precise than an insee_code, you may have to choose between different cities") do |zipcode|
      STDERR.puts("Your zipcode must have 5 digits like '78180'") and exit(1) if zipcode.to_s.length != 5
      options[:zipcode] = zipcode
    end

    opts.on("-d", "--display", "Show insee code equivalent for a zipcode") { options[:display] = true }

    opts.on("-n", "--notification", "Display forecast in a notification instead of console") { options[:notification] = true }

    opts.on("-i", "--inseecode", "Search by insee code (5 digits ex:78634). This options deactive all others options") do |insee|
      STDERR.puts("Your insee code must have 5 digits like '78634'") and exit(1) if insee.to_s.length != 5
      options[:insee_code] = insee
    end
  end.parse!

  display_goc = "%s (Code Insee: %s)"

  begin
    # Opening sqlite Database
    sql_db = SQLite3::Database.new(GC_SQLITE_FILE)

    results = sql_db.execute('SELECT code_departement, code_commune, article_riche, nom_riche FROM french_geographic_codes WHERE code_postal = ?', options[:zipcode])

    if options[:insee]
      results = [options[:insee][0..1], options[:insee][2..-1]]
    elsif options[:zipcode] && !options[:all] && results.count > 1
      results.each_with_index { |result, index| puts "#{index + 1}) " << sprintf( display_goc, result[2] << result[3], result[0] + result[1] ) }
      results = [ begin
        choice = STDIN.gets.chomp.to_i
        (1..results.count).include?(choice) ? results[choice - 1] : raise
      rescue
        puts "Bad value : #{choice} is not between 0 and #{results.count}"
        retry
      end ]
    end

    results.each { |result| printf( display_goc + "\n", result[2] << result[3], result[0] + result[1] ) } and exit(0) if options[:display]

    results.each do |result|
      uri = URI(sprintf(URL_SERVICE, result[0] + result[1]))
      res = Net::HTTP.get_response(uri)
      # ap JSON.parse(res.body)
      if options[:notification]
        TerminalNotifier.notify(parse_information(JSON.parse(res.body)), title: "Meteo pour #{result[2]}#{result[3]}")
      else
        puts "Meteo pour #{result[2]}#{result[3]} (Code Insee: #{result[0] + result[1]})"
        puts parse_information(JSON.parse(res.body))
      end if res.is_a?(Net::HTTPSuccess)
    end
  rescue SQLite3::Exception => e
    puts "Exception occurred"
    puts e
  ensure
    #Disconnecting Databse
    sql_db.close if sql_db
  end
end
