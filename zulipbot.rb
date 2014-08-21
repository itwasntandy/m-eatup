require 'net/http'
require 'json'
require 'mysql2'
require './foodfinder.rb'
require './dblogger.rb'

class ZulipBot
	def initialize(email, api_key)
		@email = email
		@api_key = api_key
		@queue_id = nil
		@last_event_id = nil
		@current_events = nil
	end

	def send_stream_msg(stream, subject, message)
		uri = URI('https://api.zulip.com/v1/messages')
		req = Net::HTTP::Post.new(uri)
		req.set_form_data(
					'type' => 'stream',
					'to' => stream,
					'subject' => subject,
					'content' => message
					)
		req.basic_auth(@email, @api_key)

		res = Net::HTTP.start(uri.hostname, uri.port, :use_ssl => uri.scheme == 'https')  {|http|
			http.request(req)
		}
	end

	def send_pm(recipient, message)
		uri = URI('https://api.zulip.com/v1/messages')
		req = Net::HTTP::Post.new(uri)
		req.set_form_data(
			'type' => 'private',
			'to' => recipient,
			'content' => message
			)
		req.basic_auth(@email, @api_key)
		res = Net::HTTP.start(uri.hostname, uri.port, :use_ssl => uri.scheme == 'https')  {|http|
			http.request(req)
		}
	end

	#create a queue to watch for events of a specified type
	def register(event_type)
		uri = URI("https://api.zulip.com/v1/register")
		req = Net::HTTP::Post.new(uri)
        #form_data = (:event_types => event_type, :apply_markdown => :true)
		req.set_form_data('event_types' => event_type, 'apply_markdown' => 'true')
		#req.set_form_data(form_data)
        #req.set_form_data('apply_markdown' => true)
		req.basic_auth(@email, @api_key)
		res = Net::HTTP.start(uri.hostname, uri.port, :use_ssl => uri.scheme == 'https')  {|http|
			http.request(req)
		}
		@queue_id = JSON.parse(res.body)["queue_id"]
		@last_event_id = JSON.parse(res.body)["last_event_id"]
	end

	#get new events out of the queue
	def get_events(regex, food_finder, logger)
		uri = URI("https://api.zulip.com/v1/events")
		params = {last_event_id: @last_event_id, queue_id: @queue_id}
		uri.query = URI.encode_www_form(params)
		req = Net::HTTP::Get.new(uri)
		req.basic_auth(@email, @api_key)
		res = Net::HTTP.start(uri.hostname, uri.port, :use_ssl => uri.scheme == 'https')  {|http|
			http.request(req)
		}
		@current_events = JSON.parse(res.body)
		unless @current_events["events"].nil?
            # we don't care much about heartbeats, so shouldn't try to parse them
            unless @current_events["events"][0]["type"] == 'heartbeat'
                extract_message(@current_events, regex, food_finder, logger)
            end
		end
	end

	#check events' content for regex matches
	def extract_message(events_hash, regex, food_finder, logger)
		events_hash["events"].each do |event|
            if event["message"]["type"] == "private"
                subject = event["message"]["subject"]
                content = event["message"]["content"]
                # don't want to search for our bot's name
                #content = content.sub(/^\@\*\*YelpFoodFinder\*\*\ /, '')
                content = content.sub(/^<p><span class="user-mention" data-user-email="yelpfoodfinder-bot@students.hackerschool.com">@YelpFoodFinder<\/span>\ /, '')
                content = content.sub(/<\/p>$/, '')
                message = food_finder.lookup(content, logger)
                self.send_pm(event["message"]["sender_email"], message)
			elsif event["message"]["content"].downcase.match(regex)
				stream = event["message"]["display_recipient"]
				subject = event["message"]["subject"]
                content = event["message"]["content"]
                content = content.sub(/^<p><span class="user-mention" data-user-email="yelpfoodfinder-bot@students.hackerschool.com">@YelpFoodFinder<\/span>\ /, '')
                content = content.sub(/<\/p>$/, '')
				message = food_finder.lookup(content, logger)
                self.send_stream_msg(stream, subject, message)
           	end
			@last_event_id = event["message"]["id"] + 1
		end
	end
end

begin
    approot = File.expand_path(File.dirname(__FILE__))
    rawconfig = File.read(approot + "/config.yml")
    config = YAML.load(rawconfig)
rescue
    raise "Could not load or parse configuration file, unable to continue"
end

if config.has_key?("yelp")
  food_finder = FoodFinder.new(config["yelp"])
else
  raise "Could not find yelp configuration"
end

if config.has_key?("zulip")
    food_bot = ZulipBot.new(config["zulip"]["username"], config["zulip"]["apikey"])
    food_bot.register(JSON.unparse(['message']))
else
  raise "could not find zulip config"
end

if config.has_key?("database")
    logger = DBLogger.new(config["database"])
end


loop do
    food_bot.get_events(/yelpfoodfinder/, food_finder, logger)
end

