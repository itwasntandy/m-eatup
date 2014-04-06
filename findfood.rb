require 'sinatra'
require 'cgi'
require 'json'
require 'geokit'
require 'yelpster'

YELP_YWSID = "***REMOVED***"
 
YELP_CONSUMER_KEY = "***REMOVED***"
YELP_CONSUMER_SECRET = "***REMOVED***"
YELP_TOKEN = "***REMOVED***"
YELP_TOKEN_SECRET = "***REMOVED***"
 
Yelp.configure(:yws_id => YELP_YWSID,
               :consumer_key => YELP_CONSUMER_KEY,
               :consumer_secret => YELP_CONSUMER_SECRET,
               :token => YELP_TOKEN,
               :token_secret => YELP_TOKEN_SECRET)

def toRadians(n)
  r = n * (Math::PI / 180)
  return r
end
  
def toDegrees(n)
  d = n * (180 / Math::PI)
  return d
end


get '/lookup*' do
  content_type :json
  {"params" => CGI::parse(request.query_string)}.to_json
#  "you asked for #{params} is that what you meant?"
  
  first_addr = Geokit::Geocoders::GoogleGeocoder.geocode(params.fetch("address1"))
  second_addr = Geokit::Geocoders::GoogleGeocoder.geocode(params.fetch("address2"))
  foodtype = params.fetch("type")

  lat1 = toRadians(first_addr.lat)
  lat2 = toRadians(second_addr.lat)
  lng1 = toRadians(first_addr.lng)
  lng2 = toRadians(second_addr.lng)

  dLon = lng2 - lng1

  Bx = Math.cos(lat2) * Math.cos(dLon)
  By = Math.cos(lat2) * Math.sin(dLon)

  LatMid = toDegrees(Math.atan2((Math.sin(lat1) + Math.sin(lat2)), Math.sqrt(( Math.cos(lat1)+Bx)**2 + By**2)))
  LongMid = toDegrees(lng1 + Math.atan2(By, Math.cos(lat1) + Bx))

  client = Yelp::Client.new
  request = Yelp::V2::Search::Request::GeoPoint.new(
              :term => foodtype,
              :latitude => LatMid,
              :longitude => LongMid,
              :limit => 1,
              :category => "food"
               )
 
  response = client.search(request)
  "the best restaurant to go to is #{response.fetch("businesses")[0].fetch("name")} and its address is #{response.fetch("businesses")[0].                 fetch("location").fetch("address")[0]}  #{response.fetch("businesses")[0].fetch("location").fetch("postal_code")}"

end
