require 'sinatra'
require 'cgi'
require 'json'
require 'geokit'
require 'yelpster'
require 'uri'

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

def to_radians(n)
  r = n * (Math::PI / 180)
  return r
end
  
def to_degrees(n)
  d = n * (180 / Math::PI)
  return d
end

def find_midpoint(lat1,long1,lat2,long2)
  dlong = long2 - long1
  
  bx = Math.cos(lat2) * Math.cos(dlong)
  by = Math.cos(lat2) * Math.sin(dlong)
 
  latmid = to_degrees(Math.atan2((Math.sin(lat1) + Math.sin(lat2)), Math.sqrt(( Math.cos(lat1)+bx)**2 + by**2)))
  longmid = to_degrees(long1 + Math.atan2(by, Math.cos(lat1) + bx))
  return [latmid, longmid]
end

get '/lookup' do
  content_type :json
  "you asked for #{params} is that what you meant?"
  if !(params.fetch("address1").empty? || params.fetch("address2").empty?)
    "You haven't added valid addresses"
  end
  address1 = URI.unescape(params.fetch("address1"))
  address2 = URI.unescape(params.fetch("address2"))
  #set a default foodtype to indian
  foodtype = "indian"
  first_addr = Geokit::Geocoders::GoogleGeocoder.geocode(address1)
  second_addr = Geokit::Geocoders::GoogleGeocoder.geocode(address2)
  foodtype = URI.unescape(params.fetch("type"))

  lat1 = to_radians(first_addr.lat)
  lat2 = to_radians(second_addr.lat)
  long1 = to_radians(first_addr.lng)
  long2 = to_radians(second_addr.lng)

  midpoint = find_midpoint(lat1,long1,lat2,long2)
  
  client = Yelp::Client.new
  request = Yelp::V2::Search::Request::GeoPoint.new(
              :term => foodtype,
              :latitude => midpoint[0],
              :longitude => midpoint[1],
              :limit => 1,
              :category => "food"
               )
 
  response = client.search(request)
  "the best restaurant to go to is #{response.fetch("businesses")[0].fetch("name")} and its address is #{response.fetch("businesses")[0].                 fetch("location").fetch("address")[0]}  #{response.fetch("businesses")[0].fetch("location").fetch("postal_code")}"

end
