require 'httparty'
require 'json'
require 'hashie'

module PDBot
  class PDClient
    attr_reader :client

    def initialize(subdomain, token)
      @token = token
      @client = Module.new do
        include HTTParty
        format :json
        base_uri "https://#{subdomain}.pagerduty.com/api/v1"
      end
    end

    def http(method, urlpart, args = {})
      urlpart = URI.encode "/" + urlpart.to_s
      if method == :get
        bodyorquery = :query
      else
        bodyorquery = :body
        args = args.to_json
      end
      r = client.__send__(
        method.to_s,
        urlpart,
        {
          :headers => {
            'Content-Type' => 'application/json',
            'Authorization' => "Token token=#{@token}"
          },
          bodyorquery => args
        }
      )
      raise "Something really wrong happened" if r.code == 500
      ret = Hashie::Mash.new convert_data_to_object(r)
      error = ret.error || ret.errors
      if error
        warn error.inspect
        raise "Bad request"
      end
      ret
    end

    def convert_data_to_object(r)
      begin
        return do_convert_data_to_object(r)
      rescue Exception => e
        warn "ERROR: The body was #{r.body.inspect}"
        raise e
      end
    end

    def do_convert_data_to_object(r)
      return {} if r.body.nil?
      JSON.parse r.body
    end

    def get(urlpart, args = {})
      http :get, urlpart, args
    end

    def post(urlpart, args = {})
      http :post, urlpart, args
    end

    def delete(urlpart)
      http :delete, urlpart
    end

    def put(urlpart, args = {})
      http :put, urlpart, args
    end

    PAGINATION_SIZE = 100
    # The sugar on top
    def services
      ret = []
      offset = 0
      loop do
        cur = get("services?limit=#{PAGINATION_SIZE}&offset=#{offset}")
        offset += PAGINATION_SIZE
        ret.push *cur.services
        break if offset >= cur.total
      end
      ret
    end

    def schedules
      ret = []
      offset = 0
      loop do
        cur = get("schedules?limit=#{PAGINATION_SIZE}&offset=#{offset}")
        offset += PAGINATION_SIZE
        ret.push *cur.schedules
        break if offset >= cur.total
      end
      ret
    end

    def on_call_all
      ret = Hash.new
      s = schedules
      s.each do |sch|
        oc = on_call_now(sch.id)
        ret[sch['name']] = {:name => oc['user']['name'], :until => Time.parse(oc['end'])}
      end
      ret
    end

    def on_call_by_schedule_name(schedule_name)
      sch = schedules
      i = sch.find_index { |s| s['name'] == schedule_name }
      on_call_now_next(sch[i]['id'])
    end

    def on_call_now_next(schedule_id)
      ret = Hash.new
      now = Time.now
      future = now + 2592000
      res = get("schedules/#{schedule_id}/entries", :since => now.iso8601, :until => future.iso8601)
      return nil if res.total < 2
      oncallnow = res['entries'][0]
      oncallnext = res['entries'][1]
      [
        {
          :name  => oncallnow['user']['name'],
          :id    => oncallnow['user']['id'],
          :until => Time.parse(oncallnow['end'])
        },
        {
          :name  => oncallnext['user']['name'],
          :id    => oncallnext['user']['id'],
          :until => Time.parse(oncallnext['end'])
        },
      ]
    end

    def create_maintenance_window(services, opts)
      opts[:service_ids] = services.map(&:id)
      post(:maintenance_windows, :maintenance_window => opts)
    end

  end
end
