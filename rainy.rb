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
  begin
    # Opening sqlite Database
    sql_db = SQLite3::Database.new(GC_SQLITE_FILE)

    sql_db.execute('SELECT code_departement, code_commune, article_riche, nom_riche FROM french_geographic_codes WHERE code_postal = ?', "78180") do |row|
      uri = URI("http://www.meteofrance.com/mf3-rpc-portlet/rest/pluie/#{row[0] + row[1] + '0'}")
      res = Net::HTTP.get_response(uri)
      parse_information(JSON.parse(res.body)) if res.is_a?(Net::HTTPSuccess)
    end
  rescue SQLite3::Exception => e
    puts "Exception occurred"
    puts e
  ensure
    #Disconnecting Databse
    sql_db.close if sql_db
  end
end
