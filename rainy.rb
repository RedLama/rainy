require 'sqlite3'
require 'awesome_print'

require 'net/http'
require 'json'

#database file
GC_SQLITE_FILE = 'GC_FR.sqlite'

begin
  # Opening sqlite Database
  sql_db = SQLite3::Database.new(GC_SQLITE_FILE)

  sql_db.execute('SELECT code_departement, code_commune FROM french_geographic_codes WHERE code_postal = ?', "78180") do |row|
    uri = URI("http://www.meteofrance.com/mf3-rpc-portlet/rest/pluie/#{row[0] + row[1] + '0'}")
    res = Net::HTTP.get_response(uri)
    ap JSON.parse(res.body) if res.is_a?(Net::HTTPSuccess)
  end
rescue SQLite3::Exception => e
  puts "Exception occurred"
  puts e
ensure
  #Disconnecting Databse
  sql_db.close if sql_db
end
