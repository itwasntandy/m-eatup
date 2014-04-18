#This is a simple app to try to find the best place for a group of friends to meet up and eat.
#it'll take input in the form of a bunch of address[] parameters in a uri query string and 
#food type via the optional foodtype parameter.
#
#In the future it should deal with edge cases better - eg. the midpoint between london and paris is over the sea, so there is no restaurant close to the midpoint.
#
#Also in the future it would be good to hook up to a routing API, as the geographic midpoint may in some cases take longer to get to then going from point A to point B.
#and this will allow people to specify method of travel too.
#i.e. Andrew is happy to go by foot, car or public transport
#Will is happy to go by foot, bicyle or public transport
#Harry is happy to go by public transport, and walk no more than 10 minutes
#
#
#longer term it will enable someone to create an event, and have people "sign up" to that event with the dates they can make and their addresses
#and this will be used to schedule events, sending out directions to each person, and reminders prior to the event.
#
#Once all that is done, being able to hook up to the OpenTable API to book a table on the scheduled date for everyone who can make it, at the appropriate restaurant
#would be the icing on the cake.
#



require 'sinatra'
require 'cgi'
require 'json'
require 'geokit'
require 'yelpster'
require 'uri'
require 'mysql2'
require 'yaml'

#Decided it would be a good idea to move the config variabels out of the main app
#so this is done throug reading a yaml file and creating a hash of hashes for this.
#
#Currently it needs the config file to be named config.yml and for it to be in the same
#directory as the running app.
#
#The config file needs to contain credentials for all the remote services used.
#
#You can sign up for a YELP developer account here: http://www.yelp.com/developers
#you can sign up for a MySQL db (from the free tier) with AWS: http://aws.amazon.com/rds/
#
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

approot = File.expand_path(File.dirname(__FILE__))
rawconfig = File.read(approot + "/config.yml")
config = YAML.load(rawconfig)


client = Mysql2::Client.new(:host => config["database"]["host"],
                            :username => config["database"]["user"],
                            :password => config["database"]["passwd"],
                            :database => config["database"]["dbname"]
                           )

 
Yelp.configure(:yws_id => config["yelp"]["ywsid"],
               :consumer_key => config["yelp"]["consumer_key"],
               :consumer_secret => config["yelp"]["consumer_secret"],
               :token => config["yelp"]["token"],
               :token_secret => config["yelp"]["token_secret"])


#two simple methods to convert from radians into degrees and vice versa

def to_radians(n)
  r = n * (Math::PI / 180)
  return r
end
  
def to_degrees(n)
  d = n * (180 / Math::PI)
  return d
end

def find_midpoint(addr1,addr2)
  # addr1 and addr2 are arrays in the format of [latitude,longitude], as that seems to be the normal convention.
  # this is actually finding the midpoint of the great circle that addr1 and addr2 live on.
  # my maths was rusty, as its 14 years since I quit my UG degree, so I was prompted by
  # http://mathforum.org/library/drmath/view/51822.html
  # to help with the formula.
  # it requires coordinates to be expressed in radians.

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
# although that said the yelp category filter doesn't appear to be too reliable.

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
  when /italian|italy|italia/i
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





error { @error = request.env['sinatra_error'] ; haml :'500' }

#example URL:
#http://localhost:4567/lookup?address[]=ec1v4ex&address[]=co43sq&address[]=wc1b5ha&type=thai#env-info

get '/lookup' do
  content_type :json
  
  #create an array containing all the addresses inputted
  #n.b. when making a query manually you need to pass parameters in the form of:
  #address[]=ec1v4ex&address[]=co43sq .. because otherwise sinatra creates a string named address
  #rather than an array

  if params.has_key?("address")
    addresses = params.fetch("address")
  else
    raise error "Input Error: no addresses inputted"
  end
  
  # if we don't have at least two addresses, we should fail, as how can we find a midpoint with only one place.
  if addresses.length < 2
    raise error "Input Error: not enough addresses entered. Only #{addresses.length} addresses entered. At least 2 are required"
  end

  # manipulate the addresses array, to convert the postcodes or addresses into coordinates in the form of radians.
  # previously it might have  been:
  # addresses =  ["co43sq", "ec1v4ex"]
  #
  # afterwards it takes the form of a nested array expressed in the form of lat,long
  #
  # addresses = [[0.9054167399564751, 0.016493853614195475], [0.8993943033488851, -0.0018665476045330916]]
  addresses.map! do |a| 
    result = Geokit::Geocoders::GoogleGeocoder.geocode(a)
    if ((result.lat).kind_of? Float ) && ((result.lng).kind_of? Float)
       [to_radians(result.lat), to_radians(result.lng)]
    else
      raise error "Validation Error: #{a} is not a valid address input.".to_json
    end
  end 

  # manipulate the addresses array again, this time to get the coordinates sorted.
  addresses.sort!
  
  # create the midpoints array based on an initial looping through the addresses array to find the midpoints there 
  # midpoints is a nested array like addresses became above.
  midpoints = loop_midpoints(addresses)

  # if the length of the midpoint array is already 1, due to only 2 addresses being passed the below will be skipped
  # Otherwise keep iterating through the midpoints, until there is 1.
  while midpoints.length > 1 do
    addr = midpoints.sort!
    midpoints = loop_midpoints(addr)
  end
 
  #if food type is specified, then use it, otherwise, set the term to restaurant and rely on yelp
  #make a good choice!
  #If food type is one of a popular type, then specify that as a filter, otherwise rely on yelp's search prowess.
  #we default to a food category of restaurants to try to avoid take away joints, and then augmnet it with further categories
  #if we detect a popular type.
  #That said Yelp's category filter seems a little unreliable in testing, so a TBD to improve upon that.
  #I've found in testing that sometimes searching or what you think is a simple enough request (e.g. french restaurant in paris, or thai restauraunt
  #in rome, that you can end up getting unpredictable results
  #For example with category "restaurants" or "restaurants,french" that you would get back quite useless results e.g. 
  #/lookup?address[]=75011,Paris&address[]=75004,Paris&type=french would return
  # a link to the Place Des Voges park.
  # By experimenting it has been discovered that overriding this with the string "french restaurant" as the term delivers the correct result.
  # similarly searching for "thai" in rome, returns by default a massage palour. Augumenting thestring with restaurant again helps here.
  food = Hash.new
  food["category"] = "[restaurants]"
  if params.has_key?("type")
    food["type"] = params.fetch("type")
    food = refine_food(food)
  else
    food["type"] = "restaurant"
  end

  # call out to Yelp using the yelpster gem to find a restaurant of the right type close to our midpoint
  # we call midpoints[0] because that's the first (and only remaining) element int he midpoint array
  # and pass the lat and long in accordingly.
  # we specify limit of 1, as we just want the first returned restaurant for now
  # we specify sort type of 1 which is to find the closest (recommended) one to our location
  # This because we specify a wide search radius to deal with cases where the midpoint may be a little away
  # from the nearest civilization!
  client = Yelp::Client.new
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
  #finally we output with some text.
  #this bit is still TBD, with some basic output given for debugging purposes
  #"the best restaurant to go to is #{response.fetch("businesses")[0].fetch("name")} and its address is #{response.fetch("businesses")[0].                 fetch("location").fetch("address")[0]}  #{response.fetch("businesses")[0].fetch("location").fetch("postal_code")}"
  if response.has_key?('businesses')
    "#{response.fetch('businesses')[0]}"
  else
    raise error "Search Error: No results found near your midpoint which was determined to be #{to_degrees(midpoints[0][0])}, #{to_degrees(midpoints[0][1])}"
  end

end
