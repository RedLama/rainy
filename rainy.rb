require 'sqlite3'
require 'awesome_print'

require 'net/http'
require 'json'

#database file
GC_SQLITE_FILE = 'GC_FR.sqlite'

RAIN_LEVEL = { 1 => "Aucune",
  2 => "pluie faible",
  3 => "pluie modérée",
  4 => "forte pluie"}

def extract_information(data)
  data["dataCadran"].to_enum.with_index.map { |d, index|
    d['index'] = index
    d
  }.chunk { |d| d["niveauPluie"] }.map { |level, blocs|
    "Il y aura dans #{blocs.first["index"]} minutes une #{RAIN_LEVEL[level]} pendant #{blocs.count * 5} minutes" if level > 1
  }.compact
end

def display_information(data)
  if !data["isAvailable"]
    p "Information non disponible pour votre département"
  elsif !data["hasData"]
    p "Pas de donnée, réessayer plus tard"
  else
    toto = extract_information data
    ap toto
  end
end

begin
  # Opening sqlite Database
  sql_db = SQLite3::Database.new(GC_SQLITE_FILE)

  sql_db.execute('SELECT code_departement, code_commune, article_riche, nom_riche FROM french_geographic_codes WHERE code_postal = ?', "78180") do |row|
    uri = URI("http://www.meteofrance.com/mf3-rpc-portlet/rest/pluie/#{row[0] + row[1] + '0'}")
    res = Net::HTTP.get_response(uri)
    display_information(JSON.parse(res.body)) if res.is_a?(Net::HTTPSuccess)
  end
rescue SQLite3::Exception => e
  puts "Exception occurred"
  puts e
ensure
  #Disconnecting Databse
  sql_db.close if sql_db
end
