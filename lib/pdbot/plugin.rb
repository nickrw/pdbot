require 'pdbot/pdclient'

class PDBot::Plugin

  include Cinch::Plugin

  match "oncall", :method => :oncall
  listen_to :pdpoll, :method => :poll
  listen_to :pdhandover, :method => :handover

  def initialize(*args)
    super

    [
      "pd_subdomain",
      "pd_api_key",
      "pd_schedule_name"
    ].each do |need|
      require_config(need)
    end

    @client = PDBot::PDClient.new(
      config["pd_subdomain"],
      config["pd_api_key"]
    )
    @oc = nil
    @timers = []
    @pdpoll = nil
    @errorcount = 0
    @announce = config["announce_channel"]
    @pollinterval = config["poll_interval"] || 900
    @nickmap = config["nickmap"] || Hash.new
    debug "Dispatching first poll"
    bot.handlers.dispatch(:pdpoll)
    @pdpoll = Timer(@pollinterval, {:start_automatically => false, :stop_automatically => false}) do
      bot.handlers.dispatch(:pdpoll)
    end

  end

  def poll(m, *args)
    synchronize(:pdpoll) do

      debug "Polling pagerduty API"
      oc = @client.on_call_by_schedule_name(config["pd_schedule_name"])

      if oc.nil?

        # The PDClient call returned nil, meaning it did not extract enough
        # useful components from the API call.
        warn "PDClient call #on_call_by_schedule_name returned nil"
        @errorcount += 1

        if @errorcount >= 10 && @errorcount < 12
          announce "Unable to retrieve a satisfactory response from the PagerDuty API after #{@errorcount} attempts (#{pollinterval}s interval)."
          return
        end

        if @errorcount >= 12
          announce "PagerDuty API still failing after 12 attempts. Shutting myself down."
          selfdestruct "PagerDuty API failed the last 12 attempts. Unloading PDBot::Plugin from Cinch.", RuntimeError
        end

      end

      if @errorcount >= 6
        # The API was recently not responding, but it has recovered
        debug "PagerDuty API is responding normally again."
      end
      @errorcount = 0

      # Don't process anything if the API call yielded the same result as
      # the last time it was polled.
      debug "oc: #{oc.inspect}"
      debug "@oc: #{@oc.inspect}"
      return if compare_oc_array(oc, @oc)

      oc[0][:name] = ircname oc[0][:name]
      oc[1][:name] = ircname oc[1][:name]
      @oc = oc
      debug "Replaced @oc with new poll Array"

      # Don't bother dealing with announcement timers if we don't have
      # an announcement channel configured.
      return if @announce.nil?

      debug "Cancelling existing handover timers..."
      cancel_timers

      debug "Scheduling new handover timer..."
      # Schedule a new timer to fire the handover channel message
      timer_opts = {:shots => 1, :start_automatically => false}
      secs_to_handover = (@oc[0][:until] - Time.now).to_i
      @timers << Timer(secs_to_handover, timer_opts) do
        debug "Dispatching :pdhandover to trigger handover message"
        bot.handlers.dispatch(:pdhandover, nil, oc)
        cancel_timers
      end

    end
  end

  def oncall(m)
    if @oc.nil?
      m.reply "Unable to determine who is on-call from the PagerDuty API."
    end
    nick = @oc[0][:name]
    untiltime = human_datetime(@oc[0][:until])
    if @oc.count > 1
      handover = "(hands over to #{@oc[1][:name]})"
    end
    m.reply "%s is on-call until %s %s" % [nick, untiltime, handover]
  end

  def handover(m, oc)
    offcall = oc[0][:name]
    oncall = oc[1][:name]
    untiltime = human_datetime(oc[1][:until])
    @oc = [oc[1]]
    debug "Replaced @oc with short handover array"
    return if config["announce_channel"].nil?
    ch = Channel(config["announce_channel"])
    ch.send "On-call shift handover: %s -> %s" % [offcall, oncall]
    ch.send "%s is on-call until %s" % [oncall, untiltime]
  end

  private

  def same_date?(t1,t2)
    Date.new(t1.year, t1.month, t1.day) === Date.new(t2.year, t2.month, t2.day)
  end

  def human_datetime(time)
    strfstring = same_date?(time,Time.now) ? "%R today" : "%R on %A (%F)"
    return time.strftime(strfstring)
  end

  def cancel_timers
    timers = @timers.dup
    timers.each do |t|
      @timers.delete(t)
      next if t.stopped?
      next if t == @pdpoll
      t.stop
    end
  end

  def compare_oc_array(oc1, oc2)
    return true if oc1 == oc2
    return false if oc1.class != oc2.class
    return false if oc1.class != Array
    return false if oc1.count != oc2.count
    (0..(oc1.count - 1)).each do |i|
      return false if oc1[i][:id] != oc2[i][:id]
      return false if oc1[i][:until] != oc2[i][:until]
    end
    return true
  end

  def ircname(name)
    nick = @nickmap[name]
    nick ||= name
  end

  def selfdestruct(message=nil, exclass=ArgumentError)
    bot.plugins.unregister_plugin(self)
    return if message.nil?
    raise exclass, message
  end

  def announce(message)
    return if @announce.nil?
    ch = Channel(@announce)
    ch.send message
  end

  def require_config(itemname)
    if config[itemname].nil?
      selfdestruct "Missing non-optional config item #{itemname}"
    end
  end

end
