class Eye::Trigger::StartingGuard < Eye::Trigger

  # check that process ready to start or not
  # by custom user condition
  # if not, process switched to :unmonitored, and then retry to start after :every interval
  #
  # trigger :starting_guard, every: 10.seconds, should: ->{ `cat /tmp/bla` == "bla" }

  param :every, [Float, Fixnum], false, 10
  param :times, [Fixnum]
  param :retry_in, [Float, Fixnum]
  param :retry_times, [Fixnum]
  param :should, [Proc, Symbol]

  def initialize(*args)
    super

    @retry_count = 0
    @reretry_count = 0
  end

  def check(transition)
    check_start if transition.to_name == :starting
  end

  def check_start
    @retry_count += 1
    condition = defer { exec_proc(:should) }

    if condition
      info "ok, process ready to start #{condition.inspect}"
      @retry_count = 0
      @reretry_count = 0
      return
    else
      info "false executed condition"
    end

    new_time = nil
    if every
      if times
        if (@retry_count < times)
          new_time = Time.now + every
          process.schedule_in every, :conditional_start, Eye::Reason::StartingGuard.new("starting_guard, retry start")
        else
          @retry_count = 0
          @reretry_count += 1
          if retry_in && (!retry_times || (@reretry_count < retry_times))
            new_time = Time.now + retry_in
            process.schedule_in retry_in, :conditional_start, Eye::Reason::StartingGuard.new("starting_guard, reretry start")
          end
        end
      else
        new_time = Time.now + every
        process.schedule_in every, :conditional_start, Eye::Reason::StartingGuard.new("starting_guard, retry start")
      end
    end

    retry_msg = new_time ? ", retry at '#{Eye::Utils.human_time2(new_time.to_i)}'" : ''
    process.switch :unmonitoring, Eye::Reason::StartingGuard.new("starting_guard, failed condition#{retry_msg}")

    raise Eye::Process::StateError.new("starting_guard, refused to start")
  end
end
