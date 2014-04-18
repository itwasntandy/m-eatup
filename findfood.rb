#This is a simple app to try to find the best place for a group of friends to meet up and eat.
#Normally this would be broken down into a number of classes, but because I'm just sending a gist
#I've left the various methods in the one file and not broken them out.
#The app will take input in the form of a bunch of address[] parameters in a uri query string and 
#food type via the optional type parameter.
#It then calculates an appropriate midpoint through iterating through the inputted addresses
#and looking for the center of the great circle path where each pair intersect
#it then calls out to the Yelp! API to find suitable restaurants near there, and outputs that to the requester.
#To help with debugging and improving quality along the way it logs request parameters and results to a database.
#For now this is a MySQL DB, should there ever be more than just me using this, I'll rethink that decision.
#For now I've wrapped all DB queries in such a way that it is easy to disable it, and any failure with the DB during a request will cause logging ot be disabled
#for the rest of the request
#The other reason for logging the event into the DB, is I would like to use them to allow users to schedule event
#and have others sign up to them. This is a TBD.
#Something akin to Doodle, but taking it much further as the app would chose not only the best date, but also the best location, and a restaurant.
#If I were able to hook it up to the Google Maps Routing API, it could then send out directions to each person, and reminders prior to the event.
#Once all that is done, being able to hook up to the OpenTable API to book a table on the scheduled date for everyone who can make it, at the appropriate restaurant
#would be the icing on the cake.
#In the future it should deal with edge cases better - eg. the midpoint between london and paris is over the sea, so there is no restaurant close to the midpoint.
#Also in the future it would be good to hook up to a routing API, as the geographic midpoint may in some cases take longer to get to then going from point A to point B.
#and this will allow people to specify method of travel too.
#i.e. Andrew is happy to go by foot, car or public transport
#Will is happy to go by foot, bicyle or public transport
#Harry is happy to go by public transport, and walk no more than 10 minutes
require 'sinatra'
require 'cgi'
require 'json'
require 'geokit'
require 'yelpster'
require 'uri'
require 'mysql2'
require 'yaml'

#Decided it would be a good idea to move the config variables out of the main app
#so this is done through reading a yaml file and creating a hash of hashes for this.
#Currently it needs the config file to be named config.yml and for it to be in the same
#directory as the running app.
#The config file needs to contain credentials for all the remote services used.
#You can sign up for a YELP developer account here: http://www.yelp.com/developers
#you can sign up for a MySQL db (from the free tier) with AWS: http://aws.amazon.com/rds/
# database:
#   host: "localhost"
#   user: "username"
#   passwd: "password"
#   dbname: "m_eatup"
# yelp:
#   ywsid: ""
#   consumer_key: ""
#   consumer_secret: ""
#   token: ""
#   token_secret: ""
begin
  approot = File.expand_path(File.dirname(__FILE__))
  rawconfig = File.read(approot + "/config.yml")
  config = YAML.load(rawconfig)
rescue
  raise "Could not load or parse configuration file, unable to continue"
end

#Configure the yelp client provided that we have a yelp config to try
if config.has_key?("yelp")
  Yelp.configure(:yws_id => config["yelp"]["ywsid"],
                 :consumer_key => config["yelp"]["consumer_key"],
                 :consumer_secret => config["yelp"]["consumer_secret"],
                 :token => config["yelp"]["token"],
                 :token_secret => config["yelp"]["token_secret"])
else
  raise "Could not find yelp configuration"
end

#create a configured db client
# if for some reason the db fails during initialisation we don't want to just die
# the logging for now is a nice to have so we can fall back to not having it.
logging = 1
begin  
  dbclient = Mysql2::Client.new(:host => config["database"]["host"],
                              :username => config["database"]["user"],
                              :password => config["database"]["passwd"],
                              :database => config["database"]["dbname"]
                             )
rescue 
  logging = 0
end

#two simple methods to convert from radians into degrees and vice versa
def to_radians(n)
  r = n * (Math::PI / 180)
  return r
end
def to_degrees(n)
  d = n * (180 / Math::PI)
  return d
end

#Method to take in array of addresses (input_addresses) and transform them into
#an array of coordinates in radian format, so that they can be used to find the midpoint later.
#An input_address array containing
# input_addresses =  ["co43sq", "ec1v4ex"]
# would then become the addresses array containing:
# addresses = [[0.9054167399564751, 0.016493853614195475], [0.8993943033488851, -0.0018665476045330916]]
# Again this will log to databases along the way so as to enable debugging of any problems and 
# enable the results to be used to improve future requests.
def map_addresses(dbclient,eventid,logging,input_addresses)
  addresses = input_addresses.map do |a| 
    if (logging == 1 )
      addressid = log_addresses(dbclient,eventid,a)
      if (addressid == "NO_DB")
        logging = 0
      end
    end
    begin
      result = Geokit::Geocoders::GoogleGeocoder.geocode(a)
    rescue
      raise error "GeoError: Either there is a problem reaching Google maps or the input is invalid #{a}"
    end
    if ((result.lat).kind_of? Float ) && ((result.lng).kind_of? Float)
     if (logging == 1 ) 
       addresscoordid = log_address_coordinates(dbclient,addressid,[to_radians(result.lat),to_radians(result.lng)])
       if (addresscoordid == "NO_DB")
         logging = 0
       end
     end
     [to_radians(result.lat), to_radians(result.lng)]
    else
      raise error "Validation Error: #{a} is not a valid address input."
    end
  end 
  return addresses
end

# Find the midpoint between two coordinates.
# addr1 and addr2 are arrays in the format of [latitude,longitude], as that seems to be the normal convention.
# this is actually finding the midpoint of the great circle that addr1 and addr2 live on.
# my maths was rusty, as its 14 years since I quit my UG degree, so I was prompted by
# http://mathforum.org/library/drmath/view/51822.html
# to help with the formula.
# it requires coordinates to be expressed in radians.
def find_midpoint(addr1,addr2)
  dlong = addr2[1] - addr1[1]
  bx = Math.cos(addr2[0]) * Math.cos(dlong)
  by = Math.cos(addr2[0]) * Math.sin(dlong)
  latmid = Math.atan2((Math.sin(addr1[0]) + Math.sin(addr2[0])), Math.sqrt(( Math.cos(addr1[0])+bx)**2 + by**2))
  longmid = addr1[1] + Math.atan2(by, Math.cos(addr1[0]) + bx)
  return [latmid, longmid]
end

# With N number of coordinates we want to be able to loop through them to get down to a final set of coordinates for midpoints
# the method below will take a set of coordinates in the form of an array, find the midpoints between the pairs.
# The effect is the array length returned is one shorter than the array length inputted.
def loop_midpoints(addr)
  midpoints = []
  0.upto(addr.length - 2 ) do | index|
    addr1 = addr[index]
    addr2 = addr[index + 1]
    midpoints << find_midpoint(addr1,addr2)
  end
  return midpoints
end

# Sometimes just searching for the inputted string will not return the answers we want, so it becomes necessary to refine the string
# Long term this will probably be enhanced to use the category list from yelp as a basis:
# http://www.yelp.co.uk/developers/documentation/category_list
#That said Yelp's category filter seems a little unreliable in testing, so a TBD to improve upon that.
#I've found in testing that sometimes searching or what you think is a simple enough request (e.g. french restaurant in paris, or thai restauraunt
#in rome, that you can end up getting unpredictable results
#For example with category "restaurants" or "restaurants,french" that you would get back quite useless results e.g. 
#/lookup?address[]=75011,Paris&address[]=75004,Paris&type=french would return
# a link to the Place Des Voges park.
# By experimenting it has been discovered that overriding this with the string "french restaurant" as the term delivers the correct result.
# similarly searching for "thai" in rome, returns by default a massage palour. Augumenting thestring with restaurant again helps here.
def refine_food(food)  
  case food["type"]
  when /thai/i
    food["category"] << "thai"
    food["type"] = "thai restaurant"
  when /indian|curry/i
    food["category"] << "indpak"
  when /french|france/i
    food["category"] << "french"
    food["type"] ="french restaurant"
  when /ital(ian|y)/i
    food["category"] << "italian"
    food["type"] = "italian restaurant"
   when /fish|seafood/i
    if (food["type"] =~ /chips/i)
      then food["category"] << "fishnchips"
      else
        food["category"] << "seafood"
        food["type"] = "fish restaurant"
    end
  end
  return food
end

#A number of simple methods to log various steps along the way to a database.
#Right now I have 5 tables:
#events (eventid INT AUTO_INCREMENT,request_time TIMESTAMP, foodtype VARCHAR(256))
#addresses (addressid INT AUTO_INCREMENT, eventid INT,address VARCHAR(256))
#address_coordinates (addresscoordid INT AUTO_INCREMENT,addressid INT ,coordinates VARCHAR(100))
#midpoints (midpointid INT AUTO_INCREMENT, eventid INT, coordinates VARCHAR(100))
#results (resultid INT AUTO_INCREMENT, eventid INT, result_name VARCHAR(100), result_address VARCHAR(256))
#In terms of the naming of the methods for each request we have:
#  1 event
#  multiple addresses
#  multiple address coordinates
#  1 final midpoint
#  1 result
# That has determined how I named these methods.
def log_event(dbclient,food)
  dbclient.query("insert into events(foodtype) values (\'#{food['type']}\')")
  eventid = dbclient.last_id
  return eventid
rescue
  eventid = 'NO_DB'
  return eventid
end
def log_addresses(dbclient,eventid,address)
  dbclient.query("insert into addresses(eventid,address) values(#{eventid},\'#{address}\')")
  addressid = dbclient.last_id
  return addressid
rescue
  addressid = 'NO_DB'
  return addressid
end
def log_address_coordinates(dbclient,addressid,coordinates)
  dbclient.query("insert into address_coordinates (addressid,coordinates) values(#{addressid},\'#{coordinates}\')")
  addresscoordid = dbclient.last_id
  return addresscoordid
rescue
  addresscoordid = 'NO_DB'
  return addresscoordid
end
def log_midpoint(dbclient,eventid,coordinates)
  dbclient.query("insert into midpoints (eventid,coordinates) values(#{eventid},\'#{coordinates}\')")
  midpointid = dbclient.last_id
  return midpointid
rescue
  midpointid = 'NO_DB'
  return midpointid
end
def log_result(dbclient,eventid,results)
  dbclient.query("insert into results (eventid,result_name,result_address) value (#{eventid},\'#{results['name']}\',\'#{results['location']['display_address']}\')")
  resultid = dbclient.last_id
  return resultid
rescue
  resultid = 'NO_DB'
  return resultid
end

error { @error = request.env['sinatra_error'] ; haml :'500' }

#example URL:
#http://localhost:4567/lookup?address[]=ec1v4ex&address[]=co43sq&address[]=wc1b5ha&type=thai#env-info
get '/lookup' do
  content_type :json
 
  #if food type is specified, then use it, otherwise, set the term to restaurant and rely on yelp
  #make a good choice!
  #Try to improve the search terms by referencing the refine_food method which has tweaks for various search terms
  #which have shown in testing to not work as expected.
  food = Hash.new
  food["category"] = "[restaurants]"
  if params.has_key?("type")
    food["type"] = params.fetch("type")
    food = refine_food(food)
  else
    food["type"] = "restaurant"
  end

  if (logging == 1 )
    eventid = log_event(dbclient,food)
    if (eventid == "NO_DB")
      logging = 0
    end
  end
  #create an array containing all the addresses inputted
  #n.b. when making a query manually you need to pass parameters in the form of:
  #address[]=ec1v4ex&address[]=co43sq .. because otherwise sinatra creates a string named address
  #rather than an array
  if params.has_key?("address")
    input_addresses = params.fetch("address")
  else
    raise error "Input Error: no addresses inputted"
  end
  
  # if we don't have at least two addresses, we should fail, as how can we find a midpoint with only one place.
  if input_addresses.length < 2
    raise error "Input Error: not enough addresses entered. Only #{input_addresses.length} addresses entered. At least 2 are required"
  end

  # Create an addresses array from the input_addresses array by converting the postcodes or addresses into coordinates in the form of radians.
  # we call the map_addresses method defined above to do this.
  addresses = map_addresses(dbclient,eventid,logging,input_addresses)
  # manipulate the addresses array again, this time to get the coordinates sorted.
  addresses.sort!
  
  # create the midpoints array based on an initial looping through the addresses array to find the midpoints there 
  # midpoints is a nested array like addresses became above.
  midpoints = loop_midpoints(addresses)

  # if the length of the midpoint array is already 1, due to only 2 addresses being passed the below will be skipped
  # Otherwise keep iterating through the midpoints, until there is 1.
  # Again we want to log the output from this to help in debugging in the event of strange results
  while midpoints.length > 1 do
    addr = midpoints.sort!
    midpoints = loop_midpoints(addr)
  end
  if (logging == 1 )
    midpointid = log_midpoint(dbclient,eventid,midpoints[0])
    if (midpointid == "NO_DB")
      logging = 0 
    end
  end   

  # call out to Yelp using the yelpster gem to find a restaurant of the right type close to our midpoint
  # we call midpoints[0] because that's the first (and only remaining) element int he midpoint array
  # and pass the lat and long in accordingly.
  # we specify limit of 1, as we just want the first returned restaurant for now
  # we specify sort type of 1 which is to find the closest (recommended) one to our location
  # This because we specify a wide search radius to deal with cases where the midpoint may be a little away
  # from the nearest civilization!
  # This is wrapped into a begin/rescue statement, to cope with cases where the YELP API is unavailable
  client = Yelp::Client.new
  begin
    request = Yelp::V2::Search::Request::GeoPoint.new(
              :term => food["type"],
              :latitude => to_degrees(midpoints[0][0]),
              :longitude => to_degrees(midpoints[0][1]),
              :limit => 1,
              :radius =>40000,
              :sort => 1,
              :category => food["category"]
               )
  response = client.search(request)
  rescue
    raise error "YelpError: YELP API is unavailable right now."
  end

  #finally we output the search results if we have the,
  #For now we are just outputting the yelp json verbatim as it contains all the useful information
  #We catch the case if the search doesn't return any result.
  #Again we log the put from this, so we can analyze it later.
  if response.has_key?('businesses')
    if (logging == 1)
      responseid = log_result(dbclient,eventid,response['businesses'][0])
      if (responseid == "NO_DB")
        logging = 0
      end
    end
    "#{response.fetch('businesses')[0]}"
  else
    raise error "Search Error: No results found near your midpoint which was determined to be #{to_degrees(midpoints[0][0])}, #{to_degrees(midpoints[0][1])}"
  end
end
