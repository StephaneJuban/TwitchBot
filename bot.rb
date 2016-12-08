require 'sinatra/base'
require 'slack-ruby-client'

# This class contains all of the webserver logic for processing incoming requests from Slack.
class API < Sinatra::Base
  # This is the endpoint Slack will post Event data to.
  post '/events' do
    # Extract the Event payload from the request and parse the JSON
    request_data = JSON.parse(request.body.read)
    # Check the verification token provided with the requat to make sure it matches the verification token in
    # your app's setting to confirm that the request came from Slack.
    unless SLACK_CONFIG[:slack_verification_token] == request_data['token']
      halt 403, "Invalid Slack verification token received: #{request_data['token']}"
    end

    case request_data['type']
      # When you enter your Events webhook URL into your app's Event Subscription settings, Slack verifies the
      # URL's authenticity by sending a challenge token to your endpoint, expecting your app to echo it back.
      # More info: https://api.slack.com/events/url_verification
      when 'url_verification'
        request_data['challenge']

      when 'event_callback'
        # Get the Team ID and Event data from the request object
        team_id = request_data['team_id']
        event_data = request_data['event']

        # Events have a "type" attribute included in their payload, allowing you to handle different
        # Event payloads as needed.
        case event_data['type']
          when 'team_join'
            # Event handler for when a user joins a team
            Events.user_join(team_id, event_data)
          when 'reaction_added'
            # Event handler for when a user reacts to a message or item
            Events.reaction_added(team_id, event_data)
          when 'pin_added'
            # Event handler for when a user pins a message
            Events.pin_added(team_id, event_data)
          when 'message'
            # Event handler for messages, including Share Message actions
            Events.message(team_id, event_data)
          else
            # In the event we receive an event we didn't expect, we'll log it and move on.
            puts "Unexpected event:\n"
            puts JSON.pretty_generate(request_data)
        end
        # Return HTTP status code 200 so Slack knows we've received the Event
        status 200
    end
  end
end



# This class contains all of the Event handling logic.
class Events
  # You may notice that user and channel IDs may be found in
  # different places depending on the type of event we're receiving.

  # A new user joins the team
  def self.user_join(team_id, event_data)
    user_id = event_data['user']['id']
    # Send the user our welcome message, with the tutorial JSON attached
    self.send_response(team_id, user_id, "#general", "WELCOME !")
  end

  def self.message(team_id, event_data)
    user_id = event_data['user']
    # Don't process messages sent from our bot user
    unless user_id == $teams[team_id][:bot_user_id]

      case event_data['text']
      when "Does Twoeasy is live ?"
        stream_infos = self.check_twitch("twoeasy")
        if stream_infos
          name = stream_infos["channel"]["display_name"]
          game = stream_infos["game"]
          viewers = stream_infos["viewers"]
          stream_url = stream_infos["channel"]["url"]
          message = "YES ! #{name} is live streaming #{game} with #{viewers} viewers !!! GOGOGO : #{stream_url}"
        else
          message = "Unfortunately no, the stream is offline :'("
        end
        self.send_response(team_id, user_id, "#general", message)
      end

    end
  end

  # Send a response to an Event via the Web API.
  def self.send_response(team_id, user_id, channel = user_id, message = "I don'k know :)")
    # `ts` is optional, depending on whether we're sending the initial
    # welcome message or updating the existing welcome message tutorial items.
    # We open a new DM with `chat.postMessage` and update an existing DM with
    # `chat.update`.
    $teams[team_id]['client'].chat_postMessage(
        as_user: 'true',
        channel: channel,
        text: message
    )
  end


  # Check if a twitch channel is live
  def self.check_twitch(channel = "twoeasy")
    # curl -H 'Accept: application/vnd.twitchtv.v3+json' -H 'Client-ID: ENV["TWITCH_CLIENT_ID"]' -X GET https://api.twitch.tv/kraken/streams/twoeasy
    uri = URI("https://api.twitch.tv/kraken/streams/#{channel}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    headers = {
      'Accept' => "application/vnd.twitchtv.v3+json",
      'Client-ID' => ENV["TWITCH_CLIENT_ID"]
    }
    resp = http.get(uri.path, headers)
    json = JSON.parse(resp.body)

    return json["stream"]
  end

end