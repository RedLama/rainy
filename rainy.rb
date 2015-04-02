#!/usr/bin/env ruby
require 'sqlite3'
require 'awesome_print'

require 'net/http'
require 'json'
require 'optparse'

#database file
GC_SQLITE_FILE = 'GC_FR.sqlite'

RAIN_LEVEL = { 2 => "pluie faible",
  3 => "pluie modérée",
  4 => "forte pluie"}

def humanize_result(result)
  first = result.shift
  sentence = (first["index"] == 0 ?
    "La #{first[:rain_level]} " << first[:duration] == 60 ? "ne s'arretera pas tout de suite" : "s'arretera dans #{first[:duration]} minutes" :
     sprintf("Il y aura dans %d minutes une %s pendant %d minutes", first.values) if first) || ""

  result.each do |state|
    beginning = state[:beginning] - first[:index] + first[:duration]
    sentence << beginning == 0 ? "qui evoluera en " : ", suivi #{beginning} minutes après par une "
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
    puts "Information non disponible pour votre département"
  elsif !data["hasData"]
    puts "Pas de donnée, réessayer plus tard"
  else
    puts humanize_result(extract_information( data ))
  end
end

if __FILE__ == $0
  options = { all: false }
  OptionParser.new do |opts|
    opts.banner = "is it going to rain ?"
    opts.separator ""
    opts.separator "Usage: rainy [options] -z ZIPCODE | -i INSEE_CODE"
    opts.separator ""
    opts.separator "Options:"

    opts.on("-z", "--zipcode ZIPCODE", "Search by zipcode (5 digits ex:78180). Warning a zipcode is less precise than an insee_code, you may have to choose between different cities") do |zipcode|
      STDERR.puts("Your zipcode must have 5 digits like '78180'") and exit(1) if zipcode.to_s.length != 5
      options[:zipcode] = zipcode
    end

  end.parse!

  begin
    # Opening sqlite Database
    sql_db = SQLite3::Database.new(GC_SQLITE_FILE)

    results = sql_db.execute('SELECT code_departement, code_commune, article_riche, nom_riche FROM french_geographic_codes WHERE code_postal = ?', options[:zipcode])
    results.each_with_index { |code, index| puts "#{index + 1}) #{code[2]}#{code[3]} (Code Insee: #{code[0] + code[1]})"}
    result = begin
      choice = STDIN.gets.chomp.to_i
      (1..results.count).include?(choice) ? results[choice - 1] : raise
    rescue
      puts "Bad value : #{choice} is not between 0 and #{result.count}"
      retry
    end
    uri = URI("http://www.meteofrance.com/mf3-rpc-portlet/rest/pluie/#{result[0] + result[1] + '0'}")
    res = Net::HTTP.get_response(uri)
    parse_information(JSON.parse(res.body)) if res.is_a?(Net::HTTPSuccess)
  rescue SQLite3::Exception => e
    puts "Exception occurred"
    puts e
  ensure
    #Disconnecting Databse
    sql_db.close if sql_db
  end
end
