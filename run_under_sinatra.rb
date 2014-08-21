require 'sinatra'
require 'cgi'
require 'json'
require 'uri'
require 'yaml'
require 'redcarpet'
require './foodfinder.rb'
require './dblogger.rb'

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
# zulip:
#   username: ""
#   apikey: ""
#
begin
  approot = File.expand_path(File.dirname(__FILE__))
  rawconfig = File.read(approot + "/config.yml")
  config = YAML.load(rawconfig)
rescue
  raise "Could not load or parse configuration file, unable to continue"
end

#Configure the yelp client provided that we have a yelp config to try
if config.has_key?("yelp")
  food_finder = FoodFinder.new(config["yelp"])
else
  raise "Could not find yelp configuration"
end

if config.has_key?("database")
  logger = DBLogger.new(config["database"])
end

markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML, autolink: true, tables: true)
error { @error = request.env['sinatra_error'] ; haml :'500' }

#example URL:
#http://localhost:4567/lookup?address[]=ec1v4ex&address[]=co43sq&address[]=wc1b5ha&type=thai#env-info
get '/lookup' do
 
  #if food type is specified, then use it, otherwise, set the term to restaurant and rely on yelp
  #make a good choice!
  #Try to improve the search terms by referencing the refine_food method which has tweaks for various search terms
  #which have shown in testing to not work as expected.
  if params.has_key?("type")
    content = params.fetch("type")
  else
    content = "restaurant"
  end

  if params.has_key?("address")
      params.fetch("address").each { |address|
          #strip any commas from address
          address = address.tr(',',' ')
          content = [content,address].join(",")
      }
  else
    raise error "Input Error: no addresses inputted"
  end

  response = food_finder.lookup(content, logger) 
  html_response = markdown.render(response)
  return html_response
end
